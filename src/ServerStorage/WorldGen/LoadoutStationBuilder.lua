--[[
	LoadoutStationBuilder - the Loadout rack in the red train (edit time only). docs/design/Combat_v3.md section 3.2:
	"The kit rack in the red train (the orange-framed rack with blue padded trays) becomes the Loadout rack. Walk up,
	the prompt reads E Loadout."

	Where: the front of the Lounge car (the arrival car), against the closed front door (wall face z -67.0 in the
	place, the car's centre line x 8800), facing down the car (+z). art/manifests/TrainLobby.manifest.json: the
	Lounge's aisle is 13 wide and clear; the nearest club chairs stand at x 8792 / 8808 from z -64.1, the first spawn
	pads at z -57. The rack is 7.2 wide and 1.9 deep (z -66.95 .. -65.05), so the aisle in front of it (z -65 .. -58)
	stays open and no chair, pad or door is touched.

	workspace.Lobby.LoadoutStation (Model)
	  Frame*      matte orange powder-coated steel: two side frames, top rail, foot rails, castors
	  Tray        the upper tray (blue padding): LoadoutController lays the chosen kit on it (Attachment "TraySpot")
	  Shelf       the lower tray (blue padding, empty)
	  Board       a pegboard at the back with a brass hook rail: the brought weapon hangs here (Attachment "HookSpot")
	  Plaque      a small brass plate on the top rail, LOADOUT in thin letters (SurfaceGui "Mark")
	  StandSpot   invisible: where your avatar stands for the preview (Attachment "Stand", looking down the car)
	  PromptSpot  invisible, ProximityPrompt "Loadout" (Custom style: HUDController draws it as one thin line;
	              E / gamepad X / tap; no hold). LoadoutController opens the screen on Triggered.
	Everything is matte (SmoothPlastic / Fabric, Reflectance 0), anchored, no collisions except the frame's one box.

	Edit mode (after the scripts are in Studio):
	  return require(game.ServerStorage.WorldGen.LoadoutStationBuilder:Clone()).build()
	  return require(game.ServerStorage.WorldGen.LoadoutStationBuilder:Clone()).unbuild()
]]
local LoadoutStationBuilder = {}

local WALL_Z = -67.0 -- the Lounge's front wall face (its collider centre -67.5, 1 thick)
local FLOOR_Y = 200
local CX = 8800
local WIDTH = 7.2
local DEPTH = 1.9

local COLORS = {
	orange = Color3.fromRGB(196, 104, 44), -- powder-coated steel, matte (the training-hall trolley)
	orangeDark = Color3.fromRGB(150, 76, 34),
	pad = Color3.fromRGB(46, 74, 124), -- blue padded trays
	padSeam = Color3.fromRGB(34, 54, 92),
	board = Color3.fromRGB(64, 56, 50), -- dark pegboard
	hole = Color3.fromRGB(36, 32, 30),
	brass = Color3.fromRGB(168, 132, 70),
	rubber = Color3.fromRGB(30, 30, 32),
	ink = Color3.fromRGB(35, 39, 43),
}

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
		CanQuery = false,
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

local function cyl(parent: Instance, name: string, length: number, diameter: number, cf: CFrame, color: Color3): Part
	-- a cylinder's axis is its X: cf is given for the axis along X
	return part(parent, name, Vector3.new(length, diameter, diameter), cf, color, { Shape = Enum.PartType.Cylinder })
end

local function buildFrame(root: Model)
	local zBack, zFront = WALL_Z + 0.15, WALL_Z + DEPTH
	local zMid = (zBack + zFront) / 2
	local x0, x1 = CX - WIDTH / 2, CX + WIDTH / 2
	local top = FLOOR_Y + 5.4
	-- the two side frames: front and back uprights, joined top and bottom
	for i, x in ipairs({ x0 + 0.12, x1 - 0.12 }) do
		for j, z in ipairs({ zBack + 0.12, zFront - 0.12 }) do
			part(root, string.format("FramePost%d%d", i, j), Vector3.new(0.24, top - FLOOR_Y - 0.5, 0.24),
				CFrame.new(x, (FLOOR_Y + 0.5 + top) / 2, z), COLORS.orange)
		end
		part(root, "FrameSideTop" .. i, Vector3.new(0.24, 0.24, DEPTH - 0.15), CFrame.new(x, top - 0.12, zMid), COLORS.orange)
		part(root, "FrameSideFoot" .. i, Vector3.new(0.26, 0.2, DEPTH - 0.15), CFrame.new(x, FLOOR_Y + 0.62, zMid), COLORS.orangeDark)
		-- castors under the foot
		for j, z in ipairs({ zBack + 0.3, zFront - 0.3 }) do
			part(root, string.format("FrameCastorFork%d%d", i, j), Vector3.new(0.18, 0.18, 0.18), CFrame.new(x, FLOOR_Y + 0.44, z), COLORS.orangeDark)
			cyl(root, string.format("FrameCastor%d%d", i, j), 0.14, 0.34, CFrame.new(x, FLOOR_Y + 0.18, z), COLORS.rubber)
		end
	end
	-- top rail across the front, and the push bar
	part(root, "FrameTopRail", Vector3.new(WIDTH, 0.24, 0.24), CFrame.new(CX, top - 0.12, zFront - 0.12), COLORS.orange)
	part(root, "FrameBackRail", Vector3.new(WIDTH, 0.24, 0.24), CFrame.new(CX, top - 0.12, zBack + 0.12), COLORS.orange)
	part(root, "FrameFootRail", Vector3.new(WIDTH - 0.3, 0.2, 0.2), CFrame.new(CX, FLOOR_Y + 0.62, zFront - 0.12), COLORS.orangeDark)
	-- one collider for the whole rack (players lean on it, never walk through it)
	part(root, "Collider", Vector3.new(WIDTH, top - FLOOR_Y, DEPTH), CFrame.new(CX, (FLOOR_Y + top) / 2, zMid), COLORS.orange,
		{ Transparency = 1, CanCollide = true, CastShadow = false })
	return top, zBack, zFront, zMid
end

local function buildTray(root: Model, name: string, y: number, zBack: number, zFront: number, lip: number): Part
	local zMid = (zBack + zFront) / 2
	local width = WIDTH - 0.5
	local depth = zFront - zBack - 0.1
	-- the steel pan and its lip
	part(root, name .. "Pan", Vector3.new(width, 0.12, depth), CFrame.new(CX, y, zMid), COLORS.orange)
	part(root, name .. "LipFront", Vector3.new(width, lip, 0.1), CFrame.new(CX, y + lip / 2, zFront - 0.1), COLORS.orange)
	-- the blue pad: two cushions with a seam, slightly domed (a thin top layer)
	local pad = part(root, name, Vector3.new(width - 0.16, 0.18, depth - 0.2), CFrame.new(CX, y + 0.15, zMid), COLORS.pad,
		{ Material = Enum.Material.Fabric })
	part(root, name .. "Seam", Vector3.new(0.06, 0.19, depth - 0.24), CFrame.new(CX, y + 0.16, zMid), COLORS.padSeam,
		{ Material = Enum.Material.Fabric })
	for i, dx in ipairs({ -width / 4, width / 4 }) do
		part(root, name .. "Dome" .. i, Vector3.new(width / 2 - 0.4, 0.05, depth - 0.5), CFrame.new(CX + dx, y + 0.26, zMid),
			COLORS.pad, { Material = Enum.Material.Fabric })
	end
	return pad
end

local function buildBoard(root: Model, top: number, zBack: number)
	local y0, y1 = FLOOR_Y + 3.3, top - 0.3
	local board = part(root, "Board", Vector3.new(WIDTH - 0.5, y1 - y0, 0.1), CFrame.new(CX, (y0 + y1) / 2, zBack + 0.08), COLORS.board)
	-- a few rows of peg holes (small dark squares; cheap: 3 x 9)
	for row = 1, 3 do
		for col = 1, 9 do
			local x = CX - (WIDTH - 1.2) / 2 + (col - 1) * (WIDTH - 1.2) / 8
			local y = y0 + 0.35 + (row - 1) * ((y1 - y0 - 0.7) / 2)
			part(root, string.format("BoardHole%d_%d", row, col), Vector3.new(0.09, 0.09, 0.02), CFrame.new(x, y, zBack + 0.14), COLORS.hole,
				{ CastShadow = false })
		end
	end
	-- the brass hook rail the brought weapon hangs from
	local railY = y0 + (y1 - y0) * 0.62
	cyl(root, "BoardRail", WIDTH - 1.0, 0.09, CFrame.new(CX, railY, zBack + 0.24), COLORS.brass)
	for i, dx in ipairs({ -0.55, 0.55 }) do
		part(root, "BoardHook" .. i, Vector3.new(0.08, 0.08, 0.34), CFrame.new(CX + dx, railY, zBack + 0.36), COLORS.brass)
		part(root, "BoardHookTip" .. i, Vector3.new(0.08, 0.2, 0.08), CFrame.new(CX + dx, railY + 0.08, zBack + 0.5), COLORS.brass)
	end
	local hook = new("Attachment", { Name = "HookSpot", Parent = board })
	hook.WorldCFrame = CFrame.new(CX, railY + 0.1, zBack + 0.55)
	return board
end

local function buildPlaque(root: Model, top: number, zFront: number)
	local plaque = part(root, "Plaque", Vector3.new(2.4, 0.42, 0.05), CFrame.new(CX, top - 0.12, zFront + 0.03), COLORS.brass)
	local gui = new("SurfaceGui", {
		Name = "Mark",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 100,
		LightInfluence = 1,
		Parent = plaque,
	})
	new("TextLabel", {
		Name = "Word",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "L O A D O U T",
		TextColor3 = COLORS.ink,
		TextTransparency = 0.1,
		TextSize = 26,
		FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold),
		Parent = gui,
	})
end

function LoadoutStationBuilder.build(): string
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return "LoadoutStationBuilder: no workspace.Lobby; nothing built"
	end
	local old = lobby:FindFirstChild("LoadoutStation")
	if old then
		old:Destroy()
	end
	local root = new("Model", { Name = "LoadoutStation" })
	local top, zBack, zFront = buildFrame(root)
	buildTray(root, "Shelf", FLOOR_Y + 1.15, zBack, zFront, 0.18)
	local tray = buildTray(root, "Tray", FLOOR_Y + 3.0, zBack + 0.55, zFront, 0.22)
	local traySpot = new("Attachment", { Name = "TraySpot", Parent = tray })
	traySpot.WorldCFrame = CFrame.new(CX, FLOOR_Y + 3.0 + 0.3, (zBack + 0.55 + zFront) / 2)
	buildBoard(root, top, zBack)
	buildPlaque(root, top, zFront)

	-- where your avatar stands for the preview: 3.2 in front of the rack, facing down the car (+z)
	local stand = part(root, "StandSpot", Vector3.new(1, 0.2, 1), CFrame.new(CX, FLOOR_Y + 0.1, zFront + 3.2), COLORS.orange,
		{ Transparency = 1, CastShadow = false })
	local standAt = new("Attachment", { Name = "Stand", Parent = stand })
	standAt.WorldCFrame = CFrame.lookAt(Vector3.new(CX, FLOOR_Y + 3, zFront + 3.2), Vector3.new(CX, FLOOR_Y + 3, zFront + 10))

	local spot = part(root, "PromptSpot", Vector3.new(1, 1, 1), CFrame.new(CX, FLOOR_Y + 3.4, zFront + 0.6), COLORS.orange,
		{ Transparency = 1, CastShadow = false })
	new("ProximityPrompt", {
		Name = "Loadout",
		ActionText = "Loadout",
		ObjectText = "",
		Style = Enum.ProximityPromptStyle.Custom,
		HoldDuration = 0,
		MaxActivationDistance = 8,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		Parent = spot,
	}):SetAttribute("LoadoutAction", true)

	root.PrimaryPart = stand
	root.Parent = lobby
	return string.format("LoadoutStationBuilder built %s: %d instances, rack %.1f x %.1f at x %.0f, z %.2f .. %.2f",
		root:GetFullName(), #root:GetDescendants(), WIDTH, DEPTH, CX, zBack, zFront)
end

function LoadoutStationBuilder.unbuild(): string
	local lobby = workspace:FindFirstChild("Lobby")
	local old = lobby and lobby:FindFirstChild("LoadoutStation")
	if old then
		old:Destroy()
		return "LoadoutStationBuilder: removed"
	end
	return "LoadoutStationBuilder: nothing to remove"
end

return LoadoutStationBuilder
