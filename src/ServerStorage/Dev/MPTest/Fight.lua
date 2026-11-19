-- MPT_Fight (mp-fight, 19 Nov 2026): batch F of the MPTest driver, Combat v3 as two players see it. Test only: it is
-- cloned under MPT_Driver by MPTest.start and required by the driver once the lobby has its players (A and B known).
-- It lives apart from Driver.server.lua because a script's Source must stay under 200000 characters.
return function(ctx: { [string]: any })
	local L = ctx.L
	local check = ctx.check
	local call = ctx.call
	local mark = ctx.mark
	local linesWith = ctx.linesWith
	local clientFind = ctx.clientFind
	local parts = ctx.parts
	local setHealth = ctx.setHealth
	local health = ctx.health
	local duel = ctx.duel
	local setupDuel = ctx.setupDuel
	local slotOf = ctx.slotOf
	local Inv = ctx.Inv
	local invLine = ctx.invLine
	local refusals = ctx.refusals
	local flatDist = ctx.flatDist
	local Stars = ctx.Stars
	local dmgOf = ctx.dmgOf
	local movingChecks = ctx.movingChecks
	local resolves = ctx.resolves
	local Shared = ctx.Shared
	local Services = ctx.Services
	local req = ctx.req
	local ARGS = ctx.ARGS
	local A: Player, B: Player = ctx.A, ctx.B
	-- batch F: Combat v3 (19 Nov, mp-fight) --------------------------------------------------------------------------------
	local Moves = req(Shared, "Moves")
	local SkillSvc = req(Services, "SkillService")
	local F_TRAILS = { A = { TrailSwing = "kindle", TrailArrow = "comet", TrailThrow = "molten" }, B = { TrailSwing = "neon_thread" } }
	local function fTrails()
		for k, v in pairs(F_TRAILS.A) do
			A:SetAttribute(k, v)
		end
		for k, v in pairs(F_TRAILS.B) do
			B:SetAttribute(k, v)
		end
	end
	local function resolvesFrom(n: number, attacker: string?): { any }
		local out = {}
		for i = n + 1, #resolves do
			if attacker == nil or resolves[i].attacker == attacker then
				table.insert(out, resolves[i])
			end
		end
		return out
	end
	local function resStr(list: { any }): string
		local out = {}
		for _, r in ipairs(list) do
			table.insert(out, string.format("%s>%s %s %s %.2f", r.attacker, r.victim, r.move, r.result, r.dealt))
		end
		return "[" .. table.concat(out, "; ") .. "]"
	end
	local function skillRefusals(): string
		local out = {}
		for k, v in pairs((SkillSvc and SkillSvc._refusals) or {}) do
			table.insert(out, k .. "=" .. tostring(v))
		end
		table.sort(out)
		return table.concat(out, " ")
	end
	-- what `viewer` drew of `owner` since `from`: clips (names), swing trails (ids), shot trails, motion lines, hit timings
	local function viewOf(viewer: Player, owner: string, from: number): { [string]: any }
		local v = { clips = {}, trails = {}, shots = {}, motion = {}, hitAt = {}, maxStep = 0, rest = 0, minRange = math.huge, frozen = 0 }
		for _, line in ipairs(linesWith(viewer, from, " " .. owner)) do
			local clip = string.match(line, "CLIP " .. owner .. " (%S+)")
			if clip then
				table.insert(v.clips, clip)
			end
			local tid = string.match(line, "TRAIL%-SWING " .. owner .. "%S* id=(%S+)")
			if tid then
				table.insert(v.trails, tid)
			end
			local sid = string.match(line, "TRAIL%-SHOT " .. owner .. " item=%S+ local=%S+ id=(%S+)")
			if sid then
				table.insert(v.shots, sid)
			end
			if string.find(line, "SEE-MOTION " .. owner, 1, true) then
				local frames = tonumber(string.match(line, "frames=(%d+)")) or 0
				local ms = tonumber(string.match(line, "maxStepDeg=([%d%.]+)")) or 0
				local rest = tonumber(string.match(line, "restPoseFrames=(%d+)")) or 0
				local range = tonumber(string.match(line, "rangeDeg=([%d%.]+)")) or 0
				local clipName = string.match(line, "clip=(%S+)") or "?"
				table.insert(v.motion, string.format("%s f=%d max=%.0f (beside %s/%s) range=%.0f rest=%d", clipName, frames, ms, string.match(line, "prev=(%S+)") or "?",
				string.match(line, "next=(%S+)") or "?", range, rest))
				-- a snap: the largest one-frame turn standing alone (over 30 degrees and 2.5 times both frames beside it);
				-- a fast cut has big steps on both sides of its biggest
				local prev = tonumber(string.match(line, "prev=([%d%.%-]+)")) or 0
				local nxt = tonumber(string.match(line, "next=([%d%.%-]+)")) or 0
				if ms > 30 and ms > 2.5 * math.max(prev, nxt, 1) then
					v.snaps = (v.snaps or 0) + 1
				end
				if frames >= 3 then
					v.maxStep = math.max(v.maxStep, ms)
					v.rest += rest
					v.minRange = math.min(v.minRange, range)
					if range < 3 then
						v.frozen += 1
					end
				end
			end
			local d = string.match(line, "SEE%-HITAT " .. owner .. " .-delta=([%+%-][%d%.]+)")
			if d then
				table.insert(v.hitAt, tonumber(d))
			end
		end
		return v
	end
	local function listStr(t: { any }): string
		local out = {}
		for _, x in ipairs(t) do
			table.insert(out, if type(x) == "number" then string.format("%+.3f", x) else tostring(x))
		end
		return table.concat(out, ",")
	end
	local function maxAbs(t: { number }): number
		local m = 0
		for _, x in ipairs(t) do
			m = math.max(m, math.abs(x))
		end
		return m
	end
	local function hasPrefix(t: { string }, prefix: string): boolean
		for _, x in ipairs(t) do
			if string.sub(x, 1, #prefix) == prefix then
				return true
			end
		end
		return false
	end
	local function count(t: { string }, value: string): number
		local n = 0
		for _, x in ipairs(t) do
			if x == value then
				n += 1
			end
		end
		return n
	end

	local function fLobby()
		if ARGS.nearPlates then
			-- (test, this test server only: RoundService spreads a few contenders evenly round the ring, 260+ studs apart
			-- for 3, beyond the load-in's 160-stud draw range; leave only as many neighbouring plinths as there are players,
			-- so they start next to each other as in a full round)
			local folder = workspace:FindFirstChild("Arena") and workspace.Arena:FindFirstChild("Plinths")
			if folder then
				local list = {}
				for _, ch in ipairs(folder:GetChildren()) do
					if string.sub(ch.Name, 1, 6) == "Plinth" or game:GetService("CollectionService"):HasTag(ch, "Plinth") then
						table.insert(list, ch)
					end
				end
				table.sort(list, function(a, b)
					return a.Name < b.Name
				end)
				local keep = tonumber(ARGS.nearPlates) or #game:GetService("Players"):GetPlayers()
				for i, ch in ipairs(list) do
					if i > keep then
						game:GetService("CollectionService"):RemoveTag(ch, "Plinth")
						ch.Name = "MPTOff_" .. ch.Name
					end
				end
				L(string.format("nearPlates: kept %d of %d plinths (%s)", math.min(keep, #list), #list, if list[1] then list[1].Name else "-"))
			end
		end
		-- (test: skills open at once instead of 45 s into the round; set before the round, as SkillsOpenAt is published at the start)
		if Moves and Moves.skills then
			Moves.skills.LockedFirst = 0
		end
		-- each player's Loadout, chosen in the train through the game's own LoadoutSet
		-- (fspecA / fspecB: other Specialties for the ricochet and piercing steps, e.g. "Throwing" and "Bow")
		call(A, "fire", { name = "LoadoutSet", a = { specialty = ARGS.fspecA or "Axe", general = "sprint_burst" } })
		call(B, "fire", { name = "LoadoutSet", a = { specialty = ARGS.fspecB or "Sword", general = "concentration" } })
		task.wait(1.2)
		fTrails()
		check("f.loadout.chosen", A:GetAttribute("LoadoutSpecialty") == "Axe" and A:GetAttribute("LoadoutGeneral") == "sprint_burst"
			and B:GetAttribute("LoadoutSpecialty") == "Sword" and B:GetAttribute("LoadoutGeneral") == "concentration", string.format(
			"in the train: A Loadout %s + %s, B %s + %s", tostring(A:GetAttribute("LoadoutSpecialty")), tostring(A:GetAttribute("LoadoutGeneral")),
			tostring(B:GetAttribute("LoadoutSpecialty")), tostring(B:GetAttribute("LoadoutGeneral"))))
	end

	local function fGive()
		Inv.clear(A)
		Inv.clear(B)
		L("give A: sword " .. tostring(Inv.give(A, "sword", 1, 1)) .. " hatchet " .. tostring(Inv.give(A, "hatchet", 1, 4)) .. " bow " .. tostring(Inv.give(A, "bow", 1, 1))
			.. " arrow " .. tostring(Inv.give(A, "arrow", 10)) .. " throwing_knife " .. tostring(Inv.give(A, "throwing_knife", 4)))
		L("give B: sword " .. tostring(Inv.give(B, "sword", 1, 1)) .. " paired_blades " .. tostring(Inv.give(B, "paired_blades", 1, 5)))
		task.wait(0.6)
		L("inv A " .. invLine(A) .. " | inv B " .. invLine(B))
	end

	local function fFace()
		call(A, "face", B.Name)
		call(B, "face", A.Name)
		task.wait(0.3)
	end

	local function fChain()
		local sw, bsw = slotOf(A, "sword"), slotOf(B, "sword")
		call(B, "seq", { { "select", bsw }, { "wait", 0.5 } }, 4)
		setHealth(A)
		setHealth(B)
		L(duel(A, B, 4))
		fFace()
		-- (B held in place: a light blow's knockback pushes it out of the next step's reach, which hides the later steps)
		local _, rbA = parts(B)
		if rbA then
			rbA.Anchored = true
		end
		local mA, mB, n0 = mark(A), mark(B), #resolves
		task.delay(1.75, L, "SHOT f_chain")
		call(A, "seq", { { "select", sw }, { "wait", 0.7 }, { "face", B.Name }, { "wait", 0.2 }, { "click" }, { "wait", 0.62 }, { "click" }, { "wait", 0.62 }, { "click" },
			{ "wait", 0.62 }, { "click" }, { "wait", 1.3 } }, 15)
		task.wait(0.6)
		if rbA then
			rbA.Anchored = false
		end
		L("FPS A: " .. tostring(call(A, "fps", nil, 4)) .. " | B: " .. tostring(call(B, "fps", nil, 4)))
		local hits = resolvesFrom(n0, A.Name)
		local vb = viewOf(B, A.Name, mB)
		local va = viewOf(A, A.Name, mA)
		local moves = {}
		local dealtOk = true
		for _, r in ipairs(hits) do
			table.insert(moves, r.move)
			dealtOk = dealtOk and r.result == "Hit" and r.dealt > 0
		end
		local want = {}
		local def = Stars and Stars.def("sword", 1)
		for i = 1, 4 do
			local okS, st = pcall(Moves.step, def, "sword", i)
			table.insert(want, if okS and st then string.format("%.2f", st.damage) else "?")
		end
		check("f.chain.server", #hits >= 4 and dealtOk and table.concat(moves, ",") == "L1,L2,L3,L4", string.format(
			"A's Longsword 1* chain of four taps at B 4 studs away: the server resolved %s (the moves' damage %s)", resStr(hits), table.concat(want, "/")))
		check("f.chain.bSeesClips", #vb.clips >= 4 and hasPrefix(vb.clips, "sword_"), "clips B's client played on A's body: " .. listStr(vb.clips))
		check("f.chain.smooth", #vb.motion >= 3 and (vb.snaps or 0) == 0 and vb.rest == 0 and vb.frozen == 0, string.format(
			"A's body on B's screen while each clip played (largest one-frame turn of the right shoulder or waist, lone jumps of over 30 deg and 2.5x the frames beside them, frames at the rest pose, clips with under 3 degrees of movement): max %.0f deg, snaps %d, rest-pose frames %d, frozen %d | %s",
			vb.maxStep, vb.snaps or 0, vb.rest, vb.frozen, table.concat(vb.motion, " ; ")))
		check("f.chain.hitAtAnimatedMoment", #vb.hitAt >= 3 and maxAbs(vb.hitAt) <= 0.05, "on B's screen, where A's clip was against its hit mark when B's own health dropped (clip seconds): "
			.. listStr(vb.hitAt))
		check("f.chain.trailSeenByB", count(vb.trails, F_TRAILS.A.TrailSwing) >= 4, "swing trails B's client drew on A: " .. listStr(vb.trails))
		check("f.chain.ownTrail", count(va.trails, F_TRAILS.A.TrailSwing) >= 4 and #linesWith(A, mA, "CLIPVIEW") >= 4, string.format("A's own: swing trails %s; first-person clips %d",
			listStr(va.trails), #linesWith(A, mA, "CLIPVIEW")))
		L("f.chain A first-person clips: " .. table.concat(linesWith(A, mA, "CLIPVIEW"), " | "))
		return hits
	end

	local function fHeavy()
		setHealth(B)
		L(duel(A, B, 4))
		fFace()
		local mB, n0 = mark(B), #resolves
		call(A, "seq", { { "face", B.Name }, { "wait", 0.6 }, { "down" }, { "wait", 0.9 }, { "up" }, { "wait", 1.2 } }, 8)
		task.wait(0.4)
		local hits = resolvesFrom(n0, A.Name)
		local vb = viewOf(B, A.Name, mB)
		local okH, heavy = pcall(Moves.heavy, Stars and Stars.def("sword", 1), "sword", 0.9 + 0, false)
		check("f.heavy.server", #hits == 1 and hits[1].kind == "Heavy" and hits[1].dealt > 40, string.format("A holds Attack 0.9 s and lets go: %s (a full heavy: %s)", resStr(hits),
			if okH and heavy then string.format("%.2f", heavy.damage) else "?"))
		check("f.heavy.bSees", hasPrefix(vb.clips, "sword_heavy") and vb.rest == 0 and vb.frozen == 0, string.format("B's clips on A: %s | motion %s", listStr(vb.clips),
			table.concat(vb.motion, " ; ")))
		task.wait(2.6)
		local j = tostring(call(A, "probe", { kind = "joints", target = B.Name }))
		local deg = tonumber(string.match(j, "maxDeg=([%d%.]+)")) or 999
		check("f.fold.afterHeavy", deg < 50, string.format("B about 3 s after taking A's heavy %s, as A's client draws B: %s", resStr(hits), j))
	end

	local function fParry(try: number, counterDelay: number)
		setHealth(A)
		setHealth(B)
		L(duel(A, B, 4))
		fFace()
		task.wait(1.4) -- (past the chain window: a fresh first step)
		local mA, mB, n0, r0 = mark(A), mark(B), #resolves, refusals()
		call(B, "react", { target = A.Name, mode = "parry", lead = 0.1, counter = true, counterDelay = counterDelay, release = 1.2 })
		local _, ra0 = parts(A)
		local _, rb0 = parts(B)
		call(A, "seq", { { "face", B.Name }, { "wait", 0.2 }, { "click" }, { "wait", 1.6 } }, 6)
		task.wait(0.4)
		local _, ra = parts(A)
		local _, rb = parts(B)
		local list = resolvesFrom(n0)
		local parried, counter = nil, nil
		for _, r in ipairs(list) do
			if r.attacker == A.Name and r.result == "Parried" then
				parried = r
			elseif r.attacker == B.Name and r.move == "C" then
				counter = r
			end
		end
		local vb = viewOf(B, A.Name, mB)
		local va = viewOf(A, A.Name, mA)
		local sawParryB = clientFind(B, "ACT Parry", mB)
		local reboundOnB = {}
		for _, c in ipairs(vb.clips) do
			if not string.find(c, "^sword_L") then
				table.insert(reboundOnB, c)
			end
		end
		local gap = if ra and rb then flatDist(ra.Position, rb.Position) else -1
		check("f.parry." .. try, parried ~= nil and sawParryB ~= nil, string.format(
			"B raises its guard 0.1 s before A's light strike: server %s; B's client told it parried=%s (spark/sound, ACT Parry); clips B played on A after the strike %s; A's own clips %s",
			resStr(list), tostring(sawParryB ~= nil), listStr(reboundOnB), listStr(va.clips)))
		check("f.counter." .. try, counter ~= nil and counter.result == "Hit" and counter.dealt > 50, string.format(
			"B taps Attack %.2f s after its client is told of the parry: the counter %s; A and B %.1f studs apart after A's rebound (were %.1f); refusals before [%s] after [%s]; B's lines: %s",
			counterDelay, if counter then string.format("%s %.2f", counter.result, counter.dealt) else "none", gap,
			if ra0 and rb0 then flatDist(ra0.Position, rb0.Position) else -1, r0, refusals(), table.concat(linesWith(B, mB, "REACT"), " | ")))
		return parried ~= nil, counter ~= nil and counter.dealt > 0
	end

	local function fDodge()
		setHealth(A)
		setHealth(B)
		L(duel(A, B, 4))
		fFace()
		task.wait(1.4)
		local mA, mB, n0 = mark(A), mark(B), #resolves
		call(B, "react", { target = A.Name, mode = "dodge", lead = 0.2 })
		call(A, "seq", { { "face", B.Name }, { "wait", 0.2 }, { "click" }, { "wait", 1.2 } }, 6)
		task.wait(0.4)
		local list = resolvesFrom(n0, A.Name)
		local va = viewOf(A, B.Name, mA)
		local dodged = #list >= 1 and list[1].result == "Dodged"
		local missed = #list == 0 and health(B) >= 99.9
		check("f.dodge", (dodged or missed) and health(B) >= 99.9 and hasPrefix(va.clips, "dodge_"), string.format(
			"B dodges 0.2 s before A's strike: server %s, B's health %.1f; A's client played on B's body: %s | motion %s", resStr(list), health(B), listStr(va.clips),
			table.concat(va.motion, " ; ")))
	end

	local function fSkills()
		-- the loadouts locked at the call, each player's own
		check("f.loadout.locked", A:GetAttribute("RoundSpecialty") == "Axe" and A:GetAttribute("RoundGeneral") == "sprint_burst" and B:GetAttribute("RoundSpecialty") == "Sword"
			and B:GetAttribute("RoundGeneral") == "concentration" and A:GetAttribute("SkillSpecialty") == "Axe" and B:GetAttribute("SkillSpecialty") == "Sword", string.format(
			"at the call: A Round %s + %s (skills say %s + %s), B Round %s + %s (skills say %s + %s)", tostring(A:GetAttribute("RoundSpecialty")),
			tostring(A:GetAttribute("RoundGeneral")), tostring(A:GetAttribute("SkillSpecialty")), tostring(A:GetAttribute("SkillGeneral")), tostring(B:GetAttribute("RoundSpecialty")),
			tostring(B:GetAttribute("RoundGeneral")), tostring(B:GetAttribute("SkillSpecialty")), tostring(B:GetAttribute("SkillGeneral"))))
		local sr0 = skillRefusals()
		-- R with the sword in A's hand (Specialty Axe): refused
		local sw, hx = slotOf(A, "sword"), slotOf(A, "hatchet")
		call(A, "seq", { { "select", sw }, { "wait", 0.6 } }, 4)
		local mA0 = mark(A)
		call(A, "skill", { slot = "weapon" })
		task.wait(0.6)
		local sr1 = skillRefusals()
		local readyA0 = tonumber(A:GetAttribute("SkillWeaponReadyAt")) or 0
		-- the same as a modified client: the request itself, past the client's own check
		call(A, "fire", { name = "MeleeSwing", a = "Skill", b = "weapon" })
		task.wait(0.6)
		local sr2 = skillRefusals()
		check("f.skill.notSpecialty", string.find(sr2, "NotSpecialty=", 1, true) ~= nil and sr2 ~= sr1 and (tonumber(A:GetAttribute("SkillWeaponReadyAt")) or 0) == readyA0,
			string.format("A presses R holding the Longsword (its Specialty is Axe): skill refusals [%s] -> [%s], A's client lines %s; the raw request: [%s] (R not used: %s)", sr0, sr1,
				table.concat(linesWith(A, mA0, "Skill"), " | "), sr2, tostring((tonumber(A:GetAttribute("SkillWeaponReadyAt")) or 0) == readyA0)))
		-- the Whirl with the Hatchet
		setHealth(A)
		setHealth(B)
		L(duel(A, B, 3))
		fFace()
		local mB, n0 = mark(B), #resolves
		call(A, "seq", { { "select", hx }, { "wait", 0.7 }, { "face", B.Name } }, 4)
		L("SHOT f_whirl_soon")
		call(A, "skill", { slot = "weapon" })
		task.wait(1.4)
		local list = resolvesFrom(n0, A.Name)
		local vb = viewOf(B, A.Name, mB)
		local readyA = tonumber(A:GetAttribute("SkillWeaponReadyAt")) or 0
		check("f.skill.whirl", #list >= 1 and list[1].move == "Whirl" and list[1].dealt > 0 and hasPrefix(vb.clips, "axe_skill_whirl"), string.format(
			"A's Whirl (Hatchet 4*) on B 3 studs away: server %s; B's clips on A %s; motion %s; A's R ready again in %.1f s", resStr(list), listStr(vb.clips),
			table.concat(vb.motion, " ; "), readyA - workspace:GetServerTimeNow()))
		task.wait(2.0)
		do
			local j = tostring(call(A, "probe", { kind = "joints", target = B.Name }))
			local deg = tonumber(string.match(j, "maxDeg=([%d%.]+)")) or 999
			check("f.fold.afterWhirl", deg < 50, "B about 3.4 s after A's Whirl, as A's client draws B: " .. j)
		end
		-- per player: A's R again is refused (cooldown); B's R (Sword: Running Cut) works at once
		local srA = skillRefusals()
		call(A, "skill", { slot = "weapon" })
		task.wait(0.3)
		-- (A's own client already holds a skill in cooldown back; the request itself, as a modified client would send it)
		call(A, "fire", { name = "MeleeSwing", a = "Skill", b = "weapon" })
		task.wait(0.5)
		local srA2 = skillRefusals()
		task.wait(0.8)
		setHealth(A)
		L(duel(B, A, 6))
		call(B, "face", A.Name)
		local bsw = slotOf(B, "sword")
		call(B, "seq", { { "select", bsw }, { "wait", 0.6 }, { "face", A.Name } }, 4)
		local readyB0 = tonumber(B:GetAttribute("SkillWeaponReadyAt")) or 0
		local mA, n1 = mark(A), #resolves
		call(B, "skill", { slot = "weapon" })
		task.wait(1.2)
		local listB = resolvesFrom(n1, B.Name)
		local va = viewOf(A, B.Name, mA)
		local readyB = tonumber(B:GetAttribute("SkillWeaponReadyAt")) or 0
		check("f.skill.perPlayerCooldown", string.find(srA2, "Cooldown=", 1, true) ~= nil and srA2 ~= srA and readyB > readyB0 and readyB > workspace:GetServerTimeNow(), string.format(
			"A's second R at once: skill refusals %s -> %s; B's R straight after: B ready-at %.1f -> %.1f (accepted), B's Running Cut on A %s; A's clips on B %s", srA, srA2, readyB0,
			readyB, resStr(listB), listStr(va.clips)))
		-- general skills: A Sprint Burst (ends on an attack), B Concentration; each only on its own player
		task.wait(1.0)
		call(A, "skill", { slot = "general" })
		task.wait(0.4)
		local sbA = (tonumber(A:GetAttribute("SprintBurstUntil")) or 0) - workspace:GetServerTimeNow()
		local cA = A:GetAttribute("ConcentrationUntil")
		call(B, "skill", { slot = "general" })
		task.wait(0.4)
		local cB = (tonumber(B:GetAttribute("ConcentrationUntil")) or 0) - workspace:GetServerTimeNow()
		local sbB = B:GetAttribute("SprintBurstUntil")
		call(A, "seq", { { "click" }, { "wait", 0.5 } }, 4)
		task.wait(0.3)
		local sbA2 = (tonumber(A:GetAttribute("SprintBurstUntil")) or 0) - workspace:GetServerTimeNow()
		check("f.skill.general", sbA > 1.5 and cA == nil and cB > 4 and sbB == nil and sbA2 <= 0.05, string.format(
			"A's F: Sprint Burst %.1f s left (A's Concentration %s); B's F: Concentration %.1f s left (B's Sprint Burst %s); A attacks: Sprint Burst left %.2f s", sbA, tostring(cA), cB,
			tostring(sbB), sbA2))
		-- a Loadout change in the round changes nothing until the next round
		call(A, "fire", { name = "LoadoutSet", a = { specialty = "Bow", general = "brace" } })
		task.wait(1.0)
		check("f.loadout.midRound", A:GetAttribute("LoadoutSpecialty") == "Bow" and A:GetAttribute("RoundSpecialty") == "Axe" and A:GetAttribute("SkillSpecialty") == "Axe"
			and A:GetAttribute("SkillGeneral") == "sprint_burst" and B:GetAttribute("SkillSpecialty") == "Sword", string.format(
			"A picks Bow + Brace mid-round: Loadout %s + %s, Round %s, skills still %s + %s; B's skills %s + %s", tostring(A:GetAttribute("LoadoutSpecialty")),
			tostring(A:GetAttribute("LoadoutGeneral")), tostring(A:GetAttribute("RoundSpecialty")), tostring(A:GetAttribute("SkillSpecialty")), tostring(A:GetAttribute("SkillGeneral")),
			tostring(B:GetAttribute("SkillSpecialty")), tostring(B:GetAttribute("SkillGeneral"))))
	end

	local function fShots()
		local bow, tk = slotOf(A, "bow"), slotOf(A, "throwing_knife")
		setHealth(B)
		L(duel(A, B, 18))
		fFace()
		local mB, mA = mark(B), mark(A)
		call(A, "seq", { { "select", bow }, { "wait", 0.9 }, { "face", B.Name }, { "wait", 0.3 }, { "down" }, { "track", B.Name, 1.4 }, { "wait", 1.2 }, { "up" }, { "wait", 1.0 } }, 10)
		local vb = viewOf(B, A.Name, mB)
		local va = viewOf(A, A.Name, mA)
		check("f.bow.trailAndClip", count(vb.shots, F_TRAILS.A.TrailArrow) >= 1 and hasPrefix(vb.clips, "bow_release"), string.format(
			"A looses an arrow at B 18 studs away (B lost %.1f): B's shot trails for A %s, B's clips on A %s; A's own shot trails %s", 400 - health(B), listStr(vb.shots),
			listStr(vb.clips), listStr(va.shots)))
		setHealth(B)
		L(duel(A, B, 12))
		fFace()
		mB, mA = mark(B), mark(A)
		call(A, "seq", { { "select", tk }, { "wait", 0.9 }, { "face", B.Name }, { "wait", 0.3 }, { "click" }, { "wait", 1.0 } }, 8)
		vb = viewOf(B, A.Name, mB)
		va = viewOf(A, A.Name, mA)
		local throwClip = false
		for _, c in ipairs(vb.clips) do
			throwClip = throwClip or string.find(c, "throw", 1, true) ~= nil
		end
		check("f.throw.trailAndClip", count(vb.shots, F_TRAILS.A.TrailThrow) >= 1 and throwClip, string.format(
			"A throws a knife at B 12 studs away (B lost %.1f): B's shot trails for A %s, B's clips on A %s; A's own %s", 400 - health(B), listStr(vb.shots), listStr(vb.clips),
			listStr(va.shots)))
		setHealth(B)
	end

	local function fOthersTrails()
		local sw = slotOf(A, "sword")
		L(duel(A, B, 4))
		fFace()
		call(A, "seq", { { "select", sw }, { "wait", 0.7 } }, 4)
		local res = {}
		local dealt = {}
		for _, mode in ipairs({ { 2, "Natural" }, { 3, "Off" }, { 0, "Auto" } }) do
			call(B, "setting", { name = "othersTrails", value = mode[1] })
			L(duel(A, B, 4)) -- (each blow knocks B back: stand it in reach again)
			fFace()
			task.wait(0.8)
			setHealth(B)
			local mA, mB, n0 = mark(A), mark(B), #resolves
			call(A, "seq", { { "face", B.Name }, { "wait", 0.2 }, { "click" }, { "wait", 0.9 } }, 5)
			task.wait(0.3)
			local vb, va = viewOf(B, A.Name, mB), viewOf(A, A.Name, mA)
			res[mode[2]] = { b = vb.trails, a = va.trails }
			local h = resolvesFrom(n0, A.Name)
			table.insert(dealt, if h[1] then string.format("%.2f", h[1].dealt) else "none")
		end
		check("f.othersTrails", count(res.Natural.b, "draught") >= 1 and #res.Off.b == 0 and count(res.Natural.a, F_TRAILS.A.TrailSwing) >= 1 and count(res.Off.a, F_TRAILS.A.TrailSwing) >= 1,
			string.format("B's Others' trails Natural: B draws %s on A (A's own %s); Off: B draws [%s] (A's own %s); Auto: B draws %s", listStr(res.Natural.b), listStr(res.Natural.a),
				listStr(res.Off.b), listStr(res.Off.a), listStr(res.Auto.b)))
		-- trails are cosmetic: the same blow with A's trail off
		A:SetAttribute("TrailSwing", "none")
		L(duel(A, B, 4))
		fFace()
		task.wait(0.8)
		setHealth(B)
		local n0, mB = #resolves, mark(B)
		call(A, "seq", { { "face", B.Name }, { "wait", 0.2 }, { "click" }, { "wait", 0.9 } }, 5)
		task.wait(0.3)
		local h = resolvesFrom(n0, A.Name)
		table.insert(dealt, if h[1] then string.format("%.2f", h[1].dealt) else "none")
		local vb = viewOf(B, A.Name, mB)
		local same = dealt[1] == dealt[2] and dealt[2] == dealt[3] and dealt[3] == dealt[4] and dealt[1] ~= "none"
		check("f.trailsCosmetic", same and #vb.trails == 0, string.format("the same first step with B's setting Natural / Off / Auto and with A's trail set to none: dealt %s; B drew %s with none",
			table.concat(dealt, " / "), listStr(vb.trails)))
		fTrails()
	end

	local function fPaired()
		local pb = slotOf(B, "paired_blades")
		call(B, "seq", { { "select", pb }, { "wait", 1.0 } }, 4)
		L(duel(A, B, 5))
		fFace()
		task.wait(0.8)
		L("SHOT f_paired")
		task.wait(1.2)
		local info = call(A, "probe", { kind = "allheld", target = B.Name })
		L("f.paired A sees B's held parts: " .. tostring(info))
		local s = tostring(info)
		local models = tonumber(string.match(s, "models=(%d+)")) or 0
		check("f.paired.twoBlades", models >= 2, "on A's screen B holds Paired Blades 5*: " .. string.sub(s, 1, 1500))
	end

	local function fCheats()
		setHealth(A)
		setHealth(B)
		local sw = slotOf(A, "sword")
		call(A, "seq", { { "select", sw }, { "wait", 0.7 } }, 4)
		L(duel(A, B, 4))
		fFace()
		task.wait(1.4)
		-- a counter claimed with no parry
		local n0, r0 = #resolves, refusals()
		call(B, "rawswing", { target = A.Name, move = "C" })
		task.wait(0.8)
		local list = resolvesFrom(n0)
		check("f.cheat.counterNoParry", #list == 0 and health(A) >= 99.9, string.format("B claims a counter with no parry: server %s, A's health %.1f; refusals [%s] -> [%s]", resStr(list),
			health(A), r0, refusals()))
		-- a heavy claimed with a 1.5 s hold the server never saw
		task.wait(1.0)
		n0, r0 = #resolves, refusals()
		call(A, "rawswing", { target = B.Name, move = "H", held = 1.5 })
		task.wait(0.8)
		list = resolvesFrom(n0)
		check("f.cheat.heavyNoHold", #list <= 1 and (#list == 0 or (list[1].kind ~= "Heavy" and list[1].dealt <= dmgOf("sword") + 0.6)), string.format(
			"A claims a full heavy it never held: server %s (a light first step is %s); refusals [%s] -> [%s]", resStr(list), tostring(dmgOf("sword")), r0, refusals()))
		-- a skill strike with no skill running
		task.wait(1.0)
		n0, r0 = #resolves, refusals()
		call(B, "rawswing", { target = A.Name, move = "S1" })
		task.wait(0.8)
		list = resolvesFrom(n0)
		check("f.cheat.skillStrike", #list == 0, string.format("B claims a chained-strikes blow with no skill running: server %s; refusals [%s] -> [%s]", resStr(list), r0, refusals()))
		-- a light blow claimed from 12 studs
		setHealth(B)
		L(duel(A, B, 12))
		fFace()
		task.wait(1.0)
		n0, r0 = #resolves, refusals()
		call(A, "rawswing", { target = B.Name, move = "L1" })
		task.wait(0.8)
		list = resolvesFrom(n0)
		check("f.cheat.reach12", #list == 0 and health(B) >= 99.9, string.format("A claims a sword hit from 12 studs: server %s; refusals [%s] -> [%s]", resStr(list), r0, refusals()))
	end

	-- a third body for the glance and the pass-through: a plain R15 test figure tagged as a training dummy (the game's
	-- targets list takes those), held still, 400 health
	local function dummyAt(pos: Vector3, look: Vector3): (Model?, Humanoid?)
		local okM, m = pcall(function()
			return game:GetService("Players"):CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if not okM or not m then
			L("DUMMY failed: " .. tostring(m))
			return nil, nil
		end
		m.Name = "MPT_DummyC"
		local hum = m:FindFirstChildOfClass("Humanoid")
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum then
			hum.MaxHealth = 400
			hum.Health = 400
		end
		m:PivotTo(CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z)))
		if root then
			root.Anchored = true
		end
		m.Parent = workspace
		game:GetService("CollectionService"):AddTag(m, "TrainingDummy")
		return m, hum
	end
	-- Ricochet (A, Specialty Throwing): R arms it, the next thrown knife hits B and glances to C nearby at 70%
	local function fRicochet()
		local tk = slotOf(A, "throwing_knife")
		if not tk then
			Inv.give(A, "throwing_knife", 4)
			task.wait(0.4)
			tk = slotOf(A, "throwing_knife")
		end
		L(duel(A, B, 12))
		fFace()
		local _, ra = parts(A)
		local _, rb = parts(B)
		if not (ra and rb) then
			return
		end
		local dir = (rb.Position - ra.Position) * Vector3.new(1, 0, 1)
		dir = dir.Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local c, chum = dummyAt(rb.Position + dir * 7 + side * 3, rb.Position)
		task.wait(0.5)
		local cBefore = if chum then chum.Health else -1
		local bBefore = health(B)
		call(A, "seq", { { "select", tk }, { "wait", 0.9 }, { "face", B.Name } }, 4)
		call(A, "skill", { slot = "weapon" })
		task.wait(0.5)
		local armed = A:GetAttribute("SkillArmed")
		call(A, "seq", { { "face", B.Name }, { "wait", 0.3 }, { "click" }, { "wait", 1.5 } }, 6)
		task.wait(0.5)
		local dB, dC = bBefore - health(B), cBefore - (if chum then chum.Health else -1)
		check("f.skill.ricochet", armed == "ricochet" and dB > 0 and dC > 0 and math.abs(dC - dB * 0.7) < 1.0, string.format(
			"A arms Ricochet (SkillArmed=%s) and throws a knife at B 12 studs away, C stands 7 studs past B and 3 to the side: B lost %.2f, C lost %.2f (70%% of B's: %.2f); skill refusals %s",
			tostring(armed), dB, dC, dB * 0.7, skillRefusals()))
		if c then
			c:Destroy()
		end
	end
	-- Piercing Shot (B, Specialty Bow): R arms it, the next full-draw arrow passes through A and hits C behind at 70%
	local function fPierce()
		Inv.give(B, "bow", 1, 1)
		Inv.give(B, "arrow", 6)
		task.wait(0.5)
		local bow = slotOf(B, "bow")
		L(duel(B, A, 15))
		fFace()
		local _, ra = parts(A)
		local _, rb = parts(B)
		if not (ra and rb) then
			return
		end
		local dir = ((ra.Position - rb.Position) * Vector3.new(1, 0, 1)).Unit
		local c, chum = dummyAt(ra.Position + dir * 5, rb.Position)
		task.wait(0.5)
		setHealth(A)
		local aBefore, cBefore = health(A), if chum then chum.Health else -1
		call(B, "seq", { { "select", bow }, { "wait", 0.9 }, { "face", A.Name } }, 4)
		call(B, "skill", { slot = "weapon" })
		task.wait(0.5)
		local armed = B:GetAttribute("SkillArmed")
		call(B, "seq", { { "face", A.Name }, { "wait", 0.3 }, { "down" }, { "track", A.Name, 1.6 }, { "wait", 1.4 }, { "up" }, { "wait", 1.2 } }, 8)
		task.wait(0.5)
		local dA, dC = aBefore - health(A), cBefore - (if chum then chum.Health else -1)
		check("f.skill.piercingShot", armed == "piercing_shot" and dA > 0 and dC > 0 and math.abs(dC - dA * 0.7) < 1.0, string.format(
			"B arms Piercing Shot (SkillArmed=%s) and looses a full draw at A 15 studs away, C 5 studs behind A in line: A lost %.2f, C lost %.2f (70%% of A's: %.2f); skill refusals %s",
			tostring(armed), dA, dC, dA * 0.7, skillRefusals()))
		if c then
			c:Destroy()
		end
	end

	local function fLoadIn(from: { [Player]: number })
		local out, ok = {}, true
		local everyone = {}
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			if p:GetAttribute("InArena") == true or p:GetAttribute("Alive") == true then
				table.insert(everyone, p)
			end
		end
		-- where each contender stands: the plate gaps (the swirl of a player beyond 160 studs is not drawn, by design)
		local gaps = {}
		for i, p in ipairs(everyone) do
			for j = i + 1, #everyone do
				local _, r1 = parts(p)
				local _, r2 = parts(everyone[j])
				table.insert(gaps, string.format("%s-%s %.0f", p.Name, everyone[j].Name, if r1 and r2 then flatDist(r1.Position, r2.Position) else -1))
			end
		end
		for _, viewer in ipairs(everyone) do
			local lines = linesWith(viewer, from[viewer] or 0, "LOADIN ")
			local who = {}
			for _, line in ipairs(lines) do
				local name, played = string.match(line, "LOADIN (%S+) played=(%S+)")
				if name and played == "true" then
					who[name] = true
				end
			end
			for _, p in ipairs(everyone) do
				ok = ok and who[p.Name] == true
			end
			table.insert(out, string.format("%s's client: %s", viewer.Name, table.concat(lines, " | ")))
		end
		check("f.loadIn.both", ok and #everyone >= 2, string.format("the load-in swirl at the arena on each of %d clients (plate gaps %s): %s", #everyone,
			table.concat(gaps, ", "), table.concat(out, " || ")))
	end

	-- mp-finish (19 Nov, wave 11) --------------------------------------------------------------------------------------
	local CollectionService = game:GetService("CollectionService")
	local ServerStorage = game:GetService("ServerStorage")
	local standAt, groundAt = ctx.standAt, ctx.groundAt
	local function pt(v: Vector3): { [string]: number }
		return { x = v.X, y = v.Y, z = v.Z }
	end
	local function lowestY(m: Model): number
		local lo = math.huge
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 0.99 then
				local h = d.Size / 2
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							lo = math.min(lo, (d.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)).Y)
						end
					end
				end
			end
		end
		return lo
	end
	local function invStars(p: Player, itemId: string): string
		local snap = Inv.getSnapshot(p)
		local out = {}
		for _, s in ipairs(snap.slots) do
			if type(s) == "table" and s.id == itemId then
				table.insert(out, tostring(s.stars))
			end
		end
		return table.concat(out, ",")
	end
	local function goodLook(s: string, want: string): boolean
		return string.find(s, "tierMesh=" .. want, 1, true) ~= nil and string.find(s, "tiled=%[[^%]]") == nil and string.find(s, "trims=[1-9]") == nil
			and string.find(s, "mesh=[1-9]") ~= nil
	end

	-- B sees A's Blender weapons at their stars in hand; A's own first person; a weapon on the ground
	local LOOK_SET = { { "sword", 1 }, { "sword", 5 }, { "hatchet", 4 }, { "twin_axe", 5 }, { "knife", 5 }, { "ring_blade", 3 }, { "paired_blades", 5 },
		{ "leaf_dagger", 1 }, { "machete", 2 }, { "spear", 3 }, { "climb_pick", 4 } }
	local function fLooks()
		L(duel(A, B, 6))
		fFace()
		local bad = {}
		for _, w in ipairs(LOOK_SET) do
			Inv.clear(A)
			Inv.give(A, w[1], 1, w[2])
			task.wait(0.5)
			call(A, "seq", { { "select", slotOf(A, w[1]) }, { "wait", 1.1 } }, 4)
			local want = w[1] .. "_t" .. w[2]
			local seen = tostring(call(B, "probe", { kind = "look", target = A.Name }))
			local own = tostring(call(A, "probe", { kind = "look", target = "self" }))
			L("SHOT f_look_" .. want)
			task.wait(1.2)
			local okW = goodLook(seen, want) and goodLook(own, want)
			if w[1] == "paired_blades" then
				local mB = tonumber(string.match(seen, "models=(%d+)")) or 0
				local mA = tonumber(string.match(own, "models=(%d+)")) or 0
				okW = okW and mB >= 2
				L(string.format("f.look paired: B sees %d models on A, A's first person %d models", mB, mA))
			end
			if not okW then
				table.insert(bad, want)
			end
			L("f.look " .. want .. " B sees: " .. string.sub(seen, 1, 900))
			L("f.look " .. want .. " A's first person: " .. string.sub(own, 1, 900))
		end
		check("f.look.held", #bad == 0, string.format("%d weapons at their stars held by A: B's model and A's first-person model are the WeaponsV3 mesh of that star (TierMesh <id>_t<stars>), no tiled Wood/Metal, no part trims; failing: [%s] (lines f.look)",
			#LOOK_SET, table.concat(bad, ",")))
		-- on the ground: a 5* Longsword and a 1* Hatchet at B's feet, as LootService drops them
		local loot = req(Services, "LootService")
		local _, rb = parts(B)
		local _, ra = parts(A)
		if loot and rb and ra then
			local mid = (ra.Position + rb.Position) / 2
			pcall(loot.spawnGroundItem, "sword", 1, mid + Vector3.new(0, 1, 1.5), Vector3.zero, 5)
			pcall(loot.spawnGroundItem, "hatchet", 1, mid + Vector3.new(0, 1, -1.5), Vector3.zero, 1)
			task.wait(1.5)
			call(B, "face", pt(mid - Vector3.new(0, 2.5, 0)))
			task.wait(0.4)
			L("SHOT f_look_ground")
			local s = tostring(call(B, "probe", { kind = "worldlook", near = pt(mid), radius = 6 }))
			check("f.look.ground", goodLook(string.match(s, "GroundItem sword.-%]") or "", "sword_t5") and goodLook(string.match(s, "GroundItem hatchet.-%]") or "", "hatchet_t1"),
				"a 5* Longsword and a 1* Hatchet on the ground as B's client draws them: " .. string.sub(s, 1, 1500))
			task.wait(1.0)
			for _, m in ipairs(CollectionService:GetTagged("GroundItem")) do
				if m:IsA("Model") and (m:GetPivot().Position - mid).Magnitude < 8 then
					m:Destroy()
				end
			end
		end
	end

	-- the newest world copy of a thrown itemId since `afterId`
	local function thrownModel(itemId: string, afterId: number): Model?
		local best, bestId = nil, afterId
		for _, m in ipairs(CollectionService:GetTagged("WorldProjectile")) do
			local id = tonumber(m:GetAttribute("WorldId")) or 0
			if m:IsA("Model") and m:GetAttribute("ItemId") == itemId and id > bestId then
				best, bestId = m, id
			end
		end
		return best
	end
	local function maxWorldId(): number
		local n = 0
		for _, m in ipairs(CollectionService:GetTagged("WorldProjectile")) do
			n = math.max(n, tonumber(m:GetAttribute("WorldId")) or 0)
		end
		return n
	end
	local function throwSeq(aim: { [string]: number }, slot: number?): { any }
		return { { "select", slot }, { "wait", 0.9 }, { "face", aim }, { "aim", true }, { "wait", 0.35 }, { "face", aim }, { "down" }, { "wait", 0.7 }, { "up" }, { "wait", 0.2 },
			{ "aim", false }, { "wait", 2.4 } }
	end
	-- A throws `itemId` at `stars` into the ground (or a tree trunk); B sees it fly at A's stars; it sticks; B takes it
	-- with E and has it at A's stars
	local function fThrowPick(itemId: string, stars: number, into: string)
		Inv.clear(A)
		Inv.give(A, itemId, 1, stars)
		Inv.clear(B)
		setHealth(A)
		setHealth(B)
		task.wait(0.5)
		local label = itemId .. stars .. "_" .. into
		local aim: Vector3? = nil
		local trunkName = "-"
		local trunkAt: Vector3? = nil
		if into == "tree" then
			-- the nearest climbable trunk to the duel base: A stands 9 studs from it
			local base = ctx.duelLine()
			local best, bestD = nil, 2500 -- (the nearest standing trunk anywhere on the map; A and B are stood beside it)
			for _, t in ipairs(CollectionService:GetTagged("Climbable")) do
				if t:IsA("BasePart") and base and t:IsDescendantOf(workspace) then
					local d = flatDist(t.Position, base)
					if d < bestD then
						best, bestD = t, d
					end
				end
			end
			if not best then
				check("f.throw." .. label, false, "no climbable trunk in the workspace")
				return
			end
			trunkName = best:GetFullName() .. " " .. best.Material.Name
			-- (the trunk's own foot: a ray from above would land on the canopy)
			local _, ext = best.CFrame:ToObjectSpace(best.CFrame), best.Size
			local foot = Vector3.new(best.Position.X, best.Position.Y - math.max(ext.X, ext.Y, ext.Z) / 2, best.Position.Z)
			trunkName ..= string.format(" foot %s size %s", tostring(foot), tostring(best.Size))
			trunkAt = foot
			local away = Vector3.new(1, 0, 0)
			standAt(A, foot.X + away.X * 9, foot.Z + away.Z * 9, foot)
			standAt(B, foot.X + away.X * 6 + 6, foot.Z - 6, foot)
			aim = foot + Vector3.new(0, 3.2, 0)
		else
			L(duel(A, B, 10))
			local _, dir = ctx.duelLine()
			local _, ra = parts(A)
			if not ra then
				return
			end
			local side = Vector3.new(-dir.Z, 0, dir.X)
			local tp = ra.Position + side * 9
			local g = groundAt(tp.X, ra.Position.Y, tp.Z)
			aim = if g then g else tp - Vector3.new(0, 3, 0)
		end
		task.wait(0.6)
		local w0, mA, mB = maxWorldId(), mark(A), mark(B)
		local slot = slotOf(A, itemId)
		task.delay(1.35, L, "SHOT f_throw_" .. label .. "_fly")
		call(A, "seq", throwSeq(pt(aim :: Vector3), slot), 12)
		local m: Model? = nil
		local t0 = os.clock()
		repeat
			m = thrownModel(itemId, w0)
			task.wait(0.1)
		until (m and CollectionService:HasTag(m, "LooseProjectile")) or os.clock() - t0 > 4
		local flyB = linesWith(B, mB, "FLY ")
		local flyEndB = linesWith(B, mB, "FLY-END " .. itemId)
		local flyLook = ""
		for _, l in ipairs(flyB) do
			if string.find(l, "item=" .. itemId, 1, true) then
				flyLook = l
				break
			end
		end
		if not m then
			check("f.throw." .. label, false, string.format("A threw %s %d* at %s: no world copy appeared; A's inventory %s; B's flight lines %s", itemId, stars, into,
				invLine(A), table.concat(flyB, " | ")))
			return
		end
		local pv = m:GetPivot()
		local g = groundAt(pv.Position.X, pv.Position.Y + 2, pv.Position.Z)
		local embed = if g then g.Y - lowestY(m) else 0
		local loose = CollectionService:HasTag(m, "LooseProjectile")
		call(B, "face", pt(pv.Position))
		call(A, "face", pt(pv.Position))
		task.wait(0.3)
		L("SHOT f_throw_" .. label .. "_stuck")
		task.wait(0.8)
		-- what B's client draws of the landed copy
		local bLook = tostring(call(B, "probe", { kind = "worldlook", near = pt(pv.Position), radius = 4, item = itemId }))
		if trunkAt then
			-- from the weapon's balance point toward the trunk's axis: the first surface, and the first one you can see
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local skip = { m }
			params.FilterDescendantsInstances = skip
			local to = Vector3.new(trunkAt.X - pv.Position.X, 0, trunkAt.Z - pv.Position.Z)
			local hits = {}
			for _ = 1, 4 do
				local r = workspace:Raycast(pv.Position, to.Unit * 8, params)
				if not r then
					break
				end
				table.insert(hits, string.format("%s %s transp=%.2f at %.2f", r.Instance.Name, r.Instance.ClassName, r.Instance.Transparency, (r.Position - pv.Position).Magnitude))
				if r.Instance.Transparency < 0.99 then
					break
				end
				table.insert(skip, r.Instance)
				params.FilterDescendantsInstances = skip
			end
			L("f.throw " .. label .. " surfaces from the balance point toward the trunk: " .. table.concat(hits, " ; "))
		end
		check("f.throw." .. label .. ".flight", goodLook(flyLook, itemId .. "_t" .. stars) and #flyEndB >= 1, string.format(
			"A threw its %s %d* (%s): B's client flew %s | %s (Studio windows draw at about 15 fps, so the per-frame turn aliases)", itemId, stars, trunkName,
			flyLook, table.concat(flyEndB, " ")))
		check("f.throw." .. label .. ".stuck", loose and tonumber(m:GetAttribute("Stars")) == stars and goodLook(bLook, itemId .. "_t" .. stars), string.format(
			"server: the world copy at %s (%s), Stars=%s, loose=%s, look %s up %s, lowest point %.2f studs into the ground under it (an edge or point in: > 0; flat on top: about 0) | B draws %s",
			tostring(pv.Position), if trunkAt then string.format("%.2f studs from the trunk's axis, %.2f above its foot", flatDist(pv.Position, trunkAt), pv.Position.Y - trunkAt.Y) else "ground", tostring(m:GetAttribute("Stars")), tostring(loose), tostring(pv.LookVector), tostring(pv.UpVector), embed, string.sub(bLook, 1, 700)))
		-- B walks up to it and takes it with E
		local _, ra = parts(A)
		local from = if ra then ra.Position else pv.Position + Vector3.new(4, 0, 0)
		local toward = Vector3.new(from.X - pv.Position.X, 0, from.Z - pv.Position.Z)
		toward = if toward.Magnitude > 0.1 then toward.Unit else Vector3.new(1, 0, 0)
		if trunkAt and ra then
			-- (by a tree a ray from above lands on a branch: B takes A's spot, about 5 studs out, and A steps aside)
			local spot = ra.Position
			standAt(A, spot.X, spot.Z + 6, pv.Position, spot.Y)
			standAt(B, spot.X, spot.Z, pv.Position, spot.Y - 3)
		else
			standAt(B, pv.Position.X + toward.X * 3, pv.Position.Z + toward.Z * 3, pv.Position, pv.Position.Y)
		end
		task.wait(0.6)
		call(B, "face", pt(pv.Position))
		task.wait(0.5)
		local took = tostring(call(B, "probe", { kind = "take", wait = 3 }, 8))
		task.wait(1.0)
		local bStars = invStars(B, itemId)
		local bSlot = slotOf(B, itemId)
		local heldLook = "-"
		if bSlot then
			call(B, "seq", { { "select", bSlot }, { "wait", 1.0 } }, 4)
			heldLook = tostring(call(A, "probe", { kind = "look", target = B.Name }))
		end
		check("f.throw." .. label .. ".takenByB", bStars == tostring(stars) and m.Parent == nil and goodLook(heldLook, itemId .. "_t" .. stars), string.format(
			"B at 3 studs, facing it: %s; B's inventory %s (%s stars %s); the world copy %s; A's inventory %s; B's hand as A sees it %s", took, invLine(B), itemId,
			bStars, if m.Parent then "still there" else "gone", invLine(A), string.sub(heldLook, 1, 600)))
	end

	-- a standing Longsword chain on a B that is not held in place: every hit connects, the last pushes about 4 studs
	local function fChainFree()
		Inv.clear(A)
		Inv.give(A, "sword", 1, 1)
		task.wait(0.5)
		local sw = slotOf(A, "sword")
		setHealth(A)
		setHealth(B)
		L(duel(A, B, 4))
		fFace()
		call(A, "seq", { { "select", sw }, { "wait", 0.8 } }, 4)
		task.wait(1.0)
		local n0 = #resolves
		local rows, running, seen = {}, true, n0
		task.spawn(function()
			while running do
				while #resolves > seen do
					seen += 1
					local r = resolves[seen]
					local _, ra = parts(A)
					local _, rb = parts(B)
					local d0 = if ra and rb then flatDist(ra.Position, rb.Position) else -1
					local row = { move = r.move, result = r.result, dealt = r.dealt, d0 = d0, d1 = -1 }
					table.insert(rows, row)
					task.delay(0.5, function()
						local _, ra2 = parts(A)
						local _, rb2 = parts(B)
						row.d1 = if ra2 and rb2 then flatDist(ra2.Position, rb2.Position) else -1
					end)
				end
				task.wait(0.02)
			end
		end)
		call(A, "seq", { { "face", B.Name }, { "wait", 0.2 }, { "click" }, { "wait", 0.62 }, { "click" }, { "wait", 0.62 }, { "click" }, { "wait", 0.62 }, { "click" },
			{ "wait", 1.4 } }, 15)
		task.wait(0.6)
		running = false
		local moves, desc, pushes = {}, {}, {}
		for _, r in ipairs(rows) do
			table.insert(moves, r.move .. ":" .. r.result)
			table.insert(pushes, r.d1 - r.d0)
			table.insert(desc, string.format("%s %s %.1f gap %.2f -> %.2f (push %.2f)", r.move, r.result, r.dealt, r.d0, r.d1, r.d1 - r.d0))
		end
		local last = pushes[4] or 0
		local earlyMax = math.max(pushes[1] or 9, pushes[2] or 9, pushes[3] or 9)
		check("f.chainFree", table.concat(moves, ",") == "L1:Hit,L2:Hit,L3:Hit,L4:Hit" and earlyMax < 1.5 and last > 2.5 and last < 6.5, string.format(
			"A's Longsword 1* chain of 4 taps 0.62 s apart at B 4 studs away, nobody moves forward, B not held: %s (early pushes under 1.5, last 2.5 to 6.5 studs)",
			table.concat(desc, "; ")))
	end

	-- no folded body after a heavy or a Whirl: every joint of B on A's screen, and of a game training dummy
	local function jointCheck(id: string, viewer: Player, target: string, what: string)
		local j = tostring(call(viewer, "probe", { kind = "joints", target = target }))
		local deg = tonumber(string.match(j, "maxDeg=([%d%.]+)")) or 999
		check("f.fold." .. id, deg < 50, string.format("%s, as %s's client draws it: %s (folded reads 100+ degrees)", what, viewer.Name, j))
	end
	local function fDummyFold()
		local template = ServerStorage:FindFirstChild("Dev") and ServerStorage.Dev:FindFirstChild("TrainingDummy")
		if not template then
			check("f.fold.dummy", false, "no ServerStorage.Dev.TrainingDummy")
			return
		end
		Inv.clear(A)
		Inv.give(A, "hatchet", 1, 4)
		Inv.give(A, "paired_blades", 1, 5)
		task.wait(0.5)
		local base, dir = ctx.duelLine()
		if not base then
			return
		end
		L(duel(A, B, 25)) -- (B out of the way)
		local _, ra = parts(A)
		local at = (if ra then ra.Position else base) + dir * 4
		local g = groundAt(at.X, at.Y, at.Z)
		local dm = template:Clone()
		dm.Name = "MPT_DummyF"
		dm:PivotTo(CFrame.lookAt(Vector3.new(at.X, (if g then g.Y else at.Y - 3) + 3, at.Z), Vector3.new(base.X, (if g then g.Y else at.Y - 3) + 3, base.Z)))
		local hum = dm:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.MaxHealth = 2000
			hum.Health = 2000
		end
		CollectionService:AddTag(dm, "TrainingDummy")
		dm.Parent = workspace
		task.wait(1.0)
		local n0 = #resolves
		local dpt = pt(Vector3.new(at.X, (if g then g.Y else at.Y - 3) + 3, at.Z))
		call(A, "seq", { { "select", slotOf(A, "hatchet") }, { "wait", 0.8 }, { "face", dpt } }, 4)
		call(A, "skill", { slot = "weapon" })
		task.wait(1.6)
		call(A, "seq", { { "select", slotOf(A, "paired_blades") }, { "wait", 0.8 }, { "face", dpt }, { "click" }, { "wait", 0.45 }, { "click" }, { "wait", 0.45 },
			{ "click" }, { "wait", 0.6 }, { "down" }, { "wait", 0.9 }, { "up" }, { "wait", 0.4 } }, 12)
		local list = resolvesFrom(n0, A.Name)
		task.wait(4.0)
		L("SHOT f_fold_dummy")
		jointCheck("dummy", A, "MPT_DummyF", string.format("a game training dummy 4.0 s after A's Whirl (Hatchet 4*), a Paired Blades 5* chain and a heavy %s", resStr(list)))
		dm:Destroy()
	end

	-- a weapon thrown into B stays in B, and falls out when B dies (the round's end, run in the train step)
	local function stuckInB(): Model?
		Inv.clear(A)
		Inv.give(A, "sword", 1, 3)
		task.wait(0.5)
		L(duel(A, B, 9))
		fFace()
		local w0 = maxWorldId()
		local _, rb = parts(B)
		call(A, "seq", throwSeq(pt(if rb then rb.Position + Vector3.new(0, 0.6, 0) else Vector3.zero), slotOf(A, "sword")), 12)
		local m = thrownModel("sword", w0)
		L(string.format("f.stuck: the thrown Longsword 3* %s host=%s hostPart=%s; B's health %.1f", if m then "is in the world" else "not found",
			tostring(m and m:GetAttribute("Host")), tostring(m and m:GetAttribute("HostPart")), health(B)))
		return m
	end

	local fRoundMarks: { [Player]: number } = {}

	local function batchF()
		if Moves and Moves.skills then
			Moves.skills.LockedFirst = 0 -- (test: skills open at once instead of 45 s into the round)
		end
		fTrails()
		task.wait(4.0) -- (the launch ends and the load-in plays)
		fLoadIn(fRoundMarks)
		setupDuel()
		fGive()
		-- (test: 400 health each, so a slow test window that turns a tap into a heavy cannot end a player mid-batch; the
		-- damage checks read what the server resolved)
		for _, p in ipairs({ A, B }) do
			local hum = parts(p)
			if hum then
				hum.MaxHealth = 400
				hum.Health = 400
			end
		end
		local steps = {
			{ "chain", fChain },
			{ "heavy", fHeavy },
			{ "parry", function()
				local okP, okC = fParry(1, 0.05)
				if okP and not okC then
					fParry(2, 0.15)
					fParry(3, 0.3)
				else
					fParry(2, 0.1)
				end
			end },
			{ "dodge", fDodge },
			{ "skills", fSkills },
			{ "shots", fShots },
			{ "trails", fOthersTrails },
			{ "paired", fPaired },
			{ "cheats", fCheats },
			{ "moving", movingChecks },
			{ "ricochet", fRicochet }, -- (run with fspecA = "Throwing")
			{ "pierce", fPierce }, -- (run with fspecB = "Bow")
			{ "chainfree", fChainFree },
			{ "fold", fDummyFold },
			{ "looks", fLooks },
			{ "throwaxe", function()
				fThrowPick("hatchet", 4, "ground")
			end },
			{ "throwsword", function()
				fThrowPick("sword", 5, "ground")
			end },
			{ "throwtree", function()
				fThrowPick("twin_axe", 3, "tree")
			end },
			{ "throwtreesword", function()
				fThrowPick("sword", 4, "tree")
			end },
			{ "train", function()
				-- the round ends (A defeats B): B appears in the train first, then A at the round's end, a few studs from B
				local mA, mB = mark(A), mark(B)
				for _, p in ipairs({ A, B }) do
					local hum = parts(p)
					if hum then
						hum.MaxHealth = 100
						hum.Health = 100
					end
				end
				-- a Longsword thrown into B first: it falls out when B dies
				local okS, stuck = pcall(stuckInB)
				local hostBefore = if okS and stuck then stuck:GetAttribute("Host") else nil
				Inv.give(A, "sword", 1, 1)
				task.wait(0.4)
				ctx.killB("f")
				if okS and stuck then
					task.wait(1.5)
					local pv = stuck:GetPivot()
					local g = groundAt(pv.Position.X, pv.Position.Y + 2, pv.Position.Z)
					check("f.throw.fallsOutOnDeath", hostBefore ~= nil and stuck:GetAttribute("Host") == nil and stuck.Parent ~= nil, string.format(
						"A's Longsword 3* thrown into B (Host=%s before); 1.5 s after B's death: Host=%s, still in the world=%s, loose=%s, lowest point %.2f above the ground, Stars=%s",
						tostring(hostBefore), tostring(stuck:GetAttribute("Host")), tostring(stuck.Parent ~= nil), tostring(CollectionService:HasTag(stuck, "LooseProjectile")),
						if g then lowestY(stuck) - g.Y else -99, tostring(stuck:GetAttribute("Stars"))))
				else
					check("f.throw.fallsOutOnDeath", false, "the throw into B did not leave a world copy: " .. tostring(stuck))
				end
				ctx.backToLobby("f", { A, B })
				task.wait(3.0)
				local function played(lines: { string }): boolean
					for _, l in ipairs(lines) do
						if string.find(l, "played=true", 1, true) then
							return true
						end
					end
					return false
				end
				local bSeesA, aSeesB = linesWith(B, mB, "LOADIN " .. A.Name), linesWith(A, mA, "LOADIN " .. B.Name)
				local aOwn, bOwn = linesWith(A, mA, "LOADIN " .. A.Name), linesWith(B, mB, "LOADIN " .. B.Name)
				local _, ra = parts(A)
				local _, rb = parts(B)
				check("f.loadIn.train", played(bSeesA) and played(aOwn) and played(bOwn), string.format(
					"back in the train (A and B %.1f studs apart): B's client %s | %s; A's client %s | %s", if ra and rb then (ra.Position - rb.Position).Magnitude else -1,
					table.concat(bOwn, " "), table.concat(bSeesA, " "), table.concat(aOwn, " "), table.concat(aSeesB, " ")))
			end },
		}
		local only = if type(ARGS.fsteps) == "string" then "," .. ARGS.fsteps .. "," else nil
		for _, s in ipairs(steps) do
			if only and not string.find(only, "," .. s[1] .. ",", 1, true) then
				continue
			end
			if not only and (s[1] == "ricochet" or s[1] == "pierce") then
				continue -- (they need other Specialties: a run of their own)
			end
			local ok, err = pcall(s[2])
			if not ok then
				L("DRIVER ERROR in " .. s[1] .. ": " .. string.gsub(tostring(err), "\n", " | "))
			end
		end
		L("refusals at the end: " .. refusals() .. " | skill refusals: " .. skillRefusals())
	end
	return {
		lobby = function()
			fLobby()
			for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
				fRoundMarks[p] = mark(p)
			end
		end,
		run = batchF,
	}
end
