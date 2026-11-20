--[[
	RankService - Level and the ten Level ranks (docs/design/CardMenusAndShop.md 2.7 and 3.8). Numbers: Shared.Progression.

	  Level n -> n + 1 costs LevelBase + LevelStep * n XP; each level pays GoldPerLevel Gold once (per Prestige).
	  Every 10 levels a rank band (Recruit .. Paragon) with its rewards, granted once ever (SeasonService.grant).
	  Level 100: PRESTIGE (Ranks menu) puts you back to level 1 with a star (1 to 10), keeping everything.
	  Levels never go down. The same XP fills the Season Track (SeasonService.addSeasonXP).

	The rank-up moment is never in a round: a band crossed is sent as { t = "rankup" } and the client holds it until
	the player is back in the train; when it has been shown the client says { t = "rankSeen" } and the player's
	RankUpAt attribute is set, so others in the car see a small emblem flash over that player for 2 s.

	Player attributes (for the results board, the emblem over heads in the train and the boards):
	  Level, Prestige, RankName, RankBand, LoadoutSlots (2, 3 from Runner, 4 from Scout), RankUpAt
	An older save (no Progress yet) is seeded once from its RoundsPlayed, Wins and TotalKills (capped at level 30), with
	that Level's Gold counted as already paid and its band rewards granted.

	API: RankService.addXP(player, n, reason), RankService.loadoutSlots(player) -> number,
	     RankService.tagFor(userId) -> { level, prestige, rank }?
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))

local RankService = {}

local SEED_CAP_LEVEL = 30

local Services: any = nil

local function call(serviceName: string, method: string, ...): any
	local service = Services and Services[serviceName]
	local fn = service and service[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(string.format("[RankService] %s.%s failed: %s", serviceName, method, tostring(result)))
		return nil
	end
	return result
end

local function season(): any
	return Services and Services.SeasonService
end

local function slotsFor(band: number): number
	return 2 + (if band >= 2 then 1 else 0) + (if band >= 3 then 1 else 0)
end

local function mirror(player: Player, p: { [string]: any })
	if player.Parent ~= Players then
		return
	end
	local level = Progression.levelOf(p.XP)
	local band = Progression.bandOf(level)
	player:SetAttribute("Level", level)
	player:SetAttribute("Prestige", p.Prestige)
	player:SetAttribute("RankName", Progression.Ranks[band].name)
	player:SetAttribute("RankBand", band)
	player:SetAttribute("LoadoutSlots", slotsFor(math.max(p.Band, band)))
end

function RankService.loadoutSlots(player: Player): number
	local S = season()
	local p = S and S.progress(player)
	if not p then
		return 2
	end
	return slotsFor(math.max(p.Band, Progression.bandOf(Progression.levelOf(p.XP))))
end

function RankService.tagFor(userId: number): { [string]: any }?
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end
	local level = player:GetAttribute("Level")
	if type(level) ~= "number" then
		return nil
	end
	return { level = level, prestige = player:GetAttribute("Prestige") or 0, rank = player:GetAttribute("RankName") }
end

-- Pays the levels and bands the XP now reaches. Returns the new bands (for the moment) and the level Gold paid.
local function settle(player: Player): ({ number }, number)
	local S = season()
	local R = Progression.config().Ranks
	local newBands = {}
	local goldPaid = 0
	local p = S and S.progress(player)
	if not p then
		return newBands, 0
	end
	local level = Progression.levelOf(p.XP)
	local band = Progression.bandOf(level)
	local fromLevel = math.max(1, p.LevelPaid)
	local fromBand = math.max(1, p.Band)
	if level <= fromLevel and band <= fromBand then
		if p.LevelPaid < 1 or p.Band < 1 then
			S.edit(player, function(q)
				q.LevelPaid = math.max(q.LevelPaid, 1)
				q.Band = math.max(q.Band, 1)
				q.BandShown = math.max(q.BandShown, 1)
			end)
		end
		return newBands, 0
	end
	local ok = S.edit(player, function(q)
		q.LevelPaid = math.max(q.LevelPaid, level)
		q.Band = math.max(q.Band, band)
		q.BandShown = math.max(q.BandShown, 1)
	end)
	if not ok then
		return newBands, 0
	end
	if level > fromLevel then
		goldPaid = (level - fromLevel) * R.GoldPerLevel
		S.grant(player, { k = "gold", n = goldPaid })
	end
	for b = fromBand + 1, band do
		table.insert(newBands, b)
		for _, r in ipairs(Progression.Ranks[b].rewards) do
			S.grant(player, r)
		end
	end
	return newBands, goldPaid
end

local function announce(player: Player, before: number, newBands: { number }, goldPaid: number)
	local S = season()
	local p = S and S.progress(player)
	if not p then
		return
	end
	local level = Progression.levelOf(p.XP)
	if #newBands > 0 then
		local band = newBands[#newBands]
		local rewards = {}
		for _, b in ipairs(newBands) do
			for _, r in ipairs(Progression.Ranks[b].rewards) do
				table.insert(rewards, r)
			end
		end
		S.send(player, { t = "rankup", band = band, level = level, prestige = p.Prestige, rewards = rewards, gold = goldPaid })
	elseif level > before then
		S.send(player, { t = "levelup", level = level, gold = goldPaid })
	end
	call("LeaderboardService", "recordLevel", player, p.Prestige, level)
end

function RankService.addXP(player: Player, n: number, reason: string?)
	local S = season()
	if not S or n <= 0 then
		return
	end
	local p = S.progress(player)
	if not p then
		return
	end
	local before = Progression.levelOf(p.XP)
	local ok = S.edit(player, function(q)
		q.XP += math.floor(n)
	end)
	if not ok then
		return
	end
	S.addSeasonXP(player, n)
	local newBands, gold = settle(player)
	announce(player, before, newBands, gold)
	local q = S.progress(player)
	if q then
		mirror(player, q)
	end
	call("DataService", "saveSoon", player)
end

-- An older save: its past rounds become Level XP once (no Gold for those levels; band rewards granted)
local function seed(player: Player)
	local S = season()
	local p = S and S.progress(player)
	if not p or p.Seeded then
		return
	end
	local rounds = tonumber(call("DataService", "get", player, "RoundsPlayed")) or 0
	local wins = tonumber(call("DataService", "get", player, "Wins")) or 0
	local kills = tonumber(call("DataService", "get", player, "TotalKills")) or 0
	local xp = math.min(rounds * 120 + wins * 100 + kills * 20, Progression.totalFor(SEED_CAP_LEVEL))
	local seededLevel = 1
	S.edit(player, function(q)
		q.Seeded = true
		if q.XP == 0 and xp > 0 then
			q.XP = xp
			seededLevel = Progression.levelOf(xp)
			q.LevelPaid = math.max(q.LevelPaid, seededLevel) -- no Gold for levels from before ranks existed
		end
	end)
	if seededLevel > 1 then
		local newBands = settle(player)
		if #newBands > 0 then
			announce(player, 1, newBands, 0)
		end
	end
end

local function onPrestige(player: Player)
	local S = season()
	local R = Progression.config().Ranks
	local p = S and S.progress(player)
	if not p then
		return
	end
	if Progression.levelOf(p.XP) < R.MaxLevel or p.Prestige >= R.MaxPrestige then
		return
	end
	S.edit(player, function(q)
		q.Prestige += 1
		q.XP = 0
		q.LevelPaid = 1
	end)
	local q = S.progress(player)
	if q then
		mirror(player, q)
		call("LeaderboardService", "recordLevel", player, q.Prestige, 1)
	end
	S.send(player, { t = "claimed", what = "prestige", prestige = q and q.Prestige })
	call("DataService", "saveSoon", player)
	S.push(player)
end

local function onRankSeen(player: Player)
	local S = season()
	local p = S and S.progress(player)
	if not p then
		return
	end
	if p.BandShown < p.Band then
		S.edit(player, function(q)
			q.BandShown = q.Band
		end)
		player:SetAttribute("RankUpAt", workspace:GetServerTimeNow())
	end
end

local function onJoined(player: Player)
	local S = season()
	if not S then
		return
	end
	for _ = 1, 120 do
		if player.Parent ~= Players then
			return
		end
		if call("DataService", "isLoaded", player) == true then
			break
		end
		task.wait(1)
	end
	seed(player)
	settle(player)
	local p = S.progress(player)
	if not p then
		return
	end
	mirror(player, p)
	-- a band crossed but never shown (they left first): shown when they are next in the train
	if p.BandShown >= 1 and p.BandShown < p.Band then
		local rewards = {}
		for b = p.BandShown + 1, p.Band do
			for _, r in ipairs(Progression.Ranks[b].rewards) do
				table.insert(rewards, r)
			end
		end
		S.send(player, { t = "rankup", band = p.Band, level = Progression.levelOf(p.XP), prestige = p.Prestige, rewards = rewards })
	end
	call("LeaderboardService", "recordLevel", player, p.Prestige, Progression.levelOf(p.XP))
end

function RankService.Init(services)
	Services = services
end

function RankService.Start()
	local S = season()
	if not S then
		warn("[RankService] SeasonService missing: no ranks")
		return
	end
	S.on("prestige", onPrestige)
	S.on("rankSeen", onRankSeen)
	Players.PlayerAdded:Connect(onJoined)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onJoined, player)
	end
end

return RankService
