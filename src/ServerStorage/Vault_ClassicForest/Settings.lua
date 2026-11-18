--[[
	Vault_ClassicForest.Settings - the place-wide settings the classic forest arena had, read from Studio on
	17 November 2026 (place version 340) just before Map 1 (the Green Land) was installed. Map1.Terrain.applyLook()
	changes the terrain colours, the water colour and the base-material overrides for the whole place; this module
	is what they were.

	Edit mode:
	  return require(game.ServerStorage.Vault_ClassicForest.Settings:Clone()).apply()
	puts back the colours, the overrides, the water and the grass. It does not touch streaming (unchanged by Map 1)
	or Config. The border, round and loot numbers of the forest arena are not here: they are
	Config.Maps.ClassicForest in ReplicatedStorage.Shared.Config, chosen by Config.Map = "ClassicForest".
]]
local Settings = {}

Settings.ReadAt = { placeVersion = 340, date = "2026-11-17" }

-- Terrain:GetMaterialColor, 0..255
Settings.Colors = {
	Grass = { 212, 206, 232 },
	LeafyGrass = { 215, 238, 255 },
	Ground = { 230, 255, 216 },
	Mud = { 174, 226, 200 },
	Sand = { 255, 250, 240 },
	Salt = { 205, 198, 182 },
	Rock = { 248, 248, 250 },
	Limestone = { 215, 215, 218 },
	Basalt = { 255, 255, 250 },
	Slate = { 92, 94, 96 },
	Snow = { 236, 240, 245 },
}

-- MaterialService:GetBaseMaterialOverride. A base material's own name means "no override".
Settings.Overrides = {
	Grass = "LS_MeadowGrass1",
	LeafyGrass = "LS_ForestFloor",
	Ground = "LS_EarthPath1",
	Mud = "LS_WetMud3",
	Sand = "LS_DampSand2",
	Salt = "LS_RiverPebbles",
	Rock = "LS_LichenGranite3",
	Limestone = "LS_StrataRock",
	Basalt = "LS_Scree1",
	Slate = "Slate",
	Snow = "Snow",
}

Settings.Water = {
	Color = { 32, 74, 72 },
	Transparency = 0.65,
	Reflectance = 0.6,
	WaveSize = 0.08,
	WaveSpeed = 6,
}

Settings.Grass = { Decoration = true, GrassLength = 0.7 }

Settings.Streaming = {
	StreamingEnabled = true,
	StreamingTargetRadius = 1024,
	StreamingMinRadius = 128,
	StreamOutBehavior = "Default",
	StreamingIntegrityMode = "PauseOutsideLoadedArea",
}

-- what the forest arena left on its instances (TerrainGen and Populate write them again)
Settings.TerrainAttributes = { TerrainVersion = 2, ArenaTerrainReady = true }
Settings.ArenaAttributes = { Center = Vector3.new(0, 0, 0), PlayRadius = 640 }

-- where things were
Settings.Lobby = { before = Vector3.new(2600, 160, 0), after = Vector3.new(8800, 160, 0) }
Settings.OldTerrainBox = { half = 960, minY = -64, maxY = 640 } -- cleared with Map1.Terrain.clearOldArena()

function Settings.apply(): string
	local terrain = workspace.Terrain
	local MaterialService = game:GetService("MaterialService")
	local colours, overrides = 0, 0
	for name, c in pairs(Settings.Colors) do
		terrain:SetMaterialColor((Enum.Material :: any)[name], Color3.fromRGB(c[1], c[2], c[3]))
		colours += 1
	end
	for name, variant in pairs(Settings.Overrides) do
		MaterialService:SetBaseMaterialOverride((Enum.Material :: any)[name], variant)
		overrides += 1
	end
	local w = Settings.Water
	terrain.WaterColor = Color3.fromRGB(w.Color[1], w.Color[2], w.Color[3])
	terrain.WaterTransparency = w.Transparency
	terrain.WaterReflectance = w.Reflectance
	terrain.WaterWaveSize = w.WaveSize
	terrain.WaterWaveSpeed = w.WaveSpeed
	terrain.Decoration = Settings.Grass.Decoration
	terrain.GrassLength = Settings.Grass.GrassLength
	return string.format(
		"classic forest look applied: %d material colours, %d base-material overrides, the water, the grass",
		colours,
		overrides
	)
end

return Settings
