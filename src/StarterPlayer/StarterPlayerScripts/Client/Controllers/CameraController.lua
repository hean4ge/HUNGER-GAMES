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
	FOV = settings.fov + a subtle sprint/slide add, times the stronger of two multipliers: the aim's (ClientState.aimAlpha)
	and the zoom's. Zoom, the action "Zoom" (V held; R3 or the touch ZOOM button toggled), eases the view in to
	Config.Camera.ZoomFovMultiplier (ZoomInTime / ZoomOutTime), a slight look closer, and turns the sprint widening off.
	It is bound only while you are alive in the arena or on your plate: not while spectating, not during the launch shot
	(and while a cutscene holds the camera, step leaves the FOV alone). While a menu is open its input passes through and
	the zoom lets go. ZOOM shares AIM's touch slot and shows only while AIM is hidden (a bow or a spear aims instead,
	which zooms further).
	settings.headBob scales bob, sway, roll, tilt, turn lean and breathing (0 = off); settings.cameraShake scales
	shakes, kicks and landing impacts. settings.sensitivity scales the default camera's IAS mouse binding
	(Shared.Input.setLookSpeed) with MouseDeltaSensitivity at 1, or MouseDeltaSensitivity itself when those bindings
	don't exist; settings.padLook and touchLook scale its controller and touch bindings. All three slow down with the
	aim or the zoom by the ratio of the view's tangents, so a turn sweeps the same share of the screen.
	The look direction is never delayed or smoothed: aiming stays 1:1 with the mouse.
	Writes ClientState.lookDelta (base camera rotation this frame, X = yaw, Y = pitch, radians),
	ClientState.cameraBob (procedural offset in camera space, without the static eye offset), ClientState.fov and
	ClientState.zoomAlpha.

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
	ZoomFovMult = num(CAM, "ZoomFovMultiplier", 0.88),
	ZoomIn = math.max(num(CAM, "ZoomInTime", 0.15), 0.02), -- seconds
	ZoomOut = math.max(num(CAM, "ZoomOutTime", 0.18), 0.02),
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
-- the zoom (action "Zoom")
local zoomBound = false
local zoomKey = false -- V held
local zoomPad = false -- R3 toggled on
local zoomTouch = false -- the touch ZOOM button toggled on
local zoomButtonShown: boolean? = nil
local zoomSpring = Spring.new(0, 4.5 / K.ZoomIn, 1) -- critically damped: about 94 % of the way after ZoomInTime
local lastPadLook: number? = nil
local lastTouchLook: number? = nil

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
-- A slight look closer. V holds it (like Sprint and Crouch on a keyboard); R3 and the touch ZOOM button toggle it (like
-- Sprint on a pad and AIM on touch). step's FOV block takes the stronger of it and the aim, so the two never add up.

-- The launch shot (the round's intro) has the camera: no zoom while it plays.
local function inLaunchShot(): boolean
	return ClientState.launchShot == true
end

-- (While anything else holds the camera, a cutscene's CameraType, step leaves the FOV alone, so V changes nothing then.)
local function zoomAllowed(): boolean
	return ClientState.inArena == true and ClientState.alive == true and ClientState.spectating == nil
		and not inLaunchShot()
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
		if touch then
			zoomTouch = true
		elseif pad then
			zoomPad = not zoomPad
		else
			zoomKey = true
		end
	elseif touch then
		zoomTouch = false
	elseif not pad then
		zoomKey = false -- V let go (End or Cancel)
	end
	return nil
end

-- Every frame: bind or unbind with the state, keep the touch button out of AIM's way, let go while a menu is open.
local function refreshZoom()
	local allowed = zoomAllowed()
	if allowed ~= zoomBound then
		zoomBound = allowed
		zoomKey, zoomPad, zoomTouch = false, false, false
		zoomButtonShown = nil
		if allowed then
			Input.bind("Zoom", onZoom, {
				keys = { Enum.KeyCode.V, Enum.KeyCode.ButtonR3 },
				touch = { toggle = true, visible = false }, -- shown below; Theme.TouchLayout.Zoom is AIM's slot
			})
		else
			Input.unbind("Zoom")
			zoomSpring:reset(0)
			ClientState.zoomAlpha = 0
		end
	end
	if not zoomBound then
		return
	end
	-- ZOOM shows only while AIM is hidden: with a bow or a spear in hand AIM has the slot (and zooms further)
	local combat = Controllers and Controllers.CombatController
	local aimShown = false
	if combat and type(combat.getEquipped) == "function" and type(combat.canAimWith) == "function" then
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
	-- a menu lets go of the zoom; a toggle doesn't come back on by itself when the menu closes
	if ClientState.menuOpen and (zoomKey or zoomPad or zoomTouch) then
		zoomKey, zoomPad, zoomTouch = false, false, false
		Input.setToggle("Zoom", false)
	end
end

-- The zoom's share this frame, 0..1, eased (step's FOV block).
local function easeZoom(dt: number): number
	local on = zoomBound and (zoomKey or zoomPad or zoomTouch)
	zoomSpring.target = if on then 1 else 0
	zoomSpring.speed = 4.5 / (if on then K.ZoomIn else K.ZoomOut)
	local z = math.clamp(zoomSpring:update(dt), 0, 1)
	if not on and z < 1e-3 then
		zoomSpring:reset(0)
		z = 0
	end
	ClientState.zoomAlpha = z
	return z
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
	if lastSensitivity == nil or math.abs(desired - lastSensitivity) > 1e-3 or ready ~= lastLookReady then
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
	if lastPadLook == nil or lastTouchLook == nil or math.abs(pad - (lastPadLook :: number)) > 1e-3
		or math.abs(touch - (lastTouchLook :: number)) > 1e-3 then
		lastPadLook, lastTouchLook = pad, touch
		Input.setLookSpeed("Gamepad", pad)
		Input.setLookSpeed("Touch", touch)
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
		end
		wasSpectating = true
		ClientState.cameraBob = CFrame.identity
		return
	end
	if wasSpectating then
		ClientState.lookDelta = Vector2.zero -- handed back: the camera's jump isn't a look movement (no sway from it)
	end
	wasSpectating = false

	local headBob = settingNumber("headBob", 1, 0, 1)
	local shakeScale = settingNumber("cameraShake", 1, 0, 1)
	local baseFov = settingNumber("fov", K.BaseFov, 40, 110)

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
		local rot = CFrame.Angles(pitchTotal, yawTotal, 0) * CFrame.Angles(0, 0, rollTotal)
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
	local zoom = easeZoom(dt) -- no sprint widening under the zoom, and the stronger of it and the aim wins (never both)
	local adds = K.SprintFov * sprintAmt * (1 - math.max(aim, zoom)) + K.SlideFov * slideAmt
	if not firstPerson then
		adds *= 0.5
	end
	fovSpring.target = baseFov + adds
	local aimMul = math.min(1 + (K.AimFovMult - 1) * aim, 1 + (K.ZoomFovMult - 1) * zoom)
	local fov = math.clamp(fovSpring:update(dt) * aimMul, 1, 120)
	cam.FieldOfView = fov
	ClientState.fov = fov
	updateSensitivity(aimMul, baseFov)
end

local function safeStep(dt: number)
	local ok, err = pcall(step, dt)
	if not ok and os.clock() - errorAt > 5 then
		errorAt = os.clock()
		warn("[CameraController] " .. tostring(err))
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
		end
	end)
	player.CharacterAdded:Connect(function()
		resetFeel()
		prevYaw = nil
	end)
	-- a held V the game never hears released: the window lost focus, or a text box took the keyboard
	UserInputService.WindowFocusReleased:Connect(function()
		zoomKey = false
	end)
	UserInputService.TextBoxFocused:Connect(function()
		zoomKey = false
	end)
	applyMode()
end

return CameraController
