-- MERGE INTO ReplicatedStorage.Shared.Config, just above `Config.Studio = {` (the patched copy of Config.lua next to this
-- file already has it there). Not a ModuleScript of its own.

-- Proximity Voice (docs/design/VoiceMode.md). Nothing changes until Enabled is true: Roblox's default voice then runs as
-- it does today. Roblox builds the voice graph (Studio: VoiceChatService.UseAudioApi = Enabled, EnableDefaultVoice = true);
-- VoiceService (server) decides who can hear whom, VoiceController (client) how it sounds, and draws the voice UI.
-- Distances are in studs (an R15 contender is ~5.2 studs tall, so 1 stud ~ 0.33 m).
Config.Voice = {
	Enabled = false,
	ServerMode = "Proximity", -- "Proximity" | "Off" (every microphone muted on this server, e.g. a future text-only server)
	DefaultOn = true, -- the choice of a player who never made one, once their saved settings have loaded
	-- (There is no time limit: a player stays muted until DataService says their settings loaded, or they choose.
	-- A failed load keeps them muted, with a note on the lobby card, until they turn voice on themselves.)
	-- Phases in which a round is running: the fallen and late joiners ("the stands") are heard only by each other.
	-- The coming train, training room and launch phases are listed already (RoundService.isRoundRunning reads this too).
	RoundPhases = { Countdown = true, Active = true, Train = true, Training = true, Launch = true },
	-- How voice fades with distance where you listen. Full: full volume up to here. Silent: nothing from here on.
	-- Shape: 1 = the inverse law between them (realistic), lower = flatter. VoiceController.Curves builds the curve.
	Profiles = {
		Social = { Full = 15, Silent = 110, Shape = 0.6 }, -- the Tor; later the train station and the training room
		Arena = { Full = 8, Silent = 90, Shape = 0.8 }, -- ~3 m at full voice, gone by ~30 m (footsteps carry 70-80 studs)
		Cabin = { Full = 8, Silent = 45, Shape = 0.9 }, -- indoors: train cars, the launch room
		Whisper = { Full = 4, Silent = 18, Shape = 1 }, -- a truce ally's whisper (on top of the place's profile)
	},
	-- The profile for contenders and spectators in each phase (everyone else uses Social). A part tagged VoiceZone with a
	-- VoiceProfile attribute overrides it inside its box; a VoiceRoom attribute muffles voices from other rooms (train cars).
	PhaseProfiles = { Countdown = "Arena", Active = "Arena", Ending = "Arena", Train = "Cabin", Training = "Social", Launch = "Cabin" },
	-- Walls and terrain. "Raycast": a client ray from the listener to each nearby speaker's head (terrain, rock, cliffs,
	-- buildings and trunks block it; foliage crowns don't take raycasts). "Engine": Roblox's acoustic simulation
	-- (SoundService.AcousticSimulationEnabled, a Studio switch; test its cost first). "None": distance only.
	Occlusion = {
		Mode = "Raycast",
		Profiles = { Arena = true, Cabin = true }, -- where rays run (not on the Tor: its third-person camera sits behind walls)
		Interval = 0.2, -- seconds between ray passes
		MaxRays = 8, -- the nearest speakers tested per pass
		Volume = 0.55, -- a blocked voice keeps this much of its volume...
		HighGainDb = -24, -- ...and loses this much treble (dB)...
		MidGainDb = -6, -- ...and some middle
		Smoothing = 6, -- 1/s: how fast a voice muffles and clears
	},
	Spectators = {
		HearArena = true, -- spectators hear the arena around the contender they watch
		ListenAt = "Target", -- "Target": through the watched contender's ears (Custom); "Camera": from the orbit camera
		-- The stands' channel: while you spectate, the other spectators come in with no distance. It wires their voice
		-- devices straight to this client, so it stays off until the published safety gate shows Roblox's own mute, block,
		-- voice volume and age rules reach it (VoiceMode.md, test plan G1-G6).
		StandsBus = false,
		Volume = 0.85, -- the stands' channel volume
	},
	Whisper = {
		Enabled = false, -- needs truces (VoiceService.setAllies): hold to whisper, and only your allies hear you, from close
		Keys = { Enum.KeyCode.V, Enum.KeyCode.DPadLeft },
	},
	-- UI
	TalkingLevel = 0.02, -- AudioAnalyzer RmsLevel above which someone counts as talking
	TalkingHold = 0.45, -- seconds a talker stays listed after they stop
	MaxTalkers = 4, -- rows in "who's talking near you" (3 on phones)
	MinAudibility = 0.04, -- a talker is listed only when you can hear them at least this loud
	ShowTalkerNames = true, -- false: contenders see "SOMEONE NEARBY" instead of names in the arena
	Tips = true, -- the one-line toasts that explain the mode (lobby, arena, after you fall)
	TipRepeats = 2, -- times each tip is shown per player (counters saved in settings.voiceTips)
	-- "Default" (the safe setting): Roblox's own listener and playback, untouched. We only give Roblox's emitters our
	-- distance curves, and move one to a silent group while you mute that player or turn voice off (and move it back
	-- once, only if nothing else changed it). Roblox's own mute, block and volume controls keep working as Roblox built
	-- them. "Custom": our own listener and an emitter per speaker, wired from each voice device (Voice volume,
	-- muffling by walls, listening through the watched contender's ears). Switch to "Custom" (and StandsBus on) only
	-- after the published safety gate passes (VoiceMode.md, test plan G1-G6). ("Engine" is gone: it rewrote Roblox's own
	-- emitters every half second, which could undo Roblox's own mute.)
	ClientGraph = "Default",
	-- Phase 2 (VoiceService.VoiceServers): voice-only reserved servers. Off until the beta has the players to fill them.
	VoiceServers = {
		Enabled = false,
		MaxPlayers = 24, -- the place's server size
		AdvertiseInterval = 15, -- seconds between a voice-only server's MemoryStore updates
	},
	Debug = false, -- print role changes (server) and the client's voice state every 10 s
}
