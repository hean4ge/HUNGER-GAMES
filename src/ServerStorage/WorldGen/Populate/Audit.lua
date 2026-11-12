--[[
	Populate.Audit - numbers and gameplay-safety checks for the set dressing (edit time).
	  report(Ctx) -> string   per output folder: models, parts, mesh triangles at full detail (template Tris), shadow
	                          casters, colliders, instances; the Lobby; enabled and shadowed local lights
	  verify(Ctx) -> string   read-only and precise (raycasts and part-shaped overlap probes on collision geometry):
	                          1 the plaza and the plates are clear      2 trails: no collider on the walking line
	                          3 crossings: the same across each         4 cave mouths: open from 10 out to 6 in
	                          5 loot markers: not inside a collider; reachable (a standing spot within the prompt
	                            range with a line of sight to the marker); resting on a surface
	                          6 runner caches: nothing solid or bushy within 6 studs below head height
	                          7 floating or buried scenery     8 Climbable OakA bark     9 crowns and trunks
	  looks(Ctx) -> string    10 eye-level cliff facets, 11 scatter fill vs ArenaLayout densities, 7b floating pieces
	                          in every folder, 12 loot and runner's-cache clearings by bounding box, 13 the Tor
	  fixLoot(Ctx) -> string  moves loot markers that scenery colliders block to the nearest clear, flat, reachable
	                          spot (seatLootMarkers-compatible: terrain or the SpirePlatform deck, slope < 26, r > 24).
	                          Never moves the Spire's niche markers or the runner's caches; reports them instead.
]]
local ServerStorage = game:GetService("ServerStorage")

local Audit = {}

local V3 = Vector3.new
local sqrt, min, max, floor, cos, sin = math.sqrt, math.min, math.max, math.floor, math.cos, math.sin

local OUT = { "Landmarks", "Plinths", "POIs", "Camps", "Cliffs", "Forest", "Flora", "Rocks", "Ambience" }
local CROWN_WORDS = { "Foliage", "Branches", "Leaves", "Canopy", "Crown", "Needles" }
local TREES = {
	SpruceA = true, SpruceB = true, FirA = true, PineA = true, ConiferYoung = true, BirchA = true, BirchB = true,
	OakA = true, SnagA = true, SnagB = true,
}

local function isCrown(name: string): boolean
	for _, w in ipairs(CROWN_WORDS) do
		if string.find(name, w, 1, true) then
			return true
		end
	end
	return false
end

local function tally(Ctx, root: Instance)
	local t = { models = 0, parts = 0, tris = 0, shadow = 0, collide = 0, inst = 0 }
	local desc = root:GetDescendants()
	t.inst = #desc
	for _, d in ipairs(desc) do
		if d:IsA("Model") then
			t.models += 1
			local tris = tonumber(d:GetAttribute("Tris"))
			if not tris then
				local info = Ctx.info(d.Name)
				tris = if info then info.tris else 0
			end
			t.tris += tris
		elseif d:IsA("BasePart") then
			t.parts += 1
			if d.CastShadow and d.Transparency < 1 then
				t.shadow += 1
			end
			if d.CanCollide then
				t.collide += 1
			end
		end
	end
	return t
end

function Audit.report(Ctx): string
	local arena = Ctx.arena()
	local lines = {}
	local T = { models = 0, parts = 0, tris = 0, shadow = 0, collide = 0, inst = 0 }
	for _, name in ipairs(OUT) do
		local f = arena:FindFirstChild(name)
		if f then
			local t = tally(Ctx, f)
			for k, v in pairs(t) do
				T[k] += v
			end
			table.insert(lines, string.format("  %-9s models %6d  parts %6d  tris %10d  shadow casters %6d  colliders %5d  instances %6d",
				name, t.models, t.parts, t.tris, t.shadow, t.collide, t.inst))
		end
	end
	table.insert(lines, 1, string.format("workspace.Arena: %d instances. Placed: %d models, %d parts, %.2fM mesh triangles at full detail, %d shadow casters, %d colliders",
		#arena:GetDescendants(), T.models, T.parts, T.tris / 1e6, T.shadow, T.collide))
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		local t = tally(Ctx, lobby)
		table.insert(lines, string.format("  Lobby     models %6d  parts %6d  tris %10d  shadow casters %6d  colliders %5d  instances %6d",
			t.models, t.parts, t.tris, t.shadow, t.collide, t.inst))
	end
	local lights, shadowed = 0, 0
	for _, root in ipairs({ arena, lobby }) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Light") and d.Enabled then
					lights += 1
					if d.Shadows then
						shadowed += 1
					end
				end
			end
		end
	end
	table.insert(lines, string.format("  local lights (arena + lobby): %d enabled, %d with shadows", lights, shadowed))
	return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------- probes
local Probe = {}
Probe.__index = Probe

local function folders(Ctx, names: { string }): { Instance }
	local arena = Ctx.arena()
	local list = {}
	for _, n in ipairs(names) do
		local f = arena:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

-- query helpers on the scenery's collision geometry
local function probes(Ctx)
	local P = setmetatable({}, Probe)
	P.scenery = folders(Ctx, { "Forest", "Flora", "Rocks", "Cliffs", "POIs", "Camps", "Landmarks", "Plinths", "SpirePlatform" })
	P.solid = OverlapParams.new()
	P.solid.FilterType = Enum.RaycastFilterType.Include
	P.solid.FilterDescendantsInstances = P.scenery
	P.solid.RespectCanCollide = true
	P.any = OverlapParams.new()
	P.any.FilterType = Enum.RaycastFilterType.Include
	P.any.FilterDescendantsInstances = folders(Ctx, { "Forest", "Flora", "Rocks", "Cliffs", "POIs", "Camps" })
	P.rayAll = RaycastParams.new()
	P.rayAll.FilterType = Enum.RaycastFilterType.Include
	local withTerrain = table.clone(P.scenery)
	table.insert(withTerrain, workspace.Terrain)
	P.rayAll.FilterDescendantsInstances = withTerrain
	P.rayAll.RespectCanCollide = true
	P.rayAll.IgnoreWater = true
	local function part(shape)
		local p = Instance.new("Part")
		p.Name = "PopulateAuditProbe"
		p.Shape = shape
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Parent = workspace
		return p
	end
	P.ball = part(Enum.PartType.Ball)
	P.box = part(Enum.PartType.Block)
	P.cyl = part(Enum.PartType.Cylinder)
	return P
end

function Probe:destroy()
	self.ball:Destroy()
	self.box:Destroy()
	self.cyl:Destroy()
end

function Probe:inBall(p: Vector3, r: number, params: OverlapParams?): { BasePart }
	self.ball.Size = V3(2 * r, 2 * r, 2 * r)
	self.ball.CFrame = CFrame.new(p)
	return workspace:GetPartsInPart(self.ball, params or self.solid)
end

function Probe:inBox(cf: CFrame, size: Vector3, params: OverlapParams?): { BasePart }
	self.box.Size = size
	self.box.CFrame = cf
	return workspace:GetPartsInPart(self.box, params or self.solid)
end

-- an upright cylinder (radius r, from y0 to y1) at (x, z)
function Probe:inCylinder(x: number, z: number, r: number, y0: number, y1: number, params: OverlapParams?): { BasePart }
	self.cyl.Size = V3(y1 - y0, 2 * r, 2 * r)
	self.cyl.CFrame = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
	return workspace:GetPartsInPart(self.cyl, params or self.solid)
end

local function owner(part: Instance): string
	local m = part:FindFirstAncestorWhichIsA("Model")
	local f = part:FindFirstAncestorWhichIsA("Folder")
	return (if m then m.Name else part.Name) .. "@" .. (if f then f.Name else "?")
end

local function where(p: Vector3): string
	return string.format("(%.0f, %.0f, %.0f)", p.X, p.Y, p.Z)
end

local function surfaceNear(P, x: number, z: number, y: number): RaycastResult?
	return workspace:Raycast(V3(x, y + 4, z), V3(0, -9, 0), P.rayAll)
end

-- room to stand at a surface point: no collider in a 1.6 x 4.2 x 1.6 box above it, no terrain in the way
local function canStand(P, g: RaycastResult): boolean
	if g.Normal.Y < 0.7 then
		return false
	end
	local base = g.Position
	if #P:inBox(CFrame.new(base + V3(0, 2.5, 0)), V3(1.6, 4.2, 1.6)) > 0 then
		return false
	end
	return workspace:Raycast(base + V3(0, 0.3, 0), V3(0, 4.5, 0), P.rayAll) == nil
end

-- a standing spot within reach of a loot marker (prompt range 8, pickup 10): 8 directions, up to 7 studs out, with a
-- clear line of sight from head height to the marker
local function reachable(P, mk: BasePart): (boolean, Vector3?)
	local c = mk.Position
	local bottom = (mk.CFrame * CFrame.new(0, -mk.Size.Y / 2, 0)).Position
	local half = max(mk.Size.X, mk.Size.Z) / 2
	for d = half + 1.2, 7, 1.3 do
		for k = 0, 7 do
			local a = k * math.pi / 4
			local p = bottom + V3(cos(a) * d, 0, sin(a) * d)
			local g = surfaceNear(P, p.X, p.Z, bottom.Y)
			if g and math.abs(g.Position.Y - bottom.Y) < 4.5 and canStand(P, g) then
				local eye = g.Position + V3(0, 4.5, 0)
				local hit = workspace:Raycast(eye, c - eye, P.rayAll)
				if not hit or (hit.Position - c).Magnitude < half + 0.6 then
					return true, g.Position
				end
			end
		end
	end
	return false, nil
end

local function markerBlocked(P, mk: BasePart): { BasePart }
	local hits = P:inBox(mk.CFrame * CFrame.new(0, 0.25, 0), mk.Size - V3(0.4, 0.7, 0.4))
	local out = {}
	for _, h in ipairs(hits) do
		if not mk:IsDescendantOf(h.Parent :: Instance) then
			table.insert(out, h)
		end
	end
	return out
end

function Audit.verify(Ctx): string
	local L = Ctx.Layout
	local arena = Ctx.arena()
	local P = probes(Ctx)
	local lines = {}
	local function add(s: string)
		table.insert(lines, s)
	end
	local ok, err = pcall(function()
		-- 1. the plaza and the plates
		local plaza = 0
		for _, h in ipairs(P:inCylinder(0, 0, 66, L.PlazaY + 1.2, L.PlazaY + 14, P.solid)) do
			local f = h:FindFirstAncestorWhichIsA("Folder")
			local m = h:FindFirstAncestorWhichIsA("Model")
			if not (f and (f.Name == "Plinths" or f.Name == "Landmarks")) and not (m and m.Name == "SpirePlatform") then
				plaza += 1
			end
		end
		local plates = 0
		local pl = arena:FindFirstChild("Plinths")
		if pl then
			for _, m in ipairs(pl:GetChildren()) do
				local st = m:FindFirstChild("Stand", true)
				if st and st:IsA("Attachment") then
					plates += #P:inCylinder(st.WorldPosition.X, st.WorldPosition.Z, 4, st.WorldPosition.Y + 0.3, st.WorldPosition.Y + 6, P.any)
				end
			end
		end
		add(string.format("1 plaza (r < 66, 1-14 studs up): scenery colliders %d; scenery parts over the 24 plates %d", plaza, plates))
		Ctx.yield()

		-- 2. trails: a collider on the walking line (a ball of radius 1 at hip height, every 4 studs)
		local samples, blocked, firstBad = 0, 0, {}
		for ti, trail in ipairs(L.Trails) do
			for s = 1, #trail - 1 do
				local a, b = trail[s], trail[s + 1]
				local steps = max(1, floor((b - a).Magnitude / 4))
				for k = 0, steps - 1 do
					local p = a:Lerp(b, k / steps)
					local y, _, _, wy = Ctx.ground(p.X, p.Z)
					if y and not wy then
						samples += 1
						local hits = P:inBall(V3(p.X, y + 2.6, p.Z), 1.0)
						if #hits > 0 then
							blocked += 1
							if #firstBad < 6 then
								table.insert(firstBad, L.TrailNames[ti] .. " " .. where(V3(p.X, y, p.Z)) .. " " .. owner(hits[1]))
							end
						end
					end
				end
			end
			Ctx.yield()
		end
		add(string.format("2 trails: %d of %d samples have a collider on the walking line%s", blocked, samples, if #firstBad > 0 then (": " .. table.concat(firstBad, "; ")) else ""))
		-- 2b. the verifier's method: a player-sized box (2 x 3.6, 1 stud above the ground) swept along every trail in
		-- 4-stud segments, on the centreline and 2.5 studs to each side
		add("2b trails, box sweeps: " .. Audit.trailSweeps(Ctx, P, { 0, -2.5, 2.5 }))

		-- 3. crossings: the walking line across each (fords at the water, the log and bridge on their decks)
		local notes = {}
		for _, c in ipairs(L.Crossings) do
			local along = V3(c.direction.X, 0, c.direction.Z).Unit
			local bad, by = 0, nil
			local half = c.span * 0.5 + 3
			local t = -half
			while t <= half do
				local p = c.position + along * t
				local y, _, _, wy = Ctx.ground(p.X, p.Z)
				local walk = wy or y or c.position.Y
				if c.kind == "Log" or c.kind == "Footbridge" then
					local g = workspace:Raycast(V3(p.X, c.position.Y + 8, p.Z), V3(0, -30, 0), P.rayAll)
					walk = if g then g.Position.Y else c.position.Y
				end
				local hits = P:inBall(V3(p.X, walk + 2.8, p.Z), 0.9)
				if #hits > 0 then
					bad += 1
					by = by or owner(hits[1])
				end
				t += 2
			end
			table.insert(notes, c.name .. " " .. bad .. (if by then (" (" .. by .. ")") else ""))
		end
		add("3 crossings, blocked samples: " .. table.concat(notes, ", "))
		add("3b footbridge: " .. Audit.footbridge(Ctx, P))
		Ctx.yield()

		-- 4. cave mouths: open along the tunnel axis at head height, from 10 studs outside to 6 inside
		notes = {}
		for _, cave in ipairs(L.Caves) do
			local m, q = cave.path[1], cave.path[2]
			local out = V3(m.X - q.X, 0, m.Z - q.Z).Unit
			local bad, by = 0, nil
			for d = -6, 10, 2 do
				local p = V3(m.X, m.Y, m.Z) + out * d
				local fy = Ctx.heightBelow(p + V3(0, 5, 0), 14) or m.Y
				local hits = P:inBall(V3(p.X, fy + 3.2, p.Z), 1.3)
				if #hits > 0 then
					bad += 1
					by = by or owner(hits[1])
				end
			end
			table.insert(notes, cave.name .. " " .. bad .. (if by then (" (" .. by .. ")") else ""))
		end
		add("4 cave mouths, blocked samples (of 9): " .. table.concat(notes, ", "))

		-- 5. loot markers
		local markers = Ctx.lootMarkers()
		local inside, unreach, floating = {}, {}, {}
		for i, mk in ipairs(markers) do
			local hits = markerBlocked(P, mk)
			if #hits > 0 then
				table.insert(inside, mk.Name .. where(mk.Position) .. " in " .. owner(hits[1]))
			end
			local bottom = (mk.CFrame * CFrame.new(0, -mk.Size.Y / 2, 0)).Position
			if not workspace:Raycast(bottom + V3(0, 1, 0), V3(0, -3, 0), P.rayAll) then
				table.insert(floating, mk.Name .. where(mk.Position))
			end
			if not reachable(P, mk) then
				table.insert(unreach, mk.Name .. where(mk.Position))
			end
			if i % 15 == 0 then
				Ctx.yield()
			end
		end
		local function list(t)
			if #t == 0 then
				return ""
			end
			local s = {}
			for i = 1, min(#t, 8) do
				s[i] = t[i]
			end
			return " (" .. table.concat(s, "; ") .. (if #t > 8 then "; ..." else "") .. ")"
		end
		add(string.format("5 loot markers %d: inside a collider %d%s; no standing spot within reach %d%s; not resting on a surface %d%s",
			#markers, #inside, list(inside), #unreach, list(unreach), #floating, list(floating)))

		-- 6. runner caches: nothing solid or bushy within 6 studs below head height (tree crowns overhead are fine)
		notes = {}
		for i, c in ipairs(Ctx.runnerCaches()) do
			local y = Ctx.height(c.X, c.Z) or c.Y
			local seen = {}
			for _, h in ipairs(P:inCylinder(c.X, c.Z, 6, y + 0.4, y + 6, P.any)) do
				local m = h:FindFirstAncestorWhichIsA("Model")
				if not (isCrown(h.Name) and m and TREES[m.Name]) then
					seen[owner(h)] = true
				end
			end
			local names = {}
			for o in pairs(seen) do
				table.insert(names, o)
			end
			table.insert(notes, i .. ":" .. (if #names == 0 then "clear" else table.concat(names, "+")))
		end
		add("6 runner caches within 6 studs: " .. table.concat(notes, " "))
		Ctx.yield()

		-- 7. floating / buried
		local fl = { trees = 0, treeFloat = 0, treeBuried = 0, rocks = 0, rockFloat = 0, flora = 0, floraFloat = 0, floraBuried = 0 }
		local worst, buriedNames = {}, {}
		local function lowestPart(m: Model): number
			local lo = math.huge
			for _, p in ipairs(m:GetChildren()) do
				if p:IsA("BasePart") and p.Transparency < 1 then
					local cf, s = p.CFrame, p.Size
					local ext = math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
					lo = min(lo, cf.Position.Y - ext)
				end
			end
			return lo
		end
		for _, fname in ipairs({ "Forest", "Rocks", "Flora" }) do
			local f = arena:FindFirstChild(fname)
			if f then
				local k = 0
				for _, m in ipairs(f:GetDescendants()) do
					if m:IsA("Model") then
						k += 1
						local p = m:GetPivot().Position
						if TREES[m.Name] then
							fl.trees += 1
							local lo, hi = math.huge, -math.huge
							for j = 0, 3 do
								local a = j * math.pi / 2
								local y = Ctx.height(p.X + cos(a), p.Z + sin(a))
								if y then
									lo, hi = min(lo, y), max(hi, y)
								end
							end
							if p.Y - lo > 0.6 then
								fl.treeFloat += 1
								if #worst < 5 then
									table.insert(worst, string.format("%s float %.1f %s", m.Name, p.Y - lo, where(p)))
								end
							end
							if hi - p.Y > 3.5 then
								fl.treeBuried += 1
							end
						elseif fname == "Flora" then
							if k % 3 == 0 then
								fl.flora += 1
								local y, _, _, wy = Ctx.ground(p.X, p.Z)
								if y and not wy then
									if p.Y - y > 0.3 then
										fl.floraFloat += 1
									elseif y - p.Y > 1.2 then
										fl.floraBuried += 1
										buriedNames[m.Name] = (buriedNames[m.Name] or 0) + 1
									end
								end
							end
						else
							fl.rocks += 1
							local y = Ctx.height(p.X, p.Z)
							if y and lowestPart(m) > y + 0.15 then
								fl.rockFloat += 1
								if #worst < 8 then
									table.insert(worst, string.format("%s float %.1f %s", m.Name, lowestPart(m) - y, where(p)))
								end
							end
						end
						if k % 200 == 0 then
							Ctx.yield()
						end
					end
				end
			end
		end
		local bn = {}
		for n, c in pairs(buriedNames) do
			table.insert(bn, n .. " " .. c)
		end
		add(string.format("7 trees %d: floating > 0.6 %d, trunk buried > 3.5 %d; rocks/logs/stumps %d: base above ground %d; flora sampled %d: floating > 0.3 %d, pivot > 1.2 under the ground at its centre %d%s%s",
			fl.trees, fl.treeFloat, fl.treeBuried, fl.rocks, fl.rockFloat, fl.flora, fl.floraFloat, fl.floraBuried,
			if #bn > 0 then (" (" .. table.concat(bn, ", ") .. ": upright plants on slopes, sunk to their lowest side)") else "",
			if #worst > 0 then (" [" .. table.concat(worst, "; ") .. "]") else ""))

		-- 8 and 9: Climbable oaks, crowns and trunks
		local oaks, oakOk, trees, crownBad, trunkBad, visual = 0, 0, 0, 0, 0, 0
		local lobby = workspace:FindFirstChild("Lobby")
		for _, root in ipairs({ arena:FindFirstChild("Forest"), arena:FindFirstChild("POIs"), lobby }) do
			if root then
				for _, m in ipairs(root:GetDescendants()) do
					if m:IsA("Model") and TREES[m.Name] then
						trees += 1
						local hasTrunk = false
						for _, p in ipairs(m:GetChildren()) do
							if p:IsA("BasePart") then
								if isCrown(p.Name) then
									if p.CanQuery then
										crownBad += 1
									end
								elseif p.CanQuery then
									hasTrunk = true
								end
							end
						end
						local pv = m:GetPivot().Position
						local outside = root ~= lobby and V3(pv.X, 0, pv.Z).Magnitude > Ctx.VISUAL_R
						if outside then
							visual += 1
						elseif not hasTrunk then
							trunkBad += 1
						end
						if m.Name == "OakA" then
							oaks += 1
							local bark = m:FindFirstChild("OakA_Bark")
							if bark and bark:HasTag("Climbable") and bark.CanQuery and bark.CanCollide then
								oakOk += 1
							end
						end
					end
				end
			end
		end
		add(string.format("8 OakA %d: Climbable + queryable + colliding bark %d", oaks, oakOk))
		add(string.format("9 trees %d: crown parts with CanQuery on %d; trees in play without a queryable trunk %d (%d visual-only beyond r %d)",
			trees, crownBad, trunkBad, visual, Ctx.VISUAL_R))
	end)
	P:destroy()
	if not ok then
		add("verify FAILED: " .. tostring(err))
	end
	return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------- sweeps and look checks
local SOLID_FOLDERS = { "Forest", "Rocks", "Cliffs", "POIs", "Camps", "Landmarks", "Plinths" }
local FLORA = {
	GrassForest = true, GrassTallA = true, GrassTallB = true, FlowersA = true, FlowersB = true, FernA = true,
	FernB = true, MossPatch = true, MushroomsA = true, ReedsA = true, BushA = true, BushB = true, BerryBush = true,
	SaplingBroadleaf = true,
}
-- placed whole (buildings on posts and sills, hung lanterns, the Spire and plinths): not seat-checked
local NOT_SEATED = { HunterCabin = true, Watchtower = true, Footbridge = true, Lantern = true, Spire = true, Plinth = true }

local function solidRay(Ctx): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = folders(Ctx, SOLID_FOLDERS)
	p.RespectCanCollide = true
	return p
end

local function solidOverlap(Ctx): OverlapParams
	local o = OverlapParams.new()
	o.FilterType = Enum.RaycastFilterType.Include
	o.FilterDescendantsInstances = folders(Ctx, SOLID_FOLDERS)
	o.RespectCanCollide = true
	return o
end

-- A player-sized box sweep from a to b (box centres): the verifier's method. The box is `w` wide and 3.6 tall (the
-- callers put its bottom 1 stud above the walking surface); an overlap test at the start catches what a sweep that
-- starts inside a part would miss. Returns the first part met, or nil.
local function sweep(P, a: Vector3, b: Vector3, w: number, rp: RaycastParams, op: OverlapParams): BasePart?
	local dir = b - a
	if dir.Magnitude < 0.05 then
		return nil
	end
	local cf = CFrame.lookAt(a, b)
	local size = V3(w, 3.6, 0.4)
	local inside = P:inBox(cf, size, op)
	if #inside > 0 then
		return inside[1]
	end
	local hit = workspace:Blockcast(cf, size, dir, rp)
	return if hit then hit.Instance :: BasePart else nil
end

-- 2 trails: box sweeps (2 x 3.6) along every trail, centreline and `offsets` to each side; segments are 4 studs
function Audit.trailSweeps(Ctx, P, offsets: { number }?): string
	local L = Ctx.Layout
	local rp, op = solidRay(Ctx), solidOverlap(Ctx)
	local lines = {}
	for _, off in ipairs(offsets or { 0 }) do
		local segs, blocked, notes, byOwner = 0, 0, {}, {}
		for ti, trail in ipairs(L.Trails) do
			local pts = {}
			for s = 1, #trail - 1 do
				local a, b = trail[s], trail[s + 1]
				local n = max(1, math.ceil((b - a).Magnitude / 4))
				for k = 0, n - 1 do
					table.insert(pts, a:Lerp(b, k / n))
				end
			end
			table.insert(pts, trail[#trail])
			local prev = nil
			for i, p in ipairs(pts) do
				local q = p
				if off ~= 0 then
					local a, b = pts[max(1, i - 1)], pts[min(#pts, i + 1)]
					local t = V3(b.X - a.X, 0, b.Z - a.Z)
					if t.Magnitude > 1e-3 then
						t = t.Unit
						q = p + V3(-t.Z, 0, t.X) * off
					end
				end
				local y = Ctx.ground(q.X, q.Z)
				if y then
					local c = V3(q.X, y + 2.8, q.Z)
					if prev then
						segs += 1
						local h = sweep(P, prev, c, 2, rp, op)
						if h then
							blocked += 1
							local o = owner(h)
							byOwner[o] = (byOwner[o] or 0) + 1
							if #notes < 6 then
								table.insert(notes, string.format("%s %s %s", L.TrailNames[ti], where(c), o))
							end
						end
					end
					prev = c
				else
					prev = nil
				end
			end
			Ctx.yield()
		end
		table.insert(lines, string.format("offset %+.1f: %d of %d segments blocked%s", off, blocked, segs, if #notes > 0 then (" (" .. table.concat(notes, "; ") .. ")") else ""))
	end
	return table.concat(lines, "; ")
end

-- the footbridge: the deck surface every stud along its axis (rays down onto the bridge and the rims), then a 2 x 3.6
-- box swept along it 1 stud above the deck, from 6 studs before EndA to 6 studs past EndB; and the headroom under the
-- end frames' cross logs
function Audit.footbridge(Ctx, P): string
	local L = Ctx.Layout
	local c = nil
	for _, x in ipairs(L.Crossings) do
		if x.kind == "Footbridge" then
			c = x
		end
	end
	local pois = Ctx.arena():FindFirstChild("POIs")
	local g = pois and pois:FindFirstChild("GorgeFootbridge")
	local bridge = g and g:FindFirstChild("Footbridge")
	if not (c and bridge) then
		return "no footbridge"
	end
	local along = V3(c.direction.X, 0, c.direction.Z).Unit
	local deck = RaycastParams.new()
	deck.FilterType = Enum.RaycastFilterType.Include
	deck.FilterDescendantsInstances = { bridge, workspace.Terrain }
	deck.RespectCanCollide = true
	local rp, op = solidRay(Ctx), solidOverlap(Ctx)
	local half = c.span * 0.5 + 6
	local prev, blocked, firstBad, gaps, lo, hi = nil, 0, nil, 0, math.huge, -math.huge
	for t = -half, half, 1 do
		local p = c.position + along * t
		local hit = workspace:Raycast(V3(p.X, c.position.Y + 10, p.Z), V3(0, -40, 0), deck)
		if hit then
			local cpos = V3(p.X, hit.Position.Y + 2.8, p.Z)
			lo, hi = min(lo, hit.Position.Y), max(hi, hit.Position.Y)
			if prev then
				local h = sweep(P, prev, cpos, 2, rp, op)
				if h then
					blocked += 1
					firstBad = firstBad or string.format("%s at t %+.0f", owner(h), t)
				end
			end
			prev = cpos
		else
			gaps += 1
			prev = nil
		end
	end
	local up = RaycastParams.new()
	up.FilterType = Enum.RaycastFilterType.Include
	up.FilterDescendantsInstances = { bridge }
	local clear = {}
	for _, n in ipairs({ "EndA", "EndB" }) do
		local a = bridge:FindFirstChild(n, true)
		if a and a:IsA("Attachment") then
			local best = math.huge
			for dt = -3, 3, 0.5 do
				for side = -1.5, 1.5, 0.75 do
					local q = a.WorldPosition + along * dt + V3(-along.Z, 0, along.X) * side
					local floor0 = workspace:Raycast(q + V3(0, 3, 0), V3(0, -8, 0), deck)
					if floor0 then
						local roof = workspace:Raycast(floor0.Position + V3(0, 0.2, 0), V3(0, 12, 0), up)
						if roof then
							best = min(best, roof.Position.Y - floor0.Position.Y)
						end
					end
				end
			end
			table.insert(clear, string.format("%s %s", n, if best < math.huge then string.format("%.1f", best) else "open to 12"))
		end
	end
	return string.format("deck sampled over %d studs (deck y %.1f..%.1f, %d gaps), 2 x 3.6 sweep blocked %d%s; headroom under the end frames: %s",
		math.floor(half * 2), lo, hi, gaps, blocked, if firstBad then (" (" .. firstBad .. ")") else "", table.concat(clear, ", "))
end

-- 7b floating: every solid piece that is placed on the ground (rocks, logs, stumps, cliff faces, outcrops, scree, POI
-- and camp pieces; trees, cards and the buildings aside). Five support samples (the centre and 4 at 30% of the box out)
-- like the verifier's, and the median of 16 columns (a visible gap on one side)
function Audit.floating(Ctx): string
	local arena = Ctx.arena()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Include
	ground.FilterDescendantsInstances = { workspace.Terrain }
	ground.IgnoreWater = true
	local function five(m: Model): (number, number)
		local cf, size = m:GetBoundingBox()
		local yExt = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
		params.FilterDescendantsInstances = { m }
		local n, worst = 0, math.huge
		for _, q in ipairs({ { 0, 0 }, { 0.3, 0 }, { -0.3, 0 }, { 0, 0.3 }, { 0, -0.3 } }) do
			local w = cf * V3(q[1] * size.X, 0, q[2] * size.Z)
			local hit = workspace:Raycast(V3(w.X, cf.Y - yExt - 1, w.Z), V3(0, 2 * yExt + 2, 0), params)
			if hit then
				local g = workspace:Raycast(V3(w.X, cf.Y + yExt + 1, w.Z), V3(0, -2 * yExt - 60, 0), ground)
				if g then
					n += 1
					worst = min(worst, hit.Position.Y - g.Position.Y)
				end
			end
		end
		return n, worst
	end
	local per = {}
	local list = {}
	local total, allFloat, medianFloat = 0, 0, 0
	for _, fname in ipairs({ "Rocks", "Forest", "POIs", "Camps", "Cliffs" }) do
		local f = arena:FindFirstChild(fname)
		local k = 0
		if f then
			for _, m in ipairs(f:GetDescendants()) do
				if m:IsA("Model") and not TREES[m.Name] and not FLORA[m.Name] and not NOT_SEATED[m.Name]
					and not (m.Parent and m.Parent:IsA("Model")) then
					local pv = m:GetPivot().Position
					if (fname ~= "Forest" or string.find(m.Name, "Log", 1, true) or string.find(m.Name, "Stump", 1, true))
						and pv.X * pv.X + pv.Z * pv.Z < 650 * 650 then
						k += 1
						total += 1
						local n, worst = five(m)
						local gaps = Ctx.gaps(m, { grid = 4 })
						table.sort(gaps)
						local med = if #gaps > 0 then gaps[math.ceil(#gaps / 2)] else -1
						local e = per[fname] or { n = 0, all = 0, med = 0 }
						per[fname] = e
						e.n += 1
						if n > 0 and worst > 0.5 then
							allFloat += 1
							e.all += 1
							table.insert(list, { m = m, g = worst, f = fname })
						end
						if med > 0.5 then
							medianFloat += 1
							e.med += 1
							if not (n > 0 and worst > 0.5) then
								table.insert(list, { m = m, g = med, f = fname, median = true })
							end
						end
						if k % 60 == 0 then
							Ctx.yield()
						end
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.g > b.g
	end)
	local parts, worstNotes = {}, {}
	for name, e in pairs(per) do
		table.insert(parts, string.format("%s %d/%d/%d", name, e.all, e.med, e.n))
	end
	table.sort(parts)
	for i = 1, min(8, #list) do
		local it = list[i]
		table.insert(worstNotes, string.format("%s@%s %s %.1f%s", it.m.Name, it.f, where(it.m:GetPivot().Position), it.g, if it.median then " (median)" else ""))
	end
	return string.format("%d pieces: floating > 0.5 at all 5 support samples %d; median of 16 columns > 0.5 %d (per folder all/median/n: %s)%s",
		total, allFloat, medianFloat, table.concat(parts, ", "), if #worstNotes > 0 then (" [" .. table.concat(worstNotes, "; ") .. "]") else "")
end

-- the bounding box of a model projected on the ground, as a rectangle in a yaw-only frame
local function boxRect(cf: CFrame, size: Vector3)
	local lv = cf.LookVector
	local fl = V3(lv.X, 0, lv.Z)
	if fl.Magnitude < 0.05 then
		fl = V3(cf.UpVector.X, 0, cf.UpVector.Z)
		if fl.Magnitude < 0.05 then
			fl = V3(0, 0, -1)
		end
	end
	local o = V3(cf.X, 0, cf.Z)
	local base = CFrame.lookAt(o, o + fl.Unit)
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, sx in ipairs({ -0.5, 0.5 }) do
		for _, sy in ipairs({ -0.5, 0.5 }) do
			for _, sz in ipairs({ -0.5, 0.5 }) do
				local w = cf * V3(size.X * sx, size.Y * sy, size.Z * sz)
				local l = base:PointToObjectSpace(V3(w.X, 0, w.Z))
				x0, x1, z0, z1 = min(x0, l.X), max(x1, l.X), min(z0, l.Z), max(z1, l.Z)
			end
		end
	end
	return base, x0, x1, z0, z1
end

-- 12 clearings by bounding box: each loot marker's clearing (crates 4.5, ground items 3) and each runner's cache (6)
-- against every scenery model's ground footprint (CanQuery-off flora included); the caches' landmarks; and whether
-- each cache's crate (1.5 up) and pole top (10 up) can be seen from the eye (4.8 over the Stand) of its nearest plate
-- (terrain only, and terrain plus scenery)
function Audit.clearings(Ctx): string
	local L = Ctx.Layout
	local arena = Ctx.arena()
	local hash = Ctx.Hash.new(16)
	local n = 0
	for _, fname in ipairs({ "Forest", "Flora", "Rocks", "Cliffs", "POIs", "Camps" }) do
		local f = arena:FindFirstChild(fname)
		if f then
			for _, m in ipairs(f:GetDescendants()) do
				if m:IsA("Model") and not (m.Parent and m.Parent:IsA("Model")) then
					local cf, size = m:GetBoundingBox()
					local base, x0, x1, z0, z1 = boxRect(cf, size)
					hash:insert({ x = cf.X, z = cf.Z, base = base, x0 = x0, x1 = x1, z0 = z0, z1 = z1, m = m, f = fname, reach = max(-x0, x1, -z0, z1) })
					n += 1
					if n % 400 == 0 then
						Ctx.yield()
					end
				end
			end
		end
	end
	local function overlaps(x: number, z: number, r: number, filter): { any }
		local out = {}
		hash:any(x, z, r + 40, function(it)
			local dx, dz = it.x - x, it.z - z
			if dx * dx + dz * dz < (r + it.reach + 1) ^ 2 and (not filter or filter(it)) then
				if Ctx.rectDistance(it.base, it.x0, it.x1, it.z0, it.z1, x, z) < r then
					table.insert(out, it)
				end
			end
			return false
		end)
		return out
	end
	local crates, grounds, crateBad, groundBad, byName = 0, 0, 0, 0, {}
	local crateRock, groundRock, rockNames = 0, 0, {}
	for i, mk in ipairs(Ctx.lootMarkers()) do
		local crate = mk:GetAttribute("Kind") == "Crate"
		local runner = mk:GetAttribute("Runner") == true or string.sub(mk.Name, 1, 11) == "RunnerCache"
		if not runner then
			local r = if crate then 4.5 else 3
			local hits = overlaps(mk.Position.X, mk.Position.Z, r, function(it)
				-- the marker's own building (a crate inside the cabin or the tower) is its setting, not clutter
				return not (it.f == "POIs" and (it.m.Name == "HunterCabin" or it.m.Name == "Watchtower"))
			end)
			if crate then
				crates += 1
			else
				grounds += 1
			end
			-- foliage (trees, bushes, ferns, grass, flowers: what could hide the loot) apart from rock and props (whose
			-- collision is checked precisely by verify: not inside, a standing spot in reach with a line of sight)
			local leafy, rocky = 0, 0
			for _, it in ipairs(hits) do
				if TREES[it.m.Name] or FLORA[it.m.Name] then
					leafy += 1
					byName[it.m.Name] = (byName[it.m.Name] or 0) + 1
				else
					rocky += 1
					rockNames[it.m.Name] = (rockNames[it.m.Name] or 0) + 1
				end
			end
			if leafy > 0 then
				if crate then
					crateBad += 1
				else
					groundBad += 1
				end
			end
			if rocky > 0 then
				if crate then
					crateRock += 1
				else
					groundRock += 1
				end
			end
		end
		if i % 20 == 0 then
			Ctx.yield()
		end
	end
	local names = {}
	for k, v in pairs(byName) do
		table.insert(names, k .. " " .. v)
	end
	table.sort(names)
	local rnames = {}
	for k, v in pairs(rockNames) do
		table.insert(rnames, k .. " " .. v)
	end
	table.sort(rnames)
	local caches = {}
	local land = {}
	local pois = arena:FindFirstChild("POIs")
	local lm = pois and pois:FindFirstChild("RunnerCacheLandmarks")
	if lm then
		for _, m in ipairs(lm:GetChildren()) do
			local tag = m:GetAttribute("RunnerCache")
			if tag ~= nil then
				land[tostring(tag)] = m.Name
			end
		end
	end
	local terrainOnly = RaycastParams.new()
	terrainOnly.FilterType = Enum.RaycastFilterType.Include
	terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
	terrainOnly.IgnoreWater = true
	local withScenery = RaycastParams.new()
	withScenery.FilterType = Enum.RaycastFilterType.Include
	local sceneryList = folders(Ctx, { "Forest", "Flora", "Rocks", "Cliffs", "POIs", "Camps" })
	table.insert(sceneryList, workspace.Terrain)
	withScenery.FilterDescendantsInstances = sceneryList
	withScenery.IgnoreWater = true
	local plinths = arena:FindFirstChild("Plinths")
	for i, c in ipairs(Ctx.runnerCaches()) do
		local y = Ctx.height(c.X, c.Z) or c.Y
		local hits = overlaps(c.X, c.Z, 6, nil)
		local who = {}
		for _, it in ipairs(hits) do
			who[it.m.Name] = true
		end
		local wl = {}
		for k in pairs(who) do
			table.insert(wl, k)
		end
		local best, bd = 1, math.huge
		for pi = 1, #L.Plates do
			local d = (L.Plates[pi].Position - V3(c.X, L.PlazaY, c.Z)).Magnitude
			if d < bd then
				bd, best = d, pi
			end
		end
		-- the contender's eye on the plate: 4.8 over the plinth's Stand (the plinth at rest, where it stands for the
		-- countdown once it has risen)
		local eye = L.Plates[best].Position + V3(0, 1.5 + 4.8 + (L.PlateTube.platformTop or 0.6), 0)
		local pl = plinths and plinths:FindFirstChild(string.format("Plinth%02d", best))
		local st = pl and pl:FindFirstChild("Stand", true)
		if st and st:IsA("Attachment") then
			eye = st.WorldPosition + V3(0, 4.8, 0)
		end
		local function seen(target: Vector3, params: RaycastParams): boolean
			local hit = workspace:Raycast(eye, target - eye, params)
			return hit == nil or (hit.Position - target).Magnitude < 1.5
		end
		local crateP, poleP = V3(c.X, y + 1.5, c.Z), V3(c.X, y + 10, c.Z)
		local cache = (L.RunnerCaches[i] and L.RunnerCaches[i].name) or ("RunnerCache_" .. i)
		table.insert(caches, string.format("%d: clear %s; landmark %s; from plate %d crate %s/%s pole %s/%s", i,
			if #wl == 0 then "yes" else ("NO (" .. table.concat(wl, "+") .. ")"),
			land[cache] or land[tostring(i)] or "none",
			best, if seen(crateP, terrainOnly) then "seen" else "hidden", if seen(crateP, withScenery) then "seen" else "hidden",
			if seen(poleP, terrainOnly) then "seen" else "hidden", if seen(poleP, withScenery) then "seen" else "hidden"))
	end
	return string.format("loot clearings overlapped by a foliage footprint: crates %d of %d, ground items %d of %d%s; by a rock or prop footprint (collision checked precisely in verify 5): crates %d, ground items %d%s\n  runner's caches (clear within 6 by footprint; landmark; seen from the nearest plate, terrain / terrain + scenery):\n    %s",
		crateBad, crates, groundBad, grounds, if #names > 0 then (" (" .. table.concat(names, ", ") .. ")") else "",
		crateRock, groundRock, if #rnames > 0 then (" (" .. table.concat(rnames, ", ") .. ")") else "", table.concat(caches, "\n    "))
end

-- 10 eye-level cliff facets (the verifier's method): observers on flat ground (6-stud grid, slope under 15 degrees, not
-- under water) in the Gorge and the Cliffs; 16 level rays 5.2 studs up, 45 long. Of the rays that end on a steep
-- surface (normal.Y < 0.643) other than a tree, the share that meets bare terrain.
function Audit.facets(Ctx): string
	local L = Ctx.Layout
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	params.IgnoreWater = true
	local cos15 = cos(math.rad(15))
	local lines = {}
	for _, biome in ipairs({ "Gorge", "Cliffs" }) do
		local bb = Ctx.biomeBounds[biome]
		local obs, steep, bare, cliff, other, tree = 0, 0, 0, 0, 0, 0
		if bb then
			for x = math.floor(bb.x0 / 6) * 6, bb.x1, 6 do
				for z = math.floor(bb.z0 / 6) * 6, bb.z1, 6 do
					if x * x + z * z < L.PlayRadius * L.PlayRadius and L.getBiome(V3(x, 0, z)) == biome then
						local y, nrm, _, wy = Ctx.ground(x, z)
						if y and not wy and nrm.Y > cos15 then
							obs += 1
							local eye = V3(x, y + 5.2, z)
							for k = 0, 15 do
								local a = k * math.pi / 8
								local h = workspace:Raycast(eye, V3(cos(a), 0, sin(a)) * 45, params)
								if h and h.Normal.Y < 0.643 then
									if h.Instance == workspace.Terrain then
										steep += 1
										bare += 1
									else
										local m = h.Instance:FindFirstAncestorWhichIsA("Model")
										if m and TREES[m.Name] then
											tree += 1
										else
											steep += 1
											if m and string.find(m.Name, "CliffFace", 1, true) then
												cliff += 1
											else
												other += 1
											end
										end
									end
								end
							end
						end
					end
				end
				Ctx.yield()
			end
		end
		table.insert(lines, string.format("%s: %d observers; steep hits (trees aside) %d: bare terrain %d (%.0f%%), CliffFace %d, other rock %d; trunks %d",
			biome, obs, steep, bare, if steep > 0 then bare / steep * 100 else 0, cliff, other, tree))
	end
	return table.concat(lines, "; ")
end

-- 11 scatter fill: per rule, models placed (pivot inside the play radius) against density x the biome's area inside
-- the play radius; and the forest's trees per 40 x 40 cell
function Audit.density(Ctx): string
	local L = Ctx.Layout
	local Scatter = require(script.Parent:FindFirstChild("Scatter"))
	local arena = Ctx.arena()
	local counts = {}
	local trees = {}
	local r2 = L.PlayRadius * L.PlayRadius
	for _, fname in ipairs({ "Forest", "Flora", "Rocks" }) do
		local f = arena:FindFirstChild(fname)
		if f then
			for _, sub in ipairs(f:GetChildren()) do
				local cb = counts[sub.Name] or {}
				counts[sub.Name] = cb
				for _, m in ipairs(sub:GetChildren()) do
					local p = m:GetPivot().Position
					if p.X * p.X + p.Z * p.Z < r2 then
						cb[m.Name] = (cb[m.Name] or 0) + 1
						if sub.Name == "Forest" and TREES[m.Name] and m.Name ~= "ConiferYoung" then
							local k = math.floor(p.X / 40) * 1000 + math.floor(p.Z / 40)
							trees[k] = (trees[k] or 0) + 1
						end
					end
				end
			end
		end
	end
	local lines = {}
	for _, biome in ipairs(L.Biomes) do
		if biome ~= "Mountains" and biome ~= "Lobby" then
			local area = Ctx.areaIn(biome)
			local cb = counts[biome] or {}
			local parts = {}
			for _, rule in ipairs(Scatter.rulesFor(L, biome)) do
				local exp = rule.density * area / 1000
				local ex = Scatter.EXTRA[biome .. "." .. rule.kind]
				if ex and ex.maxCount then
					exp = min(exp, ex.maxCount)
				end
				local placed = 0
				for _, a in ipairs(rule.assets) do
					placed += cb[a] or 0
				end
				if exp >= 1 and not (rule.kind == "CliffFace" or rule.kind == "Crag") then
					table.insert(parts, string.format("%s %d/%.0f (%.0f%%)", rule.kind, placed, exp, placed / exp * 100))
				end
			end
			table.insert(lines, biome .. ": " .. table.concat(parts, ", "))
		end
	end
	local per = {}
	for x = -640, 600, 40 do
		for z = -640, 600, 40 do
			local cx, cz = x + 20, z + 20
			if cx * cx + cz * cz < r2 and L.getBiome(V3(cx, 0, cz)) == "Forest" then
				table.insert(per, trees[math.floor(x / 40) * 1000 + math.floor(z / 40)] or 0)
			end
		end
	end
	table.sort(per)
	local empty = 0
	for _, v in ipairs(per) do
		if v == 0 then
			empty += 1
		end
	end
	if #per > 0 then
		table.insert(lines, string.format("forest trees per 40 x 40 cell (%d cells): median %d, p90 %d, max %d, empty %d",
			#per, per[math.ceil(#per / 2)], per[math.ceil(#per * 0.9)], per[#per], empty))
	end
	return table.concat(lines, "\n  ")
end

-- the lobby: climbable surfaces, fires with flames
function Audit.lobby(Ctx): string
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return "no Lobby"
	end
	local climb, emitters, fires = 0, 0, 0
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:HasTag("Climbable") and d:IsA("BasePart") and d.CanCollide and d.CanQuery then
			climb += 1
		end
		if d:IsA("ParticleEmitter") and d.Enabled then
			emitters += 1
		end
		if d:IsA("Attachment") and d.Name == "FireFx" then
			fires += 1
		end
	end
	return string.format("Tor: climbable surfaces %d, fires with flames %d, particle emitters %d", climb, fires, emitters)
end

function Audit.looks(Ctx): string
	local lines = {}
	local ok, err = pcall(function()
		table.insert(lines, "10 facets " .. Audit.facets(Ctx))
		table.insert(lines, "11 fill " .. Audit.density(Ctx))
		table.insert(lines, "7b floating " .. Audit.floating(Ctx))
		table.insert(lines, "12 clearings " .. Audit.clearings(Ctx))
		table.insert(lines, "13 " .. Audit.lobby(Ctx))
	end)
	if not ok then
		table.insert(lines, "looks FAILED: " .. tostring(err))
	end
	return table.concat(lines, "\n")
end

function Audit.fixLoot(Ctx): string
	local L = Ctx.Layout
	local P = probes(Ctx)
	local moved, kept, notes = 0, 0, {}
	local ok, err = pcall(function()
		local ad = ServerStorage:FindFirstChild("ArenaData")
		local folder = ad and ad:FindFirstChild("LootSpawns")
		if not folder then
			return
		end
		local others = {}
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("BasePart") then
				table.insert(others, m)
			end
		end
		local deck = Ctx.arena():FindFirstChild("SpirePlatform")
		local seat = RaycastParams.new()
		seat.FilterType = Enum.RaycastFilterType.Include
		seat.FilterDescendantsInstances = if deck then { workspace.Terrain, deck } else { workspace.Terrain }
		seat.IgnoreWater = false
		for i, mk in ipairs(others) do
			local bad = #markerBlocked(P, mk) > 0 or not reachable(P, mk)
			local protected = mk:GetAttribute("Runner") == true or string.sub(mk.Name, 1, 11) == "RunnerCache"
			if bad and protected then
				kept += 1
				table.insert(notes, mk.Name .. where(mk.Position) .. " left in place (runner's cache: the rules owner's spot)")
			elseif bad then
				local p0 = mk.Position
				local _, yaw = mk.CFrame:ToOrientation()
				local half = mk.Size.Y / 2
				local done = false
				for r = 2, 30, 1.5 do
					local steps = max(8, floor(r * 2))
					for s = 0, steps - 1 do
						local a = (s / steps) * math.pi * 2 + p0.X * 0.01
						local x, z = p0.X + cos(a) * r, p0.Z + sin(a) * r
						local rr = sqrt(x * x + z * z)
						local top = workspace:Raycast(V3(x, p0.Y + 12, z), V3(0, -30, 0), seat)
						if rr > 25 and rr < L.PlayRadius - 24 and top and top.Material ~= Enum.Material.Water and top.Normal.Y > cos(math.rad(26)) and Ctx.trailDistance(x, z) > 2 then
							local near = false
							for _, o in ipairs(others) do
								if o ~= mk and V3(o.Position.X - x, 0, o.Position.Z - z).Magnitude < 4 then
									near = true
									break
								end
							end
							if not near then
								local old = mk.CFrame
								mk.CFrame = CFrame.new(x, top.Position.Y + half, z) * CFrame.fromOrientation(0, yaw, 0)
								if #markerBlocked(P, mk) == 0 and reachable(P, mk) then
									done = true
									moved += 1
									table.insert(notes, string.format("%s %s -> %s (%.1f studs)", mk.Name, where(p0), where(mk.Position), r))
									break
								end
								mk.CFrame = old
							end
						end
					end
					if done then
						break
					end
				end
				if not done then
					table.insert(notes, mk.Name .. where(p0) .. " NO free spot within 30 studs")
				end
			end
			if i % 10 == 0 then
				Ctx.yield()
			end
		end
	end)
	P:destroy()
	if not ok then
		return "fixLoot FAILED: " .. tostring(err)
	end
	return string.format("fixLoot: %d markers moved, %d left in place\n  %s", moved, kept, table.concat(notes, "\n  "))
end

return Audit
