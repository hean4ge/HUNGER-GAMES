--[[
	ApplyVoiceSettings - paste into Roblox Studio's command bar (View > Command Bar), in Edit mode (not during a playtest).
	Only after the release QA, when the testers are done with Studio (docs/design/VoiceMode.md, section 8).

	READ THIS FIRST: these settings change voice for EVERY player in the place as soon as it is published, whatever
	Config.Voice.Enabled says. Config.Voice.Enabled only switches our scripts on or off; UseAudioApi switches Roblox's own
	voice from its old built-in system to the Audio API one (AudioDeviceInput, AudioEmitter, AudioListener). So:
	  1. Run it first in the private TEST COPY (a separate experience): it runs there without any flag.
	  2. On the LIVE place (120572716460286) it refuses unless Config.Voice.Enabled is already true in this place AND you
	     set APPLY_TO_LIVE_PLACE below to true: UseAudioApi and our scripts go live in the same publish, never one alone.
	To keep the switch as quiet as possible it also sets DefaultDistanceAttenuation = Legacy: Roblox's own voice keeps
	today's fade (linear-squared, 7 to 80 studs) wherever our scripts don't set their own curves.

	Why the command bar: VoiceChatService.UseAudioApi, EnableDefaultVoice and DefaultDistanceAttenuation carry the
	PluginOrOpenCloud capability. Game scripts can't set them; Studio's Properties window, the command bar, a plugin or an
	Open Cloud Luau task can. (EnableVoiceVolumeControls is RobloxScriptSecurity: it is only read here. If Studio's
	Properties window shows it, leave it ticked: it is Roblox's own global and per-player voice volume.)

	It changes only these, and prints every value before and after:
	  VoiceChatService.UseAudioApi                -> Enabled  (Automatic still means Roblox's old built-in voice today)
	  VoiceChatService.EnableDefaultVoice         -> true     (Roblox keeps building each player's voice device and emitter)
	  VoiceChatService.DefaultDistanceAttenuation -> Legacy   (today's 7-80 stud fade for Roblox's own emitters)
	  ReplicatedStorage.Remotes.VoiceRequest         a RemoteEvent, created if missing (Shared.Net lists it)
	It only reads SoundService.DefaultListenerLocation (leave it at Default or Camera) and AcousticSimulationEnabled
	(leave it off until its cost is measured on a phone).
	Undo: Ctrl+Z right away (one history step), or studio/RevertVoiceSettings.lua at any later time.
]]
local APPLY_TO_LIVE_PLACE = false -- true only for the live publish that also has Config.Voice.Enabled = true
local LIVE_PLACE_ID = 120572716460286

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local VoiceChatService = game:GetService("VoiceChatService")

local lines = {}

local function read(instance: Instance, property: string): string
	local ok, value = pcall(function()
		return (instance :: any)[property]
	end)
	return if ok then tostring(value) else "(can't read: " .. tostring(value) .. ")"
end

-- Config.Voice.Enabled as this place has it (a fresh copy of the module, so an edit made a moment ago counts)
local function voiceEnabledHere(): boolean?
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("Config")
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local ok, config = pcall(function()
		return require(module:Clone())
	end)
	if not ok or type(config) ~= "table" then
		return nil
	end
	return type(config.Voice) == "table" and config.Voice.Enabled == true
end

if game.PlaceId == LIVE_PLACE_ID then
	local enabledHere = voiceEnabledHere()
	if not APPLY_TO_LIVE_PLACE or enabledHere ~= true then
		warn("[ApplyVoiceSettings] This is the LIVE place. Nothing was changed.\n"
			.. "  UseAudioApi changes voice for every player on the next publish, so it goes live only together with the\n"
			.. "  tested voice build: set Config.Voice.Enabled = true (now: " .. tostring(enabledHere) .. ") and\n"
			.. "  APPLY_TO_LIVE_PLACE = true at the top of this script, then run it again (VoiceMode.md, section 8).")
		return
	end
end

local function set(instance: Instance, property: string, value: any)
	local before = read(instance, property)
	local ok, err = pcall(function()
		(instance :: any)[property] = value
	end)
	table.insert(lines, string.format("%s.%s: %s -> %s  %s", instance.ClassName, property, before, read(instance, property),
		if ok then "OK" else "FAILED: " .. tostring(err)))
end

local okRecording, recording = pcall(function()
	return ChangeHistoryService:TryBeginRecording("Proximity Voice settings") -- one undo step for everything below
end)
if not okRecording then
	recording = nil
end

table.insert(lines, "place " .. tostring(game.PlaceId) .. (if game.PlaceId == LIVE_PLACE_ID then " (LIVE)" else " (not the live place)"))
set(VoiceChatService, "UseAudioApi", Enum.AudioApiRollout.Enabled)
set(VoiceChatService, "EnableDefaultVoice", true)
set(VoiceChatService, "DefaultDistanceAttenuation", Enum.VoiceChatDistanceAttenuationType.Legacy)

for _, pair in ipairs({
	{ VoiceChatService, "EnableVoiceVolumeControls" },
	{ SoundService, "DefaultListenerLocation" },
	{ SoundService, "AcousticSimulationEnabled" },
}) do
	table.insert(lines, string.format("%s.%s = %s  (read only here)", pair[1].ClassName, pair[2], read(pair[1], pair[2])))
end

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	table.insert(lines, "ReplicatedStorage.Remotes is missing: nothing created (is this the right place?)")
elseif remotes:FindFirstChild("VoiceRequest") then
	table.insert(lines, "ReplicatedStorage.Remotes.VoiceRequest already exists")
else
	local remote = Instance.new("RemoteEvent")
	remote.Name = "VoiceRequest"
	remote.Parent = remotes
	table.insert(lines, "ReplicatedStorage.Remotes.VoiceRequest created")
end

if recording then
	pcall(function()
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end)
end
table.insert(lines, "Keep these 'before' values: studio/RevertVoiceSettings.lua puts them back.")
print("[ApplyVoiceSettings]\n" .. table.concat(lines, "\n"))
