--[[
	CameraController - camera modes and the procedural "feel" layer (client).

	Modes: locked first person while you are an alive contender in the arena (ClientState.inArena and alive),
	Classic third person in the lobby and after death (zoom Config.Camera.LobbyZoom, limits LobbyMinZoom..LobbyMaxZoom).
	While ClientState.spectating ~= nil this controller does nothing (SpectateController owns the camera), nor while
	ClientState.launchShot is set (the launch intro, LaunchIntroController, owns it; a faceToward asked for meanwhile
	waits until the camera is handed back).

	The default PlayerModule camera rebuilds its CFrame every frame from CurrentCamera.CFrame.LookVector
	(BaseCamera:GetCameraLookVector), so offsets written on top of it would accumulate. We therefore:
	  1. RenderPriority.First       restore the camera to the default camera's own CFrame from last frame,
	  2. RenderPriority.Camera      the default camera updates from that clean CFrame,
	  3. RenderPriority.Camera + 1  we save that base CFrame and write base + procedural offsets.
	Nothing accumulates and nothing can drift. Read the final camera at Camera + 2 or later (viewmodel).

	First-person head motion is derived from the gait (ClientState.strideAlpha: left plant at 0, right at 0.5):
	  - vertical bob at twice the stride rate (walking: lowest at each foot strike; running: lowest just after it,
	    at mid-stance), a smaller sideways sway toward the stance foot, and a tiny nod at each impact. Rotation is
	    kept very small (the eyes stabilise gaze in real life): the motion is mostly translation, for comfort.
	  - step-ups on rocks, roots and voxel terrain are smoothed (the eye height follows a velocity-predicted
	    filter of the root height, at most MaxStepLag studs behind) so the view never jitters; jumps stay crisp: from
	    a take-off (ClientState.jumped) the eye rises at the root's own speed, never held back by the step filter.
	  - a small eye dip with the knee bend before a take-off: down and back up over the dip window
	    (ClientState.jumpPrepAt / jumpPrepTime), in step with Animate's dip-and-extend, so the eye leaves the ground at
	    full height with the body (Config JumpPrepDip),
	    landing dip and pitch scaled by the drop height (ClientState.landed), a knees-absorbing hold after hard
	    landings, a slight lean into fast turns at speed, strafe tilt, slide tilt, mantle effort pitch.
	  - breathing: a slow rest rhythm when idle, and heavier, faster breathing that follows exertion and
	    exhaustion (MovementController.getMotion().exertion).
	  - unsteady footing (sprinting down steep ground) wobbles slightly before a stumble.
	FOV = settings.fov + a subtle sprint/slide add, narrowed by the aim (ClientState.aimAlpha) or by the zoom, never by
	both: the aim ends the zoom, and the view passes from one to the other in a single move, without widening first.
	Zoom, the action "Zoom" (V held; R3 or the touch ZOOM button toggled), is a real look closer. The view magnifies 2.5
	times by default (Config.Camera.ZoomFovMultiplier is that level at BaseFov; the magnification, tan(fov / 2) against
	tan(zoomed / 2), is the same at every Field of view setting). It eases in and out on a critically damped spring
	(ZoomInTime / ZoomOutTime: no overshoot, no snap) and the magnification moves by even ratios on the way.
	  - Level: while the zoom is on, the mouse wheel is the zoom's (the action "ZoomLevel", bound only then and sunk, so
	    the hotbar doesn't also change). Forward is closer. Each notch multiplies or divides the magnification by
	    ZoomWheelStep, from ZoomWheelStepsOut notches wider than the default to ZoomWheelStepsIn closer (1.56x to 4x),
	    easing over ZoomStepTime. The level is kept for the session. A controller and a phone have no level control (D-pad
	    up is the Menu and D-pad down drops): their toggle uses the level last set, the default if none was.
	  - What ends it, and what it waits for: a melee swing, a throw, a bow draw (and the moment after the shot), the aim
	    of a bow or a spear (the aim keeps its own, smaller zoom: V adds nothing to it), eating, drinking, bandaging or
	    putting armor on, and an open menu. When one of these starts, the zoom lets go and comes back only with a new
	    press. V pressed during a swing, a throw, a draw or the aim, and kept held, starts the zoom when the hands are
	    free. Pressed while eating, drinking or bandaging, or under a menu, it does nothing (a held Attack starts the
	    next berry a moment after the last: the zoom would blink in between). R3 and ZOOM pressed during any of them
	    do nothing.
	  - It is bound only while you are alive in the arena or on your plate: not in the lobby, not while spectating, not
	    during the launch shot (and while a cutscene holds the camera, step leaves the FOV alone).
	  - It turns the sprint and slide widening off (sprinting goes on at full speed: the zoom has the view), and the
	    view's own small rotations (bob nod, breathing, landing pitch, kicks, shake) are divided by the magnification, so
	    they sweep the same share of the screen as without the zoom.
	  - Nothing is drawn over the view. ZOOM shares AIM's touch slot and shows only while AIM is hidden (a bow or a spear
	    aims instead).
	settings.headBob scales bob, sway, roll, tilt, turn lean and breathing (0 = off); settings.cameraShake scales
	shakes, kicks and landing impacts. settings.sensitivity scales the default camera's IAS mouse binding
	(Shared.Input.setLookSpeed) with MouseDeltaSensitivity at 1, or MouseDeltaSensitivity itself when those bindings
	don't exist; settings.padLook and touchLook scale its controller and touch bindings. All three, and the arrow keys'
	turn, slow down with the aim or the zoom by the ratio of the view's tangents, so a turn sweeps the same share of the
	screen.
	The look direction is never delayed or smoothed: aiming stays 1:1 with the mouse.
	Writes ClientState.lookDelta (base camera rotation this frame, X = yaw, Y = pitch, radians),
	ClientState.cameraBob (procedural offset in camera space, without the static eye offset), ClientState.fov, and the
	zoom's state for the first-person arms and anyone else:
	  ClientState.zoomAlpha    0 = not zoomed .. 1 = at the current level (eased)
	  ClientState.zoomFovMult  this frame's field-of-view multiplier from the zoom alone, eased: 1 = none, 0.45 at the
	                           default level, 0.29 at the closest (at a Field of view setting of 72)
	  ClientState.zoomMag      the same as a magnification: 1 = none, 2.5 at the default level, 4 at the closest
	(zoomFovMult and zoomMag are set here at load: read them as `ClientState.zoomMag or 1` from code that may run first.)

	Public API (through the Controllers registry):
	  CameraController.getBaseCFrame() -> CFrame   the default camera's CFrame this frame, before our offsets
	  CameraController.isFirstPerson() -> boolean
	  CameraController.shake(amount: number)       same as ClientState.cameraImpulse:Fire(Vector3.zero, amount)
	  CameraController.faceToward(direction: Vector3, pitchDegrees: number?)
	                                               turn the view once: along `direction` (flattened), at `pitchDegrees`
	                                               (0 = level, negative = down), e.g. to the Spire on your plate. It is
	                                               written before the default camera runs, on FACE_FRAMES frames; the
	                                               look is free again right after
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Spring = require(Shared:WaitForChild("Spring"))
local Input = require(Shared:WaitForChild("Input"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local CameraController = {}

local player = Players.LocalPlayer

local CAM = Config.Camera or {}
local MOVE = Config.Movement or {}

local function num(tbl: { [string]: any }, key: string, default: number): number
	local v = tbl[key]
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local K = {
	BaseFov = num(CAM, "BaseFov", 72),
	SprintFov = num(CAM, "SprintFovAdd", 3.5),
	SlideFov = num(CAM, "SlideFovAdd", 6),
	AimFovMult = num(CAM, "AimFovMultiplier", 0.82),
	ZoomFovMult = math.clamp(num(CAM, "ZoomFovMultiplier", 0.45), 0.05, 1), -- the default level, at BaseFov
	ZoomStep = math.clamp(num(CAM, "ZoomWheelStep", 1.125), 1.01, 2), -- magnification ratio of one wheel notch
	ZoomStepsOut = math.clamp(math.floor(num(CAM, "ZoomWheelStepsOut", 4)), 0, 40),
	ZoomStepsIn = math.clamp(math.floor(num(CAM, "ZoomWheelStepsIn", 4)), 0, 40),
	ZoomIn = math.max(num(CAM, "ZoomInTime", 0.18), 0.02), -- seconds
	ZoomOut = math.max(num(CAM, "ZoomOutTime", 0.14), 0.02),
	ZoomStepTime = math.max(num(CAM, "ZoomStepTime", 0.1), 0.02),
	BobWalk = num(CAM, "BobWalkAmplitude", 0.085), -- studs of vertical head travel at jogging pace
	BobSprint = num(CAM, "BobSprintAmplitude", 0.14),
	BobCrouch = num(CAM, "BobCrouchScale", 0.55),
	SwayRatio = num(CAM, "BobSwayRatio", 0.55), -- sideways sway as a fraction of the vertical bob (walking)
	BobRoll = math.rad(num(CAM, "BobRollDegrees", 0.35)),
	BobNod = math.rad(num(CAM, "BobNodDegrees", 0.45)),
	StrafeTilt = math.rad(num(CAM, "StrafeTiltDegrees", 1.2)),
	TurnLean = math.rad(num(CAM, "TurnLeanDegrees", 1.4)),
	SlideTilt = math.rad(num(CAM, "SlideTiltDegrees", 4)),
	LandingDip = num(CAM, "LandingDipMax", 0.7),
	PrepDip = num(CAM, "JumpPrepDip", 0.14),
	LandingPitch = math.rad(num(CAM, "LandingPitchDegrees", 2.4)),
	BreathRest = num(CAM, "IdleBreathAmplitude", 0.012),
	BreathHard = num(CAM, "ExertedBreathAmplitude", 0.045),
	BreathPitchHard = math.rad(num(CAM, "ExertedBreathPitchDegrees", 0.6)),
	ShakeMax = math.rad(num(CAM, "ShakeMaxDegrees", 2.6)),
	ForwardOffset = num(CAM, "ForwardOffset", 0.5),
	LookDownForward = num(CAM, "LookDownForward", 0.55),
	LookDownDrop = num(CAM, "LookDownDrop", 0.3),
	LookUpBack = num(CAM, "LookUpBack", 0.25),
	StepSmoothing = num(CAM, "StepSmoothing", 14), -- 1/s: how fast the eye catches up after a step-up
	MaxStepLag = num(CAM, "MaxStepLag", 1.25),
	LobbyZoom = num(CAM, "LobbyZoom", 12),
	LobbyMinZoom = num(CAM, "LobbyMinZoom", 6),
	LobbyMaxZoom = num(CAM, "LobbyMaxZoom", 20),
	Walk = num(MOVE, "WalkSpeed", 13),
	Sprint = num(MOVE, "SprintSpeed", 21),
	Swim = num(MOVE, "SwimSpeed", 8),
}

local EYE_MARGIN = 0.3 -- keep the near plane this far from walls
local FACE_FRAMES = 3 -- a faceToward turn is written on this many frames in a row, so it holds whatever else runs
-- A critically damped spring is 98 % of the way to its target when speed x time = 5.83: the zoom's times are that point.
local ZOOM_EASE = 5.83
-- How many times bigger things look at the zoom's default level (2.5 for FOV x0.45 at 72).
local ZOOM_MAG = math.max(1,
	math.tan(math.rad(K.BaseFov) / 2) / math.tan(math.rad(K.BaseFov * K.ZoomFovMult) / 2))
-- The wheel is the zoom's while the zoom is on (action "ZoomLevel").
local ZOOM_LEVEL_KEYS = { Enum.UserInputType.MouseWheel }

-- Initial velocity that makes a spring at rest peak at `peak` (so kicks are specified as peak displacements).
local function impulseForPeak(speed: number, damping: number, peak: number): number
	local z = math.clamp(damping, 0.05, 0.995)
	local wd = speed * math.sqrt(1 - z * z)
	local tPeak = math.atan2(wd, z * speed) / wd
	local factor = math.exp(-z * speed * tPeak) * math.sin(wd * tPeak) / wd
	return peak / factor
end

local fovSpring = Spring.new(K.BaseFov, 9, 1)
local bobAmp = Spring.new(0, 7, 1)
local landDip = Spring.new(0, 9, 0.62)
local landPitch = Spring.new(0, 10, 0.6)
local kick = Spring.new(Vector3.zero, 15, 0.75)
local tilt = Spring.new(0, 9, 0.85)
local turnLean = Spring.new(0, 6, 1)
local slideSpring = Spring.new(0, 8, 1)
local mantleSpring = Spring.new(0, 9, 0.8)
local eyeLean = Spring.new(Vector3.zero, 16, 1) -- smooths the stance lean of the eye (x = forward, y = down)

local LAND_DIP_IMPULSE = impulseForPeak(9, 0.62, 1)
local LAND_PITCH_IMPULSE = impulseForPeak(10, 0.6, 1)
local KICK_IMPULSE = impulseForPeak(15, 0.75, 1)

local Controllers = nil
local savedBase: CFrame? = nil -- the default camera's output this frame
local lastSet: CFrame? = nil -- what we wrote on top of it
local savedFocus: CFrame? = nil -- the default camera's Focus this frame (first person: we point Focus ahead of the eye)
local lastFocusSet: CFrame? = nil -- the Focus we wrote
local firstPerson = false
local currentMode: string? = nil
local prevYaw, prevPitch = nil, nil
local clock = 0
local trauma = 0
local slideSign = 1
local lastSensitivity: number? = nil
local lastLookReady: boolean? = nil
local zoomToken = 0
local wasSpectating = false
local errorAt = -math.huge
local breathPhase = 0
local eyeY: number? = nil -- smoothed root height for the eye
local eyeVy = 0 -- filtered vertical speed (prediction)
local eyeCharacter: Model? = nil
local jumpAt = -math.huge -- os.clock() of the last take-off (ClientState.jumped)
local prepCur = 0 -- 0..1 the eye's share of the knee dip before a take-off
local faceLook: Vector3? = nil -- the look direction of a requested turn (faceToward)
local faceFrames = 0 -- frames left to write it
-- the zoom (actions "Zoom" and "ZoomLevel")
local zoomBound = false
local zoomKey = false -- V held, and the zoom is on from it
local zoomWait = false -- V went down while something blocked the zoom and is still held: the zoom starts when that ends
local zoomPad = false -- R3 toggled on
local zoomTouch = false -- the touch ZOOM button toggled on
local zoomButtonShown: boolean? = nil
local zoomNotch = 0 -- the level, in wheel notches from the default (-ZoomStepsOut .. ZoomStepsIn); kept for the session
local zoomLevelBound = false -- the wheel is bound to "ZoomLevel" (only while the zoom is on)
local wheelCarry = 0 -- part of a notch left over (a high-resolution wheel or a trackpad sends fractions)
local wheelAt = -math.huge -- os.clock() of the last wheel input
local zoomSpring = Spring.new(0, ZOOM_EASE / K.ZoomIn, 1) -- 0..1, critically damped
local notchSpring = Spring.new(0, ZOOM_EASE / K.ZoomStepTime, 1) -- the level on its way from notch to notch
local viewMag = 1 -- the magnification of the aim and the zoom together, as applied last frame
local lastPadLook: number? = nil
local lastTouchLook: number? = nil
local lastKeysLook: number? = nil

local eyeParams = RaycastParams.new()
eyeParams.FilterType = Enum.RaycastFilterType.Exclude
eyeParams.IgnoreWater = true
eyeParams.RespectCanCollide = true
local eyeFilterCharacter: Model? = nil

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function getCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, if root and root:IsA("BasePart") then root else nil
end

local function flatForward(cf: CFrame): Vector3
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		local up = cf.UpVector
		flat = Vector3.new(up.X, 0, up.Z) * (if look.Y > 0 then -1 else 1)
	end
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function settingNumber(key: string, default: number, lo: number, hi: number): number
	local settings = ClientState.settings
	local v = if type(settings) == "table" then tonumber(settings[key]) else nil
	if v == nil or v ~= v then
		v = default
	end
	return math.clamp(v :: number, lo, hi)
end

-- Modes ---------------------------------------------------------------------------------------------------------------

local function setThirdPersonZoom(distance: number)
	zoomToken += 1
	local token = zoomToken
	-- pin min = max for a moment so the default camera snaps to the distance, then restore the limits
	player.CameraMaxZoomDistance = math.max(distance, K.LobbyMaxZoom)
	player.CameraMinZoomDistance = distance
	player.CameraMaxZoomDistance = distance
	task.delay(0.15, function()
		if token ~= zoomToken then
			return
		end
		player.CameraMaxZoomDistance = K.LobbyMaxZoom
		player.CameraMinZoomDistance = K.LobbyMinZoom
	end)
end

local function desiredMode(): string?
	if ClientState.spectating ~= nil then
		return nil
	end
	local _, humanoid = getCharacter()
	local alive = humanoid ~= nil and humanoid.Health > 0
	if ClientState.inArena and ClientState.alive and alive then
		return "First"
	end
	-- the Training Centre's hall (TrainingService sets InTraining): first person, as in the arena, so the lent bows,
	-- blades and throws are tried the way they are used. From the arrival in train B, on the platform and in the red
	-- room too (TrainRideService sets AtTrainingCentre): a third-person camera in a 10-stud carriage sits in its walls.
	if alive and (player:GetAttribute("InTraining") == true or player:GetAttribute("AtTrainingCentre") == true) then
		return "First"
	end
	return "Third"
end

local function applyMode()
	local mode = desiredMode()
	if mode == nil then
		return
	end
	if mode == "First" then
		if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end
	else
		if player.CameraMode ~= Enum.CameraMode.Classic then
			player.CameraMode = Enum.CameraMode.Classic
		end
		if currentMode ~= "Third" then
			setThirdPersonZoom(K.LobbyZoom)
		end
	end
	currentMode = mode
end

local function resetFeel()
	bobAmp:reset(0)
	landDip:reset(0)
	landPitch:reset(0)
	kick:reset(Vector3.zero)
	tilt:reset(0)
	turnLean:reset(0)
	slideSpring:reset(0)
	mantleSpring:reset(0)
	eyeLean:reset(Vector3.zero)
	trauma = 0
	eyeY = nil
	eyeVy = 0
	jumpAt = -math.huge
	prepCur = 0
end

-- Zoom ----------------------------------------------------------------------------------------------------------------
-- A real look closer (see the header). V holds it (like Sprint and Crouch on a keyboard); R3 and the touch ZOOM button
-- toggle it (like Sprint on a pad and AIM on touch). step's FOV block takes the stronger of it and the aim, and the aim
-- ends it, so the two never add up.

-- The field of view (vertical degrees) that shows things `mag` times as big as `fov` does.
local function fovAtMagnification(fov: number, mag: number): number
	return 2 * math.deg(math.atan(math.tan(math.rad(fov) / 2) / mag))
end

-- How many times bigger things look at `fov` x `mul` than at `fov` (the other way round).
local function magnificationAt(fov: number, mul: number): number
	return math.tan(math.rad(fov) / 2) / math.tan(math.rad(fov * mul) / 2)
end

-- What other code reads (the header says what each is). zoomFovMult and zoomMag aren't in ClientState's own table, so
-- they go through a cast; they are set once at load, below.
local function publishZoom(alpha: number, fovMult: number, mag: number)
	local state = ClientState :: any
	state.zoomAlpha = alpha
	state.zoomFovMult = fovMult
	state.zoomMag = mag
end
publishZoom(0, 1, 1)

-- The launch shot (the round's intro) has the camera: no zoom while it plays.
local function inLaunchShot(): boolean
	return ClientState.launchShot == true
end

-- (While anything else holds the camera, a cutscene's CameraType, step leaves the FOV alone, so V changes nothing then.)
local function zoomAllowed(): boolean
	return ClientState.inArena == true and ClientState.alive == true and ClientState.spectating == nil
		and not inLaunchShot()
end

-- What the zoom gives way to: a swing, a throw or a bow draw under way (and the moment after a shot), the aim of a bow
-- or a spear (it has its own, smaller zoom), and eating, drinking, bandaging or putting armor on. The hands are busy and
-- would show magnified. Any of these ends the zoom, and none of them can be zoomed into.
local function zoomBlocked(): boolean
	if ClientState.aiming == true or ClientState.useProgress ~= nil then
		return true
	end
	local combat = Controllers and Controllers.CombatController
	return combat ~= nil and combat.current ~= nil
end

local function zoomOn(): boolean
	return zoomBound and (zoomKey or zoomPad or zoomTouch)
end

-- Let go of the zoom. Nothing but a new press brings it back.
local function dropZoom()
	if zoomKey or zoomPad or zoomTouch then
		zoomKey, zoomPad, zoomTouch = false, false, false
		Input.setToggle("Zoom", false)
	end
end

local function onZoom(state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult?
	local touch = io ~= nil and io.UserInputType == Enum.UserInputType.Touch
	local pad = io ~= nil and io.KeyCode == Enum.KeyCode.ButtonR3
	if ClientState.menuOpen then
		-- a menu has the input (refreshZoom lets go of the zoom meanwhile); a touch toggle that switched itself on goes
		-- back off
		if touch then
			Input.setToggle("Zoom", false)
		end
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		local blocked = zoomBlocked() -- busy hands or the aim
		if touch then
			if blocked then
				Input.setToggle("Zoom", false) -- not now, and not later from this tap
			else
				zoomTouch = true
			end
		elseif pad then
			if not blocked then
				zoomPad = not zoomPad
			end
		elseif not blocked then
			zoomKey = true
		elseif ClientState.useProgress == nil then
			-- V is a hold: pressed during a swing, a throw or the bow and kept down, it zooms as soon as the hands are free
			-- (refreshZoom). Not from eating, drinking or bandaging: a held Attack starts the next one a moment after the
			-- last (berry after berry), and the zoom would blink in between.
			zoomWait = true
		end
	elseif touch then
		zoomTouch = false
	elseif not pad then
		zoomKey, zoomWait = false, false -- V let go (End or Cancel)
	end
	return nil
end

-- The wheel while the zoom is on: one level per notch, forward = closer. It is sunk here, so the hotbar (which takes
-- the wheel input nobody else processed) doesn't also change.
local function onZoomLevel(_state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult?
	if not zoomOn() or ClientState.menuOpen then
		return Enum.ContextActionResult.Pass
	end
	local z = if io and io.UserInputType == Enum.UserInputType.MouseWheel then io.Position.Z else 0
	if z == z and z ~= 0 then
		local now = os.clock()
		if now - wheelAt > 0.3 then
			wheelCarry = 0
		end
		wheelAt = now
		wheelCarry += math.clamp(z, -4, 4)
		local notches = math.modf(wheelCarry) -- whole notches, toward zero
		if notches ~= 0 then
			wheelCarry -= notches
			zoomNotch = math.clamp(zoomNotch + notches, -K.ZoomStepsOut, K.ZoomStepsIn)
		end
	end
	return nil
end

-- Every frame: bind or unbind with the state, keep the touch button out of AIM's way, let go while a menu is open or
-- the hands are busy, and take or give back the wheel.
local function refreshZoom()
	local allowed = zoomAllowed()
	if allowed ~= zoomBound then
		zoomBound = allowed
		zoomKey, zoomWait, zoomPad, zoomTouch = false, false, false, false
		zoomButtonShown = nil
		if allowed then
			Input.bind("Zoom", onZoom, {
				keys = { Enum.KeyCode.V, Enum.KeyCode.ButtonR3 },
				touch = { toggle = true, visible = false }, -- shown below; Theme.TouchLayout.Zoom is AIM's slot
			})
		else
			Input.unbind("Zoom") -- (the view eases back out in step; where step stands down, resetZoom clears it)
		end
	end
	if zoomBound then
		-- ZOOM shows only while AIM is hidden: with a bow or a spear in hand AIM has the slot, and so does GUARD (the
		-- same button, bound as GUARD with fists or any melee weapon since Combat_v3). (hunt1_2, 20 Nov: this used to
		-- ask only "bow or spear?", so with fists or a sword ZOOM and GUARD were both drawn in the one slot on a phone.)
		-- The AIM button's own ShowOnTouch (Input.setTouchVisible, CombatController.refreshTouchButtons) is the answer.
		local combat = Controllers and Controllers.CombatController
		local aimShown = false
		local aimButton = Input.getTouchButton("Aim")
		local aimFlag = if aimButton then aimButton:GetAttribute("ShowOnTouch") else nil
		if type(aimFlag) == "boolean" then
			aimShown = aimFlag
		elseif combat and type(combat.getEquipped) == "function" and type(combat.canAimWith) == "function" then
			local _, def = combat.getEquipped()
			aimShown = combat.canAimWith(def) == true
		end
		if zoomButtonShown ~= (not aimShown) then
			zoomButtonShown = not aimShown
			Input.setTouchVisible("Zoom", not aimShown)
			if aimShown and zoomTouch then
				zoomTouch = false
				Input.setToggle("Zoom", false)
			end
		end
		-- a menu, busy hands and the aim let go of the zoom, and it doesn't come back by itself afterwards. Only a V that
		-- went down during a swing, a throw or the bow, and is still held, starts it when the hands are free.
		if ClientState.menuOpen or ClientState.useProgress ~= nil then
			dropZoom()
			zoomWait = false
		elseif zoomBlocked() then
			dropZoom()
		elseif zoomWait then
			zoomWait = false
			zoomKey = true
		end
	end
	-- the wheel is the zoom's only while the zoom is on; the rest of the time it isn't bound here at all
	local on = zoomOn()
	if on ~= zoomLevelBound then
		zoomLevelBound = on
		wheelCarry = 0
		if on then
			Input.bind("ZoomLevel", onZoomLevel, { keys = ZOOM_LEVEL_KEYS })
		else
			Input.unbind("ZoomLevel")
		end
	end
end

-- The zoom this frame: its share 0..1 (eased), the magnification it gives (1 = none), and the magnification it is
-- heading to (the level while it is on, 1 while it is off).
local function easeZoom(dt: number): (number, number, number)
	local on = zoomOn()
	local heading = if on then math.max(1, ZOOM_MAG * K.ZoomStep ^ zoomNotch) else 1
	zoomSpring.target = if on then 1 else 0
	zoomSpring.speed = ZOOM_EASE / (if on then K.ZoomIn else K.ZoomOut)
	local z = math.clamp(zoomSpring:update(dt), 0, 1)
	if not on and z < 1e-3 then
		zoomSpring:reset(0)
		z = 0
	elseif on and z > 1 - 1e-3 then
		z = 1 -- (the spring keeps closing the last thousandth; readers get a clean 1)
	end
	if z <= 0 then
		notchSpring:reset(zoomNotch) -- not zoomed: nothing to ease, the next press goes straight to the level
		return 0, 1, heading
	end
	-- the level eases from notch to notch, and the way in and out is a power of it: the magnification moves by even
	-- ratios, so the zoom's speed looks the same from start to end
	notchSpring.target = zoomNotch
	local notch = math.clamp(notchSpring:update(dt), -K.ZoomStepsOut, K.ZoomStepsIn)
	local level = math.max(1, ZOOM_MAG * K.ZoomStep ^ notch)
	return z, level ^ z, heading
end

-- Nothing of the zoom is left in the view: step isn't writing the FOV (a spectate, the launch shot, a cutscene).
local function resetZoom()
	zoomSpring:reset(0)
	notchSpring:reset(zoomNotch)
	viewMag = 1
	publishZoom(0, 1, 1)
end

-- Render steps --------------------------------------------------------------------------------------------------------

-- RenderPriority.First: hand the default camera back its own CFrame so our offsets never feed into it.
local function restoreBase()
	local cam = workspace.CurrentCamera
	if lastSet and savedBase and cam then
		local cur = cam.CFrame
		if (cur.Position - lastSet.Position).Magnitude < 1e-3 and cur.LookVector:Dot(lastSet.LookVector) > 0.99999
			and cur.UpVector:Dot(lastSet.UpVector) > 0.99999 then
			cam.CFrame = savedBase
		end
	end
	-- hand the default camera its own Focus back too (step() points Focus ahead of the eye in first person)
	if cam and lastFocusSet and savedFocus and (cam.Focus.Position - lastFocusSet.Position).Magnitude < 1e-3 then
		cam.Focus = savedFocus
	end
	-- a requested turn (faceToward): the default camera, next to run, rebuilds its CFrame from this look direction
	if faceFrames > 0 and not ClientState.launchShot then -- (a turn asked for during the launch intro waits for it)
		faceFrames -= 1
		if cam and faceLook and ClientState.spectating == nil and cam.CameraType == Enum.CameraType.Custom then
			local position = cam.CFrame.Position
			cam.CFrame = CFrame.lookAt(position, position + faceLook)
			prevYaw = nil -- not a look movement: no viewmodel sway or turn lean from it
		end
	end
	lastSet = nil
	lastFocusSet = nil
end

local function updateSensitivity(aimMul: number, baseFov: number)
	local sens = settingNumber("sensitivity", 1, 0.05, 10)
	local scale = 1
	if aimMul < 0.999 then
		-- keep the look feel consistent when the FOV zooms in (aiming or the zoom)
		scale = math.tan(math.rad(baseFov * aimMul) / 2) / math.tan(math.rad(baseFov) / 2)
	end
	local desired = sens * scale
	local ready = Input.lookBindingsReady()
	-- (a change of 1 part in 10,000 is applied: at the closest zoom the speed is a quarter, and its last step counts)
	if lastSensitivity == nil or math.abs(desired - lastSensitivity) > 1e-4 or ready ~= lastLookReady then
		lastSensitivity = desired
		lastLookReady = ready
		-- QW13: Roblox's camera reads the mouse through its IAS CameraRotationAction. Scale that binding when it exists and
		-- keep MouseDeltaSensitivity at 1, so the speed applies exactly once whichever one the engine honours.
		if ready and Input.setLookSpeed("Mouse", desired) then
			UserInputService.MouseDeltaSensitivity = 1
		else
			UserInputService.MouseDeltaSensitivity = desired
		end
	end
	-- the controller and touch look speeds (settings.padLook, touchLook) slow by the same ratio. SettingsController applies
	-- them unscaled when a setting changes; settingsChanged clears lastPadLook, so they're applied again here, scaled.
	local pad = settingNumber("padLook", 1, 0.05, 10) * scale
	local touch = settingNumber("touchLook", 1, 0.05, 10) * scale
	if lastPadLook == nil or lastTouchLook == nil or math.abs(pad - (lastPadLook :: number)) > 1e-4
		or math.abs(touch - (lastTouchLook :: number)) > 1e-4 then
		lastPadLook, lastTouchLook = pad, touch
		Input.setLookSpeed("Gamepad", pad)
		Input.setLookSpeed("Touch", touch)
	end
	-- the arrow keys turn the view as well (Roblox's own binding, a fixed 2 radians a second: four screen widths a
	-- second at the closest zoom if left alone). It has no setting of ours; it slows by the same ratio.
	if lastKeysLook == nil or math.abs(scale - (lastKeysLook :: number)) > 1e-4 then
		lastKeysLook = scale
		Input.setLookSpeed("Keys", scale)
	end
end

-- Eye height that follows the root smoothly over step-ups and voxel bumps (velocity-predicted, so slopes
-- and jumps don't lag), never more than MaxStepLag behind.
local function smoothedRootY(character: Model, root: BasePart, grounded: boolean, dt: number): number
	local rootY = root.Position.Y
	if eyeY == nil or character ~= eyeCharacter or math.abs(rootY - (eyeY :: number)) > 6 then
		eyeCharacter = character
		eyeY = rootY
		eyeVy = root.AssemblyLinearVelocity.Y
		return rootY
	end
	local vy = root.AssemblyLinearVelocity.Y
	-- A take-off: the eye leaves with the body at the root's own speed. (`grounded` is a frame late here, so the step
	-- smoothing held the eye 0.3-0.45 studs under the rising root for ~70 ms, and in a downward view the torso came
	-- right up to the camera.) An offset the eye already had (a step-up just before) still eases out.
	local launched = vy > 0 and os.clock() - jumpAt < 0.6
	if launched then
		eyeVy = vy
	elseif grounded and math.abs(vy) < math.abs(eyeVy) then
		-- a landing (or the end of a step pop): don't carry the old speed on into the ground (a deep false dip)
		if eyeVy < -8 then
			eyeY = math.min(eyeY :: number, rootY) -- touch-down: the eye arrives with the body; the landing dip does the rest
		end
		eyeVy = vy
	else
		eyeVy += (vy - eyeVy) * expAlpha(if grounded then 10 else 40, dt)
	end
	local y = (eyeY :: number) + eyeVy * dt
	y += (rootY - y) * expAlpha(if grounded and not launched then K.StepSmoothing else 40, dt)
	y = math.clamp(y, rootY - K.MaxStepLag, rootY + K.MaxStepLag)
	eyeY = y
	return y
end

local function step(dt: number)
	dt = math.clamp(dt, 0, 0.1)
	clock += dt
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	refreshZoom()
	local spectating = ClientState.spectating ~= nil
	if not spectating then
		applyMode()
	end
	local base = cam.CFrame
	savedBase = base
	firstPerson = player.CameraMode == Enum.CameraMode.LockFirstPerson and (cam.Focus.Position - base.Position).Magnitude < 1.05

	-- how far the (base) camera turned this frame
	local look = base.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	local yawDelta = 0
	if prevYaw then
		local dy = yaw - prevYaw
		if dy > math.pi then
			dy -= 2 * math.pi
		elseif dy < -math.pi then
			dy += 2 * math.pi
		end
		yawDelta = dy
		ClientState.lookDelta = Vector2.new(dy, pitch - prevPitch)
	else
		ClientState.lookDelta = Vector2.zero
	end
	prevYaw, prevPitch = yaw, pitch

	if spectating or ClientState.launchShot or cam.CameraType ~= Enum.CameraType.Custom then
		-- SpectateController, the launch intro or a cutscene owns the camera: hands off
		if not wasSpectating then
			resetFeel()
			if spectating then
				-- nobody writes the field of view while you spectate: leave it at the setting, never part-way out of a zoom
				local fov = settingNumber("fov", K.BaseFov, 40, 110)
				fovSpring:reset(fov)
				cam.FieldOfView = fov
				ClientState.fov = fov
			end
		end
		wasSpectating = true
		ClientState.cameraBob = CFrame.identity
		resetZoom()
		return
	end
	if wasSpectating then
		ClientState.lookDelta = Vector2.zero -- handed back: the camera's jump isn't a look movement (no sway from it)
	end
	wasSpectating = false

	local headBob = settingNumber("headBob", 1, 0, 1)
	local shakeScale = settingNumber("cameraShake", 1, 0, 1)
	local baseFov = settingNumber("fov", K.BaseFov, 40, 110)

	-- The zoom this frame (worked out first: the feel layer below is calmed by it, the FOV block at the end applies it)
	local zoom, zoomMag, zoomHeading = easeZoom(dt)
	local zoomMul = if zoomMag > 1 then fovAtMagnification(baseFov, zoomMag) / baseFov else 1
	publishZoom(zoom, zoomMul, zoomMag)

	local state = ClientState.moveState
	local speed = tonumber(ClientState.speed) or 0
	local grounded = ClientState.grounded == true
	local vel = if typeof(ClientState.velocity) == "Vector3" then ClientState.velocity else Vector3.zero
	local movement = Controllers and Controllers.MovementController
	local blend = if movement and type(movement.getStanceBlend) == "function" then movement.getStanceBlend() else nil
	local rig = if movement and type(movement.getRig) == "function" then movement.getRig() else nil
	local motion = if movement and type(movement.getMotion) == "function" then movement.getMotion() else nil
	local exertion = if motion then math.clamp(tonumber(motion.exertion) or 0, 0, 1) else 0
	local unsteady = if motion then math.clamp(tonumber(motion.stumble) or 0, 0, 1) else 0

	local fwd = flatForward(base)
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	local localVel = base:VectorToObjectSpace(Vector3.new(vel.X, 0, vel.Z))

	-- Gait: amplitude from speed (walk -> jog -> sprint), phase from the footsteps
	local target = 0
	local onFoot = grounded and (state == "Walk" or state == "Sprint" or state == "Crouch" or state == "Idle")
	if onFoot then
		if speed <= K.Walk then
			target = K.BobWalk * math.clamp(speed / K.Walk, 0, 1) ^ 0.9
		else
			target = K.BobWalk + (K.BobSprint - K.BobWalk) * math.clamp((speed - K.Walk) / math.max(K.Sprint - K.Walk, 1), 0, 1)
		end
		if state == "Crouch" then
			target *= K.BobCrouch
		end
	elseif state == "Swim" then
		target = K.BobWalk * 0.6 * math.clamp(speed / K.Swim, 0, 1)
	end
	bobAmp.target = target
	local amp = math.max(0, bobAmp:update(dt)) * headBob
	local run = math.clamp((speed - 9) / 8, 0, 1) -- 0 = walking gait, 1 = running gait
	-- walking: the body is lowest at each heel strike; running: lowest a little later, at mid-stance
	local theta = ((tonumber(ClientState.strideAlpha) or 0) - 0.07 * run) * 2 * math.pi
	local bobY = -math.cos(2 * theta) * amp * 0.5
	local bobX = -math.sin(theta) * amp * (K.SwayRatio - 0.25 * run)
	local ampN = amp / math.max(K.BobSprint, 1e-3)
	local bobRoll = math.sin(theta) * K.BobRoll * ampN
	local bobPitch = -math.cos(2 * theta) * K.BobNod * ampN * (0.35 + 0.65 * run)
	if state == "Swim" then
		-- strokes: a slow surge rather than footfalls
		bobY = -math.cos(2 * theta) * amp * 0.6
		bobX, bobRoll = 0, math.sin(theta) * K.BobRoll * 1.5 * ampN
		bobPitch = 0
	end

	-- Breathing: slow at rest, heavier and faster with exertion (never stronger than a gentle sway)
	local idleness = 1 - math.clamp(speed / 3, 0, 1)
	local rate = 0.22 + 0.38 * exertion
	breathPhase = (breathPhase + 2 * math.pi * rate * dt) % (2 * math.pi)
	local breath = math.sin(breathPhase)
	local breathAmp = (K.BreathRest * idleness + K.BreathHard * exertion * (0.5 + 0.5 * idleness)) * headBob
	local breathY = breath * breathAmp
	local breathPitch = (breath * math.rad(0.12) * idleness + breath * K.BreathPitchHard * exertion * (0.4 + 0.6 * idleness)) * headBob

	-- Strafe tilt (lean into sideways motion) and a lean into fast turns at speed
	tilt.target = -math.clamp(localVel.X / K.Walk, -1.3, 1.3) * K.StrafeTilt * headBob
	local tiltRoll = tilt:update(dt)
	local yawRate = if dt > 1e-4 then yawDelta / dt else 0
	local lean = if grounded and onFoot then math.clamp(yawRate * speed / (4 * K.Sprint), -1, 1) else 0
	turnLean.target = lean * K.TurnLean * headBob
	local turnRoll = turnLean:update(dt)

	-- Unsteady footing before a stumble
	local wobble = unsteady * unsteady * headBob
	local wobbleRoll = wobble * math.rad(0.8) * math.noise(clock * 3.1, 2.7, 0.4)
	local wobbleY = wobble * 0.04 * math.noise(5.3, clock * 3.7, 1.1)

	-- Slide tilt, mantle effort
	local sliding = state == "Slide"
	if sliding and slideSpring.target < 0.5 then
		slideSign = if localVel.X > 2 then -1 else 1
	end
	slideSpring.target = if sliding then 1 else 0
	local slideAmt = math.clamp(slideSpring:update(dt), 0, 1)
	local slideRoll = slideAmt * K.SlideTilt * headBob * slideSign
	mantleSpring.target = if state == "Mantle" then math.rad(-4) else 0
	local mantlePitch = mantleSpring:update(dt) * headBob

	-- Impacts
	local dip = landDip:update(dt)
	local landP = landPitch:update(dt)
	local k = kick:update(dt)
	trauma = math.max(0, trauma - dt * 1.6)
	local sh = trauma * trauma * shakeScale
	local shakePitch = K.ShakeMax * sh * 2 * math.noise(clock * 17, 0.3, 1.7)
	local shakeYaw = K.ShakeMax * sh * 2 * math.noise(0.9, clock * 17, 5.1)
	local shakeRoll = K.ShakeMax * 0.6 * sh * 2 * math.noise(4.2, 7.7, clock * 17)
	-- the legs keep absorbing a hard landing for a moment; the knee dip before a take-off
	local landHold = if blend then (tonumber(blend.land) or 0) else 0
	-- (the dip is deepest early in the window and back to full height at the take-off; the shorter dip on the move
	-- is shallower)
	local prepLen = math.max(tonumber(ClientState.jumpPrepTime) or 0.1, 0.03)
	local prepU = (os.clock() - (tonumber(ClientState.jumpPrepAt) or -math.huge)) / prepLen
	if prepU >= 0 and prepU < 1 then
		prepCur = math.sin(math.pi * prepU ^ 0.75) * math.clamp(prepLen / 0.1, 0.4, 1)
	else
		prepCur *= math.exp(-25 * dt)
	end
	local prepDip = prepCur * K.PrepDip

	local final: CFrame
	local procedural: CFrame
	local character, _, root = getCharacter()
	if firstPerson and root and character then
		if character ~= eyeFilterCharacter then
			eyeFilterCharacter = character
			eyeParams.FilterDescendantsInstances = { character :: Model }
		end
		-- Eye: in front of the head (following the stance lean), pivoting forward when looking down
		local headLocal = if rig then rig.headCenter else Vector3.new(0, 1.5, 0)
		local leanFwd, leanDown = 0, 0
		local visuals = Controllers and Controllers.CharacterVisuals
		if blend and rig and visuals and type(visuals.headLean) == "function" then
			leanFwd, leanDown = visuals.headLean(rig, blend.crouch, blend.slide)
		end
		if rig and not rig.r15 then
			leanDown += 1.1 * (tonumber(ClientState.crouchAlpha) or 0) -- R6: no hip-height crouch, lower the eye instead
		end
		eyeLean.target = Vector3.new(leanFwd, leanDown, 0)
		local leanV = eyeLean:update(dt)
		local rootCF = root.CFrame
		local rootPos = rootCF.Position
		local rootY = smoothedRootY(character, root, grounded, dt)
		local bodyFwd = flatForward(rootCF)
		local headWorld = Vector3.new(rootPos.X, rootY + headLocal.Y + 0.1 - leanV.Y, rootPos.Z) + bodyFwd * (leanV.X - headLocal.Z)
		local sinP = math.clamp(look.Y, -1, 1)
		local fwdOffset = K.ForwardOffset + (if sinP < 0 then -sinP * K.LookDownForward else -sinP * K.LookUpBack)
		local upOffset = if sinP < 0 then sinP * K.LookDownDrop else 0
		local desired = headWorld + fwd * fwdOffset + Vector3.new(0, upOffset, 0)
		-- never push the eye through a wall
		local from = Vector3.new(rootPos.X, rootY + headLocal.Y, rootPos.Z)
		local delta = desired - from
		local dist = delta.Magnitude
		if dist > 1e-3 then
			local hit = workspace:Raycast(from, delta.Unit * (dist + EYE_MARGIN), eyeParams)
			if hit then
				desired = from + delta.Unit * math.max(0, hit.Distance - EYE_MARGIN)
			end
		end
		local hold = -landHold * 0.22 - prepDip
		local transWorld = Vector3.new(0, bobY + breathY + wobbleY + (dip + hold) * shakeScale, 0) + right * bobX
		local pitchTotal = bobPitch + breathPitch + landP * shakeScale + mantlePitch + k.X + shakePitch
		local yawTotal = k.Y + shakeYaw
		local rollTotal = bobRoll + tiltRoll + turnRoll + slideRoll + wobbleRoll + k.Z + shakeRoll
		-- Under the zoom these small pitches and yaws would show magnified (at 4x a 0.45 degree nod moves the picture as
		-- far as 1.8 degrees does unzoomed). Divided by the magnification they sweep the same share of the screen as
		-- without it. Roll isn't magnified, so it stays.
		local calm = 1 / zoomMag
		local rot = CFrame.Angles(pitchTotal * calm, yawTotal * calm, 0) * CFrame.Angles(0, 0, rollTotal)
		procedural = CFrame.new(base.Rotation:VectorToObjectSpace(transWorld)) * rot
		final = CFrame.new(desired + transWorld) * base.Rotation * rot
	else
		-- third person: only impacts, softer
		eyeY = nil
		local rot = CFrame.Angles((k.X + shakePitch) * 0.5, (k.Y + shakeYaw) * 0.5, (k.Z + shakeRoll) * 0.5)
		procedural = rot
		final = base * rot
	end
	cam.CFrame = final
	lastSet = final
	if firstPerson then
		-- The engine turns the character toward (Focus - camera position). The default Focus sits at the head,
		-- behind our eye, so in first person the body faced backwards and the server's facing check threw away
		-- every shot and swing. Point Focus just ahead of the eye; restoreBase hands the default camera its own
		-- Focus back before it runs next frame.
		savedFocus = cam.Focus
		local ahead = CFrame.new(final.Position + final.LookVector)
		cam.Focus = ahead
		lastFocusSet = ahead
	end
	ClientState.cameraBob = procedural

	-- FOV: a subtle widening at a full sprint, a little more in a slide; the aim and the zoom narrow it
	local sprintAmt = 0
	if state == "Sprint" then
		sprintAmt = math.clamp((speed - K.Walk) / math.max(K.Sprint - K.Walk, 1), 0, 1)
	end
	local aim = math.clamp(tonumber(ClientState.aimAlpha) or 0, 0, 1)
	-- no sprint or slide widening under the zoom or the aim (the zoom has the view: its level is exact)
	local adds = K.SprintFov * sprintAmt * (1 - math.max(aim, zoom)) + K.SlideFov * slideAmt * (1 - zoom)
	if not firstPerson then
		adds *= 0.5
	end
	fovSpring.target = baseFov + adds
	-- The aim and the zoom never add up: the aim ends the zoom. Alone, each has exactly its own ease (the aim's is
	-- CombatController's aimAlpha, as it was before the zoom existed; the zoom's is level ^ zoom). When one lets go as
	-- the other comes on (the aim ends the zoom; a V kept held zooms as the aim is let go), the zoom eases between the
	-- aim's view and its own level, by even ratios, so the view passes from one to the other in a single move...
	local aimMag = if aim > 0 then magnificationAt(baseFov, 1 + (K.AimFovMult - 1) * aim) else 1
	local mag = aimMag ^ (1 - zoom) * zoomMag
	-- ...and it never moves away from where it is heading (the aim's own view while aiming, the zoom's level while it is
	-- on): for a frame or two the two eases can still cross, and the view would pump out and back in.
	local headingMag = math.max(if ClientState.aiming == true then magnificationAt(baseFov, K.AimFovMult) else 1, zoomHeading)
	if viewMag >= headingMag then
		mag = math.max(mag, headingMag) -- closer than that: ease out to it, not past it
	else
		mag = math.min(math.max(mag, viewMag), headingMag) -- wider than that: ease in to it, never wider first
	end
	viewMag = mag
	local viewMul = if mag > 1 then fovAtMagnification(baseFov, mag) / baseFov else 1
	local fov = math.clamp(fovSpring:update(dt) * viewMul, 1, 120)
	cam.FieldOfView = fov
	ClientState.fov = fov
	updateSensitivity(viewMul, baseFov)
end

local function safeStep(dt: number)
	local ok, err = pcall(step, dt)
	if not ok and os.clock() - errorAt > 5 then
		errorAt = os.clock()
		warn("[CameraController] " .. tostring(err))
	end
end

-- The train lobby (mp-retest2, 18 Nov): Roblox's camera stops at opaque walls but passes through the cars' window
-- glass, so a player standing by a window with the view turned inward had the camera outside the train, looking in
-- through the glass. In the lobby's third person the camera stops just inside the car instead: one ray a frame from
-- the camera's focus to the camera against the cars only (workspace.Lobby's Models: not its scenery, lamps or
-- spawns), and the camera moves forward along its own look line (the zoom and the turn are untouched).
local LOBBY_NEAR = 450 -- studs from the lobby's pivot inside which the stop runs
local LOBBY_GAP = 0.6 -- studs the camera keeps from a wall or a pane
local lobbyParams = RaycastParams.new()
lobbyParams.FilterType = Enum.RaycastFilterType.Include
lobbyParams.IgnoreWater = true
local lobbyCars: Instance? = nil
local lobbyCount = -1
local function lobbyStop()
	if firstPerson or ClientState.spectating ~= nil or ClientState.launchShot or ClientState.inArena then
		return
	end
	local cam = workspace.CurrentCamera
	local lobby = workspace:FindFirstChild("Lobby")
	if not (cam and lobby and lobby:IsA("Model")) or cam.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local focus = cam.Focus.Position
	if (focus - lobby:GetPivot().Position).Magnitude > LOBBY_NEAR then
		return
	end
	if lobbyCars ~= lobby or lobbyCount ~= #lobby:GetChildren() then
		lobbyCars = lobby
		lobbyCount = #lobby:GetChildren()
		local list = {}
		for _, child in ipairs(lobby:GetChildren()) do
			if child:IsA("Model") then
				table.insert(list, child)
			end
		end
		lobbyParams.FilterDescendantsInstances = list
	end
	local position = cam.CFrame.Position
	local offset = position - focus
	local distance = offset.Magnitude
	if distance < 0.5 then
		return
	end
	local hit = workspace:Raycast(focus, offset, lobbyParams)
	if hit and hit.Distance < distance then
		local keep = math.max(hit.Distance - LOBBY_GAP, 0.5)
		cam.CFrame = cam.CFrame + offset.Unit * (keep - distance)
	end
end

-- Back in the train after a death (or after spectating): the new character stands wherever the car's spawn put it,
-- and Roblox's camera kept the old look direction, so it could sit pressed against a side wall with half the screen
-- grey wall (wave10 final, picture 06). Turn the view so the camera behind the avatar has the most room: of 16
-- directions, the one with the longest clear line from the head (up to the lobby zoom) and the most room to either
-- side where the camera ends up, looking back over the avatar a little from above.
local arrivalParams = RaycastParams.new()
arrivalParams.FilterType = Enum.RaycastFilterType.Exclude
arrivalParams.IgnoreWater = true
local function placeLobbyView()
	if ClientState.inArena or ClientState.spectating ~= nil or ClientState.launchShot then
		return
	end
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local lobby = workspace:FindFirstChild("Lobby")
	if not (head and head:IsA("BasePart") and lobby and lobby:IsA("Model")) then
		return
	end
	if (head.Position - lobby:GetPivot().Position).Magnitude > LOBBY_NEAR then
		return
	end
	arrivalParams.FilterDescendantsInstances = { character :: Instance }
	local reach = K.LobbyZoom
	local from = head.Position + Vector3.yAxis * 0.5
	local best, bestScore = nil, -math.huge
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		local d = Vector3.new(math.sin(a), 0, math.cos(a))
		local hit = workspace:Raycast(from, d * reach, arrivalParams)
		local clear = if hit then hit.Distance else reach
		local at = from + d * math.max(clear - LOBBY_GAP, 0)
		local side = Vector3.new(-d.Z, 0, d.X)
		local l = workspace:Raycast(at, side * 6, arrivalParams)
		local r = workspace:Raycast(at, -side * 6, arrivalParams)
		local room = math.min(if l then l.Distance else 6, if r then r.Distance else 6)
		local score = clear + 1.5 * math.min(room, 4)
		if score > bestScore + 0.05 then
			best, bestScore = d, score
		end
	end
	if best then
		CameraController.faceToward(-best, -12)
	end
end

-- Public API ------------------------------------------------------------------------------------------------------------

function CameraController.getBaseCFrame(): CFrame
	if savedBase then
		return savedBase
	end
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame else CFrame.identity
end

function CameraController.isFirstPerson(): boolean
	return firstPerson
end

function CameraController.shake(amount: number)
	if type(amount) == "number" and amount == amount then
		trauma = math.clamp(trauma + amount, 0, 1)
	end
end

function CameraController.faceToward(direction: Vector3, pitchDegrees: number?)
	if typeof(direction) ~= "Vector3" then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local length = flat.Magnitude
	if not (length > 1e-3 and length < math.huge) then
		return
	end
	local pitch = math.rad(math.clamp(tonumber(pitchDegrees) or 0, -80, 80))
	faceLook = flat.Unit * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
	faceFrames = FACE_FRAMES
end

function CameraController.Init(registry)
	Controllers = registry
end

function CameraController.Start()
	player.CameraMaxZoomDistance = K.LobbyMaxZoom
	player.CameraMinZoomDistance = K.LobbyMinZoom
	fovSpring:reset(settingNumber("fov", K.BaseFov, 40, 110))

	RunService:BindToRenderStep("LS_CameraRestore", Enum.RenderPriority.First.Value, restoreBase)
	RunService:BindToRenderStep("LS_CameraFeel", Enum.RenderPriority.Camera.Value + 1, safeStep)
	RunService:BindToRenderStep("LS_CameraLobbyStop", Enum.RenderPriority.Camera.Value + 2, function()
		local ok, err = pcall(lobbyStop)
		if not ok and os.clock() - errorAt > 5 then
			errorAt = os.clock()
			warn("[CameraController] lobby stop: " .. tostring(err))
		end
	end)

	ClientState.landed:Connect(function(impact)
		if type(impact) ~= "number" or impact ~= impact then
			return
		end
		-- impact is normalised to standard gravity: recover the drop height and scale by it
		local h = impact * impact / (2 * math.max(workspace.Gravity, 1))
		local k = math.clamp(h / 9, 0.06, 1.25)
		landDip:impulse(-k * K.LandingDip * LAND_DIP_IMPULSE)
		landPitch:impulse(-k * K.LandingPitch * LAND_PITCH_IMPULSE)
		if h > 8 then
			trauma = math.min(1, trauma + math.clamp((h - 8) / 25, 0, 0.5))
		end
	end)
	ClientState.jumped:Connect(function()
		jumpAt = os.clock()
	end)
	ClientState.cameraImpulse:Connect(function(kickVec, shake)
		local scale = settingNumber("cameraShake", 1, 0, 1)
		if typeof(kickVec) == "Vector3" and kickVec == kickVec then
			kick:impulse(kickVec * KICK_IMPULSE * scale)
		end
		if type(shake) == "number" and shake == shake then
			trauma = math.clamp(trauma + shake, 0, 1)
		end
	end)
	ClientState.settingsChanged:Connect(function()
		lastSensitivity = nil -- re-apply on the next frame (mouse, controller and touch)
		lastPadLook = nil
	end)
	ClientState.lifeChanged:Connect(function()
		if ClientState.spectating == nil then
			applyMode()
		end
	end)
	ClientState.spectateChanged:Connect(function(target)
		if target == nil then
			-- spectating ended: make sure the camera follows our own character again
			local cam = workspace.CurrentCamera
			local _, humanoid = getCharacter()
			if cam and humanoid then
				cam.CameraType = Enum.CameraType.Custom
				cam.CameraSubject = humanoid
			end
			currentMode = nil
			applyMode()
			task.delay(0.35, placeLobbyView) -- back to the train from spectating: the same room-finding turn
		end
	end)
	local hadCharacter = player.Character ~= nil
	player.CharacterAdded:Connect(function(character)
		resetFeel()
		prevYaw = nil
		-- a later character (after a death): if it is in the train, turn the view to where the car has room
		if hadCharacter then
			task.delay(0.35, function()
				if player.Character == character then
					placeLobbyView()
				end
			end)
		end
		hadCharacter = true
		-- the first character: Roblox's camera sets its own default zoom (10 here, the lobby's limit) when it takes up
		-- the new character, after applyMode's lobby zoom at start-up: set the lobby zoom again once it has
		task.delay(0.2, function()
			if currentMode == "Third" and ClientState.spectating == nil and not ClientState.inArena then
				setThirdPersonZoom(K.LobbyZoom)
			end
		end)
	end)
	-- a held V the game never hears released: the window lost focus, or a text box took the keyboard
	UserInputService.WindowFocusReleased:Connect(function()
		zoomKey, zoomWait = false, false
	end)
	UserInputService.TextBoxFocused:Connect(function()
		zoomKey, zoomWait = false, false
	end)
	-- Roblox's own menu (Esc, or Start on a controller) takes the input: let go, as for the game's menu
	GuiService.MenuOpened:Connect(function()
		dropZoom()
		zoomWait = false
	end)
	applyMode()
end

return CameraController
