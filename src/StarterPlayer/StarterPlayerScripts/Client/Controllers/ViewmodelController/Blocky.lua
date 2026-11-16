--[[
	ViewmodelController.Blocky - the "Blocky" first-person arms (Config.Viewmodel.ArmStyle = "Blocky", the default).
	A sibling of Rig, which requires it (Rig.Blocky) and drives what it builds.

	Arms that plainly belong to a Roblox character: square, sharp-edged block limbs built here from Parts (no meshes,
	no textures, no uploads), the hands in the avatar's own arm colours, matte, lit by the engine only (no lamp, no
	Highlight, no shell). They sit on the FACETED SKELETON: the same joint lengths (0.95 / 0.85), the same hand frame
	(origin at the wrist joint, fingers along -Z) and the same Grip frame as the ArmsFaceted kit, so every Faceted pose,
	hold and swing set (Poses.FACETED) places a held item exactly where it does with the faceted arms.
	Rig drives them through its Faceted code path: Blocky.build returns what Rig's buildFaceted returns.

	Two hand variants (Config.Viewmodel.Blocky.Variant):
	  "A"  one block per hand (the default): 0.30 x 0.37 x 0.30 studs. The fist, the grip, the open hand and the
	       relaxed hand are the same block; what changes is where it is held. A gripped handle runs through the
	       block, food and bottles sit on its palm face.
	  "B"  a palm block (0.30 x 0.37 x 0.15), one four-finger block (0.30 x 0.24 x 0.15) hinged on the palm's front
	       edge, and a thumb block. Closed (Fist, Grip) the fingers fold onto the palm and the outline is A's block;
	       Relaxed curls them 38 degrees; Open lays them flat. One set of parts per shape; Rig:setHands swaps them.
	Sleeve (Config.Viewmodel.Blocky.Sleeve): "Jacket" (default; a 0.32 sleeve block to the wrist), "Short" (rolled up:
	the sleeve ends SleeveEnd studs from the elbow, bare forearm from there) or "Bare" (bare arm, sleeve colour unused).

	Piece space, as the Faceted kit (Rig.MESH_IN_HAND): +Y along the bone toward the fingers, +Z the palm side, +X the
	thumb side on the right arm; the left arm's pieces are X mirrors. Pivots: shoulder, elbow, wrist joint.
	The blocks' centre line runs PALM_SHIFT (0.09) to the palm side of the joints, so the Grip axis (0.1175 to the palm
	side, a 0.05-stud handle) passes through the middle of the hand block, not along its face.

	Blocky.build(parent, options?) -> arms, spec, info      options: values that replace Config.Viewmodel.Blocky's
	    arms[side] = { upper = piece, fore = piece, hands = { Relaxed, Fist, Grip, Open = piece }, hand = "Relaxed" }
	    piece = { model, parts, offsets, skins, sleeves, att }          (the shape Rig.placePiece / Rig:_rebuild read)
	    spec  = { upper, fore, grip = { Right, Left }, palm = { Right, Left }, handGrip, bowGrip, hook }   (Rig.useStyle)
	    info  = { variant, sleeve, sleeveWidth, palmShift, palmFromFaceted, ... }      (Rig keeps it as rig.blocky)
	Blocky.setSkin(arms, info, right: Color3, left: Color3?)      the hands (and bare forearms) in the arm colours
	Blocky.setExposure(arms, info, level)       0..1: every arm part's colour x level (albedo only: nothing is overlaid)
	Blocky.poses(Poses, info) -> style table    Poses.FACETED with the Blocky changes; the controller registers it as
	                                            Poses.STYLES.Blocky before Poses.useStyle("Blocky")
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Blocky = {}
Blocky.Options = (Config.Viewmodel and Config.Viewmodel.Blocky) or {} -- (swappable for Edit-mode previews)

local V3 = Vector3.new

-- The Faceted skeleton and frames (art/manifests/ArmsFaceted.manifest.json; Rig.lua FACETED_* and buildFaceted). Do
-- not change these without re-posing everything: they are what makes the Faceted poses transfer.
Blocky.UPPER = 0.95 -- shoulder to elbow
Blocky.FORE = 0.85 -- elbow to wrist joint
local GRIP_POS = V3(0.0131, 0.2573, 0.1175) -- R_HandGrip "Grip" (piece space)
local GRIP_LOOK = V3(0.9848, 0.1736, 0) -- the handle toward the thumb, tilted 10 degrees to the fingers
local GRIP_UP = V3(-0.1736, 0.9848, 0)
local PALM_Y = 0.18 -- the open hand's "Palm" attachment sits this far beyond the wrist
local FACETED_PALM_Z = 0.0631 -- ... and this far to the palm side on the Faceted hands
local HOOK_BELOW = 0.1 -- (Rig.FACETED_HOOK_BELOW)

-- The blocks (studs)
Blocky.ARM = 0.30 -- the hand block's cross-section: a square bar, like a Roblox limb
Blocky.SLEEVE = 0.32 -- the sleeve's cross-section: 0.01 proud of the hand all round (no coplanar faces)
Blocky.PALM_SHIFT = 0.09 -- the bar's centre line, to the palm side of the joints
Blocky.HAND_BACK = 0.03 -- the hand block starts this far behind the wrist joint, inside the sleeve's end
Blocky.HAND_LEN = 0.34 -- ... and ends this far beyond it (the Faceted fist's knuckles: 0.3225)
Blocky.ELBOW_PAD = 0.16 -- the upper arm and the forearm overlap this much round the elbow
Blocky.SLEEVE_END = 0.36 -- ("Short") the rolled-up sleeve ends this far from the elbow
Blocky.SKIN_INSET = 0.002 -- a bare forearm is this much slimmer than the hand per side (no coplanar faces)
-- variant B
Blocky.PALM_T = 0.15 -- the palm block's thickness (back of the hand to the palm face)
Blocky.FINGER_LEN = 0.24
Blocky.THUMB = V3(0.11, 0.21, 0.11)
-- per hand shape: the finger block's curl about the knuckle hinge (degrees; 0 flat, 180 folded onto the palm) and the
-- thumb: { splay out (degrees), shift to the palm side, shift forward }, or "Closed" (lying across the folded fingers)
Blocky.SHAPES = {
	Open = { curl = 6, thumb = { 38, 0, 0 } },
	Relaxed = { curl = 38, thumb = { 16, 0.03, 0 } },
	Grip = { curl = 180, thumb = "Closed" },
	Fist = { curl = 180, thumb = "Closed" },
}
local SHAPE_NAMES = { "Relaxed", "Fist", "Grip", "Open" } -- (Rig.HAND_SHAPES)

local PARKED = CFrame.new(0, -10000, 0)
local DEFAULT_SLEEVE = Color3.fromRGB(96, 88, 80) -- the Faceted kit's charcoal (ArtStyle rule 6: not darker)
local DEFAULT_SKIN = Color3.fromRGB(204, 158, 122)

-- hand space -> piece space, exactly Rig.MESH_IN_HAND
local MESH_IN_HAND = {
	Right = CFrame.fromMatrix(Vector3.zero, V3(0, 1, 0), V3(0, 0, -1)),
	Left = CFrame.fromMatrix(Vector3.zero, V3(0, -1, 0), V3(0, 0, -1)),
}
local GRIP_FLIP = CFrame.Angles(0, 0, math.pi)

local function option(options: { [string]: any }?, name: string, default: any): any
	local value = options and options[name]
	if value == nil then
		value = Blocky.Options[name]
	end
	if value == nil then
		return default
	end
	return value
end

-- A piece-space frame mirrored in X (the left arm).
local function mirrorX(cf: CFrame): CFrame
	local p, x, y, z = cf.Position, cf.XVector, cf.YVector, cf.ZVector
	return CFrame.fromMatrix(V3(-p.X, p.Y, p.Z), V3(x.X, -x.Y, -x.Z), V3(-y.X, y.Y, y.Z), V3(-z.X, z.Y, z.Z))
end

local function newPiece(parent: Instance, name: string): { [string]: any }
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return { model = model, parts = {}, offsets = {}, skins = {}, sleeves = {}, att = {} }
end

-- One block of a piece: `offset` is its centre frame in piece space (right arm; mirrored for the left).
local function addBlock(piece: { [string]: any }, look: { [string]: any }, name: string, offset: CFrame, size: Vector3, role: string)
	local skin = role == "Skin"
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Block
	p.Size = size
	p.Material = if skin then look.skinMaterial else look.sleeveMaterial
	local variantName = if skin then look.skinVariant else look.sleeveVariant
	if type(variantName) == "string" and variantName ~= "" then
		p.MaterialVariant = variantName
	end
	p.Reflectance = 0
	p.Color = if skin then look.skin else look.sleeve
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = look.castShadow
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = PARKED
	p:SetAttribute("Role", role)
	p.Parent = piece.model
	table.insert(piece.parts, p)
	table.insert(piece.offsets, if look.mirror then mirrorX(offset) else offset)
	if skin then
		table.insert(piece.skins, p)
	else
		table.insert(piece.sleeves, p)
	end
	return p
end

-- A block given by two opposite corners (piece space).
local function addBox(piece: { [string]: any }, look: { [string]: any }, name: string, lo: Vector3, hi: Vector3, role: string)
	return addBlock(piece, look, name, CFrame.new((lo + hi) / 2), hi - lo, role)
end

local function buildUpper(parent: Instance, look: { [string]: any }, prefix: string): { [string]: any }
	local piece = newPiece(parent, prefix .. "UpperArm")
	local h = Blocky.SLEEVE / 2 + 0.002 -- (a hair wider than the forearm's sleeve: no coplanar faces on a straight arm)
	local role = if look.sleeveMode == "Bare" then "Skin" else "Sleeve"
	addBox(piece, look, prefix .. "UpperArm_Block", V3(-h, -0.10, -h), V3(h, Blocky.UPPER + Blocky.ELBOW_PAD, h), role)
	return piece
end

local function buildFore(parent: Instance, look: { [string]: any }, prefix: string): { [string]: any }
	local piece = newPiece(parent, prefix .. "Forearm")
	local hs = Blocky.SLEEVE / 2
	local hk = Blocky.ARM / 2 - Blocky.SKIN_INSET
	local c = Blocky.PALM_SHIFT
	local pad, fore = Blocky.ELBOW_PAD, Blocky.FORE
	if look.sleeveMode == "Bare" then
		addBox(piece, look, prefix .. "Forearm_Skin", V3(-hk, -pad, c - hk), V3(hk, fore + 0.02, c + hk), "Skin")
	elseif look.sleeveMode == "Short" then
		local stop = math.clamp(look.sleeveEnd, 0.1, fore - 0.1)
		addBox(piece, look, prefix .. "Forearm_Skin", V3(-hk, stop - 0.05, c - hk), V3(hk, fore + 0.02, c + hk), "Skin")
		addBox(piece, look, prefix .. "Forearm_Sleeve", V3(-hs, -pad, c - hs), V3(hs, stop, c + hs), "Sleeve")
	else
		addBox(piece, look, prefix .. "Forearm_Sleeve", V3(-hs, -pad, c - hs), V3(hs, fore, c + hs), "Sleeve")
	end
	return piece
end

local function buildHand(parent: Instance, look: { [string]: any }, prefix: string, shape: string): { [string]: any }
	local piece = newPiece(parent, prefix .. "Hand" .. (if look.variant == "B" then shape else ""))
	local h = Blocky.ARM / 2
	local z0, z1 = Blocky.PALM_SHIFT - h, Blocky.PALM_SHIFT + h
	local back, len = Blocky.HAND_BACK, Blocky.HAND_LEN
	if look.variant ~= "B" then
		addBox(piece, look, prefix .. "Hand_Block", V3(-h, -back, z0), V3(h, len, z1), "Skin")
		return piece
	end
	local zp = z0 + Blocky.PALM_T -- the palm face
	addBox(piece, look, prefix .. "Hand_Palm", V3(-h, -back, z0), V3(h, len, zp), "Skin")
	local s = Blocky.SHAPES[shape] or Blocky.SHAPES.Fist
	-- the four-finger block, hinged along X on the palm's front edge, palm side
	local hinge = CFrame.new(0, len, zp) * CFrame.Angles(math.rad(s.curl), 0, 0)
	addBlock(piece, look, prefix .. "Hand_Fingers", hinge * CFrame.new(0, Blocky.FINGER_LEN / 2, -Blocky.PALM_T / 2),
		V3(Blocky.ARM, Blocky.FINGER_LEN, Blocky.PALM_T), "Skin")
	local thumb = s.thumb
	if thumb == "Closed" then
		addBox(piece, look, prefix .. "Hand_Thumb", V3(0.04, 0.08, z1), V3(h, 0.30, z1 + 0.06), "Skin")
	elseif type(thumb) == "table" then
		local t = Blocky.THUMB
		local base = CFrame.new(h, 0.05 + thumb[3], z0 + thumb[2]) * CFrame.Angles(0, 0, -math.rad(thumb[1]))
		addBlock(piece, look, prefix .. "Hand_Thumb", base * CFrame.new(t.X / 2, t.Y / 2, t.Z / 2), t, "Skin")
	end
	return piece
end

-- The open hand's palm face in piece space: the block's palm face for A, the palm block's face for B.
local function palmZ(variant: string): number
	local z0 = Blocky.PALM_SHIFT - Blocky.ARM / 2
	return if variant == "B" then z0 + Blocky.PALM_T else z0 + Blocky.ARM
end

function Blocky.build(parent: Instance, options: { [string]: any }?): ({ [string]: any }, { [string]: any }, { [string]: any })
	local variant = if option(options, "Variant", "A") == "B" then "B" else "A"
	local sleeveMode = option(options, "Sleeve", "Jacket")
	if sleeveMode ~= "Bare" and sleeveMode ~= "Short" then
		sleeveMode = "Jacket"
	end
	local skinMaterial = option(options, "SkinMaterial", Enum.Material.SmoothPlastic)
	local sleeveMaterial = option(options, "SleeveMaterial", Enum.Material.Fabric)
	local sleeveColor = option(options, "SleeveColor", DEFAULT_SLEEVE)
	local info = {
		variant = variant,
		sleeve = sleeveMode,
		sleeveWidth = Blocky.SLEEVE,
		palmShift = Blocky.PALM_SHIFT,
		-- how far the palm face is from the Faceted hands' (the open-hand poses move the wrist back by this)
		palmFromFaceted = palmZ(variant) - FACETED_PALM_Z,
		sleeveColor = if typeof(sleeveColor) == "Color3" then sleeveColor else DEFAULT_SLEEVE,
		skinMax = math.clamp(tonumber(option(options, "SkinMaxValue", 0.92)) or 0.92, 0.5, 1),
		skin = { Right = DEFAULT_SKIN, Left = DEFAULT_SKIN },
		level = 1,
	}
	-- shadows: Config.Viewmodel.Blocky.CastShadow, else the shared Config.Viewmodel.ArmShadows (off)
	local castShadow = option(options, "CastShadow", nil)
	if castShadow == nil then
		castShadow = Config.Viewmodel and Config.Viewmodel.ArmShadows
	end
	castShadow = castShadow == true
	local arms = {}
	for _, side in ipairs({ "Right", "Left" }) do
		local look = {
			variant = variant,
			sleeveMode = sleeveMode,
			sleeveEnd = tonumber(option(options, "SleeveEnd", Blocky.SLEEVE_END)) or Blocky.SLEEVE_END,
			skinMaterial = if typeof(skinMaterial) == "EnumItem" then skinMaterial else Enum.Material.SmoothPlastic,
			sleeveMaterial = if typeof(sleeveMaterial) == "EnumItem" then sleeveMaterial else Enum.Material.Fabric,
			skinVariant = option(options, "SkinMaterialVariant", nil),
			sleeveVariant = option(options, "SleeveMaterialVariant", nil),
			skin = DEFAULT_SKIN,
			sleeve = info.sleeveColor,
			castShadow = castShadow,
			mirror = side == "Left",
		}
		local prefix = if side == "Right" then "R_" else "L_"
		local arm = { upper = buildUpper(parent, look, prefix), fore = buildFore(parent, look, prefix), hands = {}, hand = "Relaxed" }
		if variant == "B" then
			for _, shape in ipairs(SHAPE_NAMES) do
				arm.hands[shape] = buildHand(parent, look, prefix, shape)
			end
		else
			local hand = buildHand(parent, look, prefix, "Fist") -- one block: every shape is this piece
			for _, shape in ipairs(SHAPE_NAMES) do
				arm.hands[shape] = hand
			end
		end
		arms[side] = arm
	end
	-- the frames Rig.useStyle needs (as buildFaceted makes them from the kit's attachments)
	local spec = { upper = Blocky.UPPER, fore = Blocky.FORE, grip = {}, palm = {} }
	local palm = CFrame.lookAt(V3(0, PALM_Y, palmZ(variant)), V3(0, PALM_Y, palmZ(variant) + 1), Vector3.yAxis)
	for _, side in ipairs({ "Right", "Left" }) do
		local s = if side == "Right" then 1 else -1
		local at = V3(GRIP_POS.X * s, GRIP_POS.Y, GRIP_POS.Z)
		local grip = CFrame.lookAt(at, at + V3(GRIP_LOOK.X * s, GRIP_LOOK.Y, 0), V3(GRIP_UP.X * s, GRIP_UP.Y, 0))
		local handGrip = MESH_IN_HAND[side] * grip
		spec.grip[side] = handGrip * GRIP_FLIP
		spec.palm[side] = MESH_IN_HAND[side] * palm
		if side == "Right" then
			spec.handGrip = handGrip
		else
			spec.bowGrip = handGrip -- the bow: top limb along the thumb, shooting toward the knuckles
		end
	end
	spec.hook = spec.handGrip.Position + V3(0, tonumber(option(options, "HookBelow", HOOK_BELOW)) or HOOK_BELOW, 0)
	return arms, spec, info
end

-- Every piece of an arm once (variant A shares one hand piece between the four shapes).
local function eachPiece(arm: { [string]: any }, fn: ({ [string]: any }) -> ())
	local seen = {}
	local list = { arm.upper, arm.fore }
	for _, shape in ipairs(SHAPE_NAMES) do
		table.insert(list, arm.hands[shape])
	end
	for _, piece in ipairs(list) do
		if piece and not seen[piece] then
			seen[piece] = true
			fn(piece)
		end
	end
end

-- A skin colour kept under info.skinMax in its brightest channel, so white and near-white arms stay below the bloom
-- threshold in full sun (DayCycle: Bloom threshold 1.8 by day, 1.3 at night).
local function capped(color: Color3, most: number): Color3
	local m = math.max(color.R, color.G, color.B)
	if m > most and m > 0 then
		local k = most / m
		return Color3.new(color.R * k, color.G * k, color.B * k)
	end
	return color
end

local function scaled(color: Color3, level: number): Color3
	return Color3.new(color.R * level, color.G * level, color.B * level)
end

local function paint(arms: { [string]: any }, info: { [string]: any })
	local level = info.level
	for _, side in ipairs({ "Right", "Left" }) do
		local skin = scaled(capped(info.skin[side], info.skinMax), level)
		local sleeve = scaled(info.sleeveColor, level)
		eachPiece(arms[side], function(piece)
			for _, p in ipairs(piece.skins) do
				p.Color = skin
			end
			for _, p in ipairs(piece.sleeves) do
				p.Color = sleeve
			end
		end)
	end
end

function Blocky.setSkin(arms: { [string]: any }, info: { [string]: any }, right: Color3, left: Color3?)
	info.skin.Right = right
	info.skin.Left = left or right
	paint(arms, info)
end

-- level 0..1: the arms at that share of their lit brightness, by colour alone.
function Blocky.setExposure(arms: { [string]: any }, info: { [string]: any }, level: number)
	level = math.clamp(level, 0, 1)
	if math.abs(level - info.level) < 0.004 then
		return
	end
	info.level = level
	paint(arms, info)
end

-- The Blocky pose style: Poses.FACETED, group by group, with these changes.
--   HOLD.Relaxed      empty hands at rest: thumbs up, forearms in from the bottom corners (B: backs up, lower)
--   HOLD.Fists        the guard, narrower than the Faceted one: on a 16:9 screen the left fist stays off the vitals
--   HOLD.SpearRaised  the hand outside the view (a block that near the eye would fill the right edge)
--   open-hand frames  the hand under everything Rig.FACETED_HAND holds on the open palm (apple, berries, ration, the
--                     bottles, the bandage roll) and the eating frames are moved back by info.palmFromFaceted along the
--                     palm's normal, so the thing on the palm stays where the Faceted pose shows it. What is gripped
--                     (dried meat, herbs, the med kit) keeps the Faceted frames.
--   WRAP.hold         the bandage roll further from the forearm's axis (the sleeve block is wider than the Faceted
--                     forearm).
--   TOP.GUARD_DIP     (A) hardly any dip when the guard drops: there is no hand shape to swap out of sight
function Blocky.poses(Poses: any, info: { [string]: any }): { [string]: any }
	local H, FH = Poses.hand, Poses.facetedHand
	local base = Poses.FACETED
	local out = {}
	for group, fields in pairs(base) do
		out[group] = table.clone(fields)
	end
	local function V(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z)
	end
	if info.variant == "B" then
		out.HOLD.Relaxed = {
			right = FH(V(0.92, -0.92, -1.05), V(-0.10, -0.40, -0.97), V(-0.5, -0.85, 0.15)),
			left = FH(V(-0.92, -0.92, -1.05), V(0.10, -0.40, -0.97), V(0.5, -0.85, 0.15), true),
		}
	else
		out.HOLD.Relaxed = {
			right = H(V(0.78, -0.92, -0.95), V(-0.25, 0.95, 0.15), V(-0.12, -0.12, -0.98)),
			left = H(V(-0.78, -0.92, -0.95), V(0.25, 0.95, 0.15), V(0.12, -0.12, -0.98)),
		}
	end
	out.HOLD.Fists = {
		right = H(V(0.70, -0.72, -1.08), V(-0.3, 0.95, 0.12), V(-0.22, 0.28, -0.94)),
		left = H(V(-0.70, -0.74, -1.10), V(0.3, 0.95, 0.12), V(0.22, 0.28, -0.94)),
	}
	out.HOLD.SpearRaised = {
		right = H(V(1.02, 0.05, -0.36), V(-0.1, 0, -1), V(0, 1, 0.1)),
		left = base.HOLD.SpearRaised.left,
	}
	-- The right palm faces hand -X: moving the hand frame along its own +X takes the wrist back from the palm.
	-- OPEN_ITEMS: the items Rig.FACETED_HAND holds on the open hand (keep the two lists the same).
	local back = CFrame.new(info.palmFromFaceted, 0, 0)
	for _, id in ipairs({ "apple", "berries", "ration", "water_bottle", "empty_bottle", "bandage" }) do
		local own = base.HOLD_ITEM[id]
		local right = (own and own.right) or base.HOLD.Item.right
		out.HOLD_ITEM[id] = { right = right * back, left = own and own.left }
	end
	out.EAT.hand = base.EAT.hand * back
	if base.EAT.bite then
		out.EAT.bite = base.EAT.bite * back
	end
	-- food that is gripped, not laid on the palm, is put back where the Faceted frames hold it (Poses.EAT.lift: a
	-- camera-space offset per item, added by Poses.applyUse)
	local undo = base.EAT.hand.Position - out.EAT.hand.Position
	out.EAT.lift = table.clone(base.EAT.lift or {})
	for _, id in ipairs({ "dried_meat", "herbs" }) do
		out.EAT.lift[id] = (out.EAT.lift[id] or Vector3.zero) + undo
	end
	out.WRAP.hold = 0.40
	if info.variant ~= "B" then
		out.TOP.GUARD_DIP = V(0, -0.10, 0.03)
	end
	return out
end

return Blocky
