--[[
	Populate.Scatter - forest, flora and rocks by biome from ArenaLayout.Scatter: densities (items per 1000 sq studs),
	clusters, spacing, slope / height / moisture / water-depth windows, edge and cliff boosts, scale, tilt, tiltToNormal,
	sink and align, inside ArenaLayout.Exclusions. On top of the rules:
	  * keep-outs (Ctx.prepare): loot markers (crates 4.5, ground items 3 studs), the RunnerCaches (6) and their
	    sightlines to the plates, cave mouths (12) and their approach, crossings and their landings, POI footprints;
	    the plaza (r < 70: nothing) and the meadow core (r < 100: ground cover only)
	  * trails: trees keep 3.5 + trunk, bushes and rocks 3 + their radius, ground cover 1.6 from the centreline
	  * solid occupancy: trunks, rocks, logs and stumps never overlap; ground cover never sits in a trunk or a rock
	  * stand density: a low-frequency noise field (x0.25..x1.75, mean ~1) on trees and young conifers makes thick
	    stands and open glades: dense at eye level, with sightlines
	  * trees stand upright, the pivot on the lowest ground round the trunk (no side floats on a slope; roots dive
	    0.6-0.8 below it); flora and rocks follow the ground normal (tiltToNormal) with random yaw; logs lie along the
	    contour and must touch the ground at both ends; nothing land-based stands in water deeper than 0.6
	  * past r 650 (outside the play area) everything is visual only (no collision, no queries)
	  * fill: after the seeded grid pass each rule keeps seeding clumps at random until it reaches its density x the
	    biome's area inside the play radius (ArenaLayout's numbers), so exclusions don't leave stands thin; a rule
	    stops short only where no valid ground is left (the log reports placed / target per rule)
	  * loot clearings (crates 4.5, ground items 3) and runner's caches (6) stay free by each piece's whole bounding box
	    (crowns, skirts and fronds too); rocks, logs and stumps are seated (Ctx.seat) and never stand in a trail's
	    walking space (Ctx.blocksTrail)
	  * variety for the cards that repeat by the hundred (reeds, sedge): wider scale, a lean, a non-uniform stretch,
	    patchy beds (a noise field) and clumps of varied spread; the marsh and the lake beach get extra rules
	    (Scatter.ADD: sedge, tufts, beach grass)
	  * the gorge's logs lie across the stream from bank to bank (gorgeLogs)
	Passes, each over every biome: 1 trees, 2 rocks / logs / stumps, 3 bushes, 4 ground cover and water plants.
	Output: workspace.Arena.Forest / Flora / Rocks, one sub-folder per biome. CliffFace / Crag rules belong to
	Sites.cliffs (the mountain crags are left out: the wall beyond the border stays bare terrain).
]]
local Scatter = {}

local sqrt, min, max, floor, abs, rad, deg = math.sqrt, math.min, math.max, math.floor, math.abs, math.rad, math.deg
local V3 = Vector3.new
local TAU = math.pi * 2

-- Per-class density multipliers on top of ArenaLayout.Scatter and Populate.DENSITY_SCALE (the performance knobs).
Scatter.DENSITY = { tree = 1, bush = 1, groundCover = 1, water = 1, rock = 1 }
local STAND_MAX = 1.75

-- trunk radius (studs, scale 1) used for trails, keep-outs and the occupancy test
local TRUNK = {
	SpruceA = 1.4, SpruceB = 1.1, FirA = 1.0, PineA = 1.3, ConiferYoung = 0.4, BirchA = 0.8, BirchB = 1.4,
	OakA = 2.4, SnagA = 0.9, SnagB = 0.8, SaplingBroadleaf = 0.35,
}
local LOG_LENGTH = { FallenLogA = 15.8, FallenLogB = 22.4 }
-- plants do not grow on bare rock, scree, gravel bars or snow
local BARE = {
	[Enum.Material.Rock] = true, [Enum.Material.Basalt] = true, [Enum.Material.Limestone] = true,
	[Enum.Material.Snow] = true, [Enum.Material.Slate] = true, [Enum.Material.Salt] = true,
}
local SKIP = { CliffFace = true, Crag = true }

local function lakeStyle(Ctx, x: number, z: number)
	local Lake = Ctx.Layout.Lake
	return Lake.shoreStyle(Lake.phiOf(x, z))
end

-- extra per-rule constraints from the rules' "where" notes, keyed "Biome.kind"
--   minR / maxR      radius window      maxCount  cap        weight(Ctx, x, z) -> 0..1 acceptance
--   wetMax           may stand in water this deep (rocks and logs half in the water)
--   nearWater        must be within this many studs of open water
--   rimBack          trees stay this far from steep ground     aboveWater  ground above MarshLevel + n
--   marshEdge        within n studs of the marsh outline        rockKnob    on rock or slopes over 22 degrees
--   heightFade {a,b} thins out between heights a and b         visual      no collision (outside the play area)
--   ramp             meadow grass: denser toward the treeline    density     extra density multiplier
--   fill             share of the rule's target the fill pass aims for (default 1)   noFill   no fill pass
--   slope / height / moisture   override the rule's windows        allowBare  may grow on bare rock (ledges)
--   scale / tilt / waterDepth   override the rule's                 endDrop   a log end may hang this far
--   stretch { xz, y } non-uniform stretch ranges     patchy { size, floor }  noise-field beds and gaps
--   clusterSpread { a, b }  clump radius x a..b       special  a custom placer ("gorgeLogs")
--   shoreBand        (Lake rules) may also stand in the next biome within this many studs of the Lake biome, toward
--                    the lake centre: the beach and the banks mostly lie in the meadow and the forest
local REED_VARIETY = { xz = { 0.8, 1.25 }, y = { 0.72, 1.35 } }
local EXTRA = {
	["Meadow.Wildflowers"] = { minR = 80, fill = 0.8 },
	["Meadow.GrassTuft"] = { minR = 72, ramp = true, fill = 0.8 },
	["Meadow.TallGrass"] = { minR = 115, fill = 0.8 },
	-- the meadow's few landmarks: the rule densities are per 1000 sq studs of the whole meadow, but only its outer ring
	-- may hold them, so they are sampled denser and capped
	["Meadow.LoneTree"] = { minR = 118, maxCount = 4, density = 8 },
	["Meadow.Boulder"] = { minR = 100, maxCount = 8, density = 4 },
	["Field.LoneTree"] = { maxCount = 8 },
	-- the lake rules only find room on the narrow shore band of the Lake biome (most of it is water): sampled denser
	["Lake.Birch"] = { density = 4 },
	["Lake.Reeds"] = {
		density = 2,
		weight = function(Ctx, x, z)
			local s = lakeStyle(Ctx, x, z)
			return 0.25 + 0.75 * max(s.reeds, s.mouth)
		end,
		scale = { 0.6, 1.35 },
		tilt = 8,
		stretch = REED_VARIETY,
		clusterSpread = { 0.45, 1.6 },
		nearWater = 3,
		fillTries = 60,
	},
	["Lake.BeachGrass"] = { nearWater = 16, patchy = { size = 26, floor = 0.2 }, shoreBand = 16 },
	["Lake.ShoreStones"] = {
		density = 3,
		wetMax = 0.8,
		nearWater = 4,
		shoreBand = 10,
		fillTries = 160, -- most random points in the Lake biome are open water
		weight = function(Ctx, x, z)
			local s = lakeStyle(Ctx, x, z)
			return 0.2 + 0.8 * max(s.beach, s.mouth)
		end,
	},
	["Lake.ShoreRock"] = {
		density = 3,
		wetMax = 2.0,
		shoreBand = 6,
		fillTries = 160,
		weight = function(Ctx, x, z)
			return if lakeStyle(Ctx, x, z).rocky > 0.5 then 1 else 0
		end,
	},
	["Lake.Ledge"] = {
		density = 4,
		wetMax = 1.0, -- flat rocks at the waterline
		fillTries = 160,
		weight = function(Ctx, x, z)
			return if lakeStyle(Ctx, x, z).rocky > 0.5 then 1 else 0
		end,
	},
	["Lake.Driftwood"] = {
		density = 4,
		nearWater = 7,
		scale = { 0.55, 0.9 },
		endDrop = 1.4,
		shoreBand = 14,
		fillTries = 300,
		wetMax = 1.0, -- washed up: an end may lie in the shallows
		weight = function(Ctx, x, z)
			return if lakeStyle(Ctx, x, z).beach > 0.4 then 1 else 0
		end,
	},
	["Gorge.Conifer"] = { rimBack = 5 },
	["Gorge.FallenLog"] = { maxCount = 9, special = "gorgeLogs" },
	["Gorge.StreamRocks"] = { nearWater = 3, waterDepth = { 0, 1.6 }, fillTries = 80 },
	["Gorge.Fern"] = { allowBare = true },
	["Gorge.Moss"] = { allowBare = true },
	["Cliffs.Fern"] = { allowBare = true, moisture = { 0.3, 1 } },
	["Cliffs.Moss"] = { allowBare = true },
	["Forest.Oak"] = { slope = { 0, 24 }, height = { 0, 175 } },
	["Forest.Birch"] = { moisture = { 0.3, 1 } },
	["Forest.Pine"] = { moisture = { 0, 0.62 } },
	["Forest.Mushrooms"] = { moisture = { 0.32, 1 }, slope = { 0, 34 } },
	["Forest.Moss"] = { moisture = { 0.28, 1 } },
	["Forest.FallenLog"] = { endDrop = 0.9 },
	["Marsh.Reeds"] = {
		scale = { 0.6, 1.4 },
		tilt = 9,
		stretch = REED_VARIETY,
		patchy = { size = 38, floor = 0.08 },
		clusterSpread = { 0.45, 1.7 },
		nearWater = 4,
	},
	["Marsh.Sedge"] = { stretch = REED_VARIETY, patchy = { size = 30, floor = 0.15 }, clusterSpread = { 0.5, 1.6 } },
	["Marsh.Tufts"] = { patchy = { size = 24, floor = 0.25 } },
	["Marsh.Bush"] = { aboveWater = 0.6 },
	["Marsh.Birch"] = { marshEdge = 22 },
	["Marsh.Snag"] = {
		weight = function(Ctx, x, z)
			local s = Ctx.Layout.Marsh.snags
			local dx, dz = x - s.X, z - s.Z
			return if dx * dx + dz * dz < 4900 then 1 else 0.35
		end,
	},
	["Marsh.FallenLog"] = { wetMax = 1.2 },
	["Mountains.Conifer"] = { maxR = 860, visual = true, heightFade = { 170, 300 }, density = 0.7, noFill = true },
	["Mountains.Scree"] = { minR = 715, maxR = 860, visual = true, maxCount = 60, noFill = true },
	["Forest.Outcrop"] = { rockKnob = true },
}
Scatter.EXTRA = EXTRA

-- Rules this module adds to ArenaLayout.Scatter (same fields), appended to the biome's list.
Scatter.ADD = {
	Marsh = {
		{ assets = { "GrassTallA", "GrassTallB" }, kind = "Sedge", class = "groundCover", density = 7, cluster = { radius = 8, min = 3, max = 12 }, spacing = 1.5, slope = { 0, 30 }, scale = { 0.75, 1.45 }, tilt = 7, where = "sedge and tall grass on the banks, hummocks and wet margins: breaks up the reed beds" },
		{ assets = { "GrassForest" }, kind = "Tufts", class = "groundCover", density = 5, cluster = { radius = 6, min = 4, max = 12 }, spacing = 1.2, slope = { 0, 35 }, scale = { 0.8, 1.5 }, tiltToNormal = 1 },
	},
	Lake = {
		{ assets = { "GrassForest", "GrassTallB" }, weights = { 0.7, 0.3 }, kind = "BeachGrass", class = "groundCover", density = 4, cluster = { radius = 6, min = 3, max = 9 }, spacing = 1.3, slope = { 0, 30 }, tiltToNormal = 1, where = "tufts at the back of the beach and on the banks" },
	},
}

-- the biome's ArenaLayout.Scatter rules plus Scatter.ADD
function Scatter.rulesFor(L, biome: string)
	local list = {}
	for _, r in ipairs(L.Scatter[biome] or {}) do
		table.insert(list, r)
	end
	for _, r in ipairs(Scatter.ADD[biome] or {}) do
		table.insert(list, r)
	end
	return list
end

-- Non-uniform stretch about the model's pivot (variety for cards repeated by the hundred): XZ by a, Y by b.
local function stretch(m: Model, spec, u3: number, u4: number)
	local a = spec.xz[1] + (spec.xz[2] - spec.xz[1]) * u3
	local b = spec.y[1] + (spec.y[2] - spec.y[1]) * u4
	local pv = m:GetPivot()
	local function f(v: Vector3): number
		return sqrt((a * v.X) ^ 2 + (b * v.Y) ^ 2 + (a * v.Z) ^ 2)
	end
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			local rel = pv:ToObjectSpace(p.CFrame)
			local pos = rel.Position
			p.Size = V3(p.Size.X * f(rel.RightVector), p.Size.Y * f(rel.UpVector), p.Size.Z * f(rel.LookVector))
			p.CFrame = pv * (CFrame.new(pos.X * a, pos.Y * b, pos.Z * a) * rel.Rotation)
		end
	end
end

local function outFolderName(rule): string
	local a = rule.assets[1]
	if rule.class == "tree" or LOG_LENGTH[a] or rule.kind == "Stump" or rule.kind == "YoungConifer" or rule.kind == "Sapling" then
		return "Forest"
	end
	if rule.class == "rock" or rule.kind == "StreamRocks" then
		return "Rocks"
	end
	return "Flora"
end

local function passOf(rule): number
	if rule.class == "tree" then
		return 1
	end
	if rule.class == "rock" or rule.kind == "FallenLog" or rule.kind == "Stump" or rule.kind == "StreamRocks" then
		return 2
	end
	if rule.class == "bush" then
		return 3
	end
	return 4
end

-- (footprint radius for trails and keep-outs, solid radius for the occupancy test)
local function radii(Layout, rule, asset: string, scale: number): (number, number)
	local ai = Layout.AssetInfo[asset]
	local r = (if ai and ai.r then ai.r else 1) * scale
	local t = TRUNK[asset]
	if t then
		if rule.class == "tree" then
			return t * scale, t * scale
		end
		return max(t * scale, r * 0.5), t * scale
	end
	if LOG_LENGTH[asset] then
		return 1.4 * scale, 1.3 * scale
	end
	if rule.class == "rock" or rule.kind == "StreamRocks" or rule.kind == "Stump" then
		return r * 0.85, r * 0.8
	end
	if rule.class == "bush" then
		return r * 0.8, r * 0.45
	end
	return r * 0.6, 0
end

local function stand(seed: number, x: number, z: number): number
	local n = math.noise(x / 150 + 13.37, z / 150 - 4.21, seed * 0.0017)
		+ 0.55 * math.noise(x / 55 - 2.1, z / 55 + 8.3, seed * 0.0031 + 0.37)
	return math.clamp(1 + 1.25 * n, 0.35, STAND_MAX)
end
Scatter.stand = stand

local function pickAsset(rule, rng: Random, Ctx, x: number, z: number): string
	local assets, weights = rule.assets, rule.weights
	if #assets == 1 then
		return assets[1]
	end
	local w, total, m = {}, 0, nil
	for i, a in ipairs(assets) do
		local wi = if weights then (weights[i] or 1) else 1
		if a == "FirA" or a == "FernA" or a == "FernB" then
			m = m or Ctx.Layout.moistureAt(x, z)
			if a == "FirA" then
				wi *= if m > 0.45 then 2 else 0.45 -- firs favour damp valley floors
			elseif a == "FernA" then
				wi *= if m < 0.5 then 4 else 1 -- bracken on drier, sunnier ground
			else
				wi *= if m >= 0.5 then 4 else 1 -- sword fern in damp shade
			end
		end
		w[i] = wi
		total += wi
	end
	local r = rng:NextNumber() * total
	for i, a in ipairs(assets) do
		r -= w[i]
		if r <= 0 then
			return a
		end
	end
	return assets[#assets]
end

local function occupied(S, x: number, z: number, ruleId: number, spacing: number, solid: number, cls: string): boolean
	return S.occ:any(x, z, max(spacing, solid + 7), function(it)
		local dx, dz = it.x - x, it.z - z
		local d2 = dx * dx + dz * dz
		if it.rule == ruleId and d2 < spacing * spacing then
			return true
		end
		if cls == "tree" and it.cls == "tree" then
			local s = 0.4 * (spacing + it.spacing)
			if d2 < s * s then
				return true
			end
		end
		if it.solid > 0 then
			local need = if solid > 0 then solid + it.solid else it.solid * 0.9
			if d2 < need * need then
				return true
			end
		end
		return false
	end)
end

-- counts why a rule's candidates were refused (the scatter log lists it for rules that fall short)
local function no(R, reason: string): boolean
	R.rej[reason] = (R.rej[reason] or 0) + 1
	return false
end

local function tryPlace(S, R, x: number, z: number): boolean
	local Ctx, L, rule, rng, extra = S.Ctx, S.L, R.rule, R.rng, R.extra
	local EX = L.Exclusions
	local cls = rule.class
	local isCover = cls == "groundCover" or cls == "water"
	-- a fixed number of random draws per candidate
	local asset = pickAsset(rule, rng, Ctx, x, z)
	local sc = extra.scale or rule.scale or (if cls == "tree" then { 0.9, 1.12 } else { 0.85, 1.15 })
	local scale = sc[1] + (sc[2] - sc[1]) * rng:NextNumber()
	local yaw = rng:NextNumber() * TAU
	local u1, u2 = rng:NextNumber(), rng:NextNumber()
	local u3, u4 = rng:NextNumber(), rng:NextNumber() -- the stretch (variety)
	local r = sqrt(x * x + z * z)
	if (extra.minR and r < extra.minR) or (extra.maxR and r > extra.maxR) then
		return false
	end
	if not R.inBiome(x, z) then
		return false
	end
	local foot, solid = radii(L, rule, asset, scale)
	if r < EX.plaza + foot then
		return false
	end
	if not isCover and r < EX.meadowCore then
		return false
	end
	local trailLim = if cls == "water" then 0 elseif cls == "rock" then EX.trail.bush else (EX.trail[cls] or EX.trail.groundCover)
	if trailLim > 0 and Ctx.trailDistance(x, z) < trailLim + foot then
		return no(R, "trail")
	end
	local ko = Ctx.keptOut(x, z, foot, isCover)
	if ko then
		return no(R, "keepout:" .. string.match(ko, "^[^:]+"))
	end
	if cls == "tree" then
		for _, c in ipairs(L.Clearings) do
			local dx, dz = x - c.center.X, z - c.center.Z
			if dx * dx + dz * dz < c.radius * c.radius then
				return false
			end
		end
	end
	local spacing = rule.spacing or (if isCover then foot * 1.4 else foot * 2.2)
	if occupied(S, x, z, R.id, spacing, solid, cls) then
		return no(R, "occupied")
	end
	-- the ground
	local y, n, mat, wy, depth = Ctx.ground(x, z)
	if not y then
		return false
	end
	if cls == "water" then
		local wd = extra.waterDepth or rule.waterDepth or { 0.1, 1.8 }
		if wy then
			if depth < wd[1] or depth > wd[2] then
				return no(R, "depth")
			end
		elseif wd[1] > 0 or L.distanceToWater(V3(x, 0, z)) > (extra.nearWater or 2) then
			return no(R, "dry")
		end
	elseif wy then
		if depth > (extra.wetMax or EX.water.land) then
			return no(R, "wet")
		end
	elseif extra.nearWater and L.distanceToWater(V3(x, 0, z)) > extra.nearWater then
		return no(R, "farFromWater")
	end
	local slope = deg(math.acos(math.clamp(n.Y, -1, 1)))
	local slopeWin = extra.slope or rule.slope
	if slopeWin and (slope < slopeWin[1] or slope > slopeWin[2]) then
		return no(R, "slope")
	end
	local smax = EX.slope[cls]
	if smax and slope > smax then
		return no(R, "slope")
	end
	local hWin = extra.height or rule.height
	if hWin and (y < hWin[1] or y > hWin[2]) then
		return false
	end
	local mWin = extra.moisture or rule.moisture
	if mWin then
		local m = L.moistureAt(x, z)
		if m < mWin[1] or m > mWin[2] then
			return false
		end
	end
	if BARE[mat] and not (cls == "rock" or cls == "water" or rule.kind == "StreamRocks" or extra.allowBare) then
		return false
	end
	if cls == "tree" and L.distanceToCliff(V3(x, y, z)) < max(EX.cliffEdge, extra.rimBack or 0) then
		return false
	end
	if extra.aboveWater and y < L.MarshLevel + extra.aboveWater then
		return false
	end
	if extra.marshEdge and L._signedPolygonDistance(L.Marsh.outline, x, z) < -extra.marshEdge then
		return false
	end
	if extra.rockKnob and not (mat == Enum.Material.Rock or slope > 22) then
		return false
	end
	if extra.heightFade then
		local f = math.clamp((extra.heightFade[2] - y) / (extra.heightFade[2] - extra.heightFade[1]), 0, 1)
		if u1 > f then
			return false
		end
	end
	-- the frame
	local sink = (rule.sink or 0) * scale
	local tiltN = rule.tiltToNormal or 0
	local logLen = LOG_LENGTH[asset]
	local cf
	if cls == "tree" or tiltN <= 0 then
		-- upright: the pivot on the lowest ground round the trunk / base, so no side floats
		local rr = max(0.7, if cls == "tree" then solid else foot * 0.6)
		local lo = y
		for k = 0, 3 do
			local a = yaw + k * math.pi / 2 + math.pi / 4
			local hy = Ctx.height(x + math.cos(a) * rr, z + math.sin(a) * rr)
			if hy and hy < lo then
				lo = hy
			end
		end
		cf = CFrame.new(x, lo - 0.12 - sink, z) * CFrame.Angles(0, yaw, 0)
		local tiltDeg = extra.tilt or rule.tilt
		if tiltDeg then
			local t = rad(tiltDeg)
			cf = cf * CFrame.Angles((u1 * 2 - 1) * t, 0, (u2 * 2 - 1) * t)
		end
	else
		local downhill = V3(n.X, 0, n.Z)
		if rule.align == "contour" and downhill.Magnitude > 0.03 then
			local c = downhill.Unit:Cross(Vector3.yAxis)
			yaw = math.atan2(-c.Z, c.X) + (if u1 < 0.5 then 0 else math.pi) + (u2 - 0.5) * 0.5
		elseif rule.align == "downslope" and downhill.Magnitude > 0.03 then
			local d = downhill.Unit
			yaw = math.atan2(-d.X, -d.Z) + (u2 - 0.5) * 0.6
		end
		cf = Ctx.upFrame(V3(x, y - sink, z), Vector3.yAxis:Lerp(n, tiltN), yaw)
	end
	-- a log must touch the ground at both ends, and both ends must be allowed
	if logLen then
		local half = logLen * 0.5 * scale * 0.92
		for _, sgn in ipairs({ -1, 1 }) do
			local e = cf * V3(half * sgn, 0, 0)
			local ey = Ctx.height(e.X, e.Z)
			if not ey or ey < e.Y - (extra.endDrop or 0.7) or ey > e.Y + 2.2 then
				return no(R, "logEndAir")
			end
			if Ctx.trailDistance(e.X, e.Z) < EX.trail.bush + 1.4 or Ctx.keptOut(e.X, e.Z, 1.4, false) then
				return no(R, "logEndKept")
			end
			local _, _, _, ewy, edep = Ctx.ground(e.X, e.Z)
			if ewy and edep > (extra.wetMax or EX.water.land) then
				return false
			end
			if occupied(S, e.X, e.Z, -1, 0, 1.3 * scale, "log") then
				return false
			end
		end
	end
	local visual = extra.visual or r > Ctx.VISUAL_R
	-- loot and runner's-cache clearings stay free by the whole bounding box (crowns, skirts and fronds too)
	if not visual and not Ctx.lootClear(asset, cf, scale) then
		return no(R, "lootClearing")
	end
	local m = Ctx.spawn(asset, cf, R.folder, { scale = scale, visualOnly = visual })
	if not m then
		return false
	end
	if extra.stretch then
		stretch(m, extra.stretch, u3, u4)
	end
	-- rocks, logs and stumps rest on the ground (no side hangs in the air) and never stand in a trail's walking space
	if not visual and (cls == "rock" or logLen or rule.kind == "Stump" or rule.kind == "StreamRocks") then
		Ctx.seat(m, if logLen then { share = 0.4, tol = 0.3, maxDrop = 1.2 } else { share = 0.5, tol = 0.3, maxDrop = 3 })
		local why = if Ctx.blocksTrail(m) then "blocksTrail" elseif Ctx.blocksWater(m, false) then "blocksDrinking" else nil
		if why then
			m:Destroy()
			Ctx.placed[asset] -= 1
			return no(R, why)
		end
	end
	S.occ:insert({ x = x, z = z, rule = R.id, spacing = spacing, solid = solid, cls = cls })
	if logLen then
		local third = logLen * scale / 3
		for _, sgn in ipairs({ -1, 1 }) do
			local e = cf * V3(third * sgn, 0, 0)
			S.occ:insert({ x = e.X, z = e.Z, rule = R.id, spacing = 0, solid = 1.3 * scale, cls = "log" })
		end
	end
	R.placed += 1
	if r < Ctx.PLAY_R then
		R.placedIn += 1
	end
	local info = Ctx.info(asset)
	S.tris += if info then info.tris else 0
	return true
end

local function hashString(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

-- Gorge logs: fallen across the stream ("a few across the stream or wedged between the walls"), each spanning the
-- water from bank to bank with both ends resting on the ground, away from trails and crossings.
local function gorgeLogs(S, R, target: number): number
	local Ctx, L = S.Ctx, S.L
	local samples = L.River.samples
	local rng = R.rng
	local lastS = -math.huge
	for i, smp in ipairs(samples) do
		if R.placed >= target then
			break
		end
		local u = rng:NextNumber()
		if smp.gorge == 1 and not smp.fall and not smp.cascade and smp.s - lastS > 22 and u < 0.9 then
			local p0, p1 = samples[max(i - 1, 1)], samples[min(i + 1, #samples)]
			local t = V3(p1.x - p0.x, 0, p1.z - p0.z)
			if t.Magnitude > 1e-3 then
				t = t.Unit
				local side = V3(-t.Z, 0, t.X)
				local c = V3(smp.x, 0, smp.z)
				local ends = {}
				for _, sgn in ipairs({ -1, 1 }) do
					for d = 1.5, 13, 0.5 do
						local q = c + side * (sgn * d)
						local gy = Ctx.height(q.X, q.Z)
						if gy and gy > smp.y + 0.5 then
							local rest = q + side * (sgn * 1.6)
							local ry = Ctx.height(rest.X, rest.Z)
							if ry and abs(ry - gy) < 2.5 then
								ends[sgn] = V3(rest.X, ry, rest.Z)
							end
							break
						end
					end
				end
				local A, B = ends[-1], ends[1]
				if A and B then
					local span = (V3(B.X, 0, B.Z) - V3(A.X, 0, A.Z)).Magnitude
					-- long enough that the log lies on both banks well past the water: a third of it at each end rests on
					-- ground (so it is held, not floating, wherever it is sampled 30% out from its middle)
					local want = max(span + 3.2, (span - 3.2 + 1.5) / 0.6)
					local name = if want <= 17 then "FallenLogA" else "FallenLogB"
					local s = want / LOG_LENGTH[name]
					if s >= 0.7 and s <= 1.3 and abs(B.Y - A.Y) < span * 0.35 then
						local axis = (B - A).Unit
						local up = (Vector3.yAxis - axis * axis.Y).Unit
						local mid = (A + B) / 2
						local cf = CFrame.fromMatrix(mid - up * (0.35 * s), axis, up)
						local clear = true
						for _, f in ipairs({ -0.5, 0, 0.5 }) do
							local q = mid + axis * (span * f)
							if Ctx.trailDistance(q.X, q.Z) < 5 then
								clear = false
							end
						end
						for _, cr in ipairs(L.Crossings) do
							if (V3(cr.position.X, 0, cr.position.Z) - V3(mid.X, 0, mid.Z)).Magnitude < 10 then
								clear = false
							end
						end
						if clear and Ctx.lootClear(name, cf, s) and not occupied(S, mid.X, mid.Z, R.id, 10, 1.3 * s, "log") then
							local m = Ctx.spawn(name, cf, R.folder, { scale = s })
							if m and Ctx.blocksTrail(m) then
								m:Destroy()
								Ctx.placed[name] -= 1
							elseif m then
								lastS = smp.s
								R.placed += 1
								R.placedIn += 1
								S.occ:insert({ x = mid.X, z = mid.Z, rule = R.id, spacing = 10, solid = 1.3 * s, cls = "log" })
								local info = Ctx.info(name)
								S.tris += if info then info.tris else 0
							end
						end
					end
				end
			end
			Ctx.yield()
		end
	end
	return R.placed
end

-- one rule in one biome: the seeded grid, then the fill. Returns (placed, placed inside the play radius, target).
local function runRule(S, biome: string, index: number, rule): (number, number, number)
	local Ctx, L = S.Ctx, S.L
	local key = biome .. "." .. rule.kind
	local extra = EXTRA[key] or {}
	local cls = rule.class
	local knob = (Scatter.DENSITY[cls] or 1) * Ctx.densityScale
	local dens = rule.density * knob * (extra.density or 1)
	local bb = Ctx.biomeBounds[biome]
	if dens <= 0 or not bb then
		return 0, 0, 0
	end
	local maxCount = extra.maxCount or math.huge
	-- the rule's target: its density over the biome's area inside the play radius (what ArenaLayout's numbers promise)
	local target = min(maxCount, rule.density * knob * Ctx.areaIn(biome) / 1000 * (extra.fill or 1))
	local band = extra.shoreBand or 0
	local function inBiome(x: number, z: number): boolean
		if Ctx.biomeAt(x, z) == biome then
			return true
		end
		if band > 0 then
			local c = L.Lake.center
			local d = V3(c.X - x, 0, c.Z - z)
			if d.Magnitude > 1e-3 then
				local q = V3(x, 0, z) + d.Unit * band
				return Ctx.biomeAt(q.X, q.Z) == biome
			end
		end
		return false
	end
	local R = {
		rule = rule,
		biome = biome,
		extra = extra,
		inBiome = inBiome,
		id = S.nextId,
		placed = 0,
		placedIn = 0,
		rej = {},
		rng = Random.new(Ctx.Seed * 7919 + hashString(key) * 131 + index * 977),
		folder = Ctx.folder(Ctx.out(outFolderName(rule)), biome),
	}
	S.nextId += 1
	if extra.special == "gorgeLogs" then
		gorgeLogs(S, R, target)
		return R.placed, R.placedIn, target, R.rej
	end
	local boostMax = max(rule.edgeBoost or 1, rule.cliffBoost or 1)
	local useStand = cls == "tree" or rule.kind == "YoungConifer"
	local standMax = if useStand then STAND_MAX else 1
	local cl = rule.cluster
	local avg = if cl then (cl.min + cl.max) / 2 else 1
	local cell = sqrt(1000 / (dens * boostMax * standMax / avg))
	local rng = R.rng
	local spread = extra.clusterSpread
	-- one seed: its acceptance weight (edge / cliff boosts, stand density, the rule's own weight, the meadow ramp, beds),
	-- then its clump; true once the rule is full
	local function seed(sx: number, sz: number, accept: number, members: number): boolean
		local cr = if cl then cl.radius * (if spread then spread[1] + (spread[2] - spread[1]) * rng:NextNumber() else 1) else 0
		if not inBiome(sx, sz) then
			return false
		end
		local w = 1
		if boostMax > 1 then
			local b = 1
			if rule.edgeBoost and L.forestEdgeDistance(V3(sx, 0, sz)) < 25 then
				b = max(b, rule.edgeBoost)
			end
			if rule.cliffBoost and L.distanceToCliff(V3(sx, 0, sz)) < 18 then
				b = max(b, rule.cliffBoost)
			end
			w *= b / boostMax
		end
		if useStand then
			w *= stand(Ctx.Seed, sx, sz) / STAND_MAX
		end
		if extra.weight then
			w *= extra.weight(Ctx, sx, sz)
		end
		if extra.ramp then
			local rr = sqrt(sx * sx + sz * sz)
			local edge = L.meadowEdge(L.angleOf(V3(sx, 0, sz)))
			w *= math.clamp(0.3 + 0.7 * (rr - 72) / max(edge - 72, 1), 0.3, 1)
		end
		if extra.patchy then
			local pz = extra.patchy
			local nz = math.noise(sx / pz.size + 3.17, sz / pz.size - 7.71, Ctx.Seed * 0.0013 + index * 0.37)
			w *= math.clamp(pz.floor + (nz + 0.3) * 1.7, 0, 1)
		end
		if accept < w then
			for _ = 1, members do
				local px, pz = sx, sz
				if cl then
					local a = rng:NextNumber() * TAU
					local rr = cr * sqrt(rng:NextNumber())
					px, pz = sx + math.cos(a) * rr, sz + math.sin(a) * rr
				end
				if tryPlace(S, R, px, pz) and R.placed >= maxCount then
					return true
				end
			end
		end
		return false
	end
	-- 1. the seeded grid (over the biome's bounds, grown by the shore band)
	local z = bb.z0 - band
	while z < bb.z1 + band do
		local x = bb.x0 - band
		while x < bb.x1 + band do
			local sx, sz = x + rng:NextNumber() * cell, z + rng:NextNumber() * cell
			local accept = rng:NextNumber()
			local members = if cl then rng:NextInteger(cl.min, cl.max) else 1
			if seed(sx, sz, accept, members) then
				return R.placed, R.placedIn, target, R.rej
			end
			Ctx.yield()
			x += cell
		end
		z += cell
	end
	-- 2. fill: exclusions (slopes, trails, rock, water, keep-outs) leave the grid short of the rule's density; seed more
	-- clumps at random over the biome until it reaches the target (inside the play radius) or the tries run out
	if not extra.noFill and R.placedIn < target then
		local tries = floor((target - R.placedIn) * (extra.fillTries or 20)) + 60
		local r2 = Ctx.PLAY_R * Ctx.PLAY_R
		for _ = 1, tries do
			if R.placedIn >= target then
				break
			end
			local sx = bb.x0 - band + rng:NextNumber() * (bb.x1 - bb.x0 + 2 * band)
			local sz = bb.z0 - band + rng:NextNumber() * (bb.z1 - bb.z0 + 2 * band)
			local accept = rng:NextNumber()
			local members = if cl then max(1, floor(rng:NextInteger(cl.min, cl.max) * 0.6 + 0.5)) else 1
			if sx * sx + sz * sz < r2 and seed(sx, sz, accept, members) then
				break
			end
			Ctx.yield()
		end
	end
	return R.placed, R.placedIn, target, R.rej
end

-- what already stands (other biomes on a one-biome run, cliffs, POIs, camps) goes into the occupancy hash
local function indexExisting(S, only: string?)
	local Ctx, L = S.Ctx, S.L
	local arena = Ctx.arena()
	local n = 0
	local function add(m: Model, solid: number, cls: string)
		local p = m:GetPivot().Position
		S.occ:insert({ x = p.X, z = p.Z, rule = 0, spacing = 0, solid = solid, cls = cls })
		n += 1
	end
	if only then
		for _, outName in ipairs({ "Forest", "Flora", "Rocks" }) do
			local f = arena:FindFirstChild(outName)
			if f then
				for _, sub in ipairs(f:GetChildren()) do
					if sub.Name ~= only then
						for _, m in ipairs(sub:GetChildren()) do
							if m:IsA("Model") then
								local t = TRUNK[m.Name]
								if t then
									add(m, t, if outName == "Forest" and m.Name ~= "ConiferYoung" and m.Name ~= "SaplingBroadleaf" then "tree" else "bush")
								elseif outName == "Rocks" or LOG_LENGTH[m.Name] or string.find(m.Name, "Stump", 1, true) then
									local ai = L.AssetInfo[m.Name]
									add(m, min(6, (if ai then ai.r else 2) * 0.8), "rock")
								end
							end
						end
					end
				end
			end
		end
	end
	-- cliff faces: three circles along the front of each piece
	local cliffs = arena:FindFirstChild("Cliffs")
	if cliffs then
		for _, m in ipairs(cliffs:GetChildren()) do
			if m:IsA("Model") then
				local cf = m:GetPivot()
				local size = m:GetExtentsSize()
				local w = size.X
				for _, t in ipairs({ -0.33, 0, 0.33 }) do
					local p = (cf * CFrame.new(w * t, 0, -size.Z * 0.3)).Position
					S.occ:insert({ x = p.X, z = p.Z, rule = 0, spacing = 0, solid = w / 6, cls = "rock" })
				end
				n += 1
			end
		end
	end
	-- POI and camp pieces; the big ones (the cabin, the tower, the bridge, the cave mouths) as circles over their whole
	-- footprint, so no tree or rock grows into a wall
	for _, name in ipairs({ "POIs", "Camps" }) do
		local f = arena:FindFirstChild(name)
		if f then
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("Model") then
					local ai = L.AssetInfo[d.Name]
					local r = (if ai then ai.r else 2)
					if r > 7 and not (d.Parent and d.Parent:IsA("Model")) then
						local cf, size = d:GetBoundingBox()
						for gx = -size.X / 2 + 3, size.X / 2 - 3 + 0.01, 5 do
							for gz = -size.Z / 2 + 3, size.Z / 2 - 3 + 0.01, 5 do
								local p = cf * V3(gx, 0, gz)
								S.occ:insert({ x = p.X, z = p.Z, rule = 0, spacing = 0, solid = 3.6, cls = "rock" })
							end
						end
						n += 1
					else
						add(d, min(6, r * 0.8), "rock")
					end
				end
			end
		end
	end
	return n
end

function Scatter.run(Ctx, only: string?): string
	local L = Ctx.Layout
	local S = { Ctx = Ctx, L = L, occ = Ctx.Hash.new(8), nextId = 1, tris = 0 }
	-- clear what this step owns
	for _, name in ipairs({ "Forest", "Flora", "Rocks" }) do
		local f = Ctx.out(name)
		for _, sub in ipairs(f:GetChildren()) do
			if not only or sub.Name == only then
				Ctx.clear(sub)
				sub:Destroy()
			end
		end
	end
	local indexed = indexExisting(S, only)
	local stats, total = {}, 0
	for pass = 1, 4 do
		for _, biome in ipairs(L.Biomes) do
			if not only or only == biome then
				local rules = Scatter.rulesFor(L, biome)
				-- within a pass the widest-spaced rules go first (oaks and snags before the dense conifers), so the big
				-- trees find room; each rule keeps its own seeded sequence (index i), so the order only settles who
				-- claims the ground first
				local order = {}
				for i, rule in ipairs(rules) do
					table.insert(order, { i = i, rule = rule })
				end
				table.sort(order, function(a, b)
					local sa, sb = a.rule.spacing or 0, b.rule.spacing or 0
					if pass == 1 and sa ~= sb then
						return sa > sb
					end
					return a.i < b.i
				end)
				for _, o in ipairs(order) do
					local i, rule = o.i, o.rule
					if passOf(rule) == pass and not SKIP[rule.kind] then
						Ctx.status(string.format("scatter pass %d: %s.%s", pass, biome, rule.kind), (pass - 1) / 4)
						local n, nIn, target, rej = runRule(S, biome, i, rule)
						total += n
						local why = ""
						if target >= 1 and nIn < target * 0.7 and rej then
							local list = {}
							for k, v in pairs(rej) do
								table.insert(list, { k, v })
							end
							table.sort(list, function(a, b)
								return a[2] > b[2]
							end)
							local top = {}
							for j = 1, min(3, #list) do
								table.insert(top, list[j][1] .. " " .. list[j][2])
							end
							why = " [refused: " .. table.concat(top, ", ") .. "]"
						end
						table.insert(stats, if target >= 1 then string.format("%s.%s %d/%.0f%s", biome, rule.kind, nIn, target, why) else string.format("%s.%s %d", biome, rule.kind, n))
					end
				end
			end
		end
	end
	return string.format("%d models (%d existing indexed), %.2fM mesh tris at full detail\n  %s", total, indexed, S.tris / 1e6, table.concat(stats, ", "))
end

return Scatter
