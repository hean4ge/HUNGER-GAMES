--[[
	ClientState - shared state and signals between client controllers. Client only.
	Each field says who writes it. Everyone else only reads it or listens.
	From a controller: local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Config = require(Shared:WaitForChild("Config"))

local player = Players.LocalPlayer

local ClientState = {
	-- MovementController writes:
	moveState = "Idle", -- "Idle" | "Walk" | "Sprint" | "Crouch" | "Slide" | "Air" | "Climb" | "Mantle" | "Swim" | "Frozen"
	speed = 0, -- horizontal speed (studs/s)
	velocity = Vector3.zero,
	grounded = true,
	stamina = 1, -- 0..1
	exhausted = false,
	crouchAlpha = 0, -- 0..1 smoothed crouch/slide amount
	strideAlpha = 0, -- 0..1 phase of the footstep cycle (camera bob and viewmodel sync to it)
	jumpPrepAt = -math.huge, -- os.clock() when the coming take-off's knee dip began (Animate plays the take-off from it)
	jumpPrepTime = 0.1, -- length of that dip (s)

	-- CameraController writes:
	lookDelta = Vector2.zero, -- camera rotation this frame in radians (X = yaw, Y = pitch)
	cameraBob = CFrame.identity, -- the bob/tilt offset applied to the camera this frame
	fov = Config.Camera.BaseFov,

	-- CombatController writes:
	aiming = false,
	aimAlpha = 0, -- 0..1
	drawAlpha = 0, -- bow draw 0..1
	crosshairSpread = 0, -- 0..1

	-- InventoryController writes:
	inventory = { slots = {}, equipped = 0, armor = "" }, -- mirror of the server's InventoryUpdate
	useProgress = nil :: { label: string, alpha: number }?, -- while using an item
	interactHint = nil :: { text: string, key: string }?, -- e.g. Drink when looking at water
	-- what the held item does (PlayabilityPlan QW2, Shared.ActionHints): text with this device's buttons in [brackets],
	-- e.g. "HOLD [LMB] EAT · +12 HUNGER"; keys = those names in order; stage "full" | "key" (faded to the button)
	actionHint = nil :: { text: string, keys: { string }?, action: string?, stage: string? }?,

	-- SpectateController writes:
	spectating = nil :: Player?,

	-- UI writes:
	menuOpen = false, -- true while a menu needs the mouse; gameplay ignores attack input
	settings = {
		fov = Config.Camera.BaseFov,
		sensitivity = 1,
		headBob = 1, -- 0..1 intensity (0 = off, for motion sensitivity)
		cameraShake = 1, -- 0..1
		musicVolume = 0.6,
		sfxVolume = 1,
		ambienceVolume = 0.8,
		-- PlayabilityPlan Q1 / QW13 (SettingsController rows; DataService saves them):
		guidance = ({ Off = 0, Auto = 1, Always = 2 } :: any)[(Config.Guidance or {}).Mode or "Auto"] or 1, -- 0 Off, 1 Auto, 2 Always
		hintsSeen = 0, -- action-hint use counters, 3 bits per action (Shared.ActionHints.ACTIONS)
		sprintMode = 0, -- keyboard: 0 Hold, 1 Toggle, 2 Auto (a full push forward sprints)
		sprintModePad = 1, -- gamepad (L3): Toggle
		sprintModeTouch = 2, -- touch: Auto (RUN hides)
		crouchMode = 0, -- keyboard: 0 Hold, 1 Toggle
		crouchModePad = 1, -- gamepad (B): Toggle
		crouchModeTouch = 1, -- touch (CROUCH): Toggle
		padLook = 1, -- controller look speed (x)
		touchLook = 1, -- touch look speed (x)
	},

	-- Mirrors of LocalPlayer attributes (kept in sync below):
	inArena = false,
	alive = false,
	frozen = false,
}

-- Signals (writer -> listeners)
ClientState.landed = Signal.new() -- (impactSpeed: number)                         MovementController
ClientState.jumped = Signal.new() -- ()                                            MovementController
ClientState.footstep = Signal.new() -- (material: Enum.Material, intensity: number, foot: "L" | "R")  MovementController
ClientState.moveStateChanged = Signal.new() -- (new: string, old: string)          MovementController
ClientState.cameraImpulse = Signal.new() -- (kick: Vector3 (pitch, yaw, roll in radians), shake: number 0..1)  anyone -> CameraController
ClientState.inventoryChanged = Signal.new() -- (inventory)                         InventoryController
ClientState.equippedChanged = Signal.new() -- (itemId: string?, slot: number)      InventoryController
ClientState.selectSlot = Signal.new() -- intent (slot: number)                     UI or anyone -> InventoryController
ClientState.dropSlot = Signal.new() -- intent (slot: number)                       UI or anyone -> InventoryController
ClientState.useRequested = Signal.new() -- (state: Enum.UserInputState)            CombatController -> InventoryController
ClientState.hitConfirmed = Signal.new() -- ({ damage, headshot, killed })          CombatController
ClientState.damageTaken = Signal.new() -- ({ amount, fromPosition?, cause })       CombatController
ClientState.interactHintChanged = Signal.new() -- (hint?)                          InventoryController
ClientState.actionHintChanged = Signal.new() -- (hint?)                            InventoryController
ClientState.slotDenied = Signal.new() -- (slot) an empty slot was pressed (it shakes)  InventoryController
ClientState.settingsChanged = Signal.new() -- (settings)                           UI (via setSettings)
ClientState.lifeChanged = Signal.new() -- ()  when inArena / alive / frozen change  (this module)
ClientState.spectateChanged = Signal.new() -- (player?)                            SpectateController

local function syncAttributes()
	local inArena = player:GetAttribute("InArena") == true
	local alive = player:GetAttribute("Alive") == true
	local frozen = player:GetAttribute("Frozen") == true
	if inArena ~= ClientState.inArena or alive ~= ClientState.alive or frozen ~= ClientState.frozen then
		ClientState.inArena, ClientState.alive, ClientState.frozen = inArena, alive, frozen
		ClientState.lifeChanged:Fire()
	end
end
for _, attribute in ipairs({ "InArena", "Alive", "Frozen" }) do
	player:GetAttributeChangedSignal(attribute):Connect(syncAttributes)
end
syncAttributes()

-- Merge partial settings and notify listeners.
function ClientState.setSettings(partial: { [string]: any })
	for key, value in pairs(partial) do
		ClientState.settings[key] = value
	end
	ClientState.settingsChanged:Fire(ClientState.settings)
end

-- PlayabilityPlan Q1: a new player has played fewer than Config.Guidance.NewPlayerRounds real rounds. RoundService
-- sets the NewPlayer attribute at each Countdown (before the horn adds one to RoundsPlayed); before any, RoundsPlayed.
function ClientState.isNewPlayer(): boolean
	local flagged = player:GetAttribute("NewPlayer")
	if type(flagged) == "boolean" then
		return flagged
	end
	local limit = tonumber((Config.Guidance or {}).NewPlayerRounds) or 3
	return (tonumber(player:GetAttribute("RoundsPlayed")) or 0) < limit
end

-- Guidance on for this player: settings.guidance Always, or Auto and a new player.
function ClientState.guidanceOn(): boolean
	local mode = tonumber(ClientState.settings.guidance) or 1
	if mode <= 0.5 then
		return false
	elseif mode >= 1.5 then
		return true
	end
	return ClientState.isNewPlayer()
end

-- Item id in the equipped slot, or nil for fists.
function ClientState.getEquippedItemId(): string?
	local inventory = ClientState.inventory
	local slot = inventory.slots[inventory.equipped]
	if slot then
		return slot.id
	end
	return nil
end

return ClientState
