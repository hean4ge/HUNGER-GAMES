--[[
	LoadoutController - the one place to choose what you take into the next round (docs/design/Combat_v3.md section 3.2;
	the owner, 19 Nov: "you need to fix the way you can choose kits or skills beforehand"). Replaces KitController's
	KIT / BRING line and its hidden K / B keys. Quiet style: thin text and lines on the picture, no boxes, no pop-ups.

	IN THE TRAIN
	  The summary line (bottom centre on a PC, under the status lines on touch), Ink at 72%:
	    Forager · Twin-Bit Axe ★★★★ · Axe: Whirl · Second Wind     [L] Loadout
	  Click or tap it, press L (gamepad: D-pad right), or walk up to the Loadout rack at the front of the Lounge car
	  (workspace.Lobby.LoadoutStation, ProximityPrompt "Loadout": E / X / tap) to open the screen. Never in the arena.

	THE SCREEN
	  The camera eases (0.4 s) to a three-quarter view of your own avatar (left of the screen; at the rack it stands in
	  front of it). On the right, five rows, every choice of a row visible at once:
	    KIT      Archer  Forager  Hunter  Medic  Climber          (dim: what the parcel will hold)
	    BRING    Kit weapon  Twin-Bit Axe ★★★★  ...                (dim: where it comes from)
	    WEAPON   Fists  Short blade  Sword  Axe  Spear  Throwing  Bow   (dim: that family's skill, its line, cooldown)
	    GENERAL  Concentration  Second Wind  ...                   (dim: what it does, cooldown)
	    TRAIL    SWING  ARROW  THROW  |  Draught  Dust  Comet 4,000 ... (dim: kind, rarity, owned or "hold to buy")
	  The chosen one in each row: full Ink and a 26 x 2 underline; the rest at rest. Hover or gamepad focus shows that
	  choice's line under its row (touch: one shared line above DONE, so every target stays 44 px).
	  Preview on your own avatar, client only: the kit lies on the rack's blue tray; the brought weapon (or the kit's own)
	  is in your right hand at its stars; a trail plays a swing, a shot or a throw with that trail (TrailController's
	  own recipes), looping while the TRAIL row has focus.
	  Buying a trail: a trail you do not own shows its price; hold it 0.6 s (a thin line fills under it) to buy it with
	  Gold (TrailService, remote "Trails" "buy"); it is then yours and equipped in that slot.
	  LOCKED · launching (Sun) during the countdown: kit, bring and skills dim to 50% and cannot change (trails can).
	  Gold bottom right (RobotoMono). DONE, L, gamepad B or tapping the avatar's side closes it.

	ONE SAVE
	  Choices change locally while the screen is open; closing it sends one LoadoutSet { kit, bring, specialty, general,
	  trails = { swing, arrow, throw } } (KitService checks every value). While it stays open a choice is also sent
	  1.2 s after the last change, so a call that comes while you are still looking takes it. Trails: the main screen
	  shows the three slots; choosing one (or ›) shows the trail strip in the rows' place (‹ goes back). A phone keeps
	  each row on one line that swipes sideways, with one shared line for what was touched. Shown back quietly: the summary line takes the new choice and a short "Saved" fades by it.

	Reads: player attributes Kit, KitBring, KitArmoury (KitService), LoadoutSpecialty, LoadoutGeneral (KitService),
	TrailSwing / TrailArrow / TrailThrow, TrailsOwned (TrailService), Gold; GameState Phase.
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("LoadoutCatalog"))
local Input = require(Shared:WaitForChild("Input"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Kits = require(Shared:WaitForChild("Kits"))
local Net = require(Shared:WaitForChild("Net"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Stars = require(Shared:WaitForChild("Stars"))
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local GameState = ReplicatedStorage:WaitForChild("GameState")
local C = Theme.Colors

local LoadoutController = {}

local OPT_H = 30 -- an option's height (touch: 44 through QuietUI's TouchFloor)
local TITLE_W = 112
local REST = 0.28 -- Ink at 72%
local BUY_HOLD = 0.6
local EASE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ROWS = { "kit", "bring", "specialty", "general", "trail" }
local ROW_TITLES = { kit = "KIT", bring = "BRING", specialty = "WEAPON SKILL", general = "GENERAL SKILL", trail = "TRAIL" }
local ROW_TITLES_SHORT = { specialty = "WEAPON", general = "GENERAL" } -- a phone's narrower title column

local Controllers: { [string]: any } = {}
local gui: ScreenGui? = nil
local R: { [string]: any } = {}
local rows: { [string]: any } = {}
local isOpen = false
local draft: any = nil
local saved: any = nil
local trailSlot = "swing"
local trailMode = false -- the trail strip (Combat_v3 4.5) is showing in the rows' place
local focusRow: string? = nil
local compact = false
local previewFolder: Folder? = nil
local held: Model? = nil
local trayModels: { Instance } = {}
local cameraTween: Tween? = nil
local savedCameraType: Enum.CameraType? = nil
local trailToken = 0
local hold: { key: string, t0: number, button: TextButton }? = nil
local trailsRemote: RemoteEvent? = nil
local lastSentAt = 0

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function lobbyShowing(): boolean
	return not ClientState.inArena and ClientState.spectating == nil
end

local function locked(): boolean
	return GameState:GetAttribute("Phase") == "Countdown"
end

--------------------------------------------------------------------------------------------------------------------
-- What is chosen
--------------------------------------------------------------------------------------------------------------------

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

local function ownedTrails(): { [string]: boolean }
	return Catalog.decodeOwned(player:GetAttribute("TrailsOwned"))
end

local function ownsTrail(id: string): boolean
	return Catalog.isFreeTrail(id) or ownedTrails()[id] == true
end

local function readSaved()
	local kit = (Kits.get(player:GetAttribute("Kit")) or Kits.default()).id
	local defaults = Catalog.defaults(kit)
	local bring = player:GetAttribute("KitBring")
	local out = {
		kit = kit,
		bring = if type(bring) == "string" then bring else "",
		specialty = if Catalog.specialty(player:GetAttribute("LoadoutSpecialty")) then player:GetAttribute("LoadoutSpecialty") else defaults.specialty,
		general = if Catalog.general(player:GetAttribute("LoadoutGeneral")) then player:GetAttribute("LoadoutGeneral") else defaults.general,
		trails = {},
	}
	for _, slot in ipairs(Catalog.Slots) do
		local id = player:GetAttribute(Catalog.SlotAttr[slot])
		out.trails[slot] = if Catalog.trail(id) then id else defaults.trails[slot]
	end
	return out
end

local function copy(l: any)
	return { kit = l.kit, bring = l.bring, specialty = l.specialty, general = l.general,
		trails = { swing = l.trails.swing, arrow = l.trails.arrow, throw = l.trails.throw } }
end

local function current()
	return draft or saved or readSaved()
end

local function bringStars(id: string): number?
	for _, e in ipairs(armoury()) do
		if e.id == id then
			return e.stars
		end
	end
	return nil
end

local function summaryText(l: any): string
	local kit = Kits.get(l.kit) or Kits.default()
	local parts = { kit.name }
	local stars = l.bring ~= "" and bringStars(l.bring)
	if stars then
		table.insert(parts, Stars.label(l.bring, stars))
	end
	local spec = Catalog.specialty(l.specialty)
	if spec then
		table.insert(parts, spec.name .. ": " .. spec.skill.name)
	end
	local g = Catalog.general(l.general)
	if g then
		table.insert(parts, g.name)
	end
	return table.concat(parts, "  \u{00B7}  ")
end

--------------------------------------------------------------------------------------------------------------------
-- Rows: the options and their lines
--------------------------------------------------------------------------------------------------------------------

-- { key, text, detail, font?, size?, kind? } for a row, from the catalogue and the current choice
local function optionsFor(row: string): { any }
	local l = current()
	local out = {}
	if row == "kit" then
		local stars = l.bring ~= "" and bringStars(l.bring)
		for _, kit in ipairs(Kits.List) do
			local line = Kits.summary(kit, if stars then l.bring else nil, if stars then Stars.label(l.bring, stars) else nil)
			table.insert(out, { key = kit.id, text = kit.name, detail = line .. "  \u{00B7}  " .. kit.forWhom })
		end
	elseif row == "bring" then
		table.insert(out, { key = "", text = "Kit weapon", detail = "The kit's own weapon, at 1 star" })
		local owned = armoury()
		for _, e in ipairs(owned) do
			table.insert(out, { key = e.id, text = Stars.label(e.id, e.stars),
				detail = "From your Armoury: it comes in your kit parcel in place of the kit's weapon" })
		end
		if #owned == 0 then
			out[1].detail = "Win a weapon on the wheel or in a Strongbox to bring it here"
		end
	elseif row == "specialty" then
		for _, s in ipairs(Catalog.Specialties) do
			local sk = s.skill
			table.insert(out, { key = s.id, text = s.name,
				detail = string.format("%s  \u{00B7}  %s  \u{00B7}  %d s", sk.name, string.lower(sk.line), sk.cooldown or 0) })
		end
	elseif row == "general" then
		for _, g in ipairs(Catalog.General) do
			table.insert(out, { key = g.id, text = g.name, detail = string.format("%s  \u{00B7}  %d s", g.line, g.cooldown or 0) })
		end
	elseif row == "trail" then
		local slotLines = { swing = "Your melee swings and skills", arrow = "Both bows", throw = "Every thrown weapon" }
		if not trailMode then
			-- the main screen: the three slots with what each has on; any of them (or ›) opens the trail strip
			for _, slot in ipairs(Catalog.Slots) do
				local t = Catalog.trail(l.trails[slot])
				table.insert(out, { key = "slot:" .. slot, kind = "slot", font = "SemiBold", size = Theme.TextSize.Label,
					text = string.format('%s  <font weight="500" color="%s">%s</font>', Catalog.SlotNames[slot], Theme.hex(C.Ink),
						Theme.escape(t and t.name or "None")),
					detail = slotLines[slot] .. "  \u{00B7}  choose to see every trail" })
			end
			table.insert(out, { key = "more", kind = "more", text = "\u{203A}", size = Theme.TextSize.Heading,
				detail = "Every trail: free, owned and for Gold" })
			return out
		end
		table.insert(out, { key = "back", kind = "back", text = "\u{2039}", size = Theme.TextSize.Heading,
			detail = "Back to kit and skills" })
		for _, slot in ipairs(Catalog.Slots) do
			table.insert(out, { key = "slot:" .. slot, text = Catalog.SlotNames[slot], font = "SemiBold", size = Theme.TextSize.Label,
				kind = "slot", detail = slotLines[slot] })
		end
		local owned = ownedTrails()
		for _, t in ipairs(Catalog.Trails) do
			if t.slots[trailSlot] then
				local mine = Catalog.isFreeTrail(t.id) or owned[t.id] == true
				local text = t.name
				local detail
				if t.id == "none" then
					detail = "No trail at all"
				elseif mine then
					detail = string.format("%s  \u{00B7}  %s  \u{00B7}  %s", t.kind, t.rarity, if t.rarity == "Free" then "free" else "yours")
				else
					text = string.format('%s  <font family="rbxasset://fonts/families/RobotoMono.json" color="%s">%s</font>',
						t.name, Theme.hex(C.Ink2), comma(t.price))
					detail = string.format("%s  \u{00B7}  %s  \u{00B7}  %s Gold  \u{00B7}  hold to buy", t.kind, t.rarity, comma(t.price))
				end
				if t.line then
					detail = t.line .. "  \u{00B7}  " .. detail
				end
				table.insert(out, { key = t.id, text = text, detail = detail, kind = "trail", trail = t, owned = mine })
			end
		end
	end
	return out
end

local function chosenKey(row: string): string?
	local l = current()
	if row == "trail" then
		return if trailMode then l.trails[trailSlot] else nil
	end
	return l[row]
end

local function setDetail(row: string, text: string?)
	local r = rows[row]
	if not r then
		return
	end
	if text == nil then
		local key = chosenKey(row)
		for _, opt in ipairs(r.options) do
			if opt.key == key then
				text = opt.detail
			end
		end
	end
	r.detail.Text = text or ""
	if R.shared then
		R.shared.Text = text or ""
	end
end

local function paintRow(row: string)
	local r = rows[row]
	if not r then
		return
	end
	local key = chosenKey(row)
	local lockedNow = locked() and row ~= "trail"
	for _, opt in ipairs(r.options) do
		local b = opt.button
		local on = (key ~= nil and opt.key == key) or (trailMode and opt.kind == "slot" and opt.key == "slot:" .. trailSlot)
		b:SetAttribute("Quiet", not on)
		if lockedNow then
			QuietUI.setButtonEnabled(b, on)
			b.TextTransparency = if on then 0.5 else 0.75
		else
			QuietUI.setButtonEnabled(b, true)
			b.TextTransparency = if on then 0 else REST
		end
		local mark = b:FindFirstChild("Mark")
		if mark then
			mark.Visible = on
		end
	end
	if focusRow ~= row or R.shared == nil then
		setDetail(row, nil)
	end
end

local function paintAll()
	for _, row in ipairs(ROWS) do
		paintRow(row)
	end
	if R.locked then
		R.locked.Visible = locked()
	end
	if R.gold then
		R.gold.Text = comma(tonumber(player:GetAttribute("Gold")) or 0) .. " Gold"
	end
end

-- New lines for a row's options without rebuilding its buttons (the gamepad keeps its place)
local function updateDetails(row: string)
	local r = rows[row]
	if not r then
		return
	end
	local fresh = {}
	for _, opt in ipairs(optionsFor(row)) do
		fresh[opt.key] = opt.detail
	end
	for _, opt in ipairs(r.options) do
		opt.detail = fresh[opt.key] or opt.detail
	end
	paintRow(row)
end

local choose: (string, any) -> () -- (forward)
local buildOptions: (string) -> () -- (forward)

-- The trail strip takes the rows' place (and gives it back): the three slots and every trail that fits the slot
local function setTrailMode(on: boolean)
	trailMode = on
	for _, row in ipairs(ROWS) do
		local r = rows[row]
		if r and row ~= "trail" then
			r.frame.Visible = not on
		end
	end
	if R.title then
		R.title.Text = if on then "LOADOUT  \u{00B7}  TRAILS" else "LOADOUT"
	end
	buildOptions("trail")
	paintAll()
end
local startHold: (any, string, TextButton) -> ()

buildOptions = function(row: string)
	local r = rows[row]
	for _, opt in ipairs(r.options) do
		opt.button:Destroy()
	end
	r.options = {}
	for i, opt in ipairs(optionsFor(row)) do
		local b = QuietUI.button({
			Name = "Opt_" .. (if opt.key == "" then "none" else opt.key), Text = opt.text, Font = opt.font or "Medium",
			TextSize = opt.size or Theme.TextSize.Body, Height = OPT_H, LayoutOrder = i * 2, Quiet = true,
		})
		b.RichText = true
		local mark = Instance.new("Frame")
		mark.Name = "Mark"
		mark.BorderSizePixel = 0
		mark.BackgroundColor3 = C.Ink
		mark.AnchorPoint = Vector2.new(0.5, 1)
		mark.Position = UDim2.new(0.5, 0, 1, -1)
		mark.Size = UDim2.fromOffset(26, 2)
		mark.Visible = false
		mark.Parent = b
		if opt.kind == "trail" then
			-- a small swatch of the trail itself: a short stroke from its head colour to its tail colour
			local pad = b:FindFirstChild("Pad")
			if pad and pad:IsA("UIPadding") then
				pad.PaddingLeft = UDim.new(0, 30)
			end
			local sw = Instance.new("Frame")
			sw.Name = "Swatch"
			sw.BorderSizePixel = 0
			sw.AnchorPoint = Vector2.new(0, 0.5)
			sw.Position = UDim2.new(0, -28, 0.5, 0)
			sw.Size = UDim2.fromOffset(22, if opt.key == "none" then 1 else 3)
			sw.BackgroundColor3 = Color3.new(1, 1, 1)
			sw.BackgroundTransparency = if opt.key == "none" then 0.6 else 0
			local grad = Instance.new("UIGradient")
			grad.Color = ColorSequence.new(opt.trail.colors[1], opt.trail.colors[2])
			grad.Transparency = NumberSequence.new(0, 0.55)
			grad.Parent = sw
			sw.Parent = b
			if not opt.owned then
				local fill = Instance.new("Frame")
				fill.Name = "Fill"
				fill.BorderSizePixel = 0
				fill.BackgroundColor3 = C.Sun
				fill.AnchorPoint = Vector2.new(0, 1)
				fill.Position = UDim2.new(0, 0, 1, -1)
				fill.Size = UDim2.new(0, 0, 0, 2)
				fill.Parent = b
			end
		end
		QuietUI.bindButton(b, { quiet = true, onHover = function()
			focusRow = row
			setDetail(row, opt.detail)
		end })
		b.MouseLeave:Connect(function()
			setDetail(row, nil)
		end)
		b.SelectionGained:Connect(function()
			focusRow = row
			setDetail(row, opt.detail)
		end)
		b.Activated:Connect(function()
			choose(row, opt)
		end)
		if opt.kind == "trail" and not opt.owned then
			b.InputBegan:Connect(function(io: InputObject)
				if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
					or io.KeyCode == Enum.KeyCode.ButtonA then
					startHold(opt, row, b)
				end
			end)
			b.InputEnded:Connect(function(io: InputObject)
				if hold and hold.button == b and (io.UserInputType == Enum.UserInputType.MouseButton1
					or io.UserInputType == Enum.UserInputType.Touch or io.KeyCode == Enum.KeyCode.ButtonA) then
					hold = nil
					local fill = b:FindFirstChild("Fill")
					if fill and fill:IsA("Frame") then
						fill.Size = UDim2.new(0, 0, 0, 2)
					end
				end
			end)
		end
		b.Parent = r.scroll
		opt.button = b
		table.insert(r.options, opt)
		if opt.kind == "slot" and trailMode and opt.key == "slot:" .. Catalog.Slots[#Catalog.Slots] then
			-- a thin upright line between the three slots and the trails
			local sep = Instance.new("Frame")
			sep.Name = "Sep"
			sep.BorderSizePixel = 0
			sep.BackgroundColor3 = C.Ink
			sep.BackgroundTransparency = 0.6
			sep.Size = UDim2.fromOffset(1, 16)
			sep.LayoutOrder = i * 2 + 1
			sep.Parent = r.scroll
			opt.sep = sep
			local oldDestroy = opt.button
			oldDestroy.Destroying:Connect(function()
				sep:Destroy()
			end)
		end
	end
	paintRow(row)
end

local function makeRow(parent: Instance, row: string, order: number)
	-- a row grows with its options: they wrap onto a second line rather than run off the screen
	local frame = Instance.new("Frame")
	frame.Name = "Row_" .. row
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local titleW = if compact then 78 else TITLE_W
	local title = QuietUI.label({
		Name = "Title", Text = if compact then (ROW_TITLES_SHORT[row] or ROW_TITLES[row]) else ROW_TITLES[row], Font = "SemiBold",
		TextSize = Theme.TextSize.Label, TextColor3 = C.Ink2,
		Size = UDim2.fromOffset(titleW, if compact then 44 else OPT_H), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
	})
	title.Parent = frame
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromOffset(titleW + 6, 0)
	right.Size = UDim2.new(1, -(titleW + 6), 0, 0)
	right.AutomaticSize = Enum.AutomaticSize.Y
	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, 0)
	stack.Parent = right
	-- a PC wraps a long row onto a second line; a phone keeps one line and swipes it sideways (Combat_v3 3.2)
	local scroll: GuiObject
	if compact then
		local s = Instance.new("ScrollingFrame")
		s.Size = UDim2.new(1, 0, 0, 44)
		s.ScrollingDirection = Enum.ScrollingDirection.X
		s.AutomaticCanvasSize = Enum.AutomaticSize.X
		s.CanvasSize = UDim2.new()
		s.ScrollBarThickness = 0
		s.BorderSizePixel = 0
		s.Selectable = false
		scroll = s
	else
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		scroll = f
	end
	scroll.Name = "Options"
	scroll.BackgroundTransparency = 1
	scroll.LayoutOrder = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Wraps = not compact
	layout.Padding = UDim.new(0, if compact then 14 else 18)
	layout.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 2)
	pad.Parent = scroll
	scroll.Parent = right
	local detail = QuietUI.label({
		Name = "Detail", Text = "", Font = "Medium", TextSize = Theme.TextSize.Caption, TextColor3 = C.Ink2, LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = not compact,
	})
	detail.Parent = right
	right.Parent = frame
	frame.Parent = parent
	rows[row] = { frame = frame, scroll = scroll, detail = detail, options = {} }
	buildOptions(row)
end
--------------------------------------------------------------------------------------------------------------------
-- The preview on your own avatar (client only)
--------------------------------------------------------------------------------------------------------------------

local function station(): Model?
	local lobby = workspace:FindFirstChild("Lobby")
	local s = lobby and lobby:FindFirstChild("LoadoutStation")
	return if s and s:IsA("Model") then s else nil
end

local function folder(): Folder
	if previewFolder and previewFolder.Parent then
		return previewFolder
	end
	local f = Instance.new("Folder")
	f.Name = "LoadoutPreview"
	f.Parent = workspace
	previewFolder = f
	return f
end

local function quiet(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

local function clearTray()
	for _, m in ipairs(trayModels) do
		m:Destroy()
	end
	table.clear(trayModels)
end

-- The kit (with the brought weapon in its place) laid out on the rack's blue tray
local function layTray()
	clearTray()
	local s = station()
	local spot = s and s:FindFirstChild("TraySpot", true)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (spot and spot:IsA("Attachment")) or not (root and root:IsA("BasePart")) or (root.Position - spot.WorldPosition).Magnitude > 40 then
		return
	end
	local l = current()
	local kit = Kits.get(l.kit) or Kits.default()
	local ids = {}
	local stars = l.bring ~= "" and bringStars(l.bring)
	local replaced = false
	for _, item in ipairs(kit.items) do
		local def = ItemDefs.get(item.id)
		if stars and not replaced and def and def.starred then
			replaced = true
			table.insert(ids, { id = l.bring, stars = stars })
		else
			table.insert(ids, { id = item.id, stars = 1 })
		end
	end
	if stars and not replaced then
		table.insert(ids, 1, { id = l.bring, stars = stars })
	end
	local n = #ids
	local span = 5.6
	for i, e in ipairs(ids) do
		local ok, model = pcall(ItemModels.build, e.id)
		if ok and model then
			quiet(model)
			local x = if n == 1 then 0 else -span / 2 + (i - 1) * span / (n - 1)
			local base = spot.WorldCFrame * CFrame.new(x, 0, 0)
			model:PivotTo(base * ItemModels.restRotation(e.id))
			local okExtent, low = pcall(ItemModels.getExtent, model, Vector3.yAxis)
			if okExtent and type(low) == "number" then
				model:PivotTo(model:GetPivot() + Vector3.new(0, spot.WorldPosition.Y - low, 0))
			end
			if model.PrimaryPart then
				model.PrimaryPart.Anchored = true
			end
			pcall(Stars.applyFinish, model, e.stars)
			model.Parent = folder()
			table.insert(trayModels, model)
		end
	end
end

-- The weapon in your right hand: the brought one at its stars, else the kit's own at 1 star
local function holdWeapon()
	if held then
		held:Destroy()
		held = nil
	end
	local character = player.Character
	local grip = character and character:FindFirstChild("RightGripAttachment", true)
	if not (grip and grip:IsA("Attachment") and grip.Parent and grip.Parent:IsA("BasePart")) then
		return
	end
	local l = current()
	local id, stars = nil, 1
	local s = l.bring ~= "" and bringStars(l.bring)
	if s then
		id, stars = l.bring, s
	else
		local kit = Kits.get(l.kit) or Kits.default()
		for _, item in ipairs(kit.items) do
			local def = ItemDefs.get(item.id)
			if def and def.starred and not id then
				id = item.id
			end
		end
	end
	if not id then
		return
	end
	local ok, model = pcall(ItemModels.build, id)
	if not ok or not model or not model.PrimaryPart then
		return
	end
	quiet(model)
	local handle = model.PrimaryPart
	local gripAt = handle:FindFirstChild("Grip")
	local offset = if gripAt and gripAt:IsA("Attachment") then gripAt.CFrame:Inverse() else CFrame.identity
	model:PivotTo(grip.WorldCFrame * offset)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip.Parent :: BasePart
	weld.Part1 = handle
	weld.Parent = handle
	pcall(Stars.applyFinish, model, stars)
	model.Parent = folder()
	held = model
end

-- A trail played once on the avatar: a swing arc in front of it, or a shot or a throw across the view
local function playTrail()
	trailToken += 1
	local token = trailToken
	local l = current()
	local id = l.trails[trailSlot]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not id or id == "none" or not (root and root:IsA("BasePart")) then
		return
	end
	local trailController = Controllers.TrailController
	local cf = root.CFrame
	local f, r, up = cf.LookVector, cf.RightVector, Vector3.yAxis
	if trailSlot == "swing" then
		local blade = Instance.new("Part")
		blade.Name = "PreviewBlade"
		blade.Size = Vector3.new(0.1, 0.1, 0.1)
		blade.Transparency = 1
		blade.Anchored = true
		blade.CanCollide, blade.CanQuery, blade.CanTouch, blade.CastShadow = false, false, false, false
		-- a diagonal cut across the front of the body, high on the avatar's right to low on its left (as you see it:
		-- upper left to lower right)
		local center = root.Position + up * 0.6 + f * 1.6
		local function at(theta: number): CFrame
			local d = -r * math.cos(theta) + up * math.sin(theta)
			return CFrame.lookAt(center, center + d)
		end
		local a0, a1 = math.rad(135), math.rad(-45)
		blade.CFrame = at(a0)
		blade.Parent = folder()
		local dur = 0.3
		if trailController and type(trailController.swingOn) == "function" then
			pcall(trailController.swingOn, blade, Vector3.new(0, 0, -0.4), Vector3.new(0, 0, -2.8), id, 0, dur + 0.05)
		else
			local t = Catalog.trail(id)
			local p0 = Instance.new("Attachment")
			p0.Position = Vector3.new(0, 0, -0.4)
			p0.Parent = blade
			local p1 = Instance.new("Attachment")
			p1.Position = Vector3.new(0, 0, -2.8)
			p1.Parent = blade
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = p0, p1
			tr.Lifetime = 0.18
			tr.Color = ColorSequence.new(t.colors[1], t.colors[2])
			tr.Transparency = NumberSequence.new(0.3, 1)
			tr.LightEmission = if t.glow then 0.8 else 0.15
			tr.Parent = blade
		end
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			local eased = 1 - (1 - a) * (1 - a)
			blade.CFrame = at(a0 + (a1 - a0) * eased)
			if a >= 1 or token ~= trailToken then
				conn:Disconnect()
				task.delay(0.6, function()
					blade:Destroy()
				end)
			end
		end)
	else
		local itemId = if trailSlot == "arrow" then "arrow" else "throwing_knife"
		local origin = root.Position + up * 1.2 + r * 1.2 + f * 0.8
		local dir = (r * 0.96 + f * 0.1 + up * 0.04).Unit
		local dist, dur = 34, 0.5
		local okM, model = pcall(ItemModels.build, itemId)
		if okM and model and model.PrimaryPart then
			quiet(model)
			model.PrimaryPart.Anchored = true
			model.Parent = folder()
		else
			model = nil
		end
		local handle = nil
		if trailController and type(trailController.attachProjectile) == "function" then
			local okH, h = pcall(trailController.attachProjectile, itemId, player.UserId, true, origin, id)
			if okH then
				handle = h
			end
		end
		local t0 = os.clock()
		local spin = 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			local p = origin + dir * dist * a
			spin += dt * (if itemId == "arrow" then 0 else 22)
			if model then
				local gripAt = model.PrimaryPart:FindFirstChild("Grip")
				local look = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, 0) * CFrame.Angles(-spin, 0, 0)
				model:PivotTo(look * (if gripAt then gripAt.CFrame:Inverse() else CFrame.identity))
			end
			if handle then
				pcall(handle.follow, handle, p, dir)
			end
			if a >= 1 or token ~= trailToken then
				conn:Disconnect()
				if handle then
					pcall(handle.release, handle)
				end
				if model then
					model:Destroy()
				end
			end
		end)
	end
end

local function loopTrail()
	task.spawn(function()
		while isOpen do
			if focusRow == "trail" and trailMode then
				playTrail()
			end
			task.wait(1.5)
		end
	end)
end

local function refreshPreview()
	if not isOpen then
		return
	end
	layTray()
	holdWeapon()
end

local function clearPreview()
	trailToken += 1
	clearTray()
	if held then
		held:Destroy()
		held = nil
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The camera and your body while the screen is open
--------------------------------------------------------------------------------------------------------------------

local function framing(): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local cf = root.CFrame
	local f = cf.LookVector
	local around = CFrame.Angles(0, math.rad(-26), 0) * f -- three-quarter, from the avatar's right-front
	local dist = 11.5
	-- never past a wall: the eye stops short of the first thing between it and the avatar
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position + Vector3.yAxis * 1.9, around * dist, params)
	if hit then
		dist = math.max(hit.Distance - 0.6, 4)
	end
	local eye = root.Position + around * dist + Vector3.yAxis * 1.9
	local look = CFrame.lookAt(eye, root.Position + Vector3.yAxis * 0.2)
	-- the avatar sits in the middle of the left part of the picture (the rows take the right): aim to its left (the
	-- camera's right) by the share of the half-width that puts it at about a quarter of the screen
	local camera = workspace.CurrentCamera
	local v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local vfov = math.rad(if camera then camera.FieldOfView else 70)
	local halfWidth = math.tan(vfov / 2) * (v.X / math.max(v.Y, 1)) * dist
	local share = if compact then 0.56 else 0.5
	local shift = math.clamp(halfWidth * share, 1.5, 9)
	return CFrame.lookAt(eye, root.Position + Vector3.yAxis * 0.2 + look.RightVector * shift)
end

local function showOwnBody()
	local character = player.Character
	if not character then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	if held then
		for _, d in ipairs(held:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
	end
end

local hiddenTags: { BillboardGui } = {}

local function takeBody(open: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	-- your own name tag hangs over your face in the preview: hidden on your screen only while it is open
	if open then
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BillboardGui") and d.Enabled then
				d.Enabled = false
				table.insert(hiddenTags, d)
			end
		end
	else
		for _, tag in ipairs(hiddenTags) do
			if tag.Parent then
				tag.Enabled = true
			end
		end
		table.clear(hiddenTags)
	end
	local lobbyController = Controllers.LobbyController
	if lobbyController and type(lobbyController.setCover) == "function" then
		pcall(lobbyController.setCover, "Loadout", open)
	end
	if open then
		local s = station()
		local stand = s and s:FindFirstChild("Stand", true)
		if stand and stand:IsA("Attachment") and (root.Position - stand.WorldPosition).Magnitude < 10 then
			-- at the rack: stand in front of it, looking down the car (the rack and its tray behind you)
			local at = Vector3.new(stand.WorldPosition.X, root.Position.Y, stand.WorldPosition.Z)
			local ahead = stand.WorldCFrame.LookVector * Vector3.new(1, 0, 1)
			character:PivotTo(CFrame.lookAt(at, at + ahead))
		else
			-- opened elsewhere in the car (L, the summary line, D-pad right): the 11.5-stud three-quarter view would sit
			-- outside the car's walls, so turn the avatar toward the longest clear line of sight (down the car)
			local best, bestClear = nil, -1
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			local eyeY = Vector3.yAxis * 1.9
			for i = 0, 15 do
				local a = i / 16 * math.pi * 2
				local dir = Vector3.new(math.sin(a), 0, math.cos(a))
				local hit = workspace:Raycast(root.Position + eyeY, dir * 12, params)
				local clear = if hit then hit.Distance else 12
				if clear > bestClear + 0.05 then
					best, bestClear = dir, clear
				end
			end
			if best then
				-- framing() looks from 26 degrees round from the avatar's front: face so that line runs along `best`
				local facing = CFrame.Angles(0, math.rad(26), 0) * best
				character:PivotTo(CFrame.lookAt(root.Position, root.Position + facing))
			end
		end
		task.delay(0.12, function()
			if isOpen and root.Parent then
				root.Anchored = true
			end
		end)
	else
		root.Anchored = false
	end
end

local function takeCamera(open: boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if cameraTween then
		cameraTween:Cancel()
		cameraTween = nil
	end
	if open then
		savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		local goal = framing()
		if goal then
			cameraTween = TweenService:Create(camera, EASE, { CFrame = goal })
			cameraTween:Play()
		end
	else
		camera.CameraType = if savedCameraType == Enum.CameraType.Scriptable then Enum.CameraType.Custom
			else (savedCameraType or Enum.CameraType.Custom)
		local _, humanoid = player.Character, player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Open, choose, save, close
--------------------------------------------------------------------------------------------------------------------

local function changed(a: any, b: any): boolean
	if a.kit ~= b.kit or a.bring ~= b.bring or a.specialty ~= b.specialty or a.general ~= b.general then
		return true
	end
	for _, slot in ipairs(Catalog.Slots) do
		if a.trails[slot] ~= b.trails[slot] then
			return true
		end
	end
	return false
end

local function payloadOf(l: any)
	local trails = {}
	for _, slot in ipairs(Catalog.Slots) do
		local id = l.trails[slot]
		-- an unowned trail being looked at is not sent: the slot keeps what was equipped
		trails[slot] = if ownsTrail(id) then id else (saved and saved.trails[slot]) or "draught"
	end
	return { kit = l.kit, bring = l.bring, specialty = l.specialty, general = l.general, trails = trails }
end

local function flashSaved()
	local tick = R.saved
	if not tick then
		return
	end
	tick.Visible = true
	QuietUI.fadeText(tick, true)
	task.delay(1.6, function()
		QuietUI.fadeText(tick, false)
	end)
end

local function send(force: boolean?)
	if not draft then
		return
	end
	local base = saved or readSaved()
	if not force and not changed(draft, base) then
		return
	end
	local payload = payloadOf(draft)
	lastSentAt = os.clock()
	local ok = pcall(function()
		Net.event("LoadoutSet"):FireServer(payload)
	end)
	if not ok then
		-- an old server: the kit and the bring still go through KitPick
		pcall(function()
			Net.event("KitPick"):FireServer(payload.kit)
			Net.event("KitPick"):FireServer("bring", payload.bring)
		end)
	end
	saved = copy(payload)
	flashSaved()
end

-- While it stays open, a choice is also sent 1.2 s after the last change (so a call that comes while you are still
-- looking takes what you chose; at most one LoadoutSet a second, well inside KitService's limit)
local sendToken = 0
local function scheduleSend()
	sendToken += 1
	local mine = sendToken
	task.delay(1.2, function()
		if mine == sendToken and isOpen and not locked() then
			send(false)
		end
	end)
end

local function refreshSummary()
	if R.summaryText then
		R.summaryText.Text = summaryText(current())
	end
end

choose = function(row: string, opt: any)
	if not draft then
		return
	end
	if opt.kind == "slot" or opt.kind == "more" or opt.kind == "back" then
		if opt.kind == "slot" then
			trailSlot = string.sub(opt.key, 6)
		end
		Sfx.play("UIClick")
		local wasSelected = GuiService.SelectedObject == opt.button or Input.isGamepad()
		setTrailMode(opt.kind ~= "back")
		if wasSelected then
			-- the gamepad keeps its place: the same slot, or the slot just opened, or (back) the slot line
			local want = if opt.kind == "slot" then opt.key else "slot:" .. trailSlot
			for _, o in ipairs(rows.trail.options) do
				if o.key == want then
					GuiService.SelectedObject = o.button
				end
			end
		end
		focusRow = "trail"
		if trailMode then
			playTrail()
		end
		return
	end
	if locked() and row ~= "trail" then
		return
	end
	if row == "kit" then
		local before = draft.kit
		draft.kit = opt.key
		-- the Specialty follows the kit while it is still the old kit's suggestion (Combat_v3 2.1)
		if draft.specialty == Catalog.suggestedSpecialty(before) then
			draft.specialty = Catalog.suggestedSpecialty(opt.key)
		end
		paintRow("specialty")
	elseif row == "bring" then
		draft.bring = opt.key
		updateDetails("kit") -- its lines show the parcel with the weapon in it
	elseif row == "specialty" then
		draft.specialty = opt.key
	elseif row == "general" then
		draft.general = opt.key
	elseif row == "trail" then
		draft.trails[trailSlot] = opt.key
		focusRow = "trail"
		playTrail()
	end
	Sfx.play("UIClick")
	paintRow(row)
	setDetail(row, opt.detail)
	refreshSummary()
	scheduleSend()
	if row == "kit" or row == "bring" then
		refreshPreview()
	end
end

startHold = function(opt: any, row: string, button: TextButton)
	hold = { key = opt.key, t0 = os.clock(), button = button }
	local mine = hold
	local fill = button:FindFirstChild("Fill")
	task.spawn(function()
		while hold == mine and isOpen do
			local a = math.clamp((os.clock() - mine.t0) / BUY_HOLD, 0, 1)
			if fill and fill:IsA("Frame") then
				fill.Size = UDim2.new(a, 0, 0, 2)
			end
			if a >= 1 then
				hold = nil
				if trailsRemote then
					trailsRemote:FireServer("buy", opt.key, trailSlot)
					setDetail(row, "Buying " .. opt.trail.name .. " ...")
				else
					setDetail(row, "The trail shop is not open yet")
				end
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function onBought(id: string)
	if not isOpen or not draft then
		return
	end
	local t = Catalog.trail(id)
	if t and t.slots[trailSlot] then
		draft.trails[trailSlot] = id
	end
	Sfx.play("UIClick", { pitch = 0.8 })
	buildOptions("trail")
	setDetail("trail", (t and t.name or id) .. " is yours")
	if R.shared then
		R.shared.Text = (t and t.name or id) .. " is yours"
	end
	playTrail()
end

local function sink()
	return Enum.ContextActionResult.Sink
end

local close: () -> ()
local open: () -> ()

-- The Loadout key (Input action "Loadout": L, D-pad right), bound only in the train lobby. L opens and closes the
-- screen; D-pad right only opens it, and is let go while the screen, a menu or any GUI selection is up (a controller
-- moves through those with the D-pad) and in the arena (where it is SkillGeneral).
local boundKeys = "" -- what is bound now: "", "L" or "L+Pad"
local function onLoadoutKey(state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult?
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if io and io.KeyCode == Enum.KeyCode.DPadRight then
		if isOpen or ClientState.menuOpen or GuiService.SelectedObject ~= nil or not lobbyShowing()
			or player:GetAttribute("InTraining") == true then
			return Enum.ContextActionResult.Pass
		end
		open()
		return Enum.ContextActionResult.Sink
	end
	if isOpen then
		close()
		return Enum.ContextActionResult.Sink
	end
	if ClientState.menuOpen or not lobbyShowing() then
		return Enum.ContextActionResult.Pass
	end
	open()
	return Enum.ContextActionResult.Sink
end

local function syncKeys()
	local want = ""
	if lobbyShowing() and gui then
		-- in the Training Centre's hall D-pad right is the general skill (SkillController binds it there, skills are
		-- tried in the hall): the Loadout keeps L, and a controller opens it at the rack or the kit board (ButtonX)
		local inHall = player:GetAttribute("InTraining") == true
		want = if isOpen or ClientState.menuOpen or GuiService.SelectedObject ~= nil or inHall then "L" else "L+Pad"
	end
	if want == boundKeys then
		return
	end
	boundKeys = want
	if want == "" then
		Input.unbind("Loadout")
		return
	end
	local spec = Input.ACTIONS and Input.ACTIONS.Loadout
	local keys = if spec and spec.keys then table.clone(spec.keys) else { Enum.KeyCode.L, Enum.KeyCode.DPadRight }
	if want == "L" then
		local index = table.find(keys, Enum.KeyCode.DPadRight)
		if index then
			table.remove(keys, index)
		end
	end
	Input.bind("Loadout", onLoadoutKey, { keys = keys })
end

open = function()
	if isOpen or not lobbyShowing() or ClientState.menuOpen or not gui then
		return
	end
	isOpen = true
	saved = readSaved()
	draft = copy(saved)
	focusRow = nil
	ClientState.menuOpen = true
	R.sheet.Visible = true
	R.summary.Visible = false
	if R.near then
		R.near.Visible = false
	end
	trailMode = false
	for _, row in ipairs(ROWS) do
		buildOptions(row)
	end
	setTrailMode(false)
	QuietUI.fadeIn(R.sheet, 0.25)
	takeBody(true)
	takeCamera(true)
	task.delay(0.15, refreshPreview)
	loopTrail()
	-- the station's own prompt hides while you are in it
	local s = station()
	local prompt = s and s:FindFirstChild("Loadout", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
	-- B closes (and must not also crouch); the thumbsticks stay with the GUI selection
	ContextActionService:BindActionAtPriority("LoadoutClose", function(_, state)
		if state == Enum.UserInputState.Begin then
			close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority("LoadoutSink", sink, false, Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.Space, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	if Input.isGamepad() then
		local first = rows.kit and rows.kit.options[1]
		for _, opt in ipairs(rows.kit.options) do
			if opt.key == draft.kit then
				first = opt
			end
		end
		if first then
			GuiService.SelectedObject = first.button
		end
	end
	Sfx.play("UIClick", { pitch = 1.1 })
	task.defer(syncKeys) -- (not inside the key's own callback)
end

close = function()
	if not isOpen then
		return
	end
	send(false)
	isOpen = false
	hold = nil
	ContextActionService:UnbindAction("LoadoutClose")
	ContextActionService:UnbindAction("LoadoutSink")
	if GuiService.SelectedObject and R.sheet and GuiService.SelectedObject:IsDescendantOf(R.sheet) then
		GuiService.SelectedObject = nil
	end
	clearPreview()
	takeCamera(false)
	takeBody(false)
	R.sheet.Visible = false
	ClientState.menuOpen = false
	draft = nil
	refreshSummary()
	local s = station()
	local prompt = s and s:FindFirstChild("Loadout", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = true
	end
	LoadoutController.refresh()
end

function LoadoutController.isOpen(): boolean
	return isOpen
end

function LoadoutController.open()
	open()
end

function LoadoutController.close()
	close()
end

-- The summary line's visibility and words (also after the attributes change)
function LoadoutController.refresh()
	if not R.summary then
		return
	end
	if not isOpen then
		saved = readSaved()
	end
	refreshSummary()
	R.summary.Visible = lobbyShowing() and not isOpen and not ClientState.menuOpen
	if isOpen and not lobbyShowing() then
		close()
	end
	task.defer(syncKeys)
end

-- Test hook (Studio playtests drive the screen with this; harmless in a live game)
function LoadoutController.debugChoose(row: string, key: string): boolean
	local r = rows[row]
	if not (isOpen and r) then
		return false
	end
	for _, opt in ipairs(r.options) do
		if opt.key == key then
			choose(row, opt)
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------------------------------------------
-- Building the screen
--------------------------------------------------------------------------------------------------------------------

local function isCompact(): boolean
	local camera = workspace.CurrentCamera
	local v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	-- (LocalPlayer attribute LoadoutTouchLayout = true shows the touch layout on a PC: a Studio check)
	return Input.isTouch() or Theme.isSmallScreen(v) or v.Y < 560 or player:GetAttribute("LoadoutTouchLayout") == true
end

local function buildSheet(root: Frame)
	if R.sheet then
		R.sheet:Destroy()
		table.clear(rows)
	end
	compact = isCompact()
	-- the sheet: the right part of the screen (no box: thin text on the picture, with the Quiet stroke)
	local area = Instance.new("Frame")
	area.Name = "Sheet"
	area.BackgroundTransparency = 1
	area.AnchorPoint = Vector2.new(1, 0.5)
	area.Position = UDim2.new(1, if compact then -16 else -40, 0.5, if compact then 0 else 40)
	area.Size = if compact then UDim2.new(0.64, -16, 1, -16) else UDim2.new(0.5, -40, 0, 470)
	area.Visible = false
	-- the Quiet soft shade behind the rows (as behind the Plus sheet): the rows hold over the busy rules board, a
	-- window or a lamp. No edge on screen: taller than the screen, run off its right side, its left side faded out.
	local SHADE_FEATHER = 140
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BorderSizePixel = 0
	shade.BackgroundColor3 = C.Shade
	shade.BackgroundTransparency = 0.42
	shade.ZIndex = 0
	shade.AnchorPoint = Vector2.new(0, 0.5)
	shade.Position = UDim2.new(0, -SHADE_FEATHER, 0.5, 0)
	shade.Size = UDim2.new(1, SHADE_FEATHER + 80, 0, 3000)
	local fade = Instance.new("UIGradient")
	fade.Name = "Fade"
	fade.Parent = shade
	local function paintFade()
		local width = math.max(shade.AbsoluteSize.X, SHADE_FEATHER + 1)
		local f = math.clamp(SHADE_FEATHER / width, 0.01, 0.6)
		local k = NumberSequenceKeypoint.new
		fade.Transparency = NumberSequence.new({ k(0, 1), k(f * 0.4, 0.7), k(f * 0.75, 0.2), k(f, 0), k(1, 0) })
	end
	shade:GetPropertyChangedSignal("AbsoluteSize"):Connect(paintFade)
	paintFade()
	shade.Parent = area
	local holder = Instance.new("Frame")
	holder.Name = "Body"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, if compact then 2 else 8)
	list.Parent = holder
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, if compact then 44 else 34)
	head.LayoutOrder = 0
	local title = QuietUI.label({ Name = "Title", Text = "LOADOUT", Font = "SemiBold", TextSize = Theme.TextSize.Heading,
		Size = UDim2.new(0, 240, 1, 0) })
	title.Parent = head
	R.title = title
	local lockedLine = QuietUI.label({ Name = "Locked", Text = "LOCKED  \u{00B7}  launching", Font = "SemiBold",
		TextSize = Theme.TextSize.Label, TextColor3 = C.Sun, Position = UDim2.fromOffset(250, 0), Size = UDim2.new(0, 200, 1, 0),
		Visible = false })
	lockedLine.Parent = head
	local nextRound = QuietUI.label({ Name = "Note", Text = "for your next round", Font = "Medium", TextSize = Theme.TextSize.Caption,
		TextColor3 = C.Ink2, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 200, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right, Visible = not compact })
	nextRound.Parent = head
	head.Parent = holder
	R.locked = lockedLine
	for i, row in ipairs(ROWS) do
		makeRow(holder, row, i)
	end
	-- touch: one shared line for whatever was touched last
	local shared = QuietUI.label({ Name = "Shared", Text = "", Font = "Medium", TextSize = Theme.TextSize.Caption, TextColor3 = C.Ink2,
		Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 20, TextTruncate = Enum.TextTruncate.AtEnd, Visible = compact })
	shared.Parent = holder
	R.shared = if compact then shared else nil
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, if compact then 44 else 40)
	foot.LayoutOrder = 30
	local gold = QuietUI.label({ Name = "Gold", Text = "", Font = "Mono", TextSize = Theme.TextSize.Body,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0), Size = UDim2.fromOffset(160, 24),
		TextXAlignment = Enum.TextXAlignment.Right })
	gold.Parent = if compact then head else foot
	R.gold = gold
	local done = QuietUI.button({ Name = "Done", Text = "DONE", TextSize = Theme.TextSize.Body, Height = if compact then 44 else 34,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) })
	QuietUI.bindButton(done)
	done.Activated:Connect(function()
		close()
	end)
	done.Parent = if compact then head else foot
	foot.Visible = not compact -- (a phone: Gold and DONE sit in the head line, top right)
	local keysHint = QuietUI.label({ Name = "Keys", Text = "", Font = "Medium", TextSize = Theme.TextSize.Caption, TextColor3 = C.Ink2,
		Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -280, 1, 0), Visible = not compact })
	keysHint.Text = "Click to choose  \u{00B7}  hold a price to buy  \u{00B7}  L or DONE closes"
	keysHint.Parent = foot
	R.keys = keysHint
	foot.Parent = holder
	holder.Parent = area
	QuietUI.fit(holder, Vector2.new(if compact then 500 else 560, if compact then 330 else 450), { min = if compact then 0.92 else 0.72, max = 1 })
	area.Parent = root
	R.sheet = area

	-- tapping the avatar's side (the left of the screen) closes it on touch
	local tapOut = Instance.new("TextButton")
	tapOut.Name = "TapOut"
	tapOut.BackgroundTransparency = 1
	tapOut.Text = ""
	tapOut.AutoButtonColor = false
	tapOut.Selectable = false
	tapOut.AnchorPoint = Vector2.new(1, 0.5)
	tapOut.Position = UDim2.new(0, -24, 0.5, 0)
	tapOut.Size = UDim2.new(0, 2000, 1, 0)
	tapOut.Visible = compact
	tapOut.Parent = area
	tapOut.Activated:Connect(function()
		close()
	end)
end

local function placeSummary()
	local holder = R.summary
	if not holder then
		return
	end
	if Input.isTouch() then
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 96)
	else
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -28)
	end
	if R.summaryKey then
		QuietUI.setKey(R.summaryKey, if Input.isGamepad() then "\u{2192}" elseif Input.isTouch() then "TAP" else "L")
	end
end

local function buildSummary(root: Frame)
	local holder = Instance.new("Frame")
	holder.Name = "Summary"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(720, 44)
	holder.AutomaticSize = Enum.AutomaticSize.X
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = holder
	local text = QuietUI.button({ Name = "Line", Text = "", Font = "Medium", TextSize = Theme.TextSize.Label, Height = 30,
		LayoutOrder = 1, Quiet = true })
	text.TextTransparency = REST
	QuietUI.bindButton(text, { quiet = true })
	text.Activated:Connect(open)
	text.Parent = holder
	local gap = Instance.new("Frame")
	gap.BackgroundTransparency = 1
	gap.Size = UDim2.fromOffset(14, 1)
	gap.LayoutOrder = 2
	gap.Parent = holder
	local key = QuietUI.key({ Text = "L", LayoutOrder = 3 })
	key.Parent = holder
	local word = QuietUI.button({ Name = "Open", Text = "Loadout", Font = "SemiBold", TextSize = Theme.TextSize.Label, Height = 30,
		LayoutOrder = 4 })
	QuietUI.bindButton(word)
	word.Activated:Connect(open)
	word.Parent = holder
	local tick = QuietUI.label({ Name = "Saved", Text = "Saved", Font = "Medium", TextSize = Theme.TextSize.Caption, TextColor3 = C.Ink2,
		Size = UDim2.fromOffset(48, 30), LayoutOrder = 5, Visible = false })
	tick.Parent = holder
	holder.Parent = root
	R.summary = holder
	R.summaryText = text
	R.summaryKey = key
	R.saved = tick
	placeSummary()
end

-- The rack's prompt, drawn here (the HUD's prompt line sleeps in the train): "[E] Loadout" under the middle of the
-- screen while you stand at the rack; on touch the words are the button.
local function buildNear(root: Frame)
	local holder = Instance.new("Frame")
	holder.Name = "Near"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.62, 0)
	holder.Size = UDim2.fromOffset(200, 44)
	holder.Visible = false
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = holder
	local key = QuietUI.key({ Text = "E", LayoutOrder = 1 })
	key.Parent = holder
	local word = QuietUI.button({ Name = "Word", Text = "Loadout", Font = "Medium", TextSize = Theme.TextSize.Body, Height = 34,
		LayoutOrder = 2 })
	QuietUI.bindButton(word)
	word.Activated:Connect(open)
	word.Parent = holder
	holder.Parent = root
	R.near = holder
	R.nearKey = key
end

local function onPromptShown(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Name ~= "Loadout" or not prompt:GetAttribute("LoadoutHooked") or not R.near then
		return
	end
	QuietUI.setKey(R.nearKey, if inputType == Enum.ProximityPromptInputType.Touch then "TAP"
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then "X" else "E")
	R.near.Visible = not isOpen and lobbyShowing()
end

local function onPromptHidden(prompt: ProximityPrompt)
	if prompt.Name == "Loadout" and R.near then
		R.near.Visible = false
	end
end

local function hookStation(s: Instance)
	if not s:IsA("Model") or s.Name ~= "LoadoutStation" then
		return
	end
	local function hook(prompt: Instance)
		if prompt:IsA("ProximityPrompt") and prompt.Name == "Loadout" and not prompt:GetAttribute("LoadoutHooked") then
			prompt:SetAttribute("LoadoutHooked", true)
			prompt.Triggered:Connect(function(who)
				if who == player then
					open()
				end
			end)
		end
	end
	for _, d in ipairs(s:GetDescendants()) do
		hook(d)
	end
	s.DescendantAdded:Connect(hook)
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function LoadoutController.Init(controllers)
	Controllers = controllers
end

function LoadoutController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "Loadout"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.DisplayOrder = 6
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = root
	root.Parent = screen
	screen.Parent = playerGui
	gui = screen
	saved = readSaved()
	buildSummary(root)
	buildNear(root)
	buildSheet(root)
	local promptService = game:GetService("ProximityPromptService")
	promptService.PromptShown:Connect(onPromptShown)
	promptService.PromptHidden:Connect(onPromptHidden)
	task.spawn(pcall, QuietUI.bindRoot, screen)

	Input.deviceChanged:Connect(function()
		placeSummary()
		if not isOpen and isCompact() ~= compact then
			buildSheet(root)
		end
	end)
	local function relayout()
		if not isOpen and isCompact() ~= compact then
			buildSheet(root)
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	player:GetAttributeChangedSignal("LoadoutTouchLayout"):Connect(relayout)

	ClientState.lifeChanged:Connect(LoadoutController.refresh)
	ClientState.spectateChanged:Connect(LoadoutController.refresh)
	for _, attribute in ipairs({ "Kit", "KitBring", "KitArmoury", "LoadoutSpecialty", "LoadoutGeneral", "TrailSwing", "TrailArrow",
		"TrailThrow", "TrailsOwned", "Gold" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if isOpen then
				if attribute == "KitArmoury" then
					buildOptions("bring")
				elseif attribute == "TrailsOwned" then
					buildOptions("trail")
				end
				paintAll()
			else
				LoadoutController.refresh()
			end
		end)
	end
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		if isOpen then
			if locked() and os.clock() - lastSentAt > 0.5 then
				send(false) -- the call came while it is open: what is chosen now counts
			end
			paintAll()
		end
	end)
	-- the menu flag can change under us (Settings, the Plus sheet): a cheap re-check twice a second
	task.spawn(function()
		while screen.Parent do
			task.wait(0.5)
			local want = lobbyShowing() and not isOpen and not ClientState.menuOpen
			if R.summary and R.summary.Visible ~= want then
				LoadoutController.refresh()
			end
			syncKeys()
		end
	end)

	-- the keys (Shared.Input action "Loadout", so InputCheck sees them): kept in step with the lobby, the screen and
	-- the menus by syncKeys (the summary line refresh, open, close, the GUI selection and the twice-a-second check)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(syncKeys)
	syncKeys()

	RunService:BindToRenderStep("LoadoutBody", Enum.RenderPriority.Camera.Value + 2, function()
		if isOpen then
			showOwnBody()
		end
	end)

	local lobby = workspace:WaitForChild("Lobby", 30)
	if lobby then
		local s = lobby:FindFirstChild("LoadoutStation")
		if s then
			hookStation(s)
		end
		lobby.ChildAdded:Connect(hookStation)
	end
	task.spawn(function()
		local ok, remote = pcall(Net.event, "Trails")
		if ok and remote then
			trailsRemote = remote
			remote.OnClientEvent:Connect(function(kind, a)
				if kind == "bought" and type(a) == "string" then
					onBought(a)
				elseif kind == "line" and type(a) == "string" and isOpen then
					setDetail("trail", a)
				end
			end)
		end
	end)
	LoadoutController.refresh()
end

return LoadoutController
