--[[
	TierLooks - what each star adds to a weapon's look (docs/design/Combat_v3.md section 5). Stars.applyFinish calls it,
	so every place a weapon is built (held, first person, on the ground, the hotbar, the Loadout, the wheel) shows it.

	The rule: the SILHOUETTE stays the same at every star; DETAIL grows inside it. Everything is matte (no Reflectance,
	no Neon, no light), in the weapon's own palette:
	  1 Worn        a loose trailing strap at the grip end, two dull patches on the steel
	  2 Sound       the model as authored (nothing added)
	  3 Fine        a fuller or bevel line, a pale honed edge strip, a ferrule ring where grip meets head or guard
	  4 Superior    + a brass collar and pommel cap, two engraved bands, a row of rivets
	  5 Masterwork  + a spine or haft inlay, a layered-steel band by the edge, a cord knot and short tassel, a maker's mark

	THE MESH SWAP (19 Nov 2026: live for every starred weapon). The Blender variants are in the game as
	ReplicatedStorage.Assets.Items.<id>_t1 .. <id>_t5 (WeaponsV3.glb, built by ServerStorage.WorldGen.WeaponsV3Assets;
	same Grip as the base model, which is itself the 2-star mesh). TierLooks.Meshes lists them. The held, first-person,
	ground, crate, hotbar, Loadout and wheel models take that star's mesh parts in place of their own (aligned on Grip),
	their attachments move to the variant's (the Ring Blade's Tip and Spin moved), the stand-in trims below are skipped
	and Stars.applyFinish does not re-tint them (their colours are the finish: SmoothPlastic, matte). A model with
	attribute OffHand (the pair's left blade) takes <id>_L_t<stars>. A "view" bow keeps its Beam string (the variant's
	string mesh is left out). The trims below stay only as the fallback for an id with no variant meshes.

	API
	  TierLooks.Meshes                         { [itemId]: true } the ids whose _t1.._t5 meshes ship
	  TierLooks.apply(model, stars) -> swapped the mesh swap when the id is in Meshes (returns true), else nil
	  TierLooks.trim(model, stars)             the stand-in trims (Parts with attribute TierTrim); a second call replaces them
	  TierLooks.clear(model)                   removes the trims
	  TierLooks.count(model) -> number         trims on a model (tests, budgets)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TierLooks = {}

-- the ids whose WeaponsV3 meshes ship (uploaded 19 Nov 2026 as LS_WeaponsV3_v1; see the header)
TierLooks.Meshes = {
	knife = true, leaf_dagger = true, ring_blade = true, sword = true, machete = true, paired_blades = true,
	wrapped_sabre = true, hatchet = true, twin_axe = true, climb_pick = true, spear = true, bow = true, short_bow = true,
} :: { [string]: boolean }

local V3 = Vector3.new
local CF = CFrame.new
local rad = math.rad
local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- matte trim palette (warm-neutral steels; brass and walnut as the page's 5.2)
local C = {
	honed = rgb(200, 194, 182),
	fuller = rgb(86, 80, 74),
	ferrule = rgb(132, 126, 116),
	brass = rgb(166, 132, 74),
	engrave = rgb(64, 58, 52),
	rivet = rgb(176, 142, 82),
	inlay = rgb(122, 98, 62), -- (a set-in brass line, darker than the collars: it read as a bright stripe in first person)
	layerDark = rgb(104, 98, 90), -- the layered band: two steels close in value (dark blocks read as a zebra up close)
	layerLight = rgb(168, 162, 152),
	cord = rgb(122, 46, 40), -- oxblood cord
	cord2 = rgb(52, 50, 48), -- charcoal (the pair's second blade)
	mark = rgb(40, 36, 34),
	strap = rgb(104, 78, 54),
	patch = rgb(122, 104, 84),
	stitch = rgb(206, 192, 160),
}

--[[ Shapes per weapon, in Grip space (LookVector -Z toward the business end, +Y the spine / back, edges -Y, X the flat).
	blade: z0 (base) .. z1 (near the tip), spine / edge (y), half (thickness/2)
	grip:  z0 (front) .. z1 (end), r (radius);  guard: z of the guard / bolster;  pommel: z of the end cap
	head:  an axe or pick head: z (centre), zl (length along z), y0 (edge side) .. y1 (back), half
	haft:  z0 (under the head) .. z1 (the end), r
	ring:  the Ring Blade's hoop (centre z, radius)
	bow:   riser z0..z1, limb tips at tipZ (both ends), tipY
]]
local SPEC: { [string]: any } = {
	knife = { blade = { z0 = -0.32, z1 = -0.92, spine = 0.08, edge = -0.13, half = 0.035 }, grip = { z0 = -0.25, z1 = 0.25, r = 0.07 }, guard = -0.28, pommel = 0.29 },
	machete = { blade = { z0 = -0.45, z1 = -1.95, spine = 0.06, edge = -0.24, half = 0.035 }, grip = { z0 = -0.33, z1 = 0.42, r = 0.075 }, guard = -0.38, pommel = 0.42 },
	sword = { blade = { z0 = -0.5, z1 = -2.85, spine = 0.1, edge = -0.1, half = 0.025, double = true }, grip = { z0 = -0.38, z1 = 0.38, r = 0.065 }, guard = -0.43, pommel = 0.55 },
	paired_blades = { blade = { z0 = -0.4, z1 = -2.05, spine = 0.1, edge = -0.09, half = 0.03 }, grip = { z0 = -0.28, z1 = 0.3, r = 0.09 }, guard = -0.32, pommel = 0.36, pair = true },
	wrapped_sabre = { blade = { z0 = -0.4, z1 = -2.7, spine = 0.11, edge = -0.1, half = 0.03 }, grip = { z0 = -0.28, z1 = 0.32, r = 0.09 }, guard = -0.32, pommel = 0.38 },
	leaf_dagger = { blade = { z0 = -0.26, z1 = -0.72, spine = 0.0, edge = -0.09, half = 0.03, leaf = true }, grip = { z0 = -0.16, z1 = 0.16, r = 0.06 }, guard = -0.19, pommel = 0.28 },
	hatchet = { head = { z = -1.46, zl = 0.5, y0 = -0.48, y1 = 0.13, half = 0.05 }, haft = { z0 = -1.15, z1 = 0.38, r = 0.075 } },
	twin_axe = { head = { z = -2.75, zl = 0.95, y0 = -0.85, y1 = 0.85, half = 0.05, twin = true }, haft = { z0 = -2.35, z1 = 0.4, r = 0.11 } },
	climb_pick = { head = { z = -1.72, zl = 0.24, y0 = -0.8, y1 = 0.3, half = 0.1, pick = true }, haft = { z0 = -1.58, z1 = 0.28, r = 0.095 } },
	spear = { pole = { headZ0 = -3.42, headZ1 = -4.3, haftZ0 = -3.38, haftZ1 = 2.5, r = 0.09, butt = 2.55 } },
	ring_blade = { ring = { cz = -0.45, r = 0.76 }, grip = { z0 = -0.3, z1 = 0.3, r = 0.08 } },
	bow = { bow = { z0 = -0.3, z1 = 0.3, r = 0.09, tipZ = 2.2, tipY = -0.32 } },
	short_bow = { bow = { z0 = -0.18, z1 = 0.2, r = 0.1, tipZ = 1.8, tipY = -0.2 } },
}

local function gripFrame(model: Model): (BasePart?, CFrame)
	local handle = model.PrimaryPart
	if not handle then
		return nil, CFrame.identity
	end
	local grip = handle:FindFirstChild("Grip")
	return handle, handle.CFrame * (if grip and grip:IsA("Attachment") then grip.CFrame else CFrame.identity)
end

type Ctx = { model: Model, handle: BasePart, frame: CFrame, n: number }

local function add(ctx: Ctx, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = "Trim"
	p.Shape = shape or Enum.PartType.Block
	p.Size = V3(math.max(size.X, 0.012), math.max(size.Y, 0.012), math.max(size.Z, 0.012))
	p.CFrame = ctx.frame * cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Reflectance = 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("TierTrim", true)
	local w = Instance.new("Weld")
	w.Part0 = ctx.handle
	w.Part1 = p
	w.C0 = ctx.handle.CFrame:Inverse() * p.CFrame
	w.Parent = p
	p.Parent = ctx.model
	ctx.n += 1
	return p
end

-- a ring round the Z axis (a cylinder's axis is its X)
local function collar(ctx: Ctx, z: number, r: number, len: number, color: Color3, material: Enum.Material?)
	add(ctx, V3(len, r * 2, r * 2), CF(0, 0, z) * CFrame.Angles(0, rad(90), 0), color, material, Enum.PartType.Cylinder)
end

local function tassel(ctx: Ctx, z: number, color: Color3)
	-- a cord knot at the pommel and a short tassel hanging 0.3 below it (2 segments)
	add(ctx, V3(0.07, 0.07, 0.07), CF(0, -0.03, z + 0.03), color, M.Fabric, Enum.PartType.Ball)
	add(ctx, V3(0.03, 0.16, 0.03), CF(0, -0.13, z + 0.05) * CFrame.Angles(rad(12), 0, 0), color, M.Fabric)
	add(ctx, V3(0.05, 0.14, 0.05), CF(0, -0.27, z + 0.08) * CFrame.Angles(rad(8), 0, 0), color, M.Fabric)
end

local function bladeTrims(ctx: Ctx, s: any, stars: number)
	local b = s.blade
	local len = math.abs(b.z1 - b.z0)
	local midZ = (b.z0 + b.z1) / 2
	local height = b.spine - b.edge
	local faceX = b.half + 0.004
	local sides = { -1, 1 }
	if stars == 1 then
		-- Worn: a loose strap trailing off the grip end; two dull patches on the flats
		add(ctx, V3(0.025, 0.05, 0.3), CF(0, -s.grip.r * 0.6, s.grip.z1 + 0.12) * CFrame.Angles(rad(-38), rad(8), 0), C.strap, M.Leather)
		add(ctx, V3(0.008, height * 0.35, len * 0.14), CF(faceX, b.edge + height * 0.55, b.z0 - len * 0.3), C.patch)
		add(ctx, V3(0.008, height * 0.25, len * 0.1), CF(-faceX, b.edge + height * 0.4, b.z0 - len * 0.62), C.patch)
		return
	end
	if stars < 3 then
		return
	end
	-- 3 Fine: fuller (or the leaf's ridge) on both flats, the honed edge strip, a ferrule ring at the grip's front
	local fullerY = if b.leaf then 0 else b.spine - height * 0.32
	for _, side in ipairs(sides) do
		add(ctx, V3(0.008, math.max(height * 0.1, 0.022), len * 0.72), CF(side * faceX, fullerY, b.z0 - len * 0.38), C.fuller)
	end
	add(ctx, V3(b.half * 2 + 0.012, 0.024, len * 0.98), CF(0, b.edge + 0.012, midZ), C.honed)
	if b.double or b.leaf then
		add(ctx, V3(b.half * 2 + 0.012, 0.024, len * 0.98), CF(0, b.spine - 0.012, midZ), C.honed)
	end
	collar(ctx, s.grip.z0 + 0.03, s.grip.r + 0.018, 0.05, C.ferrule)
	if stars < 4 then
		return
	end
	-- 4 Superior: brass collar at the guard and a pommel cap; two engraved bands near the guard; a rivet row
	collar(ctx, s.guard - 0.005, s.grip.r + 0.03, 0.06, C.brass)
	collar(ctx, s.pommel, s.grip.r + 0.022, 0.08, C.brass)
	for i = 1, 2 do
		for _, side in ipairs(sides) do
			add(ctx, V3(0.008, height * 0.8, 0.022), CF(side * faceX, b.edge + height * 0.5, b.z0 - 0.07 - i * 0.07), C.engrave)
		end
	end
	for i = 1, 3 do
		local z = s.grip.z0 + (s.grip.z1 - s.grip.z0) * (i / 4)
		add(ctx, V3(0.03, 0.045, 0.045), CF(s.grip.r + 0.008, 0, z) * CFrame.Angles(0, 0, 0), C.rivet, M.SmoothPlastic, Enum.PartType.Cylinder)
		add(ctx, V3(0.03, 0.045, 0.045), CF(-s.grip.r - 0.008, 0, z), C.rivet, M.SmoothPlastic, Enum.PartType.Cylinder)
	end
	if stars < 5 then
		return
	end
	-- 5 Masterwork: a spine inlay, a layered-steel band by the edge, the cord knot and tassel, a maker's mark
	if b.double then
		-- a two-edged blade has no spine: the inlay runs down the fuller on both flats
		for _, side in ipairs(sides) do
			add(ctx, V3(0.01, 0.014, len * 0.55), CF(side * (faceX + 0.003), fullerY, b.z0 - len * 0.3), C.inlay)
		end
	else
		add(ctx, V3(b.half * 2 + 0.008, 0.014, len * 0.6), CF(0, b.spine - 0.006, b.z0 - len * 0.32), C.inlay)
	end
	-- the layered band: short alternating facets in a thin strip just above the honed edge
	local bands = 9
	for i = 1, bands do
		local z = b.z0 - len * (0.15 + 0.6 * (i - 0.5) / bands)
		local col = if i % 2 == 0 then C.layerLight else C.layerDark
		for _, side in ipairs(sides) do
			add(ctx, V3(0.008, math.min(height * 0.12, 0.035), len * 0.6 / bands + 0.003), CF(side * faceX, b.edge + 0.04, z), col)
		end
	end
	tassel(ctx, s.pommel + 0.04, if s.pair and ctx.model:GetAttribute("OffHand") then C.cord2 else C.cord)
	add(ctx, V3(0.01, 0.05, 0.05), CF(faceX + 0.002, b.spine - height * 0.25, b.z0 - 0.04) * CFrame.Angles(rad(45), 0, 0), C.mark)
end

local function axeTrims(ctx: Ctx, s: any, stars: number)
	local hd, hf = s.head, s.haft
	local haftLen = math.abs(hf.z1 - hf.z0)
	if stars == 1 then
		add(ctx, V3(0.025, 0.05, 0.32), CF(0, -hf.r * 0.7, hf.z1 + 0.1) * CFrame.Angles(rad(-40), rad(-6), 0), C.strap, M.Leather)
		add(ctx, V3(0.008, 0.12, 0.14), CF(hd.half + 0.004, hd.y0 * 0.5, hd.z + 0.05), C.patch)
		return
	end
	if stars < 3 then
		return
	end
	-- 3 Fine: haft ferrule under the head, a honed strip on each cutting edge
	collar(ctx, hf.z0 + 0.04, hf.r + 0.02, 0.07, C.ferrule)
	local edges = if hd.twin then { hd.y0, hd.y1 } elseif hd.pick then {} else { hd.y0 }
	for _, y in ipairs(edges) do
		local inward = if y < 0 then 1 else -1
		add(ctx, V3(hd.half * 2 + 0.016, 0.028, hd.zl * 0.92), CF(0, y + inward * 0.018, hd.z), C.honed)
	end
	if hd.pick then
		add(ctx, V3(0.012, 0.022, haftLen * 0.25), CF(hf.r + 0.004, 0, hf.z1 - 0.18), C.stitch, M.Fabric) -- wrist-loop stitching
	end
	if stars < 4 then
		return
	end
	-- 4 Superior: a brass collar under the head, two cheek bands, three haft rivets
	collar(ctx, hf.z0 + 0.14, hf.r + 0.026, 0.06, C.brass)
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, 2 do
			local y = if hd.twin then (i == 1 and 0.28 or -0.28) else hd.y0 * (0.2 + 0.18 * i)
			add(ctx, V3(0.008, 0.025, hd.zl * 0.7), CF(side * (hd.half + 0.006), y, hd.z), C.engrave)
		end
	end
	for i = 1, 3 do
		local z = hf.z1 - 0.2 - i * haftLen * 0.16
		add(ctx, V3(0.03, 0.045, 0.045), CF(hf.r + 0.008, 0, z), C.rivet, M.SmoothPlastic, Enum.PartType.Cylinder)
	end
	if stars < 5 then
		return
	end
	-- 5 Masterwork: haft inlay, layered bands by the edges, a leather collar with a cord knot and tassel at the end
	add(ctx, V3(0.014, 0.024, haftLen * 0.62), CF(0, hf.r + 0.004, (hf.z0 + hf.z1) / 2 - haftLen * 0.08), C.inlay)
	for _, y in ipairs(edges) do
		local inward = if y < 0 then 1 else -1
		for i = 1, 6 do
			local col = if i % 2 == 0 then C.layerLight else C.layerDark
			local z = hd.z - hd.zl * 0.4 + (i - 0.5) * hd.zl * 0.8 / 6
			for _, side in ipairs({ -1, 1 }) do
				add(ctx, V3(0.008, 0.06, hd.zl * 0.8 / 6 + 0.004), CF(side * (hd.half + 0.005), y + inward * 0.075, z), col)
			end
		end
	end
	collar(ctx, hf.z1 - 0.12, hf.r + 0.018, 0.14, C.strap, M.Leather)
	tassel(ctx, hf.z1, C.cord)
	add(ctx, V3(0.01, 0.05, 0.05), CF(hd.half + 0.008, if hd.twin then 0 else hd.y1 * 0.4, hd.z + hd.zl * 0.3) * CFrame.Angles(rad(45), 0, 0), C.mark)
end

local function poleTrims(ctx: Ctx, s: any, stars: number)
	local p = s.pole
	local haftLen = math.abs(p.haftZ1 - p.haftZ0)
	if stars == 1 then
		add(ctx, V3(0.025, 0.05, 0.34), CF(0, -p.r * 0.8, p.haftZ0 + 0.45) * CFrame.Angles(rad(-50), 0, 0), C.strap, M.Leather)
		return
	end
	if stars < 3 then
		return
	end
	collar(ctx, p.haftZ0 + 0.03, p.r + 0.025, 0.09, C.ferrule) -- socket ferrule
	local headLen = math.abs(p.headZ1 - p.headZ0)
	for _, side in ipairs({ -1, 1 }) do
		add(ctx, V3(0.01, 0.02, headLen * 0.7), CF(side * 0.062, 0, (p.headZ0 + p.headZ1) / 2), C.fuller) -- head bevel line
	end
	if stars < 4 then
		return
	end
	collar(ctx, p.haftZ0 + 0.12, p.r + 0.03, 0.05, C.brass) -- socket ring
	collar(ctx, p.butt, p.r + 0.02, 0.12, C.brass) -- butt cap
	for i = 1, 4 do -- binding in two colours
		collar(ctx, p.haftZ0 + 0.22 + i * 0.05, p.r + 0.012, 0.035, if i % 2 == 0 then C.cord else C.stitch, M.Fabric)
	end
	if stars < 5 then
		return
	end
	for _, side in ipairs({ -1, 1 }) do
		add(ctx, V3(0.008, 0.1, 0.03), CF(side * 0.066, 0, p.headZ0 - 0.12), C.engrave) -- engraved head band
	end
	add(ctx, V3(0.014, 0.022, haftLen * 0.55), CF(0, p.r + 0.004, p.haftZ0 + haftLen * 0.4), C.inlay) -- haft inlay
	tassel(ctx, p.haftZ0 + 0.3, C.cord) -- the small cord tassel under the head
end

local function ringTrims(ctx: Ctx, s: any, stars: number)
	local g, rg = s.grip, s.ring
	if stars == 1 then
		add(ctx, V3(0.025, 0.05, 0.26), CF(0, -0.1, g.z1 + 0.08) * CFrame.Angles(rad(-35), 0, 0), C.strap, M.Leather)
		return
	end
	if stars < 3 then
		return
	end
	for i = 1, 5 do -- the cord wrap pulled tight: raised ridges
		collar(ctx, g.z0 + 0.08 + (i - 1) * 0.11, g.r + 0.012, 0.025, C.cord2, M.Fabric)
	end
	if stars < 4 then
		return
	end
	for _, z in ipairs({ g.z0, g.z1 }) do -- engraved bands on the ferrules
		collar(ctx, z + (if z < 0 then 0.02 else -0.02), g.r + 0.035, 0.015, C.engrave)
		collar(ctx, z + (if z < 0 then -0.02 else 0.02), g.r + 0.035, 0.015, C.engrave)
	end
	if stars < 5 then
		return
	end
	-- a layered band round the outer edge: alternating dark and light facets on both faces
	local n = 16
	local r = rg.r + 0.03
	local seg = 2 * r * math.tan(math.pi / n) * 0.9
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local col = if i % 2 == 0 then C.layerLight else C.layerDark
		for _, side in ipairs({ -1, 1 }) do
			add(ctx, V3(0.008, 0.05, seg), CF(side * 0.034, r * math.sin(a), rg.cz + r * math.cos(a)) * CFrame.Angles(-(a + math.pi / 2), 0, 0), col)
		end
	end
end

local function bowTrims(ctx: Ctx, s: any, stars: number)
	local b = s.bow
	if stars == 1 then
		add(ctx, V3(0.025, 0.045, 0.3), CF(0.1, -0.05, b.z1 + 0.14) * CFrame.Angles(rad(-20), 0, rad(30)), C.strap, M.Leather)
		return
	end
	if stars < 3 then
		return
	end
	for i = 1, 4 do -- the grip wrap cross-laid
		add(ctx, V3(b.r * 2 + 0.02, 0.025, 0.035), CF(0, 0, b.z0 + (b.z1 - b.z0) * i / 5) * CFrame.Angles(0, 0, rad(if i % 2 == 0 then 30 else -30)), C.strap, M.Leather)
	end
	if stars < 4 then
		return
	end
	for _, side in ipairs({ -1, 1 }) do -- brass beads at the limb tips
		add(ctx, V3(0.08, 0.08, 0.08), CF(0, b.tipY + 0.06, side * (b.tipZ - 0.12)), C.brass, M.SmoothPlastic, Enum.PartType.Ball)
	end
	if stars < 5 then
		return
	end
	for _, side in ipairs({ -1, 1 }) do -- inlaid limb lines (dark horn) and an engraved riser band
		add(ctx, V3(0.012, 0.02, b.tipZ * 0.55), CF(0.07, -0.02, side * (b.tipZ * 0.42)) * CFrame.Angles(side * rad(4), 0, 0), C.layerDark)
	end
	collar(ctx, b.z0 - 0.04, b.r + 0.02, 0.03, C.engrave)
	collar(ctx, b.z1 + 0.04, b.r + 0.02, 0.03, C.engrave)
end

function TierLooks.clear(model: Instance)
	for _, d in ipairs(model:GetChildren()) do -- (an OffHand child model keeps its own)
		if d:IsA("BasePart") and d:GetAttribute("TierTrim") then
			d:Destroy()
		end
	end
end

function TierLooks.count(model: Instance): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("TierTrim") then
			n += 1
		end
	end
	return n
end

local function itemIdOf(model: Instance): string?
	local id = model:GetAttribute("ItemId")
	if type(id) == "string" then
		return id
	end
	return model.Name
end

--[[ SKINS (CardMenusAndShop 3.1; Shared.CosmeticLooks). A skin goes ON TOP of the star look and never changes stats:
	after every star swap or trim pass, the model's skin (attribute Skin, set by Server CosmeticService on a held model
	or by a menu's preview) recolours the parts by PartRole. A first-person ("view") model with no Skin attribute takes
	the local player's own skin for that weapon. A skin with its own SeasonOne meshes (CosmeticLooks.Models) is swapped
	in here in place of the star's mesh. ]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local cosmeticsModule: any = false
local function Cosmetics(): any
	if cosmeticsModule == false then
		local mod = script.Parent:FindFirstChild("CosmeticLooks")
		local ok, result = pcall(function()
			return if mod then require(mod :: ModuleScript) else nil
		end)
		cosmeticsModule = if ok and type(result) == "table" then result else nil
	end
	return cosmeticsModule
end

local function skinHook(model: Instance, fresh: boolean)
	local cosmetics = Cosmetics()
	if not cosmetics then
		return
	end
	local skin = model:GetAttribute("Skin")
	if skin == nil and RunService:IsClient() and model:GetAttribute("Variant") == "view" and Players.LocalPlayer then
		local id = model:GetAttribute("ItemId")
		local own = cosmetics.skinFor(cosmetics.of(Players.LocalPlayer), if type(id) == "string" then id else model.Name)
		skin = own
	end
	if type(skin) == "string" then
		local ok, err = pcall(cosmetics.applySkin, model, skin, fresh)
		if not ok then
			warn("[TierLooks] skin: " .. tostring(err))
		end
	end
end
TierLooks.skinHook = skinHook

-- The star's variant template (Assets.Items.<id>_t<stars>, or <id>_L_t<stars> for the pair's left blade); a skin's
-- own SeasonOne meshes first, when they ship.
local function variantOf(model: Instance, id: string, stars: number): Model?
	if not TierLooks.Meshes[id] then
		return nil
	end
	local cosmetics = Cosmetics()
	if cosmetics and cosmetics.skinMesh then
		local ok, skinned = pcall(cosmetics.skinMesh, model, stars)
		if ok and skinned then
			return skinned
		end
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	if not items then
		return nil
	end
	local variant = nil
	if model:GetAttribute("OffHand") then
		variant = items:FindFirstChild(string.format("%s_L_t%d", id, stars))
	end
	variant = variant or items:FindFirstChild(string.format("%s_t%d", id, stars))
	if variant and variant:IsA("Model") and variant.PrimaryPart then
		return variant
	end
	return nil
end

-- The stand-in trims of one model (not its OffHand child: that is trimmed on its own build). Only for an id whose
-- variant meshes are missing (the fallback).
function TierLooks.trim(model: Instance, stars: number)
	if not model:IsA("Model") then
		return
	end
	TierLooks.clear(model)
	local id = itemIdOf(model)
	local spec = id and SPEC[id]
	if id and variantOf(model, id :: string, stars) then
		return
	end
	skinHook(model, true) -- (the star tint has just been set: the skin goes on it; the trims keep their own colours)
	if not spec or stars == 2 then
		return
	end
	local handle, frame = gripFrame(model)
	if not handle then
		return
	end
	local ctx: Ctx = { model = model, handle = handle, frame = frame, n = 0 }
	local ok, err = pcall(function()
		if spec.blade then
			bladeTrims(ctx, spec, stars)
		elseif spec.head then
			axeTrims(ctx, spec, stars)
		elseif spec.pole then
			poleTrims(ctx, spec, stars)
		elseif spec.ring then
			ringTrims(ctx, spec, stars)
		elseif spec.bow then
			bowTrims(ctx, spec, stars)
		end
	end)
	if not ok then
		warn("[TierLooks] " .. tostring(id) .. ": " .. tostring(err))
	end
	if model:GetAttribute("Variant") == "view" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("TierTrim") then
				d.CastShadow = false
			end
		end
	end
end

-- The mesh swap (TierLooks.Meshes): the visible parts become the star's own mesh parts, aligned on Grip.
function TierLooks.apply(model: Instance, stars: number): boolean?
	if not model:IsA("Model") then
		return nil
	end
	local id = itemIdOf(model)
	if not id then
		return nil
	end
	local variant = variantOf(model, id, stars)
	if not variant then
		return nil
	end
	if model:GetAttribute("TierMesh") == variant.Name then
		skinHook(model, false)
		return true
	end
	local handle, frame = gripFrame(model)
	if not handle then
		return nil
	end
	local view = model:GetAttribute("Variant") == "view"
	local beamString = view and handle:FindFirstChild("String") ~= nil -- (ItemModels' first-person bow string)
	local anchored = handle.Anchored
	local vHandle = variant.PrimaryPart :: BasePart
	local vGrip = vHandle:FindFirstChild("Grip")
	local vFrame = vHandle.CFrame * (if vGrip and vGrip:IsA("Attachment") then vGrip.CFrame else CFrame.identity)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d ~= handle then
			d:Destroy()
		end
	end
	for _, d in ipairs(variant:GetChildren()) do
		if d:IsA("BasePart") and d ~= vHandle and not (beamString and d:GetAttribute("String")) then
			local c = d:Clone()
			for _, w in ipairs(c:GetChildren()) do
				if w:IsA("JointInstance") or w:IsA("WeldConstraint") then
					w:Destroy()
				end
			end
			c.CFrame = frame * vFrame:ToObjectSpace(d.CFrame)
			c.Anchored = anchored
			c.Massless = true
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			c.Reflectance = 0
			c.Material = Enum.Material.SmoothPlastic -- (never Roblox's tiled Wood or Metal on a weapon: the owner, 19 Nov)
			if view then
				c.CastShadow = false
			end
			local w = Instance.new("Weld")
			w.Part0 = handle
			w.Part1 = c
			w.C0 = handle.CFrame:Inverse() * c.CFrame
			w.Parent = c
			c.Parent = model
		end
	end
	-- the variant's attachments (same names; the Ring Blade's Tip and Spin moved with its new size)
	local toModel = handle.CFrame:Inverse() * frame
	for _, a in ipairs(vHandle:GetChildren()) do
		if a:IsA("Attachment") and a.Name ~= "Grip" then
			local own = handle:FindFirstChild(a.Name)
			if not (own and own:IsA("Attachment")) then
				own = Instance.new("Attachment")
				own.Name = a.Name
				own.Parent = handle
			end
			local att = own :: Attachment
			att.CFrame = toModel * vFrame:ToObjectSpace(vHandle.CFrame * a.CFrame)
			for key, value in pairs(a:GetAttributes()) do
				att:SetAttribute(key, value)
			end
		end
	end
	model:SetAttribute("TierMesh", variant.Name)
	skinHook(model, false)
	return true
end

return TierLooks
