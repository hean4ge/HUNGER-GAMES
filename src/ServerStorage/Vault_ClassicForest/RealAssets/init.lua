--[[
	RealAssets - edit-time builder for the realistic world-set templates in ServerStorage.MeshAssets:
	  MeshAssets.<Set>.<Asset>   Set = TreesReal, GroundReal, LandmarksReal, BuildingsReal, PropsReal
	(ItemsReal is built by ItemAssets, not here.)
	Source art: the Blender exports BlenderExports/*.glb (art/blender/*_real.py), uploaded once each through Open
	Cloud as Model assets (Manifest.SOURCES). Their raw inserts are kept in ServerStorage.MeshImports (packages; never
	edit them; build() loads a missing one with InsertService). Surfaces use one shared image id per PNG
	(Manifest.IMAGES: ColorMap/NormalMap from the importer's own uploads, verified pixel-exact; RoughnessMap and
	MetalnessMap from the separate grayscale PNGs). Part flags, tags and attachments come from the Manifest child
	module, generated from BlenderExports/*.manifest.json (LS-Real-1) and art/manifests/RealSets.assetIds.json by
	art/blender/rbx_real_manifest.py. Nothing here runs at game time.

	Run in Edit mode (command bar or execute_luau; require a Clone so Studio does not serve a cached copy):
	  print(require(game.ServerStorage.WorldGen.RealAssets:Clone()).build())                       -- every set
	  print(require(game.ServerStorage.WorldGen.RealAssets:Clone()).build({ sets = { "PropsReal" } }))

	Template contract (one Model per asset):
	  WorldPivot   CFrame.identity = the manifest origin: base centre on the ground, front = LookVector (-Z).
	               Place a copy with template:Clone():PivotTo(groundCFrame). Rocks, cliffs, trunks and roots continue
	               below y = 0 on purpose (they seat into slopes); plant cards sink at most 0.07.
	  PrimaryPart  the asset's main part (first visual part in manifest order); it carries every manifest attachment
	               (Perch1-4, Plate_1..24, CrateSlot_1-4, Beacon, Stand, Door, Hearth, LadderBase/Top, EndA/B,
	               FireCenter, Glow, HangPoint, SignFace, Seat_n, CaveEntrance, ...) at pivot * lookAt(pos, pos+look, up).
	  MeshParts    named as in the manifest, Anchored, RenderFidelity Automatic, DoubleSided false, Material /
	               Color (fallback) / Transparency / CastShadow / CanCollide / CollisionFidelity / CanQuery / CanTouch
	               from the manifest, attribute Role, one SurfaceAppearance (Color = manifest tint, AlphaMode as given).
	  Embers       Material Neon, Color (255,128,48), no SurfaceAppearance, no shadow; a warm PointLight "EmberLight"
	               sits on the asset's light attachment (LIGHTS below).
	  Colliders    role Collider: Transparency 1, no shadow; they carry all collision and raycasts of that asset.
	  Ladders      HunterCabin / Watchtower get an invisible TrussPart "LadderTruss" from LadderBase to LadderTop
	               (sizes snap to 2 studs); the ladder mesh is visual only.
	  Tags         CollectionService: Plinth (asset); Climbable, Floor, Lid, LadderVisual, HideSpot (parts). Every
	               other manifest tag is descriptive: attribute Tags (comma list) on the model or part.
	  Attributes   AssetId (the GLB's Model asset id), Source, Set, Kind, Tags, Size, BoundsMin, BoundsMax, Tris.
]]
local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local Manifest = require(script:WaitForChild("Manifest"))

local RealAssets = {}

RealAssets.WORLD_SETS = { "TreesReal", "GroundReal", "LandmarksReal", "BuildingsReal", "PropsReal" }

-- CollectionService tags the game reads; every other manifest tag only becomes an attribute.
local GAME_TAGS = { Plinth = true, Climbable = true, Floor = true, Lid = true, LadderVisual = true, HideSpot = true }

-- Warm light at each asset's light attachment (manifest notes; tune in look-dev, not here). Ember parts take their
-- Neon colour (255,128,48) from the manifest rgb.
local LIGHTS: { [string]: { att: string, range: number, brightness: number, color: Color3 } } = {
	Spire = { att = "Beacon", range = 60, brightness = 2, color = Color3.fromRGB(255, 150, 80) },
	Brazier = { att = "Fire", range = 20, brightness = 1.5, color = Color3.fromRGB(255, 150, 80) },
	Pavilion = { att = "Lantern", range = 18, brightness = 1.2, color = Color3.fromRGB(255, 170, 100) },
	LobbyGate = { att = "Lantern", range = 16, brightness = 1.2, color = Color3.fromRGB(255, 170, 100) },
	Campfire = { att = "FireCenter", range = 22, brightness = 1.6, color = Color3.fromRGB(255, 150, 80) },
	Lantern = { att = "Glow", range = 18, brightness = 1.2, color = Color3.fromRGB(255, 170, 100) },
}
-- Plinth_Ember has no light on purpose: 24 shadowed lights round the plaza would blow the local-light budget.

local BOUNDS_TOLERANCE = 0.06 -- studs, template bounds vs manifest boundsMin/boundsMax

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function attachmentFrame(a: any): CFrame
	local pos = vec(a.pos)
	return CFrame.lookAt(pos, pos + vec(a.look), vec(a.up))
end

-- World-axis bounds of a box of `size` at `frame`.
local function boxBounds(frame: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size / 2
	local r = frame.Rotation
	local e = Vector3.new(
		math.abs(r.RightVector.X) * h.X + math.abs(r.UpVector.X) * h.Y + math.abs(r.LookVector.X) * h.Z,
		math.abs(r.RightVector.Y) * h.X + math.abs(r.UpVector.Y) * h.Y + math.abs(r.LookVector.Y) * h.Z,
		math.abs(r.RightVector.Z) * h.X + math.abs(r.UpVector.Z) * h.Y + math.abs(r.LookVector.Z) * h.Z
	)
	return frame.Position - e, frame.Position + e
end

local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and not f:IsA("Folder") then
		f = nil
	end
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

local function image(key: string?): string
	if not key then
		return ""
	end
	local id = Manifest.IMAGES[key]
	assert(id, "no image id for " .. key)
	return "rbxassetid://" .. tostring(id)
end

-- The raw insert of one uploaded GLB (kept in ServerStorage.MeshImports, loaded once if missing).
local function sourceModel(key: string): Instance
	local info = Manifest.SOURCES[key]
	assert(info, "unknown source " .. key)
	local imports = ensureFolder(ServerStorage, "MeshImports")
	local existing = imports:FindFirstChild(info.name)
	if existing then
		return existing
	end
	local loaded = InsertService:LoadAsset(info.assetId)
	local root = loaded:GetChildren()[1] or loaded
	root.Name = info.name
	root.Parent = imports
	if loaded ~= root then
		loaded:Destroy()
	end
	return root
end

-- partName -> MeshPart for every mesh in a source.
local function meshIndex(source: Instance): { [string]: MeshPart }
	local index = {}
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("MeshPart") then
			index[d.Name] = d
		end
	end
	return index
end

-- Where each manifest asset of one GLB sits inside its raw import, as its pivot frame (the asset's origin and axes
-- in world space). The importer keeps the GLB layout (assets in a row along +X) but turns it 180 degrees about the
-- vertical axis and bakes that turn into the mesh data (every MeshPart reads the same rotation R0: identity straight
-- from the importer, or the yaw insert_asset gave the whole model). In R0's frame the parts are axis-aligned and
-- their bounds exact; the baked turn is read off the row of assets and must be a multiple of 90 degrees.
-- Returns asset name -> pivot CFrame (world), the measured turn in degrees, and a list of problems.
local function locateAssets(assets: { [string]: any }, index: { [string]: MeshPart }): ({ [string]: CFrame }, number, { string })
	local problems = {}
	local centres: { [string]: Vector3 } = {}
	local sizes: { [string]: Vector3 } = {}
	local R0: CFrame? = nil
	for _, a in pairs(assets) do
		for _, p in ipairs(a.parts) do
			if index[p.name] then
				R0 = index[p.name].CFrame.Rotation
				break
			end
		end
		if R0 then
			break
		end
	end
	local base = R0 or CFrame.identity
	local toLocal = base:Inverse()
	for name, a in pairs(assets) do
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		local found = 0
		for _, p in ipairs(a.parts) do
			local part = index[p.name]
			if part then
				local rel = toLocal * part.CFrame
				if rel.LookVector.Z > -0.9999 or rel.UpVector.Y < 0.9999 then
					table.insert(problems, p.name .. " is turned differently from the rest of the import")
				end
				-- the manifest bounds cover the visual meshes only: colliders may reach beyond them (Spire, Brazier, ...)
				if p.role ~= "Collider" then
					found += 1
					local h = part.Size / 2
					lo = lo:Min(rel.Position - h)
					hi = hi:Max(rel.Position + h)
				end
			else
				table.insert(problems, "missing mesh " .. p.name)
			end
		end
		if found > 0 then
			centres[name] = (lo + hi) / 2
			sizes[name] = hi - lo
		end
	end
	local first, last
	for name, a in pairs(assets) do
		if centres[name] then
			if not first or a.origin[1] < assets[first].origin[1] then
				first = name
			end
			if not last or a.origin[1] > assets[last].origin[1] then
				last = name
			end
		end
	end
	local function manifestCentre(name: string): Vector3
		local a = assets[name]
		return vec(a.origin) + (vec(a.bmin) + vec(a.bmax)) / 2
	end
	local yaw = 0
	if first and last and first ~= last then
		local dm = manifestCentre(last) - manifestCentre(first)
		local dw = centres[last] - centres[first]
		yaw = math.atan2(-dw.Z, dw.X) - math.atan2(-dm.Z, dm.X)
		local snapped = math.round(yaw / (math.pi / 2)) * (math.pi / 2)
		if math.abs(snapped - yaw) > math.rad(1) then
			table.insert(problems, string.format("import turned %.1f degrees (not a multiple of 90)", math.deg(yaw)))
		end
		yaw = snapped
	end
	local R = CFrame.Angles(0, yaw, 0)
	local pivots = {}
	for name, a in pairs(assets) do
		if centres[name] then
			local c = (vec(a.bmin) + vec(a.bmax)) / 2
			pivots[name] = base * CFrame.new(centres[name] - R:VectorToWorldSpace(c)) * R
			local size = R:VectorToObjectSpace(sizes[name])
			size = Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z))
			local want = vec(a.bmax) - vec(a.bmin)
			if (size - want).Magnitude > 0.02 then
				table.insert(problems, string.format("%s measures %s, manifest %s", name, tostring(size), tostring(want)))
			end
		end
	end
	return pivots, (math.round(math.deg(yaw)) + 360) % 360, problems
end

local function joinTags(tags: { string }?, skipGame: boolean): string
	local out = {}
	for _, t in ipairs(tags or {}) do
		if not (skipGame and GAME_TAGS[t]) then
			table.insert(out, t)
		end
	end
	return table.concat(out, ",")
end

local function applySurface(part: MeshPart, info: any)
	local s = Manifest.SURF[info.surf]
	local sa = Instance.new("SurfaceAppearance")
	sa.ColorMap = image(s[1])
	sa.NormalMap = image(s[2])
	sa.RoughnessMap = image(s[3])
	sa.MetalnessMap = image(s[4] or nil)
	sa.AlphaMode = (Enum.AlphaMode :: any)[info.alpha] or Enum.AlphaMode.Overlay
	sa.Color = rgb(info.tint)
	sa.Parent = part
end

-- CollisionFidelity ignores direct writes (it stays Default, without an error). The physics is built with the wanted
-- fidelity through AssetService:CreateMeshPartAsync (about 1.4 s per mesh, so up to 8 run at once) and copied onto
-- the template part with ApplyMesh. Edit time only. Returns part name -> temporary MeshPart.
local function prefetchPhysics(group: { [string]: any }, index: { [string]: MeshPart }, only: { [string]: boolean }?): { [string]: MeshPart }
	local jobs = {}
	for name, a in pairs(group) do
		if not only or only[name] then
			for _, info in ipairs(a.parts) do
				local source = index[info.name]
				local fidelity = (Enum.CollisionFidelity :: any)[info.collision] or Enum.CollisionFidelity.Box
				if source and source.CollisionFidelity ~= fidelity then
					table.insert(jobs, { name = info.name, content = source.MeshContent, fidelity = fidelity })
				end
			end
		end
	end
	local results: { [string]: MeshPart } = {}
	local running, nextJob = 0, 1
	while nextJob <= #jobs or running > 0 do
		while running < 8 and nextJob <= #jobs do
			local job = jobs[nextJob]
			nextJob += 1
			running += 1
			task.spawn(function()
				local ok, tmp = pcall(function()
					return AssetService:CreateMeshPartAsync(job.content, {
						CollisionFidelity = job.fidelity,
						RenderFidelity = Enum.RenderFidelity.Automatic,
					})
				end)
				if ok then
					results[job.name] = tmp
				end
				running -= 1
			end)
		end
		task.wait()
	end
	return results
end

-- A clean copy of an imported mesh with the manifest's look and flags. `frame` is its CFrame in the template.
local function meshCopy(source: MeshPart, info: any, frame: CFrame, physics: { [string]: MeshPart }): MeshPart
	local part = source:Clone()
	for _, child in ipairs(part:GetChildren()) do
		child:Destroy() -- importer leftovers (its SurfaceAppearance with packed-map roughness, welds, attachments)
	end
	local tmp = physics[info.name]
	if tmp then
		part:ApplyMesh(tmp) -- collision geometry at the manifest's CollisionFidelity
		tmp:Destroy()
		physics[info.name] = nil
	end
	part.Name = info.name
	part.TextureID = ""
	part.CFrame = frame
	part.Anchored = true
	pcall(function()
		part.DoubleSided = false -- cards carry real back faces
	end)
	pcall(function()
		part.RenderFidelity = Enum.RenderFidelity.Automatic
	end)
	part.CastShadow = info.shadow and not info.neon
	part.CanCollide = info.collide
	part.CanQuery = info.query or info.collide
	part.CanTouch = info.touch
	if info.neon then
		part.Material = Enum.Material.Neon
		part.Color = rgb(info.rgb)
		part.Transparency = 0
	else
		part.Material = (Enum.Material :: any)[info.mat] or Enum.Material.SmoothPlastic
		part.Color = rgb(info.rgb)
		part.Transparency = info.transparency
		if info.surf > 0 then
			applySurface(part, info)
		end
	end
	part:SetAttribute("Role", info.role)
	for _, t in ipairs(info.tags or {}) do
		if GAME_TAGS[t] then
			CollectionService:AddTag(part, t)
		end
	end
	local extra = joinTags(info.tags, true)
	if extra ~= "" then
		part:SetAttribute("Tags", extra)
	end
	return part
end

-- An invisible native-climb TrussPart from LadderBase up to LadderTop (TrussPart sizes snap to 2 studs).
local function ladderTruss(a: any): TrussPart?
	local base, top = a.att.LadderBase, a.att.LadderTop
	if not (base and top) then
		return nil
	end
	local b, t = vec(base.pos), vec(top.pos)
	local height = math.max(2, math.ceil((t.Y - b.Y) / 2 - 1e-3) * 2)
	local truss = Instance.new("TrussPart")
	truss.Name = "LadderTruss"
	truss.Size = Vector3.new(2, height, 2)
	truss.CFrame = CFrame.lookAt(b, b + vec(base.look), Vector3.yAxis) * CFrame.new(0, height / 2, 0)
	truss.Transparency = 1
	truss.CastShadow = false
	truss.Anchored = true
	truss.CanCollide = true
	truss.CanQuery = true
	truss.CanTouch = true
	truss.Material = Enum.Material.Wood
	truss:SetAttribute("Role", "LadderTruss")
	return truss
end

local function buildAsset(setName: string, name: string, a: any, index: { [string]: MeshPart }, pivot: CFrame, physics: { [string]: MeshPart }): (Model, { string })
	local problems = {}
	local toAsset = pivot:Inverse()
	local model = Instance.new("Model")
	model.Name = name
	local main: BasePart? = nil
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local built = 0
	for _, info in ipairs(a.parts) do
		local source = index[info.name]
		if source then
			local part = meshCopy(source, info, toAsset * source.CFrame, physics)
			part.Parent = model
			built += 1
			if info.role ~= "Collider" then -- the manifest bounds are visual only
				local p0, p1 = boxBounds(part.CFrame, part.Size)
				lo = lo:Min(p0)
				hi = hi:Max(p1)
			end
			if not main and not info.neon and info.role ~= "Collider" then
				main = part
			end
		else
			table.insert(problems, "missing mesh " .. info.name)
		end
	end
	main = main or model:FindFirstChildWhichIsA("BasePart")
	if built ~= #a.parts then
		table.insert(problems, string.format("%d of %d parts", built, #a.parts))
	end
	if (lo - vec(a.bmin)).Magnitude > BOUNDS_TOLERANCE or (hi - vec(a.bmax)).Magnitude > BOUNDS_TOLERANCE then
		table.insert(problems, string.format("bounds %s .. %s, manifest %s .. %s", tostring(lo), tostring(hi),
			tostring(vec(a.bmin)), tostring(vec(a.bmax))))
	end
	if main then
		for attName, att in pairs(a.att) do
			local at = Instance.new("Attachment")
			at.Name = attName
			at.Parent = main
			at.WorldCFrame = attachmentFrame(att)
		end
		local light = LIGHTS[name]
		if light then
			local host = main:FindFirstChild(light.att)
			if host then
				local pl = Instance.new("PointLight")
				pl.Name = "EmberLight"
				pl.Color = light.color
				pl.Range = light.range
				pl.Brightness = light.brightness
				pl.Shadows = true
				pl.Parent = host
			else
				table.insert(problems, "light attachment " .. light.att .. " missing")
			end
		end
		model.PrimaryPart = main
		-- the pivot lives on the PrimaryPart: put it on the template origin explicitly (a WorldPivot write on an
		-- unparented model did not reach PivotOffset)
		main.PivotOffset = main.CFrame:Inverse()
	end
	local truss = ladderTruss(a)
	if truss then
		truss.Parent = model
	end
	model.WorldPivot = CFrame.identity
	for _, t in ipairs(a.tags or {}) do
		if GAME_TAGS[t] then
			CollectionService:AddTag(model, t)
		end
	end
	local src = Manifest.SOURCES[a.src]
	model:SetAttribute("AssetId", src.assetId)
	model:SetAttribute("Source", src.name)
	model:SetAttribute("Set", setName)
	model:SetAttribute("Kind", a.kind)
	model:SetAttribute("Tags", joinTags(a.tags, false))
	model:SetAttribute("BoundsMin", vec(a.bmin))
	model:SetAttribute("BoundsMax", vec(a.bmax))
	model:SetAttribute("Size", vec(a.bmax) - vec(a.bmin))
	model:SetAttribute("Tris", a.tris)
	return model, problems
end

-- Moves the previous build of a template to ServerStorage.Archive_v1.MeshAssets_prev.<Set> (only the latest previous
-- build is kept there; templates are generated output and can be rebuilt from the sources at any time).
local function archive(old: Instance, setName: string)
	local arch = ensureFolder(ensureFolder(ensureFolder(ServerStorage, "Archive_v1"), "MeshAssets_prev"), setName)
	local prev = arch:FindFirstChild(old.Name)
	if prev then
		prev:Destroy()
	end
	old.Parent = arch
end

-- options: sets = { "TreesReal", ... } (default all five), target = parent of MeshAssets (default ServerStorage),
--          only = { [assetName] = true } (rebuild just these)
function RealAssets.build(options: { sets: { string }?, target: Instance?, only: { [string]: boolean }? }?): string
	local sets = (options and options.sets) or RealAssets.WORLD_SETS
	local target = (options and options.target) or ServerStorage
	local only = options and options.only
	local lines = {}
	local function note(fmt: string, ...)
		table.insert(lines, string.format(fmt, ...))
	end
	local root = ensureFolder(target, "MeshAssets")
	local totalModels, totalParts = 0, 0
	for _, setName in ipairs(sets) do
		local assets = Manifest.SETS[setName]
		assert(assets, "unknown set " .. setName)
		local folder = ensureFolder(root, setName)
		-- group the set's assets by source GLB (GroundReal spans three)
		local bySource: { [string]: { [string]: any } } = {}
		for name, a in pairs(assets) do
			bySource[a.src] = bySource[a.src] or {}
			bySource[a.src][name] = a
		end
		local built, parts = 0, 0
		for srcKey, group in pairs(bySource) do
			local index = meshIndex(sourceModel(srcKey))
			local pivots, turn, problems = locateAssets(group, index)
			note("%s/%s: import turned %d degrees about Y (undone)", setName, srcKey, turn)
			for _, p in ipairs(problems) do
				note("%s/%s: %s", setName, srcKey, p)
			end
			local physics = prefetchPhysics(group, index, only)
			local names = {}
			for name in pairs(group) do
				table.insert(names, name)
			end
			table.sort(names)
			for _, name in ipairs(names) do
				if not only or only[name] then
					local pivot = pivots[name]
					if pivot then
						local model, assetProblems = buildAsset(setName, name, group[name], index, pivot, physics)
						for _, p in ipairs(assetProblems) do
							note("%s.%s: %s", setName, name, p)
						end
						local old = folder:FindFirstChild(name)
						if old then
							archive(old, setName)
						end
						model.Parent = folder
						built += 1
						parts += #group[name].parts
						task.wait()
					else
						note("%s.%s: not found in the import", setName, name)
					end
				end
			end
		end
		note("%s: %d templates, %d manifest parts", setName, built, parts)
		totalModels += built
		totalParts += parts
	end
	note("total: %d templates, %d parts in ServerStorage.MeshAssets", totalModels, totalParts)
	return table.concat(lines, "\n")
end

-- Reads every template back and compares it with the manifest: part count and names, flags, fidelities, materials,
-- SurfaceAppearance ids / AlphaMode / tint, attachments, tags, pivot and bounds. Returns a report (problems first).
function RealAssets.verify(options: { sets: { string }? }?): string
	local sets = (options and options.sets) or RealAssets.WORLD_SETS
	local problems, counts = {}, { templates = 0, parts = 0, surfaces = 0, attachments = 0, lights = 0, tags = 0 }
	local function bad(fmt: string, ...)
		table.insert(problems, string.format(fmt, ...))
	end
	for _, setName in ipairs(sets) do
		for name, a in pairs(Manifest.SETS[setName]) do
			local m = RealAssets.template(setName, name)
			if not m then
				bad("%s.%s: no template", setName, name)
				continue
			end
			counts.templates += 1
			local pv = m:GetPivot()
			if pv.Position.Magnitude > 1e-4 or pv.LookVector.Z > -0.9999 or pv.UpVector.Y < 0.9999 then
				bad("%s: pivot %s (want the identity)", name, tostring(pv))
			end
			if m:GetAttribute("AssetId") ~= Manifest.SOURCES[a.src].assetId then
				bad("%s: AssetId attribute %s", name, tostring(m:GetAttribute("AssetId")))
			end
			local lo = Vector3.new(math.huge, math.huge, math.huge)
			local hi = -lo
			for _, info in ipairs(a.parts) do
				local p = m:FindFirstChild(info.name)
				if not (p and p:IsA("MeshPart")) then
					bad("%s: missing part %s", name, info.name)
					continue
				end
				counts.parts += 1
				if info.role ~= "Collider" then -- the manifest bounds are visual only
					local p0, p1 = boxBounds(p.CFrame, p.Size)
					lo = lo:Min(p0)
					hi = hi:Max(p1)
				end
				local function check(prop: string, want: any)
					local ok, got = pcall(function()
						return (p :: any)[prop]
					end)
					local differs = if type(want) == "number" and type(got) == "number" then math.abs(got - want) > 1e-4 else got ~= want
					if ok and differs then
						bad("%s.%s: %s = %s, want %s", name, info.name, prop, tostring(got), tostring(want))
					end
				end
				check("Anchored", true)
				check("DoubleSided", false)
				check("RenderFidelity", Enum.RenderFidelity.Automatic)
				check("CastShadow", info.shadow and not info.neon)
				check("CanCollide", info.collide)
				check("CanQuery", info.query or info.collide)
				check("CanTouch", info.touch)
				check("CollisionFidelity", (Enum.CollisionFidelity :: any)[info.collision])
				check("Material", if info.neon then Enum.Material.Neon else (Enum.Material :: any)[info.mat])
				check("Transparency", if info.neon then 0 else info.transparency)
				check("TextureID", "")
				local sa = p:FindFirstChildOfClass("SurfaceAppearance")
				if info.neon or info.surf == 0 then
					if sa then
						bad("%s.%s: has a SurfaceAppearance", name, info.name)
					end
				elseif not sa then
					bad("%s.%s: no SurfaceAppearance", name, info.name)
				else
					counts.surfaces += 1
					local s = Manifest.SURF[info.surf]
					if sa.ColorMap ~= image(s[1]) or sa.NormalMap ~= image(s[2]) or sa.RoughnessMap ~= image(s[3])
						or sa.MetalnessMap ~= image(s[4] or nil) then
						bad("%s.%s: SurfaceAppearance maps differ from the manifest", name, info.name)
					end
					if sa.AlphaMode.Name ~= info.alpha then
						bad("%s.%s: AlphaMode %s, want %s", name, info.name, sa.AlphaMode.Name, info.alpha)
					end
					if sa.Color ~= rgb(info.tint) then
						bad("%s.%s: tint %s, want %s", name, info.name, tostring(sa.Color), tostring(rgb(info.tint)))
					end
				end
				for _, t in ipairs(info.tags or {}) do
					if GAME_TAGS[t] then
						counts.tags += 1
						if not p:HasTag(t) then
							bad("%s.%s: missing tag %s", name, info.name, t)
						end
					end
				end
			end
			if (lo - vec(a.bmin)).Magnitude > BOUNDS_TOLERANCE or (hi - vec(a.bmax)).Magnitude > BOUNDS_TOLERANCE then
				bad("%s: bounds %s .. %s, manifest %s .. %s", name, tostring(lo), tostring(hi), tostring(vec(a.bmin)), tostring(vec(a.bmax)))
			end
			for attName, att in pairs(a.att) do
				local at = m.PrimaryPart and m.PrimaryPart:FindFirstChild(attName)
				if not (at and at:IsA("Attachment")) then
					bad("%s: missing attachment %s", name, attName)
				else
					counts.attachments += 1
					local want = attachmentFrame(att)
					if (at.WorldPosition - want.Position).Magnitude > 1e-3 or at.WorldCFrame.LookVector:Dot(want.LookVector) < 0.9999 then
						bad("%s: attachment %s at %s, want %s", name, attName, tostring(at.WorldPosition), tostring(want.Position))
					end
				end
			end
			for _, t in ipairs(a.tags or {}) do
				if GAME_TAGS[t] then
					counts.tags += 1
					if not m:HasTag(t) then
						bad("%s: missing tag %s", name, t)
					end
				end
			end
			if LIGHTS[name] then
				local light = m:FindFirstChild("EmberLight", true)
				if light and light:IsA("PointLight") and light.Parent and light.Parent.Name == LIGHTS[name].att then
					counts.lights += 1
				else
					bad("%s: no EmberLight on %s", name, LIGHTS[name].att)
				end
			end
		end
		task.wait()
	end
	table.insert(problems, string.format("verified %d templates, %d parts, %d SurfaceAppearances, %d attachments, %d lights, %d tags",
		counts.templates, counts.parts, counts.surfaces, counts.attachments, counts.lights, counts.tags))
	return table.concat(problems, "\n")
end

-- The template for one asset, or nil.
function RealAssets.template(setName: string, assetName: string): Model?
	local root = ServerStorage:FindFirstChild("MeshAssets")
	local folder = root and root:FindFirstChild(setName)
	local m = folder and folder:FindFirstChild(assetName)
	return if m and m:IsA("Model") then m else nil
end

-- A 5.5-stud scale figure: a default R15 rig scaled to 5.5 studs, or (if the rig cannot load) a part mannequin with
-- the proportions and colour of the art director's review figure (art/blender/ad_review.py figure()).
local FIGURE_HEIGHT = 5.5
local function scaleFigure(): Model
	local ok, rig = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		local c = Color3.fromRGB(63, 77, 101) -- the review figure's blue-grey
		desc.HeadColor, desc.TorsoColor, desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = c, c, c, c, c, c
		local m = game:GetService("Players"):CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		m.Parent = workspace -- the joints only assemble in the world
		m:FindFirstChildOfClass("Humanoid"):BuildRigFromAttachments()
		return m
	end)
	if ok and rig then
		for _, d in ipairs(rig:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			elseif d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			elseif d:IsA("Humanoid") then
				d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end
		local _, size = rig:GetBoundingBox()
		rig:ScaleTo(rig:GetScale() * FIGURE_HEIGHT / size.Y)
		-- feet on y = 0 and the pivot there (set on the PrimaryPart: a WorldPivot write did not stick)
		local minY = math.huge
		for _, p in ipairs(rig:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 1 then
				local lo = boxBounds(p.CFrame, p.Size)
				minY = math.min(minY, lo.Y)
			end
		end
		for _, p in ipairs(rig:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CFrame = p.CFrame - Vector3.new(0, minY, 0)
			end
		end
		local cf = rig:GetBoundingBox()
		if rig.PrimaryPart then
			rig.PrimaryPart.PivotOffset = rig.PrimaryPart.CFrame:Inverse() * CFrame.new(cf.X, 0, cf.Z)
		end
		rig.Parent = nil
		rig.Name = "Figure_R15_5.5"
		return rig
	end
	local m = Instance.new("Model")
	m.Name = "Figure_5.5"
	local colour = Color3.fromRGB(63, 77, 101)
	local function limb(p0: Vector3, p1: Vector3, r: number)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new((p1 - p0).Magnitude + 2 * r, 2 * r, 2 * r)
		p.CFrame = CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.rad(90), 0)
		p.Color = colour
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.Parent = m
	end
	limb(Vector3.new(-0.36, 0.3, 0), Vector3.new(-0.33, 2.55, 0), 0.3)
	limb(Vector3.new(0.36, 0.3, 0), Vector3.new(0.33, 2.55, 0), 0.3)
	limb(Vector3.new(0, 2.75, 0), Vector3.new(0, 4.15, 0), 0.62)
	limb(Vector3.new(-0.95, 4.25, 0), Vector3.new(-1.1, 2.45, 0.05), 0.22)
	limb(Vector3.new(0.95, 4.25, 0), Vector3.new(1.1, 2.45, 0.05), 0.22)
	local head = Instance.new("Part")
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(0.9, 0.9, 0.9)
	head.CFrame = CFrame.new(0, 5.05, 0)
	head.Color = colour
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.Parent = m
	m.WorldPivot = CFrame.identity
	return m
end

-- Look-check lineup (temporary): every template of `sets` in rows, each next to a 5.5-stud figure, far from the
-- arena. options: origin (default (4200, 200, 0)), sets, gap (studs between assets, default 4), parent (default
-- workspace). It refuses to run while a lineup exists; RealAssets.clearLineup() takes it out of the workspace.
function RealAssets.lineup(options: { origin: Vector3?, sets: { string }?, gap: number?, parent: Instance? }?): Model
	local origin = (options and options.origin) or Vector3.new(4200, 200, 0)
	local sets = (options and options.sets) or RealAssets.WORLD_SETS
	local gap = (options and options.gap) or 4
	local parent = (options and options.parent) or workspace
	assert(not parent:FindFirstChild("RealAssets_Lineup"), "a lineup exists; call RealAssets.clearLineup() first")
	local lineup = Instance.new("Model")
	lineup.Name = "RealAssets_Lineup"
	lineup.Parent = parent
	local figure = scaleFigure()
	local z = origin.Z
	for _, setName in ipairs(sets) do
		local assets = Manifest.SETS[setName]
		local names = {}
		for name in pairs(assets) do
			table.insert(names, name)
		end
		table.sort(names, function(x, y)
			return (assets[x].bmax[1] - assets[x].bmin[1]) < (assets[y].bmax[1] - assets[y].bmin[1])
		end)
		local row = Instance.new("Model")
		row.Name = setName
		local x = origin.X
		local depth = 0
		for _, name in ipairs(names) do
			local t = RealAssets.template(setName, name)
			if t then
				local a = assets[name]
				local copy = t:Clone()
				copy:PivotTo(CFrame.new(x - a.bmin[1], origin.Y, z - a.bmin[3]))
				local fig = figure:Clone()
				fig:PivotTo(CFrame.new(x - 1.5, origin.Y, z - a.bmin[3])) -- beside the asset, level with its origin
				fig.Parent = copy
				if copy.PrimaryPart then
					local anchor = Instance.new("Attachment")
					anchor.Name = "LineupLabel"
					anchor.Parent = copy.PrimaryPart
					anchor.WorldPosition = Vector3.new(x - a.bmin[1], origin.Y + math.max(a.bmax[2], FIGURE_HEIGHT) + 1.5, z - a.bmin[3])
					local label = Instance.new("BillboardGui")
					label.Size = UDim2.fromOffset(150, 22)
					label.MaxDistance = 300
					label.Adornee = anchor
					local text = Instance.new("TextLabel")
					text.Size = UDim2.fromScale(1, 1)
					text.BackgroundTransparency = 1
					text.TextColor3 = Color3.new(1, 1, 1)
					text.TextStrokeTransparency = 0.3
					text.TextScaled = true
					text.Text = name
					text.Parent = label
					label.Parent = copy
				end
				copy.Parent = row
				x += (a.bmax[1] - a.bmin[1]) + gap + 3
				depth = math.max(depth, a.bmax[3] - a.bmin[3])
			end
		end
		row.Parent = lineup
		z += depth + gap * 3
		task.wait()
	end
	figure:Destroy() -- the unparented prototype
	-- a neutral slab whose top is the lineup's ground (buried trunks, roots and rock bases disappear into it);
	-- SmoothPlastic, because the place may override the Ground material with a MaterialVariant
	local cf, size = lineup:GetBoundingBox()
	local ground = Instance.new("Part")
	ground.Name = "LineupGround"
	ground.Anchored = true
	ground.Material = Enum.Material.SmoothPlastic
	ground.Color = Color3.fromRGB(112, 104, 88)
	ground.Size = Vector3.new(size.X + 60, 2, size.Z + 60)
	ground.CFrame = CFrame.new(cf.X, origin.Y - 1, cf.Z)
	ground.Parent = lineup
	return lineup
end

-- Moves the lineup out of the workspace into ServerStorage.MeshAssets_Preview (replacing the previous preview copy).
function RealAssets.clearLineup(parent: Instance?): string
	local lineup = (parent or workspace):FindFirstChild("RealAssets_Lineup")
	if not lineup then
		return "no lineup"
	end
	local preview = ensureFolder(ServerStorage, "MeshAssets_Preview")
	local prev = preview:FindFirstChild(lineup.Name)
	if prev then
		prev:Destroy()
	end
	lineup.Parent = preview
	return "lineup moved to ServerStorage.MeshAssets_Preview"
end

return RealAssets
