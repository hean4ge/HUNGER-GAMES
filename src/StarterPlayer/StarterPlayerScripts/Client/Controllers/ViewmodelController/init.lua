--[[
	ViewmodelController - first-person arms and the held item. Client only.

	Visible only in first person, in the arena, alive and not spectating. Arms are built from parts (dark fabric
	sleeves, cuffs, fists in the skin colour of the local character's hands) and the held item comes from
	ItemModels.build(id, "view"), placed at the hand by its Grip attachment (a bow sits in the left hand and the
	right hand draws the string). Child modules: Rig (parts, two-bone IK, item placement, BulkMoveTo) and Poses
	(hand poses and keyframes).

	Rendered every frame after the camera effects (BindToRenderStep at RenderPriority.Camera + 2) at
	camera.CFrame * offsets. Procedural motion with Shared.Spring: idle breathing, look sway from
	ClientState.lookDelta, walk/sprint bob synced to ClientState.strideAlpha (scaled by settings.headBob), sprint pose
	(weapon lowered and angled), slide tilt, crouch offset, landing dip (ClientState.landed), jump lift, equip raise
	(from the lower right, never across the crosshair), melee swings by weight (windup, strike with hit-stop,
	follow-through), bow hold and draw (the bow waits at a low ready with the drawing hand on the nock, its wrist in
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
	Fists when nothing is equipped.

	API
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
local Signal = require(Shared:WaitForChild("Signal"))
local Spring = require(Shared:WaitForChild("Spring"))
local Util = require(Shared:WaitForChild("Util"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Rig = require(script:WaitForChild("Rig"))
local Poses = require(script:WaitForChild("Poses"))

local player = Players.LocalPlayer

local ViewmodelController = {}
ViewmodelController.visibilityChanged = Signal.new()

local FIRST_PERSON_DISTANCE = 3.5 -- the camera is this close to the head in first person
local PIVOT = Vector3.new(0.25, -0.85, -1.2) -- pose rotations (sprint, equip, recoil) turn around this point
local SPEAR_REACH = Poses.SPEAR_REACH or 1.16 -- the supporting hand's distance up the spear shaft
-- Bow: how far the string is pulled at full draw in first person (studs). Longer than the mesh bow's own MaxDraw, so the
-- nock reaches an under-chin anchor with the bow arm extended (Poses.HOLD.BowDrawn is built for this length).
local BOW_DRAW = Config.Combat.ViewBowDraw or 1.35
local HIT_STOP: { [string]: number } = { Light = 0.045, Medium = 0.06, Heavy = 0.085 }
local LOWER_MOVES: { [string]: boolean } = { Climb = true, Mantle = true, Swim = true }
local USE_STYLE: { [string]: string } = {
	water_bottle = "Drink", empty_bottle = "Drink", bandage = "Wrap", medkit = "Bandage", herbs = "Eat",
}
local USE_BY_KIND: { [string]: string } = { Food = "Eat", Drink = "Drink", Heal = "Bandage", Armor = "Armor" }

local Controllers: { [string]: any } = {}
local camera: Camera? = workspace.CurrentCamera
local rig: any = nil
local visible = false
local initialized = false

local heldId: string? = nil
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
local alpha = { sprint = 0, slide = 0, lower = 0, tuck = 0, use = 0, air = 0, bob = 0, raise = 0, dip = 0 }

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
local lastRightCam = CFrame.identity
local muzzle: Vector3? = nil

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

local function holdKindFor(def: any): string
	if not def then
		return "Fists"
	elseif def.kind == "Melee" then
		return if def.throwable then "Spear" else "Blade"
	elseif def.kind == "Bow" then
		return "Bow"
	elseif def.kind == "Throwable" then
		return "Throwable"
	elseif def.kind == "Armor" then
		return "Armor"
	end
	return "Item"
end

local function skinColor(): Color3?
	local character = player.Character
	if not character then
		return nil
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand.Color
	end
	local colors = character:FindFirstChildOfClass("BodyColors")
	return if colors then colors.RightArmColor3 else nil
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
	if not (ClientState.inArena and ClientState.alive) or ClientState.spectating ~= nil then
		return false
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
		local color = skinColor()
		if color then
			rig:setSkin(color)
		end
		resetMotion()
		equipStart = os.clock()
		equipDuration = 0.4 -- the arms rise into view
		rig.model.Parent = camera
	else
		rig.model.Parent = nil
		anim = nil
		muzzle = nil
	end
	player:SetAttribute("ViewmodelVisible", on)
	ViewmodelController.visibilityChanged:Fire(on)
end

local function syncItem(now: number)
	local id = ClientState.getEquippedItemId()
	local inventory = ClientState.inventory
	local key = tostring(if inventory then inventory.equipped else 0) .. ":" .. tostring(id)
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
	rig:setItem(if shown then id else nil, if heldKind == "Bow" then "Left" else "Right")
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

local function onCombatAction(name: string, data: any)
	if type(data) ~= "table" then
		return
	end
	local now = os.clock()
	if name == "Swing" then
		anim = {
			kind = "Swing",
			t = 0,
			style = data.style,
			weight = data.weight,
			variant = data.variant or 1,
			windup = data.windup or 0.1,
			strike = data.strike or 0.1,
			total = data.total or 0.5,
		}
	elseif name == "Strike" then
		local side = if (data.variant or 1) % 2 == 0 then -1 else 1
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
		skinCheckAt = now + 2
		local color = skinColor()
		if color and color ~= rig.skin then
			rig:setSkin(color)
		end
	end

	-- One-shot animation clock (slowed for a moment on impact: hit-stop)
	if anim then
		local rate = if hitStop > 0 then 0.12 else 1
		anim.t += dt * rate
		if anim.t >= anim.total then
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
	approach("sprint", if moveState == "Sprint" and grounded and not busy then 1 else 0, 9, dt)
	approach("slide", if moveState == "Slide" then 1 else 0, 10, dt)
	approach("lower", if LOWER_MOVES[moveState] then 1 else 0, 8, dt)
	approach("use", if using then 1 else 0, 10, dt)
	approach("air", if grounded then 0 else 1, 6, dt)
	local moving = grounded and speed > 0.5 and not LOWER_MOVES[moveState] and moveState ~= "Slide"
	local bobTarget = if moving then math.clamp(speed / math.max(Config.Movement.WalkSpeed, 1), 0, 1.7) else 0
	approach("bob", bobTarget * headBob * (1 - 0.65 * aim), 8, dt)

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
		end
	end

	-- One-shot actions
	if anim then
		if anim.kind == "Swing" then
			right, left = Poses.swing(anim.style, anim.variant, anim.t, anim.windup, anim.strike, anim.total, right, left)
		elseif anim.kind == "Throw" then
			right = Poses.throw(anim.spear, anim.t, anim.windup, anim.total, right)
		end
	end

	-- The spear is held in both hands until it's raised to throw
	if heldKind == "Spear" and raised < 1 and not rig.itemHidden then
		local shaft = Poses.spearLeft(right * Rig.GRIP.Right, SPEAR_REACH, Rig.GRIP_POINT.Left, Poses.SPEAR_LEFT)
		left = shaft:Lerp(left, Poses.smooth(raised))
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
	if alpha.use > 0.001 then
		local u = Poses.smooth(alpha.use)
		right, left = Poses.applyUse(useStyle(), useT, u, right, left, rig, useTime)
		local usePole = Poses.usePole(useStyle())
		if usePole then
			leftPole = leftPole:Lerp(usePole, u) -- (bandaging: the left elbow out to the left)
		end
	end

	-- Bow: the string, the nocked arrow and the drawing hand
	local arrowCam: CFrame? = nil
	local bowPole = Rig.POLE.BowRight -- the right elbow's pole while a bow is held (follows the draw, below)
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

	-- Whole-viewmodel state transforms (rigid, so two-handed holds stay together)
	local e = math.clamp((now - equipStart) / math.max(equipDuration, 0.01), 0, 1)
	local d = (1 - e) ^ 3
	-- the arms rise from the lower right, tilted away from the crosshair, so a long blade never sweeps across it
	local state = CFrame.new(Vector3.new(0.12, -0.95, 0.3) * d) * about(PIVOT, CFrame.Angles(-0.9 * d, -0.15 * d, -0.3 * d))
	if alpha.lower > 0 then
		local a = alpha.lower
		state *= CFrame.new(0, -1.5 * a, 0.35 * a) * about(PIVOT, CFrame.Angles(-0.7 * a, 0, 0))
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

	-- Motion: look sway, bob, lean, landing, breathing, recoil
	local look: Vector2 = if typeof(ClientState.lookDelta) == "Vector2" then ClientState.lookDelta else Vector2.zero
	local swayGain = 3.4 * (1 - 0.7 * aim)
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
	local calm = (1 - 0.7 * aim) * (1 - run)
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
	local poleRight = if heldKind == "Bow" then bowPole else Rig.POLE.Right

	local frame = {
		right = camCF * (M * right),
		left = camCF * (M * left),
		shoulderRight = camCF * (M * Rig.SHOULDER.Right),
		shoulderLeft = camCF * (M * Rig.SHOULDER.Left),
		poleRight = camCF:VectorToWorldSpace(M:VectorToWorldSpace(poleRight)),
		poleLeft = camCF:VectorToWorldSpace(M:VectorToWorldSpace(leftPole)),
		up = camCF.UpVector,
		arrow = if arrowCam then camCF * (M * arrowCam) else nil,
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

function ViewmodelController.Start()
	rig = Rig.new(skinColor())
	player:SetAttribute("ViewmodelVisible", false)

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
	end)
	RunService:BindToRenderStep("ViewmodelController", Enum.RenderPriority.Camera.Value + 2, update)
end

return ViewmodelController
