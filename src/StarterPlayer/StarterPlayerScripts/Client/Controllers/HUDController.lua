--[[
	HUDController - the in-arena HUD. Owned by the UI system.
	Drives StarterGui.HUD (safe-area layout) and StarterGui.HUDFX (full-bleed, true screen centre), both built by
	ServerStorage.WorldGen.UIBuilder.
	  * Vitals: health (+ armor chip and line), hunger, thirst, stamina (auto-hides when full). Thin bars, a ghost bar
	    that trails damage, and a pulse plus a "LOW" tag when a value runs low.
	  * Hotbar: Config.Inventory.Slots slots with 3D icons (ItemModels.build(id, "world") framed by its bounding box,
	    text fallback), stack counts, rarity line, selected lift, item-name toast, tap to select on touch.
	    On touch screens it slides left so it never overlaps the action buttons (Theme.TouchLayout / Shared.Input).
	  * Compass ribbon from the camera yaw with a Spire marker (+ distance when facing it) and, when you're outside
	    the border, a border marker and an alert. Round clock, "17 REMAIN", practice tag, next-event line.
	  * Kill feed (KillFeed remote), crosshair (spread from ClientState.crosshairSpread), hit/kill marker
	    (ClientState.hitConfirmed), directional damage arcs (ClientState.damageTaken), low-health / outside-border /
	    hurt vignettes, use ring (ClientState.useProgress), bow draw meter (ClientState.drawAlpha), interaction hint
	    (ClientState.interactHint).
	  * Core GUI: Backpack and Health off, reset disabled while InArena, mouse icon hidden in arena first person.
	  PlayabilityPlan quick wins drawn here:
	  * QW2  the action hint (ClientState.actionHint = { text, keys? }) under the crosshair in the key-cap style: "[LMB]"
	         or "{1}" in the text become caps, other keys lead. The interaction hint (water) wins. Both hold 0.25 s
	         after their source goes so they never flicker. The item toast adds the item's desc for its first 3 shows.
	  * QW5  a tick at Config.Survival.RegenMinStat on Hunger and Thirst (the healing line); under Health a dim
	         "NOT HEALING · THIRSTY" only when a meter is the reason (player attribute Regen, else the meters), red
	         "DEHYDRATED · LOSING HEALTH" (or STARVING) at an empty meter; a slow shimmer while health comes back.
	         One low-health line: Config.Feedback.LowHealth drives the LOW tag and the red vignette.
	  * QW9  the event line always shows the next beat (dim while more than a minute away), built by Shared.ThreatLine
	         with Shared.Lore's names: ROLL CALL AT DUSK, THE OFFERING, THE BORDER MOVES, THE LAST STAND.
	  * QW10 Guidance: below 50 thirst with nothing to drink, a water drop and its distance on the compass (nearest
	         Shared.WaterPoints point inside the border) until your first drink of the round; off the ribbon it waits at
	         the edge with its distance and an arrow ("‹ 64 m"). Once the border moves
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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
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

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer
local C = Theme.Colors

local HUDController = {}

local SLOTS = math.max(1, math.floor(tonumber(Config.Inventory.Slots) or 6))
local SLOT_GAP = (Theme.Layout and Theme.Layout.SlotGap) or 6
local BUTTON_MARGIN = (Theme.Layout and Theme.Layout.HotbarButtonMargin) or 12
local STUD_TO_METERS = 0.28
local COMPASS_WIDTH = 360 -- design px (UIBuilder)
local COMPASS_SPAN = 150 -- degrees visible across the ribbon
local LOW_HEALTH = tonumber(Config.Feedback and Config.Feedback.LowHealth) or 0.35 -- also the vignette and heartbeat
local LOW = { Health = LOW_HEALTH, Hunger = 0.25, Thirst = 0.25 }
local REGEN_MIN = tonumber(Config.Survival.RegenMinStat) or 55 -- health only comes back above this on both meters
local HINT_HOLD = 0.25 -- hints stay up this long after their source goes, so they never flicker (P8)
local WATER_THIRST = 50 -- Guidance: the water marker shows below this thirst
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
local CAUSE_WITH = { Fall = "fall", Border = "border", Starvation = "starvation", Dehydration = "thirst", Other = "eliminated" }
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
local stats: { [string]: any } = {}
local slotRefs: { any } = {}
local equippedSlot = 0
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
local drankThisRound = false
local thirstyCardRound = false -- the THIRSTY card showed this round: the water marker comes with it
local waterPulseUntil = 0
local waterCache = { at = 0, point = nil :: Vector3?, distance = 0 }
local lastThirst: number? = nil
local interactSeen: { text: string, key: string?, at: number }? = nil
local actionSeen: { segments: { any }, at: number }? = nil
local actionState = { sig = nil :: string?, token = 0, ref = nil :: any, refText = nil :: string?, parsed = nil :: { any }? }
local actionPool = { keys = {} :: { any }, texts = {} :: { any }, used = {} :: { any } }
local flashHint: { segments: { any }, untilT: number }? = nil -- a short HUD-side hint, e.g. [SHIFT] SPRINT at the horn

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
local function refreshLabel(name: string)
	local s = stats[name]
	if not s then
		return
	end
	local text = s.baseText
	if name == "Health" and armorText then
		text ..= "  " .. armorText
	end
	if s.low then
		text ..= string.format("  <font color=\"%s\">LOW</font>", Theme.hex(C.Danger))
	end
	s.label.Text = text
end

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
		low = false,
		ghostToken = 0,
		fillT = -1,
		vis = -1,
	}
	s.baseText = s.label.Text
	s.color = s.fill.BackgroundColor3
	stats[name] = s
end

local function setStat(name: string, alpha: number, valueText: string, isLow: boolean, instant: boolean?)
	local s = stats[name]
	if not s then
		return
	end
	local a = math.clamp(alpha, 0, 1)
	if math.abs(a - s.alpha) > 0.0005 or instant then
		local dropping = a < s.alpha
		s.alpha = a
		if instant then
			s.ghostToken += 1
			s.fill.Size = UDim2.fromScale(a, 1)
			s.ghost.Size = UDim2.fromScale(a, 1)
		else
			Theme.tween(s.fill, Theme.Tween.Bar, { Size = UDim2.fromScale(a, 1) })
			if dropping then
				-- the ghost holds where the bar was, then catches up: you see how much you just lost
				s.ghostToken += 1
				local token = s.ghostToken
				task.delay(0.45, function()
					if s.ghostToken == token then
						Theme.tween(s.ghost, Theme.Tween.Ghost, { Size = UDim2.fromScale(s.alpha, 1) })
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
	if s.low ~= isLow then
		s.low = isLow
		refreshLabel(name)
		if name == "Health" then
			s.fill.BackgroundColor3 = if isLow then C.HealthLow else s.color
		end
	end
end

local function updateHealth(instant: boolean?)
	local a = health / math.max(1, maxHealth)
	setStat("Health", a, tostring(math.max(0, math.ceil(health))), a <= LOW.Health and health > 0, instant)
end

local function updateSurvival(instant: boolean?)
	local hunger = math.clamp(tonumber(player:GetAttribute("Hunger")) or 100, 0, 100)
	local thirst = math.clamp(tonumber(player:GetAttribute("Thirst")) or 100, 0, 100)
	setStat("Hunger", hunger / 100, tostring(math.floor(hunger + 0.5)), hunger / 100 <= LOW.Hunger, instant)
	setStat("Thirst", thirst / 100, tostring(math.floor(thirst + 0.5)), thirst / 100 <= LOW.Thirst, instant)
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
				-- the reason in its meter's colour, so the line points at the bar that needs filling
				local function word(w: string, color: Color3): string
					return string.format("<font color=\"%s\">%s</font>", Theme.hex(color), w)
				end
				local what = if hungry and thirsty then word("HUNGRY", C.Hunger) .. " AND " .. word("THIRSTY", C.Thirst)
					elseif thirsty then word("THIRSTY", C.Thirst)
					else word("HUNGRY", C.Hunger)
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
		label.TextColor3 = if danger then C.Danger else C.Text -- on its own dark backing (UIBuilder)
	end
end

-- QW5: a slow light sweep over the health bar while health is coming back.
local function updateShimmer(dt: number, combat: boolean)
	local shimmer = R.shimmer
	if not shimmer then
		return
	end
	local on = combat and health > 0 and health < maxHealth - 0.05 and os.clock() - lastHealthRise < 1.2
	if shimmer.Visible ~= on then
		shimmer.Visible = on
	end
	if on and R.shimmerGradient then
		shimmerPhase = (shimmerPhase + dt / 2.6) % 1
		R.shimmerGradient.Offset = Vector2.new(-0.75 + 1.5 * shimmerPhase, 0)
	end
end

local function updateArmor()
	local id = player:GetAttribute("Armor")
	local def = if type(id) == "string" and id ~= "" then ItemDefs.get(id) else nil
	if def and type(def.damageMultiplier) == "number" then
		local pct = math.floor((1 - def.damageMultiplier) * 100 + 0.5)
		armorText = string.format("<font color=\"%s\">ARMOR %d%%</font>", Theme.hex(C.Armor), pct)
	else
		armorText = nil
	end
	R.armorLine.Visible = armorText ~= nil
	refreshLabel("Health")
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
	if s.low ~= exhausted then
		s.low = exhausted
		refreshLabel("Stamina")
	end
	if math.abs(staminaVis - s.vis) > 0.01 then
		s.vis = staminaVis
		local hidden = 1 - staminaVis
		s.label.TextTransparency = hidden
		s.value.TextTransparency = hidden
		local ls, vs = s.label:FindFirstChild("Shadow"), s.value:FindFirstChild("Shadow")
		if ls then
			ls.Transparency = Theme.Transparency.TextShadow + (1 - Theme.Transparency.TextShadow) * hidden
		end
		if vs then
			vs.Transparency = Theme.Transparency.TextShadow + (1 - Theme.Transparency.TextShadow) * hidden
		end
		s.track.BackgroundTransparency = Theme.Transparency.BarTrack + (1 - Theme.Transparency.BarTrack) * hidden
	end
end

-- low-value pulse (and the stamina fade) on the fills
local function updatePulses(t: number)
	for name, s in pairs(stats) do
		local base = 0
		if s.low then
			base = 0.08 + 0.42 * (0.5 + 0.5 * math.sin(t * 6.5))
		end
		local vis = if name == "Stamina" then staminaVis else 1
		local target = 1 - (1 - base) * vis
		if math.abs(target - s.fillT) > 0.01 then
			s.fillT = target
			s.fill.BackgroundTransparency = target
		end
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

local function paintSlot(i: number)
	local r = slotRefs[i]
	if not r then
		return
	end
	local selected = i == equippedSlot and r.itemId ~= nil
	local empty = r.itemId == nil
	Theme.tween(r.card, Theme.Tween.Fast, {
		Position = UDim2.fromOffset(0, if selected then -5 else 0),
		BackgroundColor3 = if selected then C.PanelLight else C.Panel,
		BackgroundTransparency = if selected then 0.2 elseif empty then 0.64 else 0.42,
	})
	r.stroke.Color = if selected then C.Text else C.Stroke
	r.stroke.Transparency = if selected then 0.12 else 0.84
	r.stroke.Thickness = if selected then 1.5 else 1
	r.key.TextColor3 = if selected then C.Text else C.TextDim
end

local function setSlot(i: number, data: any)
	local r = slotRefs[i]
	if not r then
		return
	end
	local id = if type(data) == "table" and type(data.id) == "string" then data.id else nil
	local count = if id then math.max(1, math.floor(tonumber(data.count) or 1)) else 0
	if id ~= r.itemId then
		r.itemId = id
		clearViewport(r.viewport)
		local def = ItemDefs.get(id)
		local hasIcon = id ~= nil and frameIcon(r.viewport, id)
		r.fallback.Visible = id ~= nil and not hasIcon
		r.fallback.Text = if def then string.upper(def.name) elseif id then string.upper(id) else ""
		r.rarity.Visible = def ~= nil
		if def then
			r.rarity.BackgroundColor3 = Theme.Rarity[def.rarity] or C.TextDim
		end
	end
	r.count.Text = if count > 1 then tostring(count) else ""
	paintSlot(i)
end

local function flashItemName(itemId: string?)
	local group = R.itemName
	if not group then
		return
	end
	itemNameToken += 1
	local token = itemNameToken
	local def = ItemDefs.get(itemId)
	if not def then
		Theme.tween(group, Theme.Tween.Fast, { GroupTransparency = 1 })
		return
	end
	R.itemTitle.Text = def.name
	local rarityColor = Theme.Rarity[def.rarity] or C.TextDim
	R.itemSub.Text = string.format(
		"<font color=\"%s\">%s</font>   ·   %s",
		Theme.hex(rarityColor),
		string.upper(tostring(def.rarity)),
		KIND_LABEL[def.kind] or ""
	)
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
	group.GroupTransparency = 1
	group.Position = UDim2.new(0.5, 0, 0, 2)
	Theme.tween(group, Theme.Tween.Normal, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, -4) })
	task.delay(if showDesc then 3.6 else 1.8, function()
		if token == itemNameToken then
			Theme.tween(group, Theme.Tween.FadeOut, { GroupTransparency = 1 })
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
	for i = 1, SLOTS do
		setSlot(i, slots[i])
	end
	if equipChanged then
		for i = 1, SLOTS do
			paintSlot(i)
		end
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
local function removeEntry(entry: any, fast: boolean?)
	if entry.removed then
		return
	end
	entry.removed = true
	local index = table.find(feed, entry)
	if index then
		table.remove(feed, index)
	end
	local info = if fast then Theme.Tween.Fast else Theme.Tween.FadeOut
	Theme.tween(entry.frame, info, { BackgroundTransparency = 1 })
	Theme.tween(entry.mark, info, { BackgroundTransparency = 1 })
	local t = Theme.tween(entry.text, info, { TextTransparency = 1 })
	t.Completed:Once(function()
		entry.frame:Destroy()
	end)
end

local function addKill(data: any)
	if type(data) ~= "table" or not R.killTemplate then
		return
	end
	local victim = if type(data.victim) == "string" then data.victim else "Someone"
	local killer = if type(data.killer) == "string" and data.killer ~= "" then data.killer else nil
	local cause = if type(data.cause) == "string" then data.cause else "Other"
	local weapon = if type(data.weaponName) == "string" and data.weaponName ~= "" then data.weaponName else nil
	if not weapon and type(data.weapon) == "string" then
		local def = ItemDefs.get(data.weapon)
		weapon = if def then def.name else nil
	end
	local me = player.DisplayName
	local dim = Theme.hex(C.TextDim)
	local function name(n: string, isVictim: boolean): string
		local s = "<b>" .. Theme.escape(n) .. "</b>"
		if n == me or n == player.Name then
			return string.format("<font color=\"%s\">%s</font>", Theme.hex(if isVictim then C.Danger else C.AccentSoft), s)
		end
		return s
	end
	local involved = victim == me or killer == me or victim == player.Name or killer == player.Name
	local text
	if type(data.text) == "string" and data.text ~= "" and not killer then
		text = string.format("%s  <font color=\"%s\">%s</font>", name(victim, true), dim, Theme.escape(data.text))
	elseif killer then
		local how = weapon or CAUSE_WITH[cause] or "eliminated"
		if weapon == nil and cause == "Combat" then
			how = "fists"
		end
		text = string.format("%s  <font color=\"%s\">%s</font>  %s", name(killer, false), dim, Theme.escape(how), name(victim, true))
	else
		text = string.format("%s  <font color=\"%s\">%s</font>", name(victim, true), dim, CAUSE_ALONE[cause] or "was eliminated")
	end

	local frame = R.killTemplate:Clone()
	feedCounter += 1
	frame.Name = "Kill" .. feedCounter
	frame.LayoutOrder = feedCounter
	local textLabel = frame:FindFirstChild("Text")
	local mark = frame:FindFirstChild("Mark")
	textLabel.Text = text
	mark.Visible = involved
	frame.BackgroundTransparency = 1
	textLabel.TextTransparency = 1
	frame.Visible = true
	frame.Parent = R.killFeed
	Theme.tween(frame, Theme.Tween.Normal, { BackgroundTransparency = if involved then 0.25 else 0.42 })
	Theme.tween(textLabel, Theme.Tween.Normal, { TextTransparency = 0 })
	local entry = { frame = frame, text = textLabel, mark = mark }
	table.insert(feed, entry)
	local layout = Theme.Layout and Theme.Layout[layoutKey]
	local limit = if layout and layout.KillFeed and layout.KillFeed.max then layout.KillFeed.max elseif touchLayout then 2 else 5
	while #feed > limit do
		removeEntry(feed[1], true)
	end
	task.delay(if involved then 9 else 6.5, function()
		removeEntry(entry)
	end)
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
				shadow = child:FindFirstChild("Shadow"),
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

local function updateWater(camPos: Vector3, heading: number, half: number, pxPerDeg: number, phase: string, combat: boolean, center: any, radius: number?)
	local marker = R.waterMarker
	if not marker then
		return
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
		return
	end
	local wd = wrapDelta(bearing(camPos, point), heading)
	local atEdge = math.abs(wd) > half - 4
	marker.Position = UDim2.new(0.5, math.clamp(wd, -(half - 4), half - 4) * pxPerDeg, 0, 24)
	-- it pulses while the THIRSTY card is up. Off the ribbon it waits at the edge with the distance on the inside and
	-- an arrow toward the water, so the number never disappears.
	local alpha = 0
	if now < waterPulseUntil then
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
	if side < 0 then
		-- at the left edge the label goes to the drop's right (the ribbon clips anything further left)
		R.waterDist.AnchorPoint = Vector2.new(0, 0.5)
		R.waterDist.Position = UDim2.new(1, 3, 0.5, 0)
		R.waterDist.TextXAlignment = Enum.TextXAlignment.Left
	else
		R.waterDist.AnchorPoint = Vector2.new(1, 0.5)
		R.waterDist.Position = UDim2.new(0, -3, 0.5, 0)
		R.waterDist.TextXAlignment = Enum.TextXAlignment.Right
	end
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
						item.inst.TextTransparency = fade
						if item.shadow then
							item.shadow.Transparency = 0.6 + 0.4 * fade
						end
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
	if showSpire then
		local edge = math.abs(d) > half - 4
		local x = math.clamp(d, -(half - 4), half - 4) * pxPerDeg
		R.spire.Position = UDim2.new(0.5, x, 0, 24)
		local feast = GameState:GetAttribute("ArenaEvent") == "Feast"
		local size = if feast then 7 + 2.5 * (0.5 + 0.5 * math.sin(os.clock() * 5)) else 7
		R.spireDiamond.Size = UDim2.fromOffset(size, size)
		R.spireDiamond.BackgroundTransparency = if edge then 0.45 else 0
		-- distance rides next to the marker while it's on the ribbon
		setVisible(R.spireDist, not edge)
		if not edge then
			local text = string.format("%d m", math.floor(spireDistance * STUD_TO_METERS + 0.5))
			if R.spireDist.Text ~= text then
				R.spireDist.Text = text
			end
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
			R.edgeMarker.Position = UDim2.new(0.5, math.clamp(ed, -(half - 4), half - 4) * pxPerDeg, 0, 24)
			R.edgeTick.BackgroundTransparency = if math.abs(ed) > half - 4 then 0.45 else 0
		end
	end

	-- QW10: water for the thirsty
	updateWater(camPos, heading, half, pxPerDeg, phase, combat, center, radius)

	-- the border marker, only while you're outside it
	local showBorder = outside and phase == "Active" and typeof(center) == "Vector3"
	setVisible(R.borderMarker, showBorder)
	if showBorder then
		local b = bearing(camPos, center)
		local bd = wrapDelta(b, heading)
		R.borderMarker.Position = UDim2.new(0.5, math.clamp(bd, -(half - 4), half - 4) * pxPerDeg, 0, 24)
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
	local lead = tonumber(Config.Border.WarningLeadTime) or 30
	if elapsed < shrinkStart and elapsed >= shrinkStart - lead then
		return ThreatLine.line({ name = "Border", verb = "moves", action = toSpire, seconds = (shrinkStart - elapsed) / ts }, short), false
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
		return ThreatLine.line({ name = "Border", verb = "moves", action = if dim then nil else toSpire, seconds = seconds }, short), dim
	end
	return nil, false
end

local function updateInfo(now: number, phase: string)
	local endsAt = tonumber(GameState:GetAttribute("PhaseEndsAt")) or 0
	local showTimer = phase == "Active" and endsAt > 0
	setVisible(R.timer, showTimer)
	setVisible(R.dot, showTimer)
	if showTimer then
		local remaining = math.max(0, endsAt - now)
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

	local eventText: string? = nil
	local eventDim = false
	if phase == "Active" then
		eventText, eventDim = eventLine(now)
	end
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
	local color = if killed then C.Danger elseif headshot then C.AccentSoft else C.Text
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
		R.drawFill.Size = UDim2.fromScale(a, 1)
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
	local rawKey = if text then hint.key else nil
	local now = os.clock()
	if text then
		interactSeen = { text = text, key = rawKey, at = now }
	elseif show and interactSeen and now - interactSeen.at < HINT_HOLD then
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
	if segments then
		local parts = {}
		for _, seg in ipairs(segments) do
			table.insert(parts, seg.kind .. ":" .. seg.text)
		end
		sig = table.concat(parts, "|")
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
	local allowReset = not ClientState.inArena
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
	local showTop = (phase == "Countdown" or phase == "Active") and (ClientState.inArena or spectating) and next(topSuppressed) == nil

	updateBorderState(phase)
	setVisible(R.top, showTop)
	setVisible(R.vitals, combat)
	setVisible(R.hotbar, combat)
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

	local showCenter = combat and not ClientState.menuOpen
	updateCrosshair(showCenter)
	updateUse(showCenter)
	updateDraw(showCenter)
	local interacting = updateInteract(showCenter)
	updateAction(showCenter and not interacting)
	updateDamage(camCF)
	updateVignettes(dt, t, combat)
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
			drankThisRound = true -- the first drink of the round retires the water marker
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

	UserInputService.LastInputTypeChanged:Connect(refreshDeviceHints)
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
