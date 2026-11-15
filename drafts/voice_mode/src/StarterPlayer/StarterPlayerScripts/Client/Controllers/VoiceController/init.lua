--[[
	VoiceController - Proximity Voice on this client (docs/design/VoiceMode.md). Behind Config.Voice.Enabled: while that is
	false it does nothing.

	VoiceService (server) decides who may hear whom; nothing here can widen that (the access lists are the server's).
	This controller decides how voice sounds on this client and draws the voice UI. Two graphs (Config.Voice.ClientGraph):
	  * "Default" (the safe setting, until the published safety gate passes): Roblox's own listener and playback stay as
	    Roblox built them. We only give Roblox's emitter on each speaker's character our distance curve (the profile of
	    where you listen), and move it to the silent group "VoiceOff" while you mute that player, they are blocked, or you
	    turned voice off. We move it back once, and only if nothing else changed it meanwhile: this controller can make
	    Roblox's voice quieter, never louder than Roblox left it.
	  * "Custom": our own AudioListener (group "Voice") on an Attachment of ours under workspace.Terrain, moved every
	    frame to your camera or, while you spectate, to the watched contender's head facing your camera
	    (Spectators.ListenAt). Per speaker: their voice device -> a fader (your mute, a block, muffling) -> an
	    AudioEqualizer -> our own AudioEmitter on another Attachment of ours, moved every frame to their head. Nothing of
	    ours lives inside another player's character, so a character that is destroyed or streams out can't take our
	    listener with it. Roblox's emitters go to "VoiceOff" on this client only, so no voice is heard twice. The
	    listener's curve does the falloff; walls and terrain muffle (Config.Voice.Occlusion).
	  * The stands' channel (Spectators.StandsBus, off until the gate passes): while you spectate, every other spectator
	    comes in with no distance, through the same per-speaker fader (your mutes and blocks apply).
	Your choice: the lobby card, the VOICE panel and Settings › VOICE all call setOn, the only path that sends SetVoice.
	Turning voice off mutes your own device on this client at once (as Roblox's push-to-talk sample does) and keeps it
	muted while your choice is off, whatever arrives from the server. What the UI shows comes from the server's VoiceOn /
	VoiceHold attributes: before you choose this session, voice stays off until your saved choice has loaded, and stays
	off if it couldn't load (the card says so). If the server still shows something else 2 s after you chose, the choice
	is sent again.
	Safety: Roblox's own mute, block, report and voice volume controls are Roblox's. This client also honours blocks
	(StarterGui:GetCore "GetBlockedUserIds" and the PlayerBlocked / PlayerUnblocked events) and Roblox's mute events in
	every graph. Whether Roblox's own mute and volume reach the "Custom" chain isn't documented: that is the safety gate.
	Talking lights: an AudioAnalyzer per voice reads RmsLevel only (Roblox blocks spectra for voice). Levels never leave
	this client: nothing is recorded, transcribed or sent anywhere.
	Public API (Controllers.VoiceController):
	  isAvailable() -> boolean        isOn() -> boolean          setOn(on: boolean)          hasOwnVolume() -> boolean
	  isMuted(player) -> boolean      setMuted(player, muted)    mutedCount() -> number
	  openPanel()   closePanel()      getTalkers() -> { { player: Player, level: number, tag: string } }
	  debugState() -> { [string]: any }
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local VoiceChatService = game:GetService("VoiceChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Input = require(Shared:WaitForChild("Input"))
local Lore = require(Shared:WaitForChild("Lore"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
-- (timeouts, so a missing child makes this one controller fail to load instead of stalling the client's loader)
local Curves = require(script:WaitForChild("Curves", 10))
local Hud = require(script:WaitForChild("Hud", 10))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local VoiceCfg = Config.Voice or {}
local Profiles = VoiceCfg.Profiles or {}
local Occ = VoiceCfg.Occlusion or {}
local Spect = VoiceCfg.Spectators or {}
local WhisperCfg = VoiceCfg.Whisper or {}
local GRAPH = if VoiceCfg.ClientGraph == "Custom" then "Custom" else "Default"
local STANDS_BUS = Spect.StandsBus == true
local OWN_GAIN = GRAPH == "Custom" or STANDS_BUS -- each speaker has a fader of ours (your mutes and blocks reach it)

local GROUP_VOICE = "Voice" -- the only group our listener hears
local GROUP_OFF = "VoiceOff" -- nothing listens here: Roblox's emitters (Custom), silenced voices (Default)
local OUR_EMITTER = "ProximityVoiceEmitter"
local LEGACY_AFTER = 20 -- seconds a voice-enabled player can go without a device: the place runs Roblox's old voice
local ENGINE_SEARCH_INTERVAL = 3 -- seconds between searches for Roblox's emitter on a character that has none yet
local RESEND_AFTER = 2 -- seconds before your choice is sent again if the server still shows something else
local PARKED = Vector3.new(0, -50000, 0) -- where an emitter of ours waits while its speaker has no head (far out of earshot)
local TICK = 0.1

local VoiceController = {}
local Controllers: any = nil

local enabled = false
local startedAt = 0
local available: boolean? = nil -- this account can use voice here (nil until Roblox says)
local checkDone = false -- the availability check has finished (it may have failed: then available stays nil)
local myDevice: AudioDeviceInput? = nil
local myAnalyzer: AudioAnalyzer? = nil
local myMutedConn: RBXScriptConnection? = nil
local myTalkingUntil = 0
local rootFolder: Folder? = nil
local listener: AudioListener? = nil
local listenerWire: Wire? = nil
local ear: Attachment? = nil -- our own Attachment under workspace.Terrain: where our listener hears from
local mainFader: AudioFader? = nil
local standsFader: AudioFader? = nil
local speakers: { [Player]: any } = {}
local muted: { [number]: boolean } = {} -- UserIds you muted here (this server only)
local blocked: { [number]: boolean } = {} -- UserIds you blocked on Roblox (StarterGui GetCore)
local robloxMuted: { [number]: boolean } = {} -- UserIds Roblox reports you muted (PlayerMutedEvent)
local profileName = ""
local curveCache: { [string]: { [number]: number } } = {}
local standsActive = false
local explicitChoice: boolean? = nil -- what you chose this session (setOn); nil = follow the server (your saved choice)
local lastSendAt = -math.huge
local zones: { BasePart } = {}
local talkers: { any } = {}
local tipsShown: { [number]: boolean } = {}
local whisperBound = false
local whisperHeld = false
local cardKey = ""
local warned: { [string]: boolean } = {}
local lastDebug = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------
local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[VoiceController] " .. message)
end

-- Each step runs on its own: one failing step never stops the others (or the next pass).
local function guarded(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warnOnce(name .. ":" .. tostring(err), name .. " failed: " .. tostring(err))
	end
end

local function volumeSetting(): number
	return math.clamp(tonumber(ClientState.settings.voiceVolume) or 1, 0, 2)
end

local function roleOf(p: Player): string
	local role = p:GetAttribute("VoiceRole")
	return if type(role) == "string" then role else "Open"
end

local function wire(source: Instance, target: Instance, parent: Instance): Wire
	local w = Instance.new("Wire")
	w.SourceInstance = source
	w.TargetInstance = target
	w.Parent = parent
	return w
end

local function headOf(p: Player?): BasePart?
	local character = p and p.Character
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function findDevice(p: Player): AudioDeviceInput?
	for _, child in ipairs(p:GetChildren()) do
		if child:IsA("AudioDeviceInput") then
			return child :: AudioDeviceInput
		end
	end
	return nil
end

-- Roblox's own voice emitter on a character (a direct child named AudioEmitter in the default setup)
local function engineEmitterOf(character: Model?): AudioEmitter?
	if not character then
		return nil
	end
	local direct = character:FindFirstChild("AudioEmitter")
	if direct and direct:IsA("AudioEmitter") then
		return direct
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("AudioEmitter") and d.Name ~= OUR_EMITTER then
			return d
		end
	end
	return nil
end

local function curveFor(name: string): { [number]: number }
	local cached = curveCache[name]
	if cached then
		return cached
	end
	local points = Curves.build(Profiles[name] or Profiles.Arena)
	curveCache[name] = points
	return points
end

local function newAnalyzer(name: string, parent: Instance): AudioAnalyzer
	local analyzer = Instance.new("AudioAnalyzer")
	analyzer.Name = name
	pcall(function()
		(analyzer :: any).SpectrumEnabled = false -- loudness only (Roblox blocks voice spectra anyway)
	end)
	analyzer.Parent = parent
	return analyzer
end

local function readLevel(analyzer: AudioAnalyzer?): number
	if not analyzer then
		return 0
	end
	local ok, value = pcall(function()
		return analyzer.RmsLevel
	end)
	return if ok and type(value) == "number" then value else 0
end

local function micActive(): boolean
	local device = myDevice
	if not device then
		return false
	end
	local ok, active = pcall(function()
		return device.Active -- Roblox's own mic toggle (readable; only Roblox sets it)
	end)
	return ok and active == true
end

--------------------------------------------------------------------------------------------------------------------
-- Your choice (the server's VoiceOn / VoiceHold, and what you chose this session)
--------------------------------------------------------------------------------------------------------------------
local function serverOn(): boolean
	return player:GetAttribute("VoiceOn") == true
end

-- why the server keeps you muted before you choose: "" | "Loading" | "NotLoaded"
local function holdReason(): string
	local hold = player:GetAttribute("VoiceHold")
	return if type(hold) == "string" then hold else "Loading"
end

-- What you chose this session, else what the server applied (your saved choice once it loaded; off until then).
local function isOnNow(): boolean
	if explicitChoice ~= nil then
		return explicitChoice
	end
	return serverOn()
end

local function silenced(p: Player): boolean
	local id = p.UserId
	return muted[id] == true or blocked[id] == true or robloxMuted[id] == true
end

local function settingsReady(): boolean
	return player:GetAttribute("SettingsLoaded") == true and player:GetAttribute("SettingsJson") ~= nil
end

--------------------------------------------------------------------------------------------------------------------
-- Listening: our listener and ear (Custom), the volume faders, the stands' bus
--------------------------------------------------------------------------------------------------------------------
local function buildGraph()
	local folder = Instance.new("Folder")
	folder.Name = "ProximityVoice"
	folder.Parent = SoundService
	rootFolder = folder

	if GRAPH == "Custom" then
		local out = Instance.new("AudioDeviceOutput")
		out.Name = "VoiceOut"
		out.Parent = folder
		local fader = Instance.new("AudioFader")
		fader.Name = "VoiceVolume"
		fader.Volume = 0 -- silent until applyVolumes knows your choice
		fader.Parent = folder
		wire(fader, out, folder)
		mainFader = fader
	end
	if STANDS_BUS then
		local standsOut = Instance.new("AudioDeviceOutput")
		standsOut.Name = "StandsOut"
		standsOut.Parent = folder
		local stands = Instance.new("AudioFader")
		stands.Name = "StandsVolume"
		stands.Volume = 0
		stands.Parent = folder
		wire(stands, standsOut, folder)
		standsFader = stands
	end
end

-- Our ear is an Attachment of our own under workspace.Terrain (followCamera moves it every frame); the listener lives in
-- it. Rebuilt whenever something removed either.
local function ensureListener()
	local fader, root = mainFader, rootFolder
	if GRAPH ~= "Custom" or not (fader and root) then
		return
	end
	local terrain = workspace.Terrain
	local a = ear
	if not (a and a.Parent == terrain) then
		if a then
			pcall(function()
				(a :: Attachment):Destroy()
			end)
		end
		local fresh = Instance.new("Attachment")
		fresh.Name = "ProximityVoiceEar"
		fresh.Parent = terrain
		a = fresh
		ear = fresh
	end
	local l, w = listener, listenerWire
	if l and l.Parent == a and w and w.Parent == root then
		return
	end
	if l then
		pcall(function()
			(l :: AudioListener):Destroy()
		end)
	end
	if w then
		pcall(function()
			(w :: Wire):Destroy()
		end)
	end
	local fresh = Instance.new("AudioListener")
	fresh.Name = "ProximityVoiceListener"
	fresh.AudioInteractionGroup = GROUP_VOICE
	fresh.Parent = a
	listener = fresh
	listenerWire = wire(fresh, fader, root)
	profileName = "" -- the new listener needs its curve (updateProfile)
end

local function listenHead(): BasePart?
	local target = ClientState.spectating
	if target and Spect.ListenAt ~= "Camera" then
		local head = headOf(target)
		if head and head.Parent then
			return head
		end
	end
	return nil
end

-- Every frame (Custom): the ear sits at your camera, or at the watched contender's head turned with your camera, so
-- left and right stay where you look.
local function followCamera()
	local a = ear
	if not (a and a.Parent) then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local head = listenHead()
	if head then
		a.WorldCFrame = CFrame.new(head.Position) * camera.CFrame.Rotation
	else
		a.WorldCFrame = camera.CFrame
	end
end

local function listenerPosition(): Vector3?
	local a = ear
	if a and a.Parent then
		return a.WorldPosition
	end
	local camera = workspace.CurrentCamera -- Default: Roblox's own listener follows the camera
	return if camera then camera.CFrame.Position else nil
end

local function applyVolumes()
	local volume = if isOnNow() then volumeSetting() else 0
	local fader = mainFader
	if fader then
		local main = volume
		if ClientState.spectating and Spect.HearArena == false then
			main = 0
		end
		if fader.Volume ~= main then
			fader.Volume = main
		end
	end
	local stands = standsFader
	if stands then
		local value = if standsActive then volume * math.clamp(tonumber(Spect.Volume) or 0.85, 0, 2) else 0
		if stands.Volume ~= value then
			stands.Volume = value
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Places: profiles and rooms (VoiceZone parts)
--------------------------------------------------------------------------------------------------------------------
local function addZone(part: Instance)
	if part:IsA("BasePart") and not table.find(zones, part) then
		table.insert(zones, part)
	end
end

local function removeZone(part: Instance)
	local index = table.find(zones, part :: any)
	if index then
		table.remove(zones, index)
	end
end

local function zoneAt(position: Vector3): BasePart?
	for _, part in ipairs(zones) do
		if part.Parent then
			local rel = part.CFrame:PointToObjectSpace(position)
			local half = part.Size * 0.5
			if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
				return part
			end
		end
	end
	return nil
end

local function roomAt(position: Vector3): string?
	local zone = zoneAt(position)
	local room = zone and zone:GetAttribute("VoiceRoom")
	return if type(room) == "string" and room ~= "" then room else nil
end

local function pickProfile(position: Vector3?): string
	local zone = if position then zoneAt(position) else nil
	local zoneProfile = zone and zone:GetAttribute("VoiceProfile")
	if type(zoneProfile) == "string" and Profiles[zoneProfile] then
		return zoneProfile
	end
	if ClientState.spectating or ClientState.inArena then
		local name = (VoiceCfg.PhaseProfiles or {})[GameState:GetAttribute("Phase")]
		return if type(name) == "string" and Profiles[name] then name else "Arena"
	end
	return "Social"
end

local applySpeaker: (any) -> () -- (below)

local function updateProfile()
	local name = pickProfile(listenerPosition())
	if name == profileName then
		return
	end
	profileName = name
	local l = listener
	if l and l.Parent then
		l:SetDistanceAttenuation(curveFor(name))
	end
	if GRAPH == "Default" then
		-- there is no listener of ours: the place's curve goes on Roblox's emitters instead
		for _, s in pairs(speakers) do
			applySpeaker(s)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Speakers
--------------------------------------------------------------------------------------------------------------------
local function destroy(instance: Instance?)
	if instance then
		pcall(function()
			instance:Destroy()
		end)
	end
end

local function clearChain(s)
	destroy(s.standsWire)
	destroy(s.emitter)
	destroy(s.anchor)
	destroy(s.folder)
	s.standsWire, s.emitter, s.anchor, s.folder, s.emitterWire = nil, nil, nil, nil, nil
	s.analyzer, s.fader, s.eq, s.out = nil, nil, nil, nil
	s.curveKey, s.curveOn = "", nil
end

local function buildChain(s)
	clearChain(s)
	local device, root = s.device, rootFolder
	if not (device and root) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Speaker" .. s.player.UserId
	folder.Parent = root
	s.folder = folder
	s.analyzer = newAnalyzer("Level", folder)
	wire(device, s.analyzer, folder)
	if not OWN_GAIN then
		return -- Default without the stands' bus: Roblox's own path plays them; we only measure the talking light
	end
	local fader = Instance.new("AudioFader")
	fader.Name = "Gain"
	fader.Volume = 0 -- silent until applyGain decides
	fader.Parent = folder
	wire(device, fader, folder)
	s.fader, s.out = fader, fader
	if GRAPH == "Custom" then
		local eq = Instance.new("AudioEqualizer")
		local toneOk = pcall(function()
			eq.HighGain = 0
			eq.MidGain = 0
		end)
		if toneOk then
			eq.Name = "Muffle"
			eq.Parent = folder
			wire(fader, eq, folder)
			s.eq, s.out = eq, eq
		else
			eq:Destroy() -- no equalizer gains in this build: muffling is volume only
		end
	end
end

-- The speaker's character: Roblox's emitter on it, and their head (where our emitter goes, Custom).
local function refreshCharacter(s)
	local character = s.player.Character
	local now = os.clock()
	if character ~= s.character then
		s.character = character
		s.engineEmitter = engineEmitterOf(character)
		s.engineSaved = nil -- (it belonged to the old character's emitter)
		s.nextSearch = now + ENGINE_SEARCH_INTERVAL
	elseif not (s.engineEmitter and s.engineEmitter.Parent) and now >= s.nextSearch then
		s.engineEmitter = engineEmitterOf(character)
		s.nextSearch = now + ENGINE_SEARCH_INTERVAL
	end
	local head = headOf(s.player)
	s.head = head
	local a = s.anchor
	if a and a.Parent then
		a.WorldPosition = if head then head.Position else PARKED -- (moveAnchors keeps it there every frame)
	end
end

-- Custom: our own emitter for this speaker, on an Attachment of ours under workspace.Terrain that moveAnchors keeps at
-- their head. Rebuilt whenever something removed it.
local function attachEmitter(s)
	if GRAPH ~= "Custom" or not (s.out and s.folder) then
		return
	end
	local terrain = workspace.Terrain
	local a = s.anchor
	if not (a and a.Parent == terrain) then
		destroy(a)
		destroy(s.emitter)
		a = Instance.new("Attachment")
		a.Name = "PV_" .. s.player.UserId
		a.Parent = terrain
		s.anchor = a
		s.emitter = nil
		local head = s.head
		-- (a new Attachment sits at the world origin, the Spire: never let a voice start there)
		a.WorldPosition = if head and head.Parent then head.Position else PARKED
	end
	local emitter = s.emitter
	if emitter and emitter.Parent == a and s.emitterWire and s.emitterWire.Parent == s.folder then
		return
	end
	destroy(emitter)
	destroy(s.emitterWire)
	local fresh = Instance.new("AudioEmitter")
	fresh.Name = OUR_EMITTER
	fresh.AudioInteractionGroup = GROUP_VOICE
	pcall(function()
		(fresh :: any).DistanceAttenuationMode = (Enum :: any).DistanceAttenuationMode.Custom -- (the default, made sure)
	end)
	fresh:SetDistanceAttenuation(Curves.FLAT)
	fresh.Parent = a
	s.emitterWire = wire(s.out, fresh, s.folder)
	s.emitter = fresh
	s.curveKey = "F"
end

-- Roblox's own emitter on the speaker's character. We may always move it to the silent group; we move it back only to
-- undo our own change, once, and only if nothing else changed it meanwhile.
local function silenceEngine(s, silent: boolean)
	local engine = s.engineEmitter
	if not (engine and engine.Parent) then
		return
	end
	if silent then
		if engine.AudioInteractionGroup ~= GROUP_OFF then
			s.engineSaved = { emitter = engine, group = engine.AudioInteractionGroup }
			engine.AudioInteractionGroup = GROUP_OFF
		end
	else
		local saved = s.engineSaved
		s.engineSaved = nil
		if saved and saved.emitter == engine and engine.AudioInteractionGroup == GROUP_OFF then
			engine.AudioInteractionGroup = saved.group
		end
	end
end

-- The hot path (muffling changes): this speaker's gain and tone only.
local function applyGain(s)
	local fader, eq = s.fader, s.eq
	if not fader then
		return
	end
	local gain = 0
	if not (silenced(s.player) or not isOnNow()) then
		if GRAPH ~= "Custom" then
			gain = 1 -- (Default: this fader only feeds the stands' bus)
		elseif s.standsWire or (s.head and s.head.Parent) then
			local keep = math.clamp(tonumber(Occ.Volume) or 0.55, 0, 1)
			gain = 1 - (1 - keep) * s.occlusion
		end
	end
	if math.abs(fader.Volume - gain) > 0.001 then
		fader.Volume = gain
	end
	if eq then
		local high = (tonumber(Occ.HighGainDb) or -24) * s.occlusion
		local mid = (tonumber(Occ.MidGainDb) or -6) * s.occlusion
		if math.abs(eq.HighGain - high) > 0.05 then
			eq.HighGain = high
		end
		if math.abs(eq.MidGain - mid) > 0.05 then
			eq.MidGain = mid
		end
	end
end

local function wantsStands(s): boolean
	return STANDS_BUS
		and standsActive
		and not silenced(s.player)
		and s.player:GetAttribute("Spectating") == true
		and roleOf(s.player) ~= "Contender"
end

function applySpeaker(s)
	local whisper = s.player:GetAttribute("VoiceWhisper") == true
	if GRAPH == "Custom" then
		silenceEngine(s, true) -- this client plays the voice through our own emitter: never heard twice
		local emitter = s.emitter
		local key = if whisper then "W" else "F"
		if emitter and emitter.Parent and s.curveKey ~= key then
			s.curveKey = key
			emitter:SetDistanceAttenuation(if whisper then curveFor("Whisper") else Curves.FLAT)
		end
	else
		local silent = silenced(s.player) or not isOnNow()
		silenceEngine(s, silent)
		local engine = s.engineEmitter
		if engine and engine.Parent and not silent then
			-- Roblox's emitter carries the place's curve itself (there is no listener of ours)
			local curveKey = (if whisper then "W" else "F") .. profileName
			if s.curveOn ~= engine or s.curveKey ~= curveKey then
				s.curveOn, s.curveKey = engine, curveKey
				local curve = if whisper then curveFor("Whisper") else curveFor(if profileName ~= "" then profileName else "Social")
				pcall(function()
					(engine :: any).DistanceAttenuationMode = (Enum :: any).DistanceAttenuationMode.Custom
				end)
				pcall(function()
					engine:SetDistanceAttenuation(curve)
				end)
			end
		end
	end
	-- the stands' channel (StandsBus): spectators hear each other with no distance, through this speaker's fader
	local source, bus = s.fader, standsFader
	local want = wantsStands(s) and source ~= nil and bus ~= nil
	if want and not (s.standsWire and s.standsWire.Parent) then
		s.standsWire = wire(source, bus :: AudioFader, (s.folder or rootFolder) :: Instance)
	elseif not want and s.standsWire then
		destroy(s.standsWire)
		s.standsWire = nil
	end
	applyGain(s)
end

local function setSpeakerDevice(s, device: AudioDeviceInput?)
	if s.device == device and (device == nil or s.folder ~= nil) then
		return
	end
	s.device = device
	buildChain(s)
	refreshCharacter(s)
	attachEmitter(s)
	applySpeaker(s)
end

-- maintain(): the backstop for anything an event missed (a new device, a respawn, a removed chain)
local function refreshSpeaker(s)
	local device = findDevice(s.player)
	if device ~= s.device then
		setSpeakerDevice(s, device)
	elseif s.device and not (s.folder and s.folder.Parent == rootFolder) then
		buildChain(s) -- something removed our chain for this speaker: build it again
	end
	refreshCharacter(s)
	attachEmitter(s)
	applySpeaker(s)
end

local function trackPlayer(p: Player)
	if p == player or speakers[p] then
		return
	end
	local s = {
		player = p,
		device = nil :: AudioDeviceInput?,
		folder = nil :: Folder?,
		analyzer = nil :: AudioAnalyzer?,
		fader = nil :: AudioFader?,
		eq = nil :: AudioEqualizer?,
		out = nil :: Instance?, -- the node that feeds our emitter (the equalizer, or the fader without one)
		anchor = nil :: Attachment?, -- ours, under workspace.Terrain, kept at their head (Custom)
		emitter = nil :: AudioEmitter?,
		emitterWire = nil :: Wire?,
		engineEmitter = nil :: AudioEmitter?,
		engineSaved = nil :: { [string]: any }?, -- the group we moved Roblox's emitter from (silenceEngine)
		standsWire = nil :: Wire?,
		character = nil :: Model?,
		head = nil :: BasePart?,
		nextSearch = 0,
		curveKey = "",
		curveOn = nil :: AudioEmitter?,
		occlusion = 0,
		occlusionTarget = 0,
		level = 0,
		talkingUntil = 0,
		audible = 0,
		conns = {} :: { RBXScriptConnection },
		charConn = nil :: RBXScriptConnection?,
	}
	speakers[p] = s
	local function hookCharacter(character: Model?)
		if s.charConn then
			s.charConn:Disconnect()
			s.charConn = nil
		end
		if character then
			s.charConn = character.ChildAdded:Connect(function(child)
				guarded("character", function()
					if child:IsA("AudioEmitter") and child.Name ~= OUR_EMITTER then
						s.engineEmitter = child
						s.engineSaved = nil
						applySpeaker(s) -- (Custom: moved out of earshot at once, so nobody is heard twice)
					elseif child.Name == "Head" then
						refreshCharacter(s)
						attachEmitter(s)
						applySpeaker(s)
					end
				end)
			end)
		end
		guarded("character", function()
			refreshCharacter(s)
			attachEmitter(s)
			applySpeaker(s)
		end)
	end
	table.insert(s.conns, p.ChildAdded:Connect(function(child)
		if child:IsA("AudioDeviceInput") then
			guarded("device", function()
				setSpeakerDevice(s, findDevice(p))
			end)
		end
	end))
	table.insert(s.conns, p.ChildRemoved:Connect(function(child)
		if child == s.device then
			guarded("device", function()
				setSpeakerDevice(s, findDevice(p))
			end)
		end
	end))
	table.insert(s.conns, p.CharacterAdded:Connect(hookCharacter))
	for _, attribute in ipairs({ "VoiceWhisper", "Spectating", "VoiceRole" }) do
		table.insert(s.conns, p:GetAttributeChangedSignal(attribute):Connect(function()
			guarded("speaker", function()
				applySpeaker(s)
			end)
		end))
	end
	guarded("device", function()
		setSpeakerDevice(s, findDevice(p))
	end)
	hookCharacter(p.Character)
end

local function untrackPlayer(p: Player)
	local s = speakers[p]
	if not s then
		return
	end
	speakers[p] = nil
	for _, connection in ipairs(s.conns) do
		connection:Disconnect()
	end
	if s.charConn then
		s.charConn:Disconnect()
	end
	clearChain(s) -- your mute stays (by UserId) in case they come back to this server
end

-- Every frame (Custom): our emitters follow their speakers' heads. A head that went away (destroyed, streamed out)
-- parks that emitter and silences it until refreshCharacter finds the new one.
local function moveAnchors()
	for _, s in pairs(speakers) do
		local a, head = s.anchor, s.head
		if a and head and a.Parent then
			if head.Parent then
				a.WorldPosition = head.Position
			else
				s.head = nil
				a.WorldPosition = PARKED
				applyGain(s)
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Your own device
--------------------------------------------------------------------------------------------------------------------
-- While your choice is off (or the server hasn't opened your mic yet) this client keeps your own device muted too, as
-- Roblox's push-to-talk sample does: OFF takes effect at once, and a server write arriving late can't reopen it.
local function syncLocalMute()
	local device = myDevice
	if not device then
		return
	end
	local want = not (isOnNow() and serverOn())
	pcall(function()
		if device.Muted ~= want then
			device.Muted = want
		end
	end)
end

local function setMyDevice(device: AudioDeviceInput?)
	if device == myDevice then
		return
	end
	if myMutedConn then
		myMutedConn:Disconnect()
		myMutedConn = nil
	end
	myDevice = device
	if myAnalyzer then
		myAnalyzer:Destroy()
		myAnalyzer = nil
	end
	local root = rootFolder
	if device and root then
		local analyzer = newAnalyzer("You", root)
		wire(device, analyzer, analyzer) -- your talking light; it measures your mic and goes nowhere else
		myAnalyzer = analyzer
		available = true -- Roblox only makes a device for players who can use voice
		myMutedConn = device:GetPropertyChangedSignal("Muted"):Connect(syncLocalMute)
		syncLocalMute()
	end
end

local function updateStands()
	local on = STANDS_BUS and ClientState.spectating ~= nil and roleOf(player) ~= "Contender"
	if on ~= standsActive then
		standsActive = on
		for _, s in pairs(speakers) do
			applySpeaker(s)
		end
	end
	applyVolumes()
end

--------------------------------------------------------------------------------------------------------------------
-- Walls, terrain and rooms (Custom)
--------------------------------------------------------------------------------------------------------------------
local function characterList(): { Instance }
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function occlusionPass()
	local origin = listenerPosition()
	if not origin or GRAPH ~= "Custom" then
		return -- (muffling needs our own per-speaker fader and equalizer)
	end
	local profile = Profiles[profileName] or Profiles.Arena or {}
	local reach = tonumber(profile.Silent) or 90
	local rays = Occ.Mode == "Raycast" and (Occ.Profiles or { Arena = true, Cabin = true })[profileName] == true
	local myRoom = roomAt(origin)
	local near = {}
	for _, s in pairs(speakers) do
		local target = 0
		local head = s.head
		if head and head.Parent and s.device and not s.standsWire then
			local offset = head.Position - origin
			local distance = offset.Magnitude
			if distance < reach then
				local theirRoom = roomAt(head.Position)
				if (myRoom or theirRoom) and myRoom ~= theirRoom then
					target = 1 -- another room (a train car): through the wall
				elseif rays then
					table.insert(near, { s = s, distance = distance, offset = offset })
					target = s.occlusionTarget -- the ray below decides
				end
			end
		end
		s.occlusionTarget = target
	end
	if #near == 0 then
		return
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	rayParams.FilterDescendantsInstances = characterList()
	local maxRays = math.max(1, math.floor(tonumber(Occ.MaxRays) or 8))
	for i, entry in ipairs(near) do
		if i > maxRays then
			entry.s.occlusionTarget = 0
		else
			local hit = workspace:Raycast(origin, entry.offset, rayParams)
			entry.s.occlusionTarget = if hit then 1 else 0
		end
	end
end

local function smoothOcclusion(dt: number)
	local k = Util.damp(tonumber(Occ.Smoothing) or 6, dt)
	for _, s in pairs(speakers) do
		local diff = s.occlusionTarget - s.occlusion
		if diff ~= 0 then
			if math.abs(diff) < 0.003 then
				s.occlusion = s.occlusionTarget
			else
				s.occlusion += diff * k
			end
			applyGain(s)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Talking, state and UI
--------------------------------------------------------------------------------------------------------------------
local function audibility(s): number
	if silenced(s.player) or not isOnNow() then
		return 0
	end
	if s.standsWire then
		return 1
	end
	local l, emitter = listener, s.emitter
	if GRAPH == "Custom" and emitter and emitter.Parent and l and l.Parent then
		local ok, value = pcall(function()
			return (emitter :: any):GetAudibilityFor(l)
		end)
		if ok and type(value) == "number" then
			return value
		end
	end
	local origin, head = listenerPosition(), s.head
	if not (origin and head and head.Parent) then
		return 0
	end
	local profile = if s.player:GetAttribute("VoiceWhisper") == true then Profiles.Whisper else (Profiles[profileName] or Profiles.Social)
	local keep = math.clamp(tonumber(Occ.Volume) or 0.55, 0, 1)
	return Curves.value(profile, (head.Position - origin).Magnitude) * (1 - (1 - keep) * s.occlusion)
end

local function talkPass()
	local now = os.clock()
	local threshold = tonumber(VoiceCfg.TalkingLevel) or 0.02
	local hold = tonumber(VoiceCfg.TalkingHold) or 0.45
	local minAudible = tonumber(VoiceCfg.MinAudibility) or 0.04
	if readLevel(myAnalyzer) > threshold then
		myTalkingUntil = now + hold
	end
	local list = {}
	for p, s in pairs(speakers) do
		if s.analyzer and not silenced(p) then
			s.level = readLevel(s.analyzer) -- silence when the server doesn't let you hear them
			if s.level > threshold then
				s.talkingUntil = now + hold
			end
		else
			s.level = 0
			s.talkingUntil = 0
		end
		if s.talkingUntil > now then
			s.audible = audibility(s)
			if s.audible >= minAudible then
				table.insert(list, s)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.audible * math.max(a.level, 0.005) > b.audible * math.max(b.level, 0.005)
	end)
	talkers = list
end

local function spectatorsWatching(): number
	local n = 0
	for p in pairs(speakers) do
		if p:GetAttribute("Spectating") == true and roleOf(p) ~= "Contender" then
			n += 1
		end
	end
	return n
end

-- Who can hear you: "Nearby" | "Stands" | "Whisper" | "Off" | "" (no voice on this account)
local function channel(): string
	if available == false then
		return ""
	end
	if not isOnNow() then
		return "Off"
	end
	local role = roleOf(player)
	if role == "Bench" then
		return "Stands"
	end
	if player:GetAttribute("VoiceWhisper") == true then
		return "Whisper"
	end
	return "Nearby"
end

local function isLegacy(): boolean
	return available == true and myDevice == nil and os.clock() - startedAt > LEGACY_AFTER
end

local function chipText(): (string, boolean)
	local ch = channel()
	if ch == "Off" then
		local loading = explicitChoice == nil and holdReason() == "Loading"
		local text = if loading then "VOICE · LOADING YOUR SETTING" else "VOICE OFF"
		return text, true
	end
	local label = if ch == "Stands" then Lore.upper("Stands") elseif ch == "Whisper" then "WHISPER · ALLIES ONLY" else "NEARBY"
	if ch == "Stands" and ClientState.spectating and STANDS_BUS then
		local n = spectatorsWatching()
		if n > 0 then
			label ..= string.format(" · %d WATCHING", n)
		end
	end
	if not serverOn() or not micActive() then
		return "MIC OFF · " .. label, true
	end
	return "VOICE · " .. label, false
end

local function cardState(): { [string]: any }
	local mode = GameState:GetAttribute("VoiceMode")
	local title = if mode == "VoiceOnly" then "VOICE-ONLY SERVER" else "PROXIMITY VOICE"
	local serversCfg = VoiceCfg.VoiceServers or {}
	local server = nil
	if serversCfg.Enabled == true and available == true then
		server = if mode == "VoiceOnly" then "Leave" else "Join"
	end
	if available == false then
		return { title = title, text = "Not on your account. Roblox voice needs its 13+ age check; text chat works as usual." }
	end
	if not myDevice then
		local text = if available == nil and checkDone then "Couldn't reach Roblox voice just now. Text chat works as usual."
			elseif available == nil then "Checking your voice settings…"
			elseif isLegacy() then "Roblox's standard voice is on here."
			else "Connecting to voice…"
		return { title = title, text = text, server = server }
	end
	if explicitChoice == nil then
		local hold = holdReason()
		if hold == "Loading" then
			return { title = title, text = "Loading your voice setting… voice stays off until it's in.", server = server }
		elseif hold == "NotLoaded" then
			return {
				title = title,
				text = "Off · your saved setting didn't load. Turn voice on to talk and listen.",
				toggle = true,
				on = false,
				players = true,
				mutedCount = VoiceController.mutedCount(),
				server = server,
			}
		end
	end
	local on = isOnNow()
	return {
		title = title,
		text = if on then "On · players near you hear you. In a round, the fallen only hear each other."
			else "Off · you don't hear voice, and nobody hears you.",
		toggle = true,
		on = on,
		players = true,
		mutedCount = VoiceController.mutedCount(),
		server = server,
	}
end

local function panelState(): { [string]: any }
	local entries = {}
	local now = os.clock()
	for p, s in pairs(speakers) do
		if s.device then
			table.insert(entries, {
				player = p,
				muted = muted[p.UserId] == true,
				blocked = blocked[p.UserId] == true,
				talking = s.talkingUntil > now,
			})
		end
	end
	table.sort(entries, function(a, b)
		local an, bn = string.lower(a.player.DisplayName), string.lower(b.player.DisplayName)
		if an ~= bn then
			return an < bn
		end
		return a.player.UserId < b.player.UserId
	end)
	local card = cardState()
	return { text = card.text, toggle = card.toggle == true, on = card.on == true, rows = entries }
end

local function stackVisible(): boolean
	if available ~= true or not myDevice or ClientState.menuOpen then
		return false
	end
	return ClientState.inArena or ClientState.spectating ~= nil
end

local function render()
	local visible = stackVisible()
	Hud.setStackVisible(visible)
	if visible then
		local text, dim = chipText()
		Hud.setChip(text, myTalkingUntil > os.clock() and micActive() and serverOn(), dim)
		local hideNames = VoiceCfg.ShowTalkerNames == false and roleOf(player) == "Contender"
		local rows = {}
		for _, s in ipairs(talkers) do
			local tag = if s.standsWire then "SPECTATOR" elseif s.player:GetAttribute("VoiceWhisper") == true then "WHISPER" else ""
			table.insert(rows, {
				name = if hideNames and tag == "" then "SOMEONE NEARBY" else s.player.DisplayName,
				tag = tag,
				level = s.level,
			})
		end
		Hud.setTalkers(rows)
	end
	local card = cardState()
	local key = table.concat({
		tostring(card.title), tostring(card.text), tostring(card.toggle), tostring(card.on), tostring(card.players),
		tostring(card.mutedCount), tostring(card.server),
	}, "|")
	if key ~= cardKey then
		cardKey = key
		Hud.setCard(card)
	end
	if Hud.isPanelOpen() then
		Hud.setPanel(panelState())
	end
end

local function publishState()
	local v = ClientState.voice
	if type(v) ~= "table" then
		return
	end
	local fields = {
		available = available == true,
		connected = myDevice ~= nil,
		on = isOnNow(),
		hold = if explicitChoice == nil then holdReason() else "",
		micOn = micActive(),
		talking = myTalkingUntil > os.clock() and micActive() and serverOn(),
		channel = channel(),
		watching = if STANDS_BUS then spectatorsWatching() else 0,
	}
	local changed = false
	for key, value in pairs(fields) do
		if v[key] ~= value then
			v[key] = value
			changed = true
		end
	end
	if changed and ClientState.voiceChanged then
		ClientState.voiceChanged:Fire(v)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- One-line tips (each shown at most Config.Voice.TipRepeats times per player; counters in settings.voiceTips)
--------------------------------------------------------------------------------------------------------------------
local TIPS = {
	[0] = { text = "PROXIMITY VOICE IS ON", sub = "Players near you can hear you · turn it off or mute someone in SETTINGS › VOICE" },
	[1] = { text = "ARENA VOICE", sub = "Only contenders within about 30 m hear you · and talking gives you away" },
	[2] = { text = "ONLY " .. Lore.upper("Stands") .. " HEAR YOU NOW", sub = "Spectators and the lobby hear you · the arena can't" },
}

local function tipCount(id: number): number
	local bits = math.floor(tonumber(ClientState.settings.voiceTips) or 0)
	return (bits // (4 ^ id)) % 4
end

-- Never before the saved settings are in: the counter it saves must start from the saved one.
local function showTip(id: number)
	if VoiceCfg.Tips == false or tipsShown[id] or not settingsReady() then
		return
	end
	if tipCount(id) >= (tonumber(VoiceCfg.TipRepeats) or 2) then
		return
	end
	tipsShown[id] = true
	local tip = TIPS[id]
	local notifications = Controllers and Controllers.NotificationController
	if tip and notifications and notifications.toast then
		notifications.toast(tip.text, tip.sub, 6)
	end
	local sc = Controllers and Controllers.SettingsController
	if sc and sc.set then
		sc.set("voiceTips", math.floor(tonumber(ClientState.settings.voiceTips) or 0) + 4 ^ id)
	end
end

local tipsReadyAt: number? = nil

local function checkTips()
	if not settingsReady() then
		tipsReadyAt = nil
		return
	end
	tipsReadyAt = tipsReadyAt or os.clock()
	if os.clock() - tipsReadyAt < 2 then
		return -- (SettingsController applies the saved copy first, so the tip counters start from the saved ones)
	end
	if available ~= true or not myDevice or not isOnNow() or not serverOn() then
		return
	end
	local phase = GameState:GetAttribute("Phase")
	local role = roleOf(player)
	if role == "Contender" and ClientState.inArena then
		showTip(1)
	elseif role == "Bench" and (ClientState.spectating ~= nil or not ClientState.inArena) then
		showTip(2)
	elseif role == "Open" and not ClientState.inArena and (phase == "Lobby" or phase == "Intermission") then
		showTip(0)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The choice (Proximity voice on / off) and the optional whisper
--------------------------------------------------------------------------------------------------------------------
-- Only your explicit choice is ever sent (setOn); the server reads your saved one itself.
local function sendChoice()
	local choice = explicitChoice
	if choice == nil then
		return
	end
	lastSendAt = os.clock()
	local ok, err = pcall(function()
		Net.event("VoiceRequest"):FireServer("SetVoice", choice)
	end)
	if not ok then
		warnOnce("send", "Couldn't send the voice choice: " .. tostring(err))
	end
end

-- If the server still shows something other than what you chose, send it again (at most every RESEND_AFTER seconds).
local function checkChoice()
	syncLocalMute()
	local choice = explicitChoice
	if choice == nil or serverOn() == choice or GameState:GetAttribute("VoiceMode") == "Off" then
		return
	end
	if os.clock() - lastSendAt >= RESEND_AFTER then
		sendChoice()
	end
end

-- Until you choose this session, the Settings row shows what the server applied (shown only; never saved from here).
local function syncDisplayedChoice()
	if explicitChoice ~= nil then
		return
	end
	local value = if serverOn() then 1 else 0
	if (tonumber(ClientState.settings.voiceOn) or -1) ~= value then
		ClientState.setSettings({ voiceOn = value })
	end
end

local function sendWhisper(on: boolean)
	if whisperHeld == on then
		return
	end
	whisperHeld = on
	pcall(function()
		Net.event("VoiceRequest"):FireServer("Whisper", on)
	end)
end

-- Hold to whisper (Config.Voice.Whisper): only while you're a contender with truce allies (VoiceService.setAllies).
local function updateWhisperBinding()
	local want = WhisperCfg.Enabled == true
		and isOnNow()
		and roleOf(player) == "Contender"
		and (tonumber(player:GetAttribute("VoiceAllies")) or 0) > 0
	if want == whisperBound then
		return
	end
	whisperBound = want
	if want then
		Input.bind("VoiceWhisper", function(state)
			sendWhisper(state == Enum.UserInputState.Begin)
			return Enum.ContextActionResult.Sink
		end, {
			keys = WhisperCfg.Keys or { Enum.KeyCode.V, Enum.KeyCode.DPadLeft },
			touch = { label = "WHISPER", position = UDim2.new(1, -268, 1, -234), size = 52 },
			priority = 2000,
		})
	else
		Input.unbind("VoiceWhisper")
		task.spawn(sendWhisper, false)
	end
end

local function refreshAll()
	applyVolumes()
	for _, s in pairs(speakers) do
		applySpeaker(s)
	end
	updateWhisperBinding()
	render()
end

-- The server's VoiceOn / VoiceHold changed: follow it (the mic, the display, the speakers)
local function onServerChoice()
	syncLocalMute()
	syncDisplayedChoice()
	refreshAll()
end

local function maintain()
	guarded("listener", ensureListener)
	guarded("profile", updateProfile)
	guarded("device", function()
		if not (myDevice and myDevice.Parent == player) then
			setMyDevice(findDevice(player))
		end
	end)
	for _, s in pairs(speakers) do
		guarded("speaker", function()
			refreshSpeaker(s)
		end)
	end
	guarded("stands", updateStands)
	guarded("whisper", updateWhisperBinding)
	guarded("choice", checkChoice)
end

--------------------------------------------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------------------------------------------
function VoiceController.isAvailable(): boolean
	return available == true
end

function VoiceController.isOn(): boolean
	return isOnNow()
end

-- Your explicit choice: the lobby card, the VOICE panel and Settings › VOICE all come here.
function VoiceController.setOn(on: boolean)
	if not enabled then
		return
	end
	explicitChoice = on == true
	syncLocalMute() -- OFF closes your mic on this device at once
	sendChoice()
	local value = if explicitChoice then 1 else 0
	local sc = Controllers and Controllers.SettingsController
	if sc and sc.set then
		sc.set("voiceOn", value) -- saved (only this key is sent)
	end
	if (tonumber(ClientState.settings.voiceOn) or -1) ~= value then
		ClientState.setSettings({ voiceOn = value }) -- (a SettingsController without the VOICE rows: not saved)
	end
	refreshAll()
end

function VoiceController.hasOwnVolume(): boolean
	return GRAPH == "Custom" or STANDS_BUS
end

function VoiceController.isMuted(p: Player): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and muted[p.UserId] == true
end

function VoiceController.setMuted(p: Player, on: boolean)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p == player then
		return
	end
	muted[p.UserId] = if on then true else nil
	local s = speakers[p]
	if s then
		applySpeaker(s)
	end
	render()
end

function VoiceController.mutedCount(): number
	local n = 0
	for userId in pairs(muted) do
		if Players:GetPlayerByUserId(userId) then
			n += 1
		end
	end
	return n
end

function VoiceController.openPanel()
	if not enabled then
		return
	end
	local sc = Controllers and Controllers.SettingsController
	if sc and sc.isOpen and sc.isOpen() and sc.close then
		sc.close()
	end
	if sc and sc.setModal then
		sc.setModal("VoicePanel", true) -- frees the mouse; gameplay ignores attack input meanwhile
	end
	Hud.setPanel(panelState())
	Hud.openPanel()
end

function VoiceController.closePanel()
	Hud.closePanel()
	local sc = Controllers and Controllers.SettingsController
	if sc and sc.setModal then
		sc.setModal("VoicePanel", false)
	end
end

function VoiceController.getTalkers(): { { [string]: any } }
	local out = {}
	for _, s in ipairs(talkers) do
		table.insert(out, {
			player = s.player,
			level = s.level,
			tag = if s.standsWire then "Spectator" elseif s.player:GetAttribute("VoiceWhisper") == true then "Whisper" else "Nearby",
		})
	end
	return out
end

function VoiceController.debugState(): { [string]: any }
	local list = {}
	for p, s in pairs(speakers) do
		table.insert(list, {
			name = p.Name,
			role = roleOf(p),
			device = s.device ~= nil,
			emitter = s.emitter ~= nil,
			engineEmitter = s.engineEmitter ~= nil,
			engineGroup = if s.engineEmitter then s.engineEmitter.AudioInteractionGroup else nil,
			head = s.head ~= nil,
			stands = s.standsWire ~= nil,
			occlusion = math.floor(s.occlusion * 100 + 0.5) / 100,
			level = math.floor(s.level * 1000 + 0.5) / 1000,
			muted = muted[p.UserId] == true,
			blocked = blocked[p.UserId] == true,
			robloxMuted = robloxMuted[p.UserId] == true,
		})
	end
	local l = listener
	return {
		enabled = enabled,
		graph = GRAPH,
		standsBus = STANDS_BUS,
		available = available,
		device = myDevice ~= nil,
		micActive = micActive(),
		on = isOnNow(),
		explicit = explicitChoice,
		serverOn = serverOn(),
		hold = holdReason(),
		volume = volumeSetting(),
		profile = profileName,
		stands = standsActive,
		listenerAt = if l and l.Parent then l.Parent:GetFullName() else "Roblox's own",
		channel = channel(),
		speakers = list,
	}
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------
local function mountCard()
	local card = Hud.getCard()
	if not card then
		return
	end
	local lobby = Controllers and Controllers.LobbyController
	if lobby and type(lobby.mountCard) == "function" then
		lobby.mountCard(card, 7)
		return
	end
	-- an older LobbyController without mountCard: put the card at the bottom of the lobby's left column ourselves
	task.spawn(function()
		local gui = player:WaitForChild("PlayerGui"):WaitForChild("Lobby", 30)
		local root = gui and gui:FindFirstChild("Root")
		local brand = root and root:FindFirstChild("Brand")
		if brand then
			card.LayoutOrder = 7
			card.Parent = brand
		end
	end)
end

-- A client can only ask about its own player; the call can fail on an HTTP error, so it is retried twice.
local function checkAvailable()
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
		end)
		if ok then
			available = result == true or myDevice ~= nil
			break
		end
		if myDevice then
			available = true
			break
		end
		if attempt < 3 then
			task.wait(5 * attempt)
		end
	end
	checkDone = true
end

-- Roblox's own block list and mute events, honoured in every graph (a blocked player is silent in our chain and the
-- stands' bus, and never listed as talking). The CoreScripts register these a little after the game starts.
local function hookRobloxLists()
	local function idOf(value: any): number?
		if typeof(value) == "Instance" and value:IsA("Player") then
			return value.UserId
		end
		return tonumber(value)
	end
	local function changed()
		for _, s in pairs(speakers) do
			applySpeaker(s)
		end
		render()
	end
	local events = {
		{ name = "PlayerBlockedEvent", list = blocked, on = true },
		{ name = "PlayerUnblockedEvent", list = blocked, on = false },
		{ name = "PlayerMutedEvent", list = robloxMuted, on = true },
		{ name = "PlayerUnmutedEvent", list = robloxMuted, on = false },
	}
	task.spawn(function()
		local haveIds = false
		local hooked: { [string]: boolean } = {}
		for _ = 1, 30 do
			if not haveIds then
				local ok, ids = pcall(function()
					return StarterGui:GetCore("GetBlockedUserIds")
				end)
				if ok and type(ids) == "table" then
					haveIds = true
					for _, value in ipairs(ids) do
						local id = idOf(value)
						if id then
							blocked[id] = true
						end
					end
					guarded("blocks", changed)
				end
			end
			local all = haveIds
			for _, spec in ipairs(events) do
				if not hooked[spec.name] then
					local ok, event = pcall(function()
						return StarterGui:GetCore(spec.name)
					end)
					if ok and typeof(event) == "Instance" and event:IsA("BindableEvent") then
						hooked[spec.name] = true
						event.Event:Connect(function(who)
							local id = idOf(who)
							if id then
								spec.list[id] = if spec.on then true else nil
								guarded("blocks", changed)
							end
						end)
					else
						all = false
					end
				end
			end
			if all then
				return
			end
			task.wait(1)
		end
		warnOnce("core", "Roblox's block list or mute events weren't available; only this game's own mutes apply here.")
	end)
end

function VoiceController.Init(registry)
	Controllers = registry
	enabled = VoiceCfg.Enabled == true
end

function VoiceController.Start()
	if not enabled then
		return
	end
	startedAt = os.clock()
	buildGraph()
	guarded("listener", ensureListener)
	Hud.build({
		onToggle = function()
			VoiceController.setOn(not isOnNow())
		end,
		onOpenPanel = VoiceController.openPanel,
		onClosePanel = VoiceController.closePanel,
		onMute = function(p: Player, on: boolean)
			VoiceController.setMuted(p, on)
		end,
		onBlock = function(p: Player)
			pcall(function()
				StarterGui:SetCore("PromptBlockPlayer", p) -- Roblox's own block (voice and text), with its confirmation
			end)
		end,
		onServer = function(action: string)
			pcall(function()
				Net.event("VoiceRequest"):FireServer(if action == "Leave" then "LeaveVoiceServer" else "JoinVoiceServer")
			end)
		end,
	})
	mountCard()
	hookRobloxLists()

	for _, p in ipairs(Players:GetPlayers()) do
		trackPlayer(p)
	end
	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(untrackPlayer)
	player.ChildAdded:Connect(function(child)
		if child:IsA("AudioDeviceInput") then
			guarded("device", function()
				setMyDevice(findDevice(player))
				render()
			end)
		end
	end)
	player.ChildRemoved:Connect(function(child)
		if child == myDevice then
			guarded("device", function()
				setMyDevice(findDevice(player))
				render()
			end)
		end
	end)
	guarded("device", function()
		setMyDevice(findDevice(player))
	end)
	task.spawn(function()
		checkAvailable()
		guarded("render", render)
	end)

	for _, part in ipairs(CollectionService:GetTagged("VoiceZone")) do
		addZone(part)
	end
	CollectionService:GetInstanceAddedSignal("VoiceZone"):Connect(addZone)
	CollectionService:GetInstanceRemovedSignal("VoiceZone"):Connect(removeZone)

	local function onContext()
		guarded("context", function()
			ensureListener()
			updateProfile()
			updateStands()
			updateWhisperBinding()
			render()
		end)
	end
	ClientState.spectateChanged:Connect(onContext)
	ClientState.lifeChanged:Connect(onContext)
	ClientState.settingsChanged:Connect(function()
		guarded("settings", refreshAll)
	end)
	player:GetAttributeChangedSignal("VoiceRole"):Connect(onContext)
	player:GetAttributeChangedSignal("VoiceAllies"):Connect(function()
		guarded("whisper", updateWhisperBinding)
	end)
	player:GetAttributeChangedSignal("VoiceWhisper"):Connect(function()
		guarded("render", render)
	end)
	for _, name in ipairs({ "VoiceOn", "VoiceHold" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			guarded("choice", onServerChoice)
		end)
	end
	player:GetAttributeChangedSignal("SettingsLoaded"):Connect(function()
		guarded("render", render)
	end)
	GameState:GetAttributeChangedSignal("Phase"):Connect(onContext)
	GameState:GetAttributeChangedSignal("VoiceMode"):Connect(function()
		guarded("render", render)
	end)
	local sc = Controllers and Controllers.SettingsController
	if sc and sc.menuChanged then
		sc.menuChanged:Connect(function()
			guarded("render", render)
		end)
	end
	Input.deviceChanged:Connect(function()
		Hud.applyLayout()
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			Hud.applyLayout()
		end)
	end

	guarded("choice", onServerChoice)
	onContext()

	local function frameStep(dt: number)
		followCamera()
		moveAnchors()
		smoothOcclusion(dt)
		Hud.animate(dt)
	end
	RunService.RenderStepped:Connect(function(dt: number)
		local ok, err = pcall(frameStep, dt)
		if not ok then
			warnOnce("frame:" .. tostring(err), "frame failed: " .. tostring(err))
		end
	end)

	local lastRays, lastMaintain, lastTips = 0, 0, 0
	while true do
		local now = os.clock()
		guarded("talk", talkPass)
		if now - lastRays >= math.max(0.05, tonumber(Occ.Interval) or 0.2) then
			lastRays = now
			guarded("occlusion", occlusionPass)
		end
		if now - lastMaintain >= 0.5 then
			lastMaintain = now
			maintain() -- (every step guarded on its own)
		end
		if now - lastTips >= 1 then
			lastTips = now
			guarded("tips", checkTips)
		end
		guarded("state", publishState)
		guarded("render", render)
		if VoiceCfg.Debug == true and now - lastDebug >= 10 then
			lastDebug = now
			local d = VoiceController.debugState()
			print(string.format("[VoiceController] %s · %s graph · profile %s · listener %s · %d speakers · stands %s",
				tostring(d.channel), tostring(d.graph), tostring(d.profile), tostring(d.listenerAt), #d.speakers, tostring(d.stands)))
		end
		task.wait(TICK)
	end
end

return VoiceController
