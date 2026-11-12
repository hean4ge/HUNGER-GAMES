--[[
	Theme - UI design tokens and small UI helpers. Stylized-realistic: calm, minimal, readable.
	The UI system owns this file (refine values freely, keep the keys). Everything that draws UI uses these tokens.

	Helpers (client):
	  Theme.panel(gui, transparency?)          dark translucent panel look (corner + hairline stroke)
	  Theme.text(label, fontKey?, size?)       text defaults
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

local function font(enumName: string, weight: Enum.FontWeight): Font
	local ok, f = pcall(function()
		return Font.fromEnum((Enum.Font :: any)[enumName])
	end)
	if ok and f then
		return Font.new(f.Family, weight, Enum.FontStyle.Normal)
	end
	return Font.new("rbxasset://fonts/families/GothamSSm.json", weight, Enum.FontStyle.Normal)
end

Theme.Fonts = {
	Display = font("Oswald", Enum.FontWeight.Bold), -- big titles, countdown numbers
	Heading = font("Oswald", Enum.FontWeight.Medium), -- small-caps labels and headers
	Body = font("BuilderSans", Enum.FontWeight.Medium),
	BodyBold = font("BuilderSans", Enum.FontWeight.Bold),
	Mono = font("RobotoMono", Enum.FontWeight.Medium), -- timers and numbers
	Light = font("Oswald", Enum.FontWeight.Regular), -- secondary display text
}

Theme.Colors = {
	Text = Color3.fromRGB(237, 232, 223), -- warm off-white
	TextDim = Color3.fromRGB(170, 165, 156),
	TextFaint = Color3.fromRGB(122, 118, 112),
	TextDark = Color3.fromRGB(28, 27, 25),
	Panel = Color3.fromRGB(15, 17, 20), -- charcoal
	PanelLight = Color3.fromRGB(40, 43, 48),
	Stroke = Color3.fromRGB(255, 255, 255),
	Shadow = Color3.fromRGB(0, 0, 0),
	Accent = Color3.fromRGB(232, 116, 59), -- ember orange
	AccentSoft = Color3.fromRGB(240, 170, 120),
	Danger = Color3.fromRGB(214, 69, 65),
	Warning = Color3.fromRGB(230, 168, 74),
	Success = Color3.fromRGB(127, 176, 105),
	Gold = Color3.fromRGB(226, 186, 110),
	Health = Color3.fromRGB(136, 178, 110),
	HealthLow = Color3.fromRGB(214, 69, 65),
	Hunger = Color3.fromRGB(217, 178, 106),
	Thirst = Color3.fromRGB(96, 166, 204),
	Stamina = Color3.fromRGB(228, 226, 218),
	Armor = Color3.fromRGB(164, 178, 196),
	Border = Color3.fromRGB(232, 92, 50),
	Track = Color3.fromRGB(255, 255, 255),
}

Theme.Transparency = {
	Panel = 0.38, -- translucent dark panels
	PanelStrong = 0.15,
	PanelSoft = 0.55,
	Stroke = 0.86,
	StrokeStrong = 0.6,
	BarTrack = 0.8, -- empty part of thin bars
	TextShadow = 0.55, -- soft dark outline on world-space HUD text
	Dim = 0.45, -- full-screen dim behind modal screens
}

Theme.Rarity = {
	Common = Color3.fromRGB(184, 184, 184),
	Uncommon = Color3.fromRGB(127, 176, 105),
	Rare = Color3.fromRGB(79, 163, 209),
	Epic = Color3.fromRGB(176, 127, 217),
	Legendary = Color3.fromRGB(232, 163, 59),
}

Theme.Corner = UDim.new(0, 6)
Theme.CornerSmall = UDim.new(0, 4)
Theme.CornerLarge = UDim.new(0, 10)
Theme.CornerPill = UDim.new(1, 0)
Theme.Padding = 12 -- screen-edge padding in pixels (desktop default; see Theme.edgePadding)
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
}

-- Mobile action buttons (Shared.Input creates them). Positions are for phones; tablets are scaled up (x1.55 offsets, x1.3 size).
-- AnchorPoint is (0.5, 0.5); offsets are from the bottom-right corner, clear of Roblox's jump button.
-- The column at x = -268 (Aim, Drink) is the left edge of the cluster; the HUD keeps the hotbar left of it.
-- Drop sits alone at the top of the right edge (above RUN), clear of the top-centre HUD on the smallest phones.
Theme.TouchLayout = {
	Attack = { position = UDim2.new(1, -185, 1, -95), size = 84, label = "ATTACK" },
	Aim = { position = UDim2.new(1, -268, 1, -152), size = 60, label = "AIM" },
	Sprint = { position = UDim2.new(1, -60, 1, -172), size = 60, label = "RUN" },
	Crouch = { position = UDim2.new(1, -150, 1, -185), size = 60, label = "CROUCH" },
	Drink = { position = UDim2.new(1, -268, 1, -70), size = 60, label = "DRINK" },
	Drop = { position = UDim2.new(1, -40, 0, 130), size = 46, label = "DROP" },
	SpectatePrev = { position = UDim2.new(0.5, -120, 1, -70), size = 56, label = "<" },
	SpectateNext = { position = UDim2.new(0.5, 120, 1, -70), size = 56, label = ">" },
	Default = { position = UDim2.new(1, -320, 1, -220), size = 56 },
}

-- HUD placement per device (HUDController applies it; UIBuilder.preview uses it too).
-- Touch: the bottom left belongs to the thumbstick and the bottom right to the action buttons, so vitals and the
-- kill feed move to the top left (under the menu button) and the hotbar slides left of the buttons.
Theme.Layout = {
	Desktop = {
		Vitals = { anchor = Vector2.new(0, 1), position = UDim2.fromScale(0, 1), size = UDim2.fromOffset(210, 120), align = "Bottom" },
		KillFeed = { anchor = Vector2.new(1, 0), position = UDim2.fromScale(1, 0), size = UDim2.fromOffset(380, 170), align = "Right", max = 5 },
		SlotSize = 56,
	},
	Touch = { -- tablets
		Vitals = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 52), size = UDim2.fromOffset(176, 104), align = "Top" },
		KillFeed = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 190), size = UDim2.fromOffset(300, 92), align = "Left", max = 3 }, -- below the vitals' reason line (QW5)
		SlotSize = 48,
	},
	Phone = { -- touch screens whose short side is <= 500 px: two kill-feed rows so the feed never reaches the hotbar row
		Vitals = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 52), size = UDim2.fromOffset(176, 104), align = "Top" },
		KillFeed = { anchor = Vector2.new(0, 0), position = UDim2.fromOffset(0, 190), size = UDim2.fromOffset(300, 58), align = "Left", max = 2 },
		SlotSize = 48,
	},
	SlotGap = 6,
	HotbarButtonMargin = 12, -- design px kept between the hotbar and the touch buttons
}

-- Style helpers
function Theme.panel(gui: GuiObject, transparency: number?): GuiObject
	gui.BackgroundColor3 = Theme.Colors.Panel
	gui.BackgroundTransparency = transparency or Theme.Transparency.Panel
	gui.BorderSizePixel = 0
	local corner = gui:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = Theme.Corner
	corner.Parent = gui
	local stroke = gui:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Stroke
	stroke.Transparency = Theme.Transparency.Stroke
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui
	return gui
end

function Theme.text(label: TextLabel | TextButton, fontKey: string?, size: number?)
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.Colors.Text
	label.FontFace = Theme.Fonts[fontKey or "Body"] or Theme.Fonts.Body
	label.TextSize = math.max(Theme.TextSize.Small, size or Theme.TextSize.Body)
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

-- Design resolution is 1280x720 at scale 1. Phones and tablets stay at 1 (text floor), big screens scale up.
function Theme.scaleFor(viewport: Vector2, tenFoot: boolean?): number
	local s = math.min(viewport.X / 1280, viewport.Y / 720)
	if tenFoot then
		s *= 1.15
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
	return 16
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
