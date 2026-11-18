--[[
	TrainSceneryController - the countryside sliding past the red train's windows (client only, cheap).
	workspace.Lobby.Scenery (built by WorldGen.BlenderTemplates.buildTrainLobby) holds each scenery layer three times
	per side, attribute Speed (studs a second; the hills slower than the near trees, for depth) and the folder's
	Length (400). Every frame the layers slide toward the train's tail (world +Z of the lobby's pivot frame) and wrap,
	so a window never sees an end. Only while the camera is near the train; one BulkMoveTo a frame (36 parts).
	With reduced motion the scenery stands still.
]]
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local TrainSceneryController = {}

local NEAR = 600 -- studs from the train's pivot inside which the scenery moves

type Layer = { part: BasePart, base: CFrame, s0: number, speed: number }

local layers: { Layer } = {}
local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local length = 400
local pivot = CFrame.identity
local back = Vector3.new(0, 0, 1)
local scenery: Instance? = nil

local function collect(folder: Instance)
	table.clear(layers)
	table.clear(parts)
	table.clear(cframes)
	scenery = folder
	length = tonumber(folder:GetAttribute("Length")) or 400
	local lobby = folder.Parent
	pivot = if lobby and lobby:IsA("Model") then lobby.WorldPivot else CFrame.identity
	back = -pivot.LookVector
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then
			local speed = tonumber(p:GetAttribute("Speed")) or 0
			if speed > 0 then
				local s0 = (p.Position - pivot.Position):Dot(back)
				table.insert(layers, { part = p, base = p.CFrame - back * s0, s0 = s0, speed = speed })
				table.insert(parts, p)
				table.insert(cframes, p.CFrame)
			end
		end
	end
end

local function step()
	local folder = scenery
	if not folder or not folder.Parent then
		local lobby = workspace:FindFirstChild("Lobby")
		local f = lobby and lobby:FindFirstChild("Scenery")
		if f then
			collect(f)
		else
			scenery = nil
		end
		return
	end
	if #layers == 0 or GuiService.ReducedMotionEnabled then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - pivot.Position).Magnitude > NEAR then
		return
	end
	local t = workspace:GetServerTimeNow()
	local span = length * 3
	for i, l in ipairs(layers) do
		local s = (l.s0 + t * l.speed + span * 0.5) % span - span * 0.5
		cframes[i] = l.base + back * s
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function TrainSceneryController.Init(_registry) end

function TrainSceneryController.Start()
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			warn("[TrainSceneryController] " .. tostring(err))
			scenery = nil
		end
	end)
end

return TrainSceneryController
