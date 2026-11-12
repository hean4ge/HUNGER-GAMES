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

	  tier     ground   fern   tall   branches   detail   tree
	  High     220      300    -      -          -        -       (- = never hidden)
	  Medium   130      180    260    320        220      -
	  Low       70      110    170    160        100      420

	The tier, first match wins:
	  1 workspace attribute DetailTier = "Low" | "Medium" | "High" (tests and previews)
	  2 the player's graphics level, UserGameSettings.SavedQualityLevel: 1-3 Low, 4-6 Medium, 7-10 High
	  3 in Studio, the render quality level when Studio exposes it to scripts (settings().Rendering.QualityLevel):
	    1-6 Low, 7-13 Medium, 14-21 High (a LocalScript can't read it in current Studio builds)
	  4 the engine's running quality level (Stats.FrameRateManager.AverageQualityLevel, same bands) when readable
	  5 otherwise: High on PC and consoles, Medium on touch-only devices, and one tier lower after the frame rate stays
	    under 40 fps for 6 s (back up after 30 s over 55 fps). Off in Studio, whose unfocused window is throttled.
	The chosen tier is published as LocalPlayer attributes DetailTier and DetailTierWhy, and DetailSources says which
	of the sources above this client can read (this client only).

	Bookkeeping: models are bucketed into 40-stud cells as they stream in (ChildAdded on the Flora and Forest biome
	folders) and dropped as they stream out. Every 0.25 s, once the camera has moved 6 studs or the tier changed, only
	the cells whose distance band changed are flipped.
	API (for tests): DetailController.stats() -> { tier, why, models, cells, hidden }, DetailController.refresh().
	The stats are also published as LocalPlayer attribute DetailHidden (parts hidden now).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DetailController = {}

local CELL = 40
local HALF_DIAG = CELL * 0.7071
local INF = math.huge
-- Flora models: one class for the whole model
local FLORA = {
	GrassForest = "ground", FlowersA = "ground", FlowersB = "ground", MossPatch = "ground", MushroomsA = "ground",
	FernA = "fern", FernB = "fern",
	GrassTallA = "tall", GrassTallB = "tall", ReedsA = "tall",
}
local CLASSES = { "ground", "fern", "tall", "branches", "detail", "tree" }
local TIERS = {
	High = { ground = 220, fern = 300, tall = INF, branches = INF, detail = INF, tree = INF },
	Medium = { ground = 130, fern = 180, tall = 260, branches = 320, detail = 220, tree = INF },
	Low = { ground = 70, fern = 110, tall = 170, branches = 160, detail = 100, tree = 420 },
}
local ORDER = { "Low", "Medium", "High" }
DetailController.TIERS = TIERS
DetailController.FLORA = FLORA

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
	local floraCls = FLORA[m.Name]
	if kind == "Flora" and not floraCls then
		return
	end
	local groups, any = {}, false
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local cls = if kind == "Flora" then floraCls else forestClass(d)
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
	local forced = workspace:GetAttribute("DetailTier")
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
	return { tier = tierName, why = tierWhy, models = nModels, cells = nCells, hidden = hidden }
end

local function applyTier()
	local name, why = chooseTier()
	if name ~= tierName or why ~= tierWhy then
		tierName, tierWhy = name, why
		forceRefresh = true
		local lp = Players.LocalPlayer
		if lp then
			lp:SetAttribute("DetailTier", tierName)
			lp:SetAttribute("DetailTierWhy", tierWhy)
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
	for _, kind in ipairs({ "Flora", "Forest" }) do
		local root = arena:WaitForChild(kind, 30)
		if root then
			for _, sub in ipairs(root:GetChildren()) do
				watchBiome(sub, kind)
			end
			root.ChildAdded:Connect(function(sub)
				if sub:IsA("Folder") then
					watchBiome(sub, kind)
				end
			end)
		else
			warn("[DetailController] no workspace.Arena." .. kind .. ": it is not scaled")
		end
	end
	workspace:GetAttributeChangedSignal("DetailTier"):Connect(applyTier)
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
				lp:SetAttribute("DetailHidden", DetailController.stats().hidden)
			end
		end
		DetailController.refresh()
	end
end

return DetailController
