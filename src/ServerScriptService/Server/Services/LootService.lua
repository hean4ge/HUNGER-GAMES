--[[
	LootService - supply crates and ground items. Everything lives in workspace.Arena.Loot (folders Crates and Items).

	API (docs/GameDesign.md section 8)
	  LootService.populate()      clear, then a crate on every Crate marker and (Config.Loot.GroundSpawnChance) one ground
	                              item on every Ground marker, rolled from ItemDefs.LootTables[tier]. Doesn't yield (the
	                              work is chunked in its own thread). Zero markers -> one warning, nothing else.
	  LootService.clearAll()      remove every crate and ground item (also cancels a populate or toss in progress)
	  LootService.refillSpire()   the Feast: fresh crates drop from the sky onto the Tier-3 Crate markers near the Spire
	                              (Config.Loot.SpireRefillRadius) and empty Tier-3 Ground markers there may get an item
	  LootService.spawnGroundItem(itemId, count, position, velocity?) -> Model?
	                              a takeable ground item resting on the ground below `position`; with `velocity` it is
	                              tossed from `position` first and settles where the arc meets the ground
	Markers: Parts tagged LootSpawn (attributes Tier 1|2|3, Kind "Crate"|"Ground") in ServerStorage.ArenaData.LootSpawns.
	  A crate stands on the marker's floor (its bottom face, confirmed by a short downward ray), its front facing the
	  marker's LookVector, with a small random yaw.
	Interaction: ProximityPrompts (tag "LootPrompt", attribute Range) - only alive contenders during Countdown/Active,
	  within Config.Loot.PickupRange (server-checked).
	  Crates: hold to open -> the lid swings open, CrateItemsMin..Max items (plus a bow's arrows) pop out toward the
	  opener, Sfx CrateOpen, the prompt is disabled.
	  Ground items: Take -> InventoryService.give (stacks); leftovers stay on the ground; nothing fits -> Toast
	  "Inventory full"; Sfx PickUp.
	Models: crates are tagged "SupplyCrate" (attributes Tier, Opened); ground items are tagged "GroundItem" (attributes
	  ItemId, Count) with a dim PointLight in the rarity colour (a faint glint for Rare and better).

Playability (docs/design/PlayabilityPlan.md)
	  QW3   populate() skips markers more than Config.Loot.BorderMargin outside GameState.BorderStartRadius.
	  QW7   runner's caches: markers with Runner = true get a tier-2 crate rolled from ItemDefs.LootTables.Runner (a
	        knife or 2 throwing knives, a water bottle, one tier-1 roll) and a pale canvas on a pole beside it
	        (Model "RunnerMarker", streamed to everyone). Config.Loot.RunnerCaches switches them off.
	  QW8   after the open, the opener gets a "Take all" prompt on the crate (tag "TakeAllPrompt", attribute
	        OwnerUserId; LootCueController shows it to the owner only and hides the spilled items' own prompts meanwhile)
	        for Config.Loot.TakeAllTime s: everything that fits goes in the bag, the rest stays. Items in
	        Config.Loot.AutoPickup you already carry are picked up when you walk over them (not the stack you just
	        dropped, for a few seconds). Nothing fits: toast "INVENTORY FULL" (InventoryController adds "[G] DROP
	        THE HELD ITEM" under the crosshair with this device's button).
	  QW11  Common and Uncommon ground items glint faintly too (Config.Loot.CommonGlint); an opened crate's straps go
	        slack and its clasp stops glinting (ItemModels.slackenCrate).
	  QW15  LootService.crateOpened: Signal(player, tier, runner) for the onboarding funnel.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Signal = require(Shared:WaitForChild("Signal"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local LootCfg = Config.Loot
local TAKE_ALL_TAG = "TakeAllPrompt"
local AUTO_PICKUP_INTERVAL = 0.25
local CANVAS_COLOR = Color3.fromRGB(236, 230, 212) -- pale enough to read against the treeline from the plates
local POLE_COLOR = Color3.fromRGB(118, 100, 80)

local MARKER_TAG = "LootSpawn"
local PROMPT_TAG = "LootPrompt"
local GROUND_TAG = "GroundItem"
local CRATE_TAG = "SupplyCrate"
local TOSS_STEP = 1 / 30
local TOSS_MAX_STEPS = 75

local LootService = {}
LootService.crateOpened = Signal.new() -- (player, tier, runner)

local Services: { [string]: any } = {}
local rng = Random.new()
local generation = 0 -- bumped by clearAll; long-running work stops when it changes
local warnedNoMarkers = false
local warnedNoInventory = false
local warnedNoSpireMarkers = false

type GroundState = {
	model: Model,
	id: string,
	def: any,
	count: number,
	ready: boolean,
	taken: boolean,
	position: Vector3,
	prompt: ProximityPrompt?,
	marker: BasePart?,
	noAutoPlayer: Player?, -- just dropped it: no auto-pickup for them until noAutoUntil (os.clock)
	noAutoUntil: number,
}

type CrateState = {
	model: Model,
	tier: number,
	marker: BasePart?,
	opened: boolean,
	prompt: ProximityPrompt?,
	runner: boolean,
	opener: Player?,
	spilled: { GroundState },
	takeAll: ProximityPrompt?,
}

local groundItems: { [Model]: GroundState } = {}
local crates: { [Model]: CrateState } = {}
local crateAtMarker: { [BasePart]: Model } = {}
local itemAtMarker: { [BasePart]: Model } = {}
local lastToast: { [Player]: number } = {}

local RARITY_RANK: { [string]: number } = {}
for index, name in ipairs(ItemDefs.RarityOrder) do
	RARITY_RANK[name] = index
end

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function getFolder(name: string?): Instance
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		arena = Instance.new("Folder")
		arena.Name = "Arena"
		arena.Parent = workspace
	end
	local loot = arena:FindFirstChild("Loot")
	if not loot then
		loot = Instance.new("Folder")
		loot.Name = "Loot"
		loot.Parent = arena
	end
	if not name then
		return loot
	end
	local sub = loot:FindFirstChild(name)
	if not sub then
		sub = Instance.new("Folder")
		sub.Name = name
		sub.Parent = loot
	end
	return sub
end

local function getPhase(): string
	local round = Services.RoundService
	if round and type(round.getPhase) == "function" then
		local ok, phase = pcall(round.getPhase)
		if ok and type(phase) == "string" then
			return phase
		end
	end
	return GameState:GetAttribute("Phase") or "Lobby"
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isAliveContender(player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	local playerService = Services.PlayerService
	if playerService and type(playerService.isAlive) == "function" then
		local ok, alive = pcall(playerService.isAlive, player)
		if not ok or alive ~= true then
			return false
		end
	elseif player:GetAttribute("Alive") ~= true then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Alive contender, Countdown/Active, and close enough to `position` (server-side check; prompts can be faked).
local function canInteract(player: Player, position: Vector3): boolean
	local phase = getPhase()
	if phase ~= "Countdown" and phase ~= "Active" then
		return false
	end
	if not isAliveContender(player) then
		return false
	end
	local root = rootOf(player)
	return root ~= nil and (root.Position - position).Magnitude <= (LootCfg.PickupRange or 10) + 2
end

local function toast(player: Player, text: string, sub: string?)
	local now = os.clock()
	if lastToast[player] and now - lastToast[player] < 1.2 then
		return
	end
	lastToast[player] = now
	Net.event("Announce"):FireClient(player, { style = "Toast", text = text, sub = sub, duration = if sub then 2.4 else 1.6 })
	Sfx.playFor(player, "InventoryFull")
end

-- QW8: say how to fix it. InventoryController answers a toast starting "inventory full" with "[G] DROP THE HELD ITEM"
-- under the crosshair, in this device's button, so the toast itself only names the problem.
local function inventoryFull(player: Player)
	toast(player, "INVENTORY FULL")
end

-- Raycasts for placing loot: solid geometry and terrain (water surfaces count, so loot floats), never characters,
-- training dummies, other ground items or non-collidable foliage.
local function placementParams(extra: { Instance }?): RaycastParams
	local list: { Instance } = { getFolder("Items") }
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, dummy in ipairs(CollectionService:GetTagged("TrainingDummy")) do
		table.insert(list, dummy)
	end
	if extra then
		for _, inst in ipairs(extra) do
			table.insert(list, inst)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.IgnoreWater = false
	params.RespectCanCollide = true
	return params
end

-- Lean `normal` back toward vertical so it is at most maxTilt (radians) from straight up.
local function clampUp(normal: Vector3, maxTilt: number): Vector3
	local n = if normal.Magnitude > 1e-6 then normal.Unit else Vector3.yAxis
	if math.acos(math.clamp(n.Y, -1, 1)) <= maxTilt then
		return n
	end
	local horizontal = Vector3.new(n.X, 0, n.Z)
	if horizontal.Magnitude < 1e-4 then
		return Vector3.yAxis
	end
	return (Vector3.yAxis * math.cos(maxTilt) + horizontal.Unit * math.sin(maxTilt)).Unit
end

-- A frame at `point` whose UpVector is `up` and whose LookVector is `forward` flattened onto the surface.
local function surfaceFrame(point: Vector3, up: Vector3, forward: Vector3): CFrame
	local flat = forward - up * forward:Dot(up)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.xAxis:Cross(up)
	end
	return CFrame.lookAt(point, point + flat.Unit, up)
end

local function boundsCenter(model: Model): (Vector3, number)
	local x0, x1 = ItemModels.getExtent(model, Vector3.xAxis)
	local y0, y1 = ItemModels.getExtent(model, Vector3.yAxis)
	local z0, z1 = ItemModels.getExtent(model, Vector3.zAxis)
	return Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), y1
end

-- Pivots the item so it lies naturally on the surface at `point` (centred on it, slight tilt). Random yaw, or
-- lengthwise along `facing` (e.g. along a wall it slid down).
local function restOn(model: Model, itemId: string, point: Vector3, normal: Vector3, facing: Vector3?): CFrame
	local up = clampUp(normal, math.rad(30))
	local yaw = if facing
		then (if rng:NextNumber() < 0.5 then 0 else math.pi) + rng:NextNumber(-0.12, 0.12)
		else rng:NextNumber(0, math.pi * 2)
	local frame = surfaceFrame(point, up, facing or Vector3.zAxis) * CFrame.Angles(0, yaw, 0)
	local tilt = CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06))
	local target = frame * tilt * ItemModels.restRotation(itemId)
	model:PivotTo(target)
	local low = ItemModels.getExtent(model, up)
	local r0, r1 = ItemModels.getExtent(model, frame.RightVector)
	local f0, f1 = ItemModels.getExtent(model, frame.LookVector)
	local final = target
		+ up * (point:Dot(up) - low + 0.02)
		+ frame.RightVector * (point:Dot(frame.RightVector) - (r0 + r1) / 2)
		+ frame.LookVector * (point:Dot(frame.LookVector) - (f0 + f1) / 2)
	model:PivotTo(final)
	return final
end

-- An item that came to rest poking into a wall is slid out along its horizontal axes, then re-settled on the floor.
local function unclip(model: Model, pivot: CFrame, params: RaycastParams): CFrame
	local center = boundsCenter(model)
	local origin = center + Vector3.new(0, 0.35, 0)
	local shift = Vector3.zero
	for _, axis in ipairs({ pivot.LookVector, pivot.RightVector, pivot.UpVector }) do
		local flat = Util.flat(axis)
		if flat.Magnitude > 0.5 then
			flat = flat.Unit
			local low, high = ItemModels.getExtent(model, flat)
			local mid = center:Dot(flat)
			for _, side in ipairs({ 1, -1 }) do
				local reach = if side > 0 then high - mid else mid - low
				if reach > 0.4 then
					local direction = flat * side
					local hit = workspace:Raycast(origin, direction * reach, params)
					if hit and hit.Normal.Y < 0.5 then
						shift -= direction * (reach - (hit.Position - origin):Dot(direction) + 0.05)
					end
				end
			end
		end
	end
	if shift.Magnitude < 1e-3 then
		return pivot
	end
	if shift.Magnitude > 4 then
		shift = shift.Unit * 4
	end
	local moved = pivot + shift
	model:PivotTo(moved)
	local floor = workspace:Raycast(center + shift + Vector3.new(0, 1, 0), Vector3.new(0, -4, 0), params)
	if floor then
		local low = ItemModels.getExtent(model, Vector3.yAxis)
		moved += Vector3.new(0, floor.Position.Y - low + 0.02, 0)
		model:PivotTo(moved)
	end
	return moved
end

local function objectText(def: any, count: number): string
	if count > 1 then
		return string.format("%s  \u{00D7}%d", def.name, count)
	end
	return def.name
end

local function easeOutBack(x: number): number
	local c1 = 1.2
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

--------------------------------------------------------------------------------------------------------------------
-- Rolling loot
--------------------------------------------------------------------------------------------------------------------

local function rollCount(entry: any): number
	local low = math.max(1, math.floor(tonumber(entry.min) or 1))
	local high = math.max(low, math.floor(tonumber(entry.max) or low))
	return rng:NextInteger(low, high)
end

-- n picks from the tier's table (re-rolling duplicates a few times for variety), plus each pick's lootBundle.
local function rollItems(tier: number, n: number): { { id: string, count: number } }
	local list = ItemDefs.LootTables[tier] or ItemDefs.LootTables[1]
	local out = {}
	if type(list) ~= "table" or #list == 0 then
		return out
	end
	local seen = {}
	for _ = 1, n do
		local entry = Util.weightedPick(list, rng)
		for _ = 1, 3 do
			if not seen[entry.id] then
				break
			end
			entry = Util.weightedPick(list, rng)
		end
		local def = ItemDefs.get(entry.id)
		if def and not def.hidden then
			seen[entry.id] = true
			table.insert(out, { id = def.id, count = rollCount(entry) })
			local bundle = def.lootBundle
			if type(bundle) == "table" and ItemDefs.get(bundle.id) then
				table.insert(out, { id = bundle.id, count = rollCount(bundle) })
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------------------------------------------
-- Ground items
--------------------------------------------------------------------------------------------------------------------

local function removeGroundItem(state: GroundState)
	state.taken = true
	groundItems[state.model] = nil
	if state.marker and itemAtMarker[state.marker] == state.model then
		itemAtMarker[state.marker] = nil
	end
	state.model:Destroy()
end

local function onTake(state: GroundState, player: Player)
	if state.taken or not state.ready or not state.model.Parent then
		return
	end
	if not canInteract(player, state.position) then
		return
	end
	local inventory = Services.InventoryService
	if not inventory or type(inventory.give) ~= "function" then
		if not warnedNoInventory then
			warnedNoInventory = true
			warn("[LootService] InventoryService.give is missing; ground items can't be taken")
		end
		return
	end
	local ok, result = pcall(inventory.give, player, state.id, state.count)
	if not ok then
		warn("[LootService] InventoryService.give failed: " .. tostring(result))
		return
	end
	local added = math.clamp(math.floor(tonumber(result) or 0), 0, state.count)
	if added <= 0 then
		inventoryFull(player)
		return
	end
	Sfx.playFor(player, "PickUp")
	state.count -= added
	if state.count <= 0 then
		removeGroundItem(state)
		return
	end
	state.model:SetAttribute("Count", state.count)
	if state.prompt then
		state.prompt.ObjectText = objectText(state.def, state.count)
	end
	inventoryFull(player)
end

-- Light, glint and the Take prompt, once the item has come to rest.
local function finalizeGroundItem(state: GroundState)
	local model = state.model
	local handle = model.PrimaryPart
	if state.taken or not model.Parent or not handle then
		return
	end
	local center = boundsCenter(model)
	state.position = center
	local holder = Instance.new("Attachment")
	holder.Name = "LootAttachment"
	holder.Parent = handle
	holder.WorldPosition = center + Vector3.new(0, 0.15, 0)

	local rank = RARITY_RANK[state.def.rarity] or 1
	local color = Theme.Rarity[state.def.rarity] or Color3.new(1, 1, 1)
	local light = Instance.new("PointLight")
	light.Name = "RarityLight"
	light.Color = color
	light.Brightness = (LootCfg.ItemLightBrightness or 0.9) * (0.75 + 0.15 * rank)
	light.Range = (LootCfg.ItemLightRange or 5) + 0.5 * rank
	light.Shadows = false
	light.Parent = holder
	if rank >= 3 or LootCfg.CommonGlint ~= false then
		-- QW11: Common and Uncommon glint too, more faintly (smaller, dimmer, rarer)
		local faint = rank < 3
		local glint = Instance.new("ParticleEmitter")
		glint.Name = "Glint"
		glint.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), if faint then 0.7 else 0.55))
		glint.LightEmission = 1
		glint.LightInfluence = 0
		glint.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, if faint then 0.22 + 0.04 * rank else 0.3 + 0.06 * rank),
			NumberSequenceKeypoint.new(1, 0),
		})
		glint.Transparency = NumberSequence.new(if faint then 0.45 else 0.2)
		glint.Lifetime = NumberRange.new(0.45, 0.75)
		glint.Rate = if faint then 0.25 + 0.1 * rank else 0.6 + 0.3 * rank
		glint.Speed = NumberRange.new(0)
		glint.Rotation = NumberRange.new(0, 360)
		glint.RotSpeed = NumberRange.new(-120, 120)
		glint.ZOffset = 0.4
		glint.LockedToPart = true
		glint.Parent = holder
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TakePrompt"
	prompt.ActionText = "Take"
	prompt.ObjectText = objectText(state.def, state.count)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = LootCfg.ItemPromptDistance or 7
	prompt.RequiresLineOfSight = false -- loot in bushes and grass must stay takeable
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("Range", prompt.MaxActivationDistance)
	CollectionService:AddTag(prompt, PROMPT_TAG)
	prompt.Parent = holder
	prompt.Triggered:Connect(function(player: Player)
		onTake(state, player)
	end)
	state.prompt = prompt
	state.ready = true
end

-- Fixed-step arc from origin; returns the path, the landing point and normal, the flight time and, when it slid
-- down a wall, that wall's normal.
local function simulateArc(origin: Vector3, velocity: Vector3, params: RaycastParams): ({ Vector3 }, Vector3, Vector3, number, Vector3?)
	local gravity = Vector3.new(0, -(LootCfg.TossGravity or 70), 0)
	local points = { origin }
	local position, speed = origin, velocity
	for step = 1, TOSS_MAX_STEPS do
		local nextSpeed = speed + gravity * TOSS_STEP
		local delta = (speed + nextSpeed) * 0.5 * TOSS_STEP
		local hit = workspace:Raycast(position, delta, params)
		if hit then
			if hit.Normal.Y >= 0.45 then
				table.insert(points, hit.Position)
				return points, hit.Position, hit.Normal, step * TOSS_STEP
			end
			-- hit a wall: slide down in front of it
			local back = hit.Position + hit.Normal * 0.35
			local floor = workspace:Raycast(back, Vector3.new(0, -60, 0), params)
			local land = if floor then floor.Position else back
			table.insert(points, back)
			table.insert(points, land)
			return points, land, if floor then floor.Normal else Vector3.yAxis, step * TOSS_STEP + 0.12, hit.Normal
		end
		position += delta
		speed = nextSpeed
		table.insert(points, position)
	end
	local floor = workspace:Raycast(position, Vector3.new(0, -200, 0), params)
	local land = if floor then floor.Position else position
	table.insert(points, land)
	return points, land, if floor then floor.Normal else Vector3.yAxis, TOSS_MAX_STEPS * TOSS_STEP + 0.2, nil
end

local function toss(state: GroundState, origin: Vector3, velocity: Vector3, folder: Instance, ignore: { Instance }?)
	local model = state.model
	local params = placementParams(ignore)
	local points, land, normal, duration, wallNormal = simulateArc(origin, velocity, params)
	local facing = nil
	if wallNormal then
		local flatNormal = Util.flat(wallNormal)
		if flatNormal.Magnitude > 1e-3 then
			facing = flatNormal.Unit:Cross(Vector3.yAxis) -- lie along the wall it slid down
		end
	end
	local finalPivot = unclip(model, restOn(model, state.id, land, normal, facing), params)
	local finalCenter = boundsCenter(model)
	local localCenter = finalPivot:PointToObjectSpace(finalCenter)
	local finalRotation = finalPivot.Rotation
	local startRotation = CFrame.Angles(rng:NextNumber(-1.2, 1.2), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-1.2, 1.2))
	local function pivotAt(position: Vector3, rotation: CFrame): CFrame
		return CFrame.new(position) * rotation * CFrame.new(-localCenter)
	end
	model:PivotTo(pivotAt(origin, startRotation))
	model.Parent = folder
	local gen = generation
	duration = math.max(duration, 0.2)
	task.spawn(function()
		local segments = #points - 1
		local t = 0
		while t < duration do
			t += RunService.Heartbeat:Wait()
			if state.taken or not model.Parent or gen ~= generation then
				return
			end
			local alpha = math.min(t / duration, 1)
			local f = alpha * segments
			local i = math.min(math.floor(f), segments - 1)
			local position = points[i + 1]:Lerp(points[i + 2], f - i)
			if alpha > 0.8 then
				local s = (alpha - 0.8) / 0.2
				position = position:Lerp(finalCenter, s * s * (3 - 2 * s))
			end
			model:PivotTo(pivotAt(position, startRotation:Lerp(finalRotation, alpha * alpha)))
		end
		if state.taken or not model.Parent or gen ~= generation then
			return
		end
		model:PivotTo(finalPivot)
		finalizeGroundItem(state)
	end)
end

local function spawnGround(itemId: string, count: number?, position: Vector3, velocity: Vector3?, ignore: { Instance }?): Model?
	if type(itemId) ~= "string" then
		return nil
	end
	local def = ItemDefs.get(itemId)
	if not def or def.hidden then
		return nil
	end
	local n = math.floor(tonumber(count) or 1)
	if n < 1 or not Util.isFiniteVector(position) then
		return nil
	end
	local model = ItemModels.build(itemId, "world")
	if not model or not model.PrimaryPart then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = d.Transparency < 1
		end
	end
	model.Name = itemId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("Count", n)
	CollectionService:AddTag(model, GROUND_TAG)
	local state: GroundState = {
		model = model,
		id = itemId,
		def = def,
		count = n,
		ready = false,
		taken = false,
		position = position,
		prompt = nil,
		marker = nil,
		noAutoPlayer = nil,
		noAutoUntil = 0,
	}
	groundItems[model] = state
	local folder = getFolder("Items")
	if velocity ~= nil and Util.isFiniteVector(velocity) and velocity.Magnitude > 0.5 then
		toss(state, position, velocity, folder, ignore)
	else
		local params = placementParams(ignore)
		local hit = workspace:Raycast(position + Vector3.new(0, 1.5, 0), Vector3.new(0, -80, 0), params)
		local pivot = restOn(model, itemId, if hit then hit.Position else position, if hit then hit.Normal else Vector3.yAxis)
		unclip(model, pivot, params)
		model.Parent = folder
		finalizeGroundItem(state)
	end
	return model
end

function LootService.spawnGroundItem(itemId: string, count: number?, position: Vector3, velocity: Vector3?): Model?
	local model = spawnGround(itemId, count, position, velocity, nil)
	-- QW8: whoever just dropped it (it left from where they stand) doesn't auto-pick it straight back up
	local state = model and groundItems[model]
	if state and velocity ~= nil and Util.isFiniteVector(position) then
		local nearest, best = nil, 3
		for _, other in ipairs(Players:GetPlayers()) do
			local root = rootOf(other)
			if root and math.abs(root.Position.Y - position.Y) < 6 then
				local d = Util.flat(root.Position - position).Magnitude
				if d < best then
					nearest, best = other, d
				end
			end
		end
		if nearest then
			state.noAutoPlayer = nearest
			state.noAutoUntil = os.clock() + 6
		end
	end
	return model
end

--------------------------------------------------------------------------------------------------------------------
-- Crates
--------------------------------------------------------------------------------------------------------------------

local function puffDust(model: Model)
	local base = model.PrimaryPart
	if not base then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Name = "DustPuff"
	holder.Position = Vector3.new(0, base.Size.Y / 2 + 0.5, 0)
	holder.Parent = base
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(184, 168, 144))
	dust.LightInfluence = 1
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.7, 1.2)
	dust.Speed = NumberRange.new(1.5, 3.5)
	dust.SpreadAngle = Vector2.new(75, 75)
	dust.Acceleration = Vector3.new(0, 1.2, 0)
	dust.Drag = 2
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Rate = 55
	dust.Parent = holder
	task.delay(0.15, function()
		dust.Enabled = false
	end)
	task.delay(2, function()
		holder:Destroy()
	end)
end

local function animateLid(model: Model)
	local base = model.PrimaryPart
	local lid = model:FindFirstChild("Lid")
	if not (base and lid and lid:IsA("BasePart")) then
		return
	end
	local hingeOffset = model:GetAttribute("Hinge")
	if typeof(hingeOffset) ~= "CFrame" then
		hingeOffset = CFrame.new(0, base.Size.Y / 2, base.Size.Z / 2)
	end
	local hinge = base.CFrame * (hingeOffset :: CFrame)
	local parts = { lid }
	for _, d in ipairs(lid:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local offsets = {}
	for i, part in ipairs(parts) do
		offsets[i] = hinge:ToObjectSpace(part.CFrame)
		part.CanCollide = false
	end
	local openAngle = math.rad(110)
	local duration = LootCfg.LidOpenTime or 0.45
	task.spawn(function()
		local t = 0
		while t < duration do
			t += RunService.Heartbeat:Wait()
			if not model.Parent then
				return
			end
			local pivot = hinge * CFrame.Angles(openAngle * easeOutBack(math.clamp(t / duration, 0, 1)), 0, 0)
			for i, part in ipairs(parts) do
				part.CFrame = pivot * offsets[i]
			end
		end
	end)
end

-- QW7: a runner's cache: one basic weapon, water, and a normal tier-1 roll (ItemDefs.LootTables.Runner)
local function rollRunner(): { { id: string, count: number } }
	local spec = ItemDefs.LootTables.Runner
	if type(spec) ~= "table" then
		return rollItems(2, 3)
	end
	local out, seen = {}, {}
	local function add(entry: any)
		local def = entry and ItemDefs.get(entry.id)
		if def and not def.hidden and not seen[def.id] then
			seen[def.id] = true
			table.insert(out, { id = def.id, count = rollCount(entry) })
		end
	end
	if type(spec.weapon) == "table" and #spec.weapon > 0 then
		add(Util.weightedPick(spec.weapon, rng))
	end
	if type(spec.always) == "table" then
		for _, entry in ipairs(spec.always) do
			add(entry)
		end
	end
	local list = ItemDefs.LootTables[tonumber(spec.extraTier) or 1]
	if type(list) == "table" and #list > 0 then
		for _ = 1, math.max(0, math.floor(tonumber(spec.extraRolls) or 0)) do
			local entry = Util.weightedPick(list, rng)
			for _ = 1, 4 do
				if not seen[entry.id] then
					break
				end
				entry = Util.weightedPick(list, rng)
			end
			add(entry)
		end
	end
	return out
end

-- Returns how many items pop out (they spawn over the next few tenths of a second; state.spilled collects them).
local function spill(state: CrateState, player: Player?): number
	local model = state.model
	local base = model.PrimaryPart :: BasePart
	local low, high = LootCfg.CrateItemsMin or 2, LootCfg.CrateItemsMax or 4
	local items = if state.runner
		then rollRunner()
		else rollItems(state.tier, rng:NextInteger(math.min(low, high), math.max(low, high)))
	local origin = base.Position + base.CFrame.UpVector * (base.Size.Y / 2 + 0.9)
	local toward = Util.flat(base.CFrame.LookVector)
	local root = player and rootOf(player)
	if root then
		local flat = Util.flat(root.Position - base.Position)
		if flat.Magnitude > 0.5 then
			toward = flat
		end
	end
	toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.new(0, 0, -1)
	local gen = generation
	local ignore = { model }
	for i, item in ipairs(items) do
		local spread = (i - (#items + 1) / 2) * 0.42 + rng:NextNumber(-0.15, 0.15)
		local direction = CFrame.Angles(0, spread, 0):VectorToWorldSpace(toward)
		local velocity = direction * rng:NextNumber(5.5, 8.5) + Vector3.new(0, rng:NextNumber(11, 14), 0)
		task.delay(0.12 + (i - 1) * (LootCfg.SpillDelay or 0.09), function()
			if gen == generation and model.Parent then
				local spawned = spawnGround(item.id, item.count, origin, velocity, ignore)
				local ground = spawned and groundItems[spawned]
				if ground then
					table.insert(state.spilled, ground)
					if player then
						spawned:SetAttribute("SpillOwner", player.UserId) -- LootCueController: Take all comes first
					end
				end
			end
		end)
	end
	return #items
end

-- QW8: the opener puts everything from this crate that fits into their bag in one press; the rest stays for anyone.
local function takeAll(state: CrateState, player: Player)
	if player ~= state.opener or not state.takeAll then
		return
	end
	local base = state.model.PrimaryPart
	if not base or not canInteract(player, base.Position) then
		return
	end
	local inventory = Services.InventoryService
	if not inventory or type(inventory.give) ~= "function" then
		return
	end
	local got, left = 0, 0
	for _, item in ipairs(state.spilled) do
		if not item.taken and item.model.Parent then
			local ok, result = pcall(inventory.give, player, item.id, item.count)
			local added = if ok then math.clamp(math.floor(tonumber(result) or 0), 0, item.count) else 0
			if not ok then
				warn("[LootService] InventoryService.give failed: " .. tostring(result))
			end
			if added > 0 then
				got += added
				item.count -= added
				if item.count <= 0 then
					removeGroundItem(item)
				else
					item.model:SetAttribute("Count", item.count)
					if item.prompt then
						item.prompt.ObjectText = objectText(item.def, item.count)
					end
					left += 1
				end
			else
				left += 1
			end
		end
	end
	if got > 0 then
		Sfx.playFor(player, "PickUp")
		local prompt = state.takeAll
		state.takeAll = nil
		if prompt then
			prompt:Destroy()
		end
	end
	if left > 0 then
		inventoryFull(player)
	end
end

local function offerTakeAll(state: CrateState, player: Player, delay: number)
	local window = tonumber(LootCfg.TakeAllTime) or 0
	if window <= 0 then
		return
	end
	local gen = generation
	task.delay(delay, function()
		local model = state.model
		local base = model.PrimaryPart
		if gen ~= generation or not model.Parent or not base or player.Parent ~= Players then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TakeAllPrompt"
		prompt.ActionText = "Take all"
		prompt.ObjectText = "Supply Crate"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = LootCfg.CratePromptDistance or 8
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt:SetAttribute("Range", prompt.MaxActivationDistance)
		prompt:SetAttribute("OwnerUserId", player.UserId)
		prompt:SetAttribute("Until", workspace:GetServerTimeNow() + window)
		CollectionService:AddTag(prompt, TAKE_ALL_TAG)
		prompt.Parent = base:FindFirstChild("PromptAttachment") or base
		state.takeAll = prompt
		prompt.Triggered:Connect(function(who: Player)
			takeAll(state, who)
		end)
		task.delay(window, function()
			if state.takeAll == prompt then
				state.takeAll = nil
			end
			prompt:Destroy()
		end)
	end)
end

local function openCrate(state: CrateState, player: Player)
	if state.opened then
		return
	end
	local model = state.model
	local base = model.PrimaryPart
	if not base or not model.Parent then
		return
	end
	if not canInteract(player, base.Position) then
		return
	end
	state.opened = true
	state.opener = player
	if state.prompt then
		state.prompt.Enabled = false
	end
	model:SetAttribute("Opened", true)
	local beacon = model:FindFirstChild("FeastBeacon", true)
	if beacon then
		beacon:Destroy()
	end
	-- QW11: the clasp stops glinting now, and the straps hang loose once the lid has swung open
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Name == "Glint" then
			d.Enabled = false
		end
	end
	Sfx.play("CrateOpen", { position = base.Position })
	animateLid(model)
	task.delay((LootCfg.LidOpenTime or 0.45) + 0.06, function()
		if model.Parent then
			local ok, err = pcall(ItemModels.slackenCrate, model)
			if not ok then
				warn("[LootService] slackenCrate failed: " .. tostring(err))
			end
		end
	end)
	puffDust(model)
	local count = spill(state, player)
	-- QW8: Take all appears once every item is out of the crate (they may still be in the air)
	offerTakeAll(state, player, 0.12 + math.max(0, count - 1) * (LootCfg.SpillDelay or 0.09) + 0.05)
	LootService.crateOpened:Fire(player, state.tier, state.runner)
end

local function destroyCrate(model: Model)
	local state = crates[model]
	crates[model] = nil
	if state and state.marker and crateAtMarker[state.marker] == model then
		crateAtMarker[state.marker] = nil
	end
	model:Destroy()
end

local function dropCrateIn(state: CrateState, finalPivot: CFrame, delay: number)
	local model = state.model
	local base = model.PrimaryPart :: BasePart
	local height = LootCfg.FeastDropHeight or 55
	local beacon = Instance.new("PointLight")
	beacon.Name = "FeastBeacon"
	beacon.Color = Theme.Colors.Accent
	beacon.Brightness = 1.6
	beacon.Range = 16
	beacon.Shadows = false
	beacon.Parent = base:FindFirstChild("PromptAttachment") or base
	model:PivotTo(finalPivot + Vector3.new(0, height, 0))
	model.Parent = getFolder("Crates")
	local gen = generation
	task.spawn(function()
		if delay > 0 then
			task.wait(delay)
		end
		local duration = 1.1
		local t = 0
		while t < duration do
			t += RunService.Heartbeat:Wait()
			if gen ~= generation or not model.Parent then
				return
			end
			local a = math.clamp(t / duration, 0, 1)
			model:PivotTo(finalPivot + Vector3.new(0, height * (1 - a * a), 0))
		end
		if gen ~= generation or not model.Parent then
			return
		end
		model:PivotTo(finalPivot)
		puffDust(model)
		Sfx.play("Land_Hard", { position = finalPivot.Position, volume = 1.4 })
		if state.prompt and not state.opened then
			state.prompt.Enabled = true
		end
		task.delay(40, function()
			if beacon.Parent then
				beacon:Destroy()
			end
		end)
	end)
end

-- Where a crate stands for a marker: the marker's bottom face, snapped to the floor right under it.
local function crateFrame(marker: BasePart, params: RaycastParams): CFrame
	local bottom = (marker.CFrame * CFrame.new(0, -marker.Size.Y / 2, 0)).Position
	local hit = workspace:Raycast(bottom + Vector3.new(0, 2, 0), Vector3.new(0, -6, 0), params)
	local floor = if hit then hit.Position else bottom
	local normal = if hit then hit.Normal else Vector3.yAxis
	local up = Vector3.yAxis:Lerp(clampUp(normal, math.rad(14)), 0.6).Unit
	return surfaceFrame(floor, up, marker.CFrame.LookVector) * CFrame.Angles(0, rng:NextNumber(-0.16, 0.16), 0)
end

-- QW7: a pale canvas hung from a crossbar on a pole beside a runner's cache (Parts only), facing the Spire so it reads
-- from the launch plates.
local function buildRunnerMarker(frame: CFrame, params: RaycastParams): Model
	local spot = frame * CFrame.new(3.3, 0, 0.8) -- to the crate's right, a little behind its front
	local hit = workspace:Raycast(spot.Position + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
	local ground = if hit then hit.Position else spot.Position
	local face = Util.flat(frame.LookVector)
	face = if face.Magnitude > 1e-3 then face.Unit else Vector3.new(0, 0, -1)
	-- sized to read from a launch plate 100-150 studs away (a 5.4-stud cloth is ~30 px tall at 1570x753)
	local height, sink = 14, 0.8
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), 0, math.rad(rng:NextNumber(-3, 3)))
	local foot = CFrame.lookAt(ground, ground + face) * lean
	local model = Instance.new("Model")
	model.Name = "RunnerMarker"
	local function part(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, solid: boolean): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = solid
		p.CanQuery = solid
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local poleLength = height + sink
	-- a Cylinder's axis is its X: turned upright
	local pole = part("Pole", Enum.PartType.Cylinder, Vector3.new(poleLength, 0.42, 0.42),
		foot * CFrame.new(0, poleLength / 2 - sink, 0) * CFrame.Angles(0, 0, math.rad(90)), POLE_COLOR, Enum.Material.Wood, true)
	model.PrimaryPart = pole
	local top = foot * CFrame.new(0, height - 0.35, 0)
	part("Crossbar", Enum.PartType.Cylinder, Vector3.new(4.8, 0.24, 0.24), top * CFrame.new(1.9, 0, 0), POLE_COLOR, Enum.Material.Wood, false)
	-- the canvas hangs from the crossbar, stirred a little by the wind
	local sway = CFrame.Angles(math.rad(rng:NextNumber(4, 10)), 0, math.rad(rng:NextNumber(-2, 2)))
	local canvas = part("Canvas", Enum.PartType.Block, Vector3.new(4.2, 5.4, 0.06),
		top * CFrame.new(1.95, -0.1, 0) * sway * CFrame.new(0, -2.7, 0), CANVAS_COLOR, Enum.Material.Fabric, false)
	part("CanvasTail", Enum.PartType.Block, Vector3.new(0.7, 1.7, 0.05),
		canvas.CFrame * CFrame.new(1.4, -3.45, 0.01) * CFrame.Angles(math.rad(6), 0, math.rad(rng:NextNumber(-8, 8))),
		CANVAS_COLOR, Enum.Material.Fabric, false)
	for _, x in ipairs({ 0.1, 3.8 }) do
		part("Tie", Enum.PartType.Block, Vector3.new(0.14, 0.3, 0.26), top * CFrame.new(x, -0.05, 0), Color3.fromRGB(92, 78, 60), Enum.Material.Fabric, false)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- seen from the plates, whatever the streaming radius
	return model
end

local function spawnCrate(marker: BasePart?, tier: number, frame: CFrame, dropIn: boolean, delay: number?): Model
	local runner = marker ~= nil and marker:GetAttribute("Runner") == true and LootCfg.RunnerCaches ~= false
	local model = ItemModels.buildCrate(tier)
	local base = model.PrimaryPart :: BasePart
	if runner then
		model:SetAttribute("Runner", true)
	end
	local finalPivot = frame * CFrame.new(0, base.Size.Y / 2 - 0.1, 0) -- sunk a touch so it never floats
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, CRATE_TAG)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Supply Crate"
	prompt.HoldDuration = LootCfg.CrateOpenTime or 0.6
	prompt.MaxActivationDistance = LootCfg.CratePromptDistance or 8
	-- the prompt sits in front of the crate: with line of sight on, the crate's own body hid it from behind and E did
	-- nothing (P7). The server still checks Config.Loot.PickupRange when it opens.
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("Range", prompt.MaxActivationDistance)
	CollectionService:AddTag(prompt, PROMPT_TAG)
	prompt.Parent = base:FindFirstChild("PromptAttachment") or base
	local state: CrateState = {
		model = model,
		tier = tier,
		marker = marker,
		opened = false,
		prompt = prompt,
		runner = runner,
		opener = nil,
		spilled = {},
		takeAll = nil,
	}
	crates[model] = state
	if marker then
		crateAtMarker[marker] = model
	end
	prompt.Triggered:Connect(function(player: Player)
		openCrate(state, player)
	end)
	if dropIn then
		prompt.Enabled = false
		dropCrateIn(state, finalPivot, delay or 0)
	else
		model:PivotTo(finalPivot)
		model.Parent = getFolder("Crates")
	end
	if runner then
		local ok, flag = pcall(buildRunnerMarker, frame, placementParams({ model }))
		if ok and flag then
			flag.Parent = getFolder("Crates")
		elseif not ok then
			warn("[LootService] runner marker failed: " .. tostring(flag))
		end
	end
	return model
end

--------------------------------------------------------------------------------------------------------------------
-- Markers
--------------------------------------------------------------------------------------------------------------------

local function tierOf(marker: Instance): number
	return math.clamp(math.floor(tonumber(marker:GetAttribute("Tier")) or 1), 1, 3)
end

local function collectMarkers(): { BasePart }
	local list: { BasePart } = {}
	local seen: { [Instance]: boolean } = {}
	local data = ServerStorage:FindFirstChild("ArenaData")
	local folder = data and data:FindFirstChild("LootSpawns")
	local function consider(inst: Instance)
		if seen[inst] or not inst:IsA("BasePart") then
			return
		end
		local kind = inst:GetAttribute("Kind")
		if kind == "Crate" or kind == "Ground" then
			seen[inst] = true
			table.insert(list, inst)
		end
	end
	if folder then
		for _, inst in ipairs(folder:GetDescendants()) do
			consider(inst)
		end
	end
	-- tagged markers placed directly in the world also count (templates in ServerStorage don't)
	for _, inst in ipairs(CollectionService:GetTagged(MARKER_TAG)) do
		if inst:IsDescendantOf(workspace) then
			consider(inst)
		end
	end
	return list
end

local function spawnAtGroundMarker(marker: BasePart, tier: number): Model?
	local items = rollItems(tier, 1)
	local first = items[1]
	if not first then
		return nil
	end
	local bottom = (marker.CFrame * CFrame.new(0, -marker.Size.Y / 2, 0)).Position
	local model = spawnGround(first.id, first.count, bottom + Vector3.new(0, 0.3, 0), nil, nil)
	if model then
		local state = groundItems[model]
		if state then
			state.marker = marker
		end
		itemAtMarker[marker] = model
	end
	for i = 2, #items do
		local offset = Vector3.new(rng:NextNumber(-0.9, 0.9), 0.3, rng:NextNumber(-0.9, 0.9))
		spawnGround(items[i].id, items[i].count, bottom + offset, nil, nil)
	end
	return model
end

--------------------------------------------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------------------------------------------

function LootService.clearAll()
	generation += 1
	for model in pairs(crates) do
		model:Destroy()
	end
	for model, state in pairs(groundItems) do
		state.taken = true
		model:Destroy()
	end
	table.clear(crates)
	table.clear(groundItems)
	table.clear(crateAtMarker)
	table.clear(itemAtMarker)
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	if loot then
		for _, child in ipairs(loot:GetChildren()) do
			if child:IsA("Folder") then
				child:ClearAllChildren()
			else
				child:Destroy()
			end
		end
	end
end

function LootService.populate()
	LootService.clearAll()
	local gen = generation
	local markers = collectMarkers()
	if #markers == 0 then
		if not warnedNoMarkers then
			warnedNoMarkers = true
			warn("[LootService] No LootSpawn markers in ServerStorage.ArenaData.LootSpawns; the arena has no loot")
		end
		return
	end
	task.spawn(function()
		local params = placementParams()
		local crateCount, itemCount, skipped = 0, 0, 0
		-- QW3: loot only where the people are (this round's starting ring plus a margin)
		local r0 = tonumber(GameState:GetAttribute("BorderStartRadius")) or Config.Border.StartRadius
		local limit = r0 + (LootCfg.BorderMargin or 30)
		for index, marker in ipairs(markers) do
			if gen ~= generation then
				return
			end
			local outside = ArenaLayout.flatDistance(marker.Position) > limit
				or (marker:GetAttribute("Runner") == true and LootCfg.RunnerCaches == false)
			if outside then
				skipped += 1
			elseif marker.Parent then
				local ok, err = pcall(function()
					local tier = tierOf(marker)
					if marker:GetAttribute("Kind") == "Crate" then
						spawnCrate(marker, tier, crateFrame(marker, params), false)
						crateCount += 1
					elseif rng:NextNumber() < (LootCfg.GroundSpawnChance or 0.65) then
						if spawnAtGroundMarker(marker, tier) then
							itemCount += 1
						end
					end
				end)
				if not ok then
					warn("[LootService] marker " .. marker:GetFullName() .. " failed: " .. tostring(err))
				end
			end
			if index % 12 == 0 then
				task.wait()
			end
		end
		print(string.format("[LootService] %d crates and %d ground items from %d markers (%d skipped outside r %d)", crateCount, itemCount, #markers, skipped, math.floor(limit)))
	end)
end

function LootService.refillSpire()
	local radius = LootCfg.SpireRefillRadius or 90
	local params = placementParams()
	local crateCount, itemCount = 0, 0
	for _, marker in ipairs(collectMarkers()) do
		if marker.Parent and tierOf(marker) == 3 and ArenaLayout.flatDistance(marker.Position) <= radius then
			local ok, err = pcall(function()
				if marker:GetAttribute("Kind") == "Crate" then
					local old = crateAtMarker[marker]
					if old then
						destroyCrate(old)
					end
					-- DropIn = false (the Spire's niche markers, Populate v2): restocked in place, not dropped through the Spire
					spawnCrate(marker, 3, crateFrame(marker, params), marker:GetAttribute("DropIn") ~= false, crateCount * 0.18)
					crateCount += 1
				else
					local existing = itemAtMarker[marker]
					if not (existing and existing.Parent) and rng:NextNumber() < (LootCfg.GroundSpawnChance or 0.65) then
						if spawnAtGroundMarker(marker, 3) then
							itemCount += 1
						end
					end
				end
			end)
			if not ok then
				warn("[LootService] refill " .. marker:GetFullName() .. " failed: " .. tostring(err))
			end
		end
	end
	if crateCount == 0 and itemCount == 0 and not warnedNoSpireMarkers then
		warnedNoSpireMarkers = true
		warn("[LootService] refillSpire: no Tier-3 markers within " .. radius .. " studs of the arena centre")
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

-- QW8: ammo and throwing knives you already carry are picked up as you walk over them (server-checked range)
local function autoPickupTick()
	local ids = LootCfg.AutoPickup
	if type(ids) ~= "table" or next(ids) == nil then
		return
	end
	local phase = getPhase()
	if phase ~= "Active" and phase ~= "Countdown" then
		return
	end
	local inventory = Services.InventoryService
	if not inventory or type(inventory.count) ~= "function" or type(inventory.give) ~= "function" then
		return
	end
	local candidates = {}
	for _, state in pairs(groundItems) do
		if ids[state.id] and state.ready and not state.taken and state.model.Parent then
			table.insert(candidates, state)
		end
	end
	if #candidates == 0 then
		return
	end
	local range = math.min(tonumber(LootCfg.AutoPickupRange) or 3.5, (LootCfg.PickupRange or 10))
	local clock = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and isAliveContender(player) then
			local p = root.Position
			for _, state in ipairs(candidates) do
				local d = state.position - p
				if not state.taken and math.abs(d.Y) <= 5 and Vector3.new(d.X, 0, d.Z).Magnitude <= range
					and not (state.noAutoPlayer == player and clock < state.noAutoUntil) then
					local okCount, have = pcall(inventory.count, player, state.id)
					if okCount and (tonumber(have) or 0) > 0 then
						local ok, result = pcall(inventory.give, player, state.id, state.count)
						local added = if ok then math.clamp(math.floor(tonumber(result) or 0), 0, state.count) else 0
						if added > 0 then
							Sfx.playFor(player, "PickUp")
							state.count -= added
							if state.count <= 0 then
								removeGroundItem(state)
							else
								state.model:SetAttribute("Count", state.count)
								if state.prompt then
									state.prompt.ObjectText = objectText(state.def, state.count)
								end
							end
						end
					end
				end
			end
		end
	end
end

function LootService.Init(registry)
	Services = registry
end

function LootService.Start()
	getFolder("Crates")
	getFolder("Items")
	Players.PlayerRemoving:Connect(function(player)
		lastToast[player] = nil
	end)
	local warnedAuto = false
	while true do
		task.wait(AUTO_PICKUP_INTERVAL)
		local ok, err = pcall(autoPickupTick)
		if not ok and not warnedAuto then
			warnedAuto = true
			warn("[LootService] auto-pickup failed: " .. tostring(err))
		end
	end
end

return LootService
