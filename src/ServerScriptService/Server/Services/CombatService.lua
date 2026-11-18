--[[
	CombatService - server-authoritative melee and ranged combat, plus the training dummies of practice rounds.

	Client -> server
	  MeleeSwing("Start", variant: number?) sent when a swing starts: the others near the attacker are told at once
	    (CombatAction "Swing" with lead = the weapon's windup), so they see the swing begin before the blow lands
	  MeleeSwing(lookDirection: Vector3, predictedHit: boolean, variant: number?, target: Model?, startTime: number?)
	    sent at the strike moment of a swing;
	    predictedHit = the attacker's own trace touched someone (CombatController): a swing their screen showed as a miss
	    never lands. variant (optional) = the swing's set, an integer 1-8: passed on to the other clients so they show the
	    same swing (CharacterVisuals); any other value is ignored and the swing goes ahead without it.
	    target (optional) = the body that trace touched: the server checks that one body and no other, so a bystander
	    in the swing's path never takes the hit. startTime (optional) = workspace:GetServerTimeNow() when the swing
	    started on the attacker's client (see trySwing)
	  RangedRelease(shotId, origin, direction, charge, mode)
	    "Fire"   bow shot: consumes 1 arrow; speed and damage scale with charge (capped by the measured draw time).
	             Needs a "Draw" for that bow first; a charge under Config.Combat.MinBowCharge is refused
	    "Throw"  throwing knife (consumes 1) or spear (removes the equipped spear)
	    "Draw"   the bow draw started: the server times the charge and tells other clients (CombatAction "Draw")
	    "Cancel" the draw was let down without shooting
	Server -> client
	  HitConfirm { damage, headshot, killed, position? (hit point), target = "Player" | "Dummy", weaponId?, melee }
	    to the attacker
	  CombatAction { userId, action = "Swing" | "Draw" | "Release" | "Throw", itemId, cancelled?, variant?, lead? }
	    to the other players within ACTION_RANGE studs (variant: a Swing's set, 1-8, when the attacker sent a valid one;
	    lead: seconds from this message to the swing's strike: the windup when sent at the swing's start, 0 when the
	    attacker's client sent no start and the swing is announced at the strike)
	  Sfx: swing, release and impact sounds for the players who can hear them (within the sound's roll-off distance of
	    where they listen from: their character, or the contender they spectate), except the attacker, who plays them
	    locally, instantly

	API
	  CombatService.applyHit(attacker: Player?, humanoid: Humanoid, baseDamage: number, info) -> (damageDealt, killed)
	    info = { cause = "Combat", weaponId = string?, position = Vector3? (where the attack came from),
	             headshot = boolean?, hitPosition = Vector3? }
	    Players: damage * InventoryService.getArmorMultiplier(victim) through PlayerService.damage.
	    Other humanoids (training dummies): Humanoid:TakeDamage. Never yourself, dead players, or outside Active.
	  CombatService.characterFromPart(part) -> (Humanoid?, Model?, BasePart?)   accessories resolve to the body part they're worn on
	  CombatService.getTargets(exclude: Instance?, aliveOnly: boolean?) -> { Model }   every character and training dummy
	    that can be hit; aliveOnly leaves out bodies whose Humanoid is dead (melee: a body that just fell never takes or
	    blocks a swing). Accessory parts are not part of anyone's hit box (CanQuery off, set here as characters load).

	Training dummies: practice rounds only (GameState.Practice), during Active; in Studio, and on live servers while
	Config.Round.SoloPractice is on (PlayabilityPlan QW1).
	Config.Combat.PracticeDummies dummies appear in front of the contender, between the plinths and the Spire, to either
	side of the straight line from the plate to the Spire (that path stays clear), tagged TrainingDummy. They wobble when
	hit, heal after DummyRegenDelay, and respawn DummyRespawnTime after breaking. Their name and health bar keep one size
	on screen (DUMMY_BAR_SIZE) and hide while the contender stands within DUMMY_BAR_HIDE studs, where they would sit on
	the HUD's compass.
	Template: ServerStorage.Dev.TrainingDummy (built by ServerStorage.WorldGen.DummyBuilder).
	Melee cooldown: the same rule as the attacker's client (CombatController: nextActionAt = start + total). The next swing
	may START once the cooldown of the weapon that swung last has passed since that swing started, whatever is in hand
	now (trySwing). Refusals are counted by reason in CombatService._refusals (and printed in Studio).
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
local Sounds = require(Shared:WaitForChild("Sounds"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local CombatConfig = Config.Combat

local DUMMY_TAG = "TrainingDummy"
local DUMMY_BAR_SIZE = Vector2.new(132, 26) -- pixels: a dummy's name and health bar, the same size at any distance
local DUMMY_BAR_HIDE = 8 -- studs (flat): closer than this the contender doesn't see it (shown again half a stud out):
-- above the head of a dummy that near, it sat in the compass band at the top of the view
local FISTS = ItemDefs.get("fists")
local MELEE_FACING_DOT = -0.2 -- flat swing direction vs. character facing; lenient because the server's view lags
-- Melee reach. The attacker's screen shows a hit when CombatController's sphere (MeleeHitRadius * MELEE_PREDICT_RADIUS)
-- swept `range` studs from the first-person camera (MELEE_CAMERA_BEHIND behind the head) touches someone. The server
-- sweeps from the head and reaches MELEE_REACH_ALLOWANCE studs further for latency, plus what the attacker closes in
-- MELEE_LAG_TIME (the server sees a running attacker up to about 0.25 s behind where their screen had them). A target
-- that can move (a player) was on the attacker's screen up to interpolation plus ping ago and may have backed off
-- several studs since, so a hit seen on one is checked out to range + MeleeLagTolerance + MeleeHitRadius. The front
-- never passes that, since the attacker's speed is reported by their own client.
-- MELEE_REACH_ALLOWANCE was 1: with it a sword (range 8) standing still was confirmed on a still target 11 studs away,
-- root to root, a full stud past what an honest client's trace can touch (10). Half a stud keeps the slack for the
-- small difference between the server's head and the client's camera, and 11 is refused whatever the client claims.
local MELEE_PREDICT_RADIUS = 0.85
local MELEE_CAMERA_BEHIND = 0.5
local MELEE_REACH_ALLOWANCE = 0.5
local MELEE_LAG_TIME = 0.25
local RANGED_FACING_DOT = -0.35
local HEAVY_SWING_COOLDOWN = 0.75 -- weapons at least this slow use the heavy swing sound
local BOW_RECOVER = 0.32 -- seconds after a shot before the next draw can begin (CombatController's BOW_RECOVER)
local CHARGE_JITTER = 0.15 -- seconds of draw time forgiven for network jitter (not banked from shot to shot)
local SWING_LATE = 0.35 -- seconds a swing may arrive late and still be timed from when its client says it started
local START_MIN_GAP = 0.3 -- seconds between two swing starts relayed for one attacker
local ACTION_RANGE = 220 -- studs: CombatAction reaches the clients listening this close to the attacker
local SOUND_MARGIN = 30 -- studs past a sound's roll-off distance that still get it (the listener may be moving)

local CombatService = {}

local Services: { [string]: any } = {}
local HitConfirm: RemoteEvent
local CombatAction: RemoteEvent
local SfxRemote: RemoteEvent

type PlayerState = {
	nextSwingStart: number, -- server time (workspace:GetServerTimeNow) from which the next swing may start (trySwing)
	startAt: number?, -- when the last swing start was relayed (MeleeSwing "Start"), and for which weapon
	startItem: string?,
	nextThrow: number,
	bowFree: number, -- os.clock() from which the next draw may count (the last shot + BOW_RECOVER)
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
		st = { nextSwingStart = -math.huge, startAt = nil, startItem = nil, nextThrow = 0, bowFree = 0, drawStart = nil,
			drawItem = nil }
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

-- Melee, the same rule as the attacker's client (CombatController.startMelee: nextActionAt = start + total): the next
-- swing may START once the cooldown of the weapon that swung last has passed since that swing started, whatever is in
-- hand now. (Gating strike to strike by the weapon now in hand refused the first swing after a switch from a quick weapon
-- to a slower one, which the client allows: the attacker saw and heard a hit that never landed, the "ghost swing".)
-- `now` is workspace:GetServerTimeNow() when the strike arrived. The swing started at most `windup` before that; the
-- client's own start time (claimedStart, on the same clock) is believed when it is up to SWING_LATE earlier still, so a
-- strike held up on the way doesn't push the next swing's window back and get that one refused. Nothing is banked: a
-- client that always claims the earliest start gains SWING_LATE once, and its rate stays one swing per cooldown, because
-- an early swing never pulls the next window earlier.
local function trySwing(st: PlayerState, def: any, now: number, claimedStart: any): boolean
	local latest = now - (def.windup or 0.1)
	local start = latest
	if Util.isFiniteNumber(claimedStart) then
		start = math.clamp(claimedStart, latest - SWING_LATE, latest)
	end
	if start < st.nextSwingStart - (CombatConfig.CooldownJitter or 0.12) then
		return false
	end
	st.nextSwingStart = math.max(start, st.nextSwingStart) + (def.cooldown or 0.5)
	return true
end

-- Refusals by reason (a swing or shot the server dropped): read CombatService._refusals; printed in Studio.
local refusals: { [string]: number } = {}
local function refuse(player: Player, reason: string)
	refusals[reason] = (refusals[reason] or 0) + 1
	if Config.IsStudio then
		print(string.format("[CombatService] refused %s from %s (%d so far)", reason, player.Name, refusals[reason]))
	end
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

-- Where a player listens and watches from: the contender they spectate (PlayerService points their ReplicationFocus
-- there), else their own character. nil while they have neither (still loading).
local function listenerPosition(other: Player): Vector3?
	local focus = other.ReplicationFocus
	if focus and focus:IsA("PVInstance") and focus:IsDescendantOf(workspace) then
		return focus:GetPivot().Position
	end
	local character = other.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- A positional sound, sent only to the players who can hear it: within its roll-off distance (Sounds: rollMax) plus
-- SOUND_MARGIN of where they listen from. (Sfx.play sends to every client, the lobby 8,800 studs away included.)
local function playSound(key: string, position: Vector3, exclude: Player?, volume: number?, pitch: number?)
	local entry = (Sounds :: any)[key]
	local range = ((if type(entry) == "table" then tonumber(entry.rollMax) else nil) or 160) + SOUND_MARGIN
	local data = { position = position, volume = volume, pitch = pitch }
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= exclude then
			local at = listenerPosition(other)
			if at and (at - position).Magnitude <= range then
				SfxRemote:FireClient(other, key, data)
			end
		end
	end
end

-- To the other players within ACTION_RANGE of the attacker (everyone else, if the attacker has no body to measure from).
local function broadcastAction(player: Player, action: string, itemId: string?, cancelled: boolean?, variant: number?, lead: number?)
	local payload = { userId = player.UserId, action = action, itemId = itemId or "fists", cancelled = cancelled == true }
	payload.variant = variant -- (a Swing's set, when the attacker sent a valid one)
	payload.lead = lead -- (a Swing: seconds until its strike)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local from = if root and root:IsA("BasePart") then root.Position else nil
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local at = if from then listenerPosition(other) else nil
			if from == nil or (at ~= nil and (at - from).Magnitude <= ACTION_RANGE) then
				CombatAction:FireClient(other, payload)
			end
		end
	end
end

-- A swing's set from MeleeSwing: an integer 1-8, else nil (ignored; the swing itself goes ahead).
local function swingVariant(value: any): number?
	if type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= 8 then
		return value
	end
	return nil
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

local function isLive(model: Instance): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function CombatService.getTargets(exclude: Instance?, aliveOnly: boolean?): { Instance }
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		if character and character ~= exclude and character.Parent and (not aliveOnly or isLive(character)) then
			table.insert(list, character)
		end
	end
	for _, dummy in ipairs(CollectionService:GetTagged(DUMMY_TAG)) do
		if dummy ~= exclude and dummy:IsA("Model") and dummy:IsDescendantOf(workspace) and (not aliveOnly or isLive(dummy)) then
			table.insert(list, dummy)
		end
	end
	return list
end

-- The hit box is the body. Hats, hair, wings, auras and layered clothing took swings and arrows that missed the body (and
-- anything worn on the head counted as a headshot), so accessory parts are left out of every ray and sweep, on the
-- server and (the property replicates) in each client's own trace. Accessory parts never collide, so nothing else changes.
local function bodyOnlyPart(inst: Instance)
	if inst:IsA("BasePart") and inst.CanQuery and inst:FindFirstAncestorWhichIsA("Accessory") then
		inst.CanQuery = false
	end
end

local function watchHitBox(character: Model)
	for _, inst in ipairs(character:GetDescendants()) do
		bodyOnlyPart(inst)
	end
	character.DescendantAdded:Connect(bodyOnlyPart) -- (accessories arrive after the body; gone with the character)
end

local function watchPlayerHitBox(player: Player)
	player.CharacterAdded:Connect(watchHitBox)
	if player.Character then
		watchHitBox(player.Character)
	end
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
	bar: BillboardGui?,
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

-- Dummies stand in a shallow arc a dozen studs in front of the practice contender, toward the Spire, to either side of
-- the straight line from the plate to the Spire (the middle one used to stand on it, in the way of the first sprint).
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
		-- alternate sides: the first pair 6 studs either side of the line (a clear lane about 7 studs wide between their
		-- stands), then 12 studs further out each. (At 7 a dummy's outstretched hand was about a stud off the line from
		-- the plate to the next dummy's chest, and took the swings aimed at that one.)
		local side = if i % 2 == 1 then 1 else -1
		local lateral = side * (6 + 12 * math.floor((i - 1) / 2))
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
		playSound("Hit_Wood", soundAt, nil, 1.3, 0.75)
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
	-- one size on screen at any distance (sized in studs, it filled the top of the view up close, over the compass);
	-- updateDummies hides it while the contender is right in front of the dummy
	if bar and bar:IsA("BillboardGui") then
		bar.Size = UDim2.fromOffset(DUMMY_BAR_SIZE.X, DUMMY_BAR_SIZE.Y)
		local data = dummyData[model]
		if data then
			data.bar = bar
		end
	end
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
	local viewer = practiceContenderRoot()
	for model, data in pairs(dummyData) do
		local bar = data.bar
		local body = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if bar and body and body:IsA("BasePart") then
			local d = if viewer then Util.flat(body.Position - viewer.Position).Magnitude else math.huge
			local hide = d < (if bar.Enabled then DUMMY_BAR_HIDE else DUMMY_BAR_HIDE + 0.5)
			if bar.Enabled == hide then
				bar.Enabled = not hide
			end
		end
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

-- The body a touched part belongs to: a body part or something worn (characterFromPart), or anything else inside one of
-- `targets` (the weapon it holds): a swing that meets the target's sword first still lands on the target.
local function bodyFromPart(part: Instance, targets: { Instance }): (Humanoid?, Model?, BasePart?)
	local humanoid, model, bodyPart = CombatService.characterFromPart(part)
	if humanoid then
		return humanoid, model, bodyPart
	end
	for _, target in ipairs(targets) do
		if part:IsDescendantOf(target) and target:IsA("Model") then
			return target:FindFirstChildOfClass("Humanoid"), target, nil
		end
	end
	return nil, nil, nil
end

-- What the swing lands on. First a thin ray along the look: whoever is under the crosshair, out to the sweep's front.
-- Only when that touches nobody, the forgiving sphere sweep (first body touched), then a point-blank overlap check
-- (Spherecast skips parts that already overlap its start). A line-of-sight check so nobody is hit through a wall, then
-- a thin ray for the world sound. `reach` is the sweep's length: its front is reach + radius from the origin.
-- Only living bodies count (one that just fell neither takes the swing nor blocks it). `only` (the body the attacker's
-- own trace touched): that body is checked and no other, so a bystander in the path never takes the hit.
-- worldOnly skips the characters (the attacker's own trace missed them) and keeps the world sound.
local function meleeTrace(character: Model, origin: Vector3, direction: Vector3, reach: number, radius: number, worldOnly: boolean?, only: Instance?): MeleeHit?
	local world = worldParams(CombatService.getTargets(character), character) -- (no body, living or not, is world)
	local targets = if worldOnly then {} else CombatService.getTargets(character, true)
	if only ~= nil then
		targets = if table.find(targets, only) then { only } else {} -- (it just fell, or was never a target: nobody)
	end
	if #targets > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = targets
		local candidate: MeleeHit? = nil
		local aimed = workspace:Raycast(origin, direction * (reach + radius), params)
		if aimed then
			local humanoid, model, bodyPart = bodyFromPart(aimed.Instance, targets)
			if humanoid and humanoid.Health > 0 then
				candidate = { humanoid = humanoid, model = model, part = bodyPart, position = aimed.Position }
			end
		end
		local swept = if candidate then nil else workspace:Spherecast(origin, radius, direction * reach, params)
		if swept then
			local humanoid, model, bodyPart = bodyFromPart(swept.Instance, targets)
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
				local humanoid, model, bodyPart = bodyFromPart(part, targets)
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

-- Whether a target that can move (a player; training dummies are anchored) is in front of the swing.
local function movableTargetAhead(character: Model, origin: Vector3, direction: Vector3, reach: number, radius: number): boolean
	for _, target in ipairs(CombatService.getTargets(character)) do
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and not root.Anchored then
			local offset = root.Position - origin
			local along = offset:Dot(direction)
			if along > 0 and along < reach + 3 and (offset - direction * along).Magnitude < radius + 3 then
				return true
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------------------------------------------

-- MeleeSwing("Start", variant): a swing began on the attacker's client. The others near them are told now, so they see
-- it wind up before the blow lands (told at the strike, the victim was hurt first and saw the swing afterwards). Cheap:
-- no trace, one small message to the players in range, at most one every START_MIN_GAP per attacker, and not while the
-- swing gate is closed.
local function onMeleeStart(player: Player, variant: any)
	if not Net.rateLimit(player, "MeleeStart", 5, 3) then
		return
	end
	local ctx = getContext(player)
	if not ctx then
		return
	end
	local def = meleeDefFor(equippedItemId(player))
	if not def then
		return
	end
	local st = stateFor(player)
	local now = workspace:GetServerTimeNow()
	if now < st.nextSwingStart - (CombatConfig.CooldownJitter or 0.12) then
		return -- (the strike, if it is accepted after all, announces the swing itself)
	end
	if st.startAt and now - st.startAt < START_MIN_GAP then
		return
	end
	st.startAt = now
	st.startItem = def.id
	broadcastAction(player, "Swing", def.id, nil, swingVariant(variant), def.windup or 0.1)
end

local function onMeleeSwing(player: Player, lookDirection: any, predictedHit: any, variant: any, target: any, startTime: any)
	if lookDirection == "Start" then
		onMeleeStart(player, predictedHit)
		return
	end
	if not Net.rateLimit(player, "MeleeSwing", 5, 3) then
		refuse(player, "MeleeRate")
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
	if not def then
		return
	end
	if not facingOk(ctx.root, direction, MELEE_FACING_DOT) then
		refuse(player, "MeleeFacing")
		return
	end
	local st = stateFor(player)
	local now = workspace:GetServerTimeNow()
	if not trySwing(st, def, now, startTime) then
		refuse(player, "MeleeCooldown")
		return
	end

	local origin = ctx.head.Position
	local heavy = (def.cooldown or 0) >= HEAVY_SWING_COOLDOWN
	playSound(if heavy then "Swing_Heavy" else "Swing_Light", origin, player)
	-- the others saw this swing start (onMeleeStart); if its start never came, they are told now
	local announced = st.startAt ~= nil and st.startItem == def.id and now - st.startAt < (def.windup or 0.1) + 0.6
	st.startAt = nil
	if not announced then
		broadcastAction(player, "Swing", def.id, nil, swingVariant(variant), 0)
	end

	-- a swing the attacker's screen showed as a miss never lands; one it showed hitting is checked by a sweep whose
	-- front (cast length + radius) is MELEE_REACH_ALLOWANCE, plus lag, past the front of the attacker's own
	local range = def.range or 5
	local radius = CombatConfig.MeleeHitRadius
	local maxFront = range + CombatConfig.MeleeLagTolerance + radius
	local closing = ctx.root.AssemblyLinearVelocity:Dot(direction)
	closing = if Util.isFiniteNumber(closing) then math.clamp(closing, 0, Config.Movement.SprintSpeed or 21) else 0
	local front = range + radius * MELEE_PREDICT_RADIUS - MELEE_CAMERA_BEHIND + MELEE_REACH_ALLOWANCE
		+ closing * MELEE_LAG_TIME
	if predictedHit == true and movableTargetAhead(ctx.character, origin, direction, maxFront, radius) then
		front = maxFront
	end
	front = math.min(front, maxFront)
	local claimed = if typeof(target) == "Instance" and target:IsA("Model") then target else nil
	local hit = meleeTrace(ctx.character, origin, direction, math.max(front - radius, 0), radius, predictedHit ~= true, claimed)
	if not hit then
		if predictedHit == true then
			refuse(player, "MeleeNoTarget") -- (the attacker's screen showed a hit; the server found nobody there)
		end
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
			playSound("Hit_Flesh", hit.position, player)
		end
	else
		if predictedHit == true then
			refuse(player, "MeleeNoTarget") -- (the attacker's screen showed a hit; the server found nobody there)
		end
		playSound(worldHitSound(hit.material), hit.position, player)
	end
end

local function validOrigin(ctx: Context, origin: any, targets: { Instance }): Vector3
	local head = ctx.head.Position
	if not Util.isFiniteVector(origin) then
		return head
	end
	local offset = (origin :: Vector3) - head
	local speed = math.min(ctx.root.AssemblyLinearVelocity.Magnitude, 80)
	-- The honest origin is the eye, under 2 studs from the head, plus what the body moved while the message travelled.
	-- A shot that claims to start further from where the server sees the attacker starts at their head instead: 3 studs
	-- standing still, more with speed, never more than the old allowance (9 studs at rest let a shot start round a corner).
	local limit = math.min(3 + speed * 0.2, (CombatConfig.RangedOriginTolerance or 6) + CombatConfig.MeleeLagTolerance + speed * 0.12)
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
			st.drawItem = nil
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
		-- An arrow's power comes from a real draw of this bow: the "Draw" the client sent when the string came back
		-- (cleared by a shot, a let-down or a weapon switch). Without one there is no shot. (Measured from the last
		-- shot instead, a client that never sent Draw had a full-power arrow the instant it equipped the bow, and
		-- half power every 0.3 s.) The draw counts from the later of that message and BOW_RECOVER after the last shot
		-- (bowFree), with CHARGE_JITTER forgiven for the network; a shot that used the forgiveness counts as loosed
		-- when its charge was really reached, so the forgiveness is never banked from shot to shot.
		local drawStart = if st.drawItem == itemId then st.drawStart else nil
		st.drawStart = nil -- (each shot needs its own draw)
		if not drawStart then
			refuse(player, "BowNoDraw")
			return
		end
		local drawTime = math.max(def.drawTime or 1, 0.05)
		local began = math.max(drawStart, st.bowFree)
		amount = math.min(amount, math.clamp((now - began + CHARGE_JITTER) / drawTime, 0, 1))
		if amount < (CombatConfig.MinBowCharge or 0.2) - 1e-3 then
			refuse(player, "BowCharge")
			broadcastAction(player, "Release", itemId, true) -- (the others stop hearing the draw)
			return
		end
		local ammo = def.ammo or "arrow"
		if not consumeItem(player, ammo, 1) then
			broadcastAction(player, "Release", itemId, true)
			return
		end
		st.bowFree = math.max(now, began + amount * drawTime) + BOW_RECOVER
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
		playSound("BowRelease", start, player)
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
	playSound("Throw", start, player)
	broadcastAction(player, "Throw", itemId)
end

-- A draw doesn't outlive the bow in hand: switching away and back gave a full-power arrow at once.
local function onEquippedChanged(player: Player)
	local st = playerState[player]
	if st and st.drawStart then
		local was = st.drawItem
		st.drawStart = nil
		st.drawItem = nil
		broadcastAction(player, "Release", was, true)
	end
end

-- Test hooks (server only): the server's melee trace, the check on MeleeSwing's variant, the swing gate, and the count
-- of refused swings and shots by reason.
CombatService._trace = meleeTrace
CombatService._swingVariant = swingVariant
CombatService._trySwing = trySwing
CombatService._refusals = refusals

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function CombatService.Init(registry)
	Services = registry
	HitConfirm = Net.event("HitConfirm")
	CombatAction = Net.event("CombatAction")
	SfxRemote = Net.event("Sfx")
end

function CombatService.Start()
	Net.event("MeleeSwing").OnServerEvent:Connect(onMeleeSwing)
	Net.event("RangedRelease").OnServerEvent:Connect(onRangedRelease)
	Players.PlayerRemoving:Connect(function(player)
		playerState[player] = nil
	end)
	Players.PlayerAdded:Connect(watchPlayerHitBox)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayerHitBox(player)
	end
	local inventory = Services.InventoryService
	if inventory and type(inventory.equippedChanged) == "table" and type(inventory.equippedChanged.Connect) == "function" then
		inventory.equippedChanged:Connect(onEquippedChanged)
	end
	-- Training dummies come and go with practice rounds, in Studio and on live servers alike (wantDummies decides);
	-- updateDummies returns at once while there are none.
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

return CombatService
