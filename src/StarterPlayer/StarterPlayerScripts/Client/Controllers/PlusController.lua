--[[
	PlusController - Roblox Plus (Roblox's own subscription) in the lobby: the client half. PlusService is the server half.

	Everything it draws lives inside the Lobby screen (PlayerGui.Lobby, LobbyController's), so it is on show only when
	the lobby is: never in the arena, on the death or result card, or while spectating.
	The look is "Quiet" (docs/design/ui/StyleA_Quiet/lobby.html): no boxes, text on the picture with a dark stroke.
	  * "ROBLOX PLUS": one quiet text button at the end of the lobby's button row (SETTINGS, HOW TO PLAY). Dimmer
	    text than its neighbours (QuietUI.button Quiet), no backing, no motion, no sound, no counter. Shown only when the server says so
	    (PlusService: not a member, allowed to buy subscriptions, the API exists). Nothing opens by itself. It is
	    not offered in the Countdown or the last 12 seconds before the lobby's players are picked (roundNear).
	  * Pressing it opens a small sheet of the game's own words saying exactly what a member gets here, with SUBSCRIBE
	    and CLOSE. SUBSCRIBE asks the server to open Roblox's own window (no price in our text; theirs shows it).
	    The sheet has no box: one soft shade with no edge on screen lies behind it (a tall band whose sides fade out,
	    PlusShade), and the lobby's own text steps aside while it is open (LobbyController.setCover("Plus")).
	  * A member sees "PLUS MEMBER" in the button's place.
	  * The member perk, cosmetic and lobby-only: a small amber "PLUS" word (no pill) floats over a member's character (their
	    own included; on other players it rides above Roblox's name tag) while that character stands in the lobby. It is a BillboardGui this client makes and keeps in
	    PlayerGui (PlusMark_<UserId>), switched off the moment its player is InArena, and off altogether while this
	    client is in the arena or spectating: nothing shows in a round.
	  * "PRIVATE SERVER" above the title when GameState.PrivateServer is true (RoundService).
	  * Gamepad: the button is in the lobby row's selection order (SETTINGS, HOW TO PLAY, ROBLOX PLUS). Opening the
	    panel with a pad puts the selection on CLOSE and keeps it inside the panel; B closes it; closing hands the
	    selection back to the button.
	  * Small screens: the panel widens on a short screen and shrinks as a whole (UIScale "Fit") until it is inside
	    the Lobby root, so SUBSCRIBE and CLOSE are never off a phone's screen. Its height comes from the text's own
	    measure (TextService), not from AutomaticSize: on a short screen AutomaticSize stopped at the room the parent
	    had and cut the last lines of the text.
	If the Lobby screen or the remote is missing, the part that needs it does not run.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Input = require(Shared:WaitForChild("Input"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local C = Theme.Colors

local PlusController = {}
local Controllers: any = nil

local REMOTE_NAME = "PlusSubscribe"
local PRESS_COOLDOWN = 10 -- matches PlusService.PROMPT_COOLDOWN
local MARK_PREFIX = "PlusMark_"
-- Studs above the head's centre. Another player's head carries Roblox's own name tag at about 2 studs (lobby only:
-- PlayerService), so their mark rides above it; your own character has no name tag and wears the mark lower.
local MARK_OFFSET_OWN = Vector3.new(0, 2.05, 0)
local MARK_OFFSET_OTHER = Vector3.new(0, 3.2, 0)
local MARK_MAX_DISTANCE = 60 -- past this the name tag (a fixed size on screen) would reach the mark
local CLOSE_ACTION = "PlusClose"
local PANEL_WIDTH = 360
local PANEL_WIDTH_SHORT = 560 -- on a short (phone) screen: fewer lines, so the panel stays clear of the status line
local PANEL_PAD_X, PANEL_PAD_TOP, PANEL_PAD_BOTTOM, PANEL_GAP = 16, 14, 16, 10
local TITLE_HEIGHT = 22
-- a finger needs 44 px (QuietUI.bindButton grows the buttons to it on a touch screen)
local ACTIONS_HEIGHT = if UserInputService.TouchEnabled then 44 else 34
-- The one soft shade behind the sheet: a band taller than the screen (no top or bottom edge), its sides faded out.
local SHADE_TRANSPARENCY, SHADE_FEATHER, SHADE_BLEED = 0.45, 120, 300

local PANEL_TEXT = table.concat({
	"Roblox Plus is Roblox's own membership. It is optional, and it changes nothing about how a round plays: "
		.. "no weapons, no supplies, no head start.",
	"In this game a member gets one thing: a small PLUS tag over their character in the lobby.",
	"SUBSCRIBE opens Roblox's own window, which has the details. If you subscribe from here, Roblox pays this "
		.. "game's creator a bonus. Not an adult? Ask a parent or guardian first.",
}, "\n\n")

local lobby: ScreenGui? = nil
local R: { [string]: any } = {}
local offer = false
local panelOpen = false
local lastPress = -math.huge
local ROUND_NEAR = 12 -- seconds before the pick in which the button is not offered (PlusService refuses under 10)
local nearShown = false -- roundNear() as the button last saw it

---------------------------------------------------------------------------------------------------------------------
-- The member perk: a small PLUS tag over a member's character, in the lobby only

local marks: { [Player]: BillboardGui } = {}

local function buildMark(other: Player): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = MARK_PREFIX .. tostring(other.UserId)
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Active = false
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = MARK_MAX_DISTANCE
	gui.StudsOffsetWorldSpace = if other == player then MARK_OFFSET_OWN else MARK_OFFSET_OTHER
	-- studs plus a few pixels: it shrinks with distance like the character, and stays readable a little longer
	gui.Size = UDim2.new(1.5, 14, 0.42, 6)
	-- Quiet: the word alone in amber with the dark stroke, no pill behind it ("Pill" stays as its clear holder)
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundTransparency = 1
	pill.BorderSizePixel = 0
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(0.86, 0.8)
	text.FontFace = Theme.Fonts.SemiBold or Theme.Fonts.Heading or Theme.Fonts.Body
	text.TextScaled = true
	text.TextColor3 = C.Sun
	text.Text = "PLUS"
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Shadow"
	stroke.Color = C.Shade
	stroke.Transparency = 0.3 -- a little stronger than the screen's text: it stands over a bright plaza and sky
	stroke.Thickness = 1.5
	stroke.Parent = text
	text.Parent = pill
	pill.Parent = gui
	return gui
end

local function refreshMark(other: Player)
	local gui = marks[other]
	local character = other.Character
	local head = character and character:FindFirstChild("Head")
	local show = other.Parent == Players
		and other:GetAttribute("PlusMember") == true
		and other:GetAttribute("InArena") ~= true
		and not ClientState.inArena
		and ClientState.spectating == nil
		and head ~= nil and head:IsA("BasePart")
	if not show then
		if gui then
			gui.Enabled = false
			gui.Adornee = nil
		end
		return
	end
	if not gui then
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return
		end
		gui = buildMark(other)
		marks[other] = gui
		gui.Parent = playerGui
	end
	gui.Adornee = head :: BasePart
	gui.Enabled = true
end

local function refreshMarks()
	for _, other in ipairs(Players:GetPlayers()) do
		refreshMark(other)
	end
end

local function watchPlayer(other: Player)
	other:GetAttributeChangedSignal("PlusMember"):Connect(function()
		refreshMark(other)
	end)
	other:GetAttributeChangedSignal("InArena"):Connect(function()
		refreshMark(other)
	end)
	other.CharacterAdded:Connect(function(character)
		refreshMark(other)
		-- the head arrives a moment after the character
		if character:WaitForChild("Head", 10) and other.Character == character then
			refreshMark(other)
		end
	end)
	other.CharacterRemoving:Connect(function()
		local gui = marks[other]
		if gui then
			gui.Enabled = false
			gui.Adornee = nil
		end
	end)
	refreshMark(other)
end

local function forgetPlayer(other: Player)
	local gui = marks[other]
	marks[other] = nil
	if gui then
		gui:Destroy()
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Lobby parts

local function newLabel(name: string, text: string, fontKey: string, size: number, color: Color3): TextLabel
	return QuietUI.label({ Name = name, Text = text, Font = fontKey, TextSize = size, TextColor3 = color })
end

-- A plain Quiet text button (no box): brighter text and a thin underline on hover and on a gamepad's focus.
local function newButton(name: string, text: string, quiet: boolean?): TextButton
	return QuietUI.button({ Name = name, Text = text, Quiet = quiet == true })
end

-- the lobby's text steps aside while the sheet is open (a sheet with no box cannot lie over other text)
local function cover(on: boolean)
	local lobbyController = Controllers and Controllers.LobbyController
	if lobbyController and lobbyController.setCover then
		pcall(lobbyController.setCover, "Plus", on)
	end
end

-- The soft shade behind the open sheet: as wide as the sheet as it is drawn (its Fit scale included) plus a fade on
-- each side, and taller than the screen, so it shows no edge.
local function placeShade()
	local shade, fade, panel, fit = R.shade, R.shadeFade, R.panel, R.fit
	if not shade or not fade or not panel or not fit then
		return
	end
	local width = math.floor(panel.Size.X.Offset * (if fit.Scale > 0 then fit.Scale else 1) + 2 * SHADE_FEATHER + 0.5)
	if width <= 2 * SHADE_FEATHER then
		return
	end
	if R.shadeWidth ~= width then
		R.shadeWidth = width -- (the gradient is set here the first time too: until then the band would be solid)
		shade.Size = UDim2.new(0, width, 1, 2 * SHADE_BLEED)
		local f = SHADE_FEATHER / width
		local k = NumberSequenceKeypoint.new
		fade.Transparency = NumberSequence.new({
			k(0, 1), k(f * 0.4, 0.7), k(f * 0.75, 0.2), k(f, 0),
			k(1 - f, 0), k(1 - f * 0.75, 0.2), k(1 - f * 0.4, 0.7), k(1, 1),
		})
	end
end

-- The body text's height at a panel width, measured with the label's own font (the call can wait a moment, so it is
-- made from the lobby loop only and the answer is kept).
local bodyHeights: { [number]: number } = {}
local function measureBody(width: number): number?
	local body = R.body
	if not body then
		return nil
	end
	local key = math.floor(width + 0.5)
	if bodyHeights[key] then
		return bodyHeights[key]
	end
	local ok, bounds = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = body.Text
		params.Font = body.FontFace
		params.Size = body.TextSize
		params.Width = key - 2 * PANEL_PAD_X
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok and typeof(bounds) == "Vector2" and bounds.Y > 0 then
		bodyHeights[key] = math.ceil(bounds.Y * body.LineHeight) + 4
		return bodyHeights[key]
	end
	return nil
end

-- The panel as a whole fits inside the Lobby root: wider on a short (phone) screen, so the text needs fewer lines,
-- then scaled down until SUBSCRIBE and CLOSE are on the screen. Works in the root's own design pixels.
-- mayWait: the caller can wait for the text measure (the lobby loop); otherwise only a kept measure is used.
local function fitPanel(mayWait: boolean?)
	local panel, root, fit, body = R.panel, R.root, R.fit, R.body
	if not panel or not root or not fit or not body then
		return
	end
	local rootScale = root:FindFirstChild("Scale")
	local s = if rootScale and rootScale:IsA("UIScale") and rootScale.Scale > 0 then rootScale.Scale else 1
	local safePad = root:FindFirstChild("SafePad")
	local pad = if safePad and safePad:IsA("UIPadding") then safePad.PaddingTop.Offset else 0
	local availW = root.AbsoluteSize.X / s - 2 * pad
	local availH = root.AbsoluteSize.Y / s - 2 * pad
	if availW < 50 or availH < 50 then
		return
	end
	local width = math.floor(if availH < 400 then math.clamp(availW - 8, 280, PANEL_WIDTH_SHORT) else math.min(PANEL_WIDTH, availW - 8))
	local bodyHeight = bodyHeights[width] or (if mayWait then measureBody(width) else nil)
	if not bodyHeight then
		return -- not measured yet: the panel stays as it is until the lobby loop has the measure
	end
	local natural = PANEL_PAD_TOP + TITLE_HEIGHT + PANEL_GAP + bodyHeight + PANEL_GAP + ACTIONS_HEIGHT + PANEL_PAD_BOTTOM
	if body.AutomaticSize ~= Enum.AutomaticSize.None or body.Size.Y.Offset ~= bodyHeight then
		body.AutomaticSize = Enum.AutomaticSize.None
		body.Size = UDim2.new(1, 0, 0, bodyHeight)
	end
	if panel.AutomaticSize ~= Enum.AutomaticSize.None or panel.Size.X.Offset ~= width or panel.Size.Y.Offset ~= natural then
		panel.AutomaticSize = Enum.AutomaticSize.None
		panel.Size = UDim2.fromOffset(width, natural)
	end
	local target = math.clamp(math.min((availH - 4) / natural, (availW - 4) / width), 0.5, 1)
	if math.abs(target - fit.Scale) > 0.005 then
		fit.Scale = target
	end
	placeShade()
end

local function padActive(): boolean
	return Input.isGamepad() or GuiService.SelectedObject ~= nil
end

local setPanel: (open: boolean) -> ()

local function bindClose(on: boolean)
	if on then
		Input.bind(CLOSE_ACTION, function(state)
			if state == Enum.UserInputState.Begin then
				setPanel(false)
			end
			return Enum.ContextActionResult.Sink
		end, { keys = { Enum.KeyCode.ButtonB }, priority = 2100 })
	else
		Input.unbind(CLOSE_ACTION)
	end
end

setPanel = function(open: boolean)
	local panel = R.panel
	if not panel or open == panelOpen then
		return
	end
	panelOpen = open
	fitPanel(false)
	placeShade() -- (also when fitPanel has no text measure yet)
	-- the lobby's own text (title, status lines, buttons, HOW TO PLAY, the list) steps aside first, so on closing the
	-- ROBLOX PLUS button is back on screen before the selection returns to it
	cover(open)
	panel.Visible = open
	local shade = R.shade
	if shade then
		if open then
			shade.Visible = true
			shade.BackgroundTransparency = 1
			QuietUI.tween(shade, Theme.Tween.Normal, { BackgroundTransparency = SHADE_TRANSPARENCY })
		else
			shade.Visible = false
		end
	end
	bindClose(open)
	if open then
		if padActive() and R.close then
			GuiService.SelectedObject = R.close -- the safe choice first; SUBSCRIBE is one step to the left
		end
	else
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(panel) then
			local button = R.button
			GuiService.SelectedObject = if button and button.Visible and lobby and lobby.Enabled then button else nil
		end
	end
end

-- The Countdown is on, or the lobby's players are picked within ROUND_NEAR seconds (the Intermission's end, or a lone
-- player's practice countdown): no button and no panel now. Roblox's window, once open, cannot be closed from the
-- game and would sit over the launch and the round. PlusService refuses a press under the same test (10 s).
local function roundNear(): boolean
	local gameState = ReplicatedStorage:FindFirstChild("GameState")
	if not gameState then
		return false
	end
	local phase = gameState:GetAttribute("Phase")
	if phase == "Countdown" then
		return true
	end
	local t = workspace:GetServerTimeNow()
	if phase == "Intermission" and (tonumber(gameState:GetAttribute("PhaseEndsAt")) or 0) - t < ROUND_NEAR then
		return true
	end
	if phase == "Intermission" or phase == "Lobby" then
		local soloAt = tonumber(gameState:GetAttribute("SoloStartAt")) or 0
		if soloAt > 0 and soloAt - t < ROUND_NEAR then
			return true
		end
	end
	return false
end

local function refresh()
	local member = player:GetAttribute("PlusMember") == true
	nearShown = roundNear()
	if R.button then
		R.button.Visible = offer and not member and not nearShown
		if not R.button.Visible and GuiService.SelectedObject == R.button then
			-- a pad's selection does not stay on a button that has gone: HOW TO PLAY, its neighbour, takes it
			local neighbour = R.button.Parent and R.button.Parent:FindFirstChild("HowTo")
			GuiService.SelectedObject = if neighbour and neighbour:IsA("GuiObject") and neighbour.Visible then neighbour else nil
		end
	end
	if R.memberTag then
		R.memberTag.Visible = member
	end
	if panelOpen and (member or not offer) then
		setPanel(false)
	end
end

-- a headline, the Roll Call, a card or the menu has the screen: the panel goes rather than sit under or over it
local function mustYield(): boolean
	if not lobby or not lobby.Enabled or ClientState.menuOpen or ClientState.inArena or ClientState.spectating ~= nil then
		return true
	end
	if roundNear() then
		return true
	end
	local notifications = Controllers and Controllers.NotificationController
	if notifications and notifications.isBannerUp then
		local ok, headline, roll = pcall(notifications.isBannerUp)
		if ok and (headline == true or roll == true) then
			return true
		end
	end
	return false
end

local function buildPrivateLabel(brand: Instance)
	local GameState = ReplicatedStorage:FindFirstChild("GameState")
	if not GameState then
		return
	end
	-- a small dim line over the title (QuietUI.label carries the dark stroke "Shadow")
	local label = newLabel("PrivateServer", "PRIVATE SERVER", "SemiBold", Theme.TextSize.Small, C.Ink2)
	label.LayoutOrder = 0
	label.Size = UDim2.new(1, 0, 0, 18)
	local function apply()
		label.Visible = GameState:GetAttribute("PrivateServer") == true
	end
	GameState:GetAttributeChangedSignal("PrivateServer"):Connect(apply)
	apply()
	label.Parent = brand
end

local function buildPanel(root: Instance, remote: RemoteEvent)
	local panel = Instance.new("Frame")
	panel.Name = "PlusPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Active = true -- clicks on it do not reach the world
	panel.Visible = false
	panel.ZIndex = 5
	panel.BackgroundTransparency = 1 -- Quiet: no box (the shade behind it is PlusShade)
	panel.BorderSizePixel = 0

	-- the one soft shade, behind the sheet and every other part of the lobby
	local shade = Instance.new("Frame")
	shade.Name = "PlusShade"
	shade.AnchorPoint = Vector2.new(0.5, 0.5)
	shade.Position = UDim2.fromScale(0.5, 0.5)
	shade.Size = UDim2.new(0, PANEL_WIDTH + 2 * SHADE_FEATHER, 1, 2 * SHADE_BLEED)
	shade.BackgroundColor3 = C.Shade
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Active = true -- (clicks beside the sheet, on the shade, do not reach the world either)
	shade.ZIndex = 4
	shade.Visible = false
	local shadeFade = Instance.new("UIGradient")
	shadeFade.Name = "Fade"
	shadeFade.Parent = shade
	shade.Parent = root
	R.shade = shade
	R.shadeFade = shadeFade

	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = panel
	R.fit = fit
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, PANEL_PAD_X), UDim.new(0, PANEL_PAD_X)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, PANEL_PAD_TOP), UDim.new(0, PANEL_PAD_BOTTOM)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, PANEL_GAP)
	layout.Parent = panel

	local title = newLabel("Title", "ROBLOX PLUS", "Heading", Theme.TextSize.Heading, C.Text)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
	title.ZIndex = 5
	title.Parent = panel

	local body = newLabel("Body", PANEL_TEXT, "Body", 15, C.Text)
	body.LayoutOrder = 2
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LineHeight = 1.1
	body.ZIndex = 5
	body.Parent = panel
	R.body = body

	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.LayoutOrder = 3
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, ACTIONS_HEIGHT)
	actions.ZIndex = 5
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 28) -- (plain text buttons: the air between them is what tells them apart)
	row.Parent = actions
	actions.Parent = panel

	-- SUBSCRIBE in ink, CLOSE quieter; both plain text with the hover and focus underline
	local subscribe = newButton("Subscribe", "SUBSCRIBE")
	subscribe.LayoutOrder = 1
	subscribe.ZIndex = 5
	subscribe.Parent = actions
	QuietUI.bindButton(subscribe)
	local close = newButton("Close", "CLOSE", true)
	close.LayoutOrder = 2
	close.ZIndex = 5
	close.Parent = actions
	QuietUI.bindButton(close)

	subscribe.Activated:Connect(function()
		local now = os.clock()
		if not offer or now - lastPress < PRESS_COOLDOWN then
			setPanel(false)
			return
		end
		lastPress = now
		setPanel(false) -- Roblox's window takes over from here
		remote:FireServer("subscribe")
	end)
	close.Activated:Connect(function()
		setPanel(false)
	end)
	-- a pad's selection stays on these two while the panel is open
	subscribe.NextSelectionLeft, subscribe.NextSelectionUp, subscribe.NextSelectionDown = subscribe, subscribe, subscribe
	subscribe.NextSelectionRight = close
	close.NextSelectionRight, close.NextSelectionUp, close.NextSelectionDown = close, close, close
	close.NextSelectionLeft = subscribe

	R.close = close
	R.panel = panel
	panel.Parent = root
end

local function buildButton(buttons: Instance)
	-- quieter than SETTINGS and HOW TO PLAY (the mock-up: Medium, 70%): dimmer text at rest, no backing, no sound
	local button = newButton("Plus", "ROBLOX PLUS", true)
	button.FontFace = Theme.Fonts.Medium
	button.LayoutOrder = 3
	button.Visible = false
	button.Parent = buttons
	QuietUI.bindButton(button, { quiet = true })
	button.Activated:Connect(function()
		if panelOpen then
			setPanel(false)
		elseif offer and not mustYield() then
			setPanel(true)
		end
	end)
	R.button = button

	-- a member's word in the button's place: amber like the PLUS tag in the list of who is here, held readable over
	-- the bright plaza by the dark stroke (QuietUI.label), no backing
	local tag = newLabel("PlusMember", "PLUS MEMBER", "SemiBold", Theme.TextSize.Label, C.Sun)
	tag.LayoutOrder = 4
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.Size = UDim2.fromOffset(0, 34)
	tag.Visible = false
	tag.TextXAlignment = Enum.TextXAlignment.Center
	R.memberTag = tag
	tag.Parent = buttons
end

function PlusController.Init(registry)
	Controllers = registry
end

function PlusController.Start()
	for _, other in ipairs(Players:GetPlayers()) do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(forgetPlayer)
	ClientState.lifeChanged:Connect(refreshMarks)
	ClientState.spectateChanged:Connect(refreshMarks)
	-- A lobby player's Head can stream in long after their character did: they came back to the lobby while this
	-- client was in the arena or spectating there, and nothing above fires when this client returns and the lobby
	-- loads (the round's winner saw no mark on the others, 18 Nov). So in the lobby the marks are looked at once a second.
	task.spawn(function()
		while true do
			task.wait(1)
			if not ClientState.inArena and ClientState.spectating == nil then
				refreshMarks()
			end
		end
	end)

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("Lobby", 30)
	local root = gui and gui:WaitForChild("Root", 10)
	local brand = root and root:WaitForChild("Brand", 10)
	local buttons = brand and brand:WaitForChild("Buttons", 10)
	if not (gui and gui:IsA("ScreenGui") and root and brand and buttons) then
		return
	end
	lobby = gui
	R.root = root
	R.howTo = root:FindFirstChild("HowTo")

	buildPrivateLabel(brand)
	buildButton(buttons)
	player:GetAttributeChangedSignal("PlusMember"):Connect(refresh)
	refresh()

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local remote = remotes and remotes:WaitForChild(REMOTE_NAME, 30)
	if not remote or not remote:IsA("RemoteEvent") then
		return -- no PlusService on this server: no button, the rest stands
	end
	buildPanel(root, remote)
	remote.OnClientEvent:Connect(function(what: any, value: any)
		if what == "state" then
			offer = value == true
			refresh()
		end
	end)
	remote:FireServer("state")

	while true do
		task.wait(0.25)
		if panelOpen and mustYield() then
			setPanel(false)
		end
		if roundNear() ~= nearShown then
			refresh() -- the button goes for the last seconds before a round and comes back after the launch
		end
		if gui.Enabled then
			fitPanel(true) -- kept fitted while the lobby shows, so it opens at its final size
		end
	end
end

return PlusController
