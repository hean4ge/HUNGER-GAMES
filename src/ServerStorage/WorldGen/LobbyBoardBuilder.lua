--[[
	LobbyBoardBuilder - turns one of the lobby's two notice boards into the results board (edit time only).
	The owner (18 Nov 2026): the result "shouldnt pop up after the game it can appear on one of the physical boards".

	Which board: workspace.Lobby.Landmarks holds two "NoticeBoard" models (the same Blender prop, asset
	122335015926239), each with a clear "NoticeFace" part carrying the rules on a SurfaceGui "Notice". The results
	board is the one nearest RESULTS_AT: the board at (8814.8, 168, -14.8), whose face looks toward the spawn pads
	Spawn1 and Spawn2 (players respawn facing the plaza's middle with it in front of them). The other board, the one
	facing Spawn5 and Spawn6, keeps the rules.

	What build() changes, and nothing else (no mesh, no terrain, no other prop):
	  * on that board's NoticeFace: the old SurfaceGui "Notice" is turned off (Enabled = false, kept for unbuild)
	  * a new SurfaceGui "Results" on the same face: the paper face of docs/design/ui/StyleA_Quiet/board.html,
	    1600 x 956 (the face is 8.2 x 4.9 studs), matte (lit by the world: LightInfluence 1), Quiet type
	  * the face part gets the CollectionService tag "ResultsBoard" and the attribute ResultsBoard = true; the
	    board model gets the attribute Role = "Results"
	The words are written on each client by Controllers/ResultsBoardController (so every player sees their own row
	marked), from ResultsBoardService's last result. As built here the board shows its empty face.

	The tree (ResultsBoardController looks these up by name):
	  Results (SurfaceGui) > Paper (Frame)
	    Top > Heading ("LAST ROUND"), Meta ("24 contenders · 3 days · 9:41")
	    RuleTop
	    Winner > Label ("WINNER"), Head (ImageLabel, the winner's headshot), Who (the name), Sub
	    Table > Header > Place, Who, Defeats, Survived
	            Row1..Row5, Gap > Dot1..Dot3, You         each row: Band, Bar, Line, Place, Who, Defeats, Survived
	    RuleBottom
	    Facts > Fact1..Fact4                               each: Label, Value
	    Empty (the line shown before the first round has ended)

	Edit mode (after the scripts are in Studio):
	  return require(game.ServerStorage.WorldGen.LobbyBoardBuilder:Clone()).build()
	  return require(game.ServerStorage.WorldGen.LobbyBoardBuilder:Clone()).preview()   -- sample words, to look at
	  return require(game.ServerStorage.WorldGen.LobbyBoardBuilder:Clone()).unbuild()   -- back to the rules board
	(build() after preview() puts the empty face back.)
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyBoardBuilder = {}

local RESULTS_AT = Vector3.new(8814.8, 168, -14.8)
local TAG = "ResultsBoard"
local CANVAS = Vector2.new(1600, 956)

local function loadTheme(): any
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("Theme")
	if module and module:IsA("ModuleScript") then
		-- a clone: Studio's module cache must not serve an older Theme after a push
		local ok, theme = pcall(require, module:Clone())
		if ok and type(theme) == "table" then
			return theme
		end
	end
	return nil
end

local function colors(theme: any)
	local C = theme and theme.Colors or {}
	return {
		paper = C.Paper or Color3.fromRGB(234, 229, 217),
		ink = C.PaperInk or Color3.fromRGB(35, 39, 43),
		bar = C.PaperBar or Color3.fromRGB(201, 138, 34),
		tag = C.PaperTag or Color3.fromRGB(138, 92, 16),
		sun = C.Sun or Color3.fromRGB(232, 182, 90),
		head = Color3.fromRGB(122, 91, 72),
	}
end

local function fonts(theme: any)
	local F = theme and theme.Fonts or {}
	local montserrat = "rbxasset://fonts/families/Montserrat.json"
	local mono = "rbxasset://fonts/families/RobotoMono.json"
	return {
		Light = F.Light or Font.new(montserrat, Enum.FontWeight.Light),
		Regular = F.Regular or Font.new(montserrat, Enum.FontWeight.Regular),
		Medium = F.Medium or Font.new(montserrat, Enum.FontWeight.Medium),
		SemiBold = F.SemiBold or Font.new(montserrat, Enum.FontWeight.SemiBold),
		Mono = F.Mono or Font.new(mono, Enum.FontWeight.Regular),
	}
end

-- the NoticeBoard nearest RESULTS_AT, and its face part
local function findBoard(): (Model?, BasePart?)
	local lobby = workspace:FindFirstChild("Lobby")
	local landmarks = lobby and lobby:FindFirstChild("Landmarks")
	if not landmarks then
		return nil, nil
	end
	local best, bestFace, bestDistance = nil, nil, math.huge
	for _, model in ipairs(landmarks:GetChildren()) do
		if model:IsA("Model") and model.Name == "NoticeBoard" then
			local face = model:FindFirstChild("NoticeFace")
			if face and face:IsA("BasePart") then
				local d = (face.Position - RESULTS_AT).Magnitude
				if d < bestDistance then
					best, bestFace, bestDistance = model, face, d
				end
			end
		end
	end
	return best, bestFace
end

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function buildFace(face: BasePart, theme: any): SurfaceGui
	local K = colors(theme)
	local F = fonts(theme)
	local SOFT = 0.34 -- the soft paper ink (66%)

	local function frame(name: string, parent: Instance, props: { [string]: any }?): Frame
		local p = props or {}
		p.Name = name
		p.Parent = parent
		if p.BackgroundTransparency == nil then
			p.BackgroundTransparency = 1
		end
		p.BorderSizePixel = 0
		return new("Frame", p)
	end
	local function text(name: string, parent: Instance, font: string, size: number, props: { [string]: any }?): TextLabel
		local p = props or {}
		p.Name = name
		p.Parent = parent
		p.FontFace = F[font]
		p.TextSize = size
		p.TextColor3 = p.TextColor3 or K.ink
		p.BackgroundTransparency = 1
		p.BorderSizePixel = 0
		p.TextXAlignment = p.TextXAlignment or Enum.TextXAlignment.Left
		p.TextYAlignment = p.TextYAlignment or Enum.TextYAlignment.Center
		p.Text = p.Text or ""
		return new("TextLabel", p)
	end
	local function rule(name: string, parent: Instance, y: number, transparency: number): Frame
		return frame(name, parent, {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = K.ink,
			BackgroundTransparency = transparency,
		})
	end

	local gui = new("SurfaceGui", {
		Name = "Results",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = CANVAS,
		LightInfluence = 1, -- lit by the world: matte, never a glowing screen
		Brightness = 1,
		AlwaysOnTop = false,
		ClipsDescendants = true,
		MaxDistance = 140,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local paper = frame("Paper", gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.paper, BackgroundTransparency = 0 })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 60),
		PaddingRight = UDim.new(0, 60),
		PaddingTop = UDim.new(0, 50),
		Parent = paper,
	})

	-- top line
	local top = frame("Top", paper, { Size = UDim2.new(1, 0, 0, 46) })
	text("Heading", top, "SemiBold", 30, { Size = UDim2.new(0.4, 0, 1, 0), Text = "LAST ROUND" })
	text("Meta", top, "SemiBold", 30, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTransparency = SOFT,
		RichText = true,
	})
	rule("RuleTop", paper, 64, 0.72)

	-- the winner, at the left
	local COLS_Y, COLS_H = 100, 640
	local winner = frame("Winner", paper, { Position = UDim2.fromOffset(0, COLS_Y), Size = UDim2.fromOffset(600, COLS_H) })
	text("Label", winner, "SemiBold", 30, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 36), Text = "WINNER", TextTransparency = SOFT })
	local head = new("ImageLabel", {
		Name = "Head",
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.fromOffset(160, 160),
		BackgroundColor3 = K.head,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		Parent = winner,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 16), Parent = head })
	local name = text("Who", winner, "Light", 124, {
		Position = UDim2.fromOffset(-6, 268),
		Size = UDim2.new(1, -20, 0, 140),
		TextScaled = true,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	new("UITextSizeConstraint", { MaxTextSize = 124, MinTextSize = 56, Parent = name })
	text("Sub", winner, "Medium", 32, { Position = UDim2.fromOffset(0, 424), Size = UDim2.new(1, -20, 0, 44), RichText = true })

	-- the table, at the right
	local tableFrame = frame("Table", paper, { Position = UDim2.fromOffset(600, COLS_Y + 22), Size = UDim2.new(1, -600, 0, COLS_H - 22) })
	local function cells(row: Frame, font: string, size: number, transparency: number?, mono: boolean?)
		local numberFont = if mono then "Mono" else font
		text("Place", row, numberFont, size, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(0, 76, 1, 0), TextTransparency = transparency, ZIndex = 3 })
		text("Who", row, font, size, {
			Position = UDim2.fromOffset(98, 0),
			Size = UDim2.new(1, -98 - 22 - 430, 1, 0),
			TextTransparency = transparency,
			TextTruncate = Enum.TextTruncate.AtEnd,
			RichText = true,
			ZIndex = 3,
		})
		text("Defeats", row, numberFont, size, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -22 - 230, 0, 0),
			Size = UDim2.new(0, 200, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTransparency = transparency,
			ZIndex = 3,
		})
		text("Survived", row, numberFont, size, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -22, 0, 0),
			Size = UDim2.new(0, 230, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTransparency = transparency,
			ZIndex = 3,
		})
	end
	local header = frame("Header", tableFrame, { Size = UDim2.new(1, 0, 0, 48) })
	cells(header, "SemiBold", 30, SOFT)
	header.Who.Text = "CONTENDER"
	header.Defeats.Text = "DEFEATS"
	header.Survived.Text = "SURVIVED"
	header.Place.Text = ""
	frame("Line", header, { Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = K.ink, BackgroundTransparency = 0.72 })

	local ROW_H = 76
	local function row(rowName: string, y: number): Frame
		local r = frame(rowName, tableFrame, { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, ROW_H) })
		-- your own row: a soft Sun band and a bar at its left edge (ResultsBoardController shows them)
		frame("Band", r, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.sun, BackgroundTransparency = 0.58, Visible = false, ZIndex = 1 })
		frame("Bar", r, { Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = K.bar, BackgroundTransparency = 0, Visible = false, ZIndex = 2 })
		frame("Line", r, { Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = K.ink, BackgroundTransparency = 0.88, ZIndex = 2 })
		cells(r, "Medium", 40, nil, true)
		r.Visible = false
		return r
	end
	for i = 1, 5 do
		row("Row" .. i, 48 + (i - 1) * ROW_H)
	end
	local gapY = 48 + 5 * ROW_H
	local gap = frame("Gap", tableFrame, { Position = UDim2.fromOffset(28, gapY), Size = UDim2.fromOffset(120, 40), Visible = false })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 9),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gap,
	})
	for i = 1, 3 do
		local dot = frame("Dot" .. i, gap, { Size = UDim2.fromOffset(7, 7), BackgroundColor3 = K.ink, BackgroundTransparency = 0.55, LayoutOrder = i })
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
	end
	row("You", gapY + 40)

	-- the round's facts
	local factsY = COLS_Y + COLS_H + 4
	rule("RuleBottom", paper, factsY, 0.72)
	local facts = frame("Facts", paper, { Position = UDim2.fromOffset(0, factsY + 30), Size = UDim2.new(1, 0, 0, 100) })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = facts,
	})
	for i = 1, 4 do
		local fact = frame("Fact" .. i, facts, { Size = UDim2.new(0.25, -12, 1, 0), LayoutOrder = i })
		text("Label", fact, "SemiBold", 30, { Size = UDim2.new(1, 0, 0, 38), TextTransparency = SOFT, TextTruncate = Enum.TextTruncate.AtEnd })
		text("Value", fact, "Medium", 38, { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 46), TextTruncate = Enum.TextTruncate.AtEnd, RichText = true })
	end

	-- before the first round of this server has ended
	text("Empty", paper, "Medium", 40, {
		Position = UDim2.fromOffset(0, COLS_Y + 60),
		Size = UDim2.new(1, 0, 0, 120),
		TextWrapped = true,
		TextTransparency = SOFT,
		Text = "The result of each round is posted here.",
		Visible = true,
	})

	gui.Parent = face
	return gui
end

-- the empty face: what the board shows until a round has ended (ResultsBoardController does the same at run time)
local function setEmpty(gui: SurfaceGui)
	local paper = gui:FindFirstChild("Paper") :: any
	if not paper then
		return
	end
	paper.Top.Meta.Text = ""
	paper.Winner.Visible = false
	paper.Table.Visible = false
	paper.RuleBottom.Visible = false
	paper.Facts.Visible = false
	paper.Empty.Visible = true
end

function LobbyBoardBuilder.build(): string
	local model, face = findBoard()
	if not model or not face then
		return "LobbyBoardBuilder: no NoticeBoard with a NoticeFace in workspace.Lobby.Landmarks; nothing built"
	end
	local theme = loadTheme()
	local old = face:FindFirstChild("Results")
	if old then
		old:Destroy()
	end
	local notice = face:FindFirstChild("Notice")
	if notice and notice:IsA("SurfaceGui") then
		notice.Enabled = false -- kept for unbuild()
	end
	local gui = buildFace(face, theme)
	setEmpty(gui)
	face:SetAttribute("ResultsBoard", true)
	CollectionService:AddTag(face, TAG)
	model:SetAttribute("Role", "Results")
	return string.format("LobbyBoardBuilder built: %s (face at %.1f, %.1f, %.1f), %d parts in Results%s",
		model:GetFullName(), face.Position.X, face.Position.Y, face.Position.Z, #gui:GetDescendants(),
		if theme then "" else " (Theme not found: built with its own colours)")
end

-- Sample words, to look at the face in Edit mode (screen_capture). build() puts the empty face back.
function LobbyBoardBuilder.preview(): string
	local _, face = findBoard()
	local gui = face and face:FindFirstChild("Results")
	if not gui then
		LobbyBoardBuilder.build()
		gui = face and face:FindFirstChild("Results")
	end
	local paper = gui and (gui :: any):FindFirstChild("Paper")
	if not paper then
		return "LobbyBoardBuilder.preview: no board"
	end
	local sample = {
		{ "1", "Kestrel", "5", "9:41" }, { "2", "Rowan", "3", "9:38" }, { "3", "Juniper", "2", "8:05" },
		{ "4", "Flint", "0", "7:44" }, { "5", "Wren", "1", "7:12" },
	}
	paper.Top.Meta.Text = "24 contenders  ·  3 days  ·  9:41"
	paper.Winner.Visible = true
	paper.Winner.Who.Text = "Kestrel"
	paper.Winner.Sub.Text = "5 defeats  ·  survived 9:41"
	paper.Table.Visible = true
	for i, s in ipairs(sample) do
		local r = paper.Table["Row" .. i]
		r.Visible = true
		r.Place.Text, r.Who.Text, r.Defeats.Text, r.Survived.Text = s[1], s[2], s[3], s[4]
	end
	paper.Table.Gap.Visible = true
	local you = paper.Table.You
	you.Visible = true
	you.Band.Visible, you.Bar.Visible = true, true
	you.Place.Text, you.Defeats.Text, you.Survived.Text = "9", "1", "6:12"
	you.Who.Text = string.format("Ash<font color=\"#%s\" size=\"30\">   YOU</font>", Color3.fromRGB(138, 92, 16):ToHex())
	for _, label in ipairs({ you.Place, you.Who, you.Defeats, you.Survived }) do
		label.FontFace = Font.new(label.FontFace.Family, Enum.FontWeight.SemiBold)
	end
	paper.RuleBottom.Visible = true
	paper.Facts.Visible = true
	local facts = { { "FIRST TO FALL", "Orla, 0:14" }, { "MOST DEFEATS", "Kestrel, 5" }, { "CAUGHT BY THE BORDER", "4" }, { "FELL IN THE FIRST MINUTE", "7" } }
	for i, f in ipairs(facts) do
		paper.Facts["Fact" .. i].Label.Text = f[1]
		paper.Facts["Fact" .. i].Value.Text = f[2]
	end
	paper.Empty.Visible = false
	return "LobbyBoardBuilder.preview: sample words on the results board (run build() to clear them)"
end

function LobbyBoardBuilder.unbuild(): string
	local model, face = findBoard()
	if not face then
		return "LobbyBoardBuilder.unbuild: no board"
	end
	local gui = face:FindFirstChild("Results")
	if gui then
		gui:Destroy()
	end
	local notice = face:FindFirstChild("Notice")
	if notice and notice:IsA("SurfaceGui") then
		notice.Enabled = true
	end
	face:SetAttribute("ResultsBoard", nil)
	CollectionService:RemoveTag(face, TAG)
	if model then
		model:SetAttribute("Role", nil)
	end
	return "LobbyBoardBuilder.unbuild: the rules are back on " .. (if model then model:GetFullName() else "the board")
end

return LobbyBoardBuilder
