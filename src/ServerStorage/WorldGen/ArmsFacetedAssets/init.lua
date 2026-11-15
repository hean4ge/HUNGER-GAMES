--[[
	ArmsFacetedAssets - edit-time builder for the faceted first-person arms, ReplicatedStorage.Assets.Viewmodel.ArmsFaceted
	(ViewmodelController.Rig, Config.Viewmodel.ArmStyle = "Faceted"). Source art: ArmsFaceted.glb (art/blender/
	arms_faceted.py, art/README.md section 12), uploaded once as the Model asset LS_ArmsFaceted_v1 (Manifest.SOURCE),
	plus its six texture PNGs (Manifest.IMAGES); ids in art/manifests/ArmsFaceted.manifest.json ("assetIds"). The raw
	insert is kept in ServerStorage.MeshImports (never edit it; build() loads it with InsertService when missing).
	Nothing here runs at game time.

	Run in Edit mode (require a Clone so Studio does not serve a cached copy):
	  print(require(game.ServerStorage.WorldGen.ArmsFacetedAssets:Clone()).build())    -- a few seconds
	  print(require(game.ServerStorage.WorldGen.ArmsFacetedAssets:Clone()).verify())   -- read-back check

	Templates: one Model per piece (R_/L_ UpperArm, Forearm, HandGrip, HandOpen, HandFist, HandRelaxed), in the piece's
	own space: the pivot (WorldPivot = identity) is the proximal joint, the bone runs along +Y, the back of the arm and
	hand faces -Z, the thumb is +X on R_ pieces (L_ are X mirrors).
	  MeshParts  named as in the manifest (<Piece>_Skin, <Piece>_Sleeve), Anchored, CanCollide / CanQuery / CanTouch off,
	             CastShadow off, Massless, CollisionFidelity Box, Material and Color from the manifest (fallback), one
	             SurfaceAppearance (ColorMap / NormalMap / RoughnessMap = the uploads, no MetalnessMap, AlphaMode
	             Overlay, Color = the default tint: skin Light orange, sleeve charcoal 96, 88, 80; the game sets
	             SurfaceAppearance.Color to the player's arm colour), attribute Role ("Skin" | "Sleeve").
	  Attachments under the first part, from the manifest (Shoulder, Elbow, Wrist, Grip, Palm, Knuckles).
	  Attributes Piece, Side ("R" | "L"), Source, AssetId.
	The importer bakes a turn about Y into the meshes (180 degrees, measured from the row of assets, as ItemAssets does);
	each template part's CFrame undoes it.
]]
local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manifest = require(script:WaitForChild("Manifest"))

local ArmsFacetedAssets = {}
ArmsFacetedAssets.FOLDER = "ArmsFaceted"

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end
local function image(key: string): string
	local id = Manifest.IMAGES[key]
	assert(id, "no image id for " .. key)
	return "rbxassetid://" .. tostring(id)
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

local function sourceModel(): Instance
	local info = Manifest.SOURCE
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

-- Each asset's pivot inside the raw import (see the header): asset name -> CFrame, plus problems.
local function locate(index: { [string]: MeshPart }): ({ [string]: CFrame }, { string })
	local problems = {}
	local base: CFrame? = nil
	for _, a in ipairs(Manifest.ASSETS) do
		local part = index[a.parts[1].name]
		if part then
			base = part.CFrame.Rotation
			break
		end
	end
	base = base or CFrame.identity
	local toLocal = (base :: CFrame):Inverse()
	local centres, sizes = {}, {}
	for _, a in ipairs(Manifest.ASSETS) do
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		local found = 0
		for _, p in ipairs(a.parts) do
			local part = index[p.name]
			if part then
				found += 1
				local rel = toLocal * part.CFrame
				if rel.LookVector.Z > -0.9999 or rel.UpVector.Y < 0.9999 then
					table.insert(problems, p.name .. " is turned differently from the rest of the import")
				end
				lo = lo:Min(rel.Position - part.Size / 2)
				hi = hi:Max(rel.Position + part.Size / 2)
			else
				table.insert(problems, "missing mesh " .. p.name)
			end
		end
		if found > 0 then
			centres[a.name] = (lo + hi) / 2
			sizes[a.name] = hi - lo
		end
	end
	local first, last = Manifest.ASSETS[1], Manifest.ASSETS[#Manifest.ASSETS]
	local function manifestCentre(a: any): Vector3
		return vec(a.origin) + (vec(a.bmin) + vec(a.bmax)) / 2
	end
	local yaw = 0
	if centres[first.name] and centres[last.name] then
		local dm = manifestCentre(last) - manifestCentre(first)
		local dw = centres[last.name] - centres[first.name]
		yaw = math.atan2(-dw.Z, dw.X) - math.atan2(-dm.Z, dm.X)
		local snapped = math.round(yaw / (math.pi / 2)) * (math.pi / 2)
		if math.abs(snapped - yaw) > math.rad(1) then
			table.insert(problems, string.format("import turned %.1f degrees (not a multiple of 90)", math.deg(yaw)))
		end
		yaw = snapped
	end
	local R = CFrame.Angles(0, yaw, 0)
	local pivots = {}
	for _, a in ipairs(Manifest.ASSETS) do
		local c = centres[a.name]
		if c then
			pivots[a.name] = (base :: CFrame) * CFrame.new(c - R:VectorToWorldSpace((vec(a.bmin) + vec(a.bmax)) / 2)) * R
			local size = R:VectorToObjectSpace(sizes[a.name])
			size = Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z))
			if (size - (vec(a.bmax) - vec(a.bmin))).Magnitude > 0.02 then
				table.insert(problems, string.format("%s measures %s, manifest %s", a.name, tostring(size), tostring(vec(a.bmax) - vec(a.bmin))))
			end
		end
	end
	if math.abs(yaw) > 1e-3 then
		table.insert(problems, string.format("(note) the meshes are turned %d degrees about Y inside the import; corrected", math.round(math.deg(yaw))))
	end
	return pivots, problems
end

-- Box physics for every mesh (CollisionFidelity can't be written directly: made with CreateMeshPartAsync, copied with
-- ApplyMesh), 8 at once.
local function boxPhysics(index: { [string]: MeshPart }): { [string]: MeshPart }
	local jobs = {}
	for name, part in pairs(index) do
		if part.CollisionFidelity ~= Enum.CollisionFidelity.Box then
			table.insert(jobs, { name = name, content = part.MeshContent })
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
					return AssetService:CreateMeshPartAsync(job.content, { CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic })
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

local function buildPiece(a: any, index: { [string]: MeshPart }, pivot: CFrame, physics: { [string]: MeshPart }): Model
	local model = Instance.new("Model")
	model.Name = a.name
	local toPiece = pivot:Inverse()
	local firstPart: MeshPart? = nil
	for _, info in ipairs(a.parts) do
		local source = index[info.name]
		if source then
			local part = source:Clone()
			for _, child in ipairs(part:GetChildren()) do
				child:Destroy() -- the importer's SurfaceAppearance (its own image copies), welds, attachments
			end
			local tmp = physics[info.name]
			if tmp then
				part:ApplyMesh(tmp)
			end
			part.Name = info.name
			part.TextureID = ""
			pcall(function()
				part.DoubleSided = false
			end)
			pcall(function()
				part.RenderFidelity = Enum.RenderFidelity.Automatic
			end)
			part.Material = (Enum.Material :: any)[info.mat] or Enum.Material.SmoothPlastic
			part.Color = rgb(info.rgb)
			part.Reflectance = 0
			part.Transparency = 0
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Massless = true
			part.CFrame = toPiece * source.CFrame
			local sa = Instance.new("SurfaceAppearance")
			sa.ColorMap = image(info.set .. "_Color")
			sa.NormalMap = image(info.set .. "_Normal")
			sa.RoughnessMap = image(info.set .. "_Rough")
			sa.MetalnessMap = ""
			sa.AlphaMode = Enum.AlphaMode.Overlay
			sa.Color = rgb(info.tint)
			sa.Parent = part
			part:SetAttribute("Role", info.role)
			part.Parent = model
			firstPart = firstPart or part
		end
	end
	if firstPart then
		for attName, att in pairs(a.att) do
			local pos = vec(att.pos)
			local at = Instance.new("Attachment")
			at.Name = attName
			at.Parent = firstPart
			at.WorldCFrame = CFrame.lookAt(pos, pos + vec(att.look), vec(att.up))
		end
	end
	-- no PrimaryPart: the pivot is the joint (WorldPivot), so PivotTo places a piece by its joint
	model.WorldPivot = CFrame.identity
	local side, piece = string.match(a.name, "^(%a)_(.+)$")
	model:SetAttribute("Side", side)
	model:SetAttribute("Piece", piece)
	model:SetAttribute("Source", Manifest.SOURCE.name)
	model:SetAttribute("AssetId", Manifest.SOURCE.assetId)
	return model
end

-- Builds every template into ReplicatedStorage.Assets.Viewmodel.ArmsFaceted (a previous build is replaced).
function ArmsFacetedAssets.build(target: Instance?): string
	local root = sourceModel()
	local index: { [string]: MeshPart } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("MeshPart") then
			index[d.Name] = d
		end
	end
	local pivots, problems = locate(index)
	local physics = boxPhysics(index)
	local folder = Instance.new("Folder")
	folder.Name = ArmsFacetedAssets.FOLDER
	local built = 0
	for _, a in ipairs(Manifest.ASSETS) do
		local pivot = pivots[a.name]
		if pivot then
			buildPiece(a, index, pivot, physics).Parent = folder
			built += 1
		end
	end
	for _, tmp in pairs(physics) do
		tmp:Destroy()
	end
	folder:SetAttribute("Source", Manifest.SOURCE.name)
	folder:SetAttribute("AssetId", Manifest.SOURCE.assetId)
	local viewmodel = ensureFolder(ensureFolder(target or ReplicatedStorage, "Assets"), "Viewmodel")
	local old = viewmodel:FindFirstChild(ArmsFacetedAssets.FOLDER)
	if old then
		old:Destroy()
	end
	folder.Parent = viewmodel
	return string.format("built %d pieces into %s%s", built, folder:GetFullName(),
		if #problems > 0 then "\n" .. table.concat(problems, "\n") else "")
end

-- Read-back check of the templates against the manifest.
function ArmsFacetedAssets.verify(target: Instance?): string
	local problems = {}
	local assets = (target or ReplicatedStorage):FindFirstChild("Assets")
	local viewmodel = assets and assets:FindFirstChild("Viewmodel")
	local folder = viewmodel and viewmodel:FindFirstChild(ArmsFacetedAssets.FOLDER)
	if not folder then
		return "no Assets.Viewmodel." .. ArmsFacetedAssets.FOLDER
	end
	local parts, atts = 0, 0
	for _, a in ipairs(Manifest.ASSETS) do
		local model = folder:FindFirstChild(a.name)
		if not (model and model:IsA("Model")) then
			table.insert(problems, "missing " .. a.name)
			continue
		end
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		for _, info in ipairs(a.parts) do
			local part = model:FindFirstChild(info.name)
			if not (part and part:IsA("MeshPart")) then
				table.insert(problems, "missing part " .. info.name)
				continue
			end
			parts += 1
			local cf, h = part.CFrame, part.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
						lo, hi = lo:Min(p), hi:Max(p)
					end
				end
			end
			local sa = part:FindFirstChildOfClass("SurfaceAppearance")
			if not sa or sa.ColorMap ~= image(info.set .. "_Color") or sa.NormalMap ~= image(info.set .. "_Normal")
				or sa.RoughnessMap ~= image(info.set .. "_Rough") or sa.MetalnessMap ~= "" then
				table.insert(problems, info.name .. ": SurfaceAppearance maps differ")
			end
			if part.CanCollide or part.CanQuery or part.CanTouch or part.CastShadow or not part.Anchored then
				table.insert(problems, info.name .. ": physics flags")
			end
			if part.CollisionFidelity ~= Enum.CollisionFidelity.Box then
				table.insert(problems, info.name .. ": CollisionFidelity " .. part.CollisionFidelity.Name)
			end
		end
		-- the parts' bounds match the manifest's (the importer's turn is a multiple of 90 degrees, so the boxes stay
		-- axis-aligned)
		local bmin, bmax = vec(a.bmin), vec(a.bmax)
		if (lo - bmin).Magnitude > 0.02 or (hi - bmax).Magnitude > 0.02 then
			table.insert(problems, string.format("%s bounds %s..%s, manifest %s..%s", a.name, tostring(lo), tostring(hi), tostring(bmin), tostring(bmax)))
		end
		if model.PrimaryPart or model.WorldPivot ~= CFrame.identity then
			table.insert(problems, a.name .. ": the pivot is not the joint at the origin")
		end
		for attName, att in pairs(a.att) do
			local first = model:FindFirstChild(a.parts[1].name)
			local at = first and first:FindFirstChild(attName)
			if not (at and at:IsA("Attachment")) then
				table.insert(problems, a.name .. ": missing attachment " .. attName)
			else
				atts += 1
				local want = vec(att.pos)
				if (at.WorldPosition - want).Magnitude > 1e-3 or (at.WorldCFrame.LookVector - vec(att.look).Unit).Magnitude > 1e-3 then
					table.insert(problems, a.name .. "." .. attName .. " is off")
				end
			end
		end
	end
	return string.format("verified %d pieces, %d parts, %d attachments; %s", #Manifest.ASSETS, parts, atts,
		if #problems == 0 then "no problems" else table.concat(problems, "; "))
end

return ArmsFacetedAssets
