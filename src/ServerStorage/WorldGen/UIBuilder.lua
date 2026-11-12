--[[
	UIBuilder - edit-time builder for every ScreenGui the UI system owns (in StarterGui).
	Re-runnable: build() replaces HUD, HUDFX, Lobby, Overlay, Menu and Spectate.
	  return require(game.ServerStorage.WorldGen.UIBuilder).build()
	  return require(game.ServerStorage.WorldGen.UIBuilder).preview("HUD")  -- sample content + enabled, for screenshots
	     ("HUD" | "Lobby" | "Death" | "Victory" | "Menu" | "Spectate" | "Countdown" | "RollCall")
	  return require(game.ServerStorage.WorldGen.UIBuilder).build()          -- back to clean + disabled
	Every ScreenGui is Enabled = false at edit time; the client controllers enable them at runtime.
	The instance names below are the controllers' contract (StarterPlayerScripts.Client.Controllers):
	  HUD + HUDFX -> HUDController, Lobby -> LobbyController, Overlay -> NotificationController,
	  Menu -> SettingsController, Spectate -> SpectateController.
	Every ScreenGui has Root (Frame) > Scale (UIScale) [and SafePad (UIPadding)]; Theme.bindRoot keeps it fitted.
	Design size is 1280x720 at scale 1. Text is never below 13 px.
]]
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIBuilder = {}
UIBuilder.Names = { "HUD", "HUDFX", "Lobby", "Overlay", "Menu", "Spectate" }

local Theme: any
local Config: any

-- three short tips (P3: say less), so the control rows from Aim up show without scrolling at 720 px tall
local TIPS = {
	"Last one standing wins. At the horn, rush the Spire for gear, or run for a runner's cache under a pale flag.",
	"Keep hunger and thirst above 55 and your health comes back. Drink from streams and the lake.",
	"From the second morning the border closes in on the Spire. Stay inside it.",
}
-- the goal in one line at the top of HOW TO PLAY (QW6); LobbyController rewrites it from Shared.Lore at runtime
local STEPS = "RISE ON YOUR PLATE  →  TAKE GEAR AT THE SPIRE, OR RUN  →  OUTLAST THE BORDER"

------------------------------------------------------------------------------------------------
-- Construction helpers
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

local function canvas(name: string, props: { [string]: any }?, children: { Instance }?): any
	local p = props or {}
	p.Name = name
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	return new("CanvasGroup", p, children)
end

local function label(name: string, text: string, fontKey: string, size: number, props: { [string]: any }?, children: { Instance }?): any
	local p = props or {}
	p.Name = name
	p.Text = text
	p.FontFace = Theme.Fonts[fontKey] or Theme.Fonts.Body
	p.TextSize = math.max(Theme.TextSize.Small, size)
	if p.TextColor3 == nil then
		p.TextColor3 = Theme.Colors.Text
	end
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	p.BorderSizePixel = 0
	if p.TextXAlignment == nil then
		p.TextXAlignment = Enum.TextXAlignment.Left
	end
	if p.TextYAlignment == nil then
		p.TextYAlignment = Enum.TextYAlignment.Center
	end
	return new("TextLabel", p, children)
end

local function textButton(name: string, text: string, fontKey: string, size: number, props: { [string]: any }?, children: { Instance }?): any
	local p = props or {}
	p.Name = name
	p.Text = text
	p.FontFace = Theme.Fonts[fontKey] or Theme.Fonts.Heading
	p.TextSize = math.max(Theme.TextSize.Small, size)
	if p.TextColor3 == nil then
		p.TextColor3 = Theme.Colors.Text
	end
	if p.BackgroundColor3 == nil then
		p.BackgroundColor3 = Theme.Colors.Panel
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

local function stroke(transparency: number?, color: Color3?, thickness: number?): UIStroke
	return new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Transparency = transparency or Theme.Transparency.Stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- soft dark outline so text over the 3D world stays readable
local function shadow(transparency: number?): UIStroke
	return new("UIStroke", {
		Name = "Shadow",
		Color = Theme.Colors.Shadow,
		Transparency = transparency or Theme.Transparency.TextShadow,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
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

local function list(direction: Enum.FillDirection, gap: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return new("UIListLayout", {
		Name = "Layout",
		FillDirection = direction,
		Padding = UDim.new(0, gap or 0),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local function gradient(rotation: number, sequence: NumberSequence): UIGradient
	return new("UIGradient", { Rotation = rotation, Transparency = sequence })
end

local function seq(points: { { number } }): NumberSequence
	local keypoints = {}
	for _, p in ipairs(points) do
		table.insert(keypoints, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keypoints)
end

local function scroll(name: string, parent: Instance, children: { Instance }, position: UDim2?, size: UDim2?): ScrollingFrame
	return new("ScrollingFrame", {
		Name = name,
		Position = position or UDim2.new(),
		Size = size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Colors.Text,
		ScrollBarImageTransparency = 0.7,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Selectable = false,
		Parent = parent,
	}, children)
end

-- inset background for CanvasGroups (a Border stroke at the canvas edge would be clipped)
local function canvasBg(parent: Instance, transparency: number, radius: UDim?)
	return frame("Bg", {
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = transparency,
		ZIndex = 1,
		Parent = parent,
	}, { corner(radius or Theme.CornerLarge), stroke(0.84) })
end

local function screen(name: string, displayOrder: number, fullBleed: boolean?, padded: boolean?): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = fullBleed == true
	gui.ScreenInsets = if fullBleed then Enum.ScreenInsets.None else Enum.ScreenInsets.CoreUISafeInsets
	pcall(function()
		gui.ClipToDeviceSafeArea = false
		gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	end)
	local root = frame("Root", { Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	new("UIScale", { Name = "Scale", Scale = 1, Parent = root })
	if padded ~= false then
		local pad = padding(16, 16, 16, 16)
		pad.Name = "SafePad"
		pad.Parent = root
	end
	root.Parent = gui
	return gui, root
end

local function controlRow(parent: Instance)
	local C = Theme.Colors
	local row = frame("ControlRow", { Size = UDim2.new(1, 0, 0, 26), Parent = parent })
	label("Action", "Action", "Body", 14, { Size = UDim2.new(0.5, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
	local key = frame("Key", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(26, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.3,
		Parent = row,
	}, { corner(Theme.CornerSmall), stroke(0.82), padding(8, 8, 0, 0) })
	label("Label", "KEY", "Mono", 13, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = key })
	return row
end

local function pillButton(name: string, text: string, order: number, parent: Instance, primary: boolean?): TextButton
	local C = Theme.Colors
	return textButton(name, text, "Heading", 14, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundColor3 = if primary then C.Accent else C.Panel,
		BackgroundTransparency = if primary then 0.05 else Theme.Transparency.Panel,
		TextColor3 = if primary then C.TextDark else C.Text,
		LayoutOrder = order,
		RichText = true,
		Parent = parent,
	}, { corner(Theme.CornerPill), stroke(if primary then 0.6 else 0.8), padding(16, 16, 0, 0) })
end

------------------------------------------------------------------------------------------------
-- HUD (arena): compass + clock, kill feed, vitals, hotbar
------------------------------------------------------------------------------------------------
local function buildHUD(): ScreenGui
	local gui, root = screen("HUD", 10)
	local C = Theme.Colors

	-- Top centre
	local top = frame("Top", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(360, 104), Visible = false, Parent = root })
	local compass = frame("Compass", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(360, 40),
		ClipsDescendants = true,
		Parent = top,
	})
	frame("Baseline", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Text,
		BackgroundTransparency = 0.45,
		Parent = compass,
	}, { gradient(0, seq({ { 0, 1 }, { 0.2, 0 }, { 0.8, 0 }, { 1, 1 } })) })
	local ticks = frame("Ticks", { Size = UDim2.fromScale(1, 1), Parent = compass })
	for angle = 0, 345, 15 do
		local major = angle % 45 == 0
		local t = frame(string.format("T%03d", angle), {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.fromOffset(if angle % 90 == 0 then 2 else 1, if major then 8 else 5),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = if major then 0.1 else 0.45,
			Parent = ticks,
		})
		t:SetAttribute("Angle", angle)
		t:SetAttribute("BaseTransparency", t.BackgroundTransparency)
	end
	local directions = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
	for angle, text in pairs(directions) do
		local cardinal = angle % 90 == 0
		local l = label("L" .. text, text, "Heading", if cardinal then 17 else 13, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(34, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if angle == 0 then C.Accent elseif cardinal then C.Text else C.TextDim,
			Parent = ticks,
		}, { shadow(0.6) })
		l:SetAttribute("Angle", angle)
		l:SetAttribute("BaseTransparency", 0)
	end
	local markers = frame("Markers", { Size = UDim2.fromScale(1, 1), Parent = compass })
	local spire = frame("Spire", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(12, 12), Visible = false, Parent = markers })
	frame("Diamond", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(7, 7),
		Rotation = 45,
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0,
		Parent = spire,
	}, { stroke(0.4, C.Shadow, 1) })
	label("Dist", "", "Mono", 13, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 3, 0.5, 0),
		Size = UDim2.fromOffset(64, 14),
		AutomaticSize = Enum.AutomaticSize.X, -- "212 m  BORDER 42 m" near the border's edge
		TextColor3 = C.AccentSoft,
		RichText = true,
		Parent = spire,
	}, { shadow() })
	local border = frame("Border", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(14, 14), Visible = false, Parent = markers })
	frame("Ring", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = C.Border,
		BackgroundTransparency = 0,
		Parent = border,
	}, { corner(Theme.CornerPill), stroke(0.3, C.Shadow, 1) })
	-- water for the thirsty (QW10, Guidance): a drop with the distance on its left (at the ribbon's edge, on its inside)
	local water = frame("Water", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(16, 16), Visible = false, Parent = markers })
	frame("Tip", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -3),
		Size = UDim2.fromOffset(7, 7),
		Rotation = 45,
		BackgroundColor3 = C.Thirst,
		BackgroundTransparency = 0,
		Parent = water,
	}, { stroke(0.45, C.Shadow, 1) })
	frame("Bulb", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 1),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = C.Thirst,
		BackgroundTransparency = 0,
		Parent = water,
	}, { corner(Theme.CornerPill), stroke(0.45, C.Shadow, 1) })
	label("Dist", "", "Mono", 14, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -3, 0.5, 0),
		Size = UDim2.fromOffset(64, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Thirst,
		Parent = water,
	}, { shadow(0.3) })
	-- the border's nearest edge while it moves (QW10): a thin tick; the distance is in the Info row ("BORDER 42 m")
	local edge = frame("Edge", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(10, 14), Visible = false, Parent = markers })
	frame("Tick", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 12),
		BackgroundColor3 = C.Border,
		BackgroundTransparency = 0,
		Parent = edge,
	}, { stroke(0.4, C.Shadow, 1) })
	frame("Notch", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(2, 12),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0,
		ZIndex = 3,
		Parent = compass,
	})
	local info = frame("Info", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 20), Parent = top }, {
		list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	label("Timer", "0:00", "Mono", 16, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 1, Parent = info }, { shadow() })
	frame("Dot", { Size = UDim2.fromOffset(3, 3), BackgroundColor3 = C.TextDim, BackgroundTransparency = 0, LayoutOrder = 2, Parent = info }, { corner(Theme.CornerPill) })
	label("Remain", "24 REMAIN", "Heading", 15, { RichText = true, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 3, Parent = info }, { shadow() })
	label("Practice", "PRACTICE", "Heading", 13, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C.AccentSoft,
		LayoutOrder = 4,
		Visible = false,
		Parent = info,
	}, { shadow() })
	-- QW10: how far the border's edge is, while it moves and you're within 80 m of it; a tick on the ribbon points at it
	-- (on a dark pill: over a dark tree or a bright sky the digits must still read)
	label("Border", "", "Heading", 14, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C.Border,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.3,
		LayoutOrder = 5,
		Visible = false,
		Parent = info,
	}, { corner(Theme.CornerPill), padding(8, 8, 0, 0), shadow(0.4) })
	label("Event", "", "Heading", 14, {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Warning,
		RichText = true,
		Visible = false,
		Parent = top,
	}, { shadow() })
	-- shares the event line's slot: when you're outside the border the alert replaces the event line
	local alert = frame("Alert", { Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 36), Visible = false, Parent = top })
	label("Title", "OUTSIDE THE BORDER", "Heading", 17, { Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Danger, Parent = alert }, { shadow(0.35) })
	label("Sub", "Head back toward the marker", "Body", 13, {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = alert,
	}, { shadow() })

	-- Kill feed (top right on desktop; the controller moves it on touch screens)
	frame("KillFeed", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(380, 170), Parent = root }, {
		list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top),
	})

	-- Vitals (bottom left on desktop, top left on touch screens)
	local vitals = frame("Vitals", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(210, 120), Visible = false, Parent = root }, {
		list(Enum.FillDirection.Vertical, 7, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom),
	})
	local function statRow(name: string, text: string, color: Color3, order: number, barHeight: number)
		local row = frame(name, { Size = UDim2.new(1, 0, 0, 20 + barHeight), LayoutOrder = order, Parent = vitals })
		label("Label", text, "Heading", 13, { Size = UDim2.new(1, -44, 0, 15), TextColor3 = C.TextDim, RichText = true, Parent = row }, { shadow() })
		label("Value", "100", "Mono", 13, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(44, 15),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		}, { shadow() })
		local track = frame("Track", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, barHeight),
			BackgroundColor3 = C.Track,
			BackgroundTransparency = Theme.Transparency.BarTrack,
			Parent = row,
		}, { corner(Theme.CornerPill) })
		frame("Ghost", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.5, ZIndex = 1, Parent = track }, { corner(Theme.CornerPill) })
		frame("Fill", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = 2, Parent = track }, { corner(Theme.CornerPill) })
		return row
	end
	local health = statRow("Health", "HEALTH", C.Health, 1, 5)
	frame("ArmorLine", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -8),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Armor,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = health,
	})
	-- a slow light sweep over the health fill while health comes back (HUDController moves the gradient)
	local shimmer = frame("Shimmer", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Text,
		BackgroundTransparency = 0,
		ZIndex = 3,
		Visible = false,
		Parent = health.Track.Fill,
	}, { corner(Theme.CornerPill) })
	-- (bright enough to catch the eye at a glance: health coming back is good news worth seeing)
	gradient(0, seq({ { 0, 1 }, { 0.34, 1 }, { 0.5, 0.35 }, { 0.66, 1 }, { 1, 1 } })).Parent = shimmer
	-- why health isn't coming back (QW5): "NOT HEALING · THIRSTY", red when a meter is empty. On its own dark pill so
	-- it reads over bright plaza stone; the reason word takes its meter's colour (HUDController).
	label("Reason", "", "Heading", 15, {
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
		TextColor3 = C.Text,
		RichText = true,
		LayoutOrder = 2,
		Visible = false,
		Parent = vitals,
	}, { corner(Theme.CornerSmall), padding(8, 9, 0, 0) })
	for _, row in ipairs({ statRow("Hunger", "HUNGER", C.Hunger, 3, 3), statRow("Thirst", "THIRST", C.Thirst, 4, 3) }) do
		-- the healing line: health only comes back while both meters are above Config.Survival.RegenMinStat
		-- (HUDController places it from Config)
		frame("Tick", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.55, 0.5),
			Size = UDim2.new(0, 1, 1, 4),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = 0.3,
			ZIndex = 3,
			Parent = row.Track,
		})
	end
	statRow("Stamina", "STAMINA", C.Stamina, 5, 3)

	-- Hotbar (bottom centre)
	local slots = Config.Inventory.Slots
	local SLOT, GAP = 56, 6
	local hotbar = frame("Hotbar", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(slots * SLOT + (slots - 1) * GAP, SLOT + 8),
		Visible = false,
		Parent = root,
	})
	local row = frame("Slots", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, SLOT), Parent = hotbar }, {
		list(Enum.FillDirection.Horizontal, GAP, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom),
	})
	for i = 1, slots do
		local slot = textButton("Slot" .. i, "", "Heading", 13, {
			Size = UDim2.fromOffset(SLOT, SLOT),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Selectable = false,
			Parent = row,
		})
		local card = frame("Card", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.42, Parent = slot }, { corner(Theme.Corner) })
		local cardStroke = stroke(0.84)
		cardStroke.Name = "Stroke"
		cardStroke.Parent = card
		new("ViewportFrame", {
			Name = "Viewport",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -6, 1, -6),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(150, 150, 150),
			LightColor = Color3.fromRGB(255, 242, 228),
			LightDirection = Vector3.new(-0.55, -1, -0.65),
			Parent = card,
		})
		label("Fallback", "", "Heading", 13, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 1, -18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			TextColor3 = C.TextDim,
			Visible = false,
			Parent = card,
		})
		label("Key", tostring(i), "Mono", 13, { Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(12, 14), TextColor3 = C.TextDim, ZIndex = 3, Parent = card })
		label("Count", "", "Mono", 13, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -5, 1, -4),
			Size = UDim2.fromOffset(34, 14),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
			Parent = card,
		}, { shadow(0.4) })
		frame("Rarity", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -1),
			Size = UDim2.new(1, -16, 0, 2),
			BackgroundColor3 = C.TextDim,
			BackgroundTransparency = 0,
			Visible = false,
			ZIndex = 3,
			Parent = card,
		}, { corner(Theme.CornerPill) })
	end
	local itemName = canvas("ItemName", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(400, 42),
		GroupTransparency = 1,
		Parent = hotbar,
	})
	label("Title", "", "BodyBold", 17, { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, Parent = itemName }, { shadow() })
	label("Sub", "", "Heading", 13, {
		Position = UDim2.fromOffset(0, 23),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.TextDim,
		RichText = true,
		Parent = itemName,
	}, { shadow() })
	-- the item's description, for its first few pickups (QW2; HUDController grows the toast to 60 px for it)
	label("Desc", "", "Body", 14, {
		Position = UDim2.fromOffset(0, 41),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = itemName,
	}, { shadow() })
	local function capHint(name: string, text: string, anchorX: number, position: UDim2)
		local cap = frame(name, {
			AnchorPoint = Vector2.new(anchorX, 0.5),
			Position = position,
			Size = UDim2.fromOffset(30, 20),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.3,
			Visible = false,
			Parent = hotbar,
		}, { corner(Theme.CornerSmall), stroke(0.7) })
		label("Label", text, "Mono", 13, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = cap })
	end
	capHint("PrevHint", "LB", 1, UDim2.new(0, -8, 1, -SLOT / 2))
	capHint("NextHint", "RB", 0, UDim2.new(1, 8, 1, -SLOT / 2))

	-- Templates
	local templates = frame("Templates", { Visible = false, Parent = root })
	local entry = frame("KillEntry", {
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.4,
		Parent = templates,
	}, {
		corner(Theme.CornerSmall),
		padding(10, 10, 0, 0),
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	frame("Mark", { Size = UDim2.fromOffset(2, 14), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, LayoutOrder = 1, Visible = false, Parent = entry })
	label("Text", "", "Body", 14, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), RichText = true, LayoutOrder = 2, Parent = entry })
	return gui
end

------------------------------------------------------------------------------------------------
-- HUDFX (full bleed, true screen centre): vignettes, crosshair, hit/damage markers, use ring, draw meter, hint
------------------------------------------------------------------------------------------------
local function buildHUDFX(): ScreenGui
	local gui, root = screen("HUDFX", 9, true, false)
	local C = Theme.Colors
	local vignette = frame("Vignette", { Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = gui })
	local EDGE = seq({ { 0, 0 }, { 0.45, 0.72 }, { 1, 1 } })
	local function edges(name: string, color: Color3, depth: number)
		local holder = frame(name, { Size = UDim2.fromScale(1, 1), Parent = vignette })
		frame("Top", { Size = UDim2.new(1, 0, depth, 0), BackgroundColor3 = color, BackgroundTransparency = 1, Parent = holder }, { gradient(90, EDGE) })
		frame("Bottom", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, depth, 0),
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			Parent = holder,
		}, { gradient(270, EDGE) })
		frame("Left", { Size = UDim2.new(depth * 0.7, 0, 1, 0), BackgroundColor3 = color, BackgroundTransparency = 1, Parent = holder }, { gradient(0, EDGE) })
		frame("Right", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(depth * 0.7, 0, 1, 0),
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			Parent = holder,
		}, { gradient(180, EDGE) })
	end
	edges("LowHealth", Color3.fromRGB(105, 8, 10), 0.34)
	edges("Border", Color3.fromRGB(150, 52, 22), 0.38)
	edges("Hurt", Color3.fromRGB(150, 16, 16), 0.26)

	local center = frame("Center", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), Parent = root })

	-- crosshair: dot + spread lines
	local cross = frame("Crosshair", { Size = UDim2.fromOffset(0, 0), Visible = false, Parent = center })
	frame("Dot", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = C.Text,
		BackgroundTransparency = 0,
		Parent = cross,
	}, { corner(Theme.CornerPill), stroke(0.5, C.Shadow, 1) })
	local function line(name: string, anchor: Vector2, position: UDim2, size: UDim2)
		frame(name, { AnchorPoint = anchor, Position = position, Size = size, BackgroundColor3 = C.Text, BackgroundTransparency = 0.05, Parent = cross }, { stroke(0.62, C.Shadow, 1) })
	end
	line("Up", Vector2.new(0.5, 1), UDim2.fromOffset(0, -6), UDim2.fromOffset(2, 7))
	line("Down", Vector2.new(0.5, 0), UDim2.fromOffset(0, 6), UDim2.fromOffset(2, 7))
	line("Left", Vector2.new(1, 0.5), UDim2.fromOffset(-6, 0), UDim2.fromOffset(7, 2))
	line("Right", Vector2.new(0, 0.5), UDim2.fromOffset(6, 0), UDim2.fromOffset(7, 2))

	-- hit / kill marker
	local hit = frame("Hit", { Size = UDim2.fromOffset(0, 0), Parent = center })
	for _, d in ipairs({ { "A", 1, -1, 45 }, { "B", -1, -1, -45 }, { "C", 1, 1, -45 }, { "D", -1, 1, 45 } }) do
		local tick = frame(d[1], {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(d[2] * 8, d[3] * 8),
			Size = UDim2.fromOffset(2, 9),
			Rotation = d[4],
			BackgroundColor3 = C.Text,
			BackgroundTransparency = 1,
			Parent = hit,
		})
		local s = stroke(1, C.Shadow, 1)
		s.Parent = tick
	end

	-- directional damage arcs (each Dir is rotated toward the attacker; 5 segments form a soft arc)
	local damage = frame("Damage", { Size = UDim2.fromOffset(0, 0), Parent = center })
	for i = 1, 4 do
		local dir = frame("Dir" .. i, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(250, 250), Visible = false, Parent = damage })
		for k = -2, 2 do
			local holder = frame("Seg" .. (k + 3), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Rotation = k * 6.5, Parent = dir })
			local bar = frame("Bar", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(15, 4),
				BackgroundColor3 = C.Danger,
				BackgroundTransparency = 1,
				Parent = holder,
			}, { corner(Theme.CornerPill) })
			bar:SetAttribute("Weight", 1 - math.abs(k) * 0.3)
		end
	end

	-- use-progress ring (segmented)
	local ring = frame("UseRing", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(56, 56), Visible = false, Parent = center })
	local SEGMENTS = 36
	for i = 1, SEGMENTS do
		local a = math.rad((i - 0.5) / SEGMENTS * 360)
		frame(string.format("S%02d", i), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(a) * 24, 0.5, -math.cos(a) * 24),
			Size = UDim2.fromOffset(2, 6),
			Rotation = math.deg(a),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = 0.75,
			Parent = ring,
		})
	end
	label("Label", "", "Heading", 13, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(260, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = ring,
	}, { shadow() })

	-- bow draw meter
	local draw = frame("Draw", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.fromOffset(52, 3),
		BackgroundColor3 = C.Track,
		BackgroundTransparency = 0.7,
		Visible = false,
		Parent = center,
	}, { corner(Theme.CornerPill), stroke(0.7, C.Shadow, 1) })
	frame("Fill", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0, Parent = draw }, { corner(Theme.CornerPill) })

	-- interaction hint ([E] Drink)
	local interact = canvas("Interact", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.fromOffset(340, 28),
		GroupTransparency = 1,
		Visible = false,
		Parent = center,
	}, { list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local key = frame("Key", {
		Size = UDim2.fromOffset(24, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.2,
		LayoutOrder = 1,
		Parent = interact,
	}, { corner(Theme.CornerSmall), stroke(0.5, C.Text, 1), padding(7, 7, 0, 0) })
	label("Label", "E", "Mono", 13, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = key })
	label("Text", "", "BodyBold", 15, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 2, Parent = interact }, { shadow() })

	-- action hint (QW2): what the held item does with this device's buttons, e.g. HOLD [LMB] EAT · +12 HUNGER.
	-- Same slot and style as the interaction hint, which takes priority. HUDController builds the row from Templates.
	local action = canvas("Action", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.fromOffset(560, 28),
		GroupTransparency = 1,
		Visible = false,
		Parent = center,
	}, { list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	-- (GuiObjects under a Folder still draw, so the templates stay hidden; HUDController shows its clones)
	local actionTemplates = new("Folder", { Name = "Templates", Parent = action })
	local cap = frame("Key", {
		Size = UDim2.fromOffset(24, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = actionTemplates,
	}, { corner(Theme.CornerSmall), stroke(0.5, C.Text, 1), padding(7, 7, 0, 0) })
	label("Label", "E", "Mono", 13, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextXAlignment = Enum.TextXAlignment.Center, Parent = cap })
	label("Text", "", "BodyBold", 15, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Visible = false, Parent = actionTemplates }, { shadow() })
	return gui
end

------------------------------------------------------------------------------------------------
-- Lobby: title, status pill, record card, how-to-play panel
------------------------------------------------------------------------------------------------
local function buildLobby(): ScreenGui
	local gui, root = screen("Lobby", 14)
	local C = Theme.Colors

	local status = frame("Status", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(640, 54), Parent = root })
	local pill = frame("Pill", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = Theme.Transparency.Panel,
		Parent = status,
	}, {
		corner(Theme.CornerPill),
		stroke(),
		padding(18, 18, 0, 0),
		list(Enum.FillDirection.Horizontal, 11, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	frame("Dot", { Size = UDim2.fromOffset(7, 7), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, LayoutOrder = 1, Parent = pill }, { corner(Theme.CornerPill) })
	label("Text", "WAITING FOR PLAYERS", "Heading", 16, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), RichText = true, LayoutOrder = 2, Parent = pill })
	textButton("Spectate", "SPECTATE", "Heading", 14, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0.05,
		TextColor3 = C.TextDark,
		RichText = true,
		LayoutOrder = 3,
		Visible = false,
		Parent = pill,
	}, { corner(Theme.CornerPill), padding(14, 14, 0, 0) })
	local bar = frame("Bar", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 47),
		Size = UDim2.fromOffset(160, 2),
		BackgroundColor3 = C.Track,
		BackgroundTransparency = 0.8,
		Visible = false,
		Parent = status,
	}, { corner(Theme.CornerPill) })
	frame("Fill", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, Parent = bar }, { corner(Theme.CornerPill) })

	local brand = frame("Brand", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(340, 240), Parent = root }, {
		list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom),
	})
	frame("Mark", { Size = UDim2.fromOffset(28, 2), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, LayoutOrder = 1, Parent = brand })
	label("Title", Config.GameTitle, "Display", 34, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = brand }, { shadow(0.6) })
	label("Tagline", "Outlast everyone.", "Body", 15, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.TextDim, LayoutOrder = 3, Parent = brand }, { shadow(0.7) })
	frame("Gap", { Size = UDim2.fromOffset(1, 4), LayoutOrder = 4, Parent = brand })
	local stats = frame("Stats", {
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = Theme.Transparency.Panel,
		LayoutOrder = 5,
		Parent = brand,
	}, { corner(Theme.Corner), stroke() })
	label("Header", "YOUR RECORD", "Heading", 13, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 15), TextColor3 = C.TextDim, Parent = stats })
	local cells = frame("Cells", { Position = UDim2.fromOffset(14, 27), Size = UDim2.new(1, -28, 0, 42), Parent = stats }, {
		list(Enum.FillDirection.Horizontal, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	for i, pair in ipairs({ { "Wins", "WINS" }, { "Kills", "KILLS" }, { "Rounds", "ROUNDS" } }) do
		local cell = frame(pair[1], { Size = UDim2.new(1 / 3, 0, 1, 0), LayoutOrder = i, Parent = cells })
		label("Value", "0", "Display", 24, { Size = UDim2.new(1, 0, 0, 26), Parent = cell })
		label("Label", pair[2], "Heading", 13, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 15), TextColor3 = C.TextDim, Parent = cell })
	end
	local buttons = frame("Buttons", { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 6, Parent = brand }, {
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	pillButton("Settings", "SETTINGS", 1, buttons)
	pillButton("HowTo", "HOW TO PLAY", 2, buttons)

	local how = canvas("HowTo", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0, 330, 1, -140),
		GroupTransparency = 0,
		Parent = root,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(330, 560) }) })
	canvasBg(how, 0.22)
	local header = frame("Header", { Size = UDim2.new(1, 0, 0, 46), ZIndex = 2, Parent = how })
	label("Title", "HOW TO PLAY", "Heading", 18, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -64, 1, 0), Parent = header })
	textButton("Close", "×", "Body", 22, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 1,
		Parent = header,
	}, { corner(Theme.CornerPill) })
	frame("Divider", { Position = UDim2.fromOffset(18, 46), Size = UDim2.new(1, -36, 0, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.9, ZIndex = 2, Parent = how })
	local body = scroll("Body", how, {
		padding(18, 18, 12, 16),
		list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	}, UDim2.fromOffset(0, 47), UDim2.new(1, 0, 1, -48))
	body.ZIndex = 2
	label("Steps", STEPS, "Heading", 14, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 0,
		Parent = body,
	})
	for i, text in ipairs(TIPS) do
		local tip = frame("Tip" .. i, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = body })
		label("Num", string.format("%02d", i), "Mono", 13, { Size = UDim2.fromOffset(24, 18), TextColor3 = C.Accent, TextYAlignment = Enum.TextYAlignment.Top, Parent = tip })
		label("Text", text, "Body", 14, {
			Position = UDim2.fromOffset(28, 0),
			Size = UDim2.new(1, -28, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = tip,
		})
	end
	label("ControlsHeader", "CONTROLS", "Heading", 14, {
		Size = UDim2.new(1, 0, 0, 28),
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextColor3 = C.TextDim,
		LayoutOrder = 10,
		Parent = body,
	})
	frame("Controls", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 11, Parent = body }, {
		list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})

	local templates = frame("Templates", { Visible = false, Parent = root })
	local row = controlRow(templates)
	-- the panel is narrow: a long action ("Crouch · quieter steps · slide while sprinting") wraps onto a second line
	-- instead of being cut off (QW6 teaches crouching as quieter); the key cap keeps the right edge
	row.AutomaticSize = Enum.AutomaticSize.Y
	local action = row:FindFirstChild("Action")
	if action then
		action.Size = UDim2.new(1, -124, 0, 26)
		action.AutomaticSize = Enum.AutomaticSize.Y
		action.TextWrapped = true
		action.TextTruncate = Enum.TextTruncate.None
	end
	return gui
end

------------------------------------------------------------------------------------------------
-- Overlay: countdown, headlines, toasts, roll call, death and victory screens
------------------------------------------------------------------------------------------------
local function buildOverlay(): ScreenGui
	local gui, root = screen("Overlay", 20)
	local C = Theme.Colors
	frame("Dim", {
		Position = UDim2.fromOffset(-240, -240),
		Size = UDim2.new(1, 480, 1, 480),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = gui,
	})

	local countdown = frame("Countdown", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(440, 240), Visible = false, Parent = root })
	local number = label("Number", "3", "Display", 132, { Size = UDim2.new(1, 0, 0, 160), TextXAlignment = Enum.TextXAlignment.Center, Parent = countdown }, { shadow(0.5) })
	new("UIScale", { Name = "Pop", Parent = number })
	-- the goal, then the choice (QW6): the most-watched seconds of the round, so a bright line on a dark pill
	label("Caption", "GET READY", "Heading", 22, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 164),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Text,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.3,
		Parent = countdown,
	}, { corner(Theme.CornerPill), padding(18, 18, 0, 0), shadow(0.5) })
	-- new players: where running pays (QW7's runner's caches, behind every plate)
	label("Sub", "", "Heading", 15, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 204),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Text,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.45,
		Visible = false,
		Parent = countdown,
	}, { corner(Theme.CornerPill), padding(14, 14, 0, 0), shadow(0.6) })

	local headline = canvas("Headline", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.16, 0),
		Size = UDim2.new(1, -40, 0, 132),
		GroupTransparency = 1,
		Visible = false,
		Parent = root,
	}, {
		new("UISizeConstraint", { MaxSize = Vector2.new(780, 132) }),
		list(Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})
	label("Eyebrow", "", "Heading", 14, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Accent, LayoutOrder = 1, Parent = headline }, { shadow() })
	label("Title", "", "Display", 40, { Size = UDim2.new(1, 0, 0, 48), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = headline }, { shadow(0.45) })
	frame("Rule", { Size = UDim2.fromOffset(56, 2), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, LayoutOrder = 3, Parent = headline })
	label("Sub", "", "Body", 16, {
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		RichText = true,
		LayoutOrder = 4,
		Parent = headline,
	}, { shadow() })

	-- toasts sit above the HUD's item-name block (60 px tall with an item's description)
	frame("Toasts", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -136), Size = UDim2.fromOffset(460, 150), Parent = root }, {
		list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom),
	})
	-- one-time help cards (QW5: THIRSTY, HUNGRY) at the left, clear of the item toast, the hint and the held item
	frame("Cards", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.42), Size = UDim2.fromOffset(400, 220), Parent = root }, {
		list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})

	local roll = canvas("RollCall", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(1, -40, 0, 300),
		GroupTransparency = 1,
		Visible = false,
		Parent = root,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(640, 300) }) })
	frame("Shade", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.3,
		Parent = roll,
	}, { corner(Theme.CornerLarge), gradient(90, seq({ { 0, 1 }, { 0.22, 0.2 }, { 0.78, 0.2 }, { 1, 1 } })) })
	label("Title", "THE FALLEN", "Heading", 22, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Parent = roll }, { shadow() })
	frame("Rule", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(40, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.4, Parent = roll })
	label("Sub", "", "Body", 14, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.TextDim, Parent = roll })
	-- compact (phone) variant: the names flow on one wrapped line under the title
	label("Line", "", "Body", 15, {
		Position = UDim2.fromOffset(16, 36),
		Size = UDim2.new(1, -32, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		Visible = false,
		Parent = roll,
	}, { shadow() })
	frame("Names", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 88), Size = UDim2.new(1, -40, 1, -104), Parent = roll }, {
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(180, 24),
			CellPadding = UDim2.fromOffset(8, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- death screen
	local death = frame("Death", { Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })
	local dpanel = canvas("Panel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 1, -12),
		GroupTransparency = 1,
		Parent = death,
	}, {
		new("UISizeConstraint", { MaxSize = Vector2.new(560, 380) }),
		list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	label("Eyebrow", "ELIMINATED", "Heading", 15, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Danger, LayoutOrder = 1, Parent = dpanel }, { shadow() })
	label("Title", "#2", "Display", 72, { Size = UDim2.new(1, 0, 0, 80), TextXAlignment = Enum.TextXAlignment.Center, RichText = true, LayoutOrder = 2, Parent = dpanel }, { shadow(0.5) })
	label("Cause", "", "Body", 17, {
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		RichText = true,
		LayoutOrder = 3,
		Parent = dpanel,
	}, { shadow() })
	-- QW4: how far you got ("OUTLASTED 15 OF 24  ·  6:12") and one tip for what killed you
	label("Progress", "", "Heading", 14, {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.TextDim,
		LayoutOrder = 4,
		Visible = false,
		Parent = dpanel,
	}, { shadow() })
	label("Tip", "", "Body", 15, {
		Size = UDim2.new(1, -60, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		RichText = true,
		LayoutOrder = 5,
		Visible = false,
		Parent = dpanel,
	}, { shadow() })
	frame("Gap", { Size = UDim2.fromOffset(1, 12), LayoutOrder = 6, Parent = dpanel })
	local dbuttons = frame("Buttons", { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 7, Parent = dpanel }, {
		list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local spectate = textButton("Spectate", "SPECTATE", "Heading", 15, {
		Size = UDim2.fromOffset(176, 44),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0.05,
		TextColor3 = C.TextDark,
		Modal = true,
		LayoutOrder = 1,
		Parent = dbuttons,
	}, { corner(Theme.CornerPill), stroke(0.6) })
	spectate:SetAttribute("Primary", true)
	textButton("Continue", "CONTINUE", "Heading", 15, {
		Size = UDim2.fromOffset(176, 44),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
		Modal = true,
		LayoutOrder = 2,
		Parent = dbuttons,
	}, { corner(Theme.CornerPill), stroke(0.7) })
	label("Note", "", "Body", 13, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.TextDim, RichText = true, LayoutOrder = 8, Parent = dpanel }, { shadow(0.7) })

	-- victory screen + round summary
	local victory = frame("Victory", { Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })
	local vpanel = canvas("Panel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.new(1, -40, 0.88, 0),
		GroupTransparency = 1,
		Parent = victory,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(620, 600) }) })
	label("Eyebrow", "THE ROUND IS OVER", "Heading", 15, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Gold, Parent = vpanel }, { shadow() })
	label("Title", "VICTORY", "Display", 64, {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 72),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = vpanel,
	}, { shadow(0.5) })
	label("Sub", "", "Body", 17, {
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		RichText = true,
		Parent = vpanel,
	}, { shadow() })
	local summary = frame("Summary", {
		Position = UDim2.fromOffset(1, 132),
		Size = UDim2.new(1, -2, 1, -133),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = vpanel,
	}, { corner(Theme.CornerLarge), stroke(0.86) })
	local head = frame("Header", { Size = UDim2.new(1, 0, 0, 34), Parent = summary })
	label("Rank", "#", "Heading", 13, { Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(40, 34), TextColor3 = C.TextDim, Parent = head })
	label("Contender", "CONTENDER", "Heading", 13, { Position = UDim2.fromOffset(60, 0), Size = UDim2.new(1, -150, 0, 34), TextColor3 = C.TextDim, Parent = head })
	label("Kills", "KILLS", "Heading", 13, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.fromOffset(60, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.TextDim,
		Parent = head,
	})
	frame("Divider", { Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.9, Parent = summary })
	scroll("Rows", summary, {
		padding(6, 6, 2, 4),
		list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	}, UDim2.fromOffset(0, 38), UDim2.new(1, 0, 1, -70))
	label("Footer", "", "Body", 13, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -7),
		Size = UDim2.new(1, -32, 0, 20),
		TextColor3 = C.TextDim,
		Parent = summary,
	})

	-- templates
	local templates = frame("Templates", { Visible = false, Parent = root })
	local toast = frame("Toast", {
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.2,
		Parent = templates,
	}, {
		corner(Theme.CornerPill),
		stroke(0.85),
		padding(14, 16, 0, 0),
		list(Enum.FillDirection.Horizontal, 9, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	frame("Mark", { Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, LayoutOrder = 1, Parent = toast }, { corner(Theme.CornerPill) })
	label("Text", "", "BodyBold", 15, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = toast,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(320, 36) }) })
	label("Sub", "", "Body", 14, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 3,
		Parent = toast,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(260, 36) }) })
	local srow = frame("SummaryRow", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 1, Parent = templates }, { corner(Theme.CornerSmall) })
	frame("Mark", { Position = UDim2.fromOffset(0, 7), Size = UDim2.fromOffset(2, 14), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, Visible = false, Parent = srow })
	label("Rank", "1", "Mono", 14, { Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(40, 28), TextColor3 = C.TextDim, Parent = srow })
	label("PlayerName", "", "Body", 15, { Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -140, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, Parent = srow })
	label("Kills", "0", "Mono", 14, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.fromOffset(60, 28),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = srow,
	})
	label("RollName", "", "Body", 16, {
		Size = UDim2.fromOffset(180, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = templates,
	})
	-- one-time cards for new players (QW5: THIRSTY, HUNGRY): a title and a wrapped line, shown with the toasts
	local card = frame("Card", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.2,
		Parent = templates,
	}, {
		corner(Theme.CornerLarge),
		stroke(0.85),
		padding(14, 16, 8, 9),
		list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	local markHolder = frame("MarkHolder", { Size = UDim2.fromOffset(6, 18), LayoutOrder = 1, Parent = card })
	frame("Mark", { Position = UDim2.fromOffset(0, 6), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, Parent = markHolder }, { corner(Theme.CornerPill) })
	local cardBody = frame("Body", { Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2, Parent = card }, {
		list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	label("Title", "", "Heading", 15, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = cardBody })
	label("Text", "", "Body", 14, {
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		RichText = true,
		TextColor3 = C.TextDim,
		LayoutOrder = 2,
		Parent = cardBody,
	})
	return gui
end

------------------------------------------------------------------------------------------------
-- Menu: settings + controls reference
------------------------------------------------------------------------------------------------
local function buildMenu(): ScreenGui
	local gui, root = screen("Menu", 40)
	local C = Theme.Colors
	textButton("Dim", "", "Body", 13, {
		Position = UDim2.fromOffset(-240, -240),
		Size = UDim2.new(1, 480, 1, 480),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Modal = true,
		Selectable = false,
		Visible = false,
		ZIndex = 1,
		Parent = gui,
	})

	local launcher = textButton("Launcher", "", "Heading", 13, { Size = UDim2.fromOffset(44, 44), Visible = false, Selectable = false, Parent = root }, {
		corner(UDim.new(0, 10)),
		stroke(0.78),
	})
	local icon = frame("Icon", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 14), Parent = launcher })
	for i = 0, 2 do
		frame("Line" .. (i + 1), { Position = UDim2.fromOffset(0, i * 6), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.Text, BackgroundTransparency = 0, Parent = icon }, { corner(Theme.CornerPill) })
	end

	local panel = canvas("Panel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -8),
		GroupTransparency = 1,
		Visible = false,
		Parent = root,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(600, 500) }) })
	canvasBg(panel, 0.08)
	local header = frame("Header", { Size = UDim2.new(1, 0, 0, 54), ZIndex = 2, Parent = panel })
	local tabs = frame("Tabs", { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -84, 1, 0), Parent = header }, {
		list(Enum.FillDirection.Horizontal, 22, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	for i, pair in ipairs({ { "SettingsTab", "SETTINGS" }, { "ControlsTab", "CONTROLS" } }) do
		local tab = textButton(pair[1], pair[2], "Heading", 17, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = tabs,
		})
		frame("Underline", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = 0,
			Visible = i == 1,
			Parent = tab,
		})
	end
	textButton("Close", "×", "Body", 24, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 1,
		Parent = header,
	}, { corner(Theme.CornerPill) })
	frame("Divider", { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.9, ZIndex = 2, Parent = panel })
	local pages = frame("Pages", { Position = UDim2.fromOffset(0, 55), Size = UDim2.new(1, 0, 1, -103), ZIndex = 2, Parent = panel })
	scroll("Settings", pages, {
		padding(14, 14, 6, 12),
		list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	local controls = frame("Controls", { Size = UDim2.fromScale(1, 1), Visible = false, Parent = pages })
	local devices = frame("Devices", { Position = UDim2.fromOffset(22, 12), Size = UDim2.new(1, -44, 0, 32), Parent = controls }, {
		list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	for i, pair in ipairs({ { "KeyboardMouse", "KEYBOARD & MOUSE" }, { "Gamepad", "GAMEPAD" }, { "Touch", "TOUCH" } }) do
		textButton(pair[1], pair[2], "Heading", 13, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.6,
			LayoutOrder = i,
			Parent = devices,
		}, { corner(Theme.CornerPill), stroke(0.85), padding(14, 14, 0, 0) })
	end
	scroll("List", controls, {
		padding(22, 22, 4, 12),
		list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	}, UDim2.fromOffset(0, 54), UDim2.new(1, 0, 1, -54))
	local footer = frame("Footer", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 48), ZIndex = 2, Parent = panel })
	frame("Divider", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.9, Parent = footer })
	label("Hint", "M  CLOSE", "Heading", 13, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(0.55, 0, 1, 0), TextColor3 = C.TextDim, RichText = true, Parent = footer })
	textButton("Reset", "RESET TO DEFAULTS", "Heading", 13, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.6,
		Parent = footer,
	}, { corner(Theme.CornerPill), stroke(0.82), padding(14, 14, 0, 0) })

	local templates = frame("Templates", { Visible = false, Parent = root })
	label("Section", "CAMERA", "Heading", 13, {
		Size = UDim2.new(1, 0, 0, 32),
		TextColor3 = C.TextDim,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Parent = templates,
	}, { padding(10, 0, 0, 6) })
	local slider = textButton("SliderRow", "", "Body", 13, {
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 1,
		Selectable = true,
		Parent = templates,
	}, { corner(Theme.Corner), padding(10, 10, 8, 10) })
	label("Label", "Setting", "Body", 15, { Size = UDim2.new(1, -90, 0, 20), Parent = slider })
	label("Value", "0", "Mono", 14, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(90, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.TextDim,
		Parent = slider,
	})
	local track = frame("Track", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = C.Track,
		BackgroundTransparency = 0.8,
		Parent = slider,
	}, { corner(Theme.CornerPill) })
	frame("Fill", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, Parent = track }, { corner(Theme.CornerPill) })
	frame("Knob", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = C.Text,
		BackgroundTransparency = 0,
		ZIndex = 3,
		Parent = track,
	}, { corner(Theme.CornerPill), stroke(0.55, C.Shadow, 1) })
	controlRow(templates)
	frame("Selection", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = templates }, {
		corner(Theme.Corner),
		stroke(0.05, C.Accent, 2),
	})
	return gui
end

------------------------------------------------------------------------------------------------
-- Spectate: name card with arrows, exit button
------------------------------------------------------------------------------------------------
local function buildSpectate(): ScreenGui
	local gui, root = screen("Spectate", 12)
	local C = Theme.Colors
	local card = canvas("Card", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(460, 90),
		GroupTransparency = 1,
		Visible = false,
		Parent = root,
	})
	canvasBg(card, 0.22)
	local function arrow(name: string, glyph: string, anchorX: number, x: number, keyText: string)
		local b = textButton(name, glyph, "Display", 30, {
			AnchorPoint = Vector2.new(anchorX, 0.5),
			Position = UDim2.new(anchorX, x, 0.5, -7),
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.5,
			Selectable = false,
			ZIndex = 2,
			Parent = card,
		}, { corner(Theme.CornerPill), stroke(0.8) })
		label("Hint", keyText, "Mono", 13, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 2),
			Size = UDim2.fromOffset(52, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.TextDim,
			Parent = b,
		})
		return b
	end
	arrow("Prev", "‹", 0, 12, "Q")
	arrow("Next", "›", 1, -12, "E")
	local info = frame("Info", { Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -152, 1, 0), ZIndex = 2, Parent = card })
	label("Eyebrow", "SPECTATING", "Heading", 13, { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.AccentSoft, Parent = info })
	label("PlayerName", "", "BodyBold", 21, {
		Position = UDim2.fromOffset(0, 27),
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = info,
	})
	label("Sub", "", "Body", 13, {
		Position = UDim2.fromOffset(0, 53),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.TextDim,
		RichText = true,
		Parent = info,
	})
	local hp = frame("Health", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.new(0.72, 0, 0, 3),
		BackgroundColor3 = C.Track,
		BackgroundTransparency = 0.8,
		Parent = info,
	}, { corner(Theme.CornerPill) })
	frame("Fill", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Health, BackgroundTransparency = 0, Parent = hp }, { corner(Theme.CornerPill) })
	textButton("Exit", "EXIT SPECTATING", "Heading", 13, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		RichText = true,
		Visible = false,
		Selectable = false,
		Parent = root,
	}, { corner(Theme.CornerPill), stroke(0.8), padding(16, 16, 0, 0) })
	label("Empty", "NO CONTENDERS LEFT TO WATCH", "Heading", 16, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromOffset(460, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.TextDim,
		Visible = false,
		Parent = root,
	}, { shadow() })
	return gui
end

------------------------------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------------------------------
local BUILDERS = {
	HUD = buildHUD,
	HUDFX = buildHUDFX,
	Lobby = buildLobby,
	Overlay = buildOverlay,
	Menu = buildMenu,
	Spectate = buildSpectate,
}

local function loadModules(opts: { [string]: any }?)
	local o = opts or {}
	Theme = o.Theme or require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))
	Config = o.Config or require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
end

-- opts: { Theme = table?, Config = table?, parent = Instance? } (inject freshly required modules when re-running)
function UIBuilder.build(opts: { [string]: any }?): string
	loadModules(opts)
	local parent = (opts and opts.parent) or StarterGui
	local made = {}
	for _, name in ipairs(UIBuilder.Names) do
		local old = parent:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local gui = BUILDERS[name]()
		gui.Parent = parent
		table.insert(made, string.format("%s (%d)", name, #gui:GetDescendants()))
		task.wait()
	end
	local stale = parent:FindFirstChild("TouchPreview")
	if stale then
		stale:Destroy()
	end
	return "UIBuilder built: " .. table.concat(made, ", ")
end

------------------------------------------------------------------------------------------------
-- Preview (edit time only): sample content so each screen can be checked with screen_capture.
-- preview(which, { touch = true }) also places look-alike touch buttons (Theme.TouchLayout with Shared.Input's
-- tablet scaling, plus Roblox's jump button) and slides the hotbar clear of them like HUDController does.
-- Always finish with build() to put everything back (clean and disabled).
------------------------------------------------------------------------------------------------
local function fitRoots(parent: Instance): (number, Vector2)
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local s = Theme.scaleFor(viewport)
	local p = Theme.edgePadding(viewport)
	for _, name in ipairs(UIBuilder.Names) do
		local gui = parent:FindFirstChild(name)
		local root = gui and gui:FindFirstChild("Root")
		if root then
			root.Scale.Scale = s
			root.Size = UDim2.fromScale(1 / s, 1 / s)
			local pad = root:FindFirstChild("SafePad")
			if pad then
				local u = UDim.new(0, p)
				pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = u, u, u, u
			end
		end
	end
	return s, viewport
end

local function previewIcon(viewport: ViewportFrame, itemId: string)
	local ok, model = pcall(function()
		return require(ReplicatedStorage.Shared.ItemModels).build(itemId, "world")
	end)
	if not ok or not model then
		return
	end
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
	model:PivotTo(rot * model:GetPivot():ToObjectSpace(cf):Inverse())
	local h = size / 2
	local rx, ry, rz = rot.RightVector, rot.UpVector, -rot.LookVector
	local ex = math.abs(rx.X) * h.X + math.abs(ry.X) * h.Y + math.abs(rz.X) * h.Z
	local ey = math.abs(rx.Y) * h.X + math.abs(ry.Y) * h.Y + math.abs(rz.Y) * h.Z
	local ez = math.abs(rx.Z) * h.X + math.abs(ry.Z) * h.Y + math.abs(rz.Z) * h.Z
	local distance = math.max(ex, ey, 0.2) * 1.16 / math.tan(math.rad(15)) + ez
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0, distance * 0.12, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
end

local function previewTouchButtons(parent: Instance, viewport: Vector2): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchPreview"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	local large = math.min(viewport.X, viewport.Y) > 500
	local function circle(name: string, text: string, position: UDim2, size: number)
		local b = label(name, text, "Heading", math.max(13, math.floor(size * 0.19)), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Theme.Colors.Panel,
			BackgroundTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = gui,
		}, { corner(Theme.CornerPill), stroke(0.7, Theme.Colors.Text, 1.25) })
		return b
	end
	for _, name in ipairs({ "Attack", "Aim", "Sprint", "Crouch", "Drink", "Drop" }) do
		local layout = Theme.TouchLayout[name]
		local position, size = layout.position, layout.size
		if large then
			position = UDim2.new(position.X.Scale, position.X.Offset * 1.55, position.Y.Scale, position.Y.Offset * 1.55)
			size = math.floor(size * 1.3)
		end
		circle(name, layout.label or string.upper(name), position, size)
	end
	-- Roblox's own jump button (PlayerModule TouchJump layout), anchored at its top-left corner
	local jumpSize = if large then 120 else 70
	local jump = circle("JumpButton", "JUMP", UDim2.new(), jumpSize)
	jump.AnchorPoint = Vector2.zero
	jump.Position = if large
		then UDim2.new(1, -(jumpSize * 1.5 - 10), 1, -jumpSize * 1.75)
		else UDim2.new(1, -(jumpSize * 1.5 - 10), 1, -jumpSize - 20)
	gui.Parent = parent
	return gui
end

local function applyHudLayout(root: any, touch: boolean, viewport: Vector2?)
	local key = if not touch then "Desktop" elseif Theme.isSmallScreen(viewport) then "Phone" else "Touch"
	local layout = Theme.Layout[key] or Theme.Layout.Touch
	local vitals, feed = root.Vitals, root.KillFeed
	vitals.AnchorPoint, vitals.Position, vitals.Size = layout.Vitals.anchor, layout.Vitals.position, layout.Vitals.size
	vitals.Layout.VerticalAlignment = (Enum.VerticalAlignment :: any)[layout.Vitals.align]
	feed.AnchorPoint, feed.Position, feed.Size = layout.KillFeed.anchor, layout.KillFeed.position, layout.KillFeed.size
	feed.Layout.HorizontalAlignment = (Enum.HorizontalAlignment :: any)[layout.KillFeed.align]
	local n, px, gap = Config.Inventory.Slots, layout.SlotSize, Theme.Layout.SlotGap
	for i = 1, n do
		root.Hotbar.Slots["Slot" .. i].Size = UDim2.fromOffset(px, px)
		root.Hotbar.Slots["Slot" .. i].Card.Key.Visible = not touch
	end
	root.Hotbar.Size = UDim2.fromOffset(n * px + (n - 1) * gap, px + 8)
	root.Hotbar.Slots.Size = UDim2.new(1, 0, 0, px)
end

-- same rule as HUDController.placeHotbar
local function clearHotbarOf(hud: ScreenGui, hotbar: GuiObject, buttons: ScreenGui, s: number)
	local hbPos, hbSize = hotbar.AbsolutePosition, hotbar.AbsoluteSize
	local bandTop, bandBottom = hbPos.Y - 20 * s, hbPos.Y + hbSize.Y + 4
	local clusterLeft = math.huge
	for _, b in ipairs(buttons:GetChildren()) do
		if b:IsA("GuiObject") then
			local p, sz = b.AbsolutePosition, b.AbsoluteSize
			if p.Y + sz.Y >= bandTop and p.Y <= bandBottom then
				clusterLeft = math.min(clusterLeft, p.X)
			end
		end
	end
	local centred = hbPos.X + hbSize.X / 2
	local center = math.min(centred, clusterLeft - Theme.Layout.HotbarButtonMargin * s - hbSize.X / 2)
	center = math.max(center, hud.AbsolutePosition.X + 8 * s + hbSize.X / 2)
	hotbar.Position = UDim2.new(0.5, math.floor((center - centred) / s + 0.5), 1, 0)
end

local function sampleRows(container: Instance, template: Instance, rows: { { string } })
	for i, r in ipairs(rows) do
		local row = template:Clone() :: any
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Action.Text = r[1]
		row.Key.Label.Text = r[2]
		row.Parent = container
	end
end

local SAMPLE_CONTROLS = {
	{ "Move", "W A S D" }, { "Sprint", "Shift (hold)" }, { "Crouch · slide while sprinting", "C / Ctrl" },
	{ "Jump · vault · climb", "Space" }, { "Attack · use item", "Left click" }, { "Aim · throw the spear", "Right click" },
	{ "Drink from water", "E" }, { "Select item", "1 – 6 · Wheel" }, { "Drop item", "G" }, { "Menu", "M" },
}

local function previewCompass(top: any, heading: number)
	for _, child in ipairs(top.Compass.Ticks:GetChildren()) do
		local a = child:GetAttribute("Angle")
		if a then
			local d = ((a - heading + 540) % 360) - 180
			child.Position = UDim2.new(0.5, d * 2.4, child.Position.Y.Scale, child.Position.Y.Offset)
			child.Visible = math.abs(d) <= 79
			local fade = math.clamp((math.abs(d) - 49) / 26, 0, 1)
			if child:IsA("TextLabel") then
				child.TextTransparency = fade
			else
				local base = child:GetAttribute("BaseTransparency") or 0
				child.BackgroundTransparency = base + (1 - base) * fade
			end
		end
	end
	local spire = top.Compass.Markers.Spire
	spire.Visible = true
	spire.Position = UDim2.new(0.5, (((4 - heading + 540) % 360) - 180) * 2.4, 0, 24)
	spire.Dist.Text = "164 m"
end

local function previewHUD(parent: any, touch: boolean, s: number, viewport: Vector2)
	local C = Theme.Colors
	local hud, fx = parent.HUD, parent.HUDFX
	local root = hud.Root
	applyHudLayout(root, touch, viewport)
	root.Top.Visible = true
	root.Vitals.Visible = true
	root.Hotbar.Visible = true
	local function row(name: string, a: number, low: boolean, extra: string?)
		local r = root.Vitals[name]
		r.Track.Fill.Size = UDim2.fromScale(a, 1)
		r.Track.Ghost.Size = UDim2.fromScale(math.min(1, a + 0.12), 1)
		r.Value.Text = tostring(math.floor(a * 100 + 0.5))
		local text = string.upper(name) .. (if extra then "  " .. extra else "")
		if low then
			text ..= string.format("  <font color=\"%s\">LOW</font>", Theme.hex(C.Danger))
			r.Track.Fill.BackgroundTransparency = 0.3
		end
		r.Label.Text = text
	end
	row("Health", 0.72, false, string.format("<font color=\"%s\">ARMOR 15%%</font>", Theme.hex(C.Armor)))
	root.Vitals.Health.ArmorLine.Visible = true
	row("Hunger", 0.56, false)
	row("Thirst", 0.19, true)
	row("Stamina", 0.64, false)
	root.Vitals.Stamina.Track.Ghost.Visible = false
	previewCompass(root.Top, 20)
	root.Top.Info.Timer.Text = "11:42"
	root.Top.Info.Remain.Text = "<b>17</b> REMAIN"
	root.Top.Event.Visible = true
	root.Top.Event.Text = "THE BORDER MOVES IN 0:42"
	local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
	local items = { { "bow", 1 }, { "arrow", 14 }, { "knife", 1 }, { "apple", 3 }, { "bandage", 2 }, false }
	for i, it in ipairs(items) do
		local slot = root.Hotbar.Slots:FindFirstChild("Slot" .. i)
		if slot and it then
			local card = slot.Card
			local def = ItemDefs.get(it[1])
			card.Count.Text = if it[2] > 1 then tostring(it[2]) else ""
			card.Rarity.Visible = true
			card.Rarity.BackgroundColor3 = Theme.Rarity[def.rarity]
			previewIcon(card.Viewport, it[1])
		elseif slot then
			slot.Card.BackgroundTransparency = 0.64
		end
	end
	local selected = root.Hotbar.Slots.Slot1.Card
	selected.Position = UDim2.fromOffset(0, -5)
	selected.BackgroundColor3 = C.PanelLight
	selected.BackgroundTransparency = 0.2
	selected.Stroke.Color = C.Text
	selected.Stroke.Transparency = 0.12
	selected.Stroke.Thickness = 1.5
	selected.Key.TextColor3 = C.Text
	root.Hotbar.ItemName.GroupTransparency = 0
	root.Hotbar.ItemName.Title.Text = "Recurve Bow"
	root.Hotbar.ItemName.Sub.Text = string.format("<font color=\"%s\">RARE</font>   ·   RANGED", Theme.hex(Theme.Rarity.Rare))
	local dim = Theme.hex(C.TextDim)
	local entries = {
		{ string.format("<b>Kestrel</b>  <font color=\"%s\">Recurve Bow</font>  <b>Ana</b>", dim), false },
		{ string.format("<font color=\"%s\"><b>You</b></font>  <font color=\"%s\">Hunting Knife</font>  <b>Bo</b>", Theme.hex(C.AccentSoft), dim), true },
		{ string.format("<b>Moss</b>  <font color=\"%s\">starved</font>", dim), false },
	}
	for i, e in ipairs(entries) do
		local entry = root.Templates.KillEntry:Clone()
		entry.Name = "Kill" .. i
		entry.LayoutOrder = i
		entry.Text.Text = e[1]
		entry.Mark.Visible = e[2]
		entry.BackgroundTransparency = if e[2] then 0.25 else 0.42
		entry.Parent = root.KillFeed
	end
	local center = fx.Root.Center
	center.Crosshair.Visible = true
	center.Crosshair.Up.Position = UDim2.fromOffset(0, -9)
	center.Crosshair.Down.Position = UDim2.fromOffset(0, 9)
	center.Crosshair.Left.Position = UDim2.fromOffset(-9, 0)
	center.Crosshair.Right.Position = UDim2.fromOffset(9, 0)
	center.Draw.Visible = true
	center.Draw.Fill.Size = UDim2.fromScale(0.62, 1)
	center.Interact.Visible = true
	center.Interact.GroupTransparency = 0
	center.Interact.Key.Visible = not touch
	center.Interact.Text.Text = "Drink"
	hud.Enabled = true
	fx.Enabled = true
	if touch then
		parent.Menu.Root.Launcher.Visible = true
		parent.Menu.Enabled = true
		local buttons = previewTouchButtons(parent, viewport)
		task.wait()
		task.wait()
		clearHotbarOf(hud, root.Hotbar, buttons, s)
	end
end

local function previewLobby(parent: any, touch: boolean)
	local root = parent.Lobby.Root
	root.Status.Pill.Text.Text = "NEXT ROUND IN   <b>0:12</b>"
	root.Status.Bar.Visible = true
	root.Status.Bar.Fill.Size = UDim2.fromScale(0.5, 1)
	local cells = root.Brand.Stats.Cells
	cells.Wins.Value.Text, cells.Kills.Value.Text, cells.Rounds.Value.Text = "3", "41", "27"
	sampleRows(root.HowTo.Body.Controls, root.Templates.ControlRow, SAMPLE_CONTROLS)
	root.HowTo.Body.ControlsHeader.Text = "CONTROLS  ·  KEYBOARD & MOUSE"
	if touch then
		root.Brand.AnchorPoint = Vector2.zero
		root.Brand.Position = UDim2.new()
		root.Brand.Layout.VerticalAlignment = Enum.VerticalAlignment.Top
		root.Brand.Title.TextSize = 28
		root.Brand.Title.Size = UDim2.new(1, 0, 0, 34)
		root.HowTo.Visible = false
	end
	parent.Lobby.Enabled = true
end

local function previewMenu(parent: any)
	local gui = parent.Menu
	local root = gui.Root
	gui.Dim.Visible = true
	gui.Dim.BackgroundTransparency = Theme.Transparency.Dim
	root.Panel.Visible = true
	root.Panel.GroupTransparency = 0
	local list = root.Panel.Pages.Settings
	local samples = {
		{ "CAMERA" }, { "Field of view", 0.33, "80°" }, { "Look sensitivity", 0.29, "1.00" }, { "Head bob", 1, "100%" },
		{ "Camera shake", 0.7, "70%" }, { "AUDIO" }, { "Music volume", 0.6, "60%" }, { "Effects volume", 1, "100%" },
		{ "Ambience volume", 0.8, "80%" },
	}
	for i, sample in ipairs(samples) do
		if #sample == 1 then
			local section = root.Templates.Section:Clone()
			section.Text = sample[1]
			section.LayoutOrder = i
			section.Parent = list
		else
			local row = root.Templates.SliderRow:Clone()
			row.LayoutOrder = i
			row.Label.Text = sample[1]
			row.Value.Text = sample[3]
			row.Track.Fill.Size = UDim2.fromScale(sample[2], 1)
			row.Track.Knob.Position = UDim2.fromScale(sample[2], 0.5)
			if i == 2 then
				row.BackgroundTransparency = 0.62
				row.Value.TextColor3 = Theme.Colors.Text
			end
			row.Parent = list
		end
	end
	gui.Enabled = true
end

local function previewOverlay(parent: any, which: string)
	local C = Theme.Colors
	local gui = parent.Overlay
	local root = gui.Root
	if which == "Death" then
		gui.Dim.BackgroundTransparency = 0.45
		root.Death.Visible = true
		root.Death.Panel.GroupTransparency = 0
		root.Death.Panel.Title.Text = string.format("#7<font size=\"30\" color=\"%s\">   OF 24</font>", Theme.hex(C.TextDim))
		root.Death.Panel.Cause.Text = "Eliminated by <b>Kestrel</b>   ·   Recurve Bow"
		root.Death.Panel.Note.Text = "Watch the contenders who remain"
	elseif which == "Victory" then
		gui.Dim.BackgroundTransparency = 0.5
		local panel = root.Victory.Panel
		root.Victory.Visible = true
		panel.GroupTransparency = 0
		panel.Eyebrow.Text = "THE LAST ONE STANDING"
		panel.Title.Text = "VICTORY"
		panel.Title.TextColor3 = C.Gold
		panel.Sub.Text = "You outlasted 23 contenders   ·   <b>5</b> eliminations"
		panel.Summary.Visible = true
		local people = { { "You", 5 }, { "Kestrel", 4 }, { "Ana", 2 }, { "Moss", 1 }, { "Bo", 3 }, { "Wren", 0 }, { "Juniper", 1 }, { "Ash", 0 } }
		for i, p in ipairs(people) do
			local row = root.Templates.SummaryRow:Clone()
			row.LayoutOrder = i
			row.Rank.Text = "#" .. i
			row.Rank.TextColor3 = if i == 1 then C.Gold else C.TextDim
			row.PlayerName.Text = p[1] .. (if i == 1 then string.format("  <font color=\"%s\">YOU</font>", Theme.hex(C.AccentSoft)) else "")
			row.PlayerName.FontFace = if i == 1 then Theme.Fonts.BodyBold else Theme.Fonts.Body
			row.Kills.Text = tostring(p[2])
			row.Mark.Visible = i == 1
			row.BackgroundTransparency = if i == 1 then 0.55 else 1
			row.Parent = panel.Summary.Rows
		end
		panel.Summary.Footer.Text = "ROUND TIME  12:31     ·     24 CONTENDERS"
	elseif which == "Countdown" then
		root.Countdown.Visible = true
		root.Countdown.Number.Text = "3"
		root.Countdown.Caption.Text = "STAY ON YOUR PLINTH"
	elseif which == "RollCall" then
		local roll = root.RollCall
		roll.Visible = true
		roll.GroupTransparency = 0
		roll.Title.Text = "THE FALLEN"
		roll.Sub.Text = "7 contenders have fallen"
		for i, n in ipairs({ "Bo", "Moss", "Wren", "Juniper", "Ash", "Rowan", "Sable" }) do
			local l = root.Templates.RollName:Clone()
			l.Text = n
			l.LayoutOrder = i
			l.TextTransparency = if i <= 5 then 0 else 0.6
			l.Parent = roll.Names
		end
		roll.Size = UDim2.new(1, -40, 0, 172)
	elseif which == "Headline" then
		local h = root.Headline
		h.Visible = true
		h.GroupTransparency = 0
		h.Eyebrow.Text = "WARNING"
		h.Eyebrow.TextColor3 = C.Warning
		h.Rule.BackgroundColor3 = C.Warning
		h.Title.Text = "THE BORDER IS CLOSING"
		h.Sub.Text = "It starts moving in 30 seconds. Head for the Spire."
		for i, t in ipairs({ { "The border has closed", "Outside it, you won't last long" }, { "Inventory full", "" } }) do
			local toast = root.Templates.Toast:Clone()
			toast.LayoutOrder = i
			toast.Text.Text = t[1]
			toast.Sub.Text = t[2]
			toast.Sub.Visible = t[2] ~= ""
			toast.Parent = root.Toasts
		end
	end
	gui.Enabled = true
end

local function previewSpectate(parent: any)
	local root = parent.Spectate.Root
	local card = root.Card
	card.Visible = true
	card.GroupTransparency = 0
	card.Info.PlayerName.Text = "Kestrel"
	card.Info.Sub.Text = "@kestrel_wing   ·   <b>4</b> KILLS"
	card.Info.Health.Fill.Size = UDim2.fromScale(0.64, 1)
	root.Exit.Visible = true
	root.Exit.Text = "EXIT SPECTATING   <font transparency=\"0.45\">BACKSPACE</font>"
	parent.Spectate.Enabled = true
	local top = parent.HUD.Root.Top
	top.Visible = true
	previewCompass(top, 300)
	top.Info.Timer.Text = "06:10"
	top.Info.Remain.Text = "<b>4</b> REMAIN"
	parent.HUD.Enabled = true
end

-- which: "HUD" | "Lobby" | "Menu" | "Death" | "Victory" | "Countdown" | "RollCall" | "Headline" | "Spectate"
function UIBuilder.preview(which: string, opts: { [string]: any }?): string
	local o = opts or {}
	UIBuilder.build(o)
	local parent = o.parent or StarterGui
	local s, viewport = fitRoots(parent)
	local touch = o.touch == true
	if which == "HUD" then
		previewHUD(parent, touch, s, viewport)
	elseif which == "Lobby" then
		previewLobby(parent, touch)
	elseif which == "Menu" then
		previewMenu(parent)
	elseif which == "Spectate" then
		previewSpectate(parent)
	elseif which == "Countdown" or which == "RollCall" then
		previewHUD(parent, touch, s, viewport)
		previewOverlay(parent, which)
	else
		previewOverlay(parent, which)
	end
	return string.format("previewing %s at %dx%d, scale %.2f", which, viewport.X, viewport.Y, s)
end

return UIBuilder
