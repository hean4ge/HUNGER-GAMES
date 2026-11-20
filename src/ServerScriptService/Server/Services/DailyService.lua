--[[
	DailyService - the 7-day daily reward (docs/design/CardMenusAndShop.md 2.5 and 3.7). Rewards: Progression.DailyRewards.

	  Days run on UTC. One claim per UTC day, from the train only (not while InArena). The next card is the one after
	  the last claimed: a missed day PAUSES the streak, it never resets it. The week repeats after day 7.
	  Day 7 gives a stamp; StampsForTrim stamps give the Regular banner trim (once).
	  Earned, never sold, never from an ad. Saved in Econ.Progress.Daily { last, next, streak, stamps }.

	Remote: SeasonService's Progress remote, { t = "daily" } claims. The state's "daily" part comes from view().
	API: DailyService.view(player, progress) -> { day, claimable, nextIn, streak, stamps, week, trim }
	     DailyService.claim(player) -> rewards?
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Progression"))

local DailyService = {}

local Services: any = nil

local function season(): any
	return Services and Services.SeasonService
end

function DailyService.view(_player: Player, p: { [string]: any }): { [string]: any }
	local today = Progression.utcDay()
	local d = p.Daily
	local cfg = Progression.config().Daily
	return {
		enabled = cfg.Enabled ~= false,
		day = d.next,
		claimable = cfg.Enabled ~= false and d.last ~= today and (d.last == "" or d.last < today),
		claimedToday = d.last == today,
		nextIn = Progression.secondsToNextDay(),
		streak = d.streak,
		stamps = d.stamps,
		week = math.floor(d.streak / 7) + 1,
		trimAt = cfg.StampsForTrim,
		trim = p.Honours["trim:trim_regular"] == true,
	}
end

function DailyService.claim(player: Player): { { [string]: any } }?
	local S = season()
	if not S or Progression.config().Daily.Enabled == false then
		return nil
	end
	if player:GetAttribute("InArena") == true then
		return nil -- the train only
	end
	local p = S.progress(player)
	if not p then
		return nil
	end
	local today = Progression.utcDay()
	local d = p.Daily
	if d.last == today or (d.last ~= "" and d.last > today) then
		return nil
	end
	local index = math.clamp(d.next, 1, 7)
	local rewards = Progression.DailyRewards[index]
	local ok = S.edit(player, function(q)
		q.Daily.last = today
		q.Daily.next = index % 7 + 1
		q.Daily.streak += 1
	end)
	if not ok then
		return nil
	end
	for _, r in ipairs(rewards) do
		S.grant(player, r)
	end
	-- four stamps: the Regular trim (once)
	local after = S.progress(player)
	local cfg = Progression.config().Daily
	if after and after.Daily.stamps >= cfg.StampsForTrim and not after.Honours["trim:trim_regular"] then
		S.grant(player, { k = "trim", id = "trim_regular" })
	end
	return rewards
end

local function onDaily(player: Player, _msg: any)
	local S = season()
	local got = DailyService.claim(player)
	if got then
		S.send(player, { t = "claimed", what = "daily", rewards = got })
		local dataService = Services and Services.DataService
		if dataService then
			dataService.saveSoon(player)
		end
	end
	S.push(player)
end

function DailyService.Init(services)
	Services = services
end

function DailyService.Start()
	local S = season()
	if not S then
		warn("[DailyService] SeasonService missing: no daily reward")
		return
	end
	S.on("daily", onDaily)
	-- a new UTC day while playing: everyone's state again, so the CLAIM card lights up
	while true do
		task.wait(Progression.secondsToNextDay() + 2)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(S.push, player)
		end
	end
end

return DailyService
