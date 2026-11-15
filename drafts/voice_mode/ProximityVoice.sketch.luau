--!strict
-- DRAFT SKETCH (research output, untested, not installed anywhere).
-- Proximity voice with the Audio API as documented in November 2026.
--
-- Edit-time prerequisites. Game scripts can't set these: the VoiceChatService and
-- SoundService.DefaultListenerLocation members carry the PluginOrOpenCloud capability.
-- Set them in Studio's Properties window or through Open Cloud Luau execution.
--   * Experience Settings > Communication > Enable Voice Chat = on (universe)
--   * VoiceChatService.UseAudioApi = Enabled (per place; Automatic still behaves as Disabled)
--   * VoiceChatService.EnableDefaultVoice = true (per place; the engine builds the graph)
--   * VoiceChatService.DefaultDistanceAttenuation = Inverse (default) or Legacy (7-80 studs)
--   * SoundService.DefaultListenerLocation = Default or Camera, so a spectator hears what
--     their camera sees. Character would leave the listener on the lobby body.
-- The default setup then gives each voice-eligible player this graph:
--   Player.AudioDeviceInput -> Wire -> Character.AudioEmitter
-- and each client gets this one:
--   Workspace.CurrentCamera.AudioListener -> Wire -> AudioDeviceOutput

------------------------------------------------------------------------------
-- A. Server Script (ServerScriptService): customise the default setup
------------------------------------------------------------------------------
local Players = game:GetService("Players")

-- Example: a VC-only reserved server; set it from TeleportData or a server attribute.
local VOICE_MODE = true

-- Keys are studs and values are volume (0..1). Up to 400 points are allowed; the curve is
-- linear between points and flat past the last one.
local VOICE_CURVE = { [0] = 1, [10] = 1, [35] = 0.5, [70] = 0.15, [100] = 0 }

local function isContender(player: Player): boolean
	return player:GetAttribute("Contender") == true -- placeholder: use GameState / RoundService
end

local function deviceOf(player: Player): AudioDeviceInput?
	local d = player:FindFirstChildWhichIsA("AudioDeviceInput")
	return if d and d:IsA("AudioDeviceInput") then d else nil
end

-- Decide on the server who hears whom. Set AccessType and lists on the server only.
-- A living contender can be heard by anyone in range. The fallen and the lobby are heard
-- only by other non-contenders, so nobody ghosts into the arena.
-- Platform rules still apply on top: Roblox enforces age groups and eligibility.
local function refreshVoiceAccess()
	local bench = {}
	for _, p in Players:GetPlayers() do
		if not isContender(p) then
			table.insert(bench, p.UserId)
		end
	end
	for _, p in Players:GetPlayers() do
		local device = deviceOf(p)
		if device then
			device.Muted = not VOICE_MODE -- sound flows only when Active and not Muted
			if isContender(p) then
				device.AccessType = Enum.AccessModifierType.Deny
				device:SetUserIdAccessList({}) -- empty deny list: nobody is blocked
			else
				device.AccessType = Enum.AccessModifierType.Allow
				device:SetUserIdAccessList(bench)
			end
		end
	end
end

local function tuneEmitter(character: Model)
	local emitter = character:WaitForChild("AudioEmitter", 10) -- made by the default setup
	if emitter and emitter:IsA("AudioEmitter") then
		emitter:SetDistanceAttenuation(VOICE_CURVE) -- only used in Custom mode (the default)
		-- Preset alternative (added July 2026):
		-- emitter.DistanceAttenuationMode = Enum.DistanceAttenuationMode.InverseTapered
		-- emitter.DistanceAttenuationBounds = NumberRange.new(8, 100)
	end
end

local function onPlayerAdded(player: Player)
	player.ChildAdded:Connect(function(child)
		if child:IsA("AudioDeviceInput") then
			refreshVoiceAccess()
		end
	end)
	player.CharacterAdded:Connect(tuneEmitter)
	if player.Character then
		task.spawn(tuneEmitter, player.Character)
	end
	refreshVoiceAccess()
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshVoiceAccess)
end)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end
-- Also call refreshVoiceAccess() on every round-state change: round start and each death.

------------------------------------------------------------------------------
-- B. Variant: your own graph (UseAudioApi = Enabled, EnableDefaultVoice = false)
------------------------------------------------------------------------------
--[[ Server:
local VoiceChatService = game:GetService("VoiceChatService")
local function wire(src: Instance, dst: Instance)
	local w = Instance.new("Wire")
	w.SourceInstance = src
	w.TargetInstance = dst
	w.Parent = dst
end
local function setupVoice(player: Player)
	-- On the server this only checks players in this server. It can throw, so use pcall.
	local ok, enabled = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end)
	if not (ok and enabled) then return end
	local device = Instance.new("AudioDeviceInput")
	device.Player = player -- assign on the server
	device.Parent = player
	local function onCharacter(character: Model)
		local head = character:WaitForChild("Head", 10)
		if not head then return end
		local emitter = Instance.new("AudioEmitter")
		emitter:SetDistanceAttenuation(VOICE_CURVE)
		emitter.Parent = head
		wire(device, emitter)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then task.spawn(onCharacter, player.Character) end
end

Client LocalScript: you can skip this if DefaultListenerLocation = Camera, which builds it.
local listener = Instance.new("AudioListener")
listener.Parent = workspace.CurrentCamera
local out = Instance.new("AudioDeviceOutput")
out.Parent = listener
local w = Instance.new("Wire")
w.SourceInstance = listener
w.TargetInstance = out
w.Parent = listener
-- So you don't hear yourself, put your own character's emitter in a group this
-- listener doesn't join. The change is local only; other clients still hear you.
--   ownEmitter.AudioInteractionGroup = "Self"
]]

------------------------------------------------------------------------------
-- C. Client: who is talking? AudioAnalyzer works on clients only, and spectrum
--    analysis is blocked for voice. RmsLevel and PeakLevel still report loudness.
------------------------------------------------------------------------------
--[[
local RunService = game:GetService("RunService")
local function watchSpeaking(device: AudioDeviceInput, onLevel: (number) -> ())
	local analyzer = Instance.new("AudioAnalyzer")
	analyzer.SpectrumEnabled = false
	analyzer.Parent = device
	local w = Instance.new("Wire")
	w.SourceInstance = device
	w.TargetInstance = analyzer
	w.Parent = analyzer
	RunService.Heartbeat:Connect(function()
		onLevel(if device.Active and not device.Muted then analyzer.RmsLevel else 0)
	end)
end
]]
