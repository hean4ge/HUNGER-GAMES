-- MPT_Polish (mp-polish, 20 Nov 2026): batch P of the MPTest driver. The owner's list of 20 Nov with two or three real
-- players: the launch in first person all the way (red room, glass case, rise) and the sun's glare at the hand-off on
-- every screen; the music cues on every client through the round; a sprint slide on flat ground, down the 19 degree hill
-- and up it, as the slider and the other player see it; the border wall (honeycomb or its outline) on every screen,
-- near and moving; the rolling hills (walks over the meadow with nobody stuck, the loot markers and crates on the real
-- ground, a crate and the stream walked to, a sip). Test only: a child of MPT_Driver; the client half is
-- MPT_PolishClient (the bots' "pmod" order).
return function(ctx: { [string]: any })
	local L, check, call, waitFor, phase, shot, fmt, v3 = ctx.L, ctx.check, ctx.call, ctx.waitFor, ctx.phase, ctx.shot, ctx.fmt, ctx.v3
	local A: Player, B: Player, P3: Player? = ctx.A, ctx.B, ctx.P3
	local parts, flatDist, arenaCenter = ctx.parts, ctx.flatDist, ctx.arenaCenter
	local GS: Instance = ctx.GS
	local PS = ctx.PS
	local Players = game:GetService("Players")
	local RS = game:GetService("ReplicatedStorage")
	local ServerStorage = game:GetService("ServerStorage")
	local CollectionService = game:GetService("CollectionService")
	local HttpService = game:GetService("HttpService")
	local Config = require(ctx.Shared:WaitForChild("Config"))

	local M = {}
	local everyone = { A, B }
	if P3 then
		table.insert(everyone, P3)
	end

	local function pmod(p: Player?, op: string, arg: any, timeout: number?): any
		return call(p, "pmod", { op = op, arg = arg }, timeout or 25)
	end
	local function all(list: { Player }, op: string, arg: any, timeout: number?): { [Player]: any }
		local out, left = {}, #list
		for _, p in ipairs(list) do
			task.spawn(function()
				out[p] = pmod(p, op, arg, timeout)
				left -= 1
			end)
		end
		waitFor(function()
			return left <= 0
		end, (timeout or 25) + 2)
		return out
	end
	local function decode(s: any): any
		if type(s) ~= "string" then
			return nil
		end
		local ok, v = pcall(HttpService.JSONDecode, HttpService, s)
		return if ok then v else nil
	end

	-- the ground: terrain only (never a tree's crown)
	local terrainOnly = RaycastParams.new()
	terrainOnly.FilterType = Enum.RaycastFilterType.Include
	terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
	terrainOnly.IgnoreWater = true
	-- the solid world under a point: terrain and built parts (the Horn's floor), not characters or loot
	local function solidY(x: number, z: number, from: number, skip: Instance?): number?
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		local loot = workspace:FindFirstChild("Arena") and workspace.Arena:FindFirstChild("Loot")
		if loot then
			table.insert(ignore, loot)
		end
		if skip then
			table.insert(ignore, skip)
		end
		params.FilterDescendantsInstances = ignore
		params.IgnoreWater = true
		params.RespectCanCollide = true
		local hit = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -200, 0), params)
		return hit and hit.Position.Y
	end
	local function groundY(x: number, z: number, from: number?): number?
		local hit = workspace:Raycast(Vector3.new(x, from or 900, z), Vector3.new(0, -((from or 900) + 300), 0), terrainOnly)
		return hit and hit.Position.Y
	end
	local function standOn(p: Player, x: number, z: number, lookAt: Vector3): Vector3?
		local hum, root = parts(p)
		local gy = groundY(x, z)
		if not (hum and root and gy) then
			return nil
		end
		local y = gy + hum.HipHeight + root.Size.Y / 2 + 0.15
		local pos = Vector3.new(x, y, z)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(pos, Vector3.new(lookAt.X, y, lookAt.Z))
		return pos
	end
	-- the slope along a line: degrees between each pair of points 4 studs apart, and the overall drop
	local function profile(a: Vector3, b: Vector3, step: number?): (string, number, number)
		local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local n = math.max(1, math.floor(d.Magnitude / (step or 4)))
		local ys, degs, maxDeg = {}, {}, 0
		for i = 0, n do
			local p = a + d * (i / n)
			ys[i] = groundY(p.X, p.Z) or 0
			if i > 0 then
				local deg = math.deg(math.atan2(ys[i - 1] - ys[i], d.Magnitude / n))
				table.insert(degs, string.format("%.0f", deg))
				maxDeg = math.max(maxDeg, math.abs(deg))
			end
		end
		return table.concat(degs, ","), ys[0] - ys[n], maxDeg
	end

	function M.lobby()
		-- the border's first stage moves late enough for the slides and walks, early enough to hear its cue: 140 s after
		-- the horn at timeScale 4 (night comes about 113 s after the horn: DaySchedule 19.0 h at ~452 round seconds)
		local stages = Config.Border.Stages
		if type(stages) == "table" and stages[1] then
			stages[1] = { at = 560, over = 255, radius = 1200 }
			if stages[2] and (tonumber(stages[2].at) or 0) < 830 then
				stages[2] = { at = 830, over = 215, radius = 700 } -- (after stage 1 ends, so ArenaService doesn't warn)
			end
		end
		L("POLISH border stages now " .. fmt(Config.Border.Stages) .. " timeScale=" .. tostring(Config.Round.StudioTimeScale))
		-- pictures of the launch on every window: red room, case, rise, the flood, just after the hand-off
		task.spawn(function()
			if not waitFor(function()
				return phase() == "Countdown"
			end, 200) then
				return
			end
			local t0 = os.clock()
			for _, at in ipairs({ { 2.2, "p_launch_1red" }, { 6.6, "p_launch_2case" }, { 11.0, "p_launch_3rise" }, { 14.6, "p_launch_4flood" }, { 15.5, "p_launch_5handoff" }, { 16.6, "p_launch_6glare" } }) do
				local wait = at[1] - (os.clock() - t0)
				if wait > 0 then
					task.wait(wait)
				end
				L("SHOT " .. at[2])
			end
		end)
		local r = all(everyone, "music.start", nil, 5)
		local r2 = all(everyone, "launch.start", nil, 5)
		L("POLISH watchers started: music " .. fmt(r) .. " launch " .. fmt(r2))
	end

	-- the launch on every screen --------------------------------------------------------------------------------------------
	local function launchChecks()
		task.wait(3.5) -- the glare's fall (up to 2 s) is over and reported
		local reps = all(everyone, "launch.report", nil, 8)
		local cut = tostring(GS:GetAttribute("LaunchCut"))
		local fpOk, armsOk, coverOk, handOk, glareOk, stagesOk = true, true, true, true, true, true
		local dFp, dArms, dCover, dHand, dGlare, dStages = {}, {}, {}, {}, {}, {}
		for _, p in ipairs(everyone) do
			local r = reps[p] or {}
			L("LAUNCH report " .. p.Name .. " " .. fmt(r))
			local st = decode(r.stats) or {}
			local gl = decode(r.glare) or {}
			-- first person: the eye stays on the axis of the stand-in it rides with (your own, never drawn) every frame
			local fp = r.shotSeen == true and (tonumber(r.frames) or 0) > 20 and (tonumber(r.maxFlat) or 99) < 0.6 and (tonumber(r.noStandIn) or 99) == 0
				and (tonumber(r.ownDrawnNear) or 99) == 0 and (r.camTypes and r.camTypes.Scriptable or 0) == r.frames
			fpOk = fpOk and fp
			table.insert(dFp, string.format("%s: %s frames, camera %s, eye to the nearest stand-in's axis mean %.2f / max %.2f studs, %.2f..%.2f above its root, frames with no stand-in %s, own body drawn at the eye %s, fov %.1f..%.1f",
				p.Name, tostring(r.frames), fmt(r.camTypes), tonumber(r.meanFlat) or -1, tonumber(r.maxFlat) or -1, tonumber(r.upMin) or 0, tonumber(r.upMax) or 0,
				tostring(r.noStandIn), tostring(r.ownDrawnNear), tonumber(r.fovMin) or 0, tonumber(r.fovMax) or 0))
			local arms = (tonumber(r.armsFrames) or 0) > 0.5 * (tonumber(r.frames) or 1)
			armsOk = armsOk and arms
			table.insert(dArms, string.format("%s: arms in front of the eye in %s of %s frames (up to %s parts)", p.Name, tostring(r.armsFrames), tostring(r.frames), tostring(r.armsMax)))
			local cover = (tonumber(r.coverMax) or 0) >= 0.6 and (tonumber(r.coverMax) or 1) <= 0.951 and (tonumber(r.coverAfterMax) or 1) <= 0.951
			coverOk = coverOk and cover
			table.insert(dCover, string.format("%s: cover peak %.3f in the shot, %.3f after, frames over 0.95: %s; exposure up to %.2f (after the cut %.2f); after the cut: %s", p.Name,
				tonumber(r.coverMax) or -1, tonumber(r.coverAfterMax) or -1, tostring(r.coverFrames95), tonumber(r.exposureMax) or -99, tonumber(r.exposureAfterMax) or -99,
				tostring(r.after)))
			local h = r.handoff or {}
			local hand = (tonumber(h.lookJumpDeg) or 99) < 6 and math.abs((tonumber(h.fovShot) or 0) - (tonumber(h.fovNow) or 99)) < 3 and (tonumber(h.camToHead) or 99) < 2.5
			handOk = handOk and hand
			table.insert(dHand, string.format("%s: look jumped %s deg at the cut (yaw %s -> %s), fov %s -> %s, camera %s studs from own head, %s", p.Name, tostring(h.lookJumpDeg),
				tostring(h.yawShot), tostring(h.yawNow), tostring(h.fovShot), tostring(h.fovNow), tostring(h.camToHead), tostring(h.camType)))
			local glare = type(gl) == "table" and (tonumber(gl.seconds) or 0) > 0.8 and (tonumber(gl.seconds) or 9) < 3
			glareOk = glareOk and glare
			table.insert(dGlare, p.Name .. ": " .. tostring(r.glare))
			local hasStages = st.Red ~= nil and st.Rise ~= nil and (cut ~= "Full" or st.Cases ~= nil) and st.reason == "handoff"
			stagesOk = stagesOk and hasStages
			table.insert(dStages, p.Name .. ": " .. tostring(r.stats) .. " detailTier=" .. tostring(r.detailTier) .. " reducedMotion=" .. tostring(r.reducedMotion))
		end
		check("p.launch.cut", cut == "Full", "LaunchCut=" .. cut)
		check("p.launch.stages", stagesOk, table.concat(dStages, " | "))
		check("p.launch.firstPerson", fpOk, table.concat(dFp, " | "))
		check("p.launch.arms", armsOk, table.concat(dArms, " | "))
		check("p.launch.coverNeverWhite", coverOk, table.concat(dCover, " | "))
		check("p.launch.handoffNoJump", handOk, table.concat(dHand, " | "))
		check("p.launch.glare", glareOk, table.concat(dGlare, " | "))
	end

	-- the slide --------------------------------------------------------------------------------------------------------------
	local SLOPE_TOP = Vector3.new(104, 0, -626) -- the real 19 degree hill (slide-physics: (104, 94, -591), falling +Z)
	local function slideChecks()
		local results = {}
		local prof, drop, maxDeg = profile(Vector3.new(104, 0, -640), Vector3.new(104, 0, -500), 4)
		L(string.format("SLOPE profile x=104 z -640..-500 (deg per 4 studs, + = down toward +Z): %s; drop %.1f, steepest %.0f", prof, drop, maxDeg))
		-- a flat run: the meadow inside the plinth ring, the stretch with the least height change over 80 studs
		local center = arenaCenter()
		local bestFlat, bestSpread = nil, math.huge
		for _, ang in ipairs({ 20, 65, 110, 155, 200, 245, 290, 335 }) do
			for _, rad in ipairs({ 140, 200, 260 }) do
				local a = center + Vector3.new(math.cos(math.rad(ang)) * rad, 0, math.sin(math.rad(ang)) * rad)
				local dir = Vector3.new(math.cos(math.rad(ang + 90)), 0, math.sin(math.rad(ang + 90)))
				local lo, hi, okLine = math.huge, -math.huge, true
				for i = 0, 20 do
					local q = a + dir * (i * 4)
					local y = groundY(q.X, q.Z)
					if not y then
						okLine = false
						break
					end
					lo, hi = math.min(lo, y), math.max(hi, y)
				end
				if okLine and hi - lo < bestSpread then
					bestSpread, bestFlat = hi - lo, { a = a, dir = dir }
				end
			end
		end
		local cases = {
			{ name = "flat", from = bestFlat and bestFlat.a, toward = bestFlat and (bestFlat.a + bestFlat.dir * 90) },
			{ name = "downhill19", from = SLOPE_TOP, toward = Vector3.new(104, 0, -480) },
			{ name = "uphill19", from = Vector3.new(104, 0, -520), toward = Vector3.new(104, 0, -700) },
		}
		for _, c in ipairs(cases) do
			if not c.from then
				check("p.slide." .. c.name, false, "no place found for it")
				continue
			end
			local start = standOn(A, c.from.X, c.from.Z, c.toward)
			-- B stands 14 studs to the side of where the slide begins, watching
			local side = (c.toward - c.from)
			side = Vector3.new(-side.Z, 0, side.X).Unit
			local mid = c.from + (c.toward - c.from).Unit * 34
			standOn(B, mid.X + side.X * 14, mid.Z + side.Z * 14, mid)
			task.wait(2.0)
			local gy = groundY(c.toward.X, c.toward.Z) or (start and start.Y or 0)
			local watch: any = nil
			task.spawn(function()
				watch = pmod(B, "watchSlide", { target = A.Name, seconds = 7 }, 12)
			end)
			call(B, "track", { target = A.Name, seconds = 8 })
			if c.name == "downhill19" then
				task.delay(2.2, function()
					shot("p_slide_watch_" .. c.name, 0.2)
				end)
			end
			local r = pmod(A, "slide", { face = { x = c.toward.X, y = gy + 1, z = c.toward.Z }, run = 1.4, sprint = true }, 15) or {}
			waitFor(function()
				return watch ~= nil
			end, 8)
			results[c.name] = r
			local w = watch or {}
			L(string.format("SLIDE %s: %s | B saw %s", c.name, fmt(r), fmt(w)))
			check("p.slide." .. c.name, r.slid == true and r.fresh == true and (tonumber(r.dist) or 0) > 2,
				string.format("A from %s: ran %.1f studs/s (state %s), slid %.2f s / %.1f studs (entry %.1f, top %.1f, drop %.1f, slope up to %.0f deg, %s); B saw Stance=Slide in %s of %s samples, spray in %s (chip rate up to %.0f)",
					if start then v3(start) else "?", tonumber(r.runMax) or 0, tostring(r.moveStateAtCrouch), tonumber(r.time) or 0, tonumber(r.dist) or 0,
					tonumber(r.entry) or 0, tonumber(r.maxSpeed) or 0, tonumber(r.drop) or 0, tonumber(r.slopeDeg) or 0, tostring(r.material), tostring(w.stanceSlide),
					tostring(w.samples), tostring(w.sprayFrames), tonumber(w.rateMax) or 0))
			if c.name == "downhill19" then
				check("p.slide.seenByOther", (tonumber(w.stanceSlide) or 0) >= 3 and (tonumber(w.sprayFrames) or 0) >= 2,
					string.format("B's screen: A's Stance Slide in %s samples, A's spray in %s samples (0.1 s each)", tostring(w.stanceSlide), tostring(w.sprayFrames)))
			end
			task.wait(0.8)
		end
		local f, d, u = results.flat or {}, results.downhill19 or {}, results.uphill19 or {}
		local fd, dd, ud = tonumber(f.dist) or 0, tonumber(d.dist) or 0, tonumber(u.dist) or 0
		local ft, dt, ut = tonumber(f.time) or 0, tonumber(d.time) or 0, tonumber(u.time) or 0
		check("p.slide.steeperLonger", dd > 1.6 * fd and fd > 1.2 * ud and dt > ft and ft >= ut and fd > 0 and ud > 0,
			string.format("sprint slides on grass: uphill %.2f s / %.1f studs < flat %.2f s / %.1f studs (spread %.1f studs over 80) < down the hill %.2f s / %.1f studs",
				ut, ud, ft, fd, bestSpread, dt, dd))
	end

	-- the hills: walks, loot and water ---------------------------------------------------------------------------------------
	local function hillChecks()
		-- the routes the hills agent named (dips and rises of 5 to 10 studs): A round x 240 z -330, B round x -470 z 60
		local routeA = { { x = 240, z = -330 }, { x = 300, z = -385 }, { x = 245, z = -440 }, { x = 185, z = -385 }, { x = 240, z = -330 } }
		local routeB = { { x = -470, z = 60 }, { x = -520, z = 110 }, { x = -470, z = 160 }, { x = -420, z = 110 }, { x = -470, z = 60 } }
		for name, route in pairs({ A = routeA, B = routeB }) do
			local spread = {}
			for i = 1, #route - 1 do
				local prof, drop, maxDeg = profile(Vector3.new(route[i].x, 0, route[i].z), Vector3.new(route[i + 1].x, 0, route[i + 1].z), 6)
				table.insert(spread, string.format("leg%d steepest %.0f deg drop %.1f", i, maxDeg, drop))
			end
			L("HILLS route " .. name .. ": " .. table.concat(spread, "; "))
		end
		standOn(A, 200, -290, Vector3.new(240, 0, -330))
		standOn(B, -440, 20, Vector3.new(-470, 0, 60))
		task.wait(2.5)
		local wa, wb = nil, nil
		task.spawn(function()
			wa = pmod(A, "walk", { points = routeA, sprint = true, legTime = 20 }, 110)
		end)
		task.spawn(function()
			wb = pmod(B, "walk", { points = routeB, sprint = false, legTime = 25 }, 130)
		end)
		task.delay(6, function()
			shot("p_hills_walk", 0.2)
		end)
		waitFor(function()
			return wa ~= nil and wb ~= nil
		end, 135)
		for name, w in pairs({ A = wa or {}, B = wb or {} }) do
			L("WALK " .. name .. " " .. fmt(w))
			check("p.hills.walk" .. name, (tonumber(w.stuck) or 9) == 0 and (tonumber(w.reached) or 0) == 5,
				string.format("%s over the hills (%s): %s studs, height range %s (%s..%s), stuck windows %s, least progress in any 2 s %s studs, health %s; %s",
					name, if name == "A" then "sprint" else "jog", tostring(w.distance), tostring(w.climb), tostring(w.minH), tostring(w.maxH), tostring(w.stuck),
					tostring(w.worstWindow), tostring(w.health), tostring(w.legs)))
		end
		-- every loot marker and every crate in the world on the real ground
		local data = ServerStorage:FindFirstChild("ArenaData")
		local folder = data and data:FindFirstChild("LootSpawns")
		local n, floating, buried, list = 0, 0, 0, {}
		if folder then
			for _, m in ipairs(folder:GetDescendants()) do
				if m:IsA("BasePart") then
					n += 1
					local p = m.Position
					local top = groundY(p.X, p.Z, p.Y + 60)
					local under = groundY(p.X, p.Z, p.Y + 1)
					local bottom = p.Y - m.Size.Y / 2
					if top and top > bottom + 2.5 then
						-- terrain above the marker: under an overhang (the Peak) or buried
						local beneath = under and bottom - under
						if not (beneath and beneath > -1 and beneath < 3) then
							buried += 1
							if #list < 6 then
								table.insert(list, "buried " .. v3(p) .. string.format(" top %.1f", top))
							end
						end
					elseif under and bottom - under > 3 and bottom - (solidY(p.X, p.Z, p.Y + 0.5) or under) > 3 then
						floating += 1
						if #list < 6 then
							table.insert(list, "floating " .. v3(p) .. string.format(" gap %.1f", bottom - under))
						end
					end
				end
			end
		end
		check("p.hills.lootMarkers", folder ~= nil and n > 400 and floating == 0 and buried <= 3,
			string.format("%d markers; floating over 3 studs: %d, under terrain: %d (3 under the Peak are expected); %s", n, floating, buried, table.concat(list, "; ")))
		local crates, cFloat, cBuried, near, cList = 0, 0, 0, nil, {}
		local _, ra = parts(A)
		for _, prompt in ipairs(CollectionService:GetTagged("LootPrompt")) do
			local holder = prompt.Parent
			local part = if holder and holder:IsA("BasePart") then holder elseif holder and holder:IsA("Attachment") then holder.Parent else nil
			if part and part:IsA("BasePart") and part:IsDescendantOf(workspace) then
				crates += 1
				local p = part.Position
				local under = groundY(p.X, p.Z, p.Y + 1)
				local top = groundY(p.X, p.Z, p.Y + 60)
				if under and p.Y - under > 6 and p.Y - (solidY(p.X, p.Z, p.Y + 1.5, part:FindFirstAncestorOfClass("Model") or part) or under) > 6 then
					cFloat += 1
					local model = part:FindFirstAncestorOfClass("Model")
					table.insert(cList, string.format("%s at %s, %.1f over the ground, anchored=%s, falling %.1f, drop=%s", model and model.Name or part.Name, v3(p), p.Y - under,
						tostring(part.Anchored), -part.AssemblyLinearVelocity.Y, tostring(model and (model:GetAttribute("Dropping") or model:GetAttribute("DropIn")))))
				end
				if top and under and top > p.Y + 4 and math.abs(top - under) > 4 then
					cBuried += 1
				end
				if ra and (near == nil or flatDist(p, ra.Position) < flatDist(near, ra.Position)) and flatDist(p, ra.Position) > 12 then
					near = p
				end
			end
		end
		check("p.hills.crates", crates > 0 and cFloat == 0 and cBuried <= 3,
			string.format("%d loot prompts in the world; over 6 studs above the ground %d, under terrain %d; %s", crates, cFloat, cBuried, table.concat(cList, "; ")))
		-- A walks to the nearest crate from where its walk ended and opens it
		if near and ra then
			L("CRATE walk from " .. v3(ra.Position) .. " to " .. v3(near) .. string.format(" (%.0f studs)", flatDist(ra.Position, near)))
			local w = pmod(A, "walk", { points = { { x = near.X, z = near.Z } }, sprint = true, legTime = 30, within = 5 }, 40) or {}
			local opened = call(A, "prompt", { radius = 10 }, 10)
			check("p.hills.crateReached", (tonumber(w.reached) or 0) == 1 and (tonumber(w.stuck) or 9) == 0,
				string.format("walk %s; prompt: %s", tostring(w.legs), tostring(opened)))
		else
			check("p.hills.crateReached", nil, "no crate found near A")
		end
		-- B walks to the nearest stream point from its walk's end and drinks
		local WP = require(RS.Shared:WaitForChild("WaterPoints"))
		local _, rb = parts(B)
		local point, dist, kind = nil, 0, nil
		if rb then
			point, dist, kind = WP.nearest(rb.Position)
		end
		if point and rb then
			if dist > 90 then
				-- too far for the time: start 40 studs from it on its dry side, toward where B was
				local toward = Vector3.new(rb.Position.X - point.X, 0, rb.Position.Z - point.Z).Unit
				standOn(B, point.X + toward.X * 40, point.Z + toward.Z * 40, point)
				task.wait(2.0)
			end
			PS.addThirst(B, -40)
			local before = tonumber(B:GetAttribute("Thirst")) or -1
			local _, rb2 = parts(B)
			L(string.format("WATER walk B from %s to %s point %s (%.0f studs)", if rb2 then v3(rb2.Position) else "?", tostring(kind), v3(point),
				if rb2 then flatDist(rb2.Position, point) else -1))
			local w = pmod(B, "walk", { points = { { x = point.X, z = point.Z } }, sprint = false, legTime = 30, within = 3.5 }, 40) or {}
			local sips = 0
			for _ = 1, 3 do
				call(B, "fire", { name = "Drink" })
				task.wait(1.0)
				sips += 1
			end
			local after = tonumber(B:GetAttribute("Thirst")) or -1
			check("p.hills.waterReached", (tonumber(w.reached) or 0) == 1 and after > before + 5,
				string.format("B walked to the %s at %s: %s; thirst %.1f -> %.1f after %d sips", tostring(kind), v3(point), tostring(w.legs), before, after, sips))
			shot("p_water", 0.4)
		else
			check("p.hills.waterReached", nil, "no water point")
		end
	end

	-- the border wall ----------------------------------------------------------------------------------------------------
	local function borderChecks(tag: string, near: boolean)
		local center = arenaCenter()
		local radius = tonumber(GS:GetAttribute("BorderRadius")) or 0
		local c = GS:GetAttribute("BorderCenter")
		if typeof(c) == "Vector3" then
			center = c
		end
		if near and radius > 0 then
			-- A 30 studs inside the wall facing it; B 90 studs inside, facing it
			local _, ra = parts(A)
			local dir = if ra then Vector3.new(ra.Position.X - center.X, 0, ra.Position.Z - center.Z).Unit else Vector3.xAxis
			local wallAt = center + dir * radius
			-- (the wall closes at about 9 studs/s at timeScale 4: A starts 70 studs inside it, B 150)
			standOn(A, center.X + dir.X * (radius - 70), center.Z + dir.Z * (radius - 70), wallAt)
			standOn(B, center.X + dir.X * (radius - 150) + dir.Z * 20, center.Z + dir.Z * (radius - 150) - dir.X * 20, wallAt)
			task.wait(1.5)
			call(A, "face", { x = wallAt.X, y = (groundY(wallAt.X, wallAt.Z) or 0) + 12, z = wallAt.Z })
			call(B, "face", { x = wallAt.X, y = (groundY(wallAt.X, wallAt.Z) or 0) + 12, z = wallAt.Z })
			task.wait(0.6)
			shot(tag, 0.4)
		end
		local reps = all(everyone, "border", nil, 8)
		local ok, d = true, {}
		for _, p in ipairs(everyone) do
			local r = reps[p] or {}
			L("BORDER " .. tag .. " " .. p.Name .. " " .. fmt(r))
			local drawn = (tonumber(r.drawn) or 0) > 0 and r.folder == true and r.error == nil
			ok = ok and drawn
			table.insert(d, string.format("%s: %s of %s parts drawn, hex=%s (%s, %s panels on, tile %s), SurfaceGuis %s/%s on, lattice=%s, nearest %s studs, HexImage=%s",
				p.Name, tostring(r.drawn), tostring(r.parts), tostring(r.hex), tostring(r.hexSource), tostring(r.hexPanels), tostring(r.hexTileW), tostring(r.surfaceGuisOn),
				tostring(r.surfaceGuis), tostring(r.lattice), fmt(r.nearest), tostring(r.hexConfig)))
		end
		check("p.border." .. tag, ok, string.format("radius %.0f moving=%s | %s", radius, tostring(GS:GetAttribute("BorderMoving")), table.concat(d, " | ")))
		return reps
	end

	local function musicChecks()
		local reps = all(everyone, "music.report", nil, 8)
		local orders, ok, d, bedsOk = {}, true, {}, true
		for _, p in ipairs(everyone) do
			local r = reps[p] or {}
			L("MUSIC report " .. p.Name .. " " .. fmt(r))
			orders[p] = tostring(r.order)
			bedsOk = bedsOk and (tonumber(r.maxAudible) or 9) <= 2
			table.insert(d, string.format("%s: %s (beds at once up to %s, audible %s; now %s)", p.Name, tostring(r.order), tostring(r.maxBeds), tostring(r.maxAudible), tostring(r.cue)))
		end
		local function has(o: string, cue: string): boolean
			return string.find(">" .. o .. ">", ">" .. cue .. ">", 1, true) ~= nil
		end
		local needed = { "Rise", "Countdown", "Scramble" }
		for _, p in ipairs(everyone) do
			for _, cue in ipairs(needed) do
				ok = ok and has(orders[p], cue)
			end
		end
		check("p.music.cuesChange", ok, "every client heard Rise, Countdown and Scramble: " .. table.concat(d, " | "))
		check("p.music.twoBedsMax", bedsOk, table.concat(d, " | "))
		-- night once, without flapping (the p033504 hysteresis fix)
		local nightOk, nd = true, {}
		for _, p in ipairs(everyone) do
			local o = orders[p]
			local count = 0
			for _ in string.gmatch(">" .. o .. ">", ">Night>") do
				count += 1
			end
			nightOk = nightOk and count == 1
			table.insert(nd, string.format("%s: Night came in %d time(s)", p.Name, count))
		end
		check("p.music.nightOnce", nightOk, table.concat(nd, " | ") .. string.format(" (Lighting.ClockTime %.2f)", game:GetService("Lighting").ClockTime))
		local borderOk = true
		for _, p in ipairs(everyone) do
			borderOk = borderOk and has(orders[p], "Border")
		end
		check("p.music.border", borderOk, "Border cue while the wall moves: " .. table.concat(d, " | "))
		local same = true
		local first = nil
		for _, p in ipairs(everyone) do
			local key = {}
			for cue in string.gmatch(orders[p], "[^>]+") do
				if cue == "Rise" or cue == "Countdown" or cue == "Scramble" or cue == "Night" or cue == "Border" then
					if key[#key] ~= cue then
						table.insert(key, cue)
					end
				end
			end
			local s = table.concat(key, ">")
			first = first or s
			same = same and s == first
		end
		check("p.music.sameOnAll", same, "the round's main cues in the same order on every client: " .. table.concat(d, " | "))
	end

	function M.run()
		launchChecks()
		borderChecks("atStart", false)
		slideChecks()
		hillChecks()
		-- night, then the wall moves (stage 1 at round second 560 = about 140 s after the horn at timeScale 4)
		local moving = waitFor(function()
			return GS:GetAttribute("BorderMoving") == true
		end, 120)
		L("POLISH border moving=" .. tostring(moving) .. " radius=" .. tostring(GS:GetAttribute("BorderRadius")))
		task.wait(4)
		borderChecks("moving", true)
		task.wait(4)
		local fpsA, fpsB = pmod(A, "fps", nil, 5), pmod(B, "fps", nil, 5)
		L("FPS by the moving wall: A " .. tostring(fpsA) .. " B " .. tostring(fpsB))
		musicChecks()
	end

	return M
end
