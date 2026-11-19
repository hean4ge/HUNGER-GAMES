--[[
	ViewmodelController - first-person arms and the held item. Client only.

	Visible only in first person, in the arena, alive and not spectating. The arms (Config.Viewmodel.ArmStyle) are the
	block arms ("Blocky", the default: a Roblox character's arms, square blocks built from Parts by the child module
	Blocky, the hands in the avatar's own arm colours, a plain sleeve; matte and lit by the engine alone: no lamp, no
	Highlight, no layer over them. Config.Viewmodel.Blocky picks the hand, one block or a palm with a finger block and a
	thumb, and the sleeve; its Shade values bring pale arm colours down toward the scene's level at dusk, at night and
	under trees, by colour alone. They stand on the faceted arms' skeleton and take their poses, with their own rest,
	guard and open-hand frames, Blocky.poses), the
	faceted Blender arms ("Faceted": bare skin in the avatar's arm colours, a charcoal sleeve; one hand mesh
	per side at a time, Rig:setHands: relaxed when the hands are empty, a fist only while punching (raised on Attack,
	held as a guard Config.Viewmodel.GuardHold seconds after the last punch, then lowered out of view and relaxed),
	closed round handles and the bow string, open for food and bottles), the player's own avatar arms ("Avatar": R15
	UpperArm / LowerArm / Hand with their skin colour and shirt, Rig:setAvatar, rebuilt when the character's arms,
	shirt or colours change), or the part-built arms ("Classic": dark fabric sleeves, cuffs, fists in the skin colour
	of the local character's hands). The held item comes from
	ItemModels.build(id, "view"), placed at the hand by its Grip attachment (a bow sits in the left hand and the
	right hand draws the string). Child modules: Rig (parts, two-bone IK, item placement, BulkMoveTo) and Poses
	(hand poses and keyframes).

	Rendered every frame after the camera effects (BindToRenderStep at RenderPriority.Camera + 2) at
	camera.CFrame * offsets. Procedural motion with Shared.Spring: idle breathing, look sway from
	ClientState.lookDelta, walk/sprint bob synced to ClientState.strideAlpha (scaled by settings.headBob), sprint pose
	(weapon lowered and angled), slide tilt, crouch offset, landing dip (ClientState.landed), jump lift, equip raise
	(from the lower right, never across the crosshair), melee swings by weight (windup, strike with hit-stop,
	follow-through; the swing set CombatController picked, Poses.swing, with the set's own elbow pole and recoil side and a
	little variation from the swing's seed, CombatController.swingJitter), bow hold and draw (the bow waits at a low ready with the drawing hand on the nock, its wrist in
	line with a forearm that comes in from the lower right; drawing pulls the string back while the bow is pushed out
	and down a little and then raised, so the drawing hand drops back and down out of view early, well away from the
	eye, and arrives at an under-chin anchor; the string bends at the nock and stays a thin line, Rig:updateView; the
	arrow on the rest beside the riser; the release snaps the string and the bow hand follows through down and to the
	left; the crosshair area stays clear throughout, see Poses.HOLD.BowDrawn), throws, eat/drink/bandage/armor poses
	while ClientState.useProgress (a bottle is tipped up to the mouth from the right; a bandage roll is wound round the
	left forearm at the lower left; armor is swung out and over the right shoulder and then pulled closed across the
	chest at the bottom of the view), recoil, a tuck when the camera
	is against a wall (the bow is pulled in upright and the string let down, Poses.bowTuck), and lowered hands while
	climbing, mantling or swimming. The spear rests in a low guard across the body with the left hand on the shaft.
	Empty hands: relaxed and low; the fists come up only for a punch and the short guard after it (Blocky, Faceted; the
	older styles keep the fists up).
	V zoom (ClientState.zoomAlpha and zoomMag, written by CameraController): free hands and whatever they hold sink out
	of the bottom of the view early in the zoom and come back as it lets go (a zoomed view would draw them several
	times larger); a hand that is busy stays up, except that a swing, a throw, a use or a draw begun under the zoom
	keeps the hands down until the view has eased most of the way back (ZOOM_BUSY_MAG).
	Field of view setting: the holds are drawn for Config.Camera.BaseFov. At another setting each arm is moved as one
	piece so that its hand keeps its place on screen, clear of the hotbar and the vitals (fovFit).

	API
	  ViewmodelController.setArms(style?, options?) -> string   rebuilds the arms: another style, or (Blocky) other
	                                      values than Config.Viewmodel.Blocky's, e.g. { Variant = "B" } (previews, tests)
	  ViewmodelController.isVisible() -> boolean
	  ViewmodelController.visibilityChanged: Signal(visible)   (also LocalPlayer attribute "ViewmodelVisible")
	  ViewmodelController.getMuzzle() -> Vector3?   where a shot leaves the weapon (used for predicted projectiles)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Moves = require(Shared:WaitForChild("Moves"))
local Signal = require(Shared:WaitForChild("Signal"))
local Spring = require(Shared:WaitForChild("Spring"))
local Util = require(Shared:WaitForChild("Util"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Rig = require(script:WaitForChild("Rig"))
local Poses = require(script:WaitForChild("Poses"))
local Shade = require(script:WaitForChild("Shade"))

local player = Players.LocalPlayer

local ViewmodelController = {}
ViewmodelController.visibilityChanged = Signal.new()

local FIRST_PERSON_DISTANCE = 3.5 -- the camera is this close to the head in first person
local PIVOT = Vector3.new(0.25, -0.85, -1.2) -- pose rotations (sprint, equip, recoil) turn around this point
local SPEAR_REACH = Poses.SPEAR_REACH or 1.16 -- the supporting hand's distance up the spear shaft
-- Bow: how far the string is pulled at full draw in first person (studs). Longer than the mesh bow's own MaxDraw, so the
-- nock reaches an under-chin anchor with the bow arm extended (Poses.HOLD.BowDrawn is built for this length).
local BOW_DRAW = Config.Combat.ViewBowDraw or 1.35
-- Config.Viewmodel.ArmStyle: "Blocky" (Roblox block arms built from Parts, the default), "Faceted" (the Blender arms),
-- "Avatar" (the player's own R15 arms) or "Classic" (the first part-built arms)
local VIEWMODEL = Config.Viewmodel or {}
local ARM_STYLES: { [string]: boolean } = { Blocky = true, Faceted = true, Avatar = true, Classic = true }
local ARM_STYLE = if ARM_STYLES[VIEWMODEL.ArmStyle] then VIEWMODEL.ArmStyle else "Blocky"
-- (Blocky, Faceted) empty hands: the guard is held this long after the last punch, then the hands are lowered and relax
local GUARD_HOLD = tonumber(VIEWMODEL.GuardHold) or 1.5
-- V zoom (CameraController narrows the field of view as ClientState.zoomAlpha goes 0..1): the viewmodel is world
-- geometry at the eye, so the zoomed view draws it as many times larger as everything else. So free hands and
-- whatever they hold sink out of the bottom of the view early in the zoom, from zoomAlpha ZOOM_SINK_FROM and gone by
-- ZOOM_SINK_BY (before the view is half as large again), and come back the same way as the zoom lets go. A hand that
-- is busy (a swing, a throw, a use, a drawn or aimed weapon) stays up.
local ZOOM_SINK_FROM = 0.04
local ZOOM_SINK_BY = 0.3
local ZOOM_SINK_RATE = 20 -- 1/s: how fast the hands go down ...
local ZOOM_RISE_RATE = 12 -- ... and come back
-- A swing, a throw, a use or a draw ends the zoom (CameraController), but the view takes a moment to ease back out.
-- Hands that came up at once showed two times too large for those frames (a sword swung under the zoom). So busy
-- hands that are down stay down while the zoom still magnifies more than this, and rise from there.
local ZOOM_BUSY_MAG = 1.2
-- The field-of-view setting. Every hold is drawn for BASE_FOV (72): the hand frames are fixed in camera space while the
-- HUD is fixed on screen, so at a wider setting the hands slid in over the hotbar and the vitals (at 100 the bow arm
-- covered most of the hotbar) and at 55 the resting hands left the view. Each arm (its hand, shoulder and what it
-- holds) is therefore moved sideways and up or down as one piece, by (k - 1) x its hand's own x and y in camera space,
-- k = tan(setting / 2) / tan(BASE_FOV / 2): the hand then sits where it does at the base setting, and only looks
-- smaller or larger, as the world does. Hands that work together move together, by the leading hand's offset (the bow
-- hand and the hand on its string; the hand forward on a spear's shaft; the forearm a bandage is wound round).
-- At a narrower setting the hands draw larger, and a hand held at its place would grow over the HUD beside it: there it
-- keeps its outer, lower side instead, FIT_EDGE studs out from its frame. Measured on a 16:9 screen with the HUD's own
-- boxes, in play on Map 1: at 90 and 100 every resting hold is as clear of the hotbar and the vitals as at 72; at 55
-- the hands stay in view and off the hotbar (the bow hand covers about 3 % of the vitals' end there).
local BASE_FOV = (Config.Camera and tonumber(Config.Camera.BaseFov)) or 72
local FIT_EDGE = 0.4
-- (the hand that leads a two-handed hold, the bow hand and the hand on a spear's shaft, is the one beside the vitals:
-- at a narrower setting it keeps this much instead, so it grows toward the middle of the gap and not over the bars.
-- At 55 with the bow: 0.4 covered 9 % of the vitals, 0.2 4 %, 0 put it on the first hotbar slot)
local FIT_LEAD_EDGE = 0.15
-- A screen narrower than 16:10 (a 4:3 tablet): the HUD keeps its size while the view loses its sides, so the vitals
-- reach in under the resting left hand (16 % of their box at 4:3). There is no room beside them (the gap to the hotbar
-- is 73 px, the hand 170), so the empty hands rest lower there, NARROW_DROP studs at 4:3 and nothing at 16:10 or wider.
-- Only the rest: the guard and the punches are as on every screen. (0.10 leaves 1 % of the vitals' box under the hand
-- and the hands' tops still in view; 0.13 clears the box and all but hides them.)
local NARROW_FROM = 1.6
local NARROW_FULL = 4 / 3
local NARROW_DROP = 0.10
-- (the three numbers a look test may change while the game runs)
ViewmodelController.Fit = { Edge = FIT_EDGE, LeadEdge = FIT_LEAD_EDGE, NarrowDrop = NARROW_DROP }
local FIT_LEAD_RATE = 14 -- 1/s: how fast an arm passes from its own offset to the leading hand's and back
local HIT_STOP: { [string]: number } = { Light = 0.045, Medium = 0.06, Heavy = 0.085 }
local LOWER_MOVES: { [string]: boolean } = { Climb = true, Mantle = true, Swim = true, Sit = true } -- Sit: in a tree (TreeSeatController)
local USE_STYLE: { [string]: string } = {
	water_bottle = "Drink", empty_bottle = "Drink", bandage = "Wrap", medkit = "Bandage", herbs = "Eat",
}
local USE_BY_KIND: { [string]: string } = { Food = "Eat", Drink = "Drink", Heal = "Bandage", Armor = "Armor" }

local Controllers: { [string]: any } = {}
local camera: Camera? = workspace.CurrentCamera
local rig: any = nil
local shade: any = nil -- (Avatar arms) Shade: the light on the arms (exposure, sky key, shade layer)
local visible = false
local initialized = false

local heldId: string? = nil

-- A camera-space hand frame mirrored across the view's centre line (x -> -x), still a proper rotation.
local function mirrorX(cf: CFrame): CFrame
	local p = cf.Position
	return CFrame.fromMatrix(Vector3.new(-p.X, p.Y, p.Z), cf.XVector * Vector3.new(1, -1, -1),
		cf.YVector * Vector3.new(-1, 1, 1), cf.ZVector * Vector3.new(-1, 1, 1))
end
local heldKey = ""
local heldDef: any = nil
local heldKind = "Fists"

local springs = {
	sway = Spring.new(Vector3.zero, 13, 0.62), -- (pitch, yaw) lag behind the camera
	lean = Spring.new(Vector3.zero, 8, 0.85), -- strafe / forward lean from velocity
	land = Spring.new(0, 11, 0.42), -- vertical dip on landing and jumping
	recoil = Spring.new(Vector3.zero, 17, 0.5), -- (pitch, yaw, roll) kick
	kick = Spring.new(0, 18, 0.55), -- push back along the view
	string = Spring.new(0, 42, 0.3), -- bow string snap with a little overshoot
}
local alpha = { sprint = 0, slide = 0, lower = 0, tuck = 0, use = 0, air = 0, bob = 0, raise = 0, dip = 0, guard = 0, gdip = 0, zoom = 0, lead = 0,
	fguard = 0, fcharge = 0 }
local lastPunchAt = -10 -- (Blocky, Faceted) when the last punch started (the guard is held GUARD_HOLD after it)

local equipStart = -10
local equipDuration = 0.32
local anim: { [string]: any }? = nil
local hitStop = 0
local itemHiddenUntil = 0
local hiddenAt = 0
local arrowHiddenUntil = 0
local useStartedAt = 0
local wasUsing = false
local useHidItem = false -- the used item is out of view (armor once it is over the shoulder: Poses.useHidesItem)
local fullDrawSince: number? = nil
local skinCheckAt = 0
local avatarSignature: string? = nil -- what the avatar arms were last built from (Rig.avatarSignature)
local avatarCheckAt = 0
local avatarBuilding = false
local pendingArms: any = nil -- built arms waiting to be shown (false: the Classic arms)
local lastRightCam = CFrame.identity
local lastLeftCam = CFrame.identity
local muzzle: Vector3? = nil
-- Combat v3 (CombatController.action): the guard, the heavy's hold, a dodge, a skill (see onCombatAction)
local fight: { [string]: any } = { guard = false, charge = nil, dodge = nil, skill = nil, lastSwingEnd = -10, viewUntil = -10,
	viewTrack = nil, viewW = 0 }
local FIGHT = {
	guardIn = 22, guardOut = 14, -- 1/s: the guard comes up in about 0.1 s and goes down in about 0.12 (Moves.cfg.Guard)
	chainGap = 0.12, -- s: a swing starting this soon after the last one ended (or during it) flows on from its hand
	lead = 0.13, -- radians: how far the whole arm and shoulder turn with a cut (the body leads the blade)
}

local tuckParams = RaycastParams.new()
tuckParams.FilterType = Enum.RaycastFilterType.Exclude
tuckParams.RespectCanCollide = true
tuckParams.IgnoreWater = true

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function approach(key: string, target: number, rate: number, dt: number)
	local value = alpha[key]
	value += (target - value) * Util.damp(rate, dt)
	if math.abs(value - target) < 1e-3 then
		value = target
	end
	alpha[key] = value
end

local function about(pivot: Vector3, rotation: CFrame): CFrame
	return CFrame.new(pivot) * rotation * CFrame.new(-pivot)
end

-- How much wider (or narrower) the view is than the one the holds are drawn for: tan(setting / 2) / tan(BASE_FOV / 2).
local function fovFit(): number
	local settings = ClientState.settings
	local fov = math.clamp(tonumber(settings and settings.fov) or BASE_FOV, 40, 110)
	return math.tan(math.rad(fov) / 2) / math.tan(math.rad(BASE_FOV) / 2)
end

-- How far an arm moves (camera space) for its hand at `position` to keep its place on screen at fit k (fovFit).
local function fitOffset(position: Vector3, k: number, edge: number?): Vector3
	local offset = Vector3.new(position.X, position.Y, 0) * (k - 1)
	if k < 1 then
		offset += Vector3.new(math.sign(position.X) * (edge or ViewmodelController.Fit.Edge), -ViewmodelController.Fit.Edge, 0) * (1 - k)
	end
	return offset
end

-- How narrow the screen is: 0 at 16:10 and wider, 1 at 4:3 (NARROW_*). setViewShape replaces the window's own shape.
local viewShape: number? = nil
local function narrowFit(cam: Camera): number
	local size = cam.ViewportSize
	local shape = viewShape or size.X / math.max(size.Y, 1)
	return math.clamp((NARROW_FROM - shape) / (NARROW_FROM - NARROW_FULL), 0, 1.3)
end

-- Throwable melee weapons held one-handed like a blade, not in the spear's two-handed guard: the Ring Blade's hoop in
-- the guard filled the middle of the view (Poses.FACETED.HOLD_ITEM.ring_blade places it at the lower right).
local ONE_HAND_THROW = { ring_blade = true }

local function holdKindFor(def: any): string
	if not def then
		return "Fists"
	elseif def.kind == "Melee" then
		-- (only the spear takes the spear's two-handed hold: the hatchet, twin axe, knife and dagger took it too, so in
		-- first person an axe was held and thrown like a javelin, the owner's "throwing animation for the axe is so off")
		return if def.throwable and not ONE_HAND_THROW[def.id] and def.id == "spear" then "Spear" else "Blade"
	elseif def.kind == "Bow" then
		return "Bow"
	elseif def.kind == "Throwable" then
		return "Throwable"
	elseif def.kind == "Armor" then
		return "Armor"
	end
	return "Item"
end

-- The skin colour of the local character's right arm (and, second, its left arm).
local function skinColor(): (Color3?, Color3?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local colors = character:FindFirstChildOfClass("BodyColors")
	local function side(name: string, r6: string, fallback: Color3?): Color3?
		local hand = character:FindFirstChild(name .. "Hand") or character:FindFirstChild(r6)
		if hand and hand:IsA("BasePart") then
			return hand.Color
		end
		return fallback
	end
	local right = side("Right", "Right Arm", if colors then colors.RightArmColor3 else nil)
	local left = side("Left", "Left Arm", if colors then colors.LeftArmColor3 else nil)
	return right, left or right
end

-- (Avatar arms) rebuilds them when the character's arms, shirt or arm colours have changed. Runs on Heartbeat, outside
-- the render step: the arms are built over two frames (Rig:buildAvatar with task.wait between its halves) and shown on
-- the frame after (pendingArms, Rig:useArms), so no frame pays for the whole build inside the viewmodel's step.
local function refreshAvatar()
	if not rig or rig.style ~= "Avatar" or avatarBuilding then
		return
	end
	local character = player.Character
	local signature = Rig.avatarSignature(character)
	if signature == avatarSignature then
		return
	end
	avatarSignature = signature
	avatarBuilding = true
	task.spawn(function()
		local ok, arms = pcall(rig.buildAvatar, rig, character, task.wait)
		avatarBuilding = false
		if ok then
			pendingArms = arms or false
		else
			avatarSignature = nil -- (try again on the next check)
			warn("[ViewmodelController] avatar arms: " .. tostring(arms))
		end
	end)
end

local function onHeartbeat()
	if not rig then
		return
	end
	if pendingArms ~= nil then
		local arms = pendingArms
		pendingArms = nil
		rig:useArms(arms or nil)
	end
	local now = os.clock()
	if visible and now >= avatarCheckAt then
		avatarCheckAt = now + 1
		refreshAvatar()
	end
end

local function countItem(itemId: string): number
	local combat = Controllers.CombatController
	if combat and type(combat.countItem) == "function" then
		return combat.countItem(itemId)
	end
	local total = 0
	local slots = ClientState.inventory and ClientState.inventory.slots
	if type(slots) == "table" then
		for _, slot in pairs(slots) do
			if type(slot) == "table" and slot.id == itemId then
				total += tonumber(slot.count) or 1
			end
		end
	end
	return total
end

local function useStyle(): string
	if heldId and USE_STYLE[heldId] then
		return USE_STYLE[heldId]
	end
	return (heldDef and USE_BY_KIND[heldDef.kind]) or "Eat"
end

--------------------------------------------------------------------------------------------------------------------
-- Visibility and the held item
--------------------------------------------------------------------------------------------------------------------

local function wantVisible(): boolean
	local inHall = player:GetAttribute("InTraining") == true -- (the Training Centre: first person there too)
	if not ((ClientState.inArena and ClientState.alive) or inHall) or ClientState.spectating ~= nil or ClientState.launchShot then
		return false -- (and never during the launch intro: LaunchIntroController has the camera)
	end
	local cam = camera
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not cam or not (head and head:IsA("BasePart")) or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (cam.CFrame.Position - head.Position).Magnitude < FIRST_PERSON_DISTANCE
end

local function resetMotion()
	springs.sway:reset(Vector3.zero)
	springs.lean:reset(Vector3.zero)
	springs.land:reset(0)
	springs.recoil:reset(Vector3.zero)
	springs.kick:reset(0)
	springs.string:reset(0)
	for key in pairs(alpha) do
		alpha[key] = 0
	end
	anim = nil
	hitStop = 0
end

local function setVisible(on: boolean)
	visible = on
	if on then
		local color, left = skinColor()
		if color then
			rig:setSkin(color, left)
		end
		avatarCheckAt = 0 -- (checked on the next Heartbeat)
		if shade then
			shade:reset()
		end
		resetMotion()
		equipStart = os.clock()
		equipDuration = 0.4 -- the arms rise into view
		rig.model.Parent = camera
		if shade and not rig.blocky then
			rig:setKeyParent(workspace) -- (the arms' key light: in the workspace, a light in the camera gives none)
		end -- (the block arms have no lamp: the engine's light only)
	else
		rig.model.Parent = nil
		rig:setKeyParent(nil)
		anim = nil
		muzzle = nil
	end
	player:SetAttribute("ViewmodelVisible", on)
	ViewmodelController.visibilityChanged:Fire(on)
end

local function syncItem(now: number)
	local id = ClientState.getEquippedItemId()
	local inventory = ClientState.inventory
	local slot = inventory and inventory.slots and inventory.slots[inventory.equipped]
	local stars = if type(slot) == "table" then tonumber(slot.stars) else nil
	local key = tostring(if inventory then inventory.equipped else 0) .. ":" .. tostring(id) .. ":" .. tostring(stars)
	if initialized and key == heldKey then
		return
	end
	initialized = true
	heldKey = key
	heldId = id
	heldDef = ItemDefs.get(id)
	heldKind = holdKindFor(heldDef)
	local shown = heldDef ~= nil and not heldDef.hidden
	rig:setItemHidden(false)
	useHidItem = false
	rig:setItem(if shown then id else nil, if heldKind == "Bow" then "Left" else "Right", stars)
	rig:setArrow(heldKind == "Bow")
	itemHiddenUntil = 0
	arrowHiddenUntil = 0
	anim = nil
	alpha.raise = 0
	springs.string:reset(0)
	equipStart = now
	equipDuration = (Config.Combat.EquipTime or 0.32) + (if heldKind == "Bow" then 0.12 else 0)
	-- (InventoryController plays the equip sound)
end

--------------------------------------------------------------------------------------------------------------------
-- Combat events
--------------------------------------------------------------------------------------------------------------------

-- A swing's small variation from its seed (CombatController.swingJitter: the same every time for one seed), or nil.
local function swingJitter(seed: any): any
	local combat = Controllers.CombatController
	if seed ~= nil and combat and type(combat.swingJitter) == "function" then
		local ok, jitter = pcall(combat.swingJitter, seed)
		if ok and type(jitter) == "table" then
			return jitter
		end
	end
	return nil
end

local function onCombatAction(name: string, data: any)
	if type(data) ~= "table" then
		return
	end
	local now = os.clock()
	if name == "Swing" then
		if data.style == "Punch" then
			lastPunchAt = now -- (Faceted) the fists come up and stay up as a guard for GUARD_HOLD
		end
		-- a chain flows: the next step starts from where the last one's hand is (Poses.swing chain.from)
		local flowing = (anim ~= nil and anim.kind == "Swing") or now - fight.lastSwingEnd < FIGHT.chainGap
		local side = if type(Poses.swingSide) == "function" then Poses.swingSide(data.style, data.variant or 1) else "Right"
		local from = if flowing and data.style ~= "Kick" then (if side == "Left" then lastLeftCam else lastRightCam) else nil
		fight.charge = nil
		-- the move's Blender clip, when the clip player has it
		local cp = Controllers.ClipPlayer
		local clip = Moves.clipName(data.itemId, data.moveId)
		if cp and clip and type(cp.playView) == "function" and type(cp.has) == "function" and cp.has(clip) then
			local ok, track = pcall(cp.playView, clip, { lead = data.windup or 0.1, total = data.total or 0.5 })
			if ok and track then
				fight.viewTrack = track
				fight.viewUntil = now + (data.total or 0.5) + 0.4
			end
		end
		anim = {
			clip = clip,
			chainFrom = from,
			side = side,
			heavy = type(data.move) == "table" and data.move.heavyHit == true,
			kind = "Swing",
			t = 0,
			style = data.style,
			weight = data.weight,
			variant = data.variant or 1,
			windup = data.windup or 0.1,
			strike = data.strike or 0.1,
			total = data.total or 0.5,
			jitter = swingJitter(data.seed), -- (each swing a little different: Poses.swing)
		}
	elseif name == "Strike" then
		-- the recoil goes the way the set's camera kick goes (Poses.swingKick; without one, odd sets to the left)
		local dir = if type(Poses.swingKick) == "function" then Poses.swingKick(data.style, data.variant or 1) else nil
		local side = if dir then math.clamp(dir.Y / math.max(dir.Magnitude, 1e-3) * 1.5, -1, 1)
			else (if (data.variant or 1) % 2 == 0 then -1 else 1)
		if data.hit then
			local strength = if data.hit == "Character" then 1 else 0.7
			hitStop = (HIT_STOP[data.weight] or 0.06) * strength
			springs.recoil:impulse(Vector3.new(0.9, 0.25 * side, 0.45 * side) * strength)
			springs.kick:impulse(2.4 * strength)
		else
			springs.recoil:impulse(Vector3.new(-0.25, 0.1 * side, 0.15 * side))
		end
	elseif name == "ThrowStart" then
		anim = { kind = "Throw", t = 0, spear = data.spear == true, windup = data.windup or 0.1, total = data.total or 0.5 }
		-- the Throwing family's Blender clip (FightClips: throw_knife, throw_dagger, throw_ring, throw_hatchet,
		-- throw_spear, throw_twinaxe), fitted to the release; the procedural throw stays under it as the fallback
		local cp = Controllers.ClipPlayer
		local okFc, FightClips = pcall(require, ReplicatedStorage.Shared:FindFirstChild("FightClips") :: ModuleScript)
		local throwId = if type(data.itemId) == "string" then data.itemId else heldId
		local clip = if okFc and throwId then FightClips.forMove(throwId, "Throw") else nil
		if cp and clip and type(cp.playView) == "function" and type(cp.has) == "function" and cp.has(clip) then
			local ok, track = pcall(cp.playView, clip, { lead = data.windup or 0.1, total = data.total or 0.5 })
			if ok and track then
				fight.viewTrack = track
				fight.viewUntil = now + (data.total or 0.5) + 0.4
			end
		end
	elseif name == "ThrowRelease" then
		rig:setItemHidden(true)
		itemHiddenUntil = if data.last then math.huge else now + 0.3
		hiddenAt = now
	elseif name == "Release" then
		local charge = tonumber(data.charge) or 1
		-- the bow kicks down and to the left, away from the crosshair (never up across it)
		springs.recoil:impulse(Vector3.new(-(0.5 + charge * 0.4), 0.3 * charge, 0.35 * charge))
		springs.kick:impulse(-1.2)
		anim = { kind = "BowRelease", t = 0, total = 0.32, from = lastRightCam }
		arrowHiddenUntil = now + 0.3
	elseif name == "DrawCancel" then
		if anim and anim.kind ~= "Swing" then
			anim = nil
		end
	-- Combat v3
	elseif name == "GuardUp" then
		fight.guard = true
		lastPunchAt = now
	elseif name == "GuardDown" then
		fight.guard = false
	elseif name == "ChargeStart" then
		fight.charge = { t0 = now }
	elseif name == "ChargeCancel" then
		fight.charge = nil
	elseif name == "Dodge" then
		fight.dodge = { t0 = now, kind = data.kind or "Back", total = (data.startup or 0.15) + (data.travel or 0.25) + 0.15 }
		if anim and anim.kind == "Swing" and anim.t < anim.windup then
			anim = nil
		end
	elseif name == "Skill" then
		fight.skill = { id = data.id, t0 = now, total = data.total or 0.6 }
	elseif name == "Parry" then
		-- a clean deflection: the blade flicks up and out, then settles
		springs.recoil:impulse(Vector3.new(-1.3, 0.4, 0.7))
		springs.kick:impulse(-1.2)
		hitStop = 0.06
	elseif name == "Block" then
		springs.recoil:impulse(Vector3.new(if data.heavy then 1.2 else 0.7, 0.15, 0.25))
		springs.kick:impulse(if data.heavy then 2.6 else 1.6)
	elseif name == "Parried" then
		-- our blow was turned: the weapon rebounds back toward us
		springs.recoil:impulse(Vector3.new(1.6, -0.5, -0.6))
		springs.kick:impulse(3)
		anim = nil
	elseif name == "GuardBreak" then
		fight.guard = false
		springs.recoil:impulse(Vector3.new(1.8, 0.3, 0.5))
		springs.kick:impulse(3)
	elseif name == "Reaction" then
		local rank = ({ Flinch = 1, Stagger = 2, Heavy = 3, Knockdown = 4 })[data.tier or ""] or 1
		springs.recoil:impulse(Vector3.new(0.35 * rank, 0.25 * rank * (if math.random() < 0.5 then -1 else 1), 0.2 * rank))
		springs.kick:impulse(0.8 * rank)
		if rank >= 2 and anim and anim.kind == "Swing" and anim.t < anim.windup then
			anim = nil -- (staggered while winding up: the swing is gone, as the server refuses it)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------------------------------------------

local function update(dt: number)
	if not rig then
		return
	end
	dt = math.min(dt, 0.1)
	if workspace.CurrentCamera ~= camera then
		camera = workspace.CurrentCamera
		if visible and camera then
			rig.model.Parent = camera
		end
	end
	local cam = camera
	if not cam then
		return
	end
	local show = wantVisible()
	if show ~= visible then
		setVisible(show)
	end
	if not visible then
		return
	end

	local now = os.clock()
	syncItem(now)
	if now >= skinCheckAt then
		skinCheckAt = now + 1
		local color, left = skinColor()
		if color and (color ~= rig.skin or (left and left ~= rig.skinLeft)) then
			rig:setSkin(color, left)
		end
	end
	if Poses.STYLE ~= Rig.STYLE then
		Poses.useStyle(Rig.STYLE) -- (the avatar arms' own holds and use poses)
	end

	-- One-shot animation clock (slowed for a moment on impact: hit-stop)
	local stopped = hitStop > 0 or now < (tonumber(ClientState.hitStopUntil) or 0)
	if anim then
		local rate = if stopped then 0.12 else 1
		anim.t += dt * rate
		if anim.t >= anim.total then
			if anim.kind == "Swing" then
				fight.lastSwingEnd = now
			end
			anim = nil
		end
	end
	hitStop = math.max(0, hitStop - dt)
	local unhide = itemHiddenUntil > 0 and itemHiddenUntil ~= math.huge and now >= itemHiddenUntil
	if itemHiddenUntil == math.huge and now - hiddenAt > 1.6 and heldId and countItem(heldId) > 0 then
		unhide = true -- the server kept the weapon (the throw was refused)
	end
	if unhide then
		itemHiddenUntil = 0
		rig:setItemHidden(false)
		equipStart = now
		equipDuration = 0.22
	end

	-- Inputs
	local moveState = ClientState.moveState
	local grounded = ClientState.grounded ~= false
	local aim = math.clamp(ClientState.aimAlpha or 0, 0, 1)
	local draw = math.clamp(ClientState.drawAlpha or 0, 0, 1)
	local using = ClientState.useProgress ~= nil
	local speed = ClientState.speed or 0
	local velocity: Vector3 = if typeof(ClientState.velocity) == "Vector3" then ClientState.velocity else Vector3.zero
	local settings = ClientState.settings or {}
	local headBob = math.clamp(tonumber(settings.headBob) or 1, 0, 1)
	local camCF = cam.CFrame

	if using and not wasUsing then
		useStartedAt = now
	end
	wasUsing = using

	local busy = anim ~= nil or draw > 0 or aim > 0.1 or using
	-- V zoom: free hands sink out of view as the zoom comes on and come back as it goes (ZOOM_SINK_*), and whatever
	-- still shows moves less (the zoomed view draws every movement larger)
	local zoom = math.clamp(tonumber(ClientState.zoomAlpha) or 0, 0, 1)
	-- (CameraController publishes the zoom's magnification, 1 = none; without it, a guess from the alpha)
	local zoomMag = tonumber((ClientState :: any).zoomMag)
	local sink = Poses.smooth(math.clamp((zoom - ZOOM_SINK_FROM) / (ZOOM_SINK_BY - ZOOM_SINK_FROM), 0, 1))
	if busy then
		-- busy hands come up, but not into a view that is still magnified (ZOOM_BUSY_MAG): there they stay as they are
		local mag = if zoomMag and zoomMag >= 1 then zoomMag else 1 + 1.5 * zoom
		sink = if mag > ZOOM_BUSY_MAG then alpha.zoom else 0
	end
	approach("zoom", sink, if sink > alpha.zoom then ZOOM_SINK_RATE else ZOOM_RISE_RATE, dt)
	local zoomCalm = if zoomMag and zoomMag >= 1 then 1 / zoomMag else 1 - 0.7 * zoom
	approach("sprint", if moveState == "Sprint" and grounded and not busy then 1 else 0, 9, dt)
	approach("slide", if moveState == "Slide" then 1 else 0, 10, dt)
	approach("lower", if LOWER_MOVES[moveState] then 1 else 0, 8, dt)
	approach("use", if using then 1 else 0, 10, dt)
	approach("air", if grounded then 0 else 1, 6, dt)
	local moving = grounded and speed > 0.5 and not LOWER_MOVES[moveState] and moveState ~= "Slide"
	local bobTarget = if moving then math.clamp(speed / math.max(Config.Movement.WalkSpeed, 1), 0, 1.7) else 0
	approach("bob", bobTarget * headBob * (1 - 0.65 * aim) * zoomCalm, 8, dt)

	-- Wall tuck: pull the weapon in when the camera is right against something
	local list = { cam }
	if player.Character then
		table.insert(list, player.Character)
	end
	local effects = workspace:FindFirstChild("ClientProjectiles")
	if effects then
		table.insert(list, effects)
	end
	tuckParams.FilterDescendantsInstances = list
	local wall = workspace:Raycast(camCF.Position, camCF.LookVector * 3, tuckParams)
	approach("tuck", if wall then math.clamp((2.4 - wall.Distance) / 1.4, 0, 1) else 0, 10, dt)

	-- Base pose for what we hold
	local right: CFrame, left: CFrame
	local raised = 0
	if heldKind == "Spear" then
		raised = if anim and anim.kind == "Throw" then 1 else aim
		right = Poses.spearRaise(raised)
		left = Poses.HOLD.SpearRaised.left
	else
		if heldKind == "Bow" then
			-- drawing raises the bow from the low ready to the shooting position (pushing it out and down a little
			-- while the string comes back); it drops back after the shot
			local lift = Poses.bowRaise(draw)
			approach("raise", lift, if lift > alpha.raise then 16 else 7, dt)
			local dip = Poses.bowDip(draw)
			approach("dip", dip, if dip > alpha.dip then 18 else 8, dt)
		end
		right, left = Poses.hold(heldKind, if heldKind == "Bow" then alpha.raise else aim, heldId)
		if heldKind == "Bow" then
			left += Poses.BOW_DIP * alpha.dip
			right, left = Poses.bowTuck(right, left, alpha.tuck) -- against a wall: pulled in upright
		elseif heldKind == "Fists" and rig.faceted then
			-- (Faceted) empty hands rest low and relaxed; a punch raises them to the guard (Poses.HOLD.Fists), held for
			-- GUARD_HOLD after the last one; then they are lowered, dipping out of view on the way down (where the fists
			-- relax), back to the rest
			local punching = anim ~= nil and anim.kind == "Swing" and anim.style == "Punch"
			local guardUp = punching or now - lastPunchAt < GUARD_HOLD or fight.guard or fight.charge ~= nil
			approach("guard", if guardUp then 1 else 0, if guardUp then 22 else 3.2, dt)
			approach("gdip", if guardUp then 0 else math.sin(math.pi * alpha.guard), 30, dt)
			local restRight, restLeft = Poses.hold("Relaxed")
			right = Poses.guardBlend(restRight, right, alpha.guard, alpha.gdip)
			left = Poses.guardBlend(restLeft, left, alpha.guard, alpha.gdip)
		end
	end
	-- an off-hand pair (the Paired Blades: Rig holds the second blade in the left hand): the left hand holds its blade
	-- as the right does, mirrored across the view, so both are seen; the paired clips (fpLeft) move it from there
	local pairDef = if heldId then ItemDefs.get(heldId) else nil
	local paired = pairDef ~= nil and pairDef.offHand == true and heldKind ~= "Bow" and heldKind ~= "Spear"
	if paired then
		left = mirrorX(right)
	end

	-- Combat v3: the guard (the weapon raised across the body; the fists up) and the heavy's hold (wound back past
	-- the cut's own wind-up, trembling a little at full charge), blended in over the guard's raise time
	approach("fguard", if fight.guard and anim == nil then 1 else 0, if fight.guard then FIGHT.guardIn else FIGHT.guardOut, dt)
	local chargeA = 0
	if fight.charge then
		chargeA = math.clamp((now - fight.charge.t0) / 0.5, 0, 1)
	end
	approach("fcharge", if fight.charge and anim == nil then 1 else 0, if fight.charge then 14 else 20, dt)
	if alpha.fguard > 0.001 and heldKind ~= "Bow" and heldKind ~= "Fists" then
		local g = Poses.smooth(alpha.fguard)
		local guardRight, guardLeft = Poses.guard(heldKind, right, left)
		right, left = right:Lerp(guardRight, g), left:Lerp(guardLeft, g)
	end
	if alpha.fcharge > 0.001 and heldKind ~= "Bow" then
		local c = Poses.smooth(alpha.fcharge)
		local combat = Controllers.CombatController
		local style = if combat and type(combat.meleeStyle) == "function" then (combat.meleeStyle(heldId)) else "Slash"
		local woundRight, woundLeft = Poses.charged(style, right, left, chargeA, now)
		right = right:Lerp(woundRight, c)
		left = left:Lerp(woundLeft, c)
	end

	-- One-shot actions
	if anim then
		if anim.kind == "Swing" and anim.style == "Kick" then
			-- a kick: the leg is out of view; the hands pull in to the chest and the view dips with the step
			right, left = Poses.kickHands(anim.t, anim.windup, anim.total, right, left)
		elseif anim.kind == "Swing" then
			-- a chain flows: from the last cut's hand (chainFrom), and on toward the next step's wind-up while one is
			-- queued (ClientState.nextSwing, CombatController)
			local nextSwing = ClientState.nextSwing
			local to, toSide = nil, nil
			if type(nextSwing) == "table" and anim.t > anim.windup + anim.strike then
				to, toSide = Poses.swingWound(nextSwing.style, nextSwing.variant)
			end
			local chain = if anim.chainFrom or to then { from = anim.chainFrom, fromSide = anim.side, to = to, toSide = toSide } else nil
			-- the Blender clip for this move when the clip player has it (ClipPlayer.sampleFP(clip, t, right, left) ->
			-- (right, left) in camera space, or nil), else the procedural swing
			right, left = Poses.swing(anim.style, anim.variant, anim.t, anim.windup, anim.strike, anim.total, right, left, anim.jitter, chain)
		elseif anim.kind == "Throw" then
			-- (the javelin set only for the spear's own hold: CombatController marks every melee throw `spear`, so an
			-- axe or sword under its clip was wound back like a javelin)
			right = Poses.throw(anim.spear and heldKind == "Spear", anim.t, anim.windup, anim.total, right)
		end
	end
	-- the Blender clips (ClipPlayer: the first-person wrists of the move, fitted to the strike), blended over the
	-- procedural pose by their weight; a move without a clip keeps the procedural one
	local cp = Controllers.ClipPlayer
	if cp and type(cp.sampleView) == "function" and now < fight.viewUntil then
		if stopped then
			pcall(cp.hitStopView, math.max(hitStop, (tonumber(ClientState.hitStopUntil) or 0) - now))
		end
		local ok, r, l, pr, pl, w = pcall(cp.sampleView, fight.viewTrack, now, right, left)
		if ok and typeof(r) == "CFrame" and (w or 0) > 0.001 then
			right, left = r, l
			fight.viewPoleRight, fight.viewPoleLeft, fight.viewW = pr, pl, w
		else
			fight.viewW = 0
		end
	else
		fight.viewW = 0
	end

	-- The spear is held in both hands until it's raised to throw (the avatar arms let go with the left for a stab:
	-- Poses.spearLetGo)
	local onShaft = 0 -- (how far the left hand is on the spear's shaft, 0..1)
	if heldKind == "Spear" and raised < 1 and not rig.itemHidden then
		local shaft = Poses.spearLeft(right * Rig.GRIP.Right, Poses.SPEAR_REACH or SPEAR_REACH, Rig.GRIP_POINT.Left, Poses.SPEAR_LEFT)
		local free = Poses.spearRaiseLetGo(raised)
		if anim and anim.kind == "Swing" and anim.style == "Stab" then
			free = math.max(free, Poses.spearLetGo(anim.t, anim.windup, anim.strike, anim.total))
		end
		left = shaft:Lerp(left, free)
		onShaft = 1 - free
	end

	-- Eating, drinking, bandaging, putting on armor (Poses.applyUse: the use poses, their blend from the hold, the wrists)
	local useT = now - useStartedAt
	local useTime = (heldDef and tonumber(heldDef.useTime)) or 1.5
	-- (still hidden while the hands come back after the use: the worn vest must not pop back into the fist)
	local hideForUse = (using or alpha.use > 0.05) and Poses.useHidesItem(useStyle(), useT, useTime)
	if hideForUse ~= useHidItem then
		useHidItem = hideForUse
		rig:setItemHidden(hideForUse or itemHiddenUntil > 0)
	end
	local leftPole = Rig.POLE.Left
	local rightPole: Vector3? = nil -- (a use's or an action's own right elbow pole, blended in)
	local style = useStyle()
	local wrap = 0
	if alpha.use > 0.001 then
		local u = Poses.smooth(alpha.use)
		right, left = Poses.applyUse(style, useT, u, right, left, rig, useTime)
		local usePole = Poses.usePole(style, "Left")
		if usePole then
			leftPole = leftPole:Lerp(usePole, u) -- (bandaging: the left elbow out to the left)
		end
		local useRight = Poses.usePole(style, "Right")
		if useRight then
			rightPole = Rig.POLE.Right:Lerp(useRight, u)
		end
		if style == "Wrap" then
			wrap = Poses.wrapBand(useT, useTime) * u -- (the bandage building up on the forearm)
		end
	end
	rig:setWrap(if using or alpha.use > 0.05 then wrap else 0)
	if Poses.SWING_POLE and heldKind ~= "Bow" and anim and (anim.kind == "Swing" or anim.kind == "Throw") then
		local w = Poses.actionPoleWeight(anim.t, anim.total)
		-- (the set's own elbow pole, Poses.swingPole; a left punch moves the left elbow)
		local swinging = anim.kind == "Swing"
		local pole = if swinging then Poses.swingPole(anim.style, anim.variant or 1) else Poses.SWING_POLE
		if swinging and Poses.swingSide(anim.style, anim.variant or 1) == "Left" then
			leftPole = leftPole:Lerp(pole or leftPole, w)
		else
			rightPole = (rightPole or Rig.POLE.Right):Lerp(pole or Rig.POLE.Right, w)
		end
	end

	-- Bow: the string, the nocked arrow and the drawing hand
	local arrowCam: CFrame? = nil
	local bowPole = Rig.POLE.BowRight -- the right elbow's pole while a bow is held (follows the draw, below)
	local bowHooked = false -- (the right hand is on the string)
	local item = rig.item
	if heldKind == "Bow" and item and item.bow then
		local tucked = Poses.smooth(alpha.tuck)
		if draw > 0 then
			-- the string follows the draw after the bow is up; against a wall it is let down
			springs.string:reset(Poses.bowPull(draw) * BOW_DRAW * (1 - tucked))
			if draw >= 1 then
				fullDrawSince = fullDrawSince or now
			end
		else
			springs.string.target = 0
			fullDrawSince = nil
		end
		rig:setDraw(math.max(springs.string:update(dt), -0.15))
		bowPole = Rig.POLE.BowRight:Lerp(Rig.POLE.BowRightDrawn, math.clamp(rig.draw / BOW_DRAW, 0, 1))
		if anim and anim.kind == "BowRelease" then
			-- follow-through: the bow hand drops away down and to the left and the bow tips forward in it
			local shift, tip = Poses.bowFollow(math.clamp(anim.t / anim.total, 0, 1))
			left = (left + shift) * CFrame.Angles(tip, 0, 0)
		end
		local handle = rig:handleFrame(left)
		local hasArrow = countItem("arrow") > 0
		bowHooked = hasArrow and alpha.tuck < 0.5
		-- (against a wall there is no room for a nocked arrow: it is kept out of view)
		local showArrow = hasArrow and now >= arrowHiddenUntil and alpha.tuck < 0.35
		rig:setArrowHidden(not showArrow)
		if handle then
			if showArrow then
				arrowCam = rig:arrowFrame(handle)
			end
			local nock = handle * item.attachments.Nock.Position
			-- fingers hooked on the string at the nock, the wrist in line with the forearm (from the lower right) and
			-- the thumb relaxed toward the bottom limb (at the anchor it tucks under the jaw, out of view)
			local hooked = Rig.straightWrist(
				Poses.bowString(nock, handle.UpVector, handle.LookVector, Rig.HOOK),
				Rig.HOOK,
				-handle.LookVector,
				false,
				Rig.SHOULDER.Right,
				bowPole
			)
			if anim and anim.kind == "BowRelease" then
				local u = math.clamp(anim.t / anim.total, 0, 1)
				local from: CFrame = anim.from or hooked
				local follow = from + Vector3.new(0.1, 0.06, 0.16)
				local settle = if hasArrow then hooked else right
				right = if u < 0.35 then from:Lerp(follow, Poses.easeOut(u / 0.35)) else follow:Lerp(settle, Poses.easeInOut((u - 0.35) / 0.65))
			elseif hasArrow then
				right = hooked
			end
			if tucked > 0 then
				right = right:Lerp(Poses.HOLD.BowTucked.right, tucked)
				bowPole = bowPole:Lerp(Rig.POLE.Right, tucked) -- (the tucked hand is a plain low fist)
			end
		end
	else
		fullDrawSince = nil
	end
	lastRightCam = right
	lastLeftCam = left

	-- Whole-viewmodel state transforms (rigid, so two-handed holds stay together)
	local e = math.clamp((now - equipStart) / math.max(equipDuration, 0.01), 0, 1)
	local d = (1 - e) ^ 3
	-- the arms rise from the lower right, tilted away from the crosshair, so a long blade never sweeps across it
	local state = CFrame.new(Vector3.new(0.12, -0.95, 0.3) * d) * about(PIVOT, CFrame.Angles(-0.9 * d, -0.15 * d, -0.3 * d))
	if alpha.lower > 0 then
		local a = alpha.lower
		state *= CFrame.new(0, -1.5 * a, 0.35 * a) * about(PIVOT, CFrame.Angles(-0.7 * a, 0, 0))
	end
	if alpha.zoom > 0 then
		-- zoomed: down and tipped forward, out of the bottom of the view (a 3-stud blade and the bow leave it too)
		local a = alpha.zoom
		state *= CFrame.new(0, -1.5 * a, 0.35 * a) * about(PIVOT, CFrame.Angles(-1.1 * a, 0, 0))
	end
	if alpha.sprint > 0 then
		local a = alpha.sprint
		if heldKind == "Bow" then
			state *= CFrame.new(-0.04 * a, -0.3 * a, 0.25 * a) * about(PIVOT, CFrame.Angles(-0.3 * a, -0.2 * a, -0.4 * a))
		else
			state *= CFrame.new(0.1 * a, -0.26 * a, 0.18 * a) * about(PIVOT, CFrame.Angles(-0.42 * a, 0.38 * a, 0.22 * a))
		end
	end
	if alpha.slide > 0 then
		local a = alpha.slide
		state *= CFrame.new(0.06 * a, -0.08 * a, 0.05 * a) * about(PIVOT, CFrame.Angles(0, 0, 0.22 * a))
	end
	if alpha.tuck > 0 and heldKind ~= "Bow" then -- (the bow has its own pulled-in pose, Poses.bowTuck)
		local a = alpha.tuck
		state *= CFrame.new(0, -0.08 * a, 0.55 * a) * about(PIVOT, CFrame.Angles(0.45 * a, 0.1 * a, 0))
	end
	local crouch = math.clamp(ClientState.crouchAlpha or 0, 0, 1)
	if crouch > 0 then
		state *= CFrame.new(0, -0.035 * crouch, 0.03 * crouch)
	end
	-- Combat v3: the body leads the blade. Over a swing the whole arm turns about the shoulder the way the cut goes
	-- (Poses.swingKick's direction): a small coil the other way in the windup, the turn through the cut, a settle back
	if anim and anim.kind == "Swing" and anim.style ~= "Kick" and type(Poses.swingKick) == "function" then
		local dir = Poses.swingKick(anim.style, anim.variant or 1)
		if dir and dir.Magnitude > 1e-3 then
			local u = dir.Unit
			local w, sEnd = anim.windup, anim.windup + anim.strike
			local e
			if anim.t < w then
				e = -0.35 * Poses.smooth(anim.t / math.max(w, 1e-3))
			elseif anim.t < sEnd then
				e = -0.35 + 1.35 * Poses.smooth((anim.t - w) / math.max(anim.strike, 1e-3))
			else
				e = 1 - Poses.smooth((anim.t - sEnd) / math.max(anim.total - sEnd, 1e-3))
			end
			local k = FIGHT.lead * e * (if anim.heavy or anim.weight == "Heavy" then 1.4 elseif anim.weight == "Light" then 0.75 else 1)
			state *= about(PIVOT, CFrame.Angles(-u.X * k * 0.6, u.Y * k, u.Z * k * 0.5))
		end
	end
	local dodge = fight.dodge
	if dodge then
		local u = (now - dodge.t0) / dodge.total
		if u >= 1 then
			fight.dodge = nil
		else
			local e = math.sin(math.clamp(u, 0, 1) * math.pi)
			if dodge.kind == "Left" or dodge.kind == "Right" then
				local side = if dodge.kind == "Left" then -1 else 1
				state *= CFrame.new(-0.18 * side * e, -0.12 * e, 0) * about(PIVOT, CFrame.Angles(0, 0, 0.22 * side * e))
			elseif dodge.kind == "Roll" then
				state *= CFrame.new(0, -0.9 * e, 0.2 * e) * about(PIVOT, CFrame.Angles(-0.9 * e, 0, 0))
			else
				state *= CFrame.new(0, -0.08 * e, 0.22 * e) * about(PIVOT, CFrame.Angles(0.18 * e, 0, 0))
			end
		end
	end
	local skill = fight.skill
	if skill then
		local u = (now - skill.t0) / math.max(skill.total, 0.05)
		if u >= 1 then
			fight.skill = nil
		else
			state *= Poses.skillState(skill.id, u, PIVOT)
		end
	end

	-- Motion: look sway, bob, lean, landing, breathing, recoil
	local look: Vector2 = if typeof(ClientState.lookDelta) == "Vector2" then ClientState.lookDelta else Vector2.zero
	local swayGain = 3.4 * (1 - 0.7 * aim) * zoomCalm
	springs.sway.velocity += Vector3.new(-look.Y, -look.X, 0) * swayGain
	local sway: Vector3 = springs.sway:update(dt)
	-- a raised bow sways less, so a fast turn can't swing it into the crosshair
	local swayLimit = if heldKind == "Bow" then 0.14 - 0.09 * alpha.raise else 0.14
	local swayPitch = math.clamp(sway.X, -swayLimit, swayLimit)
	local swayYaw = math.clamp(sway.Y, -swayLimit, swayLimit)

	local localVelocity = camCF:VectorToObjectSpace(velocity)
	springs.lean.target = Vector3.new(math.clamp(localVelocity.X / 20, -1, 1), 0, math.clamp(-localVelocity.Z / 20, -1, 1))
	local lean: Vector3 = springs.lean:update(dt)
	local land: number = springs.land:update(dt)
	local recoil: Vector3 = springs.recoil:update(dt)
	local kick: number = springs.kick:update(dt)

	local phase = (ClientState.strideAlpha or 0) * math.pi * 2
	local amp = alpha.bob
	local run = alpha.sprint
	local bobOffset = Vector3.new(
		math.sin(phase) * 0.03 * amp * (1 + 0.6 * run),
		-(math.cos(phase * 2) + 1) * 0.5 * 0.034 * amp * (1 + 0.7 * run),
		math.sin(phase * 2) * 0.02 * amp * run
	)
	local calm = (1 - 0.7 * aim) * (1 - run) * zoomCalm
	local breath = Vector3.new(math.sin(now * 0.9) * 0.004, math.sin(now * 1.8) * 0.009, 0) * calm
	local airY = math.clamp(-velocity.Y * 0.004, -0.07, 0.07) * alpha.air
	local tremble = 0
	if fullDrawSince then
		tremble = math.clamp((now - fullDrawSince - 2.5) / 2, 0, 1) * 0.012
	end
	local shakeX = if tremble > 0 then math.noise(now * 7, 0.3) * tremble else 0
	local shakeY = if tremble > 0 then math.noise(0.7, now * 7) * tremble else 0

	local offset = bobOffset + breath + Vector3.new(-lean.X * 0.035, land * 0.08 + airY, lean.Z * 0.045 + kick * 0.06)
	local motion = CFrame.new(offset)
		* CFrame.Angles(swayPitch + shakeX, swayYaw + shakeY, swayYaw * 0.8 + math.sin(phase) * 0.014 * amp)
		* about(PIVOT, CFrame.Angles(recoil.X + land * 0.05 + math.sin(now * 1.8 - 0.6) * 0.004 * calm, recoil.Y, recoil.Z - lean.X * 0.05))
	local M = motion * state
	-- (with a bow the right elbow goes out to the right, so the drawing forearm comes in from the lower right)
	if (fight.viewW or 0) > 0.001 and heldKind ~= "Bow" then
		if typeof(fight.viewPoleRight) == "Vector3" then
			rightPole = (rightPole or Rig.POLE.Right):Lerp(fight.viewPoleRight, fight.viewW)
		end
		if typeof(fight.viewPoleLeft) == "Vector3" then
			leftPole = leftPole:Lerp(fight.viewPoleLeft, fight.viewW)
		end
	end
	local poleRight = if heldKind == "Bow" then bowPole else rightPole or Rig.POLE.Right
	-- (Avatar arms) hands that must stay exactly where they are put: the bow and the hand on its string, a bottle at the
	-- lips, the bandaging hands (Rig:pose frame.lock; "hand": the elbow may still turn toward the hand)
	local lock: { [string]: any }? = nil
	if heldKind == "Bow" then
		lock = { Left = "hand", Right = if alpha.tuck < 0.5 then true else nil }
	elseif heldKind == "Spear" and Rig.STYLE ~= "Classic" then
		lock = { Right = "hand" } -- (the spear's line comes from the right hand: it is never turned by the wrist limit)
	elseif alpha.use > 0.05 and (style == "Drink" or style == "Wrap") then
		lock = { Right = "hand", Left = if style == "Wrap" then true else nil }
	end
	-- the light on the avatar and faceted arms (exposure, sky key, shade layer)
	local key: CFrame? = nil
	if shade and (rig.avatar or rig.faceted) then
		key = shade:update(dt, camCF, alpha.tuck)
	else
		rig:setExposure(1)
	end
	-- (Faceted) one hand mesh per side: a fist only while punching (and through the guard), closed round a handle or
	-- the bow string, open under food and bottles, relaxed otherwise (a thrown weapon has left the hand)
	if rig.faceted then
		local rightShape, leftShape = "Relaxed", "Relaxed"
		if heldKind == "Fists" then
			local fist = (anim ~= nil and anim.kind == "Swing" and anim.style == "Punch") or alpha.guard > 0.5
			rightShape = if fist then "Fist" else "Relaxed"
			leftShape = rightShape
		elseif heldKind == "Bow" then
			rightShape = if bowHooked then "Grip" else "Relaxed"
			leftShape = "Grip"
		else
			rightShape = if rig.itemHidden and heldKind ~= "Armor" then "Relaxed" else rig:itemHand() or "Grip"
			if heldKind == "Spear" then
				local free = Poses.spearRaiseLetGo(if anim and anim.kind == "Throw" then 1 else aim)
				if anim and anim.kind == "Swing" and anim.style == "Stab" then
					free = math.max(free, Poses.spearLetGo(anim.t, anim.windup, anim.strike, anim.total))
				end
				leftShape = if free < 0.5 and not rig.itemHidden then "Grip" else "Relaxed"
			elseif heldKind == "Armor" and alpha.use > 0.05 and useT / math.max(useTime, 0.1) >= Poses.ARMOR.downAt then
				leftShape = "Grip" -- (both hands take the hem)
			elseif paired and not rig.itemHidden then
				leftShape = rightShape -- (the second blade)
			end
		end
		rig:setHands(rightShape, leftShape)
	end

	-- The field-of-view setting (fovFit): each arm moved as one piece so that its hand keeps its place on screen; the
	-- right arm goes with the left hand where the left hand leads (the bow, the spear's shaft, the bandage wrap)
	local fitRight, fitLeft = Vector3.zero, Vector3.zero
	local fit = fovFit()
	local lead = if heldKind == "Bow" then (if bowHooked then 1 else 0)
		elseif heldKind == "Spear" then onShaft
		elseif style == "Wrap" then Poses.smooth(alpha.use)
		else 0
	approach("lead", lead, FIT_LEAD_RATE, dt)
	if math.abs(fit - 1) > 0.004 then
		local own = fitOffset(left.Position, fit)
		fitLeft = own:Lerp(fitOffset(left.Position, fit, ViewmodelController.Fit.LeadEdge), alpha.lead)
		fitRight = fitOffset(right.Position, fit):Lerp(fitLeft, alpha.lead)
	end
	-- A narrow screen (narrowFit): the empty hands rest lower, clear of the vitals; the guard is where it always is
	if heldKind == "Fists" and rig.faceted then
		local narrow = narrowFit(cam)
		if narrow > 0 then
			local drop = Vector3.new(0, -ViewmodelController.Fit.NarrowDrop * narrow * (1 - alpha.guard), 0)
			fitRight += drop
			fitLeft += drop
		end
	end

	local frame = {
		right = camCF * (M * (right + fitRight)),
		left = camCF * (M * (left + fitLeft)),
		shoulderRight = camCF * (M * (Rig.SHOULDER.Right + fitRight)),
		shoulderLeft = camCF * (M * (Rig.SHOULDER.Left + fitLeft)),
		poleRight = camCF:VectorToWorldSpace(M:VectorToWorldSpace(poleRight)),
		poleLeft = camCF:VectorToWorldSpace(M:VectorToWorldSpace(leftPole)),
		up = camCF.UpVector,
		eye = camCF.Position,
		arrow = if arrowCam then camCF * (M * (arrowCam + fitLeft)) else nil,
		lock = lock,
		key = key,
	}
	rig:pose(frame)
	rig:updateView(camCF, cam.FieldOfView, cam.ViewportSize.Y)
	muzzle = rig:muzzle()
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function ViewmodelController.isVisible(): boolean
	return visible
end

function ViewmodelController.getMuzzle(): Vector3?
	return if visible then muzzle else nil
end

function ViewmodelController.Init(registry)
	Controllers = registry
end

-- Builds the arms (a Rig of that style) with their poses and their light. The avatar and faceted arms keep Shade. The
-- block arms are lit by the engine alone: no lamp, no Highlight, no layer. With Config.Viewmodel.Blocky.Shade (a table
-- of Shade's darkening values; armOptions.Shade replaces it, false switches it off) Shade's look at the light round the
-- eye runs for them too, but all it does is bring their own colours down (Rig:setExposure -> Blocky.setExposure):
-- KeyBrightness is forced to 0 and Shade returns before its key light for block arms.
local function makeRig(style: string, armOptions: { [string]: any }?)
	local skin, skinLeft = skinColor()
	rig = Rig.new(skin, style, armOptions)
	if skin then
		rig:setSkin(skin, skinLeft)
	end
	if rig.blocky and Rig.Blocky then
		Poses.useStyle("Classic") -- (arms built again: the old Blocky values come out before the new ones go in)
		Poses.STYLES.Blocky = Rig.Blocky.poses(Poses, rig.blocky) -- (Poses.FACETED with the block arms' changes)
	end
	Poses.useStyle(Rig.STYLE)
	local blockyShade: any = nil
	if rig.blocky then
		blockyShade = armOptions and armOptions.Shade
		if blockyShade == nil then
			blockyShade = (VIEWMODEL.Blocky or {}).Shade
		end
	end
	if rig.style == "Avatar" or rig.style == "Faceted" then
		Shade.Options = VIEWMODEL.Shade or {}
		shade = Shade.new(rig)
	elseif type(blockyShade) == "table" then
		local options = table.clone(blockyShade)
		options.KeyBrightness = 0
		Shade.Options = options
		shade = Shade.new(rig)
	else
		shade = nil
	end
end

-- The screen's shape (width / height) to fit the resting hands to, in place of the window's own; nil gives the window
-- back. For a look test of a narrow screen inside a wide window.
function ViewmodelController.setViewShape(shape: number?)
	viewShape = if shape and shape > 0.2 then shape else nil
end

function ViewmodelController.setArms(style: string?, options: { [string]: any }?): string
	if not rig then
		return "not started"
	end
	local newStyle = if style and ARM_STYLES[style] then style else rig.style
	if visible then
		setVisible(false) -- (shown again, with the new arms, on the next frame)
	end
	rig:destroy()
	makeRig(newStyle, options)
	avatarSignature = nil
	avatarCheckAt = 0
	pendingArms = nil
	initialized = false -- (the held item is built again for the new arms)
	heldKey = ""
	return rig.style
end

function ViewmodelController.Start()
	makeRig(ARM_STYLE, nil)
	player:SetAttribute("ViewmodelVisible", false)
	RunService.Heartbeat:Connect(onHeartbeat)

	local combat = Controllers.CombatController
	if combat and type(combat.action) == "table" and type(combat.action.Connect) == "function" then
		combat.action:Connect(onCombatAction)
	else
		warn("[ViewmodelController] CombatController.action not found; melee and bow animations are disabled")
	end
	ClientState.landed:Connect(function(impactSpeed)
		local hard = math.clamp((tonumber(impactSpeed) or 20) / 45, 0.2, 2.2)
		springs.land:impulse(-hard * 2.2)
	end)
	ClientState.jumped:Connect(function()
		springs.land:impulse(-0.9)
	end)
	ClientState.equippedChanged:Connect(function()
		if rig then
			syncItem(os.clock())
		end
	end)
	player.CharacterAdded:Connect(function()
		skinCheckAt = 0
		avatarSignature = nil
		avatarCheckAt = 0
	end)
	RunService:BindToRenderStep("ViewmodelController", Enum.RenderPriority.Camera.Value + 2, update)
end

return ViewmodelController
