--[[
	MusicController (client) - the score. Owned by the Audio system (wave 18, "music-sfx").

	One cue at a time, chosen from where this player is and what the round is doing, cross-faded: the cue that is
	leaving fades out while the new one fades in, and a third change during a cross-fade cuts the oldest quickly, so
	no more than two music beds ever sound together (plus a short sting). The cues, their tracks, levels, fades and
	loop points live in Shared.Sounds (Sounds.MusicCues and the Music_* entries); new asset ids drop in there
	(Sounds.lua, CUSTOM_MUSIC) without touching this file.

	Cues, in the order they are checked (first match wins):
	  (Roll Call show)            nothing: AudioController.setMusicSuppressed (FallenRecapController)
	  Phase "Ending"              nothing: the Victory / round-end sting carries it
	  launch shot                 Rise        (ClientState.launchShot: the glass case and the tube)
	  in the red room             RedRoom     (player attribute InRedRoom)
	  in the arena or watching it:
	    Countdown                 Countdown   (on the plate, until the horn)
	    the horn                  nothing for HornGap seconds: the horn rings alone, then
	    Last Stand / 2 alive      LastStand   (GameState.LastStand, or AliveCount <= 2 of 3+)
	    the border moving         Border      (GameState.BorderShrinking or BorderMoving)
	    the opening seconds       Scramble    (OpeningTime seconds after the horn)
	    the Feast, or <= 5 alive  Hunt
	    night                     Night       (Lighting.ClockTime, the same night window as the ambience)
	    otherwise                 Explore for ExploreOn seconds, then silence for ExploreOff (silence as tension)
	  at the Training Centre      Training    (AtTrainingCentre / InTraining)
	  on the ride                 Ride        (GameState.TrainStage "Ride")
	  anywhere else               Lobby       (the train lobby)
	Stings (2D, Music group, the bed ducks under them): Sting_Defeat when this player falls (YouDied).
	The Victory sting stays Sounds.Victory, played by NotificationController; AudioController ducks the beds under it.

	The mix: the bed ducks under combat (this player hitting or being hit: CombatLevel for CombatHold seconds), under
	announcements (Announce remote: Warning, Banner, Headline), under the Horn, cannon, feast bell and border warning
	(AudioController's ducks, read through AudioController.musicDuckLevel) and under its own stings. The Music volume
	setting is the Music SoundGroup's volume (AudioController applies it, times the master volume).

	Public API (Controllers.MusicController):
	  MusicController.currentCue() -> string?
	  MusicController.sting(name: string, opts?: { volume: number? }) -> Sound?   (a Sounds key, e.g. "Sting_Defeat")
	  MusicController.forceCue(name: string?)    test hook: holds a cue (false = release; nil = force silence)
	  MusicController.debugState() -> { cue, beds = { { key, level, volume, loudness } }, duck }
	Studio only: SoundService attribute MusicDebug, updated twice a second.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Sounds"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local IS_STUDIO = RunService:IsStudio()

local MusicController = {}

local TUNE = {
	Decide = 0.25, -- seconds between cue decisions
	HornGap = 2.4, -- seconds of no music after the horn (the horn rings alone, then the scramble hits)
	OpeningTime = 45, -- seconds of Scramble after the horn
	ExploreOn = 110, -- seconds of the Explore bed ...
	ExploreOff = 70, -- ... then this long with only the ambience
	TensionAlive = 5,
	FinalAlive = 2,
	NightFrom = 19.0,
	NightTo = 20.0,
	DawnFrom = 5.0,
	DawnTo = 6.5,
	CombatLevel = 0.45, -- bed level while fighting
	CombatHold = 6, -- seconds after the last hit
	AnnounceLevel = 0.5, -- bed level under a spoken or shown announcement
	AnnounceTime = 4,
	CutFade = 0.35, -- seconds: a third cue during a cross-fade cuts the oldest this fast
	DuckDown = 8, -- 1/s: how fast the bed ducks
	DuckUp = 0.8, -- 1/s: how fast it comes back
}
local ANNOUNCE_DUCK = { Warning = true, Banner = true, Headline = true }

local Controllers: any = nil
local GameState: Instance? = nil

local beds = {} -- { key, sound, level, target, fadeIn, fadeOut, base }
local desiredCue: string? = nil
local forced: any = false -- false = not forced; nil or a cue name when forced
local duck = 1
local combatUntil = 0
local announceUntil = 0
local stingUntil, stingLevel = 0, 1
local hornAt = 0
local lastPhase: string? = nil
local musicGroup: SoundGroup? = nil
local rootFolder: Folder? = nil

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function attr(name: string): any
	return if GameState then GameState:GetAttribute(name) else nil
end

local function group(): SoundGroup?
	if musicGroup and musicGroup.Parent then
		return musicGroup
	end
	local found = SoundService:FindFirstChild("Music")
	if found and found:IsA("SoundGroup") then
		musicGroup = found
		return found
	end
	return nil
end

local function cueSpec(name: string?): any
	if not name then
		return nil
	end
	local cues = Sounds.MusicCues
	local spec = type(cues) == "table" and cues[name] or nil
	if type(spec) ~= "table" then
		return nil
	end
	local entry = Sounds[spec.key]
	if type(entry) ~= "table" or type(entry.ids) ~= "table" or #entry.ids == 0 then
		return nil -- an empty cue is silence, which is safe
	end
	return spec
end

local function nightFactor(): number
	local clock = Lighting.ClockTime
	return math.max(smoothstep(TUNE.NightFrom, TUNE.NightTo, clock), 1 - smoothstep(TUNE.DawnFrom, TUNE.DawnTo, clock))
end

local function musicSuppressed(): boolean
	local audio = Controllers and Controllers.AudioController
	if audio and type(audio.isMusicSuppressed) == "function" then
		local ok, value = pcall(audio.isMusicSuppressed)
		return ok and value == true
	end
	return false
end

---------------------------------------------------------------------------
-- Which cue
---------------------------------------------------------------------------
local function arenaCue(now: number): string?
	local phase = attr("Phase")
	if phase == "Countdown" then
		return "Countdown"
	end
	if phase ~= "Active" then
		return nil
	end
	local sinceHorn = now - hornAt
	if hornAt > 0 and sinceHorn < TUNE.HornGap then
		return nil
	end
	local practice = attr("Practice") == true
	local alive = tonumber(attr("AliveCount")) or 0
	local started = tonumber(attr("StartedCount")) or 0
	if attr("LastStand") == true or (not practice and started >= 3 and alive >= 1 and alive <= TUNE.FinalAlive) then
		return "LastStand"
	end
	if attr("BorderShrinking") == true or attr("BorderMoving") == true then
		return "Border"
	end
	local startedAt = tonumber(attr("RoundStartedAt")) or 0
	local elapsed = if startedAt > 0 then workspace:GetServerTimeNow() - startedAt else math.huge
	if elapsed < TUNE.OpeningTime then
		return "Scramble"
	end
	if attr("ArenaEvent") == "Feast" or (not practice and started > TUNE.TensionAlive and alive <= TUNE.TensionAlive) then
		return "Hunt"
	end
	-- (hysteresis: night begins above 0.6 and ends below 0.4, so dusk never flips the cue back and forth)
	local night = nightFactor()
	if night > 0.6 or (desiredCue == "Night" and night > 0.4) then
		return "Night"
	end
	local cycle = TUNE.ExploreOn + TUNE.ExploreOff
	if elapsed ~= math.huge and (elapsed - TUNE.OpeningTime) % cycle < TUNE.ExploreOn then
		return "Explore"
	end
	return nil
end

local function decide(now: number): string?
	if forced ~= false then
		return forced
	end
	if musicSuppressed() then
		return nil
	end
	local phase = attr("Phase")
	if phase == "Ending" then
		return nil
	end
	if ClientState.launchShot == true then
		return "Rise"
	end
	if player:GetAttribute("InRedRoom") == true then
		return "RedRoom"
	end
	if ClientState.inArena or ClientState.spectating ~= nil then
		return arenaCue(now)
	end
	if player:GetAttribute("AtTrainingCentre") == true or player:GetAttribute("InTraining") == true then
		return "Training"
	end
	if attr("TrainStage") == "Ride" then
		return "Ride"
	end
	return "Lobby"
end

---------------------------------------------------------------------------
-- Beds
---------------------------------------------------------------------------
local function newBed(cue: string, spec: any)
	local entry = Sounds[spec.key]
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. cue
	sound.SoundId = entry.ids[math.random(1, #entry.ids)]
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = group()
	if type(spec.loop) == "table" and #spec.loop == 2 then
		sound.PlaybackRegionsEnabled = true
		sound.LoopRegion = NumberRange.new(spec.loop[1], spec.loop[2])
	end
	if type(spec.startAt) == "number" then
		sound.TimePosition = spec.startAt
	end
	sound.Parent = rootFolder
	sound:Play()
	local bed = {
		cue = cue,
		key = spec.key,
		sound = sound,
		level = 0,
		target = spec.level or 1,
		fadeIn = math.max(0.05, spec.fadeIn or 3),
		fadeOut = math.max(0.05, spec.fadeOut or 2.5),
		base = (entry.volume or 0.5),
	}
	table.insert(beds, bed)
	return bed
end

local function applyCue(cue: string?)
	local spec = cueSpec(cue)
	local keep = nil
	for _, bed in ipairs(beds) do
		if spec and bed.cue == cue then
			keep = bed
			bed.target = spec.level or 1
			bed.fadeIn = math.max(0.05, spec.fadeIn or 3)
		else
			if bed.target > 0 and spec then
				-- the leaving cue fades with its own fade-out, unless the new cue asks for a hard cut
				bed.fadeOut = math.min(bed.fadeOut, spec.cutIn or bed.fadeOut)
			end
			bed.target = 0
		end
	end
	if spec and not keep then
		newBed(cue :: string, spec)
	end
	-- never stacked: of the beds fading out, all but the newest leave quickly
	local leaving = {}
	for _, bed in ipairs(beds) do
		if bed.target <= 0 and bed.level > 0 then
			table.insert(leaving, bed)
		end
	end
	for i = 1, #leaving - 1 do
		leaving[i].fadeOut = math.min(leaving[i].fadeOut, TUNE.CutFade)
	end
end

local function updateBeds(dt: number, now: number)
	-- the duck: AudioController's (horn, cannon, bells, victory), combat, announcements, stings
	local target = 1
	local audio = Controllers and Controllers.AudioController
	if audio and type(audio.musicDuckLevel) == "function" then
		local ok, value = pcall(audio.musicDuckLevel)
		if ok and type(value) == "number" then
			target = math.min(target, value)
		end
	end
	if now < combatUntil then
		target = math.min(target, TUNE.CombatLevel)
	end
	if now < announceUntil then
		target = math.min(target, TUNE.AnnounceLevel)
	end
	if now < stingUntil then
		target = math.min(target, stingLevel)
	end
	local rate = if target < duck then TUNE.DuckDown else TUNE.DuckUp
	duck += (target - duck) * (1 - math.exp(-rate * dt))

	for i = #beds, 1, -1 do
		local bed = beds[i]
		if bed.level < bed.target then
			bed.level = math.min(bed.target, bed.level + dt / bed.fadeIn)
		elseif bed.level > bed.target then
			bed.level = math.max(bed.target, bed.level - dt / bed.fadeOut)
		end
		if bed.target <= 0 and bed.level <= 0 then
			bed.sound:Destroy()
			table.remove(beds, i)
		else
			-- equal-power curve: a cross-fade keeps its loudness in the middle
			local v = bed.base * math.sin(bed.level * math.pi / 2) * duck
			if math.abs(bed.sound.Volume - v) > 0.0005 then
				bed.sound.Volume = v
			end
		end
	end
end

---------------------------------------------------------------------------
-- Stings
---------------------------------------------------------------------------
function MusicController.sting(name: string, opts: { [string]: any }?): Sound?
	local entry = Sounds[name]
	if type(entry) ~= "table" or type(entry.ids) ~= "table" or #entry.ids == 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = entry.ids[math.random(1, #entry.ids)]
	sound.Volume = (entry.volume or 0.5) * (if opts and type(opts.volume) == "number" then opts.volume else 1)
	sound.SoundGroup = group()
	sound.Parent = rootFolder
	sound:Play()
	local length = entry.maxLifetime or 12
	stingUntil = os.clock() + (entry.duckTime or length)
	stingLevel = entry.duckBed or 0.25
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(length + 1, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	return sound
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function MusicController.currentCue(): string?
	return desiredCue
end

function MusicController.forceCue(name: any)
	forced = name
end

function MusicController.debugState()
	local list = {}
	for _, bed in ipairs(beds) do
		table.insert(list, {
			key = bed.key,
			cue = bed.cue,
			level = math.floor(bed.level * 100) / 100,
			volume = math.floor(bed.sound.Volume * 1000) / 1000,
			loudness = math.floor(bed.sound.PlaybackLoudness * 10) / 10,
			time = math.floor(bed.sound.TimePosition * 10) / 10,
		})
	end
	return { cue = desiredCue or "none", beds = list, duck = math.floor(duck * 100) / 100 }
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function MusicController.Init(registry)
	Controllers = registry
	local existing = SoundService:FindFirstChild("MusicController")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "MusicController"
	folder.Parent = SoundService
	rootFolder = folder

	ClientState.hitConfirmed:Connect(function()
		combatUntil = os.clock() + TUNE.CombatHold
	end)
	ClientState.damageTaken:Connect(function()
		combatUntil = os.clock() + TUNE.CombatHold
	end)
end

function MusicController.Start()
	GameState = ReplicatedStorage:WaitForChild("GameState", 30)
	lastPhase = attr("Phase")

	local okA, announce = pcall(Net.event, "Announce")
	if okA and announce then
		announce.OnClientEvent:Connect(function(data)
			if type(data) == "table" and ANNOUNCE_DUCK[data.style] then
				announceUntil = os.clock() + (tonumber(data.duration) or TUNE.AnnounceTime)
			end
		end)
	end
	local okD, died = pcall(Net.event, "YouDied")
	if okD and died then
		died.OnClientEvent:Connect(function()
			MusicController.sting("Sting_Defeat")
		end)
	end

	local acc, debugAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		local phase = attr("Phase")
		if phase ~= lastPhase then
			if phase == "Active" and lastPhase == "Countdown" then
				hornAt = now
			end
			lastPhase = phase
			acc = TUNE.Decide -- decide at once on a phase change (the horn cut is immediate)
		end
		acc += dt
		if acc >= TUNE.Decide then
			acc = 0
			local cue = decide(now)
			if cue ~= desiredCue then
				desiredCue = cue
				applyCue(cue)
			end
		end
		updateBeds(dt, now)
		if IS_STUDIO then
			debugAcc += dt
			if debugAcc >= 0.5 then
				debugAcc = 0
				local parts = {}
				for _, bed in ipairs(beds) do
					table.insert(parts, string.format("%s %.2f v%.3f L%.1f", bed.cue, bed.level, bed.sound.Volume, bed.sound.PlaybackLoudness))
				end
				SoundService:SetAttribute("MusicDebug", string.format("cue=%s duck=%.2f [%s]", desiredCue or "none", duck, table.concat(parts, " | ")))
			end
		end
	end)
end

return MusicController
