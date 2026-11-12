--[[
	Input - bind gameplay actions once for keyboard/mouse, gamepad and touch. Client only.

	Input.bind(name, handler, opts)
	  handler(state: Enum.UserInputState, input: InputObject?) -> Enum.ContextActionResult?
	    state is Begin or End (Cancel can also arrive from ContextActionService: treat it like End).
	    Return Enum.ContextActionResult.Pass to let lower-priority bindings see the input (default: Sink).
	  opts.keys     { Enum.KeyCode | Enum.UserInputType }, e.g. { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 }
	  opts.touch    true or { label = "RUN", toggle = true, visible = true, position = UDim2?, size = number? }
	                Layout defaults come from Theme.TouchLayout[name]. Toggle buttons send Begin when switched on, End when off.
	  opts.priority ContextActionService priority value (default 2000)
	Input.unbind(name)
	Input.setTouchVisible(name, visible)   -- e.g. show DRINK only near water
	Input.setTouchLabel(name, text)        -- relabel a touch button (ATTACK -> EAT, DRINK -> FILL)
	Input.setToggle(name, on)              -- update a toggle button's state/look without calling the handler
	Input.getTouchButton(name) -> GuiButton?
	Input.isBound(name) -> boolean
	Input.describe(name) -> { name, keys, keyboard, gamepad, touch = { label, visible, toggle, button }? }?
	                                       -- what an action is bound to right now (nil while unbound); keyboard holds the
	                                       -- keyboard and mouse inputs, gamepad the controller ones
	Input.list() -> { string }             -- every action bound right now, sorted
	Input.isTouch() / Input.isGamepad()    -- based on the last input device used
	Input.device() -> "KeyboardMouse" | "Gamepad" | "Touch"     Input.deviceChanged: Signal(device)
	Input.getTouchLayout(name) -> (UDim2, number, string)  -- where a touch button sits (position, size, label) on this screen
	Input.setLookSpeed(device, k)          -- "Gamepad" | "Touch" | "Mouse": scale the default camera's look speed for that
	                                       -- device (the IAS CameraRotationAction bindings). Kept when Roblox's own camera
	                                       -- settings change (sensitivity, invert). nil clears it. Returns whether the
	                                       -- bindings exist; Input.lookBindingsReady() says the same without changing them.
	Every binding is also mirrored onto LocalPlayer.InputBindings (attribute per action) for ServerStorage.Dev.InputCheck.
	Studio only: the LocalPlayer attribute LS_InputOverride = "Touch" | "Gamepad" | "KeyboardMouse" pretends that device
	is in use (hints and settings rows follow it), for checking every device's text from a PC.

	Action names are a contract (see docs/GameDesign.md, section 7).
]]
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Signal = require(script.Parent.Signal)

local Input = {}
Input.deviceChanged = Signal.new()

local bound: { [string]: any } = {}
local touchGui: ScreenGui? = nil
local lastInputKind = "KeyboardMouse"
local overrideKind: string? = nil

local function currentKind(): string
	return overrideKind or lastInputKind
end

local function setKind(kind: string)
	local before = currentKind()
	lastInputKind = kind
	if currentKind() ~= before then
		Input.deviceChanged:Fire(currentKind())
	end
end

UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	if inputType == Enum.UserInputType.Touch then
		setKind("Touch")
	elseif string.sub(inputType.Name, 1, 7) == "Gamepad" then
		setKind("Gamepad")
	elseif inputType == Enum.UserInputType.Keyboard or string.sub(inputType.Name, 1, 5) == "Mouse" then
		setKind("KeyboardMouse")
	end
end)
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	lastInputKind = "Touch"
end

if RunService:IsStudio() and RunService:IsClient() then
	local player = Players.LocalPlayer
	local function readOverride()
		local before = currentKind()
		local v = player and player:GetAttribute("LS_InputOverride")
		overrideKind = if v == "Touch" or v == "Gamepad" or v == "KeyboardMouse" then v else nil
		if currentKind() ~= before then
			Input.deviceChanged:Fire(currentKind())
		end
	end
	if player then
		player:GetAttributeChangedSignal("LS_InputOverride"):Connect(readOverride)
		readOverride()
	end
end

function Input.isTouch(): boolean
	return currentKind() == "Touch"
end

function Input.isGamepad(): boolean
	return currentKind() == "Gamepad"
end

function Input.device(): string
	return currentKind()
end

local function getTouchGui(): ScreenGui
	if touchGui and touchGui.Parent then
		return touchGui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("TouchControls") :: ScreenGui?
	if not gui then
		local created = Instance.new("ScreenGui")
		created.Name = "TouchControls"
		created.ResetOnSpawn = false
		created.IgnoreGuiInset = true
		created.DisplayOrder = 5
		created.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		created.Parent = playerGui
		gui = created
	end
	touchGui = gui
	return gui :: ScreenGui
end

local function isLargeScreen(): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local v = camera.ViewportSize
	return math.min(v.X, v.Y) > 500
end

local function layoutFor(name: string, touchOpts): (UDim2, number, string)
	local layout = Theme.TouchLayout[name] or Theme.TouchLayout.Default
	local position: UDim2 = touchOpts.position or layout.position
	local size: number = touchOpts.size or layout.size or 60
	if isLargeScreen() then
		position = UDim2.new(position.X.Scale, position.X.Offset * 1.55, position.Y.Scale, position.Y.Offset * 1.55)
		size = math.floor(size * 1.3)
	end
	return position, size, touchOpts.label or layout.label or string.upper(name)
end

local function makeTouchButton(name: string, entry)
	local touchOpts = entry.touchOpts
	local position, size, label = layoutFor(name, touchOpts)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.Size = UDim2.fromOffset(size, size)
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Colors.Panel
	button.BackgroundTransparency = 0.45
	button.Text = label
	button.TextColor3 = Theme.Colors.Text
	button.FontFace = Theme.Fonts.Heading
	button.TextSize = math.max(13, math.floor(size * 0.19))
	button.Selectable = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.Text
	stroke.Transparency = 0.7
	stroke.Thickness = 1.25
	stroke.Parent = button
	-- faint inner ring for a little depth
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, -8, 1, -8)
	ring.BackgroundTransparency = 1
	ring.Active = false
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Theme.Colors.Text
	ringStroke.Transparency = 0.9
	ringStroke.Thickness = 1
	ringStroke.Parent = ring
	ring.Parent = button
	local pop = Instance.new("UIScale")
	pop.Parent = button

	local function paint()
		local active = entry.toggled or entry.pressed
		TweenService:Create(button, Theme.Tween.Fast, {
			BackgroundColor3 = if active then Theme.Colors.Accent else Theme.Colors.Panel,
			BackgroundTransparency = if active then 0.12 else 0.45,
		}):Play()
		button.TextColor3 = if active then Theme.Colors.TextDark else Theme.Colors.Text
		stroke.Color = if active then Theme.Colors.AccentSoft else Theme.Colors.Text
		stroke.Transparency = if active then 0.3 else 0.7
		ringStroke.Transparency = if active then 0.6 else 0.9
		TweenService:Create(pop, Theme.Tween.Fast, { Scale = if entry.pressed then 0.93 else 1 }):Play()
	end
	entry.paint = paint

	button.InputBegan:Connect(function(io: InputObject)
		if io.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if touchOpts.toggle then
			entry.toggled = not entry.toggled
			paint()
			entry.handler(if entry.toggled then Enum.UserInputState.Begin else Enum.UserInputState.End, io)
			return
		end
		if entry.pressed then
			return
		end
		entry.pressed = true
		paint()
		entry.handler(Enum.UserInputState.Begin, io)
		local connection
		connection = io:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if io.UserInputState == Enum.UserInputState.End or io.UserInputState == Enum.UserInputState.Cancel then
				connection:Disconnect()
				if entry.pressed then
					entry.pressed = false
					paint()
					entry.handler(Enum.UserInputState.End, io)
				end
			end
		end)
	end)

	button.Visible = UserInputService.TouchEnabled and touchOpts.visible ~= false
	button.Parent = getTouchGui()
	return button
end

-- Dev tools (ServerStorage.Dev.InputCheck) read the bindings from LocalPlayer.InputBindings: one attribute per action,
-- "keys=E,ButtonX;touch=DRINK". Instances are shared with the command bar, which runs its own copy of this module.
local mirrorFolder: Instance? = nil
local function mirrorBinding(name: string)
	local player = Players.LocalPlayer
	if not player then
		return
	end
	pcall(function()
		if not (mirrorFolder and mirrorFolder.Parent) then
			mirrorFolder = player:FindFirstChild("InputBindings")
			if not mirrorFolder then
				local folder = Instance.new("Configuration")
				folder.Name = "InputBindings"
				folder.Parent = player
				mirrorFolder = folder
			end
		end
		local entry = bound[name]
		if not entry then
			(mirrorFolder :: Instance):SetAttribute(name, nil)
			return
		end
		local keys = {}
		for _, key in ipairs(entry.opts.keys or {}) do
			table.insert(keys, key.Name)
		end
		local touch = ""
		if entry.touchOpts then
			local button = entry.button
			local _, _, label = layoutFor(name, entry.touchOpts)
			touch = if button and button:IsA("TextButton") then button.Text else label
		end
		(mirrorFolder :: Instance):SetAttribute(name, "keys=" .. table.concat(keys, ",") .. ";touch=" .. touch)
	end)
end

function Input.bind(name: string, handler: (Enum.UserInputState, InputObject?) -> Enum.ContextActionResult?, opts: { [string]: any }?)
	local o = opts or {}
	Input.unbind(name)
	local entry = { handler = handler, opts = o, toggled = false, pressed = false, touchOpts = nil, button = nil, paint = nil }
	bound[name] = entry
	local keys = o.keys or {}
	if #keys > 0 then
		ContextActionService:BindActionAtPriority(name, function(_, state, io)
			local result = handler(state, io)
			if result ~= nil then
				return result
			end
			return Enum.ContextActionResult.Sink
		end, false, o.priority or 2000, table.unpack(keys))
	end
	if o.touch then
		entry.touchOpts = if type(o.touch) == "table" then o.touch else {}
		entry.button = makeTouchButton(name, entry)
	end
	mirrorBinding(name)
end

function Input.unbind(name: string)
	local entry = bound[name]
	if not entry then
		return
	end
	bound[name] = nil
	pcall(function()
		ContextActionService:UnbindAction(name)
	end)
	if entry.button then
		entry.button:Destroy()
	end
	mirrorBinding(name)
end

function Input.setTouchVisible(name: string, visible: boolean)
	local entry = bound[name]
	if entry and entry.button then
		entry.button.Visible = UserInputService.TouchEnabled and visible
	end
end

function Input.setTouchLabel(name: string, text: string)
	local entry = bound[name]
	local button = entry and entry.button
	if button and button:IsA("TextButton") and type(text) == "string" and button.Text ~= text then
		button.Text = text
		mirrorBinding(name)
	end
end

function Input.setToggle(name: string, on: boolean)
	local entry = bound[name]
	if entry and entry.touchOpts and entry.touchOpts.toggle then
		entry.toggled = on
		if entry.paint then
			entry.paint()
		end
	end
end

function Input.getTouchButton(name: string): GuiButton?
	local entry = bound[name]
	return entry and entry.button
end

function Input.isBound(name: string): boolean
	return bound[name] ~= nil
end

local function isGamepadInput(key: any): boolean
	if typeof(key) ~= "EnumItem" then
		return false
	end
	local n = key.Name
	if key.EnumType == Enum.UserInputType then
		return string.sub(n, 1, 7) == "Gamepad"
	end
	return string.sub(n, 1, 6) == "Button" or string.sub(n, 1, 4) == "DPad" or string.sub(n, 1, 10) == "Thumbstick"
end

function Input.describe(name: string)
	local entry = bound[name]
	if not entry then
		return nil
	end
	local keys = entry.opts.keys or {}
	local keyboard, gamepad = {}, {}
	for _, key in ipairs(keys) do
		table.insert(if isGamepadInput(key) then gamepad else keyboard, key)
	end
	local touch = nil
	if entry.touchOpts then
		local button = entry.button
		local _, _, label = layoutFor(name, entry.touchOpts)
		touch = {
			label = if button and button:IsA("TextButton") then button.Text else label,
			visible = button ~= nil and button.Visible,
			toggle = entry.touchOpts.toggle == true,
			button = button,
		}
	end
	return { name = name, keys = table.clone(keys), keyboard = keyboard, gamepad = gamepad, touch = touch }
end

function Input.list(): { string }
	local names = {}
	for name in pairs(bound) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Where a touch button sits on this screen (same rules the buttons use): position (AnchorPoint 0.5, 0.5), size, label.
function Input.getTouchLayout(name: string): (UDim2, number, string)
	local entry = bound[name]
	return layoutFor(name, (entry and entry.touchOpts) or {})
end

--------------------------------------------------------------------------------------------------------------------
-- Look speed per device (the default camera reads look input through the IAS CameraRotationAction; its CameraInput
-- sets each binding's Scale from Roblox's own settings and flips Vector2Scale.Y for "invert", so we scale the
-- magnitude of Vector2Scale and keep its signs).
--------------------------------------------------------------------------------------------------------------------
local LOOK_BINDINGS: { [string]: { string } } = {
	Gamepad = { "GamepadBinding", "MicroGamepadBinding" },
	Touch = { "TouchBinding" },
	Mouse = { "MouseBinding", "TrackpadBinding" },
}
local lookSpeeds: { [string]: number } = {}
local baseScales: { [Instance]: Vector2 } = {}
local lookHooked = false

local function rotationAction(): Instance?
	local roots = { StarterPlayer:FindFirstChild("PlayerModule") }
	local player = Players.LocalPlayer
	local scripts = player and player:FindFirstChildOfClass("PlayerScripts")
	if scripts then
		table.insert(roots, scripts:FindFirstChild("PlayerModule"))
	end
	for _, root in ipairs(roots) do
		local contexts = root and root:FindFirstChild("InputContexts")
		local camera = contexts and contexts:FindFirstChild("CameraContext")
		local action = camera and camera:FindFirstChild("CameraRotationAction")
		if action then
			return action
		end
	end
	return nil
end

local function applyLookSpeeds(): boolean
	local action = rotationAction()
	if not action then
		return false
	end
	for device, names in pairs(LOOK_BINDINGS) do
		for _, bindingName in ipairs(names) do
			local binding = action:FindFirstChild(bindingName)
			if binding and binding:IsA("InputBinding") then
				local current = binding.Vector2Scale
				local base = baseScales[binding]
				if not base then
					base = Vector2.new(math.abs(current.X), math.abs(current.Y))
					baseScales[binding] = base
				end
				local k = lookSpeeds[device] or 1
				local want = Vector2.new(
					(if current.X < 0 then -1 else 1) * base.X * k,
					(if current.Y < 0 then -1 else 1) * base.Y * k
				)
				if math.abs(want.X - current.X) > 1e-7 or math.abs(want.Y - current.Y) > 1e-7 then
					binding.Vector2Scale = want
				end
			end
		end
	end
	return true
end

local function hookLook()
	if lookHooked then
		return
	end
	lookHooked = true
	local ok, settings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	if ok and settings then
		-- Roblox's camera script rewrites the bindings when these change; apply ours again after it has run
		settings.Changed:Connect(function()
			task.defer(applyLookSpeeds)
		end)
	end
	task.spawn(function()
		-- the default camera's input contexts load after us: retry until they exist
		for _ = 1, 60 do
			if applyLookSpeeds() then
				return
			end
			task.wait(1)
		end
	end)
end

function Input.setLookSpeed(device: string, k: number?): boolean
	if not LOOK_BINDINGS[device] then
		return false
	end
	if type(k) == "number" and k == k and k > 0 then
		lookSpeeds[device] = math.clamp(k, 0.05, 10)
	else
		lookSpeeds[device] = nil
	end
	hookLook()
	return applyLookSpeeds()
end

-- True once the default camera's IAS rotation bindings exist (CameraController then scales the mouse binding).
function Input.lookBindingsReady(): boolean
	return rotationAction() ~= nil
end

return Input
