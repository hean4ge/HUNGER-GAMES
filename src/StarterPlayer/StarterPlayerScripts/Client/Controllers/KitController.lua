--[[
	KitController - the kit pick in the lobby and the kit parcel in the arena (docs/design/Weapons_v2.md section 3;
	KitService, Shared.Kits). Quiet style: thin text on the picture, no boxes, no pop-ups.

	IN THE LOBBY (the red train), while the lobby shows:
	  one thin line            KIT   ‹  Archer  ›
	  its contents, dimmer     Short Bow, Arrow ×8, Apple
	  and, once you own a weapon from the wheel or a Strongbox,
	                           BRING   ‹  Twin-Bit Axe ★★★★  ›      ("kit weapon" = bring nothing)
	  The arrows are buttons (click or tap; 44 px tall on touch). K cycles the kit (Shift+K back), B the weapon to bring;
	  on a gamepad the bumpers L1 / R1 cycle the kit. The pick goes to the server (remote KitPick) and is remembered.
	  On a PC it sits at the bottom centre; on a touch screen at the top centre under the status lines.

	IN THE ARENA
	  * Player attribute KitIncoming (server time of the landing): a soft two-note chime and one thin line, "Your kit
	    is coming", for a few seconds.
	  * Every kit parcel (tag KitParcel; attributes LandAt, DropHeight, FallTime) is drawn falling here, on each client,
	    from DropHeight under its chute with a slow sway; the server's model already stands where it lands, so the
	    server moves nothing and a late joiner simply sees it where it is.
	  * Your own parcel: a small matte parcel mark at its place on the screen (or at the edge, pointing to it) with its
	    distance in thin numbers, until it is opened or for Kits.Settings.MarkerTime s after it lands.
	  * Your own parcel's Open prompt holds for OwnerOpenTime on your screen (prompt attribute OwnerHold); the server
	    times the hold either way.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Kits = require(Shared:WaitForChild("Kits"))
local Net = require(Shared:WaitForChild("Net"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Stars = require(Shared:WaitForChild("Stars"))
local Theme = require(Shared:WaitForChild("Theme"))
local Input = require(Shared:WaitForChild("Input"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local C = Theme.Colors

local KitController = {}

local PARCEL_TAG = "KitParcel"
local PROMPT_TAG = "LootPrompt"
local S = Kits.Settings
local METERS = 0.28 -- studs to metres, as the HUD's distances
local EDGE = 34 -- px from the screen edge for the off-screen mark

local gui: ScreenGui? = nil
local R: { [string]: any } = {}
local Controllers: { [string]: any } = {}
local pending: { kit: string?, at: number } = { kit = nil, at = 0 }
local bringPending: string? = nil
local falling: { [Model]: { final: CFrame, landAt: number, height: number, fall: number, phase: number } } = {}
local incomingShownFor: number? = nil

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

--------------------------------------------------------------------------------------------------------------------
-- The lobby lines
--------------------------------------------------------------------------------------------------------------------

local function currentKit()
	return Kits.get(pending.kit or player:GetAttribute("Kit")) or Kits.default()
end

local function armouryList(): { { id: string, stars: number } }
	local out = {}
	local raw = player:GetAttribute("KitArmoury")
	if type(raw) == "string" then
		for id, stars in string.gmatch(raw, "([%w_]+):(%d)") do
			if ItemDefs.get(id) then
				table.insert(out, { id = id, stars = tonumber(stars) or 1 })
			end
		end
	end
	return out
end

local function currentBring(): string
	local v = if bringPending ~= nil then bringPending else player:GetAttribute("KitBring")
	return if type(v) == "string" then v else ""
end

local function makeRow(parent: Instance, name: string, order: number, title: string): any
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 30)
	row.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local label = QuietUI.label({
		Name = "Title", Text = title, Font = "SemiBold", TextSize = Theme.TextSize.Label,
		TextColor3 = C.Ink2, Size = UDim2.fromOffset(52, 30), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 1,
	})
	label.Parent = row
	local prev = QuietUI.button({ Name = "Prev", Text = "\u{2039}", TextSize = Theme.TextSize.Heading, Height = 30, LayoutOrder = 2 })
	prev.Size = UDim2.fromOffset(30, 30)
	prev.Parent = row
	local value = QuietUI.label({
		Name = "Value", Text = "", Font = "Medium", TextSize = Theme.TextSize.Body, Size = UDim2.fromOffset(210, 30),
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3,
	})
	value.Parent = row
	local nextB = QuietUI.button({ Name = "Next", Text = "\u{203A}", TextSize = Theme.TextSize.Heading, Height = 30, LayoutOrder = 4 })
	nextB.Size = UDim2.fromOffset(30, 30)
	nextB.Parent = row
	QuietUI.bindButton(prev, { quiet = true })
	QuietUI.bindButton(nextB, { quiet = true })
	row.Parent = parent
	return { row = row, prev = prev, nextB = nextB, value = value }
end

local function refreshLines()
	if not R.kit then
		return
	end
	local kit = currentKit()
	R.kit.value.Text = kit.name
	R.contents.Text = Kits.summary(kit)
	local owned = armouryList()
	R.bring.row.Visible = #owned > 0
	local bring = currentBring()
	local text = "kit weapon"
	for _, entry in ipairs(owned) do
		if entry.id == bring then
			text = Stars.label(entry.id, entry.stars)
		end
	end
	R.bring.value.Text = text
end

local function cycleKit(step: number)
	local kit = currentKit()
	local n = #Kits.List
	local nextKit = Kits.List[((kit.index - 1 + step) % n) + 1]
	pending.kit = nextKit.id
	pending.at = os.clock()
	refreshLines()
	Sfx.play("UIClick")
	Net.event("KitPick"):FireServer(nextKit.id)
end

local function cycleBring(step: number)
	local owned = armouryList()
	if #owned == 0 then
		return
	end
	local options = { "" }
	for _, entry in ipairs(owned) do
		table.insert(options, entry.id)
	end
	local index = 1
	for i, id in ipairs(options) do
		if id == currentBring() then
			index = i
		end
	end
	local id = options[((index - 1 + step) % #options) + 1]
	bringPending = id
	refreshLines()
	Sfx.play("UIClick")
	Net.event("KitPick"):FireServer("bring", id)
end

local function lobbyShowing(): boolean
	return not ClientState.inArena and ClientState.spectating == nil and not ClientState.menuOpen
end

local function placeLines()
	local holder = R.holder
	if not holder then
		return
	end
	if Input.isTouch() then
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 96)
	else
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -28)
	end
end

local function buildLobby(root: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "KitPick"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(380, 96)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 0)
	list.Parent = holder
	R.kit = makeRow(holder, "Kit", 1, "KIT")
	R.contents = QuietUI.label({
		Name = "Contents", Text = "", Font = "Regular", TextSize = Theme.TextSize.Small, TextColor3 = C.Ink2,
		Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2,
	})
	R.contents.Parent = holder
	R.bring = makeRow(holder, "Bring", 3, "BRING")
	R.kit.prev.Activated:Connect(function()
		cycleKit(-1)
	end)
	R.kit.nextB.Activated:Connect(function()
		cycleKit(1)
	end)
	R.bring.prev.Activated:Connect(function()
		cycleBring(-1)
	end)
	R.bring.nextB.Activated:Connect(function()
		cycleBring(1)
	end)
	R.holder = holder
	holder.Parent = root
	placeLines()
	refreshLines()
end

--------------------------------------------------------------------------------------------------------------------
-- In the arena: the warning line and the parcel mark
--------------------------------------------------------------------------------------------------------------------

local function buildArena(root: Instance)
	R.coming = QuietUI.label({
		Name = "KitComing", Text = "Your kit is coming", Font = "Medium", TextSize = Theme.TextSize.Body,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.fromOffset(320, 22),
		TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
	})
	R.coming.Parent = root
	-- a small matte parcel: a square outline, a cord across it and the distance under it
	local mark = Instance.new("Frame")
	mark.Name = "KitMark"
	mark.BackgroundTransparency = 1
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Size = UDim2.fromOffset(60, 40)
	mark.Visible = false
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 0)
	box.Size = UDim2.fromOffset(14, 11)
	box.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Ink
	stroke.Thickness = 1.5
	stroke.Parent = box
	local cord = Instance.new("Frame")
	cord.Name = "Cord"
	cord.BorderSizePixel = 0
	cord.BackgroundColor3 = C.Ink
	cord.AnchorPoint = Vector2.new(0.5, 0)
	cord.Position = UDim2.new(0.5, 0, 0, 0)
	cord.Size = UDim2.new(0, 1, 1, 0)
	cord.Parent = box
	box.Parent = mark
	local dist = QuietUI.label({
		Name = "Distance", Text = "", Font = "Mono", TextSize = Theme.TextSize.Number,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 15), Size = UDim2.fromOffset(60, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	dist.Parent = mark
	mark.Parent = root
	R.mark = mark
	R.markDist = dist
end

local function chime()
	Sfx.play("Notify", { volume = 0.6, pitch = 1 })
	task.delay(0.2, function()
		Sfx.play("Notify", { volume = 0.6, pitch = 1.26 })
	end)
end

local function onIncoming()
	local landAt = player:GetAttribute("KitIncoming")
	if type(landAt) ~= "number" or landAt == incomingShownFor then
		return
	end
	incomingShownFor = landAt
	if not ClientState.inArena then
		return
	end
	chime()
	local label = R.coming
	if label then
		label.Visible = true
		QuietUI.fadeText(label, true)
		task.delay(4, function()
			if incomingShownFor == landAt then
				QuietUI.fadeText(label, false)
			end
		end)
	end
end

local function myParcel(): Model?
	for _, model in ipairs(CollectionService:GetTagged(PARCEL_TAG)) do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId and model:GetAttribute("Opened") ~= true then
			local landAt = tonumber(model:GetAttribute("LandAt")) or 0
			if serverNow() - landAt < (S.MarkerTime or 90) then
				return model
			end
		end
	end
	return nil
end

local function updateMark()
	local mark = R.mark
	if not mark then
		return
	end
	local parcel = if ClientState.inArena and ClientState.alive then myParcel() else nil
	local camera = workspace.CurrentCamera
	if not parcel or not camera then
		mark.Visible = false
		return
	end
	local p = parcel:GetPivot().Position
	local view = camera.ViewportSize
	local point, onScreen = camera:WorldToViewportPoint(p + Vector3.new(0, 3, 0))
	local x, y = point.X, point.Y
	local inset = (gui and gui.AbsolutePosition) or Vector2.zero
	if not onScreen or x < EDGE or x > view.X - EDGE or y < EDGE or y > view.Y - EDGE then
		-- behind or off the side: on the edge, in its direction
		local rel = camera.CFrame:PointToObjectSpace(p)
		local dir = Vector2.new(rel.X, -rel.Y)
		if rel.Z > 0 then
			dir = Vector2.new(rel.X, 0) -- behind: to the side it is on
		end
		if dir.Magnitude < 1e-3 then
			dir = Vector2.new(0, 1)
		end
		dir = dir.Unit
		local half = view / 2 - Vector2.new(EDGE, EDGE)
		local k = math.min(math.abs(half.X / math.max(1e-3, math.abs(dir.X))), math.abs(half.Y / math.max(1e-3, math.abs(dir.Y))))
		local at = view / 2 + dir * k
		x, y = at.X, at.Y
	end
	mark.Position = UDim2.fromOffset(x - inset.X, y - inset.Y)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local d = if root and root:IsA("BasePart") then (root.Position - p).Magnitude else 0
	R.markDist.Text = string.format("%d m", math.floor(d * METERS + 0.5))
	mark.Visible = true
end

--------------------------------------------------------------------------------------------------------------------
-- The falling parcels (every client draws the descent; the server's model stands where it lands)
--------------------------------------------------------------------------------------------------------------------

local function track(model: Instance)
	if not model:IsA("Model") or falling[model] then
		return
	end
	local landAt = tonumber(model:GetAttribute("LandAt"))
	if not landAt or serverNow() >= landAt or model:GetAttribute("Landed") == true then
		return
	end
	falling[model] = {
		final = model:GetPivot(),
		landAt = landAt,
		height = tonumber(model:GetAttribute("DropHeight")) or 140,
		fall = math.max(0.5, tonumber(model:GetAttribute("FallTime")) or 7),
		phase = math.random() * math.pi * 2,
	}
end

local function stepFalling()
	local t = serverNow()
	for model, f in pairs(falling) do
		if not model.Parent then
			falling[model] = nil
		else
			local left = f.landAt - t
			if left <= 0 or model:GetAttribute("Landed") == true then
				model:PivotTo(f.final)
				falling[model] = nil
			else
				-- a steady descent under the chute that eases into the last second (it never drops like a stone)
				local a = math.clamp(left / f.fall, 0, 1)
				local h = f.height * a
				if left < 1 then
					h = f.height * (1 / f.fall) * (left * left)
				end
				local sway = math.sin(t * 1.3 + f.phase) * math.rad(6) * a
				local turn = (t + f.phase) * 0.35
				model:PivotTo(CFrame.new(f.final.Position + Vector3.new(0, h, 0)) * f.final.Rotation
					* CFrame.Angles(sway, turn * a, sway * 0.6))
			end
		end
	end
end

-- Your own parcel opens faster on your screen (the server times the hold either way).
local function fitPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("KitOwner") == player.UserId then
		local hold = tonumber(prompt:GetAttribute("OwnerHold"))
		if hold then
			prompt.HoldDuration = hold
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function KitController.Init(controllers)
	Controllers = controllers
end

function KitController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "Kit"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.DisplayOrder = 4
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	local scale = Instance.new("UIScale") -- Theme.bindRoot keeps Root's UIScale "Scale" right for the viewport
	scale.Name = "Scale"
	scale.Parent = root
	root.Parent = screen
	screen.Parent = playerGui
	gui = screen
	buildLobby(root)
	buildArena(root)
	task.spawn(pcall, QuietUI.bindRoot, screen) -- (never holds up the rest of Start)

	local function showLobby()
		local on = lobbyShowing()
		if R.holder then
			R.holder.Visible = on
		end
	end
	ClientState.lifeChanged:Connect(showLobby)
	ClientState.spectateChanged:Connect(showLobby)
	Input.deviceChanged:Connect(placeLines)
	showLobby()
	-- (18 Nov: after a death in a practice round the line stayed hidden in the train; a cheap re-check twice a second
	-- keeps it right whatever order the life and spectate signals arrive in)
	task.spawn(function()
		while gui and gui.Parent do
			task.wait(0.5)
			if R.holder and R.holder.Visible ~= lobbyShowing() then
				showLobby()
			end
		end
	end)

	for _, attribute in ipairs({ "Kit", "KitBring", "KitArmoury" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if attribute == "Kit" and pending.kit == player:GetAttribute("Kit") then
				pending.kit = nil
			end
			if attribute == "KitBring" and bringPending == player:GetAttribute("KitBring") then
				bringPending = nil
			end
			refreshLines()
		end)
	end
	player:GetAttributeChangedSignal("KitIncoming"):Connect(onIncoming)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not lobbyShowing() then
			return
		end
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if input.KeyCode == Enum.KeyCode.K then
			cycleKit(if shift then -1 else 1)
		elseif input.KeyCode == Enum.KeyCode.B then
			cycleBring(if shift then -1 else 1)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			cycleKit(1)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			cycleKit(-1)
		end
	end)

	CollectionService:GetInstanceAddedSignal(PARCEL_TAG):Connect(track)
	for _, model in ipairs(CollectionService:GetTagged(PARCEL_TAG)) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(fitPrompt)
	for _, prompt in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do
		fitPrompt(prompt)
	end

	local lastMark = 0
	RunService.RenderStepped:Connect(function()
		if next(falling) then
			stepFalling()
		end
		local now = os.clock()
		if now - lastMark >= 1 / 30 then
			lastMark = now
			updateMark()
		end
	end)
end

return KitController
