--[[
	Cards - "Quiet cards", the one kit every menu where a player chooses, owns, earns or buys something is built from
	(docs/design/CardMenusAndShop.md section 1; the owner, 19 and 20 Nov: pictures, edges, one action and a state in
	place of "text chunks"). Our look: matte dark panels with some transparency, our palette and fonts, no gloss, no
	bevel, no glow, no candy colours. The in-round HUD stays Quiet and never uses this kit.

	Client and edit time. The builders only make Instances; bind* / hold / itemView / countdown add behaviour (client).
	Sizes are design px (1280 x 720 at UIScale 1, Theme.bindRoot), so 1080p is x1.25.

	TOKENS
	  Cards.Surface      Panel, Card, Well, Hair: { color, transparency }; Cards.Corner { Tile = 6, Card = 10, Panel = 12 }
	  Cards.Grades       Plain, Crafted, Prized, Storied, Fabled, Honour: { name, color, label (text colour), order, edge }
	  Cards.GradeOrder   { "Plain", "Crafted", "Prized", "Storied", "Fabled" }
	  Cards.grade(name) -> def?            Cards.gradeFromRarity("Common".."Legendary" | "Free") -> grade name?
	  Cards.metrics(viewport?) -> { class = "Phone" | "Tablet" | "PC" | "TV", tile, small, card = Vector2, touch,
	                                 word, name, gap, phone }
	  Weapons and Strongbox prizes show STARS, never a grade edge (pass Stars, not Grade).

	BUILDERS (each returns the root; props are Instance properties plus the extra keys named)
	  Cards.panel(props)                  the screen panel (Panel at 80%, corner 12, a hairline, one soft shade)
	  Cards.tile(def) -> TextButton       the atom: well + picture + name + grade label + grade edge and bar.
	        def: Name, Size, Position, AnchorPoint, LayoutOrder, Parent, Title (name, bottom-left), Sub (a second word
	             under it), Grade, Stars (weapons: a star row after the name), Label (top-left caps, default the grade),
	             Item (item id: a live 3D view), ItemStars, Icon (Icons name), Picture (fn(well) that draws the picture),
	             Count ("x3" bottom-right), Wide (2.5:1 weapon tile: the name sits on the picture), Selectable (default
	             true), OnActivate (fn), Hover (fn(on)), NoName (picture only).
	  Cards.slot(def)                     an empty or filled slot: a dashed-feel faint edge and "+" or its own icon.
	        def as tile, plus Empty (boolean), Caption (a label over the slot, right-aligned to its left: "Kill effect").
	  Cards.card(def) -> TextButton       a picker card: picture well (top), name, sub (caps), up to two lines of text,
	        a fact line, optional child row and button. def: as tile, plus Text, Fact, FactIcon ("cooldown" | "coin"),
	        WellHeight (share, default 0.42), Button = { kind, text, onActivate }, Row (fn(frame) to fill a row of small
	        tiles under the text), Footer (dim line at the bottom).
	  Cards.button(kind, text, props)     kind "Primary" (Ink fill) | "Secondary" (Ink outline) | "Sun" (CLAIM / OPEN
	        only) | "Off" | "Price" (coin + RobotoMono number: props.Price) | "Ghost" (text only). Height 40 (44 touch).
	  Cards.tabs(list, props) -> (Frame, api)   list { { key, text, badge? } }; api.select(key), api.onChanged(fn(key)),
	        api.setBadge(key, n?), api.current(), api.buttons[key], api.step(dir) (LB / RB)
	  Cards.sideList(items, props) -> (ScrollingFrame, api)   items { { key, title, sub?, icon?, item?, price? } }
	  Cards.stepper(min, max, value, props) -> (Frame, api)   api.get(), api.set(n), api.onChanged(fn)
	  Cards.bar(props) -> Frame           6 px progress line (props.Height for a tier bar); Cards.setBar(bar, a, sun?)
	  Cards.countdown(endUnix, props) -> TextLabel   RobotoMono "18:21:32" (or "3d 04h"), Ink, never red or flashing
	  Cards.oddsList(rows, props) -> Frame   rows { { name, color?, pct, pct2? } }; a bar at the true share and the %;
	        "Total 100%" under it; props.Details (fn) adds the worded ODDS DETAILS button. Cards.setOdds(frame, rows)
	  Cards.stars(n, props) -> TextLabel  "★★★★" (4 and 5 in Sun) with the dim rest ("★★★☆☆" style, max props.Max)
	  Cards.hints(list, props) -> Frame   { { key = "LB", text = "tabs" }, ... } key squares with a word
	  Cards.grid(props) -> ScrollingFrame   a vertical scroll with a UIGridLayout (props.Cell Vector2, props.Gap)
	  Cards.section(text, props) -> TextLabel   a caps section title (SemiBold, Ink) with an optional dim tail (props.Tail)
	  Cards.label(text, props)            a plain Montserrat label (props.Font, TextSize, Color)
	  Cards.focusRing() -> Frame          the gamepad focus: the Selected outline + a soft Ink halo (SelectionImageObject)

	STATES (every tile and card): Cards.setState(gui, state, value)
	  "Owned" (tick disc), "Equipped" / "Chosen" (an Ink tag; value = the word, or true), "Selected" (2.5 px Ink outline
	  3 px outside), "New" (a Sun dot until hovered once), "Claimable" (Sun edge), "Locked" (value = the unlock rule:
	  the picture dims to 32%, a padlock, the rule in one line), "Disabled" (no input, dimmed).

	BEHAVIOUR (client)
	  Cards.itemView(parent, itemId, opts?) -> (ViewportFrame?, api)   a live 3D view of an item already in the place
	        (Shared.ItemModels), lit matte, framed; opts { Stars, Turn = "hover" | "drag" | "slow" | "none", Zoom,
	        Rotation (CFrame) }. Over Cards.MAX_VIEWS live views on screen it returns nil (show an icon instead).
	        api.setItem(id, stars), api.turn(deg), api.destroy()
	  Cards.hold(button, seconds, onDone) -> () -> ()   "hold to confirm": a fill grows inside the button while the
	        mouse, finger or A is held; onDone once it is full. Returns a disconnect.
	  Cards.dimWorld(on)                  the world behind a menu: a soft blur (Size 12) and slightly darker, eased 0.25 s
	  Cards.bindShoulders(name, onPrev, onNext) -> () -> ()   LB / RB (and Q / E on a keyboard) for tabs
	  Cards.trailPreview(parent, colors, opts?) -> (Frame, api)  a 2D trail sweeping left to right every 1.2 s (cards;
	        ViewportFrames do not draw Trails or Beams). opts { Glow, Width, Period, Still }. api.setColors(), api.stop()
]]
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = script.Parent
local Theme = require(Shared:WaitForChild("Theme"))
local Icons = require(Shared:WaitForChild("Icons"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))

local Cards = {}

-- (ui-motion) hover, focus and press ease (QuietUI.Motion.Hover / Press) instead of stepping; a later plain set cancels
-- a running ease, so a state set at once is never overwritten by an old hover tween. Reduce Motion: set at once.
local easing: { [Instance]: { [string]: Tween } } = setmetatable({}, { __mode = "k" }) :: any
local function ease(inst: Instance, prop: string, value: any, info: TweenInfo?)
	local running = easing[inst]
	if running and running[prop] then
		running[prop]:Cancel()
		running[prop] = nil
	end
	if info and not QuietUI.reducedMotion() and (inst :: any)[prop] ~= value then
		local t = TweenService:Create(inst, info, { [prop] = value })
		if not running then
			running = {}
			easing[inst] = running
		end
		(running :: any)[prop] = t
		t:Play()
	else
		(inst :: any)[prop] = value
	end
end

local C = Theme.Colors
local F = Theme.Fonts
local INK, INK2, SHADE, SUN = C.Ink, C.Ink2, C.Shade, C.Sun

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

--------------------------------------------------------------------------------------------------------------------
-- Tokens
--------------------------------------------------------------------------------------------------------------------

Cards.Surface = {
	Panel = { color = rgb(17, 20, 23), transparency = 0.20 }, -- Shade lifted, 80%
	Card = { color = rgb(32, 37, 41), transparency = 0.14 }, -- 86%
	Well = { color = rgb(8, 9, 12), transparency = 0.45 },
	Hair = { color = INK, transparency = 0.88 },
	Edge = { color = INK, transparency = 0.82 }, -- a card's own 1.5 px edge
}
Cards.Corner = { Tile = 6, Card = 10, Panel = 12 }
Cards.MAX_VIEWS = 24

Cards.Grades = {
	Plain = { name = "Plain", color = rgb(163, 157, 144), order = 1, edge = 0.30 },
	Crafted = { name = "Crafted", color = rgb(184, 122, 82), order = 2, edge = 0.25 },
	Prized = { name = "Prized", color = rgb(94, 158, 142), order = 3, edge = 0.20 },
	Storied = { name = "Storied", color = rgb(158, 92, 120), label = rgb(197, 138, 163), order = 4, edge = 0.15 },
	Fabled = { name = "Fabled", color = rgb(201, 211, 224), order = 5, edge = 0, double = true },
	Honour = { name = "Honour", color = rgb(232, 217, 176), order = 6, edge = 0 },
}
Cards.GradeOrder = { "Plain", "Crafted", "Prized", "Storied", "Fabled" }

function Cards.grade(name: any)
	return if type(name) == "string" then Cards.Grades[name] else nil
end

-- The old loot words (trails were priced by them) -> the card grades. "Free" has no grade.
local FROM_RARITY = { Common = "Crafted", Uncommon = "Crafted", Rare = "Prized", Epic = "Storied", Legendary = "Fabled" }
function Cards.gradeFromRarity(r: any): string?
	return if type(r) == "string" then FROM_RARITY[r] else nil
end

function Cards.metrics(viewport: Vector2?)
	local v = viewport
	if not v then
		local camera = workspace.CurrentCamera
		v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	local short = math.min(v.X, v.Y)
	if GuiService:IsTenFootInterface() then
		return { class = "TV", tile = 112, small = 84, card = Vector2.new(220, 290), touch = 56, word = 18, name = 22, gap = 14, phone = false }
	elseif short <= 500 then
		return { class = "Phone", tile = 72, small = 52, card = Vector2.new(150, 204), touch = 44, word = 14, name = 16, gap = 8, phone = true }
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return { class = "Tablet", tile = 88, small = 64, card = Vector2.new(168, 226), touch = 48, word = 15, name = 17, gap = 10, phone = false }
	end
	return { class = "PC", tile = 96, small = 64, card = Vector2.new(176, 236), touch = 40, word = 15, name = 17, gap = 12, phone = false }
end

--------------------------------------------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------------------------------------------

local KIT_KEYS = {
	Title = true, Sub = true, Grade = true, Stars = true, Label = true, Item = true, ItemStars = true, Icon = true,
	Picture = true, Count = true, Wide = true, Selectable = true, OnActivate = true, Hover = true, NoName = true,
	Empty = true, Caption = true, Text = true, Fact = true, FactIcon = true, WellHeight = true, Button = true, Row = true,
	Footer = true, Price = true, Tail = true, Cell = true, Gap = true, Details = true, Color = true, Font = true,
	TextSize = true, Max = true, Height = true, Turn = true, Big = true, NameSize = true, TextLines = true, Badge = true,
	Small = true, Start = true, Horizontal = true, Zoom = true,
}

local function apply(inst: Instance, props: { [string]: any }?)
	if not props then
		return
	end
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" and not KIT_KEYS[key] then
			(inst :: any)[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
end

local function corner(gui: GuiObject, px: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = gui
	return c
end

local function stroke(gui: GuiObject, color: Color3, transparency: number, thickness: number, name: string?): UIStroke
	local s = Instance.new("UIStroke")
	s.Name = name or "Edge"
	s.Color = color
	s.Transparency = transparency
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = gui
	return s
end

local function frame(name: string, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	if parent then
		f.Parent = parent
	end
	return f
end

-- A text label in our fonts: the card kit's text has no dark stroke (it sits on a matte surface, not on the world),
-- except names written on a picture (Shade stroke, as the design page says).
local function text(name: string, value: string, font: Font, size: number, color: Color3?, parent: Instance?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Text = value
	l.FontFace = font
	l.TextSize = math.max(Theme.TextSize.Small, size)
	l.TextColor3 = color or INK
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	if parent then
		l.Parent = parent
	end
	return l
end

local function onPicture(label: TextLabel)
	local s = Instance.new("UIStroke")
	s.Name = "Shadow"
	s.Color = SHADE
	s.Thickness = 1.5
	s.Transparency = 0.35
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = label
end

function Cards.label(value: string, props: { [string]: any }?): TextLabel
	local p = props or {}
	local font = if typeof(p.Font) == "Font" then p.Font else (F[p.Font or "Medium"] or F.Medium)
	local l = text("Label", value, font, p.TextSize or 15, p.Color or INK)
	apply(l, p)
	return l
end

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
Cards.comma = comma

--------------------------------------------------------------------------------------------------------------------
-- Focus ring and the world behind a menu
--------------------------------------------------------------------------------------------------------------------

function Cards.focusRing(): Frame
	local root = frame("CardFocus")
	root.Size = UDim2.fromScale(1, 1)
	local ring = frame("Ring", root)
	ring.Position = UDim2.fromOffset(-3, -3)
	ring.Size = UDim2.new(1, 6, 1, 6)
	corner(ring, 9)
	stroke(ring, INK, 0, 2.5, "Line")
	local halo = frame("Halo", root)
	halo.Position = UDim2.fromOffset(-7, -7)
	halo.Size = UDim2.new(1, 14, 1, 14)
	corner(halo, 13)
	stroke(halo, INK, 0.88, 4, "Line")
	return root
end

local dimTweens: { Tween } = {}
local dimCount = 0 -- several screens can ask at once (the Edit panel, then Inspect on top): the blur stays until the last lets go
function Cards.dimWorld(on: boolean)
	dimCount = math.max(0, dimCount + (if on then 1 else -1))
	on = dimCount > 0
	for _, t in ipairs(dimTweens) do
		t:Cancel()
	end
	table.clear(dimTweens)
	local blur = Lighting:FindFirstChild("CardsBlur") :: BlurEffect?
	local cc = Lighting:FindFirstChild("CardsDim") :: ColorCorrectionEffect?
	if on then
		if not blur then
			blur = Instance.new("BlurEffect")
			blur.Name = "CardsBlur"
			blur.Size = 0
			blur.Parent = Lighting
		end
		if not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "CardsDim"
			cc.Parent = Lighting
		end
	end
	local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if blur then
		local t = TweenService:Create(blur, info, { Size = if on then 12 else 0 })
		t:Play()
		table.insert(dimTweens, t)
		if not on then
			t.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and blur then
					blur:Destroy()
				end
			end)
		end
	end
	if cc then
		local t = TweenService:Create(cc, info, { Brightness = if on then -0.06 else 0, Saturation = if on then -0.1 else 0 })
		t:Play()
		table.insert(dimTweens, t)
		if not on then
			t.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and cc then
					cc:Destroy()
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------------------------------------------

function Cards.panel(props: { [string]: any }?): Frame
	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.BorderSizePixel = 0
	p.BackgroundColor3 = Cards.Surface.Panel.color
	p.BackgroundTransparency = Cards.Surface.Panel.transparency
	corner(p, Cards.Corner.Panel)
	stroke(p, INK, 0.9, 1, "Hair")
	-- one soft shade under the panel: three widening layers, very faint (no drop shadow image, nothing uploaded)
	for i = 1, 3 do
		local s = Instance.new("Frame")
		s.Name = "Shade" .. i
		s.BorderSizePixel = 0
		s.BackgroundColor3 = SHADE
		s.BackgroundTransparency = 0.86 + i * 0.03
		s.Position = UDim2.fromOffset(-i * 5, -i * 5 + 6)
		s.Size = UDim2.new(1, i * 10, 1, i * 10)
		s.ZIndex = -1
		corner(s, Cards.Corner.Panel + i * 5)
		s.Parent = p
	end
	apply(p, props)
	return p
end

--------------------------------------------------------------------------------------------------------------------
-- Star row
--------------------------------------------------------------------------------------------------------------------

function Cards.stars(n: number, props: { [string]: any }?): TextLabel
	local p = props or {}
	local max = p.Max or 0
	local s = math.clamp(math.floor(n or 0), 0, 5)
	local color = if s >= 4 then SUN else INK
	local textValue = string.rep("\u{2605}", s)
	if max > s then
		textValue = string.format('%s<font transparency="0.7">%s</font>', textValue, string.rep("\u{2605}", max - s))
	end
	local l = text("Stars", textValue, F.SemiBold, p.TextSize or 15, color)
	l.RichText = true
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, p.TextSize or 15)
	l.TextTruncate = Enum.TextTruncate.None
	apply(l, p)
	return l
end

--------------------------------------------------------------------------------------------------------------------
-- Tiles, slots, cards: one painter for edges and states
--------------------------------------------------------------------------------------------------------------------

local function gradeColor(g: any): Color3?
	local def = Cards.grade(g)
	return def and def.color
end

-- Repaint the edge, bar and states from the attributes (Grade, State_*)
local function paint(root: GuiObject, animate: boolean?)
	local hoverInfo = if animate then QuietUI.Ease.Hover else nil
	local edge = root:FindFirstChild("Edge") :: UIStroke?
	local bar = root:FindFirstChild("GradeBar") :: Frame?
	local well = root:FindFirstChild("Well") :: Frame?
	local def = Cards.grade(root:GetAttribute("Grade"))
	local hover = root:GetAttribute("Hover") == true
	local claim = root:GetAttribute("State_Claimable") == true
	local lockedRule = root:GetAttribute("State_Locked")
	local isLocked = type(lockedRule) == "string" or lockedRule == true
	local disabled = root:GetAttribute("State_Disabled") == true
	if edge then
		if claim then
			ease(edge, "Transparency", 0)
			edge.Color, edge.Thickness = SUN, 2
		elseif def then
			edge.Color = def.color
			ease(edge, "Transparency", math.max(0, def.edge - (if hover then 0.15 else 0)), hoverInfo)
			edge.Thickness = 1.5
		else
			edge.Color = INK
			ease(edge, "Transparency", if hover then 0.62 else Cards.Surface.Edge.transparency, hoverInfo)
			edge.Thickness = 1.5
		end
	end
	if bar then
		bar.Visible = def ~= nil and root:GetAttribute("NoBar") ~= true
		if def then
			bar.BackgroundColor3 = def.color
		end
	end
	local inner = well and well:FindFirstChild("Inner") :: UIStroke?
	if inner then
		inner.Enabled = def ~= nil and def.double == true
		if def then
			inner.Color = def.color
		end
	end
	-- the surface lifts a little on hover (matte: a step in transparency, no glow)
	local base = root:GetAttribute("BaseTransparency")
	if type(base) == "number" then
		ease(root, "BackgroundTransparency", if hover and not disabled then math.max(0, base - 0.08) else base, hoverInfo)
	end
	-- states
	local selected = root:FindFirstChild("Sel") :: Frame?
	if selected then
		selected.Visible = root:GetAttribute("State_Selected") == true
	end
	local tag = root:FindFirstChild("Tag") :: TextLabel?
	local tagWord = root:GetAttribute("State_Equipped") or root:GetAttribute("State_Chosen")
	if tag then
		tag.Visible = type(tagWord) == "string" and tagWord ~= ""
		if tag.Visible then
			tag.Text = tagWord
		end
	end
	local tick = root:FindFirstChild("Tick") :: GuiObject?
	if tick then
		tick.Visible = root:GetAttribute("State_Owned") == true and not (tag and tag.Visible)
	end
	local dot = root:FindFirstChild("NewDot") :: GuiObject?
	if dot then
		dot.Visible = root:GetAttribute("State_New") == true
	end
	local lock = root:FindFirstChild("Lock") :: Frame?
	if lock then
		lock.Visible = isLocked
		local rule = lock:FindFirstChild("Rule") :: TextLabel?
		if rule then
			rule.Text = if type(lockedRule) == "string" then lockedRule else ""
			rule.Visible = rule.Text ~= ""
		end
	end
	local picture = well and well:FindFirstChild("Picture") :: GuiObject?
	if picture then
		local dim = isLocked or disabled
		if picture:IsA("ViewportFrame") then
			picture.ImageTransparency = if dim then 0.68 else 0
		elseif picture:IsA("CanvasGroup") then
			picture.GroupTransparency = if dim then 0.68 else 0
		end
	end
	if root:IsA("GuiButton") then
		root.Active = not disabled
	end
	local fade = if disabled then 0.5 else 0
	for _, name in ipairs({ "Title", "Sub", "Text", "Fact" }) do
		local l = root:FindFirstChild(name, true)
		if l and l:IsA("TextLabel") then
			l.TextTransparency = fade + (l:GetAttribute("Rest") or 0)
		end
	end
end

function Cards.setState(gui: GuiObject, state: string, value: any)
	if state == "Chosen" or state == "Equipped" then
		if value == true then
			value = string.upper(state)
		end
		gui:SetAttribute("State_Equipped", nil)
		gui:SetAttribute("State_Chosen", nil)
		gui:SetAttribute("State_" .. state, if value then value else nil)
	else
		gui:SetAttribute("State_" .. state, if value == false then nil else value)
	end
	paint(gui)
end

function Cards.setGrade(gui: GuiObject, grade: string?)
	gui:SetAttribute("Grade", grade)
	local label = gui:FindFirstChild("GradeLabel", true) :: TextLabel?
	local def = Cards.grade(grade)
	if label and label:GetAttribute("Auto") then
		label.Text = if def then string.upper(def.name) else ""
		label.TextColor3 = if def then (def.label or def.color) else INK2
	end
	paint(gui)
end

-- The state decorations every tile and card carries (hidden until set)
local function decorate(root: GuiObject, small: boolean)
	local sel = frame("Sel", root)
	sel.Position = UDim2.fromOffset(-4, -4)
	sel.Size = UDim2.new(1, 8, 1, 8)
	sel.Visible = false
	sel.ZIndex = 8
	corner(sel, Cards.Corner.Card + 2)
	stroke(sel, INK, 0, 2.5, "Line")

	local tag = text("Tag", "", F.SemiBold, 13, SHADE, root)
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = INK
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.Size = UDim2.fromOffset(0, 18)
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, -6, 0, 6)
	tag.TextXAlignment = Enum.TextXAlignment.Center
	tag.TextTruncate = Enum.TextTruncate.None
	tag.Visible = false
	tag.ZIndex = 7
	corner(tag, 3)
	local tp = Instance.new("UIPadding")
	tp.PaddingLeft, tp.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
	tp.Parent = tag

	local tickPx = if small then 14 else 18
	local tick = Icons.make("tick", { Name = "Tick", Size = UDim2.fromOffset(tickPx, tickPx), AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6), ZIndex = 7 })
	tick.Visible = false
	for _, d in ipairs(tick:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 7
		end
	end
	tick.Parent = root

	local dot = frame("NewDot", root)
	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = SUN
	dot.Size = UDim2.fromOffset(9, 9)
	dot.Position = UDim2.fromOffset(6, 6)
	dot.ZIndex = 7
	dot.Visible = false
	corner(dot, 5)

	local lock = frame("Lock", root)
	lock.Size = UDim2.fromScale(1, 1)
	lock.ZIndex = 6
	lock.Visible = false
	local lockPx = if small then 18 else 24
	local padlock = Icons.make("lock", { Name = "Padlock", Size = UDim2.fromOffset(lockPx, lockPx), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if small then 0.5 else 0.38), Tone = INK2 })
	for _, d in ipairs(padlock:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 6
		end
	end
	padlock.ZIndex = 6
	padlock.Parent = lock
	local rule = text("Rule", "", F.Medium, 13, INK2, lock)
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0.38, lockPx / 2 + 4)
	rule.Size = UDim2.new(1, -12, 0, 32)
	rule.TextXAlignment = Enum.TextXAlignment.Center
	rule.TextYAlignment = Enum.TextYAlignment.Top
	rule.TextWrapped = true
	rule.ZIndex = 6
	rule.Visible = false
end

local function bindHover(root: GuiButton, hoverFn: ((boolean) -> ())?)
	root.MouseEnter:Connect(function()
		root:SetAttribute("Hover", true)
		if root:GetAttribute("State_New") then
			root:SetAttribute("State_New", nil)
		end
		paint(root, true)
		if hoverFn then
			task.spawn(hoverFn, true)
		end
	end)
	root.MouseLeave:Connect(function()
		root:SetAttribute("Hover", false)
		paint(root, true)
		if hoverFn then
			task.spawn(hoverFn, false)
		end
	end)
	root.SelectionGained:Connect(function()
		root:SetAttribute("Hover", true)
		paint(root, true)
		if hoverFn then
			task.spawn(hoverFn, true)
		end
	end)
	root.SelectionLost:Connect(function()
		root:SetAttribute("Hover", false)
		paint(root, true)
		if hoverFn then
			task.spawn(hoverFn, false)
		end
	end)
end

local function makeWell(root: GuiObject, radius: number): Frame
	local well = frame("Well", root)
	well.BackgroundTransparency = Cards.Surface.Well.transparency
	well.BackgroundColor3 = Cards.Surface.Well.color
	well.ClipsDescendants = true
	corner(well, radius)
	-- a soft lighter centre: two stops of the same colour (no gloss)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.45, 0), NumberSequenceKeypoint.new(1, 0.14),
	})
	g.Color = ColorSequence.new(rgb(30, 34, 38), Cards.Surface.Well.color)
	g.Parent = well
	local inner = stroke(well, INK, 0.2, 1, "Inner")
	inner.Enabled = false
	return well
end

local function fillPicture(well: Frame, def: { [string]: any }, scale: number)
	local picture: GuiObject? = nil
	if type(def.Picture) == "function" then
		local holder = Instance.new("CanvasGroup")
		holder.Name = "Picture"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1, 1)
		holder.Parent = well
		def.Picture(holder)
		picture = holder
	elseif type(def.Item) == "string" and RunService:IsClient() then
		local view = Cards.itemView(well, def.Item, { Stars = def.ItemStars or def.Stars, Turn = def.Turn or "hover",
			Zoom = def.Zoom or (if def.Wide then 1.7 else 1.15) })
		if view then
			view.Name = "Picture"
			picture = view
		end
	end
	if not picture then
		local name = def.Icon or (if type(def.Item) == "string" then Icons.forItem(def.Item) else nil)
		if name then
			local holder = Instance.new("CanvasGroup")
			holder.Name = "Picture"
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.fromScale(1, 1)
			holder.Parent = well
			Icons.make(name, { Size = UDim2.fromScale(scale, scale), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Parent = holder })
			picture = holder
		end
	end
	return picture
end

local function baseButton(name: string, def: { [string]: any }): TextButton
	local root = Instance.new("TextButton")
	root.Name = name
	root.Text = ""
	root.AutoButtonColor = false
	root.BorderSizePixel = 0
	root.BackgroundColor3 = Cards.Surface.Card.color
	root.BackgroundTransparency = Cards.Surface.Card.transparency
	root:SetAttribute("BaseTransparency", Cards.Surface.Card.transparency)
	root.Selectable = def.Selectable ~= false
	root.SelectionImageObject = Cards.focusRing()
	return root
end

function Cards.tile(def: { [string]: any }): TextButton
	local m = Cards.metrics()
	local root = baseButton(def.Name or "Tile", def)
	root.Size = def.Size or UDim2.fromOffset(m.tile, m.tile)
	corner(root, Cards.Corner.Tile + 2)
	stroke(root, INK, Cards.Surface.Edge.transparency, 1.5, "Edge")
	local well = makeWell(root, Cards.Corner.Tile)
	well.Position = UDim2.fromOffset(3, 3)
	well.Size = UDim2.new(1, -6, 1, -6)
	local small = (def.Size == nil and false) or (def.Size and def.Size.X.Offset > 0 and def.Size.X.Offset < 70) or def.Small
	fillPicture(well, def, if def.Wide then 0.62 elseif def.NoName then 0.62 else 0.56)

	local bar = frame("GradeBar", root)
	bar.BackgroundTransparency = 0
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -1)
	bar.Size = UDim2.new(1, -6, 0, 3)
	bar.ZIndex = 3
	bar.Visible = false
	corner(bar, 2)

	local gradeDef = Cards.grade(def.Grade)
	local label = text("GradeLabel", def.Label or (if gradeDef then string.upper(gradeDef.name) else ""), F.SemiBold, 12,
		if gradeDef then (gradeDef.label or gradeDef.color) else INK2, root)
	label:SetAttribute("Auto", def.Label == nil)
	label.Position = UDim2.fromOffset(9, 6)
	label.Size = UDim2.new(1, -18, 0, 14)
	label.ZIndex = 3
	label.Visible = not small

	if not def.NoName and (def.Title or def.Stars) then
		local holder = frame("NameRow", root)
		holder.AnchorPoint = Vector2.new(0, 1)
		holder.Position = UDim2.new(0, 9, 1, -8)
		holder.Size = UDim2.new(1, -18, 0, 20)
		holder.ZIndex = 4
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, 6)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = holder
		if def.Title then
			local name = text("Title", def.Title, F.SemiBold, def.NameSize or (if small then 13 else 15), INK, holder)
			name.AutomaticSize = Enum.AutomaticSize.X
			name.Size = UDim2.fromOffset(0, 20)
			name.ZIndex = 4
			local cap = Instance.new("UISizeConstraint")
			cap.MaxSize = Vector2.new(if def.Stars then 150 else 400, 40)
			cap.Parent = name
			onPicture(name)
		end
		if def.Stars then
			local st = Cards.stars(def.Stars, { TextSize = if small then 13 else 14, LayoutOrder = 2, ZIndex = 4 })
			onPicture(st)
			st.Parent = holder
		end
	end
	if def.Count then
		local count = text("Count", tostring(def.Count), F.Mono, 13, INK, root)
		count.AnchorPoint = Vector2.new(1, 1)
		count.Position = UDim2.new(1, -6, 1, -5)
		count.Size = UDim2.fromOffset(40, 16)
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.ZIndex = 4
		onPicture(count)
	end
	if def.Sub then
		local sub = text("Sub", def.Sub, F.Medium, 13, INK2, root)
		sub.AnchorPoint = Vector2.new(0, 1)
		sub.Position = UDim2.new(0, 9, 1, -26)
		sub.Size = UDim2.new(1, -18, 0, 16)
		sub.ZIndex = 4
		onPicture(sub)
	end
	decorate(root, small == true)
	root:SetAttribute("Grade", def.Grade)
	bindHover(root, def.Hover)
	if type(def.OnActivate) == "function" then
		root.Activated:Connect(function()
			if root:GetAttribute("State_Disabled") ~= true then
				def.OnActivate()
			end
		end)
	end
	paint(root)
	apply(root, def)
	return root
end

-- A bare card surface (Card at 86%, corner 10, the edge, the states and the hover), for a caller's own layout inside
-- (a saved loadout card, a slot card, a detail card). def: Name, Size, Grade, Selectable, OnActivate, Hover, props.
function Cards.surface(def: { [string]: any }): TextButton
	local root = baseButton(def.Name or "Surface", def)
	root.Size = def.Size or UDim2.fromOffset(200, 120)
	corner(root, Cards.Corner.Card)
	stroke(root, INK, Cards.Surface.Edge.transparency, 1.5, "Edge")
	local bar = frame("GradeBar", root)
	bar.BackgroundTransparency = 0
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -1)
	bar.Size = UDim2.new(1, -10, 0, 3)
	bar.Visible = false
	corner(bar, 2)
	decorate(root, false)
	root:SetAttribute("Grade", def.Grade)
	bindHover(root, def.Hover)
	if type(def.OnActivate) == "function" then
		root.Activated:Connect(function()
			if root:GetAttribute("State_Disabled") ~= true then
				def.OnActivate()
			end
		end)
	end
	paint(root)
	apply(root, def)
	return root
end

-- A well (the dark picture area) inside any frame, for a caller's own picture
function Cards.well(parent: GuiObject, props: { [string]: any }?): Frame
	local well = makeWell(parent, Cards.Corner.Tile)
	apply(well, props)
	return well
end

function Cards.slot(def: { [string]: any }): TextButton
	local d = table.clone(def)
	if d.Empty then
		d.Icon = d.Icon or "plus"
		d.Grade = nil
	end
	local root = Cards.tile(d)
	root.Name = def.Name or "Slot"
	if d.Empty then
		local edge = root:FindFirstChild("Edge") :: UIStroke
		edge.Transparency = 0.7
		local well = root:FindFirstChild("Well") :: Frame
		well.BackgroundTransparency = 0.7
		local pic = well:FindFirstChild("Picture")
		if pic and pic:IsA("CanvasGroup") then
			pic.GroupTransparency = 0.55
		end
	end
	return root
end

function Cards.card(def: { [string]: any }): TextButton
	local m = Cards.metrics()
	local root = baseButton(def.Name or "Card", def)
	root.Size = def.Size or UDim2.fromOffset(m.card.X, m.card.Y)
	corner(root, Cards.Corner.Card)
	stroke(root, INK, Cards.Surface.Edge.transparency, 1.5, "Edge")
	local pad = 8
	local wellShare = def.WellHeight or 0.42
	local well = makeWell(root, Cards.Corner.Tile)
	well.Position = UDim2.fromOffset(pad, pad)
	well.Size = UDim2.new(1, -pad * 2, wellShare, -pad)
	fillPicture(well, def, if def.Big then 0.62 else 0.42)

	local bar = frame("GradeBar", root)
	bar.BackgroundTransparency = 0
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -1)
	bar.Size = UDim2.new(1, -10, 0, 3)
	bar.ZIndex = 3
	bar.Visible = false
	corner(bar, 2)

	local body = frame("Body", root)
	body.Position = UDim2.new(0, pad + 2, wellShare, 6)
	body.Size = UDim2.new(1, -(pad + 2) * 2, 1 - wellShare, -12)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = body

	local nameSize = def.NameSize or m.name
	local title = text("Title", def.Title or "", F.SemiBold, nameSize, INK, body)
	title.Size = UDim2.new(1, 0, 0, nameSize + 4)
	title.LayoutOrder = 1
	local gradeDef = Cards.grade(def.Grade)
	local subText = def.Sub or (if gradeDef then string.upper(gradeDef.name) else nil)
	if subText then
		local sub = text("Sub", subText, F.SemiBold, 12, if gradeDef and not def.Sub then (gradeDef.label or gradeDef.color) else INK2, body)
		sub.Size = UDim2.new(1, 0, 0, 15)
		sub.LayoutOrder = 2
	end
	-- the grade label in the well's corner too (as on a tile)
	local label = text("GradeLabel", if gradeDef then string.upper(gradeDef.name) else "", F.SemiBold, 12,
		if gradeDef then (gradeDef.label or gradeDef.color) else INK2, well)
	label:SetAttribute("Auto", true)
	label.Position = UDim2.fromOffset(7, 5)
	label.Size = UDim2.new(1, -14, 0, 14)
	label.ZIndex = 3
	label.Visible = false
	if def.Text then
		local lines = def.TextLines or 2
		local t = text("Text", def.Text, F.Medium, m.word - 1, INK2, body)
		t.TextWrapped = true
		t.TextYAlignment = Enum.TextYAlignment.Top
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.Size = UDim2.new(1, 0, 0, (m.word + 3) * lines)
		t.LayoutOrder = 3
	end
	if type(def.Row) == "function" then
		local row = frame("Row", body)
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = 4
		def.Row(row)
	end
	-- the fact line and the button sit at the bottom
	local bottom = frame("Bottom", root)
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.new(0, pad + 2, 1, -9)
	bottom.Size = UDim2.new(1, -(pad + 2) * 2, 0, 20)
	if def.Fact then
		local holder = frame("FactRow", bottom)
		holder.Size = UDim2.fromScale(1, 1)
		local hl = Instance.new("UIListLayout")
		hl.FillDirection = Enum.FillDirection.Horizontal
		hl.VerticalAlignment = Enum.VerticalAlignment.Center
		hl.Padding = UDim.new(0, 6)
		hl.SortOrder = Enum.SortOrder.LayoutOrder
		hl.Parent = holder
		if def.FactIcon then
			Icons.make(def.FactIcon, { Size = UDim2.fromOffset(15, 15), LayoutOrder = 1, Parent = holder,
				Tone = if def.FactIcon == "coin" then nil else INK })
		end
		local fact = text("Fact", def.Fact, F.Mono, 14, INK, holder)
		fact.AutomaticSize = Enum.AutomaticSize.X
		fact.Size = UDim2.fromOffset(0, 18)
		fact.LayoutOrder = 2
		fact.TextTruncate = Enum.TextTruncate.None
	end
	if def.Footer then
		local footer = text("Footer", def.Footer, F.Medium, 13, INK2, bottom)
		footer.Size = UDim2.fromScale(1, 1)
		footer.TextXAlignment = if def.Fact then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
		footer:SetAttribute("Rest", 0.2)
		footer.TextTransparency = 0.2
	end
	if type(def.Button) == "table" then
		local b = Cards.button(def.Button.kind or "Primary", def.Button.text or "", {
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -(pad + 2), 1, -8), Size = UDim2.new(0, 0, 0, 32),
			AutomaticSize = Enum.AutomaticSize.X, Price = def.Button.price, Parent = root,
		})
		if def.Button.onActivate then
			b.Activated:Connect(def.Button.onActivate)
		end
	end
	decorate(root, false)
	root:SetAttribute("Grade", def.Grade)
	bindHover(root, def.Hover)
	if type(def.OnActivate) == "function" then
		root.Activated:Connect(function()
			if root:GetAttribute("State_Disabled") ~= true then
				def.OnActivate()
			end
		end)
	end
	paint(root)
	apply(root, def)
	return root
end

--------------------------------------------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------------------------------------------

local BUTTON_LOOK = {
	Primary = { bg = INK, bgT = 0, fg = SHADE, line = nil },
	Secondary = { bg = INK, bgT = 1, fg = INK, line = INK },
	Sun = { bg = SUN, bgT = 0, fg = SHADE, line = nil },
	Off = { bg = INK, bgT = 0.92, fg = INK2, line = nil, fgT = 0.35 },
	Price = { bg = INK, bgT = 0, fg = SHADE, line = nil },
	Ghost = { bg = INK, bgT = 1, fg = INK, line = nil },
}

function Cards.setButtonKind(b: TextButton, kind: string)
	local look = BUTTON_LOOK[kind] or BUTTON_LOOK.Primary
	b:SetAttribute("Kind", kind)
	b.BackgroundColor3 = look.bg
	ease(b, "BackgroundTransparency", look.bgT)
	b:SetAttribute("BaseTransparency", look.bgT)
	b.TextColor3 = look.fg
	b.TextTransparency = look.fgT or 0
	local line = b:FindFirstChild("Line") :: UIStroke?
	if line then
		line.Enabled = look.line ~= nil
	end
	for _, name in ipairs({ "Price", "Word" }) do
		local l = b:FindFirstChild(name)
		if l and l:IsA("TextLabel") then
			l.TextColor3 = look.fg
			l.TextTransparency = look.fgT or 0
		end
	end
	b.Active = kind ~= "Off"
	b.AutoButtonColor = false
end

function Cards.button(kind: string, value: string, props: { [string]: any }?): TextButton
	local p = props or {}
	local m = Cards.metrics()
	local b = Instance.new("TextButton")
	b.Name = p.Name or (kind .. "Button")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = string.upper(value)
	b.FontFace = F.SemiBold
	b.TextSize = p.TextSize or 15
	b.Size = UDim2.new(0, 0, 0, math.max(40, m.touch))
	b.AutomaticSize = Enum.AutomaticSize.X
	b.SelectionImageObject = Cards.focusRing()
	corner(b, 6)
	local line = stroke(b, INK, 0, 1.5, "Line")
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local pad = Instance.new("UIPadding")
	pad.Name = "Pad"
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
	pad.Parent = b
	if kind == "Price" then
		-- "BUY  (coin) 1,500": the word, the coin and the number in RobotoMono, laid out in a row
		b.Text = ""
		local hl = Instance.new("UIListLayout")
		hl.FillDirection = Enum.FillDirection.Horizontal
		hl.VerticalAlignment = Enum.VerticalAlignment.Center
		hl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		hl.Padding = UDim.new(0, 8)
		hl.SortOrder = Enum.SortOrder.LayoutOrder
		hl.Parent = b
		local word = text("Word", string.upper(value), F.SemiBold, b.TextSize, SHADE, b)
		word.AutomaticSize = Enum.AutomaticSize.X
		word.Size = UDim2.fromOffset(0, 20)
		word.LayoutOrder = 1
		word.TextTruncate = Enum.TextTruncate.None
		local gap = frame("Gap", b)
		gap.Size = UDim2.fromOffset(4, 1)
		gap.LayoutOrder = 2
		Icons.make("coin", { Size = UDim2.fromOffset(15, 15), LayoutOrder = 3, Parent = b })
		local num = text("Price", if type(p.Price) == "number" then comma(p.Price) else tostring(p.Price or ""), F.MonoMedium, b.TextSize + 1, SHADE, b)
		num.AutomaticSize = Enum.AutomaticSize.X
		num.Size = UDim2.fromOffset(0, 20)
		num.LayoutOrder = 4
		num.TextTruncate = Enum.TextTruncate.None
	end
	Cards.setButtonKind(b, kind)
	-- hover / focus: a matte step, never a glow
	local function lit(on: boolean)
		local k = b:GetAttribute("Kind")
		if k == "Off" then
			return
		end
		local base = b:GetAttribute("BaseTransparency") or 0
		if k == "Secondary" or k == "Ghost" then
			ease(b, "BackgroundTransparency", if on then 0.88 else 1, QuietUI.Ease.Hover)
		else
			ease(b, "BackgroundTransparency", if on then math.min(1, base + 0.1) else base, QuietUI.Ease.Hover)
		end
	end
	-- press: a quick matte dip over Motion.Press, back on release (no scale, nothing bounces)
	local over = false
	b.InputBegan:Connect(function(io: InputObject)
		local t = io.UserInputType
		if t == Enum.UserInputType.MouseMovement then
			over = true
		elseif (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or io.KeyCode == Enum.KeyCode.ButtonA)
			and b:GetAttribute("Kind") ~= "Off" then
			local k = b:GetAttribute("Kind")
			local base = b:GetAttribute("BaseTransparency") or 0
			ease(b, "BackgroundTransparency", if k == "Secondary" or k == "Ghost" then 0.8 else math.min(1, base + 0.22),
				QuietUI.Ease.Press)
		end
	end)
	b.InputEnded:Connect(function(io: InputObject)
		local t = io.UserInputType
		if t == Enum.UserInputType.MouseMovement then
			over = false
		elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or io.KeyCode == Enum.KeyCode.ButtonA then
			lit((over and t ~= Enum.UserInputType.Touch) or GuiService.SelectedObject == b)
		end
	end)
	b.MouseEnter:Connect(function()
		lit(true)
	end)
	b.MouseLeave:Connect(function()
		lit(false)
	end)
	b.SelectionGained:Connect(function()
		lit(true)
	end)
	b.SelectionLost:Connect(function()
		lit(false)
	end)
	apply(b, p)
	return b
end

-- Hold to confirm: a fill (Ink2 over the button) grows over `seconds`; onDone once full. Mouse, touch and gamepad A.
function Cards.hold(button: GuiButton, seconds: number, onDone: () -> ()): () -> ()
	local fill = button:FindFirstChild("HoldFill") :: Frame?
	if not fill then
		local f = frame("HoldFill", button)
		f.BackgroundTransparency = 0.55
		f.BackgroundColor3 = if button:GetAttribute("Kind") == "Secondary" then INK else SHADE
		f.Size = UDim2.fromScale(0, 1)
		f.ZIndex = button.ZIndex + 1
		f.ClipsDescendants = true
		corner(f, 6)
		fill = f
	end
	local token = 0
	local holding = false
	local connections = {}
	local function stop()
		holding = false
		token += 1
		if fill then
			fill.Size = UDim2.fromScale(0, 1)
		end
	end
	local function start()
		if button.Active == false then
			return
		end
		token += 1
		local mine = token
		holding = true
		local t0 = os.clock()
		task.spawn(function()
			while holding and mine == token and button.Parent do
				local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
				if fill then
					fill.Size = UDim2.fromScale(a, 1)
				end
				if a >= 1 then
					stop()
					onDone()
					return
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end
	local function isPress(io: InputObject): boolean
		return io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
			or io.KeyCode == Enum.KeyCode.ButtonA or io.KeyCode == Enum.KeyCode.Return
	end
	table.insert(connections, button.InputBegan:Connect(function(io)
		if isPress(io) then
			start()
		end
	end))
	table.insert(connections, button.InputEnded:Connect(function(io)
		if isPress(io) then
			stop()
		end
	end))
	table.insert(connections, button.MouseLeave:Connect(stop))
	table.insert(connections, button.SelectionLost:Connect(stop))
	return function()
		stop()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Tabs, side list, stepper
--------------------------------------------------------------------------------------------------------------------

function Cards.tabs(list: { { [string]: any } }, props: { [string]: any }?)
	local p = props or {}
	local m = Cards.metrics()
	local holder = frame("Tabs")
	holder.Size = UDim2.new(0, 0, 0, math.max(40, m.touch))
	holder.AutomaticSize = Enum.AutomaticSize.X
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, if m.phone then 2 else 8)
	layout.Parent = holder
	local api = { buttons = {}, keys = {} }
	local current: string? = nil
	local listeners = {}
	local function paintTabs()
		for key, b in pairs(api.buttons) do
			local on = key == current
			local line = b:FindFirstChild("Line") :: UIStroke
			ease(line, "Transparency", if on then 0.1 else 1, QuietUI.Ease.Tab)
			ease(b, "TextTransparency", if on then 0 else 0.3, QuietUI.Ease.Hover)
		end
	end
	for i, item in ipairs(list) do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. item.key
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.Text = item.text
		b.FontFace = F.SemiBold
		b.TextSize = p.TextSize or (if m.phone then 15 else 17)
		b.TextColor3 = INK
		b.Size = UDim2.new(0, 0, 1, 0)
		b.AutomaticSize = Enum.AutomaticSize.X
		b.LayoutOrder = i
		b.SelectionImageObject = Cards.focusRing()
		corner(b, 6)
		stroke(b, INK, 1, 1.5, "Line")
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, if m.phone then 10 else 18), UDim.new(0, if m.phone then 10 else 18)
		pad.Parent = b
		local badge = text("Badge", "", F.MonoMedium, 12, SHADE, b)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = SUN
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(1, 14, 0, 6)
		badge.Size = UDim2.fromOffset(18, 18)
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.Visible = false
		corner(badge, 9)
		b.MouseEnter:Connect(function()
			if b.Name ~= "Tab_" .. tostring(current) then
				ease(b, "TextTransparency", 0.1, QuietUI.Ease.Hover)
			end
		end)
		b.MouseLeave:Connect(paintTabs)
		b.Activated:Connect(function()
			api.select(item.key)
		end)
		b.Parent = holder
		api.buttons[item.key] = b
		table.insert(api.keys, item.key)
		if item.badge then
			badge.Text = tostring(item.badge)
			badge.Visible = true
		end
	end
	function api.select(key: string, quiet: boolean?)
		if not api.buttons[key] then
			return
		end
		local changed = key ~= current
		current = key
		paintTabs()
		if changed and not quiet then
			for _, fn in ipairs(listeners) do
				task.spawn(fn, key)
			end
		end
	end
	function api.current(): string?
		return current
	end
	function api.onChanged(fn: (string) -> ())
		table.insert(listeners, fn)
	end
	function api.setBadge(key: string, n: number?)
		local b = api.buttons[key]
		local badge = b and b:FindFirstChild("Badge") :: TextLabel?
		if badge then
			badge.Visible = n ~= nil and n > 0
			badge.Text = tostring(n or "")
		end
	end
	function api.step(dir: number)
		local i = table.find(api.keys, current or "") or 1
		local n = #api.keys
		api.select(api.keys[((i - 1 + dir) % n) + 1])
	end
	if list[1] then
		api.select(p.Start or list[1].key, true)
	end
	apply(holder, p)
	return holder, api
end

function Cards.sideList(items: { { [string]: any } }, props: { [string]: any }?)
	local p = props or {}
	local m = Cards.metrics()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "SideList"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = INK
	scroll.ScrollBarImageTransparency = 0.7
	scroll.CanvasSize = UDim2.new()
	scroll.Selectable = false
	local horizontal = m.phone or p.Horizontal == true
	scroll.ScrollingDirection = if horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = scroll
	local api = { rows = {} }
	local listeners = {}
	local current: string? = nil
	for i, item in ipairs(items) do
		local row: TextButton
		if horizontal then
			row = Cards.tile({ Name = "Item_" .. item.key, Size = UDim2.fromOffset(72, 72), Icon = item.icon, Item = item.item,
				NoName = true, Grade = item.grade, LayoutOrder = i })
		else
			row = baseButton("Item_" .. item.key, {})
			row.Size = UDim2.new(1, -8, 0, 76)
			row.LayoutOrder = i
			corner(row, Cards.Corner.Card)
			stroke(row, INK, Cards.Surface.Edge.transparency, 1.5, "Edge")
			local well = makeWell(row, Cards.Corner.Tile)
			well.Position = UDim2.fromOffset(8, 8)
			well.Size = UDim2.fromOffset(60, 60)
			fillPicture(well, { Icon = item.icon, Item = item.item }, 0.7)
			local name = text("Title", item.title, F.SemiBold, 16, INK, row)
			name.Position = UDim2.fromOffset(80, 14)
			name.Size = UDim2.new(1, -90, 0, 22)
			local sub = text("Sub", item.sub or (if item.price then comma(item.price) else ""), F.Mono, 14, INK2, row)
			sub.Position = UDim2.fromOffset(80, 40)
			sub.Size = UDim2.new(1, -90, 0, 18)
			decorate(row, false)
			bindHover(row, nil)
			paint(row)
		end
		row.Activated:Connect(function()
			api.select(item.key)
		end)
		row.Parent = scroll
		api.rows[item.key] = row
	end
	function api.select(key: string, quiet: boolean?)
		if not api.rows[key] then
			return
		end
		local changed = current ~= key
		current = key
		for k, r in pairs(api.rows) do
			Cards.setState(r, "Selected", k == key)
		end
		if changed and not quiet then
			for _, fn in ipairs(listeners) do
				task.spawn(fn, key)
			end
		end
	end
	function api.onChanged(fn)
		table.insert(listeners, fn)
	end
	function api.current()
		return current
	end
	apply(scroll, p)
	return scroll, api
end

function Cards.stepper(min: number, max: number, value: number, props: { [string]: any }?)
	local holder = frame("Stepper")
	holder.Size = UDim2.fromOffset(40 * 3 + 16, 40)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = holder
	local v = math.clamp(value, min, max)
	local listeners = {}
	local minus = Cards.button("Secondary", "-", { Name = "Minus", Size = UDim2.fromOffset(40, 40), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 1 })
	minus.Parent = holder
	local num = text("Value", tostring(v), F.MonoMedium, 17, INK, holder)
	num.Size = UDim2.fromOffset(40, 40)
	num.TextXAlignment = Enum.TextXAlignment.Center
	num.LayoutOrder = 2
	local plus = Cards.button("Secondary", "+", { Name = "Plus", Size = UDim2.fromOffset(40, 40), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 3 })
	plus.Parent = holder
	for _, b in ipairs({ minus, plus }) do
		local pad = b:FindFirstChild("Pad") :: UIPadding
		pad.PaddingLeft, pad.PaddingRight = UDim.new(), UDim.new()
	end
	local api = {}
	function api.get(): number
		return v
	end
	function api.set(n: number)
		local nv = math.clamp(math.floor(n), min, max)
		if nv == v then
			return
		end
		v = nv
		num.Text = tostring(v)
		Cards.setButtonKind(minus, if v <= min then "Off" else "Secondary")
		Cards.setButtonKind(plus, if v >= max then "Off" else "Secondary")
		for _, fn in ipairs(listeners) do
			task.spawn(fn, v)
		end
	end
	function api.onChanged(fn)
		table.insert(listeners, fn)
	end
	minus.Activated:Connect(function()
		api.set(v - 1)
	end)
	plus.Activated:Connect(function()
		api.set(v + 1)
	end)
	Cards.setButtonKind(minus, if v <= min then "Off" else "Secondary")
	Cards.setButtonKind(plus, if v >= max then "Off" else "Secondary")
	apply(holder, props)
	return holder, api
end

--------------------------------------------------------------------------------------------------------------------
-- Bars, countdown, odds
--------------------------------------------------------------------------------------------------------------------

function Cards.bar(props: { [string]: any }?): Frame
	local p = props or {}
	local track = frame("Bar")
	track.BackgroundTransparency = 0.84
	track.BackgroundColor3 = INK
	track.Size = UDim2.new(1, 0, 0, p.Height or 6)
	corner(track, 3)
	local fill = frame("Fill", track)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = INK
	fill.Size = UDim2.fromScale(0, 1)
	corner(fill, 3)
	apply(track, p)
	return track
end

function Cards.setBar(bar: Frame, alpha: number, sun: boolean?)
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
		fill.BackgroundColor3 = if sun then SUN else INK
	end
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 86400 then
		return string.format("%dd %02dh", s // 86400, (s % 86400) // 3600)
	end
	return string.format("%02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
end
Cards.clock = clock

function Cards.countdown(endUnix: number, props: { [string]: any }?): TextLabel
	local l = text("Countdown", clock(endUnix - os.time()), F.Mono, (props and props.TextSize) or 18, INK)
	l.Size = UDim2.fromOffset(120, 24)
	l:SetAttribute("EndUnix", endUnix)
	apply(l, props)
	if RunService:IsClient() then
		local gone = false
		l.Destroying:Connect(function()
			gone = true
		end)
		task.spawn(function()
			while not gone do
				local e = l:GetAttribute("EndUnix")
				if type(e) == "number" then
					l.Text = clock(e - os.time())
				end
				task.wait(1)
			end
		end)
	end
	return l
end

function Cards.setOdds(holder: Frame, rows: { { [string]: any } })
	local list = holder:FindFirstChild("Rows") :: Frame
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local total = 0
	local two = false
	for _, r in ipairs(rows) do
		total += r.pct or 0
		two = two or r.pct2 ~= nil
	end
	for i, r in ipairs(rows) do
		local row = frame("Row" .. i, list)
		row.Size = UDim2.new(1, 0, 0, 24)
		row.LayoutOrder = i
		local color = r.color or gradeColor(r.name) or INK
		local gdef = Cards.grade(r.name)
		local name = text("Name", r.label or r.name, F.SemiBold, 14, if gdef then (gdef.label or gdef.color) else color, row)
		name.Size = UDim2.new(0.28, 0, 1, 0)
		local track = frame("Track", row)
		track.BackgroundTransparency = 0.86
		track.BackgroundColor3 = INK
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.Position = UDim2.new(0.3, 0, 0.5, 0)
		track.Size = UDim2.new(if two then 0.36 else 0.5, 0, 0, 5)
		corner(track, 3)
		local fill = frame("Fill", track)
		fill.BackgroundTransparency = 0
		fill.BackgroundColor3 = color
		fill.Size = UDim2.fromScale(math.clamp((r.pct or 0) / 100, 0, 1), 1)
		corner(fill, 3)
		local pct = text("Pct", string.format("%g%%", r.pct or 0), F.Mono, 14, INK, row)
		pct.AnchorPoint = Vector2.new(1, 0)
		pct.Position = UDim2.new(if two then 0.84 else 1, 0, 0, 0)
		pct.Size = UDim2.new(0.16, 0, 1, 0)
		pct.TextXAlignment = Enum.TextXAlignment.Right
		if two then
			local p2 = text("Pct2", if r.pct2 then string.format("%g%%", r.pct2) else "", F.Mono, 14, SUN, row)
			p2.AnchorPoint = Vector2.new(1, 0)
			p2.Position = UDim2.fromScale(1, 0)
			p2.Size = UDim2.new(0.16, 0, 1, 0)
			p2.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
	local foot = holder:FindFirstChild("Total") :: TextLabel?
	if foot then
		foot.Text = string.format("Total %g%%", math.floor(total * 100 + 0.5) / 100)
	end
end

function Cards.oddsList(rows: { { [string]: any } }, props: { [string]: any }?): Frame
	local p = props or {}
	local holder = frame("Odds")
	holder.Size = UDim2.new(1, 0, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = holder
	local list = frame("Rows", holder)
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = 1
	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 2)
	ll.Parent = list
	local total = text("Total", "", F.Mono, 13, INK2, holder)
	total.Size = UDim2.new(1, 0, 0, 18)
	total.TextXAlignment = Enum.TextXAlignment.Right
	total.LayoutOrder = 2
	if type(p.Details) == "function" then
		local b = Cards.button("Secondary", "Odds details", { LayoutOrder = 3, Size = UDim2.new(0, 0, 0, 34), TextSize = 13 })
		b.Activated:Connect(p.Details)
		b.Parent = holder
	end
	Cards.setOdds(holder, rows)
	apply(holder, p)
	return holder
end

--------------------------------------------------------------------------------------------------------------------
-- Layout helpers: grid, section, hints
--------------------------------------------------------------------------------------------------------------------

function Cards.grid(props: { [string]: any }?): ScrollingFrame
	local p = props or {}
	local m = Cards.metrics()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = INK
	scroll.ScrollBarImageTransparency = 0.7
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Selectable = false
	scroll.Size = UDim2.fromScale(1, 1)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset((p.Cell or m.card).X, (p.Cell or m.card).Y)
	local gap = p.Gap or m.gap
	grid.CellPadding = UDim2.fromOffset(gap, gap)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingTop, pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 10)
	pad.Parent = scroll
	apply(scroll, p)
	return scroll
end

function Cards.section(value: string, props: { [string]: any }?): TextLabel
	local p = props or {}
	local l = text("Section", string.upper(value), F.SemiBold, p.TextSize or 15, INK)
	l.RichText = true
	if p.Tail then
		l.Text = string.format('%s  <font family="rbxasset://fonts/families/Montserrat.json" weight="500" color="%s">%s</font>',
			Theme.escape(string.upper(value)), Theme.hex(INK2), Theme.escape(p.Tail))
	end
	l.Size = UDim2.new(1, 0, 0, 24)
	apply(l, p)
	return l
end

function Cards.hints(list: { { [string]: any } }, props: { [string]: any }?): Frame
	local holder = frame("Hints")
	holder.Size = UDim2.new(0, 0, 0, 26)
	holder.AutomaticSize = Enum.AutomaticSize.X
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = holder
	for i, h in ipairs(list) do
		local key = text("Key", h.key, F.MonoMedium, 13, INK, holder)
		key.AutomaticSize = Enum.AutomaticSize.X
		key.Size = UDim2.fromOffset(22, 22)
		key.TextXAlignment = Enum.TextXAlignment.Center
		key.TextTruncate = Enum.TextTruncate.None
		key.LayoutOrder = i * 2
		corner(key, 4)
		stroke(key, INK, 0.35, 1, "Line")
		local kp = Instance.new("UIPadding")
		kp.PaddingLeft, kp.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
		kp.Parent = key
		local word = text("Word", h.text, F.Medium, 13, INK2, holder)
		word.AutomaticSize = Enum.AutomaticSize.X
		word.Size = UDim2.fromOffset(0, 22)
		word.TextTruncate = Enum.TextTruncate.None
		word.LayoutOrder = i * 2 + 1
		local gapAfter = frame("Gap", holder)
		gapAfter.Size = UDim2.fromOffset(6, 1)
		gapAfter.LayoutOrder = i * 2 + 1
	end
	apply(holder, props)
	return holder
end

--------------------------------------------------------------------------------------------------------------------
-- Gamepad shoulders for tabs
--------------------------------------------------------------------------------------------------------------------

function Cards.bindShoulders(name: string, onPrev: () -> (), onNext: () -> ()): () -> ()
	ContextActionService:BindActionAtPriority(name, function(_, state, io)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if io.KeyCode == Enum.KeyCode.ButtonL1 or io.KeyCode == Enum.KeyCode.Q then
			onPrev()
		else
			onNext()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 20, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	return function()
		ContextActionService:UnbindAction(name)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Live 3D item views
--------------------------------------------------------------------------------------------------------------------

local liveViews = 0
local ItemModelsMod: any = nil
local StarsMod: any = nil
local function itemModels()
	if ItemModelsMod == nil then
		local ok, mod = pcall(require, Shared:WaitForChild("ItemModels") :: ModuleScript)
		ItemModelsMod = if ok then mod else false
	end
	return ItemModelsMod or nil
end
local function starsModule()
	if StarsMod == nil then
		local ok, mod = pcall(require, Shared:WaitForChild("Stars") :: ModuleScript)
		StarsMod = if ok then mod else false
	end
	return StarsMod or nil
end

function Cards.liveViewCount(): number
	return liveViews
end

function Cards.itemView(parent: GuiObject, itemId: string, opts: { [string]: any }?)
	local o = opts or {}
	local models = itemModels()
	if not models or (liveViews >= Cards.MAX_VIEWS and not o.Force) then
		return nil, nil
	end
	local view = Instance.new("ViewportFrame")
	view.Name = "View"
	view.BackgroundTransparency = 1
	view.Size = UDim2.fromScale(1, 1)
	view.Ambient = rgb(128, 126, 122)
	view.LightColor = rgb(255, 246, 232)
	view.LightDirection = Vector3.new(-0.5, -0.8, -0.45)
	view.Parent = parent
	liveViews += 1
	local counted = true
	local function uncount()
		if counted then
			counted = false
			liveViews -= 1
		end
	end
	view.Destroying:Connect(uncount)
	view.AncestryChanged:Connect(function()
		if not view:IsDescendantOf(game) then
			uncount()
		end
	end)

	local model: Model? = nil
	local camera: Camera? = nil
	local baseCF = CFrame.identity
	local radius = 1
	local yaw = 0
	local pitch = 0
	local api = {}

	local function frameIt()
		if not (model and camera) then
			return
		end
		local zoom = o.Zoom or 1
		local fov = camera.FieldOfView
		local size = view.AbsoluteSize
		local aspect = if size.X > 0 and size.Y > 0 then size.X / size.Y else 1
		local tanHalf = math.tan(math.rad(fov / 2))
		local dist = radius / math.min(tanHalf, tanHalf * aspect) * 1.08 / zoom
		local rot = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
		model:PivotTo(rot * baseCF)
		camera.CFrame = CFrame.new(0, 0, dist)
	end

	function api.setItem(id: string?, stars: number?)
		if model then
			model:Destroy()
			model = nil
		end
		if not id then
			return
		end
		local built = models.renderIcon(view, id)
		if not built then
			return
		end
		model = built
		camera = view.CurrentCamera
		if camera then
			camera.FieldOfView = 26
		end
		local st = starsModule()
		if st and stars then
			pcall(st.applyFinish, built, stars)
		end
		for _, d in ipairs(built:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Reflectance = 0
			end
		end
		-- the item centred at the origin as renderIcon left it; turning keeps it centred
		local pivot = built:GetPivot()
		baseCF = (o.Rotation or CFrame.identity) * pivot
		local okX, x0, x1 = pcall(models.getExtent, built, Vector3.xAxis)
		local okY, y0, y1 = pcall(models.getExtent, built, Vector3.yAxis)
		local okZ, z0, z1 = pcall(models.getExtent, built, Vector3.zAxis)
		if okX and okY and okZ then
			local dx, dy, dz = (x1 - x0), (y1 - y0), (z1 - z0)
			radius = math.max(0.3, math.sqrt(dx * dx + dy * dy + dz * dz) / 2)
		end
		frameIt()
	end

	function api.turn(dYaw: number, dPitch: number?)
		yaw = (yaw + dYaw) % 360
		pitch = math.clamp(pitch + (dPitch or 0), -60, 60)
		frameIt()
	end

	function api.destroy()
		view:Destroy()
	end

	function api.model(): Model?
		return model
	end

	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(frameIt)
	api.setItem(itemId, o.Stars)

	local turnMode = o.Turn or "hover"
	if turnMode == "hover" or turnMode == "slow" then
		local hovering = turnMode == "slow"
		local host = parent
		while host and not host:IsA("GuiButton") and host.Parent and host.Parent:IsA("GuiObject") do
			host = host.Parent :: GuiObject
		end
		if host and host:IsA("GuiButton") and turnMode == "hover" then
			host.MouseEnter:Connect(function()
				hovering = true
			end)
			host.MouseLeave:Connect(function()
				hovering = false
			end)
			host.SelectionGained:Connect(function()
				hovering = true
			end)
			host.SelectionLost:Connect(function()
				hovering = false
			end)
		end
		task.spawn(function()
			while view.Parent do
				local dt = RunService.RenderStepped:Wait()
				if hovering and view.Visible then
					api.turn(dt * 12 * (if turnMode == "slow" then 1 else 2))
				end
			end
		end)
	elseif turnMode == "drag" then
		local dragging = false
		local last: Vector3? = nil
		view.Active = true
		view.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				last = io.Position
			end
		end)
		local c1 = UserInputService.InputChanged:Connect(function(io)
			if dragging and last and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
				local d = io.Position - last
				last = io.Position
				api.turn(d.X * 0.5, d.Y * 0.3)
			end
		end)
		local c2 = UserInputService.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		view.Destroying:Connect(function()
			c1:Disconnect()
			c2:Disconnect()
		end)
	end
	return view, api
end

--------------------------------------------------------------------------------------------------------------------
-- A 2D trail preview (cards): a ribbon sweeping along an arc, head to tail colours
--------------------------------------------------------------------------------------------------------------------

local SEGMENTS = 22

function Cards.trailPreview(parent: GuiObject, colors: { Color3 }, opts: { [string]: any }?)
	local o = opts or {}
	local holder = frame("TrailPreview", parent)
	holder.Size = UDim2.fromScale(1, 1)
	local segs: { Frame } = {}
	local head, tail = colors[1] or INK, colors[2] or colors[1] or INK
	local width = o.Width or 3
	local function place()
		local size = holder.AbsoluteSize
		if size.X < 2 then
			return
		end
		-- an arc from lower left to upper right (a swing seen from the side)
		local cx, cy = size.X * 0.62, size.Y * 1.25
		local r = math.min(size.X * 0.62, size.Y * 1.05)
		for i, seg in ipairs(segs) do
			local a0 = math.rad(200 + (i - 1) / SEGMENTS * 80)
			local a1 = math.rad(200 + i / SEGMENTS * 80)
			local x0, y0 = cx + math.cos(a0) * r, cy + math.sin(a0) * r
			local x1, y1 = cx + math.cos(a1) * r, cy + math.sin(a1) * r
			local dx, dy = x1 - x0, y1 - y0
			-- in shares of the holder (AbsoluteSize includes any UIScale above; shares do not care)
			seg.Position = UDim2.fromScale((x0 + x1) / 2 / size.X, (y0 + y1) / 2 / size.Y)
			seg.Size = UDim2.new((math.sqrt(dx * dx + dy * dy) + 1.5) / size.X, 0, 0, width * (0.55 + 0.45 * i / SEGMENTS))
			seg.Rotation = math.deg(math.atan2(dy, dx))
		end
	end
	for i = 1, SEGMENTS do
		local seg = frame("S" .. i, holder)
		seg.BackgroundTransparency = 0
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.BackgroundColor3 = tail:Lerp(head, i / SEGMENTS)
		corner(seg, 2)
		table.insert(segs, seg)
	end
	local headDot = frame("Head", holder)
	headDot.BackgroundTransparency = if o.Glow then 0 else 1
	headDot.AnchorPoint = Vector2.new(0.5, 0.5)
	headDot.Size = UDim2.fromOffset(width * 2.4, width * 2.4)
	headDot.BackgroundColor3 = head
	corner(headDot, 99)
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	task.defer(place)
	local api = {}
	local running = true
	local function show(t: number)
		-- t in 0..1: the head travels along; the tail fades behind it
		for i, seg in ipairs(segs) do
			local p = i / SEGMENTS
			local behind = t - p
			local alpha = if behind < 0 then 1 else math.clamp(behind / 1.1, 0, 1) ^ 1.5
			seg.BackgroundTransparency = 0.05 + alpha * 0.95
		end
		local last = segs[math.clamp(math.ceil(t * SEGMENTS), 1, SEGMENTS)]
		headDot.Position = last.Position
		headDot.Visible = o.Glow == true and t <= 1
	end
	function api.setColors(c: { Color3 }, glow: boolean?)
		head, tail = c[1] or INK, c[2] or c[1] or INK
		for i, seg in ipairs(segs) do
			seg.BackgroundColor3 = tail:Lerp(head, i / SEGMENTS)
		end
		headDot.BackgroundColor3 = head
		o.Glow = glow
	end
	function api.stop()
		running = false
	end
	if o.Still or not RunService:IsClient() then
		show(1)
		headDot.Visible = false
		for i, seg in ipairs(segs) do
			seg.BackgroundTransparency = 0.05 + (1 - i / SEGMENTS) * 0.6
		end
	else
		task.spawn(function()
			local period = o.Period or 1.2
			local t0 = os.clock()
			while running and holder.Parent do
				local t = ((os.clock() - t0) % (period + 0.35)) / period
				if holder.Visible and holder.AbsoluteSize.X > 1 then
					show(math.min(t, 1.6))
				end
				task.wait(1 / 30)
			end
		end)
	end
	return holder, api
end

return Cards
