--[[
	Map1.Assets - the Blender meshes of Map 1 ("the Green Land") in Roblox: the raw imports, the templates, the checks
	and the code that places them. Edit mode only; nothing here runs in a live server.
	Contract: docs/design/Map1Build.md (3.2 Instances, decisions 6 to 8). Art: art/blender/map1_green_land.py, pass 3.

	WHERE THINGS LIVE
	  ServerStorage.MeshImports.Map1_<Set>   the raw insert of one uploaded GLB (Landmarks, Plants, Skyline, FarValley).
	                                         Never edit it. Attributes AssetId, Source.
	  ServerStorage.WorldAssets.Map1.<Asset> one template Model per manifest asset (M1_Horn, M1_Plinth, M1_Fir_A, ...).
	  script.Manifest                        GENERATED (tools/map1/gen_assets_manifest.py): the asset ids, every asset
	                                         and part of the art manifests, and Map1_Layout.json's items and heart.

	USE (execute_luau, Edit mode; Studio caches required modules, so require a clone)
	  local A = require(game.ServerStorage.WorldGen.Map1.Assets:Clone())
	  A.import()                        -- InsertService:LoadAsset for every set that is not in MeshImports yet
	  A.build()                         -- the templates (about a minute: collision is made per mesh). opts.sets,
	                                    --   opts.only = { M1_Horn = true } rebuild a part of them
	  A.verify()                        -- reads every template back against the manifest; last line PASS or FAIL
	  A.placeHeart(parent, offset?, opts?)      -- the platform, the horn, 48 plinths, the beds and teardrops
	  A.placeLandmarks(parent, offset?, opts?)  -- the peak, lone trees, hedges, berms, the spiral, the glade
	  A.placeSkyline(parent, offset?, opts?)    -- the far range (Persistent)          } only when their sets are
	  A.placeFarValley(parent, offset?, opts?)  -- the valley beyond streaming (Persistent) } uploaded
	  A.checkHeart(parent, offset?)     -- raycast checks of what placeHeart made: deck, stairs, interior, mantle,
	                                    --   pockets, plinths. Last line PASS or FAIL. The heart must be in Workspace.
	  A.remove(parent, group?)          -- takes out what the place functions made under parent ("Heart", "Landmarks",
	                                    --   "Skyline", "FarValley", "Lineup"; nil = all)
	  A.lineup(parent, origin, opts?)   -- every template in rows on a slab, for a look check
	  A.template(name) -> Model?        -- e.g. A.template("M1_Fir_A")
	  A.spawn(name, cframe, parent?) -> Model?   -- a copy of a template with its pivot at cframe (for Scatter)
	  A.names(setKey?) -> { string }    -- asset names, in manifest order
	  A.info(name) -> the manifest record (kind, tags, bmin, bmax, parts, att, set)
	`parent` is the arena's root: workspace.Arena at the install, workspace.Workbench_Map1.<label> for a test. The place
	functions make or reuse its children Plinths (Folder), Landmarks (Folder), Skyline (Model) and FarValley (Model).
	`offset` (Vector3) moves everything, for a test away from the map; the layout's own positions are map positions.

	TEMPLATES
	  Model        named as the manifest asset. No PrimaryPart; WorldPivot = identity = the manifest's pivot (the base
	               centre on the ground; front = -Z). Place a copy with PivotTo(CFrame.new(position) * yaw).
	  MeshParts    named as in the manifest. Anchored. Color = the manifest's rgb (one flat colour per part: the GLBs
	               carry no textures). Material: matte only (Assets.MATERIALS: Plaster for every painted, metal, stone
	               and plant part, Wood for bark, Fabric for the bags; nothing glossy, Reflectance 0).
	               CastShadow, CanCollide, CanQuery and CanTouch as the manifest hints. CollisionFidelity as the manifest
	               hints, except the assets in FIDELITY below, where the hint was measured against the mesh and found
	               too loose (made with AssetService:CreateMeshPartAsync + ApplyMesh: a direct write is ignored).
	               RenderFidelity Automatic; Precise for the horn, the platform, the peak and the two far sets.
	               Parts the manifest lists as invisible (the horn's wall colliders) get Transparency 1, no shadow.
	               Attribute Role.
	  Attachments  from the manifest, under the first visible part: the horn's Mouth_60/180/300, the platform's Deck,
	               the plinth's Stand (1.6 up).
	  Attributes   AssetId, Source, Set, Kind, Tags, Tris, BoundsMin, BoundsMax.
	  The importer bakes a half turn about Y into every mesh; build() measures it and undoes it with the part's CFrame.

	WHAT THE PLACE FUNCTIONS ADD (not in the meshes)
	  Plinths.Plinth01..48   ring order (layout index 0..47 = bearing 3.75 + 7.5 k), tag Plinth, attributes Index and
	                         Bearing, Persistent. The Stand attachment is turned to face the centre.
	  Landmarks.Platform     + StairRamp_060/180/300: an invisible wedge over each bronze stair, flush with the step
	                         noses, so the stairs are one walkable slope (the 1.5-stud risers would otherwise trigger the
	                         game's vault on every step). Invisible parts are never mantled (MovementController).
	  Landmarks.Horn         + HornLight (a warm PointLight on an attachment, no visible source), + SailFill_* (invisible
	                         blocks inside the sealed space under each sail, so nobody can ever be inside it).
	  Tube rims              left out unless opts.rims = true: there are no bores in the beta (Map1Build decision 6).
	Everything placed carries PlacedBy = "Map1.Assets" and Group; a second call replaces the first.
]]
local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local Manifest = require(script:WaitForChild("Manifest"))

local Assets = {}
Assets.VERSION = 1
Assets.Manifest = Manifest
Assets.SOURCE = "Map1.Assets" -- the PlacedBy attribute
Assets.MAX_PART = 2048 -- studs: Roblox's limit for a part's size on any axis

-- Matte only. Left: the manifest's Roblox material. Right: what the template gets. Metal, Glass and the plastics shine
-- (and Glass refracts), so they become painted matte surfaces. Grass, LeafyGrass and Limestone are terrain materials:
-- the place overrides them for the ground (MaterialService), so meshes do not use them either.
Assets.MATERIALS = {
	Plaster = Enum.Material.Plaster,
	Metal = Enum.Material.Plaster,
	Glass = Enum.Material.Plaster,
	SmoothPlastic = Enum.Material.Plaster,
	Plastic = Enum.Material.Plaster,
	Fabric = Enum.Material.Fabric,
	Wood = Enum.Material.Wood,
	Limestone = Enum.Material.Plaster,
	LeafyGrass = Enum.Material.Plaster,
	Grass = Enum.Material.Plaster,
}
Assets.FALLBACK_MATERIAL = Enum.Material.Plaster
-- A role's own material, when it should differ from its manifest material's row above.
Assets.ROLE_MATERIALS = {}
-- The look's own colours, by role, laid over the manifest's rgb (the lighting pass, 18 Nov 2026). The Blender palette's
-- heather is a strong mauve: as small plants on the ground it is right, but as whole flat faces of the far valley
-- and the peak it read as purple polygons on the hillsides. These duskier tones sit in the distance as heath.
-- Assets.build and Assets.verify use them; Assets.applyLookColors() repaints what is already built and placed.
Assets.LOOK_COLORS = {
	FarHeather = Color3.fromRGB(110, 96, 98),
	PeakHeath = Color3.fromRGB(106, 92, 92),
	FarDryGrass = Color3.fromRGB(120, 124, 78),
}

-- Seen from far away (the horn across the valley, the peak, the far range): always the full mesh, never a reduced one.
local PRECISE_ASSETS = { M1_Horn = true, M1_Platform = true, M1_Peak = true }
local PRECISE_SETS = { Skyline = true, FarValley = true }

-- Collision fidelity by asset, where the manifest's hint was measured and found too loose. The measure: rays cast at
-- the placed asset, each hit point's distance to the visual mesh (EditableMesh:FindClosestPointOnSurface).
--   M1_Peak     Default: mean 4.7, worst 39 studs off the mesh. PreciseConvexDecomposition: mean 0.7, worst 16.
--   M1_Crag_*   Default: mean 0.2 to 0.5, worst 2.8 to 4.5. PreciseConvexDecomposition: worst 0.05.
--   M1_LoneTree, M1_Beech_A/B   Hull wraps the spreading limbs too: at a contender's head height the collision
--               began 1.1 to 1.8 studs (at worst 2.6 to 3.4) in front of the visible trunk. Default: 0.03 at worst.
-- (Boulders stay Default: worst 0.4. Firs and pines stay Hull: worst 0.14. The sails are
-- PreciseConvexDecomposition in the manifest: worst 0.41.)
local FIDELITY: { [string]: Enum.CollisionFidelity } = {
	M1_Peak = Enum.CollisionFidelity.PreciseConvexDecomposition,
	M1_Crag_A = Enum.CollisionFidelity.PreciseConvexDecomposition,
	M1_Crag_B = Enum.CollisionFidelity.PreciseConvexDecomposition,
	M1_Crag_C = Enum.CollisionFidelity.PreciseConvexDecomposition,
	M1_LoneTree = Enum.CollisionFidelity.Default,
	M1_Beech_A = Enum.CollisionFidelity.Default,
	M1_Beech_B = Enum.CollisionFidelity.Default,
}

-- The bronze stairs of pass 3's platform mesh, measured in the GLB: the top tread is 2.4 deep, the others 2.0, each
-- riser 1.5. checkHeart() measures the ramp against the mesh.
local STAIR = { topTread = 2.4, tread = 2.0, rise = 1.5, inset = 0.1, bury = 1.5, lift = 0.02 }

-- The light inside the horn: one soft warm PointLight under the apex, where the Blender scene has its render-only fill
-- (24 over the deck). It casts shadows, so it cannot shine through the walls and sails, and it sits on an attachment:
-- no glowing part, nothing to bloom.
-- Brightness 0.5 (was 1): the night's exposure (+0.65) made the inside at 21:00 as bright as by day, a lit lantern
-- in a dark valley. At 0.5 it is a soft warm fill by day, and the day cycle (Shared.DayCycle, look key InteriorLight)
-- takes it down to 0.45 of that at night: a dim, readable room.
local HORN_LIGHT = { height = 22, range = 44, brightness = 0.5, color = Color3.fromRGB(255, 232, 204), shadows = true }

-- Invisible blocks inside the sealed space under the north sail (bearing 0), in the horn's own space, as
-- { cx, cy, cz, sx, sy, sz }; the other two sails get the same blocks turned 120 and 240 degrees. Each block stays
-- 0.35 under the sail's inner face and 0.5 off the wall slabs (measured on pass 3's mesh), so none can be touched
-- from outside, and with them a 2 x 2 box with 3 studs of headroom fits nowhere in that space.
local SAIL_FILL = {
	{ 0, 1.495, -26.375, 3, 2.789, 9.25 },
	{ 0, 3.06, -24.625, 3, 5.921, 5.75 },
	{ 0, 4.527, -23.125, 3, 8.854, 2.75 },
	{ 2.5, 1.75, -24.375, 2, 3.301, 5.25 },
	{ -2.5, 1.75, -24.375, 2, 3.301, 5.25 },
	{ 4.25, 1.371, -23.5, 1.5, 2.541, 3.5 },
	{ -4.25, 1.371, -23.5, 1.5, 2.541, 3.5 },
	{ 3.5, 3.093, -20.75, 2, 5.986, 2 },
	{ -3.5, 3.093, -20.75, 2, 5.986, 2 },
	{ 4.25, 1.475, -18.5, 1.5, 2.749, 2.5 },
	{ -4.25, 1.475, -18.5, 1.5, 2.749, 2.5 },
	{ 3.125, 4.766, -18.75, 0.75, 9.333, 2 },
	{ -3.125, 4.766, -18.75, 0.75, 9.333, 2 },
}

local GROUPS = { "Heart", "Landmarks", "Skyline", "FarValley", "Lineup" }

-------------------------------------------------------------------------------------------------------------- helpers

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function absVec(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

local function fmtV(v: Vector3): string
	return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end

-- bearing in degrees: 0 = north (-Z), clockwise, 90 = east (+X)
local function dirOf(bearing: number): Vector3
	local a = math.rad(bearing)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and not f:IsA("Folder") then
		error(string.format("Map1.Assets: %s.%s is a %s, not a Folder", parent:GetFullName(), name, f.ClassName))
	end
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
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

-- name -> the manifest record, with .set added
local ASSET: { [string]: any } = {}
for _, key in ipairs(Manifest.ORDER) do
	for _, a in ipairs(Manifest.SETS[key]) do
		a.set = key
		ASSET[a.name] = a
	end
end

local function setKeys(opts: any): { string }
	local keys = {}
	for _, key in ipairs((opts and opts.sets) or Manifest.ORDER) do
		if not Manifest.SOURCES[key] then
			error("Map1.Assets: no uploaded set named " .. tostring(key) .. " (the Manifest lists " .. table.concat(Manifest.ORDER, ", ") .. ")")
		end
		table.insert(keys, key)
	end
	return keys
end

local function colorOf(info: any): Color3
	return Assets.LOOK_COLORS[info.role] or Color3.fromRGB(info.rgb[1], info.rgb[2], info.rgb[3])
end

local function materialOf(info: any): Enum.Material
	return Assets.ROLE_MATERIALS[info.role] or Assets.MATERIALS[info.mat] or Assets.FALLBACK_MATERIAL
end

local function fidelityOf(info: any, a: any): Enum.CollisionFidelity
	if not info.collide then
		return Enum.CollisionFidelity.Box -- no physics data for a part nothing collides with
	end
	return FIDELITY[a.name] or (Enum.CollisionFidelity :: any)[info.collision] or Enum.CollisionFidelity.Default
end

local function renderOf(a: any): Enum.RenderFidelity
	if PRECISE_ASSETS[a.name] or PRECISE_SETS[a.set] then
		return Enum.RenderFidelity.Precise
	end
	return Enum.RenderFidelity.Automatic
end

function Assets.info(name: string): any
	return ASSET[name]
end

function Assets.names(setKey: string?): { string }
	local out = {}
	for _, key in ipairs(Manifest.ORDER) do
		if setKey == nil or setKey == key then
			for _, a in ipairs(Manifest.SETS[key]) do
				table.insert(out, a.name)
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------------------- import

local function importsFolder(): Folder
	return ensureFolder(ServerStorage, "MeshImports")
end

local function templatesFolder(create: boolean): Instance?
	if create then
		return ensureFolder(ensureFolder(ServerStorage, "WorldAssets"), "Map1")
	end
	local wa = ServerStorage:FindFirstChild("WorldAssets")
	return wa and wa:FindFirstChild("Map1")
end

-- The raw insert of one set, loading it when it is missing. Returns the model, or nil and why.
local function sourceModel(key: string, load: boolean): (Instance?, string?)
	local src = Manifest.SOURCES[key]
	local folder = importsFolder()
	local existing = folder:FindFirstChild(src.import)
	if existing then
		local id = existing:GetAttribute("AssetId")
		if id ~= src.assetId then
			return nil, string.format("%s holds asset %s, the manifest says %d: move it away and import again", existing:GetFullName(), tostring(id), src.assetId)
		end
		return existing, nil
	end
	if not load then
		return nil, src.import .. " is not in ServerStorage.MeshImports (run Assets.import())"
	end
	local ok, loaded = pcall(function()
		return InsertService:LoadAsset(src.assetId)
	end)
	if not ok or not loaded then
		return nil, string.format("LoadAsset(%d) failed: %s", src.assetId, tostring(loaded))
	end
	local root = loaded:GetChildren()[1] or loaded
	root.Name = src.import
	root:SetAttribute("AssetId", src.assetId)
	root:SetAttribute("Source", src.name)
	root.Parent = folder
	if loaded ~= root then
		loaded:Destroy()
	end
	return root, nil
end

-- Loads every set that is not in ServerStorage.MeshImports yet. opts.sets = { "Landmarks", ... } (default: all).
function Assets.import(opts: any): string
	local lines = {}
	for _, key in ipairs(setKeys(opts)) do
		local src = Manifest.SOURCES[key]
		local had = importsFolder():FindFirstChild(src.import) ~= nil
		local root, why = sourceModel(key, true)
		if root then
			local meshes = 0
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("MeshPart") then
					meshes += 1
				end
			end
			table.insert(lines, string.format("%s: %s (%s, asset %d), %d meshes%s", key, root:GetFullName(), src.name, src.assetId, meshes,
				if had then " (already there)" else " (loaded)"))
		else
			table.insert(lines, string.format("%s: FAILED: %s", key, tostring(why)))
		end
	end
	return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------------------------------------- build

local function meshIndex(source: Instance): { [string]: MeshPart }
	local index = {}
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("MeshPart") then
			index[d.Name] = d
		end
	end
	return index
end

-- Where each asset of one set sits inside its raw import, as its pivot frame in world space, and the turn about Y
-- that the importer baked into the meshes (every MeshPart reads the same rotation; the mesh data itself is turned).
-- The manifest gives each part's centre and size in the asset's own space, so the turn is the one of 180, 0, 90, 270
-- degrees that puts every part where the import has it and keeps the assets' spacing along the GLB's row.
local function locate(assets: { any }, index: { [string]: MeshPart }): ({ [string]: CFrame }, number, { string })
	local problems = {}
	local base: CFrame? = nil
	for _, a in ipairs(assets) do
		for _, p in ipairs(a.parts) do
			if index[p.name] then
				base = index[p.name].CFrame.Rotation
				break
			end
		end
		if base then
			break
		end
	end
	local base0 = base or CFrame.identity
	local toLocal = base0:Inverse()
	local meas: { [string]: { c: Vector3, s: Vector3 } } = {}
	for _, a in ipairs(assets) do
		for _, p in ipairs(a.parts) do
			local part = index[p.name]
			if part then
				local rel = toLocal * part.CFrame
				if rel.LookVector.Z > -0.9999 or rel.UpVector.Y < 0.9999 then
					table.insert(problems, p.name .. " is turned differently from the rest of the import")
				end
				meas[p.name] = { c = rel.Position, s = part.Size }
			else
				table.insert(problems, "missing mesh " .. p.name)
			end
		end
	end
	local bestDeg, bestErr, bestPivots = 180, math.huge, {}
	for _, deg in ipairs({ 180, 0, 90, 270 }) do
		local R = CFrame.Angles(0, math.rad(deg), 0)
		local err, n = 0, 0
		local pivots: { [string]: Vector3 } = {}
		local first: any = nil
		for _, a in ipairs(assets) do
			local sum, count = Vector3.zero, 0
			for _, p in ipairs(a.parts) do
				local m = meas[p.name]
				if m then
					sum += m.c - R * vec(p.c)
					count += 1
				end
			end
			if count > 0 then
				local pv = sum / count
				pivots[a.name] = pv
				for _, p in ipairs(a.parts) do
					local m = meas[p.name]
					if m then
						err += (m.c - (pv + R * vec(p.c))).Magnitude + (m.s - absVec(R * vec(p.s))).Magnitude
						n += 1
					end
				end
				if first then
					err += ((pv - pivots[first.name]) - R * (vec(a.origin) - vec(first.origin))).Magnitude
					n += 1
				else
					first = a
				end
			end
		end
		if n > 0 and err / n < bestErr - 1e-6 then
			bestDeg, bestErr, bestPivots = deg, err / n, pivots
		end
	end
	if bestErr == math.huge then
		table.insert(problems, "none of the manifest's parts is in the import")
		return {}, bestDeg, problems
	end
	if bestErr > 0.02 then
		table.insert(problems, string.format("the import does not match the manifest: mean error %.3f studs at the best turn (%d degrees)", bestErr, bestDeg))
	end
	local R = CFrame.Angles(0, math.rad(bestDeg), 0)
	local out: { [string]: CFrame } = {}
	for name, pv in pairs(bestPivots) do
		out[name] = base0 * CFrame.new(pv) * R
	end
	return out, bestDeg, problems
end

-- CollisionFidelity ignores direct writes (it stays Default, without an error). The physics is made with the wanted
-- fidelity through AssetService:CreateMeshPartAsync (about 1.4 s per mesh, 8 at once) and copied onto the template
-- part with ApplyMesh. Returns part name -> temporary MeshPart, and the names that failed.
local function prefetchPhysics(assets: { any }, index: { [string]: MeshPart }, only: { [string]: boolean }?): ({ [string]: MeshPart }, { string })
	local jobs = {}
	for _, a in ipairs(assets) do
		if not only or only[a.name] then
			local render = renderOf(a)
			for _, info in ipairs(a.parts) do
				local source = index[info.name]
				local fidelity = fidelityOf(info, a)
				if source and (source.CollisionFidelity ~= fidelity or source.RenderFidelity ~= render) then
					table.insert(jobs, { name = info.name, content = source.MeshContent, fidelity = fidelity, render = render })
				end
			end
		end
	end
	local results: { [string]: MeshPart } = {}
	local failed: { string } = {}
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
						RenderFidelity = job.render,
					})
				end)
				if ok and tmp then
					results[job.name] = tmp
				else
					table.insert(failed, job.name .. " (" .. tostring(tmp) .. ")")
				end
				running -= 1
			end)
		end
		task.wait()
	end
	return results, failed
end

local function buildAsset(a: any, index: { [string]: MeshPart }, pivot: CFrame, physics: { [string]: MeshPart }): (Model, { string })
	local problems = {}
	local src = Manifest.SOURCES[a.set]
	local toAsset = pivot:Inverse()
	local model = Instance.new("Model")
	model.Name = a.name
	local main: MeshPart? = nil
	local built = 0
	for _, info in ipairs(a.parts) do
		local source = index[info.name]
		if not source then
			table.insert(problems, "missing mesh " .. info.name)
			continue
		end
		local part = source:Clone()
		for _, child in ipairs(part:GetChildren()) do
			child:Destroy() -- importer leftovers
		end
		local tmp = physics[info.name]
		if tmp then
			part:ApplyMesh(tmp) -- collision geometry and render fidelity as wanted
			tmp:Destroy()
			physics[info.name] = nil
		end
		part.Name = info.name
		part.TextureID = ""
		part.CFrame = toAsset * source.CFrame
		part.Anchored = true
		part.Massless = true
		pcall(function()
			part.DoubleSided = false
		end)
		part.Material = materialOf(info)
		part.MaterialVariant = ""
		part.Color = colorOf(info)
		part.Reflectance = 0
		part.Transparency = if info.hidden then 1 else 0
		part.CastShadow = info.shadow and not info.hidden
		part.CanCollide = info.collide
		part.CanQuery = info.query or info.collide
		part.CanTouch = info.touch
		part:SetAttribute("Role", info.role)
		if math.max(part.Size.X, part.Size.Y, part.Size.Z) > Assets.MAX_PART then
			table.insert(problems, string.format("%s is %s studs: over %d", info.name, fmtV(part.Size), Assets.MAX_PART))
		end
		part.Parent = model
		built += 1
		if not main and not info.hidden then
			main = part
		end
	end
	main = main or model:FindFirstChildWhichIsA("MeshPart")
	if built ~= #a.parts then
		table.insert(problems, string.format("%d of %d parts", built, #a.parts))
	end
	if main then
		for attName, att in pairs(a.att) do
			local pos = vec(att.pos)
			local at = Instance.new("Attachment")
			at.Name = attName
			at.Parent = main
			at.WorldCFrame = CFrame.lookAt(pos, pos + vec(att.look), vec(att.up))
		end
	end
	model.WorldPivot = CFrame.identity -- no PrimaryPart: the pivot is the manifest's origin
	model:SetAttribute("AssetId", src.assetId)
	model:SetAttribute("Source", src.name)
	model:SetAttribute("Set", a.set)
	model:SetAttribute("Kind", a.kind)
	model:SetAttribute("Tags", table.concat(a.tags or {}, ","))
	model:SetAttribute("Tris", a.tris)
	model:SetAttribute("BoundsMin", vec(a.bmin))
	model:SetAttribute("BoundsMax", vec(a.bmax))
	return model, problems
end

-- Builds the templates into ServerStorage.WorldAssets.Map1 (a template of the same name is replaced).
-- opts: sets = { "Landmarks", ... } (default: every uploaded set), only = { [assetName] = true }, load = false to
-- fail instead of loading a missing import.
function Assets.build(opts: any): string
	local only = opts and opts.only
	local lines = {}
	local function note(fmt: string, ...)
		table.insert(lines, string.format(fmt, ...))
	end
	local folder = templatesFolder(true) :: Instance
	local totalModels, totalParts, bad = 0, 0, 0
	local t0 = os.clock()
	for _, key in ipairs(setKeys(opts)) do
		local assets = Manifest.SETS[key]
		local root, why = sourceModel(key, not (opts and opts.load == false))
		if not root then
			note("%s: FAILED: %s", key, tostring(why))
			bad += 1
			continue
		end
		local index = meshIndex(root)
		local pivots, turn, problems = locate(assets, index)
		note("%s: the import is turned %d degrees about Y (undone)", key, turn)
		for _, p in ipairs(problems) do
			note("%s: PROBLEM: %s", key, p)
			bad += 1
		end
		local physics, failed = prefetchPhysics(assets, index, only)
		for _, f in ipairs(failed) do
			note("%s: PROBLEM: no physics for %s", key, f)
			bad += 1
		end
		local built, parts = 0, 0
		for _, a in ipairs(assets) do
			if only and not only[a.name] then
				continue
			end
			local pivot = pivots[a.name]
			if not pivot then
				note("%s.%s: PROBLEM: not found in the import", key, a.name)
				bad += 1
				continue
			end
			local model, assetProblems = buildAsset(a, index, pivot, physics)
			for _, p in ipairs(assetProblems) do
				note("%s.%s: PROBLEM: %s", key, a.name, p)
				bad += 1
			end
			local old = folder:FindFirstChild(a.name)
			if old then
				old:Destroy()
			end
			model.Parent = folder
			built += 1
			parts += #a.parts
			if built % 8 == 0 then
				task.wait()
			end
		end
		for _, tmp in pairs(physics) do
			tmp:Destroy()
		end
		note("%s: %d templates, %d parts", key, built, parts)
		totalModels += built
		totalParts += parts
	end
	note("built %d templates, %d parts into %s in %.1f s; %s", totalModels, totalParts, folder:GetFullName(), os.clock() - t0,
		if bad == 0 then "no problems" else bad .. " PROBLEMS")
	return table.concat(lines, "\n")
end

-- The template of one asset, or nil.
function Assets.template(name: string): Model?
	local folder = templatesFolder(false)
	local m = folder and folder:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end

-- A copy of a template with its pivot at `cf`, parented to `parent` (or left unparented when parent is nil).
function Assets.spawn(name: string, cf: CFrame, parent: Instance?): Model?
	local t = Assets.template(name)
	if not t then
		return nil
	end
	local m = t:Clone()
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

-------------------------------------------------------------------------------------------------------------- verify

-- Reads every template back against the manifest: counts, names, the pivot, each part's place and size, colour,
-- material, flags, fidelities, the 2,048-stud limit, attachments; then the layout: every item has a template.
-- opts.sets limits the sets. Returns a report; its last line starts with PASS or FAIL.
function Assets.verify(opts: any): string
	local problems = {}
	local counts = { templates = 0, parts = 0, attachments = 0, colliding = 0, largest = 0, largestName = "" }
	local function bad(fmt: string, ...)
		table.insert(problems, string.format(fmt, ...))
	end
	local folder = templatesFolder(false)
	if not folder then
		return "FAIL: no ServerStorage.WorldAssets.Map1 (run Assets.build())"
	end
	local wanted = 0
	local keys = setKeys(opts)
	local inSets: { [string]: boolean } = {}
	for _, key in ipairs(keys) do
		inSets[key] = true
		local src = Manifest.SOURCES[key]
		local import = importsFolder():FindFirstChild(src.import)
		if not import then
			bad("%s: no raw import ServerStorage.MeshImports.%s", key, src.import)
		elseif import:GetAttribute("AssetId") ~= src.assetId then
			bad("%s: the raw import holds asset %s, the manifest says %d", key, tostring(import:GetAttribute("AssetId")), src.assetId)
		end
		for _, a in ipairs(Manifest.SETS[key]) do
			wanted += 1
			local m = folder:FindFirstChild(a.name)
			if not (m and m:IsA("Model")) then
				bad("%s: no template", a.name)
				continue
			end
			counts.templates += 1
			local pv = m:GetPivot()
			if m.PrimaryPart or pv.Position.Magnitude > 1e-4 or pv.LookVector.Z > -0.9999 or pv.UpVector.Y < 0.9999 then
				bad("%s: the pivot is not the identity (%s)", a.name, tostring(pv))
			end
			if m:GetAttribute("AssetId") ~= src.assetId then
				bad("%s: AssetId attribute %s", a.name, tostring(m:GetAttribute("AssetId")))
			end
			local meshes = 0
			for _, ch in ipairs(m:GetChildren()) do
				if ch:IsA("BasePart") then
					meshes += 1
				end
			end
			if meshes ~= #a.parts then
				bad("%s: %d parts, the manifest lists %d", a.name, meshes, #a.parts)
			end
			local lo = Vector3.new(math.huge, math.huge, math.huge)
			local hi = -lo
			local render = renderOf(a)
			for _, info in ipairs(a.parts) do
				local p = m:FindFirstChild(info.name)
				if not (p and p:IsA("MeshPart")) then
					bad("%s: missing part %s", a.name, info.name)
					continue
				end
				counts.parts += 1
				local p0, p1 = boxBounds(p.CFrame, p.Size)
				lo, hi = lo:Min(p0), hi:Max(p1)
				local c, s = (p0 + p1) / 2, p1 - p0
				if (c - vec(info.c)).Magnitude > 0.02 or (s - vec(info.s)).Magnitude > 0.02 then
					bad("%s: centre %s size %s, the GLB has %s %s", info.name, fmtV(c), fmtV(s), fmtV(vec(info.c)), fmtV(vec(info.s)))
				end
				local big = math.max(p.Size.X, p.Size.Y, p.Size.Z)
				if big > counts.largest then
					counts.largest, counts.largestName = big, info.name
				end
				if big > Assets.MAX_PART then
					bad("%s: %.1f studs on its longest axis (limit %d)", info.name, big, Assets.MAX_PART)
				end
				local function check(prop: string, want: any)
					local ok, got = pcall(function()
						return (p :: any)[prop]
					end)
					local differs = if type(want) == "number" and type(got) == "number" then math.abs(got - want) > 1e-4 else got ~= want
					if ok and differs then
						bad("%s: %s = %s, want %s", info.name, prop, tostring(got), tostring(want))
					end
				end
				check("Anchored", true)
				check("Color", colorOf(info))
				check("Material", materialOf(info))
				check("MaterialVariant", "")
				check("Reflectance", 0)
				check("Transparency", if info.hidden then 1 else 0)
				check("TextureID", "")
				check("CastShadow", info.shadow and not info.hidden)
				check("CanCollide", info.collide)
				check("CanQuery", info.query or info.collide)
				check("CanTouch", info.touch)
				check("CollisionFidelity", fidelityOf(info, a))
				check("RenderFidelity", render)
				if p:FindFirstChildWhichIsA("SurfaceAppearance") or p:FindFirstChildWhichIsA("Decal") then
					bad("%s: carries a texture", info.name)
				end
				if info.collide then
					counts.colliding += 1
				end
			end
			if (lo - vec(a.bmin)).Magnitude > 0.06 or (hi - vec(a.bmax)).Magnitude > 0.06 then
				bad("%s: bounds %s .. %s, the manifest says %s .. %s", a.name, fmtV(lo), fmtV(hi), fmtV(vec(a.bmin)), fmtV(vec(a.bmax)))
			end
			for attName, att in pairs(a.att) do
				local at = m:FindFirstChild(attName, true)
				if not (at and at:IsA("Attachment")) then
					bad("%s: missing attachment %s", a.name, attName)
				else
					counts.attachments += 1
					local want = CFrame.lookAt(vec(att.pos), vec(att.pos) + vec(att.look), vec(att.up))
					if (at.WorldPosition - want.Position).Magnitude > 1e-3 or at.WorldCFrame.LookVector:Dot(want.LookVector) < 0.9999 then
						bad("%s: attachment %s at %s, want %s", a.name, attName, fmtV(at.WorldPosition), fmtV(want.Position))
					end
				end
			end
		end
		task.wait()
	end
	-- nothing in the folder that the manifest does not know
	for _, ch in ipairs(folder:GetChildren()) do
		if not ASSET[ch.Name] then
			bad("%s: a template the manifest does not list", ch.Name)
		end
	end
	-- the layout: every item has a template
	local items, missing = 0, {}
	for _, item in ipairs(Manifest.LAYOUT.items) do
		local a = ASSET[item[1]]
		if a == nil or inSets[a.set] then
			items += 1
			if not (a and folder:FindFirstChild(item[1])) then
				missing[item[1]] = (missing[item[1]] or 0) + 1
			end
		end
	end
	local names = {}
	for name, n in pairs(missing) do
		table.insert(names, string.format("%s x%d", name, n))
	end
	table.sort(names)
	if #names > 0 then
		bad("the layout places %d kinds of asset with no template: %s", #names, table.concat(names, ", "))
	end
	local lines = {}
	for _, p in ipairs(problems) do
		table.insert(lines, "PROBLEM: " .. p)
	end
	table.insert(lines, string.format("sets %s: %d of %d templates, %d parts (%d colliding), %d attachments; largest part %s %.1f studs (limit %d); %d layout items checked",
		table.concat(keys, ", "), counts.templates, wanted, counts.parts, counts.colliding, counts.attachments, counts.largestName, counts.largest, Assets.MAX_PART, items))
	table.insert(lines, if #problems == 0 then "PASS: every template matches the manifest and every layout item has a template" else string.format("FAIL: %d problems", #problems))
	return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------------------------------------- placing

local PERSISTENT = Enum.ModelStreamingMode.Persistent
local ATOMIC = Enum.ModelStreamingMode.Atomic

local function groupOf(assetName: string): string
	local a = ASSET[assetName]
	if (a and a.set == "Skyline") or string.match(assetName, "^M1_Skyline") then
		return "Skyline"
	end
	if (a and a.set == "FarValley") or string.match(assetName, "^M1_FarValley") then
		return "FarValley"
	end
	if assetName == "M1_Platform" or assetName == "M1_Horn" or assetName == "M1_Plinth" or assetName == "M1_PlateTubeRim"
		or string.match(assetName, "^M1_Spoke_%d+$") or string.match(assetName, "^M1_Teardrop") then
		return "Heart"
	end
	return "Landmarks"
end

local function itemCFrame(item: any, offset: Vector3, y: number?): CFrame
	return CFrame.new(item[2] + offset.X, (y or item[3]) + offset.Y, item[4] + offset.Z) * CFrame.Angles(0, math.rad(item[5]), 0)
end

-- The terrain's height under (x, z), looked for within `reach` studs of y; nil when there is none.
local function terrainY(x: number, y: number, z: number, reach: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, y + reach, z), Vector3.new(0, -2 * reach, 0), params)
	return if hit then hit.Position.Y else nil
end

local function mark(inst: Instance, group: string, assetName: string?)
	inst:SetAttribute("PlacedBy", Assets.SOURCE)
	inst:SetAttribute("Group", group)
	if assetName then
		inst:SetAttribute("Asset", assetName)
	end
end

-- Destroys the children of `container` that a place function made for `group`. Returns how many, and how many other
-- children stay.
local function clearGroup(container: Instance?, group: string): (number, number)
	local removed, others = 0, 0
	if container then
		for _, ch in ipairs(container:GetChildren()) do
			if ch:GetAttribute("PlacedBy") == Assets.SOURCE and ch:GetAttribute("Group") == group then
				ch:Destroy()
				removed += 1
			else
				others += 1
			end
		end
	end
	return removed, others
end

local function placeItem(item: any, offset: Vector3, name: string, group: string, mode: Enum.ModelStreamingMode, y: number?): Model?
	local t = Assets.template(item[1])
	if not t then
		return nil
	end
	local m = t:Clone()
	m.Name = name
	m:PivotTo(itemCFrame(item, offset, y))
	m.ModelStreamingMode = mode
	mark(m, group, item[1])
	return m
end

local function invisibleBlock(name: string, class: string, size: Vector3, cf: CFrame): BasePart
	local p = Instance.new(class) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Transparency = 1
	p.CastShadow = false
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.Material = Enum.Material.Plaster
	p.Color = Color3.fromRGB(120, 96, 64)
	p:SetAttribute("Role", "Collider")
	return p
end

-- An invisible wedge over one bronze stair: its slope passes just over the step noses, from the deck's level at the
-- top tread's nose down into the ground beyond the first riser. The thin end points outward.
local function stairRamp(mouth: any, offset: Vector3, knollY: number): BasePart
	local top = vec(mouth.stairTop) + offset
	local foot = vec(mouth.stairFoot) + offset
	local out = Vector3.new(foot.X - top.X, 0, foot.Z - top.Z).Unit
	local slope = STAIR.rise / STAIR.tread
	local hi = top + out * STAIR.topTread + Vector3.new(0, STAIR.lift, 0)
	local drop = (hi.Y - (knollY + offset.Y)) + STAIR.bury
	local length = drop / slope
	local centre = hi + out * (length / 2) - Vector3.new(0, drop / 2, 0)
	-- a WedgePart's slope rises toward its +Z (back) face: the thin edge is at -Z, which lookAt points along `out`
	local wedge = invisibleBlock(string.format("StairRamp_%03d", math.round(mouth.bearing)), "WedgePart",
		Vector3.new(mouth.stairWidth - 2 * STAIR.inset, drop, length), CFrame.lookAt(centre, centre + out))
	wedge:SetAttribute("Bearing", mouth.bearing)
	return wedge
end

-- The heart: workspace-side instances for Map1Build 3.2.
--   parent.Landmarks  Platform, Horn, Spoke_00..17, TeardropPeriwinkle_060.., TeardropMarigold_060..
--   parent.Plinths    Plinth01..Plinth48 and nothing else of ours
-- opts: rims = true also places the 48 tube rims (Landmarks.PlateRims); light = false leaves the horn dark;
--       snap = true (or a reach in studs) seats each plinth on the terrain under it instead of the layout's height.
function Assets.placeHeart(parent: Instance, offset: Vector3?, opts: any): string
	local off = offset or Vector3.zero
	local H = Manifest.LAYOUT.heart
	local lines = {}
	local function note(fmt: string, ...)
		table.insert(lines, string.format(fmt, ...))
	end
	local landmarks = ensureFolder(parent, "Landmarks")
	local plinths = ensureFolder(parent, "Plinths")
	local removed = clearGroup(landmarks, "Heart")
	local removedPlinths, foreign = clearGroup(plinths, "Heart")
	if removed + removedPlinths > 0 then
		note("replaced an earlier heart (%d instances)", removed + removedPlinths)
	end
	if foreign > 0 then
		note("PROBLEM: %s holds %d children that are not ours; the game wants exactly the 48 plinths there", plinths:GetFullName(), foreign)
	end
	local centre = Vector3.new(off.X, 0, off.Z)
	local reach = if opts and opts.snap then (if type(opts.snap) == "number" then opts.snap else 6) else nil
	local placed = { beds = 0, teardrops = 0, plinths = 0, rims = 0 }
	local missing: { [string]: boolean } = {}
	local rimItems = {}
	local plinthItems = {}
	local worstStand, worstSnap = 0, 0
	for _, item in ipairs(Manifest.LAYOUT.items) do
		local name = item[1]
		if groupOf(name) ~= "Heart" then
			continue
		end
		if name == "M1_Plinth" then
			table.insert(plinthItems, item)
		elseif name == "M1_PlateTubeRim" then
			table.insert(rimItems, item)
		else
			local instName
			if name == "M1_Platform" then
				instName = "Platform"
			elseif name == "M1_Horn" then
				instName = "Horn"
			elseif string.match(name, "^M1_Spoke_") then
				instName = string.sub(name, 4)
			else
				instName = string.format("%s_%03d", string.sub(name, 4), math.round(item.bearing or 0))
			end
			local m = placeItem(item, off, instName, "Heart", PERSISTENT)
			if not m then
				missing[name] = true
				continue
			end
			if item.bearing then
				m:SetAttribute("Bearing", item.bearing)
			end
			if name == "M1_Platform" then
				for _, mouth in ipairs(H.mouths) do
					stairRamp(mouth, off, H.knollY).Parent = m
				end
			elseif name == "M1_Horn" then
				local pivot = m:GetPivot()
				for k = 0, 2 do
					local turn = pivot * CFrame.Angles(0, -math.rad(120 * k), 0)
					for i, b in ipairs(SAIL_FILL) do
						invisibleBlock(string.format("SailFill_%03d_%d", 120 * k, i), "Part", Vector3.new(b[4], b[5], b[6]),
							turn * CFrame.new(b[1], b[2], b[3])).Parent = m
					end
				end
				if not (opts and opts.light == false) then
					local host = m:FindFirstChildWhichIsA("MeshPart")
					if host then
						local at = Instance.new("Attachment")
						at.Name = "LightPoint"
						at.Parent = host
						at.WorldPosition = pivot.Position + Vector3.new(0, HORN_LIGHT.height, 0)
						local light = Instance.new("PointLight")
						light.Name = "HornLight"
						light.Color = HORN_LIGHT.color
						light.Brightness = HORN_LIGHT.brightness
						light:SetAttribute("BaseBrightness", HORN_LIGHT.brightness) -- Shared.DayCycle dims it at night from this
						light.Range = HORN_LIGHT.range
						light.Shadows = HORN_LIGHT.shadows
						light.Parent = at
					end
				end
			elseif string.match(name, "^M1_Spoke_") then
				placed.beds += 1
			else
				placed.teardrops += 1
			end
			m.Parent = landmarks
		end
	end
	table.sort(plinthItems, function(x, y)
		return (x.index or 0) < (y.index or 0)
	end)
	for i, item in ipairs(plinthItems) do
		local y: number? = nil
		if reach then
			y = terrainY(item[2] + off.X, item[3] + off.Y, item[4] + off.Z, reach)
			if y then
				y -= off.Y
				worstSnap = math.max(worstSnap, math.abs(y - item[3]))
			end
		end
		local m = placeItem(item, off, string.format("Plinth%02d", i), "Heart", PERSISTENT, y)
		if not m then
			missing[item[1]] = true
			break
		end
		m:SetAttribute("Index", i)
		m:SetAttribute("Bearing", item.bearing)
		CollectionService:AddTag(m, "Plinth")
		local stand = m:FindFirstChild("Stand", true)
		if stand and stand:IsA("Attachment") then
			local p = stand.WorldPosition
			stand.WorldCFrame = CFrame.lookAt(p, Vector3.new(centre.X, p.Y, centre.Z))
			if item.stand and not y then
				worstStand = math.max(worstStand, (p - (vec(item.stand) + off)).Magnitude)
			end
		else
			note("PROBLEM: Plinth%02d has no Stand attachment", i)
		end
		m.Parent = plinths
		placed.plinths += 1
	end
	if opts and opts.rims then
		local rims = Instance.new("Model")
		rims.Name = "PlateRims"
		rims.ModelStreamingMode = PERSISTENT
		mark(rims, "Heart", "M1_PlateTubeRim")
		table.sort(rimItems, function(x, y)
			return (x.index or 0) < (y.index or 0)
		end)
		for i, item in ipairs(rimItems) do
			local y: number? = nil
			if reach then
				y = terrainY(item[2] + off.X, item[3] + off.Y, item[4] + off.Z, reach)
				y = if y then y - off.Y else nil
			end
			local m = placeItem(item, off, string.format("PlateRim%02d", i), "Heart", PERSISTENT, y)
			if m then
				m.Parent = rims
				placed.rims += 1
			else
				missing[item[1]] = true
				break
			end
		end
		rims.Parent = landmarks
	end
	for name in pairs(missing) do
		note("PROBLEM: no template %s (run Assets.build())", name)
	end
	note("heart at offset %s under %s: platform and horn, %d beds, %d teardrops, %d plinths (Plinth01..%02d)%s", fmtV(off), parent:GetFullName(),
		placed.beds, placed.teardrops, placed.plinths, placed.plinths, if placed.rims > 0 then string.format(", %d tube rims", placed.rims) else ", no tube rims")
	if reach then
		note("plinths seated on the terrain: the largest change from the layout's height is %.2f studs", worstSnap)
	else
		note("stand points against the layout: largest difference %.4f studs", worstStand)
	end
	return table.concat(lines, "\n")
end

-- The rest of the layout: parent.Landmarks gets Peak, LoneTree_060/180/300, CrimsonSpiral, SunGlade, HollyHedge_01..22,
-- Berm_020.. The peak and the lone trees are Persistent (seen from the heart); the others stream as whole models.
-- opts.snap = true (or a reach in studs) seats the trees, hedges, berms, spiral and glade on the terrain under them.
function Assets.placeLandmarks(parent: Instance, offset: Vector3?, opts: any): string
	local off = offset or Vector3.zero
	local lines = {}
	local landmarks = ensureFolder(parent, "Landmarks")
	local removed = clearGroup(landmarks, "Landmarks")
	if removed > 0 then
		table.insert(lines, string.format("replaced %d earlier landmarks", removed))
	end
	local reach = if opts and opts.snap then (if type(opts.snap) == "number" then opts.snap else 6) else nil
	local total: { [string]: number } = {}
	for _, item in ipairs(Manifest.LAYOUT.items) do
		if groupOf(item[1]) == "Landmarks" then
			total[item[1]] = (total[item[1]] or 0) + 1
		end
	end
	local seen: { [string]: number } = {}
	local counts: { [string]: number } = {}
	local missing: { [string]: boolean } = {}
	local worstSnap, placed = 0, 0
	for _, item in ipairs(Manifest.LAYOUT.items) do
		local name = item[1]
		if groupOf(name) ~= "Landmarks" then
			continue
		end
		seen[name] = (seen[name] or 0) + 1
		local short = string.sub(name, 4)
		local instName = short
		if total[name] > 1 then
			instName = if item.bearing then string.format("%s_%03d", short, math.round(item.bearing)) else string.format("%s_%02d", short, seen[name])
		end
		local persistent = name == "M1_Peak" or name == "M1_LoneTree"
		local y: number? = nil
		if reach and name ~= "M1_Peak" then
			y = terrainY(item[2] + off.X, item[3] + off.Y, item[4] + off.Z, reach)
			if y then
				y -= off.Y
				worstSnap = math.max(worstSnap, math.abs(y - item[3]))
			end
		end
		local m = placeItem(item, off, instName, "Landmarks", if persistent then PERSISTENT else ATOMIC, y)
		if not m then
			missing[name] = true
			continue
		end
		if item.bearing then
			m:SetAttribute("Bearing", item.bearing)
		end
		m.Parent = landmarks
		counts[short] = (counts[short] or 0) + 1
		placed += 1
	end
	for name in pairs(missing) do
		table.insert(lines, string.format("PROBLEM: no template %s (run Assets.build())", name))
	end
	local parts = {}
	for short, n in pairs(counts) do
		table.insert(parts, string.format("%s x%d", short, n))
	end
	table.sort(parts)
	table.insert(lines, string.format("landmarks at offset %s under %s: %d placed (%s)", fmtV(off), landmarks:GetFullName(), placed, table.concat(parts, ", ")))
	if reach then
		table.insert(lines, string.format("seated on the terrain: the largest change from the layout's height is %.2f studs", worstSnap))
	end
	return table.concat(lines, "\n")
end

-- One Persistent Model holding every asset of a far set at the map centre: anchored, no collision, no query, no touch,
-- no shadow (whatever the manifest says).
local function placeFar(parent: Instance, setKey: string, modelName: string, offset: Vector3?, opts: any): string
	local off = offset or Vector3.zero
	local colors = opts and opts.colors
	if not Manifest.SOURCES[setKey] then
		return string.format("FAILED: the %s set is not uploaded yet (no asset id in the Manifest)", setKey)
	end
	local old = parent:FindFirstChild(modelName)
	if old then
		if old:GetAttribute("PlacedBy") ~= Assets.SOURCE then
			return string.format("FAILED: %s exists and is not ours", old:GetFullName())
		end
		old:Destroy()
	end
	local where: { [string]: any } = {}
	for _, item in ipairs(Manifest.LAYOUT.items) do
		where[item[1]] = item
	end
	local holder = Instance.new("Model")
	holder.Name = modelName
	holder.ModelStreamingMode = PERSISTENT
	mark(holder, setKey, nil)
	local placed, parts, largest = 0, 0, 0
	local missing = {}
	local skipped = 0
	for _, a in ipairs(Manifest.SETS[setKey]) do
		if a.optional and opts and opts.optional == false then
			skipped += 1
			continue
		end
		local t = Assets.template(a.name)
		if not t then
			table.insert(missing, a.name)
			continue
		end
		local m = t:Clone()
		-- the layout's item when it has one, else the manifest's own placement, else the map centre
		local item = where[a.name] or (a.placement and { a.name, a.placement[1], a.placement[2], a.placement[3], a.placement[4] })
		m:PivotTo(if item then itemCFrame(item, off) else CFrame.new(off))
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				-- Locked: a click in Studio's 3D view can't pick it up. These meshes surround the whole map, so any stray
				-- click-and-drag in Edit mode moved the entire far valley (found 1,580 studs off and tilted, 18 Nov).
				d.Locked = true
				local role = d:GetAttribute("Role")
				if colors and role and colors[role] then
					d.Color = colors[role]
				end
				parts += 1
				largest = math.max(largest, d.Size.X, d.Size.Y, d.Size.Z)
			end
		end
		mark(m, setKey, a.name)
		m.Parent = holder
		placed += 1
	end
	holder.WorldPivot = CFrame.new(off)
	holder.Parent = parent
	return string.format("%s%s: %d assets, %d parts (largest %.0f studs) under %s, Persistent%s", if #missing > 0 then "PROBLEM: no template for " .. table.concat(missing, ", ") .. "\n" else "",
		setKey, placed, parts, largest, holder:GetFullName(), if skipped > 0 then string.format("; %d optional assets left out", skipped) else "")
end

-- opts.colors = { [role] = Color3 } repaints parts by role (for example FarGrass, to the colour the terrain's Grass
-- ends up with, so the mesh and the real ground meet without a seam at the streaming edge).
-- opts.optional = false leaves out the assets the manifest marks optional (the far valley's core under the heart).
function Assets.placeSkyline(parent: Instance, offset: Vector3?, opts: any): string
	return placeFar(parent, "Skyline", "Skyline", offset, opts)
end

function Assets.placeFarValley(parent: Instance, offset: Vector3?, opts: any): string
	return placeFar(parent, "FarValley", "FarValley", offset, opts)
end

-- Repaints, by role, the templates and everything already placed under `parent` (default workspace.Arena) with
-- Assets.LOOK_COLORS, and sets the horn's light to HORN_LIGHT. Nothing is rebuilt or moved. Safe to re-run.
function Assets.applyLookColors(parent: Instance?): string
	local painted, lights = 0, 0
	local function paint(root: Instance?)
		if not root then
			return
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				local role = d:GetAttribute("Role")
				local color = role and Assets.LOOK_COLORS[role]
				if color and d.Color ~= color then
					d.Color = color
					painted += 1
				end
			elseif d:IsA("PointLight") and d.Name == "HornLight" then
				d.Brightness = HORN_LIGHT.brightness
				d:SetAttribute("BaseBrightness", HORN_LIGHT.brightness)
				d.Range = HORN_LIGHT.range
				d.Color = HORN_LIGHT.color
				lights += 1
			end
		end
	end
	local wa = ServerStorage:FindFirstChild("WorldAssets")
	paint(wa and wa:FindFirstChild("Map1"))
	paint(parent or workspace:FindFirstChild("Arena"))
	return string.format("look colours: %d parts repainted, %d horn lights set", painted, lights)
end

-- Takes out what the place functions made under `parent` (group nil = all of them). Folders we made stay.
function Assets.remove(parent: Instance, group: string?): string
	local lines = {}
	for _, g in ipairs(GROUPS) do
		if group == nil or group == g then
			local n = 0
			n += clearGroup(parent:FindFirstChild("Landmarks"), g)
			n += clearGroup(parent:FindFirstChild("Plinths"), g)
			n += clearGroup(parent, g)
			table.insert(lines, string.format("%s: %d removed", g, n))
		end
	end
	return table.concat(lines, "; ")
end

-- A look-check lineup: every template in rows (one row per set, in manifest order) on a plain slab, with a 5-stud
-- block at the head of each row. Assets wider than opts.maxSize (default 200 studs: the peak and the far sets) are
-- left out. Returns the Model "Map1_Lineup" under `parent`; Assets.remove(parent, "Lineup") takes it away.
function Assets.lineup(parent: Instance, origin: Vector3, opts: any): Model
	local maxSize = (opts and opts.maxSize) or 200
	local gap = (opts and opts.gap) or 6
	clearGroup(parent, "Lineup")
	local lineup = Instance.new("Model")
	lineup.Name = "Map1_Lineup"
	mark(lineup, "Lineup", nil)
	local z = origin.Z
	local lo = Vector3.new(math.huge, 0, math.huge)
	local hi = -lo
	for _, key in ipairs(Manifest.ORDER) do
		local x = origin.X
		local depth = 0
		local cube = Instance.new("Part")
		cube.Name = "FiveStuds_" .. key
		cube.Size = Vector3.new(5, 5, 5)
		cube.Anchored = true
		cube.Material = Enum.Material.Plaster
		cube.Color = Color3.fromRGB(232, 163, 59)
		cube.CFrame = CFrame.new(x - 8, origin.Y + 2.5, z)
		cube.Parent = lineup
		for _, a in ipairs(Manifest.SETS[key]) do
			local size = vec(a.bmax) - vec(a.bmin)
			local t = Assets.template(a.name)
			if t and math.max(size.X, size.Z) <= maxSize then
				local m = t:Clone()
				m:PivotTo(CFrame.new(x - a.bmin[1], origin.Y, z - a.bmin[3]))
				m.Parent = lineup
				lo = lo:Min(Vector3.new(x, 0, z))
				hi = hi:Max(Vector3.new(x + size.X, 0, z + size.Z))
				x += size.X + gap
				depth = math.max(depth, size.Z)
			end
		end
		z += depth + gap * 2
	end
	if hi.X > lo.X then
		local slab = Instance.new("Part")
		slab.Name = "LineupGround"
		slab.Anchored = true
		slab.Material = Enum.Material.Plaster
		slab.Color = Color3.fromRGB(112, 110, 96)
		slab.Size = Vector3.new(hi.X - lo.X + 40, 4, hi.Z - lo.Z + 40)
		slab.CFrame = CFrame.new((lo.X + hi.X) / 2, origin.Y - 2, (lo.Z + hi.Z) / 2)
		slab.Parent = lineup
	end
	lineup.Parent = parent
	return lineup
end

-------------------------------------------------------------------------------------------------------------- checks

-- Raycast checks of a placed heart. The numbers are the layout's; the limits are the game's (Config.Movement: mantle
-- 2.2 to 6.5, walkable up to 46 degrees; MovementController never mantles an invisible part).
--   deck      every point of the deck polygon has the deck (or the horn's floor) under it
--   stairs    each mouth's stair is one slope a contender can walk: no step over 0.25, nowhere steeper than 46 degrees
--   interior  the floor is solid all over; from the centre the only ways out are the three mouths
--   mantle    round the deck's edge, away from the stairs, the game's own ledge test passes on visible parts
--   pockets   a contender-sized box is moved over the deck on a 1-stud grid: every free place connects to a stair
--   plinths   48, in ring order, each Stand 1.6 above its base, facing the centre, on the ring
function Assets.checkHeart(parent: Instance, offset: Vector3?): string
	local off = offset or Vector3.zero
	local H = Manifest.LAYOUT.heart
	local lines, fails = {}, 0
	local function note(fmt: string, ...)
		table.insert(lines, string.format(fmt, ...))
	end
	local function fail(fmt: string, ...)
		fails += 1
		table.insert(lines, "PROBLEM: " .. string.format(fmt, ...))
	end
	local landmarks = parent:FindFirstChild("Landmarks")
	local horn = landmarks and landmarks:FindFirstChild("Horn")
	local platform = landmarks and landmarks:FindFirstChild("Platform")
	local plinths = parent:FindFirstChild("Plinths")
	if not (horn and platform and plinths) then
		return "FAIL: no heart under " .. parent:GetFullName() .. " (run Assets.placeHeart)"
	end
	if not horn:IsDescendantOf(workspace) then
		return "FAIL: the heart must be in the Workspace for raycasts"
	end
	local deckY, knollY, floorY = H.deckY + off.Y, H.knollY + off.Y, H.horn.floorY + off.Y
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { horn, platform }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local function visible(inst: Instance?): boolean
		return inst ~= nil and inst:IsA("BasePart") and inst.Transparency < 0.98
	end

	-- the deck polygon (convex), in world space
	local poly = {}
	local cx, cz = 0, 0
	for _, p in ipairs(H.deckPolygon) do
		table.insert(poly, Vector3.new(p[1] + off.X, 0, p[3] + off.Z))
		cx += p[1] + off.X
		cz += p[3] + off.Z
	end
	cx /= #poly
	cz /= #poly
	local lo = Vector3.new(math.huge, 0, math.huge)
	local hi = -lo
	for _, p in ipairs(poly) do
		lo, hi = lo:Min(p), hi:Max(p)
	end
	-- signed distance to the nearest edge: positive inside
	local function inside(x: number, z: number): number
		local best = math.huge
		for i = 1, #poly do
			local a, b = poly[i], poly[i % #poly + 1]
			local ex, ez = b.X - a.X, b.Z - a.Z
			local len = math.sqrt(ex * ex + ez * ez)
			local nx, nz = -ez / len, ex / len
			if (cx - a.X) * nx + (cz - a.Z) * nz < 0 then
				nx, nz = -nx, -nz
			end
			best = math.min(best, (x - a.X) * nx + (z - a.Z) * nz)
		end
		return best
	end
	local mouths = {}
	for _, m in ipairs(H.mouths) do
		local top, foot = vec(m.stairTop) + off, vec(m.stairFoot) + off
		local out = Vector3.new(foot.X - top.X, 0, foot.Z - top.Z)
		table.insert(mouths, { bearing = m.bearing, top = top, foot = foot, run = out.Magnitude, out = out.Unit,
			side = Vector3.new(-out.Unit.Z, 0, out.Unit.X), width = m.stairWidth, openW = m.openingWidth, openH = m.openingHeight })
	end

	-- the horn's floor triangle (world x, z); margin > 0 shrinks it
	local tri = {}
	for _, p in ipairs(H.horn.floorTriangle) do
		table.insert(tri, Vector3.new(p[1] + off.X, 0, p[3] + off.Z))
	end
	local function inTriangle(x: number, z: number, margin: number): boolean
		for i = 1, 3 do
			local a, b = tri[i], tri[i % 3 + 1]
			local ex, ez = b.X - a.X, b.Z - a.Z
			local len = math.sqrt(ex * ex + ez * ez)
			local nx, nz = -ez / len, ex / len
			if (off.X - a.X) * nx + (off.Z - a.Z) * nz < 0 then
				nx, nz = -nx, -nz
			end
			if (x - a.X) * nx + (z - a.Z) * nz < margin then
				return false
			end
		end
		return true
	end

	-- 1) the deck: the platform (and the horn's floor slab) alone, so the sails standing on it do not count
	local floorPart = horn:FindFirstChild("M1_Horn_HornFloor")
	local deckParams = RaycastParams.new()
	deckParams.FilterType = Enum.RaycastFilterType.Include
	deckParams.FilterDescendantsInstances = { platform, floorPart :: Instance }
	deckParams.RespectCanCollide = true
	local samples, holes, offHeight, covered = 0, 0, 0, 0
	local firstBad: string? = nil
	for x = math.ceil(lo.X), math.floor(hi.X) do
		for z = math.ceil(lo.Z), math.floor(hi.Z) do
			if inside(x, z) >= 0.5 then
				samples += 1
				local hit = workspace:Raycast(Vector3.new(x, deckY + 2.5, z), Vector3.new(0, -5, 0), deckParams)
				if not hit then
					holes += 1
					firstBad = firstBad or string.format("hole at (%.0f, %.0f)", x - off.X, z - off.Z)
				elseif math.abs(hit.Position.Y - deckY) > 0.08 then
					offHeight += 1
					firstBad = firstBad or string.format("(%.0f, %.0f) is %+.2f on %s", x - off.X, z - off.Z, hit.Position.Y - deckY, hit.Instance.Name)
				end
				local above = workspace:Raycast(Vector3.new(x, deckY + 60, z), Vector3.new(0, -59.5, 0), params)
				if above and above.Position.Y > deckY + 0.3 and not inTriangle(x, z, -1) then
					covered += 1
				end
			end
		end
	end
	if holes + offHeight > 0 then
		fail("deck: %d holes and %d places off the deck's height in %d samples (first: %s)", holes, offHeight, samples, tostring(firstBad))
	else
		note("deck: solid at y %.2f under all %d samples of the polygon (%d of them stand under a sail or a fin)", deckY - off.Y, samples, covered)
	end

	-- 2) the stairs
	for _, m in ipairs(mouths) do
		local worstStep, worstSlope, onRamp, n = 0, 0, 0, 0
		for _, lateral in ipairs({ 0, m.width / 2 - 1.5, -(m.width / 2 - 1.5) }) do
			local prev: number? = nil
			local d = -1
			while d <= m.run + 4 do
				local p = m.top + m.out * d + m.side * lateral
				local hit = workspace:Raycast(Vector3.new(p.X, deckY + 3, p.Z), Vector3.new(0, -(deckY - knollY + 3.2), 0), params)
				local y = if hit then math.max(hit.Position.Y, knollY) else knollY
				if hit and hit.Instance.Name == string.format("StairRamp_%03d", math.round(m.bearing)) then
					onRamp += 1
				end
				if prev then
					local step = math.abs(y - prev)
					worstStep = math.max(worstStep, step)
					worstSlope = math.max(worstSlope, math.deg(math.atan2(step, 0.2)))
				end
				prev = y
				n += 1
				d += 0.2
			end
		end
		if worstStep > 0.25 or worstSlope > 46 then
			fail("stair %d: a step of %.2f studs or a slope of %.0f degrees in %d samples (%d on the ramp)", m.bearing, worstStep, worstSlope, n, onRamp)
		else
			note("stair %d: one slope, steepest %.1f degrees, largest step %.2f (%d samples, %d on the ramp)", m.bearing, worstSlope, worstStep, n, onRamp)
		end
	end

	-- 3) the interior
	local floorSamples, floorBad = 0, 0
	for x = -18, 18 do
		for z = -21, 11 do
			if inTriangle(x + off.X, z + off.Z, 1) then
				floorSamples += 1
				local hit = workspace:Raycast(Vector3.new(x + off.X, floorY + 2, z + off.Z), Vector3.new(0, -4, 0), params)
				if not (hit and math.abs(hit.Position.Y - floorY) <= 0.05) then
					floorBad += 1
				end
			end
		end
	end
	if floorBad > 0 then
		fail("interior floor: %d of %d samples are not at y %.2f", floorBad, floorSamples, floorY - off.Y)
	else
		note("interior floor: solid at y %.2f under all %d samples", floorY - off.Y, floorSamples)
	end
	for _, h in ipairs({ 1.5, 4.5 }) do
		local origin = Vector3.new(off.X, floorY + h, off.Z)
		local leaks, open = 0, {}
		for deg = 0, 359 do
			local hit = workspace:Raycast(origin, dirOf(deg) * 30, params)
			local dist = if hit then (hit.Position - origin).Magnitude else math.huge
			if dist > 22.5 then
				local viaMouth = false
				for _, m in ipairs(mouths) do
					local diff = math.abs((deg - m.bearing + 180) % 360 - 180)
					if diff <= math.deg(math.atan2(m.openW / 2, H.horn.floorInradius)) + 1 then
						viaMouth = true
						open[m.bearing] = (open[m.bearing] or 0) + 1
					end
				end
				if not viaMouth then
					leaks += 1
				end
			end
		end
		local widths = {}
		for _, m in ipairs(mouths) do
			table.insert(widths, string.format("%d: %.1f", m.bearing, 2 * H.horn.floorInradius * math.tan(math.rad((open[m.bearing] or 0) / 2))))
			if (open[m.bearing] or 0) < 10 then
				fail("mouth %d is closed at %.1f studs above the floor", m.bearing, h)
			end
		end
		if leaks > 0 then
			fail("interior walls: %d of 360 rays at %.1f above the floor leave the horn outside the mouths", leaks, h)
		else
			note("interior walls at %.1f above the floor: closed except the mouths (clear widths %s)", h, table.concat(widths, ", "))
		end
	end

	-- 4) the mantle, with the game's own tests (MovementController.findLedge, ground mode)
	local edgeSamples, edgeOk = 0, 0
	local firstEdge: string? = nil
	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		local e = b - a
		local len = e.Magnitude
		local n = Vector3.new(-e.Z, 0, e.X).Unit
		if (cx - a.X) * n.X + (cz - a.Z) * n.Z > 0 then
			n = -n -- outward
		end
		local s = 0.75
		while s < len - 0.5 do
			local p = a + e.Unit * s
			local atStair = false
			for _, m in ipairs(mouths) do
				local rel = p - m.top
				if math.abs(rel:Dot(m.side)) < m.width / 2 + 0.75 and rel:Dot(m.out) > -3 then
					atStair = true
				end
			end
			if not atStair then
				edgeSamples += 1
				local ok, why = false, "no wall"
				local wall: RaycastResult? = nil
				for _, h in ipairs({ 1.0, 2.4 }) do
					local r = workspace:Raycast(Vector3.new(p.X, knollY + h, p.Z) + n * 2, -n * 4, params)
					if r and math.abs(r.Normal.Y) < 0.6 and r.Normal:Dot(-n) < -0.45 and visible(r.Instance) then
						if not wall or r.Distance < wall.Distance then
							wall = r
						end
					end
				end
				if wall then
					why = "no top"
					for _, inset in ipairs({ 0.55, 0.15 }) do
						local q = wall.Position - n * inset
						local r = workspace:Raycast(Vector3.new(q.X, knollY + 6.5 + 0.6, q.Z), Vector3.new(0, -(6.5 + 1 - 2.2), 0), params)
						if r and r.Normal.Y >= 0.7 and visible(r.Instance) then
							local height = r.Position.Y - knollY
							if height >= 2.2 and height <= 6.5 then
								if workspace:Raycast(Vector3.new(p.X, r.Position.Y + 0.35, p.Z) + n * 2, -n * 2.8, params) then
									why = "the lip is blocked"
								else
									ok = true
								end
								break
							else
								why = string.format("the top is %.2f above the knoll", height)
							end
						end
					end
				end
				if ok then
					edgeOk += 1
				else
					firstEdge = firstEdge or string.format("(%.1f, %.1f): %s", p.X - off.X, p.Z - off.Z, why)
				end
			end
			s += 1.5
		end
	end
	if edgeOk < edgeSamples then
		fail("mantle: %d of %d edge samples fail the ledge test (first: %s)", edgeSamples - edgeOk, edgeSamples, tostring(firstEdge))
	else
		note("mantle: the ledge test passes at all %d edge samples away from the stairs (deck %.2f above the knoll)", edgeSamples, deckY - knollY)
	end

	-- 5) pockets: a contender-sized box over the deck
	local probe = Instance.new("Part")
	probe.Name = "Map1AssetsProbe"
	probe.Size = Vector3.new(2, 4.6, 2)
	probe.Anchored = true
	probe.Transparency = 1
	probe.CanCollide = false
	probe.CanQuery = false
	probe.CanTouch = false
	probe.Parent = parent
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { horn, platform }
	overlap.RespectCanCollide = true
	overlap.MaxParts = 1
	local x0, x1, z0, z1 = math.ceil(lo.X), math.floor(hi.X), math.ceil(lo.Z), math.floor(hi.Z)
	local free: { [number]: boolean } = {}
	local width = x1 - x0 + 1
	local function key(x: number, z: number): number
		return (z - z0) * width + (x - x0)
	end
	local freeCount = 0
	for x = x0, x1 do
		for z = z0, z1 do
			if inside(x, z) >= 1 then
				probe.CFrame = CFrame.new(x, deckY + 0.35 + 2.3, z)
				if #workspace:GetPartsInPart(probe, overlap) == 0 then
					free[key(x, z)] = true
					freeCount += 1
				end
			end
		end
	end
	probe:Destroy()
	local reached: { [number]: boolean } = {}
	local queue = {}
	for _, m in ipairs(mouths) do
		local s = m.top - m.out * 1.5
		local sx, sz = math.round(s.X), math.round(s.Z)
		if free[key(sx, sz)] and not reached[key(sx, sz)] then
			reached[key(sx, sz)] = true
			table.insert(queue, { sx, sz })
		end
	end
	local head, reachedCount = 1, #queue
	while head <= #queue do
		local c = queue[head]
		head += 1
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nx, nz = c[1] + d[1], c[2] + d[2]
			if nx >= x0 and nx <= x1 and nz >= z0 and nz <= z1 then
				local k = key(nx, nz)
				if free[k] and not reached[k] then
					reached[k] = true
					reachedCount += 1
					table.insert(queue, { nx, nz })
				end
			end
		end
	end
	local inHorn = 0
	local pocket, firstPocket = 0, nil
	for x = x0, x1 do
		for z = z0, z1 do
			local k = key(x, z)
			if free[k] then
				if reached[k] then
					if inTriangle(x, z, 0) then
						inHorn += 1
					end
				else
					pocket += 1
					firstPocket = firstPocket or string.format("(%d, %d)", x - off.X, z - off.Z)
				end
			end
		end
	end
	if pocket > 0 then
		fail("pockets: %d free places on the deck cannot be reached from a stair (first at %s): a contender could be shut in there", pocket, tostring(firstPocket))
	elseif #queue == 0 then
		fail("pockets: no free place at the top of any stair")
	else
		note("pockets: none. %d free places on the deck, all reached from the stairs (%d of them inside the horn)", freeCount, inHorn)
	end

	-- 6) the plinths
	local list = plinths:GetChildren()
	table.sort(list, function(x, y)
		return x.Name < y.Name
	end)
	local okPlinths, lastBearing = 0, -1
	for i, pl in ipairs(list) do
		local stand = pl:FindFirstChild("Stand", true)
		local problem: string? = nil
		if pl.Name ~= string.format("Plinth%02d", i) or not pl:IsA("Model") then
			problem = "name or class"
		elseif not (stand and stand:IsA("Attachment")) then
			problem = "no Stand"
		else
			local sp = stand.WorldPosition
			local base = (pl :: Model):GetPivot().Position
			local flat = Vector3.new(sp.X - off.X, 0, sp.Z - off.Z)
			local bearing = math.deg(math.atan2(flat.X, -flat.Z)) % 360
			local toCentre = Vector3.new(off.X - sp.X, 0, off.Z - sp.Z).Unit
			if math.abs(sp.Y - base.Y - H.plinth.standHeight) > 0.01 then
				problem = string.format("Stand is %.3f above the base", sp.Y - base.Y)
			elseif math.abs(flat.Magnitude - H.plinthRingRadius) > 0.05 then
				problem = string.format("radius %.2f", flat.Magnitude)
			elseif stand.WorldCFrame.LookVector:Dot(toCentre) < 0.999 then
				problem = "Stand does not face the centre"
			elseif bearing <= lastBearing then
				problem = "not in ring order"
			elseif not CollectionService:HasTag(pl, "Plinth") then
				problem = "no Plinth tag"
			end
			lastBearing = bearing
		end
		if problem then
			fail("%s: %s", pl.Name, problem)
		else
			okPlinths += 1
		end
	end
	if #list ~= H.plinth.count then
		fail("plinths: %d children in %s, want exactly %d", #list, plinths:GetFullName(), H.plinth.count)
	elseif okPlinths == #list then
		note("plinths: %d, Plinth01..%02d in ring order, every Stand %.1f above its base, facing the centre, on the r %d ring", #list, #list, H.plinth.standHeight, H.plinthRingRadius)
	end

	table.insert(lines, if fails == 0 then "PASS: the heart's collision and plinths check out" else string.format("FAIL: %d problems", fails))
	return table.concat(lines, "\n")
end

return Assets
