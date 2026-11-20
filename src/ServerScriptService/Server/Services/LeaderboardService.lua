--[[
	LeaderboardService - six leaderboards on OrderedDataStores, the Leaderboards menu's data and three paper boards in
	the Lounge car (docs/design/CardMenusAndShop.md 2.8 and 3.9). Boards: Shared.Progression.Boards.

	Stores (OrderedDataStore names): "LB_<id>_All" and "LB_<id>_W<ISO year-week>" (weeks start Monday 00:00 UTC).
	  Wins, Elims: all time and weekly · Top5, Survive (best seconds in one round, kept as a max): weekly · Level
	  (prestige x 1000 + level, a max): all time · RP (Arena Rank): later, nothing written.
	Writes: at round end only (SeasonService.recordRound), one IncrementAsync / UpdateAsync per board per player, spread
	  over Boards.WritesSpread s. Only rounds with Boards.FullFrom (8) or more real contenders count. Level is written
	  when it changes (RankService.recordLevel). Studio: Workspace attribute BoardsCountSmall = true counts any round.
	Reads: each board's top ReadTop (50) every ReadEvery (120) s, boards ReadStagger (20) s apart; never per player.
	  A player's own place is shown only when the last read has them; otherwise the menu says "not in the top 50".
	  Their own value comes from their save (Progress.Week, the Wins / TotalKills stats, Level).
	Top 48: the first server to start after a week ends (a claim in DataStore "LB_Jobs", idempotent per week) reads the
	  top 48 of every weekly board and writes the list to DataStore "LB_Top48" key "W<new week>"; players on it get
	  the honour "title:Top 48 W<week>" (SeasonService.grant) for that week.
	Paper boards: built here at start in workspace.Lobby.Leaderboards (three Paper-on-wood SurfaceGuis like the results
	  board): Wins this week and Eliminations this week on the Lounge's back wall either side of the door, Level all
	  time on the front wall right of the Loadout rack. Each has a ProximityPrompt "Leaderboards" (the client opens the
	  menu on that board). Top 10, written by the server after each read.

	Studio (DataStores are off): LeaderboardService.useTestStores() swaps in in-memory ordered stores (GetSortedAsync,
	IncrementAsync, UpdateAsync, SetAsync) and LeaderboardService.testSeed(boardId, scope, { {userId, value, name} })
	fills one; LeaderboardService.refreshNow() reads everything at once.
	API: recordRound(player, r), recordLevel(player, prestige, level), view(player, boardId, scope) -> table
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))
local Theme = require(Shared:WaitForChild("Theme"))

local LeaderboardService = {}

local Services: any = nil
local testMode = false
local testStores: { [string]: any } = {}
local testNames: { [number]: string } = {}
local cache: { [string]: { rows: { { [string]: any } }, at: number } } = {} -- [boardId .. "|" .. scope]
local names: { [number]: string } = {}
local lastLevel: { [Player]: number } = {}
local top48: { [number]: boolean }? = nil
local top48Week = ""
local boardsFolder: Folder? = nil

local function call(serviceName: string, method: string, ...): any
	local service = Services and Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("[LeaderboardService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function B(): { [string]: any }
	return Progression.config().Boards
end

--------------------------------------------------------------------------------------------------------------------
-- Stores (real or test)
--------------------------------------------------------------------------------------------------------------------

local function newTestStore()
	local data: { [string]: number } = {}
	local store = {}
	function store:GetAsync(key: string)
		return data[key]
	end
	function store:SetAsync(key: string, value: number)
		data[key] = value
	end
	function store:IncrementAsync(key: string, delta: number)
		data[key] = (data[key] or 0) + delta
		return data[key]
	end
	function store:UpdateAsync(key: string, fn: (any) -> any)
		local v = fn(data[key])
		if v ~= nil then
			data[key] = v
		end
		return data[key]
	end
	function store:GetSortedAsync(ascending: boolean, pageSize: number)
		local list = {}
		for k, v in pairs(data) do
			table.insert(list, { key = k, value = v })
		end
		table.sort(list, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(pageSize, #list) do
			page[i] = list[i]
		end
		return { GetCurrentPage = function()
			return page
		end, IsFinished = true }
	end
	return store
end

local function ordered(name: string): any
	if testMode then
		local s = testStores[name]
		if not s then
			s = newTestStore()
			testStores[name] = s
		end
		return s
	end
	if Progression.config().IsStudio then
		return nil -- Studio has no API access here: the boards stay empty until useTestStores
	end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	return if ok then store else nil
end

local function plain(name: string): any
	if testMode then
		return ordered("plain:" .. name)
	end
	if Progression.config().IsStudio then
		return nil
	end
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	return if ok then store else nil
end

function LeaderboardService.useTestStores(): boolean
	if not Progression.config().IsStudio then
		return false
	end
	testMode = true
	return true
end

function LeaderboardService.testSeed(boardId: string, scope: string, rows: { { any } }): boolean
	if not testMode then
		return false
	end
	local store = ordered(Progression.boardKey(boardId, scope))
	for _, row in ipairs(rows) do
		local userId, value, name = row[1], row[2], row[3]
		store:SetAsync(tostring(userId), value)
		if name then
			testNames[userId] = name
		end
	end
	return true
end

--------------------------------------------------------------------------------------------------------------------
-- Writes
--------------------------------------------------------------------------------------------------------------------

local function later(fn: () -> ())
	task.delay(math.random() * B().WritesSpread, function()
		local ok, err = pcall(fn)
		if not ok and not testMode and not Progression.config().IsStudio then
			warn("[LeaderboardService] write failed: " .. tostring(err))
		end
	end)
end

local function increment(boardId: string, scope: string, userId: number, n: number)
	if n <= 0 then
		return
	end
	later(function()
		local store = ordered(Progression.boardKey(boardId, scope))
		if store then
			store:IncrementAsync(tostring(userId), math.floor(n))
		end
	end)
end

local function keepMax(boardId: string, scope: string, userId: number, value: number)
	later(function()
		local store = ordered(Progression.boardKey(boardId, scope))
		if store then
			store:UpdateAsync(tostring(userId), function(old)
				local v = tonumber(old) or 0
				return if value > v then math.floor(value) else nil
			end)
		end
	end)
end

local function counts(r: { [string]: any }): boolean
	if Progression.config().IsStudio and workspace:GetAttribute("BoardsCountSmall") == true then
		return true
	end
	return (r.realContenders or 0) >= B().FullFrom
end

-- r = { won, kills, place, survived, realContenders }
function LeaderboardService.recordRound(player: Player, r: { [string]: any })
	if B().Enabled == false or not counts(r) then
		return
	end
	local id = player.UserId
	local week = Progression.isoWeek()
	local S = Services and Services.SeasonService
	if S then
		S.edit(player, function(p)
			if p.Week.key ~= week then
				p.Week = { key = week, Wins = 0, Elims = 0, Top5 = 0, Survive = 0 }
			end
			p.Week.Wins += if r.won then 1 else 0
			p.Week.Elims += math.max(0, r.kills or 0)
			p.Week.Top5 += if (r.place or 0) >= 1 and r.place <= 5 then 1 else 0
			p.Week.Survive = math.max(p.Week.Survive, r.survived or 0)
		end)
	end
	if r.won then
		increment("Wins", "all", id, 1)
		increment("Wins", "week", id, 1)
	end
	if (r.kills or 0) > 0 then
		increment("Elims", "all", id, r.kills)
		increment("Elims", "week", id, r.kills)
	end
	if (r.place or 0) >= 1 and r.place <= 5 then
		increment("Top5", "week", id, 1)
	end
	if (r.survived or 0) > 0 then
		keepMax("Survive", "week", id, r.survived)
	end
end

function LeaderboardService.recordLevel(player: Player, prestige: number, level: number)
	if B().Enabled == false then
		return
	end
	local value = Progression.levelValue(prestige, level)
	if (lastLevel[player] or 0) >= value then
		return
	end
	lastLevel[player] = value
	keepMax("Level", "all", player.UserId, value)
end

--------------------------------------------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------------------------------------------

local function nameOf(userId: number): string
	if testNames[userId] then
		return testNames[userId]
	end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		return here.Name
	end
	if names[userId] then
		return names[userId]
	end
	if userId <= 0 then
		return "Player" .. tostring(-userId)
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok and type(name) == "string" then name else "#" .. tostring(userId)
	return names[userId]
end

local function readBoard(boardId: string, scope: string)
	local store = ordered(Progression.boardKey(boardId, scope))
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, B().ReadTop)
	end)
	if not ok or not pages then
		return
	end
	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage or type(page) ~= "table" then
		return
	end
	local rows = {}
	for i, entry in ipairs(page) do
		local userId = tonumber(entry.key) or 0
		table.insert(rows, { place = i, userId = userId, name = nameOf(userId), value = tonumber(entry.value) or 0,
			rank = call("RankService", "tagFor", userId) })
	end
	cache[boardId .. "|" .. scope] = { rows = rows, at = os.time() }
end

local function scopesOf(board: { [string]: any }): { string }
	local list = {}
	if board.week then
		table.insert(list, "week")
	end
	if board.all then
		table.insert(list, "all")
	end
	return list
end

-- The player's own value on a board (from their save)
local function mine(player: Player, boardId: string, scope: string): number?
	local S = Services and Services.SeasonService
	local p = S and S.progress(player)
	if not p then
		return nil
	end
	if scope == "week" then
		if p.Week.key ~= Progression.isoWeek() then
			return 0
		end
		return p.Week[boardId]
	end
	if boardId == "Wins" then
		return tonumber(call("DataService", "get", player, "Wins"))
	elseif boardId == "Elims" then
		return tonumber(call("DataService", "get", player, "TotalKills"))
	elseif boardId == "Level" then
		return Progression.levelValue(p.Prestige, Progression.levelOf(p.XP))
	end
	return nil
end

function LeaderboardService.view(player: Player, boardId: string, scope: string): { [string]: any }
	local board = Progression.board(boardId)
	local entry = cache[boardId .. "|" .. scope]
	local place = nil
	if entry then
		for _, row in ipairs(entry.rows) do
			if row.userId == player.UserId then
				place = row.place
			end
		end
	end
	local _, resetAt = Progression.isoWeek()
	return {
		board = boardId, scope = scope, rows = if entry then entry.rows else {}, at = if entry then entry.at else 0,
		place = place, value = mine(player, boardId, scope), week = Progression.isoWeek(), resetAt = resetAt,
		every = B().ReadEvery, top = B().ReadTop, later = board and board.later == true,
	}
end

local function onBoards(player: Player, msg: { [string]: any })
	local boardId = tostring(msg.board)
	local scope = if msg.scope == "all" then "all" else "week"
	local S = Services and Services.SeasonService
	if not Progression.board(boardId) or not S then
		return
	end
	local v = LeaderboardService.view(player, boardId, scope)
	v.t = "boards"
	S.send(player, v)
end

--------------------------------------------------------------------------------------------------------------------
-- The paper boards in the Lounge car
--------------------------------------------------------------------------------------------------------------------

local PHYSICAL = {
	{ name = "BoardWins", board = "Wins", scope = "week", title = "WINS", sub = "THIS WEEK" },
	{ name = "BoardElims", board = "Elims", scope = "week", title = "ELIMINATIONS", sub = "THIS WEEK" },
	{ name = "BoardLevel", board = "Level", scope = "all", title = "LEVEL", sub = "ALL TIME" },
}
local W, H = 5.2, 4.3 -- studs (paper); the wood frame adds 0.25 each side
local PPS = 100

local function label(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.TextColor3 = Theme.Colors.PaperInk
	l.FontFace = Theme.Fonts.Medium
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function buildPaper(gui: SurfaceGui, def: { [string]: any })
	local paper = Instance.new("Frame")
	paper.Name = "Paper"
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3 = Theme.Colors.Paper
	paper.BorderSizePixel = 0
	paper.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 26)
	pad.PaddingRight = UDim.new(0, 26)
	pad.PaddingTop = UDim.new(0, 20)
	pad.Parent = paper
	label(paper, "Title", { Text = def.title, FontFace = Theme.Fonts.SemiBold, TextSize = 40, Size = UDim2.new(1, 0, 0, 44) })
	label(paper, "Sub", { Text = def.sub, TextSize = 20, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(0.5, 0, 0, 24),
		TextColor3 = Theme.Colors.PaperTag, FontFace = Theme.Fonts.SemiBold })
	label(paper, "Meta", { Text = "", TextSize = 17, Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.new(0.5, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right, FontFace = Theme.Fonts.Mono, TextTransparency = 0.25 })
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = Theme.Colors.PaperInk
	rule.BackgroundTransparency = 0.6
	rule.BorderSizePixel = 0
	rule.Position = UDim2.fromOffset(0, 78)
	rule.Size = UDim2.new(1, 0, 0, 2)
	rule.Parent = paper
	for i = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundColor3 = Theme.Colors.PaperInk
		row.BackgroundTransparency = if i % 2 == 0 then 0.94 else 1
		row.BorderSizePixel = 0
		row.Position = UDim2.fromOffset(0, 86 + (i - 1) * 32)
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Parent = paper
		label(row, "Place", { Text = "", TextSize = 22, FontFace = Theme.Fonts.Mono, Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(0, 40, 1, 0) })
		label(row, "Who", { Text = "", TextSize = 22, Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -170, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd })
		label(row, "Value", { Text = "", TextSize = 22, FontFace = Theme.Fonts.Mono, Position = UDim2.new(1, -110, 0, 0),
			Size = UDim2.new(0, 104, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
	label(paper, "Empty", { Text = "No one yet this week.\nWin a round with 8 or more contenders.", TextSize = 22,
		Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 0, 80), TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.3, Visible = false })
end

local function valueText(boardId: string, value: number): string
	local board = Progression.board(boardId)
	if board and board.time then
		return string.format("%d:%02d", math.floor(value / 60), value % 60)
	elseif board and board.level then
		local prestige = math.floor(value / 1000)
		return if prestige > 0 then string.format("★%d · %d", prestige, value % 1000) else tostring(value % 1000)
	end
	return Progression.comma(value)
end
LeaderboardService.valueText = valueText

local function paint(model: Instance, def: { [string]: any })
	local face = model:FindFirstChild("Face")
	local gui = face and face:FindFirstChild("Board")
	local paper = gui and gui:FindFirstChild("Paper") :: any
	if not paper then
		return
	end
	local entry = cache[def.board .. "|" .. def.scope]
	local rows = if entry then entry.rows else {}
	paper.Empty.Visible = #rows == 0
	paper.Empty.Text = if def.scope == "week" then "No one yet this week.\nRounds with 8 or more contenders count."
		else "No one yet.\nRounds with 8 or more contenders count."
	local week = Progression.isoWeek()
	paper.Meta.Text = if def.scope == "week" then "WEEK " .. string.sub(week, 6) .. " · RESETS MON 00:00 UTC" else "UPDATED EVERY 2 MIN"
	for i = 1, 10 do
		local row = paper:FindFirstChild("Row" .. i)
		local r = rows[i]
		if row then
			row.Place.Text = if r then tostring(r.place) else ""
			row.Who.Text = if r then r.name else ""
			row.Value.Text = if r then valueText(def.board, r.value) else ""
			local w = if r and r.place <= 3 then Theme.Fonts.SemiBold else Theme.Fonts.Medium
			row.Who.FontFace = w
		end
	end
end

local function buildBoards()
	local lobby = workspace:FindFirstChild("Lobby")
	local lounge = lobby and lobby:FindFirstChild("Lounge")
	if not lounge or not lounge:IsA("Model") then
		warn("[LeaderboardService] no Lobby.Lounge: the paper boards are not built")
		return
	end
	local old = lobby:FindFirstChild("Leaderboards")
	if old then
		old:Destroy()
	end
	local cf, size = lounge:GetBoundingBox()
	local centre = cf.Position
	local halfZ = size.Z / 2 - 1.0 -- the end walls' inner faces (the car is 76 long, the walls 1 thick)
	local y = centre.Y - 5.1 + 5.45 -- floor is about 5.1 below the box centre: centre 5.45 above the floor
	local spots = {
		-- back wall, either side of the door, facing into the car (-Z)
		CFrame.lookAt(Vector3.new(centre.X - 6.5, y, centre.Z + halfZ - 0.12), Vector3.new(centre.X - 6.5, y, centre.Z)),
		CFrame.lookAt(Vector3.new(centre.X + 6.5, y, centre.Z + halfZ - 0.12), Vector3.new(centre.X + 6.5, y, centre.Z)),
		-- front wall, right of the Loadout rack, facing into the car (+Z)
		CFrame.lookAt(Vector3.new(centre.X + 6.5, y, centre.Z - halfZ + 0.12), Vector3.new(centre.X + 6.5, y, centre.Z)),
	}
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	for i, def in ipairs(PHYSICAL) do
		local model = Instance.new("Model")
		model.Name = def.name
		model:SetAttribute("Board", def.board)
		model:SetAttribute("Scope", def.scope)
		local at = spots[i]
		local frame = Instance.new("Part")
		frame.Name = "Frame"
		frame.Anchored = true
		frame.CanCollide = false
		frame.CanQuery = true
		frame.Material = Enum.Material.Wood
		frame.Color = Color3.fromRGB(46, 32, 26)
		frame.Size = Vector3.new(W + 0.5, H + 0.5, 0.12)
		frame.CFrame = at * CFrame.new(0, 0, 0.04)
		frame.Parent = model
		local face = Instance.new("Part")
		face.Name = "Face"
		face.Anchored = true
		face.CanCollide = false
		face.Material = Enum.Material.SmoothPlastic
		face.Color = Theme.Colors.Paper
		face.Size = Vector3.new(W, H, 0.05)
		face.CFrame = at * CFrame.new(0, 0, -0.04)
		face.Parent = model
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Board"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(W * PPS, H * PPS)
		gui.LightInfluence = 1
		gui.Brightness = 1
		gui.MaxDistance = 60
		gui.Parent = face
		buildPaper(gui, def)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Leaderboards"
		prompt.ActionText = "Leaderboards"
		prompt.ObjectText = def.title:sub(1, 1) .. def.title:sub(2):lower()
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Parent = face
		model.PrimaryPart = face
		model.Parent = folder
	end
	folder.Parent = lobby
	boardsFolder = folder
end

local function paintAll()
	local folder = boardsFolder
	if not folder then
		return
	end
	for _, def in ipairs(PHYSICAL) do
		local model = folder:FindFirstChild(def.name)
		if model then
			pcall(paint, model, def)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Top 48 (weekly)
--------------------------------------------------------------------------------------------------------------------

local function runTop48Job()
	local now = os.time()
	local thisWeek = Progression.isoWeek(now)
	local lastWeek = Progression.isoWeek(now - 7 * 86400)
	local jobs = plain("LB_Jobs")
	local lists = plain("LB_Top48")
	if not jobs or not lists then
		return
	end
	local mineToRun = false
	local ok = pcall(function()
		jobs:UpdateAsync("Top48_" .. lastWeek, function(old)
			if old ~= nil then
				return nil
			end
			mineToRun = true
			return game.JobId ~= "" and game.JobId or "studio"
		end)
	end)
	if ok and mineToRun then
		local ids = {}
		local list = {}
		for _, board in ipairs(Progression.Boards) do
			if board.week then
				local store = ordered(Progression.boardKey(board.id, "week", now - 7 * 86400))
				local okRead, pages = pcall(function()
					return store:GetSortedAsync(false, 48)
				end)
				if okRead and pages then
					for _, e in ipairs(pages:GetCurrentPage()) do
						local id = tonumber(e.key)
						if id and not ids[id] then
							ids[id] = true
							table.insert(list, id)
						end
					end
				end
			end
		end
		pcall(function()
			lists:SetAsync("W" .. thisWeek, list)
		end)
	end
	-- this week's list (read once per week per server)
	if top48Week ~= thisWeek then
		local okGet, list = pcall(function()
			return lists:GetAsync("W" .. thisWeek)
		end)
		if okGet then
			top48Week = thisWeek
			top48 = {}
			if type(list) == "table" then
				for _, id in ipairs(list) do
					(top48 :: any)[tonumber(id) or 0] = true
				end
			end
		end
	end
end

local function honourTop48(player: Player)
	local S = Services and Services.SeasonService
	if not S or not top48 or not top48[player.UserId] then
		return
	end
	local key = "title:Top 48 W" .. top48Week
	local p = S.progress(player)
	if p and not p.Honours[key] then
		S.grant(player, { k = "title", id = "Top 48 W" .. top48Week })
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function LeaderboardService.refreshNow()
	for _, board in ipairs(Progression.Boards) do
		if not board.later then
			for _, scope in ipairs(scopesOf(board)) do
				readBoard(board.id, scope)
			end
		end
	end
	paintAll()
end

function LeaderboardService.Init(services)
	Services = services
end

function LeaderboardService.Start()
	local S = Services and Services.SeasonService
	if S then
		S.on("boards", onBoards)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastLevel[player] = nil
	end)
	pcall(buildBoards)
	if B().Enabled == false then
		return
	end
	-- DataStores are off in Studio unless the place allows them: then the boards stay empty (useTestStores for tests)
	task.spawn(function()
		pcall(runTop48Job)
		for _, player in ipairs(Players:GetPlayers()) do
			honourTop48(player)
		end
		Players.PlayerAdded:Connect(function(player)
			task.wait(10)
			honourTop48(player)
		end)
		while true do
			task.wait(3600)
			pcall(runTop48Job)
		end
	end)
	-- the read loop: one board every ReadStagger s, each board again every ReadEvery s
	local jobs = {}
	for _, board in ipairs(Progression.Boards) do
		if not board.later then
			for _, scope in ipairs(scopesOf(board)) do
				table.insert(jobs, { board.id, scope })
			end
		end
	end
	local gap = math.max(B().ReadStagger, B().ReadEvery / math.max(1, #jobs))
	while true do
		for _, job in ipairs(jobs) do
			-- Studio: no reads of the real stores (the place has no API access) until a test swaps in fake ones
			if Progression.config().IsStudio and not testMode then
				task.wait(gap)
				continue
			end
			local ok, err = pcall(readBoard, job[1], job[2])
			if not ok and not testMode then
				warn("[LeaderboardService] read failed: " .. tostring(err))
			end
			paintAll()
			task.wait(gap)
		end
	end
end

return LeaderboardService
