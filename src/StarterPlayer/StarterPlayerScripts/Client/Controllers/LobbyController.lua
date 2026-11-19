--[[
	LobbyController - the lobby screen (StarterGui.Lobby, built by ServerStorage.WorldGen.UIBuilder), in the "Quiet"
	style (docs/design/ui/StyleA_Quiet/lobby.html). Owned by the UI system. No boxes: text and lines on the picture.

	On a PC or console (the mock-up's layout):
	  * Bottom left: the title in spaced letters (Config.GameTitle), the status line with a slim progress line, a
	    second line under it, then the text buttons SETTINGS, HOW TO PLAY (and ROBLOX PLUS, PlusController).
	  * Bottom right: who is in the lobby (you first, then by wins): face, name, a YOU or PLUS tag, wins.
	    It shares the right edge with HOW TO PLAY, so it shows while that sheet is closed.
	On a touch screen the thumbstick and the buttons own the bottom, so the title and buttons are top left and the
	status lines top centre, as before. A phone has no room for the list: it keeps the one-line record instead.

	The status, from GameState (two lines: what is happening, and what you need to know about it):
	    "Waiting for players 1 / 2"   ·  "A round needs 2 contenders"
	    "Next round in 0:12" + line   ·  "7 contenders waiting"
	    "Practice round in 0:55"      ·  "Or wait for contenders"      (alone on a server, QW1: GameState.SoloStartAt)
	    "Round starting"
	    "Round in progress" SPECTATE  ·  "9 remain · next round in 6:57 at most"   (gamepad: Y spectates)
	    "Round over"                  ·  "Kestrel wins"
	  The "at most" time (QW4) is what's left of the round plus Ending (with the epilogue), Intermission and Countdown.
	  Status stays a child of Lobby.Root (other code looks it up there); on a PC it is placed under the title.

	HOW TO PLAY (Lobby.Root.HowTo, built by UIBuilder; this controller drives it): the goal in one line (Shared.Lore),
	the tips, and the controls for the device in use. Open by default only until you've played a round (RoundsPlayed
	0, larger screens; QW6), a toggle on phones and afterwards. On a PC or console it is as tall as its rows need and,
	on a short screen, shrinks as a whole so no row needs scrolling from 720 px of height up (fitHowTo). It has no
	box: one soft shade with no edge on screen lies behind its text (a band down the right side whose inner side
	fades out; on a phone a band down the middle, and the rest of the lobby steps aside while it is open).

	A sheet with no box cannot lie over other text, so the lobby's own parts hide while one is up: the menu
	(ClientState.menuOpen) or a cover another controller asks for (setCover: the Roblox Plus sheet).
	Roblox's chat window never sits on a top-centre status line: it is kept narrower than the gap beside the line
	while the lobby shows, and the line waits when even that is not enough (updateChat; touch layout only).
	Shown while you're not in the arena and not spectating, and once the death card or the round's result card
	(NotificationController.isCardUp) has gone. While a headline or the Roll Call list shows
	(NotificationController.isBannerUp), the status lines (phones: they share the top band) and the right edge
	(HOW TO PLAY, the list: the Roll Call panel's place) step aside.

	Public API (Controllers.LobbyController):
	  setHowToVisible(visible: boolean)
	  setCover(reason: string, on: boolean)    hide the lobby's own text while a sheet of yours is over it
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
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
local howToYield = false -- hidden for a headline, the Roll Call or a sheet (refreshShown)
local chatYield = false -- Roblox's chat window is open over the status line and cannot be made narrower (updateChat)
local statusInBrand = false -- PC and console: the status lines sit under the title; touch: top centre
local covers: { [string]: boolean } = {} -- sheets of other controllers that lie over the lobby (setCover)
local soloBar = { at = 0, total = 1 } -- QW1: the practice countdown on show (its SoloStartAt) and its bar's full length
local riseUntil = 0 -- os.clock() until which the arrival rise owns the status lines' place

-- Design px (the root's own pixels, before its UIScale).
local STATUS_HEIGHT = 70 -- the status line (40), its progress line (at 42) and the second line (at 50, 18 tall)
local STATUS_BAR_Y, STATUS_SUB_Y = 42, 50
local STATUS_BAR_WIDTH, STATUS_BAR_WIDTH_TOP = 298, 220 -- under the title (372 px at 1080p); at the top centre
local STATUS_SLOT_ORDER = 3 -- the status lines' place in Brand's column, between the title and the buttons
local BRAND_GAP = 40 -- PC and console: the air between the status lines and the buttons
local LIST_WIDTH, LIST_GAP = 300, 40 -- the list of who is here, and the least room between it and the title
local LIST_MAX_ROWS = 10

-- A number inside a line of words: RobotoMono (numbers that change do not make the line jump), a little smaller.
local MONO_FAMILY = Theme.Fonts.Mono.Family
local function num(value: any, size: number?): string
	if size then
		return string.format('<font family="%s" size="%d">%s</font>', MONO_FAMILY, math.max(Theme.TextSize.Small, math.floor(size)), tostring(value))
	end
	return string.format('<font family="%s">%s</font>', MONO_FAMILY, tostring(value))
end

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

-- The root's UIScale, and the height and width inside its padding, in design px.
local function rootMetrics(): (number, number, number)
	local root, rootScale = R.root, R.rootScale
	local s = if rootScale and rootScale.Scale > 0 then rootScale.Scale else 1
	local safePad = root:FindFirstChild("SafePad")
	local padY, padX = 0, 0
	if safePad and safePad:IsA("UIPadding") then
		padY = safePad.PaddingTop.Offset + safePad.PaddingBottom.Offset
		padX = safePad.PaddingLeft.Offset + safePad.PaddingRight.Offset
	end
	return s, root.AbsoluteSize.Y / s - padY, root.AbsoluteSize.X / s - padX
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

----------------------------------------------------------------------------------------------------------------------
-- HOW TO PLAY
----------------------------------------------------------------------------------------------------------------------
local HOWTO_WIDTH, HOWTO_MARGIN, HOWTO_CHROME, HOWTO_MIN_SCALE = 330, 70, 48, 0.8 -- (chrome: the header and divider)
local HOWTO_WIDTH_PHONE = 360
local HOWTO_GROW_STEP = 0.08
-- The one soft shade behind the sheet's long text. It has no edge on screen: a tall band that runs past the top and
-- the bottom (and, at the right edge, past the side), its inner side(s) faded out by a UIGradient. 1 = no shade.
local HOWTO_SHADE = 0.5
local SHADE_BLEED, SHADE_FEATHER, SHADE_FEATHER_PHONE = 300, 150, 110

-- Clear at the left end, full after `f` of the width; `both` fades the right end the same way.
local function feather(f: number, both: boolean): NumberSequence
	local k = NumberSequenceKeypoint.new
	local points = { k(0, 1), k(f * 0.4, 0.7), k(f * 0.75, 0.2), k(f, 0) }
	if both then
		table.insert(points, k(1 - f, 0))
		table.insert(points, k(1 - f * 0.75, 0.2))
		table.insert(points, k(1 - f * 0.4, 0.7))
		table.insert(points, k(1, 1))
	else
		table.insert(points, k(1, 0))
	end
	return NumberSequence.new(points)
end

local function placeShade()
	local shade, fade = R.howToShade, R.howToFade
	if not shade or not fade then
		return
	end
	if phone() then
		local width = HOWTO_WIDTH_PHONE + 2 * SHADE_FEATHER_PHONE
		shade.AnchorPoint = Vector2.new(0.5, 0.5)
		shade.Position = UDim2.fromScale(0.5, 0.5)
		shade.Size = UDim2.new(0, width, 1, 2 * SHADE_BLEED)
		fade.Transparency = feather(SHADE_FEATHER_PHONE / width, true)
	else
		local width = HOWTO_WIDTH + 12 + SHADE_BLEED + SHADE_FEATHER
		shade.AnchorPoint = Vector2.new(1, 0.5)
		shade.Position = UDim2.new(1, SHADE_BLEED, 0.5, 0)
		shade.Size = UDim2.new(0, width, 1, 2 * SHADE_BLEED)
		fade.Transparency = feather(SHADE_FEATHER / width, false)
	end
end

local refreshShown: () -> ()

local function setHowTo(on: boolean, animate: boolean?)
	howToOpen = on
	local panel, shade = R.howTo, R.howToShade
	if on then
		refreshControls()
		panel.Visible = not howToYield -- (a Roll Call, a headline or a sheet has its place for the moment: refreshShown)
		if shade then
			shade.Visible = panel.Visible
		end
		if animate then
			panel.GroupTransparency = 1
			QuietUI.tween(panel, Theme.Tween.Normal, { GroupTransparency = 0 })
			if shade then
				shade.BackgroundTransparency = 1
				QuietUI.tween(shade, Theme.Tween.Normal, { BackgroundTransparency = HOWTO_SHADE })
			end
		else
			panel.GroupTransparency = 0
			if shade then
				shade.BackgroundTransparency = HOWTO_SHADE
			end
		end
	else
		local function hide()
			if not howToOpen then
				panel.Visible = false
				if shade then
					shade.Visible = false
				end
			end
		end
		if animate then
			if shade then
				QuietUI.tween(shade, Theme.Tween.Fast, { BackgroundTransparency = 1 })
			end
			local t = QuietUI.tween(panel, Theme.Tween.Fast, { GroupTransparency = 1 })
			if t then
				t.Completed:Once(hide)
			else
				hide() -- (reduced motion: set at once)
			end
		else
			hide()
		end
	end
	R.howToButton.Text = if on then "HIDE HELP" else "HOW TO PLAY"
	if refreshShown then
		refreshShown() -- the list of who is here has the right edge while the sheet is closed
	end
end
LobbyController.setHowToVisible = function(on: boolean)
	if R.howTo then
		setHowTo(on, true)
	end
end

-- HOW TO PLAY on a PC or console: every row on the panel without scrolling, from a 720-high screen up (16:9 and
-- 16:10; it used to stop 70 px short of the top and bottom edges, 560 px at most, and cut the last two rows). The
-- panel is as tall as its text needs. It keeps its old place (70 px from the top) while it fits there, then takes the
-- room down to the bottom edge (the list of who is here gives it the right edge), then up; and when the whole height
-- is still not enough (a 720-high screen: Roblox's top bar takes 58 px of it) the panel shrinks as a whole (UIScale
-- "Fit", never under HOWTO_MIN_SCALE; below that the body scrolls, as before). Sizes are the root's design pixels.
local function fitHowTo()
	local how, root, body = R.howTo, R.root, R.howToBody
	if not how or not root or not body or not howToOpen or UserInputService.TouchEnabled then
		return
	end
	local s, inner = rootMetrics()
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

----------------------------------------------------------------------------------------------------------------------
-- Roblox's chat window and a top-centre status line
----------------------------------------------------------------------------------------------------------------------
-- Roblox's chat window (top left; closed by default, HUDController) and the status line when it is top centre (the
-- touch layout; on a PC the line is under the title at the bottom left, far from the chat window). At window widths
-- under about 1,400 px an open chat window reached the left end of the line (a late joiner's first view). While the
-- lobby screen shows, the chat window is kept narrower than the gap beside the line (its WidthScale, down to
-- CHAT_MIN_SCALE); if it is open and still over the line at that size (a very narrow window), the line waits until
-- the chat closes (refreshShown). Outside the lobby the chat window has its full width back.
local CHAT_MIN_SCALE, CHAT_GAP, STATUS_MAX_WIDTH = 0.6, 12, 450 -- (the longest line with its SPECTATE button, design px)
local function updateChat(lobbyShown: boolean)
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if not window then
		chatYield = false
		return
	end
	if not lobbyShown or statusInBrand then
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
	if status and pill then
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

----------------------------------------------------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------------------------------------------------
-- What Brand's column holds under the status lines' slot (design px): the status lines are a child of the root, so
-- on a PC they are placed over the slot from the root's bottom edge.
local function belowSlot(): number
	local gap = R.brandLayout.Padding.Offset
	local total = 0
	for _, child in ipairs(R.brand:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and child.LayoutOrder > STATUS_SLOT_ORDER then
			total += child.Size.Y.Offset + gap
		end
	end
	return total
end

local function statusPosition(): UDim2
	if statusInBrand then
		return UDim2.new(0, 0, 1, -belowSlot())
	end
	return UDim2.fromScale(0.5, 0)
end

local function placeStatus()
	local status, pill, bar, sub = R.status, R.pill, R.bar, R.sub
	if statusInBrand then
		status.AnchorPoint = Vector2.new(0, 1)
		pill.AnchorPoint = Vector2.zero
		pill.Position = UDim2.new()
		R.pillPad.PaddingLeft = UDim.new(0, 0)
		bar.AnchorPoint = Vector2.zero
		bar.Position = UDim2.fromOffset(0, STATUS_BAR_Y)
		bar.Size = UDim2.fromOffset(STATUS_BAR_WIDTH, 2)
		sub.TextXAlignment = Enum.TextXAlignment.Left
	else
		status.AnchorPoint = Vector2.new(0.5, 0)
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.fromScale(0.5, 0)
		R.pillPad.PaddingLeft = UDim.new(0, 4)
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Position = UDim2.new(0.5, 0, 0, STATUS_BAR_Y)
		bar.Size = UDim2.fromOffset(STATUS_BAR_WIDTH_TOP, 2)
		sub.TextXAlignment = Enum.TextXAlignment.Center
	end
	status.Position = statusPosition()
	status.Size = UDim2.fromOffset(640, STATUS_HEIGHT)
end

-- The spaced title never reaches the list of who is here: on a narrow window it shrinks as a whole (UIScale "Fit").
local function fitTitle()
	local row, letters = R.titleRow, R.letters
	if not row or not row.Visible or not letters or #letters == 0 then
		return
	end
	local fit = row:FindFirstChild("Fit")
	if not fit or not fit:IsA("UIScale") then
		local made = Instance.new("UIScale")
		made.Name = "Fit"
		made.Parent = row
		fit = made
	end
	local s, _, innerWidth = rootMetrics()
	local f = if fit.Scale > 0 then fit.Scale else 1
	local first, last = letters[1], letters[#letters]
	local width = (last.AbsolutePosition.X + last.AbsoluteSize.X - first.AbsolutePosition.X) / (s * f)
	if width <= 1 or innerWidth < 100 then
		return
	end
	local room = math.max(200, innerWidth - LIST_WIDTH - LIST_GAP)
	local scale = math.clamp(room / width, 0.5, 1)
	if math.abs(fit.Scale - scale) > 0.01 then
		fit.Scale = scale
	end
end

local function listAvailable(): boolean
	return R.players ~= nil and R.playerRow ~= nil and not phone()
end

local function applyLayout()
	local brand, how = R.brand, R.howTo
	local touch = UserInputService.TouchEnabled
	local small = phone()
	statusInBrand = not touch
	if touch then
		-- thumbstick and jump live at the bottom: keep the lobby UI up top
		brand.AnchorPoint = Vector2.new(0, 0)
		brand.Position = UDim2.fromOffset(0, 0)
		R.brandLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		if R.titleRow then
			R.titleRow.Visible = false
		end
		R.title.Visible = true
		R.title.TextSize = 28
		R.title.Size = UDim2.new(1, 0, 0, 34)
		R.statusSlot.Visible = false
		R.brandGap.Visible = false
		R.buttons.Size = UDim2.new(1, 0, 0, 44) -- a finger's 44 px (QuietUI.bindButton grows the buttons to it)
		if small then
			how.AnchorPoint = Vector2.new(0.5, 0.5)
			how.Position = UDim2.fromScale(0.5, 0.5)
			how.Size = UDim2.new(0, HOWTO_WIDTH_PHONE, 1, -16)
		else
			how.AnchorPoint = Vector2.new(1, 0)
			how.Position = UDim2.new(1, 0, 0, 64)
			how.Size = UDim2.new(0, HOWTO_WIDTH, 1, -240)
		end
	else
		brand.AnchorPoint = Vector2.new(0, 1)
		brand.Position = UDim2.fromScale(0, 1)
		R.brandLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		if R.titleRow then
			R.titleRow.Visible = true
			R.title.Visible = false
		else
			R.title.Visible = true
			R.title.TextSize = Theme.TextSize.Display
			R.title.Size = UDim2.new(1, 0, 0, 52)
		end
		R.statusSlot.Visible = true
		R.brandGap.Visible = true
		R.buttons.Size = UDim2.new(1, 0, 0, 34)
		fitHowTo() -- the right edge, as tall as its text needs
	end
	-- the one-line record only where the list of who is here (it has your wins) has no room: phones
	R.stats.Visible = not listAvailable()
	-- the status line: Light 24, or Medium 16 on a phone (Light is for 24 px and up; a phone's top band is narrow)
	local text = R.statusText
	if small then
		text.FontFace = Theme.Fonts.Medium
		text.TextSize = Theme.TextSize.Body
	else
		text.FontFace = Theme.Fonts.Light
		text.TextSize = Theme.TextSize.Status
	end
	Theme.shadow(text, not small)
	placeStatus()
	placeShade()
	-- who is here: bottom right on a PC, top right (HOW TO PLAY's place, above the jump button) on a tablet
	local list = R.players
	if list then
		local layout = list:FindFirstChild("Layout")
		if touch then
			list.AnchorPoint = Vector2.new(1, 0)
			list.Position = UDim2.new(1, 0, 0, 64)
		else
			list.AnchorPoint = Vector2.new(1, 1)
			list.Position = UDim2.fromScale(1, 1)
		end
		if layout and layout:IsA("UIListLayout") then
			layout.VerticalAlignment = if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
		end
	end
	fitTitle()
end

local function refreshStats()
	R.wins.Text = tostring(math.floor(tonumber(player:GetAttribute("Wins")) or 0))
	R.kills.Text = tostring(math.floor(tonumber(player:GetAttribute("TotalKills")) or 0))
	R.rounds.Text = tostring(math.floor(tonumber(player:GetAttribute("RoundsPlayed")) or 0))
end

----------------------------------------------------------------------------------------------------------------------
-- Who is in the lobby
----------------------------------------------------------------------------------------------------------------------
local listRows: { [Player]: any } = {}
local moreRow: any = nil
local listDirty = true
local listAt = 0
local listCount = 0

local function winsOf(other: Player): number
	return math.floor(tonumber(other:GetAttribute("Wins")) or 0)
end

local function lobbyPeople(): { Player }
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other == player or other:GetAttribute("InArena") ~= true then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a: Player, b: Player): boolean
		if (a == player) ~= (b == player) then
			return a == player
		end
		local wa, wb = winsOf(a), winsOf(b)
		if wa ~= wb then
			return wa > wb
		end
		local na, nb = string.lower(a.DisplayName), string.lower(b.DisplayName)
		if na ~= nb then
			return na < nb
		end
		return a.UserId < b.UserId
	end)
	return list
end

-- How many rows the screen has room for (the list grows up from the bottom edge on a PC, down from under the top
-- band on a tablet, where the jump button owns the bottom 240 px).
local function listRoom(): number
	local _, inner = rootMetrics()
	local rowHeight = math.max(1, R.playerRow.Size.Y.Offset)
	local room = if UserInputService.TouchEnabled then inner - 64 - 240 else inner - 150
	return math.clamp(math.floor((room - 30) / rowHeight), 3, LIST_MAX_ROWS)
end

local function newRow(): any
	local row = R.playerRow:Clone()
	row.Visible = true
	return row
end

local function paintRow(row: any, other: Player, order: number)
	row.LayoutOrder = order
	local own = other == player
	local left = row.Left
	if left.PlayerName.Text ~= other.DisplayName then
		left.PlayerName.Text = other.DisplayName
	end
	local tag = if own then "YOU" elseif other:GetAttribute("PlusMember") == true then "PLUS" else ""
	left.Tag.Text = tag
	left.Tag.Visible = tag ~= ""
	row.Mark.Visible = own
	local rounds = other:GetAttribute("RoundsPlayed")
	local wins = winsOf(other)
	local text, dim = "", false
	if type(rounds) ~= "number" then
		text = "" -- their record has not arrived yet
	elseif rounds <= 0 then
		text, dim = "first round", true
	elseif wins <= 0 then
		text, dim = "no wins yet", true
	else
		text = string.format("%s %s", num(wins), if wins == 1 then "win" else "wins")
	end
	if row.Wins.Text ~= text then
		row.Wins.Text = text
	end
	row.Wins.TextColor3 = if dim then C.Ink2 else C.Ink
end

local function refreshPlayers()
	listDirty = false
	listAt = os.clock()
	local holder = R.players
	if not holder or not R.playerRow then
		listCount = 0
		return
	end
	local rowsFrame = holder:FindFirstChild("Rows")
	if not rowsFrame then
		listCount = 0
		return
	end
	local people = lobbyPeople()
	local cap = listRoom()
	local shown = if #people > cap then cap - 1 else #people -- (the last row then says how many more)
	local keep: { [Player]: boolean } = {}
	for i = 1, shown do
		local other = people[i]
		keep[other] = true
		local row = listRows[other]
		if not row then
			row = newRow()
			row.Name = "Row_" .. tostring(other.UserId)
			if other.UserId > 0 then
				-- Roblox's own headshot of the player (nothing is uploaded)
				row.Left.Face.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", other.UserId)
			end
			listRows[other] = row
			paintRow(row, other, i)
			row.Parent = rowsFrame
		else
			paintRow(row, other, i)
		end
	end
	for other, row in pairs(listRows) do
		if not keep[other] then
			listRows[other] = nil
			row:Destroy()
		end
	end
	local more = #people - shown
	if more > 0 then
		if not moreRow then
			moreRow = newRow()
			moreRow.Name = "More"
			moreRow.Mark.Visible = false
			moreRow.Left.Face.Visible = false
			moreRow.Left.Tag.Visible = false
			moreRow.Left.PlayerName.TextColor3 = C.Ink2
			moreRow.Wins.Text = ""
			moreRow.Parent = rowsFrame
		end
		moreRow.LayoutOrder = shown + 1
		moreRow.Left.PlayerName.Text = string.format("and %d more", more)
		moreRow.Visible = true
	elseif moreRow then
		moreRow.Visible = false
	end
	local header = holder:FindFirstChild("Header")
	local count = header and header:FindFirstChild("Count")
	if count and count:IsA("TextLabel") then
		count.Text = tostring(#people)
	end
	listCount = #people
end

----------------------------------------------------------------------------------------------------------------------
-- Spectating from the lobby
----------------------------------------------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------------------------------------------
-- The status lines
----------------------------------------------------------------------------------------------------------------------
local function setStatus(text: string, sub: string, progress: number?, showSpectate: boolean)
	if R.statusText.Text ~= text then
		R.statusText.Text = text
	end
	if R.sub.Text ~= sub then
		R.sub.Text = sub
	end
	R.bar.Visible = progress ~= nil
	if progress then
		R.barFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	end
	if showSpectate ~= spectateAvailable then
		spectateAvailable = showSpectate
		R.spectate.Visible = showSpectate
	end
end

local function updateStatus()
	local phase = GameState:GetAttribute("Phase") or "Lobby"
	local now = workspace:GetServerTimeNow()
	local endsAt = tonumber(GameState:GetAttribute("PhaseEndsAt")) or 0
	local remaining = math.max(0, endsAt - now)
	local soloAt = tonumber(GameState:GetAttribute("SoloStartAt")) or 0
	local size = R.statusText.TextSize - 2 -- the numbers in the status line, a little smaller than its words
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
		local text = string.format(if phone() then "Practice in %s" else "Practice round in %s", num(Util.formatTime(left), size))
		setStatus(text, "Or wait for contenders", math.clamp(left / soloBar.total, 0, 1), false)
	elseif phase == "Lobby" then
		local count = math.floor(tonumber(GameState:GetAttribute("LobbyCount")) or 0)
		local need = math.max(1, math.floor(tonumber(GameState:GetAttribute("MinPlayers")) or Config.Round.MinPlayers))
		setStatus(string.format("Waiting for players %s", num(string.format("%d / %d", count, need), size)),
			if need > 1 then string.format("A round needs %s contenders", num(need)) else "", nil, false)
	elseif phase == "Intermission" and (GameState:GetAttribute("TrainStage") or "") ~= "" then
		-- the road to the arena (TrainRideService): the ride, the training, the launch doors; PhaseEndsAt is the call
		local stage = GameState:GetAttribute("TrainStage")
		local solo = GameState:GetAttribute("TrainSolo") == true
		local atCentre = player:GetAttribute("AtTrainingCentre") == true
		if stage == "Ride" and not atCentre then
			local left = math.max(0, (tonumber(GameState:GetAttribute("TrainRideEnd")) or now) - now)
			setStatus(string.format("The Training Centre in %s", num(Util.formatTime(left), size)), "On the train", nil, false)
		elseif GameState:GetAttribute("TrainDoorsOpen") == true then
			if player:GetAttribute("TrainHeld") == false then
				setStatus("This round is full", "You are first on the next train", nil, false)
			elseif solo and player:GetAttribute("InRedRoom") ~= true then
				-- alone the launch doors stand open from the arrival: train as long as you like, up to the call
				setStatus("Training Centre: try the stations", string.format("The doors to the launch are open · the call in %s",
					num(Util.formatTime(remaining))), nil, false)
			else
				setStatus(string.format("The call in %s", num(Util.formatTime(remaining), size)),
					if player:GetAttribute("InRedRoom") == true then "Stand on the disc" else "The doors are open · walk to the red room", nil, false)
			end
		else
			-- one quiet line from the arrival: what this place is and when the way on opens (the marker shows the hall)
			local doorsLeft = math.max(0, (tonumber(GameState:GetAttribute("TrainDoorsAt")) or now) - now)
			local line = string.format("Training Centre: try the stations · doors to the launch open in %s", num(Util.formatTime(doorsLeft), size))
			if phone() then
				setStatus("Training Centre: try the stations", string.format("Doors to the launch open in %s", num(Util.formatTime(doorsLeft))), nil, false)
			else
				setStatus(line, "", nil, false)
			end
		end
	elseif phase == "Intermission" then
		local total = math.max(1, tonumber(Config.Round.IntermissionTime) or 1)
		local count = math.floor(tonumber(GameState:GetAttribute("LobbyCount")) or 0)
		local sub = if count <= 0 then "" else string.format("%s %s waiting", num(count), if count == 1 then "contender" else "contenders")
		setStatus(string.format("Next round in %s", num(Util.formatTime(remaining), size)), sub, remaining / total, false)
	elseif phase == "Countdown" then
		setStatus("Round starting", "", nil, false)
	elseif phase == "Active" then
		local alive = math.floor(tonumber(GameState:GetAttribute("AliveCount")) or 0)
		local can = canSpectate()
		local nextIn = num(Util.formatTime(nextRoundIn(remaining)))
		if GameState:GetAttribute("Practice") == true then
			setStatus("Practice round in progress", string.format("Next round in %s at most", nextIn), nil, can)
		else
			setStatus("Round in progress", string.format("%s remain  ·  next round in %s at most", num(alive), nextIn), nil, can)
		end
	elseif phase == "Ending" then
		local winner = GameState:GetAttribute("WinnerName")
		if type(winner) == "string" and winner ~= "" then
			setStatus("Round over", string.format("%s wins", Theme.escape(winner)), nil, false)
		else
			setStatus("Round over", "", nil, false)
		end
	else
		setStatus(Theme.escape(tostring(phase)), "", nil, false)
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

----------------------------------------------------------------------------------------------------------------------
-- What shows
----------------------------------------------------------------------------------------------------------------------
-- the death card or the round's result card (NotificationController) has the screen first: the lobby waits for it
local function cardUp(): boolean
	local notifications = Controllers and Controllers.NotificationController
	if notifications and notifications.isCardUp then
		local ok, up = pcall(notifications.isCardUp)
		return ok and up == true
	end
	return false
end

local function setShown(object: any, on: boolean)
	if object and object.Visible ~= on then
		object.Visible = on
	end
end

-- Every part's Visible in one place, so text is never drawn over text.
--   * Headlines and the Roll Call list (NotificationController, drawn above this screen) have the place first. On
--     phones both use the top band, where the status lines are; elsewhere the Roll Call panel sits at the right
--     edge, over HOW TO PLAY and the list of who is here.
--   * A sheet (the menu, the Roblox Plus sheet, HOW TO PLAY on a phone) has no box to hide what is under it: the
--     lobby's own text steps aside while it is up.
--   * Roblox's chat window over a top-centre status line (updateChat).
refreshShown = function()
	if not R.root then
		return
	end
	local headline, roll = false, false
	local notifications = Controllers and Controllers.NotificationController
	if notifications and notifications.isBannerUp then
		local ok, h, r = pcall(notifications.isBannerUp)
		if ok then
			headline, roll = h == true, r == true
		end
	end
	local small = phone()
	local covered = next(covers) ~= nil or ClientState.menuOpen == true
	local hideHowTo = covered or roll or (small and headline)
	if hideHowTo ~= howToYield then
		howToYield = hideHowTo
		if howToOpen then
			setShown(R.howTo, not hideHowTo)
			setShown(R.howToShade, not hideHowTo)
		end
	end
	local sheet = small and howToOpen and not howToYield -- HOW TO PLAY over the middle of a phone
	local topBand = not statusInBrand and small and (headline or roll)
	setShown(R.brand, not covered and not sheet)
	setShown(R.status, not covered and not sheet and not topBand and not (chatYield and not statusInBrand))
	setShown(R.players, listAvailable() and listCount > 0 and not covered and not howToOpen and not roll)
end

function LobbyController.setCover(reason: string, on: boolean)
	covers[reason] = if on then true else nil
	refreshShown()
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
		listDirty = true
		refreshShown()
		-- a short rise as you arrive back in the lobby (the status lines ride with the title on a PC)
		local target = R.brand.Position
		R.brand.Position = target + UDim2.fromOffset(0, 10)
		QuietUI.tween(R.brand, Theme.Tween.Slow, { Position = target })
		if statusInBrand then
			local statusTarget = statusPosition()
			R.status.Position = statusTarget + UDim2.fromOffset(0, 10)
			QuietUI.tween(R.status, Theme.Tween.Slow, { Position = statusTarget })
			riseUntil = os.clock() + Theme.Tween.Slow.Time + 0.1
		end
	end
	setSpectateBinding(spectateAvailable and want)
end

local function hoverSound()
	if not Input.isTouch() then
		Sfx.play("UIHover")
	end
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
	R.stats = R.brand:WaitForChild("Stats")
	local cells = R.stats:WaitForChild("Cells")
	R.wins = cells:WaitForChild("Wins"):WaitForChild("Value")
	R.kills = cells:WaitForChild("Kills"):WaitForChild("Value")
	R.rounds = cells:WaitForChild("Rounds"):WaitForChild("Value")
	local buttons = R.brand:WaitForChild("Buttons")
	R.buttons = buttons
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
	local templates = root:WaitForChild("Templates")
	R.controlRow = templates:WaitForChild("ControlRow")
	R.title.Text = Config.GameTitle

	-- The parts that came with the Quiet style. A screen built before it has none of them: the title then stays one
	-- label and there is no list.
	local titleRow = R.brand:FindFirstChild("TitleRow")
	if titleRow and titleRow:IsA("GuiObject") then
		R.titleRow = titleRow
		R.letters = QuietUI.letters(titleRow, string.upper(tostring(Config.GameTitle)))
	end
	local players = root:FindFirstChild("Players")
	local playerRow = templates:FindFirstChild("PlayerRow")
	if players and players:IsA("GuiObject") and playerRow and playerRow:IsA("GuiObject") then
		R.players = players
		R.playerRow = playerRow
	end

	-- The status lines. The amber dot goes (the words say it), and the second line ("7 contenders waiting") moves
	-- from Brand to sit under the progress line, so the two lines travel together (under the title on a PC, top
	-- centre on a touch screen).
	R.dot.Visible = false
	R.pillPad.PaddingRight = UDim.new(0, 4)
	local sub = R.brand:FindFirstChild("Waiting")
	if not (sub and sub:IsA("TextLabel")) then
		sub = QuietUI.label({ Name = "Waiting", Font = "Medium", TextSize = Theme.TextSize.Label })
	end
	sub.RichText = true
	sub.Text = ""
	sub.AnchorPoint = Vector2.zero
	sub.Position = UDim2.fromOffset(0, STATUS_SUB_Y)
	sub.Size = UDim2.new(1, 0, 0, 18)
	sub.Visible = true
	sub.Parent = status
	R.sub = sub
	-- Brand's column, top to bottom: (PRIVATE SERVER, PlusController: 0) TitleRow 1, Title 2, the status lines' slot 3,
	-- the record 5, air 6, the buttons 7.
	local function spacer(name: string, height: number, order: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Size = UDim2.new(1, 0, 0, height)
		f.LayoutOrder = order
		f.Visible = false
		f.Parent = R.brand
		return f
	end
	R.statusSlot = spacer("StatusSlot", STATUS_HEIGHT, STATUS_SLOT_ORDER)
	R.brandGap = spacer("Gap", BRAND_GAP, 6)
	R.stats.LayoutOrder = 5
	buttons.LayoutOrder = 7

	-- HOW TO PLAY's one soft shade (behind every part of the lobby, never over its text)
	local shade = Instance.new("Frame")
	shade.Name = "HowToShade"
	shade.BackgroundColor3 = C.Shade
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.ZIndex = 0
	shade.Visible = false
	local fade = Instance.new("UIGradient")
	fade.Name = "Fade"
	fade.Parent = shade
	shade.Parent = root
	R.howToShade = shade
	R.howToFade = fade
	R.root = root -- (last: refreshShown and setCover wait for it)

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
	-- plain text buttons: brighter text and a thin underline on hover and on a gamepad's focus, no box
	for _, button in ipairs({ R.settingsButton, R.howToButton, R.spectate, R.howToClose }) do
		QuietUI.bindButton(button, { onHover = hoverSound })
	end

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
	Players.PlayerAdded:Connect(function()
		listDirty = true
	end)
	Players.PlayerRemoving:Connect(function()
		listDirty = true
	end)
	ClientState.lifeChanged:Connect(updateVisibility)
	ClientState.spectateChanged:Connect(updateVisibility)
	local sc = settingsController()
	if sc and sc.menuChanged then
		sc.menuChanged:Connect(function()
			refreshShown() -- the menu is a sheet with no box: the lobby's text steps aside at once
		end)
	end
	updateVisibility()
	updateStatus()

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if visible then
				applyLayout()
				listDirty = true
			end
		end)
	end

	while true do
		updateVisibility() -- it also waits for the death and result cards
		updateChat(visible == true)
		if visible then
			updateStatus()
			if listAvailable() and (listDirty or os.clock() - listAt >= 1) then
				refreshPlayers() -- wins, tags and who is in the arena change without a signal of their own
			end
			refreshShown()
			fitHowTo() -- its rows arrive a frame after they are filled, and change with the device
			fitTitle()
			if statusInBrand and os.clock() >= riseUntil then
				-- what Brand holds under the status lines can change (the record line comes and goes with the list)
				local want = statusPosition()
				if R.status.Position ~= want then
					R.status.Position = want
				end
			end
		end
		task.wait(0.1)
	end
end

return LobbyController
