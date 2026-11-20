--[[
	CosmeticsController - the client half of cosmetics (Server CosmeticService; Shared.CosmeticLooks, Shared.CosmeticFx).

	  * Kill effects: the KillFx remote plays the killer's effect at the defeated player's position (CosmeticFx, capped by
	    the detail tier), for anyone within FX_RANGE studs of it, and always for the victim, the killer and whoever is
	    spectating near it.
	  * The winner's banner in the train: after a round with a winner (the RoundResult remote), a banner card with the
	    winner's name hangs over their head while the train is in the Lobby or Intermission phase, until the next
	    countdown. Everyone in the car sees it.
	  * The results board: each row gets its player's kill icon beside the name, and the winner's column gets their
	    banner as a strip under the line of defeats (drawn on the paper; ResultsBoardController writes the text).
	  * The first-person weapon is skinned by Shared.TierLooks from the local player's LooksJson; when that changes,
	    this re-applies it to the model in the camera.

	Public API (Controllers.CosmeticsController)
	  equip(id, weapon?, slot?)    asks the server to put a cosmetic on ("" with slot and weapon takes it off)
	  looks() -> looks             the local player's equipped looks
	  preview(effectId, position)  plays a kill effect here only (menus' PREVIEW)
	  changed: Signal(looks)       the local player's looks changed
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Signal = require(Shared:WaitForChild("Signal"))
local CosmeticLooks = require(Shared:WaitForChild("CosmeticLooks"))
local CosmeticFx = require(Shared:WaitForChild("CosmeticFx"))

local player = Players.LocalPlayer
local GameState = ReplicatedStorage:WaitForChild("GameState")

local CosmeticsController = {}
CosmeticsController.changed = Signal.new()

local FX_RANGE = 260
local BOARD_TAG = "ResultsBoard"
local SHOW_PHASES = { Lobby = true, Intermission = true }

local looksRemote: RemoteEvent? = nil
local lastResult: any = nil
local winnerBoard: { gui: BillboardGui?, userId: number? } = { gui = nil, userId = nil }

function CosmeticsController.looks(): any
	return CosmeticLooks.of(player)
end

function CosmeticsController.equip(id: string, weapon: string?, slot: string?)
	if looksRemote then
		looksRemote:FireServer("equip", { id = id, weapon = weapon, slot = slot })
	end
end

function CosmeticsController.preview(effectId: string, position: Vector3): number?
	return CosmeticFx.play(effectId, position)
end

-- Kill effects ---------------------------------------------------------------------------------------------------------

local function onKillFx(data: any)
	if type(data) ~= "table" or typeof(data.pos) ~= "Vector3" then
		return
	end
	local involved = data.victim == player.UserId or data.killer == player.UserId
	local cam = workspace.CurrentCamera
	local near = cam ~= nil and (cam.CFrame.Position - data.pos).Magnitude <= FX_RANGE
	if involved or near then
		CosmeticFx.play(data.id, data.pos)
	end
end

-- The winner's banner over their head -------------------------------------------------------------------------------

local function clearWinner()
	if winnerBoard.gui then
		winnerBoard.gui:Destroy()
	end
	winnerBoard.gui = nil
end

local function buildWinnerGui(winner: Player): BillboardGui
	local looks = CosmeticLooks.of(winner)
	local gui = Instance.new("BillboardGui")
	gui.Name = "WinnerBanner"
	gui.Size = UDim2.fromScale(4.2, 1.85)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Name = "Winner"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.22)
	label.Text = "WINNER"
	label.TextScaled = true
	label.FontFace = Theme.Fonts.SemiBold
	label.TextColor3 = Theme.Colors.Sun
	label.TextStrokeColor3 = Theme.Colors.Shade
	label.TextStrokeTransparency = 0.55
	label.Parent = gui
	local banner = CosmeticLooks.banner(looks.b or "linen", {
		Position = UDim2.fromScale(0, 0.25),
		Size = UDim2.fromScale(1, 0.75),
		Parent = gui,
	}, looks.t)
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.fromScale(0.5, 0.5)
	name.Size = UDim2.fromScale(0.84, 0.42)
	name.Text = winner.DisplayName
	name.TextScaled = true
	name.FontFace = Theme.Fonts.SemiBold
	name.TextColor3 = Theme.Colors.Ink
	name.ZIndex = 20
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Shade
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = name
	name.Parent = banner
	return gui
end

local function refreshWinner()
	local phase = GameState:GetAttribute("Phase")
	local w = lastResult and lastResult.winner
	local userId = type(w) == "table" and tonumber(w.userId) or nil
	local winner = userId and Players:GetPlayerByUserId(userId)
	local head = winner and winner.Character and winner.Character:FindFirstChild("Head")
	if not (SHOW_PHASES[phase] and winner and head and winner:GetAttribute("Alive") ~= true) then
		clearWinner()
		return
	end
	if winnerBoard.gui and winnerBoard.gui.Adornee == head and winnerBoard.userId == userId then
		return
	end
	clearWinner()
	local gui = buildWinnerGui(winner :: Player)
	gui.Adornee = head
	gui.Parent = player:WaitForChild("PlayerGui")
	winnerBoard.gui = gui
	winnerBoard.userId = userId
end

-- The results board: kill icons by the names, the winner's banner ----------------------------------------------------

local function iconOf(userId: any): string?
	local p = tonumber(userId) and Players:GetPlayerByUserId(tonumber(userId) :: number)
	return p and CosmeticLooks.iconFor(CosmeticLooks.of(p), nil) or nil
end

local function decorateRow(rowFrame: Instance?, row: any)
	if not rowFrame then
		return
	end
	local old = rowFrame:FindFirstChild("KillIcon")
	if old then
		old:Destroy()
	end
	if type(row) ~= "table" then
		return
	end
	local id = iconOf(row.userId)
	if id then
		CosmeticLooks.killIcon(id, 56, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, -540, 0.5, 0),
			ZIndex = 4,
			Parent = rowFrame,
		})
	end
end

local function decorateBoard(gui: Instance)
	local paper = gui:FindFirstChild("Paper")
	if not paper then
		return
	end
	local r = lastResult
	local rows = r and type(r.rows) == "table" and r.rows or {}
	local tableFrame = paper:FindFirstChild("Table")
	if tableFrame then
		local mine = nil
		for i, row in ipairs(rows) do
			if type(row) == "table" and tonumber(row.userId) == player.UserId then
				mine = i
			end
		end
		for i = 1, 5 do
			decorateRow(tableFrame:FindFirstChild("Row" .. i), rows[i])
		end
		decorateRow(tableFrame:FindFirstChild("You"), if mine and mine > 5 then rows[mine] else nil)
	end
	local winnerFrame = paper:FindFirstChild("Winner")
	if winnerFrame then
		local old = winnerFrame:FindFirstChild("Banner")
		if old then
			old:Destroy()
		end
		local w = r and r.winner
		local p = type(w) == "table" and tonumber(w.userId) and Players:GetPlayerByUserId(tonumber(w.userId) :: number)
		if p then
			local looks = CosmeticLooks.of(p)
			CosmeticLooks.banner(looks.b or "linen", {
				Position = UDim2.fromOffset(0, 486),
				Size = UDim2.fromOffset(420, 140),
				ZIndex = 2,
				Parent = winnerFrame,
			}, looks.t)
		end
	end
end

local function decorateAll()
	for _, part in ipairs(CollectionService:GetTagged(BOARD_TAG)) do
		local gui = part:FindFirstChild("Results")
		if gui then
			pcall(decorateBoard, gui)
		end
	end
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

local function reskinViewmodel()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local looks = CosmeticLooks.of(player)
	for _, d in ipairs(cam:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("Variant") == "view" and type(d:GetAttribute("ItemId")) == "string" then
			local id = d:GetAttribute("ItemId") :: string
			pcall(CosmeticLooks.applySkin, d, CosmeticLooks.skinFor(looks, id) or "")
		end
	end
end

function CosmeticsController.Init(_registry) end

function CosmeticsController.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	task.spawn(function()
		local fx = remotes:WaitForChild("KillFx", 30)
		if fx and fx:IsA("RemoteEvent") then
			fx.OnClientEvent:Connect(onKillFx)
		end
	end)
	task.spawn(function()
		local r = remotes:WaitForChild("Looks", 30)
		if r and r:IsA("RemoteEvent") then
			looksRemote = r
		end
	end)
	player:GetAttributeChangedSignal("LooksJson"):Connect(function()
		reskinViewmodel()
		CosmeticsController.changed:Fire(CosmeticLooks.of(player))
	end)

	GameState:GetAttributeChangedSignal("Phase"):Connect(refreshWinner)
	Players.PlayerRemoving:Connect(function(p)
		if winnerBoard.userId == p.UserId then
			clearWinner()
		end
	end)
	task.spawn(function()
		while true do -- (characters respawn and stream in: a cheap check twice a second)
			task.wait(0.5)
			pcall(refreshWinner)
		end
	end)

	CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(function(part)
		local gui = part:WaitForChild("Results", 10)
		if gui then
			task.wait(0.2)
			pcall(decorateBoard, gui)
		end
	end)
	task.spawn(function()
		local rr = remotes:WaitForChild("RoundResult", 30)
		if not (rr and rr:IsA("RemoteEvent")) then
			return
		end
		rr.OnClientEvent:Connect(function(action: any, data: any)
			if action ~= "result" then
				return
			end
			lastResult = if type(data) == "table" then data else nil
			task.defer(decorateAll)
			task.defer(refreshWinner)
		end)
		rr:FireServer("get") -- (the last round's result, for a player who joins after it)
	end)
end

return CosmeticsController
