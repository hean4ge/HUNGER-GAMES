--[[
	FallenRecapController - "The Fallen": each dusk's Roll Call, shown in the sky as a 3D point cloud.
	Thousands of small glowing points start as drifting TV static (jitter, flicker, crackle), then stream together into
	one piece: the day caption ("DUSK · DAY ONE" over "4 FELL TODAY"), then each contender who fell that day as a
	point-cloud bust of their avatar with their name in point letters beneath, then all of the day's fallen together in
	one composition, then the day caption again; then it dissolves back to static and fades. If nobody fell: the caption
	alone, reading "NO ONE FELL TODAY". No emblem frames the fallen.

	Sync: ArenaService publishes the show in GameState "RollCall" (JSON: entries, day, startAt = server time). Every
	client runs the same timeline (Shared.DayCycle.recapTimeline) from startAt, so late joiners join mid-way.
	Busts: ArenaService snapshots each fallen avatar into ReplicatedStorage.FallenSnapshots; this controller turns each
	snapshot into a coloured point cloud as soon as it appears (Shapes.sampleBust, spread over frames), long before dusk.
	Display: anchored, non-colliding, non-queryable Neon parts moved with workspace:BulkMoveTo every frame. It hangs in
	the sky at a fixed world bearing (toward the arena centre, or where you were looking when you are near it), ~22 degrees
	up, always facing your camera at a constant apparent size, so it reads from anywhere. It turns gently to show depth.
	Under trees it climbs (each client on its own, from 25 up to 57 degrees) to where the canopy leaves it clear, and
	glides back down in the open (LIFT_*).
	The point count scales with device and graphics quality and backs off if the frame rate drops. No input is locked.
	Sound (Shared.Sounds): static hiss and crackle while it is noise, and a low tone that swells in as each piece
	assembles and resolves as it locks. Never music: no anthem and no music bed. Whatever music was playing (tension,
	the final stand) fades out as the static comes up and stays off for the whole show (AudioController.setMusicSuppressed);
	ambience dips.
	Cost: a held piece's points only move when the stage moves (your camera moved, or the slow turn stepped on), so a
	still viewer pays almost nothing between assemblies.

	API:
	  FallenRecapController.isShowing() -> boolean
	  FallenRecapController.getBearing() -> number?     degrees clockwise from north where the display hangs (while showing)
	  FallenRecapController.showChanged: Signal(showing: boolean, payload?)
	Studio only: GameState:SetAttribute("DevRecapFreeze", seconds) holds a running show at that moment of its timeline
	(screenshots); nil lets it run on. Fake fallen: ArenaService's "DevRollCall".
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayCycle = require(Shared:WaitForChild("DayCycle"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local Signal = require(Shared:WaitForChild("Signal"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))

local Shapes = require(script:WaitForChild("Shapes"))

local GameState = ReplicatedStorage:WaitForChild("GameState")

local FallenRecapController = {}
FallenRecapController.showChanged = Signal.new()

-- Stage ------------------------------------------------------------------------------------------------------------
local STAGE_DISTANCE = 170 -- studs from the camera (it moves with the camera: reads like it is far away in the sky)
local UNIT = STAGE_DISTANCE / 270 -- studs per stage unit (1 unit looks like 1 stud seen from 270 studs away): the static
-- screen spans ~58 degrees of sky, a bust ~19 degrees, the names ~2.8 degrees per letter
local ELEVATION = math.rad(25) -- centre of the display above the horizon (clear of most of the treeline)
-- Under trees the display climbs to the lowest of these elevations that the canopy leaves clear (or the least hidden
-- one), so it shows through the gaps overhead, and glides back down in the open. Measured from the forest floor in a
-- temporary stand of 155 of the real tree meshes at 20-stud spacing, crowns counted as volumes: on average 90 % of the
-- display hidden at 25 deg, 73 % at 41, 58 % at 57, and ~48 % at the best elevation for each spot. Trunks and terrain
-- alone: 30 % at 25 deg, 15 % with the lift. A dense stand hides much of the sky whatever we do: the 2D list and the
-- "look up" hint carry the names there.
local LIFT_ELEVATIONS = { math.rad(25), math.rad(33), math.rad(41), math.rad(49), math.rad(57) }
local LIFT_CLEAR = 0.12 -- a placement with at most this share of the display hidden is clear enough
local LIFT_CHECK = 0.5 -- seconds between occlusion checks (sooner once the camera has moved a few studs)
local LIFT_RATE = 1.4 -- glide speed toward a new elevation (1/s)
local NEAR_CENTRE = 170 -- closer than this to the arena centre: the display goes where you were looking
local POINT_UNITS = 1.15 -- point size (stage units)
local STATIC_W, STATIC_H, STATIC_D = 300, 176, 16 -- the static "screen" volume (stage units)
local HIDDEN = CFrame.new(1e5, 1e5, 1e5)

local STATIC_COLORS = {
	Color3.fromRGB(236, 240, 248),
	Color3.fromRGB(196, 204, 220),
	Color3.fromRGB(160, 170, 190),
	Color3.fromRGB(214, 220, 234),
	Color3.fromRGB(128, 138, 160),
}
local NAME_COLOR = Color3.fromRGB(255, 244, 228)
local CAPTION_COLOR = Color3.fromRGB(240, 226, 202)
local RULE_COLOR = Color3.fromRGB(200, 188, 168)
local COLOR_WRITES_PER_FRAME = 420

-- State --------------------------------------------------------------------------------------------------------------
local Controllers: any = nil
local folder: Folder? = nil
local pool: { BasePart } = {}
local poolTarget = 0 -- parts wanted
local activeCount = 0 -- parts in use this show (adaptive)
local cfs: { CFrame } = {}
local parked: { boolean } = {} -- point i is out of sight (no need to move it again)
local moveParts: { BasePart } = {} -- this frame's BulkMoveTo list (only the points that need moving)
local moveCfs: { CFrame } = {}
local moveCount = 0

-- per-point arrays (struct of arrays)
local ax, ay, az = {}, {}, {} -- from
local bx, by, bz = {}, {}, {} -- to
local sxp, syp, szp = {}, {}, {} -- static scatter used by breaks
local seed, delayF, curlX, curlY, curlZ = {}, {}, {}, {}, {}
local hopRate, hopPhase, lastHop, stx, sty, stz, stv = {}, {}, {}, {}, {}, {}, {}
local wantColor, curColor = {}, {}
local inShape = {} -- point i belongs to the current segment's shape
local prevInShape = {}

local clouds = {} -- [snapshotName] = cloud
local sampling = {} -- [snapshotName] = true while queued/sampling
local queue = {}
local workerBusy = false

local show = nil -- the running show
local lastShowId = nil
local frameEma = 1 / 60
local slowFor = 0

local rng = Random.new()
local diag = { loop = 0, bulk = 0, color = 0 } -- Studio: per-frame cost breakdown (ms, smoothed)

local function warnf(...)
	warn("[FallenRecap] " .. string.format(...))
end

-- Pool ---------------------------------------------------------------------------------------------------------------

local function desiredPoolSize(): number
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local console = GuiService:IsTenFootInterface()
	local n = if touch then 1500 elseif console then 2400 else 3600
	local q = 0
	pcall(function()
		q = UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if q >= 1 and q <= 3 then
		n = math.floor(n * 0.55)
	elseif q >= 4 and q <= 6 then
		n = math.floor(n * 0.8)
	end
	return n
end

local function initPointState(i: number)
	seed[i] = rng:NextNumber()
	delayF[i] = rng:NextNumber()
	local cx, cy, cz = rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.6)
	curlX[i], curlY[i], curlZ[i] = cx, cy, cz
	hopRate[i] = rng:NextNumber(5, 15)
	hopPhase[i] = rng:NextNumber()
	lastHop[i] = -1
	stx[i], sty[i], stz[i], stv[i] = 0, 0, 0, false
	ax[i], ay[i], az[i] = 0, 0, 0
	bx[i], by[i], bz[i] = 0, 0, 0
	sxp[i], syp[i], szp[i] = 0, 0, 0
	inShape[i], prevInShape[i] = false, false
	wantColor[i] = STATIC_COLORS[(i % #STATIC_COLORS) + 1]
	curColor[i] = nil
	cfs[i] = HIDDEN
	parked[i] = true
end

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "FallenRecap"
	f.Parent = workspace
	folder = f
	return f
end

-- Grow the pool toward poolTarget, a few hundred parts per frame (no hitch).
local function growPool(maxPerFrame: number)
	local f = ensureFolder()
	local size = Vector3.one * (POINT_UNITS * UNIT)
	local made = 0
	while #pool < poolTarget and made < maxPerFrame do
		local i = #pool + 1
		local p = Instance.new("Part")
		p.Name = "P"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Locked = true
		p.Material = Enum.Material.Neon
		p.Size = size
		p.CFrame = HIDDEN
		initPointState(i)
		p.Color = wantColor[i]
		curColor[i] = wantColor[i]
		p.Parent = f
		pool[i] = p
		made += 1
	end
	return #pool >= poolTarget
end

local function parkAll()
	for i = 1, #pool do
		cfs[i] = HIDDEN
		parked[i] = true
	end
	if #pool > 0 then
		workspace:BulkMoveTo(pool, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Hash noise (stateless: the same on every client for a given point and hop) -----------------------------------------

local function h1(a: number, b: number): number
	local s = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return s - math.floor(s)
end
local function h2(a: number, b: number): number
	local s = math.sin(a * 39.3468 + b * 11.135) * 24634.6345
	return s - math.floor(s)
end
local function h3(a: number, b: number): number
	local s = math.sin(a * 73.156 + b * 52.235) * 15731.7431
	return s - math.floor(s)
end
local function h4(a: number, b: number): number
	local s = math.sin(a * 27.619 + b * 91.733) * 35412.9183
	return s - math.floor(s)
end

-- Static noise position of point i at show time t (cached per hop).
local function staticAt(i: number, t: number, spread: number)
	local hop = math.floor(t * hopRate[i] + hopPhase[i])
	if hop ~= lastHop[i] then
		lastHop[i] = hop
		stx[i] = (h1(i, hop) - 0.5) * STATIC_W
		sty[i] = (h2(i, hop) - 0.5) * STATIC_H
		stz[i] = (h3(i, hop) - 0.5) * STATIC_D
		stv[i] = h4(i, hop) < 0.74
	end
	return stx[i] * spread, sty[i] * spread, stz[i], stv[i]
end

-- Shapes for the show -------------------------------------------------------------------------------------------------

local EMPTY = Shapes.newCloud()

-- Never yields (this runs inside the render step): a shape that isn't sampled yet is asked for and stands in empty.
local function cloudFor(entry): any
	local name = entry and entry.snapshot
	if type(name) == "string" and clouds[name] then
		return clouds[name], true
	end
	local mannequin = Shapes.cachedMannequin()
	if not mannequin then
		task.spawn(Shapes.mannequin)
		return EMPTY, false
	end
	return mannequin, false
end

local function textCloud(text: string, cap: number, maxPts: number, color: Color3)
	return Shapes.text(string.upper(text), cap, 0.55, color, maxPts)
end

-- Shift a cloud so its vertical extent is centred on `y`.
local function recentre(cloud, y: number)
	if cloud.n == 0 then
		return cloud
	end
	local _, _, minY, maxY = Shapes.bounds(cloud)
	local dy = y - (minY + maxY) / 2
	local ys = cloud.y
	for i = 1, cloud.n do
		ys[i] += dy
	end
	return cloud
end

-- One fallen contender: bust over their name.
local function personShape(entry, budget: number)
	local bust = cloudFor(entry)
	local name = tostring(entry.name or "")
	local nameCap = 13
	local text = textCloud(name, nameCap, math.floor(budget * 0.3), NAME_COLOR)
	if text.width > 230 then
		-- long names: shrink to fit the display
		nameCap = math.max(7.5, nameCap * 230 / text.width)
		text = textCloud(name, nameCap, math.floor(budget * 0.3), NAME_COLOR)
	end
	local bustTake = math.min(bust.n, budget - text.n)
	local bottom = bust.bottom or -38
	return recentre(Shapes.compose({
		{ cloud = bust, take = bustTake },
		{ cloud = text, y = bottom - 10 - nameCap / 2 },
	}), 6)
end

-- Everyone who fell today, together (nothing framing them: the day caption follows on its own).
local function finaleShape(entries, budget: number)
	local count = #entries
	local cols = if count <= 6 then count elseif count <= 12 then math.ceil(count / 2) else math.ceil(count / 3)
	local slotW = math.min(118, 340 / cols)
	-- fit the widest bust (shoulders, wide accessories) into its slot so neighbours don't run together
	local widest, tallest = 60, 60
	for _, entry in ipairs(entries) do
		local b = cloudFor(entry)
		widest = math.max(widest, b.width or 92)
		tallest = math.max(tallest, (b.top or 50) - (b.bottom or -38))
	end
	local scale = math.min(1, slotW * 0.88 / widest)
	local showNames = count <= 4
	local nameCap = 10
	local rowH = (tallest + (if showNames then nameCap + 10 else 8)) * scale
	local remaining = budget
	local nameBudget = if showNames then math.floor(remaining * 0.22 / count) else 0
	local perBust = math.max(60, math.floor((remaining - nameBudget * count) / count))
	local parts = {}
	local rowTop, lowest = -math.huge, math.huge
	for i, entry in ipairs(entries) do
		local r = math.floor((i - 1) / cols)
		local inRow = math.min(cols, count - r * cols)
		local c = (i - 1) - r * cols
		local x = (c - (inRow - 1) / 2) * slotW
		local y = -r * rowH
		local bust = cloudFor(entry)
		table.insert(parts, { cloud = bust, take = math.min(bust.n, perBust), scale = scale, x = x, y = y })
		if r == 0 then
			rowTop = math.max(rowTop, y + (bust.top or 50) * scale)
		end
		local bottom = y + (bust.bottom or -38) * scale
		if showNames then
			local label = textCloud(tostring(entry.name or ""), nameCap, nameBudget, NAME_COLOR)
			local cap = nameCap
			if label.width > slotW * 0.96 then
				cap = math.max(6.5, nameCap * slotW * 0.96 / label.width)
				label = textCloud(tostring(entry.name or ""), cap, nameBudget, NAME_COLOR)
			end
			table.insert(parts, { cloud = label, x = x, y = bottom - 6 - cap / 2 })
			bottom -= 6 + cap
		end
		lowest = math.min(lowest, bottom)
	end
	return recentre(Shapes.compose(parts), 6)
end

-- The day caption the show opens and closes on: "DUSK · DAY ONE" over a thin rule over "4 FELL TODAY"
-- ("NO ONE FELL TODAY" when nobody fell: then it is the whole show).
local function captionShape(day: number, count: number, budget: number)
	local line1, line2 = DayCycle.recapCaption(day, count, show and show.mode)
	local bigCap, smallCap = 19, 12
	local big = textCloud(line1, bigCap, math.floor(budget * 0.5), CAPTION_COLOR)
	if big.width > 280 then
		bigCap = bigCap * 280 / big.width
		big = textCloud(line1, bigCap, math.floor(budget * 0.5), CAPTION_COLOR)
	end
	local small = textCloud(line2, smallCap, math.floor(budget * 0.3), NAME_COLOR)
	local ruleW = math.max(big.width, small.width) * 0.78
	local rule = Shapes.line(ruleW, 0.9, math.floor(ruleW * 1.4), RULE_COLOR)
	return recentre(Shapes.compose({
		{ cloud = big, y = 9 + bigCap / 2 },
		{ cloud = rule, y = 0 },
		{ cloud = small, y = -(6 + smallCap / 2) },
	}), 6)
end

local function shapeForSegment(s, budget: number)
	if not show then
		return nil
	end
	if s.kind == "caption" or s.kind == "none" then
		return captionShape(show.day, #show.entries, budget)
	elseif s.kind == "person" then
		return personShape(show.entries[s.index] or {}, budget)
	elseif s.kind == "finale" then
		return finaleShape(show.entries, budget)
	end
	return nil
end

-- Sound ----------------------------------------------------------------------------------------------------------------

local soundFolder: Folder? = nil

local function soundEntry(key: string)
	local entry = Sounds[key]
	if type(entry) == "table" and type(entry.ids) == "table" and #entry.ids > 0 then
		return entry
	end
	return nil
end

local function makeSound(key: string, looped: boolean): Sound?
	local entry = soundEntry(key)
	if not entry then
		return nil
	end
	if not (soundFolder and soundFolder.Parent) then
		local f = Instance.new("Folder")
		f.Name = "FallenRecapAudio"
		f.Parent = SoundService
		soundFolder = f
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = entry.ids[math.random(1, #entry.ids)]
	s.Volume = 0
	s.Looped = looped
	local group = SoundService:FindFirstChild(entry.group or "SFX")
	if group and group:IsA("SoundGroup") then
		s.SoundGroup = group
	end
	if type(entry.region) == "table" then
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(entry.region[1], entry.region[2])
		if looped then
			s.LoopRegion = NumberRange.new(entry.region[1], entry.region[2])
		end
	end
	s.Parent = soundFolder
	return s
end

local function oneShot(key: string, volumeScale: number?, pitch: number?)
	local entry = soundEntry(key)
	local s = makeSound(key, false)
	if not (s and entry) then
		return nil
	end
	s.Volume = (entry.volume or 0.5) * (volumeScale or 1)
	s.PlaybackSpeed = pitch or 1
	s:Play()
	local life = entry.maxLifetime or 12
	task.delay(life, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	s.Ended:Once(function()
		s:Destroy()
	end)
	return s
end

local function fadeOutSound(s: Sound?, seconds: number)
	if not s then
		return
	end
	task.spawn(function()
		local v0 = s.Volume
		local t0 = os.clock()
		while s.Parent and os.clock() - t0 < seconds do
			s.Volume = v0 * (1 - (os.clock() - t0) / seconds)
			task.wait()
		end
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- Ramp a sound that has just started from silence up to the volume it was started at.
local function fadeInSound(s: Sound?, seconds: number)
	if not s then
		return
	end
	local target = s.Volume
	s.Volume = 0
	task.spawn(function()
		local t0 = os.clock()
		while s.Parent and os.clock() - t0 < seconds do
			local p = (os.clock() - t0) / seconds
			s.Volume = target * p * p
			task.wait()
		end
		if s.Parent then
			s.Volume = target
		end
	end)
end

-- Show lifecycle -------------------------------------------------------------------------------------------------------

local function arenaCentre(): Vector3
	local arena = workspace:FindFirstChild("Arena")
	local c = arena and arena:GetAttribute("Center")
	return if typeof(c) == "Vector3" then c else ArenaLayout.Center
end

local function chooseBearing(mode: string?): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end
	local p = camera.CFrame.Position
	local centre = arenaCentre()
	local dx, dz = centre.X - p.X, centre.Z - p.Z
	-- the epilogue (QW14) plays behind the winner card, so it hangs where you are looking, wherever you stand
	if mode ~= "epilogue" and dx * dx + dz * dz > NEAR_CENTRE * NEAR_CENTRE then
		return math.atan2(dx, -dz)
	end
	local look = camera.CFrame.LookVector
	if math.abs(look.X) + math.abs(look.Z) < 1e-3 then
		return 0
	end
	return math.atan2(look.X, -look.Z)
end

local function stopShow()
	if not show then
		return
	end
	local s = show
	show = nil
	if s.musicSuppressed then
		local audio = Controllers and Controllers.AudioController
		if audio and audio.setMusicSuppressed then
			pcall(audio.setMusicSuppressed, false)
		end
	end
	fadeOutSound(s.bed, 0.8)
	fadeOutSound(s.crackle, 0.8)
	for _, snd in ipairs(s.voices) do
		fadeOutSound(snd, 1.2)
	end
	parkAll()
	FallenRecapController.showChanged:Fire(false, nil)
end

local function startShow(payload)
	stopShow()
	local entries = {}
	if type(payload.entries) == "table" then
		for _, e in ipairs(payload.entries) do
			if type(e) == "table" and type(e.name) == "string" then
				table.insert(entries, { name = e.name, userId = tonumber(e.userId) or 0, snapshot = tostring(e.snapshot or "") })
			end
		end
	end
	local mode = if type(payload.mode) == "string" then payload.mode else nil -- "epilogue": the short show (QW14)
	local timeline = DayCycle.recapTimeline(#entries, mode)
	show = {
		id = payload.id,
		mode = mode,
		startAt = tonumber(payload.startAt) or workspace:GetServerTimeNow(),
		day = tonumber(payload.day) or 1,
		entries = entries,
		timeline = timeline,
		segIndex = 0,
		shapes = {},
		shape = nil,
		prevShape = nil,
		enteredPool = 0,
		bearing = chooseBearing(mode),
		voices = {},
		fired = {},
		nextCrackle = 0,
		crackleUntil = -1,
		crackleBand = 0,
	}
	activeCount = math.min(#pool, poolTarget)
	-- make sure every bust we'll need is queued for sampling
	for _, e in ipairs(entries) do
		if e.snapshot ~= "" and not clouds[e.snapshot] then
			local snap = ReplicatedStorage:FindFirstChild("FallenSnapshots")
			local model = snap and snap:FindFirstChild(e.snapshot)
			if model then
				FallenRecapController._queue(model)
			end
		end
	end
	local bed = makeSound("RollCallStatic", true)
	local crackle = makeSound("RollCallCrackle", true)
	if bed then
		bed:Play()
	end
	if crackle then
		crackle:Play()
	end
	show.bed, show.crackle = bed, crackle
	-- no music under the Roll Call (no anthem, no music bed): the music loops are switched off for the whole show and
	-- ducked to silence meanwhile (a fast fade as the static comes up); ambience dips
	local audio = Controllers and Controllers.AudioController
	if audio then
		local remaining = math.max(1, show.startAt + timeline.total - workspace:GetServerTimeNow())
		if audio.setMusicSuppressed then
			pcall(audio.setMusicSuppressed, true)
			show.musicSuppressed = true
		end
		if audio.duck then
			pcall(audio.duck, 0, 0.55, remaining)
		end
	end
	FallenRecapController.showChanged:Fire(true, payload)
end

-- The shape of segment k, built once per show (so re-entering a segment reuses the same point assignment).
local function shapeOf(k: number)
	if not show or k < 1 then
		return nil
	end
	local cached = show.shapes[k]
	if cached ~= nil then
		return cached or nil
	end
	local s = show.timeline.segments[k]
	local shape = if s then shapeForSegment(s, math.max(400, poolTarget)) else nil
	show.shapes[k] = shape or false
	return shape
end

-- Segment entry: precompute every point's from / to.
local function enterSegment(k: number, t: number)
	local s = show.timeline.segments[k]
	show.segIndex = k
	local shape = shapeOf(k)
	local prev = shapeOf(k - 1)
	show.shape = shape
	show.prevShape = prev
	local n = #pool
	-- per-point delay: a top-to-bottom build with randomness
	local topY, botY = 1, 0
	if shape and shape.n > 0 then
		local _, _, minY, maxY = Shapes.bounds(shape)
		topY, botY = maxY, minY
	end
	local span = math.max(1, topY - botY)
	for i = 1, n do
		prevInShape[i] = prev ~= nil and i <= prev.n
		-- from: where the point was at the end of the previous segment
		if prevInShape[i] then
			ax[i], ay[i], az[i] = prev.x[i], prev.y[i], prev.z[i]
		else
			local x, y, z = staticAt(i, s.t0, 1)
			ax[i], ay[i], az[i] = x, y, z
		end
		-- static scatter at the end of the break
		local hop = 9000 + k * 131
		sxp[i] = (h1(i, hop) - 0.5) * STATIC_W
		syp[i] = (h2(i, hop) - 0.5) * STATIC_H
		szp[i] = (h3(i, hop) - 0.5) * STATIC_D
		if shape and i <= shape.n then
			inShape[i] = true
			bx[i], by[i], bz[i] = shape.x[i], shape.y[i], shape.z[i]
			local fromTop = (topY - by[i]) / span
			delayF[i] = math.clamp(0.5 * fromTop + 0.5 * seed[i], 0, 1)
		else
			inShape[i] = false
			bx[i], by[i], bz[i] = sxp[i], syp[i], szp[i]
		end
	end
	show.shapeColors = shape and shape.c or nil
	show.fired = {}
	show.enteredPool = n
end

local function easeInOut(p: number): number
	if p < 0.5 then
		return 4 * p * p * p
	end
	local f = -2 * p + 2
	return 1 - f * f * f / 2
end

local function easeIn(p: number): number
	return p * p
end

-- The level of static noise in the sound (0..1) at show time t.
local function staticLevel(s, t: number): number
	if s.kind == "static" then
		return math.clamp(t / 1.0, 0, 1)
	elseif s.kind == "dissolve" then
		if t < s.t1 then
			return 0.3 + 0.7 * (t - s.t0) / math.max(0.01, s.t1 - s.t0)
		elseif t < s.t2 then
			return 1
		end
		return math.clamp(1 - (t - s.t2) / math.max(0.01, (s.t3 or s.t2 + 1) - s.t2), 0, 1)
	end
	if t < s.tb then
		return 0.75
	elseif t < s.t1 then
		local p = (t - s.tb) / math.max(0.01, s.t1 - s.tb)
		return 0.75 * (1 - p) + 0.1
	end
	return 0.1
end

local function updateAudio(s, t: number, k: number)
	local bedEntry = soundEntry("RollCallStatic")
	local crackleEntry = soundEntry("RollCallCrackle")
	local level = staticLevel(s, t)
	if show.bed and bedEntry then
		show.bed.Volume = (bedEntry.volume or 0.3) * level
	end
	if show.crackle and crackleEntry then
		show.crackle.Volume = (crackleEntry.volume or 0.3) * (0.25 + 0.75 * level)
	end
	local fired = show.fired
	local function once(key: string, at: number, fn)
		if not fired[key] and t >= at and t < at + 1.5 then
			fired[key] = true
			fn()
		end
	end
	if s.kind == "caption" or s.kind == "person" or s.kind == "finale" or s.kind == "none" then
		if s.tb > s.t0 then
			once("burst", s.t0, function()
				local v = oneShot("RollCallBurst", 1, 0.96 + math.random() * 0.08)
				if v then
					table.insert(show.voices, v)
				end
			end)
		end
		-- the low tone swells in while the points stream together and resolves as the piece locks
		local lead = math.clamp(s.t1 - s.tb - 0.2, 0.3, 1.4)
		once("tone", s.t1 - lead, function()
			local key = if s.kind == "person" then "RollCallToneSoft" else "RollCallTone"
			local v = oneShot(key, 1, if s.kind == "person" then 1 + ((s.index or 1) % 3 - 1) * 0.03 else 1)
			if v then
				fadeInSound(v, lead)
				table.insert(show.voices, v)
				task.delay(math.max(2, s.t2 - s.t1 + lead + 1.2), function()
					fadeOutSound(v, 1.6)
				end)
			end
		end)
	elseif s.kind == "dissolve" then
		once("burst", s.t0, function()
			local v = oneShot("RollCallBurst", 1, 0.9)
			if v then
				table.insert(show.voices, v)
			end
		end)
	end
	-- prune finished voices
	for i = #show.voices, 1, -1 do
		local v = show.voices[i]
		if not v or not v.Parent then
			table.remove(show.voices, i)
		end
	end
end

-- Per-frame ------------------------------------------------------------------------------------------------------------

-- Canopy-aware placement -------------------------------------------------------------------------------------------------

local liftParams = RaycastParams.new()
liftParams.FilterType = Enum.RaycastFilterType.Exclude
liftParams.IgnoreWater = true
local crownOverlap = OverlapParams.new()
crownOverlap.FilterType = Enum.RaycastFilterType.Exclude
crownOverlap.MaxParts = 800

-- Tree crowns. Foliage and branch meshes ignore raycasts (CanQuery off), so the crown of every tree near the camera (a
-- non-queryable part named like *Foliage* / *Branches* / *Leaves* / *Canopy* / *Crown* / *Needles* in a model found
-- through its queryable trunk) stands in as a stack of spheres; tall (conifer) boxes taper toward the top.
local CROWN_WORDS = { "Foliage", "Branches", "Leaves", "Canopy", "Crown", "Needles" }
local CROWN_RADIUS = 120 -- studs around the camera
local CROWN_MAX = 3000 -- spheres

local function isCrown(p: Instance): boolean
	if not p:IsA("BasePart") or p.CanQuery or p.Transparency >= 0.95 then
		return false
	end
	for _, word in ipairs(CROWN_WORDS) do
		if string.find(p.Name, word, 1, true) then
			return true
		end
	end
	return false
end

local function gatherCrowns(camPos: Vector3)
	local xs, ys, zs, r2s = {}, {}, {}, {}
	local seen = {}
	local n = 0
	for _, part in ipairs(workspace:GetPartBoundsInRadius(camPos, CROWN_RADIUS, crownOverlap)) do
		local model = part.Parent
		if model and model:IsA("Model") and not seen[model] then
			seen[model] = true
			for _, p in ipairs(model:GetChildren()) do
				if n < CROWN_MAX and isCrown(p) then
					local s = (p :: BasePart).Size
					local pos = (p :: BasePart).Position
					local w = math.min(s.X, s.Z)
					local r0 = 0.42 * w
					local tall = s.Y > 1.6 * w
					local bottom = pos.Y - s.Y / 2
					local y = bottom + r0 * 0.8
					while y < bottom + s.Y - r0 * 0.3 and n < CROWN_MAX do
						local r = if tall then r0 * (1 - 0.65 * (y - bottom) / s.Y) else r0
						n += 1
						xs[n], ys[n], zs[n], r2s[n] = pos.X, y, pos.Z, r * r
						y += math.max(2, r * 1.3)
					end
				end
			end
		end
	end
	return { x = xs, y = ys, z = zs, r2 = r2s, n = n }
end

local function crownBlocks(crowns, o: Vector3, d: Vector3): boolean
	local len = d.Magnitude
	local ux, uy, uz = d.X / len, d.Y / len, d.Z / len
	local ox, oy, oz = o.X, o.Y, o.Z
	local xs, ys, zs, r2s = crowns.x, crowns.y, crowns.z, crowns.r2
	for i = 1, crowns.n do
		local cx, cy, cz = xs[i] - ox, ys[i] - oy, zs[i] - oz
		local t = cx * ux + cy * uy + cz * uz
		if t > 0 and t < len and (cx * cx + cy * cy + cz * cz - t * t) < r2s[i] then
			return true
		end
	end
	return false
end

-- Share of the display (a 5 x 3 grid over the middle of the static screen) that the world hides from camPos when it
-- hangs at elevation `elev` on the show's bearing: terrain and solid parts by raycast, tree crowns by their spheres.
local function hiddenShare(camPos: Vector3, bearing: number, elev: number, crowns): number
	local horiz = Vector3.new(math.sin(bearing), 0, -math.cos(bearing))
	local centre = camPos + horiz * (STAGE_DISTANCE * math.cos(elev)) + Vector3.new(0, STAGE_DISTANCE * math.sin(elev), 0)
	local fwd = (centre - camPos).Unit
	local right = fwd:Cross(Vector3.yAxis).Unit
	local up = right:Cross(fwd).Unit
	local hidden, total = 0, 0
	for ix = -2, 2 do
		for iy = -1, 1 do
			local p = centre + right * (ix * 0.14 * STATIC_W * UNIT) + up * (iy * 0.22 * STATIC_H * UNIT)
			total += 1
			local d = p - camPos
			if workspace:Raycast(camPos, d, liftParams) or (crowns and crowns.n > 0 and crownBlocks(crowns, camPos, d)) then
				hidden += 1
			end
		end
	end
	return hidden / total
end

-- Pick (every LIFT_CHECK s, or when the camera has moved) and glide toward the lowest clear elevation.
local function updateLift(dt: number, snap: boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	local moved = show.liftFrom == nil or (camPos - show.liftFrom).Magnitude > 3
	if snap or (t >= (show.nextLift or 0) and moved) or t >= (show.nextLift or 0) + 2 then
		show.nextLift = t + LIFT_CHECK
		show.liftFrom = camPos
		local exclude = { camera }
		if folder then
			table.insert(exclude, folder)
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(exclude, p.Character)
			end
		end
		liftParams.FilterDescendantsInstances = exclude
		if not show.crowns or (camPos - show.crownsFrom).Magnitude > 8 or t >= show.crownsAt + 3 then
			show.crowns = gatherCrowns(camPos)
			show.crownsFrom, show.crownsAt = camPos, t
		end
		local crowns = show.crowns
		local current = show.elevTarget or ELEVATION
		local currentHidden = hiddenShare(camPos, show.bearing, current, crowns)
		local best, bestHidden = current, currentHidden
		local pick, pickHidden = nil, 2
		for _, e in ipairs(LIFT_ELEVATIONS) do
			local h = if math.abs(e - current) < 1e-3 then currentHidden else hiddenShare(camPos, show.bearing, e, crowns)
			if h <= LIFT_CLEAR then
				pick, pickHidden = e, h
				break
			end
			if h < pickHidden - 0.03 then
				pick, pickHidden = e, h
			end
		end
		-- move only for a clear gain (or down to a lower clear placement), so it never hunts between two similar ones
		if pick and (snap or (pick < current and pickHidden <= LIFT_CLEAR) or currentHidden - pickHidden >= 0.06) then
			best, bestHidden = pick, pickHidden
		end
		show.elevTarget = best
		show.hidden = bestHidden
	end
	if snap or not show.elev or math.abs(show.elevTarget - show.elev) < 0.002 then
		show.elev = show.elevTarget -- settled: the stage stops moving, so held points stop being moved
	else
		show.elev += (show.elevTarget - show.elev) * (1 - math.exp(-LIFT_RATE * dt))
	end
end

local function stageBasis()
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local b = show.bearing
	local horiz = Vector3.new(math.sin(b), 0, -math.cos(b))
	local elev = show.elev or ELEVATION
	local centre = camPos + horiz * (STAGE_DISTANCE * math.cos(elev)) + Vector3.new(0, STAGE_DISTANCE * math.sin(elev), 0)
	local fwd = (centre - camPos).Unit
	local right = fwd:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-3 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(fwd).Unit
	return centre, right, up, fwd
end

local function update(dt: number)
	if not show then
		return
	end
	local now = workspace:GetServerTimeNow()
	local t = now - show.startAt
	-- Studio only: GameState "DevRecapFreeze" = seconds holds the show at that moment (for screenshots)
	local frozen = if RunService:IsStudio() then GameState:GetAttribute("DevRecapFreeze") else nil
	if type(frozen) == "number" then
		t = frozen
	end
	local tl = show.timeline
	if t > tl.total + 0.2 then
		stopShow()
		return
	end
	if t < 0 then
		parkAll()
		return
	end
	-- adaptive point budget: back off if frames are slow while showing
	frameEma += (dt - frameEma) * 0.08
	if frameEma > 1 / 42 then
		slowFor += dt
		if slowFor > 1.5 and activeCount > 900 then
			slowFor = 0
			local newCount = math.floor(activeCount * 0.85)
			for i = newCount + 1, activeCount do
				cfs[i] = HIDDEN
			end
			activeCount = newCount
		end
	else
		slowFor = math.max(0, slowFor - dt)
	end

	-- current segment (re-entered when the pool grew, so new points get their targets too)
	local k = show.segIndex
	local segs = tl.segments
	if k ~= 0 and show.enteredPool < #pool then
		enterSegment(k, t)
	end
	if k == 0 or t >= (if segs[k].kind == "dissolve" then (segs[k].t3 or segs[k].t2) else segs[k].t2) or t < segs[k].t0 then
		local found = #segs
		for i, s in ipairs(segs) do
			if t < (if s.kind == "dissolve" then (s.t3 or s.t2) else s.t2) then
				found = i
				break
			end
		end
		if found ~= k then
			enterSegment(found, t)
			k = found
		end
	end
	local s = segs[k]
	updateAudio(s, t, k)

	updateLift(dt, show.elevTarget == nil)
	local centre, right, up, fwd = stageBasis()
	local rot = CFrame.fromMatrix(Vector3.zero, right, up)
	-- gentle turn so the busts read as 3D
	local yaw = 0.2 * math.sin((t + 2.5) * 0.36)
	local cy, sy = math.cos(yaw), math.sin(yaw)
	-- A held (assembled) piece only needs moving when the stage moved: the camera moved (the stage follows it), the slow
	-- turn stepped on by a hair, a glitch band passes, or the piece has just locked. Otherwise its points stay exactly
	-- where they are, which is most of the show for a viewer who stands and looks up.
	local holdingNow = s.kind ~= "static" and s.kind ~= "dissolve" and t >= s.t1
	local glitchNow = (t % 2.3) < 0.07
	local moveHeld = show.heldSeg ~= k or not show.heldCentre or (centre - show.heldCentre).Magnitude > 0.05
		or math.abs(yaw - (show.heldYaw or 1e9)) > 0.0025 or glitchNow or show.heldGlitch or show.heldPool ~= #pool
	show.heldGlitch = glitchNow
	if moveHeld and holdingNow then
		show.heldSeg, show.heldCentre, show.heldYaw, show.heldPool = k, centre, yaw, #pool
	elseif not holdingNow then
		show.heldSeg = nil
	end
	local rX, rY, rZ = right.X * UNIT, right.Y * UNIT, right.Z * UNIT
	local uX, uY, uZ = up.X * UNIT, up.Y * UNIT, up.Z * UNIT
	local fX, fY, fZ = -fwd.X * UNIT, -fwd.Y * UNIT, -fwd.Z * UNIT
	local cX, cY, cZ = centre.X, centre.Y, centre.Z

	-- static crackle: short bursts where a band of points jumps
	if t >= show.nextCrackle then
		show.nextCrackle = t + 0.5 + math.random() * 1.6
		show.crackleUntil = t + 0.06 + math.random() * 0.08
		show.crackleBand = (math.random() - 0.5) * STATIC_H
	end
	local crackling = t < show.crackleUntil
	local band = show.crackleBand
	-- a slowly travelling interference band
	local bandY = ((t * 0.37) % 1 - 0.5) * STATIC_H * 1.2
	local bandShift = 9 * math.sin(t * 23)

	local n = activeCount
	local kind = s.kind
	local colors = show.shapeColors
	local holdGlitchY = ((t * 0.21 + 0.3) % 1 - 0.5) * 160
	local glitchOn = (t % 2.3) < 0.07
	local isShapeSeg = kind ~= "static" and kind ~= "dissolve"
	local holding = isShapeSeg and t >= s.t1
	local staticFade = if kind == "static" then math.clamp(t / 1.3, 0, 1) else 0
	local breakE = 0
	if isShapeSeg and t < s.tb then
		local p = math.clamp((t - s.t0) / math.max(0.01, s.tb - s.t0), 0, 1)
		breakE = p * p
	end
	local window = s.t1 - s.tb
	local dissolveSpan = s.t1 - s.t0
	local fadeOut = if kind == "dissolve" and t >= s.t2 then (t - s.t2) / math.max(0.01, (s.t3 or s.t2 + 1) - s.t2) else -1
	local paletteN = #STATIC_COLORS
	local m = 0
	local tLoop = os.clock()

	for i = 1, n do
		local x, y, z
		local visible = true
		local useShapeColor = false
		local textured = false -- static texture (jitter, bands, crackle) applies
		if holding and inShape[i] then
			-- assembled: still, apart from a rare glitch band (and nothing to do unless the stage moved)
			if not moveHeld then
				continue
			end
			x, y, z = bx[i], by[i], bz[i]
			if glitchOn and y - holdGlitchY < 5 and holdGlitchY - y < 5 then
				x += 3.5
			end
			useShapeColor = true
		elseif kind == "static" then
			local sx, sy2, sz, v = staticAt(i, t, 1)
			x, y, z = sx, sy2, sz
			visible = v and seed[i] < staticFade
			textured = true
		elseif kind == "dissolve" then
			local sx, sy2, sz, v = staticAt(i, t, 1)
			if t < s.t1 then
				-- shape -> static
				local p = (t - s.t0 - delayF[i] * 0.4 * dissolveSpan) / math.max(0.01, 0.6 * dissolveSpan)
				p = if p < 0 then 0 elseif p > 1 then 1 else p
				local e = p * p
				x = ax[i] + (sx - ax[i]) * e
				y = ay[i] + (sy2 - ay[i]) * e
				z = az[i] + (sz - az[i]) * e
				visible = prevInShape[i] or (v and p > 0.5)
			else
				x, y, z = sx, sy2, sz
				visible = v and (fadeOut < 0 or seed[i] > fadeOut)
			end
			textured = true
		elseif t < s.tb then
			-- breaking back into static
			local e = breakE
			x = ax[i] + (sxp[i] - ax[i]) * e + (math.random() - 0.5) * 3 * e
			y = ay[i] + (syp[i] - ay[i]) * e + (math.random() - 0.5) * 3 * e
			z = az[i] + (szp[i] - az[i]) * e
			visible = prevInShape[i] or (seed[i] < 0.6 * e)
			textured = not inShape[i]
		elseif inShape[i] then
			-- streaming into the shape
			local start = s.tb + delayF[i] * 0.45 * window
			local fromX, fromY, fromZ
			if s.tb > s.t0 then
				fromX, fromY, fromZ = sxp[i], syp[i], szp[i]
			else
				-- straight out of the live static: it keeps crawling until this point's turn comes
				fromX, fromY, fromZ = staticAt(i, if t < start then t else start, 1)
			end
			local p = (t - start) / math.max(0.01, 0.55 * window)
			p = if p < 0 then 0 elseif p > 1 then 1 else p
			local e = if p < 0.5 then 4 * p * p * p else 1 - (-2 * p + 2) ^ 3 / 2
			local arc = math.sin(math.pi * e) * 16
			local jit = (1 - e) * 2.2
			x = fromX + (bx[i] - fromX) * e + curlX[i] * arc + (math.random() - 0.5) * jit
			y = fromY + (by[i] - fromY) * e + curlY[i] * arc + (math.random() - 0.5) * jit
			z = fromZ + (bz[i] - fromZ) * e + curlZ[i] * arc
			useShapeColor = p >= 0.55
			-- a point still flying in flickers like the static it came from
			if p < 1 and p > 0 then
				visible = seed[i] < 0.92 or math.random() < 0.6
			end
		else
			-- dust: a sparse drift of leftover static around the piece
			x, y, z = staticAt(i, t * 0.25, 1.15)
			visible = seed[i] < 0.1
			textured = true
		end
		if visible then
			if textured then
				-- static texture: interference band and crackle
				if y - bandY < 5 and bandY - y < 5 then
					x += bandShift
				end
				if crackling and y - band < 12 and band - y < 12 then
					x += (math.random() - 0.5) * 30
				end
				x += (math.random() - 0.5) * 0.6
				y += (math.random() - 0.5) * 0.6
			end
			-- yaw about the vertical axis, then into the world
			local rx = x * cy + z * sy
			local rz = z * cy - x * sy
			m += 1
			moveParts[m] = pool[i]
			moveCfs[m] = CFrame.new(cX + rX * rx + uX * y + fX * rz, cY + rY * rx + uY * y + fY * rz, cZ + rZ * rx + uZ * y + fZ * rz)
			parked[i] = false
		elseif not parked[i] then
			m += 1
			moveParts[m] = pool[i]
			moveCfs[m] = HIDDEN
			parked[i] = true
		end
		-- colour wanted
		if useShapeColor and colors and colors[i] then
			wantColor[i] = colors[i]
		else
			wantColor[i] = STATIC_COLORS[(i % paletteN) + 1]
		end
	end
	-- points beyond the active count (the budget shrank) go out of sight once
	for i = n + 1, #pool do
		if not parked[i] then
			m += 1
			moveParts[m] = pool[i]
			moveCfs[m] = HIDDEN
			parked[i] = true
		end
	end
	for i = m + 1, moveCount do
		moveParts[i] = nil
		moveCfs[i] = nil
	end
	moveCount = m
	local tBulk = os.clock()
	if m > 0 then
		workspace:BulkMoveTo(moveParts, moveCfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local tColor = os.clock()

	-- colours: budgeted writes (reference compares: shape and palette colours are shared Color3 objects)
	local writes = 0
	local start = show.colorCursor or 1
	local total = n
	for step = 0, total - 1 do
		local i = ((start - 1 + step) % total) + 1
		local want = wantColor[i]
		if not rawequal(curColor[i], want) then
			pool[i].Color = want
			curColor[i] = want
			writes += 1
			if writes >= COLOR_WRITES_PER_FRAME then
				show.colorCursor = i + 1
				break
			end
		end
	end
	if writes < COLOR_WRITES_PER_FRAME then
		show.colorCursor = 1
	end
	local tEnd = os.clock()
	diag.loop += ((tBulk - tLoop) * 1000 - diag.loop) * 0.1
	diag.bulk += ((tColor - tBulk) * 1000 - diag.bulk) * 0.1
	diag.color += ((tEnd - tColor) * 1000 - diag.color) * 0.1
	diag.moved = m
end

-- Snapshot sampling ------------------------------------------------------------------------------------------------------

local function worker()
	if workerBusy then
		return
	end
	workerBusy = true
	task.spawn(function()
		-- the neutral bust first (cheap, cached)
		pcall(Shapes.mannequin)
		while #queue > 0 do
			local model = table.remove(queue, 1)
			if model and model.Parent and not clouds[model.Name] then
				local ok, cloudOrErr = pcall(Shapes.sampleBust, model)
				if ok and cloudOrErr then
					clouds[model.Name] = cloudOrErr
				elseif not ok then
					warnf("couldn't sample %s: %s", model.Name, tostring(cloudOrErr))
				end
			end
			if model then
				sampling[model.Name] = nil
			end
			RunService.Heartbeat:Wait()
		end
		workerBusy = false
	end)
end

function FallenRecapController._queue(model: Instance)
	if not model:IsA("Model") or clouds[model.Name] or sampling[model.Name] then
		return
	end
	sampling[model.Name] = true
	table.insert(queue, model)
	worker()
end

local function watchSnapshots()
	local snaps = ReplicatedStorage:WaitForChild("FallenSnapshots", 60)
	if not snaps then
		return
	end
	snaps.ChildAdded:Connect(function(child)
		task.wait(0.3) -- let its descendants arrive
		FallenRecapController._queue(child)
	end)
	snaps.ChildRemoved:Connect(function(child)
		-- keep the cloud while a show still needs it; drop it otherwise
		local needed = false
		if show then
			for _, e in ipairs(show.entries) do
				if e.snapshot == child.Name then
					needed = true
				end
			end
		end
		if not needed then
			clouds[child.Name] = nil
		end
	end)
	for _, child in ipairs(snaps:GetChildren()) do
		FallenRecapController._queue(child)
	end
end

-- Show source: GameState "RollCall" --------------------------------------------------------------------------------------

local function readShow()
	local json = GameState:GetAttribute("RollCall")
	if type(json) ~= "string" or json == "" then
		-- cleared by the server (a new round is starting): a show still running ends now
		if show then
			stopShow()
		end
		return
	end
	local ok, payload = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(payload) ~= "table" then
		return
	end
	if payload.id ~= nil and payload.id == lastShowId then
		return
	end
	if payload.sky == false then
		-- QW14: a Roll Call during the finale posts its names in the 2D list only (NotificationController), so the
		-- final-stand music keeps playing; the epilogue shows them in the sky once the round is won
		lastShowId = payload.id
		return
	end
	local startAt = tonumber(payload.startAt) or 0
	local duration = tonumber(payload.duration) or 0
	local now = workspace:GetServerTimeNow()
	if now > startAt + duration then
		return -- already over
	end
	lastShowId = payload.id
	-- the pool must exist before the show can run
	poolTarget = math.max(poolTarget, desiredPoolSize())
	startShow(payload)
end

-- Public API -------------------------------------------------------------------------------------------------------------

function FallenRecapController.isShowing(): boolean
	return show ~= nil
end

function FallenRecapController.getBearing(): number?
	if not show then
		return nil
	end
	return math.deg(show.bearing) % 360
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------------

function FallenRecapController.Init(registry)
	Controllers = registry
end

function FallenRecapController.Start()
	poolTarget = desiredPoolSize()
	-- build the pool gradually in the background (parked out of sight)
	task.spawn(function()
		task.wait(3)
		while not growPool(120) do
			RunService.Heartbeat:Wait()
		end
		parkAll()
	end)
	task.spawn(watchSnapshots)
	worker()
	GameState:GetAttributeChangedSignal("RollCall"):Connect(readShow)
	-- the round is over and everyone is back in the lobby (or the next one is starting): a show still running ends
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = GameState:GetAttribute("Phase")
		if show and (phase == "Lobby" or phase == "Intermission" or phase == "Countdown") then
			stopShow()
		end
	end)
	local isStudio = RunService:IsStudio()
	local lastRender = 0
	local costEma = 0
	local function runUpdate(dt: number)
		if not show then
			return
		end
		if #pool < poolTarget then
			growPool(600)
			activeCount = math.min(#pool, poolTarget)
		end
		local t0 = os.clock()
		local ok, err = pcall(update, dt)
		if not ok then
			warnf("update failed: %s", tostring(err))
			stopShow()
			return
		end
		if isStudio and folder then
			-- Studio diagnostics: CPU cost of a frame of the show, points in use, current segment
			costEma += ((os.clock() - t0) * 1000 - costEma) * 0.1
			folder:SetAttribute("UpdateMs", math.floor(costEma * 100) / 100)
			folder:SetAttribute("Points", activeCount)
			folder:SetAttribute("Breakdown", string.format("loop %.2f bulk %.2f colour %.2f moved %d", diag.loop, diag.bulk, diag.color, diag.moved or 0))
			local seg = show and show.timeline.segments[show.segIndex]
			folder:SetAttribute("Segment", if seg then (seg.kind .. (seg.index and (" " .. seg.index) or "")) else "")
			folder:SetAttribute("LiftDeg", if show and show.elev then math.floor(math.deg(show.elev) + 0.5) else 0)
			folder:SetAttribute("HiddenPct", if show and show.hidden then math.floor(show.hidden * 100 + 0.5) else 0)
			folder:SetAttribute("Crowns", if show and show.crowns then show.crowns.n else 0)
		end
	end
	-- after the camera has moved, so the display sits exactly where this frame's camera says
	RunService:BindToRenderStep("LS_FallenRecap", Enum.RenderPriority.Camera.Value + 5, function(dt)
		lastRender = os.clock()
		runUpdate(dt)
	end)
	-- the timeline keeps going while the window isn't rendering (minimised, or a throttled device)
	RunService.Heartbeat:Connect(function(dt)
		if show and os.clock() - lastRender > 0.5 then
			runUpdate(dt)
		end
	end)
	readShow()
end

return FallenRecapController
