--[[
	StationSign - a small standing sign: a foot plate, a slim post and a little lectern board, tilted back, at about
	waist height, with a name in the Quiet style (Montserrat SemiBold, warm paper ink on a matte charcoal board), an
	optional caption line under it, an optional atlas icon at its left and a thin orange edge (orange = "you can use
	this", ArtStyle rule 9). Made for the Training Centre's kit and Specialty mats (20 Nov: the owner asked for small
	standing signs in place of the names lying flat on the mats); any station, prop or room can reuse it.

	Edit time or server. Only makes Instances; no behaviour.

	StationSign.make(opts) -> Model
	  opts.CFrame   the floor point the sign stands on; its LookVector is the way the board's face looks (toward the reader)
	  opts.Title    the name ("CLIMBER")
	  opts.Caption  optional small line under the name ("Kit · stand on the mat")
	  opts.Icon     optional Shared.Icons / IconAtlas name ("climber", "kit_climber"); no icon when it has no atlas cell
	  opts.Width    board width in studs (default 2.6; the board is 1.05 tall)
	  opts.Height   height of the board's centre above the floor (default 3.05: waist to chest on a 5-stud character)
	  opts.BoardHeight  board height in studs (default 1.05); the taller bay signs use about 1.6
	  opts.Tilt     degrees the board leans back (default StationSign.Tilt); a tall bay sign reads better near upright
	  opts.Name     the Model's name (default "Sign")
	  opts.Parent   parent, set last
	Nothing collides, is queried (arrows, throws and camera rays pass) or is touched: the sign is a picture of a sign,
	so it can never snag a player or eat a shot. Keep it beside walking lines anyway (see TrainingStations mats `sign`).
	The Model's pivot is opts.CFrame; move it with :PivotTo.
]]

local Shared = script.Parent
local IconAtlas = require(Shared:WaitForChild("IconAtlas"))
local okIcons, Icons = pcall(require, Shared:WaitForChild("Icons"))

local StationSign = {}

StationSign.Colors = {
	Board = Color3.fromRGB(40, 44, 48), -- matte charcoal face
	Stand = Color3.fromRGB(66, 70, 74), -- post and foot: dark steel
	Ink = Color3.fromRGB(238, 233, 222), -- the name (warm paper white)
	Ink2 = Color3.fromRGB(170, 172, 168), -- the caption
	Use = Color3.fromRGB(226, 120, 44), -- the orange edge (TrainingStations.Colors.Use)
}
StationSign.Tilt = 28 -- degrees the board leans back from upright (a lectern: read from standing height)
StationSign.PixelsPerStud = 100

local FONT_NAME = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
local FONT_CAPTION = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- the atlas cell for an icon name (Icons resolves the game's names; IconAtlas cell names work as written)
local function cellOf(name: string?): any
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if IconAtlas.Cells[name] then
		return IconAtlas.Cells[name]
	end
	if okIcons and type(Icons) == "table" and type(Icons.cell) == "function" then
		local ok, _, cell = pcall(Icons.cell, name)
		if ok and cell then
			return cell
		end
	end
	return nil
end

local function face(board: BasePart, opts: any, width: number, height: number)
	local ppx = StationSign.PixelsPerStud
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppx
	gui.LightInfluence = 0.35 -- lit by the room a little, never so dark it cannot be read
	gui.Brightness = 1
	gui.MaxDistance = 90
	local W, H = width * ppx, height * ppx

	-- the orange edge (left), the only colour on the board
	local edge = Instance.new("Frame")
	edge.Name = "UseEdge"
	edge.BorderSizePixel = 0
	edge.BackgroundColor3 = StationSign.Colors.Use
	edge.Size = UDim2.fromOffset(8, H)
	edge.Parent = gui

	local left = 22
	local cell = cellOf(opts.Icon)
	local sheet = cell and IconAtlas.Sheets[cell.Sheet]
	if cell and sheet then
		local size = math.floor(H * 0.62)
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = sheet.Image
		img.ImageRectOffset = Vector2.new(cell.X, cell.Y)
		img.ImageRectSize = Vector2.new(cell.W, cell.H)
		img.ScaleType = Enum.ScaleType.Fit
		img.AnchorPoint = Vector2.new(0, 0.5)
		img.Position = UDim2.new(0, left, 0.5, 0)
		img.Size = UDim2.fromOffset(size, size)
		img.Parent = gui
		left += size + 14
	end

	local hasCaption = type(opts.Caption) == "string" and opts.Caption ~= ""
	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.BackgroundTransparency = 1
	name.FontFace = FONT_NAME
	name.Text = tostring(opts.Title or "")
	name.TextColor3 = StationSign.Colors.Ink
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextYAlignment = if hasCaption then Enum.TextYAlignment.Bottom else Enum.TextYAlignment.Center
	name.TextScaled = true
	name.Position = UDim2.fromOffset(left, if hasCaption then H * 0.14 else H * 0.22)
	name.Size = UDim2.fromOffset(W - left - 14, if hasCaption then H * 0.44 else H * 0.56)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.floor(H * 0.42)
	limit.Parent = name
	name.Parent = gui

	if hasCaption then
		local cap = Instance.new("TextLabel")
		cap.Name = "Caption"
		cap.BackgroundTransparency = 1
		cap.FontFace = FONT_CAPTION
		cap.Text = opts.Caption
		cap.TextColor3 = StationSign.Colors.Ink2
		cap.TextXAlignment = Enum.TextXAlignment.Left
		cap.TextYAlignment = Enum.TextYAlignment.Top
		cap.TextScaled = true
		cap.Position = UDim2.fromOffset(left + 1, H * 0.62)
		cap.Size = UDim2.fromOffset(W - left - 14, H * 0.2)
		local capLimit = Instance.new("UITextSizeConstraint")
		capLimit.MaxTextSize = math.floor(H * 0.2)
		capLimit.Parent = cap
		cap.Parent = gui
	end
	gui.Parent = board
end

function StationSign.make(opts: { [string]: any }): Model
	local at: CFrame = opts.CFrame or CFrame.new()
	local width = opts.Width or 2.6
	local boardH = opts.BoardHeight or 1.05
	local centreY = opts.Height or 3.05
	local tilt = math.rad(opts.Tilt or StationSign.Tilt)
	local C = StationSign.Colors

	local model = Instance.new("Model")
	model.Name = opts.Name or "Sign"

	-- the board: leaning back about its own centre (its face, Front, looks along `at`'s LookVector and a little up)
	local boardCF = at * CFrame.new(0, centreY, 0) * CFrame.Angles(tilt, 0, 0)
	local board = part(model, "Board", Vector3.new(width, boardH, 0.1), boardCF, C.Board)
	-- a thin rim behind it, a shade lighter, so the board reads as a plate on a frame
	part(model, "Back", Vector3.new(width + 0.08, boardH + 0.08, 0.06), boardCF * CFrame.new(0, 0, 0.08), C.Stand)
	-- the post: from the foot to the back of the board's lower half
	local postTop = centreY - 0.1
	local postZ = 0.22 -- behind the board's centre line, so the face stays clear
	part(model, "Post", Vector3.new(0.2, postTop, 0.2), at * CFrame.new(0, postTop / 2, postZ), C.Stand)
	-- a small bracket from the post into the board's back
	part(model, "Bracket", Vector3.new(0.5, 0.16, 0.34), at * CFrame.new(0, postTop - 0.02, postZ - 0.08), C.Stand)
	-- the foot plate
	part(model, "Foot", Vector3.new(1.2, 0.12, 0.9), at * CFrame.new(0, 0.06, postZ), C.Stand)

	face(board, opts, width, boardH)

	model.WorldPivot = at
	if opts.Parent then
		model.Parent = opts.Parent
	end
	return model
end

return StationSign
