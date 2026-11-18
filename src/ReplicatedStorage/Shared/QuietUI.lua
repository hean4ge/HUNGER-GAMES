--[[
	QuietUI - the small kit every screen is built from, in the "Quiet" style (docs/design/ui/StyleA_Quiet/README.md).
	Values come from Shared.Theme. Client and edit time: the builders below only make Instances (ServerStorage.WorldGen.
	UIBuilder uses them to build the saved screens); the bind* / fade* / fit functions add behaviour and are for the
	client controllers.

	The rules the kit keeps for you: no boxes; one ink colour, Sun for "look at this", Red for a danger state only;
	text and lines stay readable through a dark stroke named "Shadow"; nothing under Theme.TextSize.Small.

	"props" is a table of Instance properties (Name, Parent, Size, Position, AnchorPoint, LayoutOrder, Visible, ZIndex,
	and so on) plus the few extra keys each function names. Parent is always set last.

	BUILD (Instances only)
	  QuietUI.label(props) -> TextLabel
	      Extra keys: Font (a Theme.Fonts key or a Font; default "Medium"), TextSize (default Theme.TextSize.Body),
	      Stroke (false for none, "Big" for the thicker one; default by size).
	      Ink colour, clear background, left aligned, with the dark stroke.
	  QuietUI.stroke(gui, big?) -> UIStroke
	      Adds or refreshes the dark stroke on a text object or a line (= Theme.shadow).
	  QuietUI.line(props) -> Frame
	      A 1 px rule in ink (Theme.Transparency.Hairline) with a 1 px shade under it. Extra key: Vertical (boolean).
	      Default size: the parent's full width, 1 px tall.
	  QuietUI.icon(kind, props) -> Frame
	      A small matte icon made of plain Frames (no images): "heart", "food", "drop", "run", "diamond", "dot",
	      "ring", "plus", "blade". Extra keys: Px (default Theme.Bar.Icon), Color (default Ink).
	      Children: Drop (the 1 px shade copy) and Ink (the parts). Recolour with QuietUI.tint.
	  QuietUI.tint(icon, color)
	      Recolours an icon. Dim an icon with a colour (Theme.Colors.Ink2), not with transparency: its parts overlap.
	  QuietUI.bar(props) -> Frame
	      A line bar: [Icon] [Track > Ghost, Fill, Tick?, Under] [Value]. Extra keys: Icon (a kind, or nil for none),
	      Height (default Theme.Bar.Height), Tick (0..1 for a healing tick, or nil), Value (false for no number).
	      Default size: the parent's full width, Theme.Bar.RowHeight tall. The line takes the width that is left.
	  QuietUI.setBar(bar, alpha, text?, state?)
	      Sets the fill (0..1) and the number at once, with no tween; state as in QuietUI.barState.
	  QuietUI.barState(bar, state)
	      "rest" (fine: icon and number dimmed), "active" (ink), "low" (Sun), "danger" (Red).
	  QuietUI.key(props) -> Frame
	      A key square: a thin outlined square with a letter and only a little shade inside (Theme.Key.Shade). Extra
	      key: Text. The letter is the child "Label" (a TextLabel); the square grows sideways for a long name.
	      Children: Stroke (the outline), Pad, Label.
	  QuietUI.setKey(key, text)
	  QuietUI.button(props) -> TextButton
	      A plain text button: SemiBold capitals, no box, an underline named "Under" that shows on hover and focus.
	      Extra keys: Font, TextSize (default Theme.TextSize.Label), Height (default 34), Quiet (true for a dimmer rest
	      state, like ROBLOX PLUS). Children: Pad (UIPadding), Shadow, Under. Add behaviour with QuietUI.bindButton.
	  QuietUI.strip(props) -> Frame
	      The slim strip along the bottom of the screen (defeat, spectating): a full-width hairline named "Line" on
	      top and room for one row under it. Extra key: Height (default Theme.Strip.Height). Never a card.
	  QuietUI.letters(holder, text, props?) -> { TextLabel }
	      The spaced title: one label per letter in a row (Roblox has no letter spacing). Clears the holder's letters
	      first, so it can be called again when the text changes. Extra keys: Font (default "Light"), TextSize (default
	      Theme.TextSize.Hero), Gap (default a fifth of the size), Color.
	  QuietUI.selection(props?) -> Frame
	      The gamepad focus outline (a Sun key-square outline) for GuiObject.SelectionImageObject.

	BEHAVIOUR (client)
	  QuietUI.bindButton(button, opts?) -> () -> ()
	      Hover, pressed, gamepad-selected and touch-sized states for a button made by QuietUI.button (or any TextButton
	      with an "Under" child). opts: { quiet = boolean?, onHover = (() -> ())? }. On a touch screen the button is
	      at least 44 px tall. Returns a function that disconnects it. It plays no sound: the caller does.
	  QuietUI.setButtonEnabled(button, enabled)
	  QuietUI.tween(instance, info | seconds, props) -> Tween?
	      Like Theme.tween, but sets the values at once when motion is reduced (then it returns nil).
	  QuietUI.textTransparency(label, t)
	      Sets a label's TextTransparency and its dark stroke together, for code that fades a label every frame.
	      A stroke does not follow its text on its own: fade the text alone and its dark outline stays on screen.
	  QuietUI.fadeText(label, shown, info?) -> Tween?
	      Tweens one label in (to `rest`, the attribute "RestTransparency", or 0) or out (to 1) with its stroke.
	      info: a TweenInfo or seconds (default Theme.Tween.In / Theme.Tween.Out).
	  QuietUI.fadeIn(gui, seconds?)
	  QuietUI.fadeOut(gui, seconds?, keepVisible?)
	      A CanvasGroup fades as one (GroupTransparency). Anything else fades part by part: the first fade remembers
	      each part's own transparency and fadeIn returns to it, so change a part's transparency only while it is
	      shown, or call QuietUI.forget(gui) after you do. fadeIn sets Visible; fadeOut clears it when done unless
	      keepVisible is true. Default times: Theme.Time.In and Theme.Time.Out.
	  QuietUI.forget(gui)
	  QuietUI.reducedMotion() -> boolean
	      The player's reduced-motion setting: Roblox's own (GuiService.ReducedMotionEnabled), or what
	      QuietUI.setReducedMotion(on) last said (nil hands it back to Roblox's setting). The game has no setting of
	      its own for it yet.
	  QuietUI.setReducedMotion(on: boolean?)
	  QuietUI.bindRoot(screenGui) -> getScale
	      = Theme.bindRoot: keeps Root's UIScale and SafePad right for the viewport. Phones stay at scale 1 with 8 px
	      of padding; the screens are built with ScreenInsets = CoreUISafeInsets, so a phone's notch and Roblox's top
	      bar are already outside Root.
	  QuietUI.fit(target, design, opts?) -> () -> number
	      For one part that must shrink on a small screen (the bottom strip on a phone): keeps a UIScale named "Fit"
	      under `target` so that a part `design` (Vector2, design px) big fits inside its parent. Give `target` that
	      size in offsets first (a UIScale shrinks a scale-sized part too). opts: { min = 0.6, max = 1, margin = 0 }.
	      Returns a function that reports the scale.
]]
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local QuietUI = {}

local C = Theme.Colors
local T = Theme.Transparency

----------------------------------------------------------------------------------------------------------------------
-- Construction helpers
----------------------------------------------------------------------------------------------------------------------
-- Sets every property in props on inst except the kit's own keys; Parent last.
local function apply(inst: Instance, props: { [string]: any }?, skip: { [string]: boolean }?)
	if not props then
		return
	end
	local parent: Instance? = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		elseif not (skip and skip[key]) then
			(inst :: any)[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
end

local function plain(name: string, size: UDim2?, position: UDim2?, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	if size then
		f.Size = size
	end
	if position then
		f.Position = position
	end
	if anchor then
		f.AnchorPoint = anchor
	end
	return f
end

local function fontOf(value: any, fallback: string): Font
	if typeof(value) == "Font" then
		return value
	end
	if type(value) == "string" and Theme.Fonts[value] then
		return Theme.Fonts[value]
	end
	return Theme.Fonts[fallback] or Theme.Fonts.Body
end

QuietUI.stroke = Theme.shadow

----------------------------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------------------------
local LABEL_KEYS = { Font = true, Stroke = true, TextSize = true }

function QuietUI.label(props: { [string]: any }?): TextLabel
	local p = props or {}
	local label = Instance.new("TextLabel")
	local px = math.max(Theme.TextSize.Small, tonumber(p.TextSize) or Theme.TextSize.Body)
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = ""
	label.TextColor3 = C.Ink
	label.FontFace = fontOf(p.Font, "Medium")
	label.TextSize = px
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	if p.Stroke ~= false then
		Theme.shadow(label, p.Stroke == "Big" or (p.Stroke == nil and px >= Theme.TextSize.Status))
	end
	apply(label, p, LABEL_KEYS)
	return label
end

function QuietUI.letters(holder: GuiObject, text: string, props: { [string]: any }?): { TextLabel }
	local p = props or {}
	local px = math.max(Theme.TextSize.Small, tonumber(p.TextSize) or Theme.TextSize.Hero)
	local gap = tonumber(p.Gap) or math.floor(px / 5 + 0.5)
	for _, child in ipairs(holder:GetChildren()) do
		if child:GetAttribute("QuietLetter") == true then
			child:Destroy()
		end
	end
	local layout = holder:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Name = "Layout"
		layout.Parent = holder
	end
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, gap)
	local made = {}
	local order = 0
	for _, code in utf8.codes(text) do
		order += 1
		local ch = utf8.char(code)
		if ch == " " then
			-- a word space: a third of an em, on top of the two gaps beside it
			local space = plain("S" .. order, UDim2.fromOffset(math.floor(px * 0.34 + 0.5), 1))
			space.LayoutOrder = order
			space:SetAttribute("QuietLetter", true)
			space.Parent = holder
		else
			local l = QuietUI.label({
				Name = "L" .. order,
				Text = ch,
				Font = p.Font or "Light",
				TextSize = px,
				TextColor3 = p.Color or C.Ink,
				TextXAlignment = Enum.TextXAlignment.Center,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, math.floor(px * 1.15 + 0.5)),
				LayoutOrder = order,
			})
			l:SetAttribute("QuietLetter", true)
			l.Parent = holder
			table.insert(made, l)
		end
	end
	return made
end

----------------------------------------------------------------------------------------------------------------------
-- Lines and icons
----------------------------------------------------------------------------------------------------------------------
local LINE_KEYS = { Vertical = true }

function QuietUI.line(props: { [string]: any }?): Frame
	local p = props or {}
	local vertical = p.Vertical == true
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BorderSizePixel = 0
	line.BackgroundColor3 = C.Ink
	line.BackgroundTransparency = T.Hairline
	line.Size = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1)
	local under = Instance.new("Frame")
	under.Name = "Under"
	under.BorderSizePixel = 0
	under.BackgroundColor3 = C.Shade
	under.BackgroundTransparency = Theme.Stroke.LineTransparency
	if vertical then
		under.Position = UDim2.new(1, 0, 0, 0)
		under.Size = UDim2.new(0, 1, 1, 0)
	else
		under.Position = UDim2.new(0, 0, 1, 0)
		under.Size = UDim2.new(1, 0, 0, 1)
	end
	under.Parent = line
	apply(line, p, LINE_KEYS)
	return line
end

-- Icon parts on a 14 x 14 grid: { shape, x, y, width, height [, rotation] } with x, y the top-left corner.
-- "r" a rectangle, "c" a circle (or a pill), "o" an outlined circle (a ring).
local ICONS: { [string]: { { any } } } = {
	heart = {
		{ "c", 0.2, 1, 7.2, 7.2 },
		{ "c", 6.6, 1, 7.2, 7.2 },
		{ "r", 3.4, 4.2, 7.2, 7.2, 45 },
	},
	food = { -- a fork and a knife
		{ "r", 1, 1, 1.2, 5 },
		{ "r", 3.1, 1, 1.2, 5 },
		{ "r", 5.2, 1, 1.2, 5 },
		{ "r", 1, 5, 5.4, 1.6 },
		{ "r", 2.9, 6, 1.6, 7 },
		{ "c", 9.4, 1, 3, 7.4 },
		{ "r", 10.8, 1, 1.6, 12 },
	},
	drop = { -- the tip's sides meet the bulb on its tangent
		{ "r", 4.67, 3.67, 4.66, 4.66, 45 },
		{ "c", 2.4, 4.6, 9.2, 9.2 },
	},
	run = { -- three speed lines
		{ "r", 5, 3, 8, 1.6 },
		{ "r", 1, 6.2, 12, 1.6 },
		{ "r", 5, 9.4, 8, 1.6 },
	},
	diamond = {
		{ "r", 3.2, 3.2, 7.6, 7.6, 45 },
	},
	dot = {
		{ "c", 4, 4, 6, 6 },
	},
	ring = {
		{ "o", 2.5, 2.5, 9, 9 },
	},
	plus = {
		{ "r", 5.8, 1.5, 2.4, 11 },
		{ "r", 1.5, 5.8, 11, 2.4 },
	},
	blade = { -- a small sword, point up and to the right
		{ "r", 6.1, 0.2, 1.8, 9.6, 45 },
		{ "r", 0.9, 7.6, 5.4, 1.6, 45 },
		{ "r", 1.3, 8.3, 1.6, 3.2, 45 },
	},
}

local ICON_KEYS = { Px = true, Color = true }

local function iconLayer(name: string, parts: { { any } }, color: Color3, transparency: number, dy: number, z: number): Frame
	local layer = plain(name, UDim2.fromScale(1, 1), UDim2.fromOffset(0, dy))
	layer.ZIndex = z
	for i, part in ipairs(parts) do
		local shape = part[1]
		local f = Instance.new("Frame")
		f.Name = "P" .. i
		f.BorderSizePixel = 0
		f.Position = UDim2.fromScale(part[2] / 14, part[3] / 14)
		f.Size = UDim2.fromScale(part[4] / 14, part[5] / 14)
		f.Rotation = part[6] or 0
		if shape == "o" then
			f.BackgroundTransparency = 1
			local outline = Instance.new("UIStroke")
			outline.Name = "Ink"
			outline.Color = color
			outline.Transparency = transparency
			outline.Thickness = 1.5
			outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			outline.Parent = f
		else
			f.BackgroundColor3 = color
			f.BackgroundTransparency = transparency
		end
		if shape ~= "r" then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = f
		end
		f.Parent = layer
	end
	return layer
end

function QuietUI.icon(kind: string, props: { [string]: any }?): Frame
	local p = props or {}
	local parts = ICONS[kind] or ICONS.dot
	local px = tonumber(p.Px) or Theme.Bar.Icon
	local icon = plain("Icon", UDim2.fromOffset(px, px))
	icon:SetAttribute("Kind", kind)
	iconLayer("Drop", parts, C.Shade, 0.45, 1, 1).Parent = icon
	iconLayer("Ink", parts, p.Color or C.Ink, 0, 0, 2).Parent = icon
	apply(icon, p, ICON_KEYS)
	return icon
end

function QuietUI.tint(icon: Instance, color: Color3)
	local layer = icon:FindFirstChild("Ink")
	if not layer then
		return
	end
	for _, part in ipairs(layer:GetChildren()) do
		if part:IsA("Frame") then
			local outline = part:FindFirstChild("Ink")
			if outline and outline:IsA("UIStroke") then
				outline.Color = color
			else
				part.BackgroundColor3 = color
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------------
-- Line bar
----------------------------------------------------------------------------------------------------------------------
local BAR_KEYS = { Icon = true, Height = true, Tick = true, Value = true }

function QuietUI.bar(props: { [string]: any }?): Frame
	local p = props or {}
	local B = Theme.Bar
	local height = tonumber(p.Height) or B.Height
	local row = plain("Bar", UDim2.new(1, 0, 0, B.RowHeight))
	local left = 0
	if p.Icon then
		local icon = QuietUI.icon(p.Icon, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
		icon.Parent = row
		left = B.Icon + B.Gap
	end
	local right = if p.Value == false then 0 else B.ValueWidth + B.Gap
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, left, 0.5, 0)
	track.Size = UDim2.new(1, -(left + right), 0, height)
	track.BackgroundColor3 = C.Ink
	track.BackgroundTransparency = T.BarTrack
	track.Parent = row
	local under = Instance.new("Frame") -- the 1 px shade under the line
	under.Name = "Under"
	under.BorderSizePixel = 0
	under.Position = UDim2.new(0, 0, 1, 0)
	under.Size = UDim2.new(1, 0, 0, 1)
	under.BackgroundColor3 = C.Shade
	under.BackgroundTransparency = Theme.Stroke.LineTransparency
	under.ZIndex = 1
	under.Parent = track
	local ghost = Instance.new("Frame")
	ghost.Name = "Ghost"
	ghost.BorderSizePixel = 0
	ghost.Size = UDim2.fromScale(1, 1)
	ghost.BackgroundColor3 = C.Ink
	ghost.BackgroundTransparency = T.BarGhost
	ghost.ZIndex = 1
	ghost.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = C.Ink
	fill.BackgroundTransparency = 0
	fill.ZIndex = 2
	fill.Parent = track
	if type(p.Tick) == "number" then
		local tick = Instance.new("Frame")
		tick.Name = "Tick"
		tick.BorderSizePixel = 0
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(math.clamp(p.Tick, 0, 1), 0.5)
		tick.Size = UDim2.new(0, 1, 1, B.TickOverhang * 2)
		tick.BackgroundColor3 = C.Ink
		tick.BackgroundTransparency = 0.25
		tick.ZIndex = 3
		tick.Parent = track
	end
	if p.Value ~= false then
		QuietUI.label({
			Name = "Value",
			Text = "",
			Font = "Mono",
			TextSize = Theme.TextSize.Number,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.new(0, B.ValueWidth, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
	end
	apply(row, p, BAR_KEYS)
	return row
end

local BAR_STATES: { [string]: { color: Color3, icon: Color3, text: number } } = {
	rest = { color = C.Ink, icon = C.Ink2, text = T.TextRest },
	active = { color = C.Ink, icon = C.Ink, text = 0 },
	low = { color = C.Sun, icon = C.Sun, text = 0 },
	danger = { color = C.Red, icon = C.Red, text = 0 },
}

function QuietUI.barState(bar: Instance, state: string)
	local s = BAR_STATES[state] or BAR_STATES.active
	local track = bar:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		fill.BackgroundColor3 = s.color
	end
	local value = bar:FindFirstChild("Value")
	if value and value:IsA("TextLabel") then
		value.TextColor3 = s.color
		QuietUI.textTransparency(value, s.text) -- its Shadow stroke fades with the digits
	end
	local icon = bar:FindFirstChild("Icon")
	if icon then
		QuietUI.tint(icon, s.icon)
	end
end

function QuietUI.setBar(bar: Instance, alpha: number, text: string?, state: string?)
	local a = math.clamp(tonumber(alpha) or 0, 0, 1)
	local track = bar:FindFirstChild("Track")
	if track then
		local fill, ghost = track:FindFirstChild("Fill"), track:FindFirstChild("Ghost")
		if fill and fill:IsA("GuiObject") then
			fill.Size = UDim2.fromScale(a, 1)
		end
		if ghost and ghost:IsA("GuiObject") then
			ghost.Size = UDim2.fromScale(a, 1)
		end
	end
	if text ~= nil then
		local value = bar:FindFirstChild("Value")
		if value and value:IsA("TextLabel") then
			value.Text = text
		end
	end
	if state then
		QuietUI.barState(bar, state)
	end
end

----------------------------------------------------------------------------------------------------------------------
-- Key square
----------------------------------------------------------------------------------------------------------------------
local KEY_KEYS = { Text = true }

function QuietUI.key(props: { [string]: any }?): Frame
	local p = props or {}
	local K = Theme.Key
	local key = Instance.new("Frame")
	key.Name = "Key"
	key.BorderSizePixel = 0
	key.Size = UDim2.fromOffset(K.Size, K.Size)
	key.AutomaticSize = Enum.AutomaticSize.X
	-- no fill to speak of: a little shade inside, so the outline and the letter hold over a bright sky
	key.BackgroundColor3 = C.Shade
	key.BackgroundTransparency = K.Shade
	local corner = Instance.new("UICorner")
	corner.CornerRadius = K.Corner
	corner.Parent = key
	local box = Instance.new("UIStroke")
	box.Name = "Stroke"
	box.Color = C.Ink
	box.Transparency = T.KeyStroke
	box.Thickness = K.Thickness
	box.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	box.Parent = key
	local pad = Instance.new("UIPadding")
	pad.Name = "Pad"
	pad.PaddingLeft = UDim.new(0, K.PadX)
	pad.PaddingRight = UDim.new(0, K.PadX)
	pad.Parent = key
	local label = QuietUI.label({
		Name = "Label",
		Text = if p.Text ~= nil then tostring(p.Text) else "",
		Font = "MonoMedium",
		TextSize = Theme.TextSize.Number,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
	})
	-- one letter is narrower than the square: the label is at least the square's inside, so the letter sits centred
	local floor = Instance.new("UISizeConstraint")
	floor.Name = "Floor"
	floor.MinSize = Vector2.new(K.Size - K.PadX * 2, 0)
	floor.Parent = label
	label.Parent = key
	apply(key, p, KEY_KEYS)
	return key
end

function QuietUI.setKey(key: Instance, text: string)
	local label = key:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

----------------------------------------------------------------------------------------------------------------------
-- Text button
----------------------------------------------------------------------------------------------------------------------
local BUTTON_KEYS = { Font = true, TextSize = true, Height = true, Quiet = true }
local BUTTON_REST, BUTTON_QUIET, BUTTON_OFF = 0.1, 0.32, 0.6

function QuietUI.button(props: { [string]: any }?): TextButton
	local p = props or {}
	local px = math.max(Theme.TextSize.Small, tonumber(p.TextSize) or Theme.TextSize.Label)
	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.AutoButtonColor = false
	button.BackgroundColor3 = C.Shade
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.TextColor3 = C.Ink
	button.TextTransparency = if p.Quiet then BUTTON_QUIET else BUTTON_REST
	button.FontFace = fontOf(p.Font, "SemiBold")
	button.TextSize = px
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.fromOffset(0, tonumber(p.Height) or 34)
	button:SetAttribute("Quiet", p.Quiet == true)
	Theme.shadow(button, false)
	local pad = Instance.new("UIPadding")
	pad.Name = "Pad"
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 2)
	pad.Parent = button
	local under = Instance.new("Frame")
	under.Name = "Under"
	under.BorderSizePixel = 0
	under.AnchorPoint = Vector2.new(0, 1)
	under.Position = UDim2.new(0, 0, 1, -5)
	under.Size = UDim2.new(1, 0, 0, 1)
	under.BackgroundColor3 = C.Ink
	under.BackgroundTransparency = 1 -- shown on hover and focus (QuietUI.bindButton)
	under.Parent = button
	apply(button, p, BUTTON_KEYS)
	return button
end

function QuietUI.selection(props: { [string]: any }?): Frame
	local frame = plain("Selection", UDim2.new(1, 8, 1, 2), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Key.Corner
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = C.Sun
	stroke.Transparency = 0.05
	stroke.Thickness = Theme.Key.Thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	apply(frame, props)
	return frame
end

----------------------------------------------------------------------------------------------------------------------
-- Strip
----------------------------------------------------------------------------------------------------------------------
local STRIP_KEYS = { Height = true }

function QuietUI.strip(props: { [string]: any }?): Frame
	local p = props or {}
	local strip = plain("Strip", UDim2.new(1, 0, 0, tonumber(p.Height) or Theme.Strip.Height), UDim2.fromScale(0, 1), Vector2.new(0, 1))
	QuietUI.line({ Name = "Line", Parent = strip })
	apply(strip, p, STRIP_KEYS)
	return strip
end

----------------------------------------------------------------------------------------------------------------------
-- Motion
----------------------------------------------------------------------------------------------------------------------
local motionOverride: boolean? = nil

function QuietUI.setReducedMotion(on: boolean?)
	motionOverride = on
end

function QuietUI.reducedMotion(): boolean
	if motionOverride ~= nil then
		return motionOverride
	end
	local ok, reduced = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and reduced == true
end

function QuietUI.tween(instance: Instance, info: TweenInfo | number, props: { [string]: any }): Tween?
	if QuietUI.reducedMotion() then
		for key, value in pairs(props) do
			(instance :: any)[key] = value
		end
		return nil
	end
	local tweenInfo = if typeof(info) == "TweenInfo"
		then info
		else TweenInfo.new(math.max(0, tonumber(info) or Theme.Time.In), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(instance, tweenInfo :: TweenInfo, props)
	t:Play()
	return t
end

-- The stroke's own transparency when its text is fully shown.
local function strokeRest(stroke: UIStroke): number
	local rest = stroke:GetAttribute("Rest")
	if type(rest) ~= "number" then
		rest = if stroke.Thickness >= Theme.Stroke.BigThickness then Theme.Stroke.BigTransparency else Theme.Stroke.Transparency
	end
	return rest
end

function QuietUI.textTransparency(label: GuiObject, t: number)
	local a = math.clamp(t, 0, 1);
	(label :: any).TextTransparency = a
	local stroke = label:FindFirstChild("Shadow")
	if stroke and stroke:IsA("UIStroke") then
		local rest = strokeRest(stroke)
		stroke.Transparency = rest + (1 - rest) * a
	end
end

function QuietUI.fadeText(label: GuiObject, shown: boolean, info: (TweenInfo | number)?): Tween?
	local rest = label:GetAttribute("RestTransparency")
	local target = if shown then (if type(rest) == "number" then rest else 0) else 1
	local tweenInfo: TweenInfo | number = info or (if shown then Theme.Tween.In else Theme.Tween.Out)
	local stroke = label:FindFirstChild("Shadow")
	if stroke and stroke:IsA("UIStroke") then
		local base = strokeRest(stroke)
		QuietUI.tween(stroke, tweenInfo, { Transparency = base + (1 - base) * target })
	end
	return QuietUI.tween(label, tweenInfo, { TextTransparency = target })
end

-- What fades on each kind of object, part by part.
local function fadeProps(inst: Instance): { string }?
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		return { "TextTransparency", "BackgroundTransparency" }
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		return { "ImageTransparency", "BackgroundTransparency" }
	elseif inst:IsA("ViewportFrame") then
		return { "ImageTransparency", "BackgroundTransparency" }
	elseif inst:IsA("ScrollingFrame") then
		return { "ScrollBarImageTransparency", "BackgroundTransparency" }
	elseif inst:IsA("CanvasGroup") then
		return { "GroupTransparency" }
	elseif inst:IsA("GuiObject") then
		return { "BackgroundTransparency" }
	elseif inst:IsA("UIStroke") then
		return { "Transparency" }
	end
	return nil
end

local remembered: { [Instance]: { { inst: Instance, prop: string, value: number } } } = setmetatable({}, { __mode = "k" }) :: any
local fadeTokens: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function remember(gui: Instance): { { inst: Instance, prop: string, value: number } }
	local list = remembered[gui]
	if list then
		return list
	end
	list = {}
	local function add(inst: Instance)
		local props = fadeProps(inst)
		if props then
			for _, prop in ipairs(props) do
				local value = (inst :: any)[prop]
				if type(value) == "number" and value < 1 then
					table.insert(list, { inst = inst, prop = prop, value = value })
				end
			end
		end
	end
	add(gui)
	for _, d in ipairs(gui:GetDescendants()) do
		-- a CanvasGroup inside fades as one: its own parts are left alone
		local inner = d:FindFirstAncestorWhichIsA("CanvasGroup")
		if not (inner and inner ~= gui and inner:IsDescendantOf(gui)) then
			add(d)
		end
	end
	remembered[gui] = list
	return list
end

function QuietUI.forget(gui: Instance)
	remembered[gui] = nil
end

local function fade(gui: GuiObject, shown: boolean, seconds: number, keepVisible: boolean?)
	local token = (fadeTokens[gui] or 0) + 1
	fadeTokens[gui] = token
	local instant = seconds <= 0 or QuietUI.reducedMotion()
	local info = TweenInfo.new(math.max(0.01, seconds), Enum.EasingStyle.Quad, if shown then Enum.EasingDirection.Out else Enum.EasingDirection.In)
	if shown then
		gui.Visible = true
	end
	if gui:IsA("CanvasGroup") then
		local target = if shown then 0 else 1
		if instant then
			gui.GroupTransparency = target
		else
			TweenService:Create(gui, info, { GroupTransparency = target }):Play()
		end
	else
		-- part by part: the first fade remembers each part's own transparency
		local list = remember(gui)
		for _, item in ipairs(list) do
			if item.inst.Parent then
				local target = if shown then item.value else 1
				if instant then
					(item.inst :: any)[item.prop] = target
				else
					TweenService:Create(item.inst, info, { [item.prop] = target }):Play()
				end
			end
		end
	end
	if not shown and not keepVisible then
		if instant then
			gui.Visible = false
		else
			task.delay(seconds, function()
				if fadeTokens[gui] == token then
					gui.Visible = false
				end
			end)
		end
	end
end

function QuietUI.fadeIn(gui: GuiObject, seconds: number?)
	if not gui.Visible and not gui:IsA("CanvasGroup") then
		-- coming back from hidden: start from clear, so it does not pop
		local list = remember(gui)
		if (fadeTokens[gui] or 0) == 0 then
			for _, item in ipairs(list) do
				(item.inst :: any)[item.prop] = 1
			end
		end
	end
	fade(gui, true, tonumber(seconds) or Theme.Time.In, true)
end

function QuietUI.fadeOut(gui: GuiObject, seconds: number?, keepVisible: boolean?)
	fade(gui, false, tonumber(seconds) or Theme.Time.Out, keepVisible)
end

----------------------------------------------------------------------------------------------------------------------
-- Button behaviour
----------------------------------------------------------------------------------------------------------------------
local TOUCH_MIN = 44

function QuietUI.setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.Selectable = enabled
	button:SetAttribute("Disabled", not enabled)
	local rest = if button:GetAttribute("Quiet") == true then BUTTON_QUIET else BUTTON_REST
	button.TextTransparency = if enabled then rest else BUTTON_OFF
	local under = button:FindFirstChild("Under")
	if under and under:IsA("GuiObject") then
		under.BackgroundTransparency = 1
	end
end

function QuietUI.bindButton(button: TextButton, opts: { [string]: any }?): () -> ()
	local o = opts or {}
	if o.quiet ~= nil then
		button:SetAttribute("Quiet", o.quiet == true)
	end
	local under = button:FindFirstChild("Under")
	local hover, pressed, focused = false, false, false
	local connections: { RBXScriptConnection } = {}

	if UserInputService.TouchEnabled then
		-- a finger needs 44 px: the text stays where it was, the button grows around it
		local floor = button:FindFirstChild("TouchFloor")
		if not floor then
			local made = Instance.new("UISizeConstraint")
			made.Name = "TouchFloor"
			made.MinSize = Vector2.new(TOUCH_MIN, TOUCH_MIN)
			made.Parent = button
		end
	end
	if button.SelectionImageObject == nil then
		-- the engine draws a SelectionImageObject itself: it is not parented anywhere
		button.SelectionImageObject = QuietUI.selection()
	end

	local function paint()
		if button:GetAttribute("Disabled") == true then
			return
		end
		local rest = if button:GetAttribute("Quiet") == true then BUTTON_QUIET else BUTTON_REST
		local lit = hover or focused
		local text = if pressed then 0.3 elseif lit then 0 else rest
		QuietUI.tween(button, Theme.Tween.Fast, { TextTransparency = text })
		if under and under:IsA("GuiObject") then
			QuietUI.tween(under, Theme.Tween.Fast, { BackgroundTransparency = if lit and not pressed then 0.15 else 1 })
		end
	end

	table.insert(connections, button.MouseEnter:Connect(function()
		hover = true
		paint()
		if type(o.onHover) == "function" and button:GetAttribute("Disabled") ~= true then
			task.spawn(o.onHover)
		end
	end))
	table.insert(connections, button.MouseLeave:Connect(function()
		hover, pressed = false, false
		paint()
	end))
	table.insert(connections, button.InputBegan:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
			or io.KeyCode == Enum.KeyCode.ButtonA then
			pressed = true
			paint()
		end
	end))
	table.insert(connections, button.InputEnded:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
			or io.KeyCode == Enum.KeyCode.ButtonA then
			pressed = false
			if io.UserInputType == Enum.UserInputType.Touch then
				hover = false -- a finger leaves no hover behind
			end
			paint()
		end
	end))
	table.insert(connections, button.SelectionGained:Connect(function()
		focused = true
		paint()
	end))
	table.insert(connections, button.SelectionLost:Connect(function()
		focused, pressed = false, false
		paint()
	end))
	paint()
	return function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end
end

----------------------------------------------------------------------------------------------------------------------
-- Scale
----------------------------------------------------------------------------------------------------------------------
QuietUI.bindRoot = Theme.bindRoot

-- The product of every UIScale above gui (not gui's own).
local function scaleAbove(gui: Instance): number
	local s = 1
	local node = gui.Parent
	while node and node:IsA("GuiObject") do
		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("UIScale") then
				s *= child.Scale
			end
		end
		node = node.Parent
	end
	return if s > 0 then s else 1
end

function QuietUI.fit(target: GuiObject, design: Vector2, opts: { [string]: any }?): () -> number
	local o = opts or {}
	local low, high = tonumber(o.min) or 0.6, tonumber(o.max) or 1
	local margin = tonumber(o.margin) or 0
	local existing = target:FindFirstChild("Fit")
	local fitScale: UIScale = if existing and existing:IsA("UIScale") then existing else Instance.new("UIScale")
	fitScale.Name = "Fit"
	fitScale.Parent = target
	local parentConnection: RBXScriptConnection? = nil
	local function update()
		local parent = target.Parent
		if not parent or not parent:IsA("GuiObject") then
			return
		end
		local above = scaleAbove(target)
		local room = parent.AbsoluteSize / above
		if room.X < 2 or room.Y < 2 or design.X <= 0 or design.Y <= 0 then
			return
		end
		local s = math.min((room.X - margin * 2) / design.X, (room.Y - margin * 2) / design.Y)
		s = math.clamp(s, low, high)
		if math.abs(fitScale.Scale - s) > 0.004 then
			fitScale.Scale = s
		end
	end
	local function hook()
		if parentConnection then
			parentConnection:Disconnect()
			parentConnection = nil
		end
		local parent = target.Parent
		if parent and parent:IsA("GuiObject") then
			parentConnection = parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
		end
		update()
	end
	target:GetPropertyChangedSignal("Parent"):Connect(hook)
	hook()
	return function()
		return fitScale.Scale
	end
end

return QuietUI
