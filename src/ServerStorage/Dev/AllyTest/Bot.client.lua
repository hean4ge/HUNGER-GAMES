-- ALT_Bot (allies test): test-only client bot, cloned by ALT_Driver into a test player's PlayerGui inside a Studio
-- multiplayer test. It drives AllyController's Studio test hook and reports what this screen shows.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end
local lp = Players.LocalPlayer
local callFn = RS:WaitForChild("MPT_Call", 30) :: RemoteFunction?
local repEv = RS:WaitForChild("MPT_Rep", 30) :: RemoteEvent?
if not (lp and callFn and repEv) then
	return
end
local TAG = "[MPT][C:" .. lp.Name .. "] "
local function L(s: string)
	print(TAG .. s)
	repEv:FireServer(s)
end

local controllers = lp:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")
local Ally = require(controllers:WaitForChild("AllyController")) :: any

callFn.OnClientInvoke = function(cmd: string, arg: any): any
	local ok, res = pcall(function(): any
		if cmd == "ally" and type(arg) == "table" then
			if arg[1] == "send" then
				RS.Remotes.AllyAsk:FireServer({ op = arg[2], target = arg[3] })
				return true
			end
			return Ally._test(arg[1], arg[2])
		end
		return nil
	end)
	if not ok then
		L("CALL " .. tostring(cmd) .. " failed: " .. tostring(res))
		return { error = tostring(res) }
	end
	return res
end

-- test-only: the camera follows the player (the Studio test clients can start on a Fixed camera)
task.spawn(function()
	task.wait(3)
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Fixed then
		cam.CameraType = Enum.CameraType.Custom
		L("CAMERA set to Custom (test-only)")
	end
end)

L("BOT ready " .. lp.Name)
repEv:FireServer("\0READY")
