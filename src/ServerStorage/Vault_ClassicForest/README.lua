--[[
	ServerStorage.Vault_ClassicForest - the classic forest arena, taken out of the game on 17 November 2026 when
	Map 1 (the Green Land) became the arena (docs/design/Map1Build.md, decision 1). In the repo:
	src/ServerStorage/Vault_ClassicForest/. Nothing in the running game reads this folder.

	WHAT IS HERE
	  ArenaLayout_v2        the forest layout (Version 2). It was ReplicatedStorage.Shared.ArenaLayout.
	                        Its LobbyPosition still says (2600, 160, 0); the lobby now stands at (8800, 160, 0).
	  TerrainGen            the forest terrain writer (v2)
	  TerrainData (+ C, H, M, S, W)   its 8-stud grids; the v2 layout reads them at ServerStorage.WorldGen.TerrainData
	  Populate (+ Audit, Lobby, Scatter, Sites)   the set dresser (v2)
	  WaterPointsBuilder    wrote Shared.WaterPoints for the forest
	  RealAssets (+ Manifest)         built the realistic templates in ServerStorage.MeshAssets from MeshImports
	  WaterPoints           the forest's Shared.WaterPoints (52 points), a copy
	  LootSpawns            the forest's 177 loot markers (Parts, tag LootSpawn, attributes Tier / Kind / ...), a copy
	  RockPocketFill_Cliffs_330_285   a hand-made 5-stud collider that stood in workspace.Arena, a copy
	  Tor_Island            a TerrainRegion: the lobby island's voxels as they were at (2600, 160, 0), taken before
	                        the move. The box it was copied from is in its attributes.
	  Settings              the terrain colours, base-material overrides, water and grass the forest arena had;
	                        Settings.apply() puts them back
	  README                this text

	WHAT IS NOT HERE
	  The forest's scenery (about 122,000 instances in workspace.Arena) and its terrain voxels were deleted, not
	  moved. Populate v2 and TerrainGen v2 are seeded: the same code, layout and markers build the same world again
	  (about 11 s for the scenery). The whole place as it was is in the saved place versions 340 (the last one
	  before the install), 302 and 258.
	  Still in place because the lobby or the game needs them: ServerStorage.MeshAssets, MeshImports, WorldAssets,
	  the LS_ MaterialVariants in MaterialService, WorldGen.AssetBuilder, LightingRig, UIBuilder, DummyBuilder,
	  ItemAssets, ArmsFacetedAssets.

	THE EASY WAY BACK
	  Open place version 340, 302 or 258 from the place's version history. That brings back everything, and undoes
	  every script change made since.

	BRINGING IT BACK IN THIS PLACE (Edit mode, no playtest running; do not save until the last step has passed)
	  NEVER call TerrainGen.generate() or Populate.generate() with their defaults: the first calls Terrain:Clear()
	  (the lobby island is terrain too) and builds a new island at the layout's LobbyPosition; the second rebuilds
	  the lobby.
	  1. Take Map 1 out: clear its terrain by region (Map1.Terrain.clearRegion(-2752, 2752, -2752, 2752,
	     { minY = -128, maxY = 1408 }); the lobby must be outside that box), and remove Map 1's instances from
	     workspace.Arena (the children of Plinths, Landmarks, Skyline, FarValley, Scatter, Boundary and Ambience)
	     and its markers from ServerStorage.ArenaData.LootSpawns (attribute Source starts "Map1:").
	  2. The layout: follow wave3/layout/RESTORE_V2.md section 3 (in the session's scratch area), or in short:
	     keep the Map 1 layout as Shared.ArenaLayout_GreenLand, copy this folder's ArenaLayout_v2 source over
	     ReplicatedStorage.Shared.ArenaLayout, and change its one LobbyPosition line to Vector3.new(8800, 160, 0)
	     if the lobby is still there. On disk the file is src/ServerStorage/Vault_ClassicForest/ArenaLayout_v2.lua
	     (RESTORE_V2.md calls it ArenaLayout.lua; it is the same 76,780 bytes, FNV-1a 0c61660e).
	  3. Move TerrainGen, TerrainData, Populate, WaterPointsBuilder and RealAssets back into ServerStorage.WorldGen
	     (in Studio and on disk: they look for each other and for TerrainData there).
	  4. Config.Map = "ClassicForest" in ReplicatedStorage.Shared.Config (one line), pushed with tools/studio_sync.
	  5. Settings.apply() (this folder): the forest's terrain colours, LS_ overrides and water.
	  6. Copy WaterPoints' source over ReplicatedStorage.Shared.WaterPoints. Put clones of LootSpawns' children
	     into ServerStorage.ArenaData.LootSpawns. Put a clone of RockPocketFill_Cliffs_330_285 into workspace.Arena.
	  7. The terrain:
	       require(game.ServerStorage.WorldGen.TerrainGen:Clone()).generate({ clear = false, island = false })
	     clear = false skips Terrain:Clear(); island = false skips the lobby island.
	  8. The scenery:
	       require(game.ServerStorage.WorldGen.Populate:Clone()).generate({ steps = { "core", "pois", "camps", "cliffs", "scatter", "ambience" } })
	     No "lobby" step.
	  9. TerrainGen.verify(), Populate.verify(), then the HOW TO PLAY tips:
	       require(game.ServerStorage.WorldGen.UIBuilder:Clone()).applyTips()
	     and one practice round before the place is saved.
	  Steps 1 to 9 were written at the install and have not been run.

	THE LOBBY
	  The install moved the lobby island and everything in workspace.Lobby by +6,200 studs on X, to (8800, 160, 0).
	  To put it back at (2600, 160, 0): paste Tor_Island at the corner in its attributes
	  (Terrain:PasteRegion(Tor_Island, Vector3int16.new(CornerX, CornerY, CornerZ), true)), move every child of
	  workspace.Lobby by -6,200 on X, clear the island's new box with FillRegion Air, and set LobbyPosition in the
	  layout. Only do it with Map 1's terrain gone: Map 1's east summit stands where the lobby was.
]]
return "ServerStorage.Vault_ClassicForest: read this module's source"
