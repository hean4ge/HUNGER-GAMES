--[[
	WeaponsV3Assets - edit-time builder for the WeaponsV3 weapon templates (art/blender/weapons_v3.py, Combat_v3 5):
	  Assets.Items.<id>_t1 .. <id>_t5   every starred weapon at every star (Shared.TierLooks swaps them in by stars)
	  Assets.Items.paired_blades_L_t1 .. _t5   the pair's left blade (InventoryService's OffHand build)
	  Assets.Items.<id>                 the base template = that weapon's 2-star mesh, so every build path shows a mesh
	  Assets.Items.throwing_knife / arrow / wire_snare   the unstarred WeaponsV3 meshes
	Source: WeaponsV3.glb, uploaded once (19 Nov 2026, the owner's yes) as the Model asset LS_WeaponsV3_v1
	(Manifest.SOURCE; ledger art/manifests/WeaponsV3.manifest.json "uploads"). The raw insert stays in
	ServerStorage.MeshImports.LS_WeaponsV3_v1 (a package; never edit it; build() loads it when missing).

	The importer drops colours: every part is SmoothPlastic in the manifest's own rgb, Reflectance 0 (the owner, 19 Nov:
	no Roblox tiled Wood or Metal on held items; matte, steel warm-neutral). Parts carry attribute Role (the
	Stars.applyFinish role) and PartRole (the art role); bow strings (role Rope) carry String.
	Template layout as ItemAssets / ItemModels: Handle = invisible 0.05 Part at CFrame.identity (PrimaryPart), the
	Grip turned into the ItemModels convention (LookVector = business end, UpVector = spine / back, edges -UpVector;
	the bow's UpVector is its shooting direction), meshes welded to Handle, Massless, no collision / query / touch.
	Attachments in Handle: Grip (identity) + the manifest's Tip, Nock, StringTop, StringBottom, ArrowRest, Spin,
	FingerRing. Bow Nock: attributes RestPosition and MaxDraw. Model attributes ItemId, Kind, Stars, Source, AssetId.

	Run in Edit (require a Clone so Studio does not serve a cached copy):
	  print(require(game.ServerStorage.WorldGen.WeaponsV3Assets:Clone()).build())
	  print(require(game.ServerStorage.WorldGen.WeaponsV3Assets:Clone()).verify())
	Templates it replaces (anything not from this source) go to ServerStorage.Archive_v1.ItemTemplates_preV3 once.
]]
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Manifest = require(script:WaitForChild("Manifest"))

local WeaponsV3Assets = {}

local HANDLE = {
	default = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.zAxis), -- Look +Y, Up +Z (spine), Right +X (flat)
	bow = CFrame.fromMatrix(Vector3.zero, -Vector3.xAxis, -Vector3.zAxis), -- Look +Y (top limb), Up -Z (shooting)
}
local BOW_MAX_DRAW = 1.12
local HANDLE_SIZE = Vector3.new(0.05, 0.05, 0.05)
local SIZE_TOLERANCE = 0.03

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
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

local function isBow(a: any): boolean
	return a.id == "bow" or a.id == "short_bow"
end

-- An asset's item frame in the import: the importer keeps the GLB row and bakes no turn into the geometry (checked
-- here against the manifest's bounds), so the Grip sits at the world bounds' centre minus the manifest's centre.
local function locate(a: any, index: { [string]: MeshPart }): (CFrame?, string?)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in ipairs(a.parts) do
		local part = index[p.name]
		if not part then
			return nil, "missing mesh " .. p.name
		end
		local h = part.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local w = part.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					lo = lo:Min(w)
					hi = hi:Max(w)
				end
			end
		end
	end
	local size = hi - lo
	local want = vec(a.bmax) - vec(a.bmin)
	if (size - want).Magnitude > SIZE_TOLERANCE then
		return nil, string.format("measures %s, manifest %s (turned?)", tostring(size), tostring(want))
	end
	local centre = (lo + hi) / 2 - (vec(a.bmin) + vec(a.bmax)) / 2
	return CFrame.new(centre), nil
end

local function attachmentFrame(t: any): CFrame
	local pos = vec(t.pos)
	return CFrame.lookAt(pos, pos + vec(t.look), vec(t.up))
end

local function buildOne(name: string, a: any, index: { [string]: MeshPart }, pivot: CFrame): Model
	local Hinv = (if isBow(a) then HANDLE.bow else HANDLE.default):Inverse()
	local toItem = pivot:Inverse()
	local model = Instance.new("Model")
	model.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = HANDLE_SIZE
	handle.Transparency = 1
	handle.CastShadow = false
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = CFrame.identity
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = model
	model.PrimaryPart = handle
	for _, info in ipairs(a.parts) do
		local source = index[info.name]
		local part = source:Clone()
		for _, child in ipairs(part:GetChildren()) do
			child:Destroy() -- importer leftovers
		end
		part.Name = info.name
		part.TextureID = ""
		part.Material = Enum.Material.SmoothPlastic
		part.MaterialVariant = ""
		part.Color = Color3.fromRGB(info.rgb[1], info.rgb[2], info.rgb[3])
		part.Reflectance = 0
		part.Transparency = 0
		part.CastShadow = true
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		pcall(function()
			part.DoubleSided = false
			part.RenderFidelity = Enum.RenderFidelity.Automatic
		end)
		part.CFrame = Hinv * (toItem * source.CFrame)
		part:SetAttribute("Role", if info.finish ~= "" then info.finish else nil)
		part:SetAttribute("PartRole", info.role)
		if isBow(a) and info.role == "Rope" then
			part:SetAttribute("String", true)
		end
		part.Parent = model
		local w = Instance.new("Weld")
		w.Name = "Weld"
		w.Part0 = handle
		w.Part1 = part
		w.C0 = part.CFrame
		w.Parent = part
	end
	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.Parent = handle
	for attName, att in pairs(a.att) do
		if attName ~= "Grip" then
			local at = Instance.new("Attachment")
			at.Name = attName
			at.CFrame = Hinv * attachmentFrame(att)
			at.Parent = handle
		end
	end
	if isBow(a) then
		local nock = handle:FindFirstChild("Nock") :: Attachment
		if nock then
			nock:SetAttribute("RestPosition", nock.Position)
			nock:SetAttribute("MaxDraw", BOW_MAX_DRAW)
		end
	end
	model:SetAttribute("ItemId", a.id)
	model:SetAttribute("Kind", a.kind)
	model:SetAttribute("Stars", a.stars)
	model:SetAttribute("Source", Manifest.SOURCE.name)
	model:SetAttribute("AssetId", Manifest.SOURCE.assetId)
	return model
end

-- Puts `model` in `items` as `name`, archiving a template from any other source the first time.
local function install(items: Folder, archive: Folder, name: string, model: Model)
	local old = items:FindFirstChild(name)
	if old then
		if old:GetAttribute("Source") ~= Manifest.SOURCE.name and not archive:FindFirstChild(name) then
			old.Parent = archive
		else
			old:Destroy()
		end
	end
	model.Name = name
	model.Parent = items
end

function WeaponsV3Assets.build(): string
	local t0 = os.clock()
	local raw = sourceModel()
	local index: { [string]: MeshPart } = {}
	for _, d in ipairs(raw:GetDescendants()) do
		if d:IsA("MeshPart") then
			index[d.Name] = d
		end
	end
	local assets = ensureFolder(ReplicatedStorage, "Assets")
	local items = ensureFolder(assets, "Items")
	local archive = ensureFolder(ensureFolder(ServerStorage, "Archive_v1"), "ItemTemplates_preV3")
	local names = {}
	for name in pairs(Manifest.Items) do
		table.insert(names, name)
	end
	table.sort(names)
	local built, problems = 0, {}
	for i, name in ipairs(names) do
		local a = Manifest.Items[name]
		local pivot, why = locate(a, index)
		if not pivot then
			table.insert(problems, name .. ": " .. tostring(why))
		else
			local model = buildOne(name, a, index, pivot)
			install(items, archive, name, model)
			built += 1
			if a.stars == 2 and a.id ~= "paired_blades_L" then
				local base = model:Clone()
				install(items, archive, a.id, base) -- the base template is the 2-star look
			end
		end
		if i % 8 == 0 then
			task.wait()
		end
	end
	return string.format("WeaponsV3Assets: %d templates in %.1f s; %d problems%s", built, os.clock() - t0, #problems,
		if #problems > 0 then ": " .. table.concat(problems, "; ") else "")
end

-- Read-back: every template exists, has its parts, SmoothPlastic, the manifest colour, its attachments.
function WeaponsV3Assets.verify(): string
	local items = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Items")
	if not items then
		return "no ReplicatedStorage.Assets.Items"
	end
	local bad, checked = {}, 0
	for name, a in pairs(Manifest.Items) do
		local m = items:FindFirstChild(name)
		if not (m and m:IsA("Model") and m.PrimaryPart) then
			table.insert(bad, name .. " missing")
		else
			checked += 1
			for _, info in ipairs(a.parts) do
				local p = m:FindFirstChild(info.name)
				if not (p and p:IsA("MeshPart")) then
					table.insert(bad, name .. "." .. info.name .. " missing")
				elseif p.Material ~= Enum.Material.SmoothPlastic or p.Color ~= Color3.fromRGB(info.rgb[1], info.rgb[2], info.rgb[3]) then
					table.insert(bad, name .. "." .. info.name .. " look")
				end
			end
			for attName in pairs(a.att) do
				if not m.PrimaryPart:FindFirstChild(attName) then
					table.insert(bad, name .. " no " .. attName)
				end
			end
		end
	end
	return string.format("verify: %d templates checked, %d problems%s", checked, #bad, if #bad > 0 then ": " .. table.concat(bad, "; ", 1, math.min(#bad, 20)) else "")
end

return WeaponsV3Assets
