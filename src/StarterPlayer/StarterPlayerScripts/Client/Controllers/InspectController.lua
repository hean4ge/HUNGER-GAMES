--[[
	InspectController - the weapon inspect screen (docs/design/CardMenusAndShop.md 2.3; the owner's reference with the
	"Passive Abilities!" tiles and the Kill Effect / Kill Icon slots, 19 Nov). Built from Shared.Cards ("Quiet cards").

	  Top left      ARMOURY · INSPECT, the weapon's name, its stars (4 and 5 in Sun) with the finish ("Superior · 4★"),
	                three line bars: damage, swing every, reach (from Shared.Stars, at your stars)
	  Middle        the weapon large, a live 3D view in its skin at your stars: drag (or the right stick) to turn
	  Right         Kill effect, Kill icon and Skin as large slots with their name and grade
	  Bottom left   the chosen slot's choices (Skin by default): owned ones to equip, the rest locked with where they
	                come from. Y (or USE ON ALL) puts a kill effect or icon on every weapon
	  Bottom right  TRAITS: what the weapon already does (ItemDefs fields; nothing new) and its family's skill (R)
	  Bottom bar    BACK and the Armoury action: "Buy 3★ · 800", "Raise to 4★ · 2,500", "Raise to 5★ · 6,000" (hold
	                0.6 s; RewardsService checks Gold, and that you stand at the Armoury board in the Lounge car)

	Opens from the Loadout's Bring and Look tabs (InspectController.open(weaponId, stars?, { from })). Also callable by
	the Armoury board and CASES. Only in the train. Cosmetics: Shared.CosmeticLooks (looks, skins on the model), the
	Shop remote's state (what is owned), the Looks remote ("equip"). Without them the slots show "none" and stay quiet.
	Gamepad: B back, Y use on all, LB / RB the slot, right stick turns. Touch: every target 44 px or more.
]]
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Catalog = require(Shared:WaitForChild("LoadoutCatalog"))
local Icons = require(Shared:WaitForChild("Icons"))
local Input = require(Shared:WaitForChild("Input"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Moves = require(Shared:WaitForChild("Moves"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Stars = require(Shared:WaitForChild("Stars"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local C = Theme.Colors
local F = Theme.Fonts

local InspectController = {}

local Controllers: { [string]: any } = {}
local screen: ScreenGui? = nil
local root: Frame? = nil
local page: Frame? = nil
local isOpen = false
local weaponId: string? = nil
local weaponStars = 1
local slotKind = "skin" -- the choices row: "skin" | "effect" | "icon"
local view: any = nil
local owned: { [string]: any } = {}
local hadMenu = false
local compact = false
local dimmedHere = false
local hidUnder: ScreenGui? = nil
local unbindShoulders: (() -> ())? = nil
local USE_DISTANCE = 14

local function optional(name: string): any
	local m = Shared:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok then
			return mod
		end
	end
	return nil
end

local function remote(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild(name)
	return if r and r:IsA("RemoteEvent") then r else nil
end

local function comma(n: number): string
	return Cards.comma(n)
end

local function ownedStars(id: string): number
	local raw = player:GetAttribute("KitArmoury")
	if type(raw) == "string" then
		for wid, s in string.gmatch(raw, "([%w_]+):(%d)") do
			if wid == id then
				return tonumber(s) or 0
			end
		end
	end
	return 0
end

local function plainFrame(name: string, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	if parent then
		f.Parent = parent
	end
	return f
end

local function list(parent: Instance, dir: Enum.FillDirection, gap: number, v: Enum.VerticalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	l.VerticalAlignment = v or Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

--------------------------------------------------------------------------------------------------------------------
-- Traits: only what the weapon already does (ItemDefs), never new power
--------------------------------------------------------------------------------------------------------------------

local function traitsOf(id: string, stars: number): { { icon: string, name: string, line: string } }
	local d = Stars.def(id, stars) or ItemDefs.get(id)
	local out = {}
	if not d then
		return out
	end
	local function add(icon: string, name: string, line: string)
		table.insert(out, { icon = icon, name = name, line = line })
	end
	if d.unseenDamage then
		add("unseen", "Unseen " .. math.floor(d.unseenDamage), "the first hit on someone facing away")
	end
	if d.sweepShare then
		add("sweep", string.format("Second in the arc %d%%", math.floor(d.sweepShare * 100 + 0.5)), "a second contender in the swing takes a share")
	end
	if d.armorPierce then
		add("armour_breaker", "Armour-breaker", string.format("armour stops %s as much", if d.armorPierce == 0.5 then "half" else tostring(d.armorPierce)))
	end
	if d.range and d.range >= 9 then
		add("reach", "Long reach", string.format("%.1f studs", d.range))
	end
	if d.climbSpeedMultiplier then
		add("climb", string.format("Climb \u{00D7}%g", d.climbSpeedMultiplier), "faster and longer with it in hand")
	end
	if d.kind == "Bow" and d.onTargetRange then
		add("draw_range", string.format("Draw to %d studs", d.onTargetRange), "a full draw stays on target this far")
	end
	if d.throwable and d.throwDamage then
		if d.throwFlight == "point" then
			add("big_throw", "Big throw " .. math.floor(d.throwDamage), "point first, no spin")
		elseif d.throwFlight == "flat" then
			add("flat_throw", "Flat throw " .. math.floor(d.throwDamage), "flies level and fast")
		elseif (d.throwSpin or 0) >= 18 then
			add("spin_throw", "Spinning throw " .. math.floor(d.throwDamage), "end over end")
		else
			add("heavy_throw", "Throw " .. math.floor(d.throwDamage), if d.quietThrow then "quiet; fetch it after" else "Guard and hold Attack")
		end
	end
	while #out > 3 do
		table.remove(out)
	end
	local family = Moves.family(id)
	local spec = Catalog.specialty(family)
	if spec then
		add(Icons.forSkill(spec.id), "R \u{00B7} " .. spec.skill.name, string.format("%s skill, %d s", spec.name, spec.skill.cooldown or 0))
	end
	return out
end

--------------------------------------------------------------------------------------------------------------------
-- Cosmetics (optional modules)
--------------------------------------------------------------------------------------------------------------------

local function CL(): any
	return optional("CosmeticLooks")
end

local function looks(): any
	local cl = CL()
	return if cl then cl.of(player) else nil
end

local function equippedFor(kind: string): string?
	local cl, l = CL(), looks()
	if not (cl and l and weaponId) then
		return nil
	end
	if kind == "skin" then
		return cl.skinFor(l, weaponId)
	elseif kind == "effect" then
		return cl.effectFor(l, weaponId)
	elseif kind == "icon" then
		return cl.iconFor(l, weaponId)
	end
	return nil
end

local function isOwned(item: any): boolean
	if item.free then
		return true
	end
	if owned[item.id] ~= nil then
		return true
	end
	return workspace:GetAttribute("DevAllCosmetics") == true and RunService:IsStudio()
end

local function choicesFor(kind: string): { any }
	local cl = CL()
	if not cl then
		return {}
	end
	local out = {}
	for _, item in ipairs(cl.list(kind)) do
		if kind ~= "skin" or cl.fits(item.id, weaponId) then
			table.insert(out, item)
		end
	end
	return out
end

local function equip(kind: string, id: string, allWeapons: boolean?)
	local r = remote("Looks")
	if not r then
		return
	end
	local slot = ({ skin = "skin", effect = "effect", icon = "icon" })[kind]
	r:FireServer("equip", { id = id, slot = slot, weapon = if allWeapons then "*" else weaponId })
	Sfx.play("UIClick", { pitch = 0.9 })
end

local function pictureFor(kind: string, item: any): ((Instance) -> ())?
	local cl = CL()
	if kind == "icon" and cl and item then
		return function(holder)
			pcall(cl.killIcon, item.id, 56, { Size = UDim2.fromScale(0.62, 0.62), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Parent = holder })
		end
	end
	return nil
end

--------------------------------------------------------------------------------------------------------------------
-- Building the page
--------------------------------------------------------------------------------------------------------------------

local rebuild: () -> ()

local function nearArmoury(): boolean
	local lobby = workspace:FindFirstChild("Lobby")
	local rewards = lobby and lobby:FindFirstChild("Rewards")
	local armoury = rewards and rewards:FindFirstChild("Armoury")
	local spot = armoury and armoury:FindFirstChild("PromptSpot", true)
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (spot and spot:IsA("BasePart") and rootPart and rootPart:IsA("BasePart")) then
		return false
	end
	return (rootPart.Position - spot.Position).Magnitude <= USE_DISTANCE
end

local function statBar(parent: Instance, order: number, name: string, alpha: number, value: string)
	local row = plainFrame("Stat" .. order, parent)
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, if compact then 18 else 26)
	Cards.label(name, { TextSize = if compact then 13 else 15, Color = C.Ink2, Size = UDim2.new(0.34, 0, 1, 0), Parent = row })
	Cards.bar({ Height = 4, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.36, 0, 0.5, 0), Size = UDim2.new(0.42, 0, 0, 4), Parent = row })
	Cards.setBar(row:FindFirstChild("Bar") :: Frame, alpha)
	Cards.label(value, { Font = F.Mono, TextSize = if compact then 13 else 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.2, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
end

local function buildPage()
	if page then
		page:Destroy()
	end
	if view then
		view = nil
	end
	local id = weaponId :: string
	local def = ItemDefs.get(id)
	if not def or not root then
		return
	end
	local mine = ownedStars(id)
	local st = if mine > 0 then mine else weaponStars
	local d = Stars.def(id, st) or def
	local p = Cards.panel({ Name = "Inspect", Size = UDim2.fromScale(1, 1), Parent = root })
	page = p
	local pad = Instance.new("UIPadding")
	local px = if compact then 12 else 48
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, px), UDim.new(0, px)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, if compact then 8 else 30), UDim.new(0, if compact then 8 else 26)
	pad.Parent = p

	-- the weapon (middle), live 3D: drag or the right stick turns it
	local stage = plainFrame("Stage", p)
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = if compact then UDim2.fromScale(0.5, 0.36) else UDim2.fromScale(0.44, 0.4)
	stage.Size = if compact then UDim2.fromScale(0.42, 0.62) else UDim2.fromScale(0.52, 0.62)
	stage.ZIndex = 1
	local okView, v, api = pcall(Cards.itemView, stage, id, { Stars = st, Turn = "drag", Force = true,
		Rotation = CFrame.Angles(0, math.rad(-20), math.rad(-30)) })
	if okView and v then
		view = api
		local cl, skin = CL(), equippedFor("skin")
		if cl and skin and api.model() then
			pcall(cl.applySkin, api.model(), skin)
		end
	end
	if not compact then
		Cards.hints({ { key = if Input.isGamepad() then "RS" else "drag", text = "to turn" } },
			{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Parent = stage })
	end

	-- top left: name, stars, bars
	local head = plainFrame("Head", p)
	head.Size = UDim2.fromOffset(if compact then 250 else 420, if compact then 150 else 250)
	list(head, Enum.FillDirection.Vertical, if compact then 2 else 6)
	Cards.label("ARMOURY  \u{00B7}  INSPECT", { Font = "SemiBold", TextSize = if compact then 12 else 15, Color = C.Ink2,
		Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = head })
	Cards.label(def.name, { Name = "WeaponName", Font = "Light", TextSize = if compact then 26 else 52, Size = UDim2.new(1, 0, 0, if compact then 30 else 60),
		LayoutOrder = 2, Parent = head })
	local starRow = plainFrame("StarRow", head)
	starRow.LayoutOrder = 3
	starRow.Size = UDim2.new(1, 0, 0, if compact then 22 else 30)
	list(starRow, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Center)
	Cards.stars(st, { Max = 5, TextSize = if compact then 18 else 26, LayoutOrder = 1, Parent = starRow })
	Cards.label(if mine > 0 then string.format("%s \u{00B7} %d\u{2605}", Stars.finish(st), st) else string.format("not owned \u{00B7} shown at %d\u{2605}", st),
		{ TextSize = if compact then 13 else 17, Color = C.Ink2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), LayoutOrder = 2, Parent = starRow })
	if d.kind == "Bow" then
		statBar(head, 4, "Damage", d.damageMax / 95, string.format("%g", d.damageMax))
		statBar(head, 5, "Full draw", math.clamp(1 - d.drawTime / 1.5, 0.05, 1), string.format("%.2f s", d.drawTime))
		statBar(head, 6, "On target", math.clamp((d.onTargetRange or 40) / 90, 0, 1), string.format("%d", d.onTargetRange or 0))
	else
		statBar(head, 4, "Damage", (d.damage or 0) / 60, string.format("%.1f", d.damage or 0))
		statBar(head, 5, "Swing every", math.clamp(1 - (d.cooldown or 1) / 1.4, 0.05, 1), string.format("%.2f s", d.cooldown or 0))
		statBar(head, 6, "Reach", math.clamp((d.range or 4) / 11, 0, 1), string.format("%.2f", d.range or 0))
	end

	-- right: Kill effect, Kill icon, Skin slots
	local cl = CL()
	local slotPx = if compact then 60 else 112
	local right = plainFrame("Slots", p)
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.Size = UDim2.fromOffset(if compact then 190 else 420, (slotPx + 10) * 3 + 50)
	local rl = list(right, Enum.FillDirection.Vertical, if compact then 6 else 14)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local slots = { { kind = "effect", title = "Kill effect", icon = "kill_effect" }, { kind = "icon", title = "Kill icon", icon = "kill_icon" },
		{ kind = "skin", title = "Skin", icon = "skin" } }
	for i, s in ipairs(slots) do
		local eq = equippedFor(s.kind)
		local item = eq and cl and cl.get(eq)
		local row = plainFrame("Row_" .. s.kind, right)
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, slotPx)
		local words = plainFrame("Words", row)
		words.Size = UDim2.new(1, -(slotPx + 14), 1, 0)
		local wl = list(words, Enum.FillDirection.Vertical, 2, Enum.VerticalAlignment.Center)
		wl.HorizontalAlignment = Enum.HorizontalAlignment.Right
		Cards.label(s.title, { Font = "SemiBold", TextSize = if compact then 14 else 20, Size = UDim2.new(1, 0, 0, if compact then 18 else 26),
			TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 1, Parent = words })
		local sub = if item then string.format("%s \u{00B7} %s", item.name, item.grade or "") elseif s.kind == "skin" then "Forged steel" else "None"
		Cards.label(sub, { TextSize = if compact then 12 else 15, Color = C.Ink2, Size = UDim2.new(1, 0, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 2, Parent = words })
		local tile
		if s.kind == "skin" then
			tile = Cards.slot({ Name = "Slot_skin", Size = UDim2.fromOffset(slotPx, slotPx), Item = id, ItemStars = st, NoName = true,
				Grade = item and item.grade, Turn = "none", Label = "" })
			local m = tile:FindFirstChild("Well") and tile.Well:FindFirstChildWhichIsA("ViewportFrame")
			local _ = m
		else
			tile = Cards.slot({ Name = "Slot_" .. s.kind, Size = UDim2.fromOffset(slotPx, slotPx), Empty = item == nil, Icon = if item then (if Icons.cell(item.id) then item.id else s.icon) else "none",
				Picture = pictureFor(s.kind, item), NoName = true, Grade = item and item.grade, Label = "" })
		end
		tile.AnchorPoint = Vector2.new(1, 0)
		tile.Position = UDim2.fromScale(1, 0)
		Cards.setState(tile, "Selected", slotKind == s.kind)
		tile.Activated:Connect(function()
			slotKind = s.kind
			Sfx.play("UIClick")
			rebuild()
		end)
		tile.Parent = row
	end
	if not compact then
		Cards.label("Kill effect and icon play when this weapon wins a fight.\nUse on all weapons: Y, or USE ON ALL.", { TextSize = 13, Color = C.Ink2,
			Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 9, Parent = right })
	end

	-- bottom: the chosen slot's choices (left) and the traits (right)
	local barH = if compact then 44 else 52
	local rowPx = if compact then 56 else 104
	local bottom = plainFrame("Bottom", p)
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.new(0, 0, 1, -(barH + (if compact then 6 else 20)))
	bottom.Size = UDim2.new(1, 0, 0, rowPx + 30)

	local left = plainFrame("Choices", bottom)
	left.Size = UDim2.new(0.5, -10, 1, 0)
	Cards.section(({ skin = "Skin", effect = "Kill effect", icon = "Kill icon" })[slotKind], { TextSize = if compact then 13 else 17,
		Tail = if compact then nil else "tap one you own to put it on", Parent = left })
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ScrollBarThickness = 0
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new()
	strip.Selectable = false
	strip.Position = UDim2.fromOffset(0, 28)
	strip.Size = UDim2.new(1, 0, 0, rowPx + 6)
	strip.Parent = left
	list(strip, Enum.FillDirection.Horizontal, if compact then 6 else 12, Enum.VerticalAlignment.Center)
	local spad = Instance.new("UIPadding")
	spad.PaddingLeft, spad.PaddingTop = UDim.new(0, 4), UDim.new(0, 3)
	spad.Parent = strip
	local current = equippedFor(slotKind)
	local tileW = if slotKind == "skin" then math.floor(rowPx * 1.5) else rowPx
	-- the default (no cosmetic) first
	local base = Cards.tile({ Name = "Choice_none", LayoutOrder = 0, Size = UDim2.fromOffset(tileW, rowPx),
		Item = if slotKind == "skin" then id else nil, ItemStars = st, Turn = "none",
		Icon = if slotKind == "skin" then nil else "none", Title = if slotKind == "skin" then "Forged steel" else "None", NameSize = 13,
		OnActivate = function()
			equip(slotKind, "")
		end })
	Cards.setState(base, "Equipped", if current == nil then "EQUIPPED" else false)
	base.Parent = strip
	for i, item in ipairs(choicesFor(slotKind)) do
		local have = isOwned(item)
		local tile = Cards.tile({ Name = "Choice_" .. item.id, LayoutOrder = i, Size = UDim2.fromOffset(tileW, rowPx), Grade = item.grade,
			Item = if slotKind == "skin" then id else nil, ItemStars = st, Turn = "none",
			Icon = if slotKind == "skin" then nil else (if slotKind == "icon" and pictureFor("icon", item) then nil else (if Icons.cell(item.id) then item.id elseif slotKind == "effect" then "kill_effect" else "kill_icon")),
			Picture = pictureFor(slotKind, item),
			Title = item.name, NameSize = 13, Label = if compact then "" else nil,
			OnActivate = function()
				if have then
					equip(slotKind, item.id)
				else
					Sfx.play("UIClick", { pitch = 0.7 })
				end
			end })
		if slotKind == "skin" and cl then
			local vp = tile:FindFirstChild("Well") and (tile :: any).Well:FindFirstChild("Picture")
			if vp and vp:IsA("ViewportFrame") then
				for _, m in ipairs(vp:GetChildren()) do
					if m:IsA("Model") then
						pcall(cl.applySkin, m, item.id)
					end
				end
			end
		end
		if not have then
			Cards.setState(tile, "Locked", if compact then "" else "CASES \u{00B7} Shelf")
		end
		Cards.setState(tile, "Equipped", if current == item.id then "EQUIPPED" else false)
		tile.Parent = strip
	end

	local rightB = plainFrame("Traits", bottom)
	rightB.AnchorPoint = Vector2.new(1, 0)
	rightB.Position = UDim2.fromScale(1, 0)
	rightB.Size = UDim2.new(0.5, -10, 1, 0)
	Cards.section("Traits", { TextSize = if compact then 13 else 17, Tail = "built in, always on", Parent = rightB })
	local traits = traitsOf(id, st)
	local tiles = plainFrame("Tiles", rightB)
	tiles.Position = UDim2.fromOffset(0, 28)
	tiles.Size = UDim2.new(0, (rowPx + 10) * #traits, 0, rowPx)
	list(tiles, Enum.FillDirection.Horizontal, if compact then 6 else 10)
	local lines = {}
	for i, t in ipairs(traits) do
		Cards.tile({ Name = "Trait" .. i, LayoutOrder = i, Size = UDim2.fromOffset(rowPx, rowPx), Icon = t.icon, NoName = true, Label = "",
			Selectable = compact }).Parent = tiles
		table.insert(lines, string.format("<b>%s</b>  \u{00B7}  %s", Theme.escape(t.name), Theme.escape(t.line)))
	end
	if not compact then
		local words = Cards.label(table.concat(lines, "\n"), { Name = "TraitLines", TextSize = 14, Color = C.Ink, RichText = true, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset((rowPx + 10) * #traits + 6, 30),
			Size = UDim2.new(1, -((rowPx + 10) * #traits + 6), 0, rowPx), Parent = rightB })
		words.TextTruncate = Enum.TextTruncate.None
	end

	-- the bar: note, BACK, the Armoury action
	local bar = plainFrame("Bar", p)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(1, 0, 0, barH)
	local bl = list(bar, Enum.FillDirection.Horizontal, 14, Enum.VerticalAlignment.Center)
	bl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local cfg = Rewards.config().Armoury
	local word, price, action = nil, nil, nil
	if Rewards.InPool[id] then
		if mine < 3 then
			word, price, action = "Buy 3\u{2605}", cfg.Buy3, "buy"
		elseif mine == 3 then
			word, price, action = "Raise to 4\u{2605}", cfg.Raise4, "raise"
		elseif mine == 4 then
			word, price, action = "Raise to 5\u{2605}", cfg.Raise5, "raise"
		end
	end
	local near = nearArmoury()
	local note = Cards.label(if action and not near then "Buy and raise at the Armoury board in the Lounge car"
		elseif action then "Hold to confirm" elseif mine >= 5 then "Masterwork: the best it can be" else "",
		{ Name = "Note", TextSize = 13, Color = C.Ink2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, barH), LayoutOrder = 1,
			TextTruncate = Enum.TextTruncate.None, Visible = not compact or not action, Parent = bar })
	if slotKind ~= "skin" and not compact then
		local all = Cards.button("Secondary", "Use on all", { Name = "UseOnAll", LayoutOrder = 2, Parent = bar })
		all.Activated:Connect(function()
			local eq = equippedFor(slotKind)
			if eq then
				equip(slotKind, eq, true)
			end
		end)
	end
	local back = Cards.button("Secondary", "Back", { Name = "Back", LayoutOrder = 3, Parent = bar })
	back.Activated:Connect(function()
		InspectController.close()
	end)
	if action then
		local b = Cards.button(if near then "Price" else "Off", word, { Name = "Armoury", Price = price, LayoutOrder = 4, Parent = bar })
		if not near then
			Cards.setButtonKind(b, "Off")
		end
		Cards.hold(b, 0.6, function()
			local r = remote("Rewards")
			if r and near then
				r:FireServer(action, id)
				note.Text = "Sent to the Armoury ..."
				Sfx.play("UIClick", { pitch = 0.8 })
			end
		end)
	end
	local _ = note
	if Input.isGamepad() then
		task.defer(function()
			GuiService.SelectedObject = back
		end)
	end
end

rebuild = function()
	if isOpen then
		buildPage()
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Open and close
--------------------------------------------------------------------------------------------------------------------

local function onPad(_, state: Enum.UserInputState, io: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if io.KeyCode == Enum.KeyCode.ButtonB then
		InspectController.close()
	elseif io.KeyCode == Enum.KeyCode.ButtonY then
		local eq = equippedFor(slotKind)
		if eq and slotKind ~= "skin" then
			equip(slotKind, eq, true)
		end
	end
	return Enum.ContextActionResult.Sink
end

function InspectController.isOpen(): boolean
	return isOpen
end

function InspectController.open(id: string, stars: number?, opts: { [string]: any }?)
	if not (screen and root) or not ItemDefs.get(id) then
		return
	end
	if ClientState.inArena and not (RunService:IsStudio() and player:GetAttribute("CardsTestForce") == true) then
		return
	end
	weaponId = id
	weaponStars = Stars.clamp(stars or 3)
	slotKind = "skin"
	local camera = workspace.CurrentCamera
	local v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	compact = Theme.isSmallScreen(v) or v.Y < 560 or player:GetAttribute("LoadoutTouchLayout") == true
	local opening = not isOpen
	if not isOpen then
		isOpen = true
		hadMenu = ClientState.menuOpen
		ClientState.menuOpen = true
		-- the screen underneath (the Loadout) steps aside while this is up: one panel at a time
		local pg = player:FindFirstChild("PlayerGui")
		local under = pg and pg:FindFirstChild("Loadout")
		if under and under:IsA("ScreenGui") and under.Enabled then
			under.Enabled = false
			hidUnder = under
		end
		dimmedHere = true -- (Cards.dimWorld counts: the blur stays while any screen holds it)
		Cards.dimWorld(true)
		ContextActionService:BindActionAtPriority("InspectPad", onPad, false, Enum.ContextActionPriority.High.Value + 30,
			Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonX)
		unbindShoulders = Cards.bindShoulders("InspectSlots", function()
			slotKind = ({ skin = "icon", icon = "effect", effect = "skin" })[slotKind]
			rebuild()
		end, function()
			slotKind = ({ skin = "effect", effect = "icon", icon = "skin" })[slotKind]
			rebuild()
		end)
		-- the right stick turns the weapon
		task.spawn(function()
			while isOpen do
				local dt = RunService.RenderStepped:Wait()
				if view then
					local stick = Vector2.zero
					for _, s in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
						if s.KeyCode == Enum.KeyCode.Thumbstick2 then
							stick = Vector2.new(s.Position.X, s.Position.Y)
						end
					end
					if stick.Magnitude > 0.2 then
						view.turn(stick.X * dt * 140, -stick.Y * dt * 90)
					end
				end
			end
		end)
		local shop = remote("Shop")
		if shop then
			shop:FireServer("state")
		end
	end
	screen.Enabled = true
	buildPage()
	if opening and page then
		QuietUI.reveal(page, { rise = QuietUI.Motion.Rise }) -- (ui-motion) fade and rise in
	end
	local _ = opts
end

function InspectController.close()
	if not isOpen then
		return
	end
	isOpen = false
	ContextActionService:UnbindAction("InspectPad")
	if unbindShoulders then
		unbindShoulders()
		unbindShoulders = nil
	end
	-- (ui-motion) the page fades and sinks out, then goes; the screen turns off unless it opened again meanwhile
	local leaving = page
	page = nil
	view = nil
	if leaving then
		QuietUI.conceal(leaving, { rise = QuietUI.Motion.Rise }, function()
			leaving:Destroy()
			if not isOpen and screen then
				screen.Enabled = false
			end
		end)
	elseif screen then
		screen.Enabled = false
	end
	if dimmedHere then
		Cards.dimWorld(false)
	end
	if hidUnder then
		hidUnder.Enabled = true
		hidUnder = nil
	end
	ClientState.menuOpen = hadMenu
	Sfx.play("UIClick", { pitch = 1.1 })
	-- give the gamepad back to the screen underneath
	local loadout = Controllers.LoadoutController
	if loadout and type(loadout.isOpen) == "function" and loadout.isOpen() and Input.isGamepad() then
		local pg = player:FindFirstChild("PlayerGui")
		local lg = pg and pg:FindFirstChild("Loadout")
		local insp = lg and lg:FindFirstChild("Inspect", true)
		local target = lg and (lg:FindFirstChild("Cancel", true) or lg:FindFirstChild("Done", true))
		local _ = insp
		if target and target:IsA("GuiObject") then
			GuiService.SelectedObject = target
		end
	end
end

function InspectController.Init(controllers)
	Controllers = controllers
end

function InspectController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "Inspect"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 9
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	local r = Instance.new("Frame")
	r.Name = "Root"
	r.BackgroundTransparency = 1
	r.Size = UDim2.fromScale(1, 1)
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = r
	r.Parent = gui
	gui.Parent = playerGui
	screen, root = gui, r
	task.spawn(pcall, QuietUI.bindRoot, gui)
	-- what is owned (CASES' state) and what is worn (LooksJson): repaint when either changes
	task.spawn(function()
		local shop = ReplicatedStorage:WaitForChild("Remotes", 30) and remote("Shop")
		if shop then
			shop.OnClientEvent:Connect(function(kind, state)
				if kind == "state" and type(state) == "table" and type(state.owned) == "table" then
					owned = state.owned
					rebuild()
				end
			end)
		end
		local rw = remote("Rewards")
		if rw then
			rw.OnClientEvent:Connect(function(kind, text)
				if kind == "line" and isOpen and page and type(text) == "string" then
					local note = page:FindFirstChild("Note", true)
					if note and note:IsA("TextLabel") then
						note.Text = text
					end
				end
			end)
		end
	end)
	player:GetAttributeChangedSignal("LooksJson"):Connect(rebuild)
	player:GetAttributeChangedSignal("KitArmoury"):Connect(rebuild)
	ClientState.lifeChanged:Connect(function()
		if ClientState.inArena and player:GetAttribute("CardsTestForce") ~= true then
			InspectController.close()
		end
	end)
end

return InspectController
