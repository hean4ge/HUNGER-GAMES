--[[
	PlusService - Roblox Plus (Roblox's own subscription) in the game: the server half. PlusController is the client half.

	What it does, and nothing more:
	  * Reads Player.HasRobloxSubscription on join and whenever it changes, and publishes it as the Player attribute
	    "PlusMember" (boolean). That attribute is the whole member perk's switch: PlusController writes a small PLUS
	    mark beside a member's name in the lobby. It is cosmetic. Nothing in a round reads it.
	  * Tells each client, and only that client, whether the lobby may show its quiet "ROBLOX PLUS" button:
	    the API exists, the player is not a member already, and PolicyService says they may buy subscriptions
	    (IsEligibleToPurchaseSubscription; a failed policy call counts as no).
	  * Opens Roblox's own subscription window (MarketplaceService:PromptRobloxSubscriptionPurchase) when, and only
	    when, the player presses SUBSCRIBE in the panel they opened themselves. At most once per PROMPT_COOLDOWN
	    seconds per player, never for a contender in the arena.

	Rules this file keeps (launch research, 18 Nov 2026: Roblox states no rule on where or how often the window may be
	shown, so the game carries the care itself, with young players in mind):
	  * The window is never opened on join, on spawn, at a round's start or end, or by touching anything.
	  * Nothing is granted for pressing the button or for closing the window. The mark follows HasRobloxSubscription
	    alone, so every member has it wherever they subscribed.
	  * No price appears in the game's own text. Roblox's window shows it.
	  * Every Roblox call is in a pcall. If the API is missing, nothing here runs and the lobby is as it was.

	Remote: ReplicatedStorage.Remotes.PlusSubscribe, created here at start (it is not in Net.Names on purpose: the
	game works unchanged without this service).
	  client -> server  "state"       ask for the button's state (PlusController, once at start)
	  client -> server  "subscribe"   the player pressed SUBSCRIBE
	  server -> client  "state", offer: boolean

	Studio only: Workspace attribute PlusTestOffer = true makes the offer show for a tester who is a member already.
]]
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local PlusService = {}

local REMOTE_NAME = "PlusSubscribe"
local PROMPT_COOLDOWN = 10 -- seconds between two windows for one player (Roblox's own sample uses 5)
local POLICY_RETRY = { 5, 15 } -- a failed policy call is tried again after these waits, then left as "no"

type State = {
	member: boolean,
	eligible: boolean,
	lastPrompt: number,
	connection: RBXScriptConnection?,
}

local isStudio = RunService:IsStudio()
local states: { [Player]: State } = {}
local remote: RemoteEvent? = nil
local apiReady = false
local warned = false

local function hasPromptApi(): boolean
	local ok, method = pcall(function()
		return (MarketplaceService :: any).PromptRobloxSubscriptionPurchase
	end)
	return ok and type(method) == "function"
end

-- nil when the property does not exist on this engine
local function readMember(player: Player): boolean?
	local ok, value = pcall(function()
		return (player :: any).HasRobloxSubscription
	end)
	if not ok then
		return nil
	end
	return value == true
end

local function offered(player: Player, st: State): boolean
	if not apiReady then
		return false
	end
	if isStudio and workspace:GetAttribute("PlusTestOffer") == true then
		return true
	end
	return st.eligible and not st.member and player.Parent == Players
end

local function send(player: Player)
	local st = states[player]
	if st and remote and player.Parent == Players then
		remote:FireClient(player, "state", offered(player, st))
	end
end

local function refreshMember(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local member = readMember(player)
	if member == nil or member == st.member then
		return
	end
	st.member = member
	-- the grant: the mark follows the subscription itself, never the button or the window
	player:SetAttribute("PlusMember", member)
	send(player)
end

local function checkPolicy(player: Player)
	for attempt = 1, #POLICY_RETRY + 1 do
		local st = states[player]
		if not st or player.Parent ~= Players then
			return
		end
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" then
			st = states[player]
			if st then
				st.eligible = (info :: any).IsEligibleToPurchaseSubscription == true
				send(player)
			end
			return
		end
		local pause = POLICY_RETRY[attempt]
		if not pause then
			return -- still no answer: the button stays hidden for this player
		end
		task.wait(pause)
	end
end

local function setup(player: Player)
	if states[player] then
		return
	end
	local member = readMember(player)
	if member == nil then
		return -- no such property here: nothing runs
	end
	local st: State = { member = member, eligible = false, lastPrompt = -math.huge }
	states[player] = st
	player:SetAttribute("PlusMember", member)
	pcall(function()
		st.connection = player:GetPropertyChangedSignal("HasRobloxSubscription"):Connect(function()
			refreshMember(player)
		end)
	end)
	task.spawn(checkPolicy, player)
end

local function onSubscribe(player: Player, st: State)
	local now = os.clock()
	if now - st.lastPrompt < PROMPT_COOLDOWN then
		return
	end
	if not offered(player, st) then
		return
	end
	-- never during a match: the lobby screen is hidden then, so a request from the arena did not come from the button
	if player:GetAttribute("InArena") == true or player:GetAttribute("Alive") == true then
		return
	end
	st.lastPrompt = now
	local ok, err = pcall(function()
		(MarketplaceService :: any):PromptRobloxSubscriptionPurchase(player)
	end)
	if not ok and not warned then
		warned = true
		warn("[Plus] the subscription window could not be opened: " .. tostring(err))
	end
end

function PlusService.Init(_services)
	apiReady = hasPromptApi()
	if not apiReady then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		apiReady = false
		return
	end
	local existing = folder:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		local created = Instance.new("RemoteEvent")
		created.Name = REMOTE_NAME
		created.Parent = folder
		remote = created
	end
end

function PlusService.Start()
	local event = remote
	if not apiReady or not event then
		return
	end
	event.OnServerEvent:Connect(function(player: Player, action: any)
		local st = states[player]
		if not st or type(action) ~= "string" then
			return
		end
		if action == "state" then
			if Net.rateLimit(player, "PlusState", 0.5, 3) then
				send(player)
			end
		elseif action == "subscribe" then
			onSubscribe(player, st)
		end
	end)
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		local st = states[player]
		states[player] = nil
		if st and st.connection then
			st.connection:Disconnect()
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		setup(player)
	end
end

return PlusService
