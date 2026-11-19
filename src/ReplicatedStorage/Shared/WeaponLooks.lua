--[[
	WeaponLooks - the one look table for the new weapons (docs/design/Weapons_v2.md 1.3, 1.4) until their Blender
	meshes exist. SUPERSEDED 19 Nov 2026: every id here now has its WeaponsV3 mesh template in Assets.Items
	(ServerStorage.WorldGen.WeaponsV3Assets), so install() leaves them all alone; these part-built looks are only the
	fallback for a place without the templates. Each look is built from plain Parts in ItemModels' conventions (see ItemModels' header): Grip at the
	origin, LookVector (-Z) toward the business end, UpVector (+Y) the spine / back, cutting edges toward -Y, parts
	carry attribute Role (Steel, Wood, Leather, Rope, Brass, Cord) so Stars.applyFinish can change their finish.
	Bows keep Nock (RestPosition, MaxDraw), StringTop, StringBottom, ArrowRest and a string part with attribute String.

	WeaponLooks.install()   (server, at start) puts a stand-in template in ReplicatedStorage.Assets.Items for every id in
	                        LOOKS that has no template there yet. ItemModels.build then clones it like any mesh template,
	                        so the held item, the ground item, the hotbar picture and the viewmodel all use it.
	THE SWAP TO BLENDER MESHES: build the model in art/blender (ir_weapons.py), run the ItemAssets builder so
	  ReplicatedStorage.Assets.Items.<id> exists with the same attachments; install() then skips that id. Nothing else
	  changes. (Delete the id's entry here once its mesh ships.)
	WeaponLooks.build(id) -> Model?   one stand-in (for tests and previews)
	WeaponLooks.ids() -> { string }

	Shapes and colours are our own (no film names, emblems or signature props): see Weapons_v2 1.4.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponLooks = {}

local V3 = Vector3.new
local CF = CFrame.new
local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- matte palette (Weapons_v2 1.4)
local ASH = rgb(196, 176, 140)
local HICKORY = rgb(150, 112, 74)
local YEW = rgb(184, 150, 104)
local LEATHER = rgb(92, 64, 44)
local TAN = rgb(160, 124, 86)
local FORGED = rgb(118, 110, 100) -- (steel greys lean warm and light: the blue sky light turned neutral and dark greys navy in daylight)
local HONED = rgb(196, 188, 174)
local SATIN = rgb(176, 168, 154)
local IRON = rgb(58, 58, 60)
local CORD = rgb(52, 50, 48)
local BRASS = rgb(150, 122, 72)
local LINEN = rgb(206, 196, 172)
local RAWHIDE = rgb(196, 170, 130)

type Spec = { name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, role: string, shape: Enum.PartType?, string_: boolean? }

local function part(model: Model, handle: BasePart, spec: Spec): Part
	local p = Instance.new("Part")
	p.Name = spec.name
	p.Shape = spec.shape or Enum.PartType.Block
	p.Size = spec.size
	p.CFrame = spec.cf
	p.Color = spec.color
	-- Plain Parts have no SurfaceAppearance, so Roblox's Metal mirrors the sky (steel read glossy blue in the train,
	-- 18 Nov): steel and brass stand-ins are matte SmoothPlastic in their own colours. Role keeps the star finish.
	-- (19 Nov: no tiled Wood either; the owner called the block-built wood "copied and pasted")
	p.Material = if spec.material == M.Metal or spec.material == M.Wood then M.SmoothPlastic else spec.material
	p.Reflectance = 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Role", spec.role)
	if spec.string_ then
		p:SetAttribute("String", true)
		p.CastShadow = false
	end
	local w = Instance.new("Weld")
	w.Part0 = handle
	w.Part1 = p
	w.C0 = handle.CFrame:Inverse() * p.CFrame
	w.Parent = p
	p.Parent = model
	return p
end

local function attach(handle: BasePart, name: string, cf: CFrame, attrs: { [string]: any }?): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	if attrs then
		for k, v in pairs(attrs) do
			a:SetAttribute(k, v)
		end
	end
	a.Parent = handle
	return a
end

local function newModel(id: string): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = id
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = V3(0.05, 0.05, 0.05)
	handle.Transparency = 1
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = CFrame.identity
	handle.Parent = model
	model.PrimaryPart = handle
	attach(handle, "Grip", CFrame.identity)
	model:SetAttribute("StandIn", true)
	return model, handle
end

local TIP_DOWN = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, -Vector3.zAxis) -- look (0,-1,0): the edge side
local LOOK_UP = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.zAxis) -- look (0,1,0): a bow's shooting way
local TIP_FWD = CFrame.identity -- look (0,0,-1)

local LOOKS: { [string]: (Model, BasePart) -> () } = {}

-- Twin-Bit Axe: a long pale ash haft, a leather band at the grip, a steel collar, a broad head with two mirrored
-- flared bits (3.4 studs).
LOOKS.twin_axe = function(model, h)
	part(model, h, { name = "Haft", size = V3(0.2, 0.22, 3.4), cf = CF(0, 0, -1.25), color = ASH, material = M.Wood, role = "Wood" })
	part(model, h, { name = "Band", size = V3(0.25, 0.27, 0.6), cf = CF(0, 0, 0.05), color = LEATHER, material = M.Leather, role = "Leather" })
	part(model, h, { name = "Collar", size = V3(0.27, 0.29, 0.16), cf = CF(0, 0, -2.45), color = FORGED, material = M.Metal, role = "Steel" })
	part(model, h, { name = "Eye", size = V3(0.3, 0.42, 0.5), cf = CF(0, 0, -2.75), color = FORGED, material = M.Metal, role = "Steel" })
	for _, side in ipairs({ -1, 1 }) do
		part(model, h, { name = "Cheek", size = V3(0.14, 0.34, 0.6), cf = CF(0, side * 0.36, -2.75), color = FORGED, material = M.Metal, role = "Steel" })
		part(model, h, { name = "Bit", size = V3(0.09, 0.32, 0.95), cf = CF(0, side * 0.66, -2.75), color = FORGED, material = M.Metal, role = "Steel" })
		-- flared horns of the edge, three facets
		part(model, h, { name = "Flare", size = V3(0.08, 0.2, 0.36), cf = CF(0, side * 0.8, -2.29) * CFrame.Angles(side * math.rad(28), 0, 0), color = FORGED, material = M.Metal, role = "Steel" })
		part(model, h, { name = "Flare", size = V3(0.08, 0.2, 0.36), cf = CF(0, side * 0.8, -3.21) * CFrame.Angles(-side * math.rad(28), 0, 0), color = FORGED, material = M.Metal, role = "Steel" })
		part(model, h, { name = "Edge", size = V3(0.05, 0.06, 1.05), cf = CF(0, side * 0.85, -2.75), color = HONED, material = M.Metal, role = "Steel" })
	end
	attach(h, "Tip", CF(0, -0.88, -2.75) * TIP_DOWN)
end

-- Ring Blade: a flat steel hoop 1.7 studs across (the Blender sheet's 1.6 to 1.8; it was 2.2 and filled the first-person
-- view) in 16 straight segments with a bevelled outer strip, a cord-wrapped grip bar across the inside with a brass
-- ferrule at each end.
LOOKS.ring_blade = function(model, h)
	local r, cz, n, bevel = 0.76, -0.45, 16, 0.09
	local seg = 2 * r * math.tan(math.pi / n) + 0.02
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local pos = V3(0, r * math.sin(a), cz + r * math.cos(a))
		local rot = CFrame.Angles(-(a + math.pi / 2), 0, 0)
		part(model, h, { name = "Hoop", size = V3(0.06, 0.17, seg), cf = CF(pos) * rot, color = SATIN, material = M.Metal, role = "Steel" })
		local edge = V3(0, (r + bevel) * math.sin(a), cz + (r + bevel) * math.cos(a))
		part(model, h, { name = "Bevel", size = V3(0.03, 0.06, seg * (r + bevel) / r), cf = CF(edge) * rot, color = HONED, material = M.Metal, role = "Steel" })
	end
	-- the grip bar runs along Z through the hand, from the back of the hoop toward its middle
	part(model, h, { name = "Grip", size = V3(0.16, 0.16, 0.62), cf = CF(0, 0, 0.0), color = CORD, material = M.Fabric, role = "Cord" })
	part(model, h, { name = "Ferrule", size = V3(0.19, 0.19, 0.08), cf = CF(0, 0, 0.3), color = BRASS, material = M.Metal, role = "Brass" })
	part(model, h, { name = "Ferrule", size = V3(0.19, 0.19, 0.08), cf = CF(0, 0, -0.3), color = BRASS, material = M.Metal, role = "Brass" })
	part(model, h, { name = "Spoke", size = V3(0.05, 0.05, 0.28), cf = CF(0, 0, cz), color = SATIN, material = M.Metal, role = "Steel" })
	attach(h, "Tip", CF(0, 0, cz - r - bevel) * TIP_FWD)
end

-- Climbing Pick: a short hickory haft, a curved pick of four bent segments, a square adze at the back, a rawhide
-- wrist loop and a steel spike at the foot (2 studs).
LOOKS.climb_pick = function(model, h)
	part(model, h, { name = "Haft", size = V3(0.17, 0.19, 2.0), cf = CF(0, 0, -0.7), color = HICKORY, material = M.Wood, role = "Wood" })
	part(model, h, { name = "Wrap", size = V3(0.2, 0.22, 0.42), cf = CF(0, 0, 0.05), color = RAWHIDE, material = M.Leather, role = "Leather" })
	part(model, h, { name = "Loop", size = V3(0.05, 0.3, 0.05), cf = CF(0, -0.2, 0.3), color = RAWHIDE, material = M.Fabric, role = "Rope" })
	part(model, h, { name = "Spike", size = V3(0.09, 0.09, 0.22), cf = CF(0, 0, 0.38), color = IRON, material = M.Metal, role = "Steel" })
	part(model, h, { name = "Head", size = V3(0.2, 0.26, 0.24), cf = CF(0, 0, -1.72), color = IRON, material = M.Metal, role = "Steel" })
	local points = { V3(0, -0.2, -1.74), V3(0, -0.42, -1.76), V3(0, -0.62, -1.72), V3(0, -0.8, -1.63) }
	local prev = V3(0, -0.06, -1.72)
	for i, p in ipairs(points) do
		local mid = (prev + p) / 2
		local len = (p - prev).Magnitude + 0.04
		part(model, h, { name = "Pick", size = V3(0.09 - i * 0.012, 0.11 - i * 0.012, len), cf = CFrame.lookAt(mid, p), color = IRON, material = M.Metal, role = "Steel" })
		prev = p
	end
	part(model, h, { name = "Adze", size = V3(0.26, 0.3, 0.07), cf = CF(0, 0.26, -1.72), color = IRON, material = M.Metal, role = "Steel" })
	attach(h, "Tip", CF(0, -0.82, -1.62) * TIP_DOWN)
end

-- Short Bow: a plain flat-limbed bow (3.6 studs), limbs as tapered slabs, a leather grip block, a linen string.
-- Bow axes: LookVector up the bow to the top limb, UpVector the shooting direction, the string on the -Y side.
LOOKS.short_bow = function(model, h)
	part(model, h, { name = "Riser", size = V3(0.16, 0.2, 0.6), cf = CF(0, 0, 0), color = YEW, material = M.Wood, role = "Wood" })
	part(model, h, { name = "GripWrap", size = V3(0.19, 0.23, 0.36), cf = CF(0, 0, 0.02), color = TAN, material = M.Leather, role = "Leather" })
	local tipY, half = -0.2, 1.8
	for _, side in ipairs({ -1, 1 }) do -- -1: the top limb (-Z), 1: the bottom
		local a = V3(0, 0, side * 0.28)
		local b = V3(0, -0.06, side * 1.05)
		local c = V3(0, tipY, side * half)
		part(model, h, { name = "Limb", size = V3(0.2, 0.08, (b - a).Magnitude + 0.04), cf = CFrame.lookAt((a + b) / 2, b), color = YEW, material = M.Wood, role = "Wood" })
		part(model, h, { name = "Limb", size = V3(0.14, 0.07, (c - b).Magnitude + 0.04), cf = CFrame.lookAt((b + c) / 2, c), color = YEW, material = M.Wood, role = "Wood" })
		part(model, h, { name = "Nock", size = V3(0.08, 0.1, 0.08), cf = CF(c), color = TAN, material = M.Leather, role = "Leather" })
	end
	local stringY = tipY - 0.02
	part(model, h, { name = "String", size = V3(0.025, 0.025, half * 2), cf = CF(0, stringY, 0), color = LINEN, material = M.Fabric, role = "Rope", string_ = true })
	local up = LOOK_UP
	attach(h, "StringTop", CF(0, stringY, -half))
	attach(h, "StringBottom", CF(0, stringY, half) * CFrame.Angles(0, math.pi, 0))
	attach(h, "Nock", CF(0, stringY, -0.1) * up, { RestPosition = V3(0, stringY, -0.1), MaxDraw = 0.95 })
	attach(h, "ArrowRest", CF(0.1, 0.06, -0.1) * up)
end

-- Combat v3 5.4 / 5.5: the two new weapons (our own designs after the owner's pictures) and the pair's fallback.
local BLUED = rgb(70, 68, 66) -- near-black matte steel (a touch warm: cool greys read navy under the sky light)
local PALE_EDGE = rgb(178, 176, 168)
local GUARD_STEEL = rgb(150, 148, 142)

-- A single-edged, gently curved blade of `n` facets from z0 forward `len` studs, `h` tall at the base; a pale honed
-- edge strip along the full cutting edge (-Y) and a clipped, angled tip.
local function curvedBlade(model: Model, h: BasePart, z0: number, len: number, height: number, n: number, curve: number)
	local seg = len / n
	local y, z, a = 0, z0, 0
	for i = 1, n do
		local mid = CF(0, y, z) * CFrame.Angles(a, 0, 0) * CF(0, 0, -seg / 2)
		local hh = height * (1 - 0.12 * (i - 1) / n)
		part(model, h, { name = "Blade", size = V3(0.05, hh, seg + 0.02), cf = mid, color = BLUED, material = M.Metal, role = "Steel" })
		part(model, h, { name = "Edge", size = V3(0.035, 0.035, seg + 0.02), cf = mid * CF(0, -hh / 2 - 0.012, 0), color = PALE_EDGE, material = M.Metal, role = "Steel" })
		local nextFrame = CF(0, y, z) * CFrame.Angles(a, 0, 0) * CF(0, 0, -seg)
		y, z = nextFrame.Position.Y, nextFrame.Position.Z
		a += curve
	end
	-- the clipped tip: a short slab cut at 35 degrees from the spine down to the edge
	local tip = CF(0, y, z) * CFrame.Angles(a, 0, 0)
	part(model, h, { name = "Blade", size = V3(0.05, height * 0.55, 0.22), cf = tip * CF(0, -height * 0.18, -0.08) * CFrame.Angles(math.rad(-35), 0, 0), color = BLUED, material = M.Metal, role = "Steel" })
	part(model, h, { name = "Edge", size = V3(0.035, 0.035, 0.2), cf = tip * CF(0, -height * 0.45, -0.1) * CFrame.Angles(math.rad(12), 0, 0), color = PALE_EDGE, material = M.Metal, role = "Steel" })
	attach(h, "Tip", tip * CF(0, -height * 0.25, -0.2) * TIP_FWD)
end

-- A round guard (12 sides), a diamond-wrapped grip with raised windows and a small round pommel cap.
local function roundGuardGrip(model: Model, h: BasePart, guardZ: number, gripLen: number, guardD: number, windows: number)
	part(model, h, { name = "Guard", size = V3(0.07, guardD, guardD), cf = CF(0, 0, guardZ) * CFrame.Angles(0, math.rad(90), 0), color = GUARD_STEEL, material = M.Metal, role = "Steel", shape = Enum.PartType.Cylinder })
	local gz = guardZ + 0.04 + gripLen / 2
	part(model, h, { name = "Grip", size = V3(0.15, 0.17, gripLen), cf = CF(0, 0, gz), color = rgb(60, 60, 60), material = M.Fabric, role = "Cord" })
	for i = 1, windows do
		local z = guardZ + 0.04 + (i - 0.5) / windows * gripLen
		part(model, h, { name = "Wrap", size = V3(0.165, 0.1, 0.1), cf = CF(0, 0, z) * CFrame.Angles(math.rad(45), 0, 0), color = CORD, material = M.Fabric, role = "Cord" })
	end
	part(model, h, { name = "Pommel", size = V3(0.08, 0.2, 0.2), cf = CF(0, 0, guardZ + 0.08 + gripLen) * CFrame.Angles(0, math.rad(90), 0), color = GUARD_STEEL, material = M.Metal, role = "Steel", shape = Enum.PartType.Cylinder })
end

-- Paired Blades: one of the pair (the server welds a second build to the left hand: InventoryService). 2.7 studs: a
-- 2.0 blade of 3 facets, a 0.42 round guard, a 0.6 diamond-wrapped grip.
LOOKS.paired_blades = function(model, h)
	roundGuardGrip(model, h, -0.32, 0.6, 0.42, 5)
	curvedBlade(model, h, -0.36, 1.85, 0.2, 3, math.rad(2.5))
end

-- Wrapped Sabre (the pair's fallback): one 3.4-stud sabre, the same blade, guard and wrap.
LOOKS.wrapped_sabre = function(model, h)
	roundGuardGrip(model, h, -0.32, 0.62, 0.46, 5)
	curvedBlade(model, h, -0.36, 2.5, 0.23, 4, math.rad(2))
end

-- Leaf Dagger: 1.25 studs. A leaf blade 0.65 long, widest a third of the way up, with a central ridge; a 0.35 grip
-- with a raised spiral wrap; a ring pommel 0.22 across (12 sides, the hole through the flat).
LOOKS.leaf_dagger = function(model, h)
	local z0 = -0.2
	local widths = { 0.12, 0.2, 0.19, 0.15, 0.1, 0.05 }
	local seg = 0.65 / #widths
	for i, w in ipairs(widths) do
		local z = z0 - (i - 0.5) * seg
		part(model, h, { name = "Blade", size = V3(0.05, w, seg + 0.01), cf = CF(0, 0, z), color = BLUED, material = M.Metal, role = "Steel" })
		for _, side in ipairs({ -1, 1 }) do
			part(model, h, { name = "Edge", size = V3(0.03, 0.025, seg + 0.01), cf = CF(0, side * (w / 2 + 0.008), z), color = PALE_EDGE, material = M.Metal, role = "Steel" })
		end
	end
	-- the diamond's ridge: a raised line on both faces
	for _, side in ipairs({ -1, 1 }) do
		part(model, h, { name = "Ridge", size = V3(0.02, 0.025, 0.6), cf = CF(side * 0.03, 0, z0 - 0.3), color = rgb(92, 90, 86), material = M.Metal, role = "Steel" })
	end
	part(model, h, { name = "Bolster", size = V3(0.08, 0.15, 0.05), cf = CF(0, 0, -0.18), color = BLUED, material = M.Metal, role = "Steel" })
	part(model, h, { name = "Grip", size = V3(0.1, 0.11, 0.34), cf = CF(0, 0, 0), color = rgb(58, 56, 54), material = M.Fabric, role = "Cord" })
	for i = 1, 5 do
		part(model, h, { name = "Wrap", size = V3(0.115, 0.125, 0.03), cf = CF(0, 0, -0.14 + (i - 1) * 0.07) * CFrame.Angles(0, 0, math.rad(25)), color = CORD, material = M.Fabric, role = "Cord" })
	end
	local r, cz, n = 0.09, 0.28, 12
	local s = 2 * r * math.tan(math.pi / n) + 0.012
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		part(model, h, { name = "Ring", size = V3(0.04, 0.035, s), cf = CF(0, r * math.sin(a), cz + r * math.cos(a)) * CFrame.Angles(-(a + math.pi / 2), 0, 0), color = BLUED, material = M.Metal, role = "Steel" })
	end
	attach(h, "Tip", CF(0, 0, z0 - 0.66) * TIP_FWD)
end

-- Wire Snare (Trapper, later): a small coil of wire with a peg.
LOOKS.wire_snare = function(model, h)
	part(model, h, { name = "Coil", size = V3(0.12, 0.6, 0.6), cf = CF(0, 0, -0.3), color = SATIN, material = M.Metal, role = "Steel", shape = Enum.PartType.Cylinder })
	part(model, h, { name = "Peg", size = V3(0.1, 0.1, 0.5), cf = CF(0, 0, 0.05), color = HICKORY, material = M.Wood, role = "Wood" })
end

function WeaponLooks.ids(): { string }
	local out = {}
	for id in pairs(LOOKS) do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

function WeaponLooks.build(id: string): Model?
	local build = LOOKS[id]
	if not build then
		return nil
	end
	local model, handle = newModel(id)
	build(model, handle)
	return model
end

-- Server: a stand-in template for each id that has no mesh template yet. Returns the ids installed.
function WeaponLooks.install(): { string }
	local installed = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	if not items then
		return installed
	end
	for _, id in ipairs(WeaponLooks.ids()) do
		local existing = items:FindFirstChild(id)
		if not existing then
			local ok, model = pcall(WeaponLooks.build, id)
			if ok and model then
				model.Parent = items
				table.insert(installed, id)
			elseif not ok then
				warn("[WeaponLooks] " .. id .. " failed: " .. tostring(model))
			end
		end
	end
	return installed
end

return WeaponLooks
