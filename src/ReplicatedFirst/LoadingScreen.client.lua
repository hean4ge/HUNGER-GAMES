--[[
	LoadingScreen (ReplicatedFirst, client) - the first thing a player sees after pressing Play (wave 20, "loadscreen").

	Owner's brief: a loading GUI on a dark screen with a glowing progress bar, a small bird that loads with the screen,
	and the words ARENA 48 revealed as it loads, in a rusted, forest-weathered 3D-ish look.

	What it draws (all plain GuiObjects; nothing is uploaded)
	  * A near-black forest night: two rows of pine silhouettes (stacked rotated squares), a ground band, slow dust.
	  * Our own bird mark: a small perched songbird on a twig, drawn from rounded frames and rotated bars (no ring, no
	    arrow). A dim ink copy, and an amber copy that fills it from the feet up as the game loads (a CanvasGroup clip).
	    It flaps now and then, and once more when loading is done.
	  * ARENA 48, one letter at a time as progress passes each letter's mark: per letter a drop shadow, a five-step
	    extrusion in dark rust, a warm rim highlight, a rust-to-moss gradient face with a dark stroke and a moss grime
	    layer creeping up from the bottom. Oswald Bold (Roblox's own family).
	  * A slim amber bar with a soft glow and a bright head, the percentage (RobotoMono) and a quiet status line.

	Progress (never goes backwards)
	  0.00 - 0.40  before game:IsLoaded(): eases toward 0.40 with time, nudged by ContentProvider.RequestQueueSize
	  0.40 - 0.55  the character is in the world
	  0.55 - 0.95  the train lobby's content (Workspace.Lobby and the PlayerGui) preloaded first, measured by the
	               request queue draining from its peak
	  1.00         all of that done (or the cap reached)
	  Hard cap: the screen fades out CAP seconds after it appeared, whatever is still loading. Minimum MIN_SHOW so the
	  title has time to be read on a fast machine.

	Load order (what this script asks for, in order)
	  1. the lobby: Workspace.Lobby (Persistent) and the player's own GUI, during the screen
	  2. after the screen: ReplicatedStorage.Assets.Viewmodel (first-person arms), a few seconds later
	  3. on the ride (GameState.TrainStage "Ride", or 90 s after joining, or at once if this player joins into a
	     running round): ReplicatedStorage.Assets Items, Crates, Creatures, in small batches
	  The AudioController preloads short sounds after the first screen; music beds are streamed, never preloaded.

	Measurements: LocalPlayer attribute LoadScreen (JSON: seconds since this script began for loaded, character,
	lobby, done, the request queue's peak, whether the cap fired) and one [LoadingScreen] line in the output.
	LocalPlayer attribute LoadingScreenUp is true while the screen is up.
]]
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local T0 = os.clock()
local CAP = 25 -- seconds: never hold anyone longer than this
local MIN_SHOW = 3.2 -- seconds: long enough to read the title on a fast machine
local HOLD_AT_FULL = 0.7 -- seconds at 100 % before the fade
local FADE = 0.9

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
player:SetAttribute("LoadingScreenUp", true)

---------------------------------------------------------------------------
-- Palette and fonts
---------------------------------------------------------------------------
local INK = Color3.fromRGB(244, 241, 234) -- #F4F1EA
local SUN = Color3.fromRGB(232, 182, 90) -- #E8B65A
local NIGHT = Color3.fromRGB(9, 12, 10)
local PINE_FAR = Color3.fromRGB(20, 28, 22)
local PINE_NEAR = Color3.fromRGB(13, 19, 15)

local RUST_LIGHT = Color3.fromRGB(219, 132, 74)
local RUST = Color3.fromRGB(178, 84, 42)
local RUST_DARK = Color3.fromRGB(132, 58, 28)
local BARK = Color3.fromRGB(112, 74, 36)
local MOSS = Color3.fromRGB(96, 112, 52)
local MOSS_DEEP = Color3.fromRGB(62, 84, 40)
local EXTRUDE_NEAR = Color3.fromRGB(78, 42, 22)
local EXTRUDE_FAR = Color3.fromRGB(34, 20, 12)
local STROKE = Color3.fromRGB(26, 17, 10)
local RIM = Color3.fromRGB(244, 186, 124)

local TITLE_FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local SMALL_FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)
local MONO_FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)

---------------------------------------------------------------------------
-- Fading: every drawn property is registered with its full-strength value and a group (0 = the whole screen, a
-- letter index = that letter). shown = base faded by the group's alpha and the screen's alpha.
---------------------------------------------------------------------------
local registry: { { inst: Instance, prop: string, base: number, group: number } } = {}
local groupAlpha: { [number]: number } = { [0] = 1 }
local screenAlpha = 1
local dirty = true

local function reg(inst: Instance, prop: string, base: number, group: number?)
	table.insert(registry, { inst = inst, prop = prop, base = base, group = group or 0 })
end

local function applyAlpha()
	for _, r in ipairs(registry) do
		local a = screenAlpha * (if r.group == 0 then 1 else (groupAlpha[r.group] or 0))
		;(r.inst :: any)[r.prop] = 1 - (1 - r.base) * a
	end
	dirty = false
end

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function frame(props: { [string]: any }, parent: Instance, group: number?, round: number?): Frame
	local alpha = props.BackgroundTransparency or 0
	props.BorderSizePixel = 0
	local f = make("Frame", props, parent)
	reg(f, "BackgroundTransparency", alpha, group)
	if round then
		make("UICorner", { CornerRadius = UDim.new(round, 0) }, f)
	end
	return f
end

local function label(props: { [string]: any }, parent: Instance, group: number?): TextLabel
	local alpha = props.TextTransparency or 0
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	local l = make("TextLabel", props, parent)
	reg(l, "TextTransparency", alpha, group)
	return l
end

---------------------------------------------------------------------------
-- The screen
---------------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 10000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ScreenInsets = Enum.ScreenInsets.None,
})

local bg = frame({ Name = "Night", Size = UDim2.fromScale(1, 1), BackgroundColor3 = NIGHT }, gui)
make("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(6, 8, 8)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(14, 20, 17)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(18, 24, 19)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 9)),
	}),
}, bg)

-- Pines: a tree is three rotated squares stacked (diamonds), the lower half of each hidden by the next one down
local rng = Random.new(48)
local function pineRow(count: number, baseY: number, minH: number, maxH: number, color: Color3, z: number)
	local row = make("Frame", { Name = "Pines", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z }, bg)
	for i = 1, count do
		local x = (i - 0.5) / count + rng:NextNumber(-0.4, 0.4) / count
		local h = rng:NextInteger(minH, maxH)
		for k = 0, 2 do
			local s = math.floor(h * (0.34 + k * 0.12))
			local y = -h * (0.62 - k * 0.24)
			frame({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(x, 0, baseY, y),
				Size = UDim2.fromOffset(s, s),
				Rotation = 45,
				BackgroundColor3 = color,
				ZIndex = z,
			}, row)
		end
		frame({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(x, 0, baseY, 0),
			Size = UDim2.fromOffset(math.max(3, math.floor(h * 0.06)), math.floor(h * 0.3)),
			BackgroundColor3 = color,
			ZIndex = z,
		}, row)
	end
end
pineRow(22, 0.9, 70, 140, PINE_FAR, 2)
-- a low band of fog between the rows
local fog = frame({
	Name = "Fog",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 0.92),
	Size = UDim2.fromScale(1, 0.16),
	BackgroundColor3 = Color3.fromRGB(46, 58, 50),
	BackgroundTransparency = 0.82,
	ZIndex = 3,
}, bg)
make("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, fog)
pineRow(14, 0.97, 110, 220, PINE_NEAR, 4)
frame({
	Name = "Ground",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0.05, 2),
	BackgroundColor3 = Color3.fromRGB(7, 9, 8),
	ZIndex = 5,
}, bg)

-- Dust motes drifting up through the dark
local motes = {}
for i = 1, 22 do
	local m = frame({
		Size = UDim2.fromOffset(2, 2),
		BackgroundColor3 = if i % 4 == 0 then SUN else INK,
		BackgroundTransparency = rng:NextNumber(0.72, 0.9),
		ZIndex = 6,
	}, bg, nil, 1)
	table.insert(motes, { f = m, x = rng:NextNumber(), y = rng:NextNumber(), v = rng:NextNumber(0.006, 0.02), p = rng:NextNumber(0, 6.28) })
end

-- The centre stack, scaled to the screen
local stack = make("Frame", {
	Name = "Stack",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(640, 270),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, gui)
local uiScale = make("UIScale", { Scale = 1 }, stack)
local function rescale()
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	uiScale.Scale = math.clamp(math.min(vp.X / 760, vp.Y / 520), 0.45, 1.35)
end
rescale()

---------------------------------------------------------------------------
-- The bird: a perched songbird, facing right, in a 64 x 48 box
---------------------------------------------------------------------------
local BIRD_W, BIRD_H = 64, 48
local birdBox = make("Frame", {
	Name = "Bird",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(BIRD_W, BIRD_H),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, stack)
local BIRD_SCALE = 1.3
local birdScale = make("UIScale", { Scale = BIRD_SCALE }, birdBox)

local wings: { Frame } = {}
local heads: { Frame } = {}
local function drawBird(parent: Instance, color: Color3, alpha: number, eyeColor: Color3, wingColor: Color3, z: number)
	local function part(x, y, w, h, rot, round, c, a, zz)
		return frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			Rotation = rot,
			BackgroundColor3 = c or color,
			BackgroundTransparency = a or alpha,
			ZIndex = zz or z,
		}, parent, nil, round)
	end
	-- twig and a leaf on it
	part(32, 42, 54, 2, -4, 0.5)
	part(54, 38, 8, 3, -35, 0.5)
	-- legs
	part(29, 37, 1.5, 6, 10)
	part(33, 37, 1.5, 6, -4)
	-- tail: a long slim fan, down and back
	part(9, 32, 20, 3, 30, 0.5)
	part(10, 35, 17, 3, 42, 0.5)
	-- body: slim and tilted, a rounder breast at the front
	part(26, 26, 32, 13, -24, 0.5)
	part(33, 25, 16, 15, -10, 0.5)
	-- head, crown tuft, beak, eye
	local head = part(42, 15, 12, 11, 0, 0.5)
	part(39, 9.5, 5, 3, -30, 0.5)
	part(49, 16, 4, 4, 45, nil)
	part(44, 13.5, 2, 2, 0, 0.5, eyeColor, 0, z + 1)
	table.insert(heads, head)
	-- wing (flaps): pivots at its front edge, a shade darker than the body
	local wing = part(25, 22, 20, 7, -22, 0.5, wingColor, alpha, z + 1)
	wing.AnchorPoint = Vector2.new(0.85, 0.5)
	wing.Position = UDim2.fromOffset(34, 22)
	table.insert(wings, wing)
end

-- the dim copy is drawn solid inside a CanvasGroup and faded as one, so overlapping parts leave no seams
local dimGroup = make("CanvasGroup", {
	Name = "Dim",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	GroupTransparency = 0.8,
	ZIndex = 12,
}, birdBox)
reg(dimGroup, "GroupTransparency", 0.8)
drawBird(dimGroup, INK, 0, NIGHT, Color3.fromRGB(150, 147, 140), 12)
local fillClip = make("CanvasGroup", {
	Name = "Fill",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundTransparency = 1,
	ZIndex = 13,
}, birdBox)
reg(fillClip, "GroupTransparency", 0)
local fillInner = make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromOffset(BIRD_W, BIRD_H),
	BackgroundTransparency = 1,
	ZIndex = 13,
}, fillClip)
drawBird(fillInner, SUN, 0, Color3.fromRGB(40, 28, 14), Color3.fromRGB(176, 128, 52), 13)

---------------------------------------------------------------------------
-- ARENA 48
---------------------------------------------------------------------------
local TITLE = "ARENA 48"
local TITLE_SIZE = 118
local title = make("Frame", {
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(640, 128),
	BackgroundTransparency = 1,
	ZIndex = 14,
}, stack)

local function glyphWidth(ch: string): number
	if ch == " " then
		return TITLE_SIZE * 0.22
	end
	local ok, size = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = ch
		params.Font = TITLE_FONT
		params.Size = TITLE_SIZE
		params.Width = 1000
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok and size and size.X > 0 then
		return size.X
	end
	return TITLE_SIZE * 0.5
end

local letters: { { holder: Frame, scale: UIScale, group: number, at: number, shownAt: number?, face: TextLabel, grad: UIGradient } } = {}
local widths, total = {}, 0
local TRACK = 6 -- extra px between letters
for i = 1, #TITLE do
	local ch = string.sub(TITLE, i, i)
	widths[i] = glyphWidth(ch)
	total += widths[i] + (if i < #TITLE then TRACK else 0)
end

local visibleCount = 0
for i = 1, #TITLE do
	if string.sub(TITLE, i, i) ~= " " then
		visibleCount += 1
	end
end

local x = (640 - total) / 2
local n = 0
for i = 1, #TITLE do
	local ch = string.sub(TITLE, i, i)
	local w = widths[i]
	if ch ~= " " then
		n += 1
		local g = n
		groupAlpha[g] = 0
		local holder = make("Frame", {
			Name = "L" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + w / 2, 64),
			Size = UDim2.fromOffset(w + 16, 128),
			BackgroundTransparency = 1,
			ZIndex = 14,
		}, title)
		local sc = make("UIScale", { Scale = 1.25 }, holder)
		local function layer(dx: number, dy: number, color: Color3, alpha: number, z: number): TextLabel
			return label({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, dx, 0.5, dy),
				Size = UDim2.fromScale(1, 1),
				Text = ch,
				FontFace = TITLE_FONT,
				TextSize = TITLE_SIZE,
				TextColor3 = color,
				TextTransparency = alpha,
				ZIndex = z,
			}, holder, g)
		end
		-- soft drop shadow
		layer(7, 10, Color3.new(0, 0, 0), 0.45, 14)
		-- extrusion, far to near
		for k = 5, 1, -1 do
			local c = EXTRUDE_FAR:Lerp(EXTRUDE_NEAR, (5 - k) / 4)
			layer(k * 0.9, k * 1.2, c, 0, 15)
		end
		-- warm rim along the top edges (shows above the face)
		layer(-0.6, -1.6, RIM, 0.35, 16)
		-- the face: weathered rust running into moss
		local face = layer(0, 0, Color3.new(1, 1, 1), 0, 17)
		local rot = 90 + rng:NextNumber(-12, 12)
		local grad = make("UIGradient", {
			Rotation = rot,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, RUST_LIGHT),
				ColorSequenceKeypoint.new(0.22, RUST),
				ColorSequenceKeypoint.new(0.38, RUST_LIGHT:Lerp(RUST, 0.6)),
				ColorSequenceKeypoint.new(0.55, RUST_DARK),
				ColorSequenceKeypoint.new(0.72, BARK),
				ColorSequenceKeypoint.new(0.88, MOSS),
				ColorSequenceKeypoint.new(1, MOSS_DEEP),
			}),
			Offset = Vector2.new(0, rng:NextNumber(-0.06, 0.06)),
		}, face)
		local stroke = make("UIStroke", {
			Color = STROKE,
			Thickness = 1.4,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}, face)
		reg(stroke, "Transparency", 0, g)
		-- moss grime creeping up from the bottom, patchy
		local grime = layer(0, 0, MOSS_DEEP, 0, 18)
		local a = rng:NextNumber(0.62, 0.78)
		make("UIGradient", {
			Rotation = 90 + rng:NextNumber(-25, 25),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(a - 0.12, 1),
				NumberSequenceKeypoint.new(a, 0.55),
				NumberSequenceKeypoint.new(a + 0.08, 0.8),
				NumberSequenceKeypoint.new(math.min(0.97, a + 0.16), 0.35),
				NumberSequenceKeypoint.new(1, 0.25),
			}),
		}, grime)
		-- each letter's mark: spread over 0.06 .. 0.86 of the bar
		local at = 0.06 + (g - 1) * (0.8 / math.max(1, visibleCount - 1))
		table.insert(letters, { holder = holder, scale = sc, group = g, at = at, face = face, grad = grad })
	end
	x += w + TRACK
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local BAR_W = 380
local barBox = make("Frame", {
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 222),
	Size = UDim2.fromOffset(BAR_W, 40),
	BackgroundTransparency = 1,
	ZIndex = 20,
}, stack)
frame({ Name = "Track", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = INK, BackgroundTransparency = 0.86, ZIndex = 20 }, barBox, nil, 0.5)
local glowWide = frame({
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromOffset(0, 1),
	Size = UDim2.fromOffset(0, 18),
	BackgroundColor3 = SUN,
	BackgroundTransparency = 0.93,
	ZIndex = 21,
}, barBox, nil, 0.5)
local glow = frame({
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromOffset(0, 1),
	Size = UDim2.fromOffset(0, 7),
	BackgroundColor3 = SUN,
	BackgroundTransparency = 0.8,
	ZIndex = 22,
}, barBox, nil, 0.5)
local fill = frame({ Size = UDim2.fromOffset(0, 2), BackgroundColor3 = SUN, ZIndex = 23 }, barBox, nil, 0.5)
local headGlow = frame({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(0, 1),
	Size = UDim2.fromOffset(16, 16),
	BackgroundColor3 = SUN,
	BackgroundTransparency = 0.72,
	ZIndex = 24,
}, barBox, nil, 0.5)
local head = frame({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(0, 1),
	Size = UDim2.fromOffset(5, 5),
	BackgroundColor3 = Color3.fromRGB(255, 236, 196),
	ZIndex = 25,
}, barBox, nil, 0.5)

local statusLabel = label({
	Position = UDim2.fromOffset(0, 12),
	Size = UDim2.new(1, -60, 0, 16),
	Text = "CONNECTING",
	FontFace = SMALL_FONT,
	TextSize = 12,
	TextColor3 = INK,
	TextTransparency = 0.45,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 20,
}, barBox)
local pctLabel = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 11),
	Size = UDim2.fromOffset(60, 18),
	Text = "0%",
	FontFace = MONO_FONT,
	TextSize = 14,
	TextColor3 = INK,
	TextTransparency = 0.1,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 20,
}, barBox)

applyAlpha()
gui.Parent = playerGui

---------------------------------------------------------------------------
-- Loading state
---------------------------------------------------------------------------
local marks: { [string]: number } = {}
local function mark(name: string)
	if marks[name] == nil then
		marks[name] = math.floor((os.clock() - T0) * 100 + 0.5) / 100
	end
end

local peakQueue = 0
local lobbyStarted = false
local lobbyDone = false
local lobbyQueuePeak = 0

local function hasCharacter(): boolean
	local char = player.Character
	return char ~= nil and char:FindFirstChild("HumanoidRootPart") ~= nil
end

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	mark("loaded")
	-- the lobby first: the persistent train lobby and this player's GUI (copied in on spawn)
	local list = {}
	local lobby = workspace:FindFirstChild("Lobby") or workspace:WaitForChild("Lobby", 8)
	if lobby then
		table.insert(list, lobby)
	end
	local waited = 0
	while not hasCharacter() and os.clock() - T0 < CAP - 2 do
		waited += task.wait(0.1)
	end
	if hasCharacter() then
		mark("character")
	end
	for _, g in ipairs(playerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= gui then
			table.insert(list, g)
		end
	end
	lobbyStarted = true
	lobbyQueuePeak = math.max(1, ContentProvider.RequestQueueSize)
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	mark("lobby")
	lobbyDone = true
end)

local progress = 0 -- the target, never lower
local shown = 0 -- what the bar shows, eased toward progress
local function computeTarget(): number
	local t = os.clock() - T0
	local q = ContentProvider.RequestQueueSize
	peakQueue = math.max(peakQueue, q)
	local p
	if not game:IsLoaded() then
		local timeEase = 0.36 * (1 - math.exp(-t / 3.5))
		local queueBit = if peakQueue > 0 then 0.04 * (1 - q / peakQueue) else 0
		p = timeEase + queueBit
		statusLabel.Text = if t < 1.2 then "CONNECTING" else "LOADING THE WORLD"
	elseif not hasCharacter() then
		p = 0.4 + 0.1 * (1 - math.exp(-t / 4))
		statusLabel.Text = "BOARDING THE TRAIN"
	elseif not lobbyDone then
		lobbyQueuePeak = math.max(lobbyQueuePeak, q)
		local frac = if lobbyStarted then 1 - q / math.max(1, lobbyQueuePeak) else 0
		p = 0.55 + 0.38 * math.clamp(frac, 0, 1)
		statusLabel.Text = "LOADING THE LOBBY"
	else
		p = 1
		statusLabel.Text = "READY"
	end
	return p
end

---------------------------------------------------------------------------
-- Animation loop
---------------------------------------------------------------------------
local fullAt: number? = nil
local fading = false
local finished = false
local capped = false
local flapUntil = 0
local nextFlap = 1.4
local lastPct = -1

local function setBar(p: number)
	local w = math.floor(BAR_W * p + 0.5)
	fill.Size = UDim2.fromOffset(w, 2)
	glow.Size = UDim2.fromOffset(w, 7)
	glowWide.Size = UDim2.fromOffset(w, 18)
	head.Position = UDim2.fromOffset(w, 1)
	headGlow.Position = UDim2.fromOffset(w, 1)
	fillClip.Size = UDim2.new(1, 0, 0, math.max(1, math.floor(BIRD_H * (0.08 + 0.92 * p))))
	local pct = math.floor(p * 100 + 0.0001)
	if pct ~= lastPct then
		lastPct = pct
		pctLabel.Text = tostring(pct) .. "%"
	end
end

-- Studio only, for captures: Workspace attribute LoadScreenPreview (a number 0..1) holds the screen at that progress
-- and keeps it up; set it on the client to move it. Never read in a live game.
local IS_STUDIO = RunService:IsStudio()

local conn
conn = RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local t = now - T0
	local preview = if IS_STUDIO then workspace:GetAttribute("LoadScreenPreview") else nil
	if type(preview) == "number" then
		progress = math.clamp(preview, 0, 1)
		shown = progress
		T0 = math.min(T0, now - MIN_SHOW) -- (lets maxShown pass)
		t = now - T0
		statusLabel.Text = if progress < 0.4 then "LOADING THE WORLD" elseif progress < 0.55 then "BOARDING THE TRAIN" elseif progress < 1 then "LOADING THE LOBBY" else "READY"
		fullAt = nil
	elseif not fading then
		progress = math.max(progress, computeTarget())
		if t >= CAP and progress < 1 then
			capped = true
			progress = 1
			statusLabel.Text = "READY"
		end
	end
	-- the shown value eases toward the target; held back a little early on so the letters keep pace on fast loads
	local maxShown = math.clamp(t / MIN_SHOW, 0, 1)
	local goal = math.min(progress, maxShown)
	shown += (goal - shown) * math.min(1, dt * 5)
	if goal - shown < 0.002 then
		shown = goal
	end
	setBar(shown)

	-- letters
	for _, L in ipairs(letters) do
		if not L.shownAt and shown >= L.at then
			L.shownAt = now
		end
		if L.shownAt then
			local k = math.clamp((now - L.shownAt) / 0.42, 0, 1)
			local ease = 1 - (1 - k) ^ 3
			if groupAlpha[L.group] ~= ease then
				groupAlpha[L.group] = ease
				dirty = true
			end
			-- settle from a little large, with a small overshoot
			local over = math.sin(k * math.pi) * 0.04
			L.scale.Scale = 1.25 - 0.25 * ease - over
		end
		-- slow rust shimmer
		L.grad.Offset = Vector2.new(0, math.sin(t * 0.6 + L.group) * 0.03)
	end

	-- bird: idle bob, a flap now and then
	if t >= nextFlap then
		flapUntil = t + 0.45
		nextFlap = t + 1.6 + rng:NextNumber(0, 1.4)
	end
	local flap = if t < flapUntil then math.sin((flapUntil - t) / 0.45 * math.pi * 3) * 28 else 0
	for _, wng in ipairs(wings) do
		wng.Rotation = -18 - math.abs(flap)
	end
	local bob = math.sin(t * 2.2) * 0.6
	for _, h in ipairs(heads) do
		h.Position = UDim2.fromOffset(42, 15 + bob)
	end
	headGlow.BackgroundTransparency = 1 - (1 - (0.72 + math.sin(t * 5) * 0.08)) * screenAlpha

	-- motes
	for _, m in ipairs(motes) do
		m.y -= m.v * dt
		if m.y < -0.02 then
			m.y = 1.02
			m.x = rng:NextNumber()
		end
		m.f.Position = UDim2.fromScale(m.x + math.sin(t * 0.5 + m.p) * 0.01, m.y)
	end

	-- done: hold, then fade
	if progress >= 1 and shown >= 0.999 and not fullAt then
		fullAt = now
		flapUntil = t + 0.6
		mark("full")
	end
	if fullAt and not fading and now - fullAt >= HOLD_AT_FULL then
		fading = true
		local start = now
		task.spawn(function()
			while true do
				local k = math.clamp((os.clock() - start) / FADE, 0, 1)
				screenAlpha = 1 - (k * k * (3 - 2 * k))
				birdScale.Scale = BIRD_SCALE * (1 + k * 0.08)
				dirty = true
				if k >= 1 then
					break
				end
				task.wait()
			end
			finished = true
		end)
	end
	if dirty then
		applyAlpha()
	end
	if finished then
		conn:Disconnect()
		mark("done")
		gui:Destroy()
		player:SetAttribute("LoadingScreenUp", false)
		local report = {
			loaded = marks.loaded,
			character = marks.character,
			lobby = marks.lobby,
			full = marks.full,
			done = marks.done,
			peakQueue = peakQueue,
			capped = capped,
		}
		local ok, json = pcall(HttpService.JSONEncode, HttpService, report)
		if ok then
			player:SetAttribute("LoadScreen", json)
		end
		print(string.format(
			"[LoadingScreen] loaded %.2f s, character %s, lobby %s, gone %.2f s, queue peak %d%s",
			marks.loaded or -1,
			if marks.character then string.format("%.2f s", marks.character) else "-",
			if marks.lobby then string.format("%.2f s", marks.lobby) else "-",
			marks.done or -1,
			peakQueue,
			if capped then " (cap)" else ""
		))
	end
end)

local cam = workspace.CurrentCamera
if cam then
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

---------------------------------------------------------------------------
-- After the screen: the rest of the load order (low priority, small batches)
---------------------------------------------------------------------------
local function preloadChildren(folder: Instance?, batch: number)
	if not folder then
		return 0
	end
	local kids = folder:GetChildren()
	local count = 0
	for i = 1, #kids, batch do
		local list = {}
		for j = i, math.min(i + batch - 1, #kids) do
			table.insert(list, kids[j])
		end
		-- yield to whatever the game itself is asking for first
		local spins = 0
		while ContentProvider.RequestQueueSize > 24 and spins < 40 do
			spins += 1
			task.wait(0.25)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		count += #list
		task.wait(0.1)
	end
	return count
end

task.spawn(function()
	-- wait for the screen to finish
	while not finished and os.clock() - T0 < CAP + 5 do
		task.wait(0.25)
	end
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local assets = ReplicatedStorage:WaitForChild("Assets", 20)
	if not assets then
		return
	end
	-- the first-person arms are used in the lobby too: soon after the screen
	task.wait(4)
	preloadChildren(assets:FindFirstChild("Viewmodel"), 6)

	-- the arena's items, crates and creatures: on the ride
	local gameState = ReplicatedStorage:WaitForChild("GameState", 20)
	local started = os.clock()
	local function shouldGo(): boolean
		if os.clock() - started > 90 then
			return true
		end
		if player:GetAttribute("InArena") == true then
			return true
		end
		if gameState then
			local stage = gameState:GetAttribute("TrainStage")
			if stage == "Ride" or stage == "Training" then
				return true
			end
			local phase = gameState:GetAttribute("Phase")
			if phase ~= nil and phase ~= "Lobby" and phase ~= "Intermission" and phase ~= "Waiting" then
				return true
			end
		end
		return false
	end
	while not shouldGo() do
		task.wait(0.5)
	end
	local t = os.clock()
	local n = preloadChildren(assets:FindFirstChild("Items"), 8)
	n += preloadChildren(assets:FindFirstChild("Crates"), 8)
	n += preloadChildren(assets:FindFirstChild("Creatures"), 8)
	player:SetAttribute("ArenaPreload", string.format("%d in %.1f s", n, os.clock() - t))
end)
