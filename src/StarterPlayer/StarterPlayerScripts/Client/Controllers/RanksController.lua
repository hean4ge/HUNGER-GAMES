--[[
	RanksController - the RANKS screen (docs/design/CardMenusAndShop.md 2.7 and 2.8, mock-ups m09_ranks and
	m10_boards), the rank-up moment, the rank over heads in the train, and the paper boards' prompts. Built on
	Shared.Cards; servers: RankService and LeaderboardService (through SeasonService's Progress remote).

	  Tabs: Level · Arena Rank (later, shown dim) · Leaderboards (LB / RB).
	  Level: "You" (big emblem, rank name, level, XP bar, the next rank's rewards as tiles, the Prestige rule and, at
	    level 100, PRESTIGE), then the ladder of ten rank cards (past dim, yours outlined, the next one's rewards).
	  Leaderboards: the six boards as cards on the left, This week / All time, "Week 47 · resets Monday 00:00 UTC ·
	    updated every 2 min", rows (place, name strip, rank emblem, value), the top three in full Ink, your row outlined
	    in Sun and pinned at the bottom when you are not on the page ("not in the top 50" when the read cannot place you).
	  The rank-up moment: never in a round. When a band is crossed the server says { t = "rankup" }; the moment waits
	    until you are in the train with no menu open: the screen dims slightly, the emblem turns in (0.6 s), a low bell,
	    "RANK UP" in Sun, the rank name in Light 60, its reward tiles one by one with NEW dots and one button; after 3 s
	    of nothing (or a press) it folds away and the server is told (others in the car then see a small emblem flash
	    over you for 2 s: the RankUpAt attribute). A plain level-up shows one quiet line: "Level 24 · +100 Gold".
	  Over heads in the train: a small emblem and "Lv 24" (★n with Prestige) over each player while both of you are
	    out of the arena.
	Public: open(tab?, board?, scope?), close(), isOpen(), showRankUp(msg) (tests)
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Theme = require(Shared:WaitForChild("Theme"))
local Progression = require(Shared:WaitForChild("Progression"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local ProgressUI = require(Client:WaitForChild("ProgressUI"))

local player = Players.LocalPlayer

local RanksController = {}

local screen: any = nil
local R: { [string]: any } = {}
local tabsApi: any = nil
local scopeApi: any = nil
local currentBoard = "Wins"
local currentScope = "week"
local unbindShoulders: (() -> ())? = nil
local pendingRankUp: { [string]: any }? = nil
local momentGui: ScreenGui? = nil
local momentShowing = false
local lineGui: ScreenGui? = nil
local pendingLine: string? = nil

local function lv(): { [string]: any }?
	local s = ProgressUI.state
	return s and s.level
end

local function clear(frame: Instance)
	for _, c in ipairs(frame:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function rewardTile(r: { [string]: any }, size: number, parent: Instance, order: number): TextButton
	return Cards.tile({
		Name = "Reward" .. order,
		Picture = ProgressUI.rewardPicture(r),
		Grade = ProgressUI.gradeOf(r),
		Label = "",
		NoName = true,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = order,
		Selectable = false,
		Parent = parent,
	})
end

local function rewardsLine(rewards: { { [string]: any } }): string
	if #rewards == 0 then
		return "—"
	end
	return Progression.rewardsText(rewards)
end

--------------------------------------------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------------------------------------------

local function build()
	screen = ProgressUI.screen("RanksGui", "Ranks")
	local phone = screen.phone
	-- tabs sit in the head (right of the title)
	local tabs, api = Cards.tabs({
		{ key = "level", text = "Level" },
		{ key = "arena", text = "Arena Rank" },
		{ key = "boards", text = "Leaderboards" },
	}, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), TextSize = if phone then 14 else 17 })
	tabs.Parent = screen.sub.Parent
	tabs.Position = UDim2.fromOffset(if phone then 100 else 200, if phone then 6 else 22)
	tabs.AnchorPoint = Vector2.new(0, 0)
	tabsApi = api
	local arena = api.buttons.arena
	arena.Text = "Arena Rank  later"
	arena.TextTransparency = 0.55
	screen.sub.Visible = false

	local level = Instance.new("Frame")
	level.Name = "LevelTab"
	level.BackgroundTransparency = 1
	level.Size = UDim2.fromScale(1, 1)
	level.Parent = screen.body
	R.level = level
	local boards = Instance.new("Frame")
	boards.Name = "BoardsTab"
	boards.BackgroundTransparency = 1
	boards.Size = UDim2.fromScale(1, 1)
	boards.Visible = false
	boards.Parent = screen.body
	R.boards = boards
	local later = Cards.label("Arena Rank arrives once rounds fill to 8 or more real contenders reliably. Your Level is your rank until then.",
		{ Name = "ArenaLater", TextSize = 16, Color = Theme.Colors.Ink2, Size = UDim2.new(1, 0, 0, 60), Visible = false, Parent = screen.body })
	later.TextWrapped = true
	R.arena = later

	-- Level: You (left) + ladder (right)
	local youW = if phone then 0.36 else 0.34
	local you = Cards.panel({ Name = "You", Size = UDim2.new(youW, -10, 1, 0), Parent = level })
	you.BackgroundColor3 = Cards.Surface.Card.color
	you.BackgroundTransparency = Cards.Surface.Card.transparency
	for _, n in ipairs({ "Shade1", "Shade2", "Shade3" }) do
		local s = you:FindFirstChild(n)
		if s then
			s:Destroy()
		end
	end
	R.you = you
	local ladder = Cards.grid({ Name = "Ladder", Position = UDim2.new(youW, 6, 0, 0), Size = UDim2.new(1 - youW, -6, 1, 0),
		Cell = if phone then Vector2.new(200, 76) else Vector2.new(250, 104), Gap = if phone then 6 else 12, Parent = level })
	R.ladder = ladder

	-- Leaderboards: board list (left) + rows (right)
	local listW = if phone then 150 else 250
	local list = Instance.new("ScrollingFrame")
	list.Name = "BoardList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 2
	list.Selectable = false
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Size = UDim2.new(0, listW, 1, 0)
	list.Parent = boards
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, if phone then 6 else 10)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	local lp = Instance.new("UIPadding")
	lp.PaddingLeft, lp.PaddingTop, lp.PaddingRight = UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 6)
	lp.Parent = list
	R.boardCards = {}
	for i, b in ipairs(Progression.Boards) do
		local card = Instance.new("TextButton")
		card.Name = "Board_" .. b.id
		card.Text = ""
		card.AutoButtonColor = false
		card.BackgroundColor3 = Cards.Surface.Card.color
		card.BackgroundTransparency = Cards.Surface.Card.transparency
		card.Size = UDim2.new(1, 0, 0, if phone then 50 else 82)
		card.LayoutOrder = i
		card.SelectionImageObject = Cards.focusRing()
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, Cards.Corner.Card)
		cc.Parent = card
		local st = Instance.new("UIStroke")
		st.Name = "Edge"
		st.Color = Theme.Colors.Ink
		st.Transparency = 0.82
		st.Thickness = 1.5
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = card
		Cards.label(b.name, { Name = "Name", Font = Theme.Fonts.SemiBold, TextSize = if phone then 14 else 18,
			Position = UDim2.fromOffset(14, if phone then 6 else 18), Size = UDim2.new(1, -20, 0, 22), Parent = card })
		Cards.label(b.sub, { Name = "Sub", TextSize = if phone then 12 else 14, Color = Theme.Colors.Ink2,
			Position = UDim2.fromOffset(14, if phone then 26 else 42), Size = UDim2.new(1, -20, 0, 18), Parent = card })
		if b.later then
			card.BackgroundTransparency = 0.5
			card.Active = false
			card.Selectable = false
		else
			card.Activated:Connect(function()
				currentBoard = b.id
				if b.all and not b.week then
					currentScope = "all"
				elseif b.week and not b.all then
					currentScope = "week"
				end
				RanksController.renderBoards()
				ProgressUI.send({ t = "boards", board = currentBoard, scope = currentScope })
			end)
		end
		card.Parent = list
		R.boardCards[b.id] = card
	end
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.BackgroundTransparency = 1
	right.Position = UDim2.new(0, listW + (if phone then 8 else 34), 0, 0)
	right.Size = UDim2.new(1, -listW - (if phone then 8 else 34), 1, 0)
	right.Parent = boards
	local scope, sApi = Cards.tabs({ { key = "week", text = "This week" }, { key = "all", text = "All time" } },
		{ TextSize = if phone then 13 else 17, Parent = right })
	scopeApi = sApi
	sApi.onChanged(function(key)
		currentScope = key
		RanksController.renderBoards()
		ProgressUI.send({ t = "boards", board = currentBoard, scope = currentScope })
	end)
	R.scope = scope
	local meta = Cards.label("", { Name = "Meta", TextSize = if phone then 11 else 14, Color = Theme.Colors.Ink2,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.6, 0, 0, if phone then 40 else 44),
		Parent = right })
	meta.TextXAlignment = Enum.TextXAlignment.Right
	meta.TextWrapped = true
	R.meta = meta
	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.ScrollBarThickness = 3
	rows.ScrollBarImageTransparency = 0.7
	rows.Selectable = false
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.CanvasSize = UDim2.new()
	rows.Position = UDim2.fromOffset(0, if phone then 48 else 64)
	rows.Size = UDim2.new(1, 0, 1, if phone then -48 - 52 else -64 - 96)
	rows.Parent = right
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, if phone then 4 else 8)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = rows
	R.rows = rows
	local mine = Instance.new("Frame")
	mine.Name = "Mine"
	mine.BackgroundTransparency = 1
	mine.AnchorPoint = Vector2.new(0, 1)
	mine.Position = UDim2.new(0, 0, 1, if phone then 0 else -34)
	mine.Size = UDim2.new(1, 0, 0, if phone then 44 else 56)
	mine.Parent = right
	R.mine = mine
	if not phone then
		local foot = Cards.label("Only rounds with 8 or more real contenders count. The weekly top 48 on any board earns the <b>Top 48</b> title for the next week. The same boards stand on paper in the Lounge car.",
			{ Name = "Foot", TextSize = 13, Color = Theme.Colors.Ink2, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 28), Parent = right })
		foot.RichText = true
		foot.TextWrapped = true
	end

	api.onChanged(function(key)
		if key == "arena" then
			api.select("level", true)
			key = "level"
		end
		level.Visible = key == "level"
		boards.Visible = key == "boards"
		later.Visible = false
		if key == "boards" then
			RanksController.renderBoards()
			ProgressUI.send({ t = "boards", board = currentBoard, scope = currentScope })
		else
			RanksController.renderLevel()
		end
	end)
end

function RanksController.renderLevel()
	if not screen then
		return
	end
	local l = lv()
	local you, ladder = R.you, R.ladder
	clear(you)
	clear(ladder)
	if not l then
		return
	end
	local phone = screen.phone
	local band = l.band or 1
	local rank = Progression.Ranks[band]
	local yLab = Cards.label("YOU", { Font = Theme.Fonts.SemiBold, TextSize = if phone then 12 else 16, Color = Theme.Colors.Ink2,
		Position = UDim2.fromOffset(0, if phone then 6 else 22), Size = UDim2.new(1, 0, 0, 20), Parent = you })
	yLab.TextXAlignment = Enum.TextXAlignment.Center
	local emb = Instance.new("Frame")
	emb.Name = "EmblemWell"
	emb.BackgroundTransparency = 1
	emb.AnchorPoint = Vector2.new(0.5, 0)
	emb.Position = UDim2.new(0.5, 0, 0, if phone then 24 else 56)
	emb.Size = UDim2.fromOffset(if phone then 64 else 150, if phone then 64 else 150)
	emb.Parent = you
	ProgressUI.emblem(emb, band, nil, l.prestige).Size = UDim2.fromScale(1, 1)
	local name = Cards.label(rank.name, { Font = Theme.Fonts.Light, TextSize = if phone then 26 else 54,
		Position = UDim2.fromOffset(0, if phone then 88 else 212), Size = UDim2.new(1, 0, 0, if phone then 30 else 60), Parent = you })
	name.TextXAlignment = Enum.TextXAlignment.Center
	local lvLabel = Cards.label(string.format("Level %d%s", l.level, if (l.prestige or 0) > 0 then "  ·  ★" .. l.prestige else ""),
		{ Font = Theme.Fonts.Mono, TextSize = if phone then 14 else 20, Position = UDim2.fromOffset(0, if phone then 118 else 274),
			Size = UDim2.new(1, 0, 0, 24), Parent = you })
	lvLabel.TextXAlignment = Enum.TextXAlignment.Center
	local bar = Cards.bar({ Height = if phone then 6 else 8, Position = UDim2.new(0, 22, 0, if phone then 146 else 318),
		Size = UDim2.new(1, -44, 0, 8), Parent = you })
	Cards.setBar(bar, if l.need > 0 then l.into / l.need else 1)
	local xpText = if l.need > 0 then string.format("%s / %s XP to level %d · 100 Gold each level", Progression.comma(l.into),
		Progression.comma(l.need), l.level + 1) else "Level 100 · you may Prestige"
	local xp = Cards.label(xpText, { Font = Theme.Fonts.Mono, TextSize = if phone then 11 else 13, Color = Theme.Colors.Ink2,
		Position = UDim2.new(0, 22, 0, if phone then 156 else 334), Size = UDim2.new(1, -44, 0, 18), Parent = you })
	xp.TextWrapped = true
	if not phone then
		local nextRank = Progression.Ranks[band + 1]
		local y = 380
		if nextRank then
			Cards.section(string.format("Next rank: %s at level %d", nextRank.name, nextRank.level), { Position = UDim2.new(0, 22, 0, y),
				Size = UDim2.new(1, -44, 0, 24), TextSize = 15, Parent = you })
			local tilesRow = Instance.new("Frame")
			tilesRow.Name = "NextRewards"
			tilesRow.BackgroundTransparency = 1
			tilesRow.Position = UDim2.new(0, 22, 0, y + 32)
			tilesRow.Size = UDim2.new(1, -44, 0, 84)
			tilesRow.Parent = you
			local hl = Instance.new("UIListLayout")
			hl.FillDirection = Enum.FillDirection.Horizontal
			hl.Padding = UDim.new(0, 10)
			hl.SortOrder = Enum.SortOrder.LayoutOrder
			hl.Parent = tilesRow
			for i, r in ipairs(nextRank.rewards) do
				rewardTile(r, 80, tilesRow, i)
			end
			local goldTile = rewardTile({ k = "gold", n = 100 }, 80, tilesRow, 9)
			goldTile.Name = "LevelGold"
			y += 126
		end
		local rule = Cards.label("Levels never go down. At level 100 you may Prestige: back to level 1 with a star by your name (up to 10), keeping everything.",
			{ TextSize = 13, Color = Theme.Colors.Ink2, Position = UDim2.new(0, 22, 0, y), Size = UDim2.new(1, -44, 0, 40), Parent = you })
		rule.TextWrapped = true
	end
	if l.level >= 100 and (l.prestige or 0) < 10 then
		local p = Cards.button("Primary", "Prestige", { Name = "Prestige", AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14), Parent = you })
		Cards.hold(p, 1.2, function()
			ProgressUI.send({ t = "prestige" })
		end)
	end

	for i, r in ipairs(Progression.Ranks) do
		local card = Instance.new("TextButton")
		card.Name = "Rank" .. i
		card.Text = ""
		card.AutoButtonColor = false
		card.LayoutOrder = i
		card.BackgroundColor3 = Cards.Surface.Card.color
		card.BackgroundTransparency = if i < band then 0.4 else Cards.Surface.Card.transparency
		card.SelectionImageObject = Cards.focusRing()
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, Cards.Corner.Card)
		cc.Parent = card
		local st = Instance.new("UIStroke")
		st.Color = Theme.Colors.Ink
		st.Transparency = if i == band then 0 else 0.82
		st.Thickness = if i == band then 2 else 1.5
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = card
		local ew = Instance.new("Frame")
		ew.Name = "Well"
		ew.BackgroundColor3 = Cards.Surface.Well.color
		ew.BackgroundTransparency = Cards.Surface.Well.transparency
		ew.Position = UDim2.fromOffset(10, 10)
		ew.Size = UDim2.new(0, if phone then 56 else 76, 1, -20)
		local wc = Instance.new("UICorner")
		wc.CornerRadius = UDim.new(0, Cards.Corner.Tile)
		wc.Parent = ew
		ew.Parent = card
		local e = ProgressUI.emblem(ew, i)
		e.Size = UDim2.fromScale(0.78, 0.78)
		local fade = if i < band then 0.45 else 0
		local x = if phone then 74 else 98
		local n = Cards.label(r.name, { Font = Theme.Fonts.SemiBold, TextSize = if phone then 14 else 18,
			Position = UDim2.fromOffset(x, if phone then 6 else 12), Size = UDim2.new(1, -x - 8, 0, 22), Parent = card })
		n.TextTransparency = fade
		local m = Cards.label(string.format("Lv %d · %s XP", r.level, Progression.comma(Progression.totalFor(r.level))),
			{ Font = Theme.Fonts.Mono, TextSize = if phone then 11 else 13, Color = Theme.Colors.Ink2,
				Position = UDim2.fromOffset(x, if phone then 26 else 36), Size = UDim2.new(1, -x - 8, 0, 18), Parent = card })
		m.TextTransparency = fade
		local rl = Cards.label(rewardsLine(r.rewards), { TextSize = if phone then 11 else 13, Color = Theme.Colors.Ink2,
			Position = UDim2.fromOffset(x, if phone then 44 else 58), Size = UDim2.new(1, -x - 8, 0, if phone then 28 else 36), Parent = card })
		rl.TextWrapped = true
		rl.TextYAlignment = Enum.TextYAlignment.Top
		rl.TextTransparency = fade
		if i < band then
			Cards.label("✓", { TextSize = 16, Color = Theme.Colors.Ink2, AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(20, 20), Parent = card })
		end
		card.Parent = ladder
	end
end

local function boardView(): { [string]: any }?
	local v = R.view
	if v and v.board == currentBoard and v.scope == currentScope then
		return v
	end
	return nil
end

local function row(parent: Instance, r: { [string]: any }, mine: boolean, order: number, valueText: string): Frame
	local phone = screen.phone
	local f = Instance.new("Frame")
	f.Name = "Row" .. order
	f.LayoutOrder = order
	f.BackgroundColor3 = if mine then Color3.fromRGB(46, 38, 24) else Cards.Surface.Card.color
	f.BackgroundTransparency = if mine then 0.2 else Cards.Surface.Card.transparency + 0.1
	f.Size = UDim2.new(1, -6, 0, if phone then 40 else 56)
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 8)
	cc.Parent = f
	if mine then
		local st = Instance.new("UIStroke")
		st.Color = Theme.Colors.Sun
		st.Thickness = 1.5
		st.Parent = f
	end
	local top = (r.place or 99) <= 3
	local place = Cards.label(if r.place then tostring(r.place) else "—", { Font = Theme.Fonts.MonoMedium,
		TextSize = if phone then 15 else 20, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 56, 1, 0), Parent = f })
	place.TextTransparency = if top or mine then 0 else 0.25
	-- the name on its strip (the banner backing once banners are on the boards)
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundColor3 = Color3.fromRGB(72, 78, 84)
	strip.BackgroundTransparency = if top then 0.1 else 0.35
	strip.Position = UDim2.new(0, if phone then 52 else 76, 0.5, if phone then -14 else -20)
	strip.Size = UDim2.new(0.42, 0, 0, if phone then 28 else 40)
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 4)
	sc.Parent = strip
	strip.Parent = f
	local who = Cards.label((if mine then "You · " else "") .. tostring(r.name or "?"), { Font = Theme.Fonts.SemiBold,
		TextSize = if phone then 13 else 17, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -16, 1, 0), Parent = strip })
	who.TextTruncate = Enum.TextTruncate.AtEnd
	who.TextTransparency = if top or mine then 0 else 0.15
	-- the rank emblem (players on this server; others show none)
	if r.rank and type(r.rank) == "table" and r.rank.rank then
		local band = 1
		for i, rk in ipairs(Progression.Ranks) do
			if rk.name == r.rank.rank then
				band = i
			end
		end
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.new(0.42, if phone then 60 else 92, 0.5, if phone then -14 else -18)
		holder.Size = UDim2.fromOffset(if phone then 28 else 36, if phone then 28 else 36)
		holder.Parent = f
		ProgressUI.emblem(holder, band).Size = UDim2.fromScale(1, 1)
	end
	local value = Cards.label(valueText, { Font = Theme.Fonts.MonoMedium, TextSize = if phone then 15 else 20,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0, 140, 1, 0), Parent = f })
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextTransparency = if top or mine then 0 else 0.2
	f.Parent = parent
	return f
end

local function valueText(boardId: string, v: number?): string
	if v == nil then
		return "—"
	end
	local b = Progression.board(boardId)
	if b and b.time then
		return string.format("%d:%02d", math.floor(v / 60), v % 60)
	elseif b and b.level then
		local p = math.floor(v / 1000)
		return if p > 0 then string.format("★%d · %d", p, v % 1000) else tostring(v % 1000)
	end
	return Progression.comma(v)
end

function RanksController.renderBoards()
	if not screen then
		return
	end
	local b = Progression.board(currentBoard)
	for id, card in pairs(R.boardCards) do
		local edge = card:FindFirstChild("Edge") :: UIStroke
		edge.Transparency = if id == currentBoard then 0 else 0.82
		edge.Thickness = if id == currentBoard then 2 else 1.5
	end
	if scopeApi and b then
		scopeApi.buttons.week.Visible = b.week == true
		scopeApi.buttons.all.Visible = b.all == true
		scopeApi.select(currentScope, true)
	end
	local rows, mine = R.rows, R.mine
	clear(rows)
	clear(mine)
	local v = boardView()
	if not v then
		R.meta.Text = "reading the board…"
		return
	end
	local week = tostring(v.week or "")
	local left = math.max(0, (v.resetAt or 0) - os.time())
	R.meta.Text = if currentScope == "week"
		then string.format("Week %s · resets Monday 00:00 UTC · %s · updated every %d min", string.sub(week, 6), Cards.clock(left),
			math.floor((v.every or 120) / 60))
		else string.format("All time · updated every %d min", math.floor((v.every or 120) / 60))
	local onPage = false
	local shown = v.rows or {}
	if #shown == 0 then
		local empty = Cards.label(if currentScope == "week" then "No one on this board yet this week. Rounds with 8 or more real contenders count."
			else "No one on this board yet.", { TextSize = 15, Color = Theme.Colors.Ink2, Size = UDim2.new(1, 0, 0, 40), Parent = rows })
		empty.TextWrapped = true
	end
	for i, r in ipairs(shown) do
		local isMe = r.userId == player.UserId
		onPage = onPage or isMe
		row(rows, r, isMe, i, valueText(currentBoard, r.value))
	end
	if not onPage then
		local me = { place = v.place, name = player.Name, rank = { rank = player:GetAttribute("RankName") } }
		local f = row(mine, me, true, 1, valueText(currentBoard, v.value))
		f.Size = UDim2.fromScale(1, 1)
		if not v.place then
			local note = Cards.label(string.format("not in the top %d", v.top or 50), { TextSize = 12, Color = Theme.Colors.Ink2,
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -170, 0.5, 0), Size = UDim2.fromOffset(160, 20), Parent = f })
			note.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
end

function RanksController.open(tab: string?, board: string?, scope: string?): boolean
	if not screen then
		return false
	end
	if board and Progression.board(board) then
		currentBoard = board
	end
	if scope == "all" or scope == "week" then
		currentScope = scope
	end
	if Cards.metrics().phone ~= screen.phone then
		RanksController.rebuild() -- built before the window had its size, or the device class changed
	end
	local ok = screen.open()
	if not ok then
		return false
	end
	local key = tab or "level"
	tabsApi.select(key, true)
	R.level.Visible = key == "level"
	R.boards.Visible = key == "boards"
	if key == "boards" then
		RanksController.renderBoards()
		ProgressUI.send({ t = "boards", board = currentBoard, scope = currentScope })
	else
		RanksController.renderLevel()
	end
	unbindShoulders = Cards.bindShoulders("RanksShoulders", function()
		tabsApi.step(-1)
	end, function()
		tabsApi.step(1)
	end)
	if ProgressUI.isGamepad() then
		GuiService.SelectedObject = if key == "boards" then R.boardCards[currentBoard] else tabsApi.buttons[key]
	end
	return true
end

function RanksController.close()
	if screen then
		screen.close()
	end
end

-- builds the screen again (after the device class changes; tests)
function RanksController.rebuild()
	if screen then
		screen.close()
		screen.gui:Destroy()
	end
	local view = R.view
	R = { view = view }
	build()
end

function RanksController.isOpen(): boolean
	return screen ~= nil and screen.isOpen()
end

--------------------------------------------------------------------------------------------------------------------
-- The rank-up moment
--------------------------------------------------------------------------------------------------------------------

local function buildMoment(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RankUpGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 45
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Theme.Colors.Shade
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 0
	dim.Parent = gui
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 2
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = root
	gui.Parent = player:WaitForChild("PlayerGui")
	Theme.bindRoot(gui)
	return gui
end

function RanksController.showRankUp(msg: { [string]: any })
	local gui = momentGui
	if not gui or momentShowing then
		return
	end
	momentShowing = true
	pendingRankUp = nil
	local root = gui:FindFirstChild("Root") :: Frame
	clear(root)
	local band = math.clamp(tonumber(msg.band) or 1, 1, 10)
	local rank = Progression.Ranks[band]
	local m = Cards.metrics()
	local phone = m.phone
	local col = Instance.new("Frame")
	col.Name = "Moment"
	col.BackgroundTransparency = 1
	col.AnchorPoint = Vector2.new(0.5, 0.5)
	col.Position = UDim2.fromScale(0.5, 0.5)
	col.Size = UDim2.fromOffset(560, if phone then 330 else 520)
	col.Parent = root
	local word = Cards.label("RANK UP", { Font = Theme.Fonts.SemiBold, TextSize = if phone then 15 else 18, Color = Theme.Colors.Sun,
		Size = UDim2.new(1, 0, 0, 24), Parent = col })
	word.TextXAlignment = Enum.TextXAlignment.Center
	local emWell = Instance.new("Frame")
	emWell.Name = "EmblemWell"
	emWell.BackgroundTransparency = 1
	emWell.AnchorPoint = Vector2.new(0.5, 0)
	emWell.Position = UDim2.new(0.5, 0, 0, if phone then 30 else 40)
	emWell.Size = UDim2.fromOffset(if phone then 96 else 170, if phone then 96 else 170)
	emWell.Parent = col
	local emblem = ProgressUI.emblem(emWell, band, nil, msg.prestige)
	emblem.Size = UDim2.fromScale(0.2, 0.2)
	emblem.Rotation = -90
	local name = Cards.label(rank.name, { Font = Theme.Fonts.Light, TextSize = if phone then 40 else 60,
		Position = UDim2.fromOffset(0, if phone then 132 else 222), Size = UDim2.new(1, 0, 0, if phone then 46 else 70), Parent = col })
	name.TextXAlignment = Enum.TextXAlignment.Center
	local lvl = Cards.label("Level " .. tostring(msg.level or rank.level), { Font = Theme.Fonts.Mono, TextSize = if phone then 15 else 20,
		Position = UDim2.fromOffset(0, if phone then 178 else 296), Size = UDim2.new(1, 0, 0, 26), Parent = col })
	lvl.TextXAlignment = Enum.TextXAlignment.Center
	local tilesRow = Instance.new("Frame")
	tilesRow.Name = "Rewards"
	tilesRow.BackgroundTransparency = 1
	tilesRow.Position = UDim2.fromOffset(0, if phone then 210 else 340)
	tilesRow.Size = UDim2.new(1, 0, 0, if phone then 64 else 100)
	tilesRow.Parent = col
	local hl = Instance.new("UIListLayout")
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hl.Padding = UDim.new(0, 14)
	hl.SortOrder = Enum.SortOrder.LayoutOrder
	hl.Parent = tilesRow
	local rewards = if type(msg.rewards) == "table" then msg.rewards else {}
	local equipId: string? = nil
	local equipName: string? = nil
	for _, r in ipairs(rewards) do
		if r.k == "cosmetic" and not equipId then
			equipId = r.id
			equipName = Progression.rewardText(r)
		end
	end
	local buttonText = if equipName then "Equip " .. equipName else "Continue"
	local button = Cards.button("Primary", buttonText, { Name = "Go", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if phone then 284 else 462), Parent = col })
	button.Visible = false

	-- in: the dim, the emblem turns in, the bell, then the tiles one by one
	local dim = gui:FindFirstChild("Dim") :: Frame
	gui.Enabled = true
	ProgressUI.setModal("RankUp", true) -- the lobby's own words step aside while it shows
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.3 }):Play()
	for _, l in ipairs({ word, name, lvl }) do
		l.TextTransparency = 1
		TweenService:Create(l, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.35),
			{ TextTransparency = 0 }):Play()
	end
	TweenService:Create(emblem, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1, 1), Rotation = 0 }):Play()
	Sfx.play("FeastBell", { volume = 0.35, pitch = 0.78 })
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		ProgressUI.send({ t = "rankSeen" })
		local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(dim, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(col, fade, { Position = UDim2.fromScale(0.08, 0.06), Size = UDim2.fromOffset(0, 0) }):Play()
		task.delay(0.4, function()
			gui.Enabled = false
			clear(root)
			momentShowing = false
			ProgressUI.setModal("RankUp", false)
		end)
	end
	button.Activated:Connect(function()
		if equipId then
			local cos = ProgressUI.Controllers and ProgressUI.Controllers.CosmeticsController
			if cos and type(cos.equip) == "function" then
				pcall(cos.equip, equipId)
			end
		end
		finish()
	end)
	task.spawn(function()
		task.wait(0.7)
		for i, r in ipairs(rewards) do
			if done then
				return
			end
			local t = rewardTile(r, if phone then 60 else 92, tilesRow, i)
			Cards.setState(t, "New", true)
			task.wait(0.22)
		end
		button.Visible = true
		if ProgressUI.isGamepad() then
			GuiService.SelectedObject = button
		end
		-- three quiet seconds, then it folds away by itself
		local t0 = os.clock()
		while not done and os.clock() - t0 < 3 do
			task.wait(0.1)
		end
		finish()
	end)
end

local function tryMoment()
	if pendingRankUp and not momentShowing and ProgressUI.inTrain() and not ClientState.menuOpen then
		RanksController.showRankUp(pendingRankUp)
	end
end

-- the quiet level-up line (bottom centre, in the train)
local function showLine(text: string)
	local gui = lineGui
	if not gui then
		return
	end
	local label = gui:FindFirstChild("Line") :: TextLabel
	label.Text = text
	label.TextTransparency = 1
	gui.Enabled = true
	TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	task.delay(3.5, function()
		if label.Text == text then
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
	end)
end

local function tryLine()
	if pendingLine and ProgressUI.inTrain() and not ClientState.menuOpen and not momentShowing then
		local t = pendingLine
		pendingLine = nil
		showLine(t)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The rank over heads in the train, and the flash when someone ranks up
--------------------------------------------------------------------------------------------------------------------

local tags: { [Player]: BillboardGui } = {}

local function tagFor(other: Player): BillboardGui?
	local character = other.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local existing = tags[other]
	if existing and existing.Parent == head then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "RankTag"
	bb.Adornee = head
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 36
	bb.Size = UDim2.new(3.2, 0, 0.62, 0) -- studs: it shrinks with distance like the world (quiet, never a big label)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1.7, 0)
	bb.ResetOnSpawn = false
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = bb
	local hl = Instance.new("UIListLayout")
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hl.VerticalAlignment = Enum.VerticalAlignment.Center
	hl.Padding = UDim.new(0, 4)
	hl.SortOrder = Enum.SortOrder.LayoutOrder
	hl.Parent = row
	local em = Instance.new("Frame")
	em.Name = "EmblemHolder"
	em.BackgroundTransparency = 1
	em.Size = UDim2.fromScale(0.26, 1)
	em.LayoutOrder = 1
	em.Parent = row
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = em
	local text = Cards.label("", { Name = "Level", Font = Theme.Fonts.SemiBold, TextSize = 13, LayoutOrder = 2,
		Size = UDim2.fromScale(0.7, 0.8), Parent = row })
	text.TextScaled = true
	Theme.shadow(text)
	bb.Parent = head
	tags[other] = bb
	return bb
end

local function refreshTag(other: Player)
	local level = other:GetAttribute("Level")
	local mineOut = ProgressUI.inTrain()
	local theirsOut = other:GetAttribute("InArena") ~= true
	-- (your own tag shows only in a Studio test: Workspace attribute RankTagSelf = true)
	local show = type(level) == "number" and mineOut and theirsOut
		and (other ~= player or workspace:GetAttribute("RankTagSelf") == true)
	if not show then
		local old = tags[other]
		if old then
			old.Enabled = false
		end
		return
	end
	local bb = tagFor(other)
	if not bb then
		return
	end
	bb.Enabled = true
	local band = tonumber(other:GetAttribute("RankBand")) or 1
	local holder = bb.Row.EmblemHolder :: Frame
	if holder:GetAttribute("Band") ~= band then
		clear(holder)
		ProgressUI.emblem(holder, band).Size = UDim2.fromScale(1, 1)
		holder:SetAttribute("Band", band)
	end
	local prestige = tonumber(other:GetAttribute("Prestige")) or 0
	bb.Row.Level.Text = string.format("%sLv %d", if prestige > 0 then "★" .. prestige .. " " else "", level)
end

local function flash(other: Player)
	if not ProgressUI.inTrain() or other:GetAttribute("InArena") == true then
		return
	end
	local character = other.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "RankUpFlash"
	bb.Adornee = head :: BasePart
	bb.Size = UDim2.fromOffset(44, 44)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 60
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = bb
	local e = ProgressUI.emblem(holder, tonumber(other:GetAttribute("RankBand")) or 1)
	e.Size = UDim2.fromScale(0.4, 0.4)
	bb.Parent = head
	TweenService:Create(e, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromScale(1, 1) }):Play()
	task.delay(1.6, function()
		for _, d in ipairs(e:GetDescendants()) do
			if d:IsA("Frame") then
				TweenService:Create(d, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			end
		end
	end)
	task.delay(2.05, function()
		bb:Destroy()
	end)
end

local function watch(other: Player)
	for _, a in ipairs({ "Level", "RankBand", "Prestige", "InArena" }) do
		other:GetAttributeChangedSignal(a):Connect(function()
			refreshTag(other)
		end)
	end
	other:GetAttributeChangedSignal("RankUpAt"):Connect(function()
		flash(other)
	end)
	other.CharacterAdded:Connect(function()
		task.wait(1)
		refreshTag(other)
	end)
	refreshTag(other)
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function RanksController.Init(controllers)
	ProgressUI.Controllers = ProgressUI.Controllers or controllers
end

function RanksController.Start()
	build()
	ProgressUI.openers.ranks = function(arg)
		if arg == "phone" then
			RanksController.rebuild()
		end
		RanksController.open("level")
	end
	ProgressUI.openers.boards = function(board, scope)
		RanksController.open("boards", board, scope)
	end
	ProgressUI.openers.rankup = function(band)
		local b = tonumber(band) or 2
		RanksController.showRankUp({ band = b, level = Progression.Ranks[b].level, rewards = Progression.Ranks[b].rewards })
	end
	ProgressUI.openers.close = function()
		RanksController.close()
	end
	momentGui = buildMoment()
	-- the level-up line
	local lg = Instance.new("ScreenGui")
	lg.Name = "LevelLineGui"
	lg.ResetOnSpawn = false
	lg.DisplayOrder = 12
	lg.Enabled = false
	local line = Cards.label("", { Name = "Line", Font = Theme.Fonts.Medium, TextSize = 16, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -118), Size = UDim2.fromOffset(420, 24), Parent = lg })
	line.TextXAlignment = Enum.TextXAlignment.Center
	Theme.shadow(line)
	lg.Parent = player:WaitForChild("PlayerGui")
	lineGui = lg

	screen.onClose(function()
		if unbindShoulders then
			unbindShoulders()
			unbindShoulders = nil
		end
		task.delay(0.3, tryMoment)
	end)
	ProgressUI.stateChanged:Connect(function()
		if screen.isOpen() and R.level.Visible then
			RanksController.renderLevel()
		end
	end)
	ProgressUI.on("boards", function(msg)
		R.view = msg
		if screen.isOpen() and R.boards.Visible then
			RanksController.renderBoards()
		end
	end)
	ProgressUI.on("rankup", function(msg)
		pendingRankUp = msg
		tryMoment()
	end)
	ProgressUI.on("levelup", function(msg)
		pendingLine = string.format("Level %d · +%s Gold", tonumber(msg.level) or 0, Progression.comma(tonumber(msg.gold) or 0))
		tryLine()
	end)
	ClientState.lifeChanged:Connect(function()
		task.delay(2, tryMoment)
		task.delay(2.5, tryLine)
		for _, other in ipairs(Players:GetPlayers()) do
			refreshTag(other)
		end
	end)
	-- the paper boards: E opens this menu on that board
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player or prompt.Name ~= "Leaderboards" then
			return
		end
		local model = prompt.Parent and prompt.Parent.Parent
		local board = model and model:GetAttribute("Board")
		local scope = model and model:GetAttribute("Scope")
		RanksController.open("boards", if type(board) == "string" then board else nil, if type(scope) == "string" then scope else nil)
	end)
	for _, other in ipairs(Players:GetPlayers()) do
		watch(other)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(other)
		local bb = tags[other]
		if bb then
			bb:Destroy()
		end
		tags[other] = nil
	end)
	while true do
		task.wait(1)
		tryMoment()
		tryLine()
	end
end

return RanksController
