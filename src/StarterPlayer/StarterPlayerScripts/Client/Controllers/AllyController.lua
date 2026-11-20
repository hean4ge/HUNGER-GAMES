--[[
	AllyController - the client side of allies (the truce; server: AllyService; design: docs/design/TrainingAndLoadup.md
	section 4). UI style A, Quiet: thin lines of text on the picture, no boxes.

	CHOOSING
	  * Walk up and ask: look at a player within 10 studs and a thin line shows under the crosshair:
	      [T]  Offer a truce · Wren          (they offered first: "Accept Wren's truce"; already allies: "Allies · Wren")
	    Hold T (gamepad Y) for 0.4 s; a hairline under the words fills while you hold. On touch the line is the button:
	    tap it.
	  * The answer: whoever is asked sees one line for 15 s, "Wren offers a truce · hold T to accept" (touch: tap it).
	    Hold T with nobody in view to accept the newest offer. Silence is a no.
	  * The quiet list (phones, gamepads, anyone shy): before the call, a dim "ALLIES" word sits at the left edge (tap or
	    click it, or tap T with nobody in view). It opens a list of the players waiting, each with OFFER, ACCEPT, WAITING
	    or ALLY, the group's size and cap, and LEAVE TRUCE. Text and hairlines only.
	SHOWING ALLIES
	  * Over each ally's head: a small sage double bar (Theme.Colors.Ally when the Theme has it, else #9DBFAE), 1.2
	    studs above the head at a fixed 18 x 10 px, no name, no health. Through walls within 60 studs, in line of sight
	    out to 300, never further. The same in the prep room as soon as a group forms.
	  * On the compass (arena only, while the compass shows): a short sage tick with the ally's initial at their
	    bearing, built into HUD.Root.Top.Compass.Markers with HUDController's own numbers (360 px for 150 degrees).
	WHEN IT ENDS
	  One soft low bell (the bell and four-left ends), one quiet line ("The truce is over", "Wren broke the truce", ...),
	  the marks fade over 2 s and the compass ticks go.

	Input: action "Ally" = T and ButtonY (priority 1900; it passes the key on whenever there is nothing to do with it,
	so the lobby's spectate and a fire's second action keep ButtonY).
	API: AllyController.getAllies() -> { [userId]: name }; AllyController.openList(on?: boolean);
	     AllyController.isOpen() -> boolean
	Studio tests: AllyController._test(cmd, arg) (see the bottom).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Input = require(Shared:WaitForChild("Input"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local GameState = ReplicatedStorage:WaitForChild("GameState")

local SAGE = (Theme.Colors :: any).Ally or Color3.fromRGB(157, 191, 174) -- #9DBFAE: allies only (one colour, one meaning)
local REACH = 10 -- studs: the walk-up gesture
local AIM_DEG = 11 -- how far off the crosshair a head may be and still be "looked at"
local HOLD = 0.4
local SEE_THROUGH = 60 -- marks show through walls this close
local SEE_MAX = 300
local FADE = 2
local COMPASS_WIDTH, COMPASS_SPAN, MARKER_Y = 360, 150, 24 -- HUDController's numbers

local AllyController = {}

local gui: ScreenGui? = nil
local R: { [string]: any } = {}
local state = { allies = {}, size = 1, cap = 0, context = "", offersIn = {}, offersOut = {}, truceOver = false }
local allyIds: { [number]: string } = {} -- userId -> name
local offersIn: { [number]: { name: string, expires: number } } = {}
local offersOut: { [number]: number } = {}
local dismissed: { [number]: number } = {} -- offers answered by a truce with someone else (userId -> until, os.clock)
local marks: { [number]: { bb: BillboardGui, tick: Frame?, bars: { Frame }, seen: boolean, fading: boolean } } = {}
local target: Player? = nil
local holding: { t0: number, target: Player?, offerFrom: number? }? = nil
local listOpen = false
local lineToken = 0
local testTarget: Player? = nil
local testNone = false -- (tests: nobody is looked at)
local lastLines: { string } = {} -- what was shown, newest last (tests)

-- Helpers -----------------------------------------------------------------------------------------------------------

local function phase(): string
	return tostring(GameState:GetAttribute("Phase") or "Lobby")
end

local function myContext(): string
	local ph = phase()
	if ph == "Active" then
		return if ClientState.inArena and ClientState.alive and GameState:GetAttribute("Practice") ~= true then "arena" else ""
	elseif ph == "Countdown" or ph == "Ending" then
		return ""
	end
	return if not ClientState.inArena and not ClientState.alive then "prep" else ""
end

local function theirContext(p: Player): string
	local ph = phase()
	if ph == "Active" then
		return if p:GetAttribute("Alive") == true and p:GetAttribute("InArena") == true then "arena" else ""
	elseif ph == "Countdown" or ph == "Ending" then
		return ""
	end
	return if p:GetAttribute("InArena") ~= true and p:GetAttribute("Alive") ~= true then "prep" else ""
end

local function head(p: Player): BasePart?
	local c = p.Character
	local h = c and c:FindFirstChild("Head")
	return if h and h:IsA("BasePart") then h else nil
end

local function send(op: string, userId: number?)
	Net.event("AllyAsk"):FireServer({ op = op, target = userId })
end

local function newestOffer(): (number?, string?)
	local best, bestT, name = nil, -math.huge, nil
	local t = os.clock()
	for id, o in pairs(offersIn) do
		if o.expires > t and o.expires > bestT then
			best, bestT, name = id, o.expires, o.name
		end
	end
	return best, name
end

local function keyText(): string
	return if Input.isGamepad() then "Y" else "T"
end

local function shade(o: GuiObject)
	local s = Instance.new("UIStroke")
	s.Name = "Shadow"
	s.Color = Theme.Colors.Shade
	s.Transparency = 0.45
	s.Thickness = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
end

-- The quiet line (one at a time) ------------------------------------------------------------------------------------

local function showLine(text: string, sub: string?, seconds: number?, tone: string?)
	if not R.line then
		return
	end
	lineToken += 1
	local token = lineToken
	table.insert(lastLines, text .. (if sub then " | " .. sub else ""))
	if #lastLines > 20 then
		table.remove(lastLines, 1)
	end
	R.lineText.Text = text
	R.lineSub.Text = sub or ""
	R.lineSub.Visible = sub ~= nil and sub ~= ""
	R.line.Visible = true
	QuietUI.fadeText(R.lineText, true, 0.2)
	if sub then
		QuietUI.fadeText(R.lineSub, true, 0.2)
	end
	if tone == "bell" then
		Sfx.play("RollCallToneSoft", { volume = 0.35, pitch = 0.82 })
	else
		Sfx.play("Notify", { volume = 0.35, pitch = 0.9 })
	end
	task.delay(seconds or 4, function()
		if lineToken == token and R.line then
			QuietUI.fadeText(R.lineText, false, 0.6)
			QuietUI.fadeText(R.lineSub, false, 0.6)
			task.delay(0.65, function()
				if lineToken == token and R.line then
					R.line.Visible = false
				end
			end)
		end
	end)
end

-- Marks over heads and on the compass --------------------------------------------------------------------------------

local function compassMarkers(): Instance?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("HUD")
	local root = hud and hud:FindFirstChild("Root")
	local top = root and root:FindFirstChild("Top")
	local compass = top and top:FindFirstChild("Compass")
	return compass and compass:FindFirstChild("Markers")
end

local function makeMark(userId: number, name: string)
	if marks[userId] then
		local m = marks[userId]
		if m.fading then
			-- agreed again while fading: back to full
			m.fading = false
			for _, b in ipairs(m.bars) do
				b.BackgroundTransparency = 0
			end
		end
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "AllyMark_" .. userId
	bb.Size = UDim2.fromOffset(18, 10)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1.2 + 0.6, 0) -- 1.2 studs over the top of the head (its centre + half)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = SEE_MAX
	bb.ResetOnSpawn = false
	bb.Enabled = false
	local bars = {}
	for i = 0, 1 do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. (i + 1)
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Position = UDim2.new(0.5, 0, 0, 1 + i * 5)
		bar.Size = UDim2.fromOffset(14, 2)
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = SAGE
		bar.Parent = bb
		shade(bar)
		table.insert(bars, bar)
	end
	bb.Parent = player:FindFirstChildOfClass("PlayerGui")

	local tick: Frame? = nil
	local markers = compassMarkers()
	if markers then
		local f = Instance.new("Frame")
		f.Name = "Ally_" .. userId
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, 0, 0, MARKER_Y)
		f.Size = UDim2.fromOffset(12, 14)
		f.BackgroundTransparency = 1
		f.Visible = false
		local t = Instance.new("Frame")
		t.Name = "Tick"
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.5)
		t.Size = UDim2.fromOffset(2, 9)
		t.BorderSizePixel = 0
		t.BackgroundColor3 = SAGE
		t.Parent = f
		shade(t)
		table.insert(bars, t)
		local letter = QuietUI.label({
			Name = "Initial",
			Text = string.upper(string.sub(name, 1, 1)),
			Font = "SemiBold",
			TextSize = Theme.TextSize.Small,
			TextColor3 = SAGE,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 1),
			Size = UDim2.fromOffset(14, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = f,
		})
		letter.Name = "Initial"
		f.Parent = markers
		tick = f
	end
	marks[userId] = { bb = bb, tick = tick, bars = bars, seen = false, fading = false }
end

local function fadeMark(userId: number)
	local m = marks[userId]
	if not m or m.fading then
		return
	end
	m.fading = true
	for _, b in ipairs(m.bars) do
		QuietUI.tween(b, FADE, { BackgroundTransparency = 1 })
	end
	if m.tick then
		local letter = m.tick:FindFirstChild("Initial")
		if letter and letter:IsA("TextLabel") then
			QuietUI.fadeText(letter, false, FADE)
		end
	end
	task.delay(FADE + 0.1, function()
		local now = marks[userId]
		if now == m and m.fading then
			marks[userId] = nil
			m.bb:Destroy()
			if m.tick then
				m.tick:Destroy()
			end
		end
	end)
end

local function syncMarks()
	for id, name in pairs(allyIds) do
		makeMark(id, name)
	end
	for id in pairs(marks) do
		if not allyIds[id] then
			fadeMark(id)
		end
	end
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local lastLos = 0

local function updateMarks()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camCF = cam.CFrame
	local camPos = camCF.Position
	local now = os.clock()
	local checkLos = now - lastLos > 0.25
	if checkLos then
		lastLos = now
	end
	-- the compass's heading (HUDController's formula)
	local right = camCF.RightVector
	local heading = math.deg(math.atan2(right.Z, right.X)) % 360
	local pxPerDeg = COMPASS_WIDTH / COMPASS_SPAN
	local half = COMPASS_SPAN / 2
	local markers = compassMarkers()
	local top = markers and markers.Parent and markers.Parent.Parent
	local compassOn = phase() == "Active" and ClientState.inArena and ClientState.alive and top ~= nil
		and (top :: any).Visible == true and not ClientState.launchShot
	for id, m in pairs(marks) do
		local p = Players:GetPlayerByUserId(id)
		local h = p and head(p)
		if not h then
			m.bb.Enabled = false
			if m.tick then
				m.tick.Visible = false
			end
			continue
		end
		if m.bb.Adornee ~= h then
			m.bb.Adornee = h
		end
		local d = (h.Position - camPos).Magnitude
		if d <= SEE_THROUGH then
			m.seen = true
		elseif d > SEE_MAX then
			m.seen = false
		elseif checkLos then
			local myChar = player.Character
			losParams.FilterDescendantsInstances = if myChar then { myChar, (p :: Player).Character :: any } else { (p :: Player).Character :: any }
			local hit = workspace:Raycast(camPos, h.Position - camPos, losParams)
			m.seen = hit == nil
		end
		m.bb.Enabled = m.seen and not ClientState.launchShot
		-- a tick on the compass at the ally's bearing
		if m.tick then
			if compassOn then
				local dx, dz = h.Position.X - camPos.X, h.Position.Z - camPos.Z
				local b = math.deg(math.atan2(dx, -dz)) % 360
				local delta = ((b - heading + 540) % 360) - 180
				local x = math.clamp(delta, -(half - 4), half - 4) * pxPerDeg
				m.tick.Position = UDim2.new(0.5, x, 0, MARKER_Y)
				m.tick.Visible = true
			else
				m.tick.Visible = false
			end
		end
	end
end

-- The look-at line under the crosshair -------------------------------------------------------------------------------

local function findTarget(): Player?
	if testTarget and testTarget.Parent == Players then
		return testTarget
	elseif testNone then
		return nil
	end
	local cam = workspace.CurrentCamera
	local myChar = player.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not (cam and myRoot and myRoot:IsA("BasePart")) then
		return nil
	end
	local ctx = myContext()
	if ctx == "" then
		return nil
	end
	local camCF = cam.CFrame
	local look = camCF.LookVector
	local best, bestAng = nil, AIM_DEG
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and theirContext(p) == ctx then
			local h = head(p)
			if h and (h.Position - myRoot.Position).Magnitude <= REACH then
				local dir = h.Position - camCF.Position
				if dir.Magnitude > 0.1 then
					local ang = math.deg(math.acos(math.clamp(look:Dot(dir.Unit), -1, 1)))
					if ang < bestAng then
						best, bestAng = p, ang
					end
				end
			end
		end
	end
	return best
end

local function hintFor(p: Player): (string, boolean)
	if allyIds[p.UserId] then
		return "Allies · " .. p.DisplayName, false
	end
	local o = offersIn[p.UserId]
	if o and o.expires > os.clock() then
		return "Accept " .. p.DisplayName .. "'s truce", true
	end
	local out = offersOut[p.UserId]
	if out and out > os.clock() then
		return "Truce offered · " .. p.DisplayName, false
	end
	return "Offer a truce · " .. p.DisplayName, true
end

local function updateHint()
	if not R.hint then
		return
	end
	local p = target
	local show = p ~= nil and not ClientState.menuOpen and not ClientState.launchShot
	if show and p then
		local text, actionable = hintFor(p)
		R.hintText.Text = text
		R.hintKey.Visible = actionable and not Input.isTouch()
		QuietUI.setKey(R.hintKey, keyText())
		R.hintText.TextTransparency = if actionable then 0 else Theme.Transparency.TextDim
	end
	R.hint.Visible = show
	R.hint.Active = Input.isTouch() -- a button only on touch: never in the way of a mouse click
	-- the hold's hairline
	if holding and holding.t0 then
		local a = math.clamp((os.clock() - holding.t0) / HOLD, 0, 1)
		R.hold.Size = UDim2.new(a, 0, 0, 1)
		R.hold.Visible = true
	else
		R.hold.Visible = false
	end
end

-- The offer line (15 s) ----------------------------------------------------------------------------------------------

local function updateOfferLine()
	if not R.offer then
		return
	end
	local id, name = newestOffer()
	local show = id ~= nil and not ClientState.launchShot
	if show and name then
		local o = offersIn[id :: number]
		local left = math.max(0, math.ceil(o.expires - os.clock()))
		local how = if Input.isTouch() then "tap to accept" else "hold " .. keyText() .. " to accept"
		R.offerText.Text = string.format("%s offers a truce · %s · %d", name, how, left)
	end
	R.offer.Visible = show
	R.offer.Active = Input.isTouch()
end

-- The quiet list -----------------------------------------------------------------------------------------------------

local function clearRows()
	for _, c in ipairs(R.rows:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function rebuildList()
	if not R.list then
		return
	end
	local ctx = myContext()
	R.entry.Visible = ctx == "prep" and not ClientState.launchShot and not ClientState.menuOpen -- (fixesUI) not through a menu
	R.list.Visible = listOpen and ctx ~= ""
	if not R.list.Visible then
		return
	end
	clearRows()
	local cap = tonumber(state.cap) or 0
	R.listSub.Text = if cap < 2 then "Truces need five or more contenders"
		else string.format("Groups of %d at most · both must agree · ends on any damage, at the bell, or at four left", cap)
	local order = 0
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and theirContext(p) == ctx then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		local aa, ba = allyIds[a.UserId] ~= nil, allyIds[b.UserId] ~= nil
		if aa ~= ba then
			return aa
		end
		return a.DisplayName < b.DisplayName
	end)
	local t = os.clock()
	for _, p in ipairs(list) do
		order += 1
		local row = Instance.new("Frame")
		row.Name = "Row_" .. p.UserId
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 26)
		row.LayoutOrder = order
		QuietUI.label({
			Name = "Name",
			Text = p.DisplayName,
			Font = "Medium",
			TextSize = Theme.TextSize.Label,
			TextColor3 = if allyIds[p.UserId] then SAGE else Theme.Colors.Ink,
			Size = UDim2.new(1, -110, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		local word, op = "OFFER", "offer"
		if allyIds[p.UserId] then
			word, op = "ALLY", nil
		elseif offersIn[p.UserId] and offersIn[p.UserId].expires > t then
			word, op = "ACCEPT", "accept"
		elseif offersOut[p.UserId] and offersOut[p.UserId] > t then
			word, op = "WAITING", nil
		end
		if cap < 2 and op then
			word, op = "", nil
		end
		local btn = QuietUI.button({
			Name = "Act",
			Text = word,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(104, 26),
			TextXAlignment = Enum.TextXAlignment.Right,
			Quiet = op == nil,
			Parent = row,
		})
		btn.Active = op ~= nil
		btn.Selectable = op ~= nil
		if op == nil then
			btn.TextColor3 = if word == "ALLY" then SAGE else Theme.Colors.Ink2
		end
		QuietUI.bindButton(btn, { quiet = op == nil })
		if op then
			local uid = p.UserId
			btn.Activated:Connect(function()
				send(op, uid)
				Sfx.play("UIClick", { pitch = 1.05 })
			end)
		end
		row.Parent = R.rows
	end
	if order == 0 then
		order += 1
		QuietUI.label({
			Name = "Empty",
			Text = "Nobody else is here yet",
			TextSize = Theme.TextSize.Label,
			TextColor3 = Theme.Colors.Ink2,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = order,
			Parent = R.rows,
		})
	end
	R.leave.Visible = next(allyIds) ~= nil and phase() ~= "Countdown"
	R.leave.LayoutOrder = order + 1
end

function AllyController.openList(on: boolean?)
	local want = if on == nil then not listOpen else on == true
	if want and (myContext() == "" or (ClientState.menuOpen and not listOpen)) then
		return
	end
	if want == listOpen then
		return
	end
	listOpen = want
	ClientState.menuOpen = want -- the mouse is the list's while it is open
	rebuildList()
	if want then
		QuietUI.fadeIn(R.list, 0.2)
		if Input.isGamepad() then
			local first = R.rows:FindFirstChildWhichIsA("Frame")
			local act = first and first:FindFirstChild("Act")
			GuiService.SelectedObject = if act and act:IsA("GuiObject") and act.Selectable then act else R.close
		end
	elseif GuiService.SelectedObject and R.list and GuiService.SelectedObject:IsDescendantOf(R.list) then
		GuiService.SelectedObject = nil
	end
end

function AllyController.isOpen(): boolean
	return listOpen
end

function AllyController.getAllies(): { [number]: string }
	return table.clone(allyIds)
end

-- Input ---------------------------------------------------------------------------------------------------------------

local function act(h: { t0: number, target: Player?, offerFrom: number? })
	if h.target and h.target.Parent == Players then
		local p = h.target
		if allyIds[p.UserId] then
			return
		end
		local o = offersIn[p.UserId]
		send(if o and o.expires > os.clock() then "accept" else "offer", p.UserId)
	elseif h.offerFrom then
		send("accept", h.offerFrom)
	end
end

local function onAllyKey(inputState: Enum.UserInputState, _io: InputObject?): Enum.ContextActionResult?
	if inputState == Enum.UserInputState.Begin then
		if listOpen then
			AllyController.openList(false)
			return Enum.ContextActionResult.Sink
		end
		if ClientState.menuOpen or ClientState.launchShot then
			return Enum.ContextActionResult.Pass
		end
		local offerFrom = newestOffer()
		local ctx = myContext()
		if not target and not offerFrom and ctx ~= "prep" then
			return Enum.ContextActionResult.Pass
		end
		if target and allyIds[target.UserId] and not offerFrom then
			return Enum.ContextActionResult.Pass
		end
		holding = { t0 = os.clock(), target = target, offerFrom = if target then nil else offerFrom }
		return Enum.ContextActionResult.Sink
	end
	-- End / Cancel
	local h = holding
	holding = nil
	if h and os.clock() - h.t0 < HOLD and not h.target and not h.offerFrom then
		AllyController.openList(true) -- a tap with nobody in view: the quiet list
	end
	return Enum.ContextActionResult.Sink
end

-- UI ------------------------------------------------------------------------------------------------------------------

local function build()
	local pg = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "Allies"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 12
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = g
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = root

	-- under the crosshair: [T]  Offer a truce · Wren
	local hint = Instance.new("TextButton")
	hint.Name = "Hint"
	hint.Text = ""
	hint.AutoButtonColor = false
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0.5, 40)
	hint.Size = UDim2.fromOffset(320, 30)
	hint.Visible = false
	hint.Parent = root
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = hint
	local key = QuietUI.key({ Name = "Key", Text = "T", LayoutOrder = 1, Parent = hint })
	local hintText = QuietUI.label({
		Name = "Text",
		Text = "",
		Font = "Medium",
		TextSize = Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		LayoutOrder = 2,
		Parent = hint,
	})
	-- the hold's hairline, under the words (outside the row's list layout)
	local holdHolder = Instance.new("Frame")
	holdHolder.Name = "HoldLine"
	holdHolder.BackgroundTransparency = 1
	holdHolder.AnchorPoint = Vector2.new(0.5, 0)
	holdHolder.Position = UDim2.new(0.5, 0, 0.5, 72)
	holdHolder.Size = UDim2.fromOffset(160, 2)
	holdHolder.Parent = root
	local hold = Instance.new("Frame")
	hold.Name = "Hold"
	hold.BorderSizePixel = 0
	hold.BackgroundColor3 = SAGE
	hold.Size = UDim2.new(0, 0, 0, 1)
	hold.Visible = false
	hold.Parent = holdHolder
	hint.Activated:Connect(function()
		if target then
			act({ t0 = os.clock(), target = target })
		end
	end)

	-- the offer, lower middle: "Wren offers a truce · hold T to accept · 12"
	local offer = Instance.new("TextButton")
	offer.Name = "Offer"
	offer.Text = ""
	offer.AutoButtonColor = false
	offer.BackgroundTransparency = 1
	offer.AnchorPoint = Vector2.new(0.5, 0.5)
	offer.Position = UDim2.new(0.5, 0, 0.7, 0)
	offer.Size = UDim2.fromOffset(560, 28)
	offer.Visible = false
	offer.Active = false
	offer.Parent = root
	local offerText = QuietUI.label({
		Name = "Text",
		Text = "",
		Font = "Medium",
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Ink,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = offer,
	})
	offer.Activated:Connect(function()
		local id = newestOffer()
		if id then
			send("accept", id)
		end
	end)

	-- one quiet line: "Truce agreed", "Wren broke the truce", "The truce is over"
	local lineFrame = Instance.new("Frame")
	lineFrame.Name = "Line"
	lineFrame.BackgroundTransparency = 1
	lineFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	lineFrame.Position = UDim2.new(0.5, 0, 0.64, 0)
	lineFrame.Size = UDim2.fromOffset(560, 46)
	lineFrame.Visible = false
	lineFrame.Parent = root
	local lineText = QuietUI.label({
		Name = "Text",
		Text = "",
		Font = "SemiBold",
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Colors.Ink,
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = lineFrame,
	})
	local lineSub = QuietUI.label({
		Name = "Sub",
		Text = "",
		Font = "Medium",
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Colors.Ink2,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = lineFrame,
	})

	-- the quiet list's word at the left edge, and the list
	local entry = QuietUI.button({
		Name = "Entry",
		Text = "ALLIES",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 0),
		Size = UDim2.fromOffset(90, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Quiet = true,
		Parent = root,
	})
	entry.Visible = false
	QuietUI.bindButton(entry, { quiet = true })
	entry.Activated:Connect(function()
		AllyController.openList()
	end)

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.AnchorPoint = Vector2.new(0, 0.5)
	list.Position = UDim2.new(0, 24, 0.5, 0)
	list.Size = UDim2.fromOffset(340, 420)
	list.Visible = false
	list.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list
	QuietUI.label({ Name = "Title", Text = "ALLIES", Font = "SemiBold", TextSize = Theme.TextSize.Label, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Parent = list })
	local listSub = QuietUI.label({
		Name = "Sub",
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.Ink2,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 2,
		Parent = list,
	})
	QuietUI.line({ Name = "Rule", LayoutOrder = 3, Parent = list })
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.Size = UDim2.new(1, 0, 0, 0)
	rows.LayoutOrder = 4
	rows.Parent = list
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, 2)
	rowsLayout.Parent = rows
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, 30)
	foot.LayoutOrder = 6
	foot.Parent = list
	local leave = QuietUI.button({ Name = "Leave", Text = "LEAVE TRUCE", Size = UDim2.fromOffset(130, 28), TextXAlignment = Enum.TextXAlignment.Left, Quiet = true, Parent = foot })
	QuietUI.bindButton(leave, { quiet = true })
	leave.Activated:Connect(function()
		send("leave")
	end)
	local close = QuietUI.button({ Name = "Close", Text = "CLOSE", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(80, 28), TextXAlignment = Enum.TextXAlignment.Right, Parent = foot })
	QuietUI.bindButton(close)
	close.Activated:Connect(function()
		AllyController.openList(false)
	end)

	g.Parent = pg
	Theme.bindRoot(g)
	gui = g
	R.hint, R.hintKey, R.hintText, R.hold = hint, key, hintText, hold
	R.offer, R.offerText = offer, offerText
	R.line, R.lineText, R.lineSub = lineFrame, lineText, lineSub
	R.entry, R.list, R.listSub, R.rows, R.leave, R.close = entry, list, listSub, rows, leave, close
end

-- From the server -----------------------------------------------------------------------------------------------------

local function onUpdate(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local kind = msg.kind
	if kind == "state" then
		local before = 0
		for _ in pairs(allyIds) do
			before += 1
		end
		state = msg
		table.clear(allyIds)
		local after = 0
		for _, a in ipairs(msg.allies or {}) do
			if type(a) == "table" and type(a.userId) == "number" then
				allyIds[a.userId] = tostring(a.name)
				after += 1
			end
		end
		local t = os.clock()
		-- a truce just agreed answers every other offer that was waiting: those lines go (they can offer again), and so
		-- do offers from allies and offers a full group could not take
		local full = (tonumber(msg.cap) or 0) > 0 and (tonumber(msg.size) or 1) >= (tonumber(msg.cap) or 0)
		table.clear(offersIn)
		for _, o in ipairs(msg.offersIn or {}) do
			local left = tonumber(o.left) or 0
			if after > before then
				dismissed[o.userId] = t + left
			end
			local gone = (dismissed[o.userId] or 0) > t
			if not gone and not allyIds[o.userId] and not full then
				offersIn[o.userId] = { name = tostring(o.name), expires = t + left }
			end
		end
		table.clear(offersOut)
		for _, o in ipairs(msg.offersOut or {}) do
			offersOut[o.userId] = t + (tonumber(o.left) or 0)
		end
		syncMarks()
		rebuildList()
	elseif kind == "offer" then
		dismissed[msg.userId] = nil -- a fresh offer from someone whose earlier one was answered by another truce
		offersIn[msg.userId] = { name = tostring(msg.name), expires = os.clock() + (tonumber(msg.left) or 15) }
		Sfx.play("Notify", { volume = 0.45 })
		rebuildList()
	elseif kind == "line" then
		showLine(tostring(msg.text), if msg.sub then tostring(msg.sub) else nil, nil, msg.tone)
	elseif kind == "ended" then
		if msg.text then
			showLine(tostring(msg.text), nil, 5, msg.tone)
		end
		-- the marks fade as the state that follows clears them (syncMarks)
	end
end

-- Lifecycle -----------------------------------------------------------------------------------------------------------

function AllyController.Init(_controllers)
end

function AllyController.Start()
	build()
	Net.event("AllyUpdate").OnClientEvent:Connect(onUpdate)
	Input.bind("Ally", onAllyKey, { keys = { Enum.KeyCode.T, Enum.KeyCode.ButtonY }, priority = 1900 })
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		if myContext() == "" and listOpen then
			AllyController.openList(false)
		end
		rebuildList()
	end)
	ClientState.lifeChanged:Connect(rebuildList)
	Players.PlayerAdded:Connect(function()
		task.delay(1, rebuildList)
	end)
	Players.PlayerRemoving:Connect(function(p)
		offersIn[p.UserId] = nil
		task.defer(rebuildList)
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			local t = findTarget()
			if t ~= target then
				target = t
			end
			updateOfferLine()
			-- (fixesUI) the ALLIES word never shows through an open menu (the hub, Daily, Settings ...): it hides while
			-- one is up (the quiet list itself counts: it takes the word's place) and comes back when the last one closes
			if R.entry then
				local entryWanted = myContext() == "prep" and not ClientState.launchShot and not ClientState.menuOpen
				if R.entry.Visible ~= entryWanted then
					R.entry.Visible = entryWanted
				end
			end
			-- offers that ran out
			local now = os.clock()
			for id, o in pairs(offersIn) do
				if o.expires <= now then
					offersIn[id] = nil
				end
			end
		end
		if holding and os.clock() - holding.t0 >= HOLD then
			local h = holding
			holding = nil
			act(h)
		end
		updateHint()
		if next(marks) then
			updateMarks()
		end
	end)
end

-- Studio tests (AllyTest's bot) ---------------------------------------------------------------------------------------
-- "aim" userId: treat that player as looked at (nil clears); "hold" seconds: press and release the Ally key as a
-- player would; "tap": the same, short; "state": what this screen shows.
function AllyController._test(cmd: string, arg: any): any
	if not RunService:IsStudio() then
		return nil
	end
	if cmd == "aim" then
		testTarget = if arg then Players:GetPlayerByUserId(arg) else nil
		target = findTarget()
		return target and target.Name
	elseif cmd == "hold" or cmd == "tap" then
		if cmd == "tap" then
			testNone, target = true, nil -- a tap with nobody in view
		end
		onAllyKey(Enum.UserInputState.Begin, nil)
		task.wait(if cmd == "tap" then 0.1 else (tonumber(arg) or 0.5))
		onAllyKey(Enum.UserInputState.End, nil)
		testNone = false
		return true
	elseif cmd == "state" then
		local out = { allies = {}, marks = {}, lines = table.clone(lastLines), listOpen = listOpen }
		for id, name in pairs(allyIds) do
			table.insert(out.allies, name .. "#" .. id)
		end
		for id, m in pairs(marks) do
			table.insert(out.marks, {
				id = id,
				enabled = m.bb.Enabled,
				adornee = if m.bb.Adornee then m.bb.Adornee:GetFullName() else "nil",
				fading = m.fading,
				bar = m.bars[1] and m.bars[1].BackgroundTransparency,
				tick = m.tick ~= nil and m.tick.Visible,
				tickX = if m.tick then m.tick.Position.X.Offset else nil,
			})
		end
		out.hint = if R.hint and R.hint.Visible then R.hintText.Text else ""
		out.offer = if R.offer and R.offer.Visible then R.offerText.Text else ""
		out.line = if R.line and R.line.Visible then R.lineText.Text .. (if R.lineSub.Text ~= "" then " | " .. R.lineSub.Text else "") else ""
		out.entry = R.entry and R.entry.Visible
		out.cap = state.cap
		out.context = state.context
		local rows = {}
		if R.rows then
			for _, row in ipairs(R.rows:GetChildren()) do
				local act = row:FindFirstChild("Act")
				local nm = row:FindFirstChild("Name")
				if act and nm then
					table.insert(rows, nm.Text .. ":" .. act.Text)
				end
			end
		end
		out.rows = rows
		return out
	elseif cmd == "list" then
		AllyController.openList(arg == true)
		return listOpen
	elseif cmd == "press" then
		-- press a list row's button for that userId (the same as a click)
		local row = R.rows and R.rows:FindFirstChild("Row_" .. tostring(arg))
		local act = row and row:FindFirstChild("Act")
		if act and act:IsA("TextButton") and act.Active then
			local word = act.Text
			send(if word == "ACCEPT" then "accept" else "offer", arg)
			return word
		end
		return false
	end
	return nil
end

return AllyController
