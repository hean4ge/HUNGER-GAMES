--[[
	Props - man-made prop templates for ServerStorage.WorldAssets.Props:
	  Campfire, Tent, Tent_Green, Crate, CrateStack, Barrel, Fence_Segment, Lantern (hangs from its pivot),
	  LanternPost, Bench, LogSeat, Brazier, Banner, NoticeBoard, Signpost, Plinth, Rowboat, Sack, Bedroll,
	  Table, Stool, Shelf, Firewood
	Fires carry a FireFx attachment (flames, embers, smoke, PointLight) and an EmitterPoint ("Emit_Fire").
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Props = {}

function Props.build(Kit, folders)
	local P = Kit.Palette
	local M = Enum.Material
	local V = Vector3.new
	local CF = CFrame.new
	local out = folders.Props
	local rng = Random.new(31337)

	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Config = require(Shared:WaitForChild("Config"))
	local Theme = require(Shared:WaitForChild("Theme"))

	local function finish(name: string, children: { Instance }, attrs: { [string]: any }): Model
		local model = Kit.model(name, children, attrs)
		model.Parent = out
		return model
	end

	------------------------------------------------------------------ campfire
	do
		local stones: { BasePart } = {}
		for i = 1, 9 do
			local ang = (i / 9) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local pos = V(math.cos(ang) * 1.95, 0.18, math.sin(ang) * 1.95)
			local size = V(rng:NextNumber(0.9, 1.2), rng:NextNumber(0.55, 0.8), rng:NextNumber(0.8, 1.0))
			local cf = CFrame.lookAt(pos, V(0, pos.Y, 0)) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.25, 0.25))
			table.insert(stones, Kit.block("Stone", size, cf, Kit.jitter(P.Rock, rng, 0.01, 0.1, 0.12), M.Rock))
		end
		local ring = Kit.union("Stones", stones, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(ring, Kit.DECOR)
		Kit.setAll(ring, Kit.NOSHADOW)

		local logs: { BasePart } = {}
		for i = 1, 5 do
			local ang = (i / 5) * math.pi * 2
			local foot = V(math.cos(ang) * 1.15, 0.1, math.sin(ang) * 1.15)
			table.insert(logs, Kit.rod("Log", foot, V(0, 1.45, 0), rng:NextNumber(0.34, 0.44), if i % 2 == 0 then P.TimberDark else P.CutWood, M.Wood))
		end
		table.insert(logs, Kit.rod("Log", V(-1.3, 0.25, -0.4), V(1.2, 0.25, 0.5), 0.42, P.TimberDark, M.Wood))
		local logUnion = Kit.union("Logs", logs, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(logUnion, Kit.DECOR)
		Kit.setAll(logUnion, Kit.NOSHADOW)

		local ash = Kit.vcyl("Ash", 0.12, 2.8, CF(0, 0.04, 0), P.Charcoal, M.Slate)
		Kit.setAll(ash, Kit.DECOR)
		local embers = Kit.vcyl("Embers", 0.22, 1.3, CF(0, 0.16, 0), P.EmberDeep, M.Neon)
		Kit.setAll(embers, Kit.DECOR)
		Kit.setAll(embers, Kit.NOSHADOW)
		local att = Instance.new("Attachment")
		att.Name = "FireFx"
		att.Parent = embers
		att.WorldPosition = V(0, 0.45, 0)
		Kit.fireFx(att, 1, { light = 1.1, range = 20, shadows = true })
		finish("Campfire", { ring, logUnion, ash, embers, Kit.emitterPoint(V(0, 1, 0), "Emit_Fire") },
			{ Category = "Prop", Kind = "Campfire", Footprint = 2.6, Sink = 0.05 })
	end

	------------------------------------------------------------------ tents
	local function tent(name: string, cloth: Color3)
		local halfW, height, depth = 3.6, 5.6, 8.4
		local slant = math.sqrt(halfW * halfW + height * height)
		local angle = math.atan2(height, halfW)
		local panels: { BasePart } = {
			Kit.block("Panel", V(slant + 0.3, 0.18, depth), CF(-halfW / 2, height / 2, 0) * CFrame.Angles(0, 0, angle), cloth, M.Fabric),
			Kit.block("Panel", V(slant + 0.3, 0.18, depth), CF(halfW / 2, height / 2, 0) * CFrame.Angles(0, 0, -angle), cloth, M.Fabric),
		}
		-- back wall: two wedges forming a triangle in the XY plane
		local back = depth / 2 - 0.1
		table.insert(panels, Kit.wedge("Back", V(0.16, height, halfW), CF(-halfW / 2, height / 2, back) * CFrame.Angles(0, math.rad(90), 0), cloth, M.Fabric))
		table.insert(panels, Kit.wedge("Back", V(0.16, height, halfW), CF(halfW / 2, height / 2, back) * CFrame.Angles(0, math.rad(-90), 0), cloth, M.Fabric))
		-- a front flap tied back
		table.insert(panels, Kit.wedge("Flap", V(0.14, height * 0.8, halfW * 0.7), CF(-halfW * 0.62, height * 0.4, -depth / 2 - 0.15) * CFrame.Angles(0, math.rad(115), 0), Kit.jitter(cloth, rng, 0, 0.05, -0.12), M.Fabric))
		local shell = Kit.union("Canvas", panels, { collision = Enum.CollisionFidelity.PreciseConvexDecomposition })
		Kit.setAll(shell, Kit.SOLID)

		local poles: { BasePart } = {
			Kit.rod("Ridge", V(0, height + 0.05, -depth / 2 - 0.4), V(0, height + 0.05, depth / 2 + 0.3), 0.22, P.TimberDark, M.Wood),
			Kit.rod("Pole", V(0, 0, -depth / 2 - 0.3), V(0, height + 0.3, -depth / 2 - 0.3), 0.2, P.TimberDark, M.Wood),
			Kit.rod("Pole", V(0, 0, depth / 2 + 0.2), V(0, height + 0.3, depth / 2 + 0.2), 0.2, P.TimberDark, M.Wood),
			Kit.rod("Rope", V(0, height + 0.2, -depth / 2 - 0.35), V(0, 0, -depth / 2 - 1.7), 0.06, P.Rope, M.Wood),
			Kit.rod("Rope", V(0, height + 0.2, depth / 2 + 0.25), V(0, 0, depth / 2 + 1.9), 0.06, P.Rope, M.Wood),
			Kit.rod("Stake", V(0, -0.3, -depth / 2 - 1.7), V(0, 0.4, -depth / 2 - 1.7), 0.16, P.TimberDark, M.Wood),
			Kit.rod("Stake", V(0, -0.3, depth / 2 + 1.9), V(0, 0.4, depth / 2 + 1.9), 0.16, P.TimberDark, M.Wood),
		}
		local frame = Kit.union("Poles", poles, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(frame, Kit.DECOR)
		Kit.setAll(frame, Kit.NOSHADOW)
		local floor = Kit.block("Groundsheet", V(halfW * 2 - 0.4, 0.1, depth - 0.3), CF(0, 0.03, 0), Kit.jitter(cloth, rng, 0, 0.1, -0.3), M.Fabric)
		Kit.setAll(floor, Kit.DECOR)
		return finish(name, { shell, frame, floor }, { Category = "Prop", Kind = "Tent", Footprint = 5, Sink = 0 })
	end
	tent("Tent", P.Canvas)
	tent("Tent_Green", P.CanvasGreen)

	------------------------------------------------------------------ crates, barrels, sacks
	local function crateParts(origin: CFrame, size: number): { BasePart }
		local s = size
		local list: { BasePart } = { Kit.block("Body", V(s - 0.15, s - 0.15, s - 0.15), origin * CF(0, s / 2, 0), P.TimberWeathered, M.WoodPlanks) }
		local e = 0.36
		for _, x in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				table.insert(list, Kit.block("Edge", V(e, s, e), origin * CF(x * (s - e) / 2, s / 2, z * (s - e) / 2), P.TimberDark, M.WoodPlanks))
			end
			for _, y in ipairs({ e / 2, s - e / 2 }) do
				table.insert(list, Kit.block("Edge", V(e, e, s), origin * CF(x * (s - e) / 2, y, 0), P.TimberDark, M.WoodPlanks))
				table.insert(list, Kit.block("Edge", V(s, e, e), origin * CF(0, y, x * (s - e) / 2), P.TimberDark, M.WoodPlanks))
			end
		end
		-- diagonal brace on two faces
		local diag = math.sqrt(2) * (s - e)
		table.insert(list, Kit.block("Brace", V(diag, e * 0.8, 0.12), origin * CF(0, s / 2, -s / 2) * CFrame.Angles(0, 0, math.rad(45)), P.TimberDark, M.WoodPlanks))
		table.insert(list, Kit.block("Brace", V(0.12, e * 0.8, diag), origin * CF(s / 2, s / 2, 0) * CFrame.Angles(math.rad(45), 0, 0), P.TimberDark, M.WoodPlanks))
		return list
	end
	do
		local crate = Kit.union("Crate", crateParts(CFrame.identity, 3), { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(crate, Kit.SOLID)
		finish("Crate", { crate }, { Category = "Prop", Kind = "Crate", Footprint = 1.9, Sink = 0 })
		local stack: { Instance } = {}
		for i, cf in ipairs({ CF(-1.6, 0, 0) * CFrame.Angles(0, 0.08, 0), CF(1.6, 0, 0.2) * CFrame.Angles(0, -0.12, 0), CF(-0.4, 3, 0.1) * CFrame.Angles(0, 0.35, 0) }) do
			local c = Kit.union("Crate" .. i, crateParts(cf, 3), { collision = Enum.CollisionFidelity.Box })
			Kit.setAll(c, Kit.SOLID)
			table.insert(stack, c)
		end
		finish("CrateStack", stack, { Category = "Prop", Kind = "Crate", Footprint = 3.6, Sink = 0 })
	end

	do
		local staves: { BasePart } = {
			Kit.vcyl("Body", 3.4, 2.45, CF(0, 1.7, 0), P.Timber, M.WoodPlanks),
			Kit.vcyl("Belly", 1.8, 2.62, CF(0, 1.7, 0), P.Timber, M.WoodPlanks),
		}
		for _, y in ipairs({ 0.45, 1.15, 2.25, 2.95 }) do
			table.insert(staves, Kit.vcyl("Hoop", 0.2, if y > 1 and y < 2.5 then 2.68 else 2.52, CF(0, y, 0), P.Iron, M.WoodPlanks))
		end
		table.insert(staves, Kit.vcyl("Lid", 0.12, 2.2, CF(0, 3.38, 0), P.TimberDark, M.WoodPlanks))
		local barrel = Kit.union("Barrel", staves, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(barrel, Kit.SOLID)
		finish("Barrel", { barrel }, { Category = "Prop", Kind = "Barrel", Footprint = 1.4, Sink = 0 })
	end

	do
		local sack = Kit.union("Sack", {
			Kit.ball("Body", 1.6, V(0, 0.6, 0), P.Canvas, M.Fabric),
			Kit.ball("Top", 1.15, V(0, 1.25, 0), P.Canvas, M.Fabric),
			Kit.vcyl("Neck", 0.5, 0.5, CF(0, 1.85, 0), P.Canvas, M.Fabric),
			Kit.vcyl("Tie", 0.14, 0.58, CF(0, 1.75, 0), P.Rope, M.Fabric),
		}, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(sack, Kit.SOLID)
		Kit.setAll(sack, Kit.NOSHADOW)
		finish("Sack", { sack }, { Category = "Prop", Kind = "Sack", Footprint = 0.9, Sink = 0.15 })

		local bed = Kit.union("Bedroll", {
			Kit.block("Mat", V(2.4, 0.22, 6), CF(0, 0.11, 0), P.CanvasGreen, M.Fabric),
			Kit.part("Roll", V(2.5, 0.9, 0.9), CF(0, 0.42, 2.6), Kit.jitter(P.CanvasGreen, rng, 0, 0, -0.2), M.Fabric, Enum.PartType.Cylinder),
			Kit.block("Blanket", V(2.3, 0.14, 3), CF(0.05, 0.25, -1.2) * CFrame.Angles(0, 0.05, 0), P.Cloth, M.Fabric),
		}, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(bed, Kit.DECOR)
		Kit.setAll(bed, Kit.NOSHADOW)
		finish("Bedroll", { bed }, { Category = "Prop", Kind = "Bedroll", Footprint = 1.6, Sink = 0 })
	end

	------------------------------------------------------------------ fences, furniture
	do
		local parts: { BasePart } = {}
		for _, x in ipairs({ -4, 4 }) do
			table.insert(parts, Kit.block("Post", V(0.55, 4.6, 0.55), CF(x, 1.8, 0) * CFrame.Angles(rng:NextNumber(-0.04, 0.04), 0, rng:NextNumber(-0.04, 0.04)), P.TimberWeathered, M.Wood))
		end
		table.insert(parts, Kit.block("Rail", V(8.8, 0.5, 0.28), CF(0, 1.5, 0.12) * CFrame.Angles(0, 0, 0.02), P.TimberWeathered, M.Wood))
		table.insert(parts, Kit.block("Rail", V(8.8, 0.5, 0.28), CF(0, 3.05, 0.12) * CFrame.Angles(0, 0, -0.025), P.TimberWeathered, M.Wood))
		local fence = Kit.union("Fence", parts, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(fence, Kit.SOLID)
		finish("Fence_Segment", { fence }, { Category = "Prop", Kind = "Fence", Footprint = 4.4, Sink = 0.1, Length = 8 })
	end

	do
		local parts: { BasePart } = {
			Kit.block("Seat", V(5.6, 0.35, 1.5), CF(0, 1.75, 0), P.Planks, M.Wood),
			Kit.block("Stretcher", V(4.2, 0.3, 0.3), CF(0, 0.7, 0), P.TimberDark, M.Wood),
		}
		for _, x in ipairs({ -2.2, 2.2 }) do
			for _, z in ipairs({ -0.5, 0.5 }) do
				table.insert(parts, Kit.rod("Leg", V(x + (if x > 0 then 0.25 else -0.25), 0, z * 1.4), V(x, 1.6, z * 0.9), 0.32, P.TimberDark, M.Wood, true))
			end
		end
		local bench = Kit.union("Bench", parts, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(bench, Kit.SOLID)
		finish("Bench", { bench }, { Category = "Prop", Kind = "Bench", Footprint = 2.9, Sink = 0 })

		local log = Kit.part("Log", V(5.2, 1.5, 1.5), CF(0, 0.6, 0), P.OakBark, M.Wood, Enum.PartType.Cylinder)
		Kit.setAll(log, Kit.SOLID)
		local ends = Kit.union("Ends", {
			Kit.part("Cap", V(0.08, 1.25, 1.25), CF(2.62, 0.6, 0), P.CutWood, M.Wood, Enum.PartType.Cylinder),
			Kit.part("Cap", V(0.08, 1.25, 1.25), CF(-2.62, 0.6, 0), P.CutWood, M.Wood, Enum.PartType.Cylinder),
		}, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(ends, Kit.DECOR)
		Kit.setAll(ends, Kit.NOSHADOW)
		finish("LogSeat", { log, ends }, { Category = "Prop", Kind = "Seat", Footprint = 2.7, Sink = 0.05 })

		local tableParts: { BasePart } = { Kit.block("Top", V(5, 0.3, 3), CF(0, 2.85, 0), P.Planks, M.Wood) }
		for _, x in ipairs({ -2.1, 2.1 }) do
			for _, z in ipairs({ -1.1, 1.1 }) do
				table.insert(tableParts, Kit.block("Leg", V(0.35, 2.7, 0.35), CF(x, 1.35, z), P.TimberDark, M.Wood))
			end
		end
		local tbl = Kit.union("Table", tableParts, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(tbl, Kit.SOLID)
		finish("Table", { tbl }, { Category = "Prop", Kind = "Table", Footprint = 2.6, Sink = 0 })

		local stoolParts: { BasePart } = { Kit.vcyl("Seat", 0.25, 1.3, CF(0, 1.8, 0), P.Planks, M.Wood) }
		for i = 1, 3 do
			local ang = i / 3 * math.pi * 2
			table.insert(stoolParts, Kit.rod("Leg", V(math.cos(ang) * 0.65, 0, math.sin(ang) * 0.65), V(math.cos(ang) * 0.35, 1.7, math.sin(ang) * 0.35), 0.18, P.TimberDark, M.Wood))
		end
		local stool = Kit.union("Stool", stoolParts, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(stool, Kit.SOLID)
		Kit.setAll(stool, Kit.NOSHADOW)
		finish("Stool", { stool }, { Category = "Prop", Kind = "Stool", Footprint = 0.8, Sink = 0 })

		local shelfParts: { BasePart } = {
			Kit.block("Side", V(0.25, 5, 1.1), CF(-1.85, 2.5, 0), P.TimberDark, M.Wood),
			Kit.block("Side", V(0.25, 5, 1.1), CF(1.85, 2.5, 0), P.TimberDark, M.Wood),
			Kit.block("Back", V(3.7, 5, 0.12), CF(0, 2.5, 0.5), P.Planks, M.Wood),
		}
		for _, y in ipairs({ 0.4, 2.0, 3.6 }) do
			table.insert(shelfParts, Kit.block("Board", V(3.6, 0.2, 1.05), CF(0, y, 0), P.Planks, M.Wood))
		end
		local shelf = Kit.union("Shelf", shelfParts, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(shelf, Kit.SOLID)
		local jars: { BasePart } = {}
		for _, spec in ipairs({ { -1.2, 2.1 }, { -0.6, 2.1 }, { 0.9, 2.1 }, { -0.9, 3.7 }, { 0.3, 3.7 }, { 1.2, 0.5 } }) do
			local h = rng:NextNumber(0.6, 1.0)
			table.insert(jars, Kit.vcyl("Jar", h, rng:NextNumber(0.4, 0.55), CF(spec[1], spec[2] + h / 2, -0.05), Kit.jitter(Color3.fromRGB(150, 130, 96), rng, 0.05, 0.2, 0.2), M.SmoothPlastic))
		end
		local jarUnion = Kit.union("Jars", jars, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(jarUnion, Kit.DECOR)
		Kit.setAll(jarUnion, Kit.NOSHADOW)
		finish("Shelf", { shelf, jarUnion }, { Category = "Prop", Kind = "Shelf", Footprint = 2, Sink = 0 })

		local pile: { BasePart } = {}
		for row = 0, 2 do
			for i = 0, 3 - row do
				local x = (i - (3 - row) / 2) * 0.72
				local y = 0.34 + row * 0.62
				local cf = CF(x, y, rng:NextNumber(-0.15, 0.15)) * CFrame.Angles(0, math.rad(90), 0)
				table.insert(pile, Kit.part("Split", V(3.2, 0.66, 0.66), cf, if (row + i) % 2 == 0 then P.CutWood else P.TimberDark, M.Wood, Enum.PartType.Cylinder))
			end
		end
		local wood = Kit.union("Firewood", pile, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(wood, Kit.SOLID)
		Kit.setAll(wood, Kit.NOSHADOW)
		finish("Firewood", { wood }, { Category = "Prop", Kind = "Firewood", Footprint = 1.8, Sink = 0 })
	end

	------------------------------------------------------------------ lights
	local function lanternParts(top: CFrame): { Instance }
		local metal = Kit.union("Frame", {
			Kit.vcyl("Hook", 0.5, 0.12, top * CF(0, -0.25, 0), P.Iron, M.Metal),
			Kit.block("Cap", V(0.95, 0.22, 0.95), top * CF(0, -0.6, 0), P.DarkMetal, M.Metal),
			Kit.block("CapTop", V(0.55, 0.2, 0.55), top * CF(0, -0.42, 0), P.DarkMetal, M.Metal),
			Kit.block("Base", V(0.9, 0.18, 0.9), top * CF(0, -1.95, 0), P.DarkMetal, M.Metal),
			Kit.block("Bar", V(0.1, 1.3, 0.1), top * CF(0.4, -1.28, 0.4), P.DarkMetal, M.Metal),
			Kit.block("Bar", V(0.1, 1.3, 0.1), top * CF(-0.4, -1.28, 0.4), P.DarkMetal, M.Metal),
			Kit.block("Bar", V(0.1, 1.3, 0.1), top * CF(0.4, -1.28, -0.4), P.DarkMetal, M.Metal),
			Kit.block("Bar", V(0.1, 1.3, 0.1), top * CF(-0.4, -1.28, -0.4), P.DarkMetal, M.Metal),
		}, { collision = Enum.CollisionFidelity.Box })
		local glass = Kit.block("Glass", V(0.7, 1.2, 0.7), top * CF(0, -1.28, 0), P.Glass, M.Glass)
		glass.Transparency = 0.45
		local flame = Kit.ball("Flame", 0.3, (top * CF(0, -1.4, 0)).Position, P.EmberGlow, M.Neon)
		local light = Instance.new("PointLight")
		light.Name = "LanternLight"
		light.Color = Color3.fromRGB(255, 176, 104)
		light.Brightness = 0.9
		light.Range = 12
		light.Shadows = false
		light.Parent = flame
		for _, p in ipairs({ metal, glass, flame }) do
			Kit.setAll(p, Kit.DECOR)
			Kit.setAll(p, Kit.NOSHADOW)
		end
		return { metal, glass, flame }
	end
	finish("Lantern", lanternParts(CFrame.identity), { Category = "Prop", Kind = "Lantern", Footprint = 0.6, Sink = 0, Hangs = true })
	do
		local post = Kit.union("Post", {
			Kit.block("Post", V(0.5, 7.6, 0.5), CF(0, 3.3, 0), P.TimberDark, M.Wood),
			Kit.block("Arm", V(0.35, 0.35, 2.2), CF(0, 7.0, -0.9), P.TimberDark, M.Wood),
			Kit.rod("Brace", V(0, 5.9, 0), V(0, 6.9, -1.0), 0.22, P.TimberDark, M.Wood, true),
		}, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(post, Kit.SOLID)
		Kit.setAll(post, Kit.NOSHADOW)
		local children: { Instance } = { post }
		for _, p in ipairs(lanternParts(CF(0, 6.82, -1.75))) do
			table.insert(children, p)
		end
		finish("LanternPost", children, { Category = "Prop", Kind = "Lantern", Footprint = 1, Sink = 0.4 })
	end

	do -- brazier
		local metal: { BasePart } = {}
		for i = 1, 3 do
			local ang = i / 3 * math.pi * 2
			table.insert(metal, Kit.rod("Leg", V(math.cos(ang) * 1.35, -0.2, math.sin(ang) * 1.35), V(math.cos(ang) * 0.6, 3.1, math.sin(ang) * 0.6), 0.26, P.DarkMetal, M.CorrodedMetal))
		end
		table.insert(metal, Kit.vcyl("Ring", 0.2, 2.2, CF(0, 1.2, 0), P.DarkMetal, M.CorrodedMetal))
		table.insert(metal, Kit.vcyl("Bowl", 0.55, 2.1, CF(0, 3.1, 0), P.DarkMetal, M.CorrodedMetal))
		for i = 1, 8 do
			local ang = i / 8 * math.pi * 2
			local pos = V(math.cos(ang) * 1.25, 3.55, math.sin(ang) * 1.25)
			local cf = CFrame.lookAt(pos, V(0, pos.Y, 0)) * CFrame.Angles(math.rad(28), 0, 0)
			table.insert(metal, Kit.block("Plate", V(1.05, 1.2, 0.16), cf, P.DarkMetal, M.CorrodedMetal))
		end
		local body = Kit.union("Brazier", metal, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(body, Kit.SOLID)
		local coals = Kit.vcyl("Coals", 0.3, 1.9, CF(0, 3.45, 0), P.EmberDeep, M.Neon)
		Kit.setAll(coals, Kit.DECOR)
		Kit.setAll(coals, Kit.NOSHADOW)
		local att = Instance.new("Attachment")
		att.Name = "FireFx"
		att.Parent = coals
		att.WorldPosition = V(0, 3.7, 0)
		Kit.fireFx(att, 0.95, { light = 0.9, range = 18, smoke = 0.6 })
		finish("Brazier", { body, coals, Kit.emitterPoint(V(0, 4, 0), "Emit_Fire") }, { Category = "Prop", Kind = "Brazier", Footprint = 1.6, Sink = 0 })
	end

	------------------------------------------------------------------ banner, notice board, signpost
	do
		local pole = Kit.union("Pole", {
			Kit.vcyl("Pole", 15, 0.5, CF(0, 6.5, 0), P.TimberDark, M.Wood),
			Kit.rod("Crossbar", V(-2.25, 13.1, -0.32), V(2.25, 13.1, -0.32), 0.3, P.TimberDark, M.Wood),
		}, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(pole, Kit.SOLID)
		local finial = Kit.ball("Finial", 0.75, V(0, 14.2, 0), P.Ember, M.Metal)
		Kit.setAll(finial, Kit.DECOR)
		local z = -0.42
		local cloth: { BasePart } = {
			Kit.block("Cloth", V(3.9, 7.4, 0.12), CF(0, 9.2, z), P.Ember, M.Fabric),
			Kit.wedge("Tail", V(0.12, 1.3, 1.95), CF(-0.975, 4.85, z) * CFrame.Angles(0, math.rad(90), math.rad(180)), P.Ember, M.Fabric),
			Kit.wedge("Tail", V(0.12, 1.3, 1.95), CF(0.975, 4.85, z) * CFrame.Angles(0, math.rad(-90), math.rad(180)), P.Ember, M.Fabric),
		}
		local clothUnion = Kit.union("Cloth", cloth, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(clothUnion, Kit.SOFT)
		-- emblem: a dark spire under a ringed sun (original mark)
		local ez = z - 0.09
		local emblem = Kit.union("Emblem", {
			Kit.block("Band", V(3.95, 0.45, 0.1), CF(0, 12.55, ez), P.Charcoal, M.Fabric),
			Kit.block("Band", V(3.95, 0.22, 0.1), CF(0, 6.0, ez), P.Charcoal, M.Fabric),
			Kit.wedge("Spire", V(0.1, 3.4, 0.75), CF(-0.375, 8.1, ez) * CFrame.Angles(0, math.rad(90), 0), P.Charcoal, M.Fabric),
			Kit.wedge("Spire", V(0.1, 3.4, 0.75), CF(0.375, 8.1, ez) * CFrame.Angles(0, math.rad(-90), 0), P.Charcoal, M.Fabric),
			Kit.part("Sun", V(0.1, 1.5, 1.5), CF(0, 10.75, ez) * CFrame.Angles(0, math.rad(90), 0), P.Charcoal, M.Fabric, Enum.PartType.Cylinder),
		}, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(emblem, Kit.SOFT)
		Kit.setAll(emblem, Kit.NOSHADOW)
		local sunCore = Kit.part("SunCore", V(0.1, 0.85, 0.85), CF(0, 10.75, ez - 0.04) * CFrame.Angles(0, math.rad(90), 0), P.EmberGlow, M.Fabric, Enum.PartType.Cylinder)
		Kit.setAll(sunCore, Kit.SOFT)
		Kit.setAll(sunCore, Kit.NOSHADOW)
		finish("Banner", { pole, finial, clothUnion, emblem, sunCore }, { Category = "Prop", Kind = "Banner", Footprint = 1.2, Sink = 0.8 })
	end

	do
		local frame = Kit.union("Frame", {
			Kit.block("Post", V(0.6, 8, 0.6), CF(-4.4, 3.5, 0), P.TimberDark, M.Wood),
			Kit.block("Post", V(0.6, 8, 0.6), CF(4.4, 3.5, 0), P.TimberDark, M.Wood),
			Kit.block("Board", V(8.2, 4.8, 0.35), CF(0, 4.4, 0), P.Planks, M.Wood),
			Kit.block("Trim", V(8.6, 0.35, 0.5), CF(0, 6.95, 0), P.TimberDark, M.Wood),
			Kit.block("Trim", V(8.6, 0.35, 0.5), CF(0, 1.85, 0), P.TimberDark, M.Wood),
			Kit.block("Roof", V(10, 0.25, 1.4), CF(0, 7.65, -0.45) * CFrame.Angles(math.rad(-22), 0, 0), P.TimberWeathered, M.Wood),
			Kit.block("Roof", V(10, 0.25, 1.4), CF(0, 7.65, 0.45) * CFrame.Angles(math.rad(22), 0, 0), P.TimberWeathered, M.Wood),
		}, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(frame, Kit.SOLID)
		local face = Kit.block("Face", V(7.8, 4.4, 0.1), CF(0, 4.4, -0.2), P.Planks, M.Wood)
		Kit.setAll(face, Kit.DECOR)
		Kit.setAll(face, Kit.NOSHADOW)

		local gui = Instance.new("SurfaceGui")
		gui.Name = "Notice"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 64
		gui.LightInfluence = 1
		gui.Brightness = 1.4
		gui.ClipsDescendants = true
		gui.Parent = face
		local paper = Instance.new("Frame")
		paper.Name = "Paper"
		paper.AnchorPoint = Vector2.new(0.5, 0.5)
		paper.Position = UDim2.fromScale(0.5, 0.5)
		paper.Size = UDim2.fromScale(0.9, 0.86)
		paper.BackgroundColor3 = Color3.fromRGB(226, 214, 186)
		paper.BorderSizePixel = 0
		paper.Rotation = -0.6
		paper.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = paper
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.05, 0)
		pad.PaddingRight = UDim.new(0.05, 0)
		pad.PaddingTop = UDim.new(0.04, 0)
		pad.Parent = paper
		local function label(name: string, text: string, y: number, h: number, font: Font, color: Color3, align: Enum.TextXAlignment): TextLabel
			local l = Instance.new("TextLabel")
			l.Name = name
			l.BackgroundTransparency = 1
			l.Position = UDim2.fromScale(0, y)
			l.Size = UDim2.fromScale(1, h)
			l.FontFace = font
			l.Text = text
			l.TextColor3 = color
			l.TextScaled = true
			l.TextWrapped = true
			l.TextXAlignment = align
			l.TextYAlignment = Enum.TextYAlignment.Top
			l.Parent = paper
			return l
		end
		label("Title", string.upper(Config.GameTitle), 0, 0.22, Theme.Fonts.Display, Theme.Colors.TextDark, Enum.TextXAlignment.Center)
		label("Subtitle", "THE WAITING GROUNDS", 0.23, 0.08, Theme.Fonts.Heading, Color3.fromRGB(150, 70, 34), Enum.TextXAlignment.Center)
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.AnchorPoint = Vector2.new(0.5, 0)
		rule.Position = UDim2.fromScale(0.5, 0.33)
		rule.Size = UDim2.new(0.5, 0, 0, 3)
		rule.BackgroundColor3 = Theme.Colors.Accent
		rule.BorderSizePixel = 0
		rule.Parent = paper
		label("Rules", table.concat({
			"- Twenty-four contenders. One walks out.",
			"- At the horn: rush the Spire for the best gear, or slip into the woods.",
			"- Hunger and thirst never rest. Drink from rivers and the lake.",
			"- Hide in bushes and trees. Listen for footsteps and the cannon.",
			"- On the second morning the border closes in. Be the last one standing.", -- PlayabilityPlan QW6
		}, "\n"), 0.38, 0.58, Theme.Fonts.Body, Color3.fromRGB(46, 42, 38), Enum.TextXAlignment.Left)
		finish("NoticeBoard", { frame, face }, { Category = "Prop", Kind = "NoticeBoard", Footprint = 4.6, Sink = 0.3 })
	end

	do -- signpost with two arrow boards (Populate writes the destinations)
		local post = Kit.vcyl("Post", 8, 0.55, CF(0, 3.4, 0), P.TimberWeathered, M.Wood)
		Kit.setAll(post, Kit.SOLID)
		local children: { Instance } = { post }
		for i, y in ipairs({ 6.3, 5.0 }) do
			-- the board is created plain (not a union) so its Front face is predictable for the SurfaceGui
			local board = Kit.block("Arm" .. i, V(3.6, 0.85, 0.18), CF(1.9, y, 0), P.Planks, M.Wood)
			Kit.setAll(board, Kit.DECOR)
			Kit.setAll(board, Kit.NOSHADOW)
			local tip = Kit.union("Tip" .. i, {
				Kit.wedge("Tip", V(0.18, 0.425, 0.6), CF(4.0, y + 0.2125, 0) * CFrame.Angles(0, math.rad(-90), 0), P.Planks, M.Wood),
				Kit.wedge("Tip", V(0.18, 0.425, 0.6), CF(4.0, y - 0.2125, 0) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(0, 0, math.pi), P.Planks, M.Wood),
			}, { collision = Enum.CollisionFidelity.Box })
			Kit.setAll(tip, Kit.DECOR)
			Kit.setAll(tip, Kit.NOSHADOW)
			table.insert(children, tip)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Text"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 48
			gui.LightInfluence = 1
			gui.Parent = board
			local l = Instance.new("TextLabel")
			l.Name = "Label"
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.FontFace = Theme.Fonts.Heading
			l.TextScaled = true
			l.TextColor3 = Color3.fromRGB(44, 36, 30)
			l.Text = ""
			l.Parent = gui
			local back = gui:Clone()
			back.Face = Enum.NormalId.Back
			back.Parent = board
			table.insert(children, board)
		end
		finish("Signpost", children, { Category = "Prop", Kind = "Signpost", Footprint = 1, Sink = 0.4 })
	end

	------------------------------------------------------------------ plinth (start pad)
	do
		local pad = Kit.block("Pad", V(4.8, 0.6, 4.8), CF(0, 1.2, 0), P.DarkMetal, M.DiamondPlate)
		Kit.setAll(pad, Kit.SOLID)
		local base = Kit.union("Base", {
			Kit.vcyl("Base", 1.6, 6.6, CF(0, 0.2, 0), P.SpireStoneDark, M.Slate),
			Kit.vcyl("Footing", 0.5, 7.4, CF(0, -0.15, 0), P.SpireStoneDark, M.Slate),
		}, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(base, Kit.SOLID)
		local trim = Kit.vcyl("Trim", 0.18, 6.85, CF(0, 0.95, 0), P.Iron, M.Metal)
		Kit.setAll(trim, Kit.DECOR)
		local chevron = Kit.union("Chevron", {
			Kit.block("Arm", V(0.22, 0.06, 1.3), CF(-0.38, 1.52, -1.55) * CFrame.Angles(0, math.rad(-38), 0), P.Ember, M.Neon),
			Kit.block("Arm", V(0.22, 0.06, 1.3), CF(0.38, 1.52, -1.55) * CFrame.Angles(0, math.rad(38), 0), P.Ember, M.Neon),
		}, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(chevron, Kit.DECOR)
		Kit.setAll(chevron, Kit.NOSHADOW)
		local plate = Kit.block("NumberPlate", V(1.7, 0.75, 0.12), CF(0, 0.3, -3.3), P.Iron, M.Metal)
		Kit.setAll(plate, Kit.DECOR)
		Kit.setAll(plate, Kit.NOSHADOW)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Number"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.LightInfluence = 1
		gui.Parent = plate
		local l = Instance.new("TextLabel")
		l.Name = "Index"
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.FontFace = Theme.Fonts.Display
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(226, 220, 208)
		l.Text = "00"
		l.Parent = gui
		-- no PrimaryPart: the pivot must stay at the base on the ground (Populate finds the pad by name)
		finish("Plinth", { pad, base, trim, chevron, plate }, { Category = "Prop", Kind = "Plinth", Footprint = 3.7, Sink = 0 })
	end

	------------------------------------------------------------------ rowboat
	do
		local hull: { BasePart } = {
			Kit.block("Bottom", V(2.4, 0.3, 6), CF(0, 0.15, 0.4), P.Timber, M.WoodPlanks),
			Kit.block("Side", V(0.25, 1.3, 6.4), CF(-1.35, 0.75, 0.3) * CFrame.Angles(0, 0, math.rad(-12)), P.Timber, M.WoodPlanks),
			Kit.block("Side", V(0.25, 1.3, 6.4), CF(1.35, 0.75, 0.3) * CFrame.Angles(0, 0, math.rad(12)), P.Timber, M.WoodPlanks),
			Kit.block("Stern", V(3, 1.3, 0.3), CF(0, 0.75, 3.55), P.TimberDark, M.WoodPlanks),
			Kit.wedge("Bow", V(1.6, 1.4, 2.2), CF(-0.8, 0.75, -3.6) * CFrame.Angles(0, 0, 0), P.Timber, M.WoodPlanks),
			Kit.wedge("Bow", V(1.6, 1.4, 2.2), CF(0.8, 0.75, -3.6), P.Timber, M.WoodPlanks),
			Kit.block("Seat", V(2.7, 0.2, 0.8), CF(0, 1.0, -0.6), P.TimberDark, M.WoodPlanks),
			Kit.block("Seat", V(2.7, 0.2, 0.8), CF(0, 1.0, 2.3), P.TimberDark, M.WoodPlanks),
			Kit.block("Gunwale", V(0.35, 0.2, 6.6), CF(-1.5, 1.42, 0.3), P.TimberDark, M.WoodPlanks),
			Kit.block("Gunwale", V(0.35, 0.2, 6.6), CF(1.5, 1.42, 0.3), P.TimberDark, M.WoodPlanks),
		}
		local boat = Kit.union("Hull", hull, { collision = Enum.CollisionFidelity.Default })
		Kit.setAll(boat, Kit.SOLID)
		local oars = Kit.union("Oars", {
			Kit.rod("Oar", V(-0.9, 1.1, -1.8), V(0.6, 1.25, 3.2), 0.16, P.CutWood, M.Wood),
			Kit.block("Blade", V(0.5, 0.1, 1.3), CF(0.75, 1.27, 3.4) * CFrame.Angles(0, 0.3, 0), P.CutWood, M.Wood),
		}, { collision = Enum.CollisionFidelity.Box })
		Kit.setAll(oars, Kit.DECOR)
		Kit.setAll(oars, Kit.NOSHADOW)
		finish("Rowboat", { boat, oars }, { Category = "Prop", Kind = "Boat", Footprint = 3.6, Sink = 0.5 })
	end
end

return Props
