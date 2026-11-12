--[[
	SyntaxCheck - compile-check scripts WITHOUT running them (works in Edit mode, no playtest needed).
	From execute_luau (Edit):
	  return require(game.ServerStorage.Dev.SyntaxCheck).run()                                   -- whole game
	  return require(game.ServerStorage.Dev.SyntaxCheck).run({ game.ReplicatedStorage.Shared })  -- some roots
	  return require(game.ServerStorage.Dev.SyntaxCheck).checkScript(someScript)
	It only finds syntax errors. Runtime mistakes (nil access, wrong API names) still need careful reading or a playtest.
]]
local LogService = game:GetService("LogService")
local ServerStorage = game:GetService("ServerStorage")

local SyntaxCheck = {}

local function defaultRoots(): { Instance }
	return {
		game:GetService("ReplicatedStorage"),
		game:GetService("ReplicatedFirst"),
		game:GetService("ServerScriptService"),
		game:GetService("StarterPlayer"),
		game:GetService("StarterGui"),
		game:GetService("ServerStorage"),
		workspace,
	}
end

local function probeHolder(): Instance
	local holder = ServerStorage:FindFirstChild("_SyntaxProbes")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "_SyntaxProbes"
		holder.Parent = ServerStorage
	end
	return holder
end

function SyntaxCheck.checkSource(source: string, label: string?): (boolean, string?)
	local holder = probeHolder()
	local probe = Instance.new("ModuleScript")
	local safeName = string.gsub(label or "source", "[^%w_]", "_")
	probe.Name = "Probe_" .. safeName
	probe.Source = "return function(...) " .. source .. "\nend"
	probe.Parent = holder
	local captured = {}
	local connection = LogService.MessageOut:Connect(function(message: string)
		if string.find(message, probe.Name, 1, true) then
			table.insert(captured, message)
		end
	end)
	local ok, err = pcall(require, probe)
	if not ok then
		task.wait()
	end
	connection:Disconnect()
	probe:Destroy()
	if #holder:GetChildren() == 0 then
		holder:Destroy()
	end
	if ok then
		return true, nil
	end
	local message = captured[1] or tostring(err)
	local prefix = "ServerStorage._SyntaxProbes." .. probe.Name
	local s, e = string.find(message, prefix, 1, true)
	if s and e then
		message = (label or "source") .. string.sub(message, e + 1)
	end
	return false, message
end

function SyntaxCheck.checkScript(container: LuaSourceContainer): (boolean, string?)
	return SyntaxCheck.checkSource((container :: any).Source, container:GetFullName())
end

function SyntaxCheck.run(roots: { Instance }?): string
	local list = roots or defaultRoots()
	local failures = {}
	local count = 0
	for _, root in ipairs(list) do
		for _, inst in ipairs(root:GetDescendants()) do
			if inst:IsA("LuaSourceContainer") and not (inst.Parent and inst.Parent.Name == "_SyntaxProbes") then
				count += 1
				local ok, message = SyntaxCheck.checkScript(inst)
				if not ok then
					table.insert(failures, message or inst:GetFullName())
				end
			end
		end
	end
	if #failures == 0 then
		return string.format("SyntaxCheck OK: %d scripts compiled cleanly", count)
	end
	return string.format("SyntaxCheck FAILED: %d of %d scripts have errors:\n%s", #failures, count, table.concat(failures, "\n"))
end

return SyntaxCheck
