--[[
	NotificationController - announcements and full-screen moments (StarterGui.Overlay, built by UIBuilder).
	Owned by the UI system.
	  * Announce remote: Banner and Warning (one headline at a time, queued), Toast (stacked pills),
	    Countdown (big numbers from GameState.PhaseEndsAt, a BEGIN flash on "GO"), RollCall (a small list beside the sky show; owned by the day/night system),
	    Victory (see below). Unknown styles fall back to a toast.
	  * YouDied: the death screen ("#7 OF 24", killer or cause, weapon) with SPECTATE / CONTINUE, a muted grade.
	    QW4: "OUTLASTED 15 OF 24 · 6:12", and one tip for the cause and weapon class (a more specific one the second
	    time the same thing kills you). SPECTATE opens on your killer (payload killerUserId, else the killer's name).
	    When your death ends the round (a lone practice contender, the runner-up), the death card stays up for
	    DEATH_DWELL s (or until CONTINUE) with the result in its note, and the result card follows. Practice deaths read
	    "FALLEN" (not "#1 OF 1"); a death before the horn (payload phase "Countdown") reads "OUT" with no tip.
	  * QW5: one-time cards for new players (Guidance, through HUDController.guidanceOn): THIRSTY below 60 thirst (it
	    also shows the water marker), HUNGRY below 60 hunger. Cards never show during a Roll Call; they wait for it.
	    They sit at the left (Overlay Cards), clear of the item toast and the held item; toasts sit above the item toast.
	  * QW6: the countdown caption says the goal while the plate rises ("LAST ONE STANDING WINS", with "PRACTICE ROUND"
	    in front in practice) and the choice once it locks ("RUSH THE SPIRE FOR WEAPONS · OR RUN FOR THE TREES"), with a
	    line about the runner's caches for new players; trying to step off the plate brings back "STAY ON YOUR PLATE".
	  * Victory: Phase Ending + WinnerName (or the Victory announce); a special version when you won; then the
	    RoundSummary table. Players who didn't take part in the round get a headline instead.
	Public API (Controllers.NotificationController):
	  announce(payload)                     same shape as the Announce remote
	  toast(text: string, sub: string?, duration: number?)
	  banner(text: string, sub: string?, duration: number?)
	  warning(text: string, sub: string?, duration: number?)
	  card(title: string, text: string | () -> string, opts?)   a card with the toasts; opts: { color: Color3?,
	                                        duration: number?, when: (() -> boolean)?, onShow: (() -> ())? }
	  hideDeathScreen()
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lore = require(Shared:WaitForChild("Lore"))
local Theme = require(Shared:WaitForChild("Theme"))
local Input = require(Shared:WaitForChild("Input"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local DayCycle = require(Shared:WaitForChild("DayCycle"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer
local C = Theme.Colors

local NotificationController = {}
local Controllers: any = nil

local gui: ScreenGui? = nil
local R: { [string]: any } = {}
local started = false
local pending: { any } = {} -- announcements that arrived before the Overlay was ready

local HEADLINE_Y = 0.16
local headlineQueue: { any } = {}
local headlineCurrent: { [string]: any }? = nil
local toasts: { any } = {}
local toastCounter = 0
local countdown = { active = false, last = nil :: number?, caption = "GET READY", flashing = false, flashedRound = nil :: any }
local dimLevels: { [string]: number } = {}
local deathVisible = false
local deathToken = 0
local deathGrade: ColorCorrectionEffect? = nil
local victoryVisible = false
local victoryToken = 0
local victoryRound: any = nil
local summary: { [string]: any }? = nil
local participatedRound: any = nil
local rollToken = 0
local lastDeath: { [string]: any }? = nil
local deathCounts: { [string]: number } = {} -- this session's deaths per tip class
local cardQueue: { any } = {}
local cardsShown: { [string]: boolean } = {}
local pendingVictory: { [string]: any }? = nil -- QW4: your death ended the round; its result waits behind the death card
local DEATH_DWELL = 8 -- seconds a round-ending death card (and its tip) stays before the round's result replaces it
local flushVictory: () -> () = function() end -- shows a pending result (assigned once showVictory exists)

local STUD_TO_METERS = 0.28 -- the same scale as the HUD's distances

-- This device's button, from the HUD (Shared.Glyphs once it exists), as "[E]" in rich text.
local function keyName(action: string): string
	local hud = Controllers and Controllers.HUDController
	if hud and hud.keyName then
		local ok, name = pcall(hud.keyName, action)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	if Input.isTouch() then
		return if action == "Interact" then "DRINK" else "ATTACK"
	elseif Input.isGamepad() then
		return if action == "Interact" then "X" else "RT"
	end
	return if action == "Interact" then "E" else "LMB"
end

local function keyCap(action: string): string
	return "<b>[" .. Theme.escape(keyName(action)) .. "]</b>"
end

local function guidanceOn(): boolean
	local hud = Controllers and Controllers.HUDController
	if hud and hud.guidanceOn then
		local ok, on = pcall(hud.guidanceOn)
		return ok and on == true
	end
	return false
end

local function settingsController()
	return Controllers and Controllers.SettingsController
end

local function setModal(reason: string, on: boolean)
	local sc = settingsController()
	if sc and sc.setModal then
		sc.setModal(reason, on)
	else
		ClientState.menuOpen = on
	end
end

local function isMe(name: any): boolean
	return type(name) == "string" and (name == player.DisplayName or name == player.Name)
end

local function isPhone(): boolean
	return Theme.isSmallScreen()
end

-- On phones the top band is shared: headlines, the roll call and the countdown stand in for the compass block.
local function suppressTop(reason: string, on: boolean)
	local hud = Controllers and Controllers.HUDController
	if hud and hud.suppressTop then
		hud.suppressTop(reason, on)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Dim
--------------------------------------------------------------------------------------------------------------------
local function setDim(reason: string, alpha: number?)
	dimLevels[reason] = alpha
	local top = 0
	for _, a in pairs(dimLevels) do
		top = math.max(top, a)
	end
	if R.dim then
		Theme.tween(R.dim, Theme.Tween.Slow, { BackgroundTransparency = 1 - top })
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Headlines (Banner / Warning)
--------------------------------------------------------------------------------------------------------------------
local nextHeadline: () -> ()

local function playHeadline(item: { [string]: any })
	local token = {}
	headlineCurrent = { token = token }
	local h = R.headline
	local compact = isPhone()
	-- phones: the top band (over the compass) keeps the crosshair clear; elsewhere a little below the compass
	local y = if compact then 0 else HEADLINE_Y
	suppressTop("Headline", compact)
	local eyebrow = item.eyebrow
	R.hEyebrow.Visible = type(eyebrow) == "string" and eyebrow ~= ""
	R.hEyebrow.Text = eyebrow or ""
	R.hEyebrow.TextColor3 = item.eyebrowColor or C.Accent
	R.hTitle.Text = string.upper(item.text)
	R.hTitle.TextSize = if compact then 28 else 40
	R.hTitle.Size = UDim2.new(1, 0, 0, if compact then 34 else 48)
	R.hSub.Visible = type(item.sub) == "string" and item.sub ~= ""
	R.hSub.Text = if type(item.sub) == "string" then Theme.escape(item.sub) else ""
	R.hRule.Visible = not compact
	R.hRule.BackgroundColor3 = item.ruleColor or C.Accent
	R.hRule.Size = UDim2.fromOffset(0, 2)
	h.Visible = true
	h.GroupTransparency = 1
	h.Position = UDim2.new(0.5, 0, y, 10)
	Theme.tween(h, Theme.Tween.Slow, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, y, 0) })
	Theme.tween(R.hRule, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(56, 2) })
	if item.sound then
		Sfx.play(item.sound)
	end
	local duration = math.clamp(tonumber(item.duration) or 3.5, 1.5, 12)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			if not headlineCurrent or headlineCurrent.token ~= token then
				return
			end
			-- something newer is waiting: let it in after a short read
			if #headlineQueue > 0 and os.clock() - t0 >= 1.6 then
				break
			end
			task.wait(0.05)
		end
		if not headlineCurrent or headlineCurrent.token ~= token then
			return
		end
		local t = Theme.tween(h, Theme.Tween.FadeOut, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, y, -6) })
		t.Completed:Wait()
		if headlineCurrent and headlineCurrent.token == token then
			headlineCurrent = nil
			h.Visible = false
			nextHeadline()
		end
	end)
end

nextHeadline = function()
	local item = table.remove(headlineQueue, 1)
	if item then
		playHeadline(item)
	else
		suppressTop("Headline", false)
	end
end

local function clearHeadlines()
	table.clear(headlineQueue)
	headlineCurrent = nil
	suppressTop("Headline", false)
	if R.headline then
		R.headline.Visible = false
	end
end

local function pushHeadline(item: { [string]: any })
	if type(item.text) ~= "string" or item.text == "" then
		return
	end
	if victoryVisible then
		return -- the victory screen owns the stage
	end
	table.insert(headlineQueue, item)
	while #headlineQueue > 3 do
		table.remove(headlineQueue, 1)
	end
	if not headlineCurrent then
		nextHeadline()
	end
end

function NotificationController.banner(text: string, sub: string?, duration: number?)
	pushHeadline({ text = text, sub = sub, duration = duration or 3.5 })
end

function NotificationController.warning(text: string, sub: string?, duration: number?)
	pushHeadline({
		eyebrow = "WARNING",
		eyebrowColor = C.Warning,
		ruleColor = C.Warning,
		text = text,
		sub = sub,
		duration = duration or 5,
	})
end

--------------------------------------------------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------------------------------------------------
local function removeToast(entry: any, fast: boolean?)
	if entry.removed then
		return
	end
	entry.removed = true
	local index = table.find(toasts, entry)
	if index then
		table.remove(toasts, index)
	end
	local info = if fast then Theme.Tween.Fast else Theme.Tween.FadeOut
	local f = entry.frame
	Theme.tween(f, info, { BackgroundTransparency = 1 })
	Theme.tween(entry.stroke, info, { Transparency = 1 })
	Theme.tween(entry.mark, info, { BackgroundTransparency = 1 })
	Theme.tween(entry.sub, info, { TextTransparency = 1 })
	local t = Theme.tween(entry.text, info, { TextTransparency = 1 })
	t.Completed:Once(function()
		f:Destroy()
	end)
end

-- Touch screens: one toast at a time, centred over the hotbar (which sits left of the touch buttons), above the
-- item-name line and below the crosshair; elsewhere up to three, centred above the hotbar.
local function compactToasts(): boolean
	return UserInputService.TouchEnabled
end

local function layoutToasts()
	local container = R.toasts
	if not container then
		return
	end
	-- clear of the HUD's item-name block above the hotbar (60 px tall while it shows an item's description)
	if not compactToasts() then
		container.Position = UDim2.new(0.5, 0, 1, -136)
		return
	end
	local offset = 0
	local hud = Controllers and Controllers.HUDController
	if hud and hud.getHotbarRect and ClientState.inArena and ClientState.alive then
		local ok, pos, size = pcall(hud.getHotbarRect)
		local root = container.Parent
		local scaleObject = root and root:FindFirstChild("Scale")
		if ok and typeof(pos) == "Vector2" and typeof(size) == "Vector2" and size.X > 0 and scaleObject then
			local s = math.max(0.1, scaleObject.Scale)
			local centredX = container.AbsolutePosition.X + container.AbsoluteSize.X / 2 - container.Position.X.Offset * s
			offset = (pos.X + size.X / 2 - centredX) / s
		end
	end
	container.Position = UDim2.new(0.5, math.floor(offset + 0.5), 1, -126)
end

function NotificationController.toast(text: string, sub: string?, duration: number?)
	if type(text) ~= "string" or text == "" then
		return
	end
	if not started then
		table.insert(pending, { style = "Toast", text = text, sub = sub, duration = duration })
		return
	end
	local compact = compactToasts()
	layoutToasts()
	local frame = R.toastTemplate:Clone()
	toastCounter += 1
	frame.Name = "Toast" .. toastCounter
	frame.LayoutOrder = toastCounter
	local textLabel = frame:FindFirstChild("Text")
	local subLabel = frame:FindFirstChild("Sub")
	local mark = frame:FindFirstChild("Mark")
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	textLabel.Text = Theme.escape(text)
	subLabel.Text = if type(sub) == "string" then sub else ""
	subLabel.Visible = subLabel.Text ~= "" and not compact
	local textLimit = textLabel:FindFirstChildOfClass("UISizeConstraint")
	if textLimit and compact then
		textLimit.MaxSize = Vector2.new(290, 36)
	end
	frame.BackgroundTransparency = 1
	textLabel.TextTransparency = 1
	subLabel.TextTransparency = 1
	mark.BackgroundTransparency = 1
	if stroke then
		stroke.Transparency = 1
	end
	frame.Visible = true
	frame.Parent = R.toasts
	Theme.tween(frame, Theme.Tween.Normal, { BackgroundTransparency = 0.2 })
	Theme.tween(textLabel, Theme.Tween.Normal, { TextTransparency = 0 })
	Theme.tween(subLabel, Theme.Tween.Normal, { TextTransparency = 0 })
	Theme.tween(mark, Theme.Tween.Normal, { BackgroundTransparency = 0 })
	if stroke then
		Theme.tween(stroke, Theme.Tween.Normal, { Transparency = 0.85 })
	end
	local entry = { frame = frame, text = textLabel, sub = subLabel, mark = mark, stroke = stroke or Instance.new("UIStroke") }
	table.insert(toasts, entry)
	local limit = if compact then 1 elseif isPhone() then 2 else 3
	-- cards (below) keep their place; the oldest plain toast makes room
	local cards = 0
	for _, e in ipairs(toasts) do
		if e.card then
			cards += 1
		end
	end
	while #toasts > limit + cards do
		local victim = toasts[1]
		for _, e in ipairs(toasts) do
			if not e.card then
				victim = e
				break
			end
		end
		removeToast(victim, true)
	end
	Sfx.play("Notify")
	task.delay(math.clamp(tonumber(duration) or 3, 1.5, 10), function()
		removeToast(entry)
	end)
end

--------------------------------------------------------------------------------------------------------------------
-- Cards (QW5): one-time help for new players, shown with the toasts, never during a Roll Call
--------------------------------------------------------------------------------------------------------------------
local function rollCallActive(): boolean
	if R.roll and R.roll.Visible then
		return true
	end
	local json = GameState:GetAttribute("RollCall")
	if type(json) == "string" and json ~= "" then
		local ok, payload = pcall(function()
			return HttpService:JSONDecode(json)
		end)
		if ok and type(payload) == "table" then
			local startAt = tonumber(payload.startAt) or 0
			local endAt = startAt + (tonumber(payload.duration) or 0)
			local nowT = workspace:GetServerTimeNow()
			return nowT >= startAt - 2 and nowT <= endAt + 1
		end
	end
	return false
end

local function showCard(item: { [string]: any })
	local frame = R.cardTemplate:Clone()
	toastCounter += 1
	frame.Name = "Card" .. toastCounter
	frame.LayoutOrder = toastCounter
	local body = frame:FindFirstChild("Body")
	local title = body and body:FindFirstChild("Title")
	local textLabel = body and body:FindFirstChild("Text")
	local holder = frame:FindFirstChild("MarkHolder")
	local mark = holder and holder:FindFirstChild("Mark")
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if not (title and textLabel and mark) then
		frame:Destroy()
		return
	end
	local text = item.text
	if type(text) == "function" then
		local ok, result = pcall(text)
		text = if ok then result else ""
	end
	title.Text = Theme.escape(tostring(item.title))
	textLabel.Text = tostring(text or "")
	mark.BackgroundColor3 = item.opts.color or C.Accent
	frame.BackgroundTransparency = 1
	title.TextTransparency = 1
	textLabel.TextTransparency = 1
	mark.BackgroundTransparency = 1
	if stroke then
		stroke.Transparency = 1
	end
	layoutToasts()
	frame.Visible = true
	-- cards have their own place at the left (Overlay Cards), so they never cover the item toast or the held item
	frame.Parent = R.cards or R.toasts
	Theme.tween(frame, Theme.Tween.Normal, { BackgroundTransparency = 0.2 })
	Theme.tween(title, Theme.Tween.Normal, { TextTransparency = 0 })
	Theme.tween(textLabel, Theme.Tween.Normal, { TextTransparency = 0 })
	Theme.tween(mark, Theme.Tween.Normal, { BackgroundTransparency = 0 })
	if stroke then
		Theme.tween(stroke, Theme.Tween.Normal, { Transparency = 0.85 })
	end
	local entry = { frame = frame, text = title, sub = textLabel, mark = mark, stroke = stroke or Instance.new("UIStroke"), card = true }
	table.insert(toasts, entry)
	Sfx.play("Notify")
	if item.opts.onShow then
		pcall(item.opts.onShow)
	end
	task.delay(math.clamp(tonumber(item.opts.duration) or 7, 3, 15), function()
		removeToast(entry)
	end)
end

function NotificationController.card(title: string, text: any, opts: { [string]: any }?)
	if type(title) ~= "string" or title == "" then
		return
	end
	table.insert(cardQueue, { title = title, text = text, opts = opts or {} })
end

local function pumpCards()
	if #cardQueue == 0 or not started or not R.cardTemplate then
		return
	end
	if rollCallActive() or victoryVisible or deathVisible then
		return -- wait: never during a Roll Call or over a full-screen moment
	end
	local item = table.remove(cardQueue, 1)
	if item.opts.when then
		local ok, still = pcall(item.opts.when)
		if not ok or not still then
			return -- no longer true (you drank meanwhile, or died)
		end
	end
	showCard(item)
end

-- THIRSTY and HUNGRY, once per session, for new players (Q1 Guidance)
local NEED_CARD_AT = 60
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
local function checkNeeds()
	if not (started and ClientState.inArena and ClientState.alive) or GameState:GetAttribute("Phase") ~= "Active" then
		return
	end
	if not guidanceOn() then
		return
	end
	local function stillInRound(): boolean
		return ClientState.inArena and ClientState.alive and GameState:GetAttribute("Phase") == "Active"
	end
	local thirst = tonumber(player:GetAttribute("Thirst")) or 100
	if thirst < NEED_CARD_AT and not cardsShown.Thirsty then
		cardsShown.Thirsty = true
		NotificationController.card("THIRSTY", function()
			if carriesDrink() then
				return "Hold " .. keyCap("Use") .. " with your bottle to drink. Streams and the lake are drinkable too: look at the water and press " .. keyCap("Interact") .. "."
			end
			-- the HUD shows the water marker with this card (HUDController.pulseWater)
			return "Follow the water drop on your compass. Streams and the lake are drinkable: look at the water and press " .. keyCap("Interact") .. "."
		end, {
			color = C.Thirst,
			duration = 8,
			when = function()
				return stillInRound() and (tonumber(player:GetAttribute("Thirst")) or 100) < NEED_CARD_AT + 10
			end,
			onShow = function()
				local hud = Controllers and Controllers.HUDController
				if hud and hud.pulseWater then
					hud.pulseWater(8)
				end
			end,
		})
	end
	local hunger = tonumber(player:GetAttribute("Hunger")) or 100
	if hunger < NEED_CARD_AT and not cardsShown.Hungry then
		cardsShown.Hungry = true
		NotificationController.card("HUNGRY", function()
			return "Berries and apples are common in crates and on the ground. Hold " .. keyCap("Use") .. " to eat."
		end, {
			color = C.Hunger,
			duration = 8,
			when = function()
				return stillInRound() and (tonumber(player:GetAttribute("Hunger")) or 100) < NEED_CARD_AT + 10
			end,
		})
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Countdown
--------------------------------------------------------------------------------------------------------------------
-- QW6: the goal while the plate rises, then the opening choice once it locks (GameState LaunchAt + LaunchRise), in
-- practice rounds too (a lone newcomer's first round is a practice round). A press that tries to leave the plate
-- brings back "STAY ON YOUR PLATE" for a moment. New players also get a line about the runner's caches (QW7).
local stayUntil = 0
local function launchLocked(): boolean
	local launchAt = tonumber(GameState:GetAttribute("LaunchAt")) or 0
	local rise = tonumber(GameState:GetAttribute("LaunchRise")) or tonumber(Config.Round.LaunchRiseTime) or 3.4
	return launchAt > 0 and workspace:GetServerTimeNow() >= launchAt + rise
end

local function goalCaption(): string
	if os.clock() < stayUntil then
		return "STAY ON YOUR PLATE  ·  THE ARENA OPENS IN {N}"
	end
	if not launchLocked() then
		if GameState:GetAttribute("Practice") == true then
			return if isPhone() then "PRACTICE  ·  LAST ONE STANDING WINS" else "PRACTICE ROUND  ·  LAST ONE STANDING WINS"
		end
		return "LAST ONE STANDING WINS"
	end
	local spire = Lore.upper("Spire")
	return if isPhone() then "RUSH " .. spire .. "  ·  OR RUN" else "RUSH " .. spire .. " FOR WEAPONS  ·  OR RUN FOR THE TREES"
end

-- once the plate locks, new players learn where running pays: the pale flags behind them (every plate faces the Spire)
local function cacheLine(): string?
	if Config.Loot.RunnerCaches == false or os.clock() < stayUntil or not launchLocked() or not guidanceOn() then
		return nil
	end
	local caches = Lore.upper("RunnerCaches")
	return if isPhone() then "PALE FLAGS BEHIND YOU: " .. caches
		else "PALE FLAGS BEHIND YOU MARK " .. caches .. "  ·  A BLADE AND WATER"
end

-- "{N}" in a countdown caption is the seconds left, filled in here so it never lags the number.
local function captionFor(n: number?): string
	local caption = goalCaption()
	if string.find(caption, "{N}", 1, true) then
		caption = string.gsub(caption, "{N}", tostring(n or ""))
	end
	return caption
end

-- the caption pill under the number, and the cache line under it
local function setCaption(n: number?)
	local text = captionFor(n)
	if R.cdCaption.Text ~= text then
		R.cdCaption.Text = text
	end
	R.cdCaption.Visible = text ~= ""
	if R.cdSub then
		local sub = cacheLine()
		R.cdSub.Visible = sub ~= nil
		if sub and R.cdSub.Text ~= sub then
			R.cdSub.Text = sub
		end
	end
end

local function showCountdownNumber(n: number)
	R.countdown.Visible = true
	R.cdNumber.Text = tostring(n)
	R.cdNumber.TextColor3 = C.Text
	R.cdNumber.TextTransparency = 0.4
	R.cdPop.Scale = 1.3
	Theme.tween(R.cdPop, Theme.Tween.Pop, { Scale = 1 })
	Theme.tween(R.cdNumber, Theme.Tween.Pop, { TextTransparency = 0 })
	setCaption(n)
	R.cdCaption.TextTransparency = 0
	Sfx.play("CountdownTick")
end

local function beginFlash()
	local roundId = GameState:GetAttribute("RoundId")
	if countdown.flashing or countdown.flashedRound == roundId then
		return
	end
	countdown.flashing = true
	countdown.flashedRound = roundId
	countdown.active = false
	R.countdown.Visible = true
	R.cdNumber.Text = "BEGIN"
	R.cdNumber.TextColor3 = C.Accent
	R.cdNumber.TextTransparency = 0
	R.cdCaption.Text = ""
	R.cdCaption.Visible = false
	if R.cdSub then
		R.cdSub.Visible = false
	end
	R.cdPop.Scale = 0.86
	Theme.tween(R.cdPop, TweenInfo.new(1.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1.06 })
	task.delay(0.8, function()
		local t = Theme.tween(R.cdNumber, Theme.Tween.FadeOut, { TextTransparency = 1 })
		t.Completed:Wait()
		countdown.flashing = false
		if not countdown.active then
			R.countdown.Visible = false
			suppressTop("Countdown", false)
		end
	end)
end

local function updateCountdown()
	local phase = GameState:GetAttribute("Phase")
	if phase == "Countdown" and ClientState.inArena then
		if not countdown.active then
			countdown.active = true
			countdown.last = nil
			-- phones: smaller numbers, and they take the top band for these few seconds
			local compact = isPhone()
			R.cdNumber.TextSize = if compact then 96 else 132
			R.cdNumber.Size = UDim2.new(1, 0, 0, if compact then 112 else 160)
			R.cdCaption.Position = UDim2.new(0.5, 0, 0, if compact then 114 else 164)
			R.cdCaption.TextSize = if compact then 17 else 22
			if R.cdSub then
				R.cdSub.Position = UDim2.new(0.5, 0, 0, if compact then 146 else 204)
				R.cdSub.TextSize = if compact then 14 else 15
			end
			suppressTop("Countdown", compact)
		end
		local endsAt = tonumber(GameState:GetAttribute("PhaseEndsAt")) or 0
		local n = math.ceil(endsAt - workspace:GetServerTimeNow())
		if n >= 1 and n ~= countdown.last and not countdown.flashing then
			countdown.last = n
			showCountdownNumber(math.min(n, 99))
		end
	elseif countdown.active then
		countdown.active = false
		if phase == "Active" and ClientState.inArena then
			beginFlash()
		end
		if not countdown.flashing then
			R.countdown.Visible = false
			suppressTop("Countdown", false)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Death screen
--------------------------------------------------------------------------------------------------------------------
local function setGrade(on: boolean)
	if on then
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if not deathGrade or not deathGrade.Parent then
			local grade = Instance.new("ColorCorrectionEffect")
			grade.Name = "UI_DeathGrade"
			grade.Parent = camera
			deathGrade = grade
		end
		Theme.tween(deathGrade :: ColorCorrectionEffect, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Saturation = -0.75,
			Contrast = 0.06,
			Brightness = -0.04,
		})
	elseif deathGrade then
		local grade = deathGrade
		deathGrade = nil
		local t = Theme.tween(grade, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			Saturation = 0,
			Contrast = 0,
			Brightness = 0,
		})
		t.Completed:Once(function()
			grade:Destroy()
		end)
	end
end

local function canSpectate(): boolean
	local spectate = Controllers and Controllers.SpectateController
	if spectate and spectate.canSpectate then
		local ok, result = pcall(spectate.canSpectate)
		return ok and result == true
	end
	return false
end

-- QW4: the contender who killed you, if they're still alive (YouDied killerUserId, else their display name).
local function killerOf(data: any): Player?
	if type(data) ~= "table" then
		return nil
	end
	local id = tonumber(data.killerUserId)
	local found: Player? = if id and id > 0 then Players:GetPlayerByUserId(id) else nil
	if not found and type(data.killer) == "string" and data.killer ~= "" then
		for _, other in ipairs(Players:GetPlayers()) do
			if other.DisplayName == data.killer or other.Name == data.killer then
				found = other
				break
			end
		end
	end
	if found and found ~= player and found:GetAttribute("Alive") == true then
		return found
	end
	return nil
end

local function refreshDeathButtons()
	local can = canSpectate()
	if R.dSpectate.Visible ~= can then
		R.dSpectate.Visible = can
		if Input.isGamepad() and deathVisible then
			GuiService.SelectedObject = if can then R.dSpectate else R.dContinue
		end
	end
	if pendingVictory then
		R.dNote.Text = pendingVictory.note or "" -- the round is over: its result, until the card gives way to it
	elseif ClientState.inArena then
		R.dNote.Text = "Returning to the lobby"
	else
		local killer = if can then killerOf(lastDeath) else nil
		R.dNote.Text = if killer then "SPECTATE follows <b>" .. Theme.escape(killer.DisplayName) .. "</b>"
			elseif can then "Watch the contenders who remain"
			else ""
	end
end

-- QW4: one tip per cause and weapon class. The second time the same thing kills you, a more specific one. Every tip is
-- something you can see or do today; numbers come from Config and ItemDefs so they stay true when retuned.
local function meters(studs: number): number
	return math.max(1, math.floor(studs * STUD_TO_METERS + 0.5))
end

local function minutes(seconds: number): number
	return math.max(1, math.floor(seconds / 60 + 0.5))
end

local TIPS: { [string]: { () -> string } } = {
	Thirst = {
		function()
			return "Look at any stream or the lake and press " .. keyCap("Interact") .. ". Fill empty bottles too."
		end,
		function()
			local full = 100 / math.max(1e-3, tonumber(Config.Survival.ThirstDrainPerSecond) or 0.185)
			local sprint = full / math.max(1, tonumber(Config.Survival.SprintDrainMultiplier) or 1.6)
			return string.format("A full thirst bar lasts about %d minutes, %d if you sprint. Drink at every stream you pass, and keep a full bottle.", minutes(full), minutes(sprint))
		end,
	},
	Hunger = {
		function()
			return "Hold " .. keyCap("Use") .. " with food in hand. Berries and apples are common in crates and on the ground."
		end,
		function()
			return string.format("Below %d hunger or thirst your health stops coming back. Eat before the bar gets there, and keep food in your bag.", tonumber(Config.Survival.RegenMinStat) or 55)
		end,
	},
	Border = {
		function()
			return "From the second morning " .. Lore.Border .. " closes on " .. Lore.Spire .. ". Head in when the timer shows."
		end,
		function()
			return string.format("Outside %s you lose %d health a second, %d once it has closed. Near its edge the compass shows how far it is.",
				Lore.Border, tonumber(Config.Border.DamagePerSecond) or 4, tonumber(Config.Border.LateDamagePerSecond) or 10)
		end,
	},
	Fall = {
		function()
			return string.format("Drops of more than about %d m hurt. Climb down, or drop into water.", meters(tonumber(Config.Movement.FallDamage.MinHeight) or 13))
		end,
		function()
			return string.format("A drop of about %d m kills from full health. Find a slope, climb down a tree, or land in deep water.", meters(tonumber(Config.Movement.FallDamage.LethalHeight) or 58))
		end,
	},
	Bow = {
		function()
			local bow = ItemDefs.get("bow")
			local draw = (bow and bow.drawTime) or 0.9
			local time = if draw <= 1.3 then "about a second" else string.format("about %d seconds", math.floor(draw + 0.5))
			return "An archer needs " .. time .. " to draw. Keep moving, zig-zag, and break their line of sight behind trees."
		end,
		function()
			local bow = ItemDefs.get("bow")
			local damage = (bow and bow.damageMax) or 50
			local head = math.floor(damage * ((bow and bow.headshotMultiplier) or 2) + 0.5)
			return string.format("A full-draw arrow hits for %d, %d to the head. Move from tree to tree, and never stop in the open.", damage, head)
		end,
	},
	Melee = {
		function()
			return "Fists barely scratch. Arm yourself before you fight, and back off to bandage when a fight turns against you."
		end,
		function()
			local fists, knife = ItemDefs.get("fists"), ItemDefs.get("knife")
			return string.format("Fists do %d damage, a %s %d. Open crates for a blade before you pick a fight, and carry a bandage.",
				(fists and fists.damage) or 8, (knife and knife.name) or "Hunting Knife", (knife and knife.damage) or 22)
		end,
	},
	Spear = {
		function()
			local spear = ItemDefs.get("spear")
			return string.format("A thrown spear hits for %d, more than half your health. Keep moving, and keep cover between you and anyone carrying one.", (spear and spear.throwDamage) or 60)
		end,
		function()
			return "A thrown spear stays where it lands until someone picks it up. Make them throw it, then close in."
		end,
	},
	Thrown = {
		function()
			local knife = ItemDefs.get("throwing_knife")
			return string.format("A throwing knife hits for %d. Keep moving, and keep cover between you and anyone throwing them.", (knife and knife.damage) or 28)
		end,
		function()
			return "Thrown knives stay where they land until they're picked up. Make them throw, then close in."
		end,
	},
	Other = {
		function()
			return string.format("Keep hunger and thirst above %d and your health comes back on its own.", tonumber(Config.Survival.RegenMinStat) or 55)
		end,
	},
}

local function tipClass(data: { [string]: any }): string
	local cause = data.cause
	if cause == "Dehydration" then
		return "Thirst"
	elseif cause == "Starvation" then
		return "Hunger"
	elseif cause == "Border" then
		return "Border"
	elseif cause == "Fall" then
		return "Fall"
	elseif cause == "Combat" then
		local def = if type(data.weapon) == "string" then ItemDefs.get(data.weapon) else nil
		if def then
			if def.kind == "Bow" or def.kind == "Ammo" then
				return "Bow"
			elseif def.id == "spear" then
				return "Spear"
			elseif def.kind == "Throwable" then
				return "Thrown"
			end
		end
		return "Melee" -- a blade, or fists
	end
	return "Other"
end

local function tipFor(data: { [string]: any }): string?
	local class = tipClass(data)
	local list = TIPS[class]
	if not list or #list == 0 then
		return nil
	end
	local count = (deathCounts[class] or 0) + 1
	deathCounts[class] = count
	local ok, text = pcall(list[math.min(count, #list)])
	return if ok and type(text) == "string" and text ~= "" then text else nil
end

-- "OUTLASTED 15 OF 24  ·  6:12" (practice, or the first to fall: "SURVIVED  6:12")
local function progressLine(data: { [string]: any }): string?
	local placement = math.floor(tonumber(data.placement) or 0)
	local total = math.max(placement, math.floor(tonumber(data.total) or 0))
	local startedAt = tonumber(GameState:GetAttribute("RoundStartedAt")) or 0
	local timeText = if startedAt > 0 then Util.formatTime(math.max(0, workspace:GetServerTimeNow() - startedAt)) else nil
	local outlasted = total - placement
	if placement <= 0 or total <= 1 or outlasted <= 0 or GameState:GetAttribute("Practice") == true then
		return if timeText then "SURVIVED  " .. timeText else nil
	end
	local text = string.format("OUTLASTED %d OF %d", outlasted, total)
	if timeText then
		text ..= "  ·  " .. timeText
	end
	return text
end

local function causeLine(data: { [string]: any }): string
	local killer = if type(data.killer) == "string" and data.killer ~= "" then "<b>" .. Theme.escape(data.killer) .. "</b>" else nil
	local weapon = if type(data.weaponName) == "string" and data.weaponName ~= "" then data.weaponName else nil
	if not weapon and type(data.weapon) == "string" then
		local def = ItemDefs.get(data.weapon)
		weapon = if def then def.name else nil
	end
	local cause = data.cause
	if cause == "Combat" then
		if killer and weapon then
			return string.format("Eliminated by %s   ·   %s", killer, Theme.escape(weapon))
		elseif killer then
			return "Eliminated by " .. killer
		end
		return "Eliminated in combat"
	elseif cause == "Fall" then
		return if killer then "You fell to your death   ·   chased by " .. killer else "You fell to your death"
	elseif cause == "Border" then
		return if killer then "Caught outside the border   ·   after a fight with " .. killer else "Caught outside the border"
	elseif cause == "Starvation" then
		return "You starved"
	elseif cause == "Dehydration" then
		return "You died of thirst"
	end
	return if killer then "Eliminated by " .. killer else "You were eliminated"
end

local function hideDeath()
	if not deathVisible then
		return
	end
	deathVisible = false
	deathToken += 1
	local token = deathToken
	setModal("Death", false)
	setDim("Death", nil)
	setGrade(false)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(R.death) then
		GuiService.SelectedObject = nil
	end
	local t = Theme.tween(R.dPanel, Theme.Tween.Normal, { GroupTransparency = 1 })
	t.Completed:Once(function()
		if token == deathToken and not deathVisible then
			R.death.Visible = false
		end
	end)
	if pendingVictory then
		task.defer(flushVictory) -- the round's result, now that the death card has had its say
	end
end
NotificationController.hideDeathScreen = hideDeath

local function showDeath(data: any)
	if type(data) ~= "table" or victoryVisible then
		return
	end
	participatedRound = GameState:GetAttribute("RoundId")
	deathToken += 1
	local token = deathToken
	-- a help card still up (THIRSTY on the way to dying of thirst) gives way to the death card and its tip
	for _, entry in ipairs(table.clone(toasts)) do
		if entry.card then
			removeToast(entry, true)
		end
	end
	local placement = math.floor(tonumber(data.placement) or 0)
	local total = math.max(placement, math.floor(tonumber(data.total) or 0))
	-- a practice death is not "#1 OF 1"; a death before the horn (a reset on the plate) is not an elimination
	local practice = data.practice == true or (data.practice == nil and GameState:GetAttribute("Practice") == true)
	local beforeHorn = data.phase == "Countdown"
	if R.dEyebrow then
		R.dEyebrow.Text = if beforeHorn then (if practice then "PRACTICE CANCELLED" else "OUT OF THE ROUND")
			elseif practice then "PRACTICE ROUND"
			else "ELIMINATED"
		R.dEyebrow.TextColor3 = if practice and not beforeHorn then C.AccentSoft else C.Danger
	end
	if beforeHorn then
		R.dTitle.Text = "OUT"
	elseif placement > 0 and not practice then
		R.dTitle.Text = string.format("#%d<font size=\"30\" color=\"%s\">   OF %d</font>", placement, Theme.hex(C.TextDim), total)
	else
		R.dTitle.Text = "FALLEN"
	end
	R.dCause.Text = if beforeHorn then "You left your plate before the horn" else causeLine(data)
	lastDeath = data
	if R.dProgress then
		local progress = if beforeHorn then nil else progressLine(data)
		R.dProgress.Visible = progress ~= nil
		R.dProgress.Text = progress or ""
	end
	if R.dTip then
		local tip = if beforeHorn then nil else tipFor(data)
		R.dTip.Visible = tip ~= nil
		R.dTip.Text = if tip then string.format("<font color=\"%s\">TIP</font>   %s", Theme.hex(C.TextDim), tip) else ""
	end
	deathVisible = true
	R.dSpectate.Visible = false
	refreshDeathButtons()
	R.death.Visible = true
	R.dPanel.GroupTransparency = 1
	R.dPanel.Position = UDim2.new(0.5, 0, 0.5, 14)
	Theme.tween(R.dPanel, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = UDim2.fromScale(0.5, 0.5),
	})
	setDim("Death", 0.55)
	setModal("Death", true)
	setGrade(true)
	if Input.isGamepad() then
		GuiService.SelectedObject = if R.dSpectate.Visible then R.dSpectate else R.dContinue
	end
	task.spawn(function()
		local t0 = os.clock()
		while token == deathToken and deathVisible do
			local age = os.clock() - t0
			-- QW4: when this death ended the round, its card (and tip) stays DEATH_DWELL s, then the result follows
			if age > 15 or (pendingVictory ~= nil and age >= DEATH_DWELL) then
				hideDeath()
				break
			end
			refreshDeathButtons()
			task.wait(0.25)
		end
	end)
end

--------------------------------------------------------------------------------------------------------------------
-- Victory + round summary
--------------------------------------------------------------------------------------------------------------------
local function populateSummary(data: { [string]: any })
	local rowsFrame = R.vRows
	for _, child in ipairs(rowsFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local placements = if type(data.placements) == "table" then data.placements else {}
	local list = {}
	for _, entry in ipairs(placements) do
		if type(entry) == "table" then
			table.insert(list, entry)
		end
	end
	local function isLocal(entry): boolean
		if tonumber(entry.userId) then
			return tonumber(entry.userId) == player.UserId
		end
		return isMe(entry.name)
	end
	local shown = {}
	local localShown = false
	for i, entry in ipairs(list) do
		if i <= 10 then
			table.insert(shown, entry)
			localShown = localShown or isLocal(entry)
		end
	end
	if not localShown then
		for _, entry in ipairs(list) do
			if isLocal(entry) then
				table.insert(shown, entry)
				break
			end
		end
	end
	for i, entry in ipairs(shown) do
		local row = R.summaryTemplate:Clone()
		row.Name = "Row" .. i
		row.LayoutOrder = i
		local placement = math.floor(tonumber(entry.placement) or 0)
		local mine = isLocal(entry)
		row.Rank.Text = if placement > 0 then "#" .. placement else "–"
		row.Rank.TextColor3 = if placement == 1 then C.Gold else C.TextDim
		row.PlayerName.Text = Theme.escape(tostring(entry.name or "?")) .. (if mine then string.format("  <font color=\"%s\">YOU</font>", Theme.hex(C.AccentSoft)) else "")
		row.PlayerName.FontFace = if mine or placement == 1 then Theme.Fonts.BodyBold else Theme.Fonts.Body
		row.Kills.Text = tostring(math.floor(tonumber(entry.kills) or 0))
		row.Mark.Visible = mine
		row.BackgroundTransparency = if mine then 0.55 else 1
		for _, label in ipairs({ row.Rank, row.PlayerName, row.Kills }) do
			label.TextTransparency = 1
		end
		row.Visible = true
		row.Parent = rowsFrame
		task.delay(0.05 * i, function()
			for _, label in ipairs({ row.Rank, row.PlayerName, row.Kills }) do
				Theme.tween(label, Theme.Tween.Normal, { TextTransparency = 0 })
			end
		end)
	end
	local duration = tonumber(data.duration) or 0
	R.vFooter.Text = string.format("ROUND TIME  %s     ·     %d %s", Util.formatTime(duration), #list, if #list == 1 then "CONTENDER" else "CONTENDERS")
	R.vSummary.Visible = #shown > 0
end

-- Compact on phones so the summary table keeps a few readable rows.
local function applyVictoryLayout()
	local compact = isPhone()
	local panel = R.vPanel
	panel.Size = if compact then UDim2.new(1, -24, 1, -8) else UDim2.new(1, -40, 0.88, 0)
	R.vTitle.TextSize = if compact then 44 else 64
	R.vTitle.Position = UDim2.fromOffset(0, if compact then 18 else 20)
	R.vTitle.Size = UDim2.new(1, 0, 0, if compact then 50 else 72)
	R.vSub.Position = UDim2.fromOffset(0, if compact then 68 else 94)
	R.vSummary.Position = UDim2.fromOffset(1, if compact then 96 else 132)
	R.vSummary.Size = UDim2.new(1, -2, 1, if compact then -97 else -133)
end

local function hideVictory(immediate: boolean?)
	if not victoryVisible then
		return
	end
	victoryVisible = false
	victoryToken += 1
	local token = victoryToken
	setDim("Victory", nil)
	if immediate then
		R.victory.Visible = false
		return
	end
	local t = Theme.tween(R.vPanel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { GroupTransparency = 1 })
	t.Completed:Once(function()
		if token == victoryToken and not victoryVisible then
			R.victory.Visible = false
		end
	end)
end

local function showVictory(text: string?, sub: string?, winner: any, fallback: boolean?)
	local roundId = GameState:GetAttribute("RoundId")
	local winnerName = if type(winner) == "string" and winner ~= "" then winner else nil
	local participated = participatedRound ~= nil and participatedRound == roundId
	local won = participated and isMe(winnerName)
	local practice = GameState:GetAttribute("Practice") == true
	local title = if type(text) == "string" and text ~= "" then text elseif winnerName then winnerName else "ROUND OVER"
	local subText = if type(sub) == "string" then sub elseif winnerName then "is the last one standing" else ""
	if victoryRound == roundId and victoryVisible then
		-- the attribute fallback already showed it; refresh the words from the announcement
		if not won then
			R.vTitle.Text = string.upper(title)
			R.vSub.Text = Theme.escape(subText)
		end
		return
	end
	if victoryRound == roundId then
		return
	end
	-- QW4: when your death ended the round (a lone practice contender, the runner-up), the death card and its tip stay
	-- up first and its note gives the result; the full result follows after DEATH_DWELL s or CONTINUE (flushVictory)
	if participated and deathVisible then
		if not (fallback and pendingVictory and pendingVictory.roundId == roundId) then
			local note
			if practice then
				note = "Practice over  ·  a new round starts soon"
			elseif winnerName then
				note = "<b>" .. Theme.escape(winnerName) .. "</b> " .. Theme.escape(subText)
			else
				note = Theme.escape(string.upper(title))
			end
			pendingVictory = { roundId = roundId, text = text, sub = sub, winner = winner, note = note }
		end
		refreshDeathButtons()
		return
	end
	pendingVictory = nil
	victoryRound = roundId
	if not participated then
		pushHeadline({ eyebrow = "ROUND OVER", eyebrowColor = C.Gold, ruleColor = C.Gold, text = title, sub = subText, duration = 5 })
		return
	end

	hideDeath()
	clearHeadlines()
	victoryVisible = true
	victoryToken += 1
	local token = victoryToken
	local kills = math.floor(tonumber(player:GetAttribute("Kills")) or 0)
	if won then
		R.vEyebrow.Text = if practice then "PRACTICE ROUND" else "THE LAST ONE STANDING"
		R.vTitle.Text = if practice then "SURVIVED" else "VICTORY"
		R.vTitle.TextColor3 = C.Gold
		local startedCount = math.floor(tonumber(GameState:GetAttribute("StartedCount")) or 0)
		if practice or startedCount <= 1 then
			R.vSub.Text = string.format("%d %s", kills, if kills == 1 then "elimination" else "eliminations")
		else
			R.vSub.Text = string.format("You outlasted %d contenders   ·   <b>%d</b> %s", startedCount - 1, kills, if kills == 1 then "elimination" else "eliminations")
		end
	else
		R.vEyebrow.Text = "THE ROUND IS OVER"
		R.vTitle.Text = string.upper(title)
		R.vTitle.TextColor3 = C.Text
		R.vSub.Text = Theme.escape(subText)
	end
	applyVictoryLayout()
	local topY = if isPhone() then 0 else 0.06
	R.vSummary.Visible = false
	R.victory.Visible = true
	R.vPanel.GroupTransparency = 1
	R.vPanel.Position = UDim2.new(0.5, 0, topY, 16)
	Theme.tween(R.vPanel, TweenInfo.new(1.0, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = UDim2.fromScale(0.5, topY),
	})
	setDim("Victory", 0.5)
	Sfx.play("Victory")
	task.delay(1.3, function()
		if token == victoryToken and summary and summary.roundId == roundId then
			populateSummary(summary.data)
		end
	end)
end

-- The result that waited for a round-ending death card (QW4). Already back in the lobby, it goes after a short read.
flushVictory = function()
	local p = pendingVictory
	pendingVictory = nil
	if not p or deathVisible then
		return
	end
	local phase = GameState:GetAttribute("Phase")
	if p.roundId ~= GameState:GetAttribute("RoundId") or phase == "Countdown" or phase == "Active" then
		return
	end
	showVictory(p.text, p.sub, p.winner)
	if victoryVisible and (phase == "Lobby" or phase == "Intermission") then
		local token = victoryToken
		task.delay(if summary and summary.roundId == p.roundId then 7 else 4, function()
			if token == victoryToken then
				hideVictory(false)
			end
		end)
	end
end

local function onSummary(data: any)
	if type(data) ~= "table" then
		return
	end
	local roundId = GameState:GetAttribute("RoundId")
	summary = { roundId = roundId, data = data }
	if victoryVisible and victoryRound == roundId then
		local token = victoryToken
		task.delay(1.0, function()
			if token == victoryToken and victoryVisible then
				populateSummary(data)
			end
		end)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Roll Call (owned by the day/night system): a small, accessible list beside the 3D "The Fallen" show in the sky
-- (FallenRecapController). Names appear as their busts form, on the show's own timeline (Shared.DayCycle).
--------------------------------------------------------------------------------------------------------------------
local lastRollId: any = nil

local BEARINGS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function bearingName(degrees: number?): string?
	if type(degrees) ~= "number" then
		return nil
	end
	return BEARINGS[(math.floor((degrees % 360) / 45 + 0.5) % 8) + 1]
end

local function showRollCall(payload: { [string]: any })
	if payload.id ~= nil and payload.id == lastRollId then
		return
	end
	if payload.list == false then
		return -- the epilogue (QW14): the sky show alone, behind the winner card's placements
	end
	local names = {}
	if type(payload.names) == "table" then
		for _, n in ipairs(payload.names) do
			if type(n) == "string" and n ~= "" then
				table.insert(names, n)
			end
		end
	end
	local timeline = DayCycle.recapTimeline(#names, if type(payload.mode) == "string" then payload.mode else nil)
	local nowT = workspace:GetServerTimeNow()
	local startAt = tonumber(payload.startAt) or nowT
	local endAt = startAt + (tonumber(payload.duration) or timeline.total)
	if nowT > endAt - 1 then
		return
	end
	lastRollId = payload.id
	rollToken += 1
	local token = rollToken
	for _, child in ipairs(R.rollNames:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local compact = isPhone()
	local day = tonumber(payload.day)
	R.rollTitle.Text = "THE FALLEN"
	R.rollSub.Text = if type(payload.sub) == "string" then payload.sub
		elseif day then string.format("Day %d", day) else ""
	local grid = R.rollNames:FindFirstChildOfClass("UIGridLayout")
	local labels = {}
	local shown = names
	local revealIndex = {} -- label index -> name index (for the timing)
	if compact then
		-- phones: the top band for a short while (the compass gives way meanwhile); the names flow on one line
		R.rollTitle.Position = UDim2.fromOffset(0, 8)
		R.rollRule.Visible = false
		R.rollSub.Visible = false
		R.rollNames.Visible = false
		R.rollLine.Visible = true
		R.rollLine.Position = UDim2.fromOffset(16, 36)
		R.rollLine.Size = UDim2.new(1, -32, 0, 42)
		R.rollLine.Text = Theme.escape(R.rollSub.Text)
		R.roll.AnchorPoint = Vector2.new(0.5, 0)
		R.roll.Position = UDim2.new(0.5, 0, 0, 0)
		R.roll.Size = UDim2.new(1, -40, 0, 86)
		R.rollConstraint.MaxSize = Vector2.new(560, 86)
	else
		-- a slim panel at the right edge
		local cols = if #names > 8 then 2 else 1
		local maxShown = if cols == 2 then 20 else 8
		if #names > maxShown then
			shown = table.move(names, 1, maxShown - 1, 1, {})
			table.insert(shown, string.format("+%d more", #names - (maxShown - 1)))
		end
		local rows = math.max(1, math.ceil(#shown / cols))
		local width = if cols == 2 then 320 else 250
		local height = 84 + (if #shown > 0 then rows * 24 + 8 else 0) + 28
		R.rollTitle.Position = UDim2.fromOffset(0, 16)
		R.rollRule.Visible = true
		R.rollRule.Position = UDim2.new(0.5, 0, 0, 46)
		R.rollSub.Visible = true
		R.rollSub.Position = UDim2.fromOffset(0, 52)
		R.rollNames.Visible = true
		R.rollNames.Position = UDim2.new(0.5, 0, 0, 80)
		R.rollNames.Size = UDim2.new(1, -28, 1, -112)
		if grid then
			grid.CellSize = UDim2.new(1 / cols, -6, 0, 20)
			grid.CellPadding = UDim2.fromOffset(6, 4)
		end
		R.rollLine.Visible = true
		R.rollLine.Position = UDim2.new(0, 14, 1, -30)
		R.rollLine.Size = UDim2.new(1, -28, 0, 20)
		R.rollLine.Text = ""
		R.roll.AnchorPoint = Vector2.new(1, 0.5)
		R.roll.Position = UDim2.new(1, -18, 0.44, 0)
		R.roll.Size = UDim2.fromOffset(width, height)
		R.rollConstraint.MaxSize = Vector2.new(width, height)
		for i, n in ipairs(shown) do
			local l = R.rollTemplate:Clone()
			l.Name = "Name" .. i
			l.Text = n
			l.TextSize = if cols == 2 then 14 else 16
			l.TextTruncate = Enum.TextTruncate.AtEnd
			l.LayoutOrder = i
			l.TextTransparency = 1
			l.Visible = true
			l.Parent = R.rollNames
			table.insert(labels, l)
			revealIndex[i] = if i < maxShown or #names <= maxShown then i else #names
		end
	end
	R.roll.Visible = true
	R.roll.GroupTransparency = 1
	if compact then
		suppressTop("RollCall", true)
	end
	task.spawn(function()
		local function waitUntil(t: number): boolean
			while workspace:GetServerTimeNow() < t do
				task.wait(0.05)
				if token ~= rollToken then
					return false
				end
			end
			return token == rollToken
		end
		if not waitUntil(startAt) then
			return
		end
		Theme.tween(R.roll, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 })
		-- where to look (the display hangs at a fixed bearing for this player)
		task.delay(0.3, function()
			if token ~= rollToken then
				return
			end
			local recap = Controllers and Controllers.FallenRecapController
			local bearing = recap and recap.getBearing and bearingName(recap.getBearing())
			-- a Roll Call during the finale has no sky show (QW14): nothing to look up at
			local hint = if payload.sky == false then ""
				elseif bearing then "LOOK UP · IN THE SKY TO THE " .. bearing
				else "LOOK UP"
			if compact then
				R.rollLine.Text = Theme.escape(hint)
			else
				R.rollLine.Text = hint
				R.rollLine.TextTransparency = 0.25
			end
		end)
		local phoneUntil = startAt + 14
		local revealed = {}
		for i = 1, #shown do
			local at = startAt + (timeline.revealAt[revealIndex[i] or i] or 0) - 0.3
			if compact and at > phoneUntil then
				break
			end
			if not waitUntil(at) then
				return
			end
			if compact then
				table.insert(revealed, Theme.escape(shown[i]))
				R.rollLine.Text = table.concat(revealed, string.format("<font color=\"%s\">   ·   </font>", Theme.hex(C.TextDim)))
			elseif labels[i] then
				Theme.tween(labels[i], TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 })
			end
		end
		local closeAt = if compact then math.min(endAt - 1.4, math.max(phoneUntil, startAt + 6)) else endAt - 1.6
		if not waitUntil(closeAt) then
			return
		end
		local t = Theme.tween(R.roll, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { GroupTransparency = 1 })
		t.Completed:Wait()
		if token == rollToken then
			R.roll.Visible = false
			suppressTop("RollCall", false)
		end
	end)
end

-- A show already running when this player arrived (GameState "RollCall").
local function resumeRollCall()
	local json = GameState:GetAttribute("RollCall")
	if type(json) ~= "string" or json == "" then
		return
	end
	local ok, payload = pcall(function()
		return game:GetService("HttpService"):JSONDecode(json)
	end)
	if ok and type(payload) == "table" then
		showRollCall(payload)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Announce
--------------------------------------------------------------------------------------------------------------------
local function onAnnounce(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if not started then
		table.insert(pending, payload)
		return
	end
	local style = payload.style
	local text = if type(payload.text) == "string" then payload.text else ""
	local sub = if type(payload.sub) == "string" then payload.sub else nil
	local duration = tonumber(payload.duration)
	if style == "Banner" then
		NotificationController.banner(text, sub, duration)
	elseif style == "Warning" then
		NotificationController.warning(text, sub, duration)
	elseif style == "Toast" then
		NotificationController.toast(text, sub, duration)
	elseif style == "Countdown" then
		local upper = string.upper(text)
		if upper == "GO" or upper == "BEGIN" then
			if ClientState.inArena then
				beginFlash()
			end
		else
			if sub then
				countdown.caption = string.upper(sub)
				if countdown.active and not countdown.flashing then
					setCaption(countdown.last)
				end
			end
			if GameState:GetAttribute("Phase") ~= "Countdown" and text ~= "" then
				NotificationController.toast(text, sub, duration)
			end
		end
	elseif style == "RollCall" then
		showRollCall(payload)
	elseif style == "Victory" then
		showVictory(text, sub, payload.winner)
	elseif text ~= "" then
		NotificationController.toast(text, sub, duration)
	end
end

function NotificationController.announce(payload: { [string]: any })
	onAnnounce(payload)
end

-- Frozen on a launch plate and trying to move: the countdown caption answers (LaunchController calls this).
local lastPulse = 0
local captionColor: Color3? = nil
function NotificationController.pulseCountdown()
	if not (started and countdown.active and R.countdown and R.countdown.Visible) then
		return
	end
	local t = os.clock()
	if t - lastPulse < 0.7 then
		return
	end
	lastPulse = t
	-- the answer to the press: "STAY ON YOUR PLATE · THE ARENA OPENS IN 6" for a moment, then the goal again
	stayUntil = t + 1.6
	setCaption(countdown.last)
	task.delay(1.65, function()
		if countdown.active and R.cdCaption and not countdown.flashing then
			setCaption(countdown.last)
		end
	end)
	captionColor = captionColor or R.cdCaption.TextColor3
	R.cdCaption.TextColor3 = C.Accent
	R.cdCaption.TextTransparency = 0
	Theme.tween(R.cdCaption, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = captionColor })
	R.cdPop.Scale = 1.08
	Theme.tween(R.cdPop, Theme.Tween.Pop, { Scale = 1 })
end

--------------------------------------------------------------------------------------------------------------------
-- Phases
--------------------------------------------------------------------------------------------------------------------
local function onPhase()
	local phase = GameState:GetAttribute("Phase")
	local roundId = GameState:GetAttribute("RoundId")
	if (phase == "Countdown" or phase == "Active") and ClientState.inArena then
		participatedRound = roundId
	end
	if phase == "Countdown" then
		countdown.caption = "GET READY"
		pendingVictory = nil -- a new round: last round's result is old news
		hideVictory(true)
		hideDeath()
	elseif phase == "Ending" then
		task.delay(0.7, function()
			if GameState:GetAttribute("Phase") == "Ending" and victoryRound ~= GameState:GetAttribute("RoundId") then
				local winner = GameState:GetAttribute("WinnerName")
				local w = if type(winner) == "string" and winner ~= "" then winner else nil
				showVictory(w, if w then "is the last one standing" else nil, w, true)
			end
		end)
	elseif phase == "Lobby" or phase == "Intermission" then
		if victoryVisible then
			local token = victoryToken
			task.delay(if R.vSummary.Visible then 7 else 3, function()
				if token == victoryToken then
					hideVictory(false)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------
function NotificationController.Init(registry)
	Controllers = registry
	-- connect early so nothing sent during boot is missed; replayed once the Overlay is ready
	Net.event("Announce").OnClientEvent:Connect(onAnnounce)
	Net.event("YouDied").OnClientEvent:Connect(function(data)
		if started then
			showDeath(data)
		end
	end)
	Net.event("RoundSummary").OnClientEvent:Connect(onSummary)
end

function NotificationController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local overlay = playerGui:WaitForChild("Overlay") :: ScreenGui
	gui = overlay
	Theme.bindRoot(overlay)
	local root = overlay:WaitForChild("Root") :: any
	R.dim = overlay:WaitForChild("Dim")
	R.countdown = root:WaitForChild("Countdown")
	R.cdNumber = R.countdown:WaitForChild("Number")
	R.cdPop = R.cdNumber:WaitForChild("Pop")
	R.cdCaption = R.countdown:WaitForChild("Caption")
	R.cdSub = R.countdown:FindFirstChild("Sub") -- the cache line under the caption (UIBuilder)
	R.headline = root:WaitForChild("Headline")
	R.hEyebrow = R.headline:WaitForChild("Eyebrow")
	R.hTitle = R.headline:WaitForChild("Title")
	R.hRule = R.headline:WaitForChild("Rule")
	R.hSub = R.headline:WaitForChild("Sub")
	R.toasts = root:WaitForChild("Toasts")
	R.cards = root:FindFirstChild("Cards") -- QW5 cards at the left (UIBuilder); without it they stack with the toasts
	R.roll = root:WaitForChild("RollCall")
	R.rollConstraint = R.roll:FindFirstChildOfClass("UISizeConstraint") or Instance.new("UISizeConstraint", R.roll)
	R.rollTitle = R.roll:WaitForChild("Title")
	R.rollRule = R.roll:WaitForChild("Rule")
	R.rollSub = R.roll:WaitForChild("Sub")
	R.rollNames = R.roll:WaitForChild("Names")
	R.rollLine = R.roll:WaitForChild("Line")
	R.death = root:WaitForChild("Death")
	R.dPanel = R.death:WaitForChild("Panel")
	R.dEyebrow = R.dPanel:FindFirstChild("Eyebrow")
	R.dTitle = R.dPanel:WaitForChild("Title")
	R.dCause = R.dPanel:WaitForChild("Cause")
	R.dNote = R.dPanel:WaitForChild("Note")
	R.dProgress = R.dPanel:FindFirstChild("Progress")
	R.dTip = R.dPanel:FindFirstChild("Tip")
	R.dSpectate = R.dPanel:WaitForChild("Buttons"):WaitForChild("Spectate")
	R.dContinue = R.dPanel.Buttons:WaitForChild("Continue")
	R.victory = root:WaitForChild("Victory")
	R.vPanel = R.victory:WaitForChild("Panel")
	R.vEyebrow = R.vPanel:WaitForChild("Eyebrow")
	R.vTitle = R.vPanel:WaitForChild("Title")
	R.vSub = R.vPanel:WaitForChild("Sub")
	R.vSummary = R.vPanel:WaitForChild("Summary")
	R.vRows = R.vSummary:WaitForChild("Rows")
	R.vFooter = R.vSummary:WaitForChild("Footer")
	local templates = root:WaitForChild("Templates")
	R.toastTemplate = templates:WaitForChild("Toast")
	R.summaryTemplate = templates:WaitForChild("SummaryRow")
	R.rollTemplate = templates:WaitForChild("RollName")
	R.cardTemplate = templates:FindFirstChild("Card")

	local function hoverable(button: GuiButton, normal: number, hover: number)
		local function set(on: boolean)
			Theme.tween(button, Theme.Tween.Fast, { BackgroundTransparency = if on then hover else normal })
		end
		button.MouseEnter:Connect(function()
			set(true)
			if not Input.isTouch() then
				Sfx.play("UIHover")
			end
		end)
		button.MouseLeave:Connect(function()
			set(false)
		end)
		button.SelectionGained:Connect(function()
			set(true)
		end)
		button.SelectionLost:Connect(function()
			set(false)
		end)
	end
	hoverable(R.dSpectate, 0.05, 0)
	hoverable(R.dContinue, 0.25, 0.08)
	R.dSpectate.Activated:Connect(function()
		Sfx.play("UIClick")
		local spectate = Controllers and Controllers.SpectateController
		local killer = killerOf(lastDeath) -- QW4: watch the one who did it
		hideDeath()
		if spectate and spectate.start then
			spectate.start(killer)
		end
	end)
	R.dContinue.Activated:Connect(function()
		Sfx.play("UIClick")
		hideDeath()
	end)

	GameState:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	ClientState.lifeChanged:Connect(function()
		local phase = GameState:GetAttribute("Phase")
		if ClientState.inArena and (phase == "Countdown" or phase == "Active") then
			participatedRound = GameState:GetAttribute("RoundId")
		end
	end)
	player.CharacterAdded:Connect(function()
		-- back in the lobby: lift the death grade even if the screen is still up
		setGrade(false)
	end)
	if ClientState.inArena then
		participatedRound = GameState:GetAttribute("RoundId")
	end

	overlay.Enabled = true
	started = true
	for _, payload in ipairs(pending) do
		onAnnounce(payload)
	end
	table.clear(pending)
	RunService.RenderStepped:Connect(updateCountdown)
	-- QW5 cards: the needs that trigger them, and a slow pump that holds them through Roll Calls and full screens
	player:GetAttributeChangedSignal("Thirst"):Connect(checkNeeds)
	player:GetAttributeChangedSignal("Hunger"):Connect(checkNeeds)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(pumpCards)
			if not ok then
				warn("[NotificationController] card: " .. tostring(err))
			end
		end
	end)
	-- the countdown caption switches from the goal to the choice when the plate locks
	task.spawn(function()
		while true do
			task.wait(0.2)
			if countdown.active and R.cdCaption and not countdown.flashing then
				setCaption(countdown.last)
			end
		end
	end)
	-- a Roll Call show already running when this player arrived, and every one from here on
	GameState:GetAttributeChangedSignal("RollCall"):Connect(resumeRollCall)
	resumeRollCall()
end

return NotificationController
