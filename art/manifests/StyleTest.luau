--[[
	StyleTest (ServerStorage.StyleTest.StyleTestBuilder) - edit-time builder for the three Blender style-test variants
	and the side-by-side diorama the owner compares them in:
	  A  Low-poly realism        art/blender/style_a.py   BlenderExports/StyleTest/A/StyleTest_A.glb
	  B  Blocky voxel realism    art/blender/style_b.py   BlenderExports/StyleTest/B/StyleTest_B.glb
	  C  Smooth stylized realism art/blender/style_c.py   BlenderExports/StyleTest/C/StyleTest_C.glb
	Each GLB was uploaded once as a Model asset; every id is in art/manifests/StyleTest.assetIds.json and in the
	generated Manifest child (art/blender/rbx_styletest_manifest.py). Nothing here runs at game time.

	Run in Edit mode (require a Clone so Studio does not serve a cached copy):
	  local S = require(game.ServerStorage.StyleTest.StyleTestBuilder:Clone())
	  print(S.build())       -- ServerStorage.StyleTest.Templates.<A|B|C>.<Asset> from the raw inserts
	  print(S.verify())      -- read-back check of the templates against the manifest
	  print(S.materials())   -- MaterialService.StyleTest: StyleTest_<V>_Pebble / _ForestFloor (Ground base)
	  print(S.diorama())     -- Workspace.StyleTest: three identical scenes around (7000, 300, 0)
	  print(S.labels(true))  -- the floating variant labels (off for captures)
	  S.shot("A", "wide")    -- camera position, look-at position (world) for screen_capture

	Raw inserts: ServerStorage.StyleTest.Raw.LS_StyleTest_<V>_v1 (packages; never edit them).
	What the Open Cloud importer does to these GLBs, and what build() fixes on the copies:
	  - It bakes a 180 degree turn about Y into the mesh data (and insert_asset may add a yaw). Measured from the row
	    of assets and undone; every template's WorldPivot is the manifest origin (base centre, front = -Z).
	  - It builds one SurfaceAppearance per part from the embedded images. ColorMap / NormalMap are the importer's
	    own uploads (pixel-checked against the PNGs). Its RoughnessMap is the G channel of the packed glTF
	    metallicRoughness at its embedded size, which is half the grayscale PNG for A Spruce/Oak/Cabin/CabinRoof and
	    for all of B: those copies use the uploaded full-size PNG. For A Boulder and all of C the embedded map is
	    full size and pixel-identical, so the importer's image is kept. The importer also adds a flat-black
	    metalness map; the copies leave MetalnessMap empty, as the manifests ask.
	  - AlphaMode is set from the manifest (Overlay on every part of these sets: none of them uses cut-out cards).
	  - Parts arrive grey Plastic, unanchored, with Default collision: material, colour, flags and
	    CollisionFidelity (rebuilt with CreateMeshPartAsync + ApplyMesh, the only way that sticks) come from the
	    manifest.
	Ground tiles: MaterialVariants on the Ground base material, used ONLY by the 12 x 12 test slabs in the diorama
	(Part.MaterialVariant). They are never terrain base-material overrides.
]]
local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local MaterialService = game:GetService("MaterialService")
local ServerStorage = game:GetService("ServerStorage")

local Manifest = require(script:WaitForChild("Manifest"))

local StyleTest = {}

-- CollectionService tags the game reads; every other manifest tag becomes the attribute Tags.
local GAME_TAGS = { Climbable = true, Floor = true }
local BOUNDS_TOLERANCE = 0.06 -- studs, template bounds vs manifest boundsMin/boundsMax

-- Diorama: three identical scenes side by side, far outside the arena. Scene-local frame: origin on the ground at
-- the scene centre, the cameras look along local +Z and every asset faces local -Z (toward the cameras).
StyleTest.DIORAMA = {
	centre = Vector3.new(7000, 300, 0), -- top of the grass pad
	spacing = 260, -- studs between scene centres (neighbours stay out of every shot)
	yaw = 90, -- degrees about Y for the whole diorama (a multiple of 90, so the slab footprints stay on the voxel grid).
	-- Chosen from test captures: at 90 the 14:00 sun lights the fronts from the cameras' left shoulder (at 180 the
	-- scenes were backlit, although Lighting:GetSunDirection() reads (-0.47, 0.81, +0.35) at 14:00).
	padSize = Vector3.new(1200, 12, 1200),
}
StyleTest.LAYOUT = {
	oak = CFrame.new(-24, 0, 16) * CFrame.Angles(0, math.rad(15), 0),
	conifer = CFrame.new(-2, 0, 40),
	cabin = CFrame.new(22, 0, 20),
	boulder = CFrame.new(-6, 0, 6) * CFrame.Angles(0, math.rad(-20), 0),
	figure = CFrame.new(4, 0, 2) * CFrame.Angles(0, math.rad(15), 0), -- fallback; normally on the porch (figureOnPorch)
	figureOnPorch = CFrame.new(-2.5, 0, -2.2) * CFrame.Angles(0, math.rad(-15), 0), -- from the cabin's Door attachment
	-- slab footprints (min corner x, z; 12 x 12), on the 4-stud voxel grid
	slabs = { Pebble = Vector2.new(-12, -20), ForestFloor = Vector2.new(4, -20) },
	slabTop = 0.2,
	pond = Vector3.new(0, 0, -30), -- in front: the wide shot looks across the water (the grass is too tall to see over)
	pondRadius = 9,
}
-- Cameras (scene-local; eye level = 5 studs, the 5.5-stud figure's eyes)
StyleTest.SHOTS = {
	wide = { cam = Vector3.new(0, 5, -44), look = Vector3.new(0, 9, 16) },
	trunk = { cam = Vector3.new(-20, 5, 5), look = Vector3.new(-24, 4.5, 16) }, -- keeps the neighbour scenes out of frame
	porch = { cam = Vector3.new(17, 5, -3), look = Vector3.new(22, 4.5, 12) }, -- keeps the neighbour scenes out of frame
	slabs = { cam = Vector3.new(2, 16, -27), look = Vector3.new(2, 0, -14) },
}
StyleTest.SHOT_ORDER = { "wide", "trunk", "porch", "slabs" }

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function image(id: string?): string -- ids are strings in the Manifest
	return if id and id ~= "" then "rbxassetid://" .. id else ""
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

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

function StyleTest.root(): Folder
	return ensureFolder(ServerStorage, "StyleTest")
end

-- The raw insert of one variant's GLB (ServerStorage.StyleTest.Raw.<source name>; loaded once if missing).
local function rawImport(v: any): Instance
	local raw = ensureFolder(StyleTest.root(), "Raw")
	local existing = raw:FindFirstChild(v.source.name)
	if existing then
		return existing
	end
	local loaded = InsertService:LoadAsset(tonumber(v.source.assetId) :: number)
	local root = loaded:GetChildren()[1] or loaded
	root.Name = v.source.name
	root.Parent = raw
	if loaded ~= root then
		loaded:Destroy()
	end
	return root
end

local function meshIndex(source: Instance): { [string]: MeshPart }
	local index = {}
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("MeshPart") then
			index[d.Name] = d
		end
	end
	return index
end

-- Where each manifest asset of one GLB sits inside its raw import, as its pivot frame. The importer keeps the GLB
-- layout (assets in a row along +X) but turns it about the vertical axis and bakes that turn into the mesh data
-- (every MeshPart reads the same rotation R0). In R0's frame the parts are axis-aligned and their bounds exact; the
-- baked turn is read off the row of assets and must be a multiple of 90 degrees. (Same method as RealAssets.)
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
				found += 1
				local h = part.Size / 2
				lo = lo:Min(rel.Position - h)
				hi = hi:Max(rel.Position + h)
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

-- CollisionFidelity ignores direct writes (it stays Default without an error): the physics is built with the wanted
-- fidelity through AssetService:CreateMeshPartAsync (up to 8 at once) and copied onto the template with ApplyMesh.
local function prefetchPhysics(assets: { [string]: any }, index: { [string]: MeshPart }): { [string]: MeshPart }
	local jobs = {}
	for _, a in pairs(assets) do
		for _, info in ipairs(a.parts) do
			local source = index[info.name]
			local fidelity = (Enum.CollisionFidelity :: any)[info.collision] or Enum.CollisionFidelity.Box
			if source and source.CollisionFidelity ~= fidelity then
				table.insert(jobs, { name = info.name, content = source.MeshContent, fidelity = fidelity })
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

local function applySurface(part: MeshPart, info: any, textures: { [string]: any })
	local t = textures[info.tex]
	assert(t and t.color and t.normal and t.rough, "texture ids missing for " .. tostring(info.tex))
	local sa = Instance.new("SurfaceAppearance")
	sa.ColorMap = image(t.color)
	sa.NormalMap = image(t.normal)
	sa.RoughnessMap = image(t.rough)
	sa.MetalnessMap = "" -- the manifests ask for no metalness map (metal 0)
	sa.AlphaMode = (Enum.AlphaMode :: any)[info.alpha] or Enum.AlphaMode.Overlay
	sa.Color = rgb(info.tint)
	sa.Parent = part
end

-- A clean copy of an imported mesh with the manifest's look and flags; `frame` is its CFrame in the template.
local function meshCopy(source: MeshPart, info: any, frame: CFrame, physics: { [string]: MeshPart }, textures: any): MeshPart
	local part = source:Clone()
	for _, child in ipairs(part:GetChildren()) do
		child:Destroy() -- importer leftovers: its SurfaceAppearance (half-size packed roughness), welds, attachments
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
		part.DoubleSided = false
	end)
	pcall(function()
		part.RenderFidelity = Enum.RenderFidelity.Automatic
	end)
	part.CastShadow = info.shadow
	part.CanCollide = info.collide
	part.CanQuery = info.query or info.collide
	part.CanTouch = info.touch
	part.Material = (Enum.Material :: any)[info.mat] or Enum.Material.SmoothPlastic
	part.Color = rgb(info.rgb)
	part.Transparency = info.transparency
	if info.tex then
		applySurface(part, info, textures)
	end
	part:SetAttribute("Role", info.role)
	local extra = {}
	for _, t in ipairs(info.tags or {}) do
		if GAME_TAGS[t] then
			CollectionService:AddTag(part, t)
		else
			table.insert(extra, t)
		end
	end
	if #extra > 0 then
		part:SetAttribute("Tags", table.concat(extra, ","))
	end
	return part
end

local function buildAsset(v: any, name: string, a: any, index: { [string]: MeshPart }, pivot: CFrame, physics: any): (Model, { string })
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
			local part = meshCopy(source, info, toAsset * source.CFrame, physics, v.textures)
			part.Parent = model
			built += 1
			local p0, p1 = boxBounds(part.CFrame, part.Size)
			lo = lo:Min(p0)
			hi = hi:Max(p1)
			main = main or part
		else
			table.insert(problems, "missing mesh " .. info.name)
		end
	end
	if built ~= #a.parts then
		table.insert(problems, string.format("%d of %d parts", built, #a.parts))
	end
	if (lo - vec(a.bmin)).Magnitude > BOUNDS_TOLERANCE or (hi - vec(a.bmax)).Magnitude > BOUNDS_TOLERANCE then
		table.insert(problems, string.format("bounds %s .. %s, manifest %s .. %s", tostring(lo), tostring(hi),
			tostring(vec(a.bmin)), tostring(vec(a.bmax))))
	end
	if main then
		for _, attName in ipairs(sortedKeys(a.att)) do
			local at = Instance.new("Attachment")
			at.Name = attName
			at.Parent = main
			at.WorldCFrame = attachmentFrame(a.att[attName])
		end
		model.PrimaryPart = main
		main.PivotOffset = main.CFrame:Inverse() -- pivot = template origin (WorldPivot writes on unparented models don't stick)
	end
	model.WorldPivot = CFrame.identity
	model:SetAttribute("AssetId", v.source.assetId)
	model:SetAttribute("Source", v.source.name)
	model:SetAttribute("Variant", v.key)
	model:SetAttribute("Style", v.style)
	model:SetAttribute("Kind", a.kind)
	model:SetAttribute("BoundsMin", vec(a.bmin))
	model:SetAttribute("BoundsMax", vec(a.bmax))
	model:SetAttribute("Size", vec(a.bmax) - vec(a.bmin))
	model:SetAttribute("Tris", a.tris)
	return model, problems
end

-- options: variants = { "A", ... } (default all)
function StyleTest.build(options: { variants: { string }? }?): string
	local keys = (options and options.variants) or Manifest.ORDER
	local lines = {}
	local function note(fmt: string, ...)
		table.insert(lines, string.format(fmt, ...))
	end
	local templates = ensureFolder(StyleTest.root(), "Templates")
	for _, key in ipairs(keys) do
		local v = Manifest.VARIANTS[key]
		assert(v, "unknown variant " .. tostring(key))
		local index = meshIndex(rawImport(v))
		local pivots, turn, problems = locateAssets(v.assets, index)
		note("%s: import turned %d degrees about Y (undone)", key, turn)
		for _, p in ipairs(problems) do
			note("%s: %s", key, p)
		end
		local physics = prefetchPhysics(v.assets, index)
		local folder = ensureFolder(templates, key)
		local parts = 0
		for _, name in ipairs(sortedKeys(v.assets)) do
			local pivot = pivots[name]
			if pivot then
				local model, assetProblems = buildAsset(v, name, v.assets[name], index, pivot, physics)
				for _, p in ipairs(assetProblems) do
					note("%s.%s: %s", key, name, p)
				end
				local old = folder:FindFirstChild(name)
				if old then
					old:Destroy()
				end
				model.Parent = folder
				parts += #v.assets[name].parts
				task.wait()
			else
				note("%s.%s: not found in the import", key, name)
			end
		end
		for _, tmp in pairs(physics) do
			tmp:Destroy()
		end
		note("%s: %d templates, %d parts in ServerStorage.StyleTest.Templates.%s", key, #sortedKeys(v.assets), parts, key)
	end
	return table.concat(lines, "\n")
end

function StyleTest.template(key: string, name: string): Model?
	local t = StyleTest.root():FindFirstChild("Templates")
	local f = t and t:FindFirstChild(key)
	local m = f and f:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end

-- Read-back of every template against the manifest. Returns problems first, then the counts.
function StyleTest.verify(): string
	local problems, counts = {}, { templates = 0, parts = 0, surfaces = 0, attachments = 0, tags = 0 }
	local function bad(fmt: string, ...)
		table.insert(problems, string.format(fmt, ...))
	end
	for _, key in ipairs(Manifest.ORDER) do
		local v = Manifest.VARIANTS[key]
		for _, name in ipairs(sortedKeys(v.assets)) do
			local a = v.assets[name]
			local m = StyleTest.template(key, name)
			if not m then
				bad("%s.%s: no template", key, name)
				continue
			end
			counts.templates += 1
			local pv = m:GetPivot()
			if pv.Position.Magnitude > 1e-4 or pv.LookVector.Z > -0.9999 or pv.UpVector.Y < 0.9999 then
				bad("%s: pivot %s (want the identity)", name, tostring(pv))
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
				local p0, p1 = boxBounds(p.CFrame, p.Size)
				lo = lo:Min(p0)
				hi = hi:Max(p1)
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
				check("CastShadow", info.shadow)
				check("CanCollide", info.collide)
				check("CanQuery", info.query or info.collide)
				check("CanTouch", info.touch)
				check("CollisionFidelity", (Enum.CollisionFidelity :: any)[info.collision])
				check("Material", (Enum.Material :: any)[info.mat])
				check("Transparency", info.transparency)
				check("TextureID", "")
				local sas = {}
				for _, c in ipairs(p:GetChildren()) do
					if c:IsA("SurfaceAppearance") then
						table.insert(sas, c)
					end
				end
				if #sas ~= 1 then
					bad("%s.%s: %d SurfaceAppearances", name, info.name, #sas)
				else
					counts.surfaces += 1
					local sa = sas[1]
					local t = v.textures[info.tex]
					if sa.ColorMap ~= image(t.color) or sa.NormalMap ~= image(t.normal) or sa.RoughnessMap ~= image(t.rough) or sa.MetalnessMap ~= "" then
						bad("%s.%s: SurfaceAppearance maps differ from the manifest", name, info.name)
					end
					if sa.AlphaMode.Name ~= info.alpha then
						bad("%s.%s: AlphaMode %s, want %s", name, info.name, sa.AlphaMode.Name, info.alpha)
					end
					if sa.Color ~= rgb(info.tint) then
						bad("%s.%s: tint %s", name, info.name, tostring(sa.Color))
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
		end
	end
	table.insert(problems, string.format("verified %d templates, %d parts, %d SurfaceAppearances, %d attachments, %d tags",
		counts.templates, counts.parts, counts.surfaces, counts.attachments, counts.tags))
	return table.concat(problems, "\n")
end

-- MaterialService.StyleTest.StyleTest_<V>_<Pebble|ForestFloor>: one MaterialVariant per ground tile, on the Ground
-- base material, with the artist's StudsPerTile and MaterialPattern. Only the diorama's test slabs use them.
function StyleTest.materials(): string
	local before = MaterialService:GetBaseMaterialOverride(Enum.Material.Ground)
	local folder = ensureFolder(MaterialService, "StyleTest")
	local lines = {}
	for _, key in ipairs(Manifest.ORDER) do
		for _, tile in ipairs({ "Pebble", "ForestFloor" }) do
			local g = Manifest.VARIANTS[key].ground[tile]
			local mv = folder:FindFirstChild(g.name)
			if not (mv and mv:IsA("MaterialVariant")) then
				mv = Instance.new("MaterialVariant")
				mv.Name = g.name
			end
			mv.BaseMaterial = Enum.Material.Ground
			mv.ColorMap = image(g.color)
			mv.NormalMap = image(g.normal)
			mv.RoughnessMap = image(g.rough)
			mv.MetalnessMap = ""
			mv.StudsPerTile = g.studsPerTile
			mv.MaterialPattern = (Enum.MaterialPattern :: any)[g.pattern] or Enum.MaterialPattern.Organic
			mv:SetAttribute("Artist", g.artistName)
			mv:SetAttribute("ArtistSuggestedBase", g.artistBase)
			mv.Parent = folder
			table.insert(lines, string.format("%s: StudsPerTile %g, %s", g.name, g.studsPerTile, mv.MaterialPattern.Name))
		end
	end
	local after = MaterialService:GetBaseMaterialOverride(Enum.Material.Ground)
	assert(after == before, "the Ground base-material override changed")
	table.insert(lines, "Ground base-material override unchanged: " .. tostring(after))
	return table.concat(lines, "\n")
end

-- Puts a model's pivot under its feet: the bottom centre of its bounding box, keeping the pivot's rotation.
local function feetPivot(m: Model)
	local cf, size = m:GetBoundingBox()
	local feet = CFrame.new((cf * CFrame.new(0, -size.Y / 2, 0)).Position) * m:GetPivot().Rotation
	if m.PrimaryPart then
		m.PrimaryPart.PivotOffset = m.PrimaryPart.CFrame:Inverse() * feet
	else
		m.WorldPivot = feet
	end
end

-- A 5.5-stud scale figure (default R15 rig in the review figure's blue-grey), feet and pivot on y = 0, facing -Z.
local FIGURE_HEIGHT = 5.5
local function scaleFigure(): Model
	-- reuse the look-check figure RealAssets made, so every review uses the same body
	local preview = ServerStorage:FindFirstChild("MeshAssets_Preview")
	local existing = preview and preview:FindFirstChild("Figure_R15_5.5", true)
	if existing and existing:IsA("Model") then
		local copy = existing:Clone()
		feetPivot(copy) -- its saved pivot was not always at the feet
		copy:PivotTo(copy:GetPivot().Rotation) -- keep its facing, move it to the origin
		return copy
	end
	local desc = Instance.new("HumanoidDescription")
	local c = Color3.fromRGB(63, 77, 101)
	desc.HeadColor, desc.TorsoColor, desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = c, c, c, c, c, c
	local rig = game:GetService("Players"):CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	rig.Parent = workspace -- the joints only assemble in the world
	rig:FindFirstChildOfClass("Humanoid"):BuildRigFromAttachments()
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	local _, size = rig:GetBoundingBox()
	rig:ScaleTo(rig:GetScale() * FIGURE_HEIGHT / size.Y)
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

-- Height of the terrain surface under (x, z), or nil. Smooth terrain does not end exactly at a FillBlock's top
-- (the pad filled to y 300 measures 302), so every scene stands on the measured surface.
local function groundY(x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = true
	local top = StyleTest.DIORAMA.centre.Y
	local r = workspace:Raycast(Vector3.new(x, top + 100, z), Vector3.new(0, -200, 0), params)
	return if r then r.Position.Y else nil
end

-- A scene's frame: its centre on the measured grass surface, turned by DIORAMA.yaw.
function StyleTest.sceneFrame(key: string): CFrame
	local D = StyleTest.DIORAMA
	local i = table.find(Manifest.ORDER, key)
	assert(i, "unknown variant " .. tostring(key))
	local f = CFrame.new(D.centre) * CFrame.Angles(0, math.rad(D.yaw), 0) * CFrame.new((i - 2) * D.spacing, 0, 0)
	local y = groundY(f.X, f.Z)
	return if y then f + Vector3.new(0, y - f.Y, 0) else f
end

-- World camera and look-at positions of one shot of one scene.
function StyleTest.shot(key: string, shotName: string): (Vector3, Vector3)
	local s = StyleTest.SHOTS[shotName]
	assert(s, "unknown shot " .. tostring(shotName))
	local f = StyleTest.sceneFrame(key)
	return f * s.cam, f * s.look
end

-- Every shot of every scene as plain numbers (for screen_capture calls).
function StyleTest.shotTable(): string
	local out = {}
	for _, key in ipairs(Manifest.ORDER) do
		for _, shotName in ipairs(StyleTest.SHOT_ORDER) do
			local c, l = StyleTest.shot(key, shotName)
			table.insert(out, string.format("%s_%s cam [%.2f, %.2f, %.2f] look [%.2f, %.2f, %.2f]", key, shotName, c.X, c.Y, c.Z, l.X, l.Y, l.Z))
		end
	end
	return table.concat(out, "\n")
end

local function slabPart(key: string, tile: string, frame: CFrame): Part
	local L = StyleTest.LAYOUT
	local g = Manifest.VARIANTS[key].ground[tile]
	local corner = L.slabs[tile]
	local p = Instance.new("Part")
	p.Name = "Slab_" .. tile
	p.Anchored = true
	p.Size = Vector3.new(12, 1, 12)
	p.CFrame = frame * CFrame.new(corner.X + 6, L.slabTop - 0.5, corner.Y + 6)
	p.Material = Enum.Material.Ground
	p.MaterialVariant = g.name
	p.Color = Color3.new(1, 1, 1) -- white: the ColorMap shows as authored
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("MaterialVariant", g.name)
	p:SetAttribute("StudsPerTile", g.studsPerTile)
	return p
end

local function snap4(v: Vector3): Vector3
	return Vector3.new(math.round(v.X / 4) * 4, math.round(v.Y / 4) * 4, math.round(v.Z / 4) * 4)
end

-- One flat grass pad under all scenes, the slab beds and the ponds. Terrain only inside the diorama's box.
local function terrainWork(frames: { [string]: CFrame }): string
	local T = workspace.Terrain
	local D = StyleTest.DIORAMA
	local L = StyleTest.LAYOUT
	local half = D.padSize / 2
	-- refuse to paint over terrain that is not ours (11 x 11 vertical probes over the pad)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { T }
	params.IgnoreWater = false
	local hits = 0
	for ix = -5, 5 do
		for iz = -5, 5 do
			local p = D.centre + Vector3.new(ix * half.X / 5, 0, iz * half.Z / 5)
			if workspace:Raycast(p + Vector3.new(0, 500, 0), Vector3.new(0, -1000, 0), params) then
				hits += 1
			end
		end
	end
	local existing = workspace:FindFirstChild("StyleTest")
	if hits > 0 and not (existing and existing:GetAttribute("TerrainPad")) then
		error(string.format("terrain already exists in the diorama box (%d of 121 probes); not painting", hits))
	end
	T:FillBlock(CFrame.new(D.centre - Vector3.new(0, D.padSize.Y / 2, 0)), D.padSize, Enum.Material.Grass)
	-- the surface voxel layer above the block keeps its material between rebuilds: reset old slab beds to grass
	local lo = D.centre - Vector3.new(half.X, 4, half.Z)
	local hi = D.centre + Vector3.new(half.X, 8, half.Z)
	T:ReplaceMaterial(Region3.new(lo, hi), 4, Enum.Material.Ground, Enum.Material.Grass)
	for _, frame in pairs(frames) do
		-- slab beds: no grass blades under the test slabs (both voxel layers at the surface)
		for _, corner in pairs(L.slabs) do
			local a = snap4(frame * Vector3.new(corner.X, -4, corner.Y)) -- snapped: the turned frame leaves 1e-13 errors
			local b = snap4(frame * Vector3.new(corner.X + 12, 4, corner.Y + 12)) -- that widen the region by a voxel
			T:ReplaceMaterial(Region3.new(a:Min(b), a:Max(b)), 4, Enum.Material.Grass, Enum.Material.Ground)
		end
		-- pond: a shallow bowl of mud filled with water to just under the grass
		local pc = frame * L.pond
		T:FillCylinder(CFrame.new(pc + Vector3.new(0, -3, 0)), 6, L.pondRadius + 2, Enum.Material.Mud)
		T:FillCylinder(CFrame.new(pc + Vector3.new(0, -1.5, 0)), 3, L.pondRadius + 2, Enum.Material.Grass)
		T:FillCylinder(CFrame.new(pc + Vector3.new(0, -1.75, 0)), 3.5, L.pondRadius, Enum.Material.Air)
		T:FillCylinder(CFrame.new(pc + Vector3.new(0, -2.25, 0)), 3, L.pondRadius, Enum.Material.Water)
	end
	return "terrain: grass pad " .. tostring(D.padSize) .. ", 6 slab beds, 3 ponds"
end

-- Workspace.StyleTest: three identical scenes (A, B, C) side by side. Each: the variant's conifer, oak, cabin and
-- boulder, its two 12 x 12 ground slabs, a 5.5-stud R15 figure, on the terrain grass, with a terrain pond in front.
function StyleTest.diorama(options: { terrain: boolean? }?): string
	local lines = {}
	local old = workspace:FindFirstChild("StyleTest")
	local frames = {}
	local function flatFrame(key: string): CFrame -- on the grid, at DIORAMA.centre.Y (for the terrain work)
		local D = StyleTest.DIORAMA
		local i = table.find(Manifest.ORDER, key) :: number
		return CFrame.new(D.centre) * CFrame.Angles(0, math.rad(D.yaw), 0) * CFrame.new((i - 2) * D.spacing, 0, 0)
	end
	for _, key in ipairs(Manifest.ORDER) do
		frames[key] = flatFrame(key)
	end
	if not options or options.terrain ~= false then
		table.insert(lines, terrainWork(frames))
	end
	for _, key in ipairs(Manifest.ORDER) do
		frames[key] = StyleTest.sceneFrame(key) -- on the measured surface
		table.insert(lines, string.format("scene %s ground y %.2f", key, frames[key].Y))
	end
	local root = Instance.new("Model")
	root.Name = "StyleTest"
	root:SetAttribute("TerrainPad", true)
	root:SetAttribute("Centre", StyleTest.DIORAMA.centre)
	root:SetAttribute("Readme", "Style test A/B/C (ServerStorage.StyleTest.StyleTestBuilder). Scene A at z +260, B at z 0, C at z -260 (x 7000, ground y 302); every scene faces -X (world), so view it from about x 6940 looking toward +X. Rebuild: require(game.ServerStorage.StyleTest.StyleTestBuilder:Clone()).diorama()")
	local figure = scaleFigure()
	local L = StyleTest.LAYOUT
	for _, key in ipairs(Manifest.ORDER) do
		local v = Manifest.VARIANTS[key]
		local frame = frames[key]
		local scene = Instance.new("Model")
		scene.Name = "Scene_" .. key
		scene:SetAttribute("Variant", key)
		scene:SetAttribute("Style", v.style)
		for _, role in ipairs({ "conifer", "oak", "cabin", "boulder" }) do
			local t = StyleTest.template(key, v.roles[role])
			assert(t, "no template for " .. key .. " " .. role)
			local copy = t:Clone()
			copy:PivotTo(frame * L[role])
			copy.Parent = scene
		end
		for tile in pairs(L.slabs) do
			slabPart(key, tile, frame).Parent = scene
		end
		local fig = figure:Clone()
		fig:PivotTo(frame * L.figure) -- moved onto the porch below, once the scene is in the workspace
		fig.Parent = scene
		-- label (off while capturing)
		local anchor = Instance.new("Part")
		anchor.Name = "LabelAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = frame * CFrame.new(0, 58, 16)
		local gui = Instance.new("BillboardGui")
		gui.Name = "Label"
		gui.Size = UDim2.fromOffset(420, 48)
		gui.MaxDistance = 2000
		gui.Enabled = false
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.2
		text.TextScaled = true
		text.Font = Enum.Font.GothamBold
		text.Text = v.label
		text.Parent = gui
		gui.Parent = anchor
		anchor.Parent = scene
		scene.Parent = root
		task.wait()
	end
	figure:Destroy()
	if old then
		old:Destroy()
	end
	root.Parent = workspace
	table.insert(lines, StyleTest.placeFigures())
	table.insert(lines, "Workspace.StyleTest: scenes " .. table.concat(Manifest.ORDER, ", "))
	return table.concat(lines, "\n")
end

-- The scale figure of each scene stands on the porch beside the door (the meadow grass would hide it up to the
-- shoulders). Re-runnable on the built diorama.
function StyleTest.placeFigures(): string
	local root = workspace:FindFirstChild("StyleTest")
	local L = StyleTest.LAYOUT
	local lines = {}
	for _, key in ipairs(Manifest.ORDER) do
		local scene = root and root:FindFirstChild("Scene_" .. key)
		local fig = scene and scene:FindFirstChild("Figure_R15_5.5")
		local cabin = scene and scene:FindFirstChild(Manifest.VARIANTS[key].roles.cabin)
		local door = cabin and cabin.PrimaryPart and cabin.PrimaryPart:FindFirstChild("Door")
		if fig and fig:IsA("Model") and door and door:IsA("Attachment") then
			feetPivot(fig)
			local spot = door.WorldCFrame * L.figureOnPorch
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { cabin }
			local hit = workspace:Raycast(spot.Position + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0), params)
			if hit then
				local look = spot.LookVector * Vector3.new(1, 0, 1)
				fig:PivotTo(CFrame.lookAt(hit.Position, hit.Position + look))
				local cf, size = fig:GetBoundingBox()
				table.insert(lines, string.format("scene %s figure on %s, feet %.2f above the grass, %.2f tall", key, hit.Instance.Name,
					cf.Y - size.Y / 2 - StyleTest.sceneFrame(key).Y, size.Y))
			end
		end
	end
	return table.concat(lines, "\n")
end

function StyleTest.labels(on: boolean): string
	local root = workspace:FindFirstChild("StyleTest")
	local n = 0
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BillboardGui") and d.Name == "Label" then
				d.Enabled = on
				n += 1
			end
		end
	end
	return string.format("%d labels %s", n, if on then "on" else "off")
end

return StyleTest
