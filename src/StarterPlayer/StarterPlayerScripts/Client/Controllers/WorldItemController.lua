--[[
	WorldItemController - the Take prompt for spent arrows, throwing knives and spears left in the world
	(ProjectileService.WorldProjectiles; rules in Shared.WorldItems). Client only.

	Loose items (tag LooseProjectile, as they stream in and out) go into an 8-stud grid. Every 0.1 s - never per frame -
	the item nearest the crosshair within reach (WorldItems.inReach: Config.Loot.ItemPromptDistance from your root and
	no higher than a raised hand, so one high up a tree or a wall needs a climb) and in line of sight gets the one local
	ProximityPrompt, set up like a ground item's Take prompt (Default style, "Take" + the item's name, E / ButtonX / a
	tap: Roblox draws this device's own button). Alive contenders in the arena only; never while spectating or in a menu.
	Triggered -> TakeWorldItem(worldId); the server checks reach again and adds it to your stack ("+1 ARROW" comes with
	the InventoryUpdate) or says INVENTORY FULL. Walking over arrows and throwing knives picks them up on the server.
	API (tests): WorldItemController.stats() -> { tracked, cells, target (worldId or 0) }
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Net = require(Shared:WaitForChild("Net"))
local WorldItems = require(Shared:WaitForChild("WorldItems"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local LootCfg = Config.Loot

local TICK = 0.1
local CELL = 8
local CONE = math.rad(30) -- how far off the crosshair an item may be and still be the one you look at...
local CONE_NEAR = math.rad(28) -- ...plus this much more for one right at your feet
local MAX_LOS = 3 -- line-of-sight rays per check
local RETRY = 0.6 -- an item you just pressed E on isn't offered again for this long

local WorldItemController = {}

type Item = { model: Model, itemId: string, worldId: number, cell: number }

local items: { [Instance]: Item } = {}
local grid: { [number]: { Item } } = {}
local tracked = 0
local target: Item? = nil
local holder: Attachment? = nil
local prompt: ProximityPrompt? = nil
local pressedAt: { [number]: number } = {}
local remote: RemoteEvent? = nil
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.RespectCanCollide = true -- leaves and grass don't hide an arrow; walls and trunks do
losParams.IgnoreWater = true

local function cellOf(position: Vector3): number
	return (math.floor(position.X / CELL) + 32768) * 65536 + (math.floor(position.Z / CELL) + 32768)
end

local function onLooseAdded(model: Instance)
	if items[model] or not model:IsA("Model") then
		return
	end
	local itemId = model:GetAttribute("ItemId")
	local worldId = model:GetAttribute("WorldId")
	if type(itemId) ~= "string" or type(worldId) ~= "number" then
		return
	end
	local key = cellOf(WorldItems.grabPoint(itemId, model:GetPivot()))
	local item: Item = { model = model, itemId = itemId, worldId = worldId, cell = key }
	items[model] = item
	tracked += 1
	local list = grid[key]
	if not list then
		list = {}
		grid[key] = list
	end
	table.insert(list, item)
end

local function onLooseRemoved(model: Instance)
	local item = items[model]
	if not item then
		return
	end
	items[model] = nil
	tracked -= 1
	local list = grid[item.cell]
	if list then
		local index = table.find(list, item)
		if index then
			list[index] = list[#list]
			list[#list] = nil
		end
		if #list == 0 then
			grid[item.cell] = nil
		end
	end
	if target == item then
		target = nil
		if prompt then
			prompt.Enabled = false
		end
	end
end

local function ensurePrompt(): ProximityPrompt
	if prompt and prompt.Parent and holder and holder.Parent then
		return prompt
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "WorldItemPrompt"
	attachment.Parent = workspace.Terrain
	local p = Instance.new("ProximityPrompt")
	p.Name = "TakePrompt"
	p.ActionText = "Take"
	p.ObjectText = "Arrow"
	p.HoldDuration = 0
	p.MaxActivationDistance = (tonumber(LootCfg.ItemPromptDistance) or 7) + 3 -- our own reach check decides
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	p.Enabled = false
	p.Parent = attachment
	p.Triggered:Connect(function()
		local item = target
		if not item then
			return
		end
		pressedAt[item.worldId] = os.clock()
		if remote then
			remote:FireServer(item.worldId)
		end
		target = nil
		p.Enabled = false
	end)
	holder, prompt = attachment, p
	return p
end

local function setTarget(item: Item?, grab: Vector3?)
	local p = ensurePrompt()
	if item and grab then
		if target ~= item then
			target = item
			local def = ItemDefs.get(item.itemId)
			p.ObjectText = if def then def.name else item.itemId
		end
		local h = holder :: Attachment
		if (h.WorldPosition - grab).Magnitude > 0.05 then
			h.WorldPosition = grab
		end
		if not p.Enabled then
			p.Enabled = true
		end
	else
		target = nil
		if p.Enabled then
			p.Enabled = false
		end
	end
end

local function check()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if tracked == 0 or not camera or not (root and root:IsA("BasePart")) or not ClientState.alive or not ClientState.inArena
		or ClientState.spectating ~= nil or ClientState.menuOpen then
		setTarget(nil)
		return
	end
	local range = tonumber(LootCfg.ItemPromptDistance) or 7
	local rootPosition = root.Position
	local eye = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local now = os.clock()
	local candidates = {}
	local x0, x1 = math.floor((rootPosition.X - range) / CELL), math.floor((rootPosition.X + range) / CELL)
	local z0, z1 = math.floor((rootPosition.Z - range) / CELL), math.floor((rootPosition.Z + range) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local list = grid[(cx + 32768) * 65536 + (cz + 32768)]
			if list then
				for _, item in ipairs(list) do
					if item.model.Parent and now - (pressedAt[item.worldId] or -math.huge) > RETRY then
						local grab = WorldItems.grabPoint(item.itemId, item.model:GetPivot())
						if WorldItems.inReach(rootPosition, grab, range) then
							local to = grab - eye
							local distance = to.Magnitude
							local angle = if distance > 1e-3 then math.acos(math.clamp(to.Unit:Dot(look), -1, 1)) else 0
							local allow = CONE + CONE_NEAR * math.clamp(1 - distance / range, 0, 1)
							if angle <= allow then
								table.insert(candidates, { item = item, grab = grab, score = angle / allow + distance / range * 0.15 })
							end
						end
					end
				end
			end
		end
	end
	if #candidates == 0 then
		setTarget(nil)
		return
	end
	table.sort(candidates, function(a, b)
		return a.score < b.score
	end)
	losParams.FilterDescendantsInstances = { character :: Model, camera } -- items, effects and loot never block (CanQuery off)
	for i = 1, math.min(#candidates, MAX_LOS) do
		local c = candidates[i]
		local to = c.grab - eye
		local length = to.Magnitude - 0.35
		if length <= 0 or workspace:Raycast(eye, to.Unit * length, losParams) == nil then
			setTarget(c.item, c.grab)
			return
		end
	end
	setTarget(nil)
end

function WorldItemController.stats(): { [string]: number }
	local cells = 0
	for _ in pairs(grid) do
		cells += 1
	end
	return { tracked = tracked, cells = cells, target = if target then target.worldId else 0 }
end

function WorldItemController.Init(_registry) end

function WorldItemController.Start()
	local ok, result = pcall(Net.event, "TakeWorldItem")
	if ok then
		remote = result
	else
		warn("[WorldItemController] TakeWorldItem remote missing: " .. tostring(result))
	end
	CollectionService:GetInstanceAddedSignal(WorldItems.LOOSE_TAG):Connect(onLooseAdded)
	CollectionService:GetInstanceRemovedSignal(WorldItems.LOOSE_TAG):Connect(onLooseRemoved)
	for _, model in ipairs(CollectionService:GetTagged(WorldItems.LOOSE_TAG)) do
		onLooseAdded(model)
	end
	ClientState.lifeChanged:Connect(function()
		if not ClientState.alive then
			setTarget(nil)
		end
	end)
	local warned = false
	while true do
		task.wait(TICK)
		local okCheck, err = pcall(check)
		if not okCheck and not warned then
			warned = true
			warn("[WorldItemController] " .. tostring(err))
		end
	end
end

return WorldItemController
