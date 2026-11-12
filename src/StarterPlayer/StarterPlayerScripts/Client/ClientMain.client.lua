--[[
	ClientMain - boots every client controller in ./Controllers.
	Contract: each controller is a ModuleScript returning a table with optional
	Init(Controllers) (must not yield) and Start() (runs in its own thread, may yield or loop).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sfx = require(Shared:WaitForChild("Sfx"))

local controllersFolder = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"SettingsController", "CameraController", "MovementController", "CharacterVisuals",
	"InventoryController", "CombatController", "ViewmodelController", "ProjectileController",
	"AudioController", "ArenaController", "HUDController", "LobbyController",
	"NotificationController", "SpectateController",
}

local Controllers = {}
local loaded = {}

local function load(module: ModuleScript)
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		Controllers[module.Name] = result
		table.insert(loaded, { name = module.Name, mod = result })
	else
		warn(string.format("[Client] Failed to load controller %s: %s", module.Name, tostring(result)))
	end
end

local seen = {}
for _, name in ipairs(ORDER) do
	local module = controllersFolder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		seen[module] = true
		load(module)
	end
end
for _, module in ipairs(controllersFolder:GetChildren()) do
	if module:IsA("ModuleScript") and not seen[module] then
		load(module)
	end
end

Sfx.initClient()

for _, entry in ipairs(loaded) do
	if type(entry.mod.Init) == "function" then
		local ok, err = xpcall(entry.mod.Init, debug.traceback, Controllers)
		if not ok then
			warn("[Client] Init failed: " .. entry.name .. "\n" .. tostring(err))
		end
	end
end

for _, entry in ipairs(loaded) do
	if type(entry.mod.Start) == "function" then
		task.spawn(function()
			local ok, err = xpcall(entry.mod.Start, debug.traceback)
			if not ok then
				warn("[Client] Start failed: " .. entry.name .. "\n" .. tostring(err))
			end
		end)
	end
end

print(string.format("[Client] %d controllers started", #loaded))
