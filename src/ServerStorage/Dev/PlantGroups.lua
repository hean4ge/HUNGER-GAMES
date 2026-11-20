--[[
	PlantGroups - lumps Map 1's small plants into groups of up to 5 neighbours, in place, so the map has far fewer
	Models to load and track, and puts every plant back as it was when asked. Studio only, Edit mode only.
	Owner approval (20 Nov 2026): "if you lumped 4 or 5 but then kept them by eachother etc to make it still look the
	same but use less lag", then "Keep it".

	WHAT IT TOUCHES
	  workspace.Arena.Scatter (one Folder per 80-stud cell, built by ServerStorage.WorldGen.Map1.Scatter). Only the
	  ground plants in KINDS below: heather mats, gorse bushes, tall grass and wildflowers. Each of those is a Model
	  holding a single MeshPart. Everything else is left single on purpose:
	    M1_Pine_* / M1_Beech_*  climbable trees (Shared.TreeClimb: Climbable tag, TreePerch attachments, prompts)
	    M1_Fir_*                trees: WildlifeService indexes one squirrel tree per Model by its *_Bark part
	    M1_Boulder_* / M1_Crag_* rocks with collision; HazardLook borrows a boulder mesh for the rockfall
	  A plant is only grouped when it is plain: a Model with exactly one child, a BasePart, no tags and no attributes
	  on either. Anything else is skipped (and counted in the report).

	HOW IT LOOKS THE SAME
	  The MeshParts are not changed or moved at all: up to GROUP_MAX of them, the same kind, in the same cell, all within
	  LINK studs of the first one, are re-parented into one Model named like the originals (M1_Heather_A ...), Atomic
	  streaming as before. So DetailController still classes the group by its name (heath / tall / ground, hidden by
	  distance on low tiers), and Butterflies still finds gorse and wildflowers by name (one position per group).
	  Plants with no neighbour within LINK stay as they are.

	HOW REVERT WORKS
	  Each moved part keeps its old Model's data in attributes: PG_Pivot (CFrame), PG_Scale (number, when not 1),
	  PG_Primary (true when it was the PrimaryPart). revert() rebuilds one Model per part from those and removes them.
	  A group Model carries the attribute PlantGroup = member count. The Scatter folder carries PlantGroups = a summary.

	USE (execute_luau, Edit mode; Studio caches modules, so require a clone)
	  local PG = require(game.ServerStorage.Dev.PlantGroups:Clone())
	  PG.plan(opts?)  -> what group() would do, changing nothing (opts.link: studs, default LINK)
	  PG.group(opts?) -> groups every ungrouped plain plant (re-runnable: groups already made are left alone)
	  PG.revert()   -> every group back to one Model per plant
	  PG.count()    -> Models and instances under Scatter, and how many are groups
	  Each yields (task.wait) every CHUNK models so Studio does not freeze.
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local PlantGroups = {}

PlantGroups.KINDS = {
	M1_Heather_A = true,
	M1_Heather_B = true,
	M1_Gorse_A = true,
	M1_Gorse_B = true,
	M1_TallGrass_A = true,
	M1_Wildflowers_A = true,
}
local GROUP_MAX = 5 -- plants per group
local LINK_DEFAULT = 20 -- studs: every member is within this of the group's first plant (flat distance); opts.link overrides
-- (the plants are sparse: at 9 studs only half found a neighbour; at 20, 82 % do, 3.2 a group. The parts never move,
-- so a wider link changes nothing on screen; a group still sits inside about one DetailController 40-stud cell.)
local LINK = LINK_DEFAULT
local BUCKET = LINK -- spatial hash size for the neighbour search (= the link in use)
local CHUNK = 400 -- models handled between yields

local function scatterFolder(): Folder
	assert(RunService:IsStudio() and not RunService:IsRunning(), "PlantGroups: Studio Edit mode only")
	local arena = workspace:FindFirstChild("Arena")
	local scatter = arena and arena:FindFirstChild("Scatter")
	assert(scatter, "PlantGroups: workspace.Arena.Scatter not found")
	return scatter
end

local function hasData(inst: Instance): boolean
	return next(inst:GetAttributes()) ~= nil or #CollectionService:GetTags(inst) > 0
end

-- the single BasePart of a plain plant Model, or nil when the Model is not plain
local function plainPart(m: Instance): BasePart?
	if not m:IsA("Model") or not PlantGroups.KINDS[m.Name] or hasData(m) then
		return nil
	end
	local kids = m:GetChildren()
	if #kids ~= 1 then
		return nil
	end
	local p = kids[1]
	if not p:IsA("BasePart") or hasData(p) or #p:GetChildren() > 0 then
		return nil
	end
	if m.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
		return nil
	end
	return p
end

local function key(x: number, z: number): number
	return (math.floor(x / BUCKET) + 8192) * 16384 + (math.floor(z / BUCKET) + 8192)
end

local function setLink(opts)
	LINK = if opts and type(opts.link) == "number" then opts.link else LINK_DEFAULT
	BUCKET = LINK
end

-- groups for one cell folder: { { {model, part, pos}, ... }, ... } (only groups of 2 or more)
local function planCell(cell: Instance, stats)
	local byKind = {}
	for _, m in ipairs(cell:GetChildren()) do
		if PlantGroups.KINDS[m.Name] and m:IsA("Model") and m:GetAttribute("PlantGroup") == nil then
			local p = plainPart(m)
			if p then
				local list = byKind[m.Name]
				if not list then
					list = {}
					byKind[m.Name] = list
				end
				table.insert(list, { m = m, p = p, pos = m:GetPivot().Position })
			else
				stats.skipped += 1
			end
		end
	end
	local groups = {}
	for _, list in pairs(byKind) do
		-- a stable order (west to east) so a re-run plans the same groups
		table.sort(list, function(a, b)
			if a.pos.X ~= b.pos.X then
				return a.pos.X < b.pos.X
			end
			return a.pos.Z < b.pos.Z
		end)
		local hash = {}
		for _, e in ipairs(list) do
			local k = key(e.pos.X, e.pos.Z)
			local b = hash[k]
			if not b then
				b = {}
				hash[k] = b
			end
			table.insert(b, e)
		end
		local used = {}
		for _, seed in ipairs(list) do
			if not used[seed] then
				used[seed] = true
				local near = {}
				local bx, bz = math.floor(seed.pos.X / BUCKET), math.floor(seed.pos.Z / BUCKET)
				for i = bx - 1, bx + 1 do
					for j = bz - 1, bz + 1 do
						local b = hash[(i + 8192) * 16384 + (j + 8192)]
						if b then
							for _, e in ipairs(b) do
								if not used[e] then
									local dx, dz = e.pos.X - seed.pos.X, e.pos.Z - seed.pos.Z
									local d = dx * dx + dz * dz
									if d <= LINK * LINK then
										table.insert(near, { e = e, d = d })
									end
								end
							end
						end
					end
				end
				table.sort(near, function(a, b)
					return a.d < b.d
				end)
				local g = { seed }
				for i = 1, math.min(#near, GROUP_MAX - 1) do
					used[near[i].e] = true
					table.insert(g, near[i].e)
				end
				if #g >= 2 then
					table.insert(groups, g)
				else
					stats.alone += 1
				end
			end
		end
	end
	return groups
end

local function newStats()
	return { cells = 0, groups = 0, grouped = 0, alone = 0, skipped = 0 }
end

local function summary(verb: string, s): string
	return string.format(
		"PlantGroups.%s: %d cells, %d plants into %d groups (%.1f each), %d left single (no neighbour within %d studs), %d skipped (not plain)",
		verb,
		s.cells,
		s.grouped,
		s.groups,
		if s.groups > 0 then s.grouped / s.groups else 0,
		s.alone,
		LINK,
		s.skipped
	)
end

function PlantGroups.plan(opts: { link: number? }?): string
	setLink(opts)
	local scatter = scatterFolder()
	local s = newStats()
	local budget = 0
	for _, cell in ipairs(scatter:GetChildren()) do
		s.cells += 1
		local groups = planCell(cell, s)
		for _, g in ipairs(groups) do
			s.groups += 1
			s.grouped += #g
		end
		budget += #cell:GetChildren()
		if budget >= CHUNK * 4 then
			budget = 0
			task.wait()
		end
	end
	return summary("plan", s)
end

function PlantGroups.group(opts: { link: number? }?): string
	setLink(opts)
	local scatter = scatterFolder()
	local s = newStats()
	local budget = 0
	for _, cell in ipairs(scatter:GetChildren()) do
		s.cells += 1
		local groups = planCell(cell, s)
		for _, g in ipairs(groups) do
			local holder = Instance.new("Model")
			holder.Name = g[1].m.Name
			holder.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			local sum = Vector3.zero
			for _, e in ipairs(g) do
				local m, p = e.m, e.p
				p:SetAttribute("PG_Pivot", m:GetPivot())
				local scale = m:GetScale()
				if math.abs(scale - 1) > 1e-6 then
					p:SetAttribute("PG_Scale", scale)
				end
				if m.PrimaryPart == p then
					p:SetAttribute("PG_Primary", true)
				end
				sum += e.pos
				p.Parent = holder
				m:Destroy()
			end
			local c = sum / #g
			holder.WorldPivot = CFrame.new(c)
			holder:SetAttribute("PlantGroup", #g)
			holder.Parent = cell
			s.groups += 1
			s.grouped += #g
			budget += #g
			if budget >= CHUNK then
				budget = 0
				task.wait()
			end
		end
	end
	local result = summary("group", s)
	-- the folder's note says what is grouped now, counted (a re-run that finds nothing new rewrites the same totals)
	local groups, inGroups = 0, 0
	for _, cell in ipairs(scatter:GetChildren()) do
		for _, m in ipairs(cell:GetChildren()) do
			if m:GetAttribute("PlantGroup") ~= nil then
				groups += 1
				inGroups += #m:GetChildren()
			end
		end
	end
	scatter:SetAttribute(
		"PlantGroups",
		if inGroups > 0
			then string.format(
				"%s: %d plants in %d groups (link %d studs); revert with ServerStorage.Dev.PlantGroups.revert()",
				os.date("!%Y-%m-%d %H:%M"),
				inGroups,
				groups,
				LINK
			)
			else nil
	)
	print(result)
	return result
end

function PlantGroups.revert(): string
	local scatter = scatterFolder()
	local restored, groups, budget = 0, 0, 0
	for _, cell in ipairs(scatter:GetChildren()) do
		for _, holder in ipairs(cell:GetChildren()) do
			if holder:IsA("Model") and holder:GetAttribute("PlantGroup") ~= nil then
				groups += 1
				for _, p in ipairs(holder:GetChildren()) do
					local pivot = p:GetAttribute("PG_Pivot")
					if p:IsA("BasePart") and typeof(pivot) == "CFrame" then
						local m = Instance.new("Model")
						m.Name = holder.Name
						m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
						local scale = p:GetAttribute("PG_Scale")
						local primary = p:GetAttribute("PG_Primary") == true
						p:SetAttribute("PG_Pivot", nil)
						p:SetAttribute("PG_Scale", nil)
						p:SetAttribute("PG_Primary", nil)
						p.Parent = m
						if primary then
							m.PrimaryPart = p -- the part keeps its own PivotOffset
						else
							m.WorldPivot = pivot
						end
						if type(scale) == "number" then
							-- give the Model back its scale without resizing the part: shrink, then scale up about the pivot
							local cf, size = p.CFrame, p.Size
							m:ScaleTo(1 / scale)
							m:ScaleTo(scale)
							p.Size, p.CFrame = size, cf
							if not primary then
								m.WorldPivot = pivot
							end
						end
						m.Parent = cell
						restored += 1
					end
				end
				if #holder:GetChildren() == 0 then
					holder:Destroy()
				else
					warn("PlantGroups.revert: " .. holder:GetFullName() .. " still holds parts without PG_Pivot; left as is")
				end
				budget += 5
				if budget >= CHUNK then
					budget = 0
					task.wait()
				end
			end
		end
	end
	scatter:SetAttribute("PlantGroups", nil)
	local result = string.format("PlantGroups.revert: %d groups back to %d single plants", groups, restored)
	print(result)
	return result
end

function PlantGroups.count(): string
	local scatter = scatterFolder()
	local models, groups, inGroups, kinds = 0, 0, 0, 0
	for _, cell in ipairs(scatter:GetChildren()) do
		for _, m in ipairs(cell:GetChildren()) do
			models += 1
			if PlantGroups.KINDS[m.Name] then
				kinds += 1
			end
			local n = m:GetAttribute("PlantGroup")
			if n then
				groups += 1
				inGroups += #m:GetChildren()
			end
		end
	end
	return string.format(
		"Scatter: %d Models (%d of them small-plant Models, %d groups holding %d plants), %d instances; workspace %d instances",
		models,
		kinds,
		groups,
		inGroups,
		#scatter:GetDescendants(),
		#workspace:GetDescendants()
	)
end

return PlantGroups
