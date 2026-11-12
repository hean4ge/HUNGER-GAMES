--[[
	Util - small helpers shared by client and server.
]]
local Players = game:GetService("Players")

local Util = {}

function Util.serverTime(): number
	return workspace:GetServerTimeNow()
end

function Util.formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Util.lerp(a: any, b: any, t: number): any
	return a + (b - a) * t
end

-- Frame-rate independent smoothing factor: x = x + (target - x) * Util.damp(rate, dt)
function Util.damp(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n > -1e9 and n < 1e9
end

function Util.isFiniteVector(v: any): boolean
	return typeof(v) == "Vector3"
		and Util.isFiniteNumber(v.X)
		and Util.isFiniteNumber(v.Y)
		and Util.isFiniteNumber(v.Z)
end

function Util.getHumanoid(model: Instance?): Humanoid?
	if not model then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

-- The Player whose character contains this part, if any.
function Util.playerFromPart(part: Instance?): Player?
	local model = part and part:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- The Humanoid (and its model) that owns this part, if any (works for NPCs too).
function Util.humanoidFromPart(part: Instance?): (Humanoid?, Model?)
	local model = part and part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

-- entries: { { weight = number, ... }, ... } -> one entry
function Util.weightedPick(entries: { any }, rng: Random?): any
	local total = 0
	for _, entry in ipairs(entries) do
		total += entry.weight or 1
	end
	local roll = (if rng then rng:NextNumber() else math.random()) * total
	for _, entry in ipairs(entries) do
		roll -= entry.weight or 1
		if roll <= 0 then
			return entry
		end
	end
	return entries[#entries]
end

function Util.excludeParams(list: { Instance }, ignoreWater: boolean?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.IgnoreWater = if ignoreWater == nil then true else ignoreWater
	return params
end

return Util
