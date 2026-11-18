--[[
	SpectateController - watch the remaining contenders (StarterGui.Spectate, built by UIBuilder). Owned by the UI system.
	While you're not an alive contender during an Active round you can spectate the alive contenders:
	  * SpectateTarget(target) tells the server to stream around them; ClientState.spectating is set and
	    ClientState.spectateChanged fires (other controllers stand down: combat, first-person camera, HUD vitals).
	  * Camera: Custom with CameraSubject = the target's Humanoid (third-person orbit).
	  * Cycle with Q / E or Left / Right, ButtonL1 / ButtonR1, or the on-screen arrows; exit with Backspace or
	    ButtonB, or the "Back to lobby" words. Style A "Quiet": the card is the middle of the slim bottom strip
	    (fallen.html): "Spectating Rowan", "@rowan · 2 defeats" and a slim health line, with the arrows and their key
	    squares either side; no box. After a defeat the strip itself is NotificationController's (Overlay.Root.Strip,
	    with its own "Back to lobby"): this screen's Exit and hairline then stay hidden (onStripChanged). Spectating
	    from the lobby, this screen draws the hairline (Root.Line) and the Exit at the strip's right end itself.
	  * Switches automatically when the target falls or leaves: to their killer (the KilledBy attribute, a UserId) while
	    that contender is alive, else to the next name. Stops when the round is over (SpectateTarget(nil)).
	  * The death screen's SPECTATE starts on your own killer (NotificationController passes them to start).
	Public API (Controllers.SpectateController):
	  start(target: Player?) -> boolean    stop()    next()    prev()
	  canSpectate() -> boolean             getTarget() -> Player?    isSpectating() -> boolean
	  onStripChanged(up: boolean)          NotificationController: its defeat strip came or went
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Input = require(Shared:WaitForChild("Input"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer
local C = Theme.Colors

local SpectateController = {}
local Controllers: any = nil

local gui: ScreenGui? = nil
local R: { [string]: any } = {}
local active = false
local target: Player? = nil
local targetConnections: { RBXScriptConnection } = {}
local switchToken = 0
local emptyToken = 0
local saved: { [string]: any }? = nil
local lastAssert = 0
local cardToken = 0
local stripUp = false -- NotificationController's defeat strip is on screen (its "Back to lobby" is the way out)
local CARD_HEIGHT = 58 -- under the strip's hairline (Theme.Strip.Height 62)

local function candidates(): { Player }
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p:GetAttribute("Alive") == true then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		local an, bn = string.lower(a.DisplayName), string.lower(b.DisplayName)
		if an ~= bn then
			return an < bn
		end
		return a.UserId < b.UserId
	end)
	return list
end

local function targetHumanoid(p: Player?): Humanoid?
	local character = p and p.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function SpectateController.canSpectate(): boolean
	if GameState:GetAttribute("Phase") ~= "Active" then
		return false
	end
	if ClientState.inArena and ClientState.alive then
		return false
	end
	return #candidates() > 0
end

function SpectateController.getTarget(): Player?
	return target
end

function SpectateController.isSpectating(): boolean
	return active
end

--------------------------------------------------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------------------------------------------------
local function applyCamera()
	if not active or not target then
		return
	end
	local camera = workspace.CurrentCamera
	local hum = targetHumanoid(target)
	if not camera or not hum then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Custom then
		camera.CameraType = Enum.CameraType.Custom
	end
	if camera.CameraSubject ~= hum then
		camera.CameraSubject = hum
	end
end

local function saveCamera()
	if saved then
		return
	end
	saved = {
		mode = player.CameraMode,
		minZoom = player.CameraMinZoomDistance,
		maxZoom = player.CameraMaxZoomDistance,
		inArena = ClientState.inArena,
	}
	-- a third-person orbit around the target, whatever mode we came from
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = math.max(saved.maxZoom, 28)
	player.CameraMinZoomDistance = 12 -- pushes the zoom out to 12...
	task.delay(0.3, function()
		if active then
			player.CameraMinZoomDistance = 6 -- ...then lets the player zoom in a little
		end
	end)
end

local function restoreCamera()
	local s = saved
	saved = nil
	-- only restore the old camera setup if our life state didn't change meanwhile (the camera system re-applies its
	-- own setup on spectateChanged / lifeChanged otherwise)
	if s and s.inArena == ClientState.inArena then
		player.CameraMinZoomDistance = math.min(s.minZoom, s.maxZoom)
		player.CameraMaxZoomDistance = s.maxZoom
		player.CameraMinZoomDistance = s.minZoom
		player.CameraMode = s.mode
	elseif s then
		player.CameraMinZoomDistance = math.min(player.CameraMinZoomDistance, 0.5)
	end
	local camera = workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if camera and hum then
		camera.CameraSubject = hum
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Card
--------------------------------------------------------------------------------------------------------------------
local function updateCard()
	local p = target
	if not p or not R.card then
		return
	end
	R.eyebrow.Visible = false -- Quiet: the word sits in the name line ("Spectating Rowan")
	R.name.Text = "Spectating <b>" .. Theme.escape(p.DisplayName) .. "</b>"
	local kills = math.floor(tonumber(p:GetAttribute("Kills")) or 0)
	local finding = if targetHumanoid(p) then "" else "  ·  finding them…"
	R.sub.Text = string.format("@%s  ·  %d %s%s", Theme.escape(p.Name), kills, if kills == 1 then "defeat" else "defeats", finding)
end

local function refreshHints()
	if not R.card then
		return
	end
	local gamepad, touch = Input.isGamepad(), Input.isTouch()
	R.prevHint.Text = if gamepad then "LB" else "Q"
	R.nextHint.Text = if gamepad then "RB" else "E"
	R.prevHint.Visible = not touch
	R.nextHint.Visible = not touch
	local key = if gamepad then "B" elseif touch then nil else "Backspace"
	R.exit.Text = if key then string.format("Back to lobby   <font transparency=\"0.45\">%s</font>", key) else "Back to lobby"
end

-- this screen's own hairline and Exit show only when NotificationController's defeat strip is not up
local function refreshExit()
	if not R.card then
		return
	end
	local own = active and not stripUp
	R.exit.Visible = own
	if R.line then
		R.line.Visible = own
	end
end

local function applyLayout()
	if not R.card then
		return
	end
	local narrow = UserInputService.TouchEnabled or Theme.isSmallScreen()
	R.card.Size = UDim2.fromOffset(if narrow then 360 else 460, CARD_HEIGHT)
	-- the card's lines (UIBuilder built them for a 66 px card with an eyebrow): one name line, one small line, the
	-- health line, all under the strip's hairline
	R.name.RichText = true
	R.name.FontFace = Theme.Fonts.Medium or R.name.FontFace
	R.name.TextSize = 18
	R.name.Position = UDim2.fromOffset(0, 5)
	R.name.Size = UDim2.new(1, 0, 0, 24)
	R.sub.Position = UDim2.fromOffset(0, 29)
	R.sub.Size = UDim2.new(1, 0, 0, 16)
	R.health.Position = UDim2.new(0.5, 0, 0, 50)
	for _, arrow in ipairs({ R.prev, R.next }) do
		arrow.Position = UDim2.new(arrow.Position.X.Scale, arrow.Position.X.Offset, 0, math.floor((CARD_HEIGHT - arrow.Size.Y.Offset) / 2))
	end
	-- the Exit at the strip's right end, on the strip's middle line
	local stripHeight = tonumber(Theme.Strip and Theme.Strip.Height) or 62
	R.exit.AnchorPoint = Vector2.new(1, 0.5)
	R.exit.Position = UDim2.new(1, 0, 1, -math.floor(stripHeight / 2))
end

local function flashEmpty(text: string)
	if not R.empty then
		return
	end
	emptyToken += 1
	local token = emptyToken
	R.empty.Text = text
	QuietUI.textTransparency(R.empty, 0)
	R.empty.Visible = true
	task.delay(2.6, function()
		if token ~= emptyToken then
			return
		end
		-- the words and their dark outline fade together
		local t = QuietUI.fadeText(R.empty, false, Theme.Tween.FadeOut)
		local function done()
			if token == emptyToken then
				R.empty.Visible = false
			end
		end
		if t then
			t.Completed:Once(done)
		else
			done()
		end
	end)
end

local function showCard(on: boolean)
	if not R.card then
		return
	end
	cardToken += 1
	local token = cardToken
	if on then
		applyLayout()
		refreshHints()
		R.card.Visible = true
		refreshExit()
		R.card.Position = UDim2.new(0.5, 0, 1, 8)
		QuietUI.tween(R.card, Theme.Tween.Slow, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 1) })
	else
		refreshExit()
		local t = QuietUI.tween(R.card, Theme.Tween.Normal, { GroupTransparency = 1 })
		if t then
			t.Completed:Once(function()
				if token == cardToken then
					R.card.Visible = false
				end
			end)
		else
			R.card.Visible = false
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Targets
--------------------------------------------------------------------------------------------------------------------
local setTarget: (Player?) -> ()

local function disconnectTarget()
	for _, connection in ipairs(targetConnections) do
		connection:Disconnect()
	end
	table.clear(targetConnections)
end

local function onTargetLost(p: Player, delay: number)
	if target ~= p then
		return
	end
	switchToken += 1
	local token = switchToken
	if R.sub then
		R.sub.Text = "Out of the round  ·  finding the next contender…"
	end
	task.delay(delay, function()
		if token ~= switchToken or not active or target ~= p then
			return
		end
		local list = candidates()
		if #list == 0 then
			SpectateController.stop("NO CONTENDERS LEFT TO WATCH")
			return
		end
		-- QW4: follow the one who took them out (PlayerService sets KilledBy to the killer's UserId)
		local killerId = tonumber(p:GetAttribute("KilledBy"))
		local killer = if killerId and killerId ~= 0 then Players:GetPlayerByUserId(killerId) else nil -- (ids are negative in a Studio test server)
		if killer and table.find(list, killer) then
			setTarget(killer)
			return
		end
		-- else the next contender after the one who fell, in card order
		local pick = list[1]
		local pName = string.lower(p.DisplayName)
		for _, other in ipairs(list) do
			if string.lower(other.DisplayName) > pName then
				pick = other
				break
			end
		end
		setTarget(pick)
	end)
end

setTarget = function(p: Player?)
	disconnectTarget()
	switchToken += 1
	target = p
	ClientState.spectating = p
	pcall(function()
		Net.event("SpectateTarget"):FireServer(p)
	end)
	ClientState.spectateChanged:Fire(p)
	if p then
		table.insert(targetConnections, p:GetAttributeChangedSignal("Alive"):Connect(function()
			if p:GetAttribute("Alive") ~= true then
				onTargetLost(p, 1.6)
			end
		end))
		table.insert(targetConnections, p:GetAttributeChangedSignal("Kills"):Connect(updateCard))
		table.insert(targetConnections, p.CharacterAdded:Connect(function()
			task.defer(applyCamera)
			task.defer(updateCard)
		end))
	end
	updateCard()
	applyCamera()
end

local function cycle(dir: number)
	if not active then
		return
	end
	local list = candidates()
	if #list == 0 then
		return
	end
	local index = if target then table.find(list, target) else nil
	local nextIndex
	if index then
		nextIndex = ((index - 1 + dir) % #list) + 1
	else
		nextIndex = if dir > 0 then 1 else #list
	end
	local pick = list[nextIndex]
	if pick and pick ~= target then
		Sfx.play("UIClick")
		setTarget(pick)
	end
end

function SpectateController.next()
	cycle(1)
end

function SpectateController.prev()
	cycle(-1)
end

local function bindInputs()
	Input.bind("SpectatePrev", function(state)
		if state == Enum.UserInputState.Begin and not ClientState.menuOpen then
			cycle(-1)
		end
		return Enum.ContextActionResult.Sink
	end, { keys = { Enum.KeyCode.Q, Enum.KeyCode.Left, Enum.KeyCode.ButtonL1 }, priority = 2500 })
	Input.bind("SpectateNext", function(state)
		if state == Enum.UserInputState.Begin and not ClientState.menuOpen then
			cycle(1)
		end
		return Enum.ContextActionResult.Sink
	end, { keys = { Enum.KeyCode.E, Enum.KeyCode.Right, Enum.KeyCode.ButtonR1 }, priority = 2500 })
	Input.bind("SpectateExit", function(state)
		if state == Enum.UserInputState.Begin and not ClientState.menuOpen then
			SpectateController.stop()
		end
		return Enum.ContextActionResult.Sink
	end, { keys = { Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB }, priority = 2500 })
end

local function unbindInputs()
	Input.unbind("SpectatePrev")
	Input.unbind("SpectateNext")
	Input.unbind("SpectateExit")
end

function SpectateController.start(p: Player?): boolean
	if active then
		if p and p ~= target and p:GetAttribute("Alive") == true then
			setTarget(p)
		end
		return true
	end
	if not SpectateController.canSpectate() then
		flashEmpty(if GameState:GetAttribute("Phase") == "Active" then "NO CONTENDERS TO WATCH" else "NO ROUND IN PROGRESS")
		return false
	end
	local list = candidates()
	local first = if p and table.find(list, p) then p else list[1]
	if not first then
		return false
	end
	active = true
	saveCamera()
	bindInputs()
	showCard(true)
	setTarget(first)
	local notifications = Controllers and Controllers.NotificationController
	if notifications and notifications.hideDeathScreen then
		notifications.hideDeathScreen()
	end
	return true
end

function SpectateController.stop(message: string?)
	if not active then
		return
	end
	active = false
	switchToken += 1
	unbindInputs()
	disconnectTarget()
	target = nil
	ClientState.spectating = nil
	pcall(function()
		Net.event("SpectateTarget"):FireServer(nil)
	end)
	restoreCamera()
	ClientState.spectateChanged:Fire(nil)
	showCard(false)
	if message then
		flashEmpty(message)
	end
end

function SpectateController.onStripChanged(up: boolean)
	stripUp = up == true
	refreshExit()
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------
local function frame()
	if not active then
		return
	end
	local hum = targetHumanoid(target)
	if hum and R.healthFill then
		local a = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
		R.healthFill.Size = UDim2.fromScale(a, 1)
		-- Quiet: ink, Red only for the danger state (low health); never a hit effect
		R.healthFill.BackgroundColor3 = if a <= 0.3 then (C.Red or C.HealthLow) else (C.Ink or C.Health)
	end
	local t = os.clock()
	if t - lastAssert > 0.25 then
		lastAssert = t
		local camera = workspace.CurrentCamera
		if camera and hum and camera.CameraSubject ~= hum then
			applyCamera()
			updateCard()
		end
	end
end

function SpectateController.Init(registry)
	Controllers = registry
end

function SpectateController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local spectateGui = playerGui:WaitForChild("Spectate") :: ScreenGui
	gui = spectateGui
	Theme.bindRoot(spectateGui)
	local root = spectateGui:WaitForChild("Root") :: any
	R.card = root:WaitForChild("Card")
	local info = R.card:WaitForChild("Info")
	R.eyebrow = info:WaitForChild("Eyebrow")
	R.name = info:WaitForChild("PlayerName")
	R.sub = info:WaitForChild("Sub")
	R.health = info:WaitForChild("Health")
	R.healthFill = R.health:WaitForChild("Fill")
	R.prev = R.card:WaitForChild("Prev")
	R.next = R.card:WaitForChild("Next")
	R.prevHint = R.prev:WaitForChild("Hint")
	R.nextHint = R.next:WaitForChild("Hint")
	R.exit = root:WaitForChild("Exit")
	R.empty = root:WaitForChild("Empty")
	R.line = root:FindFirstChild("Line") -- the strip's hairline when there is no defeat strip (UIBuilder, Quiet)
	local bg = R.card:FindFirstChild("Bg")
	if bg then
		bg.Active = true
	end

	-- Quiet buttons: no box; hover, pressed and gamepad focus come from QuietUI (an underline under the words)
	local function onHover()
		if not Input.isTouch() then
			Sfx.play("UIHover")
		end
	end
	for _, button in ipairs({ R.prev, R.next, R.exit }) do
		if button:FindFirstChild("Under") then
			QuietUI.bindButton(button, { onHover = onHover })
		else
			button.MouseEnter:Connect(onHover)
		end
	end
	R.prev.Activated:Connect(function()
		cycle(-1)
	end)
	R.next.Activated:Connect(function()
		cycle(1)
	end)
	R.exit.Activated:Connect(function()
		Sfx.play("UIClick")
		SpectateController.stop()
	end)

	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = GameState:GetAttribute("Phase")
		if active and phase ~= "Active" and phase ~= "Ending" then
			SpectateController.stop()
		end
	end)
	ClientState.lifeChanged:Connect(function()
		if active and ClientState.inArena and ClientState.alive then
			SpectateController.stop()
		elseif active then
			task.defer(applyCamera)
		end
	end)
	player.CharacterAdded:Connect(function()
		-- the default camera grabs the new character; point it back at the target
		if active then
			task.delay(0.1, applyCamera)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		if active and p == target then
			onTargetLost(p, 0.4)
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(refreshHints)

	applyLayout()
	refreshHints()
	spectateGui.Enabled = true
	RunService.RenderStepped:Connect(frame)
end

return SpectateController
