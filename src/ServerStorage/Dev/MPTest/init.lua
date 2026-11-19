--[[
	MPTest - a real multiplayer test from Studio: one server and 2 to 4 clients as separate Studio processes
	(StudioTestService), driven by test code, with the results in the test server's log file. Studio only: nothing
	here runs in a live game (the scripts sit in ServerStorage, where scripts do not run, and the driver also checks
	RunService:IsStudio() and the test's own arguments).

	From execute_luau, in Edit mode:
	  return require(game.ServerStorage.Dev.MPTest:Clone()).start({ batch = "B", clients = 2 })
	It copies Driver (with Bot inside) into ServerScriptService as MPT_Driver, starts the test and returns at once.
	The copy is removed from the Edit data model when the test ends, and the QA_Lock it took is cleared.

	Arguments (all optional but batch):
	  batch     "A" combat (bow, thrown knife, weapon switches) | "B" sword reach, poses, loot, eating, the border,
	            a kill, the result, the Roll Call, round two | "B2" poses, eating, loot | "C" three clients: a kill,
	            spectating, the dusk Roll Call, a contender leaves | "D" loot, a client joins mid-round, a contender
	            leaves, the next round takes the late joiner | "E" a contender leaves during the Countdown | "G" the fill
	            rule: a third client joins during a 45-second lobby countdown, which starts again (fill = true) | "H" the
	            evening build (18 Nov): the train lobby, the personal intro skip (A in round one, B in round two), squirrels
	            (flee, climb, a hunt), sticks at a climbable trunk, a campfire A lights and B cooks on, a butterfly swarm
	            and its smoke escape, a tree climb and a seat, a rockfall, the "You won" line, the results board
	            | "W" the weapons build (19 Nov): Gold per player through a fake store and a rejoin, A's wheel spin and
	            Strongbox watched by B (the prize A's only, A's board holds until the reveal), the Armoury and BRING, the
	            kit pick, the midpoint parcel (lands 15 to 25 studs out, B steals A's, A opens its own and takes all),
	            stars (damage, the finish on B's screen and in A's first person), throws, the Twin-Bit Axe on armour, the
	            bow on a moving player at 60/100/150, the head cap, raw sword claims, the hotbar under load, the round's
	            Gold and board line, round two with Kits.Delivery = "Start"
	            | "F" Combat v3 (19 Nov, mp-fight): the loadouts per player (chosen, locked at the call, a change mid-round),
	            the load-in on both screens, A's sword chain and heavy as B sees them (clips, smoothness, the hit against
	            the clip's hit mark, A's swing trail), B's parry and counter, B's dodge, skills per player (Whirl, the
	            cooldowns, Sprint Burst ending on an attack, Concentration), A's arrow and throw trails and clips, B's
	            Others' trails setting, trails cosmetic, Paired Blades on B as A sees them, cheats, the moving checks.
	            fsteps = "chain,parry,..." runs only those steps
	            | "T" the road to the arena (19 Nov, mp-training; child module Training): three clients ride together,
	            train side by side (chests per station, dummies, targets, the striker, skills, drops), agree a truce (and one
	            not answered), the launch doors, the disc and the early call, the allies' plinths and marks, the truce's
	            three ends; round two with places for two, a late joiner during the ride, and the one left out spectating.
	            training / doors: Config.TrainFlow.TrainingTime and DoorsOpenBefore for round one (Studio defaults 85 / 30)
	  clients   2 (3 for batch "C"); minPlayers = clients for "C"
	  cut       "Short" | "Full": forces the launch cut (GameState.LaunchCutTest)
	  border    a small start radius for the ring (batch "B" uses 170, so "outside" is a few steps from the plates)
	  timeScale Config.Round.StudioTimeScale (batch "C" uses 6: dusk comes 57 s after the horn)
	  failsafe  seconds after which the test ends itself whatever happens (default 330)
	  respawn   Config.Round.RespawnDelay on the test server (default 4, the live value; Studio's own is 2)
	  quality   an Enum.QualityLevel name ("Level21"): asks each test window for that render quality (an unfocused Studio
	            window draws at its lowest, without small far parts); handed back before the test ends
	  plus      false leaves the PLUS member mark checks out (they use the Studio switch Workspace.PlusTestMember)
	  lock      the QA_Lock label to take (default "mp-test")

	Reading the result: every line starts with "[MPT]"; checks are "[MPT] nnnn t [CHECK] <id> PASS|FAIL|NOTE ...".
	  python tools/mp_test/readlog.py 6 --newest --grep CHECK
	Pictures of each client window at the driver's "SHOT <name>" lines: tools/mp_test/shots.ps1 (start it first).
	A server and two clients take about 9 GB of memory; they close by themselves when the batch ends.
	Test players are Player1, Player2, ... with UserIds -1, -2, ...; DataStores are off in Studio.
]]
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local MPTest = {}

function MPTest.start(args: { [string]: any }?): string
	if not RunService:IsStudio() or RunService:IsRunning() then
		return "MPTest: Edit mode in Studio only"
	end
	local a: { [string]: any } = table.clone(args or {})
	a.suite = "mpt"
	a.batch = a.batch or "B"
	a.clients = math.clamp(math.floor(tonumber(a.clients) or (if a.batch == "C" then 3 else 2)), 2, 4)
	a.minPlayers = a.minPlayers or (if a.batch == "C" then a.clients else 2)
	-- each batch's own settings, as in the runs of 18 November 2026
	if a.batch == "B" and a.border == nil then
		a.border = 170
	elseif a.batch == "C" then
		a.timeScale = a.timeScale or 6
		a.cut = a.cut or "Short"
	elseif a.batch == "D" or a.batch == "B2" then
		a.cut = a.cut or "Short"
	elseif a.batch == "G" then
		a.cut = a.cut or "Short"
		a.fill = true
		a.intermission = a.intermission or 45
	elseif a.batch == "H" then
		a.cut = a.cut or "Full"
		a.failsafe = a.failsafe or 600
	elseif a.batch == "W" then
		a.cut = a.cut or "Short"
		a.failsafe = a.failsafe or 840
	elseif a.batch == "F" then
		a.cut = a.cut or "Short"
		a.failsafe = a.failsafe or 600
	elseif a.batch == "T" then
		-- the ride, the Training Centre and allies (mp-training, 19 Nov): three clients, a late joiner in round two
		a.clients = math.max(a.clients, 3)
		a.minPlayers = a.minPlayers or 2
		a.cut = a.cut or "Short"
		a.failsafe = a.failsafe or 600
	end
	local label = tostring(a.lock or "mp-test")
	a.lock = nil
	local lock = workspace:GetAttribute("QA_Lock")
	if type(lock) == "string" and string.sub(lock, 1, #label + 1) ~= label .. "|" then
		local t = tonumber(string.match(lock, "|(%d+)$")) or 0
		if os.time() - t < 540 then
			return "MPTest: Studio is locked by " .. lock
		end
	end
	if not StudioTestService.EditModeActive then
		return "MPTest: a test is already running"
	end
	local driverSource = script:FindFirstChild("Driver")
	local botSource = script:FindFirstChild("Bot")
	if not (driverSource and botSource) then
		return "MPTest: Driver or Bot is missing (require a :Clone() of the module, children included)"
	end
	for _, child in ipairs(ServerScriptService:GetChildren()) do
		if child.Name == "MPT_Driver" then
			child:Destroy()
		end
	end
	workspace:SetAttribute("QA_Lock", label .. "|" .. os.time())
	local driver = driverSource:Clone()
	driver.Name = "MPT_Driver"
	local bot = botSource:Clone()
	bot.Name = "MPT_Bot"
	bot.Parent = driver
	local fight = script:FindFirstChild("Fight") -- (batch F: Combat v3, mp-fight)
	if fight then
		local f = fight:Clone()
		f.Name = "MPT_Fight"
		f.Parent = driver
	end
	local training = script:FindFirstChild("Training") -- (batch T: the ride, the hall and allies, mp-training)
	if training then
		local t = training:Clone()
		t.Name = "MPT_Training"
		t.Parent = driver
	end
	driver.Parent = ServerScriptService
	task.spawn(function()
		local ok, result = pcall(function()
			return StudioTestService:ExecuteMultiplayerTestAsync(a.clients, a)
		end)
		print("[MPT][EDIT] finished ok=" .. tostring(ok) .. " result=" .. tostring(result))
		local left = ServerScriptService:FindFirstChild("MPT_Driver")
		if left then
			left:Destroy()
		end
		workspace:SetAttribute("QA_Lock", nil)
		print("[MPT][EDIT] driver removed from Edit, lock cleared")
	end)
	return string.format("MPTest: batch %s with %d clients started at %d", tostring(a.batch), a.clients, os.time())
end

return MPTest
