-- MPT_Shop (mp-shop, 20 Nov 2026): batch S of the MPTest driver. The card menus (the bar, keys 1 to 7, the hub), CASES
-- (a crate bought and opened by each player; the reveal only on the opener's screen), the daily reward, the Season
-- Track, ranks and the rank-up moment, leaderboards, cosmetics (skin, kill effect, kill icon, banner as the others see
-- them), all per player and saved (the driver's fake store, DataService.testRejoin). Test only: a child of MPT_Driver;
-- the client half is MPT_ShopClient (the bots' "mod" order).
return function(ctx: { [string]: any })
	local L, check, call, clientFind, mark, waitFor, phase, shot, fmt = ctx.L, ctx.check, ctx.call, ctx.clientFind, ctx.mark, ctx.waitFor, ctx.phase,
		ctx.shot, ctx.fmt
	local A: Player, B: Player, P3: Player? = ctx.A, ctx.B, ctx.P3
	local Data = ctx.Data
	local Services: Instance = ctx.Services
	local req = ctx.req
	local Players = game:GetService("Players")
	local Shop = req(Services, "ShopService")
	local Cos = req(Services, "CosmeticService")
	local Season = req(Services, "SeasonService")
	local Rank = req(Services, "RankService")
	local Boards = req(Services, "LeaderboardService")
	local Progression = req(ctx.Shared, "Progression")
	local Crates = req(ctx.Shared, "Crates")

	local M = {}
	local everyone = { A, B }
	if P3 then
		table.insert(everyone, P3)
	end

	local function mod(p: Player?, op: string, arg: any, timeout: number?): any
		return call(p, "mod", { op = op, arg = arg }, timeout or 25)
	end
	-- the same order on every listed client at once; returns { [Player] = result }
	local function both(list: { Player }, op: string, arg: any, timeout: number?): { [Player]: any }
		local out, left = {}, #list
		for _, p in ipairs(list) do
			task.spawn(function()
				out[p] = mod(p, op, arg, timeout)
				left -= 1
			end)
		end
		waitFor(function()
			return left <= 0
		end, (timeout or 25) + 2)
		return out
	end
	local function gold(p: Player): number
		return tonumber(Data.get(p, "Gold")) or -1
	end
	local function econ(p: Player): any
		return Data.getEcon(p) or {}
	end
	local function count(t: any): number
		local n = 0
		for _ in pairs(t or {}) do
			n += 1
		end
		return n
	end
	local function prog(p: Player): any
		return Season.progress(p) or {}
	end

	-- the looks each player wears (CosmeticLooks ids); owned through ShopService.grantCosmetic, equipped from the client
	-- through CosmeticsController.equip (the call the Loadout's Look tab makes)
	local LOOKS = {
		[A] = { skin = "starfall", effect = "petal_fall", icon = "laurel", banner = "mountain_dawn" },
		[B] = { skin = "riverstone", effect = "bell_toll", icon = "wolf_head", banner = "oak_and_iron" },
	}
	local refs: any = {}
	local before: { [Player]: any } = {}

	local function snapshot(p: Player): any
		local e = econ(p)
		local pr = prog(p)
		return {
			gold = gold(p), owned = count(e.Shop and e.Shop.Owned), pity = fmt(e.Shop and e.Shop.Pity), opened = e.Shop and e.Shop.Opened,
			daily = fmt(pr.Daily), season = fmt(pr.Season), xp = pr.XP, band = pr.Band, looks = fmt(e.Looks),
		}
	end

	function M.lobby()
		L("SHOP lobby part starts; phase=" .. phase())
		workspace:SetAttribute("BoardsCountSmall", true) -- (test server only: a 2-player round counts on the boards)
		check("s.setup.boards", Boards.useTestStores(), "LeaderboardService.useTestStores (in-memory ordered stores)")
		local loaded = waitFor(function()
			for _, p in ipairs(everyone) do
				if not Data.isLoaded(p) then
					return false
				end
			end
			return true
		end, 30)
		for _, p in ipairs(everyone) do
			Data.increment(p, "Gold", 5000)
		end
		task.wait(0.5)
		check("s.setup.loaded", loaded ~= nil, string.format("profiles loaded from the fake store; Gold A=%d B=%d", gold(A), gold(B)))
		local w = both(everyone, "watch", nil)
		L("SHOP watch " .. fmt(w))
		refs = mod(B, "refs", { icons = { "laurel", "wolf_head" }, banners = { "mountain_dawn", "oak_and_iron", "linen" } }) or {}

		-- 1. the daily reward opened by itself on join, on each screen -----------------------------------------------
		local m0 = both(everyone, "menu", nil)
		local det = {}
		local okDaily = true
		for _, p in ipairs(everyone) do
			local r = m0[p] or {}
			okDaily = okDaily and string.find(tostring(r.open), "daily", 1, true) ~= nil
			table.insert(det, p.Name .. ": open=" .. tostring(r.open) .. " titles=" .. tostring(r.titles))
		end
		check("s.daily.opensOnJoin", okDaily, table.concat(det, " | "))
		shot("s_daily_on_join", 1.2)
		both(everyone, "closeAll", nil)

		-- 2. the bar and the Hub action on each client --------------------------------------------------------------
		local m1 = both(everyone, "menu", nil)
		det = {}
		local okBar = true
		for _, p in ipairs(everyone) do
			local r = m1[p] or {}
			local keys = tostring(r.keyboard)
			local good = r.bar == true and r.tiles == "boards,cases,daily,inspect,loadout,pass,ranks" and string.find(keys, "One", 1, true) ~= nil
				and string.find(keys, "Seven", 1, true) ~= nil and string.find(tostring(r.gamepad), "DPadDown", 1, true) ~= nil
			okBar = okBar and good
			table.insert(det, string.format("%s: bar=%s tiles=[%s] keys=[%s] pad=[%s] priority=%s device=%s", p.Name, tostring(r.bar), tostring(r.tiles), keys,
				tostring(r.gamepad), tostring(r.priority), tostring(r.device)))
		end
		check("s.menu.bar", okBar, table.concat(det, " | "))
		shot("s_bar", 1.0)

		-- 3. keys 1 to 7 on every client at the same moment (a real key press when the test client allows one) -------
		local okKeys, howAll = true, {}
		det = {}
		for _, key in ipairs({ "loadout", "cases", "pass", "daily", "ranks", "boards", "inspect" }) do
			local r = both(everyone, "go", { key = key, press = true, keep = key == "cases" })
			for _, p in ipairs(everyone) do
				local x = r[p] or {}
				okKeys = okKeys and x.ok == true
				howAll[x.how or "?"] = true
				table.insert(det, string.format("%s %s: %s open=[%s] titles=[%s]%s", p.Name, key, tostring(x.how), tostring(x.open), tostring(x.titles),
					if x.vimWhy then " (no real key: " .. x.vimWhy .. ")" else ""))
			end
			if key == "cases" then
				shot("s_cases_both", 1.0)
				both(everyone, "closeAll", nil)
			end
		end
		check("s.menu.keys1to7", okKeys, table.concat(det, " | "))
		check("s.menu.realKeys", if howAll.key and not howAll.go then true else nil,
			"how the screens were opened: " .. fmt(howAll) .. " (key = a real key event through VirtualInputManager; go = MenuHubController.go, what the key handler calls)")

		-- 4. the hub on every client at once --------------------------------------------------------------------------
		local h = both(everyone, "hub", { press = true, keep = true })
		det = {}
		local okHub = true
		for _, p in ipairs(everyone) do
			local x = h[p] or {}
			okHub = okHub and x.open == true and x.count == 8
			table.insert(det, string.format("%s: how=%s open=%s cards=%s selected=%s :: %s", p.Name, tostring(x.how), tostring(x.open), tostring(x.count),
				tostring(x.selected), string.sub(tostring(x.cards), 1, 600)))
		end
		check("s.menu.hub", okHub, table.concat(det, " | "))
		shot("s_hub_both", 1.2)
		both(everyone, "closeAll", nil)

		-- 5. CASES: A buys a Timber crate, B an Ironbound one, at the same time -------------------------------------
		for _, p in ipairs(everyone) do
			before[p] = snapshot(p)
		end
		local mA, mB = mark(A), mark(B)
		local m3 = if P3 then mark(P3) else 0
		mod(A, "cases", { crate = "timber" })
		mod(B, "cases", { crate = "ironbound" })
		task.spawn(call, A, "fire", { name = "Shop", a = "buy", b = "timber", c = 1, d = false })
		task.spawn(call, B, "fire", { name = "Shop", a = "buy", b = "ironbound", c = 1, d = false })
		local gotA = waitFor(function()
			return clientFind(A, "SHOPEV shop result", mA)
		end, 8)
		local gotB = waitFor(function()
			return clientFind(B, "SHOPEV shop result", mB)
		end, 4)
		task.wait(2.5)
		local after = { [A] = snapshot(A), [B] = snapshot(B) }
		local tim, iro = Crates.ById.timber, Crates.ById.ironbound
		local function paid(p: Player, crate: any): (boolean, string)
			local spent = before[p].gold - after[p].gold
			local got = after[p].owned - before[p].owned
			-- a duplicate pays Gold back instead of an item
			local ok = (got == 1 and spent == crate.gold) or (got == 0 and spent < crate.gold and spent > 0)
			return ok, string.format("%s: Gold %d -> %d (spent %d, the %s is %d), owned %d -> %d, opened %s -> %s", p.Name, before[p].gold, after[p].gold, spent,
				crate.name, crate.gold, before[p].owned, after[p].owned, tostring(before[p].opened), tostring(after[p].opened))
		end
		local okA, dA = paid(A, tim)
		local okB, dB = paid(B, iro)
		check("s.cases.perPlayer", okA and okB and gotA ~= nil and gotB ~= nil and string.find(gotA, "crate=timber", 1, true) ~= nil
			and string.find(gotB, "crate=ironbound", 1, true) ~= nil, dA .. " | " .. dB .. " | A's client: " .. tostring(gotA) .. " | B's client: " .. tostring(gotB))
		-- the reveal is the opener's only
		local rA, rB = mod(A, "reveal", nil) or {}, mod(B, "reveal", nil) or {}
		local bSawA = clientFind(B, "crate=timber", mB)
		local aSawB = clientFind(A, "crate=ironbound", mA)
		local p3Saw = if P3 then (clientFind(P3, "SHOPEV shop result", m3)) else nil
		check("s.cases.revealPrivate", rA.lastCrate == "timber" and rB.lastCrate == "ironbound" and bSawA == nil and aSawB == nil and p3Saw == nil
			and rA.texts ~= "" and rB.texts ~= "", string.format("A's CASES reveal: crate=%s texts=[%s] | B's: crate=%s texts=[%s] | B got A's result: %s, A got B's: %s, %s got any: %s",
			tostring(rA.lastCrate), tostring(rA.texts), tostring(rB.lastCrate), tostring(rB.texts), tostring(bSawA), tostring(aSawB),
			if P3 then P3.Name else "(no third)", tostring(p3Saw)))
		shot("s_cases_reveal", 1.4)
		both(everyone, "closeAll", nil)

		-- 6. the daily reward per player --------------------------------------------------------------------------------
		local g0 = { [A] = gold(A), [B] = gold(B) }
		mA, mB = mark(A), mark(B)
		call(A, "fire", { name = "Progress", a = { t = "daily" } })
		call(B, "fire", { name = "Progress", a = { t = "daily" } })
		waitFor(function()
			return clientFind(A, "SHOPEV progress claimed", mA) and clientFind(B, "SHOPEV progress claimed", mB)
		end, 6)
		task.wait(1.2)
		local g1 = { [A] = gold(A), [B] = gold(B) }
		call(A, "fire", { name = "Progress", a = { t = "daily" } }) -- a second claim the same day: refused
		task.wait(1.5)
		local g2 = gold(A)
		check("s.daily.perPlayer", g1[A] - g0[A] == 150 and g1[B] - g0[B] == 150 and g2 == g1[A] and prog(A).Daily.streak == 1 and prog(B).Daily.streak == 1,
			string.format("A Gold %d -> %d (then a second claim: %d), streak %s; B Gold %d -> %d, streak %s; A's client: %s | B's client: %s", g0[A], g1[A], g2,
				tostring(prog(A).Daily.streak), g0[B], g1[B], tostring(prog(B).Daily.streak), tostring(clientFind(A, "SHOPEV progress claimed", mA)),
				tostring(clientFind(B, "SHOPEV progress claimed", mB))))

		-- 7. Season Track and Level per player: A to just under level 10 (the round then crosses into Runner) ---------
		local need = Progression.totalFor(10) - (prog(A).XP or 0) - 200
		Rank.addXP(A, need, "test")
		Rank.addXP(B, 500, "test") -- (level 2, still Season tier 0: the Level board gets B's write now that the test stores are on)
		task.wait(0.8)
		mA, mB = mark(A), mark(B)
		call(A, "fire", { name = "Progress", a = { t = "claim", row = "free", tier = 1 } })
		call(B, "fire", { name = "Progress", a = { t = "claim", row = "free", tier = 1 } })
		task.wait(2)
		local sA, sB = prog(A).Season or {}, prog(B).Season or {}
		local tierA = Progression.tierOf(sA.xp or 0)
		local tierB = Progression.tierOf(sB.xp or 0)
		check("s.season.perPlayer", tierA >= 1 and tierB == 0 and clientFind(A, "SHOPEV progress claimed", mA) ~= nil and clientFind(B, "SHOPEV progress claimed", mB) == nil,
			string.format("A: level %s, season XP %s (tier %d), free claims bits %s, client %s | B: level %s, season XP %s (tier %d), free bits %s, a tier-1 claim refused (client got: %s); free tier 1 reward %s",
				tostring(A:GetAttribute("Level")), tostring(sA.xp), tierA, tostring(sA.free), tostring(clientFind(A, "SHOPEV progress claimed", mA)),
				tostring(B:GetAttribute("Level")), tostring(sB.xp), tierB, tostring(sB.free), tostring(clientFind(B, "SHOPEV progress claimed", mB)),
				fmt(Progression.FreeRow[1])))

		-- 8. cosmetics: owned and equipped per player, seen by the other ---------------------------------------------
		for p, set in pairs(LOOKS) do
			for _, id in pairs(set) do
				Shop.grantCosmetic(p, id)
			end
		end
		task.wait(0.4)
		for p, set in pairs(LOOKS) do
			task.spawn(function()
				for _, slot in ipairs({ "skin", "effect", "icon", "banner" }) do
					mod(p, "equip", { id = set[slot], slot = slot, weapon = if slot == "skin" then nil else "*" })
					task.wait(0.6) -- (the Looks remote takes 4 a second at most... and 8 in a burst)
				end
			end)
		end
		task.wait(4)
		local la, lb = Cos.getLooks(A), Cos.getLooks(B)
		local function wears(l: any, set: any): boolean
			return l.s.sword == set.skin and l.e["*"] == set.effect and l.i["*"] == set.icon and l.b == set.banner
		end
		local seenByB = mod(B, "looksOf", { name = A.Name }) or {}
		local seenByA = mod(A, "looksOf", { name = B.Name }) or {}
		local encA, encB = A:GetAttribute("LooksJson"), B:GetAttribute("LooksJson")
		check("s.looks.equipped", wears(la, LOOKS[A]) and wears(lb, LOOKS[B]), "server: A " .. fmt(la) .. " | B " .. fmt(lb))
		check("s.looks.seenByOther", seenByB.looks == encA and seenByA.looks == encB, string.format("B's client has A's looks %s (server %s) | A's client has B's %s (server %s)",
			tostring(seenByB.looks), tostring(encA), tostring(seenByA.looks), tostring(encB)))

		-- 9. leave and come back (DataService.testRejoin through the fake store): everything per player stays -------
		local pre = { [A] = snapshot(A), [B] = snapshot(B) }
		Data.saveNow(A)
		Data.saveNow(B)
		local r1, r2 = Data.testRejoin(A), Data.testRejoin(B)
		waitFor(function()
			return Data.isLoaded(A) and Data.isLoaded(B)
		end, 15)
		task.wait(0.5)
		local post = { [A] = snapshot(A), [B] = snapshot(B) }
		det = {}
		local okRe = r1 and r2
		for _, p in ipairs({ A, B }) do
			for k, v in pairs(pre[p]) do
				if post[p][k] ~= v then
					okRe = false
					table.insert(det, string.format("%s.%s %s -> %s", p.Name, k, tostring(v), tostring(post[p][k])))
				end
			end
		end
		check("s.save.rejoin", okRe, string.format("saved=%s/%s; fake store keys=%d writes=%d; differences: %s; A now %s | B now %s", tostring(r1), tostring(r2),
			count(ctx.fakeData), ctx.fakeWrites(), if #det > 0 then table.concat(det, "; ") else "none", fmt(post[A]), fmt(post[B])))
		before = post
		both(everyone, "closeAll", nil)
		L("SHOP lobby part done; phase=" .. phase())
	end

	function M.run()
		-- the round: both walk a little first (taking part: CurrencyService's AFK rule), then A wears its looks with the
		-- sword, B sees them; A defeats B
		task.spawn(call, A, "move", { seconds = 4, y = 1 })
		if P3 then
			task.spawn(call, P3, "move", { seconds = 4, y = 1 })
		end
		call(B, "move", { seconds = 4, y = 1 })
		task.wait(4.6)
		ctx.setupDuel()
		local slot = nil
		if ctx.Inv.give(A, "sword", 1) > 0 then
			local snap = ctx.Inv.getSnapshot(A)
			for i, s in ipairs(snap.slots) do
				if type(s) == "table" and s.id == "sword" then
					slot = i
				end
			end
		end
		if slot then
			call(A, "seq", { { "select", slot }, { "wait", 1.2 } }, 10)
		end
		local seen = mod(B, "looksOf", { name = A.Name }) or {}
		local own = mod(A, "looksOf", { name = A.Name }) or {}
		local hold = A.Character and A.Character:FindFirstChild("EquippedModel")
		check("s.round.skinSeen", seen.item == "sword" and seen.skin == LOOKS[A].skin and own.viewSkin == LOOKS[A].skin, string.format(
			"server: A holds %s skin=%s | on B's screen A's sword: item=%s skin=%s colours %s | A's first person: item=%s skin=%s", tostring(hold and hold:GetAttribute("ItemId")),
			tostring(hold and hold:GetAttribute("Skin")), tostring(seen.item), tostring(seen.skin), tostring(seen.colors), tostring(own.viewItem), tostring(own.viewSkin)))
		shot("s_skin_seen", 1.0)
		local mA, mB = ctx.killB("round1")
		task.wait(1.3) -- the clients sample the drawn effect 0.5 s after it appears
		local _, rootB = ctx.parts(B)
		local fxA = clientFind(A, "SHOPEV killfx remote", mA)
		local fxB = clientFind(B, "SHOPEV killfx remote", mB)
		local drawnA = clientFind(A, "SHOPEV killfx drawn", mA)
		local drawnB = clientFind(B, "SHOPEV killfx drawn", mB)
		check("s.round.killEffect", fxA ~= nil and fxB ~= nil and string.find(fxB, "id=" .. LOOKS[A].effect, 1, true) ~= nil
			and string.find(fxB, "killer=" .. A.UserId, 1, true) ~= nil and drawnA ~= nil and drawnB ~= nil
			and string.find(drawnB, "KillFx_" .. LOOKS[A].effect, 1, true) ~= nil
			-- where the victim fell: the drawn bits' middle within 12 studs (flat) of the message's position, on both screens
			and (tonumber(string.match(drawnB, "flatOff=([%d%.]+)")) or 999) <= 12 and (tonumber(string.match(drawnA, "flatOff=([%d%.]+)")) or 999) <= 12,
			string.format("A's client: %s ; %s | B's client: %s ; %s | B's body now at %s", tostring(fxA), tostring(drawnA), tostring(fxB), tostring(drawnB),
				if rootB then ctx.v3(rootB.Position) else "gone"))
		local iconA = clientFind(A, "SHOPEV feedicon", mA)
		local iconB = clientFind(B, "SHOPEV feedicon", mB)
		local want = refs["icon:" .. LOOKS[A].icon]
		check("s.round.killIcon", iconA ~= nil and iconB ~= nil and want ~= nil and string.find(iconB, "sig=" .. want, 1, true) ~= nil
			and string.find(iconA, "sig=" .. want, 1, true) ~= nil, string.format("A's feed: %s | B's feed: %s | laurel drawn: %s | wolf head: %s", tostring(iconA),
			tostring(iconB), tostring(want), tostring(refs["icon:" .. LOOKS[B].icon])))
		if P3 then
			-- the third client: its own screen got A's effect message and icon too; then it falls (no killer) so the round ends
			local fx3 = clientFind(P3, "SHOPEV killfx remote", 0)
			local icon3 = clientFind(P3, "SHOPEV feedicon", 0)
			local looks3 = mod(P3, "looksOf", { name = A.Name }) or {}
			check("s.round.thirdSees", fx3 ~= nil and icon3 ~= nil and want ~= nil and string.find(icon3, "sig=" .. want, 1, true) ~= nil
				and looks3.looks == A:GetAttribute("LooksJson"), string.format("%s's client: %s | feed %s | A's looks there %s", P3.Name, tostring(fx3), tostring(icon3),
				tostring(looks3.looks)))
		end
		ctx.deathChecks("round1", mA, mB, if P3 then 3 else 2)
		if P3 then
			local hum = ctx.parts(P3)
			if hum then
				hum.Health = 0
			end
		end
		-- the rank-up: A's XP crosses into Runner with this round; the moment waits for the train
		ctx.resultChecks("round1", mA, mB, A, { B })
		local rankMsgA = waitFor(function()
			return clientFind(A, "SHOPEV progress rankup", mA)
		end, 8)
		local guiDuring = clientFind(A, "SHOPEV rankupgui enabled=true inArena=true", mA)
		ctx.backToLobby("round1", { A, B })
		local shown = waitFor(function()
			return clientFind(A, "SHOPEV rankupgui enabled=true", mA)
		end, 12)
		local ru = mod(A, "rankup", nil) or {}
		shot("s_rankup", 1.4)
		check("s.rank.upInTrain", rankMsgA ~= nil and shown ~= nil and guiDuring == nil and clientFind(B, "SHOPEV progress rankup", mB) == nil,
			string.format("A: level %s rank %s; message %s; moment shown: %s; texts [%s] | shown while in the arena: %s | B got a rank-up: %s (B level %s)",
				tostring(A:GetAttribute("Level")), tostring(A:GetAttribute("RankName")), tostring(rankMsgA), tostring(shown), tostring(ru.texts),
				tostring(guiDuring), tostring(clientFind(B, "SHOPEV progress rankup", mB)), tostring(B:GetAttribute("Level"))))
		mod(A, "closeAll", nil)
		-- the round's pay, per player
		local pA, pB = snapshot(A), snapshot(B)
		-- (both walked 30+ studs first, so both took part under CurrencyService's AFK rule)
		check("s.round.paid", pA.gold > before[A].gold and (pA.xp or 0) > (before[A].xp or 0) and pB.gold > before[B].gold and (pB.xp or 0) > (before[B].xp or 0),
			string.format("A Gold %d -> %d XP %s -> %s | B Gold %d -> %d XP %s -> %s (B's taking part: %s)", before[A].gold, pA.gold, tostring(before[A].xp),
				tostring(pA.xp), before[B].gold, pB.gold, tostring(before[B].xp), tostring(pB.xp),
				fmt(Services:FindFirstChild("CurrencyService") and req(Services, "CurrencyService").lastRound(B))))
		-- the winner's banner over A in the train, on B's screen
		local ban = waitFor(function()
			local list = mod(B, "banner", nil, 8)
			return if type(list) == "table" and #list > 0 then list else nil
		end, 10) or {}
		local wantBanner = refs["banner:" .. LOOKS[A].banner]
		local b1 = ban[1] or {}
		check("s.banner.seenByB", b1.over == A.Name and b1.sig == wantBanner and wantBanner ~= refs["banner:linen"], string.format(
			"B's screen: banner over %s, picture %s | Mountain Dawn %s | Linen %s", tostring(b1.over), tostring(b1.sig), tostring(wantBanner), tostring(refs["banner:linen"])))
		shot("s_banner", 1.2)
		-- the boards: both ranked once the writes land (spread over 10 s) and are read
		task.wait(11)
		Boards.refreshNow()
		task.wait(1.5)
		local function rowsOf(board: string, scope: string): string
			local v = Boards.view(A, board, scope)
			local out = {}
			for _, r in ipairs(v.rows or {}) do
				table.insert(out, string.format("%d.%s=%s", r.place, tostring(r.name), tostring(r.value)))
			end
			return table.concat(out, " ")
		end
		local surv, elims, level = rowsOf("Survive", "week"), rowsOf("Elims", "week"), rowsOf("Level", "all")
		local wins = rowsOf("Wins", "week")
		local both2 = function(s: string): boolean
			return string.find(s, A.Name, 1, true) ~= nil and string.find(s, B.Name, 1, true) ~= nil
		end
		local paper = mod(B, "boards", nil) or {}
		local paperText = if type(paper) == "table" then table.concat(paper, " || ") else tostring(paper)
		check("s.boards.rankBoth", both2(surv) and both2(level) and string.find(wins, A.Name, 1, true) ~= nil and string.find(elims, A.Name, 1, true) ~= nil,
			string.format("Survive week: %s | Level all: %s | Wins week: %s | Elims week: %s", surv, level, wins, elims))
		check("s.boards.paperOnB", string.find(paperText, A.Name, 1, true) ~= nil, "B's screen, paper boards: " .. string.sub(paperText, 1, 900))
		-- saved again after the round
		local pre = { [A] = snapshot(A), [B] = snapshot(B) }
		Data.saveNow(A)
		Data.saveNow(B)
		Data.testRejoin(A)
		Data.testRejoin(B)
		waitFor(function()
			return Data.isLoaded(A) and Data.isLoaded(B)
		end, 15)
		task.wait(0.5)
		local post = { [A] = snapshot(A), [B] = snapshot(B) }
		local diffs = {}
		for _, p in ipairs({ A, B }) do
			for k, v in pairs(pre[p]) do
				if post[p][k] ~= v then
					table.insert(diffs, string.format("%s.%s %s -> %s", p.Name, k, tostring(v), tostring(post[p][k])))
				end
			end
		end
		check("s.save.afterRound", #diffs == 0, "after the round, leave and rejoin: " .. (if #diffs > 0 then table.concat(diffs, "; ") else "nothing changed") .. " | A " .. fmt(post[A]))
		-- every menu again with both players back in the train
		local okK, det = true, {}
		for _, key in ipairs({ "loadout", "cases", "pass", "ranks" }) do
			local r = both({ A, B }, "go", { key = key })
			for _, p in ipairs({ A, B }) do
				local x = r[p] or {}
				okK = okK and x.ok == true
				table.insert(det, p.Name .. " " .. key .. "=" .. tostring(x.ok))
			end
		end
		check("s.menu.afterRound", okK, table.concat(det, " "))
	end

	return M
end
