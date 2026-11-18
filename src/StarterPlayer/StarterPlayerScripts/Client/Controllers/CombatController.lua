--[[
	CombatController - the local player's attacks. Client only.

	Binds Attack (MouseButton1 / ButtonR2 / touch "ATTACK") and Aim (MouseButton2 / ButtonL2 / touch "AIM", shown only
	for the bow and the spear) through Shared.Input, and only while alive in the arena and not spectating, so lobby
	clicks and the third-person camera are untouched. Input is ignored while ClientState.menuOpen.
	  Melee: windup -> strike -> recover, timed from ItemDefs (windup, cooldown). When the swing starts MeleeSwing
	    ("Start", set) tells the server, which shows the others the swing from its beginning. At the strike moment
	    MeleeSwing is sent with the camera look vector, whether the local trace touched someone (only such a swing can
	    land), the swing's set (variant 1-8: other players see the same swing, CharacterVisuals), the body the trace
	    touched (the server checks that one and no other) and the server time at which the swing started (the server
	    gates swings by the rule used here: the next may start once the last one's `total` has passed since its start).
	    The trace (predictMelee) takes whoever is under the crosshair first; only when the crosshair is on nobody does
	    the forgiving ball decide. It starts at the default camera (CameraController.getBaseCFrame: half a stud behind
	    the head, no kick, bob or shake), whatever the render-step order is.
	    Swing sets (#90): each weapon remembers its last set. A swing that starts within Config.Combat.SwingChainWindow of
	    the same weapon's last swing ending (held Attack, a buffered or quick press) takes the next set in order; a fresh
	    click takes any other set at random, so a set never plays twice running. How many sets a style has is read from
	    the viewmodel's Poses at run time (Poses.swingCount(style) when it exists, else the style's list in Poses.SWING;
	    Punch: Poses.PUNCH, left and right; Stab: Poses.STAB). Each swing also carries a seed for small pose variation
	    (CombatController.swingJitter); windup, strike and total never vary. Each set kicks the camera its own way
	    (Poses.swingKick(style, set): a direction scaled to the style's KICK; a set without one flips left / right).
	    Holding Attack keeps swinging; a press just before a swing ends is buffered, and a press during an item switch is kept
    for the whole switch. Attacking while climbing or swimming answers with Feedback.deny.
	  Bow: hold Attack to draw (ClientState.drawAlpha over drawTime), release to shoot (RangedRelease "Fire") when
	    there are arrows; a very light draw is let down instead. Aim zooms (ClientState.aiming / aimAlpha) and
	    tightens the spread. The server is told when a draw starts and stops (RangedRelease "Draw" / "Cancel").
	    The arrow lands where the crosshair points: the release is lifted just enough that the arc (speed, gravity)
	    passes through the point under the crosshair (Config.Combat.BowAimOnTarget, BowZeroDistance).
	    Weapons v2 (the owner's bow, 18 Nov): only within the bow's on-target range (Shared.CombatStats: recurve 60, short
	    bow 40, +5 a star); beyond it the shot is zeroed at that range and drops below the crosshair along its real arc,
	    the same every time. No random spread standing still; moving, jumping and holding a full draw past
	    HoldSteadyTime widen it (the hold also drains stamina and lets the string down when it runs out). Writes
	    ClientState.drawFull (the full-draw moment, also a soft click) and ClientState.bowAim (nil on target, else
	    { distance, onTarget, drop, degrees } for a drop mark under the crosshair). Stats at the item's stars.
	  Throwing knife: Attack throws. Spear: Attack stabs, Aim + Attack throws (RangedRelease "Throw"). A throw is lifted
	    onto the crosshair point the same way, with its own speed and gravity (Config.Combat.ThrowAimOnTarget).
	  Food, drink, healing and armor: Attack is forwarded to ClientState.useRequested(state) instead.
	Feedback: the strike is traced locally so impact sounds, sparks and camera kicks are instant; the server confirms
	with HitConfirm -> ClientState.hitConfirmed + HitMarker / HitMarkerKill. DamageTaken -> ClientState.damageTaken,
	a camera kick away from the attacker and the Hurt sound. Writes ClientState.crosshairSpread every frame.

	For ViewmodelController / ProjectileController:
	  CombatController.current -> the action in progress, or nil:
	    { kind = "Melee", itemId, style, weight, variant, seed, t0, windup, strike, total, struck, hit }
	      variant: the swing set (1 .. the style's set count); seed: an integer, the same for the whole swing
	    { kind = "Draw", itemId, t0, drawTime }   { kind = "BowRecover", itemId, t0, total, charge }
	    { kind = "Throw", itemId, spear, t0, windup, total, released }
	    style: "Punch" | "Slash" | "Chop" | "Smash" | "Stab"; weight: "Light" | "Medium" | "Heavy"; times use os.clock()
	  CombatController.action: Signal(name, data)
	    "Swing" | "DrawStart" | "ThrowStart" (the new current record), "Strike" { itemId, style, weight, variant, hit },
	    "DrawCancel" { itemId }, "Release" { itemId, charge }, "ThrowRelease" { itemId, spear, last }
	  CombatController.equipBlockedUntil -> os.clock() time when the equip raise is done
	  CombatController.getEquipped() -> (itemId?, def)    CombatController.canAimWith(def) -> boolean
	  CombatController.countItem(itemId) -> number   items left, minus what we've spent since the last InventoryUpdate
	  CombatController.isDrawing() -> boolean   the bow is drawn (MovementController keeps sprint off for the whole draw)
	  CombatController.meleeStyle(itemId) -> (style, weight)   how that melee weapon swings
	  CombatController.swingJitter(seed) -> { pitch, yaw, roll, follow }   a swing's small variation, the same for one
	    seed: angles in radians (each within +-3 degrees) and a timing scale (1 +- 4 %) for use inside the follow-through
	    only (the recovery still ends at total, so the hit timing never changes)
	Optional hooks used when present: MovementController.spendStamina(amount) (melee staminaCost),
	MovementController.stopSprint() (drawing and throwing), ViewmodelController.getMuzzle() -> Vector3?,
	NotificationController.toast(text) ("No arrows").
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatStats = require(Shared:WaitForChild("CombatStats"))
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
	-- Weapons v2 (18 Nov): until their own swing sets exist, each borrows the nearest style
	twin_axe = { style = "Smash", weight = "Heavy", strike = 0.13 }, -- slow, wide, heavy; others read the wind-up
	ring_blade = { style = "Slash", weight = "Light", strike = 0.08 }, -- a close slash through the hoop
	climb_pick = { style = "Chop", weight = "Medium", strike = 0.1 }, -- a short overhead peck
}
local DEFAULT_STYLE = { style = "Slash", weight = "Medium", strike = 0.1 }

-- Camera kicks per swing style (pitch, yaw, roll in radians). Each swing set gives the direction (swingKick, from
-- Poses.swingKick) and the style the size; for a set without one, yaw and roll flip with the set (odd sets to the left).
local KICK: { [string]: Vector3 } = {
	Punch = Vector3.new(-0.005, 0.008, 0.006),
	Slash = Vector3.new(-0.004, 0.014, 0.012),
	Chop = Vector3.new(-0.014, 0.004, 0.006),
	Smash = Vector3.new(-0.022, 0.004, 0.01),
	Stab = Vector3.new(0.006, 0, 0.004),
}
local HIT_SHAKE: { [string]: number } = { Light = 0.12, Medium = 0.2, Heavy = 0.32 }

local BLOCKING_MOVES: { [string]: boolean } = { Climb = true, Mantle = true, Swim = true, Sit = true } -- Sit: in a tree
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
local swingSets: { [string]: number } = {} -- per weapon: the swing set it played last (#90)
local lastSwingItem: string? = nil -- the weapon of the last swing
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

-- The stars (1..5) of the item in hand: the equipped slot's `stars` in the inventory copy (1 when it has none).
local function equippedStars(): number
	local inventory = ClientState.inventory
	local slots = inventory and inventory.slots
	local slot = type(slots) == "table" and slots[inventory.equipped]
	return CombatStats.clampStars(if type(slot) == "table" then slot.stars else nil)
end

-- The swing's stats at the stars of the weapon in hand (CombatStats.melee: the server reads the same numbers).
local function meleeDef(): any
	if equippedDef.kind == "Melee" then
		return CombatStats.melee(equippedDef, equippedStars())
	end
	return CombatStats.melee(FISTS, 1)
end

local function bowStats(): any
	return CombatStats.bow(equippedDef, equippedStars())
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
		-- The owner's bow (Weapons_v2 6): standing, the arrow goes exactly where the crosshair says, at any draw: no
		-- random spread. Moving or in the air widens it (the crosshair's lines show it), and so does holding a full draw
		-- past HoldSteadyTime: a sway growing to HoldSwayMax degrees over 3 s.
		local sway = 0
		if fullDrawSince then
			local steady = CombatStats.config("HoldSteadyTime") or 2
			sway = math.clamp((os.clock() - fullDrawSince - steady) / 3, 0, 1) * (CombatStats.config("HoldSwayMax") or 1.2)
		end
		return (1.8 * move + 2.5 * air) * (1 - 0.6 * aimAlpha) + sway
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

-- The humanoid a touched part belongs to, and its body: a body part, something worn, or (given the target list)
-- anything else inside a target, such as the weapon it holds.
local function humanoidOf(part: Instance?, targets: { Instance }?): (Humanoid?, Instance?)
	if not part then
		return nil, nil
	end
	local parent = part.Parent
	if parent and parent:IsA("Accessory") then
		parent = parent.Parent
	end
	if parent and parent:IsA("Model") then
		local humanoid = parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, parent
		end
	end
	if targets then
		for _, target in ipairs(targets) do
			if part:IsDescendantOf(target) then
				return target:FindFirstChildOfClass("Humanoid"), target
			end
		end
	end
	return nil, nil
end

-- The default camera's CFrame (before the eye offset, kick, bob and shake): where melee traces start. Read from
-- CameraController, so it doesn't depend on which render step ran last.
local function baseCFrame(): CFrame
	local controller = Controllers.CameraController
	if controller and type(controller.getBaseCFrame) == "function" then
		local ok, cf = pcall(controller.getBaseCFrame)
		if ok and typeof(cf) == "CFrame" then
			return cf
		end
	end
	return camera.CFrame
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
local function crosshairPoint(cf: CFrame, onTarget: number?): Vector3?
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
	if distance == nil and onTarget then
		return nil -- (sky: the shot is zeroed at its on-target range)
	end
	return origin + look * (distance or CombatConfig.BowZeroDistance or 100)
end

-- The release direction (CombatStats.aimDirection, the same solver the tests read): the arc passes exactly through the
-- point under the crosshair when it is within `onTarget` studs; further away (or nothing under it) the shot is zeroed at
-- onTarget along the look and drops below the crosshair from there, the same every time. onTarget nil: on the crosshair
-- at any range (the old rule). The look itself when the arc can't reach, or would need more than BowMaxLiftDegrees.
local function ballisticDirection(origin: Vector3, look: Vector3, crosshair: Vector3?, speed: number, gravity: number, onTarget: number?): Vector3
	local dir = CombatStats.aimDirection(origin, look, crosshair, speed, gravity, onTarget, CombatConfig.BowMaxLiftDegrees or 25)
	return dir
end

type Prediction = { character: boolean, position: Vector3, normal: Vector3?, material: Enum.Material?, target: Instance? }

-- What this swing touches, as the server will check it (CombatService.meleeTrace). First a thin ray along the look:
-- whoever is under the crosshair, out to the ball's front. Only when the crosshair is on nobody (or on a body behind
-- cover), the forgiving ball (the first body it touches), then a point-blank overlap check. (The ball alone took the first body it touched: a
-- bystander's arm beside the line, or the next practice dummy's hand, instead of the one aimed at.) Only living bodies
-- count: one that just fell neither takes the swing nor blocks it.
local function predictMelee(def: any, cf: CFrame): Prediction?
	local origin = cf.Position
	local direction = cf.LookVector
	local reach = def.range or 5
	local radius = CombatConfig.MeleeHitRadius * 0.85
	local everyone = targetModels()
	local world = worldParams(everyone) -- (no body, living or not, is world)
	local targets = {}
	for _, model in ipairs(everyone) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(targets, model)
		end
	end
	if #targets > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = targets
		local candidate: Vector3? = nil
		local body: Instance? = nil
		local aimed = workspace:Raycast(origin, direction * (reach + radius), params)
		if aimed then
			local humanoid, model = humanoidOf(aimed.Instance, targets)
			if humanoid and humanoid.Health > 0 then
				candidate, body = aimed.Position, model
			end
		end
		if candidate then
			-- the body under the crosshair, if the way to that point is clear; if it is not (the ray above passes
			-- through cover), the ball below still gets its turn (CombatService.meleeTrace does the same)
			local offset = candidate - origin
			local distance = offset.Magnitude
			local blocked = if distance > 0.5 then workspace:Raycast(origin, offset, world) else nil
			if blocked == nil or blocked.Distance >= distance - 0.75 then
				return { character = true, position = candidate, target = body }
			end
			candidate, body = nil, nil
		end
		local swept = workspace:Spherecast(origin, radius, direction * reach, params)
		if swept then
			local humanoid, model = humanoidOf(swept.Instance, targets)
			if humanoid and humanoid.Health > 0 then
				candidate, body = swept.Position, model
			end
		end
		if not candidate then
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Include
			overlap.FilterDescendantsInstances = targets
			local best = math.huge
			for _, part in ipairs(workspace:GetPartBoundsInRadius(origin + direction * radius, radius, overlap)) do
				local humanoid, model = humanoidOf(part, targets)
				if humanoid and humanoid.Health > 0 then
					local offset = part.Position - origin
					if offset:Dot(direction) > -0.5 and offset.Magnitude < best then
						best = offset.Magnitude
						candidate, body = part.Position, model
					end
				end
			end
		end
		if candidate then
			local offset = candidate - origin
			local distance = offset.Magnitude
			local blocked = if distance > 0.5 then workspace:Raycast(origin, offset, world) else nil
			if blocked == nil or blocked.Distance >= distance - 0.75 then
				return { character = true, position = candidate, target = body }
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

-- Swing sets (#90, see the header). The viewmodel's Poses module is pure data; it is loaded on the first swing.
local posesModule: any = nil
local function swingSetCount(style: string): number
	if posesModule == nil then
		posesModule = false
		local folder = script.Parent:FindFirstChild("ViewmodelController")
		local module = folder and folder:FindFirstChild("Poses")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				posesModule = result
			end
		end
	end
	local poses = posesModule
	if not poses then
		return if style == "Stab" then 1 else 2
	end
	if type(poses.swingCount) == "function" then
		local ok, count = pcall(poses.swingCount, style)
		if ok and type(count) == "number" and count >= 1 then
			return math.floor(count)
		end
	end
	local swing = if type(poses.SWING) == "table" then poses.SWING else {}
	local sets = swing[style]
	if type(sets) == "table" and #sets > 0 then
		return #sets
	elseif style == "Punch" then
		local punch = poses.PUNCH
		return if type(punch) == "table" and #punch > 0 then #punch else 2 -- (left and right)
	elseif style == "Stab" then
		local stab = poses.STAB
		return if type(stab) == "table" and #stab > 0 then #stab else 1
	end
	local slash = swing.Slash -- (Poses.swing falls back on the Slash sets)
	return if type(slash) == "table" and #slash > 0 then #slash else 1
end

local function pickVariant(itemId: string, style: string, now: number): number
	local count = math.max(1, swingSetCount(style))
	local last = swingSets[itemId]
	if count == 1 then
		return 1
	elseif not last or last > count then
		return rng:NextInteger(1, count) -- the first swing with this weapon (or its sets changed)
	elseif lastSwingItem == itemId and now - lastSwingEnd < (CombatConfig.SwingChainWindow or 0.45) then
		return last % count + 1 -- a chain steps through the sets in order
	end
	local pick = rng:NextInteger(1, count - 1) -- a fresh click: any set but the last one
	return if pick >= last then pick + 1 else pick
end

-- The camera kick for a swing set: its own direction from the viewmodel's Poses (Poses.swingKick: pitch, yaw, roll),
-- at the size of the style's kick `base`; without one, yaw and roll flip with the set (odd sets cut to the left).
local function swingKick(style: string, variant: number, base: Vector3): Vector3
	swingSetCount(style) -- (loads the Poses module once)
	local poses = posesModule
	if poses and type(poses.swingKick) == "function" then
		local ok, dir = pcall(poses.swingKick, style, variant)
		if ok and typeof(dir) == "Vector3" and dir == dir and dir.Magnitude > 1e-4 then
			return dir.Unit * base.Magnitude
		end
	end
	local side = if variant % 2 == 0 then -1 else 1
	return Vector3.new(base.X, base.Y * side, base.Z * side)
end

local function startMelee(now: number)
	local def = meleeDef()
	local look = MELEE_STYLE[def.id] or DEFAULT_STYLE
	local variant = pickVariant(def.id, look.style, now)
	swingSets[def.id] = variant
	lastSwingItem = def.id
	local windup = def.windup or 0.1
	local total = math.max(def.cooldown or 0.5, windup + look.strike + 0.08)
	local rec = {
		kind = "Melee",
		itemId = def.id,
		def = def,
		style = look.style,
		weight = look.weight,
		variant = variant,
		seed = rng:NextInteger(1, 2147483646),
		t0 = now,
		windup = windup,
		strike = look.strike,
		total = total,
		struck = false,
		hit = nil,
		startedAt = workspace:GetServerTimeNow(), -- (sent with the strike: the server times its cooldown from here)
	}
	CombatController.current = rec
	nextActionAt = now + total
	spendStamina(def.staminaCost)
	if MeleeSwing then
		-- the others see the swing from its start (the server relays it), not from the moment it lands
		MeleeSwing:FireServer("Start", if variant <= 8 then variant else nil)
	end
	CombatController.action:Fire("Swing", rec)
end

local function strike(rec: any, now: number)
	rec.struck = true
	lastStrikeAt = now
	local cf = baseCFrame()
	local hit = predictMelee(rec.def, cf)
	if MeleeSwing then
		-- the server lands a swing only if this trace touched someone, so a hit you didn't see never counts, and it
		-- checks the body this trace touched and no other; the set (1-8) lets the other players see this same swing;
		-- the start time lets the server gate the swing by when it began here, however late this message arrives
		MeleeSwing:FireServer(cf.LookVector, hit ~= nil and hit.character, if rec.variant <= 8 then rec.variant else nil,
			if hit and hit.character then hit.target else nil, rec.startedAt)
	end
	Sfx.play(if rec.weight == "Light" then "Swing_Light" else "Swing_Heavy")

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
	local strength = if hit and hit.character then 2.6 elseif hit then 2 else 1
	local shake = if hit and hit.character then HIT_SHAKE[rec.weight] or 0.2 elseif hit then (HIT_SHAKE[rec.weight] or 0.2) * 0.6 else 0
	kick(swingKick(rec.style, rec.variant, base) * strength, shake)
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
	local stats = bowStats() -- (draw time, speed, damage and on-target range at its stars: the server's numbers)
	local rec = { kind = "Draw", itemId = def.id, def = def, stats = stats, t0 = now, drawTime = stats.drawTime, shotId = newShotId(), full = false }
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
	local stats = rec.stats or bowStats()
	local ammo = def.ammo or "arrow"
	local cf = camera.CFrame
	local speed = Util.lerp(stats.speedMin, stats.speedMax, charge)
	local gravity = stats.gravity
	local aimCF = cf
	if CombatConfig.BowAimOnTarget ~= false then
		-- lift the release so the arc comes down exactly on the crosshair point within the bow's on-target range
		-- (60 studs, +5 a star; the short bow 40); beyond it the bow is zeroed there and the arrow drops below the
		-- crosshair along its real arc. Any spread (moving, a long hold) is applied around that.
		local lifted = ballisticDirection(cf.Position, cf.LookVector, crosshairPoint(cf, stats.onTarget), speed, gravity, stats.onTarget)
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
	spendStamina((if spear then def.throwStaminaCost else nil) or def.staminaCost or 0.05)
	stopSprint()
	CombatController.action:Fire("ThrowStart", rec)
end

local function releaseThrow(rec: any, now: number)
	rec.released = true
	local def = rec.def
	-- Aim along what the screen shows, like the bow: this runs in the render step, where the camera is the default one
	-- again, so the view's landing dip, kick and shake (ClientState.cameraBob, last frame's) are put back on. Without
	-- them a spear thrown while landing a jump left up to 2.4 degrees off the crosshair.
	local cf = baseCFrame()
	local bob = ClientState.cameraBob
	if typeof(bob) == "CFrame" then
		cf = cf * bob.Rotation
	end
	local speed = if rec.spear then def.throwSpeed or 150 else def.speed or 150
	local gravity = if rec.spear then def.throwGravity or 45 else def.gravity or 40
	-- a weapon with its own on-target throw range (the Ring Blade: 45 studs) is zeroed there like a bow; any other
	-- throw lands on the crosshair at any range the lift allows, as before
	local onTarget = if rec.spear then CombatStats.melee(def, 1).throwOnTarget else CombatStats.throwable(def).onTarget
	local aimCF = cf
	if CombatConfig.ThrowAimOnTarget ~= false then
		-- like the bow: lift the release so this throw's arc (its speed and gravity) comes down on the crosshair point;
		-- thrown along the look, a knife landed about 1.1 studs low at 40 studs (combat QA)
		local lifted = ballisticDirection(cf.Position, cf.LookVector, crosshairPoint(cf, onTarget), speed, gravity, onTarget)
		aimCF = CFrame.lookAt(cf.Position, cf.Position + lifted)
	end
	local direction = applySpread(aimCF, spreadDegrees("Throw"))
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
	elseif state == "Sit" then
		Feedback.deny("Climbing", "STAND UP TO FIGHT · [E]")
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
	local drawFull = false
	if rec and rec.kind == "Draw" then
		drawAlpha = math.clamp((now - rec.t0) / rec.drawTime, 0, 1)
		if drawAlpha >= 1 and not fullDrawSince then
			-- the full-draw moment: a soft creak-stop and a tiny settle of the view, and ClientState.drawFull for the HUD
			-- (its draw ticks meet on the crosshair). From here the arrow has all its speed and damage.
			fullDrawSince = now
			rec.full = true
			Sfx.play("UIClick", { volume = 0.35, pitch = 0.55 })
			kick(Vector3.new(-0.002, 0, 0), 0)
		end
		drawFull = fullDrawSince ~= nil
		-- holding a full draw past HoldSteadyTime tires the arms: the sway grows (spreadDegrees) and stamina drains; at
		-- empty stamina the string is let down
		if fullDrawSince and now - fullDrawSince > (CombatStats.config("HoldSteadyTime") or 2) then
			spendStamina((CombatStats.config("HoldStaminaDrain") or 0.04) * dt)
			if (tonumber(ClientState.stamina) or 1) <= 0.001 then
				cancelDraw()
				drawAlpha = 0
				drawFull = false
			end
		end
	else
		drawAlpha = 0
	end
	ClientState.drawFull = drawFull
	-- Where this arrow would land relative to the crosshair (for the HUD's drop mark): nil within the bow's on-target
	-- range (it lands on the crosshair), else { distance, onTarget, drop (studs below), degrees (below the crosshair) }.
	-- Two rays a frame, only while drawing.
	local aimInfo = nil
	if rec and rec.kind == "Draw" and rec.stats and drawAlpha >= (CombatConfig.MinBowCharge or 0.2) then
		local cf = camera.CFrame
		local stats = rec.stats
		local point = crosshairPoint(cf, stats.onTarget)
		local distance = if point then (point - cf.Position).Magnitude else nil
		if distance == nil or distance > stats.onTarget then
			local d = distance or math.max(stats.onTarget * 2.5, 150) -- (sky: shown for a far shot)
			local speed = Util.lerp(stats.speedMin, stats.speedMax, drawAlpha)
			local drop = CombatStats.dropAt(d, stats.onTarget, speed, stats.gravity)
			aimInfo = { distance = d, onTarget = stats.onTarget, drop = drop, degrees = math.deg(math.atan2(drop, d)) }
		end
	end
	ClientState.bowAim = aimInfo

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

-- Test hook: the release a bow shot from `cf` at `charge` would send, with no spread: (direction, speed, gravity, the
-- stats used). Reads the bow in hand (or `def` when given) exactly as releaseDraw does.
function CombatController._bowRelease(cf: CFrame, charge: number, def: any?): (Vector3, number, number, any)
	local d = def or equippedDef
	local stats = CombatStats.bow(d, if def then 1 else equippedStars())
	local speed = Util.lerp(stats.speedMin, stats.speedMax, math.clamp(charge, 0, 1))
	local dir = ballisticDirection(cf.Position, cf.LookVector, crosshairPoint(cf, stats.onTarget), speed, stats.gravity, stats.onTarget)
	return dir, speed, stats.gravity, stats
end

-- The bow is drawn: MovementController keeps sprint blocked for the whole draw (stopSprint alone only ends a sprint
-- as the draw starts; combat QA ran at 21 studs/s at full draw).
function CombatController.isDrawing(): boolean
	local rec = CombatController.current
	return rec ~= nil and rec.kind == "Draw"
end

-- How a melee weapon swings, for an item id: (style, weight); an id without its own style swings like DEFAULT_STYLE.
function CombatController.meleeStyle(itemId: string?): (string, string)
	local look = (if type(itemId) == "string" then MELEE_STYLE[itemId] else nil) or DEFAULT_STYLE
	return look.style, look.weight
end

-- A swing's small variation from its seed (the Melee record's seed), the same every time for one seed: angles in radians
-- (pitch, yaw, roll, each within +-JITTER_DEGREES) and `follow`, a timing scale (1 +- JITTER_FOLLOW) for use inside the
-- follow-through only, so the swing still ends at its total and the hit timing never changes.
local JITTER_DEGREES = 3
local JITTER_FOLLOW = 0.04
function CombatController.swingJitter(seed: number?): { pitch: number, yaw: number, roll: number, follow: number }
	local r = Random.new(math.floor(tonumber(seed) or 0))
	local angle = math.rad(JITTER_DEGREES)
	return {
		pitch = (r:NextNumber() * 2 - 1) * angle,
		yaw = (r:NextNumber() * 2 - 1) * angle,
		roll = (r:NextNumber() * 2 - 1) * angle,
		follow = 1 + (r:NextNumber() * 2 - 1) * JITTER_FOLLOW,
	}
end

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
