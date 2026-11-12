--[[
	CombatController - the local player's attacks. Client only.

	Binds Attack (MouseButton1 / ButtonR2 / touch "ATTACK") and Aim (MouseButton2 / ButtonL2 / touch "AIM", shown only
	for the bow and the spear) through Shared.Input, and only while alive in the arena and not spectating, so lobby
	clicks and the third-person camera are untouched. Input is ignored while ClientState.menuOpen.
	  Melee: windup -> strike -> recover, timed from ItemDefs (windup, cooldown). At the strike moment MeleeSwing is
	    sent with the camera look vector. Holding Attack keeps swinging; a press just before a swing ends is buffered, and a press during an item switch is kept
    for the whole switch. Attacking while climbing or swimming answers with Feedback.deny.
	  Bow: hold Attack to draw (ClientState.drawAlpha over drawTime), release to shoot (RangedRelease "Fire") when
	    there are arrows; a very light draw is let down instead. Aim zooms (ClientState.aiming / aimAlpha) and
	    tightens the spread. The server is told when a draw starts and stops (RangedRelease "Draw" / "Cancel").
	    The arrow lands where the crosshair points: the release is lifted just enough that the arc (speed, gravity)
	    passes through the point under the crosshair (Config.Combat.BowAimOnTarget, BowZeroDistance).
	  Throwing knife: Attack throws. Spear: Attack stabs, Aim + Attack throws (RangedRelease "Throw").
	  Food, drink, healing and armor: Attack is forwarded to ClientState.useRequested(state) instead.
	Feedback: the strike is traced locally so impact sounds, sparks and camera kicks are instant; the server confirms
	with HitConfirm -> ClientState.hitConfirmed + HitMarker / HitMarkerKill. DamageTaken -> ClientState.damageTaken,
	a camera kick away from the attacker and the Hurt sound. Writes ClientState.crosshairSpread every frame.

	For ViewmodelController / ProjectileController:
	  CombatController.current -> the action in progress, or nil:
	    { kind = "Melee", itemId, style, weight, variant, t0, windup, strike, total, struck, hit }
	    { kind = "Draw", itemId, t0, drawTime }   { kind = "BowRecover", itemId, t0, total, charge }
	    { kind = "Throw", itemId, spear, t0, windup, total, released }
	    style: "Punch" | "Slash" | "Chop" | "Smash" | "Stab"; weight: "Light" | "Medium" | "Heavy"; times use os.clock()
	  CombatController.action: Signal(name, data)
	    "Swing" | "DrawStart" | "ThrowStart" (the new current record), "Strike" { itemId, style, weight, variant, hit },
	    "DrawCancel" { itemId }, "Release" { itemId, charge }, "ThrowRelease" { itemId, spear, last }
	  CombatController.equipBlockedUntil -> os.clock() time when the equip raise is done
	  CombatController.getEquipped() -> (itemId?, def)    CombatController.canAimWith(def) -> boolean
	  CombatController.countItem(itemId) -> number   items left, minus what we've spent since the last InventoryUpdate
	Optional hooks used when present: MovementController.spendStamina(amount) (melee staminaCost),
	MovementController.stopSprint() (drawing and throwing), ViewmodelController.getMuzzle() -> Vector3?,
	NotificationController.toast(text) ("No arrows").
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Input = require(Shared:WaitForChild("Input"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Signal = require(Shared:WaitForChild("Signal"))
local Util = require(Shared:WaitForChild("Util"))
local Feedback = require(Shared:WaitForChild("Feedback"))
local ActionHints = require(Shared:WaitForChild("ActionHints"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local GameState = ReplicatedStorage:WaitForChild("GameState")
local CombatConfig = Config.Combat

local CombatController = {}
CombatController.action = Signal.new()
CombatController.current = nil :: { [string]: any }?
CombatController.equipBlockedUntil = 0

local Controllers: { [string]: any } = {}
local MeleeSwing: RemoteEvent? = nil
local RangedRelease: RemoteEvent? = nil

local FISTS = ItemDefs.get("fists")

-- How each melee weapon looks and feels (the numbers that matter for balance live in ItemDefs).
local MELEE_STYLE: { [string]: { style: string, weight: string, strike: number } } = {
	fists = { style = "Punch", weight = "Light", strike = 0.08 },
	knife = { style = "Slash", weight = "Light", strike = 0.08 },
	machete = { style = "Slash", weight = "Medium", strike = 0.1 },
	sword = { style = "Slash", weight = "Medium", strike = 0.1 },
	hatchet = { style = "Chop", weight = "Medium", strike = 0.1 },
	spear = { style = "Stab", weight = "Medium", strike = 0.1 },
	mace = { style = "Smash", weight = "Heavy", strike = 0.13 },
}
local DEFAULT_STYLE = { style = "Slash", weight = "Medium", strike = 0.1 }

-- Camera kicks per swing style (pitch, yaw, roll in radians; yaw/roll flip with the swing direction).
local KICK: { [string]: Vector3 } = {
	Punch = Vector3.new(-0.005, 0.008, 0.006),
	Slash = Vector3.new(-0.004, 0.014, 0.012),
	Chop = Vector3.new(-0.014, 0.004, 0.006),
	Smash = Vector3.new(-0.022, 0.004, 0.01),
	Stab = Vector3.new(0.006, 0, 0.004),
}
local HIT_SHAKE: { [string]: number } = { Light = 0.12, Medium = 0.2, Heavy = 0.32 }

local BLOCKING_MOVES: { [string]: boolean } = { Climb = true, Mantle = true, Swim = true }
local BUFFER_WINDOW = 0.22 -- a press this close to the end of an action starts the next one when it can
local BOW_RECOVER = 0.32

local camera = workspace.CurrentCamera
local rng = Random.new()

local bound = false
local attackHeld = false
local attackArmed = false -- needs a fresh press after equipping or opening a menu
local aimHeld = false
local useActive = false
local equippedId: string? = nil
local equippedKey = "0:nil"
local equippedDef: any = FISTS
local nextActionAt = 0
local awaitingInventoryUntil = 0
local queuedAttack = false
local queuedAt = 0
local comboIndex = 0
local lastSwingEnd = -1
local lastStrikeAt = -1
local lastPredictedHitAt = -1
local lastDryAt = -1
local lastHurtAt = -1
local shotCounter = 0
local pendingSpent: { [string]: number } = {}
local pendingAt: { [string]: number } = {}
local PENDING_TIMEOUT = 1.5
local drawSound: Sound? = nil
local fullDrawSince: number? = nil
local aimAlpha = 0
local drawAlpha = 0
local spread = 0
local actionPulse = 0

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function phaseActive(): boolean
	return GameState:GetAttribute("Phase") == "Active"
end

local function canAct(): boolean
	return bound
		and ClientState.inArena
		and ClientState.alive
		and not ClientState.frozen
		and not ClientState.menuOpen
		and ClientState.spectating == nil
		and phaseActive()
end

local function movementAllows(): boolean
	return not BLOCKING_MOVES[ClientState.moveState]
end

local function canAimWith(def: any): boolean
	return def ~= nil and (def.kind == "Bow" or (def.kind == "Melee" and def.throwable == true))
end

-- "Melee" | "Bow" | "Throwable" | "Use". Ammo and utility items punch (the server treats them as fists).
local function equipKind(): string
	local def = equippedDef
	if def.kind == "Bow" then
		return "Bow"
	elseif def.kind == "Throwable" then
		return "Throwable"
	elseif ItemDefs.isConsumable(def.id) then
		return "Use"
	end
	return "Melee"
end

local function meleeDef(): any
	if equippedDef.kind == "Melee" then
		return equippedDef
	end
	return FISTS
end

local function isAiming(): boolean
	return aimHeld and canAimWith(equippedDef) and canAct() and movementAllows()
end

-- Items left, minus what we've used since the last InventoryUpdate (so latency can't fire arrows we don't have).
local function countItem(itemId: string): number
	local total = 0
	local inventory = ClientState.inventory
	local slots = inventory and inventory.slots
	if type(slots) == "table" then
		for _, slot in pairs(slots) do
			if type(slot) == "table" and slot.id == itemId then
				total += tonumber(slot.count) or 1
			end
		end
	end
	if pendingSpent[itemId] and os.clock() - (pendingAt[itemId] or 0) > PENDING_TIMEOUT then
		pendingSpent[itemId] = nil -- no InventoryUpdate came: the server refused it
	end
	return math.max(0, total - (pendingSpent[itemId] or 0))
end

local function spend(itemId: string)
	pendingSpent[itemId] = (pendingSpent[itemId] or 0) + 1
	pendingAt[itemId] = os.clock()
end

local function spendStamina(amount: number?)
	local movement = Controllers.MovementController
	if amount and amount > 0 and movement and type(movement.spendStamina) == "function" then
		pcall(movement.spendStamina, amount)
	end
end

local function stopSprint()
	local movement = Controllers.MovementController
	if movement and type(movement.stopSprint) == "function" then
		pcall(movement.stopSprint)
	end
end

local function notify(text: string)
	local notifications = Controllers.NotificationController
	if notifications and type(notifications.toast) == "function" then
		pcall(notifications.toast, text)
	end
end

local function muzzlePosition(): Vector3?
	local viewmodel = Controllers.ViewmodelController
	if viewmodel and type(viewmodel.getMuzzle) == "function" then
		local ok, position = pcall(viewmodel.getMuzzle)
		if ok and typeof(position) == "Vector3" then
			return position
		end
	end
	return nil
end

local function surfaceSound(material: Enum.Material?): string
	local projectiles = Controllers.ProjectileController
	if projectiles and type(projectiles.surfaceSound) == "function" then
		return projectiles.surfaceSound(material)
	end
	return "Hit_Stone"
end

local function impactEffect(position: Vector3, normal: Vector3?, material: Enum.Material?, kind: string?)
	local projectiles = Controllers.ProjectileController
	if projectiles and type(projectiles.impactEffect) == "function" then
		projectiles.impactEffect(position, normal, material, kind)
	end
end

local function predictProjectile(shotId: string, itemId: string, origin: Vector3, velocity: Vector3, gravity: number)
	local projectiles = Controllers.ProjectileController
	if projectiles and type(projectiles.predict) == "function" then
		projectiles.predict(shotId, itemId, origin, velocity, gravity, muzzlePosition())
	end
end

local function newShotId(): string
	shotCounter += 1
	return string.format("%d-%d", shotCounter, math.floor(os.clock() * 1000) % 1000000)
end

local function kick(rotation: Vector3, shake: number)
	ClientState.cameraImpulse:Fire(rotation, shake)
end

-- Spread in degrees for ranged attacks: movement and jumping widen it, drawing and aiming tighten it.
local function moveFactor(): number
	return math.clamp((ClientState.speed or 0) / math.max(Config.Movement.SprintSpeed, 1), 0, 1)
end

local function spreadDegrees(kind: string): number
	local move = moveFactor()
	local air = if ClientState.grounded == false then 1 else 0
	if kind == "Bow" then
		local fatigue = 0
		if fullDrawSince then
			fatigue = math.clamp((os.clock() - fullDrawSince - 2.5) / 2, 0, 1) * 1.6 -- arms tire at full draw
		end
		local hip = 2.6 * (1 - 0.65 * drawAlpha) + 1.8 * move + 2.5 * air
		return hip * (1 - 0.9 * aimAlpha) + fatigue
	end
	return (1.1 + 1.4 * move + 2 * air) * (1 - 0.5 * aimAlpha)
end

local function applySpread(cf: CFrame, degrees: number): Vector3
	if degrees <= 0.01 then
		return cf.LookVector
	end
	local radius = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local theta = rng:NextNumber() * math.pi * 2
	return (cf.Rotation * CFrame.Angles(math.sin(theta) * radius, math.cos(theta) * radius, 0)).LookVector
end

--------------------------------------------------------------------------------------------------------------------
-- Local hit prediction (mirrors CombatService's trace without the lag allowance)
--------------------------------------------------------------------------------------------------------------------

local function humanoidOf(part: Instance?): Humanoid?
	if not part then
		return nil
	end
	local parent = part.Parent
	if parent and parent:IsA("Accessory") then
		parent = parent.Parent
	end
	if parent and parent:IsA("Model") then
		return parent:FindFirstChildOfClass("Humanoid")
	end
	return nil
end

local function targetModels(): { Instance }
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, dummy in ipairs(CollectionService:GetTagged("TrainingDummy")) do
		if dummy:IsA("Model") and dummy:IsDescendantOf(workspace) then
			table.insert(list, dummy)
		end
	end
	return list
end

local function worldParams(targets: { Instance }): RaycastParams
	local list = table.clone(targets)
	if player.Character then
		table.insert(list, player.Character)
	end
	table.insert(list, camera)
	local effects = workspace:FindFirstChild("ClientProjectiles")
	if effects then
		table.insert(list, effects)
	end
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	local items = loot and loot:FindFirstChild("Items") -- ground items only; crates stay solid
	if items then
		table.insert(list, items)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

-- Where the crosshair points for a bow shot: the first character part or solid surface along the camera ray
-- (non-collidable foliage is skipped, as the server's arrow flies through it), else BowZeroDistance out.
local AIM_RANGE = 900
local function crosshairPoint(cf: CFrame): Vector3
	local origin, look = cf.Position, cf.LookVector
	local targets = targetModels()
	local distance: number? = nil
	if #targets > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = targets
		local hit = workspace:Raycast(origin, look * AIM_RANGE, params)
		if hit then
			distance = hit.Distance
		end
	end
	local world = workspace:Raycast(origin, look * (distance or AIM_RANGE), worldParams(targets))
	if world then
		distance = world.Distance
	end
	return origin + look * (distance or CombatConfig.BowZeroDistance or 100)
end

-- The release direction whose arc (speed, gravity) passes through `target`: the low solution, or the camera look
-- when the target is out of range for this speed or would need more than BowMaxLiftDegrees of lift.
local function ballisticDirection(origin: Vector3, target: Vector3, speed: number, gravity: number, look: Vector3): Vector3
	local delta = target - origin
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local x = flat.Magnitude
	if x < 1 or gravity <= 0 or speed <= 0 then
		return look
	end
	local v2 = speed * speed
	local disc = v2 * v2 - gravity * (gravity * x * x + 2 * delta.Y * v2)
	if disc < 0 then
		return look
	end
	local angle = math.atan((v2 - math.sqrt(disc)) / (gravity * x))
	local dir = flat.Unit * math.cos(angle) + Vector3.yAxis * math.sin(angle)
	if math.deg(math.acos(math.clamp(dir:Dot(look), -1, 1))) > (CombatConfig.BowMaxLiftDegrees or 25) then
		return look
	end
	return dir
end

type Prediction = { character: boolean, position: Vector3, normal: Vector3?, material: Enum.Material? }

local function predictMelee(def: any, cf: CFrame): Prediction?
	local origin = cf.Position
	local direction = cf.LookVector
	local reach = def.range or 5
	local radius = CombatConfig.MeleeHitRadius * 0.85
	local targets = targetModels()
	local world = worldParams(targets)
	if #targets > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = targets
		local candidate: Vector3? = nil
		local swept = workspace:Spherecast(origin, radius, direction * reach, params)
		if swept then
			local humanoid = humanoidOf(swept.Instance)
			if humanoid and humanoid.Health > 0 then
				candidate = swept.Position
			end
		end
		if not candidate then
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Include
			overlap.FilterDescendantsInstances = targets
			local best = math.huge
			for _, part in ipairs(workspace:GetPartBoundsInRadius(origin + direction * radius, radius, overlap)) do
				local humanoid = humanoidOf(part)
				if humanoid and humanoid.Health > 0 then
					local offset = part.Position - origin
					if offset:Dot(direction) > -0.5 and offset.Magnitude < best then
						best = offset.Magnitude
						candidate = part.Position
					end
				end
			end
		end
		if candidate then
			local offset = candidate - origin
			local distance = offset.Magnitude
			local blocked = if distance > 0.5 then workspace:Raycast(origin, offset, world) else nil
			if blocked == nil or blocked.Distance >= distance - 0.75 then
				return { character = true, position = candidate }
			end
		end
	end
	local result = workspace:Raycast(origin, direction * reach, world)
	if result then
		return { character = false, position = result.Position, normal = result.Normal, material = result.Material }
	end
	return nil
end

--------------------------------------------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------------------------------------------

local function stopDrawSound()
	if drawSound then
		drawSound:Destroy()
		drawSound = nil
	end
end

local function cancelDraw()
	local rec = CombatController.current
	if not rec or rec.kind ~= "Draw" then
		return
	end
	CombatController.current = nil
	stopDrawSound()
	fullDrawSince = nil
	if RangedRelease then
		local cf = camera.CFrame
		RangedRelease:FireServer(rec.shotId, cf.Position, cf.LookVector, 0, "Cancel")
	end
	CombatController.action:Fire("DrawCancel", { itemId = rec.itemId })
end

local function endUse()
	if useActive then
		useActive = false
		ClientState.useRequested:Fire(Enum.UserInputState.End)
	end
end

local function startMelee(now: number)
	local def = meleeDef()
	local look = MELEE_STYLE[def.id] or DEFAULT_STYLE
	comboIndex = if now - lastSwingEnd < 0.45 then comboIndex + 1 else 1
	local windup = def.windup or 0.1
	local total = math.max(def.cooldown or 0.5, windup + look.strike + 0.08)
	local rec = {
		kind = "Melee",
		itemId = def.id,
		def = def,
		style = look.style,
		weight = look.weight,
		variant = comboIndex,
		t0 = now,
		windup = windup,
		strike = look.strike,
		total = total,
		struck = false,
		hit = nil,
	}
	CombatController.current = rec
	nextActionAt = now + total
	spendStamina(def.staminaCost)
	CombatController.action:Fire("Swing", rec)
end

local function strike(rec: any, now: number)
	rec.struck = true
	lastStrikeAt = now
	local cf = camera.CFrame
	if MeleeSwing then
		MeleeSwing:FireServer(cf.LookVector)
	end
	Sfx.play(if rec.weight == "Light" then "Swing_Light" else "Swing_Heavy")

	local hit = predictMelee(rec.def, cf)
	rec.hit = if hit then (if hit.character then "Character" else "World") else nil
	if hit then
		if hit.character then
			lastPredictedHitAt = now
			Sfx.play("Hit_Flesh", { position = hit.position })
		else
			Sfx.play(surfaceSound(hit.material), { position = hit.position })
			local metal = rec.style ~= "Punch" and hit.material ~= nil
			impactEffect(hit.position, hit.normal, hit.material, if metal then "World" else "Soft")
		end
	end

	local base = KICK[rec.style] or KICK.Slash
	local side = if rec.variant % 2 == 0 then -1 else 1
	local strength = if hit and hit.character then 2.6 elseif hit then 2 else 1
	local shake = if hit and hit.character then HIT_SHAKE[rec.weight] or 0.2 elseif hit then (HIT_SHAKE[rec.weight] or 0.2) * 0.6 else 0
	kick(Vector3.new(base.X, base.Y * side, base.Z * side) * strength, shake)
	actionPulse = 1
	CombatController.action:Fire("Strike", {
		itemId = rec.itemId,
		style = rec.style,
		weight = rec.weight,
		variant = rec.variant,
		hit = rec.hit,
	})
end

local function startDraw(now: number)
	local def = equippedDef
	local ammo = def.ammo or "arrow"
	if countItem(ammo) <= 0 then
		if now - lastDryAt > 1 then
			lastDryAt = now
			Sfx.play("UIClick", { volume = 0.8, pitch = 0.7 })
			notify("No arrows")
		end
		return
	end
	local rec = { kind = "Draw", itemId = def.id, def = def, t0 = now, drawTime = math.max(def.drawTime or 1, 0.05), shotId = newShotId() }
	CombatController.current = rec
	fullDrawSince = nil
	stopSprint()
	stopDrawSound()
	drawSound = Sfx.play("BowDraw")
	if RangedRelease then
		local cf = camera.CFrame
		RangedRelease:FireServer(rec.shotId, cf.Position, cf.LookVector, 0, "Draw")
	end
	CombatController.action:Fire("DrawStart", rec)
end

local function releaseDraw(now: number)
	local rec = CombatController.current
	if not rec or rec.kind ~= "Draw" then
		return
	end
	local charge = math.clamp((now - rec.t0) / rec.drawTime, 0, 1)
	if charge < (CombatConfig.MinBowCharge or 0.2) or not canAct() then
		cancelDraw()
		return
	end
	stopDrawSound()
	local def = rec.def
	local ammo = def.ammo or "arrow"
	local cf = camera.CFrame
	local speed = Util.lerp(def.speedMin or 90, def.speedMax or 240, charge)
	local gravity = def.gravity or 50
	local aimCF = cf
	if CombatConfig.BowAimOnTarget ~= false then
		-- lift the release so the arc comes down on the crosshair point; the spread is applied around that
		local lifted = ballisticDirection(cf.Position, crosshairPoint(cf), speed, gravity, cf.LookVector)
		aimCF = CFrame.lookAt(cf.Position, cf.Position + lifted)
	end
	local direction = applySpread(aimCF, spreadDegrees("Bow"))
	if RangedRelease then
		RangedRelease:FireServer(rec.shotId, cf.Position, direction, charge, "Fire")
	end
	spend(ammo)
	Sfx.play("BowRelease")
	predictProjectile(rec.shotId, ammo, cf.Position, direction * speed, gravity)
	kick(Vector3.new(0.008 + 0.016 * charge, (rng:NextNumber() - 0.5) * 0.006, (rng:NextNumber() - 0.5) * 0.01), 0.03 + 0.05 * charge)
	CombatController.current = { kind = "BowRecover", itemId = rec.itemId, t0 = now, total = BOW_RECOVER, charge = charge }
	nextActionAt = now + BOW_RECOVER
	fullDrawSince = nil
	actionPulse = 0.7
	CombatController.action:Fire("Release", { itemId = rec.itemId, charge = charge })
end

local function startThrow(now: number, spear: boolean)
	local def = equippedDef
	if not spear and countItem(def.id) <= 0 then
		return
	end
	local windup = if spear then 0.15 else 0.1
	local total = math.max(def.cooldown or 0.5, windup + 0.3)
	if spear then
		total = math.max(total, 0.6)
	end
	local rec = {
		kind = "Throw",
		itemId = def.id,
		def = def,
		spear = spear,
		t0 = now,
		windup = windup,
		total = total,
		released = false,
		shotId = newShotId(),
	}
	CombatController.current = rec
	nextActionAt = now + total
	spendStamina(def.staminaCost or 0.05)
	stopSprint()
	CombatController.action:Fire("ThrowStart", rec)
end

local function releaseThrow(rec: any, now: number)
	rec.released = true
	local def = rec.def
	local cf = camera.CFrame
	local direction = applySpread(cf, spreadDegrees("Throw"))
	local speed = if rec.spear then def.throwSpeed or 150 else def.speed or 150
	local gravity = if rec.spear then def.throwGravity or 45 else def.gravity or 40
	if RangedRelease then
		RangedRelease:FireServer(rec.shotId, cf.Position, direction, 1, "Throw")
	end
	spend(rec.itemId)
	Sfx.play("Throw")
	predictProjectile(rec.shotId, rec.itemId, cf.Position, direction * speed, gravity)
	kick(Vector3.new(-0.012, 0.006, -0.012), 0.03)
	actionPulse = 0.8
	local last = rec.spear or countItem(rec.itemId) <= 0
	if last then
		awaitingInventoryUntil = now + 1.5 -- the weapon left our hand; wait for the server's inventory
	end
	CombatController.action:Fire("ThrowRelease", { itemId = rec.itemId, spear = rec.spear, last = last })
end

local function tryStartAttack(now: number, fromPress: boolean)
	if not canAct() or not movementAllows() then
		return
	end
	local busyUntil = math.max(nextActionAt, CombatController.equipBlockedUntil, awaitingInventoryUntil)
	if CombatController.current ~= nil or now < busyUntil then
		-- QW12: a press during the switch to a new item is kept for the whole switch (0.32 s, 0.44 s for the bow)
		local switching = now < CombatController.equipBlockedUntil
		if fromPress and (busyUntil - now < BUFFER_WINDOW or switching) then
			queuedAttack = true
			queuedAt = math.max(now, busyUntil - BUFFER_WINDOW) -- it expires 0.4 s after this, so never mid-switch
		end
		return
	end
	local kind = equipKind()
	if kind == "Bow" then
		startDraw(now)
	elseif kind == "Throwable" then
		startThrow(now, false)
	elseif kind == "Melee" then
		if equippedDef.kind == "Melee" and equippedDef.throwable and isAiming() then
			startThrow(now, true)
		else
			startMelee(now)
		end
	end
end

local function refreshTouchButtons()
	if not bound then
		return
	end
	local aimable = canAimWith(equippedDef)
	Input.setTouchVisible("Aim", aimable)
	if not aimable then
		Input.setToggle("Aim", false)
		if Input.isTouch() then
			aimHeld = false
		end
	end
	local button = Input.getTouchButton("Attack")
	if button and button:IsA("TextButton") then
		-- QW2: EAT, DRINK, HEAL, WEAR, DRAW, THROW (also a spear while aimed), else ATTACK
		button.Text = ActionHints.touchLabel(equippedDef, ClientState.aiming == true)
	end
end

local function equipKey(itemId: string?): string
	local inventory = ClientState.inventory
	return tostring(if inventory then inventory.equipped else 0) .. ":" .. tostring(itemId)
end

local function onEquipChanged(itemId: string?)
	local key = equipKey(itemId)
	if key == equippedKey then
		return
	end
	equippedKey = key
	equippedId = itemId
	equippedDef = ItemDefs.get(itemId) or FISTS
	cancelDraw()
	endUse()
	CombatController.current = nil
	queuedAttack = false
	attackArmed = false
	awaitingInventoryUntil = 0
	local equipTime = CombatConfig.EquipTime or 0.32
	if equippedDef.kind == "Bow" then
		equipTime += 0.12
	end
	CombatController.equipBlockedUntil = os.clock() + equipTime
	refreshTouchButtons()
end

--------------------------------------------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------------------------------------------

-- QW12: an attack or use you can't do right now still gets an answer.
local function denyBlockedMove()
	local state = ClientState.moveState
	if state == "Climb" then
		Feedback.deny("Climbing", "LET GO TO FIGHT · [" .. ActionHints.keyOf("Crouch") .. "]")
	elseif state == "Swim" then
		Feedback.deny("Swimming", "YOU CAN'T FIGHT WHILE SWIMMING")
	else
		Feedback.deny("Mantling") -- a mantle is over in under a second: the dry click is enough
	end
end

local function onAttack(state: Enum.UserInputState, _input: InputObject?): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		if ClientState.menuOpen then
			return Enum.ContextActionResult.Pass
		end
		attackHeld = true
		attackArmed = true
		if canAct() and not movementAllows() then
			denyBlockedMove()
		end
		if equipKind() == "Use" then
			if canAct() and movementAllows() and not useActive then
				useActive = true
				ClientState.useRequested:Fire(Enum.UserInputState.Begin)
			end
			return nil
		end
		tryStartAttack(os.clock(), true)
		return nil
	end
	-- End or Cancel
	attackHeld = false
	endUse()
	local rec = CombatController.current
	if rec and rec.kind == "Draw" then
		releaseDraw(os.clock())
	end
	return nil
end

local function onAim(state: Enum.UserInputState, _input: InputObject?): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		aimHeld = true
		if ClientState.menuOpen or not canAimWith(equippedDef) then
			return Enum.ContextActionResult.Pass
		end
	else
		aimHeld = false
	end
	return nil
end

local function bindInputs()
	if bound then
		return
	end
	bound = true
	attackHeld = false
	attackArmed = false
	aimHeld = false
	Input.bind("Attack", onAttack, {
		keys = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
		touch = true,
	})
	Input.bind("Aim", onAim, {
		keys = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2 },
		touch = { toggle = true, visible = false },
	})
	refreshTouchButtons()
end

local function unbindInputs()
	if not bound then
		return
	end
	cancelDraw()
	endUse()
	CombatController.current = nil
	bound = false
	attackHeld = false
	attackArmed = false
	aimHeld = false
	queuedAttack = false
	Input.unbind("Attack")
	Input.unbind("Aim")
end

local function refreshBinding()
	local want = ClientState.inArena and ClientState.alive and ClientState.spectating == nil
	if want then
		bindInputs()
	else
		unbindInputs()
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Feedback from the server
--------------------------------------------------------------------------------------------------------------------

local function onHitConfirm(data: any)
	if type(data) ~= "table" then
		return
	end
	local info = {
		damage = tonumber(data.damage) or 0,
		headshot = data.headshot == true,
		killed = data.killed == true,
		position = if typeof(data.position) == "Vector3" then data.position else nil,
		target = if type(data.target) == "string" then data.target else "Player",
		weaponId = if type(data.weaponId) == "string" then data.weaponId else nil,
		melee = data.melee == true,
	}
	ClientState.hitConfirmed:Fire(info)
	if info.killed then
		Sfx.play("HitMarkerKill")
		kick(Vector3.new(0.004, 0, 0), 0.06)
	else
		Sfx.play("HitMarker", if info.headshot then { pitch = 1.62, volume = 1.15 } else nil)
	end
	-- The server landed a swing our prediction missed (latency): make the impact heard now.
	local now = os.clock()
	if info.melee and info.position and now - lastStrikeAt < 0.6 and lastPredictedHitAt < lastStrikeAt then
		lastPredictedHitAt = now
		Sfx.play("Hit_Flesh", { position = info.position })
	end
end

local TICK_CAUSES: { [string]: boolean } = { Border = true, Starvation = true, Dehydration = true }

local function onDamageTaken(data: any)
	if type(data) ~= "table" then
		return
	end
	local amount = tonumber(data.amount) or 0
	local info = {
		amount = amount,
		fromPosition = if typeof(data.fromPosition) == "Vector3" then data.fromPosition else nil,
		cause = if type(data.cause) == "string" then data.cause else "Other",
	}
	ClientState.damageTaken:Fire(info)

	local now = os.clock()
	local ticking = TICK_CAUSES[info.cause] == true
	if now - lastHurtAt >= (if ticking then 2.2 else 0.25) then
		lastHurtAt = now
		Sfx.play("Hurt", { volume = if ticking then 0.55 else math.clamp(0.75 + amount / 60, 0.75, 1.3) })
	end

	local strength = math.clamp(amount / 30, 0.15, 1.2)
	if ticking then
		strength *= 0.35
	end
	local pitch, yaw, roll = 0.02, 0, 0
	if info.fromPosition then
		local relative = camera.CFrame:PointToObjectSpace(info.fromPosition)
		local flat = Vector3.new(relative.X, 0, relative.Z)
		if flat.Magnitude > 0.1 then
			local dir = flat.Unit
			yaw = dir.X * 0.025 -- snap away from the side the hit came from
			roll = -dir.X * 0.035
			pitch = 0.008 + 0.02 * math.max(0, -dir.Z)
		end
	end
	kick(Vector3.new(pitch, yaw, roll) * strength, math.clamp(strength * 0.6, 0.06, 0.8))
end

--------------------------------------------------------------------------------------------------------------------
-- Frame update
--------------------------------------------------------------------------------------------------------------------

local function update(dt: number)
	local now = os.clock()
	local heldId = ClientState.getEquippedItemId()
	if equipKey(heldId) ~= equippedKey then
		onEquipChanged(heldId)
	end

	local active = canAct()
	if not active then
		cancelDraw()
		if ClientState.menuOpen or not bound then
			endUse()
		end
		if ClientState.menuOpen then
			attackArmed = false
		end
	end
	if useActive and not movementAllows() then
		endUse()
	end

	local rec = CombatController.current
	if rec then
		if rec.kind == "Melee" then
			if not rec.struck and now >= rec.t0 + rec.windup then
				if active then
					strike(rec, now)
				else
					rec.struck = true
				end
			end
			if now >= rec.t0 + rec.total then
				CombatController.current = nil
				lastSwingEnd = now
			end
		elseif rec.kind == "Throw" then
			if not rec.released and now >= rec.t0 + rec.windup then
				if active then
					releaseThrow(rec, now)
				else
					rec.released = true
				end
			end
			if now >= rec.t0 + rec.total then
				CombatController.current = nil
			end
		elseif rec.kind == "BowRecover" then
			if now >= rec.t0 + rec.total then
				CombatController.current = nil
			end
		end
	end

	-- Buffered presses and held attacks
	if queuedAttack and now - queuedAt > 0.4 then
		queuedAttack = false
	end
	if active and CombatController.current == nil then
		if queuedAttack then
			if now >= math.max(nextActionAt, CombatController.equipBlockedUntil, awaitingInventoryUntil) then
				queuedAttack = false
				if attackHeld or equipKind() ~= "Bow" then
					tryStartAttack(now, false)
				end
			end
		elseif attackHeld and attackArmed then
			local kind = equipKind()
			if kind == "Melee" or kind == "Throwable" or (kind == "Bow" and CombatController.current == nil) then
				if kind ~= "Bow" or now >= nextActionAt then
					tryStartAttack(now, false)
				end
			end
		end
	end

	-- Bow draw
	rec = CombatController.current
	if rec and rec.kind == "Draw" then
		drawAlpha = math.clamp((now - rec.t0) / rec.drawTime, 0, 1)
		if drawAlpha >= 1 and not fullDrawSince then
			fullDrawSince = now
		end
	else
		drawAlpha = 0
	end

	-- Aim
	local aiming = isAiming()
	aimAlpha += ((if aiming then 1 else 0) - aimAlpha) * Util.damp(if aiming then 12 else 9, dt)
	if aimAlpha < 0.001 then
		aimAlpha = 0
	end

	-- Crosshair spread (0..1)
	actionPulse = math.max(0, actionPulse - dt * 4)
	local kind = equipKind()
	local target
	if kind == "Bow" then
		target = spreadDegrees("Bow") / 7
	elseif kind == "Throwable" or aiming then
		target = spreadDegrees("Throw") / 7
	else
		target = 0.12 + moveFactor() * 0.3 + (if ClientState.grounded == false then 0.25 else 0)
	end
	target = math.clamp(target + actionPulse * 0.25, 0, 1)
	spread += (target - spread) * Util.damp(14, dt)

	ClientState.aiming = aiming
	ClientState.aimAlpha = aimAlpha
	ClientState.drawAlpha = drawAlpha
	ClientState.crosshairSpread = spread
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function CombatController.getEquipped(): (string?, any)
	return equippedId, equippedDef
end

CombatController.canAimWith = canAimWith
CombatController.countItem = countItem

function CombatController.Init(registry)
	Controllers = registry
end

function CombatController.Start()
	MeleeSwing = Net.event("MeleeSwing")
	RangedRelease = Net.event("RangedRelease")
	Net.event("HitConfirm").OnClientEvent:Connect(onHitConfirm)
	Net.event("DamageTaken").OnClientEvent:Connect(onDamageTaken)
	ClientState.lifeChanged:Connect(refreshBinding)
	ClientState.spectateChanged:Connect(refreshBinding)
	ClientState.equippedChanged:Connect(function(itemId)
		onEquipChanged(if type(itemId) == "string" then itemId else nil)
	end)
	ClientState.inventoryChanged:Connect(function()
		table.clear(pendingSpent)
		awaitingInventoryUntil = 0
		refreshTouchButtons()
	end)
	player.CharacterAdded:Connect(function()
		camera = workspace.CurrentCamera
	end)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera = workspace.CurrentCamera
	end)
	RunService:BindToRenderStep("CombatController", Enum.RenderPriority.Input.Value + 10, update)
	refreshBinding()
end

return CombatController
