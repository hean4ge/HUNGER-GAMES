--[[
	Glyphs - the name of a button on the player's own device, for hints and control lists (PlayabilityPlan QW13).
	Client only.

	Glyphs.forKey(key: Enum.KeyCode | Enum.UserInputType, family: string?) -> string
	    Keyboard keys follow the player's keyboard layout (UserInputService:GetStringForKeyCode); Shift, Space and
	    the like get short names; mouse buttons read LMB / RMB / MMB. Gamepad buttons use the connected pad's own
	    names: Xbox "X", "RT", "LB", "LS"...; PlayStation "SQUARE", "R2", "L1", "L3"... (`family` overrides the guess).
	Glyphs.imageForKey(keyCode) -> string?     Roblox's icon for a gamepad button on this platform (nil if none)
	Glyphs.family() -> "Xbox" | "PlayStation"  the connected gamepad's family (Xbox when unknown)
	Glyphs.forAction(name, device?) -> string? the button for a Shared.Input action on a device ("KeyboardMouse" |
	    "Gamepad" | "Touch"; default: the device in use): its first key for that device, or the touch button's label.
	    Falls back to Glyphs.DEFAULTS while the action isn't bound (Drink is only bound near water).
	Glyphs.DEFAULTS                             the keys each gameplay action is bound to (keep in step with the binds)
	Glyphs.changed: Signal()                    the device in use or the gamepad family changed
	Studio only: the LocalPlayer attribute LS_GlyphFamily = "PlayStation" | "Xbox" forces a family, for checking hints
	without that controller.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(script.Parent.Signal)
local Input = require(script.Parent.Input)

local Glyphs = {}
Glyphs.changed = Signal.new()

local KEYBOARD_NAMES: { [string]: string } = {
	LeftShift = "SHIFT", RightShift = "SHIFT", LeftControl = "CTRL", RightControl = "CTRL",
	LeftAlt = "ALT", RightAlt = "ALT", LeftMeta = "CMD", RightMeta = "CMD", LeftSuper = "WIN", RightSuper = "WIN",
	Space = "SPACE", Return = "ENTER", KeypadEnter = "ENTER", Tab = "TAB", Backspace = "BACKSPACE",
	Escape = "ESC", Delete = "DEL", CapsLock = "CAPS", Up = "UP", Down = "DOWN", Left = "LEFT", Right = "RIGHT",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	MouseLeftButton = "LMB", MouseRightButton = "RMB", MouseMiddleButton = "MMB",
}
local INPUT_TYPE_NAMES: { [string]: string } = {
	MouseButton1 = "LMB", MouseButton2 = "RMB", MouseButton3 = "MMB", MouseWheel = "WHEEL", MouseMovement = "MOUSE",
	Touch = "TAP",
}
local PAD_NAMES: { [string]: { [string]: string } } = {
	Xbox = {
		ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y", ButtonL1 = "LB", ButtonR1 = "RB", ButtonL2 = "LT",
		ButtonR2 = "RT", ButtonL3 = "LS", ButtonR3 = "RS", ButtonStart = "MENU", ButtonSelect = "VIEW",
		DPadUp = "D-PAD UP", DPadDown = "D-PAD DOWN", DPadLeft = "D-PAD LEFT", DPadRight = "D-PAD RIGHT",
		Thumbstick1 = "LEFT STICK", Thumbstick2 = "RIGHT STICK",
	},
	PlayStation = {
		ButtonA = "CROSS", ButtonB = "CIRCLE", ButtonX = "SQUARE", ButtonY = "TRIANGLE", ButtonL1 = "L1",
		ButtonR1 = "R1", ButtonL2 = "L2", ButtonR2 = "R2", ButtonL3 = "L3", ButtonR3 = "R3", ButtonStart = "OPTIONS",
		ButtonSelect = "CREATE", DPadUp = "D-PAD UP", DPadDown = "D-PAD DOWN", DPadLeft = "D-PAD LEFT",
		DPadRight = "D-PAD RIGHT", Thumbstick1 = "LEFT STICK", Thumbstick2 = "RIGHT STICK",
	},
}

-- The keys every gameplay action is bound to (the binds live in the controllers; keep this table in step).
Glyphs.DEFAULTS = {
	Attack = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
	Aim = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2 },
	Drink = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
	Interact = { Enum.KeyCode.E, Enum.KeyCode.ButtonX }, -- crates and ground items (ProximityPrompts)
	Crouch = { Enum.KeyCode.C, Enum.KeyCode.ButtonB },
	Sprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },
	Jump = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA },
	Drop = { Enum.KeyCode.G, Enum.KeyCode.DPadDown },
	NextSlot = { Enum.KeyCode.ButtonR1 },
	PrevSlot = { Enum.KeyCode.ButtonL1 },
	Menu = { Enum.KeyCode.M, Enum.KeyCode.DPadUp },
}
-- Touch names for actions that have no Shared.Input button of their own.
local TOUCH_FALLBACK: { [string]: string } = { Jump = "JUMP", Interact = "TAP" }

local function isGamepadName(name: string): boolean
	return string.sub(name, 1, 6) == "Button" or string.sub(name, 1, 4) == "DPad" or string.sub(name, 1, 10) == "Thumbstick"
end

local function isGamepadKey(key: any): boolean
	if typeof(key) ~= "EnumItem" then
		return false
	end
	if key.EnumType == Enum.UserInputType then
		return string.sub(key.Name, 1, 7) == "Gamepad"
	end
	return key.EnumType == Enum.KeyCode and isGamepadName(key.Name)
end
Glyphs.isGamepadKey = isGamepadKey

local detectedFamily = "Xbox"

local function detectFamily(): string
	if RunService:IsStudio() then
		local forced = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("LS_GlyphFamily")
		if forced == "PlayStation" or forced == "Xbox" then
			return forced
		end
	end
	local okS, s = pcall(UserInputService.GetStringForKeyCode, UserInputService, Enum.KeyCode.ButtonA)
	if okS and type(s) == "string" and string.find(string.lower(s), "cross", 1, true) then
		return "PlayStation"
	end
	local okI, image = pcall(UserInputService.GetImageForKeyCode, UserInputService, Enum.KeyCode.ButtonA)
	if okI and type(image) == "string" then
		local lower = string.lower(image)
		if string.find(lower, "playstation", 1, true) or string.find(lower, "cross", 1, true)
			or string.find(lower, "ps4", 1, true) or string.find(lower, "ps5", 1, true) then
			return "PlayStation"
		end
	end
	return "Xbox"
end

function Glyphs.family(): string
	return detectedFamily
end

function Glyphs.forKey(key: any, family: string?): string
	if typeof(key) ~= "EnumItem" then
		return "?"
	end
	local name = key.Name
	if key.EnumType == Enum.UserInputType then
		return INPUT_TYPE_NAMES[name] or string.upper(name)
	end
	if isGamepadName(name) then
		local names = PAD_NAMES[family or detectedFamily] or PAD_NAMES.Xbox
		return names[name] or PAD_NAMES.Xbox[name] or string.upper(name)
	end
	local fixed = KEYBOARD_NAMES[name]
	if fixed then
		return fixed
	end
	local ok, s = pcall(UserInputService.GetStringForKeyCode, UserInputService, key)
	if ok and type(s) == "string" then
		s = string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
		if s ~= "" then
			return string.upper(s)
		end
	end
	return string.upper(name)
end

function Glyphs.imageForKey(key: any): string?
	if typeof(key) ~= "EnumItem" or key.EnumType ~= Enum.KeyCode then
		return nil
	end
	local ok, image = pcall(UserInputService.GetImageForKeyCode, UserInputService, key)
	if ok and type(image) == "string" and image ~= "" then
		return image
	end
	return nil
end

local function firstFor(keys: { any }?, gamepad: boolean): any
	if type(keys) ~= "table" then
		return nil
	end
	for _, key in ipairs(keys) do
		if isGamepadKey(key) == gamepad then
			return key
		end
	end
	return nil
end

function Glyphs.forAction(name: string, device: string?): string?
	local d = device or Input.device()
	local info = Input.describe(name)
	if d == "Touch" then
		if info and info.touch and type(info.touch.label) == "string" and info.touch.label ~= "" then
			return info.touch.label
		end
		if TOUCH_FALLBACK[name] then
			return TOUCH_FALLBACK[name]
		end
		local _, _, label = Input.getTouchLayout(name)
		return label
	end
	local gamepad = d == "Gamepad"
	local key = info and firstFor(info.keys, gamepad)
	if key == nil then
		key = firstFor(Glyphs.DEFAULTS[name], gamepad)
	end
	if key == nil then
		return nil
	end
	return Glyphs.forKey(key)
end

local lastDevice = Input.device()
local function refresh()
	local family = detectFamily()
	local device = Input.device()
	if family ~= detectedFamily or device ~= lastDevice then
		detectedFamily = family
		lastDevice = device
		Glyphs.changed:Fire()
	end
end

if RunService:IsClient() then
	detectedFamily = detectFamily()
	UserInputService.GamepadConnected:Connect(refresh)
	UserInputService.GamepadDisconnected:Connect(refresh)
	Input.deviceChanged:Connect(refresh)
	local player = Players.LocalPlayer
	if player and RunService:IsStudio() then
		player:GetAttributeChangedSignal("LS_GlyphFamily"):Connect(refresh)
	end
end

return Glyphs
