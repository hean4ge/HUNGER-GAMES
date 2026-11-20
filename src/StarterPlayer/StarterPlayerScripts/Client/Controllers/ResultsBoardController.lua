--[[
	ResultsBoardController - writes the last round's result on the results board in the lobby (the client half;
	Server/Services/ResultsBoardService is the server half, ServerStorage.WorldGen.LobbyBoardBuilder builds the board).
	Owned by the UI system.

	The owner (18 Nov 2026): the result "shouldnt pop up after the game it can appear on one of the physical boards".
	The board is a SurfaceGui "Results" on the NoticeFace part tagged "ResultsBoard" (docs/design/ui/StyleA_Quiet/
	board.html): the winner with their headshot, defeats and time survived; the top five; your own row marked with a
	soft Sun band and a bar (in the top five, or under them after three dots); the round's facts. The text is written
	here, on each client, so every player sees their own row; nobody else's screen changes.

	Data: the remote ReplicatedStorage.Remotes.RoundResult ("result", result) when a round ends, and once at start
	(this controller asks with "get", so a player who joins later sees the last round too). The shape is in
	ResultsBoardService's header. No result yet: the board's empty face.

	Public API (Controllers.ResultsBoardController):
	  getResult() -> table?     the last result this client has
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Lore = require(Shared:WaitForChild("Lore"))
local Util = require(Shared:WaitForChild("Util"))

local player = Players.LocalPlayer

local ResultsBoardController = {}

local TAG = "ResultsBoard"
local TOP = 5

local result: { [string]: any }? = nil

local function escape(text: any): string
	return Theme.escape(tostring(text or ""))
end

local function plural(n: number, one: string, many: string): string
	return string.format("%d %s", n, if n == 1 then one else many)
end

local function weight(label: TextLabel, w: Enum.FontWeight)
	local face = label.FontFace
	if face.Weight ~= w then
		label.FontFace = Font.new(face.Family, w, face.Style)
	end
end

local function headshot(userId: any): string
	local id = tonumber(userId)
	if not id or id <= 0 then
		return "" -- a Studio test player (negative id) has no picture
	end
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", id)
end

local function isMine(row: { [string]: any }): boolean
	return tonumber(row.userId) == player.UserId
end

local function paintRow(frame: any, row: { [string]: any }?, mine: boolean)
	if not frame then
		return
	end
	if not row then
		frame.Visible = false
		return
	end
	frame.Visible = true
	frame.Band.Visible = mine
	frame.Bar.Visible = mine
	frame.Line.Visible = not mine
	local place = math.floor(tonumber(row.place) or 0)
	frame.Place.Text = if place > 0 then tostring(place) else "–"
	local name = escape(row.name)
	if mine then
		name ..= string.format("<font color=\"#%s\" size=\"30\">   YOU</font>", (Theme.Colors.PaperTag or Color3.fromRGB(138, 92, 16)):ToHex())
	end
	-- the Level (RankService): a short "LV 30" in the board's dim ink (★n after a Prestige); the rank's name is in
	-- the Ranks menu and over heads in the train (the column is too narrow for both)
	local rank = row.rank
	if type(rank) == "table" and tonumber(rank.level) then
		local prestige = math.floor(tonumber(rank.prestige) or 0)
		name ..= string.format("<font color=\"#%s\" size=\"22\" transparency=\"0.4\">  LV %d%s</font>", (Theme.Colors.PaperInk or Color3.new()):ToHex(),
			math.floor(tonumber(rank.level) or 1), if prestige > 0 then " ★" .. prestige else "")
	end
	frame.Who.Text = name
	frame.Defeats.Text = tostring(math.floor(tonumber(row.kills) or 0))
	frame.Survived.Text = Util.formatTime(tonumber(row.survived) or 0)
	for _, label in ipairs({ frame.Place, frame.Who, frame.Defeats, frame.Survived }) do
		weight(label, if mine then Enum.FontWeight.SemiBold else Enum.FontWeight.Medium)
	end
	if not mine then
		-- the numbers are RobotoMono, which ships Regular and Medium only
		for _, label in ipairs({ frame.Place, frame.Defeats, frame.Survived }) do
			weight(label, Enum.FontWeight.Regular)
		end
	else
		for _, label in ipairs({ frame.Place, frame.Defeats, frame.Survived }) do
			weight(label, Enum.FontWeight.Medium)
		end
	end
end

local function setFact(fact: any, label: string, value: string?)
	if not fact then
		return
	end
	fact.Label.Text = label
	fact.Value.Text = value or "None"
end

local function render(gui: Instance)
	local paper = gui:FindFirstChild("Paper") :: any
	if not paper then
		return
	end
	local ok, err = pcall(function()
		local r = result
		local hasRows = r ~= nil and type(r.rows) == "table" and #r.rows > 0
		paper.Empty.Visible = not hasRows
		paper.Winner.Visible = hasRows
		paper.Table.Visible = hasRows
		paper.RuleBottom.Visible = hasRows
		paper.Facts.Visible = hasRows
		if not hasRows or not r then
			paper.Top.Meta.Text = ""
			return
		end
		local rows = r.rows
		local count = math.floor(tonumber(r.contenders) or #rows)
		local days = math.max(1, math.floor(tonumber(r.days) or 1))
		paper.Top.Meta.Text = string.format("%s  ·  %s  ·  %s", plural(count, "contender", "contenders"), plural(days, "day", "days"),
			Util.formatTime(tonumber(r.duration) or 0))

		-- the winner (or what happened instead)
		local w = r.winner
		local winner = paper.Winner
		if type(w) == "table" then
			winner.Label.Text = "WINNER"
			winner.Head.Visible = true
			winner.Head.Image = headshot(w.userId)
			winner.Who.Text = tostring(w.name or "?")
			local kills = math.floor(tonumber(w.kills) or 0)
			winner.Sub.Text = string.format("%s  ·  survived %s", plural(kills, "defeat", "defeats"), Util.formatTime(tonumber(w.survived) or 0))
		else
			winner.Label.Text = "RESULT"
			winner.Head.Visible = false
			winner.Who.Text = tostring(r.title or "Round over")
			winner.Sub.Text = ""
		end

		-- the top five, and your own row
		local mineIndex = nil
		for i, row in ipairs(rows) do
			if type(row) == "table" and isMine(row) then
				mineIndex = i
				break
			end
		end
		local t = paper.Table
		for i = 1, TOP do
			local row = rows[i]
			paintRow(t:FindFirstChild("Row" .. i), if type(row) == "table" then row else nil, mineIndex == i)
		end
		local below = mineIndex ~= nil and mineIndex > TOP
		t.Gap.Visible = below and mineIndex > TOP + 1
		paintRow(t.You, if below and mineIndex then rows[mineIndex] else nil, true)
		if below and mineIndex == TOP + 1 then
			-- 6th sits straight under the 5th: no dots
			t.You.Position = UDim2.fromOffset(0, t.Row5.Position.Y.Offset + t.Row5.Size.Y.Offset)
		else
			t.You.Position = UDim2.fromOffset(0, t.Gap.Position.Y.Offset + t.Gap.Size.Y.Offset)
		end

		-- the facts
		local facts = if type(r.facts) == "table" then r.facts else {}
		local first = facts.firstFall
		setFact(paper.Facts.Fact1, "FIRST TO FALL", if type(first) == "table" then string.format("%s, %s", escape(first.name), Util.formatTime(tonumber(first.time) or 0)) else nil)
		local most = facts.mostDefeats
		setFact(paper.Facts.Fact2, "MOST DEFEATS", if type(most) == "table" then string.format("%s, %d", escape(most.name), math.floor(tonumber(most.kills) or 0)) else nil)
		setFact(paper.Facts.Fact3, "CAUGHT BY " .. Lore.upper("Border"), tostring(math.floor(tonumber(facts.border) or 0)))
		setFact(paper.Facts.Fact4, "FELL IN THE FIRST MINUTE", tostring(math.floor(tonumber(facts.early) or 0)))
	end)
	if not ok then
		warn("[ResultsBoardController] " .. tostring(err))
	end
end

local function boards(): { Instance }
	local list = {}
	for _, part in ipairs(CollectionService:GetTagged(TAG)) do
		local gui = part:FindFirstChild("Results")
		if gui and gui:IsA("SurfaceGui") then
			table.insert(list, gui)
		end
	end
	return list
end

local function renderAll()
	for _, gui in ipairs(boards()) do
		render(gui)
	end
end

function ResultsBoardController.getResult(): { [string]: any }?
	return result
end

function ResultsBoardController.Init(_registry) end

function ResultsBoardController.Start()
	-- the board streams in and out with the lobby: write it each time it arrives
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(part)
		local gui = part:WaitForChild("Results", 10)
		if gui then
			render(gui)
		end
	end)
	renderAll()

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("RoundResult", 30)
	if not remote or not remote:IsA("RemoteEvent") then
		warn("[ResultsBoardController] no RoundResult remote: the results board stays empty")
		return
	end
	remote.OnClientEvent:Connect(function(action: any, data: any)
		if action ~= "result" then
			return
		end
		result = if type(data) == "table" then data else nil
		renderAll()
	end)
	remote:FireServer("get")
end

return ResultsBoardController
