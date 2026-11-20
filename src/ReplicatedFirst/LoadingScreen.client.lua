--[[
	LoadingScreen (ReplicatedFirst, client) - the first thing a player sees after pressing Play.

	Wave 24 remake (owner: the wave 20 screen was "so ugly"; their reference is a black screen with a glowing blue
	segmented bar). What it draws, all plain GuiObjects (nothing is uploaded):
	  * A fully opaque near-black screen. Nothing of the game shows through until the final fade.
	  * A bar of CELLS separate rounded cells. Unlit cells are thin dim blue outlines; lit cells are a white-blue core
	    with a bright blue edge. The cell being filled brightens in proportion, so the bar fills cell by cell, smoothly.
	  * A soft blue glow under the lit part of the bar (stacked rounded bands, faintest widest), plus a faint glow along
	    the whole bar.
	  * "Loading" with four animated dots above the bar's left end, the percentage large above its right end, both
	    white-blue with a blue glow. A small wide-tracked ARENA 48 wordmark above, a quiet status line below.
	  * Every size is computed in whole pixels from the viewport (no UIScale), so the cells stay crisp and evenly
	    spaced from a phone to 4K.

	Progress (never goes backwards)
	  0.00 - 0.40  before game:IsLoaded(): eases toward 0.40 with time, nudged by ContentProvider.RequestQueueSize
	  0.40 - 0.55  the character is in the world
	  0.55 - 0.95  the train lobby's content (Workspace.Lobby and the PlayerGui) preloaded first, measured by the
	               request queue draining from its peak
	  1.00         all of that done (or the cap reached)
	  Hard cap: the screen fades out CAP seconds after it appeared, whatever is still loading. Minimum MIN_SHOW so a
	  fast load still reads as a smooth fill rather than a flash.

	Load order (what this script asks for, in order)
	  1. the lobby: Workspace.Lobby (Persistent) and the player's own GUI, during the screen
	  2. after the screen: ReplicatedStorage.Assets.Viewmodel (first-person arms), a few seconds later
	  3. on the ride (GameState.TrainStage "Ride", or 90 s after joining, or at once if this player joins into a
	     running round): ReplicatedStorage.Assets Items, Crates, Creatures, in small batches
	  The AudioController preloads short sounds after the first screen; music beds are streamed, never preloaded.

	Measurements: LocalPlayer attribute LoadScreen (JSON: seconds since this script began for loaded, character,
	lobby, done, the request queue's peak, whether the cap fired) and one [LoadingScreen] line in the output.
	LocalPlayer attribute LoadingScreenUp is true while the screen is up.
	Studio only: Workspace attribute LoadScreenPreview (a number 0..1) holds the screen at that progress, for captures.
]]
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local T0 = os.clock()
local CAP = 25 -- seconds: never hold anyone longer than this
local MIN_SHOW = 3.2 -- seconds: the bar takes at least this long to fill
local HOLD_AT_FULL = 0.35 -- seconds at 100 % before the fade
local FADE = 0.6

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
player:SetAttribute("LoadingScreenUp", true)

---------------------------------------------------------------------------
-- Palette and fonts
---------------------------------------------------------------------------
local BLACK = Color3.fromRGB(3, 4, 7)
local CORE = Color3.fromRGB(226, 242, 255) -- lit cell core, text
local EDGE = Color3.fromRGB(70, 172, 255) -- lit cell edge, text glow
local GLOW = Color3.fromRGB(38, 132, 255) -- the soft glow
local DIM = Color3.fromRGB(44, 110, 190) -- unlit cell outline
local QUIET = Color3.fromRGB(140, 172, 214) -- status line

local BOLD = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local THIN = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Light, Enum.FontStyle.Normal)
local SMALL = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)

local CELLS = 40

---------------------------------------------------------------------------
-- Fading: every static drawn property is registered with its full-strength value; shown = base faded by screenAlpha.
-- The lit cells are set every frame instead (their strength depends on progress too).
---------------------------------------------------------------------------
local registry: { { inst: Instance, prop: string, base: number } } = {}
local screenAlpha = 1
local dirty = true

local function reg(inst: Instance, prop: string, base: number)
	table.insert(registry, { inst = inst, prop = prop, base = base })
end

local function fadeOf(base: number): number
	return 1 - (1 - base) * screenAlpha
end

local function applyAlpha()
	for _, r in ipairs(registry) do
		(r.inst :: any)[r.prop] = fadeOf(r.base)
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

local function frame(props: { [string]: any }, parent: Instance): Frame
	props.BorderSizePixel = 0
	local f = make("Frame", props, parent)
	reg(f, "BackgroundTransparency", props.BackgroundTransparency or 0)
	return f
end

local function stroke(parent: Instance, color: Color3, transparency: number, mode: Enum.ApplyStrokeMode?): UIStroke
	local s = make("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = 1,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
	reg(s, "Transparency", transparency)
	return s
end

-- a text with a blue glow: a soft wide halo label behind, and the crisp label with a thin blue edge on top
local function glowText(name: string, font: Font, xAlign: Enum.TextXAlignment, anchor: Vector2, parent: Instance, edgeAlpha: number?)
	local function one(z: number, textAlpha: number, strokeAlpha: number)
		local l = make("TextLabel", {
			Name = name,
			AnchorPoint = anchor,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			FontFace = font,
			RichText = true,
			Text = "",
			TextColor3 = CORE,
			TextTransparency = textAlpha,
			TextXAlignment = xAlign,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			ZIndex = z,
		}, parent)
		reg(l, "TextTransparency", textAlpha)
		return l, stroke(l, EDGE, strokeAlpha)
	end
	local halo, haloStroke = one(30, 0.6, 0.92)
	local top, topStroke = one(31, 0, edgeAlpha or 0.45)
	haloStroke.Color = GLOW
	return { halo = halo, haloStroke = haloStroke, top = top, topStroke = topStroke }
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

-- fully opaque: oversized a little so no edge of the game can show at any aspect or inset
frame({
	Name = "Black",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 80, 1, 80),
	BackgroundColor3 = BLACK,
	ZIndex = 1,
}, gui)

-- everything is placed in whole pixels around the bar's own box, which sits centred on the screen
local bar = make("Frame", {
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 10,
}, gui)

-- the glow: many faint rounded bands stacked, so their overlap falls off smoothly. "Lit" bands follow the filled
-- width; a few fainter ones span the whole bar so the unlit cells sit in a dim haze too
local GLOW_LAYERS = 11
local litBands: { { f: Frame, pad: number, corner: UICorner } } = {}
for i = 1, GLOW_LAYERS do
	local f = frame({
		Name = "Glow" .. i,
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = GLOW,
		BackgroundTransparency = 0.95,
		ZIndex = 11,
	}, bar)
	local c = make("UICorner", {}, f)
	table.insert(litBands, { f = f, pad = 1.2 * i ^ 1.3, corner = c })
end
local wholeBands: { { f: Frame, pad: number, corner: UICorner } } = {}
for i = 1, 4 do
	local f = frame({
		Name = "GlowWhole" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = GLOW,
		BackgroundTransparency = 0.985,
		ZIndex = 11,
	}, bar)
	local c = make("UICorner", {}, f)
	table.insert(wholeBands, { f = f, pad = 4 + i * 5, corner = c })
end

-- the cells: an outline that is always there, and a lit core over it whose strength is set every frame
local cells: { { box: Frame, outline: UIStroke, oc: UICorner, ic: UICorner, core: Frame, coreStroke: UIStroke, cc: UICorner } } = {}
for i = 1, CELLS do
	local box = make("Frame", { Name = "Cell" .. i, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 12 }, bar)
	local outline = make("UIStroke", {
		Color = DIM,
		Transparency = 0.35,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, box)
	reg(outline, "Transparency", 0.35)
	local inner = make("Frame", { -- the unlit cell's faint fill
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = DIM,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 12,
	}, box)
	reg(inner, "BackgroundTransparency", 0.9)
	local oc = make("UICorner", {}, box)
	local ic = make("UICorner", {}, inner)
	local core = make("Frame", {
		Name = "Lit",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = CORE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 13,
	}, box)
	local coreStroke = make("UIStroke", {
		Color = EDGE,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, core)
	local cc = make("UICorner", {}, core)
	table.insert(cells, { box = box, outline = outline, oc = oc, ic = ic, core = core, coreStroke = coreStroke, cc = cc })
end

local loadingText = glowText("Loading", BOLD, Enum.TextXAlignment.Left, Vector2.new(0, 1), bar)
local pctText = glowText("Percent", BOLD, Enum.TextXAlignment.Right, Vector2.new(1, 1), bar)
local wordmark = glowText("Wordmark", THIN, Enum.TextXAlignment.Center, Vector2.new(0.5, 1), bar, 0.75)
local WORDMARK = "A R E N A   4 8"
wordmark.halo.Text = WORDMARK
wordmark.top.Text = WORDMARK
wordmark.halo.TextColor3 = Color3.fromRGB(250, 252, 255)
wordmark.top.TextColor3 = Color3.fromRGB(250, 252, 255)

local statusLabel = make("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	FontFace = SMALL,
	Text = "Connecting",
	TextColor3 = QUIET,
	TextTransparency = 0.45,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 30,
}, bar)
reg(statusLabel, "TextTransparency", 0.45)

---------------------------------------------------------------------------
-- Layout, in whole pixels from the viewport
---------------------------------------------------------------------------
local L = { pitch = 18, cw = 10, ch = 30, barW = 712, s = 1 }

local function px(v: number, min: number?): number
	return math.max(min or 1, math.floor(v + 0.5))
end

local function setTextGeometry(t, size: number, pos: UDim2, w: number, strokeTop: number, strokeHalo: number)
	for _, l in ipairs({ t.halo, t.top }) do
		l.TextSize = size
		l.Position = pos
		l.Size = UDim2.fromOffset(w, math.floor(size * 1.25 + 0.5))
	end
	t.topStroke.Thickness = strokeTop
	t.haloStroke.Thickness = strokeHalo
end

local function layout()
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	if vp.X < 2 or vp.Y < 2 then
		vp = Vector2.new(1280, 720)
	end
	-- the bar takes about 60 % of a wide screen, up to 88 % of a narrow one, and never too much of a short one
	local want = math.max(vp.X * 0.6, math.min(vp.X * 0.88, 520))
	local s = math.clamp(math.min(want / 712, vp.Y / 420), 0.3, 6)
	local pitch = px(18 * s, 4)
	local cw = math.clamp(px(pitch * 0.56, 2), 2, pitch - 1)
	local ch = px(30 * s, 8)
	local barW = pitch * CELLS - (pitch - cw)
	L.pitch, L.cw, L.ch, L.barW, L.s = pitch, cw, ch, barW, s

	bar.Size = UDim2.fromOffset(barW, ch)
	bar.Position = UDim2.new(0.5, 0, 0.5, px(14 * s, 0))

	local r = UDim.new(0, math.max(1, math.floor(cw * 0.3)))
	local outlineT = math.max(1, math.floor(1.1 * s + 0.5))
	local coreT = math.max(1, math.floor(1.6 * s + 0.5))
	for i, c in ipairs(cells) do
		c.box.Position = UDim2.fromOffset((i - 1) * pitch, 0)
		c.box.Size = UDim2.fromOffset(cw, ch)
		c.oc.CornerRadius = r
		c.cc.CornerRadius = r
		c.ic.CornerRadius = r
		c.outline.Thickness = outlineT
		c.coreStroke.Thickness = coreT
	end
	for _, b in ipairs(litBands) do
		local p = px(b.pad * s, 1)
		b.f.Position = UDim2.new(0, -p, 0.5, 0)
		b.f.Size = UDim2.fromOffset(2 * p, ch + 2 * p)
		b.corner.CornerRadius = UDim.new(0, p + math.floor(cw * 0.3))
	end
	for _, b in ipairs(wholeBands) do
		local p = px(b.pad * s, 1)
		b.f.Size = UDim2.fromOffset(barW + 2 * p, ch + 2 * p)
		b.corner.CornerRadius = UDim.new(0, p + math.floor(cw * 0.3))
	end

	local gap = px(9 * s, 2)
	local smallSize = px(24 * s, 10)
	local bigSize = px(38 * s, 14)
	local half = math.floor(barW / 2)
	setTextGeometry(loadingText, smallSize, UDim2.fromOffset(0, -gap), half, math.max(1, math.floor(1.2 * s + 0.5)), px(5 * s, 2))
	setTextGeometry(pctText, bigSize, UDim2.new(1, 0, 0, -gap + px(2 * s, 0)), half, math.max(1, math.floor(1.4 * s + 0.5)), px(6 * s, 2))
	local markSize = px(17 * s, 9)
	setTextGeometry(wordmark, markSize, UDim2.new(0.5, 0, 0, -px(120 * s, 30)), barW, 1, px(4 * s, 2))
	statusLabel.TextSize = px(13 * s, 9)
	statusLabel.Position = UDim2.new(0.5, 0, 1, px(20 * s, 6))
	statusLabel.Size = UDim2.fromOffset(barW, px(18 * s, 12))
	dirty = true
end
layout()

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
		statusLabel.Text = if t < 1.2 then "Connecting" else "Loading the world"
	elseif not hasCharacter() then
		p = 0.4 + 0.1 * (1 - math.exp(-t / 4))
		statusLabel.Text = "Boarding the train"
	elseif not lobbyDone then
		lobbyQueuePeak = math.max(lobbyQueuePeak, q)
		local frac = if lobbyStarted then 1 - q / math.max(1, lobbyQueuePeak) else 0
		p = 0.55 + 0.38 * math.clamp(frac, 0, 1)
		statusLabel.Text = "Loading the lobby"
	else
		p = 1
		statusLabel.Text = "Loading the lobby" -- "Ready" only once the bar itself is full (see the loop)
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
local lastPct = -1
local lastDots = -1
local lastLitW = -1

local function setBar(p: number)
	-- cells: each one lights over its own 1/CELLS of the progress, so the bar fills cell by cell without a jump
	local f = p * CELLS
	for i, c in ipairs(cells) do
		local k = math.clamp(f - (i - 1), 0, 1)
		k = k * k * (3 - 2 * k)
		c.core.BackgroundTransparency = 1 - k * screenAlpha
		c.coreStroke.Transparency = 1 - k * screenAlpha
	end
	-- the glow follows the filled width, ending at the edge of the cell being lit
	local litW = 0
	if f > 0 then
		local whole = math.floor(f)
		litW = whole * L.pitch - (if whole > 0 then L.pitch - L.cw else 0)
		local part = f - whole
		if part > 0 then
			litW = (if whole > 0 then litW + (L.pitch - L.cw) else 0) + L.cw * part
		end
		litW = math.floor(litW + 0.5)
	end
	if litW ~= lastLitW then
		lastLitW = litW
		for _, b in ipairs(litBands) do
			local h = b.f.Size.Y.Offset
			local p2 = -b.f.Position.X.Offset * 2
			b.f.Size = UDim2.fromOffset(if litW > 0 then litW + p2 else 0, h)
		end
	end
	local pct = math.floor(p * 100 + 0.0001)
	if pct ~= lastPct then
		lastPct = pct
		pctText.halo.Text = tostring(pct) .. "%"
		pctText.top.Text = pctText.halo.Text
	end
end

local function setDots(t: number)
	-- four dots; the lit run grows 1..4 and starts over, the rest stay dim
	local n = if lastPct >= 100 then 4 else 1 + math.floor(t * 2.6) % 4
	if n == lastDots then
		return
	end
	lastDots = n
	local s = "Loading"
	for i = 1, 4 do
		s ..= if i <= n then "." else '<font transparency="0.72">.</font>'
	end
	loadingText.halo.Text = s
	loadingText.top.Text = s
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
		statusLabel.Text = if progress < 0.4 then "Loading the world" elseif progress < 0.55 then "Boarding the train" elseif progress < 1 then "Loading the lobby" else "Ready"
		fullAt = nil
	elseif not fading then
		progress = math.max(progress, computeTarget())
		if t >= CAP and progress < 1 then
			capped = true
			progress = 1
		end
	end
	-- the shown value eases toward the target (never past it, never back); held back early on so a fast load still
	-- fills smoothly instead of jumping
	local maxShown = math.clamp(t / MIN_SHOW, 0, 1)
	local goal = math.min(progress, maxShown)
	if goal > shown then
		shown += (goal - shown) * math.min(1, dt * 5)
		if goal - shown < 0.002 then
			shown = goal
		end
	end
	setBar(shown)
	if shown >= 0.995 and statusLabel.Text ~= "Ready" then
		statusLabel.Text = "Ready" -- the status says Ready only when the bar shows 100 %, never at 60 %
	end
	setDots(t)

	-- done: hold, then fade
	if progress >= 1 and shown >= 0.999 and not fullAt then
		fullAt = now
		mark("full")
	end
	if fullAt and not fading and now - fullAt >= HOLD_AT_FULL then
		fading = true
		local start = now
		task.spawn(function()
			while true do
				local k = math.clamp((os.clock() - start) / FADE, 0, 1)
				screenAlpha = 1 - (k * k * (3 - 2 * k))
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
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		layout()
		lastLitW = -1
	end)
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
