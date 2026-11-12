--[[
	ViewmodelController.Rig - builds and places the first-person arms and the held item. Holds no game state, so it
	can be previewed in Edit mode. Every part is Anchored, CanCollide / CanQuery / CanTouch = false, CastShadow = false,
	and all of them are moved together with one workspace:BulkMoveTo per frame.

	The arms are the original part-built viewmodel: per side an upper-arm and a forearm sleeve (Cylinders, dark
	Fabric), a Ball elbow, a Cuff, and a fist of SmoothPlastic blocks in the skin colour of the character's hands, posed
	with two-bone IK. (The Blender mesh arms in ReplicatedStorage.Assets.Viewmodel are not used.) The held items are the
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

	Rig.new(skinColor?) -> rig            rig.model: parent it to the camera to show it
	rig:setSkin(color)
	rig:setItem(itemId?, hand: "Right" | "Left")    ItemModels.build(itemId, "view"), held by that hand
	rig:setArrow(enabled)                           a nocked arrow model for the bow
	rig:setItemHidden(hidden) / rig:setArrowHidden(hidden)
	rig:handleFrame(handFrame) -> CFrame?           the item's Handle frame for a hand frame (any space)
	rig:point(name, handleFrame) -> Vector3?        an item attachment (Tip, Nock, ...) for that Handle frame
	rig:setDraw(studs)                              pulls the bow string back (moves the Nock attachment)
	rig:arrowFrame(handleFrame) -> CFrame?          the nocked arrow's Grip frame (nock on the string, on the shelf)
	rig:pose(frame)   frame = { right, left = hand frames (world), shoulderRight, shoulderLeft, poleRight, poleLeft,
	                            up = Vector3, arrow = CFrame? (arrow Grip frame, world) }
	rig:updateView(cameraCFrame, fieldOfView, viewportHeight)   after pose: sizes the bow string for the camera
	Rig.solveArm(shoulder, target, pole) -> (elbow, wrist)       the two-bone IK the arms use
	Rig.straightWrist(hand, pivot, up, strictUp, shoulder, pole) -> CFrame   see above
	rig:muzzle() -> Vector3?   where a shot leaves the weapon (nocked arrow tip, spear tip, or the held item)
	rig:destroy()
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemModels = require(Shared:WaitForChild("ItemModels"))

local Rig = {}
Rig.__index = Rig
Rig.ItemModels = ItemModels -- swappable for Edit-mode previews

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

-- Two-bone IK: elbow position for a shoulder, a wrist target and a pole direction (where the elbow points).
local function solveArm(shoulder: Vector3, target: Vector3, pole: Vector3): (Vector3, Vector3)
	local l1, l2 = Rig.UPPER_ARM, Rig.FOREARM
	local offset = target - shoulder
	local distance = offset.Magnitude
	local dir = if distance > 1e-4 then offset / distance else Vector3.new(0, 0, -1)
	distance = math.clamp(distance, math.abs(l1 - l2) + 0.05, l1 + l2 - 0.002)
	local wrist = shoulder + dir * distance
	local cosA = math.clamp((l1 * l1 + distance * distance - l2 * l2) / (2 * l1 * distance), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local bend = pole - dir * pole:Dot(dir)
	if bend.Magnitude < 1e-4 then
		bend = dir:Cross(if math.abs(dir.X) < 0.9 then Vector3.xAxis else Vector3.zAxis)
	end
	bend = bend.Unit
	return shoulder + dir * (l1 * cosA) + bend * (l1 * sinA), wrist
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
		local elbow = solveArm(shoulder, result.Position, pole)
		local along = result.Position - elbow
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

function Rig.new(skin: Color3?)
	local self = setmetatable({}, Rig)
	self.model = Instance.new("Model")
	self.model.Name = "Viewmodel"
	self.skin = skin or DEFAULT_SKIN
	self.arms = {}
	self.item = nil
	self.arrow = nil
	self.itemHidden = false
	self.arrowHidden = false
	self.draw = 0
	for _, side in ipairs({ "Right", "Left" }) do
		local s = if side == "Right" then 1 else -1
		local arm = { side = side, hand = {}, solved = CFrame.identity }
		arm.upper = newPart(self.model, side .. "UpperArm", Enum.PartType.Cylinder, Vector3.new(Rig.UPPER_ARM, 0.44, 0.44), SLEEVE, Enum.Material.Fabric)
		arm.elbow = newPart(self.model, side .. "Elbow", Enum.PartType.Ball, Vector3.new(0.43, 0.43, 0.43), SLEEVE, Enum.Material.Fabric)
		arm.fore = newPart(self.model, side .. "Forearm", Enum.PartType.Cylinder, Vector3.new(Rig.FOREARM, 0.38, 0.38), SLEEVE, Enum.Material.Fabric)
		arm.cuff = newPart(self.model, side .. "Cuff", Enum.PartType.Cylinder, Vector3.new(0.14, 0.42, 0.42), CUFF, Enum.Material.Fabric)
		for _, spec in ipairs(HAND_PARTS) do
			local p = newPart(self.model, side .. spec.name, Enum.PartType.Block, spec.size, self.skin, Enum.Material.SmoothPlastic)
			local offset = CFrame.new(spec.x * s, spec.y, spec.z) * CFrame.Angles(0, math.rad((spec.yaw or 0) * s), 0)
			table.insert(arm.hand, { part = p, offset = offset, shade = spec.shade })
		end
		self.arms[side] = arm
	end
	self:setSkin(self.skin)
	self:_rebuild()
	return self
end

function Rig:setSkin(color: Color3)
	self.skin = color
	local black = Color3.new(0, 0, 0)
	for _, arm in pairs(self.arms) do
		for _, entry in ipairs(arm.hand) do
			entry.part.Color = if entry.shade then color:Lerp(black, 1 - entry.shade) else color
		end
	end
end

function Rig:_rebuild()
	local parts = {}
	for _, side in ipairs({ "Right", "Left" }) do
		local arm = self.arms[side]
		table.insert(parts, arm.upper)
		table.insert(parts, arm.elbow)
		table.insert(parts, arm.fore)
		table.insert(parts, arm.cuff)
		for _, entry in ipairs(arm.hand) do
			table.insert(parts, entry.part)
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
			local info = prepareItem(model, ITEM_SCALE[itemId])
			info.itemId = itemId
			info.hand = if hand == "Left" then "Left" else "Right"
			info.hold = ITEM_HOLD[itemId] or CFrame.identity
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
	for _, side in ipairs({ "Right", "Left" }) do
		local arm = self.arms[side]
		local right = side == "Right"
		local hand: CFrame = if right then frame.right else frame.left
		local shoulder: Vector3 = if right then frame.shoulderRight else frame.shoulderLeft
		local pole: Vector3 = if right then frame.poleRight else frame.poleLeft
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
end

return Rig
