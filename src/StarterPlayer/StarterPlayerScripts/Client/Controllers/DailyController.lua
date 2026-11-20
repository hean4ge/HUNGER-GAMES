--[[
	DailyController - the DAILY REWARD screen (docs/design/CardMenusAndShop.md 2.5, mock-up m07_daily; the owner's
	reference ui_ref_daily_reward): seven day cards in a row, each a picture and its reward, CLAIMED (dim + tick) /
	CLAIM (Sun, today only) / locked (padlock); "Next reward in 18:21:32 · a missed day pauses your streak, it never
	resets it"; the stamps top right (4 = the Regular banner trim). Built on Shared.Cards; server: DailyService.

	It opens by itself once a UTC day, the first time the player is settled in the train with a reward waiting (never
	in a round, never in the minute after one), otherwise from the menu hub: Controllers.DailyController.open().
	Public: open(), close(), isOpen(), claimable() -> boolean

	(fixesUI, 20 Nov) Never over the launch shot: while ClientState.launchShot is set the screen is hidden at once and
	closed (and it never opens by itself then). Never in the way of a fight in the Training Centre's hall: it does not
	open by itself there, and while it is open there an attack press (left mouse outside the panel, or R2) closes it
	and passes the same press on to the attack, so nothing is swallowed.
]]
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Theme = require(Shared:WaitForChild("Theme"))
local Progression = require(Shared:WaitForChild("Progression"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local ProgressUI = require(Client:WaitForChild("ProgressUI"))

local DailyController = {}

local screen: any = nil
local row: Frame? = nil
local lineLabel: TextLabel? = nil
local countdown: TextLabel? = nil
local stampsHolder: Frame? = nil
local autoDay = ""
local lastArenaAt = -math.huge
local trainSince = os.clock()
local autoOpened = false -- the screen on show was opened by itself (not from the menu hub)

local function daily(): { [string]: any }?
	local s = ProgressUI.state
	return s and s.daily
end

function DailyController.claimable(): boolean
	local d = daily()
	return d ~= nil and d.claimable == true
end

local function build()
	screen = ProgressUI.screen("DailyGui", "Daily reward", { MaxSize = Vector2.new(1200, 480) })
	local body = screen.body
	local phone = screen.phone
	-- the stamps (top right)
	local stamps = Instance.new("Frame")
	stamps.Name = "Stamps"
	stamps.BackgroundTransparency = 1
	stamps.Size = UDim2.fromScale(1, 1)
	stamps.Parent = screen.head
	local hl = Instance.new("UIListLayout")
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	hl.VerticalAlignment = Enum.VerticalAlignment.Center
	hl.Padding = UDim.new(0, 8)
	hl.SortOrder = Enum.SortOrder.LayoutOrder
	hl.Parent = stamps
	stampsHolder = stamps

	-- the countdown line
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, 0, 0, if phone then 22 else 30)
	line.Parent = body
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ll.VerticalAlignment = Enum.VerticalAlignment.Center
	ll.Padding = UDim.new(0, 6)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = line
	local a = Cards.label("Next reward in", { TextSize = if phone then 13 else 16, Color = Theme.Colors.Ink2, LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), Parent = line })
	a.Name = "Lead"
	lineLabel = a
	countdown = Cards.countdown(os.time() + Progression.secondsToNextDay(), { LayoutOrder = 2, TextSize = if phone then 15 else 19,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), Parent = line })
	Cards.label("· a missed day pauses your streak, it never resets it", { TextSize = if phone then 13 else 16,
		Color = Theme.Colors.Ink2, LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24),
		Parent = line }).Name = "Tail"

	local r = Instance.new("Frame")
	r.Name = "Days"
	r.BackgroundTransparency = 1
	r.Position = UDim2.fromOffset(0, if phone then 30 else 56)
	r.Size = UDim2.new(1, 0, 1, if phone then -30 else -70)
	r.Parent = body
	row = r
end

local function stampDisc(parent: Instance, filled: boolean, order: number)
	local disc = Instance.new("Frame")
	disc.Name = "Stamp" .. order
	disc.BackgroundTransparency = 1
	disc.Size = UDim2.fromOffset(26, 26)
	disc.LayoutOrder = order
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = disc
	local s = Instance.new("UIStroke")
	s.Color = Theme.Colors.Sun
	s.Thickness = 1.5
	s.Transparency = if filled then 0 else 0.7
	s.Parent = disc
	local seven = Cards.label("7", { Font = Theme.Fonts.MonoMedium, TextSize = 12, Color = Theme.Colors.Sun,
		Size = UDim2.fromScale(1, 1), Parent = disc })
	seven.TextXAlignment = Enum.TextXAlignment.Center
	seven.TextTransparency = if filled then 0 else 0.6
	disc.Parent = parent
end

local function render()
	if not screen or not row then
		return
	end
	local d = daily()
	local s = ProgressUI.state
	for _, c in ipairs(row:GetChildren()) do
		c:Destroy()
	end
	if not d then
		screen.sub.Text = "loading"
		return
	end
	screen.sub.Text = string.format("Week %d · streak <b>%d</b> day%s", d.week or 1, d.streak or 0, if d.streak == 1 then "" else "s")
	-- stamps
	if stampsHolder then
		for _, c in ipairs(stampsHolder:GetChildren()) do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		if not screen.phone then
			local word = Cards.label("Stamps", { TextSize = 14, Color = Theme.Colors.Ink2, LayoutOrder = 0,
				AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), Parent = stampsHolder })
			word.Name = "Word"
		end
		local trimAt = d.trimAt or 4
		local have = math.min(d.stamps or 0, trimAt)
		for i = 1, trimAt do
			stampDisc(stampsHolder, i <= have, i)
		end
		if not screen.phone then
			Cards.label(if d.trim then "Regular trim earned" else string.format('%d = "Regular" banner trim', trimAt), {
				TextSize = 14, Color = Theme.Colors.Ink2, LayoutOrder = 99, AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 24), Parent = stampsHolder }).Name = "Rule"
		end
	end
	if countdown then
		countdown:SetAttribute("EndUnix", os.time() + (d.nextIn or Progression.secondsToNextDay()))
	end
	if lineLabel then
		lineLabel.Text = if d.claimable then "Today's reward is ready · next in" else "Next reward in"
	end
	-- which card is today
	local current = if d.claimable then d.day else ((d.day - 2) % 7) + 1
	local phone = screen.phone
	local gap = if phone then 6 else 20
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local firstFocus: GuiObject? = nil
	for i = 1, 7 do
		local rewards = Progression.DailyRewards[i]
		local col = Instance.new("Frame")
		col.Name = "Day" .. i
		col.BackgroundTransparency = 1
		col.LayoutOrder = i
		col.Size = UDim2.new(1 / 7, -gap * 6 / 7, 1, 0)
		col.Parent = row
		local today = i == current
		local claimed = i < current or (today and not d.claimable)
		local dayLabel = Cards.label("Day " .. i, { Font = Theme.Fonts.SemiBold, TextSize = if phone then 14 else 19,
			Color = if today and d.claimable then Theme.Colors.Sun else Theme.Colors.Ink, Size = UDim2.new(1, 0, 0, if phone then 20 else 30),
			Parent = col })
		dayLabel.TextXAlignment = Enum.TextXAlignment.Center
		local cardH = if phone then 0.62 else 0.66
		local card = Cards.card({
			Name = "Card",
			Title = Progression.rewardsText(rewards),
			NameSize = if phone then 12 else 16,
			Picture = ProgressUI.rewardPicture(rewards[1]),
			WellHeight = 0.7,
			Big = true,
			Position = UDim2.fromOffset(0, if phone then 22 else 36),
			Size = UDim2.new(1, 0, cardH, if phone then -22 else -36),
			Selectable = false,
			Parent = col,
		})
		local title = card:FindFirstChild("Title", true) :: TextLabel?
		if title then
			title.TextXAlignment = Enum.TextXAlignment.Center
			title.TextWrapped = true
			title.Size = UDim2.new(1, 0, 0, if phone then 30 else 44)
		end
		if claimed then
			Cards.setState(card, "Owned", true)
			Cards.setState(card, "Disabled", true)
		elseif today then
			Cards.setState(card, "Claimable", true)
			Cards.setState(card, "Selected", true)
		else
			Cards.setState(card, "Locked", "")
		end
		if not (today and d.claimable) then
			local nextDay = (current % 7) + 1
			local word = if claimed then "CLAIMED" elseif i == nextDay or (today and not d.claimable) then "TOMORROW" else "LOCKED"
			local status = Cards.label(word, { Name = "Status", Font = Theme.Fonts.SemiBold, TextSize = if phone then 12 else 14,
				Color = Theme.Colors.Ink2, Position = UDim2.new(0, 0, cardH, if phone then 8 else 14),
				Size = UDim2.new(1, 0, 0, if phone then 44 else 48), Parent = col })
			status.TextXAlignment = Enum.TextXAlignment.Center
			continue
		end
		local kind = "Sun"
		local word = "Claim"
		local button = Cards.button(kind, word, { Name = "Claim", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, if phone then 44 else 48), AutomaticSize = Enum.AutomaticSize.None, TextSize = if phone then 13 else 16,
			Parent = col })
		button.Position = UDim2.new(0, 0, cardH, if phone then 8 else 14)
		button.AnchorPoint = Vector2.new(0, 0)
		local pads = button:FindFirstChild("Pad") :: UIPadding?
		if pads then
			pads.PaddingLeft, pads.PaddingRight = UDim.new(0, 2), UDim.new(0, 2)
		end
		button.Selectable = today and d.claimable == true
		if today and d.claimable then
			firstFocus = button
			button.Activated:Connect(function()
				Cards.setButtonKind(button, "Off")
				button.Text = "…"
				ProgressUI.send({ t = "daily" })
			end)
		end
	end
	if firstFocus and screen.isOpen() and ProgressUI.isGamepad() then
		GuiService.SelectedObject = firstFocus
	end
end

function DailyController.open(): boolean
	if not screen then
		return false
	end
	if Cards.metrics().phone ~= screen.phone then
		DailyController.rebuild() -- built before the window had its size, or the device class changed
	end
	local ok = screen.open()
	if ok then
		render()
	end
	return ok
end

function DailyController.close()
	if screen then
		screen.close()
	end
end

-- builds the screen again (after the device class changes; tests)
function DailyController.rebuild()
	if screen then
		screen.close()
		screen.gui:Destroy()
	end
	build()
end

function DailyController.isOpen(): boolean
	return screen ~= nil and screen.isOpen()
end

-- (fixesUI) The Training Centre's hall: TrainingService sets InTraining while the character stands there
local function inHall(): boolean
	return Players.LocalPlayer:GetAttribute("InTraining") == true
end

-- (fixesUI) an attack press while the screen is open in the hall: close it, then let the same press reach the attack
-- (CombatController's "Attack" binding sits at priority 2000; this one is just above it and always passes)
local HALL_ACTION = "DailyHallAttack"
local hallBound = false

local function overPanel(): boolean
	local panel = screen and screen.panel
	if not panel then
		return false
	end
	local p = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local a, s = panel.AbsolutePosition, panel.AbsoluteSize
	return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

local function onHallAttack(state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin and DailyController.isOpen() and inHall() then
		local mouse = io ~= nil and io.UserInputType == Enum.UserInputType.MouseButton1
		if not (mouse and overPanel()) then
			DailyController.close() -- ClientState.menuOpen clears now, before the attack binding sees this press
		end
	end
	return Enum.ContextActionResult.Pass
end

local function syncGuards()
	if not screen then
		return
	end
	-- never over the launch shot: hidden at once (no fade), then closed
	if ClientState.launchShot then
		if screen.gui.Enabled then
			screen.gui.Enabled = false
		end
		if screen.isOpen() then
			DailyController.close()
		end
	end
	local want = screen.isOpen() and inHall()
	if want ~= hallBound then
		hallBound = want
		if want then
			ContextActionService:BindActionAtPriority(HALL_ACTION, onHallAttack, false, 2050,
				Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
		else
			ContextActionService:UnbindAction(HALL_ACTION)
		end
	end
end

-- once a UTC day, settled in the train with a reward waiting
local function maybeAutoOpen()
	local d = daily()
	if not d or not d.claimable or d.enabled == false then
		return
	end
	local today = Progression.utcDay()
	if autoDay == today or not ProgressUI.inTrain() or ClientState.menuOpen or ProgressUI.anyOpen() then
		return
	end
	-- (fixesUI) not in the Training Centre's hall (it would cover the fight) and never over the launch shot
	if inHall() or ClientState.launchShot then
		return
	end
	-- (hunt2_1) only while parked at the station: never over the loading screen, the ride (it covered the tunnel and
	-- the arrival, then Prepare opened as it closed) or anywhere at the Training Centre (Prepare is its screen)
	local me = Players.LocalPlayer
	local gameState = ReplicatedStorage:FindFirstChild("GameState")
	if me:GetAttribute("LoadingScreenUp") == true or me:GetAttribute("AtTrainingCentre") == true
		or (gameState and gameState:GetAttribute("TrainStage") == "Ride") then
		return
	end
	if os.clock() - lastArenaAt < 60 or os.clock() - trainSince < 4 then
		return
	end
	if workspace:GetAttribute("DailyAutoOpen") == false then
		return
	end
	autoDay = today
	if DailyController.open() then
		autoOpened = true
	end
end

function DailyController.Init(controllers)
	ProgressUI.Controllers = ProgressUI.Controllers or controllers
end

function DailyController.Start()
	build()
	ProgressUI.openers.daily = function(arg)
		autoOpened = false
		if arg == "phone" then
			DailyController.rebuild()
		end
		DailyController.open()
	end
	ProgressUI.stateChanged:Connect(function()
		if screen and screen.isOpen() then
			render()
		end
		maybeAutoOpen()
	end)
	ProgressUI.on("claimed", function(msg)
		if msg.what == "daily" then
			Sfx.play("UIClick", { pitch = 0.9 })
			-- (hunt1_1) nothing is left to do here once today's reward is in: the screen shows CLAIMED for a moment,
			-- then closes by itself, so the player is not left hunting for the small close button
			task.delay(1.6, function()
				local d = daily()
				if screen and screen.isOpen() and not (d and d.claimable) then
					DailyController.close()
				end
			end)
		end
	end)
	local wasInArena = ClientState.inArena
	ClientState.lifeChanged:Connect(function()
		if ClientState.inArena or wasInArena then
			lastArenaAt = os.clock() -- in a round, or just back from one
		end
		if not ClientState.inArena and wasInArena then
			trainSince = os.clock()
		end
		wasInArena = ClientState.inArena
	end)
	-- (hunt2_1) the doors seal: a screen that opened by itself at the station and is still up goes, so it never covers
	-- the ride and the arrival; with the reward still waiting it may open by itself again at the next station stop
	local gameState = ReplicatedStorage:WaitForChild("GameState")
	gameState:GetAttributeChangedSignal("TrainStage"):Connect(function()
		if gameState:GetAttribute("TrainStage") ~= "Ride" then
			return
		end
		if autoOpened and screen and screen.isOpen() then
			DailyController.close()
			if DailyController.claimable() then
				autoDay = ""
			end
		end
		autoOpened = false
	end)
	-- (fixesUI) the launch shot and the hall, every frame (cheap: two attribute reads)
	RunService.Heartbeat:Connect(syncGuards)
	while true do
		task.wait(5)
		pcall(maybeAutoOpen)
	end
end

return DailyController
