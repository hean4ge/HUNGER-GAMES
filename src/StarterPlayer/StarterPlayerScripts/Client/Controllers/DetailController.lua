--[[
	DetailController - scales the arena's scenery with the graphics quality, so phones and low settings draw fewer
	triangles. Owner: environment art / performance (see docs/GameDesign.md section 11, "Set dressing").

	What it hides, on this client only (BasePart.LocalTransparencyModifier = 1: nothing replicates, nothing changes for
	anyone else), beyond a draw distance from the camera:
	  ground   grass tufts, flowers, moss, mushrooms (workspace.Arena.Flora)
	  fern     ferns
	  tall     tall grass and reeds (they can screen a crouching contender: the longest distances)
	  branches the trees' branch cards (*_Branches in workspace.Arena.Forest)
	  detail   the trees' root flares and moss (*_Roots, *_Moss)
	  tree     whole trees, saplings, logs and stumps (workspace.Arena.Forest), Low only, past 420 studs: the far side of
	           the arena, faded by the haze
	Bushes, rocks, cliffs and buildings are never hidden, and nothing that hides a contender is hidden within the
	distances a fight happens at, so every tier sees the same cover where it matters.

	  tier     ground   fern   tall   branches   detail   tree   heath
	  High     220      300    -      -          -        -      -       (- = never hidden)
	  Medium   130      180    260    320        220      -      320
	  Low       70      110    170    160        100      420    200

	Map 1 (the Green Land) keeps all its plants in workspace.Arena.Scatter, one Folder per 80-stud cell, each plant a
	Model named after its Blender asset (ServerStorage.WorldGen.Map1.Scatter). A Scatter model is classed whole, by
	its name, like a Flora model:
	  ground   M1_Wildflowers_A
	  heath    M1_Heather_A / _B: the heather mats that colour the upper slopes (they hide nobody)
	  tall     M1_TallGrass_A
	  tree     the firs, pines and beeches (M1_Fir_*, M1_Pine_*, M1_Beech_*)
	Gorse, boulders and crags are cover and are never hidden. The Scatter folder's attribute DetailClasses
	("M1_Fir_A=tree;M1_Heather_A=heath;...", written by the builder) adds to the table below, so a new asset needs
	no change here as long as its class is one of this table's.

	The tier, first match wins:
	  1 in Studio only, workspace attribute DetailTier = "Low" | "Medium" | "High" (tests and previews)
	  2 the player's graphics level, UserGameSettings.SavedQualityLevel: 1-3 Low, 4-6 Medium, 7-10 High
	  3 in Studio, the render quality level when Studio exposes it to scripts (settings().Rendering.QualityLevel):
	    1-6 Low, 7-13 Medium, 14-21 High (a LocalScript can't read it in current Studio builds)
	  4 the engine's running quality level (Stats.FrameRateManager.AverageQualityLevel, same bands) when readable
	  5 otherwise: High on PC and consoles, Medium on touch-only devices, and one tier lower after the frame rate stays
	    under 40 fps for 6 s (back up after 30 s over 55 fps). Off in Studio, whose unfocused window is throttled.
	The chosen tier is published as LocalPlayer attributes DetailTier and DetailTierWhy, and DetailSources says which
	of the sources above this client can read (this client only).

	The shader tier (what the lighting look adds on top of the engine: Shared.DayCycle.Tiers) rides on the same choice
	and is published as LocalPlayer attributes ShaderTier and ShaderDevice, which ArenaController.Sky reads:
	  scenery Low -> Phone, Medium -> Mid, High -> High; a touch-only device on automatic graphics is Phone
	  the player's own choice, the Menu's "Shaders: Off / Auto / Full" row (ClientState.settings.shaders 0 / 1 / 2,
	  saved with the other settings): Off = plain Roblox lighting with the same sun and clock, Full = High anywhere
	  in Studio, the workspace attribute DevShaders = "Off" | "Phone" | "Mid" | "High" forces it (tests, captures)
	ShaderDevice is the tier the device would have on Auto (Off keeps that tier's haze).

	The far canopy (Map 1): workspace.Arena.FarValley holds, per 1,900-stud tile, a dark canopy shell (Role
	"FarCanopy") that stands for the forests beyond the streamed radius. It lies at tree-top height over the real
	trees too, and where the engine has dropped the real trees (low quality levels cull them a few hundred studs
	out) a slab hovered over bare ground (seen at the lake, 18 Nov). So each canopy part is hidden on this client
	(LocalTransparencyModifier) while the camera is within FAR_HIDE studs of its footprint and fades in up to
	FAR_SHOW: the tile you stand in and the next one you walk toward never draw over ground that is streamed in;
	from the heart (r under 190) the ring tiles, 700 studs and more away, all show. The ground parts of the far
	valley (grass, heather, rock, water) lie under the real terrain and are never touched.

	Bookkeeping: models are bucketed into 40-stud cells as they stream in (ChildAdded on the Flora and Forest biome
	folders and on Map 1's Scatter cells) and dropped as they stream out. Every 0.25 s, once the camera has moved
	6 studs or the tier changed, only the cells whose distance band changed are flipped.
	API (for tests): DetailController.stats() -> { tier, why, models, cells, hidden, farCanopy, farCanopyHidden },
	DetailController.refresh(). The stats are also published as LocalPlayer attributes DetailHidden (parts hidden now)
	and DetailFarHidden ("hidden/all" far canopy parts).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local ArenaLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ArenaLayout"))

local DetailController = {}

local IS_STUDIO = RunService:IsStudio()
local CELL = 40
local HALF_DIAG = CELL * 0.7071
local INF = math.huge
-- Flora models, and Map 1's Scatter models: one class for the whole model, by its name
local FLORA = {
	-- the classic forest arena (workspace.Arena.Flora)
	GrassForest = "ground", FlowersA = "ground", FlowersB = "ground", MossPatch = "ground", MushroomsA = "ground",
	FernA = "fern", FernB = "fern",
	GrassTallA = "tall", GrassTallB = "tall", ReedsA = "tall",
	-- Map 1, the Green Land (workspace.Arena.Scatter). Not listed, so never hidden: M1_Gorse_*, M1_Boulder_*, M1_Crag_*
	M1_Wildflowers_A = "ground",
	M1_Heather_A = "heath", M1_Heather_B = "heath",
	M1_TallGrass_A = "tall",
	M1_Fir_A = "tree", M1_Fir_B = "tree", M1_Fir_C = "tree", M1_Pine_A = "tree", M1_Pine_B = "tree",
	M1_Beech_A = "tree", M1_Beech_B = "tree",
}
local CLASSES = { "ground", "fern", "tall", "branches", "detail", "tree", "heath" }
local TIERS = {
	High = { ground = 220, fern = 300, tall = INF, branches = INF, detail = INF, tree = INF, heath = INF },
	Medium = { ground = 130, fern = 180, tall = 260, branches = 320, detail = 220, tree = INF, heath = 320 },
	Low = { ground = 70, fern = 110, tall = 170, branches = 160, detail = 100, tree = 420, heath = 200 },
}
-- the scenery folders of workspace.Arena this controller watches, and how their models are classed
local ROOTS = { Flora = true, Forest = true, Scatter = true }
local ORDER = { "Low", "Medium", "High" }
DetailController.TIERS = TIERS
DetailController.FLORA = FLORA

-- the far canopy shells: hidden inside FAR_HIDE studs of the camera (measured to the part's footprint), shown from FAR_SHOW
local FAR_HIDE, FAR_SHOW = 450, 650
local FAR_ROLE = "FarCanopy"
local farParts = {} -- { part, x0, x1, z0, z1, k (the modifier written) }

-- The skyline from the lobby: workspace.Arena.Skyline is Persistent, so the lobby (8,800 studs east of the horn and
-- 500 studs under the feet of the east tiles) drew the outer slopes of the east mountains as grey shells hanging in
-- its western sky (seen at full quality, 18 Nov). The skyline and the far valley (Persistent too, hidden with it as
-- a precaution) are hidden on this client (LocalTransparencyModifier) while the camera is within SKYLINE_LOBBY
-- studs (flat) of ArenaLayout.LobbyPosition. Every camera in the arena, a spectator's included, is 6,900 studs or
-- more from the lobby, so nothing changes there. Still drawn from the lobby, and left alone: the Peak (a hazy cone)
-- and, once the arena has been visited, the rim of its terrain (a thin band on the horizon).
local SKYLINE_LOBBY = 3000
local skylineHidden: boolean? = nil

local cells = {} -- key -> { x, z, [class] = { parts }, shown = { [class] = bool } }
local modelCell = {} -- model -> { k, groups = { [class] = { parts } } }
local nModels, nCells = 0, 0
local tierName, tierWhy = "High", "default"
local autoDrop = 0
local lastCam: Vector3? = nil
local forceRefresh = true

local function cellKey(ix: number, iz: number): number
	return (ix + 4096) * 8192 + (iz + 4096)
end

local function setShown(list, shown: boolean)
	local v = if shown then 0 else 1
	for _, p in ipairs(list) do
		p.LocalTransparencyModifier = v
	end
end

-- the class of a part of a Forest model (trees, saplings, logs, stumps)
local function forestClass(part: BasePart): string
	local n = part.Name
	if string.find(n, "_Branches", 1, true) then
		return "branches"
	elseif string.find(n, "_Roots", 1, true) or string.find(n, "_Moss", 1, true) then
		return "detail"
	end
	return "tree"
end

local function register(m: Instance, kind: string)
	if not m:IsA("Model") or modelCell[m] then
		return
	end
	-- Flora and Map 1's Scatter: the whole model by its name. Forest: each part by its own name.
	local byName = kind ~= "Forest"
	local floraCls = FLORA[m.Name]
	if byName and not floraCls then
		return
	end
	local groups, any = {}, false
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local cls = if byName then floraCls else forestClass(d)
			local g = groups[cls]
			if not g then
				g = {}
				groups[cls] = g
			end
			table.insert(g, d)
			any = true
		end
	end
	if not any then
		return
	end
	local pos = m:GetPivot().Position
	local ix, iz = math.floor(pos.X / CELL), math.floor(pos.Z / CELL)
	local k = cellKey(ix, iz)
	local c = cells[k]
	if not c then
		c = { x = (ix + 0.5) * CELL, z = (iz + 0.5) * CELL, shown = {} }
		for _, cl in ipairs(CLASSES) do
			c[cl] = {}
			c.shown[cl] = true
		end
		cells[k] = c
		nCells += 1
		-- a cell that streams in after the last refresh starts in the right state
		if lastCam then
			local tier = TIERS[tierName]
			local dx, dz = c.x - lastCam.X, c.z - lastCam.Z
			local d = math.sqrt(dx * dx + dz * dz) - HALF_DIAG
			for _, cl in ipairs(CLASSES) do
				c.shown[cl] = d < tier[cl]
			end
		end
	end
	for cls, parts in pairs(groups) do
		local list = c[cls]
		for _, p in ipairs(parts) do
			table.insert(list, p)
			if not c.shown[cls] then
				p.LocalTransparencyModifier = 1
			end
		end
	end
	modelCell[m] = { k = k, groups = groups }
	nModels += 1
end

local function unregister(m: Instance)
	local e = modelCell[m]
	if not e then
		return
	end
	modelCell[m] = nil
	nModels -= 1
	local c = cells[e.k]
	if c then
		for cls, parts in pairs(e.groups) do
			local list = c[cls]
			for _, p in ipairs(parts) do
				local i = table.find(list, p)
				if i then
					list[i] = list[#list]
					list[#list] = nil
				end
			end
		end
	end
end

local function watchBiome(folder: Instance, kind: string)
	for _, m in ipairs(folder:GetChildren()) do
		register(m, kind)
	end
	folder.ChildAdded:Connect(function(m)
		register(m, kind)
		if not modelCell[m] and m:IsA("Model") then
			task.defer(register, m, kind) -- parts still arriving
		end
	end)
	folder.ChildRemoved:Connect(unregister)
end

-- The far canopy --------------------------------------------------------------------------------------------------

local function addFarPart(d: Instance)
	if not d:IsA("BasePart") then
		return
	end
	if d:GetAttribute("Role") ~= FAR_ROLE and string.sub(d.Name, -7) ~= "_Canopy" then
		return
	end
	for _, e in ipairs(farParts) do
		if e.part == d then
			return
		end
	end
	-- the footprint: the part's box on the ground (the tiles are placed unrotated; a turned one gets its outer box)
	local cf, size = d.CFrame, d.Size
	local rx, rz = cf.RightVector, cf.LookVector
	local ux = cf.UpVector
	local hx = (math.abs(rx.X) * size.X + math.abs(ux.X) * size.Y + math.abs(rz.X) * size.Z) / 2
	local hz = (math.abs(rx.Z) * size.X + math.abs(ux.Z) * size.Y + math.abs(rz.Z) * size.Z) / 2
	table.insert(farParts, { part = d, x0 = cf.Position.X - hx, x1 = cf.Position.X + hx, z0 = cf.Position.Z - hz,
		z1 = cf.Position.Z + hz, k = -1 })
end

local function watchFar(holder: Instance)
	for _, d in ipairs(holder:GetDescendants()) do
		addFarPart(d)
	end
	holder.DescendantAdded:Connect(function(d)
		addFarPart(d)
		forceRefresh = true
	end)
end

local function refreshFar(p: Vector3)
	if skylineHidden then
		return -- the camera is at the lobby: the whole far valley is hidden there (refreshSkyline)
	end
	for i = #farParts, 1, -1 do
		local e = farParts[i]
		if not e.part.Parent then
			table.remove(farParts, i)
		else
			local dx = math.max(e.x0 - p.X, 0, p.X - e.x1)
			local dz = math.max(e.z0 - p.Z, 0, p.Z - e.z1)
			local d = math.sqrt(dx * dx + dz * dz)
			-- 1 = hidden, 0 = shown; in steps of 1/20 so a walk writes a few times, not every pass
			local k = math.floor(math.clamp((FAR_SHOW - d) / (FAR_SHOW - FAR_HIDE), 0, 1) * 20 + 0.5) / 20
			if k ~= e.k then
				e.k = k
				e.part.LocalTransparencyModifier = k
			end
		end
	end
end

-- The skyline is hidden while the camera is at the lobby (see SKYLINE_LOBBY). `again` writes the hidden state once
-- more, for skyline parts that arrived after the last pass.
local function refreshSkyline(arena: Instance, again: boolean)
	local camera = workspace.CurrentCamera
	local holder = arena:FindFirstChild("Skyline")
	if not camera or not holder then
		return
	end
	local p = camera.CFrame.Position
	local lobby = ArenaLayout.LobbyPosition
	local dx, dz = p.X - lobby.X, p.Z - lobby.Z
	local hide = dx * dx + dz * dz < SKYLINE_LOBBY * SKYLINE_LOBBY
	if hide == skylineHidden and not (hide and again) then
		return
	end
	skylineHidden = hide
	local v = if hide then 1 else 0
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = v
		end
	end
	-- the far valley's tiles are Persistent too: hidden with the skyline
	local far = arena:FindFirstChild("FarValley")
	if far then
		for _, d in ipairs(far:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = v
			end
		end
	end
	if not hide then
		-- back at the arena: the canopy shells take their distance rule again at once
		for _, e in ipairs(farParts) do
			e.k = -1
		end
		refreshFar(p)
	end
end

-- the player's graphics level 1-10, or nil on Automatic
local function savedLevel(): number?
	local ok, q = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and typeof(q) == "EnumItem" and q ~= Enum.SavedQualitySetting.Automatic then
		return q.Value
	end
	return nil
end

-- Studio's render quality 1-21, or nil (Automatic, or not exposed to this script)
local function studioLevel(): number?
	if not RunService:IsStudio() then
		return nil
	end
	local ok, q = pcall(function()
		return settings().Rendering.QualityLevel
	end)
	if ok and typeof(q) == "EnumItem" and q ~= Enum.QualityLevel.Automatic then
		return q.Value
	end
	return nil
end

-- the engine's own running quality level 1-21 (Stats.FrameRateManager.AverageQualityLevel), when readable
local function engineLevel(): number?
	local ok, v = pcall(function()
		local frm = game:GetService("Stats"):FindFirstChild("FrameRateManager")
		local item = frm and frm:FindFirstChild("AverageQualityLevel")
		return item and item:GetValue()
	end)
	if ok and type(v) == "number" and v >= 1 then
		return v
	end
	return nil
end

local function band21(q: number): string
	return if q <= 6 then "Low" elseif q <= 13 then "Medium" else "High"
end

local engineBand, pendingBand, pendingSince = nil, nil, 0
local function chooseTier(): (string, string)
	-- Studio only: a test attribute left in a saved place must not force every player's tier (Map1.Audit lists it too)
	local forced = if IS_STUDIO then workspace:GetAttribute("DetailTier") else nil
	if type(forced) == "string" and TIERS[forced] then
		return forced, "workspace DetailTier"
	end
	local s = savedLevel()
	if s then
		return (if s <= 3 then "Low" elseif s <= 6 then "Medium" else "High"), "graphics level " .. s
	end
	local q = studioLevel()
	if q then
		return band21(q), "Studio quality level " .. q
	end
	local e = engineLevel()
	if e then
		-- follow the engine's automatic level; a new band must hold for 3 s, so a dip doesn't flicker the scenery
		local b = band21(e)
		if engineBand == nil then
			engineBand = b
		elseif b ~= engineBand then
			if pendingBand ~= b then
				pendingBand, pendingSince = b, os.clock()
			elseif os.clock() - pendingSince >= 3 then
				engineBand, pendingBand = b, nil
			end
		else
			pendingBand = nil
		end
		return engineBand, string.format("engine quality level %.0f", e)
	end
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local base = if touchOnly then 2 else 3
	local i = math.max(1, base - autoDrop)
	return ORDER[i], (if touchOnly then "automatic (touch device)" else "automatic") .. (if autoDrop > 0 then (", -" .. autoDrop .. " for frame rate") else "")
end

function DetailController.refresh()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local p = cam.CFrame.Position
	if not forceRefresh and lastCam and (p - lastCam).Magnitude < 6 then
		return
	end
	forceRefresh = false
	lastCam = p
	refreshFar(p)
	local tier = TIERS[tierName]
	for _, c in pairs(cells) do
		local dx, dz = c.x - p.X, c.z - p.Z
		local d = math.sqrt(dx * dx + dz * dz) - HALF_DIAG
		for _, cls in ipairs(CLASSES) do
			local want = d < tier[cls]
			if want ~= c.shown[cls] then
				c.shown[cls] = want
				setShown(c[cls], want)
			end
		end
	end
end

function DetailController.stats()
	local hidden = 0
	for _, c in pairs(cells) do
		for _, cls in ipairs(CLASSES) do
			if not c.shown[cls] then
				hidden += #c[cls]
			end
		end
	end
	local farHidden = 0
	for _, e in ipairs(farParts) do
		if e.k >= 1 then
			farHidden += 1
		end
	end
	return { tier = tierName, why = tierWhy, models = nModels, cells = nCells, hidden = hidden, shaders = shaderName, shaderDevice = shaderDevice,
		farCanopy = #farParts, farCanopyHidden = farHidden }
end

-- The shader tier and the tier this device has on Auto (see the header).
local SHADER_OF = { Low = "Phone", Medium = "Mid", High = "High" }
local SHADER_TIERS = { Off = true, Phone = true, Mid = true, High = true }
local shaderName, shaderDevice = "", ""
local function chooseShaders(): (string, string)
	local device = SHADER_OF[tierName] or "High"
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if touchOnly and savedLevel() == nil and not (IS_STUDIO and workspace:GetAttribute("DetailTier") ~= nil) then
		device = "Phone" -- a phone on automatic graphics: the planned low look until its player asks for more
	end
	if RunService:IsStudio() then
		local dev = workspace:GetAttribute("DevShaders")
		if type(dev) == "string" and SHADER_TIERS[dev] then
			return dev, if dev == "Off" then device else dev
		end
	end
	local setting = tonumber(ClientState.settings and ClientState.settings.shaders) or 1
	if setting <= 0 then
		return "Off", device
	elseif setting >= 2 then
		return "High", device
	end
	return device, device
end

local function applyTier()
	local name, why = chooseTier()
	local lp = Players.LocalPlayer
	if name ~= tierName or why ~= tierWhy then
		tierName, tierWhy = name, why
		forceRefresh = true
		if lp then
			lp:SetAttribute("DetailTier", tierName)
			lp:SetAttribute("DetailTierWhy", tierWhy)
		end
	end
	local shader, device = chooseShaders()
	if shader ~= shaderName or device ~= shaderDevice then
		shaderName, shaderDevice = shader, device
		if lp then
			lp:SetAttribute("ShaderTier", shader)
			lp:SetAttribute("ShaderDevice", device)
		end
	end
end

function DetailController.Init(_controllers)
	-- nothing that yields: the arena is found in Start
end

function DetailController.Start()
	local arena = workspace:WaitForChild("Arena", 60)
	while not arena do
		arena = workspace:WaitForChild("Arena", 60)
	end
	-- The classic arena dresses Flora and Forest (a Folder per biome); Map 1 dresses Scatter (a Folder per cell).
	-- Whichever are there are watched, and any that arrives later: nothing waits for a folder this map does not have.
	local watching = {}
	local function watchRoot(root: Instance)
		local kind = root.Name
		if not ROOTS[kind] or not root:IsA("Folder") or watching[root] then
			return
		end
		watching[root] = true
		if kind == "Scatter" then
			-- the builder's own list, "Name=class;Name=class": it adds to FLORA (classes this table does not have are skipped)
			local listed = root:GetAttribute("DetailClasses")
			if type(listed) == "string" then
				for name, cls in string.gmatch(listed, "([^=;]+)=([^=;]+)") do
					if TIERS.High[cls] ~= nil then
						FLORA[name] = cls
					end
				end
			end
		end
		for _, sub in ipairs(root:GetChildren()) do
			watchBiome(sub, kind)
		end
		root.ChildAdded:Connect(function(sub)
			if sub:IsA("Folder") then
				watchBiome(sub, kind)
			end
		end)
	end
	for _, child in ipairs(arena:GetChildren()) do
		watchRoot(child)
	end
	arena.ChildAdded:Connect(watchRoot)
	-- Map 1's far valley (a Persistent model: there from the start, or arriving a moment later)
	local function watchFarHolder(child: Instance)
		if child.Name == "FarValley" and child:IsA("Model") then
			watchFar(child)
			forceRefresh = true
		end
	end
	for _, child in ipairs(arena:GetChildren()) do
		watchFarHolder(child)
	end
	arena.ChildAdded:Connect(watchFarHolder)
	task.delay(30, function()
		if next(watching) == nil then
			warn("[DetailController] workspace.Arena has no Flora, Forest or Scatter folder: the scenery is not scaled")
		end
	end)
	workspace:GetAttributeChangedSignal("DetailTier"):Connect(applyTier)
	workspace:GetAttributeChangedSignal("DevShaders"):Connect(applyTier)
	ClientState.settingsChanged:Connect(applyTier)
	pcall(function()
		UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"):Connect(applyTier)
	end)
	do
		-- which quality sources this client can read (for tests)
		local okS, vS = pcall(function()
			return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Name
		end)
		local okR, vR = pcall(function()
			return settings().Rendering.QualityLevel.Name
		end)
		local lp = Players.LocalPlayer
		if lp then
			lp:SetAttribute("DetailSources", string.format("saved %s; studio %s; engine %s", if okS then tostring(vS) else "unreadable",
				if okR then tostring(vR) else "unreadable", if engineLevel() then tostring(engineLevel()) else "unreadable"))
		end
	end
	applyTier()
	DetailController.refresh()
	refreshSkyline(arena, true)
	-- every frame (a distance test; parts are written only when the answer changes): a camera cut between the lobby
	-- and the arena never shows a frame with the wrong skyline
	RunService.RenderStepped:Connect(function()
		refreshSkyline(arena, false)
	end)

	-- the frame-rate step: live clients on Automatic only (Studio's unfocused window is throttled to ~15 fps)
	local frames, elapsed, lowFor, highFor = 0, 0, 0, 0
	if not RunService:IsStudio() then
		RunService.RenderStepped:Connect(function(dt)
			frames += 1
			elapsed += dt
		end)
	end
	local tick = 0
	while true do
		task.wait(0.25)
		tick += 1
		if tick % 4 == 0 then
			if elapsed > 0 and savedLevel() == nil then
				local fps = frames / elapsed
				lowFor = if fps < 40 then lowFor + 1 else 0
				highFor = if fps > 55 then highFor + 1 else 0
				if lowFor >= 6 and autoDrop < 2 then
					autoDrop += 1
					lowFor = 0
				elseif highFor >= 30 and autoDrop > 0 then
					autoDrop -= 1
					highFor = 0
				end
			end
			frames, elapsed = 0, 0
			applyTier()
			local lp = Players.LocalPlayer
			if lp then
				local st = DetailController.stats()
				lp:SetAttribute("DetailHidden", st.hidden)
				lp:SetAttribute("DetailFarHidden", string.format("%d/%d", st.farCanopyHidden, st.farCanopy))
			end
		end
		DetailController.refresh()
		if tick % 4 == 0 then
			refreshSkyline(arena, true)
		end
	end
end

return DetailController
