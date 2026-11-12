--[[
	Sfx - play registered sounds (see Shared.Sounds) by key.
	Client: Sfx.play(key, { position = Vector3?, parent = Instance?, volume = number?, pitch = number?, looped = boolean? }) -> Sound?
	        No position/parent = 2D (UI-style). Looped sounds are returned; the caller must Stop() and Destroy() them.
	Server: Sfx.play(key, { position = Vector3?, volume = number?, pitch = number?, exclude = Player? }) broadcasts to clients.
	        Sfx.playFor(player, key, opts) plays for one client.
	ClientMain calls Sfx.initClient() once so server broadcasts are heard.
]]
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local Sounds = require(script.Parent.Sounds)
local Net = require(script.Parent.Net)

local IS_SERVER = RunService:IsServer()

local Sfx = {}

local function pickPitch(entry, opts): number
	if opts.pitch then
		return opts.pitch
	end
	local p = entry.pitch
	if type(p) == "table" then
		return p[1] + math.random() * (p[2] - p[1])
	end
	return p or 1
end

local function payload(opts)
	if not opts then
		return nil
	end
	return { position = opts.position, volume = opts.volume, pitch = opts.pitch }
end

function Sfx.play(key: string, opts: { [string]: any }?): Sound?
	local o = opts or {}
	if IS_SERVER then
		local remote = Net.event("Sfx")
		local data = payload(o)
		if o.exclude then
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= o.exclude then
					remote:FireClient(player, key, data)
				end
			end
		else
			remote:FireAllClients(key, data)
		end
		return nil
	end

	local entry = Sounds[key]
	if type(entry) ~= "table" or type(entry.ids) ~= "table" or #entry.ids == 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = entry.ids[math.random(1, #entry.ids)]
	sound.Volume = (entry.volume or 0.5) * (o.volume or 1)
	sound.PlaybackSpeed = pickPitch(entry, o)
	sound.Looped = o.looped == true or entry.looped == true
	local group = SoundService:FindFirstChild(entry.group or "SFX")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end

	local holder: Instance = sound
	if o.position then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Sfx_" .. key
		attachment.Parent = workspace.Terrain
		attachment.WorldPosition = o.position
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = entry.rollMin or 10
		sound.RollOffMaxDistance = entry.rollMax or 160
		sound.Parent = attachment
		holder = attachment
	elseif o.parent then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = entry.rollMin or 10
		sound.RollOffMaxDistance = entry.rollMax or 160
		sound.Parent = o.parent
	else
		sound.Parent = SoundService
	end
	sound:Play()

	if not sound.Looped then
		sound.Ended:Once(function()
			holder:Destroy()
		end)
		task.delay(entry.maxLifetime or 12, function()
			if holder.Parent then
				holder:Destroy()
			end
		end)
	end
	return sound
end

function Sfx.playFor(player: Player, key: string, opts: { [string]: any }?)
	assert(IS_SERVER, "Sfx.playFor is server-only")
	Net.event("Sfx"):FireClient(player, key, payload(opts))
end

local clientReady = false
function Sfx.initClient()
	if IS_SERVER or clientReady then
		return
	end
	clientReady = true
	Net.event("Sfx").OnClientEvent:Connect(function(key, opts)
		if type(key) == "string" then
			Sfx.play(key, if type(opts) == "table" then opts else nil)
		end
	end)
end

return Sfx
