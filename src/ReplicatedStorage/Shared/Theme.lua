--[[
	Theme - UI design tokens and small UI helpers, in the "Quiet" style (docs/design/ui/StyleA_Quiet/README.md).
	The UI system owns this file (refine values freely, keep the keys). Everything that draws UI uses these tokens;
	Shared.QuietUI builds the parts (labels, line bars, key squares, text buttons, the strip) from them.

	The style in one paragraph: no panels or boxes. Thin light text and small matte icons sit straight on the 3D
	picture and stay readable through a soft dark stroke. One ink colour; Sun (amber) only for "look at this"; Red only
	for a danger state (low health, the border), never as a hit effect. Bars are slim lines. Numbers are RobotoMono,
	words are Montserrat. Things fade out when they are not needed.

	Sizes are design pixels: 1280 x 720 at scale 1 (Theme.scaleFor). A 1080p screen runs at scale 1.25, so the style
	guide's 1080p sizes are these times 1.25 (13 -> 16, 16 -> 20, 24 -> 30, 37 -> 46, 54 -> 68). Nothing is under 13.

	Colours (Theme.Colors)
	  Quiet palette:  Ink, Ink2 (dim tone), Shade (strokes and shadows only), Sun, Red,
	                  Paper, PaperInk, PaperBar, PaperTag (the physical board), Wood, WoodLit, WoodShade (its frame)
	  Older names, kept so every reader still works, now pointing at the palette:
	                  Text, TextDim, TextFaint, TextDark, Panel, PanelLight, Stroke, Shadow, Accent, AccentSoft, Danger,
	                  Warning, Success, Gold, Health, HealthLow, Hunger, Thirst, Stamina, Armor, Track
	  World colours (not UI; unchanged): Border (the border wall, ArenaController), Theme.Rarity (item tints),
	                  Theme.World.Ember (the old ember accent, for a world light that should stay ember)
	Fonts (Theme.Fonts)
	  Quiet:  Light, Regular, Medium, SemiBold (Montserrat 300 / 400 / 500 / 600), Mono, MonoMedium (RobotoMono 400 / 500)
	  Older:  Display (= Light), Heading (= SemiBold), Body (= Medium), BodyBold (= SemiBold)
	  Light is for 24 design px and up only (30 px at 1080p); words 13 to 16 are Medium; capital labels are SemiBold.
	Other tables
	  Theme.TextSize      Small / Caption / Label / Body / Heading / Title / Display / Huge, and Number, Status, Count, Hero
	  Theme.Transparency  Panel, PanelStrong, PanelSoft, Stroke, StrokeStrong, BarTrack, TextShadow, Dim, and the Quiet
	                      states TextRest, TextDim, TextFaint, Hairline, BarGhost, KeyStroke
	  Theme.Stroke        the dark stroke behind text and lines: Thickness, Transparency, BigThickness, LineTransparency
	  Theme.Bar           the line bar: Height, HealthHeight, Icon, Gap, ValueWidth, RowHeight, RowGap, TickOverhang
	  Theme.Key           the key square: Size, Corner, Thickness, PadX, Shade
	  Theme.Strip         the slim bottom strip: Height, Line
	  Theme.Time          fade times in seconds: In, Out, Idle (how long a quiet thing stays before it fades to rest)
	  Theme.Tween         TweenInfos: Fast, Normal, Slow, Pop, Fade, FadeOut, Bar, Ghost, In, Out
	  Theme.Layout        HUD placement per device (HUDController applies it): Desktop, Touch, Phone, SlotGap,
	                      HotbarButtonMargin, IconSize, IconSelected
	  Theme.TouchLayout   the mobile action buttons (Shared.Input)

	Helpers (client)
	  Theme.panel(gui, transparency?)          a flat shade backing, no corner and no outline (Quiet has no boxes: the
	                                           default is fully clear; pass a number only for a modal sheet)
	  Theme.text(label, fontKey?, size?)       text defaults, with the Quiet stroke
	  Theme.shadow(gui, big?)                  adds or refreshes the dark stroke (a UIStroke named "Shadow")
	  Theme.scaleFor(viewport, tenFoot?)       UI scale for a viewport (never below 1 so 13 px text stays >= 13 px)
	  Theme.edgePadding(viewport, tenFoot?)    screen-edge padding in design pixels (larger on TVs for overscan)
	  Theme.bindRoot(screenGui)                keeps ScreenGui.Root sized/scaled for the viewport; returns getScale()
	  Theme.tween(instance, info, props)       create + play a tween, returns it
	  Theme.escape(text)                       escape text for RichText
	  Theme.hex(color)                         "#RRGGBB" for RichText <font color>
	  Theme.isSmallScreen(viewport?)           phone-sized viewport
]]
local TweenService = game:GetService("TweenService")

local Theme = {}

-- Roblox's own font families (nothing is uploaded). Checked in Studio on 18 Nov 2026 with
-- TextService:GetFamilyInfoAsync: Montserrat ships Light, Regular, Medium and SemiBold; RobotoMono ships Regular
-- and Medium. Font.new takes the nearest weight a family has, so a missing one would still draw.
local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local ROBOTO_MONO = "rbxasset://fonts/families/RobotoMono.json"

local function font(family: string, weight: Enum.FontWeight): Font
	return Font.new(family, weight, Enum.FontStyle.Normal)
end

Theme.Fonts = {
	-- Quiet
	Light = font(MONTSERRAT, Enum.FontWeight.Light), -- 24 design px and up only: the title, the count, the status line
	Regular = font(MONTSERRAT, Enum.FontWeight.Regular), -- a quieter word beside a Medium one
	Medium = font(MONTSERRAT, Enum.FontWeight.Medium), -- words, 13 to 16
	SemiBold = font(MONTSERRAT, Enum.FontWeight.SemiBold), -- capital labels and names that matter
	Mono = font(ROBOTO_MONO, Enum.FontWeight.Regular), -- numbers that change: vitals, distances, the clock
	MonoMedium = font(ROBOTO_MONO, Enum.FontWeight.Medium), -- the letter in a key square
	-- older names
	Display = font(MONTSERRAT, Enum.FontWeight.Light), -- big titles, countdown numbers
	Heading = font(MONTSERRAT, Enum.FontWeight.SemiBold), -- capital labels and headers
	Body = font(MONTSERRAT, Enum.FontWeight.Medium),
	BodyBold = font(MONTSERRAT, Enum.FontWeight.SemiBold),
}

local INK = Color3.fromRGB(244, 241, 234) -- #F4F1EA
local INK2 = Color3.fromRGB(189, 184, 172) -- #BDB8AC
local SHADE = Color3.fromRGB(13, 16, 18) -- #0D1012
local SUN = Color3.fromRGB(232, 182, 90) -- #E8B65A
local RED = Color3.fromRGB(222, 91, 75) -- #DE5B4B
local PAPER_INK = Color3.fromRGB(35, 39, 43) -- #23272B

Theme.Colors = {
	-- Quiet palette
	Ink = INK, -- all text, lines and icons
	Ink2 = INK2, -- the dim tone: a value at rest, a second word
	Shade = SHADE, -- strokes and shadows only, never a box
	Sun = SUN, -- "look at this": low hunger or thirst, the water marker, YOU and PLUS tags
	Red = RED, -- a danger state: low health, the border. Never a hit effect.
	Paper = Color3.fromRGB(234, 229, 217), -- the physical board's face (#EAE5D9)
	PaperInk = PAPER_INK, -- text on the board
	PaperBar = Color3.fromRGB(201, 138, 34), -- the board's "your row" bar (#C98A22)
	PaperTag = Color3.fromRGB(138, 92, 16), -- the YOU tag on paper (#8A5C10)
	Wood = Color3.fromRGB(90, 69, 53), -- the board's frame and posts: front (#5A4535)
	WoodLit = Color3.fromRGB(107, 83, 64), -- lit edge (#6B5340)
	WoodShade = Color3.fromRGB(67, 51, 42), -- shaded edge (#43332A)
	-- older names
	Text = INK,
	TextDim = INK2,
	TextFaint = Color3.fromRGB(150, 146, 137),
	TextDark = PAPER_INK,
	Panel = SHADE,
	PanelLight = Color3.fromRGB(40, 44, 48),
	Stroke = INK,
	Shadow = SHADE,
	Accent = SUN,
	AccentSoft = SUN,
	Danger = RED,
	Warning = SUN,
	Success = INK,
	Gold = SUN,
	Health = INK,
	HealthLow = RED,
	Hunger = SUN, -- the colour a hungry or thirsty state takes (the bar itself is ink until it is low)
	Thirst = SUN,
	Stamina = INK,
	Armor = INK2,
	Track = INK,
	-- world, not UI: the border wall's own colour (ArenaController). UI that warns about the border uses Red.
	Border = Color3.fromRGB(120, 170, 255), -- the hollow blue border (was orange 232,92,50; matches Config.Border.WallLineColor, lighter for UI)
}

-- World colours that must not follow the UI palette.
Theme.World = {
	Border = Theme.Colors.Border,
	Ember = Color3.fromRGB(232, 116, 59), -- the old accent: for a world light or part that should stay ember
}

Theme.Transparency = {
	Panel = 1, -- Quiet has no panels: what used to be a translucent box is clear
	PanelStrong = 0.4, -- the one backing left: a modal sheet that cannot dim the whole screen
	PanelSoft = 1,
	Stroke = 0.5, -- a hairline in ink
	StrokeStrong = 0.25,
	BarTrack = 0.74, -- the empty part of a line bar (ink at 26%)
	TextShadow = 0.5, -- the dark stroke behind text
	Dim = 0.4, -- the full-screen shade behind a modal screen
	-- Quiet states
	TextRest = 0.28, -- a value that is fine (72%)
	TextDim = 0.38, -- a second word, a far compass letter (62%)
	TextFaint = 0.5, -- an old kill-feed line
	Hairline = 0.5, -- a 1 px rule in ink
	BarGhost = 0.6, -- where a bar was a moment ago
	KeyStroke = 0.08, -- the key square's outline
}

-- The dark stroke that keeps text and lines readable over the picture (a UIStroke named "Shadow").
Theme.Stroke = {
	Color = SHADE,
	Thickness = 1.5,
	Transparency = Theme.Transparency.TextShadow,
	BigThickness = 2, -- Light text at 24 and up
	BigTransparency = 0.55,
	LineTransparency = 0.6, -- the 1 px shade under a line bar or a hairline
}

-- World art, not UI: item tints (Shared.ItemModels, LootService). Unchanged.
Theme.Rarity = {
	Common = Color3.fromRGB(184, 184, 184),
	Uncommon = Color3.fromRGB(127, 176, 105),
	Rare = Color3.fromRGB(79, 163, 209),
	Epic = Color3.fromRGB(176, 127, 217),
	Legendary = Color3.fromRGB(232, 163, 59),
}

Theme.Corner = UDim.new(0, 6)
Theme.CornerSmall = UDim.new(0, 4)
Theme.CornerLarge = UDim.new(0, 6)
Theme.CornerPill = UDim.new(1, 0)
Theme.Padding = 30 -- screen-edge padding in pixels (desktop default; see Theme.edgePadding)
Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24 }
Theme.TextSize = {
	Small = 13, -- the floor: nothing is ever smaller than this
	Caption = 13,
	Label = 14,
	Body = 16,
	Heading = 18,
	Title = 28,
	Display = 44,
	Huge = 96,
	-- Quiet
	Number = 13, -- RobotoMono numbers beside a line or under a marker
	Status = 24, -- the lobby's status line (Light)
	Count = 37, -- the "17" of "17 left" (Light)
	Hero = 54, -- the game's title (Light, one label per letter)
}

Theme.Bar = {
	Height = 3,
	HealthHeight = 4,
	Icon = 14, -- the icon square at the left
	Gap = 9, -- icon to line, line to number
	ValueWidth = 26,
	RowHeight = 16,
	RowGap = 10,
	TickOverhang = 3, -- the healing tick stands this far above and below the line
}

Theme.Key = {
	Size = 26, -- height, and the least width
	Corner = UDim.new(0, 6),
	Thickness = 1.5,
	PadX = 7,
	Shade = 0.7, -- the little shade inside the square (background transparency), so it holds over a bright sky
}

Theme.Strip = {
	Height = 62, -- the slim strip along the bottom (defeat, spectating)
	Line = 1,
}

Theme.Time = {
	In = 0.16,
	Out = 0.4,
	Idle = 4, -- seconds a quiet element stays up after it last changed
}

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Fade = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
	FadeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Bar = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Ghost = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
	-- Quiet
	In = TweenInfo.new(Theme.Time.In, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Out = TweenInfo.new(Theme.Time.Out, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

-- Mobile action buttons (Shared.Input creates them). Positions are for phones; tablets are scaled up (x1.55 offsets, x1.3 size).
-- AnchorPoint is (0.5, 0.5); offsets are from the bottom-right corner, clear of Roblox's jump button.
-- The column at x = -268 (Aim, Drink) is the left edge of the cluster; the HUD keeps the hotbar left of it.
-- Drop sits alone at the top of the right edge (above RUN), clear of the top-centre HUD on the smallest phones.
Theme.TouchLayout = {
	Attack = { position = UDim2.new(1, -185, 1, -95), size = 84, label = "ATTACK" },
	Aim = { position = UDim2.new(1, -268, 1, -152), size = 60, label = "AIM" },
	-- ZOOM (the zoom, a toggle) shares AIM's slot: CameraController shows it only while AIM is hidden (no bow or spear
	-- in hand; with one, AIM has the slot), so it adds no button and covers nothing AIM doesn't
	Zoom = { position = UDim2.new(1, -268, 1, -152), size = 60, label = "ZOOM" },
	Sprint = { position = UDim2.new(1, -60, 1, -172), size = 60, label = "RUN" },
	Crouch = { position = UDim2.new(1, -150, 1, -185), size = 60, label = "CROUCH" },
	Drink = { position = UDim2.new(1, -268, 1, -70), size = 60, label = "DRINK" },
	Drop = { position = UDim2.new(1, -40, 0, 130), size = 46, label = "DROP" },
	SpectatePrev = { position = UDim2.new(0.5, -120, 1, -70), size = 56, label = "<" },
	SpectateNext = { position = UDim2.new(0.5, 120, 1, -70), size = 56, label = ">" },
	Default = { position = UDim2.new(1, -320, 1, -220), size = 56 },
}

-- HUD placement per device (HUDController applies it; UIBuilder.preview uses it too).
-- Desktop: vitals bottom left, the round's facts and the kill feed top right, the hotbar bottom centre.
-- Touch: the bottom left belongs to the thumbstick and the bottom right to the action buttons, so vitals and the
-- kill feed move to the top left (under the menu button) and the hotbar slides left of the buttons. The top right
-- holds the DROP button there, so the round's facts stay in the line under the compass (Facts = false).
-- Vitals sizes: the width is icon + gap + line + gap + number (the line takes what is left); the height holds
-- four rows and the "not healing" line.
Theme.Layout = {
	Desktop = {
		Vitals = { anchor = Vector2.new(0, 1), position = UDim2.fromScale(0, 1), size = UDim2.fromOffset(236, 128), align = "Bottom" },
		KillFeed = { anchor = Vector2.new(1, 0), position = UDim2.new(1, 0, 0, 68), size = UDim2.fromOffset(380, 150), align = "Right", max = 5 },
		SlotSize = 64,
		Facts = true, -- HUD.Root.Facts shows (top right) and Top.Info's Remain, Dot and Timer hide
	},
	Touch = { -- tablets
		Vitals = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 52), size = UDim2.fromOffset(190, 104), align = "Top" },
		KillFeed = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 190), size = UDim2.fromOffset(300, 92), align = "Left", max = 3 }, -- below the vitals' reason line (QW5)
		SlotSize = 48,
		Facts = false,
	},
	Phone = { -- touch screens whose short side is <= 500 px: two kill-feed rows so the feed never reaches the hotbar row
		Vitals = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 52), size = UDim2.fromOffset(190, 104), align = "Top" },
		KillFeed = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 190), size = UDim2.fromOffset(300, 58), align = "Left", max = 2 },
		SlotSize = 48,
		Facts = false,
	},
	SlotGap = 6,
	HotbarButtonMargin = 12, -- design px kept between the hotbar and the touch buttons
	IconSize = 44, -- an item's picture in its hotbar cell
	IconSelected = 54, -- ...and the one in hand
}

-- Style helpers

-- The dark stroke behind text (TextLabel / TextButton / TextBox) or around a line (Frame). One per object, named
-- "Shadow": controllers find it by that name to fade it with its text.
function Theme.shadow(gui: GuiObject, big: boolean?): UIStroke
	local existing = gui:FindFirstChild("Shadow")
	local stroke: UIStroke = if existing and existing:IsA("UIStroke") then existing else Instance.new("UIStroke")
	stroke.Name = "Shadow"
	stroke.Color = Theme.Stroke.Color
	stroke.Thickness = if big then Theme.Stroke.BigThickness else Theme.Stroke.Thickness
	stroke.Transparency = if big then Theme.Stroke.BigTransparency else Theme.Stroke.Transparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = gui
	return stroke
end

-- Quiet has no boxes. Called with no number the backing is clear; with a number it is a flat shade behind a modal
-- sheet. No corner and no outline are added.
function Theme.panel(gui: GuiObject, transparency: number?): GuiObject
	gui.BackgroundColor3 = Theme.Colors.Shade
	gui.BackgroundTransparency = transparency or Theme.Transparency.Panel
	gui.BorderSizePixel = 0
	return gui
end

function Theme.text(label: TextLabel | TextButton, fontKey: string?, size: number?)
	local px = math.max(Theme.TextSize.Small, size or Theme.TextSize.Body)
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.Colors.Ink
	label.FontFace = Theme.Fonts[fontKey or "Body"] or Theme.Fonts.Body
	label.TextSize = px
	Theme.shadow(label, px >= Theme.TextSize.Status)
	return label
end

function Theme.tween(instance: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

function Theme.escape(text: string): string
	local s = tostring(text)
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, "\"", "&quot;")
	s = string.gsub(s, "'", "&apos;")
	return s
end

function Theme.hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

function Theme.isSmallScreen(viewport: Vector2?): boolean
	local v = viewport
	if not v then
		local camera = workspace.CurrentCamera
		v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	end
	return math.min(v.X, v.Y) <= 500
end

-- Design resolution is 1280x720 at scale 1. Phones and tablets stay at 1 (the text floor). Bigger screens scale up
-- at half the rate the picture grows (1080p: 1.25, 1440p: 1.5, 4K: 2): the Quiet style keeps the HUD small, and its
-- 1080p sizes are the design sizes times 1.25. A TV (ten-foot) keeps the full rate: it is read from across a room.
function Theme.scaleFor(viewport: Vector2, tenFoot: boolean?): number
	local s = math.min(viewport.X / 1280, viewport.Y / 720)
	if tenFoot then
		s *= 1.15
	elseif s > 1 then
		s = 1 + (s - 1) * 0.5
	end
	return math.clamp(s, 1, 2.2)
end

function Theme.edgePadding(viewport: Vector2, tenFoot: boolean?): number
	if tenFoot then
		return 34 -- TV overscan
	end
	if Theme.isSmallScreen(viewport) then
		return 8
	end
	if math.min(viewport.X, viewport.Y) < 700 then
		return 16 -- a small window or a small tablet
	end
	return Theme.Padding
end

-- Keeps <screenGui>.Root (a Frame with a UIScale "Scale" and optional UIPadding "SafePad") sized for the viewport.
-- Returns a function that reports the current scale.
function Theme.bindRoot(screenGui: ScreenGui): () -> number
	local GuiService = game:GetService("GuiService")
	local root = screenGui:WaitForChild("Root") :: Frame
	local scaleObject = root:WaitForChild("Scale") :: UIScale
	local pad = root:FindFirstChild("SafePad") :: UIPadding?
	local cameraConnection: RBXScriptConnection? = nil
	local function apply()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		if viewport.X < 2 or viewport.Y < 2 then
			return
		end
		local tenFoot = GuiService:IsTenFootInterface()
		local s = Theme.scaleFor(viewport, tenFoot)
		scaleObject.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		if pad then
			local p = UDim.new(0, Theme.edgePadding(viewport, tenFoot))
			pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = p, p, p, p
		end
	end
	local function hook()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
		end
		apply()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	hook()
	return function()
		return scaleObject.Scale
	end
end

return Theme
