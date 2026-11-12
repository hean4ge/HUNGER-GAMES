--[[
	CharacterVisuals - full-body first person for the local player and procedural body motion for every
	character (client).

	First person: the default TransparencyController hides the whole character every frame. After it runs
	(RenderPriority.Camera + 2) we show the torso, legs and feet again (plus lower-body layered clothing), and keep
	the head, face, hair/hat accessories and arms hidden (the viewmodel draws arms). Anything named "EquippedModel"
	(the third-person weapon) is hidden too. CameraController places the eye in front of the head.

	Procedural layers, multiplied into the joint Transforms on RunService.PreSimulation (after the Animator, before
	physics) - the documented layering path for AnimationConstraint rigs (Avatar Joint Upgrade), and identical for
	Motor6D rigs. A joint the Animator didn't write this frame (throttled or unanimated) reuses its previous base, so
	nothing ever accumulates. Everything runs in this one pass, in a fixed order, so the leg IK always sees the final
	stance pose (an IKControl solves inside the animation step and could not see these poses). Characters within
	POSE_RANGE studs of the camera are processed (IK within IK_RANGE):
	  1. Stance poses: Crouch (bent hips and knees that exactly absorb the hitbox drop, slight forward lean), Slide
	     (lean back, leading leg forward, trailing leg folded) and Climb (arms up, diagonal reach cycle). Remote
	     characters use the replicated character attribute Stance; the local character uses MovementController's
	     live blend so the pose matches its HipHeight exactly.
	  2. Hip twist: when moving sideways relative to where the body faces (first-person strafing), the hips turn
	     toward the direction of travel (up to ~50 degrees) and the waist/neck counter-turn, so the torso keeps
	     facing forward and the legs step the way they move.
	  3. Foot IK: each foot is raycast against the ground; feet follow slopes, steps and rocks (the animation's
	     own foot lift is preserved), the pelvis drops so the lower foot can reach, an analytic two-bone solve bends
	     the knee and swings the leg onto the target, and planted feet tilt onto the ground plane. As soon as the body
	     rises off the floor (a take-off) the IK lets go: it stops reading the ground and only releases the offsets it
	     held, so the feet leave with the body (chasing the receding floor dragged the pelvis down for three frames,
	     then snapped it back). Local: MovementController's state; remote: the root's rise above the floor its feet
	     last stood on (step-ups rise onto a higher floor and don't count), or the replicated Jumping state.
	  4. Lean and stabilisation: the body leans into acceleration (forward when pushing off, back when skidding
	     to a stop), a little into the run, and sideways into turns, without lifting the planted feet (IK targets
	     are taken before the lean). The neck counters the lean so the head stays level.
	  5. Landing compression: the pelvis dips and the knees absorb after a landing, scaled by the drop height
	     (local: MovementController's blend; remote: detected from the root's vertical velocity).
	  6. Air: the legs tuck toward the apex and reach for the ground before touch-down, the arms come out a little
	     for balance (wider in a long fall), over Animate's take-off/air clip pose (local: moveState "Air";
	     remote: the ground probe and vertical speed, swimmers excluded).
	IK reach, pelvis drop and the landing dip scale with each rig's leg length (any avatar size).
	First person (local body only): the eye is placed from the root, not from the animated head, so in the air under a
	downward view the own body keeps the jump clip's root lift and forward trunk pitch at most at the bind pose (the clip
	lifts the pelvis ~0.2 studs and pitches the trunk ~8 degrees forward, which brought the chest up into the view and
	hid the hands), and the air tuck and lean flatten out. A shown body part within NEAR_CULL studs of the camera is
	hidden until it moves away (never cut open by the near plane). Test hook: the local player's attribute LS_PoseAsRemote = true poses
	the own body through the remote path (what other players' clients compute).

	Public API (through the Controllers registry):
	  CharacterVisuals.headLean(rig, crouchWeight, slideWeight) -> (forward: number, down: number)
	      how far the head centre moves (root space, studs) under the crouch/slide poses; CameraController uses it.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local CharacterVisuals = {}

local player = Players.LocalPlayer

local MOVE = Config.Movement or {}
local POSE_RANGE = 150
local IK_RANGE = 75
local BLEND_RATE = 11 -- remote stance blend speed (1/s)
local CLIMB_STROKE = (MOVE.Climb and MOVE.Climb.StrokeLength) or 2.6
local FALL_GRAVITY = (tonumber(MOVE.AirGravity) or 125) * (tonumber(MOVE.FallGravityScale) or 1.08)

-- IK limits (studs)
local MAX_FOOT_UP = 1.6 -- a foot can be raised this far onto a step or rock
local MAX_FOOT_DOWN = 1.3 -- or reach this far down a slope or step
local MAX_PELVIS_DROP = 0.9
local MAX_FOOT_TILT = math.rad(28)
local LAND_DROP = 0.55 -- pelvis dip at full landing compression
local REF_LEGS = 1.75 -- the limits above are for the classic R15 legs (hip to ankle); each rig scales them
-- Take-off: the IK lets go at RELEASE_RATE (1/s). A remote root rising faster than RISE_SPEED (studs/s) whose feet's
-- reference plane is RISE_GAP (x leg scale) above the floor they last stood on is taking off.
local RELEASE_RATE = 20
local RISE_SPEED = 6
local RISE_GAP = 0.12
-- First person: the air tuck and lean flatten by up to FP_TUCK_CUT as the view pitches down from FP_DOWN_FROM to
-- FP_DOWN_FULL (sines of the downward pitch)
local FP_TUCK_CUT = 0.7
local FP_DOWN_FROM = math.sin(math.rad(45))
local FP_DOWN_FULL = math.sin(math.rad(72))
-- First person: a shown body part closer than NEAR_CULL studs to the camera is hidden; it shows again beyond NEAR_SHOW
local NEAR_CULL = 0.2
local NEAR_SHOW = 0.28
-- Air pose (radians)
local AIR_HIP = math.rad(30)
local AIR_KNEE = math.rad(-58)
local AIR_ANKLE = math.rad(14)
local AIR_ARM_OUT = math.rad(16)
local FALL_ARM_OUT = math.rad(42)
local AIR_ARM_FWD = math.rad(14)
local AIR_ELBOW = math.rad(22)
local AIR_LEAN = math.rad(-5) -- a slight forward lean at the hips

-- Pose angles (radians). Joint rotations are about the joint's X axis: + swings a hanging limb forward.
local CROUCH_ROOT = math.rad(-10) -- forward lean at the hips
local CROUCH_WAIST = math.rad(-8)
local CROUCH_NECK = math.rad(14) -- keeps the face looking ahead
local CROUCH_SHOULDER = math.rad(12)
local SLIDE_ROOT = math.rad(24) -- lean back
local SLIDE_WAIST = math.rad(4)
local SLIDE_NECK = math.rad(-22)
local SLIDE_LEAD_KNEE = math.rad(-8)
local SLIDE_LEAD_ANKLE = math.rad(18)
local SLIDE_TRAIL_THIGH = math.rad(32) -- world angle of the folded leg's thigh
local SLIDE_TRAIL_SHIN = math.rad(-85) -- world angle of its shin (lying back along the ground)
local SLIDE_TRAIL_ANKLE = math.rad(40)
local CLIMB_ROOT = math.rad(-5)
local CLIMB_NECK = math.rad(12)
-- Lean (radians per stud/s^2 of acceleration) and limits
local LEAN_PER_ACCEL = 0.0032
local LEAN_FORWARD_MAX = math.rad(9)
local LEAN_BACK_MAX = math.rad(8)
local RUN_LEAN = math.rad(4) -- extra forward lean at a full sprint
local ROLL_PER_ACCEL = 0.0028
local ROLL_MAX = math.rad(7)
local TWIST_MAX = math.rad(50)
local SPRINT_SPEED = tonumber(MOVE.SprintSpeed) or 21

local BODY_PARTS = {
	UpperTorso = true, LowerTorso = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true, Torso = true, ["Left Leg"] = true, ["Right Leg"] = true,
}
local LOWER_BODY_ACCESSORIES = {
	[Enum.AccessoryType.Pants] = true,
	[Enum.AccessoryType.Shorts] = true,
	[Enum.AccessoryType.DressSkirt] = true,
	[Enum.AccessoryType.LeftShoe] = true,
	[Enum.AccessoryType.RightShoe] = true,
	[Enum.AccessoryType.Waist] = true,
}
local POSE_JOINTS = {
	"Root", "Waist", "Neck", "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle",
	"LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow",
}
local LEG_JOINTS = { "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle" }
local UPPER_JOINTS = { "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow" }

local Controllers = nil
local entries: { [Model]: any } = {}
local localEntry = nil
local errorAt = -math.huge
local fpDown = 0 -- 0..1 how steeply the first-person view looks down (smoothed)
local poseAsRemote = false -- test hook (player attribute LS_PoseAsRemote)

local ikParams = RaycastParams.new()
ikParams.FilterType = Enum.RaycastFilterType.Exclude
ikParams.IgnoreWater = true
ikParams.RespectCanCollide = true
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
waterParams.IgnoreWater = false
waterParams.RespectCanCollide = true
local filterDirty = true

local IDENTITY = CFrame.identity

local function movement()
	return Controllers and Controllers.MovementController
end

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function smooth01(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- How far the head centre moves (root space: + forward, + down) under the crouch/slide upper-body poses.
-- Exact forward kinematics through the rig's own joints; an analytic estimate if the joints are missing.
function CharacterVisuals.headLean(rig, crouchW: number, slideW: number): (number, number)
	local rootX = CROUCH_ROOT * crouchW + SLIDE_ROOT * slideW
	local waistX = CROUCH_WAIST * crouchW + SLIDE_WAIST * slideW
	local neckX = CROUCH_NECK * crouchW + SLIDE_NECK * slideW
	local j = rig.joints
	if j and j.Root and j.Waist and j.Neck then
		local ok, forward, down = pcall(function()
			local lower = j.Root.C0 * CFrame.Angles(rootX, 0, 0) * j.Root.C1:Inverse()
			local upper = lower * j.Waist.C0 * CFrame.Angles(waistX, 0, 0) * j.Waist.C1:Inverse()
			local head = upper * j.Neck.C0 * CFrame.Angles(neckX, 0, 0) * j.Neck.C1:Inverse()
			local d = head.Position - rig.headCenter
			return -d.Z, -d.Y
		end)
		if ok then
			return forward, down
		end
	end
	local hy = rig.headCenter.Y
	local armRoot = hy - rig.rootPivotY
	return -armRoot * math.sin(rootX), armRoot * (1 - math.cos(rootX))
end

local LEAD_FOOT_WORLD = math.rad(50) -- the leading foot slides heel-first, toes up

-- Slide leg angles for this rig (world swing angles), solved with forward kinematics so that from the lowered
-- slide hip line the leading heel and the folded leg rest on the ground instead of clipping into it.
local function solveSlidePose(rig)
	local pose = {
		leadThigh = math.rad(72),
		leadKnee = SLIDE_LEAD_KNEE,
		leadAnkle = SLIDE_LEAD_ANKLE,
		trailThigh = SLIDE_TRAIL_THIGH,
		trailShin = SLIDE_TRAIL_SHIN,
		trailAnkle = SLIDE_TRAIL_ANKLE,
	}
	local j = rig.joints
	local hipJ, kneeJ, ankleJ = j.LeftHip, j.LeftKnee, j.LeftAnkle
	local foot = ankleJ and ankleJ.Parent
	if not (hipJ and kneeJ and ankleJ and foot and foot:IsA("BasePart")) then
		return pose
	end
	local ok = pcall(function()
		local hipLine = rig.hip - rig.slideDrop -- the hip joints sit on the root's pitch axis, at the hip line
		local fs = foot.Size
		local corners = {
			Vector3.new(0, -fs.Y / 2, fs.Z / 2), Vector3.new(0, -fs.Y / 2, -fs.Z / 2),
			Vector3.new(0, fs.Y / 2, fs.Z / 2), Vector3.new(0, fs.Y / 2, -fs.Z / 2),
		}
		local shin = kneeJ.Parent
		local ss = if shin and shin:IsA("BasePart") then shin.Size else Vector3.new(1, rig.shin, 1)
		local shinCorners = {
			Vector3.new(0, -ss.Y / 2, ss.Z / 2), Vector3.new(0, -ss.Y / 2, -ss.Z / 2),
			Vector3.new(0, ss.Y / 2, ss.Z / 2), Vector3.new(0, ss.Y / 2, -ss.Z / 2),
		}
		local hipInv, kneeInv, ankleInv = hipJ.C1:Inverse(), kneeJ.C1:Inverse(), ankleJ.C1:Inverse()
		-- lowest point of the foot box and of the shin box above the ground for one leg pose
		local function lowest(thighWorld: number, kneeRel: number, ankleRel: number): (number, number)
			local upperLeg = CFrame.new(0, hipLine, 0) * CFrame.Angles(thighWorld, 0, 0) * hipInv
			local lowerLeg = upperLeg * kneeJ.C0 * CFrame.Angles(kneeRel, 0, 0) * kneeInv
			local footCF = lowerLeg * ankleJ.C0 * CFrame.Angles(ankleRel, 0, 0) * ankleInv
			local footLow, shinLow = math.huge, math.huge
			for i = 1, 4 do
				footLow = math.min(footLow, (footCF * corners[i]).Y)
				shinLow = math.min(shinLow, (lowerLeg * shinCorners[i]).Y)
			end
			return footLow, shinLow
		end
		-- leading leg: the lowest thigh angle whose heel and shin clear the ground
		for deg = 40, 88 do
			local thigh = math.rad(deg)
			local ankle = LEAD_FOOT_WORLD - (thigh + pose.leadKnee)
			pose.leadThigh, pose.leadAnkle = thigh, ankle
			local footLow, shinLow = lowest(thigh, pose.leadKnee, ankle)
			if math.min(footLow, shinLow) >= -0.03 then
				break
			end
		end
		-- folded leg: rest the shin and foot on the ground, as close to the reference fold as possible
		local best = math.huge
		for thighDeg = 20, 70, 5 do
			for shinDeg = -110, -50, 5 do
				for ankleDeg = -120, 60, 15 do
					local thigh, shinWorld = math.rad(thighDeg), math.rad(shinDeg)
					local footLow, shinLow = lowest(thigh, shinWorld - thigh, math.rad(ankleDeg))
					local low = math.min(footLow, shinLow)
					local score = math.max(0, -low) * 3 + math.max(0, low - 0.15)
						+ math.abs(thighDeg - math.deg(SLIDE_TRAIL_THIGH)) * 0.002 + math.abs(shinDeg - math.deg(SLIDE_TRAIL_SHIN)) * 0.002
					if score < best then
						best = score
						pose.trailThigh, pose.trailShin, pose.trailAnkle = thigh, shinWorld, math.rad(ankleDeg)
					end
				end
			end
		end
	end)
	if not ok then
		pose.leadThigh, pose.leadAnkle = math.rad(72), SLIDE_LEAD_ANKLE
		pose.trailThigh, pose.trailShin, pose.trailAnkle = SLIDE_TRAIL_THIGH, SLIDE_TRAIL_SHIN, SLIDE_TRAIL_ANKLE
	end
	return pose
end

-- Leg geometry for IK: joints, and how far the sole sits below the ankle pivot with the foot flat.
local function legInfo(j, side: string)
	local hip, knee, ankle = j[side .. "Hip"], j[side .. "Knee"], j[side .. "Ankle"]
	if not (hip and knee and ankle) then
		return nil
	end
	local foot = ankle.Parent
	local soleDrop = 0.2
	if foot and foot:IsA("BasePart") then
		soleDrop = math.max(0.05, ankle.C1.Position.Y + foot.Size.Y / 2)
	end
	return { hip = hip, knee = knee, ankle = ankle, hipName = side .. "Hip", kneeName = side .. "Knee",
		ankleName = side .. "Ankle", soleDrop = soleDrop }
end

-- Entries ---------------------------------------------------------------------------------------------------------------

local function untrack(character: Model)
	local entry = entries[character]
	if not entry then
		return
	end
	entries[character] = nil
	filterDirty = true
	for _, conn in ipairs(entry.conns) do
		conn:Disconnect()
	end
	if entry == localEntry then
		localEntry = nil
	end
end

local function track(character: Model, isLocal: boolean)
	if entries[character] then
		return
	end
	local stance = character:GetAttribute("Stance")
	local entry = {
		character = character,
		isLocal = isLocal,
		conns = {},
		rig = nil,
		rigDirty = true,
		partsDirty = true,
		showParts = {},
		hideParts = {},
		wasFirstPerson = false,
		written = {},
		bases = {},
		posed = false,
		crouch = 0,
		slide = 0,
		climb = 0,
		phase = 0,
		stance = if type(stance) == "string" then stance else "Stand",
		slidePose = nil,
		legs = nil,
		twist = 0,
		leanX = 0,
		leanZ = 0,
		ik = 0,
		land = 0,
		air = 0,
		airTime = 0,
		accel = Vector3.zero,
		prevVelH = Vector3.zero,
		prevVy = 0,
		footHold = nil, -- per leg: the floor offset (delta, normal, planted) last read on the ground
		floorTop = nil, -- highest floor under the feet when last read (world Y), and when
		floorAt = -math.huge,
		lift = 0, -- 0..1 rising off the ground (releases the landing dip)
		nearHidden = {}, -- first-person body parts hidden because they are at the camera
	}
	entries[character] = entry
	filterDirty = true
	if isLocal then
		localEntry = entry
	end
	table.insert(entry.conns, character:GetAttributeChangedSignal("Stance"):Connect(function()
		local v = character:GetAttribute("Stance")
		entry.stance = if type(v) == "string" then v else "Stand"
	end))
	table.insert(entry.conns, character.DescendantAdded:Connect(function(d)
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			entry.rigDirty = true
		end
		if isLocal and (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Accessory") or d.Name == "EquippedModel") then
			entry.partsDirty = true
		end
	end))
	table.insert(entry.conns, character.DescendantRemoving:Connect(function(d)
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			entry.rigDirty = true
		end
		if isLocal and (d:IsA("BasePart") or d:IsA("Decal")) then
			entry.partsDirty = true
		end
	end))
	table.insert(entry.conns, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			untrack(character)
		end
	end))
end

local function watchPlayer(p: Player)
	local isLocal = p == player
	p.CharacterAdded:Connect(function(character)
		track(character, isLocal)
	end)
	p.CharacterRemoving:Connect(function(character)
		untrack(character)
	end)
	if p.Character then
		track(p.Character, isLocal)
	end
end

-- Returns true when the entry has a usable R15 rig.
local function ensureRig(entry): boolean
	if entry.isLocal and not entry.rigDirty then
		-- MovementController re-measures when avatar scaling changes the standing height
		local mc = movement()
		local own = if mc and type(mc.getRig) == "function" then mc.getRig() else nil
		if own ~= entry.rig then
			entry.rigDirty = true
		end
	end
	if not entry.rigDirty then
		return entry.rig ~= nil and entry.rig.r15 and entry.rig.joints.Root ~= nil
	end
	local character = entry.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local mc = movement()
	if not humanoid or not root or not mc then
		return false
	end
	local rig = nil
	if entry.isLocal then
		-- the local humanoid's HipHeight is being lowered by crouching: use MovementController's standing measurement
		local own = if type(mc.getRig) == "function" then mc.getRig() else nil
		if own and own.joints.Root and own.joints.Root.Parent and own.joints.Root:IsDescendantOf(character) then
			rig = own
		end
	elseif type(mc.measureRig) == "function" then
		rig = mc.measureRig(character, humanoid, nil)
	end
	if not rig then
		return false -- try again next frame
	end
	entry.rigDirty = false
	entry.rig = rig
	entry.humanoid = humanoid
	entry.root = root
	entry.slidePose = solveSlidePose(rig)
	local left, right = legInfo(rig.joints, "Left"), legInfo(rig.joints, "Right")
	entry.legs = if left and right then { left, right } else nil
	entry.footHold = {
		{ delta = 0, normal = Vector3.yAxis, planted = 0 },
		{ delta = 0, normal = Vector3.yAxis, planted = 0 },
	}
	entry.floorTop = nil
	table.clear(entry.written)
	table.clear(entry.bases)
	entry.posed = false
	return rig.r15 and rig.joints.Root ~= nil
end

-- Pose application ------------------------------------------------------------------------------------------------------

-- This frame's animated Transform. If the Animator didn't write this joint this frame (throttled or not
-- animated) the value is still what we wrote last frame, so we reuse the stored base and never stack poses.
local function readBase(entry, joint: any): CFrame
	local current = joint.Transform
	local written = entry.written[joint]
	if written ~= nil and current == written then
		return entry.bases[joint] or current
	end
	return current
end

local function writeJoint(entry, joint: any, base: CFrame, new: CFrame)
	joint.Transform = new
	entry.written[joint] = new
	entry.bases[joint] = base
end

local function clearPose(entry)
	for joint, written in pairs(entry.written) do
		if joint.Parent and joint.Transform == written then
			local base = entry.bases[joint]
			if base then
				joint.Transform = base
			end
		end
	end
	table.clear(entry.written)
	table.clear(entry.bases)
	entry.posed = false
end

-- World-space rotation taking unit vector a onto unit vector b.
local function rotationBetween(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local s = axis.Magnitude
	local c = a:Dot(b)
	if s < 1e-6 then
		return IDENTITY
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, c))
end

-- Two-bone leg solve. Given the world frame of the lower torso and the posed hip/knee transforms, returns
-- extra rotations (in each joint's C0 frame) that bend the knee and swing the leg so the ankle reaches `target`.
local function solveLeg(lowerCF: CFrame, leg, hipT: CFrame, kneeT: CFrame, target: Vector3): (CFrame, CFrame)
	local hipJ, kneeJ, ankleJ = leg.hip, leg.knee, leg.ankle
	local hipFrame = lowerCF * hipJ.C0
	local upperLeg = hipFrame * hipT * hipJ.C1:Inverse()
	local kneeFrame = upperLeg * kneeJ.C0
	local lowerLeg = kneeFrame * kneeT * kneeJ.C1:Inverse()
	local H = hipFrame.Position
	local Kp = kneeFrame.Position
	local A = (lowerLeg * ankleJ.C0).Position
	local L1 = (Kp - H).Magnitude
	local L2 = (A - Kp).Magnitude
	if L1 < 1e-3 or L2 < 1e-3 then
		return IDENTITY, IDENTITY
	end
	local d0 = math.clamp((A - H).Magnitude, math.abs(L1 - L2) + 1e-3, L1 + L2)
	local d1 = math.clamp((target - H).Magnitude, math.abs(L1 - L2) + 0.05, L1 + L2 - 0.005)
	local denom = 2 * L1 * L2
	local inner0 = math.acos(math.clamp((L1 * L1 + L2 * L2 - d0 * d0) / denom, -1, 1))
	local inner1 = math.acos(math.clamp((L1 * L1 + L2 * L2 - d1 * d1) / denom, -1, 1))
	-- knee flexion is a negative rotation about the hinge (X) axis
	local kneeR = CFrame.Angles(-(inner0 - inner1), 0, 0)
	local lowerLeg2 = kneeFrame * (kneeR * kneeT) * kneeJ.C1:Inverse()
	local A2 = (lowerLeg2 * ankleJ.C0).Position
	local from, to = A2 - H, target - H
	local hipR = IDENTITY
	if from.Magnitude > 1e-4 and to.Magnitude > 1e-4 then
		local world = rotationBetween(from.Unit, to.Unit)
		hipR = hipFrame.Rotation:Inverse() * world * hipFrame.Rotation
	end
	return hipR, kneeR
end

-- Per-frame scratch tables (reused)
local B: { [string]: CFrame } = {}
local P: { [string]: CFrame } = {}

local function poseEntry(entry, dt: number, camPos: Vector3)
	if not ensureRig(entry) then
		return
	end
	local root, humanoid, rig = entry.root, entry.humanoid, entry.rig
	if not root.Parent or not humanoid.Parent or humanoid.Health <= 0 then
		if entry.posed then
			clearPose(entry)
		end
		return
	end
	local distance = (root.Position - camPos).Magnitude
	if not entry.isLocal and distance > POSE_RANGE then
		if entry.posed then
			clearPose(entry)
		end
		entry.crouch, entry.slide, entry.climb = 0, 0, 0
		return
	end
	local j = rig.joints
	if not j.Root then
		return
	end

	-- Stance weights
	local mc = movement()
	local motion = nil
	local land = 0
	-- (the test hook LS_PoseAsRemote poses the local body the way other players' clients pose it)
	local isLocal = entry.isLocal and not poseAsRemote
	if isLocal then
		local blend = if mc and type(mc.getStanceBlend) == "function" then mc.getStanceBlend() else nil
		if blend then
			entry.crouch, entry.slide, entry.climb, entry.phase = blend.crouch, blend.slide, blend.climb, blend.climbPhase
			land = tonumber(blend.land) or 0
		end
		motion = if mc and type(mc.getMotion) == "function" then mc.getMotion() else nil
	else
		local stance = entry.stance
		local k = 1 - math.exp(-BLEND_RATE * dt)
		entry.crouch += ((if stance == "Crouch" then 1 else 0) - entry.crouch) * k
		entry.slide += ((if stance == "Slide" then 1 else 0) - entry.slide) * k
		entry.climb += ((if stance == "Climb" then 1 else 0) - entry.climb) * k
		if entry.climb > 0.01 then
			entry.phase += math.abs(root.AssemblyLinearVelocity.Y) * dt / CLIMB_STROKE
		end
	end
	local c, s, k = entry.crouch, entry.slide, entry.climb

	-- Motion readings: velocity, acceleration, landings
	local rootCF = root.CFrame
	local vel = root.AssemblyLinearVelocity
	local velH = Vector3.new(vel.X, 0, vel.Z)
	local accel: Vector3
	if motion and typeof(motion.accel) == "Vector3" then
		accel = motion.accel
	else
		local raw = (velH - entry.prevVelH) / math.max(dt, 1 / 240)
		if raw.Magnitude > 400 then
			raw = Vector3.zero -- teleport
		end
		entry.accel = entry.accel:Lerp(raw, expAlpha(8, dt))
		accel = entry.accel
	end
	entry.prevVelH = velH
	if not isLocal then
		if entry.prevVy < -28 and vel.Y > -6 then
			local h = entry.prevVy * entry.prevVy / (2 * FALL_GRAVITY)
			entry.land = math.max(entry.land, math.clamp(h / 9, 0.1, 1))
		end
		entry.land = math.max(0, entry.land - dt * 2.6)
		land = smooth01(entry.land)
	end
	entry.prevVy = vel.Y

	-- Ground under the body: grounded estimate and the reference plane the animation's feet stand on
	local drop = rig.crouchDrop * math.max(c, s) + (rig.slideDrop - rig.crouchDrop) * s
	local legsLen = rig.hip + rig.rootHalf
	local refY = rootCF.Position.Y - legsLen + drop
	if filterDirty then
		filterDirty = false
		local list = {}
		for model in pairs(entries) do
			table.insert(list, model)
		end
		ikParams.FilterDescendantsInstances = list
		waterParams.FilterDescendantsInstances = list
	end
	local doIK = entry.legs ~= nil and distance <= IK_RANGE
	local ls = math.clamp((rig.thigh + rig.shin) / REF_LEGS, 0.6, 1.6) -- this rig's legs against the classic rig's
	local groundHit = nil
	if doIK then
		-- (long enough to see the ground coming in a fall: the legs reach for it)
		groundHit = workspace:Raycast(rootCF.Position, Vector3.new(0, -(legsLen + 6), 0), ikParams)
	end
	local grounded = groundHit ~= nil and (rootCF.Position.Y - groundHit.Position.Y) < legsLen - drop + 0.7 * ls
	local groundGap = if groundHit then math.max(0, rootCF.Position.Y - legsLen - groundHit.Position.Y) else 6
	-- Leaving the ground. A take-off lifts the root at once while the floor is still within the feet's reach;
	-- chasing it dragged the pelvis down for three frames and then snapped it back. So once the body rises off the
	-- floor the IK lets go (below) and the feet leave with the body. Local: MovementController's state; remote: the
	-- replicated Jumping state; both: the root rising fast with the feet's reference plane already above the floor
	-- they last stood on (a step-up rises onto a higher floor, so it doesn't count).
	local rising = false
	if doIK and vel.Y > 0 then
		if isLocal then
			rising = ClientState.moveState == "Air"
		else
			rising = humanoid:GetState() == Enum.HumanoidStateType.Jumping
		end
		if not rising and vel.Y > RISE_SPEED then
			local floorY = if entry.floorTop and os.clock() - entry.floorAt < 0.3 then entry.floorTop
				elseif groundHit then groundHit.Position.Y
				else nil
			rising = floorY ~= nil and refY - floorY > RISE_GAP * ls
		end
	end
	-- Airborne (jumps and falls): local from MovementController's state, remote from the take-off, the ground probe
	-- and the vertical speed (swimmers are not airborne)
	local airborne = false
	if doIK and s < 0.2 and k < 0.2 then
		if isLocal then
			airborne = ClientState.moveState == "Air"
		elseif rising or (not grounded and math.abs(vel.Y) > 1.5) then
			local wet = workspace:Raycast(rootCF.Position + Vector3.new(0, 1, 0), Vector3.new(0, -(legsLen + 1.5), 0), waterParams)
			airborne = not (wet and wet.Material == Enum.Material.Water)
		end
	end
	entry.airTime = if airborne then entry.airTime + dt else 0
	-- (a few frames of Freefall over bumps don't count; a jump or a real drop does)
	local airPose = airborne and (entry.airTime > 0.12 or vel.Y > 6 or vel.Y < -10)
	entry.air += ((if airPose then 1 else 0) - entry.air) * expAlpha(if airPose then 10 else 20, dt)
	local ikTarget = if grounded and not rising and s < 0.2 and k < 0.2 then 1 else 0
	entry.ik += (ikTarget - entry.ik) * expAlpha(if ikTarget > entry.ik then 8 elseif rising then RELEASE_RATE else 14, dt)
	local w = entry.ik
	-- the landing dip lets go too when the legs push off again (and is whole again well before the next touch-down)
	entry.lift += ((if rising then 1 else 0) - entry.lift) * expAlpha(RELEASE_RATE, dt)

	-- Hip twist toward the direction of travel (strafing), counter-turned at the waist and neck
	local bodyFwd = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z)
	local speedH = velH.Magnitude
	local twistTarget = 0
	if bodyFwd.Magnitude > 1e-3 and speedH > 1.5 and s < 0.2 and k < 0.2 then
		local fwdU = bodyFwd.Unit
		local dir = velH / speedH
		local angle = math.atan2(fwdU:Cross(dir).Y, fwdU:Dot(dir))
		if math.abs(angle) > math.rad(100) then
			angle -= math.sign(angle) * math.pi -- backpedalling: the legs walk backwards, facing forward
		end
		twistTarget = math.clamp(angle * 0.65, -TWIST_MAX, TWIST_MAX) * math.clamp((speedH - 1.5) / 3, 0, 1)
	end
	entry.twist += (twistTarget - entry.twist) * expAlpha(9, dt)
	local twist = entry.twist

	-- Lean into acceleration and turns (plus a little into the run), body-relative
	local leanXTarget, leanZTarget = 0, 0
	if bodyFwd.Magnitude > 1e-3 and s < 0.2 and k < 0.2 then
		local fwdU = bodyFwd.Unit
		local rightU = Vector3.new(-fwdU.Z, 0, fwdU.X)
		local aF = accel:Dot(fwdU)
		local aL = accel:Dot(rightU)
		local vF = velH:Dot(fwdU)
		leanXTarget = -math.clamp(aF * LEAN_PER_ACCEL, -LEAN_BACK_MAX, LEAN_FORWARD_MAX)
			- RUN_LEAN * math.clamp(vF / SPRINT_SPEED, 0, 1) * (if grounded then 1 else 0.4)
		leanZTarget = -math.clamp(aL * ROLL_PER_ACCEL, -ROLL_MAX, ROLL_MAX)
	end
	entry.leanX += (leanXTarget - entry.leanX) * expAlpha(7, dt)
	entry.leanZ += (leanZTarget - entry.leanZ) * expAlpha(7, dt)
	local leanX, leanZ = entry.leanX, entry.leanZ

	local trivial = c < 0.002 and s < 0.002 and k < 0.002 and math.abs(twist) < 0.004 and math.abs(leanX) < 0.002
		and math.abs(leanZ) < 0.002 and land < 0.002 and w < 0.002 and entry.air < 0.002
	if trivial then
		if entry.posed then
			clearPose(entry)
		end
		return
	end

	-- Stance pose angles
	local legs = rig.thigh + rig.shin
	local cdrop = rig.crouchDrop * c
	local theta = if cdrop > 1e-3 then math.acos(math.clamp(1 - cdrop / legs, -1, 1)) else 0
	local rootX = CROUCH_ROOT * c + SLIDE_ROOT * s + CLIMB_ROOT * k
	local waistX = CROUCH_WAIST * c + SLIDE_WAIST * s
	local neckX = CROUCH_NECK * c + SLIDE_NECK * s + CLIMB_NECK * k
	-- A limb's world swing = root rotation + its own hip rotation, so each hip subtracts the root lean.
	local hipCrouch = theta - CROUCH_ROOT * c
	local kneeCrouch = -2 * theta
	local ankleCrouch = theta
	local sp = entry.slidePose
	local hipLead = (sp.leadThigh - SLIDE_ROOT) * s
	local hipTrail = (sp.trailThigh - SLIDE_ROOT) * s
	local kneeLead = sp.leadKnee * s
	local kneeTrail = (sp.trailShin - sp.trailThigh) * s
	local ankleLead = sp.leadAnkle * s
	local ankleTrail = sp.trailAnkle * s
	local reachL = 0.5 + 0.5 * math.sin(entry.phase * 2 * math.pi)
	local reachR = 1 - reachL
	local shoulderL = (2.35 + 0.45 * reachL) * k
	local shoulderR = (2.35 + 0.45 * reachR) * k
	local elbowL = (0.25 + 0.75 * (1 - reachL)) * k
	local elbowR = (0.25 + 0.75 * (1 - reachR)) * k
	local hipClimbL = (0.3 + 0.8 * reachR) * k
	local hipClimbR = (0.3 + 0.8 * reachL) * k
	local kneeClimbL = -(0.4 + 1.0 * reachR) * k
	local kneeClimbR = -(0.4 + 1.0 * reachL) * k
	local shoulderLX = CROUCH_SHOULDER * c + math.rad(-25) * s + shoulderL
	local shoulderRX = CROUCH_SHOULDER * c + math.rad(40) * s + shoulderR
	local shoulderLZ = math.rad(-35) * s + 0.12 * k
	local shoulderRZ = math.rad(20) * s - 0.12 * k
	-- Air: tuck toward the apex, reach for the ground before touch-down, arms out for balance
	local a = entry.air
	local airHipL, airHipR, airKneeL, airKneeR, airAnkle, airElbow = 0, 0, 0, 0, 0, 0
	if a > 0.002 then
		local ascent = math.clamp(vel.Y / 22, 0, 1) -- 1 right after take-off: the legs are still extending
		local reach = math.clamp((groundGap - 0.3 * ls) / (2.2 * ls), 0, 1) -- 0 = about to touch down: legs reach
		local tuck = (1 - 0.65 * ascent) * (if vel.Y < 0 then reach else 1)
		local longFall = math.clamp((entry.airTime - 0.5) / 0.6, 0, 1)
		tuck = (tuck * (1 - 0.5 * longFall) + 0.3 * longFall) * a
		-- first person, looking down at your own body: the tucked knees came up into the view and hid the hands, so
		-- the tuck and the forward lean flatten out the further you look down (only this client sees its own body)
		local view = if isLocal then 1 - FP_TUCK_CUT * fpDown else 1
		tuck *= view
		local airLean = AIR_LEAN * a * view
		airHipL = AIR_HIP * tuck - airLean
		airHipR = AIR_HIP * tuck * 0.7 - airLean
		airKneeL, airKneeR = AIR_KNEE * tuck, AIR_KNEE * tuck * 0.75
		airAnkle = AIR_ANKLE * tuck
		airElbow = AIR_ELBOW * a
		local out = (AIR_ARM_OUT + (FALL_ARM_OUT - AIR_ARM_OUT) * longFall) * a
		shoulderLX += AIR_ARM_FWD * a
		shoulderRX += AIR_ARM_FWD * a
		shoulderLZ -= out
		shoulderRZ += out
		rootX += airLean
	end

	-- Bases (this frame's animation) and stance/twist poses
	for _, name in ipairs(POSE_JOINTS) do
		local joint = j[name]
		B[name] = if joint and joint.Parent then readBase(entry, joint) else IDENTITY
	end
	local rootStance = CFrame.Angles(0, twist, 0) * CFrame.Angles(rootX, 0, 0)
	P.Waist = CFrame.Angles(leanX * 0.5, 0, leanZ * 0.5) * CFrame.Angles(0, -twist * 0.85, 0) * CFrame.Angles(waistX, 0, 0)
	-- the neck counters the lean so the head stays level
	P.Neck = CFrame.Angles(-leanX * 0.8, 0, -leanZ * 0.8) * CFrame.Angles(0, -twist * 0.15, 0) * CFrame.Angles(neckX, 0, 0)
	P.LeftHip = CFrame.Angles(hipCrouch + hipTrail + hipClimbL + airHipL, 0, 0)
	P.RightHip = CFrame.Angles(hipCrouch + hipLead + hipClimbR + airHipR, 0, 0)
	P.LeftKnee = CFrame.Angles(kneeCrouch + kneeTrail + kneeClimbL + airKneeL, 0, 0)
	P.RightKnee = CFrame.Angles(kneeCrouch + kneeLead + kneeClimbR + airKneeR, 0, 0)
	P.LeftAnkle = CFrame.Angles(ankleCrouch + ankleTrail + airAnkle, 0, 0)
	P.RightAnkle = CFrame.Angles(ankleCrouch + ankleLead + airAnkle, 0, 0)
	P.LeftShoulder = CFrame.Angles(shoulderLX, 0, shoulderLZ)
	P.RightShoulder = CFrame.Angles(shoulderRX, 0, shoulderRZ)
	P.LeftElbow = CFrame.Angles(elbowL + airElbow, 0, 0)
	P.RightElbow = CFrame.Angles(elbowR + airElbow, 0, 0)

	-- First person, looking down in the air: the jump clip doesn't lift the pelvis or pitch the trunk toward the eye
	-- (see the header; on the ground the clips are left as they are)
	local baseRoot = B.Root
	local fpFix = if isLocal then fpDown * a else 0
	if fpFix > 0.002 then
		local t = baseRoot.Position
		local rx = baseRoot:ToEulerAnglesXYZ()
		local lift = math.max(0, t.Y) * fpFix
		local unpitch = math.max(0, -rx) * fpFix -- (a forward pitch is a negative X rotation)
		if lift > 1e-4 or unpitch > 1e-4 then
			baseRoot = CFrame.new(t.X, t.Y - lift, t.Z) * CFrame.Angles(unpitch, 0, 0) * baseRoot.Rotation
		end
	end

	local rootJ = j.Root
	local rootFrame = rootCF * rootJ.C0
	local rootC1Inv = rootJ.C1:Inverse()
	local rootLean = CFrame.Angles(leanX * 0.5, 0, leanZ * 0.5)
	local pelvisDrop = 0
	local legOut = nil

	if doIK and (w > 0.002 or land > 0.002) then
		-- 1) where the posed feet want to be (before lean and pelvis drop), and the ground under each. On the ground
		-- each foot reads the floor; while the IK lets go (a take-off, or the ground fell away) it only releases the
		-- offsets it last read, so the feet never chase a floor that is dropping away under the body.
		local lowerStance = rootFrame * (rootStance * B.Root) * rootC1Inv
		legOut = {}
		local minDelta = 0
		local sample = ikTarget > 0
		local floorTop = -math.huge
		for i, leg in ipairs(entry.legs) do
			local hipT = P[leg.hipName] * B[leg.hipName]
			local kneeT = P[leg.kneeName] * B[leg.kneeName]
			local ankleT = P[leg.ankleName] * B[leg.ankleName]
			local hipFrame = lowerStance * leg.hip.C0
			local upperLeg = hipFrame * hipT * leg.hip.C1:Inverse()
			local lowerLeg = upperLeg * leg.knee.C0 * kneeT * leg.knee.C1:Inverse()
			local ankleFrame = lowerLeg * leg.ankle.C0
			local A = ankleFrame.Position
			local footRot = (ankleFrame * ankleT).Rotation -- the posed foot's world orientation
			local lift = (A.Y - leg.soleDrop) - refY
			local delta, normal, planted = 0, Vector3.yAxis, 0
			local hold = entry.footHold and entry.footHold[i]
			if w > 0.002 then
				if sample or not hold then
					local footUp, footDown = MAX_FOOT_UP * ls, MAX_FOOT_DOWN * ls
					local hit = workspace:Raycast(Vector3.new(A.X, refY + footUp + 0.25, A.Z),
						Vector3.new(0, -(footUp + footDown + 0.5), 0), ikParams)
					if hit then
						delta = math.clamp(hit.Position.Y - refY, -footDown, footUp)
						normal = hit.Normal
						planted = 1 - math.clamp((lift - 0.15 * ls) / (0.6 * ls), 0, 1)
						if planted < 0.5 then
							delta = math.max(delta, -0.35 * ls) -- a swinging foot doesn't reach down into holes
						end
						floorTop = math.max(floorTop, hit.Position.Y)
					end
					if hold then
						hold.delta, hold.normal, hold.planted = delta, normal, planted
					end
				else
					delta, normal, planted = hold.delta, hold.normal, hold.planted
				end
			end
			delta *= w
			minDelta = math.min(minDelta, delta * planted)
			legOut[i] = { leg = leg, target = A + Vector3.new(0, delta, 0), normal = normal, planted = planted,
				footRot = footRot, ankleT = ankleT }
		end
		if sample and floorTop > -math.huge then
			entry.floorTop, entry.floorAt = floorTop, os.clock()
		end
		-- 2) the pelvis drops so the lower foot can reach (plus the landing dip, released when the legs push off)
		pelvisDrop = math.clamp(-minDelta, 0, MAX_PELVIS_DROP * ls)
			+ land * LAND_DROP * ls * math.max(w, 0.35) * (1 - entry.lift)
	end

	-- Root: twist + stance + lean, lowered by the pelvis drop (world down, expressed in the joint frame)
	local dropLocal = rootFrame:VectorToObjectSpace(Vector3.new(0, -pelvisDrop, 0))
	local rootT = CFrame.new(dropLocal) * rootLean * rootStance * baseRoot
	writeJoint(entry, rootJ, B.Root, rootT)

	if legOut then
		-- 3) solve each leg from the final pelvis onto its target, then tilt planted feet onto the ground
		local lowerFinal = rootFrame * rootT * rootC1Inv
		for _, out in ipairs(legOut) do
			local leg = out.leg
			local hipT = P[leg.hipName] * B[leg.hipName]
			local kneeT = P[leg.kneeName] * B[leg.kneeName]
			local hipR, kneeR = solveLeg(lowerFinal, leg, hipT, kneeT, out.target)
			local hipFinal = hipR * hipT
			local kneeFinal = kneeR * kneeT
			-- keep the posed foot orientation (lean and leg swing don't tilt it), then lay it on the ground
			local hipFrame = lowerFinal * leg.hip.C0
			local upperLeg = hipFrame * hipFinal * leg.hip.C1:Inverse()
			local ankleFrame = upperLeg * leg.knee.C0 * kneeFinal * leg.knee.C1:Inverse() * leg.ankle.C0
			local desired = out.footRot
			local n = out.normal
			local axis = Vector3.yAxis:Cross(n)
			local axisLen = axis.Magnitude
			if axisLen > 1e-3 and n.Y > 0.2 then
				local tiltAngle = math.min(math.atan2(axisLen, n.Y), MAX_FOOT_TILT) * out.planted * w
				desired = CFrame.fromAxisAngle(axis / axisLen, tiltAngle) * out.footRot
			end
			local ankleFinal = CFrame.new(out.ankleT.Position) * (ankleFrame.Rotation:Inverse() * desired)
			writeJoint(entry, leg.hip, B[leg.hipName], hipFinal)
			writeJoint(entry, leg.knee, B[leg.kneeName], kneeFinal)
			writeJoint(entry, leg.ankle, B[leg.ankleName], ankleFinal)
		end
	else
		for _, name in ipairs(LEG_JOINTS) do
			local joint = j[name]
			if joint and joint.Parent then
				writeJoint(entry, joint, B[name], P[name] * B[name])
			end
		end
	end
	for _, name in ipairs(UPPER_JOINTS) do
		local joint = j[name]
		if joint and joint.Parent then
			writeJoint(entry, joint, B[name], P[name] * B[name])
		end
	end
	entry.posed = true
end

local function preSimulation(dt: number)
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	for _, entry in pairs(entries) do
		local ok, err = pcall(poseEntry, entry, dt, camPos)
		if not ok and os.clock() - errorAt > 5 then
			errorAt = os.clock()
			warn("[CharacterVisuals] pose error: " .. tostring(err))
		end
	end
end

-- First-person body ----------------------------------------------------------------------------------------------------

local function rebuildLocalParts(entry)
	local show, hide = {}, {}
	local character = entry.character
	for _, d in ipairs(character:GetDescendants()) do
		local hidden = d.Name == "EquippedModel" or d:FindFirstAncestor("EquippedModel") ~= nil
		if hidden then
			if d:IsA("BasePart") or d:IsA("Decal") then
				table.insert(hide, d)
			end
		elseif d:IsA("BasePart") then
			if d.Parent == character and BODY_PARTS[d.Name] then
				table.insert(show, d)
			else
				local accessory = d:FindFirstAncestorWhichIsA("Accessory")
				if accessory and accessory.Parent == character and LOWER_BODY_ACCESSORIES[accessory.AccessoryType] then
					table.insert(show, d)
				end
			end
		end
	end
	entry.showParts, entry.hideParts = show, hide
end

local function isFirstPerson(): boolean
	local cam = Controllers and Controllers.CameraController
	if cam and type(cam.isFirstPerson) == "function" then
		return cam.isFirstPerson() == true
	end
	local camera = workspace.CurrentCamera
	return camera ~= nil and player.CameraMode == Enum.CameraMode.LockFirstPerson
		and (camera.Focus.Position - camera.CFrame.Position).Magnitude < 1.5
end

-- RenderPriority.Camera + 2: after the default TransparencyController (which hides everything in first person)
-- and after CameraController (the camera is final here).
local function firstPersonBody(dt: number)
	local entry = localEntry
	if not entry then
		fpDown = 0
		return
	end
	if entry.partsDirty then
		entry.partsDirty = false
		rebuildLocalParts(entry)
		table.clear(entry.nearHidden)
	end
	local cam = workspace.CurrentCamera
	if cam and isFirstPerson() and ClientState.spectating == nil then
		local camCF = cam.CFrame
		-- how steeply the view looks down (the air pose flattens its tuck under a downward view)
		local down = smooth01((-camCF.LookVector.Y - FP_DOWN_FROM) / (FP_DOWN_FULL - FP_DOWN_FROM))
		fpDown += (down - fpDown) * expAlpha(14, math.clamp(tonumber(dt) or 1 / 60, 0, 0.1))
		-- a body part right at the camera would be cut open by the near plane: hidden until it moves away
		local eye = camCF.Position
		local nearHidden = entry.nearHidden
		for _, part in ipairs(entry.showParts) do
			local p = part.CFrame:PointToObjectSpace(eye)
			local h = part.Size * 0.5
			local gap = (p - Vector3.new(math.clamp(p.X, -h.X, h.X), math.clamp(p.Y, -h.Y, h.Y), math.clamp(p.Z, -h.Z, h.Z))).Magnitude
			local hide = gap < (if nearHidden[part] then NEAR_SHOW else NEAR_CULL)
			nearHidden[part] = if hide then true else nil
			local want = if hide then 1 else 0
			if part.LocalTransparencyModifier ~= want then
				part.LocalTransparencyModifier = want
			end
		end
		for _, part in ipairs(entry.hideParts) do
			if part.LocalTransparencyModifier ~= 1 then
				part.LocalTransparencyModifier = 1
			end
		end
		entry.wasFirstPerson = true
	else
		fpDown = 0
		if entry.wasFirstPerson then
			entry.wasFirstPerson = false
			for _, part in ipairs(entry.hideParts) do
				part.LocalTransparencyModifier = 0
			end
			for part in pairs(entry.nearHidden) do
				part.LocalTransparencyModifier = 0
			end
			table.clear(entry.nearHidden)
		end
	end
end

function CharacterVisuals.Init(registry)
	Controllers = registry
end

function CharacterVisuals.Start()
	local function readHook()
		poseAsRemote = player:GetAttribute("LS_PoseAsRemote") == true
	end
	readHook()
	player:GetAttributeChangedSignal("LS_PoseAsRemote"):Connect(readHook)
	RunService:BindToRenderStep("LS_FirstPersonBody", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local ok, err = pcall(firstPersonBody, dt)
		if not ok and os.clock() - errorAt > 5 then
			errorAt = os.clock()
			warn("[CharacterVisuals] body error: " .. tostring(err))
		end
	end)
	RunService.PreSimulation:Connect(preSimulation)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(p)
		if p.Character then
			untrack(p.Character)
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
end

return CharacterVisuals
