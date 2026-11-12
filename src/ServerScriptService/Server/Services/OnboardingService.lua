--[[
	OnboardingService - Roblox's onboarding funnel for a player's first session (PlayabilityPlan QW15). Server only.

	Logs AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name) the first time each step happens for a player
	in this server (Roblox counts a player's first pass through the funnel). It only reaches the Creator Dashboard from
	published games; in Studio every step prints to the Output instead ("[Onboarding] Name: 3 OnPlate").
	  1 Joined            the player joined
	  2 Moved             the character moved within its first 10 s of control (time frozen on a launch plate doesn't
	                      count, so joining just before a Countdown still leaves the full window; catches "I can't move")
	  3 OnPlate           on a launch plate (picked for a round)
	  4 LeftPlate         more than 10 studs from the plate after the horn
	  5 OpenedCrate       opened a supply crate
	  6 EquippedItem      held an item
	  7 AteOrDrank        ate, drank (a bottle, or a sip from water)
	  8 SurvivedRollCall1 alive at the round's first Roll Call
	  9 FinishedRound     was in a round when it ended
	  10 OnPlateRound2    on a launch plate again after finishing a round

	Most steps come from signals that exist: RoundService.roundStarting / roundStarted / roundEnded,
	InventoryService.equippedChanged and .used, GameState.RollCall (ArenaService) and ProximityPromptService (a crate's
	OpenPrompt). Other code may also report a step itself:
	  OnboardingService.step(player, name | number)   e.g. step(player, "OpenedCrate"); repeats are ignored
	  OnboardingService.stepNumber(name) -> number?   OnboardingService.STEPS (in order)
	  OnboardingService.reached(player) -> { [number]: true }   steps this player has reached (for tests)
]]
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = ReplicatedStorage:WaitForChild("GameState")

local OnboardingService = {}

OnboardingService.STEPS = {
	"Joined", "Moved", "OnPlate", "LeftPlate", "OpenedCrate",
	"EquippedItem", "AteOrDrank", "SurvivedRollCall1", "FinishedRound", "OnPlateRound2",
}
local NUMBER: { [string]: number } = {}
for i, name in ipairs(OnboardingService.STEPS) do
	NUMBER[string.lower(name)] = i
end
-- loose spellings other scripts might use
local ALIASES: { [string]: string } = {
	join = "joined", move = "moved", plate = "onplate", crate = "openedcrate", crateopened = "openedcrate",
	opencrate = "openedcrate", equip = "equippeditem", equipped = "equippeditem", ate = "ateordrank",
	drank = "ateordrank", eat = "ateordrank", drink = "ateordrank", itemused = "ateordrank",
	rollcall = "survivedrollcall1", finished = "finishedround", roundended = "finishedround", round2 = "onplateround2",
}

-- step 2 counts a move within this many seconds of control (Studio: 30, because FastTimers + SoloTest give the lobby
-- only ~8 s before the plate, so a tester's first move usually comes after the horn)
local MOVE_WINDOW = if RunService:IsStudio() then 30 else 10
local MOVE_DISTANCE = 3
local LEAVE_DISTANCE = 10 -- step 4: studs from the plate after the horn
local IS_STUDIO = RunService:IsStudio()

local Services: { [string]: any } = {}
local reachedBy: { [Player]: { [number]: boolean } } = {}
local finishedBy: { [Player]: boolean } = {}
local warned: { [string]: boolean } = {}
local rollCallRound: any = nil -- the RoundId whose first Roll Call was counted

function OnboardingService.stepNumber(name: any): number?
	if type(name) == "number" then
		local n = math.floor(name)
		return if n >= 1 and n <= #OnboardingService.STEPS then n else nil
	end
	if type(name) ~= "string" then
		return nil
	end
	local key = string.lower((string.gsub(name, "[%s_%-]", "")))
	return NUMBER[key] or NUMBER[ALIASES[key] or ""]
end

function OnboardingService.step(player: Player, name: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return
	end
	local n = OnboardingService.stepNumber(name)
	if not n then
		local key = tostring(name)
		if not warned[key] then
			warned[key] = true
			warn("[OnboardingService] unknown step " .. key)
		end
		return
	end
	local reached = reachedBy[player]
	if not reached then
		reached = {}
		reachedBy[player] = reached
	end
	if reached[n] then
		return
	end
	reached[n] = true
	local stepName = OnboardingService.STEPS[n]
	if IS_STUDIO then
		print(string.format("[Onboarding] %s: %d %s", player.Name, n, stepName))
		return
	end
	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, n, stepName)
	end)
	if not ok and not warned.log then
		warned.log = true
		warn("[OnboardingService] LogOnboardingFunnelStepEvent failed: " .. tostring(err))
	end
end

function OnboardingService.reached(player: Player): { [number]: boolean }
	return table.clone(reachedBy[player] or {})
end

--------------------------------------------------------------------------------------------------------------------
-- Watchers
--------------------------------------------------------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function contenders(): { Player }
	local round = Services.RoundService
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local picked = false
		if round and type(round.isContender) == "function" then
			local ok, result = pcall(round.isContender, player)
			picked = ok and result == true
		else
			picked = player:GetAttribute("InArena") == true
		end
		if picked then
			table.insert(list, player)
		end
	end
	return list
end

-- Step 2: the player moved within their first MOVE_WINDOW seconds of control: time without a character, or frozen on a
-- launch plate, doesn't count (in Studio's SoloTest the lobby lasts ~8 s; on a live server a joiner can land just
-- before a Countdown). Follows the player across characters (lobby -> plate).
local function watchFirstMove(player: Player, _character: Model)
	task.spawn(function()
		local control = 0
		local walked = 0
		local last: Vector3? = nil
		local lastRoot: BasePart? = nil
		while control < MOVE_WINDOW and player.Parent == Players do
			task.wait(0.25)
			local root = rootOf(player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and player:GetAttribute("Frozen") ~= true then
				control += 0.25
				local now = root.Position
				if last and root == lastRoot then
					local stepLength = Vector3.new(now.X - last.X, 0, now.Z - last.Z).Magnitude
					-- a teleport (onto a launch plate, back to the lobby) is a big jump, not the player moving
					if stepLength < 8 then
						walked += stepLength
						if walked >= MOVE_DISTANCE then
							OnboardingService.step(player, "Moved")
							return
						end
					end
				end
				last, lastRoot = now, root
			else
				last, lastRoot = nil, nil
			end
		end
	end)
end

local function onPlayerAdded(player: Player)
	OnboardingService.step(player, "Joined")
	local first = true
	local function onCharacter(character: Model)
		if first then
			first = false
			watchFirstMove(player, character)
		end
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

-- Steps 3 and 10 at the Countdown.
local function onRoundStarting()
	for _, player in ipairs(contenders()) do
		OnboardingService.step(player, "OnPlate")
		if finishedBy[player] then
			OnboardingService.step(player, "OnPlateRound2")
		end
	end
end

-- Step 4: more than LEAVE_DISTANCE studs from the plate after the horn.
local function onRoundStarted()
	local starts: { [Player]: Vector3 } = {}
	for _, player in ipairs(contenders()) do
		local root = rootOf(player)
		if root then
			starts[player] = root.Position
		end
	end
	task.spawn(function()
		local deadline = os.clock() + 120
		while next(starts) ~= nil and os.clock() < deadline do
			task.wait(0.5)
			for player, start in pairs(starts) do
				local root = rootOf(player)
				if player.Parent ~= Players or player:GetAttribute("Alive") ~= true then
					starts[player] = nil
				elseif root then
					local delta = root.Position - start
					if Vector3.new(delta.X, 0, delta.Z).Magnitude > LEAVE_DISTANCE then
						OnboardingService.step(player, "LeftPlate")
						starts[player] = nil
					end
				end
			end
		end
	end)
end

-- Step 9 when the round is decided (everyone picked for it who is still here).
local function onRoundEnded()
	for _, player in ipairs(contenders()) do
		OnboardingService.step(player, "FinishedRound")
		finishedBy[player] = true
	end
end

-- Step 8: alive at the round's first Roll Call (ArenaService publishes it in GameState.RollCall).
local function onRollCall()
	local payload = GameState:GetAttribute("RollCall")
	if payload == nil or payload == "" then
		return
	end
	-- a dusk Roll Call happens mid-round; the epilogue (QW14) plays during Ending and is not one
	if GameState:GetAttribute("Phase") ~= "Active" then
		return
	end
	local roundId = GameState:GetAttribute("RoundId")
	if rollCallRound == roundId then
		return -- only the round's first Roll Call
	end
	rollCallRound = roundId
	for _, player in ipairs(contenders()) do
		if player:GetAttribute("Alive") == true then
			OnboardingService.step(player, "SurvivedRollCall1")
		end
	end
end

local function hookSignal(service: string, signal: string, fn: (...any) -> ())
	local s = Services[service]
	local sig = s and s[signal]
	if type(sig) == "table" and type(sig.Connect) == "function" then
		sig:Connect(fn)
		return true
	end
	warn(string.format("[OnboardingService] %s.%s is missing; that funnel step won't log", service, signal))
	return false
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function OnboardingService.Init(registry)
	Services = registry
end

function OnboardingService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		reachedBy[player] = nil
		finishedBy[player] = nil
	end)
	hookSignal("RoundService", "roundStarting", onRoundStarting)
	hookSignal("RoundService", "roundStarted", onRoundStarted)
	hookSignal("RoundService", "roundEnded", onRoundEnded)
	hookSignal("InventoryService", "equippedChanged", function(player: Player, itemId: string?)
		if itemId ~= nil then
			OnboardingService.step(player, "EquippedItem")
		end
	end)
	-- InventoryService.used(player, itemId?, kind): a use finished ("Food" | "Drink" | "Heal" | "Armor") or a sip of water
	hookSignal("InventoryService", "used", function(player: Player, _itemId: string?, kind: string?)
		if kind == "Food" or kind == "Drink" or kind == "Sip" then
			OnboardingService.step(player, "AteOrDrank")
		end
	end)
	-- a crate opened: its OpenPrompt was triggered and LootService marked the crate Opened (repeats are ignored)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= "OpenPrompt" then
			return
		end
		local crate = prompt:FindFirstAncestorOfClass("Model")
		task.delay(0.1, function()
			if crate and crate:GetAttribute("Opened") == true then
				OnboardingService.step(player, "OpenedCrate")
			end
		end)
	end)
	GameState:GetAttributeChangedSignal("RollCall"):Connect(onRollCall)
end

return OnboardingService
