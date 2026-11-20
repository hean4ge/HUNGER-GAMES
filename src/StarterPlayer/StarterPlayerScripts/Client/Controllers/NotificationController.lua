--[[
	NotificationController - announcements and the defeat strip (StarterGui.Overlay, built by UIBuilder).
	Owned by the UI system. Style A "Quiet" (docs/design/ui/StyleA_Quiet): no boxes and no pop-ups; text on the picture
	with its dark stroke (faded with QuietUI.fadeText so the outline goes with the text).
	  * Announce remote: Banner and Warning (one headline at a time, queued), Toast (stacked lines),
	    Countdown (big numbers from GameState.PhaseEndsAt, a BEGIN flash on "GO"), RollCall (a small list beside the sky show; owned by the day/night system),
	    Victory (see below). Unknown styles fall back to a toast.
	  * YouDied: the defeat strip along the bottom (Overlay.Root.Strip; fallen.html): "Defeated by Kestrel" (or the
	    cause in plain words) | "You placed 9th of 24" ... "Back to lobby [Backspace]", a muted grade, and one line above
	    it with a tip for the cause and weapon class (QW4: a more specific one the second time the same thing defeats
	    you; the border's first tip follows the border as it was). The middle of the strip is the Spectate screen's card:
	    a few seconds after the strip appears (AUTO_SPECTATE) spectating starts on your killer (payload killerUserId,
	    else the killer's name) when there is anyone to watch. The strip stays while you spectate; "Back to lobby"
	    (Backspace, B, or the button) stops spectating and takes the strip away. Without anyone to watch it goes after
	    STRIP_DWELL s. There is no full-screen card and no dim any more.
	    Whether YOU won is decided by UserId (payload winnerUserId), never by the display name alone (iWon).
	    When your death ends the round (a lone practice contender, the runner-up), the strip stays DEATH_DWELL s with
	    the result on the line above it, and the result's notice follows. A practice death has no placing; a death
	    before the horn (payload phase "Countdown") says you left your plate, with no tip.
	  * QW5: one-time cards for new players (Guidance, through HUDController.guidanceOn): THIRSTY below 60 thirst (it
	    also shows the water marker), HUNGRY below 60 hunger. Cards never show during a Roll Call; they wait for it.
	    They sit at the left (Overlay Cards), clear of the item toast and the held item; toasts sit above the item toast.
	  * QW6: the countdown caption says the goal while the plate rises ("LAST ONE STANDING WINS"; alone in a practice
	    round, "PRACTICE ROUND · NO RIVALS, JUST TRAINING DUMMIES") and the choice once it locks ("RUSH THE SPIRE FOR WEAPONS · OR RUN FOR THE TREES";
	    both names are the arena's, from Shared.Lore: "RUSH THE HORN FOR WEAPONS · OR RUN FOR THE HILLS" on Map 1), with a
	    line about the runner's caches for new players; trying to step off the plate brings back "STAY ON YOUR PLATE".
	  * Victory: Phase Ending + WinnerName (or the Victory announce). The owner: the result "shouldnt pop up after the
	    game it can appear on one of the physical boards". The winner gets one quiet line for a few seconds ("You won",
	    and "Outlasted 23 · 5 defeats · 9:41" under it), everyone else a one-line notice ("Kestrel is the last one
	    standing" / "The full result is on the board in the lobby"). The full result is on the lobby's results board
	    (ResultsBoardService / ResultsBoardController); the RoundSummary table is no longer drawn here.
	Public API (Controllers.NotificationController):
	  announce(payload)                     same shape as the Announce remote
	  toast(text: string, sub: string?, duration: number?)
	  banner(text: string, sub: string?, duration: number?)
	  warning(text: string, sub: string?, duration: number?)
	  card(title: string, text: string | () -> string, opts?)   a card with the toasts; opts: { color: Color3?,
	                                        duration: number?, when: (() -> boolean)?, onShow: (() -> ())? }
	  hideDeathScreen()                     ends the "just defeated" moment; the strip stays while you spectate
	  isStripUp() -> boolean                the defeat strip is on screen (SpectateController hides its own Exit then)
	  isCardUp() -> boolean                the defeat moment (the strip, before spectating) or the winner's line is
	                                        up (the lobby and the HUD wait for it)
	  isBannerUp() -> (boolean, boolean)    a headline is showing, the Roll Call list is showing (the lobby's status pill
	                                        and HOW TO PLAY step aside for them)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lore = require(Shared:WaitForChild("Lore"))
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Input = require(Shared:WaitForChild("Input"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local DayCycle = require(Shared:WaitForChild("DayCycle"))
local ThreatLineModule = Shared:FindFirstChild("ThreatLine")
local ThreatLine = if ThreatLineModule and ThreatLineModule:IsA("ModuleScript") then require(ThreatLineModule) :: any else nil

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
local deathVisible = false
local deathToken = 0
local deathGrade: ColorCorrectionEffect? = nil
local victoryVisible = false
local victoryToken = 0
local victoryRound: any = nil
local participatedRound: any = nil
local stripUp = false -- the defeat strip is on screen (deathVisible, or spectating after a defeat)
local stripToken = 0
local stripLeft = false -- the player pressed Back to lobby during this defeat: no auto-spectate
local AUTO_SPECTATE = 2.5 -- seconds of the strip alone before spectating starts on its own
local STRIP_DWELL = 12 -- seconds the strip stays when there is nobody to watch
local WIN_LINE = 5 -- seconds the winner's quiet line stays
local rollToken = 0
local lastDeath: { [string]: any }? = nil
local deathCounts: { [string]: number } = {} -- this session's deaths per tip class
local cardQueue: { any } = {}
local cardsShown: { [string]: boolean } = {}
local pendingVictory: { [string]: any }? = nil -- QW4: your death ended the round; its result waits behind the death card
local DEATH_DWELL = 8 -- seconds a round-ending defeat strip (and its tip) stays before the round's result notice
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

-- Whether this client is the round's winner. Display names are not unique, so the name alone never decides it (audit
-- F4: a fallen contender with the winner's display name got the gold VICTORY screen). The server's winnerUserId when
-- the payload carries one. Without it: the name, AND this player is still standing (Alive; anyone who fell is not,
-- from the moment they fell) in first place (Placement 1, set by RoundService before it announces the result; a
-- survivor ranked lower by a tiebreak holds 2 or more; 0 = not arrived yet). Placement alone is not enough: a lone
-- practice contender who falls holds place 1 too.
local function iWon(winnerName: string?, winnerUserId: any): boolean
	local id = tonumber(winnerUserId)
	if id and id ~= 0 then
		return id == player.UserId
	end
	if not isMe(winnerName) or player:GetAttribute("Alive") ~= true then
		return false
	end
	return math.floor(tonumber(player:GetAttribute("Placement")) or 0) <= 1
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

-- (Quiet: nothing dims the whole picture any more; Overlay.Dim stays clear)

--------------------------------------------------------------------------------------------------------------------
-- Headlines (Banner / Warning)
--------------------------------------------------------------------------------------------------------------------
local nextHeadline: () -> ()
-- (hunt2_1) a menu panel is see-through by design: a headline is held hidden while a menu is open, not drawn through it
local headlineHeldForMenu = false

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
	-- a quiet item (the round's result notice) is one line in sentence case, smaller, with no rule
	local quiet = item.quiet == true
	R.hTitle.Text = if quiet then item.text else string.upper(item.text)
	R.hTitle.TextSize = if quiet then (if compact then 24 else 30) elseif compact then 28 else 40
	R.hTitle.Size = UDim2.new(1, 0, 0, if quiet then (if compact then 30 else 38) elseif compact then 34 else 48)
	R.hSub.Visible = type(item.sub) == "string" and item.sub ~= ""
	R.hSub.Text = if type(item.sub) == "string" then Theme.escape(item.sub) else ""
	R.hRule.Visible = not compact and not quiet
	R.hRule.BackgroundColor3 = item.ruleColor or C.Accent
	R.hRule.Size = UDim2.fromOffset(0, 2)
	-- (ui-motion) fade and rise QuietUI.Motion.ToastRise px; with Reduce Motion on it only fades
	local still = QuietUI.reducedMotion()
	local rise = if still then 0 else QuietUI.Motion.ToastRise
	h.Visible = not ClientState.menuOpen
	headlineHeldForMenu = ClientState.menuOpen == true
	h.GroupTransparency = 1
	h.Position = UDim2.new(0.5, 0, y, rise)
	TweenService:Create(h, Theme.Tween.Slow, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, y, 0) }):Play()
	if still then
		R.hRule.Size = UDim2.fromOffset(56, 2)
	else
		TweenService:Create(R.hRule, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(56, 2) }):Play()
	end
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
		local t = TweenService:Create(h, QuietUI.Ease.ToastOut, { GroupTransparency = 1,
			Position = UDim2.new(0.5, 0, y, if QuietUI.reducedMotion() then 0 else -QuietUI.Motion.ToastRise / 2) })
		t:Play()
		t.Completed:Wait()
		if headlineCurrent and headlineCurrent.token == token then
			headlineCurrent = nil
			h.Visible = false
			nextHeadline()
		end
	end)
end

nextHeadline = function()
	-- (the defeat strip sits along the bottom, so headlines no longer wait for it as they waited for the old card)
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
	if R.headline and R.headline.Visible then
		-- (ui-motion) a quick fade, not a cut; a new headline meanwhile keeps it
		local h = R.headline
		local t = TweenService:Create(h, QuietUI.Ease.Out, { GroupTransparency = 1 })
		t:Play()
		t.Completed:Once(function()
			if headlineCurrent == nil and h.GroupTransparency > 0.99 then
				h.Visible = false
			end
		end)
	end
end

local function pushHeadline(item: { [string]: any })
	if type(item.text) ~= "string" or item.text == "" then
		return
	end
	if victoryVisible then
		return -- the winner's line owns the stage for its few seconds
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
	local info = if fast then Theme.Tween.Fast else QuietUI.Ease.ToastOut
	local f = entry.frame
	-- no box: the dot and the words (with their dark strokes) fade; then the line goes
	QuietUI.tween(entry.mark, info, { BackgroundTransparency = 1 })
	QuietUI.fadeText(entry.sub, false, info)
	local t = QuietUI.fadeText(entry.text, false, info)
	if t then
		t.Completed:Once(function()
			-- (ui-motion) fold the empty line, so the toasts left close up instead of jumping
			if f.Parent and f.AutomaticSize ~= Enum.AutomaticSize.Y and f.AutomaticSize ~= Enum.AutomaticSize.XY then
				local fold = TweenService:Create(f, QuietUI.Ease.Out, { Size = UDim2.new(f.Size.X.Scale, f.Size.X.Offset, 0, 0) })
				fold:Play()
				fold.Completed:Once(function()
					f:Destroy()
				end)
			else
				f:Destroy()
			end
		end)
	else
		f:Destroy() -- reduced motion: set at once
	end
end

-- (ui-motion) a new toast or card opens its line from nothing (Motion.Toast, Quint Out): the others move up smoothly
-- and its words rise into place as the line grows from the bottom. Reduce Motion: it is simply there.
local function growIn(frame: GuiObject)
	if QuietUI.reducedMotion() or frame.AutomaticSize == Enum.AutomaticSize.Y or frame.AutomaticSize == Enum.AutomaticSize.XY then
		return
	end
	local full = frame.Size
	if full.Y.Scale ~= 0 or full.Y.Offset <= 0 then
		return
	end
	frame.Size = UDim2.new(full.X.Scale, full.X.Offset, 0, 0)
	TweenService:Create(frame, QuietUI.Ease.Toast, { Size = full }):Play()
end

-- a toast's or card's words start clear, with their strokes, and fade in
local function fadeInLabels(labels: { any }, mark: GuiObject?)
	for _, label in ipairs(labels) do
		QuietUI.textTransparency(label, 1)
	end
	if mark then
		mark.BackgroundTransparency = 1
	end
	for _, label in ipairs(labels) do
		QuietUI.fadeText(label, true, QuietUI.Ease.Toast)
	end
	if mark then
		QuietUI.tween(mark, QuietUI.Ease.Toast, { BackgroundTransparency = 0 })
	end
end

-- Touch screens: one toast at a time, centred over the hotbar (which sits left of the touch buttons), above the
-- item-name line and below the crosshair; elsewhere up to three, centred above the hotbar.
local function compactToasts(): boolean
	return UserInputService.TouchEnabled
end

-- The Loadout screen is open (its rows take the right half and the bottom of the screen; the avatar the left).
local function loadoutOpen(): boolean
	local lc = Controllers and Controllers.LoadoutController
	if lc and type(lc.isOpen) == "function" then
		local ok, open = pcall(lc.isOpen)
		return ok and open == true
	end
	return false
end

local function layoutToasts()
	local container = R.toasts
	if not container then
		return
	end
	-- while the Loadout is open the toasts move up to the top of the avatar's side, clear of the rows ("A contender
	-- has arrived" lay over GENERAL SKILL and TRAIL, wave10); a phone's left side is too narrow: they wait, hidden
	if loadoutOpen() then
		container.Visible = not compactToasts()
		container.Position = UDim2.new(0.25, 0, 0, 190)
		return
	end
	container.Visible = true
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
	textLabel.Text = Theme.escape(text)
	subLabel.Text = if type(sub) == "string" then sub else ""
	subLabel.Visible = subLabel.Text ~= "" and not compact
	local textLimit = textLabel:FindFirstChildOfClass("UISizeConstraint")
	if textLimit and compact then
		textLimit.MaxSize = Vector2.new(290, 36)
	end
	frame.BackgroundTransparency = 1 -- Quiet: no box behind a toast
	frame.Visible = true
	growIn(frame)
	frame.Parent = R.toasts
	fadeInLabels({ textLabel, subLabel }, mark)
	local entry = { frame = frame, text = textLabel, sub = subLabel, mark = mark }
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
	frame.BackgroundTransparency = 1 -- Quiet: no box behind a card
	layoutToasts()
	frame.Visible = true
	-- cards have their own place at the left (Overlay Cards), so they never cover the item toast or the held item
	growIn(frame)
	frame.Parent = R.cards or R.toasts
	fadeInLabels({ title, textLabel }, mark)
	local entry = { frame = frame, text = title, sub = textLabel, mark = mark, card = true }
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
			-- alone in the arena there is nobody to outlast: say what the round is (round-flow QA pt1)
			local dummies = (tonumber(Config.Combat.PracticeDummies) or 0) > 0
				and (Config.IsStudio or Config.Round.SoloPractice ~= false)
			if dummies then
				return if isPhone() then "PRACTICE  ·  JUST TRAINING DUMMIES" else "PRACTICE ROUND  ·  NO RIVALS, JUST TRAINING DUMMIES"
			end
			return if isPhone() then "PRACTICE  ·  NO RIVALS" else "PRACTICE ROUND  ·  NO RIVALS THIS TIME"
		end
		return "LAST ONE STANDING WINS"
	end
	-- the centre and where a runner runs to are the arena's own names (the Spire and the trees; the Horn and the hills)
	local spire = Lore.upper("Spire")
	return if isPhone() then "RUSH " .. spire .. "  ·  OR RUN"
		else "RUSH " .. spire .. " FOR WEAPONS  ·  OR RUN FOR " .. (if type(Lore.Cover) == "string" then Lore.upper("Cover") else "THE TREES")
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
local captionBase: string? = nil
local function setCaption(n: number?)
	local text = captionFor(n)
	local base = goalCaption()
	if R.cdCaption.Text ~= text then
		-- (ui-motion) new words fade through (Motion.Text); only the seconds changing are set at once
		if base ~= captionBase and R.cdCaption.Text ~= "" then
			QuietUI.setText(R.cdCaption, text)
		else
			R.cdCaption.Text = text
		end
	end
	captionBase = base
	R.cdCaption.Visible = text ~= ""
	if R.cdSub then
		local sub = cacheLine()
		if sub and not R.cdSub.Visible then
			R.cdSub.Text = sub
			R.cdSub.Visible = true
			QuietUI.textTransparency(R.cdSub, 1)
			QuietUI.fadeText(R.cdSub, true, QuietUI.Ease.Toast)
		elseif sub and R.cdSub.Text ~= sub then
			QuietUI.setText(R.cdSub, sub)
		end
		if not sub then
			R.cdSub.Visible = false
		end
	end
end

local function showCountdownNumber(n: number)
	R.countdown.Visible = true
	R.cdNumber.Text = tostring(n)
	R.cdNumber.TextColor3 = C.Text
	QuietUI.textTransparency(R.cdNumber, 0.4)
	-- (ui-motion) no pop: the number settles from 1.08 as it fades in (Quint Out); Reduce Motion: no scale
	R.cdPop.Scale = if QuietUI.reducedMotion() then 1 else 1.08
	QuietUI.tween(R.cdPop, QuietUI.Ease.Toast, { Scale = 1 })
	QuietUI.fadeText(R.cdNumber, true, QuietUI.Ease.Toast)
	setCaption(n)
	QuietUI.textTransparency(R.cdCaption, 0)
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
	QuietUI.textTransparency(R.cdNumber, 0)
	R.cdCaption.Text = ""
	R.cdCaption.Visible = false
	if R.cdSub then
		R.cdSub.Visible = false
	end
	R.cdPop.Scale = if QuietUI.reducedMotion() then 1 else 0.96
	QuietUI.tween(R.cdPop, TweenInfo.new(1.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1.03 })
	task.delay(0.8, function()
		-- the word and its dark outline fade together (a stroke left behind would read as a ghost "BEGIN")
		local t = QuietUI.fadeText(R.cdNumber, false, Theme.Tween.FadeOut)
		if t then
			t.Completed:Wait()
		end
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
		-- (held while the launch intro plays: no numbers and no ticks over the shot; the current one shows after it)
		if n >= 1 and n ~= countdown.last and not countdown.flashing and not ClientState.launchShot then
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
	local found: Player? = if id and id ~= 0 then Players:GetPlayerByUserId(id) else nil -- (negative in a Studio test server)
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
			-- the border as it was when you died: on day 1 it hasn't moved (a small round's starts closer in), so "from
			-- the second morning" read wrong after a day-1 death outside it (round-flow QA pt3)
			local full = tonumber(Config.Border.StartRadius) or 640
			local start = tonumber(GameState:GetAttribute("BorderStartRadius")) or full
			local radius = tonumber(GameState:GetAttribute("BorderRadius"))
			local moving = GameState:GetAttribute("BorderShrinking") == true or (radius ~= nil and radius < start - 0.5)
			if not moving and start < full - 0.5 then
				return "With fewer contenders " .. Lore.Border .. " starts closer in, and it hurts from the start. If you stray out, follow the marker on your compass back in."
			elseif not moving then
				return Lore.cap("Border") .. " hurts from the start, even before it moves. If you stray out, follow the marker on your compass back in."
			end
			-- when this round's ring first moved, in words ("the second morning"; "the first evening" for a big ring)
			local when = "the second morning"
			if ThreatLine and type(ThreatLine.dayPart) == "function" and type(ThreatLine.borderMovesAt) == "function" then
				local ok, words = pcall(function()
					return ThreatLine.dayPart(ThreatLine.borderMovesAt())
				end)
				if ok and type(words) == "string" and words ~= "" then
					when = words
				end
			end
			return "From " .. when .. " " .. Lore.Border .. " closes on " .. Lore.Spire .. ". Head in when the timer shows."
		end,
		function()
			return string.format("Outside %s you lose %d health a second, %d once it has closed. Near its edge the compass shows how far it is.",
				Lore.Border, tonumber(Config.Border.DamagePerSecond) or 4, tonumber(Config.Border.LateDamagePerSecond) or 10)
		end,
	},
	Fall = {
		function()
			return string.format("Drops of more than about %d m hurt. Take the slope down, or drop into water.", meters(tonumber(Config.Movement.FallDamage.MinHeight) or 13))
		end,
		function()
			return string.format("A drop of about %d m kills from full health. Find a slope, or land in deep water.", meters(tonumber(Config.Movement.FallDamage.LethalHeight) or 58))
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
			return string.format("A full-draw arrow hits for %d, %d to the head. Move from cover to cover, and never stop in the open.", damage, head)
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
	elseif cause == "Reset" then
		return "Reset" -- no tip: you chose to go
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

-- "1st", "2nd", "9th", "11th", "22nd"
local function ordinal(n: number): string
	local suffix = "th"
	local tens = n % 100
	if tens < 11 or tens > 13 then
		local ones = n % 10
		suffix = if ones == 1 then "st" elseif ones == 2 then "nd" elseif ones == 3 then "rd" else "th"
	end
	return tostring(n) .. suffix
end

-- How long this round has run ("6:12"), for "survived" lines
local function roundTime(): string?
	local startedAt = tonumber(GameState:GetAttribute("RoundStartedAt")) or 0
	if startedAt <= 0 then
		return nil
	end
	return Util.formatTime(math.max(0, workspace:GetServerTimeNow() - startedAt))
end

-- The strip's left words: who or what ended your round, in plain, neutral words (rated Mild: no talk of death).
local function causeLine(data: { [string]: any }, short: boolean): string
	local killer = if type(data.killer) == "string" and data.killer ~= "" then "<b>" .. Theme.escape(data.killer) .. "</b>" else nil
	local weapon = if type(data.weaponName) == "string" and data.weaponName ~= "" then data.weaponName else nil
	if not weapon and type(data.weapon) == "string" then
		local def = ItemDefs.get(data.weapon)
		weapon = if def then def.name else nil
	end
	local cause = data.cause
	if cause == "Combat" then
		if killer and weapon and not short then
			return string.format("Defeated by %s  <font transparency=\"0.35\">·  %s</font>", killer, Theme.escape(weapon))
		end
		return if killer then "Defeated by " .. killer else "Defeated in a fight"
	elseif cause == "Fall" then
		return if killer and not short then "A long fall  ·  chased by " .. killer else "A long fall"
	elseif cause == "Border" then
		local border = if type(Lore.Border) == "string" then Lore.Border else "the border"
		return if killer and not short then "Caught outside " .. border .. "  ·  after a fight with " .. killer else "Caught outside " .. border
	elseif cause == "Starvation" then
		return "Ran out of food"
	elseif cause == "Dehydration" then
		return "Ran out of water"
	elseif cause == "Reset" then
		return "You reset"
	end
	return if killer then "Defeated by " .. killer else "Out of the round"
end

-- The strip's placing: "You placed 9th of 24" (nil when there is none to give)
local function placeLine(data: { [string]: any }, practice: boolean, beforeHorn: boolean): string?
	if beforeHorn then
		return if practice then "Practice cancelled"
			else "You left your plate before " .. (if type(Lore.StartSignal) == "string" then Lore.StartSignal else "the horn")
	end
	if practice then
		local t = roundTime()
		return if t then "Practice round  ·  " .. t else "Practice round"
	end
	local placement = math.floor(tonumber(data.placement) or 0)
	local total = math.max(placement, math.floor(tonumber(data.total) or 0))
	if placement <= 0 or total <= 1 then
		return nil
	end
	return string.format("You placed <b>%s</b> of %d", ordinal(placement), total)
end

--------------------------------------------------------------------------------------------------------------------
-- The defeat strip (Overlay.Root.Strip): Left > Mark, Cause, Sep, Place; Right > Leave, LeaveKey. The Spectate
-- screen's card sits in its middle. One line above it (StripTip, made here) carries the tip, or the round's result.
--------------------------------------------------------------------------------------------------------------------
local stripInfo: { [string]: any } = {} -- what the current strip says: tip, place (for the phone's line)
local stripBound = false
local leaveStrip: () -> ()

local function spectateController()
	return Controllers and Controllers.SpectateController
end

local function isSpectating(): boolean
	local spectate = spectateController()
	if spectate and spectate.isSpectating then
		local ok, on = pcall(spectate.isSpectating)
		return ok and on == true
	end
	return false
end

-- SpectateController hides its own Exit while the strip's "Back to lobby" is on screen
local function tellSpectate()
	local spectate = spectateController()
	if spectate and spectate.onStripChanged then
		pcall(spectate.onStripChanged, stripUp)
	end
end

local function setStripBinding(on: boolean)
	if on == stripBound then
		return
	end
	stripBound = on
	if on then
		-- Backspace / B leaves, as the spectate screen's own exit does (that one has the higher priority while you
		-- spectate, and SpectateController.stop then takes the strip away)
		Input.bind("StripLeave", function(state)
			local sc = settingsController()
			local menu = sc and sc.isOpen and sc.isOpen()
			if state == Enum.UserInputState.Begin and not menu then
				leaveStrip()
			end
			return Enum.ContextActionResult.Sink
		end, { keys = { Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB }, priority = 2400 })
	else
		Input.unbind("StripLeave")
	end
end

local function stripKeyText(): string?
	if Input.isTouch() then
		return nil -- a finger presses the words
	elseif Input.isGamepad() then
		return "B"
	end
	return "Backspace"
end

-- the key square and the line above the strip, kept current while the strip is up
local function refreshStrip()
	if not R.strip then
		return
	end
	local keyText = stripKeyText()
	if R.stripKey then
		R.stripKey.Visible = keyText ~= nil
		if keyText then
			QuietUI.setKey(R.stripKey, keyText)
		end
	end
	if R.stripTip then
		local lines = {}
		if pendingVictory and type(pendingVictory.note) == "string" and pendingVictory.note ~= "" then
			table.insert(lines, pendingVictory.note) -- the round is over: its result, until the strip goes
		end
		if stripInfo.phonePlace then
			table.insert(lines, stripInfo.phonePlace)
		end
		if stripInfo.tip and not pendingVictory then
			table.insert(lines, stripInfo.tip)
		end
		local text = table.concat(lines, "\n")
		if R.stripTip.Text ~= text then
			R.stripTip.Text = text
		end
	end
end

local function hideStrip()
	if not stripUp then
		return
	end
	stripUp = false
	stripToken += 1
	setStripBinding(false)
	local selected = GuiService.SelectedObject
	if selected and R.strip and selected:IsDescendantOf(R.strip) then
		GuiService.SelectedObject = nil
	end
	if R.strip then
		QuietUI.conceal(R.strip, { seconds = Theme.Time.Out, rise = QuietUI.Motion.ToastRise }) -- (ui-motion)
	end
	if R.stripTip then
		QuietUI.fadeText(R.stripTip, false)
	end
	tellSpectate()
end

local function showStrip()
	if not R.strip then
		return
	end
	stripUp = true
	stripToken += 1
	setStripBinding(true)
	refreshStrip()
	QuietUI.reveal(R.strip, { seconds = 0.5, rise = QuietUI.Motion.ToastRise }) -- (ui-motion) fade and rise, no jump
	if R.stripTip then
		R.stripTip.Visible = true
		QuietUI.fadeText(R.stripTip, true, 0.6)
	end
	tellSpectate()
end

-- keepStrip: spectating has started, so the strip stays (its middle is the spectate card)
local function hideDeath(keepStrip: boolean?)
	if deathVisible then
		deathVisible = false
		deathToken += 1
		setModal("Death", false)
		setGrade(false)
		if R.stripTip then
			QuietUI.fadeText(R.stripTip, false) -- the tip was for the moment of defeat
		end
		if pendingVictory then
			task.defer(flushVictory) -- the round's result, now that the strip has had its say
		end
	end
	if not keepStrip then
		hideStrip()
	end
end
NotificationController.hideDeathScreen = function()
	-- SpectateController.start calls this once it is spectating: the strip stays, only the moment ends
	hideDeath(isSpectating())
end

leaveStrip = function()
	stripLeft = true
	Sfx.play("UIClick")
	if isSpectating() then
		local spectate = spectateController()
		pcall(spectate.stop) -- spectateChanged(nil) takes the strip away too
	end
	hideDeath(false)
end

function NotificationController.isStripUp(): boolean
	return stripUp
end

-- The defeat moment (the strip before spectating) or the winner's line is up: LobbyController keeps the lobby screen
-- back until it goes, and the HUD stays down, so the two never draw text over text (round-flow QA pt2/pt3).
function NotificationController.isCardUp(): boolean
	return deathVisible or victoryVisible
end

-- A headline is showing; the Roll Call list is showing. On phones both use the top band, where the lobby's status
-- pill is, and elsewhere the Roll Call panel sits at the right edge, where HOW TO PLAY is: LobbyController moves
-- them out of the way meanwhile.
function NotificationController.isBannerUp(): (boolean, boolean)
	return headlineCurrent ~= nil, R.roll ~= nil and R.roll.Visible == true
end

local function showDeath(data: any)
	if type(data) ~= "table" or victoryVisible then
		return
	end
	participatedRound = GameState:GetAttribute("RoundId")
	deathToken += 1
	local token = deathToken
	-- a help card still up (THIRSTY on the way to running out of water) gives way to the strip and its tip
	for _, entry in ipairs(table.clone(toasts)) do
		if entry.card then
			removeToast(entry, true)
		end
	end
	local practice = data.practice == true or (data.practice == nil and GameState:GetAttribute("Practice") == true)
	local beforeHorn = data.phase == "Countdown"
	local compact = isPhone()
	lastDeath = data
	stripLeft = false

	-- the strip's words
	local place = placeLine(data, practice, beforeHorn)
	if R.stripCause then
		R.stripCause.Text = causeLine(data, compact)
	end
	if R.stripMark then
		QuietUI.tint(R.stripMark, if practice and not beforeHorn then C.Sun else C.Red)
	end
	-- a phone has no room for the placing on the strip: it goes on the line above it
	local placeOnStrip = place ~= nil and not compact
	if R.stripPlace then
		R.stripPlace.Text = place or ""
		R.stripPlace.Visible = placeOnStrip
	end
	if R.stripSep then
		R.stripSep.Visible = placeOnStrip
	end
	stripInfo = {
		phonePlace = if compact then place else nil,
		tip = nil,
	}
	local tip = if beforeHorn then nil else tipFor(data)
	if tip then
		stripInfo.tip = string.format("<font color=\"%s\">TIP</font>   %s", Theme.hex(C.TextDim), tip)
	end
	if R.stripTip then
		R.stripTip.Size = UDim2.new(if compact then 1 else 0.5, 0, 0, 0)
	end

	deathVisible = true
	showStrip()
	-- On a window narrower than a full-HD screen (a 1,214-wide Studio test window, 18 Nov) the full left end ("Defeated
	-- by <name> · <weapon>  |  You placed 3rd of 3") ran under the Spectate card's Prev arrow and its key in the
	-- strip's middle. Once it is laid out: if its words reach the card's place, the strip takes the phone's short form
	-- (no weapon; the placing on the line above it).
	if not compact and placeOnStrip then
		task.delay(0.1, function()
			if token ~= deathToken or not deathVisible or not (R.stripPlace and R.stripPlace.Visible) then
				return
			end
			local screen = R.strip:FindFirstAncestorWhichIsA("LayerCollector")
			local width = if screen and screen:IsA("ScreenGui") then screen.AbsoluteSize.X else 0
			local half = if UserInputService.TouchEnabled or Theme.isSmallScreen() then 180 else 230 -- (SpectateController's card)
			local label = R.stripPlace :: TextLabel
			local reach = label.AbsolutePosition.X + math.min(label.TextBounds.X, label.AbsoluteSize.X)
			if width > 0 and reach > width / 2 - half - 16 then
				if R.stripCause then
					R.stripCause.Text = causeLine(data, true)
				end
				label.Visible = false
				if R.stripSep then
					R.stripSep.Visible = false
				end
				stripInfo.phonePlace = place
				refreshStrip()
			end
		end)
	end
	setModal("Death", true) -- the mouse is free for "Back to lobby"
	setGrade(true)
	if Input.isGamepad() and R.stripLeave then
		GuiService.SelectedObject = R.stripLeave
	end
	task.spawn(function()
		local t0 = os.clock()
		while token == deathToken and deathVisible do
			local age = os.clock() - t0
			-- QW4: when this fall ended the round, the strip (and the result above it) stays DEATH_DWELL s
			if pendingVictory ~= nil then
				if age >= DEATH_DWELL then
					hideDeath(false)
					break
				end
			elseif not stripLeft and age >= AUTO_SPECTATE and canSpectate() then
				-- watch the one who did it (or whoever remains): the strip stays, its middle becomes the card
				local spectate = spectateController()
				if spectate and spectate.start then
					local ok, started = pcall(spectate.start, killerOf(lastDeath))
					if ok and started then
						break -- start() called hideDeathScreen: the moment is over, the strip stays
					end
				end
			end
			if age > STRIP_DWELL and not isSpectating() then
				hideDeath(false)
				break
			end
			refreshStrip()
			task.wait(0.25)
		end
	end)
end

--------------------------------------------------------------------------------------------------------------------
-- The round's result: a quiet line for the winner, a one-line notice for everyone else. The full result is on the
-- results board in the lobby (ResultsBoardController).
--------------------------------------------------------------------------------------------------------------------
local function hideVictory(immediate: boolean?)
	if not victoryVisible then
		return
	end
	victoryVisible = false
	victoryToken += 1
	local token = victoryToken
	if immediate then
		R.victory.Visible = false
		return
	end
	local t = QuietUI.tween(R.vPanel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { GroupTransparency = 1 })
	if not t then
		R.victory.Visible = false
		return
	end
	t.Completed:Once(function()
		if token == victoryToken and not victoryVisible then
			R.victory.Visible = false
		end
	end)
end

-- "Kestrel is the last one standing" / "The full result is on the board in the lobby"
local function noticeFor(title: string, subText: string, winnerName: string?, practice: boolean): (string, string?)
	local line = if winnerName and subText ~= "" then winnerName .. " " .. subText
		elseif winnerName then winnerName .. " won"
		else title
	-- practice rounds are not posted (ResultsBoardService keeps the last real round)
	local sub = if practice then (if winnerName then nil elseif subText ~= "" then subText else nil)
		else "The full result is on the board in the lobby"
	return line, sub
end

-- winnerUserId: the winner's UserId when the server sent it. wonBefore: the answer worked out when the result first
-- arrived (a result that waited behind the strip is shown later, when Placement and Alive may have been reset).
-- practiceBefore: the same for GameState.Practice, which is already false by the time a waiting result is shown (so a
-- practice round's notice said "The full result is on the board in the lobby", and practice rounds are not posted).
local function showVictory(text: string?, sub: string?, winner: any, fallback: boolean?, winnerUserId: any, wonBefore: boolean?,
	practiceBefore: boolean?)
	local roundId = GameState:GetAttribute("RoundId")
	local winnerName = if type(winner) == "string" and winner ~= "" then winner else nil
	local participated = participatedRound ~= nil and participatedRound == roundId
	local won = if wonBefore ~= nil then wonBefore else participated and iWon(winnerName, winnerUserId)
	local practice = if practiceBefore ~= nil then practiceBefore else GameState:GetAttribute("Practice") == true
	local title = if type(text) == "string" and text ~= "" then text elseif winnerName then winnerName else "Round over"
	local subText = if type(sub) == "string" then sub elseif winnerName then "is the last one standing" else ""
	if victoryRound == roundId then
		return -- shown already (the Ending attribute's fallback, then the announcement)
	end
	-- QW4: when your fall ended the round (a lone practice contender, the runner-up), the strip and its tip stay up
	-- first and the line above it gives the result; the notice follows after DEATH_DWELL s or Back to lobby
	if participated and deathVisible then
		if not (fallback and pendingVictory and pendingVictory.roundId == roundId) then
			local note
			if practice then
				note = "Practice over  ·  a new round starts soon"
			elseif winnerName then
				note = "<b>" .. Theme.escape(winnerName) .. "</b> " .. Theme.escape(subText)
			else
				note = Theme.escape(title)
			end
			pendingVictory = { roundId = roundId, text = text, sub = sub, winner = winner, note = note,
				winnerUserId = winnerUserId, won = won, practice = practice }
		end
		refreshStrip()
		return
	end
	pendingVictory = nil
	victoryRound = roundId
	if not won then
		-- everyone else: one quiet line, and where to find the rest
		local line, noticeSub = noticeFor(title, subText, winnerName, practice)
		pushHeadline({ quiet = true, text = line, sub = noticeSub, duration = 5 })
		return
	end

	-- the winner: "You won" and the round's facts, a few seconds, fading. No box, no dim, no table.
	hideDeath(false)
	clearHeadlines()
	victoryVisible = true
	victoryToken += 1
	local token = victoryToken
	local kills = math.floor(tonumber(player:GetAttribute("Kills")) or 0)
	local defeats = string.format("%d %s", kills, if kills == 1 then "defeat" else "defeats")
	local facts = {}
	local startedCount = math.floor(tonumber(GameState:GetAttribute("StartedCount")) or 0)
	if not practice and startedCount > 1 then
		table.insert(facts, string.format("Outlasted %d", startedCount - 1))
	end
	table.insert(facts, defeats)
	local t = roundTime()
	if t then
		table.insert(facts, t)
	end
	R.vEyebrow.Visible = not practice
	R.vEyebrow.Text = "THE LAST ONE STANDING"
	R.vEyebrow.TextColor3 = C.Sun
	R.vTitle.Text = if practice then "Practice survived" else "You won"
	R.vTitle.TextColor3 = C.Text
	R.vTitle.TextSize = if isPhone() then 36 else 48
	R.vTitle.Size = UDim2.new(1, 0, 0, if isPhone() then 44 else 58)
	R.vSub.Text = Theme.escape(table.concat(facts, "  ·  "))
	R.vSub.Position = UDim2.fromOffset(0, if isPhone() then 64 else 80)
	if R.vSummary then
		R.vSummary.Visible = false
	end
	local topY = if isPhone() then 0.04 else 0.2
	R.victory.Visible = true
	R.vPanel.GroupTransparency = 1
	R.vPanel.Position = UDim2.new(0.5, 0, topY, 12)
	QuietUI.tween(R.vPanel, TweenInfo.new(1.0, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = UDim2.fromScale(0.5, topY),
	})
	Sfx.play("Victory")
	task.delay(WIN_LINE, function()
		if token == victoryToken then
			hideVictory(false)
		end
	end)
end

-- The result that waited for a round-ending defeat strip (QW4).
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
	showVictory(p.text, p.sub, p.winner, nil, p.winnerUserId, p.won, p.practice)
end

--------------------------------------------------------------------------------------------------------------------
-- Roll Call (owned by the day/night system): a small, accessible list beside the 3D "The Fallen" show in the sky
-- (FallenRecapController). Names appear as their busts form, on the show's own timeline (Shared.DayCycle).
--------------------------------------------------------------------------------------------------------------------
local lastRollId: any = nil

-- full words (hunt2_2: "IN THE SKY TO THE W" read as a cut-off line); the longest, "LOOK UP · TO THE NORTHWEST", fits the 250 px panel
local BEARINGS = { "NORTH", "NORTHEAST", "EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST" }

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
			QuietUI.textTransparency(l, 1) -- the name and its stroke start clear
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
				elseif bearing then "LOOK UP · TO THE " .. bearing
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
				QuietUI.fadeText(labels[i], true, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
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
		showVictory(text, sub, payload.winner, nil, payload.winnerUserId)
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
	R.cdPop.Scale = if QuietUI.reducedMotion() then 1 else 1.04
	QuietUI.tween(R.cdPop, QuietUI.Ease.Toast, { Scale = 1 })
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
		hideDeath(false)
	elseif phase == "Ending" then
		task.delay(0.7, function()
			if GameState:GetAttribute("Phase") == "Ending" and victoryRound ~= GameState:GetAttribute("RoundId") then
				local winner = GameState:GetAttribute("WinnerName")
				local w = if type(winner) == "string" and winner ~= "" then winner else nil
				showVictory(w, if w then "is the last one standing" else nil, w, true, GameState:GetAttribute("WinnerUserId"))
			end
		end)
	elseif phase == "Lobby" or phase == "Intermission" then
		if victoryVisible then
			-- the winner's line fades on its own (WIN_LINE); back in the lobby it goes soon in any case
			local token = victoryToken
			task.delay(1.5, function()
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
	-- (RoundSummary is no longer drawn here: the full result is on the lobby's results board)
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
	-- the defeat strip (UIBuilder: Strip > Line, Left > Mark, Cause, Sep, Place; Right > Leave, LeaveKey)
	R.strip = root:WaitForChild("Strip", 10)
	if R.strip then
		local left = R.strip:WaitForChild("Left")
		local right = R.strip:WaitForChild("Right")
		R.stripMark = left:WaitForChild("Mark")
		R.stripCause = left:WaitForChild("Cause")
		R.stripSep = left:WaitForChild("Sep")
		R.stripPlace = left:WaitForChild("Place")
		R.stripLeave = right:WaitForChild("Leave")
		R.stripKey = right:WaitForChild("LeaveKey")
		-- the line above the strip (the tip, or the round's result): one wrapped line of plain text, made here
		local tip = QuietUI.label({
			Name = "StripTip",
			Font = "Medium",
			TextSize = 15,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -((tonumber(Theme.Strip and Theme.Strip.Height) or 62) + 12)),
			Size = UDim2.new(0.5, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			RichText = true,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Visible = false,
			Parent = root,
		})
		QuietUI.textTransparency(tip, 1)
		R.stripTip = tip
		QuietUI.bindButton(R.stripLeave, {
			onHover = function()
				if not Input.isTouch() then
					Sfx.play("UIHover")
				end
			end,
		})
		R.stripLeave.Activated:Connect(function()
			leaveStrip()
		end)
	else
		warn("[NotificationController] Overlay.Root.Strip is missing (an older UIBuilder build): no defeat strip")
	end
	-- the old full-screen death card stays hidden (UIBuilder still builds it)
	local oldDeath = root:FindFirstChild("Death")
	if oldDeath then
		oldDeath.Visible = false
	end
	R.victory = root:WaitForChild("Victory")
	R.vPanel = R.victory:WaitForChild("Panel")
	R.vEyebrow = R.vPanel:WaitForChild("Eyebrow")
	R.vTitle = R.vPanel:WaitForChild("Title")
	R.vSub = R.vPanel:WaitForChild("Sub")
	R.vSummary = R.vPanel:FindFirstChild("Summary") -- (no longer used: the board has the table)
	if R.vSummary then
		R.vSummary.Visible = false
	end
	local templates = root:WaitForChild("Templates")
	R.toastTemplate = templates:WaitForChild("Toast")
	R.rollTemplate = templates:WaitForChild("RollName")
	R.cardTemplate = templates:FindFirstChild("Card")

	-- spectating stopped (Back to lobby, the round over, nobody left): the strip goes with it
	ClientState.spectateChanged:Connect(function(target)
		if target == nil and stripUp and not deathVisible then
			hideStrip()
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		if stripUp then
			refreshStrip()
		end
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
	-- (hunt2_1) headlines step out while a menu is open (Daily, Season, Cases, Prepare...) and come back after
	RunService.Heartbeat:Connect(function()
		local h = R.headline
		if not h then
			return
		end
		if ClientState.menuOpen then
			if h.Visible then
				h.Visible = false
				headlineHeldForMenu = true
			end
		elseif headlineHeldForMenu then
			headlineHeldForMenu = false
			h.Visible = headlineCurrent ~= nil
		end
	end)
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
	-- the Loadout opening or closing moves the toasts (layoutToasts) and hides the cards
	task.spawn(function()
		local wasOpen = false
		while true do
			task.wait(0.1)
			local open = loadoutOpen()
			if open ~= wasOpen then
				wasOpen = open
				layoutToasts()
				if R.cards then
					R.cards.Visible = not open
				end
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
