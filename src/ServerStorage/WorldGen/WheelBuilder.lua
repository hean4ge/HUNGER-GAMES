--[[
	WheelBuilder - the wheel, the prize case, the Masterwork box and the Armoury board in the red train (edit time only).
	docs/design/Weapons_v2.md section 5.5: "a physical object in the red train, mounted on the end bulkhead of the car".

	Where: the front bulkhead of the Observation car (the red wall with the door to the Dining car, its face at z 77.8,
	looking down the car toward +z). The wheel hangs on the panel left of the door (as you face it), its brass odds
	plaque under it; the counter with the steel prize case and the Masterwork box stands on the panel right of the door,
	the Armoury board above it. Nothing else in the train is moved; spawn pads 37 and 38 (z 81.8) stay clear.

	workspace.Lobby.Rewards (Model)
	  Wheel     Backplate, Root (anchored hub; every turning part is welded to it, so a client turns the wheel by
	            setting Root.CFrame), Seg* (wedges, each segment at its true share of the wheel), Spoke*, Rim*, Peg*
	            (32 brass pegs), Label* (SurfaceGui "Mark"), Tongue (leather, clicks over the pegs), Bracket, Lamp
	            (SpotLight "WinLight", off), Plaque (SurfaceGui "Odds"), PromptSpot (ProximityPrompt "Spin")
	            attributes: Segments (count), Pegs (32), Radius
	  Case      Counter, Base, Lid (hinged at the back), Plinth (inside, lowered), Latch1..3, Lamp (SpotLight
	            "CaseLight", off), PromptSpot (ProximityPrompt "Strongbox")
	  Masterwork Box, Lid, Band1..2, PromptSpot (ProximityPrompt "Masterwork")
	  Armoury   Frame, Face (SurfaceGui "Static": the board as built; WheelController draws the live one over it),
	            PromptSpot (the distance check for its buttons)
	Prompts are Custom style (HUDController draws them as one thin line); RewardsAction / RewardsKind attributes say
	what each asks for.

	Edit mode (after the scripts are in Studio):
	  return require(game.ServerStorage.WorldGen.WheelBuilder:Clone()).build()
	  return require(game.ServerStorage.WorldGen.WheelBuilder:Clone()).unbuild()
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WheelBuilder = {}

local WALL_Z = 77.8
local FLOOR_Y = 200
local WHEEL_C = Vector3.new(8793.75, 206.1, WALL_Z + 0.55)
local RADIUS = 2.65
local PEGS = 32
local COUNTER = { x0 = 8803.4, x1 = 8809.3, depth = 2.4, top = 203.2 }

local COLORS = {
	oxblood = Color3.fromRGB(112, 30, 34),
	cream = Color3.fromRGB(226, 214, 188),
	charcoal = Color3.fromRGB(44, 45, 49),
	brass = Color3.fromRGB(168, 132, 70),
	brassDark = Color3.fromRGB(120, 92, 48),
	leather = Color3.fromRGB(92, 58, 38),
	steel = Color3.fromRGB(138, 140, 138),
	steelDark = Color3.fromRGB(92, 94, 94),
	walnut = Color3.fromRGB(70, 48, 34),
	ink = Color3.fromRGB(35, 39, 43),
	paper = Color3.fromRGB(234, 229, 217),
}

local function loadShared(name: string): any
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module:Clone()) -- a clone: never an older cached copy after a push
		if ok then
			return result
		end
	end
	return nil
end

local function fontsFrom(theme: any)
	local F = theme and theme.Fonts or {}
	local montserrat = "rbxasset://fonts/families/Montserrat.json"
	return {
		Light = F.Light or Font.new(montserrat, Enum.FontWeight.Light),
		Medium = F.Medium or Font.new(montserrat, Enum.FontWeight.Medium),
		SemiBold = F.SemiBold or Font.new(montserrat, Enum.FontWeight.SemiBold),
	}
end

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): Part
	local p = new("Part", {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CastShadow = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	})
	if props then
		for k, v in pairs(props) do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- A flat triangle a, b, c made of two wedges, `thickness` thick across the plane.
local function triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3): { WedgePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local out = {}
	for i = 1, 2 do
		local w = Instance.new("WedgePart")
		w.Name = name
		w.Color = color
		w.Material = Enum.Material.SmoothPlastic
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		if i == 1 then
			w.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
		else
			w.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
		end
		w.Parent = parent
		table.insert(out, w)
	end
	return out
end

local function surfaceText(target: BasePart, guiName: string, pxPerStud: number, face: Enum.NormalId?): SurfaceGui
	local size = target.Size
	return new("SurfaceGui", {
		Name = guiName,
		Face = face or Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(math.floor(size.X * pxPerStud), math.floor(size.Y * pxPerStud)),
		LightInfluence = 1, -- lit by the train: matte, never a glowing screen
		Brightness = 1,
		AlwaysOnTop = false,
		MaxDistance = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = target,
	})
end

local function label(parent: Instance, text: string, font: Font, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = text,
		FontFace = font,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
	})
	if props then
		for k, v in pairs(props) do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

local function prompt(spot: BasePart, name: string, action: string, object: string, attrs: { [string]: any })
	local p = new("ProximityPrompt", {
		Name = name,
		ActionText = action,
		ObjectText = object,
		Style = Enum.ProximityPromptStyle.Custom,
		HoldDuration = 0.4, -- a held press: nothing is bought by a stray tap
		MaxActivationDistance = 9,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		Parent = spot,
	})
	for k, v in pairs(attrs) do
		p:SetAttribute(k, v)
	end
	return p
end

-- The wheel ------------------------------------------------------------------------------------------------------------

local function segmentColor(i: number, key: string, count: number): (Color3, Color3)
	if key == "w5" or i == count then
		return COLORS.charcoal, COLORS.cream
	end
	if i % 2 == 1 then
		return COLORS.cream, COLORS.ink
	end
	return COLORS.oxblood, COLORS.cream
end

local function buildWheel(root: Model, Rewards: any, fonts: any)
	local wheel = new("Model", { Name = "Wheel", Parent = root })
	local W = CFrame.lookAt(WHEEL_C, WHEEL_C + Vector3.new(0, 0, 1)) -- looks down the car (+z)
	local function at(angleDeg: number, r: number, forward: number): Vector3
		local a = math.rad(angleDeg)
		-- clockwise from the top as seen by someone facing the wheel (local -X is their right)
		return W:PointToWorldSpace(Vector3.new(-math.sin(a) * r, math.cos(a) * r, -forward))
	end
	local facing = Vector3.new(0, 0, 1)

	-- the static back: a charcoal disc on the wall and a brass outer ring
	part(wheel, "Backplate", Vector3.new(0.3, (RADIUS + 0.35) * 2, (RADIUS + 0.35) * 2),
		CFrame.fromMatrix(at(0, 0, -0.38), facing, Vector3.yAxis), COLORS.walnut, { Shape = Enum.PartType.Cylinder })

	local hub = part(wheel, "Root", Vector3.new(0.34, 0.7, 0.7), CFrame.fromMatrix(at(0, 0, 0.14), facing, Vector3.yAxis),
		COLORS.brass, { Shape = Enum.PartType.Cylinder })
	local turning: { BasePart } = {}

	-- the segments, each at its true size, as fans of triangles no wider than 6 degrees
	local segs = Rewards.WheelSegments
	for i, seg in ipairs(segs) do
		local a0, a1 = Rewards.segmentAngles(i)
		local fill, ink = segmentColor(i, seg[1], #segs)
		local steps = math.max(1, math.ceil((a1 - a0) / 6))
		for s = 1, steps do
			local p0 = a0 + (a1 - a0) * (s - 1) / steps
			local p1 = a0 + (a1 - a0) * s / steps
			for _, w in ipairs(triangle(wheel, string.format("Seg%02d", i), at(0, 0, 0), at(p0, RADIUS, 0), at(p1, RADIUS, 0), 0.12, fill)) do
				table.insert(turning, w)
			end
		end
		-- its mark: a radial strip of thin text (Gold value, or the stars)
		local o = Rewards.outcome(seg[1])
		local mid = (a0 + a1) / 2
		local span = math.rad(a1 - a0)
		local height = math.clamp(span * 1.75 * 0.8, 0.2, 0.85)
		local outward = (at(mid, 1, 0) - at(mid, 0, 0)).Unit
		local up = outward:Cross(facing)
		local strip = part(wheel, string.format("Label%02d", i), Vector3.new(1.55, height, 0.02),
			CFrame.fromMatrix(at(mid, 1.72, 0.075), outward, up), fill, { Transparency = 1, CastShadow = false })
		local gui = surfaceText(strip, "Mark", 120)
		local text = if o.kind == "gold" then string.format("%d <font size=\"%d\">GOLD</font>", o.gold, math.floor(height * 120 * 0.36))
			else string.rep("★", o.stars)
		label(gui, text, fonts.SemiBold, math.floor(height * 120 * 0.62), ink, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextWrapped = false,
			TextScaled = o.kind ~= "gold" and height < 0.4,
		})
		strip.Transparency = 1
		table.insert(turning, strip)
		-- a thin brass spoke on its leading edge
		local sp = part(wheel, string.format("Spoke%02d", i), Vector3.new(RADIUS - 0.35, 0.05, 0.05),
			CFrame.fromMatrix(at(a0, (RADIUS + 0.35) / 2, 0.075), (at(a0, 1, 0) - at(a0, 0, 0)).Unit, facing:Cross((at(a0, 1, 0) - at(a0, 0, 0)).Unit)),
			COLORS.brassDark)
		table.insert(turning, sp)
	end

	-- the rim and its pegs
	local step = 360 / PEGS
	local chord = 2 * (RADIUS + 0.06) * math.sin(math.rad(step / 2)) * 1.04
	for k = 0, PEGS - 1 do
		local a = k * step + step / 2
		local tangent = (at(a + 1, RADIUS + 0.06, 0) - at(a - 1, RADIUS + 0.06, 0)).Unit
		local rim = part(wheel, string.format("Rim%02d", k + 1), Vector3.new(chord, 0.16, 0.26),
			CFrame.fromMatrix(at(a, RADIUS + 0.06, 0.02), tangent, facing:Cross(tangent)), COLORS.brass)
		table.insert(turning, rim)
		local peg = part(wheel, string.format("Peg%02d", k + 1), Vector3.new(0.4, 0.11, 0.11),
			CFrame.fromMatrix(at(k * step, RADIUS - 0.13, 0.2), facing, Vector3.yAxis), COLORS.brass, { Shape = Enum.PartType.Cylinder })
		table.insert(turning, peg)
	end

	for _, p in ipairs(turning) do
		p.Anchored = false
		p.Massless = true
		p.CanQuery = false
		new("WeldConstraint", { Part0 = hub, Part1 = p, Parent = p })
	end

	-- the leather tongue at the top (static), on a brass bracket
	part(wheel, "Bracket", Vector3.new(0.5, 0.45, 0.6), CFrame.new(at(0, RADIUS + 0.48, 0.05)), COLORS.brassDark)
	local tip = at(0, RADIUS - 0.32, 0.36)
	local baseL, baseR = at(-3.2, RADIUS + 0.35, 0.36), at(3.2, RADIUS + 0.35, 0.36)
	local tongue = new("Model", { Name = "Tongue", Parent = wheel })
	triangle(tongue, "Leather", tip, baseL, baseR, 0.06, COLORS.leather)
	tongue:SetAttribute("PivotAt", at(0, RADIUS + 0.35, 0.36))

	-- the warm lamp above it (lights the winning segment when it stops)
	local lampPos = WHEEL_C + Vector3.new(0, RADIUS + 1.35, 1.1)
	local lamp = part(wheel, "Lamp", Vector3.new(0.7, 0.26, 0.5), CFrame.lookAt(lampPos, at(0, RADIUS - 0.8, 0)), COLORS.charcoal)
	new("SpotLight", {
		Name = "WinLight",
		Face = Enum.NormalId.Front,
		Angle = 38,
		Range = 6,
		Brightness = 0,
		Color = Color3.fromRGB(255, 205, 150),
		Shadows = false,
		Enabled = true,
		Parent = lamp,
	})
	part(wheel, "LampArm", Vector3.new(0.12, 0.12, 1.25), CFrame.new(WHEEL_C + Vector3.new(0, RADIUS + 1.35, 0.5)), COLORS.brassDark)

	-- the brass plaque under it: every outcome and its odds, free and paid (rules.md section 2)
	local plaque = part(wheel, "Plaque", Vector3.new(4.1, 2.35, 0.1),
		CFrame.lookAt(Vector3.new(WHEEL_C.X, FLOOR_Y + 1.88, WALL_Z + 0.05), Vector3.new(WHEEL_C.X, FLOOR_Y + 1.88, WALL_Z + 5)), COLORS.brass)
	local gui = surfaceText(plaque, "Odds", 150)
	new("UIPadding", { PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 26), PaddingTop = UDim.new(0, 18), Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = gui })
	local cfg = Rewards.config()
	local engraved = Color3.fromRGB(46, 34, 18)
	label(gui, "THE WHEEL", fonts.SemiBold, 34, engraved, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
	label(gui, string.format("ONE FREE SPIN A DAY  ·  THEN %d GOLD", cfg.Wheel.SpinCost), fonts.Medium, 22, engraved,
		{ Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 2 })
	-- every outcome with its percent, the Gold row then the weapon row
	local goldRow, weaponRow, paidRow = {}, {}, {}
	for _, o in ipairs(Rewards.WheelOutcomes) do
		if o.kind == "gold" then
			table.insert(goldRow, string.format("%d GOLD  <b>%d%%</b>", o.gold, o.chance))
			table.insert(paidRow, Rewards.comma(Rewards.wheelGold(o, true)))
		else
			table.insert(weaponRow, string.format("%s WEAPON  <b>%d%%</b>", string.rep("★", o.stars), o.chance))
		end
	end
	label(gui, table.concat(goldRow, "     "), fonts.Medium, 25, engraved, { Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 3 })
	label(gui, table.concat(weaponRow, "     "), fonts.Medium, 25, engraved, { Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 4 })
	label(gui, string.format("On a paid spin those Gold segments pay %s", table.concat(paidRow, " · ")), fonts.Medium, 20, engraved,
		{ Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 5 })
	label(gui, string.format("A ★★★★ weapon or better is certain by the %dth spin without one. A weapon you already"
		.. " hold at that star comes up last; if it does, it pays Gold.", cfg.Wheel.Pity4),
		fonts.Medium, 18, engraved, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 6 })

	-- where you stand to spin
	local spot = part(wheel, "PromptSpot", Vector3.new(1, 1, 1), CFrame.new(Vector3.new(WHEEL_C.X, FLOOR_Y + 3, WALL_Z + 1.6)),
		COLORS.brass, { Transparency = 1, CanQuery = false, CastShadow = false })
	prompt(spot, "Spin", "Spin", "the wheel", { RewardsAction = "spin" })

	wheel:SetAttribute("Segments", #segs)
	wheel:SetAttribute("Pegs", PEGS)
	wheel:SetAttribute("Radius", RADIUS)
	wheel:SetAttribute("RestCFrame", hub.CFrame)
	return wheel
end

-- The counter, the case and the Masterwork box ---------------------------------------------------------------------------

local function buildCase(root: Model, Rewards: any)
	local cfg = Rewards.config()
	local case = new("Model", { Name = "Case", Parent = root })
	local cx = (COUNTER.x0 + COUNTER.x1) / 2
	local width = COUNTER.x1 - COUNTER.x0
	local cz = WALL_Z + COUNTER.depth / 2
	local height = COUNTER.top - FLOOR_Y
	part(case, "Counter", Vector3.new(width, height - 0.18, COUNTER.depth - 0.1),
		CFrame.new(cx, FLOOR_Y + (height - 0.18) / 2, cz - 0.05), COLORS.walnut, { CanCollide = true })
	part(case, "CounterTop", Vector3.new(width + 0.16, 0.18, COUNTER.depth + 0.08),
		CFrame.new(cx, COUNTER.top - 0.09, cz), COLORS.steelDark, { CanCollide = true })
	part(case, "Kick", Vector3.new(width - 0.2, 0.3, 0.05), CFrame.new(cx, FLOOR_Y + 0.15, WALL_Z + COUNTER.depth - 0.08), COLORS.brassDark)

	-- the steel case (left on the counter): base, lid hinged at the back, a plinth inside, three latches
	local bx = COUNTER.x0 + 1.55
	local baseH = 0.95
	local base = part(case, "Base", Vector3.new(2.3, baseH, 1.5), CFrame.new(bx, COUNTER.top + baseH / 2, cz), COLORS.steel,
		{ Material = Enum.Material.Metal, CanCollide = true })
	local lid = part(case, "Lid", Vector3.new(2.36, 0.22, 1.56), CFrame.new(bx, COUNTER.top + baseH + 0.11, cz), COLORS.steelDark,
		{ Material = Enum.Material.Metal })
	lid:SetAttribute("Hinge", CFrame.new(bx, COUNTER.top + baseH + 0.11, cz - 0.78))
	local plinth = part(case, "Plinth", Vector3.new(0.18, 0.8, 0.8), CFrame.fromMatrix(Vector3.new(bx, COUNTER.top + baseH - 0.2, cz), Vector3.yAxis, -Vector3.xAxis),
		COLORS.brass, { Shape = Enum.PartType.Cylinder })
	plinth:SetAttribute("Rest", plinth.CFrame)
	for i = 1, 3 do
		part(case, "Latch" .. i, Vector3.new(0.22, 0.28, 0.06), CFrame.new(bx - 0.75 + (i - 1) * 0.75, COUNTER.top + baseH - 0.05, cz + 0.78), COLORS.brass)
	end
	local lampPos = Vector3.new(bx, 210.2, cz + 0.6)
	local lamp = part(case, "Lamp", Vector3.new(0.55, 0.24, 0.55), CFrame.lookAt(lampPos, Vector3.new(bx, COUNTER.top, cz)), COLORS.charcoal)
	new("SpotLight", {
		Name = "CaseLight",
		Face = Enum.NormalId.Front,
		Angle = 34,
		Range = 9,
		Brightness = 0,
		Color = Color3.fromRGB(255, 226, 190),
		Shadows = true,
		Enabled = true,
		Parent = lamp,
	})
	local spot = part(case, "PromptSpot", Vector3.new(1, 1, 1), CFrame.new(bx, COUNTER.top + 0.6, cz + 0.9), COLORS.steel,
		{ Transparency = 1, CanQuery = false, CastShadow = false })
	prompt(spot, "Strongbox", "Open", string.format("a Strongbox · %s Gold", Rewards.comma(cfg.Strongbox.Cost)),
		{ RewardsAction = "box", RewardsKind = "strongbox" })

	-- the Masterwork box (right on the counter): dark walnut, brass bands
	local mw = new("Model", { Name = "Masterwork", Parent = root })
	local mx = COUNTER.x1 - 1.0
	part(mw, "Box", Vector3.new(1.35, 0.8, 1.05), CFrame.new(mx, COUNTER.top + 0.4, cz), COLORS.walnut, { CanCollide = true })
	part(mw, "Lid", Vector3.new(1.41, 0.18, 1.11), CFrame.new(mx, COUNTER.top + 0.89, cz), COLORS.charcoal)
	for i = 1, 2 do
		part(mw, "Band" .. i, Vector3.new(0.1, 1.0, 1.13), CFrame.new(mx - 0.4 + (i - 1) * 0.8, COUNTER.top + 0.5, cz), COLORS.brass)
	end
	local mspot = part(mw, "PromptSpot", Vector3.new(1, 1, 1), CFrame.new(mx, COUNTER.top + 0.6, cz + 0.9), COLORS.steel,
		{ Transparency = 1, CanQuery = false, CastShadow = false })
	prompt(mspot, "Masterwork", "Open", string.format("a Masterwork Strongbox · %s Gold", Rewards.comma(cfg.Strongbox.MasterworkCost)),
		{ RewardsAction = "box", RewardsKind = "masterwork" })
end

-- The Armoury board ----------------------------------------------------------------------------------------------------

local function buildArmoury(root: Model, Rewards: any, fonts: any)
	local cfg = Rewards.config()
	local board = new("Model", { Name = "Armoury", Parent = root })
	local cx = (COUNTER.x0 + COUNTER.x1) / 2
	local w, h = COUNTER.x1 - COUNTER.x0, 5.3
	local cy = COUNTER.top + 1.05 + h / 2
	part(board, "Frame", Vector3.new(w + 0.24, h + 0.24, 0.12), CFrame.new(cx, cy, WALL_Z + 0.06), COLORS.walnut)
	local face = part(board, "Face", Vector3.new(w, h, 0.04),
		CFrame.lookAt(Vector3.new(cx, cy, WALL_Z + 0.14), Vector3.new(cx, cy, WALL_Z + 5)), COLORS.paper)
	local gui = surfaceText(face, "Static", 200)
	gui.MaxDistance = 80
	new("UIPadding", { PaddingLeft = UDim.new(0, 48), PaddingRight = UDim.new(0, 48), PaddingTop = UDim.new(0, 40), Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = gui })
	local ink = COLORS.ink
	label(gui, "ARMOURY", fonts.SemiBold, 54, ink, { Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 1 })
	label(gui, string.format("Any weapon at ★★★ for %s Gold · no chance", Rewards.comma(cfg.Armoury.Buy3)), fonts.Medium, 34, ink,
		{ Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2 })
	label(gui, string.format("Strongbox  %s Gold\n%s", Rewards.comma(cfg.Strongbox.Cost), Rewards.boxOddsLine("strongbox")),
		fonts.Medium, 34, ink, { Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 3 })
	label(gui, string.format("Masterwork Strongbox  %s Gold\n%s", Rewards.comma(cfg.Strongbox.MasterworkCost), Rewards.boxOddsLine("masterwork")),
		fonts.Medium, 34, ink, { Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 4 })
	label(gui, string.format("A ★★★★ or better is certain by the %dth box without one, a ★★★★★ by the %dth. A weapon you"
		.. " already hold at that star comes up last; if it does, you get your Gold back.", cfg.Strongbox.Pity4, cfg.Strongbox.Pity5),
		fonts.Medium, 28, ink, { Size = UDim2.new(1, 0, 0, 120), LayoutOrder = 5, TextTransparency = 0.25 })
	part(board, "PromptSpot", Vector3.new(1, 1, 1), CFrame.new(cx, COUNTER.top + 0.6, WALL_Z + COUNTER.depth + 0.6), COLORS.steel,
		{ Transparency = 1, CanQuery = false, CastShadow = false })
end

function WheelBuilder.build(): string
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return "WheelBuilder: no workspace.Lobby; nothing built"
	end
	local Rewards = loadShared("Rewards")
	if not Rewards then
		return "WheelBuilder: ReplicatedStorage.Shared.Rewards is missing; push it first"
	end
	local fonts = fontsFrom(loadShared("Theme"))
	local old = lobby:FindFirstChild("Rewards")
	if old then
		old:Destroy()
	end
	local root = new("Model", { Name = "Rewards" })
	buildWheel(root, Rewards, fonts)
	buildCase(root, Rewards)
	buildArmoury(root, Rewards, fonts)
	root.Parent = lobby
	return string.format("WheelBuilder built %s: %d parts", root:GetFullName(), #root:GetDescendants())
end

function WheelBuilder.unbuild(): string
	local lobby = workspace:FindFirstChild("Lobby")
	local old = lobby and lobby:FindFirstChild("Rewards")
	if old then
		old:Destroy()
		return "WheelBuilder: removed"
	end
	return "WheelBuilder: nothing to remove"
end

return WheelBuilder
