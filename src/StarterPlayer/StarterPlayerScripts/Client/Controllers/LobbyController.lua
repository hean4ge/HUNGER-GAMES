--[[
	LobbyController - the lobby screen (StarterGui.Lobby, built by ServerStorage.WorldGen.UIBuilder). Owned by the UI system.
	  * Title (Config.GameTitle) and tagline, a personal record card (Wins, TotalKills, RoundsPlayed attributes).
	  * Status pill from GameState: "WAITING FOR PLAYERS 1 / 2", "NEXT ROUND IN 0:12" (+ progress line),
	    "ROUND STARTING", "ROUND IN PROGRESS · 9 REMAIN · NEXT ROUND IN 6:57 AT MOST" with a SPECTATE button
	    (gamepad: Y), "ROUND OVER". Alone on a server (QW1, GameState.SoloStartAt): "PRACTICE ROUND IN 0:55 · OR WAIT FOR
	    CONTENDERS". The "at most" time (QW4) is what's left of the round plus Ending (with the epilogue), Intermission
	    and Countdown.
	  * How-to-play panel: the goal in one line (from Shared.Lore), the tips, and the controls for the current device
	    (keyboard, gamepad or touch). Open by default only until you've played a round (RoundsPlayed 0, larger screens;
	    QW6), a toggle on phones and afterwards. On a PC or console it is as tall as its rows need and, on a short
	    screen, shrinks as a whole so no row needs scrolling from 720 px of height up (fitHowTo).
	  * Roblox's chat window never sits on the status line: it is kept narrower than the gap beside the line while the
	    lobby shows, and the line waits when even that is not enough (updateChat).
	  * SETTINGS opens the menu (SettingsController).
	Shown while you're not in the arena and not spectating, and once the death card or the round's result card
	(NotificationController.isCardUp) has gone: the two never draw text over text (round-flow QA pt2/pt3).
	While a headline or the Roll Call list shows (NotificationController.isBannerUp), the status pill (phones: they
	share the top band) and HOW TO PLAY (the Roll Call panel's edge) step aside.
	Public API (Controllers.LobbyController): setHowToVisible(visible: boolean)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Input = require(Shared:WaitForChild("Input"))
local Util = require(Shared:WaitForChild("Util"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Lore = require(Shared:WaitForChild("Lore"))
local DayCycle = require(Shared:WaitForChild("DayCycle"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer
local C = Theme.Colors

local LobbyController = {}
local Controllers: any = nil

local gui: ScreenGui? = nil
local R: { [string]: any } = {}
local howToOpen = false
local shownDevice: string? = nil
local spectateAvailable = false
local spectateBound = false
local visible = nil :: boolean?
local howToTouched = false -- the player opened or closed HOW TO PLAY themselves: leave it as they set it
local howToYield, statusYield = false, false -- hidden for a headline or the Roll Call (updateYield)
local chatYield = false -- Roblox's chat window is open over the status line and cannot be made narrower (updateChat)
local soloBar = { at = 0, total = 1 } -- QW1: the practice countdown on show (its SoloStartAt) and its bar's full length

local function settingsController()
	return Controllers and Controllers.SettingsController
end

local function spectateController()
	return Controllers and Controllers.SpectateController
end

local function currentDevice(): string
	local sc = settingsController()
	if sc and sc.currentDevice then
		return sc.currentDevice()
	end
	if Input.isGamepad() then
		return "Gamepad"
	end
	if Input.isTouch() then
		return "Touch"
	end
	return "KeyboardMouse"
end

local DEVICE_TITLE = { KeyboardMouse = "CONTROLS  ·  KEYBOARD & MOUSE", Gamepad = "CONTROLS  ·  GAMEPAD", Touch = "CONTROLS  ·  TOUCH" }

local function refreshControls()
	local device = currentDevice()
	if device == shownDevice then
		return
	end
	shownDevice = device
	R.controlsHeader.Text = DEVICE_TITLE[device] or "CONTROLS"
	local sc = settingsController()
	if sc and sc.fillControls then
		sc.fillControls(R.controls, R.controlRow, device)
	end
end

local function phone(): boolean
	return UserInputService.TouchEnabled and Theme.isSmallScreen()
end

-- QW6: HOW TO PLAY opens by itself only until the first round has been played
local function howToByDefault(): boolean
	return not phone() and math.floor(tonumber(player:GetAttribute("RoundsPlayed")) or 0) <= 0
end

-- QW4: the longest the next horn can be away while a round runs: what's left of it, then Ending (grown to fit the
-- epilogue Roll Call, QW14), Intermission (as long as joins can make it) and Countdown
local function nextRoundIn(remaining: number): number
	local ending = tonumber(Config.Round.EndingTime) or 10
	if GameState:GetAttribute("Practice") ~= true and Config.Round.Epilogue ~= false then
		-- the epilogue is the short show (DayCycle "epilogue" mode: about 19 s however many fell), not a full Roll Call
		local fallen = math.max(1, math.floor(tonumber(GameState:GetAttribute("StartedCount")) or 0) - 1)
		local ok, length = pcall(DayCycle.recapDuration, fallen, "epilogue")
		if ok and type(length) == "number" then
			ending = math.max(ending, length + (tonumber(Config.Round.EpilogueLeadIn) or 2.5) + 1)
		end
	end
	-- with the launch intro the Countdown is as long as its cut (RoundService.launchTiming): the longest one, since
	-- which cut plays is only known at the call (audit F16: the pill promised up to 12 s too little)
	local countdown = tonumber(Config.Round.CountdownTime) or 10
	local launch = (Config :: any).Launch
	if type(launch) == "table" and launch.Intro ~= false then
		countdown = math.max(tonumber(launch.FullCountdown) or 22, tonumber(launch.ShortCountdown) or 12)
	end
	-- the Intermission at its longest: where joins restart it (RoundService.fillRule: a live public server, or Studio
	-- with GameState.FillTest) it can run to FillMaxTime, and the pick can then wait StartHoldTime for a second ready
	-- player ("AT MOST" came up to 75 s short on a filling server)
	local intermission = tonumber(Config.Round.IntermissionTime) or 25
	if Config.Round.FillExtendOnJoin ~= false and GameState:GetAttribute("PrivateServer") ~= true
		and (not Config.IsStudio or GameState:GetAttribute("FillTest") ~= nil) then
		intermission = math.max(intermission, tonumber(Config.Round.FillMaxTime) or 90)
	end
	local hold = math.max(0, tonumber(Config.Round.StartHoldTime) or 0)
	return remaining + ending + intermission + hold + countdown
end

local function setHowTo(on: boolean, animate: boolean?)
	howToOpen = on
	local panel = R.howTo
	if on then
		refreshControls()
		panel.Visible = not howToYield -- (a Roll Call or headline has its place for the moment: updateYield)
		if animate then
			panel.GroupTransparency = 1
			Theme.tween(panel, Theme.Tween.Normal, { GroupTransparency = 0 })
		else
			panel.GroupTransparency = 0
		end
	else
		if animate then
			local t = Theme.tween(panel, Theme.Tween.Fast, { GroupTransparency = 1 })
			t.Completed:Once(function()
				if not howToOpen then
					panel.Visible = false
				end
			end)
		else
			panel.Visible = false
		end
	end
	R.howToButton.Text = if on then "HIDE HELP" else "HOW TO PLAY"
end
LobbyController.setHowToVisible = function(on: boolean)
	if R.howTo then
		setHowTo(on, true)
	end
end

-- HOW TO PLAY on a PC or console: every row on the panel without scrolling, from a 720-high screen up (16:9 and
-- 16:10; it used to stop 70 px short of the top and bottom edges, 560 px at most, and cut the last two rows). The
-- panel is as tall as its text needs. It keeps its old place (70 px from the top) while it fits there, then takes the
-- room down to the bottom edge (nothing else lives at the lobby's bottom right), then up; and when the whole height is
-- still not enough (a 720-high screen: Roblox's top bar takes 58 px of it) the panel shrinks as a whole (UIScale
-- "Fit", never under HOWTO_MIN_SCALE; below that the body scrolls, as before). Sizes are the root's design pixels.
local HOWTO_WIDTH, HOWTO_MARGIN, HOWTO_CHROME, HOWTO_MIN_SCALE = 330, 70, 48, 0.8 -- (chrome: the header and divider)
local HOWTO_GROW_STEP = 0.08
local function fitHowTo()
	local how, root, body = R.howTo, R.root, R.howToBody
	if not how or not root or not body or not howToOpen or UserInputService.TouchEnabled then
		return
	end
	local rootScale = R.rootScale
	local s = if rootScale and rootScale.Scale > 0 then rootScale.Scale else 1
	local safePad = root:FindFirstChild("SafePad")
	local pad = if safePad and safePad:IsA("UIPadding") then safePad.PaddingTop.Offset + safePad.PaddingBottom.Offset else 0
	local inner = root.AbsoluteSize.Y / s - pad
	if inner < 100 then
		return
	end
	local fit = how:FindFirstChild("Fit")
	if not fit or not fit:IsA("UIScale") then
		local made = Instance.new("UIScale")
		made.Name = "Fit"
		made.Parent = how
		fit = made
	end
	local f = if fit.Scale > 0 then fit.Scale else 1
	local total, count = 0, 0
	for _, child in ipairs(body:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			total += child.AbsoluteSize.Y / (s * f)
			count += 1
		end
	end
	if count == 0 or total <= 0 then
		return
	end
	local bodyPad = body:FindFirstChild("Pad")
	local listLayout = body:FindFirstChild("Layout")
	local padY = if bodyPad and bodyPad:IsA("UIPadding") then bodyPad.PaddingTop.Offset + bodyPad.PaddingBottom.Offset else 28
	local gap = if listLayout and listLayout:IsA("UIListLayout") then listLayout.Padding.Offset else 10
	local needed = math.ceil(HOWTO_CHROME + padY + total + gap * (count - 1) + 2)
	local scale = math.clamp(inner / needed, HOWTO_MIN_SCALE, 1)
	-- Text wraps a little differently at each scale, so the size it needs changes with the scale it is given: left
	-- alone, the panel hopped between three sizes ten times a second. It shrinks as soon as it must and grows back
	-- only for a real gain (a shorter list, a taller window).
	if scale > f and scale < f + HOWTO_GROW_STEP then
		scale = f
	end
	-- the panel's own height before its scale: all it needs, or (at the smallest scale) what the screen has
	local height = math.min(needed, math.floor(inner / scale))
	local top = math.max(0, math.floor(math.min(HOWTO_MARGIN, inner - height * scale)))
	local constraint = how:FindFirstChildOfClass("UISizeConstraint")
	if constraint and constraint.MaxSize.Y < height then
		constraint.MaxSize = Vector2.new(constraint.MaxSize.X, height) -- (UIBuilder's 560 cap is for the touch layouts)
	end
	if math.abs(fit.Scale - scale) > 0.004 then
		fit.Scale = scale
	end
	if how.Size.Y.Offset ~= height or how.Position.Y.Offset ~= top or how.Size.Y.Scale ~= 0 then
		how.AnchorPoint = Vector2.new(1, 0)
		how.Position = UDim2.new(1, 0, 0, top)
		how.Size = UDim2.fromOffset(HOWTO_WIDTH, height)
	end
end

-- Roblox's chat window (top left; closed by default, HUDController) and the status line (top centre). At window
-- widths under about 1,400 px an open chat window reached the left end of the line (a late joiner's first view).
-- While the lobby screen shows, the chat window is kept narrower than the gap beside the line (its WidthScale, down
-- to CHAT_MIN_SCALE); if it is open and still over the line at that size (a very narrow window), the line waits
-- until the chat closes (updateYield). Outside the lobby the chat window has its full width back.
local CHAT_MIN_SCALE, CHAT_GAP, STATUS_MAX_WIDTH = 0.6, 12, 450 -- (the longest line with its SPECTATE button, design px)
local function updateChat(lobbyShown: boolean)
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if not window then
		chatYield = false
		return
	end
	if not lobbyShown then
		-- (a closed window reports no size, so this does not wait for one)
		chatYield = false
		pcall(function()
			if window.WidthScale ~= 1 then
				window.WidthScale = 1
			end
		end)
		return
	end
	local ok, x, width, scale = pcall(function()
		return window.AbsolutePosition.X, window.AbsoluteSize.X, window.WidthScale
	end)
	if not ok or type(width) ~= "number" or width <= 0 or scale <= 0 then
		chatYield = false
		return
	end
	local want, hide = 1, false
	local status, pill = R.status, R.pill
	if lobbyShown and status and pill then
		local rootScale = R.rootScale
		local s = if rootScale and rootScale.Scale > 0 then rootScale.Scale else 1
		local centre = status.AbsolutePosition.X + status.AbsoluteSize.X / 2
		local base = width / scale
		want = math.clamp((centre - STATUS_MAX_WIDTH / 2 * s - CHAT_GAP - x) / base, CHAT_MIN_SCALE, 1)
		local okActive, active = pcall(function()
			return StarterGui:GetCore("ChatActive") == true and StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat)
		end)
		hide = okActive and active == true and x + base * want + 4 > pill.AbsolutePosition.X
	end
	if math.abs(want - scale) > 0.01 then
		pcall(function()
			window.WidthScale = want
		end)
	end
	chatYield = hide
end

local function applyLayout()
	local brand, how = R.brand, R.howTo
	if UserInputService.TouchEnabled then
		-- thumbstick and jump live at the bottom: keep the lobby UI up top
		brand.AnchorPoint = Vector2.new(0, 0)
		brand.Position = UDim2.fromOffset(0, 0)
		R.brandLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		R.title.TextSize = 28
		R.title.Size = UDim2.new(1, 0, 0, 34)
		if phone() then
			how.AnchorPoint = Vector2.new(0.5, 0.5)
			how.Position = UDim2.fromScale(0.5, 0.5)
			how.Size = UDim2.new(0, 360, 1, -16)
		else
			how.AnchorPoint = Vector2.new(1, 0)
			how.Position = UDim2.new(1, 0, 0, 64)
			how.Size = UDim2.new(0, 330, 1, -240)
		end
	else
		brand.AnchorPoint = Vector2.new(0, 1)
		brand.Position = UDim2.fromScale(0, 1)
		R.brandLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		R.title.TextSize = 34
		R.title.Size = UDim2.new(1, 0, 0, 40)
		fitHowTo() -- the right edge, as tall as its text needs
	end
end

local function refreshStats()
	R.wins.Text = tostring(math.floor(tonumber(player:GetAttribute("Wins")) or 0))
	R.kills.Text = tostring(math.floor(tonumber(player:GetAttribute("TotalKills")) or 0))
	R.rounds.Text = tostring(math.floor(tonumber(player:GetAttribute("RoundsPlayed")) or 0))
end

local function canSpectate(): boolean
	local sc = spectateController()
	if sc and sc.canSpectate then
		local ok, result = pcall(sc.canSpectate)
		return ok and result == true
	end
	return false
end

local function startSpectating()
	local sc = spectateController()
	if sc and sc.start then
		sc.start()
	end
end

local function setSpectateBinding(on: boolean)
	if on == spectateBound then
		return
	end
	spectateBound = on
	if on then
		Input.bind("LobbySpectate", function(state)
			if state == Enum.UserInputState.Begin and not ClientState.menuOpen then
				startSpectating()
			end
			return Enum.ContextActionResult.Sink
		end, { keys = { Enum.KeyCode.ButtonY }, priority = 2100 })
	else
		Input.unbind("LobbySpectate")
	end
end

local function setStatus(text: string, progress: number?, showSpectate: boolean, pulse: boolean)
	if R.statusText.Text ~= text then
		R.statusText.Text = text
	end
	R.bar.Visible = progress ~= nil
	if progress then
		R.barFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	end
	if showSpectate ~= spectateAvailable then
		spectateAvailable = showSpectate
		R.spectate.Visible = showSpectate
		R.pillPad.PaddingRight = UDim.new(0, if showSpectate then 6 else 18)
	end
	R.dot.BackgroundTransparency = if pulse then 0.5 - 0.5 * math.cos(os.clock() * 3.2) else 0
end

local function updateStatus()
	local phase = GameState:GetAttribute("Phase") or "Lobby"
	local now = workspace:GetServerTimeNow()
	local endsAt = tonumber(GameState:GetAttribute("PhaseEndsAt")) or 0
	local remaining = math.max(0, endsAt - now)
	local soloAt = tonumber(GameState:GetAttribute("SoloStartAt")) or 0
	if (phase == "Lobby" or phase == "Intermission") and soloAt > now then
		-- QW1: alone on the server, one countdown to the practice round covers the wait and the Intermission
		local left = soloAt - now
		if math.abs(soloAt - soloBar.at) > 5 then
			-- a new countdown. One that starts in the Intermission (a lone player's next practice round, no wait) fills the
			-- bar by itself; otherwise the bar spans the wait and the Intermission.
			soloBar.at = soloAt
			soloBar.total = if phase == "Intermission" then math.max(1, left)
				else math.max(1, (tonumber(Config.Round.SoloWaitTime) or 30) + (tonumber(Config.Round.IntermissionTime) or 25))
		end
		local text = if phone() then string.format("PRACTICE IN   <b>%s</b>", Util.formatTime(left))
			else string.format("PRACTICE ROUND IN   <b>%s</b>   ·   OR WAIT FOR CONTENDERS", Util.formatTime(left))
		setStatus(text, math.clamp(left / soloBar.total, 0, 1), false, phase == "Lobby")
	elseif phase == "Lobby" then
		local count = math.floor(tonumber(GameState:GetAttribute("LobbyCount")) or 0)
		local need = math.max(1, math.floor(tonumber(GameState:GetAttribute("MinPlayers")) or Config.Round.MinPlayers))
		setStatus(string.format("WAITING FOR PLAYERS   <b>%d / %d</b>", count, need), nil, false, true)
	elseif phase == "Intermission" then
		local total = math.max(1, tonumber(Config.Round.IntermissionTime) or 1)
		setStatus(string.format("NEXT ROUND IN   <b>%s</b>", Util.formatTime(remaining)), remaining / total, false, false)
	elseif phase == "Countdown" then
		setStatus("ROUND STARTING", nil, false, true)
	elseif phase == "Active" then
		local alive = math.floor(tonumber(GameState:GetAttribute("AliveCount")) or 0)
		local can = canSpectate()
		local nextIn = Util.formatTime(nextRoundIn(remaining))
		local text
		if GameState:GetAttribute("Practice") == true then
			text = string.format("PRACTICE ROUND   ·   NEXT ROUND IN <b>%s</b> AT MOST", nextIn)
		elseif phone() then
			text = string.format("<b>%d</b> REMAIN   ·   NEXT ROUND IN <b>%s</b> AT MOST", alive, nextIn)
		else
			text = string.format("ROUND IN PROGRESS   ·   <b>%d</b> REMAIN   ·   NEXT ROUND IN <b>%s</b> AT MOST", alive, nextIn)
		end
		setStatus(text, nil, can, false)
	elseif phase == "Ending" then
		local winner = GameState:GetAttribute("WinnerName")
		if type(winner) == "string" and winner ~= "" then
			setStatus(string.format("ROUND OVER   ·   <b>%s</b> WINS", Theme.escape(string.upper(winner))), nil, false, false)
		else
			setStatus("ROUND OVER", nil, false, false)
		end
	else
		setStatus(string.upper(tostring(phase)), nil, false, false)
	end
	setSpectateBinding(spectateAvailable and visible == true)
end

local function refreshSpectateLabel()
	if Input.isGamepad() then
		R.spectate.Text = string.format("SPECTATE   <font transparency=\"0.35\">Y</font>")
	else
		R.spectate.Text = "SPECTATE"
	end
end

-- the death card or the round's result card (NotificationController) has the screen first: the lobby waits for it
local function cardUp(): boolean
	local notifications = Controllers and Controllers.NotificationController
	if notifications and notifications.isCardUp then
		local ok, up = pcall(notifications.isCardUp)
		return ok and up == true
	end
	return false
end

-- Headlines and the Roll Call list (NotificationController, drawn above this screen) have the place first. On phones
-- both use the top band, where the status pill is; elsewhere the Roll Call panel sits at the right edge, over HOW TO
-- PLAY. The pill and the panel step aside until they are gone, so text is never drawn over text.
local function updateYield()
	local headline, roll = false, false
	local notifications = Controllers and Controllers.NotificationController
	if notifications and notifications.isBannerUp then
		local ok, h, r = pcall(notifications.isBannerUp)
		if ok then
			headline, roll = h == true, r == true
		end
	end
	local small = phone()
	local hideStatus = (small and (headline or roll)) or chatYield
	local hideHowTo = roll or (small and headline)
	if R.status and hideStatus ~= statusYield then
		statusYield = hideStatus
		R.status.Visible = not hideStatus
	end
	if hideHowTo ~= howToYield then
		howToYield = hideHowTo
		if howToOpen and R.howTo then
			R.howTo.Visible = not hideHowTo
		end
	end
end

local function updateVisibility()
	local want = not ClientState.inArena and ClientState.spectating == nil and not cardUp()
	if want == visible then
		return
	end
	visible = want
	if gui then
		gui.Enabled = want
	end
	if want then
		applyLayout()
		-- a short rise as you arrive back in the lobby
		local target = R.brand.Position
		R.brand.Position = target + UDim2.fromOffset(0, 10)
		Theme.tween(R.brand, Theme.Tween.Slow, { Position = target })
	end
	setSpectateBinding(spectateAvailable and want)
end

local function styleButton(button: GuiButton, normal: number, hover: number)
	local hovered, selected = false, false
	local function apply()
		Theme.tween(button, Theme.Tween.Fast, { BackgroundTransparency = if hovered or selected then hover else normal })
	end
	button.MouseEnter:Connect(function()
		hovered = true
		apply()
		if not Input.isTouch() then
			Sfx.play("UIHover")
		end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		apply()
	end)
	button.SelectionGained:Connect(function()
		selected = true
		apply()
	end)
	button.SelectionLost:Connect(function()
		selected = false
		apply()
	end)
end

function LobbyController.Init(registry)
	Controllers = registry
end

function LobbyController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local lobby = playerGui:WaitForChild("Lobby") :: ScreenGui
	gui = lobby
	Theme.bindRoot(lobby)
	local root = lobby:WaitForChild("Root") :: any
	R.root = root
	R.rootScale = root:FindFirstChild("Scale")
	local status = root:WaitForChild("Status")
	R.status = status
	local pill = status:WaitForChild("Pill")
	R.pill = pill
	R.pillPad = pill:WaitForChild("Pad")
	R.dot = pill:WaitForChild("Dot")
	R.statusText = pill:WaitForChild("Text")
	R.spectate = pill:WaitForChild("Spectate")
	R.bar = status:WaitForChild("Bar")
	R.barFill = R.bar:WaitForChild("Fill")
	R.brand = root:WaitForChild("Brand")
	R.brandLayout = R.brand:WaitForChild("Layout")
	R.title = R.brand:WaitForChild("Title")
	local cells = R.brand:WaitForChild("Stats"):WaitForChild("Cells")
	R.wins = cells:WaitForChild("Wins"):WaitForChild("Value")
	R.kills = cells:WaitForChild("Kills"):WaitForChild("Value")
	R.rounds = cells:WaitForChild("Rounds"):WaitForChild("Value")
	local buttons = R.brand:WaitForChild("Buttons")
	R.settingsButton = buttons:WaitForChild("Settings")
	R.howToButton = buttons:WaitForChild("HowTo")
	R.howTo = root:WaitForChild("HowTo")
	R.howToClose = R.howTo:WaitForChild("Header"):WaitForChild("Close")
	local body = R.howTo:WaitForChild("Body")
	R.howToBody = body
	R.controlsHeader = body:WaitForChild("ControlsHeader")
	R.controls = body:WaitForChild("Controls")
	R.steps = body:FindFirstChild("Steps")
	if R.steps then
		-- QW6: the goal in one line, in our own names
		R.steps.Text = string.format("RISE ON YOUR PLATE  →  TAKE GEAR AT %s, OR RUN  →  OUTLAST %s", Lore.upper("Spire"), Lore.upper("Border"))
	end
	R.controlRow = root:WaitForChild("Templates"):WaitForChild("ControlRow")
	R.title.Text = Config.GameTitle

	local bg = R.howTo:FindFirstChild("Bg")
	if bg then
		bg.Active = true
	end

	R.settingsButton.Activated:Connect(function()
		Sfx.play("UIClick")
		local sc = settingsController()
		if sc and sc.open then
			sc.open("Settings")
		end
	end)
	R.howToButton.Activated:Connect(function()
		Sfx.play("UIClick")
		howToTouched = true
		setHowTo(not howToOpen, true)
	end)
	R.howToClose.Activated:Connect(function()
		Sfx.play("UIClick")
		howToTouched = true
		setHowTo(false, true)
	end)
	R.spectate.Activated:Connect(function()
		Sfx.play("UIClick")
		startSpectating()
	end)
	styleButton(R.settingsButton, Theme.Transparency.Panel, 0.15)
	styleButton(R.howToButton, Theme.Transparency.Panel, 0.15)
	styleButton(R.spectate, 0.05, 0)
	R.howToClose.MouseEnter:Connect(function()
		Theme.tween(R.howToClose, Theme.Tween.Fast, { BackgroundTransparency = 0.5 })
	end)
	R.howToClose.MouseLeave:Connect(function()
		Theme.tween(R.howToClose, Theme.Tween.Fast, { BackgroundTransparency = 1 })
	end)

	for _, attribute in ipairs({ "Wins", "TotalKills", "RoundsPlayed" }) do
		player:GetAttributeChangedSignal(attribute):Connect(refreshStats)
	end
	refreshStats()
	UserInputService.LastInputTypeChanged:Connect(function()
		refreshSpectateLabel()
		if howToOpen then
			refreshControls()
		end
	end)
	refreshSpectateLabel()

	applyLayout()
	setHowTo(howToByDefault(), false)
	-- RoundsPlayed arrives from the save a moment after joining, and goes up after a first round
	player:GetAttributeChangedSignal("RoundsPlayed"):Connect(function()
		if not howToTouched and howToOpen ~= howToByDefault() then
			setHowTo(howToByDefault(), visible == true)
		end
	end)
	ClientState.lifeChanged:Connect(updateVisibility)
	ClientState.spectateChanged:Connect(updateVisibility)
	updateVisibility()
	updateStatus()

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if visible then
				applyLayout()
			end
		end)
	end

	while true do
		updateVisibility() -- it also waits for the death and result cards
		updateChat(visible == true)
		if visible then
			updateStatus()
			updateYield()
			fitHowTo() -- its rows arrive a frame after they are filled, and change with the device
		end
		task.wait(0.1)
	end
end

return LobbyController
