--[[
	ViewmodelController.Poses - hand poses for the first-person viewmodel. Pure data and functions (no state), so
	poses can be previewed in Edit mode.
	Camera space: camera at the origin looking down -Z, +X right, +Y up. A pose is a wrist frame:
	the thumb (+Y) points where a held item's business end goes, the knuckles (-Z) where a blade's edge faces.
	  Poses.hand(position, thumbDirection, knuckleDirection) -> CFrame
	  Poses.hold(kind, aim, itemId?) -> (right, left)   kind: Fists | Blade | Spear | SpearRaised | Bow | Throwable | Item |
	                                                Armor (for the Bow, aim is how far the bow is raised: 0 low ready, 1
	                                                drawn); Poses.HOLD_ITEM[itemId] replaces a hand for that item
	  Poses.swing(style, variant, t, windup, strike, total, restRight, restLeft, jitter?) -> (right, left)   jitter:
	                                         CombatController.swingJitter(seed) (a little different every swing)
	  Poses.swingCount(style) -> number   Poses.swingSide(style, variant) -> "Left" | "Right"
	  Poses.swingKick(style, variant) -> Vector3?   the set's camera-kick direction (CombatController)
	  Poses.swingPole(style, variant) -> Vector3?   the striking elbow's pole during the swing
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
	  Poses.useStyle(style)   "Faceted" | "Avatar" | "Classic": the arm style's values for the holds and uses
	                                         (Poses.FACETED, Poses.AVATAR; Poses.STYLES)
	  Poses.facetedHand(wrist, fingers, palm, left?) -> CFrame   (Faceted) a hand frame from its wrist, the way the fingers
	                                         point and the way the palm faces
	  Poses.guardBlend(relaxed, guard, g, dip?) -> CFrame   (Faceted) the empty hand between the relaxed idle (g = 0)
	                                         and the raised guard (g = 1), dipped below the view by dip x Poses.GUARD_DIP
	                                         (on the way down, so the fist can turn back into the relaxed hand out of sight)
	  Melee swings (#90): Poses.SWING[style] is a list of swing sets (see "Swing sets" below: W, M, F and optional U, A,
	  B, R waypoints, side, pole, kick, tp); Poses.swing picks ((variant - 1) % #list) + 1, so a style takes any number of
	  sets (append to the list; CombatController reads the count, Poses.swingCount). Punches: Poses.PUNCH and thrusts:
	  Poses.STAB are lists of sets too for the Faceted arms (jab, cross, hook; straight, high, low); the Classic and
	  Avatar arms keep PUNCH.left / right (odd variants jab with the left) and a single STAB { W, M, F }. Each arm style
	  has its own tables (Poses.FACETED.SWING ...).
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
Poses.HOLD.Relaxed = Poses.HOLD.Fists -- (empty hands at rest; only the Faceted arms have their own, Poses.FACETED)

-- (Faceted) a hand frame from its wrist, the direction its fingers point (the hand's length, -Z) and the direction its
-- palm faces; the right hand unless `left`.
function Poses.facetedHand(wrist: Vector3, fingers: Vector3, palm: Vector3, left: boolean?): CFrame
	local f = fingers.Unit
	local p = palm - f * palm:Dot(f)
	p = if p.Magnitude > 1e-3 then p.Unit else V(0, -1, 0)
	return H(wrist, if left then p:Cross(f) else f:Cross(p), f)
end

-- (Faceted) empty hands between the relaxed idle (g = 0) and the raised guard (g = 1), dipped by `dip` x
-- Poses.GUARD_DIP: on the way down the controller dips the hands out of view around g = 0.5, where the fist turns
-- back into the relaxed hand.
Poses.GUARD_DIP = V(0, -0.45, 0.12)
function Poses.guardBlend(relaxed: CFrame, guard: CFrame, g: number, dip: number?): CFrame
	return relaxed:Lerp(guard, smooth(math.clamp(g, 0, 1))) + Poses.GUARD_DIP * (dip or 0)
end

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

-- Swing sets. A set is { W = windup end, M = mid-strike, F = follow-through (frames for the striking hand), and
-- optionally U = waypoints from the hold to W, A = waypoints from W to M, B = from M to F, R = waypoints on the way
-- back from F to the hold (each one frame or a list of frames, passed through in order), side = "Left" (a punch with
-- the left fist; else the right hand), pole = the striking elbow's pole (Poses.swingPole), kick = the camera kick's
-- direction (pitch, yaw, roll: Poses.swingKick), tp = the third-person shape (CharacterVisuals) }.
local function path(frames: { CFrame }, s: number): CFrame
	local n = #frames - 1
	if n <= 0 then
		return frames[1]
	end
	local x = math.clamp(s, 0, 1) * n
	local i = math.min(math.floor(x), n - 1)
	return frames[i + 1]:Lerp(frames[i + 2], x - i)
end

-- first, the waypoints in `keys` (one frame or a list), then last
local function via(first: CFrame, keys: any, last: CFrame?): { CFrame }
	local list = { first }
	if typeof(keys) == "CFrame" then
		table.insert(list, keys)
	elseif type(keys) == "table" then
		for _, key in ipairs(keys) do
			table.insert(list, key)
		end
	end
	if last then
		table.insert(list, last)
	end
	return list
end

-- The hand for a set at t s into an action of windup / strike / total s: the hold to W over the windup (easing out),
-- W to M accelerating and M to F slowing over the strike, then back to the hold (by way of R, under the view, when the
-- set has one). `follow` (about 1) stretches the first part of the way back a little (the swing's jitter).
local function phases(t: number, windup: number, strike: number, total: number, rest: CFrame, set: any, follow: number?): CFrame
	local W, M, F = set.W, set.M, set.F
	if t <= windup then
		return path(via(rest, set.U, W), easeOut(math.clamp(t / math.max(windup, 1e-3), 0, 1)))
	end
	if t <= windup + strike then
		local u = math.clamp((t - windup) / math.max(strike, 1e-3), 0, 1)
		if M then
			if u < 0.5 then
				return path(via(W, set.A, M), easeIn(u * 2))
			end
			return path(via(M, set.B, F), easeOut((u - 0.5) * 2))
		end
		return path(via(W, set.A, F), easeInOut(u))
	end
	local u = math.clamp((t - windup - strike) / math.max(total - windup - strike, 1e-3), 0, 1)
	local R = set.R
	if R then
		local first = if typeof(R) == "CFrame" then R else R[1]
		local a = 0.4 * math.clamp(follow or 1, 0.8, 1.2)
		if u < a then
			return F:Lerp(first, smooth(u / a))
		end
		local list = { first }
		if typeof(R) ~= "CFrame" then
			for i = 2, #R do
				table.insert(list, R[i])
			end
		end
		table.insert(list, rest)
		return path(list, easeInOut((u - a) / (1 - a)))
	end
	return F:Lerp(rest, easeInOut(u))
end

-- The set a swing plays: Poses.SWING[style] (a list; an unknown style swings like Slash), the punches Poses.PUNCH and
-- the thrusts Poses.STAB. PUNCH and STAB are lists for the Faceted arms; the older arms keep PUNCH = { left, right }
-- (odd swings jab with the left) and a single STAB.
local function setFor(style: string, variant: number): (any, string)
	variant = math.max(1, math.floor(tonumber(variant) or 1))
	if style == "Punch" then
		local punch = Poses.PUNCH
		if #punch > 0 then
			local set = punch[((variant - 1) % #punch) + 1]
			return set, set.side or (if variant % 2 == 1 then "Left" else "Right")
		end
		if variant % 2 == 1 then
			return punch.left, "Left"
		end
		return punch.right, "Right"
	elseif style == "Stab" then
		local stab = Poses.STAB
		if #stab > 0 then
			return stab[((variant - 1) % #stab) + 1], "Right"
		end
		return stab, "Right"
	end
	local sets = Poses.SWING[style] or Poses.SWING.Slash
	return sets[((variant - 1) % #sets) + 1], "Right"
end

-- How many sets a style has (CombatController picks one per swing).
function Poses.swingCount(style: string): number
	if style == "Punch" then
		return if #Poses.PUNCH > 0 then #Poses.PUNCH else 2
	elseif style == "Stab" then
		return if #Poses.STAB > 0 then #Poses.STAB else 1
	end
	local sets = Poses.SWING[style] or Poses.SWING.Slash
	return #sets
end

-- Which hand a set strikes with ("Left" | "Right").
function Poses.swingSide(style: string, variant: number): string
	local _, side = setFor(style, variant)
	return side
end

-- The direction of the camera kick for a set (pitch, yaw, roll; + pitch looks up, + yaw turns left, + roll tilts left;
-- CombatController scales it to the style's kick), or nil for a set without its own `kick` (then odd sets kick to the
-- left, even sets to the right).
function Poses.swingKick(style: string, variant: number): Vector3?
	local set = setFor(style, variant)
	if set and typeof(set.kick) == "Vector3" then
		return set.kick
	end
	return nil
end

-- The striking elbow's pole during a swing (nil: the hold's): the set's own, else Poses.SWING_POLE (mirrored for the
-- left fist).
function Poses.swingPole(style: string, variant: number): Vector3?
	local set, side = setFor(style, variant)
	if set and typeof(set.pole) == "Vector3" then
		return set.pole
	end
	local p = Poses.SWING_POLE
	if p and side == "Left" then
		return V(-p.X, p.Y, p.Z)
	end
	return p
end

-- Per-swing variation (CombatController.swingJitter(seed): pitch, yaw, roll in radians and follow ~1): the set's
-- keyframes turned a little about the striking shoulder (Poses.JITTER_PIVOT, x mirrored for the left), by
-- Poses.JITTER_SCALE of the angles, and the follow-through shortened a little. The hold and R are not turned, so the
-- swing still starts and ends exactly at the hold.
Poses.JITTER_PIVOT = V(0.5, -0.9, 0)
Poses.JITTER_SCALE = 0.6
local function jittered(set: any, side: string, jitter: any): any
	if type(jitter) ~= "table" then
		return set
	end
	local k = Poses.JITTER_SCALE or 0
	local pitch, yaw, roll = (tonumber(jitter.pitch) or 0) * k, (tonumber(jitter.yaw) or 0) * k, (tonumber(jitter.roll) or 0) * k
	local p = Poses.JITTER_PIVOT or V(0.5, -0.9, 0)
	if side == "Left" then
		yaw, roll = -yaw, -roll
		p = V(-p.X, p.Y, p.Z)
	end
	local turn = CFrame.new(p) * CFrame.Angles(pitch, yaw, roll) * CFrame.new(-p)
	local function apply(key: any): any
		if typeof(key) == "CFrame" then
			return turn * key
		elseif type(key) == "table" then
			local out = table.create(#key)
			for i, frame in ipairs(key) do
				out[i] = turn * frame
			end
			return out
		end
		return key
	end
	local follow = math.clamp(tonumber(jitter.follow) or 1, 0.8, 1.2)
	local F = set.F
	if set.M and follow < 1 then
		F = set.M:Lerp(F, follow) -- (a shorter follow-through)
	end
	return {
		U = apply(set.U), W = apply(set.W), A = apply(set.A), M = apply(set.M), B = apply(set.B), F = apply(F),
		R = set.R, side = set.side,
	}
end

function Poses.swing(style: string, variant: number, t: number, windup: number, strike: number, total: number, restRight: CFrame, restLeft: CFrame, jitter: any?): (CFrame, CFrame)
	local set, side = setFor(style, variant)
	if not set then
		return restRight, restLeft
	end
	set = jittered(set, side, jitter)
	local follow = if type(jitter) == "table" then tonumber(jitter.follow) else nil
	if style == "Punch" then
		local left = side == "Left"
		local moving = phases(t, windup, strike, total, if left then restLeft else restRight, set, follow)
		-- the other fist tucks back a little while this one punches
		local tuck = math.sin(math.clamp(t / math.max(total, 1e-3), 0, 1) * math.pi) * 0.12
		if left then
			return restRight + V(0.02, -0.03, tuck), moving
		end
		return moving, restLeft + V(-0.02, -0.03, tuck)
	end
	-- (a thrust: from the guard the point comes round under the crosshair, then the thrust drives it forward)
	return phases(t, windup, strike, total, restRight, set, follow), restLeft
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
Poses.MEDKIT = {} -- (Avatar: Poses.AVATAR.MEDKIT; the Classic arms bandage in place, Poses.use)
-- How far the supporting hand has let go of the shaft as the spear is raised to throw (raised 0..1 -> 0..1): it is off
-- by SPEAR_RAISE_LET_GO of the raise (Avatar: early, before the shaft swings across the bottom of the view).
Poses.SPEAR_RAISE_LET_GO = 1
function Poses.spearRaiseLetGo(raised: number): number
	return smooth(math.clamp(raised / math.max(Poses.SPEAR_RAISE_LET_GO or 1, 0.05), 0, 1))
end
-- (Avatar) the left hand lets go of the shaft for a stab (Poses.spearLetGo: how far, 0..1, the controller blends it
-- from the shaft to its free hold): it lets go at once as the thrust starts (so it never rides the shaft across the
-- bottom of the view) and takes the shaft again only as the spear settles back into the guard.
Poses.STAB_LET_GO = 0
function Poses.spearLetGo(t: number, windup: number, strike: number, total: number): number
	local most = Poses.STAB_LET_GO or 0
	if most <= 0 then
		return 0
	elseif t <= windup then
		return most * smooth(math.clamp(t / math.max(windup * 0.2, 1e-3), 0, 1))
	elseif t <= windup + strike then
		return most
	end
	local u = math.clamp((t - windup - strike) / math.max(total - windup - strike, 1e-3), 0, 1)
	return most * (1 - smooth(math.clamp((u - 0.75) / 0.25, 0, 1)))
end

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
	local angle
	if W.twist then
		-- (Avatar) the roll is held against the near side of the forearm (a small circle there) while the forearm turns
		-- to and fro about its length, so the bandage winds on without the roll swinging up over the arm
		local swing = math.sin(s * W.turns * 2 * math.pi) * W.twist
		left = CFrame.new(W.wrist) * CFrame.fromAxisAngle(along, swing) * CFrame.new(-W.wrist) * left
		angle = W.slowAt + 2 * math.pi * s * W.turns * 2
	else
		local turn = s * W.turns
		local p = if s >= 1 then 0 else turn - math.floor(turn)
		angle = W.slowAt + 2 * math.pi * p - W.ease * math.sin(2 * math.pi * p)
	end
	local centre = W.wrist - along * W.at + (up * math.cos(angle) + near * math.sin(angle)) * W.radius
	if W.twist then
		centre += (up * math.cos(W.slowAt) + near * math.sin(W.slowAt)) * W.hold
	end
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

-- (Avatar) how much bandage is wound on the left forearm t seconds into the wrap (Rig:setWrap, studs): none until the
-- winding starts, then it grows to Poses.WRAP.band (nil: no band).
function Poses.wrapBand(t: number, duration: number): number
	local W = Poses.WRAP
	if not W.band then
		return 0
	end
	local k = math.clamp(t / math.max(duration, 0.1), 0, 1)
	if k <= W.start then
		return 0
	end
	return 0.04 + (W.band - 0.04) * math.clamp((k - W.start) / (W.stop - W.start), 0, 1)
end

-- The elbows' poles during a use (nil: Rig.POLE); the controller blends them in with the use. Poses.USE_POLE[style] =
-- { right = Vector3?, left = Vector3? } (bandaging: the left elbow out to the left, Poses.WRAP.pole).
Poses.USE_POLE = {} :: { [string]: { [string]: Vector3 } }
function Poses.usePole(style: string, side: string?): Vector3?
	if (side or "Left") == "Left" and style == "Wrap" then
		return Poses.WRAP.pole
	end
	local poles = Poses.USE_POLE[style]
	return poles and poles[if side == "Right" then "right" else "left"]
end

-- The right elbow's pole during melee swings and throws (nil: Rig.POLE.Right; a left jab mirrors it on the left arm),
-- blended in and out over the action by Poses.actionPoleWeight (the avatar arms swing with the elbow out to the side,
-- so the forearm stays off the hotbar).
Poses.SWING_POLE = nil :: Vector3?
function Poses.actionPoleWeight(t: number, total: number): number
	return math.sin(math.clamp(t / math.max(total, 1e-3), 0, 1) * math.pi) ^ 0.5
end

-- The med kit (Poses.MEDKIT, when it has values): the right hand holds it open in front, the left hand reaches into
-- it and presses what it takes to the body (out of view), MEDKIT.cycles times over the use.
local function medkitHands(t: number, duration: number, restLeft: CFrame): (CFrame, CFrame)
	local K = Poses.MEDKIT
	local k = math.clamp(t / math.max(duration, 0.1), 0, 1)
	local p = (k * K.cycles) % 1
	if K.oneHand then
		-- (Avatar) the kit up at the lower right, shaken as the other hand rummages in it out of view, then pressed to the
		-- chest (out of view below) and back
		local b = if p < 0.55 then 0 elseif p < 0.7 then smooth((p - 0.55) / 0.15) elseif p < 0.85 then 1 else 1 - smooth((p - 0.85) / 0.15)
		local shake = V(math.sin(t * 9) * 0.012, math.abs(math.sin(t * 6.5)) * 0.02, 0) * (1 - b)
		return K.kit:Lerp(K.press, b) + shake, restLeft
	end
	local left
	if p < 0.35 then
		left = K.press:Lerp(K.reach, smooth(p / 0.35))
	elseif p < 0.5 then
		left = K.reach
	elseif p < 0.8 then
		left = K.reach:Lerp(K.press, smooth((p - 0.5) / 0.3))
	else
		left = K.press
	end
	return K.kit + V(math.sin(t * 2.1) * 0.01, math.sin(t * 1.7) * 0.012, 0), left
end

-- Eating, bandaging with the med kit and putting on armor (t = seconds since the use began).
function Poses.use(style: string, t: number, restRight: CFrame, restLeft: CFrame, duration: number?): (CFrame, CFrame)
	if style == "Armor" then
		return armorHands(t, duration or 1.5, restRight, restLeft)
	elseif style == "Bandage" then
		if Poses.MEDKIT.kit then
			return medkitHands(t, duration or 5, restLeft)
		end
		local left = H(V(0.12, -0.88, -1.32), V(0.05, 1, 0.1), V(1, 0, -0.25))
		local angle = t * 8.5
		local around = V(0.02 + math.cos(angle) * 0.2, 0.02 + math.sin(angle) * 0.17, 0.06)
		local right = H(left.Position + around + V(0.32, 0.05, 0.1), V(-0.45, 0.7, -0.5), V(-1, -0.1, -0.3))
		return right, left
	end
	-- Eat: bites (EAT.bite: down to the mouth and back every EAT.biteEvery seconds), or a small chewing bob
	local E = Poses.EAT
	if E.bite then
		local p = (t / E.biteEvery) % 1
		local b = if p < 0.45 then smooth(p / 0.45) elseif p < 0.6 then 1 else 1 - smooth((p - 0.6) / 0.4)
		return E.hand:Lerp(E.bite, b), restLeft
	end
	return E.hand + V(0, math.abs(math.sin(t * 7)) * E.chew, 0), restLeft
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

-- Arm styles. ViewmodelController keeps Poses.useStyle(Rig.STYLE) current. The avatar arms are Roblox R15 arms: a
-- square hand block on a long forearm, not a fist on a thin sleeve, so most holds and actions have their own values
-- (Poses.AVATAR), placed by where the hand block is seen (A: its centre, Poses.AVATAR_HAND_AT along the knuckles from
-- the hand frame's origin) and kept within the arm's reach from Rig.AVATAR_SHOULDER, so the elbows bend instead of the
-- arms sliding about straight. They keep the hands and forearms off the hotbar (bottom centre) and the health meters
-- (bottom left): hands that work in front come in from the sides with the elbows out and low. useStyle("Avatar")
-- copies them over the values above, field by field (AVATAR.TOP: top-level values), and useStyle("Classic") puts the
-- originals back. Camera space at FOV 72: a point at screen (x, y) (-1..1) and depth d is (1.515 x d, 0.727 y d, -d).
Poses.STYLE = "Classic"
Poses.AVATAR_HAND_AT = 0.265
local function A(centre: Vector3, thumb: Vector3, knuckles: Vector3): CFrame
	local h = H(centre, thumb, knuckles)
	return h - h.LookVector * Poses.AVATAR_HAND_AT
end
Poses.avatarHand = A
local LOW_LEFT = Poses.HOLD.Blade.left -- (the free left hand, down out of view)
Poses.AVATAR = {
	HOLD = {
		Fists = { -- a loose guard: the fists up at the lower corners, the forearms rising into view from below
			right = A(V(0.88, -0.42, -1.35), V(-0.1, 0.85, 0.5), V(-0.15, 0.55, -0.8)),
			left = A(V(-0.74, -0.38, -1.35), V(0.1, 0.85, 0.5), V(0.15, 0.55, -0.8)),
		},
		Blade = { -- the blade upright at the lower right, leaning a little forward and in
			right = A(V(0.89, -0.5, -1.28), V(-0.25, 0.92, -0.3), V(-0.15, 0.35, -0.92)),
			left = LOW_LEFT,
		},
		Throwable = {
			right = A(V(0.85, -0.5, -1.25), V(0.02, 0.8, -0.6), V(-0.05, 0.6, -0.8)),
			left = LOW_LEFT,
		},
		Item = { -- held up at the lower right, the thing on the palm side, toward the middle of the view
			right = A(V(0.8, -0.44, -1.22), V(-0.15, 0.85, 0.5), V(-0.15, 0.5, -0.85)),
			left = LOW_LEFT,
		},
		Armor = { -- the vest held up by its collar at the right, hanging in view toward the middle
			right = A(V(1.0, -0.26, -1.3), V(0.05, -1, 0.05), V(-0.7, 0, -0.7)),
			left = LOW_LEFT,
		},
		-- the spear guard: the right hand at the hip (out of view), the shaft up through the left hand above the left
		-- end of the hotbar (Poses.SPEAR_LEFT) to the point at the left
		Spear = {
			right = H(V(0.63, -0.975, -0.667), V(-0.787, 0.198, -0.583), V(-0.2, -0.9, -0.35)),
			left = Poses.HOLD.Spear.left,
		},
		SpearRaised = { -- over the shoulder: the hand at the right edge (the arm out of view at the aim zoom), the shaft
			-- coming in level from it
			right = A(V(1.04, 0.14, -0.56), V(-0.1, 0, -1), V(0, 1, 0.1)),
			left = H(V(-0.75, -1.4, -0.8), V(0.12, 1, -0.2), V(0.15, -0.1, -1)),
		},
	},
	HOLD_ITEM = {
		bandage = { right = A(V(0.84, -0.4, -1.22), V(-0.15, 0.95, -0.25), V(-0.35, -0.25, -0.9)) },
		berries = { right = A(V(0.84, -0.42, -1.2), V(-0.12, 0.92, -0.38), V(-0.2, -0.3, -0.9)) },
		-- the bottle stands up beside the palm, left of the hand
		water_bottle = { right = A(V(1.08, -0.5, -1.25), V(-0.3, 0.95, 0.1), V(-0.15, 0.3, -0.95)) },
		empty_bottle = { right = A(V(1.08, -0.5, -1.25), V(-0.3, 0.95, 0.1), V(-0.15, 0.3, -0.95)) },
	},
	PUNCH = {
		left = {
			W = A(V(-0.84, -0.4, -1.2), V(0.2, 0.9, 0.4), V(0.2, 0.45, -0.85)),
			F = A(V(-0.36, -0.3, -1.5), V(0.95, 0.25, 0), V(0.1, 0.25, -1)),
		},
		right = {
			W = A(V(0.92, -0.42, -1.2), V(-0.2, 0.9, 0.4), V(-0.2, 0.45, -0.85)),
			F = A(V(0.36, -0.3, -1.5), V(-0.95, 0.25, 0), V(-0.1, 0.25, -1)),
		},
	},
	SWING = {
		Slash = {
			{ -- right to left, falling: from over the right shoulder, across above the hotbar, out low at the left, and
				-- back under the view (R) to the guard
				W = A(V(1.14, 0.04, -1.0), V(0.55, 0.75, 0.35), V(-0.8, -0.2, -0.55)),
				M = A(V(0.25, -0.29, -1.4), V(-0.6, 0.25, -0.75), V(-0.55, -0.5, 0.2)),
				F = A(V(-0.62, -1.15, -1.05), V(-0.85, -0.35, -0.4), V(-0.2, -0.9, 0.3)),
				R = A(V(0.45, -1.45, -0.75), V(-0.3, 0.4, 0.85), V(-0.2, -0.9, 0.3)),
			},
			{ -- right to left, flat: from out at the right, across at chest height, out low at the left (the arm never
				-- crosses the hotbar to wind up on the left)
				W = A(V(1.25, -0.22, -0.85), V(0.6, 0.45, 0.65), V(-0.6, -0.3, -0.7)),
				M = A(V(0.3, -0.33, -1.4), V(-0.85, 0.15, -0.5), V(-0.45, -0.6, 0.3)),
				F = A(V(-0.55, -1.12, -1.0), V(-0.8, -0.3, 0.2), V(-0.3, -0.9, 0.3)),
				R = A(V(0.45, -1.45, -0.75), V(-0.3, 0.4, 0.85), V(-0.2, -0.9, 0.3)),
			},
		},
	},
	-- one-handed thrust at the lower right (the left hand lets go of the shaft: Poses.STAB_LET_GO), the point driven in
	-- just under the crosshair
	STAB = {
		W = A(V(0.75, -0.5, -0.95), V(-0.068, -0.035, -1), V(-0.55, 0.55, -0.1)),
		M = A(V(0.78, -0.54, -1.15), V(-0.07, -0.03, -1), V(-0.55, 0.55, -0.1)),
		F = A(V(0.77, -0.57, -1.42), V(-0.073, -0.03, -1), V(-0.55, 0.55, -0.1)),
	},
	THROW = {
		knife = {
			W = A(V(0.82, 0.02, -0.55), V(0.1, 0.6, 0.8), V(0, 0.8, -0.6)),
			R = A(V(0.66, -0.26, -1.45), V(-0.05, 0.2, -1), V(0, -1, -0.2)),
			F = A(V(0.87, -1.05, -1.15), V(0, -0.6, -0.8), V(0, -0.8, 0.6)),
		},
		spear = {
			W = A(V(1.0, 0.05, -0.2), V(-0.06, 0.16, -1), V(0, 1, 0.15)),
			R = A(V(0.55, -0.21, -1.45), V(-0.05, 0.05, -1), V(0, 1, 0)),
			F = A(V(0.87, -1.05, -1.2), V(0, -0.55, -0.85), V(0, 0.8, -0.5)),
		},
	},
	-- eating: the hand comes up at the lower right, right of the hotbar, its palm (and the food on it) turned toward you;
	-- each bite takes the food down to the mouth (out of view below) and back
	EAT = {
		hand = A(V(0.79, -0.44, -1.0), V(0.89, 0.1, 0.44), V(0, 0.97, -0.22)),
		bite = A(V(0.42, -0.62, -0.62), V(0.89, 0.1, 0.44), V(0, 0.97, -0.22)),
		biteEvery = 0.55,
		lift = {},
	},
	-- drinking: the bottle tipped up toward the mouth, its neck going out of view at the bottom right of the hotbar and
	-- its base up at the right of the crosshair, the hand on its right side
	DRINK = {
		lips = V(0.4, -0.72, -0.9),
		yaw = 30,
		tilt0 = 50,
		tilt1 = 62,
		roll = 160,
		low = V(0.2, -0.55, 0.1),
	},
	-- bandaging (the roll): the left forearm held up at the lower left (between the meters and the hotbar), the right
	-- hand holding the roll against its near side while the forearm turns to and fro; the bandage builds up behind the
	-- wrist (Poses.wrapBand)
	WRAP = {
		wrist = V(-0.6, -0.44, -1.15),
		pole = V(-1, -0.6, 0.1),
		bend = V(0.1, -1.4, -0.1),
		palm = V(0.2, 0.6, 1),
		at = 0.22,
		radius = 0.05,
		hold = 0.38,
		slowAt = math.rad(140),
		twist = math.rad(55),
		turns = 2.5,
		band = 0.26,
		fist = V(0.3, -0.9, 0.2),
	},
	-- the med kit: held up open at the lower right with a rummaging shake, pressed to the chest (out of view below) twice
	MEDKIT = {
		kit = A(V(0.92, -0.42, -1.2), V(-0.45, 0.88, 0.15), V(-0.2, 0.3, -0.95)),
		press = A(V(0.78, -1.1, -0.6), V(-0.6, 0.6, 0.5), V(-0.3, 0.55, -0.8)),
		cycles = 2,
		oneHand = true,
	},
	-- putting on armor: the vest raised at the upper right, swung over the right shoulder (it leaves the view at the top
	-- right and is worn from then on), both hands come down at the sides and tug the hem twice at the bottom corners
	ARMOR = {
		lift = A(V(0.78, 0.15, -1.2), V(0.05, -1, 0.1), V(-0.8, 0.1, -0.5)),
		over = A(V(1.15, 1.3, 0.1), V(0.1, 0.2, 1), V(-0.3, 1, -0.2)),
		downRight = A(V(1.0, -1.2, -0.7), V(-0.2, 1, -0.2), V(-0.3, -0.2, -1)),
		downLeft = A(V(-1.0, -1.2, -0.7), V(0.2, 1, -0.2), V(0.3, -0.2, -1)),
		tugRight = A(V(1.0, -0.62, -1.2), V(-0.25, 0.85, -0.45), V(-0.15, 0.5, -0.88)),
		tugLeft = A(V(-1.0, -0.62, -1.2), V(0.25, 0.85, -0.45), V(0.15, 0.5, -0.88)),
		liftedAt = 0.25,
		overAt = 0.45,
		downAt = 0.58,
		tug0At = 0.66,
	},
	USE_POLE = {
		Bandage = { right = V(0.8, -1, 0) },
		Eat = { right = V(1, -0.6, 0) },
		Drink = { right = V(1, -0.6, 0) },
		Wrap = { right = V(1, -0.7, 0) },
	},
	TOP = {
		SPEAR_LEFT = V(-0.8, -0.6, -1.55),
		SPEAR_REACH = 1.6,
		STAB_LET_GO = 1,
		SPEAR_RAISE_LET_GO = 0.2,
		SWING_POLE = V(1, -0.6, 0.1),
		JITTER_PIVOT = V(0.6, -1.2, -0.4), -- (the shoulder the per-swing jitter turns a swing about)
	},
}
-- Faceted arms (Rig "Faceted"): world-scale arms from Rig.FACETED_SHOULDER (reach 1.8 studs to the wrist), a hand frame
-- whose origin is the wrist and whose -Z runs along the hand to the knuckles (Poses.facetedHand builds one from the way
-- the fingers point and the way the palm faces). A gripped item's axis leaves the thumb side, tilted 10 degrees toward
-- the knuckles (the faceted grip). Everything is kept off the hotbar (bottom centre) and the vitals (bottom left), and
-- the wrists within Rig.FACETED_MAX_WRIST of the forearms. Camera space at FOV 72 (16:9): a point at screen (x, y)
-- (-1..1) and depth d is (1.29 x d, 0.727 y d, -d).
local FH = Poses.facetedHand
local function FL(wrist: Vector3, fingers: Vector3, palm: Vector3): CFrame
	return FH(wrist, fingers, palm, true)
end
local F_LOW_LEFT = FL(V(-0.62, -1.25, -0.75), V(0.25, 0.3, -0.92), V(0.6, -0.8, 0)) -- (the free left hand, down out of view)
Poses.FACETED = {
	HOLD = {
		-- empty hands at rest: low in the bottom corners, the backs of the hands up, the fingers easy and pointing
		-- forward and a little in, the forearms below the view (the guard, Fists, only while punching)
		Relaxed = {
			right = FH(V(0.95, -0.78, -0.98), V(-0.1, -0.22, -0.97), V(-0.5, -0.85, 0.15)),
			left = FL(V(-0.95, -0.78, -0.98), V(0.1, -0.22, -0.97), V(0.5, -0.85, 0.15)),
		},
		-- the guard: fists up at the lower corners, knuckles forward, thumbs on top
		Fists = {
			right = H(V(0.78, -0.7, -1.08), V(-0.3, 0.95, 0.12), V(-0.22, 0.28, -0.94)),
			left = H(V(-0.78, -0.72, -1.1), V(0.3, 0.95, 0.12), V(0.22, 0.28, -0.94)),
		},
		-- the blade upright at the lower right, leaning a little forward
		Blade = {
			right = H(V(0.9, -0.66, -1.05), V(0.22, 1, -0.3), V(-0.12, 0.15, -1)),
			left = F_LOW_LEFT,
		},
		Throwable = {
			right = H(V(0.9, -0.66, -1.05), V(0.15, 0.85, -0.5), V(-0.12, 0.45, -0.88)),
			left = F_LOW_LEFT,
		},
		-- food on the open palm at the lower right, turned up toward you
		Item = {
			right = FH(V(0.92, -0.72, -1.1), V(-0.4, 0.3, -0.87), V(-0.35, 0.9, 0.25)),
			left = F_LOW_LEFT,
		},
		Armor = {
			right = H(V(0.86, -0.36, -1.15), V(0.05, -1, 0.05), V(-0.7, 0, -0.7)),
			left = F_LOW_LEFT,
		},
		Spear = {
			right = H(V(0.63, -0.95, -0.7), V(-0.74, 0.4, -0.54), V(-0.25, -0.88, -0.3)),
			left = Poses.HOLD.Spear.left,
		},
		SpearRaised = {
			right = H(V(0.86, 0.02, -0.5), V(-0.1, 0, -1), V(0, 1, 0.1)),
			left = F_LOW_LEFT,
		},
		-- the bow hand: the classic (avatar-arms) bow frames turned for the faceted grip, so the bow sits exactly where
		-- the clear-view check passed (classic frame x classic BOW_GRIP x faceted BOW_GRIP^-1)
		BowReady = {
			right = Poses.HOLD.BowReady.right,
			left = H(V(-0.671, -1.215, -1.379), V(-0.567, 0.822, -0.05), V(-0.135, -0.153, -0.979)),
		},
		BowDrawn = {
			right = Poses.HOLD.BowDrawn.right,
			left = H(V(-0.487, -0.917, -1.652), V(-0.442, 0.861, 0.25), V(-0.344, 0.095, -0.934)),
		},
		BowTucked = {
			right = Poses.HOLD.BowTucked.right,
			left = H(V(-0.673, -0.954, -0.763), V(-0.407, 0.83, 0.382), V(0.134, 0.468, -0.874)),
		},
	},
	HOLD_ITEM = {
		bandage = { right = FH(V(0.92, -0.7, -1.1), V(-0.35, 0.35, -0.87), V(-0.4, 0.88, 0.2)) },
		berries = { right = FH(V(0.92, -0.72, -1.1), V(-0.4, 0.3, -0.87), V(-0.35, 0.9, 0.25)) },
		-- the bottle stands in the open hand at the lower right, the palm against its side
		water_bottle = { right = FH(V(1.08, -0.74, -1.2), V(-0.12, 0.2, -0.97), V(-1, 0.05, 0.1)) },
		empty_bottle = { right = FH(V(1.08, -0.74, -1.2), V(-0.12, 0.2, -0.97), V(-1, 0.05, 0.1)) },
		-- the mace leans forward and out, so its head is in view at the upper right
		mace = { right = H(V(0.9, -0.7, -1.05), V(0.18, 0.8, -0.58), V(-0.15, 0.55, -0.82)) },
		hatchet = { right = H(V(0.9, -0.66, -1.05), V(0.2, 0.95, -0.3), V(-0.12, 0.3, -0.95)) },
		knife = { right = H(V(0.9, -0.66, -1.05), V(0.15, 0.85, -0.5), V(-0.12, 0.45, -0.88)) },
		-- the Ring Blade one-handed at the lower right, the hoop leaning forward and out, seen nearly edge-on, clear
		-- of the crosshair (ViewmodelController ONE_HAND_THROW)
		-- (the hoop's plane holds the thumb and the knuckles: both lie in the plane through the eye's line to the hand
		-- and the vertical, so the hoop is seen edge-on as a thin upright sliver)
		ring_blade = { right = H(V(1.0, -0.8, -1.1), V(0.32, 0.8, -0.51), V(0.42, -0.6, -0.68)) },
	},
	PUNCH = { -- jab (left), cross (right), hook (left): odd sets punch with the left
		{ -- 1 jab: the left fist straight out, left of the crosshair
			tp = "Jab", kick = V(-0.5, 0.8, 0.6), side = "Left",
			W = H(V(-0.520, -0.660, -0.850), V(0.300, 0.949, 0.100), V(0.110, 0.070, -0.992)),
			F = H(V(-0.420, -0.450, -1.450), V(0.966, 0.254, -0.051), V(-0.030, -0.084, -0.996)),
		},
		{ -- 2 cross: the right fist across, right of the crosshair
			tp = "Cross", kick = V(-0.5, -0.8, -0.6),
			W = H(V(0.520, -0.640, -0.830), V(-0.300, 0.949, 0.100), V(-0.110, 0.070, -0.992)),
			F = H(V(0.400, -0.440, -1.480), V(-0.966, 0.254, -0.051), V(0.029, -0.089, -0.996)),
		},
		{ -- 3 hook: the left fist swings in from the side, knuckles turning, under the crosshair
			tp = "Jab", kick = V(-0.3, -1, -0.7), side = "Left",
			W = H(V(-0.550, -0.600, -0.900), V(0.050, 0.998, 0.050), V(0.502, 0.018, -0.865)),
			M = H(V(-0.380, -0.380, -1.150), V(0.050, 0.998, 0.050), V(0.894, -0.022, -0.448)),
			F = H(V(-0.240, -0.420, -1.300), V(0.050, 0.998, 0.050), V(0.942, -0.064, 0.330)),
		},
	},
	-- Swing sets (#90, see "Swing sets" above), authored offline against the Faceted IK (the wrist within
	-- Rig.FACETED_MAX_WRIST) and checked against the mesh triangles: the blade and the arms stay out of the
	-- crosshair's 6 % circle at FOV 72 (with the per-swing jitter), nothing rests on the hotbar or the vitals
	-- (only the fast strike crosses them), and the way back passes under the view (R).
	SWING = {
		Slash = {
			{ -- 1 falling cut, right to left: from over the right shoulder, under the crosshair, out at the low left
				tp = "DownLeft", kick = V(-0.3, 1, 0.85),
				W = H(V(0.780, 0.074, -0.776), V(0.401, 0.595, 0.696), V(-0.493, 0.781, -0.384)),
				A = H(V(0.788, -0.108, -0.964), V(0.310, -0.359, -0.880), V(-0.305, 0.839, -0.450)),
				M = H(V(0.760, -0.468, -1.248), V(-0.958, -0.264, -0.107), V(-0.120, 0.716, -0.687)),
				B = H(V(0.410, -1.275, -1.322), V(-0.980, -0.199, 0.004), V(-0.037, 0.159, -0.987)),
				F = H(V(-0.390, -1.480, -1.138), V(-0.926, 0.092, 0.367), V(-0.379, -0.224, -0.898)),
				R = H(V(0.400, -1.050, -0.500), V(0.769, -0.224, -0.599), V(-0.307, 0.692, -0.653)),
			},
			{ -- 2 rising backhand, left to right: dropped under the view, up left of the hotbar, past the right of the crosshair
				tp = "Right", kick = V(0.5, -1, -0.85), pole = V(1, -0.4, 0.1),
				U = {
					H(V(0.700, -1.220, -1.072), V(0.842, -0.496, -0.212), V(-0.427, -0.372, -0.824)),
					H(V(-0.095, -1.389, -1.064), V(0.686, -0.674, -0.274), V(-0.705, -0.526, -0.475)),
				},
				W = H(V(-0.785, -1.914, -1.399), V(0.848, -0.369, -0.380), V(-0.524, -0.479, -0.704)),
				A = H(V(-0.955, -1.100, -1.465), V(0.953, 0.010, -0.302), V(-0.298, -0.129, -0.946)),
				M = H(V(0.461, -0.534, -1.355), V(0.902, 0.059, -0.427), V(-0.410, 0.427, -0.806)),
				B = H(V(0.915, -0.388, -1.254), V(0.898, 0.305, -0.316), V(-0.404, 0.294, -0.866)),
				F = H(V(0.928, 0.137, -0.967), V(0.545, 0.464, 0.698), V(-0.169, 0.877, -0.450)),
			},
			{ -- 3 high cut, right to left over the crosshair, the elbow out to the right
				tp = "Left", kick = V(0.1, 1, 0.4), pole = V(1, 0.1, 0),
				W = H(V(0.846, 0.277, -0.778), V(0.475, 0.473, 0.742), V(-0.320, 0.879, -0.355)),
				M = H(V(0.480, 0.436, -1.012), V(-0.957, -0.056, -0.284), V(0.048, 0.936, -0.349)),
				F = H(V(0.000, 0.501, -1.150), V(-0.797, 0.116, 0.593), V(-0.463, 0.512, -0.723)),
				R = H(V(0.988, 0.062, -0.850), V(0.451, 0.562, 0.694), V(-0.264, 0.826, -0.497)),
			},
			{ -- 4 overhead: straight down right of the crosshair
				tp = "Overhead", kick = V(-1, 0.05, 0.15),
				W = H(V(0.557, 0.832, -0.817), V(0.178, 0.344, 0.922), V(-0.143, 0.936, -0.322)),
				A = H(V(0.477, 0.535, -0.989), V(0.503, 0.757, -0.417), V(-0.839, 0.311, -0.447)),
				M = H(V(0.696, -0.070, -1.160), V(0.225, -0.347, -0.911), V(-0.237, 0.887, -0.396)),
				F = H(V(0.972, -0.952, -1.159), V(0.158, -0.872, 0.464), V(-0.294, -0.490, -0.821)),
				R = H(V(0.400, -1.050, -0.500), V(0.769, -0.224, -0.599), V(-0.307, 0.692, -0.653)),
			},
		},
		Chop = {
			{ -- 1 overhead: straight down right of the crosshair
				tp = "Overhead", kick = V(-1, 0, 0.25),
				W = H(V(0.394, 0.730, -0.450), V(0.138, 0.152, 0.979), V(-0.492, 0.868, -0.066)),
				A = H(V(0.561, 0.458, -0.803), V(0.176, 0.661, -0.730), V(-0.708, 0.600, 0.373)),
				M = H(V(0.649, -0.142, -1.132), V(0.138, -0.497, -0.857), V(-0.322, 0.796, -0.513)),
				F = H(V(0.778, -0.916, -1.104), V(0.255, -0.904, -0.343), V(-0.303, 0.262, -0.916)),
				R = H(V(0.400, -1.050, -0.500), V(0.769, -0.224, -0.599), V(-0.307, 0.692, -0.653)),
			},
			{ -- 2 right diagonal: from high at the right down across to the low left
				tp = "DownLeft", kick = V(-0.8, 0.7, 0.6),
				W = H(V(0.831, 0.347, -0.792), V(0.519, 0.458, 0.722), V(-0.331, 0.886, -0.324)),
				A = H(V(0.797, -0.023, -0.953), V(0.342, -0.293, -0.893), V(-0.288, 0.872, -0.396)),
				M = H(V(0.975, -0.934, -1.421), V(-0.831, -0.129, -0.541), V(0.503, 0.241, -0.830)),
				F = H(V(-0.110, -1.770, -1.314), V(-0.573, -0.731, 0.371), V(-0.270, -0.258, -0.928)),
				R = H(V(0.400, -1.050, -0.500), V(0.769, -0.224, -0.599), V(-0.307, 0.692, -0.653)),
			},
			{ -- 3 flat side chop from the right, under the crosshair
				tp = "Left", kick = V(-0.2, 1, 0.45),
				W = H(V(0.927, -0.087, -0.787), V(0.740, -0.023, 0.673), V(0.108, 0.991, -0.085)),
				A = H(V(0.918, -0.265, -1.024), V(0.374, -0.311, -0.874), V(-0.187, 0.897, -0.400)),
				M = H(V(1.072, -0.973, -1.420), V(-0.936, 0.288, 0.205), V(-0.177, 0.120, -0.977)),
				F = H(V(-0.078, -1.926, -1.470), V(-0.781, -0.426, 0.456), V(-0.222, -0.494, -0.841)),
				R = H(V(0.400, -1.050, -0.500), V(0.769, -0.224, -0.599), V(-0.307, 0.692, -0.653)),
			},
		},
		Smash = {
			{ -- 1 overhead
				tp = "Overhead", kick = V(-1, 0, 0.3),
				W = H(V(0.391, 0.732, -0.450), V(0.138, 0.153, 0.979), V(-0.494, 0.867, -0.065)),
				A = H(V(0.587, 0.473, -0.811), V(0.170, 0.657, -0.735), V(-0.673, 0.622, 0.401)),
				M = H(V(0.653, -0.133, -1.108), V(0.137, -0.497, -0.857), V(-0.317, 0.797, -0.513)),
				F = H(V(0.754, -0.855, -1.037), V(0.272, -0.897, -0.348), V(-0.399, 0.224, -0.889)),
				R = H(V(0.400, -1.050, -0.500), V(0.769, -0.224, -0.599), V(-0.307, 0.692, -0.653)),
			},
			{ -- 2 diagonal: from high at the right down across to the low left
				tp = "DownLeft", kick = V(-0.85, 0.5, 0.55),
				W = H(V(0.912, 0.380, -0.858), V(0.498, 0.457, 0.737), V(-0.211, 0.888, -0.409)),
				A = H(V(0.863, -0.001, -1.057), V(0.314, -0.328, -0.891), V(-0.190, 0.897, -0.398)),
				M = H(V(0.654, -0.446, -1.205), V(-0.650, -0.481, -0.588), V(-0.078, 0.812, -0.578)),
				F = H(V(-0.190, -1.502, -1.218), V(-0.548, -0.752, 0.366), V(-0.412, -0.138, -0.901)),
				R = H(V(0.400, -1.050, -0.500), V(0.769, -0.224, -0.599), V(-0.307, 0.692, -0.653)),
			},
		},
	},
	STAB = { -- straight, high, low (the left hand lets go for the thrust: STAB_LET_GO)
		{ -- 1 straight: the point drives in under the crosshair
			tp = "Thrust", kick = V(0.8, 0, 0.55),
			W = H(V(0.640, -0.820, -0.550), V(-0.006, -0.507, -0.862), V(-0.724, 0.596, -0.346)),
			M = H(V(0.620, -0.780, -0.950), V(0.156, -0.392, -0.907), V(-0.685, 0.619, -0.386)),
			F = H(V(0.600, -0.760, -1.350), V(0.190, -0.354, -0.916), V(-0.675, 0.630, -0.384)),
			R = H(V(0.620, -0.850, -0.800), V(-0.137, -0.478, -0.868), V(-0.725, 0.645, -0.241)),
		},
		{ -- 2 high: the point comes round under the crosshair, then rises past its right
			tp = "ThrustHigh", kick = V(0.9, -0.35, 0.3),
			U = H(V(0.660, -0.850, -0.550), V(-0.067, -0.531, -0.845), V(-0.734, 0.600, -0.319)),
			W = H(V(0.700, -0.750, -0.500), V(0.443, -0.284, -0.851), V(-0.572, 0.641, -0.512)),
			M = H(V(0.680, -0.620, -0.900), V(0.345, 0.004, -0.938), V(-0.665, 0.707, -0.242)),
			F = H(V(0.620, -0.540, -1.300), V(0.319, 0.101, -0.942), V(-0.691, 0.705, -0.158)),
			R = {
				H(V(0.660, -0.800, -0.800), V(0.341, -0.464, -0.818), V(-0.613, 0.550, -0.568)),
				H(V(0.640, -0.850, -0.750), V(-0.133, -0.504, -0.854), V(-0.730, 0.632, -0.260)),
			},
		},
		{ -- 3 low: the point drives in low
			tp = "ThrustLow", kick = V(0.3, 0.2, 0.6),
			W = H(V(0.620, -0.920, -0.550), V(-0.030, -0.579, -0.815), V(-0.739, 0.561, -0.372)),
			M = H(V(0.600, -0.920, -0.950), V(0.091, -0.507, -0.857), V(-0.708, 0.573, -0.413)),
			F = H(V(0.580, -0.920, -1.350), V(0.123, -0.479, -0.869), V(-0.698, 0.581, -0.419)),
			R = H(V(0.620, -0.900, -0.800), V(-0.158, -0.527, -0.835), V(-0.734, 0.629, -0.257)),
		},
	},
	THROW = {
		knife = {
			W = H(V(0.75, -0.05, -0.45), V(0.1, 0.6, 0.8), V(0, 0.8, -0.6)),
			R = H(V(0.5, -0.35, -1.35), V(-0.05, 0.2, -1), V(0, -1, -0.2)),
			F = H(V(0.7, -1.0, -1.0), V(0, -0.6, -0.8), V(0, -0.8, 0.6)),
		},
		spear = {
			W = H(V(0.85, 0.0, -0.15), V(-0.06, 0.16, -1), V(0, 1, 0.15)),
			R = H(V(0.5, -0.25, -1.35), V(-0.05, 0.05, -1), V(0, 1, 0)),
			F = H(V(0.7, -1.0, -1.05), V(0, -0.55, -0.85), V(0, 0.8, -0.5)),
		},
	},
	-- eating: the food comes up on the open palm at the lower right, each bite takes it down to the mouth (out of view)
	EAT = {
		hand = FH(V(0.85, -0.68, -1.0), V(-0.45, 0.35, -0.82), V(-0.3, 0.9, 0.3)),
		bite = FH(V(0.35, -0.85, -0.55), V(-0.5, 0.45, -0.75), V(-0.2, 0.7, 0.7)),
		biteEvery = 0.55,
		lift = {},
	},
	-- drinking: the bottle tipped up in front of the right of the crosshair, the hand round its far side and the forearm
	-- going down out of the lower right (roll 0: the hand behind the bottle, so the bottle is not hidden by the arm)
	DRINK = {
		lips = V(0.26, -0.86, -0.78),
		yaw = 25,
		tilt0 = 40,
		tilt1 = 52,
		roll = 0,
		low = V(0.2, -0.5, 0.1),
	},
	WRAP = {
		wrist = V(-0.5, -0.5, -1.0),
		pole = V(-1, -0.6, 0.1),
		bend = V(0.1, -1.2, -0.1),
		palm = V(0.2, 0.6, 1),
		at = 0.2,
		radius = 0.05,
		hold = 0.24,
		slowAt = math.rad(140),
		twist = math.rad(50),
		turns = 2.5,
		band = 0.22,
		fist = V(0.3, -0.9, 0.2),
	},
	MEDKIT = {
		kit = H(V(0.7, -0.62, -1.0), V(-0.45, 0.88, 0.15), V(-0.2, 0.3, -0.95)),
		press = H(V(0.55, -1.15, -0.55), V(-0.6, 0.6, 0.5), V(-0.3, 0.55, -0.8)),
		cycles = 2,
		oneHand = true,
	},
	ARMOR = {
		lift = H(V(1.0, 0.05, -1.3), V(0.05, -1, 0.1), V(-0.8, 0.1, -0.5)), -- the vest hangs at the right, clear of the hotbar
		over = H(V(0.95, 1.0, 0.15), V(0.1, 0.2, 1), V(-0.3, 1, -0.2)),
		downRight = H(V(0.8, -1.25, -0.6), V(-0.2, 1, -0.2), V(-0.3, -0.2, -1)),
		downLeft = H(V(-0.8, -1.25, -0.6), V(0.2, 1, -0.2), V(0.3, -0.2, -1)),
		tugRight = H(V(0.62, -0.8, -0.95), V(-0.25, 0.85, -0.45), V(-0.15, 0.5, -0.88)),
		tugLeft = H(V(-0.62, -0.8, -0.95), V(0.25, 0.85, -0.45), V(0.15, 0.5, -0.88)),
		liftedAt = 0.25,
		overAt = 0.45,
		downAt = 0.58,
		tug0At = 0.66,
	},
	USE_POLE = {
		Bandage = { right = V(0.8, -1, 0) },
		Eat = { right = V(1, -0.6, 0) },
		Drink = { right = V(1, -0.6, 0) },
		Wrap = { right = V(1, -0.7, 0) },
	},
	TOP = {
		SPEAR_LEFT = V(-0.72, -0.58, -1.4),
		SPEAR_REACH = 1.3,
		STAB_LET_GO = 1,
		SPEAR_RAISE_LET_GO = 0.2,
		SWING_POLE = V(0.5, -1, 0.25),
		JITTER_PIVOT = V(0.5, -0.72, 0.15), -- (the shoulder the per-swing jitter turns a swing about)
	},
}

Poses.STYLES = { Avatar = Poses.AVATAR, Faceted = Poses.FACETED }
local classicValues: { [string]: { [string]: any } } = {}
local NONE = {} -- (a field the Classic table didn't have)
-- Copies a style's values over the Classic ones, field by field (on), or puts the Classic values back (off).
local function applyStyle(values: { [string]: any }, on: boolean)
	for group, fields in pairs(values) do
		local target = if group == "TOP" then (Poses :: any) else (Poses :: any)[group]
		if type(target) == "table" then
			local saved = classicValues[group] or {}
			classicValues[group] = saved
			for key, value in pairs(fields) do
				if saved[key] == nil then
					saved[key] = if target[key] == nil then NONE else target[key]
				end
				if on then
					target[key] = value
				else
					local original = saved[key]
					target[key] = if original == NONE then nil else original
				end
			end
		end
	end
end
function Poses.useStyle(style: string)
	style = if Poses.STYLES[style] then style else "Classic"
	if style == Poses.STYLE then
		return
	end
	local current = Poses.STYLES[Poses.STYLE]
	if current then
		applyStyle(current, false)
	end
	Poses.STYLE = style
	local values = Poses.STYLES[style]
	if values then
		applyStyle(values, true)
	end
end

return Poses
