--[[
	Hud - the Proximity Voice UI (VoiceController builds and drives it). Built at runtime from Theme tokens, the way
	Shared.Input builds its touch buttons, so nothing has to be added to StarterGui. (Move it into
	ServerStorage.WorldGen.UIBuilder later if you prefer edit-time UI; the instance names below are the contract.)
	  ScreenGui "Voice" (DisplayOrder 13): Root > Stack = the mic chip (who can hear you, a light while you talk) over
	    who's talking near you (up to Config.Voice.MaxTalkers rows, 3 on phones). Left middle on desktop, top right on
	    touch. Shown in the arena and while spectating; the lobby has the card instead.
	  Frame "VoiceCard": the lobby card. The mode (PROXIMITY VOICE, ON / OFF), what it means in one line, PLAYERS ›, and
	    VOICE-ONLY SERVER › / LEAVE when phase 2 is on. LobbyController.mountCard puts it in the lobby's left column.
	  ScreenGui "VoicePanel" (DisplayOrder 41, over the Menu): your voice on / off, every other player with voice on
	    this server with MUTE and BLOCK (a player you blocked on Roblox reads BLOCKED), and where to report.
	    B / Backspace / the dimmed backdrop close it.
	Text is never below 13 px (Theme).
	API: build(handlers)  applyLayout()  setStackVisible(on)  setChip(text, talking, dim)  setTalkers(rows)  animate(dt)
	     getCard()  setCard(state)  openPanel()  closePanel()  isPanelOpen()  setPanel(state)
	handlers: onToggle(), onOpenPanel(), onClosePanel(), onMute(player, muted), onBlock(player), onServer("Join" | "Leave")
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Input = require(Shared:WaitForChild("Input"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local player = Players.LocalPlayer
local C = Theme.Colors
local VoiceCfg = Config.Voice or {}
local ROW_POOL = math.clamp(math.floor(tonumber(VoiceCfg.MaxTalkers) or 4), 1, 6)

local Hud = {}

local handlers: { [string]: any } = {}
local R: { [string]: any } = {}
local rows: { any } = {} -- talker rows, pooled
local rowLevels: { number } = {}
local panelRows: { [Player]: any } = {}
local panelOpen = false
local maxRows = ROW_POOL
local dotLit = false
local wobble = 0

local function call(name: string, ...: any)
	local fn = handlers[name]
	if type(fn) == "function" then
		task.spawn(fn, ...)
	end
end

------------------------------------------------------------------------------------------------
-- Construction helpers (the same shapes as UIBuilder's)
------------------------------------------------------------------------------------------------
local function new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function frame(name: string, props: { [string]: any }?, children: { Instance }?): any
	local p = props or {}
	p.Name = name
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	return new("Frame", p, children)
end

local function label(name: string, text: string, fontKey: string, size: number, props: { [string]: any }?): any
	local p = props or {}
	p.Name = name
	p.Text = text
	p.FontFace = Theme.Fonts[fontKey] or Theme.Fonts.Body
	p.TextSize = math.max(Theme.TextSize.Small, size)
	if p.TextColor3 == nil then
		p.TextColor3 = C.Text
	end
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	if p.TextXAlignment == nil then
		p.TextXAlignment = Enum.TextXAlignment.Left
	end
	return new("TextLabel", p)
end

local function button(name: string, text: string, fontKey: string, size: number, props: { [string]: any }?, children: { Instance }?): any
	local p = props or {}
	p.Name = name
	p.Text = text
	p.FontFace = Theme.Fonts[fontKey] or Theme.Fonts.Heading
	p.TextSize = math.max(Theme.TextSize.Small, size)
	if p.TextColor3 == nil then
		p.TextColor3 = C.Text
	end
	if p.BackgroundColor3 == nil then
		p.BackgroundColor3 = C.Panel
	end
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = Theme.Transparency.Panel
	end
	p.BorderSizePixel = 0
	p.AutoButtonColor = false
	return new("TextButton", p, children)
end

local function corner(radius: UDim?): UICorner
	return new("UICorner", { CornerRadius = radius or Theme.Corner })
end

local function stroke(transparency: number?): UIStroke
	return new("UIStroke", {
		Color = C.Stroke,
		Transparency = transparency or Theme.Transparency.Stroke,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(left: number, right: number?, top: number?, bottom: number?): UIPadding
	return new("UIPadding", {
		Name = "Pad",
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right or left),
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
	})
end

local function list(direction: Enum.FillDirection, gap: number?, h: Enum.HorizontalAlignment?, v: Enum.VerticalAlignment?): UIListLayout
	return new("UIListLayout", {
		Name = "Layout",
		FillDirection = direction,
		Padding = UDim.new(0, gap or 0),
		HorizontalAlignment = h or Enum.HorizontalAlignment.Left,
		VerticalAlignment = v or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- A ScreenGui with Root > Scale + SafePad, kept fitted by Theme.bindRoot like every other screen.
local function screen(name: string, displayOrder: number): (ScreenGui, Frame)
	local playerGui = player:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = true
	local root = frame("Root", { Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	new("UIScale", { Name = "Scale", Scale = 1, Parent = root })
	local pad = padding(16, 16, 16, 16)
	pad.Name = "SafePad"
	pad.Parent = root
	root.Parent = gui
	gui.Parent = playerGui
	Theme.bindRoot(gui)
	return gui, root
end

local function hover(b: GuiButton, normal: number, over: number)
	local hovered, selected = false, false
	local function apply()
		Theme.tween(b, Theme.Tween.Fast, { BackgroundTransparency = if hovered or selected then over else normal })
	end
	b.MouseEnter:Connect(function()
		hovered = true
		apply()
		if not Input.isTouch() then
			Sfx.play("UIHover")
		end
	end)
	b.MouseLeave:Connect(function()
		hovered = false
		apply()
	end)
	b.SelectionGained:Connect(function()
		selected = true
		apply()
	end)
	b.SelectionLost:Connect(function()
		selected = false
		apply()
	end)
end

local function click(b: GuiButton, name: string, ...: any)
	local args = table.pack(...)
	b.Activated:Connect(function()
		Sfx.play("UIClick")
		call(name, table.unpack(args, 1, args.n))
	end)
end

local function styleToggle(b: TextButton, on: boolean)
	b.Text = if on then "ON" else "OFF"
	b.BackgroundColor3 = if on then C.Accent else C.PanelLight
	b.BackgroundTransparency = if on then 0.05 else 0.4
	b.TextColor3 = if on then C.TextDark else C.Text
end

------------------------------------------------------------------------------------------------
-- The stack: mic chip + who's talking
------------------------------------------------------------------------------------------------
local function buildStack()
	local _, root = screen("Voice", 13)
	local stack = frame("Stack", {
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = root,
	})
	local layout = list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	layout.Parent = stack
	R.stack, R.stackLayout = stack, layout

	local chip = frame("Chip", {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = Theme.Transparency.Panel,
		LayoutOrder = 0,
		Parent = stack,
	}, {
		corner(Theme.CornerPill),
		stroke(),
		padding(10, 12, 0, 0),
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	R.dot = frame("Dot", { Size = UDim2.fromOffset(8, 8), BackgroundColor3 = C.Text, BackgroundTransparency = 0.7, LayoutOrder = 1, Parent = chip }, {
		corner(Theme.CornerPill),
	})
	R.chipLabel = label("Label", "VOICE", "Heading", 13, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = chip })
	R.chip = chip

	for i = 1, ROW_POOL do
		local row = frame("Talker" .. i, {
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.45,
			LayoutOrder = i,
			Visible = false,
			Parent = stack,
		}, {
			corner(Theme.CornerPill),
			padding(10, 12, 0, 0),
			list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
			new("UISizeConstraint", { MaxSize = Vector2.new(230, 26) }),
		})
		local bars = frame("Bars", { Size = UDim2.fromOffset(13, 12), LayoutOrder = 1, Parent = row })
		for b = 1, 3 do
			frame("Bar" .. b, {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, (b - 1) * 5, 1, 0),
				Size = UDim2.new(0, 3, 0.3, 0),
				BackgroundColor3 = C.Text,
				BackgroundTransparency = 0.1,
				Parent = bars,
			}, { corner(Theme.CornerPill) })
		end
		label("Who", "", "Body", 14, {
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 2,
			Parent = row,
		})
		label("Tag", "", "Heading", 13, {
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			TextColor3 = C.TextDim,
			LayoutOrder = 3,
			Visible = false,
			Parent = row,
		})
		rows[i] = row
		rowLevels[i] = 0
	end
end

------------------------------------------------------------------------------------------------
-- The lobby card
------------------------------------------------------------------------------------------------
-- Three rows: the header with the ON / OFF toggle; what the mode means (two lines); the links (VOICE-ONLY SERVER › at
-- the left, PLAYERS › at the right). Without links (voice not on this account) the card is shorter.
local CARD_TALL, CARD_SHORT = 96, 70

local function buildCard()
	local card = frame("VoiceCard", {
		Size = UDim2.new(1, 0, 0, CARD_SHORT),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = Theme.Transparency.Panel,
	}, { corner(Theme.Corner), stroke() })
	R.cardHeader = label("Header", "PROXIMITY VOICE", "Heading", 13, {
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -104, 0, 15),
		TextColor3 = C.TextDim,
		Parent = card,
	})
	R.cardText = label("State", "", "Body", 13, {
		Position = UDim2.fromOffset(14, 31),
		Size = UDim2.new(1, -28, 0, 34),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	R.cardToggle = button("Toggle", "ON", "Heading", 13, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(64, 24),
		Visible = false,
		Parent = card,
	}, { corner(Theme.CornerPill), stroke(0.7) })
	R.cardPlayers = button("Players", "PLAYERS ›", "Heading", 13, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -8),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		TextColor3 = C.AccentSoft,
		Visible = false,
		Parent = card,
	})
	R.cardServer = button("Server", "VOICE-ONLY SERVER ›", "Heading", 13, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -8),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		TextColor3 = C.AccentSoft,
		Visible = false,
		Parent = card,
	})
	click(R.cardToggle, "onToggle")
	click(R.cardPlayers, "onOpenPanel")
	R.cardServer.Activated:Connect(function()
		Sfx.play("UIClick")
		call("onServer", R.cardServer:GetAttribute("Action") or "Join")
	end)
	R.card = card
end

------------------------------------------------------------------------------------------------
-- The players panel
------------------------------------------------------------------------------------------------
local function buildPanel()
	local gui, root = screen("VoicePanel", 41)
	R.panelGui = gui
	R.dim = button("Dim", "", "Body", 13, {
		Position = UDim2.fromOffset(-240, -240),
		Size = UDim2.new(1, 480, 1, 480),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Modal = true, -- frees the mouse in first person, like the Menu
		Selectable = false,
		Visible = false,
		ZIndex = 1,
		Parent = gui,
	})
	local panel = new("CanvasGroup", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = root,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(440, 480) }) })
	frame("Bg", {
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		Active = true,
		ZIndex = 1,
		Parent = panel,
	}, { corner(Theme.CornerLarge), stroke(0.84) })
	label("Title", "VOICE", "Heading", 18, { Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -80, 0, 50), ZIndex = 2, Parent = panel })
	R.close = button("Close", "×", "Body", 24, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 5),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = panel,
	}, { corner(Theme.CornerPill) })
	frame("Divider", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.9, ZIndex = 2, Parent = panel })

	label("YouHeader", "YOU", "Heading", 13, { Position = UDim2.fromOffset(20, 62), Size = UDim2.new(1, -130, 0, 15), TextColor3 = C.TextDim, ZIndex = 2, Parent = panel })
	R.youText = label("YouText", "", "Body", 14, {
		Position = UDim2.fromOffset(20, 80),
		Size = UDim2.new(1, -130, 0, 38),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 2,
		Parent = panel,
	})
	R.youToggle = button("YouToggle", "ON", "Heading", 13, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 64),
		Size = UDim2.fromOffset(76, 30),
		ZIndex = 2,
		Parent = panel,
	}, { corner(Theme.CornerPill), stroke(0.7) })
	frame("Divider2", { Position = UDim2.fromOffset(20, 128), Size = UDim2.new(1, -40, 0, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.9, ZIndex = 2, Parent = panel })

	R.listHeader = label("ListHeader", "PLAYERS WITH VOICE", "Heading", 13, { Position = UDim2.fromOffset(20, 138), Size = UDim2.new(1, -40, 0, 15), TextColor3 = C.TextDim, ZIndex = 2, Parent = panel })
	R.list = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 158),
		Size = UDim2.new(1, 0, 1, -158 - 72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Text,
		ScrollBarImageTransparency = 0.7,
		Selectable = false,
		ZIndex = 2,
		Parent = panel,
	}, {
		padding(20, 20, 4, 8),
		list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	R.empty = label("Empty", "Nobody else here has voice right now.", "Body", 14, {
		Position = UDim2.fromOffset(20, 164),
		Size = UDim2.new(1, -40, 0, 20),
		TextColor3 = C.TextDim,
		Visible = false,
		ZIndex = 2,
		Parent = panel,
	})
	frame("Divider3", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -70), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.9, ZIndex = 2, Parent = panel })
	label("Footer", "Mutes last while you're on this server. Roblox only connects voice between players of similar ages. "
		.. "To report someone, open Roblox's menu (Esc) › Report.", "Body", 13, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -10),
		Size = UDim2.new(1, -40, 0, 54),
		TextWrapped = true,
		TextColor3 = C.TextDim,
		ZIndex = 2,
		Parent = panel,
	})
	R.panel = panel

	click(R.youToggle, "onToggle")
	click(R.close, "onClosePanel")
	R.dim.Activated:Connect(function()
		call("onClosePanel")
	end)
	R.close.MouseEnter:Connect(function()
		Theme.tween(R.close, Theme.Tween.Fast, { BackgroundTransparency = 0.5 })
	end)
	R.close.MouseLeave:Connect(function()
		Theme.tween(R.close, Theme.Tween.Fast, { BackgroundTransparency = 1 })
	end)
end

local function panelRow(p: Player): any
	local row = frame("P" .. p.UserId, {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.7,
		ZIndex = 2,
	}, { corner(Theme.Corner) })
	frame("Talking", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = C.Text,
		BackgroundTransparency = 0.85,
		ZIndex = 3,
		Parent = row,
	}, { corner(Theme.CornerPill) })
	label("Who", p.DisplayName, "BodyBold", 15, {
		Position = UDim2.fromOffset(24, 5),
		Size = UDim2.new(1, -196, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = row,
	})
	label("User", "@" .. p.Name, "Body", 13, {
		Position = UDim2.fromOffset(24, 25),
		Size = UDim2.new(1, -196, 0, 16),
		TextColor3 = C.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = row,
	})
	local mute = button("Mute", "MUTE", "Heading", 13, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -86, 0.5, 0),
		Size = UDim2.fromOffset(84, 30),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.4,
		ZIndex = 3,
		Parent = row,
	}, { corner(Theme.CornerPill), stroke(0.8) })
	local block = button("Block", "BLOCK", "Heading", 13, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(72, 30),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.6,
		ZIndex = 3,
		Parent = row,
	}, { corner(Theme.CornerPill), stroke(0.85) })
	mute.Activated:Connect(function()
		if row:GetAttribute("Blocked") == true then
			return -- blocked on Roblox: silent anyway (unblock them in Roblox's menu)
		end
		Sfx.play("UIClick")
		call("onMute", p, row:GetAttribute("Muted") ~= true)
	end)
	block.Activated:Connect(function()
		if row:GetAttribute("Blocked") == true then
			return
		end
		Sfx.play("UIClick")
		call("onBlock", p)
	end)
	hover(mute, 0.4, 0.15)
	hover(block, 0.6, 0.3)
	return row
end

------------------------------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------------------------------
function Hud.build(h: { [string]: any })
	handlers = h or {}
	buildStack()
	buildCard()
	buildPanel()
	Hud.applyLayout()
end

-- Desktop: left middle (clear of the vitals at the bottom left and the kill feed at the top right).
-- Touch: top right, left of the DROP button's column (the vitals and kill feed sit at the top left there).
function Hud.applyLayout()
	if not R.stack then
		return
	end
	local touch = UserInputService.TouchEnabled
	local phone = touch and Theme.isSmallScreen()
	maxRows = if phone then math.min(3, ROW_POOL) else ROW_POOL
	if touch then
		R.stack.AnchorPoint = Vector2.new(1, 0)
		R.stack.Position = UDim2.new(1, -66, 0, 0)
		R.stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	else
		R.stack.AnchorPoint = Vector2.new(0, 0.5)
		R.stack.Position = UDim2.fromScale(0, 0.5)
		R.stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	end
end

function Hud.setStackVisible(on: boolean)
	if R.stack and R.stack.Visible ~= on then
		R.stack.Visible = on
	end
end

function Hud.setChip(text: string, talking: boolean, dim: boolean)
	if not R.chip then
		return
	end
	if R.chipLabel.Text ~= text then
		R.chipLabel.Text = text
	end
	R.chipLabel.TextColor3 = if dim then C.TextDim else C.Text
	if talking ~= dotLit then
		dotLit = talking
		Theme.tween(R.dot, Theme.Tween.Fast, { BackgroundTransparency = if talking then 0 else 0.7 })
	end
end

-- rows: { { name: string, tag: string, level: number } }, loudest first
function Hud.setTalkers(entries: { { [string]: any } })
	for i, row in ipairs(rows) do
		local entry = if i <= maxRows then entries[i] else nil
		if entry then
			local who = row:FindFirstChild("Who")
			local tag = row:FindFirstChild("Tag")
			if who and who.Text ~= entry.name then
				who.Text = entry.name
			end
			if tag then
				tag.Text = entry.tag or ""
				tag.Visible = tag.Text ~= ""
			end
			rowLevels[i] = tonumber(entry.level) or 0
			row.Visible = true
		else
			row.Visible = false
			rowLevels[i] = 0
		end
	end
end

-- The talking bars: a light wobble scaled by each voice's level.
function Hud.animate(dt: number)
	if not (R.stack and R.stack.Visible) then
		return
	end
	wobble += dt * 9
	for i, row in ipairs(rows) do
		if row.Visible then
			local level = math.clamp((rowLevels[i] or 0) * 18, 0.15, 1)
			local bars = row:FindFirstChild("Bars")
			if bars then
				for b = 1, 3 do
					local bar = bars:FindFirstChild("Bar" .. b)
					if bar then
						local k = 0.55 + 0.45 * math.abs(math.sin(wobble + b * 1.7 + i))
						bar.Size = UDim2.new(0, 3, math.clamp(level * k, 0.15, 1), 0)
					end
				end
			end
		end
	end
end

function Hud.getCard(): Frame?
	return R.card
end

-- state: { title, text, toggle: boolean, on: boolean, players: boolean, mutedCount: number, server: "Join" | "Leave" | nil }
function Hud.setCard(state: { [string]: any })
	if not R.card then
		return
	end
	R.cardHeader.Text = state.title or "PROXIMITY VOICE"
	R.cardText.Text = state.text or ""
	R.cardToggle.Visible = state.toggle == true
	if state.toggle then
		styleToggle(R.cardToggle, state.on == true)
	end
	R.cardPlayers.Visible = state.players == true
	local mutedCount = tonumber(state.mutedCount) or 0
	R.cardPlayers.Text = if mutedCount > 0 then string.format("PLAYERS · %d MUTED ›", mutedCount) else "PLAYERS ›"
	local server = state.server
	R.cardServer.Visible = server ~= nil
	if server then
		R.cardServer:SetAttribute("Action", server)
		R.cardServer.Text = if server == "Leave" then "LEAVE VOICE-ONLY SERVER ›" else "VOICE-ONLY SERVER ›"
	end
	-- the links' row only when there is a link to show
	local height = if state.players == true or server ~= nil then CARD_TALL else CARD_SHORT
	if R.card.Size.Y.Offset ~= height then
		R.card.Size = UDim2.new(1, 0, 0, height) -- (LobbyController.mountCard follows the card's height)
	end
end

function Hud.isPanelOpen(): boolean
	return panelOpen
end

function Hud.openPanel()
	if panelOpen or not R.panel then
		return
	end
	panelOpen = true
	R.dim.Visible = true
	R.panel.Visible = true
	R.panel.GroupTransparency = 1
	R.panel.Position = UDim2.new(0.5, 0, 0.5, 14)
	Theme.tween(R.panel, Theme.Tween.Normal, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) })
	Theme.tween(R.dim, Theme.Tween.Normal, { BackgroundTransparency = Theme.Transparency.Dim })
	if Input.isGamepad() then
		GuiService.SelectedObject = if R.youToggle.Visible then R.youToggle else R.close
	end
	Input.bind("VoicePanelBack", function(state)
		if state == Enum.UserInputState.Begin then
			call("onClosePanel")
		end
		return Enum.ContextActionResult.Sink
	end, { keys = { Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace }, priority = 3100 })
	Sfx.play("UIClick")
end

function Hud.closePanel()
	if not panelOpen then
		return
	end
	panelOpen = false
	Input.unbind("VoicePanelBack")
	local t = Theme.tween(R.panel, Theme.Tween.Fast, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 10) })
	Theme.tween(R.dim, Theme.Tween.Fast, { BackgroundTransparency = 1 })
	t.Completed:Once(function()
		if not panelOpen then
			R.panel.Visible = false
			R.dim.Visible = false
		end
	end)
	local selected = GuiService.SelectedObject
	if selected and R.panelGui and selected:IsDescendantOf(R.panelGui) then
		GuiService.SelectedObject = nil
	end
end

-- state: { text: string, toggle: boolean, on: boolean, rows = { { player, muted: boolean, blocked: boolean, talking: boolean } } }
function Hud.setPanel(state: { [string]: any })
	if not R.panel then
		return
	end
	R.youText.Text = state.text or ""
	R.youToggle.Visible = state.toggle == true
	if state.toggle then
		styleToggle(R.youToggle, state.on == true)
	end
	local entries = state.rows or {}
	local seen: { [Player]: boolean } = {}
	for i, entry in ipairs(entries) do
		local p = entry.player
		seen[p] = true
		local row = panelRows[p]
		if not row then
			row = panelRow(p)
			panelRows[p] = row
			row.Parent = R.list
		end
		row.LayoutOrder = i
		row:SetAttribute("Muted", entry.muted == true)
		row:SetAttribute("Blocked", entry.blocked == true)
		local mute = row:FindFirstChild("Mute")
		if mute then
			mute.Text = if entry.blocked then "BLOCKED" elseif entry.muted then "UNMUTE" else "MUTE"
			mute.TextColor3 = if entry.blocked then C.TextDim elseif entry.muted then C.AccentSoft else C.Text
		end
		local block = row:FindFirstChild("Block")
		if block then
			block.Visible = entry.blocked ~= true
		end
		local talking = row:FindFirstChild("Talking")
		if talking then
			talking.BackgroundTransparency = if entry.talking and not entry.muted and not entry.blocked then 0 else 0.85
		end
	end
	for p, row in pairs(panelRows) do
		if not seen[p] then
			row:Destroy()
			panelRows[p] = nil
		end
	end
	R.empty.Visible = #entries == 0
	R.listHeader.Text = if #entries > 0 then string.format("PLAYERS WITH VOICE · %d", #entries) else "PLAYERS WITH VOICE"
end

return Hud
