--[[
	PrepareController - the one "Prepare" screen before a round (owner, 20 Nov: "you havent fully furnished the game UI
	for kit choosing etc it should be more easy and intuitive and nicer looking for people").

	WHAT THE PLAYER SEES
	  * A big PREPARE button at the bottom centre of the screen in the train and the Training Centre (kit picture, the
	    word PREPARE in amber until you are ready, your kit and skill in a short line, the key: L / View). Click, tap,
	    L, or the gamepad's View / D-pad right opens it. The Loadout rack (E) and the hub's Loadout card open it too.
	  * It opens BY ITSELF once per pre-round, a moment after you step off the train into the Training Centre (after
	    the daily reward, the loading screen or any other menu has gone), unless you already pressed READY.
	  * Three steps in a strip across the top: 1 KIT · 2 SKILLS · 3 TRAIL, each showing what is chosen. Tap a step, or
	    use NEXT / BACK, LB / RB (Q / E on a keyboard).
	      KIT     five big picture cards: name, one line, three simple bars (Fight, Survive, Move), what lands for you.
	      SKILLS  two rows of cards: WEAPON SKILL (R) and GENERAL SKILL (F); icon, name, one line, a Recharge bar.
	              The weapon skill that suits your kit carries "SUITS YOUR KIT" (and follows the kit until you pick one).
	      TRAIL   SWING · ARROW · THROW, then the trails as cards with a moving preview; OWNED or a price with a padlock.
	              A locked one you can afford: HOLD TO BUY (0.6 s), bought with Gold through TrailService as before.
	  * Tap a card to choose it: an amber outline and an amber tick. Locked cards are dimmed with a padlock.
	  * Sensible defaults are always chosen (what the server already holds: Forager, its weapon skill, Second Wind,
	    Draught), so a player who ignores the screen is fine.
	  * One big amber READY button bottom-right. A timer top-right ("LOCKS IN 0:42") while the call is coming.
	  * "Saved loadouts & more" opens the full Loadout screen (LoadoutController: saved cards, the weapon you bring,
	    looks) for players who want it.
	  * Mouse (hover lifts a card), touch (every target 44 px or more; on a phone the rows scroll and one line under
	    them says what was touched) and gamepad (focus ring, A choose, LB / RB steps, Y ready, B close).

	SAVING (no new server code): the same remote and checks as the Loadout screen. Each change sends one LoadoutSet
	{ kit, specialty, general, trails } (KitService checks every value; at most one send every 2.1 s, the remote allows
	2 in 4 s); READY and closing send at once if anything is waiting. The saved loadout cards are left as they are.

	Reads: player attributes Kit, LoadoutSpecialty, LoadoutGeneral, TrailSwing / TrailArrow / TrailThrow, TrailsOwned,
	Gold, AtTrainingCentre, InRedRoom, LoadingScreenUp; GameState Phase, TrainStage, TrainCallAt, TrainRideStart.
	Studio only (pictures): LocalPlayer attribute PrepareTestPhone = Vector2 draws the screen in a box of that size
	(a phone's points, e.g. 844 x 390) on black, as a phone would lay it out.

	API: PrepareController.open(step?), .close(), .isOpen(), .setStep(n), .debugChoose(row, id)
]]
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Catalog = require(Shared:WaitForChild("LoadoutCatalog"))
local Icons = require(Shared:WaitForChild("Icons"))
local Input = require(Shared:WaitForChild("Input"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Kits = require(Shared:WaitForChild("Kits"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Theme = require(Shared:WaitForChild("Theme"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local ProgressUI = require(Client:WaitForChild("ProgressUI"))

local player = Players.LocalPlayer
local GameState = ReplicatedStorage:WaitForChild("GameState")

local PrepareController = {}

--------------------------------------------------------------------------------------------------------------------
-- Look
--------------------------------------------------------------------------------------------------------------------

local INK = Theme.Colors.Ink
local INK2 = Theme.Colors.Ink2
local SHADE = Theme.Colors.Shade
local SUN = Theme.Colors.Sun
local F = Theme.Fonts
local PANEL = Color3.fromRGB(17, 20, 23)
local CARD = Color3.fromRGB(32, 37, 41)
local CARD_ON = Color3.fromRGB(44, 40, 32) -- a chosen card warms a little toward the amber
local WELL = Color3.fromRGB(8, 9, 12)

local FAST = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SOFT = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local STEPS = {
	{ key = "kit", word = "KIT", line = "What lands for you as a parcel mid-round" },
	{ key = "skills", word = "SKILLS", line = "One weapon skill (R) and one general skill (F)" },
	{ key = "trail", word = "TRAIL", line = "Looks only: the streak behind your swings, arrows and throws" },
}

-- plain words for each kit (Shared.Kits holds the items); the bars are 1..5
local KIT_INFO = {
	archer = { line = "A short bow and arrows for fighting at range", fight = 4, survive = 2, move = 2 },
	forager = { line = "A knife, food and water. The safe start", fight = 2, survive = 4, move = 3 },
	hunter = { line = "Throwing knives to hold a path or a camp", fight = 3, survive = 3, move = 2 },
	medic = { line = "Bandages and herbs. No weapon, outlasts", fight = 1, survive = 5, move = 2 },
	climber = { line = "A climbing pick for trees, rock and height", fight = 2, survive = 2, move = 5 },
}
local SLOT_WORDS = { swing = "Swing", arrow = "Arrow", throw = "Throw" }

local SEND_GAP = 2.1 -- KitService allows 2 LoadoutSets in 4 s

--------------------------------------------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------------------------------------------

local Controllers: { [string]: any } = {}
local gui: ScreenGui? = nil
local root: Frame? = nil
local scaleObj: UIScale? = nil
local R: { [string]: any } = {}
local isOpen = false
local step = 1
local pick: any = nil -- { kit, specialty, general, trails = { swing, arrow, throw } }
local specTouched = false -- the player chose a weapon skill himself (else it follows the kit)
local trailSlot = "swing"
local buyId: string? = nil
local cardsByStep: { [number]: { [string]: TextButton } } = {}
local readyKey: string? = nil -- the pre-round READY was pressed in
local autoKey: string? = nil -- the pre-round the screen opened by itself in
local arrivedAt: number? = nil
local lastSend = -10
local sendQueued = false
local unbindShoulders: (() -> ())? = nil
local trailApis: { any } = {}
local focusRing: GuiObject? = nil
local closing = false

--------------------------------------------------------------------------------------------------------------------
-- Small builders
--------------------------------------------------------------------------------------------------------------------

local function make(class: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		(inst :: any).BorderSizePixel = 0
	end
	if props then
		for k, v in pairs(props) do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function frame(name: string, parent: Instance?, props: { [string]: any }?): Frame
	local f = make("Frame", { Name = name, BackgroundTransparency = 1 }, nil)
	if props then
		for k, v in pairs(props) do
			(f :: any)[k] = v
		end
	end
	f.Parent = parent
	return f
end

local function corner(gui: Instance, px: number)
	make("UICorner", { CornerRadius = UDim.new(0, px) }, gui)
end

local function stroke(gui: Instance, color: Color3, transparency: number, thickness: number, name: string?): UIStroke
	return make("UIStroke", { Name = name or "Stroke", Color = color, Transparency = transparency, Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, gui)
end

local function padding(gui: Instance, l: number, r: number, t: number, b: number)
	make("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r), PaddingTop = UDim.new(0, t),
		PaddingBottom = UDim.new(0, b) }, gui)
end

local function list(parent: Instance, dir: Enum.FillDirection, gap: number, halign: Enum.HorizontalAlignment?,
	valign: Enum.VerticalAlignment?): UIListLayout
	return make("UIListLayout", { FillDirection = dir, Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left, VerticalAlignment = valign or Enum.VerticalAlignment.Top }, parent)
end

local function text(name: string, value: string, size: number, font: Font, color: Color3, parent: Instance?,
	props: { [string]: any }?): TextLabel
	local l = make("TextLabel", { Name = name, BackgroundTransparency = 1, Text = value, TextSize = size, FontFace = font,
		TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, RichText = false }, nil)
	if props then
		for k, v in pairs(props) do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

local function tween(inst: Instance, info: TweenInfo, props: { [string]: any })
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function icon(name: string, parent: Instance, size: number, props: { [string]: any }?): GuiObject?
	local ok, result = pcall(function()
		local p = { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Parent = parent }
		if props then
			for k, v in pairs(props) do
				p[k] = v
			end
		end
		return Icons.make(name, p)
	end)
	return if ok then result else nil
end

--------------------------------------------------------------------------------------------------------------------
-- What is chosen
--------------------------------------------------------------------------------------------------------------------

local function ownedTrails(): { [string]: boolean }
	return Catalog.decodeOwned(player:GetAttribute("TrailsOwned"))
end

local function ownsTrail(id: string): boolean
	return Catalog.isFreeTrail(id) or ownedTrails()[id] == true
end

local function gold(): number
	return tonumber(player:GetAttribute("Gold")) or 0
end

local function readServer()
	local kit = (Kits.get(player:GetAttribute("Kit")) or Kits.default()).id
	local d = Catalog.defaults(kit)
	local out = {
		kit = kit,
		specialty = if Catalog.specialty(player:GetAttribute("LoadoutSpecialty")) then player:GetAttribute("LoadoutSpecialty") else d.specialty,
		general = if Catalog.general(player:GetAttribute("LoadoutGeneral")) then player:GetAttribute("LoadoutGeneral") else d.general,
		trails = {},
	}
	for _, slot in ipairs(Catalog.Slots) do
		local id = player:GetAttribute(Catalog.SlotAttr[slot])
		out.trails[slot] = if Catalog.trail(id) then id else d.trails[slot]
	end
	return out
end

local function current()
	return pick or readServer()
end

local function roundKey(): string
	return tostring(GameState:GetAttribute("TrainRideStart") or GameState:GetAttribute("RoundId") or 0)
end

local function isReady(): boolean
	return readyKey ~= nil and readyKey == roundKey()
end

local function lobbyShowing(): boolean
	if RunService:IsStudio() and player:GetAttribute("CardsTestForce") == true then
		return true
	end
	return not ClientState.inArena and ClientState.spectating == nil and player:GetAttribute("InArena") ~= true
end

local function lockedNow(): boolean
	return GameState:GetAttribute("Phase") == "Countdown"
end

-- the call to launch, when it is coming (choices lock then)
local function deadline(): number?
	local now = workspace:GetServerTimeNow()
	local at = tonumber(GameState:GetAttribute("TrainCallAt"))
	local stage = GameState:GetAttribute("TrainStage")
	if at and at > now and at - now < 900 and (stage == "Training" or stage == "Ride" or GameState:GetAttribute("Phase") == "Intermission") then
		return at
	end
	return nil
end

local function payload()
	local l = current()
	local trails = {}
	local server = readServer()
	for _, slot in ipairs(Catalog.Slots) do
		local id = l.trails[slot]
		trails[slot] = if ownsTrail(id) and Catalog.trailFits(id, slot) then id else server.trails[slot]
	end
	return { kit = l.kit, specialty = l.specialty, general = l.general, trails = trails }
end

-- the newest choice waiting to go (it survives the screen closing: the remote's limit may hold it a moment)
local pending: any = nil

local function flush()
	sendQueued = false
	local p = pending
	pending = nil
	if not p or lockedNow() then
		return
	end
	lastSend = os.clock()
	pcall(function()
		Net.event("LoadoutSet"):FireServer(p)
	end)
end

local function queueSend(now: boolean?)
	if pick then
		pending = payload()
	end
	if not pending then
		return
	end
	local waitFor = math.max(0, SEND_GAP - (os.clock() - lastSend))
	if now and waitFor <= 0 then
		flush()
		return
	end
	if sendQueued then
		return
	end
	sendQueued = true
	task.delay(waitFor, function()
		if sendQueued then
			flush()
		end
	end)
end

--------------------------------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------------------------------

local function rootSize(): Vector2
	if root and root.AbsoluteSize.X > 2 then
		local s = if scaleObj then scaleObj.Scale else 1
		return root.AbsoluteSize / s
	end
	return Vector2.new(1280, 720)
end

local function compact(): boolean
	local s = rootSize()
	return s.Y < 520 or s.X < 900
end

local function touchy(): boolean
	return Input.isTouch() or compact()
end

local function applyScale()
	if not gui or not root or not scaleObj then
		return
	end
	local test = RunService:IsStudio() and player:GetAttribute("PrepareTestPhone")
	local backdrop = gui:FindFirstChild("TestBackdrop")
	if typeof(test) == "Vector2" then
		scaleObj.Scale = 1
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Size = UDim2.fromOffset(test.X, test.Y)
		if not backdrop then
			backdrop = frame("TestBackdrop", gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0,
				BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 0 })
		end
		(backdrop :: Frame).Visible = isOpen
		if R.scrim then
			R.scrim.Visible = false
		end
		return
	end
	if backdrop then
		backdrop:Destroy()
	end
	if R.scrim then
		R.scrim.Visible = true
	end
	local size = gui.AbsoluteSize
	if size.X < 2 then
		local cam = workspace.CurrentCamera
		size = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	end
	local s = Theme.scaleFor(size, GuiService:IsTenFootInterface())
	scaleObj.Scale = s
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromScale(0, 0)
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end

--------------------------------------------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------------------------------------------

local function setChosen(card: TextButton, on: boolean, instant: boolean?)
	local edge = card:FindFirstChild("Edge") :: UIStroke?
	local check = card:FindFirstChild("Check") :: Frame?
	card:SetAttribute("Chosen", on)
	local info = if instant then TweenInfo.new(0) else FAST
	if edge then
		tween(edge, info, { Color = if on then SUN else INK, Transparency = if on then 0 else 0.82,
			Thickness = if on then 2.5 else 1.5 })
	end
	tween(card, info, { BackgroundColor3 = if on then CARD_ON else CARD })
	if check then
		local sc = check:FindFirstChildOfClass("UIScale")
		if on then
			check.Visible = true
			if sc and not instant then
				sc.Scale = 0.4
				tween(sc, POP, { Scale = 1 })
			elseif sc then
				sc.Scale = 1
			end
		else
			check.Visible = false
		end
	end
end

local function makeCard(parent: Instance, def: { [string]: any }): TextButton
	local card = make("TextButton", { Name = def.name, Text = "", AutoButtonColor = false, BackgroundColor3 = CARD,
		BackgroundTransparency = 0.1, Size = def.size, LayoutOrder = def.order or 0, ClipsDescendants = false,
		Selectable = true }, nil)
	corner(card, 10)
	stroke(card, INK, 0.82, 1.5, "Edge")
	local sc = make("UIScale", { Name = "Hover" }, card)
	if focusRing then
		card.SelectionImageObject = focusRing
	end
	-- the picture well (on top; or on the left, def.side = its width in px, for short rows on a phone)
	local wellH = def.wellH or 0.42
	local well = frame("Well", card, { BackgroundTransparency = 0.35, BackgroundColor3 = WELL,
		Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, wellH, -8), ClipsDescendants = true })
	if def.side then
		well.Size = UDim2.new(0, def.side, 1, -16)
	end
	corner(well, 7)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.1, 0.45) }, well)
	if def.picture then
		def.picture(well)
	end
	-- the words under it
	local body = frame("Body", card, { Position = UDim2.new(0, 12, wellH, 6), Size = UDim2.new(1, -24, 1 - wellH, -14) })
	if def.side then
		body.Position = UDim2.fromOffset(def.side + 16, 8)
		body.Size = UDim2.new(1, -def.side - 26, 1, -14)
	end
	list(body, Enum.FillDirection.Vertical, def.gap or 4)
	if def.fill then
		def.fill(body)
	end
	-- the chosen tick (amber disc)
	local check = frame("Check", card, { BackgroundTransparency = 0, BackgroundColor3 = SUN, Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Visible = false, ZIndex = 5 })
	corner(check, 13)
	make("UIScale", {}, check)
	stroke(check, SHADE, 0.4, 1.5)
	icon("tick", check, 16, { Tone = SHADE, ZIndex = 6 })
	-- a tag (top-left): SUITS YOUR KIT, OWNED ... (def.tagTop: it sits on the card's top edge, clear of a short
	-- picture well, so a skill card's icon is never covered)
	if def.tag then
		local tag = text("Tag", def.tag, 11, F.SemiBold, SHADE, card, { BackgroundTransparency = 0,
			BackgroundColor3 = def.tagColor or INK, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18),
			Position = if def.tagTop then UDim2.fromOffset(10, -9) else UDim2.fromOffset(12, 12), ZIndex = 7,
			TextXAlignment = Enum.TextXAlignment.Center })
		padding(tag, 6, 6, 0, 0)
		corner(tag, 4)
	end
	if def.locked then
		card.BackgroundTransparency = 0.3
		local lock = frame("Lock", well, { BackgroundTransparency = 0.25, BackgroundColor3 = SHADE,
			Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -6), ZIndex = 4 })
		corner(lock, 13)
		icon("lock", lock, 16, { Tone = INK2, ZIndex = 5 })
	end
	-- hover lifts it (mouse); touch has no hover
	card.MouseEnter:Connect(function()
		tween(sc, FAST, { Scale = 1.02 })
		local edge = card:FindFirstChild("Edge") :: UIStroke?
		if edge and card:GetAttribute("Chosen") ~= true then
			tween(edge, FAST, { Transparency = 0.45 })
		end
		if def.hover then
			def.hover()
		end
	end)
	card.MouseLeave:Connect(function()
		tween(sc, FAST, { Scale = 1 })
		local edge = card:FindFirstChild("Edge") :: UIStroke?
		if edge and card:GetAttribute("Chosen") ~= true then
			tween(edge, FAST, { Transparency = 0.82 })
		end
	end)
	card.SelectionGained:Connect(function()
		if def.hover then
			def.hover()
		end
	end)
	card.Activated:Connect(function()
		if def.onActivate then
			def.onActivate()
		end
	end)
	card.Parent = parent
	return card
end

-- five pips (Fight / Survive / Move)
local function statRow(parent: Instance, word: string, value: number, order: number, w: number)
	local row = frame("Stat" .. word, parent, { Size = UDim2.new(1, 0, 0, 14), LayoutOrder = order })
	text("Word", string.upper(word), 12, F.SemiBold, INK2, row, { Size = UDim2.new(0, 64, 1, 0) })
	local pips = frame("Pips", row, { Position = UDim2.fromOffset(66, 3), Size = UDim2.new(1, -66, 0, 8) })
	list(pips, Enum.FillDirection.Horizontal, 3, nil, Enum.VerticalAlignment.Center)
	local pw = math.max(8, math.floor((w - 66 - 12) / 5))
	for i = 1, 5 do
		local pip = frame("P" .. i, pips, { BackgroundTransparency = if i <= value then 0.08 else 0.82,
			BackgroundColor3 = INK, Size = UDim2.fromOffset(pw, 6), LayoutOrder = i })
		corner(pip, 3)
	end
end

local function rechargeRow(parent: Instance, cooldown: number, order: number)
	local row = frame("Recharge", parent, { Size = UDim2.new(1, 0, 0, 14), LayoutOrder = order })
	local ic = frame("Clock", row, { Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(0, 1) })
	icon("cooldown", ic, 12, { Tone = INK2 })
	text("Secs", string.format("%d s", cooldown), 12, F.Mono, INK2, row, { Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(0, 34, 1, 0) })
	local track = frame("Track", row, { BackgroundTransparency = 0.84, BackgroundColor3 = INK,
		Position = UDim2.new(0, 54, 0.5, -2), Size = UDim2.new(1, -54, 0, 4) })
	corner(track, 2)
	-- faster recharge = fuller bar (10 s full, 60 s a sliver)
	local a = math.clamp(1 - (cooldown - 10) / 55, 0.12, 1)
	local fill = frame("Fill", track, { BackgroundTransparency = 0.1, BackgroundColor3 = INK, Size = UDim2.fromScale(a, 1) })
	corner(fill, 2)
end

--------------------------------------------------------------------------------------------------------------------
-- The shared line (what was touched / hovered)
--------------------------------------------------------------------------------------------------------------------

local function setNote(value: string, sun: boolean?)
	local note = R.note :: TextLabel?
	if note then
		note.Text = value
		note.TextColor3 = if sun then SUN else INK2
	end
end

local function defaultNote()
	if Input.isGamepad() then
		setNote("A choose  ·  LB / RB steps  ·  Y ready  ·  B close")
	elseif Input.isTouch() then
		setNote("Tap a card to choose it")
	else
		setNote("Click a card to choose it  ·  Q / E change step  ·  L close")
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Steps
--------------------------------------------------------------------------------------------------------------------

local buildStep: (dir: number?) -> ()
local refreshStrip: () -> ()

local function markStep(n: number, chosenId: string, group: string?)
	local cards = cardsByStep[n]
	if not cards then
		return
	end
	for id, card in pairs(cards) do
		local g = card:GetAttribute("Group")
		if group == nil or g == group then
			setChosen(card, id == chosenId)
		end
	end
end

local function choose(row: string, id: string)
	if not pick or lockedNow() then
		return
	end
	local changed = false
	if row == "kit" and Kits.get(id) and pick.kit ~= id then
		local before = Catalog.suggestedSpecialty(pick.kit)
		pick.kit = id
		changed = true
		-- the weapon skill follows the kit until the player picks one himself
		if not specTouched or pick.specialty == before then
			pick.specialty = Catalog.suggestedSpecialty(id)
		end
		markStep(1, id)
	elseif row == "specialty" and Catalog.specialty(id) then
		specTouched = true
		if pick.specialty ~= id then
			pick.specialty = id
			changed = true
		end
		markStep(2, "s:" .. id, "s")
	elseif row == "general" and Catalog.general(id) then
		if pick.general ~= id then
			pick.general = id
			changed = true
		end
		markStep(2, "g:" .. id, "g")
	elseif row == "trail" and Catalog.trail(id) and Catalog.trailFits(id, trailSlot) then
		if ownsTrail(id) then
			buyId = nil
			if pick.trails[trailSlot] ~= id then
				pick.trails[trailSlot] = id
				changed = true
			end
			markStep(3, id)
			if R.slotChips and R.slotChips[trailSlot] then
				R.slotChips[trailSlot].Value.Text = (Catalog.trail(id) :: any).name
			end
		end
	end
	if changed then
		Sfx.play("UIClick", { pitch = 1.05 })
		queueSend(false)
		refreshStrip()
	end
end

local function chooseFeedback(line: string)
	setNote(line, false)
end

-- KIT
local function kitStep(body: Frame, size: Vector2)
	local cards = {}
	cardsByStep[1] = cards
	local small = compact()
	local gap = if small then 10 else 16
	local n = #Kits.List
	local holder: GuiObject
	local w: number
	if small then
		local sc = make("ScrollingFrame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X,
			CanvasSize = UDim2.new(), ScrollBarThickness = 4, ScrollBarImageColor3 = INK, ScrollBarImageTransparency = 0.6,
			ElasticBehavior = Enum.ElasticBehavior.Always, Selectable = false }, body)
		padding(sc, 3, 3, 3, 3)
		holder = sc
		w = math.clamp(math.floor((size.X - gap * 2) / 3.3), 150, 200)
	else
		holder = frame("Row", body, { Size = UDim2.fromScale(1, 1) })
		w = math.floor((size.X - gap * (n - 1)) / n)
	end
	local l = list(holder, Enum.FillDirection.Horizontal, gap)
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	local h = size.Y - (if small then 8 else 0)
	local roomy = h >= 300
	-- a short page (a phone in landscape: about 150 px) cannot stack picture, name, line and three bars; the picture
	-- goes on the left then, and the card is a little wider so the line still fits on two rows
	local side = if small and h < 230 then math.min(h - 16, 64) else nil
	if side then
		w = math.max(w, 236)
	end
	local bodyW = if side then w - side - 26 else w - 24
	for i, kit in ipairs(Kits.List) do
		local info = KIT_INFO[kit.id] or { line = kit.forWhom or "", fight = 2, survive = 2, move = 2 }
		local card = makeCard(holder, {
			name = "Kit_" .. kit.id, order = i, size = UDim2.fromOffset(w, h), wellH = if roomy then 0.4 else 0.36,
			tag = if kit.id == Kits.default().id and not side then "STARTER" else nil, side = side,
			picture = function(well)
				icon(Icons.forKit(kit.id), well, if side then math.floor(side * 0.72)
					else math.floor(math.min(w * 0.55, h * (if roomy then 0.4 else 0.36) * 0.75)))
			end,
			fill = function(b)
				text("Name", kit.name, if small then 18 else 22, F.SemiBold, INK, b, { Size = UDim2.new(1, if side then -24 else 0, 0, if small then 22 else 28), LayoutOrder = 1 })
				text("Line", info.line, if small then 12 else 14, F.Medium, INK2, b, { Size = UDim2.new(1, 0, 0, if small then 30 else 36),
					TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2, TextTruncate = Enum.TextTruncate.None })
				frame("Gap", b, { Size = UDim2.new(1, 0, 0, if small then 0 else 4), LayoutOrder = 3 })
				statRow(b, "Fight", info.fight, 4, bodyW)
				statRow(b, "Survive", info.survive, 5, bodyW)
				statRow(b, "Move", info.move, 6, bodyW)
				if roomy then
					frame("Gap2", b, { Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 7 })
					local items = frame("Items", b, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 8 })
					list(items, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
					for j, item in ipairs(kit.items) do
						local tile = frame("I" .. j, items, { BackgroundTransparency = 0.5, BackgroundColor3 = WELL,
							Size = UDim2.fromOffset(40, 40), LayoutOrder = j })
						corner(tile, 6)
						icon(Icons.forItem(item.id), tile, 28)
						if (item.count or 1) > 1 then
							text("Count", "\u{00D7}" .. item.count, 10, F.SemiBold, INK, tile, { AnchorPoint = Vector2.new(1, 1),
								Position = UDim2.new(1, -2, 1, 0), Size = UDim2.fromOffset(20, 12),
								TextXAlignment = Enum.TextXAlignment.Right, TextStrokeColor3 = SHADE, TextStrokeTransparency = 0.3 })
						end
					end
				end
			end,
			hover = function()
				local names = {}
				for _, item in ipairs(kit.items) do
					local def = ItemDefs.get(item.id)
					local nm = if def then def.name else item.id
					table.insert(names, if (item.count or 1) > 1 then string.format("%s \u{00D7}%d", nm, item.count) else nm)
				end
				chooseFeedback(kit.name .. ":  " .. table.concat(names, ", "))
			end,
			onActivate = function()
				choose("kit", kit.id)
			end,
		})
		cards[kit.id] = card
	end
	local l2 = current()
	for id, card in pairs(cards) do
		setChosen(card, id == l2.kit, true)
	end
end

-- SKILLS
local function skillsStep(body: Frame, size: Vector2)
	local cards = {}
	cardsByStep[2] = cards
	local small = compact()
	local gap = if small then 8 else 12
	local head = if small then 18 else 22
	local rowH = math.floor((size.Y - head * 2 - gap * 3) / 2)
	local l = current()
	local suits = Catalog.suggestedSpecialty(l.kit)
	local col = list(body, Enum.FillDirection.Vertical, gap)
	local _ = col
	local function section(order: number, word: string, key: string, tail: string)
		local s = frame("Head" .. order, body, { Size = UDim2.new(1, 0, 0, head), LayoutOrder = order })
		local k = text("Key", key, 11, F.MonoMedium, INK, s, { Size = UDim2.fromOffset(18, 18), Position = UDim2.new(0, 0, 0.5, -9),
			TextXAlignment = Enum.TextXAlignment.Center })
		corner(k, 4)
		stroke(k, INK, 0.5, 1)
		text("Word", word, if small then 12 else 13, F.SemiBold, INK, s, { Position = UDim2.fromOffset(26, 0),
			Size = UDim2.new(0, 160, 1, 0), AutomaticSize = Enum.AutomaticSize.X })
		text("Tail", tail, 12, F.Medium, INK2, s, { Position = UDim2.fromOffset(if small then 150 else 170, 0), Size = UDim2.new(1, -170, 1, 0) })
	end
	local function row(order: number, count: number): (GuiObject, number)
		local w
		local holder: GuiObject
		if small then
			holder = make("ScrollingFrame", { Name = "Row" .. order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rowH),
				ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(),
				ScrollBarThickness = 3, ScrollBarImageColor3 = INK, ScrollBarImageTransparency = 0.6, LayoutOrder = order,
				Selectable = false }, body)
			padding(holder, 3, 3, 3, 3)
			w = 196
		else
			holder = frame("Row" .. order, body, { Size = UDim2.new(1, 0, 0, rowH), LayoutOrder = order })
			w = math.floor((size.X - gap * 6) / 7)
		end
		list(holder, Enum.FillDirection.Horizontal, gap)
		return holder, w
	end
	local roomy = rowH >= 140
	local side = if rowH < 120 then rowH - 16 else nil
	-- (hunt1_1) in a phone's scrolling row the card sits inside 3 px of padding at top and bottom: it is 6 px shorter
	-- so its lower edge is not cut off; and a very short side card (about 44 px) has room for the name and one small
	-- line only, so the recharge goes into that line ("SWORD · 18 S") instead of a bar that would be cut off
	local cardH = if small then rowH - 6 else rowH
	local tight = side ~= nil and cardH < 64
	local function skillCard(holder: GuiObject, w: number, i: number, key: string, iconName: string, name: string,
		sub: string?, line: string, cooldown: number, tag: string?, onPick: () -> ())
		local card = makeCard(holder, {
			name = key, order = i, size = UDim2.fromOffset(w, cardH), wellH = if roomy then 0.38 else 0.36,
			tag = if side then nil else tag, tagColor = SUN, tagTop = true, gap = 2, side = side,
			picture = function(well)
				icon(iconName, well, if side then math.floor(side * 0.7) else math.floor(math.min(w * 0.42, rowH * 0.38 * 0.72)))
			end,
			fill = function(b)
				-- (a side card keeps the name clear of the tick, top right)
				text("Name", name, if small then 14 else 16, F.SemiBold, INK, b, { Size = UDim2.new(1, if side then -24 else 0, 0, 20), LayoutOrder = 1 })
				if tight then
					local word = if tag then tag elseif sub then string.upper(sub) else "RECHARGE"
					text("Sub", string.format("%s  ·  %d S", word, cooldown), 10, F.SemiBold, if tag then SUN else INK2, b,
						{ Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd })
				elseif side and tag then
					text("Sub", tag, 10, F.SemiBold, SUN, b, { Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 2 })
				elseif sub then
					text("Sub", string.upper(sub), 10, F.SemiBold, INK2, b, { Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 2 })
				end
				if roomy then
					text("Line", line, 12, F.Medium, INK2, b, { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 3, TextTruncate = Enum.TextTruncate.AtEnd })
				end
				if not tight then
					frame("Gap", b, { Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 4 })
					rechargeRow(b, cooldown, 5)
				end
			end,
			hover = function()
				chooseFeedback(name .. ":  " .. line .. "  ·  recharges in " .. cooldown .. " s")
			end,
			onActivate = function()
				onPick()
				chooseFeedback(name .. ":  " .. line)
			end,
		})
		return card
	end
	section(1, "WEAPON SKILL", "R", "works while you hold a weapon of its kind")
	local wrow, ww = row(2, #Catalog.Specialties)
	for i, spec in ipairs(Catalog.Specialties) do
		local key = "s:" .. spec.id
		local card = skillCard(wrow, ww, i, key, Icons.forSkill(spec.id), spec.skill.name, spec.name, spec.skill.line,
			spec.skill.cooldown, if spec.id == suits then "SUITS YOUR KIT" else nil, function()
				choose("specialty", spec.id)
			end)
		card:SetAttribute("Group", "s")
		cards[key] = card
	end
	section(3, "GENERAL SKILL", "F", "works with anything, any time")
	local grow, gw = row(4, #Catalog.General)
	for i, g in ipairs(Catalog.General) do
		local key = "g:" .. g.id
		local card = skillCard(grow, gw, i, key, Icons.forSkill(g.id), g.name, nil, g.line, g.cooldown, nil, function()
			choose("general", g.id)
		end)
		card:SetAttribute("Group", "g")
		cards[key] = card
	end
	for key, card in pairs(cards) do
		setChosen(card, key == "s:" .. l.specialty or key == "g:" .. l.general, true)
	end
end

-- TRAIL
local function trailStep(body: Frame, size: Vector2)
	local cards = {}
	cardsByStep[3] = cards
	local small = compact()
	local gap = if small then 8 else 12
	local l = current()
	-- the three slots
	local chipH = if touchy() then 48 else 46
	local chips = frame("Slots", body, { Size = UDim2.new(1, 0, 0, chipH) })
	list(chips, Enum.FillDirection.Horizontal, gap, nil, Enum.VerticalAlignment.Center)
	R.slotChips = {}
	for i, slot in ipairs(Catalog.Slots) do
		local on = slot == trailSlot
		local chip = make("TextButton", { Name = "Slot_" .. slot, Text = "", AutoButtonColor = false, LayoutOrder = i,
			BackgroundColor3 = if on then CARD_ON else CARD, BackgroundTransparency = 0.1,
			Size = UDim2.new(0, if small then 150 else 190, 1, 0) }, chips)
		corner(chip, 8)
		stroke(chip, if on then SUN else INK, if on then 0 else 0.8, if on then 2 else 1.5, "Edge")
		if focusRing then
			chip.SelectionImageObject = focusRing
		end
		text("Word", string.upper(SLOT_WORDS[slot]), 11, F.SemiBold, if on then SUN else INK2, chip,
			{ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 14) })
		local value = text("Value", (Catalog.trail(l.trails[slot]) or { name = "None" }).name, if small then 14 else 16, F.SemiBold,
			INK, chip, { Position = UDim2.fromOffset(12, 20), Size = UDim2.new(1, -24, 0, chipH - 24) })
		local _ = value
		chip.Activated:Connect(function()
			if trailSlot ~= slot then
				trailSlot = slot
				buyId = nil
				Sfx.play("UIClick")
				buildStep(0)
			end
		end)
		R.slotChips[slot] = chip
	end
	local hint = text("Hint", "Trails are looks only. They never change a fight.", 12, F.Medium, INK2, chips,
		{ Size = UDim2.new(0, 320, 1, 0), LayoutOrder = 9 })
	hint.Visible = not small
	-- the trails for this slot
	local gridTop = chipH + gap
	local grid = make("ScrollingFrame", { Name = "Grid", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, gridTop),
		Size = UDim2.new(1, 0, 1, -gridTop), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = INK,
		ScrollBarImageTransparency = 0.6, Selectable = false }, body)
	padding(grid, 2, 8, 4, 4)
	local per = if small then 5 else 7
	local fits = {}
	for _, t in ipairs(Catalog.Trails) do
		if Catalog.trailFits(t.id, trailSlot) then
			table.insert(fits, t)
		end
	end
	local rows = math.ceil(#fits / per)
	local cw = math.floor((size.X - 10 - gap * (per - 1)) / per)
	local ch = math.max(if small then 96 else 100, math.floor((size.Y - gridTop - 10 - gap * (math.min(rows, 3) - 1)) / math.min(rows, 3)))
	make("UIGridLayout", { CellSize = UDim2.fromOffset(cw, ch), CellPadding = UDim2.fromOffset(gap, gap),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local owned = ownedTrails()
	for i, t in ipairs(fits) do
		local own = Catalog.isFreeTrail(t.id) or owned[t.id] == true
		local gradeName = Cards.gradeFromRarity(t.rarity)
		local grade = gradeName and Cards.grade(gradeName)
		local price = (Catalog.Prices and Catalog.Prices[t.rarity]) or t.price or 0
		local card = makeCard(grid, {
			name = t.id, order = i, size = UDim2.fromOffset(cw, ch), wellH = 0.56, locked = not own, gap = 1,
			picture = function(well)
				if t.id == "none" then
					icon("none", well, 26, { Tone = INK2 })
				else
					local _, api = Cards.trailPreview(well, t.colors, { Glow = t.glow, Width = 3 })
					table.insert(trailApis, api)
				end
			end,
			fill = function(b)
				text("Name", t.name, if small then 13 else 14, F.SemiBold, INK, b, { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1 })
				local state
				if own then
					state = text("State", if grade then string.upper(gradeName) .. "  ·  OWNED" else "FREE", 10, F.SemiBold,
						if grade then grade.label or grade.color else INK2, b, { Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 2 })
				else
					state = text("State", "\u{25CF} " .. comma(price), 12, F.Mono, if gold() >= price then SUN else INK2, b,
						{ Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 2 })
				end
				local _ = state
			end,
			hover = function()
				if own then
					chooseFeedback(t.name .. "  ·  " .. (if t.kind then t.kind else "") .. "  ·  owned")
				else
					chooseFeedback(t.name .. "  ·  " .. comma(price) .. " Gold")
				end
			end,
			onActivate = function()
				if own then
					choose("trail", t.id)
				else
					buyId = t.id
					Sfx.play("UIClick", { pitch = 0.95 })
					if R.showBuy then
						R.showBuy(t, price)
					end
				end
			end,
		})
		cards[t.id] = card
	end
	for id, card in pairs(cards) do
		setChosen(card, id == l.trails[trailSlot], true)
	end
end

local BUILDERS = { kitStep, skillsStep, trailStep }

--------------------------------------------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------------------------------------------

local function chosenWords(n: number): string
	local l = current()
	if n == 1 then
		return (Kits.get(l.kit) or Kits.default()).name
	elseif n == 2 then
		local s = Catalog.specialty(l.specialty)
		local g = Catalog.general(l.general)
		return string.format("%s · %s", if s then s.skill.name else "-", if g then g.name else "-")
	else
		local t = Catalog.trail(l.trails.swing)
		return if t then t.name else "None"
	end
end

refreshStrip = function()
	local strip = R.strip
	if not strip then
		return
	end
	for i = 1, #STEPS do
		local chip = strip:FindFirstChild("Step" .. i)
		if chip then
			local on = i == step
			local num = chip:FindFirstChild("Num") :: TextLabel
			local word = chip:FindFirstChild("Word") :: TextLabel
			local value = chip:FindFirstChild("Value") :: TextLabel
			local bar = chip:FindFirstChild("Bar") :: Frame
			if num then
				tween(num, FAST, { BackgroundColor3 = if on then SUN else CARD, TextColor3 = if on then SHADE else INK })
			end
			if word then
				tween(word, FAST, { TextColor3 = if on then INK else INK2 })
			end
			if value then
				value.Text = chosenWords(i)
				tween(value, FAST, { TextColor3 = if on then SUN else INK2 })
			end
			if bar then
				tween(bar, SOFT, { BackgroundTransparency = if on then 0 else 1, Size = if on then UDim2.new(1, 0, 0, 3) else UDim2.new(0.3, 0, 0, 3) })
			end
		end
	end
	if R.back then
		R.back.Visible = step > 1
	end
	if R.next then
		R.next.Visible = step < #STEPS
		local label = R.next:FindFirstChild("Label")
		if label then
			label.Text = "NEXT: " .. STEPS[math.min(step + 1, #STEPS)].word
		end
	end
	if R.stepLine then
		R.stepLine.Text = STEPS[step].line
	end
end

buildStep = function(dir: number?)
	local holder = R.body :: Frame?
	if not holder then
		return
	end
	for _, api in ipairs(trailApis) do
		pcall(api.stop)
	end
	table.clear(trailApis)
	if R.hideBuy then
		R.hideBuy()
	end
	local old = holder:FindFirstChild("Page")
	if old then
		old:Destroy()
	end
	-- (plain Frames, not CanvasGroups: a CanvasGroup draws its text soft) the page slides in under a veil that fades
	local page = make("Frame", { Name = "Page", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(if dir then 36 * dir else 0, 0) }, holder)
	local size = holder.AbsoluteSize / (if scaleObj then scaleObj.Scale else 1)
	if size.X < 10 then
		size = Vector2.new(1100, 420)
	end
	BUILDERS[step](page :: any, size)
	if dir and dir ~= 0 then
		local veil = frame("Veil", holder, { BackgroundTransparency = 0, BackgroundColor3 = PANEL,
			Size = UDim2.new(1, 24, 1, 24), Position = UDim2.fromOffset(-12, -12), ZIndex = 50 })
		tween(page, SOFT, { Position = UDim2.fromOffset(0, 0) })
		local t = tween(veil, SOFT, { BackgroundTransparency = 1 })
		t.Completed:Connect(function()
			veil:Destroy()
		end)
	end
	refreshStrip()
	defaultNote()
	-- a row that scrolls shows its chosen card
	task.defer(function()
		local cards = cardsByStep[step]
		if not cards then
			return
		end
		for _, c in pairs(cards) do
			local sf = c.Parent
			if c:GetAttribute("Chosen") == true and sf and sf:IsA("ScrollingFrame") then
				local s = if scaleObj then scaleObj.Scale else 1
				if sf.ScrollingDirection == Enum.ScrollingDirection.X then
					local x = (c.AbsolutePosition.X - sf.AbsolutePosition.X) / s + sf.CanvasPosition.X
					local want = math.max(0, x - (sf.AbsoluteSize.X / s - c.AbsoluteSize.X / s) / 2)
					sf.CanvasPosition = Vector2.new(want, 0)
				else
					local y = (c.AbsolutePosition.Y - sf.AbsolutePosition.Y) / s + sf.CanvasPosition.Y
					if y + c.AbsoluteSize.Y / s > sf.AbsoluteSize.Y / s then
						sf.CanvasPosition = Vector2.new(0, y - 8)
					end
				end
			end
		end
	end)
	-- the gamepad's focus goes to the chosen card of this step
	if Input.isGamepad() then
		task.defer(function()
			local cards = cardsByStep[step]
			if cards then
				for _, c in pairs(cards) do
					if c.Parent and c:GetAttribute("Chosen") == true and c:IsDescendantOf(page) then
						GuiService.SelectedObject = c
						return
					end
				end
			end
		end)
	end
end

function PrepareController.setStep(n: number)
	n = math.clamp(math.floor(n), 1, #STEPS)
	if n == step and R.body and R.body:FindFirstChild("Page") then
		return
	end
	local dir = if n > step then 1 else -1
	step = n
	Sfx.play("UIClick", { pitch = 1.15 })
	buildStep(dir)
end

local function bigButton(name: string, word: string, kind: string, w: number, h: number, parent: Instance, order: number): TextButton
	local b = make("TextButton", { Name = name, Text = "", AutoButtonColor = false, LayoutOrder = order,
		Size = UDim2.fromOffset(w, h), BackgroundColor3 = if kind == "sun" then SUN else CARD,
		BackgroundTransparency = if kind == "sun" then 0 elseif kind == "ghost" then 1 else 0.1 }, parent)
	corner(b, 8)
	if kind ~= "sun" then
		stroke(b, INK, if kind == "ghost" then 1 else 0.6, 1.5, "Edge")
	end
	if focusRing then
		b.SelectionImageObject = focusRing
	end
	local label = text("Label", word, if kind == "sun" then 18 else 14, F.SemiBold, if kind == "sun" then SHADE else INK, b,
		{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	local _ = label
	local sc = make("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		tween(sc, FAST, { Scale = 1.04 })
	end)
	b.MouseLeave:Connect(function()
		tween(sc, FAST, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		tween(sc, FAST, { Scale = 0.97 })
	end)
	b.MouseButton1Up:Connect(function()
		tween(sc, FAST, { Scale = 1 })
	end)
	return b
end

local ready: () -> ()
local closeScreen: (silent: boolean?) -> ()

local function buildPanel()
	local holder = R.layer :: Frame
	for _, c in ipairs(holder:GetChildren()) do
		if c.Name == "Panel" then
			c:Destroy()
		end
	end
	local size = rootSize()
	local small = compact()
	local edge = if small then 6 else 20
	local pw = math.min(size.X - edge * 2, 1240)
	local ph = math.min(size.Y - edge * 2, 700)
	local panel = make("Frame", { Name = "Panel", BackgroundColor3 = PANEL, BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(pw, ph) }, holder)
	corner(panel, 12)
	stroke(panel, INK, 0.88, 1, "Hair")
	R.panel = panel
	local px = if small then 12 else 28
	local headH = if small then 40 else 64
	local stripH = if small then 42 else 60
	local footH = if small then 52 else 76
	-- header: title + the step's one line | timer · gold · close
	local head = frame("Head", panel, { Position = UDim2.fromOffset(px, if small then 4 else 10), Size = UDim2.new(1, -px * 2, 0, headH) })
	text("Title", "Prepare", if small then 24 else 34, F.Light, INK, head, { Size = UDim2.new(0, if small then 110 else 160, 1, 0) })
	R.stepLine = text("Line", STEPS[step].line, if small then 12 else 14, F.Medium, INK2, head,
		{ Position = UDim2.fromOffset(if small then 116 else 172, 0), Size = UDim2.new(1, if small then -116 - 250 else -172 - 330, 1, 0) })
	local right = frame("Right", head, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 330, 1, 0) })
	local rl = list(right, Enum.FillDirection.Horizontal, if small then 8 else 14, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local _ = rl
	-- the timer pill
	local timer = frame("Timer", right, { BackgroundTransparency = 0.2, BackgroundColor3 = WELL, Size = UDim2.fromOffset(0, if small then 30 else 36),
		AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Visible = false })
	corner(timer, 18)
	padding(timer, 14, 14, 0, 0)
	list(timer, Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center)
	text("Word", "LOCKS IN", 11, F.SemiBold, INK2, timer, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 })
	R.timerValue = text("Value", "0:00", if small then 16 else 20, F.Mono, INK, timer, { Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	R.timer = timer
	-- gold
	local g = frame("Gold", right, { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	list(g, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
	local coin = frame("Coin", g, { Size = UDim2.fromOffset(18, 18), LayoutOrder = 1 })
	icon("coin", coin, 18)
	R.gold = text("Value", comma(gold()), 15, F.Mono, INK, g, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	-- close
	local x = make("TextButton", { Name = "Close", Text = "", AutoButtonColor = false, BackgroundTransparency = 0.6,
		BackgroundColor3 = CARD, Size = UDim2.fromOffset(44, 44), LayoutOrder = 3 }, right)
	corner(x, 22)
	if focusRing then
		x.SelectionImageObject = focusRing
	end
	icon("close", x, 18, { Tone = INK })
	x.Activated:Connect(function()
		closeScreen(false)
	end)
	-- the step strip
	local stripTop = (if small then 4 else 10) + headH + (if small then 2 else 6)
	local strip = frame("Steps", panel, { Position = UDim2.fromOffset(px, stripTop), Size = UDim2.new(1, -px * 2, 0, stripH) })
	make("Frame", { Name = "StepsRule", BackgroundColor3 = INK, BackgroundTransparency = 0.88,
		Position = UDim2.fromOffset(px, stripTop + stripH - 1), Size = UDim2.new(1, -px * 2, 0, 1) }, panel)
	local sl = list(strip, Enum.FillDirection.Horizontal, 0, Enum.HorizontalAlignment.Left)
	local _ = sl
	local chipW = math.floor((pw - px * 2) / 3)
	for i, s in ipairs(STEPS) do
		local chip = make("TextButton", { Name = "Step" .. i, Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
			Size = UDim2.new(0, chipW, 1, 0), LayoutOrder = i }, strip)
		if focusRing then
			chip.SelectionImageObject = focusRing
		end
		local num = text("Num", tostring(i), if small then 13 else 15, F.SemiBold, INK, chip, { BackgroundTransparency = 0,
			BackgroundColor3 = CARD, Size = UDim2.fromOffset(if small then 24 else 30, if small then 24 else 30),
			Position = UDim2.new(0, 0, 0.5, if small then -14 else -17), TextXAlignment = Enum.TextXAlignment.Center })
		corner(num, 15)
		local tx = if small then 32 else 42
		text("Word", s.word, if small then 13 else 15, F.SemiBold, INK2, chip, { Position = UDim2.new(0, tx, 0.5, if small then -16 else -20),
			Size = UDim2.new(1, -tx - 8, 0, if small then 16 else 18) })
		text("Value", "", if small then 11 else 13, F.Medium, INK2, chip, { Position = UDim2.new(0, tx, 0.5, if small then 0 else 0),
			Size = UDim2.new(1, -tx - 8, 0, if small then 14 else 18) })
		make("Frame", { Name = "Bar", BackgroundColor3 = SUN, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1), Size = UDim2.new(0.3, 0, 0, 3), ZIndex = 2 }, chip)
		chip.Activated:Connect(function()
			PrepareController.setStep(i)
		end)
	end
	R.strip = strip
	-- the body
	local bodyTop = stripTop + stripH + (if small then 8 else 18)
	local body = frame("Body", panel, { Position = UDim2.fromOffset(px, bodyTop),
		Size = UDim2.new(1, -px * 2, 1, -bodyTop - footH - (if small then 2 else 6)), ClipsDescendants = false })
	R.body = body
	-- the footer: the shared line (or the buy row) | MORE · BACK · NEXT · READY
	local foot = frame("Foot", panel, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, px, 1, if small then -6 else -14),
		Size = UDim2.new(1, -px * 2, 0, footH - (if small then 6 else 14)) })
	local bh = if touchy() then 48 else 46
	local buttons = frame("Buttons", foot, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0, 560, 1, 0) })
	list(buttons, Enum.FillDirection.Horizontal, if small then 8 else 12, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local more = bigButton("More", if small then "MORE" else "SAVED LOADOUTS & MORE", "ghost", if small then 70 else 210, bh, buttons, 1)
	more.Activated:Connect(function()
		local lc = Controllers.LoadoutController
		closeScreen(true)
		if lc and type(lc.openFull) == "function" then
			task.delay(0.05, lc.openFull)
		end
	end)
	R.back = bigButton("Back", "BACK", "secondary", if small then 70 else 96, bh, buttons, 2)
	R.back.Activated:Connect(function()
		PrepareController.setStep(step - 1)
	end)
	R.next = bigButton("Next", "NEXT", "secondary", if small then 112 else 150, bh, buttons, 3)
	R.next.Activated:Connect(function()
		PrepareController.setStep(step + 1)
	end)
	local go = bigButton("Ready", "READY", "sun", if small then 120 else 200, if small then bh else 56, buttons, 4)
	local tick = frame("Tick", go, { Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, if small then 12 else 26, 0.5, 0) })
	icon("tick", tick, 20, { Tone = SHADE })
	go.Activated:Connect(function()
		ready()
	end)
	R.ready = go
	R.note = text("Note", "", if small then 12 else 13, F.Medium, INK2, foot, { Size = UDim2.new(1, -(if small then 400 else 600), 1, 0),
		TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd })
	-- the buy row (a locked trail you tapped): it takes the note's place
	local buy = frame("Buy", foot, { Size = UDim2.new(1, -(if small then 400 else 600), 1, 0), Visible = false })
	list(buy, Enum.FillDirection.Horizontal, 10, nil, Enum.VerticalAlignment.Center)
	local buyWord = text("Word", "", 13, F.Medium, INK, buy, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 })
	local buyBtn = bigButton("BuyButton", "HOLD TO BUY", "secondary", 150, bh - 6, buy, 2)
	local unhold: (() -> ())? = nil
	R.showBuy = function(t: any, price: number)
		R.note.Visible = false
		buy.Visible = true
		if unhold then
			unhold()
			unhold = nil
		end
		if gold() >= price then
			buyWord.Text = string.format("%s  ·  \u{25CF} %s", t.name, comma(price))
			buyBtn.Visible = true
			unhold = Cards.hold(buyBtn, 0.6, function()
				local ok, remote = pcall(Net.event, "Trails")
				if ok and remote then
					remote:FireServer("buy", t.id, trailSlot)
				end
				buyWord.Text = "Buying " .. t.name .. "..."
				buyBtn.Visible = false
			end)
		else
			buyWord.Text = string.format("%s costs %s Gold. You have %s. Gold comes from rounds and the daily reward.",
				t.name, comma(price), comma(gold()))
			buyBtn.Visible = false
		end
	end
	R.hideBuy = function()
		if unhold then
			unhold()
			unhold = nil
		end
		buy.Visible = false
		if R.note then
			R.note.Visible = true
		end
	end
	buildStep(0)
end

--------------------------------------------------------------------------------------------------------------------
-- Open, close, ready
--------------------------------------------------------------------------------------------------------------------

local function bindPad()
	ContextActionService:BindActionAtPriority("PreparePad", function(_, state, io)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if io.KeyCode == Enum.KeyCode.ButtonB then
			closeScreen(false)
		elseif io.KeyCode == Enum.KeyCode.ButtonY then
			ready()
		elseif io.KeyCode == Enum.KeyCode.Q then
			PrepareController.setStep(step - 1)
		elseif io.KeyCode == Enum.KeyCode.E then
			PrepareController.setStep(step + 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 12, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonY,
		Enum.KeyCode.Q, Enum.KeyCode.E)
	-- Space must not jump behind the screen
	ContextActionService:BindActionAtPriority("PrepareSink", function()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 5, Enum.KeyCode.Space)
	unbindShoulders = Cards.bindShoulders("PrepareSteps", function()
		if isOpen then
			PrepareController.setStep(step - 1)
		end
	end, function()
		if isOpen then
			PrepareController.setStep(step + 1)
		end
	end)
end

local function unbindPad()
	ContextActionService:UnbindAction("PreparePad")
	ContextActionService:UnbindAction("PrepareSink")
	if unbindShoulders then
		unbindShoulders()
		unbindShoulders = nil
	end
end

local function canOpen(): boolean
	if isOpen or closing or not gui or not lobbyShowing() or lockedNow() then
		return false
	end
	if ClientState.menuOpen or ProgressUI.anyOpen() then
		return false
	end
	local lc = Controllers.LoadoutController
	if lc and type(lc.isOpen) == "function" and lc.isOpen() then
		return false
	end
	return true
end

function PrepareController.open(startStep: number?): boolean
	if not canOpen() then
		return false
	end
	isOpen = true
	autoKey = roundKey() -- (hunt2_1) opened once this pre-round, by hand or by itself: it does not open itself again
	pick = readServer()
	specTouched = pick.specialty ~= Catalog.suggestedSpecialty(pick.kit)
	step = math.clamp(startStep or 1, 1, #STEPS)
	buyId = nil
	ClientState.menuOpen = true
	applyScale()
	R.layer.Visible = true
	R.modal.Visible = true
	R.modal.Modal = true
	R.scrim.BackgroundTransparency = 1
	tween(R.scrim, SOFT, { BackgroundTransparency = 0.45 })
	Cards.dimWorld(true)
	buildPanel()
	local panel = R.panel :: Frame
	panel.Position = UDim2.new(0.5, 0, 0.5, 26)
	local psc = make("UIScale", { Name = "Pop", Scale = 0.97 }, panel)
	tween(psc, SOFT, { Scale = 1 })
	tween(panel, SOFT, { Position = UDim2.fromScale(0.5, 0.5) })
	local veil = frame("Veil", panel, { BackgroundTransparency = 0, BackgroundColor3 = PANEL, Size = UDim2.fromScale(1, 1), ZIndex = 60 })
	corner(veil, 12)
	local vt = tween(veil, SOFT, { BackgroundTransparency = 1 })
	vt.Completed:Connect(function()
		veil:Destroy()
	end)
	bindPad()
	Sfx.play("UIClick", { pitch = 1.1 })
	return true
end

closeScreen = function(silent: boolean?)
	if not isOpen then
		return
	end
	isOpen = false
	closing = true
	if sendQueued then
		queueSend(true)
	end
	unbindPad()
	if GuiService.SelectedObject and R.layer and GuiService.SelectedObject:IsDescendantOf(R.layer) then
		GuiService.SelectedObject = nil
	end
	R.modal.Modal = false
	R.modal.Visible = false
	Cards.dimWorld(false)
	tween(R.scrim, FAST, { BackgroundTransparency = 1 })
	local panel = R.panel :: Frame?
	R.body, R.strip, R.note, R.slotChips = nil, nil, nil, nil
	for _, api in ipairs(trailApis) do
		pcall(api.stop)
	end
	table.clear(trailApis)
	ClientState.menuOpen = false
	if not silent then
		Sfx.play("UIClick", { pitch = 0.9 })
	end
	local function done()
		closing = false
		if not isOpen and R.layer then
			R.layer.Visible = false
			if panel then
				panel:Destroy()
			end
			local backdrop = gui and gui:FindFirstChild("TestBackdrop")
			if backdrop then
				(backdrop :: Frame).Visible = false
			end
		end
		pick = nil
	end
	if panel then
		tween(panel, FAST, { Position = UDim2.new(0.5, 0, 0.5, 18) })
		local veil = frame("Veil", panel, { BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(4, 5, 7),
			Size = UDim2.fromScale(1, 1), ZIndex = 60 })
		corner(veil, 12)
		tween(veil, FAST, { BackgroundTransparency = 0 })
		task.delay(0.16, done)
	else
		done()
	end
	local lc = Controllers.LoadoutController
	if lc and type(lc.refresh) == "function" then
		task.defer(lc.refresh)
	end
end

function PrepareController.close()
	closeScreen(false)
end

function PrepareController.isOpen(): boolean
	return isOpen
end

ready = function()
	if not isOpen then
		return
	end
	readyKey = roundKey()
	-- what is chosen goes now, or as soon as the remote's limit allows (the screen can close meanwhile)
	local server = readServer()
	local p = payload()
	local differs = p.kit ~= server.kit or p.specialty ~= server.specialty or p.general ~= server.general
	for _, slot in ipairs(Catalog.Slots) do
		differs = differs or p.trails[slot] ~= server.trails[slot]
	end
	if differs or sendQueued then
		queueSend(true)
	end
	Sfx.play("UIClick", { pitch = 1.3 })
	closeScreen(true)
	if R.toast then
		-- (hunt2_1) the button under it already shows the kit and skills: the toast says what READY did
		R.toast.Text = "Saved  ·  you can change it until the call"
		R.toast.Visible = true
		R.toast.TextTransparency = 1
		tween(R.toast, SOFT, { TextTransparency = 0 })
		task.delay(2.6, function()
			if R.toast then
				tween(R.toast, SOFT, { TextTransparency = 1 })
			end
		end)
	end
end

-- Test hooks (Studio playtests; harmless live)
function PrepareController.debugChoose(row: string, id: string): boolean
	if not isOpen then
		return false
	end
	if row == "slot" then
		trailSlot = id
		buildStep(0)
		return true
	end
	choose(row, id)
	return true
end

--------------------------------------------------------------------------------------------------------------------
-- The PREPARE button (train and hall) and the timer
--------------------------------------------------------------------------------------------------------------------

local function buildButton(parent: Instance)
	local b = make("TextButton", { Name = "PrepareButton", Text = "", AutoButtonColor = false, BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.18, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(0, 56), AutomaticSize = Enum.AutomaticSize.X, Visible = false }, parent)
	corner(b, 28)
	local edge = stroke(b, SUN, 0.1, 2, "Edge")
	padding(b, 8, 18, 0, 0)
	list(b, Enum.FillDirection.Horizontal, 12, nil, Enum.VerticalAlignment.Center)
	local disc = frame("Pic", b, { BackgroundTransparency = 0.2, BackgroundColor3 = WELL, Size = UDim2.fromOffset(42, 42), LayoutOrder = 1 })
	corner(disc, 21)
	local words = frame("Words", b, { Size = UDim2.fromOffset(0, 42), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	list(words, Enum.FillDirection.Vertical, 0, nil, Enum.VerticalAlignment.Center)
	local title = text("Title", "PREPARE", 16, F.SemiBold, SUN, words, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 })
	local line = text("Line", "", 12, F.Medium, INK2, words, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	local key = text("Key", "L", 13, F.MonoMedium, INK, b, { Size = UDim2.fromOffset(26, 26), LayoutOrder = 3,
		TextXAlignment = Enum.TextXAlignment.Center })
	corner(key, 5)
	stroke(key, INK, 0.5, 1.2)
	local sc = make("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		tween(sc, FAST, { Scale = 1.04 })
	end)
	b.MouseLeave:Connect(function()
		tween(sc, FAST, { Scale = 1 })
	end)
	b.Activated:Connect(function()
		PrepareController.open(1)
	end)
	R.button = b
	R.buttonParts = { edge = edge, disc = disc, title = title, line = line, key = key }
	-- the toast after READY (just above the button)
	R.toast = text("ReadyToast", "", 14, F.Medium, INK, parent, { AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84), Size = UDim2.fromOffset(600, 20), TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeColor3 = SHADE, TextStrokeTransparency = 0.4, Visible = false })
end

local lastPic = ""
local pulseT = 0
local function refreshButton(dt: number)
	local b = R.button :: TextButton?
	if not b then
		return
	end
	local show = lobbyShowing() and not isOpen and not closing and not ClientState.menuOpen and not ProgressUI.anyOpen()
		and not lockedNow() and player:GetAttribute("LoadingScreenUp") ~= true
	local lc = Controllers.LoadoutController
	if show and lc and type(lc.isOpen) == "function" and lc.isOpen() then
		show = false
	end
	b.Visible = show
	if R.toast and not lobbyShowing() then
		R.toast.Visible = false
	end
	if not show then
		return
	end
	local p = R.buttonParts
	local l = readServer()
	local kit = Kits.get(l.kit) or Kits.default()
	if lastPic ~= kit.id then
		lastPic = kit.id
		for _, c in ipairs(p.disc:GetChildren()) do
			if not c:IsA("UICorner") then
				c:Destroy()
			end
		end
		icon(Icons.forKit(kit.id), p.disc, 36)
	end
	local s = Catalog.specialty(l.specialty)
	local g = Catalog.general(l.general)
	p.line.Text = string.format("%s  ·  %s  ·  %s", kit.name, if s then s.skill.name else "-", if g then g.name else "-")
	local touch = Input.isTouch()
	p.key.Visible = not touch
	p.key.Text = if Input.isGamepad() then "\u{25A3}" else "L"
	b.Position = UDim2.new(0.5, 0, 1, if touch then -96 else -18)
	if isReady() then
		p.title.Text = "READY  \u{2713}"
		p.title.TextColor3 = INK
		p.edge.Color = INK
		p.edge.Transparency = 0.75
	else
		p.title.Text = "PREPARE"
		p.title.TextColor3 = SUN
		p.edge.Color = SUN
		-- a slow breath on the amber edge until you are ready
		pulseT += dt
		p.edge.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(pulseT * 2.4))
	end
end

local function refreshTimer()
	if not isOpen or not R.timer then
		return
	end
	local at = deadline()
	if at then
		local left = at - workspace:GetServerTimeNow()
		R.timer.Visible = true
		R.timerValue.Text = clock(left)
		R.timerValue.TextColor3 = if left <= 10 then SUN else INK
	else
		R.timer.Visible = false
	end
	if R.gold then
		R.gold.Text = comma(gold())
	end
end

-- opens by itself once per pre-round, soon after you arrive at the Training Centre
local function autoOpen()
	local key = roundKey()
	if player:GetAttribute("AtTrainingCentre") ~= true then
		arrivedAt = nil
		return
	end
	if autoKey == key or isReady() then
		return
	end
	-- the multiplayer test's switch (MPTest Driver, as for DailyAutoOpen): bots never close menus
	if workspace:GetAttribute("PrepareAutoOpen") == false then
		return
	end
	arrivedAt = arrivedAt or os.clock()
	if os.clock() - arrivedAt < 1.6 then
		return
	end
	local at = deadline()
	if at and at - workspace:GetServerTimeNow() < 12 then
		autoKey = key -- too late to be useful
		return
	end
	if player:GetAttribute("InRedRoom") == true or player:GetAttribute("LoadingScreenUp") == true then
		return
	end
	if canOpen() and PrepareController.open(1) then
		autoKey = key
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function PrepareController.Init(controllers)
	Controllers = controllers
end

function PrepareController.Start()
	local pg = player:WaitForChild("PlayerGui")
	local g = make("ScreenGui", { Name = "Prepare", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, nil)
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	local rt = frame("Root", g, { Size = UDim2.fromScale(1, 1) })
	scaleObj = make("UIScale", { Name = "Scale" }, rt)
	root = rt
	gui = g
	focusRing = Cards.focusRing()
	-- the ring is amber here (the chosen colour); the halo stays soft
	local ring = focusRing:FindFirstChild("Ring")
	local rs = ring and ring:FindFirstChildOfClass("UIStroke")
	if rs then
		rs.Color = SUN
	end
	-- the full-screen layer while open: scrim + a modal button (frees the mouse) + the panel
	local layer = frame("Layer", rt, { Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 2 })
	R.layer = layer
	R.scrim = frame("Scrim", layer, { Size = UDim2.new(1, 400, 1, 400), Position = UDim2.fromOffset(-200, -200),
		BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(4, 5, 7) })
	R.modal = make("TextButton", { Name = "Modal", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		Visible = false, Selectable = false, AutoButtonColor = false }, layer)
	buildButton(rt)
	g.Parent = pg
	applyScale()
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyScale()
		if isOpen then
			task.defer(buildPanel)
		end
	end)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("PrepareTestPhone"):Connect(function()
			applyScale()
			if isOpen then
				task.defer(buildPanel)
			end
		end)
	end
	-- (hunt1_1) the Settings menu (M) opened over this screen: its panel has no fill of its own, so the two read as one
	-- jumble. This screen steps aside (the choices are already sent) and the Settings menu keeps the mouse.
	task.spawn(function()
		local menu = pg:WaitForChild("Menu", 30)
		local mroot = menu and menu:WaitForChild("Root", 10)
		local mpanel = mroot and mroot:WaitForChild("Panel", 10)
		if not (mpanel and mpanel:IsA("GuiObject")) then
			return
		end
		mpanel:GetPropertyChangedSignal("Visible"):Connect(function()
			if mpanel.Visible and isOpen then
				closeScreen(true)
				ClientState.menuOpen = true
			end
		end)
	end)
	-- a trail bought here goes on at once
	task.spawn(function()
		local ok, remote = pcall(Net.event, "Trails")
		if ok and remote then
			remote.OnClientEvent:Connect(function(kind, a)
				if kind == "bought" and type(a) == "string" and isOpen and pick then
					local t = Catalog.trail(a)
					task.wait(0.2)
					if isOpen and t and Catalog.trailFits(a, trailSlot) then
						buyId = nil
						buildStep(0)
						choose("trail", a)
						setNote("Bought " .. t.name .. ". It is on your " .. SLOT_WORDS[trailSlot] .. " trail.", true)
					end
				end
			end)
		end
	end)
	-- the server holds the choice: when the kit changes from outside (a mat in the hall) while open, follow it
	player:GetAttributeChangedSignal("Kit"):Connect(function()
		if isOpen and pick and not sendQueued and os.clock() - lastSend > 3 then
			local k = player:GetAttribute("Kit")
			if Kits.get(k) and k ~= pick.kit then
				choose("kit", k)
			end
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		refreshButton(dt)
		if acc < 0.2 then
			return
		end
		acc = 0
		if isOpen and (not lobbyShowing() or lockedNow()) then
			closeScreen(true)
		end
		refreshTimer()
		autoOpen()
	end)
	Input.deviceChanged:Connect(function()
		if isOpen then
			defaultNote()
		end
	end)
end

return PrepareController
