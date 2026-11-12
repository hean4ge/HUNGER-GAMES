--[[
	ViewmodelController.Poses - hand poses for the first-person viewmodel. Pure data and functions (no state), so
	poses can be previewed in Edit mode.
	Camera space: camera at the origin looking down -Z, +X right, +Y up. A pose is a wrist frame:
	the thumb (+Y) points where a held item's business end goes, the knuckles (-Z) where a blade's edge faces.
	  Poses.hand(position, thumbDirection, knuckleDirection) -> CFrame
	  Poses.hold(kind, aim, itemId?) -> (right, left)   kind: Fists | Blade | Spear | SpearRaised | Bow | Throwable | Item |
	                                                Armor (for the Bow, aim is how far the bow is raised: 0 low ready, 1
	                                                drawn); Poses.HOLD_ITEM[itemId] replaces a hand for that item
	  Poses.swing(style, variant, t, windup, strike, total, restRight, restLeft) -> (right, left)
	  Poses.spearLeft(rightGrip, reach, gripPointLeft, near?) -> CFrame   the supporting hand on a spear shaft
	  Poses.throw(spear, t, windup, total, restRight) -> CFrame
	  Poses.applyUse(style, t, u, right, left, rig, duration) -> (right, left)   style: Eat | Drink | Bandage | Wrap |
	                                         Armor: the use pose t s in, blended in from the hold by u (Poses.DRINK, EAT,
	                                         WRAP, ARMOR)
	  Poses.usePole(style) -> Vector3?   the left elbow's pole during a use (Wrap); the controller blends it in by u
	  Poses.useHidesItem(style, t, duration) -> boolean   the used item is out of view (armor over the shoulder)
	  Poses.use(style, t, restRight, restLeft, duration?) -> (right, left)   the Eat / Bandage / Armor keyframes
	  Poses.bowString(nock, shootDir, bowUp, hook) -> CFrame     right hand hooked on the string (the controller then
	                                                             straightens its wrist, Rig.straightWrist)
	  Poses.bowFollow(u) -> (Vector3, number)   bow-hand follow-through after a release: offset and forward tip
	  Poses.bowRaise(draw) / Poses.bowPull(draw) / Poses.bowDip(draw) -> number   how far the bow is raised, the
	                                         string pulled, and the bow pushed out and down (x Poses.BOW_DIP), 0..1
	  Poses.bowTuck(right, left, tuck) -> (right, left)      the bow pulled in against a wall (tuck 0..1)
]]
local Poses = {}

local V = Vector3.new

function Poses.hand(position: Vector3, thumb: Vector3, knuckles: Vector3): CFrame
	local y = thumb.Unit
	local edge = knuckles - y * knuckles:Dot(y)
	if edge.Magnitude < 1e-3 then
		local fallback = if math.abs(y.Z) < 0.9 then V(0, 0, -1) else V(0, -1, 0)
		edge = fallback - y * fallback:Dot(y)
	end
	local z = -edge.Unit
	return CFrame.fromMatrix(position, y:Cross(z), y, z)
end
local H = Poses.hand

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end
local function easeIn(t: number): number
	return t * t
end
local function easeInOut(t: number): number
	return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
end
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end
Poses.easeOut = easeOut
Poses.easeInOut = easeInOut
Poses.smooth = smooth

Poses.SPEAR_DIR = V(-0.1, 0.13, -1).Unit

-- Idle holds
Poses.HOLD = {
	Fists = {
		right = H(V(0.74, -0.94, -1.5), V(-0.12, 1, -0.3), V(-0.15, -0.2, -1)),
		left = H(V(-0.78, -1.0, -1.6), V(0.12, 1, -0.3), V(0.15, -0.2, -1)),
	},
	Blade = {
		right = H(V(0.93, -0.92, -1.33), V(0.12, 0.92, -0.37), V(-0.1, -0.35, -0.93)),
		left = H(V(-0.82, -1.55, -1.3), V(0.15, 1, -0.3), V(0.1, -0.2, -1)),
	},
	-- Spear: a low guard across the body - the right hand at the hip (just below the view), the left hand forward on
	-- the shaft at the lower left (Poses.SPEAR_LEFT, knuckles up so the fist shows on the shaft), the head out at the
	-- left edge near the horizon. The crosshair and a target in front stay clear; the stab swings the point onto
	-- the crosshair (Poses.STAB) and the shaft slides through the left hand.
	Spear = {
		right = H(V(0.630, -0.975, -0.667), V(-0.742, 0.363, -0.564), V(-0.226, -0.927, -0.299)),
		left = H(V(-0.597, -0.964, -1.247), V(-0.742, 0.363, -0.564), V(0.670, 0.359, -0.650)),
	},
	SpearRaised = {
		right = H(V(0.85, -0.32, -0.72), V(-0.07, 0.09, -1), V(0, 1, 0.1)),
		left = H(V(-0.55, -0.62, -1.55), V(0.12, 1, -0.2), V(0.15, -0.1, -1)),
	},
	-- Bow in the left hand; the right hand hooks the string whenever an arrow is nocked (ViewmodelController). The
	-- arrow rides on the camera side of the riser (Rig.ARROW_SIDE), so the shaft and the arrowhead show past the bow hand.
	-- BowReady: low ready - the bow low on the left, canted 35 deg, the arrow pointing a little down toward the ground
	-- ahead; the string hand holds the nock at the lower left (left of the hotbar), its forearm coming in from the lower
	-- right (Rig.POLE.BowRight) with the wrist straight (Rig.straightWrist), and the shaft passes above the hotbar.
	-- BowDrawn: full draw (string pulled Config.Combat.ViewBowDraw = 1.35): the nock at an under-chin anchor, camera
	-- (-0.12, -0.55, -0.2), so the drawing hand is just below the view; the bow canted 30 deg toward the upper left with
	-- the bow hand 14-17 deg below-left of the crosshair and the arrowhead 13 deg left / 11 deg below it, pointing up
	-- toward the aim. Drawing pulls the string back while the bow is pushed out and down a little (Poses.bowDip) and
	-- then raised (Poses.bowRaise), so the drawing hand goes back and down out of view early in the draw, staying over
	-- 1.4 studs from the eye while it shows, instead of passing just under the eye. Everything stays out of the
	-- crosshair's 6 % circle up to a 106 deg FOV and off a training dummy at 15-60 studs.
	BowReady = {
		right = H(V(0.55, -1.3, -1.1), V(-0.1, 1, -0.2), V(-0.3, -0.2, -1)),
		left = H(V(-0.665, -1.132, -1.364), V(-0.582, 0.783, -0.219), V(-0.035, -0.293, -0.955)),
	},
	BowDrawn = {
		right = H(V(0.55, -1.3, -1.1), V(-0.1, 1, -0.2), V(-0.3, -0.2, -1)),
		left = H(V(-0.466, -0.841, -1.622), V(-0.495, 0.865, 0.084), V(-0.262, -0.056, -0.964)),
	},
	-- Against a wall: the bow pulled in upright at the left shoulder (within about a stud of the eye), the string let
	-- down and the arrow kept out of view, the right hand low at the right.
	BowTucked = {
		right = H(V(0.56, -1.12, -0.72), V(-0.1, 1, -0.2), V(-0.3, -0.2, -1)),
		left = H(V(-0.66, -0.9, -0.7), V(-0.42, 1, 0.25), V(0.3, 0.1, -1)),
	},
	Throwable = {
		right = H(V(0.86, -0.95, -1.38), V(0.05, 0.75, -0.66), V(-0.05, -0.66, -0.75)),
		left = H(V(-0.82, -1.55, -1.3), V(0.15, 1, -0.3), V(0.1, -0.2, -1)),
	},
	Item = {
		right = H(V(0.82, -1.0, -1.38), V(0, 0.88, -0.48), V(-0.1, -0.48, -0.87)),
		left = H(V(-0.82, -1.55, -1.3), V(0.15, 1, -0.3), V(0.1, -0.2, -1)),
	},
	Armor = {
		right = H(V(1.2, -0.35, -2.1), V(0.05, -1, 0.05), V(-1, 0, -0.55)), -- the vest hangs from the fist by its collar, in view
		left = H(V(-0.82, -1.55, -1.3), V(0.15, 1, -0.3), V(0.1, -0.2, -1)),
	},
}

-- Items held up to be seen, over their kind's hold (a hand left out keeps the kind's): the bandage roll beside the fist
-- (Rig.ITEM_HOLD.bandage) and the berry sprig upright in it, the berries over the fist, both above the hotbar at the
-- lower right.
Poses.HOLD_ITEM = {
	bandage = { right = H(V(0.8, -0.62, -1.42), V(-0.15, 0.95, -0.25), V(-0.35, -0.25, -0.9)) },
	berries = { right = H(V(0.74, -0.86, -1.34), V(-0.12, 0.92, -0.38), V(-0.2, -0.42, -0.88)) },
}

function Poses.hold(kind: string, aim: number?, itemId: string?): (CFrame, CFrame)
	if kind == "Bow" then
		local a = math.clamp(aim or 0, 0, 1)
		local ready, drawn = Poses.HOLD.BowReady, Poses.HOLD.BowDrawn
		return ready.right:Lerp(drawn.right, a), ready.left:Lerp(drawn.left, a)
	end
	local hold = Poses.HOLD[kind] or Poses.HOLD.Item
	local own = if itemId then Poses.HOLD_ITEM[itemId] else nil
	if own then
		return own.right or hold.right, own.left or hold.left
	end
	return hold.right, hold.left
end

-- Drawing a bow (draw = charge 0..1): the string comes back quickly at first while the bow arm pushes the bow out and
-- down a little, so the drawing hand drops back and down out of view while it is still well away from the eye; the
-- bow comes up to the shooting position over the draw and arrives with the hand at the anchor.
Poses.BOW_DIP = V(0, -0.3, -0.15) -- the bow hand's push at the deepest point of the draw (camera space)
function Poses.bowRaise(draw: number): number
	local d = math.clamp(draw, 0, 1)
	return d * d
end
function Poses.bowPull(draw: number): number
	return easeOut(math.clamp(draw, 0, 1))
end
function Poses.bowDip(draw: number): number
	return math.sin(math.pi * math.clamp(draw, 0, 1) ^ 0.7)
end

-- Against a wall the bow is pulled in upright beside the left shoulder (tuck 0..1).
function Poses.bowTuck(right: CFrame, left: CFrame, tuck: number): (CFrame, CFrame)
	local s = smooth(math.clamp(tuck, 0, 1))
	if s <= 0 then
		return right, left
	end
	local tucked = Poses.HOLD.BowTucked
	return right:Lerp(tucked.right, s), left:Lerp(tucked.left, s)
end

-- Melee swings. W = end of the windup, M = middle of the strike, F = follow-through (right hand).
Poses.SWING = {
	Slash = {
		{ -- right to left, falling
			W = H(V(1.08, -0.45, -1.02), V(0.55, 0.75, 0.35), V(-0.8, -0.2, -0.55)),
			M = H(V(0.28, -0.76, -1.7), V(-0.55, 0.3, -0.78), V(-0.6, -0.5, 0.2)),
			F = H(V(-0.42, -1.18, -1.3), V(-0.85, -0.35, -0.4), V(-0.2, -0.9, 0.3)),
		},
		{ -- left to right, rising backhand
			W = H(V(-0.12, -0.72, -1.25), V(-0.75, 0.55, 0.2), V(0.7, 0.1, -0.7)),
			M = H(V(0.5, -0.74, -1.7), V(0.3, 0.35, -0.9), V(0.8, -0.3, 0.1)),
			F = H(V(1.12, -0.88, -1.18), V(0.9, 0.1, -0.2), V(0.2, -0.6, 0.75)),
		},
	},
	Chop = {
		{
			W = H(V(0.88, -0.38, -0.9), V(0.22, 0.7, 0.68), V(0, 0.55, -0.85)),
			M = H(V(0.6, -0.66, -1.65), V(-0.05, 0.38, -0.92), V(0, -0.95, -0.35)),
			F = H(V(0.42, -1.22, -1.32), V(-0.08, -0.72, -0.68), V(0, -0.65, 0.75)),
		},
		{
			W = H(V(1.0, -0.42, -1.0), V(0.5, 0.72, 0.45), V(-0.45, 0.45, -0.75)),
			M = H(V(0.45, -0.72, -1.65), V(-0.35, 0.35, -0.85), V(-0.5, -0.8, -0.2)),
			F = H(V(0.05, -1.2, -1.3), V(-0.55, -0.6, -0.55), V(-0.3, -0.6, 0.7)),
		},
	},
	Smash = {
		{
			W = H(V(0.95, -0.18, -0.62), V(0.3, 0.6, 0.75), V(0, 0.72, -0.7)),
			M = H(V(0.62, -0.58, -1.72), V(0, 0.28, -0.96), V(0, -1, -0.25)),
			F = H(V(0.35, -1.32, -1.38), V(-0.12, -0.8, -0.58), V(0, -0.5, 0.85)),
		},
		{
			W = H(V(1.08, -0.32, -0.75), V(0.62, 0.6, 0.5), V(-0.5, 0.5, -0.7)),
			M = H(V(0.45, -0.62, -1.72), V(-0.4, 0.3, -0.86), V(-0.45, -0.85, -0.25)),
			F = H(V(-0.15, -1.25, -1.35), V(-0.7, -0.55, -0.45), V(-0.3, -0.55, 0.78)),
		},
	},
}

-- Fists: odd swings jab with the left, even swings cross with the right.
Poses.PUNCH = {
	left = {
		W = H(V(-0.6, -0.92, -1.25), V(0.15, 1, -0.2), V(0.2, -0.15, -1)),
		F = H(V(-0.16, -0.56, -2.05), V(1, 0.15, -0.05), V(0.05, -0.1, -1)),
	},
	right = {
		W = H(V(0.66, -0.9, -1.2), V(-0.15, 1, -0.2), V(-0.2, -0.15, -1)),
		F = H(V(0.1, -0.52, -2.1), V(-1, 0.15, -0.05), V(-0.05, -0.1, -1)),
	},
}

local function phases(t: number, windup: number, strike: number, total: number, rest: CFrame, W: CFrame, M: CFrame?, F: CFrame): CFrame
	if t <= windup then
		return rest:Lerp(W, easeOut(math.clamp(t / math.max(windup, 1e-3), 0, 1)))
	end
	if t <= windup + strike then
		local u = math.clamp((t - windup) / math.max(strike, 1e-3), 0, 1)
		if M then
			if u < 0.5 then
				return W:Lerp(M, easeIn(u * 2))
			end
			return M:Lerp(F, easeOut((u - 0.5) * 2))
		end
		return W:Lerp(F, easeInOut(u))
	end
	local u = math.clamp((t - windup - strike) / math.max(total - windup - strike, 1e-3), 0, 1)
	return F:Lerp(rest, easeInOut(u))
end

function Poses.swing(style: string, variant: number, t: number, windup: number, strike: number, total: number, restRight: CFrame, restLeft: CFrame): (CFrame, CFrame)
	if style == "Punch" then
		local left = variant % 2 == 1
		local set = if left then Poses.PUNCH.left else Poses.PUNCH.right
		local rest = if left then restLeft else restRight
		local moving = phases(t, windup, strike, total, rest, set.W, nil, set.F)
		-- the other fist tucks back a little while this one punches
		local tuck = math.sin(math.clamp(t / math.max(total, 1e-3), 0, 1) * math.pi) * 0.12
		if left then
			return restRight + V(0.02, -0.03, tuck), moving
		end
		return moving, restLeft + V(-0.02, -0.03, tuck)
	end
	if style == "Stab" then
		-- from the guard the point comes round onto the crosshair, then the thrust drives it forward
		local stab = Poses.STAB
		return phases(t, windup, strike, total, restRight, stab.W, stab.M, stab.F), restLeft
	end
	local sets = Poses.SWING[style] or Poses.SWING.Slash
	local set = sets[((variant - 1) % #sets) + 1]
	return phases(t, windup, strike, total, restRight, set.W, set.M, set.F), restLeft
end

-- Spear thrust (right hand): W the point brought round to the front at the hip, M half way, F full reach - the point
-- drives in just under the crosshair (the hit itself follows the camera).
Poses.STAB = {
	W = H(V(0.55, -1.0, -0.45), V(-0.08, -0.14, -1), V(0.15, -1, 0)),
	M = H(V(0.42, -0.86, -0.95), V(-0.07, 0, -1), V(0.12, -1, 0)),
	F = H(V(0.3, -0.82, -1.3), V(-0.05, -0.01, -1), V(0.1, -1, 0)),
}

-- Raising the spear to throw (s 0..1): from the guard the point comes round to the front at the hip first (passing
-- under the crosshair, not across it), then the spear is lifted over the shoulder.
function Poses.spearRaise(s: number): CFrame
	local guard, raised, front = Poses.HOLD.Spear.right, Poses.HOLD.SpearRaised.right, Poses.STAB.W
	if s <= 0 then
		return guard
	elseif s < 0.5 then
		return guard:Lerp(front, smooth(s * 2))
	end
	return front:Lerp(raised, smooth(math.min((s - 0.5) * 2, 1)))
end
Poses.SPEAR_LEFT = V(-0.4, -0.8, -1.4) -- where the left hand holds the shaft in the guard (camera space)
Poses.SPEAR_REACH = 1.241 -- from the right hand's grip to the left hand's, along the shaft, in the guard

-- The supporting hand on the spear shaft: `reach` up the shaft from the right hand's grip, or, given `near`, at the
-- point of the shaft closest to it (so in a thrust the shaft slides through the left hand). Knuckles up, so the
-- fist reads on top of the shaft instead of hiding behind the forearm.
function Poses.spearLeft(rightGrip: CFrame, reach: number, gripPointLeft: Vector3, near: Vector3?): CFrame
	local along = rightGrip.LookVector
	local s = reach
	if near then
		s = math.clamp((near - rightGrip.Position):Dot(along), 0.55, reach + 0.6)
	end
	local target = rightGrip.Position + along * s
	local hand = H(Vector3.zero, along, V(-0.2, 0.6, -1))
	return hand.Rotation + (target - hand.Rotation * gripPointLeft)
end

Poses.THROW = {
	knife = {
		W = H(V(0.86, -0.36, -0.68), V(0.12, 0.55, 0.82), V(0, 0.85, -0.5)),
		R = H(V(0.3, -0.64, -1.78), V(-0.05, 0.22, -1), V(0, -1, -0.2)),
		F = H(V(0.36, -1.28, -1.3), V(0, -0.6, -0.8), V(0, -0.8, 0.6)),
	},
	spear = {
		W = H(V(0.9, -0.24, 0.02), V(-0.06, 0.16, -1), V(0, 1, 0.15)),
		R = H(V(0.38, -0.5, -1.65), V(-0.05, 0.05, -1), V(0, 1, 0)),
		F = H(V(0.4, -1.2, -1.2), V(0, -0.55, -0.85), V(0, 0.8, -0.5)),
	},
}

function Poses.throw(spear: boolean, t: number, windup: number, total: number, rest: CFrame): CFrame
	local set = if spear then Poses.THROW.spear else Poses.THROW.knife
	local snap = 0.07
	if t <= windup then
		return rest:Lerp(set.W, easeOut(math.clamp(t / math.max(windup, 1e-3), 0, 1)))
	elseif t <= windup + snap then
		return set.W:Lerp(set.R, easeIn(math.clamp((t - windup) / snap, 0, 1)))
	end
	local u = math.clamp((t - windup - snap) / math.max(total - windup - snap, 1e-3), 0, 1)
	if u < 0.45 then
		return set.R:Lerp(set.F, easeOut(u / 0.45))
	end
	return set.F:Lerp(rest, easeInOut((u - 0.45) / 0.55))
end

-- Item uses (t = seconds since the use began, `duration` = the item's useTime). Poses.applyUse(style, t, u, right,
-- left, rig, duration) blends the use pose in from the hold (right, left) by u (0..1). `rig` is the viewmodel Rig
-- instance: the held item's Mouth attachment and its hold in the fist (Rig.ITEM_HOLD) place the bottle and the
-- bandage roll, Rig.solveArm gives the left forearm the roll is wound round, and Rig.straightWrist keeps the armor
-- wrists in line with the forearms. Poses.useHidesItem(style, t, duration) is true while the used item is out of view
-- and should be hidden.

-- Drinking: the bottle comes up from the lower right and is tipped to the mouth. Its neck goes down past the bottom
-- edge to the lips (at FOV 100 too), its body runs up to the right, and the fist holds it round its band from behind
-- and below, at the edge, so what shows is mostly the bottle; it tips up further as it empties. The fist is placed by
-- the bottle's roll, not turned to follow the forearm (which is out of view below): that would bring it round in front.
Poses.DRINK = {
	lips = V(0.18, -0.9, -0.72), -- where the bottle's mouth goes (camera space)
	yaw = 75, -- the bottle's axis (mouth -> base): degrees right of straight ahead ...
	tilt0 = 30, -- ... and above level when it reaches the lips,
	tilt1 = 42, -- tipping up to this as it empties
	roll = 225, -- the bottle, and the fist round it, turned about its axis: the fist behind and below the bottle
	low = V(0.3, -0.7, 0.2), -- on the way up and down the bottle passes here (relative to the drinking pose)
}

-- The right hand holding the bottle to the lips (Poses.DRINK), t seconds into a drink of `duration`.
local function drinkHand(rig: any, t: number, duration: number): CFrame
	local D = Poses.DRINK
	local item = rig.item
	local k = math.clamp(t / math.max(duration, 0.1), 0, 1)
	local tilt = math.rad(D.tilt0 + (D.tilt1 - D.tilt0) * k) + math.sin(t * 5) * 0.03 -- small gulps
	local yaw = math.rad(D.yaw)
	local up = V(math.sin(yaw) * math.cos(tilt), math.sin(tilt), -math.cos(yaw) * math.cos(tilt)) -- mouth -> base
	-- the bottle's Handle: LookVector toward its mouth, turned about that axis by D.roll
	local handle = CFrame.lookAt(Vector3.zero, -up, Vector3.yAxis) * CFrame.Angles(0, 0, math.rad(D.roll))
	local mouth = item and item.attachments.Mouth
	handle = handle.Rotation + (D.lips - handle.Rotation * (if mouth then mouth.Position else V(0, 0, -0.6)))
	local hold = (item and item.hold) or CFrame.identity
	local gripFrame = if item then item.gripInverse:Inverse() else CFrame.identity
	return handle * gripFrame * hold:Inverse() * rig.GRIP.Right:Inverse()
end

-- Eating: the food is brought up to the mouth, just above the bottom edge in the middle, the thumb pointing back at
-- the mouth: a sprig, a strip or a bone end goes to the lips, round food sits in the fist on the palm side
-- (Rig.ITEM_HOLD) and shows beside it; a small chewing bob. The berry sprig is held by its stalk with the cluster out
-- of the top of the fist, so the berries go to the mouth (the hand a little higher, EAT.lift, so they show above the
-- hotbar) and the leaves hang out of sight below the fist.
Poses.EAT = {
	hand = H(V(0.2, -0.9, -0.8), V(-0.25, 0.55, 0.8), V(0.2, 0.8, -0.5)),
	chew = 0.035,
	lift = { berries = V(-0.06, 0.09, 0) } :: { [string]: Vector3 }, -- per item, added to the hand (camera space)
}

-- Putting on armor: the right fist holds the folded vest by its collar (it hangs from the fist, inside toward you),
-- lifts it up the right side and swings it back over the right shoulder (it leaves the view at the upper right and is
-- hidden from then on: it is being worn); both fists come down outside the view, then come up at the bottom edge and
-- tug its hem down twice. The *At times are fractions of the use.
Poses.ARMOR = {
	lift = H(V(1.35, -0.1, -1.6), V(0.05, -1, 0.1), V(-1, 0.05, -0.45)),
	over = H(V(1.2, 0.9, 0.3), V(0.15, 0.4, 1), V(-0.2, 1, -0.3)), -- the fist stays out to the right: the vest leaves past the top right corner
	downRight = H(V(1.1, -1.55, -0.45), V(-0.2, 1, -0.2), V(-0.3, -0.2, -1)),
	downLeft = H(V(-1.1, -1.55, -0.45), V(0.2, 1, -0.2), V(0.3, -0.2, -1)),
	tugRight = H(V(0.6, -0.9, -1.35), V(-0.25, 0.85, -0.45), V(-0.15, -0.45, -0.88)), -- clear of the hotbar
	tugLeft = H(V(-0.6, -0.9, -1.35), V(0.25, 0.85, -0.45), V(0.15, -0.45, -0.88)),
	pull = 0.08, -- how far down each tug pulls (studs)
	liftedAt = 0.22, -- the vest is up at the right side
	overAt = 0.42, -- ... and over the shoulder (hidden from here on)
	downAt = 0.56, -- both fists down outside the view
	tug0At = 0.64, -- the fists at the bottom edge; two tugs until
	tug1At = 0.95,
}

function Poses.useHidesItem(style: string, t: number, duration: number): boolean
	return style == "Armor" and t / math.max(duration, 0.1) >= Poses.ARMOR.overAt
end

local function armorHands(t: number, duration: number, restRight: CFrame, restLeft: CFrame): (CFrame, CFrame)
	local A = Poses.ARMOR
	local k = t / math.max(duration, 0.1)
	local right, left = restRight, restLeft
	if k < A.liftedAt then
		right = restRight:Lerp(A.lift, smooth(k / A.liftedAt))
	elseif k < A.overAt then
		right = A.lift:Lerp(A.over, smooth((k - A.liftedAt) / (A.overAt - A.liftedAt)))
	elseif k < A.downAt then
		local s = smooth((k - A.overAt) / (A.downAt - A.overAt))
		right = A.over:Lerp(A.downRight, s)
		left = restLeft:Lerp(A.downLeft, s)
	elseif k < A.tug0At then
		local s = smooth((k - A.downAt) / (A.tug0At - A.downAt))
		right = A.downRight:Lerp(A.tugRight, s)
		left = A.downLeft:Lerp(A.tugLeft, s)
	else
		local p = math.clamp((k - A.tug0At) / (A.tug1At - A.tug0At), 0, 1)
		local pull = V(0, -A.pull * math.abs(math.sin(p * math.pi * 2)), 0)
		right = A.tugRight + pull
		left = A.tugLeft + pull
	end
	return right, left
end

-- Bandaging (the bandage roll, style Wrap): the left forearm comes up across the lower left of the view (its elbow out
-- to the left: Poses.usePole) with the fist bent down at the wrist, and the right hand winds the roll round the
-- forearm just behind the wrist, the roll's axis along the forearm and the right fist below and behind the roll, so
-- the roll shows on the near side and over the top. It moves slowest there and hurries round the far side (out of
-- sight). Two turns, then a short pull to tighten it. It stays left of the hotbar and out of the crosshair's 12 %
-- circle at FOV 72 and 100. The med kit keeps the Bandage style (Poses.use).
Poses.WRAP = {
	wrist = V(-0.6, -0.54, -1.42), -- the left wrist (camera space)
	pole = V(-1, -0.45, 0.1), -- the left elbow's pole: out to the left, so the forearm lies across the view
	bend = V(-0.1, -0.9, -0.4), -- the left fist bent down at the wrist (added to the forearm direction)
	palm = V(0.2, 0.6, 1), -- the left palm turned up toward the eye
	at = 0.3, -- the roll winds round the forearm this far back from the wrist ...
	radius = 0.28, -- ... its centre this far from the forearm's axis
	fist = V(0.8, -0.8, -0.3), -- the right fist sits this way from the roll (across the forearm): below, right, behind
	turns = 2,
	slowAt = math.rad(45), -- where the roll moves slowest (0 = over the top, 90 = the near side) ...
	ease = 0.6, -- ... and how much faster it goes round the far side
	start = 0.12, -- the winding runs from here ...
	stop = 0.84, -- ... to here (fractions of the use), then
	tug = V(-0.06, -0.1, 0.03), -- a short pull, down and back, to tighten the wrap
}

local function wrapHands(rig: any, t: number, duration: number): (CFrame, CFrame)
	local W = Poses.WRAP
	local elbow = rig.solveArm(rig.SHOULDER.Left, W.wrist, W.pole)
	local along = (W.wrist - elbow).Unit -- the left forearm as the arm IK draws it
	local knuckles = (along + W.bend).Unit
	local palm = (W.palm - knuckles * knuckles:Dot(W.palm)).Unit
	local left = H(W.wrist, (-knuckles):Cross(palm), knuckles)
	local up = (Vector3.yAxis - along * along.Y).Unit -- across the forearm: up ...
	local near = along:Cross(up) -- ... and toward the eye
	local k = math.clamp(t / math.max(duration, 0.1), 0, 1)
	local s = math.clamp((k - W.start) / (W.stop - W.start), 0, 1)
	local turn = s * W.turns
	local p = if s >= 1 then 0 else turn - math.floor(turn)
	local angle = W.slowAt + 2 * math.pi * p - W.ease * math.sin(2 * math.pi * p)
	local centre = W.wrist - along * W.at + (up * math.cos(angle) + near * math.sin(angle)) * W.radius
	-- the roll's axis (the right thumb, Rig.ITEM_HOLD.bandage) along the forearm, the fist on the W.fist side of it
	local side = (W.fist - along * along:Dot(W.fist)).Unit
	local hand = CFrame.fromMatrix(Vector3.zero, side, along)
	local item = rig.item
	local roll = (rig.GRIP.Right * ((item and item.hold) or CFrame.identity)).Position -- the roll's centre in the hand
	local right = hand + (centre - hand:VectorToWorldSpace(roll))
	if k > W.stop then
		right += W.tug * math.sin(smooth((k - W.stop) / (1 - W.stop)) * math.pi * 0.5)
	end
	return right, left
end

-- The left elbow's pole during a use (nil: Rig.POLE.Left); the controller blends it in with the use.
function Poses.usePole(style: string): Vector3?
	return if style == "Wrap" then Poses.WRAP.pole else nil
end

-- Eating, bandaging with the med kit and putting on armor (t = seconds since the use began).
function Poses.use(style: string, t: number, restRight: CFrame, restLeft: CFrame, duration: number?): (CFrame, CFrame)
	if style == "Armor" then
		return armorHands(t, duration or 1.5, restRight, restLeft)
	elseif style == "Bandage" then
		local left = H(V(0.12, -0.88, -1.32), V(0.05, 1, 0.1), V(1, 0, -0.25))
		local angle = t * 8.5
		local around = V(0.02 + math.cos(angle) * 0.2, 0.02 + math.sin(angle) * 0.17, 0.06)
		local right = H(left.Position + around + V(0.32, 0.05, 0.1), V(-0.45, 0.7, -0.5), V(-1, -0.1, -0.3))
		return right, left
	end
	-- Eat
	return Poses.EAT.hand + V(0, math.abs(math.sin(t * 7)) * Poses.EAT.chew, 0), restLeft
end

function Poses.applyUse(style: string, t: number, u: number, right: CFrame, left: CFrame, rig: any, duration: number): (CFrame, CFrame)
	if style == "Drink" then
		local drink = drinkHand(rig, t, duration)
		local low = drink + Poses.DRINK.low
		return if u < 0.5 then right:Lerp(low, u * 2) else low:Lerp(drink, (u - 0.5) * 2), left
	end
	local useRight: CFrame, useLeft: CFrame
	if style == "Wrap" then
		useRight, useLeft = wrapHands(rig, t, duration)
	else
		useRight, useLeft = Poses.use(style, t, right, left, duration)
	end
	if style == "Eat" then
		local lift = rig and rig.item and Poses.EAT.lift[rig.item.itemId]
		if lift then
			useRight += lift
		end
	elseif style == "Armor" then
		-- both wrists in line with the forearms (the vest hangs from the right fist along the thumb)
		useRight = rig.straightWrist(useRight, rig.GRIP_POINT.Right, useRight.UpVector, true, rig.SHOULDER.Right, rig.POLE.Right)
		useLeft = rig.straightWrist(useLeft, rig.GRIP_POINT.Left, useLeft.UpVector, false, rig.SHOULDER.Left, rig.POLE.Left)
	end
	return right:Lerp(useRight, u), left:Lerp(useLeft, u)
end

-- Right hand hooked on the bow string at the nocking point.
function Poses.bowString(nock: Vector3, shootDir: Vector3, bowUp: Vector3, hook: Vector3): CFrame
	local hand = H(Vector3.zero, bowUp, shootDir)
	return hand.Rotation + (nock - hand.Rotation * hook)
end

-- Follow-through after a release (u = 0..1 over the release animation): the bow hand drops away down and to the left
-- (away from the crosshair) and the bow tips forward in the hand, then it settles. Returns a camera-space offset and the
-- tip angle (hand-space X rotation; negative tips the top limb away from you).
function Poses.bowFollow(u: number): (Vector3, number)
	local pulse = if u < 0.25 then easeOut(u / 0.25) else 1 - easeInOut((u - 0.25) / 0.75)
	return V(-0.06, -0.1, -0.03) * pulse, -0.2 * pulse
end

return Poses
