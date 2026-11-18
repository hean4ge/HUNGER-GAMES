--[[
	ViewmodelController.Rig - builds and places the first-person arms and the held item. Holds no game state, so it
	can be previewed in Edit mode. Every part is Anchored, CanCollide / CanQuery / CanTouch = false, CastShadow = false
	(avatar arms: Config.Viewmodel.ArmShadows), and all of them are moved together with one workspace:BulkMoveTo per frame.

	Four arm styles (Config.Viewmodel.ArmStyle), posed with the same two-bone IK on the same hand frames:
	- "Blocky" (default): Roblox block arms built from Parts by the sibling module Blocky (Rig.Blocky; no meshes, no
	  uploads) on the Faceted skeleton and frames, so they are driven by the Faceted code below (rig.faceted holds their
	  pieces, rig.blocky their settings) and take every Faceted pose. Their rig holds the arm blocks, the bandage band
	  and the held item only (no part-built arms, no key light, no Highlight). One block per hand (variant A) or a palm, a
	  four-finger block and a thumb (variant B, swapped per shape by rig:setHands). Matte, lit by the engine only: no
	  key light, no Highlight (rig:setExposure works on their colours), no shade layer.
	- "Faceted": bare hands and forearms built from chunky flat facets with a charcoal sleeve, the Blender kit
	  in ReplicatedStorage.Assets.Viewmodel.ArmsFaceted (ServerStorage.WorldGen.ArmsFacetedAssets; art/README.md section
	  12) at world scale. Per side an UpperArm (shoulder pivot), a Forearm (elbow pivot) and four hands (wrist pivot), one
	  shown at a time (rig:setHands): Relaxed (empty hands at rest), Fist (only while punching), Grip (closed round a
	  handle or the bow string) and Open (food and bottles on the palm). The hand frame's origin is the wrist joint; a
	  held item's Grip goes on the Grip hand's own grip frame (Rig.GRIP), food on the Open hand's palm (Rig.PALM). The skin
	  takes the avatar's arm colours through SurfaceAppearance.Color (rig:setSkin). The forearm turns with the hand, so
	  the wrist ring lines up; the elbow turns toward where the forearm would line up with the hand (Rig.AUTO_POLE) and
	  any bend past Rig.MAX_WRIST is taken out of the hand, so the faceted wrist (good to about 30 degrees) never folds.
	- "Avatar": the player's own R15 arms. rig:setAvatar(character) clones the character's UpperArm, LowerArm
	  and Hand MeshParts (meshes, sizes, colours, any SurfaceAppearance) into a Model "AvatarArms" with a Humanoid and the
	  character's Shirt and arm colours (BodyColors), so the engine draws the shirt on them, at Config.Viewmodel.ArmScale
	  of their size (a full-size Roblox hand would fill the view and cover the crosshair at the bow grip). R6 avatars,
	  missing rig attachments and arms far from Roblox proportions get the standard R15 arms
	  (ReplicatedStorage.Assets.Viewmodel.StandardArms) in the avatar's colours. The IK lengths are the measured joint
	  distances (Rig.useStyle). The hand sits on the hand frame with its wrist joint Rig.WRIST down the fingers, so a held
	  item's Grip is inside it; the forearm runs from the elbow to that wrist with its front turned to the thumb; the
	  upper arm from the shoulder to the elbow, its front toward the bend. A hand out of reach pulls the shoulder (never
	  in view) toward it, so every hand frame is met exactly. Lit like the world: Config.Viewmodel.ArmMaterial.
	- "Classic": the original part-built arms: per side an upper-arm and a forearm sleeve (Cylinders, dark Fabric), a
	  Ball elbow, a Cuff, and a fist of SmoothPlastic blocks in the skin colour of the character's hands.
	(The Blender mesh arms in ReplicatedStorage.Assets.Viewmodel are not used.) The held items are the
	Blender meshes from ItemModels: the view bow's string is two Beams through its Nock attachment and its nock bead
	(parts with attribute FollowsNock) moves with the Nock; the nocked arrow lies on the bow's ArrowRest attachment with
	its own Nock on the string. In the view the arrow rides on the camera side of the riser (Rig.ARROW_SIDE, on the
	bow hand's thumb) so the shaft and the arrowhead stay visible past the bow hand (with the bow canted to the upper
	left that is also the riser's upper side, where an arrow rests). rig:updateView keeps the string about
	Rig.STRING_PX pixels wide at every depth, so where it passes close to the eye at full draw it stays a thin line
	instead of a flat pale band.
	Rig.straightWrist turns a hand so its wrist is in line with the forearm the IK will give it (the drawing hand on the
	bow string, the hand tipping a bottle), keeping one point of the hand (the string hook, the grip) where it is.

	Hand space: origin at the wrist, fingers along -Z, thumb along +Y; the right palm faces -X (the left one +X).
	Items follow the ItemModels convention: their Grip attachment is placed on Rig.GRIP, so the business end (Grip
	LookVector) runs out of the thumb side of the fist and a blade's cutting edge (-Grip.UpVector) faces the knuckles.
	A bow sits in the left hand on Rig.BOW_GRIP: top limb along the thumb, shooting toward the knuckles.
	Rig.ITEM_HOLD[itemId] moves an item within the fist (things wider than the fist sit in it on the palm side).

	Rig.new(skinColor?, style?, armOptions?) -> rig    rig.model: parent it to the camera to show it; style "Blocky" |
	                                      "Faceted" | "Avatar" | "Classic" (rig.style: the style it got; Faceted falls
	                                      back to Avatar without its templates); armOptions: (Blocky) values that replace
	                                      Config.Viewmodel.Blocky's (Variant, Sleeve, ...)
	rig:setSkin(color, leftColor?)                  the Classic fists, the Faceted and Blocky skin (each side its arm colour)
	rig:setHands(right?, left?)                     (Faceted, Blocky) the hand shapes: "Relaxed" | "Fist" | "Grip" | "Open"
	rig:setFloor(floor)                             (Blocky) dark arm colours lifted to at least this (night, open sky)
	rig:itemHand() -> "Grip" | "Open" | nil         (Faceted) the hand mesh the held item wants
	rig:setAvatar(character?) -> "Avatar" | "Standard" | "Classic"   (Avatar style) the arms from that character
	Rig.avatarSignature(character?) -> string       changes when its arms, shirt or arm colours change
	Rig.useStyle(style, spec?)                      swaps the module's arm constants (setAvatar calls it)
	rig:setItem(itemId?, hand: "Right" | "Left")    ItemModels.build(itemId, "view"), held by that hand
	rig:setArrow(enabled)                           a nocked arrow model for the bow
	rig:setItemHidden(hidden) / rig:setArrowHidden(hidden)
	rig:handleFrame(handFrame) -> CFrame?           the item's Handle frame for a hand frame (any space)
	rig:point(name, handleFrame) -> Vector3?        an item attachment (Tip, Nock, ...) for that Handle frame
	rig:setDraw(studs)                              pulls the bow string back (moves the Nock attachment)
	rig:arrowFrame(handleFrame) -> CFrame?          the nocked arrow's Grip frame (nock on the string, on the shelf)
	rig:pose(frame)   frame = { right, left = hand frames (world), shoulderRight, shoulderLeft, poleRight, poleLeft,
	                            up = Vector3, arrow = CFrame? (arrow Grip frame, world), eye = Vector3? (the camera's
	                            position: the block arms' upper arm fades out when its elbow is right beside it) }
	rig:updateView(cameraCFrame, fieldOfView, viewportHeight)   after pose: sizes the bow string for the camera
	Rig.solveArm(shoulder, target, pole) -> (elbow, wrist)       the two-bone IK the arms use
	Rig.straightWrist(hand, pivot, up, strictUp, shoulder, pole) -> CFrame   see above
	rig:muzzle() -> Vector3?   where a shot leaves the weapon (nocked arrow tip, spear tip, or the held item)
	rig:destroy()
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Config = require(Shared:WaitForChild("Config"))

-- The "Blocky" arms' builder, colours and pose style: the sibling module ViewmodelController.Blocky (a Rig cloned on its
-- own, without its parent, has none: it then builds the older arms)
local blockyModule = if script.Parent then script.Parent:WaitForChild("Blocky", 10) else nil
local Blocky = if blockyModule then require(blockyModule) else nil

local Rig = {}
Rig.__index = Rig
Rig.Blocky = Blocky
Rig.ItemModels = ItemModels -- swappable for Edit-mode previews
Rig.Options = Config.Viewmodel or {} -- (Config.Viewmodel; swappable for Edit-mode previews)

Rig.UPPER_ARM = 1.3
Rig.FOREARM = 1.2
-- Camera-space shoulders and elbow pole directions (the controller moves them with the whole viewmodel).
Rig.SHOULDER = { Right = Vector3.new(0.85, -1.0, 0.25), Left = Vector3.new(-0.85, -1.0, 0.25) }
Rig.POLE = { Right = Vector3.new(0.6, -1, 0.25), Left = Vector3.new(-0.6, -1, 0.25) }
-- While the right hand is on a bow string the elbow goes out to the right (low), so the forearm comes in diagonally
-- from the lower right instead of standing straight up from the bottom of the view; as the string comes back to the
-- anchor the elbow swings back behind the shoulder line (BowRightDrawn), out of view. The controller blends the two
-- by how far the string is drawn.
Rig.POLE.BowRight = Vector3.new(2, -1, -0.2)
Rig.POLE.BowRightDrawn = Vector3.new(0.8, -0.6, 1)
Rig.GRIP_POINT = { Right = Vector3.new(-0.07, 0, -0.29), Left = Vector3.new(0.07, 0, -0.29) }
local TO_GRIP = CFrame.Angles(math.rad(90), 0, 0) -- hand +Y (thumb) becomes the Grip LookVector, knuckles its -UpVector
Rig.GRIP = {
	Right = CFrame.new(Rig.GRIP_POINT.Right) * TO_GRIP,
	Left = CFrame.new(Rig.GRIP_POINT.Left) * TO_GRIP,
}
Rig.BOW_GRIP = CFrame.new(Rig.GRIP_POINT.Left) * CFrame.Angles(0, math.pi, 0) * TO_GRIP
-- Where the right hand's fingers hook the bow string (hand space): at the knuckle end, on the edge of the fist that
-- faces the bow's top limb (the controller turns the thumb toward the bottom limb), so the fist hangs under the
-- string and arrow and stays out of view at the under-chin anchor.
Rig.HOOK = Vector3.new(-0.08, -0.1, -0.45)
-- View bow: the nocked arrow's rest point, sideways in Handle space (the mesh ArrowRest is at X = 0.04, inside the
-- riser's width, so from the eye the riser hid the arrowhead). -0.13 puts the shaft against the riser's camera side.
Rig.ARROW_SIDE = -0.13
Rig.NOCK_STRING_WIDTH = 0.005 -- the view string's width at the nock end (the mesh beams are 0.012 everywhere)
Rig.STRING_PX = 1.8 -- rig:updateView: the view string's on-screen width in pixels
Rig.STRING_MIN_WIDTH = 0.0006
Rig.STRING_MAX_WIDTH = 0.012 -- a real string's thickness (the mesh beams' width)

-- Arm style. The arm constants above are the Classic arms'; Rig.useStyle swaps in an avatar's measured arms
-- (rig:setAvatar) and puts them back, for every user of Rig (the controller and Poses read them every frame).
Rig.STYLE = "Classic"
Rig.WRIST = Vector3.zero -- the arm's wrist joint in hand space (Avatar: down the hand, so a held item's grip is in it)
Rig.REACH_DRAG = false -- (Avatar) a hand out of reach pulls the shoulder (never in view) toward it ...
Rig.DRAG_MAX = 0.3 -- ... by up to this much; further out the hand stops short of its frame (the item stays in it)
-- (Avatar) The wrist. The elbow turns from the pose's pole toward where the forearm would line up with the hand (by
-- Rig.AUTO_POLE of the angle between them), a free hand (not frame.lock[side]) turns about its thumb (the held item's
-- axis, so the item keeps pointing where it did) to meet the forearm, and any bend left past Rig.MAX_WRIST is taken out
-- by turning the hand about the wrist toward the forearm. So no pose folds the hand back on the arm.
Rig.AUTO_POLE = 0
Rig.AVATAR_AUTO_POLE = 0.25
Rig.AVATAR_HAND_LOCK_POLE = 0.6 -- (the auto pole for a hand that may not turn, frame.lock[side] = "hand")
Rig.MAX_WRIST = math.rad(58)
Rig.MAX_TWIST = 0 -- (off: turning a blade about its axis showed its flat to the eye; the elbow and the limit suffice)
Rig.MAX_POLE_SWING = math.rad(40) -- the most the auto pole turns the elbow away from the pose's own pole
-- Avatar arms: the camera-space shoulders they hang from (before any pull), how far down the R15 hand a held item's
-- grip point sits (0 = wrist joint, 1 = fingertips) and how far back from the fingertips the bow string is hooked.
Rig.AVATAR_SHOULDER = { Right = Vector3.new(0.6, -1.2, -0.4), Left = Vector3.new(-0.6, -1.2, -0.4) }
Rig.AVATAR_GRIP_AT = 0.6
Rig.AVATAR_HOOK_IN = 0.05
-- (the avatar elbows hang under the hands, so the forearms rise into view from the bottom edge; the string hand's elbow
-- hangs lower still, so the wider avatar forearm stays below the hotbar at the low ready)
Rig.AVATAR_POLE = { Right = Vector3.new(0.25, -1, 0), Left = Vector3.new(-0.25, -1, 0), BowRight = Vector3.new(0.5, -1, 0.3) }
-- Faceted arms: the camera-space shoulders they hang from (before any pull, Rig.REACH_DRAG), the elbow poles, the wrist
-- limit (the faceted wrist is modelled for bends up to about 30 degrees), how far the elbow turns toward a straight
-- wrist (free hands, and hands that may not turn: frame.lock[side] = "hand") and how far below the nock the drawing
-- hand's grip sits on the bow string (toward the bottom limb: three fingers under the arrow).
Rig.FACETED_SHOULDER = { Right = Vector3.new(0.5, -0.72, 0.15), Left = Vector3.new(-0.5, -0.72, 0.15) }
Rig.FACETED_POLE = {
	Right = Vector3.new(0.45, -1, 0.1),
	Left = Vector3.new(-0.45, -1, 0.1),
	BowRight = Vector3.new(1.2, -1, 0),
	BowRightDrawn = Vector3.new(0.8, -0.6, 1),
}
Rig.FACETED_MAX_WRIST = math.rad(34)
Rig.FACETED_AUTO_POLE = 0.5
Rig.FACETED_HAND_LOCK_POLE = 0.6
Rig.FACETED_HOOK_BELOW = 0.1
local CLASSIC = {
	UPPER_ARM = Rig.UPPER_ARM,
	FOREARM = Rig.FOREARM,
	HOOK = Rig.HOOK,
	SHOULDER = { Right = Rig.SHOULDER.Right, Left = Rig.SHOULDER.Left },
	POLE = { Right = Rig.POLE.Right, Left = Rig.POLE.Left },
	BOW_POLE = Rig.POLE.BowRight,
	BOW_POLE_DRAWN = Rig.POLE.BowRightDrawn,
	GRIP = { Right = Rig.GRIP.Right, Left = Rig.GRIP.Left },
	GRIP_POINT = { Right = Rig.GRIP_POINT.Right, Left = Rig.GRIP_POINT.Left },
	BOW_GRIP = Rig.BOW_GRIP,
	MAX_WRIST = Rig.MAX_WRIST,
}

-- Swaps the module's arm constants: "Avatar" with `spec` (viewmodel-scale joint lengths: upper, fore, hand), "Faceted"
-- with `spec` (joint lengths upper, fore and the hand frames grip, bowGrip, hook from the templates) or Classic. Every
-- style starts from the Classic values.
function Rig.useStyle(style: string, spec: { [string]: any }?)
	Rig.POLE.BowRightDrawn = CLASSIC.BOW_POLE_DRAWN
	Rig.GRIP.Right, Rig.GRIP.Left = CLASSIC.GRIP.Right, CLASSIC.GRIP.Left
	Rig.GRIP_POINT.Right, Rig.GRIP_POINT.Left = CLASSIC.GRIP_POINT.Right, CLASSIC.GRIP_POINT.Left
	Rig.BOW_GRIP = CLASSIC.BOW_GRIP
	Rig.MAX_WRIST = CLASSIC.MAX_WRIST
	if (style == "Faceted" or style == "Blocky") and spec then
		Rig.STYLE = style -- ("Blocky": block arms on the Faceted skeleton and frames)
		Rig.UPPER_ARM, Rig.FOREARM = spec.upper, spec.fore
		Rig.SHOULDER.Right, Rig.SHOULDER.Left = Rig.FACETED_SHOULDER.Right, Rig.FACETED_SHOULDER.Left
		Rig.WRIST = Vector3.zero
		Rig.HOOK = spec.hook
		Rig.POLE.Right, Rig.POLE.Left = Rig.FACETED_POLE.Right, Rig.FACETED_POLE.Left
		-- (the block arms bring their own pole for the string arm at the low ready: Blocky.BOW_POLE)
		Rig.POLE.BowRight = if typeof(spec.bowPole) == "Vector3" then spec.bowPole else Rig.FACETED_POLE.BowRight
		Rig.POLE.BowRightDrawn = Rig.FACETED_POLE.BowRightDrawn
		Rig.GRIP.Right, Rig.GRIP.Left = spec.grip.Right, spec.grip.Left
		Rig.GRIP_POINT.Right, Rig.GRIP_POINT.Left = spec.grip.Right.Position, spec.grip.Left.Position
		Rig.BOW_GRIP = spec.bowGrip
		Rig.PALM.Right, Rig.PALM.Left = spec.palm.Right, spec.palm.Left
		Rig.MAX_WRIST = Rig.FACETED_MAX_WRIST
		Rig.REACH_DRAG = true
		Rig.AUTO_POLE = Rig.FACETED_AUTO_POLE
	elseif style == "Avatar" and spec then
		Rig.STYLE = "Avatar"
		Rig.UPPER_ARM, Rig.FOREARM = spec.upper, spec.fore
		Rig.SHOULDER.Right, Rig.SHOULDER.Left = Rig.AVATAR_SHOULDER.Right, Rig.AVATAR_SHOULDER.Left
		local wrist = -Rig.GRIP_POINT.Right.Z - Rig.AVATAR_GRIP_AT * spec.hand
		Rig.WRIST = Vector3.new(0, 0, -wrist)
		Rig.HOOK = Vector3.new(CLASSIC.HOOK.X, CLASSIC.HOOK.Y, -(wrist + spec.hand - Rig.AVATAR_HOOK_IN))
		Rig.POLE.BowRight = Rig.AVATAR_POLE.BowRight
		Rig.POLE.Right, Rig.POLE.Left = Rig.AVATAR_POLE.Right, Rig.AVATAR_POLE.Left
		Rig.REACH_DRAG = true
		Rig.AUTO_POLE = Rig.AVATAR_AUTO_POLE
	else
		Rig.STYLE = "Classic"
		Rig.UPPER_ARM, Rig.FOREARM = CLASSIC.UPPER_ARM, CLASSIC.FOREARM
		Rig.SHOULDER.Right, Rig.SHOULDER.Left = CLASSIC.SHOULDER.Right, CLASSIC.SHOULDER.Left
		Rig.WRIST = Vector3.zero
		Rig.HOOK = CLASSIC.HOOK
		Rig.POLE.BowRight = CLASSIC.BOW_POLE
		Rig.POLE.Right, Rig.POLE.Left = CLASSIC.POLE.Right, CLASSIC.POLE.Left
		Rig.REACH_DRAG = false
		Rig.AUTO_POLE = 0
	end
end

local SLEEVE = Color3.fromRGB(47, 51, 57)
local CUFF = Color3.fromRGB(70, 64, 56)
local DEFAULT_SKIN = Color3.fromRGB(204, 158, 122)
local ALONG_X = CFrame.Angles(0, math.rad(90), 0) -- turns a lookAt frame so a cylinder's axis (X) points forward
local PARKED = CFrame.new(0, -10000, 0)

-- Big soft items are held smaller in the view.
local ITEM_SCALE: { [string]: number } = { leather_vest = 0.42, padded_armor = 0.4, medkit = 0.62 }
-- Where an item sits in the fist: its Grip frame relative to Rig.GRIP (Grip space: -Z toward the business end, -X
-- toward the palm). Things wider than the fist (the apple, the bandage roll, the bottles, the ration tin) sit in it on
-- the palm side, so the fingers close round them instead of the item perching on top; the bottles are gripped round
-- their band (Poses.applyUse "Drink" takes the bottle's frame from this hold). The bandage roll lies along the palm,
-- its axis along the thumb and its loose end toward the knuckles (Poses.applyUse "Wrap" winds it round the forearm
-- from this hold). The berry sprig is held by its stalk, upside down, so the cluster stands out of the top of the fist
-- and the leaves hang below it. Everything else is held at its Grip (herbs by their stems, the dried meat by its bone).
local ITEM_HOLD: { [string]: CFrame } = {
	apple = CFrame.new(-0.12, 0, -0.16),
	bandage = CFrame.fromMatrix(Vector3.new(-0.25, 0, 0), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)),
	berries = CFrame.new(-0.1, 0, -0.22) * CFrame.Angles(math.pi, 0, 0),
	ration = CFrame.new(-0.3, 0, 0),
	water_bottle = CFrame.new(-0.26, 0, -0.08),
	empty_bottle = CFrame.new(-0.26, 0, -0.08),
}
Rig.ITEM_HOLD = ITEM_HOLD
-- Avatar arms: where an item sits on the R15 hand, a block with no fingers to close round it (Grip space as above):
-- against the palm face (-X), a little sunk into it, never through the hand (the glass bottle would show the hand
-- inside it), so it reads as held in the palm.
Rig.AVATAR_ITEM_HOLD = {
	apple = CFrame.new(-0.26, 0.025, 0.03),
	berries = CFrame.new(-0.24, 0.03, -0.05), -- (the sprig lies on the palm, its leaves out past the thumb, off the hotbar)
	bandage = CFrame.fromMatrix(Vector3.new(-0.32, 0.03, 0), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)),
	ration = CFrame.new(-0.375, 0.03, 0),
	water_bottle = CFrame.new(-0.4, 0.03, 0),
	empty_bottle = CFrame.new(-0.4, 0.03, 0),
} :: { [string]: CFrame }

-- Right-hand parts in hand space (x mirrors for the left hand).
local HAND_PARTS = {
	{ name = "Wrist", size = Vector3.new(0.25, 0.28, 0.2), x = 0, y = 0, z = -0.06 },
	{ name = "Fist", size = Vector3.new(0.3, 0.34, 0.32), x = -0.03, y = 0, z = -0.29 },
	{ name = "Fingers", size = Vector3.new(0.07, 0.31, 0.26), x = -0.19, y = -0.01, z = -0.3, shade = 0.86 },
	{ name = "Knuckles", size = Vector3.new(0.26, 0.3, 0.05), x = -0.03, y = 0, z = -0.455, shade = 0.94 },
	{ name = "Thumb", size = Vector3.new(0.1, 0.11, 0.23), x = -0.13, y = 0.165, z = -0.3, yaw = 12 },
}

local function newPart(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = PARKED
	p.Parent = parent
	return p
end

-- Anchors an ItemModels model for BulkMoveTo and records every part's offset from the Handle.
local function prepareItem(model: Model, scale: number?)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("JointInstance") or inst:IsA("WeldConstraint") or inst:IsA("ProximityPrompt") then
			inst:Destroy()
		end
	end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.CastShadow = false
			inst.Massless = true
		end
	end
	if scale and scale ~= 1 then
		local beams: { [Beam]: { number } } = {}
		for _, inst in ipairs(model:GetDescendants()) do
			if inst:IsA("Beam") then
				beams[inst] = { inst.Width0, inst.Width1 }
			end
		end
		model:ScaleTo(scale)
		for beam, widths in pairs(beams) do
			beam.Width0 = widths[1] * scale
			beam.Width1 = widths[2] * scale
		end
	end
	local handle = model.PrimaryPart :: BasePart
	local inverse = handle.CFrame:Inverse()
	local parts, offsets, followers = {}, {}, {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
			table.insert(offsets, inverse * inst.CFrame)
			if inst:GetAttribute("FollowsNock") then
				followers[#parts] = true -- the bow's nock bead moves with the string
			end
		end
	end
	local attachments: { [string]: Attachment } = {}
	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("Attachment") then
			attachments[child.Name] = child
		end
	end
	local grip = attachments.Grip
	return {
		model = model,
		handle = handle,
		parts = parts,
		offsets = offsets,
		followers = followers,
		attachments = attachments,
		gripInverse = (if grip then grip.CFrame else CFrame.identity):Inverse(),
	}
end

-- Two-bone IK: elbow position for a shoulder, a wrist target and a pole direction (where the elbow points). Also returns
-- the wrist (the target, or short of it when out of reach) and the shoulder (Rig.REACH_DRAG: pulled toward a target out
-- of reach, so the wrist is always the target).
local function solveArm(shoulder: Vector3, target: Vector3, pole: Vector3): (Vector3, Vector3, Vector3)
	local l1, l2 = Rig.UPPER_ARM, Rig.FOREARM
	local offset = target - shoulder
	local distance = offset.Magnitude
	local dir = if distance > 1e-4 then offset / distance else Vector3.new(0, 0, -1)
	if Rig.REACH_DRAG then
		local reach = (l1 + l2) * 0.97
		if distance > reach then
			local pull = math.min(distance - reach, Rig.DRAG_MAX)
			shoulder += dir * pull
			distance -= pull
		end
	end
	distance = math.clamp(distance, math.abs(l1 - l2) + 0.05, l1 + l2 - 0.002)
	local wrist = shoulder + dir * distance
	local cosA = math.clamp((l1 * l1 + distance * distance - l2 * l2) / (2 * l1 * distance), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local bend = pole - dir * pole:Dot(dir)
	if bend.Magnitude < 1e-4 then
		bend = dir:Cross(if math.abs(dir.X) < 0.9 then Vector3.xAxis else Vector3.zAxis)
	end
	bend = bend.Unit
	return shoulder + dir * (l1 * cosA) + bend * (l1 * sinA), wrist, shoulder
end
Rig.solveArm = solveArm

-- Turns `hand` so the wrist is straight: the fingers (-Z) carry on along the forearm (elbow -> wrist, from the IK for
-- `shoulder` and `pole`), keeping the hand-space point `pivot` (the string hook, a grip) where it is. strictUp keeps
-- the thumb (+Y) exactly on `up` (a held bottle's axis) and only turns the hand about it; otherwise the fingers follow
-- the forearm and the thumb comes as close to `up` as it can. All vectors in the hand frame's space.
function Rig.straightWrist(hand: CFrame, pivot: Vector3, up: Vector3, strictUp: boolean, shoulder: Vector3, pole: Vector3): CFrame
	local fixed = hand * pivot
	local result = hand
	for _ = 1, 4 do
		local wrist = result * Rig.WRIST -- (the arm's wrist joint; the hand frame's origin for the Classic arms)
		local elbow = solveArm(shoulder, wrist, pole)
		local along = wrist - elbow
		if along.Magnitude < 1e-4 then
			break
		end
		along = along.Unit
		local y: Vector3, z: Vector3
		if strictUp then
			y = up.Unit
			z = -(along - y * along:Dot(y))
		else
			z = -along
			y = up - z * up:Dot(z)
		end
		if y.Magnitude < 1e-3 or z.Magnitude < 1e-3 then
			break
		end
		y, z = y.Unit, z.Unit
		local rotation = CFrame.fromMatrix(Vector3.zero, y:Cross(z), y, z)
		result = rotation + (fixed - rotation * pivot)
	end
	return result
end

-- A cylinder (axis = X) spanning a -> b.
local function alongAxis(a: Vector3, b: Vector3, up: Vector3): CFrame
	local mid = (a + b) * 0.5
	local dir = b - a
	if dir.Magnitude < 1e-4 then
		return CFrame.new(mid)
	end
	local unit = dir.Unit
	local hint = up
	if math.abs(unit:Dot(up)) > 0.98 then
		hint = if math.abs(unit.X) < 0.9 then Vector3.xAxis else Vector3.zAxis
	end
	return CFrame.lookAt(mid, mid + unit, hint) * ALONG_X
end

--------------------------------------------------------------------------------------------------------------------
-- Avatar arms
--------------------------------------------------------------------------------------------------------------------

local ARM_SEGMENTS = { "UpperArm", "LowerArm", "Hand" }
-- hand space -> R15 hand part space: the part's +Y runs back up to the wrist (hand +Z), its front (-Z) is the thumb
local HAND_TO_PART = CFrame.Angles(math.rad(90), 0, 0)

local function armSet(container: Instance?, side: string): { [string]: MeshPart }?
	if not container then
		return nil
	end
	local set = {}
	for _, segment in ipairs(ARM_SEGMENTS) do
		local part = container:FindFirstChild(side .. segment)
		if not (part and part:IsA("MeshPart")) then
			return nil
		end
		set[segment] = part
	end
	return set
end

local function attachmentAt(part: Instance, name: string): Vector3?
	local a = part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else nil
end

-- One arm's joints in its parts' own space (full size), or nil when a rig attachment is missing or the arm is far from
-- Roblox proportions (then the standard arm is used).
local function measureArm(set: { [string]: MeshPart }, side: string): { [string]: any }?
	local shoulder = attachmentAt(set.UpperArm, side .. "ShoulderRigAttachment")
	local elbowUpper = attachmentAt(set.UpperArm, side .. "ElbowRigAttachment")
	local elbowLower = attachmentAt(set.LowerArm, side .. "ElbowRigAttachment")
	local wristLower = attachmentAt(set.LowerArm, side .. "WristRigAttachment")
	local wristHand = attachmentAt(set.Hand, side .. "WristRigAttachment")
	if not (shoulder and elbowUpper and elbowLower and wristLower and wristHand) then
		return nil
	end
	local upper = shoulder.Y - elbowUpper.Y
	local fore = elbowLower.Y - wristLower.Y
	local hand = wristHand.Y + set.Hand.Size.Y / 2
	local width = math.max(set.LowerArm.Size.X, set.LowerArm.Size.Z, set.Hand.Size.X, set.Hand.Size.Z)
	if upper < 0.35 or upper > 1.6 or fore < 0.35 or fore > 1.6 or hand < 0.1 or hand > 0.9 or width < 0.4 or width > 1.9 then
		return nil
	end
	return {
		upper = upper,
		fore = fore,
		hand = hand,
		width = width,
		elbowUpper = elbowUpper,
		wristLower = wristLower,
		wristHand = wristHand,
	}
end

local function standardArms(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Viewmodel")
	return folder and folder:FindFirstChild("StandardArms")
end

local function armColors(character: Model?): { [string]: Color3 }?
	if not character then
		return nil
	end
	local colors = character:FindFirstChildOfClass("BodyColors")
	if colors then
		return { Right = colors.RightArmColor3, Left = colors.LeftArmColor3 }
	end
	local out = {}
	for _, side in ipairs({ "Right", "Left" }) do
		local part = character:FindFirstChild(side .. "Hand") or character:FindFirstChild(side .. " Arm")
		if not (part and part:IsA("BasePart")) then
			return nil
		end
		out[side] = part.Color
	end
	return out
end

local function cloneArmPart(source: MeshPart, scale: Vector3): MeshPart
	local archivable = source.Archivable
	source.Archivable = true
	local part = source:Clone() :: MeshPart
	source.Archivable = archivable
	local ownLook = false
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceAppearance") then
			ownLook = true -- (realistic bodies bring their own skin maps)
		else
			child:Destroy()
		end
	end
	part.Size = source.Size * scale
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = Rig.Options.ArmShadows == true
	part.Transparency = 0
	part.LocalTransparencyModifier = 0
	if not ownLook then
		local material = Rig.Options.ArmMaterial
		part.Material = if typeof(material) == "EnumItem" then material else Enum.Material.SmoothPlastic
		part.Reflectance = 0
	end
	part.CFrame = PARKED
	return part
end

-- What the avatar arms are built from: changes when the character's arms, shirt or arm colours change.
function Rig.avatarSignature(character: Model?): string
	if not character then
		return ""
	end
	local bits = {}
	for _, side in ipairs({ "Right", "Left" }) do
		for _, segment in ipairs(ARM_SEGMENTS) do
			local part = character:FindFirstChild(side .. segment)
			if part and part:IsA("MeshPart") then
				table.insert(bits, part.MeshId .. "|" .. tostring(part.Size) .. "|" .. part.Color:ToHex() .. "|" .. part.TextureID)
			else
				local r6 = character:FindFirstChild(side .. " Arm")
				table.insert(bits, if r6 and r6:IsA("BasePart") then "r6" .. r6.Color:ToHex() else "-")
			end
		end
	end
	local shirt = character:FindFirstChildOfClass("Shirt")
	table.insert(bits, if shirt then shirt.ShirtTemplate else "noshirt")
	local colors = character:FindFirstChildOfClass("BodyColors")
	if colors then
		table.insert(bits, colors.RightArmColor3:ToHex() .. colors.LeftArmColor3:ToHex())
	end
	return table.concat(bits, ";")
end

-- The shade layer (Rig:setShade): a copy of each arm part a little bigger, plain and mostly transparent, outside the
-- shirt's Humanoid. Lit by the same light as the arm, it gives dark and black clothing (which has no albedo to light)
-- the shape of the light, and tints the skin a touch toward it.
local SHADE_GROW = 0.012
local function shadeOf(part: MeshPart): MeshPart
	local shade = part:Clone()
	for _, child in ipairs(shade:GetChildren()) do
		child:Destroy()
	end
	shade.Name = part.Name .. "Shade"
	shade.Size = part.Size + Vector3.one * SHADE_GROW
	shade.Material = Enum.Material.SmoothPlastic
	shade.Color = Color3.new(1, 1, 1)
	shade.Transparency = 1
	shade.CastShadow = false
	shade:SetAttribute("ShadeLayer", true)
	return shade
end

-- (Avatar arms) the elbow pole turned from the pose's `pole` toward `ideal` (an elbow that would put the forearm in line
-- with the hand) by `w` of the angle between them, at most Rig.MAX_POLE_SWING.
local function towardElbow(shoulder: Vector3, wrist: Vector3, pole: Vector3, ideal: Vector3, w: number): Vector3
	local dir = wrist - shoulder
	if dir.Magnitude < 1e-4 then
		return pole
	end
	dir = dir.Unit
	local a = pole - dir * pole:Dot(dir)
	local b = (ideal - shoulder) - dir * (ideal - shoulder):Dot(dir)
	if a.Magnitude < 1e-4 or b.Magnitude < 1e-4 then
		return pole
	end
	a, b = a.Unit, b.Unit
	local angle = math.acos(math.clamp(a:Dot(b), -1, 1))
	if angle < 1e-3 then
		return a
	end
	local axis = a:Cross(b)
	axis = if axis.Magnitude > 1e-4 then axis.Unit else dir
	return CFrame.fromAxisAngle(axis, math.min(angle * w, Rig.MAX_POLE_SWING)):VectorToWorldSpace(a)
end

-- (Avatar arms) a free hand turned about its thumb (the held item's axis), through its grip, so its knuckles come round to
-- the forearm the IK gives it (by at most Rig.MAX_TWIST).
local function twistToward(hand: CFrame, shoulder: Vector3, pole: Vector3, grip: Vector3): CFrame
	local target = hand * Rig.WRIST
	local elbow = solveArm(shoulder, target, pole)
	local f = target - elbow
	if f.Magnitude < 1e-4 then
		return hand
	end
	f = f.Unit
	local u = hand.UpVector
	local want = f - u * f:Dot(u)
	if want.Magnitude < 0.35 then
		return hand -- (the forearm runs along the item: no clear way to turn)
	end
	want = want.Unit
	local k = hand.LookVector
	local angle = math.acos(math.clamp(k:Dot(want), -1, 1))
	if angle < 1e-3 then
		return hand
	end
	local sign = if k:Cross(want):Dot(u) >= 0 then 1 else -1
	local pivot = hand * grip
	return CFrame.new(pivot) * CFrame.fromAxisAngle(u, sign * math.min(angle, Rig.MAX_TWIST)) * CFrame.new(-pivot) * hand
end

-- (Avatar arms) a hand bent further than Rig.MAX_WRIST from the forearm (elbow -> wrist) turned back about the wrist.
local function limitWrist(hand: CFrame, wrist: Vector3, elbow: Vector3): CFrame
	local f = wrist - elbow
	if f.Magnitude < 1e-4 then
		return hand
	end
	f = f.Unit
	local k = hand.LookVector
	local angle = math.acos(math.clamp(k:Dot(f), -1, 1))
	if angle <= Rig.MAX_WRIST then
		return hand
	end
	local axis = k:Cross(f)
	axis = if axis.Magnitude > 1e-4 then axis.Unit else hand.RightVector
	return CFrame.new(wrist) * CFrame.fromAxisAngle(axis, angle - Rig.MAX_WRIST) * CFrame.new(-wrist) * hand
end

-- A frame on a bone: Y along `up` (toward the parent joint), the front (-Z) toward `front` as far as it can.
local function boneFrame(at: Vector3, up: Vector3, front: Vector3): CFrame
	local back = up * front:Dot(up) - front
	if back.Magnitude < 1e-3 then
		local hint = if math.abs(up.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
		back = hint - up * hint:Dot(up)
	end
	back = back.Unit
	return CFrame.fromMatrix(at, up:Cross(back), up, back)
end

--------------------------------------------------------------------------------------------------------------------
-- Faceted arms
--------------------------------------------------------------------------------------------------------------------

-- hand space -> faceted piece space. The pieces' bone runs along +Y, the palm faces +Z and the R_ thumb is +X (the L_
-- pieces are X mirrors): piece +X = the right thumb (hand +Y), +Y = toward the fingers (hand -Z), +Z = the palm (hand
-- -X on the right, +X on the left).
local MESH_IN_HAND = {
	Right = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, -1)),
	Left = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, -1)),
}
Rig.MESH_IN_HAND = MESH_IN_HAND
Rig.HAND_SHAPES = { "Relaxed", "Fist", "Grip", "Open" }
-- The Grip hand's own grip frame (look = the handle toward the thumb, up = toward the fingers) turned about the handle
-- into an item's Grip frame (its edge, -UpVector, toward the knuckles).
local GRIP_FLIP = CFrame.Angles(0, 0, math.pi)
-- (Faceted) the hand an item is held in ("Grip" by default) and, for the open hand, where its Grip frame sits on the
-- palm (Rig.PALM space: -Z out of the palm, +Y toward the fingers, +X toward the little finger on the right hand). Round
-- food sits in the cupped palm, the tin across it, the bottle lies along the palm with its neck past the thumb.
Rig.FACETED_HAND = {
	apple = "Open", berries = "Open", ration = "Open", water_bottle = "Open", empty_bottle = "Open", bandage = "Open",
} :: { [string]: string }
Rig.FACETED_PALM_HOLD = {
	apple = CFrame.new(0, 0.02, -0.135),
	berries = CFrame.new(0, 0.05, -0.08) * CFrame.Angles(math.rad(80), 0, 0),
	ration = CFrame.new(0, 0.05, -0.25) * CFrame.Angles(0, math.rad(90), 0),
	water_bottle = CFrame.new(0, 0.05, -0.23) * CFrame.Angles(0, math.rad(90), 0),
	empty_bottle = CFrame.new(0, 0.05, -0.23) * CFrame.Angles(0, math.rad(90), 0),
	bandage = CFrame.new(0, 0.04, -0.17),
} :: { [string]: CFrame }
-- (Faceted) where a gripped item sits in the fist, relative to Rig.GRIP (Grip space, as Rig.ITEM_HOLD)
Rig.FACETED_ITEM_HOLD = {} :: { [string]: CFrame }
-- (Faceted) the open hand's palm frame in hand space (look = out of the palm, up = toward the fingers)
Rig.PALM = { Right = CFrame.identity, Left = CFrame.identity }

local function facetedFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets") or ReplicatedStorage:WaitForChild("Assets", 5)
	local viewmodel = assets and (assets:FindFirstChild("Viewmodel") or assets:WaitForChild("Viewmodel", 5))
	return viewmodel and (viewmodel:FindFirstChild("ArmsFaceted") or viewmodel:WaitForChild("ArmsFaceted", 5))
end

-- A faceted piece: a clone of its template, every part's offset from the pivot (the joint), its skin and sleeve parts
-- (with their SurfaceAppearances) and its attachment frames (piece space).
local function facetedPiece(template: Instance, parent: Instance): { [string]: any }
	local model = template:Clone()
	local inverse = if model:IsA("Model") then model.WorldPivot:Inverse() else CFrame.identity -- (the joint)
	local piece = { model = model, parts = {}, offsets = {}, skins = {}, sleeves = {}, att = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = Rig.Options.ArmShadows == true
			table.insert(piece.parts, d)
			table.insert(piece.offsets, inverse * d.CFrame)
			local role = d:GetAttribute("Role")
			if role == "Skin" then
				table.insert(piece.skins, d)
			elseif role == "Sleeve" then
				table.insert(piece.sleeves, d)
			end
		elseif d:IsA("Attachment") then
			piece.att[d.Name] = inverse * d.WorldCFrame
		end
	end
	for _, p in ipairs(piece.parts) do
		p.CFrame = PARKED
	end
	model.Parent = parent
	return piece
end

-- Writes a faceted piece's part frames for its pivot at `at` into cframes after index i; returns the last index.
local function placePiece(cframes: { CFrame }, i: number, piece: { [string]: any }, at: CFrame): number
	for _, offset in ipairs(piece.offsets) do
		i += 1
		cframes[i] = at * offset
	end
	return i
end

-- Builds the faceted arms from the templates (nil when they are missing) and the hand frames the style needs.
local function buildFaceted(parent: Instance): ({ [string]: any }?, { [string]: any }?)
	local folder = facetedFolder()
	if not folder then
		return nil, nil
	end
	local arms = {}
	for _, side in ipairs({ "Right", "Left" }) do
		local prefix = if side == "Right" then "R_" else "L_"
		local function piece(name: string)
			local template = folder:FindFirstChild(prefix .. name)
			return template and facetedPiece(template, parent)
		end
		local arm = { upper = piece("UpperArm"), fore = piece("Forearm"), hands = {}, hand = "Relaxed" }
		for _, shape in ipairs(Rig.HAND_SHAPES) do
			arm.hands[shape] = piece("Hand" .. shape)
		end
		if not (arm.upper and arm.fore and arm.hands.Relaxed and arm.hands.Fist and arm.hands.Grip and arm.hands.Open) then
			for _, p in ipairs({ arm.upper, arm.fore, arm.hands.Relaxed, arm.hands.Fist, arm.hands.Grip, arm.hands.Open }) do
				if p then
					p.model:Destroy()
				end
			end
			for _, done in pairs(arms) do
				for _, p in ipairs({ done.upper, done.fore, done.hands.Relaxed, done.hands.Fist, done.hands.Grip, done.hands.Open }) do
					p.model:Destroy()
				end
			end
			return nil, nil
		end
		arms[side] = arm
	end
	local elbow = arms.Right.upper.att.Elbow
	local wrist = arms.Right.fore.att.Wrist
	local spec = { upper = if elbow then elbow.Position.Y else 0.95, fore = if wrist then wrist.Position.Y else 0.85, grip = {}, palm = {} }
	for _, side in ipairs({ "Right", "Left" }) do
		local arm = arms[side]
		local grip = arm.hands.Grip.att.Grip or CFrame.lookAt(Vector3.new(0, 0.257, 0.118), Vector3.new(1, 0.43, 0.118), Vector3.yAxis)
		local palm = arm.hands.Open.att.Palm or CFrame.lookAt(Vector3.new(0, 0.18, 0.063), Vector3.new(0, 0.18, 1), Vector3.yAxis)
		local handGrip = MESH_IN_HAND[side] * grip
		spec.grip[side] = handGrip * GRIP_FLIP
		spec.palm[side] = MESH_IN_HAND[side] * palm
		if side == "Right" then
			spec.handGrip = handGrip
		else
			spec.bowGrip = handGrip -- the bow: top limb along the thumb, shooting toward the knuckles
		end
	end
	spec.hook = spec.handGrip.Position + Vector3.new(0, Rig.FACETED_HOOK_BELOW, 0)
	return arms, spec
end

function Rig.new(skin: Color3?, style: string?, armOptions: { [string]: any }?)
	local self = setmetatable({}, Rig)
	self.model = Instance.new("Model")
	self.model.Name = "Viewmodel"
	self.skin = skin or DEFAULT_SKIN
	if style == "Blocky" and not Blocky then
		style = "Faceted" -- (a Rig cloned without its sibling module Blocky)
	end
	self.style = if style == "Avatar" or style == "Faceted" or style == "Blocky" then style else "Classic"
	self.blocky = nil -- (Blocky) the block arms' settings (Blocky.build's info); their pieces are in self.faceted
	self.avatar = nil
	self.faceted = nil -- (Faceted) per side: upper, fore, hands[shape], hand (the shape shown)
	self.arms = {}
	self.item = nil
	self.arrow = nil
	self.itemHidden = false
	self.arrowHidden = false
	self.draw = 0
	-- The block arms are built whole by Blocky.build, which cannot fail, so they need nothing the older styles keep
	-- at hand: not the part-built arms (the other styles' fallback), not the lamp, not the Highlight. Their viewmodel
	-- holds the arm blocks, the bandage band and the held item, and nothing else.
	local blockArms = self.style == "Blocky"
	for _, side in ipairs({ "Right", "Left" }) do
		local s = if side == "Right" then 1 else -1
		local arm = { side = side, hand = {}, solved = CFrame.identity }
		if not blockArms then
			arm.upper = newPart(self.model, side .. "UpperArm", Enum.PartType.Cylinder, Vector3.new(Rig.UPPER_ARM, 0.44, 0.44), SLEEVE, Enum.Material.Fabric)
			arm.elbow = newPart(self.model, side .. "Elbow", Enum.PartType.Ball, Vector3.new(0.43, 0.43, 0.43), SLEEVE, Enum.Material.Fabric)
			arm.fore = newPart(self.model, side .. "Forearm", Enum.PartType.Cylinder, Vector3.new(Rig.FOREARM, 0.38, 0.38), SLEEVE, Enum.Material.Fabric)
			arm.cuff = newPart(self.model, side .. "Cuff", Enum.PartType.Cylinder, Vector3.new(0.14, 0.42, 0.42), CUFF, Enum.Material.Fabric)
			for _, spec in ipairs(HAND_PARTS) do
				local p = newPart(self.model, side .. spec.name, Enum.PartType.Block, spec.size, self.skin, Enum.Material.SmoothPlastic)
				local offset = CFrame.new(spec.x * s, spec.y, spec.z) * CFrame.Angles(0, math.rad((spec.yaw or 0) * s), 0)
				table.insert(arm.hand, { part = p, offset = offset, shade = spec.shade })
			end
		end
		self.arms[side] = arm
	end
	self:setSkin(self.skin)
	self.keyAnchor = nil
	self.key = nil
	self.exposure = nil
	if not blockArms then
		-- (Avatar arms) the light ViewmodelController.Shade puts on them: a key light above the arms (moved with them,
		-- frame.key) and the exposure, the whole viewmodel darkened toward the scene's level (Rig:setExposure). The key's
		-- part lives in the workspace while the arms are shown (rig:setKeyParent): a light inside the camera gives no light.
		self.keyAnchor = newPart(self.model, "ViewmodelKeyLight", Enum.PartType.Block, Vector3.new(0.05, 0.05, 0.05), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		self.keyAnchor.Transparency = 1
		self.keyAnchor.Parent = nil
		local key = Instance.new("SpotLight")
		key.Name = "Key"
		key.Face = Enum.NormalId.Front
		key.Shadows = false
		key.Brightness = 0
		key.Enabled = false
		key.Parent = self.keyAnchor
		self.key = key
		local exposure = Instance.new("Highlight")
		exposure.Name = "Exposure"
		exposure.FillColor = Color3.new(0, 0, 0)
		exposure.FillTransparency = 1
		exposure.OutlineTransparency = 1
		exposure.DepthMode = Enum.HighlightDepthMode.Occluded
		exposure.Enabled = false
		exposure.Adornee = self.model
		exposure.Parent = self.model
		self.exposure = exposure
	end
	self.exposureLevel = 1
	-- (Avatar arms) the bandage wound onto the left forearm while bandaging (Rig:setWrap)
	self.wrapBand = newPart(self.model, "WrapBand", Enum.PartType.Block, Vector3.new(0.5, 0.05, 0.5), Color3.fromRGB(236, 232, 222), Enum.Material.Fabric)
	self.wrapLength = 0
	if blockArms then
		-- block arms built from Parts, in the shape buildFaceted returns: the Faceted code below drives them. Nothing is
		-- laid over them and no lamp is lit for them: their rig has no Highlight and no key light at all, and
		-- rig:setExposure works on their colours.
		self.faceted, self.facetedSpec, self.blocky = Blocky.build(self.model, armOptions or Rig.Options.Blocky)
	end
	if self.style == "Faceted" then
		local arms, spec = buildFaceted(self.model)
		if arms then
			self.faceted = arms
			self.facetedSpec = spec
		else
			warn("[ViewmodelController.Rig] ReplicatedStorage.Assets.Viewmodel.ArmsFaceted is missing; using the avatar arms")
			self.style = "Avatar"
		end
	end
	if self.style == "Faceted" or self.style == "Blocky" then
		self:_useFaceted()
	elseif self.style == "Avatar" then
		self:setAvatar(nil) -- the standard arms in the skin colour until the character's own arms are measured
	else
		self:_useAvatarArms(nil)
	end
	return self
end

-- (Faceted, Blocky) shows the faceted or block arms: the part-built arms are hidden and the style's constants swapped in.
function Rig:_useFaceted()
	for _, arm in pairs(self.arms) do
		for _, p in ipairs({ arm.upper, arm.elbow, arm.fore, arm.cuff }) do
			p.LocalTransparencyModifier = 1
			p.CFrame = PARKED
		end
		for _, entry in ipairs(arm.hand) do
			entry.part.LocalTransparencyModifier = 1
			entry.part.CFrame = PARKED
		end
	end
	Rig.useStyle(self.style, self.facetedSpec)
	self:setSkin(self.skin, self.skinLeft)
	self:_rebuild()
end

-- (Faceted) the hand meshes shown: "Relaxed" | "Fist" | "Grip" | "Open" (nil keeps a side's current one).
function Rig:setHands(right: string?, left: string?)
	local fac = self.faceted
	if not fac then
		return
	end
	local changed = false
	for _, side in ipairs({ "Right", "Left" }) do
		local shape = if side == "Right" then right else left
		local arm = fac[side]
		if shape and arm.hands[shape] and arm.hand ~= shape then
			if arm.hands[shape] ~= arm.hands[arm.hand] then -- (Blocky variant A: one block is every shape)
				for _, p in ipairs(arm.hands[arm.hand].parts) do
					p.CFrame = PARKED
				end
				changed = true
			end
			arm.hand = shape
		end
	end
	if changed then
		self:_rebuild()
	end
end

-- (Faceted) the hand mesh the held item wants ("Grip" | "Open"), nil with nothing in hand.
function Rig:itemHand(): string?
	return if self.item then self.item.handShape else nil
end

-- Where the key light's part lives (the workspace while the arms are shown, nil otherwise; nil also switches it off).
function Rig:setKeyParent(parent: Instance?)
	if not self.keyAnchor then
		return -- (the block arms have no lamp)
	end
	self.keyAnchor.Parent = parent
	if not parent then
		self.key.Enabled = false
	end
end

-- The whole viewmodel at `level` (0..1) of its lit brightness (1: as the engine lights it).
function Rig:setExposure(level: number)
	level = math.clamp(level, 0, 1)
	if math.abs(level - self.exposureLevel) < 0.004 then
		return
	end
	self.exposureLevel = level
	if self.blocky and Blocky then
		Blocky.setExposure(self.faceted, self.blocky, level) -- (by colour alone: nothing is laid over the block arms)
		return
	end
	self.exposure.Enabled = level < 0.995
	self.exposure.FillTransparency = level
end

-- (Blocky) dark arm colours lifted to at least `floor` in their brightest channel (0: as they are): Blocky.setFloor.
function Rig:setFloor(floor: number)
	if self.blocky and Blocky then
		Blocky.setFloor(self.faceted, self.blocky, floor)
	end
end

-- (Avatar arms) how much bandage is wound onto the left forearm, studs along it from just behind the wrist (0: none).
Rig.WRAP_FROM = 0.05
function Rig:setWrap(length: number)
	length = math.max(0, length)
	if math.abs(length - self.wrapLength) < 0.01 then
		return
	end
	self.wrapLength = length
	local arms = self.avatar
	local width = if arms then arms.parts.Left.LowerArm.Size.X elseif self.blocky then self.blocky.sleeveWidth elseif self.faceted then 0.24 else 0.46
	if length > 0.01 then
		self.wrapBand.Size = Vector3.new(width + 0.035, length, width + 0.035)
	end
end

-- (Avatar arms) the shade layer's colour and transparency (1: off) over the upper arms and forearms (the sleeves), and
-- over the hands (handTransparency, fainter: the skin barely changes, a dark glove or cuff keeps some form).
function Rig:setShade(color: Color3, transparency: number, handTransparency: number?)
	local arms = self.avatar
	if not (arms and arms.shades) then
		return
	end
	local hand = handTransparency or 1
	if arms.shadeColor == color and arms.shadeTransparency and math.abs(arms.shadeTransparency - transparency) < 0.004
		and arms.shadeHand == hand then
		return
	end
	arms.shadeColor, arms.shadeTransparency, arms.shadeHand = color, transparency, hand
	for _, side in ipairs({ "Right", "Left" }) do
		for _, segment in ipairs(ARM_SEGMENTS) do
			local shade = arms.shades[side][segment]
			shade.Color = color
			shade.Transparency = if segment == "Hand" then hand else transparency
		end
	end
end

-- (Faceted) tints a skin part: its SurfaceAppearance's Color multiplies the neutral light ColorMap; without one (or if
-- the engine refuses the write) the part is plain SmoothPlastic in that colour, its facets read from the flat shading.
local function tintSkin(part: BasePart, color: Color3)
	local sa = part:FindFirstChildOfClass("SurfaceAppearance")
	if sa and not pcall(function()
		sa.Color = color
	end) then
		sa:Destroy()
		sa = nil
	end
	if not sa then
		part.Material = Enum.Material.SmoothPlastic
	end
	part.Color = color
end

-- The skin colour: the Classic fists, and (Faceted) the bare skin, each side in its arm colour (left: `left` or `color`).
function Rig:setSkin(color: Color3, left: Color3?)
	self.skin = color
	self.skinLeft = left or color
	local black = Color3.new(0, 0, 0)
	for _, arm in pairs(self.arms) do
		for _, entry in ipairs(arm.hand) do
			entry.part.Color = if entry.shade then color:Lerp(black, 1 - entry.shade) else color
		end
	end
	local fac = self.faceted
	if fac and self.blocky and Blocky then
		Blocky.setSkin(fac, self.blocky, color, self.skinLeft) -- (the block arms colour themselves: plain matte Parts)
	elseif fac then
		for side, arm in pairs(fac) do
			local c = if side == "Left" then self.skinLeft else color
			for _, piece in ipairs({ arm.upper, arm.fore, arm.hands.Relaxed, arm.hands.Fist, arm.hands.Grip, arm.hands.Open }) do
				for _, p in ipairs(piece.skins) do
					tintSkin(p, c)
				end
			end
		end
	end
end

-- (Avatar style) Builds the arms from `character`: its own R15 arms, or the standard R15 arms in its colours (R6,
-- missing parts or rig attachments, unusual proportions). Returns "Avatar", "Standard", or "Classic" when no arms could
-- be built (the part-built arms are shown then). Same as rig:useArms(rig:buildAvatar(character)).
function Rig:setAvatar(character: Model?): string
	if self.style ~= "Avatar" then
		return "Classic"
	end
	local arms, source = self:buildAvatar(character)
	self:useArms(arms)
	return source
end

-- Shows arms from rig:buildAvatar (nil: the Classic part-built arms). Cheap: the arms are already built and in place.
function Rig:useArms(arms: { [string]: any }?)
	if self.style ~= "Avatar" or (arms and arms.rig ~= self) then
		return
	end
	self:_useAvatarArms(arms)
end

-- (Avatar style) Builds the arms for `character` (see setAvatar) inside the viewmodel, parked out of sight, without
-- showing them: returns (arms, source), arms nil for "Classic". This is the costly part (about a millisecond: the
-- parts are cloned and the shirt set up), so the controller runs it outside the render step, in two halves on two
-- frames (`pause`, e.g. task.wait, is called between cloning the parts and setting up the shirt), and shows the arms
-- with rig:useArms afterwards.
function Rig:buildAvatar(character: Model?, pause: (() -> any)?): ({ [string]: any }?, string)
	if self.style ~= "Avatar" then
		return nil, "Classic"
	end
	local sets, specs = {}, {}
	local source = "Avatar"
	for _, side in ipairs({ "Right", "Left" }) do
		local set = armSet(character, side)
		local spec = set and measureArm(set, side)
		if not (set and spec) then
			source = "Standard"
			break
		end
		sets[side], specs[side] = set, spec
	end
	local colors: { [string]: Color3 }? = nil
	if source == "Standard" then
		local template = standardArms()
		for _, side in ipairs({ "Right", "Left" }) do
			local set = armSet(template, side)
			local spec = set and measureArm(set, side)
			if not (set and spec) then
				return nil, "Classic"
			end
			sets[side], specs[side] = set, spec
		end
		colors = armColors(character) or { Right = self.skin, Left = self.skin }
	end
	-- Across, drawn at ArmScale (arms wider than a standard Roblox arm brought down to about its width); along, stretched
	-- or shrunk so every avatar's arm reaches ArmReach from shoulder to wrist (the poses are built for that reach).
	local width = math.max(specs.Right.width, specs.Left.width)
	local across = (tonumber(Rig.Options.ArmScale) or 0.46) * math.min(1, 1.1 / width)
	local reach = (specs.Right.upper + specs.Right.fore + specs.Left.upper + specs.Left.fore) / 2
	local along = (tonumber(Rig.Options.ArmReach) or 1.34) / reach
	local scale = Vector3.new(across, along, across)
	local model = Instance.new("Model")
	model.Name = "AvatarArms"
	local shadeModel = Instance.new("Model")
	shadeModel.Name = "ArmShade"
	local parts, shades, placed = {}, {}, {}
	local shaded = true
	for _, side in ipairs({ "Right", "Left" }) do
		local spec = specs[side]
		parts[side], shades[side] = {}, {}
		for _, segment in ipairs(ARM_SEGMENTS) do
			local part = cloneArmPart(sets[side][segment], scale)
			if colors then
				part.Color = colors[side]
			end
			part.Parent = model
			parts[side][segment] = part
			if part:FindFirstChildOfClass("SurfaceAppearance") then
				shaded = false -- (a realistic body's own skin maps carry its shading)
			end
			local shade = shadeOf(part)
			shade.Parent = shadeModel
			shades[side][segment] = shade
		end
		placed[side] = {
			upper = spec.upper * along,
			fore = spec.fore * along,
			hand = spec.hand * along,
			upperOffset = CFrame.new(-spec.elbowUpper * scale),
			lowerOffset = CFrame.new(-spec.wristLower * scale),
			handOffset = CFrame.new(-spec.wristHand * scale),
		}
	end
	if not shaded then
		shadeModel:Destroy()
		shadeModel, shades = nil, nil
	end
	if pause then
		pause()
	end
	-- the shirt and skin: a Humanoid with the character's Shirt and arm colours draws the shirt on R15 arm meshes
	local shirt = character and character:FindFirstChildOfClass("Shirt")
	if shirt then
		local copy = Instance.new("Shirt")
		copy.Name = "Shirt"
		copy.ShirtTemplate = shirt.ShirtTemplate
		copy.Color3 = shirt.Color3
		copy.Parent = model
	end
	local skin = colors or armColors(character) or { Right = parts.Right.Hand.Color, Left = parts.Left.Hand.Color }
	local bodyColors = Instance.new("BodyColors")
	bodyColors.RightArmColor3 = skin.Right
	bodyColors.LeftArmColor3 = skin.Left
	bodyColors.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.AutomaticScalingEnabled = false
	pcall(function()
		humanoid.EvaluateStateMachine = false
	end)
	humanoid.Parent = model
	for _, list in ipairs({ parts, shades or {} }) do
		for _, set in pairs(list) do
			for _, part in pairs(set) do
				part.CFrame = PARKED
			end
		end
	end
	model.Parent = self.model
	if shadeModel then
		shadeModel.Parent = self.model
	end
	return {
		rig = self,
		model = model,
		shade = shadeModel,
		parts = parts,
		shades = shades,
		placed = placed,
		source = source,
		scale = scale,
	}, source
end

-- Swaps the arm set: the avatar arms `arms` (nil: the Classic part-built arms).
function Rig:_useAvatarArms(arms: { [string]: any }?)
	local old = self.avatar
	if old == arms and arms then
		return
	end
	if old then
		-- (destroyed after this frame's work: taking a Humanoid model apart isn't free)
		old.model.Parent = nil
		if old.shade then
			old.shade.Parent = nil
		end
		task.defer(function()
			old.model:Destroy()
			if old.shade then
				old.shade:Destroy()
			end
		end)
	end
	self.avatar = arms
	local classicShown = arms == nil
	for _, arm in pairs(self.arms) do
		for _, p in ipairs({ arm.upper, arm.elbow, arm.fore, arm.cuff }) do
			p.LocalTransparencyModifier = if classicShown then 0 else 1
			p.CFrame = PARKED
		end
		for _, entry in ipairs(arm.hand) do
			entry.part.LocalTransparencyModifier = if classicShown then 0 else 1
			entry.part.CFrame = PARKED
		end
	end
	if arms then
		local r, l = arms.placed.Right, arms.placed.Left
		Rig.useStyle("Avatar", { upper = (r.upper + l.upper) / 2, fore = (r.fore + l.fore) / 2, hand = (r.hand + l.hand) / 2 })
		arms.model.Parent = self.model
		if arms.shade then
			arms.shade.Parent = self.model
		end
	else
		Rig.useStyle("Classic", nil)
	end
	self:_rebuild()
end

function Rig:_rebuild()
	local parts = {}
	local avatar = self.avatar
	local fac = self.faceted
	for _, side in ipairs({ "Right", "Left" }) do
		if fac then
			local arm = fac[side]
			for _, piece in ipairs({ arm.upper, arm.fore, arm.hands[arm.hand] }) do
				for _, p in ipairs(piece.parts) do
					table.insert(parts, p)
				end
			end
		elseif avatar then
			for _, segment in ipairs(ARM_SEGMENTS) do
				table.insert(parts, avatar.parts[side][segment])
			end
			if avatar.shades then
				for _, segment in ipairs(ARM_SEGMENTS) do
					table.insert(parts, avatar.shades[side][segment])
				end
			end
		else
			local arm = self.arms[side]
			table.insert(parts, arm.upper)
			table.insert(parts, arm.elbow)
			table.insert(parts, arm.fore)
			table.insert(parts, arm.cuff)
			for _, entry in ipairs(arm.hand) do
				table.insert(parts, entry.part)
			end
		end
	end
	if self.item then
		for _, p in ipairs(self.item.parts) do
			table.insert(parts, p)
		end
	end
	if self.arrow then
		for _, p in ipairs(self.arrow.parts) do
			table.insert(parts, p)
		end
	end
	if self.keyAnchor then
		table.insert(parts, self.keyAnchor)
	end
	table.insert(parts, self.wrapBand)
	self.parts = parts
	self.cframes = table.create(#parts, PARKED)
end

local function setHidden(info: any, hidden: boolean)
	if not info then
		return
	end
	for _, p in ipairs(info.parts) do
		p.LocalTransparencyModifier = if hidden then 1 else 0
	end
	for _, inst in ipairs(info.model:GetDescendants()) do
		if inst:IsA("Beam") then
			inst.Enabled = not hidden
		end
	end
end

function Rig:setItem(itemId: string?, hand: string?)
	if self.item then
		self.item.model:Destroy()
		self.item = nil
	end
	if itemId then
		local ok, model = pcall(Rig.ItemModels.build, itemId, "view")
		if ok and typeof(model) == "Instance" and model:IsA("Model") and model.PrimaryPart then
			-- (the block arms have their own scale and place for a few things: Blocky.ITEM_SCALE, PALM_HOLD, ITEM_HOLD)
			local own = if self.blocky then Blocky else nil
			local info = prepareItem(model, (own and own.ITEM_SCALE[itemId]) or ITEM_SCALE[itemId])
			info.itemId = itemId
			info.hand = if hand == "Left" then "Left" else "Right"
			if self.faceted then
				-- (Faceted) gripped in the fist, or lying on the open palm (Rig.FACETED_PALM_HOLD)
				local shape = Rig.FACETED_HAND[itemId] or "Grip"
				info.handShape = shape
				if shape == "Open" then
					local onPalm = (own and own.PALM_HOLD[itemId]) or Rig.FACETED_PALM_HOLD[itemId] or CFrame.identity
					info.hold = Rig.GRIP[info.hand]:Inverse() * Rig.PALM[info.hand] * onPalm
				else
					info.hold = (own and own.ITEM_HOLD[itemId]) or Rig.FACETED_ITEM_HOLD[itemId] or CFrame.identity
				end
			else
				info.hold = (if Rig.STYLE == "Avatar" then Rig.AVATAR_ITEM_HOLD[itemId] else nil) or ITEM_HOLD[itemId] or CFrame.identity
			end
			local nock = info.attachments.Nock
			if nock and info.attachments.StringTop then -- a bow (an arrow has a Nock too)
				info.bow = true
				local rest = nock:GetAttribute("RestPosition")
				info.nockRest = if typeof(rest) == "Vector3" then rest else nock.Position
				local maxDraw = nock:GetAttribute("MaxDraw")
				info.maxDraw = if type(maxDraw) == "number" then maxDraw else 1.7
				-- The arrow rests on the shelf (the mesh bow's ArrowRest attachment); the nocking point on the string
				-- sits level with it.
				local arrowRest = info.attachments.ArrowRest
				local shelf = model:FindFirstChild("ArrowShelf")
				local gripCF = info.gripInverse:Inverse()
				if arrowRest then
					info.restPoint = Vector3.new(Rig.ARROW_SIDE, arrowRest.Position.Y, arrowRest.Position.Z)
				elseif shelf and shelf:IsA("BasePart") then
					info.restPoint = info.handle.CFrame:PointToObjectSpace(shelf.Position) - Vector3.new(0, 0, shelf.Size.Z / 2 + 0.04)
				else
					info.restPoint = gripCF * Vector3.new(0.1, 0.12, -0.45)
				end
				info.strings = {}
				for _, beam in ipairs(model:GetDescendants()) do
					if beam:IsA("Beam") then
						if beam.Attachment0 == nock then
							beam.Width0 = math.min(beam.Width0, Rig.NOCK_STRING_WIDTH)
						end
						if beam.Attachment1 == nock then
							beam.Width1 = math.min(beam.Width1, Rig.NOCK_STRING_WIDTH)
						end
						if beam.Attachment0 and beam.Attachment1 then
							table.insert(info.strings, beam)
						end
					end
				end
			end
			model.Parent = self.model
			self.item = info
			setHidden(info, self.itemHidden)
		elseif ok and typeof(model) == "Instance" then
			model:Destroy()
		end
	end
	self.draw = -1
	self:setDraw(0)
	self:_rebuild()
end

function Rig:setArrow(enabled: boolean)
	if enabled and not self.arrow then
		local ok, model = pcall(Rig.ItemModels.build, "arrow", "view")
		if ok and typeof(model) == "Instance" and model:IsA("Model") and model.PrimaryPart then
			local info = prepareItem(model, nil)
			-- where the arrow's own nock is in its Grip frame (the mesh arrow's Grip is at the nock)
			local nock = info.attachments.Nock
			info.nockInGrip = if nock then info.gripInverse * nock.Position else Vector3.new(0, 0, 0.37)
			model.Name = "NockedArrow"
			model.Parent = self.model
			self.arrow = info
			setHidden(info, self.arrowHidden)
		end
	elseif not enabled and self.arrow then
		self.arrow.model:Destroy()
		self.arrow = nil
	end
	self:_rebuild()
end

function Rig:setItemHidden(hidden: boolean)
	if self.itemHidden ~= hidden then
		self.itemHidden = hidden
		setHidden(self.item, hidden)
	end
end

function Rig:setArrowHidden(hidden: boolean)
	if self.arrowHidden ~= hidden then
		self.arrowHidden = hidden
		setHidden(self.arrow, hidden)
	end
end

function Rig:handleFrame(hand: CFrame): CFrame?
	local item = self.item
	if not item then
		return nil
	end
	local grip = if item.bow and item.hand == "Left" then Rig.BOW_GRIP else Rig.GRIP[item.hand]
	return hand * grip * item.hold * item.gripInverse
end

function Rig:point(name: string, handle: CFrame): Vector3?
	local item = self.item
	local attachment = item and item.attachments[name]
	if not attachment then
		return nil
	end
	return handle * attachment.Position
end

function Rig:setDraw(studs: number)
	local item = self.item
	if not (item and item.bow) then
		return
	end
	if math.abs(studs - self.draw) < 1e-4 then
		return
	end
	self.draw = studs
	local rest: Vector3 = item.nockRest
	local z = if item.restPoint then item.restPoint.Z else rest.Z
	item.attachments.Nock.Position = Vector3.new(rest.X, rest.Y - studs, z)
end

function Rig:arrowFrame(handle: CFrame): CFrame?
	local item = self.item
	if not (item and item.bow and item.restPoint) then
		return nil
	end
	local nock = handle * item.attachments.Nock.Position
	local rest = handle * item.restPoint
	local dir = rest - nock
	if dir.Magnitude < 1e-3 then
		return nil
	end
	dir = dir.Unit
	-- The arrow's own nock goes on the string and its shaft over the rest; arrow UpVector = down the bow, so the mesh
	-- arrow's cock feather (+RightVector) points away from the riser.
	local frame = CFrame.lookAt(nock, nock + dir, -handle.LookVector)
	local nockInGrip = if self.arrow and self.arrow.nockInGrip then self.arrow.nockInGrip else Vector3.new(0, 0, 0.37)
	return frame - frame:VectorToWorldSpace(nockInGrip)
end

function Rig:pose(frame: { [string]: any })
	local cframes = self.cframes
	local up: Vector3 = frame.up or Vector3.yAxis
	local i = 0
	local wrapAt: CFrame? = nil
	for _, side in ipairs({ "Right", "Left" }) do
		local arm = self.arms[side]
		local right = side == "Right"
		local hand: CFrame = if right then frame.right else frame.left
		local shoulder: Vector3 = if right then frame.shoulderRight else frame.shoulderLeft
		local pole: Vector3 = if right then frame.poleRight else frame.poleLeft
		local avatar = self.avatar
		local fac = self.faceted
		if fac then
			-- the faceted arm: the hand piece on the hand frame (its pivot is the wrist), the forearm from the elbow to the
			-- wrist turned with the hand's palm (so the wrist ring lines up), the upper arm from the shoulder to the elbow,
			-- its inner elbow toward the forearm. Locks and the wrist limit as for the avatar arms (frame.lock[side]).
			local lock = frame.lock and frame.lock[side]
			local free = not lock
			local target = hand.Position
			if lock ~= true and Rig.AUTO_POLE > 0 then
				local w = if free then Rig.AUTO_POLE else Rig.FACETED_HAND_LOCK_POLE
				pole = towardElbow(shoulder, target, pole, target - hand.LookVector * Rig.FOREARM, w)
			end
			local elbow, wrist, from = solveArm(shoulder, target, pole)
			hand += wrist - target
			if free then
				hand = limitWrist(hand, wrist, elbow)
			end
			if self.lastDrag then
				self.lastDrag[side] = (from - shoulder).Magnitude
			end
			arm.solved = hand
			local fa = fac[side]
			local mesh = hand * MESH_IN_HAND[side]
			local fore = wrist - elbow
			fore = if fore.Magnitude > 1e-4 then fore.Unit else mesh.UpVector
			local palm = mesh.ZVector
			local zF = palm - fore * palm:Dot(fore)
			if zF.Magnitude < 1e-3 then
				zF = mesh.XVector:Cross(fore)
			end
			zF = zF.Unit
			local upper = elbow - from
			upper = if upper.Magnitude > 1e-4 then upper.Unit else fore
			local zU = fore - upper * fore:Dot(upper)
			if zU.Magnitude < 0.05 then
				zU = zF - upper * zF:Dot(upper) -- (a straight arm: the inner elbow with the palm)
			end
			zU = if zU.Magnitude > 1e-4 then zU.Unit else zF
			local upperCF = CFrame.fromMatrix(from, upper:Cross(zU), upper, zU)
			local foreCF = CFrame.fromMatrix(elbow, fore:Cross(zF), fore, zF)
			if self.blocky and Blocky and frame.eye then
				-- (block arms) an upper arm right beside the eye (a high wind-up, a high cut with the elbow out) would
				-- fill the side of the view with one flat sleeve face: it fades out as its elbow comes close to the eye
				local d = (elbow - frame.eye).Magnitude
				local hide = math.clamp((Blocky.NEAR_SHOW - d) / math.max(Blocky.NEAR_SHOW - Blocky.NEAR_HIDE, 0.01), 0, 1)
				hide = math.floor(hide * 20 + 0.5) / 20
				if hide ~= fa.upperHide then
					fa.upperHide = hide
					for _, p in ipairs(fa.upper.parts) do
						p.LocalTransparencyModifier = hide
					end
				end
			end
			if not right then
				local centre = wrist - fore * (Rig.WRAP_FROM + self.wrapLength / 2)
				if self.blocky then
					centre += zF * self.blocky.palmShift -- (the sleeve block's centre line)
				end
				wrapAt = if self.wrapLength > 0.01 then foreCF.Rotation + centre else nil
			end
			i = placePiece(cframes, i, fa.upper, upperCF)
			i = placePiece(cframes, i, fa.fore, foreCF)
			i = placePiece(cframes, i, fa.hands[fa.hand], mesh)
		elseif avatar then
			-- the R15 arm: the hand on the hand frame (its wrist joint at Rig.WRIST), the forearm turned with the hand;
			-- a free hand turns about its thumb to meet the forearm and never folds past Rig.MAX_WRIST
			-- (frame.lock[side]: true = the hand and the elbow exactly as given; "hand" = the hand exactly as given (a bow,
			-- a bottle at the lips), the elbow still turns toward the hand)
			local lock = frame.lock and frame.lock[side]
			local free = not lock
			if free and Rig.MAX_TWIST > 0 then
				hand = twistToward(hand, shoulder, pole, Rig.GRIP_POINT[side])
			end
			local target = hand * Rig.WRIST
			if lock ~= true and Rig.AUTO_POLE > 0 then
				local w = if free then Rig.AUTO_POLE else Rig.AVATAR_HAND_LOCK_POLE
				pole = towardElbow(shoulder, target, pole, target - hand.LookVector * Rig.FOREARM, w)
			end
			local elbow, wrist, from = solveArm(shoulder, target, pole)
			hand += wrist - target
			if free then
				hand = limitWrist(hand, wrist, elbow)
			end
			if self.lastDrag then
				self.lastDrag[side] = (from - shoulder).Magnitude
			end
			arm.solved = hand
			local placed = avatar.placed[side]
			local thumb = hand.UpVector
			local foreUp = elbow - wrist
			foreUp = if foreUp.Magnitude > 1e-4 then foreUp.Unit else -hand.LookVector
			local upperUp = from - elbow
			upperUp = if upperUp.Magnitude > 1e-4 then upperUp.Unit else foreUp
			-- the upper arm's front faces the way the elbow bends; a straight arm keeps the forearm's
			local bend = -foreUp - upperUp * (-foreUp):Dot(upperUp)
			local foreFront = thumb - foreUp * thumb:Dot(foreUp)
			local w = math.clamp(bend.Magnitude / 0.3, 0, 1)
			local upperFront = (if bend.Magnitude > 1e-4 then bend.Unit * w else Vector3.zero)
				+ (if foreFront.Magnitude > 1e-4 then foreFront.Unit * (1 - w) else Vector3.zero)
			local upperCF = boneFrame(elbow, upperUp, upperFront) * placed.upperOffset
			local foreFrame = boneFrame(wrist, foreUp, thumb)
			local lowerCF = foreFrame * placed.lowerOffset
			if not right then
				wrapAt = if self.wrapLength > 0.01 then foreFrame * CFrame.new(0, Rig.WRAP_FROM + self.wrapLength / 2, 0) else nil
			end
			local handCF = (hand.Rotation * HAND_TO_PART + wrist) * placed.handOffset
			cframes[i + 1], cframes[i + 2], cframes[i + 3] = upperCF, lowerCF, handCF
			i += 3
			if avatar.shades then
				cframes[i + 1], cframes[i + 2], cframes[i + 3] = upperCF, lowerCF, handCF
				i += 3
			end
		else
			local elbow, wrist = solveArm(shoulder, hand.Position, pole)
			hand = hand.Rotation + wrist
			arm.solved = hand
			local fore = alongAxis(elbow, wrist, up)
			local foreDir = (wrist - elbow).Unit
			cframes[i + 1] = alongAxis(shoulder, elbow, up)
			cframes[i + 2] = CFrame.new(elbow)
			cframes[i + 3] = fore
			cframes[i + 4] = fore.Rotation + (wrist - foreDir * 0.035)
			i += 4
			for _, entry in ipairs(arm.hand) do
				i += 1
				cframes[i] = hand * entry.offset
			end
		end
	end
	local item = self.item
	if item then
		local handle = self:handleFrame(self.arms[item.hand].solved) :: CFrame
		self.handleWorld = handle
		-- the bow's nock bead follows the string
		local shift = if item.bow then handle:VectorToWorldSpace(item.attachments.Nock.Position - item.nockRest) else Vector3.zero
		for k, offset in ipairs(item.offsets) do
			i += 1
			local cf = handle * offset
			cframes[i] = if item.followers[k] then cf + shift else cf
		end
	else
		self.handleWorld = nil
	end
	local arrow = self.arrow
	if arrow then
		local handle = if frame.arrow then frame.arrow * arrow.gripInverse else PARKED
		self.arrowWorld = if frame.arrow then handle else nil
		for _, offset in ipairs(arrow.offsets) do
			i += 1
			cframes[i] = handle * offset
		end
	end
	if self.keyAnchor then
		i += 1
		cframes[i] = if typeof(frame.key) == "CFrame" then frame.key else PARKED
	end
	i += 1
	cframes[i] = wrapAt or PARKED
	workspace:BulkMoveTo(self.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Keeps the view bow string about Rig.STRING_PX pixels wide at every depth (a camera-facing beam of one width reads as
-- a flat pale band where it passes close to the eye at full draw). Call after rig:pose.
function Rig:updateView(camCF: CFrame, fov: number, viewportHeight: number)
	local item = self.item
	local handle = self.handleWorld
	if not (item and item.strings and handle) or viewportHeight <= 0 then
		return
	end
	local perStud = Rig.STRING_PX * 2 * math.tan(math.rad(fov) / 2) / viewportHeight
	for _, beam in ipairs(item.strings) do
		local a0, a1 = beam.Attachment0, beam.Attachment1
		if a0 and a1 then
			local d0 = -camCF:PointToObjectSpace(handle * a0.Position).Z
			local d1 = -camCF:PointToObjectSpace(handle * a1.Position).Z
			beam.Width0 = math.clamp(math.max(d0, 0.05) * perStud, Rig.STRING_MIN_WIDTH, Rig.STRING_MAX_WIDTH)
			beam.Width1 = math.clamp(math.max(d1, 0.05) * perStud, Rig.STRING_MIN_WIDTH, Rig.STRING_MAX_WIDTH)
		end
	end
end

function Rig:muzzle(): Vector3?
	local arrow = self.arrow
	if arrow and self.arrowWorld and not self.arrowHidden then
		local tip = arrow.attachments.Tip
		if tip then
			return self.arrowWorld * tip.Position
		end
	end
	local item = self.item
	local handle = self.handleWorld
	if item and handle then
		local tip = item.attachments.Tip
		if tip and item.itemId == "spear" then
			return handle * tip.Position
		end
		return handle.Position
	end
	return nil
end

function Rig:destroy()
	self.model:Destroy()
	if self.keyAnchor then
		self.keyAnchor:Destroy() -- (it may be in the workspace)
	end
	if self.exposure then
		self.exposure:Destroy()
	end
end

return Rig
