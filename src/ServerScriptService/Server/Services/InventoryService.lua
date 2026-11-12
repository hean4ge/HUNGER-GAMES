--[[
	InventoryService - every player's inventory. The server is the only source of truth.
	  slots[1..Config.Inventory.Slots] = { id, count } | false, an equipped slot (0 = fists) and worn armor ("" = none).

	API (docs/GameDesign.md section 8)
	  give(player, itemId, count) -> number added   tops up stacks (def.stack), then fills empty slots; 0 unless the player
	                                                is an alive contender (the lobby inventory is always empty)
	  take(player, itemId, count) -> boolean        all or nothing; stacks you aren't holding are used first
	  consume(...)                                  same as take
	  has(player, itemId, count) -> boolean         count(player, itemId) -> number
	  getEquipped(player) -> (itemId?, slot)        (nil, 0) = fists
	  removeEquipped(player) -> itemId?             removes one of the held item (a thrown spear)
	  getArmorMultiplier(player) -> number          the worn armor's damageMultiplier (1 = no armor)
	  clear(player)                                 empty everything, no drops
	  dropAll(player, position)                     every stack and the worn armor scatter as ground items around position
	Extras: equip(player, slot); getSnapshot(player) -> InventoryUpdate payload;
	        changed: Signal(player); equippedChanged: Signal(player, itemId?, slot)

	Remotes (validated, rate-limited; only alive contenders can use items):
	  EquipSlot(0..Slots)  an empty slot means fists
	  DropSlot(slot, count?) the stack (or `count` of it: a tap on Drop sends 1) is tossed in front of you
	                       (LootService.spawnGroundItem); never lost
	  UseStart / UseFinish / UseCancel(slot)   server-timed: UseFinish counts only for the equipped slot started at least
	                       useTime - Config.Inventory.UseFinishTolerance earlier with the item still there. Food, drink and
	                       healing go through PlayerService (addHunger / addThirst / heal); armor is worn (Player.Armor,
	                       the previous armor goes back into the slot); "becomes" items stay in hand (water -> empty bottle)
	  Drink()              needs terrain water within Config.Survival.DrinkRange of the head (raycasts with IgnoreWater =
	                       false, then Terrain:ReadVoxels); +DrinkPerSip thirst, or fills a held empty bottle; one sip per
	                       Config.Survival.DrinkSipTime
	  InventoryUpdate { slots (false = empty), equipped, armor } goes to the owner after every change and on spawn.

	Visuals: the equipped item's "world" model is welded to the character's RightHand (Grip on RightGripAttachment) as
	  Character.EquippedModel (attribute ItemId); the character's EquippedItem attribute is the id or "".
	  Melee weapons and throwables also play Roblox's R15 "toolnone" hold pose (right arm raised, Idle priority) so the
	  blade points forward like a held Tool; the bow, food, bottles, kits and armor hang naturally from the hand.
	Attributes: Player.Armor (worn armor id or ""), Player.UsingItem (item being used or "").
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Signal = require(Shared:WaitForChild("Signal"))
local Util = require(Shared:WaitForChild("Util"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local InvCfg = Config.Inventory
local Survival = Config.Survival
local SLOTS = InvCfg.Slots or 6

local InventoryService = {}
InventoryService.changed = Signal.new()
InventoryService.equippedChanged = Signal.new()
-- (player, itemId?, kind) a use finished ("Food" | "Drink" | "Heal" | "Armor"), a sip of water ("Sip", no item) or a
-- bottle filled ("Fill"). OnboardingService counts "ate or drank" from it.
InventoryService.used = Signal.new()

local Services: { [string]: any } = {}
local InventoryUpdate: RemoteEvent
local rng = Random.new()

type Slot = { id: string, count: number }
type Use = { slot: number, itemId: string, startedAt: number }
type Inventory = {
	slots: { any },
	equipped: number,
	armor: string,
	use: Use?,
	lastDrink: number,
	model: Model?,
	modelItemId: string?,
	modelCharacter: Model?,
	sendPending: boolean,
	equipKey: string,
	charConnections: { RBXScriptConnection },
	lastToast: number,
	holdTrack: AnimationTrack?,
	holdCharacter: Model?,
}

local inventories: { [Player]: Inventory } = {}

local HOLD_POSE_KINDS = { Melee = true, Throwable = true }
local holdAnimation = Instance.new("Animation")
holdAnimation.Name = "HoldPose"
holdAnimation.AnimationId = "rbxassetid://507768375" -- Roblox's R15 "toolnone": right arm raised to hold an item

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function newInventory(): Inventory
	return {
		slots = table.create(SLOTS, false),
		equipped = 0,
		armor = "",
		use = nil,
		lastDrink = 0,
		model = nil,
		modelItemId = nil,
		modelCharacter = nil,
		sendPending = false,
		equipKey = "0:",
		charConnections = {},
		lastToast = 0,
		holdTrack = nil,
		holdCharacter = nil,
	}
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function getInventory(player: Player): Inventory?
	local inv = inventories[player]
	if not inv and isPlayer(player) and player.Parent == Players then
		inv = newInventory()
		inventories[player] = inv
	end
	return inv
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

local function isAliveContender(player: Player): boolean
	if not isPlayer(player) or player.Parent ~= Players then
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

local function inRound(): boolean
	local phase = getPhase()
	return phase == "Countdown" or phase == "Active"
end

-- Integer slot index from a remote argument, or nil.
local function toSlot(value: any, allowZero: boolean): number?
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		return nil
	end
	if value < (if allowZero then 0 else 1) or value > SLOTS then
		return nil
	end
	return value
end

local function equippedEntry(inv: Inventory): Slot?
	if inv.equipped == 0 then
		return nil
	end
	local entry = inv.slots[inv.equipped]
	return if entry then entry else nil
end

local function countIn(inv: Inventory, itemId: string): number
	local total = 0
	for i = 1, SLOTS do
		local s = inv.slots[i]
		if s and s.id == itemId then
			total += s.count
		end
	end
	return total
end

local function hasAnything(inv: Inventory): boolean
	if inv.armor ~= "" then
		return true
	end
	for i = 1, SLOTS do
		if inv.slots[i] then
			return true
		end
	end
	return false
end

-- Puts items into stacks / free slots (no checks, no auto-equip). Returns how many didn't fit.
local function place(inv: Inventory, itemId: string, count: number): number
	local def = ItemDefs.get(itemId)
	if not def then
		return count
	end
	local stack = math.max(1, math.floor(def.stack or 1))
	local remaining = count
	for i = 1, SLOTS do
		if remaining <= 0 then
			break
		end
		local s = inv.slots[i]
		if s and s.id == itemId and s.count < stack then
			local add = math.min(stack - s.count, remaining)
			s.count += add
			remaining -= add
		end
	end
	for i = 1, SLOTS do
		if remaining <= 0 then
			break
		end
		if not inv.slots[i] then
			local add = math.min(stack, remaining)
			inv.slots[i] = { id = itemId, count = add }
			remaining -= add
		end
	end
	return remaining
end

local function toast(player: Player, inv: Inventory, text: string)
	local now = os.clock()
	if now - inv.lastToast < 1.2 then
		return
	end
	inv.lastToast = now
	Net.event("Announce"):FireClient(player, { style = "Toast", text = text, duration = 1.6 })
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Something that didn't fit anywhere (armor swap, filled bottle) lands at the player's feet.
local function dropNear(player: Player, itemId: string, count: number)
	local root = rootOf(player)
	local loot = Services.LootService
	if not root or not loot or type(loot.spawnGroundItem) ~= "function" then
		warn(string.format("[InventoryService] no room for %d %s and nowhere to drop it", count, itemId))
		return
	end
	local look = Util.flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local ok, err = pcall(loot.spawnGroundItem, itemId, count, root.Position + look * 1.5, look * 4 + Vector3.new(0, 8, 0))
	if not ok then
		warn("[InventoryService] spawnGroundItem failed: " .. tostring(err))
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Snapshots, equip visuals, commit
--------------------------------------------------------------------------------------------------------------------

local function snapshot(inv: Inventory)
	local slots = table.create(SLOTS, false)
	for i = 1, SLOTS do
		local s = inv.slots[i]
		slots[i] = if s then { id = s.id, count = s.count } else false
	end
	return { slots = slots, equipped = inv.equipped, armor = inv.armor }
end

local function sendSnapshot(player: Player)
	local inv = inventories[player]
	if inv and player.Parent == Players then
		InventoryUpdate:FireClient(player, snapshot(inv))
	end
end

-- One snapshot per frame however many changes an action makes.
local function scheduleSnapshot(player: Player, inv: Inventory)
	if inv.sendPending then
		return
	end
	inv.sendPending = true
	task.defer(function()
		inv.sendPending = false
		sendSnapshot(player)
	end)
end

local function setUse(player: Player, inv: Inventory, use: Use?)
	inv.use = use
	local value = if use then use.itemId else ""
	if player.Parent == Players and player:GetAttribute("UsingItem") ~= value then
		player:SetAttribute("UsingItem", value)
	end
end

local function destroyModel(inv: Inventory)
	if inv.model then
		inv.model:Destroy()
	end
	inv.model = nil
	inv.modelItemId = nil
	inv.modelCharacter = nil
end

-- Right arm raised (one cached track per character, so re-equipping never piles up AnimationTracks).
local function setHoldPose(inv: Inventory, character: Model?, on: boolean)
	if inv.holdCharacter ~= character then
		inv.holdTrack = nil
		inv.holdCharacter = character
	end
	local track = inv.holdTrack
	if not on then
		if track and track.IsPlaying then
			track:Stop(0.25)
		end
		return
	end
	if not character then
		return
	end
	if not track then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local ok, loaded = pcall(function()
			return (animator :: Animator):LoadAnimation(holdAnimation)
		end)
		if not ok or not loaded then
			return
		end
		track = loaded
		loaded.Priority = Enum.AnimationPriority.Idle
		loaded.Looped = true
		inv.holdTrack = loaded
	end
	if track and not track.IsPlaying then
		track:Play(0.2)
	end
end

-- Builds and welds the held item; returns its def when attached.
local function attachModel(inv: Inventory, character: Model, itemId: string): any
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not (hand and hand:IsA("BasePart")) then
		return nil
	end
	local ok, model = pcall(ItemModels.build, itemId, "world")
	if not ok or not model then
		return nil
	end
	local handle = model.PrimaryPart
	if not handle then
		model:Destroy()
		return nil
	end
	local grip = handle:FindFirstChild("Grip")
	local handGrip = hand:FindFirstChild("RightGripAttachment")
	local c0 = if handGrip and handGrip:IsA("Attachment")
		then handGrip.CFrame
		else CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	local c1 = if grip and grip:IsA("Attachment") then grip.CFrame else CFrame.identity
	model.Name = "EquippedModel"
	model:SetAttribute("ItemId", itemId)
	model:PivotTo(hand.CFrame * c0 * c1:Inverse())
	local weld = Instance.new("Weld")
	weld.Name = "GripWeld"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = c0
	weld.C1 = c1
	weld.Parent = handle
	model.Parent = character
	inv.model = model
	inv.modelItemId = itemId
	inv.modelCharacter = character
	return ItemDefs.get(itemId)
end

-- The held item, welded to the right hand (Grip aligned to RightGripAttachment), plus the hold pose.
local function refreshModel(player: Player, inv: Inventory)
	local character = player.Character
	local entry = equippedEntry(inv)
	local itemId = if entry then entry.id else nil
	if inv.model and inv.model.Parent and inv.modelItemId == itemId and inv.modelCharacter == character then
		return
	end
	destroyModel(inv)
	if character and character.Parent then
		character:SetAttribute("EquippedItem", itemId or "")
	end
	local def = if itemId and character then attachModel(inv, character, itemId) else nil
	setHoldPose(inv, character, def ~= nil and HOLD_POSE_KINDS[def.kind] == true)
end

-- Every mutation ends here: normalise, keep visuals / attributes in sync, notify, queue a snapshot.
local function commit(player: Player, inv: Inventory)
	for i = 1, SLOTS do
		local s = inv.slots[i]
		if s and (s.count <= 0 or ItemDefs.get(s.id) == nil) then
			inv.slots[i] = false
		end
	end
	if inv.equipped ~= 0 and not inv.slots[inv.equipped] then
		inv.equipped = 0
	end
	local use = inv.use
	if use then
		local s = inv.slots[use.slot]
		if not s or s.id ~= use.itemId or inv.equipped ~= use.slot then
			setUse(player, inv, nil)
		end
	end
	if player.Parent == Players and player:GetAttribute("Armor") ~= inv.armor then
		player:SetAttribute("Armor", inv.armor)
	end
	refreshModel(player, inv)
	local entry = equippedEntry(inv)
	local key = tostring(inv.equipped) .. ":" .. (if entry then entry.id else "")
	if key ~= inv.equipKey then
		inv.equipKey = key
		InventoryService.equippedChanged:Fire(player, if entry then entry.id else nil, inv.equipped)
	end
	InventoryService.changed:Fire(player)
	scheduleSnapshot(player, inv)
end

--------------------------------------------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------------------------------------------

function InventoryService.give(player: Player, itemId: string, count: number?): number
	if type(itemId) ~= "string" then
		return 0
	end
	local def = ItemDefs.get(itemId)
	if not def or def.hidden then
		return 0
	end
	local n = math.floor(tonumber(count) or 1)
	if n <= 0 or not isAliveContender(player) then
		return 0
	end
	local inv = getInventory(player)
	if not inv then
		return 0
	end
	local wasEmpty = table.create(SLOTS, false)
	for i = 1, SLOTS do
		wasEmpty[i] = not inv.slots[i]
	end
	local added = n - place(inv, itemId, n)
	if added <= 0 then
		return 0
	end
	if inv.equipped == 0 and InvCfg.AutoEquipWeapons ~= false and ItemDefs.isWeapon(itemId) then
		for i = 1, SLOTS do
			local s = inv.slots[i]
			if wasEmpty[i] and s and s.id == itemId then
				inv.equipped = i -- grabbed a weapon with empty hands: it goes straight into your hand
				break
			end
		end
	end
	commit(player, inv)
	return added
end

function InventoryService.take(player: Player, itemId: string, count: number?): boolean
	local n = math.floor(tonumber(count) or 1)
	if n <= 0 then
		return true
	end
	local inv = inventories[player]
	if not inv or type(itemId) ~= "string" or countIn(inv, itemId) < n then
		return false
	end
	local remaining = n
	local function drain(i: number)
		local s = inv.slots[i]
		if remaining > 0 and s and s.id == itemId then
			local used = math.min(s.count, remaining)
			s.count -= used
			remaining -= used
			if s.count <= 0 then
				inv.slots[i] = false
			end
		end
	end
	for i = SLOTS, 1, -1 do
		if i ~= inv.equipped then
			drain(i)
		end
	end
	if inv.equipped ~= 0 then
		drain(inv.equipped)
	end
	commit(player, inv)
	return true
end

InventoryService.consume = InventoryService.take

function InventoryService.has(player: Player, itemId: string, count: number?): boolean
	local inv = inventories[player]
	if not inv or type(itemId) ~= "string" then
		return false
	end
	return countIn(inv, itemId) >= math.max(1, math.floor(tonumber(count) or 1))
end

function InventoryService.count(player: Player, itemId: string): number
	local inv = inventories[player]
	if not inv or type(itemId) ~= "string" then
		return 0
	end
	return countIn(inv, itemId)
end

function InventoryService.getEquipped(player: Player): (string?, number)
	local inv = inventories[player]
	local entry = inv and equippedEntry(inv)
	if not inv or not entry then
		return nil, 0
	end
	return entry.id, inv.equipped
end

function InventoryService.removeEquipped(player: Player): string?
	local inv = inventories[player]
	local entry = inv and equippedEntry(inv)
	if not inv or not entry then
		return nil
	end
	local itemId = entry.id
	entry.count -= 1
	if entry.count <= 0 then
		inv.slots[inv.equipped] = false
	end
	commit(player, inv)
	return itemId
end

function InventoryService.getArmorMultiplier(player: Player): number
	local inv = inventories[player]
	if not inv or inv.armor == "" then
		return 1
	end
	local def = ItemDefs.get(inv.armor)
	local multiplier = def and tonumber(def.damageMultiplier)
	if not multiplier or multiplier ~= multiplier then
		return 1
	end
	return math.clamp(multiplier, 0, 1)
end

function InventoryService.clear(player: Player)
	local inv = inventories[player]
	if not inv then
		return
	end
	for i = 1, SLOTS do
		inv.slots[i] = false
	end
	inv.equipped = 0
	inv.armor = ""
	setUse(player, inv, nil)
	commit(player, inv)
end

function InventoryService.dropAll(player: Player, position: Vector3?)
	local inv = inventories[player]
	if not inv then
		return
	end
	-- empty the inventory first: whatever happens below, nothing can be duplicated
	local drops = {}
	for i = 1, SLOTS do
		local s = inv.slots[i]
		if s then
			table.insert(drops, { id = s.id, count = s.count })
			inv.slots[i] = false
		end
	end
	if inv.armor ~= "" then
		table.insert(drops, { id = inv.armor, count = 1 })
		inv.armor = ""
	end
	inv.equipped = 0
	setUse(player, inv, nil)
	commit(player, inv)
	if #drops == 0 then
		return
	end
	local origin: Vector3? = if Util.isFiniteVector(position) then position else nil
	if not origin then
		local root = rootOf(player)
		origin = if root then root.Position else nil
	end
	local loot = Services.LootService
	if not origin or not loot or type(loot.spawnGroundItem) ~= "function" then
		warn(string.format("[InventoryService] couldn't drop %d stacks for %s", #drops, player.Name))
		return
	end
	local scatter = Config.Loot.DeathDropScatter or 3
	local gravity = Config.Loot.TossGravity or 70
	local start = (origin :: Vector3) + Vector3.new(0, 1.2, 0)
	local turn = rng:NextNumber(0, math.pi * 2)
	for i, drop in ipairs(drops) do
		local angle = turn + (i / #drops) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local up = rng:NextNumber(9, 12)
		local flight = (up + math.sqrt(up * up + 2 * gravity * 4.2)) / gravity -- about the time to reach the ground
		local speed = scatter * rng:NextNumber(0.45, 1) / flight
		local velocity = Vector3.new(math.cos(angle) * speed, up, math.sin(angle) * speed)
		local ok, err = pcall(loot.spawnGroundItem, drop.id, drop.count, start, velocity)
		if not ok then
			warn("[InventoryService] dropAll spawnGroundItem failed: " .. tostring(err))
		end
	end
end

function InventoryService.equip(player: Player, slot: number)
	local inv = inventories[player]
	local s = toSlot(slot, true)
	if not inv or s == nil then
		return
	end
	if s ~= 0 and not inv.slots[s] then
		s = 0
	end
	if inv.equipped == s then
		scheduleSnapshot(player, inv) -- confirms the client's prediction
		return
	end
	inv.equipped = s
	setUse(player, inv, nil)
	commit(player, inv)
end

function InventoryService.getSnapshot(player: Player)
	local inv = inventories[player]
	return snapshot(inv or newInventory())
end

--------------------------------------------------------------------------------------------------------------------
-- Using items
--------------------------------------------------------------------------------------------------------------------

-- PlayerService.addHunger / addThirst / heal, with plain fallbacks so items still work without it.
local function survival(method: string, player: Player, amount: number)
	local playerService = Services.PlayerService
	local fn = playerService and playerService[method]
	if type(fn) == "function" then
		local ok, err = pcall(fn, player, amount)
		if not ok then
			warn(string.format("[InventoryService] PlayerService.%s failed: %s", method, tostring(err)))
		end
		return
	end
	if method == "heal" then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
		end
	else
		local attribute = if method == "addHunger" then "Hunger" else "Thirst"
		local current = tonumber(player:GetAttribute(attribute)) or 100
		player:SetAttribute(attribute, math.clamp(current + amount, 0, 100))
	end
end

local function applyUse(player: Player, inv: Inventory, slot: number, entry: Slot, def: any)
	local root = rootOf(player)
	if def.kind == "Armor" then
		local previous = inv.armor
		inv.armor = def.id
		entry.count -= 1
		if entry.count <= 0 then
			inv.slots[slot] = false
		end
		if previous ~= "" and previous ~= def.id then
			-- the armor you took off goes where the new one came from
			if not inv.slots[slot] then
				inv.slots[slot] = { id = previous, count = 1 }
			elseif place(inv, previous, 1) > 0 then
				dropNear(player, previous, 1)
			end
		end
		if root then
			Sfx.play(def.useSound or "ArmorOn", { position = root.Position, exclude = player })
		end
	else
		if def.hunger then
			survival("addHunger", player, def.hunger)
		end
		if def.thirst then
			survival("addThirst", player, def.thirst)
		end
		if def.heal then
			survival("heal", player, def.heal)
		end
		entry.count -= 1
		if entry.count <= 0 then
			inv.slots[slot] = false
		end
		local becomes = def.becomes and ItemDefs.get(def.becomes)
		if becomes then
			if not inv.slots[slot] then
				inv.slots[slot] = { id = becomes.id, count = 1 } -- stays in your hand
			elseif place(inv, becomes.id, 1) > 0 then
				dropNear(player, becomes.id, 1)
			end
		end
	end
	commit(player, inv)
	InventoryService.used:Fire(player, def.id, def.kind)
end

local function onUseStart(player: Player, slot: any)
	if not Net.rateLimit(player, "UseStart", 6, 6) then
		return
	end
	local s = toSlot(slot, false)
	local inv = inventories[player]
	if not s or not inv or inv.equipped ~= s or not isAliveContender(player) then
		return
	end
	local entry = inv.slots[s]
	if not entry or not ItemDefs.isConsumable(entry.id) then
		return
	end
	local def = ItemDefs.get(entry.id)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if def.kind == "Armor" and inv.armor == entry.id then
		toast(player, inv, "You're already wearing it")
		return
	end
	if def.kind == "Heal" and humanoid and humanoid.Health >= humanoid.MaxHealth - 0.5 then
		toast(player, inv, "You're not hurt")
		return
	end
	-- QW12: no eating when full or drinking when not thirsty (the client says so first)
	local fullAt = tonumber(InvCfg.FullAt) or 95
	if def.kind == "Food" and (tonumber(player:GetAttribute("Hunger")) or 0) >= fullAt then
		toast(player, inv, "You're full")
		return
	end
	if def.kind == "Drink" and (tonumber(player:GetAttribute("Thirst")) or 0) >= fullAt then
		toast(player, inv, "You're not thirsty")
		return
	end
	setUse(player, inv, { slot = s, itemId = entry.id, startedAt = os.clock() })
	local root = rootOf(player)
	if root and def.useSound and def.kind ~= "Armor" then
		Sfx.play(def.useSound, { position = root.Position, exclude = player }) -- others hear you eat or bandage
	end
end

local function onUseFinish(player: Player, slot: any)
	if not Net.rateLimit(player, "UseFinish", 6, 6) then
		return
	end
	local s = toSlot(slot, false)
	local inv = inventories[player]
	if not s or not inv then
		return
	end
	local use = inv.use
	if not use or use.slot ~= s then
		scheduleSnapshot(player, inv) -- resync a client that thinks it was using something
		return
	end
	setUse(player, inv, nil)
	local entry = inv.slots[s]
	local def = ItemDefs.get(use.itemId)
	if not entry or entry.id ~= use.itemId or inv.equipped ~= s or not def or not isAliveContender(player) then
		scheduleSnapshot(player, inv)
		return
	end
	local useTime = tonumber(def.useTime) or 1
	if os.clock() - use.startedAt < useTime - (InvCfg.UseFinishTolerance or 0.25) then
		scheduleSnapshot(player, inv)
		return
	end
	applyUse(player, inv, s, entry, def)
end

local function onUseCancel(player: Player, slot: any)
	if not Net.rateLimit(player, "UseCancel", 8, 8) then
		return
	end
	local inv = inventories[player]
	if inv and inv.use then
		local s = toSlot(slot, true)
		if s == nil or s == 0 or s == inv.use.slot then
			setUse(player, inv, nil)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Drinking
--------------------------------------------------------------------------------------------------------------------

local DRINK_RAYS: { Vector3 } = {}
do
	for i = 0, 7 do
		local angle = i * math.pi / 4
		for _, pitch in ipairs({ math.rad(-30), math.rad(-60) }) do
			table.insert(DRINK_RAYS, Vector3.new(math.cos(angle) * math.cos(pitch), math.sin(pitch), math.sin(angle) * math.cos(pitch)))
		end
	end
	table.insert(DRINK_RAYS, Vector3.new(0, -1, 0))
end

local function nearWater(character: Model, head: BasePart): boolean
	local range = (Survival.DrinkRange or 9) + 1.5 -- a little slack for latency and the camera sitting ahead of the head
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = false
	local origin = head.Position
	local function waterAlong(direction: Vector3): boolean
		local result = workspace:Raycast(origin, direction * range, params)
		return result ~= nil and result.Material == Enum.Material.Water
	end
	local look = head.CFrame.LookVector
	if waterAlong(look) or waterAlong((look - Vector3.new(0, 0.6, 0)).Unit) then
		return true
	end
	for _, direction in ipairs(DRINK_RAYS) do
		if waterAlong(direction) then
			return true
		end
	end
	-- swimming or wading (rays that start in water don't report it): look for water voxels around the head
	local region = Region3.new(origin - Vector3.new(range, range, range), origin + Vector3.new(range, 2, range)):ExpandToGrid(4)
	local ok, materials, occupancies = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if ok and materials and occupancies then
		local size = materials.Size
		local corner = region.CFrame.Position - region.Size / 2
		for x = 1, size.X do
			for y = 1, size.Y do
				for z = 1, size.Z do
					if materials[x][y][z] == Enum.Material.Water and occupancies[x][y][z] > 0.05 then
						local center = corner + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * 4
						if (center - origin).Magnitude <= range + 2 then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

local function onDrink(player: Player)
	if not Net.rateLimit(player, "Drink", 4, 4) then
		return
	end
	local inv = inventories[player]
	if not inv or not inRound() or not isAliveContender(player) then
		return
	end
	local now = os.clock()
	if now - inv.lastDrink < (Survival.DrinkSipTime or 0.7) - 0.15 then
		return
	end
	local character = player.Character :: Model
	local head = character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) or not nearWater(character, head) then
		return
	end
	inv.lastDrink = now
	local entry = equippedEntry(inv)
	local def = entry and ItemDefs.get(entry.id)
	local filled = def and def.fillsInto and ItemDefs.get(def.fillsInto)
	if entry and filled then
		entry.count -= 1
		if entry.count <= 0 then
			inv.slots[inv.equipped] = { id = filled.id, count = 1 } -- the full bottle stays in your hand
		elseif place(inv, filled.id, 1) > 0 then
			dropNear(player, filled.id, 1)
		end
		setUse(player, inv, nil)
		commit(player, inv)
		Sfx.play("WaterSplash", { position = head.Position, volume = 0.5, exclude = player })
		InventoryService.used:Fire(player, filled.id, "Fill")
		return
	end
	survival("addThirst", player, Survival.DrinkPerSip or 10)
	Sfx.play("Drink", { position = head.Position, exclude = player })
	InventoryService.used:Fire(player, nil, "Sip")
end

--------------------------------------------------------------------------------------------------------------------
-- Equip and drop remotes
--------------------------------------------------------------------------------------------------------------------

local function onEquipSlot(player: Player, slot: any)
	local rate = InvCfg.EquipRequestsPerSecond or 20
	if not Net.rateLimit(player, "EquipSlot", rate, rate) then
		return
	end
	if toSlot(slot, true) == nil then
		return
	end
	InventoryService.equip(player, slot)
end

local function onDropSlot(player: Player, slot: any, count: any)
	if not Net.rateLimit(player, "DropSlot", 5, 6) then
		return
	end
	local s = toSlot(slot, false)
	local inv = inventories[player]
	if not s or not inv then
		return
	end
	local entry = inv.slots[s]
	if not entry or not inRound() or not isAliveContender(player) then
		return
	end
	local character = player.Character :: Model
	local root = rootOf(player)
	local loot = Services.LootService
	if not root or not loot or type(loot.spawnGroundItem) ~= "function" then
		return
	end
	-- QW12: a count drops part of the stack (a tap on Drop drops one); none, or all of it, drops the whole stack
	local n = entry.count
	if type(count) == "number" and count == count and count % 1 == 0 and count >= 1 and count < entry.count then
		n = count
	end
	local partial = n < entry.count
	if partial then
		entry.count -= n
	else
		inv.slots[s] = false
	end
	commit(player, inv)
	local look = Util.flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local origin = root.Position + Vector3.new(0, 0.8, 0)
	local start = origin + look * 1.6
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local wall = workspace:Raycast(origin, look * 1.6, params)
	if wall then
		start = wall.Position - look * 0.45 -- don't toss it through a wall you're facing
	end
	local velocity = look * (InvCfg.DropForwardSpeed or 8) + Vector3.new(0, InvCfg.DropUpSpeed or 10, 0)
	local ok, model = pcall(loot.spawnGroundItem, entry.id, n, start, velocity)
	if not ok or not model then
		-- nothing is ever lost: nothing yielded since we took them out, so they still fit
		if partial then
			entry.count += n
		elseif not inv.slots[s] then
			inv.slots[s] = entry
		else
			place(inv, entry.id, entry.count)
		end
		commit(player, inv)
		if not ok then
			warn("[InventoryService] DropSlot spawnGroundItem failed: " .. tostring(model))
		end
		return
	end
	Sfx.playFor(player, "Drop")
end

--------------------------------------------------------------------------------------------------------------------
-- Players and characters
--------------------------------------------------------------------------------------------------------------------

local function onDied(player: Player, character: Model)
	local inv = inventories[player]
	if not inv then
		return
	end
	setUse(player, inv, nil)
	if inv.modelCharacter == character then
		destroyModel(inv)
	end
	if inv.holdCharacter == character then
		setHoldPose(inv, character, false)
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else nil
	-- PlayerService drops the inventory itself on death; this deferred pass only catches anything it missed
	task.defer(function()
		if inventories[player] ~= inv or not hasAnything(inv) then
			return
		end
		if inRound() then
			InventoryService.dropAll(player, position)
		else
			InventoryService.clear(player)
		end
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local inv = getInventory(player)
	if not inv then
		return
	end
	for _, connection in ipairs(inv.charConnections) do
		connection:Disconnect()
	end
	table.clear(inv.charConnections)
	destroyModel(inv)
	setUse(player, inv, nil)
	if player:GetAttribute("Alive") ~= true then
		-- a fresh character outside a round: the lobby inventory is empty
		for i = 1, SLOTS do
			inv.slots[i] = false
		end
		inv.equipped = 0
		inv.armor = ""
	end
	commit(player, inv) -- sends the spawn snapshot (and re-attaches a held item for a contender)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") and player.Character == character then
		table.insert(inv.charConnections, (humanoid :: Humanoid).Died:Connect(function()
			onDied(player, character)
		end))
		if inv.model == nil and equippedEntry(inv) then
			refreshModel(player, inv)
		end
	end
end

local function onPlayerAdded(player: Player)
	local inv = getInventory(player)
	if not inv then
		return
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	else
		scheduleSnapshot(player, inv)
	end
end

local function onPlayerRemoving(player: Player)
	local inv = inventories[player]
	if not inv then
		return
	end
	if hasAnything(inv) and inRound() then
		local root = rootOf(player)
		if root then
			-- leaving mid-round counts as an elimination: the loot stays in the arena
			InventoryService.dropAll(player, root.Position)
		end
	end
	for _, connection in ipairs(inv.charConnections) do
		connection:Disconnect()
	end
	destroyModel(inv)
	inventories[player] = nil
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function InventoryService.Init(registry)
	Services = registry
	InventoryUpdate = Net.event("InventoryUpdate")
end

function InventoryService.Start()
	Net.event("EquipSlot").OnServerEvent:Connect(onEquipSlot)
	Net.event("DropSlot").OnServerEvent:Connect(onDropSlot)
	Net.event("UseStart").OnServerEvent:Connect(onUseStart)
	Net.event("UseFinish").OnServerEvent:Connect(onUseFinish)
	Net.event("UseCancel").OnServerEvent:Connect(onUseCancel)
	Net.event("Drink").OnServerEvent:Connect(onDrink)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return InventoryService
