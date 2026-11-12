--[[
	Structures - building templates for ServerStorage.WorldAssets.Structures:
	  Spire        central monument: paved platform, buttressed stone shaft, ember crown beacon, 4 braziers,
	               4 banners, 24 radial paths to the plinth ring, 10 Tier-3 loot points
	  Pavilion     open wooden pavilion for the lobby
	  RangerCabin  enterable log cabin with porch, hearth and a loft (TrussPart ladder)
	  Watchtower   ~32-stud tower, TrussPart ladder through a hatch, lookout with roof, lantern and pennant
	  WaterWheel   wheel with an "Axle" attachment (axis = model X); Populate spins it with a hinge motor
	  MillHouse    two-storey stone and timber mill; its WaterWheel child sits on the +X (river) side
	  FishingShack tin-roof shack on a deck (door faces -Z, toward the water)
	  StiltHut     thatched swamp hut on a raised deck with railings and a ladder down to the water
	Floors sit at the pivot (y = 0). Attachments named "Foot" mark where Populate adds posts down to the terrain.
]]
local Structures = {}

function Structures.build(Kit, folders)
	local P = Kit.Palette
	local M = Enum.Material
	local V = Vector3.new
	local CF = CFrame.new
	local ANG = CFrame.Angles
	local rng = Random.new(2718)
	local out = folders.Structures

	local function finish(name: string, children: { Instance? }, attrs: { [string]: any }): Model
		local list = {}
		for _, child in pairs(children) do
			if child then
				table.insert(list, child)
			end
		end
		local model = Kit.model(name, list, attrs)
		model.Parent = out
		return model
	end

	-- Clone a prop / plant template into a structure.
	local function prop(name: string, cf: CFrame): Instance?
		local template = folders.Props:FindFirstChild(name) or folders.Plants:FindFirstChild(name)
		if not template then
			warn("[Structures] missing template " .. name)
			return nil
		end
		local copy = template:Clone()
		copy:PivotTo(cf)
		return copy
	end

	local function solid(inst: Instance): Instance
		Kit.setAll(inst, Kit.SOLID)
		return inst
	end
	local function decor(inst: Instance, noShadow: boolean?): Instance
		Kit.setAll(inst, Kit.DECOR)
		if noShadow then
			Kit.setAll(inst, Kit.NOSHADOW)
		end
		return inst
	end
	local function soft(inst: Instance): Instance
		Kit.setAll(inst, Kit.SOFT)
		return inst
	end

	local function ladder(cf: CFrame, height: number): TrussPart
		local t = Instance.new("TrussPart")
		t.Name = "Ladder"
		t.Size = V(2, height, 2)
		t.CFrame = cf
		t.Material = M.Wood
		t.Color = P.TimberDark
		t.Style = Enum.Style.NoSupports
		t.Anchored = true
		t.CanTouch = false
		t:AddTag("Climbable")
		return t
	end

	-- Blocks covering a wall minus rectangular openings { s0, s1, y0, y1 } (s = coordinate along the wall).
	-- axis "X": wall runs along X at z = fixed; axis "Z": wall runs along Z at x = fixed.
	local function wallBlocks(list: { BasePart }, axis: string, fixed: number, s0: number, s1: number, y0: number, y1: number, thick: number, openings: { { number } }, color: Color3, material: Enum.Material)
		table.sort(openings, function(a, b)
			return a[1] < b[1]
		end)
		local function block(a: number, b: number, c: number, d: number)
			if b - a < 0.05 or d - c < 0.05 then
				return
			end
			local size, pos
			if axis == "X" then
				size, pos = V(b - a, d - c, thick), V((a + b) / 2, (c + d) / 2, fixed)
			else
				size, pos = V(thick, d - c, b - a), V(fixed, (c + d) / 2, (a + b) / 2)
			end
			table.insert(list, Kit.block("Wall", size, CF(pos), color, material))
		end
		local cursor = s0
		for _, o in ipairs(openings) do
			block(cursor, o[1], y0, y1)
			block(o[1], o[2], y0, o[3])
			block(o[1], o[2], o[4], y1)
			cursor = o[2]
		end
		block(cursor, s1, y0, y1)
	end

	-- Horizontal log courses along a wall, unioned per region so every region keeps a tight box collision.
	local LOG = 1.2
	local function logRegion(children: { Instance }, axis: string, fixed: number, s0: number, s1: number, ys: { number }, color: Color3)
		if #ys == 0 or s1 - s0 < 0.2 then
			return
		end
		local logs: { BasePart } = {}
		for _, y in ipairs(ys) do
			local cf = if axis == "X" then CF((s0 + s1) / 2, y, fixed) else CF(fixed, y, (s0 + s1) / 2) * ANG(0, math.rad(90), 0)
			table.insert(logs, Kit.part("Log", V(s1 - s0, LOG, LOG), cf, Kit.jitter(color, rng, 0.01, 0.06, 0.08), M.Wood, Enum.PartType.Cylinder))
		end
		table.insert(children, solid(Kit.union("Logs", logs, { collision = Enum.CollisionFidelity.Box })))
	end
	local function logWall(children: { Instance }, axis: string, fixed: number, s0: number, s1: number, ys: { number }, openings: { { number } }, color: Color3)
		table.sort(openings, function(a, b)
			return a[1] < b[1]
		end)
		local function filter(lo: number, hi: number): { number }
			local r = {}
			for _, y in ipairs(ys) do
				if y >= lo and y <= hi then
					table.insert(r, y)
				end
			end
			return r
		end
		local cursor = s0
		for _, o in ipairs(openings) do
			logRegion(children, axis, fixed, cursor, o[1], ys, color)
			logRegion(children, axis, fixed, o[1], o[2], filter(-1e9, o[3] - LOG / 2), color)
			logRegion(children, axis, fixed, o[1], o[2], filter(o[4] + LOG / 2, 1e9), color)
			cursor = o[2]
		end
		logRegion(children, axis, fixed, cursor, s1, ys, color)
	end

	-- Triangle (two wedges) standing on a wall top. axis as in wallBlocks.
	local function gable(list: { BasePart }, axis: string, fixed: number, halfSpan: number, baseY: number, height: number, thick: number, color: Color3, material: Enum.Material)
		local cy = baseY + height / 2
		if axis == "X" then
			table.insert(list, Kit.wedge("Gable", V(thick, height, halfSpan), CF(-halfSpan / 2, cy, fixed) * ANG(0, math.rad(90), 0), color, material))
			table.insert(list, Kit.wedge("Gable", V(thick, height, halfSpan), CF(halfSpan / 2, cy, fixed) * ANG(0, math.rad(-90), 0), color, material))
		else
			table.insert(list, Kit.wedge("Gable", V(thick, height, halfSpan), CF(fixed, cy, -halfSpan / 2), color, material))
			table.insert(list, Kit.wedge("Gable", V(thick, height, halfSpan), CF(fixed, cy, halfSpan / 2) * ANG(0, math.pi, 0), color, material))
		end
	end

	-- Two roof slabs meeting at a ridge. ridgeAxis "Z": ridge along Z (slopes fall toward +-X); "X": ridge along X.
	local function gableRoof(list: { BasePart }, ridgeAxis: string, ridgeY: number, halfWidth: number, drop: number, length: number, thick: number, color: Color3, material: Enum.Material)
		local slant = math.sqrt(halfWidth * halfWidth + drop * drop)
		local angle = math.atan2(drop, halfWidth)
		for _, side in ipairs({ -1, 1 }) do
			local offset = side * halfWidth / 2
			local cy = ridgeY - drop / 2 + thick / 2 * math.cos(angle)
			if ridgeAxis == "Z" then
				table.insert(list, Kit.block("Roof", V(slant + 0.3, thick, length), CF(offset, cy, 0) * ANG(0, 0, -side * angle), color, material))
			else
				table.insert(list, Kit.block("Roof", V(length, thick, slant + 0.3), CF(0, cy, offset) * ANG(side * angle, 0, 0), color, material))
			end
		end
	end

	-- Railing run from a to b (posts about every 3 studs, two rails), box collision.
	local function railing(a: Vector3, b: Vector3, height: number, color: Color3): Instance
		local parts: { BasePart } = {}
		local n = math.max(1, math.ceil((b - a).Magnitude / 3))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			table.insert(parts, Kit.block("Post", V(0.42, height, 0.42), CF(p + V(0, height / 2, 0)), color, M.Wood))
		end
		table.insert(parts, Kit.rod("Rail", a + V(0, height - 0.15, 0), b + V(0, height - 0.15, 0), 0.36, color, M.Wood, true))
		table.insert(parts, Kit.rod("Rail", a + V(0, height * 0.5, 0), b + V(0, height * 0.5, 0), 0.28, color, M.Wood, true))
		return solid(Kit.union("Railing", parts, { collision = Enum.CollisionFidelity.Box }))
	end

	-- Pointed banner cloth with the spire-and-sun emblem, hanging from cf (cloth plane = cf XY, front = cf LookVector).
	local function bannerCloth(children: { Instance }, cf: CFrame, width: number, height: number)
		local cloth = Kit.union("BannerCloth", {
			Kit.block("Cloth", V(width, height, 0.12), cf * CF(0, -height / 2, 0), P.Ember, M.Fabric),
			Kit.wedge("Tail", V(0.12, 1.4, width / 2), cf * CF(-width / 4, -height - 0.7, 0) * ANG(0, math.rad(90), math.pi), P.Ember, M.Fabric),
			Kit.wedge("Tail", V(0.12, 1.4, width / 2), cf * CF(width / 4, -height - 0.7, 0) * ANG(0, math.rad(-90), math.pi), P.Ember, M.Fabric),
		}, { collision = Enum.CollisionFidelity.Box })
		table.insert(children, soft(cloth))
		local f = -0.1
		local emblem = Kit.union("BannerEmblem", {
			Kit.block("Band", V(width + 0.05, 0.5, 0.1), cf * CF(0, -0.5, f), P.Charcoal, M.Fabric),
			Kit.block("Band", V(width + 0.05, 0.25, 0.1), cf * CF(0, -height + 0.6, f), P.Charcoal, M.Fabric),
			Kit.wedge("Spire", V(0.1, height * 0.36, width * 0.22), cf * CF(-width * 0.11, -height * 0.66, f) * ANG(0, math.rad(90), 0), P.Charcoal, M.Fabric),
			Kit.wedge("Spire", V(0.1, height * 0.36, width * 0.22), cf * CF(width * 0.11, -height * 0.66, f) * ANG(0, math.rad(-90), 0), P.Charcoal, M.Fabric),
			Kit.part("Sun", V(0.1, width * 0.42, width * 0.42), cf * CF(0, -height * 0.3, f) * ANG(0, math.rad(90), 0), P.Charcoal, M.Fabric, Enum.PartType.Cylinder),
		}, { collision = Enum.CollisionFidelity.Box })
		table.insert(children, soft(emblem))
		Kit.setAll(emblem, Kit.NOSHADOW)
		local core = Kit.part("SunCore", V(0.1, width * 0.24, width * 0.24), cf * CF(0, -height * 0.3, f - 0.05) * ANG(0, math.rad(90), 0), P.EmberGlow, M.Fabric, Enum.PartType.Cylinder)
		table.insert(children, soft(core))
		Kit.setAll(core, Kit.NOSHADOW)
	end

	------------------------------------------------------------------ SPIRE (pivot = ground at the arena centre)
	do
		local c: { Instance } = {}
		local TOP = 2.4 -- platform walking surface
		table.insert(c, solid(Kit.vcyl("Apron", 1.4, 66, CF(0, -0.5, 0), P.PavingDark, M.Cobblestone)))
		table.insert(c, solid(Kit.vcyl("Step", 1.6, 61, CF(0, 0.4, 0), P.SpireStoneDark, M.Slate)))
		table.insert(c, solid(Kit.vcyl("Platform", 1.8, 56, CF(0, 1.5, 0), P.Paving, M.Cobblestone)))
		table.insert(c, decor(Kit.vcyl("InlayRing", 0.06, 41, CF(0, TOP + 0.02, 0), P.DarkMetal, M.Metal), true))
		table.insert(c, decor(Kit.vcyl("InlayField", 0.08, 39.4, CF(0, TOP + 0.03, 0), P.Paving, M.Cobblestone), true))

		-- 24 paved paths radiating to the plinth ring (flush with the clearing, non-solid)
		local paths: { BasePart } = {}
		for i = 0, 23 do
			local ang = math.rad(i * 15)
			local dir = V(math.sin(ang), 0, -math.cos(ang))
			table.insert(paths, Kit.plank("Path", dir * 31 + V(0, -0.2, 0), dir * 48.8 + V(0, -0.2, 0), 2.4, 0.64, P.SpireStoneDark, M.Slate))
		end
		local pathUnion = Kit.union("Paths", paths, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(pathUnion, Kit.SOFT)
		Kit.setAll(pathUnion, Kit.NOSHADOW)
		table.insert(c, pathUnion)

		-- pedestal and buttress fins
		table.insert(c, solid(Kit.octagon("Pedestal", 15, 4.6, CF(0, TOP + 2.3, 0), P.SpireStoneDark, M.Slate)))
		table.insert(c, solid(Kit.octagon("PedestalCap", 16.2, 0.7, CF(0, TOP + 4.95, 0), P.DarkMetal, M.CorrodedMetal)))
		local PED_TOP = TOP + 5.3
		for i = 0, 3 do
			local ang = math.rad(i * 90)
			local dir = V(math.sin(ang), 0, -math.cos(ang))
			local h, depth, inner = 27, 11.5, 4.2
			local centre = dir * (inner + depth / 2) + V(0, TOP + h / 2, 0)
			local cf = CFrame.lookAt(centre, centre - dir) * ANG(0, math.pi, 0)
			table.insert(c, solid(Kit.wedge("Fin", V(3.4, h, depth), cf, P.SpireStone, M.Slate)))
			local bottomOuter = dir * (inner + depth) + V(0, TOP + 0.25, 0)
			local topInner = dir * inner + V(0, TOP + h + 0.25, 0)
			table.insert(c, decor(Kit.plank("FinCap", bottomOuter, topInner, 3.8, 0.5, P.DarkMetal, M.CorrodedMetal)))
		end

		-- three tapering octagonal shaft sections with dark metal collars
		local S1_TOP = 36
		table.insert(c, solid(Kit.octagon("Shaft1", 9.2, S1_TOP - PED_TOP, CF(0, (PED_TOP + S1_TOP) / 2, 0), P.SpireStone, M.Slate)))
		table.insert(c, solid(Kit.vcyl("Collar1", 1.4, 11.6, CF(0, S1_TOP + 0.7, 0), P.DarkMetal, M.CorrodedMetal)))
		local S2_BOT, S2_TOP = S1_TOP + 1.4, 49
		table.insert(c, solid(Kit.octagon("Shaft2", 7.4, S2_TOP - S2_BOT, CF(0, (S2_BOT + S2_TOP) / 2, 0), P.SpireStone, M.Slate)))
		table.insert(c, solid(Kit.vcyl("Collar2", 1.2, 9.6, CF(0, S2_TOP + 0.6, 0), P.DarkMetal, M.CorrodedMetal)))
		local S3_BOT, S3_TOP = S2_TOP + 1.2, 56
		table.insert(c, solid(Kit.octagon("Shaft3", 5.6, S3_TOP - S3_BOT, CF(0, (S3_BOT + S3_TOP) / 2, 0), P.SpireStoneDark, M.Slate)))

		-- metal ribs on the eight edges of the lower shaft, ember slits in the middle section
		local ribs: { BasePart } = {}
		for i = 0, 7 do
			local ang = math.rad(22.5 + i * 45)
			local dir = V(math.sin(ang), 0, -math.cos(ang))
			local pos = dir * (4.6 / math.cos(math.rad(22.5)) - 0.05) + V(0, (PED_TOP + S1_TOP) / 2, 0)
			table.insert(ribs, Kit.block("Rib", V(0.7, S1_TOP - PED_TOP, 0.7), CFrame.lookAt(pos, pos + dir), P.DarkMetal, M.CorrodedMetal))
		end
		table.insert(c, decor(Kit.union("Ribs", ribs, { collision = Enum.CollisionFidelity.Box })))
		local slits: { BasePart } = {}
		for i = 0, 3 do
			local ang = math.rad(i * 90)
			local dir = V(math.sin(ang), 0, -math.cos(ang))
			local pos = dir * 3.72 + V(0, (S2_BOT + S2_TOP) / 2, 0)
			table.insert(slits, Kit.block("Slit", V(0.4, 8.6, 0.1), CFrame.lookAt(pos, pos + dir), P.EmberGlow, M.Neon))
		end
		table.insert(c, decor(Kit.union("EmberSlits", slits, { collision = Enum.CollisionFidelity.Box }), true))

		-- four long banners on the diagonal faces under the first collar
		for i = 0, 3 do
			local ang = math.rad(45 + i * 90)
			local dir = V(math.sin(ang), 0, -math.cos(ang))
			local anchor = dir * (4.6 + 0.14) + V(0, S1_TOP - 0.4, 0)
			bannerCloth(c, CFrame.lookAt(anchor, anchor + dir), 3.6, 13)
		end

		-- ember crown: flared brazier bowl with tines
		local CROWN = S3_TOP
		local crown: { BasePart } = {
			Kit.vcyl("Neck", 1.4, 6.6, CF(0, CROWN + 0.7, 0), P.DarkMetal, M.CorrodedMetal),
			Kit.vcyl("BowlBase", 1, 8, CF(0, CROWN + 1.8, 0), P.DarkMetal, M.CorrodedMetal),
		}
		for i = 1, 12 do
			local ang = (i / 12) * math.pi * 2
			local dir = V(math.cos(ang), 0, math.sin(ang))
			local pos = dir * 4.4 + V(0, CROWN + 4.2, 0)
			table.insert(crown, Kit.block("Plate", V(3.3, 5.6, 0.4), CFrame.lookAt(pos, pos - dir) * ANG(math.rad(28), 0, 0), P.DarkMetal, M.CorrodedMetal))
		end
		for i = 1, 8 do
			local ang = (i / 8) * math.pi * 2 + math.rad(11)
			local dir = V(math.cos(ang), 0, math.sin(ang))
			local pos = dir * 5.6 + V(0, CROWN + 9.4, 0)
			table.insert(crown, Kit.wedge("Tine", V(0.7, 6.4, 1.5), CFrame.lookAt(pos, pos - dir) * ANG(0, math.pi, 0) * ANG(math.rad(-10), 0, 0), P.DarkMetal, M.CorrodedMetal))
		end
		table.insert(c, solid(Kit.union("Crown", crown, { collision = Enum.CollisionFidelity.Default })))
		local bed = Kit.vcyl("EmberBed", 1.2, 8.4, CF(0, CROWN + 3.0, 0), P.EmberDeep, M.Neon)
		local core = Kit.ball("EmberCore", 4.2, V(0, CROWN + 3.6, 0), P.EmberGlow, M.Neon)
		table.insert(c, decor(bed, true))
		table.insert(c, decor(core, true))
		local fx = Instance.new("Attachment")
		fx.Name = "BeaconFx"
		fx.Parent = bed
		fx.WorldPosition = V(0, CROWN + 4.4, 0)
		Kit.fireFx(fx, 3.2, { light = 0, smoke = 3, sparks = 3, rate = 34 })
		local beacon = Instance.new("PointLight")
		beacon.Name = "BeaconLight"
		beacon.Color = Color3.fromRGB(255, 150, 80)
		beacon.Brightness = 1.4
		beacon.Range = 50
		beacon.Shadows = true
		beacon.Parent = core

		-- braziers on the platform and the Tier-3 loot ring
		for i = 0, 3 do
			local ang = math.rad(45 + i * 90)
			table.insert(c, prop("Brazier", CF(math.sin(ang) * 24.6, TOP, -math.cos(ang) * 24.6)) :: Instance)
		end
		for i = 0, 9 do
			local ang = math.rad(18 + i * 36)
			table.insert(c, Kit.lootOnFloor(V(math.sin(ang) * 19.5, TOP, -math.cos(ang) * 19.5), -ang, 3, "Crate"))
		end
		local spire = finish("Spire", c, { Category = "Structure", Footprint = 33, Sink = 0, Height = CROWN + 12.6 })
		spire.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
	task.wait()

	------------------------------------------------------------------ PAVILION (lobby)
	do
		local c: { Instance } = {}
		table.insert(c, solid(Kit.block("Deck", V(13, 0.8, 13), CF(0, 0.2, 0), P.SpireStoneDark, M.Slate)))
		for _, x in ipairs({ -5.6, 5.6 }) do
			for _, z in ipairs({ -5.6, 5.6 }) do
				table.insert(c, solid(Kit.block("Post", V(0.9, 9, 0.9), CF(x, 5.1, z), P.TimberDark, M.Wood)))
			end
		end
		local beams: { BasePart } = { Kit.block("TieBeam", V(12, 0.6, 0.6), CF(0, 10.1, 0), P.TimberDark, M.Wood) }
		for _, s in ipairs({ -5.6, 5.6 }) do
			table.insert(beams, Kit.block("Beam", V(12.6, 0.8, 0.8), CF(0, 9.9, s), P.TimberDark, M.Wood))
			table.insert(beams, Kit.block("Beam", V(0.8, 0.8, 12.6), CF(s, 9.9, 0), P.TimberDark, M.Wood))
		end
		for _, x in ipairs({ -5.6, 5.6 }) do
			for _, z in ipairs({ -5.6, 5.6 }) do
				table.insert(beams, Kit.rod("Knee", V(x, 8.0, z), V(x - math.sign(x) * 1.8, 9.6, z), 0.4, P.TimberDark, M.Wood, true))
				table.insert(beams, Kit.rod("Knee", V(x, 8.0, z), V(x, 9.6, z - math.sign(z) * 1.8), 0.4, P.TimberDark, M.Wood, true))
			end
		end
		table.insert(c, decor(Kit.union("Beams", beams, { collision = Enum.CollisionFidelity.Box })))
		local roof: { BasePart } = {}
		Kit.pyramid(roof, CF(0, 10.3, 0), 16.5, 5.2, P.TimberWeathered, M.WoodPlanks)
		table.insert(c, solid(Kit.union("Roof", roof, { collision = Enum.CollisionFidelity.Default })))
		table.insert(c, decor(Kit.ball("Finial", 0.9, V(0, 15.6, 0), P.Ember, M.Metal)))
		local valance: { BasePart } = {}
		for _, s in ipairs({ -1, 1 }) do
			table.insert(valance, Kit.block("Valance", V(11.4, 1.1, 0.1), CF(0, 9.0, s * 6.05), P.Ember, M.Fabric))
			table.insert(valance, Kit.block("Valance", V(0.1, 1.1, 11.4), CF(s * 6.05, 9.0, 0), P.Ember, M.Fabric))
		end
		local valanceUnion = Kit.union("Valance", valance, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(valanceUnion, Kit.SOFT)
		table.insert(c, valanceUnion)
		table.insert(c, prop("Bench", CF(0, 0.6, -3.3)))
		table.insert(c, prop("Bench", CF(0, 0.6, 3.3) * ANG(0, math.pi, 0)))
		table.insert(c, prop("Lantern", CF(0, 9.8, 0)))
		finish("Pavilion", c, { Category = "Structure", Footprint = 8.5, Sink = 0 })
	end
	task.wait()

	------------------------------------------------------------------ RANGER CABIN (door faces -Z)
	do
		local c: { Instance } = {}
		local hx, hz = 10, 7.5 -- wall centre lines
		local floor = Kit.block("Floor", V(2 * hx + 1.6, 0.8, 2 * hz + 1.6), CF(0, -0.4, 0), P.Planks, M.WoodPlanks)
		table.insert(c, solid(floor))
		table.insert(c, solid(Kit.block("Sill", V(2 * hx + 1.2, 2.4, 2 * hz + 1.2), CF(0, -2.0, 0), P.Rock, M.Cobblestone)))
		local ys, ysSide = {}, {}
		for i = 0, 8 do
			table.insert(ys, 0.6 + i * 1.1)
			table.insert(ysSide, 1.15 + i * 1.1)
		end
		logWall(c, "X", -hz, -hx - 1, hx + 1, ys, { { -2, 2, 0, 6.6 }, { 4.5, 7.5, 2.9, 6.0 } }, P.OakBark)
		logWall(c, "X", hz, -hx - 1, hx + 1, ys, {}, P.OakBark)
		logWall(c, "Z", -hx, -hz - 1, hz + 1, ysSide, { { -1.6, 1.6, 2.9, 6.0 } }, P.OakBark)
		logWall(c, "Z", hx, -hz - 1, hz + 1, ysSide, { { -1.6, 1.6, 2.9, 6.0 } }, P.OakBark)
		task.wait()

		-- gables and roof (ridge along Z)
		local gables: { BasePart } = {}
		gable(gables, "X", -hz, hx + 0.6, 10.0, 6.6, 0.9, P.TimberWeathered, M.WoodPlanks)
		gable(gables, "X", hz, hx + 0.6, 10.0, 6.6, 0.9, P.TimberWeathered, M.WoodPlanks)
		table.insert(c, solid(Kit.union("Gables", gables, { collision = Enum.CollisionFidelity.PreciseConvexDecomposition })))
		local roof: { BasePart } = {}
		gableRoof(roof, "Z", 16.6, 12.2, 8.05, 2 * hz + 4, 0.7, Color3.fromRGB(86, 74, 64), M.WoodPlanks)
		table.insert(roof, Kit.rod("Ridge", V(0, 16.95, -hz - 2), V(0, 16.95, hz + 2), 0.8, P.TimberDark, M.WoodPlanks, true))
		table.insert(c, solid(Kit.union("Roof", roof, { collision = Enum.CollisionFidelity.PreciseConvexDecomposition })))

		-- chimney and hearth on the back wall
		table.insert(c, solid(Kit.block("Chimney", V(4, 20.5, 2.8), CF(0, 7.25, hz + 2.1), P.Rock, M.Cobblestone)))
		table.insert(c, solid(Kit.block("ChimneyCap", V(4.6, 0.6, 3.4), CF(0, 17.7, hz + 2.1), P.Slate, M.Slate)))
		table.insert(c, solid(Kit.block("Hearth", V(5.4, 3.8, 1.5), CF(0, 1.9, hz - 1.3), P.Rock, M.Cobblestone)))
		local firebox = Kit.block("Firebox", V(2.8, 2.0, 0.2), CF(0, 1.3, hz - 2.06), P.Charcoal, M.Slate)
		table.insert(c, decor(firebox, true))
		local hearthFire = Instance.new("Attachment")
		hearthFire.Name = "FireFx"
		hearthFire.Parent = firebox
		hearthFire.WorldPosition = V(0, 0.7, hz - 2.3)
		Kit.fireFx(hearthFire, 0.55, { light = 0.9, range = 14, smoke = 0, sparks = 0.5 })
		table.insert(c, Kit.emitterPoint(V(0, 1.5, hz - 2.6), "Emit_Fire"))

		-- loft over the back half, railing and ladder
		table.insert(c, solid(Kit.block("Loft", V(2 * hx - 0.8, 0.5, 6.4), CF(0, 5.35, 3.9), P.Planks, M.WoodPlanks)))
		table.insert(c, decor(Kit.union("LoftBeams", {
			Kit.block("Beam", V(2 * hx - 0.6, 0.6, 0.6), CF(0, 4.8, 1.0), P.TimberDark, M.Wood),
			Kit.block("Beam", V(2 * hx - 0.6, 0.6, 0.6), CF(0, 4.8, 6.6), P.TimberDark, M.Wood),
		}, { collision = Enum.CollisionFidelity.Box })))
		table.insert(c, solid(Kit.block("LoftPost", V(0.6, 4.6, 0.6), CF(-4.5, 2.3, 1.0), P.TimberDark, M.Wood)))
		table.insert(c, railing(V(-hx + 0.6, 5.6, 1.0), V(4.4, 5.6, 1.0), 3.0, P.TimberDark))
		table.insert(c, ladder(CF(6.4, 4, -0.3), 8))

		-- porch
		table.insert(c, solid(Kit.block("Porch", V(2 * hx + 1.6, 0.6, 5), CF(0, -0.3, -hz - 3.3), P.Planks, M.WoodPlanks)))
		-- the cabin stands 2.4 studs up on its cobblestone sill (clear of the terrain grass): three steps to the porch
		for k = 0, 2 do
			local top = -0.6 * (k + 1)
			table.insert(c, solid(Kit.block("Step", V(5, 2.4, 1.2), CF(0, top - 1.2, -hz - 6.4 - 1.2 * k), P.TimberWeathered, M.WoodPlanks)))
		end
		for _, x in ipairs({ -hx + 0.4, hx - 0.4 }) do
			table.insert(c, solid(Kit.block("PorchPost", V(0.7, 8.4, 0.7), CF(x, 4.0, -hz - 5.4), P.TimberDark, M.Wood)))
		end
		table.insert(c, solid(Kit.plank("PorchRoof", V(0, 9.4, -hz - 0.6), V(0, 7.9, -hz - 6.3), 2 * hx + 2.4, 0.5, Color3.fromRGB(86, 74, 64), M.WoodPlanks)))
		table.insert(c, prop("Lantern", CF(3.2, 8.75, -hz - 2.6)))

		-- window frames and shutters
		local trim: { BasePart } = {}
		for _, side in ipairs({ -1, 1 }) do
			local x = side * (hx + 0.65)
			table.insert(trim, Kit.block("Sill", V(0.3, 0.3, 3.8), CF(x, 2.75, 0), P.TimberDark, M.Wood))
			table.insert(trim, Kit.block("Head", V(0.3, 0.3, 3.8), CF(x, 6.15, 0), P.TimberDark, M.Wood))
			table.insert(trim, Kit.block("Shutter", V(0.2, 3.2, 1.6), CF(x + side * 0.6, 4.45, -2.6) * ANG(0, side * 0.5, 0), P.TimberWeathered, M.Wood))
			table.insert(trim, Kit.block("Shutter", V(0.2, 3.2, 1.6), CF(x + side * 0.6, 4.45, 2.6) * ANG(0, -side * 0.5, 0), P.TimberWeathered, M.Wood))
		end
		table.insert(trim, Kit.block("Sill", V(3.8, 0.3, 0.3), CF(6, 2.15, -hz - 0.65), P.TimberDark, M.Wood))
		table.insert(c, decor(Kit.union("WindowTrim", trim, { collision = Enum.CollisionFidelity.Box }), true))
		table.insert(c, solid(Kit.block("Door", V(0.25, 6.4, 3.7), CF(-1.95, 3.2, -hz + 2.0), P.TimberWeathered, M.WoodPlanks)))

		-- furniture
		local rug = Kit.block("Rug", V(6, 0.06, 4), CF(0, 0.03, -2.5), P.Cloth, M.Fabric)
		table.insert(c, soft(rug))
		table.insert(c, prop("Table", CF(-5, 0, -3) * ANG(0, 0.1, 0)))
		table.insert(c, prop("Stool", CF(-5.2, 0, -0.7)))
		table.insert(c, prop("Stool", CF(-2.4, 0, -3.4)))
		table.insert(c, prop("Shelf", CF(-hx + 1.2, 0, -4.4) * ANG(0, math.rad(-90), 0)))
		table.insert(c, prop("Barrel", CF(-8, 0, -5.8)))
		table.insert(c, prop("Crate", CF(-8.1, 0, 1.3) * ANG(0, 0.3, 0)))
		table.insert(c, prop("Bedroll", CF(-5.5, 5.6, 4.4) * ANG(0, math.rad(90), 0)))

		-- loot (Tier 2 crates indoors, one ground item on the porch)
		table.insert(c, Kit.lootOnFloor(V(7.2, 0, 5.2), 0.1, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(-7.4, 0, 5.6), -0.05, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(0.3, 5.6, 5.4), 0, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(5.0, 5.6, 5.4), 0.05, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(-6, 0, -hz - 3.4), 0, 1, "Ground"))

		for _, p in ipairs({ { -hx, -hz }, { 0, -hz }, { hx, -hz }, { -hx, 0 }, { hx, 0 }, { -hx, hz }, { 0, hz }, { hx, hz } }) do
			Kit.foot(floor, V(p[1], -3.2, p[2]), 2.2, "Stone")
		end
		for _, x in ipairs({ -hx + 0.4, 0, hx - 0.4 }) do
			Kit.foot(floor, V(x, -0.6, -hz - 5.4), 0.8, "Wood")
		end
		finish("RangerCabin", c, { Category = "Structure", Footprint = 15, Sink = 0 })
	end
	task.wait()

	------------------------------------------------------------------ WATCHTOWER
	do
		local c: { Instance } = {}
		local function legPos(sx: number, sz: number, y: number): Vector3
			local t = (y + 2) / 32
			local o = 6.2 + (4.4 - 6.2) * t
			return V(sx * o, y, sz * o)
		end
		local legs: { BasePart } = {}
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local leg = Kit.rod("Leg", legPos(sx, sz, -2), legPos(sx, sz, 30.2), 1.3, P.TimberDark, M.Wood, true)
				table.insert(c, solid(leg))
				table.insert(legs, leg)
			end
		end
		local faces = { { { -1, -1 }, { 1, -1 } }, { { 1, -1 }, { 1, 1 } }, { { 1, 1 }, { -1, 1 } }, { { -1, 1 }, { -1, -1 } } }
		local levels = { 7, 15, 23, 29.3 }
		for _, f in ipairs(faces) do
			local parts: { BasePart } = {}
			for li, y in ipairs(levels) do
				table.insert(parts, Kit.rod("Girt", legPos(f[1][1], f[1][2], y), legPos(f[2][1], f[2][2], y), 0.55, P.Timber, M.Wood, true))
				local y2 = levels[li + 1]
				if y2 then
					table.insert(parts, Kit.rod("Brace", legPos(f[1][1], f[1][2], y), legPos(f[2][1], f[2][2], y2), 0.42, P.Timber, M.Wood, true))
					table.insert(parts, Kit.rod("Brace", legPos(f[2][1], f[2][2], y), legPos(f[1][1], f[1][2], y2), 0.42, P.Timber, M.Wood, true))
				end
			end
			table.insert(c, solid(Kit.union("Bracing", parts, { collision = Enum.CollisionFidelity.PreciseConvexDecomposition })))
		end
		-- lookout floor with a hatch over the ladder
		local FLOOR = 30
		for _, b in ipairs({
			{ V(1.9, 0.6, 11.2), V(-4.65, FLOOR - 0.3, 0) },
			{ V(6.7, 0.6, 11.2), V(2.25, FLOOR - 0.3, 0) },
			{ V(2.6, 0.6, 4.3), V(-2.4, FLOOR - 0.3, -3.45) },
			{ V(2.6, 0.6, 4.3), V(-2.4, FLOOR - 0.3, 3.45) },
		}) do
			table.insert(c, solid(Kit.block("Floor", b[1], CF(b[2]), P.Planks, M.WoodPlanks)))
		end
		table.insert(c, decor(Kit.union("Joists", {
			Kit.block("Joist", V(11, 0.6, 0.6), CF(0, FLOOR - 0.9, -3.4), P.TimberDark, M.Wood),
			Kit.block("Joist", V(11, 0.6, 0.6), CF(0, FLOOR - 0.9, 3.4), P.TimberDark, M.Wood),
		}, { collision = Enum.CollisionFidelity.Box }), true))
		local R = 5.4
		table.insert(c, railing(V(-R, FLOOR, -R), V(R, FLOOR, -R), 3.4, P.Timber))
		table.insert(c, railing(V(R, FLOOR, -R), V(R, FLOOR, R), 3.4, P.Timber))
		table.insert(c, railing(V(R, FLOOR, R), V(-R, FLOOR, R), 3.4, P.Timber))
		table.insert(c, railing(V(-R, FLOOR, R), V(-R, FLOOR, -R), 3.4, P.Timber))
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(c, solid(Kit.block("RoofPost", V(0.6, 7.4, 0.6), CF(sx * 5.2, FLOOR + 3.7, sz * 5.2), P.TimberDark, M.Wood)))
			end
		end
		table.insert(c, decor(Kit.union("EaveBeams", {
			Kit.block("Beam", V(11, 0.5, 0.5), CF(0, FLOOR + 7.0, -5.2), P.TimberDark, M.Wood),
			Kit.block("Beam", V(11, 0.5, 0.5), CF(0, FLOOR + 7.0, 5.2), P.TimberDark, M.Wood),
			Kit.block("Beam", V(0.5, 0.5, 11), CF(-5.2, FLOOR + 7.0, 0), P.TimberDark, M.Wood),
			Kit.block("Beam", V(0.5, 0.5, 11), CF(5.2, FLOOR + 7.0, 0), P.TimberDark, M.Wood),
			Kit.block("Beam", V(10.4, 0.5, 0.5), CF(0, FLOOR + 7.0, 0), P.TimberDark, M.Wood),
		}, { collision = Enum.CollisionFidelity.Box }), true))
		local roof: { BasePart } = {}
		Kit.pyramid(roof, CF(0, FLOOR + 7.2, 0), 13.6, 5.4, P.TimberWeathered, M.WoodPlanks)
		table.insert(c, solid(Kit.union("Roof", roof, { collision = Enum.CollisionFidelity.Default })))
		local apex = FLOOR + 12.6
		table.insert(c, decor(Kit.rod("FlagPole", V(0, apex - 0.6, 0), V(0, apex + 5.6, 0), 0.25, P.TimberDark, M.Wood), true))
		local flag = Kit.union("Pennant", {
			Kit.wedge("Flag", V(0.12, 0.8, 5), CF(2.6, apex + 4.9 + 0.4, 0) * ANG(0, math.rad(-90), 0), P.Ember, M.Fabric),
			Kit.wedge("Flag", V(0.12, 0.8, 5), CF(2.6, apex + 4.9 - 0.4, 0) * ANG(0, math.rad(-90), 0) * ANG(0, 0, math.pi), P.Ember, M.Fabric),
		}, { collision = Enum.CollisionFidelity.Box })
		table.insert(c, soft(flag))
		table.insert(c, prop("Lantern", CF(0, FLOOR + 6.75, 0)))
		table.insert(c, ladder(CF(-2.4, 16, 0), 32))

		-- lean-to store at the base (+X side)
		table.insert(c, solid(Kit.block("ShedWall", V(0.5, 4.6, 6.6), CF(10.2, 2.1, 0), P.TimberWeathered, M.WoodPlanks)))
		table.insert(c, solid(Kit.block("ShedWall", V(3.9, 4.0, 0.5), CF(8.2, 1.8, 3.1), P.TimberWeathered, M.WoodPlanks)))
		for _, z in ipairs({ -3.1, 3.1 }) do
			table.insert(c, solid(Kit.block("ShedPost", V(0.5, 5.2, 0.5), CF(6.4, 2.4, z), P.TimberDark, M.Wood)))
		end
		table.insert(c, solid(Kit.plank("ShedRoof", V(6.0, 5.3, 0), V(10.8, 4.4, 0), 7.4, 0.4, P.TimberWeathered, M.WoodPlanks)))
		table.insert(c, prop("CrateStack", CF(-3.8, 0, 7.6) * ANG(0, 0.2, 0)))
		table.insert(c, prop("Barrel", CF(-7.6, 0, -3.8)))
		table.insert(c, prop("Barrel", CF(-7.9, 0, -1.2)))
		table.insert(c, prop("Firewood", CF(2.8, 0, -7.8) * ANG(0, 0.2, 0)))
		table.insert(c, Kit.lootOnFloor(V(2.8, FLOOR, 2.9), 0.5, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(2.6, FLOOR, -3.0), -0.4, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(8.3, 0, -0.6), math.rad(90), 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(-1.2, 0, 5.4), 0, 1, "Ground"))
		for _, leg in ipairs(legs) do
			local bottom = leg.CFrame * CF(-leg.Size.X / 2 + 0.2, 0, 0)
			Kit.foot(leg, bottom.Position, 1.3, "Wood")
		end
		local tower = finish("Watchtower", c, { Category = "Structure", Footprint = 11, Sink = 0, Height = apex + 5.6 })
		tower.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
	task.wait()

	------------------------------------------------------------------ WATER WHEEL (pivot = hub centre, axle = X)
	local function buildWheel(): Model
		local R = 7.6
		local parts: { BasePart } = { Kit.part("Hub", V(4.2, 2.6, 2.6), CF(0, 0, 0), P.TimberDark, M.WoodPlanks, Enum.PartType.Cylinder) }
		for _, x in ipairs({ -1.5, 1.5 }) do
			for k = 0, 11 do
				local a = k * math.pi / 6
				local pos = V(x, math.sin(a) * R, math.cos(a) * R)
				local tangent = V(0, math.cos(a), -math.sin(a))
				table.insert(parts, Kit.block("Rim", V(0.5, 0.8, 2 * R * math.sin(math.pi / 12) + 0.35), CFrame.lookAt(pos, pos + tangent, Vector3.xAxis), P.Timber, M.WoodPlanks))
			end
			for k = 0, 5 do
				local a = k * math.pi / 3 + math.pi / 12
				table.insert(parts, Kit.rod("Spoke", V(x, 0, 0), V(x, math.sin(a) * (R - 0.2), math.cos(a) * (R - 0.2)), 0.5, P.TimberDark, M.WoodPlanks, true))
			end
		end
		for k = 0, 11 do
			local a = k * math.pi / 6 + math.pi / 12
			local radial = V(0, math.sin(a), math.cos(a))
			local pos = radial * (R + 0.6)
			table.insert(parts, Kit.block("Paddle", V(3.6, 0.3, 2.4), CFrame.lookAt(pos, pos + radial, Vector3.xAxis), P.TimberWeathered, M.WoodPlanks))
		end
		local wheel = Kit.union("Wheel", parts, { collision = Enum.CollisionFidelity.Box })
		soft(wheel)
		if wheel:IsA("BasePart") then
			local axle = Instance.new("Attachment")
			axle.Name = "Axle"
			axle.Parent = wheel
			axle.WorldCFrame = CFrame.identity
		end
		return Kit.model("WaterWheel", { wheel }, { Category = "Structure", Footprint = 8.5, Sink = 0, Radius = R + 1.8 })
	end
	buildWheel().Parent = out

	------------------------------------------------------------------ MILL HOUSE (door -Z, wheel on +X)
	do
		local c: { Instance } = {}
		local floor = Kit.block("Floor", V(17.4, 1.2, 15.4), CF(0, -0.6, 0), P.PavingDark, M.Cobblestone)
		table.insert(c, solid(floor))
		table.insert(c, solid(Kit.block("Footing", V(18, 3, 16), CF(0, -2.6, 0), P.Rock, M.Cobblestone)))
		local stone: { BasePart } = {}
		wallBlocks(stone, "X", -7, -8.6, 8.6, 0, 7.5, 1.2, { { -2, 2, 0, 6.4 }, { 4, 6.4, 3, 5.4 } }, P.Paving, M.Cobblestone)
		wallBlocks(stone, "X", 7, -8.6, 8.6, 0, 7.5, 1.2, { { -5.5, -3, 3, 5.4 } }, P.Paving, M.Cobblestone)
		wallBlocks(stone, "Z", -8, -6.4, 6.4, 0, 7.5, 1.2, { { -1.2, 1.2, 3, 5.4 } }, P.Paving, M.Cobblestone)
		wallBlocks(stone, "Z", 8, -6.4, 6.4, 0, 7.5, 1.2, {}, P.Paving, M.Cobblestone)
		for _, b in ipairs(stone) do
			table.insert(c, solid(b))
		end
		-- upper floor with a hatch at (-5.4, 4.6)
		for _, b in ipairs({
			{ V(12.2, 0.6, 14), V(1.9, 7.2, 0) },
			{ V(1.4, 0.6, 14), V(-7.3, 7.2, 0) },
			{ V(2.4, 0.6, 10.4), V(-5.4, 7.2, -1.8) },
			{ V(2.4, 0.6, 1.2), V(-5.4, 7.2, 6.4) },
		}) do
			table.insert(c, solid(Kit.block("UpperFloor", b[1], CF(b[2]), P.Planks, M.WoodPlanks)))
		end
		local upper: { BasePart } = {}
		wallBlocks(upper, "X", -7, -8.6, 8.6, 7.5, 14, 0.7, { { -5, -2.4, 9.4, 12 }, { 2.4, 5, 9.4, 12 } }, P.Planks, M.WoodPlanks)
		wallBlocks(upper, "X", 7, -8.6, 8.6, 7.5, 14, 0.7, { { -1.5, 1.5, 7.5, 12.4 } }, P.Planks, M.WoodPlanks)
		wallBlocks(upper, "Z", -8, -6.65, 6.65, 7.5, 14, 0.7, { { -1.2, 1.2, 9.4, 12 } }, P.Planks, M.WoodPlanks)
		wallBlocks(upper, "Z", 8, -6.65, 6.65, 7.5, 14, 0.7, {}, P.Planks, M.WoodPlanks)
		for _, b in ipairs(upper) do
			table.insert(c, solid(b))
		end
		-- half-timber framing
		local frame: { BasePart } = {}
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(frame, Kit.block("Post", V(0.8, 6.6, 0.8), CF(sx * 8.4, 10.8, sz * 7.4), P.TimberDark, M.Wood))
			end
		end
		for _, y in ipairs({ 7.75, 13.8 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(frame, Kit.block("Plate", V(17.6, 0.6, 0.5), CF(0, y, sz * 7.45), P.TimberDark, M.Wood))
			end
			for _, sx in ipairs({ -1, 1 }) do
				table.insert(frame, Kit.block("Plate", V(0.5, 0.6, 15.4), CF(sx * 8.45, y, 0), P.TimberDark, M.Wood))
			end
		end
		for _, x in ipairs({ -7.0, 7.0 }) do
			table.insert(frame, Kit.rod("Brace", V(x, 8.0, -7.5), V(x - math.sign(x) * 3.2, 13.5, -7.5), 0.45, P.TimberDark, M.Wood, true))
			table.insert(frame, Kit.rod("Brace", V(x, 8.0, 7.5), V(x - math.sign(x) * 3.2, 13.5, 7.5), 0.45, P.TimberDark, M.Wood, true))
		end
		table.insert(c, decor(Kit.union("Framing", frame, { collision = Enum.CollisionFidelity.Box })))
		-- gables on the X ends and the slate roof (ridge along X)
		local gables: { BasePart } = {}
		gable(gables, "Z", -8, 7.6, 14, 6.2, 0.8, P.Planks, M.WoodPlanks)
		gable(gables, "Z", 8, 7.6, 14, 6.2, 0.8, P.Planks, M.WoodPlanks)
		table.insert(c, solid(Kit.union("Gables", gables, { collision = Enum.CollisionFidelity.PreciseConvexDecomposition })))
		local roof: { BasePart } = {}
		gableRoof(roof, "X", 20.5, 9.2, 7.5, 19.4, 0.7, Color3.fromRGB(84, 82, 84), M.Slate)
		table.insert(c, solid(Kit.union("Roof", roof, { collision = Enum.CollisionFidelity.PreciseConvexDecomposition })))
		-- hoist beam over the loading door
		table.insert(c, decor(Kit.block("Hoist", V(0.6, 0.6, 3.4), CF(0, 14.6, 8.4), P.TimberDark, M.Wood)))
		table.insert(c, decor(Kit.rod("HoistRope", V(0, 14.3, 9.8), V(0, 9.5, 9.8), 0.12, P.Rope, M.Wood), true))

		-- millstones, gear and axle
		table.insert(c, solid(Kit.block("MillDeck", V(6, 1.4, 6), CF(1.8, 0.7, 0), P.Planks, M.WoodPlanks)))
		table.insert(c, solid(Kit.union("Millstones", {
			Kit.vcyl("Stone", 0.9, 5, CF(1.8, 1.85, 0), P.Rock, M.Slate),
			Kit.vcyl("Stone", 0.9, 4.8, CF(1.8, 2.8, 0), Kit.jitter(P.Rock, rng, 0, 0, 0.1), M.Slate),
			Kit.vcyl("Spindle", 1.2, 0.8, CF(1.8, 3.6, 0), P.Iron, M.Slate),
		}, { collision = Enum.CollisionFidelity.Default })))
		-- the mill floor sits 2.6 studs up on its stone footing, so the axle is low (2.3) to keep the wheel in the water
		local AXLE_Y = 2.3
		table.insert(c, decor(Kit.part("Gear", V(0.6, 6, 6), CF(6.2, AXLE_Y, 0), P.TimberDark, M.WoodPlanks, Enum.PartType.Cylinder)))
		table.insert(c, decor(Kit.rod("Axle", V(5.4, AXLE_Y, 0), V(10.6, AXLE_Y, 0), 1.1, P.Iron, M.Metal)))
		local mount = Kit.vcyl("AxleMount", 1.4, 1.6, CF(9.4, AXLE_Y, 0) * ANG(0, 0, math.rad(90)), P.DarkMetal, M.Metal)
		table.insert(c, decor(mount))
		for _, z in ipairs({ -2.6, 2.6 }) do
			local post = Kit.block("WheelPost", V(0.9, 11, 0.9), CF(15.2, -2.4, z), P.TimberDark, M.Wood)
			table.insert(c, solid(post))
			Kit.foot(post, V(15.2, -7.8, z), 0.9, "Wood")
		end
		table.insert(c, decor(Kit.block("WheelBeam", V(0.9, 0.9, 6.2), CF(15.2, AXLE_Y + 0.9, 0), P.TimberDark, M.Wood)))
		for k = 0, 2 do
			local top = -0.65 * (k + 1)
			table.insert(c, solid(Kit.block("Step", V(4.6, 2.6, 1.2), CF(0, top - 1.3, -8.2 - 1.2 * k), P.Rock, M.Cobblestone)))
		end
		local wheel = buildWheel()
		wheel:PivotTo(CF(12.3, AXLE_Y, 0))
		table.insert(c, wheel)

		table.insert(c, ladder(CF(-5.4, 5, 4.6), 10))
		table.insert(c, solid(Kit.block("Door", V(0.25, 6.2, 3.8), CF(-2.05, 3.1, -4.9), P.TimberWeathered, M.WoodPlanks)))
		table.insert(c, decor(Kit.block("Bracket", V(0.3, 0.3, 1.3), CF(3, 7.0, -8.1), P.TimberDark, M.Wood), true))
		table.insert(c, prop("Lantern", CF(3, 6.85, -8.6)))
		table.insert(c, prop("Sack", CF(-3.8, 0, -4.4)))
		table.insert(c, prop("Sack", CF(-3.0, 0, -5.6) * ANG(0, 2, 0)))
		table.insert(c, prop("Barrel", CF(-6.1, 0, -5.1)))
		table.insert(c, prop("Crate", CF(5.6, 0, -4.8) * ANG(0, 0.2, 0)))
		table.insert(c, prop("Sack", CF(-3, 7.5, 5)))
		table.insert(c, prop("Sack", CF(-1.8, 7.5, 5.6) * ANG(0, 1.4, 0)))
		table.insert(c, prop("Table", CF(3.5, 7.5, -3.4)))

		table.insert(c, Kit.lootOnFloor(V(-6.2, 0, -1.2), math.rad(90), 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(5.2, 0, 4.8), 0.05, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(4.9, 7.5, 4.6), -0.05, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(-3.2, 7.5, -4.8), 0.15, 2, "Crate"))
		for _, p in ipairs({ { -9, -8 }, { 9, -8 }, { -9, 8 }, { 9, 8 }, { 0, -8 }, { 0, 8 } }) do
			Kit.foot(floor, V(p[1], -4.1, p[2]), 2.4, "Stone")
		end
		local mill = finish("MillHouse", c, { Category = "Structure", Footprint = 14, Sink = 0 })
		mill.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
	task.wait()

	------------------------------------------------------------------ FISHING SHACK (door faces -Z)
	do
		local c: { Instance } = {}
		local deck = Kit.block("Deck", V(16, 0.6, 14), CF(0, -0.3, 0), P.TimberWeathered, M.WoodPlanks)
		table.insert(c, solid(deck))
		local walls: { BasePart } = {}
		wallBlocks(walls, "X", -4, -5.25, 5.25, 0, 8.4, 0.5, { { -1.5, 1.5, 0, 6.6 } }, P.TimberWeathered, M.WoodPlanks)
		wallBlocks(walls, "X", 4, -5.25, 5.25, 0, 7.5, 0.5, { { 1, 3.2, 3.2, 5.2 } }, P.TimberWeathered, M.WoodPlanks)
		wallBlocks(walls, "Z", -5, -3.75, 3.75, 0, 7.5, 0.5, { { -1, 1, 3.2, 5.2 } }, P.TimberWeathered, M.WoodPlanks)
		wallBlocks(walls, "Z", 5, -3.75, 3.75, 0, 7.5, 0.5, {}, P.TimberWeathered, M.WoodPlanks)
		for _, w in ipairs(walls) do
			table.insert(c, solid(w))
		end
		for _, x in ipairs({ -5, 5 }) do
			table.insert(c, solid(Kit.wedge("WallTop", V(0.5, 1.15, 7.5), CF(x, 7.5 + 0.575, 0) * ANG(0, math.pi, 0), P.TimberWeathered, M.WoodPlanks)))
		end
		local tin = Color3.fromRGB(124, 88, 64)
		table.insert(c, solid(Kit.plank("Roof", V(0, 8.95, -5.4), V(0, 7.55, 5.4), 12.4, 0.35, tin, M.CorrodedMetal)))
		table.insert(c, solid(Kit.block("Door", V(0.22, 6.4, 2.9), CF(-1.4, 3.2, -2.5), P.TimberDark, M.WoodPlanks)))
		local net = Kit.block("Net", V(0.15, 3.2, 4), CF(-4.62, 4.4, 1.4) * ANG(0.05, 0, 0.04), Color3.fromRGB(70, 84, 66), M.Fabric)
		table.insert(c, soft(net))
		table.insert(c, prop("Table", CF(-3.2, 0, 1.0) * ANG(0, math.rad(90), 0)))
		table.insert(c, prop("Stool", CF(-1.2, 0, 0.0)))
		table.insert(c, prop("Barrel", CF(-6.6, 0, -4.9)))
		table.insert(c, prop("Barrel", CF(-6.6, 0, -2.3) * ANG(0, 1, 0)))
		table.insert(c, prop("Barrel", CF(4.4, 0, -5.6) * ANG(0, 0.4, 0)))
		table.insert(c, prop("Sack", CF(6.6, 0, 1.5)))
		table.insert(c, decor(Kit.block("Bracket", V(0.3, 0.3, 1.2), CF(2.4, 6.9, -4.6), P.TimberDark, M.Wood), true))
		table.insert(c, prop("Lantern", CF(2.4, 6.75, -5.05)))
		table.insert(c, decor(Kit.union("Rods", {
			Kit.rod("Rod", V(3.6, 0, -4.5), V(4.6, 7.2, -4.35), 0.14, P.TimberDark, M.Wood),
			Kit.rod("Rod", V(4.1, 0, -4.5), V(4.0, 6.8, -4.35), 0.14, P.CutWood, M.Wood),
		}, { collision = Enum.CollisionFidelity.Box }), true))
		table.insert(c, Kit.lootOnFloor(V(1.6, 0, 2.2), 0, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(3.4, 0, -1.7), math.rad(90), 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(-3.0, 0, 5.6), 0, 2, "Crate"))
		for _, p in ipairs({ { -7.6, -6.6 }, { 0, -6.6 }, { 7.6, -6.6 }, { -7.6, 6.6 }, { 0, 6.6 }, { 7.6, 6.6 }, { -7.6, 0 }, { 7.6, 0 } }) do
			Kit.foot(deck, V(p[1], -0.6, p[2]), 0.9, "Wood")
		end
		finish("FishingShack", c, { Category = "Structure", Footprint = 9, Sink = 0 })
	end
	task.wait()

	------------------------------------------------------------------ STILT HUT (front -Z faces the walkway)
	do
		local c: { Instance } = {}
		local deck = Kit.block("Deck", V(16, 0.6, 14), CF(0, -0.3, 0), P.TimberWeathered, M.WoodPlanks)
		table.insert(c, solid(deck))
		local hz0 = 1.5
		local moss = Kit.jitter(P.TimberWeathered, rng, 0.04, 0.2, -0.1)
		local walls: { BasePart } = {}
		wallBlocks(walls, "X", hz0 - 4.5, -5.25, 5.25, 0, 7, 0.5, { { -1.4, 1.4, 0, 6.2 } }, moss, M.WoodPlanks)
		wallBlocks(walls, "X", hz0 + 4.5, -5.25, 5.25, 0, 7, 0.5, { { -1.2, 1.2, 3, 5 } }, moss, M.WoodPlanks)
		wallBlocks(walls, "Z", -5, hz0 - 4.25, hz0 + 4.25, 0, 7, 0.5, { { hz0 - 1.1, hz0 + 1.1, 3, 5 } }, moss, M.WoodPlanks)
		wallBlocks(walls, "Z", 5, hz0 - 4.25, hz0 + 4.25, 0, 7, 0.5, {}, moss, M.WoodPlanks)
		for _, w in ipairs(walls) do
			table.insert(c, solid(w))
		end
		local thatch: { BasePart } = {}
		Kit.pyramid(thatch, CF(0, 6.8, hz0), 13.6, 5.8, P.Thatch, M.Grass, 12.8)
		table.insert(c, solid(Kit.union("Thatch", thatch, { collision = Enum.CollisionFidelity.Default })))
		table.insert(c, decor(Kit.block("TieBeam", V(10, 0.5, 0.5), CF(0, 6.9, hz0), P.TimberDark, M.Wood), true))
		table.insert(c, prop("Lantern", CF(0, 6.65, hz0)))
		-- railings with gaps for the walkway (front-left) and the ladder (front-right)
		local ry = 0
		table.insert(c, railing(V(-7.8, ry, -6.8), V(-6.3, ry, -6.8), 3.2, P.TimberWeathered))
		table.insert(c, railing(V(-3.3, ry, -6.8), V(3.2, ry, -6.8), 3.2, P.TimberWeathered))
		table.insert(c, railing(V(5.8, ry, -6.8), V(7.8, ry, -6.8), 3.2, P.TimberWeathered))
		table.insert(c, railing(V(-7.8, ry, -6.8), V(-7.8, ry, 6.8), 3.2, P.TimberWeathered))
		table.insert(c, railing(V(7.8, ry, -6.8), V(7.8, ry, 6.8), 3.2, P.TimberWeathered))
		table.insert(c, railing(V(-7.8, ry, 6.8), V(7.8, ry, 6.8), 3.2, P.TimberWeathered))
		table.insert(c, ladder(CF(4.5, -5, -8.0), 14))
		table.insert(c, solid(Kit.block("Door", V(0.22, 6, 2.7), CF(-1.35, 3, hz0 - 2.9), P.TimberDark, M.WoodPlanks)))
		-- interior (x -4.75..4.75, z hz0-4.25..hz0+4.25): table front-right, three crates, the door leaf front-left
		table.insert(c, prop("Table", CF(3.1, 0, hz0 - 1.4) * ANG(0, math.rad(90), 0)))
		table.insert(c, prop("Barrel", CF(6.5, 0, -4.4)))
		table.insert(c, prop("Sack", CF(-6.6, 0, 1.6)))
		table.insert(c, prop("Sack", CF(-6.4, 0, 3.0) * ANG(0, 1.2, 0)))
		table.insert(c, Kit.lootOnFloor(V(-2.6, 0, hz0 + 2.8), 0, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(2.6, 0, hz0 + 2.8), 0, 2, "Crate"))
		table.insert(c, Kit.lootOnFloor(V(-3.3, 0, hz0 - 0.9), math.rad(90), 2, "Crate"))
		for _, p in ipairs({ { -7.6, -6.6 }, { 0, -6.6 }, { 7.6, -6.6 }, { -7.6, 6.6 }, { 0, 6.6 }, { 7.6, 6.6 }, { -7.6, 0 }, { 7.6, 0 }, { 0, hz0 } }) do
			Kit.foot(deck, V(p[1], -0.6, p[2]), 1.1, "Wood")
		end
		finish("StiltHut", c, { Category = "Structure", Footprint = 10, Sink = 0, FloorAboveWater = 6.5 })
	end
end

return Structures
