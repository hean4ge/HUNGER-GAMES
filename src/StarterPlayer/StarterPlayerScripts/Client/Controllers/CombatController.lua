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
	Combat v3 moves (docs/design/Combat_v3.md section 1; numbers in Shared.Moves; the server checks every one):
  Melee: tap Attack = the next light chain step (a tap during a swing's recovery is kept, so the chain flows; the
    step after the last is the first again); hold Attack HoldToHeavy (0.25 s) = the heavy's hold ("Charge" to the
    server), released (or by itself 1.5 s after full) it strikes with its charge; Aim (Mouse 2 / L2 / touch GUARD,
    held) = the guard, raised whenever nothing else is going on (the server times the parry from its raise); guard +
    tap = a kick; guard + hold with a throwable = the throw (aimed while wound); a press inside the counter window
    after a parry = the counter, at once; Dodge (Q, or Space / A while guarding; touch DODGE) = the dodge, its travel
    driven on our own body. CombatAction "Reaction" (the server's): the stagger, the knockback impulse, the hit-stop
    (ClientState.hitStopUntil) and the camera's jolt. Writes ClientState.guarding, charging (0..1), staggered,
    combatSpeedMult (for MovementController), nextSwing (the queued chain step, for the viewmodel). Actions:
    "GuardUp", "GuardDown", "ChargeStart", "ChargeCancel", "Dodge", "Parry", "Block", "Parried", "GuardBreak",
    "Reaction", "Skill" (SkillController). API for SkillController: canFight, playSkillMove, driveBody, holdAttacks.
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
local Moves = require(Shared:WaitForChild("Moves"))
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
	-- Combat v3 (5.4, 5.5)
	paired_blades = { style = "Slash", weight = "Light", strike = 0.07 },
	leaf_dagger = { style = "Stab", weight = "Light", strike = 0.08 },
	wrapped_sabre = { style = "Slash", weight = "Medium", strike = 0.1 },
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

-- Combat v3 (see the header's "Moves" part; numbers in Shared.Moves)
local MV = Moves.cfg
local RX = Moves.reactions
local lastChainStep: number? = nil -- the light chain: the step the last light swing played
local pressAt: number? = nil -- Attack went down with a melee weapon (tap or hold is decided from this)
local pressGuard = false -- ...while the guard was held (a tap kicks, a hold throws a throwable)
local charge: { [string]: any }? = nil -- the heavy's hold: { t0 (os.clock when it was told), sentAt }
local throwWind = false -- a throwable melee weapon wound back to throw (guard + hold Attack)
local guardHeld = false -- the Guard input (Aim's binding) is down with a melee weapon in hand
local guardOn = false -- the guard is up (and the server was told)
local guardSince = 0
local counterUntil = 0 -- os.clock: a press now is a counter (after this player parried)
local kickReadyAt = 0
local dodgeReadyAt = 0
local dodgeTimes: { number } = {}
local drive: { [string]: any }? = nil -- a dodge, a dash or a vault moving our own body (driveBody)
local staggerUntil = 0
local hitStopUntil = 0
local knockdownAt = -math.huge

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
	if equippedDef.kind == "Melee" then
		return throwWind and canAct() and movementAllows() -- (a throwable wound back: guard + hold Attack)
	end
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
local function predictOne(cf: CFrame, reach: number, radius: number): Prediction?
	local origin = cf.Position
	local direction = cf.LookVector
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

-- Combat v3: a slash traces three rays across its arc (-15, 0, +15 degrees), a stab one thinner ray, as the server
-- does (CombatService, Moves.traceDirections); the first body any ray touches is the target. move nil: step 1.
local function predictMelee(def: any, cf: CFrame, move: any?): Prediction?
	local m = move or Moves.step(def, def.id, 1)
	local reach = (m.range or def.range or 5) + (m.reach or 0)
	local radius = CombatConfig.MeleeHitRadius * 0.85 * (if m.stab then MV.StabRadius else 1)
	local world: Prediction? = nil
	for _, dir in ipairs(Moves.traceDirections(m, cf.LookVector)) do
		local found = predictOne(CFrame.lookAt(cf.Position, cf.Position + dir), reach, radius)
		if found and found.character then
			return found
		elseif found and not world then
			world = found
		end
	end
	return world
end

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

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function concentrating(): boolean
	local untilAt = tonumber(player:GetAttribute("ConcentrationUntil"))
	return untilAt ~= nil and serverNow() < untilAt
end

-- The guard (Combat_v3 1.3): told to the server when it goes up or down; the server times the parry from here.
local function setGuard(on: boolean)
	if on == guardOn then
		return
	end
	guardOn = on
	guardSince = os.clock()
	if MeleeSwing then
		MeleeSwing:FireServer("Guard", on, serverNow())
	end
	Input.setTouchVisible("Dodge", on)
	CombatController.action:Fire(if on then "GuardUp" else "GuardDown", { itemId = equippedDef.id })
end

local function cancelCharge(tell: boolean)
	if charge then
		charge = nil
		if tell and MeleeSwing then
			MeleeSwing:FireServer("Charge", false)
		end
		CombatController.action:Fire("ChargeCancel", {})
	end
end

-- The light chain step the next tap plays: the next after the last one while the chain holds (inside the chain window
-- after the last swing ended, or a press during its recovery), else the first. After the last step, the first again.
local function nextStep(itemId: string, now: number): number
	local n = Moves.chainLength(itemId)
	local rec = CombatController.current
	local chaining = lastSwingItem == itemId and lastChainStep ~= nil
		and ((rec ~= nil and rec.kind == "Melee" and rec.itemId == itemId) or now - lastSwingEnd < MV.ChainWindow)
	if chaining then
		return (lastChainStep :: number) % n + 1
	end
	return 1
end

local scheduleMark: (any) -> () -- (set below, beside fireDue)

-- Starts a move (a Shared.Moves move: a chain step, a heavy, a counter, a kick, a skill strike's swing).
local function startMove(now: number, move: { [string]: any }, held: number?)
	local def = meleeDef()
	local look = MELEE_STYLE[def.id] or DEFAULT_STYLE
	local windup = move.windup or def.windup or 0.1
	local total = move.total or def.cooldown or 0.5
	if (tonumber(ClientState.stamina) or 1) <= 0.001 then
		total = windup + (total - windup) / MV.ExhaustedAttackSpeed -- (no stamina: the chain slows)
	end
	local style = move.style or look.style
	local variant = move.variant or 1
	if move.kind == "Light" then
		lastChainStep = move.index
	elseif move.kind ~= "Skill" then
		lastChainStep = nil
	end
	swingSets[def.id] = variant
	lastSwingItem = def.id
	local rec = {
		kind = "Melee",
		move = move,
		moveId = move.id,
		moveKind = move.kind,
		held = held,
		itemId = def.id,
		def = def,
		style = style,
		weight = if move.heavyHit then "Heavy" else look.weight,
		variant = variant,
		seed = rng:NextInteger(1, 2147483646),
		t0 = now,
		windup = windup,
		strike = if move.heavyHit then look.strike * 1.25 else look.strike,
		total = math.max(total, windup + look.strike + 0.08),
		struck = false,
		hit = nil,
		tier = move.tier,
		startedAt = serverNow(), -- (sent with the strike: the server times its cooldown from here)
	}
	CombatController.current = rec
	nextActionAt = now + rec.total
	spendStamina((move.stamina or 0) * (if concentrating() then 0.7 else 1))
	setGuard(false)
	if MeleeSwing and move.kind ~= "Skill" then
		-- the others see the swing from its start (the server relays it), not from the moment it lands
		MeleeSwing:FireServer("Start", if variant <= 8 then variant else nil, move.id)
	end
	CombatController.action:Fire("Swing", rec)
	scheduleMark(rec)
	return rec
end

local function startMelee(now: number)
	local def = meleeDef()
	startMove(now, Moves.step(def, def.id, nextStep(def.id, now)))
end

-- The hit-stop on our own view (ViewmodelController and CharacterVisuals read ClientState.hitStopUntil).
local function hitStop(seconds: number)
	if seconds > 0 then
		hitStopUntil = math.max(hitStopUntil, os.clock() + seconds)
		ClientState.hitStopUntil = hitStopUntil
	end
end

local function strike(rec: any, now: number)
	rec.struck = true
	lastStrikeAt = now
	CombatController.lastStrikeLate = now - (rec.t0 + rec.windup) -- (seconds after the hit mark: the test reads it)
	local cf = baseCFrame()
	local hit = predictMelee(rec.def, cf, rec.move)
	if MeleeSwing then
		-- the server lands a swing only if this trace touched someone, so a hit you didn't see never counts, and it
		-- checks the body this trace touched and no other; the set (1-8) lets the other players see this same swing;
		-- the start time lets the server gate the swing by when it began here, however late this message arrives;
		-- the move ("L2", "H", "K" ...) and, for a heavy, how long Attack was held
		MeleeSwing:FireServer(cf.LookVector, hit ~= nil and hit.character, if rec.variant <= 8 then rec.variant else nil,
			if hit and hit.character then hit.target else nil, rec.startedAt, rec.moveId, rec.held)
	end
	Sfx.play(if rec.weight == "Light" then "Swing_Light" else "Swing_Heavy", if rec.move and rec.move.heavyHit then { pitch = 0.85 } else nil)

	rec.hit = if hit then (if hit.character then "Character" else "World") else nil
	if hit then
		if hit.character then
			lastPredictedHitAt = now
			Sfx.play("Hit_Flesh", { position = hit.position, pitch = if rec.move and rec.move.heavyHit then 0.8 else nil })
			-- weight on contact: the view holds for the tier's hit-stop (Combat_v3 1.8)
			hitStop(Moves.tier(rec.tier).hitStop)
		else
			Sfx.play(surfaceSound(hit.material), { position = hit.position })
			local metal = rec.style ~= "Punch" and hit.material ~= nil
			impactEffect(hit.position, hit.normal, hit.material, if metal then "World" else "Soft")
		end
	end

	local base = KICK[rec.style] or KICK.Slash
	local strength = if hit and hit.character then 2.6 elseif hit then 2 else 1
	if rec.move and rec.move.heavyHit then
		strength *= 1.5
	end
	local shake = if hit and hit.character then HIT_SHAKE[rec.weight] or 0.2 elseif hit then (HIT_SHAKE[rec.weight] or 0.2) * 0.6 else 0
	if hit and hit.character and rec.tier == "Heavy" then
		shake = math.max(shake, (RX.Heavy.ShakeAttacker or { 0.25 })[1])
	end
	kick(swingKick(rec.style, rec.variant, base) * strength, shake)
	actionPulse = 1
	CombatController.action:Fire("Strike", {
		itemId = rec.itemId,
		style = rec.style,
		weight = rec.weight,
		variant = rec.variant,
		hit = rec.hit,
		move = rec.moveId,
		tier = rec.tier,
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

local queuedIntent: string? = nil

-- The strike (and a throw's release) leaves on its hit mark: checked at the mark itself (task.delay from the swing's
-- start), on every Heartbeat and in the render step, whichever comes first. Checking only once per drawn frame sent it
-- up to a frame late (0.057 s in the 15 fps test windows). The server times the swing from its start (trySwing), so
-- sending on the mark is the honest time, never early.
local function fireDue(now: number)
	local rec = CombatController.current
	if not rec or now < rec.t0 + (rec.windup or 0) then
		return
	end
	-- (a throw still leaves in the render step: its aim puts the view's bob back on, which is only right there)
	if rec.kind == "Melee" and not rec.struck then
		if canAct() then
			strike(rec, now)
		else
			rec.struck = true
		end
	end
end

scheduleMark = function(rec: any)
	task.delay(math.max(0, rec.windup or 0), function()
		if CombatController.current == rec then
			fireDue(os.clock())
		end
	end)
end

-- intent: "Light" (a tap), "Kick" (a tap while guarding), "Counter" (a press after a parry), "Throw" (a throwable
-- melee weapon released after guard + hold), nil (bows, throwing knives: as before).
local function tryStartAttack(now: number, fromPress: boolean, intent: string?)
	if not canAct() or not movementAllows() then
		return
	end
	if now < staggerUntil then
		return -- (staggered: no attack until it ends)
	end
	local busyUntil = math.max(nextActionAt, CombatController.equipBlockedUntil, awaitingInventoryUntil)
	local rec = CombatController.current
	if rec ~= nil or now < busyUntil then
		-- QW12: a press during the switch to a new item is kept for the whole switch (0.32 s, 0.44 s for the bow);
		-- Combat v3: a tap during a swing's recovery is kept too, so the chain flows into its next step
		local switching = now < CombatController.equipBlockedUntil
		-- (the whole swing, wind-up included: a fast tap early in a wind-up was dropped, so quick tapping lost steps)
		local swinging = rec ~= nil and rec.kind == "Melee"
		if fromPress and (busyUntil - now < BUFFER_WINDOW or switching or swinging) then
			queuedAttack = true
			queuedIntent = intent
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
		local def = meleeDef()
		if intent == "Throw" and equippedDef.kind == "Melee" and equippedDef.throwable then
			startThrow(now, true)
		elseif intent == "Counter" then
			startMove(now, Moves.counter(def, def.id))
		elseif intent == "Kick" and now >= kickReadyAt then
			kickReadyAt = now + MV.Kick.Cooldown
			startMove(now, Moves.kick())
		else
			startMelee(now)
		end
	end
end

-- The heavy's hold begins (Attack held HoldToHeavy with a melee weapon, not guarding): the server is told, so it
-- times the charge and the others see the weapon wound back.
local function beginCharge(now: number)
	if charge or not canAct() or not movementAllows() or now < staggerUntil then
		return
	end
	if CombatController.current ~= nil or now < math.max(nextActionAt, CombatController.equipBlockedUntil, awaitingInventoryUntil) then
		return
	end
	charge = { t0 = now }
	setGuard(false)
	stopSprint()
	if MeleeSwing then
		MeleeSwing:FireServer("Charge", serverNow())
	end
	CombatController.action:Fire("ChargeStart", { itemId = equippedDef.id, t0 = now })
end

-- Lets the heavy go: the hold so far (MinHold + the time since the server was told) sets its strength.
local function releaseCharge(now: number)
	local c = charge
	if not c then
		return
	end
	charge = nil
	local held = MV.Heavy.MinHold + (now - c.t0)
	local def = meleeDef()
	startMove(now, Moves.heavy(def, def.id, held, concentrating()), held)
end

local guardMode: string? = nil -- how Aim's touch button is bound: "Guard" (held) or "Aim" (a toggle)

local function bindAim(mode: string)
	if guardMode == mode then
		return
	end
	guardMode = mode
	local spec = Input.ACTIONS and Input.ACTIONS.Guard
	if mode == "Guard" then
		local touch = if spec then table.clone(spec.touch) else { label = "GUARD", toggle = false }
		Input.bind("Aim", CombatController._onAim, { keys = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2 }, touch = touch })
	else
		Input.bind("Aim", CombatController._onAim, {
			keys = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2 },
			touch = { toggle = true, visible = false },
		})
	end
end

local function refreshTouchButtons()
	if not bound then
		return
	end
	local melee = equipKind() == "Melee"
	bindAim(if melee then "Guard" else "Aim")
	local aimable = melee or canAimWith(equippedDef)
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
	cancelCharge(false) -- (the server drops the hold itself when the weapon changes)
	setGuard(false)
	throwWind = false
	pressAt = nil
	lastChainStep = nil
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
	local now = os.clock()
	if state == Enum.UserInputState.Begin then
		if ClientState.menuOpen then
			return Enum.ContextActionResult.Pass
		end
		attackHeld = true
		attackArmed = true
		if canAct() and not movementAllows() then
			denyBlockedMove()
		end
		local kind = equipKind()
		if kind == "Use" then
			if canAct() and movementAllows() and not useActive then
				useActive = true
				ClientState.useRequested:Fire(Enum.UserInputState.Begin)
			end
			return nil
		elseif kind == "Melee" then
			-- Combat v3: a press after a parry is a counter, at once; otherwise a tap or a hold, decided by how long
			-- Attack stays down (HoldToHeavy)
			if now < counterUntil then
				counterUntil = 0
				pressAt = nil
				tryStartAttack(now, true, "Counter")
				return nil
			end
			pressAt = now
			pressGuard = guardHeld
			return nil
		end
		tryStartAttack(now, true)
		return nil
	end
	-- End or Cancel
	attackHeld = false
	endUse()
	local rec = CombatController.current
	if rec and rec.kind == "Draw" then
		releaseDraw(now)
	end
	if charge then
		releaseCharge(now)
	elseif throwWind then
		throwWind = false
		tryStartAttack(now, true, "Throw")
	elseif pressAt then
		tryStartAttack(now, true, if pressGuard then "Kick" else "Light")
	end
	pressAt = nil
	return nil
end

local function onAim(state: Enum.UserInputState, _input: InputObject?): Enum.ContextActionResult?
	local melee = equipKind() == "Melee"
	if state == Enum.UserInputState.Begin then
		if ClientState.menuOpen then
			return Enum.ContextActionResult.Pass
		end
		if melee then
			guardHeld = true -- (update raises the guard when nothing else is going on)
			return nil
		end
		aimHeld = true
		if not canAimWith(equippedDef) then
			return Enum.ContextActionResult.Pass
		end
	else
		aimHeld = false
		guardHeld = false
	end
	return nil
end
CombatController._onAim = onAim

-- The dodge (Combat_v3 1.3): Q, or Jump while guarding. A 0.15 s start-up, then 8 studs in 0.25 s the way you move
-- (a 6-stud backstep standing still); melee blows miss you during the travel (the server times it).
local function tryDodge(): boolean
	local now = os.clock()
	local D = MV.Dodge
	local downFor = now - knockdownAt
	local rollOut = downFor < (RX.Knockdown.Down or 1) and downFor >= (RX.Knockdown.RollOutAfter or 0.5)
	if not canAct() or not movementAllows() or (now < staggerUntil and not rollOut) or now < dodgeReadyAt or drive then
		return false
	end
	if (tonumber(ClientState.stamina) or 1) < D.Stamina then
		Feedback.deny("Tired")
		return false
	end
	local recent = {}
	for _, t in ipairs(dodgeTimes) do
		if now - t < D.RepeatWindow then
			table.insert(recent, t)
		end
	end
	spendStamina(D.Stamina * (if #recent >= 2 then D.RepeatCostMult else 1))
	table.insert(recent, now)
	dodgeTimes = recent
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local move = if humanoid then Util.flat(humanoid.MoveDirection) else Vector3.zero
	local distance = D.Distance
	local look = Util.flat(camera.CFrame.LookVector)
	if move.Magnitude < 0.2 then
		move = if look.Magnitude > 0.05 then -look.Unit else Vector3.zero
		distance = D.BackDistance
	end
	if move.Magnitude < 0.05 then
		return false
	end
	move = move.Unit
	dodgeReadyAt = now + D.Cooldown
	cancelCharge(true)
	cancelDraw()
	setGuard(false)
	throwWind = false
	local rec = CombatController.current
	if rec and rec.kind == "Melee" and not rec.struck then
		CombatController.current = nil -- (a dodge cancels a swing still being wound up)
		nextActionAt = now
	end
	if MeleeSwing then
		MeleeSwing:FireServer("Dodge", move, serverNow())
	end
	local localDir = camera.CFrame:VectorToObjectSpace(move)
	local kind = if localDir.Z < -0.5 then "Roll" elseif localDir.Z > 0.5 then "Back" elseif localDir.X < 0 then "Left" else "Right"
	drive = { t0 = now + D.Startup, duration = D.Travel, dir = move, speed = distance / D.Travel, kind = "Dodge" }
	nextActionAt = math.max(nextActionAt, now + D.Startup + D.Travel + D.Recovery)
	kick(Vector3.new(-0.01, localDir.X * -0.01, localDir.X * 0.02), 0.04)
	CombatController.action:Fire("Dodge", { kind = kind, dir = localDir, t0 = now, startup = D.Startup, travel = D.Travel })
	return true
end

local function onDodge(state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult?
	local key = if io then io.KeyCode else nil
	local jumpKey = key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA
	if state ~= Enum.UserInputState.Begin then
		return if jumpKey then Enum.ContextActionResult.Pass else nil
	end
	if ClientState.menuOpen then
		return Enum.ContextActionResult.Pass
	end
	if jumpKey and not guardOn and not guardHeld then
		return Enum.ContextActionResult.Pass -- (Space / A jump unless the guard is up)
	end
	if not tryDodge() and jumpKey then
		return Enum.ContextActionResult.Pass
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
	guardHeld = false
	guardMode = nil
	Input.bind("Attack", onAttack, {
		keys = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
		touch = true,
	})
	bindAim(if equipKind() == "Melee" then "Guard" else "Aim")
	local dodgeSpec = Input.ACTIONS and Input.ACTIONS.Dodge
	Input.bind("Dodge", onDodge, {
		keys = if dodgeSpec then dodgeSpec.keys else { Enum.KeyCode.Q },
		touch = if dodgeSpec then table.clone(dodgeSpec.touch) else { label = "DODGE", visible = false },
		priority = 2100, -- (over the default jump's binding, which gets Space / A back through Pass)
	})
	refreshTouchButtons()
end

local function unbindInputs()
	if not bound then
		return
	end
	cancelDraw()
	endUse()
	cancelCharge(true)
	setGuard(false)
	CombatController.current = nil
	bound = false
	attackHeld = false
	attackArmed = false
	aimHeld = false
	guardHeld = false
	throwWind = false
	pressAt = nil
	queuedAttack = false
	guardMode = nil
	Input.unbind("Attack")
	Input.unbind("Aim")
	Input.unbind("Dodge")
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
	-- Combat v3: our blow was parried (nothing landed; the Reaction that staggers us comes with it) or blocked
	if data.parried == true then
		Sfx.play("Hit_Metal", { pitch = 1.45, volume = 1.1 })
		kick(Vector3.new(0.02, 0, 0.01), 0.15)
		CombatController.action:Fire("Parried", { position = info.position })
		return
	end
	if data.blocked == true then
		CombatController.action:Fire("Blocked", { position = info.position })
		kick(Vector3.new(0.012, 0, 0), 0.08)
	end
	if type(data.hitStop) == "number" and data.hitStop > 0 and not data.blocked then
		hitStop(math.min(data.hitStop, 0.12) * 0.5) -- (the server's tier: a little more if our prediction missed it)
	end
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

-- Combat v3: what the server says happened to our own body (CombatAction "Reaction", "Parry", "GuardBreak").
-- A reaction: the stagger (no attack, no guard, a swing being wound up is cancelled, as on the server), the
-- knockback by impulse on our own body (we own it; MovementController's velocity takes it and lets it decay), the
-- hit-stop and the camera's jolt along the blow (never red: Mild).
local function onReaction(data: { [string]: any })
	local now = os.clock()
	local tierName = if type(data.tier) == "string" then data.tier else "Flinch"
	local time = tonumber(data.time) or 0
	local tier = Moves.tier(tierName)
	if tier.rank >= 2 and time > 0 then
		staggerUntil = math.max(staggerUntil, now + time)
		cancelCharge(false)
		setGuard(false)
		throwWind = false
		local rec = CombatController.current
		if rec and rec.kind == "Melee" and not rec.struck then
			CombatController.current = nil -- (Interrupted, as the server refuses it)
			nextActionAt = now
		end
		if tier.rank == 4 then
			knockdownAt = now
		end
	end
	local impulse = data.impulse
	local cap = tonumber(data.cap) or RX.Knockback.Cap
	if typeof(impulse) == "Vector3" and impulse == impulse and impulse.Magnitude > 0.01 then
		local flat = Util.flat(impulse)
		if flat.Magnitude > cap then
			flat = flat.Unit * cap
		end
		local movement = Controllers.MovementController
		if movement and type(movement.addImpulse) == "function" then
			pcall(movement.addImpulse, flat)
		end
		local lift = math.clamp(impulse.Y, 0, 20)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if lift > 0.5 and root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity += Vector3.new(0, lift, 0)
		end
	end
	hitStop(tonumber(data.hitStop) or tier.hitStop)
	-- the view jolts along the blow: 2 degrees for a flinch, 6 for a stagger (the owner's numbers)
	local jolt = math.rad(tier.jolt)
	local pitch, yaw = jolt * 0.4, 0
	if typeof(data.from) == "Vector3" then
		local rel = camera.CFrame:PointToObjectSpace(data.from)
		local flat = Vector3.new(rel.X, 0, rel.Z)
		if flat.Magnitude > 0.1 then
			yaw = -flat.Unit.X * jolt
			pitch = jolt * (0.3 + 0.5 * math.max(0, -flat.Unit.Z))
		end
	end
	local shake = if tier.rank >= 3 then ((RX.Heavy.ShakeVictim or { 0.4 })[1]) else tier.rank * 0.08
	kick(Vector3.new(pitch, yaw, yaw * 0.6), shake)
	CombatController.action:Fire("Reaction", { tier = tierName, time = time, from = data.from })
end

local function onCombatAction(data: any)
	if type(data) ~= "table" then
		return
	end
	local action = data.action
	local character = player.Character
	if action == "Reaction" then
		onReaction(data)
	elseif action == "Parry" and character and data.target == character then
		-- we parried: the next press within the window is a counter
		counterUntil = os.clock() + (tonumber(data.counterFor) or MV.Counter.Window)
		Sfx.play("Hit_Metal", { pitch = 1.5, volume = 1.2 })
		hitStop(0.06)
		kick(Vector3.new(-0.01, 0, 0), 0.06)
		CombatController.action:Fire("Parry", { position = data.position })
	elseif action == "Block" and character and data.target == character then
		Sfx.play("Hit_Metal", { pitch = if data.heavy then 0.8 else 1.05 })
		kick(Vector3.new(0.01, 0, 0), if data.heavy then 0.15 else 0.06)
		CombatController.action:Fire("Block", { heavy = data.heavy == true })
	elseif action == "GuardBreak" and character and data.target == character then
		setGuard(false)
		CombatController.action:Fire("GuardBreak", {})
	end
end

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
		fireDue(now) -- (also on every Heartbeat and at the mark itself: see fireDue)
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
	local meleeKind = equipKind() == "Melee"
	if active and CombatController.current == nil then
		if queuedAttack then
			if now >= math.max(nextActionAt, CombatController.equipBlockedUntil, awaitingInventoryUntil) then
				queuedAttack = false
				if attackHeld or equipKind() ~= "Bow" then
					tryStartAttack(now, false, queuedIntent)
				end
			end
		elseif attackHeld and attackArmed and not meleeKind then
			-- (melee: holding Attack charges a heavy instead of swinging again, below)
			local kind = equipKind()
			if kind == "Throwable" or (kind == "Bow" and CombatController.current == nil) then
				if kind ~= "Bow" or now >= nextActionAt then
					tryStartAttack(now, false)
				end
			end
		end
	end

	-- Combat v3: the hold (a heavy, or a throwable's throw from the guard), the guard, our own body's drives
	if meleeKind and active and attackHeld and pressAt and not charge and not throwWind and now - pressAt >= MV.HoldToHeavy then
		if pressGuard and equippedDef.kind == "Melee" and equippedDef.throwable then
			throwWind = true -- (released: thrown; ClientState.aiming zooms while it is wound)
			setGuard(false)
		else
			beginCharge(now)
		end
		if charge or throwWind then
			pressAt = nil
		end
	end
	if charge then
		local H = MV.Heavy
		local held = H.MinHold + (now - charge.t0)
		if not active or now < staggerUntil then
			cancelCharge(true)
		elseif held >= H.FullHold + H.MaxHoldAfterFull then
			releaseCharge(now) -- (a full charge is held up to 1.5 s more, then it lets go by itself)
		elseif held > H.FullHold then
			spendStamina(H.HoldDrain * dt)
		end
	end
	local wantGuard = guardHeld and meleeKind and active and movementAllows() and now >= staggerUntil
		and CombatController.current == nil and charge == nil and not throwWind and drive == nil
		and now >= CombatController.equipBlockedUntil
	setGuard(wantGuard)
	if drive then
		local d = drive
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local movement = Controllers.MovementController
		if now >= d.t0 + d.duration or not (root and root:IsA("BasePart")) then
			drive = nil
		elseif now >= d.t0 then
			if not d.lifted and d.lift and d.lift > 0 then
				d.lifted = true
				root.AssemblyLinearVelocity += Vector3.new(0, d.lift, 0)
			end
			-- top the body's speed along the drive up to its own each frame (MovementController owns the velocity)
			local current = Util.flat(root.AssemblyLinearVelocity):Dot(d.dir)
			local deficit = d.speed - current
			if deficit > 0 and movement and type(movement.addImpulse) == "function" then
				pcall(movement.addImpulse, d.dir * deficit)
			end
		end
	end
	-- the chain's next step while a tap is queued: the viewmodel carries the cut on into its wind-up
	if queuedAttack and meleeKind and (queuedIntent == nil or queuedIntent == "Light") then
		local def = meleeDef()
		local nextMove = Moves.step(def, def.id, nextStep(def.id, now))
		ClientState.nextSwing = { style = nextMove.style, variant = nextMove.variant }
	else
		ClientState.nextSwing = nil
	end
	ClientState.guarding = guardOn
	ClientState.charging = if charge then math.clamp((MV.Heavy.MinHold + now - charge.t0 - MV.Heavy.MinHold) / (MV.Heavy.FullHold - MV.Heavy.MinHold), 0, 1) else nil
	ClientState.staggered = now < staggerUntil
	-- (MovementController: walk x Guard.WalkMult while guarding, x Heavy.WalkMult while charging, x Stagger.WalkMult
	-- while staggered; 1 otherwise)
	ClientState.combatSpeedMult = if now < staggerUntil then RX.Stagger.WalkMult
		elseif guardOn then MV.Guard.WalkMult elseif charge then MV.Heavy.WalkMult else 1

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
	-- (Combat v3: a guard, a heavy's hold and a stagger keep you off a sprint too)
	return (rec ~= nil and rec.kind == "Draw") or guardOn or charge ~= nil or os.clock() < staggerUntil
end

-- Combat v3, for SkillController and the views ------------------------------------------------------------------
-- The guard: (up, os.clock when it changed). The heavy's hold: 0..1 or nil. Staggered now.
function CombatController.guardState(): (boolean, number)
	return guardOn, guardSince
end
function CombatController.chargeAlpha(): number?
	return ClientState.charging
end
function CombatController.isStaggered(): boolean
	return os.clock() < staggerUntil
end
function CombatController.canFight(): boolean
	return canAct() and movementAllows() and os.clock() >= staggerUntil
end
-- A skill's own swing (Head Kick, a chained strike): plays it as a move and strikes at its windup, as any swing.
function CombatController.playSkillMove(move: { [string]: any }): { [string]: any }?
	if not CombatController.canFight() then
		return nil
	end
	cancelCharge(true)
	cancelDraw()
	return startMove(os.clock(), move)
end
-- Moves our own body: `speed` studs/s along `dir` (flat) for `duration` s from `delay` s on, plus `lift` studs/s up
-- once (the running cut, the vault).
function CombatController.driveBody(dir: Vector3, speed: number, duration: number, delay: number?, lift: number?)
	local flat = Util.flat(dir)
	if flat.Magnitude < 0.05 then
		return
	end
	drive = { t0 = os.clock() + (delay or 0), duration = duration, dir = flat.Unit, speed = speed, lift = lift, kind = "Skill" }
end
-- Holds attacks back for `seconds` (a skill owns the hands).
function CombatController.holdAttacks(seconds: number)
	nextActionAt = math.max(nextActionAt, os.clock() + seconds)
	setGuard(false)
end
CombatController._predictMelee = predictMelee -- test hook: (def, cf, move?) -> what the local trace touches

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
	Net.event("CombatAction").OnClientEvent:Connect(function(payload)
		local ok, err = pcall(onCombatAction, payload)
		if not ok then
			warn("[CombatController] " .. tostring(err))
		end
	end)
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
	RunService.Heartbeat:Connect(function()
		if CombatController.current then
			fireDue(os.clock())
		end
	end)
	refreshBinding()
end

return CombatController
