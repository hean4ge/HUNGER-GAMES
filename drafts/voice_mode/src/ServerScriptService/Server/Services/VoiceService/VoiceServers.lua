--[[
	VoiceServers - Proximity Voice, phase 2: voice-only servers (docs/design/VoiceMode.md, "Phase 2"). VoiceService loads it
	only when Config.Voice.VoiceServers.Enabled is true. Off for the beta: one pool of players fills 24-contender rounds
	faster, and Roblox's matchmaking already groups voice users (its Voice Chat signal).

	  * Joining (in a public server's lobby, VOICE-ONLY SERVER on the lobby card -> VoiceRequest "JoinVoiceServer"): the
	    server checks the player can use voice (VoiceChatService:IsVoiceEnabledForUserIdAsync) and isn't in a round, picks
	    the voice-only server with room that starts soonest and is fullest (the MemoryStore sorted map VoiceServers_v1)
	    or opens a new one (a GUID ticket in the MemoryStore hash map VoiceTickets_v1), and teleports the player there
	    with TeleportOptions.ReservedServerId = that GUID.
	  * A voice-only server (a reserved server whose ticket says VoiceOnly) returns "VoiceOnly" from resolve() (VoiceService
	    publishes GameState.VoiceMode), advertises { count, max, phase, t } every AdvertiseInterval seconds, and sends anyone
	    without voice back to the public servers with a toast.
	  * Leaving (LEAVE VOICE-ONLY SERVER on the lobby card -> "LeaveVoiceServer"): a plain TeleportAsync to this place,
	    which is Roblox matchmaking.
	Teleport data is only a pointer to the ticket; the ticket in MemoryStore is the authority (modes-progression.md 4.3).
	MemoryStore and reserved servers work only in a published game (TeleportAsync also runs in Team Test).
	API: init(VoiceService)   resolve() -> "VoiceOnly"? (yields)   onPlayerAdded(player)   request(player, action)
	     isVoiceServer() -> boolean
]]
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local VoiceChatService = game:GetService("VoiceChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local Cfg = (Config.Voice and Config.Voice.VoiceServers) or {}

local SERVERS_MAP = "VoiceServers_v1"
local TICKETS_MAP = "VoiceTickets_v1"
local TICKET_TTL = 6 * 60 * 60 -- seconds; a running voice server refreshes its own ticket every 10 minutes
local ADVERT_TTL = 60
local STALE_AFTER = 45 -- an advert older than this belongs to a server that has gone
local PHASE_RANK = { Lobby = 3, Intermission = 2, Ending = 1 } -- where a joiner gets into a round soonest

local VoiceServers = {}
local voiceServer = false
local matchId: string? = nil
local busy: { [Player]: boolean } = {}
local gated: { [Player]: boolean } = {}
local lastTicketWrite = -math.huge

local function maxPlayers(): number
	return math.max(2, math.floor(tonumber(Cfg.MaxPlayers) or 24))
end

local function notify(player: Player, text: string, sub: string?)
	pcall(function()
		Net.event("Announce"):FireClient(player, { style = "Toast", text = text, sub = sub, duration = 4 })
	end)
end

-- true / false, or nil when Roblox couldn't say (an HTTP error)
local function voiceEnabled(player: Player): boolean?
	local ok, result = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end)
	if not ok then
		return nil
	end
	return result == true
end

local function readTicket(id: string): { [string]: any }?
	local ok, value = pcall(function()
		return MemoryStoreService:GetHashMap(TICKETS_MAP):GetAsync(id)
	end)
	return if ok and type(value) == "table" then value else nil
end

local function writeTicket(id: string): boolean
	local ok = pcall(function()
		MemoryStoreService:GetHashMap(TICKETS_MAP):SetAsync(id, { mode = "VoiceOnly", t = os.time() }, TICKET_TTL)
	end)
	return ok
end

-- Teleports ----------------------------------------------------------------------------------------------------------

local function teleportTo(player: Player, id: string): boolean
	local options = Instance.new("TeleportOptions")
	local okId, err = pcall(function()
		(options :: any).ReservedServerId = id -- the GUID names the server: the first teleport creates it
	end)
	if not okId then
		warn("[VoiceServers] TeleportOptions.ReservedServerId is unavailable: " .. tostring(err))
		return false
	end
	options:SetTeleportData({ voiceMatch = id })
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return TeleportService:TeleportAsync(game.PlaceId, { player }, options)
		end)
		if ok then
			return true
		end
		warn(string.format("[VoiceServers] Teleport attempt %d failed: %s", attempt, tostring(result)))
		task.wait(2 * attempt)
		if player.Parent ~= Players then
			return false
		end
	end
	return false
end

-- Back to the public servers: no options means Roblox matchmaking picks one.
local function toPublic(player: Player): boolean
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return TeleportService:TeleportAsync(game.PlaceId, { player })
		end)
		if ok then
			return true
		end
		warn(string.format("[VoiceServers] Return attempt %d failed: %s", attempt, tostring(result)))
		task.wait(2 * attempt)
		if player.Parent ~= Players then
			return false
		end
	end
	return false
end

-- Matching -----------------------------------------------------------------------------------------------------------

local function pickServer(): string?
	local ok, items = pcall(function()
		return MemoryStoreService:GetSortedMap(SERVERS_MAP):GetRangeAsync(Enum.SortDirection.Descending, 50)
	end)
	if not ok or type(items) ~= "table" then
		return nil
	end
	local now = os.time()
	local best, bestScore = nil, -math.huge
	for _, item in ipairs(items) do
		local value = item.value
		if type(item.key) == "string" and type(value) == "table" then
			local count = tonumber(value.count) or 0
			local max = tonumber(value.max) or maxPlayers()
			local fresh = now - (tonumber(value.t) or 0) < STALE_AFTER
			if fresh and count < max - 1 then -- leave a seat for a party member who follows
				local score = (PHASE_RANK[value.phase] or 0) * 1000 + count
				if score > bestScore then
					best, bestScore = item.key, score
				end
			end
		end
	end
	return best
end

-- In a voice-only server: tell the public servers we're here and how full we are.
local function advertise()
	local id = matchId
	if not id then
		return
	end
	local count = #Players:GetPlayers()
	pcall(function()
		MemoryStoreService:GetSortedMap(SERVERS_MAP):SetAsync(id, {
			count = count,
			max = maxPlayers(),
			phase = GameState:GetAttribute("Phase") or "Lobby",
			t = os.time(),
		}, ADVERT_TTL, count)
	end)
	if os.clock() - lastTicketWrite > 600 then
		lastTicketWrite = os.clock()
		writeTicket(id)
	end
end

local function unadvertise()
	local id = matchId
	if id then
		pcall(function()
			MemoryStoreService:GetSortedMap(SERVERS_MAP):RemoveAsync(id)
		end)
	end
end

-- Public API ---------------------------------------------------------------------------------------------------------

function VoiceServers.isVoiceServer(): boolean
	return voiceServer
end

-- On a reserved server: is it voice-only? Yields for MemoryStore (and up to 30 s for the first arrival).
function VoiceServers.resolve(): string?
	if game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0 then
		return nil -- a public server, or a Roblox private server (Private Games)
	end
	local id = game.PrivateServerId
	local ticket = readTicket(id)
	if not ticket then
		-- the ticket's GUID may not equal PrivateServerId: follow the first arrival's pointer, then check it in MemoryStore
		local first = Players:GetPlayers()[1]
		local deadline = os.clock() + 30
		while not first and os.clock() < deadline do
			task.wait(0.5)
			first = Players:GetPlayers()[1]
		end
		if first then
			local okJoin, joinData = pcall(function()
				return first:GetJoinData()
			end)
			local data = if okJoin and type(joinData) == "table" then joinData.TeleportData else nil
			local pointer = if type(data) == "table" then data.voiceMatch else nil
			if type(pointer) == "string" and #pointer <= 64 then
				ticket = readTicket(pointer)
				if ticket then
					id = pointer
				end
			end
		end
	end
	if not (ticket and ticket.mode == "VoiceOnly") then
		return nil
	end
	voiceServer = true
	matchId = id
	game:BindToClose(unadvertise)
	task.spawn(function()
		while true do
			advertise()
			task.wait(math.max(5, tonumber(Cfg.AdvertiseInterval) or 15))
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(VoiceServers.onPlayerAdded, player)
	end
	return "VoiceOnly"
end

-- On a voice-only server: anyone Roblox says can't use voice goes back to the public servers.
function VoiceServers.onPlayerAdded(player: Player)
	if not voiceServer or gated[player] then
		return
	end
	gated[player] = true
	if voiceEnabled(player) == false and player.Parent == Players then
		notify(player, "THIS IS A VOICE-ONLY SERVER", "Voice isn't on for your account · taking you to a regular server")
		task.wait(3)
		if player.Parent == Players then
			toPublic(player)
		end
	end
end

function VoiceServers.request(player: Player, action: string)
	if busy[player] then
		return
	end
	busy[player] = true
	local ok, err = pcall(function()
		if action == "LeaveVoiceServer" then
			if voiceServer then
				notify(player, "LEAVING THE VOICE-ONLY SERVER", "Taking you to a regular server")
				toPublic(player)
			end
			return
		end
		if voiceServer then
			return -- already on one
		end
		if player:GetAttribute("Alive") == true or player:GetAttribute("InArena") == true then
			notify(player, "FINISH YOUR ROUND FIRST", "Voice-only servers open from the lobby")
			return
		end
		if voiceEnabled(player) ~= true then
			notify(player, "VOICE ISN'T ON FOR YOUR ACCOUNT", "Voice-only servers need Roblox voice chat")
			return
		end
		local id = pickServer()
		if not id then
			id = HttpService:GenerateGUID(false)
			if not writeTicket(id) then
				notify(player, "COULDN'T OPEN A VOICE-ONLY SERVER", "Try again in a moment")
				return
			end
		end
		notify(player, "VOICE-ONLY SERVER", "Taking you there…")
		if not teleportTo(player, id :: string) then
			notify(player, "TELEPORT FAILED", "You're still here · try again in a moment")
		end
	end)
	busy[player] = nil
	if not ok then
		warn("[VoiceServers] " .. tostring(err))
	end
end

function VoiceServers.init(_voiceService)
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result, message)
		if player and player.Parent == Players then
			warn(string.format("[VoiceServers] Teleport failed for %s: %s %s", player.Name, tostring(result), tostring(message)))
			notify(player, "TELEPORT FAILED", "You're still here · try again in a moment")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		gated[player] = nil
	end)
end

return VoiceServers
