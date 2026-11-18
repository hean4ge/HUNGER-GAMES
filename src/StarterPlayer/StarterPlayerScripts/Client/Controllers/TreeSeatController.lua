--[[
	TreeSeatController - the prompts of the climbable trees: the client half of sitting in the trees.
	TreeSeatService is the server half; Shared.TreeClimb says what a climbable tree is.

	Three ProximityPrompts in the Custom style (HUDController draws them as it draws the crate and item prompts, with
	the tap button on phones), made once and moved to where they are needed; tagged "TreePrompt":
	  SIT     on a limb, next to its perch (all devices, E / ButtonX / tap): asks the server for a seat there
	  STAND   while sitting in a tree (E / ButtonX / tap; jumping stands up too): instant
	  CLIMB   at the foot of a climbable trunk, on touch and gamepad only (on a keyboard, holding W into the trunk
	          climbs, and InventoryController shows that hint): MovementController.tryClimb
	The search runs 6 times a second over the parts within 7 studs (GetPartBoundsInRadius); nothing runs per tree.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TreeClimb = require(Shared:WaitForChild("TreeClimb"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local TreeSeatController = {}

TreeSeatController.PERIOD = 1 / 6
TreeSeatController.SEARCH = 7 -- studs round the root
TreeSeatController.SIT_REACH = 3.2 -- flat studs from the root to a perch
TreeSeatController.CLIMB_REACH = 4.5 -- flat studs from the root to a trunk's axis

local player = Players.LocalPlayer
local Controllers = nil
local remote: RemoteEvent? = nil

local holder: Attachment? = nil
local prompts: { [string]: ProximityPrompt } = {}
local target: { [string]: any } = {}
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.MaxParts = 80

local function makePrompt(name: string, action: string, object: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "Tree" .. name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Style = Enum.ProximityPromptStyle.Custom -- the game's quiet look, drawn by HUDController like every prompt
	p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	p.Enabled = false
	p:AddTag("TreePrompt")
	return p
end

local function ensureHolder(): Attachment
	if holder and holder.Parent then
		return holder
	end
	local a = Instance.new("Attachment")
	a.Name = "TreePrompts"
	a.Parent = workspace.Terrain
	holder = a
	for _, p in pairs(prompts) do
		p.Parent = a
	end
	return a
end

local function show(name: string, at: Vector3?, thing: any)
	local p = prompts[name]
	if not p then
		return
	end
	target[name] = thing
	if at then
		ensureHolder().WorldPosition = at
	end
	p.Enabled = at ~= nil
end

-- Where a prompt that belongs to the contender goes: just in front of the view (a prompt is only shown while its
-- spot is on screen) and nearer than anything else, so it is the E prompt there.
local function inView(root: BasePart): Vector3
	local cam = workspace.CurrentCamera
	if not cam then
		return root.Position
	end
	local look = cam.CFrame.LookVector
	return cam.CFrame.Position + look * 2
end

local function treeAxis(trunk: BasePart): Vector3
	local model = trunk.Parent
	if model and model:IsA("Model") then
		return model:GetPivot().Position
	end
	return trunk.Position
end

local function update()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) or humanoid.Health <= 0 or ClientState.menuOpen then
		show("Sit", nil)
		show("Stand", nil)
		show("Climb", nil)
		return
	end
	local seat = humanoid.SeatPart
	if seat and seat.Name == "TreeSeat" then
		show("Sit", nil)
		show("Climb", nil)
		show("Stand", inView(root), seat)
		return
	end
	show("Stand", nil)
	local state = ClientState.moveState
	if humanoid.Sit or state == "Climb" or state == "Mantle" or state == "Swim" or state == "Frozen" then
		show("Sit", nil)
		show("Climb", nil)
		return
	end
	overlap.FilterDescendantsInstances = { character }
	local pos = root.Position
	local feetY = pos.Y - humanoid.HipHeight - root.Size.Y / 2
	local bestPerch, bestPerchD = nil, TreeSeatController.SIT_REACH
	local bestTrunk, bestTrunkD = nil, TreeSeatController.CLIMB_REACH
	local seen = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, TreeSeatController.SEARCH, overlap)) do
		if not seen[part] and part:HasTag(TreeClimb.TAG_TRUNK) then
			seen[part] = true
			local perches = TreeClimb.perchesOf(part)
			if #perches > 0 then
				for _, perch in ipairs(perches) do
					local pp = perch.WorldPosition
					local d = Vector3.new(pp.X - pos.X, 0, pp.Z - pos.Z).Magnitude
					if d < bestPerchD and math.abs(feetY - pp.Y) < 1.2 then
						bestPerch, bestPerchD = perch, d
					end
				end
				local axis = treeAxis(part)
				local d = Vector3.new(axis.X - pos.X, 0, axis.Z - pos.Z).Magnitude
				if d < bestTrunkD and feetY - axis.Y < 4 and feetY - axis.Y > -3 then
					bestTrunk, bestTrunkD = part, d
				end
			end
		end
	end
	if bestPerch then
		-- in front of the view (a Custom prompt is drawn in the HUD, not in the world): the nearest E prompt
		show("Sit", inView(root), bestPerch)
		show("Climb", nil)
		return
	end
	show("Sit", nil)
	local touchOrPad = UserInputService.TouchEnabled or UserInputService.GamepadEnabled
	if bestTrunk and touchOrPad and state ~= "Air" then
		local axis = treeAxis(bestTrunk)
		local at = Vector3.new(axis.X, feetY + 3, axis.Z)
		-- the prompt sits on the near face of the trunk
		local toMe = Vector3.new(pos.X - axis.X, 0, pos.Z - axis.Z)
		if toMe.Magnitude > 0.1 then
			at += toMe.Unit * math.min(1.5, toMe.Magnitude)
		end
		show("Climb", at, bestTrunk)
	else
		show("Climb", nil)
	end
end

function TreeSeatController.Init(registry)
	Controllers = registry
end

function TreeSeatController.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local found = remotes and remotes:WaitForChild("TreeSeat", 30)
	if found and found:IsA("RemoteEvent") then
		remote = found
	end
	prompts.Sit = makePrompt("Sit", "Sit", "Branch")
	prompts.Stand = makePrompt("Stand", "Stand up", "")
	prompts.Climb = makePrompt("Climb", "Climb", "Tree")
	ensureHolder()

	prompts.Sit.Triggered:Connect(function()
		local perch = target.Sit
		if remote and perch and perch.Parent then
			remote:FireServer("sit", perch)
		end
	end)
	prompts.Stand.Triggered:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Sit then
			humanoid.Sit = false
		end
	end)
	prompts.Climb.Triggered:Connect(function()
		local trunk = target.Climb
		local mc = Controllers and Controllers.MovementController
		if trunk and trunk.Parent and mc and type(mc.tryClimb) == "function" then
			mc.tryClimb(trunk)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TreeSeatController.PERIOD then
			return
		end
		acc = 0
		local ok, err = pcall(update)
		if not ok then
			warn("[TreeSeatController] " .. tostring(err))
		end
	end)
end

return TreeSeatController
