--[[
	VoiceService - Proximity Voice, server side: who can hear whom (docs/design/VoiceMode.md). Behind Config.Voice.Enabled:
	while that is false this service does nothing. (Roblox's own voice still runs: how it sounds then depends on the
	place's VoiceChatService settings, not on this flag. See studio/ApplyVoiceSettings.lua.)

	With VoiceChatService.UseAudioApi = Enabled and EnableDefaultVoice = true, Roblox gives every voice-eligible player an
	AudioDeviceInput under their Player. This service writes three things on each of those devices, on the server (the
	access list is set on the server and replicates to clients):
	  * AccessType + SetUserIdAccessList, from the player's voice role (Player attribute VoiceRole):
	      "Open"       no round running (Lobby, Intermission, Ending): Deny + an empty list = anyone in range hears them.
	      "Contender"  alive in a running round: anyone in range (other contenders, and spectators watching close by).
	                   While whispering (Config.Voice.Whisper, truce allies): Allow + those allies only.
	      "Bench"      everyone else while a round runs (the fallen, late joiners, the lobby: "the stands"): Allow + the
	                   bench's UserIds. The living are never on that list, wherever their body or their camera is.
	  * Muted, unless the player's choice is known and On (Routing.choice): their choice this session (VoiceRequest
	    SetVoice), else their saved one once DataService says the profile loaded (SettingsLoaded = true). Until then, and
	    for the whole session if the load failed, they stay muted: nothing turns a saved OFF back on by itself.
	    ServerMode "Off" mutes everyone. Roblox's own mic toggle (AudioDeviceInput.Active) is never touched.
	A contender who falls moves to the bench the moment PlayerService handles the death (onEliminated), before the cannon.
	Every pass reads each device back and rewrites whatever differs from the rules, in Routing.plan's fail-closed order;
	a write that fails is retried on the next pass (at most 5 s later), and a device someone else changed is logged.
	What this does not prove: where Roblox applies the list (the docs don't say whether a modified client could still
	receive a stream it isn't listed for), and whether Roblox's own mute, block and volume controls reach the client's
	custom audio chain. Those are the published safety gate (VoiceMode.md, test plan G1-G6).
	It never records: no AudioRecorder, no speech-to-text, no audio analysis on the server.

	Attributes (replicated):
	  GameState.VoiceMode   "Proximity" | "Off" | "VoiceOnly" (a voice-only server, VoiceServers); not set while disabled
	  Player.VoiceRole      "Open" | "Contender" | "Bench"
	  Player.VoiceOn        true while the server lets this player be heard (the device is unmuted)
	  Player.VoiceHold      "" | "Loading" (the saved choice is still loading) | "NotLoaded" (it couldn't load): why a
	                        player who hasn't chosen this session is muted
	  Player.VoiceWhisper   true while this player whispers to allies (clients shorten that voice's reach)
	  Player.VoiceAllies    how many allies would hear a whisper (0 = nothing to whisper to)
	  (Player.Spectating is written by PlayerService; Player.SettingsLoaded by DataService)
	API (through the registry):
	  VoiceService.isEnabled() -> boolean
	  VoiceService.getRole(player) -> string
	  VoiceService.onEliminated(player)            PlayerService.handleDeath, right after the victim's Alive goes false
	  VoiceService.refresh()                       recompute and re-check every device now
	  VoiceService.setAllies(player, { Player })   for a future TruceService (Config.Voice.Whisper)
	  VoiceService.changed: Signal()               after every pass
	  VoiceService.debugState() -> { [string]: any }
	Remote VoiceRequest(action: string, value: any), validated; each action has its own rate limit, and a request over
	the limit is applied shortly instead of dropped (the last one always lands). SetVoice(false) is never limited.
	  "SetVoice" (boolean)   the player's explicit Proximity voice choice (the client sends it only when they toggle it)
	  "Whisper"  (boolean)   hold to whisper; ignored unless Config.Voice.Whisper.Enabled and the player has allies
	  "JoinVoiceServer" / "LeaveVoiceServer"   phase 2: VoiceServers (Config.Voice.VoiceServers.Enabled)
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VoiceChatService = game:GetService("VoiceChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))

-- (a timeout, so a missing child makes this one service fail to load instead of stalling the server's loader)
local Routing = require(script:WaitForChild("Routing", 10))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local VoiceCfg = Config.Voice or {}

local SAFETY_INTERVAL = 5 -- seconds between full re-checks (each reads every device back; unchanged ones aren't written)
local NO_DEVICE_WARNING = 30 -- seconds a voice-enabled player may go without a device before we say why
local FLUSH_DELAY = 0.5 -- seconds before a request that was over the rate limit is applied
local DEFAULT_ROUND_PHASES = { Countdown = true, Active = true }

-- Enum.AccessModifierType (Allow / Deny) comes with the Audio API; without it there is nothing to route
local ALLOW: EnumItem? = nil
local DENY: EnumItem? = nil
pcall(function()
	ALLOW = (Enum :: any).AccessModifierType.Allow
	DENY = (Enum :: any).AccessModifierType.Deny
end)

local VoiceService = {}
VoiceService.changed = Signal.new()

local Services = nil
local enabled = false
local serverMode = "Proximity" -- "Proximity" | "Off" | "VoiceOnly"
local states = {} -- [Player] = per-player state (newState)
local queued = false
local warned = {}
local VoiceServers = nil -- the phase-2 module, when Config.Voice.VoiceServers.Enabled

-- Helpers ----------------------------------------------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[VoiceService] " .. message)
end

local function debugPrint(...: any)
	if VoiceCfg.Debug == true then
		print("[VoiceService]", ...)
	end
end

local function setAttr(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function newState()
	return {
		device = nil :: AudioDeviceInput?,
		explicit = nil :: boolean?, -- the player's choice this session (SetVoice): newer than any saved copy
		saved = nil :: boolean?, -- the saved choice (SettingsJson voiceOn), read only once the profile has loaded
		loadState = "Loading", -- "Loading" | "Loaded" | "Failed" (DataService's SettingsLoaded attribute)
		whisper = false,
		allies = {} :: { [Player]: boolean },
		role = "Open",
		lastTarget = nil :: { [string]: any }?, -- what this service last wrote to the device (drift check)
		failed = false, -- the last write failed: the next pass tries again
		eligible = nil :: boolean?,
		connections = {} :: { RBXScriptConnection },
		pending = {} :: { [string]: { value: any } }, -- requests over the rate limit, applied shortly
		flushQueued = false,
	}
end

-- Roles ------------------------------------------------------------------------------------------------------------

local function roundRunning(): boolean
	local rs = Services and Services.RoundService
	if rs and type(rs.isRoundRunning) == "function" then
		local ok, running = pcall(rs.isRoundRunning)
		if ok then
			return running == true
		end
	end
	local phases = VoiceCfg.RoundPhases or DEFAULT_ROUND_PHASES
	return phases[GameState:GetAttribute("Phase")] == true
end

local function isAlive(player: Player): boolean
	local ps = Services and Services.PlayerService
	if ps and type(ps.isAlive) == "function" then
		local ok, alive = pcall(ps.isAlive, player)
		if ok then
			return alive == true
		end
	end
	return player:GetAttribute("Alive") == true
end

-- The saved choice ---------------------------------------------------------------------------------------------------

-- DataService sets SettingsJson, then SettingsLoaded: true once the stored profile was read (or, in Studio only, when
-- DataStores are off), false when the load failed. Only a loaded profile counts; "{}" after a failed load is not a
-- choice. (The player's explicit choice this session, st.explicit, always wins over this.)
local function readSaved(player: Player, st)
	local loaded = player:GetAttribute("SettingsLoaded")
	local json = player:GetAttribute("SettingsJson")
	st.saved = nil
	if loaded == false then
		st.loadState = "Failed"
		return
	end
	if loaded ~= true or type(json) ~= "string" or json == "" then
		st.loadState = "Loading"
		return
	end
	st.loadState = "Loaded"
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if ok and type(decoded) == "table" and type(decoded.voiceOn) == "number" then
		st.saved = decoded.voiceOn >= 0.5
	end
end

-- Devices ----------------------------------------------------------------------------------------------------------

local function findDevice(player: Player): AudioDeviceInput?
	for _, child in ipairs(player:GetChildren()) do
		if child:IsA("AudioDeviceInput") then
			local owner = (child :: any).Player
			if owner == nil or owner == player then
				return child :: AudioDeviceInput
			end
		end
	end
	return nil
end

-- The device as it is now (nil if it can't be read: the next pass tries again)
local function readDevice(device: AudioDeviceInput): { [string]: any }?
	local ok, state = pcall(function()
		return {
			muted = device.Muted == true,
			allow = device.AccessType == ALLOW,
			list = Routing.sortedIds(device:GetUserIdAccessList()),
		}
	end)
	return if ok then state else nil
end

local function runSteps(device: AudioDeviceInput, steps: { { [string]: any } })
	for _, step in ipairs(steps) do
		if step.op == "Muted" then
			device.Muted = step.value == true
		elseif step.op == "AccessType" then
			device.AccessType = (if step.value == "Allow" then ALLOW else DENY) :: any
		elseif step.op == "List" then
			device:SetUserIdAccessList(step.value)
		end
	end
end

local function describe(state: { [string]: any }): string
	return string.format("%s %s(%d)", if state.muted then "muted" else "live", if state.allow then "Allow" else "Deny", #state.list)
end

local function allyIds(player: Player, st): { number }
	local ids = {}
	for ally in pairs(st.allies) do
		if ally.Parent == Players and ally ~= player then
			table.insert(ids, ally.UserId)
		end
	end
	table.sort(ids)
	return ids
end

local function applyPlayer(player: Player, st, bench: { number })
	local on = Routing.choice(st, VoiceCfg.DefaultOn ~= false)
	local allies = allyIds(player, st)
	local whisper = st.whisper and st.role == "Contender" and #allies > 0
	local target = Routing.desired(st.role, on, whisper, allies, bench, serverMode)
	local live = not target.muted
	setAttr(player, "VoiceRole", st.role)
	setAttr(player, "VoiceHold", if on ~= nil then "" elseif st.loadState == "Failed" then "NotLoaded" else "Loading")
	setAttr(player, "VoiceWhisper", whisper)
	setAttr(player, "VoiceAllies", if st.role == "Contender" then #allies else 0)
	if not live then
		setAttr(player, "VoiceOn", false) -- the client closes its mic on this at once (VoiceController)
	end

	local device = st.device
	if not device or device.Parent ~= player then
		setAttr(player, "VoiceOn", live)
		return
	end
	local current = readDevice(device)
	if not current then
		st.failed = true
		warnOnce("read:" .. player.UserId, "Couldn't read " .. player.Name .. "'s voice device; trying again.")
		return
	end
	local last = st.lastTarget
	if last and not st.failed and (current.muted ~= last.muted or current.allow ~= last.allow
		or not Routing.sameList(current.list, last.list)) then
		-- something other than this service changed the device: put it back, and say so once (worth knowing in tests)
		warnOnce("drift:" .. player.UserId, string.format("%s's voice device changed under us (%s, expected %s); rewritten.",
			player.Name, describe(current), describe(last)))
	end
	local steps = Routing.plan(current, target)
	if #steps > 0 then
		local ok, err = pcall(runSteps, device, steps)
		if not ok then
			st.failed = true
			st.lastTarget = nil
			warnOnce("write:" .. tostring(err), "Couldn't set a voice device: " .. tostring(err))
			return
		end
		debugPrint(player.Name, st.role, describe(current), "->", describe(target))
	end
	st.failed = false
	st.lastTarget = target
	if live then
		setAttr(player, "VoiceOn", true) -- only once the device really is open
	end
end

-- Recompute every role, read every device back and write what differs.
local function refreshNow()
	queued = false
	if not enabled then
		return
	end
	local running = roundRunning()
	local roster = {}
	for player, st in pairs(states) do
		if player.Parent == Players then
			table.insert(roster, { key = player, id = player.UserId, alive = isAlive(player) })
		end
	end
	local roles, bench = Routing.assign(roster, running)
	for player, st in pairs(states) do
		if player.Parent == Players then
			st.role = roles[player] or "Open"
			applyPlayer(player, st, bench)
		end
	end
	VoiceService.changed:Fire()
end

local function safeRefresh()
	local ok, err = pcall(refreshNow)
	if not ok then
		queued = false
		warnOnce("refresh:" .. tostring(err), "Refresh failed: " .. tostring(err))
	end
end

local function queueRefresh()
	if queued or not enabled then
		return
	end
	queued = true
	task.defer(safeRefresh)
end

-- Players ----------------------------------------------------------------------------------------------------------

-- Diagnostics only: a voice-enabled player without a device means the place still runs Roblox's old built-in voice.
local function checkEligibility(player: Player, st)
	local ok, result = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end)
	if not ok or states[player] ~= st then
		return
	end
	st.eligible = result == true
	if st.eligible then
		task.delay(NO_DEVICE_WARNING, function()
			if states[player] == st and player.Parent == Players and not st.device then
				warnOnce("nodevice", string.format("A voice-enabled player still has no AudioDeviceInput after %d s. Is "
					.. "VoiceChatService.UseAudioApi = Enabled in Studio? (Automatic still runs the old built-in voice, which "
					.. "these rules can't reach.)", NO_DEVICE_WARNING))
			end
		end)
	end
end

local function useDevice(player: Player, st)
	local device = findDevice(player)
	if device ~= st.device then
		st.device = device
		st.lastTarget = nil
		st.failed = false
		queueRefresh()
	end
end

local function onPlayerAdded(player: Player)
	if states[player] or player.Parent ~= Players then
		return
	end
	local st = newState()
	states[player] = st
	setAttr(player, "VoiceOn", false) -- muted until the choice is known
	table.insert(st.connections, player.ChildAdded:Connect(function(child)
		if child:IsA("AudioDeviceInput") then
			useDevice(player, st)
		end
	end))
	table.insert(st.connections, player.ChildRemoved:Connect(function(child)
		if child == st.device then
			useDevice(player, st)
		end
	end))
	table.insert(st.connections, player:GetAttributeChangedSignal("Alive"):Connect(queueRefresh))
	for _, attribute in ipairs({ "SettingsJson", "SettingsLoaded" }) do
		table.insert(st.connections, player:GetAttributeChangedSignal(attribute):Connect(function()
			readSaved(player, st)
			queueRefresh()
		end))
	end
	readSaved(player, st)
	useDevice(player, st)
	queueRefresh()
	task.spawn(checkEligibility, player, st)
	if VoiceServers then
		task.spawn(VoiceServers.onPlayerAdded, player)
	end
end

local function onPlayerRemoving(player: Player)
	local st = states[player]
	if not st then
		return
	end
	for _, connection in ipairs(st.connections) do
		connection:Disconnect()
	end
	states[player] = nil
	for _, other in pairs(states) do
		other.allies[player] = nil
	end
	queueRefresh()
end

local function handleRequest(player: Player, st, action: string, value: any)
	if action == "SetVoice" then
		if type(value) ~= "boolean" then
			return
		end
		st.explicit = value
		if value == false then
			st.pending.SetVoice = nil -- an older ON still waiting for its turn must not land after this OFF
		end
		safeRefresh()
	elseif action == "Whisper" then
		if type(value) ~= "boolean" then
			return
		end
		st.whisper = value and (VoiceCfg.Whisper or {}).Enabled == true
		safeRefresh()
	elseif action == "JoinVoiceServer" or action == "LeaveVoiceServer" then
		if VoiceServers then
			task.spawn(VoiceServers.request, player, action)
		end
	end
end

local ACTIONS = { SetVoice = true, Whisper = true, JoinVoiceServer = true, LeaveVoiceServer = true }

local function onRequest(player: Player, action: any, value: any)
	local st = states[player]
	if not st or type(action) ~= "string" or ACTIONS[action] ~= true then
		return
	end
	if Routing.exempt(action, value) then
		handleRequest(player, st, action, value) -- turning voice off is never limited or delayed
		return
	end
	if Net.rateLimit(player, "Voice:" .. action, 4, 8) then
		handleRequest(player, st, action, value)
		return
	end
	-- over the limit: keep the latest of each action and apply it shortly, so the last request always lands
	st.pending[action] = { value = value }
	if st.flushQueued then
		return
	end
	st.flushQueued = true
	task.delay(FLUSH_DELAY, function()
		st.flushQueued = false
		if states[player] ~= st then
			return
		end
		local pending = st.pending
		st.pending = {}
		for pendingAction, entry in pairs(pending) do
			handleRequest(player, st, pendingAction, entry.value)
		end
	end)
end

-- Public API ---------------------------------------------------------------------------------------------------------

function VoiceService.isEnabled(): boolean
	return enabled
end

function VoiceService.getRole(player: Player): string
	local st = states[player]
	return if st then st.role else "Open"
end

function VoiceService.refresh()
	if enabled then
		safeRefresh()
	end
end

-- PlayerService.handleDeath calls this right after the victim's Alive attribute goes false: they join the bench now,
-- not a frame later, so not a word reaches the living from the body.
function VoiceService.onEliminated(_player: Player)
	if enabled then
		safeRefresh()
	end
end

-- For a future TruceService: the allies who may hear this player's whisper (Config.Voice.Whisper). An empty list ends it.
function VoiceService.setAllies(player: Player, allies: { Player })
	local st = states[player]
	if not st then
		return
	end
	table.clear(st.allies)
	if type(allies) == "table" then
		for _, ally in ipairs(allies) do
			if typeof(ally) == "Instance" and ally:IsA("Player") and ally ~= player then
				st.allies[ally] = true
			end
		end
	end
	if next(st.allies) == nil then
		st.whisper = false
	end
	if enabled then
		safeRefresh()
	end
end

function VoiceService.debugState(): { [string]: any }
	local players = {}
	for player, st in pairs(states) do
		local entry: { [string]: any } = {
			name = player.Name,
			role = st.role,
			on = Routing.choice(st, VoiceCfg.DefaultOn ~= false),
			explicit = st.explicit,
			saved = st.saved,
			loadState = st.loadState,
			eligible = st.eligible,
			device = st.device ~= nil,
			failed = st.failed,
		}
		local device = st.device
		if device then
			pcall(function()
				entry.muted = device.Muted
				entry.micActive = device.Active
				entry.accessType = tostring(device.AccessType)
				entry.listSize = #device:GetUserIdAccessList()
			end)
		end
		table.insert(players, entry)
	end
	return { enabled = enabled, mode = serverMode, roundRunning = roundRunning(), players = players }
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function VoiceService.Init(registry)
	Services = registry
	if VoiceCfg.Enabled ~= true then
		return
	end
	if not (ALLOW and DENY) then
		warnOnce("enum", "Enum.AccessModifierType is missing (no Audio API in this build?): Proximity Voice stays off.")
		return
	end
	enabled = true
	serverMode = if VoiceCfg.ServerMode == "Off" then "Off" else "Proximity"
	GameState:SetAttribute("VoiceMode", serverMode)
	Net.event("VoiceRequest").OnServerEvent:Connect(onRequest)

	local serversCfg = VoiceCfg.VoiceServers or {}
	local module = script:FindFirstChild("VoiceServers")
	if serversCfg.Enabled == true and module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			VoiceServers = result
			result.init(VoiceService)
		else
			warn("[VoiceService] VoiceServers failed to load: " .. tostring(result))
		end
	end
end

function VoiceService.Start()
	if not enabled then
		return
	end
	GameState:GetAttributeChangedSignal("Phase"):Connect(queueRefresh)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	if VoiceServers then
		task.spawn(function()
			local ok, mode = pcall(VoiceServers.resolve) -- yields (MemoryStore); a public server returns nil at once
			if ok and mode == "VoiceOnly" and serverMode ~= "Off" then
				serverMode = "VoiceOnly"
				GameState:SetAttribute("VoiceMode", "VoiceOnly")
				queueRefresh()
			elseif not ok then
				warn("[VoiceService] VoiceServers.resolve failed: " .. tostring(mode))
			end
		end)
	end
	while true do
		task.wait(SAFETY_INTERVAL)
		-- the backstop: a missed device, a missed attribute change or a failed write is caught here
		for player, st in pairs(states) do
			if player.Parent == Players then
				local ok = pcall(function()
					readSaved(player, st)
					local device = findDevice(player)
					if device ~= st.device then
						st.device = device
						st.lastTarget = nil
						st.failed = false
					end
				end)
				if not ok then
					st.failed = true
				end
			end
		end
		safeRefresh()
	end
end

return VoiceService
