--[[
	SeasonController - the SEASON TRACK screen (docs/design/CardMenusAndShop.md 2.6, mock-up m08_season; the owner's
	reference ui_ref_battlepass): the tier bar ("Tier 23", the XP bar, "620 / 1,000 XP to tier 24", days left), one
	track of numbered nodes with the FREE row of reward cards above it and the PREMIUM row under it, claimed (dim +
	tick) / claimable (Sun edge, CLAIM in the card) / locked, sideways scroll (wheel, drag, LB / RB jump 5 tiers), and
	the ENCORE card on the right (the reference's "Rebirth"). Built on Shared.Cards; server: SeasonService.

	While Config.Shop.SeasonPremium is off (or has no product id) the premium row and its button are hidden, not
	teased, and the free row centres. Public: open(), close(), isOpen(), claimableCount() -> number
]]
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Icons = require(Shared:WaitForChild("Icons"))
local Theme = require(Shared:WaitForChild("Theme"))
local Progression = require(Shared:WaitForChild("Progression"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local Client = script.Parent.Parent
local ProgressUI = require(Client:WaitForChild("ProgressUI"))

local SeasonController = {}

local screen: any = nil
local R: { [string]: any } = {}
local built = false
local tiles: { [string]: { [number]: TextButton } } = { free = {}, prem = {} }
local nodes: { [number]: Frame } = {}
local unbindShoulders: (() -> ())? = nil
local CARD_W, CARD_H, GAP = 176, 210, 18

local function season(): { [string]: any }?
	local s = ProgressUI.state
	return s and s.season
end

local function bit(bits: string?, tier: number): boolean
	return type(bits) == "string" and string.sub(bits, tier, tier) == "1"
end

function SeasonController.claimableCount(): number
	local s = season()
	if not s then
		return 0
	end
	local n = 0
	for t = 1, s.tier do
		if not bit(s.free, t) then
			n += 1
		end
		if s.premiumOn and s.premium and not bit(s.prem, t) then
			n += 1
		end
	end
	return n + math.max(0, (s.encores or 0) - (s.encoreClaimed or 0))
end

local function daysLeft(s: { [string]: any }): string
	local now = (ProgressUI.state and ProgressUI.state.now) or os.time()
	local left = (s.finish or now) - now
	if left <= 0 then
		return "season over"
	end
	local days = math.floor(left / 86400)
	if days >= 1 then
		return string.format("%d day%s left", days, if days == 1 then "" else "s")
	end
	return Cards.clock(left) .. " left"
end

local function build()
	screen = ProgressUI.screen("SeasonGui", "Season Track")
	local body = screen.body
	local phone = screen.phone
	if phone then
		CARD_W, CARD_H, GAP = 112, 150, 8
	end
	-- Gold (top right)
	local goldRow = Instance.new("Frame")
	goldRow.Name = "Gold"
	goldRow.BackgroundTransparency = 1
	goldRow.Size = UDim2.fromScale(1, 1)
	goldRow.Parent = screen.head
	local gl = Instance.new("UIListLayout")
	gl.FillDirection = Enum.FillDirection.Horizontal
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	gl.VerticalAlignment = Enum.VerticalAlignment.Center
	gl.Padding = UDim.new(0, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = goldRow
	local claimAll = Cards.button("Secondary", "Claim all", { Name = "ClaimAll", LayoutOrder = 1, Visible = false,
		Size = UDim2.new(0, 0, 0, if phone then 34 else 40), Parent = goldRow })
	claimAll.Activated:Connect(function()
		ProgressUI.send({ t = "claimAll" })
	end)
	R.claimAll = claimAll
	local spacer = Instance.new("Frame")
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.fromOffset(14, 1)
	spacer.LayoutOrder = 2
	spacer.Parent = goldRow
	Icons.make("coin", { Size = UDim2.fromOffset(18, 18), LayoutOrder = 3, Parent = goldRow })
	R.gold = Cards.label("0", { Font = Theme.Fonts.MonoMedium, TextSize = if phone then 17 else 22, LayoutOrder = 4,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), Parent = goldRow })

	-- the tier bar box
	local boxH = if phone then 46 else 84
	local box = Instance.new("Frame")
	box.Name = "TierBox"
	box.BackgroundColor3 = Cards.Surface.Card.color
	box.BackgroundTransparency = Cards.Surface.Card.transparency
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, 0, 0, boxH)
	box.Parent = body
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, Cards.Corner.Card)
	bc.Parent = box
	local bs = Instance.new("UIStroke")
	bs.Color = Theme.Colors.Ink
	bs.Transparency = 0.82
	bs.Thickness = 1.5
	bs.Parent = box
	R.tier = Cards.label("Tier 0", { Font = Theme.Fonts.SemiBold, TextSize = if phone then 18 else 26,
		Position = UDim2.fromOffset(if phone then 12 else 26, 0), Size = UDim2.new(0, if phone then 90 else 140, 1, 0), Parent = box })
	R.bar = Cards.bar({ Height = if phone then 8 else 12, Position = UDim2.new(0, if phone then 108 else 172, 0.5, if phone then -8 else -10),
		Size = UDim2.new(1, if phone then -240 else -440, 0, if phone then 8 else 12), Parent = box })
	R.xp = Cards.label("", { Font = Theme.Fonts.Mono, TextSize = if phone then 12 else 14, Color = Theme.Colors.Ink2,
		Position = UDim2.new(0, if phone then 108 else 172, 0.5, if phone then 2 else 8),
		Size = UDim2.new(0.5, -120, 0, 18), Parent = box })
	if not phone then
		local how = Cards.label("about 250 XP a round · placing, defeats and time alive · drills in the Training Centre",
			{ TextSize = 13, Color = Theme.Colors.Ink2, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -268, 0.5, 8),
				Size = UDim2.new(0.5, -200, 0, 18), Parent = box })
		how.TextXAlignment = Enum.TextXAlignment.Right
		how.TextTruncate = Enum.TextTruncate.AtEnd
	end
	R.days = Cards.label("", { Font = Theme.Fonts.Mono, TextSize = if phone then 13 else 19, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, if phone then -12 else -26, 0, 0), Size = UDim2.new(0, if phone then 110 else 220, 1, 0), Parent = box })
	R.days.TextXAlignment = Enum.TextXAlignment.Right

	-- the track area: row labels | scrolling track | encore
	local trackTop = boxH + (if phone then 8 else 24)
	local labelW = if phone then 0 else 120
	local encoreW = if phone then 124 else 220
	local area = Instance.new("Frame")
	area.Name = "Area"
	area.BackgroundTransparency = 1
	area.Position = UDim2.fromOffset(0, trackTop)
	area.Size = UDim2.new(1, 0, 1, -trackTop)
	area.Parent = body
	R.area = area
	R.freeLabel = Cards.section("Free", { Position = UDim2.fromOffset(0, 40), Size = UDim2.fromOffset(labelW, 24), Visible = not phone,
		Parent = area })
	R.premLabel = Cards.section("Premium", { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(labelW, 24), Visible = false,
		Parent = area })
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Track"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Theme.Colors.Ink
	scroll.ScrollBarImageTransparency = 0.7
	scroll.Selectable = false
	scroll.Position = UDim2.fromOffset(labelW, 0)
	scroll.Size = UDim2.new(1, -labelW - encoreW - (if phone then 8 else 16), 1, 0)
	scroll.CanvasSize = UDim2.fromOffset(50 * (CARD_W + GAP) + GAP, 0)
	scroll.Parent = area
	R.scroll = scroll

	-- the Encore card (right)
	local encore = Cards.card({
		Name = "Encore",
		Title = "Encore",
		NameSize = if phone then 13 else 18,
		Picture = function(well)
			ProgressUI.glyph(well, "spark", 0.5, Progression.Metals.brass)
		end,
		Text = if phone then "After tier 50: every 2,500 XP pays the free row again."
			else "After tier 50, every 2,500 XP is an Encore: the free row pays out again. Encores 1, 2, 3, 5, 7 and 10 add a numbered banner trim. Nothing random.",
		TextLines = if phone then 4 else 7,
		WellHeight = if phone then 0.3 else 0.3,
		Selectable = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, encoreW, 1, 0),
		Parent = area,
	})
	R.encore = encore
	local eb = Cards.button("Off", "Tier 50 first", { Name = "EncoreButton", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, if phone then 40 else 44), AutomaticSize = Enum.AutomaticSize.None,
		TextSize = if phone then 12 else 15, Parent = encore })
	eb.Activated:Connect(function()
		if eb:GetAttribute("Kind") == "Sun" then
			ProgressUI.send({ t = "encore" })
		end
	end)
	R.encoreButton = eb

	-- premium purchase line (shown only when the switch is on)
	local buy = Cards.button("Secondary", "Unlock premium", { Name = "BuyPremium", AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, labelW, 1, 0), Visible = false, Parent = area })
	buy.Activated:Connect(function()
		ProgressUI.send({ t = "buyPremium" })
	end)
	R.buy = buy

	unbindShoulders = nil
end

local function cardFor(row: string, tier: number, reward: { [string]: any }): TextButton
	local phone = screen.phone
	local card = Cards.card({
		Name = string.format("%s%02d", row, tier),
		Title = ProgressUI.rewardTitle(reward),
		Sub = if Progression.Grades[reward.id or ""] then nil else ProgressUI.rewardKind(reward),
		Grade = ProgressUI.gradeOf(reward),
		NameSize = if phone then 12 else 15,
		Picture = ProgressUI.rewardPicture(reward),
		WellHeight = if phone then 0.56 else 0.62,
		Big = true,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
	})
	local claim = Cards.button("Sun", "Claim", { Name = "ClaimButton", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, if phone then 30 else 34), AutomaticSize = Enum.AutomaticSize.None,
		TextSize = if phone then 12 else 14, Visible = false, Parent = card })
	claim.ZIndex = 9
	claim.Activated:Connect(function()
		claim.Visible = false
		ProgressUI.send({ t = "claim", row = row, tier = tier })
	end)
	card.Activated:Connect(function()
		if claim.Visible then
			claim.Visible = false
			ProgressUI.send({ t = "claim", row = row, tier = tier })
		end
	end)
	return card
end

local function buildTrack()
	if built then
		return
	end
	built = true
	local scroll = R.scroll :: ScrollingFrame
	for t = 1, 50 do
		local x = GAP / 2 + (t - 1) * (CARD_W + GAP)
		local free = cardFor("free", t, Progression.FreeRow[t])
		free.Position = UDim2.fromOffset(x, 0)
		free.Parent = scroll
		tiles.free[t] = free
		local prem = cardFor("prem", t, Progression.PremiumRow[t])
		prem.Position = UDim2.fromOffset(x, 0)
		prem.Visible = false
		prem.Parent = scroll
		tiles.prem[t] = prem
		-- the node (a numbered disc on the line)
		local node = Instance.new("Frame")
		node.Name = string.format("Node%02d", t)
		node.BackgroundColor3 = Cards.Surface.Card.color
		node.BorderSizePixel = 0
		node.Size = UDim2.fromOffset(if screen.phone then 30 else 46, if screen.phone then 30 else 46)
		node.AnchorPoint = Vector2.new(0.5, 0.5)
		node.ZIndex = 3
		local nc = Instance.new("UICorner")
		nc.CornerRadius = UDim.new(0.5, 0)
		nc.Parent = node
		local ns = Instance.new("UIStroke")
		ns.Name = "Ring"
		ns.Color = Theme.Colors.Ink
		ns.Transparency = 0.6
		ns.Thickness = 1.5
		ns.Parent = node
		local num = Cards.label(tostring(t), { Font = Theme.Fonts.SemiBold, TextSize = if screen.phone then 13 else 18,
			Size = UDim2.fromScale(1, 1), Parent = node })
		num.Name = "Num"
		num.TextXAlignment = Enum.TextXAlignment.Center
		num.ZIndex = 4
		node.Parent = scroll
		nodes[t] = node
		-- the line to the next node
		if t < 50 then
			local line = Instance.new("Frame")
			line.Name = string.format("Line%02d", t)
			line.BorderSizePixel = 0
			line.BackgroundColor3 = Theme.Colors.Ink
			line.BackgroundTransparency = 0.8
			line.AnchorPoint = Vector2.new(0, 0.5)
			line.Size = UDim2.fromOffset(CARD_W + GAP, 3)
			line.ZIndex = 2
			line.Parent = scroll
			node:SetAttribute("Line", line.Name)
		end
	end
end

local function layoutTrack(premiumShown: boolean)
	local scroll = R.scroll :: ScrollingFrame
	local h = scroll.AbsoluteSize.Y / math.max(0.01, (screen.gui.Root :: any).Scale.Scale)
	if h < 120 then
		h = if screen.phone then 230 else 440 -- not laid out yet: the next render corrects it
	end
	local nodeH = if screen.phone then 36 else 64
	local freeY, nodeY, premY
	if premiumShown then
		local cardH = math.min(CARD_H, (h - nodeH - 50) / 2)
		freeY, nodeY, premY = 0, cardH + nodeH / 2, cardH + nodeH
		for t = 1, 50 do
			tiles.free[t].Size = UDim2.fromOffset(CARD_W, cardH)
			tiles.prem[t].Size = UDim2.fromOffset(CARD_W, cardH)
		end
	else
		local cardH = math.min(CARD_H + 90, h - nodeH - 20)
		local total = cardH + nodeH
		freeY = math.max(0, (h - total) / 2 - 10)
		nodeY = freeY + cardH + nodeH / 2
		for t = 1, 50 do
			tiles.free[t].Size = UDim2.fromOffset(CARD_W, cardH)
		end
	end
	for t = 1, 50 do
		local x = GAP / 2 + (t - 1) * (CARD_W + GAP)
		tiles.free[t].Position = UDim2.fromOffset(x, freeY)
		tiles.prem[t].Visible = premiumShown
		if premiumShown then
			tiles.prem[t].Position = UDim2.fromOffset(x, premY)
		end
		nodes[t].Position = UDim2.fromOffset(x + CARD_W / 2, nodeY)
		local line = scroll:FindFirstChild(string.format("Line%02d", t)) :: Frame?
		if line then
			line.Position = UDim2.fromOffset(x + CARD_W / 2, nodeY)
		end
	end
	R.freeLabel.Position = UDim2.fromOffset(0, freeY + 8)
	R.premLabel.Visible = premiumShown and not screen.phone
	if premiumShown and premY then
		R.premLabel.Position = UDim2.fromOffset(0, premY + 8)
	end
end

local function render()
	if not screen then
		return
	end
	local st = ProgressUI.state
	local s = season()
	if not s or not st then
		screen.sub.Text = "loading"
		return
	end
	buildTrack()
	screen.sub.Text = string.format("Season %s · %s", string.gsub(s.id or "S1", "^S", ""), s.name or "")
	R.gold.Text = Progression.comma(st.gold or 0)
	local atTop = s.tier >= (s.tiers or 50)
	R.tier.Text = "Tier " .. tostring(s.tier)
	local claimable = SeasonController.claimableCount()
	Cards.setBar(R.bar, if s.need > 0 then s.into / s.need else 1, claimable > 0)
	R.xp.Text = if atTop then string.format("%s / %s XP to Encore %d", Progression.comma(s.into), Progression.comma(s.need), (s.encores or 0) + 1)
		else string.format("%s / %s XP to tier %d", Progression.comma(s.into), Progression.comma(s.need), s.tier + 1)
	R.days.Text = daysLeft(s)
	R.claimAll.Visible = claimable >= 2
	local premiumShown = s.premiumOn == true
	layoutTrack(premiumShown)
	R.buy.Visible = premiumShown and not s.premium
	for t = 1, 50 do
		for _, row in ipairs({ "free", "prem" }) do
			local card = tiles[row][t]
			if row == "prem" and not premiumShown then
				continue
			end
			local reached = t <= s.tier
			local done = bit(if row == "free" then s.free else s.prem, t)
			local canClaim = reached and not done and (row == "free" or s.premium)
			Cards.setState(card, "Owned", done)
			Cards.setState(card, "Disabled", done)
			Cards.setState(card, "Claimable", canClaim)
			Cards.setState(card, "Locked", if not reached or (row == "prem" and not s.premium) then "" else false)
			local claim = card:FindFirstChild("ClaimButton") :: GuiObject?
			if claim then
				claim.Visible = canClaim
			end
			local bottom = card:FindFirstChild("Bottom") :: GuiObject?
			if bottom then
				bottom.Visible = not canClaim
			end
		end
		local node = nodes[t]
		local reached = t <= s.tier
		local ring = node:FindFirstChild("Ring") :: UIStroke
		local current = t == math.min(s.tier + 1, 50) and not atTop
		node.BackgroundColor3 = if reached then Theme.Colors.Ink else Cards.Surface.Card.color
		node.BackgroundTransparency = if reached then 0 else 0.1
		ring.Color = if current then Theme.Colors.Sun else Theme.Colors.Ink
		ring.Transparency = if current then 0 else 0.6
		local num = node:FindFirstChild("Num") :: TextLabel
		num.TextColor3 = if reached then Theme.Colors.Shade else (if current then Theme.Colors.Sun else Theme.Colors.Ink)
		local line = R.scroll:FindFirstChild(string.format("Line%02d", t)) :: Frame?
		if line then
			line.BackgroundTransparency = if t < s.tier then 0.05 else 0.8
		end
	end
	-- Encore
	local owedEncores = math.max(0, (s.encores or 0) - (s.encoreClaimed or 0))
	if not atTop then
		Cards.setButtonKind(R.encoreButton, "Off")
		R.encoreButton.Text = "TIER 50 FIRST"
	elseif owedEncores > 0 then
		Cards.setButtonKind(R.encoreButton, "Sun")
		R.encoreButton.Text = string.format("CLAIM ENCORE %d", (s.encoreClaimed or 0) + 1)
	else
		Cards.setButtonKind(R.encoreButton, "Off")
		R.encoreButton.Text = string.format("ENCORE %d · %s XP", (s.encores or 0) + 1, Progression.comma(s.need - s.into))
	end
	Cards.setState(R.encore, "Claimable", owedEncores > 0)
end

local function scrollToCurrent(instant: boolean?)
	local s = season()
	if not s or not R.scroll then
		return
	end
	local scroll = R.scroll :: ScrollingFrame
	local scale = (screen.gui.Root :: any).Scale.Scale
	local view = scroll.AbsoluteSize.X / math.max(0.01, scale)
	-- the first claimable tier, else the next one to reach
	local target = math.min(s.tier + 1, 50)
	for t = 1, s.tier do
		if not bit(s.free, t) then
			target = t
			break
		end
	end
	local x = math.max(0, (target - 1) * (CARD_W + GAP) - view / 2 + CARD_W / 2)
	local pos = Vector2.new(x * scale, 0)
	if instant then
		scroll.CanvasPosition = pos
	else
		TweenService:Create(scroll, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { CanvasPosition = pos }):Play()
	end
end

local function jump(dir: number)
	local scroll = R.scroll :: ScrollingFrame
	local scale = (screen.gui.Root :: any).Scale.Scale
	local step = 5 * (CARD_W + GAP) * scale
	local x = math.clamp(scroll.CanvasPosition.X + dir * step, 0, math.max(0, scroll.AbsoluteCanvasSize.X - scroll.AbsoluteSize.X))
	TweenService:Create(scroll, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { CanvasPosition = Vector2.new(x, 0) }):Play()
end

function SeasonController.open(): boolean
	if not screen then
		return false
	end
	if Cards.metrics().phone ~= screen.phone then
		SeasonController.rebuild() -- built before the window had its size, or the device class changed
	end
	local ok = screen.open()
	if ok then
		render()
		-- once the panel has its size (the first frame after it shows), lay the track out again and scroll to it
		task.delay(0.05, function()
			render()
			scrollToCurrent(true)
		end)
		unbindShoulders = Cards.bindShoulders("SeasonShoulders", function()
			jump(-1)
		end, function()
			jump(1)
		end)
		if ProgressUI.isGamepad() then
			local s = season()
			local t = if s then math.clamp(s.tier, 1, 50) else 1
			GuiService.SelectedObject = tiles.free[t]
		end
	end
	return ok
end

function SeasonController.close()
	if screen then
		screen.close()
	end
end

-- builds the screen again (after the device class changes; tests)
function SeasonController.rebuild()
	if screen then
		screen.close()
		screen.gui:Destroy()
	end
	R = {}
	built = false
	tiles = { free = {}, prem = {} }
	nodes = {}
	CARD_W, CARD_H, GAP = 176, 210, 18
	build()
	screen.onClose(function()
		if unbindShoulders then
			unbindShoulders()
			unbindShoulders = nil
		end
	end)
end

function SeasonController.isOpen(): boolean
	return screen ~= nil and screen.isOpen()
end

function SeasonController.Init(controllers)
	ProgressUI.Controllers = ProgressUI.Controllers or controllers
end

function SeasonController.Start()
	build()
	ProgressUI.openers.season = function(arg)
		if arg == "phone" then
			SeasonController.rebuild()
		end
		SeasonController.open()
	end
	screen.onClose(function()
		if unbindShoulders then
			unbindShoulders()
			unbindShoulders = nil
		end
	end)
	ProgressUI.stateChanged:Connect(function()
		if screen.isOpen() then
			render()
		end
	end)
	ProgressUI.on("claimed", function(msg)
		if msg.what == "tier" or msg.what == "all" or msg.what == "encore" then
			Sfx.play("UIClick", { pitch = 0.9 })
		end
	end)
	-- days left ticks over while it is open
	while true do
		task.wait(30)
		if screen.isOpen() then
			local s = season()
			if s then
				R.days.Text = daysLeft(s)
			end
		end
	end
end

return SeasonController
