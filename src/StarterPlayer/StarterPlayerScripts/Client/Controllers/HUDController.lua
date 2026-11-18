--[[
	HUDController - the in-arena HUD. Owned by the UI system.
	Drives StarterGui.HUD (safe-area layout) and StarterGui.HUDFX (full-bleed, true screen centre), both built by
	ServerStorage.WorldGen.UIBuilder in the "Quiet" style (docs/design/ui/StyleA_Quiet/README.md; Shared.Theme,
	Shared.QuietUI): no boxes, one ink colour, Sun for "look at this", Red only for a danger state (low health, the
	border), never as a hit effect. Things rest or fade when they are not needed.
	  * Vitals: health (+ a thin armour line), hunger, thirst, stamina (only while in use). Slim lines with an icon and
	    a number, and a ghost that trails a loss. A value that is fine rests (dimmed); one that just changed is full
	    ink for a few seconds. Hunger or thirst at or under the healing tick turns Sun; low health turns Red (also
	    while you are outside the border). No "LOW" tags: the colour says it.
	  * Hotbar: Config.Inventory.Slots cells with no boxes: the item's own 3D picture (ItemModels.build(id, "world")
	    framed by its bounding box, text fallback), the cell's number, the stack count. The cell in hand has a bigger
	    picture and a line under it, and its name shows above the hotbar for a moment. An empty cell is a small
	    ring. With a keyboard or a gamepad the cells you do not hold dim a few seconds after the last change. Tap to
	    select on touch. On touch screens it slides left so it never overlaps the action buttons (Theme.TouchLayout /
	    Shared.Input).
	  * Compass line from the camera yaw with a Spire marker (its distance under it when facing it) and, when you're
	    outside the border, a border marker, a Red line, one line of text and a thin Red edge around the screen
	    (HUDFX.BorderLine). The round's facts: "17 left" with the day and the time of day (GameState.Clock through
	    Shared.DayCycle, in ten-minute steps), top right on a desktop (HUD.Root.Facts) and in the line under the
	    compass on touch screens. Practice tag, next-event line. One countdown at a time: the round clock shows only
	    while the event line has no sooner countdown of its own (round-flow QA).
	  * Kill feed (KillFeed remote): plain lines, a small blade between the two names; a line dims after a few
	    seconds and then fades out. Crosshair (a dot and a thin ring; spread lines from ClientState.crosshairSpread
	    with a bow or a throw), hit/kill marker (ClientState.hitConfirmed), directional damage arcs
	    (ClientState.damageTaken), low-health / outside-border / hurt edges, use ring (ClientState.useProgress), bow
	    draw gauge upright beside the crosshair (ClientState.drawAlpha; under it, it covered a far target's legs),
	    interaction hint (ClientState.interactHint).
	  * Prompts: a ProximityPrompt whose Style is Custom (crates, ground items, loose arrows: InventoryController,
	    LootCueController and WorldItemController set it) is drawn here as a key square and a few words under the
	    crosshair, in the interaction hint's place: "[E] Open crate", "[E] Take Bandage ×2". The text is the prompt's
	    attribute PromptLine, else its ActionText and ObjectText. A hold fills a short line under it. On a touch
	    screen the key reads TAP and the line is a button (48 px tall). The engine still reads E / ButtonX itself.
	    Prompts in any other style are left to Roblox.
	  * The practice dummies' name and health line (BillboardGui "HealthBar" in the head of a TrainingDummy, built
	    and driven by the server) are restyled on this client: a slim ink line that mirrors the server's fill.
	  * Core GUI: Backpack and Health off, reset disabled while InArena, mouse icon hidden in arena first person.
	  PlayabilityPlan quick wins drawn here:
	  * QW2  the action hint (ClientState.actionHint = { text, keys? }) under the crosshair in the key-cap style: "[LMB]"
	         or "{1}" in the text become caps, other keys lead. The interaction hint (water) wins. Both hold 0.25 s
	         after their source goes so they never flicker. The item toast adds the item's desc for its first 3 shows.
	         With a bow in hand the action hint sits lower, below the feet of a target 60 studs out.
	  * QW5  a tick at Config.Survival.RegenMinStat on Hunger and Thirst (the healing line); under Health a dim
	         "NOT HEALING · THIRSTY" only when a meter is the reason (player attribute Regen, else the meters), red
	         "DEHYDRATED · LOSING HEALTH" (or STARVING) at an empty meter; a slow shimmer while health comes back.
	         One low-health line: Config.Feedback.LowHealth turns the health line Red and brings the dark edge.
	  * QW9  the event line always shows the next beat (dim while more than a minute away), built by Shared.ThreatLine
	         with Shared.Lore's names: ROLL CALL AT DUSK, THE OFFERING, THE BORDER MOVES, THE LAST STAND.
	  * QW10 Guidance: below 50 thirst with nothing to drink, a water drop and its distance on the compass (nearest
	         Shared.WaterPoints point inside the border). A drink retires it until thirst drops under 50 again (or 5
	         below a drink that left you under 50). Off the ribbon it waits at the edge with its distance and an arrow
	         ("‹ 64 m"). Each distance sits centred under its marker; where the water's and the Spire's would meet,
	         the Spire's gives way. Once the border moves
	         and you're within 80 m of its edge: "BORDER 42 m" under the compass and a tick toward the edge.
	Public API (Controllers.HUDController):
	  flashItemName(itemId: string?)               show the item-name toast above the hotbar
	  getHotbarRect() -> (Vector2, Vector2)        absolute position and size of the hotbar
	  suppressTop(reason: string, on: boolean)     hide the compass block while something else uses the top band
	                                               (NotificationController does this for headlines on phones)
	  guidanceOn() -> boolean                      Q1: extra help for this player (Config.Guidance, or the player's
	                                               Guidance setting: "Off" | "Auto" | "Always", or 0 | 1 | 2)
	  roundsPlayed() -> number                     real rounds played, as read at this round's Countdown
	  keyName(action: "Interact" | "Use") -> string  this device's button as hints print it ("E", "LMB", "X", ...)
	  pulseWater(seconds: number?)                 the THIRSTY card is up: show and pulse the water marker
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Input = require(Shared:WaitForChild("Input"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local Lore = require(Shared:WaitForChild("Lore"))
local ThreatLine = require(Shared:WaitForChild("ThreatLine"))
local WaterPoints: any = nil
do
	local module = Shared:FindFirstChild("WaterPoints")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		WaterPoints = if ok and type(result) == "table" then result else nil
	end
end
-- the day and the time of day beside "17 left" (GameState.Clock); without the module that line is left out
local DayCycle: any = nil
do
	local module = Shared:FindFirstChild("DayCycle")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		DayCycle = if ok and type(result) == "table" then result else nil
	end
end

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer
local C = Theme.Colors
local T = Theme.Transparency

local HUDController = {}

local SLOTS = math.max(1, math.floor(tonumber(Config.Inventory.Slots) or 6))
local SLOT_GAP = (Theme.Layout and Theme.Layout.SlotGap) or 6
local BUTTON_MARGIN = (Theme.Layout and Theme.Layout.HotbarButtonMargin) or 12
local ICON = (Theme.Layout and Theme.Layout.IconSize) or 44 -- an item's picture in its cell (design px)
local ICON_SELECTED = (Theme.Layout and Theme.Layout.IconSelected) or 54 -- ...and the one in hand
local IDLE = (Theme.Time and Theme.Time.Idle) or 4 -- seconds a quiet thing stays lit after it last changed
local STUD_TO_METERS = 0.28
local COMPASS_WIDTH = 360 -- design px (UIBuilder)
local COMPASS_SPAN = 150 -- degrees visible across the ribbon
local MARKER_Y = 24 -- every compass marker's y inside Markers (UIBuilder's MARKER_Y)
local LOW_HEALTH = tonumber(Config.Feedback and Config.Feedback.LowHealth) or 0.35 -- also the dark edge and the heartbeat
local LOW = { Health = LOW_HEALTH, Hunger = 0.25, Thirst = 0.25 } -- at or under these the line also pulses
local REGEN_MIN = tonumber(Config.Survival.RegenMinStat) or 55 -- health only comes back above this on both meters
local MONO_FAMILY = "rbxasset://fonts/families/RobotoMono.json" -- numbers inside a RichText line of words
local FEED_IN, FEED_OUT, FEED_FAST = 0.16, 0.5, 0.12 -- a kill-feed line's fades (seconds)
local FEED_REST_AT, FEED_REST_TIME = 3.2, 0.6 -- when a line dims to "old", and how long that takes
local PROMPT_Y = 64 -- the interaction hint's place under the crosshair (UIBuilder), shared by prompts
local PROMPT_TAP = Vector2.new(280, 48) -- the touch target over a prompt (design px; never under 44)
local DUMMY_TAG = "TrainingDummy"
local HINT_HOLD = 0.25 -- hints stay up this long after their source goes, so they never flicker (P8)
local DRINK_HINT_MAX = 95 -- the "Drink" hint is not drawn at or above this thirst (a swimmer at 97 had it on screen)
local WATER_THIRST = 50 -- Guidance: the water marker shows below this thirst
local WATER_REARM_DROP = 5 -- after a drink that leaves you under WATER_THIRST, the marker returns this much thirstier
local DRAW_GAUGE_X = 32 -- the bow's draw gauge stands this far right of the crosshair (design px), clear of a far target
local DRAW_GAUGE_HEIGHT = 34
local ACTION_Y = 64 -- the action hint's place under the crosshair (UIBuilder)...
local ACTION_Y_BOW = 100 -- ...and with a bow in hand: below the feet of a target 60 studs out
local BORDER_NEAR_METERS = 80 -- the border's distance shows this close to its edge while it moves
local DESC_SHOWS = 3 -- the item toast carries the description the first few times each item shows
local KIND_LABEL = {
	Melee = "MELEE", Bow = "RANGED", Throwable = "THROWN", Ammo = "AMMO", Food = "FOOD", Drink = "DRINK",
	Heal = "HEALING", Armor = "ARMOR", Utility = "UTILITY",
}
local CAUSE_ALONE = {
	Fall = "fell to their death", Border = "was caught by the border", Starvation = "starved",
	Dehydration = "died of thirst", Combat = "was eliminated", Other = "was eliminated", Left = "left the arena",
}
local HIT_DIRS = { A = { 1, -1 }, B = { -1, -1 }, C = { 1, 1 }, D = { -1, 1 } }

local hud: ScreenGui? = nil
local fx: ScreenGui? = nil
local playerGui: PlayerGui? = nil
local R: { [string]: any } = {}
local getScale: () -> number = function()
	return 1
end

local touchLayout = false
local layoutKey = "Desktop"
local slotSize = 56
local humanoid: Humanoid? = nil
local charConnections: { RBXScriptConnection } = {}
local health, maxHealth = 100, 100
local armorText: string? = nil
local armorNoteUntil = 0 -- os.clock() until which the armour's share is written beside the health number
local armorNoteShown: boolean? = nil
local stats: { [string]: any } = {}
local slotRefs: { any } = {}
local equippedSlot = 0
local hotbarLitUntil = 0 -- os.clock() until which every cell is fully lit (after that the ones not in hand dim)
local hotbarRest = false
local factsOn = false -- the round's facts are in HUD.Root.Facts (desktop) instead of the line under the compass
local reducedMotion = false -- QuietUI.reducedMotion(), read once a second
local reducedAt = -math.huge
local clockRaw: any = nil -- GameState.Clock as last decoded...
local clockBase: any = nil -- ...and its time base (Shared.DayCycle)
local baselineRed: boolean? = nil
local feed: { any } = {}
local feedCounter = 0
local damageDirs: { any } = {}
local nextDir = 1
local hurtAlpha = 0
local borderAlpha = 0
local compassItems: { any } = {}
local lastHeading = -1000
local itemNameToken = 0
local staminaVis = 0
local staminaActiveAt = 0
local lastUseLit = -1
local hintState = { text = nil :: string?, key = nil :: string? }
local hintToken = 0
local hitToken = 0
local coreTokens: { [string]: number } = {}
local lastResetAllowed: boolean? = nil
local lastMouseHidden: boolean? = nil
local vignetteCache: { [Instance]: number } = {}
local visibleCache: { [Instance]: boolean } = {}
local infoClock = 0
local outside = false
local outsideBy = 0
local topSuppressed: { [string]: boolean } = {}
local Controllers: any = nil
local roundsSnapshot: number? = nil -- RoundsPlayed at this round's Countdown (RoundService adds one at the horn)
local lastHealthRise = 0 -- os.clock() when health last went up (healing)
local shimmerPhase = 0
local reasonState = { text = nil :: string?, danger = false }
local descShown: { [string]: number } = {}
local drankThisRound = false -- a drink retired the water marker until thirst drops under waterRearmBelow
local waterRearmBelow = 0
local thirstyCardRound = false -- the THIRSTY card showed this round: the water marker comes with it
local waterPulseUntil = 0
local waterCache = { at = 0, point = nil :: Vector3?, distance = 0 }
local lastThirst: number? = nil
local interactSeen: { text: string, key: string?, at: number }? = nil
local actionSeen: { segments: { any }, at: number }? = nil
local actionState = { sig = nil :: string?, token = 0, ref = nil :: any, refText = nil :: string?, parsed = nil :: { any }?,
	sigFor = nil :: { any }?, sigText = nil :: string? } -- sigFor / sigText: the segments the signature was last built from
local actionPool = { keys = {} :: { any }, texts = {} :: { any }, used = {} :: { any } }
local flashHint: { segments: { any }, untilT: number }? = nil -- a short HUD-side hint, e.g. [SHIFT] SPRINT at the horn
local lastCardUp: boolean? = nil -- a death, result or victory card had the screen last frame (update)
-- ProximityPrompts in the Custom style, drawn in the interaction hint's place (the newest one shown has it)
local prompts: { { prompt: ProximityPrompt, input: Enum.ProximityPromptInputType, connections: { RBXScriptConnection } } } = {}
local promptHold: { prompt: ProximityPrompt, t0: number, duration: number }? = nil
local promptLineCache = { prompt = nil :: ProximityPrompt?, action = "", object = "", attribute = nil :: any, line = "" }
local tapPrompt: ProximityPrompt? = nil -- the prompt a finger is holding through the tap button
local dummyBars: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- restyled practice-dummy bars

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------
local function timeScale(): number
	if Config.IsStudio then
		local s = tonumber(Config.Round.StudioTimeScale)
		if s and s > 0 then
			return s
		end
	end
	return 1
end

local function setVisible(obj: GuiObject, on: boolean)
	if visibleCache[obj] ~= on then
		visibleCache[obj] = on
		obj.Visible = on
	end
end

-- RichText: a number in RobotoMono inside a line of words, and a word in the dim tone.
local function mono(text: string | number): string
	return "<font family=\"" .. MONO_FAMILY .. "\">" .. tostring(text) .. "</font>"
end

local DIM_HEX = Theme.hex(C.Ink2)
local function dimmed(text: string): string
	return "<font color=\"" .. DIM_HEX .. "\">" .. text .. "</font>"
end

-- Fades an icon made by QuietUI.icon (its Ink parts, and the shade copy under them) for a moment's transition.
-- To keep an icon dim, tint it (QuietUI.tint): its parts overlap, and transparency would show the overlaps.
local function iconTransparency(icon: Instance, t: number)
	for _, layer in ipairs(icon:GetChildren()) do
		local base = if layer.Name == "Drop" then 0.45 else 0
		for _, part in ipairs(layer:GetChildren()) do
			if part:IsA("GuiObject") then
				part.BackgroundTransparency = base + (1 - base) * t
			end
		end
	end
end

-- SetCore can fail until the core scripts register; retry, and let a newer call supersede an older one
local function setCore(name: string, value: any)
	coreTokens[name] = (coreTokens[name] or 0) + 1
	local token = coreTokens[name]
	task.spawn(function()
		for _ = 1, 60 do
			if coreTokens[name] ~= token then
				return
			end
			local ok = pcall(function()
				StarterGui:SetCore(name, value)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

local function setCoreGui(kind: Enum.CoreGuiType, enabled: boolean)
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(kind, enabled)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

local function setVignette(holder: Instance, alpha: number)
	local a = math.clamp(alpha, 0, 1)
	local last = vignetteCache[holder]
	if last and math.abs(last - a) < 0.004 then
		return
	end
	vignetteCache[holder] = a
	local t = 1 - a
	for _, edge in ipairs(holder:GetChildren()) do
		if edge:IsA("GuiObject") then
			edge.BackgroundTransparency = t
		end
	end
end

local function arenaCenter(): Vector3
	local arena = workspace:FindFirstChild("Arena")
	local center = arena and arena:GetAttribute("Center")
	if typeof(center) == "Vector3" then
		return center
	end
	return ArenaLayout.Center
end

local function bearing(from: Vector3, to: Vector3): (number, number)
	local dx, dz = to.X - from.X, to.Z - from.Z
	return math.deg(math.atan2(dx, -dz)) % 360, math.sqrt(dx * dx + dz * dz)
end

local function wrapDelta(angle: number, heading: number): number
	return ((angle - heading + 540) % 360) - 180
end

-- Real rounds played. During a round it is the value read at the Countdown, so round 3 still counts as new.
local function roundsPlayed(): number
	local live = math.max(0, math.floor(tonumber(player:GetAttribute("RoundsPlayed")) or 0))
	if roundsSnapshot ~= nil then
		return math.min(live, roundsSnapshot)
	end
	return live
end

-- Q1: Guidance. The player's own setting (when SettingsController adds one) wins over Config.Guidance.Mode.
local function guidanceMode(): string
	local setting = (ClientState.settings :: any).guidance
	if type(setting) == "string" then
		local m = string.lower(setting)
		if m == "off" then
			return "Off"
		elseif m == "always" then
			return "Always"
		elseif m == "auto" then
			return "Auto"
		end
	elseif type(setting) == "number" then
		local n = math.floor(setting + 0.5) -- a 3-step slider: 0 = Off, 1 = Auto, 2 = Always
		return if n <= 0 then "Off" elseif n >= 2 then "Always" else "Auto"
	end
	local g = Config.Guidance
	local mode = if type(g) == "table" then g.Mode elseif type(g) == "string" then g else "Auto"
	return if mode == "Off" or mode == "Always" then mode else "Auto"
end

local function guidanceOn(): boolean
	-- one rule for every hint: ClientState.guidanceOn (settings.guidance + the NewPlayer flag) when it exists
	local shared = (ClientState :: any).guidanceOn
	if type(shared) == "function" then
		local ok, on = pcall(shared)
		if ok and type(on) == "boolean" then
			return on
		end
	end
	local mode = guidanceMode()
	if mode == "Off" then
		return false
	elseif mode == "Always" then
		return true
	end
	-- during a round the server's verdict at the Countdown (RoundService: NewPlayer) wins
	local flag = player:GetAttribute("NewPlayer")
	if roundsSnapshot ~= nil and type(flag) == "boolean" then
		return flag
	end
	local limit = tonumber(type(Config.Guidance) == "table" and Config.Guidance.NewPlayerRounds) or 3
	return roundsPlayed() < limit
end

-- Shared.Glyphs (QW13) names each platform's buttons; until it exists, Xbox names.
local glyphs: any = false
local function glyphFor(keyCode: Enum.KeyCode, fallback: string): string
	if glyphs == false then
		glyphs = nil
		local module = Shared:FindFirstChild("Glyphs")
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				glyphs = result
			end
		end
	end
	if glyphs and type(glyphs.forKey) == "function" then
		local ok, result = pcall(glyphs.forKey, keyCode)
		if ok then
			if type(result) == "string" and result ~= "" then
				return result
			elseif type(result) == "table" then
				local text = result.text or result.name or result.label
				if type(text) == "string" and text ~= "" then
					return text
				end
			end
		end
	end
	return fallback
end

-- This device's button for "Interact" (drink, fill, open) or "Use" (attack, eat, bandage), as hints print it.
local function keyName(action: string): string
	glyphFor(Enum.KeyCode.E, "E") -- looks Shared.Glyphs up once
	if glyphs and type(glyphs.forAction) == "function" then
		local ok, name = pcall(glyphs.forAction, if action == "Interact" then "Drink" else "Attack")
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	if Input.isTouch() then
		return if action == "Interact" then "DRINK" else "ATTACK"
	end
	if Input.isGamepad() then
		if action == "Interact" then
			return glyphFor(Enum.KeyCode.ButtonX, "X")
		end
		return glyphFor(Enum.KeyCode.ButtonR2, "RT")
	end
	return if action == "Interact" then "E" else "LMB"
end

--------------------------------------------------------------------------------------------------------------------
-- Vitals
--------------------------------------------------------------------------------------------------------------------
local function makeStat(name: string)
	local row = R.vitals:WaitForChild(name)
	local s = {
		row = row,
		label = row:WaitForChild("Label"),
		value = row:WaitForChild("Value"),
		track = row:WaitForChild("Track"),
		fill = row.Track:WaitForChild("Fill"),
		ghost = row.Track:WaitForChild("Ghost"),
		alpha = 1,
		state = "", -- "rest" | "active" | "low" | "danger" (QuietUI.barState); updateVitalStates sets it
		litUntil = 0, -- os.clock() until which a value that just changed stays in full ink
		ghostToken = 0,
		fillT = -1,
		vis = -1,
	}
	stats[name] = s
end

local function setStat(name: string, alpha: number, valueText: string, instant: boolean?)
	local s = stats[name]
	if not s then
		return
	end
	local a = math.clamp(alpha, 0, 1)
	if math.abs(a - s.alpha) > 0.0005 or instant then
		local dropping = a < s.alpha
		-- health that moved either way, and a meal or a drink, light the row for a few seconds (a meter that only
		-- drains stays at rest until it reaches the healing tick)
		if not instant and (name == "Health" or a > s.alpha + 0.015) then
			s.litUntil = os.clock() + IDLE
		end
		s.alpha = a
		if instant then
			s.ghostToken += 1
			s.fill.Size = UDim2.fromScale(a, 1)
			s.ghost.Size = UDim2.fromScale(a, 1)
		else
			QuietUI.tween(s.fill, Theme.Tween.Bar, { Size = UDim2.fromScale(a, 1) })
			if dropping then
				-- the ghost holds where the line was, then catches up: you see how much you just lost
				s.ghostToken += 1
				local token = s.ghostToken
				task.delay(0.45, function()
					if s.ghostToken == token then
						QuietUI.tween(s.ghost, Theme.Tween.Ghost, { Size = UDim2.fromScale(s.alpha, 1) })
					end
				end)
			else
				s.ghostToken += 1
				s.ghost.Size = UDim2.fromScale(a, 1)
			end
		end
	end
	if s.value.Text ~= valueText then
		s.value.Text = valueText
	end
end

local function updateHealth(instant: boolean?)
	local a = health / math.max(1, maxHealth)
	setStat("Health", a, tostring(math.max(0, math.ceil(health))), instant)
end

local function updateSurvival(instant: boolean?)
	local hunger = math.clamp(tonumber(player:GetAttribute("Hunger")) or 100, 0, 100)
	local thirst = math.clamp(tonumber(player:GetAttribute("Thirst")) or 100, 0, 100)
	setStat("Hunger", hunger / 100, tostring(math.floor(hunger + 0.5)), instant)
	setStat("Thirst", thirst / 100, tostring(math.floor(thirst + 0.5)), instant)
end

-- Each row's Quiet state, and the fill's own transparency (rest, the low pulse, the stamina fade). Every frame.
--   health:  danger (Red) at or under Config.Feedback.LowHealth, and while you are outside the border; active (ink)
--            while it is not full or has just changed; else at rest
--   hunger, thirst:  low (Sun) at or under the healing tick (Config.Survival.RegenMinStat: health no longer comes
--            back), pulsing at a quarter and under; active for a few seconds after a meal or a drink; else at rest
--   stamina: low (Sun) while exhausted, else active (the whole row fades out when it is not in use)
local function updateVitalStates(t: number, combat: boolean)
	for name, s in pairs(stats) do
		local state = "rest"
		local pulse = false
		if name == "Health" then
			local low = health > 0 and s.alpha <= LOW.Health
			if low or (outside and combat) then
				state, pulse = "danger", low
			elseif s.alpha < 0.999 or t < s.litUntil then
				state = "active"
			end
		elseif name == "Stamina" then
			state = if ClientState.exhausted == true then "low" else "active"
		elseif s.alpha <= REGEN_MIN / 100 then
			state, pulse = "low", s.alpha <= (LOW[name] or 0.25)
		elseif t < s.litUntil then
			state = "active"
		end
		if state ~= s.state then
			s.state = state
			QuietUI.barState(s.row, state)
			s.vis = -1 -- (barState wrote the number's transparency: the stamina fade writes its own again)
			s.fillT = -1
		end
		local base = if state == "rest" then T.TextRest else 0
		if pulse and not reducedMotion then
			base = 0.45 * (0.5 + 0.5 * math.sin(t * 5))
		end
		local vis = if name == "Stamina" then staminaVis else 1
		local target = 1 - (1 - base) * vis
		if math.abs(target - s.fillT) > 0.01 then
			s.fillT = target
			s.fill.BackgroundTransparency = target
		end
	end
end

-- QW5: why health isn't coming back, only when a meter is the reason. Red when a meter is empty (you lose health).
local function updateReason(combat: boolean)
	local label = R.reason
	if not label then
		return
	end
	local text: string? = nil
	local danger = false
	if combat and health > 0 then
		local hunger = math.clamp(tonumber(player:GetAttribute("Hunger")) or 100, 0, 100)
		local thirst = math.clamp(tonumber(player:GetAttribute("Thirst")) or 100, 0, 100)
		local starving, dry = hunger <= 0, thirst <= 0
		if starving or dry then
			local what = if starving and dry then "DEHYDRATED  ·  STARVING" elseif dry then "DEHYDRATED" else "STARVING"
			text, danger = what .. "  ·  LOSING HEALTH", true
		elseif health < 0.9 * maxHealth then
			-- the server says why (PlayerService Regen: "ok" | "hunger" | "thirst" | "both" | "zero" | ""); the meters you
			-- can see fill in a tick it hasn't caught up with yet. "ok" means health is coming back: nothing to say.
			local regen = player:GetAttribute("Regen")
			local hungry, thirsty = false, false
			if regen ~= "ok" then
				hungry = regen == "hunger" or regen == "both" or hunger <= REGEN_MIN
				thirsty = regen == "thirst" or regen == "both" or thirst <= REGEN_MIN
			end
			if hungry or thirsty then
				-- the reason in Sun, like the line of the meter that needs filling
				local function word(w: string): string
					return string.format("<font color=\"%s\">%s</font>", Theme.hex(C.Sun), w)
				end
				local what = if hungry and thirsty then word("HUNGRY") .. " AND " .. word("THIRSTY")
					elseif thirsty then word("THIRSTY")
					else word("HUNGRY")
				text = "NOT HEALING  ·  " .. what
			end
		end
	end
	if text == reasonState.text and danger == reasonState.danger then
		return
	end
	reasonState.text, reasonState.danger = text, danger
	label.Visible = text ~= nil
	if text then
		label.Text = text
		label.TextColor3 = if danger then C.Red else C.Ink
	end
end

-- QW5: a slow sweep over the health line while health is coming back.
local function updateShimmer(dt: number, combat: boolean)
	local shimmer = R.shimmer
	if not shimmer then
		return
	end
	local on = combat and health > 0 and health < maxHealth - 0.05 and os.clock() - lastHealthRise < 1.2 and not reducedMotion
	if shimmer.Visible ~= on then
		shimmer.Visible = on
	end
	if on and R.shimmerGradient then
		shimmerPhase = (shimmerPhase + dt / 2.6) % 1
		R.shimmerGradient.Offset = Vector2.new(-0.75 + 1.5 * shimmerPhase, 0)
	end
end

-- Armour: a thin line under the health line for as long as you wear some. Its share ("ARMOR 15%") is written beside
-- the health number for a few seconds when it changes (desktop only: on a touch screen that place is the compass's).
local function updateArmor()
	local id = player:GetAttribute("Armor")
	local def = if type(id) == "string" and id ~= "" then ItemDefs.get(id) else nil
	local text: string? = nil
	if def and type(def.damageMultiplier) == "number" then
		text = string.format("ARMOR %d%%", math.floor((1 - def.damageMultiplier) * 100 + 0.5))
	end
	if text ~= armorText then
		armorText = text
		armorNoteUntil = if text then os.clock() + IDLE + 2 else 0
		local s = stats.Health
		if text and s then
			s.label.Text = text -- (taken off, the old words stay while they fade)
		end
	end
	if R.armorLine then
		R.armorLine.Visible = armorText ~= nil
	end
end

local function updateArmorNote(t: number)
	local s = stats.Health
	if not s then
		return
	end
	local shown = armorText ~= nil and layoutKey == "Desktop" and t < armorNoteUntil
	if shown ~= armorNoteShown then
		armorNoteShown = shown
		QuietUI.fadeText(s.label, shown)
	end
end

local function bindCharacter(character: Model?)
	for _, connection in ipairs(charConnections) do
		connection:Disconnect()
	end
	table.clear(charConnections)
	humanoid = nil
	if not character then
		return
	end
	task.spawn(function()
		local hum = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if not hum or not hum:IsA("Humanoid") or player.Character ~= character then
			return
		end
		humanoid = hum
		local function onHealth()
			local before = health
			health = hum.Health
			maxHealth = math.max(1, hum.MaxHealth)
			if health > before + 1e-3 then
				lastHealthRise = os.clock()
			elseif health < before - 1e-3 then
				lastHealthRise = 0
			end
			updateHealth(false)
		end
		table.insert(charConnections, hum.HealthChanged:Connect(onHealth))
		table.insert(charConnections, hum:GetPropertyChangedSignal("MaxHealth"):Connect(onHealth))
		health = hum.Health
		maxHealth = math.max(1, hum.MaxHealth)
		updateHealth(true)
	end)
end

-- Stamina shows only while it is in use: the line, its track and its number fade together.
local function updateStamina(dt: number, t: number)
	local s = stats.Stamina
	if not s then
		return
	end
	local st = math.clamp(tonumber(ClientState.stamina) or 1, 0, 1)
	local exhausted = ClientState.exhausted == true
	if st < 0.995 or exhausted or ClientState.moveState == "Sprint" then
		staminaActiveAt = t
	end
	local want = if t - staminaActiveAt < 1.4 then 1 else 0
	staminaVis += (want - staminaVis) * Util.damp(if want > staminaVis then 10 else 3.5, dt)
	if math.abs(st - s.alpha) > 0.001 then
		s.alpha = st
		s.fill.Size = UDim2.fromScale(st, 1)
	end
	local text = tostring(math.floor(st * 100 + 0.5))
	if s.value.Text ~= text then
		s.value.Text = text
	end
	if math.abs(staminaVis - s.vis) > 0.01 then
		s.vis = staminaVis
		local hidden = 1 - staminaVis
		QuietUI.textTransparency(s.value, hidden)
		s.track.BackgroundTransparency = T.BarTrack + (1 - T.BarTrack) * hidden
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Hotbar
--------------------------------------------------------------------------------------------------------------------
local function clearViewport(viewport: ViewportFrame)
	viewport.CurrentCamera = nil
	for _, child in ipairs(viewport:GetChildren()) do
		child:Destroy()
	end
end

-- Puts the item's world model in the viewport, longest axis on the diagonal, framed by its bounding box.
local function frameIcon(viewport: ViewportFrame, itemId: string): boolean
	local ok, model = pcall(ItemModels.build, itemId, "world")
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false
	end
	local framed = pcall(function()
		local cf, size = model:GetBoundingBox()
		local align
		if size.X >= size.Y and size.X >= size.Z then
			align = CFrame.identity
		elseif size.Y >= size.Z then
			align = CFrame.Angles(0, 0, -math.pi / 2)
		else
			align = CFrame.Angles(0, math.pi / 2, 0)
		end
		local rot = CFrame.Angles(0, math.rad(24), 0) * CFrame.Angles(0, 0, math.rad(42)) * align
		local offset = model:GetPivot():ToObjectSpace(cf)
		model:PivotTo(rot * offset:Inverse())
		local h = size / 2
		local rx, ry, rz = rot.RightVector, rot.UpVector, -rot.LookVector
		local ex = math.abs(rx.X) * h.X + math.abs(ry.X) * h.Y + math.abs(rz.X) * h.Z
		local ey = math.abs(rx.Y) * h.X + math.abs(ry.Y) * h.Y + math.abs(rz.Y) * h.Z
		local ez = math.abs(rx.Z) * h.X + math.abs(ry.Z) * h.Y + math.abs(rz.Z) * h.Z
		local fov = 30
		local extent = math.max(ex, ey, 0.2) * 1.16
		local distance = extent / math.tan(math.rad(fov / 2)) + ez
		local camera = Instance.new("Camera")
		camera.FieldOfView = fov
		camera.CFrame = CFrame.lookAt(Vector3.new(0, distance * 0.12, distance), Vector3.zero)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end)
	if not framed then
		model:Destroy()
		return false
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	model.Parent = viewport
	return true
end

-- One cell, the Quiet way: no box. The cell in hand has a bigger picture, the line under it and its number in full
-- ink. An empty cell is a small ring. At rest (hotbarRest: keyboard and gamepad, a few seconds after the last
-- change) the cells that are not in hand dim.
local function paintSlot(i: number)
	local r = slotRefs[i]
	if not r then
		return
	end
	local empty = r.itemId == nil
	local selected = i == equippedSlot and not empty
	local rest = hotbarRest and not selected
	local px = if selected then ICON_SELECTED else ICON
	QuietUI.tween(r.viewport, Theme.Tween.Fast, {
		Size = UDim2.fromOffset(px, px),
		ImageTransparency = if selected then 0 elseif rest then 0.32 else 0.08,
	})
	r.key.TextColor3 = if selected then C.Ink else C.Ink2
	QuietUI.textTransparency(r.key, if selected then 0 elseif rest then T.TextFaint else 0.12)
	QuietUI.textTransparency(r.count, if rest then T.TextDim else 0)
	if r.fallback.Visible then
		QuietUI.textTransparency(r.fallback, if rest then T.TextDim else 0)
		r.fallback.TextColor3 = if selected then C.Ink else C.Ink2
	end
	if r.under then
		r.under.Visible = selected
	end
	if r.ring then
		r.ring.Visible = empty
		if r.ringInk then
			r.ringInk.Transparency = if rest then 0.6 else 0.25
		end
	end
end

-- Lights every cell again (a pickup, a change of hand, a refused empty cell); they dim IDLE + 2 s later.
local function wakeHotbar()
	hotbarLitUntil = os.clock() + IDLE + 2
	if hotbarRest then
		hotbarRest = false
		for i = 1, SLOTS do
			paintSlot(i)
		end
	end
end

local function updateHotbarRest(t: number)
	-- a touch screen's cells are buttons: they stay lit
	local rest = not touchLayout and t > hotbarLitUntil
	if rest ~= hotbarRest then
		hotbarRest = rest
		for i = 1, SLOTS do
			paintSlot(i)
		end
	end
end

-- Returns true when the cell's item or count changed.
local function setSlot(i: number, data: any): boolean
	local r = slotRefs[i]
	if not r then
		return false
	end
	local id = if type(data) == "table" and type(data.id) == "string" then data.id else nil
	local count = if id then math.max(1, math.floor(tonumber(data.count) or 1)) else 0
	local changed = id ~= r.itemId or count ~= r.amount
	if id ~= r.itemId then
		r.itemId = id
		clearViewport(r.viewport)
		local def = ItemDefs.get(id)
		local hasIcon = id ~= nil and frameIcon(r.viewport, id)
		r.fallback.Visible = id ~= nil and not hasIcon
		r.fallback.Text = if def then string.upper(def.name) elseif id then string.upper(id) else ""
	end
	r.amount = count
	-- (no rarity colours on the HUD: one ink. The cell's Rarity line stays hidden.)
	r.rarity.Visible = false
	r.count.Text = if count > 1 then tostring(count) else ""
	paintSlot(i)
	return changed
end

-- The name of what you just took in hand, above the hotbar for a moment (with what kind of thing it is; and, the
-- first few times for a new player, what it is for).
local function flashItemName(itemId: string?)
	local group = R.itemName
	if not group then
		return
	end
	itemNameToken += 1
	local token = itemNameToken
	local def = ItemDefs.get(itemId)
	if not def then
		QuietUI.tween(group, Theme.Tween.Fast, { GroupTransparency = 1 })
		return
	end
	wakeHotbar()
	R.itemTitle.Text = def.name
	R.itemSub.Text = KIND_LABEL[def.kind] or ""
	-- QW2: what it's for, the first few times each item shows (Guidance)
	local showDesc = false
	if R.itemDesc and type(def.desc) == "string" and def.desc ~= "" and guidanceOn() then
		local shown = descShown[def.id] or 0
		if shown < DESC_SHOWS then
			descShown[def.id] = shown + 1
			showDesc = true
			R.itemDesc.Text = def.desc
		end
	end
	if R.itemDesc then
		R.itemDesc.Visible = showDesc
	end
	group.Size = UDim2.fromOffset(400, if showDesc then 60 else 42)
	if reducedMotion then
		group.Position = UDim2.new(0.5, 0, 0, -4)
		group.GroupTransparency = 0
	else
		group.GroupTransparency = 1
		group.Position = UDim2.new(0.5, 0, 0, 2)
		QuietUI.tween(group, Theme.Tween.Normal, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, -4) })
	end
	task.delay(if showDesc then 4.2 else 2.4, function()
		if token == itemNameToken then
			QuietUI.tween(group, Theme.Tween.FadeOut, { GroupTransparency = 1 })
		end
	end)
end

local function onInventory(inventory: any)
	if type(inventory) ~= "table" then
		return
	end
	local slots = if type(inventory.slots) == "table" then inventory.slots else {}
	local newEquipped = math.floor(tonumber(inventory.equipped) or 0)
	local equipChanged = newEquipped ~= equippedSlot
	equippedSlot = newEquipped
	local changed = equipChanged
	for i = 1, SLOTS do
		if setSlot(i, slots[i]) then
			changed = true
		end
	end
	if changed then
		wakeHotbar()
	end
end

local function setSlotSize(px: number)
	slotSize = px
	for i = 1, SLOTS do
		slotRefs[i].button.Size = UDim2.fromOffset(px, px)
	end
	R.hotbar.Size = UDim2.fromOffset(SLOTS * px + (SLOTS - 1) * SLOT_GAP, px + 8)
	R.slots.Size = UDim2.new(1, 0, 0, px)
	R.prevHint.Position = UDim2.new(0, -8, 1, -px / 2)
	R.nextHint.Position = UDim2.new(1, 8, 1, -px / 2)
end

-- Touch screens: keep the hotbar left of the action buttons that share its row (and Roblox's jump button).
local function placeHotbar()
	local hotbar = R.hotbar
	if not hotbar or not hud then
		return
	end
	if not touchLayout then
		if hotbar.Position ~= UDim2.fromScale(0.5, 1) then
			hotbar.Position = UDim2.fromScale(0.5, 1)
		end
		return
	end
	local s = getScale()
	local hbPos, hbSize = hotbar.AbsolutePosition, hotbar.AbsoluteSize
	if hbSize.X <= 0 then
		return
	end
	local bandTop, bandBottom = hbPos.Y - 20 * s, hbPos.Y + hbSize.Y + 4
	local clusterLeft = math.huge
	local function consider(obj: Instance)
		if not obj:IsA("GuiObject") then
			return
		end
		local p, sz = obj.AbsolutePosition, obj.AbsoluteSize
		if sz.X > 0 and p.Y + sz.Y >= bandTop and p.Y <= bandBottom then
			clusterLeft = math.min(clusterLeft, p.X)
		end
	end
	local pg = playerGui
	local touchGui = pg and pg:FindFirstChild("TouchControls")
	if touchGui then
		for _, b in ipairs(touchGui:GetChildren()) do
			consider(b)
		end
	end
	local robloxTouch = pg and pg:FindFirstChild("TouchGui")
	local jump = robloxTouch and robloxTouch:FindFirstChild("JumpButton", true)
	if jump then
		consider(jump)
	end
	-- Always reserve where ATTACK and DRINK sit, bound or not: DRINK only appears near water and is the leftmost
	-- button in this row, so the hotbar must not slide around when it comes and goes.
	local right = hud.AbsolutePosition.X + hud.AbsoluteSize.X
	for _, name in ipairs({ "Attack", "Drink" }) do
		local pos, size = Input.getTouchLayout(name)
		if pos.X.Scale == 1 then
			clusterLeft = math.min(clusterLeft, right + pos.X.Offset - size / 2)
		end
	end
	local currentOffset = hotbar.Position.X.Offset
	local centred = hbPos.X + hbSize.X / 2 - currentOffset * s
	local center = centred
	if clusterLeft < math.huge then
		center = math.min(center, clusterLeft - BUTTON_MARGIN * s - hbSize.X / 2)
	end
	center = math.max(center, hud.AbsolutePosition.X + 8 * s + hbSize.X / 2)
	local offset = math.floor((center - centred) / s + 0.5)
	if math.abs(offset - currentOffset) >= 1 then
		hotbar.Position = UDim2.new(0.5, offset, 1, 0)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Kill feed
--------------------------------------------------------------------------------------------------------------------
-- A line of the feed is plain text on the picture: "Kestrel [blade] Rowan", "Orla  was caught by the border". It
-- fades in, dims to "old" after a few seconds and fades out at the end of its life (at once when newer lines push
-- it out). updateFeed drives every line each frame from its age: there are no tweens to keep track of.
local function endEntry(entry: any, now: number, fast: boolean?)
	if entry.dieAt then
		return
	end
	entry.dieAt = now
	entry.dieTime = if fast then FEED_FAST else FEED_OUT
end

-- fade: 0 shown .. 1 gone.  rest: 0 new .. 1 old.
local function paintEntry(entry: any, fade: number, rest: number)
	local t = 1 - (1 - fade) * (1 - T.TextFaint * rest)
	QuietUI.textTransparency(entry.text, t)
	if entry.second then
		QuietUI.textTransparency(entry.second, t)
	end
	if entry.icon then
		iconTransparency(entry.icon, fade)
		if rest ~= entry.restShown then
			QuietUI.tint(entry.icon, C.Ink:Lerp(C.TextFaint, rest)) -- (an icon dims by colour: its parts overlap)
		end
	end
	entry.mark.BackgroundTransparency = t
	entry.fadeShown, entry.restShown = fade, rest
end

local function updateFeed()
	if #feed == 0 then
		return
	end
	local now = os.clock()
	for i = #feed, 1, -1 do
		local entry = feed[i]
		local age = now - entry.born
		if not entry.dieAt and age >= entry.life then
			endEntry(entry, now, false)
		end
		local fade = if age < FEED_IN then 1 - age / FEED_IN else 0
		local rest = math.clamp((age - FEED_REST_AT) / FEED_REST_TIME, 0, 1)
		local gone = false
		if entry.dieAt then
			local k = math.clamp((now - entry.dieAt) / math.max(0.01, entry.dieTime), 0, 1)
			fade += (1 - fade) * k
			gone = k >= 1
		end
		if gone then
			table.remove(feed, i)
			entry.frame:Destroy()
		else
			if reducedMotion then
				fade = if fade > 0.5 then 1 else 0
				rest = if rest > 0.5 then 1 else 0
			end
			if math.abs(fade - entry.fadeShown) > 0.01 or math.abs(rest - entry.restShown) > 0.01 then
				paintEntry(entry, fade, rest)
			end
		end
	end
end

local function addKill(data: any)
	if type(data) ~= "table" or not R.killTemplate then
		return
	end
	local victim = if type(data.victim) == "string" then data.victim else "Someone"
	local killer = if type(data.killer) == "string" and data.killer ~= "" then data.killer else nil
	local cause = if type(data.cause) == "string" then data.cause else "Other"
	local me = player.DisplayName
	-- "you" is decided by UserId when the payload carries one (killerUserId / victimUserId): display names are not
	-- unique. A payload without ids falls back to the names.
	local function mine(n: string?, id: any): boolean
		local userId = tonumber(id)
		if userId and userId ~= 0 then
			return userId == player.UserId
		end
		return n ~= nil and (n == me or n == player.Name)
	end
	local victimMine = mine(victim, data.victimUserId)
	local killerMine = killer ~= nil and mine(killer, data.killerUserId)
	-- your own name is in Sun, either way round (Red is kept for a danger state)
	local function name(n: string, isMine: boolean): string
		local s = Theme.escape(n)
		if isMine then
			return string.format("<font color=\"%s\">%s</font>", Theme.hex(C.Sun), s)
		end
		return s
	end
	local involved = victimMine or killerMine
	local first: string
	local second: string? = nil
	if type(data.text) == "string" and data.text ~= "" and not killer then
		first = name(victim, victimMine) .. "  " .. dimmed(Theme.escape(data.text))
	elseif killer then
		-- two names with a small blade between them (the weapon is not named: the line stays short)
		first, second = name(killer, killerMine), name(victim, victimMine)
	else
		first = name(victim, victimMine) .. "  " .. dimmed(CAUSE_ALONE[cause] or "was eliminated")
	end

	local frame = R.killTemplate:Clone()
	local textLabel = frame:FindFirstChild("Text")
	local mark = frame:FindFirstChild("Mark")
	if not (textLabel and textLabel:IsA("TextLabel") and mark and mark:IsA("GuiObject")) then
		frame:Destroy()
		return
	end
	feedCounter += 1
	frame.Name = "Kill" .. feedCounter
	frame.LayoutOrder = feedCounter
	textLabel.Text = first
	mark.Visible = involved
	local icon: Frame? = nil
	local secondLabel: TextLabel? = nil
	if second then
		icon = QuietUI.icon("blade", { Name = "Blade", Px = 13, LayoutOrder = 3 })
		icon.Parent = frame
		local clone = textLabel:Clone()
		clone.Name = "Victim"
		clone.LayoutOrder = 4
		clone.Text = second
		clone.Parent = frame
		secondLabel = clone
	end
	local entry = {
		frame = frame,
		text = textLabel,
		second = secondLabel,
		icon = icon,
		mark = mark,
		born = os.clock(),
		life = if involved then 9 else 6.5,
		dieAt = nil :: number?,
		dieTime = FEED_OUT,
		fadeShown = -1,
		restShown = -1,
	}
	paintEntry(entry, 1, 0) -- it starts clear; updateFeed brings it in
	frame.Visible = true
	frame.Parent = R.killFeed
	table.insert(feed, entry)
	local layout = Theme.Layout and Theme.Layout[layoutKey]
	local limit = if layout and layout.KillFeed and layout.KillFeed.max then layout.KillFeed.max elseif touchLayout then 2 else 5
	local live = 0
	for _, e in ipairs(feed) do
		if not e.dieAt then
			live += 1
		end
	end
	local now = os.clock()
	for _, e in ipairs(feed) do
		if live <= limit then
			break
		end
		if not e.dieAt then
			endEntry(e, now, true)
			live -= 1
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Compass, clock, events
--------------------------------------------------------------------------------------------------------------------
local function collectCompass()
	table.clear(compassItems)
	for _, child in ipairs(R.ticks:GetChildren()) do
		local angle = child:GetAttribute("Angle")
		if type(angle) == "number" and child:IsA("GuiObject") then
			table.insert(compassItems, {
				inst = child,
				angle = angle,
				y = child.Position.Y,
				isLabel = child:IsA("TextLabel"),
				base = tonumber(child:GetAttribute("BaseTransparency")) or 0,
				fade = -1,
				visible = true,
			})
		end
	end
end

-- QW10: the nearest drinkable water, for a thirsty new player with nothing to drink (Guidance). Once the border
-- moves, water outside it is skipped.
local function carriesDrink(): boolean
	local slots = ClientState.inventory and ClientState.inventory.slots
	if type(slots) ~= "table" then
		return false
	end
	for _, slot in pairs(slots) do
		if type(slot) == "table" then
			local def = ItemDefs.get(slot.id)
			if def and def.kind == "Drink" then
				return true
			end
		end
	end
	return false
end

-- QW10 compass labels: a distance sits centred under its marker (UIBuilder builds it there; the compass no longer
-- clips, so one under a marker at the ribbon's end is whole). The water's and the Spire's must not run into each
-- other ("667 1m m", round-flow QA): where they would meet, the Spire's gives way. Widths come from the text
-- (RobotoMono, 0.6 em a character: a little generous), so nothing waits for the engine to lay a label out.
local compassSpire = { shown = false, x = 0, label = false, from = 0, to = 0, meters = -1, text = "" }

local function monoWidth(text: string, size: number): number
	return (utf8.len(text) or #text) * size * 0.6
end

-- Returns true when the Spire's distance has to give way to the water's.
local function updateWater(camPos: Vector3, heading: number, half: number, pxPerDeg: number, phase: string, combat: boolean, center: any, radius: number?): boolean
	local marker = R.waterMarker
	if not marker then
		return false
	end
	local show = false
	if combat and phase == "Active" and WaterPoints and not drankThisRound and guidanceOn() then
		local thirst = tonumber(player:GetAttribute("Thirst")) or 100
		show = (thirst < WATER_THIRST or thirstyCardRound) and not carriesDrink()
	end
	local now = os.clock()
	if show and now - waterCache.at > 0.5 then
		waterCache.at = now
		local accept = nil
		if typeof(center) == "Vector3" and radius then
			local limit = radius - 10
			accept = function(v: Vector3): boolean
				local dx, dz = v.X - center.X, v.Z - center.Z
				return dx * dx + dz * dz <= limit * limit
			end
		end
		local ok, point, distance = pcall(WaterPoints.nearest, camPos, accept)
		waterCache.point = if ok then point else nil
		waterCache.distance = if ok and type(distance) == "number" then distance else 0
	end
	local point = waterCache.point
	show = show and point ~= nil
	setVisible(marker, show)
	if not show or not point then
		return false
	end
	local wd = wrapDelta(bearing(camPos, point), heading)
	local atEdge = math.abs(wd) > half - 4
	local x = math.clamp(wd, -(half - 4), half - 4) * pxPerDeg
	marker.Position = UDim2.new(0.5, x, 0, MARKER_Y)
	-- it pulses while the THIRSTY card is up. Off the ribbon it waits at the edge, its distance with an arrow toward
	-- the water, so the number never disappears.
	local alpha = 0
	if now < waterPulseUntil and not reducedMotion then
		alpha = 0.5 * (0.5 + 0.5 * math.sin(now * 6))
	end
	R.waterTip.BackgroundTransparency = alpha
	R.waterBulb.BackgroundTransparency = alpha
	setVisible(R.waterDist, true)
	local meters = math.floor(waterCache.distance * STUD_TO_METERS + 0.5)
	local side = if not atEdge then 0 elseif wd < 0 then -1 else 1
	local text = if side < 0 then string.format("‹ %d m", meters)
		elseif side > 0 then string.format("%d m ›", meters)
		else string.format("%d m", meters)
	if R.waterDist.Text ~= text then
		R.waterDist.Text = text
	end
	-- the Spire's distance gives way where the two would meet under the line
	local halfWidth = monoWidth(text, R.waterDist.TextSize) / 2
	return compassSpire.label and x - halfWidth < compassSpire.to + 6 and compassSpire.from - 6 < x + halfWidth
end

local function updateCompass(camCF: CFrame, phase: string)
	local right = camCF.RightVector
	local heading = math.deg(math.atan2(right.Z, right.X)) % 360
	local pxPerDeg = COMPASS_WIDTH / COMPASS_SPAN
	local half = COMPASS_SPAN / 2
	if math.abs(heading - lastHeading) > 0.03 then
		lastHeading = heading
		for _, item in ipairs(compassItems) do
			local d = wrapDelta(item.angle, heading)
			local ad = math.abs(d)
			local show = ad <= half + 4
			if show ~= item.visible then
				item.visible = show
				item.inst.Visible = show
			end
			if show then
				item.inst.Position = UDim2.new(0.5, d * pxPerDeg, item.y.Scale, item.y.Offset)
				local fade = math.clamp((ad - (half - 26)) / 26, 0, 1)
				if math.abs(fade - item.fade) > 0.02 then
					item.fade = fade
					if item.isLabel then
						QuietUI.textTransparency(item.inst, fade) -- the letter and its dark stroke together
					else
						item.inst.BackgroundTransparency = item.base + (1 - item.base) * fade
					end
				end
			end
		end
	end

	local camPos = camCF.Position
	local combat = ClientState.inArena and ClientState.alive and not ClientState.spectating
	local center = GameState:GetAttribute("BorderCenter")
	local radius = tonumber(GameState:GetAttribute("BorderRadius"))

	-- QW10: how far the border's edge is once it has started to move, when you're within BORDER_NEAR_METERS of it
	-- (the round's own start radius is GameState.BorderStartRadius: small rounds start small, QW3)
	local borderText: string? = nil
	local edgeBearing: number? = nil
	local startRadius = tonumber(GameState:GetAttribute("BorderStartRadius")) or tonumber(Config.Border.StartRadius) or 640
	local moving = GameState:GetAttribute("BorderShrinking") == true or (radius ~= nil and radius < startRadius - 0.5)
	if combat and phase == "Active" and moving and not outside and typeof(center) == "Vector3" and radius then
		local dx, dz = camPos.X - center.X, camPos.Z - center.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		local meters = (radius - dist) * STUD_TO_METERS
		if meters <= BORDER_NEAR_METERS then
			borderText = string.format("BORDER %d m", math.max(0, math.floor(meters + 0.5)))
			-- the nearest point of the edge lies straight out from the centre, through you
			local ux = if dist > 0.5 then dx / dist else 0
			local uz = if dist > 0.5 then dz / dist else -1
			edgeBearing = bearing(camPos, Vector3.new(center.X + ux * radius, camPos.Y, center.Z + uz * radius))
		end
	end

	-- the Spire marker (clamped to the ribbon edge when it's behind you)
	local spireBearing, spireDistance = bearing(camPos, arenaCenter())
	local d = wrapDelta(spireBearing, heading)
	local showSpire = spireDistance > 30
	setVisible(R.spire, showSpire)
	compassSpire.shown, compassSpire.label = showSpire, false
	if showSpire then
		local edge = math.abs(d) > half - 4
		local x = math.clamp(d, -(half - 4), half - 4) * pxPerDeg
		R.spire.Position = UDim2.new(0.5, x, 0, MARKER_Y)
		compassSpire.x = x
		local feast = GameState:GetAttribute("ArenaEvent") == "Feast"
		local size = if feast and not reducedMotion then 7 + 2.5 * (0.5 + 0.5 * math.sin(os.clock() * 5)) else 7
		R.spireDiamond.Size = UDim2.fromOffset(size, size)
		R.spireDiamond.BackgroundTransparency = if edge then 0.45 else 0
		-- its distance sits centred under the marker while that is on the ribbon. Shown below, once the water's
		-- distance has had its say.
		if not edge then
			local meters = math.floor(spireDistance * STUD_TO_METERS + 0.5)
			if meters ~= compassSpire.meters then
				compassSpire.meters = meters
				compassSpire.text = string.format("%d m", meters)
				R.spireDist.Text = compassSpire.text
			end
			local halfWidth = monoWidth(compassSpire.text, R.spireDist.TextSize) / 2
			compassSpire.label, compassSpire.from, compassSpire.to = true, x - halfWidth, x + halfWidth
		end
	end

	-- the border's distance under the compass, and a tick on the ribbon toward its nearest edge
	if R.borderDist then
		setVisible(R.borderDist, borderText ~= nil)
		if borderText and R.borderDist.Text ~= borderText then
			R.borderDist.Text = borderText
		end
	end
	if R.edgeMarker then
		local showEdge = edgeBearing ~= nil
		setVisible(R.edgeMarker, showEdge)
		if showEdge then
			local ed = wrapDelta(edgeBearing :: number, heading)
			R.edgeMarker.Position = UDim2.new(0.5, math.clamp(ed, -(half - 4), half - 4) * pxPerDeg, 0, MARKER_Y)
			R.edgeTick.BackgroundTransparency = if math.abs(ed) > half - 4 then 0.45 else 0
		end
	end

	-- QW10: water for the thirsty (where its distance would meet the Spire's, the Spire's gives way)
	local spireYields = updateWater(camPos, heading, half, pxPerDeg, phase, combat, center, radius)
	if showSpire then
		setVisible(R.spireDist, compassSpire.label and not spireYields)
	end

	-- the border marker, only while you're outside it: the way back in. The compass line itself turns Red meanwhile.
	local showBorder = outside and phase == "Active" and typeof(center) == "Vector3"
	setVisible(R.borderMarker, showBorder)
	if showBorder then
		local b = bearing(camPos, center)
		local bd = wrapDelta(b, heading)
		R.borderMarker.Position = UDim2.new(0.5, math.clamp(bd, -(half - 4), half - 4) * pxPerDeg, 0, MARKER_Y)
	end
	if R.baseline and showBorder ~= baselineRed then
		baselineRed = showBorder
		R.baseline.BackgroundColor3 = if showBorder then C.Red else C.Ink
		R.baseline.BackgroundTransparency = if showBorder then 0.1 else 0.4 -- (0.4: as UIBuilder builds it)
	end
end

local function updateBorderState(phase: string)
	outside = false
	outsideBy = 0
	if phase ~= "Active" or not (ClientState.inArena and ClientState.alive) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local center = GameState:GetAttribute("BorderCenter")
	local radius = GameState:GetAttribute("BorderRadius")
	if not root or not root:IsA("BasePart") or typeof(center) ~= "Vector3" or type(radius) ~= "number" then
		return
	end
	local p = root.Position
	local dx, dz = p.X - center.X, p.Z - center.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > radius then
		outside = true
		outsideBy = distance - radius
	end
end

-- QW9: the event line always says what's next, in Shared.ThreatLine's format with Shared.Lore's names. Active threats
-- come first (the Last Stand, the moving border, its warning, the Offering), then the next scheduled beat, dimmed
-- while it is more than a minute away. Returns (text?, dim).
local UPCOMING = { RollCall = true, Offering = true, BorderMoves = true }
local function eventLine(now: number): (string?, boolean)
	local startedAt = tonumber(GameState:GetAttribute("RoundStartedAt")) or 0
	if startedAt <= 0 then
		return nil, false
	end
	local ts = timeScale()
	local elapsed = (now - startedAt) * ts
	local short = Theme.isSmallScreen()
	local toSpire = "Head for " .. Lore.Spire
	local shrinkStart = tonumber(Config.Border.ShrinkStartTime) or 600
	local shrinkEnd = shrinkStart + (tonumber(Config.Border.ShrinkDuration) or 230)
	local shrinking = GameState:GetAttribute("BorderShrinking") == true
	local radius = tonumber(GameState:GetAttribute("BorderRadius"))
	local finalRadius = tonumber(Config.Border.FinalRadius) or 35
	-- the Last Stand (QW14, Config.Round.LastStand): after the border has closed the ring keeps closing to nothing over
	-- Config.Border.LastStandDuration (ArenaService keeps BorderShrinking on meanwhile)
	local lastStand = GameState:GetAttribute("LastStand") == true or GameState:GetAttribute("ArenaEvent") == "LastStand"
		or (elapsed >= shrinkEnd and ((Config.Round.LastStand ~= false and shrinking) or (radius ~= nil and radius < finalRadius - 0.5)))
	if lastStand then
		local standEnd = shrinkEnd + (tonumber(Config.Border.LastStandDuration) or 55)
		-- a practice round's ring stops at Config.Border.PracticeLastStandRadius (ArenaService): stay inside it
		local floor = if GameState:GetAttribute("Practice") == true then tonumber(Config.Border.PracticeLastStandRadius) or 0 else 0
		return ThreatLine.line({
			name = "LastStand",
			action = if floor > 0 then "Stay inside the ring" else "The ring closes to nothing",
			seconds = if shrinking and elapsed < standEnd then (standEnd - elapsed) / ts else nil,
		}, short), false
	end
	if shrinking then
		return ThreatLine.line({ name = "Border", action = toSpire, seconds = math.max(0, shrinkEnd - elapsed) / ts }, short), false
	end
	-- this round's ring may first move before shrinkStart (a big ring creeps in early: ThreatLine.borderMovesAt); it
	-- is the final closing at shrinkStart that sends everyone to the centre
	local lead = tonumber(Config.Border.WarningLeadTime) or 30
	local movesAt = shrinkStart
	if type(ThreatLine.borderMovesAt) == "function" then
		movesAt = math.min(shrinkStart, tonumber(ThreatLine.borderMovesAt()) or shrinkStart)
	end
	-- (a head start of under 20 s is announced as the final closing itself, as ArenaService does)
	local creeping = movesAt < shrinkStart - 20
	if elapsed < movesAt and elapsed >= movesAt - lead then
		return ThreatLine.line({ name = "Border", verb = "moves", action = if creeping then nil else toSpire,
			seconds = (movesAt - elapsed) / ts }, short), false
	end
	if GameState:GetAttribute("ArenaEvent") == "Feast" then
		return ThreatLine.line({ name = "Offering", action = Lore.cap("Spire") .. " is restocked" }, short), false
	end
	local beat, inSeconds = ThreatLine.nextBeat(elapsed, UPCOMING)
	if not beat or not inSeconds then
		return nil, false
	end
	local seconds = inSeconds / ts
	local dim = seconds > 60
	if beat.key == "RollCall" then
		return ThreatLine.line({ name = Lore.bare("RollCall") .. " at " .. Lore.Dusk, seconds = seconds }, short), dim
	elseif beat.key == "Offering" then
		return ThreatLine.line({ name = "Offering", action = "Fresh gear at " .. Lore.Spire, seconds = seconds }, short), dim
	elseif beat.key == "BorderMoves" then
		return ThreatLine.line({ name = "Border", verb = "moves", action = if dim or creeping then nil else toSpire,
			seconds = seconds }, short), dim
	end
	return nil, false
end

local function updateInfo(now: number, phase: string)
	local eventText: string? = nil
	local eventDim = false
	if phase == "Active" then
		eventText, eventDim = eventLine(now)
	end
	-- one countdown at a time (round-flow QA): the round clock (the hard time limit) gives way while the event line
	-- counts down to something sooner, and comes back when the time limit is the next thing left
	local endsAt = tonumber(GameState:GetAttribute("PhaseEndsAt")) or 0
	local remaining = math.max(0, endsAt - now)
	local eventLeft: number? = nil
	if eventText then
		local m, s = string.match(eventText, "(%d+):(%d%d)$")
		if m and s then
			eventLeft = (tonumber(m) or 0) * 60 + (tonumber(s) or 0)
		end
	end
	local showTimer = phase == "Active" and endsAt > 0 and (eventLeft == nil or remaining <= eventLeft + 0.5)
	setVisible(R.timer, showTimer)
	setVisible(R.dot, showTimer)
	if showTimer then
		local text = Util.formatTime(remaining)
		if R.timer.Text ~= text then
			R.timer.Text = text
		end
		R.timer.TextColor3 = if remaining <= 60 then C.Warning else C.Text
	end
	local alive = math.floor(tonumber(GameState:GetAttribute("AliveCount")) or 0)
	local remainText = if phase == "Countdown"
		then string.format("<b>%d</b> %s", alive, if alive == 1 then "CONTENDER" else "CONTENDERS")
		else string.format("<b>%d</b> REMAIN", alive)
	if R.remain.Text ~= remainText then
		R.remain.Text = remainText
	end
	setVisible(R.practice, GameState:GetAttribute("Practice") == true)

	-- the event line and the border alert share one slot; being outside the border wins
	setVisible(R.event, eventText ~= nil and not outside)
	if eventText and R.event.Text ~= eventText then
		R.event.Text = eventText
	end
	if eventText then
		local color = if eventDim then C.TextDim else C.Warning
		if R.event.TextColor3 ~= color then
			R.event.TextColor3 = color
		end
	end

	setVisible(R.alert, outside)
	if outside then
		local meters = math.max(1, math.floor(outsideBy * STUD_TO_METERS + 0.5))
		local small = Theme.isSmallScreen()
		-- short screens get a single line so nothing crosses the crosshair
		local title = if small then string.format("OUTSIDE THE BORDER  ·  %d m", meters) else "OUTSIDE THE BORDER"
		if R.alertTitle.Text ~= title then
			R.alertTitle.Text = title
		end
		setVisible(R.alertSub, not small)
		if not small then
			local sub = string.format("Head back toward the marker  ·  %d m", meters)
			if R.alertSub.Text ~= sub then
				R.alertSub.Text = sub
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Centre: crosshair, hit marker, damage arcs, use ring, draw meter, interaction hint
--------------------------------------------------------------------------------------------------------------------
local function updateCrosshair(show: boolean)
	setVisible(R.cross, show)
	if not show then
		return
	end
	local id = ClientState.getEquippedItemId()
	local def = ItemDefs.get(id)
	local kind = def and def.kind
	local using = ClientState.useProgress ~= nil
	local ranged = kind == "Bow" or kind == "Throwable" or (def ~= nil and def.throwable == true and ClientState.aiming == true)
	setVisible(R.crossDot, not using)
	local showLines = ranged and not using
	for _, line in pairs(R.lines) do
		setVisible(line, showLines)
	end
	if showLines then
		-- the lines bracket the real spread cone: crosshairSpread is degrees / 7 (CombatController), drawn at the camera's FOV
		local spread = math.clamp(tonumber(ClientState.crosshairSpread) or 0, 0, 1)
		local cam = workspace.CurrentCamera
		local fov = if cam then cam.FieldOfView else 70
		local height = if cam then cam.ViewportSize.Y else 720
		local px = math.tan(math.rad(spread * 7)) / math.tan(math.rad(fov) / 2) * height / 2
		local gap = math.clamp(4 + px / math.max(getScale(), 0.01), 5, 60)
		R.lines.Up.Position = UDim2.fromOffset(0, -gap)
		R.lines.Down.Position = UDim2.fromOffset(0, gap)
		R.lines.Left.Position = UDim2.fromOffset(-gap, 0)
		R.lines.Right.Position = UDim2.fromOffset(gap, 0)
	end
end

local function showHit(info: any)
	if type(info) ~= "table" then
		return
	end
	hitToken += 1
	local token = hitToken
	local killed = info.killed == true
	local headshot = info.headshot == true
	local color = if killed then C.Gold elseif headshot then C.AccentSoft else C.Text -- (a kill was red: no red hit effects)
	local length = if killed then 13 elseif headshot then 10 else 8
	local from = if killed then 7 else 6
	local to = if killed then 13 else 9
	for name, dir in pairs(HIT_DIRS) do
		local tick = R.hit[name]
		local s = tick:FindFirstChildOfClass("UIStroke")
		tick.BackgroundColor3 = color
		tick.Size = UDim2.fromOffset(2, length)
		tick.BackgroundTransparency = 0
		tick.Position = UDim2.fromOffset(dir[1] * from, dir[2] * from)
		if s then
			s.Transparency = 0.45
		end
		Theme.tween(tick, Theme.Tween.Pop, { Position = UDim2.fromOffset(dir[1] * to, dir[2] * to) })
	end
	local hold = if killed then 0.42 elseif headshot then 0.2 else 0.12
	task.delay(hold, function()
		if token ~= hitToken then
			return
		end
		for name in pairs(HIT_DIRS) do
			local tick = R.hit[name]
			Theme.tween(tick, Theme.Tween.Normal, { BackgroundTransparency = 1 })
			local s = tick:FindFirstChildOfClass("UIStroke")
			if s then
				Theme.tween(s, Theme.Tween.Normal, { Transparency = 1 })
			end
		end
	end)
end

local function onDamage(info: any)
	if type(info) ~= "table" then
		return
	end
	local amount = tonumber(info.amount) or 0
	if amount <= 0 then
		return
	end
	local cause = info.cause
	local ticking = cause == "Starvation" or cause == "Dehydration" or cause == "Border"
	hurtAlpha = math.max(hurtAlpha, math.clamp(amount / 30, if ticking then 0.16 else 0.3, 0.8))
	local from = info.fromPosition
	if typeof(from) ~= "Vector3" or #damageDirs == 0 then
		return
	end
	local slot = nil
	for _, d in ipairs(damageDirs) do
		if d.active and d.from and (d.from - from).Magnitude < 6 then
			slot = d
			break
		end
	end
	if not slot then
		slot = damageDirs[nextDir]
		nextDir = nextDir % #damageDirs + 1
	end
	slot.active = true
	slot.from = from
	slot.t0 = os.clock()
	slot.strength = math.clamp(amount / 25, 0.45, 1)
	slot.life = if ticking then 1.15 else 1.7
	setVisible(slot.holder, true)
end

local function updateDamage(camCF: CFrame)
	local t = os.clock()
	for _, d in ipairs(damageDirs) do
		if d.active then
			local age = t - d.t0
			if age >= d.life then
				d.active = false
				setVisible(d.holder, false)
			else
				local rel = camCF:PointToObjectSpace(d.from)
				d.holder.Rotation = math.deg(math.atan2(rel.X, -rel.Z))
				local fadeIn = math.clamp(age / 0.08, 0, 1)
				local fadeOut = 1 - math.clamp((age - (d.life - 0.6)) / 0.6, 0, 1)
				local a = d.strength * fadeIn * fadeOut
				for _, seg in ipairs(d.bars) do
					seg.bar.BackgroundTransparency = 1 - a * seg.weight
				end
			end
		end
	end
end

local function updateUse(show: boolean)
	local up = ClientState.useProgress
	if show and type(up) == "table" and type(up.alpha) == "number" then
		setVisible(R.ring, true)
		local lit = math.floor(math.clamp(up.alpha, 0, 1) * #R.segments + 0.5)
		if lit ~= lastUseLit then
			lastUseLit = lit
			for i, seg in ipairs(R.segments) do
				seg.BackgroundTransparency = if i <= lit then 0 else 0.75
			end
		end
		local text = string.upper(tostring(up.label or ""))
		if R.ringLabel.Text ~= text then
			R.ringLabel.Text = text
		end
	else
		setVisible(R.ring, false)
		lastUseLit = -1
	end
end

local function updateDraw(show: boolean)
	local a = math.clamp(tonumber(ClientState.drawAlpha) or 0, 0, 1)
	local on = show and a > 0.02
	setVisible(R.draw, on)
	if on then
		R.drawFill.Size = UDim2.fromScale(1, a) -- upright: it fills from the bottom
		R.drawFill.BackgroundColor3 = if a >= 0.999 then C.Accent else C.Text
		-- below the minimum charge a release lets the string down instead of shooting: the fill stays faint until then
		R.drawFill.BackgroundTransparency = if a < (Config.Combat.MinBowCharge or 0.2) then 0.6 else 0
	end
end

local function hintKeyFor(key: string?): string?
	if Input.isTouch() then
		return nil -- the DRINK button is on screen
	end
	if Input.isGamepad() then
		return glyphFor(Enum.KeyCode.ButtonX, "X") -- Square on PlayStation, once Shared.Glyphs knows
	end
	if type(key) == "string" and key ~= "" and key ~= "X" then
		return string.upper(key)
	end
	return "E"
end

-- The interaction hint (water: [E] Drink). It holds HINT_HOLD after the look ray leaves the water, and while it shows
-- it has the slot (returns true).
local function updateInteract(show: boolean): boolean
	local hint = ClientState.interactHint
	local text = if show and type(hint) == "table" and type(hint.text) == "string" and hint.text ~= "" then hint.text else nil
	local full = false
	if text == "Drink" and (tonumber(player:GetAttribute("Thirst")) or 0) >= DRINK_HINT_MAX then
		-- nothing to gain from a drink (a swimmer at thirst 97 had "E Drink" over the whole lake): no hint. The key
		-- itself still drinks (InventoryController); "Fill bottle" is unaffected.
		text, full = nil, true
	end
	local rawKey = if text then hint.key else nil
	local now = os.clock()
	if text then
		interactSeen = { text = text, key = rawKey, at = now }
	elseif show and not full and interactSeen and now - interactSeen.at < HINT_HOLD then
		text, rawKey = interactSeen.text, interactSeen.key
	end
	local key = if text then hintKeyFor(rawKey) else nil
	if text == hintState.text and key == hintState.key then
		return text ~= nil
	end
	hintState.text, hintState.key = text, key
	hintToken += 1
	local token = hintToken
	local group = R.interact
	if text then
		R.interactText.Text = text
		R.interactKey.Visible = key ~= nil
		R.interactKeyLabel.Text = key or ""
		group.Visible = true
		Theme.tween(group, Theme.Tween.Fast, { GroupTransparency = 0 })
	else
		local t = Theme.tween(group, Theme.Tween.Fast, { GroupTransparency = 1 })
		t.Completed:Once(function()
			if token == hintToken then
				group.Visible = false
			end
		end)
	end
	return text ~= nil
end

-- QW2: ClientState.actionHint = { text, keys? } (InventoryController). "[LMB]" and "{1}" in the text become key caps;
-- keys the text doesn't place lead the line (a faded hint can be keys alone).
local function parseHint(hint: any): { any }?
	if type(hint) ~= "table" then
		return nil
	end
	local text = if type(hint.text) == "string" then hint.text else ""
	local keys = if type(hint.keys) == "table" then hint.keys else {}
	if hint == actionState.ref and text == actionState.refText then
		return actionState.parsed
	end
	local segments = {}
	local placed = false
	local function addText(s: string)
		local trimmed = string.match(s, "^%s*(.-)%s*$") or ""
		if trimmed ~= "" then
			table.insert(segments, { kind = "text", text = trimmed })
		end
	end
	local pos = 1
	while pos <= #text do
		local a, b = string.find(text, "%b[]", pos)
		local c, d, n = string.find(text, "{(%d+)}", pos)
		if not a and not c then
			break
		end
		placed = true
		if a and b and (not c or a < c) then
			addText(string.sub(text, pos, a - 1))
			table.insert(segments, { kind = "key", text = string.sub(text, a + 1, b - 1) })
			pos = b + 1
		else
			addText(string.sub(text, pos, (c :: number) - 1))
			local k = keys[tonumber(n) or 0]
			if type(k) == "string" and k ~= "" then
				table.insert(segments, { kind = "key", text = k })
			end
			pos = (d :: number) + 1
		end
	end
	addText(string.sub(text, pos))
	if not placed then
		for i = #keys, 1, -1 do
			local k = keys[i]
			if type(k) == "string" and k ~= "" then
				table.insert(segments, 1, { kind = "key", text = k })
			end
		end
	end
	local result = if #segments > 0 then segments else nil
	actionState.ref, actionState.refText, actionState.parsed = hint, text, result
	return result
end

local function renderAction(segments: { any })
	for _, inst in ipairs(actionPool.used) do
		inst.Visible = false
	end
	table.clear(actionPool.used)
	local nKeys, nTexts = 0, 0
	for order, seg in ipairs(segments) do
		local inst
		if seg.kind == "key" then
			nKeys += 1
			inst = actionPool.keys[nKeys]
			if not inst then
				inst = R.actionKey:Clone()
				inst.Parent = R.action
				actionPool.keys[nKeys] = inst
			end
			local label = inst:FindFirstChild("Label")
			if label then
				label.Text = seg.text
			end
		else
			nTexts += 1
			inst = actionPool.texts[nTexts]
			if not inst then
				inst = R.actionText:Clone()
				inst.Parent = R.action
				actionPool.texts[nTexts] = inst
			end
			inst.Text = seg.text
		end
		inst.Name = "Seg" .. order
		inst.LayoutOrder = order
		inst.Visible = true
		table.insert(actionPool.used, inst)
	end
end

-- Under the crosshair while the interaction hint isn't showing; holds HINT_HOLD after the hint goes, like it.
local function updateAction(show: boolean)
	local group = R.action
	if not group or not R.actionKey or not R.actionText then
		return
	end
	-- with a bow in hand the line sits lower, below the feet of a target 60 studs out (combat QA pt3)
	local held = ItemDefs.get(ClientState.getEquippedItemId())
	local y = if held and held.kind == "Bow" then ACTION_Y_BOW else ACTION_Y
	if group.Position.Y.Offset ~= y then
		group.Position = UDim2.fromOffset(0, y)
	end
	local segments = if show then parseHint((ClientState :: any).actionHint) else nil
	local now = os.clock()
	if segments then
		actionSeen = { segments = segments, at = now }
	elseif show and actionSeen and now - actionSeen.at < HINT_HOLD then
		segments = actionSeen.segments
	elseif show and flashHint and now < flashHint.untilT then
		segments = flashHint.segments
	end
	local sig: string? = nil
	if segments and segments == actionState.sigFor then
		sig = actionState.sigText -- the same parsed hint as last frame (parseHint and the hold both hand back one table)
	elseif segments then
		local parts = {}
		for _, seg in ipairs(segments) do
			table.insert(parts, seg.kind .. ":" .. seg.text)
		end
		sig = table.concat(parts, "|")
		actionState.sigFor, actionState.sigText = segments, sig
	end
	if sig == actionState.sig then
		return
	end
	actionState.sig = sig
	actionState.token += 1
	local token = actionState.token
	if segments then
		renderAction(segments)
		group.Visible = true
		Theme.tween(group, Theme.Tween.Fast, { GroupTransparency = 0 })
	else
		local t = Theme.tween(group, Theme.Tween.Fast, { GroupTransparency = 1 })
		t.Completed:Once(function()
			if token == actionState.token then
				group.Visible = false
			end
		end)
	end
end

local function updateVignettes(dt: number, t: number, combat: boolean)
	local lowAlpha = 0
	if combat and humanoid and health > 0 then
		local f = health / math.max(1, maxHealth)
		if f < LOW_HEALTH then
			local k = math.clamp((LOW_HEALTH - f) / math.max(0.05, LOW_HEALTH - 0.1), 0, 1)
			local beat = 0.72 + 0.28 * math.sin(t * 2 * math.pi * (0.85 + 0.6 * k))
			lowAlpha = (0.22 + 0.55 * k) * beat
		end
	end
	setVignette(R.vLow, lowAlpha)
	local borderTarget = if outside and combat then 0.34 + 0.08 * math.sin(t * 2.2) else 0
	borderAlpha += (borderTarget - borderAlpha) * Util.damp(5, dt)
	setVignette(R.vBorder, borderAlpha)
	hurtAlpha = math.max(0, hurtAlpha - dt * 1.4)
	setVignette(R.vHurt, if combat then hurtAlpha else 0)
end

local function updateCore(combat: boolean)
	-- Reset (Roblox menu): in the lobby, and in the arena once the round is on and you are off your plate - a way out
	-- of a spot you can't leave. It counts as a death (PlayerService credits a recent attacker with the kill).
	local allowReset = not ClientState.inArena
		or (combat and not ClientState.frozen and GameState:GetAttribute("Phase") == "Active")
	if allowReset ~= lastResetAllowed then
		lastResetAllowed = allowReset
		setCore("ResetButtonCallback", allowReset)
	end
	local hideMouse = combat and not ClientState.menuOpen
	if hideMouse ~= lastMouseHidden then
		lastMouseHidden = hideMouse
		UserInputService.MouseIconEnabled = not hideMouse
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------------------------------
local function refreshDeviceHints()
	local gamepad = Input.isGamepad()
	local touch = Input.isTouch() or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	for i = 1, SLOTS do
		slotRefs[i].key.Visible = not gamepad and not touch
	end
	R.prevHint.Visible = gamepad
	R.nextHint.Visible = gamepad
	-- QW13 (qw:controls): the pad's own names, L1 / R1 on PlayStation (Shared.Glyphs)
	local prevLabel, nextLabel = R.prevHint:FindFirstChild("Label"), R.nextHint:FindFirstChild("Label")
	if prevLabel and nextLabel and prevLabel:IsA("TextLabel") and nextLabel:IsA("TextLabel") then
		prevLabel.Text = glyphFor(Enum.KeyCode.ButtonL1, "LB")
		nextLabel.Text = glyphFor(Enum.KeyCode.ButtonR1, "RB")
	end
	hintState.key = "?" -- force the interaction hint to refresh its key cap
end

local FALLBACK_LAYOUT = {
	Desktop = {
		Vitals = { anchor = Vector2.new(0, 1), position = UDim2.fromScale(0, 1), size = UDim2.fromOffset(210, 120), align = "Bottom" },
		KillFeed = { anchor = Vector2.new(1, 0), position = UDim2.fromScale(1, 0), size = UDim2.fromOffset(380, 170), align = "Right" },
		SlotSize = 56,
	},
	Touch = {
		Vitals = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 52), size = UDim2.fromOffset(176, 104), align = "Top" },
		KillFeed = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 190), size = UDim2.fromOffset(300, 92), align = "Left" },
		SlotSize = 48,
	},
}

local function applyLayout()
	touchLayout = UserInputService.TouchEnabled
	local key = if not touchLayout then "Desktop" elseif Theme.isSmallScreen() then "Phone" else "Touch"
	local layout = (Theme.Layout and Theme.Layout[key]) or FALLBACK_LAYOUT[if touchLayout then "Touch" else "Desktop"]
	layoutKey = if Theme.Layout and Theme.Layout[key] then key elseif touchLayout then "Touch" else "Desktop"
	local vitals, killFeed = R.vitals, R.killFeed
	vitals.AnchorPoint = layout.Vitals.anchor
	vitals.Position = layout.Vitals.position
	vitals.Size = layout.Vitals.size
	R.vitalsLayout.VerticalAlignment = (Enum.VerticalAlignment :: any)[layout.Vitals.align] or Enum.VerticalAlignment.Bottom
	killFeed.AnchorPoint = layout.KillFeed.anchor
	killFeed.Position = layout.KillFeed.position
	killFeed.Size = layout.KillFeed.size
	R.feedLayout.HorizontalAlignment = (Enum.HorizontalAlignment :: any)[layout.KillFeed.align] or Enum.HorizontalAlignment.Right
	setSlotSize(layout.SlotSize or 56)
	refreshDeviceHints()
	placeHotbar()
end

--------------------------------------------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------------------------------------------
local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera or not hud then
		return
	end
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	local camCF = camera.CFrame
	local phase = GameState:GetAttribute("Phase") or "Lobby"
	local spectating = ClientState.spectating ~= nil
	local combat = ClientState.inArena and ClientState.alive and not spectating
	-- A death, result or victory card has the screen (NotificationController.isCardUp): nothing of the round's HUD
	-- shows through it. The winner is still a living contender in the arena while VICTORY is up, so "combat" alone
	-- left the hotbar, the vitals, the crosshair, the hints and Roblox's own Take / Open prompts under the table.
	local card = false
	local notifications = Controllers and Controllers.NotificationController
	if notifications and notifications.isCardUp then
		local ok, up = pcall(notifications.isCardUp)
		card = ok and up == true
	end
	if card ~= lastCardUp then
		lastCardUp = card
		ProximityPromptService.Enabled = not card -- this client only; back on the moment the card goes
	end
	local showHud = combat and not card
	local showTop = (phase == "Countdown" or phase == "Active") and (ClientState.inArena or spectating)
		and next(topSuppressed) == nil and not card

	updateBorderState(phase)
	setVisible(R.top, showTop)
	setVisible(R.vitals, showHud)
	setVisible(R.hotbar, showHud)
	-- on touch layouts the kill feed sits at the left, where the cards are: it waits for them (a PC's is in the corner)
	setVisible(R.killFeed, not (card and layoutKey ~= "Desktop"))
	if showTop then
		updateCompass(camCF, phase)
		infoClock -= dt
		if infoClock <= 0 then
			infoClock = 0.1
			updateInfo(now, phase)
		end
	end
	if combat then
		updateStamina(dt, t)
	end
	updatePulses(t)
	updateReason(combat)
	updateShimmer(dt, combat)

	local showCenter = showHud and not ClientState.menuOpen
	updateCrosshair(showCenter)
	updateUse(showCenter)
	updateDraw(showCenter)
	local interacting = updateInteract(showCenter)
	updateAction(showCenter and not interacting)
	updateDamage(camCF)
	updateVignettes(dt, t, showHud)
	updateCore(combat)
end

--------------------------------------------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------------------------------------------
HUDController.flashItemName = flashItemName
HUDController.guidanceOn = guidanceOn
HUDController.roundsPlayed = roundsPlayed
HUDController.keyName = keyName

function HUDController.pulseWater(seconds: number?)
	waterPulseUntil = os.clock() + math.clamp(tonumber(seconds) or 6, 0, 30)
	thirstyCardRound = true
end

function HUDController.suppressTop(reason: string, on: boolean)
	if on then
		topSuppressed[reason] = true
	else
		topSuppressed[reason] = nil
	end
end

function HUDController.getHotbarRect(): (Vector2, Vector2)
	if not R.hotbar then
		return Vector2.zero, Vector2.zero
	end
	return R.hotbar.AbsolutePosition, R.hotbar.AbsoluteSize
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------
function HUDController.Init(registry)
	Controllers = registry
end

function HUDController.Start()
	setCoreGui(Enum.CoreGuiType.Backpack, false)
	setCoreGui(Enum.CoreGuiType.Health, false)
	-- Roblox's player list opens by itself on a PC, in the corner the kill feed uses (one row per player, up to 48): off.
	-- The Roblox menu keeps its own players page for muting and reporting.
	setCoreGui(Enum.CoreGuiType.PlayerList, false)
	-- Roblox's chat window opens by itself on a PC, over the top left (a late joiner's covered the left end of the
	-- lobby's status line): closed until the player opens it with the chat button in Roblox's top bar or the / key.
	-- Chat itself stays on; the button shows when there is something new.
	setCore("ChatActive", false)
	-- Roblox's chat opens its window again a moment after it has loaded (two real clients, 18 Nov: open 0.2 s after the
	-- close above, and it stayed open in the lobby). For the first seconds it is closed again whenever it reads open,
	-- until it has stayed closed for 3 s; from then on (8 s after chat first answered at the latest) it is the player's.
	task.spawn(function()
		local firstAnswer: number? = nil
		local closedSince: number? = nil
		for _ = 1, 400 do
			local ok, active = pcall(function()
				return StarterGui:GetCore("ChatActive")
			end)
			local t = os.clock()
			if ok then
				firstAnswer = firstAnswer or t
				if active == true then
					closedSince = nil
					pcall(function()
						StarterGui:SetCore("ChatActive", false)
					end)
				else
					closedSince = closedSince or t
					if t - closedSince >= 3 then
						return
					end
				end
				if t - firstAnswer > 8 then
					return
				end
			end
			task.wait(0.15)
		end
	end)

	local pg = player:WaitForChild("PlayerGui") :: PlayerGui
	playerGui = pg
	local hudGui = pg:WaitForChild("HUD") :: ScreenGui
	local fxGui = pg:WaitForChild("HUDFX") :: ScreenGui
	hud, fx = hudGui, fxGui
	getScale = Theme.bindRoot(hudGui)
	Theme.bindRoot(fxGui)

	local root = hudGui:WaitForChild("Root") :: any
	local top = root:WaitForChild("Top")
	R.top = top
	R.ticks = top.Compass.Ticks
	R.spire = top.Compass.Markers.Spire
	R.spireDiamond = top.Compass.Markers.Spire.Diamond
	R.spireDist = top.Compass.Markers.Spire.Dist
	R.borderMarker = top.Compass.Markers.Border
	local markers = top.Compass.Markers
	R.waterMarker = markers:FindFirstChild("Water")
	if R.waterMarker then
		R.waterTip = R.waterMarker:WaitForChild("Tip")
		R.waterBulb = R.waterMarker:WaitForChild("Bulb")
		R.waterDist = R.waterMarker:WaitForChild("Dist")
	end
	R.edgeMarker = markers:FindFirstChild("Edge")
	if R.edgeMarker then
		R.edgeTick = R.edgeMarker:WaitForChild("Tick")
	end
	R.borderDist = top.Info:FindFirstChild("Border")
	R.timer = top.Info.Timer
	R.dot = top.Info.Dot
	R.remain = top.Info.Remain
	R.practice = top.Info.Practice
	R.event = top.Event
	R.alert = top.Alert
	R.alertTitle = top.Alert.Title
	R.alertSub = top.Alert.Sub
	R.killFeed = root:WaitForChild("KillFeed")
	R.feedLayout = R.killFeed:WaitForChild("Layout")
	R.vitals = root:WaitForChild("Vitals")
	R.vitalsLayout = R.vitals:WaitForChild("Layout")
	R.hotbar = root:WaitForChild("Hotbar")
	R.slots = R.hotbar:WaitForChild("Slots")
	R.itemName = R.hotbar:WaitForChild("ItemName")
	R.itemTitle = R.itemName:WaitForChild("Title")
	R.itemSub = R.itemName:WaitForChild("Sub")
	R.itemDesc = R.itemName:FindFirstChild("Desc")
	R.prevHint = R.hotbar:WaitForChild("PrevHint")
	R.nextHint = R.hotbar:WaitForChild("NextHint")
	R.killTemplate = root:WaitForChild("Templates"):WaitForChild("KillEntry")

	local fxRoot = fxGui:WaitForChild("Root") :: any
	local center = fxRoot:WaitForChild("Center")
	local vignette = fxGui:WaitForChild("Vignette") :: any
	R.vLow = vignette:WaitForChild("LowHealth")
	R.vBorder = vignette:WaitForChild("Border")
	R.vHurt = vignette:WaitForChild("Hurt")
	-- No red hit effects (the age rating's "Mild" condition): the hurt flash and the low-health edge are built dark
	-- red (UIBuilder); here they become a neutral dark edge. The Border vignette keeps the wall's own colour.
	for _, holder in ipairs({ R.vLow, R.vHurt }) do
		for _, edge in ipairs(holder:GetChildren()) do
			if edge:IsA("GuiObject") then
				edge.BackgroundColor3 = NEUTRAL_EDGE
			end
		end
	end
	R.cross = center:WaitForChild("Crosshair")
	R.crossDot = R.cross:WaitForChild("Dot")
	R.lines = { Up = R.cross.Up, Down = R.cross.Down, Left = R.cross.Left, Right = R.cross.Right }
	-- the centre dot has to read on any background (bright sky, foliage, night): a near-solid dark outline
	local dotStroke = R.crossDot:FindFirstChildOfClass("UIStroke")
	if dotStroke then
		dotStroke.Transparency = 0.15
		dotStroke.Thickness = 1.5
	end
	for _, line in pairs(R.lines) do
		local lineStroke = line:FindFirstChildOfClass("UIStroke")
		if lineStroke then
			lineStroke.Transparency = 0.4
		end
	end
	R.hit = center:WaitForChild("Hit")
	R.ring = center:WaitForChild("UseRing")
	R.ringLabel = R.ring:WaitForChild("Label")
	R.segments = {}
	local i = 1
	while true do
		local seg = R.ring:FindFirstChild(string.format("S%02d", i))
		if not seg then
			break
		end
		table.insert(R.segments, seg)
		i += 1
	end
	R.draw = center:WaitForChild("Draw")
	R.drawFill = R.draw:WaitForChild("Fill")
	-- the draw gauge stands upright beside the crosshair and fills from the bottom: under the crosshair it covered a far
	-- target's legs (combat QA pt3, 60 studs)
	R.draw.AnchorPoint = Vector2.new(0, 0.5)
	R.draw.Position = UDim2.fromOffset(DRAW_GAUGE_X, 0)
	R.draw.Size = UDim2.fromOffset(3, DRAW_GAUGE_HEIGHT)
	R.drawFill.AnchorPoint = Vector2.new(0, 1)
	R.drawFill.Position = UDim2.fromScale(0, 1)
	R.drawFill.Size = UDim2.fromScale(1, 0)
	R.interact = center:WaitForChild("Interact")
	R.interactKey = R.interact:WaitForChild("Key")
	R.interactKeyLabel = R.interactKey:WaitForChild("Label")
	R.interactText = R.interact:WaitForChild("Text")
	R.action = center:FindFirstChild("Action")
	if R.action then
		local templates = R.action:WaitForChild("Templates")
		R.actionKey = templates:WaitForChild("Key")
		R.actionText = templates:WaitForChild("Text")
		R.actionKey.Visible = false -- templates under a Folder would still draw
		R.actionText.Visible = false
	end
	local damage = center:WaitForChild("Damage")
	for n = 1, 4 do
		local holder = damage:FindFirstChild("Dir" .. n)
		if holder then
			local bars = {}
			for _, seg in ipairs(holder:GetChildren()) do
				local bar = seg:FindFirstChild("Bar")
				if bar then
					bar.BackgroundColor3 = C.Warning -- amber, not the built red (no red hit effects)
					table.insert(bars, { bar = bar, weight = tonumber(bar:GetAttribute("Weight")) or 1 })
				end
			end
			table.insert(damageDirs, { holder = holder, bars = bars, active = false, from = nil, t0 = 0, life = 1, strength = 1 })
		end
	end

	for _, name in ipairs({ "Health", "Hunger", "Thirst", "Stamina" }) do
		makeStat(name)
	end
	R.armorLine = R.vitals.Health:WaitForChild("ArmorLine")
	stats.Stamina.ghost.Visible = false
	R.reason = R.vitals:FindFirstChild("Reason")
	R.shimmer = stats.Health.fill:FindFirstChild("Shimmer")
	R.shimmerGradient = R.shimmer and R.shimmer:FindFirstChildOfClass("UIGradient")
	-- the healing line on Hunger and Thirst sits at Config.Survival.RegenMinStat
	for _, name in ipairs({ "Hunger", "Thirst" }) do
		local tick = stats[name] and stats[name].track:FindFirstChild("Tick")
		if tick then
			tick.Position = UDim2.fromScale(math.clamp(REGEN_MIN / 100, 0, 1), 0.5)
		end
	end

	for n = 1, SLOTS do
		local button = R.slots:FindFirstChild("Slot" .. n)
		if not button then
			warn("[HUDController] Hotbar slot " .. n .. " is missing; run UIBuilder.build()")
			break
		end
		local card = button:WaitForChild("Card")
		slotRefs[n] = {
			button = button,
			card = card,
			stroke = card:WaitForChild("Stroke"),
			viewport = card:WaitForChild("Viewport"),
			fallback = card:WaitForChild("Fallback"),
			key = card:WaitForChild("Key"),
			count = card:WaitForChild("Count"),
			rarity = card:WaitForChild("Rarity"),
			itemId = nil,
		}
		button.Activated:Connect(function()
			if not (ClientState.inArena and ClientState.alive) or ClientState.spectating then
				return
			end
			ClientState.selectSlot:Fire(if equippedSlot == n then 0 else n)
		end)
	end
	SLOTS = #slotRefs

	collectCompass()
	applyLayout()
	bindCharacter(player.Character)
	player.CharacterAdded:Connect(bindCharacter)
	for _, attribute in ipairs({ "Hunger", "Thirst" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			updateSurvival(false)
		end)
	end
	player:GetAttributeChangedSignal("Armor"):Connect(updateArmor)
	updateSurvival(true)
	updateArmor()

	-- a new round: new-player status as read at the Countdown, and the water marker starts over
	local function onPhase()
		local phase = GameState:GetAttribute("Phase")
		if phase == "Countdown" then
			roundsSnapshot = math.max(0, math.floor(tonumber(player:GetAttribute("RoundsPlayed")) or 0))
			drankThisRound = false
			thirstyCardRound = false
			waterPulseUntil = 0
		elseif phase == "Lobby" or phase == "Intermission" then
			roundsSnapshot = nil
		end
	end
	GameState:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	onPhase()
	-- QW6: at the horn a new player gets a 3-second key hint for sprinting (the action hint, when there is one, wins)
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState:GetAttribute("Phase") ~= "Active" or not ClientState.inArena or not guidanceOn() then
			return
		end
		-- it follows the Sprint setting per device (SettingsController: 0 Hold, 1 Toggle, 2 Auto)
		local settings = ClientState.settings :: any
		local function sprintKey(fallback: string): string
			glyphFor(Enum.KeyCode.E, "E")
			if glyphs and type(glyphs.forAction) == "function" then
				local ok, name = pcall(glyphs.forAction, "Sprint")
				if ok and type(name) == "string" and name ~= "" then
					return name
				end
			end
			return fallback
		end
		local auto = { { kind = "text", text = "PUSH THE STICK ALL THE WAY TO SPRINT" } }
		local segments = nil
		if Input.isTouch() then
			segments = if tonumber(settings.sprintModeTouch) == 2 then auto
				else { { kind = "key", text = sprintKey("RUN") }, { kind = "text", text = "SPRINT" } }
		elseif Input.isGamepad() then
			segments = if tonumber(settings.sprintModePad) == 2 then auto
				else { { kind = "key", text = sprintKey(glyphFor(Enum.KeyCode.ButtonL3, "L3")) }, { kind = "text", text = "SPRINT" } }
		elseif tonumber(settings.sprintMode) ~= 2 then
			segments = { { kind = "key", text = sprintKey("SHIFT") }, { kind = "text", text = "SPRINT" } }
		end
		if segments then
			flashHint = { segments = segments, untilT = os.clock() + 3 }
		end
	end)
	player:GetAttributeChangedSignal("Thirst"):Connect(function()
		local thirst = tonumber(player:GetAttribute("Thirst")) or 100
		if lastThirst and thirst > lastThirst + 6 and GameState:GetAttribute("Phase") == "Active" and ClientState.inArena then
			-- a drink retires the water marker (and the THIRSTY card's early showing) until thirst drops under the
			-- threshold again; after a drink that left you under it, until you are WATER_REARM_DROP thirstier
			drankThisRound = true
			thirstyCardRound = false
			waterRearmBelow = math.min(WATER_THIRST, thirst - WATER_REARM_DROP)
		elseif drankThisRound and thirst < waterRearmBelow then
			drankThisRound = false -- thirsty again: the marker comes back (while you carry nothing to drink)
		end
		lastThirst = thirst
	end)

	ClientState.inventoryChanged:Connect(onInventory)
	ClientState.equippedChanged:Connect(function(itemId, slot)
		local n = math.floor(tonumber(slot) or 0)
		if n ~= equippedSlot then
			equippedSlot = n
			for k = 1, SLOTS do
				paintSlot(k)
			end
		end
		if ClientState.inArena and ClientState.alive then
			flashItemName(if type(itemId) == "string" then itemId else nil)
		end
	end)
	onInventory(ClientState.inventory)
	ClientState.hitConfirmed:Connect(showHit)
	ClientState.damageTaken:Connect(onDamage)
	ClientState.lifeChanged:Connect(function()
		if not ClientState.inArena then
			hurtAlpha = 0
			for _, d in ipairs(damageDirs) do
				d.active = false
				setVisible(d.holder, false)
			end
		end
		updateSurvival(true)
	end)
	Net.event("KillFeed").OnClientEvent:Connect(addKill)

	-- (the device kind, not every switch between keys and mouse: that one fires many times a second in a fight and
	-- each time made the interaction hint tween again)
	Input.deviceChanged:Connect(refreshDeviceHints)
	glyphFor(Enum.KeyCode.E, "E")
	if glyphs and glyphs.changed and type(glyphs.changed.Connect) == "function" then
		glyphs.changed:Connect(refreshDeviceHints) -- a PlayStation pad was plugged in: the key caps follow
	end
	local function hookCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				task.defer(applyLayout)
			end)
		end
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	hookCamera()

	hudGui.Enabled = true
	fxGui.Enabled = true
	RunService:BindToRenderStep("UI_HUD", Enum.RenderPriority.Last.Value, update)

	-- touch buttons appear and move as other controllers bind them; keep the hotbar clear of them
	if UserInputService.TouchEnabled then
		while true do
			task.wait(0.5)
			placeHotbar()
		end
	end
end

return HUDController
