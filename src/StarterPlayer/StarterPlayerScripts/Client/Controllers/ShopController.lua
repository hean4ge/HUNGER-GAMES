--[[
	ShopController - CASES, the card screen for the crates, the wheel, the Strongboxes and the Armoury
	(docs/design/CardMenusAndShop.md 2.4; mock-ups m06_cases_buy, m06b_cases_open, m06c_strongbox). The owner's
	reference layout in our look: matte dark panel (Shade lifted, 80%), cards at 86%, grade edges, no gloss or glow.

	  BUY tab   side list (5 crates · Prize Wheel · Strongbox · Masterwork Strongbox · Armoury) | buy card (3D box,
	            name, line, quantity stepper, price, BUY = hold 0.6 s to confirm) + odds card (per grade or star, true
	            share bars, Now and With Acorn columns, Total 100%, ODDS DETAILS, pity in numbers, Numbered, duplicates)
	            | Luck card (Lucky Acorn charges + "use a charge" switch) and the Shelf card; for weapons "Your Armoury"
	  OPEN tab  crates you hold as cards (×count, OPEN), and the reveal card: the lid lifts in the well, the item rises
	            in a tile with its grade washing the background softly, NEW, the name in Light, grade · type, one line,
	            PREVIEW and EQUIP; "Rolled twice: Crafted and Storied, kept Storied" when an Acorn was used
	  Buying several shows their reveal cards in a grid, best last.
	Strongboxes and wheel prizes keep their physical reveal at the steel case (RewardsService / WheelController): BUY
	on a Strongbox closes the screen and the case opens in the car. The wheel's card sends you to the wheel.
	Restricted players (only while a Robux switch makes crates paid random items): BUY is replaced by a line; OPEN and
	the Shelf stay. No Robux price, button or teaser shows while every Config.Shop switch is off.

	Opens with ShopController.open(entry?, tab?) (the menu hub, the steel case counter); only in the train.
	Input: mouse, touch (targets >= 44 px), gamepad (D-pad across, A choose / hold A to buy, B back, LB / RB tabs,
	Y odds details), Esc closes. Phones (short side <= 500): the side list becomes a strip of tiles across the top,
	the odds stay beside BUY, the Acorn switch sits in the buy card and the Shelf opens from the header.

	Remotes: Shop (ShopService) and Rewards (RewardsService, with the "menu" flag).
]]
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Crates = require(Shared:WaitForChild("Crates"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local function optional(name: string): any
	local m = Shared:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, result = pcall(require, m)
	return if ok then result else nil
end
local Icons = optional("Icons")
local ItemModels = optional("ItemModels")
local Cards = optional("Cards") -- the card kit: its focus ring and world dim (its tokens are the same as K below)

local player = Players.LocalPlayer
local GameState = ReplicatedStorage:WaitForChild("GameState")

local ShopController = {}
ShopController.isOpen = false

-- Tokens (the page's Theme.Card; local until the card kit adds them to Theme) -------------------------------------------
local C = Theme.Colors
local INK, INK2, SHADE, SUN = C.Ink, C.Ink2, C.Shade, C.Sun
local K = {
	Panel = Color3.fromRGB(17, 20, 23), PanelT = 0.2,
	Card = Color3.fromRGB(32, 37, 41), CardT = 0.14,
	Well = Color3.fromRGB(8, 9, 12), WellT = 0.45,
	StrokeT = 0.82, HairT = 0.88,
	Faint = C.TextFaint,
}
local F = Theme.Fonts

local shopRemote: RemoteEvent? = nil
local rewardsRemote: RemoteEvent? = nil
local controllers: any = nil

local shop: { [string]: any } = { held = {}, owned = {}, pity = {}, acorns = 0, shelf = {}, robux = {} }
local rew: { [string]: any } = { armoury = {}, pity = {} }

local ENTRIES = {
	{ id = "timber", kind = "crate", group = "COSMETIC CRATES" },
	{ id = "ironbound", kind = "crate" },
	{ id = "steel", kind = "crate" },
	{ id = "silverleaf", kind = "crate" },
	{ id = "crown", kind = "crate" },
	{ id = "wheel", kind = "wheel", group = "WEAPONS (STARS)" },
	{ id = "strongbox", kind = "box" },
	{ id = "masterwork", kind = "box" },
	{ id = "armoury", kind = "armoury" },
}
local ENTRY = {}
for _, e in ipairs(ENTRIES) do
	ENTRY[e.id] = e
end

local ui: { [string]: any } = {}
local current = "steel"
local tab = "buy"
local quantity = 1
local acornOn = false
local armourySel = "sword"
local phone = false
local viewports = {} -- [ViewportFrame] = true (for the 24 limit)
local revealToken = 0
local lastResult: any = nil

-- Small builders -----------------------------------------------------------------------------------------------------

local function make(class: string, props: { [string]: any }?, parent: Instance?): any
	local o = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			(o :: any)[k] = v
		end
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(gui: Instance, r: number)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, gui)
end

local function edge(gui: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local s = gui:FindFirstChild("Edge") or make("UIStroke", { Name = "Edge" }, gui)
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

local function panelFrame(name: string, parent: Instance, kind: string?): Frame
	local f = make("Frame", { Name = name, BorderSizePixel = 0, BackgroundColor3 = if kind == "panel" then K.Panel else K.Card,
		BackgroundTransparency = if kind == "panel" then K.PanelT else K.CardT }, parent)
	corner(f, if kind == "panel" then 12 else 10)
	edge(f, INK, 1.5, if kind == "panel" then 0.88 else K.StrokeT)
	return f
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1, TextColor3 = INK, FontFace = F.Medium, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Text = "",
	}, parent)
	for k, v in pairs(props) do
		if k ~= "Font" then
			(l :: any)[k] = v
		end
	end
	if type(props.Font) == "string" then
		l.FontFace = (F :: any)[props.Font]
	end
	return l
end

local function sound(key: string, volume: number?, pitch: number?)
	pcall(Sfx.play, key, { volume = volume or 0.5, pitch = pitch })
end

-- kind: "primary" (Ink fill), "secondary" (Ink outline), "sun" (CLAIM / OPEN only), "off"
local function button(parent: Instance, kind: string, text: string, props: { [string]: any }?): TextButton
	local b = make("TextButton", { AutoButtonColor = false, BorderSizePixel = 0, Text = text, FontFace = F.SemiBold,
		TextSize = 15, Selectable = true }, parent)
	corner(b, 8)
	b:SetAttribute("Kind", kind)
	if Cards and Cards.focusRing then
		pcall(function()
			b.SelectionImageObject = Cards.focusRing()
		end)
	end
	local function paint()
		local k = b:GetAttribute("Kind")
		local stroke = b:FindFirstChild("Edge")
		if k == "primary" then
			b.BackgroundColor3, b.BackgroundTransparency, b.TextColor3 = INK, 0, SHADE
			if stroke then
				stroke.Transparency = 1
			end
		elseif k == "sun" then
			b.BackgroundColor3, b.BackgroundTransparency, b.TextColor3 = SUN, 0, SHADE
			if stroke then
				stroke.Transparency = 1
			end
		elseif k == "off" then
			b.BackgroundColor3, b.BackgroundTransparency, b.TextColor3 = INK, 0.92, K.Faint
			edge(b, INK, 1, 0.9)
		elseif k == "plain" then
			b.BackgroundColor3, b.BackgroundTransparency, b.TextColor3 = INK, 1, INK
			edge(b, INK, 1.5, 1)
		else
			b.BackgroundColor3, b.BackgroundTransparency, b.TextColor3 = INK, 1, INK
			edge(b, INK, 1.5, 0.15)
		end
	end
	b:GetAttributeChangedSignal("Kind"):Connect(paint)
	paint()
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Kind") ~= "off" then
			sound("UIHover", 0.25)
		end
	end)
	if props then
		for k, v in pairs(props) do
			(b :: any)[k] = v
		end
	end
	return b
end

local function setKind(b: TextButton, kind: string)
	b:SetAttribute("Kind", kind)
end

local function icon(name: string, parent: Instance, props: { [string]: any }?): GuiObject?
	if not Icons then
		return nil
	end
	local ok, g = pcall(Icons.make, name, props or {})
	if ok and g then
		g.Parent = parent
		return g
	end
	return nil
end

local function well(parent: Instance, props: { [string]: any }?): Frame
	local w = make("Frame", { Name = "Well", BorderSizePixel = 0, BackgroundColor3 = K.Well, BackgroundTransparency = K.WellT,
		ClipsDescendants = true }, parent)
	corner(w, 6)
	local g = make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.1) }),
		Color = ColorSequence.new(Color3.fromRGB(40, 44, 50), K.Well), Rotation = 90 }, w)
	g.Name = "Soft"
	if props then
		for k, v in pairs(props) do
			(w :: any)[k] = v
		end
	end
	return w
end

local function comma(n: number): string
	return Crates.comma(n or 0)
end

local function starText(n: number): string
	return string.rep("★", math.clamp(math.floor(n or 0), 0, 5))
end

-- Live 3D views ----------------------------------------------------------------------------------------------------------

local function frameModel(vf: ViewportFrame, model: Model, yaw: number?, pitch: number?)
	local cam = vf.CurrentCamera or make("Camera", { FieldOfView = 26 }, vf)
	vf.CurrentCamera = cam
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.05
	local dir = (CFrame.Angles(0, math.rad(yaw or 25), 0) * CFrame.Angles(math.rad(-(pitch or 18)), 0, 0)).LookVector
	cam.CFrame = CFrame.lookAt(cf.Position - dir * dist, cf.Position)
	vf.Ambient = Color3.fromRGB(150, 148, 146)
	vf.LightColor = Color3.fromRGB(255, 244, 228)
	vf.LightDirection = Vector3.new(-0.55, -0.85, -0.6)
end

local function newViewport(parent: Instance, props: { [string]: any }?): ViewportFrame
	local vf = make("ViewportFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Name = "View" }, parent)
	if props then
		for k, v in pairs(props) do
			(vf :: any)[k] = v
		end
	end
	viewports[vf] = true
	vf.Destroying:Connect(function()
		viewports[vf] = nil
	end)
	return vf
end

local function crateView(parent: Instance, crateId: string): (ViewportFrame, Model)
	local vf = newViewport(parent)
	local model = Crates.buildModel(crateId)
	model:PivotTo(CFrame.new())
	model.Parent = vf
	frameModel(vf, model, 28, 20)
	return vf, model
end

local function weaponView(parent: Instance, id: string, tint: Color3?): ViewportFrame?
	if not ItemModels then
		return nil
	end
	local vf = newViewport(parent)
	local ok, model = pcall(ItemModels.renderIcon, vf, id)
	if not ok or not model then
		vf:Destroy()
		return nil
	end
	if tint then
		-- a skin stand-in: the weapon re-coloured toward the skin's look (the cosmetics agent's real looks replace it)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Color = d.Color:Lerp(tint, 0.55)
				if d:IsA("MeshPart") then
					pcall(function()
						(d :: any).TextureID = ""
					end)
				end
			end
		end
	end
	return vf
end

local TYPE_ICON = { ["Kill effect"] = "kill_effect", ["Kill icon"] = "kill_icon", Banner = "banner", Emote = "emote",
	["Launch effect"] = "spark", Wrap = "skin", Skin = "skin" }

-- An item's picture in a well: a skin = its weapon in 3D; everything else = its glyph
local function itemPicture(parent: Instance, item: any): GuiObject?
	if not item then
		return nil
	end
	local Looks = optional("CosmeticLooks")
	local look = Looks and Looks.get and Looks.get(item.id)
	if item.type == "Skin" and item.weapon then
		-- the skin's own look (CosmeticLooks, by PartRole) on the live weapon; else a tint toward its colour
		local vf = weaponView(parent, item.weapon, if look and Looks.applySkin then nil else item.tint)
		if vf then
			local model = vf:FindFirstChildWhichIsA("Model")
			if model and look and Looks.applySkin then
				pcall(Looks.applySkin, model, item.id, true)
			end
			return vf
		end
	end
	if look and item.type == "Kill icon" and Looks.killIcon then
		local ok, g = pcall(Looks.killIcon, item.id, 64, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.66, 0.66) })
		if ok and g then
			g.Parent = parent
			return g
		end
	elseif look and item.type == "Banner" and Looks.banner then
		local ok, g = pcall(Looks.banner, item.id, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.29) })
		if ok and g then
			g.Parent = parent
			return g
		end
	end
	-- the item's own drawn cell (kill effect, emote, launch effect, a skin's tile ...), else its kind's glyph
	local own = Icons and Icons.cell and Icons.cell(tostring(item.id))
	local g = icon(own or TYPE_ICON[item.type] or "spark", parent, { Size = UDim2.fromScale(if own then 0.86 else 0.62, if own then 0.86 else 0.62),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	if g and not own and item.tint and Icons and Icons.tint then
		pcall(Icons.tint, g, item.tint)
	end
	return g
end

-- Grade tile: a well with the grade's edge and 4 px bottom bar, a grade label and a name
local function gradeTile(parent: Instance, item: any, size: number, props: { [string]: any }?): Frame
	local col = Crates.GradeColor[item.grade] or INK2
	local t = make("Frame", { Name = "Tile_" .. tostring(item.id), BackgroundColor3 = K.Card, BackgroundTransparency = K.CardT,
		BorderSizePixel = 0, Size = UDim2.fromOffset(size, size) }, parent)
	corner(t, 6)
	local rank = Crates.GradeRank[item.grade] or 1
	edge(t, col, 1.5, 0.3 - rank * 0.05)
	local w = well(t, { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4) })
	itemPicture(w, item)
	make("Frame", { Name = "Bar", BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 4),
		Position = UDim2.new(0, 4, 1, -8) }, t)
	if item.grade == "Fabled" then
		local inner = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3) }, t)
		corner(inner, 5)
		edge(inner, col, 1, 0.45)
	end
	if size >= 80 then
		label(t, { Text = string.upper(item.grade), Font = "SemiBold", TextSize = 13, TextColor3 = Crates.GradeLabel[item.grade] or INK2,
			Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 16) })
	end
	if props then
		for k, v in pairs(props) do
			(t :: any)[k] = v
		end
	end
	return t
end

-- The screen ------------------------------------------------------------------------------------------------------------

local function inRound(): boolean
	return GameState:GetAttribute("Phase") == "Active" and player:GetAttribute("Alive") == true
end

local function gold(): number
	return tonumber(player:GetAttribute("Gold")) or tonumber(shop.gold) or 0
end

local function heldTotal(): number
	local n = 0
	for _, c in pairs(shop.held or {}) do
		n += c
	end
	return n
end

local function blurOn(on: boolean)
	if Cards and Cards.dimWorld then
		pcall(Cards.dimWorld, on)
		return
	end
	local blur = Lighting:FindFirstChild("CasesBlur") :: BlurEffect?
	if on and not blur then
		blur = make("BlurEffect", { Name = "CasesBlur", Size = 0 }, Lighting)
	end
	if blur then
		local t = TweenService:Create(blur, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = if on then 12 else 0 })
		t:Play()
		if not on then
			t.Completed:Connect(function()
				if not ShopController.isOpen and blur then
					blur:Destroy()
				end
			end)
		end
	end
end

local refresh: () -> () -- forward
local layout: () -> ()
local showResult: (any) -> ()

-- the hold-to-confirm BUY: hold 0.6 s (mouse, touch, or A); a tap says "Hold to confirm"
local function holdButton(b: TextButton, onConfirm: () -> ())
	local fill = make("Frame", { Name = "Fill", BackgroundColor3 = SHADE, BackgroundTransparency = 0.75, BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1), ZIndex = b.ZIndex + 1 }, b)
	corner(fill, 8)
	local holding = 0
	local base = b.Text
	local function start()
		if b:GetAttribute("Kind") == "off" or b:GetAttribute("NoHold") == true then
			return
		end
		holding += 1
		local token = holding
		base = b.Text
		b.Text = "HOLD TO CONFIRM"
		fill.Size = UDim2.fromScale(0, 1)
		local t = TweenService:Create(fill, TweenInfo.new(0.6, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		t:Play()
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and holding == token then
				holding += 1
				fill.Size = UDim2.fromScale(0, 1)
				b.Text = base
				sound("UIClick", 0.7, 0.9)
				onConfirm()
			end
		end)
	end
	local function stop()
		if fill.Size.X.Scale < 1 and holding > 0 then
			holding += 1
			TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(0, 1) }):Play()
			task.delay(1.4, function()
				if b.Text == "HOLD TO CONFIRM" then
					b.Text = base
				end
			end)
		end
	end
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
			or (t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA) then
			start()
		end
	end)
	b.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
			or (t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA) then
			stop()
		end
	end)
	b.MouseLeave:Connect(stop)
	-- gamepad: hold A while the button is selected (Roblox keeps A for selection, so this listens globally)
	local c1 = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonA and GuiService.SelectedObject == b and b.Visible then
			start()
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonA then
			stop()
		end
	end)
	b.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
end

local function toast(text: string)
	if not ui.toast then
		return
	end
	ui.toast.Text = text
	ui.toast.TextTransparency = 0
	local token = (ui.toastToken or 0) + 1
	ui.toastToken = token
	task.delay(4, function()
		if ui.toastToken == token and ui.toast then
			TweenService:Create(ui.toast, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
	end)
end

local function sendShop(...)
	if shopRemote then
		shopRemote:FireServer(...)
	end
end

local function sendRewards(action: string, arg: any)
	if rewardsRemote then
		rewardsRemote:FireServer(action, arg, "menu")
	end
end

-- Side list ----------------------------------------------------------------------------------------------------------

local function entryName(e: any): string
	if e.kind == "crate" then
		return Crates.ById[e.id].name
	end
	return ({ wheel = "Prize Wheel", strongbox = "Strongbox", masterwork = "Masterwork Strongbox", armoury = "Armoury" })[e.id]
end

local function entryPrice(e: any): (string, boolean)
	local cfg = Rewards.config()
	if e.kind == "crate" then
		return comma(Crates.ById[e.id].gold), true
	elseif e.id == "wheel" then
		if (rew.freeLeft or 0) > 0 then
			return "free today", false
		end
		return comma(rew.spinCost or cfg.Wheel.SpinCost), true
	elseif e.id == "strongbox" then
		return comma(cfg.Strongbox.Cost), true
	elseif e.id == "masterwork" then
		return comma(cfg.Strongbox.MasterworkCost), true
	end
	return "choose", false
end

-- a case's drawn icon from the sheets (Shared.Icons "case_<id>"); false if it has none
local function caseIcon(parent: Instance, id: string, scale: number): boolean
	if not (Icons and Icons.cell and Icons.cell("case_" .. id)) then
		return false
	end
	return icon("case_" .. id, parent, { Size = UDim2.fromScale(scale, scale), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5) }) ~= nil
end

local function entryPicture(e: any, parent: Instance)
	if caseIcon(parent, tostring(e.id), 0.8) then
		return
	elseif e.kind == "crate" or e.kind == "box" then
		crateView(parent, e.id)
	elseif e.id == "wheel" then
		icon("wheel", parent, { Size = UDim2.fromScale(0.7, 0.7), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	else
		icon("crate", parent, { Size = UDim2.fromScale(0.7, 0.7), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	end
end

local select: (string) -> ()

local function buildSide(parent: Instance)
	local side = make("ScrollingFrame", { Name = "Side", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = INK, ScrollBarImageTransparency = 0.6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.XY,
		Selectable = false }, parent)
	ui.side = side
	ui.sideRows = {}
	ui.sideHeads = {}
	for i, e in ipairs(ENTRIES) do
		if e.group then
			local h = label(side, { Text = e.group, Font = "SemiBold", TextSize = 13, TextColor3 = INK2, Name = "Head" .. i })
			ui.sideHeads[e.id] = h
		end
		local row = make("TextButton", { Name = "Entry_" .. e.id, AutoButtonColor = false, Text = "", BackgroundColor3 = K.Card,
			BackgroundTransparency = K.CardT, BorderSizePixel = 0, Selectable = true }, side)
		corner(row, 8)
		edge(row, INK, 1.5, K.StrokeT)
		local w = well(row, { Name = "Pic" })
		entryPicture(e, w)
		local name = label(row, { Name = "Name", Text = entryName(e), Font = "SemiBold", TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd })
		local priceRow = make("Frame", { Name = "Price", BackgroundTransparency = 1 }, row)
		icon("coin", priceRow, { Name = "Coin", Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(0, 2) })
		local price = label(priceRow, { Name = "Value", Font = "Mono", TextSize = 13, TextColor3 = INK2, Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -16, 1, 0) })
		local count = label(row, { Name = "Count", Font = "Mono", TextSize = 13, TextColor3 = SUN, TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0), Visible = false })
		row.Activated:Connect(function()
			sound("UIClick", 0.4)
			select(e.id)
		end)
		ui.sideRows[e.id] = { row = row, well = w, name = name, price = price, coin = priceRow:FindFirstChild("Coin"), priceRow = priceRow,
			count = count }
	end
end

-- Buy card -----------------------------------------------------------------------------------------------------------

local function buildBuyCard(parent: Instance)
	local card = panelFrame("BuyCard", parent)
	ui.buy = { card = card }
	local b = ui.buy
	b.well = well(card, { Name = "Pic" })
	b.name = label(card, { Name = "Title", Font = "SemiBold", TextSize = 24 })
	b.line = label(card, { Name = "Line", TextSize = 14, TextColor3 = INK2, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	b.qtyLabel = label(card, { Name = "QtyLabel", Text = "Quantity", TextSize = 13, TextColor3 = INK2 })
	b.minus = button(card, "secondary", "−", { Name = "Minus", TextSize = 20 })
	b.qty = label(card, { Name = "Qty", Font = "Mono", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.6,
		BackgroundColor3 = K.Well })
	corner(b.qty, 6)
	b.plus = button(card, "secondary", "+", { Name = "Plus", TextSize = 20 })
	b.priceLabel = label(card, { Name = "PriceLabel", Text = "Price", TextSize = 13, TextColor3 = INK2 })
	b.coin = icon("coin", card, { Name = "Coin", Size = UDim2.fromOffset(16, 16) })
	b.price = label(card, { Name = "Price", Font = "Mono", TextSize = 24 })
	b.action = button(card, "primary", "BUY", { Name = "Buy", TextSize = 17 })
	b.note = label(card, { Name = "Note", TextSize = 13, TextColor3 = INK2, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	-- the phone's Acorn switch (the Luck card's, inside the buy card)
	b.acornRow = make("TextButton", { Name = "AcornRow", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Selectable = true }, card)
	b.acornSwitch = make("Frame", { Name = "Switch", BackgroundColor3 = INK, BackgroundTransparency = 0.8, BorderSizePixel = 0,
		Size = UDim2.fromOffset(40, 22) }, b.acornRow)
	corner(b.acornSwitch, 11)
	b.acornKnob = make("Frame", { Name = "Knob", BackgroundColor3 = INK, BorderSizePixel = 0, Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromOffset(3, 3) }, b.acornSwitch)
	corner(b.acornKnob, 8)
	b.acornText = label(b.acornRow, { Name = "Text", TextSize = 13, Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -48, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd })
	b.minus.Activated:Connect(function()
		quantity = math.max(1, quantity - 1)
		sound("UIClick", 0.35, 0.9)
		refresh()
	end)
	b.plus.Activated:Connect(function()
		local e = ENTRY[current]
		local max = if e.kind == "crate" then (shop.maxQuantity or 10) else 1
		quantity = math.min(max, quantity + 1)
		sound("UIClick", 0.35, 1.1)
		refresh()
	end)
	holdButton(b.action, function()
		local e = ENTRY[current]
		if e.kind == "crate" then
			sendShop("buy", e.id, quantity, acornOn and (shop.acorns or 0) > 0)
		elseif e.kind == "box" then
			-- the physical reveal at the steel case: the screen steps aside
			sendRewards("box", e.id)
			ShopController.close()
		elseif e.kind == "armoury" then
			local owned = (rew.armoury or {})[armourySel] or 0
			if owned < 5 then
				sendRewards(if owned < 3 then "buy" else "raise", armourySel)
			end
		end
	end)
	b.action.Activated:Connect(function()
		local e = ENTRY[current]
		if e.kind == "wheel" then
			ShopController.close()
			toast("")
		end
	end)
end

-- Odds card ----------------------------------------------------------------------------------------------------------

local function buildOddsCard(parent: Instance)
	local card = panelFrame("OddsCard", parent)
	ui.odds = { card = card, rows = {} }
	local o = ui.odds
	o.title = label(card, { Name = "Title", Font = "SemiBold", TextSize = 17 })
	o.details = button(card, "secondary", "ODDS DETAILS", { Name = "Details", TextSize = 14 })
	o.headGrade = label(card, { Name = "HeadGrade", Text = "Grade", TextSize = 13, TextColor3 = INK2 })
	o.headNow = label(card, { Name = "HeadNow", Text = "Now", TextSize = 13, TextColor3 = INK2, TextXAlignment = Enum.TextXAlignment.Right })
	o.headAcorn = label(card, { Name = "HeadAcorn", Text = "With Acorn", TextSize = 13, TextColor3 = INK2, TextXAlignment = Enum.TextXAlignment.Right })
	o.list = make("Frame", { Name = "Rows", BackgroundTransparency = 1 }, card)
	o.rule = make("Frame", { Name = "Rule", BackgroundColor3 = INK, BackgroundTransparency = K.HairT, BorderSizePixel = 0 }, card)
	o.notes = make("ScrollingFrame", { Name = "Notes", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Selectable = false }, card)
	o.notesText = label(o.notes, { Name = "Text", RichText = true, TextWrapped = true, TextSize = 14, TextColor3 = INK2,
		TextYAlignment = Enum.TextYAlignment.Top, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -6, 0, 0), LineHeight = 1.15 })
	o.details.Activated:Connect(function()
		sound("UIClick", 0.4)
		ShopController.showDetails()
	end)
end

-- rows = { { name, color, pct, acornPct? } }
local function setOddsRows(rows: { any }, showAcorn: boolean, rowH: number, width: number)
	local o = ui.odds
	for _, r in ipairs(o.rows) do
		r:Destroy()
	end
	o.rows = {}
	local nameW = math.floor(width * (if phone then 0.3 else 0.22))
	local numW = if phone then 54 else 70
	local acornW = if showAcorn then numW + 16 else 0
	local barX = nameW + 8
	local barW = math.max(30, width - barX - numW - acornW - 16)
	local total, totalA = 0, 0
	for i, row in ipairs(rows) do
		local f = make("Frame", { Name = "Row" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH),
			Position = UDim2.fromOffset(0, (i - 1) * rowH) }, o.list)
		label(f, { Name = "Name", Text = row.name, Font = "SemiBold", TextSize = if phone then 14 else 16, TextColor3 = row.color,
			Size = UDim2.new(0, nameW, 1, 0), RichText = true })
		local track = make("Frame", { Name = "Track", BackgroundColor3 = INK, BackgroundTransparency = 0.84, BorderSizePixel = 0,
			Size = UDim2.fromOffset(barW, 6), Position = UDim2.new(0, barX, 0.5, -3) }, f)
		corner(track, 3)
		local fill = make("Frame", { Name = "Fill", BackgroundColor3 = row.bar or row.color, BorderSizePixel = 0,
			Size = UDim2.fromScale(math.clamp(row.pct / 100, 0.012, 1), 1) }, track)
		corner(fill, 3)
		label(f, { Name = "Now", Text = Crates.fmt(row.pct), Font = "Mono", TextSize = if phone then 14 else 16,
			TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(0, numW, 1, 0), Position = UDim2.new(1, -(numW + acornW), 0, 0) })
		if showAcorn and row.acornPct then
			label(f, { Name = "Acorn", Text = Crates.fmt(row.acornPct), Font = "Mono", TextSize = if phone then 14 else 16,
				TextColor3 = if acornOn then SUN else INK2, TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0, acornW, 1, 0), Position = UDim2.new(1, -acornW, 0, 0) })
		end
		total += row.pct
		totalA += row.acornPct or 0
		table.insert(o.rows, f)
	end
	local f = make("Frame", { Name = "Total", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH),
		Position = UDim2.fromOffset(0, #rows * rowH) }, o.list)
	label(f, { Text = "Total", TextSize = 15, TextColor3 = INK2, Size = UDim2.new(0, nameW, 1, 0) })
	label(f, { Text = Crates.fmt(total), Font = "Mono", TextSize = 15, TextColor3 = INK2, TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0, numW, 1, 0), Position = UDim2.new(1, -(numW + acornW), 0, 0) })
	if showAcorn then
		label(f, { Text = Crates.fmt(totalA), Font = "Mono", TextSize = 15, TextColor3 = INK2, TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0, acornW, 1, 0), Position = UDim2.new(1, -acornW, 0, 0) })
	end
	table.insert(o.rows, f)
	o.headAcorn.Visible = showAcorn
	return (#rows + 1) * rowH
end

-- Right column: Luck, Shelf, Your Armoury --------------------------------------------------------------------------

local function buildLuckCard(parent: Instance)
	local card = panelFrame("LuckCard", parent)
	ui.luck = { card = card }
	local l = ui.luck
	l.head = label(card, { Text = "LUCK", Font = "SemiBold", TextSize = 16, Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 22) })
	l.well = well(card, { Position = UDim2.fromOffset(20, 44), Size = UDim2.fromOffset(84, 84) })
	icon("acorn", l.well, { Size = UDim2.fromScale(0.62, 0.62), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	l.name = label(card, { Text = "Lucky Acorn", Font = "SemiBold", TextSize = 20, Position = UDim2.fromOffset(118, 58), Size = UDim2.new(1, -138, 0, 26) })
	l.count = label(card, { Text = "", TextSize = 14, TextColor3 = INK2, Position = UDim2.fromOffset(118, 84), Size = UDim2.new(1, -138, 0, 20),
		RichText = true })
	l.body = label(card, { RichText = true, TextWrapped = true, TextSize = 14, TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(20, 140), Size = UDim2.new(1, -40, 0, 58),
		Text = "One charge: <b>this crate rolls twice and keeps the better grade.</b> The right column shows your odds with it." })
	l.toggle = make("TextButton", { Name = "Toggle", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Selectable = true,
		Position = UDim2.fromOffset(20, 204), Size = UDim2.new(1, -40, 0, 28) }, card)
	l.switch = make("Frame", { BackgroundColor3 = INK, BackgroundTransparency = 0.8, BorderSizePixel = 0, Size = UDim2.fromOffset(44, 24),
		Position = UDim2.fromOffset(0, 2) }, l.toggle)
	corner(l.switch, 12)
	l.knob = make("Frame", { BackgroundColor3 = INK, BorderSizePixel = 0, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3) }, l.switch)
	corner(l.knob, 9)
	l.toggleText = label(l.toggle, { Text = "Use a charge on this crate", Font = "SemiBold", TextSize = 14, Position = UDim2.fromOffset(54, 0),
		Size = UDim2.new(1, -54, 1, 0) })
	l.foot = label(card, { TextWrapped = true, TextSize = 13, TextColor3 = K.Faint, TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(20, 238), Size = UDim2.new(1, -40, 0, 34),
		Text = "Earned only: daily reward day 6, rank-ups, Season Track. Never sold." })
	-- the Robux Lucky Charm (only when Config.Shop.RobuxLuck is on and the player may buy it)
	l.charm = button(card, "secondary", "LUCKY CHARM", { Name = "Charm", Visible = false, TextSize = 13 })
	l.charm.Activated:Connect(function()
		sendShop("robux", "luck")
	end)
	local function flip()
		if (shop.acorns or 0) <= 0 then
			toast("No Lucky Acorns yet · the daily reward's day 6, rank-ups and the Season Track give them")
			acornOn = false
		else
			acornOn = not acornOn
		end
		sound("UIClick", 0.4, if acornOn then 1.1 else 0.9)
		refresh()
	end
	l.toggle.Activated:Connect(flip)
	ui.buy.acornRow.Activated:Connect(flip)
end

local function buildShelfCard(parent: Instance)
	local card = panelFrame("ShelfCard", parent)
	ui.shelf = { card = card }
	local s = ui.shelf
	label(card, { Text = "INSTEAD, BUY IT OUTRIGHT", Font = "SemiBold", TextSize = 16, Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 22) })
	label(card, { TextWrapped = true, TextSize = 14, TextColor3 = INK2, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(20, 40),
		Size = UDim2.new(1, -40, 0, 40), Text = "Every crate item is also on the Shelf by name, so nobody must gamble for one." })
	s.tiles = make("Frame", { Name = "Tiles", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 88), Size = UDim2.new(1, -40, 0, 96) }, card)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }, s.tiles)
	s.open = button(card, "secondary", "OPEN THE SHELF", { Name = "OpenShelf", TextSize = 14, Position = UDim2.fromOffset(20, 196),
		Size = UDim2.fromOffset(170, 36) })
	s.open.Activated:Connect(function()
		sound("UIClick", 0.4)
		ShopController.showShelf()
	end)
end

local function buildArmouryCard(parent: Instance)
	local card = panelFrame("ArmouryCard", parent)
	ui.arm = { card = card, tiles = {} }
	local a = ui.arm
	a.head = label(card, { Text = "YOUR ARMOURY", Font = "SemiBold", TextSize = 16, Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 22) })
	a.grid = make("ScrollingFrame", { Name = "Grid", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Selectable = false, Position = UDim2.fromOffset(20, 44) }, card)
	a.layout = make("UIGridLayout", { CellSize = UDim2.fromOffset(92, 80), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, a.grid)
	for i, id in ipairs(Rewards.Pool) do
		local t = make("TextButton", { Name = "W_" .. id, Text = "", AutoButtonColor = false, BackgroundColor3 = K.Card,
			BackgroundTransparency = K.CardT, BorderSizePixel = 0, LayoutOrder = i, Selectable = true }, a.grid)
		corner(t, 6)
		edge(t, INK, 1.5, K.StrokeT)
		local w = well(t, { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3) })
		local vf = weaponView(w, id)
		local stars = label(t, { Name = "Stars", Font = "Medium", TextSize = 13, Position = UDim2.new(0, 8, 1, -20), Size = UDim2.new(1, -16, 0, 16) })
		local lock = icon("lock", t, { Name = "Lock", Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45) })
		local bring = label(t, { Name = "Bring", Text = "BRING", Font = "SemiBold", TextSize = 13, TextColor3 = SUN, Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 14), Visible = false })
		t.Activated:Connect(function()
			sound("UIClick", 0.4)
			armourySel = id
			if current ~= "armoury" then
				select("armoury")
			else
				refresh()
			end
		end)
		a.tiles[id] = { button = t, view = vf, stars = stars, lock = lock, bring = bring }
	end
	a.open = button(card, "secondary", "OPEN THE ARMOURY", { Name = "OpenArmoury", TextSize = 14, Size = UDim2.fromOffset(190, 36) })
	a.open.Activated:Connect(function()
		sound("UIClick", 0.4)
		select("armoury")
	end)
	a.bringBtn = button(card, "secondary", "BRING IT NEXT ROUND", { Name = "Bring", TextSize = 14, Size = UDim2.fromOffset(210, 36), Visible = false })
	a.bringBtn.Activated:Connect(function()
		local owned = (rew.armoury or {})[armourySel] or 0
		if owned > 0 then
			sendRewards("bring", if rew.bring == armourySel then "" else armourySel)
		end
	end)
end

-- Open tab ------------------------------------------------------------------------------------------------------------

local function buildOpenView(parent: Instance)
	local v = make("Frame", { Name = "OpenView", BackgroundTransparency = 1, Visible = false }, parent)
	ui.open = { view = v, cards = {} }
	local o = ui.open
	o.head = label(v, { Text = "YOURS TO OPEN", Font = "SemiBold", TextSize = 16 })
	o.grid = make("ScrollingFrame", { Name = "Grid", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Selectable = false }, v)
	o.layout = make("UIGridLayout", { CellSize = UDim2.fromOffset(200, 236), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder }, o.grid)
	o.note = label(v, { TextWrapped = true, TextSize = 13, TextColor3 = INK2, TextYAlignment = Enum.TextYAlignment.Top,
		Text = "Crates from the daily reward, the Season Track and ranks wait here. Opening is free. Strongboxes and wheel prizes open at the steel case in the train, where others in the car can watch." })
	o.acorn = make("TextButton", { Name = "AcornToggle", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Selectable = true }, v)
	o.acornText = label(o.acorn, { TextSize = 14, Font = "SemiBold", Size = UDim2.fromScale(1, 1), RichText = true })
	o.acorn.Activated:Connect(function()
		if (shop.acorns or 0) > 0 then
			acornOn = not acornOn
		end
		refresh()
	end)
	for i, crate in ipairs(Crates.List) do
		local c = panelFrame("Held_" .. crate.id, o.grid)
		c.LayoutOrder = i
		local w = well(c, { Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 118) })
		if not caseIcon(w, crate.id, 0.86) then
			crateView(w, crate.id)
		end
		local name = label(c, { Text = crate.name, Font = "SemiBold", TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 138), Size = UDim2.new(1, 0, 0, 24) })
		local count = label(c, { Font = "Mono", TextSize = 14, TextColor3 = INK2, TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 162), Size = UDim2.new(1, 0, 0, 18) })
		local b = button(c, "primary", "OPEN", { Position = UDim2.new(0, 14, 1, -50), Size = UDim2.new(1, -28, 0, 36), TextSize = 15 })
		b.Activated:Connect(function()
			if (shop.held or {})[crate.id] and shop.held[crate.id] > 0 then
				sound("UIClick", 0.5)
				sendShop("open", crate.id, acornOn and (shop.acorns or 0) > 0)
			end
		end)
		o.cards[crate.id] = { card = c, well = w, name = name, count = count, button = b }
	end
	o.reveal = make("Frame", { Name = "RevealPane", BackgroundTransparency = 1 }, v)
end

-- The reveal -----------------------------------------------------------------------------------------------------------

local function clear(f: Instance)
	for _, c in ipairs(f:GetChildren()) do
		c:Destroy()
	end
end

local function typeLine(d: any): string
	local kind = string.upper(d.type or "")
	if d.weapon then
		kind ..= " · " .. string.upper(Rewards.weaponName(d.weapon))
	end
	return string.upper(d.grade or "") .. (if kind ~= "" then " · " .. kind else "")
end

local function footLine(d: any): string
	local parts = {}
	if d.rolls and #d.rolls == 2 then
		table.insert(parts, string.format("%s: %s and %s, kept %s.", if d.lucky then "Lucky Charm, rolled twice" else "Rolled twice with a Lucky Acorn",
			d.rolls[1], d.rolls[2], d.grade))
	end
	if d.pity == "Fabled" then
		table.insert(parts, "A Fabled item was certain on this crate (pity).")
	elseif d.pity then
		table.insert(parts, string.format("%s or better was certain on this crate (pity).", d.pity))
	end
	if d.serial and d.serial > 0 then
		table.insert(parts, string.format("Numbered #%04d.", d.serial))
	end
	if d.duplicate then
		table.insert(parts, string.format("You own every %s item already: %s Gold back instead.", d.grade, comma(d.goldBack or 0)))
	end
	return table.concat(parts, "  ")
end

-- one item's big reveal inside `pane` (width w). animate: the crate's lid lifts first.
local function revealOne(pane: Frame, d: any, crateId: string?, animate: boolean, w: number, token: number, h: number?)
	clear(pane)
	local item = d.id and Crates.item(d.id) or { id = d.id or "gold", grade = d.grade, type = d.type, tint = SUN }
	local col = Crates.GradeColor[d.grade] or INK2
	local labelCol = Crates.GradeLabel[d.grade] or INK2
	local crateName = crateId and Crates.ById[crateId] and Crates.ById[crateId].name or (if crateId == "shelf" then "The Shelf" else "")
	-- the grade washing the background softly (no rays, no confetti)
	local wash = make("Frame", { Name = "Wash", BackgroundColor3 = col, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), ZIndex = 0 }, pane)
	corner(wash, 10)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 0.9),
		NumberSequenceKeypoint.new(1, 1) }), Rotation = 90 }, wash)
	local tileSize = math.clamp(math.floor(math.min(w * 0.62, (h or 520) - 260)), 96, 300)
	if phone then
		tileSize = math.clamp(math.floor(w * 0.42), 96, 150)
	end
	local head = label(pane, { Name = "Head", Text = string.upper(crateName) .. (if crateId == "shelf" then " · BOUGHT" else " · OPENED"),
		Font = "SemiBold", TextSize = 15, TextColor3 = labelCol, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 4) })
	local tileX = if phone then 8 else math.floor((w - tileSize) / 2)
	local tileY = 34
	local tile = make("Frame", { Name = "Tile", BackgroundColor3 = K.Card, BackgroundTransparency = K.CardT, BorderSizePixel = 0,
		Size = UDim2.fromOffset(tileSize, tileSize), Position = UDim2.fromOffset(tileX, tileY) }, pane)
	corner(tile, 8)
	local tileEdge = edge(tile, INK, 1.5, K.StrokeT)
	local tw = well(tile, { Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5) })
	local bar = make("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.new(0, 0, 0, 4), Position = UDim2.new(0, 5, 1, -9) }, tile)
	local textX = if phone then tileX + tileSize + 14 else 0
	local textW = if phone then w - textX - 8 else w
	local y = if phone then tileY else tileY + tileSize + 14
	local align = if phone then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	local new = label(pane, { Name = "New", Text = if d.duplicate then "ALREADY YOURS" else "NEW", Font = "SemiBold", TextSize = 14,
		TextColor3 = if d.duplicate then INK2 else SUN, TextXAlignment = align, Position = UDim2.fromOffset(textX, y), Size = UDim2.fromOffset(textW, 18),
		TextTransparency = 1 })
	local nameSize = if phone then 28 else 46
	local name = label(pane, { Name = "ItemName", Text = d.name or "", Font = "Light", TextSize = nameSize, TextXAlignment = align,
		Position = UDim2.fromOffset(textX, y + 18), Size = UDim2.fromOffset(textW, nameSize + 8), TextTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd })
	local kind = label(pane, { Name = "Kind", Text = typeLine(d), Font = "SemiBold", TextSize = 14, TextColor3 = labelCol, TextXAlignment = align,
		Position = UDim2.fromOffset(textX, y + nameSize + 28), Size = UDim2.fromOffset(textW, 18), TextTransparency = 1 })
	local look = label(pane, { Name = "Look", Text = d.look or "", TextSize = 15, TextWrapped = true, TextXAlignment = align,
		Position = UDim2.fromOffset(textX, y + nameSize + 50), Size = UDim2.fromOffset(textW, 40), TextTransparency = 1,
		TextYAlignment = Enum.TextYAlignment.Top })
	local by = y + nameSize + 96
	local preview = button(pane, "secondary", "PREVIEW", { Name = "Preview", TextSize = 15, Visible = false })
	local equipText = "EQUIP"
	if d.type == "Skin" and d.weapon then
		equipText = "EQUIP ON " .. string.upper(Rewards.weaponName(d.weapon))
	end
	local equipB = button(pane, "primary", equipText, { Name = "Equip", TextSize = 15, Visible = false })
	local pw, ew = 120, math.max(150, 12 * #equipText + 24)
	if phone then
		preview.Position = UDim2.fromOffset(textX, by)
		preview.Size = UDim2.fromOffset(110, 40)
		equipB.Position = UDim2.fromOffset(textX + 120, by)
		equipB.Size = UDim2.fromOffset(math.min(ew, textW - 120), 40)
	else
		local total = pw + 14 + ew
		preview.Position = UDim2.fromOffset(math.floor((w - total) / 2), by)
		preview.Size = UDim2.fromOffset(pw, 44)
		equipB.Position = UDim2.fromOffset(math.floor((w - total) / 2) + pw + 14, by)
		equipB.Size = UDim2.fromOffset(ew, 44)
	end
	local foot = label(pane, { Name = "Foot", Text = footLine(d), TextSize = 13, TextColor3 = INK2, TextWrapped = true, TextXAlignment = align,
		Position = UDim2.fromOffset(textX, by + 52), Size = UDim2.fromOffset(textW, 34), TextYAlignment = Enum.TextYAlignment.Top,
		TextTransparency = 1 })
	equipB.Activated:Connect(function()
		if d.id and not d.duplicate then
			sendShop("equip", d.id)
			setKind(equipB, "off")
			equipB.Text = "EQUIPPED"
		end
	end)
	local spinning = false
	preview.Activated:Connect(function()
		spinning = not spinning
		preview.Text = if spinning then "STOP" else "PREVIEW"
	end)

	-- 1. the crate in the well, its lid lifting
	if animate and crateId and Crates.ById[crateId] then
		local vf, model = crateView(tw, crateId)
		local lid = model:FindFirstChild("Lid") :: Model?
		local hinge = lid and lid:GetAttribute("Hinge")
		if lid and typeof(hinge) == "CFrame" then
			local rest = lid:GetPivot()
			sound("Launch_Seal", 0.5, 1.15)
			local t0 = os.clock()
			while os.clock() - t0 < 0.55 and revealToken == token do
				local u = math.min(1, (os.clock() - t0) / 0.55)
				local e = 1 - (1 - u) ^ 3
				lid:PivotTo(hinge * CFrame.Angles(math.rad(-100 * e), 0, 0) * hinge:Inverse() * rest)
				RunService.RenderStepped:Wait()
			end
		end
		task.wait(0.15)
		TweenService:Create(vf, TweenInfo.new(0.25), { ImageTransparency = 1 }):Play()
		task.wait(0.22)
		vf:Destroy()
	end
	if revealToken ~= token then
		return
	end
	-- 2. the item rises in its tile
	local holder = make("Frame", { Name = "Holder", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0.25) }, tw)
	local pic = itemPicture(holder, item)
	if d.duplicate then
		clear(holder)
		icon("coin", holder, { Size = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	end
	TweenService:Create(holder, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0, 0) }):Play()
	TweenService:Create(wash, TweenInfo.new(0.6), { BackgroundTransparency = 0.82 }):Play()
	TweenService:Create(tileEdge, TweenInfo.new(0.4), { Color = col, Transparency = 0.1 }):Play()
	TweenService:Create(bar, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(1, -10, 0, 4) }):Play()
	local rank = Crates.GradeRank[d.grade] or 1
	if d.duplicate then
		sound("PickUp", 0.6)
	elseif rank >= 5 then
		sound("FeastBell", 0.55)
	elseif rank >= 4 then
		sound("Notify", 0.6, 0.8)
	else
		sound("UIOpen", 0.5, 1.0)
	end
	task.wait(0.25)
	for i, l in ipairs({ new, name, kind, look, foot }) do
		TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		if i == 2 then
			task.wait(0.08)
		end
	end
	preview.Visible = not d.duplicate and d.id ~= nil
	equipB.Visible = not d.duplicate and d.id ~= nil
	if equipB.Visible and (shop.equipped or {})[d.type == "Skin" and d.weapon and ("skin:" .. d.weapon) or d.type] == d.id then
		setKind(equipB, "off")
		equipB.Text = "EQUIPPED"
	end
	if equipB.Visible and UserInputService.GamepadEnabled then
		GuiService.SelectedObject = equipB
	end
	-- PREVIEW: a slow turn of the picture (kill effects play on a mannequin once the cosmetics agent's VFX exist)
	task.spawn(function()
		local a = 0
		while pane.Parent and holder.Parent do
			local dt = RunService.RenderStepped:Wait()
			if spinning and pic and pic:IsA("ViewportFrame") then
				a += dt * 40
				local cam = (pic :: ViewportFrame).CurrentCamera
				local model = pic:FindFirstChildWhichIsA("Model")
				if cam and model then
					local cf = model:GetPivot()
					model:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, math.rad(dt * 40), 0) * cf.Rotation)
				end
			elseif spinning and pic then
				pic.Rotation = math.sin(a) * 6
				a += dt * 3
			end
		end
	end)
end

-- several crates: their tiles in a grid (best last), then the best one large
local function revealMany(pane: Frame, result: any, w: number, token: number, h: number?)
	clear(pane)
	local list = result.results
	local n = #list
	local cell = if phone then 54 else 84
	local per = math.max(1, math.floor((w + 10) / (cell + 10)))
	local grid = make("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, math.ceil(n / per) * (cell + 10)) }, pane)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(cell, cell), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center }, grid)
	local detail = make("Frame", { Name = "Detail", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, grid.Size.Y.Offset + 6),
		Size = UDim2.new(1, 0, 1, -(grid.Size.Y.Offset + 6)) }, pane)
	for i, d in ipairs(list) do
		if revealToken ~= token then
			return
		end
		local item = d.id and Crates.item(d.id) or { id = "gold" .. i, grade = d.grade, type = "" }
		local t = gradeTile(grid, item, cell, { LayoutOrder = i })
		local b = make("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Selectable = true, ZIndex = 5 }, t)
		if d.duplicate then
			local w0 = t:FindFirstChild("Well")
			if w0 then
				clear(w0)
				icon("coin", w0, { Size = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			end
		end
		b.Activated:Connect(function()
			revealToken += 1
			task.spawn(revealOne, detail, d, result.crate, false, w, revealToken, (h or 520) - grid.Size.Y.Offset - 6)
		end)
		sound("UIClick", 0.35, 0.8 + (Crates.GradeRank[d.grade] or 1) * 0.08)
		task.wait(if i == n then 0.35 else 0.12)
	end
	revealOne(detail, list[n], result.crate, false, w, token, (h or 520) - grid.Size.Y.Offset - 6)
end

-- Odds details and the Shelf (overlays) ------------------------------------------------------------------------------

local function overlay(name: string, title: string): (Frame, Frame)
	local o = ui.panel:FindFirstChild(name)
	if o then
		o:Destroy()
	end
	local shade = make("TextButton", { Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = SHADE, BackgroundTransparency = 0.35,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 20, Selectable = false }, ui.panel)
	corner(shade, 12)
	local sheet = panelFrame("Sheet", shade, "panel")
	sheet.BackgroundTransparency = 0.04
	sheet.ZIndex = 21
	sheet.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.Position = UDim2.fromScale(0.5, 0.5)
	sheet.Size = if phone then UDim2.new(1, -16, 1, -16) else UDim2.new(0, 760, 1, -60)
	label(sheet, { Text = title, Font = "SemiBold", TextSize = 18, Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -90, 0, 28), ZIndex = 22 })
	local close = button(sheet, "secondary", "", { Name = "Close", Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6), ZIndex = 22 })
	icon("close", close, { Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 23 })
	close.Activated:Connect(function()
		shade:Destroy()
		ui.overlay = nil
	end)
	ui.overlay = shade
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = close
	end
	local body = make("ScrollingFrame", { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageTransparency = 0.5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(20, 56),
		Size = UDim2.new(1, -40, 1, -70), ZIndex = 22, Selectable = false }, sheet)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	return shade, body
end

function ShopController.showDetails()
	local e = ENTRY[current]
	local _, body = overlay("Details", "ODDS DETAILS · " .. string.upper(entryName(e)))
	local order = 0
	local function row(text: string, right: string?, color: Color3?, font: string?)
		order += 1
		local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 24), LayoutOrder = order, ZIndex = 22 }, body)
		label(f, { Text = text, TextColor3 = color or INK, Font = font or "Medium", TextSize = 15, Size = UDim2.new(1, -110, 1, 0), ZIndex = 22,
			RichText = true, TextTruncate = Enum.TextTruncate.AtEnd })
		if right then
			label(f, { Text = right, Font = "Mono", TextSize = 15, TextColor3 = color or INK, TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0, 100, 1, 0), Position = UDim2.new(1, -100, 0, 0), ZIndex = 22 })
		end
	end
	if e.kind == "crate" then
		local crate = Crates.ById[e.id]
		local useAcorn = acornOn and (shop.acorns or 0) > 0
		row(string.format("Your own odds for one %s%s. Items you own are never drawn.", crate.name,
			if useAcorn then ", with a Lucky Acorn" else ""), nil, INK2)
		for _, g in ipairs(Crates.playerOdds(crate, shop.owned, useAcorn)) do
			row(string.upper(g.grade), Crates.fmt(g.pct), Crates.GradeLabel[g.grade], "SemiBold")
			if g.full then
				row("    You own every " .. g.grade .. " item: " .. comma(g.goldBack) .. " Gold back", Crates.fmt(g.pct), INK2)
			end
			for _, it in ipairs(g.items) do
				local item = Crates.item(it.id)
				local text = "    " .. item.name .. "  <font color=\"#BDB8AC\">" .. item.type
					.. (if item.weapon then " · " .. Rewards.weaponName(item.weapon) else "") .. "</font>"
				if g.grade == "Fabled" then
					row(text .. "  <font color=\"#BDB8AC\">plain</font>", Crates.fmt(it.pct * (1 - Crates.NumberedChance)), INK)
					row(text .. "  <font color=\"#BDB8AC\">Numbered</font>", Crates.fmt(it.pct * Crates.NumberedChance), INK)
				else
					row(text, Crates.fmt(it.pct), INK)
				end
			end
		end
		row("Total", "100%", INK2)
		row("Item shares are rounded to 0.01%: the items of a grade share its odds equally.", nil, INK2)
	elseif e.kind == "box" or e.id == "wheel" then
		local rows = if e.id == "wheel" then {} else Rewards.BoxOdds[e.id]
		if e.id == "wheel" then
			local paid = (rew.freeLeft or 0) <= 0
			for _, oc in ipairs(Rewards.WheelOutcomes) do
				if oc.kind == "gold" then
					row(string.format("%s Gold", comma(Rewards.wheelGold(oc, paid))), Crates.fmt(oc.chance), INK, "SemiBold")
				else
					row(starText(oc.stars) .. " weapon", Crates.fmt(oc.chance), if oc.stars >= 4 then SUN else INK, "SemiBold")
					for _, id in ipairs(Rewards.Pool) do
						row("    " .. Rewards.weaponName(id), Crates.fmt(oc.chance / #Rewards.Pool), INK2)
					end
				end
			end
		else
			for _, r in ipairs(rows) do
				row(starText(r[1]), Crates.fmt(r[2]), if r[1] >= 4 then SUN else INK, "SemiBold")
				for _, id in ipairs(Rewards.Pool) do
					row("    " .. Rewards.weaponName(id), Crates.fmt(r[2] / #Rewards.Pool), INK2)
				end
			end
		end
		row("Each weapon is equally likely within a star count; ones you hold at that star or better are drawn last.", nil, INK2)
		row("Total", "100%", INK2)
	else
		row("The Armoury has no chance: you choose the weapon and its stars.", nil, INK2)
	end
end

function ShopController.showShelf()
	local _, body = overlay("ShelfSheet", "THE SHELF · TODAY")
	make("UIListLayout", { Padding = UDim.new(0, 4) }, body):Destroy()
	local list = body:FindFirstChildOfClass("UIListLayout")
	if list then
		list:Destroy()
	end
	local cell = if phone then 150 else 220
	make("UIGridLayout", { CellSize = UDim2.fromOffset(cell, cell + 70), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	for i, id in ipairs(shop.shelf or {}) do
		local item = Crates.item(id)
		if item then
			local f = make("Frame", { BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 22 }, body)
			gradeTile(f, item, cell)
			label(f, { Text = item.name, Font = "SemiBold", TextSize = 15, Position = UDim2.fromOffset(0, cell + 4), Size = UDim2.new(1, 0, 0, 20),
				ZIndex = 22, TextTruncate = Enum.TextTruncate.AtEnd })
			local price = Crates.shelfPrice(item.grade)
			local b = button(f, if gold() >= price then "primary" else "off", "BUY · " .. comma(price), { Position = UDim2.fromOffset(0, cell + 28),
				Size = UDim2.new(1, 0, 0, 38), ZIndex = 22, TextSize = 14 })
			holdButton(b, function()
				sendShop("shelf", id)
			end)
		end
	end
	if #(shop.shelf or {}) == 0 then
		label(body, { Text = "You own everything the Shelf shows today. It changes at 00:00 UTC.", TextColor3 = INK2, Size = UDim2.new(1, 0, 0, 30), ZIndex = 22 })
	end
end

-- Refresh (fills every card from the state) ------------------------------------------------------------------------

local function pityLines(crate: any): { string }
	local out = {}
	local left = (shop.pity or {})[crate.id] or Crates.pityLeft(crate, nil)
	local function within(n: number): string
		return if n <= 1 then "on your next " .. crate.name else string.format("within %d more %ss", n, crate.name)
	end
	if crate.pity.storied and left.storied then
		table.insert(out, string.format("<font color=\"#F4F1EA\">Storied or better %s</font> (certain by the %dth without one).",
			within(left.storied), crate.pity.storied))
	end
	if crate.pity.fabled and left.fabled then
		table.insert(out, string.format("<font color=\"#F4F1EA\">Fabled %s</font> (certain by the %dth without one).",
			within(left.fabled), crate.pity.fabled))
	end
	if #out == 0 then
		table.insert(out, "No pity counter on this crate: each one is rolled on its own.")
	end
	return out
end

local function refreshCrate(e: any, b: any, o: any)
	local crate = Crates.ById[e.id]
	local useAcorn = acornOn and (shop.acorns or 0) > 0
	b.name.Text = crate.name
	b.line.Text = crate.line
	local max = shop.maxQuantity or 10
	quantity = math.clamp(quantity, 1, max)
	b.qty.Text = tostring(quantity)
	b.price.Text = comma(crate.gold * quantity)
	local restricted = shop.restricted == true
	b.action.Visible = not restricted
	b.note.Visible = restricted
	-- restricted: no stepper and no price, one line in their place (OPEN and the Shelf stay)
	for _, g in ipairs({ b.qtyLabel, b.minus, b.qty, b.plus, b.priceLabel, b.price, b.coin }) do
		if g then
			g.Visible = not restricted
		end
	end
	b.note.Text = if restricted then "Not available in your region · earn crates from the daily reward and the Season Track" else ""
	b.action.Text = "BUY"
	setKind(b.action, if gold() >= crate.gold * quantity then "primary" else "off")
	-- odds
	o.title.Text = "ODDS · ONE ITEM PER CRATE"
	o.headGrade.Text = "Grade"
	local boosted = Crates.acornOdds(crate)
	local rows = {}
	for i, r in ipairs(crate.odds) do
		table.insert(rows, { name = r[1], color = Crates.GradeLabel[r[1]], bar = Crates.GradeColor[r[1]], pct = r[2], acornPct = boosted[i][2] })
	end
	local width = o.card.Size.X.Offset - (if phone then 20 else 48)
	local h = setOddsRows(rows, true, if phone then 22 else 40, width)
	o.headAcorn.TextColor3 = if useAcorn then SUN else INK2
	-- notes: each player's own facts
	local fabled = 0
	for _, r in ipairs(if useAcorn then boosted else crate.odds) do
		if r[1] == "Fabled" then
			fabled = r[2]
		end
	end
	local lines = { "Every item of a grade is equally likely. You only draw items you do not own yet." }
	for _, l in ipairs(pityLines(crate)) do
		table.insert(lines, l)
	end
	if fabled > 0 then
		table.insert(lines, string.format("A Fabled item has a 1 in 10 chance to be <font color=\"#F4F1EA\"><b>Numbered</b></font> (#0001 on Inspect): %s now.",
			Crates.fmt(fabled * Crates.NumberedChance)))
	end
	local full = {}
	for _, g in ipairs(Crates.playerOdds(crate, shop.owned, false)) do
		if g.full then
			table.insert(full, string.format("%s gives %s Gold back", g.grade, comma(g.goldBack)))
		end
	end
	table.insert(lines, "Own the whole grade already? You get Gold back instead (Plain 30% … Fabled 150% of the price)."
		.. (if #full > 0 then " <font color=\"#E8B65A\">You own every item of a grade: " .. table.concat(full, ", ") .. ".</font>" else ""))
	if shop.robux and shop.robux.luckOwned then
		local nextIn = shop.robux.luckNext or 3
		table.insert(lines, if nextIn <= 1 then "<font color=\"#E8B65A\">Lucky Charm: your next crate is lucky (it rolls twice).</font>"
			else string.format("Lucky Charm: every 3rd crate rolls twice · the next lucky one in %d.", nextIn))
	end
	if useAcorn then
		table.insert(lines, string.format("<font color=\"#E8B65A\">A Lucky Acorn will be used on %s.</font> Pity still counts each crate once.",
			if quantity > 1 then "each crate while charges last (" .. (shop.acorns or 0) .. ")" else "this crate"))
	end
	o.notesText.Text = table.concat(lines, "\n")
	return h
end

local function refreshWeapons(e: any, b: any, o: any)
	local cfg = Rewards.config()
	local pity = rew.pity or {}
	quantity = 1
	b.qty.Text = "1"
	b.note.Visible = false
	b.action.Visible = true
	local lines = {}
	local rows = {}
	if e.id == "wheel" then
		b.name.Text = "Prize Wheel"
		local free = (rew.freeLeft or 0) > 0
		b.line.Text = "Spin it at the wheel in the Lounge car, where the car can watch. Every segment pays Gold or a weapon."
		b.price.Text = if free then "free today" else comma(rew.spinCost or cfg.Wheel.SpinCost)
		b.action.Text = "GO TO THE WHEEL"
		setKind(b.action, "secondary")
		o.title.Text = "ODDS · THE WHEEL"
		o.headGrade.Text = "Prize"
		for _, oc in ipairs(Rewards.WheelOutcomes) do
			if oc.kind == "gold" then
				table.insert(rows, { name = comma(Rewards.wheelGold(oc, not free)) .. " Gold", color = INK, bar = SUN, pct = oc.chance })
			else
				table.insert(rows, { name = starText(oc.stars) .. " weapon", color = if oc.stars >= 4 then SUN else INK, bar = INK, pct = oc.chance })
			end
		end
		table.insert(lines, string.format("<font color=\"#F4F1EA\">A ★★★★ weapon or better within %d spins.</font>", pity.wheel4 or cfg.Wheel.Pity4))
		table.insert(lines, if free then "Your free spin today is waiting." else string.format("A spin is %s Gold; a paid spin's Gold segments pay at least the stake.", comma(rew.spinCost or cfg.Wheel.SpinCost)))
		if rew.paidBlocked then
			table.insert(lines, "Paid spins are not available on this account · the free spin comes back each day.")
		end
	else
		local master = e.id == "masterwork"
		b.name.Text = if master then "Masterwork Strongbox" else "Strongbox"
		b.line.Text = if master then "One weapon at 4★ or 5★, kept in your Armoury. Never the Recurve Bow."
			else "One weapon at 3★ to 5★, kept in your Armoury. Never the Recurve Bow."
		local cost = if master then cfg.Strongbox.MasterworkCost else cfg.Strongbox.Cost
		b.price.Text = comma(cost)
		b.action.Text = "BUY"
		setKind(b.action, if gold() >= cost then "primary" else "off")
		if rew.paidBlocked then
			b.action.Visible = false
			b.note.Visible = true
			b.note.Text = "Not available in your region · the Armoury sells every weapon"
		end
		o.title.Text = "ODDS · STARS"
		o.headGrade.Text = "Stars"
		for _, r in ipairs(Rewards.BoxOdds[e.id]) do
			table.insert(rows, { name = starText(r[1]), color = if r[1] >= 4 then SUN else INK, bar = INK, pct = r[2] })
		end
		table.insert(lines, string.format("Each of the %d weapons is equally likely within a star count.", #Rewards.Pool))
		table.insert(lines, string.format("<font color=\"#F4F1EA\">4★ or better within %d more boxes · 5★ within %d more boxes</font> (both Strongbox kinds count).",
			pity.box4 or cfg.Strongbox.Pity4, pity.box5 or cfg.Strongbox.Pity5))
		local dg = cfg.Strongbox.DuplicateGold
		table.insert(lines, string.format("Same or lower star than you own: Gold back (3★ %s, 4★ %s, 5★ %s; a paid box never less than its price). Higher: it replaces yours.",
			comma(dg[3]), comma(dg[4]), comma(dg[5])))
		table.insert(lines, string.format("Lucky Acorns do not work on weapons. Want a sure thing? The Armoury sells any 3★ for %s.", comma(cfg.Armoury.Buy3)))
		table.insert(lines, "The box opens at the steel case in the train: the screen steps aside so you can watch.")
	end
	local width = o.card.Size.X.Offset - (if phone then 20 else 48)
	local h = setOddsRows(rows, false, if phone then 22 else 40, width)
	o.notesText.Text = table.concat(lines, "\n")
	return h
end

local function refreshArmoury(e: any, b: any, o: any)
	local cfg = Rewards.config()
	local owned = (rew.armoury or {})[armourySel] or 0
	b.name.Text = Rewards.weaponName(armourySel) .. (if owned > 0 then "  " .. starText(owned) else "")
	b.line.Text = if owned > 0 then "In your Armoury. Bring it into a round with your kit." else "Not in your Armoury yet."
	quantity = 1
	b.qty.Text = "1"
	b.note.Visible = false
	b.action.Visible = true
	local cost, text
	if owned < 3 then
		cost, text = cfg.Armoury.Buy3, "BUY 3★"
	elseif owned == 3 then
		cost, text = cfg.Armoury.Raise4, "RAISE TO 4★"
	elseif owned == 4 then
		cost, text = cfg.Armoury.Raise5, "RAISE TO 5★"
	end
	if cost then
		b.price.Text = comma(cost)
		b.action.Text = text
		setKind(b.action, if gold() >= cost then "primary" else "off")
	else
		b.price.Text = "—"
		b.action.Text = "HIGHEST STARS"
		setKind(b.action, "off")
	end
	o.title.Text = "THE ARMOURY · NO CHANCE"
	o.headGrade.Text = "Step"
	local rows = {
		{ name = "Buy any 3★", color = INK, bar = INK, pct = 0 },
	}
	for _, r in ipairs(o.rows) do
		r:Destroy()
	end
	o.rows = {}
	o.headAcorn.Visible = false
	local lines = {
		string.format("<font color=\"#F4F1EA\">Buy any pool weapon at 3★: %s Gold.</font>", comma(cfg.Armoury.Buy3)),
		string.format("<font color=\"#F4F1EA\">Raise 3★ → 4★: %s Gold.  4★ → 5★: %s Gold.</font>", comma(cfg.Armoury.Raise4), comma(cfg.Armoury.Raise5)),
		"Choose a weapon in Your Armoury. Nothing here is random: you pick the weapon and its stars.",
		if rew.bring and rew.bring ~= "" then string.format("You bring your %s %s next round · it comes with your kit.",
			Rewards.weaponName(rew.bring), starText((rew.armoury or {})[rew.bring] or 0)) else "Pick a weapon you own and BRING it next round.",
	}
	o.notesText.Text = table.concat(lines, "\n")
	local _ = rows
	return 0
end

local function refreshSide()
	for _, e in ipairs(ENTRIES) do
		local r = ui.sideRows[e.id]
		local selected = e.id == current
		local price, isGold = entryPrice(e)
		r.price.Text = price
		if r.coin then
			r.coin.Visible = isGold
		end
		r.price.Position = UDim2.fromOffset(if isGold then 16 else 0, 0)
		edge(r.row, INK, if selected then 2.5 else 1.5, if selected then 0.05 else K.StrokeT)
		local held = (shop.held or {})[e.id] or 0
		r.count.Visible = held > 0
		r.count.Text = "×" .. held
	end
end

refresh = function()
	if not ui.panel then
		return
	end
	layout()
	ui.gold.Text = comma(gold())
	local badge = heldTotal()
	ui.badge.Visible = badge > 0
	ui.badgeText.Text = tostring(badge)
	setKind(ui.tabBuy, if tab == "buy" then "secondary" else "plain")
	setKind(ui.tabOpen, if tab == "open" then "secondary" else "plain")
	ui.buyView.Visible = tab == "buy"
	ui.open.view.Visible = tab == "open"
	ui.shelfHeader.Visible = phone and tab == "buy" and ENTRY[current].kind == "crate"
	refreshSide()
	local e = ENTRY[current]
	local b, o = ui.buy, ui.odds
	-- the box picture
	if b.shown ~= current .. (if e.kind == "armoury" then armourySel else "") then
		b.shown = current .. (if e.kind == "armoury" then armourySel else "")
		clear(b.well)
		local soft = make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.1) }), Color = ColorSequence.new(Color3.fromRGB(40, 44, 50), K.Well), Rotation = 90 }, b.well)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, b.well)
		local _ = soft
		if e.kind == "armoury" then
			weaponView(b.well, armourySel)
		else
			entryPicture(e, b.well)
		end
	end
	local isCrate = e.kind == "crate"
	b.action:SetAttribute("NoHold", e.id == "wheel")
	b.qtyLabel.Visible = e.kind ~= "armoury" and e.id ~= "wheel"
	b.minus.Visible, b.plus.Visible, b.qty.Visible = b.qtyLabel.Visible, b.qtyLabel.Visible, b.qtyLabel.Visible
	b.priceLabel.Visible, b.price.Visible = true, true
	if b.coin then
		b.coin.Visible = true
	end
	setKind(b.minus, if isCrate and quantity > 1 then "secondary" else "off")
	setKind(b.plus, if isCrate and quantity < (shop.maxQuantity or 10) then "secondary" else "off")
	if isCrate then
		refreshCrate(e, b, o)
	elseif e.kind == "armoury" then
		refreshArmoury(e, b, o)
	else
		refreshWeapons(e, b, o)
	end
	o.details.Visible = e.kind ~= "armoury"
	o.headNow.Visible = e.kind ~= "armoury"
	o.headGrade.Visible = e.kind ~= "armoury"
	-- the Acorn
	local acorns = shop.acorns or 0
	if acorns <= 0 then
		acornOn = false
	end
	local function paintSwitch(sw: Frame, knob: Frame)
		sw.BackgroundColor3 = if acornOn then SUN else INK
		sw.BackgroundTransparency = if acornOn then 0 else 0.8
		knob.BackgroundColor3 = if acornOn then SHADE else INK
		knob.Position = UDim2.fromOffset(if acornOn then sw.Size.X.Offset - knob.Size.X.Offset - 3 else 3, 3)
	end
	paintSwitch(ui.luck.switch, ui.luck.knob)
	paintSwitch(b.acornSwitch, b.acornKnob)
	ui.luck.count.Text = string.format("You have <b>%d</b> charge%s", acorns, if acorns == 1 then "" else "s")
	b.acornText.Text = string.format("Use a Lucky Acorn (%d)", acorns)
	b.acornRow.Visible = phone and isCrate
	ui.luck.charm.Visible = shop.robux and shop.robux.luck == true and not shop.robux.luckOwned or false
	-- right column
	ui.luck.card.Visible = not phone and isCrate
	ui.shelf.card.Visible = not phone and isCrate
	ui.arm.card.Visible = (not phone and not isCrate) or (phone and e.kind == "armoury")
	o.card.Visible = not (phone and e.kind == "armoury")
	-- shelf preview tiles
	local key = table.concat(shop.shelf or {}, ",")
	if ui.shelf.key ~= key then
		ui.shelf.key = key
		for _, c in ipairs(ui.shelf.tiles:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, id in ipairs(shop.shelf or {}) do
			if i <= 3 then
				local item = Crates.item(id)
				if item then
					gradeTile(ui.shelf.tiles, item, 92, { LayoutOrder = i })
				end
			end
		end
	end
	-- armoury tiles
	for id, t in pairs(ui.arm.tiles) do
		local owned = (rew.armoury or {})[id] or 0
		t.stars.Text = if owned > 0 then starText(owned) else ""
		t.stars.TextColor3 = if owned >= 4 then SUN else INK
		if t.lock then
			t.lock.Visible = owned <= 0
		end
		if t.view then
			t.view.ImageTransparency = if owned > 0 then 0 else 0.68
		end
		t.bring.Visible = rew.bring == id
		edge(t.button, INK, if e.kind == "armoury" and id == armourySel then 2.5 else 1.5,
			if e.kind == "armoury" and id == armourySel then 0.05 else K.StrokeT)
	end
	ui.arm.open.Visible = e.kind ~= "armoury"
	local selOwned = (rew.armoury or {})[armourySel] or 0
	ui.arm.bringBtn.Visible = e.kind == "armoury" and selOwned > 0
	ui.arm.bringBtn.Text = if rew.bring == armourySel then "LEAVE IT HOME" else "BRING IT NEXT ROUND"
	-- open tab
	for id, c in pairs(ui.open.cards) do
		local n = (shop.held or {})[id] or 0
		c.count.Text = "× " .. n
		c.button.Text = if n > 0 then "OPEN" else "NONE LEFT"
		setKind(c.button, if n > 0 then "primary" else "off")
		for _, d in ipairs(c.well:GetChildren()) do
			if d:IsA("ViewportFrame") then
				d.ImageTransparency = if n > 0 then 0 else 0.6
			end
		end
		c.name.TextTransparency = if n > 0 then 0 else 0.45
	end
	ui.open.acorn.Visible = acorns > 0
	ui.open.acornText.Text = string.format("%s  Use a Lucky Acorn when opening <font color=\"#BDB8AC\">(%d left · rolls twice, keeps the better grade)</font>",
		if acornOn then "<font color=\"#E8B65A\">●</font>" else "○", acorns)
	layout()
end

-- Layout --------------------------------------------------------------------------------------------------------------

layout = function()
	if not ui.panel then
		return
	end
	local s = ui.scale()
	local rootSize = ui.root.AbsoluteSize / s
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	phone = math.min(viewport.X, viewport.Y) <= 500
	-- Studio only: a phone-sized preview (812 x 375, inside its 8 px safe padding) on a desktop screen, for QA
	local preview = ui.phonePreview == true and RunService:IsStudio()
	if preview then
		phone = true
		rootSize = Vector2.new(812 - 16, 375 - 16) * (1 / s) * s
	end
	if ui.phoneFrame then
		ui.phoneFrame.Visible = preview
		ui.phoneFrame.Size = UDim2.fromOffset(812, 375)
	end
	local W = if phone then rootSize.X else math.min(1200, rootSize.X - 20)
	local H = if phone then rootSize.Y else math.min(660, rootSize.Y - 20)
	ui.panel.Size = UDim2.fromOffset(W, H)
	local headH = if phone then 46 else 70
	local pad = if phone then 8 else 24
	-- header
	ui.title.Position = UDim2.fromOffset(pad, 0)
	ui.title.Size = UDim2.fromOffset(if phone then 90 else 150, headH)
	ui.title.TextSize = if phone then 24 else 38
	local tx = pad + (if phone then 92 else 160)
	local tabW, tabH = if phone then 70 else 92, if phone then 36 else 44
	ui.tabBuy.Position = UDim2.fromOffset(tx, (headH - tabH) / 2)
	ui.tabBuy.Size = UDim2.fromOffset(tabW, tabH)
	ui.tabOpen.Position = UDim2.fromOffset(tx + tabW + 10, (headH - tabH) / 2)
	ui.tabOpen.Size = UDim2.fromOffset(tabW, tabH)
	ui.close.Size = UDim2.fromOffset(44, 44)
	ui.close.Position = UDim2.new(1, -pad - 44 + (if phone then 0 else 8), 0, (headH - 44) / 2)
	ui.goldRow.Position = UDim2.new(1, -pad - 44 - 150, 0, 0)
	ui.goldRow.Size = UDim2.fromOffset(140, headH)
	ui.shelfHeader.Position = UDim2.new(1, -pad - 44 - 150 - 92, 0, (headH - 36) / 2)
	ui.shelfHeader.Size = UDim2.fromOffset(84, 36)
	-- body
	local bodyY = headH + (if phone then 2 else 6)
	local bodyH = H - bodyY - (if phone then 6 else 20)
	ui.buyView.Position = UDim2.fromOffset(0, bodyY)
	ui.buyView.Size = UDim2.fromOffset(W, bodyH)
	ui.open.view.Position = UDim2.fromOffset(0, bodyY)
	ui.open.view.Size = UDim2.fromOffset(W, bodyH)
	ui.toast.Position = UDim2.new(0, pad, 1, if phone then -20 else -22)
	ui.toast.Size = UDim2.new(1, -pad * 2, 0, 18)
	local side = ui.side
	local b, o = ui.buy, ui.odds
	local rightW = 340
	local centerX, centerW, contentY, contentH
	if phone then
		-- the side list as a strip of 64 px tiles across the top
		side.Position = UDim2.fromOffset(pad, 0)
		side.Size = UDim2.fromOffset(W - pad * 2, 62)
		side.ScrollingDirection = Enum.ScrollingDirection.X
		local x = 0
		for _, e in ipairs(ENTRIES) do
			local r = ui.sideRows[e.id]
			if ui.sideHeads[e.id] then
				ui.sideHeads[e.id].Visible = false
			end
			r.row.Position = UDim2.fromOffset(x, 0)
			r.row.Size = UDim2.fromOffset(124, 58)
			r.well.Position = UDim2.fromOffset(4, 4)
			r.well.Size = UDim2.fromOffset(40, 40)
			r.name.Position = UDim2.fromOffset(48, 4)
			r.name.Size = UDim2.fromOffset(74, 34)
			r.name.TextSize = 13
			r.name.TextWrapped = true
			r.name.Text = entryName(e):gsub(" Crate", ""):gsub(" Strongbox", " Box")
			r.priceRow.Position = UDim2.fromOffset(6, 44)
			r.priceRow.Size = UDim2.fromOffset(100, 14)
			r.count.Position = UDim2.new(1, -4, 0, 2)
			r.count.Size = UDim2.fromOffset(30, 14)
			x += 130
		end
		contentY, contentH = 64, bodyH - 66
		centerX, centerW = pad, math.floor((W - pad * 3) * 0.44)
		b.card.Position = UDim2.fromOffset(centerX, contentY)
		b.card.Size = UDim2.fromOffset(centerW, contentH)
		local ox = centerX + centerW + pad
		local ow = W - ox - pad
		o.card.Position = UDim2.fromOffset(ox, contentY)
		o.card.Size = UDim2.fromOffset(ow, contentH)
		ui.arm.card.Position = o.card.Position
		ui.arm.card.Size = o.card.Size
	else
		local sideW = 210
		side.Position = UDim2.fromOffset(pad, 0)
		side.Size = UDim2.fromOffset(sideW + 6, bodyH)
		side.ScrollingDirection = Enum.ScrollingDirection.Y
		local y = 0
		for _, e in ipairs(ENTRIES) do
			local r = ui.sideRows[e.id]
			local h = ui.sideHeads[e.id]
			if h then
				h.Visible = true
				h.Position = UDim2.fromOffset(4, y + (if y > 0 then 6 else 0))
				h.Size = UDim2.fromOffset(sideW, 18)
				y += if y > 0 then 28 else 22
			end
			r.row.Position = UDim2.fromOffset(0, y)
			r.row.Size = UDim2.fromOffset(sideW, 52)
			r.well.Position = UDim2.fromOffset(6, 6)
			r.well.Size = UDim2.fromOffset(44, 40)
			r.name.Position = UDim2.fromOffset(58, 6)
			r.name.Size = UDim2.fromOffset(sideW - 64, 22)
			r.name.Text = entryName(e)
			-- (hunt2_1) "Masterwork Strongbox" was cut to "Masterwork..." at 15: a long name is set a little smaller
			r.name.TextSize = if #r.name.Text > 17 then 13 else 15
			r.name.TextWrapped = false
			r.priceRow.Position = UDim2.fromOffset(58, 30)
			r.priceRow.Size = UDim2.fromOffset(sideW - 64, 16)
			r.count.Position = UDim2.new(1, -8, 0, 30)
			r.count.Size = UDim2.fromOffset(40, 16)
			y += 57
		end
		contentY, contentH = 0, bodyH
		centerX = pad + sideW + 16
		centerW = W - centerX - 16 - rightW - pad
		b.card.Position = UDim2.fromOffset(centerX, 0)
		b.card.Size = UDim2.fromOffset(centerW, 150)
		o.card.Position = UDim2.fromOffset(centerX, 162)
		o.card.Size = UDim2.fromOffset(centerW, bodyH - 162)
		local rx = W - pad - rightW
		ui.luck.card.Position = UDim2.fromOffset(rx, 0)
		ui.luck.card.Size = UDim2.fromOffset(rightW, 282)
		ui.shelf.card.Position = UDim2.fromOffset(rx, 294)
		ui.shelf.card.Size = UDim2.fromOffset(rightW, bodyH - 294)
		ui.arm.card.Position = UDim2.fromOffset(rx, 0)
		ui.arm.card.Size = UDim2.fromOffset(rightW, bodyH)
	end
	-- inside the buy card
	local bw = b.card.Size.X.Offset
	local bh = b.card.Size.Y.Offset
	if phone then
		b.well.Position = UDim2.fromOffset(10, 10)
		b.well.Size = UDim2.fromOffset(72, 64)
		b.name.Position = UDim2.fromOffset(90, 8)
		b.name.Size = UDim2.fromOffset(bw - 98, 24)
		b.name.TextSize = 17
		b.line.Position = UDim2.fromOffset(90, 32)
		b.line.Size = UDim2.fromOffset(bw - 98, 44)
		b.line.TextSize = 13
		-- phone: no small captions; every target 44 px
		local y = 80
		b.qtyLabel.Visible = false
		b.priceLabel.Visible = false
		b.minus.Position = UDim2.fromOffset(10, y)
		b.minus.Size = UDim2.fromOffset(44, 44)
		b.qty.Position = UDim2.fromOffset(58, y)
		b.qty.Size = UDim2.fromOffset(40, 44)
		b.plus.Position = UDim2.fromOffset(102, y)
		b.plus.Size = UDim2.fromOffset(44, 44)
		if b.coin then
			b.coin.Position = UDim2.fromOffset(160, y + 14)
		end
		b.price.Position = UDim2.fromOffset(180, y)
		b.price.Size = UDim2.fromOffset(math.max(40, bw - 186), 44)
		b.price.TextSize = 18
		b.acornRow.Position = UDim2.fromOffset(10, y + 48)
		b.acornRow.Size = UDim2.fromOffset(bw - 20, 44)
		b.acornSwitch.Position = UDim2.fromOffset(0, 11)
		b.action.Position = UDim2.new(0, 10, 1, -52)
		b.action.Size = UDim2.new(1, -20, 0, 44)
		b.note.Position = UDim2.fromOffset(10, y)
		b.note.Size = UDim2.new(1, -20, 0, 60)
	else
		local wellW = if bw >= 640 then 150 else bh - 32
		b.well.Position = UDim2.fromOffset(16, 16)
		b.well.Size = UDim2.fromOffset(wellW, bh - 32)
		local x = wellW + 34
		b.name.Position = UDim2.fromOffset(x, 14)
		b.name.Size = UDim2.fromOffset(bw - x - 16, 32)
		b.name.TextSize = 26
		b.line.Position = UDim2.fromOffset(x, 48)
		b.line.Size = UDim2.fromOffset(bw - x - 16, 36)
		b.line.TextSize = 14
		local y = 90
		b.qtyLabel.Position = UDim2.fromOffset(x, y)
		b.qtyLabel.Size = UDim2.fromOffset(80, 16)
		b.minus.Position = UDim2.fromOffset(x, y + 18)
		b.minus.Size = UDim2.fromOffset(40, 40)
		b.qty.Position = UDim2.fromOffset(x + 46, y + 18)
		b.qty.Size = UDim2.fromOffset(44, 40)
		b.plus.Position = UDim2.fromOffset(x + 96, y + 18)
		b.plus.Size = UDim2.fromOffset(40, 40)
		local px = x + 156
		b.priceLabel.Position = UDim2.fromOffset(px, y)
		b.priceLabel.Size = UDim2.fromOffset(60, 16)
		if b.coin then
			b.coin.Position = UDim2.fromOffset(px, y + 30)
		end
		b.price.Position = UDim2.fromOffset(px + 22, y + 18)
		b.price.Size = UDim2.fromOffset(118, 40)
		b.price.TextSize = 24
		b.price.TextScaled = false
		local aw = math.clamp(bw - (px + 22 + 120) - 16, 110, 200)
		b.action.Position = UDim2.new(1, -16 - aw, 0, y + 14)
		b.action.Size = UDim2.fromOffset(aw, 46)
		b.note.Position = UDim2.fromOffset(x, y + 6)
		b.note.Size = UDim2.fromOffset(bw - x - 16, 50)
		b.note.TextSize = 15
		b.acornRow.Visible = false
	end
	-- inside the odds card
	local ow = o.card.Size.X.Offset
	local oh = o.card.Size.Y.Offset
	local ip = if phone then 10 else 24
	o.title.Position = UDim2.fromOffset(ip, if phone then 6 else 16)
	o.title.Size = UDim2.fromOffset(ow - ip * 2 - 140, 26)
	o.title.TextSize = if phone then 13 else 17
	o.details.Position = UDim2.new(1, -ip - (if phone then 112 else 150), 0, if phone then 4 else 12)
	o.details.Size = UDim2.fromOffset(if phone then 112 else 150, if phone then 32 else 38)
	o.details.TextSize = if phone then 12 else 14
	local hy = if phone then 38 else 62
	o.headGrade.Position = UDim2.fromOffset(ip, hy)
	o.headGrade.Size = UDim2.fromOffset(100, 16)
	local numW = if phone then 54 else 70
	o.headNow.Position = UDim2.new(1, -ip - numW - (numW + 16), 0, hy)
	o.headNow.Size = UDim2.fromOffset(numW, 16)
	o.headAcorn.Position = UDim2.new(1, -ip - (numW + 16), 0, hy)
	o.headAcorn.Size = UDim2.fromOffset(numW + 16, 16)
	if ENTRY[current].kind ~= "crate" then
		o.headNow.Position = UDim2.new(1, -ip - numW, 0, hy)
	end
	o.list.Position = UDim2.fromOffset(ip, hy + 18)
	o.list.Size = UDim2.fromOffset(ow - ip * 2, 10)
	local listH = 0
	for _, r in ipairs(o.rows) do
		listH = math.max(listH, r.Position.Y.Offset + r.Size.Y.Offset)
	end
	local ry = hy + 18 + listH + (if phone then 4 else 12)
	if ENTRY[current].kind == "armoury" then
		ry = hy
	end
	o.rule.Position = UDim2.fromOffset(ip, ry)
	o.rule.Size = UDim2.fromOffset(ow - ip * 2, 1)
	o.notes.Position = UDim2.fromOffset(ip, ry + (if phone then 6 else 16))
	o.notes.Size = UDim2.fromOffset(ow - ip * 2, math.max(20, oh - ry - (if phone then 10 else 24)))
	o.notesText.TextSize = if phone then 12 else 14
	-- the armoury card's grid
	local a = ui.arm
	local aw = a.card.Size.X.Offset
	local cellW = math.floor((aw - 40 - 20) / 3)
	a.layout.CellSize = UDim2.fromOffset(cellW, if phone then 64 else 86)
	a.grid.Position = UDim2.fromOffset(if phone then 10 else 20, if phone then 34 else 44)
	a.grid.Size = UDim2.new(1, if phone then -20 else -40, 1, if phone then -84 else -100)
	a.head.Position = UDim2.fromOffset(if phone then 10 else 20, if phone then 6 else 14)
	a.open.Position = UDim2.new(0, 20, 1, -50)
	a.bringBtn.Position = UDim2.new(0, if phone then 10 else 20, 1, if phone then -46 else -50)
	-- open tab
	local ov = ui.open
	local revealW = if phone then W - pad * 2 else 520
	local gridW = if phone then W - pad * 2 else W - pad * 2 - revealW - 24
	ov.head.Position = UDim2.fromOffset(pad, 0)
	ov.head.Size = UDim2.fromOffset(gridW, 22)
	ov.acorn.Position = UDim2.fromOffset(pad + 170, 0)
	ov.acorn.Size = UDim2.fromOffset(math.max(100, gridW - 170), 22)
	if phone then
		ov.layout.CellSize = UDim2.fromOffset(140, 170)
		ov.grid.Position = UDim2.fromOffset(pad, 26)
		ov.grid.Size = UDim2.fromOffset(gridW, bodyH - 30)
		ov.note.Visible = false
		ov.reveal.Position = UDim2.fromOffset(pad, 26)
		ov.reveal.Size = UDim2.fromOffset(revealW, bodyH - 30)
	else
		ov.layout.CellSize = UDim2.fromOffset(math.floor((gridW - 28) / 3), 236)
		ov.grid.Position = UDim2.fromOffset(pad, 30)
		ov.grid.Size = UDim2.fromOffset(gridW, bodyH - 110)
		ov.note.Visible = true
		ov.note.Position = UDim2.new(0, pad, 1, -70)
		ov.note.Size = UDim2.fromOffset(gridW, 44)
		ov.reveal.Position = UDim2.new(1, -pad - revealW, 0, 0)
		ov.reveal.Size = UDim2.fromOffset(revealW, bodyH)
	end
	for _, c in pairs(ov.cards) do
		local small = phone
		c.well.Size = UDim2.new(1, -20, 0, if small then 72 else 118)
		c.well.Position = UDim2.fromOffset(10, 10)
		c.name.Position = UDim2.fromOffset(0, if small then 84 else 138)
		c.name.TextSize = if small then 14 else 17
		c.count.Position = UDim2.fromOffset(0, if small then 104 else 162)
		c.button.Size = UDim2.new(1, -20, 0, 44)
		c.button.Position = UDim2.new(0, 10, 1, -54)
	end
	-- the buy reveal covers the odds and the right column (phone: everything under the header)
	local rv = ui.buyReveal
	if phone then
		rv.Position = UDim2.fromOffset(pad, 0)
		rv.Size = UDim2.fromOffset(W - pad * 2, bodyH - 18)
	else
		rv.Position = UDim2.fromOffset(centerX, 0)
		rv.Size = UDim2.fromOffset(W - centerX - pad, bodyH)
	end
end

-- Build ------------------------------------------------------------------------------------------------------------

local function build()
	-- (integrate, 20 Nov: inside Roblox's own buttons, so a phone's full-screen panel keeps its header clear of them)
	local gui = make("ScreenGui", { Name = "Cases", ResetOnSpawn = false, IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, DisplayOrder = 40, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	make("UIScale", { Name = "Scale" }, root)
	make("UIPadding", { Name = "SafePad" }, root)
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.gui = gui
	ui.root = root
	ui.scale = Theme.bindRoot(gui)
	-- the soft shade around the panel
	make("Frame", { Name = "Dim", BackgroundColor3 = SHADE, BackgroundTransparency = 0.55, BorderSizePixel = 0,
		Size = UDim2.new(1, 200, 1, 200), Position = UDim2.fromOffset(-100, -100), ZIndex = 0 }, root)
	local panel = panelFrame("Panel", root, "panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	ui.panel = panel
	-- (integrate, 20 Nov) the mouse is free while CASES is up: first person locks it otherwise
	make("TextButton", { Name = "Modal", Modal = true, Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0),
		Selectable = false }, panel)
	-- header
	ui.title = label(panel, { Name = "Title", Text = "Cases", Font = "Light", TextSize = 38 })
	ui.tabBuy = button(panel, "secondary", "Buy", { Name = "TabBuy", TextSize = 18 })
	ui.tabOpen = button(panel, "plain", "Open", { Name = "TabOpen", TextSize = 18 })
	for _, t in ipairs({ ui.tabBuy, ui.tabOpen }) do
		t.FontFace = F.SemiBold
	end
	ui.badge = make("Frame", { Name = "Badge", BackgroundColor3 = SUN, BorderSizePixel = 0, Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0, 2), Visible = false, ZIndex = 3 }, ui.tabOpen)
	corner(ui.badge, 11)
	ui.badgeText = label(ui.badge, { Font = "SemiBold", TextSize = 13, TextColor3 = SHADE, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	ui.goldRow = make("Frame", { Name = "Gold", BackgroundTransparency = 1 }, panel)
	local goldCoin = icon("coin", ui.goldRow, { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0) })
	ui.gold = label(ui.goldRow, { Font = "Mono", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(0, 90, 1, 0),
		Position = UDim2.new(1, -90, 0, 0) })
	-- (hunt1_1) the coin sits just left of the number, however short it is ("150" left an 80 px gap)
	if goldCoin then
		local function hug()
			local w = (ui.gold :: TextLabel).TextBounds.X
			goldCoin.Position = UDim2.new(1, -math.ceil(w) - 8, 0.5, 0)
		end
		(ui.gold :: TextLabel):GetPropertyChangedSignal("TextBounds"):Connect(hug)
		hug()
	end
	ui.close = button(panel, "plain", "", { Name = "Close" })
	icon("close", ui.close, { Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	ui.shelfHeader = button(panel, "secondary", "SHELF", { Name = "ShelfHeader", TextSize = 13, Visible = false })
	ui.shelfHeader.Activated:Connect(ShopController.showShelf)
	ui.tabBuy.Activated:Connect(function()
		ShopController.setTab("buy")
	end)
	ui.tabOpen.Activated:Connect(function()
		ShopController.setTab("open")
	end)
	ui.close.Activated:Connect(function()
		ShopController.close()
	end)
	ui.toast = label(panel, { Name = "Toast", TextSize = 14, TextColor3 = INK2, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
	-- buy view
	ui.buyView = make("Frame", { Name = "BuyView", BackgroundTransparency = 1 }, panel)
	buildSide(ui.buyView)
	buildBuyCard(ui.buyView)
	buildOddsCard(ui.buyView)
	buildLuckCard(ui.buyView)
	buildShelfCard(ui.buyView)
	buildArmouryCard(ui.buyView)
	ui.buyReveal = make("Frame", { Name = "BuyReveal", BackgroundColor3 = K.Panel, BackgroundTransparency = 0, BorderSizePixel = 0,
		Visible = false, ZIndex = 10 }, ui.buyView)
	corner(ui.buyReveal, 10)
	ui.buyRevealPane = make("Frame", { Name = "Pane", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 58), Size = UDim2.new(1, -40, 1, -72),
		ZIndex = 10 }, ui.buyReveal)
	ui.buyRevealDone = button(ui.buyReveal, "secondary", "DONE", { Name = "Done", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(96, 40), ZIndex = 12, TextSize = 14 })
	ui.buyRevealDone.Activated:Connect(function()
		revealToken += 1
		ui.buyReveal.Visible = false
		clear(ui.buyRevealPane)
	end)
	buildOpenView(panel)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if ShopController.isOpen then
			refresh()
		end
	end)
end

-- Results from the server -----------------------------------------------------------------------------------------------

showResult = function(result: any)
	if not ui.panel or type(result) ~= "table" or type(result.results) ~= "table" or #result.results == 0 then
		return
	end
	lastResult = result
	revealToken += 1
	local token = revealToken
	local pane: Frame
	local w: number
	local h: number
	if tab == "open" then
		pane = ui.open.reveal
		w = pane.Size.X.Offset
		h = pane.Size.Y.Offset
	else
		ui.buyReveal.Visible = true
		pane = ui.buyRevealPane
		w = ui.buyReveal.Size.X.Offset - 40
		h = ui.buyReveal.Size.Y.Offset - 72
	end
	if #result.results == 1 then
		task.spawn(revealOne, pane, result.results[1], result.crate, result.crate ~= "shelf", w, token, h)
	else
		task.spawn(revealMany, pane, result, w, token, h)
	end
end

-- Public -------------------------------------------------------------------------------------------------------------------

select = function(id: string)
	if not ENTRY[id] then
		return
	end
	if current ~= id then
		quantity = 1
	end
	current = id
	if ui.buyReveal then
		ui.buyReveal.Visible = false
	end
	refresh()
end

function ShopController.setTab(t: string)
	if t ~= "buy" and t ~= "open" then
		return
	end
	tab = t
	sound("UIClick", 0.4)
	revealToken += 1
	if ui.buyReveal then
		ui.buyReveal.Visible = false
	end
	refresh()
	-- (ui-motion) the new tab's page cross-fades in (Motion.Tab, 0.15 s)
	local page = if tab == "buy" then ui.buyView else (ui.open and ui.open.view)
	if page then
		QuietUI.swap(page)
	end
end

local function onAction(name: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if name == "CasesBack" then
		if ui.overlay then
			ui.overlay:Destroy()
			ui.overlay = nil
		elseif ui.buyReveal and ui.buyReveal.Visible then
			ui.buyReveal.Visible = false
		else
			ShopController.close()
		end
	elseif name == "CasesTabs" then
		ShopController.setTab(if tab == "buy" then "open" else "buy")
	elseif name == "CasesDetails" then
		if tab == "buy" and ENTRY[current].kind ~= "armoury" then
			ShopController.showDetails()
		end
	end
	return Enum.ContextActionResult.Sink
end

-- (integrate, 20 Nov) CASES holds the menu state like every other card screen: gameplay keys rest, the M menu and the
-- hub bar step aside (SettingsController.setModal keeps ClientState.menuOpen right)
local function setModal(on: boolean)
	local settings = controllers and controllers.SettingsController
	if settings and settings.setModal then
		settings.setModal("Cases", on)
	end
end

local function awayFromTrain(): boolean
	local ok, state = pcall(function()
		return require(script.Parent.Parent:WaitForChild("ClientState") :: ModuleScript)
	end)
	if ok and type(state) == "table" then
		return state.inArena == true or state.spectating ~= nil or state.launchShot == true
	end
	return false
end

function ShopController.open(entry: string?, startTab: string?)
	if inRound() or awayFromTrain() then
		return false
	end
	if not ui.panel then
		build()
	end
	if entry and ENTRY[entry] then
		current = entry
		quantity = 1
	end
	tab = if startTab == "open" then "open" else "buy"
	if not ShopController.isOpen then
		blurOn(true)
	end
	ShopController.isOpen = true
	QuietUI.openScreen(ui.gui, ui.panel) -- (ui-motion) fade and rise, no pop
	setModal(true)
	sound("UIOpen", 0.5)
	if shopRemote then
		shopRemote:FireServer("state")
	end
	if rewardsRemote then
		rewardsRemote:FireServer("state")
	end
	refresh()
	ContextActionService:BindActionAtPriority("CasesBack", onAction, false, 3000, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
	ContextActionService:BindActionAtPriority("CasesTabs", onAction, false, 3000, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority("CasesDetails", onAction, false, 3000, Enum.KeyCode.ButtonY)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = if tab == "buy" then ui.buy.action else ui.tabOpen
	end
	return true
end

function ShopController.close()
	if not ShopController.isOpen then
		return
	end
	ShopController.isOpen = false
	revealToken += 1
	if ui.gui then
		QuietUI.closeScreen(ui.gui, ui.panel) -- (ui-motion) fade and sink out, then disabled
	end
	if ui.overlay then
		ui.overlay:Destroy()
		ui.overlay = nil
	end
	blurOn(false)
	setModal(false)
	ContextActionService:UnbindAction("CasesBack")
	ContextActionService:UnbindAction("CasesTabs")
	ContextActionService:UnbindAction("CasesDetails")
	if GuiService.SelectedObject and ui.gui and GuiService.SelectedObject:IsDescendantOf(ui.gui) then
		GuiService.SelectedObject = nil
	end
end

-- Studio tests: the last result shown, and the state
function ShopController._debug(): any
	return { shop = shop, rew = rew, current = current, tab = tab, quantity = quantity, acornOn = acornOn, lastResult = lastResult, phone = phone }
end
function ShopController._set(k: string, v: any)
	if k == "phonePreview" then
		ui.phonePreview = v == true
		if v and not ui.phoneFrame and ui.root then
			-- the phone's outline (812 x 375 design px at scale 1) around the panel
			ui.phoneFrame = make("Frame", { Name = "PhoneFrame", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), ZIndex = 0 }, ui.root)
			edge(ui.phoneFrame, SUN, 2, 0.2)
		end
		if ui.scaleObject then
			ui.scaleObject.Scale = if v then 1 else ui.scaleObject.Scale
		end
	elseif k == "acornOn" then
		acornOn = v
	elseif k == "quantity" then
		quantity = v
	elseif k == "armourySel" then
		armourySel = v
	end
	refresh()
end
ShopController.select = function(id: string)
	select(id)
end

function ShopController.Init(c)
	controllers = c
end

function ShopController.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	shopRemote = remotes:WaitForChild("Shop", 30) :: RemoteEvent?
	rewardsRemote = remotes:WaitForChild("Rewards", 30) :: RemoteEvent?
	if shopRemote then
		shopRemote.OnClientEvent:Connect(function(kind, data)
			if kind == "state" and type(data) == "table" then
				shop = data
				if ShopController.isOpen then
					refresh()
				end
			elseif kind == "result" then
				if ShopController.isOpen then
					showResult(data)
				end
			elseif kind == "line" and type(data) == "string" then
				toast(data)
			elseif kind == "gold" and ShopController.isOpen then
				refresh()
			end
		end)
		shopRemote:FireServer("state")
	end
	if rewardsRemote then
		rewardsRemote.OnClientEvent:Connect(function(kind, data)
			if kind == "state" and type(data) == "table" then
				rew = data
				if ShopController.isOpen then
					refresh()
				end
			elseif kind == "line" and type(data) == "string" and ShopController.isOpen then
				toast(data)
			end
		end)
	end
	player:GetAttributeChangedSignal("Gold"):Connect(function()
		if ShopController.isOpen then
			refresh()
		end
	end)
	-- never open in a round: close if the round takes the player
	player:GetAttributeChangedSignal("Alive"):Connect(function()
		if inRound() then
			ShopController.close()
		end
	end)
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		if inRound() then
			ShopController.close()
		end
	end)
	local _ = controllers
end

return ShopController
