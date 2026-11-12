--[[
	FallenSnapshots (ArenaService helper, server) - avatar snapshots for the Roll Call show ("The Fallen").
	When a contender falls, a fresh R15 model of their avatar is built from the HumanoidDescription they wore (neutral
	standing pose; falls back to a clone of the live character), anchored, with scripts, sounds and effects stripped and
	accessories kept, and parked in ReplicatedStorage.FallenSnapshots. Every client turns it into a coloured point cloud
	(FallenRecapController) long before dusk.
	API:
	  FallenSnapshots.capture(player, character?) -> string   snapshot name (the model appears asynchronously)
	  FallenSnapshots.clear()                                  remove every snapshot (a new round)
	  FallenSnapshots.folder() -> Folder
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FallenSnapshots = {}

local FOLDER_NAME = "FallenSnapshots"
local MAX_SNAPSHOTS = 40
local counter = 0

function FallenSnapshots.folder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

local STRIP = {
	Script = true, LocalScript = true, ModuleScript = true, Sound = true, Animator = true, ForceField = true,
	BillboardGui = true, ProximityPrompt = true, ParticleEmitter = true, Fire = true, Smoke = true, Sparkles = true,
	Trail = true, Beam = true, Highlight = true, Tool = true,
}

-- A model built outside the workspace hasn't placed its accessories yet (their AccessoryWeld is only solved in the
-- workspace): put each handle where its weld says, before everything is anchored.
local function placeAccessories(model: Model)
	for _ = 1, 2 do
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("JointInstance") then
				local p0, p1 = d.Part0, d.Part1
				if p0 and p1 then
					if p0.Parent and p0.Parent:IsA("Accessory") then
						p0.CFrame = p1.CFrame * d.C1 * d.C0:Inverse()
					elseif p1.Parent and p1.Parent:IsA("Accessory") then
						p1.CFrame = p0.CFrame * d.C0 * d.C1:Inverse()
					end
				end
			end
		end
	end
end

local function prepare(model: Model)
	placeAccessories(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Parent and (STRIP[d.ClassName] or d:IsA("BaseScript") or d:IsA("Light") or d:IsA("Constraint")) then
			d:Destroy()
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CastShadow = false
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	model:PivotTo(CFrame.new(0, 0, 0))
end

local function trim(folder: Folder)
	local list = folder:GetChildren()
	if #list <= MAX_SNAPSHOTS then
		return
	end
	table.sort(list, function(a, b)
		return (a:GetAttribute("Seq") or 0) < (b:GetAttribute("Seq") or 0)
	end)
	for i = 1, #list - MAX_SNAPSHOTS do
		list[i]:Destroy()
	end
end

local function cloneLive(character: Model?): Model?
	if not character then
		return nil
	end
	local was = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(character.Clone, character)
	character.Archivable = was
	if ok and copy then
		return copy
	end
	return nil
end

local function finish(model: Model, name: string, player: Player?, seq: number)
	prepare(model)
	model.Name = name
	model:SetAttribute("Seq", seq)
	if player then
		model:SetAttribute("UserId", player.UserId)
		model:SetAttribute("DisplayName", player.DisplayName)
	end
	local folder = FallenSnapshots.folder()
	model.Parent = folder
	trim(folder)
end

-- Build a snapshot of `player`'s avatar. Returns its (future) name right away; the model appears a moment later.
function FallenSnapshots.capture(player: Player, character: Model?): string
	counter += 1
	local seq = counter
	local name = string.format("Fallen_%d_%d", player.UserId, seq)
	character = character or player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local description: HumanoidDescription? = nil
	if humanoid then
		local ok, desc = pcall(humanoid.GetAppliedDescription, humanoid)
		if ok and desc then
			description = desc
		end
	end
	-- the live character may be gone in a moment (death, leaving): copy it now as the fallback
	local fallback = if description then nil else cloneLive(character)
	local userId = player.UserId
	task.spawn(function()
		local model: Model? = nil
		if not description and not fallback then
			local ok, desc = pcall(function()
				return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
			end)
			if ok and desc then
				description = desc
			end
		end
		if description then
			local ok, built = pcall(function()
				return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
			end)
			if ok and built then
				model = built
			end
		end
		if model then
			if fallback then
				fallback:Destroy()
			end
		else
			model = fallback or cloneLive(character)
		end
		if not model then
			warn("[FallenSnapshots] couldn't snapshot " .. player.Name)
			return
		end
		finish(model, name, player, seq)
	end)
	return name
end

function FallenSnapshots.clear()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

return FallenSnapshots
