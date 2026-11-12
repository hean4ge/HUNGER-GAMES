--[[
	MovementService - server side of movement. No public API (docs/GameDesign.md section 8).

	SetStance(stance)  validated ("Stand" | "Crouch" | "Slide" | "Climb") and rate-limited, then mirrored to the
	                   character attribute Stance (every client's CharacterVisuals poses other players from it).
	Fall damage        watches each character's HumanoidRootPart vertical velocity on Heartbeat. On landing, the
	                   fastest fall speed of that descent gives the equivalent drop height under the contenders' air
	                   gravity (Config.Movement.AirGravity * FallGravityScale; MovementController applies it on the
	                   client): h = v^2 / (2 g). Damage rises from 0 at FallDamage.MinHeight to MaxHealth at
	                   FallDamage.LethalHeight (curve exponent FallDamage.Exponent), through
	                   Services.PlayerService.damage(player, amount, { cause = "Fall" }). Skipped when landing in
	                   water, when the player is not InArena, while frozen, or when GameState.Phase ~= "Active".
	Sanity             warns (no punishment yet) when a player's horizontal speed stays above Slide.MaxSpeed + 10 for
	                   more than a second.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local MovementService = {}

local MOVE = Config.Movement or {}
local FALL = MOVE.FallDamage or {}
local SURVIVAL = Config.Survival or {}

local function num(tbl: any, key: string, default: number): number
	local v = if type(tbl) == "table" then tbl[key] else nil
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local FALL_GRAVITY = math.max(1, num(MOVE, "AirGravity", 125) * num(MOVE, "FallGravityScale", 1.08))
local MIN_HEIGHT = num(FALL, "MinHeight", 13)
local LETHAL_HEIGHT = math.max(MIN_HEIGHT + 1, num(FALL, "LethalHeight", 58))
local EXPONENT = math.clamp(num(FALL, "Exponent", 1.15), 0.5, 3)
local MAX_HEALTH = num(SURVIVAL, "MaxHealth", 100)
-- the slowest a real fall reaches the damage threshold (falls start with full gravity for a moment)
local MIN_IMPACT = math.sqrt(2 * FALL_GRAVITY * MIN_HEIGHT)
local SANITY_SPEED = num(MOVE.Slide, "MaxSpeed", 28) + 10
local SANITY_TIME = 1
local WARN_INTERVAL = 10

local ALLOWED_STANCES = { Stand = true, Crouch = true, Slide = true, Climb = true }

local Services = nil
local tracked: { [Model]: any } = {}

local function phase(): string
	local gameState = ReplicatedStorage:FindFirstChild("GameState")
	local value = gameState and gameState:GetAttribute("Phase")
	return if type(value) == "string" then value else "Lobby"
end

-- Damage for a landing at `impact` studs/s (the equivalent drop height under the contenders' fall gravity).
local function fallDamage(impact: number): (number, number)
	local h = impact * impact / (2 * FALL_GRAVITY)
	if h <= MIN_HEIGHT then
		return 0, h
	end
	local k = math.clamp((h - MIN_HEIGHT) / (LETHAL_HEIGHT - MIN_HEIGHT), 0, 2)
	return MAX_HEALTH * k ^ EXPONENT, h
end

-- Terrain water around the landing spot (the impact is cushioned by water).
local function inWater(position: Vector3): boolean
	local region = Region3.new(position - Vector3.new(3, 4, 3), position + Vector3.new(3, 2, 3)):ExpandToGrid(4)
	local ok, materials = pcall(function()
		return (workspace.Terrain:ReadVoxels(region, 4))
	end)
	if not ok or type(materials) ~= "table" then
		return false
	end
	for _, plane in ipairs(materials) do
		for _, row in ipairs(plane) do
			for _, material in ipairs(row) do
				if material == Enum.Material.Water then
					return true
				end
			end
		end
	end
	return false
end

local function handleLanding(st, impact: number)
	local player = st.player
	if player.Parent ~= Players or player:GetAttribute("InArena") ~= true or player:GetAttribute("Frozen") == true then
		return
	end
	if phase() ~= "Active" then
		return
	end
	local playerService = Services and Services.PlayerService
	if not playerService or type(playerService.damage) ~= "function" then
		return
	end
	if type(playerService.isAlive) == "function" and not playerService.isAlive(player) then
		return
	end
	local position = st.root.Position
	if st.humanoid:GetState() == Enum.HumanoidStateType.Swimming or inWater(position) then
		return
	end
	local damage = fallDamage(impact)
	if damage > 0.5 then
		playerService.damage(player, damage, { cause = "Fall", position = position })
	end
end

local function untrack(character: Model)
	tracked[character] = nil
end

local function track(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") then
		return
	end
	if player.Character ~= character or not character.Parent then
		return
	end
	character:SetAttribute("Stance", "Stand")
	tracked[character] = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		falling = false,
		peak = 0,
		fallStartAt = 0,
		fastFor = 0,
		lastWarnAt = -math.huge,
	}
	-- these connections belong to the character's own instances and die with it
	humanoid.Died:Connect(function()
		untrack(character)
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			untrack(character)
		end
	end)
end

local function onHeartbeat(dt: number)
	local now = os.clock()
	for _, st in pairs(tracked) do
		local root = st.root
		if not root.Parent or st.humanoid.Health <= 0 then
			continue
		end
		if root.Anchored then
			st.falling, st.peak = false, 0
			st.fastFor = 0
			continue
		end
		local v = root.AssemblyLinearVelocity
		local vy = v.Y
		if vy < -8 then
			if not st.falling then
				st.falling = true
				st.fallStartAt = now
				st.peak = 0
			end
			if -vy > st.peak then
				st.peak = -vy
			end
		elseif st.falling and vy > -3 then
			-- the descent ended: landed (or caught by water)
			local impact = st.peak
			local duration = now - st.fallStartAt
			st.falling, st.peak = false, 0
			-- a real fall needs time to reach its speed; ignore one-frame velocity spikes (teleports, lag).
			-- (bounded with the strongest gravity a fall can have, so real falls are never rejected)
			local minDuration = 0.6 * impact / (math.max(workspace.Gravity, FALL_GRAVITY) * 1.1)
			if impact > MIN_IMPACT and duration >= minDuration then
				handleLanding(st, impact)
			end
		end

		local horizontal = Vector3.new(v.X, 0, v.Z).Magnitude
		if horizontal > SANITY_SPEED then
			st.fastFor += dt
			if st.fastFor > SANITY_TIME and now - st.lastWarnAt > WARN_INTERVAL then
				st.lastWarnAt = now
				warn(string.format("[MovementService] %s moved at %.0f studs/s for %.1f s (limit %.0f)",
					st.player.Name, horizontal, st.fastFor, SANITY_SPEED))
			end
		else
			st.fastFor = 0
		end
	end
end

local function onSetStance(player: Player, stance: any)
	if type(stance) ~= "string" or not ALLOWED_STANCES[stance] then
		return
	end
	if not Net.rateLimit(player, "SetStance", 10, 14) then
		return
	end
	local character = player.Character
	local st = character and tracked[character]
	if not st or st.humanoid.Health <= 0 then
		return
	end
	if character:GetAttribute("Stance") ~= stance then
		character:SetAttribute("Stance", stance)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		track(player, character)
	end)
	if player.Character then
		task.spawn(track, player, player.Character)
	end
end

-- exposed for tests only (not part of the service contract)
MovementService._fallDamage = fallDamage

function MovementService.Init(registry)
	Services = registry
end

function MovementService.Start()
	Net.event("SetStance").OnServerEvent:Connect(onSetStance)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			untrack(player.Character)
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	RunService.Heartbeat:Connect(onHeartbeat)
end

return MovementService
