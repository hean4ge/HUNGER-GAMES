--[[
	TreeSeatService - sitting in the trees: the server half. TreeSeatController is the client half; the perches are
	the "TreePerch" Attachments of the climbable trees (Shared.TreeClimb, planted by Map1.Scatter).

	A contender standing on a limb next to a perch asks to sit (the SIT prompt). If the perch is real, free and within
	reach, a plain invisible Seat named "TreeSeat" is made on it for as long as they sit, and they are sat in it with
	Seat:Sit: the seat weld, the sitting pose and the view are Roblox's own, so every other player sees them sitting.
	Standing up (jump, or the STAND prompt) is instant; the Seat is removed as soon as it is empty. A seated contender
	can be hit like anyone else, and a fall from the limb afterwards hurts as any fall does (MovementService).

	Remote: ReplicatedStorage.Remotes.TreeSeat (created here at start, not in Net.Names: the game runs unchanged
	without this service)
	  client -> server  "sit", perch: Attachment

	Cost: one Seat per seated contender, nothing per tree, nothing per frame.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local TreeClimb = require(Shared:WaitForChild("TreeClimb"))

local TreeSeatService = {}

TreeSeatService.REMOTE = "TreeSeat"
TreeSeatService.SEAT_NAME = "TreeSeat"
TreeSeatService.REACH = 7 -- studs from the contender's root to the perch
TreeSeatService.SEAT_SIZE = Vector3.new(1.6, 0.2, 1.6)

local remote: RemoteEvent? = nil
local folder: Folder? = nil
local seats: { [Attachment]: Seat } = {}

local function seatFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild("TreeSeats")
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = "TreeSeats"
		f.Parent = workspace
	end
	folder = f :: Folder
	return f :: Folder
end

local function release(perch: Attachment)
	local seat = seats[perch]
	seats[perch] = nil
	if seat then
		seat:Destroy()
	end
end

local function onSit(player: Player, perch: any)
	if not TreeClimb.isPerch(perch) or not perch:IsDescendantOf(workspace) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) or humanoid.Health <= 0 or humanoid.Sit or root.Anchored then
		return
	end
	if player:GetAttribute("Frozen") == true then
		return
	end
	local at = perch.WorldPosition
	if (root.Position - at).Magnitude > TreeSeatService.REACH then
		return
	end
	local taken = seats[perch]
	if taken and taken.Parent and taken.Occupant then
		return
	end
	if taken then
		release(perch)
	end
	-- facing out along the limb, the trunk at the back, level
	local look = perch.WorldCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local seat = Instance.new("Seat")
	seat.Name = TreeSeatService.SEAT_NAME
	seat.Size = TreeSeatService.SEAT_SIZE
	seat.Anchored = true
	seat.CanCollide = false
	seat.CanTouch = false -- only Seat:Sit puts anyone in it: walking along a limb never sits you down
	seat.CanQuery = false
	seat.Transparency = 1
	seat.CastShadow = false
	seat.CFrame = CFrame.lookAlong(at + Vector3.new(0, TreeSeatService.SEAT_SIZE.Y / 2, 0), flat.Unit)
	seat:SetAttribute("Perch", perch:GetFullName())
	seat.Parent = seatFolder()
	seats[perch] = seat
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Occupant then
			task.defer(function()
				if seats[perch] == seat and not seat.Occupant then
					release(perch)
				end
			end)
		end
	end)
	seat:Sit(humanoid)
	-- Seat:Sit can refuse (a humanoid in a state that cannot sit): never leave an empty seat behind
	task.delay(0.5, function()
		if seats[perch] == seat and not seat.Occupant then
			release(perch)
		end
	end)
end

function TreeSeatService.Init(_services)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	local existing = remotes:FindFirstChild(TreeSeatService.REMOTE)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		local created = Instance.new("RemoteEvent")
		created.Name = TreeSeatService.REMOTE
		created.Parent = remotes
		remote = created
	end
end

function TreeSeatService.Start()
	local event = remote
	if not event then
		return
	end
	event.OnServerEvent:Connect(function(player: Player, action: any, perch: any)
		if action ~= "sit" or not Net.rateLimit(player, "TreeSeat", 2, 3) then
			return
		end
		onSit(player, perch)
	end)
	Players.PlayerRemoving:Connect(function()
		for perch, seat in pairs(seats) do
			if not seat.Parent or not seat.Occupant then
				release(perch)
			end
		end
	end)
end

return TreeSeatService
