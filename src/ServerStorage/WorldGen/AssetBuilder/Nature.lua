--[[
	Nature - plant and rock templates.
	  Plants: Bush_A (small), Bush_B (medium), Bush_C (large hiding bush), BerryBush, Reeds_A, Reeds_B,
	          Mushrooms_A, Mushrooms_B, Fern_A, Flowers_A, Flowers_B, Stump_A, FallenLog_A, FallenLog_B
	  Rocks:  Rock_<Small|Medium|Large|Huge>_<Rock|Slate|Basalt> (irregular CSG silhouettes, one part each)
	Bushes, reeds, ferns and flowers are soft (CanCollide/CanQuery = false) so players can walk in and hide.
]]
local Nature = {}

function Nature.build(Kit, folders)
	local P = Kit.Palette
	local M = Enum.Material
	local V = Vector3.new
	local plants = folders.Plants
	local rocks = folders.Rocks
	local rng = Random.new(777)

	local function finish(folder: Folder, name: string, children: { Instance }, attrs: { [string]: any }): Model
		local model = Kit.model(name, children, attrs)
		model.Parent = folder
		return model
	end

	------------------------------------------------------------------ bushes
	local function leafBalls(spec: { { any } }, color: Color3): BasePart
		local balls: { BasePart } = {}
		for _, b in ipairs(spec) do
			table.insert(balls, Kit.ball("Leaves", b[2], b[1], color, M.LeafyGrass))
		end
		local u = Kit.union("Leaves", balls, { collision = Enum.CollisionFidelity.Box, usePartColor = true })
		Kit.setAll(u, Kit.SOFT)
		return u :: BasePart
	end

	local bushA = { { V(0, 1, 0), 3.4 }, { V(1.4, 0.8, 0.5), 2.6 }, { V(-1.2, 0.7, -0.6), 2.5 }, { V(0.2, 0.8, -1.3), 2.2 } }
	local bushB = {
		{ V(0, 1.6, 0), 4.6 }, { V(2.2, 1.2, 0.6), 3.6 }, { V(-2.1, 1.1, -0.4), 3.5 }, { V(0.4, 1, 2), 3.2 },
		{ V(-0.5, 1.2, -2), 3.2 }, { V(0.6, 2.6, -0.3), 3 },
	}
	local bushC = {
		{ V(0, 2.4, 0), 6.4 }, { V(3, 1.8, 1), 5 }, { V(-3, 1.7, -0.6), 5 }, { V(0.6, 1.6, 3), 4.6 }, { V(-0.8, 1.7, -3), 4.6 },
		{ V(2.4, 1.6, -2.4), 4 }, { V(-2.4, 1.6, 2.4), 4 }, { V(0.2, 4, 0.3), 4.4 },
	}
	local a = leafBalls(bushA, P.BushLeaves)
	Kit.setAll(a, Kit.NOSHADOW)
	finish(plants, "Bush_A", { a }, { Category = "Plant", Kind = "Bush", Footprint = 2.6, Sink = 0.3 })
	finish(plants, "Bush_B", { leafBalls(bushB, P.BushLeaves) }, { Category = "Plant", Kind = "Bush", Footprint = 3.8, Sink = 0.3 })
	finish(plants, "Bush_C", { leafBalls(bushC, P.BushLeavesDark) }, { Category = "Plant", Kind = "Bush", Footprint = 5.2, Sink = 0.4, Hide = true })

	do -- berry bush
		local leaves = leafBalls(bushB, P.BushLeavesDark)
		local berries: { BasePart } = {}
		for _ = 1, 9 do
			local b = bushB[rng:NextInteger(1, #bushB)]
			local dir = V(rng:NextNumber(-1, 1), rng:NextNumber(-0.1, 1), rng:NextNumber(-1, 1)).Unit
			local centre = b[1] + dir * (b[2] / 2 * 0.97)
			for _ = 1, 3 do
				local jitter = V(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.3, 0.3))
				table.insert(berries, Kit.ball("Berry", rng:NextNumber(0.34, 0.46), centre + jitter, P.Berry, M.SmoothPlastic))
			end
		end
		local berryUnion = Kit.union("Berries", berries, { collision = Enum.CollisionFidelity.Box, usePartColor = true })
		Kit.setAll(berryUnion, Kit.SOFT)
		Kit.setAll(berryUnion, Kit.NOSHADOW)
		finish(plants, "BerryBush", { leaves, berryUnion }, { Category = "Plant", Kind = "BerryBush", Footprint = 3.8, Sink = 0.3 })
	end

	------------------------------------------------------------------ reeds
	local function reeds(name: string, count: number, height: number, spread: number, color: Color3, cattails: number)
		local stalks: { BasePart } = {}
		for i = 1, count do
			local ang = rng:NextNumber(0, math.pi * 2)
			local rad = spread * math.sqrt(rng:NextNumber())
			local h = height * rng:NextNumber(0.55, 1)
			local base = CFrame.new(math.cos(ang) * rad, -0.4, math.sin(ang) * rad)
				* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.2, 0.2))
			table.insert(stalks, Kit.block("Reed", V(0.14, h, rng:NextNumber(0.24, 0.4)), base * CFrame.new(0, h / 2, 0), color, M.Grass))
			if i <= cattails then
				table.insert(stalks, Kit.vcyl("Cattail", 1.1, 0.36, base * CFrame.new(0, h + 0.2, 0), P.Cattail, M.Grass))
				table.insert(stalks, Kit.vcyl("Tip", 0.9, 0.08, base * CFrame.new(0, h + 1.1, 0), color, M.Grass))
			end
		end
		local u = Kit.union("Reeds", stalks, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(u, Kit.SOFT)
		Kit.setAll(u, Kit.NOSHADOW)
		return finish(plants, name, { u }, { Category = "Plant", Kind = "Reeds", Footprint = spread + 0.6, Sink = 0 })
	end
	reeds("Reeds_A", 12, 4.6, 1.5, P.Reed, 3)
	reeds("Reeds_B", 16, 5.6, 2.1, P.ReedDry, 2)

	------------------------------------------------------------------ mushrooms, ferns, flowers
	local function mushrooms(name: string, spec: { { any } }, capColor: Color3)
		local parts: { BasePart } = {}
		for _, s in ipairs(spec) do
			local base = CFrame.new(s[1]) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15))
			table.insert(parts, Kit.vcyl("Stem", s[2] + 0.3, s[3], base * CFrame.new(0, (s[2] - 0.3) / 2, 0), P.MushroomStem, M.SmoothPlastic))
			table.insert(parts, Kit.dome("Cap", s[4], base * CFrame.new(0, s[2] - 0.15, 0), capColor, M.SmoothPlastic))
		end
		local u = Kit.union("Mushrooms", parts, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(u, Kit.SOFT)
		Kit.setAll(u, Kit.NOSHADOW)
		return finish(plants, name, { u }, { Category = "Plant", Kind = "Mushrooms", Footprint = 1.2, Sink = 0 })
	end
	mushrooms("Mushrooms_A", { { V(0, 0, 0), 0.9, 0.36, 1.3 }, { V(0.7, 0, 0.4), 0.6, 0.28, 0.9 }, { V(-0.5, 0, 0.6), 0.45, 0.22, 0.7 } }, P.MushroomCap)
	mushrooms("Mushrooms_B", { { V(0, 0, 0), 1.2, 0.45, 1.8 }, { V(-0.9, 0, -0.3), 0.8, 0.34, 1.2 } }, P.MushroomCapTan)

	do -- fern: tapered fronds (two mirrored thin wedges each, wide at the base, pointed at the tip)
		local fronds: { BasePart } = {}
		for i = 1, 9 do
			local yaw = (i / 9) * math.pi * 2 + rng:NextNumber(-0.22, 0.22)
			local len = rng:NextNumber(2.2, 3.3)
			local width = rng:NextNumber(0.5, 0.7)
			local base = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(rng:NextNumber(24, 50)), 0, 0)
			for _, side in ipairs({ -1, 1 }) do
				local cf = base * CFrame.new(side * width / 4, 0, -len / 2) * CFrame.Angles(0, 0, -side * math.pi / 2)
				table.insert(fronds, Kit.wedge("Frond", V(0.06, width / 2, len), cf, P.OakLeavesDark, M.Grass))
			end
		end
		local u = Kit.union("Fronds", fronds, { collision = Enum.CollisionFidelity.Box, usePartColor = true })
		Kit.setAll(u, Kit.SOFT)
		Kit.setAll(u, Kit.NOSHADOW)
		finish(plants, "Fern_A", { u }, { Category = "Plant", Kind = "Fern", Footprint = 1.8, Sink = 0.1 })
	end

	local function flowers(name: string, petal: Color3, count: number)
		local parts: { BasePart } = {}
		for _ = 1, count do
			local ang = rng:NextNumber(0, math.pi * 2)
			local rad = 1.6 * math.sqrt(rng:NextNumber())
			local h = rng:NextNumber(0.6, 1.2)
			local pos = V(math.cos(ang) * rad, 0, math.sin(ang) * rad)
			table.insert(parts, Kit.vcyl("Stem", h + 0.2, 0.07, CFrame.new(pos + V(0, h / 2 - 0.1, 0)), P.OakLeaves, M.SmoothPlastic))
			table.insert(parts, Kit.ball("Bloom", rng:NextNumber(0.26, 0.38), pos + V(0, h, 0), Kit.jitter(petal, rng, 0.02, 0.1, 0.1), M.SmoothPlastic))
		end
		local u = Kit.union("Flowers", parts, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(u, Kit.SOFT)
		Kit.setAll(u, Kit.NOSHADOW)
		return finish(plants, name, { u }, { Category = "Plant", Kind = "Flowers", Footprint = 1.8, Sink = 0 })
	end
	flowers("Flowers_A", Color3.fromRGB(236, 226, 196), 14)
	flowers("Flowers_B", Color3.fromRGB(150, 118, 196), 12)

	------------------------------------------------------------------ stumps and logs
	do
		local wood: { BasePart } = { Kit.vcyl("Stump", 3.2, 2.8, CFrame.new(0, 0.6, 0), P.OakBark, M.Wood) }
		Kit.roots(wood, 4, 1.4, 1.5, 1.9, P.OakBark, rng)
		table.insert(wood, Kit.vcyl("Rings", 0.1, 2.5, CFrame.new(0, 2.22, 0), P.CutWood, M.Wood))
		table.insert(wood, Kit.wedge("Splinter", V(0.8, 0.9, 0.6), CFrame.new(0.6, 2.6, 0.4) * CFrame.Angles(0, 0.6, 0), P.OakBark, M.Wood))
		local u = Kit.union("Stump", wood, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(u, Kit.SOLID)
		finish(plants, "Stump_A", { u }, { Category = "Plant", Kind = "Stump", Footprint = 2, Sink = 0.2 })
	end

	local function fallenLog(name: string, length: number, dia: number, color: Color3, hollow: boolean)
		local y = dia / 2 - 0.25
		local log = Kit.part("Log", V(length, dia, dia), CFrame.new(0, y, 0), color, M.Wood, Enum.PartType.Cylinder)
		Kit.setAll(log, Kit.SOLID)
		local details: { BasePart } = {
			Kit.part("Cap", V(0.1, dia - 0.3, dia - 0.3), CFrame.new(length / 2 + 0.02, y, 0), if hollow then P.Charcoal else P.CutWood, M.Wood, Enum.PartType.Cylinder),
			Kit.part("Cap", V(0.1, dia - 0.3, dia - 0.3), CFrame.new(-length / 2 - 0.02, y, 0), P.CutWood, M.Wood, Enum.PartType.Cylinder),
			Kit.rod("Stub", V(length * 0.2, y, 0), V(length * 0.2 + 0.6, y + 1.7, -1.2), 0.5, color, M.Wood),
			Kit.rod("Stub", V(-length * 0.15, y, 0), V(-length * 0.15 - 0.4, y + 0.6, 1.9), 0.45, color, M.Wood),
		}
		local d = Kit.union("Details", details, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(d, Kit.DECOR)
		Kit.setAll(d, Kit.NOSHADOW)
		local moss = Kit.union("Moss", {
			Kit.block("Moss", V(length * 0.35, 0.3, dia * 0.55), CFrame.new(-length * 0.1, y + dia / 2 - 0.05, 0.1), P.Moss, M.Grass),
			Kit.block("Moss", V(length * 0.2, 0.3, dia * 0.45), CFrame.new(length * 0.28, y + dia / 2 - 0.1, -0.2) * CFrame.Angles(0.3, 0, 0), P.Moss, M.Grass),
		}, { collision = Enum.CollisionFidelity.Box, usePartColor = true })
		Kit.setAll(moss, Kit.SOFT)
		Kit.setAll(moss, Kit.NOSHADOW)
		return finish(plants, name, { log, d, moss }, { Category = "Plant", Kind = "Log", Footprint = length / 2, Sink = 0.1 })
	end
	fallenLog("FallenLog_A", 16, 2.4, P.OakBark, false)
	fallenLog("FallenLog_B", 11, 3, P.DeadWood, true)

	------------------------------------------------------------------ rocks
	local SIZES = {
		{ "Small", V(2.6, 1.7, 2.2), 3, Enum.CollisionFidelity.Hull, false },
		{ "Medium", V(5.4, 3.4, 4.6), 4, Enum.CollisionFidelity.Hull, true },
		{ "Large", V(10, 6.2, 8.6), 5, Enum.CollisionFidelity.Default, true },
		{ "Huge", V(17, 11, 14.5), 6, Enum.CollisionFidelity.Default, true },
	}
	local STONES = {
		{ "Rock", M.Rock, P.Rock },
		{ "Slate", M.Slate, P.Slate },
		{ "Basalt", M.Basalt, P.Basalt },
	}
	for si, size in ipairs(SIZES) do
		for mi, stone in ipairs(STONES) do
			local r = Random.new(9000 + si * 31 + mi * 7)
			local s: Vector3 = size[2]
			local pieces: { BasePart } = {
				Kit.block("Rock", s * V(0.78, 0.72, 0.78), CFrame.new(0, s.Y * 0.3, 0)
					* CFrame.Angles(r:NextNumber(-0.15, 0.15), r:NextNumber(0, math.pi), r:NextNumber(-0.15, 0.15)), stone[3], stone[2]),
			}
			for _ = 1, size[3] do
				local ps = s * V(r:NextNumber(0.38, 0.72), r:NextNumber(0.32, 0.66), r:NextNumber(0.38, 0.72))
				local offset = V(r:NextNumber(-0.3, 0.3) * s.X, r:NextNumber(0.08, 0.38) * s.Y, r:NextNumber(-0.3, 0.3) * s.Z)
				local cf = CFrame.new(offset) * CFrame.Angles(r:NextNumber(-0.55, 0.55), r:NextNumber(0, math.pi * 2), r:NextNumber(-0.55, 0.55))
				table.insert(pieces, Kit.block("Rock", ps, cf, stone[3], stone[2]))
			end
			-- a sloped facet so the silhouette is not all boxes
			local ws = s * V(0.55, 0.5, 0.6)
			table.insert(pieces, Kit.wedge("Facet", ws, CFrame.new(r:NextNumber(-0.2, 0.2) * s.X, s.Y * 0.42, r:NextNumber(-0.2, 0.2) * s.Z)
				* CFrame.Angles(0, r:NextNumber(0, math.pi * 2), 0), stone[3], stone[2]))
			local u = Kit.union("Rock", pieces, { collision = size[4], usePartColor = true })
			Kit.setAll(u, Kit.SOLID)
			if not size[5] then
				Kit.setAll(u, Kit.NOSHADOW)
			end
			local name = string.format("Rock_%s_%s", size[1], stone[1])
			finish(rocks, name, { u }, {
				Category = "Rock", Kind = "Rock", Size = size[1], Stone = stone[1],
				Footprint = math.max(s.X, s.Z) * 0.55, Sink = s.Y * 0.12,
			})
		end
		task.wait()
	end
end

return Nature
