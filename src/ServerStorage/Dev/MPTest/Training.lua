-- MPT_Training (mp-training, 19 Nov 2026): batch T of the MPTest driver. The train ride, the Training Centre's
-- stations and allies with three real clients, then a second round with a late joiner, held places and a spectator.
-- Test only: cloned under MPT_Driver by MPTest.start, required by the driver once the lobby has its players.
return function(ctx: { [string]: any })
	local L, check, call, mark, clientFind = ctx.L, ctx.check, ctx.call, ctx.mark, ctx.clientFind
	local parts, setHealth, health, slotOf, Inv, invLine = ctx.parts, ctx.setHealth, ctx.health, ctx.slotOf, ctx.Inv, ctx.invLine
	local waitFor, waitPhase, phase, shot, fmt, v3, now = ctx.waitFor, ctx.waitPhase, ctx.phase, ctx.shot, ctx.fmt, ctx.v3, ctx.now
	local Round, Combat, Services, Shared, req = ctx.Round, ctx.Combat, ctx.Services, ctx.Shared, ctx.req
	local A: Player, B: Player, C: Player? = ctx.A, ctx.B, ctx.P3
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local STS = game:GetService("StudioTestService")
	local LogService = game:GetService("LogService")
	local GS = RS:WaitForChild("GameState")
	local Config = require(Shared:WaitForChild("Config"))
	local TS = req(Shared, "TrainingStations")
	local Moves = req(Shared, "Moves")
	local Training = req(Services, "TrainingService")
	local Road = req(Services, "TrainRideService")
	local Ally = req(Services, "AllyService")

	local T = {}

	-- every hit the server applied in this batch (attacker, the body's model, dealt)
	local applied: { { t: number, attacker: string, victim: string, dealt: number } } = {}
	if Combat and type(Combat.applyHit) == "function" then
		local inner = Combat.applyHit
		Combat.applyHit = function(attacker, humanoid, base, info)
			local dealt, killed = inner(attacker, humanoid, base, info)
			table.insert(applied, { t = os.clock(), attacker = if attacker then attacker.Name else "nil",
				victim = if typeof(humanoid) == "Instance" and humanoid.Parent then humanoid.Parent.Name else "?", dealt = tonumber(dealt) or 0 })
			return dealt, killed
		end
	end

	-- every projectile the server fired, per shooter
	local firedBy: { [string]: number } = {}
	local Projectiles = Services:FindFirstChild("ProjectileService") and req(Services, "ProjectileService")
	if Projectiles and type(Projectiles.fire) == "function" then
		local innerFire = Projectiles.fire
		Projectiles.fire = function(shooter, ...)
			local id = innerFire(shooter, ...)
			if id and shooter then
				firedBy[shooter.Name] = (firedBy[shooter.Name] or 0) + 1
			end
			return id
		end
	end

	local function root(p: Player?): BasePart?
		local _, r = parts(p)
		return r
	end
	local function players(): { Player }
		local out = {}
		for _, p in ipairs({ A, B, C }) do
			if p and p.Parent == Players then
				table.insert(out, p)
			end
		end
		return out
	end
	local function floorAt(pos: Vector3): Vector3
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ex = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ex, p.Character)
			end
		end
		params.FilterDescendantsInstances = ex
		local hit = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
		return if hit then hit.Position else pos
	end
	local function put(p: Player, pos: Vector3, look: Vector3?)
		local c = p.Character
		local r = root(p)
		if not (c and r) then
			return
		end
		local g = floorAt(pos)
		local at = g + Vector3.new(0, 3.1, 0)
		local to = if look then Vector3.new(look.X, at.Y, look.Z) else at + r.CFrame.LookVector * Vector3.new(1, 0, 1)
		if (to - at).Magnitude < 0.1 then
			to = at + Vector3.new(0, 0, -1)
		end
		r.AssemblyLinearVelocity = Vector3.zero
		c:PivotTo(CFrame.lookAt(at, to))
	end
	local function hall(): CFrame
		return Training.hallCFrame()
	end
	local function stationPos(id: string, spot: string?): Vector3
		local s = TS.get(id)
		local base = hall() * CFrame.new(s.origin)
		if spot and s.spots[spot] then
			return (base * CFrame.new(s.spots[spot].pos)).Position
		end
		return base.Position
	end
	local function chestPart(id: string): BasePart?
		local want = stationPos(id, "chest")
		local folder = workspace:FindFirstChild("TrainingStations")
		local best, bd = nil, 12
		for _, d in ipairs(folder and folder:GetDescendants() or {}) do
			if d:IsA("BasePart") and d.Name == "Chest" and (d.Position - want).Magnitude < bd then
				best, bd = d, (d.Position - want).Magnitude
			end
		end
		return best
	end
	local function dummy(stance: string): any
		for _, e in ipairs(Training._dummies() or {}) do
			if e.stance == stance then
				return e
			end
		end
		return nil
	end
	local function dummyRoot(e: any): BasePart?
		local m = e and e.model
		local r = m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart)
		return if r and r:IsA("BasePart") then r else nil
	end
	local function inFront(e: any, dist: number, side: number?): Vector3
		local r = dummyRoot(e) :: BasePart
		local look = r.CFrame.LookVector * Vector3.new(1, 0, 1)
		local right = r.CFrame.RightVector * Vector3.new(1, 0, 1)
		return r.Position + look.Unit * dist + right.Unit * (side or 0)
	end
	local function bag(p: Player): { [string]: number }
		local out = {}
		local snap = Inv.getSnapshot(p)
		for _, s in ipairs(snap.slots) do
			if type(s) == "table" then
				out[s.id] = (out[s.id] or 0) + (tonumber(s.count) or 1)
			end
		end
		return out
	end
	local function lentIds(): { [string]: string }
		local out = {}
		for _, s in ipairs(TS.List) do
			for _, it in ipairs(s.chest or {}) do
				out[it.id] = s.id
			end
		end
		return out
	end
	local LENT = lentIds()
	local function lentIn(p: Player): string
		local out = {}
		for id, n in pairs(bag(p)) do
			if LENT[id] then
				table.insert(out, id .. "x" .. n)
			end
		end
		table.sort(out)
		return table.concat(out, ",")
	end
	local function ast(p: Player): any
		return call(p, "ally", { "state" }) or {}
	end
	local function hasLine(s: any, needle: string): boolean
		for _, l in ipairs(s.lines or {}) do
			if string.find(tostring(l), needle, 1, true) then
				return true
			end
		end
		return false
	end
	local function faceToFace(a: Player, b: Player, dist: number)
		local ra = root(a)
		if not ra then
			return
		end
		local look = ra.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude < 0.1 then
			look = Vector3.new(0, 0, -1)
		end
		local pos = ra.Position + look.Unit * dist
		put(b, pos, ra.Position)
		put(a, ra.Position, pos)
	end
	local function offer(a: Player, b: Player)
		call(a, "ally", { "aim", b.UserId })
		task.wait(0.3)
		call(a, "ally", { "hold", 0.5 })
		call(a, "ally", { "aim", nil })
	end
	local function ringAngle(p: Player): number?
		local r = root(p)
		if not r then
			return nil
		end
		local c = ctx.arenaCenter()
		return math.deg(math.atan2(r.Position.X - c.X, -(r.Position.Z - c.Z)))
	end
	local function gap(a: number?, b: number?): number
		if not (a and b) then
			return -1
		end
		local d = math.abs(a - b) % 360
		return math.min(d, 360 - d)
	end
	local function lobbyBox(): (CFrame?, Vector3?)
		local lobby = workspace:FindFirstChild("Lobby")
		if lobby and lobby:IsA("Model") then
			return lobby:GetBoundingBox()
		end
		return nil, nil
	end
	local function inTrainA(p: Player): boolean
		local cf, size = lobbyBox()
		local r = root(p)
		if not (cf and size and r) then
			return false
		end
		local lp = cf:PointToObjectSpace(r.Position)
		return math.abs(lp.X) <= size.X / 2 + 2 and math.abs(lp.Y) <= size.Y / 2 + 6 and math.abs(lp.Z) <= size.Z / 2 + 2
	end
	local function findDisc(): BasePart?
		for _, holder in ipairs({ workspace:FindFirstChild("TrainingCentre"), workspace:FindFirstChild("TrainStationB") }) do
			if holder then
				for _, d in ipairs(holder:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Disc" then
						return d
					end
				end
			end
		end
		return nil
	end
	local function onDisc(p: Player, disc: BasePart, k: number)
		local ang = k * 2.1
		local off = Vector3.new(math.cos(ang), 0, math.sin(ang)) * 1.2
		local top = disc.Position + Vector3.new(0, 4, 0) + off
		put(p, top, disc.Position + Vector3.new(0, 0, -20))
	end
	local function attrs(p: Player): string
		return string.format("%s AtTC=%s InTraining=%s Bay=%s Held=%s Rode=%s InRedRoom=%s Ready=%s", p.Name, tostring(p:GetAttribute("AtTrainingCentre")),
			tostring(p:GetAttribute("InTraining")), tostring(p:GetAttribute("TrainingBay")), tostring(p:GetAttribute("TrainHeld")), tostring(p:GetAttribute("Rode")),
			tostring(p:GetAttribute("InRedRoom")), tostring(p:GetAttribute("RedRoomReady")))
	end
	local function logHistory(needle: string): { string }
		local out = {}
		for _, e in ipairs(LogService:GetLogHistory()) do
			if string.find(e.message, needle, 1, true) then
				table.insert(out, string.sub(e.message, 1, 200))
			end
		end
		return out
	end

	-- before the release: the hall's timings for this test, truces allowed with three
	function T.lobby()
		local flow = (Config :: any).TrainFlow
		flow.TrainingTime = tonumber(ctx.ARGS.training) or 85
		flow.DoorsOpenBefore = tonumber(ctx.ARGS.doors) or 30
		L(string.format("TRAINFLOW Enabled=%s ride=%s training=%s doorsBefore=%s minTraining=%s readyHold=%s readyLead=%s road.enabled=%s",
			tostring(flow.Enabled), tostring(flow.RideTime), tostring(flow.TrainingTime), tostring(flow.DoorsOpenBefore), tostring(flow.MinTraining),
			tostring(flow.ReadyHold), tostring(flow.ReadyLead), tostring(Road and Road.enabled())))
		local set = workspace:FindFirstChild("TrainingCentre")
		check("t.set.built", Road ~= nil and Road.enabled() and set ~= nil, string.format("workspace.TrainingCentre=%s BlenderSet=%s parts=%d; log: %s | %s | lacks: %d",
			tostring(set ~= nil), tostring(set and set:GetAttribute("BlenderSet")), if set then #set:GetDescendants() else 0,
			table.concat(logHistory("[TrainRideService] train B"), " ; "), table.concat(logHistory("TrainingCentreBuilder"), " ; "), #logHistory("lacks")))
		GS:SetAttribute("AllyCapTest", 2)
		GS:SetAttribute("AllyEndAtTest", 0)
		-- three players, two of them allies, one not: the prep room (station) context first
		local sa = ast(A)
		L("ALLY prep state A: " .. fmt(sa))
	end

	-- round one ---------------------------------------------------------------------------------------------------------
	local function rideChecks(): boolean
		if not waitFor(function()
			return GS:GetAttribute("TrainStage") == "Ride"
		end, 90) then
			check("t.ride.departs", false, "no Ride within 90 s; phase=" .. phase() .. " stage=" .. tostring(GS:GetAttribute("TrainStage")))
			return false
		end
		local tDepart = now()
		local inA = {}
		for _, p in ipairs(players()) do
			table.insert(inA, p.Name .. "=" .. tostring(inTrainA(p)))
		end
		check("t.ride.departs", true, string.format("Ride at %.2f; ride %.1f s; in train A: %s", tDepart,
			(tonumber(GS:GetAttribute("TrainRideEnd")) or 0) - (tonumber(GS:GetAttribute("TrainRideStart")) or 0), table.concat(inA, " ")))
		local marks = {}
		for _, p in ipairs(players()) do
			marks[p] = mark(p)
		end
		task.wait(2)
		shot("t_ride", 0.5)
		if not waitFor(function()
			return GS:GetAttribute("TrainStage") == "Training"
		end, 40) then
			check("t.ride.arrives", false, "no Training stage within 40 s")
			return false
		end
		task.wait(1.2)
		local ok, detail, times, pos = true, {}, {}, {}
		for _, p in ipairs(players()) do
			local line = clientFind(p, "TRAINRIDE {kind=arrive", marks[p])
			local arrived = clientFind(p, "ARRIVED", marks[p])
			local t = line and tonumber(string.match(line, "^([%d%.]+)"))
			local off = arrived and tonumber(string.match(arrived, "camOff=([%d%.]+)"))
			table.insert(times, t or -1)
			local r = root(p)
			if r then
				table.insert(pos, r.Position)
			end
			local good = p:GetAttribute("AtTrainingCentre") == true and t ~= nil and off ~= nil and off < 20 and not inTrainA(p)
			ok = ok and good
			table.insert(detail, string.format("%s arrive at %s camOff=%s at %s", attrs(p), tostring(t), tostring(off), if r then v3(r.Position) else "?"))
		end
		local spreadT, spreadP = 0, 0
		for i = 1, #times do
			for j = 1, #times do
				spreadT = math.max(spreadT, math.abs(times[i] - times[j]))
			end
		end
		for i = 1, #pos do
			for j = 1, #pos do
				spreadP = math.max(spreadP, (pos[i] - pos[j]).Magnitude)
			end
		end
		-- (each keeps their spot in the four-car train: up to its length, about 300 studs, apart)
		check("t.ride.together", ok and spreadT < 1 and spreadP < 320, string.format("all moved in one step: arrive lines %.2f s apart, standing within %.1f studs | %s",
			spreadT, spreadP, table.concat(detail, " | ")))
		shot("t_arrived", 0.6)
		return true
	end

	local function stationChecks()
		-- each to a different chest at once: A the blade circle, B the throwing range, C the survival corner
		local plan = { { A, "blades" }, { B, "throwing" }, { C, "survival" } }
		for _, pl in ipairs(plan) do
			local p, id = pl[1], pl[2]
			local chest = chestPart(id)
			if p and chest then
				local inward = (stationPos(id) - chest.Position) * Vector3.new(1, 0, 1)
				put(p, chest.Position + inward.Unit * 3.5, chest.Position)
			else
				L(string.format("STATION no chest for %s (%s)", id, tostring(p)))
			end
		end
		task.wait(1.0)
		local done = {}
		for _, pl in ipairs(plan) do
			if pl[1] then
				task.spawn(function()
					done[pl[1]] = call(pl[1], "tprompt", { match = "borrow", radius = 10 }, 6)
				end)
			end
		end
		waitFor(function()
			local n = 0
			for _ in pairs(done) do
				n += 1
			end
			return n >= #players()
		end, 8)
		task.wait(1.5)
		local ok, detail = true, {}
		for _, pl in ipairs(plan) do
			local p, id = pl[1], pl[2]
			if p then
				local have = bag(p)
				local own, foreign = true, {}
				for _, it in ipairs(TS.chestItems(id)) do
					own = own and (have[it.id] or 0) >= it.count
				end
				for itemId in pairs(have) do
					if LENT[itemId] and LENT[itemId] ~= id then
						table.insert(foreign, itemId)
					end
				end
				local st = call(p, "state") or {}
				local good = own and #foreign == 0 and p:GetAttribute("TrainingBay") == id
				ok = ok and good
				table.insert(detail, string.format("%s at %s: prompt %s; bag %s; foreign [%s]; client hotbar '%s'", attrs(p), id, tostring(done[p]), invLine(p),
					table.concat(foreign, ","), tostring(st.inv)))
			end
		end
		check("t.chest.perStation", ok, table.concat(detail, " | "))
		shot("t_chests", 0.6)
		-- the drop key in the hall does nothing to borrowed items (G sends DropSlot; InventoryService keeps it closed there)
		if C then
			local before = invLine(C)
			local loose = #workspace:GetDescendants()
			call(C, "fire", { name = "DropSlot", a = 1 })
			call(C, "fire", { name = "DropSlot", a = 2 })
			task.wait(1.0)
			check("t.drop.closedInHall", invLine(C) == before, string.format("C pressed drop on slots 1 and 2 in the hall: bag before '%s', after '%s' (workspace descendants %d -> %d)",
				before, invLine(C), loose, #workspace:GetDescendants()))
			-- C to the archery lanes: borrow the bow, step on lane 1's line, shoot at its pop-up targets (outside a round)
			task.spawn(function()
				local okB, eB = pcall(function()
					local chestA = chestPart("archery")
					if not chestA then
						return
					end
					local inward = (stationPos("archery") - chestA.Position) * Vector3.new(1, 0, 1)
					put(C, chestA.Position + inward.Unit * 3.5, chestA.Position)
					task.wait(0.8)
					call(C, "tprompt", { match = "borrow", radius = 10 }, 6)
					task.wait(0.6)
					local folder = workspace:FindFirstChild("TrainingStations")
					local arch = folder and folder:FindFirstChild("archery")
					local start = arch and arch:FindFirstChild("LaneStart1")
					local targets = {}
					for _, d in ipairs(arch and arch:GetChildren() or {}) do
						if d:IsA("Model") and string.sub(d.Name, 1, 8) == "Target1_" then
							table.insert(targets, d)
						end
					end
					local bowSlot = slotOf(C, "short_bow")
					if not (start and bowSlot and #targets > 0) then
						check("t.bow.outsideRound", false, string.format("no lane start (%s), bow slot (%s) or targets (%d); C's bag %s", tostring(start), tostring(bowSlot), #targets, invLine(C)))
						return
					end
					put(C, start.Position, targets[1]:GetPivot().Position)
					task.wait(1.2)
					local fired0 = firedBy[C.Name] or 0
					local mC = mark(C)
					local shots = {}
					for k = 1, 6 do
						-- aim at the centre of lane 1's target that is up now (TrainingService marks it Up = true)
						local best = waitFor(function()
							for _, t in ipairs(targets) do
								if t:GetAttribute("Up") == true then
									return t
								end
							end
							return nil
						end, 5)
						local aim = best and best:GetPivot().Position
						if aim then
							call(C, "seq", { { "select", bowSlot }, { "wait", if k == 1 then 0.8 else 0.1 }, { "face", aim }, { "down" }, { "wait", 1.2 }, { "face", aim }, { "up" },
								{ "wait", 0.5 } }, 6)
							table.insert(shots, best.Name)
						end
					end
					task.wait(0.8)
					local d = Training._state(C) and Training._state(C).drill
					check("t.bow.outsideRound", (firedBy[C.Name] or 0) > fired0 and phase() == "Intermission", string.format(
						"C shot %d arrows in the hall (aimed at %s): the server fired %d; archery drill %s score=%s points=%s (the centre ring counts double); bag %s; C's archery lines: %s",
						#shots, table.concat(shots, ","), (firedBy[C.Name] or 0) - fired0, tostring(d and d.id), tostring(d and d.score), tostring(d and d.points), invLine(C),
						table.concat(ctx.linesWith(C, mC, "id=archery"), " ; ")))
					local best = 0
					for _, l in ipairs(ctx.linesWith(C, mC, "id=archery")) do
						best = math.max(best, tonumber(string.match(l, "score=(%d+)")) or 0)
					end
					check("t.archery.hitsCount", best >= 1 or (d ~= nil and (d.score or 0) >= 1), string.format(
						"C's arrows at the target that was up: best score on C's screen %d, server drill score %s points %s (a centre-ring hit counts 2 points)", best,
						tostring(d and d.score), tostring(d and d.points)))
				end)
				if not okB then
					L("DRIVER ERROR archery: " .. tostring(eB))
				end
			end)
		end
	end

	local function hitChecks()
		local target, blocker, striker = dummy("Target"), dummy("Blocker"), dummy("Striker")
		if not (target and blocker and striker and dummyRoot(target)) then
			check("t.dummies", false, "the four dummies were not found: " .. #(Training._dummies() or {}))
			return
		end
		-- B: the throwing line, a throwing knife at the 20-stud board (a real throw from B's client)
		local line = stationPos("throwing", "start")
		put(B, line, line + (hall().RightVector * 20))
		task.wait(0.8)
		local sB = Training._state(B)
		local knife = slotOf(B, "throwing_knife")
		local s = TS.get("throwing")
		local board = (hall() * CFrame.new(s.origin) * CFrame.new(20 + (s.boardFront or 0), s.boardHeight or 4.4, s.boardOffsets[2])).Position
		local mB = mark(B)
		if knife then
			call(B, "seq", { { "select", knife }, { "wait", 0.7 }, { "face", board }, { "wait", 0.3 }, { "click", 0.05 }, { "wait", 1.2 } }, 8)
		end
		task.wait(1.0)
		sB = Training._state(B)
		local dB = sB and sB.drill
		check("t.throw.countsForB", dB ~= nil and dB.id == "throwing" and (dB.extra.throws or 0) >= 1, string.format(
			"B on the throwing line: drill=%s throws=%s score=%s; knife slot %s; B's client: %s", tostring(dB and dB.id), tostring(dB and dB.extra.throws),
			tostring(dB and dB.score), tostring(knife), tostring((clientFind(B, "TRAINING {id=throwing", mB)))))
		-- A: the blade circle's centre pad (the drill), then a real sword blow on the Target dummy
		put(A, stationPos("blades", "start"), dummyRoot(target).Position)
		task.wait(0.8)
		local sword = slotOf(A, "sword")
		put(A, inFront(target, 3.6), dummyRoot(target).Position)
		task.wait(0.4)
		local n0 = #applied
		if sword then
			call(A, "seq", { { "select", sword }, { "wait", 0.8 }, { "face", dummyRoot(target).Position }, { "wait", 0.3 }, { "click", 0.05 }, { "wait", 1.0 },
				{ "face", dummyRoot(target).Position }, { "click", 0.05 }, { "wait", 1.0 } }, 10)
		end
		local hitA = {}
		for i = n0 + 1, #applied do
			table.insert(hitA, string.format("%s>%s %.1f", applied[i].attacker, applied[i].victim, applied[i].dealt))
		end
		local landed = false
		for i = n0 + 1, #applied do
			landed = landed or (applied[i].attacker == A.Name and applied[i].dealt > 0)
		end
		check("t.hit.dummyOutsideRound", landed and phase() == "Intermission", "phase=" .. phase() .. ", A's sword in the hall: [" .. table.concat(hitA, "; ") .. "] refusals: "
			.. ctx.refusals())
		shot("t_dummy_hit", 0.4)
		-- B walks over to the circle: B's throwing items go back (they stay in their bay)
		put(B, stationPos("blades", "start") + Vector3.new(1.2, 0, 0), dummyRoot(blocker).Position)
		task.wait(1.0)
		check("t.lent.backOnBayLeave", lentIn(B) == "", "B's lent items after leaving the throwing bay: '" .. lentIn(B) .. "' bag " .. invLine(B))
		-- players never hurt each other in the hall: a server-side blow and a real swing, A on B
		local hb = parts(B)
		local before = health(B)
		local okH, dealt = pcall(Combat.applyHit, A, hb, 25, { cause = "Combat", weaponId = "sword", melee = true, position = root(A) and root(A).Position })
		put(B, inFront(target, 6, 3), dummyRoot(target).Position)
		task.wait(0.3)
		local rb = root(B)
		if sword and rb then
			put(A, rb.Position + rb.CFrame.LookVector * 3.5, rb.Position)
			task.wait(0.3)
			call(A, "seq", { { "face", B.Name }, { "wait", 0.2 }, { "click", 0.05 }, { "wait", 0.9 } }, 6)
		end
		task.wait(0.4)
		check("t.hall.noPvP", okH and (tonumber(dealt) or 0) == 0 and math.abs(health(B) - before) < 0.01 and B:GetAttribute("InTraining") == true, string.format(
			"applyHit(A -> B, 25) in the hall: ok=%s dealt=%s; then A's real swing at B; B's health %.1f -> %.1f; B InTraining=%s", tostring(okH), tostring(dealt), before,
			health(B), tostring(B:GetAttribute("InTraining"))))
		-- the blocker's clean hits count for whoever struck it: A and B both on the centre pad (both in the drill), A nearer
		put(A, stationPos("blades", "start") + Vector3.new(-0.8, 0, 0), dummyRoot(blocker).Position)
		put(B, stationPos("blades", "start") + Vector3.new(0.8, 0, 0), dummyRoot(blocker).Position)
		task.wait(0.9)
		local sa, sb = Training._state(A), Training._state(B)
		local inDrill = sa and sa.drill and sa.drill.id == "blades" and sb and sb.drill and sb.drill.id == "blades"
		put(A, inFront(blocker, 3.0, 0), dummyRoot(blocker).Position)
		put(B, inFront(blocker, 5.5, 2), dummyRoot(blocker).Position)
		waitFor(function()
			return blocker.model:GetAttribute("Guard") ~= true
		end, 3)
		local hA0 = sa and sa.drill and sa.drill.extra.hits or 0
		local hB0 = sb and sb.drill and sb.drill.extra.hits or 0
		pcall(Combat.applyHit, B, blocker.model:FindFirstChildOfClass("Humanoid"), 10, { cause = "Combat", weaponId = "sword", melee = true, position = root(B) and root(B).Position })
		task.wait(0.4)
		sa, sb = Training._state(A), Training._state(B)
		local hA1 = sa and sa.drill and sa.drill.extra.hits or 0
		local hB1 = sb and sb.drill and sb.drill.extra.hits or 0
		check("t.dummy.creditsStriker", inDrill and hB1 == hB0 + 1 and hA1 == hA0, string.format(
			"both in the blades drill=%s; B struck the blocker (A stands nearer, 3.0 vs 5.5 studs): A's hits %d -> %d, B's %d -> %d", tostring(inDrill), hA0, hA1, hB0, hB1))
		-- the striker picks the nearest player in front of it, and hurts nobody
		local function victimWithin(seconds: number): string?
			return waitFor(function()
				local v = striker.data and striker.data.victim
				return if v then v.Name else nil
			end, seconds)
		end
		local hpA, hpB = health(A), health(B)
		put(A, inFront(striker, 4, 0), dummyRoot(striker).Position)
		put(B, inFront(striker, 6.5, 1.5), dummyRoot(striker).Position)
		local v1 = victimWithin(6)
		task.wait(1.4)
		put(B, inFront(striker, 3.5, 0), dummyRoot(striker).Position)
		put(A, inFront(striker, 6.5, -1.5), dummyRoot(striker).Position)
		local v2 = waitFor(function()
			local v = striker.data and striker.data.victim
			return if v and v.Name ~= v1 then v.Name elseif v and v1 ~= A.Name then v.Name else nil
		end, 6)
		task.wait(1.4)
		check("t.striker.nearest", v1 == A.Name and v2 == B.Name and health(A) >= hpA - 0.01 and health(B) >= hpB - 0.01, string.format(
			"A nearer: the striker chose %s; then B nearer: %s; health A %.1f -> %.1f, B %.1f -> %.1f", tostring(v1), tostring(v2), hpA, health(A), hpB, health(B)))
		-- a skill in the hall recharges at a quarter
		local gid = A:GetAttribute("SkillGeneral")
		local def = Moves and Moves.skills and Moves.skills.General[gid]
		call(A, "skill", { slot = "general" })
		task.wait(0.6)
		local readyAt = tonumber(A:GetAttribute("SkillGeneralReadyAt")) or 0
		local left = readyAt - workspace:GetServerTimeNow()
		local want = (def and def.Cooldown or 30) * (tonumber(A:GetAttribute("TrainingCooldownScale")) or 1)
		check("t.skill.quarter", def ~= nil and readyAt > 0 and math.abs(left + 0.6 - want) < 1.2 and A:GetAttribute("TrainingCooldownScale") == 0.25, string.format(
			"A's general skill %s (cooldown %s s) in the hall: ready again in %.1f s (+0.6 s since); scale %s, so %.1f s expected", tostring(gid), tostring(def and def.Cooldown),
			left, tostring(A:GetAttribute("TrainingCooldownScale")), want))
	end

	local function allyPrepChecks()
		if not C then
			return
		end
		-- C offers A; A does not answer: no truce
		faceToFace(C, A, 6)
		task.wait(0.5)
		offer(C, A)
		local seen = waitFor(function()
			local s = ast(A)
			return if string.find(s.offer or "", C.DisplayName, 1, true) then s else nil
		end, 4)
		check("t.ally.offerOnly", seen ~= nil and not Ally.allied(A, C), string.format("A's offer line from C: '%s'; allied(A, C)=%s", tostring(seen and seen.offer),
			tostring(Ally.allied(A, C))))
		-- A offers B (the walk-up gesture), B holds T: allies
		faceToFace(A, B, 6)
		task.wait(0.5)
		offer(A, B)
		local offerB = waitFor(function()
			local s = ast(B)
			return if string.find(s.offer or "", A.DisplayName, 1, true) then s else nil
		end, 4)
		call(B, "ally", { "hold", 0.5 })
		local agreed = waitFor(function()
			return Ally.allied(A, B)
		end, 4)
		task.wait(1.0)
		local sa, sb, sc = ast(A), ast(B), ast(C)
		check("t.ally.bothAgree", agreed ~= nil and hasLine(sa, "Truce agreed") and hasLine(sb, "Truce agreed") and not Ally.allied(A, C) and not Ally.allied(B, C),
			string.format("B saw '%s'; allied A-B=%s A-C=%s B-C=%s; A lines %s; B lines %s", tostring(offerB and offerB.offer), tostring(Ally.allied(A, B)), tostring(Ally.allied(A, C)),
				tostring(Ally.allied(B, C)), fmt(sa.lines), fmt(sb.lines)))
		check("t.ally.marksOnlyAllies", #(sa.marks or {}) == 1 and #(sb.marks or {}) == 1 and #(sc.marks or {}) == 0, string.format("marks: A %s | B %s | C %s",
			fmt(sa.marks), fmt(sb.marks), fmt(sc.marks)))
		shot("t_ally_prep", 0.6)
		-- C asks A, already in a full pair
		offer(C, A)
		task.wait(1.0)
		sc = ast(C)
		check("t.ally.capFull", not Ally.allied(A, C) and (hasLine(sc, "too big") or hasLine(sc, "truce")), "C's lines: " .. fmt(sc.lines))
		call(A, "ally", { "tap" })
		task.wait(0.5)
		sa = ast(A)
		L("ALLY A's quiet list: open=" .. tostring(sa.listOpen) .. " rows=" .. fmt(sa.rows))
		call(A, "ally", { "list", false })
	end

	local function doorsAndCall(): { [string]: any }
		local res = {}
		local opened = waitFor(function()
			return GS:GetAttribute("TrainDoorsOpen") == true
		end, 80)
		task.wait(0.6)
		local held = {}
		for _, p in ipairs(players()) do
			table.insert(held, attrs(p))
		end
		check("t.doors.held", opened ~= nil, "doors open at " .. string.format("%.2f", now()) .. ": " .. table.concat(held, " | "))
		local disc = findDisc()
		if not disc then
			check("t.disc", false, "no Disc part under TrainingCentre or TrainStationB")
			return res
		end
		-- A borrows the circle's blades again, then walks out through the doors with them
		local chest = chestPart("blades")
		if chest then
			local inward = (stationPos("blades") - chest.Position) * Vector3.new(1, 0, 1)
			put(A, chest.Position + inward.Unit * 3.5, chest.Position)
			task.wait(0.8)
			call(A, "tprompt", { match = "borrow", radius = 10 }, 6)
			task.wait(0.8)
		end
		local lentBefore = lentIn(A)
		for k, p in ipairs(players()) do
			onDisc(p, disc, k)
		end
		local tOn = now()
		task.wait(0.8)
		local after = {}
		for _, p in ipairs(players()) do
			table.insert(after, p.Name .. " lent='" .. lentIn(p) .. "' InTraining=" .. tostring(p:GetAttribute("InTraining")) .. " InRedRoom=" .. tostring(p:GetAttribute("InRedRoom")))
		end
		check("t.lent.backAtDoors", lentBefore ~= "" and lentIn(A) == "" and lentIn(B) == "" and (not C or lentIn(C) == ""), "A's lent before the doors '" .. lentBefore .. "'; on the disc: "
			.. table.concat(after, " | "))
		local ready = waitFor(function()
			for _, p in ipairs(players()) do
				if p:GetAttribute("TrainHeld") == true and p:GetAttribute("RedRoomReady") ~= true then
					return false
				end
			end
			return true
		end, 8)
		local tReady = now()
		local callAt = tonumber(GS:GetAttribute("TrainCallAt")) or 0
		res.tOn, res.tReady, res.callAt = tOn, tReady, callAt
		check("t.call.early", ready ~= nil and (callAt % 100000) - tReady > 3 and (callAt % 100000) - tReady < 7, string.format(
			"on the disc at %.2f, all held Ready at %.2f (%.1f s), the call set for %.2f (%.1f s later)", tOn, tReady, tReady - tOn, callAt % 100000, (callAt % 100000) - tReady))
		shot("t_disc", 0.4)
		return res
	end

	local function arenaAllyChecks()
		if not C then
			return
		end
		task.wait(2.0)
		faceToFace(A, B, 24)
		task.wait(1.5)
		local sa, sb, sc = ast(A), ast(B), ast(C)
		check("t.arena.marks", Ally.allied(A, B) and #(sa.marks or {}) == 1 and #(sb.marks or {}) == 1 and #(sc.marks or {}) == 0, string.format(
			"allied A-B=%s; A %s | B %s | C %s", tostring(Ally.allied(A, B)), fmt(sa.marks), fmt(sb.marks), fmt(sc.marks)))
		check("t.arena.compass", sa.marks and sa.marks[1] and sa.marks[1].tick == true, "A's mark: " .. fmt(sa.marks and sa.marks[1]))
		shot("t_arena_marks", 0.6)
		-- a hit between allies lands and ends it (both told)
		local hb = parts(B)
		local before = health(B)
		local okH, dealt = pcall(Combat.applyHit, A, hb, 12, { cause = "Combat", weaponId = "knife", melee = true, position = root(A) and root(A).Position })
		task.wait(1.2)
		sa, sb = ast(A), ast(B)
		check("t.truce.endsOnHit", okH and health(B) < before and not Ally.allied(A, B) and hasLine(sb, A.DisplayName .. " broke the truce") and hasLine(sa, "You broke the truce"),
			string.format("B %.1f -> %.1f (dealt %s); A %s | B %s", before, health(B), tostring(dealt), fmt(sa.lines), fmt(sb.lines)))
		shot("t_truce_broke", 0.4)
		setHealth(B)
		-- A and C agree in the arena; the Offering's bell ends it
		faceToFace(A, C, 6)
		task.wait(0.4)
		offer(A, C)
		task.wait(0.6)
		call(C, "ally", { "hold", 0.5 })
		local ac = waitFor(function()
			return Ally.allied(A, C)
		end, 4)
		GS:SetAttribute("ArenaEvent", "Feast")
		task.wait(1.3)
		local s1, s3 = ast(A), ast(C)
		check("t.truce.endsAtBell", ac ~= nil and not Ally.allied(A, C) and hasLine(s1, "The truce is over") and hasLine(s3, "The truce is over"), string.format(
			"A-C agreed in the arena=%s; after the bell allied=%s; A %s | C %s", tostring(ac ~= nil), tostring(Ally.allied(A, C)), fmt(s1.lines), fmt(s3.lines)))
		GS:SetAttribute("ArenaEvent", "")
		Ally._testReset()
		-- B and C agree; "four left" (three left, AllyEndAtTest = 3) ends it
		faceToFace(B, C, 6)
		task.wait(0.4)
		offer(B, C)
		task.wait(0.6)
		call(C, "ally", { "hold", 0.5 })
		local bc = waitFor(function()
			return Ally.allied(B, C)
		end, 4)
		GS:SetAttribute("AllyEndAtTest", 3)
		task.wait(1.5)
		local s2, s4 = ast(B), ast(C)
		check("t.truce.endsAtFour", bc ~= nil and not Ally.allied(B, C) and hasLine(s2, "The truce is over") and hasLine(s4, "The truce is over"), string.format(
			"B-C agreed=%s; with AliveCount %s <= 3 allied=%s; B %s | C %s", tostring(bc ~= nil), tostring(GS:GetAttribute("AliveCount")), tostring(Ally.allied(B, C)),
			fmt(s2.lines), fmt(s4.lines)))
		GS:SetAttribute("AllyEndAtTest", 0)
	end

	-- round two: places for two, a late joiner during the training, one left out who watches -------------------------------
	local function roundTwo()
		if not waitFor(function()
			return GS:GetAttribute("TrainStage") == "Ride"
		end, 90) then
			check("t2.ride", false, "no second ride within 90 s; phase " .. phase())
			return
		end
		local known = {}
		for _, p in ipairs(Players:GetPlayers()) do
			known[p] = true
		end
		local okAdd, errAdd = pcall(function()
			STS:AddPlayers(1)
		end)
		L("AddPlayers(1) at the ride: " .. tostring(okAdd) .. " " .. tostring(errAdd))
		local stageAtJoin = "?"
		local D = waitFor(function()
			for _, p in ipairs(Players:GetPlayers()) do
				if not known[p] then
					if stageAtJoin == "?" then
						stageAtJoin = tostring(GS:GetAttribute("TrainStage"))
					end
					if ctx.botReady[p] and p.Character and root(p) then
						return p
					end
				end
			end
			return nil
		end, 80)
		if not D then
			check("t2.late.join", false, "no new client within 80 s")
			return
		end
		local stageReady = tostring(GS:GetAttribute("TrainStage"))
		task.wait(3.0)
		local rd = root(D)
		check("t2.late.toPlatformB", D:GetAttribute("AtTrainingCentre") == true and not inTrainA(D), string.format(
			"%s joined (stage %s at the join, %s when its bot was ready): %s at %s, in train A=%s, %.0f studs from the hall", D.Name, stageAtJoin, stageReady, attrs(D),
			if rd then v3(rd.Position) else "?", tostring(inTrainA(D)), if rd then (rd.Position - hall().Position).Magnitude else -1))
		shot("t2_late_joiner", 0.5)
		local opened = waitFor(function()
			return GS:GetAttribute("TrainDoorsOpen") == true
		end, 70)
		task.wait(0.8)
		local heldList, all = {}, {}
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(all, attrs(p))
			if p:GetAttribute("TrainHeld") == true then
				table.insert(heldList, p)
			end
		end
		check("t2.doors.twoHeld", opened ~= nil and #heldList == 2, "held " .. #heldList .. " of " .. #Players:GetPlayers() .. ": " .. table.concat(all, " | "))
		-- everyone onto the disc: only the held count
		local disc = findDisc()
		if disc then
			for k, p in ipairs(Players:GetPlayers()) do
				onDisc(p, disc, k)
			end
		end
		task.wait(4.0)
		local readyStr = {}
		local onlyHeld = true
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(readyStr, p.Name .. " held=" .. tostring(p:GetAttribute("TrainHeld")) .. " ready=" .. tostring(p:GetAttribute("RedRoomReady")))
			if p:GetAttribute("TrainHeld") ~= true and p:GetAttribute("RedRoomReady") == true then
				onlyHeld = false
			end
		end
		check("t2.disc.onlyHeld", onlyHeld, table.concat(readyStr, " | "))
		if not waitPhase("Countdown", 40) then
			check("t2.call", false, "no Countdown")
			return
		end
		task.wait(0.5)
		local picked, out = true, {}
		local left: Player? = nil
		for _, p in ipairs(Players:GetPlayers()) do
			local isC = Round.isContender(p)
			picked = picked and (isC == (p:GetAttribute("TrainHeld") == true or table.find(heldList, p) ~= nil))
			if not isC then
				left = p
			end
			table.insert(out, p.Name .. " contender=" .. tostring(isC) .. " heldAtDoors=" .. tostring(table.find(heldList, p) ~= nil))
		end
		check("t2.call.heldFirst", picked and GS:GetAttribute("StartedCount") == 2, "StartedCount=" .. tostring(GS:GetAttribute("StartedCount")) .. ": " .. table.concat(out, " | "))
		task.wait(2.0)
		if left then
			check("t2.leftOut.backInTrainA", inTrainA(left) and lentIn(left) == "", string.format("%s left out: in train A=%s %s lent='%s'", left.Name, tostring(inTrainA(left)),
				attrs(left), lentIn(left)))
		end
		if not waitPhase("Active", 40) then
			check("t2.horn", false, "no Active")
			return
		end
		task.wait(2.0)
		if left then
			local target = nil
			for _, p in ipairs(Players:GetPlayers()) do
				if Round.isContender(p) then
					target = p
					break
				end
			end
			local res = call(left, "spectate", { op = "start", target = target and target.Name })
			task.wait(2.0)
			local st = call(left, "state") or {}
			-- where the watcher's screen has the watched contender, against the server (streamed in around them?)
			local function seenOff(): (number, string)
				local see = call(left, "see") or {}
				local s = target and see[target.Name]
				local rt = root(target)
				if not (s and s.pos and rt) then
					return -1, "not on the watcher's screen"
				end
				return (s.pos - rt.Position).Magnitude, string.format("watcher has it at %s, server %s; camera at %s", v3(s.pos), v3(rt.Position), fmt(st.camPos))
			end
			local off2, where2 = seenOff()
			task.wait(3.0)
			local off5, where5 = seenOff()
			shot("t2_spectator_5s", 0.3)
			task.wait(10.0)
			local off15, where15 = seenOff()
			local st15 = call(left, "state") or {}
			-- the watched body's parts as the watcher's client has them (a stale copy left from the hall?)
			local seeAll = call(left, "see") or {}
			local sTarget = target and seeAll[target.Name]
			check("t2.spectator", target ~= nil and st.spectating == target.Name and left:GetAttribute("InArena") ~= true and off5 >= 0 and off5 < 3, string.format(
				"%s (left out) spectates %s: %s; client spectating=%s camSubject=%s | after 2 s off by %.1f (%s) | after 5 s off by %.1f (%s) | after 15 s off by %.1f (%s), camera %s; the watcher's copy: %s",
				left.Name, tostring(target and target.Name), tostring(res), tostring(st.spectating), tostring(st.camSubject), off2, where2, off5, where5, off15, where15,
				fmt(st15.camPos), fmt(sTarget)))
			shot("t2_spectator", 0.6)
			call(left, "spectate", { op = "stop" })
		end
		local bagsOk, bags = true, {}
		for _, p in ipairs(Players:GetPlayers()) do
			if Round.isContender(p) then
				bagsOk = bagsOk and lentIn(p) == ""
				table.insert(bags, p.Name .. " " .. invLine(p))
			end
		end
		check("t2.arena.noLent", bagsOk, table.concat(bags, " | "))
	end

	function T.run()
		if not rideChecks() then
			return
		end
		local okS, eS = pcall(stationChecks)
		if not okS then
			L("DRIVER ERROR stations: " .. tostring(eS))
		end
		local okH, eH = pcall(hitChecks)
		if not okH then
			L("DRIVER ERROR hits: " .. tostring(eH))
		end
		local okA, eA = pcall(allyPrepChecks)
		if not okA then
			L("DRIVER ERROR allies: " .. tostring(eA))
		end
		-- the call (a watcher records the plinths and the bags at the Countdown)
		task.spawn(function()
			if waitPhase("Countdown", 120) then
				task.wait(1.2)
				local aA, aB, aC = ringAngle(A), ringAngle(B), C and ringAngle(C)
				check("t.plinths.allies", Ally.allied(A, B) and gap(aA, aB) >= 90, string.format("at the call allied A-B=%s; A-B %.0f degrees apart, A-C %.0f, B-C %.0f (need 90 for a pair)",
					tostring(Ally.allied(A, B)), gap(aA, aB), gap(aA, aC), gap(aB, aC)))
				local bags, ok = {}, true
				for _, p in ipairs(players()) do
					ok = ok and lentIn(p) == ""
					table.insert(bags, p.Name .. " " .. invLine(p))
				end
				check("t.arena.noLent", ok, table.concat(bags, " | "))
			end
		end)
		local okD, eD = pcall(doorsAndCall)
		if not okD then
			L("DRIVER ERROR doors: " .. tostring(eD))
		end
		if not ctx.roundStartChecks("round1") then
			return
		end
		local okR, eR = pcall(arenaAllyChecks)
		if not okR then
			L("DRIVER ERROR arena allies: " .. tostring(eR))
		end
		-- the round ends: B and C fall, A wins (round two's numbers set now, before the next ride departs)
		Config.Round.MaxContenders = 2
		local flow = (Config :: any).TrainFlow
		flow.TrainingTime = 55
		flow.DoorsOpenBefore = 18
		L("ROUND2 MaxContenders=2 training=55 doorsBefore=18")
		setHealth(B, 0)
		task.wait(0.5)
		if C then
			setHealth(C, 0)
		end
		ctx.backToLobby("t.r1", players())
		-- C leaves; round two takes a newcomer
		if C then
			call(C, "leave")
			waitFor(function()
				return C.Parent ~= Players
			end, 15)
			L("C left: " .. tostring(C.Parent ~= Players))
		end
		ctx.setExpect(2)
		local ok2, e2 = pcall(roundTwo)
		if not ok2 then
			L("DRIVER ERROR round two: " .. tostring(e2))
		end
	end

	return T
end
