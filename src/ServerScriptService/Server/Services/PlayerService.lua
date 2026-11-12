--[[
	PlayerService - characters, life and death, survival meters and spectator streaming focus.

	Public API (docs/GameDesign.md section 8):
	  PlayerService.isAlive(player) -> boolean                 alive contender this round
	  PlayerService.damage(player, amount, info) -> killed
	      info = { attacker: Player?, cause: "Combat"|"Fall"|"Border"|"Starvation"|"Dehydration"|"Other",
	               weaponId: string?, position: Vector3?, headshot: boolean? }
	      Applies `amount` as given (armor is applied by CombatService) and only to alive contenders during Active.
	      Records the attacker for kill credit, fires DamageTaken to the victim and runs death handling exactly once.
	  PlayerService.heal(player, amount) -> number healed
	  PlayerService.addHunger(player, delta) -> new value   (clamped 0..100)
	  PlayerService.addThirst(player, delta) -> new value   (clamped 0..100)
	  PlayerService.getAlivePlayers() -> { Player }
	  PlayerService.died: Signal(victim: Player, killer: Player?, cause: string)
	      Fires once per contender elimination during Countdown/Active, including contenders who leave
	      (cause "Left": the victim is already leaving, so don't FireClient to it). Lobby deaths don't fire it.
	Used by RoundService:
	  PlayerService.loadIntoLobby(player)                      (re)load the character into the lobby, reset life attributes
	  PlayerService.getLobbyPlayers() -> { Player }            waiting in the lobby with a live character
	  PlayerService.getWaitingCount() -> number                players who aren't in the arena
	  PlayerService.prepareContender(player, ground: CFrame) -> boolean   frozen on a plinth (feet CFrame facing the Spire)
	  PlayerService.setFrozen(player, frozen)
	  PlayerService.clearSpectate(player)
	Remote: SpectateTarget(target: Player?) points the requester's ReplicationFocus at an alive contender.
YouDied { placement, total, killer, killerUserId?, cause, weapon, weaponName, headshot, phase ("Active" | "Countdown"),
	practice } goes to the victim, who also
	gets the attribute KilledBy (the killer's UserId, or 0). Practice rounds add no TotalKills.
Attribute Regen (QW5, every survival tick, alive contenders in Active): why health is or isn't coming back -
	"ok" healing; "hunger" / "thirst" / "both": hurt but that meter is at Config.Survival.RegenMinStat or below;
	"zero": a meter is empty and you are losing StarveDamagePerSecond per empty meter (causes "Starvation" /
	"Dehydration"); "" nothing to say (full health, the RegenDelayAfterDamage window after a hit, or not in a round).

	Characters: Players.CharacterAutoLoads is off. Every load goes through loadIntoLobby: the avatar is loaded from a copy of
	the player's HumanoidDescription exactly as they have it (body scales and proportions included - movement, camera and
	body IK measure each rig), forced to R15 where possible, and the default Health regen script is removed (survival rules
	handle regeneration).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Util = require(Shared:WaitForChild("Util"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local Survival = Config.Survival
local RoundCfg = Config.Round

local MAX_STAT = 100
local MAX_HEALTH = Survival.MaxHealth or 100
local VOID_HEIGHT = Survival.VoidHeight or (ArenaLayout.WaterLevel - 90) -- contenders below this fell out of the world
local LOBBY_FALL_DEPTH = RoundCfg.LobbyFallDepth or 80 -- lobby players this far below the lobby surface are put back
local TICK = 1
local NAMETAG_ARENA = Enum.HumanoidDisplayDistanceType.None
local NAMETAG_LOBBY = Enum.HumanoidDisplayDistanceType.Viewer
local LOBBY_FACING = Vector3.new(-1, 0, 0) -- the lobby island sits east of the arena; face toward it

local PlayerService = {}
PlayerService.died = Signal.new()

local Services = nil
local states = {} -- [Player] = per-player state (see onPlayerAdded)
local spectateTargets = {} -- [requester] = target Player
local warned = {}
local fallbackPad = nil
local spawnCache = { list = {}, at = -math.huge }

-- Helpers ----------------------------------------------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[PlayerService] " .. message)
end

local function call(serviceName: string, method: string, ...: any): any
	local service = Services and Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		warnOnce(serviceName .. "." .. method, serviceName .. "." .. method .. " is not available")
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("[PlayerService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function phaseNow(): string
	return GameState:GetAttribute("Phase") or "Lobby"
end

local function getCharacterParts(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and not root:IsA("BasePart") then
		root = nil
	end
	return character, humanoid, root :: BasePart?
end

-- Height of the HumanoidRootPart centre above the feet.
local function rootOffset(humanoid: Humanoid?, root: BasePart?): number
	if humanoid and root and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

local function roundTo(value: number, decimals: number): number
	local m = 10 ^ decimals
	return math.floor(value * m + 0.5) / m
end

local function stillCurrent(player: Player, st, token: number): boolean
	return states[player] == st and st.loadToken == token and player.Parent == Players
end

local function characterList(): { Instance }
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- Lobby spawn points ---------------------------------------------------------------------------------------------

local function lobbySpawns(): { SpawnLocation }
	if os.clock() - spawnCache.at < 10 then
		return spawnCache.list
	end
	local list = {}
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("SpawnLocation") and d.Enabled then
				table.insert(list, d)
			end
		end
	end
	spawnCache.list = list
	spawnCache.at = os.clock()
	return list
end

-- Ground at the lobby centre when no lobby SpawnLocations exist. Builds a temporary pad if there's nothing there at all.
local function fallbackLobbyGround(offset: Vector3): Vector3
	local center = ArenaLayout.LobbyPosition
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterList()
	local down = Vector3.new(0, -240, 0)
	local hit = workspace:Raycast(center + offset + Vector3.new(0, 80, 0), down, params)
		or workspace:Raycast(center + Vector3.new(0, 80, 0), down, params)
	if hit then
		return hit.Position
	end
	if not (fallbackPad and fallbackPad.Parent) then
		warnOnce("NoLobby", "No lobby found (SpawnLocations in workspace.Lobby, or ground at ArenaLayout.LobbyPosition). Created a temporary spawn pad.")
		local pad = Instance.new("Part")
		pad.Name = "FallbackLobbyPad"
		pad.Anchored = true
		pad.Size = Vector3.new(80, 2, 80)
		pad.Material = Enum.Material.Slate
		pad.Color = Color3.fromRGB(86, 88, 92)
		pad.CFrame = CFrame.new(center - Vector3.new(0, 1, 0))
		pad.Parent = workspace
		fallbackPad = pad
	end
	return center + Vector3.new(offset.X, 0, offset.Z)
end

-- Feet CFrame for a lobby spawn, plus the SpawnLocation used (if any).
local function pickLobbySpot(): (CFrame, SpawnLocation?)
	local valid = {}
	for _, s in ipairs(lobbySpawns()) do
		if s.Parent and s.Enabled then
			table.insert(valid, s)
		end
	end
	if #valid > 0 then
		local s = valid[math.random(1, #valid)]
		local halfX = math.max(0, s.Size.X / 2 - 1.5)
		local halfZ = math.max(0, s.Size.Z / 2 - 1.5)
		local point = s.CFrame:PointToWorldSpace(
			Vector3.new((math.random() * 2 - 1) * halfX, s.Size.Y / 2, (math.random() * 2 - 1) * halfZ)
		)
		local look = s.CFrame.LookVector
		look = Vector3.new(look.X, 0, look.Z)
		if look.Magnitude < 0.05 then
			look = LOBBY_FACING
		end
		return CFrame.lookAt(point, point + look.Unit), s
	end
	local offset = Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
	local ground = fallbackLobbyGround(offset)
	return CFrame.lookAt(ground, ground + LOBBY_FACING), nil
end

local function placeCharacter(player: Player, ground: CFrame): boolean
	local character, humanoid, root = getCharacterParts(player)
	if not character or not root then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(ground + Vector3.new(0, rootOffset(humanoid, root) + 0.05, 0))
	return true
end

local function unseat(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
	end
end

-- Avatars ----------------------------------------------------------------------------------------------------------

-- The player's avatar description as they have it (cached per session; retried at most once a minute).
local function fetchDescription(player: Player, st): HumanoidDescription?
	local deadline = os.clock() + 10
	while st.descriptionFetching and os.clock() < deadline do
		task.wait(0.05)
	end
	if st.description then
		return st.description
	end
	if player.UserId <= 0 or os.clock() < st.descriptionRetryAt then
		return nil
	end
	st.descriptionFetching = true
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)
	st.descriptionFetching = false
	if ok and typeof(desc) == "Instance" and desc:IsA("HumanoidDescription") then
		st.description = desc
		return desc
	end
	st.descriptionRetryAt = os.clock() + 60
	return nil
end

-- The game loaded an R6 rig: rebuild the same avatar as R15 and hand it to the player.
local function rebuildAsR15(player: Player, oldCharacter: Model, desc: HumanoidDescription): boolean
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not model:FindFirstChild("Animate") or not model:FindFirstChildOfClass("Humanoid") then
		model:Destroy()
		return false
	end
	if not model.PrimaryPart and root:IsA("BasePart") then
		model.PrimaryPart = root
	end
	model.Name = player.Name
	local starterScripts = StarterPlayer:FindFirstChildOfClass("StarterCharacterScripts")
	if starterScripts then
		for _, child in ipairs(starterScripts:GetChildren()) do
			if child.Name ~= "Health" then
				local existing = model:FindFirstChild(child.Name)
				if existing then
					existing:Destroy()
				end
				child:Clone().Parent = model
			end
		end
	end
	if player.Parent ~= Players or player.Character ~= oldCharacter then
		model:Destroy()
		return false
	end
	model:PivotTo(oldCharacter:GetPivot())
	player.Character = model
	model.Parent = workspace
	oldCharacter:Destroy()
	return true
end

local function resetLifeAttributes(player: Player)
	player:SetAttribute("Alive", false)
	player:SetAttribute("InArena", false)
	player:SetAttribute("Frozen", false)
	player:SetAttribute("Hunger", MAX_STAT)
	player:SetAttribute("Thirst", MAX_STAT)
	player:SetAttribute("Armor", "")
	player:SetAttribute("Regen", "")
end

-- QW5: why health is or isn't coming back (see the header)
local function setRegen(player: Player, value: string)
	if player:GetAttribute("Regen") ~= value then
		player:SetAttribute("Regen", value)
	end
end

-- Loads a fresh character into the lobby. Runs in its own thread; `token` cancels stale loads.
local function doLoad(player: Player, st, token: number)
	local waited = 0
	while st.loading and waited < 20 do
		task.wait(0.1)
		waited += 0.1
	end
	if not stillCurrent(player, st, token) then
		return
	end
	st.loading = true
	local ground, spawnLocation = pickLobbySpot()
	-- stream the lobby in while the avatar description loads
	local streamed = false
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, ground.Position, 2)
		streamed = true
	end)
	local desc = fetchDescription(player, st)
	local streamDeadline = os.clock() + 2.5
	while not streamed and os.clock() < streamDeadline do
		task.wait(0.05)
	end
	if not stillCurrent(player, st, token) then
		st.loading = false
		return
	end
	if spawnLocation then
		player.RespawnLocation = spawnLocation
	end
	local ok, err = pcall(function()
		if desc then
			player:LoadCharacterWithHumanoidDescriptionAsync(desc:Clone())
		else
			player:LoadCharacterAsync()
		end
	end)
	if not ok and desc and player.Parent == Players then
		warn(string.format("[PlayerService] Couldn't load %s's avatar (%s); using the default appearance", player.Name, tostring(err)))
		desc = nil
		ok, err = pcall(function()
			player:LoadCharacterAsync()
		end)
	end
	st.loading = false
	if not ok then
		if player.Parent == Players then
			warn(string.format("[PlayerService] Character load failed for %s: %s (will retry)", player.Name, tostring(err)))
		end
		return
	end
	if not stillCurrent(player, st, token) then
		return
	end
	local character, humanoid = getCharacterParts(player)
	if not character or not humanoid then
		return
	end
	st.loading = true
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 and stillCurrent(player, st, token) then
		local source = desc
		if not source then
			local okApplied, applied = pcall(function()
				return humanoid:GetAppliedDescription()
			end)
			if okApplied and applied then
				source = applied
			end
		end
		local rebuilt = source ~= nil and rebuildAsR15(player, character, source:Clone())
		if not rebuilt then
			warnOnce("R6", "Characters load as R6 and couldn't be rebuilt as R15. Set Game Settings > Avatar > R15.")
		end
	end
	st.loading = false
	if stillCurrent(player, st, token) then
		placeCharacter(player, ground)
	end
end

-- Spectating -------------------------------------------------------------------------------------------------------

function PlayerService.clearSpectate(player: Player)
	spectateTargets[player] = nil
	if player.Parent == Players then
		player.ReplicationFocus = nil
	end
end

local function releaseSpectatorsOf(target: Player)
	for requester, current in pairs(spectateTargets) do
		if current == target then
			spectateTargets[requester] = nil
			if requester.Parent == Players then
				requester.ReplicationFocus = nil
			end
		end
	end
end

-- Lobby loading ----------------------------------------------------------------------------------------------------

function PlayerService.loadIntoLobby(player: Player)
	local st = states[player]
	if not st or player.Parent ~= Players then
		return
	end
	st.loadToken += 1
	st.respawnPending = false
	st.pendingPlacement = nil
	st.missingSince = nil
	resetLifeAttributes(player)
	PlayerService.clearSpectate(player)
	task.spawn(doLoad, player, st, st.loadToken)
end

local function scheduleRespawn(player: Player, st)
	st.respawnPending = true
	local token = st.loadToken
	task.delay(math.max(0, RoundCfg.RespawnDelay or 4), function()
		if stillCurrent(player, st, token) and st.respawnPending then
			PlayerService.loadIntoLobby(player)
		end
	end)
end

-- Death ------------------------------------------------------------------------------------------------------------

local function weaponLabel(weaponId: string?): string?
	local def = weaponId and ItemDefs.get(weaponId)
	return if def then def.name else nil
end

-- Runs exactly once per life (callers set st.deathHandled first).
local function handleDeath(victim: Player, info, position: Vector3?, leaving: boolean)
	local st = states[victim]
	local phase = phaseNow()
	if victim:GetAttribute("Alive") == true and (phase == "Active" or phase == "Countdown") then
		local others = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= victim and p:GetAttribute("Alive") == true then
				others += 1
			end
		end
		local placement = others + 1
		local total = math.max(placement, tonumber(GameState:GetAttribute("StartedCount")) or placement)
		local cause = info.cause or "Other"
		local weaponId = info.weaponId
		local killer = info.attacker
		if killer and (killer == victim or killer.Parent ~= Players) then
			killer = nil
		end
		if not killer and cause ~= "Combat" and st and st.lastAttacker and st.lastAttacker ~= victim
			and st.lastAttacker.Parent == Players
			and os.clock() - st.lastAttackerTime <= (Survival.KillCreditWindow or 15) then
			killer = st.lastAttacker -- environmental death (or leaving) shortly after being attacked
		end

		victim:SetAttribute("Placement", placement)
		victim:SetAttribute("Alive", false)
		victim:SetAttribute("Frozen", false)
		victim:SetAttribute("Regen", "")
		victim:SetAttribute("KilledBy", if killer then killer.UserId else 0) -- SpectateController opens on the killer (QW4)
		if killer then
			killer:SetAttribute("Kills", (tonumber(killer:GetAttribute("Kills")) or 0) + 1)
			if GameState:GetAttribute("Practice") ~= true then -- practice rounds never add Kills
				call("DataService", "increment", killer, "TotalKills", 1)
			end
		end

		local killerName = if killer then killer.DisplayName else nil
		local weaponName = weaponLabel(weaponId)
		Sfx.play("Cannon")
		Net.event("KillFeed"):FireAllClients({
			killer = killerName,
			victim = victim.DisplayName,
			weapon = weaponId,
			weaponName = weaponName,
			cause = cause,
			text = if leaving then "left the arena" else nil,
		})
		if not leaving then
			Net.event("YouDied"):FireClient(victim, {
				placement = placement,
				total = total,
				killer = killerName,
				killerUserId = if killer then killer.UserId else nil,
				cause = cause,
				weapon = weaponId,
				weaponName = weaponName,
				headshot = info.headshot == true,
				-- QW4: a death before the horn (a reset on the plate) gets its own card, and practice deaths no "#1 OF 1"
				phase = phase,
				practice = GameState:GetAttribute("Practice") == true,
			})
		end
		if position then
			call("InventoryService", "dropAll", victim, position)
		end
		releaseSpectatorsOf(victim)
		PlayerService.died:Fire(victim, killer, cause)
	else
		-- Lobby death (reset, fell off the island) or after the round was decided: just respawn.
		victim:SetAttribute("Alive", false)
		victim:SetAttribute("Frozen", false)
	end
	if st and not leaving then
		scheduleRespawn(victim, st)
	end
end

local function sanitizeCause(cause: any): string
	if type(cause) == "string" and #cause > 0 and #cause <= 32 then
		return cause
	end
	return "Other"
end

-- Public API ---------------------------------------------------------------------------------------------------------

function PlayerService.isAlive(player: Player): boolean
	if not isPlayer(player) or player:GetAttribute("Alive") ~= true then
		return false
	end
	local st = states[player]
	if not st or st.deathHandled then
		return false
	end
	local _, humanoid = getCharacterParts(player)
	return humanoid ~= nil and humanoid.Health > 0
end

function PlayerService.getAlivePlayers(): { Player }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if PlayerService.isAlive(player) then
			table.insert(list, player)
		end
	end
	return list
end

function PlayerService.damage(player: Player, amount: number, info: { [string]: any }?): boolean
	if not isPlayer(player) or not Util.isFiniteNumber(amount) or amount <= 0 then
		return false
	end
	local st = states[player]
	if not st or st.deathHandled or player:GetAttribute("Alive") ~= true or phaseNow() ~= "Active" then
		return false
	end
	local _, humanoid, root = getCharacterParts(player)
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local data = if type(info) == "table" then info else {}
	local cause = sanitizeCause(data.cause)
	local attacker = if isPlayer(data.attacker) and data.attacker ~= player then data.attacker else nil
	local weaponId = if type(data.weaponId) == "string" then data.weaponId else nil

	local now = os.clock()
	st.lastDamageTime = now
	if attacker then
		st.lastAttacker = attacker
		st.lastAttackerTime = now
	end

	local fromPosition = nil
	if attacker then
		local _, _, attackerRoot = getCharacterParts(attacker)
		if attackerRoot then
			fromPosition = attackerRoot.Position
		end
	end
	-- only directional damage has a source position (falls and hunger pass the victim's own spot, or nothing)
	if not fromPosition and (cause == "Combat" or cause == "Border") and Util.isFiniteVector(data.position) then
		fromPosition = data.position
	end
	Net.event("DamageTaken"):FireClient(player, { amount = amount, fromPosition = fromPosition, cause = cause })

	local remaining = humanoid.Health - amount
	if remaining > 0 then
		humanoid.Health = remaining
		return false
	end
	st.deathHandled = true
	local position = if root then root.Position else nil
	if not position or position.Y < VOID_HEIGHT then
		position = st.lastSafePosition
	end
	humanoid.Health = 0
	handleDeath(player, { attacker = attacker, cause = cause, weaponId = weaponId, headshot = data.headshot == true }, position, false)
	return true
end

function PlayerService.heal(player: Player, amount: number): number
	if not isPlayer(player) or not Util.isFiniteNumber(amount) or amount <= 0 then
		return 0
	end
	local st = states[player]
	if not st or st.deathHandled then
		return 0
	end
	local _, humanoid = getCharacterParts(player)
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end
	local before = humanoid.Health
	local after = math.min(humanoid.MaxHealth, before + amount)
	humanoid.Health = after
	return after - before
end

local function addStat(player: Player, name: string, delta: number): number
	if not isPlayer(player) then
		return 0
	end
	local current = tonumber(player:GetAttribute(name)) or MAX_STAT
	if not Util.isFiniteNumber(delta) then
		return current
	end
	local value = roundTo(math.clamp(current + delta, 0, MAX_STAT), 3)
	player:SetAttribute(name, value)
	return value
end

function PlayerService.addHunger(player: Player, delta: number): number
	return addStat(player, "Hunger", delta)
end

function PlayerService.addThirst(player: Player, delta: number): number
	return addStat(player, "Thirst", delta)
end

-- Players waiting in the lobby with a live character (RoundService picks contenders from these).
function PlayerService.getLobbyPlayers(): { Player }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local st = states[player]
		if st and not st.loading and not st.respawnPending
			and player:GetAttribute("InArena") ~= true and player:GetAttribute("Alive") ~= true then
			local _, humanoid, root = getCharacterParts(player)
			if humanoid and root and humanoid.Health > 0 then
				table.insert(list, player)
			end
		end
	end
	return list
end

-- Players who aren't in the arena (GameState.LobbyCount).
function PlayerService.getWaitingCount(): number
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if states[player] and player:GetAttribute("InArena") ~= true and player:GetAttribute("Alive") ~= true then
			count += 1
		end
	end
	return count
end

-- Countdown: make a lobby player an alive contender, frozen on the given plinth spot (feet CFrame facing the Spire).
function PlayerService.prepareContender(player: Player, ground: CFrame): boolean
	local st = states[player]
	if not st or player.Parent ~= Players or st.loading then
		return false
	end
	local character, humanoid, root = getCharacterParts(player)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	st.loadToken += 1 -- cancels any pending lobby load
	st.respawnPending = false
	st.deathHandled = false
	st.lastAttacker = nil
	st.lastAttackerTime = -math.huge
	st.lastDamageTime = -math.huge
	st.lastTickPosition = nil
	st.lastSafePosition = ground.Position
	st.missingSince = nil
	PlayerService.clearSpectate(player)

	player:SetAttribute("Alive", true)
	player:SetAttribute("InArena", true)
	player:SetAttribute("Frozen", true)
	player:SetAttribute("Hunger", MAX_STAT)
	player:SetAttribute("Thirst", MAX_STAT)
	player:SetAttribute("Armor", "")
	player:SetAttribute("Kills", 0)
	player:SetAttribute("Placement", 0)
	player:SetAttribute("Regen", "")
	player:SetAttribute("KilledBy", nil)
	unseat(humanoid)
	humanoid.MaxHealth = MAX_HEALTH
	humanoid.Health = MAX_HEALTH
	humanoid.DisplayDistanceType = NAMETAG_ARENA
	root.Anchored = true -- fallback freeze (MovementController also locks input while Frozen)

	st.pendingPlacement = ground
	local token = st.loadToken
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, ground.Position, 4)
		if states[player] ~= st or st.loadToken ~= token or st.pendingPlacement ~= ground then
			return
		end
		st.pendingPlacement = nil
		placeCharacter(player, ground)
	end)
	return true
end

function PlayerService.setFrozen(player: Player, frozen: boolean)
	local st = states[player]
	if not st then
		return
	end
	if not frozen and st.pendingPlacement then
		-- streaming took longer than the countdown: place them now
		local ground = st.pendingPlacement
		st.pendingPlacement = nil
		placeCharacter(player, ground)
	end
	player:SetAttribute("Frozen", frozen == true)
	local _, _, root = getCharacterParts(player)
	if root then
		root.Anchored = frozen == true
		if not frozen then
			pcall(root.SetNetworkOwner, root, player)
		end
	end
end

-- Survival tick ------------------------------------------------------------------------------------------------------

local function contenderTick(player: Player, st, humanoid: Humanoid, root: BasePart, phase: string, dt: number)
	local position = root.Position
	if position.Y < VOID_HEIGHT then
		if phase == "Active" then
			PlayerService.damage(player, humanoid.Health + 1000, { cause = "Fall" })
		else
			humanoid.Health = 0 -- the Died handler respawns them
		end
		return
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		st.lastSafePosition = position
	end
	local last = st.lastTickPosition
	st.lastTickPosition = position
	if phase ~= "Active" then
		setRegen(player, "")
		return
	end

	local speed = 0
	if last then
		local moved = Util.flat(position - last).Magnitude
		if moved < 90 then -- ignore teleports
			speed = moved / dt
		end
	end
	local multiplier = if speed > Survival.SprintSpeedThreshold then Survival.SprintDrainMultiplier else 1
	local hunger = math.clamp((tonumber(player:GetAttribute("Hunger")) or MAX_STAT) - Survival.HungerDrainPerSecond * multiplier * dt, 0, MAX_STAT)
	local thirst = math.clamp((tonumber(player:GetAttribute("Thirst")) or MAX_STAT) - Survival.ThirstDrainPerSecond * multiplier * dt, 0, MAX_STAT)
	player:SetAttribute("Hunger", roundTo(hunger, 3))
	player:SetAttribute("Thirst", roundTo(thirst, 3))

	-- QW5: say why health is or isn't coming back (the HUD shows it); "zero" before the damage so it is never late
	local hungry, thirsty = hunger <= Survival.RegenMinStat, thirst <= Survival.RegenMinStat
	local recentlyHit = os.clock() - st.lastDamageTime < Survival.RegenDelayAfterDamage
	if hunger <= 0 or thirst <= 0 then
		setRegen(player, "zero")
	elseif humanoid.Health >= humanoid.MaxHealth - 0.01 then
		setRegen(player, "")
	elseif hungry or thirsty then
		setRegen(player, if hungry and thirsty then "both" elseif hungry then "hunger" else "thirst")
	else
		setRegen(player, if recentlyHit then "" else "ok")
	end

	if hunger <= 0 and PlayerService.damage(player, Survival.StarveDamagePerSecond * dt, { cause = "Starvation" }) then
		return
	end
	if thirst <= 0 and PlayerService.damage(player, Survival.StarveDamagePerSecond * dt, { cause = "Dehydration" }) then
		return
	end
	if not hungry and not thirsty and not recentlyHit
		and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
		PlayerService.heal(player, Survival.RegenPerSecond * dt)
	end
end

local function lobbyTick(player: Player, root: BasePart)
	if root.Position.Y < ArenaLayout.LobbyPosition.Y - LOBBY_FALL_DEPTH then
		placeCharacter(player, (pickLobbySpot()))
	end
end

-- Anti-softlock: a player with no live character and nothing scheduled gets handled and reloaded.
local function watchdog(player: Player, st)
	if st.loading or st.respawnPending then
		st.missingSince = nil
		return
	end
	local _, humanoid, root = getCharacterParts(player)
	if humanoid and root and humanoid.Health > 0 then
		st.missingSince = nil
		return
	end
	st.missingSince = st.missingSince or os.clock()
	if os.clock() - st.missingSince < 2.5 then
		return
	end
	st.missingSince = nil
	if not st.deathHandled and (player:GetAttribute("Alive") == true or (humanoid ~= nil and humanoid.Health <= 0)) then
		st.deathHandled = true
		handleDeath(player, { cause = "Other" }, st.lastSafePosition, false) -- schedules the respawn
	else
		PlayerService.loadIntoLobby(player)
	end
end

local function survivalTick(dt: number)
	local phase = phaseNow()
	for _, player in ipairs(Players:GetPlayers()) do
		local st = states[player]
		if st then
			local _, humanoid, root = getCharacterParts(player)
			if humanoid and root and humanoid.Health > 0 then
				if player:GetAttribute("Alive") == true and not st.deathHandled then
					contenderTick(player, st, humanoid, root, phase, dt)
				elseif not st.loading and player:GetAttribute("InArena") ~= true then
					lobbyTick(player, root)
				end
			end
			watchdog(player, st)
		end
	end
end

-- Player and character lifecycle ---------------------------------------------------------------------------------

local function updateNametag(player: Player)
	local _, humanoid = getCharacterParts(player)
	if humanoid then
		humanoid.DisplayDistanceType = if player:GetAttribute("InArena") == true then NAMETAG_ARENA else NAMETAG_LOBBY
	end
end

-- The default character "Health" script regenerates 1% a second; survival rules replace it.
local function removeDefaultHealth(child: Instance)
	if child.Name == "Health" and child:IsA("Script") then
		task.defer(function()
			if child.Parent then
				child:Destroy()
			end
		end)
	end
end

local function onHumanoidDied(player: Player, character: Model)
	local st = states[player]
	if not st or st.deathHandled or player.Character ~= character then
		return
	end
	st.deathHandled = true
	local root = character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else nil
	local cause = "Other"
	if not position or position.Y < VOID_HEIGHT then
		cause = "Fall"
		position = st.lastSafePosition
	end
	handleDeath(player, { cause = cause }, position, false)
end

local function onCharacterAdded(player: Player, character: Model)
	local st = states[player]
	if not st then
		return
	end
	st.deathHandled = false
	st.lastTickPosition = nil
	st.missingSince = nil
	for _, connection in ipairs(st.charConnections) do
		connection:Disconnect()
	end
	table.clear(st.charConnections)
	PlayerService.clearSpectate(player)

	for _, child in ipairs(character:GetChildren()) do
		removeDefaultHealth(child)
	end
	table.insert(st.charConnections, character.ChildAdded:Connect(removeDefaultHealth))

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		local found = character:WaitForChild("Humanoid", 10)
		humanoid = if found and found:IsA("Humanoid") then found else nil
	end
	if not humanoid or player.Character ~= character then
		return
	end
	humanoid.MaxHealth = MAX_HEALTH
	humanoid.Health = MAX_HEALTH
	humanoid.DisplayDistanceType = if player:GetAttribute("InArena") == true then NAMETAG_ARENA else NAMETAG_LOBBY
	table.insert(st.charConnections, humanoid.Died:Connect(function()
		onHumanoidDied(player, character)
	end))
end

-- An alive contender losing their character without dying (removed by something else) is an elimination,
-- unless they're leaving the game (PlayerRemoving handles that as "Left").
local function onCharacterRemoving(player: Player, character: Model)
	local st = states[player]
	if not st or st.deathHandled or player:GetAttribute("Alive") ~= true then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") and root.Position.Y >= VOID_HEIGHT then root.Position else st.lastSafePosition
	task.delay(0.25, function()
		if states[player] ~= st or player.Parent ~= Players or player:GetAttribute("Alive") ~= true then
			return
		end
		if player.Character == character and character.Parent then
			return
		end
		st.deathHandled = true
		handleDeath(player, { cause = "Other" }, position, false)
	end)
end

local function onPlayerAdded(player: Player)
	if states[player] or player.Parent ~= Players then
		return
	end
	local st = {
		loadToken = 0,
		loading = false,
		respawnPending = false,
		deathHandled = false,
		lastAttacker = nil,
		lastAttackerTime = -math.huge,
		lastDamageTime = -math.huge,
		lastSafePosition = nil,
		lastTickPosition = nil,
		pendingPlacement = nil,
		missingSince = nil,
		description = nil,
		descriptionFetching = false,
		descriptionRetryAt = 0,
		charConnections = {},
		connections = {},
	}
	states[player] = st
	player:SetAttribute("Alive", false)
	player:SetAttribute("InArena", false)
	player:SetAttribute("Frozen", false)
	player:SetAttribute("Hunger", MAX_STAT)
	player:SetAttribute("Thirst", MAX_STAT)
	player:SetAttribute("Armor", "")
	player:SetAttribute("Kills", 0)
	player:SetAttribute("Placement", 0)

	table.insert(st.connections, player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end))
	table.insert(st.connections, player.CharacterRemoving:Connect(function(character)
		onCharacterRemoving(player, character)
	end))
	table.insert(st.connections, player:GetAttributeChangedSignal("InArena"):Connect(function()
		updateNametag(player)
	end))
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	PlayerService.loadIntoLobby(player)
end

local function onPlayerRemoving(player: Player)
	local st = states[player]
	if not st then
		return
	end
	if player:GetAttribute("Alive") == true and not st.deathHandled then
		st.deathHandled = true
		local _, _, root = getCharacterParts(player)
		local position = if root and root.Position.Y >= VOID_HEIGHT then root.Position else st.lastSafePosition
		handleDeath(player, { cause = "Left" }, position, true)
	end
	spectateTargets[player] = nil
	releaseSpectatorsOf(player)
	for _, connection in ipairs(st.charConnections) do
		connection:Disconnect()
	end
	for _, connection in ipairs(st.connections) do
		connection:Disconnect()
	end
	if st.description then
		st.description:Destroy()
	end
	states[player] = nil
end

local function onSpectateTarget(player: Player, target: any)
	if not states[player] or not Net.rateLimit(player, "SpectateTarget", 5, 10) then
		return
	end
	if PlayerService.isAlive(player) then
		PlayerService.clearSpectate(player)
		return
	end
	if isPlayer(target) and target ~= player and target.Parent == Players and PlayerService.isAlive(target) then
		local _, _, root = getCharacterParts(target)
		if root then
			spectateTargets[player] = target
			player.ReplicationFocus = root
			return
		end
	end
	PlayerService.clearSpectate(player)
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function PlayerService.Init(registry)
	Services = registry
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Net.event("SpectateTarget").OnServerEvent:Connect(onSpectateTarget)
end

function PlayerService.Start()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = math.clamp(now - last, 0.05, 3)
		last = now
		local ok, err = pcall(survivalTick, dt)
		if not ok then
			warnOnce("tick:" .. tostring(err), "Survival tick error: " .. tostring(err))
		end
	end
end

return PlayerService
