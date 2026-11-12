--[[
	InputCheck - Studio-only check that every gameplay action has a keyboard, a gamepad and a touch binding in the state
	you are in (PlayabilityPlan QW15). It guards against a Roblox controls change quietly breaking an action.

	Run it during a playtest:
	  1. Server (command bar on the server, or execute_luau Server):
	       require(game.ServerStorage.Dev.InputCheck).install()
	     copies this module to ReplicatedStorage.DevInputCheck so the client can require it (Studio only).
	  2. Client (command bar on the client):
	       print(require(game.ReplicatedStorage:WaitForChild("DevInputCheck")).run())
	     -> "PASS ..." or "FAIL ..." plus one line per action: keyboard / gamepad / touch, each OK or MISSING.
	     run({ state = "Arena" }) checks a given state; run({ unbind = { "Attack" } }) pretends Attack is unbound
	     (it must FAIL then) without touching the live game.
	  3. Server, when done: require(game.ServerStorage.Dev.InputCheck).uninstall()

	It reads the bindings that Shared.Input mirrors onto LocalPlayer.InputBindings (one attribute per action), so it works
	from the command bar too, which runs its own copy of every module. The state is detected from the LocalPlayer's
	attributes: Lobby, Plate (Countdown, frozen on a launch plate), Arena (alive in a round); from the command bar,
	Spectating isn't visible, so pass run({ state = "Spectating" }) while you spectate.
	An action may name a stand-in for one device: "gui:<path under PlayerGui>" (a button the UI draws, e.g. the touch
	menu button or the hotbar slots), "via:<Action>" (another action covers it, e.g. LB / RB pick items on a gamepad),
	"wheel" (the mouse wheel, InventoryController), "auto" (touch sprint on Auto needs no button), and "optional" (only
	bound in some moments, e.g. Drink near water).
	Movement and jumping come from Roblox's own controls (PlayerModule), so they are in the publish checklist
	(docs/handoff/PublishChecklist.md) instead.
]]
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputCheck = {}

local SLOT_TOUCH = "gui:HUD.Root.Hotbar.Slots" -- the touch hotbar: tap a slot
local SLOT = { gamepad = "via:NextSlot", touch = SLOT_TOUCH }

InputCheck.EXPECTED = {
	Lobby = {
		Menu = { touch = "gui:Lobby.Root.Brand.Buttons.Settings" }, -- M / D-pad up; touch: the lobby SETTINGS button
		LobbySpectate = { optional = true, keyboard = "gui:Lobby.Root.Status.Pill.Spectate", touch = "gui:Lobby.Root.Status.Pill.Spectate" },
		Sprint = { touch = "auto" },
		Crouch = {},
	},
	Plate = {
		Menu = { touch = "gui:Menu.Root.Launcher" },
		Attack = {},
		Aim = { optional = true }, -- bound with the weapon; its touch button shows for the bow and spear only
		Slot1 = SLOT, Slot2 = SLOT, Slot3 = SLOT, Slot4 = SLOT, Slot5 = SLOT, Slot6 = SLOT,
		NextSlot = { keyboard = "wheel", touch = SLOT_TOUCH },
		PrevSlot = { keyboard = "wheel", touch = SLOT_TOUCH },
		Drop = {},
		Sprint = { touch = "auto" },
		Crouch = {},
	},
	Arena = {
		Menu = { touch = "gui:Menu.Root.Launcher" },
		Attack = {},
		Aim = {},
		Slot1 = SLOT, Slot2 = SLOT, Slot3 = SLOT, Slot4 = SLOT, Slot5 = SLOT, Slot6 = SLOT,
		NextSlot = { keyboard = "wheel", touch = SLOT_TOUCH },
		PrevSlot = { keyboard = "wheel", touch = SLOT_TOUCH },
		Drop = {},
		Drink = { optional = true }, -- bound only while you look at water
		Sprint = { touch = "auto" },
		Crouch = {},
	},
	Spectating = {
		Menu = { touch = "gui:Menu.Root.Launcher" },
		SpectatePrev = { touch = "gui:Spectate.Root.Card.Prev" },
		SpectateNext = { touch = "gui:Spectate.Root.Card.Next" },
		SpectateExit = { touch = "gui:Spectate.Root.Exit" },
	},
}

-- Copy this module where the client can require it (Studio only).
function InputCheck.install()
	assert(RunService:IsStudio(), "InputCheck is Studio-only")
	local existing = ReplicatedStorage:FindFirstChild("DevInputCheck")
	if existing then
		existing:Destroy()
	end
	local copy = script:Clone()
	copy.Name = "DevInputCheck"
	copy.Parent = ReplicatedStorage
	return "installed: ReplicatedStorage.DevInputCheck"
end

function InputCheck.uninstall()
	local existing = ReplicatedStorage:FindFirstChild("DevInputCheck")
	if existing then
		existing:Destroy()
	end
	return "removed"
end

local function guiExists(path: string): boolean
	local player = game:GetService("Players").LocalPlayer
	local node: Instance? = player and player:FindFirstChildOfClass("PlayerGui")
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node ~= nil
end

local function isPadName(name: string): boolean
	return string.sub(name, 1, 6) == "Button" or string.sub(name, 1, 4) == "DPad" or string.sub(name, 1, 10) == "Thumbstick"
		or string.sub(name, 1, 7) == "Gamepad"
end

-- What an action is bound to right now: { keyboard = { names }, gamepad = { names }, touch = { label }? } or nil.
local function describe(name: string): { [string]: any }?
	local player = game:GetService("Players").LocalPlayer
	local mirror = player and player:FindFirstChild("InputBindings")
	if not mirror then
		return nil
	end
	local value = mirror:GetAttribute(name)
	if type(value) ~= "string" then
		return nil
	end
	local keysPart, touchPart = string.match(value, "^keys=(.-);touch=(.*)$")
	local keyboard, gamepad = {}, {}
	for key in string.gmatch(keysPart or "", "[^,]+") do
		table.insert(if isPadName(key) then gamepad else keyboard, key)
	end
	return { keyboard = keyboard, gamepad = gamepad, touch = if touchPart and touchPart ~= "" then { label = touchPart } else nil }
end

local function standIn(rule: string?, device: string, settingsMode: number?): (boolean, string?)
	if type(rule) ~= "string" then
		return false, nil
	end
	if rule == "wheel" then
		return true, "mouse wheel"
	elseif rule == "auto" then
		return settingsMode == 2, "Auto (no button needed)"
	elseif string.sub(rule, 1, 4) == "gui:" then
		local path = string.sub(rule, 5)
		return guiExists(path), "GUI " .. path
	elseif string.sub(rule, 1, 4) == "via:" then
		local other = describe(string.sub(rule, 5))
		local list = other and other[device]
		return type(list) == "table" and #list > 0, "via " .. string.sub(rule, 5)
	end
	return false, nil
end

local function detectState(player: Player): string
	if player:GetAttribute("InArena") ~= true then
		return "Lobby"
	elseif player:GetAttribute("Frozen") == true then
		return "Plate"
	end
	return "Arena"
end

function InputCheck.run(opts: { [string]: any }?): string
	assert(RunService:IsClient(), "run InputCheck.run() on the client")
	local o = opts or {}
	local player = game:GetService("Players").LocalPlayer
	if not player:FindFirstChild("InputBindings") then
		return "FAIL no LocalPlayer.InputBindings (Shared.Input mirrors its bindings there; is the game running?)"
	end
	local state = o.state or detectState(player)
	local expected = InputCheck.EXPECTED[state]
	if not expected then
		return "FAIL unknown state " .. tostring(state)
	end
	local pretendUnbound: { [string]: boolean } = {}
	for _, name in ipairs(o.unbind or {}) do
		pretendUnbound[name] = true
	end
	local sprintTouchMode = 2
	local json = player:GetAttribute("SettingsJson")
	if type(json) == "string" then
		local ok, decoded = pcall(function()
			return game:GetService("HttpService"):JSONDecode(json)
		end)
		if ok and type(decoded) == "table" and tonumber(decoded.sprintModeTouch) then
			sprintTouchMode = tonumber(decoded.sprintModeTouch) :: number
		end
	end
	local names = {}
	for name in pairs(expected) do
		table.insert(names, name)
	end
	table.sort(names)
	local lines = {}
	local failures = 0
	for _, name in ipairs(names) do
		local rule = expected[name]
		local info = if pretendUnbound[name] then nil else describe(name)
		if info == nil and rule.optional then
			table.insert(lines, string.format("  %-13s (not bound right now: allowed)", name))
		else
			local cells = {}
			local missing = false
			for _, device in ipairs({ "keyboard", "gamepad", "touch" }) do
				local ok, how = false, nil
				if info then
					if device == "touch" then
						ok = info.touch ~= nil
						how = if ok then "button " .. tostring(info.touch.label) else nil
					else
						local list = info[device]
						ok = type(list) == "table" and #list > 0
						if ok then
							how = table.concat(list, "/")
						end
					end
				end
				if not ok then
					ok, how = standIn(rule[device], device, if name == "Sprint" then sprintTouchMode else nil)
				end
				if not ok then
					missing = true
				end
				table.insert(cells, string.format("%s %s", device, if ok then "OK (" .. tostring(how) .. ")" else "MISSING"))
			end
			if missing then
				failures += 1
			end
			table.insert(lines, string.format("%s %-13s %s", if missing then "x" else " ", name, table.concat(cells, " · ")))
		end
	end
	local verdict = if failures == 0
		then string.format("PASS %s: %d actions have keyboard, gamepad and touch input", state, #names)
		else string.format("FAIL %s: %d of %d actions are missing an input", state, failures, #names)
	return verdict .. "\n" .. table.concat(lines, "\n")
end

return InputCheck
