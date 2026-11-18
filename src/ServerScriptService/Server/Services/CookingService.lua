--[[
	CookingService - campfires and cooking: the server half. CookingController draws the fires and shows the prompts.
	Numbers: Shared.WildlifeConfig.Campfire. Items: Shared.ItemDefs (firewood, squirrel, cooked_squirrel).

	The recipe (two steps and a light):
	  1 Gather sticks: look at a tree's trunk from close and hold the prompt -> one Firewood (a bundle; stack 2).
	  2 Build fire: hold the Firewood, look at the ground near you and hold the prompt -> an unlit campfire there.
	  3 Light it (hold). It burns for BurnTime seconds; another Firewood adds FeedTime. It can be put out (hold), and
	    it goes out on its own. Ashes stay a while, then they are cleared.
	  Cook: with a raw item in the bag (ItemDefs cooksInto: the Squirrel), the prompt puts one on the spit. After its
	  cookTime it is done and anyone may take it: a Cooked Squirrel feeds five times what a raw one does.
	The choice: a lit fire warms (a little health a second to contenders close by), feeds, and gives light, and its
	light and its smoke column show from far off, day and night.
	A fire is a row on the server and one Configuration under ReplicatedStorage.Campfires (it replicates to everyone
	whatever is streamed in): no Parts on the server, nothing touches the terrain, nothing spreads, nothing burns.
	Only alive contenders in an Active round can do any of it, within UseRange of the fire, all checked here.

	ReplicatedStorage.Campfires.<id> (Configuration) attributes:
	  Position (Vector3, on the ground), Yaw, State "Unlit" | "Lit" | "Out", BurnsUntil (server time, Lit),
	  Spit (item id on the spit, "" = empty), SpitDone (server time it is cooked; 0 = it never will be: the fire went
	  out first), SpitResult (what it becomes), Owner (UserId)
	Remote ReplicatedStorage.Remotes.CampAction (created here, like PlusService's; not in Net.Names), client -> server:
	  "Gather", point: Vector3     the spot on the trunk the player looks at
	  "Build", point: Vector3      where the fire should go
	  "Light" | "Cook" | "Take" | "Feed" | "PutOut", fireId: number
	API
	  CookingService.cooked: Signal(player, itemId)     someone took a cooked item off a spit
	  CookingService.fires() -> { [id]: { position, state, ... } }   (tests)
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Signal = require(Shared:WaitForChild("Signal"))
local WildlifeConfig = require(Shared:WaitForChild("WildlifeConfig"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local CF = WildlifeConfig.Campfire

local CookingService = {}
CookingService.cooked = Signal.new()

local REMOTE_NAME = "CampAction"
local FOLDER_NAME = "Campfires"

type Fire = {
	id: number,
	owner: number,
	position: Vector3,
	state: string,
	builtAt: number,
	burnsUntil: number,
	outAt: number,
	spit: string,
	spitDone: number,
	spitResult: string,
	inst: Configuration,
}

local Services: { [string]: any } = {}
local folder: Folder? = nil
local fires: { [number]: Fire } = {}
local fireCount = 0
local nextId = 0
local lastGather: { [Player]: number } = {}
local lastToast: { [Player]: number } = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function toast(player: Player, text: string)
	local t = os.clock()
	if t - (lastToast[player] or 0) < 1.2 then
		return
	end
	lastToast[player] = t
	Net.event("Announce"):FireClient(player, { style = "Toast", text = text, duration = 1.8 })
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function canAct(player: Player): BasePart?
	if GameState:GetAttribute("Phase") ~= "Active" or player:GetAttribute("Frozen") == true then
		return nil
	end
	local playerService = Services.PlayerService
	if playerService and type(playerService.isAlive) == "function" then
		local ok, alive = pcall(playerService.isAlive, player)
		if not ok or alive ~= true then
			return nil
		end
	elseif player:GetAttribute("Alive") ~= true then
		return nil
	end
	return rootOf(player)
end

local function inventory()
	return Services.InventoryService
end

local function publish(fire: Fire)
	local inst = fire.inst
	inst:SetAttribute("State", fire.state)
	inst:SetAttribute("BurnsUntil", fire.burnsUntil)
	inst:SetAttribute("Spit", fire.spit)
	inst:SetAttribute("SpitDone", fire.spitDone)
	inst:SetAttribute("SpitResult", fire.spitResult)
end

local function spitIsDone(fire: Fire, t: number): boolean
	return fire.spit ~= "" and fire.spitDone > 0 and t >= fire.spitDone
end

-- What is on the spit falls beside the fire as a ground item (cooked if it was done).
local function dropSpit(fire: Fire)
	if fire.spit == "" then
		return
	end
	local itemId = if spitIsDone(fire, now()) then fire.spitResult else fire.spit
	fire.spit, fire.spitDone, fire.spitResult = "", 0, ""
	local loot = Services.LootService
	if loot and type(loot.spawnGroundItem) == "function" and GameState:GetAttribute("Phase") == "Active" then
		pcall(loot.spawnGroundItem, itemId, 1, fire.position + Vector3.new(0, 1.6, 0), Vector3.new(2.5, 4, 0))
	end
end

local function removeFire(fire: Fire, drop: boolean)
	if fires[fire.id] ~= fire then
		return
	end
	if drop then
		dropSpit(fire)
	end
	fires[fire.id] = nil
	fireCount -= 1
	fire.inst:Destroy()
end

local function putOut(fire: Fire)
	if fire.state == "Out" then
		return
	end
	local t = now()
	if fire.spit ~= "" and not spitIsDone(fire, t) then
		fire.spitDone = 0 -- it stays raw
	end
	fire.state = "Out"
	fire.outAt = t
	fire.burnsUntil = 0
	publish(fire)
end

local function clearAll()
	for _, fire in pairs(fires) do
		fire.inst:Destroy()
	end
	table.clear(fires)
	fireCount = 0
end

local function fireFor(player: Player, id: any): (Fire?, BasePart?)
	local root = canAct(player)
	if not root or type(id) ~= "number" then
		return nil, nil
	end
	local fire = fires[id]
	if not fire then
		return nil, nil
	end
	if (root.Position - fire.position).Magnitude > CF.UseRange then
		return nil, nil
	end
	return fire, root
end

--------------------------------------------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------------------------------------------

local function isTrunk(part: Instance?): boolean
	if not part or not part:IsA("BasePart") then
		return false
	end
	if string.sub(part.Name, -5) == "_Bark" or part.Name == "Trunk" then
		return true
	end
	return CollectionService:HasTag(part, "Climbable") and string.find(part.Name, "Ladder", 1, true) == nil
end

local function onGather(player: Player, point: any)
	local root = canAct(player)
	if not root or typeof(point) ~= "Vector3" or point ~= point then
		return
	end
	local t = os.clock()
	if t - (lastGather[player] or 0) < CF.GatherCooldown then
		return
	end
	if (point - root.Position).Magnitude > CF.GatherRange + 3 then
		return
	end
	-- a trunk really is there: the wildlife index knows every tree, and a ray from the head must meet bark
	local found = false
	local wildlife = Services.WildlifeService
	if wildlife and type(wildlife.nearestTree) == "function" then
		local ok, tree = pcall(wildlife.nearestTree, root.Position, CF.GatherRange + 2)
		found = ok and tree ~= nil
	end
	if not found then
		local character = player.Character :: Model
		local head = character:FindFirstChild("Head")
		local from = if head and head:IsA("BasePart") then head.Position else root.Position
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local direction = point - from
		if direction.Magnitude > 0.05 then
			local result = workspace:Raycast(from, direction.Unit * (direction.Magnitude + 2), params)
			found = result ~= nil and isTrunk(result.Instance)
		end
	end
	if not found then
		return
	end
	local inv = inventory()
	if not inv then
		return
	end
	local def = ItemDefs.get(CF.FirewoodItem)
	if def and inv.count(player, CF.FirewoodItem) >= (def.stack or 2) then
		toast(player, "You carry enough firewood")
		return
	end
	lastGather[player] = t
	if inv.give(player, CF.FirewoodItem, 1) > 0 then
		Sfx.play("Hit_Wood", { position = point, volume = 0.35, pitch = 1.25 })
	else
		local loot = Services.LootService
		if loot and type(loot.inventoryFull) == "function" then
			loot.inventoryFull(player)
		end
	end
end

local function onBuild(player: Player, point: any)
	local root = canAct(player)
	if not root or typeof(point) ~= "Vector3" or point ~= point then
		return
	end
	if not Net.rateLimit(player, "CampBuild", 1, 2) then
		return
	end
	local inv = inventory()
	if not inv or not inv.has(player, CF.FirewoodItem, 1) then
		return
	end
	if (Vector3.new(point.X, root.Position.Y, point.Z) - root.Position).Magnitude > CF.BuildRange then
		return
	end
	local result = workspace:Raycast(Vector3.new(point.X, root.Position.Y + 8, point.Z), Vector3.new(0, -30, 0), groundParams)
	if not result or result.Material == Enum.Material.Water then
		toast(player, "A fire needs dry ground")
		return
	end
	if result.Normal.Y < CF.MaxSlope then
		toast(player, "Too steep for a fire")
		return
	end
	local spot = result.Position
	if math.abs(spot.Y - root.Position.Y) > 9 then
		return
	end
	-- nothing solid over the spot (a rock, a floor): the fire sits on open ground
	local own, oldest = 0, nil
	for _, other in pairs(fires) do
		if (other.position - spot).Magnitude < CF.MinSpacing then
			toast(player, "Too close to another fire")
			return
		end
		if other.owner == player.UserId and other.state ~= "Out" then
			own += 1
			if not oldest or other.builtAt < oldest.builtAt then
				oldest = other
			end
		end
	end
	if fireCount >= CF.MaxFires then
		-- make room: the oldest ashes go first
		local ashes = nil
		for _, other in pairs(fires) do
			if other.state == "Out" and (not ashes or other.outAt < ashes.outAt) then
				ashes = other
			end
		end
		if not ashes then
			toast(player, "Too many fires are burning")
			return
		end
		removeFire(ashes, true)
	end
	if not inv.take(player, CF.FirewoodItem, 1) then
		return
	end
	if own >= CF.PerPlayer and oldest then
		putOut(oldest)
	end
	nextId += 1
	local inst = Instance.new("Configuration")
	inst.Name = tostring(nextId)
	local look = root.CFrame.LookVector
	local fire: Fire = {
		id = nextId,
		owner = player.UserId,
		position = spot,
		state = "Unlit",
		builtAt = now(),
		burnsUntil = 0,
		outAt = 0,
		spit = "",
		spitDone = 0,
		spitResult = "",
		inst = inst,
	}
	inst:SetAttribute("Position", spot)
	inst:SetAttribute("Yaw", math.atan2(look.X, look.Z))
	inst:SetAttribute("Owner", player.UserId)
	fires[fire.id] = fire
	fireCount += 1
	publish(fire)
	inst.Parent = folder
	Sfx.play("Drop", { position = spot, volume = 0.9 })
end

local function onLight(player: Player, id: any)
	local fire = fireFor(player, id)
	if not fire or fire.state ~= "Unlit" then
		return
	end
	fire.state = "Lit"
	fire.burnsUntil = now() + CF.BurnTime
	publish(fire)
end

local function onFeed(player: Player, id: any)
	local fire = fireFor(player, id)
	if not fire or fire.state ~= "Lit" then
		return
	end
	local inv = inventory()
	local t = now()
	if not inv or fire.burnsUntil - t > CF.MaxBurn - 10 then
		return
	end
	if not inv.take(player, CF.FirewoodItem, 1) then
		return
	end
	fire.burnsUntil = math.min(t + CF.MaxBurn, fire.burnsUntil + CF.FeedTime)
	publish(fire)
	Sfx.play("Drop", { position = fire.position, volume = 0.8 })
end

local function onCook(player: Player, id: any)
	local fire = fireFor(player, id)
	if not fire or fire.state ~= "Lit" or fire.spit ~= "" then
		return
	end
	local inv = inventory()
	if not inv then
		return
	end
	-- the raw thing in hand first, else the first one in the bag
	local choice: string? = nil
	local held = inv.getEquipped(player)
	local heldDef = ItemDefs.get(held)
	if heldDef and heldDef.cooksInto and ItemDefs.get(heldDef.cooksInto) then
		choice = held
	else
		local snapshot = inv.getSnapshot(player)
		for _, slot in ipairs(snapshot.slots) do
			if slot then
				local def = ItemDefs.get(slot.id)
				if def and def.cooksInto and ItemDefs.get(def.cooksInto) then
					choice = slot.id
					break
				end
			end
		end
	end
	if not choice then
		toast(player, "Nothing to cook")
		return
	end
	local def = ItemDefs.get(choice)
	if not inv.take(player, choice, 1) then
		return
	end
	fire.spit = choice
	fire.spitResult = def.cooksInto
	fire.spitDone = now() + (tonumber(def.cookTime) or CF.CookTime)
	publish(fire)
	Sfx.play("Drop", { position = fire.position, volume = 0.6, pitch = 1.3 })
end

local function onTake(player: Player, id: any)
	local fire = fireFor(player, id)
	if not fire or fire.spit == "" then
		return
	end
	local inv = inventory()
	if not inv then
		return
	end
	local done = spitIsDone(fire, now())
	local itemId = if done then fire.spitResult else fire.spit
	if inv.give(player, itemId, 1) <= 0 then
		local loot = Services.LootService
		if loot and type(loot.inventoryFull) == "function" then
			loot.inventoryFull(player)
		end
		return
	end
	fire.spit, fire.spitDone, fire.spitResult = "", 0, ""
	publish(fire)
	Sfx.playFor(player, "PickUp")
	if done then
		CookingService.cooked:Fire(player, itemId)
	end
end

local function onPutOut(player: Player, id: any)
	local fire = fireFor(player, id)
	if not fire or fire.state == "Out" then
		return
	end
	if fire.state == "Unlit" then
		removeFire(fire, true) -- kicked apart: the sticks are spent
		return
	end
	putOut(fire)
end

local ACTIONS: { [string]: (Player, any) -> () } = {
	Gather = onGather,
	Build = onBuild,
	Light = onLight,
	Feed = onFeed,
	Cook = onCook,
	Take = onTake,
	PutOut = onPutOut,
}

--------------------------------------------------------------------------------------------------------------------
-- Time: burning out, ashes, warmth
--------------------------------------------------------------------------------------------------------------------

local function tick(dt: number)
	local t = now()
	local warm: { Fire } = {}
	for _, fire in pairs(fires) do
		if fire.state == "Lit" then
			if t >= fire.burnsUntil then
				putOut(fire)
			else
				table.insert(warm, fire)
			end
		elseif fire.state == "Out" then
			if t - fire.outAt > CF.OutTime and fire.spit == "" then
				removeFire(fire, true)
			elseif t - fire.outAt > CF.OutTime * 3 then
				removeFire(fire, true)
			end
		elseif fire.state == "Unlit" and t - fire.builtAt > CF.UnlitTime then
			removeFire(fire, true)
		end
	end
	if #warm == 0 then
		return
	end
	local playerService = Services.PlayerService
	if not playerService or type(playerService.heal) ~= "function" then
		return
	end
	local amount = CF.WarmHealPerSecond * dt
	local range2 = CF.WarmRange * CF.WarmRange
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Alive") == true then
			local root = rootOf(player)
			if root then
				for _, fire in ipairs(warm) do
					local d = root.Position - fire.position
					if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= range2 then
						pcall(playerService.heal, player, amount)
						break
					end
				end
			end
		end
	end
end

function CookingService.fires()
	return fires
end

function CookingService.Init(registry)
	Services = registry
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
		existing:ClearAllChildren()
	else
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and not remotes:FindFirstChild(REMOTE_NAME) then
		local created = Instance.new("RemoteEvent")
		created.Name = REMOTE_NAME
		created.Parent = remotes
	end
end

function CookingService.Start()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild(REMOTE_NAME)
	if not (remote and remote:IsA("RemoteEvent")) then
		return
	end
	remote.OnServerEvent:Connect(function(player: Player, action: any, value: any)
		local handler = if type(action) == "string" then ACTIONS[action] else nil
		if not handler or not Net.rateLimit(player, "CampAction", 4, 6) then
			return
		end
		local ok, err = pcall(handler, player, value)
		if not ok then
			warn("[Cooking] " .. tostring(action) .. ": " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastGather[player] = nil
		lastToast[player] = nil
	end)
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = GameState:GetAttribute("Phase")
		if phase ~= "Active" and phase ~= "Countdown" then
			clearAll() -- no fire outlives its round
		end
	end)
	while true do
		local dt = task.wait(2)
		if fireCount > 0 then
			local ok, err = pcall(tick, dt)
			if not ok then
				warn("[Cooking] tick: " .. tostring(err))
			end
		end
	end
end

return CookingService
