--[[
	UIBuilder - edit-time builder for every ScreenGui the UI system owns (in StarterGui), in the "Quiet" style
	(docs/design/ui/StyleA_Quiet/README.md; tokens in Shared.Theme, parts from Shared.QuietUI).
	Re-runnable: build() replaces HUD, HUDFX, Lobby, Overlay, Menu and Spectate.

	Run it from a COPY of this module, with fresh copies of Theme, QuietUI and Config, so that Studio's module cache
	cannot serve an old builder or an old theme (Edit mode):
	  return require(game.ServerStorage.WorldGen.UIBuilder:Clone()).buildFresh()
	  return require(game.ServerStorage.WorldGen.UIBuilder:Clone()).previewFresh("HUD")  -- sample content + enabled
	     ("HUD" | "Lobby" | "Death" | "Strip" | "Victory" | "Menu" | "Spectate" | "Countdown" | "RollCall" | "Headline";
	      previewFresh("HUD", { touch = true }) adds look-alike touch buttons)
	  return require(game.ServerStorage.WorldGen.UIBuilder:Clone()).buildFresh()          -- back to clean + disabled
	build(opts) and preview(which, opts) are the same with the modules you hand them
	(opts = { Theme = , QuietUI = , Config = , parent = }); without opts they require Shared's own.

	The Lobby screen's three HOW TO PLAY tips and its one-line goal are written from the arena in the place
	(Shared.Lore's names for Config.Map, the border's time from Shared.ThreatLine). After Config.Map changes, write
	them again. Either only the tips, in place:
	  return require(game.ServerStorage.WorldGen.UIBuilder:Clone()).applyTips()
	or every screen from scratch (buildFresh, above).

	Every ScreenGui is Enabled = false at edit time; the client controllers enable them at runtime.
	The instance names below are the controllers' contract (StarterPlayerScripts.Client.Controllers):
	  HUD + HUDFX -> HUDController, Lobby -> LobbyController (and PlusController), Overlay -> NotificationController,
	  Menu -> SettingsController, Spectate -> SpectateController.
	Every ScreenGui has Root (Frame) > Scale (UIScale) [and SafePad (UIPadding)]; Theme.bindRoot keeps it fitted.
	Design size is 1280x720 at scale 1. Text is never below 13 px.

	The Quiet rules this builder keeps:
	  * No panels or boxes. Text, lines and icons sit on the picture; every text has the dark stroke "Shadow".
	    A label whose text is faded on its own must have its stroke faded with it (QuietUI.fadeText).
	  * One ink colour. Sun only for "look at this". Red only for a danger state (low health, the border, defeat).
	    Nothing red is a hit effect: the hurt flash and the low-health edge are a neutral dark edge.
	  * Parts that are NEW with this style are built hidden (Visible = false) and do nothing until a controller
	    shows them. They are listed with "NEW" where they are built.
]]
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIBuilder = {}
UIBuilder.Names = { "HUD", "HUDFX", "Lobby", "Overlay", "Menu", "Spectate" }

local Theme: any
local Config: any
local Quiet: any

-- The arena's own names and the border's time, from fresh copies of Config, Lore and ThreatLine side by side:
-- Studio caches a required module for the whole session, and a lone copy of Lore would not find Config beside it.
local function arenaWords(): (any, any)
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local box = Instance.new("Folder")
	local lore: any = nil
	local threat: any = nil
	pcall(function()
		for _, moduleName in ipairs({ "Config", "Lore", "ThreatLine" }) do
			shared:WaitForChild(moduleName):Clone().Parent = box
		end
		lore = require(box:FindFirstChild("Lore") :: any)
		threat = require(box:FindFirstChild("ThreatLine") :: any)
	end)
	box:Destroy()
	return lore, threat
end

-- three short tips (P3: say less), so the control rows from Aim up show without scrolling at 720 px tall. They are
-- baked into the Lobby screen, so they are written from the arena in the place when the screens are built: the names
-- from Shared.Lore (the Spire, or the Horn on Map 1; the start signal's word), the border's time from Shared.ThreatLine
-- ("the second morning" in the forest; a full ring on Map 1 first moves on "the first evening"). Rebuild the Lobby
-- screen after Config.Map changes.
local function tips(): { string }
	local lore, threat = arenaWords()
	local function name(key: string, fallback: string): string
		local value = lore and lore[key]
		return if type(value) == "string" and value ~= "" then value else fallback
	end
	local when = "the second morning"
	if threat and type(threat.dayPart) == "function" and type(threat.fullRingMovesAt) == "function" then
		local ok, words = pcall(function()
			return threat.dayPart(threat.fullRingMovesAt())
		end)
		if ok and type(words) == "string" and words ~= "" then
			when = words
		end
	end
	return {
		string.format("Last one standing wins. At %s, rush %s for gear, or run for a %s under a pale flag.",
			name("StartSignal", "the horn"), name("Spire", "the Spire"), name("RunnerCache", "runner's cache")),
		"Keep hunger and thirst above 55 and your health comes back. Drink from streams and the lake.",
		string.format("From %s %s closes in on %s. Stay inside it.", when, name("Border", "the border"), name("Spire", "the Spire")),
	}
end

-- the goal in one line at the top of HOW TO PLAY (QW6), in the arena's own names (the Spire, or the Horn on Map 1).
-- LobbyController writes the same line from Shared.Lore at runtime.
local function steps(): string
	local lore = arenaWords()
	local function upper(key: string, fallback: string): string
		local value = lore and lore[key]
		return string.upper(if type(value) == "string" and value ~= "" then value else fallback)
	end
	return string.format("RISE ON YOUR PLATE  →  TAKE GEAR AT %s, OR RUN  →  OUTLAST %s", upper("Spire", "the Spire"), upper("Border", "the border"))
end

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

-- A Quiet label: ink, clear, with the dark stroke "Shadow" (props.Stroke = false for none). fontKey is a
-- Theme.Fonts key. Parent is set after the children are in.
local function label(name: string, text: string, fontKey: string, size: number, props: { [string]: any }?, children: { Instance }?): any
	local p = props or {}
	local parent = p.Parent
	p.Parent = nil
	p.Name = name
	p.Text = text
	p.Font = fontKey
	p.TextSize = size
	local l = Quiet.label(p)
	if children then
		for _, child in ipairs(children) do
			child.Parent = l
		end
	end
	if parent then
		l.Parent = parent
	end
	return l
end

-- A Quiet text button: SemiBold capitals with no box, an "Under" line for hover and focus (QuietUI.bindButton), a
-- UIPadding "Pad". It grows sideways with its text unless props.AutomaticSize says otherwise.
local function textButton(name: string, text: string, fontKey: string, size: number, props: { [string]: any }?, children: { Instance }?): any
	local p = props or {}
	local parent = p.Parent
	p.Parent = nil
	p.Name = name
	p.Text = text
	p.Font = fontKey
	p.TextSize = size
	local b = Quiet.button(p)
	if children then
		for _, child in ipairs(children) do
			child.Parent = b
		end
	end
	if parent then
		b.Parent = parent
	end
	return b
end

-- A button that is not text (a hotbar cell, the menu launcher, a slider row): no look of its own.
local function plainButton(name: string, props: { [string]: any }?, children: { Instance }?): any
	local p = props or {}
	p.Name = name
	p.Text = ""
	p.AutoButtonColor = false
	p.BorderSizePixel = 0
	if p.BackgroundColor3 == nil then
		p.BackgroundColor3 = Theme.Colors.Shade
	end
	if p.BackgroundTransparency == nil then
		p.BackgroundTransparency = 1
	end
	return new("TextButton", p, children)
end

local function corner(radius: UDim?): UICorner
	return new("UICorner", { CornerRadius = radius or Theme.Corner })
end

-- a thin dark edge around a small ink shape (a marker, a knob), so it holds over a bright sky
local function edge(transparency: number?): UIStroke
	return new("UIStroke", {
		Name = "Edge",
		Color = Theme.Colors.Shade,
		Transparency = transparency or 0.5,
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

-- a 1 px rule in ink with its shade under it
local function hair(name: string, props: { [string]: any }?): any
	local p = props or {}
	p.Name = name
	return Quiet.line(p)
end

-- a key square: Frame > Stroke, Pad, Label (the letter)
local function key(name: string, text: string, props: { [string]: any }?): any
	local p = props or {}
	p.Name = name
	p.Text = text
	return Quiet.key(p)
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
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Colors.Ink,
		ScrollBarImageTransparency = 0.5,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Selectable = false,
		Parent = parent,
	}, children)
end

-- Where a panel's box used to be. Quiet has no box, so it is clear; it stays because the controllers set it Active
-- (clicks on a sheet do not reach the world).
local function canvasBg(parent: Instance)
	return frame("Bg", {
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = Theme.Colors.Shade,
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = parent,
	})
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
		local pad = padding(Theme.Padding, Theme.Padding, Theme.Padding, Theme.Padding)
		pad.Name = "SafePad"
		pad.Parent = root
	end
	root.Parent = gui
	return gui, root
end

-- One line of a control list: the action at the left, its key square at the right.
local function controlRow(parent: Instance)
	local row = frame("ControlRow", { Size = UDim2.new(1, 0, 0, 30), Parent = parent })
	label("Action", "Action", "Medium", 14, { Size = UDim2.new(0.5, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
	key("Key", "KEY", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -2, 0.5, 0), Parent = row })
	return row
end

------------------------------------------------------------------------------------------------
-- HUD (arena): compass, the round's facts, kill feed, vitals, hotbar
------------------------------------------------------------------------------------------------
local COMPASS_WIDTH = 360 -- design px; HUDController's COMPASS_WIDTH must match
local COMPASS_LINE_Y = 26 -- the compass line: letters above it, markers hanging under it
local MARKER_Y = 24 -- HUDController places every marker at this y inside Markers...
local MARKERS_DROP = 13 -- ...and Markers sits this far down, so a marker's middle is 11 px under the line

local function buildHUD(): ScreenGui
	local gui, root = screen("HUD", 10)
	local C = Theme.Colors
	local B = Theme.Bar

	-- Top centre: the compass, then one line of facts, then the event line (or the border alert in its place)
	local top = frame("Top", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(COMPASS_WIDTH, 126), Visible = false, Parent = root })
	-- (not clipped: HUDController hides what leaves the ribbon, and a distance under a marker at the ribbon's end
	-- must not be cut)
	local compass = frame("Compass", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(COMPASS_WIDTH, 62),
		ClipsDescendants = false,
		Parent = top,
	})
	compass:SetAttribute("Width", COMPASS_WIDTH)
	hair("Baseline", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, COMPASS_LINE_Y),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundTransparency = 0.4,
		Parent = compass,
	})
	local ticks = frame("Ticks", { Size = UDim2.fromScale(1, 1), Parent = compass })
	for angle = 0, 345, 15 do
		local major = angle % 45 == 0
		local t = frame(string.format("T%03d", angle), {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, COMPASS_LINE_Y),
			Size = UDim2.fromOffset(1, if major then 8 else 4),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = if major then 0.05 else 0.45,
			Parent = ticks,
		})
		t:SetAttribute("Angle", angle)
		t:SetAttribute("BaseTransparency", t.BackgroundTransparency)
	end
	local directions = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
	for angle, text in pairs(directions) do
		local cardinal = angle % 90 == 0
		-- (a far letter is dimmed by its colour: HUDController drives the letters' transparency every frame)
		local l = label("L" .. text, text, "Medium", 13, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.fromOffset(34, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if cardinal then C.Ink else C.Ink2,
			Parent = ticks,
		})
		l:SetAttribute("Angle", angle)
		l:SetAttribute("BaseTransparency", 0)
	end

	-- Markers hang under the line. Each is a small ink shape with its distance; HUDController moves them.
	local markers = frame("Markers", { Position = UDim2.fromOffset(0, MARKERS_DROP), Size = UDim2.fromScale(1, 1), Parent = compass })
	local function distance(parent: Instance, color: Color3)
		return label("Dist", "", "Mono", Theme.TextSize.Number, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 1),
			Size = UDim2.fromOffset(64, 14),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = color,
			RichText = true,
			Parent = parent,
		})
	end
	local spire = frame("Spire", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, MARKER_Y), Size = UDim2.fromOffset(14, 14), Visible = false, Parent = markers })
	frame("Diamond", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(7, 7),
		Rotation = 45,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0,
		Parent = spire,
	}, { edge(0.45) })
	distance(spire, C.Ink)
	-- the way back in, only while you are outside the border
	local border = frame("Border", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, MARKER_Y), Size = UDim2.fromOffset(14, 14), Visible = false, Parent = markers })
	frame("Ring", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = C.Red,
		BackgroundTransparency = 0,
		Parent = border,
	}, { corner(Theme.CornerPill), edge(0.4) })
	-- water for the thirsty (QW10, Guidance): a drop in Sun with its distance. (Tip and Bulb are the drop; their shade
	-- copies sit 1 px lower and behind, so the two parts show no seam.)
	local water = frame("Water", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, MARKER_Y), Size = UDim2.fromOffset(16, 16), Visible = false, Parent = markers })
	for _, part in ipairs({ { "TipShade", C.Shade, 0.5, 1, 1 }, { "Tip", C.Sun, 0, 0, 2 } }) do
		frame(part[1], {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -2 + part[4]),
			Size = UDim2.fromOffset(5, 5),
			Rotation = 45,
			BackgroundColor3 = part[2],
			BackgroundTransparency = part[3],
			ZIndex = part[5],
			Parent = water,
		})
	end
	for _, part in ipairs({ { "BulbShade", C.Shade, 0.5, 1, 1 }, { "Bulb", C.Sun, 0, 0, 2 } }) do
		frame(part[1], {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 1.5 + part[4]),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = part[2],
			BackgroundTransparency = part[3],
			ZIndex = part[5],
			Parent = water,
		}, { corner(Theme.CornerPill) })
	end
	distance(water, C.Sun)
	-- the border's nearest edge while it moves (QW10): a thin red tick; the distance is in the Info row ("BORDER 42 m")
	local edgeMarker = frame("Edge", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, MARKER_Y), Size = UDim2.fromOffset(10, 14), Visible = false, Parent = markers })
	frame("Tick", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 12),
		BackgroundColor3 = C.Red,
		BackgroundTransparency = 0,
		Parent = edgeMarker,
	}, { edge(0.4) })
	-- where you are looking: a short upright stroke across the line
	frame("Notch", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, COMPASS_LINE_Y),
		Size = UDim2.fromOffset(2, 14),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0,
		ZIndex = 3,
		Parent = compass,
	}, { edge(0.5) })

	-- One line under the compass. On a touch screen it carries the round's facts; on a desktop they are in Facts
	-- (top right) and this line is left with PRACTICE and the border's distance.
	local info = frame("Info", { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 20), Parent = top }, {
		list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	label("Timer", "", "Mono", 14, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 1, Parent = info })
	frame("Dot", { Size = UDim2.fromOffset(3, 3), BackgroundColor3 = C.Ink2, BackgroundTransparency = 0, LayoutOrder = 2, Parent = info }, { corner(Theme.CornerPill) })
	label("Remain", "", "Medium", 14, { RichText = true, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 3, Parent = info })
	label("Practice", "PRACTICE", "SemiBold", 13, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C.Ink2,
		LayoutOrder = 4,
		Visible = false,
		Parent = info,
	})
	-- QW10: how far the border's edge is, while it moves and you're within 80 m of it; a tick on the ribbon points at it
	label("Border", "", "SemiBold", 13, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C.Red,
		LayoutOrder = 5,
		Visible = false,
		Parent = info,
	})
	label("Event", "", "SemiBold", 13, {
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Sun,
		RichText = true,
		Visible = false,
		Parent = top,
	})
	-- shares the event line's slot: when you're outside the border the alert replaces the event line
	local alert = frame("Alert", { Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 0, 38), Visible = false, Parent = top })
	label("Title", "Outside the border", "Medium", 16, { Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, Parent = alert })
	label("Sub", "", "Medium", 13, {
		Position = UDim2.fromOffset(0, 21),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		RichText = true,
		Parent = alert,
	})

	-- NEW. The round's facts, top right (desktop: Theme.Layout[...].Facts): "17 left", then one small line (the day
	-- and the time, or the round clock). Row > Count (the big light number), Word ("left"); Sub (the small line).
	local facts = frame("Facts", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(240, 60), Visible = false, Parent = root })
	local factsRow = frame("Row", { Size = UDim2.new(1, 0, 0, 40), Parent = facts }, {
		list(Enum.FillDirection.Horizontal, 7, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom),
	})
	label("Count", "", "Light", Theme.TextSize.Count, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 1, Parent = factsRow })
	-- (the small word sits on the big number's baseline: 5 px of room under it)
	label("Word", "left", "Medium", 14, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = 2,
		Parent = factsRow,
	}, { padding(0, 0, 0, 5) })
	label("Sub", "", "Medium", 13, {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		RichText = true,
		Parent = facts,
	})

	-- Kill feed (top right on desktop, under Facts; the controller moves it on touch screens)
	local feedLayout = Theme.Layout.Desktop.KillFeed
	frame("KillFeed", { AnchorPoint = feedLayout.anchor, Position = feedLayout.position, Size = feedLayout.size, Parent = root }, {
		list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top),
	})

	-- Vitals (bottom left on desktop, top left on touch screens): slim lines, an icon at the left, the number at the
	-- right. Each row: Icon, Track > Under, Ghost, Fill [, Tick], Value, and Label (a note beside the number: the
	-- armour's share on the health row; empty otherwise).
	local vitalsLayout = Theme.Layout.Desktop.Vitals
	local vitals = frame("Vitals", { AnchorPoint = vitalsLayout.anchor, Position = vitalsLayout.position, Size = vitalsLayout.size, Visible = false, Parent = root }, {
		list(Enum.FillDirection.Vertical, B.RowGap, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom),
	})
	local LEFT, RIGHT = B.Icon + B.Gap, B.ValueWidth + B.Gap -- the line's insets in a row
	local function statRow(name: string, icon: string?, order: number, barHeight: number, tick: number?)
		local row = Quiet.bar({ Name = name, Icon = icon, Height = barHeight, Tick = tick, LayoutOrder = order })
		row.Value.Text = "100"
		if not icon then
			-- no icon, but the line still starts where the others do
			row.Track.Position = UDim2.new(0, LEFT, 0.5, 0)
			row.Track.Size = UDim2.new(1, -(LEFT + RIGHT), 0, barHeight)
		end
		label("Label", "", "SemiBold", 13, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, 10, 0.5, 0),
			Size = UDim2.new(0, 190, 1, 0),
			TextColor3 = C.Ink2,
			RichText = true,
			Parent = row,
		})
		row.Parent = vitals
		return row
	end
	local regenTick = math.clamp((tonumber(Config.Survival and Config.Survival.RegenMinStat) or 55) / 100, 0, 1)
	local health = statRow("Health", "heart", 1, B.HealthHeight)
	-- armour: a second, thinner line right under the health line
	frame("ArmorLine", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, LEFT, 0.5, 5),
		Size = UDim2.new(1, -(LEFT + RIGHT), 0, 1),
		BackgroundColor3 = C.Ink2,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = health,
	})
	-- a slow sweep over the health line while health comes back (HUDController moves the gradient). On an ink line
	-- a light sweep would not show, so the band is the dim tone.
	local shimmer = frame("Shimmer", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink2,
		BackgroundTransparency = 0,
		ZIndex = 3,
		Visible = false,
		Parent = health.Track.Fill,
	})
	gradient(0, seq({ { 0, 1 }, { 0.34, 1 }, { 0.5, 0 }, { 0.66, 1 }, { 1, 1 } })).Parent = shimmer
	-- why health isn't coming back (QW5): "NOT HEALING · THIRSTY". Plain text; the reason word takes Sun, and the
	-- whole line Red when a meter is empty (HUDController).
	label("Reason", "", "SemiBold", 13, {
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		RichText = true,
		LayoutOrder = 2,
		Visible = false,
		Parent = vitals,
	})
	-- the tick on Hunger and Thirst is the healing line: health only comes back while both are above
	-- Config.Survival.RegenMinStat (HUDController places it from Config too)
	statRow("Hunger", "food", 3, B.Height, regenTick)
	statRow("Thirst", "drop", 4, B.Height, regenTick)
	-- stamina shows only while it is in use: no icon, and no shade line (HUDController fades the line itself)
	local stamina = statRow("Stamina", nil, 5, B.Height)
	stamina.Track.Under:Destroy()

	-- Hotbar (bottom centre): no slot boxes. Each cell: Card (clear) > Stroke (clear), Viewport (the item's own 3D
	-- picture), Fallback, Key (the slot's number, under the picture), Count (at the picture's lower right), Rarity,
	-- and NEW: Under (the line under the cell in hand) and Ring (the small ring of an empty cell).
	local slots = Config.Inventory.Slots
	local SLOT, GAP = Theme.Layout.Desktop.SlotSize, Theme.Layout.SlotGap
	local ICON = Theme.Layout.IconSize
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
		local slot = plainButton("Slot" .. i, {
			Size = UDim2.fromOffset(SLOT, SLOT),
			LayoutOrder = i,
			Selectable = false,
			Parent = row,
		})
		local card = frame("Card", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Shade, BackgroundTransparency = 1, Parent = slot })
		new("UIStroke", {
			Name = "Stroke",
			Color = C.Ink,
			Transparency = 1,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = card,
		})
		-- the picture stands on the cell's top ICON px and grows up and out when it is the one in hand
		-- (Theme.Layout.IconSelected). HUDController clears every child of the viewport: nothing else lives in it.
		new("ViewportFrame", {
			Name = "Viewport",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, ICON),
			Size = UDim2.fromOffset(ICON, ICON),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(150, 150, 150),
			LightColor = Color3.fromRGB(255, 242, 228),
			LightDirection = Vector3.new(-0.55, -1, -0.65),
			Parent = card,
		})
		local ring = frame("Ring", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, ICON / 2 + 6),
			Size = UDim2.fromOffset(8, 8),
			Visible = false,
			Parent = card,
		}, { corner(Theme.CornerPill) })
		new("UIStroke", { Name = "Ink", Color = C.Ink, Transparency = 0.25, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = ring })
		label("Fallback", "", "SemiBold", 13, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, ICON / 2),
			Size = UDim2.new(1, -4, 0, ICON - 6),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			TextColor3 = C.Ink2,
			Visible = false,
			Parent = card,
		})
		label("Key", tostring(i), "Mono", Theme.TextSize.Number, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.fromOffset(20, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Ink2,
			ZIndex = 3,
			Parent = card,
		})
		label("Count", "", "Mono", Theme.TextSize.Number, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 2, 0, ICON + 2),
			Size = UDim2.fromOffset(34, 14),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
			Parent = card,
		})
		frame("Rarity", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(14, 2),
			BackgroundColor3 = C.Ink2,
			BackgroundTransparency = 0,
			Visible = false,
			ZIndex = 3,
			Parent = card,
		})
		frame("Under", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(22, 2),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0,
			Visible = false,
			ZIndex = 4,
			Parent = card,
		}, { edge(0.55) })
	end
	local itemName = canvas("ItemName", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(400, 42),
		GroupTransparency = 1,
		Parent = hotbar,
	})
	label("Title", "", "Medium", 16, { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, Parent = itemName })
	label("Sub", "", "SemiBold", 13, {
		Position = UDim2.fromOffset(0, 23),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Ink2,
		RichText = true,
		Parent = itemName,
	})
	-- the item's description, for its first few pickups (QW2; HUDController grows the toast to 60 px for it)
	label("Desc", "", "Medium", 14, {
		Position = UDim2.fromOffset(0, 41),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = itemName,
	})
	-- gamepad: the shoulder buttons that step through the cells, as key squares at the hotbar's ends
	key("PrevHint", "LB", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -8, 1, -SLOT / 2), Visible = false, Parent = hotbar })
	key("NextHint", "RB", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, 8, 1, -SLOT / 2), Visible = false, Parent = hotbar })

	-- Templates
	local templates = frame("Templates", { Visible = false, Parent = root })
	-- one kill-feed line: plain text, no box. Mark is a small Sun bar for a line you are part of.
	local entry = frame("KillEntry", {
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Shade,
		BackgroundTransparency = 1,
		Parent = templates,
	}, {
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	frame("Mark", { Size = UDim2.fromOffset(2, 12), BackgroundColor3 = C.Sun, BackgroundTransparency = 0, LayoutOrder = 1, Visible = false, Parent = entry })
	label("Text", "", "Medium", 14, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), RichText = true, LayoutOrder = 2, Parent = entry })
	return gui
end

------------------------------------------------------------------------------------------------
-- HUDFX (full bleed, true screen centre): screen edges, crosshair, hit/damage markers, use ring, draw meter, hints
------------------------------------------------------------------------------------------------
local function buildHUDFX(): ScreenGui
	local gui, root = screen("HUDFX", 9, true, false)
	local C = Theme.Colors
	local T = Theme.Transparency
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
	-- No red hit effects (the age rating's "Mild" condition). The hurt flash and the low-health edge are a neutral
	-- dark edge, built that way here. Low health shows as the health line turning Red (a state, not a flash).
	-- Only the border has a red edge: being outside it is a danger state.
	edges("LowHealth", C.Shade, 0.34)
	edges("Border", C.Red, 0.38)
	edges("Hurt", C.Shade, 0.26)
	-- NEW. The Quiet border warning: a 2 px Red line just inside the screen's edge, for while you are outside.
	local borderLine = frame("BorderLine", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		Visible = false,
		ZIndex = 1,
		Parent = gui,
	})
	new("UIStroke", { Name = "Stroke", Color = C.Red, Transparency = 0.1, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = borderLine })

	local center = frame("Center", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), Parent = root })

	-- crosshair: a dot, and spread lines for a bow or a throw
	local cross = frame("Crosshair", { Size = UDim2.fromOffset(0, 0), Visible = false, Parent = center })
	frame("Dot", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0,
		Parent = cross,
	}, { corner(Theme.CornerPill), edge(0.45) })
	-- NEW. The thin ring around the dot (for a hand or a blade; not with the spread lines).
	local crossRing = frame("Ring", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(19, 19), Visible = false, Parent = cross })
	local ringShade = frame("Shade", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 1, 1, 1), ZIndex = 1, Parent = crossRing }, { corner(Theme.CornerPill) })
	new("UIStroke", { Name = "Stroke", Color = C.Shade, Transparency = 0.72, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = ringShade })
	local ringLine = frame("Line", { Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = crossRing }, { corner(Theme.CornerPill) })
	new("UIStroke", { Name = "Stroke", Color = C.Ink, Transparency = 0.45, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = ringLine })
	local function line(name: string, anchor: Vector2, position: UDim2, size: UDim2)
		frame(name, { AnchorPoint = anchor, Position = position, Size = size, BackgroundColor3 = C.Ink, BackgroundTransparency = 0.05, Parent = cross }, { edge(0.55) })
	end
	line("Up", Vector2.new(0.5, 1), UDim2.fromOffset(0, -6), UDim2.fromOffset(2, 7))
	line("Down", Vector2.new(0.5, 0), UDim2.fromOffset(0, 6), UDim2.fromOffset(2, 7))
	line("Left", Vector2.new(1, 0.5), UDim2.fromOffset(-6, 0), UDim2.fromOffset(7, 2))
	line("Right", Vector2.new(0, 0.5), UDim2.fromOffset(6, 0), UDim2.fromOffset(7, 2))

	-- hit / kill marker: four ink ticks (never red)
	local hit = frame("Hit", { Size = UDim2.fromOffset(0, 0), Parent = center })
	for _, d in ipairs({ { "A", 1, -1, 45 }, { "B", -1, -1, -45 }, { "C", 1, 1, -45 }, { "D", -1, 1, 45 } }) do
		local tick = frame(d[1], {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(d[2] * 8, d[3] * 8),
			Size = UDim2.fromOffset(2, 9),
			Rotation = d[4],
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 1,
			Parent = hit,
		})
		edge(1).Parent = tick
	end

	-- where a hit came from (each Dir is rotated toward the attacker; 5 segments form a soft arc). Sun, not red:
	-- it says "look that way".
	local damage = frame("Damage", { Size = UDim2.fromOffset(0, 0), Parent = center })
	for i = 1, 4 do
		local dir = frame("Dir" .. i, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(250, 250), Visible = false, Parent = damage })
		for k = -2, 2 do
			local holder = frame("Seg" .. (k + 3), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Rotation = k * 6.5, Parent = dir })
			local bar = frame("Bar", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(15, 3),
				BackgroundColor3 = C.Sun,
				BackgroundTransparency = 1,
				Parent = holder,
			})
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
			Size = UDim2.fromOffset(2, 5),
			Rotation = math.deg(a),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.75,
			Parent = ring,
		})
	end
	label("Label", "", "SemiBold", 13, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(260, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = ring,
	})

	-- bow draw meter: a slim line (HUDController stands it upright beside the crosshair)
	local draw = frame("Draw", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.fromOffset(52, 3),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = T.BarTrack,
		Visible = false,
		Parent = center,
	}, { edge(0.6) })
	frame("Fill", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = 0, Parent = draw })

	-- interaction hint: a key square and a few words ([E] Drink). 34 px tall so the key's outline is not clipped.
	local interact = canvas("Interact", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.fromOffset(340, 34),
		GroupTransparency = 1,
		Visible = false,
		Parent = center,
	}, { list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	key("Key", "E", { LayoutOrder = 1, Parent = interact })
	label("Text", "", "Medium", 16, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 2, Parent = interact })

	-- action hint (QW2): what the held item does with this device's buttons, e.g. HOLD [LMB] EAT · +12 HUNGER.
	-- Same slot and style as the interaction hint, which takes priority. HUDController builds the row from Templates.
	local action = canvas("Action", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.fromOffset(560, 34),
		GroupTransparency = 1,
		Visible = false,
		Parent = center,
	}, { list(Enum.FillDirection.Horizontal, 7, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	-- (GuiObjects under a Folder still draw, so the templates stay hidden; HUDController shows its clones)
	local actionTemplates = new("Folder", { Name = "Templates", Parent = action })
	key("Key", "E", { Visible = false, Parent = actionTemplates })
	label("Text", "", "Medium", 15, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Visible = false, Parent = actionTemplates })
	return gui
end

------------------------------------------------------------------------------------------------
-- Lobby: status line, title, record line, text buttons, how-to-play sheet, and (NEW) who is here
------------------------------------------------------------------------------------------------
local function buildLobby(): ScreenGui
	local gui, root = screen("Lobby", 14)
	local C = Theme.Colors
	local T = Theme.Transparency

	-- The status line (top centre): plain light text, a slim progress line under it. Pill is no pill any more: it is
	-- the row that holds the dot, the text and the SPECTATE button (its Pad stays: LobbyController sets it).
	local status = frame("Status", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(640, 54), Parent = root })
	local pill = frame("Pill", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Shade,
		BackgroundTransparency = 1,
		Parent = status,
	}, {
		padding(4, 4, 0, 0),
		list(Enum.FillDirection.Horizontal, 11, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	frame("Dot", { Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.Sun, BackgroundTransparency = 0, LayoutOrder = 1, Parent = pill }, { corner(Theme.CornerPill), edge(0.5) })
	label("Text", "WAITING FOR PLAYERS", "Light", Theme.TextSize.Status, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), RichText = true, LayoutOrder = 2, Parent = pill })
	textButton("Spectate", "SPECTATE", "SemiBold", 14, {
		Height = 30,
		RichText = true,
		LayoutOrder = 3,
		Visible = false,
		Parent = pill,
	})
	local bar = frame("Bar", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.fromOffset(220, 2),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = T.BarTrack,
		Visible = false,
		Parent = status,
	}, { edge(0.7) })
	frame("Fill", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = 0, Parent = bar })

	-- Bottom left: the title, your record in one dim line, the text buttons.
	local brand = frame("Brand", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(640, 240), Parent = root }, {
		list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom),
	})
	-- NEW. The spaced title: one label per letter (Roblox has no letter spacing). Hidden until LobbyController shows
	-- it in Title's place; QuietUI.letters(TitleRow, text) writes it again if the title changes.
	local titleRow = frame("TitleRow", { Size = UDim2.new(1, 0, 0, 62), LayoutOrder = 1, Visible = false, Parent = brand })
	Quiet.letters(titleRow, string.upper(tostring(Config.GameTitle)))
	label("Title", Config.GameTitle, "Light", Theme.TextSize.Display, { Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 2, Parent = brand })
	-- NEW. "7 contenders waiting", under the title.
	label("Waiting", "", "Medium", 14, { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3, Visible = false, Parent = brand })
	local stats = frame("Stats", { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 5, Parent = brand })
	label("Header", "YOUR RECORD", "SemiBold", 13, { Size = UDim2.fromOffset(112, 18), TextColor3 = C.Ink2, Parent = stats })
	local cells = frame("Cells", { Position = UDim2.fromOffset(116, 0), Size = UDim2.new(1, -116, 1, 0), Parent = stats }, {
		list(Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	for i, pair in ipairs({ { "Wins", "WINS" }, { "Kills", "KILLS" }, { "Rounds", "ROUNDS" } }) do
		local cell = frame(pair[1], { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = cells }, {
			list(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		})
		label("Value", "0", "Mono", Theme.TextSize.Number, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 1, Parent = cell })
		label("Label", pair[2], "SemiBold", 13, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextColor3 = C.Ink2, LayoutOrder = 2, Parent = cell })
	end
	local buttons = frame("Buttons", { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 6, Parent = brand }, {
		list(Enum.FillDirection.Horizontal, 28, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	textButton("Settings", "SETTINGS", "SemiBold", 14, { RichText = true, LayoutOrder = 1, Parent = buttons })
	textButton("HowTo", "HOW TO PLAY", "SemiBold", 14, { RichText = true, LayoutOrder = 2, Parent = buttons })

	-- NEW. Who is in the lobby (bottom right): a header with the count, a hairline, one row a player (Templates.
	-- PlayerRow). Hidden until LobbyController fills it; it shares the right edge with the how-to-play sheet, so
	-- only one of the two shows at a time.
	local players = frame("Players", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(300, 320), Visible = false, Parent = root }, {
		list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom),
	})
	local playersHeader = frame("Header", { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = players })
	label("Title", "IN THE LOBBY", "SemiBold", 13, { Size = UDim2.new(1, -40, 1, 0), Parent = playersHeader })
	label("Count", "0", "Mono", Theme.TextSize.Number, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 40, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = playersHeader,
	})
	hair("Line", { LayoutOrder = 2, Parent = players })
	frame("Rows", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = players }, {
		list(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})

	-- HOW TO PLAY: text on the picture, no box (Bg is clear). The 18 px inside the sheet stays: a CanvasGroup cuts
	-- what reaches its edge, the text's dark stroke included.
	local how = canvas("HowTo", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0, 330, 1, -140),
		GroupTransparency = 0,
		Parent = root,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(330, 560) }) })
	canvasBg(how)
	local header = frame("Header", { Size = UDim2.new(1, 0, 0, 46), ZIndex = 2, Parent = how })
	label("Title", "HOW TO PLAY", "SemiBold", 16, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -64, 1, 0), Parent = header })
	textButton("Close", "×", "Regular", 24, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = C.PanelLight,
		Parent = header,
	}, { corner(Theme.CornerPill) })
	hair("Divider", { Position = UDim2.fromOffset(18, 46), Size = UDim2.new(1, -36, 0, 1), ZIndex = 2, Parent = how })
	local body = scroll("Body", how, {
		padding(18, 18, 12, 16),
		list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	}, UDim2.fromOffset(0, 48), UDim2.new(1, 0, 1, -49))
	body.ZIndex = 2
	label("Steps", steps(), "SemiBold", 13, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 0,
		Parent = body,
	})
	for i, text in ipairs(tips()) do
		local tip = frame("Tip" .. i, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = body })
		label("Num", string.format("%02d", i), "Mono", Theme.TextSize.Number, { Size = UDim2.fromOffset(24, 18), TextColor3 = C.Ink2, TextYAlignment = Enum.TextYAlignment.Top, Parent = tip })
		label("Text", text, "Medium", 14, {
			Position = UDim2.fromOffset(28, 0),
			Size = UDim2.new(1, -28, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = tip,
		})
	end
	label("ControlsHeader", "CONTROLS", "SemiBold", 13, {
		Size = UDim2.new(1, 0, 0, 28),
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextColor3 = C.Ink2,
		LayoutOrder = 10,
		Parent = body,
	})
	frame("Controls", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 11, Parent = body }, {
		list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})

	local templates = frame("Templates", { Visible = false, Parent = root })
	local row = controlRow(templates)
	-- the sheet is narrow: a long action ("Crouch · quieter steps · slide while sprinting") wraps onto a second line
	-- instead of being cut off (QW6 teaches crouching as quieter); the key square keeps the right edge
	row.AutomaticSize = Enum.AutomaticSize.Y
	local action = row:FindFirstChild("Action")
	if action then
		action.Size = UDim2.new(1, -124, 0, 30)
		action.AutomaticSize = Enum.AutomaticSize.Y
		action.TextWrapped = true
		action.TextTruncate = Enum.TextTruncate.None
	end
	-- NEW. One row of the Players list: Mark (a Sun bar for your own row), Left > Face (the player's headshot, a
	-- Roblox thumbnail), PlayerName, Tag ("YOU", "PLUS"); Wins at the right ("3 wins", "first round").
	local playerRow = frame("PlayerRow", { Size = UDim2.new(1, 0, 0, 32), Parent = templates })
	frame("Mark", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -9, 0.5, 0),
		Size = UDim2.fromOffset(3, 18),
		BackgroundColor3 = C.Sun,
		BackgroundTransparency = 0,
		Visible = false,
		Parent = playerRow,
	}, { edge(0.55) })
	local rowLeft = frame("Left", { Size = UDim2.new(1, -96, 1, 0), Parent = playerRow }, {
		list(Enum.FillDirection.Horizontal, 9, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	new("ImageLabel", {
		Name = "Face",
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Image = "",
		LayoutOrder = 1,
		Parent = rowLeft,
	}, { corner(UDim.new(0, 5)) })
	label("PlayerName", "", "Medium", 15, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 2, Parent = rowLeft }, {
		new("UISizeConstraint", { MaxSize = Vector2.new(150, 32) }),
	})
	label("Tag", "", "SemiBold", 13, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), TextColor3 = C.Sun, LayoutOrder = 3, Visible = false, Parent = rowLeft })
	label("Wins", "", "Medium", 13, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 96, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		RichText = true,
		Parent = playerRow,
	})
	return gui
end

------------------------------------------------------------------------------------------------
-- Overlay: countdown, headlines, toasts, roll call, the defeat strip (NEW), and the older death and victory screens
------------------------------------------------------------------------------------------------
local function buildOverlay(): ScreenGui
	local gui, root = screen("Overlay", 20)
	local C = Theme.Colors
	frame("Dim", {
		Position = UDim2.fromOffset(-240, -240),
		Size = UDim2.new(1, 480, 1, 480),
		BackgroundColor3 = C.Shade,
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = gui,
	})

	local countdown = frame("Countdown", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(440, 240), Visible = false, Parent = root })
	local number = label("Number", "", "Light", 132, { Size = UDim2.new(1, 0, 0, 160), TextXAlignment = Enum.TextXAlignment.Center, Parent = countdown })
	new("UIScale", { Name = "Pop", Parent = number })
	-- the goal, then the choice (QW6): the most-watched seconds of the round. Plain text, no pill.
	label("Caption", "GET READY", "SemiBold", 18, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 164),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = countdown,
	})
	-- new players: where running pays (QW7's runner's caches, behind every plate)
	label("Sub", "", "Medium", 14, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 198),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = countdown,
	})

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
	label("Eyebrow", "", "SemiBold", 13, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Sun, LayoutOrder = 1, Parent = headline })
	label("Title", "", "Light", 40, { Size = UDim2.new(1, 0, 0, 48), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = headline })
	frame("Rule", { Size = UDim2.fromOffset(56, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = 0.3, LayoutOrder = 3, Parent = headline })
	label("Sub", "", "Medium", 16, {
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		RichText = true,
		LayoutOrder = 4,
		Parent = headline,
	})

	-- toasts sit above the HUD's item-name block (60 px tall with an item's description)
	frame("Toasts", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -136), Size = UDim2.fromOffset(460, 150), Parent = root }, {
		list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom),
	})
	-- one-time help cards (QW5: THIRSTY, HUNGRY) at the left, clear of the item toast, the hint and the held item
	frame("Cards", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.42), Size = UDim2.fromOffset(400, 220), Parent = root }, {
		list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})

	local roll = canvas("RollCall", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(1, -40, 0, 300),
		GroupTransparency = 1,
		Visible = false,
		Parent = root,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(640, 300) }) })
	label("Title", "THE FALLEN", "SemiBold", 18, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Parent = roll })
	frame("Rule", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(40, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = 0.4, Parent = roll })
	label("Sub", "", "Medium", 14, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Ink2, Parent = roll })
	-- compact (phone) variant: the names flow on one wrapped line under the title
	label("Line", "", "Medium", 15, {
		Position = UDim2.fromOffset(16, 36),
		Size = UDim2.new(1, -32, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		Visible = false,
		Parent = roll,
	})
	frame("Names", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 88), Size = UDim2.new(1, -40, 1, -104), Parent = roll }, {
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(180, 24),
			CellPadding = UDim2.fromOffset(8, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- NEW. Defeat is this one slim strip along the bottom, never a card: a hairline (Line), and under it
	--   Left  > Mark (a small red diamond), Cause ("Defeated by Kestrel"), Sep, Place ("You placed 9th of 24")
	--   Right > Leave (a text button: "Back to lobby"), LeaveKey (its key square)
	-- The middle of the strip is the Spectate screen's Card (who you are watching), which sits on the same line.
	-- On a phone the strip is too wide for one row: shrink it (QuietUI.fit) or hide Sep and Place.
	local strip = Quiet.strip({ Name = "Strip", Visible = false, Parent = root })
	local stripLeft = frame("Left", { Position = UDim2.fromOffset(0, 1), Size = UDim2.new(0.4, 0, 1, -1), Parent = strip }, {
		list(Enum.FillDirection.Horizontal, 11, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	Quiet.icon("diamond", { Name = "Mark", Px = 12, Color = C.Red, LayoutOrder = 1, Parent = stripLeft })
	label("Cause", "", "Medium", 16, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), RichText = true, LayoutOrder = 2, Parent = stripLeft })
	hair("Sep", { Vertical = true, Size = UDim2.fromOffset(1, 20), LayoutOrder = 3, Parent = stripLeft })
	label("Place", "", "Medium", 16, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), RichText = true, LayoutOrder = 4, Parent = stripLeft })
	local stripRight = frame("Right", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 1), Size = UDim2.new(0.3, 0, 1, -1), Parent = strip }, {
		list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center),
	})
	textButton("Leave", "Back to lobby", "Medium", 15, { LayoutOrder = 1, Parent = stripRight })
	key("LeaveKey", "Backspace", { LayoutOrder = 2, Parent = stripRight })

	-- the older death screen (centre of the screen). Kept, in Quiet type, so NotificationController works until it
	-- shows the strip instead.
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
	label("Eyebrow", "ELIMINATED", "SemiBold", 14, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Red, LayoutOrder = 1, Parent = dpanel })
	label("Title", "", "Light", 72, { Size = UDim2.new(1, 0, 0, 80), TextXAlignment = Enum.TextXAlignment.Center, RichText = true, LayoutOrder = 2, Parent = dpanel })
	label("Cause", "", "Medium", 16, {
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		RichText = true,
		LayoutOrder = 3,
		Parent = dpanel,
	})
	-- QW4: how far you got ("OUTLASTED 15 OF 24  ·  6:12") and one tip for what killed you
	label("Progress", "", "SemiBold", 13, {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Ink2,
		LayoutOrder = 4,
		Visible = false,
		Parent = dpanel,
	})
	label("Tip", "", "Medium", 15, {
		Size = UDim2.new(1, -60, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		RichText = true,
		LayoutOrder = 5,
		Visible = false,
		Parent = dpanel,
	})
	frame("Gap", { Size = UDim2.fromOffset(1, 12), LayoutOrder = 6, Parent = dpanel })
	local dbuttons = frame("Buttons", { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 7, Parent = dpanel }, {
		list(Enum.FillDirection.Horizontal, 32, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local spectate = textButton("Spectate", "SPECTATE", "SemiBold", 15, { Height = 44, Modal = true, LayoutOrder = 1, Parent = dbuttons })
	spectate:SetAttribute("Primary", true)
	textButton("Continue", "CONTINUE", "SemiBold", 15, { Height = 44, Modal = true, LayoutOrder = 2, Parent = dbuttons })
	label("Note", "", "Medium", 13, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Ink2, RichText = true, LayoutOrder = 8, Parent = dpanel })

	-- the older victory screen + round summary. Kept, in Quiet type and with no box; the round's results belong on
	-- the physical board in the lobby.
	local victory = frame("Victory", { Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })
	local vpanel = canvas("Panel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.new(1, -40, 0.88, 0),
		GroupTransparency = 1,
		Parent = victory,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(620, 600) }) })
	label("Eyebrow", "THE ROUND IS OVER", "SemiBold", 14, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Sun, Parent = vpanel })
	label("Title", "", "Light", 64, {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 72),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = vpanel,
	})
	label("Sub", "", "Medium", 16, {
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		RichText = true,
		Parent = vpanel,
	})
	local summary = frame("Summary", {
		Position = UDim2.fromOffset(1, 132),
		Size = UDim2.new(1, -2, 1, -133),
		BackgroundColor3 = C.Shade,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = vpanel,
	})
	local head = frame("Header", { Size = UDim2.new(1, 0, 0, 34), Parent = summary })
	label("Rank", "#", "SemiBold", 13, { Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(40, 34), TextColor3 = C.Ink2, Parent = head })
	label("Contender", "CONTENDER", "SemiBold", 13, { Position = UDim2.fromOffset(60, 0), Size = UDim2.new(1, -150, 0, 34), TextColor3 = C.Ink2, Parent = head })
	label("Kills", "KILLS", "SemiBold", 13, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.fromOffset(60, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Ink2,
		Parent = head,
	})
	hair("Divider", { Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 1), Parent = summary })
	scroll("Rows", summary, {
		padding(6, 6, 2, 4),
		list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	}, UDim2.fromOffset(0, 38), UDim2.new(1, 0, 1, -70))
	label("Footer", "", "Medium", 13, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -7),
		Size = UDim2.new(1, -32, 0, 20),
		TextColor3 = C.Ink2,
		Parent = summary,
	})

	-- templates
	local templates = frame("Templates", { Visible = false, Parent = root })
	-- a toast: a small Sun dot and a line of text, no box
	local toast = frame("Toast", {
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Shade,
		BackgroundTransparency = 1,
		Parent = templates,
	}, {
		padding(8, 8, 0, 0),
		list(Enum.FillDirection.Horizontal, 9, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	frame("Mark", { Size = UDim2.fromOffset(5, 5), BackgroundColor3 = C.Sun, BackgroundTransparency = 0, LayoutOrder = 1, Parent = toast }, { corner(Theme.CornerPill) })
	label("Text", "", "Medium", 15, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = toast,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(320, 36) }) })
	label("Sub", "", "Medium", 14, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = C.Ink2,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 3,
		Parent = toast,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(260, 36) }) })
	local srow = frame("SummaryRow", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 1, Parent = templates })
	frame("Mark", { Position = UDim2.fromOffset(0, 7), Size = UDim2.fromOffset(2, 14), BackgroundColor3 = C.Sun, BackgroundTransparency = 0, Visible = false, Parent = srow })
	label("Rank", "1", "Mono", Theme.TextSize.Number, { Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(40, 28), TextColor3 = C.Ink2, Parent = srow })
	label("PlayerName", "", "Medium", 15, { Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -140, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, Parent = srow })
	label("Kills", "0", "Mono", Theme.TextSize.Number, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.fromOffset(60, 28),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = srow,
	})
	-- a name in the Roll Call. Its text starts clear and NotificationController fades it in: the stroke starts clear
	-- too, and has to be faded with the text (QuietUI.fadeText).
	local rollName = label("RollName", "", "Medium", 15, {
		Size = UDim2.fromOffset(180, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = templates,
	})
	rollName.Shadow:SetAttribute("Rest", rollName.Shadow.Transparency)
	rollName.Shadow.Transparency = 1
	-- one-time cards for new players (QW5: THIRSTY, HUNGRY): a title and a wrapped line, no box
	local card = frame("Card", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = C.Shade,
		BackgroundTransparency = 1,
		Parent = templates,
	}, {
		padding(8, 10, 6, 6),
		list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	local markHolder = frame("MarkHolder", { Size = UDim2.fromOffset(5, 18), LayoutOrder = 1, Parent = card })
	frame("Mark", { Position = UDim2.fromOffset(0, 7), Size = UDim2.fromOffset(5, 5), BackgroundColor3 = C.Sun, BackgroundTransparency = 0, Parent = markHolder }, { corner(Theme.CornerPill) })
	local cardBody = frame("Body", { Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2, Parent = card }, {
		list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	label("Title", "", "SemiBold", 14, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = cardBody })
	label("Text", "", "Medium", 14, {
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		RichText = true,
		LayoutOrder = 2,
		Parent = cardBody,
	})
	return gui
end

------------------------------------------------------------------------------------------------
-- Menu: settings + controls reference. A modal sheet: the whole picture dims behind it (Dim) and the sheet has no box.
------------------------------------------------------------------------------------------------
local function buildMenu(): ScreenGui
	local gui, root = screen("Menu", 40)
	local C = Theme.Colors
	local T = Theme.Transparency
	plainButton("Dim", {
		Position = UDim2.fromOffset(-240, -240),
		Size = UDim2.new(1, 480, 1, 480),
		BackgroundColor3 = C.Shade,
		BackgroundTransparency = 1,
		Modal = true,
		Selectable = false,
		Visible = false,
		ZIndex = 1,
		Parent = gui,
	})

	-- touch screens: the menu button (three ink lines; 44 px for a finger)
	local launcher = plainButton("Launcher", { Size = UDim2.fromOffset(44, 44), Visible = false, Selectable = false, Parent = root }, {
		corner(Theme.Corner),
	})
	local icon = frame("Icon", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 14), Parent = launcher })
	for i = 0, 2 do
		frame("Line" .. (i + 1), { Position = UDim2.fromOffset(0, i * 6), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.Ink, BackgroundTransparency = 0, Parent = icon }, { edge(0.5) })
	end

	local panel = canvas("Panel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -8),
		GroupTransparency = 1,
		Visible = false,
		Parent = root,
	}, { new("UISizeConstraint", { MaxSize = Vector2.new(600, 500) }) })
	canvasBg(panel)
	local header = frame("Header", { Size = UDim2.new(1, 0, 0, 54), ZIndex = 2, Parent = panel })
	local tabs = frame("Tabs", { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -84, 1, 0), Parent = header }, {
		list(Enum.FillDirection.Horizontal, 26, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	for i, pair in ipairs({ { "SettingsTab", "SETTINGS" }, { "ControlsTab", "CONTROLS" } }) do
		local tab = textButton(pair[1], pair[2], "SemiBold", 16, {
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = i,
			Parent = tabs,
		})
		frame("Underline", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -1),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0,
			Visible = i == 1,
			Parent = tab,
		})
	end
	textButton("Close", "×", "Regular", 26, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.PanelLight,
		Parent = header,
	}, { corner(Theme.CornerPill) })
	hair("Divider", { Position = UDim2.fromOffset(22, 54), Size = UDim2.new(1, -44, 0, 1), ZIndex = 2, Parent = panel })
	local pages = frame("Pages", { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -105), ZIndex = 2, Parent = panel })
	scroll("Settings", pages, {
		padding(14, 14, 6, 12),
		list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
	local controls = frame("Controls", { Size = UDim2.fromScale(1, 1), Visible = false, Parent = pages })
	local devices = frame("Devices", { Position = UDim2.fromOffset(22, 12), Size = UDim2.new(1, -44, 0, 32), Parent = controls }, {
		list(Enum.FillDirection.Horizontal, 22, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	for i, pair in ipairs({ { "KeyboardMouse", "KEYBOARD & MOUSE" }, { "Gamepad", "GAMEPAD" }, { "Touch", "TOUCH" } }) do
		textButton(pair[1], pair[2], "SemiBold", 13, {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = i,
			Parent = devices,
		}, { corner(Theme.Corner) })
	end
	scroll("List", controls, {
		padding(22, 22, 4, 12),
		list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	}, UDim2.fromOffset(0, 54), UDim2.new(1, 0, 1, -54))
	local footer = frame("Footer", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 48), ZIndex = 2, Parent = panel })
	hair("Divider", { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -44, 0, 1), Parent = footer })
	label("Hint", "M  CLOSE", "SemiBold", 13, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(0.55, 0, 1, 0), TextColor3 = C.Ink2, RichText = true, Parent = footer })
	textButton("Reset", "RESET TO DEFAULTS", "SemiBold", 13, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -22, 0.5, 0),
		Height = 32,
		BackgroundColor3 = C.PanelLight,
		Parent = footer,
	}, { corner(Theme.Corner) })

	local templates = frame("Templates", { Visible = false, Parent = root })
	label("Section", "CAMERA", "SemiBold", 13, {
		Size = UDim2.new(1, 0, 0, 32),
		TextColor3 = C.Ink2,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Parent = templates,
	}, { padding(10, 0, 0, 6) })
	-- a setting: its name, its value, and a slim line with a small ink knob
	local slider = plainButton("SliderRow", {
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 1,
		Selectable = true,
		Parent = templates,
	}, { corner(Theme.Corner), padding(10, 10, 8, 10) })
	label("Label", "Setting", "Medium", 15, { Size = UDim2.new(1, -90, 0, 20), Parent = slider })
	label("Value", "0", "Mono", Theme.TextSize.Number, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(90, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Ink2,
		Parent = slider,
	})
	local track = frame("Track", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -5),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = T.BarTrack,
		Parent = slider,
	})
	frame("Fill", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = 0, Parent = track })
	frame("Knob", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(11, 11),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0,
		ZIndex = 3,
		Parent = track,
	}, { corner(Theme.CornerPill), edge(0.45) })
	controlRow(templates)
	-- the gamepad's focus: a Sun outline (the one place a box is drawn, so the focus is never lost)
	Quiet.selection({ Name = "Selection", AnchorPoint = Vector2.zero, Position = UDim2.new(), Size = UDim2.fromScale(1, 1), Parent = templates })
	return gui
end

------------------------------------------------------------------------------------------------
-- Spectate: the middle of the bottom strip (who you are watching, previous / next), and the way out
------------------------------------------------------------------------------------------------
local function buildSpectate(): ScreenGui
	local gui, root = screen("Spectate", 12)
	local C = Theme.Colors
	local T = Theme.Transparency
	local K = Theme.Key
	-- NEW. The strip's hairline, for spectating without a defeat strip under it (watching from the lobby).
	hair("Line", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -Theme.Strip.Height), Visible = false, Parent = root })
	local card = canvas("Card", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(460, 66),
		GroupTransparency = 1,
		Visible = false,
		Parent = root,
	})
	canvasBg(card)
	-- a chevron to press, with its key in a key square beside it (Hint is a TextLabel: SpectateController writes it)
	local function arrow(name: string, glyph: string, anchorX: number, x: number, keyText: string)
		local b = textButton(name, glyph, "Regular", 28, {
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(anchorX, x, 0, 10),
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = C.PanelLight,
			Selectable = false,
			ZIndex = 2,
			Parent = card,
		}, { corner(Theme.Corner) })
		-- (the outline is on a clear child, Box: the label keeps one stroke, its text's)
		local hint = label("Hint", keyText, "MonoMedium", Theme.TextSize.Number, {
			AnchorPoint = Vector2.new(1 - anchorX, 0.5),
			Position = UDim2.new(anchorX, if anchorX == 0 then -6 else 6, 0.5, 0),
			Size = UDim2.fromOffset(K.Size, K.Size),
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundColor3 = C.Shade,
			BackgroundTransparency = K.Shade,
			Parent = b,
		}, { corner(K.Corner) })
		local box = frame("Box", { Size = UDim2.fromScale(1, 1), Parent = hint }, { corner(K.Corner) })
		new("UIStroke", { Name = "Stroke", Color = C.Ink, Transparency = T.KeyStroke, Thickness = K.Thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = box })
		return b
	end
	arrow("Prev", "‹", 0, 40, "Q")
	arrow("Next", "›", 1, -40, "E")
	local info = frame("Info", { Position = UDim2.fromOffset(90, 0), Size = UDim2.new(1, -180, 1, 0), ZIndex = 2, Parent = card })
	label("Eyebrow", "SPECTATING", "SemiBold", 13, { Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Ink2, Parent = info })
	label("PlayerName", "", "SemiBold", 17, {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = info,
	})
	label("Sub", "", "Medium", 13, {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Ink2,
		RichText = true,
		Parent = info,
	})
	local hp = frame("Health", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(150, 3),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = T.BarTrack,
		Parent = info,
	})
	frame("Under", { Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Shade, BackgroundTransparency = Theme.Stroke.LineTransparency, Parent = hp })
	frame("Fill", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = 0, ZIndex = 2, Parent = hp })
	-- the way out: a text button above the card. (In the strip it belongs at the right end, as "Back to lobby".)
	textButton("Exit", "EXIT SPECTATING", "SemiBold", 13, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Height = 32,
		RichText = true,
		Visible = false,
		Selectable = false,
		Parent = root,
	})
	label("Empty", "NO CONTENDERS LEFT TO WATCH", "SemiBold", 14, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromOffset(460, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Ink2,
		Visible = false,
		Parent = root,
	})
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
	local shared = ReplicatedStorage:WaitForChild("Shared")
	Theme = o.Theme or require(shared:WaitForChild("Theme"))
	Config = o.Config or require(shared:WaitForChild("Config"))
	Quiet = o.QuietUI or require(shared:WaitForChild("QuietUI"))
end

-- Fresh copies of Theme, QuietUI and Config, required side by side (QuietUI requires the Theme beside it), so that
-- nothing comes out of Studio's module cache. Returns the opts for build() / preview().
local function freshModules(opts: { [string]: any }?): { [string]: any }
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local box = Instance.new("Folder")
	box.Name = "UIBuilderFresh"
	for _, moduleName in ipairs({ "Theme", "QuietUI", "Config" }) do
		shared:WaitForChild(moduleName):Clone().Parent = box
	end
	local o: { [string]: any } = {}
	if opts then
		for k, v in pairs(opts) do
			o[k] = v
		end
	end
	o.Theme = require(box:FindFirstChild("Theme") :: any)
	o.QuietUI = require(box:FindFirstChild("QuietUI") :: any)
	o.Config = require(box:FindFirstChild("Config") :: any)
	box:Destroy()
	return o
end

-- opts: { Theme = table?, QuietUI = table?, Config = table?, parent = Instance? } (inject freshly required modules
-- when re-running, or call buildFresh)
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

function UIBuilder.buildFresh(opts: { [string]: any }?): string
	return UIBuilder.build(freshModules(opts))
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
		local b = label(name, text, "SemiBold", math.max(13, math.floor(size * 0.19)), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Theme.Colors.Shade,
			BackgroundTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Center,
			Stroke = false,
			Parent = gui,
		}, { corner(Theme.CornerPill) })
		new("UIStroke", { Color = Theme.Colors.Ink, Transparency = 0.7, Thickness = 1.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
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

-- The HUD's placement for a device, from Theme.Layout: what HUDController.applyLayout does, plus the Quiet parts
-- (the round's facts top right on a desktop, the picture's size in a cell).
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
	-- the round's facts: top right on a desktop, in the line under the compass on a touch screen
	local facts = layout.Facts == true
	root.Facts.Visible = facts
	root.Top.Info.Remain.Visible = not facts
	root.Top.Info.Timer.Visible = not facts
	root.Top.Info.Dot.Visible = not facts
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

local PX_PER_DEGREE = COMPASS_WIDTH / 150 -- HUDController's COMPASS_SPAN

local function previewCompass(top: any, heading: number)
	for _, child in ipairs(top.Compass.Ticks:GetChildren()) do
		local a = child:GetAttribute("Angle")
		if a then
			local d = ((a - heading + 540) % 360) - 180
			child.Position = UDim2.new(0.5, d * PX_PER_DEGREE, child.Position.Y.Scale, child.Position.Y.Offset)
			child.Visible = math.abs(d) <= 79
			local fade = math.clamp((math.abs(d) - 49) / 26, 0, 1)
			if child:IsA("TextLabel") then
				Quiet.textTransparency(child, fade)
			else
				local base = child:GetAttribute("BaseTransparency") or 0
				child.BackgroundTransparency = base + (1 - base) * fade
			end
		end
	end
	local spire = top.Compass.Markers.Spire
	spire.Visible = true
	spire.Position = UDim2.new(0.5, (((4 - heading + 540) % 360) - 180) * PX_PER_DEGREE, 0, MARKER_Y)
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
	-- vitals: health in use, hunger fine (at rest), thirst low (Sun), stamina in use
	Quiet.setBar(root.Vitals.Health, 0.72, "72", "active")
	root.Vitals.Health.Track.Ghost.Size = UDim2.fromScale(0.84, 1)
	root.Vitals.Health.ArmorLine.Visible = true
	root.Vitals.Health.Label.Text = "ARMOR 15%"
	Quiet.setBar(root.Vitals.Hunger, 0.81, "81", "rest")
	Quiet.setBar(root.Vitals.Thirst, 0.19, "19", "low")
	Quiet.setBar(root.Vitals.Stamina, 0.64, "64", "active")
	root.Vitals.Stamina.Track.Ghost.Visible = false
	root.Vitals.Reason.Visible = true
	root.Vitals.Reason.Text = string.format("NOT HEALING  ·  <font color=\"%s\">THIRSTY</font>", Theme.hex(C.Sun))
	-- compass: the Spire ahead, water for the thirsty off to the left
	previewCompass(root.Top, 20)
	local water = root.Top.Compass.Markers.Water
	water.Visible = true
	water.Position = UDim2.new(0.5, -84, 0, MARKER_Y)
	water.Dist.Text = "64 m"
	root.Top.Info.Timer.Text = "11:42"
	root.Top.Info.Remain.Text = "17 left"
	root.Facts.Row.Count.Text = "17"
	root.Facts.Sub.Text = "11:42"
	root.Top.Event.Visible = true
	root.Top.Event.Text = "THE BORDER MOVES IN 0:42"
	local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
	local items = { { "bow", 1 }, { "arrow", 14 }, { "knife", 1 }, { "apple", 3 }, { "bandage", 2 }, false }
	for i, it in ipairs(items) do
		local slot = root.Hotbar.Slots:FindFirstChild("Slot" .. i)
		if slot and it then
			local card = slot.Card
			card.Count.Text = if it[2] > 1 then tostring(it[2]) else ""
			previewIcon(card.Viewport, it[1])
		elseif slot then
			slot.Card.Ring.Visible = true
		end
	end
	-- the cell in hand: a bigger picture, the line under it, its number in full ink, its name above
	local selected = root.Hotbar.Slots.Slot1.Card
	selected.Viewport.Size = UDim2.fromOffset(Theme.Layout.IconSelected, Theme.Layout.IconSelected)
	selected.Under.Visible = true
	selected.Key.TextColor3 = C.Ink
	local def = ItemDefs.get("bow")
	root.Hotbar.ItemName.GroupTransparency = 0
	root.Hotbar.ItemName.Title.Text = if def then def.name else "Recurve Bow"
	root.Hotbar.ItemName.Sub.Text = "RANGED"
	local dim = Theme.hex(C.Ink2)
	local entries = {
		{ string.format("<b>Kestrel</b>  <font color=\"%s\">Recurve Bow</font>  <b>Ana</b>", dim), false },
		{ string.format("<font color=\"%s\"><b>You</b></font>  <font color=\"%s\">Hunting Knife</font>  <b>Bo</b>", Theme.hex(C.Sun), dim), true },
		{ string.format("<b>Moss</b>  <font color=\"%s\">starved</font>", dim), false },
	}
	for i, e in ipairs(entries) do
		local entry = root.Templates.KillEntry:Clone()
		entry.Name = "Kill" .. i
		entry.LayoutOrder = i
		entry.Text.Text = e[1]
		entry.Mark.Visible = e[2]
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
	root.Status.Pill.Text.Text = "Next round in 0:12"
	root.Status.Bar.Visible = true
	root.Status.Bar.Fill.Size = UDim2.fromScale(0.5, 1)
	root.Brand.TitleRow.Visible = true
	root.Brand.Title.Visible = false
	root.Brand.Waiting.Visible = true
	root.Brand.Waiting.Text = "7 contenders waiting"
	local cells = root.Brand.Stats.Cells
	cells.Wins.Value.Text, cells.Kills.Value.Text, cells.Rounds.Value.Text = "3", "41", "27"
	sampleRows(root.HowTo.Body.Controls, root.Templates.ControlRow, SAMPLE_CONTROLS)
	root.HowTo.Body.ControlsHeader.Text = "CONTROLS  ·  KEYBOARD & MOUSE"
	if touch then
		root.Brand.AnchorPoint = Vector2.zero
		root.Brand.Position = UDim2.new()
		root.Brand.Layout.VerticalAlignment = Enum.VerticalAlignment.Top
		root.Brand.TitleRow.Visible = false
		root.Brand.Title.Visible = true
		root.Brand.Title.TextSize = 28
		root.Brand.Title.Size = UDim2.new(1, 0, 0, 34)
		root.HowTo.Visible = false
	end
	parent.Lobby.Enabled = true
end

-- the lobby with the how-to-play sheet closed and the list of who is here in its place
local function previewPlayers(parent: any)
	local C = Theme.Colors
	local root = parent.Lobby.Root
	root.HowTo.Visible = false
	root.Players.Visible = true
	local people = { { "Ash", "YOU", "<b>3</b> wins" }, { "Kestrel", "PLUS", "<b>11</b> wins" }, { "Rowan", "", "<b>6</b> wins" }, { "Wren", "", "first round" } }
	root.Players.Header.Count.Text = tostring(#people)
	for i, p in ipairs(people) do
		local row = root.Templates.PlayerRow:Clone()
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Left.PlayerName.Text = p[1]
		row.Left.Tag.Text = p[2]
		row.Left.Tag.Visible = p[2] ~= ""
		row.Wins.Text = p[3]
		row.Wins.TextColor3 = if p[3] == "first round" then C.Ink2 else C.Ink
		row.Mark.Visible = i == 1
		row.Parent = root.Players.Rows
	end
end

local function previewMenu(parent: any)
	local gui = parent.Menu
	local root = gui.Root
	gui.Dim.Visible = true
	gui.Dim.BackgroundTransparency = Theme.Transparency.Dim
	root.Panel.Visible = true
	root.Panel.GroupTransparency = 0
	local settings = root.Panel.Pages.Settings
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
			section.Parent = settings
		else
			local row = root.Templates.SliderRow:Clone()
			row.LayoutOrder = i
			row.Label.Text = sample[1]
			row.Value.Text = sample[3]
			row.Track.Fill.Size = UDim2.fromScale(sample[2], 1)
			row.Track.Knob.Position = UDim2.fromScale(sample[2], 0.5)
			if i == 2 then
				row.Value.TextColor3 = Theme.Colors.Ink
			end
			row.Parent = settings
		end
	end
	gui.Enabled = true
end

local function previewOverlay(parent: any, which: string)
	local C = Theme.Colors
	local gui = parent.Overlay
	local root = gui.Root
	if which == "Strip" then
		-- the Quiet defeat: the strip, with the Spectate card in its middle
		local strip = root.Strip
		strip.Visible = true
		strip.Left.Cause.Text = "Defeated by <b>Kestrel</b>"
		strip.Left.Place.Text = "You placed <b>9th</b> of 24"
		local card = parent.Spectate.Root.Card
		card.Visible = true
		card.GroupTransparency = 0
		card.Info.PlayerName.Text = "Rowan"
		card.Info.Health.Fill.Size = UDim2.fromScale(0.64, 1)
		parent.Spectate.Enabled = true
	elseif which == "Death" then
		gui.Dim.BackgroundTransparency = Theme.Transparency.Dim
		root.Death.Visible = true
		root.Death.Panel.GroupTransparency = 0
		root.Death.Panel.Title.Text = string.format("#7<font size=\"30\" color=\"%s\">   OF 24</font>", Theme.hex(C.Ink2))
		root.Death.Panel.Cause.Text = "Eliminated by <b>Kestrel</b>   ·   Recurve Bow"
		root.Death.Panel.Note.Text = "Watch the contenders who remain"
	elseif which == "Victory" then
		gui.Dim.BackgroundTransparency = Theme.Transparency.Dim
		local panel = root.Victory.Panel
		root.Victory.Visible = true
		panel.GroupTransparency = 0
		panel.Eyebrow.Text = "THE LAST ONE STANDING"
		panel.Title.Text = "VICTORY"
		panel.Sub.Text = "You outlasted 23 contenders   ·   <b>5</b> eliminations"
		panel.Summary.Visible = true
		local people = { { "You", 5 }, { "Kestrel", 4 }, { "Ana", 2 }, { "Moss", 1 }, { "Bo", 3 }, { "Wren", 0 }, { "Juniper", 1 }, { "Ash", 0 } }
		for i, p in ipairs(people) do
			local row = root.Templates.SummaryRow:Clone()
			row.LayoutOrder = i
			row.Rank.Text = "#" .. i
			row.PlayerName.Text = p[1] .. (if i == 1 then string.format("  <font color=\"%s\">YOU</font>", Theme.hex(C.Sun)) else "")
			row.PlayerName.FontFace = if i == 1 then Theme.Fonts.SemiBold else Theme.Fonts.Medium
			row.Kills.Text = tostring(p[2])
			row.Mark.Visible = i == 1
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
			Quiet.textTransparency(l, if i <= 5 then 0 else 0.6)
			l.Parent = roll.Names
		end
		roll.Size = UDim2.new(1, -40, 0, 172)
	elseif which == "Headline" then
		local h = root.Headline
		h.Visible = true
		h.GroupTransparency = 0
		h.Eyebrow.Text = "WARNING"
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
	root.Line.Visible = true
	card.Visible = true
	card.GroupTransparency = 0
	card.Info.PlayerName.Text = "Kestrel"
	card.Info.Sub.Text = "@kestrel_wing   ·   <b>4</b> KILLS"
	card.Info.Health.Fill.Size = UDim2.fromScale(0.64, 1)
	root.Exit.Visible = true
	root.Exit.Text = "EXIT SPECTATING   <font transparency=\"0.45\">BACKSPACE</font>"
	parent.Spectate.Enabled = true
	local hudRoot = parent.HUD.Root
	local top = hudRoot.Top
	top.Visible = true
	previewCompass(top, 300)
	top.Info.Timer.Text = "06:10"
	top.Info.Remain.Text = "4 left"
	parent.HUD.Enabled = true
end

-- which: "HUD" | "Lobby" | "Players" | "Menu" | "Death" | "Strip" | "Victory" | "Countdown" | "RollCall" | "Headline"
--        | "Spectate"
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
	elseif which == "Players" then
		previewLobby(parent, touch)
		previewPlayers(parent)
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

function UIBuilder.previewFresh(which: string, opts: { [string]: any }?): string
	return UIBuilder.preview(which, freshModules(opts))
end

-- The three HOW TO PLAY tips as they are written for the arena in the place (Shared.Lore, Shared.ThreatLine).
UIBuilder.tips = tips
-- ...and the one-line goal above them.
UIBuilder.steps = steps

-- Rewrites only those three tips and the goal line in the built Lobby screen (StarterGui.Lobby ... Body.Tip1..3.Text,
-- Body.Steps): for a change of Config.Map without building every screen again. Returns a line per text: written or
-- not found, and the text.
function UIBuilder.applyTips(parent: Instance?): string
	local root = (parent or StarterGui):FindFirstChild("Lobby")
	if not root then
		return "UIBuilder.applyTips: there is no Lobby screen (run buildFresh())"
	end
	local lines = {}
	for i, text in ipairs(tips()) do
		local written = 0
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == "Tip" .. i and d:IsA("Frame") then
				local tipLabel = d:FindFirstChild("Text")
				if tipLabel and tipLabel:IsA("TextLabel") then
					tipLabel.Text = text
					written += 1
				end
			end
		end
		table.insert(lines, string.format("tip %d %s: %s", i, if written > 0 then "written" else "NOT FOUND", text))
	end
	local goal = steps()
	local goalWritten = false
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == "Steps" and d:IsA("TextLabel") then
			d.Text = goal
			goalWritten = true
		end
	end
	table.insert(lines, string.format("goal %s: %s", if goalWritten then "written" else "NOT FOUND", goal))
	return table.concat(lines, "\n")
end

return UIBuilder
