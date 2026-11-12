--[[
	Net - access to the RemoteEvents in ReplicatedStorage.Remotes, plus a server-side rate limiter.
	All remotes are created at edit time. If you need a new one, add it to the Remotes folder in Studio,
	to Net.Names below, and to docs/GameDesign.md.
	Net.event(name) -> RemoteEvent
	Net.rateLimit(player, key, perSecond, burst?) -> boolean   (server)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Net = {}

Net.Names = {
	-- server -> client
	"Announce", "KillFeed", "YouDied", "Sfx", "InventoryUpdate", "ProjectileFired", "ProjectileImpact",
	"HitConfirm", "DamageTaken", "CombatAction", "RoundSummary",
	-- client -> server
	"EquipSlot", "DropSlot", "UseStart", "UseFinish", "UseCancel", "Drink", "MeleeSwing", "RangedRelease",
	"SetStance", "SaveSettings", "SpectateTarget",
}

local folder = ReplicatedStorage:WaitForChild("Remotes")
local cache: { [string]: RemoteEvent } = {}

function Net.event(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
			warn("[Net] RemoteEvent '" .. name .. "' was missing and was created at runtime. Add it to the Remotes folder.")
		else
			remote = folder:WaitForChild(name, 15)
			if not remote then
				error("[Net] RemoteEvent '" .. name .. "' not found")
			end
		end
	end
	cache[name] = remote :: RemoteEvent
	return remote :: RemoteEvent
end

-- Token-bucket rate limit (server). Returns true if the call is allowed.
-- Example: if not Net.rateLimit(player, "MeleeSwing", 6) then return end
local buckets: { [Player]: { [string]: { tokens: number, t: number } } } = {}

function Net.rateLimit(player: Player, key: string, perSecond: number, burst: number?): boolean
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local capacity = burst or math.max(1, perSecond)
	local bucket = perPlayer[key]
	if not bucket then
		bucket = { tokens = capacity, t = now }
		perPlayer[key] = bucket
	end
	bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.t) * perSecond)
	bucket.t = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return Net
