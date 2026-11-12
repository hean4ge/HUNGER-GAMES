--[[
	Populate.Sites - the set pieces that are placed, not scattered.
	  core(Ctx)      the Spire (Landmarks.Spire, Persistent) with 4 niche crate markers (child Parts CrateSlot_1..4 tagged
	                 LootSpawn: Tier 3, Kind Crate, DropIn false), and the 24 realistic Plinths on the SpirePlatform's
	                 Plate_n attachments (names Plinth01..24, tag Plinth, Stand attachment, Index, PlateOffset 0.6). The v1
	                 part plinths go to ServerStorage.Archive_v1.Plinths_v1.
	  pois(Ctx)      ArenaLayout.POIs with ArenaLayout.POIKits: HunterCabin (+ woodpile, barrels, paddock, sign),
	                 Watchtower (+ crate pile, unlit deck lantern), Footbridge (X along Crossings.GorgeFootbridge.direction,
	                 pivot at the rim height), the gorge log, stepping stones on the two stepping crossings, a CaveMouth on
	                 each cave (CaveEntrance on Caves[i].mouth, front out of the hill; bushes screen the CreekCave, a cold
	                 camp inside the LedgeCave), the falls pool rim rocks, the lake island, the overlook ledge, the giant oak
	                 (OakA x1.6, climbable), the field boulder (BoulderD x2.4) and the marsh dead stand.
	  camps(Ctx)     the 6 Campsite POIs: Tent, Campfire, 2 LogBenches, Bedroll, Woodpile, a Lantern on the tent pole; tier-2
	                 camps add a Barrel and a CratePile, tier-1 camps a broken fence. Abandoned: fires and lanterns are cold
	                 except two smouldering fires (dim, unshadowed). The layout turns until no piece sits on a loot marker.
	  cliffs(Ctx)    CliffFace pieces skinned onto the escarpment face, the gorge walls and the falls bowl (the mean front
	                 surface 1 stud proud of the terrain face, base sunk 2.5 x scale), RockOutcrops on the escarpment rim.
	                 Never over a cave mouth, a crossing, a trail or the falling water.
	  ambience(Ctx)  AmbientEmitters (workspace.Arena.Ambience): Emit_River along the river, Emit_Waterfall at the falls,
	                 Emit_Frogs at marsh pools, Emit_Wind on the heights, Emit_Fire at the smouldering camp fires.
]]
local Sites = {}

local rad, sin, cos, sqrt, min, max, floor, abs = math.rad, math.sin, math.cos, math.sqrt, math.min, math.max, math.floor, math.abs
local V3 = Vector3.new
local TAU = math.pi * 2
local PERSISTENT = Enum.ModelStreamingMode.Persistent
-- The footbridge's end-frame logs (posts, cross logs and braces: one mesh) are stretched upward by this factor about
-- their own bottom, so the cross logs (deck + about 4 at scale 1) clear a standing contender (POI.Bridge).
Sites.BRIDGE_FRAME_STRETCH = 1.65
-- the hunter's cabin stands this far behind the POI centre (its porch clear of the Cabin trail's end)
Sites.CABIN_BACK = 4.6
-- the footbridge sits this much under the crossing's rim height, so its end sills meet the rims nearly flush (a 1.5-
-- stud step up onto the bridge before)
Sites.BRIDGE_DROP = 1.2
-- at most this many coverage pieces (cliffs, step 5), and how far their foot stands in front of the face
Sites.COVER_BUDGET = 150
Sites.TOUCHUP_BUDGET = 60
Sites.COVER_PROUD = 1.2

local function flat(v: Vector3): Vector3
	return V3(v.X, 0, v.Z)
end

local function dirOf(degrees: number): Vector3
	local a = rad(degrees)
	return V3(sin(a), 0, -cos(a))
end

-- an upright frame at pos whose front (LookVector = the templates' -Z) faces the horizontal direction dir
local function facing(pos: Vector3, dir: Vector3): CFrame
	local d = flat(dir)
	if d.Magnitude < 1e-4 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + d.Unit)
end

local function yawFacing(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

-- lowest, highest and mean terrain height under a template's footprint at cf (scaled, shrunk by `inset`)
local function footprint(Ctx, name: string, cf: CFrame, scale: number?, inset: number?)
	local info = Ctx.info(name)
	if not info then
		return nil
	end
	local s = scale or 1
	local k = inset or 0.9
	local cx, cz = (info.bmin.X + info.bmax.X) / 2 * s, (info.bmin.Z + info.bmax.Z) / 2 * s
	local hx, hz = (info.bmax.X - info.bmin.X) / 2 * s * k, (info.bmax.Z - info.bmin.Z) / 2 * s * k
	local lo, hi, sum, n = math.huge, -math.huge, 0, 0
	for _, q in ipairs({ { 0, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local p = cf * V3(cx + q[1] * hx, 0, cz + q[2] * hz)
		local y = Ctx.height(p.X, p.Z)
		if y then
			lo, hi, sum, n = min(lo, y), max(hi, y), sum + y, n + 1
		end
	end
	if n == 0 then
		return nil
	end
	return lo, hi, sum / n
end

local function atY(cf: CFrame, y: number): CFrame
	return cf + V3(0, y - cf.Position.Y, 0)
end

-- `name` upright at frame * (x, 0, z) turned yawDeg, its pivot on the lowest ground under its footprint minus sink
-- (no side floats). opts: scale, sink, inset, plus Ctx.spawn options. Sites keep the template attributes.
local function piece(Ctx, name: string, frame: CFrame, x: number, z: number, yawDeg: number, parent: Instance, opts: any?)
	local o = opts or {}
	local p = frame * V3(x, 0, z)
	local ai = Ctx.Layout.AssetInfo[name]
	if Ctx.lootNear(p.X, p.Z, (if ai then ai.r else 2) * (o.scale or 1) * 0.8) then
		return nil -- never on a loot marker
	end
	local cf = CFrame.new(p) * frame.Rotation * CFrame.Angles(0, rad(yawDeg), 0)
	local lo = footprint(Ctx, name, cf, o.scale, o.inset)
	if not lo then
		return nil
	end
	cf = atY(cf, lo - (o.sink or 0.05))
	o.keep = true
	return Ctx.spawn(name, cf, parent, o)
end

-- a tree upright at p, its pivot on the lowest ground round the trunk (radius r) minus sink
local function tree(Ctx, name: string, p: Vector3, scale: number, yaw: number, parent: Instance, r: number?, sink: number?)
	local rr = (r or 1.2) * scale
	if Ctx.lootNear(p.X, p.Z, rr + 0.5) then
		return nil
	end
	local lo = Ctx.height(p.X, p.Z)
	if not lo then
		return nil
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local y = Ctx.height(p.X + cos(a) * rr, p.Z + sin(a) * rr)
		if y and y < lo then
			lo = y
		end
	end
	return Ctx.spawn(name, CFrame.new(p.X, lo - (sink or 0.15), p.Z) * CFrame.Angles(0, yaw, 0), parent, { keep = true, scale = scale })
end

-- a ground piece following the slope (rocks, moss, logs): tilt 0..1 toward the ground normal, sunk `sink` studs
local function onGround(Ctx, name: string, p: Vector3, scale: number, yaw: number, tilt: number, sink: number, parent: Instance)
	local ai = Ctx.Layout.AssetInfo[name]
	if Ctx.lootNear(p.X, p.Z, (if ai then ai.r else 2) * scale * 0.8) then
		return nil
	end
	local y, n = Ctx.ground(p.X, p.Z)
	if not y then
		return nil
	end
	local m = Ctx.spawn(name, Ctx.upFrame(V3(p.X, y - sink, p.Z), Vector3.yAxis:Lerp(n, tilt), yaw), parent, { keep = true, scale = scale })
	if m and name ~= "MossPatch" and name ~= "MushroomsA" then
		-- the underside rests on the ground: no side of a rock or log hangs in the air
		Ctx.seat(m, { share = 0.5, tol = 0.3, maxDrop = 6 })
	end
	return m
end

-- Puts a fire or lantern out (cold), or leaves it smouldering (a dim, unshadowed glow).
function Sites.douse(m: Instance?, smoulder: boolean?)
	if not m then
		return
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Light") then
			if smoulder then
				d.Shadows = false
				d.Brightness = 0.6
				d.Range = 10
				d.Color = Color3.fromRGB(255, 122, 64)
			else
				d.Enabled = false
			end
		elseif d:IsA("BasePart") and string.find(d.Name, "Ember", 1, true) then
			if smoulder then
				d.Color = Color3.fromRGB(150, 58, 24)
			else
				d.Material = Enum.Material.Slate
				d.Color = Color3.fromRGB(46, 42, 39)
			end
		end
	end
end

-- local lights: shadows off (the playbook budget is 4-6 shadowed lights in view)
local function noShadows(m: Instance?)
	if m then
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Light") then
				d.Shadows = false
			end
		end
	end
end

-------------------------------------------------------------------------------- core: the Spire and the plinths
function Sites.core(Ctx): string
	local L = Ctx.Layout
	local arena = Ctx.arena()
	local landmarks = Ctx.out("Landmarks")
	local old = landmarks:FindFirstChild("Spire")
	if old then
		old:Destroy()
	end
	local c = L.Center
	local spire = Ctx.spawn("Spire", CFrame.new(c.X, L.PlazaY, c.Z), landmarks, { keep = true, keepTouch = true, streaming = PERSISTENT })
	if not spire then
		return "FAILED: no Spire template"
	end
	spire:SetAttribute("PlacedBy", Ctx.SOURCE)
	local pp = spire.PrimaryPart
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { spire }
	local slots, notes = 0, {}
	for i = 1, 4 do
		local att = pp and pp:FindFirstChild("CrateSlot_" .. i)
		if att and att:IsA("Attachment") then
			local base = att.WorldCFrame
			-- the niche floor (the Spire's collider) under the slot: the crate's bottom rests on it
			local hit = workspace:Raycast(base.Position + V3(0, 2, 0), V3(0, -5, 0), params)
			if hit then
				table.insert(notes, string.format("%d:%+.2f", i, hit.Position.Y - base.Position.Y))
				base = base + V3(0, hit.Position.Y - base.Position.Y, 0)
			else
				table.insert(notes, i .. ":no floor hit")
			end
			local m = Instance.new("Part")
			m.Name = "CrateSlot_" .. i
			m.Size = V3(4, 2.2, 2.6)
			m.CFrame = base * CFrame.new(0, 1.1, 0)
			m.Anchored = true
			m.CanCollide = false
			m.CanQuery = false
			m.CanTouch = false
			m.CastShadow = false
			m.Transparency = 1
			m.Color = Color3.fromRGB(232, 163, 59)
			m:SetAttribute("Tier", 3)
			m:SetAttribute("Kind", "Crate")
			m:SetAttribute("Source", "Populate:Spire")
			m:SetAttribute("DropIn", false)
			m:AddTag("LootSpawn")
			m.Parent = spire
			slots += 1
		end
	end
	-- the plinths
	local plinths = Ctx.folder(arena, "Plinths")
	local archived = 0
	for _, ch in ipairs(plinths:GetChildren()) do
		if ch:GetAttribute("PlacedBy") == Ctx.SOURCE then
			ch:Destroy()
		else
			Ctx.archive(ch, "Plinths_v1")
			archived += 1
		end
	end
	local platform = arena:FindFirstChild("SpirePlatform")
	local ppf = platform and (platform.PrimaryPart or platform:FindFirstChildWhichIsA("BasePart"))
	local offset = L.PlateTube.platformTop or 0.6
	local placed, fallback = 0, 0
	for i = 1, L.PlinthCount do
		local att = ppf and ppf:FindFirstChild("Plate_" .. i)
		local cf
		if att and att:IsA("Attachment") then
			cf = att.WorldCFrame
		else
			cf = L.Plates[i] + V3(0, offset, 0)
			fallback += 1
		end
		local m = Ctx.spawn("Plinth", cf, nil, { keep = true, keepTouch = true, streaming = PERSISTENT, name = string.format("Plinth%02d", i) })
		if m then
			m:SetAttribute("Index", i)
			m:SetAttribute("PlateOffset", offset)
			m:SetAttribute("PlacedBy", Ctx.SOURCE)
			if not m:HasTag("Plinth") then
				m:AddTag("Plinth")
			end
			-- PlateCollar: a thin rusted-iron disc just under the deck surface. The deck openings (2.6-3.7 studs from
			-- the plate axis) are wider than the plinth (half-width 2.76), so without it you look down a dark gap beside
			-- every raised plate. Its top sits 0.1 below the pivot (the plate's raised height); it moves with the plinth.
			local collar = Instance.new("Part")
			collar.Name = "PlateCollar"
			collar.Shape = Enum.PartType.Cylinder
			collar.Size = V3(0.3, 7.5, 7.5)
			collar.CFrame = CFrame.new(m:GetPivot().Position + V3(0, -0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
			collar.Material = Enum.Material.CorrodedMetal
			collar.Color = Color3.fromRGB(64, 44, 36)
			collar.Anchored = true
			collar.CanCollide = false
			collar.CanQuery = false
			collar.CanTouch = false
			collar.CastShadow = false
			collar.Massless = true
			collar.Parent = m
			m.Parent = plinths
			placed += 1
		end
	end
	return string.format("Spire + %d niche crate markers (niche floor vs slot: %s); %d realistic Plinths (%d v1 plinths archived%s)",
		slots, table.concat(notes, " "), placed, archived, if fallback > 0 then (", " .. fallback .. " placed from Layout.Plates") else "")
end

-------------------------------------------------------------------------------- POIs
local POI = {}

POI.Cabin = function(Ctx, poi, g, rng)
	local dir = dirOf(poi.facing or 0)
	-- the Cabin trail ends 8 studs in front of the POI centre, which put its last steps into the porch railing: the
	-- cabin stands Sites.CABIN_BACK studs further back (the ground there is as level), so the trail ends in front of
	-- the porch
	local cf = facing(poi.position, dir) * CFrame.new(0, 0, Sites.CABIN_BACK)
	local lo, hi = footprint(Ctx, "HunterCabin", cf, 1, 0.85)
	if not lo then
		return "no ground"
	end
	-- the floor is 1.0 above the pivot: keep the highest ground under it, let the low side sit on its sill logs
	local y = max(lo, hi - 0.8)
	local frame = atY(cf, y)
	local cabin = Ctx.spawn("HunterCabin", frame, g, { keep = true, keepTouch = true })
	noShadows(cabin)
	-- kit: woodpile on the east (chimney, +X) gable, barrels beside the porch, a small paddock behind, a sign by the trail
	piece(Ctx, "Woodpile", cf, 16.0, 4.6, 90, g)
	piece(Ctx, "Barrel", cf, -14.6, -9.4, rng:NextNumber(0, 360), g)
	piece(Ctx, "Barrel", cf, -15.0, -6.9, rng:NextNumber(0, 360), g)
	for k, f in ipairs({ { -19.6, -1.5, 90 }, { -19.6, 6.9, 92 }, { -15.4, 11.1, 2 }, { -7.0, 11.4, -4 } }) do
		if k <= 3 or rng:NextNumber() < 0.6 then
			piece(Ctx, "FenceSegment", cf, f[1], f[2], f[3] + rng:NextNumber(-3, 3), g)
		end
	end
	piece(Ctx, "Sign", cf, 7.5, -18.5, 12, g)
	return string.format("cabin pivot %.1f (ground under it %.1f..%.1f)", y, lo, hi)
end

POI.Watchtower = function(Ctx, poi, g, rng)
	local cf = facing(poi.position, dirOf(poi.facing or 0))
	local lo, hi = footprint(Ctx, "Watchtower", cf, 1, 0.9)
	if not lo then
		return "no ground"
	end
	local frame = atY(cf, lo - 0.15) -- the legs go into the ground on the high side, none floats
	local tower = Ctx.spawn("Watchtower", frame, g, { keep = true, keepTouch = true })
	piece(Ctx, "CratePile", cf, 5.0, -10.8, rng:NextNumber(-20, 20), g)
	local note = ""
	if tower then
		-- an unlit lantern on the deck
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { tower }
		local top = tower:FindFirstChild("LadderTop", true)
		local spot = frame * V3(-4.3, 0, -4.3)
		local fromY = (if top then top.WorldPosition.Y else frame.Position.Y + 22) + 3
		local hit = workspace:Raycast(V3(spot.X, fromY, spot.Z), V3(0, -6, 0), params)
		if hit then
			local lantern = Ctx.spawn("Lantern", CFrame.new(hit.Position) * frame.Rotation, g, { keep = true })
			Sites.douse(lantern, false)
		end
		note = string.format("tower ground %.1f..%.1f under the legs", lo, hi)
	end
	return note
end

POI.Bridge = function(Ctx, poi, g, rng)
	local L = Ctx.Layout
	local c = nil
	for _, x in ipairs(L.Crossings) do
		if x.name == poi.crossing then
			c = x
		end
	end
	if not c then
		return "no crossing"
	end
	local along = flat(c.direction).Unit
	local cf = CFrame.fromMatrix(c.position - V3(0, Sites.BRIDGE_DROP, 0), along, Vector3.yAxis)
	local bridge = Ctx.spawn("Footbridge", cf, g, { keep = true, keepTouch = true })
	local notes = {}
	-- The end frames' cross logs hang at head height (about deck + 4: a contender can't walk under them). Stretch the
	-- frame logs (posts, cross logs and braces: one mesh) upward about their own bottom so the cross logs clear a
	-- standing contender; the deck, the planks and the ropes are untouched.
	local frame = bridge and bridge:FindFirstChild("Footbridge_Logs", true)
	if frame and frame:IsA("BasePart") then
		local k = Sites.BRIDGE_FRAME_STRETCH
		local bottom = frame.CFrame * CFrame.new(0, -frame.Size.Y / 2, 0)
		frame.Size = V3(frame.Size.X, frame.Size.Y * k, frame.Size.Z)
		frame.CFrame = bottom * CFrame.new(0, frame.Size.Y / 2, 0)
		table.insert(notes, string.format("frame logs stretched x%.2f", k))
	end
	for _, n in ipairs({ "EndA", "EndB" }) do
		local a = bridge and bridge:FindFirstChild(n, true)
		if a then
			local gy = Ctx.height(a.WorldPosition.X, a.WorldPosition.Z)
			table.insert(notes, string.format("%s deck %.2f above the rim", n, a.WorldPosition.Y - (gy or a.WorldPosition.Y)))
		end
	end
	local endA = c.position - along * 26 + V3(-along.Z, 0, along.X) * 4.5
	piece(Ctx, "Sign", facing(endA, -along), 0, 0, 0, g)
	return table.concat(notes, ", ")
end

POI.Cave = function(Ctx, poi, g, rng)
	local L = Ctx.Layout
	local cave = L.Caves[poi.cave or 0]
	if not cave then
		return "no cave"
	end
	local m, q = cave.path[1], cave.path[2]
	local out = flat(m - q).Unit
	local mouth = Ctx.spawn("CaveMouth", facing(m, out), nil, { keep = true, keepTouch = true })
	if not mouth then
		return "no CaveMouth template"
	end
	-- its CaveEntrance attachment goes exactly on the cave mouth (floor level)
	local e = mouth:FindFirstChild("CaveEntrance", true)
	if e and e:IsA("Attachment") then
		mouth:PivotTo(mouth:GetPivot() + (m - e.WorldPosition))
	end
	mouth.Parent = g
	local side = V3(-out.Z, 0, out.X)
	if poi.name == "CreekCave" then
		-- bushes and ferns screen it from the creek trail, 6-12 studs to the sides
		for _, sgn in ipairs({ -1, 1 }) do
			for k, d in ipairs({ 8, 11 }) do
				local p = flat(m) + side * (sgn * (d + rng:NextNumber(-1, 1))) + out * rng:NextNumber(1, 4)
				local y = Ctx.height(p.X, p.Z)
				if y then
					Ctx.spawn(if k == 1 then "BushA" else "FernB", CFrame.new(p.X, y - 0.05, p.Z) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), g, { keep = true, scale = rng:NextNumber(0.95, 1.2) })
				end
			end
		end
	elseif poi.name == "LedgeCave" then
		-- an old camp in the chamber
		local ch = cave.chamber
		local fy = Ctx.heightBelow(V3(ch.X, ch.Y + 4, ch.Z), 10) or ch.Y
		local fire = Ctx.spawn("Campfire", CFrame.new(ch.X, fy - 0.05, ch.Z), g, { keep = true })
		Sites.douse(fire, false)
		local bp = flat(ch) + side * 4.5
		local by = Ctx.heightBelow(V3(bp.X, ch.Y + 4, bp.Z), 10) or fy
		Ctx.spawn("Bedroll", facing(V3(bp.X, by - 0.02, bp.Z), out), g, { keep = true })
	end
	return ""
end

POI.Waterfall = function(Ctx, poi, g, rng)
	local L = Ctx.Layout
	local pc, pr = L.River.pool.center, L.River.pool.radius
	local toFall = flat(L.River.fall.base - pc).Unit
	local n = 0
	for k = 0, 13 do
		local a = rad(k * (360 / 14) + rng:NextNumber(-8, 8))
		local d = V3(sin(a), 0, -cos(a))
		if d:Dot(toFall) < cos(rad(38)) then
			local p = flat(pc) + d * (pr + rng:NextNumber(0.5, 4.5))
			local y, nrm, _, wy, depth = Ctx.ground(p.X, p.Z)
			if y and (not wy or depth < 1.6) then
				local name = if k % 3 == 0 then "RiverStones" elseif k % 3 == 1 then "BoulderB" else "BoulderC"
				local s = rng:NextNumber(0.85, 1.25)
				local rock = Ctx.spawn(name, Ctx.upFrame(V3(p.X, y - 0.35 * s, p.Z), Vector3.yAxis:Lerp(nrm, 0.6), rng:NextNumber(0, TAU)), g, { keep = true, scale = s })
				if rock then
					-- the rim is steep: lower the rock until its underside rests on the bank (or the pool bed)
					Ctx.seat(rock, { share = 0.5, tol = 0.3, maxDrop = 8 })
				end
				n += 1
				if rock and name ~= "RiverStones" and k % 2 == 0 then
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Include
					params.FilterDescendantsInstances = { rock }
					local hit = workspace:Raycast(V3(p.X, y + 20, p.Z), V3(0, -25, 0), params)
					if hit then
						Ctx.spawn("MossPatch", Ctx.upFrame(hit.Position - V3(0, 0.06, 0), hit.Normal, rng:NextNumber(0, TAU)), g, { keep = true, scale = 0.55 * s })
					end
				end
			end
		end
	end
	return n .. " rim rocks"
end

POI.Island = function(Ctx, poi, g, rng)
	local L = Ctx.Layout
	local c = flat(poi.position)
	local birches = 0
	-- two birches where their whole crown keeps the island's crates in plain sight (crowns may lean out over the water)
	for _, o in ipairs({ { 3.5, -2.0 }, { -4.2, 3.6 }, { 5.5, 4.5 }, { -2.5, -6.0 }, { 7.0, -1.0 }, { -6.5, 0.5 }, { 9, 6 }, { -9, -6 }, { 10, -5 }, { -8, 8 }, { 2, 11 }, { -2, -11 } }) do
		if birches < 2 then
			local yaw = rng:NextNumber(0, TAU)
			local s = rng:NextNumber(0.8, 0.95)
			local p = c + V3(o[1], 0, o[2])
			local _, _, _, wy = Ctx.ground(p.X, p.Z)
			if not wy and Ctx.lootClear("BirchA", CFrame.new(p) * CFrame.Angles(0, yaw, 0), s) and tree(Ctx, "BirchA", p, s, yaw, g, 0.8, 0.2) then
				birches += 1
			end
		end
	end
	onGround(Ctx, "BoulderC", c + V3(-6.5, 0, -5.0), rng:NextNumber(0.9, 1.15), rng:NextNumber(0, TAU), 0.6, 0.5, g)
	-- a flat rock at the waterline on the side facing the meadow
	local toward = (-c).Unit
	for r = 7, 20, 1 do
		local p = c + toward * r
		local y, n, _, wy = Ctx.ground(p.X, p.Z)
		if y and (wy or y < L.LakeLevel + 0.4) then
			Ctx.spawn("RockFlat", Ctx.upFrame(V3(p.X, y - 0.35, p.Z), Vector3.yAxis:Lerp(n, 0.7), yawFacing(toward)), g, { keep = true })
			break
		end
	end
	return ""
end

POI.Overlook = function(Ctx, poi, g, rng)
	local L = Ctx.Layout
	local c = flat(poi.position)
	local best, bd = nil, math.huge
	for _, smp in ipairs(L.River.samples) do
		if smp.gorge == 1 or smp.fall then
			local d = (V3(smp.x, 0, smp.z) - c).Magnitude
			if d < bd then
				bd, best = d, smp
			end
		end
	end
	local dir = if best then (V3(best.x, 0, best.z) - c).Unit else V3(1, 0, 0)
	local side = V3(-dir.Z, 0, dir.X)
	-- the Overlook trail ends here: each piece takes the first spot that leaves the trail's walking space clear
	local function place(name: string, spots, scale: number, sink: number): Model?
		for _, o in ipairs(spots) do
			local m = onGround(Ctx, name, c + dir * o[1] + side * o[2], scale, yawFacing(dir), 0.5, sink, g)
			if m and not Ctx.blocksTrail(m) then
				return m
			elseif m then
				m:Destroy()
			end
		end
		return nil
	end
	local ledge = place("RockFlat", { { 3, 0 }, { 3, 4 }, { 3, -4 }, { 5, 0 } }, 1.1, 0.45)
	local crop = place("RockOutcrop", { { -7.5, 0 }, { -10, 4 }, { -10, -4 }, { -13, 0 }, { -7.5, 8 }, { -7.5, -8 } }, 1.0, 1.1)
	return (if ledge then "ledge" else "no ledge") .. ", " .. (if crop then "outcrop" else "no outcrop")
end

POI.GiantTree = function(Ctx, poi, g, rng)
	local c = flat(poi.position)
	local oak = tree(Ctx, "OakA", c, 1.6, rng:NextNumber(0, TAU), g, 2.0, 0.3)
	for k = 1, 7 do
		local a = rng:NextNumber(0, TAU)
		local p = c + V3(cos(a), 0, sin(a)) * rng:NextNumber(4.5, 8)
		onGround(Ctx, if k <= 4 then "MossPatch" else "MushroomsA", p, rng:NextNumber(0.8, 1.2), rng:NextNumber(0, TAU), 1, 0.04, g)
	end
	return if oak then "giant OakA x1.6 (Climbable)" else "no oak"
end

POI.Boulder = function(Ctx, poi, g, rng)
	-- the lone boulder stands beside the trails that meet here, never on them
	local s = 2.4
	local rr = 5.5 * s * 0.85
	local c = flat(poi.position)
	local best, bestD = c, -math.huge
	for k = 0, 15 do
		for _, d in ipairs({ 0, 4, 8, 12, 16 }) do
			local a = k * TAU / 16
			local p = c + V3(cos(a), 0, sin(a)) * d
			local td = Ctx.trailDistance(p.X, p.Z)
			if td - rr > bestD and not Ctx.lootNear(p.X, p.Z, rr) then
				best, bestD = p, td - rr
			end
		end
		if bestD >= 2.5 then
			break
		end
	end
	onGround(Ctx, "BoulderD", best, s, rng:NextNumber(0, TAU), 0.3, 1.5, g)
	return string.format("BoulderD x2.4, %.1f studs clear of the trails", bestD)
end

POI.DeadStand = function(Ctx, poi, g, rng)
	local L = Ctx.Layout
	local c = flat(poi.position)
	local snags, logs, reeds = 0, 0, 0
	local spots = {}
	local tries = 0
	while snags < 10 and tries < 120 do
		tries += 1
		local a, r = rng:NextNumber(0, TAU), poi.radius * sqrt(rng:NextNumber())
		local p = c + V3(cos(a), 0, sin(a)) * r
		local ok = true
		for _, q in ipairs(spots) do
			if (q - p).Magnitude < 6 then
				ok = false
			end
		end
		local _, _, _, wy, depth = Ctx.ground(p.X, p.Z)
		if ok and (not wy or depth < 1.0) then
			if tree(Ctx, if rng:NextNumber() < 0.55 then "SnagA" else "SnagB", p, rng:NextNumber(0.85, 1.2), rng:NextNumber(0, TAU), g, 0.9, 0.4) then
				snags += 1
				table.insert(spots, p)
			end
		end
	end
	for _ = 1, 2 do
		local a, r = rng:NextNumber(0, TAU), rng:NextNumber(4, poi.radius - 6)
		local p = c + V3(cos(a), 0, sin(a)) * r
		if onGround(Ctx, "FallenLogB", p, rng:NextNumber(0.9, 1.1), rng:NextNumber(0, TAU), 1, 0.8, g) then
			logs += 1
		end
	end
	tries = 0
	while reeds < 10 and tries < 80 do
		tries += 1
		local a, r = rng:NextNumber(0, TAU), rng:NextNumber(3, poi.radius + 6)
		local p = c + V3(cos(a), 0, sin(a)) * r
		local y, _, _, wy, depth = Ctx.ground(p.X, p.Z)
		if y and wy and depth > 0.1 and depth < 1.5 then
			Ctx.spawn("ReedsA", CFrame.new(p.X, y - 0.6, p.Z) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), g, { keep = true, scale = rng:NextNumber(0.85, 1.2) })
			reeds += 1
		end
	end
	return string.format("%d snags, %d logs, %d reeds", snags, logs, reeds)
end

function Sites.pois(Ctx): string
	local L = Ctx.Layout
	local root = Ctx.out("POIs")
	Ctx.clear(root)
	local rng = Random.new(Ctx.Seed * 31 + 17)
	local notes = {}
	for _, poi in ipairs(L.POIs) do
		local builder = POI[poi.kind]
		if builder then
			Ctx.status("pois: " .. poi.name)
			local g = Ctx.folder(root, poi.name)
			local ok, res = pcall(builder, Ctx, poi, g, rng)
			table.insert(notes, poi.name .. (if ok then (if res and res ~= "" then (" (" .. tostring(res) .. ")") else "") else (" FAILED " .. tostring(res))))
			Ctx.yield()
		end
	end
	-- the crossings that are not POIs: the gorge log and the stepping stones
	for _, c in ipairs(L.Crossings) do
		local along = flat(c.direction).Unit
		if c.kind == "Log" then
			local g = Ctx.folder(root, c.name)
			local s = 1.18
			local cf = CFrame.fromMatrix(c.position - V3(0, 0.9, 0), along, Vector3.yAxis)
			local log = Ctx.spawn("FallenLogB", cf, g, { keep = true, scale = s })
			table.insert(notes, c.name .. (if log then " (FallenLogB x1.18 across the gorge)" else " FAILED"))
		elseif c.kind == "Stepping" then
			local g = Ctx.folder(root, c.name)
			local n = max(3, floor(c.span / 2.4 + 0.5))
			local placed = 0
			for k = 1, n do
				local t = (k - (n + 1) / 2) * ((c.span + 2) / n)
				local p = flat(c.position) + along * t + V3(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4))
				local y, _, _, wy = Ctx.ground(p.X, p.Z)
				if y then
					local level = wy or c.position.Y
					local s = rng:NextNumber(0.72, 0.86)
					-- the stone's top (BoulderB 3.13 x scale) about half a stud above the water
					local py = min(level + 0.5 - 3.13 * s, y)
					Ctx.spawn("BoulderB", CFrame.new(p.X, py, p.Z) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), g, { keep = true, scale = s })
					placed += 1
				end
			end
			table.insert(notes, string.format("%s (%d stepping stones)", c.name, placed))
		end
	end
	-- a landmark 8 studs from each runner's cache (the rules owner's `landmark` suggestion), out and to the side of it,
	-- so the cache's crate and pole stay in sight of the plates and its 6-stud clearing stays empty
	if type(L.RunnerCaches) == "table" then
		local g = Ctx.folder(root, "RunnerCacheLandmarks")
		local placed = 0
		for i, c in ipairs(L.RunnerCaches) do
			local wanted = if type(c) == "table" then c.landmark else nil
			local p = if type(c) == "table" then c.position else nil
			-- the rules owner's landmark first; where it finds no spot that keeps the clearings free, a boulder or a stump
			-- (the kinds its note allows)
			local done = false
			for _, name in ipairs(if type(wanted) == "string" then { wanted, "BoulderC", "StumpA" } else {}) do
			if not done and typeof(p) == "Vector3" and Ctx.template(name) then
				local out = flat(p).Unit
				local q, dir = nil, nil
				-- far enough that its body (an oak's low limbs spread ~6) stays outside the 6.5-stud clearing
				-- (a log lies across the line, so its half length must clear the cache's crate clearing too: 12.5 out)
				local body = if name == "OakA" then 6 elseif name == "FallenLogA" or name == "FallenLogB" then 6 else (L.AssetInfo[name] and L.AssetInfo[name].r or 2) * 1.25
				local dist = math.clamp(6.5 + body, 8, 12.5)
				local isLog = name == "FallenLogA" or name == "FallenLogB"
				local isTree = name == "OakA" or name == "BirchA" or name == "BirchB" or name == "SnagA" or name == "SnagB" or name == "PineA"
				local sc = if name == "OakA" then 0.85 elseif isLog then 0.8 elseif isTree then 1.05 else 1.25
				-- out and to the side first (the plates look in along the radial line), then round the cache and further out:
				-- the first spot whose whole footprint (a crown too) keeps every loot clearing free, tested at the yaw it
				-- will stand at
				local yaw0 = rng:NextNumber(0, TAU)
				for _, more in ipairs({ 0, 3, 6, 9 }) do
					for _, ang in ipairs({ 40, 70, 100, 140 }) do
						for _, side in ipairs({ if i % 2 == 0 then 1 else -1, if i % 2 == 0 then -1 else 1 }) do
							if not q then
								local d = CFrame.Angles(0, rad(ang * side), 0):VectorToWorldSpace(out)
								local cand = flat(p) + d * (dist + more)
								local test = CFrame.new(cand) * CFrame.Angles(0, if isLog then yawFacing(d) else yaw0, 0)
								if Ctx.trailDistance(cand.X, cand.Z) > 4.5 and Ctx.lootClear(name, test, sc, 0.8) then
									q, dir = cand, d
								end
							end
						end
					end
				end
				if q and dir then
					local yaw = yaw0
					local m
					if isTree then
						m = tree(Ctx, name, q, if name == "OakA" then 0.85 else rng:NextNumber(0.95, 1.05), yaw, g, 1.0, 0.15)
					elseif name == "FallenLogA" or name == "FallenLogB" then
						-- lying across the line from the cache, so its length doesn't point at the clearing (scale 0.8 keeps both
						-- ends outside the cache's crate clearing)
						m = onGround(Ctx, name, q, 0.8, yawFacing(dir), 1, 0.3, g)
					elseif string.find(name, "Stump", 1, true) then
						m = onGround(Ctx, name, q, rng:NextNumber(1.0, 1.15), yaw, 0.3, 0.3, g)
					else
						local s = rng:NextNumber(1.05, 1.25)
						m = onGround(Ctx, name, q, s, yaw, 0.6, 0.35 * s, g)
					end
					if m then
						m.Name = name
						m:SetAttribute("RunnerCache", if type(c.name) == "string" then c.name else i)
						if name ~= wanted then
							m:SetAttribute("InsteadOf", wanted)
						end
						placed += 1
						done = true
					end
				end
			end
			end
		end
		table.insert(notes, string.format("RunnerCacheLandmarks (%d of %d)", placed, #L.RunnerCaches))
	end
	return table.concat(notes, "; ")
end

-------------------------------------------------------------------------------- camps
-- name, x, z (camp frame: -Z = toward the arena centre), yaw (degrees), tier filter
local CAMP_KIT = {
	{ "Campfire", 0, 0, 0 },
	{ "Tent", 0, 8.4, 0 },
	{ "LogBench", -5.0, -0.6, 90 },
	{ "LogBench", 2.8, -5.0, 205 },
	{ "Bedroll", 5.6, 6.8, 6 },
	{ "Woodpile", -7.2, 6.2, 70 },
	{ "Barrel", 6.6, -2.6, 0, tier = 2 },
	{ "CratePile", -7.8, -5.8, 25, tier = 2 },
	{ "FenceSegment", 10.4, 2.5, 82, tier = 1 },
	{ "FenceSegment", 8.0, 10.8, 28, tier = 1 },
}
Sites.SMOULDER = { CampNorth = true, CampWest = true }

function Sites.camps(Ctx): string
	local L = Ctx.Layout
	local root = Ctx.out("Camps")
	Ctx.clear(root)
	local rng = Random.new(Ctx.Seed * 53 + 3)
	local markers = {}
	for _, m in ipairs(Ctx.lootMarkers()) do
		table.insert(markers, { p = flat(m.Position), crate = m:GetAttribute("Kind") == "Crate" })
	end
	local notes = {}
	for _, poi in ipairs(L.POIs) do
		if poi.kind == "Campsite" then
			Ctx.status("camps: " .. poi.name)
			local g = Ctx.folder(root, poi.name)
			local c = flat(poi.position)
			local toCentre = if c.Magnitude > 1 then (-c).Unit else V3(0, 0, -1)
			local kit = {}
			for _, k in ipairs(CAMP_KIT) do
				if not k.tier or k.tier == poi.tier then
					table.insert(kit, k)
				end
			end
			-- shift (up to 6 studs) and turn the layout until no piece sits on a loot marker's clearing or a trail
			local function clashes(frame: CFrame, k): boolean
				local ai = L.AssetInfo[k[1]]
				local r = (if ai then ai.r else 2) * 0.8
				local p = flat(frame * V3(k[2], 0, k[3]))
				return Ctx.lootNear(p.X, p.Z, r) or Ctx.trailDistance(p.X, p.Z) < L.Exclusions.trail.bush + r
			end
			local bestFrame, bestHits = nil, math.huge
			for _, off in ipairs({ { 0, 0 }, { 4, 0 }, { -4, 0 }, { 0, 4 }, { 0, -4 }, { 6, 6 }, { -6, 6 }, { 6, -6 }, { -6, -6 } }) do
				for _, turn in ipairs({ 0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180 }) do
					local frame = facing(c + V3(off[1], 0, off[2]), CFrame.Angles(0, rad(turn), 0):VectorToWorldSpace(toCentre))
					local hits = 0
					for i, k in ipairs(kit) do
						if clashes(frame, k) then
							hits += if i == 1 then 100 else 1 -- the fire must have its spot
						end
					end
					if hits < bestHits then
						bestFrame, bestHits = frame, hits
					end
					if hits == 0 then
						break
					end
				end
				if bestHits == 0 then
					break
				end
			end
			local frame = bestFrame :: CFrame
			local tent, fire = nil, nil
			local skipped = 0
			for _, k in ipairs(kit) do
				if clashes(frame, k) then
					skipped += 1
				else
					local m = piece(Ctx, k[1], frame, k[2], k[3], k[4] + rng:NextNumber(-6, 6), g, { sink = if k[1] == "Campfire" then 0.1 else 0.05 })
					if not m then
						skipped += 1
					end
					if k[1] == "Tent" then
						tent = m
					elseif k[1] == "Campfire" then
						fire = m
					end
				end
			end
			local smoulder = Sites.SMOULDER[poi.name] == true
			Sites.douse(fire, smoulder)
			if fire then
				fire:SetAttribute("Smouldering", smoulder)
			end
			if tent then
				-- a lantern hung from the front of the ridge pole, out
				local lantern = Ctx.spawn("Lantern", tent:GetPivot() * CFrame.new(0, 3.05, -6.25), g, { keep = true })
				Sites.douse(lantern, false)
			end
			table.insert(notes, string.format("%s (tier %d, %s, %s%s)", poi.name, poi.tier, if smoulder then "smouldering" else "cold", if fire then "fire" else "NO FIRE", if skipped > 0 then (", " .. skipped .. " pieces left out for loot or trails") else ""))
		end
	end
	return table.concat(notes, "; ")
end

-------------------------------------------------------------------------------- cliffs
-- mean depth of each CliffFace's front surface ahead of its pivot, its full height and width (studs, scale 1)
local FRONT = { CliffFaceA = 7.0, CliffFaceB = 10.7, CliffFaceC = 15.0 }
local TALL = { CliffFaceA = 22.3, CliffFaceB = 31.9, CliffFaceC = 44.1 }
local WIDE = { CliffFaceA = 27.3, CliffFaceB = 38.3, CliffFaceC = 48.4 }

local function cliffFor(h: number): string
	if h < 25 then
		return "CliffFaceA"
	elseif h < 37 then
		return "CliffFaceB"
	end
	return "CliffFaceC"
end

function Sites.cliffs(Ctx): string
	local L = Ctx.Layout
	local folder = Ctx.out("Cliffs")
	Ctx.clear(folder)
	local rng = Random.new(Ctx.Seed * 13 + 5)
	local params = Ctx.terrainParams
	local pieces = {}
	local count = { escarpment = 0, gorge = 0, falls = 0, outcrop = 0, cover = 0, skipped = 0, seated = 0, why = {} }
	local function fail(reason: string): nil
		count.why[reason] = (count.why[reason] or 0) + 1
		return nil
	end
	local fall = L.River.fall
	local lipF, baseF = flat(fall.lip), flat(fall.base)

	-- flat distance from f to a crossing's span (the line between its two landings)
	local function spanDistance(f: Vector3, c): number
		local d = flat(c.direction)
		if d.Magnitude < 1e-3 then
			return (f - flat(c.position)).Magnitude
		end
		d = d.Unit
		local a = flat(c.position) - d * (c.span * 0.5)
		local t = math.clamp((f - a):Dot(d), 0, c.span)
		return (f - (a + d * t)).Magnitude
	end

	-- why a piece of radius r at p may not go there (nil = it may). cover = the coverage pass: crossings are measured
	-- from their span line and cave mouths by a tighter ring (a precise probe of the mouth follows in accept)
	local function blocked(p: Vector3, r: number, ovl: number?, cover: boolean?, hitY: number?): string?
		local f = flat(p)
		for _, cave in ipairs(L.Caves) do
			if (f - flat(cave.mouth)).Magnitude < (if cover then r * 0.4 + 5 else r * 0.7 + 8) then
				return "cave"
			end
		end
		local ab = baseF - lipF
		local t = math.clamp((f - lipF):Dot(ab) / max(ab:Dot(ab), 1e-6), 0, 1)
		if (f - (lipF + ab * t)).Magnitude < r * 0.6 + 7 then
			return "falls"
		end
		for _, c in ipairs(L.Crossings) do
			if cover then
				-- (the precise test of the crossing's walking line follows in accept: blocksCrossing)
				if spanDistance(f, c) < 2 then
					return "crossing"
				end
			elseif (f - flat(c.position)).Magnitude < r * 0.6 + max(6, c.span * 0.6) then
				return "crossing"
			end
		end
		for _, q in ipairs(pieces) do
			-- (a piece whose top stays under the bare band still being hit is no reason to leave the band bare)
			if (f - q.p).Magnitude < (r + q.r) * (ovl or 0.45) then
				return "overlap"
			end
		end
		return nil
	end

	-- a placed piece stays only when, seated (its front foot lowered onto the ground: no overhang over air), it keeps
	-- every trail's walking space and every loot clearing free; else it is removed and the spot counts as skipped.
	-- Returns (kept, drop).
	local caveProbe = OverlapParams.new()
	caveProbe.FilterType = Enum.RaycastFilterType.Include
	caveProbe.RespectCanCollide = true
	-- true when m reaches into a cave mouth's walking space: a 3.4 x 5 box from 6 studs inside to 12 out along each cave
	local function blocksCave(m: Model): boolean
		local probe = Ctx.probePart()
		probe.Shape = Enum.PartType.Block
		probe.Size = V3(3.4, 5, 3.4)
		caveProbe.FilterDescendantsInstances = { m }
		local pv = flat(m:GetPivot().Position)
		for _, cave in ipairs(L.Caves) do
			local mo = cave.mouth
			if (flat(mo) - pv).Magnitude < 80 then
				local out = flat(mo - cave.path[2])
				out = if out.Magnitude > 1e-3 then out.Unit else V3(1, 0, 0)
				for _, d in ipairs({ -6, -4, -2, 0, 2, 4, 6, 8, 10, 12 }) do
					local q = mo + out * d
					local fy = Ctx.heightBelow(q + V3(0, 5, 0), 14) or mo.Y
					probe.CFrame = CFrame.new(q.X, fy + 2.9, q.Z)
					if #workspace:GetPartsInPart(probe, caveProbe) > 0 then
						return true
					end
				end
			end
		end
		return false
	end

	-- true when m reaches into a crossing's walking line: a 2.6 x 3.6 box every 2 studs from 8 studs before one landing
	-- to 8 past the other (the approaches too), on the deck (the footbridge, the log) or the bed (fords, stepping stones)
	local deckParams = RaycastParams.new()
	deckParams.FilterType = Enum.RaycastFilterType.Include
	local function blocksCrossing(m: Model): boolean
		local pv = flat(m:GetPivot().Position)
		local _, size = m:GetBoundingBox()
		local reach = sqrt(size.X * size.X + size.Z * size.Z) / 2
		local probe = Ctx.probePart()
		probe.Shape = Enum.PartType.Block
		probe.Size = V3(2.6, 3.6, 2.6)
		caveProbe.FilterDescendantsInstances = { m }
		local pois = Ctx.arena():FindFirstChild("POIs")
		deckParams.FilterDescendantsInstances = if pois then { pois, workspace.Terrain } else { workspace.Terrain }
		for _, c in ipairs(L.Crossings) do
			if spanDistance(pv, c) < reach + 6 then
				local d = flat(c.direction).Unit
				local half = c.span * 0.5 + 8
				for t = -half, half, 2 do
					local q = c.position + d * t
					local y
					if c.kind == "Log" or c.kind == "Footbridge" then
						local hit = workspace:Raycast(V3(q.X, c.position.Y + 6, q.Z), V3(0, -30, 0), deckParams)
						y = if hit then hit.Position.Y else c.position.Y
					else
						y = Ctx.heightBelow(V3(q.X, c.position.Y + 4, q.Z), 30) or c.position.Y
					end
					probe.CFrame = CFrame.new(q.X, y + 2.8, q.Z)
					if #workspace:GetPartsInPart(probe, caveProbe) > 0 then
						return true
					end
				end
			end
		end
		return false
	end

	local function accept(m: Model, region: string?, maxDrop: number?): (boolean, number)
		local drop = Ctx.seat(m, { region = region or "front", share = 0.6, tol = 0.4, maxDrop = maxDrop or 6 })
		if drop > 0 then
			count.seated += 1
		end
		local why = if Ctx.blocksTrail(m) then "trail" elseif Ctx.blocksLoot(m) then "loot" elseif blocksCave(m) then "caveProbe"
			elseif Ctx.blocksWater(m, true) then "stream" elseif blocksCrossing(m) then "crossingProbe" else nil
		if why then
			m:Destroy()
			count.skipped += 1
			fail(why)
			return false, 0
		end
		return true, drop
	end

	-- skins the face at H (terrain normal n) between footY and topY with one CliffFace
	local function put(H: Vector3, n: Vector3, footY: number, topY: number, tag: string): boolean
		local h = topY - footY
		if h < 8 then
			return false
		end
		local nn = flat(n)
		if nn.Magnitude < 0.35 then
			return false
		end
		nn = nn.Unit
		local name = cliffFor(h)
		local s = math.clamp((h + 2.5) / TALL[name], 0.7, 1.45)
		local r = WIDE[name] * s * 0.5
		local face = flat(H) + nn * 1.0 -- the mean front surface goes 1 stud proud of the terrain face
		if blocked(face, r) then
			count.skipped += 1
			return false
		end
		local pos = face - nn * (FRONT[name] * s) + V3(0, footY - 2.5 * s, 0)
		-- trails and loot along the whole piece: its front edge, and its body behind the face
		local right = V3(-nn.Z, 0, nn.X)
		for _, t in ipairs({ -0.9, -0.45, 0, 0.45, 0.9 }) do
			for _, back in ipairs({ -1.5, FRONT[name] * s }) do
				local q = face + right * (r * t) - nn * back
				if Ctx.trailDistance(q.X, q.Z) < 3.5 or Ctx.lootNear(q.X, q.Z, 2) then
					count.skipped += 1
					return false
				end
			end
		end
		local cf = CFrame.lookAt(pos, pos + nn) * CFrame.Angles(0, rng:NextNumber(-0.16, 0.16), 0)
		local m = Ctx.spawn(name, cf, folder, { scale = s })
		if m and (accept(m)) then
			table.insert(pieces, { p = face, r = r })
			count[tag] += 1
			return true
		end
		return false
	end

	local function probe(origin: Vector3, dir: Vector3, reach: number): RaycastResult?
		local hit = workspace:Raycast(origin, dir * reach, params)
		if hit and abs(hit.Normal.Y) < 0.6 then
			return hit
		end
		return nil
	end

	-- the face behind a probe hit: foot just in front of it, top just behind it
	local function skin(hit: RaycastResult, back: number, tag: string)
		local nn = flat(hit.Normal)
		if nn.Magnitude < 0.3 then
			return
		end
		nn = nn.Unit
		local f = hit.Position + nn * 3.5
		local b = hit.Position - nn * back
		local footY, topY = Ctx.height(f.X, f.Z), Ctx.height(b.X, b.Z)
		if footY and topY and footY < hit.Position.Y and topY > hit.Position.Y then
			put(hit.Position, hit.Normal, footY, topY, tag)
		end
	end

	-- 1. the escarpment: probe its face from the open side, toward the plateau
	Ctx.status("cliffs: escarpment")
	local E = L.Escarpment
	local a = 343
	while a >= 258 do
		local rTop, height = E.at(a)
		if rTop and height >= 12 then
			local tp = L.polar(a, rTop + 5)
			local topY = Ctx.height(tp.X, tp.Z)
			if topY then
				for _, frac in ipairs({ 0.45, 0.8 }) do
					local hit = probe(L.polar(a, rTop - 60, topY - height * frac), dirOf(a), 85)
					if hit then
						skin(hit, 10, "escarpment")
					end
				end
			end
		end
		Ctx.yield()
		a -= 1.4
	end

	-- 2. the gorge walls: probe sideways from the stream
	Ctx.status("cliffs: gorge")
	local samples = L.River.samples
	local lastS = -math.huge
	for i, smp in ipairs(samples) do
		if smp.gorge == 1 and not smp.fall and smp.s - lastS >= 14 then
			lastS = smp.s
			local p0, p1 = samples[max(i - 1, 1)], samples[min(i + 1, #samples)]
			local t = V3(p1.x - p0.x, 0, p1.z - p0.z)
			if t.Magnitude > 1e-3 then
				t = t.Unit
				local side = V3(-t.Z, 0, t.X)
				for _, sgn in ipairs({ 1, -1 }) do
					for _, up in ipairs({ 4, 10, 17 }) do
						local hit = probe(V3(smp.x, smp.y + up, smp.z), side * sgn, 40)
						if hit then
							skin(hit, 9, "gorge")
							break
						end
					end
				end
			end
			Ctx.yield()
		end
	end

	-- 3. the falls bowl: probe outward from the plunge pool, never across the falling water
	Ctx.status("cliffs: falls")
	local pc, level = L.River.pool.center, L.River.pool.level
	local toFall = flat(fall.base - pc).Unit
	for k = 0, 23 do
		local d = dirOf(k * 15)
		if d:Dot(toFall) < cos(rad(30)) then
			for _, up in ipairs({ 5, 12, 20 }) do
				local hit = probe(V3(pc.X, level + up, pc.Z), d, 70)
				if hit then
					skin(hit, 9, "falls")
					break
				end
			end
		end
	end
	Ctx.yield()

	-- 4. rock outcrops along the escarpment rim
	Ctx.status("cliffs: rim outcrops")
	a = 340
	while a >= 260 do
		local rTop, height = E.at(a)
		if rTop and height >= 16 then
			local p = L.polar(a + rng:NextNumber(-1, 1), rTop + rng:NextNumber(2.5, 6))
			if not blocked(p, 8) and Ctx.trailDistance(p.X, p.Z) > 6 then
				local s = rng:NextNumber(0.8, 1.3)
				local m = onGround(Ctx, "RockOutcrop", p, s, yawFacing(-dirOf(a)), 0.5, 1.2 * s, folder)
				if m and (accept(m)) then
					for key in pairs(m:GetAttributes()) do
						m:SetAttribute(key, nil)
					end
					table.insert(pieces, { p = flat(p), r = 8 * s })
					count.outcrop += 1
				end
			end
		end
		a -= 5.5
	end

	-- 5. coverage: the walls players actually see. Observers on walkable ground (6-stud grid, slope under 20 degrees,
	-- not under water) in the Gorge and the Cliffs cast 16 level rays at eye height (5.2 up, 45 long); a ray that ends
	-- on bare steep terrain (normal.Y < 0.643) is a hit. Greedy: the 12-stud cell holding the most hits gets a rock
	-- piece fitted to its face (a CliffFace sized by the face's height and leaned back to its slope about the piece's
	-- front foot; a BoulderD on banks under 7 studs), the hits it now stands in front of are dropped, and every 12
	-- pieces the rays are cast again. Stops when no cell holds 3 hits or after Sites.COVER_BUDGET pieces.
	Ctx.status("cliffs: coverage")
	local obs = {}
	local cos20 = cos(rad(20))
	for _, biome in ipairs({ "Gorge", "Cliffs" }) do
		local bb = Ctx.biomeBounds[biome]
		if bb then
			for x = floor(bb.x0 / 6) * 6, bb.x1, 6 do
				for z = floor(bb.z0 / 6) * 6, bb.z1, 6 do
					if x * x + z * z < L.PlayRadius * L.PlayRadius and Ctx.biomeAt(x, z) == biome then
						local y, nrm, _, wy = Ctx.ground(x, z)
						if y and not wy and nrm.Y > cos20 then
							table.insert(obs, V3(x, y + 5.2, z))
						end
					end
				end
				Ctx.yield()
			end
		end
	end
	local eyeParams = RaycastParams.new()
	eyeParams.FilterType = Enum.RaycastFilterType.Exclude
	eyeParams.FilterDescendantsInstances = {}
	eyeParams.IgnoreWater = true
	local function castAll()
		local list = {}
		for i, eye in ipairs(obs) do
			for k = 0, 15 do
				local an = k * math.pi / 8
				local h = workspace:Raycast(eye, V3(cos(an), 0, sin(an)) * 45, eyeParams)
				if h and h.Instance == workspace.Terrain and h.Normal.Y < 0.643 then
					table.insert(list, { p = h.Position, n = h.Normal, o = eye.Y - 5.2, alive = true, eye = eye, dir = V3(cos(an), 0, sin(an)) * 45 })
				end
			end
			if i % 50 == 0 then
				Ctx.yield()
			end
		end
		return list
	end
	local function cellOf(p: Vector3): number
		return (floor(p.X / 12) + 200) * 160000 + (floor(p.Z / 12) + 200) * 400 + (floor(p.Y / 12) + 200)
	end
	-- one piece over the face at H (the cell's mean hit) with mean normal n3, seen from ground at obsY; returns a
	-- covers(p) test or nil. The piece stands Sites.COVER_PROUD in front of the face, so voxel bulges stay behind it.
	local function coverFace(H: Vector3, n3: Vector3, obsY: number, touch: boolean?)
		local nh = flat(n3)
		if nh.Magnitude < 0.3 then
			return fail("normal")
		end
		nh = nh.Unit
		local slopeDeg = math.deg(math.acos(math.clamp(n3.Y, -1, 1)))
		-- the foot: walk out from the hit until the ground stops falling, or until the water's edge (a wall rising
		-- out of a stream keeps its foot on the bank, so the stream stays open)
		local footD, footY, prevY, wet = nil, nil, H.Y, false
		for d = 0.5, 20, 1 do
			local q = flat(H) + nh * d
			local gy = Ctx.heightBelow(V3(q.X, H.Y + 0.5, q.Z), 60)
			if not gy then
				break
			end
			local _, _, _, wy = Ctx.ground(q.X, q.Z)
			if wy and wy > gy and wy < H.Y then
				footD, footY, wet = max(d - 0.8, 0.3), wy - 0.6, true
				break
			end
			if gy < H.Y - 0.8 and prevY - gy < 0.6 then
				footD, footY = d, gy
				break
			end
			prevY = gy
		end
		if not footD then
			-- an overhang or a drop with no floor in reach: stand the piece on the observers' ground
			footD, footY = 1.5, obsY
		end
		local back = flat(H) - nh * 8
		local topY = Ctx.height(back.X, back.Z)
		if not topY or topY < H.Y then
			topY = H.Y + 2
		end
		local h = topY - footY
		local E = flat(H) + nh * (max(footD - 0.6, 0.3) + (if wet then 0.2 else Sites.COVER_PROUD))
		-- a boulder against a low bank (or where no cliff piece fits)
		local function boulder(bh: number)
			-- tall enough to reach past the eye level of the contenders who see this face (their ground + 6.5)
			local s = math.clamp((max(bh, obsY + 6.5 - footY) + 1.5) / 7.1, 0.6, 1.6)
			local why = blocked(E, 6 * s, if touch then 0 else 0.15, true, H.Y)
			if why then
				return fail(why)
			end
			local pos = E - nh * (2.2 * s)
			local base = V3(pos.X, footY - 0.7 * s, pos.Z)
			local m = Ctx.spawn("BoulderD", CFrame.lookAt(base, base + nh) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0), folder, { scale = s })
			if not m then
				return fail("spawn")
			end
			local kept, drop = accept(m, "all", 3)
			if not kept then
				return nil
			end
			local top = footY - 0.7 * s - drop + 7.1 * s
			table.insert(pieces, { p = E, r = 5.5 * s, top = top })
			count.cover += 1
			return function(p: Vector3): boolean
				return (V3(p.X, 0, p.Z) - V3(pos.X, 0, pos.Z)).Magnitude < 6.5 * s and p.Y < top
			end
		end
		local tilt = math.clamp(90 - slopeDeg, 0, 35)
		local slant = h / cos(rad(tilt))
		-- a CliffFace fitted to the face (small = the smallest one, at 0.7: where a bigger piece doesn't fit)
		local function cliff(small: boolean)
			local name = if small then "CliffFaceA" else cliffFor(slant)
			local s = if small then 0.7 else math.clamp((slant + 2.5) / TALL[name], 0.7, 1.45)
			local w = WIDE[name] * s
			local why = blocked(E, w * 0.5, 0.15, true, H.Y)
			if why then
				return fail(why)
			end
			local jitter = rng:NextNumber(-0.12, 0.12)
			local function frameFor(sc: number): CFrame
				local edge = V3(E.X, footY - 1.0 * sc, E.Z)
				return CFrame.lookAt(edge, edge + nh) * CFrame.Angles(0, jitter, 0) * CFrame.Angles(rad(tilt), 0, 0)
			end
			local faceCf = frameFor(s)
			-- the sides must not hang over a drop (the wall ends there): take a narrower piece, else give up
			for _ = 1, 2 do
				local hang = false
				for _, t in ipairs({ -0.42, 0.42 }) do
					-- 1.5 behind the front, 1 up: inside the hill where the wall goes on (the top surface is above it)
					local q = faceCf * V3(t * w, 1, 1.5)
					local gy = Ctx.height(q.X, q.Z)
					if not gy or gy < q.Y - 3 then
						hang = true
					end
				end
				if not hang then
					break
				end
				if name == "CliffFaceA" then
					return fail("sideHang")
				end
				name = if name == "CliffFaceC" then "CliffFaceB" else "CliffFaceA"
				s = math.clamp((slant + 2.5) / TALL[name], 0.7, 1.45)
				w = WIDE[name] * s
				faceCf = frameFor(s)
			end
			-- stand the face in front of the wall's bulges: probe the terrain from 8 studs out along the face normal over a
			-- grid on the face (eye-level band), and move the piece out by the largest bulge (at most 3.5)
			local fwd = faceCf.LookVector
			local bulge = 0
			for _, t in ipairs({ -0.4, -0.2, 0, 0.2, 0.4 }) do
				for hy = 1.5, min(TALL[name] * s - 1, 14), 3 do
					local from = faceCf * V3(t * w, hy, 0) + fwd * 8
					local hit = workspace:Raycast(from, -fwd * 14, Ctx.terrainParams)
					if hit then
						bulge = max(bulge, 8 - (hit.Position - from).Magnitude)
					end
				end
			end
			if bulge > 0 then
				faceCf = faceCf + fwd * min(bulge + 0.4, 2.5)
			end
			-- the back must stay inside the hill (no slab poking out of the slope behind the wall)
			local info = Ctx.info(name)
			local depth = FRONT[name] * s + (if info then info.bmax.Z * s else 10)
			for _, t in ipairs({ -0.45, 0, 0.45 }) do
				local q = faceCf * V3(t * w, TALL[name] * s, depth)
				local gy = Ctx.height(q.X, q.Z)
				if not gy or gy < q.Y - 4 then
					return fail("backPoke")
				end
			end
			local m = Ctx.spawn(name, faceCf * CFrame.new(0, 0, FRONT[name] * s), folder, { scale = s })
			if not m then
				return fail("spawn")
			end
			-- a coverage piece drops at most 2.5 to rest its front: deeper and it would slide off a ledge into the stream
			local kept, drop = accept(m, nil, 2.5)
			if not kept then
				return nil
			end
			table.insert(pieces, { p = E, r = w * 0.5, top = footY - 1.0 * s - drop + TALL[name] * s * cos(rad(tilt)) })
			count.cover += 1
			local face = faceCf - V3(0, drop, 0)
			local hw, top = w * 0.46, TALL[name] * s - 0.5
			return function(p: Vector3): boolean
				local l = face:PointToObjectSpace(p)
				return math.abs(l.X) < hw and l.Y > -1 and l.Y < top and l.Z > -1.5 and l.Z < 7
			end
		end
		if h < 7 or touch then
			return boulder(min(h, 7.5))
		end
		if Ctx.biomeAt(H.X, H.Z) == "Gorge" then
			-- the gorge winds and its stream runs close under the walls: a big straight face would cut across the water
			-- at a bend, so the eye-level band is skinned with boulders first, then small faces
			return cliff(true) or boulder(min(h, 7.5)) or cliff(false)
		end
		return cliff(false) or cliff(true) or boulder(min(h, 8))
	end
	local hits = castAll()
	local before = #hits
	local tried = 0
	local dead = {}
	while count.cover < Sites.COVER_BUDGET and tried < Sites.COVER_BUDGET * 4 do
		local cells = {}
		local bestK, bestN = nil, 0
		for _, hh in ipairs(hits) do
			if hh.alive then
				local k = cellOf(hh.p)
				if not dead[k] then
					local c = cells[k]
					if not c then
						c = { n = 0, p = Vector3.zero, nrm = Vector3.zero, o = 0 }
						cells[k] = c
					end
					c.n += 1
					c.p += hh.p
					c.nrm += hh.n
					c.o += hh.o
					if c.n > bestN then
						bestN, bestK = c.n, k
					end
				end
			end
		end
		if not bestK or bestN < 2 then
			break
		end
		tried += 1
		local c = cells[bestK]
		local covers = coverFace(c.p / c.n, c.nrm.Unit, c.o / c.n)
		if covers then
			-- what the piece really hides: re-cast the rays that met this cell
			for _, hh in ipairs(hits) do
				if hh.alive and cellOf(hh.p) == bestK then
					count.aimed = (count.aimed or 0) + 1
					local r2 = workspace:Raycast(hh.eye, hh.dir, eyeParams)
					if r2 and r2.Instance == workspace.Terrain and r2.Normal.Y < 0.643 then
						count.missed = (count.missed or 0) + 1
					end
				end
			end
			for _, hh in ipairs(hits) do
				if hh.alive and (covers(hh.p) or cellOf(hh.p) == bestK) then
					hh.alive = false
				end
			end
			if count.cover % 12 == 0 then
				hits = castAll()
			end
		else
			dead[bestK] = true
		end
		Ctx.yield()
	end
	-- touch-up: boulders straight in front of what the faces left bare (beside or under an earlier piece), with no
	-- overlap rule; the trail, loot, cave and stream checks still hold
	hits = castAll()
	dead = {}
	local touched = 0
	while touched < Sites.TOUCHUP_BUDGET do
		local cells = {}
		local bestK, bestN = nil, 0
		for _, hh in ipairs(hits) do
			if hh.alive then
				local k = cellOf(hh.p)
				if not dead[k] then
					local c = cells[k]
					if not c then
						c = { n = 0, p = Vector3.zero, nrm = Vector3.zero, o = 0 }
						cells[k] = c
					end
					c.n += 1
					c.p += hh.p
					c.nrm += hh.n
					c.o += hh.o
					if c.n > bestN then
						bestN, bestK = c.n, k
					end
				end
			end
		end
		if not bestK or bestN < 2 then
			break
		end
		local c = cells[bestK]
		local covers = coverFace(c.p / c.n, c.nrm.Unit, c.o / c.n, true)
		dead[bestK] = true
		if covers then
			touched += 1
			for _, hh in ipairs(hits) do
				if hh.alive and covers(hh.p) then
					hh.alive = false
				end
			end
		end
		Ctx.yield()
	end
	count.touch = touched
	local after = #castAll()
	local whys = {}
	for k, v in pairs(count.why) do
		table.insert(whys, k .. " " .. v)
	end
	table.sort(whys)
	return string.format("cliff faces: escarpment %d, gorge %d, falls %d; rim outcrops %d; coverage pieces %d (%d of them touch-up boulders; bare steep eye-level hits %d -> %d, %d observers; the cells' own rays hidden by their piece %d of %d; cells refused: %s); %d seated lower; %d spots skipped",
		count.escarpment, count.gorge, count.falls, count.outcrop, count.cover, count.touch or 0, before, after, #obs, (count.aimed or 0) - (count.missed or 0), count.aimed or 0, table.concat(whys, ", "), count.seated, count.skipped)
end

-------------------------------------------------------------------------------- ambience
function Sites.ambience(Ctx): string
	local L = Ctx.Layout
	local folder = Ctx.out("Ambience")
	Ctx.clear(folder)
	local count = { river = 0, waterfall = 0, frogs = 0, wind = 0, fire = 0 }
	local function emitter(pos: Vector3, key: string)
		local p = Instance.new("Part")
		p.Name = key
		p.Size = V3(1, 1, 1)
		p.CFrame = CFrame.new(pos)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p:SetAttribute("SoundKey", key)
		p:SetAttribute("Source", "Populate:Ambience")
		p:AddTag("AmbientEmitter")
		p.Parent = folder
	end
	-- the river, every ~60 studs (not on the falling water)
	local walked, nextAt, last = 0, 20, nil
	for _, smp in ipairs(L.River.samples) do
		local p = V3(smp.x, smp.y, smp.z)
		if last then
			walked += (flat(p) - flat(last)).Magnitude
		end
		last = p
		if walked >= nextAt and not smp.fall then
			emitter(p + V3(0, 1.5, 0), "Emit_River")
			count.river += 1
			nextAt = walked + 60
		end
	end
	-- the falls: in front of the falling sheet, a third of the way up
	local fall = L.River.fall
	local outward = flat(fall.base - fall.lip)
	outward = if outward.Magnitude > 1e-3 then outward.Unit else V3(0, 0, 1)
	emitter(V3(fall.base.X, fall.bottom + (fall.top - fall.bottom) * 0.3, fall.base.Z) + outward * 6, "Emit_Waterfall")
	count.waterfall = 1
	-- frogs: marsh pools, spread out
	local rng = Random.new(Ctx.Seed + 77)
	local frogs = {}
	for _ = 1, 900 do
		if #frogs >= 6 then
			break
		end
		local a, r = rng:NextNumber(0, TAU), 115 * sqrt(rng:NextNumber())
		local p = flat(L.Marsh.center) + V3(cos(a), 0, sin(a)) * r
		local far = true
		for _, q in ipairs(frogs) do
			if (flat(q) - p).Magnitude < 55 then
				far = false
			end
		end
		if far and L.isInMarsh(p) then
			local _, _, _, wy, depth = Ctx.ground(p.X, p.Z)
			if wy and depth > 0.2 then
				local spot = V3(p.X, wy + 1, p.Z)
				table.insert(frogs, spot)
				emitter(spot, "Emit_Frogs")
			end
		end
	end
	count.frogs = #frogs
	-- wind: four exposed heights
	for _, spec in ipairs({ { 322, 560 }, { 348, 600 }, { 16, 470 }, { 38, 590 } }) do
		local p = L.polar(spec[1], spec[2])
		local h = Ctx.height(p.X, p.Z)
		if h then
			emitter(V3(p.X, h + 12, p.Z), "Emit_Wind")
			count.wind += 1
		end
	end
	-- the smouldering camp fires
	local camps = Ctx.arena():FindFirstChild("Camps")
	if camps then
		for _, d in ipairs(camps:GetDescendants()) do
			if d:IsA("Model") and d.Name == "Campfire" and d:GetAttribute("Smouldering") == true then
				local fc = d:FindFirstChild("FireCenter", true)
				emitter(if fc and fc:IsA("Attachment") then fc.WorldPosition else d:GetPivot().Position + V3(0, 0.6, 0), "Emit_Fire")
				count.fire += 1
			end
		end
	end
	return string.format("emitters: river %d, waterfall %d, frogs %d, wind %d, fire %d", count.river, count.waterfall, count.frogs, count.wind, count.fire)
end

return Sites
