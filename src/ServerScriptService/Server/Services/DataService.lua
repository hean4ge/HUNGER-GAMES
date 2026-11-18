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
	a failed load or a quick server hop never wipes or double-counts them. Settings are written only once the profile
	has loaded, and only the keys this session changed, merged into the stored table: a change made while the profile
	was still loading keeps every other stored key, and a session whose load failed never writes Settings at all
	(SettingsController sends only the keys the player changed). Every call is pcall-wrapped with retries.
	A profile that could not be loaded at join is asked for again every LOAD_RETRY_INTERVAL seconds while the player
	stays. One store call runs per session at a time (session.saving): a save never starts beside another one, so the
	same deltas are never written twice. A player whose leave save failed keeps their unsaved stats on this server
	(orphans): the autosave loop and the shutdown save try again, and they get them back if they rejoin this server.
	In Studio without API access (or an unpublished place) it logs once and keeps session-only defaults.

	Gold and the Armoury (Weapons_v2 sections 4 and 5; CurrencyService and RewardsService use them):
	  Gold is a fourth stat beside Wins, TotalKills and RoundsPlayed: written as a delta like them (earning adds,
	  spending subtracts), mirrored to the player attribute Gold, never below 0 in the store.
	  Econ (stored key "Econ", Version 2) = {
	    Armoury = { [weaponId] = stars 1..5 },   the best star of each weapon won or bought; merged by the higher star
	    Pity = { box4, box5, wheel4 },           draws since the last 4-star-or-better box / 5-star box / 4-star spin
	    Daily = { day = "YYYY-MM-DD" (UTC), free, paid (spins used), roundGold, firstRound, firstWin },
	    LastKit = string, Bring = string,        the kit and the owned weapon picked for the next round ("" = none)
	    Draws = number,                          wheel spins and boxes opened, ever
	  }
	  Econ is written like Settings: only once the profile has loaded, and whole except the Armoury, which is merged
	  by the higher star with what is stored. A save from before Gold existed (no Gold, no Econ, Version 1) loads as
	  Gold 0 and an empty Econ, and is written back as Version 2.
	  DataService.isLoaded(player) -> boolean     the profile answered (or DataStores are off): Gold can be spent
	  DataService.spendGold(player, n) -> boolean only when loaded and the balance covers n
	  DataService.getEcon(player) -> Econ?        a deep copy
	  DataService.updateEcon(player, fn)          fn(econ) edits the live table; it is sanitized and marked to save
	  DataService.saveSoon(player)                a save within a few seconds (after a purchase)
	  DataService.saveNow(player) -> boolean      a save now (yields); true once everything pending is written
	  Studio only, for tests (DataStores are off in Studio): DataService.useTestStore(store) swaps in a stand-in with
	  GetAsync / UpdateAsync; DataService.testRejoin(player) saves and drops the player's session, then loads it again
	  from the store, as a leave and a rejoin would.
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
local LOAD_RETRY_INTERVAL = 30 -- seconds between later tries for a profile that did not load at join
local SAVE_ATTEMPTS = 3
local SAVE_WAIT = 90 -- seconds a save waits for the store call already running for that session before it gives up
local ORPHAN_TRIES = 10 -- autosave rounds a departed player's unsaved stats are retried for (20 minutes)
local STATS = { "Wins", "TotalKills", "RoundsPlayed", "Gold" }
local IS_STAT = { Wins = true, TotalKills = true, RoundsPlayed = true, Gold = true }
local ECON_VERSION = 2
local SAVE_SOON_DELAY = 4
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
	shaders = { 0, 2 }, -- the lighting look: 0 Off, 1 Auto, 2 Full
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
local orphans = {} -- [userId] = { session, player, tries }: left with changes the leave save could not write

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

-- Econ (see the header): a clean copy of whatever is stored, with every field present
local function sanitizeEcon(raw: any)
	local src = if type(raw) == "table" then raw else {}
	local out = {
		Armoury = {},
		Pity = { box4 = 0, box5 = 0, wheel4 = 0 },
		Daily = { day = "", free = 0, paid = 0, roundGold = 0, firstRound = false, firstWin = false },
		LastKit = "",
		Bring = "",
		Draws = 0,
	}
	local function count(v: any, max: number): number
		return if Util.isFiniteNumber(v) then math.clamp(math.floor(v), 0, max) else 0
	end
	if type(src.Armoury) == "table" then
		for id, stars in pairs(src.Armoury) do
			if type(id) == "string" and #id <= 32 and Util.isFiniteNumber(stars) then
				local s = math.clamp(math.floor(stars), 0, 5)
				if s > 0 then
					out.Armoury[id] = s
				end
			end
		end
	end
	if type(src.Pity) == "table" then
		for _, k in ipairs({ "box4", "box5", "wheel4" }) do
			out.Pity[k] = count(src.Pity[k], 1000)
		end
	end
	if type(src.Daily) == "table" then
		local d = src.Daily
		out.Daily.day = if type(d.day) == "string" and #d.day <= 10 then d.day else ""
		out.Daily.free = count(d.free, 100)
		out.Daily.paid = count(d.paid, 1000)
		out.Daily.roundGold = count(d.roundGold, 1e7)
		out.Daily.firstRound = d.firstRound == true
		out.Daily.firstWin = d.firstWin == true
	end
	if type(src.LastKit) == "string" and #src.LastKit <= 24 then
		out.LastKit = src.LastKit
	end
	if type(src.Bring) == "string" and #src.Bring <= 32 then
		out.Bring = src.Bring
	end
	out.Draws = count(src.Draws, 1e9)
	return out
end

local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = deepCopy(v)
	end
	return c
end

local function newSession(userId: number)
	return {
		userId = userId,
		base = { Wins = 0, TotalKills = 0, RoundsPlayed = 0, Gold = 0 }, -- last values known to be stored
		pending = { Wins = 0, TotalKills = 0, RoundsPlayed = 0, Gold = 0 }, -- not yet saved
		econ = sanitizeEcon(nil),
		econVersion = 0,
		savedEconVersion = 0,
		saveSoon = false,
		settings = {},
		changed = {}, -- [key] = true: settings this session changed (only these are written, merged into the stored ones)
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
	return session.loaded and (session.settingsVersion ~= session.savedSettingsVersion
		or session.econVersion ~= session.savedEconVersion)
end

local function applySettings(player: Player, session, values: { [string]: number })
	local changed = false
	for key, value in pairs(values) do
		if session.settings[key] ~= value then
			session.settings[key] = value
			session.changed[key] = true
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

-- One GetAsync for a session whose profile has not loaded yet. Returns true once it has; false and the error
-- otherwise ("busy": another store call is running for this session; the caller checks the session is still current).
local function fetchProfile(player: Player, session): (boolean, any)
	if session.saving then
		return false, "busy"
	end
	session.saving = true -- a save waits for this answer: a read that crossed a write would bring back the older totals
	waitForBudget(Enum.DataStoreRequestType.GetAsync, 5)
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(keyFor(session.userId))
	end)
	session.saving = false
	if sessions[player] ~= session then
		return false, "left"
	end
	if not ok then
		return false, result
	end
	if type(result) == "table" then
		for _, stat in ipairs(STATS) do
			session.base[stat] = math.max(0, math.floor(tonumber(result[stat]) or 0))
		end
		-- stored settings, overridden only by the keys the player changed while we were loading
		local merged = sanitizeSettings(result.Settings)
		for k in pairs(session.changed) do
			merged[k] = session.settings[k]
		end
		session.settings = merged
		-- Econ: a save from before Gold (Version 1, no Econ) loads as an empty one. Anything this session already holds
		-- (nothing can be won before the load, but keep the higher star to be safe) is merged in.
		local econ = sanitizeEcon(result.Econ)
		if session.carryEcon then
			-- back on the server they left before their Econ was saved: what they had here is newer than the store
			local stored = econ
			econ = session.carryEcon
			session.carryEcon = nil
			for id, stars in pairs(stored.Armoury) do
				if stars > (econ.Armoury[id] or 0) then
					econ.Armoury[id] = stars
				end
			end
			session.econVersion += 1
		end
		for id, stars in pairs(session.econ.Armoury) do
			if stars > (econ.Armoury[id] or 0) then
				econ.Armoury[id] = stars
			end
		end
		session.econ = econ
	end
	session.loaded = true
	return true, nil
end

local function loadPlayer(player: Player)
	local session = newSession(player.UserId)
	sessions[player] = session
	-- back on the server they left with unsaved stats: this session carries them on (unless that save is running now)
	local orphan = orphans[session.userId]
	if orphan and not orphan.session.saving then
		orphans[session.userId] = nil
		for _, stat in ipairs(STATS) do
			session.pending[stat] += orphan.session.pending[stat]
			orphan.session.pending[stat] = 0
		end
		local o = orphan.session
		if o.loaded and o.econVersion ~= o.savedEconVersion then
			session.carryEcon = deepCopy(o.econ)
			o.savedEconVersion = o.econVersion
		end
	end
	mirror(player, session, false)
	if store and available then
		for attempt = 1, LOAD_ATTEMPTS do
			local ok, result = fetchProfile(player, session)
			if sessions[player] ~= session then
				return
			end
			if ok then
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
			warn("[DataService] Couldn't load " .. player.Name .. "'s stats yet; new progress is still saved safely as deltas,"
				.. " and the load is tried again every " .. LOAD_RETRY_INTERVAL .. " s.")
		end
	end
	if sessions[player] ~= session then
		return
	end
	if not available then
		session.loaded = true -- session-only defaults
	end
	mirror(player, session, true)
	-- a profile that did not load is asked for again while the player stays: until it answers their Wins and
	-- RoundsPlayed read 0 (new-player help is on) and their settings changes are not written
	while store and available and not session.loaded do
		task.wait(LOAD_RETRY_INTERVAL)
		if sessions[player] ~= session or not available then
			return
		end
		local ok = fetchProfile(player, session)
		if sessions[player] ~= session then
			return
		end
		if ok then
			mirror(player, session, true)
			print("[DataService] Loaded " .. player.Name .. "'s stats on a later try.")
		end
	end
end

local function savePlayer(player: Player, session): boolean
	if not store or not available then
		return false
	end
	-- one store call per session at a time. A write still in its retries has these same deltas in hand: starting a
	-- second one beside it would add them twice, so this one waits, and gives up (false) if that takes too long.
	local waited = 0
	while session.saving do
		if waited >= SAVE_WAIT then
			return false
		end
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
	-- Settings only once the profile has loaded (a failed load must not overwrite them), and only the changed keys
	local settingsDirty = session.loaded and settingsVersion ~= session.savedSettingsVersion
	local changedSettings = {}
	for k in pairs(session.changed) do
		changedSettings[k] = session.settings[k]
	end
	-- Econ only once loaded (a failed load must not overwrite the Armoury), as a snapshot taken now
	local econVersion = session.econVersion
	local econDirty = session.loaded and econVersion ~= session.savedEconVersion
	local econSnapshot = if econDirty then deepCopy(session.econ) else nil
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
					-- merged into what is stored: keys this session never changed keep their stored values
					local stored = if type(data.Settings) == "table" then data.Settings else {}
					for k, v in pairs(changedSettings) do
						stored[k] = v
					end
					data.Settings = stored
				elseif type(data.Settings) ~= "table" then
					data.Settings = {}
				end
				if econSnapshot then
					-- whole, except the Armoury: the higher star of what is stored and what this session has wins
					local stored = sanitizeEcon(data.Econ)
					local out = deepCopy(econSnapshot)
					for id, stars in pairs(stored.Armoury) do
						if stars > (out.Armoury[id] or 0) then
							out.Armoury[id] = stars
						end
					end
					data.Econ = out
				elseif type(data.Econ) ~= "table" then
					data.Econ = sanitizeEcon(nil)
				end
				data.Version = ECON_VERSION
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
			if econDirty then
				session.savedEconVersion = math.max(session.savedEconVersion, econVersion)
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

-- An orphan that lost its place in the list while its retry was writing (the player came back and left again with a
-- second failed save): once that write has answered, whatever it left unsaved joins the entry now in the list, or goes
-- back in the list itself. Without this a failed retry's stats were out of reach of every later save.
local function keepReplaced(userId: number, earlier)
	local waited = 0
	while earlier.session.saving and waited < SAVE_WAIT * 2 do
		task.wait(0.25)
		waited += 0.25
	end
	local left = earlier.session.pending
	local any = false
	for _, stat in ipairs(STATS) do
		if left[stat] ~= 0 then
			any = true
		end
	end
	if not any then
		return -- that write went through
	end
	local current = orphans[userId]
	if current == earlier then
		return
	end
	if current == nil then
		orphans[userId] = earlier -- nothing took its place for good (they rejoined, or the newer entry was saved)
	elseif not earlier.session.saving then
		for _, stat in ipairs(STATS) do
			current.session.pending[stat] += left[stat]
			left[stat] = 0
		end
	else
		warn(string.format("[DataService] Could not keep user %d's earlier unsaved stats (Wins +%d, TotalKills +%d, RoundsPlayed +%d).",
			userId, left.Wins, left.TotalKills, left.RoundsPlayed))
	end
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

-- Gold and Econ (CurrencyService, RewardsService) ---------------------------------------------------------------------

function DataService.isLoaded(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.loaded == true
end

-- Spends n Gold if the profile has loaded and the balance covers it (a balance not yet known is never spent).
function DataService.spendGold(player: Player, n: number): boolean
	local session = sessions[player]
	if not session or not session.loaded or not Util.isFiniteNumber(n) then
		return false
	end
	local amount = math.floor(n)
	if amount < 0 then
		return false
	end
	local balance = session.base.Gold + session.pending.Gold
	if balance < amount then
		return false
	end
	session.pending.Gold -= amount
	mirror(player, session, false)
	return true
end

function DataService.getEcon(player: Player): { [string]: any }?
	local session = sessions[player]
	if not session then
		return nil
	end
	return deepCopy(session.econ)
end

-- fn(econ) edits the session's Econ in place; the result is sanitized and saved with the next write.
-- Refused (false) until the profile has loaded, so a failed load never writes over the stored Armoury.
function DataService.updateEcon(player: Player, fn: (any) -> ()): boolean
	local session = sessions[player]
	if not session or not session.loaded then
		return false
	end
	local working = deepCopy(session.econ)
	local ok, err = pcall(fn, working)
	if not ok then
		warn("[DataService] updateEcon failed: " .. tostring(err))
		return false
	end
	session.econ = sanitizeEcon(working)
	session.econVersion += 1
	return true
end

-- A save in a few seconds (after a purchase or a prize), coalesced per player.
function DataService.saveSoon(player: Player)
	local session = sessions[player]
	if not session or session.saveSoon or not store or not available then
		return
	end
	session.saveSoon = true
	task.delay(SAVE_SOON_DELAY, function()
		session.saveSoon = false
		if sessions[player] == session then
			savePlayer(player, session)
		end
	end)
end

-- A save now (yields); true once everything pending is written. For a Robux receipt before it is acknowledged.
function DataService.saveNow(player: Player): boolean
	local session = sessions[player]
	if not session or not store or not available then
		return false
	end
	return savePlayer(player, session)
end

-- Studio only: a stand-in store (GetAsync / UpdateAsync), since DataStores are off in Studio.
function DataService.useTestStore(testStore: any): boolean
	if not Config.IsStudio or type(testStore) ~= "table" then
		return false
	end
	store = testStore
	available = true
	return true
end

-- Studio only: save and drop the player's session, then load it again from the store (a leave and a rejoin).
function DataService.testRejoin(player: Player): boolean
	if not Config.IsStudio then
		return false
	end
	local session = sessions[player]
	local saved = if session then savePlayer(player, session) else true
	sessions[player] = nil
	loadPlayer(player)
	return saved
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
		local saved = savePlayer(player, session)
		if sessions[player] == session then
			sessions[player] = nil
		end
		-- the leave save failed (or another write was still running): keep what is unsaved and try again later
		if not saved and store and available and hasChanges(session) then
			local earlier = orphans[session.userId]
			if earlier and earlier.session ~= session and not earlier.session.saving then
				for _, stat in ipairs(STATS) do
					session.pending[stat] += earlier.session.pending[stat]
					earlier.session.pending[stat] = 0
				end
			elseif earlier and earlier.session ~= session then
				-- its retry is writing right now and this entry is about to take its place in the list
				task.spawn(keepReplaced, session.userId, earlier)
			end
			orphans[session.userId] = { session = session, player = player, tries = 0 }
			warn(string.format(
				"[DataService] %s left before their stats were saved (Wins +%d, TotalKills +%d, RoundsPlayed +%d); kept and tried again.",
				player.Name, session.pending.Wins, session.pending.TotalKills, session.pending.RoundsPlayed))
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
		for _, orphan in pairs(orphans) do
			running += 1
			task.spawn(function()
				pcall(savePlayer, orphan.player, orphan.session)
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
			-- players who left with changes their leave save could not write
			local left = {}
			for userId, orphan in pairs(orphans) do
				table.insert(left, { userId = userId, orphan = orphan })
			end
			for _, entry in ipairs(left) do
				local userId, orphan = entry.userId, entry.orphan
				if orphans[userId] == orphan then
					if not hasChanges(orphan.session) then
						orphans[userId] = nil
					else
						orphan.tries += 1
						task.spawn(function()
							local saved = savePlayer(orphan.player, orphan.session)
							if orphans[userId] == orphan and (saved or orphan.tries >= ORPHAN_TRIES) then
								orphans[userId] = nil
								if not saved then
									local pending = orphan.session.pending
									warn(string.format(
										"[DataService] Gave up saving user %d's stats after they left (Wins +%d, TotalKills +%d, RoundsPlayed +%d).",
										userId, pending.Wins, pending.TotalKills, pending.RoundsPlayed))
								end
							end
						end)
						task.wait(0.3)
					end
				end
			end
		end
	end
end

return DataService
