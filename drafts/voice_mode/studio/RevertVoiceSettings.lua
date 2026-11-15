--[[
	RevertVoiceSettings - paste into Roblox Studio's command bar (Edit mode) to put Roblox's voice back the way it was
	before studio/ApplyVoiceSettings.lua, then publish. Use it if the voice build has to come out after it went live:
	set Config.Voice.Enabled = false in the same publish (VoiceMode.md, section 8, "Taking it out").

	Set the three values below to the "before" values ApplyVoiceSettings printed. The defaults are Roblox's own defaults,
	which is what an untouched place has: UseAudioApi Automatic (today the same as Disabled: Roblox's old built-in voice),
	EnableDefaultVoice true, DefaultDistanceAttenuation Inverse.
	The VoiceRequest RemoteEvent stays (harmless without VoiceService).
]]
local RESTORE_USE_AUDIO_API = Enum.AudioApiRollout.Automatic
local RESTORE_DEFAULT_VOICE = true
local RESTORE_ATTENUATION = Enum.VoiceChatDistanceAttenuationType.Inverse

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local VoiceChatService = game:GetService("VoiceChatService")

local lines = { "place " .. tostring(game.PlaceId) }

local function read(property: string): string
	local ok, value = pcall(function()
		return (VoiceChatService :: any)[property]
	end)
	return if ok then tostring(value) else "(can't read: " .. tostring(value) .. ")"
end

local function set(property: string, value: any)
	local before = read(property)
	local ok, err = pcall(function()
		(VoiceChatService :: any)[property] = value
	end)
	table.insert(lines, string.format("VoiceChatService.%s: %s -> %s  %s", property, before, read(property),
		if ok then "OK" else "FAILED: " .. tostring(err)))
end

local okRecording, recording = pcall(function()
	return ChangeHistoryService:TryBeginRecording("Revert Proximity Voice settings")
end)
if not okRecording then
	recording = nil
end
set("UseAudioApi", RESTORE_USE_AUDIO_API)
set("EnableDefaultVoice", RESTORE_DEFAULT_VOICE)
set("DefaultDistanceAttenuation", RESTORE_ATTENUATION)
if recording then
	pcall(function()
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end)
end
print("[RevertVoiceSettings]\n" .. table.concat(lines, "\n") .. "\nNow publish (with Config.Voice.Enabled = false).")
