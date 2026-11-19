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
	LOD.poseRange studs of the camera are processed (IK within LOD.ikRange), with caps so a crowd cannot sink a frame
	(47 contenders run to the horn together): only the nearest LOD.ikMax other characters get foot IK and the air pose
	(three rays each), only the nearest LOD.poseMax get the twist and lean, and one behind the camera (further than
	LOD.behindNear) counts as far; the rest keep only what must be seen at any distance, stances (crouch, slide,
	climb) and swings, and cost nothing while they do neither. Ranked every LOD.rank seconds (the living only; one
	that has foot IK keeps it two places past the cap, so two at the edge don't swap it); phones and tablets use
	the smaller LOD_TOUCH numbers. CharacterVisuals._poseStats has the measured cost.
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
	  7. Melee swings (#90): other players' swings, from the CombatAction remote ("Swing", which the server relays when
	     the swing starts, with the attacker's swing set as `variant` and `lead`, the seconds until the strike: the
	     wind-up is fitted so the cut crosses at the strike, when the damage lands; a swing announced only at its strike
	     (lead 0) starts wound up), as a short procedural swing on the waist, neck, shoulders
	     and elbows over whatever the Animator plays (the "toolnone" hold with a weapon, the idle with fists): a flat or
	     falling cut to the left, a backhand to the right, an overhead chop, a spear thrust (straight, high or low), a
	     left jab or a right cross. The shape follows the first-person set the attacker played (ViewmodelController.Poses:
	     a set's own `tp` name, else its hand path), so both views agree; with no variant (an older server) the shapes
	     alternate per attacker. A quick wind-up, a fast cut, a held follow-through that settles, then a slower recovery;
	     the torso leads the arm, the neck keeps the head on the target and the other arm counters. 0.36 / 0.42 / 0.5 s by
	     the weapon's weight (fists 0.4), and every swing a little different (size, path, length). A swing that cuts into
	     another blends from where the body was. Config.Combat.ThirdPersonSwings = false turns it off.
	  8. The bow. The server welds it into the LEFT hand (InventoryService), as in first person. While a character holds
	     one (the replicated character attribute EquippedItem) the bow arm is raised with the forearm level, the bow
	     upright in front of the body and clear of the ground, a little higher while crouched (the Animator's arm swing is
	     replaced, by weight). A draw
	     ("Draw" on the CombatAction remote for other players, CombatController.action for your own body) lifts the bow
	     arm straight out at the target and turns the chest side-on (not on your own first-person body), while the right
	     hand reaches for the string and pulls it back to the cheek over the bow's own draw time: a two-bone solve onto
	     a point that runs from the bow's Nock to an anchor beside the jaw, the elbow kept out and back. On other
	     players the straight string mesh is swapped for two Beams through the pulling hand while it is drawn. "Release":
	     the string snaps back at once, the hand stays at the cheek a moment and both arms settle; a let-down (cancelled)
	     rides the string forward again. It shows at any distance inside LOD.poseRange, like stances and swings.
	Defeat (the game's age rating: clearly unrealistic). A body at zero health stays in one piece (the server turns
	BreakJointsOnDeath off), topples over (your own client tips your own body back), and DEFEAT_FALL seconds later
	fades out over DEFEAT_FADE on this client (LocalTransparencyModifier); the server then removes it for everyone
	(CombatService). Roblox's default "Died" voice sound is muted on every character: there is no cry.
	IK reach, pelvis drop and the landing dip scale with each rig's leg length (any avatar size).
	First person (local body only): the eye is placed from the root, not from the animated head, so in the air under a
	downward view the own body keeps the jump clip's root lift and forward trunk pitch at most at the bind pose (the clip
	lifts the pelvis ~0.2 studs and pitches the trunk ~8 degrees forward, which brought the chest up into the view and
	hid the hands), and the air tuck and lean flatten out. A shown body part within NEAR_CULL studs of the camera is
	hidden until it moves away (never cut open by the near plane). Test hooks (Studio only): the local player's attribute
	LS_PoseAsRemote = true poses the own body through the remote path (what other players' clients compute) and lets
	CombatAction swings sent about yourself show on it; LS_SwingSlowMo = n plays the swings that start while it is set n
	times slower.

	Public API (through the Controllers registry):
	  CharacterVisuals.headLean(rig, crouchWeight, slideWeight) -> (forward: number, down: number)
	      how far the head centre moves (root space, studs) under the crouch/slide poses; CameraController uses it.
	  CharacterVisuals.playSwing(character, itemId?, variant?, lead?) -> boolean
	      a third-person swing (item 7) on that character; any R15 model (a test rig, an NPC) is tracked on first use.
	      lead: seconds from now to the strike (0 = it lands now: the swing starts wound up); nil = the plain shape.
	  CharacterVisuals._poseStats -> { ms, last, peak, entries, posed, ik }   test hook: the pose pass's cost per frame (ms:
	      smoothed, last frame's, the recent peak) and how many characters it tracked, posed and gave foot IK last frame.
	  CharacterVisuals._lod   test hook: the caps (LOD), to compare costs live in a playtest.
	  CharacterVisuals._swingOf(character) -> { shape, style, variant, u, duration }?   test hook: the swing it plays.
	  CharacterVisuals._swingShapes   test hook: the shape table (radians), to try new angles live in a playtest.
	  CharacterVisuals._bow   test hook: the bow pose's numbers (radians, studs), to tune live in a playtest.
	  CharacterVisuals._bowEvent(character, "Draw" | "Release", cancelled?)   test hook: a draw on any tracked character.
	  CharacterVisuals._bowOf(character) -> { bow, hold, aim, arm, pull, drawing, string }?   test hook: its bow state.

	Combat v3 (19 Nov, docs/design/Combat_v3.md sections 1 and 7): "rogue and choppy" was the three keys of item 7.
	  Swings are now sampled through nine keys on a Hermite curve with time-fitted tangents (rest, coil, wound up past
	  W, half way, M, an overshoot past F, F, the settle, rest), so the velocity is continuous: the cut accelerates
	  out of the anticipation, overshoots, settles and returns. A swing's length is its move's (Shared.Moves: the
	  chain step, the heavy, the counter), its shape from the step's first-person set. Over the swing layer:
	  the guard (a held pose per family, CombatAction "Guard"), the heavy's hold ("Charge": the wind-up held, coiled),
	  upper-body reactions ("React": additive, 0.08 s in, 0.25 s out, the owner's numbers; the legs keep walking),
	  and a full-body layer (root pitch, turn and roll, the pelvis, both hips and knees; foot IK lets go while it
	  plays) for the kick, the dodges ("Dodge": a back step, side hops, a forward roll), the stagger and heavy
	  stagger, the knockdown and get-up, and the skills ("Skill": Whirl's turn, Vault Kick, Running Cut, Head Kick,
	  the chained strikes, a breath for Concentration, Second Wind and Brace). Hit-stop: the two bodies of a hit within
	  Moves.reactions.HitStopViewRange of the camera hold their swing for the hit-stop. A dummy's swing (payload.model)
	  shows the same way. When the clip player exists (Controllers.ClipPlayer.applyTP(character, clipName, t, weight)
	  -> boolean) and has the move's clip (Moves.clipName), it poses the joints instead, family by family.
	  CharacterVisuals.playBody(character, kind) / react(character, tier, from) / setGuard(character, on, itemId)
	  are the hooks (test rigs too); _bodyMoves holds the full-body keys (degrees, studs) for tuning.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Moves = require(Shared:WaitForChild("Moves"))
local Net = require(Shared:WaitForChild("Net"))

local CharacterVisuals = {}

local player = Players.LocalPlayer

local MOVE = Config.Movement or {}
-- How much of a crowd is posed (see the header). Distances are from the camera.
local LOD = {
	poseRange = 150, -- studs: further characters are left to the Animator
	ikRange = 75, -- studs: foot IK inside this
	ikMax = 8, -- the nearest this many other characters get foot IK and the air pose (both read the ground)
	poseMax = 24, -- the nearest this many get the twist and lean; the rest only stances and swings
	behindNear = 14, -- studs: a character behind the camera and further than this counts as far
	rank = 0.25, -- seconds between rankings
}
local LOD_TOUCH = { poseRange = 90, ikRange = 45, ikMax = 4, poseMax = 12 } -- phones and tablets
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
-- Melee swings (#90, item 7 above). Each shape has three keyframes, W (wound up), M (the cut) and F (the
-- follow-through), as joint angles in degrees over the Animator's pose: waist { lean back, turn left, bend left },
-- right shoulder { raise, swing toward the left, out to the right }, right elbow bend, left shoulder { raise, swing
-- toward the left, in toward the right }, left elbow bend. `arm`: the striking arm (the path jitter goes there).
local SWING_N = 11
local function swingKey(waist: { number }, rs: { number }, re: number, ls: { number }, le: number): { number }
	local r = math.rad
	return {
		r(waist[1]), r(waist[2]), r(waist[3]), r(rs[1]), r(rs[2]), r(rs[3]), r(re), r(ls[1]), r(ls[2]), r(ls[3]), r(le),
	}
end
local SWING_SHAPES: { [string]: { arm: string, W: { number }, M: { number }, F: { number } } } = {
	Left = { -- a flat cut from the right across to the left at chest height
		arm = "Right",
		W = swingKey({ 0, -24, 0 }, { 20, -60, 10 }, 40, { 10, 0, -12 }, 30),
		M = swingKey({ -2, 2, 0 }, { 2, 0, 0 }, 10, { 0, 0, -6 }, 20),
		F = swingKey({ -4, 28, 0 }, { -18, 70, -6 }, 18, { -14, 0, -14 }, 35),
	},
	DownLeft = { -- falling: from high at the right down across to the low left
		arm = "Right",
		W = swingKey({ 6, -22, -4 }, { 55, -50, 15 }, 55, { 12, 0, -12 }, 30),
		M = swingKey({ -4, 2, 0 }, { 10, 0, 0 }, 12, { 0, 0, -6 }, 20),
		F = swingKey({ -12, 26, 4 }, { -40, 60, -8 }, 15, { -12, 0, -16 }, 35),
	},
	Right = { -- a backhand from the left across to the right, rising a little
		arm = "Right",
		W = swingKey({ 0, 26, 0 }, { 0, 75, -10 }, 80, { -8, 0, -8 }, 30),
		M = swingKey({ -2, 0, 0 }, { 8, 0, 0 }, 25, { 0, 0, -6 }, 20),
		F = swingKey({ -2, -26, 0 }, { 22, -62, 18 }, 10, { 10, 0, -10 }, 30),
	},
	Overhead = { -- straight down from over the head, the body bending into it
		arm = "Right",
		W = swingKey({ 12, -8, 0 }, { 80, -8, 8 }, 75, { 20, 0, -14 }, 40),
		M = swingKey({ -8, 0, 0 }, { 12, 0, 0 }, 15, { 4, 0, -8 }, 25),
		F = swingKey({ -18, 6, 0 }, { -50, 8, 0 }, 8, { -10, 0, -10 }, 25),
	},
	Thrust = { -- the spear drawn back to the hip, level, then driven straight out with the shoulder behind it
		arm = "Right",
		W = swingKey({ 4, -22, 0 }, { -60, -8, 10 }, 50, { 20, 0, -10 }, 45),
		M = swingKey({ -4, 8, 0 }, { 2, 4, 0 }, 0, { 6, 0, -6 }, 30),
		F = swingKey({ -10, 20, 0 }, { 11, 6, 0 }, -8, { -6, 0, -8 }, 25),
	},
	ThrustHigh = {
		arm = "Right",
		W = swingKey({ 4, -22, 0 }, { -50, -8, 10 }, 50, { 20, 0, -10 }, 45),
		M = swingKey({ -2, 8, 0 }, { 14, 4, 0 }, 0, { 6, 0, -6 }, 30),
		F = swingKey({ -6, 20, 0 }, { 26, 6, 0 }, -8, { -6, 0, -8 }, 25),
	},
	ThrustLow = {
		arm = "Right",
		W = swingKey({ 2, -22, 0 }, { -64, -8, 10 }, 50, { 20, 0, -10 }, 45),
		M = swingKey({ -8, 8, 0 }, { -10, 4, 0 }, 0, { 6, 0, -6 }, 30),
		F = swingKey({ -16, 20, 0 }, { -6, 6, 0 }, -8, { -6, 0, -8 }, 25),
	},
	Jab = { -- fists: up into a guard, the left fist driven straight out, the body turning behind it
		arm = "Left",
		W = swingKey({ 0, -8, 0 }, { 45, 0, 4 }, 110, { 60, -6, -4 }, 115),
		M = swingKey({ -3, -16, 0 }, { 45, 0, 4 }, 112, { 88, -10, 0 }, 15),
		F = swingKey({ -4, -18, 0 }, { 42, 0, 4 }, 108, { 92, -12, 0 }, 4),
	},
	Cross = { -- the right fist across from the guard, the body turning behind it
		arm = "Right",
		W = swingKey({ 0, 10, 0 }, { 60, 6, 4 }, 115, { 45, 0, -4 }, 110),
		M = swingKey({ -4, 20, 0 }, { 88, 12, 0 }, 15, { 45, 0, -4 }, 112),
		F = swingKey({ -5, 24, 0 }, { 92, 14, 0 }, 4, { 42, 0, -4 }, 108),
	},
}
-- Chops and smashes bend the body further into the blow (the waist's lean x torso); a smash also winds up higher (the
-- right shoulder `raise` degrees more at W).
local SWING_STYLE: { [string]: { torso: number, raise: number? } } = {
	Chop = { torso = 1.3 },
	Smash = { torso = 1.4, raise = 10 },
}
local SWING_TIME = { Light = 0.36, Medium = 0.42, Heavy = 0.5 } -- seconds, by the weapon's weight
local SWING_TIME_STYLE = { Punch = 0.4 } -- (fists come up into a guard first)
local SWING_WINDUP = { Light = 0.22, Medium = 0.24, Heavy = 0.28 } -- share of the swing spent winding up, then
local SWING_CUT = 0.1 -- to the cut (M), accelerating,
local SWING_FOLLOW = 0.12 -- on into the follow-through (F), slowing,
local SWING_HOLD = 0.1 -- held there while it settles SWING_SETTLE of the way back; the rest is the recovery
local SWING_SETTLE = 0.12
local SWING_SIZE = { Light = 0.85, Medium = 1, Heavy = 1.1 } -- how big the motion is, by weight
local SWING_SIZE_JITTER = 0.08 -- every swing a little different: its size (+-8 %),
local SWING_ANGLE_JITTER = 4 -- the striking arm's path (+-4 degrees up or down and sideways)
local SWING_TIME_JITTER = 0.05 -- and its length (+-5 %)
local SWING_LEAD = 0.04 -- the torso leads the arm by this share of the swing
local SWING_FADE = 0.07 -- seconds: a swing that cuts into another blends from where the body was
-- The bow (item 8 above). Angles in radians: `raise` swings the hanging arm forward (pi / 2 = level), `elbow` bends it,
-- `yaw` turns the raised arm toward the body's left (+) or right (-).
local BOW = {
	holdRaise = math.rad(34), -- held: the upper arm a third of the way up,
	holdElbow = math.rad(56), -- the forearm level (raise + elbow = 90 degrees keeps the bow upright),
	holdYaw = math.rad(-14), -- the hand a little in front of the body
	crouchRaise = math.rad(24), -- crouched: the bow arm that much higher, so the lower limb stays off the ground
	aimRaise = math.rad(86), -- drawn: the bow arm straight out at shoulder height
	aimElbow = math.rad(6),
	turn = math.rad(-36), -- the chest turns side-on (to the right), the neck keeps the head on the target
	anchor = Vector3.new(0.48, -0.5, 0.06), -- the string hand's wrist at full draw, in the head's frame (x rig scale)
	reach = 0.22, -- where the pull starts, as a share of the way from the bow's Nock to the anchor (the wrist sits
	-- a hand's length behind the fingers on the string)
	pole = Vector3.new(0.75, 0.3, 0.6), -- the string arm's elbow points this way in the root's frame: out, up, back
	follow = 0.35, -- seconds the pose is held after the arrow leaves
	limit = 90, -- seconds: a draw that never ended (its Release never reached this client) is let down
	stringWidth = 0.035,
	stringColor = Color3.fromRGB(160, 132, 92),
}
-- Defeat (see the header): a body is seen falling for DEFEAT_FALL seconds, then fades over DEFEAT_FADE. CombatService
-- has the same two numbers and removes the body when they have passed.
local DEFEAT_FALL = 1.8
local DEFEAT_FADE = 1.0
local DEFEAT_TIP = 2.6 -- radians/s: your own client tips your own body over backward as it falls

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

-- The slide pose's angles before a rig's own are solved (solveSlidePose, the first time that character slides).
local DEFAULT_SLIDE_POSE = {
	leadThigh = math.rad(72),
	leadKnee = SLIDE_LEAD_KNEE,
	leadAnkle = SLIDE_LEAD_ANKLE,
	trailThigh = SLIDE_TRAIL_THIGH,
	trailShin = SLIDE_TRAIL_SHIN,
	trailAnkle = SLIDE_TRAIL_ANKLE,
}

local poseStats = { ms = 0, last = 0, peak = 0, entries = 0, posed = 0, ik = 0, slideSolves = 0 }
local ikCount = 0 -- characters given foot IK this frame

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
local slidePoseCache: { [string]: any } = {} -- solved slide poses by the leg's measures (solveSlidePose); never changed once stored
local slidePoseCount = 0

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
	-- The solve below is about 1,900 leg poses (0.9 ms on a desktop, several on a phone) and runs in the frame a
	-- character first slides: at the horn many do so within seconds. Its result depends only on the leg's measures,
	-- so it is kept by those: avatars of one build share a solve, and so does the same contender round after round.
	local key: string? = nil
	pcall(function()
		local shin = kneeJ.Parent
		local n = { rig.hip, rig.slideDrop, rig.shin, foot.Size.Y, foot.Size.Z }
		if shin and shin:IsA("BasePart") then
			table.insert(n, shin.Size.Y)
			table.insert(n, shin.Size.Z)
		end
		for _, cf in ipairs({ hipJ.C1, kneeJ.C0, kneeJ.C1, ankleJ.C0, ankleJ.C1 }) do
			table.move({ cf:GetComponents() }, 1, 12, #n + 1, n)
		end
		for i, v in ipairs(n) do
			n[i] = string.format("%.3f", v)
		end
		key = table.concat(n, " ")
	end)
	local known = if key then slidePoseCache[key] else nil
	if known then
		return known
	end
	poseStats.slideSolves += 1
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
	elseif key then
		if slidePoseCount >= 64 then
			table.clear(slidePoseCache) -- (far more builds than one server holds: start again rather than grow)
			slidePoseCount = 0
		end
		slidePoseCache[key] = pose
		slidePoseCount += 1
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

-- The bow's drawn string (item 8) ---------------------------------------------------------------------------------------

-- Back to the bow's own straight string mesh.
local function removeBowString(entry)
	local drawn = entry.bowString
	if not drawn then
		return
	end
	entry.bowString = nil
	for _, inst in ipairs(drawn.made) do
		inst:Destroy()
	end
	for _, part in ipairs(drawn.hidden) do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
end

-- The string drawn by the right hand: the world bow's string is a straight mesh, so while it is drawn it is hidden
-- (on this client) and two Beams run from the limb tips to the pulling hand. Everything made here is local.
local function showBowString(entry)
	if entry.bowString then
		return
	end
	local character = entry.character
	local model = character:FindFirstChild("EquippedModel")
	local handle = model and model:FindFirstChild("Handle")
	local top = handle and handle:FindFirstChild("StringTop")
	local bottom = handle and handle:FindFirstChild("StringBottom")
	local hand = character:FindFirstChild("RightHand")
	if not (model and handle and top and bottom and hand and top:IsA("Attachment") and bottom:IsA("Attachment") and hand:IsA("BasePart")) then
		return
	end
	local grip = hand:FindFirstChild("RightGripAttachment")
	local pull = Instance.new("Attachment")
	pull.Name = "LS_StringPull"
	pull.Position = if grip and grip:IsA("Attachment") then grip.Position else Vector3.new(0, -hand.Size.Y / 2, 0)
	pull.Parent = hand
	local drawn = { made = { pull }, hidden = {} }
	for _, tip in ipairs({ top, bottom }) do
		local beam = Instance.new("Beam")
		beam.Name = "LS_String"
		beam.Attachment0 = tip
		beam.Attachment1 = pull
		beam.Width0 = BOW.stringWidth
		beam.Width1 = BOW.stringWidth
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightInfluence = 1
		beam.Color = ColorSequence.new(BOW.stringColor)
		beam.Transparency = NumberSequence.new(0)
		beam.Parent = handle
		table.insert(drawn.made, beam)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("String") then
			d.LocalTransparencyModifier = 1
			table.insert(drawn.hidden, d)
		end
	end
	entry.bowString = drawn
end

-- A draw starts ("Draw") or ends ("Release": the arrow left, or with `cancelled` the string was let down).
local function bowEvent(entry, action: string, cancelled: boolean?)
	if not entry then
		return
	end
	local now = os.clock()
	if action == "Draw" then
		entry.bowT0 = now
		entry.bowLoosedAt = nil
	elseif action == "Release" then
		if entry.bowT0 and not cancelled then
			entry.bowLoosedAt = now
		end
		entry.bowT0 = nil
		removeBowString(entry) -- (the string is straight again at once)
	end
end

-- Roblox's default character sounds give every character a voice sound, "Died", played at zero health: muted (the
-- game has no cry of pain; see the header). The sounds are made on this client, so this is local.
local function muteDefeatSound(inst: Instance)
	if inst.Name == "Died" and inst:IsA("Sound") then
		inst.Volume = 0
	end
end

-- Entries ---------------------------------------------------------------------------------------------------------------

local function untrack(character: Model)
	local entry = entries[character]
	if not entry then
		return
	end
	entries[character] = nil
	filterDirty = true
	removeBowString(entry)
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
		bow = false, -- a bow is in hand (the character attribute EquippedItem)
		bowDrawTime = 0.9, -- that bow's draw time (seconds)
		bowT0 = nil, -- os.clock() when the draw in progress began
		bowLoosedAt = nil, -- os.clock() when the last arrow left
		bowHold = 0, -- 0..1 the bow arm's hold pose
		bowAim = 0, -- 0..1 the bow arm raised at the target
		bowArm = 0, -- 0..1 the string arm on the string
		bowPull = 0, -- 0..1 how far back the string hand is
		bowString = nil, -- the drawn string's Beams (showBowString)
		defeatAt = nil, -- os.clock() when this client saw the body fall (defeatStep)
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
	local function readHeld()
		local id = character:GetAttribute("EquippedItem")
		local def = if type(id) == "string" and id ~= "" then ItemDefs.get(id) else nil
		entry.bow = def ~= nil and def.kind == "Bow"
		if entry.bow then
			entry.bowDrawTime = math.max(tonumber(def.drawTime) or 0.9, 0.05)
		else
			entry.bowT0 = nil
			entry.bowLoosedAt = nil
			removeBowString(entry)
		end
	end
	readHeld()
	table.insert(entry.conns, character:GetAttributeChangedSignal("EquippedItem"):Connect(readHeld))
	for _, d in ipairs(character:GetDescendants()) do
		muteDefeatSound(d)
	end
	table.insert(entry.conns, character.DescendantAdded:Connect(function(d)
		muteDefeatSound(d)
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
	entry.slidePose = nil -- (about 1,900 leg solves: left until this character first slides, see poseEntry)
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

-- Melee swings (#90) ---------------------------------------------------------------------------------------------------

-- The viewmodel's pose module (ViewmodelController.Poses: pure data, the first-person swing sets), loaded on first use.
local posesModule: any = nil
local function swingPoses(): any
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
	return if posesModule then posesModule else nil
end

-- The shape that matches one first-person swing set: the set's own `tp` name when it has one, else its hand path in
-- camera space (+X right, +Y up), taken at the fist (a wrist frame's origin sits behind the hand: Poses.avatarHand).
-- W to F mostly downward: Overhead. Otherwise the cut (W to M) from right to left: Left, or DownLeft when it falls more
-- than ~10 degrees; from left to right: Right. A Stab set: a thrust, high or low by where F ends.
local function fist(frame: CFrame): Vector3
	return frame.Position + frame.LookVector * 0.2
end
local function shapeForSet(style: string, set: any): string?
	if type(set) ~= "table" then
		return nil
	end
	if type(set.tp) == "string" and SWING_SHAPES[set.tp] then
		return set.tp
	end
	local W, M, F = set.W, set.M, set.F
	if typeof(W) ~= "CFrame" or typeof(F) ~= "CFrame" then
		return nil
	end
	local whole = fist(F) - fist(W)
	if style == "Stab" then
		return if whole.Y > 0.12 then "ThrustHigh" elseif whole.Y < -0.12 then "ThrustLow" else "Thrust"
	end
	if math.abs(whole.X) < 0.6 * math.abs(whole.Y) then
		return if whole.Y < 0 then "Overhead" else "Right"
	end
	local cut = (if typeof(M) == "CFrame" then fist(M) else fist(F)) - fist(W)
	if cut.X < 0 then
		return if cut.Y < -0.18 * math.abs(cut.X) then "DownLeft" else "Left"
	end
	return "Right"
end

-- Shapes by swing set when the first-person sets can't say (also used per attacker when the server sends no set).
local DEFAULT_SHAPES: { [string]: { string } } = {
	Slash = { "DownLeft", "Right", "Left" },
	Chop = { "Overhead", "DownLeft", "Left" },
	Smash = { "Overhead", "DownLeft" },
	Stab = { "Thrust", "ThrustHigh", "ThrustLow" },
	Punch = { "Jab", "Cross" },
}

local function shapeFor(style: string, variant: number): string
	local poses = swingPoses()
	if style == "Punch" then
		-- (as in first person: odd swings jab with the left, even swings cross with the right, unless a set names its shape)
		local punch = poses and poses.PUNCH
		local set = if type(punch) == "table" and #punch > 0 then punch[(variant - 1) % #punch + 1] else nil
		if type(set) == "table" and type(set.tp) == "string" and SWING_SHAPES[set.tp] then
			return set.tp
		end
		return if variant % 2 == 1 then "Jab" else "Cross"
	end
	if poses then
		local swing = if type(poses.SWING) == "table" then poses.SWING else {}
		local sets = swing[style]
		if not (type(sets) == "table" and #sets > 0) then
			if style == "Stab" then
				local stab = poses.STAB
				sets = if type(stab) == "table" and #stab > 0 then stab else { stab }
			else
				sets = swing.Slash -- (Poses.swing falls back on the Slash sets)
			end
		end
		if type(sets) == "table" and #sets > 0 then
			local found = shapeForSet(style, sets[(variant - 1) % #sets + 1])
			if found then
				return found
			end
		end
	end
	local list = DEFAULT_SHAPES[style] or DEFAULT_SHAPES.Slash
	return list[(variant - 1) % #list + 1]
end

-- (style, weight) of a melee weapon, from CombatController (the table the first-person swings use).
local function meleeStyle(itemId: string?): (string, string)
	local combat = Controllers and Controllers.CombatController
	if combat and type(combat.meleeStyle) == "function" then
		local ok, style, weight = pcall(combat.meleeStyle, itemId)
		if ok and type(style) == "string" then
			return style, if type(weight) == "string" then weight else "Medium"
		end
	end
	return "Slash", "Medium"
end

-- A swing set from the wire: an integer 1-8, else nil.
local function validVariant(value: any): number?
	if type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= 8 then
		return value
	end
	return nil
end

local swingRng = Random.new()

-- Starts a third-person swing on a character (item 7 in the header): itemId gives the style and weight, variant (1-8)
-- the attacker's swing set.
-- (Combat v3: defined further down, used by the swings and the CombatAction handler above them)
local scaled: (v: { number }, k: number) -> { number }
local entryFor: (character: Instance?) -> any
local SKILL_BODY: { [string]: string }
local clipPlay: (model: Instance, name: string?, opts: { [string]: any }?) -> any
local clipPlayer: () -> any
local CLIP_BODY: { [string]: string }
local CLIP_SKILL: { [string]: string }
local FAMILY_CHARGE: { [string]: string }

function CharacterVisuals.playSwing(character: Model, itemId: string?, variant: number?, lead: number?, moveId: string?): boolean
	if typeof(character) ~= "Instance" or not character:IsA("Model") or not character:IsDescendantOf(workspace) then
		return false
	end
	local entry = entries[character]
	if not entry then
		if Players:GetPlayerFromCharacter(character) then
			return false -- (a player's character is tracked from CharacterAdded)
		end
		track(character, false) -- not a player's: a test rig, an NPC
		entry = entries[character]
		if not entry then
			return false
		end
	end
	local style, weight = meleeStyle(itemId)
	local v = validVariant(variant)
	-- Combat v3: the move gives the set (a chain step's own cut), its weight and its length
	local move = nil
	local kind = Moves.parse(moveId)
	if kind then
		local def = ItemDefs.get(itemId) or ItemDefs.get("fists")
		local stats = { id = itemId, damage = def.damage, windup = def.windup, cooldown = def.cooldown, staminaCost = def.staminaCost }
		local _, index = Moves.parse(moveId)
		if kind == "Heavy" then
			move = Moves.heavy(stats, itemId, 1)
		elseif kind == "Counter" then
			move = Moves.counter(stats, itemId)
		elseif kind == "Kick" then
			CharacterVisuals.playBody(character, "Kick")
			return true
		elseif kind == "Skill" then
			move = Moves.skillStrike(stats, itemId, moveId :: string)
			if move and move.style == "Kick" then
				CharacterVisuals.playBody(character, "HeadKick")
				return true
			end
		else
			move = Moves.step(stats, itemId, index)
		end
		if move and move.style and move.style ~= "Kick" then
			style = move.style
			v = move.variant
			if move.heavyHit then
				weight = "Heavy"
			end
		end
	end
	if not v then
		entry.swingCount = (entry.swingCount or 0) % 8 + 1 -- (no set from the server: alternate per attacker)
		v = entry.swingCount
	end
	local name = shapeFor(style, v)
	local shape = SWING_SHAPES[name] or SWING_SHAPES.Left
	local tweak = SWING_STYLE[style]
	local size = (SWING_SIZE[weight] or 1) * (1 + (swingRng:NextNumber() * 2 - 1) * SWING_SIZE_JITTER)
	local pitch = math.rad(SWING_ANGLE_JITTER) * (swingRng:NextNumber() * 2 - 1)
	local yaw = math.rad(SWING_ANGLE_JITTER) * (swingRng:NextNumber() * 2 - 1)
	local leftArm = shape.arm == "Left"
	local pitchAt, yawAt = if leftArm then 8 else 4, if leftArm then 9 else 5
	local function key(source: { number }, jitter: number): { number }
		local out = table.create(SWING_N, 0)
		for i = 1, SWING_N do
			out[i] = source[i] * size
		end
		out[1] *= if tweak then tweak.torso else 1
		out[pitchAt] += pitch * jitter
		out[yawAt] += yaw * jitter
		return out
	end
	local W, M, F = key(shape.W, 1), key(shape.M, 0.5), key(shape.F, 1)
	if tweak and tweak.raise then
		W[4] += math.rad(tweak.raise)
	end
	local settle = table.create(SWING_N, 0)
	for i = 1, SWING_N do
		settle[i] = F[i] * (1 - SWING_SETTLE)
	end
	local duration = math.clamp((SWING_TIME_STYLE[style] or SWING_TIME[weight] or 0.42)
		* (1 + (swingRng:NextNumber() * 2 - 1) * SWING_TIME_JITTER), 0.35, 0.5)
	if move and move.total then
		-- (the move's own length: a Twin-Bit Axe recovers for longer than a knife; a heavy's cut is bigger)
		duration = math.clamp(move.total * (1 + (swingRng:NextNumber() * 2 - 1) * SWING_TIME_JITTER), 0.35, 1.1)
		if move.heavyHit then
			W = scaled(W, 1.18)
			F = scaled(F, 1.12)
		end
	end
	-- The cut crosses when the damage lands. With `lead` seconds to the strike (the swing's start was relayed), the
	-- wind-up takes what the lead leaves before the cut and the rest of the swing keeps its length. With no lead left
	-- (announced at the strike) the swing starts already wound up and blends in over SWING_FADE.
	local uW = SWING_WINDUP[weight] or 0.24
	local cutShare, followShare, holdShare = SWING_CUT, SWING_FOLLOW, SWING_HOLD
	local startU = 0 -- the share of the swing already behind it when it starts
	local leadTime = tonumber(lead)
	if leadTime and leadTime == leadTime then
		local windup = uW * duration
		local rest = duration - windup
		if leadTime > 0.02 then
			local fitted = math.clamp(leadTime - SWING_CUT * duration, 0.04, 0.3)
			local scale = duration / (fitted + rest)
			duration = fitted + rest
			uW = fitted / duration
			cutShare, followShare, holdShare = SWING_CUT * scale, SWING_FOLLOW * scale, SWING_HOLD * scale
		else
			startU = uW
		end
	end
	if Config.IsStudio then
		local slow = tonumber(player:GetAttribute("LS_SwingSlowMo"))
		if slow and slow > 1 then
			duration *= math.min(slow, 60) -- (test hook, for captures)
		end
	end
	local now = os.clock()
	local from = nil
	if entry.swing and entry.swingOut and now - (entry.swingOutAt or -math.huge) < 0.1 then
		from = table.clone(entry.swingOut) -- (cutting into a swing: blend from where the body is)
	elseif startU > 0 then
		from = table.create(SWING_N, 0) -- (starting wound up: blend from the body as the Animator has it)
	end
	-- the Blender clip of this move, fitted to the server's strike (lead) and the move's length (total); the
	-- procedural swing stays underneath it (and is the swing when the clip player has no clip for the move)
	if moveId and not (kind == "Skill" and moveId ~= "S1") then
		local clip = if kind == "Skill" then "shortblade_skill_chained" else Moves.clipName(itemId, moveId)
		if entry.chargeTrack then
			local cp = clipPlayer()
			if cp then
				pcall(cp.stopTrack, entry.chargeTrack, 0.06)
			end
			entry.chargeTrack = nil
		end
		clipPlay(character, clip, { lead = math.max(tonumber(lead) or 0, 0), total = duration })
	end
	entry.swing = {
		name = name,
		style = style,
		variant = v,
		W = W,
		M = M,
		F = F,
		settle = settle,
		from = from,
		startU = startU,
		move = moveId,
		itemId = itemId,
		at = now, -- when it began to show here (the blend from `from` runs from this)
		t0 = now - startU * duration,
		duration = duration,
		uW = uW,
		uM = uW + cutShare,
		uF = uW + cutShare + followShare,
		uH = uW + cutShare + followShare + holdShare,
	}
	return true
end

-- Test hook: the swing a character is playing, or nil.
function CharacterVisuals._swingOf(character: Model): { [string]: any }?
	local entry = entries[character]
	local swing = entry and entry.swing
	if not swing then
		return nil
	end
	return { shape = swing.name, style = swing.style, variant = swing.variant, duration = swing.duration,
		u = (os.clock() - swing.t0) / swing.duration }
end
CharacterVisuals._swingShapes = SWING_SHAPES -- (test hook: the shapes, radians, for tuning in a playtest)

local function onCombatAction(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local action = payload.action
	-- Combat v3: what happened to a body (a player's or a dummy's: payload.target)
	if action == "React" or action == "Block" or action == "Parry" or action == "GuardBreak" then
		local target = payload.target
		if typeof(target) == "Instance" and target:IsA("Model") and (target ~= player.Character or poseAsRemote) then
			if action == "React" then
				CharacterVisuals.react(target, payload.tier, payload.from)
			elseif action == "GuardBreak" then
				CharacterVisuals.setGuard(target, false)
				if not clipPlay(target, "guard_break") then
					CharacterVisuals.react(target, "Stagger", nil)
				end
			else
				local entry = entryFor(target)
				if entry and not clipPlay(target, if action == "Parry" then "parry" else "block_hit") then
					entry.react = { t0 = os.clock(), side = if action == "Parry" then -1 else 1, amp = if action == "Parry" then 0.5 else 0.35 }
				end
			end
		end
		-- hit-stop: the two bodies of the hit hold a moment when they are near the camera
		local hold = tonumber(payload.hitStop) or (if action == "Parry" then 0.08 else 0)
		local cam = workspace.CurrentCamera
		if hold > 0 and cam then
			local range = Moves.reactions.HitStopViewRange or 30
			local function stop(model: any)
				local entry = if typeof(model) == "Instance" then entries[model] else nil
				if entry and entry.root and (entry.root.Position - cam.CFrame.Position).Magnitude <= range then
					entry.stopUntil = os.clock() + hold
					local cp = clipPlayer()
					if cp and type(cp.hitStop) == "function" and entry.clipClaimed then
						pcall(cp.hitStop, model, hold)
					end
				end
			end
			stop(target)
			local attackerId = tonumber(payload.attackerId)
			local by = if attackerId then Players:GetPlayerByUserId(attackerId) else nil
			stop(if by then by.Character else payload.attacker)
		end
		return
	end
	if action ~= "Swing" and action ~= "Draw" and action ~= "Release" and action ~= "Guard" and action ~= "Charge"
		and action ~= "Dodge" and action ~= "Skill" and action ~= "Throw" then
		return
	end
	local userId = tonumber(payload.userId)
	local attacker = if userId then Players:GetPlayerByUserId(userId) else nil
	local character = if attacker then attacker.Character else nil
	if not attacker and typeof(payload.model) == "Instance" and payload.model:IsA("Model") then
		character = payload.model -- (a dummy's swing: CombatService._npcStrike)
	elseif not attacker or (attacker == player and not poseAsRemote) then
		-- (your own swings are first person; with the test hook LS_PoseAsRemote your body shows them too)
		return
	end
	if not character then
		return
	end
	local itemId = if type(payload.itemId) == "string" then payload.itemId else nil
	if action == "Swing" then
		if Config.Combat.ThirdPersonSwings ~= false then
			-- lead: seconds until the strike (the swing's start was relayed); 0 or missing: the strike is now
			CharacterVisuals.setCharge(character, false, itemId)
			CharacterVisuals.setGuard(character, false, itemId)
			CharacterVisuals.playSwing(character, itemId, payload.variant, tonumber(payload.lead) or 0,
				if type(payload.move) == "string" then payload.move else nil)
		end
	elseif action == "Guard" then
		CharacterVisuals.setGuard(character, payload.cancelled ~= true, itemId)
	elseif action == "Charge" then
		CharacterVisuals.setCharge(character, payload.cancelled ~= true, itemId)
	elseif action == "Dodge" then
		local entry = entryFor(character)
		local dir = payload.direction
		local kind = "DodgeBack"
		if entry and entry.root and typeof(dir) == "Vector3" and dir.Magnitude > 0.1 then
			local rel = entry.root.CFrame:VectorToObjectSpace(dir)
			kind = if rel.Z < -0.5 then "DodgeRoll" elseif rel.Z > 0.5 then "DodgeBack" elseif rel.X < 0 then "DodgeLeft" else "DodgeRight"
		end
		CharacterVisuals.setGuard(character, false, itemId)
		CharacterVisuals.playBody(character, kind)
	elseif action == "Skill" then
		local skill = payload.skill
		if type(skill) == "string" and clipPlay(character, CLIP_SKILL[skill]) then
			return -- (the Blender clip plays it)
		end
		if skill == "chained_strikes" then
			-- five quick strikes that grow (Moves.skills.Weapon.ShortBlade)
			local S = Moves.skills.Weapon.ShortBlade
			local held = character:GetAttribute("EquippedItem")
			for i = 1, #S.Mults do
				task.delay(if i == 1 then 0 else S.First + (i - 1) * S.Gap - 0.04, function()
					CharacterVisuals.playSwing(character, if type(held) == "string" then held else "knife", nil, 0.04, "S" .. i)
				end)
			end
		elseif type(skill) == "string" and SKILL_BODY[skill] then
			CharacterVisuals.playBody(character, SKILL_BODY[skill])
		end
	elseif action == "Throw" then
		-- the Throwing family's Blender clip (throw_knife, throw_dagger, throw_ring, throw_hatchet, throw_spear,
		-- throw_twinaxe; Shared.FightClips): the throw was released on the server just now
		CharacterVisuals.setGuard(character, false, itemId)
		CharacterVisuals.playThrow(character, itemId)
	else
		bowEvent(entries[character], action, payload.cancelled == true) -- (item 8: another player's draw)
		if action == "Release" and payload.cancelled ~= true then
			clipPlay(character, "bow_release") -- the bow's follow-through after the arrow leaves (upper body)
		end
	end
end

-- A throw's body (Combat_v3 7.2 Throwing): the Blender clip for the thrown item, from its release.
function CharacterVisuals.playThrow(character: Model, itemId: string?): boolean
	local okFc, FightClips = pcall(require, ReplicatedStorage.Shared:FindFirstChild("FightClips") :: ModuleScript)
	local name = if okFc and type(itemId) == "string" then FightClips.forMove(itemId, "Throw") else nil
	-- (the release is the server's moment: start the clip at its release frame so the arm is already going through)
	return clipPlay(character, name, { lead = 0 }) ~= nil
end

-- Your own draws (the server tells only the others): your body takes the same pose, for anyone watching it here.
local function onOwnCombat(name: string, data: any)
	if name == "Swing" and type(data) == "table" and data.style == "Kick" and localEntry and localEntry.character then
		CharacterVisuals.playBody(localEntry.character, if data.moveId == "HK" then "HeadKick" else "Kick")
		return
	end
	if name == "DrawStart" then
		bowEvent(localEntry, "Draw")
	elseif name == "Release" then
		bowEvent(localEntry, "Release")
	elseif name == "DrawCancel" then
		bowEvent(localEntry, "Release", true)
	end
end

-- Test hooks (item 8).
CharacterVisuals._bow = BOW
function CharacterVisuals._bowEvent(character: Model, action: string, cancelled: boolean?)
	bowEvent(entries[character], action, cancelled)
end
function CharacterVisuals._bowOf(character: Model): { [string]: any }?
	local entry = entries[character]
	if not entry then
		return nil
	end
	return { bow = entry.bow, hold = entry.bowHold, aim = entry.bowAim, arm = entry.bowArm, pull = entry.bowPull,
		drawing = entry.bowT0 ~= nil, string = entry.bowString ~= nil, defeatAt = entry.defeatAt }
end

-- The swing's timeline (shares of its length): wind up to W, accelerate to the cut (M), slow into the follow-through
-- (F), hold it while it settles back a little, recover.
local swingArm = table.create(SWING_N, 0)
local swingBody = table.create(SWING_N, 0)

-- Combat v3: a key curve. ts: key times (increasing), ps: key values (n numbers each); a cubic Hermite through the keys
-- with each key's tangent taken from its neighbours (Catmull-Rom on uneven times), flat at both ends, so the motion
-- has no corners: it eases out of a key and into the next at the speed the keys around it ask for.
local function sampleKeys(ts: { number }, ps: { { number } }, n: number, u: number, out: { number })
	local m = #ts
	if u <= ts[1] then
		table.move(ps[1], 1, n, 1, out)
		return
	elseif u >= ts[m] then
		table.move(ps[m], 1, n, 1, out)
		return
	end
	local k = 1
	while k < m - 1 and u > ts[k + 1] do
		k += 1
	end
	local t0, t1 = ts[k], ts[k + 1]
	local h = math.max(t1 - t0, 1e-4)
	local x = (u - t0) / h
	local x2, x3 = x * x, x * x * x
	local h00, h10, h01, h11 = 2 * x3 - 3 * x2 + 1, x3 - 2 * x2 + x, -2 * x3 + 3 * x2, x3 - x2
	local p0, p1, pa, pb = ps[k], ps[k + 1], ps[k - 1], ps[k + 2]
	local ta, tb = ts[k - 1], ts[k + 2]
	for i = 1, n do
		local m0 = if pa then (p1[i] - pa[i]) / (t1 - ta) else 0
		local m1 = if pb then (pb[i] - p0[i]) / (tb - t0) else 0
		out[i] = h00 * p0[i] + h10 * h * m0 + h01 * p1[i] + h11 * h * m1
	end
end

function scaled(v: { number }, k: number): { number }
	local out = table.create(#v, 0)
	for i = 1, #v do
		out[i] = v[i] * k
	end
	return out
end

local function mix(a: { number }, b: { number }, k: number): { number }
	local out = table.create(#a, 0)
	for i = 1, #a do
		out[i] = a[i] + (b[i] - a[i]) * k
	end
	return out
end

-- The nine keys of a swing (see the header) on its own timeline.
local function swingKeys(swing: any)
	local zero = table.create(SWING_N, 0)
	local W, M, F = swing.W, swing.M, swing.F
	local uW, uM, uF, uH = swing.uW, swing.uM, swing.uF, swing.uH
	swing.ts = { 0, uW * 0.55, uW, (uW + uM) * 0.5, uM, uF, uH, uH + (1 - uH) * 0.45, 1 }
	swing.ps = { swing.from or zero, scaled(W, 0.72), scaled(W, 1.06), mix(W, M, 0.55), M, scaled(F, 1.1), scaled(F, 0.97),
		scaled(F, 0.4), zero }
	if swing.startU and swing.startU > 0 then
		-- (announced at the strike: it starts wound up, from where the body was)
		swing.ts = { 0, uW, (uW + uM) * 0.5, uM, uF, uH, uH + (1 - uH) * 0.45, 1 }
		swing.ps = { swing.from or zero, scaled(W, 1.02), mix(W, M, 0.55), M, scaled(F, 1.1), scaled(F, 0.97), scaled(F, 0.4), zero }
	end
end

local function sampleSwing(swing: any, u: number, out: { number })
	if not swing.ts then
		swingKeys(swing)
	end
	sampleKeys(swing.ts, swing.ps, SWING_N, u, out)
end

-- This frame's swing angles for an entry (nil without one; a finished swing is dropped here). The torso runs
-- SWING_LEAD ahead of the arms; a swing that cut into another starts from the angles it took over.
local function swingPose(entry, now: number): { number }?
	local swing = entry.swing
	if not swing then
		return nil
	end
	-- hit-stop: the body holds its swing for a moment on contact (only its clock slows; the server never pauses)
	local last = swing.lastNow or now
	if now < (entry.stopUntil or -math.huge) then
		swing.t0 += (now - last) * 0.88
	end
	swing.lastNow = now
	local u = (now - swing.t0) / swing.duration
	if u >= 1 then
		entry.swing = nil
		return nil
	end
	u = math.max(u, 0)
	sampleSwing(swing, u, swingArm)
	sampleSwing(swing, math.min(u + SWING_LEAD, 0.999), swingBody)
	swingArm[1], swingArm[2], swingArm[3] = swingBody[1], swingBody[2], swingBody[3]
	local from = swing.from
	local since = now - (swing.at or swing.t0)
	if from and since < SWING_FADE then
		local k = smooth01(since / SWING_FADE)
		for i = 1, SWING_N do
			swingArm[i] = from[i] + (swingArm[i] - from[i]) * k
		end
	end
	local out = entry.swingOut
	if not out then
		out = table.create(SWING_N, 0)
		entry.swingOut = out
	end
	table.move(swingArm, 1, SWING_N, 1, out)
	entry.swingOutAt = now
	return out
end

-- Combat v3: guard, charge, reactions and the full-body layer -------------------------------------------------------

local function deg(v: { number }): { number }
	local out = table.create(#v, 0)
	for i = 1, #v do
		out[i] = math.rad(v[i])
	end
	return out
end
-- Held poses over the Animator (the 11 swing angles, degrees): the guard per family, the fists' guard.
local GUARD_POSE = {
	Blade = deg({ 2, -12, 0, 70, -38, 12, 72, 42, -22, -10, 82 }),
	Spear = deg({ 4, -18, 0, 25, -12, 10, 62, 48, -30, -12, 40 }),
	Fists = deg({ 0, -6, 0, 62, 8, 4, 118, 64, -8, -4, 116 }),
}
local GUARD_FAMILY = { Fists = "Fists", Spear = "Spear" }

-- The full-body layer: keys { u (share of the move), body = { rootPitch (+ back), rootYaw, rootRoll, drop (studs),
-- hipL, hipR (+ thigh forward), kneeL, kneeR (- bent) }, upper = the 11 swing angles? } in degrees; duration in seconds;
-- legs = foot IK lets go while it plays.
local BODY_N = 8
local function bk(u: number, body: { number }, upper: { number }?)
	return { u = u, body = body, upper = upper }
end
local Z8 = { 0, 0, 0, 0, 0, 0, 0, 0 }
local ARMS_OUT = { 0, 0, 0, 25, 0, 28, 30, 25, 0, -28, 30 }
local BODY_MOVES: { [string]: { duration: number, legs: boolean, keys: { any } } } = {
	Kick = { duration = 0.59, legs = true, keys = { -- a front kick: chamber, snap out at 0.16 s, recoil, set down
		bk(0, Z8), bk(0.15, { 6, 0, 0, 0.05, -4, 62, -6, -95 }, ARMS_OUT), bk(0.27, { 14, 0, 0, 0.1, -6, 88, -10, -8 }, ARMS_OUT),
		bk(0.45, { 8, 0, 0, 0.05, -4, 60, -6, -80 }, ARMS_OUT), bk(1, Z8) } },
	HeadKick = { duration = 0.7, legs = true, keys = { -- a high round kick, the hips turning over
		bk(0, Z8), bk(0.18, { 10, -20, 8, 0.1, -6, 70, -10, -100 }, ARMS_OUT), bk(0.32, { 22, -45, 20, 0.15, -8, 105, -12, -10 }, ARMS_OUT),
		bk(0.55, { 12, -25, 10, 0.1, -6, 70, -10, -90 }, ARMS_OUT), bk(1, Z8) } },
	DodgeBack = { duration = 0.55, legs = true, keys = {
		bk(0, Z8), bk(0.25, { -6, 0, 0, 0.35, 30, 18, -50, -30 }), bk(0.55, { 10, 0, 0, 0.2, -10, 20, -20, -40 }), bk(1, Z8) } },
	DodgeLeft = { duration = 0.55, legs = true, keys = {
		bk(0, Z8), bk(0.25, { -4, 10, -14, 0.4, 25, 20, -55, -40 }), bk(0.6, { 0, 6, 10, 0.25, 10, 15, -30, -30 }), bk(1, Z8) } },
	DodgeRight = { duration = 0.55, legs = true, keys = {
		bk(0, Z8), bk(0.25, { -4, -10, 14, 0.4, 20, 25, -40, -55 }), bk(0.6, { 0, -6, -10, 0.25, 15, 10, -30, -30 }), bk(1, Z8) } },
	DodgeRoll = { duration = 0.6, legs = true, keys = { -- a forward roll: tuck and go over
		bk(0, Z8), bk(0.2, { -30, 0, 0, 0.8, 70, 70, -110, -110 }), bk(0.45, { -200, 0, 0, 1.6, 100, 100, -130, -130 }),
		bk(0.7, { -330, 0, 0, 0.9, 80, 80, -120, -120 }), bk(0.85, { -360, 0, 0, 0.3, 30, 30, -50, -50 }), bk(1, { -360, 0, 0, 0, 0, 0, 0, 0 }) } },
	Stagger = { duration = 0.6, legs = true, keys = { -- the torso turns into the blow, one foot steps back
		bk(0, Z8), bk(0.18, { 10, 6, 4, 0.1, 6, -22, -10, -28 }, { 12, 8, 4, 18, 0, 10, 20, 18, 0, -10, 20 }),
		bk(0.5, { 5, 3, 2, 0.05, 2, -10, -5, -14 }, { 6, 4, 2, 8, 0, 5, 10, 8, 0, -5, 10 }), bk(1, Z8) } },
	HeavyStagger = { duration = 0.9, legs = true, keys = {
		bk(0, Z8), bk(0.15, { 18, 14, 6, 0.2, 10, -34, -14, -40 }, { 20, 14, 6, 30, 0, 18, 30, 30, 0, -18, 30 }),
		bk(0.45, { 10, 8, 3, 0.15, 6, -20, -10, -26 }, { 10, 8, 3, 15, 0, 9, 15, 15, 0, -9, 15 }), bk(1, Z8) } },
	Knockdown = { duration = 1.6, legs = true, keys = { -- down for a second, up in 0.6
		bk(0, Z8), bk(0.12, { 40, 0, 0, 0.8, 30, 40, -20, -30 }), bk(0.25, { 82, 0, 0, 2.3, 40, 50, -10, -20 }),
		bk(0.62, { 80, 0, 0, 2.3, 40, 50, -15, -20 }), bk(0.8, { 30, 0, 0, 1.2, 80, 40, -120, -60 }), bk(1, Z8) } },
	Whirl = { duration = 1.15, legs = true, keys = { -- pull across the body (readable), one full turn, settle
		bk(0, Z8, nil), bk(0.3, { -6, 40, 0, 0.3, 20, 15, -30, -25 }, { 4, 30, 0, 70, 55, 10, 30, 40, 0, -10, 40 }),
		bk(0.44, { -8, -150, 0, 0.35, 20, 15, -30, -25 }, { 0, 0, 0, 80, -20, 30, 10, 40, 0, -10, 30 }),
		bk(0.57, { -6, -320, 0, 0.3, 15, 15, -25, -25 }, { 0, -20, 0, 70, -60, 20, 15, 30, 0, -10, 30 }),
		bk(1, { 0, -360, 0, 0, 0, 0, 0, 0 }) } },
	VaultKick = { duration = 1.25, legs = true, keys = { -- plant the spear, vault, both feet out at 0.75 s, land
		bk(0, Z8), bk(0.22, { -18, 0, 0, 0.5, 30, 30, -60, -60 }, { 0, 0, 0, 60, -10, 10, 20, 60, 10, -10, 20 }),
		bk(0.45, { 20, 0, 0, -0.6, 70, 70, -90, -90 }, { 0, 0, 0, 30, -10, 10, 10, 30, 10, -10, 10 }),
		bk(0.6, { 30, 0, 0, -0.8, 85, 85, -5, -5 }, ARMS_OUT), bk(0.8, { 8, 0, 0, 0.3, 30, 30, -50, -50 }), bk(1, Z8) } },
	RunningCut = { duration = 0.9, legs = true, keys = { -- a low crouch, the dash with the blade out, the cut
		bk(0, Z8), bk(0.22, { -16, 10, 0, 0.45, 40, 20, -70, -40 }, { -4, 20, 0, 30, -40, 15, 50, 20, 0, -10, 30 }),
		bk(0.4, { -22, 0, 0, 0.3, 50, -10, -40, -20 }, { -6, 0, 0, 20, 30, 10, 20, 20, 0, -10, 30 }),
		bk(0.6, { -14, -20, 0, 0.25, 30, 0, -40, -30 }, { -4, -30, 0, 10, 70, -6, 15, 15, 0, -10, 30 }), bk(1, Z8) } },
	Breath = { duration = 0.5, legs = false, keys = { -- Concentration, Second Wind, Brace: a slow breath, a lower stance
		bk(0, Z8), bk(0.45, { 3, 0, 0, 0.12, 0, 0, 0, 0 }, { 4, 0, 0, 10, 0, 4, 20, 10, 0, -4, 20 }), bk(1, Z8) } },
}
CharacterVisuals._bodyMoves = BODY_MOVES

-- (converted to radians once: the drop stays in studs)
for _, move in pairs(BODY_MOVES) do
	local ts, bodies, uppers = {}, {}, {}
	for _, key in ipairs(move.keys) do
		table.insert(ts, key.u)
		local b = table.create(BODY_N, 0)
		for i = 1, BODY_N do
			b[i] = if i == 4 then key.body[i] else math.rad(key.body[i])
		end
		table.insert(bodies, b)
		table.insert(uppers, if key.upper then deg(key.upper) else table.create(SWING_N, 0))
	end
	(move :: any).ts, (move :: any).bodies, (move :: any).uppers = ts, bodies, uppers
end

SKILL_BODY = { whirl = "Whirl", vault_kick = "VaultKick", running_cut = "RunningCut", head_kick = "HeadKick",
	concentration = "Breath", second_wind = "Breath", brace = "Breath" }

function entryFor(character: Instance?): any
	if typeof(character) ~= "Instance" or not character:IsA("Model") or not character:IsDescendantOf(workspace) then
		return nil
	end
	local entry = entries[character]
	if not entry and not Players:GetPlayerFromCharacter(character) then
		track(character, false) -- (a dummy, a test rig)
		entry = entries[character]
	end
	return entry
end

function CharacterVisuals.playBody(character: Model, kind: string): boolean
	local entry = entryFor(character)
	local move = BODY_MOVES[kind]
	if not entry or not move then
		return false
	end
	if clipPlay(character, CLIP_BODY[kind]) then
		if kind == "Knockdown" then
			task.delay(1.0, function()
				clipPlay(character, "getup")
			end)
		end
		return true -- (the Blender clip plays it)
	end
	local slow = if Config.IsStudio then tonumber(player:GetAttribute("LS_SwingSlowMo")) else nil
	entry.body = { kind = kind, t0 = os.clock(), duration = move.duration * (if slow and slow > 1 then math.min(slow, 60) else 1) }
	return true
end

-- An upper-body reaction (additive): rank 1 a flinch, 2+ with a full-body stagger too; `from`: where the blow came from.
function CharacterVisuals.react(character: Model, tier: string?, from: Vector3?): boolean
	local entry = entryFor(character)
	if not entry or not entry.root then
		return false
	end
	local rank = (Moves.TIERS[tier or ""] or Moves.TIERS.Flinch).rank
	local side = 1
	if typeof(from) == "Vector3" then
		local rel = entry.root.CFrame:PointToObjectSpace(from)
		side = if rel.X >= 0 then 1 else -1
	end
	if rank == 1 then
		local dir = "F"
		if typeof(from) == "Vector3" then
			local rel = entry.root.CFrame:PointToObjectSpace(from)
			dir = if math.abs(rel.X) > math.abs(rel.Z) then (if rel.X > 0 then "R" else "L") elseif rel.Z > 0 then "B" else "F"
		end
		if clipPlay(character, "react_light_" .. dir) then
			return true -- (additive, over whatever the body does)
		end
	end
	entry.react = { t0 = os.clock(), side = side, amp = 0.6 + 0.4 * rank }
	if rank == 2 then
		CharacterVisuals.playBody(character, "Stagger")
	elseif rank == 3 then
		CharacterVisuals.playBody(character, "HeavyStagger")
	elseif rank >= 4 then
		CharacterVisuals.playBody(character, "Knockdown")
	end
	return true
end

function CharacterVisuals.setGuard(character: Model, on: boolean, itemId: string?)
	local entry = entryFor(character)
	if entry then
		local was = entry.guardOn == true
		entry.guardOn = on
		entry.guardFamily = GUARD_FAMILY[Moves.family(itemId)] or "Blade"
		local cp = clipPlayer()
		if cp and on and not was then
			clipPlay(character, "guard_in")
			entry.guardTrack = clipPlay(character, "guard_hold", { loop = true, blendIn = 0.12 })
		elseif cp and not on and was then
			if entry.guardTrack then
				pcall(cp.stopTrack, entry.guardTrack, 0.12)
				entry.guardTrack = nil
				entry.clipUntil = os.clock() + 0.6
			end
		end
	end
end

function CharacterVisuals.setCharge(character: Model, on: boolean, itemId: string?)
	local entry = entryFor(character)
	if entry then
		entry.chargeOn = on
		entry.chargeItem = itemId
		entry.chargeAt = os.clock()
		local cp = clipPlayer()
		if cp and on then
			entry.chargeTrack = clipPlay(character, FAMILY_CHARGE[Moves.family(itemId)], { loop = true })
		elseif cp and entry.chargeTrack then
			pcall(cp.stopTrack, entry.chargeTrack, 0.1)
			entry.chargeTrack = nil
			entry.clipUntil = os.clock() + 0.5
		end
	end
end

-- The full-body sample of an entry now: (body 8 values, upper 11 values, legs) or nil.
local bodyOut = table.create(BODY_N, 0)
local bodyUpper = table.create(SWING_N, 0)
local function bodyPose(entry, now: number): ({ number }?, { number }?, boolean)
	local b = entry.body
	if not b then
		return nil, nil, false
	end
	local move = BODY_MOVES[b.kind] :: any
	if now < (entry.stopUntil or -math.huge) then
		b.t0 += (now - (b.lastNow or now)) * 0.88
	end
	b.lastNow = now
	local u = (now - b.t0) / b.duration
	if not move or u >= 1 then
		entry.body = nil
		return nil, nil, false
	end
	sampleKeys(move.ts, move.bodies, BODY_N, math.max(u, 0), bodyOut)
	sampleKeys(move.ts, move.uppers, SWING_N, math.max(u, 0), bodyUpper)
	return bodyOut, bodyUpper, move.legs
end

-- Guard, charge and reaction angles added to the swing layer (nil when none of them shows).
local fxOut = table.create(SWING_N, 0)
local function combatLayer(entry, dt: number, now: number, swing: { number }?, upper: { number }?): { number }?
	entry.guardW = (entry.guardW or 0) + ((if entry.guardOn and not entry.swing then 1 else 0) - (entry.guardW or 0))
		* expAlpha(if entry.guardOn then 22 else 14, dt)
	entry.chargeW = (entry.chargeW or 0) + ((if entry.chargeOn and not entry.swing then 1 else 0) - (entry.chargeW or 0))
		* expAlpha(if entry.chargeOn then 12 else 20, dt)
	local react = entry.react
	local r = 0
	if react then
		local since = now - react.t0
		-- the owner's numbers: 0.08 s in, 0.25 s out
		if since < 0.08 then
			r = smooth01(since / 0.08)
		elseif since < 0.33 then
			r = 1 - smooth01((since - 0.08) / 0.25)
		else
			entry.react = nil
		end
	end
	local g, c = entry.guardW, entry.chargeW
	if g < 0.002 and c < 0.002 and r < 0.002 and not swing and not upper then
		return nil
	end
	for i = 1, SWING_N do
		fxOut[i] = (if swing then swing[i] else 0) + (if upper then upper[i] else 0)
	end
	if g > 0.002 then
		local pose = GUARD_POSE[entry.guardFamily or "Blade"] or GUARD_POSE.Blade
		for i = 1, SWING_N do
			fxOut[i] += pose[i] * g
		end
	end
	if c > 0.002 then
		-- the heavy's hold: its cut's wind-up, coiled further (the others read it coming)
		local style = meleeStyle(entry.chargeItem)
		local shape = SWING_SHAPES[shapeFor(style, 1)] or SWING_SHAPES.Left
		local tremble = math.clamp((now - (entry.chargeAt or now)) / 0.5, 0, 1)
		for i = 1, SWING_N do
			fxOut[i] += shape.W[i] * 1.2 * c
		end
		fxOut[2] += math.rad(-8) * c * tremble
		fxOut[4] += math.rad(1.5) * math.sin(now * 40) * tremble * c
	end
	if r > 0.002 then
		local a = react.amp * r
		fxOut[1] += math.rad(12) * a
		fxOut[2] += math.rad(10) * react.side * a
		fxOut[3] += math.rad(6) * react.side * a
		fxOut[4] += math.rad(10) * a
		fxOut[8] += math.rad(10) * a
	end
	return fxOut
end

-- The clip player (Combat_v3 7.1, Controllers.ClipPlayer: the Blender clips in Shared.FightClips). Hooked: each
-- character that plays a clip is claimed once, and after this pass has posed it the clip's joints are blended over
-- it (ClipPlayer.sample: the clip's Transform by its weight, additive reactions multiplied on), written through the
-- same bookkeeping as every pose here so nothing accumulates. A move without a clip keeps the procedural pose.
function clipPlayer(): any
	local registry = Controllers
	local cp = registry and registry.ClipPlayer
	return if cp and type(cp.play) == "function" and type(cp.sample) == "function" and type(cp.has) == "function" then cp else nil
end

function clipPlay(model: Instance, name: string?, opts: { [string]: any }?): any
	local cp = clipPlayer()
	if not cp or not name or not (typeof(model) == "Instance" and model:IsA("Model")) then
		return nil
	end
	local okHas, has = pcall(cp.has, name)
	if not okHas or not has then
		return nil
	end
	local entry = entryFor(model)
	if not entry then
		return nil
	end
	if not entry.clipClaimed then
		entry.clipClaimed = true
		pcall(cp.claim, model, true)
	end
	local ok, track = pcall(cp.play, model, name, opts)
	if not ok or not track then
		return nil
	end
	local info = if type(cp.info) == "function" then cp.info(name) else nil
	local length = if info and type(info.len) == "number" then info.len else 1
	local loop = (opts and opts.loop) or (info and info.loop)
	entry.clipUntil = math.max(entry.clipUntil or 0, if loop then math.huge else os.clock() + length * 2 + 0.4)
	return track
end

CLIP_BODY = {
	Kick = "kick", HeadKick = "fists_skill_head_kick", DodgeBack = "dodge_back", DodgeLeft = "dodge_left",
	DodgeRight = "dodge_right", DodgeRoll = "dodge_roll", Stagger = "stagger_F", HeavyStagger = "heavy_stagger_F",
	Knockdown = "knockdown", Whirl = "axe_skill_whirl", VaultKick = "spear_skill_vault_kick", RunningCut = "sword_skill_running_cut",
}
CLIP_SKILL = {
	whirl = "axe_skill_whirl", vault_kick = "spear_skill_vault_kick", running_cut = "sword_skill_running_cut",
	head_kick = "fists_skill_head_kick", chained_strikes = "shortblade_skill_chained", concentration = "skill_concentration",
	second_wind = "skill_second_wind", brace = "skill_brace",
}
FAMILY_CHARGE = { Fists = "fists_heavy_charge", ShortBlade = "shortblade_heavy_charge", Sword = "sword_heavy_charge",
	Axe = "axe_heavy_charge", Spear = "spear_heavy_charge" }

local clipOut: { [string]: CFrame } = {}
local clipW: { [string]: number } = {}
local clipAdd: { [string]: CFrame } = {}
local function applyClips(entry, now: number)
	local cp = clipPlayer()
	if not cp or not entry.clipClaimed or not (entry.clipUntil and now < entry.clipUntil) then
		return
	end
	table.clear(clipOut)
	table.clear(clipW)
	table.clear(clipAdd)
	local ok, any = pcall(cp.sample, entry.character, now, clipOut, clipW, clipAdd)
	if not ok or not any then
		return
	end
	local joints = entry.clipJoints
	if not joints then
		joints = {}
		for _, d in ipairs(entry.character:GetDescendants()) do
			if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
				if joints[d.Name] == nil or d:IsA("AnimationConstraint") then
					joints[d.Name] = d
				end
			end
		end
		entry.clipJoints = joints
	end
	local function put(joint: any, final: CFrame)
		local cur = joint.Transform
		-- the base for the bookkeeping: what the Animator gave this frame (ours if we wrote this joint just now)
		local base = if entry.written[joint] ~= nil and entry.written[joint] == cur then (entry.bases[joint] or cur) else cur
		joint.Transform = final -- (as writeJoint, below)
		entry.written[joint] = final
		entry.bases[joint] = base
	end
	for name, cf in pairs(clipOut) do
		local joint = joints[name]
		if joint and joint.Parent then
			put(joint, joint.Transform:Lerp(cf, math.clamp(clipW[name] or 1, 0, 1)))
		end
	end
	for name, add in pairs(clipAdd) do
		local joint = joints[name]
		if joint and joint.Parent then
			put(joint, add * joint.Transform)
		end
	end
	entry.posed = true
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

-- Two-bone arm solve (the bow's string arm). Given the upper torso's world frame and a starting pose with the elbow
-- bent (shoulderT, elbowT: absolute joint transforms), returns the shoulder and elbow transforms that put the wrist on
-- `target` with the elbow pointing along `pole` (world). wristC0: the wrist's pivot in the lower arm's frame.
local function solveArm(upperCF: CFrame, shoulderJ: any, elbowJ: any, wristC0: CFrame, shoulderT: CFrame, elbowT: CFrame,
	target: Vector3, pole: Vector3): (CFrame, CFrame)
	local shoulderFrame = upperCF * shoulderJ.C0
	local upperArm = shoulderFrame * shoulderT * shoulderJ.C1:Inverse()
	local elbowFrame = upperArm * elbowJ.C0
	local lowerArm = elbowFrame * elbowT * elbowJ.C1:Inverse()
	local S = shoulderFrame.Position
	local E = elbowFrame.Position
	local W = (lowerArm * wristC0).Position
	local L1 = (E - S).Magnitude
	local L2 = (W - E).Magnitude
	if L1 < 1e-3 or L2 < 1e-3 then
		return shoulderT, elbowT
	end
	local d0 = math.clamp((W - S).Magnitude, math.abs(L1 - L2) + 1e-3, L1 + L2)
	local d1 = math.clamp((target - S).Magnitude, math.abs(L1 - L2) + 0.05, L1 + L2 - 0.005)
	local denom = 2 * L1 * L2
	local inner0 = math.acos(math.clamp((L1 * L1 + L2 * L2 - d0 * d0) / denom, -1, 1))
	local inner1 = math.acos(math.clamp((L1 * L1 + L2 * L2 - d1 * d1) / denom, -1, 1))
	-- elbow flexion is a positive rotation about the hinge (X) axis
	local elbowFinal = CFrame.Angles(inner0 - inner1, 0, 0) * elbowT
	local W2 = (elbowFrame * elbowFinal * elbowJ.C1:Inverse() * wristC0).Position
	local from, to = W2 - S, target - S
	if from.Magnitude < 1e-4 or to.Magnitude < 1e-4 then
		return shoulderT, elbowFinal
	end
	local axis = to.Unit
	local world = rotationBetween(from.Unit, axis)
	-- swivel about the shoulder-to-wrist line until the elbow points along the pole
	local elbowOut = world * (E - S)
	elbowOut -= axis * elbowOut:Dot(axis)
	local poleOut = pole - axis * pole:Dot(axis)
	if elbowOut.Magnitude > 1e-3 and poleOut.Magnitude > 1e-3 then
		local eu, pu = elbowOut.Unit, poleOut.Unit
		world = CFrame.fromAxisAngle(axis, math.atan2(axis:Dot(eu:Cross(pu)), eu:Dot(pu))) * world
	end
	local shoulderR = shoulderFrame.Rotation:Inverse() * world * shoulderFrame.Rotation
	return shoulderR * shoulderT, elbowFinal
end

-- The wrist's pivot in the right lower arm's frame (not one of the rig's posed joints), found once per rig.
local function stringWrist(entry): CFrame
	local found = entry.bowWristC0
	if found then
		return found
	end
	local hand = entry.character:FindFirstChild("RightHand")
	local wrist = hand and hand:FindFirstChild("RightWrist")
	local c0 = CFrame.new(0, -0.55, 0)
	if wrist and (wrist:IsA("Motor6D") or wrist:IsA("AnimationConstraint")) then
		c0 = (wrist :: any).C0
	end
	entry.bowWristC0 = c0
	return c0
end

-- Where the bow's string rests (world): the held bow's Nock attachment, as the last frame left it.
local function bowNock(entry): Vector3?
	local nock = entry.bowNock
	if not (nock and nock.Parent and nock:IsDescendantOf(entry.character)) then
		local model = entry.character:FindFirstChild("EquippedModel")
		local handle = model and model:FindFirstChild("Handle")
		local found = handle and handle:FindFirstChild("Nock")
		nock = if found and found:IsA("Attachment") then found else nil
		entry.bowNock = nock
	end
	return if nock then nock.WorldPosition else nil
end

-- This frame's bow weights for an entry (item 8): returns the hold weight. `allow`: 0 while sliding or climbing.
local function bowWeights(entry, dt: number, allow: number): number
	local now = os.clock()
	if entry.bowT0 and (not entry.bow or now - entry.bowT0 > BOW.limit) then
		entry.bowT0 = nil -- (the bow left the hand, or the draw's end never arrived: let down)
		removeBowString(entry)
	end
	local drawing = entry.bowT0 ~= nil
	entry.bowHold += ((if entry.bow then allow else 0) - entry.bowHold) * expAlpha(10, dt)
	local loosed = entry.bow and entry.bowLoosedAt ~= nil and now - entry.bowLoosedAt < BOW.follow
	local aim = if drawing or loosed then 1 else 0
	entry.bowAim += (aim - entry.bowAim) * expAlpha(if aim > entry.bowAim then 12 else 6, dt)
	if drawing then
		entry.bowPull = smooth01((now - entry.bowT0) / entry.bowDrawTime)
		entry.bowArm += (1 - entry.bowArm) * expAlpha(16, dt)
	else
		-- the arrow left: the hand stays at the cheek and the arm lets go of the pose; let down: it rides the string forward
		if not loosed then
			entry.bowPull += (0 - entry.bowPull) * expAlpha(9, dt)
		end
		entry.bowArm += (0 - entry.bowArm) * expAlpha(if loosed then 7 else 5, dt)
	end
	return entry.bowHold
end

-- Per-frame scratch tables (reused)
local B: { [string]: CFrame } = {}
local P: { [string]: CFrame } = {}
local OVER: { [string]: CFrame } = {} -- absolute arm poses that replace the Animator's (the bow), with their weights
local OVER_W: { [string]: number } = {}

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
	-- how much of the pose this character gets this frame (rankEntries): 2 = everything, 1 = no foot IK, 0 = stances
	-- and swings only
	local lod = if entry.isLocal then 2 else (entry.lod or 0)
	local distance = (root.Position - camPos).Magnitude
	if not entry.isLocal and distance > LOD.poseRange then
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
	if lod == 0 and not entry.posed and entry.swing == nil and c < 0.002 and s < 0.002 and k < 0.002 and not entry.bow
		and entry.bowHold < 0.002 then
		return -- far, unseen or beyond the crowd cap, and neither in a stance, swinging nor holding a bow: the Animator's pose
	end

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
	-- Combat v3: the full-body layer (a kick, a dodge, a stagger, a skill) owns the legs while it plays
	local bodyB, bodyU, bodyLegs = bodyPose(entry, os.clock())
	local doIK = entry.legs ~= nil and lod >= 2 and distance <= LOD.ikRange and not bodyLegs
	if doIK then
		ikCount += 1
	end
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
	if lod < 1 then
		twistTarget = 0
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
	if lod < 1 then
		leanXTarget, leanZTarget = 0, 0
	end
	entry.leanX += (leanXTarget - entry.leanX) * expAlpha(7, dt)
	entry.leanZ += (leanZTarget - entry.leanZ) * expAlpha(7, dt)
	local leanX, leanZ = entry.leanX, entry.leanZ

	-- Melee swing (#90): this frame's joint angles, or nil (a finished swing is dropped here)
	local swingAngles = swingPose(entry, os.clock())
	-- Combat v3: the guard, the heavy's hold and the reactions over it (and the full-body layer's arms)
	swingAngles = combatLayer(entry, dt, os.clock(), swingAngles, bodyU)
	-- The bow (item 8): how much of the hold pose this frame (the draw's own weights are on the entry)
	local bow = bowWeights(entry, dt, 1 - math.max(s, k))

	local trivial = c < 0.002 and s < 0.002 and k < 0.002 and math.abs(twist) < 0.004 and math.abs(leanX) < 0.002
		and math.abs(leanZ) < 0.002 and land < 0.002 and w < 0.002 and entry.air < 0.002 and swingAngles == nil
		and bow < 0.002 and bodyB == nil and not (entry.clipUntil and os.clock() < entry.clipUntil)
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
	if not sp then
		if s > 0.002 then
			sp = solveSlidePose(rig) -- (this rig's own angles, the first time it slides)
			entry.slidePose = sp
		else
			sp = DEFAULT_SLIDE_POSE -- (every use below is times s)
		end
	end
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
	if bodyB then
		rootStance = rootStance * CFrame.Angles(0, bodyB[2], 0) * CFrame.Angles(bodyB[1], 0, bodyB[3])
	end
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
	if bodyB then
		P.LeftHip = CFrame.Angles(bodyB[5], 0, 0) * P.LeftHip
		P.RightHip = CFrame.Angles(bodyB[6], 0, 0) * P.RightHip
		P.LeftKnee = CFrame.Angles(bodyB[7], 0, 0) * P.LeftKnee
		P.RightKnee = CFrame.Angles(bodyB[8], 0, 0) * P.RightKnee
	end
	if swingAngles then
		-- the swing over the stance pose: the torso turns into it, the neck keeps the head on the target
		local a = swingAngles
		P.Waist = CFrame.Angles(0, a[2], 0) * CFrame.Angles(a[1], 0, a[3]) * P.Waist
		P.Neck = CFrame.Angles(0, -0.75 * a[2], 0) * CFrame.Angles(-0.6 * a[1], 0, -0.5 * a[3]) * P.Neck
		P.RightShoulder = CFrame.Angles(0, a[5], 0) * CFrame.Angles(a[4], 0, a[6]) * P.RightShoulder
		P.RightElbow = CFrame.Angles(a[7], 0, 0) * P.RightElbow
		P.LeftShoulder = CFrame.Angles(0, a[9], 0) * CFrame.Angles(a[8], 0, a[10]) * P.LeftShoulder
		P.LeftElbow = CFrame.Angles(a[11], 0, 0) * P.LeftElbow
	end

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
	local dropLocal = rootFrame:VectorToObjectSpace(Vector3.new(0, -pelvisDrop - (if bodyB then bodyB[4] * ls else 0), 0))
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
	-- The bow (item 8): the bow arm's hold and aim, the chest side-on, the string arm solved onto the string
	OVER.LeftShoulder, OVER.LeftElbow, OVER.RightShoulder, OVER.RightElbow = nil, nil, nil, nil
	if bow > 0.002 then
		local aim = entry.bowAim
		-- (your own first-person body keeps its chest square: the view looks down on it)
		local turn = if isLocal then 0 else BOW.turn * aim * bow
		if turn ~= 0 then
			P.Waist = CFrame.Angles(0, turn, 0) * P.Waist
			P.Neck = CFrame.Angles(0, -0.9 * turn, 0) * P.Neck
		end
		-- the arm is posed in the chest's frame: take out the chest's own pitch and turn so it stays level and on target
		local raise = BOW.holdRaise + (BOW.aimRaise - BOW.holdRaise) * aim - (rootX + waistX) + BOW.crouchRaise * c * (1 - aim)
		local bend = BOW.holdElbow + (BOW.aimElbow - BOW.holdElbow) * aim
		local yaw = BOW.holdYaw * (1 - aim) - turn
		OVER.LeftShoulder = CFrame.Angles(0, yaw, 0) * CFrame.Angles(raise, 0, 0)
		OVER.LeftElbow = CFrame.Angles(bend, 0, 0)
		OVER_W.LeftShoulder, OVER_W.LeftElbow = bow, bow
		local arm = entry.bowArm * bow
		local shoulderJ, elbowJ = j.RightShoulder, j.RightElbow
		if arm > 0.01 and shoulderJ and elbowJ and j.Waist and j.Neck then
			local lowerCF = rootFrame * rootT * rootC1Inv
			local upperCF = lowerCF * j.Waist.C0 * (P.Waist * B.Waist) * j.Waist.C1:Inverse()
			local headCF = upperCF * j.Neck.C0 * (P.Neck * B.Neck) * j.Neck.C1:Inverse()
			local anchor = headCF * (BOW.anchor * (rig.scale or 1))
			local nock = bowNock(entry) or (rootCF * Vector3.new(-0.3, 0.9, -1.5))
			local target = nock:Lerp(anchor, BOW.reach + (1 - BOW.reach) * entry.bowPull)
			local shoulderT, elbowT = solveArm(upperCF, shoulderJ, elbowJ, stringWrist(entry), CFrame.Angles(math.rad(75), 0, math.rad(25)),
				CFrame.Angles(math.rad(95), 0, 0), target, rootCF:VectorToWorldSpace(BOW.pole))
			OVER.RightShoulder, OVER.RightElbow = shoulderT, elbowT
			OVER_W.RightShoulder, OVER_W.RightElbow = arm, arm
		end
		-- other players' bows show the string drawn (your own arms and bow are hidden in first person)
		if entry.bowT0 and entry.bowArm > 0.6 and (not entry.isLocal or poseAsRemote) then
			showBowString(entry)
		end
	end
	for _, name in ipairs(UPPER_JOINTS) do
		local joint = j[name]
		if joint and joint.Parent then
			local pose = P[name] * B[name]
			local over = OVER[name]
			if over then
				pose = pose:Lerp(over, OVER_W[name])
			end
			writeJoint(entry, joint, B[name], pose)
		end
	end
	entry.posed = true
	-- the Blender clips over all of it (ClipPlayer, hooked)
	applyClips(entry, os.clock())
end

-- Ranks the other characters by distance from the camera and gives each its share of the pose (entry.lod, see LOD).
local ranked: { any } = {}
local rankAt = -math.huge
local IK_KEEP = 2 -- places past LOD.ikMax at which a character that has foot IK keeps it
local function byRankDistance(a: any, b: any): boolean
	return a.rankDistance < b.rankDistance
end
local function rankEntries(camCF: CFrame?)
	table.clear(ranked)
	local camPos = if camCF then camCF.Position else Vector3.zero
	local look = if camCF then camCF.LookVector else nil
	for _, entry in pairs(entries) do
		if entry.isLocal then
			entry.lod = 2
		else
			entry.hadIK = entry.lod == 2
			entry.lod = 0
			local root = entry.root
			local humanoid = entry.humanoid
			-- (a body that has fallen is not posed, poseEntry: it takes no place in the ranking from the living)
			if root and root.Parent and not (humanoid and humanoid.Health <= 0) then
				local offset = root.Position - camPos
				local d = offset.Magnitude
				-- (behind: more than about 100 degrees off the look, outside any field of view)
				local behind = look ~= nil and d > LOD.behindNear and offset:Dot(look) < -0.2 * d
				if d <= LOD.poseRange and not behind then
					entry.rankDistance = d
					table.insert(ranked, entry)
				end
			end
		end
	end
	table.sort(ranked, byRankDistance)
	for i, entry in ipairs(ranked) do
		-- A character that has foot IK keeps it IK_KEEP places past the cap. By plain rank, two about equally far from
		-- the camera swapped the last place every ranking, and the one that lost it had its foot offsets and pelvis
		-- drop cut in one frame: the hips jumped, four times a second.
		local ik = entry.rankDistance <= LOD.ikRange and (i <= LOD.ikMax or (entry.hadIK and i <= LOD.ikMax + IK_KEEP))
		entry.lod = if ik then 2 elseif i <= LOD.poseMax then 1 else 0
	end
end

local function preSimulation(dt: number)
	local started = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	if started - rankAt >= LOD.rank then
		rankAt = started
		rankEntries(if cam then cam.CFrame else nil)
	end
	ikCount = 0
	local count, posed = 0, 0
	for _, entry in pairs(entries) do
		local ok, err = pcall(poseEntry, entry, dt, camPos)
		if not ok and os.clock() - errorAt > 5 then
			errorAt = os.clock()
			warn("[CharacterVisuals] pose error: " .. tostring(err))
		end
		count += 1
		if entry.posed then
			posed += 1
		end
	end
	local ms = (os.clock() - started) * 1000
	poseStats.last = ms
	poseStats.ms += (ms - poseStats.ms) * 0.05
	poseStats.peak = math.max(poseStats.peak * 0.995, ms)
	poseStats.entries, poseStats.posed, poseStats.ik = count, posed, ikCount
end
CharacterVisuals._poseStats = poseStats -- (test hooks, see the header)
CharacterVisuals._lod = LOD

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

-- Defeat (see the header) ----------------------------------------------------------------------------------------------

-- Runs in the render step, after the default TransparencyController. A body this client has just seen at zero health:
-- its default voice sound is silenced, and your own (this client simulates it) is tipped over backward so it never
-- stays standing. DEFEAT_FALL seconds later every part and face fades out over DEFEAT_FADE (local transparency: the
-- server's copy is untouched until it removes the body itself, CombatService).
local function defeatStep(now: number)
	for character, entry in pairs(entries) do
		local at = entry.defeatAt
		if not at then
			local humanoid = entry.humanoid
			if not (humanoid and humanoid.Parent == character) then
				humanoid = character:FindFirstChildOfClass("Humanoid")
			end
			if humanoid and humanoid.Health <= 0 then
				entry.defeatAt = now
				entry.bowT0 = nil
				removeBowString(entry)
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local cry = root:FindFirstChild("Died")
					if cry and cry:IsA("Sound") then
						cry.Volume = 0
						cry:Stop()
					end
					if entry.isLocal and not root.Anchored then
						local cf = root.CFrame
						root.AssemblyAngularVelocity += cf.RightVector * DEFEAT_TIP
						root.AssemblyLinearVelocity -= cf.LookVector * 2
					end
				end
			end
		else
			local k = (now - at - DEFEAT_FALL) / DEFEAT_FADE
			if k > 0 and not (entry.defeatGone and not entry.isLocal) then
				local parts = entry.defeatParts
				if not parts then
					parts = {}
					for _, d in ipairs(character:GetDescendants()) do
						if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
							table.insert(parts, d)
						end
					end
					entry.defeatParts = parts
				end
				local fade = smooth01(k)
				for _, d in ipairs(parts) do
					d.LocalTransparencyModifier = fade
				end
				entry.defeatGone = k >= 1
			end
		end
	end
end

function CharacterVisuals.Init(registry)
	Controllers = registry
end

function CharacterVisuals.Start()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		for key, value in pairs(LOD_TOUCH) do
			(LOD :: any)[key] = value -- a phone or tablet: a smaller crowd is posed
		end
	end
	local function readHook()
		poseAsRemote = Config.IsStudio and player:GetAttribute("LS_PoseAsRemote") == true -- (a test hook: Studio only)
	end
	readHook()
	player:GetAttributeChangedSignal("LS_PoseAsRemote"):Connect(readHook)
	RunService:BindToRenderStep("LS_FirstPersonBody", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local ok, err = pcall(firstPersonBody, dt)
		if ok then
			ok, err = pcall(defeatStep, os.clock())
		end
		if not ok and os.clock() - errorAt > 5 then
			errorAt = os.clock()
			warn("[CharacterVisuals] body error: " .. tostring(err))
		end
	end)
	-- your own bow draws (item 8)
	local combat = Controllers and Controllers.CombatController
	if combat and type(combat.action) == "table" and type(combat.action.Connect) == "function" then
		combat.action:Connect(onOwnCombat)
	end
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
	-- other players' melee swings (#90)
	local okRemote, remote = pcall(Net.event, "CombatAction")
	if okRemote and remote then
		remote.OnClientEvent:Connect(function(payload)
			local ok, err = pcall(onCombatAction, payload)
			if not ok and os.clock() - errorAt > 5 then
				errorAt = os.clock()
				warn("[CharacterVisuals] swing error: " .. tostring(err))
			end
		end)
	else
		warn("[CharacterVisuals] no CombatAction remote: other players' swings won't show")
	end
end

return CharacterVisuals
