--[[
	Server Main - boots every service in ./Services.
	Contract: each service is a ModuleScript returning a table with optional
	Init(Services) (must not yield) and Start() (runs in its own thread, may yield or loop).
]]
local servicesFolder = script.Parent:WaitForChild("Services")

local ORDER = {
	"DataService", "PlayerService", "MovementService", "InventoryService", "LootService",
	"CombatService", "ProjectileService", "ArenaService", "RoundService",
}

local Services = {}
local loaded = {}

local function load(module: ModuleScript)
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		Services[module.Name] = result
		table.insert(loaded, { name = module.Name, mod = result })
	else
		warn(string.format("[Server] Failed to load service %s: %s", module.Name, tostring(result)))
	end
end

local seen = {}
for _, name in ipairs(ORDER) do
	local module = servicesFolder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		seen[module] = true
		load(module)
	end
end
for _, module in ipairs(servicesFolder:GetChildren()) do
	if module:IsA("ModuleScript") and not seen[module] then
		load(module)
	end
end

for _, entry in ipairs(loaded) do
	if type(entry.mod.Init) == "function" then
		local ok, err = xpcall(entry.mod.Init, debug.traceback, Services)
		if not ok then
			warn("[Server] Init failed: " .. entry.name .. "\n" .. tostring(err))
		end
	end
end

for _, entry in ipairs(loaded) do
	if type(entry.mod.Start) == "function" then
		task.spawn(function()
			local ok, err = xpcall(entry.mod.Start, debug.traceback)
			if not ok then
				warn("[Server] Start failed: " .. entry.name .. "\n" .. tostring(err))
			end
		end)
	end
end

print(string.format("[Server] %d services started", #loaded))
