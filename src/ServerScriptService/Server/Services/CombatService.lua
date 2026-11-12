--[[
	CombatService - server-authoritative melee and ranged combat, plus the Studio training dummies.

	Client -> server
	  MeleeSwing(lookDirection: Vector3)                       sent at the strike moment of a swing
	  RangedRelease(shotId, origin, direction, charge, mode)
	    "Fire"   bow shot: consumes 1 arrow; speed and damage scale with charge (capped by the measured draw time)
	    "Throw"  throwing knife (consumes 1) or spear (removes the equipped spear)
	    "Draw"   the bow draw started: the server times the charge and tells other clients (CombatAction "Draw")
	    "Cancel" the draw was let down without shooting
	Server -> client
	  HitConfirm { damage, headshot, killed, position? (hit point), target = "Player" | "Dummy", weaponId?, melee }
	    to the attacker
	  CombatAction { userId, action = "Swing" | "Draw" | "Release" | "Throw", itemId, cancelled? }   to everyone else
	  Sfx: swing, release and impact sounds for everyone except the attacker (who plays them locally, instantly)

	API
	  CombatService.applyHit(attacker: Player?, humanoid: Humanoid, baseDamage: number, info) -> (damageDealt, killed)
	    info = { cause = "Combat", weaponId = string?, position = Vector3? (where the attack came from),
	             headshot = boolean?, hitPosition = Vector3? }
	    Players: damage * InventoryService.getArmorMultiplier(victim) through PlayerService.damage.
	    Other humanoids (training dummies): Humanoid:TakeDamage. Never yourself, dead players, or outside Active.
	  CombatService.characterFromPart(part) -> (Humanoid?, Model?, BasePart?)   accessories resolve to the body part they're worn on
	  CombatService.getTargets(exclude: Instance?) -> { Model }   every character and training dummy that can be hit

	Training dummies: practice rounds only (GameState.Practice), during Active; in Studio, and on live servers while
	Config.Round.SoloPractice is on (PlayabilityPlan QW1).
	Config.Combat.PracticeDummies dummies appear in front of the contender, between the plinths and the Spire, tagged
	TrainingDummy. They wobble when hit, heal after DummyRegenDelay, and respawn DummyRespawnTime after breaking.
	Template: ServerStorage.Dev.TrainingDummy (built by ServerStorage.WorldGen.DummyBuilder).
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
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local CombatConfig = Config.Combat

local DUMMY_TAG = "TrainingDummy"
local FISTS = ItemDefs.get("fists")
local MELEE_FACING_DOT = -0.2 -- flat swing direction vs. character facing; lenient because the server's view lags
local RANGED_FACING_DOT = -0.35
local HEAVY_SWING_COOLDOWN = 0.75 -- weapons at least this slow use the heavy swing sound
local BOW_MIN_INTERVAL = 0.3 -- seconds between two arrows, on top of the draw time
local CHARGE_JITTER = 0.15 -- seconds of draw time forgiven for network jitter

local CombatService = {}

local Services: { [string]: any } = {}
local HitConfirm: RemoteEvent
local CombatAction: RemoteEvent

type PlayerState = {
	nextSwing: number,
	nextShot: number,
	nextThrow: number,
	lastShot: number,
	drawStart: number?,
	drawItem: string?,
}
local playerState: { [Player]: PlayerState } = {}

type Context = { character: Model, humanoid: Humanoid, head: BasePart, root: BasePart }

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function phaseActive(): boolean
	local round = Services.RoundService
	if round and type(round.getPhase) == "function" then
		return round.getPhase() == "Active"
	end
	return GameState:GetAttribute("Phase") == "Active"
end

local function isAliveContender(player: Player): boolean
	local playerService = Services.PlayerService
	if playerService and type(playerService.isAlive) == "function" then
		return playerService.isAlive(player) == true
	end
	return player:GetAttribute("Alive") == true
end

local function stateFor(player: Player): PlayerState
	local st = playerState[player]
	if not st then
		st = { nextSwing = 0, nextShot = 0, nextThrow = 0, lastShot = 0, drawStart = nil, drawItem = nil }
		playerState[player] = st
	end
	return st
end

-- Cooldown that forgives network jitter without being exploitable: an early action doesn't pull the next window
-- earlier, so spamming at (cooldown - jitter) gains nothing on average.
local function tryCooldown(st: any, key: string, cooldown: number, now: number): boolean
	local ready = st[key] or 0
	if now < ready - (CombatConfig.CooldownJitter or 0.12) then
		return false
	end
	st[key] = math.max(now, ready) + cooldown
	return true
end

local function getContext(player: Player): Context?
	if not phaseActive() or player:GetAttribute("Frozen") == true or not isAliveContender(player) then
		return nil
	end
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	if not (head and head:IsA("BasePart")) or not (root and root:IsA("BasePart")) then
		return nil
	end
	return { character = character, humanoid = humanoid, head = head, root = root }
end

local function equippedItemId(player: Player): string?
	local inventory = Services.InventoryService
	if inventory and type(inventory.getEquipped) == "function" then
		local itemId = inventory.getEquipped(player)
		if type(itemId) == "string" then
			return itemId
		end
	end
	return nil
end

-- The melee stats used for the equipped item: fists for nothing, ammo or utility items; nil for items that never swing.
local function meleeDefFor(itemId: string?)
	local def = ItemDefs.get(itemId)
	if def == nil or def.kind == "Ammo" or def.kind == "Utility" then
		return FISTS
	end
	if def.kind == "Melee" then
		return def
	end
	return nil
end

local function hasItem(player: Player, itemId: string, count: number): boolean
	local inventory = Services.InventoryService
	return inventory ~= nil and type(inventory.has) == "function" and inventory.has(player, itemId, count) == true
end

local function consumeItem(player: Player, itemId: string, count: number): boolean
	local inventory = Services.InventoryService
	if not inventory then
		return false
	end
	local consume = inventory.consume or inventory.take
	return type(consume) == "function" and consume(player, itemId, count) == true
end

-- A shot the projectile caps refused gives its item back: nothing thrown or shot is ever lost.
local function refund(player: Player, itemId: string)
	local inventory = Services.InventoryService
	if inventory and type(inventory.give) == "function" then
		pcall(inventory.give, player, itemId, 1)
	end
end

local function facingOk(root: BasePart, direction: Vector3, minDot: number): boolean
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.3 then
		return true -- looking almost straight up or down
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.1 then
		return true
	end
	return flat.Unit:Dot(flatLook.Unit) >= minDot
end

local function broadcastAction(player: Player, action: string, itemId: string?, cancelled: boolean?)
	local payload = { userId = player.UserId, action = action, itemId = itemId or "fists", cancelled = cancelled == true }
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			CombatAction:FireClient(other, payload)
		end
	end
end

local SOUND_BY_MATERIAL: { [string]: string } = {
	Metal = "Hit_Metal", CorrodedMetal = "Hit_Metal", DiamondPlate = "Hit_Metal", Foil = "Hit_Metal",
	Wood = "Hit_Wood", WoodPlanks = "Hit_Wood", Fabric = "Hit_Wood", Grass = "Hit_Wood", LeafyGrass = "Hit_Wood",
	Ground = "Hit_Wood", Mud = "Hit_Wood", Sand = "Hit_Wood", Snow = "Hit_Wood", Cardboard = "Hit_Wood",
	Carpet = "Hit_Wood", Leather = "Hit_Wood", Rubber = "Hit_Wood", Plastic = "Hit_Wood", SmoothPlastic = "Hit_Wood",
}

local function worldHitSound(material: Enum.Material?): string
	return (material and SOUND_BY_MATERIAL[material.Name]) or "Hit_Stone"
end

-- Ground items (crates are solid and stay hittable).
local function lootFolder(): Instance?
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	return loot and loot:FindFirstChild("Items")
end

-- World geometry only: characters and dummies are excluded (they get their own precise pass) and non-collidable
-- foliage is ignored, so bushes and leaves don't stop a blade.
local function worldParams(targets: { Instance }, extra: Instance?): RaycastParams
	local list = table.clone(targets)
	if extra then
		table.insert(list, extra)
	end
	local loot = lootFolder()
	if loot then
		table.insert(list, loot)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

--------------------------------------------------------------------------------------------------------------------
-- Public helpers
--------------------------------------------------------------------------------------------------------------------

local HEAD_ATTACHMENTS = { HatAttachment = true, HairAttachment = true, FaceFrontAttachment = true, FaceCenterAttachment = true }

local function wornOn(handle: BasePart, accessory: Instance): BasePart?
	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
			local a = (child :: any).Part0
			local b = (child :: any).Part1
			local other = if a == handle then b else a
			if other and other ~= handle and other:IsA("BasePart") then
				return other
			end
		elseif child:IsA("RigidConstraint") then
			-- current avatars (layered clothing, most accessories) hang on a RigidConstraint between two attachments
			local a = child.Attachment0
			local b = child.Attachment1
			local other = if a and a.Parent == handle then b else a
			local part = other and other.Parent
			if part and part ~= handle and part:IsA("BasePart") then
				return part
			end
		end
	end
	local character = accessory.Parent
	if character then
		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("Attachment") and HEAD_ATTACHMENTS[child.Name] then
				local head = character:FindFirstChild("Head")
				if head and head:IsA("BasePart") then
					return head
				end
			end
		end
	end
	return nil
end

function CombatService.characterFromPart(part: Instance?): (Humanoid?, Model?, BasePart?)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil, nil, nil
	end
	local bodyPart: BasePart = part
	local parent = part.Parent
	if parent and parent:IsA("Accessory") then
		bodyPart = wornOn(part, parent) or part
		parent = parent.Parent
	end
	if parent and parent:IsA("Model") then
		local humanoid = parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, parent, bodyPart
		end
	end
	return nil, nil, nil
end

function CombatService.getTargets(exclude: Instance?): { Instance }
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		if character and character ~= exclude and character.Parent then
			table.insert(list, character)
		end
	end
	for _, dummy in ipairs(CollectionService:GetTagged(DUMMY_TAG)) do
		if dummy ~= exclude and dummy:IsA("Model") and dummy:IsDescendantOf(workspace) then
			table.insert(list, dummy)
		end
	end
	return list
end

--------------------------------------------------------------------------------------------------------------------
-- Training dummies
--------------------------------------------------------------------------------------------------------------------

type DummySlot = { cframe: CFrame, model: Model?, stand: Instance? }
type DummyData = {
	lastHit: number,
	wobble: number,
	wobbleTime: number,
	axis: Vector3,
	push: Vector3,
	motor: Motor6D?,
	baseC0: CFrame?,
}

local dummyFolder: Folder? = nil
local dummySlots: { DummySlot } = {}
local dummyData: { [Model]: DummyData } = {}
local dummiesWanted = false
local warnedTemplate = false

local function getDummyFolder(): Folder
	if dummyFolder and dummyFolder.Parent then
		return dummyFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "TrainingDummies"
	folder.Parent = workspace
	dummyFolder = folder
	return folder
end

local function dummyTemplate(): Model?
	local dev = ServerStorage:FindFirstChild("Dev")
	local template = dev and dev:FindFirstChild("TrainingDummy")
	if template and template:IsA("Model") then
		return template
	end
	-- Fall back to building one (the builder works at runtime too) and keep it as the template.
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local builder = worldGen and worldGen:FindFirstChild("DummyBuilder")
	if builder and builder:IsA("ModuleScript") then
		local ok, result = pcall(function()
			return require(builder :: ModuleScript).create()
		end)
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			result.Name = "TrainingDummy"
			result.Parent = dev or ServerStorage
			return result
		end
	end
	if not warnedTemplate then
		warnedTemplate = true
		warn("[CombatService] No ServerStorage.Dev.TrainingDummy template; run ServerStorage.WorldGen.DummyBuilder.build()")
	end
	return nil
end

local function practiceContenderRoot(): BasePart?
	for _, other in ipairs(Players:GetPlayers()) do
		if other:GetAttribute("Alive") == true and other.Character then
			local root = other.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root
			end
		end
	end
	return nil
end

-- Dummies stand in a shallow arc a dozen studs in front of the practice contender, toward the Spire.
local function dummyLayout(): { CFrame }
	local center = Vector3.new(ArenaLayout.Center.X, ArenaLayout.BaseHeight, ArenaLayout.Center.Z)
	local root = practiceContenderRoot()
	local anchor = if root then root.Position else ArenaLayout.polar(0, ArenaLayout.PlinthRingRadius, ArenaLayout.BaseHeight + 3)
	local toCenter = Util.flat(center - anchor)
	toCenter = if toCenter.Magnitude > 1 then toCenter.Unit else Vector3.new(0, 0, 1)
	local right = toCenter:Cross(Vector3.yAxis)

	local ignore = CombatService.getTargets(nil)
	local loot = lootFolder()
	if loot then
		table.insert(ignore, loot)
	end
	if dummyFolder then
		table.insert(ignore, dummyFolder)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = false -- stand on what you can see (path overlays are non-collidable)
	params.IgnoreWater = false

	local spots = {}
	local count = math.max(0, math.floor(CombatConfig.PracticeDummies or 3))
	for i = 1, count do
		local lateral = (i - (count + 1) / 2) * 7
		local ahead = 13 + math.abs(lateral) * 0.3
		local spot = anchor + toCenter * ahead + right * lateral
		local ground = workspace:Raycast(Vector3.new(spot.X, anchor.Y + 40, spot.Z), Vector3.new(0, -120, 0), params)
		local position = if ground then ground.Position else Vector3.new(spot.X, ArenaLayout.BaseHeight, spot.Z)
		local face = Vector3.new(anchor.X, position.Y, anchor.Z)
		if (face - position).Magnitude < 0.5 then
			face = position - toCenter
		end
		table.insert(spots, CFrame.lookAt(position, face))
	end
	return spots
end

local spawnDummy: (slot: DummySlot) -> ()

local function breakDummy(model: Model, slot: DummySlot)
	local data = dummyData[model]
	if not data then
		return -- already broken (Died and HealthChanged can both report it)
	end
	dummyData[model] = nil
	-- arrows and blades in it come out now, where they are, and drop to the ground before its parts tumble away
	local projectiles = Services.ProjectileService
	local world = projectiles and projectiles.world
	if world and type(world.releaseFrom) == "function" then
		local ok, err = pcall(world.releaseFrom, model)
		if not ok then
			warn("[CombatService] couldn't free the items stuck in a training dummy: " .. tostring(err))
		end
	end
	CollectionService:RemoveTag(model, DUMMY_TAG)
	local push = if data then data.push else Vector3.zero
	local head = model:FindFirstChild("Head")
	local bar = head and head:FindFirstChild("HealthBar")
	if bar and bar:IsA("BillboardGui") then
		bar.Enabled = false
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		root:Destroy()
	end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("Motor6D") then
			inst:Destroy()
		end
	end
	local soundAt: Vector3? = nil
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = true
			inst.CanQuery = false
			inst.CanTouch = false
			soundAt = soundAt or inst.Position
		end
	end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			pcall(function()
				inst:SetNetworkOwner(nil)
			end)
			local scatter = Vector3.new(math.random() - 0.5, 0.6 + math.random() * 0.5, math.random() - 0.5)
			inst:ApplyImpulse((push * 16 + scatter * 14) * inst.AssemblyMass)
			inst:ApplyAngularImpulse(Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 6 * inst.AssemblyMass)
		end
	end
	if soundAt then
		Sfx.play("Hit_Wood", { position = soundAt, volume = 1.3, pitch = 0.75 })
	end
	task.delay(CombatConfig.DummyRespawnTime or 3, function()
		if model.Parent then
			model:Destroy()
		end
		if slot.model == model then
			slot.model = nil
			if dummiesWanted and table.find(dummySlots, slot) then
				spawnDummy(slot)
			end
		end
	end)
end

spawnDummy = function(slot: DummySlot)
	if not dummiesWanted then
		return
	end
	local template = dummyTemplate()
	if not template then
		return
	end
	local model = template:Clone()
	model:PivotTo(slot.cframe)
	local stand = model:FindFirstChild("Stand")
	if stand then
		if slot.stand and slot.stand.Parent then
			stand:Destroy()
		else
			stand.Parent = getDummyFolder()
			slot.stand = stand
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		model:Destroy()
		return
	end
	local maxHealth = CombatConfig.DummyHealth or 200
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	local upperTorso = model:FindFirstChild("UpperTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist")
	local motor = if waist and waist:IsA("Motor6D") then waist else nil
	dummyData[model] = {
		lastHit = 0,
		wobble = 0,
		wobbleTime = 0,
		axis = Vector3.xAxis,
		push = Vector3.zero,
		motor = motor,
		baseC0 = if motor then motor.C0 else nil,
	}
	CollectionService:AddTag(model, DUMMY_TAG)
	model.Parent = getDummyFolder()
	slot.model = model

	local head = model:FindFirstChild("Head")
	local bar = head and head:FindFirstChild("HealthBar")
	local track = bar and bar:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Fill")
	humanoid.HealthChanged:Connect(function(health: number)
		if fill and fill:IsA("GuiObject") then
			local alpha = math.clamp(health / math.max(humanoid.MaxHealth, 1), 0, 1)
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			fill.BackgroundColor3 = Theme.Colors.HealthLow:Lerp(Theme.Colors.Health, math.clamp(alpha * 1.6, 0, 1))
		end
		if health <= 0 then
			breakDummy(model, slot)
		end
	end)
	humanoid.Died:Once(function()
		breakDummy(model, slot)
	end)
end

local function onDummyHit(model: Model, info: { [string]: any })
	local data = dummyData[model]
	if not data then
		return
	end
	data.lastHit = os.clock()
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local from = info.position
	if root and root:IsA("BasePart") and typeof(from) == "Vector3" then
		local away = Util.flat(root.Position - from)
		if away.Magnitude > 0.01 then
			data.push = away.Unit
			local localAway = root.CFrame:VectorToObjectSpace(away.Unit)
			local axis = Vector3.yAxis:Cross(localAway)
			if axis.Magnitude > 0.01 then
				data.axis = axis.Unit
			end
		end
	end
	data.wobble = math.min(1, data.wobble * 0.5 + 0.55)
	data.wobbleTime = 0
end

local function updateDummies(dt: number)
	if next(dummyData) == nil then
		return
	end
	local now = os.clock()
	for model, data in pairs(dummyData) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			if now - data.lastHit > (CombatConfig.DummyRegenDelay or 4) and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 1.5 * dt)
			end
			local motor = data.motor
			if motor and data.baseC0 then
				if data.wobble > 0.002 then
					data.wobbleTime += dt
					data.wobble *= math.exp(-3.2 * dt)
					local angle = data.wobble * math.rad(13) * math.sin(data.wobbleTime * 16)
					motor.C0 = data.baseC0 * CFrame.fromAxisAngle(data.axis, angle)
				elseif data.wobble ~= 0 then
					data.wobble = 0
					motor.C0 = data.baseC0
				end
			end
		end
	end
end

local function clearDummies()
	dummiesWanted = false
	for _, slot in ipairs(dummySlots) do
		if slot.model then
			slot.model:Destroy()
		end
		if slot.stand then
			slot.stand:Destroy()
		end
	end
	table.clear(dummySlots)
	table.clear(dummyData)
	if dummyFolder then
		dummyFolder:Destroy()
		dummyFolder = nil
	end
end

local function wantDummies(): boolean
	if not phaseActive() or (not Config.IsStudio and Config.Round.SoloPractice == false) then
		return false
	end
	local practice = GameState:GetAttribute("Practice") == true
	local round = Services.RoundService
	if not practice and round and type(round.isPractice) == "function" then
		practice = round.isPractice() == true
	end
	return practice
end

local function refreshDummies()
	if wantDummies() then
		if not dummiesWanted then
			dummiesWanted = true
			for _, cframe in ipairs(dummyLayout()) do
				local slot: DummySlot = { cframe = cframe, model = nil, stand = nil }
				table.insert(dummySlots, slot)
				spawnDummy(slot)
			end
		end
	elseif dummiesWanted or #dummySlots > 0 then
		clearDummies()
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Hits
--------------------------------------------------------------------------------------------------------------------

function CombatService.applyHit(attacker: Player?, humanoid: Humanoid, baseDamage: number, info: { [string]: any }?): (number, boolean)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then
		return 0, false
	end
	if not Util.isFiniteNumber(baseDamage) or baseDamage <= 0 or not phaseActive() then
		return 0, false
	end
	local model = humanoid.Parent
	if not model or humanoid.Health <= 0 then
		return 0, false
	end
	if attacker ~= nil and (typeof(attacker) ~= "Instance" or not attacker:IsA("Player") or attacker.Parent == nil) then
		attacker = nil -- left the game: no credit, no confirm
	end

	local hit = if type(info) == "table" then table.clone(info) else {}
	hit.attacker = attacker
	hit.cause = hit.cause or "Combat"

	local victim = Players:GetPlayerFromCharacter(model)
	local dealt, killed = 0, false
	if victim then
		if victim == attacker or not isAliveContender(victim) then
			return 0, false
		end
		local multiplier = 1
		local inventory = Services.InventoryService
		if inventory and type(inventory.getArmorMultiplier) == "function" then
			local ok, value = pcall(inventory.getArmorMultiplier, victim)
			if ok and Util.isFiniteNumber(value) then
				multiplier = math.clamp(value, 0, 1)
			end
		end
		local playerService = Services.PlayerService
		if not playerService or type(playerService.damage) ~= "function" then
			return 0, false
		end
		dealt = baseDamage * multiplier
		local ok, result = pcall(playerService.damage, victim, dealt, hit)
		if not ok then
			warn("[CombatService] PlayerService.damage failed: " .. tostring(result))
			return 0, false
		end
		killed = result == true
	else
		local before = humanoid.Health
		humanoid:TakeDamage(baseDamage)
		dealt = math.max(0, before - humanoid.Health)
		killed = humanoid.Health <= 0
		if model:IsA("Model") then
			onDummyHit(model, hit)
		end
	end

	if attacker and dealt > 0 then
		HitConfirm:FireClient(attacker, {
			damage = math.floor(dealt + 0.5),
			headshot = hit.headshot == true,
			killed = killed,
			position = if typeof(hit.hitPosition) == "Vector3" then hit.hitPosition else nil,
			target = if victim then "Player" else "Dummy",
			weaponId = if type(hit.weaponId) == "string" then hit.weaponId else nil,
			melee = hit.melee == true,
		})
	end
	return dealt, killed
end

type MeleeHit = {
	humanoid: Humanoid?,
	model: Model?,
	part: BasePart?,
	position: Vector3,
	normal: Vector3?,
	material: Enum.Material?,
}

-- A forgiving sphere sweep against characters, a point-blank overlap check (Spherecast skips parts that already
-- overlap its start), a line-of-sight check so nobody is hit through a wall, then a thin ray for the world sound.
local function meleeTrace(character: Model, origin: Vector3, direction: Vector3, reach: number, radius: number): MeleeHit?
	local targets = CombatService.getTargets(character)
	local world = worldParams(targets, character)
	if #targets > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = targets
		local candidate: MeleeHit? = nil
		local swept = workspace:Spherecast(origin, radius, direction * reach, params)
		if swept then
			local humanoid, model, bodyPart = CombatService.characterFromPart(swept.Instance)
			if humanoid and humanoid.Health > 0 then
				candidate = { humanoid = humanoid, model = model, part = bodyPart, position = swept.Position }
			end
		end
		if not candidate then
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Include
			overlap.FilterDescendantsInstances = targets
			local bestDistance = math.huge
			for _, part in ipairs(workspace:GetPartBoundsInRadius(origin + direction * radius, radius, overlap)) do
				local humanoid, model, bodyPart = CombatService.characterFromPart(part)
				if humanoid and humanoid.Health > 0 then
					local offset = part.Position - origin
					local distance = offset.Magnitude
					if offset:Dot(direction) > -0.5 and distance < bestDistance then
						bestDistance = distance
						candidate = { humanoid = humanoid, model = model, part = bodyPart, position = part.Position }
					end
				end
			end
		end
		if candidate then
			local offset = candidate.position - origin
			local distance = offset.Magnitude
			local clear = true
			if distance > 0.5 then
				local blocked = workspace:Raycast(origin, offset, world)
				clear = blocked == nil or blocked.Distance >= distance - 0.75
			end
			if clear then
				return candidate
			end
		end
	end
	local result = workspace:Raycast(origin, direction * reach, world)
	if result then
		return { position = result.Position, normal = result.Normal, material = result.Material }
	end
	return nil
end

--------------------------------------------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------------------------------------------

local function onMeleeSwing(player: Player, lookDirection: any)
	if not Net.rateLimit(player, "MeleeSwing", 5, 3) then
		return
	end
	if not Util.isFiniteVector(lookDirection) then
		return
	end
	local magnitude = (lookDirection :: Vector3).Magnitude
	if magnitude < 0.9 or magnitude > 1.1 then
		return
	end
	local direction = (lookDirection :: Vector3) / magnitude
	local ctx = getContext(player)
	if not ctx then
		return
	end
	local def = meleeDefFor(equippedItemId(player))
	if not def or not facingOk(ctx.root, direction, MELEE_FACING_DOT) then
		return
	end
	if not tryCooldown(stateFor(player), "nextSwing", def.cooldown or 0.5, os.clock()) then
		return
	end

	local origin = ctx.head.Position
	local heavy = (def.cooldown or 0) >= HEAVY_SWING_COOLDOWN
	Sfx.play(if heavy then "Swing_Heavy" else "Swing_Light", { position = origin, exclude = player })
	broadcastAction(player, "Swing", def.id)

	local reach = (def.range or 5) + CombatConfig.MeleeLagTolerance
	local hit = meleeTrace(ctx.character, origin, direction, reach, CombatConfig.MeleeHitRadius)
	if not hit then
		return
	end
	if hit.humanoid then
		local dealt = CombatService.applyHit(player, hit.humanoid, def.damage or 0, {
			cause = "Combat",
			weaponId = def.id,
			position = origin,
			hitPosition = hit.position,
			melee = true,
		})
		if dealt > 0 then
			Sfx.play("Hit_Flesh", { position = hit.position, exclude = player })
		end
	else
		Sfx.play(worldHitSound(hit.material), { position = hit.position, exclude = player })
	end
end

local function validOrigin(ctx: Context, origin: any, targets: { Instance }): Vector3
	local head = ctx.head.Position
	if not Util.isFiniteVector(origin) then
		return head
	end
	local offset = (origin :: Vector3) - head
	local speed = math.min(ctx.root.AssemblyLinearVelocity.Magnitude, 80)
	local limit = (CombatConfig.RangedOriginTolerance or 6) + CombatConfig.MeleeLagTolerance + speed * 0.12
	if offset.Magnitude > limit then
		return head
	end
	if offset.Magnitude > 0.5 and workspace:Raycast(head, offset, worldParams(targets, ctx.character)) then
		return head -- the reported origin is on the far side of a wall
	end
	return origin :: Vector3
end

local function onRangedRelease(player: Player, shotId: any, origin: any, direction: any, charge: any, mode: any)
	if not Net.rateLimit(player, "RangedRelease", 8, 4) then
		return
	end
	if mode ~= "Fire" and mode ~= "Throw" and mode ~= "Draw" and mode ~= "Cancel" then
		return
	end
	local ctx = getContext(player)
	if not ctx then
		return
	end
	local st = stateFor(player)
	local now = os.clock()
	local itemId = equippedItemId(player)
	local def = ItemDefs.get(itemId)

	if mode == "Draw" then
		if def and def.kind == "Bow" and hasItem(player, def.ammo or "arrow", 1) then
			st.drawStart = now
			st.drawItem = itemId
			broadcastAction(player, "Draw", itemId)
		end
		return
	elseif mode == "Cancel" then
		if st.drawStart then
			st.drawStart = nil
			broadcastAction(player, "Release", st.drawItem or itemId, true)
		end
		return
	end

	if type(shotId) ~= "string" or #shotId == 0 or #shotId > 40 then
		return
	end
	if not def or not Util.isFiniteVector(direction) then
		return
	end
	local magnitude = (direction :: Vector3).Magnitude
	if magnitude < 0.9 or magnitude > 1.1 then
		return
	end
	local aim = (direction :: Vector3) / magnitude
	if not facingOk(ctx.root, aim, RANGED_FACING_DOT) then
		return
	end
	local projectiles = Services.ProjectileService
	if not projectiles or type(projectiles.fire) ~= "function" then
		return
	end
	local amount = if Util.isFiniteNumber(charge) then math.clamp(charge, 0, 1) else 0
	local start = validOrigin(ctx, origin, CombatService.getTargets(ctx.character))

	if mode == "Fire" then
		if def.kind ~= "Bow" then
			return
		end
		local drawStart = if st.drawItem == itemId and st.drawStart then st.drawStart else st.lastShot
		local maxCharge = math.clamp((now - drawStart + CHARGE_JITTER) / math.max(def.drawTime or 1, 0.05), 0, 1)
		amount = math.min(amount, maxCharge)
		if not tryCooldown(st, "nextShot", BOW_MIN_INTERVAL, now) then
			return
		end
		local ammo = def.ammo or "arrow"
		if not consumeItem(player, ammo, 1) then
			return
		end
		st.drawStart = nil
		st.lastShot = now
		local speed = Util.lerp(def.speedMin or 90, def.speedMax or 240, amount)
		local damage = Util.lerp(def.damageMin or 10, def.damageMax or 40, amount)
		local fired = projectiles.fire(player, ammo, start, aim * speed, def.gravity or 50, damage, {
			shotId = shotId,
			weaponId = itemId,
			headshotMultiplier = def.headshotMultiplier,
			recoverItem = ammo, -- it stays where it ends up (ProjectileService.WorldProjectiles)
		})
		if not fired then
			refund(player, ammo)
			return
		end
		Sfx.play("BowRelease", { position = start, exclude = player })
		broadcastAction(player, "Release", itemId)
		return
	end

	-- Throw
	local speed, gravity, damage
	if def.kind == "Throwable" then
		if not tryCooldown(st, "nextThrow", def.cooldown or 0.5, now) then
			return
		end
		if not consumeItem(player, itemId :: string, 1) then
			return
		end
		speed, gravity, damage = def.speed, def.gravity, def.damage
	elseif def.kind == "Melee" and def.throwable then
		if not tryCooldown(st, "nextThrow", def.cooldown or 0.8, now) then
			return
		end
		local inventory = Services.InventoryService
		if not inventory or type(inventory.removeEquipped) ~= "function" then
			return
		end
		if inventory.removeEquipped(player) ~= itemId then
			return
		end
		speed, gravity, damage = def.throwSpeed, def.throwGravity, def.throwDamage
	else
		return
	end
	local fired = projectiles.fire(player, itemId :: string, start, aim * (speed or 120), gravity or 40, damage or 0, {
		shotId = shotId,
		weaponId = itemId,
		headshotMultiplier = CombatConfig.DefaultHeadshotMultiplier,
		recoverItem = itemId, -- it stays where it ends up, like an arrow
	})
	if not fired then
		refund(player, itemId :: string)
		return
	end
	Sfx.play("Throw", { position = start, exclude = player })
	broadcastAction(player, "Throw", itemId)
end

-- Test hook (Edit-mode checks): the server's melee trace.
CombatService._trace = meleeTrace

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function CombatService.Init(registry)
	Services = registry
	HitConfirm = Net.event("HitConfirm")
	CombatAction = Net.event("CombatAction")
end

function CombatService.Start()
	Net.event("MeleeSwing").OnServerEvent:Connect(onMeleeSwing)
	Net.event("RangedRelease").OnServerEvent:Connect(onRangedRelease)
	Players.PlayerRemoving:Connect(function(player)
		playerState[player] = nil
	end)
	if Config.IsStudio then
		GameState:GetAttributeChangedSignal("Phase"):Connect(refreshDummies)
		GameState:GetAttributeChangedSignal("Practice"):Connect(refreshDummies)
		local round = Services.RoundService
		if round and type(round.roundEnded) == "table" and type(round.roundEnded.Connect) == "function" then
			round.roundEnded:Connect(function()
				clearDummies()
			end)
		end
		RunService.Heartbeat:Connect(updateDummies)
		refreshDummies()
	end
end

return CombatService
