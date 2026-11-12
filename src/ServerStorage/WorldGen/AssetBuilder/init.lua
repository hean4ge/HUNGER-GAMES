--[[
	AssetBuilder - builds every world template into ServerStorage.WorldAssets (edit time, re-runnable).
	Owner: level design.

	  require(game.ServerStorage.WorldGen.AssetBuilder).build()   -- rebuilds Trees, Plants, Rocks, Props, Structures

	Children:
	  Kit         construction helpers (also used by Populate)
	  Trees       pines, oaks, birches, dead swamp trees
	  Nature      bushes, berry bush, reeds, mushrooms, logs, stumps, rocks
	  Props       campfire, tent, crates, barrel, fence, lanterns, benches, brazier, banner, notice board, plinth...
	  Structures  the Spire, pavilion, cabin, watchtower, mill, water wheel, shack, stilt hut

	Template conventions (see Kit): every template is a Model whose WorldPivot is the centre of its base on the
	ground (y = 0), front facing -Z, with attributes Category, Footprint and Sink. Placeholder geometry: a Blender
	mesh can replace any template as long as it keeps the name, the pivot and the special children
	(LootPoint / EmitterPoint parts, Foot attachments).
]]
local ServerStorage = game:GetService("ServerStorage")

local Kit = require(script.Kit)

local AssetBuilder = {}

local SECTIONS = { "Trees", "Nature", "Props", "Structures" }
local FOLDERS = { "Trees", "Plants", "Rocks", "Props", "Structures" }

function AssetBuilder.getFolder(): Folder
	local root = ServerStorage:FindFirstChild("WorldAssets")
	if not root then
		root = Instance.new("Folder")
		root.Name = "WorldAssets"
		root.Parent = ServerStorage
	end
	return root :: Folder
end

-- Rebuilds every template. Only touches the folders listed in FOLDERS.
function AssetBuilder.build(): string
	local root = AssetBuilder.getFolder()
	local folders = {}
	for _, name in ipairs(FOLDERS) do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = name
		folders[name] = folder
	end
	local report = {}
	for _, section in ipairs(SECTIONS) do
		local module = script:FindFirstChild(section)
		if module then
			local builder = require(module)
			local ok, err = xpcall(builder.build, debug.traceback, Kit, folders)
			if not ok then
				warn("[AssetBuilder] " .. section .. " failed: " .. tostring(err))
				table.insert(report, section .. " FAILED")
			end
		end
		task.wait()
	end
	local total = 0
	for _, name in ipairs(FOLDERS) do
		local folder = folders[name]
		folder.Parent = root
		local count = #folder:GetChildren()
		total += count
		table.insert(report, string.format("%s: %d", name, count))
	end
	return string.format("AssetBuilder: %d templates (%s)", total, table.concat(report, ", "))
end

-- Finds a template by name in any WorldAssets folder.
function AssetBuilder.get(name: string): Model?
	local root = AssetBuilder.getFolder()
	for _, folder in ipairs(root:GetChildren()) do
		local found = folder:FindFirstChild(name)
		if found then
			return found :: Model
		end
	end
	return nil
end

return AssetBuilder
