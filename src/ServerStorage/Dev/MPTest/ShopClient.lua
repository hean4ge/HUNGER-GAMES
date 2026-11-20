-- MPT_ShopClient (mp-shop, 20 Nov 2026): the client half of batch S (the card menus, CASES, the Season Track, the
-- daily reward, ranks, leaderboards and cosmetics with two or three players). Test only: MPT_Driver copies it into
-- ReplicatedStorage while a Studio multiplayer test runs, and MPT_Bot requires it for its "mod" order. It reads the
-- game's own controllers (the same module tables the game uses: the bot is a LocalScript in the same VM) and reports.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

return function(ctx: { [string]: any })
	local L: (string) -> () = ctx.L
	local fmt = ctx.fmt
	local Controllers: Instance = ctx.Controllers
	local ClientState = ctx.ClientState
	local Input = ctx.Input
	local lp = Players.LocalPlayer
	local gui = lp:WaitForChild("PlayerGui")
	local Shared = RS:WaitForChild("Shared")
	local CosmeticLooks = require(Shared:WaitForChild("CosmeticLooks"))
	local Client = Controllers.Parent

	local cache: { [string]: any } = {}
	local function C(name: string): any
		if cache[name] == nil then
			local m = Controllers:FindFirstChild(name)
			local ok, res = pcall(require, m)
			cache[name] = if ok then res else false
		end
		return cache[name] or nil
	end
	local function ProgressUI(): any
		local m = Client and Client:FindFirstChild("ProgressUI")
		local ok, res = pcall(require, m)
		return if ok then res else nil
	end

	-- which card screens are up now
	local function openScreens(): { string }
		local out = {}
		local function add(name: string, on: any)
			if on == true then
				table.insert(out, name)
			end
		end
		local hub, shop, lo, ins, se, da, ra, st = C("MenuHubController"), C("ShopController"), C("LoadoutController"), C("InspectController"),
			C("SeasonController"), C("DailyController"), C("RanksController"), C("SettingsController")
		add("hub", hub and hub.isOpen())
		add("cases", shop and shop.isOpen)
		-- (20 Nov) the loadout key, tile and rack open the Prepare screen (kit, skills, trail); the old Loadout is behind it
		local prep = C("PrepareController")
		add("loadout", (lo and lo.isOpen()) or (prep and prep.isOpen()))
		add("inspect", ins and ins.isOpen())
		add("pass", se and se.isOpen())
		add("daily", da and da.isOpen())
		add("ranks", ra and ra.isOpen())
		add("settings", st and st.isOpen and st.isOpen())
		return out
	end
	-- the visible ScreenGuis of the card screens and their titles
	local function titles(): { string }
		local out = {}
		for _, g in ipairs(gui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "MPT" then
				local t = g:FindFirstChild("Title", true)
				if t and t:IsA("TextLabel") and t.Visible then
					table.insert(out, g.Name .. ":" .. t.Text)
				end
			end
		end
		table.sort(out)
		return out
	end
	local function closeAll()
		for _, name in ipairs({ "MenuHubController", "ShopController", "LoadoutController", "InspectController", "SeasonController",
			"DailyController", "RanksController", "SettingsController", "PrepareController" }) do
			local c = C(name)
			if c and type(c.close) == "function" then
				pcall(c.close)
			end
		end
		-- (20 Nov) HOW TO PLAY opens by itself before a player's first round and the bar steps aside while it shows
		local lobby = C("LobbyController")
		if lobby and type(lobby.setHowToVisible) == "function" then
			pcall(lobby.setHowToVisible, false)
		end
		task.wait(0.7)
	end

	-- a real key through Roblox's input (VirtualInputManager): only when the test client allows it
	local vimOk: boolean? = nil
	local vimWhy = ""
	local function press(key: Enum.KeyCode): boolean
		local ok, err = pcall(function()
			local vim = game:GetService("VirtualInputManager")
			vim:SendKeyEvent(true, key, false, game)
			task.wait(0.06)
			vim:SendKeyEvent(false, key, false, game)
		end)
		if not ok then
			vimWhy = tostring(err)
		end
		vimOk = ok
		return ok
	end

	-- a picture signature of a GUI tree (colours and classes), to tell one icon or banner from another
	local function sig(root: Instance?): string
		if not root then
			return "none"
		end
		local parts = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("GuiObject") and not d:IsA("TextLabel") then -- (the winner's name label on a banner is not its picture)
				local c = d.BackgroundColor3
				local s = d.ClassName .. ":" .. c:ToHex()
				if d:IsA("ImageLabel") or d:IsA("ImageButton") then -- (20 Nov) banners and icons are atlas cuts now
					s ..= ":" .. (tostring(d.Image):match("%d+$") or tostring(d.Image)) .. "@" .. tostring(d.ImageRectOffset)
				end
				table.insert(parts, s)
			end
		end
		return #parts .. "|" .. table.concat(parts, ","):sub(1, 400)
	end
	local function refIcon(id: string): string
		local made = CosmeticLooks.killIcon(id, 16, { Name = "Ref" })
		local s = sig(made)
		if made then
			made:Destroy()
		end
		return s
	end
	local function refBanner(id: string): string
		local made = CosmeticLooks.banner(id, { Name = "Ref" })
		local s = sig(made)
		made:Destroy()
		return s
	end

	-- listeners, logged as they happen ("SHOPEV ...") so the driver finds them with clientFind --------------------------
	local watching = false
	local function watch()
		if watching then
			return true
		end
		watching = true
		local remotes = RS:WaitForChild("Remotes")
		local function on(name: string, fn: (...any) -> ())
			local r = remotes:WaitForChild(name, 10)
			if r and r:IsA("RemoteEvent") then
				r.OnClientEvent:Connect(function(...)
					local ok, err = pcall(fn, ...)
					if not ok then
						L("SHOPEV listen " .. name .. " failed: " .. tostring(err))
					end
				end)
			else
				L("SHOPEV no remote " .. name)
			end
		end
		on("Shop", function(kind, data)
			if kind == "result" and type(data) == "table" then
				local ids = {}
				for _, d in ipairs(data.results or {}) do
					table.insert(ids, tostring(d.id or d.name) .. "/" .. tostring(d.grade))
				end
				L(string.format("SHOPEV shop result crate=%s spent=%s goldBack=%s items=%s", tostring(data.crate), tostring(data.spent), tostring(data.goldBack),
					table.concat(ids, ",")))
			elseif kind == "line" then
				L("SHOPEV shop line " .. tostring(data))
			elseif kind == "state" and type(data) == "table" then
				local n = 0
				for _ in pairs(data.owned or {}) do
					n += 1
				end
				L(string.format("SHOPEV shop state gold=%s owned=%d acorns=%s", tostring(data.gold), n, tostring(data.acorns)))
			end
		end)
		on("Progress", function(msg)
			if type(msg) ~= "table" then
				return
			end
			if msg.t == "state" then
				local s = msg.s or {}
				local d = s.daily or {}
				local se = s.season or {}
				L(string.format("SHOPEV progress state daily.claimable=%s daily.day=%s season.tier=%s level=%s", tostring(d.claimable), tostring(d.day), tostring(se.tier),
					tostring(s.level)))
			else
				L("SHOPEV progress " .. tostring(msg.t) .. " " .. string.sub(fmt(msg), 1, 300))
			end
		end)
		on("Looks", function(kind, data)
			L("SHOPEV looks " .. tostring(kind) .. " ok=" .. tostring(type(data) == "table" and data.ok) .. " why=" .. tostring(type(data) == "table" and data.why))
		end)
		local lastFxPos: Vector3? = nil
		on("KillFx", function(data)
			if type(data) == "table" then
				if typeof(data.pos) == "Vector3" then
					lastFxPos = data.pos
				end
				L(string.format("SHOPEV killfx remote id=%s pos=%s killer=%s victim=%s weapon=%s", tostring(data.id), fmt(data.pos), tostring(data.killer),
					tostring(data.victim), tostring(data.weapon)))
			end
		end)
		workspace.ChildAdded:Connect(function(child)
			if child:IsA("Folder") and string.sub(child.Name, 1, 7) == "KillFx_" then
				-- the bits are placed by the effect's Heartbeat step, so sample a little later and take the middle of the
				-- placed parts (ones still at the world origin are not placed yet), and how far it is from the message's pos
				task.wait(0.5)
				local sum, placed, n = Vector3.zero, 0, 0
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then
						n += 1
						if d.Position.Magnitude > 1 then
							sum += d.Position
							placed += 1
						end
					end
				end
				local at: Vector3? = if placed > 0 then sum / placed else nil
				local off = if at and lastFxPos then string.format("%.1f", (Vector3.new(at.X, 0, at.Z) - Vector3.new(lastFxPos.X, 0, lastFxPos.Z)).Magnitude) else "?"
				L(string.format("SHOPEV killfx drawn %s parts=%d placed=%d at=%s flatOff=%s", child.Name, n, placed, fmt(at), off))
			end
		end)
		gui.DescendantAdded:Connect(function(d)
			if d.Name == "KillIcon" and d.Parent and string.match(d.Parent.Name, "^Kill%d+$") then
				task.wait()
				L("SHOPEV feedicon " .. d.Parent.Name .. " sig=" .. sig(d))
			elseif d.Name == "Blade" and d.Parent and string.match(d.Parent.Name, "^Kill%d+$") then
				L("SHOPEV feedblade " .. d.Parent.Name)
			elseif d:IsA("BillboardGui") and d.Name == "WinnerBanner" then
				task.wait(0.2)
				local adornee = d.Adornee
				local owner = adornee and adornee.Parent and Players:GetPlayerFromCharacter(adornee.Parent)
				L(string.format("SHOPEV winnerbanner over=%s sig=%s", if owner then owner.Name else "?", sig(d:FindFirstChild("Banner", true))))
			end
		end)
		local function watchRankUp(g: Instance)
			if g:IsA("ScreenGui") and g.Name == "RankUpGui" then
				g:GetPropertyChangedSignal("Enabled"):Connect(function()
					L(string.format("SHOPEV rankupgui enabled=%s inArena=%s phase=%s", tostring(g.Enabled), tostring(ClientState.inArena),
						tostring(RS.GameState:GetAttribute("Phase"))))
				end)
			end
		end
		for _, g in ipairs(gui:GetChildren()) do
			watchRankUp(g)
		end
		gui.ChildAdded:Connect(watchRankUp)
		-- the level-up line (RanksController): when it is shown, where this player is
		task.spawn(function()
			local lg = gui:WaitForChild("LevelLineGui", 20)
			local line = lg and lg:WaitForChild("Line", 5)
			if line and line:IsA("TextLabel") then
				line:GetPropertyChangedSignal("Text"):Connect(function()
					L(string.format("SHOPEV levelline '%s' inArena=%s launchShot=%s menuOpen=%s phase=%s alive=%s", line.Text, tostring(ClientState.inArena),
						tostring(ClientState.launchShot), tostring(ClientState.menuOpen), tostring(RS.GameState:GetAttribute("Phase")), tostring(lp:GetAttribute("Alive"))))
				end)
			end
		end)
		-- the modal state as it changes (a menu left "open" holds the rank-up moment and the level line)
		task.spawn(function()
			local last = nil
			while true do
				task.wait(0.5)
				local now = ClientState.menuOpen == true
				if now ~= last then
					last = now
					L(string.format("SHOPEV menuOpen=%s inArena=%s phase=%s", tostring(now), tostring(ClientState.inArena), tostring(RS.GameState:GetAttribute("Phase"))))
				end
			end
		end)
		return true
	end

	local ops: { [string]: (any) -> any } = {}

	ops.watch = function()
		return watch()
	end

	-- the bar, the hub's bindings, what is open
	ops.menu = function()
		local hub = C("MenuHubController")
		local d = Input.describe("Hub")
		local bar = gui:FindFirstChild("MenuHub")
		local tiles = {}
		local barFrame = bar and bar:FindFirstChild("Bar", true)
		if barFrame then
			for _, t in ipairs(barFrame:GetChildren()) do
				if t:IsA("GuiButton") then
					table.insert(tiles, t.Name)
				end
			end
		end
		table.sort(tiles)
		local function names(list: { any }?): string
			local out = {}
			for _, k in ipairs(list or {}) do
				table.insert(out, k.Name)
			end
			return table.concat(out, ",")
		end
		local info = ContextActionService:GetBoundActionInfo("Hub")
		return {
			bar = hub and hub.barVisible(), tiles = table.concat(tiles, ","), keyboard = d and names(d.keyboard), gamepad = d and names(d.gamepad),
			priority = info and info.priorityLevel, open = table.concat(openScreens(), ","), menuOpen = ClientState.menuOpen == true,
			inArena = ClientState.inArena == true, titles = table.concat(titles(), " ; "), device = Input.device(),
		}
	end

	ops.closeAll = function()
		closeAll()
		return table.concat(openScreens(), ",")
	end

	-- one card screen through the menu: by its number key (a real key press when the client allows it) or MenuHub.go
	local KEYS = { loadout = Enum.KeyCode.One, cases = Enum.KeyCode.Two, pass = Enum.KeyCode.Three, daily = Enum.KeyCode.Four,
		ranks = Enum.KeyCode.Five, boards = Enum.KeyCode.Six, inspect = Enum.KeyCode.Seven }
	local WANT = { loadout = "loadout", cases = "cases", pass = "pass", daily = "daily", ranks = "ranks", boards = "ranks", inspect = "inspect",
		settings = "settings" }
	ops.go = function(arg)
		local key = tostring(arg.key)
		closeAll()
		local how = "go"
		if arg.press and KEYS[key] and vimOk ~= false then
			if press(KEYS[key]) then
				how = "key"
			end
		end
		if how == "go" then
			C("MenuHubController").go(key)
		end
		task.wait(arg.wait or 0.8)
		local open = openScreens()
		local t = titles()
		local good = table.find(open, WANT[key]) ~= nil
		local res = { key = key, how = how, open = table.concat(open, ","), titles = table.concat(t, " ; "), ok = good, menuOpen = ClientState.menuOpen == true,
			vimWhy = if vimOk == false then string.sub(vimWhy, 1, 160) else nil }
		if arg.keep ~= true then
			closeAll()
		end
		return res
	end

	-- the hub of eight cards (gamepad D-pad down when the client allows a real press)
	ops.hub = function(arg)
		closeAll()
		local hub = C("MenuHubController")
		local how = "open"
		if arg and arg.press and vimOk ~= false and press(Enum.KeyCode.DPadDown) then
			how = "dpad"
			task.wait(0.6)
		end
		if not hub.isOpen() then
			how = how .. "+open()"
			hub.open()
		end
		task.wait(0.8)
		local g = gui:FindFirstChild("MenuHubGui")
		local cards = {}
		local scroll = g and g:FindFirstChild("Cards", true)
		if scroll then
			for _, c in ipairs(scroll:GetChildren()) do
				if c:IsA("GuiButton") then
					local text = {}
					for _, d in ipairs(c:GetDescendants()) do
						if d:IsA("TextLabel") and d.Visible and d.Text ~= "" then
							table.insert(text, d.Text)
						end
					end
					table.insert(cards, c.Name .. "[" .. table.concat(text, "|") .. "]")
				end
			end
		end
		local sel = GuiService.SelectedObject
		local res = { how = how, open = hub.isOpen(), count = #cards, cards = table.concat(cards, " ; "), selected = if sel then sel.Name else "none",
			vimWhy = if vimOk == false then string.sub(vimWhy, 1, 160) else nil }
		if not (arg and arg.keep) then
			closeAll()
		end
		return res
	end

	-- CASES open on a crate (as the hub's Cases card does), ready for BUY
	ops.cases = function(arg)
		closeAll()
		local shop = C("ShopController")
		local ok = shop.open(arg and arg.crate, (arg and arg.tab) or "buy")
		if arg and arg.crate and shop.select then
			pcall(shop.select, arg.crate)
		end
		task.wait(0.5)
		return { ok = ok, open = shop.isOpen }
	end

	-- what CASES shows now: the reveal pane's texts
	ops.reveal = function()
		local shop = C("ShopController")
		local cases = gui:FindFirstChild("Cases")
		local texts = {}
		-- (every reveal pane: OPEN's "RevealPane", BUY's "BuyReveal" when shown)
		for _, pane in ipairs(if cases then cases:GetDescendants() else {}) do
			if pane.Name == "RevealPane" or (pane.Name == "BuyReveal" and pane:IsA("GuiObject") and pane.Visible) then
				for _, d in ipairs(pane:GetDescendants()) do
					if d:IsA("TextLabel") and d.Visible and d.Text ~= "" then
						table.insert(texts, d.Text)
					end
				end
			end
		end
		local dbg = shop and shop._debug and shop._debug() or {}
		local last = dbg.lastResult
		return { open = shop and shop.isOpen, enabled = cases ~= nil and cases.Enabled, texts = table.concat(texts, " | "):sub(1, 400),
			lastCrate = type(last) == "table" and last.crate or nil, gold = dbg.shop and dbg.shop.gold }
	end

	ops.equip = function(arg)
		local cos = C("CosmeticsController")
		cos.equip(arg.id, arg.weapon, arg.slot)
		return true
	end

	-- someone's looks as THIS client has them, and the weapon they hold as drawn here
	ops.looksOf = function(arg)
		local p = Players:FindFirstChild(arg.name)
		if not (p and p:IsA("Player")) then
			return { error = "no player " .. tostring(arg.name) }
		end
		local looks = CosmeticLooks.of(p)
		local out = { looks = CosmeticLooks.encode(looks) }
		local c = p.Character
		local em = c and c:FindFirstChild("EquippedModel")
		if em then
			out.item = em:GetAttribute("ItemId")
			out.skin = em:GetAttribute("Skin")
			local cols = {}
			for _, d in ipairs(em:GetDescendants()) do
				if d:IsA("BasePart") then
					local role = d:GetAttribute("Role") or d.Name
					table.insert(cols, tostring(role) .. "=" .. d.Color:ToHex())
				end
			end
			table.sort(cols)
			out.colors = table.concat(cols, ","):sub(1, 400)
		end
		if p == lp then
			-- the first-person model in the camera
			local cam = workspace.CurrentCamera
			for _, d in ipairs(cam:GetDescendants()) do
				if d:IsA("Model") and d:GetAttribute("Skin") ~= nil then
					out.viewSkin = d:GetAttribute("Skin")
					out.viewItem = d:GetAttribute("ItemId")
					break
				end
			end
		end
		return out
	end

	ops.refs = function(arg)
		local out = {}
		for _, id in ipairs(arg.icons or {}) do
			out["icon:" .. id] = refIcon(id)
		end
		for _, id in ipairs(arg.banners or {}) do
			out["banner:" .. id] = refBanner(id)
		end
		return out
	end

	-- the winner banner and paper boards as this client has them
	ops.banner = function()
		local out = {}
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("BillboardGui") and d.Name == "WinnerBanner" then
				local adornee = d.Adornee
				local owner = adornee and adornee.Parent and Players:GetPlayerFromCharacter(adornee.Parent)
				table.insert(out, { over = if owner then owner.Name else "?", enabled = d.Enabled, sig = sig(d:FindFirstChild("Banner", true)) })
			end
		end
		return out
	end

	ops.boards = function()
		local out = {}
		local lobby = workspace:FindFirstChild("Lobby")
		local folder = lobby and lobby:FindFirstChild("Leaderboards")
		if not folder then
			return { error = "no Lobby.Leaderboards" }
		end
		for _, sg in ipairs(folder:GetDescendants()) do
			if sg:IsA("SurfaceGui") then
				local texts = {}
				for _, d in ipairs(sg:GetDescendants()) do
					if d:IsA("TextLabel") and d.Text ~= "" then
						table.insert(texts, d.Text)
					end
				end
				table.insert(out, (sg.Parent and sg.Parent.Name or "?") .. ": " .. table.concat(texts, " | "):sub(1, 500))
			end
		end
		return out
	end

	ops.progress = function()
		local P = ProgressUI()
		local s = P and P.state
		return { state = if s then string.sub(fmt(s), 1, 900) else "none", level = lp:GetAttribute("Level"), rank = lp:GetAttribute("RankName"),
			gold = lp:GetAttribute("Gold") }
	end

	ops.rankup = function()
		local g = gui:FindFirstChild("RankUpGui")
		local texts = {}
		if g then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("TextLabel") and d.Visible and d.Text ~= "" then
					table.insert(texts, d.Text)
				end
			end
		end
		return { exists = g ~= nil, enabled = g ~= nil and g.Enabled, texts = table.concat(texts, " | "):sub(1, 300), inTrain = ProgressUI().inTrain(),
			menuOpen = ClientState.menuOpen == true }
	end

	return function(op: string, arg: any): any
		local fn = ops[op]
		if not fn then
			return "unknown op " .. tostring(op)
		end
		return fn(arg or {})
	end
end
