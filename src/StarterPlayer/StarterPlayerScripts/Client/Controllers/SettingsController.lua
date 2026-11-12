--[[
	SettingsController - player settings (load, apply, save) and the Menu screen (settings + controls reference).
	Owned by the UI system. Drives StarterGui.Menu (built by ServerStorage.WorldGen.UIBuilder).

	* Loads ClientState.settings from the SettingsJson player attribute (DataService) and applies them with
	  ClientState.setSettings; other controllers (camera, audio, movement) react to ClientState.settingsChanged.
	* Saves with the SaveSettings remote, debounced (~1 s after the last change).
	* Menu opens with M / DPadUp / the on-screen button (touch, in the arena) / the lobby SETTINGS button.
	  While it's open ClientState.menuOpen = true and a Modal button frees the mouse in first person.
	  Gamepad: D-pad up/down to move, D-pad left/right to adjust, LB/RB to switch tabs, B to close.
	* Every row is a slider; a choice (Sprint: Hold / Toggle / Auto, Crouch, Guidance) is a stepped slider whose value
	  prints the word. Rows with a `device` show only while that device is in use (Shared.Input.device), so each
	  device keeps its own sprint and crouch mode and look speed (PlayabilityPlan QW13):
	    sprint  Hold (keyboard default) | Toggle (gamepad default, L3) | Auto (touch default: a full push sprints)
	    crouch  Hold (keyboard default) | Toggle (gamepad and touch default)
	    look    mouse sensitivity (CameraController), controller and touch look speed (Input.setLookSpeed, 0.5-2x)
	  Field of view is stored in vertical degrees (what the camera uses) and shown in horizontal degrees for this
	  screen; the floor is 55 (about 86 degrees across on 16:9).
	  Guidance (Off / Auto / Always; default Config.Guidance.Mode) is the help for new players (PlayabilityPlan Q1).
	  Hidden settings (no row) are saved the same way: hintsSeen (Shared.ActionHints' fade counters).

	Public API (Controllers.SettingsController):
	  open(page: "Settings" | "Controls"?)   close()   toggle()   isOpen() -> boolean
	  setModal(reason: string, on: boolean)   any active reason sets ClientState.menuOpen (menu, death screen, ...)
	  menuChanged: Signal(menuOpen: boolean)  fires when ClientState.menuOpen changes
	  currentDevice() -> "KeyboardMouse" | "Gamepad" | "Touch"
	  getControls(device) -> { { action: string, keys: string } }
	  fillControls(container, rowTemplate, device)   fills a list with ControlRow clones (used by the lobby too)
	  set(key, value)                         set and save one setting from code (e.g. hintsSeen)
	  DEFS                                    the settings definitions (key, label, min, max, step, format, device?, hidden?)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Input = require(Shared:WaitForChild("Input"))
local Glyphs = require(Shared:WaitForChild("Glyphs"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local C = Theme.Colors

local SettingsController = {}
SettingsController.menuChanged = Signal.new()

--------------------------------------------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------------------------------------------
local function percent(v: number): string
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

local function words(list: { string }): (number) -> string
	return function(v: number): string
		return list[math.floor(v + 0.5) + 1] or "?"
	end
end

local function multiplier(v: number): string
	return string.format("%.2f×", v)
end

-- Horizontal degrees across this screen for a vertical field of view.
local function horizontalFov(v: number): string
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(16, 9)
	local aspect = if size.Y > 1 then size.X / size.Y else 16 / 9
	local h = 2 * math.deg(math.atan(math.tan(math.rad(v) / 2) * aspect))
	return string.format("%d°", math.floor(h + 0.5))
end

local MODE3 = { "Hold", "Toggle", "Auto" }
local MODE2 = { "Hold", "Toggle" }

local DEFAULTS = table.clone(ClientState.settings)

local DEFS = {
	{ section = "CAMERA" },
	{ key = "fov", label = "Field of view", min = 55, max = 100, step = 1, format = horizontalFov },
	{ key = "headBob", label = "Head bob", min = 0, max = 1, step = 0.05, format = percent },
	{ key = "cameraShake", label = "Camera shake", min = 0, max = 1, step = 0.05, format = percent },
	{ section = "CONTROLS" },
	{ key = "sensitivity", label = "Look sensitivity", device = "KeyboardMouse", min = 0.2, max = 3, step = 0.05, format = function(v: number): string
		return string.format("%.2f", v)
	end },
	{ key = "padLook", label = "Look sensitivity", device = "Gamepad", min = 0.5, max = 2, step = 0.05, format = multiplier },
	{ key = "touchLook", label = "Look sensitivity", device = "Touch", min = 0.5, max = 2, step = 0.05, format = multiplier },
	{ key = "sprintMode", label = "Sprint", device = "KeyboardMouse", min = 0, max = 2, step = 1, format = words(MODE3) },
	{ key = "sprintModePad", label = "Sprint", device = "Gamepad", min = 0, max = 2, step = 1, format = words(MODE3) },
	{ key = "sprintModeTouch", label = "Sprint", device = "Touch", min = 0, max = 2, step = 1, format = words(MODE3) },
	{ key = "crouchMode", label = "Crouch", device = "KeyboardMouse", min = 0, max = 1, step = 1, format = words(MODE2) },
	{ key = "crouchModePad", label = "Crouch", device = "Gamepad", min = 0, max = 1, step = 1, format = words(MODE2) },
	{ key = "crouchModeTouch", label = "Crouch", device = "Touch", min = 0, max = 1, step = 1, format = words(MODE2) },
	{ key = "guidance", label = "Guidance for new players", min = 0, max = 2, step = 1, format = words({ "Off", "Auto", "Always" }) },
	{ section = "AUDIO" },
	{ key = "musicVolume", label = "Music volume", min = 0, max = 1, step = 0.05, format = percent },
	{ key = "sfxVolume", label = "Effects volume", min = 0, max = 1, step = 0.05, format = percent },
	{ key = "ambienceVolume", label = "Ambience volume", min = 0, max = 1, step = 0.05, format = percent },
	-- saved like the rest, but no row
	{ key = "hintsSeen", hidden = true, min = 0, max = 2 ^ 30 - 1, step = 1, format = tostring },
}
SettingsController.DEFS = DEFS

local DEF_BY_KEY: { [string]: any } = {}
for _, def in ipairs(DEFS) do
	if def.key then
		DEF_BY_KEY[def.key] = def
	end
end

local function modeWord(key: string, list: { string }): string
	local v = tonumber(ClientState.settings[key]) or tonumber(DEFAULTS[key]) or 0
	return string.lower(list[math.clamp(math.floor(v + 0.5), 0, #list - 1) + 1])
end

-- The controls reference (Menu > Controls and the lobby's HOW TO PLAY), with this device's button names. Most-used first,
-- so the lobby panel shows moving, attacking and aiming (the spear throw) without scrolling.
local function controlsFor(device: string): { { string } }
	if device == "Gamepad" then
		local g = Glyphs.forKey
		local K = Enum.KeyCode
		local sprint = modeWord("sprintModePad", MODE3)
		return {
			{ "Move", "Left stick" },
			{ "Look", "Right stick" },
			{ "Sprint (" .. sprint .. ")", if sprint == "auto" then "Push the stick fully" else g(K.ButtonL3) },
			{ "Jump · vault · climb", g(K.ButtonA) },
			{ "Attack · use item (hold to eat, drink, draw)", g(K.ButtonR2) },
			{ "Aim · with a spear, Aim + Attack throws", g(K.ButtonL2) },
			{ "Drink · fill · pick up · open", g(K.ButtonX) },
			{ "Crouch (" .. modeWord("crouchModePad", MODE2) .. ") · quieter steps · slide while sprinting", g(K.ButtonB) },
			{ "Let go of a climb", g(K.ButtonB) },
			{ "Previous / next item", g(K.ButtonL1) .. " / " .. g(K.ButtonR1) },
			{ "Drop: tap for one, hold for the stack", g(K.DPadDown) },
			{ "Spectate: previous / next · leave", g(K.ButtonL1) .. " / " .. g(K.ButtonR1) .. " · " .. g(K.ButtonB) },
			{ "Menu", g(K.DPadUp) },
		}
	elseif device == "Touch" then
		local sprint = modeWord("sprintModeTouch", MODE3)
		return {
			{ "Move", "Left thumbstick" },
			{ "Look", "Drag on the right" },
			{ "Sprint (" .. sprint .. ")", if sprint == "auto" then "Push the stick fully" else "RUN" },
			{ "Jump · vault · climb", "Jump button" },
			{ "Attack · use item (hold)", "ATTACK · EAT · DRAW" },
			{ "Aim (bow, spear) · then THROW", "AIM" },
			{ "Drink · fill (near water)", "DRINK · FILL" },
			{ "Pick up · open crates", "Tap the prompt" },
			{ "Crouch (" .. modeWord("crouchModeTouch", MODE2) .. ") · quieter steps · slide", "CROUCH" },
			{ "Let go of a climb", "CROUCH" },
			{ "Select item", "Tap a slot" },
			{ "Drop: tap for one, hold for the stack", "DROP" },
			{ "Spectate: previous / next", "‹  ›" },
			{ "Menu", "Menu button" },
		}
	end
	local sprint = modeWord("sprintMode", MODE3)
	local sprintKeys = if sprint == "auto" then "W (hold Shift to jog)" else "Shift (" .. sprint .. ")"
	return {
		{ "Move", "W A S D" },
		{ "Look", "Mouse" },
		{ "Sprint", sprintKeys },
		{ "Jump · vault · climb", "Space" },
		{ "Attack · use item (hold to eat, drink, draw)", "Left click" },
		{ "Aim · with a spear, Aim + Attack throws", "Right click" },
		{ "Drink · fill a bottle (at water)", "E" },
		{ "Pick up · open crates", "E" },
		{ "Crouch (" .. modeWord("crouchMode", MODE2) .. ") · quieter steps · slide while sprinting", "C / Ctrl" },
		{ "Let go of a climb", "C" },
		{ "Select item", "1 – 6 · Wheel" },
		{ "Drop: tap for one, hold for the stack", "G" },
		{ "Spectate: previous / next", "Q / E" },
		{ "Menu", "M" },
	}
end

function SettingsController.currentDevice(): string
	return Input.device()
end

function SettingsController.getControls(device: string): { { action: string, keys: string } }
	local out = {}
	for _, entry in ipairs(controlsFor(device)) do
		table.insert(out, { action = entry[1], keys = entry[2] })
	end
	return out
end

function SettingsController.fillControls(container: Instance, template: Instance, device: string)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, entry in ipairs(controlsFor(device)) do
		local row = template:Clone() :: any
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Visible = true
		row.Action.Text = entry[1]
		row.Key.Label.Text = entry[2]
		row.Parent = container
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Modal state (ClientState.menuOpen)
--------------------------------------------------------------------------------------------------------------------
local modalReasons: { [string]: boolean } = {}

function SettingsController.setModal(reason: string, on: boolean)
	if on then
		modalReasons[reason] = true
	else
		modalReasons[reason] = nil
	end
	local any = next(modalReasons) ~= nil
	if ClientState.menuOpen ~= any then
		ClientState.menuOpen = any
		SettingsController.menuChanged:Fire(any)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Settings values
--------------------------------------------------------------------------------------------------------------------
local localDirty = false -- the player changed something this session; later server copies don't override it
local saveToken = 0

local function quantize(def, value: number): number
	local v = math.clamp(value, def.min, def.max)
	local steps = math.floor((v - def.min) / def.step + 0.5)
	v = def.min + steps * def.step
	v = math.floor(v * 1000 + 0.5) / 1000
	return math.clamp(v, def.min, def.max)
end

local function currentValue(def): number
	local v = ClientState.settings[def.key]
	if type(v) ~= "number" or v ~= v then
		v = DEFAULTS[def.key]
	end
	if type(v) ~= "number" then
		v = def.min
	end
	return math.clamp(v, def.min, def.max)
end

local function snapshot(): { [string]: number }
	local out = {}
	for _, def in ipairs(DEFS) do
		if def.key then
			out[def.key] = currentValue(def)
		end
	end
	return out
end

local function scheduleSave()
	localDirty = true
	saveToken += 1
	local token = saveToken
	task.delay(1, function()
		if token ~= saveToken then
			return
		end
		local ok, err = pcall(function()
			Net.event("SaveSettings"):FireServer(snapshot())
		end)
		if not ok then
			warn("[SettingsController] Couldn't save settings: " .. tostring(err))
		end
	end)
end

local function sanitize(raw: any): { [string]: number }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, def in ipairs(DEFS) do
		if def.key then
			local v = raw[def.key]
			if type(v) == "number" and v == v and v > -1e10 and v < 1e10 then
				out[def.key] = quantize(def, v)
			end
		end
	end
	return out
end

-- Set and save one setting from code (no row needed), e.g. the hint fade counters.
function SettingsController.set(key: string, value: number)
	local def = DEF_BY_KEY[key]
	if not def or type(value) ~= "number" or value ~= value then
		return
	end
	local q = quantize(def, value)
	if ClientState.settings[key] ~= q then
		ClientState.setSettings({ [key] = q })
		scheduleSave()
	end
end

-- Look speeds for the controller and touch (the mouse is CameraController's).
local function applyControls()
	local s = ClientState.settings
	Input.setLookSpeed("Gamepad", tonumber(s.padLook) or 1)
	Input.setLookSpeed("Touch", tonumber(s.touchLook) or 1)
end

--------------------------------------------------------------------------------------------------------------------
-- Menu UI
--------------------------------------------------------------------------------------------------------------------
local gui: ScreenGui? = nil
local refs: { [string]: any } = {}
local rows: { [string]: any } = {}
local rowOrder: { any } = {}
local isOpen = false
local currentPage = "Settings"
local controlsDevice: string? = nil
local dragging: { entry: any, input: InputObject }? = nil
local repeatToken = 0
local closeToken = 0

local function paintRow(entry)
	local def = entry.def
	local v = currentValue(def)
	local a = (v - def.min) / (def.max - def.min)
	entry.fill.Size = UDim2.fromScale(a, 1)
	entry.knob.Position = UDim2.fromScale(a, 0.5)
	entry.value.Text = def.format(v)
end

local function refreshRows()
	for _, entry in pairs(rows) do
		paintRow(entry)
	end
end

local function rowShown(entry): boolean
	return entry.def.device == nil or entry.def.device == Input.device()
end

-- Rows for another device hide; a gamepad selection on a hidden row moves to the first shown one.
local function refreshRowVisibility()
	for _, entry in pairs(rows) do
		local on = rowShown(entry)
		if entry.row.Visible ~= on then
			entry.row.Visible = on
		end
	end
	local selected = GuiService.SelectedObject
	if selected and gui and selected:IsDescendantOf(gui) and not selected.Visible then
		for _, entry in ipairs(rowOrder) do
			if rowShown(entry) then
				GuiService.SelectedObject = entry.row
				break
			end
		end
	end
end

local function setValue(entry, value: number, tick: boolean?)
	local q = quantize(entry.def, value)
	if ClientState.settings[entry.def.key] ~= q then
		ClientState.setSettings({ [entry.def.key] = q })
		scheduleSave()
		if tick then
			Sfx.play("UIHover")
		end
	end
	paintRow(entry)
end

local function applyAttribute()
	if localDirty then
		return
	end
	local json = player:GetAttribute("SettingsJson")
	if type(json) ~= "string" or json == "" then
		return
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok then
		return
	end
	local values = sanitize(decoded)
	if next(values) ~= nil then
		ClientState.setSettings(values)
		refreshRows()
	end
end

local function selectedEntry()
	local selected = GuiService.SelectedObject
	if not selected then
		return nil
	end
	for _, entry in pairs(rows) do
		if entry.row == selected then
			return entry
		end
	end
	return nil
end

local function styleButton(button: GuiButton, onHover: (boolean) -> ())
	local hovered, selected = false, false
	local function apply()
		onHover(hovered or selected)
	end
	button.MouseEnter:Connect(function()
		hovered = true
		apply()
		if not Input.isTouch() then
			Sfx.play("UIHover")
		end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		apply()
	end)
	button.SelectionGained:Connect(function()
		selected = true
		apply()
	end)
	button.SelectionLost:Connect(function()
		selected = false
		apply()
	end)
end

local function styleTab(tab: any, active: boolean)
	tab.TextColor3 = if active then C.Text else C.TextDim
	tab.Underline.Visible = active
end

local function showDevice(device: string)
	controlsDevice = device
	for _, b in ipairs(refs.devices:GetChildren()) do
		if b:IsA("TextButton") then
			local on = b.Name == device
			b.BackgroundColor3 = if on then C.Text else C.PanelLight
			b.BackgroundTransparency = if on then 0.04 else 0.6
			b.TextColor3 = if on then C.TextDark else C.Text
		end
	end
	SettingsController.fillControls(refs.controlsList, refs.templates.ControlRow, device)
	refs.controlsList.CanvasPosition = Vector2.zero
end

local function showPage(name: string)
	currentPage = name
	refs.settingsPage.Visible = name == "Settings"
	refs.controlsPage.Visible = name == "Controls"
	styleTab(refs.settingsTab, name == "Settings")
	styleTab(refs.controlsTab, name == "Controls")
	refs.reset.Visible = name == "Settings"
	if name == "Controls" then
		showDevice(controlsDevice or SettingsController.currentDevice())
	end
end

local function updateHint()
	if not refs.hint then
		return
	end
	local device = SettingsController.currentDevice()
	if device == "Gamepad" then
		local g = Glyphs.forKey
		local K = Enum.KeyCode
		refs.hint.Text = string.format("%s  BACK     %s / %s  TABS     D-PAD  ADJUST", g(K.ButtonB), g(K.ButtonL1), g(K.ButtonR1))
	elseif device == "Touch" then
		refs.hint.Text = ""
	else
		refs.hint.Text = "M  CLOSE"
	end
end

local function updateLauncher()
	if not refs.launcher then
		return
	end
	refs.launcher.Visible = UserInputService.TouchEnabled
		and not isOpen
		and (ClientState.inArena or ClientState.spectating ~= nil)
end

local function firstSelectable(): GuiObject?
	if currentPage == "Settings" then
		for _, entry in ipairs(rowOrder) do
			if rowShown(entry) then
				return entry.row
			end
		end
		return nil
	end
	return refs.devices:FindFirstChild(controlsDevice or "KeyboardMouse") :: GuiObject?
end

local bindMenuKeys -- forward declaration

local function setOpen(on: boolean, page: string?)
	if not gui then
		return
	end
	if on == isOpen then
		if on and page then
			showPage(page)
		end
		return
	end
	isOpen = on
	closeToken += 1
	SettingsController.setModal("Menu", on)
	local panel = refs.panel
	local dim = refs.dim
	if on then
		refreshRowVisibility()
		showPage(page or currentPage)
		refreshRows()
		updateHint()
		dim.Visible = true
		panel.Visible = true
		panel.GroupTransparency = 1
		panel.Position = UDim2.new(0.5, 0, 0.5, 14)
		Theme.tween(panel, Theme.Tween.Normal, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) })
		Theme.tween(dim, Theme.Tween.Normal, { BackgroundTransparency = Theme.Transparency.Dim })
		if Input.isGamepad() then
			GuiService.SelectedObject = firstSelectable()
		end
		Sfx.play("UIClick")
	else
		dragging = nil
		repeatToken += 1
		local token = closeToken
		local t = Theme.tween(panel, Theme.Tween.Fast, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 10) })
		Theme.tween(dim, Theme.Tween.Fast, { BackgroundTransparency = 1 })
		t.Completed:Once(function()
			if token == closeToken and not isOpen then
				panel.Visible = false
				dim.Visible = false
			end
		end)
		local selected = GuiService.SelectedObject
		if selected and gui and selected:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
	end
	bindMenuKeys()
	updateLauncher()
end

function SettingsController.open(page: string?)
	setOpen(true, if page == "Controls" then "Controls" elseif page == "Settings" then "Settings" else nil)
end

function SettingsController.close()
	setOpen(false)
end

function SettingsController.toggle()
	setOpen(not isOpen)
end

function SettingsController.isOpen(): boolean
	return isOpen
end

bindMenuKeys = function()
	Input.bind("Menu", function(state)
		if state == Enum.UserInputState.Begin then
			SettingsController.toggle()
		end
		return Enum.ContextActionResult.Sink
	end, {
		-- while open, D-pad up navigates the menu instead of closing it (B closes)
		keys = if isOpen then { Enum.KeyCode.M } else { Enum.KeyCode.M, Enum.KeyCode.DPadUp },
	})
	if isOpen then
		Input.bind("MenuBack", function(state)
			if state == Enum.UserInputState.Begin then
				SettingsController.close()
			end
			return Enum.ContextActionResult.Sink
		end, { keys = { Enum.KeyCode.ButtonB }, priority = 3000 })
		Input.bind("MenuTabs", function(state, io)
			if state == Enum.UserInputState.Begin and io then
				local target = if io.KeyCode == Enum.KeyCode.ButtonL1 then "Settings" else "Controls"
				if target ~= currentPage then
					showPage(target)
					Sfx.play("UIClick")
					if Input.isGamepad() then
						GuiService.SelectedObject = firstSelectable()
					end
				end
			end
			return Enum.ContextActionResult.Sink
		end, { keys = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }, priority = 3000 })
	else
		Input.unbind("MenuBack")
		Input.unbind("MenuTabs")
	end
end

local function buildRows()
	local list = refs.settingsPage
	local templates = refs.templates
	for i, def in ipairs(DEFS) do
		if def.section then
			local section = templates.Section:Clone()
			section.Name = "Section" .. i
			section.Text = def.section
			section.LayoutOrder = i
			section.Parent = list
		elseif not def.hidden then
			local row = templates.SliderRow:Clone()
			row.Name = def.key
			row.LayoutOrder = i
			row.Label.Text = def.label
			row.SelectionImageObject = templates.Selection
			row.Parent = list
			local entry = { row = row, def = def, fill = row.Track.Fill, knob = row.Track.Knob, value = row.Value }
			rows[def.key] = entry
			table.insert(rowOrder, entry)
			styleButton(row, function(on)
				Theme.tween(row, Theme.Tween.Fast, { BackgroundTransparency = if on then 0.62 else 1 })
				entry.value.TextColor3 = if on then C.Text else C.TextDim
			end)
			row.InputBegan:Connect(function(io: InputObject)
				if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
					dragging = { entry = entry, input = io }
					local track = row.Track
					local a = (io.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
					setValue(entry, def.min + math.clamp(a, 0, 1) * (def.max - def.min))
				end
			end)
			paintRow(entry)
		end
	end
	refreshRowVisibility()
end

local function hookInput()
	UserInputService.InputChanged:Connect(function(io: InputObject)
		local d = dragging
		if not d then
			return
		end
		if io.UserInputType == Enum.UserInputType.MouseMovement or (io.UserInputType == Enum.UserInputType.Touch and io == d.input) then
			local track = d.entry.row.Track
			local a = (io.Position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
			local def = d.entry.def
			setValue(d.entry, def.min + math.clamp(a, 0, 1) * (def.max - def.min))
		end
	end)
	UserInputService.InputEnded:Connect(function(io: InputObject)
		local d = dragging
		if d and (io.UserInputType == Enum.UserInputType.MouseButton1 or io == d.input) then
			dragging = nil
		end
		if io.KeyCode == Enum.KeyCode.DPadLeft or io.KeyCode == Enum.KeyCode.DPadRight then
			repeatToken += 1
		end
	end)
	-- gamepad: D-pad left/right adjusts the selected slider (hold to repeat)
	UserInputService.InputBegan:Connect(function(io: InputObject)
		if not isOpen then
			return
		end
		local dir = if io.KeyCode == Enum.KeyCode.DPadLeft then -1 elseif io.KeyCode == Enum.KeyCode.DPadRight then 1 else 0
		if dir == 0 then
			return
		end
		local entry = selectedEntry()
		if not entry then
			return
		end
		setValue(entry, currentValue(entry.def) + dir * entry.def.step, true)
		repeatToken += 1
		local token = repeatToken
		local def = entry.def
		local stepped = (def.max - def.min) / def.step <= 4 -- a choice moves one word per press; no auto-repeat through it
		task.delay(0.35, function()
			while not stepped and token == repeatToken and isOpen and selectedEntry() == entry do
				setValue(entry, currentValue(entry.def) + dir * entry.def.step, false)
				task.wait(0.06)
			end
		end)
	end)
	Input.deviceChanged:Connect(function()
		updateHint()
		refreshRowVisibility()
		if isOpen and currentPage == "Controls" and controlsDevice == nil then
			showDevice(SettingsController.currentDevice())
		end
	end)
	Glyphs.changed:Connect(function()
		updateHint()
		if isOpen and currentPage == "Controls" then
			showDevice(controlsDevice or SettingsController.currentDevice())
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local entry = rows.fov
			if entry and isOpen then
				paintRow(entry) -- the horizontal FOV follows the screen's shape
			end
		end)
	end
end

local function wire()
	local function click(button: GuiButton, fn: () -> ())
		button.Activated:Connect(function()
			Sfx.play("UIClick")
			fn()
		end)
	end
	local selection = refs.templates.Selection
	for _, b in ipairs({ refs.settingsTab, refs.controlsTab, refs.close, refs.reset }) do
		b.SelectionImageObject = selection
	end
	click(refs.settingsTab, function()
		showPage("Settings")
	end)
	click(refs.controlsTab, function()
		showPage("Controls")
	end)
	for _, tab in ipairs({ refs.settingsTab, refs.controlsTab }) do
		styleButton(tab, function(on)
			if not tab.Underline.Visible then
				tab.TextColor3 = if on then C.Text else C.TextDim
			end
		end)
	end
	click(refs.close, function()
		SettingsController.close()
	end)
	styleButton(refs.close, function(on)
		Theme.tween(refs.close, Theme.Tween.Fast, { BackgroundTransparency = if on then 0.5 else 1 })
	end)
	click(refs.reset, function()
		local values = {}
		for _, def in ipairs(DEFS) do
			if def.key and not def.hidden then -- progress (hintsSeen) is not a preference: keep it
				values[def.key] = quantize(def, DEFAULTS[def.key] or def.min)
			end
		end
		ClientState.setSettings(values)
		scheduleSave()
		refreshRows()
	end)
	styleButton(refs.reset, function(on)
		Theme.tween(refs.reset, Theme.Tween.Fast, { BackgroundTransparency = if on then 0.3 else 0.6 })
	end)
	for _, b in ipairs(refs.devices:GetChildren()) do
		if b:IsA("TextButton") then
			b.SelectionImageObject = selection
			click(b, function()
				showDevice(b.Name)
			end)
		end
	end
	-- clicking the dimmed backdrop closes; the panel itself sinks clicks
	click(refs.dim, function()
		SettingsController.close()
	end)
	click(refs.launcher, function()
		SettingsController.open()
	end)
	styleButton(refs.launcher, function(on)
		Theme.tween(refs.launcher, Theme.Tween.Fast, { BackgroundTransparency = if on then 0.15 else Theme.Transparency.Panel })
	end)
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------
function SettingsController.Init(_registry)
	-- apply saved settings as early as possible so other controllers start with them
	applyAttribute()
end

function SettingsController.Start()
	player:GetAttributeChangedSignal("SettingsJson"):Connect(applyAttribute)
	ClientState.lifeChanged:Connect(updateLauncher)
	ClientState.spectateChanged:Connect(updateLauncher)
	ClientState.settingsChanged:Connect(applyControls)
	applyControls()
	bindMenuKeys()

	local playerGui = player:WaitForChild("PlayerGui")
	local menu = playerGui:WaitForChild("Menu") :: ScreenGui
	gui = menu
	Theme.bindRoot(menu)
	local root = menu:WaitForChild("Root") :: any
	local panel = root:WaitForChild("Panel")
	refs.dim = menu:WaitForChild("Dim")
	refs.panel = panel
	refs.launcher = root:WaitForChild("Launcher")
	refs.templates = root:WaitForChild("Templates")
	refs.settingsTab = panel.Header.Tabs.SettingsTab
	refs.controlsTab = panel.Header.Tabs.ControlsTab
	refs.close = panel.Header.Close
	refs.settingsPage = panel.Pages.Settings
	refs.controlsPage = panel.Pages.Controls
	refs.devices = panel.Pages.Controls.Devices
	refs.controlsList = panel.Pages.Controls.List
	refs.hint = panel.Footer.Hint
	refs.reset = panel.Footer.Reset
	panel.Active = true
	local bg = panel:FindFirstChild("Bg")
	if bg then
		bg.Active = true
	end
	pcall(function()
		playerGui.SelectionImageObject = refs.templates.Selection
	end)

	buildRows()
	wire()
	hookInput()
	showPage("Settings")
	updateHint()
	updateLauncher()
	applyAttribute()
	menu.Enabled = true
end

return SettingsController
