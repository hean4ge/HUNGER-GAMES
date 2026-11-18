--[[
	TreeClimb - which trees can be climbed and sat in, and what marks them. Shared by the planting builder
	(ServerStorage.WorldGen.Map1.Scatter, Edit mode), the climbing code (MovementController), the Sit and Climb
	prompts (TreeSeatController) and the seats (TreeSeatService). Loads anywhere without yielding.

	WHAT A CLIMBABLE TREE IS (the contract every reader keeps to; a purpose-built mesh keeps to it too)
	  <tree Model>                 named after its asset as every Scatter plant is (M1_Pine_A ...)
	    <trunk part>               its collision is the trunk; it carries the tag "Climbable" (MovementController's
	                               climb reads that tag) and stands upright on the model's pivot
	      Perch1, Perch2 ...       Attachments with the tag "TreePerch": the spot on top of a sturdy limb where a
	                               contender stands, and sits. Position = feet on the limb; LookVector = the way a
	                               seated contender faces (out along the limb, the trunk at their back)
	    Limb1, Limb2 ...           the limbs themselves (collide), when they are not part of the trunk's own mesh
	  The top perch is the top of the climb: the trunk above it is not climbed.

	TODAY the limbs are stand-ins: plain matte Wood blocks in the bark's colour, added by TreeClimb.dress() to the
	scatter's own tree templates (the Map 1 tree meshes have no usable limbs: the conifers are a pole in a cone of
	needles, the beeches fork into thin steep sticks).

	THE SWAP TO PURPOSE-BUILT MESHES (the Blender "TreesClimb" set), one table entry per asset:
	  TreeClimb.SPECS.M1_Pine_A.mesh = "TC_Pine_A"
	  Then the scatter clones ServerStorage.WorldAssets.Map1.<mesh> (found anywhere under it) for the climbable
	  trees of that asset instead of dressing the plain template, and TreeClimb.adopt() marks it:
	    - the trunk is the part named in spec.trunkPart, else the first part whose name has "Bark" or "Trunk" in it
	    - limbs that are their own parts have "Limb", "Branch" or "Step" in their names (they collide)
	    - perches are Attachments whose names begin "Perch" or "Seat", anywhere in the model (they are moved under
	      the trunk part and tagged); the Blender empty's -Z (Roblox LookVector) is where the sitter faces
	    - crown parts ("Needles", "Leaves", "Crown") never collide, as today
	  The mesh must stand on its pivot at the same scale as the plain asset (the scatter scales both alike), and
	  its top perch is the top of the climb. Nothing else changes: the climbing, the prompts and the seats read
	  only the tags and the attachments. Then rebuild the tree kinds:
	    S.build({ kinds = { "Conifer", "Broadleaf" } })

	WHICH TREES (TreeClimb.SPECS): every pine and every beech inside the play radius, whatever its size. Pines are
	the bare trunks with two limbs under the crown; beeches the broadleaf trees. Firs are not climbed. share and
	minScale thin that out per asset if a budget ever asks for it.
]]
local CollectionService = game:GetService("CollectionService")

local TreeClimb = {}
TreeClimb.VERSION = 1
TreeClimb.TAG_TRUNK = "Climbable"
TreeClimb.TAG_PERCH = "TreePerch"
TreeClimb.PERCH = "Perch"
TreeClimb.LIMB = "Limb"

-- The stand-in limb, in studs at the tree's scale 1 (the scatter then scales the whole tree 0.96 to 1.44).
TreeClimb.LIMB_DEFAULT = {
	length = 5.4, -- from the trunk's axis to the tip
	width = 1.5, -- the walking width (a contender's torso is 2 wide)
	thick = 0.8,
	stand = 2.0, -- from the trunk's surface to the perch point
}

--[[ SPECS[asset]
	share      0..1: the part of this asset's trees that are climbable (the tree's own random draw decides)
	minScale   only trees at least this big
	mesh       nil: the plain template with stand-in limbs; a name: a purpose-built template (see the header)
	trunkPart  the trunk part's name (default: the first part with "Bark" or "Trunk" in its name)
	trunk      the trunk's radius at the limbs, scale 1
	limbs      the stand-ins: y = the limb's top above the pivot at scale 1, bearing in degrees about the trunk
	           (0 = the model's -Z, clockwise from above). Low limb first, the top perch last. ]]
TreeClimb.SPECS = {
	M1_Pine_A = {
		share = 1, minScale = 0, mesh = nil, trunk = 0.8,
		limbs = { { y = 9.5, bearing = 30 }, { y = 20.5, bearing = 210 } },
	},
	M1_Pine_B = {
		share = 1, minScale = 0, mesh = nil, trunk = 0.9,
		limbs = { { y = 9.5, bearing = 140 }, { y = 23.5, bearing = 320 } },
	},
	M1_Beech_A = {
		share = 1, minScale = 0, mesh = nil, trunk = 0.95,
		limbs = { { y = 6.5, bearing = 250, length = 6.2, width = 1.7 }, { y = 10.5, bearing = 70, length = 6.2, width = 1.7 } },
	},
	M1_Beech_B = {
		share = 1, minScale = 0, mesh = nil, trunk = 1.1,
		limbs = { { y = 8, bearing = 100, length = 7, width = 1.8 }, { y = 12.5, bearing = 280, length = 7, width = 1.8 } },
	},
}

function TreeClimb.specOf(asset: string): any
	return TreeClimb.SPECS[asset]
end

-- Is a tree of this asset, at this scale, with this draw (0..1), climbable?
function TreeClimb.chosen(asset: string, scale: number, draw: number): boolean
	local spec = TreeClimb.SPECS[asset]
	if not spec then
		return false
	end
	return scale >= (spec.minScale or 0) and draw < (spec.share or 1)
end

-- How many instances dress() or adopt() adds to a tree of this asset (for a plan that makes nothing).
function TreeClimb.extraInstances(asset: string): (number, number)
	local spec = TreeClimb.SPECS[asset]
	if not spec or spec.mesh then
		return 0, 0
	end
	local n = #spec.limbs
	return n * 2, n -- instances (a limb and its perch), colliding parts
end

local function nameHas(name: string, words: { string }): boolean
	for _, w in ipairs(words) do
		if string.find(name, w, 1, true) then
			return true
		end
	end
	return false
end

function TreeClimb.trunkOf(model: Instance, spec: any?): BasePart?
	local wanted = spec and spec.trunkPart
	if wanted then
		local p = model:FindFirstChild(wanted, true)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and nameHas(d.Name, { "Bark", "Trunk" }) then
			return d
		end
	end
	return nil
end

-- Is this part a limb of a climbable tree (a stand-in, or a mesh's own limb part)?
function TreeClimb.isLimbName(name: string): boolean
	return nameHas(name, { "Limb", "Branch", "Step" })
end

--[[ Adds the stand-in limbs and perches to a plain tree model standing at scale 1 (Edit mode, or anywhere a
	builder runs). The model is not parented by this. Returns the number of perches. ]]
function TreeClimb.dress(model: Model, asset: string): number
	local spec = TreeClimb.SPECS[asset]
	if not spec then
		return 0
	end
	local trunk = TreeClimb.trunkOf(model, spec)
	if not trunk then
		return 0
	end
	trunk:AddTag(TreeClimb.TAG_TRUNK)
	local pivot = model:GetPivot()
	local D = TreeClimb.LIMB_DEFAULT
	local made = 0
	for i, limb in ipairs(spec.limbs) do
		local length = limb.length or D.length
		local width = limb.width or D.width
		local thick = limb.thick or D.thick
		-- the limb's frame: on the trunk's axis at the limb's top, looking out along it
		local out = pivot * CFrame.Angles(0, -math.rad(limb.bearing), 0) * CFrame.new(0, limb.y, 0)
		local part = Instance.new("Part")
		part.Name = TreeClimb.LIMB .. i
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Wood
		part.Color = trunk.Color
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(width, thick, length)
		part.CFrame = out * CFrame.new(0, -thick / 2, -length / 2)
		part.Parent = model
		local perch = Instance.new("Attachment")
		perch.Name = TreeClimb.PERCH .. i
		perch.Parent = trunk
		perch.WorldCFrame = out * CFrame.new(0, 0, -((spec.trunk or 1) + (limb.stand or D.stand)))
		perch:AddTag(TreeClimb.TAG_PERCH)
		made += 1
	end
	return made
end

--[[ Marks a purpose-built climbable tree (see the header): tags its trunk, makes its limb parts collide, moves its
	Perch / Seat attachments under the trunk and tags them. Returns the number of perches. ]]
function TreeClimb.adopt(model: Model, asset: string): number
	local spec = TreeClimb.SPECS[asset]
	local trunk = TreeClimb.trunkOf(model, spec)
	if not trunk then
		return 0
	end
	trunk:AddTag(TreeClimb.TAG_TRUNK)
	local found = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Attachment") and (string.sub(d.Name, 1, 5) == "Perch" or string.sub(d.Name, 1, 4) == "Seat") then
			table.insert(found, d)
		elseif d:IsA("BasePart") and d ~= trunk and TreeClimb.isLimbName(d.Name) then
			d.CanCollide = true
			d.CanQuery = true
		end
	end
	table.sort(found, function(a, b)
		return a.WorldPosition.Y < b.WorldPosition.Y
	end)
	for i, a in ipairs(found) do
		local world = a.WorldCFrame
		a.Name = TreeClimb.PERCH .. i
		a.Parent = trunk
		a.WorldCFrame = world
		a:AddTag(TreeClimb.TAG_PERCH)
	end
	return #found
end

-- The perches of a climbable tree, lowest first, from its trunk part (any reader, at run time).
function TreeClimb.perchesOf(trunk: Instance): { Attachment }
	local list = {}
	for _, child in ipairs(trunk:GetChildren()) do
		if child:IsA("Attachment") and child:HasTag(TreeClimb.TAG_PERCH) then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.WorldPosition.Y < b.WorldPosition.Y
	end)
	return list
end

-- The trunk a perch belongs to, and its tree.
function TreeClimb.treeOfPerch(perch: Instance): (BasePart?, Instance?)
	local trunk = perch.Parent
	if trunk and trunk:IsA("BasePart") then
		return trunk, trunk.Parent
	end
	return nil, nil
end

function TreeClimb.isPerch(inst: any): boolean
	return typeof(inst) == "Instance" and inst:IsA("Attachment") and CollectionService:HasTag(inst, TreeClimb.TAG_PERCH)
end

return TreeClimb
