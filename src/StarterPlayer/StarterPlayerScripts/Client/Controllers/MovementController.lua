--[[
	MovementController - realistic, weighty locomotion for the local character (client).

	INPUT (never blocks; re-scanned until found, re-found if destroyed):
	  1. Player.InputContexts.CharacterContext.MoveAction            (server-authority builds: per-player copy)
	  2. StarterPlayer.PlayerModule.InputContexts.CharacterContext.MoveAction
	     (InputAction, Direction2D: X = right, Y = forward; WASD, arrows, Thumbstick1, touch thumbsticks)
	  3. PlayerScripts.PlayerModule:GetControls():GetMoveVector()     (legacy PlayerModule)
	  Raw keys (W/Up, S/Down, A, D; Space for jump) only while no source exists, or while the source reads zero
	  with those keys held - never while a TextBox is focused, the Roblox menu is open, or a script disabled the
	  controls on purpose (PlayerModule ControlModule.Enabled = false).
	  The default ControlModule (RenderPriority.Input) still calls Humanoid:Move / sets Humanoid.Jump every
	  frame; our step (LS_Movement, RenderPriority.Character + 1) runs after it and wins.

	PHYSICS MODEL (Config.Movement; numbers are justified there):
	  - Ground: a friction-circle model. Push-off is force-limited at low speed and power-limited at speed
	    (a sprint builds over ~0.6 s), braking skids (harder from speed), and turning is limited by lateral
	    grip, so turns carve wider at speed and sharp turns cost speed. Every limit scales with surface grip.
	  - Direction: strafing and backpedalling are slower than running forward; sprint only roughly forward.
	  - Terrain: speed follows the slope along your path (uphill slower and tiring, downhill faster up to a
	    point, then you brake); sprinting down steep ground builds instability until you stumble. Ground
	    steeper than MaxWalkableAngle (Humanoid.MaxSlopeAngle) can't be walked up: you slide down it with
	    friction. Surfaces (mud, sand, snow, ice, rock, grass...) change speed, grip and effort, and wading
	    slows you by water depth.
	  - Air: a lighter, human-scale gravity while airborne (Roblox's default gravity is ~6.6 g at character
	    scale), applied with a local VectorForce; Humanoid.JumpHeight is converted so the jump apex is
	    Config.Movement.JumpHeight studs. Momentum is kept, air control is small.
	  - Jumps are edge-triggered: a press starts a short knee dip (JumpPrepTime; Animate plays the take-off from it)
	    and the take-off fires at its end. After a landing the feet stay down JumpGroundTime first, so a held or
	    mashed key can't bunny-hop; repeated hops are lower, cost more stamina and shed a little speed.
	  - Any avatar: measureRig scales ledge reach, probe heights, the crouch and the stride to each body; speeds and
	    the jump height are the same for everyone.
	  - Landing: compression and a slowdown scaled by the equivalent drop height; hard landings stumble.
	  - Mantles, vaults, climbs and swim exits are kinematic (PlatformStand + a root drive on PreSimulation
	    with gravity cancelled). Ladders (TrussParts) use the native Humanoid climb.
	  - Safety: if our update errors or stops running, the humanoid is handed back to the default controls
	    (WalkSpeed restored, PlatformStand cleared, jumping re-enabled) so nobody is ever left stuck.

	States (ClientState.moveState): Idle | Walk | Sprint | Crouch | Slide | Air | Climb | Mantle | Swim | Frozen
	  ("Slide" also covers sliding involuntarily down ground that is too steep to stand on.)
	Writes ClientState: moveState, speed, velocity, grounded, stamina, exhausted, crouchAlpha, strideAlpha
	Fires ClientState: moveStateChanged(new, old), jumped(), landed(impactSpeed),
	                   footstep(material: Enum.Material, intensity 0..1, foot "L" | "R")
	  strideAlpha is the phase of a full gait cycle: the left foot plants at 0, the right foot at 0.5.
	  landed's impactSpeed is normalised to standard gravity: sqrt(2 * workspace.Gravity * dropHeight), so
	  listeners tuned to drop heights keep working whatever the air gravity is. Fired for impacts >= 6.
	  footstep also fires with Enum.Material.Water for swim strokes and when wading, a soft step when you come to
	  a stop, a heavy one on a stumble, and one on top of a ledge after a mantle.
	Replicates stance changes with the SetStance remote ("Stand" | "Crouch" | "Slide" | "Climb").
Sprint and crouch modes come from the settings per device (Hold / Toggle / Auto, Hold / Toggle; see modeFor). A sprint
press while out of breath answers with Feedback.deny ("OUT OF BREATH").

	Public API (through the Controllers registry):
	  MovementController.getStanceBlend() -> { crouch, slide, climb, climbPhase, land, prep }   eased 0..1 pose weights
	  MovementController.getRig() -> rig?            measured rig of the local character
	  MovementController.measureRig(character, humanoid, standingHipHeight?) -> rig
	      rig = { r15, hip, rootHalf, headCenter: Vector3, headTop, torsoTop, rootPivotY, waistPivotY,
	              thigh, shin, legs, standHeight, crouchDrop, slideDrop, scale (height / 5.2), legScale (legs / 1.75),
	              strideScale (legs / 2.42, the clips' measuring rig), joints = { [name] = AnimationConstraint | Motor6D } }
	  MovementController.findJoints(character) -> { [name]: joint }
	  MovementController.stopSprint()                 cancel the current sprint (e.g. when attacking)
	  MovementController.addImpulse(velocity: Vector3) add horizontal velocity (local knockback, lunges)
	  MovementController.spendStamina(amount: number)  spend 0..1 stamina (melee swings)
	  MovementController.getMotion() -> { accel: Vector3, exertion: 0..1, surface: string, slope: number,
	      stumble: 0..1, wade: number, land: number }   live locomotion readings for the camera and body (shared table)
	  MovementController.getDebug() -> table           internal readings for tuning; set the local player's
	      attribute LS_MoveDebug = true to mirror them onto dbg_* attributes (10 Hz) for probes
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Input = require(Shared:WaitForChild("Input"))
local Feedback = require(Shared:WaitForChild("Feedback"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local MovementController = {}

local player = Players.LocalPlayer

local MOVE = Config.Movement or {}

local function num(tbl: any, key: string, default: number): number
	local v = if type(tbl) == "table" then tbl[key] else nil
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local STAM_CFG = MOVE.Stamina or {}
local SLIDE_CFG = MOVE.Slide or {}
local MANTLE_CFG = MOVE.Mantle or {}
local CLIMB_CFG = MOVE.Climb or {}
local STANCE_CFG = MOVE.Stance or {}
local SLOPE_CFG = MOVE.Slope or {}
local SWIM_CFG = MOVE.Swim or {}

-- Speeds (studs/s). The default pace is a jog; analog sticks walk below full deflection.
local SPD = {
	Walk = num(MOVE, "WalkSpeed", 13),
	Sprint = num(MOVE, "SprintSpeed", 21),
	Crouch = num(MOVE, "CrouchSpeed", 6.5),
	Climb = num(MOVE, "ClimbSpeed", 5.5),
	UseItem = num(MOVE, "UseItemSpeed", 8),
	AimMult = num(MOVE, "AimSpeedMultiplier", 0.8),
	Backpedal = num(MOVE, "BackpedalMultiplier", 0.68),
	Strafe = num(MOVE, "StrafeMultiplier", 0.88),
	SprintCos = math.cos(math.rad(num(MOVE, "SprintMaxAngle", 50))),
	ExhaustedMult = num(MOVE, "ExhaustedSpeedMultiplier", 0.9),
	FatigueSprint = num(MOVE, "FatigueSprintMultiplier", 0.86), -- sprint speed with an almost empty tank
}
-- Momentum (studs/s^2)
local ACC = {
	Push = num(MOVE, "PushAcceleration", 48),
	Power = num(MOVE, "RunPower", 340),
	Brake = num(MOVE, "BrakeAcceleration", 34),
	BrakePerSpeed = num(MOVE, "BrakePerSpeed", 0.9),
	Turn = num(MOVE, "TurnAcceleration", 95),
	AirControl = num(MOVE, "AirControl", 0.22),
	AirDrag = num(MOVE, "AirDrag", 0.4),
}
-- Jumping, air and landing
local JMP = {
	Height = num(MOVE, "JumpHeight", 3),
	Cooldown = num(MOVE, "JumpCooldown", 0.4),
	Stamina = num(MOVE, "JumpStaminaCost", 0.08),
	ExhaustedScale = num(MOVE, "ExhaustedJumpScale", 0.8),
	Coyote = num(MOVE, "CoyoteTime", 0.1),
	Buffer = num(MOVE, "JumpBufferTime", 0.12),
	RiseGravity = num(MOVE, "AirGravity", 125),
	FallScale = num(MOVE, "FallGravityScale", 1.08),
	RepeatWindow = num(MOVE, "RepeatJumpWindow", 0.45),
	RepeatScale = num(MOVE, "RepeatJumpScale", 0.8),
	StickTime = 0.1, -- walking off a step: full gravity this long, so slopes and stairs don't float you
	StunHeight = num(MOVE, "LandingStunHeight", 5),
	HardHeight = num(MOVE, "HardLandingHeight", 10),
	MaxLoss = num(MOVE, "LandingMaxSpeedLoss", 0.55),
	HopSpeedLoss = num(MOVE, "LandingHopSpeedLoss", 0.06),
	StepWalk = num(MOVE, "StepLengthWalk", 2.3), -- the walk clip's step length (studs)
	StepRun = num(MOVE, "StepLengthRun", 4.85), -- the run clip's step length
	PrepTime = num(MOVE, "JumpPrepTime", 0.1), -- a standing jump starts with a short knee dip...
	PrepTimeMoving = num(MOVE, "JumpPrepTimeMoving", 0.06), -- ...shorter on the move (momentum carries you)
	GroundTime = num(MOVE, "JumpGroundTime", 0.2), -- after a landing the feet are down this long before the next take-off
}
JMP.FallGravity = JMP.RiseGravity * JMP.FallScale
-- Stamina
local STA = {
	SprintDrain = num(STAM_CFG, "SprintDrain", 0.11),
	ClimbDrain = num(STAM_CFG, "ClimbDrain", 0.09),
	Regen = num(STAM_CFG, "Regen", 0.2),
	RegenDelay = num(STAM_CFG, "RegenDelay", 1),
	IdleBonus = num(STAM_CFG, "IdleRegenBonus", 1.35),
	Threshold = num(STAM_CFG, "ExhaustedThreshold", 0.25),
	MantleBase = num(STAM_CFG, "MantleCost", 0.03),
	MantlePerStud = num(STAM_CFG, "MantleCostPerStud", 0.012),
}
-- Slopes
local SLOPE = {
	MaxWalkable = num(SLOPE_CFG, "MaxWalkableAngle", 46),
	Uphill = num(SLOPE_CFG, "UphillSlowdown", 0.9),
	Downhill = num(SLOPE_CFG, "DownhillBoost", 0.55),
	BoostSin = math.sin(math.rad(num(SLOPE_CFG, "DownhillBoostMaxAngle", 15))),
	SteepBrake = num(SLOPE_CFG, "SteepDownhillBrake", 1),
	StumbleSin = math.sin(math.rad(num(SLOPE_CFG, "StumbleAngle", 18))),
	StumbleRate = num(SLOPE_CFG, "StumbleRate", 4),
	UphillDrain = num(SLOPE_CFG, "UphillStaminaDrain", 0.12),
	UphillDrainSin = math.sin(math.rad(num(SLOPE_CFG, "UphillDrainAngle", 15))),
	SlideAccel = num(SLOPE_CFG, "SlideAcceleration", 38),
	SlideFriction = num(SLOPE_CFG, "SlideFriction", 0.55),
	SlideMax = num(SLOPE_CFG, "SlideMaxSpeed", 26),
}
SLOPE.MaxCos = math.cos(math.rad(SLOPE.MaxWalkable))
SLOPE.MaxSin = math.sin(math.rad(SLOPE.MaxWalkable))
SLOPE.FadeSin = math.sin(math.rad(SLOPE.MaxWalkable - 6)) -- uphill headway fades to nothing from here...
SLOPE.FadeCos = math.cos(math.rad(SLOPE.MaxWalkable - 6)) -- ...when the ground ahead really is that steep
SLOPE.RecoverCos = math.cos(math.rad(math.max(5, SLOPE.MaxWalkable - 5)))
-- Swimming and wading
local SWM = {
	Speed = num(MOVE, "SwimSpeed", 8),
	Sprint = num(SWIM_CFG, "SprintSpeed", 11.5),
	Stroke = math.max(1, num(SWIM_CFG, "StrokeLength", 5.5)),
	Pulse = math.clamp(num(SWIM_CFG, "StrokePulse", 0.35), 0, 0.9),
	SprintDrain = num(SWIM_CFG, "SprintDrain", 0.07),
	ExitMax = num(SWIM_CFG, "ExitMaxHeight", 3.8),
	WadeStart = num(SWIM_CFG, "WadeStartDepth", 0.35),
	WadeFull = num(SWIM_CFG, "WadeFullDepth", 3.2),
	WadeSlow = num(SWIM_CFG, "WadeMaxSlowdown", 0.55),
}
-- Stance
local ST = {
	CrouchHeadTop = num(STANCE_CFG, "CrouchHeadTop", 4.3),
	Blend = math.max(0.02, num(STANCE_CFG, "BlendTime", 0.16)),
}
-- Slide
local SL = {
	MinEntry = num(SLIDE_CFG, "MinEntrySpeed", 15),
	Boost = num(SLIDE_CFG, "Boost", 1.15),
	Max = num(SLIDE_CFG, "MaxSpeed", 28),
	Friction = num(SLIDE_CFG, "Friction", 15),
	SlopeAccel = num(SLIDE_CFG, "SlopeAcceleration", 40),
	MaxTime = num(SLIDE_CFG, "MaxTime", 1.2),
	MinTime = num(SLIDE_CFG, "MinTime", 0.35),
	DownhillTime = num(SLIDE_CFG, "DownhillTimeScale", 0.35),
	HardCap = num(SLIDE_CFG, "HardMaxTime", 3.5),
	Steer = num(SLIDE_CFG, "SteerRate", 1.2),
	Cooldown = num(SLIDE_CFG, "Cooldown", 0.7),
	EndSpeed = num(SLIDE_CFG, "EndSpeed", 8),
}
-- Mantle and vault
local MT = {
	Min = num(MANTLE_CFG, "MinHeight", 2.2),
	Max = num(MANTLE_CFG, "MaxHeight", 6.5),
	AirMax = num(MANTLE_CFG, "MaxHeightFromJump", 7.8), -- above the take-off ground: a jump-and-grab
	Reach = num(MANTLE_CFG, "Reach", 3.2),
	Grab = num(MANTLE_CFG, "GrabDistance", 1.9),
	PushTime = num(MANTLE_CFG, "PushTime", 0.18),
	TimeLow = num(MANTLE_CFG, "TimeLow", 0.45),
	Time = num(MANTLE_CFG, "Time", 0.8),
	VaultMin = num(MANTLE_CFG, "VaultMinHeight", 1.3),
	VaultMax = num(MANTLE_CFG, "VaultMaxHeight", 3.4),
	VaultTime = num(MANTLE_CFG, "VaultTime", 0.36),
}
-- Climb
local CL = {
	Reach = num(CLIMB_CFG, "Reach", 2.5),
	StandOff = num(CLIMB_CFG, "StandOff", 0.85),
	Lateral = num(CLIMB_CFG, "LateralFactor", 0.6),
	PushSpeed = num(CLIMB_CFG, "PushOffSpeed", 12),
	PushUp = num(CLIMB_CFG, "PushOffUp", 22),
	EntryTime = num(CLIMB_CFG, "EntryPushTime", 0.15),
	Stroke = math.max(0.5, num(CLIMB_CFG, "StrokeLength", 2.6)),
	Pulse = math.clamp(num(CLIMB_CFG, "StrokePulse", 0.6), 0, 0.9),
}

-- Surfaces: speed multiplier, grip (accel/brake/turn multiplier) and effort (stamina multiplier).
-- Anything not listed (rock, slate, basalt, cobblestone, concrete, brick, asphalt...) is firm ground.
local SURFACE_DEFAULTS = {
	Grass = { Speed = 1, Grip = 0.95, Effort = 1 },
	LeafyGrass = { Speed = 0.95, Grip = 0.9, Effort = 1.08 },
	Ground = { Speed = 1, Grip = 1, Effort = 1 },
	Mud = { Speed = 0.72, Grip = 0.5, Effort = 1.45 },
	Sand = { Speed = 0.84, Grip = 0.72, Effort = 1.3 },
	Snow = { Speed = 0.8, Grip = 0.6, Effort = 1.35 },
	Glacier = { Speed = 0.95, Grip = 0.28, Effort = 1.1 },
	Ice = { Speed = 0.95, Grip = 0.2, Effort = 1.1 },
	Salt = { Speed = 0.96, Grip = 0.85, Effort = 1.05 },
	Pebble = { Speed = 0.94, Grip = 0.82, Effort = 1.1 },
	SmoothPlastic = { Speed = 1, Grip = 0.85, Effort = 1 },
	Plastic = { Speed = 1, Grip = 0.9, Effort = 1 },
	Metal = { Speed = 1, Grip = 0.85, Effort = 1 },
	Marble = { Speed = 1, Grip = 0.8, Effort = 1 },
	Glass = { Speed = 1, Grip = 0.7, Effort = 1 },
	Foil = { Speed = 1, Grip = 0.7, Effort = 1 },
}
local SURFACES: { [Enum.Material]: { speed: number, grip: number, effort: number } } = {}
do
	local defs = if type(MOVE.Surfaces) == "table" then MOVE.Surfaces else SURFACE_DEFAULTS
	for name, def in pairs(defs) do
		local ok, material = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and typeof(material) == "EnumItem" and type(def) == "table" then
			SURFACES[material] = {
				speed = math.clamp(num(def, "Speed", 1), 0.2, 1.5),
				grip = math.clamp(num(def, "Grip", 1), 0.05, 1.5),
				effort = math.clamp(num(def, "Effort", 1), 0.5, 3),
			}
		end
	end
end
local FIRM = { speed = 1, grip = 1, effort = 1 }

-- Avatar size. Config.Movement was tuned on the classic R15 rig (5.2 studs tall, 1.75-stud legs from hip to ankle);
-- the walk/run clip strides were measured on a rig with 2.42-stud legs (ServerStorage.Dev.TrainingDummy).
local REF_STAND_HEIGHT = 5.2
local REF_LEGS = 1.75
local STRIDE_REF_LEGS = 2.42

local HumanoidState = Enum.HumanoidStateType
local RISE_BOX = Vector3.new(1.5, 0.2, 0.75)
local GROUND_PROBES = { 1.0, 2.4 }
local AIR_PROBES = { 0.35, 1.4 }
local SWIM_PROBES = { 1.6, 2.5 }
local TOP_INSETS = { 0.55, 0.15 } -- where the top of a ledge is looked for, beyond its face
local JOINT_NAMES = {
	Root = true, Waist = true, Neck = true, LeftHip = true, RightHip = true, LeftKnee = true, RightKnee = true,
	LeftAnkle = true, RightAnkle = true, LeftShoulder = true, RightShoulder = true, LeftElbow = true, RightElbow = true,
}

-- Query params (the local character is excluded once it spawns)
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.IgnoreWater = true
worldParams.RespectCanCollide = true

local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
waterParams.IgnoreWater = false
waterParams.RespectCanCollide = true

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true

-- Registry / environment
local Controllers = nil
local setStanceRemote: RemoteEvent? = nil
local moveSrc = {
	action = nil :: Instance?, jump = nil :: Instance?, controls = nil :: any,
	nextScan = 0, scans = 0, kind = "none", warned = false, fallback = false,
}

-- Per-character context: { character, humanoid, root, rig, baseHip, lastSetHip, conns, attachment, gravity, gravityMode, dead }
local ctx = nil

-- Input state
local sprintHeld, sprintToggled, sprintToggleSource = false, false, nil
local sprintJogHeld = false -- sprint mode Auto: holding the sprint key jogs instead
local autoSprintBlocked = false -- stopSprint() (a draw or a throw) pauses Auto sprint until the stick is let go
local crouchHeld, crouchToggled = false, false
local crouchPressedAt = -math.huge
local jumpHeldPrev = false
local jumpPressAt = -math.huge
local inputVector = Vector3.zero
local stickIdleTime = 0
local touchVisible = true

-- Movement state
local moveState = "Idle"
local velocity = Vector3.zero -- commanded horizontal velocity (our momentum)
local swimVelocity = Vector3.zero
local stamina, exhausted = 1, false
local lastDrainAt = -math.huge
local crouchAmt, slideAmt, climbAmt = 0, 0, 0 -- linear blends
local easedCrouch, easedSlide, easedClimb = 0, 0, 0 -- smoothstepped blends (hitbox + pose)
local crouchForced = false
local slide = nil -- { kind = "Slide" | "Slope", time, age, dir, blockedTime, airTime, recover }
local slideCooldownUntil = 0
local mantle = nil
local climb = nil
local lastKinematicEndAt = -math.huge
local stridePhase, lastStepAt, wasMoving = 0, -math.huge, false
local lastRootPos: Vector3? = nil
local sentStance, lastStanceSentAt = nil, -math.huge
local jumpEnabledState = nil
local lastJumpHeight = nil
local blendOut = { crouch = 0, slide = 0, climb = 0, climbPhase = 0, land = 0, prep = 0 }
local errorAt = -math.huge

-- Air / landing / stumble bookkeeping
local AIR = {
	airborne = false, minVy = 0, jumped = false, coyoteUntil = 0, lastJumpAt = -math.huge, wishSpeed = 13,
	startAt = 0, takeoffY = 0, lastLandAt = -math.huge, lastLandWasJump = false,
	stunUntil = 0, stunScale = 1, bufferedJump = false, landSlide = false, mantleStep = nil,
	stumbleUntil = 0, instability = 0, armed = false,
	prepAt = nil :: number?, prepTime = 0.1, jumpWanted = nil :: number?, firedAt = -math.huge,
}
-- Pushing into ledges / climbables / banks
local PUSH = { mantle = 0, climb = 0, swim = 0 }
-- Ground and water probes (this frame) and the smoothed surface response
local G = {
	hit = false, normal = Vector3.yAxis, material = Enum.Material.Air, y = 0, dist = math.huge,
	alongSin = 0, alongSmooth = 0, steepTime = 0, aheadNY = 1,
}
local W = { depth = 0, surfaceY = -math.huge, inWater = false }
local SURF = { speed = 1, grip = 1, effort = 1, name = "Ground" }
-- Live readings for the camera and body layers
local motion = { accel = Vector3.zero, exertion = 0, surface = "Ground", slope = 0, stumble = 0, wade = 0, land = 0 }
local prevVel = Vector3.zero
local landPose = 0 -- 0..1 knee compression after a landing (decays)
local prepPose = 0 -- 0..1 knee dip before a take-off
local debugOut = {}
local debugNextAt = 0
local lastUpdateAt = -math.huge
local recovered = false

-- Helpers ----------------------------------------------------------------------------------------------------------

local function approach(current: number, target: number, maxDelta: number): number
	if current < target then
		return math.min(target, current + maxDelta)
	end
	return math.max(target, current - maxDelta)
end

local function smooth01(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function setState(new: string)
	if new == moveState then
		return
	end
	local old = moveState
	moveState = new
	ClientState.moveState = new
	ClientState.moveStateChanged:Fire(new, old)
end

local function hasTagUp(inst: Instance?, tag: string): boolean
	local depth = 0
	local node = inst
	while node and node ~= workspace and depth < 5 do
		if node:HasTag(tag) then
			return true
		end
		node = node.Parent
		depth += 1
	end
	return false
end

-- Trusses are left to the native Humanoid ladder climb.
local function isClimbableHit(inst: Instance?): boolean
	if not inst or inst:IsA("TrussPart") then
		return false
	end
	return hasTagUp(inst, "Climbable")
end

local function validLedgeSurface(inst: Instance?): boolean
	if not inst then
		return false
	end
	if inst == workspace.Terrain then
		return true
	end
	if not inst:IsA("BasePart") then
		return false
	end
	if inst.Transparency >= 0.98 then
		return false -- invisible barriers
	end
	if hasTagUp(inst, "NoMantle") then
		return false
	end
	if Util.humanoidFromPart(inst) then
		return false -- characters and NPCs
	end
	local s = inst.Size
	if math.max(s.X, s.Y, s.Z) < 1.2 or s.X * s.Y * s.Z < 0.8 then
		return false -- tiny props
	end
	return true
end

local function flatBasis(cf: CFrame): (Vector3, Vector3)
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		local up = cf.UpVector
		flat = Vector3.new(up.X, 0, up.Z) * (if look.Y > 0 then -1 else 1)
	end
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	return flat, Vector3.new(-flat.Z, 0, flat.X)
end

local function cameraCFrame(): CFrame
	local camCtrl = Controllers and Controllers.CameraController
	if camCtrl and type(camCtrl.getBaseCFrame) == "function" then
		local cf = camCtrl.getBaseCFrame()
		if typeof(cf) == "CFrame" then
			return cf
		end
	end
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame else CFrame.identity
end

local function isFirstPerson(): boolean
	local camCtrl = Controllers and Controllers.CameraController
	if camCtrl and type(camCtrl.isFirstPerson) == "function" then
		return camCtrl.isFirstPerson() == true
	end
	return player.CameraMode == Enum.CameraMode.LockFirstPerson
end

local function facingRotation(fallbackDir: Vector3): CFrame
	local dir = fallbackDir
	if isFirstPerson() then
		dir = flatBasis(cameraCFrame())
	end
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAlong(Vector3.zero, dir)
end

-- Move input -------------------------------------------------------------------------------------------------------

local function findAction(container: Instance?, name: string): Instance?
	local contexts = container and container:FindFirstChild("InputContexts")
	local character = contexts and contexts:FindFirstChild("CharacterContext")
	local action = character and character:FindFirstChild(name)
	if action and action:IsA("InputAction") then
		return action
	end
	return nil
end

-- Cheap, non-blocking discovery of the move source (called from the frame update until something is found).
local function scanMoveSource(t: number)
	moveSrc.scans += 1
	moveSrc.nextScan = t + (if moveSrc.scans < 40 then 0.5 else 3)
	local playerModule = StarterPlayer:FindFirstChild("PlayerModule")
	local action = findAction(player, "MoveAction") or findAction(playerModule, "MoveAction")
	if action then
		moveSrc.action = action
		local jump = action.Parent and action.Parent:FindFirstChild("JumpAction")
		moveSrc.jump = if jump and jump:IsA("InputAction") then jump else nil
		moveSrc.controls = nil
		moveSrc.kind = "InputAction"
		return
	end
	-- legacy PlayerModule (PlayerScripts.PlayerModule:GetControls())
	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	local legacy = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if legacy and legacy:IsA("ModuleScript") then
		local okRequire, module = pcall(require, legacy)
		if okRequire and type(module) == "table" and type(module.GetControls) == "function" then
			local okControls, controls = pcall(function()
				return module:GetControls()
			end)
			if okControls and type(controls) == "table" and type(controls.GetMoveVector) == "function" then
				moveSrc.controls = controls
				moveSrc.kind = "ControlModule"
				return
			end
		end
	end
	if moveSrc.scans == 20 and not moveSrc.warned then
		moveSrc.warned = true
		warn("[MovementController] no MoveAction or PlayerModule controls found yet; using raw keys until one appears")
	end
end

local function keyDown(code: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(code)
end

local function rawKeysAllowed(): boolean
	return UserInputService:GetFocusedTextBox() == nil and not GuiService.MenuIsOpen
end

local function readMoveVector(t: number): Vector3
	local mv = Vector3.zero
	local action = moveSrc.action
	if action and not action.Parent then
		moveSrc.action, moveSrc.jump, moveSrc.kind = nil, nil, "none"
		moveSrc.scans, moveSrc.nextScan = 0, 0
		action = nil
	end
	if action then
		local ok, v = pcall((action :: any).GetState, action)
		if ok and typeof(v) == "Vector2" then
			mv = Vector3.new(v.X, 0, -v.Y)
		end
	elseif moveSrc.controls then
		local ok, v = pcall(moveSrc.controls.GetMoveVector, moveSrc.controls)
		if ok and typeof(v) == "Vector3" then
			mv = Vector3.new(v.X, 0, v.Z)
		end
	end
	if not action and not moveSrc.controls and t >= moveSrc.nextScan then
		scanMoveSource(t)
	end
	-- raw keys: only if nothing else moves us (and never when a script disabled the controls on purpose:
	-- the ControlModule mirrors PlayerModule.ControlModule.Enabled onto the action)
	moveSrc.fallback = false
	local disabledOnPurpose = action ~= nil and (action :: any).Enabled == false
	if mv.Magnitude < 0.01 and not disabledOnPurpose and rawKeysAllowed() then
		local f = (if keyDown(Enum.KeyCode.W) or keyDown(Enum.KeyCode.Up) then 1 else 0)
			- (if keyDown(Enum.KeyCode.S) or keyDown(Enum.KeyCode.Down) then 1 else 0)
		local r = (if keyDown(Enum.KeyCode.D) then 1 else 0) - (if keyDown(Enum.KeyCode.A) then 1 else 0)
		if f ~= 0 or r ~= 0 then
			mv = Vector3.new(r, 0, -f)
			moveSrc.fallback = true
		end
	end
	if mv.Magnitude > 1 then
		mv = mv.Unit
	end
	return mv
end

-- Jump input: the default controls set Humanoid.Jump; without a working source we read JumpAction / Space.
local function readJumpHeld(humanoid: Humanoid): boolean
	if humanoid.Jump then
		return true
	end
	local jump = moveSrc.jump
	if jump and jump.Parent then
		local ok, v = pcall((jump :: any).GetState, jump)
		if ok and v == true then
			return true
		end
	end
	if (moveSrc.kind == "none" or moveSrc.fallback) and rawKeysAllowed() and keyDown(Enum.KeyCode.Space) then
		return true
	end
	return false
end

local function setSprintToggle(on: boolean)
	sprintToggled = on
	if not on then
		sprintToggleSource = nil
	end
	Input.setToggle("Sprint", on)
end

local function setCrouchToggle(on: boolean)
	crouchToggled = on
	Input.setToggle("Crouch", on)
end

-- Sprint and crouch modes per device (ClientState.settings; SettingsController rows, PlayabilityPlan QW13):
-- sprint 0 Hold, 1 Toggle, 2 Auto (a full push sprints while you have stamina; holding the key jogs); crouch 0 Hold,
-- 1 Toggle. Defaults: keyboard Hold / Hold, gamepad Toggle / Toggle (L3, B), touch Auto / Toggle (RUN hides on Auto).
local AUTO_SPRINT_PUSH = 0.9 -- stick deflection (or a held W) that counts as a full push
local MODE_KEYS = {
	sprint = { KeyboardMouse = "sprintMode", Gamepad = "sprintModePad", Touch = "sprintModeTouch" },
	crouch = { KeyboardMouse = "crouchMode", Gamepad = "crouchModePad", Touch = "crouchModeTouch" },
}
local MODE_DEFAULTS = {
	sprint = { KeyboardMouse = 0, Gamepad = 1, Touch = 2 },
	crouch = { KeyboardMouse = 0, Gamepad = 1, Touch = 1 },
}

local function modeFor(kind: string, device: string): number
	local keys, defaults = MODE_KEYS[kind], MODE_DEFAULTS[kind]
	local v = tonumber(ClientState.settings[keys[device] or keys.KeyboardMouse])
	if v == nil or v ~= v then
		return defaults[device] or 0
	end
	return math.floor(v + 0.5)
end

local function deviceOf(io: InputObject?): string
	if io then
		if io.UserInputType == Enum.UserInputType.Touch then
			return "Touch"
		elseif string.sub(io.UserInputType.Name, 1, 7) == "Gamepad" or io.KeyCode == Enum.KeyCode.ButtonL3
			or io.KeyCode == Enum.KeyCode.ButtonB then
			return "Gamepad"
		end
	end
	return "KeyboardMouse"
end

local function setJumpEnabled(humanoid: Humanoid, on: boolean)
	if jumpEnabledState ~= on then
		jumpEnabledState = on
		humanoid:SetStateEnabled(HumanoidState.Jumping, on)
	end
end

local function stateSpeedFor(state: string): number
	if state == "Sprint" or state == "Slide" then
		return SPD.Sprint
	elseif state == "Crouch" then
		return SPD.Crouch
	end
	return SPD.Walk
end

-- Humanoid.JumpHeight is converted to a take-off speed with workspace.Gravity; our air gravity is lighter.
local function humanoidJumpHeight(apex: number): number
	local g = math.max(workspace.Gravity, 1)
	local v0 = math.sqrt(2 * JMP.RiseGravity * math.max(apex, 0))
	return v0 * v0 / (2 * g)
end

-- Equivalent drop height of a landing at `impact` studs/s under our fall gravity.
local function dropHeight(impact: number): number
	return impact * impact / (2 * JMP.FallGravity)
end

-- Rig measurement ---------------------------------------------------------------------------------------------------

function MovementController.findJoints(character: Model): { [string]: Instance }
	local joints = {}
	-- AnimationConstraint (Avatar Joint Upgrade) first, Motor6D for older rigs
	for _, className in ipairs({ "AnimationConstraint", "Motor6D" }) do
		for _, d in ipairs(character:GetDescendants()) do
			if JOINT_NAMES[d.Name] and joints[d.Name] == nil and d:IsA(className) then
				local parent = d.Parent
				if parent and parent.Parent == character then
					joints[d.Name] = d
				end
			end
		end
	end
	return joints
end

function MovementController.measureRig(character: Model, humanoid: Humanoid, standingHip: number?)
	local root = humanoid.RootPart or character:FindFirstChild("HumanoidRootPart")
	local hip = standingHip or humanoid.HipHeight
	local rig = {
		r15 = humanoid.RigType == Enum.HumanoidRigType.R15,
		hip = hip,
		rootHalf = if root and root:IsA("BasePart") then root.Size.Y / 2 else 1,
		headCenter = Vector3.new(0, 1.5, 0),
		headTop = 2.1,
		torsoTop = 1.05,
		rootPivotY = -1,
		waistPivotY = -0.65,
		thigh = math.max(0.3, hip * 0.42),
		shin = math.max(0.3, hip * 0.46),
		crouchDrop = 0,
		slideDrop = 0,
		standHeight = 0,
		joints = MovementController.findJoints(character),
	}
	local j = rig.joints
	pcall(function()
		local rootJ, waist, neck = j.Root :: any, j.Waist :: any, j.Neck :: any
		if rootJ and waist and neck then
			local lower = rootJ.C0 * rootJ.C1:Inverse()
			local upper = lower * waist.C0 * waist.C1:Inverse()
			local head = upper * neck.C0 * neck.C1:Inverse()
			local headPart = character:FindFirstChild("Head")
			local upperPart = character:FindFirstChild("UpperTorso")
			rig.headCenter = head.Position
			rig.headTop = head.Position.Y + (if headPart and headPart:IsA("BasePart") then headPart.Size.Y / 2 else 0.6)
			rig.torsoTop = upper.Position.Y + (if upperPart and upperPart:IsA("BasePart") then upperPart.Size.Y / 2 else 0.85)
			rig.rootPivotY = rootJ.C0.Position.Y
			rig.waistPivotY = (lower * waist.C0).Position.Y
		end
		local hipJ, knee, ankle = j.LeftHip :: any, j.LeftKnee :: any, j.LeftAnkle :: any
		if hipJ and knee and ankle then
			rig.thigh = math.max(0.3, (hipJ.C1.Position - knee.C0.Position).Magnitude)
			rig.shin = math.max(0.3, (knee.C1.Position - ankle.C0.Position).Magnitude)
		end
	end)
	rig.standHeight = hip + rig.rootHalf + rig.headTop
	rig.legs = rig.thigh + rig.shin
	-- size against the tuning rig: ledge reach and probe heights follow the body, the stride follows the legs
	rig.scale = math.clamp(rig.standHeight / REF_STAND_HEIGHT, 0.75, 1.35)
	rig.legScale = math.clamp(rig.legs / REF_LEGS, 0.6, 1.6)
	rig.strideScale = math.clamp(rig.legs / STRIDE_REF_LEGS, 0.4, 1.4)
	if rig.r15 and j.Root and j.LeftHip and j.LeftKnee then
		-- low enough to fit under CrouchHeadTop-high gaps where the legs allow it, never shallower than the tuning
		-- rig's crouch in proportion (45% of the hip height), never deeper than the knees can fold (~125 degrees)
		local crouch = math.clamp(math.max(rig.standHeight - ST.CrouchHeadTop, hip * 0.45), hip * 0.3,
			math.max(hip * 0.3, math.min(hip * 0.62, rig.legs * 0.55)))
		-- the slide keeps the crouch hitbox (the lean-back pose makes it look lower) so the legs have room
		local slideDrop = math.clamp(crouch, 0, math.max(0, hip - 0.5))
		-- Avatar Settings single box collider: keep its underside above the ground
		local collider = character:FindFirstChild("CollisionPart")
		if collider and collider:IsA("BasePart") and root and root:IsA("BasePart") then
			local rel = root.CFrame:PointToObjectSpace(collider.Position)
			local limit = math.max(0, hip + rig.rootHalf + rel.Y - collider.Size.Y / 2 - 0.15)
			crouch = math.min(crouch, limit)
			slideDrop = math.min(slideDrop, limit)
		end
		rig.crouchDrop = math.max(0, crouch)
		rig.slideDrop = math.max(rig.crouchDrop, slideDrop)
	end
	return rig
end

-- Probes -------------------------------------------------------------------------------------------------------------

local DOWN_EXTRA = 2.2

-- Ground under the root (normal, material, gap below the feet) and the slope along the direction of travel.
local function probeGround(c, travel: Vector3)
	local root, humanoid = c.root, c.humanoid
	local pos = root.Position
	local legs = humanoid.HipHeight + c.rig.rootHalf
	local len = legs + DOWN_EXTRA
	local hit = workspace:Raycast(pos, Vector3.new(0, -len, 0), worldParams)
	if hit then
		G.hit = true
		G.normal = hit.Normal
		G.material = hit.Material
		G.y = hit.Position.Y
		G.dist = hit.Distance - legs
	else
		G.hit = false
		G.normal = Vector3.yAxis
		G.material = humanoid.FloorMaterial
		G.y = pos.Y - legs
		G.dist = math.huge
	end
	local along = 0
	G.aheadNY = 1
	if hit and travel.Magnitude > 0.1 then
		local d = Vector3.new(travel.X, 0, travel.Z).Unit
		local ahead = workspace:Raycast(pos + d * 1.1, Vector3.new(0, -(len + 1.2), 0), worldParams)
		local behind = workspace:Raycast(pos - d * 1.1, Vector3.new(0, -(len + 1.2), 0), worldParams)
		if ahead then
			G.aheadNY = ahead.Normal.Y
		end
		if ahead and behind and ahead.Normal.Y > 0.25 and behind.Normal.Y > 0.25 then
			local rise = ahead.Position.Y - behind.Position.Y
			along = rise / math.sqrt(rise * rise + 4.84)
		else
			local n = hit.Normal
			local tanA = -(n.X * d.X + n.Z * d.Z) / math.max(n.Y, 0.1)
			along = tanA / math.sqrt(1 + tanA * tanA)
		end
	end
	G.alongSin = math.clamp(along, -0.95, 0.95)
end

-- Water depth above the ground where we stand (wading), and the water surface height.
local function probeWater(c)
	local root = c.root
	local pos = root.Position
	local legs = c.humanoid.HipHeight + c.rig.rootHalf
	local top = 3.2
	local hit = workspace:Raycast(pos + Vector3.new(0, top, 0), Vector3.new(0, -(top + legs + 0.6), 0), waterParams)
	if hit and hit.Material == Enum.Material.Water then
		W.inWater = true
		W.surfaceY = hit.Position.Y
		W.depth = math.max(0, W.surfaceY - G.y)
	else
		W.inWater = false
		W.depth = 0
	end
end

-- Smoothed surface response (grip changes over ~0.2 s instead of snapping between materials)
local function updateSurface(dt: number, grounded: boolean)
	local s = SURFACES[G.material] or FIRM
	local speed, grip, effort = s.speed, s.grip, s.effort
	if W.depth > 0.15 then
		grip = math.min(grip, 0.85) -- wet footing
	end
	if not grounded then
		-- keep the last ground's response while airborne
		return
	end
	local k = expAlpha(10, dt)
	SURF.speed += (speed - SURF.speed) * k
	SURF.grip += (grip - SURF.grip) * k
	SURF.effort += (effort - SURF.effort) * k
	SURF.name = G.material.Name
end

local function footstepMaterial(c): Enum.Material
	if W.depth > 0.25 then
		return Enum.Material.Water
	end
	local m = G.material
	if m == Enum.Material.Air then
		m = c.humanoid.FloorMaterial
	end
	return m
end

local function emitFootstep(c, foot: string, scale: number, t: number, speed: number, material: Enum.Material?)
	local base, ref = 0.55, SPD.Walk
	if moveState == "Sprint" then
		base, ref = 0.95, SPD.Sprint
	elseif moveState == "Crouch" then
		base, ref = 0.25, SPD.Crouch
	elseif moveState == "Swim" then
		base, ref = 0.45, SWM.Speed
	elseif moveState == "Climb" then
		base, ref = 0.35, SPD.Climb
	end
	local intensity = math.clamp(base * math.clamp(speed / ref, 0.6, 1.15) * scale, 0.05, 1)
	lastStepAt = t
	local mat = material or (if moveState == "Swim" then Enum.Material.Water else footstepMaterial(c))
	ClientState.footstep:Fire(mat, intensity, foot)
end

-- Is there room to stand back up? (cast up from the collidable torso to the standing head height)
local function hasStandingRoom(c): boolean
	local humanoid, root, rig = c.humanoid, c.root, c.rig
	local missing = c.baseHip - humanoid.HipHeight
	if missing <= 0.05 then
		return true
	end
	local fwd = flatBasis(root.CFrame)
	local origin = root.Position + Vector3.new(0, rig.torsoTop - 0.15, 0)
	local cf = CFrame.lookAlong(origin, fwd)
	local reach = (rig.headTop - rig.torsoTop) + missing + 0.15
	return workspace:Blockcast(cf, RISE_BOX, Vector3.new(0, reach, 0), worldParams) == nil
end

-- Direction from a climbable surface back toward the climber. Trunk-sized parts use the direction from their
-- axis (smooth all the way round, ignoring faceted root flares); big climbable walls use the surface normal.
local function climbNormal(hit: RaycastResult, fromPos: Vector3): Vector3?
	local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	local part = hit.Instance
	if part:IsA("BasePart") and part ~= workspace.Terrain then
		local cf, s = part.CFrame, part.Size
		local ex = math.abs(cf.XVector.X) * s.X + math.abs(cf.YVector.X) * s.Y + math.abs(cf.ZVector.X) * s.Z
		local ez = math.abs(cf.XVector.Z) * s.X + math.abs(cf.YVector.Z) * s.Y + math.abs(cf.ZVector.Z) * s.Z
		if ex <= 12 and ez <= 12 then
			local axis = Vector3.new(fromPos.X - cf.Position.X, 0, fromPos.Z - cf.Position.Z)
			if axis.Magnitude > 0.2 then
				n = axis
			end
		end
	end
	if n.Magnitude < 0.2 then
		return nil
	end
	return n.Unit
end

local function probeClimbable(c, dir: Vector3): (RaycastResult?, Vector3?)
	local root, humanoid = c.root, c.humanoid
	local pos = root.Position
	local feetY = pos.Y - (humanoid.HipHeight + c.rig.rootHalf)
	local sc = c.rig.scale or 1
	for _, h in ipairs({ 2.4, 1.2, 3.6 }) do
		local origin = Vector3.new(pos.X, feetY + h * sc, pos.Z)
		local r = workspace:Raycast(origin, dir * (0.5 + CL.Reach * sc), worldParams)
		if r and isClimbableHit(r.Instance) and math.abs(r.Normal.Y) < 0.8 then
			local n = climbNormal(r, pos)
			if n and n:Dot(dir) < -0.35 then
				return r, n
			end
		end
	end
	return nil, nil
end

-- Find a ledge to mantle or an obstacle to vault in direction `dir`.
-- mode: "ground" (MinHeight..MaxHeight), "vault" (VaultMinHeight..VaultMaxHeight), "air" (0.4..MaxHeight),
--       "swim" (a bank up to ExitMaxHeight above the water surface)
local function findLedge(c, dir: Vector3, mode: string, maxWallDist: number)
	local root, humanoid, rig = c.root, c.humanoid, c.rig
	local rootPos = root.Position
	local feetY = rootPos.Y - (humanoid.HipHeight + rig.rootHalf)
	local sc = rig.scale or 1 -- reach follows the body: a taller contender gets onto higher ledges
	local minH, maxH, facing = MT.Min * sc, MT.Max * sc, -0.45
	local probes = GROUND_PROBES
	if mode == "air" then
		minH = 0.4
		probes = AIR_PROBES
		-- a jump only gets your hands so high: the ledge must be within reach of the take-off ground
		maxH = math.min(MT.Max * sc, AIR.takeoffY + MT.AirMax * sc - feetY)
		if maxH < minH then
			return nil
		end
	elseif mode == "vault" then
		minH, maxH, facing = math.max(MT.VaultMin * sc, 1), MT.VaultMax * sc, -0.7
	elseif mode == "swim" then
		if not W.inWater then
			return nil
		end
		-- measure from where the feet would be when treading water at the surface
		feetY = W.surfaceY - 2.6 * sc
		minH, maxH = 1.6 * sc, (2.6 + SWM.ExitMax) * sc
		probes = SWIM_PROBES
	end

	-- 1) a wall in front of us
	local wallHit: RaycastResult? = nil
	for _, h0 in ipairs(probes) do
		local h = h0 * sc
		if h < maxH then
			local origin = Vector3.new(rootPos.X, feetY + h, rootPos.Z)
			local r = workspace:Raycast(origin, dir * maxWallDist, worldParams)
			if r and math.abs(r.Normal.Y) < 0.6 and r.Normal:Dot(dir) < facing and validLedgeSurface(r.Instance) then
				if wallHit == nil or r.Distance < wallHit.Distance then
					wallHit = r
				end
			end
		end
	end
	if not wallHit then
		return nil
	end
	local n = Vector3.new(wallHit.Normal.X, 0, wallHit.Normal.Z)
	if n.Magnitude < 0.2 then
		return nil
	end
	local inward = -n.Unit
	local toWall = Vector3.new(wallHit.Position.X - rootPos.X, 0, wallHit.Position.Z - rootPos.Z)
	local perp = toWall:Dot(inward)
	if perp < 0.2 then
		return nil
	end

	-- 2) the top surface just beyond the face (close to the face too, so thin fences and walls count)
	local startY = feetY + maxH + 0.6
	local top: RaycastResult? = nil
	local probe = wallHit.Position
	for _, inset in ipairs(TOP_INSETS) do
		local p = wallHit.Position + inward * inset
		local r = workspace:Raycast(Vector3.new(p.X, startY, p.Z), Vector3.new(0, -(maxH + 1 - minH), 0), worldParams)
		if r and r.Normal.Y >= 0.7 and validLedgeSurface(r.Instance) then
			local h = r.Position.Y - feetY
			if h >= minH and h <= maxH then
				top, probe = r, p
				break
			end
		end
	end
	if not top then
		return nil
	end
	local topY = top.Position.Y
	local height = topY - feetY

	-- 3) the lip must be open: the wall can't continue above the top we found
	if workspace:Raycast(Vector3.new(rootPos.X, topY + 0.35, rootPos.Z), inward * (perp + 0.8), worldParams) then
		return nil
	end

	-- 4) vault over a thin obstacle, or hop onto a platform
	local kind = if mode == "vault" then "Vault" else "Mantle"
	local depth = 0
	local function topAt(dist: number): boolean
		local p = probe + inward * dist
		local r = workspace:Raycast(Vector3.new(p.X, topY + 0.6, p.Z), Vector3.new(0, -1.2, 0), worldParams)
		return r ~= nil and math.abs(r.Position.Y - topY) < 0.5
	end
	if kind == "Vault" then
		if topAt(1.45) then
			kind = "QuickMantle"
		elseif topAt(0.7) then
			depth = 1.45
		else
			depth = 0.8
		end
	end

	-- 5) clearance: rise beside the wall, then move over the edge at the final height
	local yaw = CFrame.lookAlong(Vector3.zero, inward)
	local standBody = rig.standHeight - 0.3
	local crouchBody = rig.standHeight - rig.crouchDrop - 0.3
	local crouch = false
	local needStand = topY + standBody + 0.1 - rootPos.Y
	local needCrouch = topY + crouchBody + 0.1 - rootPos.Y
	local rise = workspace:Blockcast(CFrame.new(rootPos) * yaw, RISE_BOX, Vector3.new(0, math.max(needStand, 0.2), 0), worldParams)
	if rise then
		if rig.crouchDrop <= 0 or rise.Distance < needCrouch then
			return nil
		end
		crouch = true
	end
	local distance = if kind == "Vault" then perp + depth + 0.5 + 0.75 else perp + 0.5 + 0.65
	local function pathClear(bodyH: number): (boolean, number)
		local center = Vector3.new(rootPos.X, topY + 0.18 + bodyH / 2, rootPos.Z)
		local hit = workspace:Blockcast(CFrame.new(center) * yaw, Vector3.new(1.5, bodyH, 0.75), inward * distance, worldParams)
		if not hit then
			return true, distance
		end
		return false, hit.Distance
	end
	local ok, reach = pathClear(if crouch then crouchBody else standBody)
	if not ok and not crouch and rig.crouchDrop > 0 then
		crouch = true
		ok, reach = pathClear(crouchBody)
	end
	if not ok then
		-- a mantle may stop short, as long as the whole body ends up on top
		if kind ~= "Vault" and reach - 0.1 >= perp + 1.0 then
			distance = reach - 0.1
		else
			return nil
		end
	end

	-- 6) something to stand on at the destination (vaults land beyond the obstacle instead)
	local floorY = topY
	if kind ~= "Vault" then
		local dest = rootPos + inward * distance
		local support = workspace:Raycast(Vector3.new(dest.X, topY + 0.8, dest.Z), Vector3.new(0, -1.8, 0), worldParams)
		if support and support.Normal.Y >= 0.6 then
			floorY = support.Position.Y
		elseif mode ~= "swim" and height <= MT.VaultMax * sc + 1.8 then
			-- nothing to stand on (a fence or thin wall up to ~5 studs): go up and over it instead (slower when tall)
			kind = "Vault"
			depth = if topAt(0.7) then 1.45 else 0.8
			distance = perp + depth + 0.5 + 0.75
			if not pathClear(if crouch then crouchBody else standBody) then
				return nil
			end
		else
			return nil
		end
	end

	return {
		kind = kind,
		topY = topY,
		floorY = floorY,
		height = height,
		inward = inward,
		perp = perp,
		distance = distance,
		crouch = crouch,
		material = top.Material,
		fromWater = mode == "swim",
	}
end

local function overlapsWorld(c): boolean
	for _, name in ipairs({ "HumanoidRootPart", "UpperTorso", "LowerTorso" }) do
		local part = c.character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			for _, hit in ipairs(workspace:GetPartsInPart(part, overlapParams)) do
				if hit.CanCollide and not hit:IsDescendantOf(c.character) then
					return true
				end
			end
		end
	end
	return false
end

-- Kinematic modes (mantle, vault, climb) -------------------------------------------------------------------------------

local function beginKinematic(c)
	c.humanoid.PlatformStand = true
	c.humanoid.AutoRotate = false
	c.gravityMode = "cancel"
end

local function endKinematic(c, nextState: Enum.HumanoidStateType?)
	c.gravityMode = nil
	lastKinematicEndAt = os.clock()
	if c.dead or not c.humanoid.Parent then
		return
	end
	c.humanoid.PlatformStand = false
	c.humanoid.AutoRotate = slide == nil
	if nextState then
		c.humanoid:ChangeState(nextState)
	end
end

-- Mantle path. The rise eases in (hands take the weight), presses through the middle and settles at the top;
-- the forward move waits until the body clears the lip.
local function mantlePosition(m, u: number): Vector3
	local s = math.min(1, u / m.riseEnd)
	local e
	if m.linear then
		e = 1 - (1 - s) * (1 - s)
	else
		-- smootherstep: zero velocity at both ends, no snap at the start or the top
		e = s * s * s * (s * (s * 6 - 15) + 10)
	end
	local y = m.p0.Y + (m.yTop - m.p0.Y) * e
	if m.kind == "Vault" and u > m.riseEnd then
		local f = (u - m.riseEnd) / (1 - m.riseEnd)
		y = m.yTop - m.sink * f * f
	end
	local h = 0
	if u > m.uLag then
		h = (u - m.uLag) / (1 - m.uLag)
		if not m.linear then
			h = h * h * (3 - 2 * h)
		end
	end
	return Vector3.new(m.p0.X, y, m.p0.Z) + m.dirH * (m.distance * h)
end

local function endSlide(c, t: number)
	local wasSlope = slide and slide.kind == "Slope"
	slide = nil
	slideCooldownUntil = t + (if wasSlope then 0.2 else SL.Cooldown)
	if c and c.humanoid and not mantle and not climb and not c.dead then
		c.humanoid.AutoRotate = true
	end
end

local function spend(amount: number, t: number)
	stamina = math.max(0, stamina - amount)
	lastDrainAt = t
end

local function startMantle(c, ledge, t: number, speed: number)
	local rig = c.rig
	local p0 = c.root.Position
	local hipTarget = if ledge.crouch then c.baseHip - rig.crouchDrop else c.baseHip
	local m = {
		kind = ledge.kind,
		t = 0,
		p0 = p0,
		dirH = ledge.inward,
		distance = ledge.distance,
		topY = ledge.topY,
		crouch = ledge.crouch,
		material = ledge.material,
		lastPos = p0,
		riseEnd = 0.78,
		yTop = ledge.floorY + hipTarget + rig.rootHalf + 0.04,
		sink = 0,
		linear = false,
		exitSpeed = 4,
		uLag = 0,
		T = MT.Time,
		height = ledge.height,
	}
	if ledge.kind == "Vault" then
		m.riseEnd = 0.5
		m.yTop = math.max(ledge.topY + rig.rootHalf + 0.4, p0.Y + 0.5)
		m.sink = 0.45
		m.linear = true
		m.exitSpeed = math.clamp(speed * 0.92, SPD.Walk * 0.9, SPD.Sprint)
		-- climbing over a fence taller than a vault: hands on top, a slower swing over, most momentum lost
		m.tall = math.clamp((ledge.height - MT.VaultMax * (rig.scale or 1)) / 1.8, 0, 1)
		if m.tall > 0 then
			m.riseEnd = 0.6
			m.exitSpeed = math.clamp(speed * (0.92 - 0.45 * m.tall), SPD.Walk * 0.5, SPD.Sprint)
		end
	elseif ledge.kind == "QuickMantle" then
		m.riseEnd = 0.7
		m.linear = true
		m.exitSpeed = math.clamp(speed * 0.75, SPD.Walk * 0.7, SPD.Sprint)
	end
	-- the horizontal move waits until the root's underside clears the lip
	local rise = m.yTop - p0.Y
	local need = ledge.topY + 0.06 + rig.rootHalf - p0.Y
	local uClear = 0
	if rise > 1e-3 and need > 0 then
		local frac = math.clamp(need / rise, 0, 1)
		if m.linear then
			uClear = (1 - math.sqrt(1 - frac)) * m.riseEnd
		else
			-- invert the smootherstep numerically (monotonic)
			local lo, hi = 0, 1
			for _ = 1, 18 do
				local mid = (lo + hi) / 2
				local e = mid * mid * mid * (mid * (mid * 6 - 15) + 10)
				if e < frac then
					lo = mid
				else
					hi = mid
				end
			end
			uClear = hi * m.riseEnd
		end
	end
	local e = math.max(0, ledge.perp - 0.55) / math.max(ledge.distance, 0.1)
	m.uLag = if e < 0.999 then math.clamp((uClear - e) / (1 - e), 0, uClear) else uClear
	if ledge.kind == "Mantle" then
		-- a waist-high ledge takes about half a second, a head-high one about 0.8 s (more when exhausted)
		local k = math.clamp((ledge.height - MT.Min) / math.max(MT.Max - MT.Min, 0.1), 0, 1)
		m.T = MT.TimeLow + (MT.Time - MT.TimeLow) * k
		if ledge.fromWater then
			m.T *= 1.15
		end
		if exhausted then
			m.T *= 1.3
		end
		spend(STA.MantleBase + STA.MantlePerStud * ledge.height, t)
	else
		-- keep momentum: cross at roughly the current speed
		local cross = ledge.distance / (math.max(speed, SPD.Walk) * (1 - m.uLag))
		local lo, hi = MT.VaultTime * 0.75, MT.VaultTime * (if ledge.kind == "Vault" then 1.6 else 1.8)
		m.T = math.clamp(cross, lo, hi)
		spend(STA.MantleBase, t)
		if (m.tall or 0) > 0 then
			m.T = math.max(m.T, MT.VaultTime * 1.6 + 0.5 * m.tall) -- ~0.8-1.1 s over a 4-5 stud fence
			spend(STA.MantlePerStud * ledge.height, t)
		end
	end

	if slide then
		endSlide(c, t)
	end
	mantle = m
	velocity = Vector3.zero
	jumpPressAt = -math.huge
	PUSH.mantle, PUSH.climb, PUSH.swim = 0, 0, 0
	c.humanoid.Jump = false
	if ledge.crouch then
		crouchForced = true
	end
	beginKinematic(c)
	setState("Mantle")
end

local function cancelMantle(c)
	mantle = nil
	endKinematic(c, HumanoidState.Freefall)
end

local function finishMantle(c)
	local m = mantle
	mantle = nil
	local root = c.root
	local rot = facingRotation(m.dirH)
	root.CFrame = CFrame.new(mantlePosition(m, 1)) * rot
	-- never leave the character inside geometry
	if overlapsWorld(c) then
		local fixed = false
		for _ = 1, 6 do
			root.CFrame += Vector3.new(0, 0.35, 0)
			if not overlapsWorld(c) then
				fixed = true
				break
			end
		end
		if not fixed then
			root.CFrame = CFrame.new(m.p0) * rot
		end
	end
	local exit = m.dirH * m.exitSpeed
	velocity = exit
	root.AssemblyAngularVelocity = Vector3.zero
	if m.kind == "Vault" then
		root.AssemblyLinearVelocity = exit + Vector3.new(0, -2, 0)
		AIR.wishSpeed = math.max(m.exitSpeed, SPD.Walk)
		endKinematic(c, HumanoidState.Freefall)
	else
		root.AssemblyLinearVelocity = exit
		endKinematic(c, HumanoidState.Landed)
		AIR.mantleStep = m.material
		landPose = math.max(landPose, if m.kind == "Mantle" then 0.35 else 0.2)
	end
end

local function stepMantle(c, dt: number)
	local m = mantle
	local root = c.root
	if root.Anchored or (root.Position - m.lastPos).Magnitude > 6 or m.t > m.T + 0.5 then
		cancelMantle(c) -- teleported, frozen or interrupted
		return
	end
	m.t += dt
	local u = math.clamp(m.t / m.T, 0, 1)
	local pos = mantlePosition(m, u)
	local nextPos = mantlePosition(m, math.clamp((m.t + dt) / m.T, 0, 1))
	root.CFrame = CFrame.new(pos) * facingRotation(m.dirH)
	root.AssemblyLinearVelocity = (nextPos - pos) / math.max(dt, 1 / 240)
	root.AssemblyAngularVelocity = Vector3.zero
	m.lastPos = nextPos
	if u >= 1 then
		finishMantle(c)
	end
end

local function startClimb(c, hit: RaycastResult, normal: Vector3)
	if slide then
		endSlide(c, os.clock())
	end
	climb = {
		normal = normal,
		time = 0,
		phase = 0,
		material = hit.Material,
		lastPos = c.root.Position,
		moving = false,
	}
	velocity = Vector3.zero
	jumpPressAt = -math.huge
	PUSH.mantle, PUSH.climb, PUSH.swim = 0, 0, 0
	c.humanoid.Jump = false
	if sprintToggled then
		setSprintToggle(false)
	end
	beginKinematic(c)
	setState("Climb")
end

local function exitClimb(c, how: string)
	local cl = climb
	climb = nil
	if not cl then
		return
	end
	local root = c.root
	local n = cl.normal
	local t = os.clock()
	if how == "Jump" then
		root.AssemblyLinearVelocity = n * CL.PushSpeed + Vector3.new(0, CL.PushUp, 0)
		velocity = n * CL.PushSpeed
		AIR.wishSpeed = SPD.Walk
		spend(JMP.Stamina, t)
		AIR.lastJumpAt = t
		endKinematic(c, HumanoidState.Freefall)
		ClientState.jumped:Fire()
	elseif how == "Land" then
		root.AssemblyLinearVelocity = Vector3.zero
		velocity = Vector3.zero
		endKinematic(c, HumanoidState.Landed)
	else
		root.AssemblyLinearVelocity = n * 4
		velocity = n * 4
		AIR.wishSpeed = SPD.Walk
		endKinematic(c, HumanoidState.Freefall)
	end
end

local function stepClimb(c, dt: number)
	local cl = climb
	local root, humanoid, rig = c.root, c.humanoid, c.rig
	local pos = root.Position
	if root.Anchored or (pos - cl.lastPos).Magnitude > 6 then
		exitClimb(c, "Fall")
		return
	end
	cl.time += dt
	local reach = CL.StandOff + 1.8
	local hit = workspace:Raycast(pos + Vector3.new(0, 0.5, 0), -cl.normal * reach, worldParams)
	if not (hit and isClimbableHit(hit.Instance)) then
		hit = workspace:Raycast(pos - Vector3.new(0, 0.5, 0), -cl.normal * reach, worldParams)
	end
	if not (hit and isClimbableHit(hit.Instance)) then
		exitClimb(c, "Fall") -- slipped off the side
		return
	end
	local n = climbNormal(hit, pos)
	if n then
		local blended = cl.normal:Lerp(n, math.min(1, dt * 10))
		if blended.Magnitude > 1e-3 then
			cl.normal = blended.Unit
		end
	end
	cl.material = hit.Material

	local up = -inputVector.Z
	local side = inputVector.X
	if math.abs(up) < 0.15 then
		up = 0
	end
	if math.abs(side) < 0.15 then
		side = 0
	end
	if up > 0 then
		-- out of trunk above the head: pull up onto whatever is there, or stop climbing higher
		local headHit = workspace:Raycast(Vector3.new(pos.X, pos.Y + rig.headTop + 0.1, pos.Z), -cl.normal * reach, worldParams)
		if not (headHit and isClimbableHit(headHit.Instance)) then
			AIR.takeoffY = pos.Y - (humanoid.HipHeight + rig.rootHalf) -- the hands reach from where we hang
			local ledge = findLedge(c, -cl.normal, "air", reach + 0.6)
			if ledge then
				climb = nil
				startMantle(c, ledge, os.clock(), 0)
				return
			end
			up = 0
		end
	elseif up < 0 then
		if workspace:Raycast(pos, Vector3.new(0, -(humanoid.HipHeight + rig.rootHalf + 0.3), 0), worldParams) then
			exitClimb(c, "Land")
			return
		end
	end

	-- hand-over-hand: each stroke pulls hard through the middle and pauses as the hands change grip
	local s = math.sin(math.pi * cl.phase)
	local pulse = (1 - CL.Pulse) + 2 * CL.Pulse * s * s
	local speed = SPD.Climb * pulse * (if exhausted then 0.7 else 1)
	local target = hit.Position + cl.normal * CL.StandOff
	local correction = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	local tangent = Vector3.yAxis:Cross(cl.normal)
	local move = Vector3.new(0, up * speed, 0) + tangent * (side * SPD.Climb * CL.Lateral)
	local vel = move + correction * 10
	root.CFrame = CFrame.lookAlong(pos, -cl.normal)
	root.AssemblyLinearVelocity = vel
	root.AssemblyAngularVelocity = Vector3.zero
	cl.lastPos = pos + vel * dt
	-- the stroke clock runs on effort, so the pull cycle keeps going through the slow phase
	local effort = math.max(math.abs(up), math.abs(side) * CL.Lateral)
	cl.moving = effort > 0.05
	cl.phase += effort * SPD.Climb * dt / CL.Stroke
end

-- Ground, air, swim and slide momentum ----------------------------------------------------------------------------------

-- Friction-circle ground model. Speeding up is force-limited (push-off) at low speed and power-limited at
-- speed; braking skids harder from speed; turning is limited by lateral grip. All limits scale with grip.
local function groundStep(v: Vector3, wishDir: Vector3, S: number, dt: number, grip: number, pushScale: number): Vector3
	local target = wishDir * S
	local dv = target - v
	local dm = dv.Magnitude
	if dm < 1e-4 then
		return target
	end
	local speed = v.Magnitude
	local fwd: Vector3
	if speed > 0.25 then
		fwd = v / speed
	elseif S > 0.05 then
		fwd = wishDir
	else
		fwd = dv / dm
	end
	local along = dv:Dot(fwd)
	local lateral = dv - fwd * along
	local maxAlong
	if along > 0 then
		maxAlong = math.min(ACC.Push, ACC.Power / math.max(speed, 1)) * grip * pushScale
	else
		maxAlong = (ACC.Brake + ACC.BrakePerSpeed * speed) * grip
	end
	local dAlong = math.clamp(along, -maxAlong * dt, maxAlong * dt)
	local latMag = lateral.Magnitude
	local maxLat = ACC.Turn * grip * dt
	local dLat = if latMag > maxLat then lateral * (maxLat / latMag) else lateral
	local nv = v + fwd * dAlong + dLat
	if S < 0.05 and nv:Dot(v) <= 0 then
		return Vector3.zero -- braking never reverses you
	end
	return nv
end

local function airStep(v: Vector3, w: Vector3, S: number, dt: number): Vector3
	if w.Magnitude < 0.01 or S < 0.05 then
		local s = v.Magnitude
		if s < 0.01 then
			return Vector3.zero
		end
		return v * (math.max(0, s - ACC.AirDrag * dt) / s)
	end
	local accel = ACC.Push * ACC.AirControl
	local along = v:Dot(w)
	local perp = v - w * along
	if along < S then
		along = math.min(S, along + accel * dt)
	end
	local pm = perp.Magnitude
	if pm > 1e-4 then
		perp = perp * (math.max(0, pm - accel * 0.6 * dt) / pm)
	end
	return w * along + perp
end

local function startSlide(c, t: number, fwd: Vector3, actualSpeed: number)
	local s = math.max(velocity.Magnitude, actualSpeed)
	local dir = if velocity.Magnitude > 0.5 then velocity.Unit else fwd
	local speed = math.min(SL.Max, math.max(s, SL.MinEntry) * SL.Boost)
	velocity = dir * speed
	slide = { kind = "Slide", time = 0, age = 0, dir = dir, blockedTime = 0, airTime = 0, recover = 0 }
	if sprintToggled then
		setSprintToggle(false)
	end
	c.humanoid.AutoRotate = false -- the body keeps facing the slide; the camera looks freely
end

local function slideStep(c, dt: number, t: number, wishDir: Vector3, actualSpeed: number, grounded: boolean): Vector3
	local sl = slide
	local s = velocity.Magnitude
	local dir = if s > 0.01 then velocity / s else sl.dir
	if wishDir.Magnitude > 0.01 then
		local angle = math.acos(math.clamp(dir:Dot(wishDir), -1, 1))
		if angle > 1e-3 and angle < 2.2 then
			local sign = if dir:Cross(wishDir).Y >= 0 then 1 else -1
			dir = CFrame.fromAxisAngle(Vector3.yAxis, sign * math.min(angle, SL.Steer * dt)):VectorToWorldSpace(dir)
		end
	end
	-- friction depends on the surface: you slide further on mud, snow and ice
	s = math.max(0, s - SL.Friction * math.clamp(SURF.grip, 0.35, 1.2) * dt)
	local nv = dir * s
	local downhill = 0
	local n = G.normal
	if grounded and n.Y < 0.999 and n.Y > 0.3 then
		-- the horizontal part of gravity along the slope: downhill speeds you up, uphill slows you
		local g = Vector3.new(n.X * n.Y, 0, n.Z * n.Y)
		nv += g * SL.SlopeAccel * dt
		downhill = g:Dot(dir)
	end
	local ns = nv.Magnitude
	if ns > SL.Max then
		nv = nv * (SL.Max / ns)
	end
	sl.time += dt * (if downhill > 0.12 then SL.DownhillTime else 1)
	sl.age += dt
	if actualSpeed < SL.EndSpeed * 0.6 and sl.age > 0.15 then
		sl.blockedTime += dt
	else
		sl.blockedTime = 0
	end
	if grounded then
		sl.airTime = 0
	else
		sl.airTime += dt
	end
	local crouchInput = crouchHeld or crouchToggled
	if nv.Magnitude < SL.EndSpeed or sl.time >= SL.MaxTime or sl.age >= SL.HardCap or sl.blockedTime > 0.12
		or (not crouchInput and sl.age >= SL.MinTime) or sl.airTime > 0.15 then
		endSlide(c, t)
	end
	return nv
end

-- Ground too steep to stand on: you slide down it with friction and can only steer across it.
local function startSlopeSlide(c, t: number)
	local n = G.normal
	local downhill = Vector3.new(n.X, 0, n.Z)
	local dir = if downhill.Magnitude > 1e-3 then downhill.Unit else flatBasis(c.root.CFrame)
	slide = { kind = "Slope", time = 0, age = 0, dir = dir, blockedTime = 0, airTime = 0, recover = 0 }
	if sprintToggled then
		setSprintToggle(false)
	end
	c.humanoid.AutoRotate = false
end

local function slopeSlideStep(c, dt: number, t: number, wishDir: Vector3): Vector3
	local sl = slide
	sl.age += dt
	local n = G.normal
	local v = velocity
	local onSlope = G.hit and G.dist < 1.4
	if onSlope and n.Y < SLOPE.RecoverCos then
		local downhill = Vector3.new(n.X, 0, n.Z)
		if downhill.Magnitude > 1e-3 then
			downhill = downhill.Unit
			sl.dir = downhill
			local sinT = math.sqrt(math.max(0, 1 - n.Y * n.Y))
			local a = SLOPE.SlideAccel * math.max(0.12, sinT - SLOPE.SlideFriction * SURF.grip * n.Y)
			v += downhill * a * dt
			-- no walking back up it
			local into = v:Dot(downhill)
			if into < 0 then
				v -= downhill * into
			end
			-- a little steering across the slope
			if wishDir.Magnitude > 0.1 then
				local across = wishDir - downhill * wishDir:Dot(downhill)
				v += across * 10 * dt
			end
		end
	end
	local s = v.Magnitude
	if s > SLOPE.SlideMax then
		v = v * (SLOPE.SlideMax / s)
	end
	if onSlope and n.Y >= SLOPE.RecoverCos then
		sl.recover += dt
	else
		sl.recover = 0
	end
	if sl.recover > 0.12 or ((not G.hit or G.dist > 3) and sl.age > 0.35) then
		endSlide(c, t)
	end
	return v
end

-- Slope speed multiplier from the sine of the slope along the path (+ uphill).
local function slopeFactor(sinAlong: number): number
	if sinAlong >= 0 then
		return math.max(0.25, 1 - SLOPE.Uphill * sinAlong)
	end
	local d = -sinAlong
	if d <= SLOPE.BoostSin then
		return 1 + SLOPE.Downhill * d
	end
	-- steep descents: you have to brake with every step
	return math.max(0.55, 1 + SLOPE.Downhill * SLOPE.BoostSin - SLOPE.SteepBrake * (d - SLOPE.BoostSin))
end

-- Swimming: strokes pulse the speed (pull, then glide) and the camera direction lets you dive and surface.
local function swimStep(dt: number, camCF: CFrame, mv: Vector3, inputMag: number, wishSpeed: number): Vector3
	local target = Vector3.zero
	if inputMag > 0.02 then
		local w3 = camCF:VectorToWorldSpace(Vector3.new(mv.X, 0, mv.Z))
		if w3.Magnitude > 1e-3 then
			-- strokes: fastest mid-pull, slowest at the glide
			local s = math.sin(math.pi * stridePhase * 2)
			local pulse = (1 - SWM.Pulse) + 2 * SWM.Pulse * s * s
			target = w3.Unit * wishSpeed * pulse
		end
	end
	local delta = target - swimVelocity
	local stepSize = (if target.Magnitude > swimVelocity.Magnitude then 14 else 7) * dt -- water drag: slow to stop
	if delta.Magnitude <= stepSize then
		swimVelocity = target
	else
		swimVelocity += delta.Unit * stepSize
	end
	return Vector3.new(swimVelocity.X, 0, swimVelocity.Z)
end

-- Humanoid state events -------------------------------------------------------------------------------------------------

local function stumble(c, t: number, strength: number)
	AIR.instability = 0
	AIR.stumbleUntil = t + 0.35 + 0.3 * strength
	velocity *= 1 - 0.45 * strength
	AIR.stunUntil = math.max(AIR.stunUntil, AIR.stumbleUntil)
	AIR.stunScale = math.min(AIR.stunScale, 1 - 0.5 * strength)
	landPose = math.max(landPose, 0.55 * strength + 0.2)
	local side = if math.random() < 0.5 then -1 else 1
	ClientState.cameraImpulse:Fire(Vector3.new(math.rad(-3.5) * strength, math.rad(1.2) * side * strength, math.rad(3) * side * strength), 0.18 * strength)
	emitFootstep(c, if stridePhase < 0.5 then "R" else "L", 1.15, t, SPD.Sprint)
end

-- Drop a pending take-off (a mantle, climb or freeze took over).
local function cancelJumpPrep()
	if AIR.prepAt then
		AIR.prepAt = nil
		ClientState.jumpPrepAt = -math.huge
	end
	AIR.jumpWanted = nil
end

local function onJumped(c)
	local t = os.clock()
	AIR.lastJumpAt = t
	AIR.airborne = true
	AIR.minVy = 0
	AIR.jumped = true
	AIR.coyoteUntil = 0
	AIR.startAt = t
	AIR.takeoffY = c.root.Position.Y - (c.humanoid.HipHeight + c.rig.rootHalf)
	spend(JMP.Stamina * (if t - AIR.lastLandAt < JMP.RepeatWindow and AIR.lastLandWasJump then 1.5 else 1), t)
	AIR.wishSpeed = math.max(stateSpeedFor(moveState), velocity.Magnitude)
	if slide then
		endSlide(c, t) -- slide-jump: the velocity (momentum) is kept
	end
	if crouchToggled then
		setCrouchToggle(false) -- jumping stands you up
	end
	ClientState.jumped:Fire()
end

local function onLanded(c, impact: number)
	local t = os.clock()
	local h = dropHeight(impact)
	local wasJump = AIR.jumped
	AIR.lastLandAt = t
	AIR.lastLandWasJump = wasJump
	if h > JMP.StunHeight then
		-- a hard landing: legs absorb it, you lose speed for a moment; from high up you stumble
		local k = math.clamp((h - JMP.StunHeight) / math.max(JMP.HardHeight - JMP.StunHeight, 1), 0, 1)
		velocity *= 1 - JMP.MaxLoss * k
		AIR.stunUntil = t + 0.12 + 0.33 * k
		AIR.stunScale = 1 - 0.5 * k
		if h > JMP.HardHeight then
			stumble(c, t, math.clamp((h - JMP.HardHeight) / 10, 0.4, 1))
		end
	elseif wasJump and velocity.Magnitude > SPD.Walk then
		velocity *= 1 - JMP.HopSpeedLoss -- each landing absorbs a little speed (no free bunny-hopping)
	end
	landPose = math.max(landPose, math.clamp(h / 9, 0.08, 1))
	if impact >= 6 then
		-- normalised to standard gravity so listeners tuned to drop heights keep working
		ClientState.landed:Fire(math.sqrt(2 * workspace.Gravity * h))
	end
	if t - jumpPressAt <= JMP.Buffer then
		AIR.bufferedJump = true
	end
	if crouchHeld or crouchToggled then
		AIR.landSlide = true
	end
end

local function onStateChanged(c, old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	if ctx ~= c then
		return
	end
	local t = os.clock()
	if new == HumanoidState.Jumping then
		onJumped(c)
	elseif new == HumanoidState.Freefall then
		if not AIR.airborne then
			AIR.airborne = true
			AIR.minVy = math.min(0, c.root.AssemblyLinearVelocity.Y)
			AIR.startAt = t
			AIR.takeoffY = c.root.Position.Y - (c.humanoid.HipHeight + c.rig.rootHalf)
			local fromGround = old == HumanoidState.Running or old == HumanoidState.RunningNoPhysics
				or old == HumanoidState.Landed or old == HumanoidState.Climbing
			AIR.jumped = not fromGround
			AIR.coyoteUntil = if fromGround then t + JMP.Coyote else 0
			AIR.wishSpeed = math.max(stateSpeedFor(moveState), velocity.Magnitude)
		end
	elseif new == HumanoidState.PlatformStanding or new == HumanoidState.Dead then
		AIR.airborne = false
	elseif AIR.airborne and (new == HumanoidState.Landed or new == HumanoidState.Running or new == HumanoidState.RunningNoPhysics
		or new == HumanoidState.Climbing or new == HumanoidState.Swimming) then
		AIR.airborne = false
		local impact = math.max(0, -AIR.minVy)
		if new == HumanoidState.Swimming then
			if impact > 20 then
				ClientState.footstep:Fire(Enum.Material.Water, math.clamp(impact / 80, 0.4, 1), "L")
			end
		elseif slide and slide.kind == "Slope" and impact < 45 then
			-- skittering down a steep slope: not a landing
		else
			onLanded(c, impact)
		end
	end
end

-- Stance (hitbox height) and replication -------------------------------------------------------------------------------

local function updateStance(c, dt: number, t: number, crouchActive: boolean)
	local rig = c.rig
	-- vaults tuck the legs (crouch pose) and land into a short squat
	local targetCrouch = if crouchActive or slide or (mantle and (mantle.crouch or mantle.kind ~= "Mantle")) then 1 else 0
	local targetSlide = if slide then 1 else 0
	local targetClimb = if climb or (mantle and mantle.kind == "Mantle") then 1 else 0
	local rate = dt / ST.Blend
	crouchAmt = approach(crouchAmt, targetCrouch, rate)
	slideAmt = approach(slideAmt, targetSlide, rate * (if targetSlide > 0 then 1.25 else 0.8))
	climbAmt = approach(climbAmt, targetClimb, rate * 0.8)
	easedCrouch, easedSlide, easedClimb = smooth01(crouchAmt), smooth01(slideAmt), smooth01(climbAmt)

	if rig.r15 and rig.crouchDrop > 0 and not c.dead then
		local drop = rig.crouchDrop * math.max(easedCrouch, easedSlide) + (rig.slideDrop - rig.crouchDrop) * easedSlide
		local hip = c.baseHip - drop
		if math.abs(c.humanoid.HipHeight - hip) > 1e-3 then
			c.lastSetHip = hip
			c.humanoid.HipHeight = hip
		end
	end

	-- stay low under ceilings until there is room to stand
	if not slide and not mantle and not climb then
		if crouchHeld or crouchToggled then
			crouchForced = false
		elseif crouchAmt > 0.02 or crouchForced then
			crouchForced = not hasStandingRoom(c)
		end
	end

	local stance = "Stand"
	if climb or (mantle and mantle.kind == "Mantle") then
		stance = "Climb"
	elseif slide then
		stance = "Slide"
	elseif crouchAmt > 0.5 then
		stance = "Crouch"
	end
	if stance ~= sentStance then
		if t - lastStanceSentAt >= 0.12 and setStanceRemote then
			sentStance = stance
			lastStanceSentAt = t
			setStanceRemote:FireServer(stance)
		end
	elseif sentStance and setStanceRemote and t - lastStanceSentAt > 2 then
		-- reconcile if the server's copy disagrees (e.g. a dropped update)
		local replicated = c.character:GetAttribute("Stance")
		if replicated ~= nil and replicated ~= sentStance then
			lastStanceSentAt = t
			setStanceRemote:FireServer(sentStance)
		end
	end
end

local function regenStamina(dt: number, t: number, still: boolean)
	if t - lastDrainAt >= STA.RegenDelay then
		-- breathing recovers faster standing still; a nearly empty tank recovers a little slower
		local k = if stamina < 0.2 then 0.8 else 1
		stamina = math.min(1, stamina + STA.Regen * k * (if still then STA.IdleBonus else 1) * dt)
	end
end

local function updateExhaustion()
	stamina = math.clamp(stamina, 0, 1)
	if stamina <= 0 and not exhausted then
		exhausted = true
		if sprintToggled then
			setSprintToggle(false)
		end
	elseif exhausted and stamina >= STA.Threshold then
		exhausted = false
	end
end

-- Step length follows the walk and run clips (Animate blends them over the same speeds and plays them at the
-- ground speed), so footsteps, head-bob and the visible legs stay in step: cadence rises from ~2.8 steps/s at a
-- walk to ~2.7 at a jog and ~4.3 at a full sprint on the clips' measuring rig. Each rig scales its steps by its leg
-- length (rig.strideScale), as Animate scales the clip speeds.
local function stepLength(speed: number): number
	local run = smooth01((speed - 8) / 3.5)
	local scale = if ctx and ctx.rig then ctx.rig.strideScale or 1 else 1
	-- above a jog, runners lengthen the stride more than the cadence: the steps grow up to 25% by a full sprint
	-- (~4.8 steps/s instead of ~6; Animate stretches the run clip's stride the same way)
	local reach = 1 + 0.25 * smooth01((speed - SPD.Walk) / math.max(SPD.Sprint - SPD.Walk, 1))
	return math.max(0.8, (JMP.StepWalk + (JMP.StepRun - JMP.StepWalk) * run) * scale * reach)
end

local function updateStride(c, dt: number, t: number, speed: number, onFoot: boolean, swimming: boolean)
	if swimming then
		if speed > 1 then
			local prev = stridePhase
			stridePhase += speed * dt / (2 * SWM.Stroke)
			if prev < 0.5 and stridePhase >= 0.5 then
				emitFootstep(c, "R", 0.8, t, speed, Enum.Material.Water)
			end
			if stridePhase >= 1 then
				stridePhase -= 1
				emitFootstep(c, "L", 0.8, t, speed, Enum.Material.Water)
			end
		end
		wasMoving = false
		return
	end
	local moving = onFoot and speed > 1.2
	if moving then
		if not wasMoving and t - lastStepAt > 0.3 then
			stridePhase = if stridePhase < 0.5 then 0.4 else 0.9 -- the first step lands quickly
		end
		local prev = stridePhase
		stridePhase += speed * dt / (2 * stepLength(speed))
		if prev < 0.5 and stridePhase >= 0.5 then
			emitFootstep(c, "R", 1, t, speed)
		end
		if stridePhase >= 1 then
			stridePhase -= 1
			emitFootstep(c, "L", 1, t, speed)
		end
	elseif wasMoving and onFoot and t - lastStepAt > 0.2 then
		emitFootstep(c, if stridePhase < 0.5 then "R" else "L", 0.6, t, math.max(speed, 3)) -- settling step
	end
	wasMoving = moving
end

local function writeState(av: Vector3, grounded: boolean)
	ClientState.speed = Vector3.new(av.X, 0, av.Z).Magnitude
	ClientState.velocity = av
	ClientState.grounded = grounded
	ClientState.stamina = stamina
	ClientState.exhausted = exhausted
	ClientState.crouchAlpha = math.max(easedCrouch, easedSlide)
	ClientState.strideAlpha = stridePhase
end

local function applyHumanoidMove(humanoid: Humanoid, v: Vector3)
	local s = v.Magnitude
	if s > 0.05 then
		humanoid.WalkSpeed = s
		humanoid:Move(v / s, false)
	else
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero, false)
	end
end

-- Exertion (0..1) rises with hard work and decays over several seconds; the camera breathes with it.
local function updateExertion(dt: number, working: number)
	local e = motion.exertion
	if working > e then
		e += (working - e) * expAlpha(0.6, dt)
	else
		e += (working - e) * expAlpha(0.18, dt)
	end
	if exhausted then
		e = math.max(e, 0.85)
	end
	motion.exertion = math.clamp(e, 0, 1)
end

-- Per-frame update (after the default controls) ------------------------------------------------------------------------

local function update(dt: number)
	local c = ctx
	if not c or c.dead then
		return
	end
	local humanoid, root = c.humanoid, c.root
	if not root.Parent or not humanoid.Parent or humanoid.Health <= 0 then
		return
	end
	dt = math.clamp(dt, 0, 0.1)
	local t = os.clock()
	lastUpdateAt = t
	recovered = false

	-- Input
	local spectating = ClientState.spectating ~= nil
	local mv = if spectating then Vector3.zero else readMoveVector(t)
	inputVector = mv
	local camCF = cameraCFrame()
	local fwd, right = flatBasis(camCF)
	local wishWorld = right * mv.X + fwd * -mv.Z
	local inputMag = math.min(1, wishWorld.Magnitude)
	local wishDir = if inputMag > 0.02 then wishWorld.Unit else Vector3.zero
	-- "forward" is where the camera looks in first person; in third person (lobby) the body turns to face its movement
	local firstPerson = isFirstPerson()
	local faceDir = if firstPerson then fwd else flatBasis(root.CFrame)
	local forwardness = 0 -- 1 = moving straight ahead, 0 = sideways, < 0 = backwards
	if inputMag > 0.02 then
		forwardness = if firstPerson then -mv.Z / math.max(inputMag, 1e-3) else 1
	end
	local forwardAmount = forwardness * inputMag
	local jumpHeld = not spectating and readJumpHeld(humanoid)
	local jumpEdge = jumpHeld and not jumpHeldPrev
	jumpHeldPrev = jumpHeld
	if jumpEdge then
		jumpPressAt = t
	end
	local wantTouch = not spectating
	if wantTouch ~= touchVisible then
		touchVisible = wantTouch
		Input.setTouchVisible("Sprint", wantTouch)
		Input.setTouchVisible("Crouch", wantTouch)
	end

	-- Physics readings
	local av = root.AssemblyLinearVelocity
	local actualH = Vector3.new(av.X, 0, av.Z)
	local actualSpeed = actualH.Magnitude
	local hState = humanoid:GetState()
	local swimming = hState == HumanoidState.Swimming
	local nativeClimb = hState == HumanoidState.Climbing
	local seated = humanoid.Sit or hState == HumanoidState.Seated
	local inAir = hState == HumanoidState.Freefall or hState == HumanoidState.Jumping
	local frozen = ClientState.frozen or player:GetAttribute("Frozen") == true or root.Anchored
	local useBusy = ClientState.useProgress ~= nil

	-- acceleration we actually experienced (for the body lean and camera)
	if dt > 1e-4 then
		local a = (actualH - prevVel) / dt
		motion.accel = motion.accel:Lerp(a, expAlpha(14, dt))
	end
	prevVel = actualH

	-- Teleports (plinths, lobby reloads) reset momentum
	local pos = root.Position
	if lastRootPos and (pos - lastRootPos).Magnitude > 25 and not mantle and not climb then
		velocity = Vector3.zero
		swimVelocity = Vector3.zero
		motion.accel = Vector3.zero
		if slide then
			endSlide(c, t)
		end
	end
	lastRootPos = pos
	probeGround(c, if inputMag > 0.02 then wishDir else actualH)
	probeWater(c)
	local grounded = not inAir and not swimming and humanoid.FloorMaterial ~= Enum.Material.Air
	updateSurface(dt, grounded or (G.hit and G.dist < 0.6))
	G.alongSmooth += (G.alongSin - G.alongSmooth) * expAlpha(if grounded then 9 else 3, dt)
	if swimming and slide then
		endSlide(c, t) -- sliding into water ends the slide
	end
	landPose = math.max(0, landPose - dt * 2.6)
	-- the knee dip before a take-off (it drops the eye a little); released quickly as the legs extend
	if AIR.prepAt then
		prepPose = math.min(1, prepPose + dt / math.max(AIR.prepTime, 0.03))
	else
		prepPose = math.max(0, prepPose - dt * 14)
	end

	if AIR.mantleStep then
		local material = AIR.mantleStep
		AIR.mantleStep = nil
		emitFootstep(c, "L", 0.7, t, SPD.Walk, material)
	end

	-- Seated: leave the humanoid to the seat
	if seated then
		if slide then
			endSlide(c, t)
		end
		velocity = Vector3.zero
		c.gravityMode = nil
		setJumpEnabled(humanoid, true) -- the jump key stands you up out of a seat
		cancelJumpPrep()
		setState("Idle")
		regenStamina(dt, t, true)
		updateExhaustion()
		updateStance(c, dt, t, false)
		updateExertion(dt, 0)
		writeState(av, false)
		return
	end

	-- Frozen: no movement, no jumping (the server also anchors the root on the plinths)
	if frozen then
		if mantle then
			cancelMantle(c)
		end
		if climb then
			exitClimb(c, "Fall")
		end
		if slide then
			endSlide(c, t)
		end
		velocity = Vector3.zero
		swimVelocity = Vector3.zero
		c.gravityMode = nil
		applyHumanoidMove(humanoid, Vector3.zero)
		setJumpEnabled(humanoid, false)
		cancelJumpPrep()
		setState("Frozen")
		regenStamina(dt, t, true)
		updateExhaustion()
		updateStance(c, dt, t, false) -- the root is anchored: a crouch pose would float the feet
		updateExertion(dt, 0)
		writeState(av, true)
		return
	end

	-- Kinematic modes are stepped on PreSimulation; here we only handle their input and bookkeeping
	if mantle then
		applyHumanoidMove(humanoid, Vector3.zero)
		setJumpEnabled(humanoid, false)
		setState("Mantle")
		updateStance(c, dt, t, false)
		updateExertion(dt, 0.55)
		writeState(av, false)
		return
	end
	if climb then
		applyHumanoidMove(humanoid, Vector3.zero)
		setJumpEnabled(humanoid, false)
		if jumpEdge and climb.time > 0.2 then
			exitClimb(c, "Jump")
		elseif t - crouchPressedAt < 0.15 then
			crouchPressedAt = -math.huge
			exitClimb(c, "Fall") -- let go
		else
			stamina -= STA.ClimbDrain * (if climb.moving then 1 else 0.4) * dt
			lastDrainAt = t
			updateExhaustion()
			if stamina <= 0 then
				exitClimb(c, "Fall")
			else
				setState("Climb") -- AudioController times the climb sounds from the root's vertical speed
			end
		end
		updateStance(c, dt, t, false)
		updateExertion(dt, if climb and climb.moving then 0.75 else 0.45)
		writeState(av, false)
		return
	end

	-- Ground too steep to stand on: the Humanoid (MaxSlopeAngle) has lost its floor and the ground under us
	-- is steeper than walkable
	local steep = G.hit and G.dist < 0.8 and G.normal.Y < SLOPE.MaxCos and not swimming
	if steep and not slide and not nativeClimb then
		G.steepTime += dt
		if G.steepTime > 0.08 then
			startSlopeSlide(c, t)
		end
	else
		G.steepTime = 0
	end
	local slopeSliding = slide ~= nil and slide.kind == "Slope"

	-- Jumping, edge-triggered: holding the key (or the default controls' Humanoid.Jump) never repeats a jump.
	-- A press on the ground asks for a take-off; once the feet are ready (JumpGroundTime after a landing, no
	-- hard-landing stun) a short knee dip plays (JumpPrepTime, shorter on the move) and the take-off fires at its
	-- end. A press just before landing is buffered; coyote time still allows a jump just after walking off a
	-- ledge. No jumping off unstandable ground or while stumbling.
	local stumbling = t < AIR.stumbleUntil
	local canJump = t - AIR.lastJumpAt >= JMP.Cooldown and not spectating and not slopeSliding and not steep and not stumbling
	local apex = JMP.Height
	if exhausted then
		apex *= JMP.ExhaustedScale
	end
	if t - AIR.lastLandAt < JMP.RepeatWindow and AIR.lastLandWasJump then
		apex *= JMP.RepeatScale -- tired legs: repeated hops are lower
	end
	if W.depth > SWM.WadeStart then
		apex *= math.clamp(1 - W.depth / SWM.WadeFull, 0.35, 1)
	end
	local jumpHeight = humanoidJumpHeight(apex)
	if lastJumpHeight == nil or math.abs(lastJumpHeight - jumpHeight) > 1e-3 then
		lastJumpHeight = jumpHeight
		humanoid.JumpHeight = jumpHeight
	end
	if (jumpEdge or AIR.bufferedJump) and grounded and AIR.prepAt == nil then
		AIR.jumpWanted = t
	end
	AIR.bufferedJump = false
	if AIR.jumpWanted and (t - AIR.jumpWanted > 0.35 or not grounded) then
		AIR.jumpWanted = nil -- the moment passed (or we left the ground)
	end
	if AIR.jumpWanted and AIR.prepAt == nil and canJump and t >= math.max(AIR.lastLandAt + JMP.GroundTime, AIR.stunUntil) then
		AIR.jumpWanted = nil
		AIR.prepAt = t
		AIR.prepTime = if actualSpeed > 4 then JMP.PrepTimeMoving else JMP.PrepTime
		ClientState.jumpPrepAt = t -- Animate plays the take-off from the dip
		ClientState.jumpPrepTime = AIR.prepTime
	end
	local fire = false
	if AIR.prepAt then
		if t - AIR.prepAt > AIR.prepTime + 0.25 then
			cancelJumpPrep() -- stale
		elseif not grounded then
			-- walked off the edge mid-dip: still a jump within coyote time
			fire = inAir and not AIR.jumped and t < AIR.coyoteUntil and canJump
			if not fire then
				cancelJumpPrep()
			end
		elseif not canJump then
			cancelJumpPrep()
		elseif t - AIR.prepAt >= AIR.prepTime then
			fire = true
		end
	end
	if not fire and inAir and not AIR.jumped and t < AIR.coyoteUntil and jumpEdge and canJump then
		fire = true -- just walked off a ledge: no dip, the feet already left
	end
	if fire then
		AIR.prepAt = nil
		AIR.jumpWanted = nil
		AIR.firedAt = t
	end
	-- The Jumping state is only enabled for our own take-offs (and native ladder/swim exits), so nothing
	-- re-launches you on landing while the key is still held.
	setJumpEnabled(humanoid, fire or t - AIR.firedAt < 0.15 or nativeClimb or swimming
		or (inAir and av.Y > 0 and t - AIR.lastJumpAt < 0.5))
	if fire then
		humanoid:ChangeState(HumanoidState.Jumping)
	end
	-- the jump happens in this frame's physics step: switch to the lighter air gravity before it
	AIR.armed = fire or t - AIR.firedAt < 0.05

	-- Climb entry: face a Climbable and push into it (or jump at it)
	if not useBusy and not swimming and not nativeClimb and not slide and stamina > 0.05 and t - lastKinematicEndAt > 0.3 and forwardAmount > 0.2 then
		local hit, hitNormal = probeClimbable(c, faceDir)
		if hit and hitNormal then
			if forwardAmount > 0.6 and (actualH:Dot(faceDir) < 4 or inAir) then
				PUSH.climb += dt
			else
				PUSH.climb = 0
			end
			if jumpEdge or PUSH.climb >= CL.EntryTime then
				cancelJumpPrep()
				startClimb(c, hit, hitNormal)
				updateStance(c, dt, t, false)
				writeState(av, false)
				return
			end
		else
			PUSH.climb = 0
		end
	else
		PUSH.climb = 0
	end

	-- Mantle / vault / climb out of the water
	if not useBusy and not nativeClimb and not slopeSliding and inputMag > 0.3 and (not firstPerson or wishDir:Dot(fwd) > 0.5)
		and t - lastKinematicEndAt > 0.25 then
		local ledge = nil
		local rigScale = c.rig.scale or 1
		if swimming then
			PUSH.mantle = 0
			-- (strokes bounce you off the bank, so the push decays instead of resetting)
			PUSH.swim = if actualH:Dot(wishDir) < 3 then PUSH.swim + dt else math.max(0, PUSH.swim - dt * 0.5)
			if jumpEdge or PUSH.swim >= 0.25 then
				ledge = findLedge(c, wishDir, "swim", 2.4 * rigScale)
			end
		elseif grounded then
			PUSH.swim = 0
			if actualH:Dot(wishDir) < 3 then
				PUSH.mantle += dt
			else
				PUSH.mantle = 0
			end
			if (moveState == "Sprint" or moveState == "Slide") and actualSpeed > SPD.Walk then
				ledge = findLedge(c, wishDir, "vault", MT.Reach * rigScale)
			end
			if not ledge and (jumpEdge or (jumpHeld and t - jumpPressAt < 0.3) or PUSH.mantle >= MT.PushTime) then
				local reach = (if jumpHeld then MT.Grab else math.min(MT.Grab, 1.35)) * rigScale
				ledge = findLedge(c, wishDir, "ground", reach)
			end
		elseif inAir then
			PUSH.mantle, PUSH.swim = 0, 0
			local candidate = findLedge(c, wishDir, "air", MT.Grab * rigScale)
			if candidate then
				-- only grab the ledge if the jump would fall short of it
				local vy = av.Y
				local rise = if vy > 0 then vy * vy / (2 * JMP.RiseGravity) else 0
				local feetY = pos.Y - (humanoid.HipHeight + c.rig.rootHalf)
				if feetY + rise < candidate.topY + 0.35 then
					ledge = candidate
				end
			end
		end
		if ledge then
			cancelJumpPrep()
			startMantle(c, ledge, t, actualSpeed)
			updateStance(c, dt, t, false)
			writeState(av, false)
			return
		end
	else
		PUSH.mantle, PUSH.swim = 0, 0
	end

	-- Crouch, slide, sprint
	local crouchInput = crouchHeld or crouchToggled
	if not slide and t - crouchPressedAt < 0.15 and t >= slideCooldownUntil and grounded and not swimming and not useBusy
		and W.depth < SWM.WadeStart
		and (moveState == "Sprint" or ((sprintHeld or sprintToggled) and actualSpeed >= SL.MinEntry)) and actualSpeed >= SL.MinEntry * 0.9 then
		crouchPressedAt = -math.huge
		startSlide(c, t, fwd, actualSpeed)
	end
	if AIR.landSlide then
		AIR.landSlide = false
		if not slide and crouchInput and t >= slideCooldownUntil and grounded and not useBusy and actualSpeed >= SL.MinEntry then
			startSlide(c, t, fwd, actualSpeed)
		end
	end
	slopeSliding = slide ~= nil and slide.kind == "Slope"

	if sprintToggled and (sprintToggleSource == "Gamepad" or sprintToggleSource == "Keyboard") then
		stickIdleTime = if inputMag < 0.15 then stickIdleTime + dt else 0
		if stickIdleTime > 0.3 then
			setSprintToggle(false) -- a toggled sprint (gamepad, keyboard Toggle) ends when you stop
		end
	end
	if autoSprintBlocked and inputMag < 0.5 then
		autoSprintBlocked = false
	end
	local autoSprint = modeFor("sprint", Input.device()) == 2 and not sprintJogHeld and not autoSprintBlocked
		and inputMag >= AUTO_SPRINT_PUSH
	local wantsSprint = (sprintHeld or sprintToggled or autoSprint) and not spectating
	local aiming = ClientState.aiming == true
	local deepWade = W.depth > SWM.WadeFull * 0.55
	local sprintAllowed = wantsSprint and not exhausted and stamina > 0 and inputMag > 0.35 and forwardness >= SPD.SprintCos
		and not crouchInput and not crouchForced and not slide and not useBusy and not aiming and not stumbling and not deepWade
	local crouchActive = (crouchInput or crouchForced) and not slide and not swimming

	-- Target speed for this frame
	local targetSpeed
	if nativeClimb then
		targetSpeed = SPD.Climb * 1.25
	elseif swimming then
		targetSpeed = if wantsSprint and stamina > 0.05 and not exhausted then SWM.Sprint else SWM.Speed
	elseif crouchActive then
		targetSpeed = SPD.Crouch
	elseif sprintAllowed then
		-- an almost empty tank slows the sprint down before it runs out
		local tank = math.clamp(stamina / 0.3, 0, 1)
		targetSpeed = SPD.Sprint * (SPD.FatigueSprint + (1 - SPD.FatigueSprint) * tank)
	else
		targetSpeed = SPD.Walk * (if exhausted then SPD.ExhaustedMult else 1)
	end
	local surfaceMult, slopeMult, wadeMult = 1, 1, 1
	if not swimming and not nativeClimb then
		surfaceMult = SURF.speed
		slopeMult = slopeFactor(G.alongSmooth)
		if G.alongSmooth > SLOPE.FadeSin and G.aheadNY < SLOPE.FadeCos then
			-- walking into ground too steep to climb: no headway (instead of jittering against it)
			slopeMult *= math.clamp((SLOPE.MaxSin - G.alongSmooth) / (SLOPE.MaxSin - SLOPE.FadeSin), 0, 1)
		end
		if W.depth > SWM.WadeStart then
			wadeMult = 1 - SWM.WadeSlow * math.clamp((W.depth - SWM.WadeStart) / (SWM.WadeFull - SWM.WadeStart), 0, 1)
		end
		targetSpeed *= surfaceMult * slopeMult * wadeMult
	end
	if useBusy then
		targetSpeed = math.min(targetSpeed, SPD.UseItem)
	end
	if aiming then
		targetSpeed *= SPD.AimMult
	end
	if not swimming and firstPerson and inputMag > 0.02 then
		-- people run forward fastest; side-steps and backpedalling are slower
		if forwardness >= 0 then
			targetSpeed *= SPD.Strafe + (1 - SPD.Strafe) * forwardness
		else
			targetSpeed *= SPD.Strafe + (SPD.Strafe - SPD.Backpedal) * forwardness
		end
	end
	if t < AIR.stunUntil then
		targetSpeed *= AIR.stunScale
	end
	local wishSpeed = targetSpeed * inputMag

	-- Integrate momentum
	local grip = math.clamp(SURF.grip, 0.05, 1.5)
	local pushScale = (if exhausted then 0.85 else 1) * (if W.depth > SWM.WadeStart then 0.75 else 1)
	if swimming then
		velocity = swimStep(dt, camCF, mv, inputMag, wishSpeed)
	elseif slopeSliding then
		velocity = slopeSlideStep(c, dt, t, wishDir)
		swimVelocity = velocity
	elseif slide then
		velocity = slideStep(c, dt, t, wishDir, actualSpeed, grounded)
		swimVelocity = velocity
	elseif grounded or nativeClimb then
		velocity = groundStep(velocity, wishDir, wishSpeed, dt, grip, pushScale)
		-- the world is blocking part of what we command (walls): bleed it off instead of storing it
		local s = velocity.Magnitude
		if s > 0.5 and not nativeClimb then
			local along = actualH:Dot(velocity / s)
			local slack = math.max(3, 0.3 * s)
			if s - along > slack then
				velocity = velocity / s * math.max(along + slack, s - ACC.Brake * dt)
			end
		end
		swimVelocity = velocity
	else
		local airWish = math.min(AIR.wishSpeed, if useBusy then SPD.UseItem else math.huge) * inputMag
		velocity = airStep(velocity, wishDir, airWish, dt)
		local s = velocity.Magnitude
		if s > 0.5 then
			local along = actualH:Dot(velocity / s)
			if s - along > 4 then
				velocity = velocity / s * math.max(along + 4, s - 30 * dt)
			end
		end
		swimVelocity = velocity
	end

	if swimming then
		applyHumanoidMove(humanoid, swimVelocity)
	else
		applyHumanoidMove(humanoid, velocity)
	end
	if velocity.Magnitude <= 0.05 then
		velocity = Vector3.zero
	end

	-- Air gravity (a local force; the kinematic modes cancel gravity instead). Full gravity for the first
	-- moments after walking off a step so slopes and stairs keep you planted.
	if swimming or slopeSliding then
		c.gravityMode = nil
	elseif inAir and (AIR.jumped or t - AIR.startAt > JMP.StickTime) then
		c.gravityMode = if av.Y > 0 then "rise" else "fall"
	elseif AIR.armed then
		c.gravityMode = "rise"
	else
		c.gravityMode = nil
	end

	-- Stumbling: sprinting down steep ground (worse on poor grip) builds instability until you trip
	if grounded and moveState == "Sprint" and G.alongSmooth < -SLOPE.StumbleSin then
		local over = -G.alongSmooth - SLOPE.StumbleSin
		AIR.instability += over * SLOPE.StumbleRate * (actualSpeed / SPD.Sprint) * (1.6 - math.min(grip, 1) * 0.6) * dt
	else
		AIR.instability = math.max(0, AIR.instability - 0.7 * dt)
	end
	if AIR.instability >= 1 then
		stumble(c, t, 0.8)
	end
	motion.stumble = math.clamp(AIR.instability, 0, 1)

	-- State
	local newState
	if swimming then
		newState = "Swim"
	elseif nativeClimb then
		newState = "Climb"
	elseif slide then
		newState = "Slide"
	elseif inAir then
		newState = "Air"
	elseif crouchActive then
		newState = "Crouch"
	elseif sprintAllowed and actualSpeed > SPD.Walk * 0.6 then
		newState = "Sprint"
	elseif inputMag > 0.05 or actualSpeed > 1 then
		newState = "Walk"
	else
		newState = "Idle"
	end
	setState(newState)

	-- Stamina: sprinting (more uphill and on soft ground), steep climbs on foot, hard swimming
	local drained = false
	local uphill = if grounded then math.max(0, G.alongSmooth) else 0
	local working = 0
	if newState == "Sprint" and actualSpeed > SPD.Walk + 0.5 then
		stamina -= STA.SprintDrain * SURF.effort * (1 + 2.5 * uphill) * dt
		drained = true
		working = 0.75 + 0.25 * uphill
	elseif nativeClimb and actualSpeed + math.abs(av.Y) > 1 then
		stamina -= STA.ClimbDrain * dt
		drained = true
		working = 0.7
	elseif swimming and targetSpeed > SWM.Speed + 0.5 and inputMag > 0.3 then
		stamina -= SWM.SprintDrain * dt
		drained = true
		working = 0.7
	elseif grounded and actualSpeed > 2 and uphill > SLOPE.UphillDrainSin then
		-- walking up a steep hill: no recovery, and a slow drain on the steepest ground
		stamina -= SLOPE.UphillDrain * (uphill - SLOPE.UphillDrainSin) * SURF.effort * dt
		drained = true
		working = 0.35 + uphill
	elseif swimming and inputMag > 0.3 then
		working = 0.3
	elseif actualSpeed > SPD.Walk * 0.8 then
		working = 0.2
	end
	if drained then
		lastDrainAt = t
	else
		regenStamina(dt, t, actualSpeed < 1 or crouchActive)
	end
	updateExhaustion()
	updateExertion(dt, working)

	updateStride(c, dt, t, actualSpeed, grounded and not slide, swimming)
	updateStance(c, dt, t, crouchActive)
	writeState(av, grounded)

	motion.surface = SURF.name
	motion.slope = G.alongSmooth
	motion.wade = W.depth
	motion.land = landPose
	debugOut.source = moveSrc.kind
	debugOut.fallback = moveSrc.fallback
	debugOut.targetSpeed = targetSpeed
	debugOut.wishSpeed = wishSpeed
	debugOut.surfaceMult, debugOut.slopeMult, debugOut.wadeMult = surfaceMult, slopeMult, wadeMult
	debugOut.grip = grip
	debugOut.groundAngle = math.deg(math.acos(math.clamp(G.normal.Y, -1, 1)))
	debugOut.alongDeg = math.deg(math.asin(G.alongSmooth))
	debugOut.gravityMode = c.gravityMode or "none"
	debugOut.state = newState
	debugOut.commanded = velocity.Magnitude
	debugOut.jumpHeight = jumpHeight
	debugOut.prep = prepPose
	debugOut.rigScale = c.rig.scale or 1
	debugOut.strideScale = c.rig.strideScale or 1
	-- tuning probes: mirrored onto dbg_* attributes of the local player while it has LS_MoveDebug = true
	if t >= debugNextAt and player:GetAttribute("LS_MoveDebug") == true then
		debugNextAt = t + 0.1
		for key, value in pairs(MovementController.getDebug()) do
			local kind = typeof(value)
			if kind == "number" or kind == "string" or kind == "boolean" then
				player:SetAttribute("dbg_" .. key, value)
			end
		end
	end
end

-- Hand the humanoid back to the default controls so nobody is left stuck if we fail.
local function recover(c, reason: string)
	if recovered or not c or c.dead then
		return
	end
	recovered = true
	pcall(function()
		local humanoid = c.humanoid
		if mantle or climb then
			mantle, climb = nil, nil
		end
		slide = nil
		c.gravityMode = nil
		if c.gravity then
			c.gravity.Enabled = false
		end
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
			if not (ClientState.frozen or player:GetAttribute("Frozen") == true) then
				humanoid.WalkSpeed = SPD.Walk
				humanoid:SetStateEnabled(HumanoidState.Jumping, true)
				jumpEnabledState = true
			end
		end
	end)
	warn("[MovementController] handing control back to the default controls (" .. reason .. ")")
end

local function safeUpdate(dt: number)
	local ok, err = pcall(update, dt)
	if not ok then
		recover(ctx, "update error")
		if os.clock() - errorAt > 5 then
			errorAt = os.clock()
			warn("[MovementController] update error: " .. tostring(err))
		end
	end
end

local function preSimulation(dt: number)
	local c = ctx
	if not c or c.dead or not c.root.Parent then
		return
	end
	local ok, err = pcall(function()
		if mantle then
			stepMantle(c, dt)
		elseif climb then
			stepClimb(c, dt)
		end
		-- keep the local gravity force in sync with the mode
		local gravity = c.gravity
		local mode = c.gravityMode
		if mode == nil or c.root.Anchored then
			if gravity.Enabled then
				gravity.Enabled = false
			end
		else
			local mass = c.root.AssemblyMass
			local g = workspace.Gravity
			local target = 0
			if mode == "rise" then
				target = JMP.RiseGravity
			elseif mode == "fall" then
				target = JMP.FallGravity
			end
			gravity.Force = Vector3.new(0, mass * (g - target), 0)
			if not gravity.Enabled then
				gravity.Enabled = true
			end
		end
	end)
	if not ok then
		recover(c, "simulation error")
		if os.clock() - errorAt > 5 then
			errorAt = os.clock()
			warn("[MovementController] simulation error: " .. tostring(err))
		end
	end
end

local function postSimulation()
	local c = ctx
	if not c then
		return
	end
	if AIR.airborne and c.root.Parent then
		local vy = c.root.AssemblyLinearVelocity.Y
		if vy < AIR.minVy then
			AIR.minVy = vy
		end
	end
	-- watchdog: our render step stopped running (unbound, the thread died, or the client isn't rendering) while alive
	if not c.dead and lastUpdateAt > 0 and os.clock() - lastUpdateAt > 0.75 then
		if not recovered then
			recover(c, "movement step stalled")
		elseif c.humanoid.Parent and c.humanoid.WalkSpeed < 1 and not (ClientState.frozen or player:GetAttribute("Frozen") == true) then
			-- still out, and a freeze (launch plates) ended meanwhile: keep the default controls usable
			c.humanoid.WalkSpeed = SPD.Walk
			c.humanoid:SetStateEnabled(HumanoidState.Jumping, true)
			jumpEnabledState = true
		end
	end
end

-- Input actions ---------------------------------------------------------------------------------------------------------

local function onSprintAction(state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult?
	local began = state == Enum.UserInputState.Begin
	local device = deviceOf(io)
	local mode = modeFor("sprint", device)
	if began and exhausted and mode ~= 2 then
		Feedback.deny("OutOfBreath", "OUT OF BREATH") -- the press still gets an answer
	end
	if mode == 2 then
		-- Auto: a full push already sprints; holding the key jogs instead
		sprintJogHeld = began
		sprintHeld = false
		if sprintToggled then
			setSprintToggle(false)
		end
	elseif mode == 1 then
		if device == "Touch" then
			-- RUN is a toggle button: Begin when switched on, End when off
			if began and exhausted then
				setSprintToggle(false) -- too tired: the button pops back off
			else
				sprintToggled = began
				sprintToggleSource = if began then "Touch" else nil
				if began and crouchToggled then
					setCrouchToggle(false)
				end
			end
		elseif began then
			-- each press switches it; it also ends when you stop moving or run out of breath
			if sprintToggled then
				setSprintToggle(false)
			elseif not exhausted then
				setSprintToggle(true)
				sprintToggleSource = if device == "Gamepad" then "Gamepad" else "Keyboard"
				stickIdleTime = 0
				if crouchToggled then
					setCrouchToggle(false)
				end
			end
		end
	else
		-- Hold
		sprintHeld = began
		if began and crouchToggled then
			setCrouchToggle(false)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onCrouchAction(state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult?
	local began = state == Enum.UserInputState.Begin
	if io and io.KeyCode == Enum.KeyCode.ButtonB and ClientState.menuOpen then
		return Enum.ContextActionResult.Pass
	end
	local device = deviceOf(io)
	local mode = modeFor("crouch", device)
	if mode == 1 and device == "Touch" then
		-- CROUCH is a toggle button: Begin when switched on, End when off
		crouchToggled = began
		if began then
			crouchPressedAt = os.clock()
		end
	elseif mode == 1 then
		if began then
			if climb then
				crouchPressedAt = os.clock() -- the press lets go of the climb; it doesn't toggle the crouch
			else
				setCrouchToggle(not crouchToggled)
				if crouchToggled then
					crouchPressedAt = os.clock()
				end
			end
		end
	else
		if began and not crouchHeld then
			crouchPressedAt = os.clock()
		end
		crouchHeld = began
	end
	return Enum.ContextActionResult.Sink
end

-- (Re)binds Sprint and Crouch when a mode changes: the touch buttons are toggle or hold buttons, and RUN hides on
-- Auto. Held and toggled states reset so nothing sticks.
local boundModes: string? = nil
local function bindModeInputs()
	local parts = {}
	for _, kind in ipairs({ "sprint", "crouch" }) do
		for _, device in ipairs({ "KeyboardMouse", "Gamepad", "Touch" }) do
			table.insert(parts, tostring(modeFor(kind, device)))
		end
	end
	local key = table.concat(parts, ":")
	if key == boundModes then
		return
	end
	boundModes = key
	sprintHeld, sprintJogHeld, crouchHeld = false, false, false
	setSprintToggle(false)
	setCrouchToggle(false)
	local sprintTouch = modeFor("sprint", "Touch")
	local crouchTouch = modeFor("crouch", "Touch")
	Input.bind("Sprint", onSprintAction, {
		keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },
		touch = { toggle = sprintTouch == 1, visible = sprintTouch ~= 2 },
	})
	Input.bind("Crouch", onCrouchAction, {
		keys = { Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB },
		touch = { toggle = crouchTouch == 1 },
	})
end

-- Character lifecycle ---------------------------------------------------------------------------------------------------

local function cleanupCharacter()
	local c = ctx
	if not c then
		return
	end
	ctx = nil
	for _, conn in ipairs(c.conns) do
		conn:Disconnect()
	end
	if c.gravity then
		c.gravity:Destroy()
	end
	if c.attachment then
		c.attachment:Destroy()
	end
	mantle, climb, slide = nil, nil, nil
	AIR.airborne = false
	velocity, swimVelocity = Vector3.zero, Vector3.zero
	crouchAmt, slideAmt, climbAmt = 0, 0, 0
	easedCrouch, easedSlide, easedClimb = 0, 0, 0
	crouchForced = false
	sentStance = nil
	jumpEnabledState = nil
	lastJumpHeight = nil
	lastRootPos = nil
	AIR.bufferedJump, AIR.landSlide, AIR.mantleStep = false, false, nil
	AIR.stunUntil, AIR.stumbleUntil, AIR.instability = 0, 0, 0
	landPose = 0
	prepPose = 0
	AIR.prepAt, AIR.jumpWanted, AIR.firedAt = nil, nil, -math.huge
	ClientState.jumpPrepAt = -math.huge
	motion.exertion = 0
	lastUpdateAt = -math.huge
	setState("Idle")
end

local function onDied(c)
	c.dead = true
	if mantle or climb then
		mantle, climb = nil, nil
		c.humanoid.PlatformStand = false
	end
	slide = nil
	c.gravityMode = nil
	if c.gravity then
		c.gravity.Enabled = false
	end
	setState("Idle")
end

local function setupCharacter(character: Model)
	if ctx and ctx.character == character then
		return
	end
	cleanupCharacter()
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") or player.Character ~= character then
		return
	end
	-- let the rig finish assembling its joints
	local deadline = os.clock() + 3
	while os.clock() < deadline and not (character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso")) do
		task.wait()
	end
	if player.Character ~= character or not humanoid.Parent or ctx then
		return
	end

	local c = {
		character = character,
		humanoid = humanoid,
		root = root,
		conns = {},
		baseHip = humanoid.HipHeight,
		lastSetHip = humanoid.HipHeight,
		dead = humanoid.Health <= 0,
		gravityMode = nil,
	}
	c.rig = MovementController.measureRig(character, humanoid, c.baseHip)
	worldParams.FilterDescendantsInstances = { character }
	waterParams.FilterDescendantsInstances = { character }
	overlapParams.FilterDescendantsInstances = { character }

	humanoid.UseJumpPower = false
	lastJumpHeight = humanoidJumpHeight(JMP.Height)
	humanoid.JumpHeight = lastJumpHeight
	humanoid.MaxSlopeAngle = SLOPE.MaxWalkable
	humanoid.AutoRotate = true
	humanoid.PlatformStand = false

	-- local-only force: lighter air gravity, and gravity cancelling while mantling or climbing
	local attachment = Instance.new("Attachment")
	attachment.Name = "MovementForce"
	attachment.Parent = root
	local gravity = Instance.new("VectorForce")
	gravity.Name = "MovementGravity"
	gravity.Attachment0 = attachment
	gravity.RelativeTo = Enum.ActuatorRelativeTo.World
	gravity.ApplyAtCenterOfMass = true
	gravity.Force = Vector3.zero
	gravity.Enabled = false
	gravity.Parent = root
	c.attachment, c.gravity = attachment, gravity

	stamina, exhausted = 1, false
	lastDrainAt = -math.huge
	jumpEnabledState = nil
	recovered = false
	ctx = c

	table.insert(c.conns, humanoid.StateChanged:Connect(function(old, new)
		onStateChanged(c, old, new)
	end))
	table.insert(c.conns, humanoid.Died:Connect(function()
		onDied(c)
	end))
	table.insert(c.conns, humanoid:GetPropertyChangedSignal("HipHeight"):Connect(function()
		-- avatar scaling (not us) changed the standing height
		if ctx == c and math.abs(humanoid.HipHeight - c.lastSetHip) > 0.01 then
			c.baseHip = humanoid.HipHeight
			c.lastSetHip = humanoid.HipHeight
			c.rig = MovementController.measureRig(character, humanoid, c.baseHip)
			crouchAmt, slideAmt, easedCrouch, easedSlide = 0, 0, 0, 0
		end
	end))
	table.insert(c.conns, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and ctx == c then
			cleanupCharacter()
		end
	end))
end

-- Public API ------------------------------------------------------------------------------------------------------------

function MovementController.getStanceBlend()
	blendOut.crouch = easedCrouch * (1 - easedSlide)
	blendOut.slide = easedSlide
	blendOut.climb = easedClimb
	blendOut.climbPhase = if climb then climb.phase else blendOut.climbPhase
	blendOut.land = smooth01(landPose)
	blendOut.prep = smooth01(prepPose)
	return blendOut
end

function MovementController.getRig()
	return if ctx then ctx.rig else nil
end

function MovementController.stopSprint()
	sprintHeld = false
	autoSprintBlocked = true
	if sprintToggled then
		setSprintToggle(false)
	end
end

function MovementController.addImpulse(v: Vector3)
	if Util.isFiniteVector(v) then
		velocity += Vector3.new(v.X, 0, v.Z)
	end
end

function MovementController.spendStamina(amount: number)
	if type(amount) == "number" and amount == amount and amount > 0 then
		spend(math.min(amount, 1), os.clock())
		updateExhaustion()
	end
end

function MovementController.getMotion()
	return motion
end

function MovementController.getDebug()
	debugOut.stamina = stamina
	debugOut.exhausted = exhausted
	debugOut.surface = SURF.name
	debugOut.surfaceGrip = SURF.grip
	debugOut.wade = W.depth
	debugOut.instability = AIR.instability
	debugOut.exertion = motion.exertion
	debugOut.slide = if slide then slide.kind else "none"
	debugOut.mantle = if mantle then mantle.kind else "none"
	debugOut.climb = climb ~= nil
	return debugOut
end

function MovementController.Init(registry)
	Controllers = registry
	ClientState.moveState = moveState
end

function MovementController.Start()
	bindModeInputs()
	ClientState.settingsChanged:Connect(bindModeInputs)

	-- the move source is found without blocking (and re-found if it is replaced)
	scanMoveSource(os.clock())

	RunService:BindToRenderStep("LS_Movement", Enum.RenderPriority.Character.Value + 1, safeUpdate)
	RunService.PreSimulation:Connect(preSimulation)
	RunService.PostSimulation:Connect(postSimulation)

	player.CharacterAdded:Connect(function(character)
		task.spawn(setupCharacter, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		if ctx and ctx.character == character then
			cleanupCharacter()
		end
	end)
	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end

	local ok, remote = pcall(Net.event, "SetStance")
	if ok then
		setStanceRemote = remote
	else
		warn("[MovementController] SetStance remote missing: " .. tostring(remote))
	end
end

return MovementController
