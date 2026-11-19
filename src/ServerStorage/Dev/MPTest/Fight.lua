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
		for _, viewer in ipairs({ A, B }) do
			local lines = linesWith(viewer, from[viewer] or 0, "LOADIN ")
			local who = {}
			for _, line in ipairs(lines) do
				local name, played = string.match(line, "LOADIN (%S+) played=(%S+)")
				if name and played == "true" then
					who[name] = true
				end
			end
			ok = ok and who[A.Name] == true and who[B.Name] == true
			table.insert(out, string.format("%s's client: %s", viewer.Name, table.concat(lines, " | ")))
		end
		check("f.loadIn.both", ok, "the load-in swirl at the arena on each client: " .. table.concat(out, " || "))
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
				ctx.killB("f")
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
			fRoundMarks[A] = mark(A)
			fRoundMarks[B] = mark(B)
		end,
		run = batchF,
	}
end
