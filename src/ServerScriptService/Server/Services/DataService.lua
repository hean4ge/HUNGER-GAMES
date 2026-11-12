--[[
	DataService - persistent player stats and settings in the DataStore "PlayerStats_v1" (key "Player_<UserId>").
	Stored keys: Wins, TotalKills, RoundsPlayed (numbers) and Settings ({ [string]: number }).
	Mirrored to player attributes: Wins, TotalKills, RoundsPlayed, SettingsJson (HttpService:JSONEncode of Settings;
	set once the profile has loaded).

	API:
	  DataService.increment(player, key, n?)      key = "Wins" | "TotalKills" | "RoundsPlayed" (n defaults to 1)
	  DataService.get(player, key) -> any         a number for stats, a copy of the settings table for "Settings"
	  DataService.setSettings(player, settings)   merges known keys (clamped), same rules as the SaveSettings remote
	Remote: SaveSettings({ [string]: number }) - only fov, sensitivity, headBob, cameraShake, musicVolume, sfxVolume,
	        ambienceVolume, guidance, hintsSeen, the sprint / crouch modes, padLook, touchLook; values clamped; rate-limited (bursts are coalesced, so the last change always lands).

	Saving: autosave every 120 s, on leave and in game:BindToClose. Stats are written as deltas through UpdateAsync, so
	a failed load or a quick server hop never wipes or double-counts them. Every call is pcall-wrapped with retries.
	In Studio without API access (or an unpublished place) it logs once and keeps session-only defaults.
]]
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local STORE_NAME = "PlayerStats_v1"
local AUTOSAVE_INTERVAL = 120
local LOAD_ATTEMPTS = 4
local SAVE_ATTEMPTS = 3
local STATS = { "Wins", "TotalKills", "RoundsPlayed" }
local IS_STAT = { Wins = true, TotalKills = true, RoundsPlayed = true }
local SETTING_LIMITS = {
	fov = { 50, 120 },
	sensitivity = { 0.05, 5 },
	headBob = { 0, 1 },
	cameraShake = { 0, 1 },
	musicVolume = { 0, 1 },
	sfxVolume = { 0, 1 },
	ambienceVolume = { 0, 1 },
	-- PlayabilityPlan Q1 / QW2 / QW13 (SettingsController)
	guidance = { 0, 2 }, -- 0 Off, 1 Auto, 2 Always
	hintsSeen = { 0, 2 ^ 30 - 1 }, -- action-hint use counters, 3 bits per action (Shared.ActionHints)
	sprintMode = { 0, 2 }, -- 0 Hold, 1 Toggle, 2 Auto (keyboard; Pad = gamepad, Touch = touch)
	sprintModePad = { 0, 2 },
	sprintModeTouch = { 0, 2 },
	crouchMode = { 0, 1 }, -- 0 Hold, 1 Toggle
	crouchModePad = { 0, 1 },
	crouchModeTouch = { 0, 1 },
	padLook = { 0.5, 2 }, -- controller look speed (x)
	touchLook = { 0.5, 2 }, -- touch look speed (x)
}

local DataService = {}

local store: DataStore? = nil
local available = true
local unavailableLogged = false
local sessions = {} -- [Player] = session (see newSession)

-- Helpers ----------------------------------------------------------------------------------------------------------

local function markUnavailable(reason: any)
	available = false
	if not unavailableLogged then
		unavailableLogged = true
		warn("[DataService] DataStores are unavailable (" .. tostring(reason) .. "). Stats and settings won't persist this session."
			.. " In Studio: Game Settings > Security > Enable Studio Access to API Services.")
	end
end

local function looksUnavailable(err: any): boolean
	local message = string.lower(tostring(err))
	for _, needle in ipairs({ "studio", "api services", "403", "publish", "not allowed", "forbidden" }) do
		if string.find(message, needle, 1, true) then
			return true
		end
	end
	return false
end

local function waitForBudget(requestType: Enum.DataStoreRequestType, timeout: number)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, requestType)
		if not ok or budget > 0 then
			return
		end
		task.wait(0.5)
	end
end

local function keyFor(userId: number): string
	return "Player_" .. tostring(userId)
end

local function newSession(userId: number)
	return {
		userId = userId,
		base = { Wins = 0, TotalKills = 0, RoundsPlayed = 0 }, -- last values known to be stored
		pending = { Wins = 0, TotalKills = 0, RoundsPlayed = 0 }, -- not yet saved
		settings = {},
		settingsVersion = 0,
		savedSettingsVersion = 0,
		loaded = false,
		saving = false,
		queued = nil,
		flushScheduled = false,
	}
end

local function sanitizeSettings(raw: any): { [string]: number }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, limits in pairs(SETTING_LIMITS) do
		local value = raw[key]
		if Util.isFiniteNumber(value) then
			out[key] = math.clamp(value, limits[1], limits[2])
		end
	end
	return out
end

local function encodeSettings(settings: { [string]: number }): string
	if next(settings) == nil then
		return "{}"
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, settings)
	return if ok then json else "{}"
end

local function mirror(player: Player, session, includeSettings: boolean)
	if player.Parent ~= Players then
		return
	end
	for _, key in ipairs(STATS) do
		player:SetAttribute(key, (session.base[key] or 0) + (session.pending[key] or 0))
	end
	if includeSettings then
		player:SetAttribute("SettingsJson", encodeSettings(session.settings))
	end
end

local function hasChanges(session): boolean
	for _, key in ipairs(STATS) do
		if session.pending[key] ~= 0 then
			return true
		end
	end
	return session.settingsVersion ~= session.savedSettingsVersion
end

local function applySettings(player: Player, session, values: { [string]: number })
	local changed = false
	for key, value in pairs(values) do
		if session.settings[key] ~= value then
			session.settings[key] = value
			changed = true
		end
	end
	if changed then
		session.settingsVersion += 1
		if session.loaded or not available then
			mirror(player, session, true)
		end
	end
end

-- Load / save ------------------------------------------------------------------------------------------------------

local function loadPlayer(player: Player)
	local session = newSession(player.UserId)
	sessions[player] = session
	mirror(player, session, false)
	if store and available then
		local key = keyFor(session.userId)
		for attempt = 1, LOAD_ATTEMPTS do
			waitForBudget(Enum.DataStoreRequestType.GetAsync, 5)
			local ok, result = pcall(function()
				return (store :: DataStore):GetAsync(key)
			end)
			if sessions[player] ~= session then
				return
			end
			if ok then
				if type(result) == "table" then
					for _, stat in ipairs(STATS) do
						session.base[stat] = math.max(0, math.floor(tonumber(result[stat]) or 0))
					end
					-- stored settings, overridden by anything the player changed while we were loading
					local merged = sanitizeSettings(result.Settings)
					for k, v in pairs(session.settings) do
						merged[k] = v
					end
					session.settings = merged
				end
				session.loaded = true
				break
			end
			if Config.IsStudio and looksUnavailable(result) then
				markUnavailable(result)
				break
			end
			warn(string.format("[DataService] Load attempt %d for %s failed: %s", attempt, player.Name, tostring(result)))
			if attempt < LOAD_ATTEMPTS then
				task.wait(attempt * 2)
			end
		end
		if not session.loaded and available then
			warn("[DataService] Couldn't load " .. player.Name .. "'s stats; new progress is still saved safely as deltas.")
		end
	end
	if sessions[player] ~= session then
		return
	end
	if not available then
		session.loaded = true -- session-only defaults
	end
	mirror(player, session, true)
end

local function savePlayer(player: Player, session): boolean
	if not store or not available then
		return false
	end
	local waited = 0
	while session.saving and waited < 30 do
		task.wait(0.25)
		waited += 0.25
	end
	if not hasChanges(session) then
		return true
	end
	session.saving = true
	local deltas = {}
	for _, stat in ipairs(STATS) do
		deltas[stat] = session.pending[stat]
	end
	local settingsVersion = session.settingsVersion
	local settingsDirty = settingsVersion ~= session.savedSettingsVersion
	local settingsCopy = table.clone(session.settings)
	local key = keyFor(session.userId)
	local success = false
	for attempt = 1, SAVE_ATTEMPTS do
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync, 5)
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(old)
				local data = if type(old) == "table" then old else {}
				for _, stat in ipairs(STATS) do
					data[stat] = math.max(0, math.floor((tonumber(data[stat]) or 0) + deltas[stat]))
				end
				if settingsDirty then
					data.Settings = settingsCopy
				elseif type(data.Settings) ~= "table" then
					data.Settings = {}
				end
				data.Version = 1
				return data
			end)
		end)
		if ok then
			success = true
			for _, stat in ipairs(STATS) do
				session.pending[stat] -= deltas[stat]
				local stored = if type(result) == "table" then tonumber(result[stat]) else nil
				session.base[stat] = stored or (session.base[stat] + deltas[stat])
			end
			if settingsDirty then
				session.savedSettingsVersion = math.max(session.savedSettingsVersion, settingsVersion)
			end
			break
		end
		if Config.IsStudio and looksUnavailable(result) then
			markUnavailable(result)
			break
		end
		warn(string.format("[DataService] Save attempt %d for %s failed: %s", attempt, player.Name, tostring(result)))
		if attempt < SAVE_ATTEMPTS then
			task.wait(attempt * 2)
		end
	end
	session.saving = false
	mirror(player, session, false)
	return success
end

-- Public API ---------------------------------------------------------------------------------------------------------

function DataService.increment(player: Player, key: string, n: number?)
	if not IS_STAT[key] then
		warn("[DataService] increment: unknown key " .. tostring(key))
		return
	end
	local session = sessions[player]
	if not session then
		return
	end
	local amount = if n == nil then 1 else tonumber(n)
	if not amount or not Util.isFiniteNumber(amount) then
		return
	end
	amount = math.floor(amount + 0.5)
	if amount == 0 then
		return
	end
	session.pending[key] += amount
	mirror(player, session, false)
end

function DataService.get(player: Player, key: string): any
	local session = sessions[player]
	if not session then
		return nil
	end
	if IS_STAT[key] then
		return session.base[key] + session.pending[key]
	end
	if key == "Settings" then
		return table.clone(session.settings)
	end
	return nil
end

function DataService.setSettings(player: Player, settings: { [string]: any })
	local session = sessions[player]
	if not session then
		return
	end
	local values = sanitizeSettings(settings)
	if next(values) ~= nil then
		applySettings(player, session, values)
	end
end

local function onSaveSettings(player: Player, payload: any)
	local session = sessions[player]
	if not session or type(payload) ~= "table" then
		return
	end
	local values = sanitizeSettings(payload) -- reads only the known keys
	if next(values) == nil then
		return
	end
	if Net.rateLimit(player, "SaveSettings", 2, 6) then
		applySettings(player, session, values)
		return
	end
	-- over the limit: keep the latest values and apply them shortly
	local queued = session.queued or {}
	for k, v in pairs(values) do
		queued[k] = v
	end
	session.queued = queued
	if not session.flushScheduled then
		session.flushScheduled = true
		task.delay(1, function()
			session.flushScheduled = false
			local pending = session.queued
			session.queued = nil
			if pending and sessions[player] == session then
				applySettings(player, session, pending)
			end
		end)
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function DataService.Init(_registry)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and result then
		store = result
	else
		markUnavailable(result)
	end
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if not session then
			return
		end
		savePlayer(player, session)
		if sessions[player] == session then
			sessions[player] = nil
		end
	end)
	Net.event("SaveSettings").OnServerEvent:Connect(onSaveSettings)
	game:BindToClose(function()
		if not store or not available then
			return
		end
		local running = 0
		for player, session in pairs(sessions) do
			running += 1
			task.spawn(function()
				pcall(savePlayer, player, session)
				running -= 1
			end)
		end
		local deadline = os.clock() + 25
		while running > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

function DataService.Start()
	for _, player in ipairs(Players:GetPlayers()) do
		if not sessions[player] then
			task.spawn(loadPlayer, player)
		end
	end
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		if store and available then
			local list = {}
			for player, session in pairs(sessions) do
				if player.Parent == Players and hasChanges(session) then
					table.insert(list, { player = player, session = session })
				end
			end
			for _, entry in ipairs(list) do
				if sessions[entry.player] == entry.session then
					task.spawn(savePlayer, entry.player, entry.session)
					task.wait(0.3)
				end
			end
		end
	end
end

return DataService
