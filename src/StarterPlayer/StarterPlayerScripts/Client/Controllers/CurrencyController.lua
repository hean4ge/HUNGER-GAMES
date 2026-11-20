--[[
	CurrencyController - where a player reads their Gold (server half: CurrencyService; numbers: Shared.Rewards).
	Quiet style, never a pop-up mid-round:
	  * in the train only: one thin line at the top right, "GOLD  1,240" (the player attribute Gold, mirrored by
	    DataService). It holds the old number while your own wheel or box reveal is playing (WheelController.holdUntil),
	    so the balance never gives the prize away.
	  * after a round: one line on the results board in the train (ResultsBoard face > Results > Paper), written on
	    this client only: "YOUR ROUND  +62 GOLD  ·  6th place 25 · 2 defeats 30 · 7 minutes 14 · taking part 10".
	  * the Rewards remote's "line" (not enough Gold, the wheel is turning, your weapon is in your bag): one thin line
	    low in the middle for 3 s, then it fades.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared:WaitForChild("Rewards"))
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer

local CurrencyController = {}

local Controllers: any = nil
local goldLabel: TextLabel? = nil
local noteLabel: TextLabel? = nil
local shownGold: number? = nil
local lastRound: { [string]: any }? = nil
local noteToken = 0

-- the train's box (workspace.Lobby's cars), read once
local trainMin: Vector3? = nil
local trainMax: Vector3? = nil

local function readTrain()
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	-- the cars only (the Scenery folder runs far outside the train)
	local lo, hi = nil, nil
	for _, name in ipairs({ "Nose", "Lounge", "Dining", "Observation" }) do
		local car = lobby:FindFirstChild(name)
		if car and car:IsA("Model") then
			local ok, cf, size = pcall(function()
				return car:GetBoundingBox()
			end)
			if ok then
				local a, b = cf.Position - size / 2, cf.Position + size / 2
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
			end
		end
	end
	if lo and hi then
		trainMin = lo - Vector3.new(2, 4, 2)
		trainMax = hi + Vector3.new(2, 4, 2)
	end
end

local function inTrain(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not trainMin or not trainMax then
		return false
	end
	local p = root.Position
	local lo, hi = trainMin :: Vector3, trainMax :: Vector3
	return p.X >= lo.X and p.X <= hi.X and p.Y >= lo.Y and p.Y <= hi.Y and p.Z >= lo.Z and p.Z <= hi.Z
end

local PLACE_SUFFIX = { "st", "nd", "rd" }
local function ordinal(n: number): string
	local m = n % 100
	local s = if m >= 11 and m <= 13 then "th" else (PLACE_SUFFIX[n % 10] or "th")
	return tostring(n) .. s
end

-- "6th place 25 · 2 defeats 30 · ..." from the parts CurrencyService sent
local function partsText(r: { [string]: any }): string
	local p = r.parts or {}
	local out = {}
	local function add(text: string?, value: number?)
		if text and value and value ~= 0 then
			table.insert(out, string.format("%s %s%d", text, if value < 0 then "−" else "", math.abs(value)))
		end
	end
	local place = tonumber(player:GetAttribute("Placement")) or 0
	add(if place > 0 then ordinal(place) .. " place" else "placing", p.placing)
	add(string.format("%d defeat%s", tonumber(player:GetAttribute("Kills")) or 0, if (tonumber(player:GetAttribute("Kills")) or 0) == 1 then "" else "s"), p.defeats)
	add("time alive", p.time)
	add("the win", p.win)
	add("challenges", p.challenges)
	add("taking part", p.takePart)
	add("first round today", p.firstRound)
	add("first win today", p.firstWin)
	add("daily limit", p.softCap)
	return table.concat(out, "  ·  ")
end

local function boardPaper(): Instance?
	for _, face in ipairs(CollectionService:GetTagged("ResultsBoard")) do
		local gui = face:FindFirstChild("Results")
		local paper = gui and gui:FindFirstChild("Paper")
		if paper then
			return paper
		end
	end
	return nil
end

local function writeBoard()
	local r = lastRound
	local paper = boardPaper()
	if not r or not paper then
		return
	end
	local labelObj = paper:FindFirstChild("YourGold")
	if not labelObj then
		local l = Instance.new("TextLabel")
		l.Name = "YourGold"
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.AnchorPoint = Vector2.new(0, 1)
		l.Position = UDim2.new(0, 0, 1, -18)
		l.Size = UDim2.new(1, 0, 0, 40)
		l.FontFace = Theme.Fonts.Medium
		l.TextSize = 28
		l.TextColor3 = Theme.Colors.PaperInk or Color3.fromRGB(35, 39, 43)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.RichText = true
		l.ZIndex = 4
		l.Parent = paper
		labelObj = l
	end
	local label = labelObj :: TextLabel
	local detail = partsText(r)
	local tag = Color3.fromRGB(138, 92, 16):ToHex()
	if (r.gold or 0) <= 0 then
		label.Text = string.format("<font color=\"#%s\"><b>YOUR ROUND  NO GOLD</b></font>    %s", tag,
			if r.tookPart == false then "Gold needs a few steps in the first minute" else "this round paid no Gold")
		return
	end
	label.Text = string.format("<font color=\"#%s\"><b>YOUR ROUND  +%s GOLD</b></font>%s",
		tag, Rewards.comma(r.gold or 0), if detail ~= "" then "    " .. detail else "")
end

local function showNote(text: string)
	local l = noteLabel
	if not l then
		return
	end
	noteToken += 1
	local token = noteToken
	l.Text = text
	QuietUI.fadeText(l, true, 0.2)
	task.delay(3, function()
		if noteToken == token then
			QuietUI.fadeText(l, false, 0.6)
		end
	end)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GoldLine"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 3
	goldLabel = QuietUI.label({
		Name = "Gold",
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 14),
		Size = UDim2.fromOffset(220, 22),
		TextSize = Theme.TextSize.Label,
		Font = "Medium",
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		RichText = true,
	})
	noteLabel = QuietUI.label({
		Name = "Note",
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.new(0.8, 0, 0, 22),
		TextSize = Theme.TextSize.Body,
		Font = "Medium",
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	QuietUI.textTransparency(noteLabel :: TextLabel, 1)
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function step()
	local l = goldLabel
	if not l then
		return
	end
	-- (fixesUI) not through an open menu (the hub, Daily, Season, Ranks, Settings, the Shop: the menus that deal in Gold
	-- show it themselves)
	local shop = Controllers and Controllers.ShopController
	local menuUp = ClientState.menuOpen == true or (shop ~= nil and shop.isOpen == true)
	local show = inTrain() and player:GetAttribute("Gold") ~= nil and not menuUp
	l.Visible = show
	if not show then
		return
	end
	local hold = Controllers and Controllers.WheelController and Controllers.WheelController.holdUntil or 0
	local gold = tonumber(player:GetAttribute("Gold")) or 0
	if shownGold == nil or os.clock() >= hold then
		shownGold = gold
	end
	l.Text = string.format("<font transparency=\"0.3\">GOLD</font>  %s", Rewards.comma(shownGold or 0))
end

function CurrencyController.Init(controllers)
	Controllers = controllers
end

function CurrencyController.Start()
	build()
	readTrain()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("Rewards", 30) :: RemoteEvent?
	if remote then
		remote.OnClientEvent:Connect(function(kind: any, data: any)
			if kind == "round" and type(data) == "table" then
				lastRound = data
				writeBoard()
			elseif kind == "line" and type(data) == "string" then
				showNote(data)
			end
		end)
	end
	-- the results board can be rebuilt or arrive later: write the line again when the round's result lands
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		if t >= 0.25 then
			t = 0
			if not trainMin then
				readTrain()
			end
			step()
		end
	end)
	CollectionService:GetInstanceAddedSignal("ResultsBoard"):Connect(writeBoard)
end

return CurrencyController
