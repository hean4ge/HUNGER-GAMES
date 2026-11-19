--[[
	TrainingController - the Training Centre on this client (docs/design/TrainingAndLoadup.md section 3; the server half
	is TrainingService, the numbers Shared.TrainingStations). UI style A, Quiet: no boxes, a few words and thin lines.

	  The guidance: while the player stands at one of the station's own things (its chest, an orange mat, the pad or
	    line its drill starts from; within ANCHOR_REACH studs), small lines low in the middle of the screen say what it is
	    and how its drill starts ("ARCHERY LANES" / "Step on a lane's orange line to start · ..."). Crossing a station's
	    floor (the walk to the launch doors crosses the track's) shows nothing.
	  The drill: while one runs, the same place shows its name, the score and the time left ("ARCHERY · 3 / 6 · 0:12");
	    at its end one result line for 4 s ("ARCHERY · 5 / 6 · passed · +1 token").
	  Lines: the server's short notes (kit mat, borrowed items back), under the guidance, for 3 s.
	  Prompts: the hall's ProximityPrompts (tag TrainingPrompt, Style Custom) are drawn here as "[E] Borrow ..." with
	    a thin hold line while HUDController is not showing them (outside the arena it draws none).
	  Bike: seated on a Seat with attribute TrainingBike, a line gauge with a green band; tap E, click or the PEDAL
	    button (gamepad R2) to push the needle up; 20 s in the green passes. The result goes to the server.
	  Weights: after the bench's Lift prompt, a ring closes on a fixed circle once per beat; press on the beat (E, click,
	    LIFT, R2). 10 clean lifts pass; the attempt ends after 14 beats.
	Remote ReplicatedStorage.Remotes.Training (TrainingService). Nothing here runs per frame outside the hall.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Theme = require(Shared:WaitForChild("Theme"))
local TS = require(Shared:WaitForChild("TrainingStations"))

local player = Players.LocalPlayer
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local TrainingController = {}

local remote: RemoteEvent? = nil
local gui: ScreenGui? = nil
local ui: { [string]: any } = {}
local drill: { [string]: any }? = nil -- the running drill, as the server last said
local resultUntil = 0
local lineUntil = 0
local shownPrompt: ProximityPrompt? = nil
local promptHoldAt: number? = nil
local bike: { [string]: any }? = nil
local weights: { [string]: any }? = nil
local renderConn: RBXScriptConnection? = nil

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function label(name: string, parent: Instance, y: number, size: number, font: string, color: Color3?): TextLabel
	local l = QuietUI.label({
		Name = name,
		Parent = parent,
		Size = UDim2.new(1, 0, 0, size + 6),
		Position = UDim2.new(0, 0, 0, y),
		Text = "",
		TextSize = size,
		Font = font,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	if color then
		l.TextColor3 = color
	end
	return l
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "TrainingGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 4
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- the guidance block: small and low in the middle (wave 16: high in the middle it sat over the view on every walk
	-- across a station's floor), between the lobby's title (bottom left) and the list of who is here (bottom right)
	local block = Instance.new("Frame")
	block.Name = "Guide"
	block.BackgroundTransparency = 1
	block.AnchorPoint = Vector2.new(0.5, 1)
	block.Position = UDim2.new(0.5, 0, 1, -84) -- (over the Loadout summary line)
	block.Size = UDim2.new(0, 560, 0, 88)
	block.Visible = false -- (until the hall: its empty rule line showed alone on the train and the platform)
	block.Parent = screen
	ui.block = block
	ui.title = label("Title", block, 0, Theme.TextSize.Label, "SemiBold")
	ui.rule = QuietUI.line({ Name = "Rule", Parent = block, Size = UDim2.new(0, 160, 0, 1), Position = UDim2.new(0.5, -80, 0, 22) })
	ui.how = label("How", block, 27, Theme.TextSize.Small, "Medium", Theme.Colors.Ink2)
	ui.note = label("Note", block, 50, Theme.TextSize.Small, "Medium", Theme.Colors.Ink2)
	ui.sub = label("Sub", block, 68, Theme.TextSize.Small, "Regular", Theme.Colors.Ink2)

	-- the prompt line, under the crosshair
	local promptLine = label("Prompt", screen, 0, Theme.TextSize.Body, "Medium")
	promptLine.AnchorPoint = Vector2.new(0.5, 0)
	promptLine.Size = UDim2.new(0, 420, 0, 22)
	promptLine.Position = UDim2.new(0.5, 0, 0.5, 40)
	ui.prompt = promptLine
	local hold = Instance.new("Frame")
	hold.Name = "Hold"
	hold.BackgroundColor3 = Theme.Colors.Ink
	hold.BorderSizePixel = 0
	hold.AnchorPoint = Vector2.new(0.5, 0)
	hold.Position = UDim2.new(0.5, 0, 0.5, 66)
	hold.Size = UDim2.new(0, 0, 0, 2)
	hold.Visible = false
	hold.Parent = screen
	ui.hold = hold

	-- the gauge (bike) and the beat ring (weights), centred a little under the crosshair
	local gauge = Instance.new("Frame")
	gauge.Name = "Gauge"
	gauge.BackgroundTransparency = 1
	gauge.AnchorPoint = Vector2.new(0.5, 0.5)
	gauge.Position = UDim2.new(0.5, 0, 0.62, 0)
	gauge.Size = UDim2.new(0, 360, 0, 28)
	gauge.Visible = false
	gauge.Parent = screen
	ui.gauge = gauge
	QuietUI.line({ Name = "Track", Parent = gauge, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0.5, 0) })
	local green = Instance.new("Frame")
	green.Name = "Green"
	green.BorderSizePixel = 0
	green.BackgroundColor3 = Theme.Colors.Sun
	green.BackgroundTransparency = 0.25
	green.Position = UDim2.new(0.5, 0, 0.5, -1)
	green.Size = UDim2.new(0.25, 0, 0, 3)
	green.Parent = gauge
	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.BorderSizePixel = 0
	needle.BackgroundColor3 = Theme.Colors.Ink
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Position = UDim2.new(0, 0, 0.5, 0)
	needle.Size = UDim2.new(0, 2, 0, 18)
	needle.Parent = gauge
	QuietUI.stroke(needle)
	ui.needle = needle

	local ring = Instance.new("Frame")
	ring.Name = "Beat"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0.6, 0)
	ring.Size = UDim2.new(0, 60, 0, 60)
	ring.Visible = false
	ring.Parent = screen
	local fixed = Instance.new("Frame")
	fixed.Name = "Fixed"
	fixed.BackgroundTransparency = 1
	fixed.AnchorPoint = Vector2.new(0.5, 0.5)
	fixed.Position = UDim2.fromScale(0.5, 0.5)
	fixed.Size = UDim2.fromOffset(60, 60)
	Instance.new("UICorner", fixed).CornerRadius = UDim.new(1, 0)
	local fs = Instance.new("UIStroke", fixed)
	fs.Color = Theme.Colors.Ink
	fs.Thickness = 1.5
	fixed.Parent = ring
	local closing = fixed:Clone()
	closing.Name = "Closing"
	closing.Parent = ring
	ui.ring = ring
	ui.closing = closing
	ui.closingStroke = closing:FindFirstChildOfClass("UIStroke")

	-- one touch button for both (PEDAL / LIFT)
	local tap = QuietUI.button({ Name = "Tap", Parent = screen, Text = "PEDAL", AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -40, 1, -180), Size = UDim2.fromOffset(120, 44), Visible = false })
	QuietUI.bindButton(tap)
	ui.tap = tap

	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
end

local function setText(l: TextLabel, text: string?)
	local t = text or ""
	if l.Text ~= t then
		l.Text = t
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The two timing drills
--------------------------------------------------------------------------------------------------------------------

local function press()
	local now = os.clock()
	if bike then
		bike.value = math.min(1, bike.value + 0.085)
		return true
	elseif weights and weights.started then
		local phase = (now - weights.t0) / weights.period
		local nearest = math.floor(phase + 0.5)
		local off = math.abs(phase - nearest) * weights.period
		if nearest >= 1 and nearest ~= weights.lastPressed then
			weights.lastPressed = nearest
			if off <= 0.2 then
				weights.clean += 1
				pcall(Sfx.play, "UIClick", { volume = 0.5, pitch = 1.1 })
				weights.flash = now
			else
				weights.miss = now
			end
		end
		return true
	end
	return false
end

local function finishBike(reason: string?)
	local b = bike
	bike = nil
	if b and remote then
		(remote :: RemoteEvent):FireServer({ t = "bike", green = b.green, reason = reason })
	end
end

local function finishWeights()
	local w = weights
	weights = nil
	if w and remote then
		(remote :: RemoteEvent):FireServer({ t = "weights", clean = w.clean, beats = w.beats })
	end
	for _, pr in ipairs(CollectionService:GetTagged("TrainingPrompt")) do
		if pr:IsA("ProximityPrompt") and pr.ActionText == "Lift" then
			pr.Enabled = true
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Every frame while in the hall
--------------------------------------------------------------------------------------------------------------------

local function stationLine(id: string?): (string?, string?)
	local station = TS.get(id)
	if not station then
		return nil, nil
	end
	if station.drill then
		return string.upper(station.name), station.drill.line
	end
	if station.id == "fitness" then
		return "FITNESS CORNER", "Climbing wall · bikes · weights"
	elseif station.id == "track" then
		return "TRACK AND OBSTACLE RUN", "Cross the orange line for a lap · the orange pad starts the run"
	end
	return string.upper(station.name), nil
end

-- Is the player at one of this station's own things (TrainingService's parts in workspace.TrainingStations.<id>:
-- the chest, the orange mats, the pads and lines a drill starts from)? Checked five times a second.
local ANCHOR_REACH = 3 -- studs, across the floor, from the thing's edge (5 caught the arch beside archery lane 1)
local ANCHOR_NAMES = { "^Chest$", "^Mat_", "^CentrePad$", "^LaneStart", "^ThrowLine$", "^RunStart$", "^LapLine$" }
local anchorCache: { [string]: { BasePart } } = {}
local nearAt, nearBay, nearWas = 0, nil :: string?, false

local function anchorsFor(id: string): { BasePart }
	local list = anchorCache[id]
	if list and (#list == 0 or list[1].Parent) then
		return list
	end
	list = {}
	local folder = workspace:FindFirstChild("TrainingStations")
	local model = folder and folder:FindFirstChild(id)
	if model then
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("BasePart") then
				for _, pattern in ipairs(ANCHOR_NAMES) do
					if string.match(d.Name, pattern) then
						table.insert(list, d)
						break
					end
				end
			end
		end
	end
	anchorCache[id] = list
	return list
end

local function atStation(id: string?): boolean
	if not id then
		return false
	end
	local now = os.clock()
	if id == nearBay and now < nearAt then
		return nearWas
	end
	nearBay, nearAt, nearWas = id, now + 0.2, false
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, p in ipairs(anchorsFor(id)) do
		local lp = p.CFrame:PointToObjectSpace((root :: BasePart).Position)
		local dx = math.max(0, math.abs(lp.X) - p.Size.X / 2)
		local dz = math.max(0, math.abs(lp.Z) - p.Size.Z / 2)
		if dx * dx + dz * dz <= ANCHOR_REACH * ANCHOR_REACH and math.abs(lp.Y) < 8 then
			nearWas = true
			break
		end
	end
	if not nearWas and #anchorsFor(id) == 0 then
		anchorCache[id] = nil -- (the stations may still be building: look again next time)
	end
	return nearWas
end

local setRunning: (on: boolean) -> ()

local function update(dt: number)
	if not gui then
		return
	end
	local now = os.clock()
	local inHall = player:GetAttribute("InTraining") == true
	if not inHall and not bike and not weights and now > resultUntil + 1 and now > lineUntil then
		drill = nil
		task.defer(setRunning, false)
	end
	local bay = player:GetAttribute("TrainingBay")

	-- the guidance / drill / result block
	local title, how, note, sub = nil, nil, nil, nil
	if drill and drill.state == "done" and now < resultUntil then
		title = drill.text
		how = if drill.token and drill.token > 0 then string.format("+%d token%s", drill.token, if drill.token > 1 then "s" else "")
			else nil
		ui.title.TextColor3 = if drill.passed then Theme.Colors.Sun else Theme.Colors.Ink
	elseif drill and drill.state == "run" then
		ui.title.TextColor3 = Theme.Colors.Ink
		local left = if drill.endsAt then drill.endsAt - serverNow() else 0
		local name = string.upper(drill.name or "")
		if drill.id == "blades" then
			title = string.format("%s · hits %d / 8 · guarded %d / 2 · %s", name, drill.hits or 0, drill.guards or 0, clock(left))
		elseif drill.id == "survival" then
			title = string.format("%s · %d / 4 · %s", name, drill.score or 0, clock(left))
			how = string.format("%s fire  ·  %s water  ·  plants %d / 3%s  ·  %s bandage",
				if drill.fire then "\u{2713}" else "\u{00B7}", if drill.water then "\u{2713}" else "\u{00B7}", drill.plants or 0,
				if drill.spoiled then " (a spoiled one: start again)" else "", if drill.bandage then "\u{2713}" else "\u{00B7}")
		elseif drill.id == "throwing" then
			title = string.format("%s · %d hits · throw %d / %d · %s", name, drill.score or 0, drill.throws or 0, drill.total or 5, clock(left))
		elseif drill.id == "archery" then
			title = string.format("%s · %d / %d · %d points · %s", name, drill.score or 0, drill.total or 6, drill.points or 0, clock(left))
			how = if drill.up then string.format("Target at %d", drill.up) else nil
		elseif drill.id == "lap" then
			title = string.format("%s · gate %d / 4 · %s", name, drill.score or 0, clock(left))
		else
			title = string.format("%s · %s", name, clock(left))
		end
		how = how or drill.line
		if drill.endsAt and left < -8 then
			drill = nil -- the server's end never came (left the hall): let it go
		end
	elseif inHall then
		ui.title.TextColor3 = Theme.Colors.Ink
		if bike then
			title = string.format("BIKE · %d / 20 s in the green", math.floor(bike.green))
			how = "Tap E, click or PEDAL to keep the needle in the band"
		elseif weights then
			title = string.format("WEIGHTS · %d / 10 clean · beat %d / 14", weights.clean, weights.beats)
			how = "Press as the ring meets the circle"
		elseif atStation(bay) then
			title, how = stationLine(bay)
		end
	end
	if now < lineUntil then
		note, sub = ui.lineText, ui.lineSub
	end
	-- (a sheet, the Loadout or the menu, has the screen: ClientState.menuOpen)
	local show = (inHall or (drill ~= nil and now < resultUntil + 0.5)) and not ClientState.menuOpen
	ui.block.Visible = show and (title ~= nil or note ~= nil)
	if ui.block.Visible then
		setText(ui.title, title)
		setText(ui.how, how)
		setText(ui.note, note)
		setText(ui.sub, sub)
		ui.rule.Visible = title ~= nil
	end

	-- the prompt line (only while HUDController isn't drawing Custom prompts: outside the arena)
	local p = shownPrompt
	if p and p.Parent and p.Enabled and inHall and not ClientState.inArena and not ClientState.menuOpen then
		local key = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "TAP"
			elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "X" else "E"
		setText(ui.prompt, string.format("[%s]  %s", key, p:GetAttribute("PromptLine") or p.ActionText))
		ui.prompt.Visible = true
		if promptHoldAt and p.HoldDuration > 0 then
			ui.hold.Visible = true
			ui.hold.Size = UDim2.new(0, 160 * math.clamp((now - promptHoldAt) / p.HoldDuration, 0, 1), 0, 2)
		else
			ui.hold.Visible = false
		end
	else
		ui.prompt.Visible = false
		ui.hold.Visible = false
	end

	-- bike
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:GetAttribute("TrainingBike") ~= nil then
		if not bike then
			bike = { value = 0.2, green = 0, t0 = now, seat = seat }
		end
		local b = bike :: any
		b.value = math.max(0, b.value - 0.32 * dt)
		if b.value >= 0.5 and b.value <= 0.75 then
			b.green += dt
		end
		ui.needle.Position = UDim2.new(b.value, 0, 0.5, 0)
		ui.needle.BackgroundColor3 = if b.value >= 0.5 and b.value <= 0.75 then Theme.Colors.Sun else Theme.Colors.Ink
		if b.green >= 20 then
			finishBike("done")
		elseif now - b.t0 > 40 then
			finishBike("time")
		end
	elseif bike then
		finishBike("stood")
	end
	ui.gauge.Visible = bike ~= nil

	-- weights
	local w = weights
	if w then
		if not w.started then
			w.started = true
			w.t0 = now
		end
		local phase = (now - w.t0) / w.period
		local frac = phase - math.floor(phase)
		local beat = math.floor(phase)
		if beat > w.beats then
			w.beats = beat
			if w.beats >= 14 or w.clean >= 10 then
				finishWeights()
			end
		end
		-- the ring closes from 3x to the circle on each beat
		local scale = 1 + 2 * (1 - frac)
		ui.closing.Size = UDim2.fromOffset(60 * scale, 60 * scale)
		if ui.closingStroke then
			ui.closingStroke.Transparency = 0.2 + 0.6 * (1 - frac)
			ui.closingStroke.Color = if w.flash and now - w.flash < 0.2 then Theme.Colors.Sun else Theme.Colors.Ink
		end
	end
	ui.ring.Visible = weights ~= nil
	ui.tap.Visible = (bike ~= nil or weights ~= nil) and UserInputService.TouchEnabled
	ui.tap.Text = if bike then "PEDAL" else "LIFT"
end

setRunning = function(on: boolean)
	if on and not renderConn then
		renderConn = RunService.RenderStepped:Connect(update)
	elseif not on and renderConn and not bike and not weights and os.clock() > resultUntil + 1 then
		renderConn:Disconnect()
		renderConn = nil
		if ui.block then
			ui.block.Visible = false
			ui.prompt.Visible = false
			ui.hold.Visible = false
			ui.gauge.Visible = false
			ui.ring.Visible = false
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- From the server
--------------------------------------------------------------------------------------------------------------------

local function onServer(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.t == "drill" then
		if payload.state == "done" then
			drill = payload
			resultUntil = os.clock() + 4
			pcall(Sfx.play, if payload.passed then "Notify" else "UIClick", { volume = 0.5 })
		else
			local d = drill
			if d and d.state == "run" and d.id == payload.id then
				for k, v in pairs(payload) do
					d[k] = v
				end
			else
				drill = payload
			end
			if payload.hit then
				pcall(Sfx.play, "HitMarker", { volume = 0.5, pitch = if payload.bull then 1.2 else 1 })
			end
		end
		setRunning(true)
	elseif payload.t == "line" then
		ui.lineText = payload.text
		ui.lineSub = payload.sub
		lineUntil = os.clock() + 3
		setRunning(true)
	elseif payload.t == "weights" then
		weights = { period = tonumber(payload.period) or 1.1, clean = 0, beats = 0, started = false, lastPressed = 0 }
		for _, pr in ipairs(CollectionService:GetTagged("TrainingPrompt")) do
			if pr:IsA("ProximityPrompt") and pr.ActionText == "Lift" then
				pr.Enabled = false -- this client only, while the beat runs
			end
		end
		setRunning(true)
	elseif payload.t == "strike" then
		if payload.result == "Parried" or payload.result == "Blocked" then
			pcall(Sfx.play, "UIClick", { volume = 0.4 })
		end
	end
end

function TrainingController.Init(_controllers)
end

function TrainingController.Start()
	build()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local r = remotes:WaitForChild("Training", 30)
	if r and r:IsA("RemoteEvent") then
		remote = r
		r.OnClientEvent:Connect(onServer)
	else
		warn("[TrainingController] no Training remote")
	end
	player:GetAttributeChangedSignal("InTraining"):Connect(function()
		setRunning(player:GetAttribute("InTraining") == true)
	end)
	setRunning(player:GetAttribute("InTraining") == true)

	ProximityPromptService.PromptShown:Connect(function(pr)
		if CollectionService:HasTag(pr, "TrainingPrompt") then
			shownPrompt = pr
			promptHoldAt = nil
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(pr)
		if pr == shownPrompt then
			shownPrompt = nil
			promptHoldAt = nil
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(pr)
		if pr == shownPrompt then
			promptHoldAt = os.clock()
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(pr)
		if pr == shownPrompt then
			promptHoldAt = nil
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(pr)
		if pr == shownPrompt then
			promptHoldAt = nil
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not (bike or weights) then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonR2 or input.UserInputType == Enum.UserInputType.MouseButton1 then
			press()
		elseif processed then
			return
		end
	end)
	ui.tap.Activated:Connect(press)
end

TrainingController._press = press
TrainingController._state = function()
	return { drill = drill, bike = bike, weights = weights }
end

return TrainingController
