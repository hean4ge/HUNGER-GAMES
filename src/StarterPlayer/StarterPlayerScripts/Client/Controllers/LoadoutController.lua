--[[
	LoadoutController - the one place to choose what you take into the next round (docs/design/Combat_v3.md section 3.2),
	rebuilt as cards (docs/design/CardMenusAndShop.md 2.1 and 2.2; the owner, 20 Nov: "instead of text chunks like we
	have rn the skills and whatnot can look like a similar ui to this"). Built from Shared.Cards ("Quiet cards").

	IN THE TRAIN
	  The summary line (bottom centre on a PC, under the status lines on touch), Ink at 72%:
	    Forager · Twin-Bit Axe ★★★★ · Axe: Whirl · Second Wind     [L] Loadout
	  Click or tap it, press L (gamepad: D-pad right), or walk up to the Loadout rack at the front of the Lounge car
	  (workspace.Lobby.LoadoutStation, ProximityPrompt "Loadout": E / X / tap) to open the screen. Never in the arena.

	THE LOADOUT SCREEN (2.1, the owner's "saved loadouts" reference)
	  The camera eases (0.4 s) to a three-quarter view of your own avatar (left). On the right, the SAVED LOADOUT CARDS:
	  each card is a name ("1 Horn runner"), two big tiles (the kit, and the weapon you bring as a live 3D view with its
	  stars) and five small tiles (weapon skill, general skill, the Swing, Arrow and Throw trails), with EDIT beside it.
	  Tapping a card makes it the loadout you take (SELECTED in Sun). Slots: 2 at start, slot 3 at Level 10 (Runner),
	  slot 4 at Level 20 (Scout) (player attribute Level, RankService); a locked card shows its rule.
	  During the call to launch the cards dim to 50% and "LOCKED · launching" shows in Sun (trails can still change).
	THE EDIT PANEL (2.2): tabs Kit · Bring · Skills · Trails · Look; CANCEL / SAVE; Gold top right.
	  Kit     five tall cards: the kit's picture, name, one line, its items as small live 3D tiles, "Suggests: Bow"
	  Bring   the Armoury's weapons as live 3D tiles with stars, "Kit weapon", and locked tiles for the rest
	          ("Armoury 800 or a Strongbox"); INSPECT (gamepad X) opens the weapon inspect screen (InspectController)
	  Skills  two rows of picker cards: Weapon skill (seven, the family under the name) and General skill (six); icon,
	          name, a two-line effect, the cooldown
	  Trails  the SWING · ARROW · THROW slot cards, then every trail for that slot as a card with a moving preview,
	          grade and OWNED / EQUIPPED / price; the detail card on the right with BUY · HOLD (0.6 s, Gold, TrailService)
	  Look    your weapons (tap: inspect, with its Skin, Kill effect and Kill icon slots)
	  Gamepad: LB / RB tabs, A choose, X inspect or edit, B back. Touch: every target 44 px or more.

	ONE SAVE
	  The selected loadout is what the server holds: choosing a card, or SAVE on the selected one, sends one LoadoutSet
	  { kit, bring, specialty, general, trails = { swing, arrow, throw }, slot, saved } (KitService checks every value;
	  `slot` and `saved` are for when KitService keeps the saved list: until then the other cards live for the session,
	  and slot 1 always starts as what the server holds). Closing the screen sends the selected one if it changed.
	  Saved list read from the player attribute LoadoutSaved (JSON, when the server publishes it).

	Reads: player attributes Kit, KitBring, KitArmoury (KitService), LoadoutSpecialty, LoadoutGeneral (KitService),
	TrailSwing / TrailArrow / TrailThrow, TrailsOwned (TrailService), Gold, Level, LoadoutSaved; GameState Phase.
]]
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Catalog = require(Shared:WaitForChild("LoadoutCatalog"))
local Icons = require(Shared:WaitForChild("Icons"))
local Input = require(Shared:WaitForChild("Input"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Kits = require(Shared:WaitForChild("Kits"))
local Net = require(Shared:WaitForChild("Net"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Stars = require(Shared:WaitForChild("Stars"))
local Theme = require(Shared:WaitForChild("Theme"))
local Trails = require(Shared:WaitForChild("Trails"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local GameState = ReplicatedStorage:WaitForChild("GameState")
local C = Theme.Colors
local F = Theme.Fonts

local LoadoutController = {}

local REST = 0.28 -- Ink at 72%
local BUY_HOLD = 0.6
local EASE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAX_SLOTS = 4
local SLOT_LEVEL = { 1, 1, 10, 20 } -- slot 3 at Level 10 (Runner), slot 4 at Level 20 (Scout)
local SLOT_RANK = { "", "", "Runner", "Scout" }
local TABS = { { key = "kit", text = "Kit" }, { key = "bring", text = "Bring" }, { key = "skills", text = "Skills" },
	{ key = "trails", text = "Trails" }, { key = "look", text = "Look" } }
local SLOT_LINES = { swing = "Your melee swings and skills", arrow = "Both bows", throw = "Every thrown weapon" }

local Controllers: { [string]: any } = {}
local gui: ScreenGui? = nil
local R: { [string]: any } = {}
local isOpen = false
local draft: any = nil -- the selected loadout while the screen is open
local saved: any = nil -- what the server holds (last sent / read)
local presets: { any } = {} -- the saved loadout cards (session, or LoadoutSaved)
local activeSlot = 1
local editing: number? = nil -- the card being edited
local editDraft: any = nil
local tab = "kit"
local trailSlot = "swing"
local trailPick: string? = nil -- the trail shown in the detail card
local trailMode = false -- the Trails tab is showing (the avatar's trail loop plays then)
local focusRow: string? = nil
local compact = false
local previewFolder: Folder? = nil
local held: Model? = nil
local trayModels: { Instance } = {}
local cameraTween: Tween? = nil
local savedCameraType: Enum.CameraType? = nil
local trailToken = 0
local trailsRemote: RemoteEvent? = nil
local lastSentAt = 0
local unbindShoulders: (() -> ())? = nil

local comma = Cards.comma

local function lobbyShowing(): boolean
	-- (Studio only: the LocalPlayer attribute CardsTestForce lets a playtest show the screens anywhere, for pictures)
	if RunService:IsStudio() and player:GetAttribute("CardsTestForce") == true then
		return true
	end
	return not ClientState.inArena and ClientState.spectating == nil
end

local function locked(): boolean
	return GameState:GetAttribute("Phase") == "Countdown"
end

local function level(): number
	return tonumber(player:GetAttribute("Level")) or 1
end

local function slotOpen(i: number): boolean
	return level() >= (SLOT_LEVEL[i] or 999)
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
	return { name = l.name, kit = l.kit, bring = l.bring, specialty = l.specialty, general = l.general,
		trails = { swing = l.trails.swing, arrow = l.trails.arrow, throw = l.trails.throw } }
end

-- what the preview on the avatar shows: the card being edited, else the selected one
local function current()
	return editDraft or draft or saved or readSaved()
end

local function bringStars(id: string): number?
	for _, e in ipairs(armoury()) do
		if e.id == id then
			return e.stars
		end
	end
	return nil
end

local function kitWeapon(kitId: string): string?
	local kit = Kits.get(kitId) or Kits.default()
	for _, item in ipairs(kit.items) do
		local def = ItemDefs.get(item.id)
		if def and def.starred then
			return item.id
		end
	end
	return nil
end

-- the weapon a loadout takes: the brought one at its stars, else the kit's own at 1 star (Medic: none)
local function weaponOf(l: any): (string?, number)
	local s = l.bring ~= "" and bringStars(l.bring)
	if s then
		return l.bring, s
	end
	return kitWeapon(l.kit), 1
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

local function defaultName(i: number, l: any): string
	local kit = Kits.get(l.kit)
	return if kit then kit.name else ("Loadout " .. i)
end

-- The saved cards: from LoadoutSaved when the server publishes it; else the session's list, whose selected card
-- always follows what the server holds
local function loadPresets()
	local raw = player:GetAttribute("LoadoutSaved")
	if type(raw) == "string" and raw ~= "" then
		local ok, list = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(list) == "table" then
			local out = {}
			for i = 1, MAX_SLOTS do
				local src = list[i]
				if type(src) == "table" then
					local clean = Catalog.sanitize(src, ownsTrail, src.kit)
					table.insert(out, { name = if type(src.name) == "string" then string.sub(src.name, 1, 20) else nil,
						kit = (Kits.get(src.kit) or Kits.default()).id, bring = if type(src.bring) == "string" then src.bring else "",
						specialty = clean.specialty, general = clean.general, trails = clean.trails })
				end
			end
			if #out > 0 then
				presets = out
				local sel = tonumber(player:GetAttribute("LoadoutSlot"))
				activeSlot = if sel and presets[sel] then sel else 1
			end
		end
	end
	local live = readSaved()
	if #presets == 0 then
		live.name = nil
		presets[1] = live
		-- a second card to start from: the Archer, bow skill, Steady Hands
		local alt = { kit = "archer", bring = "", specialty = Catalog.suggestedSpecialty("archer"), general = "steady_hands",
			trails = table.clone(live.trails) }
		if not Catalog.general("steady_hands") then
			alt.general = live.general
		end
		presets[2] = alt
		activeSlot = 1
	else
		-- the selected card is what the server holds
		local keepName = presets[activeSlot] and presets[activeSlot].name
		presets[activeSlot] = live
		live.name = keepName
	end
	for i, p in ipairs(presets) do
		p.name = p.name or defaultName(i, p)
	end
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
-- One save
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
	local list = {}
	for i, p in ipairs(presets) do
		list[i] = { name = p.name, kit = p.kit, bring = p.bring, specialty = p.specialty, general = p.general,
			trails = { swing = p.trails.swing, arrow = p.trails.arrow, throw = p.trails.throw } }
	end
	return { kit = l.kit, bring = l.bring, specialty = l.specialty, general = l.general, trails = trails,
		slot = activeSlot, saved = list }
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
		pcall(function()
			Net.event("KitPick"):FireServer(payload.kit)
			Net.event("KitPick"):FireServer("bring", payload.bring)
		end)
	end
	saved = copy(payload)
	flashSaved()
end

-- At most one LoadoutSet a second while the screen is open (KitService allows 2 in 4 s)
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

-- (integrate, 20 Nov; design 2.1) the train's summary line shows the loadout as five small pictures - the kit, the
-- weapon you bring (live 3D), the weapon skill, the general skill and the swing trail - and only the kit's name in words
local summaryKey = ""
local function refreshSummary()
	local l = draft or saved or readSaved()
	if R.summaryText then
		local kit = Kits.get(l.kit) or Kits.default()
		R.summaryText.Text = kit.name
		R.summaryText:SetAttribute("Full", summaryText(l))
	end
	local holder = R.summaryIcons
	if not holder then
		return
	end
	local swing = (l.trails and l.trails.swing) or player:GetAttribute("TrailSwing") or ""
	local key = table.concat({ tostring(l.kit), tostring(l.bring), tostring(l.specialty), tostring(l.general), tostring(swing) }, "|")
	if key == summaryKey then
		return
	end
	summaryKey = key
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local size = UDim2.fromOffset(30, 30)
	local function add(order: number, def: { [string]: any })
		def.Size = size
		def.NoName = true
		def.Selectable = false
		def.LayoutOrder = order
		def.Turn = "none"
		local t = Cards.tile(def)
		t.Active = false
		t.Parent = holder
	end
	add(1, { Name = "Kit", Icon = Icons.forKit(l.kit) })
	local stars = l.bring ~= "" and bringStars(l.bring)
	if stars then
		add(2, { Name = "Bring", Item = l.bring, ItemStars = stars })
	end
	local spec = Catalog.specialty(l.specialty)
	add(3, { Name = "WeaponSkill", Icon = Icons.forSkill(if spec then l.specialty else nil) })
	add(4, { Name = "GeneralSkill", Icon = Icons.forSkill(l.general) })
	local trail = Trails.get(swing)
	add(5, { Name = "Trail", Icon = "swing", Grade = if trail then Cards.gradeFromRarity(trail.rarity) else nil })
end

local function layTrayAndHold()
	refreshPreview()
end

--------------------------------------------------------------------------------------------------------------------
-- The card screens
--------------------------------------------------------------------------------------------------------------------

local M: any = Cards.metrics()

local function isCompact(): boolean
	local camera = workspace.CurrentCamera
	local v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	-- (LocalPlayer attribute LoadoutTouchLayout = true shows the phone layout on a PC: a Studio check)
	return Theme.isSmallScreen(v) or v.Y < 560 or player:GetAttribute("LoadoutTouchLayout") == true
end

local function metrics()
	compact = isCompact()
	M = if compact then Cards.metrics(Vector2.new(812, 375)) else Cards.metrics()
	return M
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

local function listLayout(parent: Instance, dir: Enum.FillDirection, gap: number, align: Enum.VerticalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	l.VerticalAlignment = align or Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

local function goldRow(parent: Instance, props: { [string]: any }): Frame
	local row = plainFrame("Gold", parent)
	row.Size = UDim2.fromOffset(160, 28)
	for k, v in pairs(props) do
		(row :: any)[k] = v
	end
	local l = listLayout(row, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Center)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	Icons.make("coin", { Size = UDim2.fromOffset(16, 16), LayoutOrder = 1, Parent = row })
	local n = Cards.label(comma(tonumber(player:GetAttribute("Gold")) or 0), { Name = "Amount", Font = F.Mono, TextSize = if compact then 17 else 20,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.None })
	n.Parent = row
	return row
end

local function trailGrade(t: any): string?
	return if t then Cards.gradeFromRarity(t.rarity) else nil
end

local function trailTile(id: string, size: UDim2, order: number): TextButton
	local t = Catalog.trail(id) or Catalog.trail("draught")
	return Cards.tile({
		Name = "Trail_" .. tostring(id), Size = size, NoName = true, Selectable = false, LayoutOrder = order,
		Grade = trailGrade(t), Label = "",
		Picture = function(holder)
			if t and t.id ~= "none" then
				Cards.trailPreview(holder, t.colors, { Still = true, Width = 3, Glow = t.glow })
			else
				Icons.make("none", { Size = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = holder })
			end
		end,
	})
end

--------------------------------------------------------------------------------------------------------------------
-- The Loadout screen: saved loadout cards
--------------------------------------------------------------------------------------------------------------------

local selectSlot: (number) -> ()
local openEdit: (number) -> ()
local closeEdit: (boolean) -> ()
local buildTab: () -> ()
local close: () -> ()
local open: () -> ()

local function inspect(id: string?, stars: number?)
	local inspector = Controllers.InspectController
	if id and inspector and type(inspector.open) == "function" then
		Sfx.play("UIClick")
		inspector.open(id, stars, { from = "Loadout" })
	end
end

local function loadoutCard(i: number, size: Vector2, bigH: number, smallPx: number): TextButton
	local p = presets[i]
	local open_ = slotOpen(i) and p ~= nil
	local card = Cards.surface({ Name = "Loadout" .. i, Size = UDim2.fromOffset(size.X, size.Y),
		OnActivate = function()
			selectSlot(i)
		end })
	card:SetAttribute("PresetIndex", i)
	local name = Cards.label(if open_ then string.format("%d  %s", i, p.name) else string.format("%d  Locked", i),
		{ Name = "Title", Font = "SemiBold", TextSize = 15, Color = if open_ then C.Ink else C.Ink2,
			Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20) })
	name.Parent = card
	local pad = 10
	local rowW = size.X - pad * 2
	local kitW = math.floor(rowW * 0.38)
	local y1 = 30
	local y2 = y1 + bigH + 8
	if open_ then
		local kit = Kits.get(p.kit) or Kits.default()
		local kitTile = Cards.tile({ Name = "Kit", Size = UDim2.fromOffset(kitW, bigH), Position = UDim2.fromOffset(pad, y1),
			Icon = Icons.forKit(kit.id), Title = kit.name, Selectable = false, Label = "" })
		kitTile.Parent = card
		local wid, wstars = weaponOf(p)
		local wdef = wid and ItemDefs.get(wid)
		local weaponTile = Cards.tile({ Name = "Weapon", Size = UDim2.fromOffset(rowW - kitW - 8, bigH),
			Position = UDim2.fromOffset(pad + kitW + 8, y1), Item = wid, ItemStars = wstars, Wide = true,
			Title = if wdef then wdef.name else "No weapon", Stars = if wdef then wstars else nil, Selectable = false, Label = "",
			Icon = if wid then nil else "none" })
		weaponTile.Parent = card
		local smalls = plainFrame("Small", card)
		smalls.Position = UDim2.fromOffset(pad, y2)
		smalls.Size = UDim2.new(1, -pad * 2, 0, smallPx)
		local sl = listLayout(smalls, Enum.FillDirection.Horizontal, 0)
		sl.HorizontalAlignment = Enum.HorizontalAlignment.Left
		sl.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
		local spec = Catalog.specialty(p.specialty)
		Cards.tile({ Name = "Specialty", Size = UDim2.fromOffset(smallPx, smallPx), NoName = true, Selectable = false, LayoutOrder = 1,
			Icon = Icons.forSkill(p.specialty), Label = "" }).Parent = smalls
		Cards.tile({ Name = "General", Size = UDim2.fromOffset(smallPx, smallPx), NoName = true, Selectable = false, LayoutOrder = 2,
			Icon = Icons.forSkill(p.general), Label = "" }).Parent = smalls
		for k, slot in ipairs(Catalog.Slots) do
			trailTile(p.trails[slot], UDim2.fromOffset(smallPx, smallPx), 2 + k).Parent = smalls
		end
		local _ = spec
		if i == activeSlot then
			Cards.setState(card, "Selected", true)
		end
		if locked() then
			Cards.setState(card, "Disabled", true)
		end
	else
		for k = 1, 2 do
			local w = if k == 1 then kitW else rowW - kitW - 8
			local t = Cards.tile({ Name = "Locked" .. k, Size = UDim2.fromOffset(w, bigH), Position = UDim2.fromOffset(if k == 1 then pad else pad + kitW + 8, y1),
				NoName = true, Selectable = false, Label = "" })
			Cards.setState(t, "Locked", true)
			t.Parent = card
		end
		local smalls = plainFrame("Small", card)
		smalls.Position = UDim2.fromOffset(pad, y2)
		smalls.Size = UDim2.new(1, -pad * 2, 0, smallPx)
		local sl = listLayout(smalls, Enum.FillDirection.Horizontal, 0)
		sl.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
		for k = 1, 5 do
			local t = Cards.tile({ Name = "L" .. k, Size = UDim2.fromOffset(smallPx, smallPx), NoName = true, Selectable = false, LayoutOrder = k, Label = "" })
			Cards.setState(t, "Locked", true)
			t.Parent = smalls
		end
		Cards.setState(card, "Disabled", true)
		card.Selectable = false
	end
	return card
end

local function buildMain(screen: Frame)
	if R.main then
		R.main:Destroy()
	end
	local main = plainFrame("Main", screen)
	main.Size = UDim2.fromScale(1, 1)
	R.main = main
	local cardW = if compact then 300 else 372
	local bigH = if compact then 54 else 78
	local smallPx = if compact then 48 else 62
	local cardH = 30 + bigH + 8 + smallPx + 10
	local editW = if compact then 84 else 132
	local gap = if compact then 8 else 14

	-- title (top left, over the avatar's side)
	local title = Cards.label("Loadout", { Name = "Title", Font = "Light", TextSize = if compact then 26 else 40,
		Size = UDim2.fromOffset(300, if compact then 32 else 48) })
	title.Parent = main
	if not compact then
		local sub = Cards.label("Pick a saved loadout, or EDIT one. Locks at the call to launch.",
			{ Name = "Sub", TextSize = 15, Color = C.Ink2, Position = UDim2.fromOffset(2, 50), Size = UDim2.fromOffset(520, 22) })
		sub.Parent = main
	end
	local lockLine = Cards.label("LOCKED  \u{00B7}  launching", { Name = "Locked", Font = "SemiBold", TextSize = 14, Color = C.Sun,
		Position = UDim2.fromOffset(2, if compact then 34 else 76), Size = UDim2.fromOffset(300, 20), Visible = locked() })
	lockLine.Parent = main
	R.lockMain = lockLine

	local colW = cardW + gap + editW
	local footH = if compact then 0 else 52
	local topH = if compact then 0 else 56
	local column = Instance.new("ScrollingFrame")
	column.Name = "Cards"
	column.BackgroundTransparency = 1
	column.BorderSizePixel = 0
	column.ScrollBarThickness = 3
	column.ScrollBarImageColor3 = C.Ink
	column.ScrollBarImageTransparency = 0.7
	column.ScrollingDirection = Enum.ScrollingDirection.Y
	column.AutomaticCanvasSize = Enum.AutomaticSize.Y
	column.CanvasSize = UDim2.new()
	column.Selectable = false
	column.AnchorPoint = Vector2.new(1, 0)
	column.Position = UDim2.new(1, 0, 0, topH)
	column.Size = UDim2.new(0, colW + 10, 1, -(topH + footH + (if compact then 0 else 8)))
	column.Parent = main
	local cl = listLayout(column, Enum.FillDirection.Vertical, if compact then 8 else 12)
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local cpad = Instance.new("UIPadding")
	cpad.PaddingTop, cpad.PaddingLeft, cpad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 6)
	cpad.Parent = column
	R.cards = {}
	for i = 1, MAX_SLOTS do
		local row = plainFrame("Row" .. i, column)
		row.Size = UDim2.fromOffset(colW, cardH)
		row.LayoutOrder = i
		local card = loadoutCard(i, Vector2.new(cardW, cardH), bigH, smallPx)
		card.Parent = row
		R.cards[i] = card
		local side = plainFrame("Side", row)
		side.Position = UDim2.fromOffset(cardW + gap, 0)
		side.Size = UDim2.new(0, editW, 1, 0)
		local sll = listLayout(side, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Center)
		sll.HorizontalAlignment = Enum.HorizontalAlignment.Left
		if slotOpen(i) and presets[i] then
			local edit = Cards.button(if i == activeSlot then "Primary" else "Secondary", "Edit", { Name = "Edit", LayoutOrder = 1,
				Size = UDim2.fromOffset(editW - (if compact then 0 else 20), math.max(40, M.touch)), AutomaticSize = Enum.AutomaticSize.None })
			edit.Activated:Connect(function()
				openEdit(i)
			end)
			edit.Parent = side
			if i == activeSlot then
				local selected = Cards.label("SELECTED", { Name = "Selected", Font = "SemiBold", TextSize = 13, Color = C.Sun,
					Size = UDim2.fromOffset(editW, 18), LayoutOrder = 2 })
				selected.Parent = side
			end
		else
			local rule = Cards.label(string.format("Opens at <b>Level %d</b>  \u{00B7}  %s", SLOT_LEVEL[i], SLOT_RANK[i]),
				{ Name = "Rule", TextSize = 13, Color = C.Ink2, Size = UDim2.fromOffset(editW, 54), TextWrapped = true, RichText = true,
					TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 1 })
			rule.Parent = side
		end
	end

	-- top right: Gold (and on a phone, DONE beside it)
	local top = plainFrame("Top", main)
	top.AnchorPoint = Vector2.new(1, 0)
	top.Position = UDim2.fromScale(1, 0)
	top.Size = UDim2.fromOffset(if compact then 0 else 300, 44)
	if compact then
		-- a phone: Gold and DONE sit at the top of the left side, under the title (the right is the cards)
		top.AnchorPoint = Vector2.new(0, 1)
		top.Position = UDim2.new(0, 0, 1, 0)
		top.Size = UDim2.fromOffset(260, 44)
	end
	local tl = listLayout(top, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Center)
	tl.HorizontalAlignment = if compact then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right
	-- (Gold shows in the train's own Gold line, top right: not repeated here)
	if compact then
		local done = Cards.button("Primary", "Done", { Name = "Done", LayoutOrder = 1 })
		done.Activated:Connect(function()
			close()
		end)
		done.Parent = top
		R.done = done
	else
		local foot = plainFrame("Foot", main)
		foot.AnchorPoint = Vector2.new(1, 1)
		foot.Position = UDim2.fromScale(1, 1)
		foot.Size = UDim2.new(1, 0, 0, 48)
		local fl = listLayout(foot, Enum.FillDirection.Horizontal, 18, Enum.VerticalAlignment.Center)
		fl.HorizontalAlignment = Enum.HorizontalAlignment.Right
		local hints = if Input.isGamepad() then { { key = "B", text = "close" }, { key = "A", text = "pick" }, { key = "X", text = "edit" } }
			else { { key = "L", text = "close" }, { key = "Click", text = "pick" } }
		Cards.hints(hints, { LayoutOrder = 1, Parent = foot })
		local done = Cards.button("Primary", "Done", { Name = "Done", LayoutOrder = 2 })
		done.Activated:Connect(function()
			close()
		end)
		done.Parent = foot
		R.done = done
		local note = Cards.label("Your avatar at the Loadout rack", { Name = "AvatarNote", TextSize = 13, Color = C.Ink2,
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(320, 40) })
		note.Parent = main
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The Edit panel
--------------------------------------------------------------------------------------------------------------------

local function setNote(text: string)
	if R.note then
		R.note.Text = text
	end
end

local function editLocked(): boolean
	return locked()
end

local function markChosen(cards: { [string]: GuiObject }, key: string?)
	for k, c in pairs(cards) do
		Cards.setState(c, "Chosen", if k == key then "CHOSEN" else false)
		Cards.setState(c, "Selected", k == key)
	end
end

local function sectionGrid(parent: Instance, order: number, cell: Vector2): Frame
	local f = plainFrame("Grid" .. order, parent)
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	g.CellPadding = UDim2.fromOffset(M.gap, M.gap)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = f
	return f
end

local function scrollBody(body: Frame): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = "Scroll"
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 3
	s.ScrollBarImageColor3 = C.Ink
	s.ScrollBarImageTransparency = 0.7
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.Selectable = false
	s.Size = UDim2.fromScale(1, 1)
	s.Parent = body
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingTop, pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = s
	listLayout(s, Enum.FillDirection.Vertical, if compact then 8 else 12)
	return s
end

local function capital(s: string): string
	return (string.gsub(s, "^%l", string.upper))
end

local function kitTab(body: Frame)
	local s = scrollBody(body)
	Cards.section("Kit", { Tail = "what your midpoint parcel holds", LayoutOrder = 1, Parent = s })
	local cell = if compact then Vector2.new(150, 236) else Vector2.new(218, 318)
	local grid = sectionGrid(s, 2, cell)
	local cards = {}
	local itemPx = if compact then 34 else 48
	for i, kit in ipairs(Kits.List) do
		local family = Catalog.suggestedSpecialty(kit.id)
		local spec = Catalog.specialty(family)
		local card = Cards.card({
			Name = "Kit_" .. kit.id, LayoutOrder = i, Icon = Icons.forKit(kit.id), Big = true, WellHeight = 0.36,
			Title = kit.name, Text = capital(kit.forWhom), NameSize = if compact then 16 else 19,
			Footer = if kit.id == "medic" then "No suggestion" else ("Suggests: " .. (spec and spec.name or family)),
			Row = function(row)
				local l = listLayout(row, Enum.FillDirection.Horizontal, 6, Enum.VerticalAlignment.Center)
				local _ = l
				for k, item in ipairs(kit.items) do
					Cards.tile({ Name = "Item" .. k, Size = UDim2.fromOffset(itemPx, itemPx), Item = item.id, NoName = true,
						Selectable = false, LayoutOrder = k, Count = if item.count > 1 then ("\u{00D7}" .. item.count) else nil, Label = "",
						Turn = "none" }).Parent = row
				end
			end,
			Hover = function(on)
				if on then
					setNote(kit.name .. ":  " .. Kits.summary(kit))
				end
			end,
			OnActivate = function()
				if editLocked() or not editDraft then
					return
				end
				local before = editDraft.kit
				editDraft.kit = kit.id
				if editDraft.specialty == Catalog.suggestedSpecialty(before) then
					editDraft.specialty = Catalog.suggestedSpecialty(kit.id)
				end
				Sfx.play("UIClick")
				markChosen(cards, kit.id)
				setNote(kit.name .. ":  " .. Kits.summary(kit))
				task.spawn(function()
					layTrayAndHold()
				end)
			end,
		})
		if editLocked() then
			Cards.setState(card, "Disabled", true)
		end
		card.Parent = grid
		cards[kit.id] = card
	end
	markChosen(cards, editDraft and editDraft.kit)
	setNote("The weapon you BRING replaces the kit's weapon (Medic: it is added). Hover or touch a kit for its parcel.")
end

local function bringTab(body: Frame)
	local s = scrollBody(body)
	Cards.section("Bring", { Tail = "an Armoury weapon in place of the kit's own", LayoutOrder = 1, Parent = s })
	local cell = if compact then Vector2.new(176, 82) else Vector2.new(236, 104)
	local grid = sectionGrid(s, 2, cell)
	local cards = {}
	local owned = {}
	for _, e in ipairs(armoury()) do
		owned[e.id] = e.stars
	end
	local function lineFor(id: string, st: number): string
		local d = Stars.def(id, st)
		if not d then
			return ""
		end
		if d.kind == "Bow" then
			return string.format("%s  %s  \u{00B7}  %g to %g damage, draw %.2f s", d.name, Stars.text(st), d.damageMin, d.damageMax, d.drawTime)
		end
		return string.format("%s  %s  \u{00B7}  %g damage, every %.2f s, reach %.1f", d.name, Stars.text(st), d.damage, d.cooldown, d.range)
	end
	local function chooseFocus(id: string?, st: number?)
		R.inspectId, R.inspectStars = id, st
		if R.inspectButton then
			R.inspectButton.Visible = id ~= nil
		end
	end
	-- the kit's own weapon
	local kw = kitWeapon(editDraft.kit)
	local kitCard = Cards.tile({ Name = "Bring_kit", LayoutOrder = 0, Size = UDim2.fromOffset(cell.X, cell.Y), Wide = true,
		Item = kw, ItemStars = 1, Icon = if kw then nil else Icons.forKit(editDraft.kit), Title = "Kit weapon", Stars = if kw then 1 else nil,
		Label = "FROM THE KIT",
		Hover = function(on)
			if on then
				setNote(if kw then lineFor(kw, 1) .. "  \u{00B7}  the kit's own" else "The Medic kit has no weapon")
				chooseFocus(kw, 1)
			end
		end,
		OnActivate = function()
			if editLocked() then
				return
			end
			editDraft.bring = ""
			Sfx.play("UIClick")
			markChosen(cards, "")
			task.spawn(layTrayAndHold)
		end })
	kitCard.Parent = grid
	cards[""] = kitCard
	for i, id in ipairs(Rewards.Pool) do
		local def = ItemDefs.get(id)
		if def then
			local st = owned[id]
			local tile = Cards.tile({ Name = "Bring_" .. id, LayoutOrder = i, Size = UDim2.fromOffset(cell.X, cell.Y), Wide = true,
				Item = id, ItemStars = st or 3, Title = def.name, Stars = st, Label = if st then Stars.finish(st) else "",
				Hover = function(on)
					if on then
						setNote(if st then lineFor(id, st) else (def.name .. "  \u{00B7}  not in your Armoury: buy it at 3\u{2605} for "
							.. comma(Rewards.config().Armoury.Buy3) .. " Gold, or win it in a Strongbox"))
						chooseFocus(id, st or 3)
					end
				end,
				OnActivate = function()
					if not st then
						inspect(id, 3)
						return
					end
					if editLocked() then
						return
					end
					editDraft.bring = id
					Sfx.play("UIClick")
					markChosen(cards, id)
					task.spawn(layTrayAndHold)
				end })
			if not st then
				Cards.setState(tile, "Locked", "Armoury " .. comma(Rewards.config().Armoury.Buy3) .. " or a Strongbox")
			elseif editLocked() then
				Cards.setState(tile, "Disabled", true)
			end
			tile.Parent = grid
			cards[id] = tile
		end
	end
	markChosen(cards, editDraft.bring)
	setNote("Choose the weapon you bring. INSPECT shows it turning, its stars, traits, skin and kill effect.")
	chooseFocus(weaponOf(editDraft))
end

local function skillsTab(body: Frame)
	local s = scrollBody(body)
	local cell = if compact then Vector2.new(150, 204) else Vector2.new(172, 230)
	Cards.section("Weapon skill  \u{00B7}  your specialty", { Tail = "works on R while you hold a weapon of that family", LayoutOrder = 1, Parent = s })
	local g1 = sectionGrid(s, 2, cell)
	local specCards, genCards = {}, {}
	for i, spec in ipairs(Catalog.Specialties) do
		local sk = spec.skill
		local card = Cards.card({ Name = "Spec_" .. spec.id, LayoutOrder = i, Icon = Icons.forSkill(spec.id), WellHeight = 0.38,
			Title = sk.name, Sub = string.upper(spec.name), Text = sk.line, Fact = string.format("%d s", sk.cooldown or 0), FactIcon = "cooldown",
			NameSize = if compact then 15 else 17,
			Hover = function(on)
				if on then
					setNote(string.format("%s  \u{00B7}  %s skill  \u{00B7}  %s  \u{00B7}  %d s", sk.name, spec.name, sk.line, sk.cooldown or 0))
				end
			end,
			OnActivate = function()
				if editLocked() then
					return
				end
				editDraft.specialty = spec.id
				Sfx.play("UIClick")
				markChosen(specCards, spec.id)
			end })
		if editLocked() then
			Cards.setState(card, "Disabled", true)
		end
		card.Parent = g1
		specCards[spec.id] = card
	end
	Cards.section("General skill", { Tail = "works with anything, on F", LayoutOrder = 3, Parent = s })
	local g2 = sectionGrid(s, 4, cell)
	for i, g in ipairs(Catalog.General) do
		local card = Cards.card({ Name = "Gen_" .. g.id, LayoutOrder = i, Icon = Icons.forSkill(g.id), WellHeight = 0.38,
			Title = g.name, Text = g.line, Fact = string.format("%d s", g.cooldown or 0), FactIcon = "cooldown",
			NameSize = if compact then 15 else 17,
			Hover = function(on)
				if on then
					setNote(string.format("%s  \u{00B7}  %s  \u{00B7}  %d s", g.name, g.line, g.cooldown or 0))
				end
			end,
			OnActivate = function()
				if editLocked() then
					return
				end
				editDraft.general = g.id
				Sfx.play("UIClick")
				markChosen(genCards, g.id)
			end })
		if editLocked() then
			Cards.setState(card, "Disabled", true)
		end
		card.Parent = g2
		genCards[g.id] = card
	end
	markChosen(specCards, editDraft.specialty)
	markChosen(genCards, editDraft.general)
	setNote(if editLocked() then "Skills are locked for this launch." else "One weapon skill and one general skill. Hover or touch a card for its line.")
end

local buyTrail: (string) -> ()

local function trailsTab(body: Frame)
	local slotH = if compact then 50 else 64
	local detailW = if compact then 196 else 300
	-- the three slots
	local slots = plainFrame("Slots", body)
	slots.Size = UDim2.new(1, 0, 0, slotH)
	listLayout(slots, Enum.FillDirection.Horizontal, M.gap, Enum.VerticalAlignment.Center)
	local slotCards = {}
	for k, slot in ipairs(Catalog.Slots) do
		local t = Catalog.trail(editDraft.trails[slot])
		local sc = Cards.surface({ Name = "Slot_" .. slot, Size = UDim2.fromOffset(if compact then 118 else 210, slotH), LayoutOrder = k,
			OnActivate = function()
				trailSlot = slot
				trailPick = editDraft.trails[slot]
				Sfx.play("UIClick")
				buildTab()
			end })
		Cards.label(Catalog.SlotNames[slot], { Font = "SemiBold", TextSize = 12, Color = C.Ink2, Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -20, 0, 16), Parent = sc })
		Cards.label(t and t.name or "None", { Name = "Title", Font = "SemiBold", TextSize = if compact then 15 else 17, Position = UDim2.fromOffset(12, 22),
			Size = UDim2.new(1, -20, 0, if compact then 22 else 30), Parent = sc })
		Cards.setState(sc, "Selected", slot == trailSlot)
		sc.Parent = slots
		slotCards[slot] = sc
	end
	if not compact then
		Cards.label("Choose a slot, then a trail.\nChanging trails is free, any time in the train.", { TextSize = 13, Color = C.Ink2,
			Size = UDim2.fromOffset(320, slotH), LayoutOrder = 9, TextWrapped = true, Parent = slots })
	end
	-- the trail cards
	local area = plainFrame("Area", body)
	area.Position = UDim2.fromOffset(0, slotH + M.gap)
	area.Size = UDim2.new(1, 0, 1, -(slotH + M.gap))
	local cell = if compact then Vector2.new(132, 158) else Vector2.new(166, 150)
	local grid = Cards.grid({ Cell = cell, Size = UDim2.new(1, -(detailW + M.gap), 1, 0), Parent = area })
	local owned = ownedTrails()
	local cards = {}
	trailPick = trailPick or editDraft.trails[trailSlot]
	local detail: any = nil
	local function paintCards()
		for id, c in pairs(cards) do
			Cards.setState(c, "Equipped", if id == editDraft.trails[trailSlot] then "EQUIPPED" else false)
			Cards.setState(c, "Selected", id == trailPick)
		end
	end
	local order = 0
	for _, t in ipairs(Catalog.Trails) do
		if t.slots[trailSlot] then
			order += 1
			local mine = Catalog.isFreeTrail(t.id) or owned[t.id] == true
			local grade = trailGrade(t)
			local card = Cards.card({ Name = "Trail_" .. t.id, LayoutOrder = order, WellHeight = if compact then 0.44 else 0.56, Grade = grade,
				Title = t.name, NameSize = if compact then 14 else 16,
				Sub = if t.id == "none" then "NO TRAIL" elseif not grade then "NO GRADE" else nil,
				Fact = if mine then "OWNED" elseif t.earned then "SEASON" else comma(t.price),
				FactIcon = if mine or t.earned then nil else "coin",
				Picture = function(holder)
					if t.id ~= "none" then
						Cards.trailPreview(holder, t.colors, { Glow = t.glow, Width = if compact then 3 else 4 })
					else
						Icons.make("none", { Size = UDim2.fromScale(0.4, 0.4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = holder })
					end
				end,
				OnActivate = function()
					trailPick = t.id
					if mine then
						editDraft.trails[trailSlot] = t.id
						local sc = slotCards[trailSlot]
						local title = sc and sc:FindFirstChild("Title")
						if title then
							title.Text = t.name
						end
					end
					Sfx.play("UIClick")
					paintCards()
					if detail then
						detail(t.id)
					end
					focusRow = "trail"
					task.spawn(playTrail)
				end })
			if not mine and t.earned then
				Cards.setState(card, "Locked", "Season Track")
			end
			card.Parent = grid
			cards[t.id] = card
		end
	end
	-- the detail card (right)
	local d = Cards.surface({ Name = "Detail", Selectable = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, detailW, 1, -4), Parent = area })
	local well = Cards.well(d, { Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, if compact then 70 else 150) })
	local _, preview = Cards.trailPreview(well, { C.Ink, C.Ink2 }, { Glow = false, Width = if compact then 4 else 6, Period = 1.4 })
	local y = (if compact then 70 else 150) + 18
	local name = Cards.label("", { Name = "Name", Font = "SemiBold", TextSize = if compact then 17 else 24,
		Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, if compact then 22 else 30), Parent = d })
	local facts = Cards.label("", { Name = "Facts", Font = "SemiBold", TextSize = 12, Position = UDim2.fromOffset(12, y + (if compact then 22 else 32)),
		Size = UDim2.new(1, -24, 0, 16), Parent = d })
	local line = Cards.label("", { Name = "Line", TextSize = if compact then 13 else 15, Color = C.Ink2, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(12, y + (if compact then 40 else 54)),
		Size = UDim2.new(1, -24, 0, if compact then 34 else 66), Parent = d })
	local action = plainFrame("Action", d)
	action.AnchorPoint = Vector2.new(0, 1)
	action.Position = UDim2.new(0, 10, 1, -10)
	action.Size = UDim2.new(1, -20, 0, if compact then 46 else 74)
	detail = function(id: string)
		local t = Catalog.trail(id)
		if not t then
			return
		end
		local grade = trailGrade(t)
		local gdef = Cards.grade(grade)
		preview.setColors(t.colors, t.glow)
		name.Text = t.name
		local slotsList = {}
		for _, sname in ipairs(Catalog.Slots) do
			if t.slots[sname] then
				table.insert(slotsList, string.upper(sname))
			end
		end
		facts.Text = string.format("%s  \u{00B7}  %s  \u{00B7}  %s", if gdef then string.upper(gdef.name) else "NO GRADE", string.upper(t.kind or ""),
			table.concat(slotsList, ", "))
		facts.TextColor3 = if gdef then (gdef.label or gdef.color) else C.Ink2
		line.Text = t.line or (if t.id == "none" then "No trail at all." else (SLOT_LINES[trailSlot] .. "."))
		action:ClearAllChildren()
		local mine = Catalog.isFreeTrail(t.id) or ownedTrails()[t.id] == true
		local b
		if mine then
			local on = editDraft.trails[trailSlot] == t.id
			b = Cards.button(if on then "Off" else "Primary", if on then "Equipped" else "Equip", { Name = "Equip",
				Size = UDim2.new(1, 0, 0, 44), AutomaticSize = Enum.AutomaticSize.None, Parent = action })
			b.Activated:Connect(function()
				editDraft.trails[trailSlot] = t.id
				Sfx.play("UIClick")
				buildTab()
			end)
		elseif t.earned then
			-- earned on the Season Track, never sold: no price button (integrate, 20 Nov)
			b = Cards.button("Off", t.earned, { Name = "Earned", Size = UDim2.new(1, 0, 0, 44),
				AutomaticSize = Enum.AutomaticSize.None, Parent = action })
		else
			b = Cards.button("Price", if compact then "Buy" else "Buy \u{00B7} hold", { Name = "Buy", Price = t.price,
				Size = UDim2.new(1, 0, 0, 44), AutomaticSize = Enum.AutomaticSize.None, Parent = action })
			Cards.hold(b, BUY_HOLD, function()
				buyTrail(t.id)
			end)
			if not compact then
				Cards.label("Hold 0.6 s to buy. Yours for every slot it fits.", { TextSize = 13, Color = C.Ink2,
					AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 22), Parent = action })
			end
		end
		b.Position = UDim2.fromOffset(0, 0)
		R.trailAction = b
	end
	detail(trailPick)
	paintCards()
	trailMode = true
	focusRow = "trail"
	setNote("Previews loop on each card; your avatar plays the chosen trail when the panel closes.")
end

local function lookTab(body: Frame)
	local s = scrollBody(body)
	Cards.section("Your weapons", { Tail = "choose one for its skin, kill effect and kill icon", LayoutOrder = 1, Parent = s })
	local cell = if compact then Vector2.new(176, 82) else Vector2.new(236, 104)
	local grid = sectionGrid(s, 2, cell)
	local list = armoury()
	local kw = kitWeapon(editDraft.kit)
	if #list == 0 and kw then
		table.insert(list, { id = kw, stars = 1 })
	end
	for i, e in ipairs(list) do
		local def = ItemDefs.get(e.id)
		Cards.tile({ Name = "Look_" .. e.id, LayoutOrder = i, Size = UDim2.fromOffset(cell.X, cell.Y), Wide = true, Item = e.id,
			ItemStars = e.stars, Title = def and def.name or e.id, Stars = e.stars, Label = Stars.finish(e.stars),
			OnActivate = function()
				inspect(e.id, e.stars)
			end }).Parent = grid
	end
	-- the account-wide slots ("use on all weapons" looks)
	Cards.section("Every weapon", { Tail = "kill effect and kill icon set with Y on the inspect screen", LayoutOrder = 3, Parent = s })
	local row = plainFrame("Slots", s)
	row.LayoutOrder = 4
	row.Size = UDim2.new(1, 0, 0, M.tile + 24)
	listLayout(row, Enum.FillDirection.Horizontal, M.gap, Enum.VerticalAlignment.Top)
	local okLooks, CL = pcall(function()
		return require(Shared:FindFirstChild("CosmeticLooks") :: ModuleScript)
	end)
	local looks = if okLooks and CL then CL.of(player) else nil
	for k, slot in ipairs({ { "e", "kill_effect", "Kill effect" }, { "i", "kill_icon", "Kill icon" }, { "b", "banner", "Banner" } }) do
		local id = looks and (if slot[1] == "b" then looks.b else (looks[slot[1]] and looks[slot[1]]["*"]))
		local item = id and okLooks and CL.get(id)
		local holder = plainFrame("S" .. k, row)
		holder.Size = UDim2.fromOffset(M.tile + 40, M.tile + 24)
		holder.LayoutOrder = k
		Cards.slot({ Size = UDim2.fromOffset(M.tile, M.tile), Empty = item == nil, Icon = slot[2], Grade = item and item.grade,
			NoName = true, Selectable = false, Parent = holder })
		Cards.label(slot[3] .. (if item then (" \u{00B7} " .. item.name) else " \u{00B7} none"), { TextSize = 13, Color = C.Ink2,
			Position = UDim2.fromOffset(0, M.tile + 4), Size = UDim2.new(1, 40, 0, 18), Parent = holder })
	end
	setNote("Skins, kill effects and kill icons come from CASES and the Season Track. They never change damage or reach.")
end

local TAB_BUILDERS = { kit = kitTab, bring = bringTab, skills = skillsTab, trails = trailsTab, look = lookTab }

buildTab = function()
	local body = R.body
	if not body or not editDraft then
		return
	end
	local focusName = GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(body) and GuiService.SelectedObject.Name
	body:ClearAllChildren()
	trailMode = false
	focusRow = nil
	R.inspectId = nil
	if R.inspectButton then
		R.inspectButton.Visible = false
	end
	TAB_BUILDERS[tab](body)
	if R.tabsApi then
		R.tabsApi.select(tab, true)
	end
	if R.lockEdit then
		R.lockEdit.Visible = locked()
	end
	if Input.isGamepad() then
		task.defer(function()
			local want = focusName and body:FindFirstChild(focusName, true)
			if not (want and want:IsA("GuiObject") and want.Selectable) then
				want = nil
				for _, d in ipairs(body:GetDescendants()) do
					if d:IsA("GuiButton") and d.Selectable and d.Visible then
						want = d
						break
					end
				end
			end
			if want then
				GuiService.SelectedObject = want
			end
		end)
	end
end

local function buildEdit(screen: Frame, index: number)
	if R.edit then
		R.edit:Destroy()
	end
	local p = presets[index]
	local panel = Cards.panel({ Name = "Edit", Size = UDim2.fromScale(1, 1), Parent = screen })
	R.edit = panel
	local pad = Instance.new("UIPadding")
	local px = if compact then 10 else 28
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, px), UDim.new(0, px), UDim.new(0, if compact then 6 else 18), UDim.new(0, if compact then 6 else 16)
	pad.Parent = panel
	local headH = if compact then 44 else 60
	local footH = if compact then 46 else 52
	local head = plainFrame("Head", panel)
	head.Size = UDim2.new(1, 0, 0, headH)
	local hl = listLayout(head, Enum.FillDirection.Horizontal, if compact then 10 else 36, Enum.VerticalAlignment.Center)
	local _ = hl
	Cards.label(if compact then "Edit" else ("Edit \u{00B7} " .. p.name), { Name = "Title", Font = if compact then "SemiBold" else "Light",
		TextSize = if compact then 18 else 36, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, headH), LayoutOrder = 1,
		TextTruncate = Enum.TextTruncate.None, Parent = head })
	local tabs, api = Cards.tabs(TABS, { LayoutOrder = 2, Start = tab, Parent = head })
	local _t = tabs
	R.tabsApi = api
	api.onChanged(function(key)
		tab = key
		Sfx.play("UIClick")
		buildTab()
		if R.body then
			QuietUI.swap(R.body) -- (ui-motion) tabs cross-fade (Motion.Tab)
		end
	end)
	goldRow(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(140, headH) })

	local body = plainFrame("Body", panel)
	body.Position = UDim2.fromOffset(0, headH + (if compact then 4 else 14))
	body.Size = UDim2.new(1, 0, 1, -(headH + footH + (if compact then 8 else 24)))
	body.ClipsDescendants = true
	R.body = body

	local foot = plainFrame("Foot", panel)
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.fromScale(0, 1)
	foot.Size = UDim2.new(1, 0, 0, footH)
	local note = Cards.label("", { Name = "Note", TextSize = 13, Color = C.Ink2, Size = UDim2.new(1, if compact then -300 else -560, 1, 0),
		TextWrapped = true, Parent = foot })
	R.note = note
	local lockEdit = Cards.label("LOCKED  \u{00B7}  launching  (trails can still change)", { Name = "Locked", Font = "SemiBold", TextSize = 13,
		Color = C.Sun, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 0, -2), Size = UDim2.fromOffset(420, 18), Visible = locked(), Parent = foot })
	R.lockEdit = lockEdit
	local right = plainFrame("Buttons", foot)
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.Size = UDim2.new(0, if compact then 300 else 560, 1, 0)
	local rl = listLayout(right, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Center)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	if not compact then
		Cards.hints(if Input.isGamepad() then { { key = "LB", text = "" }, { key = "RB", text = "tabs" }, { key = "A", text = "choose" }, { key = "X", text = "inspect" } }
			else { { key = "L", text = "close" } }, { LayoutOrder = 0, Parent = right })
	end
	local inspectButton = Cards.button("Secondary", "Inspect", { Name = "Inspect", LayoutOrder = 1, Visible = false, Parent = right })
	inspectButton.Activated:Connect(function()
		inspect(R.inspectId, R.inspectStars)
	end)
	R.inspectButton = inspectButton
	local cancel = Cards.button("Secondary", "Cancel", { Name = "Cancel", LayoutOrder = 2, Parent = right })
	cancel.Activated:Connect(function()
		closeEdit(false)
	end)
	local save = Cards.button("Primary", "Save", { Name = "Save", LayoutOrder = 3, Parent = right })
	save.Activated:Connect(function()
		closeEdit(true)
	end)
	buildTab()
end

--------------------------------------------------------------------------------------------------------------------
-- Choosing, editing, buying
--------------------------------------------------------------------------------------------------------------------

local function screenFrame(): Frame?
	return R.screen
end

local function focusCard(i: number)
	if Input.isGamepad() and R.cards and R.cards[i] then
		GuiService.SelectedObject = R.cards[i]
	end
end

selectSlot = function(i: number)
	if not isOpen or not presets[i] or not slotOpen(i) then
		return
	end
	if locked() then
		return
	end
	Sfx.play("UIClick")
	activeSlot = i
	draft = copy(presets[i])
	refreshSummary()
	buildMain(R.screen)
	focusCard(i)
	refreshPreview()
	-- the slot changes what the server holds: sent at once if the loadout differs, else soon (it keeps the slot)
	if saved and changed(draft, saved) then
		send(false)
	else
		scheduleSend()
	end
end

openEdit = function(i: number)
	if not isOpen or not presets[i] then
		return
	end
	Sfx.play("UIClick")
	editing = i
	editDraft = copy(presets[i])
	tab = if locked() then "trails" else (if tab == "" then "kit" else tab)
	trailPick = nil
	if R.main then
		R.main.Visible = false
	end
	buildEdit(R.screen, i)
	if R.edit then
		QuietUI.swap(R.edit) -- (ui-motion) the Edit panel cross-fades in
	end
	if unbindShoulders then
		unbindShoulders()
	end
	unbindShoulders = Cards.bindShoulders("LoadoutTabs", function()
		if R.tabsApi then
			R.tabsApi.step(-1)
		end
	end, function()
		if R.tabsApi then
			R.tabsApi.step(1)
		end
	end)
	refreshPreview()
end

closeEdit = function(save: boolean)
	if not editing then
		return
	end
	local i = editing
	if save and editDraft then
		local keepName = presets[i].name
		presets[i] = copy(editDraft)
		presets[i].name = keepName
		if i == activeSlot then
			draft = copy(presets[i])
			send(false)
		end
		Sfx.play("UIClick", { pitch = 0.9 })
	else
		Sfx.play("UIClick", { pitch = 1.1 })
	end
	editing = nil
	editDraft = nil
	trailMode = false
	focusRow = nil
	if unbindShoulders then
		unbindShoulders()
		unbindShoulders = nil
	end
	if R.edit then
		R.edit:Destroy()
		R.edit = nil
	end
	R.body, R.note, R.tabsApi, R.inspectButton = nil, nil, nil, nil
	buildMain(R.screen)
	if R.main then
		QuietUI.swap(R.main) -- (ui-motion) back to the cards: a cross-fade
	end
	refreshSummary()
	refreshPreview()
	focusCard(i)
end

buyTrail = function(id: string)
	local t = Catalog.trail(id)
	if trailsRemote then
		trailsRemote:FireServer("buy", id, trailSlot)
		setNote("Buying " .. (t and t.name or id) .. " ...")
	else
		setNote("The trail shop is not open yet")
	end
end

local function onBought(id: string)
	if not isOpen then
		return
	end
	local t = Catalog.trail(id)
	local target = editDraft or draft
	if target and t and t.slots[trailSlot] then
		target.trails[trailSlot] = id
	end
	Sfx.play("UIClick", { pitch = 0.8 })
	trailPick = id
	if editing and tab == "trails" then
		buildTab()
	end
	setNote((t and t.name or id) .. " is yours")
	playTrail()
end

-- Repaint after something changed under the screen (Gold, the Armoury, the trails owned, the lock)
local function repaint()
	if not isOpen then
		return
	end
	if editing then
		buildTab()
		local gold = R.edit and R.edit:FindFirstChild("Gold")
		local amount = gold and gold:FindFirstChild("Amount")
		if amount then
			amount.Text = comma(tonumber(player:GetAttribute("Gold")) or 0)
		end
	else
		buildMain(R.screen)
		focusCard(activeSlot)
	end
end

local function sink()
	return Enum.ContextActionResult.Sink
end

local function inspectorOpen(): boolean
	local inspector = Controllers.InspectController
	return inspector ~= nil and type(inspector.isOpen) == "function" and inspector.isOpen() == true
end

-- B: back out of the Edit panel, else close. X: EDIT the focused card, or INSPECT the focused weapon.
local function onPadAction(name: string, state: Enum.UserInputState, io: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or inspectorOpen() then
		return Enum.ContextActionResult.Pass
	end
	if io.KeyCode == Enum.KeyCode.ButtonB or io.KeyCode == Enum.KeyCode.Escape then
		if editing then
			closeEdit(false)
		elseif io.KeyCode == Enum.KeyCode.ButtonB then
			close()
		else
			return Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Sink
	end
	if io.KeyCode == Enum.KeyCode.ButtonX then
		local sel = GuiService.SelectedObject
		if not editing then
			local node: Instance? = sel
			while node and node ~= R.screen do
				local index = node:GetAttribute("PresetIndex")
				if type(index) == "number" then
					openEdit(index)
					return Enum.ContextActionResult.Sink
				end
				node = node.Parent
			end
		elseif R.inspectId then
			inspect(R.inspectId, R.inspectStars)
		elseif sel and string.sub(sel.Name, 1, 5) == "Look_" then
			inspect(string.sub(sel.Name, 6), nil)
		end
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

-- The Loadout key (Input action "Loadout": L, View, D-pad right), bound only in the train lobby. L opens and closes
-- the screen wherever the lobby shows. In the train D-pad right only opens it, and is let go while the screen, a menu
-- or any GUI selection is up (a controller moves through those with the D-pad). In the Training Centre's hall D-pad
-- right is SkillGeneral, so there the controller's View (Create) button opens and closes it instead.
local boundKeys = "" -- what is bound now: "", "L", "L+Pad" or "L+View"
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

local autoSelectBefore: boolean? = nil -- GuiService.AutoSelectGuiEnabled as it was before the hall took View
local function syncKeys()
	local want = ""
	if lobbyShowing() and gui then
		-- in the Training Centre's hall D-pad right is the general skill (SkillController binds it there, skills are
		-- tried in the hall): there the Loadout has L and View. Roblox's own use of View (it puts a controller's
		-- selection on the screen's buttons, GuiService.AutoSelectGuiEnabled) is off while in the hall, or it takes
		-- the press first (wave 16, in play); in the train it stays, and D-pad right opens the Loadout.
		local inHall = player:GetAttribute("InTraining") == true
		want = if inHall then "L+View"
			elseif isOpen or ClientState.menuOpen or GuiService.SelectedObject ~= nil then "L" else "L+Pad"
	end
	if want == boundKeys then
		return
	end
	boundKeys = want
	if want == "L+View" then
		if autoSelectBefore == nil then
			autoSelectBefore = GuiService.AutoSelectGuiEnabled
		end
		GuiService.AutoSelectGuiEnabled = false
	elseif autoSelectBefore ~= nil then
		GuiService.AutoSelectGuiEnabled = autoSelectBefore
		autoSelectBefore = nil
	end
	if want == "" then
		Input.unbind("Loadout")
		return
	end
	local spec = Input.ACTIONS and Input.ACTIONS.Loadout
	local keys = if spec and spec.keys then table.clone(spec.keys) else { Enum.KeyCode.L, Enum.KeyCode.ButtonSelect, Enum.KeyCode.DPadRight }
	local function drop(key: Enum.KeyCode)
		local index = table.find(keys, key)
		if index then
			table.remove(keys, index)
		end
	end
	if want ~= "L+View" then
		drop(Enum.KeyCode.ButtonSelect)
	end
	if want ~= "L+Pad" then
		drop(Enum.KeyCode.DPadRight)
	end
	Input.bind("Loadout", onLoadoutKey, { keys = keys })
end

open = function()
	if isOpen or not lobbyShowing() or ClientState.menuOpen or not gui then
		return
	end
	isOpen = true
	metrics()
	saved = readSaved()
	loadPresets()
	draft = copy(presets[activeSlot])
	editing, editDraft = nil, nil
	focusRow, trailMode = nil, false
	ClientState.menuOpen = true
	R.screen.Visible = true
	R.summary.Visible = false
	if R.near then
		R.near.Visible = false
	end
	buildMain(R.screen)
	if R.main then
		-- (ui-motion) the cards fade and rise in (Motion.In, 12 px)
		QuietUI.reveal(R.main, { rise = QuietUI.Motion.Rise })
	end
	takeBody(true)
	takeCamera(true)
	task.delay(0.15, refreshPreview)
	loopTrail()
	local s = station()
	local prompt = s and s:FindFirstChild("Loadout", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
	-- B backs out or closes (and must not also crouch); X edits or inspects; the thumbsticks stay with the selection
	ContextActionService:BindActionAtPriority("LoadoutPad", onPadAction, false, Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonX)
	ContextActionService:BindActionAtPriority("LoadoutSink", sink, false, Enum.ContextActionPriority.High.Value + 5,
		Enum.KeyCode.Space, Enum.KeyCode.ButtonY)
	focusCard(activeSlot)
	Sfx.play("UIClick", { pitch = 1.1 })
	task.defer(syncKeys)
end

close = function()
	if not isOpen then
		return
	end
	local inspector = Controllers.InspectController
	if inspector and type(inspector.close) == "function" and inspectorOpen() then
		inspector.close()
	end
	if editing then
		closeEdit(false)
	end
	send(false)
	isOpen = false
	ContextActionService:UnbindAction("LoadoutPad")
	ContextActionService:UnbindAction("LoadoutSink")
	if unbindShoulders then
		unbindShoulders()
		unbindShoulders = nil
	end
	if GuiService.SelectedObject and R.screen and GuiService.SelectedObject:IsDescendantOf(R.screen) then
		GuiService.SelectedObject = nil
	end
	clearPreview()
	takeCamera(false)
	takeBody(false)
	-- (ui-motion) the cards fade and sink out (Motion.Out); the screen hides when they are gone, unless it opened again
	local leaving = R.main
	R.main = nil
	if leaving then
		leaving.Name = "MainLeaving"
		QuietUI.conceal(leaving, { rise = QuietUI.Motion.Rise }, function()
			leaving:Destroy()
			if not isOpen and R.screen then
				R.screen.Visible = false
			end
		end)
	else
		R.screen.Visible = false
	end
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

-- Test hooks (Studio playtests drive the screen with these; harmless in a live game)
-- debugChoose(row, key): row "kit" | "bring" | "specialty" | "general" | "trail" on the selected loadout
function LoadoutController.debugChoose(row: string, key: string): boolean
	if not isOpen or not draft then
		return false
	end
	if row == "trail" then
		draft.trails[trailSlot] = key
	elseif row == "kit" or row == "bring" or row == "specialty" or row == "general" then
		draft[row] = key
	else
		return false
	end
	presets[activeSlot] = copy(draft)
	presets[activeSlot].name = presets[activeSlot].name or defaultName(activeSlot, draft)
	scheduleSend()
	if not editing then
		buildMain(R.screen)
	end
	return true
end

-- debugView(view, arg): "main" | "edit" (arg = card) | "tab" (arg = tab key) | "slot" (arg = trail slot) | "select" (arg = card)
function LoadoutController.debugView(view: string, arg: any): boolean
	if not isOpen then
		return false
	end
	if view == "main" then
		if editing then
			closeEdit(false)
		end
	elseif view == "edit" then
		openEdit(tonumber(arg) or activeSlot)
	elseif view == "tab" and editing then
		tab = tostring(arg)
		buildTab()
	elseif view == "slot" and editing then
		trailSlot = tostring(arg)
		trailPick = nil
		buildTab()
	elseif view == "select" then
		selectSlot(tonumber(arg) or 1)
	else
		return false
	end
	return true
end

-- Dims the world behind the Edit panel only (the Loadout cards keep the avatar sharp)
local function watchDim()
	local was = false
	RunService.Heartbeat:Connect(function()
		local want = isOpen and editing ~= nil
		if want ~= was then
			was = want
			Cards.dimWorld(want)
		end
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
	-- the five small pictures (refreshSummary fills them)
	local pics = Instance.new("Frame")
	pics.Name = "Pictures"
	pics.BackgroundTransparency = 1
	pics.Size = UDim2.fromOffset(0, 30)
	pics.AutomaticSize = Enum.AutomaticSize.X
	pics.LayoutOrder = 0
	local pl = Instance.new("UIListLayout")
	pl.FillDirection = Enum.FillDirection.Horizontal
	pl.VerticalAlignment = Enum.VerticalAlignment.Center
	pl.SortOrder = Enum.SortOrder.LayoutOrder
	pl.Padding = UDim.new(0, 4)
	pl.Parent = pics
	pics.Parent = holder
	R.summaryIcons = pics
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
	-- the card screens: their own frame with the screen-edge padding
	local cards = Instance.new("Frame")
	cards.Name = "Cards"
	cards.BackgroundTransparency = 1
	cards.Size = UDim2.fromScale(1, 1)
	cards.Visible = false
	local pad = Instance.new("UIPadding")
	pad.Name = "Edge"
	pad.Parent = cards
	cards.Parent = root
	R.screen = cards
	local function edge()
		metrics()
		local p = if compact then 8 else 30
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, p), UDim.new(0, p)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, if compact then 6 else 24), UDim.new(0, if compact then 6 else 22)
	end
	edge()
	saved = readSaved()
	buildSummary(root)
	buildNear(root)
	local promptService = game:GetService("ProximityPromptService")
	promptService.PromptShown:Connect(onPromptShown)
	promptService.PromptHidden:Connect(onPromptHidden)
	task.spawn(pcall, QuietUI.bindRoot, screen)
	watchDim()

	local function relayout()
		local was = compact
		edge()
		if isOpen and was ~= compact then
			if editing then
				buildEdit(R.screen, editing)
			else
				buildMain(R.screen)
			end
		end
	end
	Input.deviceChanged:Connect(function()
		placeSummary()
		relayout()
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	end
	player:GetAttributeChangedSignal("LoadoutTouchLayout"):Connect(relayout)

	ClientState.lifeChanged:Connect(LoadoutController.refresh)
	ClientState.spectateChanged:Connect(LoadoutController.refresh)
	local pending = false
	for _, attribute in ipairs({ "Kit", "KitBring", "KitArmoury", "LoadoutSpecialty", "LoadoutGeneral", "TrailSwing", "TrailArrow",
		"TrailThrow", "TrailsOwned", "Gold", "Level" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if isOpen then
				-- one repaint for a burst of changes (a purchase changes Gold and TrailsOwned together)
				if attribute == "KitArmoury" or attribute == "TrailsOwned" or attribute == "Gold" or attribute == "Level" then
					if not pending then
						pending = true
						task.delay(0.15, function()
							pending = false
							repaint()
						end)
					end
				end
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
			if editing and locked() and tab ~= "trails" then
				tab = "trails"
			end
			repaint()
		end
	end)
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
					setNote(a)
				end
			end)
		end
	end)
	-- Studio only: playtests drive the screens through the LocalPlayer attribute CardsTest ("open", "close",
	-- "edit:<n>", "tab:<key>", "slot:<swing|arrow|throw>", "select:<n>", "main", "inspect:<id>:<stars>", "uninspect")
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("CardsTest"):Connect(function()
			local cmd = player:GetAttribute("CardsTest")
			if type(cmd) ~= "string" or cmd == "" then
				return
			end
			local verb, a, b = string.match(cmd, "^([%w_]+):?([%w_]*):?([%w_]*)")
			if verb == "open" then
				open()
			elseif verb == "close" then
				close()
			elseif verb == "edit" then
				LoadoutController.debugView("edit", tonumber(a))
			elseif verb == "tab" then
				LoadoutController.debugView("tab", a)
			elseif verb == "slot" then
				LoadoutController.debugView("slot", a)
			elseif verb == "select" then
				LoadoutController.debugView("select", tonumber(a))
			elseif verb == "main" then
				LoadoutController.debugView("main")
			elseif verb == "inspect" then
				local inspector = Controllers.InspectController
				if inspector then
					inspector.open(a, tonumber(b) or 3, { from = "test" })
				end
			elseif verb == "uninspect" then
				local inspector = Controllers.InspectController
				if inspector then
					inspector.close()
				end
			end
			player:SetAttribute("CardsTest", nil)
		end)
	end
	LoadoutController.refresh()
end

return LoadoutController
