--[[
	InventoryController - the local player's inventory, and the hints and answers around it. Client only; the server
	stays the source of truth.

	State (ClientState):
	  inventory = { slots = { [1..Slots] = { id, count } | false }, equipped (0 = fists), armor ("" = none) }
	  fires inventoryChanged(inventory) and equippedChanged(itemId?, slot). Equipping is predicted (instant hotbar,
	  viewmodel and sound) and confirmed or corrected by the next InventoryUpdate.
	  useProgress = { label, alpha } while using an item.
	  interactHint = { text, key } while looking at water: "Drink" or "Fill bottle", key = this device's button
	  (Shared.Glyphs); interactHintChanged fires on change.
	  actionHint = { text, keys, action, stage } what the held item does (PlayabilityPlan QW2, Shared.ActionHints), e.g.
	  "HOLD [LMB] EAT · +12 HUNGER"; actionHintChanged fires on change. Never binds a key (E stays with crate prompts).
	    Guidance (settings.guidance, Config.Guidance): Auto shows it to new players (ClientState.isNewPlayer) and fades
	    it by use: the full line for the first HintFullUses successful uses of an action, then only its button until
	    HintKeyUses, then nothing (settings.hintsSeen, 3 bits per action). Always keeps the full line; Off shows none.
	    A new player holding food or a drink for StallTime with that meter under StallBelow gets the full line back
	    once a round. The climb line shows with a Climbable trunk within reach (and "LET GO" while climbing).
	    "[G] DROP THE HELD ITEM" shows for 3 s after an "Inventory full" toast, whatever the Guidance.
	  Both hints stay up 0.25 s after their target leaves the look ray, so they don't flicker as you look around.
	Input (bound only while an alive contender and not spectating, so it never fights the spectator controls):
	  Slot1..Slot6 (One..Six), NextSlot / PrevSlot (mouse wheel, ButtonR1 / ButtonL1), Drop (G, DPadDown, touch "DROP"
	  shown only while something is equipped): a tap drops one, holding 0.4 s drops the stack ("DROPPED ARROWS ×24").
	  Selecting the equipped slot again goes back to fists (the item toast says FISTS). An empty slot is refused: the
	  slot shakes and the deny sound plays (Shared.Feedback), and you keep what you hold.
	  UI intents: ClientState.selectSlot:Fire(slot), ClientState.dropSlot:Fire(slot)
	Using items: ClientState.useRequested(state) (CombatController forwards Attack for consumables): Begin -> UseStart
	  and the progress bar; released early -> UseCancel; done -> UseFinish. Holding keeps going (berry after berry), but
	  stops before the next one would waste more than half its value. Food is refused at Hunger 95+ ("YOU'RE FULL"),
	  drinks at Thirst 95+ ("YOU'RE NOT THIRSTY"); the server refuses them too. Cancelled when the held item changes or
	  you die.
	Water: every 0.15 s the camera looks (forward and a little down) for terrain water within DrinkRange. Then the hint
	  says "Drink" or "Fill bottle" (holding an empty bottle) and the Drink action (E / ButtonX / touch "DRINK", which
	  reads "FILL" with an empty bottle) is bound; holding it keeps sipping every DrinkSipTime. Never while a
	  ProximityPrompt is showing, so E reaches prompts.
	Loot prompts (tag "LootPrompt") are hidden locally unless you are an alive contender. (A crate's "Take all" prompt,
	  only for its opener, and holding back that crate's item prompts meanwhile are LootCueController's; QW8.)
	Pickups: when a stack grows or a new item arrives (not by using, filling or swapping an item), Feedback.pickup shows
	  "+4 ARROWS" over the hotbar in the item's rarity colour.
	Bow: a release too light to shoot says "DRAW LONGER TO SHOOT" (the first 3 times).
	API: InventoryController.select(slot), .drop(slot?, count?), .cycle(direction)
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Input = require(Shared:WaitForChild("Input"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Glyphs = require(Shared:WaitForChild("Glyphs"))
local Feedback = require(Shared:WaitForChild("Feedback"))
local ActionHints = require(Shared:WaitForChild("ActionHints"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local SLOTS = Config.Inventory.Slots or 6
local SLOT_KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}
local PROMPT_TAG = "LootPrompt"
local HINT_INTERVAL = 0.15
local HINT_LINGER = 0.25 -- a hint stays up this long after its target leaves the look ray (no flicker)
local PREDICT_TIMEOUT = 0.8 -- an equip the server hasn't confirmed by then is rolled back
local EQUIP_INTERVAL = 1 / 12 -- most EquipSlot requests per second (the server allows more)
local DROP_INTERVAL = 0.2
local DROP_HOLD = 0.4 -- holding Drop this long drops the whole stack; a shorter tap drops one
local FULL_AT = tonumber(Config.Inventory.FullAt) or 95 -- food is refused at Hunger >= this, drinks at Thirst >= this
local FULL_HINT_TIME = 3 -- how long "[G] DROP THE HELD ITEM" stays after an "Inventory full" toast

local GUIDE = Config.Guidance or {}
local FULL_USES = tonumber(GUIDE.HintFullUses) or 3
local KEY_USES = tonumber(GUIDE.HintKeyUses) or 6
local STALL_TIME = tonumber(GUIDE.StallTime) or 10
local STALL_BELOW = tonumber(GUIDE.StallBelow) or 40

local InventoryController = {}

local Controllers: { [string]: any } = {}
local remotes: { [string]: RemoteEvent } = {}

local serverInventory: any = nil -- the last InventoryUpdate, sanitised
local pending: { slot: number, t: number }? = nil -- predicted equip waiting for the server
local sendQueued = false
local queueToken = 0
local lastEquipRequest = 0
local lastDropRequest = 0
local lastEquipKey = "0:"

type UseState = { slot: number, itemId: string, startedAt: number, duration: number, label: string, def: any }
local use: UseState? = nil
local useHeld = false
local useConnection: RBXScriptConnection? = nil
local awaitingSnapshot = false

local bound = false
local wheelConnection: RBXScriptConnection? = nil
local dropPress: { slot: number, t: number, token: number }? = nil
local dropToken = 0

local hint: { text: string, key: string }? = nil
local drinkBound = false
local drinkHeld = false
local lastSip = 0
local waterSeenAt = -math.huge
local shownPrompts: { [Instance]: boolean } = {}
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
waterParams.IgnoreWater = false

-- action hints
local actionHint: any = nil
local actionKey = ""
local climbSeenAt = -math.huge
local fullHintUntil = 0
local heldId: string? = nil
local heldSince = 0
local stallState: { [string]: string } = {} -- action -> "showing" | "done" (this round)
local drawStarted: { t0: number, drawTime: number, itemId: string }? = nil
local climbParams = RaycastParams.new()
climbParams.FilterType = Enum.RaycastFilterType.Exclude
climbParams.RespectCanCollide = true

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function fire(name: string, ...: any)
	local remote = remotes[name]
	if not remote then
		local ok, result = pcall(Net.event, name)
		if not ok then
			warn("[InventoryController] remote " .. name .. " missing: " .. tostring(result))
			return
		end
		remote = result
		remotes[name] = remote
	end
	(remote :: RemoteEvent):FireServer(...)
end

local function emptyInventory()
	return { slots = table.create(SLOTS, false), equipped = 0, armor = "" }
end

local function sanitize(data: any)
	local inv = emptyInventory()
	if type(data) ~= "table" then
		return inv
	end
	if type(data.slots) == "table" then
		for i = 1, SLOTS do
			local s = data.slots[i]
			if type(s) == "table" and type(s.id) == "string" and ItemDefs.get(s.id) then
				inv.slots[i] = { id = s.id, count = math.max(1, math.floor(tonumber(s.count) or 1)) }
			end
		end
	end
	if type(data.equipped) == "number" and data.equipped == data.equipped then
		inv.equipped = math.clamp(math.floor(data.equipped), 0, SLOTS)
	end
	if inv.equipped ~= 0 and not inv.slots[inv.equipped] then
		inv.equipped = 0
	end
	if type(data.armor) == "string" then
		inv.armor = data.armor
	end
	return inv
end

local function cloneInventory(source: any)
	local copy = emptyInventory()
	for i = 1, SLOTS do
		local s = source.slots[i]
		copy.slots[i] = if s then { id = s.id, count = s.count } else false
	end
	copy.equipped = source.equipped or 0
	copy.armor = source.armor or ""
	return copy
end

local function canUseInventory(): boolean
	return ClientState.alive == true and ClientState.spectating == nil
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function meter(name: string): number
	return tonumber(player:GetAttribute(name)) or 100
end

local function countOf(itemId: string): number
	local total = 0
	for i = 1, SLOTS do
		local s = ClientState.inventory.slots[i]
		if s and s.id == itemId then
			total += s.count
		end
	end
	return total
end

local function updateDropButton()
	if bound then
		Input.setTouchVisible("Drop", ClientState.inventory.equipped ~= 0)
	end
end

local function hintsSeen(): number
	return tonumber(ClientState.settings.hintsSeen) or 0
end

local refreshActionHint: () -> ()

-- One more successful use of an action: its hint fades a step (saved through SettingsController).
local function bumpHint(action: string)
	if stallState[action] == "showing" then
		stallState[action] = "done"
	end
	local before = hintsSeen()
	local after = ActionHints.bump(before, action)
	if after ~= before then
		local settings = Controllers.SettingsController
		if settings and type(settings.set) == "function" then
			settings.set("hintsSeen", after)
		else
			ClientState.setSettings({ hintsSeen = after })
		end
	end
	if refreshActionHint then
		refreshActionHint()
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Using items
--------------------------------------------------------------------------------------------------------------------

local USE_ACTION: { [string]: string } = { Food = "Eat", Drink = "Drink", Heal = "Heal", Armor = "Wear" }

local function stopUseLoop()
	if useConnection then
		useConnection:Disconnect()
		useConnection = nil
	end
end

local function cancelUse(tellServer: boolean)
	local current = use
	if not current then
		return
	end
	use = nil
	ClientState.useProgress = nil
	stopUseLoop()
	if tellServer then
		fire("UseCancel", current.slot)
	end
end

local startUse: (fromHold: boolean?) -> ()

local function finishUse()
	local current = use
	if not current then
		return
	end
	use = nil
	ClientState.useProgress = nil
	stopUseLoop()
	awaitingSnapshot = true
	fire("UseFinish", current.slot)
	if current.def.kind == "Armor" and current.def.useSound then
		Sfx.play(current.def.useSound)
	end
	local action = USE_ACTION[current.def.kind]
	if action then
		bumpHint(action)
	end
	if useHeld then
		-- still holding: wait for the server's update, then use the next one (berry after berry)
		task.spawn(function()
			local deadline = os.clock() + 1
			while awaitingSnapshot and os.clock() < deadline do
				task.wait()
			end
			task.wait(0.15)
			if useHeld and not use then
				startUse(true)
			end
		end)
	end
end

local function stepUse()
	local current = use
	if not current then
		stopUseLoop()
		return
	end
	local alpha = (os.clock() - current.startedAt) / current.duration
	local progress = ClientState.useProgress
	if progress then
		progress.alpha = math.clamp(alpha, 0, 1)
	end
	if alpha >= 1 then
		finishUse()
	end
end

-- Why the server would refuse this use (or why a held repeat should stop), as (reason, text), or nil.
local function useRefusal(def: any, inv: any, entry: any, humanoid: Humanoid, fromHold: boolean): (string?, string?)
	if def.kind == "Armor" and inv.armor == entry.id then
		return "Worn", "YOU'RE ALREADY WEARING IT"
	end
	if def.kind == "Heal" then
		local missing = humanoid.MaxHealth - humanoid.Health
		if missing <= 0.5 then
			return "NotHurt", "YOU'RE NOT HURT"
		end
		local heal = tonumber(def.heal) or 0
		if fromHold and heal - missing > heal / 2 then
			return "NotHurt", "YOU'RE NOT HURT"
		end
		return nil, nil
	end
	local stat = if def.kind == "Food" then "Hunger" elseif def.kind == "Drink" then "Thirst" else nil
	if not stat then
		return nil, nil
	end
	local level = meter(stat)
	local text = if stat == "Hunger" then "YOU'RE FULL" else "YOU'RE NOT THIRSTY"
	if level >= FULL_AT then
		return "Full" .. stat, text
	end
	local value = tonumber(if stat == "Hunger" then def.hunger else def.thirst) or 0
	if fromHold and value > 0 and level + value - 100 > value / 2 then
		return "Full" .. stat, text -- the next one would waste more than half of it
	end
	return nil, nil
end

local flushEquip: () -> ()

startUse = function(fromHold: boolean?)
	if use or not canUseInventory() or ClientState.menuOpen then
		return
	end
	flushEquip() -- the server must know what we're holding before UseStart arrives
	local inv = ClientState.inventory
	local slot = inv.equipped
	local entry = inv.slots[slot]
	if not entry or not ItemDefs.isConsumable(entry.id) then
		return
	end
	local def = ItemDefs.get(entry.id)
	local humanoid = getHumanoid()
	if not def or not humanoid or humanoid.Health <= 0 then
		return
	end
	-- the server would refuse these: say why instead of filling the bar for nothing
	local reason, text = useRefusal(def, inv, entry, humanoid, fromHold == true)
	if reason then
		useHeld = false
		Feedback.deny(reason, text)
		return
	end
	local current: UseState = {
		slot = slot,
		itemId = entry.id,
		startedAt = os.clock(),
		duration = math.max(0.1, tonumber(def.useTime) or 1),
		label = def.useLabel or "Using",
		def = def,
	}
	use = current
	ClientState.useProgress = { label = current.label, alpha = 0 }
	fire("UseStart", slot)
	if def.kind ~= "Armor" and def.useSound then
		Sfx.play(def.useSound)
	end
	stopUseLoop()
	useConnection = RunService.RenderStepped:Connect(stepUse)
end

--------------------------------------------------------------------------------------------------------------------
-- Inventory state and equipping
--------------------------------------------------------------------------------------------------------------------

local function equipKey(inv: any): string
	local entry = inv.slots[inv.equipped]
	return tostring(inv.equipped) .. ":" .. (if entry then entry.id else "")
end

-- Fire equippedChanged / play the equip sound when the held item changed; keep the use and DROP button in sync.
local function announceEquip()
	local inv = ClientState.inventory
	local key = equipKey(inv)
	if key ~= lastEquipKey then
		local previousSlot = tonumber(string.match(lastEquipKey, "^(%d+):")) or 0
		lastEquipKey = key
		local itemId = ClientState.getEquippedItemId()
		ClientState.equippedChanged:Fire(itemId, inv.equipped)
		if itemId and previousSlot ~= inv.equipped then
			local def = ItemDefs.get(itemId)
			Sfx.play(if def and def.equipSound then def.equipSound else "Equip_Generic")
		end
	end
	local current = use
	if current then
		local entry = inv.slots[current.slot]
		if inv.equipped ~= current.slot or not entry or entry.id ~= current.itemId then
			cancelUse(true)
		end
	end
	updateDropButton()
end

local function publish(inv: any)
	ClientState.inventory = inv
	ClientState.inventoryChanged:Fire(inv)
	announceEquip()
	if refreshActionHint then
		refreshActionHint()
	end
end

local function totals(inv: any): { [string]: number }
	local t = {}
	for i = 1, SLOTS do
		local s = inv.slots[i]
		if s then
			t[s.id] = (t[s.id] or 0) + s.count
		end
	end
	return t
end

-- "+4 ARROWS" for whatever arrived since the last snapshot - not what an item turned into (a drunk bottle becomes
-- an empty one, an empty one is filled) or armor you took off when putting on another.
local function announcePickups(before: any, after: any)
	if not before or not ClientState.inArena or not ClientState.alive then
		return
	end
	local a, b = totals(before), totals(after)
	local turnedInto: { [string]: number } = {}
	for id, n in pairs(a) do
		local lost = n - (b[id] or 0)
		local def = ItemDefs.get(id)
		if lost > 0 and def then
			for _, into in ipairs({ def.becomes, def.fillsInto }) do
				if type(into) == "string" then
					turnedInto[into] = (turnedInto[into] or 0) + lost
				end
			end
		end
	end
	if before.armor ~= after.armor and before.armor ~= "" then
		turnedInto[before.armor] = (turnedInto[before.armor] or 0) + 1
	end
	for id, m in pairs(b) do
		local gained = m - (a[id] or 0) - (turnedInto[id] or 0)
		if gained > 0 then
			Feedback.pickup(id, gained)
		end
	end
end

local function onSnapshot(data: any)
	local previous = serverInventory
	serverInventory = sanitize(data)
	awaitingSnapshot = false
	announcePickups(previous, serverInventory)
	local inv = cloneInventory(serverInventory)
	local want = pending
	if want then
		if inv.equipped == want.slot or os.clock() - want.t > PREDICT_TIMEOUT then
			pending = nil
		elseif want.slot == 0 or inv.slots[want.slot] then
			inv.equipped = want.slot -- the server hasn't seen our latest choice yet
		else
			pending = nil
		end
	end
	publish(inv)
end

local function rollbackIfUnconfirmed(stamp: number)
	task.delay(PREDICT_TIMEOUT + 0.05, function()
		local want = pending
		if want and want.t == stamp then
			pending = nil
			if serverInventory then
				publish(cloneInventory(serverInventory))
			end
		end
	end)
end

local function sendEquip()
	local want = pending
	if not want then
		return
	end
	lastEquipRequest = os.clock()
	want.t = lastEquipRequest
	fire("EquipSlot", want.slot)
	rollbackIfUnconfirmed(want.t)
end

flushEquip = function()
	if sendQueued then
		sendQueued = false
		queueToken += 1
		sendEquip()
	end
end

-- Predict the change at once; requests are coalesced so mouse-wheel spam sends only the latest choice.
local function requestEquip(slot: number)
	local inv = ClientState.inventory
	if slot == inv.equipped then
		return
	end
	pending = { slot = slot, t = os.clock() }
	local predicted = cloneInventory(inv)
	predicted.equipped = slot
	publish(predicted)
	local waitFor = EQUIP_INTERVAL - (os.clock() - lastEquipRequest)
	if waitFor <= 0 then
		sendEquip()
	elseif not sendQueued then
		sendQueued = true
		queueToken += 1
		local token = queueToken
		task.delay(waitFor, function()
			if sendQueued and token == queueToken then
				sendQueued = false
				sendEquip()
			end
		end)
	end
end

local function flashFists()
	local hud = Controllers.HUDController
	if hud and type(hud.flashItemName) == "function" and ClientState.inArena and ClientState.alive then
		pcall(hud.flashItemName, "fists")
	end
end

function InventoryController.select(slot: number)
	if type(slot) ~= "number" or slot ~= slot or not canUseInventory() then
		return
	end
	local s = math.floor(slot)
	if s < 0 or s > SLOTS then
		return
	end
	local inv = ClientState.inventory
	if s ~= 0 and not inv.slots[s] then
		-- an empty slot: refuse it and keep what you hold (the slot shakes, a dry click)
		Feedback.deny("EmptySlot")
		Feedback.shakeSlot(s)
		local denied = (ClientState :: any).slotDenied
		if denied then
			denied:Fire(s)
		end
		return
	end
	local target = s
	if s ~= 0 and s == inv.equipped then
		target = 0 -- the slot you hold again: back to fists
	end
	if target == 0 and inv.equipped ~= 0 then
		requestEquip(0)
		flashFists()
		return
	end
	requestEquip(target)
end

-- Cycles through fists and the occupied slots.
function InventoryController.cycle(direction: number)
	if not canUseInventory() then
		return
	end
	local inv = ClientState.inventory
	local order = { 0 }
	for i = 1, SLOTS do
		if inv.slots[i] then
			table.insert(order, i)
		end
	end
	if #order <= 1 then
		return
	end
	local index = table.find(order, inv.equipped) or 1
	local step = if direction < 0 then -1 else 1
	requestEquip(order[((index - 1 + step) % #order) + 1])
end

-- Drop a slot (default: the held one). count = how many (default: the whole stack).
function InventoryController.drop(slot: number?, count: number?)
	if not canUseInventory() then
		return
	end
	local inv = ClientState.inventory
	local s = if type(slot) == "number" and slot == slot then math.floor(slot) else inv.equipped
	local entry = if s >= 1 and s <= SLOTS then inv.slots[s] else nil
	if not entry then
		return
	end
	local now = os.clock()
	if now - lastDropRequest < DROP_INTERVAL then
		return
	end
	lastDropRequest = now
	local current = use
	if current and current.slot == s then
		cancelUse(true)
	end
	local n = if type(count) == "number" and count == count then math.clamp(math.floor(count), 1, entry.count) else entry.count
	if n < entry.count then
		fire("DropSlot", s, n)
	else
		fire("DropSlot", s)
	end
	Feedback.dropped(entry.id, n)
end

--------------------------------------------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------------------------------------------

-- Drop: a tap drops one, holding DROP_HOLD drops the stack (at once, while still held).
local function onDropAction(state: Enum.UserInputState): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		if ClientState.menuOpen then
			return Enum.ContextActionResult.Pass
		end
		local inv = ClientState.inventory
		local s = inv.equipped
		local entry = if s ~= 0 then inv.slots[s] else nil
		if not entry then
			Feedback.deny("NothingToDrop", "NOTHING IN YOUR HAND", { limit = 2 })
			return nil
		end
		if entry.count <= 1 then
			InventoryController.drop(s, nil)
			return nil
		end
		dropToken += 1
		local token = dropToken
		dropPress = { slot = s, t = os.clock(), token = token }
		task.delay(DROP_HOLD, function()
			local press = dropPress
			if press and press.token == token then
				dropPress = nil
				InventoryController.drop(press.slot, nil)
			end
		end)
		return nil
	end
	local press = dropPress
	dropPress = nil
	if press and os.clock() - press.t < DROP_HOLD then
		InventoryController.drop(press.slot, 1)
	end
	return nil
end

local function bindActions()
	if bound then
		return
	end
	bound = true
	for i = 1, math.min(SLOTS, #SLOT_KEYS) do
		Input.bind("Slot" .. i, function(state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				if ClientState.menuOpen then
					return Enum.ContextActionResult.Pass
				end
				InventoryController.select(i)
			end
			return nil
		end, { keys = { SLOT_KEYS[i] } })
	end
	Input.bind("NextSlot", function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin and not ClientState.menuOpen then
			InventoryController.cycle(1)
		end
		return nil
	end, { keys = { Enum.KeyCode.ButtonR1 } })
	Input.bind("PrevSlot", function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin and not ClientState.menuOpen then
			InventoryController.cycle(-1)
		end
		return nil
	end, { keys = { Enum.KeyCode.ButtonL1 } })
	Input.bind("Drop", onDropAction, { keys = { Enum.KeyCode.G, Enum.KeyCode.DPadDown }, touch = { visible = false } })
	updateDropButton()
	wheelConnection = UserInputService.InputChanged:Connect(function(io: InputObject, processed: boolean)
		if processed or io.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		if ClientState.menuOpen or not canUseInventory() then
			return
		end
		local z = io.Position.Z
		if z > 0 then
			InventoryController.cycle(-1)
		elseif z < 0 then
			InventoryController.cycle(1)
		end
	end)
end

local function unbindActions()
	if not bound then
		return
	end
	bound = false
	dropPress = nil
	for i = 1, math.min(SLOTS, #SLOT_KEYS) do
		Input.unbind("Slot" .. i)
	end
	Input.unbind("NextSlot")
	Input.unbind("PrevSlot")
	Input.unbind("Drop")
	if wheelConnection then
		wheelConnection:Disconnect()
		wheelConnection = nil
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Drinking
--------------------------------------------------------------------------------------------------------------------

local function trySip()
	local current = hint
	if not current or use then
		return
	end
	local now = os.clock()
	if now - lastSip < (Config.Survival.DrinkSipTime or 0.7) then
		return
	end
	lastSip = now
	fire("Drink")
	if current.text == "Fill bottle" then
		Sfx.play("WaterSplash", { volume = 0.5 })
		bumpHint("Fill")
	else
		Sfx.play("Drink")
	end
end

local function drinkLabel(): string
	return if hint and hint.text == "Fill bottle" then "FILL" else "DRINK"
end

local function bindDrink()
	if drinkBound then
		Input.setTouchLabel("Drink", drinkLabel())
		return
	end
	drinkBound = true
	Input.bind("Drink", function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			if ClientState.menuOpen then
				return Enum.ContextActionResult.Pass
			end
			drinkHeld = true
			trySip()
		else
			drinkHeld = false
		end
		return nil
	end, { keys = { Enum.KeyCode.E, Enum.KeyCode.ButtonX }, touch = { label = drinkLabel() } })
	Input.setTouchVisible("Drink", true)
end

local function unbindDrink()
	drinkHeld = false
	if drinkBound then
		drinkBound = false
		Input.unbind("Drink")
	end
end

local function setHint(text: string?)
	if text == nil then
		if hint ~= nil then
			hint = nil
			ClientState.interactHint = nil
			ClientState.interactHintChanged:Fire(nil)
		end
		unbindDrink()
		return
	end
	local key = ActionHints.keyOf("Drink")
	local current = hint
	if not current or current.text ~= text or current.key ~= key then
		local newHint = { text = text, key = key }
		hint = newHint
		ClientState.interactHint = newHint
		ClientState.interactHintChanged:Fire(newHint)
	end
	bindDrink()
end

local function lookingAtWater(): boolean
	local camera = workspace.CurrentCamera
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not camera or not character or not (head and head:IsA("BasePart")) then
		return false
	end
	local origin = camera.CFrame.Position
	if (origin - head.Position).Magnitude > 4 then
		origin = head.Position -- not in first person: measure from the head like the server does
	end
	waterParams.FilterDescendantsInstances = { character, camera }
	local look = camera.CFrame.LookVector
	local range = (Config.Survival.DrinkRange or 9) - 0.5
	for _, direction in ipairs({ look, (look - Vector3.new(0, 0.45, 0)).Unit }) do
		local result = workspace:Raycast(origin, direction * range, waterParams)
		if result and result.Instance == workspace.Terrain and result.Material == Enum.Material.Water then
			return true
		end
	end
	return false
end

local function anyPromptShown(): boolean
	for prompt in pairs(shownPrompts) do
		if prompt.Parent then
			return true
		end
		shownPrompts[prompt] = nil
	end
	return false
end

--------------------------------------------------------------------------------------------------------------------
-- Action hints (QW2)
--------------------------------------------------------------------------------------------------------------------

local function hasTagUp(inst: Instance?, tag: string): boolean
	local node = inst
	local depth = 0
	while node and node ~= workspace and depth < 5 do
		if node:HasTag(tag) then
			return true
		end
		node = node.Parent
		depth += 1
	end
	return false
end

-- A Climbable surface (not a ladder) within climbing reach in front of you, as MovementController probes it.
local function climbableInReach(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not (root and root:IsA("BasePart") and humanoid and camera) then
		return false
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.2 then
		return false
	end
	flat = flat.Unit
	climbParams.FilterDescendantsInstances = { character :: Model }
	local reach = 0.5 + (tonumber(Config.Movement.Climb and Config.Movement.Climb.Reach) or 2.5)
	local feetY = root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
	for _, h in ipairs({ 2.4, 1.2, 3.6 }) do
		local origin = Vector3.new(root.Position.X, feetY + h, root.Position.Z)
		local result = workspace:Raycast(origin, flat * reach, climbParams)
		if result and not result.Instance:IsA("TrussPart") and math.abs(result.Normal.Y) < 0.8
			and hasTagUp(result.Instance, "Climbable") then
			return true
		end
	end
	return false
end

-- 0 Off, 1 Auto, 2 Always: the player's Guidance setting (a number, or a word), else Config.Guidance.Mode.
local function guidanceMode(): number
	local setting = ClientState.settings.guidance
	if type(setting) == "number" and setting == setting then
		return math.clamp(math.floor(setting + 0.5), 0, 2)
	end
	local word = if type(setting) == "string" then setting else GUIDE.Mode
	if type(word) == "string" then
		local w = string.lower(word)
		if w == "off" then
			return 0
		elseif w == "always" then
			return 2
		end
	end
	return 1
end

local function isNewPlayer(): boolean
	local fn = (ClientState :: any).isNewPlayer
	if type(fn) == "function" then
		return fn() == true
	end
	return (tonumber(player:GetAttribute("RoundsPlayed")) or 0) < (tonumber(GUIDE.NewPlayerRounds) or 3)
end

-- Holding food (or a drink) a while without using it, with that meter low: the full line comes back once a round.
local function stalled(action: string): boolean
	if action ~= "Eat" and action ~= "Drink" then
		return false
	end
	local state = stallState[action]
	if state == "showing" then
		return true
	end
	if state == "done" or os.clock() - heldSince < STALL_TIME then
		return false
	end
	if meter(if action == "Eat" then "Hunger" else "Thirst") >= STALL_BELOW then
		return false
	end
	stallState[action] = "showing"
	return true
end

-- "full" | "key" | nil: how much of an action's hint this player sees now.
local function hintStage(action: string): string?
	local mode = guidanceMode()
	if mode == 0 then
		return nil
	elseif mode == 2 then
		return "full"
	end
	if not isNewPlayer() then
		return nil
	end
	local n = ActionHints.count(hintsSeen(), action)
	if n < FULL_USES then
		return "full"
	end
	if stalled(action) then
		return "full"
	end
	if n < KEY_USES then
		return "key"
	end
	return nil
end

local function keysIn(text: string): { string }?
	local keys = {}
	for key in string.gmatch(text, "%[([^%]]+)%]") do
		table.insert(keys, key)
	end
	return if #keys > 0 then keys else nil
end

local function computeActionHint(): any
	if not bound or ClientState.menuOpen or use or useHeld or hint ~= nil then
		return nil -- the use ring is up, or the water hint (it takes priority) is
	end
	local now = os.clock()
	local device = Input.device()
	local itemId = ClientState.getEquippedItemId()
	local def = if itemId then ItemDefs.get(itemId) else nil
	if now < fullHintUntil then
		local drop = ActionHints.keyOf("Drop", device)
		local text
		if device == "Touch" then
			text = if def then "TAP [DROP] TO MAKE ROOM" else "TAP A SLOT · THEN [DROP]"
		else
			text = if def then string.format("[%s] DROP THE HELD ITEM", drop) else string.format("SELECT AN ITEM · [%s] DROP IT", drop)
		end
		return { text = text, keys = keysIn(text), action = "Drop", stage = "full" }
	end
	local climbing = ClientState.moveState == "Climb"
	if climbing or now - climbSeenAt <= HINT_LINGER then
		local stage = hintStage("Climb")
		if stage then
			local h = ActionHints.build("Climb", nil, device, { climbing = climbing, keyOnly = stage == "key" })
			if h then
				return h
			end
		end
	end
	local action = ActionHints.forItem(def)
	if action then
		local stage = hintStage(action)
		if stage then
			return ActionHints.build(action, def, device, { keyOnly = stage == "key", arrows = countOf("arrow") })
		end
	end
	return nil
end

refreshActionHint = function()
	local h = computeActionHint()
	local key = if h then (h.text .. "|" .. tostring(h.stage)) else ""
	if key == actionKey then
		return
	end
	actionKey = key
	actionHint = h
	ClientState.actionHint = h
	local changed = (ClientState :: any).actionHintChanged
	if changed then
		changed:Fire(h)
	end
end

-- The big touch button names what the held item does (EAT, DRINK, DRAW, THROW while a spear is aimed...).
local function refreshTouchLabels()
	if not bound then
		return
	end
	local itemId = ClientState.getEquippedItemId()
	local def = if itemId then ItemDefs.get(itemId) else nil
	Input.setTouchLabel("Attack", ActionHints.touchLabel(def, ClientState.aiming == true))
end

local function hintLoop()
	while true do
		local now = os.clock()
		local busy = not bound or ClientState.menuOpen or use ~= nil or anyPromptShown()
		if not busy and lookingAtWater() then
			waterSeenAt = now
		end
		local text = nil
		if not busy and now - waterSeenAt <= HINT_LINGER then
			local itemId = ClientState.getEquippedItemId()
			local def = itemId and ItemDefs.get(itemId)
			text = if def and def.fillsInto then "Fill bottle" else "Drink"
		end
		setHint(text)
		if drinkHeld and hint then
			trySip()
		end
		-- the held item, for the stall rule
		local itemId = ClientState.getEquippedItemId()
		if itemId ~= heldId then
			heldId = itemId
			heldSince = now
			for action, state in pairs(stallState) do
				if state == "showing" then
					stallState[action] = "done" -- it came back once; switching items ends it
				end
			end
		end
		if bound and ClientState.moveState ~= "Climb" and climbableInReach() then
			climbSeenAt = now
		end
		refreshActionHint()
		refreshTouchLabels()
		task.wait(HINT_INTERVAL)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Loot prompt visibility (alive contenders only) and life changes
--------------------------------------------------------------------------------------------------------------------

local function applyPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local range = prompt:GetAttribute("Range")
	if type(range) == "number" then
		prompt.MaxActivationDistance = if ClientState.alive then range else 0
	end
end

local function refreshPrompts()
	for _, prompt in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do
		applyPrompt(prompt)
	end
end

local function refreshLife()
	refreshPrompts()
	if canUseInventory() then
		bindActions()
	else
		unbindActions()
		useHeld = false
		cancelUse(true)
		setHint(nil)
	end
	if ClientState.inArena and ClientState.alive then
		table.clear(stallState)
	end
	refreshActionHint()
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function InventoryController.Init(registry)
	Controllers = registry
	Feedback.init(registry)
end

function InventoryController.Start()
	publish(emptyInventory())
	Net.event("InventoryUpdate").OnClientEvent:Connect(onSnapshot)
	-- "Inventory full": say how to make room, under the crosshair, with this device's button
	Net.event("Announce").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.text) == "string"
			and string.find(string.lower(payload.text), "inventory full", 1, true) == 1 then
			fullHintUntil = os.clock() + FULL_HINT_TIME
			refreshActionHint()
		end
	end)
	ClientState.selectSlot:Connect(function(slot)
		InventoryController.select(slot)
	end)
	ClientState.dropSlot:Connect(function(slot)
		InventoryController.drop(slot)
	end)
	ClientState.useRequested:Connect(function(state)
		if state == Enum.UserInputState.Begin then
			useHeld = true
			startUse(false)
		else
			useHeld = false
			cancelUse(true)
		end
		refreshActionHint()
	end)
	ClientState.lifeChanged:Connect(refreshLife)
	ClientState.spectateChanged:Connect(refreshLife)
	ClientState.settingsChanged:Connect(function()
		refreshActionHint()
	end)
	ClientState.moveStateChanged:Connect(function(new, old)
		if new == "Climb" and old ~= "Climb" then
			bumpHint("Climb")
		end
		refreshActionHint()
	end)
	Glyphs.changed:Connect(function()
		if hint then
			setHint(hint.text) -- the key name follows the device
		end
		refreshActionHint()
	end)
	local combat = Controllers.CombatController
	if combat and type(combat.action) == "table" and type(combat.action.Connect) == "function" then
		combat.action:Connect(function(name: string, data: any)
			if name == "DrawStart" and type(data) == "table" then
				drawStarted = { t0 = tonumber(data.t0) or os.clock(), drawTime = tonumber(data.drawTime) or 1, itemId = data.itemId }
			elseif name == "DrawCancel" then
				local started = drawStarted
				drawStarted = nil
				-- let down because the release came too early (not because you switched, opened a menu or died)
				local minCharge = tonumber(Config.Combat.MinBowCharge) or 0.2
				if started and os.clock() - started.t0 < started.drawTime * minCharge + 0.08
					and ClientState.getEquippedItemId() == started.itemId and not ClientState.menuOpen
					and ClientState.alive and not ClientState.frozen then
					Feedback.deny("ShortDraw", "DRAW LONGER TO SHOOT", { limit = 3 })
				end
			elseif name == "Release" then
				drawStarted = nil
				bumpHint("Bow")
				bumpHint("Ammo")
			elseif name == "ThrowRelease" and type(data) == "table" then
				bumpHint(if data.spear then "Spear" else "Knife")
			end
		end)
	end
	CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(applyPrompt)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		shownPrompts[prompt] = true
		setHint(nil) -- E belongs to the prompt now
		waterSeenAt = -math.huge
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		shownPrompts[prompt] = nil
	end)
	player.CharacterAdded:Connect(function()
		useHeld = false
		cancelUse(false)
	end)
	refreshLife()
	task.spawn(hintLoop)
end

return InventoryController
