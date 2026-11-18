--[[
	LaunchIntroController.Figures - the stand-ins of the launch intro, on this client only.
	  * Figures.copy(character) -> figure?   a copy of a contender's avatar: scripts, sounds, lights, effects, prompts,
	    tools and movers stripped, joints and accessories kept, only the root anchored (so an idle clip can play),
	    no name tag, no collisions or queries; nil when there is nothing to copy.
	  * Figures.plain(seed) -> figure        a plain blockish figure in a white launch suit with dark trim (skin and hair
	    picked by `seed`), for contenders whose avatar isn't here (not streamed in, or the copy failed).
	figure = {
	  model: Model,
	  place(feet: CFrame)          stand it with its feet at feet.Position, facing feet.LookVector
	  play(idleId: string?)        start the idle clip (copies of R15 avatars; call once the model is in the workspace)
	  look(pitch: number, yaw: number)   turn the head (radians: + pitch looks up, + yaw turns left)
	  secure()                     once in the workspace: weld anything not joined to the root to it
	  fade(alpha: number)          0 = as built, 1 = not drawn at all (the shot's camera moves into your own stand-in's
	                               eyes at the end of the rise: its head must not be in front of the lens)
	  height: number               feet to the top of the head
	  eye: number                  feet to the eyes: where the first-person camera sits on the real character (the
	                               middle of the head and 0.1 up, as LaunchIntroController's hand-off places it)
	  destroy()
	}
]]
local Figures = {}

local STRIP: { [string]: boolean } = {
	Script = true, LocalScript = true, ModuleScript = true, Sound = true, ForceField = true, BillboardGui = true,
	SurfaceGui = true, ProximityPrompt = true, ClickDetector = true, ParticleEmitter = true, Fire = true, Smoke = true,
	Sparkles = true, Trail = true, Beam = true, Highlight = true, Tool = true, SelectionBox = true, IKControl = true,
	-- movers (the movement controller's gravity force and the like); rigid joints and constraints stay
	VectorForce = true, LineForce = true, Torque = true, AlignPosition = true, AlignOrientation = true,
	LinearVelocity = true, AngularVelocity = true, PlaneConstraint = true,
}

local SKIN = {
	Color3.fromRGB(234, 192, 160), Color3.fromRGB(198, 156, 124), Color3.fromRGB(170, 122, 92),
	Color3.fromRGB(141, 96, 68), Color3.fromRGB(104, 70, 50), Color3.fromRGB(226, 178, 140),
}
local HAIR = {
	Color3.fromRGB(46, 36, 30), Color3.fromRGB(88, 62, 40), Color3.fromRGB(190, 160, 104), Color3.fromRGB(30, 28, 28),
	Color3.fromRGB(122, 70, 44),
}
local SUIT = Color3.fromRGB(216, 216, 212)
local TRIM = Color3.fromRGB(52, 62, 82)
local SHOE = Color3.fromRGB(58, 58, 60)

local function newFigure(model: Model, root: BasePart, footOffset: number, neck: Instance?, height: number, eye: number?)
	-- the eyes: as measured, else where a standing body has them (about 1.7 above the root's middle; `height` can't
	-- say, a tall hat or a pair of wings raises it)
	local eyeHeight = if eye and eye == eye then math.clamp(eye, 1, 12) else math.min(0.88 * height, footOffset + 1.7)
	local figure = { model = model, root = root, footOffset = footOffset, height = height, eye = eyeHeight }
	-- the neck: a Motor6D (turned through its C0), or an AnimationConstraint (the avatar joint upgrade: turned through
	-- its torso-side attachment)
	local neckC0 = if neck and neck:IsA("Motor6D") then neck.C0 else nil
	local neckAtt: Attachment? = if neck and neck:IsA("AnimationConstraint") then neck.Attachment0 else nil
	local neckAttCF = if neckAtt then neckAtt.CFrame else nil
	local track: AnimationTrack? = nil
	local lookP, lookY = 0, 0

	function figure.place(feet: CFrame)
		local cf = feet * CFrame.new(0, footOffset, 0)
		if model:IsDescendantOf(workspace) then
			root.CFrame = cf -- the joints carry the rest
		else
			model:PivotTo(cf) -- (outside the workspace nothing follows the root: move every part)
		end
	end

	function figure.play(idleId: string?)
		if track or not idleId or idleId == "" then
			return
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local ok, result = pcall(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = idleId
			local t = (animator :: Animator):LoadAnimation(animation)
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Idle
			t:Play(0.3, 1, 0.92 + math.random() * 0.16)
			return t
		end)
		if ok then
			track = result
		end
	end

	function figure.look(pitch: number, yaw: number)
		if not neck or not neck.Parent then
			return
		end
		if math.abs(pitch - lookP) < 1e-4 and math.abs(yaw - lookY) < 1e-4 then
			return
		end
		lookP, lookY = pitch, yaw
		local turn = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		if neckC0 then
			-- turn about the neck pivot, in the torso's axes (works for R15's plain C0 and R6's rotated one)
			local pivot = CFrame.new(neckC0.Position);
			(neck :: Motor6D).C0 = pivot * turn * (pivot:Inverse() * neckC0)
		elseif neckAtt and neckAttCF and neckAtt.Parent then
			neckAtt.CFrame = CFrame.new(neckAttCF.Position) * turn * neckAttCF.Rotation
		end
	end

	-- once in the workspace: anything not joined to the root (a loose accessory) is welded to it where it is, so
	-- nothing falls away or stays behind when the figure moves
	function figure.secure()
		if not root.Parent then
			return
		end
		local joined = {}
		for _, p in ipairs(root:GetConnectedParts(true)) do
			joined[p] = true
		end
		-- (parts held by any joint or constraint count as joined: the animated limbs must stay free)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				local j = d :: any
				if j.Part0 then joined[j.Part0] = true end
				if j.Part1 then joined[j.Part1] = true end
			elseif d:IsA("Constraint") then
				local c = d :: any
				local a0, a1 = c.Attachment0, c.Attachment1
				if a0 and a0.Parent then joined[a0.Parent] = true end
				if a1 and a1.Parent then joined[a1.Parent] = true end
			end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= root and not joined[d] then
				d.Anchored = false
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = d
				w.Parent = d
			end
		end
	end

	-- Seen or not: every part and decal of the figure through its LocalTransparencyModifier (nothing else writes it on
	-- a stand-in: it has no scripts and is nobody's camera subject). The list is made on the first call that changes
	-- anything, so a figure that is never faded costs nothing.
	local fadeParts: { any }? = nil
	local fadeAlpha = 0
	function figure.fade(alpha: number)
		local a = if alpha == alpha then math.clamp(alpha, 0, 1) else 0
		if math.abs(a - fadeAlpha) < 0.004 and not (a ~= fadeAlpha and (a == 0 or a == 1)) then
			return
		end
		if not fadeParts then
			local list = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then
					table.insert(list, d)
				end
			end
			fadeParts = list
		end
		fadeAlpha = a
		for _, d in ipairs(fadeParts :: { any }) do
			d.LocalTransparencyModifier = a
		end
	end

	function figure.destroy()
		if track then
			pcall(function()
				(track :: AnimationTrack):Stop(0)
			end)
			track = nil
		end
		model:Destroy()
	end

	return figure
end

-- The feet's height under the root, from the model's bounding box (accessories only ever raise its top).
local function measure(model: Model, root: BasePart): (number, number)
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	local top = cf.Position.Y + size.Y / 2
	return root.Position.Y - bottom, top - bottom
end

function Figures.copy(character: Model?): any
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local was = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(character.Clone, character)
	character.Archivable = was
	if not ok or not copy then
		return nil
	end
	local model = copy :: Model
	model.Name = "StandIn"
	for _, d in ipairs(model:GetDescendants()) do
		if d.Parent and (STRIP[d.ClassName] or d:IsA("BaseScript") or d:IsA("Light") or d:IsA("BodyMover")) then
			d:Destroy()
		end
	end
	local copyRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local copyHumanoid = model:FindFirstChildOfClass("Humanoid")
	if not copyRoot or not copyHumanoid then
		model:Destroy()
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d == copyRoot
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.LocalTransparencyModifier = 0
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	copyHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	copyHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	copyHumanoid.NameDisplayDistance = 0
	copyHumanoid.HealthDisplayDistance = 0
	copyHumanoid.BreakJointsOnDeath = false
	copyHumanoid.RequiresNeck = false
	pcall(function()
		copyHumanoid.EvaluateStateMachine = false
	end)
	model.PrimaryPart = copyRoot
	local neck: Instance? = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") then
			-- rigid, so the limbs ride the anchored root and the idle clip still drives them
			pcall(function()
				(d :: any).IsKinematic = true
			end)
		end
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and d.Name == "Neck" and not neck then
			neck = d
		end
	end
	local footOffset, height = measure(model, copyRoot)
	if not (footOffset > 0.5 and footOffset < 12 and height > 1.5 and height < 20) then
		-- an odd pose or rig: fall back to a standard R15 stance
		footOffset = copyHumanoid.HipHeight + copyRoot.Size.Y / 2
		height = 5.2
	end
	-- the eyes: the middle of the head and 0.1 up, measured in the pose the copy was taken in (a head that is missing
	-- or far from where a standing body has it gives nil: newFigure then puts them where a standing body has them)
	local eye: number? = nil
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local above = head.Position.Y - copyRoot.Position.Y
		if above > 0.6 and above < 4 then
			eye = footOffset + above + 0.1
		end
	end
	return newFigure(model, copyRoot, footOffset, neck, height, eye)
end

function Figures.plain(seed: number): any
	local rng = Random.new(math.floor(seed) % 100003 + 7)
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local hair = HAIR[rng:NextInteger(1, #HAIR)]
	local model = Instance.new("Model")
	model.Name = "StandIn"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1.9, 2, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = CFrame.new(0, 2.3, 0)
	root.Parent = model
	model.PrimaryPart = root
	local function block(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = root.CFrame * CFrame.new(offset)
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		p.Parent = model
		return p
	end
	-- feet at 0 (the root sits 2.3 above them): a realistic-blockish body about 5.6 tall in the white launch suit
	local fabric = Enum.Material.Fabric
	local smooth = Enum.Material.SmoothPlastic
	for _, x in ipairs({ -0.47, 0.47 }) do
		block("Leg", Vector3.new(0.88, 1.9, 0.9), Vector3.new(x, -1.1, 0), SUIT, fabric)
		block("Shoe", Vector3.new(0.9, 0.3, 1.1), Vector3.new(x, -2.15, -0.08), SHOE, smooth)
	end
	block("Hips", Vector3.new(1.9, 0.45, 0.98), Vector3.new(0, 0.025, 0), SUIT, fabric)
	block("Belt", Vector3.new(2.0, 0.18, 1.02), Vector3.new(0, 0.2, 0), TRIM, smooth)
	block("Torso", Vector3.new(1.95, 1.6, 1.0), Vector3.new(0, 1.05, 0), SUIT, fabric)
	for _, x in ipairs({ -1.36, 1.36 }) do
		block("Arm", Vector3.new(0.74, 1.75, 0.78), Vector3.new(x, 0.925, 0), SUIT, fabric)
		block("Hand", Vector3.new(0.6, 0.5, 0.64), Vector3.new(x, -0.1, 0), skin, smooth)
		block("Cuff", Vector3.new(0.78, 0.14, 0.82), Vector3.new(x, 0.12, 0), TRIM, smooth)
	end
	block("Collar", Vector3.new(1.25, 0.14, 0.88), Vector3.new(0, 1.87, 0), TRIM, smooth)
	block("Neck", Vector3.new(0.5, 0.25, 0.5), Vector3.new(0, 1.98, 0), skin, smooth)
	local head = block("Head", Vector3.new(1.05, 1.08, 1.02), Vector3.new(0, 2.62, 0), skin, smooth)
	block("Hair", Vector3.new(1.1, 0.3, 1.08), Vector3.new(0, 3.15, 0.03), hair, smooth)
	block("HairBack", Vector3.new(1.1, 0.62, 0.28), Vector3.new(0, 2.75, 0.42), hair, smooth)
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Transparency = 0.35
	face.Parent = head
	return newFigure(model, root, 2.3, nil, 5.6, 2.3 + 2.62 + 0.1)
end

return Figures
