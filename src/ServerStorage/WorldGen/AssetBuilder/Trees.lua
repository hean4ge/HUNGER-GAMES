--[[
	Trees - tree templates for ServerStorage.WorldAssets.Trees:
	  Pine_A (classic), Pine_B (short and bushy), Pine_C (tall, bare lower trunk)
	  Oak_A, Oak_B   thick branches you can stand on; the Trunk is tagged Climbable
	  Birch_A (single), Birch_B (twin trunk)
	  DeadTree_A (swamp snag with hanging moss), DeadTree_B (leaning broken trunk)
	Every tree is a Model with ModelStreamingMode Atomic: a solid trunk (+ branches) and a soft canopy union
	(CanCollide/CanQuery = false, UsePartColor so Populate can tint each copy).
]]
local Trees = {}

function Trees.build(Kit, folders)
	local P = Kit.Palette
	local M = Enum.Material
	local out = folders.Trees
	local rng = Random.new(4242)

	local function finish(name: string, children: { Instance }, attrs: { [string]: any }): Model
		local model = Kit.model(name, children, attrs)
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model.Parent = out
		return model
	end

	-- Root flare: wedges sloping down and away from a trunk of the given radius.
	local function roots(list: { BasePart }, count: number, radius: number, height: number, length: number, color: Color3, yaw0: number)
		for i = 0, count - 1 do
			local yaw = math.rad(yaw0 + i * (360 / count) + rng:NextNumber(-12, 12))
			local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
			local pos = dir * (radius + length / 2 - 0.5) + Vector3.new(0, height / 2 - 0.35, 0)
			local cf = CFrame.lookAt(pos, pos - dir) * CFrame.Angles(0, math.pi, 0)
			table.insert(list, Kit.wedge("Root", Vector3.new(radius * 0.9, height, length), cf, color, M.Wood))
		end
	end

	------------------------------------------------------------------ pines
	local function pine(name: string, trunkTop: number, trunkDia: number, tiers: { { number } }, color: Color3, footprint: number, stubs: number)
		local wood: { BasePart } = {
			Kit.vcyl("Trunk", trunkTop + 2, trunkDia, CFrame.new(0, trunkTop / 2 - 1, 0), P.PineBark, M.Wood),
		}
		roots(wood, 3, trunkDia / 2, 1.4, 1.8, P.PineBark, rng:NextNumber(0, 120))
		for _ = 1, stubs do
			local yaw = rng:NextNumber(0, math.pi * 2)
			local y = rng:NextNumber(3, tiers[1][1])
			local dir = Vector3.new(math.sin(yaw), 0.35, math.cos(yaw)).Unit
			local a = Vector3.new(0, y, 0)
			table.insert(wood, Kit.rod("Stub", a, a + dir * rng:NextNumber(1.6, 2.6), 0.35, P.PineBark, M.Wood))
		end
		local trunk = Kit.union("Trunk", wood, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(trunk, Kit.SOLID)

		local needles: { BasePart } = {}
		for _, t in ipairs(tiers) do
			local base = CFrame.new(0, t[1], 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0)
			Kit.pyramid(needles, base, t[2], t[3], color, M.Grass)
			Kit.pyramid(needles, base * CFrame.Angles(0, math.rad(45), 0), t[2] * 0.93, t[3] * 0.97, color, M.Grass)
		end
		local canopy = Kit.union("Needles", needles, { collision = Enum.CollisionFidelity.Box, usePartColor = true })
		Kit.setAll(canopy, Kit.SOFT)
		local last = tiers[#tiers]
		return finish(name, { trunk, canopy }, {
			Category = "Tree", Kind = "Pine", Footprint = footprint, Sink = 0.6, Height = last[1] + last[3],
		})
	end

	pine("Pine_A", 19, 1.7, { { 4.5, 13, 9 }, { 9, 10.6, 8.6 }, { 13.5, 8.2, 8.2 }, { 18, 5.4, 8 } }, P.PineNeedles, 6, 2)
	pine("Pine_B", 12, 1.5, { { 2.6, 12.5, 8 }, { 7, 9.2, 7.6 }, { 11.2, 6, 7.6 } }, P.PineNeedlesLight, 6, 0)
	pine("Pine_C", 27, 1.9, { { 8, 11, 8.2 }, { 12.8, 9.4, 7.8 }, { 17.4, 7.8, 7.4 }, { 21.8, 6, 7 }, { 26, 4, 8 } }, P.PineNeedlesDark, 5.5, 4)

	------------------------------------------------------------------ oaks
	type OakSpec = {
		trunk: { { number } }, -- { y0, y1, diameter }
		branches: { { any } }, -- { from: Vector3, to: Vector3, diameter }
		canopy: { { any } }, -- { centre: Vector3, diameter }
		leaves: Color3,
		footprint: number,
	}
	local function oak(name: string, spec: OakSpec)
		local wood: { BasePart } = {}
		for _, s in ipairs(spec.trunk) do
			table.insert(wood, Kit.vcyl("Trunk", s[2] - s[1], s[3], CFrame.new(0, (s[1] + s[2]) / 2, 0), P.OakBark, M.Wood))
		end
		roots(wood, 4, spec.trunk[1][3] / 2, 2.4, 2.8, P.OakBark, rng:NextNumber(0, 90))
		local trunk = Kit.union("Trunk", wood, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(trunk, Kit.SOLID)
		trunk:AddTag("Climbable")

		local children: { Instance } = { trunk }
		for i, b in ipairs(spec.branches) do
			local branch = Kit.rod("Branch" .. i, b[1], b[2], b[3], P.OakBark, M.Wood)
			Kit.setAll(branch, Kit.SOLID)
			table.insert(children, branch)
		end

		local balls: { BasePart } = {}
		for _, c in ipairs(spec.canopy) do
			table.insert(balls, Kit.ball("Leaves", c[2], c[1], spec.leaves, M.LeafyGrass))
		end
		local canopy = Kit.union("Leaves", balls, { collision = Enum.CollisionFidelity.Box, usePartColor = true })
		Kit.setAll(canopy, Kit.SOFT)
		table.insert(children, canopy)
		local top = 0
		for _, c in ipairs(spec.canopy) do
			top = math.max(top, c[1].Y + c[2] / 2)
		end
		return finish(name, children, { Category = "Tree", Kind = "Oak", Footprint = spec.footprint, Sink = 0.8, Height = top })
	end

	local V = Vector3.new
	oak("Oak_A", {
		trunk = { { -2, 9.5, 3.2 }, { 9, 14.5, 2.6 } },
		branches = {
			{ V(0, 9.5, 0), V(6.8, 14.2, 1.5), 1.9 },
			{ V(0, 10.5, 0), V(-4.6, 14.8, 4.8), 1.8 },
			{ V(0, 11, 0), V(-2.2, 15.2, -6.6), 1.7 },
			{ V(0, 13.5, 0), V(1.5, 19.5, -1), 1.6 },
		},
		canopy = {
			{ V(6.8, 16.6, 1.5), 9 }, { V(-4.6, 17.2, 4.8), 9 }, { V(-2.2, 17.6, -6.6), 9 },
			{ V(1.5, 21.4, -1), 11 }, { V(0, 18.4, 2), 10 }, { V(3.6, 19.6, -4), 8.5 }, { V(-5.2, 20.2, -1), 8 },
		},
		leaves = P.OakLeaves,
		footprint = 8,
	})
	oak("Oak_B", {
		trunk = { { -2, 7.5, 3.6 }, { 7, 10.5, 3 } },
		branches = {
			{ V(0, 7, 0), V(7.6, 9.8, 0.2), 2.1 },
			{ V(0, 7.5, 0), V(-3.6, 10.4, 6.6), 2 },
			{ V(0, 8, 0), V(-4.1, 10.6, -6.4), 2 },
			{ V(0, 9.5, 0), V(2.5, 15, -2), 1.7 },
		},
		canopy = {
			{ V(7.6, 12.6, 0.2), 10 }, { V(-3.6, 13.2, 6.6), 10 }, { V(-4.1, 13.2, -6.4), 10 },
			{ V(2.5, 16.8, -2), 11 }, { V(0, 14.4, 1), 11 }, { V(-6.4, 14.6, 0), 8.5 }, { V(4.2, 13.8, 5.2), 8.5 },
			{ V(4.2, 13.8, -6), 8 },
		},
		leaves = P.OakLeavesDark,
		footprint = 9,
	})

	------------------------------------------------------------------ birches
	local function birchTrunk(list: { BasePart }, a: Vector3, b: Vector3, dia: number)
		table.insert(list, Kit.rod("Trunk", a, b, dia, P.BirchBark, M.Wood))
		local axis = (b - a).Unit
		local length = (b - a).Magnitude
		local t = 2.5
		while t < length - 3 do
			local p = a + axis * t
			local half = rng:NextNumber(0.08, 0.16)
			table.insert(list, Kit.rod("Mark", p - axis * half, p + axis * half, dia + 0.07, P.BirchMark, M.Wood))
			t += rng:NextNumber(1.6, 2.8)
		end
	end
	local function birch(name: string, trunks: { { any } }, canopy: { { any } }, footprint: number)
		local wood: { BasePart } = {}
		for _, t in ipairs(trunks) do
			birchTrunk(wood, t[1], t[2], t[3])
		end
		local trunk = Kit.union("Trunk", wood, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(trunk, Kit.SOLID)
		local balls: { BasePart } = {}
		local top = 0
		for _, c in ipairs(canopy) do
			table.insert(balls, Kit.ball("Leaves", c[2], c[1], P.BirchLeaves, M.LeafyGrass))
			top = math.max(top, c[1].Y + c[2] / 2)
		end
		local leaves = Kit.union("Leaves", balls, { collision = Enum.CollisionFidelity.Box, usePartColor = true })
		Kit.setAll(leaves, Kit.SOFT)
		return finish(name, { trunk, leaves }, { Category = "Tree", Kind = "Birch", Footprint = footprint, Sink = 0.5, Height = top })
	end

	birch("Birch_A", { { V(0, -2, 0), V(0.9, 21.5, 0.3), 1.25 } }, {
		{ V(0.6, 13.5, 0.4), 6 }, { V(-0.4, 16.2, -0.4), 6.6 }, { V(1.1, 18.8, 0.7), 6 }, { V(0.5, 21.2, 0), 5.2 },
		{ V(0.9, 23.4, 0.2), 3.8 }, { V(3.2, 15.2, 1), 3.6 }, { V(-2.2, 18.2, -1.4), 3.6 },
	}, 4)
	birch("Birch_B", { { V(-0.5, -2, 0), V(-1.9, 19, 0.5), 1.05 }, { V(0.5, -2, 0), V(2.1, 17, -0.6), 0.95 } }, {
		{ V(-1.8, 13, 0.5), 5.6 }, { V(-2.2, 15.8, 0.3), 5.8 }, { V(-1.9, 18.6, 0.6), 4.8 }, { V(-2.4, 20.8, 0.4), 3.4 },
		{ V(2, 11.6, -0.6), 5 }, { V(2.3, 14.4, -0.8), 5.4 }, { V(2.1, 17, -0.5), 4.4 }, { V(0.2, 14.5, 0), 4 },
	}, 4.5)

	------------------------------------------------------------------ dead swamp trees
	local function deadTree(name: string, segments: { { any } }, moss: { Vector3 }, footprint: number, lean: number)
		local wood: { BasePart } = {}
		for _, s in ipairs(segments) do
			table.insert(wood, Kit.rod("Wood", s[1], s[2], s[3], P.DeadWood, M.Wood))
			-- knuckle so bends look continuous
			table.insert(wood, Kit.ball("Knot", s[3] * 1.02, s[2], P.DeadWood, M.Wood))
		end
		roots(wood, 3, segments[1][3] / 2, 1.8, 2.4, P.DeadWood, rng:NextNumber(0, 120))
		local snag = Kit.union("Snag", wood, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(snag, Kit.SOLID)
		local children: { Instance } = { snag }
		if #moss > 0 then
			local strands: { BasePart } = {}
			for _, p in ipairs(moss) do
				local len = rng:NextNumber(1.8, 3.4)
				local cf = CFrame.new(p - Vector3.new(0, len / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.12, 0.12))
				table.insert(strands, Kit.block("Moss", Vector3.new(0.12, len, rng:NextNumber(0.5, 0.9)), cf, P.Moss, M.Grass))
			end
			local mossUnion = Kit.union("Moss", strands, { collision = Enum.CollisionFidelity.Box, usePartColor = true })
			Kit.setAll(mossUnion, Kit.SOFT)
			Kit.setAll(mossUnion, Kit.NOSHADOW)
			table.insert(children, mossUnion)
		end
		local top = 0
		for _, s in ipairs(segments) do
			top = math.max(top, s[2].Y)
		end
		local model = finish(name, children, { Category = "Tree", Kind = "Dead", Footprint = footprint, Sink = 0.7, Height = top })
		if lean ~= 0 then
			model:PivotTo(CFrame.Angles(0, 0, math.rad(lean)))
			model.WorldPivot = CFrame.identity
		end
		return model
	end

	deadTree("DeadTree_A", {
		{ V(0, -2, 0), V(0.3, 8, 0.2), 2.2 },
		{ V(0.3, 8, 0.2), V(-0.4, 15, 0.6), 1.5 },
		{ V(-0.4, 15, 0.6), V(0.2, 18.2, 0.4), 0.9 },
		{ V(0.2, 9, 0.1), V(4, 12, 1), 0.8 },
		{ V(4, 12, 1), V(5.6, 15.2, 0.4), 0.55 },
		{ V(0, 11, 0.4), V(-3.6, 13.4, -1.5), 0.75 },
		{ V(-3.6, 13.4, -1.5), V(-5.2, 16.6, -1), 0.5 },
		{ V(-0.2, 13.6, 0.5), V(1.6, 16.2, -3), 0.6 },
		{ V(0.1, 6, 0), V(-2.6, 7.6, 2.6), 0.7 },
	}, { V(4, 12, 1), V(2.4, 10.6, 0.6), V(-3.6, 13.4, -1.5), V(-1.8, 12.2, -0.6), V(1.6, 16.2, -3), V(-2.6, 7.6, 2.6), V(5.2, 14.4, 0.5) }, 4, 0)
	deadTree("DeadTree_B", {
		{ V(0, -2, 0), V(1.2, 6, 0.4), 2.6 },
		{ V(1.2, 6, 0.4), V(2.6, 10.6, 0.9), 2 },
		{ V(2.6, 10.6, 0.9), V(3, 12, 1.4), 1.2 },
		{ V(1.6, 7, 0.5), V(-1.5, 10, 1.5), 0.8 },
		{ V(-1.5, 10, 1.5), V(-3, 12.6, 1), 0.6 },
		{ V(2.2, 9, 0.7), V(4.6, 10.2, -1), 0.6 },
	}, { V(-1.5, 10, 1.5), V(4.4, 10.1, -0.9), V(0.2, 8.6, 1) }, 4, -6)
end

return Trees
