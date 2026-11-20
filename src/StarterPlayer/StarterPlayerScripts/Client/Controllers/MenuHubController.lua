--[[
	MenuHubController - the train's menu (docs/design/CardMenusAndShop.md 2.0; the owner, 19 and 20 Nov: every menu
	where a player chooses, owns, earns or buys something is cards, and they all open from one place).

	THE BAR (in the train and the Training Centre only; never in a round, on the plate or while a menu is up)
	  A column of seven small cards on the right edge, each an icon, a short word and (keyboard) its number key:
	    1 Loadout · 2 Cases · 3 Pass · 4 Daily · 5 Ranks · 6 Boards · 7 Inspect
	  A Sun dot on a card when something waits there (a daily reward, a Season tier to claim, crates to open).
	  Phones: one MENU card instead (the column would sit under the jump button); it opens the hub.

	THE HUB (a card screen built on ProgressUI.screen, like Season / Daily / Ranks)
	  Eight big cards: the seven above plus Settings, each with its picture, its name, one live fact ("Claim day 3",
	  "Tier 4 · 620 / 1,000 XP", "3 crates to open", "Recruit · Level 1", "Longsword ★★★") and one action (OPEN, or the
	  Sun CLAIM when something waits). A, click or tap opens it; B / Esc / the X close.

	INPUT (Shared.Input action "Hub", bound only while the bar shows)
	  Keyboard 1 to 7 open the screens directly (in the Training Centre's hall the hotbar keeps them when it binds them:
	  this action sits below the default priority). Gamepad D-pad down opens the hub (only while no GUI selection is up,
	  so it never steals the D-pad from a menu). Touch: the bar's cards (InputCheck: gui:MenuHub.Root.Bar).
	  Settings keeps M / D-pad up (SettingsController); the Loadout keeps L / D-pad right (LoadoutController).

	Public: MenuHubController.open(), close(), isOpen(), go(key), barVisible()
	Studio only: LocalPlayer attribute MenuTest = "open" | "close" | "go:<key>" drives it in a playtest (execute_luau
	runs its own module copies, so tests reach the live one through this attribute); it is cleared after each use.
]]
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Icons = require(Shared:WaitForChild("Icons"))
local Input = require(Shared:WaitForChild("Input"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Kits = require(Shared:WaitForChild("Kits"))
local Progression = require(Shared:WaitForChild("Progression"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Theme = require(Shared:WaitForChild("Theme"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local ProgressUI = require(Client:WaitForChild("ProgressUI"))

local player = Players.LocalPlayer
local C = Theme.Colors

local MenuHubController = {}

local Controllers: { [string]: any } = {}

-- key, word on the bar, name on the hub card, icon, number key
local ENTRIES = {
	{ key = "loadout", word = "Loadout", long = "Loadout", icon = "archer", num = Enum.KeyCode.One }, -- (hunt2_1) paintBar swaps in the kit's picture
	{ key = "cases", word = "Cases", long = "Cases", icon = "crate", num = Enum.KeyCode.Two },
	{ key = "pass", word = "Pass", long = "Season Track", icon = "season", num = Enum.KeyCode.Three },
	{ key = "daily", word = "Daily", long = "Daily reward", icon = "daily", num = Enum.KeyCode.Four },
	{ key = "ranks", word = "Ranks", long = "Ranks", icon = "ranks", num = Enum.KeyCode.Five },
	{ key = "boards", word = "Boards", long = "Leaderboards", icon = "boards", num = Enum.KeyCode.Six },
	{ key = "inspect", word = "Inspect", long = "Inspect a weapon", icon = "inspect", num = Enum.KeyCode.Seven },
}
local SETTINGS = { key = "settings", word = "Settings", long = "Settings", icon = "gear" }
local BY_KEY: { [string]: any } = {}
local BY_NUM: { [Enum.KeyCode]: string } = {}
for i, e in ipairs(ENTRIES) do
	e.order = i
	BY_KEY[e.key] = e
	BY_NUM[e.num] = e.key
end
BY_KEY.settings = SETTINGS

local gui: ScreenGui? = nil
local root: Frame? = nil
local bar: Frame? = nil
local barTiles: { [string]: TextButton } = {}
local barPhone: boolean? = nil
local hub: any = nil -- the ProgressUI screen
local hubCards: { [string]: TextButton } = {}
local shopState: { [string]: any } = {}
local boundHub = ""
local padOpened = false -- the hub was opened with D-pad down: the focus goes on its first card
local forcePhoneBar: boolean? = nil -- Studio pictures only (MenuTest "bar:phone" / "bar:pc" / "bar:auto")

--------------------------------------------------------------------------------------------------------------------
-- Where the menu may show
--------------------------------------------------------------------------------------------------------------------

local function forced(): boolean
	return RunService:IsStudio() and player:GetAttribute("CardsTestForce") == true
end

local function inTrain(): boolean
	if forced() then
		return true
	end
	if not ProgressUI.inTrain() then
		return false
	end
	if player:GetAttribute("InArena") == true or player:GetAttribute("InRedRoom") == true or player:GetAttribute("Frozen") == true then
		return false
	end
	return true
end

local function otherScreenOpen(): boolean
	local shop = Controllers.ShopController
	if shop and shop.isOpen == true then
		return true
	end
	for _, name in ipairs({ "LoadoutController", "InspectController", "PrepareController" }) do
		local c = Controllers[name]
		if c and type(c.isOpen) == "function" and c.isOpen() then
			return true
		end
	end
	return ProgressUI.anyOpen()
end

function MenuHubController.barVisible(): boolean
	return bar ~= nil and bar.Visible
end

-- (final-shop, 20 Nov) HOW TO PLAY (LobbyController) has the same right edge: while that sheet shows, the bar steps
-- aside instead of drawing under it (H closes the sheet and the bar comes back)
local function howToShown(): boolean
	local lobby = player:FindFirstChildOfClass("PlayerGui") and player.PlayerGui:FindFirstChild("Lobby")
	local root = lobby and lobby:FindFirstChild("Root")
	local howTo = root and root:FindFirstChild("HowTo")
	return lobby ~= nil and lobby:IsA("ScreenGui") and lobby.Enabled and howTo ~= nil and howTo:IsA("GuiObject")
		and howTo.Visible
end

local function barWanted(): boolean
	return inTrain() and not ClientState.menuOpen and not otherScreenOpen()
end

--------------------------------------------------------------------------------------------------------------------
-- Live facts
--------------------------------------------------------------------------------------------------------------------

local function heldCrates(): number
	local n = 0
	for _, c in pairs(shopState.held or {}) do
		n += tonumber(c) or 0
	end
	return n
end

local function armoury(): { { id: string, stars: number } }
	local out = {}
	local raw = player:GetAttribute("KitArmoury")
	if type(raw) == "string" then
		for id, stars in string.gmatch(raw, "([%w_]+):(%d)") do
			if ItemDefs.get(id) then
				table.insert(out, { id = id, stars = tonumber(stars) or 1 })
			end
		end
	end
	return out
end

-- The weapon Inspect opens on: the one you bring, else your best Armoury weapon, else the Longsword at 3 stars (what
-- the Armoury sells first), so the screen always has something to show
local function inspectTarget(): (string, number, boolean)
	local owned = armoury()
	local bring = player:GetAttribute("KitBring")
	for _, w in ipairs(owned) do
		if w.id == bring then
			return w.id, w.stars, true
		end
	end
	table.sort(owned, function(a, b)
		return a.stars > b.stars
	end)
	if owned[1] then
		return owned[1].id, owned[1].stars, true
	end
	return "sword", 3, false
end

local function seasonState(): { [string]: any }?
	local s = ProgressUI.state
	return s and s.season
end

local function waiting(key: string): number
	if key == "daily" then
		local d = Controllers.DailyController
		return if d and type(d.claimable) == "function" and d.claimable() then 1 else 0
	elseif key == "pass" then
		local s = Controllers.SeasonController
		return if s and type(s.claimableCount) == "function" then s.claimableCount() else 0
	elseif key == "cases" then
		return heldCrates()
	end
	return 0
end

local function fact(key: string): string
	if key == "loadout" then
		local kit = Kits.get(player:GetAttribute("Kit")) or Kits.default()
		local bring = player:GetAttribute("KitBring")
		local def = type(bring) == "string" and bring ~= "" and ItemDefs.get(bring)
		return string.format("%s kit · %s", kit.name, if def then def.name else "kit weapon")
	elseif key == "cases" then
		local n = heldCrates()
		if n > 0 then
			return string.format("%d crate%s to open", n, if n == 1 then "" else "s")
		end
		return string.format("%s Gold · crates, Strongboxes, the Armoury", Cards.comma(tonumber(player:GetAttribute("Gold")) or 0))
	elseif key == "pass" then
		local s = seasonState()
		if not s then
			return "Season one · The First Ride"
		end
		local n = waiting("pass")
		if n > 0 then
			return string.format("Tier %d · %d to claim", s.tier or 0, n)
		end
		return string.format("Tier %d · %s / %s XP", s.tier or 0, Progression.comma(s.into or 0), Progression.comma(s.need or 1000))
	elseif key == "daily" then
		local st = ProgressUI.state
		local d = st and st.daily
		if d and d.claimable then
			return string.format("Claim day %d", d.day or 1)
		elseif d then
			return "Next reward in " .. Cards.clock(d.nextIn or Progression.secondsToNextDay())
		end
		return "Seven days of rewards"
	elseif key == "ranks" then
		return string.format("%s · Level %d", tostring(player:GetAttribute("RankName") or "Recruit"),
			tonumber(player:GetAttribute("Level")) or 1)
	elseif key == "boards" then
		return "Wins, eliminations, level · this week and all time"
	elseif key == "inspect" then
		local id, stars, owned = inspectTarget()
		local def = ItemDefs.get(id)
		return string.format("%s %s%s", if def then def.name else id, string.rep("\u{2605}", stars), if owned then "" else " · in the Armoury")
	elseif key == "settings" then
		return "Controls, sound, picture"
	end
	return ""
end

--------------------------------------------------------------------------------------------------------------------
-- Opening a screen
--------------------------------------------------------------------------------------------------------------------

local function openTarget(key: string): boolean
	local c = Controllers
	if key == "loadout" then
		local l = c.LoadoutController
		if l and l.open then
			l.open()
			-- (kitui) the Loadout entry opens the Prepare screen first
			local p = c.PrepareController
			if p and type(p.isOpen) == "function" and p.isOpen() then
				return true
			end
			return l.isOpen and l.isOpen() or false
		end
	elseif key == "cases" then
		local s = c.ShopController
		if s and s.open then
			return s.open(nil, if heldCrates() > 0 then "open" else "buy") == true
		end
	elseif key == "pass" then
		local s = c.SeasonController
		return s ~= nil and s.open ~= nil and s.open() == true
	elseif key == "daily" then
		local d = c.DailyController
		return d ~= nil and d.open ~= nil and d.open() == true
	elseif key == "ranks" then
		local r = c.RanksController
		return r ~= nil and r.open ~= nil and r.open("level") == true
	elseif key == "boards" then
		local r = c.RanksController
		return r ~= nil and r.open ~= nil and r.open("boards") == true
	elseif key == "inspect" then
		local i = c.InspectController
		if i and i.open then
			local id, stars = inspectTarget()
			i.open(id, stars, { from = "hub" })
			return i.isOpen and i.isOpen() or false
		end
	elseif key == "settings" then
		local s = c.SettingsController
		if s and s.open then
			s.open()
			return true
		end
	end
	return false
end

function MenuHubController.go(key: string): boolean
	if not BY_KEY[key] or not inTrain() then
		return false
	end
	if hub and hub.isOpen() then
		hub.close()
	end
	local ok = openTarget(key)
	if ok then
		Sfx.play("UIClick", { pitch = 1.05 })
	end
	return ok
end

--------------------------------------------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------------------------------------------

local function makeDot(parent: GuiObject)
	local dot = Instance.new("Frame")
	dot.Name = "Waiting"
	dot.BackgroundColor3 = C.Sun
	dot.BorderSizePixel = 0
	dot.Size = UDim2.fromOffset(9, 9)
	dot.AnchorPoint = Vector2.new(1, 0)
	dot.Position = UDim2.new(1, -5, 0, 5)
	dot.ZIndex = 9
	dot.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	dot.Parent = parent
	return dot
end

local function barTile(e: { [string]: any }, size: number, onActivate: () -> ()): TextButton
	local tile = Cards.surface({ Name = e.key, Size = UDim2.fromOffset(size, size), LayoutOrder = e.order or 0, OnActivate = onActivate })
	Icons.make(e.icon, { Name = "Icon", Size = UDim2.fromOffset(math.floor(size * 0.44), math.floor(size * 0.44)),
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, math.floor(size * 0.12)), Parent = tile })
	local word = Cards.label(e.word, { Name = "Word", Font = "SemiBold", TextSize = 12, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -4, 0, 14), Parent = tile })
	word.TextXAlignment = Enum.TextXAlignment.Center
	if e.num then
		local num = Cards.label(tostring(e.order), { Name = "Num", Font = "Mono", TextSize = 11, Color = C.Ink2,
			Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(12, 13), Parent = tile })
		num.TextTransparency = 0.25
	end
	makeDot(tile)
	return tile
end

local function buildBar()
	if not root then
		return
	end
	local phone = Cards.metrics().phone
	if forcePhoneBar ~= nil then
		phone = forcePhoneBar
	end
	if bar and barPhone == phone then
		return
	end
	if bar then
		bar:Destroy()
	end
	table.clear(barTiles)
	barPhone = phone
	local holder = Instance.new("Frame")
	holder.Name = "Bar"
	holder.BackgroundTransparency = 1
	holder.Visible = false
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = holder
	if phone then
		-- one MENU card on the right edge, above the jump button and clear of the top line (the left holds the joystick
		-- and the title)
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -8, 0.36, 0)
		holder.Size = UDim2.fromOffset(52, 52)
		barTiles.menu = barTile({ key = "menu", word = "Menu", icon = "menu", order = 1 }, 52, function()
			MenuHubController.open()
		end)
		barTiles.menu.Parent = holder
	else
		local size = 54
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -14, 0.42, 0)
		holder.Size = UDim2.fromOffset(size, #ENTRIES * (size + 6) + 30)
		local hint = Cards.hints({ { key = "\u{2193}", text = "Menu" } }, { Name = "PadHint", LayoutOrder = 0, Visible = false })
		hint.Parent = holder
		for _, e in ipairs(ENTRIES) do
			local key = e.key
			local tile = barTile(e, size, function()
				MenuHubController.go(key)
			end)
			tile.Parent = holder
			barTiles[key] = tile
		end
	end
	holder.Parent = root
	bar = holder
end

-- (hunt2_1) the Loadout tile and card show the chosen kit's picture (as the PREPARE button does): the old satchel glyph
-- read as a padlock at this size
local function loadoutIcon(): string
	local kit = Kits.get(player:GetAttribute("Kit")) or Kits.default()
	return Icons.forKit(kit.id)
end

local function paintBar()
	if not bar then
		return
	end
	local lt = barTiles.loadout
	if lt then
		local want = loadoutIcon()
		local old = lt:FindFirstChild("Icon")
		if old and old:IsA("GuiObject") and lt:GetAttribute("IconKit") ~= want then
			lt:SetAttribute("IconKit", want)
			local size, pos, anchor = old.Size, old.Position, old.AnchorPoint
			old:Destroy()
			Icons.make(want, { Name = "Icon", Size = size, Position = pos, AnchorPoint = anchor, Parent = lt })
		end
	end
	local keyboard = not Input.isGamepad() and not Input.isTouch()
	local any = 0
	for key, tile in pairs(barTiles) do
		local n = if key == "menu" then 0 else waiting(key)
		any += n
		local dot = tile:FindFirstChild("Waiting")
		if dot then
			dot.Visible = n > 0
		end
		local num = tile:FindFirstChild("Num")
		if num then
			num.Visible = keyboard
		end
	end
	if barTiles.menu then
		local dot = barTiles.menu:FindFirstChild("Waiting")
		if dot then
			dot.Visible = waiting("daily") + waiting("pass") + waiting("cases") > 0
		end
	end
	local hint = bar:FindFirstChild("PadHint")
	if hint then
		hint.Visible = Input.isGamepad()
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The hub
--------------------------------------------------------------------------------------------------------------------

-- (fixesUI, 20 Nov) the gamepad focus on a hub card: Style A "Quiet", a thin Sun (amber) line just outside the card
-- and a faint Ink line a little further out, no fill. The engine's own SelectionImageObject did not show in the last
-- check, so the ring is the card's own child, shown while the card holds GuiService.SelectedObject (SelectionGained /
-- SelectionLost); the card's SelectionImageObject is an empty Frame so the engine adds no second outline.
local function focusRing(): Frame
	local root = Instance.new("Frame")
	root.Name = "HubFocus"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	local function line(name: string, out: number, color: Color3, transparency: number, thick: number, radius: number)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Position = UDim2.fromOffset(-out, -out)
		f.Size = UDim2.new(1, out * 2, 1, out * 2)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, radius)
		c.Parent = f
		local st = Instance.new("UIStroke")
		st.Color = color
		st.Transparency = transparency
		st.Thickness = thick
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = f
		f.Parent = root
	end
	line("Amber", 3, C.Sun, 0, 1.5, 10)
	line("Ink", 6, C.Ink, 0.7, 1, 13)
	return root
end

-- the focus goes on the first card when a gamepad is in use and nothing in the hub holds it yet
local function focusHub(force: boolean?)
	if not (hub and hub.isOpen()) then
		return
	end
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(hub.gui) then
		return
	end
	if force or Input.isGamepad() then
		local first = hubCards.loadout
		if first and first.Parent then
			GuiService.SelectedObject = first
		end
	end
end

local function fillHub()
	if not hub then
		return
	end
	local body = hub.body
	for _, child in ipairs(body:GetChildren()) do
		child:Destroy()
	end
	table.clear(hubCards)
	local phone = hub.phone
	local m = Cards.metrics()
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	-- (ui-motion, Figma 01) room for the hints row along the bottom
	local hintsH = if Input.isTouch() then 0 else 30
	scroll.Size = UDim2.new(1, 0, 1, -hintsH)
	scroll.ScrollBarThickness = 4 -- (final-shop) shown only when the cards overflow
	scroll.ScrollBarImageColor3 = C.Ink
	scroll.ScrollBarImageTransparency = 0.6
	scroll.Selectable = false
	scroll.AutomaticCanvasSize = if phone then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = if phone then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
	scroll.Parent = body
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	if phone then
		grid.CellSize = UDim2.fromOffset(150, 236)
		grid.CellPadding = UDim2.fromOffset(8, 8)
		grid.FillDirection = Enum.FillDirection.Vertical
		grid.FillDirectionMaxCells = 1
		grid.VerticalAlignment = Enum.VerticalAlignment.Center
	else
		local w = if m.class == "TV" then 250 else 236
		-- (final-shop, 20 Nov) both rows fit a short window (about 750 px): the cards give up picture height, down to
		-- 210 px, before the second row's OPEN buttons would hide below the panel
		local h = 252
		local scaleObj = hub.gui:FindFirstChild("Root") and hub.gui.Root:FindFirstChild("Scale")
		local s = if scaleObj and scaleObj:IsA("UIScale") and scaleObj.Scale > 0 then scaleObj.Scale else 1
		local avail = body.AbsoluteSize.Y / s
		if avail > 0 then
			h = math.clamp(math.floor((avail - hintsH - 16 - 18) / 2), 190, 232)
		end
		grid.CellSize = UDim2.fromOffset(w, h)
		grid.CellPadding = UDim2.fromOffset(18, 18)
		grid.FillDirectionMaxCells = 4
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	grid.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = scroll

	local list = table.clone(ENTRIES)
	table.insert(list, SETTINGS)
	for i, e in ipairs(list) do
		local key = e.key
		local n = waiting(key)
		local function go()
			MenuHubController.go(key)
		end
		-- (ui-motion, Figma 01) the whole card is the button: its name, one fact (Sun when something waits there) and a
		-- Sun dot; the keys are listed once in the hints along the bottom
		local card = Cards.card({
			Name = key,
			Title = e.long,
			Icon = if key == "loadout" then loadoutIcon() else e.icon,
			Big = true,
			Text = fact(key),
			WellHeight = 0.58,
			LayoutOrder = i,
			OnActivate = go,
		})
		if n > 0 then
			Cards.setState(card, "New", true)
			local factLabel = card:FindFirstChild("Text", true)
			if factLabel and factLabel:IsA("TextLabel") then
				factLabel.TextColor3 = C.Sun
			end
		end
		local ring = focusRing()
		ring.Name = "FocusRing"
		ring.Visible = GuiService.SelectedObject == card
		ring.ZIndex = 50
		ring.Parent = card
		card.SelectionGained:Connect(function()
			ring.Visible = true
		end)
		card.SelectionLost:Connect(function()
			ring.Visible = false
		end)
		local blank = Instance.new("Frame")
		blank.Name = "NoEngineRing"
		blank.BackgroundTransparency = 1
		blank.BorderSizePixel = 0
		blank.Size = UDim2.fromScale(0, 0)
		card.SelectionImageObject = blank
		card.Selectable = true
		card.Parent = scroll
		hubCards[key] = card
	end
	if hintsH > 0 then
		local hints = if Input.isGamepad() then { { key = "B", text = "close" }, { key = "A", text = "open" } }
			else { { key = "Esc", text = "close" }, { key = "1-7", text = "open" }, { key = "M", text = "settings" } }
		Cards.hints(hints, { Name = "Hints", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = body })
	end
	hub.sub.Text = if phone then "" else "Everything you choose, own, earn or buy."
	-- (fixesUI) after a frame, so the cards have their place in the opened screen before the engine draws the ring
	local force = padOpened
	padOpened = false
	task.defer(focusHub, force)
end

function MenuHubController.isOpen(): boolean
	return hub ~= nil and hub.isOpen()
end

function MenuHubController.open(): boolean
	if not hub or not inTrain() then
		return false
	end
	if hub.isOpen() then
		return true
	end
	-- the hub builds once per device class (a phone's cards scroll sideways)
	local phone = Cards.metrics().phone
	if phone ~= hub.phone then
		hub.gui:Destroy()
		hub = ProgressUI.screen("MenuHubGui", "Menu", { MaxSize = Vector2.new(1100, 640) })
		hub.onOpen(fillHub)
	end
	local ok = hub.open()
	if ok then
		Sfx.play("UIClick", { pitch = 1.1 })
	end
	return ok
end

function MenuHubController.close()
	if hub then
		hub.close()
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------------------------------------------

local function onHubKey(state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult?
	if state ~= Enum.UserInputState.Begin or not io then
		return Enum.ContextActionResult.Pass
	end
	if io.KeyCode == Enum.KeyCode.DPadDown then
		if GuiService.SelectedObject ~= nil or ClientState.menuOpen or not inTrain() then
			return Enum.ContextActionResult.Pass
		end
		padOpened = true
		MenuHubController.open()
		return Enum.ContextActionResult.Sink
	end
	local key = BY_NUM[io.KeyCode]
	if not key then
		return Enum.ContextActionResult.Pass
	end
	if (ClientState.menuOpen and not MenuHubController.isOpen()) or not inTrain() then
		return Enum.ContextActionResult.Pass
	end
	MenuHubController.go(key)
	return Enum.ContextActionResult.Sink
end

local function syncKeys(show: boolean)
	-- bound while the bar shows or the hub is up (numbers also jump from the hub); D-pad down only with no selection
	local want = ""
	if show or MenuHubController.isOpen() then
		want = if GuiService.SelectedObject == nil and show then "all" else "keys"
	end
	if want == boundHub then
		return
	end
	boundHub = want
	if want == "" then
		Input.unbind("Hub")
		return
	end
	local keys = {}
	for _, e in ipairs(ENTRIES) do
		table.insert(keys, e.num)
	end
	if want == "all" then
		table.insert(keys, Enum.KeyCode.DPadDown)
	end
	Input.bind("Hub", onHubKey, { keys = keys, priority = 1500 })
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function MenuHubController.Init(controllers)
	Controllers = controllers
	ProgressUI.Controllers = ProgressUI.Controllers or controllers
end

local function studioHook()
	if not RunService:IsStudio() then
		return
	end
	player:GetAttributeChangedSignal("MenuTest"):Connect(function()
		local v = player:GetAttribute("MenuTest")
		if type(v) ~= "string" or v == "" then
			return
		end
		player:SetAttribute("MenuTest", nil)
		if v == "open" then
			MenuHubController.open()
		elseif v == "close" then
			MenuHubController.close()
		elseif string.sub(v, 1, 3) == "go:" then
			MenuHubController.go(string.sub(v, 4))
		elseif string.sub(v, 1, 4) == "bar:" then
			local mode = string.sub(v, 5)
			forcePhoneBar = if mode == "phone" then true elseif mode == "pc" then false else nil
			buildBar()
			paintBar()
		end
		player:SetAttribute("MenuTestResult", HttpService:JSONEncode({ hub = MenuHubController.isOpen(),
			bar = MenuHubController.barVisible(), menuOpen = ClientState.menuOpen == true, at = os.clock() }))
	end)
end

function MenuHubController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "MenuHub"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.DisplayOrder = 7
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local r = Instance.new("Frame")
	r.Name = "Root"
	r.BackgroundTransparency = 1
	r.Size = UDim2.fromScale(1, 1)
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = r
	r.Parent = screen
	screen.Parent = playerGui
	gui, root = screen, r
	task.spawn(pcall, Theme.bindRoot, screen)
	buildBar()

	hub = ProgressUI.screen("MenuHubGui", "Menu", { MaxSize = Vector2.new(1100, 640) })
	hub.onOpen(fillHub)
	-- Studio pictures: workspace ProgressTestOpen = "hub" or "hub:phone" (ProgressUI's phone preview frame)
	ProgressUI.openers = ProgressUI.openers or {}
	ProgressUI.openers.hub = function()
		if hub and hub.isOpen() then
			hub.close()
		end
		MenuHubController.open()
	end

	-- what CASES knows (crates waiting to open)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
		local shop = remotes and remotes:WaitForChild("Shop", 60)
		if shop and shop:IsA("RemoteEvent") then
			shop.OnClientEvent:Connect(function(kind, data)
				if kind == "state" and type(data) == "table" then
					shopState = data
				end
			end)
			shop:FireServer("state")
		end
	end)

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			buildBar()
		end)
	end
	Input.deviceChanged:Connect(function()
		buildBar()
		paintBar()
		focusHub() -- (fixesUI) a pad picked up with the hub open: the focus ring shows on its first card
	end)
	studioHook()

	-- a cheap look four times a second: the bar shows only where it may, and its dots follow what waits
	local last = 0
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		if t - last < 0.25 then
			return
		end
		last = t
		local wanted = barWanted()
		local show = wanted and not howToShown() -- the keys stay bound while HOW TO PLAY covers the bar
		if bar and bar.Visible ~= show then
			bar.Visible = show
		end
		if show then
			paintBar()
		end
		syncKeys(wanted)
	end)
end

return MenuHubController
