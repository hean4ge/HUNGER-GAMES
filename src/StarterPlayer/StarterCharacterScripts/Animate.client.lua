--[[
	Animate - locomotion animation for this character (LocalScript in StarterPlayer.StarterCharacterScripts; it runs
	on the owning client, so every track replicates to the other players). Replaces Roblox's default Animate.

	- Ground: idle, walk and run (and an optional sprint clip) are blended by ground speed. All cycles advance at one
	  shared normalised gait rate taken from the blended stride length, so the feet travel at the ground speed (no
	  foot sliding) and the clips stay in step while they cross-fade. Moving backwards plays the cycle in reverse (no
	  moonwalking); strafing plays the forward cycle and CharacterVisuals twists the hips toward the direction of
	  travel. Crouching uses the crouch clips when present, otherwise the walk under the procedural crouch pose.
	  Clip speeds scale with this rig's leg length (any avatar size keeps its feet planted).
	- Jump, fall and landing: one realistic standing-jump clip (generated for this game) played in segments:
	  the knee dip, timed to MovementController's take-off (ClientState.jumpPrepAt / jumpPrepTime; shorter and
	  later in the dip when moving), the extension into the air pose, held while airborne (CharacterVisuals tucks
	  the legs toward the apex, reaches them for the ground and balances the arms over it), and the touch-down,
	  quicker for light landings and handed back to locomotion as soon as you move. Walking off a ledge goes straight
	  into the air pose. No arms-up cartoon jump.
	- Water: swim strokes matched to the swim speed, treading water when still.
	- Native ladder climb (TrussParts) matched to the climb speed; sitting.
	- While sliding, mantling or tree-climbing (PlatformStand, or ClientState.moveState / the Stance attribute
	  "Slide"/"Climb") locomotion fades out under CharacterVisuals' procedural poses.
	- Keeps the idle variations, the facial "mood" track, a Tool hold pose and the emote wheel (PlayEmote).

	Clips: CLIPS below, or a Folder named "Clips" under this script with Animation children named like the keys
	(attribute NativeSpeed = studs/s the clip covers at playback speed 1 on a rig with STRIDE_REF_LEGS legs,
	StrideLength = studs per full cycle). Players' own animation packs (HumanoidDescription) are deliberately
	ignored: everyone moves the same, realistic way.
]]
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local root = character:WaitForChild("HumanoidRootPart") :: BasePart
local animator = (humanoid:WaitForChild("Animator", 10) or humanoid:FindFirstChildOfClass("Animator")) :: Animator?
if not animator then
	warn("[Animate] no Animator on the humanoid")
	return
end

local MOVE = {}
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configModule = shared and shared:FindFirstChild("Config")
	if configModule then
		local ok, config = pcall(require, configModule)
		if ok and type(config) == "table" and type(config.Movement) == "table" then
			MOVE = config.Movement
		end
	end
end
local FALL_GRAVITY = (tonumber(MOVE.AirGravity) or 125) * (tonumber(MOVE.FallGravityScale) or 1.08)

local ID = "rbxassetid://"
-- native = studs/s of ground speed the clip covers at playback speed 1, measured from the clips' keyframes (speed
-- of the planted foot under the root) on a rig with STRIDE_REF_LEGS-stud legs: walk 7.4 (stride 4.6 studs per
-- 0.625 s cycle), run 15.5 (stride 9.7). Each rig scales them by its own leg length.
-- Config.Movement.StepLengthWalk/Run are half these strides, so footsteps and head-bob stay in step with the legs.
local STRIDE_REF_LEGS = 2.42
local CLIPS: { [string]: any } = {
	idle = { { id = ID .. "17172918855", weight = 9 }, { id = ID .. "17173014241", weight = 1 } },
	walk = { id = ID .. "10921269718", native = 7.4 },
	run = { id = ID .. "913376220", native = 15.5 },
	sprint = nil, -- optional: { id, native }
	crouchIdle = nil, -- optional
	crouchWalk = nil, -- optional: { id, native }
	-- the standing jump: segment times (s) in the clip
	jump = { id = ID .. "130849611836373", dip = 6.3, takeoff = 6.83, air = 6.97, touch = 7.12, settle = 7.75 },
	swim = { id = ID .. "913384386", native = 10 },
	swimIdle = { id = ID .. "913389285" },
	climb = { id = ID .. "507765644", native = 5 },
	sit = { id = ID .. "2506281703" },
	toolNone = { id = ID .. "507768375" },
	mood = { id = ID .. "14366558676" },
}
local EMOTES = {
	wave = ID .. "507770239", point = ID .. "507770453", cheer = ID .. "507770677", laugh = ID .. "507770818",
	dance = ID .. "507771019", dance2 = ID .. "507776043", dance3 = ID .. "507777268",
}

-- Overrides from the Clips folder (names that a HumanoidDescription never touches)
local clipsFolder = script:FindFirstChild("Clips")
if clipsFolder then
	for _, anim in ipairs(clipsFolder:GetChildren()) do
		if anim:IsA("Animation") and anim.AnimationId ~= "" then
			local entry = { id = anim.AnimationId, native = anim:GetAttribute("NativeSpeed"), stride = anim:GetAttribute("StrideLength") }
			if anim.Name == "idle" then
				CLIPS.idle = { { id = anim.AnimationId, weight = 1 } }
			elseif anim.Name ~= "jump" then -- the jump clip's segment times belong to the clip above
				CLIPS[anim.Name] = entry
			end
		end
	end
end

local P = Enum.AnimationPriority
local tracks: { [string]: AnimationTrack } = {}
local natives: { [string]: number } = {}

local function load(name: string, id: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.Name = name
	anim.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or not track then
		warn("[Animate] could not load " .. name .. " (" .. id .. "): " .. tostring(track))
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

local function loadClip(name: string, priority: Enum.AnimationPriority, looped: boolean)
	local clip = CLIPS[name]
	if type(clip) ~= "table" or type(clip.id) ~= "string" then
		return
	end
	local track = load(name, clip.id, priority, looped)
	if track then
		tracks[name] = track
		natives[name] = tonumber(clip.native) or 0
	end
end

-- idle: variations, weighted
local idleTracks: { AnimationTrack } = {}
local idleWeights: { number } = {}
for i, v in ipairs(CLIPS.idle or {}) do
	local track = load("idle" .. i, v.id, P.Core, true)
	if track then
		table.insert(idleTracks, track)
		table.insert(idleWeights, v.weight or 1)
	end
end
loadClip("walk", P.Core, true)
loadClip("run", P.Core, true)
loadClip("sprint", P.Core, true)
loadClip("crouchIdle", P.Core, true)
loadClip("crouchWalk", P.Core, true)
loadClip("jump", P.Core, false)
loadClip("swim", P.Core, true)
loadClip("swimIdle", P.Core, true)
loadClip("climb", P.Core, true)
loadClip("sit", P.Core, true)
loadClip("toolNone", P.Idle, true)
loadClip("mood", P.Core, true)

-- This rig's legs (hip to ankle, from the joints) against the rig the clip speeds were measured on.
local legScale = 1
local legsMeasuredAt = -math.huge
local function jointFrames(joint: Instance): (CFrame?, CFrame?)
	if joint:IsA("Motor6D") then
		return joint.C0, joint.C1
	elseif joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if a0 and a1 then
			return a0.CFrame, a1.CFrame
		end
	end
	return nil, nil
end
local function findJoint(name: string): Instance?
	for _, d in ipairs(character:GetDescendants()) do
		if d.Name == name and (d:IsA("AnimationConstraint") or d:IsA("Motor6D")) then
			return d
		end
	end
	return nil
end
local function measureLegs()
	legsMeasuredAt = os.clock()
	local hip, knee, ankle = findJoint("LeftHip"), findJoint("LeftKnee"), findJoint("LeftAnkle")
	if not (hip and knee and ankle) then
		return
	end
	local _, hipC1 = jointFrames(hip)
	local kneeC0, kneeC1 = jointFrames(knee)
	local ankleC0 = jointFrames(ankle)
	if hipC1 and kneeC0 and kneeC1 and ankleC0 then
		local legs = (hipC1.Position - kneeC0.Position).Magnitude + (kneeC1.Position - ankleC0.Position).Magnitude
		if legs > 0.3 then
			legScale = math.clamp(legs / STRIDE_REF_LEGS, 0.4, 1.4)
		end
	end
end
measureLegs()

-- Weight / speed with change thresholds (every call replicates, so only send real changes)
local current: { [AnimationTrack]: { w: number, s: number } } = {}
local function setTrack(track: AnimationTrack?, weight: number, speed: number?)
	if not track then
		return
	end
	local st = current[track]
	if not st then
		st = { w = -1, s = 1 }
		current[track] = st
	end
	if weight > 0.001 then
		if not track.IsPlaying then
			track:Play(0, math.max(weight, 0.001), speed or 1)
			st.w, st.s = weight, speed or 1
			return
		end
		if math.abs(st.w - weight) > 0.015 or (weight >= 0.999 and st.w < 0.999) then
			track:AdjustWeight(weight, 0)
			st.w = weight
		end
	elseif track.IsPlaying then
		if st.w > 0.001 then
			track:AdjustWeight(0.0001, 0)
			st.w = 0.0001
		end
	end
	if speed and math.abs(st.s - speed) > math.max(0.02 * math.abs(st.s), 0.01) then
		track:AdjustSpeed(speed)
		st.s = speed
	end
end
local function stopTrack(track: AnimationTrack?, fade: number?)
	if track and track.IsPlaying then
		track:Stop(fade or 0.2)
		current[track] = nil
	end
end

local function smooth01(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function approach(cur: number, target: number, rate: number, dt: number): number
	return cur + (target - cur) * (1 - math.exp(-rate * dt))
end

-- Stride (studs per full gait cycle) of a looping clip on this rig; needs the track length (0 until it has loaded)
local function stride(name: string): number
	local track = tracks[name]
	if not track or track.Length <= 0 then
		return 0
	end
	local clip = CLIPS[name]
	if clip and tonumber(clip.stride) then
		return (tonumber(clip.stride) :: number) * legScale
	end
	return natives[name] * legScale * track.Length
end

-- State
local blend = { idle = 1, walk = 0, run = 0, sprint = 0, crouch = 0, air = 0, swim = 0, climb = 0, sit = 0 }
local startGait = false -- align every locomotion cycle to phase 0 on the next frame
local idleIndex = 1
local idleMix: { number } = {}
local wasMoving = false
local emoteTrack: AnimationTrack? = nil
local mode = "ground"
local LOCO = { { "walk", "walk" }, { "run", "run" }, { "sprint", "sprint" }, { "crouch", "crouchWalk" } }
-- the jump clip: phase "none" | "prep" | "air" | "land", its weight, and what it is doing
local J = {
	phase = "none", w = 0, sentW = -1, speed = 1, held = false, prepSeen = -math.huge, landAt = -math.huge, minVy = 0,
	airStart = nil :: number?,
}

local function pickIdle()
	local total = 0
	for _, w in ipairs(idleWeights) do
		total += w
	end
	local roll = math.random() * total
	for i, w in ipairs(idleWeights) do
		roll -= w
		if roll <= 0 then
			return i
		end
	end
	return 1
end
idleIndex = pickIdle()
for i, track in ipairs(idleTracks) do
	track.DidLoop:Connect(function()
		if i == idleIndex and #idleTracks > 1 then
			idleIndex = pickIdle()
		end
	end)
end

local function stopEmote()
	if emoteTrack then
		emoteTrack:Stop(0.2)
		emoteTrack = nil
	end
end

-- The owner's live movement state (same frame as MovementController), found without blocking.
local clientState: any = nil
local nextLookup = 0
local function liveState(): any
	if clientState == nil and os.clock() >= nextLookup then
		nextLookup = os.clock() + 1
		local owner = Players:GetPlayerFromCharacter(character)
		local scripts = owner and owner:FindFirstChildOfClass("PlayerScripts")
		local client = scripts and scripts:FindFirstChild("Client")
		local module = client and client:FindFirstChild("ClientState")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				clientState = result
			end
		end
	end
	return clientState
end

-- Jump clip control (seeks and speed changes replicate, so they are only sent when they change)
local function jumpPlayAt(time: number, speed: number, fade: number)
	local jt = tracks.jump
	if not jt then
		return
	end
	if not jt.IsPlaying then
		jt:Play(fade, math.max(J.w, 0.05), speed)
		J.sentW = math.max(J.w, 0.05)
	elseif math.abs(J.speed - speed) > 1e-3 then
		jt:AdjustSpeed(speed)
	end
	J.speed = speed
	J.held = false
	jt.TimePosition = math.clamp(time, 0, math.max(jt.Length - 0.02, 0))
end
local function jumpSetSpeed(speed: number)
	local jt = tracks.jump
	if jt and jt.IsPlaying and math.abs(J.speed - speed) > 1e-3 then
		jt:AdjustSpeed(speed)
		J.speed = speed
	end
end

local POSE_STATES = { Slide = "Slide", Mantle = "Climb", Climb = "Climb" }

local function updateJump(dt: number, state: Enum.HumanoidStateType, speed: number, vy: number)
	local jt = tracks.jump
	local clip = CLIPS.jump
	if not jt or not clip or jt.Length <= 0 then
		return
	end
	local now = os.clock()
	local airborne = state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
	local cs = liveState()
	local prepAt = if cs then tonumber(cs.jumpPrepAt) or -math.huge else -math.huge
	local prepTime = if cs then math.max(tonumber(cs.jumpPrepTime) or 0.1, 0.03) else 0.1

	-- 1) the knee dip before a take-off
	if prepAt > J.prepSeen and now - prepAt < prepTime + 0.05 and not airborne and mode == "ground" then
		J.prepSeen = prepAt
		J.phase = "prep"
		local moving = speed > 4
		-- on the move the dip is shallow: start late in it (momentum, one-footed take-off)
		local from = if moving then clip.takeoff - 0.2 else clip.dip
		local remaining = math.max(0.03, prepTime - (now - prepAt))
		jumpPlayAt(from, math.clamp((clip.takeoff - from) / remaining, 0.5, 8), if moving then 0.07 else 0.05)
	elseif J.phase == "prep" and not airborne and (prepAt < J.prepSeen or now - J.prepSeen > prepTime + 0.3) then
		J.phase = "none" -- the take-off was cancelled (a mantle or climb took over)
	end

	if J.phase == "prep" and jt.IsPlaying and jt.TimePosition >= clip.takeoff + 0.04 then
		jumpSetSpeed(1.25) -- the take-off is a frame late: don't run ahead of it
	end

	-- 2) airborne: carry on into the air pose and hold it (a few frames of Freefall over bumps don't count)
	if airborne and mode == "air" then
		J.airStart = J.airStart or now
		if J.phase == "prep" or J.phase == "air" or now - J.airStart > 0.15 or vy < -12 or vy > 8 then
			if J.phase ~= "air" then
				if J.phase == "prep" then
					jumpSetSpeed(1.25) -- the legs extend at real speed
				else
					jumpPlayAt(clip.air - 0.1, 1, 0.2) -- off a ledge: straight into the air pose
				end
				J.phase = "air"
				J.minVy = 0
			end
			J.minVy = math.min(J.minVy, vy)
			if not J.held and jt.TimePosition >= clip.air then
				jt.TimePosition = clip.air
				jumpSetSpeed(0)
				J.held = true
			end
		end
	elseif J.phase == "air" then
		J.airStart = nil
		-- 3) touch-down: knees absorb (light landings play quicker), then locomotion takes over
		local h = J.minVy * J.minVy / (2 * FALL_GRAVITY)
		J.phase = "land"
		J.landAt = now
		jumpPlayAt(clip.touch, math.clamp(1.6 - h / 10, 0.8, 1.6), 0.05)
	end
	if not airborne then
		J.airStart = nil
	end
	if J.phase == "land" then
		if mode ~= "ground" or jt.TimePosition >= clip.settle or now - J.landAt > 1.5 or (speed > 3 and now - J.landAt > 0.12) then
			J.phase = "none"
		end
	end

	-- weight: in fast, out as locomotion takes over (faster when moving)
	local target = if J.phase == "none" then 0 else 1
	local rate = if target > J.w then 45 else (if speed > 3 then 10 else 5)
	J.w = approach(J.w, target, rate, dt)
	if J.phase == "none" and J.w < 0.02 then
		J.w = 0
		if jt.IsPlaying then
			jt:Stop(0.1)
		end
		J.sentW, J.held = -1, false
	elseif jt.IsPlaying and math.abs(J.sentW - J.w) > 0.02 then
		jt:AdjustWeight(math.max(J.w, 0.001), 0)
		J.sentW = J.w
	end
end

local function update(dt: number)
	dt = math.clamp(dt, 0, 0.1)
	if humanoid.Health <= 0 or not root.Parent then
		return
	end
	if os.clock() - legsMeasuredAt > 3 then
		measureLegs() -- (cheap; follows avatar re-scaling)
	end
	local state = humanoid:GetState()
	local stance = character:GetAttribute("Stance")
	local cs = liveState()
	local live = if cs then cs.moveState else nil
	if live then
		stance = POSE_STATES[live] or (if live == "Crouch" then "Crouch" else "Stand")
		if live == "Climb" and state == Enum.HumanoidStateType.Climbing then
			stance = "Stand" -- a native ladder climb has its own clip
		end
	end
	local vel = root.AssemblyLinearVelocity
	local velH = Vector3.new(vel.X, 0, vel.Z)
	local speed = velH.Magnitude
	local look = root.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	local forwardSpeed = if fwd.Magnitude > 1e-3 then velH:Dot(fwd.Unit) else speed

	-- mode
	if state == Enum.HumanoidStateType.Seated or humanoid.Sit then
		mode = "sit"
	elseif state == Enum.HumanoidStateType.Climbing then
		mode = "climb"
	elseif state == Enum.HumanoidStateType.Swimming then
		mode = "swim"
	elseif state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		mode = "air"
	elseif humanoid.PlatformStand or stance == "Slide" or stance == "Climb" then
		mode = "pose"
	else
		mode = "ground"
	end

	-- emotes end as soon as you move
	if emoteTrack and (speed > 1 or mode ~= "ground") then
		stopEmote()
	end

	updateJump(dt, state, speed, vel.Y)
	local others = 1 - J.w -- the jump clip owns the body while it plays

	-- target blend weights
	local tIdle, tWalk, tRun, tSprint, tCrouch, tAir, tSwim, tClimb, tSit = 0, 0, 0, 0, 0, 0, 0, 0, 0
	local backwards = speed > 0.5 and forwardSpeed < -0.35 * speed
	if mode == "ground" then
		local moving = smooth01((speed - 0.4) / 1.4)
		tIdle = 1 - moving
		local runW = if backwards then 0 else smooth01((speed - 8) / 3.5)
		local sprintW = if tracks.sprint and not backwards then smooth01((speed - 16) / 4) else 0
		if stance == "Crouch" and tracks.crouchWalk then
			tCrouch = moving
		else
			tWalk = moving * (1 - runW)
			tRun = moving * runW * (1 - sprintW)
			tSprint = moving * runW * sprintW
		end
		if moving > 0.05 and not wasMoving then
			startGait = true
		end
		wasMoving = moving > 0.05
	elseif mode == "pose" then
		tIdle = 1
		wasMoving = false
	elseif mode == "air" then
		tAir = 1
		wasMoving = false
	elseif mode == "swim" then
		tSwim = 1
		wasMoving = false
	elseif mode == "climb" then
		tClimb = 1
		wasMoving = false
	elseif mode == "sit" then
		tSit = 1
		wasMoving = false
	end

	local rate = if mode == "ground" then 12 else 9
	blend.idle = approach(blend.idle, tIdle, rate, dt)
	blend.walk = approach(blend.walk, tWalk, rate, dt)
	blend.run = approach(blend.run, tRun, rate, dt)
	blend.sprint = approach(blend.sprint, tSprint, rate, dt)
	blend.crouch = approach(blend.crouch, tCrouch, rate, dt)
	blend.air = approach(blend.air, tAir, 14, dt)
	blend.swim = approach(blend.swim, tSwim, 6, dt)
	blend.climb = approach(blend.climb, tClimb, 10, dt)
	blend.sit = approach(blend.sit, tSit, 10, dt)

	-- one shared gait rate: cycles per second = ground speed / blended stride
	local strideSum, strideW = 0, 0
	for _, pair in ipairs(LOCO) do
		local w = blend[pair[1]]
		local s = stride(pair[2])
		if w > 0.001 and s > 0 then
			strideSum += s * w
			strideW += w
		end
	end
	local cycleRate = 0
	if strideW > 0 then
		-- above a jog the stride lengthens (up to 25% by a full sprint) rather than the cadence racing up;
		-- MovementController's footsteps use the same factor
		local walkSpeed = tonumber(MOVE.WalkSpeed) or 13
		local sprintSpeed = tonumber(MOVE.SprintSpeed) or 21
		local reach = 1 + 0.25 * smooth01((speed - walkSpeed) / math.max(sprintSpeed - walkSpeed, 1))
		cycleRate = speed / (strideSum / strideW * reach)
	end
	local dirSign = if backwards then -1 else 1

	-- every cycle advances at the same normalised rate, so once aligned they stay in step while blending;
	-- the heaviest one leads and the others are re-aligned to it only if they drift (seeks replicate)
	local leadPhase: number? = nil
	local leadW = 0
	for _, pair in ipairs(LOCO) do
		local track = tracks[pair[2]]
		if track and track.IsPlaying and track.Length > 0 and blend[pair[1]] > leadW then
			leadW = blend[pair[1]]
			leadPhase = track.TimePosition / track.Length
		end
	end
	if startGait then
		leadPhase = 0 -- start every walk on the same foot
		startGait = false
	end
	for _, pair in ipairs(LOCO) do
		local track = tracks[pair[2]]
		if track then
			local w = blend[pair[1]] * others
			local len = track.Length
			local spd = 1
			if len > 0 then
				spd = math.clamp(cycleRate * len, 0.05, 3) * dirSign
			end
			local wasPlaying = track.IsPlaying
			setTrack(track, w, spd)
			if leadPhase and len > 0 and track.IsPlaying and (w > 0.02 or not wasPlaying) then
				local want = (leadPhase :: number) * len
				local diff = math.abs(track.TimePosition - want)
				if math.min(diff, len - diff) > 0.1 * len then
					track.TimePosition = want
				end
			end
		end
	end

	-- idle (variations cross-fade; crouched idle when available)
	local crouchIdle = tracks.crouchIdle
	local idleW = blend.idle * (1 - blend.air) * (1 - blend.swim) * others
	local crouchIdleW = if crouchIdle and stance == "Crouch" then idleW else 0
	for i, track in ipairs(idleTracks) do
		idleMix[i] = approach(idleMix[i] or (if i == idleIndex then 1 else 0), if i == idleIndex then 1 else 0, 3, dt)
		setTrack(track, (idleW - crouchIdleW) * idleMix[i], 1)
	end
	if crouchIdle then
		setTrack(crouchIdle, crouchIdleW, 1)
	end

	-- water
	local swimMoving = speed > 1.2
	local swimSpeed = 1
	if natives.swim and natives.swim > 0 then
		swimSpeed = math.clamp(speed / natives.swim, 0.4, 1.8)
	end
	setTrack(tracks.swim, if swimMoving then blend.swim else 0, swimSpeed)
	setTrack(tracks.swimIdle, if swimMoving then 0 else blend.swim, 1)

	-- native ladder climb: matched to the vertical speed (paused when still)
	local climbSpeed = 0
	if natives.climb and natives.climb > 0 then
		climbSpeed = math.clamp(vel.Y / natives.climb, -2, 2)
	end
	setTrack(tracks.climb, blend.climb, if math.abs(climbSpeed) < 0.05 then 0 else climbSpeed)

	setTrack(tracks.sit, blend.sit, 1)

	-- tool hold pose
	local tool = character:FindFirstChildOfClass("Tool")
	setTrack(tracks.toolNone, if tool and tool:FindFirstChild("Handle") then 1 else 0, 1)
end

-- the facial mood track stays on
if tracks.mood then
	tracks.mood:Play(0.2)
end

local stepSignal = (RunService :: any).PreAnimation or RunService.Stepped
local conn
conn = stepSignal:Connect(function(a, b)
	local dt = if type(b) == "number" then b else a
	local ok, err = pcall(update, dt)
	if not ok then
		warn("[Animate] " .. tostring(err))
	end
end)

humanoid.Died:Connect(function()
	for _, track in pairs(tracks) do
		stopTrack(track, 0.1)
	end
	for _, track in ipairs(idleTracks) do
		stopTrack(track, 0.1)
	end
	stopEmote()
	if conn then
		conn:Disconnect()
	end
end)

-- Emote wheel / chat emotes: Roblox calls character.Animate.PlayEmote
local playEmote = Instance.new("BindableFunction")
playEmote.Name = "PlayEmote"
playEmote.OnInvoke = function(emote: any)
	if mode ~= "ground" or root.AssemblyLinearVelocity.Magnitude > 1 then
		return false
	end
	local anim: Animation? = nil
	if typeof(emote) == "Instance" and emote:IsA("Animation") then
		anim = emote
	elseif type(emote) == "string" and EMOTES[emote] then
		local a = Instance.new("Animation")
		a.AnimationId = EMOTES[emote]
		anim = a
	end
	if not anim then
		return false
	end
	stopEmote()
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim :: Animation)
	end)
	if not ok or not track then
		return false
	end
	track.Priority = P.Action
	track:Play(0.2)
	emoteTrack = track
	return true, track
end
playEmote.Parent = script
