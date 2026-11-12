--[[
	SpectateController - watch the remaining contenders (StarterGui.Spectate, built by UIBuilder). Owned by the UI system.
	While you're not an alive contender during an Active round you can spectate the alive contenders:
	  * SpectateTarget(target) tells the server to stream around them; ClientState.spectating is set and
	    ClientState.spectateChanged fires (other controllers stand down: combat, first-person camera, HUD vitals).
	  * Camera: Custom with CameraSubject = the target's Humanoid (third-person orbit).
	  * Cycle with Q / E or Left / Right, ButtonL1 / ButtonR1, or the on-screen arrows; exit with the EXIT button,
	    Backspace or ButtonB. A name card shows DisplayName, @name, kills and health.
	  * Switches automatically when the target falls or leaves: to their killer (the KilledBy attribute, a UserId) while
	    that contender is alive, else to the next name. Stops when the round is over (SpectateTarget(nil)).
	  * The death screen's SPECTATE starts on your own killer (NotificationController passes them to start).
	Public API (Controllers.SpectateController):
	  start(target: Player?) -> boolean    stop()    next()    prev()
	  canSpectate() -> boolean             getTarget() -> Player?    isSpectating() -> boolean
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
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
	R.eyebrow.Text = "SPECTATING"
	R.eyebrow.TextColor3 = C.AccentSoft
	R.name.Text = p.DisplayName
	local kills = math.floor(tonumber(p:GetAttribute("Kills")) or 0)
	local finding = if targetHumanoid(p) then "" else "   ·   finding them…"
	R.sub.Text = string.format("@%s   ·   <b>%d</b> %s%s", Theme.escape(p.Name), kills, if kills == 1 then "KILL" else "KILLS", finding)
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
	local key = if gamepad then "B" elseif touch then nil else "BACKSPACE"
	R.exit.Text = if key then string.format("EXIT SPECTATING   <font transparency=\"0.45\">%s</font>", key) else "EXIT SPECTATING"
end

local function applyLayout()
	if not R.card then
		return
	end
	local narrow = UserInputService.TouchEnabled or Theme.isSmallScreen()
	R.card.Size = UDim2.fromOffset(if narrow then 360 else 460, 90)
end

local function flashEmpty(text: string)
	if not R.empty then
		return
	end
	emptyToken += 1
	local token = emptyToken
	R.empty.Text = text
	R.empty.TextTransparency = 0
	R.empty.Visible = true
	task.delay(2.6, function()
		if token ~= emptyToken then
			return
		end
		local t = Theme.tween(R.empty, Theme.Tween.FadeOut, { TextTransparency = 1 })
		t.Completed:Once(function()
			if token == emptyToken then
				R.empty.Visible = false
			end
		end)
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
		R.exit.Visible = true
		R.card.Position = UDim2.new(0.5, 0, 1, 10)
		Theme.tween(R.card, Theme.Tween.Slow, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 1) })
	else
		R.exit.Visible = false
		local t = Theme.tween(R.card, Theme.Tween.Normal, { GroupTransparency = 1 })
		t.Completed:Once(function()
			if token == cardToken then
				R.card.Visible = false
			end
		end)
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
	if R.eyebrow then
		R.eyebrow.Text = "ELIMINATED"
		R.eyebrow.TextColor3 = C.Danger
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
		local killer = if killerId and killerId > 0 then Players:GetPlayerByUserId(killerId) else nil
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
		R.healthFill.BackgroundColor3 = if a <= 0.3 then C.HealthLow else C.Health
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
	R.healthFill = info:WaitForChild("Health"):WaitForChild("Fill")
	R.prev = R.card:WaitForChild("Prev")
	R.next = R.card:WaitForChild("Next")
	R.prevHint = R.prev:WaitForChild("Hint")
	R.nextHint = R.next:WaitForChild("Hint")
	R.exit = root:WaitForChild("Exit")
	R.empty = root:WaitForChild("Empty")
	local bg = R.card:FindFirstChild("Bg")
	if bg then
		bg.Active = true
	end

	local function hoverable(button: GuiButton, normal: number, hover: number)
		button.MouseEnter:Connect(function()
			Theme.tween(button, Theme.Tween.Fast, { BackgroundTransparency = hover })
			if not Input.isTouch() then
				Sfx.play("UIHover")
			end
		end)
		button.MouseLeave:Connect(function()
			Theme.tween(button, Theme.Tween.Fast, { BackgroundTransparency = normal })
		end)
	end
	hoverable(R.prev, 0.5, 0.2)
	hoverable(R.next, 0.5, 0.2)
	hoverable(R.exit, Theme.Transparency.Panel, 0.12)
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
