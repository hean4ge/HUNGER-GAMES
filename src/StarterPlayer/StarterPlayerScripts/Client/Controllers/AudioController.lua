--[[
	AudioController (client) - the living soundscape. Owned by the Audio system.

	- Local foley from ClientState (MovementController): footsteps by floor material, jump, landings
	  (Land_Hard for real drops), slide, mantle, climb and swim.
	- Other contenders' footsteps in 3D (stealth): stride estimated from HumanoidRootPart velocity plus a
	  floor raycast for the material; quieter and shorter-range when their Stance is Crouch, silent when
	  still or airborne; their landings, slides and climbing too. Pooled voices, capped.
	- Ambience beds by biome (Shared.ArenaLayout.getBiome around the camera, spatially blended) and time of
	  day (Lighting.ClockTime; night beds take over around 19:30), crossfaded. AmbientEmitter-tagged parts
	  get looped 3D emitters (SoundKey attribute, optional Volume attribute), streaming-aware, nearest N only.
	- Music by game state: Music_Lobby in the lobby; Music_Tension during the countdown, the opening rush,
	  the Feast, while the border shrinks or at AliveCount <= 5; Music_Final at AliveCount <= 2.
	  Music and ambience duck under the cannon, start horn, feast bell, border warning, victory and roll call.
	- Low-stamina breathing and low-health heartbeat (looped, faded; below Config.Feedback.LowHealth, the HUD's LOW line).
	- Other contenders' bow draws (PlayabilityPlan QW9): the CombatAction remote's "Draw" plays the bow's creak at the
	  archer for anyone within 45 studs, following them, and "Release" (loosed or let down) stops it.
	- SoundGroup volumes from ClientState.settings; SFX reverb by environment (forest, mountains, lake,
	  cave, indoors); muffle while the camera is underwater, on death and on heavy hits.

	Public API (through the Controllers registry, e.g. Controllers.AudioController.play("Hit_Wood", { position = p })):
	  AudioController.play(key: string, opts?) -> (Sound?, voice?)
	      Pooled, region-aware one-shot. opts: { position: Vector3?, volume: number?, pitch: number?,
	      rollScale: number?, priority: number?, foot: "L"|"R"? }. No position = 2D.
	  AudioController.footstepAt(position: Vector3, material: Enum.Material, intensity: number?, crouched: boolean?)
	  AudioController.duck(musicFactor: number, ambienceFactor: number, seconds: number)
	  AudioController.materialKey(material: Enum.Material) -> string?   ("Footstep_*")
	  AudioController.setMusicSuppressed(suppressed: boolean)
	  AudioController.debugState() -> { [string]: any }
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Sounds"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local IS_STUDIO = RunService:IsStudio()

local AudioController = {}

local TUNE = {
	LocalVoices = 8, -- 2D voices for the local player's own foley and 2D one-shots
	WorldVoices = 16, -- 3D voices shared by other contenders' footsteps and positional one-shots
	RemoteRange = 90, -- studs: other characters closer than this are simulated
	RemoteMaxSimulated = 10, -- only the nearest N characters make footsteps
	RemoteGain = 1.1,
	CrouchVolume = 0.35,
	CrouchRollScale = 0.55,
	StepMinSpeed = 2.2, -- horizontal speed below which nobody makes footsteps
	LocalStepMinInterval = 0.11,
	SoftLandSpeed = 18,
	HardLandSpeed = 62, -- a regular jump lands at ~49 studs/s; Land_Hard is for real drops
	NightFrom = 19.0,
	NightTo = 20.0, -- night beds cross over around 19:30
	DawnFrom = 5.0,
	DawnTo = 6.5,
	BedFade = 0.5, -- crossfade rate (1/s) for ambience beds
	MusicFadeIn = 0.45,
	MusicFadeOut = 0.32,
	FinalFadeIn = 0.9,
	OpeningMusicTime = 40, -- seconds of tension music after the start horn
	TensionAlive = 5,
	FinalAlive = 2,
	MaxEmitters = 14,
	EmitterMargin = 30, -- emitters start this many studs before their RollOffMaxDistance
	RemoteDrawRange = 45, -- studs: other contenders' bow creak is heard this close (QW9)
	RemoteDrawGain = 1.3,
}
local LOW_HEALTH = tonumber(Config.Feedback and Config.Feedback.LowHealth) or 0.35 -- one low-health line (QW5)

-- Floor material -> footstep key (by Enum name so newer materials never error)
local MATERIAL_KEYS: { [string]: string } = {
	Grass = "Footstep_Grass", LeafyGrass = "Footstep_Grass",
	Ground = "Footstep_Dirt", Fabric = "Footstep_Dirt", Carpet = "Footstep_Dirt", Cardboard = "Footstep_Dirt",
	Leather = "Footstep_Dirt", Rubber = "Footstep_Dirt",
	Mud = "Footstep_Mud",
	Rock = "Footstep_Rock", Slate = "Footstep_Rock", Basalt = "Footstep_Rock", Granite = "Footstep_Rock",
	Concrete = "Footstep_Rock", Cobblestone = "Footstep_Rock", Brick = "Footstep_Rock", Pavement = "Footstep_Rock",
	Limestone = "Footstep_Rock", Sandstone = "Footstep_Rock", Asphalt = "Footstep_Rock", CrackedLava = "Footstep_Rock",
	Marble = "Footstep_Rock", Pebble = "Footstep_Rock", Glass = "Footstep_Rock", Plastic = "Footstep_Rock",
	SmoothPlastic = "Footstep_Rock", Neon = "Footstep_Rock", ForceField = "Footstep_Rock", Plaster = "Footstep_Rock",
	CeramicTiles = "Footstep_Rock", ClayRoofTiles = "Footstep_Rock",
	Wood = "Footstep_Wood", WoodPlanks = "Footstep_Wood", RoofShingles = "Footstep_Wood",
	Sand = "Footstep_Sand", Salt = "Footstep_Sand",
	Snow = "Footstep_Snow", Glacier = "Footstep_Snow", Ice = "Footstep_Snow",
	Metal = "Footstep_Metal", CorrodedMetal = "Footstep_Metal", DiamondPlate = "Footstep_Metal", Foil = "Footstep_Metal",
	Water = "Footstep_Water",
}

-- Ambience beds per biome: weights for day and night (crossfaded by the night factor)
local BED_KEYS = {
	"Amb_ForestDay", "Amb_ForestNight", "Amb_Swamp", "Amb_Highlands", "Amb_Lake", "Amb_Lobby", "Amb_PineForest", "Amb_Wind",
}
local BIOME_MIX = {
	Clearing = { day = { Amb_ForestDay = 0.85, Amb_Wind = 0.35 }, night = { Amb_ForestNight = 0.9, Amb_Wind = 0.3 } },
	Woodland = { day = { Amb_ForestDay = 1 }, night = { Amb_ForestNight = 1 } },
	PineForest = {
		day = { Amb_PineForest = 1, Amb_ForestDay = 0.3, Amb_Wind = 0.3 },
		night = { Amb_ForestNight = 0.75, Amb_PineForest = 0.5, Amb_Wind = 0.35 },
	},
	Highlands = {
		day = { Amb_Highlands = 1, Amb_Wind = 0.7 },
		night = { Amb_Wind = 0.85, Amb_Highlands = 0.4, Amb_ForestNight = 0.25 },
	},
	Mountains = { day = { Amb_Wind = 1, Amb_Highlands = 0.45 }, night = { Amb_Wind = 1 } },
	Lakeside = {
		day = { Amb_Lake = 0.8, Amb_ForestDay = 0.6 },
		night = { Amb_Lake = 0.7, Amb_ForestNight = 0.55, Amb_Swamp = 0.3 },
	},
	Lake = { day = { Amb_Lake = 1, Amb_ForestDay = 0.3 }, night = { Amb_Lake = 0.9, Amb_Swamp = 0.35, Amb_ForestNight = 0.3 } },
	Swamp = { day = { Amb_Swamp = 0.75, Amb_ForestDay = 0.35 }, night = { Amb_Swamp = 1, Amb_ForestNight = 0.5 } },
	Lobby = { day = { Amb_Lobby = 1, Amb_Wind = 0.4 }, night = { Amb_Lobby = 1, Amb_Wind = 0.4 } },
	-- v2 arena biomes (Shared.ArenaLayout.getBiome)
	Meadow = { day = { Amb_ForestDay = 0.8, Amb_Wind = 0.45 }, night = { Amb_ForestNight = 0.85, Amb_Wind = 0.35 } },
	Forest = {
		day = { Amb_PineForest = 1, Amb_ForestDay = 0.45, Amb_Wind = 0.25 },
		night = { Amb_ForestNight = 0.9, Amb_PineForest = 0.45, Amb_Wind = 0.25 },
	},
	Gorge = { day = { Amb_Highlands = 0.6, Amb_PineForest = 0.5, Amb_Wind = 0.45 }, night = { Amb_Wind = 0.6, Amb_ForestNight = 0.5, Amb_Highlands = 0.3 } },
	Cliffs = { day = { Amb_Highlands = 0.8, Amb_Wind = 0.6, Amb_PineForest = 0.3 }, night = { Amb_Wind = 0.8, Amb_Highlands = 0.35, Amb_ForestNight = 0.3 } },
	Field = { day = { Amb_Wind = 0.75, Amb_ForestDay = 0.55 }, night = { Amb_ForestNight = 0.7, Amb_Wind = 0.55 } },
	Marsh = { day = { Amb_Swamp = 0.8, Amb_ForestDay = 0.3 }, night = { Amb_Swamp = 1, Amb_ForestNight = 0.45 } },
}
-- Blend the biome at the camera with four samples around it so borders crossfade instead of snapping.
local BIOME_SAMPLES = {
	{ Vector3.zero, 0.4 },
	{ Vector3.new(45, 0, 0), 0.15 },
	{ Vector3.new(-45, 0, 0), 0.15 },
	{ Vector3.new(0, 0, 45), 0.15 },
	{ Vector3.new(0, 0, -45), 0.15 },
}

local BIOME_ENV = {
	Clearing = "Forest", Woodland = "Forest", PineForest = "Forest", Swamp = "Forest",
	Highlands = "Mountains", Mountains = "Mountains", Lake = "Lake", Lakeside = "Lake", Lobby = "Open",
	Meadow = "Open", Forest = "Forest", Gorge = "Mountains", Cliffs = "Mountains", Field = "Open", Marsh = "Forest",
}
-- SFX-bus reverb per environment (decay seconds, wet dB, density, diffusion)
local REVERB = {
	Forest = { 1.4, -20, 0.9, 1 },
	Mountains = { 2.6, -17, 0.6, 0.7 },
	Lake = { 1.1, -22, 0.7, 0.9 },
	Open = { 0.9, -26, 0.6, 0.8 },
	Room = { 0.7, -12, 1, 1 },
	Cave = { 3.4, -9, 1, 0.9 },
	Underwater = { 1.8, -8, 1, 1 },
}
local ENCLOSURE_RAYS = { Vector3.new(0, 22, 0), Vector3.new(10, 18, 6), Vector3.new(-10, 18, -6) }
local SOFT_ROOF = { Grass = true, LeafyGrass = true }

-- 2D stings and signals that duck the mix (and get a big outdoor reverb tail)
local DUCKS = {
	Cannon = { music = 0.3, amb = 0.5, time = 3.8, reverb = { 4.5, -4 }, eq = { 3, -1, -7 } },
	StartHorn = { music = 0.35, amb = 0.6, time = 4.5, reverb = { 3.5, -7 } },
	FeastBell = { music = 0.5, amb = 0.7, time = 3.5, reverb = { 4.0, -6 } },
	BorderWarning = { music = 0.6, amb = 0.8, time = 3 },
	Victory = { music = 0.12, amb = 0.6, time = 11 },
	RollCall = { music = 0.08, amb = 0.65, time = 31 },
}

local function damp(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function entryOf(key: string): any
	local entry = Sounds[key]
	if type(entry) == "table" then
		return entry
	end
	return nil
end

local function randomPitch(entry: any): number
	local p = entry.pitch
	if type(p) == "table" then
		return p[1] + math.random() * (p[2] - p[1])
	end
	return if type(p) == "number" then p else 1
end

local function materialKey(material: any): string?
	if typeof(material) ~= "EnumItem" or material.EnumType ~= Enum.Material then
		return nil
	end
	if material == Enum.Material.Air then
		return nil
	end
	return MATERIAL_KEYS[material.Name] or "Footstep_Dirt"
end

---------------------------------------------------------------------------
-- Sound groups and bus effects
---------------------------------------------------------------------------
local groups: { [string]: SoundGroup } = {}

local function getGroup(name: string?): SoundGroup?
	local groupName = name or "SFX"
	local g = groups[groupName]
	if g and g.Parent then
		return g
	end
	local found = SoundService:FindFirstChild(groupName)
	if found and found:IsA("SoundGroup") then
		groups[groupName] = found
		return found
	end
	return nil
end

local fx = { eq = {} :: { [string]: EqualizerSoundEffect }, reverb = nil :: ReverbSoundEffect?, comp = nil :: CompressorSoundEffect? }

local function ensureEffects()
	for _, name in ipairs({ "SFX", "Ambience", "Music" }) do
		local g = getGroup(name)
		local eq = fx.eq[name]
		if g and not (eq and eq.Parent == g) then
			local created = Instance.new("EqualizerSoundEffect")
			created.Name = "AudioMuffleEQ"
			created.LowGain = 0
			created.MidGain = 0
			created.HighGain = 0
			created.Priority = 3
			created.Enabled = false
			created.Parent = g
			fx.eq[name] = created
		end
	end
	local sfx = getGroup("SFX")
	if sfx then
		if not (fx.reverb and fx.reverb.Parent == sfx) then
			local reverb = Instance.new("ReverbSoundEffect")
			reverb.Name = "AudioEnvReverb"
			reverb.DecayTime = 1.4
			reverb.Density = 0.9
			reverb.Diffusion = 1
			reverb.DryLevel = 0
			reverb.WetLevel = -20
			reverb.Priority = 2
			reverb.Parent = sfx
			fx.reverb = reverb
		end
		if not (fx.comp and fx.comp.Parent == sfx) then
			local comp = Instance.new("CompressorSoundEffect")
			comp.Name = "AudioBusCompressor"
			comp.Threshold = -12 -- glue + protects the mix when the cannon fires; transients stay punchy
			comp.Ratio = 3
			comp.Attack = 0.005
			comp.Release = 0.25
			comp.GainMakeup = 0
			comp.Priority = 1
			comp.Parent = sfx
			fx.comp = comp
		end
	end
end

---------------------------------------------------------------------------
-- Voice pools (one-shots; no Instance churn)
---------------------------------------------------------------------------
local rootFolder: Folder = nil :: any -- 2D voices and loops live here (inside SoundService)
local localVoices = {}
local worldVoices = {}
local lengthOf: { [string]: number } = {}
local lastPick: { [string]: number } = {}

local function newVoice(spatial: boolean, index: number)
	local sound = Instance.new("Sound")
	sound.Name = "Voice" .. index
	sound.Volume = 0
	sound.Looped = false
	local holder: Attachment? = nil
	if spatial then
		local attachment = Instance.new("Attachment")
		attachment.Name = "AudioVoice" .. index
		attachment.Parent = workspace.Terrain
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.Parent = attachment
		holder = attachment
	else
		sound.Parent = rootFolder
	end
	return { sound = sound, holder = holder, id = "", busyUntil = 0, started = 0, priority = 0, base = 0, fade = nil :: number? }
end

local function acquire(pool, id: string, priority: number)
	local now = os.clock()
	local free, victim, oldest
	for _, voice in ipairs(pool) do
		if voice.busyUntil <= now then
			if voice.id == id then
				return voice -- already holds this asset: no reload
			end
			free = free or voice
		else
			if voice.priority <= priority and (victim == nil or voice.started < victim.started) then
				victim = voice
			end
			if oldest == nil or voice.started < oldest.started then
				oldest = voice
			end
		end
	end
	if free or victim then
		return free or victim
	end
	-- everything busy with higher priority: take the oldest once its transient is over (never go silent)
	if oldest and now - oldest.started > 0.25 then
		return oldest
	end
	return nil
end

-- Picks a variant: (id, from?, to?, gain). Regions are preferred; avoids immediate repeats;
-- foot "L"/"R" alternates odd/even slices so a walk sounds like two feet.
local function pickVariant(entry: any, key: string, foot: string?)
	local regions = entry.regions
	if type(regions) == "table" and #regions > 0 then
		local n = #regions
		local index = math.random(1, n)
		for _ = 1, 3 do
			if foot and n >= 4 and ((index % 2 == 1) ~= (foot == "L")) then
				index = (index % n) + 1
			end
			if index ~= lastPick[key] then
				break
			end
			index = math.random(1, n)
		end
		lastPick[key] = index
		local r = regions[index]
		return r.id, r.from, r.to, r.gain or 1
	end
	local ids = entry.ids
	if type(ids) == "table" and #ids > 0 then
		local index = math.random(1, #ids)
		if #ids > 1 and index == lastPick[key] then
			index = (index % #ids) + 1
		end
		lastPick[key] = index
		return ids[index], nil, nil, 1
	end
	return nil, nil, nil, 1
end

local function playKey(key: string, opts: { [string]: any }?)
	local o = opts or {}
	local entry = entryOf(key)
	if not entry or not rootFolder then
		return nil, nil
	end
	local id, from, to, gain = pickVariant(entry, key, o.foot)
	if not id then
		return nil, nil
	end
	local position: Vector3? = o.position
	local pool = if position then worldVoices else localVoices
	local priority = o.priority or 1
	local voice = acquire(pool, id, priority)
	if not voice then
		return nil, nil
	end
	local sound: Sound = voice.sound
	if sound.IsPlaying then
		sound:Stop()
	end
	if voice.id ~= id then
		sound.SoundId = id
		voice.id = id
	end
	sound.SoundGroup = getGroup(entry.group)
	local volume = math.clamp((entry.volume or 0.5) * (o.volume or 1) * gain, 0, 10)
	local speed = o.pitch or randomPitch(entry)
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	if voice.holder and position then
		local rollScale = o.rollScale or 1
		sound.RollOffMinDistance = (entry.rollMin or 10) * rollScale
		sound.RollOffMaxDistance = math.max((entry.rollMax or 160) * rollScale, sound.RollOffMinDistance + 1)
		voice.holder.WorldPosition = position
	end
	local duration
	if from and to then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(from, to)
		sound.TimePosition = from
		duration = to - from
	else
		sound.PlaybackRegionsEnabled = false
		sound.TimePosition = 0
		duration = lengthOf[id] or 2.5
	end
	sound:Play()
	local now = os.clock()
	voice.started = now
	voice.busyUntil = now + math.min(duration / math.max(speed, 0.05), entry.maxLifetime or 12) + 0.03
	voice.priority = priority
	voice.base = volume
	voice.fade = nil
	return sound, voice
end

local function fadeVoice(voice, seconds: number)
	if voice and voice.busyUntil > os.clock() then
		voice.fade = 1 / math.max(seconds, 0.02)
	end
end

local function updateVoiceFades(dt: number)
	for _, pool in ipairs({ localVoices, worldVoices }) do
		for _, voice in ipairs(pool) do
			if voice.fade then
				local sound: Sound = voice.sound
				local v = sound.Volume - voice.base * voice.fade * dt
				if v <= 0.001 then
					sound:Stop()
					sound.Volume = 0
					voice.fade = nil
					voice.busyUntil = 0
				else
					sound.Volume = v
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Loops (beds, music, emitters, breathing...) with smooth level fades
---------------------------------------------------------------------------
local function newLoop(key: string, parent: Instance, rateIn: number, rateOut: number?, randomStart: boolean?, spatial: boolean?)
	return {
		key = key,
		parent = parent,
		rateIn = rateIn,
		rateOut = rateOut or rateIn,
		randomStart = randomStart == true,
		spatial = spatial == true,
		level = 0,
		target = 0,
		gain = 1,
		speed = nil :: number?,
		sound = nil :: Sound?,
		entry = nil :: any,
		playing = false,
		fresh = true,
		lastVolume = -1,
	}
end

local function destroyLoop(loop)
	if loop.sound then
		loop.sound:Destroy()
		loop.sound = nil
	end
	loop.playing = false
end

local function updateLoop(loop, dt: number, mult: number?)
	local rate = if loop.target > loop.level then loop.rateIn else loop.rateOut
	loop.level += (loop.target - loop.level) * damp(rate, dt)
	if loop.target <= 0.0001 and loop.level < 0.004 then
		loop.level = 0
		if loop.sound and loop.playing then
			loop.sound:Pause()
			loop.playing = false
		end
		return
	end
	local sound = loop.sound
	if not sound or not sound.Parent then
		local entry = entryOf(loop.key)
		if not entry or type(entry.ids) ~= "table" or #entry.ids == 0 or not loop.parent.Parent then
			loop.target, loop.level = 0, 0
			return
		end
		local created = Instance.new("Sound")
		created.Name = "Loop_" .. loop.key
		created.SoundId = entry.ids[math.random(1, #entry.ids)]
		created.Looped = true
		created.Volume = 0
		created.SoundGroup = getGroup(entry.group)
		if loop.spatial then
			created.RollOffMode = Enum.RollOffMode.InverseTapered
			created.RollOffMinDistance = entry.rollMin or 10
			created.RollOffMaxDistance = entry.rollMax or 160
		end
		created.Parent = loop.parent
		sound = created
		loop.sound = created
		loop.entry = entry
		loop.playing = false
		loop.fresh = true
		loop.lastVolume = -1
	end
	assert(sound)
	if not loop.playing then
		if loop.fresh then
			if loop.randomStart and sound.IsLoaded and sound.TimeLength > 4 then
				sound.TimePosition = math.random() * sound.TimeLength * 0.85
			end
			loop.fresh = false
			sound:Play()
		else
			sound:Resume()
		end
		loop.playing = true
	end
	local volume = math.clamp((loop.entry.volume or 0.5) * loop.level * loop.gain * (mult or 1), 0, 10)
	if math.abs(volume - loop.lastVolume) > 0.0005 then
		sound.Volume = volume
		loop.lastVolume = volume
	end
	if loop.speed and math.abs(sound.PlaybackSpeed - loop.speed) > 0.002 then
		sound.PlaybackSpeed = loop.speed
	end
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local GameState: Instance? = nil
local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

local bedLoops: { [string]: any } = {}
local musicLoops: { [string]: any } = {}
local breathLoop, heartLoop, swimLoop
local emitters: { [Instance]: any } = {}

local settings = { sfx = 1, music = 0.6, ambience = 0.8 }
local ducks = {}
local musicDuck, ambDuck = 1, 1
local muffle, deathMuffle, hitMuffle = 0, 0, 0
local underwater = false
local nightFactor = 0
local currentBiome = "Woodland"
local currentEnv = "Forest"
local reverbDecay, reverbWet = 1.4, -20
local indoorFactor = 1
local desiredMusic: string? = nil
local desiredMusicLevel = 1
local musicSuppressed = false

local lastLocalStep = 0
local lastLanding = 0
local lastMaterial: Enum.Material = Enum.Material.Grass
local slideVoice = nil
local climbPhase = 0

local remoteChars: { [Model]: any } = {}
local simList = {}
local playerConns: { [Player]: { RBXScriptConnection } } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false
local envParams = RaycastParams.new()
envParams.FilterType = Enum.RaycastFilterType.Exclude
envParams.IgnoreWater = true
local rayDirty = true

local function rebuildRayFilters()
	rayDirty = false
	local list = {}
	if character then
		table.insert(list, character)
	end
	for char in pairs(remoteChars) do
		table.insert(list, char)
	end
	local arena = workspace:FindFirstChild("Arena")
	if arena then
		for _, name in ipairs({ "Border", "Loot" }) do
			local child = arena:FindFirstChild(name)
			if child then
				table.insert(list, child)
			end
		end
	end
	rayParams.FilterDescendantsInstances = list
	local envList = table.clone(list)
	local foliage = arena and arena:FindFirstChild("Foliage")
	if foliage then
		table.insert(envList, foliage)
	end
	envParams.FilterDescendantsInstances = envList
end

---------------------------------------------------------------------------
-- Local player foley
---------------------------------------------------------------------------
local function localFloorMaterial(): Enum.Material?
	if humanoid and humanoid.Parent then
		local m = humanoid.FloorMaterial
		if m ~= Enum.Material.Air then
			return m
		end
	end
	if rootPart and rootPart.Parent and humanoid then
		local origin = rootPart.Position
		local reach = humanoid.HipHeight + rootPart.Size.Y * 0.5 + 2
		local result = workspace:Raycast(origin, Vector3.new(0, -reach, 0), rayParams)
		if result then
			return result.Material
		end
	end
	return nil
end

local function onFootstep(material: any, intensity: any, foot: any)
	if typeof(material) == "EnumItem" and material.EnumType == Enum.Material and material ~= Enum.Material.Air then
		lastMaterial = material
	end
	if ClientState.moveState == "Swim" then
		return -- the swim loop covers it
	end
	local now = os.clock()
	if now - lastLocalStep < TUNE.LocalStepMinInterval then
		return
	end
	local key = materialKey(material)
	if not key then
		return
	end
	lastLocalStep = now
	local entry = entryOf(key)
	local i = math.clamp(tonumber(intensity) or 0.6, 0, 1.4)
	playKey(key, {
		volume = 0.25 + 0.75 * i,
		pitch = randomPitch(entry) * (0.97 + 0.05 * math.min(i, 1)),
		foot = if foot == "L" or foot == "R" then foot else nil,
		priority = 2,
	})
end

local function onJumped()
	local key = materialKey(localFloorMaterial() or lastMaterial)
	if key and key ~= "Footstep_Water" then
		playKey(key, { volume = 0.8, priority = 2 })
	end
	playKey("Jump", { volume = 0.8, priority = 1 })
end

local function onLanded(impactSpeed: any)
	local v = math.abs(tonumber(impactSpeed) or 0)
	local now = os.clock()
	if v < 10 or now - lastLanding < 0.25 then
		return
	end
	lastLanding = now
	local material = localFloorMaterial() or lastMaterial
	lastMaterial = material
	local key = materialKey(material)
	local t = math.clamp((v - 10) / (TUNE.HardLandSpeed - 10), 0, 1)
	if key then
		playKey(key, { volume = 0.55 + 0.6 * t, priority = 2, foot = "L" })
		task.delay(0.045 + 0.03 * math.random(), function()
			playKey(key, { volume = 0.45 + 0.5 * t, priority = 2, foot = "R" })
		end)
	end
	if key == "Footstep_Water" then
		playKey("WaterSplash", { volume = 0.35 + 0.65 * t, priority = 3 })
	elseif v >= TUNE.HardLandSpeed then
		playKey("Land_Hard", { volume = math.clamp(0.75 + (v - TUNE.HardLandSpeed) / 45, 0.75, 1.4), priority = 3 })
	elseif v >= TUNE.SoftLandSpeed then
		playKey("Land_Soft", { volume = 0.35 + 0.65 * t, priority = 2 })
	end
end

local function onMoveStateChanged(new: any, old: any)
	if new == "Slide" and old ~= "Slide" then
		local _, voice = playKey("Slide", { volume = 1, priority = 3 })
		slideVoice = voice
	elseif old == "Slide" and new ~= "Slide" and slideVoice then
		fadeVoice(slideVoice, 0.18)
		slideVoice = nil
	end
	if new == "Mantle" then
		playKey("Mantle", { volume = 1, priority = 3 })
		task.delay(0.09, function()
			playKey("Jump", { volume = 0.6, priority = 1 })
		end)
	elseif new == "Climb" and old ~= "Climb" then
		playKey("Climb", { volume = 0.9, priority = 2 })
		climbPhase = 0
	elseif new == "Swim" and old ~= "Swim" then
		local vel = if rootPart then rootPart.AssemblyLinearVelocity else ClientState.velocity
		local vy = if typeof(vel) == "Vector3" then vel.Y else 0
		if old == "Air" or vy < -12 then
			playKey("WaterSplash", { volume = math.clamp(math.abs(vy) / 45, 0.35, 1.1), priority = 3 })
		end
	end
end

local function onLocalDied()
	deathMuffle = 1
	AudioController.duck(0.35, 0.45, 3)
end

local function onDamageTaken(info: any)
	local amount = if type(info) == "table" then tonumber(info.amount) or 0 else 0
	if amount >= 12 then
		hitMuffle = math.max(hitMuffle, math.clamp(amount / 60, 0.2, 0.6))
	end
end

local function onCharacter(char: Model)
	character = char
	humanoid = nil
	rootPart = nil
	rayDirty = true
	task.spawn(function()
		local hum = char:WaitForChild("Humanoid", 10)
		local root = char:WaitForChild("HumanoidRootPart", 10)
		if character ~= char then
			return
		end
		if hum and hum:IsA("Humanoid") then
			humanoid = hum
			hum.Died:Connect(onLocalDied)
		end
		if root and root:IsA("BasePart") then
			rootPart = root
		end
	end)
end

---------------------------------------------------------------------------
-- Other contenders (3D footsteps for stealth)
---------------------------------------------------------------------------
local function newRemoteState(char: Model)
	return {
		char = char, root = nil :: BasePart?, hum = nil :: Humanoid?, dist = 0,
		phase = math.random() * 0.5, foot = "L", lastProbe = 0, grounded = true, swimming = false,
		material = Enum.Material.Grass, airTime = 0, minVy = 0, stance = "Stand", climb = 0,
	}
end

local function trackCharacter(char: Model)
	if char and not remoteChars[char] then
		remoteChars[char] = newRemoteState(char)
		rayDirty = true
	end
end

local function untrackCharacter(char: Model)
	if char and remoteChars[char] then
		remoteChars[char] = nil
		rayDirty = true
	end
end

local function watchPlayer(other: Player)
	if other == player or playerConns[other] then
		return
	end
	playerConns[other] = {
		other.CharacterAdded:Connect(trackCharacter),
		other.CharacterRemoving:Connect(untrackCharacter),
	}
	if other.Character then
		trackCharacter(other.Character)
	end
end

local function unwatchPlayer(other: Player)
	local conns = playerConns[other]
	if conns then
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end
	playerConns[other] = nil
	if other.Character then
		untrackCharacter(other.Character)
	end
end

local function feetOf(root: BasePart, hum: Humanoid): Vector3
	return root.Position - Vector3.new(0, hum.HipHeight + root.Size.Y * 0.5 - 0.3, 0)
end

local function probeFloor(st, root: BasePart, hum: Humanoid)
	local below = hum.HipHeight + root.Size.Y * 0.5
	local origin = root.Position + Vector3.new(0, 1.2, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -(below + 2.8), 0), rayParams)
	if result then
		st.grounded = true
		st.material = result.Material
		-- water surface above the hips = swimming (strokes instead of steps)
		st.swimming = result.Material == Enum.Material.Water and result.Position.Y > root.Position.Y - below * 0.5
	else
		st.grounded = false
		st.swimming = false
	end
end

local function remoteStep(st, root: BasePart, hum: Humanoid, horizontalSpeed: number, stance: string)
	local key = materialKey(st.material)
	if not key then
		return
	end
	local intensity = math.clamp((horizontalSpeed - 4) / 17, 0.2, 1)
	local volume = (0.45 + 0.55 * intensity) * TUNE.RemoteGain
	local rollScale = 1
	if stance == "Crouch" then
		volume *= TUNE.CrouchVolume
		rollScale = TUNE.CrouchRollScale
	end
	local foot = st.foot
	st.foot = if foot == "L" then "R" else "L"
	playKey(key, { position = feetOf(root, hum), volume = volume, foot = foot, rollScale = rollScale, priority = 1 })
end

local function remoteLand(st, root: BasePart, hum: Humanoid, impact: number)
	local key = materialKey(st.material)
	local feet = feetOf(root, hum)
	local t = math.clamp((impact - 10) / (TUNE.HardLandSpeed - 10), 0, 1)
	if key then
		playKey(key, { position = feet, volume = (0.6 + 0.5 * t) * TUNE.RemoteGain, foot = "L", priority = 2 })
	end
	if key == "Footstep_Water" then
		playKey("WaterSplash", { position = feet, volume = 0.4 + 0.6 * t, priority = 2 })
	elseif impact >= TUNE.HardLandSpeed then
		playKey("Land_Hard", { position = feet, volume = 0.9, priority = 2 })
	elseif impact >= TUNE.SoftLandSpeed then
		playKey("Land_Soft", { position = feet, volume = 0.4 + 0.6 * t, priority = 2 })
	end
end

local function refreshSimList(camPos: Vector3)
	table.clear(simList)
	for char, st in pairs(remoteChars) do
		if char.Parent == nil then
			remoteChars[char] = nil
			rayDirty = true
		else
			local root = st.root
			if not root or root.Parent ~= char then
				local found = char:FindFirstChild("HumanoidRootPart")
				root = if found and found:IsA("BasePart") then found else nil
				st.root = root
			end
			if root then
				local d = (root.Position - camPos).Magnitude
				if d <= TUNE.RemoteRange then
					st.dist = d
					table.insert(simList, st)
				end
			end
		end
	end
	table.sort(simList, function(a, b)
		return a.dist < b.dist
	end)
	for i = #simList, TUNE.RemoteMaxSimulated + 1, -1 do
		simList[i] = nil
	end
end

local function simulateRemote(st, dt: number, now: number)
	local char: Model = st.char
	local root: BasePart? = st.root
	if not root or root.Parent ~= char then
		return
	end
	local hum: Humanoid? = st.hum
	if not hum or hum.Parent ~= char then
		hum = char:FindFirstChildOfClass("Humanoid")
		st.hum = hum
	end
	if not hum or hum.Health <= 0 then
		return
	end
	local vel = root.AssemblyLinearVelocity
	local hs = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	if now - st.lastProbe > 0.1 then
		probeFloor(st, root, hum)
		st.lastProbe = now
	end
	-- landings
	if st.grounded then
		if st.airTime > 0.28 and -st.minVy >= TUNE.SoftLandSpeed then
			remoteLand(st, root, hum, -st.minVy)
		end
		st.airTime = 0
		st.minVy = 0
	else
		st.airTime += dt
		if vel.Y < st.minVy then
			st.minVy = vel.Y
		end
	end
	-- stance (replicated attribute set by the server from SetStance)
	local stance = char:GetAttribute("Stance")
	if type(stance) ~= "string" then
		stance = "Stand"
	end
	if stance ~= st.stance then
		if stance == "Slide" and st.grounded then
			playKey("Slide", { position = feetOf(root, hum), volume = 0.9, priority = 2 })
		end
		st.stance = stance
	end
	if stance == "Slide" then
		st.phase = 0.5
		return
	end
	if stance == "Climb" then
		local vy = math.abs(vel.Y)
		if vy > 1 then
			st.climb += dt * vy / 3.2
			if st.climb >= 1 then
				st.climb -= 1
				playKey("Climb", { position = root.Position, volume = 0.8 * TUNE.RemoteGain, priority = 1 })
			end
		end
		return
	end
	if st.swimming then
		if hs > 1.5 then
			st.phase += dt * 0.9
			if st.phase >= 1 then
				st.phase -= 1
				playKey("Footstep_Water", { position = root.Position, volume = 0.55, pitch = 0.85 + math.random() * 0.1, priority = 1 })
			end
		end
		return
	end
	if not st.grounded or hs < TUNE.StepMinSpeed then
		st.phase = math.min(st.phase, 0.55) -- the first step after moving again comes quickly
		return
	end
	local rate = math.clamp(0.75 + hs * 0.095, 1.1, 3.3) -- steps per second (walk ~2, sprint ~2.75)
	st.phase += dt * rate
	if st.phase >= 1 then
		st.phase -= 1
		probeFloor(st, root, hum)
		st.lastProbe = now
		if st.grounded and not st.swimming then
			remoteStep(st, root, hum, hs, stance)
		end
	end
end

---------------------------------------------------------------------------
-- Ambience emitters (AmbientEmitter tag, SoundKey attribute)
---------------------------------------------------------------------------
local function emitterPosition(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Attachment") then
		return inst.WorldPosition
	end
	return nil
end

local function removeEmitter(inst: Instance)
	local loop = emitters[inst]
	if loop then
		destroyLoop(loop)
		emitters[inst] = nil
	end
end

local function addEmitter(inst: Instance)
	if emitters[inst] or not (inst:IsA("BasePart") or inst:IsA("Attachment")) then
		return
	end
	local key = inst:GetAttribute("SoundKey")
	if type(key) ~= "string" then
		return
	end
	local entry = entryOf(key)
	if not entry or type(entry.ids) ~= "table" or #entry.ids == 0 then
		return
	end
	local loop = newLoop(key, inst, 0.8, 0.8, true, true)
	local gain = inst:GetAttribute("Volume")
	loop.gain = if type(gain) == "number" then math.clamp(gain, 0, 4) else 1
	loop.reach = (entry.rollMax or 160) + TUNE.EmitterMargin
	emitters[inst] = loop
end

local emitterCandidates = {}
local function updateEmitterTargets(camPos: Vector3)
	table.clear(emitterCandidates)
	for inst, loop in pairs(emitters) do
		if inst.Parent == nil then
			removeEmitter(inst)
		else
			local pos = emitterPosition(inst)
			loop.target = 0
			if pos then
				local d = (pos - camPos).Magnitude
				if d <= loop.reach then
					loop.dist = d
					table.insert(emitterCandidates, loop)
				end
			end
		end
	end
	table.sort(emitterCandidates, function(a, b)
		return a.dist < b.dist
	end)
	for i = 1, math.min(#emitterCandidates, TUNE.MaxEmitters) do
		local loop = emitterCandidates[i]
		local t = 1
		if loop.key == "Emit_Frogs" then
			t = 0.45 + 0.55 * nightFactor
		end
		loop.target = t
	end
end

---------------------------------------------------------------------------
-- Ambience beds, environment and music decisions
---------------------------------------------------------------------------
local function computeNight(clock: number): number
	local evening = smoothstep(TUNE.NightFrom, TUNE.NightTo, clock)
	local morning = 1 - smoothstep(TUNE.DawnFrom, TUNE.DawnTo, clock)
	return math.max(evening, morning)
end

local bedWeights: { [string]: number } = {}
local function updateBedTargets(camPos: Vector3)
	table.clear(bedWeights)
	local n = nightFactor
	for _, sample in ipairs(BIOME_SAMPLES) do
		local biome = ArenaLayout.getBiome(camPos + sample[1])
		if sample[2] >= 0.4 then
			currentBiome = biome
		end
		local mix = BIOME_MIX[biome] or BIOME_MIX.Woodland
		local w = sample[2]
		for key, v in pairs(mix.day) do
			bedWeights[key] = (bedWeights[key] or 0) + v * (1 - n) * w
		end
		for key, v in pairs(mix.night) do
			bedWeights[key] = (bedWeights[key] or 0) + v * n * w
		end
	end
	local envMult = (if underwater then 0.45 else 1) * indoorFactor
	for key, loop in pairs(bedLoops) do
		loop.target = (bedWeights[key] or 0) * envMult
	end
end

local function cameraUnderwater(pos: Vector3): boolean
	local cell = Vector3.new(math.floor(pos.X / 4) * 4, math.floor(pos.Y / 4) * 4, math.floor(pos.Z / 4) * 4)
	local ok, materials, occupancies = pcall(function()
		return workspace.Terrain:ReadVoxels(Region3.new(cell, cell + Vector3.new(4, 4, 4)), 4)
	end)
	if not ok or not materials or not materials[1] or not materials[1][1] then
		return false
	end
	local material = materials[1][1][1]
	if material ~= Enum.Material.Water then
		return false
	end
	local occupancy = occupancies[1][1][1] or 0
	return occupancy >= 0.99 or pos.Y < cell.Y + occupancy * 4
end

local function detectEnvironment(camPos: Vector3): string
	if underwater then
		return "Underwater"
	end
	local hits, terrainHits = 0, 0
	for _, dir in ipairs(ENCLOSURE_RAYS) do
		local result = workspace:Raycast(camPos, dir, envParams)
		if result and not SOFT_ROOF[result.Material.Name] then
			hits += 1
			if result.Instance == workspace.Terrain then
				terrainHits += 1
			end
		end
	end
	if hits == #ENCLOSURE_RAYS then
		return if terrainHits >= 2 then "Cave" else "Room"
	end
	return BIOME_ENV[currentBiome] or "Forest"
end

local function attr(name: string): any
	return if GameState then GameState:GetAttribute(name) else nil
end

local function decideMusic(): (string?, number)
	if musicSuppressed then
		return nil, 1
	end
	local phase = attr("Phase")
	if phase == "Ending" then
		return nil, 1 -- the victory sting carries it
	end
	local watchingArena = ClientState.inArena or ClientState.spectating ~= nil
	if not watchingArena then
		return "Music_Lobby", 1
	end
	if phase == "Countdown" then
		return "Music_Tension", 0.6
	end
	if phase == "Active" then
		local practice = attr("Practice") == true
		local alive = tonumber(attr("AliveCount")) or 0
		local started = tonumber(attr("StartedCount")) or 0
		if not practice and started >= 3 and alive >= 1 and alive <= TUNE.FinalAlive then
			return "Music_Final", 1
		end
		if attr("BorderShrinking") == true then
			return "Music_Tension", 1
		end
		if not practice and started > TUNE.TensionAlive and alive <= TUNE.TensionAlive then
			return "Music_Tension", 1
		end
		if attr("ArenaEvent") == "Feast" then
			return "Music_Tension", 0.75
		end
		local startedAt = tonumber(attr("RoundStartedAt")) or 0
		if startedAt > 0 and workspace:GetServerTimeNow() - startedAt < TUNE.OpeningMusicTime then
			return "Music_Tension", 0.8
		end
		return nil, 1 -- exploration: ambience only, the arena breathes
	end
	return "Music_Lobby", 1
end

---------------------------------------------------------------------------
-- Ducking of stings (2D Sfx sounds are parented to SoundService by Shared.Sfx)
---------------------------------------------------------------------------
local function addReverbTail(sound: Sound, spec: any)
	if spec.reverb and not sound:FindFirstChild("AudioTail") then
		local reverb = Instance.new("ReverbSoundEffect")
		reverb.Name = "AudioTail"
		reverb.DecayTime = spec.reverb[1]
		reverb.WetLevel = spec.reverb[2]
		reverb.DryLevel = -1
		reverb.Density = 0.85
		reverb.Diffusion = 0.9
		reverb.Parent = sound
	end
	if spec.eq and not sound:FindFirstChild("AudioDistance") then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.Name = "AudioDistance"
		eq.LowGain = spec.eq[1]
		eq.MidGain = spec.eq[2]
		eq.HighGain = spec.eq[3]
		eq.Parent = sound
	end
end

local function onSfxSound(sound: Instance)
	if not sound:IsA("Sound") then
		return
	end
	local spec = DUCKS[sound.Name]
	if not spec then
		return
	end
	AudioController.duck(spec.music, spec.amb, spec.time)
	addReverbTail(sound, spec)
end

---------------------------------------------------------------------------
-- Main update
---------------------------------------------------------------------------
local timers = { sim = 0, beds = 0, env = 0, water = 0, music = 0, debug = 0, rays = 0 }
local lastGroupVolumes: { [string]: number } = {}

local function setGroupVolume(name: string, value: number)
	local g = getGroup(name)
	if g and math.abs((lastGroupVolumes[name] or -1) - value) > 0.002 then
		g.Volume = value
		lastGroupVolumes[name] = value
	end
end

local function updateMix(dt: number, now: number)
	-- ducks
	local musicTarget, ambTarget = 1, 1
	for i = #ducks, 1, -1 do
		local d = ducks[i]
		if now >= d.untilTime then
			table.remove(ducks, i)
		else
			musicTarget = math.min(musicTarget, d.music)
			ambTarget = math.min(ambTarget, d.amb)
		end
	end
	musicDuck += (musicTarget - musicDuck) * damp(if musicTarget < musicDuck then 6 else 0.6, dt)
	ambDuck += (ambTarget - ambDuck) * damp(if ambTarget < ambDuck then 6 else 0.8, dt)
	setGroupVolume("SFX", settings.sfx)
	setGroupVolume("UI", settings.sfx * 0.8)
	-- music ducking is applied to our music loops only, so stings in the Music group (Victory, RollCall) stay full
	setGroupVolume("Music", settings.music)
	setGroupVolume("Ambience", settings.ambience * ambDuck)
	-- muffle (underwater, death, heavy hits)
	deathMuffle = math.max(0, deathMuffle - dt / 3)
	hitMuffle = math.max(0, hitMuffle - dt * 2.5)
	local target = math.max(if underwater then 1 else 0, deathMuffle * 0.8, hitMuffle)
	muffle += (target - muffle) * damp(if target > muffle then 10 else 4, dt)
	for name, eq in pairs(fx.eq) do
		if eq.Parent then
			local depth = if name == "Music" then 0.35 else 1
			local m = muffle * depth
			local on = m > 0.01
			if eq.Enabled ~= on then
				eq.Enabled = on
			end
			if on then
				eq.HighGain = -38 * m
				eq.MidGain = -14 * m
				eq.LowGain = 2 * m
			end
		end
	end
	-- environment reverb on the SFX bus
	local preset = REVERB[currentEnv] or REVERB.Forest
	local k = damp(2, dt)
	reverbDecay += (preset[1] - reverbDecay) * k
	reverbWet += (preset[2] - reverbWet) * k
	local reverb = fx.reverb
	if reverb and reverb.Parent then
		if math.abs(reverb.DecayTime - reverbDecay) > 0.02 then
			reverb.DecayTime = reverbDecay
		end
		if math.abs(reverb.WetLevel - reverbWet) > 0.1 then
			reverb.WetLevel = reverbWet
		end
		if reverb.Density ~= preset[3] then
			reverb.Density = preset[3]
		end
		if reverb.Diffusion ~= preset[4] then
			reverb.Diffusion = preset[4]
		end
	end
end

local function updateLocalLoops(dt: number)
	local hum = humanoid
	local alive = hum ~= nil and hum.Parent ~= nil and hum.Health > 0
	-- breathing: exhausted or low stamina
	local stamina = tonumber(ClientState.stamina) or 1
	local breath = 0
	if alive then
		if ClientState.exhausted then
			breath = 1
		elseif stamina < 0.4 then
			breath = ((0.4 - stamina) / 0.4) ^ 1.2 * 0.85
		end
	end
	breathLoop.target = breath
	breathLoop.speed = 0.96 + 0.08 * breath
	updateLoop(breathLoop, dt)
	-- heartbeat: low health
	local heart = 0
	if alive and hum then
		local fraction = hum.Health / math.max(hum.MaxHealth, 1)
		if fraction < LOW_HEALTH then
			heart = math.clamp((LOW_HEALTH - fraction) / math.max(0.05, LOW_HEALTH - 0.1), 0.3, 1)
		end
	end
	heartLoop.target = heart
	heartLoop.speed = 0.95 + 0.35 * heart
	updateLoop(heartLoop, dt)
	-- swimming
	local swim = 0
	if alive and ClientState.moveState == "Swim" then
		local speed = tonumber(ClientState.speed) or 0
		swim = math.clamp(speed / Config.Movement.SwimSpeed, 0.15, 1)
	end
	swimLoop.target = swim
	updateLoop(swimLoop, dt)
	-- climbing cadence
	if alive and ClientState.moveState == "Climb" then
		local vel = if rootPart then rootPart.AssemblyLinearVelocity else ClientState.velocity
		local vy = if typeof(vel) == "Vector3" then math.abs(vel.Y) else 0
		if vy > 1 then
			climbPhase += dt * vy / 3.2
			if climbPhase >= 1 then
				climbPhase -= 1
				playKey("Climb", { volume = 0.75 + math.random() * 0.2, priority = 2 })
			end
		end
	else
		climbPhase = 0.6
	end
end

---------------------------------------------------------------------------
-- Other contenders' bow draws (QW9): CombatService tells everyone else "Draw" when a draw starts and "Release" when
-- it is loosed or let down (cancelled = true). The creak plays at the archer and follows them while it lasts.
---------------------------------------------------------------------------
local drawVoices: { [number]: { voice: any, part: BasePart, started: number } } = {}

local function stopRemoteDraw(userId: number, seconds: number)
	local entry = drawVoices[userId]
	if entry then
		drawVoices[userId] = nil
		if entry.voice.started == entry.started then
			fadeVoice(entry.voice, seconds)
		end
	end
end

local function onCombatAction(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local userId = tonumber(payload.userId)
	if not userId or userId == player.UserId then
		return
	end
	local action = payload.action
	if action == "Draw" then
		stopRemoteDraw(userId, 0.05)
		local archer = Players:GetPlayerByUserId(userId)
		local char = archer and archer.Character
		local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
		local camera = workspace.CurrentCamera
		if not (part and part:IsA("BasePart") and camera) then
			return
		end
		if (part.Position - camera.CFrame.Position).Magnitude > TUNE.RemoteDrawRange then
			return
		end
		local _, voice = playKey("BowDraw", { position = part.Position, priority = 3, volume = TUNE.RemoteDrawGain })
		if voice then
			drawVoices[userId] = { voice = voice, part = part, started = voice.started }
		end
	elseif action == "Release" or action == "Throw" or action == "Swing" then
		stopRemoteDraw(userId, if payload.cancelled then 0.25 else 0.06)
	end
end

local function updateRemoteDraws()
	local now = os.clock()
	for userId, entry in pairs(drawVoices) do
		local voice = entry.voice
		if voice.started ~= entry.started or voice.busyUntil <= now or not entry.part.Parent then
			drawVoices[userId] = nil
		elseif voice.holder then
			voice.holder.WorldPosition = entry.part.Position
		end
	end
end

local debugInfo = {}
local function writeDebug()
	local parts = {}
	for key, loop in pairs(bedLoops) do
		if loop.level > 0.01 then
			table.insert(parts, string.format("%s=%.2f", string.sub(key, 5), loop.level))
		end
	end
	table.sort(parts)
	local busy = 0
	local now = os.clock()
	for _, voice in ipairs(worldVoices) do
		if voice.busyUntil > now then
			busy += 1
		end
	end
	local activeEmitters = 0
	for _, loop in pairs(emitters) do
		if loop.playing then
			activeEmitters += 1
		end
	end
	debugInfo = {
		biome = currentBiome,
		env = currentEnv,
		night = math.floor(nightFactor * 100) / 100,
		music = desiredMusic or "none",
		beds = table.concat(parts, " "),
		underwater = underwater,
		worldVoicesBusy = busy,
		remoteSimulated = #simList,
		emitters = activeEmitters,
	}
	if IS_STUDIO then
		SoundService:SetAttribute("AudioDebug", string.format("biome=%s env=%s night=%.2f music=%s beds=[%s] uw=%s voices=%d remote=%d emitters=%d",
			currentBiome, currentEnv, nightFactor, debugInfo.music, debugInfo.beds, tostring(underwater), busy, #simList, activeEmitters))
	end
end

local function update(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero

	if rayDirty then
		timers.rays += dt
		if timers.rays > 0.5 then
			timers.rays = 0
			rebuildRayFilters()
		end
	end

	timers.water += dt
	if timers.water >= 0.125 then
		timers.water = 0
		local wasUnder = underwater
		underwater = cameraUnderwater(camPos)
		if underwater and not wasUnder then
			playKey("WaterSplash", { volume = 0.35, pitch = 0.7, priority = 2 })
		end
	end

	timers.env += dt
	if timers.env >= 0.25 then
		timers.env = 0
		currentEnv = detectEnvironment(camPos)
		local indoorTarget = if currentEnv == "Room" then 0.45 elseif currentEnv == "Cave" then 0.5 else 1
		indoorFactor += (indoorTarget - indoorFactor) * 0.5
	end

	timers.beds += dt
	if timers.beds >= 0.2 then
		timers.beds = 0
		local clock = Lighting.ClockTime
		nightFactor += (computeNight(clock) - nightFactor) * 0.25
		updateBedTargets(camPos)
		updateEmitterTargets(camPos)
	end

	timers.music += dt
	if timers.music >= 0.5 then
		timers.music = 0
		desiredMusic, desiredMusicLevel = decideMusic()
		for key, loop in pairs(musicLoops) do
			loop.target = if key == desiredMusic then desiredMusicLevel else 0
			loop.rateIn = if key == "Music_Final" then TUNE.FinalFadeIn else TUNE.MusicFadeIn
		end
	end

	timers.sim += dt
	if timers.sim >= 0.4 then
		timers.sim = 0
		refreshSimList(camPos)
	end
	for _, st in ipairs(simList) do
		simulateRemote(st, dt, now)
	end

	updateMix(dt, now)
	updateVoiceFades(dt)
	for _, loop in pairs(bedLoops) do
		updateLoop(loop, dt)
	end
	for _, loop in pairs(musicLoops) do
		updateLoop(loop, dt, musicDuck)
	end
	local emitterMult = if underwater then 0.5 else 1
	for _, loop in pairs(emitters) do
		updateLoop(loop, dt, emitterMult)
	end
	updateLocalLoops(dt)
	updateRemoteDraws()

	timers.debug += dt
	if timers.debug >= 1 then
		timers.debug = 0
		ensureEffects() -- cheap parent checks; covers SoundGroups that replicate late
		writeDebug()
	end
end

---------------------------------------------------------------------------
-- Preload short assets so the first footstep or hit is never late
---------------------------------------------------------------------------
local function preload()
	local ids, seen = {}, {}
	local function add(id: any)
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	-- footsteps first, then every other non-looped sound (loops fade in, so they can stream in later)
	for key, entry in pairs(Sounds) do
		if type(entry) == "table" and string.sub(key, 1, 9) == "Footstep_" and type(entry.regions) == "table" then
			for _, r in ipairs(entry.regions) do
				add(r.id)
			end
		end
	end
	for _, entry in pairs(Sounds) do
		if type(entry) == "table" and not entry.looped then
			for _, id in ipairs(entry.ids or {}) do
				add(id)
			end
			if type(entry.regions) == "table" then
				for _, r in ipairs(entry.regions) do
					add(r.id)
				end
			end
		end
	end
	local probeFolder = Instance.new("Folder")
	probeFolder.Name = "Preload"
	probeFolder.Parent = rootFolder
	for i = 1, #ids, 16 do
		local batch = {}
		for j = i, math.min(i + 15, #ids) do
			local probe = Instance.new("Sound")
			probe.SoundId = ids[j]
			probe.Volume = 0
			probe.Parent = probeFolder
			table.insert(batch, probe)
		end
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		for _, probe in ipairs(batch) do
			if probe.TimeLength > 0 then
				lengthOf[probe.SoundId] = probe.TimeLength
			end
		end
		task.wait()
	end
	probeFolder:Destroy()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function AudioController.play(key: string, opts: { [string]: any }?)
	if type(key) ~= "string" then
		return nil, nil
	end
	if type(opts) == "table" and opts.position ~= nil and typeof(opts.position) ~= "Vector3" then
		local copy = table.clone(opts)
		copy.position = nil
		return playKey(key, copy)
	end
	local o = if type(opts) == "table" then opts else {}
	if o.priority == nil then
		o = table.clone(o)
		o.priority = 2
	end
	return playKey(key, o)
end

function AudioController.footstepAt(position: Vector3, material: Enum.Material, intensity: number?, crouched: boolean?)
	local key = materialKey(material)
	if not key or typeof(position) ~= "Vector3" then
		return
	end
	local i = math.clamp(intensity or 0.6, 0, 1.4)
	local volume = (0.35 + 0.65 * i) * TUNE.RemoteGain
	local rollScale = 1
	if crouched then
		volume *= TUNE.CrouchVolume
		rollScale = TUNE.CrouchRollScale
	end
	playKey(key, { position = position, volume = volume, rollScale = rollScale, priority = 1 })
end

function AudioController.duck(musicFactor: number, ambienceFactor: number, seconds: number)
	table.insert(ducks, {
		music = math.clamp(tonumber(musicFactor) or 1, 0, 1),
		amb = math.clamp(tonumber(ambienceFactor) or 1, 0, 1),
		untilTime = os.clock() + math.clamp(tonumber(seconds) or 1, 0, 60),
	})
end

function AudioController.materialKey(material: Enum.Material): string?
	return materialKey(material)
end

function AudioController.setMusicSuppressed(suppressed: boolean)
	musicSuppressed = suppressed == true
end

function AudioController.debugState()
	return debugInfo
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local function applySettings(s: any)
	local source = if type(s) == "table" then s else ClientState.settings
	settings.sfx = math.clamp(tonumber(source.sfxVolume) or 1, 0, 1)
	settings.music = math.clamp(tonumber(source.musicVolume) or 0.6, 0, 1)
	settings.ambience = math.clamp(tonumber(source.ambienceVolume) or 0.8, 0, 1)
end

function AudioController.Init(_registry)
	-- client-local infrastructure (no yields)
	local existing = SoundService:FindFirstChild("AudioController")
	if existing then
		existing:Destroy()
	end
	rootFolder = Instance.new("Folder")
	rootFolder.Name = "AudioController"
	rootFolder.Parent = SoundService
	for i = 1, TUNE.LocalVoices do
		table.insert(localVoices, newVoice(false, i))
	end
	for i = 1, TUNE.WorldVoices do
		table.insert(worldVoices, newVoice(true, i))
	end
	for _, key in ipairs(BED_KEYS) do
		bedLoops[key] = newLoop(key, rootFolder, TUNE.BedFade, TUNE.BedFade, true)
	end
	for _, key in ipairs({ "Music_Lobby", "Music_Tension", "Music_Final" }) do
		musicLoops[key] = newLoop(key, rootFolder, TUNE.MusicFadeIn, TUNE.MusicFadeOut, false)
	end
	breathLoop = newLoop("BreathHeavy", rootFolder, 1.6, 0.9, true)
	heartLoop = newLoop("Heartbeat", rootFolder, 0.9, 0.7, false)
	swimLoop = newLoop("Swim", rootFolder, 3, 2.5, true)

	SoundService.DopplerScale = 0.5
	SoundService.RolloffScale = 1
	ensureEffects()
	applySettings(ClientState.settings)

	ClientState.footstep:Connect(onFootstep)
	ClientState.jumped:Connect(onJumped)
	ClientState.landed:Connect(onLanded)
	ClientState.moveStateChanged:Connect(onMoveStateChanged)
	ClientState.damageTaken:Connect(onDamageTaken)
	ClientState.settingsChanged:Connect(applySettings)

	SoundService.ChildAdded:Connect(onSfxSound)
end

function AudioController.Start()
	GameState = ReplicatedStorage:WaitForChild("GameState", 30)
	ensureEffects()

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	for _, other in ipairs(Players:GetPlayers()) do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(unwatchPlayer)

	-- QW9: hear other contenders draw a bow
	local okRemote, remote = pcall(Net.event, "CombatAction")
	if okRemote and remote then
		remote.OnClientEvent:Connect(function(payload)
			local ok, err = pcall(onCombatAction, payload)
			if not ok then
				warn("[AudioController] CombatAction: " .. tostring(err))
			end
		end)
	end

	CollectionService:GetInstanceAddedSignal("AmbientEmitter"):Connect(addEmitter)
	CollectionService:GetInstanceRemovedSignal("AmbientEmitter"):Connect(removeEmitter)
	for _, inst in ipairs(CollectionService:GetTagged("AmbientEmitter")) do
		addEmitter(inst)
	end

	local failures, lastWarn = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(update, math.min(dt, 0.1))
		if not ok then
			failures += 1
			local now = os.clock()
			if now - lastWarn > 10 then
				lastWarn = now
				warn(string.format("[AudioController] update error (%d): %s", failures, tostring(err)))
			end
		end
	end)

	preload()
end

return AudioController
