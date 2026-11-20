--[[
	Low-poly consistency fixes for instances that live in the place (20 Nov 2026, wave18 lowpoly-consistency).
	Run in Studio Edit mode (command bar or execute_luau), under the QA_Lock. Idempotent: a second run changes 0.
	Then save the place.

	1. Foliage and stone meshes that use a terrain material (LeafyGrass, Grass, Limestone) draw Roblox's tiled ground
	   texture on the mesh (a leaf-litter pattern on the pine needles of the TC_Pine / TC_Beech climb trees).
	   They become matte Plaster, as Map1.Assets.MATERIALS already does for every other Map 1 plant.
	   Scope: Workspace.Arena.Scatter and the templates in ServerStorage.WorldAssets.Map1.TreesClimb.
	   (WorldGen.BlenderTemplates now does the same when it rebuilds the templates.)
	2. The red train's roofs (TrainLobby_*_Roof) and its window scenery (TrainLobby_Scenery_*) were SmoothPlastic,
	   which shines like car paint under the Realistic lighting. They become matte Plaster. The train's interior walls
	   and ceilings stay SmoothPlastic: Plaster's stipple reads as grain on big close surfaces.
	   Meshes with a SurfaceAppearance are skipped (their texture already decides the look).
]]
local TERRAIN = {
	[Enum.Material.LeafyGrass] = true,
	[Enum.Material.Grass] = true,
	[Enum.Material.Limestone] = true,
}

local counts = { foliage = 0, templates = 0, train = 0 }

local function matteFoliage(root: Instance?, key: string)
	if not root then
		return
	end
	local list = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("MeshPart") and TERRAIN[d.Material] and not d:FindFirstChildOfClass("SurfaceAppearance") then
			table.insert(list, d)
		end
	end
	for i, d in ipairs(list) do
		d.Material = Enum.Material.Plaster
		counts[key] += 1
		if i % 2000 == 0 then
			task.wait()
		end
	end
end

local arena = workspace:FindFirstChild("Arena")
matteFoliage(arena and arena:FindFirstChild("Scatter"), "foliage")
local wa = game:GetService("ServerStorage"):FindFirstChild("WorldAssets")
local map1 = wa and wa:FindFirstChild("Map1")
matteFoliage(map1 and map1:FindFirstChild("TreesClimb"), "templates")

local lobby = workspace:FindFirstChild("Lobby")
if lobby then
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("MeshPart") and (d.Material == Enum.Material.SmoothPlastic or d.Material == Enum.Material.Plastic)
			and not d:FindFirstChildOfClass("SurfaceAppearance")
			and (d.Name:match("^TrainLobby_.*_Roof$") or d.Name:match("^TrainLobby_Scenery_")) then
			d.Material = Enum.Material.Plaster
			counts.train += 1
		end
	end
end

return ("matte fixes: %d Scatter foliage meshes, %d TreesClimb template meshes, %d train roof/scenery meshes")
	:format(counts.foliage, counts.templates, counts.train)
