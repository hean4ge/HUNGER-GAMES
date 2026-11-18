--[[
	ArenaLayout (v3) - the single source of truth for where things are in the arena: MAP 1, THE GREEN LAND.
	Until the install this module is Shared.ArenaLayout_GreenLand. The install puts it in Shared.ArenaLayout's place
	and moves the classic forest layout (v2) to ServerStorage.Vault_ClassicForest. The contract for every name in
	here is docs/design/Map1Build.md, section 3.1.

	The border, the launch, loot, the compass, the mist and the ambience read it, on the server and on every client.
	So it loads without yielding, never touches ServerStorage, and none of its functions errors or yields.
	The terrain is NOT made from these numbers, as v2's was: it comes from Blender (the data pack "map1_data",
	written into the place by ServerStorage.WorldGen.Map1). The tables between the two GENERATED marker lines come
	from the same export, through tools/map1/gen_layout.py; everything else is written by hand. If the export
	changes, run that script again; do not edit the block.

	CONVENTIONS (the same as v2)
	  Angles are degrees clockwise from north. North is -Z, east is +X.
	  polar(angle, r, y) = Vector3(sin(a) * r, y, -cos(a) * r) around Center (0, 0, 0).
	  Heights are absolute studs.

	THE MAP (centre outwards; heights measured on the export's height map, pass 3)
	  The Heart      r 0..190. A knoll: level at 46 (BaseHeight) to r 50, then falling to 44.3 at the plinth ring
	                 (RingHeight) and 43.9 at the turf's edge (r 180). On it stands the horn, on a three-pointed star
	                 platform whose deck is at 52.05: points at 0, 120 and 240 degrees (out to r 45.7), the horn's
	                 mouths and bronze steps at 60, 180 and 300 (the steps reach the knoll at r 33). 18 lens-shaped
	                 flower beds lie like spokes from r 42..69 out to r 136, six teardrop beds flank the three mouth
	                 lanes (open turf 18 wide, r 33..136), and 48 launch plinths stand at r 150, at 3.75 + 7.5 * k
	                 degrees (Plates[k + 1]). There are no bores under the plinths in the beta.
	  The Iris       the meadow, from the Heart to about r 600 (its edge wavers between 570 and 630; about 750 in
	                 the south): open grass in folds, y 33..96. Three lone trees at r 300 on the mouth bearings,
	                 eight berms, the eight runner's flags at r 340. The stream crosses its west side in a dip,
	                 from its spring in the north-west (315 degrees, r 720) to the lake.
	  The North Wood 300..60 degrees, from the Iris to the Edge: dense conifers on ground that climbs from 60 at
	                 the Iris to about 240 before the Edge (higher against the ridges). The Crimson Spiral
	                 (330, r 900), the Flower-Sun Glade (60, r 1,000), the Hedge Hollow (0, r 1,600).
	  The ridges     EastRidge (60..120 degrees) and WestRidge (240..300): dry shoulders, then the lids with their
	                 crag bands, up to y 500 and 522 at the field line.
	  The South Mountain  120..240 degrees beyond r 750: the lake's bowl, scree and crags. The peak is a mesh
	                 (180 degrees, r 1,550, summit y 640).
	  The Lake       an ellipse 660 x 256, centred 925 south of the horn. Water at 34 (WaterLevel), up to 14 deep.
	                 The stream's last 600 studs are at the lake's level too.
	  The Edge       due north, r 1,640..1,800, within 24 degrees of north: level ground at about 240, then a cliff
	                 of 107 studs into a canyon (floor 133). Its lip is nearest at r 1,718 (bearing 357) and inside
	                 the field line between bearings 349 and 12. It is inside the border and it is a real drop.
	  The field line r 1,800 (PlayRadius): a full round's border starts here. The Crest is the ground between it and
	                 the invisible Boundary at r 1,900 (BoundaryRadius), y 130..593. The terrain goes on to r 2,750
	                 (TerrainRadius, up to y 1,143) for looks; past that the far valley and the skyline are meshes.
	  The lobby      the Tor, 8,800 studs east of the horn (LobbyPosition), outside all of it.

	WHAT A RUNNING GAME READS (12 scripts, 14 names; a missing one either errors or falls back to a forest number)
	  Center            ArenaService, RoundService, CombatService, ArenaController, HUDController, LaunchController,
	                    LaunchIntroController, FallenRecapController: the border's centre, where contenders face, the
	                    compass marker, the Roll Call's bearing
	  BaseHeight        ArenaService and ArenaController (the border centre's height; the wall hangs from 110 under
	                    it), CombatService (dummies), RoundService (fallback ring)
	  PlinthRingRadius  LaunchController and LaunchIntroController ("on the plate ring" = within 8 studs of it),
	                    RoundService and CombatService (fallbacks)
	  PlinthCount       RoundService (fallback ring), LaunchIntroController (the cases in the launch hall)
	  PlazaRadius, AssetInfo.Spire.r   ArenaService: where the Last Stand closes (see below)
	  LobbyPosition     PlayerService: the fallback spawn, and the rescue of lobby players who fall 80 under its Y
	  WaterLevel        PlayerService (void line, only if Config has none), ArenaController.Sky (mist height)
	  Lake, Sectors     ArenaController.Sky: night mist over the lake's ellipse. There is no Marsh table and no sector
	                    named Marsh or Swamp, because Sky would lay marsh mist there
	  polar             CombatService, RoundService, ArenaController.Sky (fallback paths)
	  flatDistance      LootService: loot only inside the round's start ring; the Feast's refill radius
	  getBiome          AudioController: five points round the camera, five times a second, on every device

	QUERIES
	  getBiome(position) -> "Meadow" | "Field" | "Forest" | "Cliffs" | "Mountains" | "Lake" | "Lobby"
	                                 from the replicated region grid (Shared.Map1Regions); distance bands without it
	  regionAt(x, z) -> (id, name)   Map 1's own region there (Regions[id])
	  groundAt(x, z) -> (y, normal, material)?   raycast on Terrain only, water ignored; nil where nothing has streamed in
	  heightAt(x, z) -> number?      the same y, else the coarse height grid in Shared.Map1Regions, else nil
	  polar, angleOf, flatDistance, isInLake, getSite

	DATA (generated): Regions, Plates, Heart, Sites, TrailNames, Trails, Stream, Edge, Lake. All 166 placements of the
	export (every bed, hedge, berm and mesh) are in the data pack's Layout blob, for the builders.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArenaLayout = {}

ArenaLayout.Version = 3 -- the classic forest layout is 2; its builders (TerrainGen, Populate) assert 2 and refuse this one
ArenaLayout.Map = "GreenLand" -- = Config.Map

----------------------------------------------------------------------------------------------------
-- Core numbers (Map1Build 3.1). tools/map1/gen_layout.py checks the plain numbers against the export.
----------------------------------------------------------------------------------------------------
ArenaLayout.Center = Vector3.new(0, 0, 0)
ArenaLayout.BaseHeight = 46 -- the knoll under the platform: the border centre's height. NOT the deck (52.05) and not the plinths
ArenaLayout.RingHeight = 44.3 -- the turf of the plinth ring
ArenaLayout.WaterLevel = 34 -- the lake's surface

ArenaLayout.PlinthRingRadius = 150
ArenaLayout.PlinthCount = 48
ArenaLayout.PlinthOffsetDeg = 3.75 -- plinth k (0..47) stands at PlinthOffsetDeg + k * 360 / PlinthCount degrees

ArenaLayout.PlayRadius = 1800 -- the field line: a full round's border starts here (Config holds the border's numbers)
ArenaLayout.BoundaryRadius = 1900 -- the invisible backstop (workspace.Arena.Boundary)
ArenaLayout.TerrainRadius = 2750 -- terrain is written out to here

ArenaLayout.LobbyPosition = Vector3.new(8800, 160, 0) -- top surface centre of the lobby island (it was at x 2600 in v2)
ArenaLayout.LobbyRadius = 90

----------------------------------------------------------------------------------------------------
-- The Last Stand: PlazaRadius and AssetInfo.Spire.r
----------------------------------------------------------------------------------------------------
-- These two old names are what the game reads, so they stay. On Map 1 they describe no plaza and no spire: they
-- place the Last Stand (Map1Build decision 11: the ring closes on turf 90 to 100 studs from the centre, not on the
-- platform).
--
-- ArenaService.pickFinalCenter (ArenaService/init.lua, lines 269-301) picks the point the border closes on, once
-- a round, at a random bearing and at this distance from the centre:
--     d = min(PlazaRadius - 6, AssetInfo.Spire.r + random(gap[1], gap[2])),  gap = Config.Border.FinalSpireGap = { 15, 25 }
-- It keeps the point if a ray finds ground within 2 studs of BaseHeight that is nearly level (normal.Y > 0.96); after
-- 16 misses it takes the first point unchecked.
--     Spire.r = 75         75 + 15 = 90 and 75 + 25 = 100, so d runs from 90 to 100.
--     PlazaRadius = 106    106 - 6 = 100: the cap does not cut that range, and it holds d to 100 whatever the gap is.
-- The lower end needs FinalSpireGap[1] to stay 15: a smaller gap moves the point in by the difference (then raise
-- Spire.r by as much).
-- What is at r 90..100 (measured on the export's height map): turf at y 45.16 to 45.31 all the way round, 0.69 to
-- 0.84 under BaseHeight, so the 2-stud test passes, and level (normal.Y 0.9998). The deck's points end at r 45.7 and
-- the steps at r 33, so the point is never on the platform. About two fifths of the band is flower bed (the 18 beds
-- are 12 to 13.5 wide there; a bed is mounded 1 to 1.5, which passes the test where its face is not steep), so the
-- point can lie on a bed. The three mouth lanes are open turf: Heart.mouths[i].lane.
--
-- Every reader of the two names (src/ at commit 25d4073, and the scripts in Studio, 15 November 2026):
--   PlazaRadius         ArenaService.pickFinalCenter: the cap above (62 if the name is missing).
--                       TerrainGen v2, lines 1415 and 2021, and its archived copies: the flat plaza disc of the classic
--                       forest arena. Vaulted builders; they refuse to load against Version 3.
--   AssetInfo.Spire.r   ArenaService.pickFinalCenter: the distance above (20 if the name is missing).
--   AssetInfo[name]     Populate.Sites and Populate.Scatter v2: asset sizes for spacing. Vaulted builders, as above.
-- Nothing else reads either name. RoundService reads Center, PlinthCount, PlinthRingRadius, BaseHeight and polar; the
-- launch's ring tests (LaunchController, LaunchIntroController) read Center, PlinthRingRadius and PlinthCount;
-- ArenaController.Sky reads WaterLevel, Lake, Marsh, Sectors and polar. None of them is touched by these two values.
ArenaLayout.PlazaRadius = 106
ArenaLayout.AssetInfo = {
	-- "Spire" = the horn. The three numbers are the horn's real size (w, h, d). r is NOT its footprint: it is the
	-- distance the Last Stand keeps from the centre, as worked out above.
	Spire = { 65.8, 53.3, 57.5, r = 75 },
}

----------------------------------------------------------------------------------------------------
-- Sectors
----------------------------------------------------------------------------------------------------
-- Coarse angular sectors beyond the Iris (for code that walks sectors; use getBiome or regionAt for real queries).
-- name = the biome getBiome gives there, region = Map 1's own name. There is no marsh on this map: keep any sector
-- named "Marsh" or "Swamp" out of this list (ArenaController.Sky lays mist over one).
ArenaLayout.Sectors = {
	{ name = "Forest", region = "NorthWood", from = 300, to = 60 },
	{ name = "Cliffs", region = "EastRidge", from = 60, to = 120 },
	{ name = "Mountains", region = "SouthMountain", from = 120, to = 240 },
	{ name = "Cliffs", region = "WestRidge", from = 240, to = 300 },
}

----------------------------------------------------------------------------------------------------
-- polar, angleOf, flatDistance (as in v2)
----------------------------------------------------------------------------------------------------
local CX, CZ = ArenaLayout.Center.X, ArenaLayout.Center.Z
local sin, cos, rad, deg, sqrt = math.sin, math.cos, math.rad, math.deg, math.sqrt
local atan2 = math.atan2

function ArenaLayout.polar(angleDeg: number, radius: number, y: number?): Vector3
	local a = rad(angleDeg)
	return Vector3.new(CX + sin(a) * radius, y or 0, CZ - cos(a) * radius)
end

function ArenaLayout.angleOf(position: Vector3): number
	return deg(atan2(position.X - CX, -(position.Z - CZ))) % 360
end

-- flatDistance(position): the flat distance from the centre, exactly as in v2 (LootService calls it this way).
-- flatDistance(a, b): the flat distance between two points.
function ArenaLayout.flatDistance(a: Vector3, b: Vector3?): number
	local dx, dz
	if b then
		dx, dz = a.X - b.X, a.Z - b.Z
	else
		dx, dz = a.X - CX, a.Z - CZ
	end
	return sqrt(dx * dx + dz * dz)
end

----------------------------------------------------------------------------------------------------
-- <<< GENERATED by tools/map1/gen_layout.py (do not edit by hand: re-run the script) >>>
-- From the Blender export of Map 1 (art/blender/map1_green_land.py, seed 50):
--   Map1_Layout.json   sha256 e2fd2bcf1b1d  52,545 bytes
--   Map1_Terrain.json  sha256 6fd98911247d  12,488 bytes
-- (tools/map1/pack_manifest.json lists the same fingerprints under "sources" when the data pack is from this export.)

-- Regions[id]: Map 1's regions by the id the region grid stores (Shared.Map1Regions.regionAt).
ArenaLayout.Regions = { "Heart", "Iris", "NorthWood", "EastRidge", "SouthMountain", "Lake", "WestRidge", "Edge", "Crest", "Outside" }

-- Plates[i]: launch plate i, in ring order clockwise from north (i = the export's index + 1; its plinth in the
-- place is workspace.Arena.Plinths.Plinth01 .. Plinth48). bearing: degrees. position: the plinth's pivot, on the
-- turf. stand: where a contender's feet go (the plinth's Stand attachment, 1.6 above the turf). yaw: the plinth
-- mesh's yaw about +Y, as the export places it.
ArenaLayout.Plates = {
	{ index = 1, bearing = 3.75, position = Vector3.new(9.81, 44.301, -149.679), stand = Vector3.new(9.81, 45.901, -149.679), yaw = -3.75 },
	{ index = 2, bearing = 11.25, position = Vector3.new(29.264, 44.302, -147.118), stand = Vector3.new(29.264, 45.902, -147.118), yaw = -11.25 },
	{ index = 3, bearing = 18.75, position = Vector3.new(48.216, 44.301, -142.04), stand = Vector3.new(48.216, 45.901, -142.04), yaw = -18.75 },
	{ index = 4, bearing = 26.25, position = Vector3.new(66.343, 44.301, -134.531), stand = Vector3.new(66.343, 45.901, -134.531), yaw = -26.25 },
	{ index = 5, bearing = 33.75, position = Vector3.new(83.336, 44.302, -124.72), stand = Vector3.new(83.336, 45.902, -124.72), yaw = -33.75 },
	{ index = 6, bearing = 41.25, position = Vector3.new(98.902, 44.302, -112.776), stand = Vector3.new(98.902, 45.902, -112.776), yaw = -41.25 },
	{ index = 7, bearing = 48.75, position = Vector3.new(112.776, 44.302, -98.902), stand = Vector3.new(112.776, 45.902, -98.902), yaw = -48.75 },
	{ index = 8, bearing = 56.25, position = Vector3.new(124.72, 44.302, -83.336), stand = Vector3.new(124.72, 45.902, -83.336), yaw = -56.25 },
	{ index = 9, bearing = 63.75, position = Vector3.new(134.531, 44.301, -66.343), stand = Vector3.new(134.531, 45.901, -66.343), yaw = -63.75 },
	{ index = 10, bearing = 71.25, position = Vector3.new(142.04, 44.301, -48.216), stand = Vector3.new(142.04, 45.901, -48.216), yaw = -71.25 },
	{ index = 11, bearing = 78.75, position = Vector3.new(147.118, 44.302, -29.264), stand = Vector3.new(147.118, 45.902, -29.264), yaw = -78.75 },
	{ index = 12, bearing = 86.25, position = Vector3.new(149.679, 44.301, -9.81), stand = Vector3.new(149.679, 45.901, -9.81), yaw = -86.25 },
	{ index = 13, bearing = 93.75, position = Vector3.new(149.679, 44.301, 9.81), stand = Vector3.new(149.679, 45.901, 9.81), yaw = -93.75 },
	{ index = 14, bearing = 101.25, position = Vector3.new(147.118, 44.302, 29.264), stand = Vector3.new(147.118, 45.902, 29.264), yaw = -101.25 },
	{ index = 15, bearing = 108.75, position = Vector3.new(142.04, 44.301, 48.216), stand = Vector3.new(142.04, 45.901, 48.216), yaw = -108.75 },
	{ index = 16, bearing = 116.25, position = Vector3.new(134.531, 44.301, 66.343), stand = Vector3.new(134.531, 45.901, 66.343), yaw = -116.25 },
	{ index = 17, bearing = 123.75, position = Vector3.new(124.72, 44.302, 83.336), stand = Vector3.new(124.72, 45.902, 83.336), yaw = -123.75 },
	{ index = 18, bearing = 131.25, position = Vector3.new(112.776, 44.302, 98.902), stand = Vector3.new(112.776, 45.902, 98.902), yaw = -131.25 },
	{ index = 19, bearing = 138.75, position = Vector3.new(98.902, 44.302, 112.776), stand = Vector3.new(98.902, 45.902, 112.776), yaw = -138.75 },
	{ index = 20, bearing = 146.25, position = Vector3.new(83.336, 44.302, 124.72), stand = Vector3.new(83.336, 45.902, 124.72), yaw = -146.25 },
	{ index = 21, bearing = 153.75, position = Vector3.new(66.343, 44.301, 134.531), stand = Vector3.new(66.343, 45.901, 134.531), yaw = -153.75 },
	{ index = 22, bearing = 161.25, position = Vector3.new(48.216, 44.301, 142.04), stand = Vector3.new(48.216, 45.901, 142.04), yaw = -161.25 },
	{ index = 23, bearing = 168.75, position = Vector3.new(29.264, 44.302, 147.118), stand = Vector3.new(29.264, 45.902, 147.118), yaw = -168.75 },
	{ index = 24, bearing = 176.25, position = Vector3.new(9.81, 44.301, 149.679), stand = Vector3.new(9.81, 45.901, 149.679), yaw = -176.25 },
	{ index = 25, bearing = 183.75, position = Vector3.new(-9.81, 44.301, 149.679), stand = Vector3.new(-9.81, 45.901, 149.679), yaw = -183.75 },
	{ index = 26, bearing = 191.25, position = Vector3.new(-29.264, 44.302, 147.118), stand = Vector3.new(-29.264, 45.902, 147.118), yaw = -191.25 },
	{ index = 27, bearing = 198.75, position = Vector3.new(-48.216, 44.301, 142.04), stand = Vector3.new(-48.216, 45.901, 142.04), yaw = -198.75 },
	{ index = 28, bearing = 206.25, position = Vector3.new(-66.343, 44.301, 134.531), stand = Vector3.new(-66.343, 45.901, 134.531), yaw = -206.25 },
	{ index = 29, bearing = 213.75, position = Vector3.new(-83.336, 44.302, 124.72), stand = Vector3.new(-83.336, 45.902, 124.72), yaw = -213.75 },
	{ index = 30, bearing = 221.25, position = Vector3.new(-98.902, 44.302, 112.776), stand = Vector3.new(-98.902, 45.902, 112.776), yaw = -221.25 },
	{ index = 31, bearing = 228.75, position = Vector3.new(-112.776, 44.302, 98.902), stand = Vector3.new(-112.776, 45.902, 98.902), yaw = -228.75 },
	{ index = 32, bearing = 236.25, position = Vector3.new(-124.72, 44.302, 83.336), stand = Vector3.new(-124.72, 45.902, 83.336), yaw = -236.25 },
	{ index = 33, bearing = 243.75, position = Vector3.new(-134.531, 44.301, 66.343), stand = Vector3.new(-134.531, 45.901, 66.343), yaw = -243.75 },
	{ index = 34, bearing = 251.25, position = Vector3.new(-142.04, 44.301, 48.216), stand = Vector3.new(-142.04, 45.901, 48.216), yaw = -251.25 },
	{ index = 35, bearing = 258.75, position = Vector3.new(-147.118, 44.302, 29.264), stand = Vector3.new(-147.118, 45.902, 29.264), yaw = -258.75 },
	{ index = 36, bearing = 266.25, position = Vector3.new(-149.679, 44.301, 9.81), stand = Vector3.new(-149.679, 45.901, 9.81), yaw = -266.25 },
	{ index = 37, bearing = 273.75, position = Vector3.new(-149.679, 44.301, -9.81), stand = Vector3.new(-149.679, 45.901, -9.81), yaw = -273.75 },
	{ index = 38, bearing = 281.25, position = Vector3.new(-147.118, 44.302, -29.264), stand = Vector3.new(-147.118, 45.902, -29.264), yaw = -281.25 },
	{ index = 39, bearing = 288.75, position = Vector3.new(-142.04, 44.301, -48.216), stand = Vector3.new(-142.04, 45.901, -48.216), yaw = -288.75 },
	{ index = 40, bearing = 296.25, position = Vector3.new(-134.531, 44.301, -66.343), stand = Vector3.new(-134.531, 45.901, -66.343), yaw = -296.25 },
	{ index = 41, bearing = 303.75, position = Vector3.new(-124.72, 44.302, -83.336), stand = Vector3.new(-124.72, 45.902, -83.336), yaw = -303.75 },
	{ index = 42, bearing = 311.25, position = Vector3.new(-112.776, 44.302, -98.902), stand = Vector3.new(-112.776, 45.902, -98.902), yaw = -311.25 },
	{ index = 43, bearing = 318.75, position = Vector3.new(-98.902, 44.302, -112.776), stand = Vector3.new(-98.902, 45.902, -112.776), yaw = -318.75 },
	{ index = 44, bearing = 326.25, position = Vector3.new(-83.336, 44.302, -124.72), stand = Vector3.new(-83.336, 45.902, -124.72), yaw = -326.25 },
	{ index = 45, bearing = 333.75, position = Vector3.new(-66.343, 44.301, -134.531), stand = Vector3.new(-66.343, 45.901, -134.531), yaw = -333.75 },
	{ index = 46, bearing = 341.25, position = Vector3.new(-48.216, 44.301, -142.04), stand = Vector3.new(-48.216, 45.901, -142.04), yaw = -341.25 },
	{ index = 47, bearing = 348.75, position = Vector3.new(-29.264, 44.302, -147.118), stand = Vector3.new(-29.264, 45.902, -147.118), yaw = -348.75 },
	{ index = 48, bearing = 356.25, position = Vector3.new(-9.81, 44.301, -149.679), stand = Vector3.new(-9.81, 45.901, -149.679), yaw = -356.25 },
}

-- Heart: the horn's knoll and what stands on it. Y values are world heights.
-- deckY is the deck's walkable top; hornPivotY is where the horn asset's pivot stands (its hems sink 0.05 into
-- the deck; Map1_Terrain.json calls this plaza.deckY)
-- the deck is walkable everywhere outside the horn; it is 6.05 above the knoll (a mantle, under the 6.5 limit)
-- and the stairs at the mouths are the only steps
ArenaLayout.Heart = {
	knollY = 46, -- the knoll under the platform, level to r = flatTo
	flatTo = 50,
	deckY = 52.05, -- the platform deck's walkable top
	hornPivotY = 52,
	ringRadius = 150, -- the plinth ring
	ringY = 44.3, -- its turf
	turfRadius = 180, -- the fresher green disc
	protectedDisc = { 200, 255 }, -- the terrain is the designed dome inside the first radius and blends out by the second
	starPoints = { 0, 120, 240 }, -- bearings of the platform's three points
	deckPolygon = { Vector3.new(-40.801, 52.05, 20.67), Vector3.new(-38.301, 52.05, 25), Vector3.new(38.301, 52.05, 25), Vector3.new(40.801, 52.05, 20.67), Vector3.new(2.5, 52.05, -45.67), Vector3.new(-2.5, 52.05, -45.67) },
	plinth = { count = 48, step = 7.5, offset = 3.75, standHeight = 1.6, drumRadius = 2.15, tubeRadius = 3.6, rimOuterRadius = 4.2 },
	horn = {
		colouring = "b",
		floorY = 52.06, -- the floor inside the horn
		floorTriangle = { Vector3.new(0, 52.06, -20.6), Vector3.new(17.84, 52.06, 10.3), Vector3.new(-17.84, 52.06, 10.3) },
		floorInradius = 10.5,
		coreCornerRadius = 21,
		apexY = 96,
		topY = 105,
		-- six weapon racks are modelled on the floor (props in the mesh, not loot); loot for TwoArenas 3.5's
		-- interior ring goes at or beside them
		rackSpots = { Vector3.new(-3, 52.06, -12.5), Vector3.new(3, 52.06, -12.5), Vector3.new(12.325, 52.06, 3.652), Vector3.new(9.325, 52.06, 8.848), Vector3.new(-9.325, 52.06, 8.848), Vector3.new(-12.325, 52.06, 3.652) },
	},
	-- mouths: the horn's three doorways. threshold = the doorway on the horn's floor; stairTop and stairFoot = the
	-- bronze steps from the deck down to the knoll; lane = the open turf from the steps to the plinth ring (no bed
	-- lies within halfWidth of the mouth's bearing between fromR and toR).
	mouths = {
		{ bearing = 60, threshold = Vector3.new(9.093, 52.06, -5.25), openingWidth = 14, openingHeight = 16, frameWidthAtDeck = 19,
			stairTop = Vector3.new(21.304, 52.05, -12.3), stairFoot = Vector3.new(28.579, 46, -16.5), stairWidth = 18, stairRisers = 4, stairRise = 1.5,
			lane = { halfWidth = 9, fromR = 33, toR = 136 } },
		{ bearing = 180, threshold = Vector3.new(0, 52.06, 10.5), openingWidth = 14, openingHeight = 16, frameWidthAtDeck = 19,
			stairTop = Vector3.new(0, 52.05, 24.6), stairFoot = Vector3.new(0, 46, 33), stairWidth = 18, stairRisers = 4, stairRise = 1.5,
			lane = { halfWidth = 9, fromR = 33, toR = 136 } },
		{ bearing = 300, threshold = Vector3.new(-9.093, 52.06, -5.25), openingWidth = 14, openingHeight = 16, frameWidthAtDeck = 19,
			stairTop = Vector3.new(-21.304, 52.05, -12.3), stairFoot = Vector3.new(-28.579, 46, -16.5), stairWidth = 18, stairRisers = 4, stairRise = 1.5,
			lane = { halfWidth = 9, fromR = 33, toR = 136 } },
	},
	-- sails: one at each star point. solid: the sail is sealed to the walls up to 16 over the deck; nobody
	-- gets behind it
	sails = {
		{ bearing = 0, hemTip = Vector3.new(0, 52, -38), tip = Vector3.new(0, 100, -14), finTip = Vector3.new(0, 105, -7.5) },
		{ bearing = 120, hemTip = Vector3.new(32.909, 52, 19), tip = Vector3.new(12.124, 100, 7), finTip = Vector3.new(6.495, 105, 3.75) },
		{ bearing = 240, hemTip = Vector3.new(-32.909, 52, 19), tip = Vector3.new(-12.124, 100, 7), finTip = Vector3.new(-6.495, 105, 3.75) },
	},
	-- beds: the 18 lens-shaped flower beds, laid like spokes from innerR to outerR along their bearing; position =
	-- the bed mesh's pivot (its middle), yaw = its yaw about +Y. Mounded 1 to 1.5 above the turf.
	beds = {
		{ asset = "M1_Spoke_00", bearing = 7.5, colour = "yellow", length = 90.93, width = 13.5, innerR = 45.07, outerR = 136, position = Vector3.new(11.817, 45.311, -89.759), yaw = -7.5 },
		{ asset = "M1_Spoke_01", bearing = 22.5, colour = "red", length = 94, width = 13.5, innerR = 42, outerR = 136, position = Vector3.new(34.059, 45.337, -82.225), yaw = -22.5 },
		{ asset = "M1_Spoke_02", bearing = 37.5, colour = "pink", length = 67, width = 12, innerR = 69, outerR = 136, position = Vector3.new(62.398, 45.107, -81.319), yaw = -37.5 },
		{ asset = "M1_Spoke_03", bearing = 82.5, colour = "lavender", length = 67, width = 12, innerR = 69, outerR = 136, position = Vector3.new(101.623, 45.107, -13.379), yaw = -82.5 },
		{ asset = "M1_Spoke_04", bearing = 97.5, colour = "magenta", length = 94, width = 13.5, innerR = 42, outerR = 136, position = Vector3.new(88.239, 45.337, 11.617), yaw = -97.5 },
		{ asset = "M1_Spoke_05", bearing = 112.5, colour = "yellow", length = 90.93, width = 13.5, innerR = 45.07, outerR = 136, position = Vector3.new(83.642, 45.311, 34.646), yaw = -112.5 },
		{ asset = "M1_Spoke_06", bearing = 127.5, colour = "red", length = 90.93, width = 13.5, innerR = 45.07, outerR = 136, position = Vector3.new(71.825, 45.311, 55.113), yaw = -127.5 },
		{ asset = "M1_Spoke_07", bearing = 142.5, colour = "pink", length = 94, width = 13.5, innerR = 42, outerR = 136, position = Vector3.new(54.18, 45.337, 70.608), yaw = -142.5 },
		{ asset = "M1_Spoke_08", bearing = 157.5, colour = "lavender", length = 67, width = 12, innerR = 69, outerR = 136, position = Vector3.new(39.225, 45.107, 94.698), yaw = -157.5 },
		{ asset = "M1_Spoke_09", bearing = 202.5, colour = "magenta", length = 67, width = 12, innerR = 69, outerR = 136, position = Vector3.new(-39.225, 45.107, 94.698), yaw = -202.5 },
		{ asset = "M1_Spoke_10", bearing = 217.5, colour = "yellow", length = 94, width = 13.5, innerR = 42, outerR = 136, position = Vector3.new(-54.18, 45.337, 70.608), yaw = -217.5 },
		{ asset = "M1_Spoke_11", bearing = 232.5, colour = "red", length = 90.93, width = 13.5, innerR = 45.07, outerR = 136, position = Vector3.new(-71.825, 45.311, 55.113), yaw = -232.5 },
		{ asset = "M1_Spoke_12", bearing = 247.5, colour = "pink", length = 90.93, width = 13.5, innerR = 45.07, outerR = 136, position = Vector3.new(-83.642, 45.311, 34.646), yaw = -247.5 },
		{ asset = "M1_Spoke_13", bearing = 262.5, colour = "lavender", length = 94, width = 13.5, innerR = 42, outerR = 136, position = Vector3.new(-88.239, 45.337, 11.617), yaw = -262.5 },
		{ asset = "M1_Spoke_14", bearing = 277.5, colour = "magenta", length = 67, width = 12, innerR = 69, outerR = 136, position = Vector3.new(-101.623, 45.107, -13.379), yaw = -277.5 },
		{ asset = "M1_Spoke_15", bearing = 322.5, colour = "yellow", length = 67, width = 12, innerR = 69, outerR = 136, position = Vector3.new(-62.398, 45.107, -81.319), yaw = -322.5 },
		{ asset = "M1_Spoke_16", bearing = 337.5, colour = "red", length = 94, width = 13.5, innerR = 42, outerR = 136, position = Vector3.new(-34.059, 45.337, -82.225), yaw = -337.5 },
		{ asset = "M1_Spoke_17", bearing = 352.5, colour = "pink", length = 90.93, width = 13.5, innerR = 45.07, outerR = 136, position = Vector3.new(-11.817, 45.311, -89.759), yaw = -352.5 },
	},
	-- teardrops: the 6 big pale petals, one on each side of each mouth lane, laid along it with the round end toward
	-- the horn. lane = the mouth's bearing; side = which side of the lane, facing out from the horn.
	teardrops = {
		{ asset = "M1_TeardropPeriwinkle", lane = 60, side = "left", colour = "periwinkle", length = 68, width = 16, position = Vector3.new(46.926, 45.724, -46.722), yaw = -60 },
		{ asset = "M1_TeardropMarigold", lane = 60, side = "right", colour = "marigold", length = 60, width = 15, position = Vector3.new(60.212, 45.792, -15.711), yaw = -60 },
		{ asset = "M1_TeardropPeriwinkle", lane = 180, side = "left", colour = "periwinkle", length = 68, width = 16, position = Vector3.new(17, 45.724, 64), yaw = -180 },
		{ asset = "M1_TeardropMarigold", lane = 180, side = "right", colour = "marigold", length = 60, width = 15, position = Vector3.new(-16.5, 45.792, 60), yaw = -180 },
		{ asset = "M1_TeardropPeriwinkle", lane = 300, side = "left", colour = "periwinkle", length = 68, width = 16, position = Vector3.new(-63.926, 45.724, -17.278), yaw = -300 },
		{ asset = "M1_TeardropMarigold", lane = 300, side = "right", colour = "marigold", length = 60, width = 15, position = Vector3.new(-43.712, 45.792, -44.289), yaw = -300 },
	},
}

-- Sites: the design's places as points on the ground (TwoArenas 3.6 and 3.9): rings B, C and D, the eight
-- runner's flags (F) and seven single berms (S). position.Y is the ground there in the export. built = what the
-- export really made there; no built = a design anchor only, nothing stands there yet.
-- From the export: TwoArenas 3.6 and 3.9's sites, runner's flags and single berms as bearings and radii put on
-- the ground. 'built' says what the generator made there; everything else (springs, pools, the East Brook,
-- fords, caves, the wreck, the kits) is NOT in the terrain or the meshes yet. The eight M1_Berm items above
-- stand at the generator's own positions, not at TwoArenas 3.6's sixteen.
ArenaLayout.Sites = {
	{ id = "B1", name = "The NW lone tree", bearing = 300, r = 300, position = Vector3.new(-259.808, 43.263, -150), region = "Iris", slopeDegrees = 4.5, waterWithin32 = false, built = "M1_LoneTree" },
	{ id = "B2", name = "The NE lone tree", bearing = 60, r = 300, position = Vector3.new(259.808, 50.323, -150), region = "Iris", slopeDegrees = 3.9, waterWithin32 = false, built = "M1_LoneTree" },
	{ id = "B3", name = "The S lone tree", bearing = 180, r = 300, position = Vector3.new(0, 41.961, 300), region = "Iris", slopeDegrees = 3.6, waterWithin32 = false, built = "M1_LoneTree" },
	{ id = "B4", name = "The Stepping Stones", bearing = 255, r = 340, position = Vector3.new(-328.415, 37.7, 87.998), region = "Iris", slopeDegrees = 17.4, waterWithin32 = true, built = "the stream passes here; no stones or ford are modelled" },
	{ id = "B5", name = "The Stream Bend", bearing = 215, r = 470, position = Vector3.new(-269.581, 32.815, 385.001), region = "Iris", slopeDegrees = 0.2, waterWithin32 = true, built = "the stream passes here; no pool or gorse bank is shaped" },
	{ id = "B6a", name = "The Gorse Banks", bearing = 110, r = 430, position = Vector3.new(404.068, 46.087, 147.069), region = "Iris", slopeDegrees = 7, waterWithin32 = false },
	{ id = "B6b", name = "The Daisy Spring", bearing = 122, r = 440, position = Vector3.new(373.141, 43.271, 233.164), region = "Iris", slopeDegrees = 5.1, waterWithin32 = false },
	{ id = "B7", name = "The South Fold", bearing = 180, r = 480, position = Vector3.new(0, 41.165, 480), region = "Iris", slopeDegrees = 0.6, waterWithin32 = false },
	{ id = "B8a", name = "The Butterfly Lane (south end)", bearing = 5, r = 560, position = Vector3.new(48.807, 79.97, -557.869), region = "Iris", slopeDegrees = 19.5, waterWithin32 = false },
	{ id = "B8b", name = "The Butterfly Lane (north end)", bearing = 5, r = 760, position = Vector3.new(66.238, 151.682, -757.108), region = "NorthWood", slopeDegrees = 18.8, waterWithin32 = false },
	{ id = "B9", name = "The Cress Spring", bearing = 20, r = 520, position = Vector3.new(177.85, 64.558, -488.64), region = "Iris", slopeDegrees = 17.4, waterWithin32 = false },
	{ id = "B10a", name = "The West Berms (5)", bearing = 320, r = 450, position = Vector3.new(-289.254, 63.352, -344.72), region = "Iris", slopeDegrees = 2, waterWithin32 = false },
	{ id = "B10b", name = "The East Berms (4)", bearing = 75, r = 480, position = Vector3.new(463.644, 51.564, -124.233), region = "Iris", slopeDegrees = 7.9, waterWithin32 = false },
	{ id = "C1", name = "The Crimson Spiral", bearing = 330, r = 900, position = Vector3.new(-450, 182.689, -779.423), region = "NorthWood", slopeDegrees = 0, waterWithin32 = false, built = "M1_CrimsonSpiral" },
	{ id = "C2", name = "The Flower-Sun Glade", bearing = 60, r = 1000, position = Vector3.new(866.025, 193.401, -500), region = "NorthWood", slopeDegrees = 0, waterWithin32 = false, built = "M1_SunGlade" },
	{ id = "C3", name = "The wreck", bearing = 20, r = 1250, position = Vector3.new(427.525, 202.026, -1174.616), region = "NorthWood", slopeDegrees = 2.9, waterWithin32 = false },
	{ id = "C4", name = "The Fern Pools", bearing = 345, r = 1150, position = Vector3.new(-297.642, 191.491, -1110.815), region = "NorthWood", slopeDegrees = 21.2, waterWithin32 = false },
	{ id = "C5", name = "The Apple Knoll", bearing = 35, r = 700, position = Vector3.new(401.504, 114.373, -573.406), region = "NorthWood", slopeDegrees = 15.7, waterWithin32 = false },
	{ id = "C6", name = "The North Beach", bearing = 180, r = 800, position = Vector3.new(0, 33.554, 800), region = "SouthMountain", slopeDegrees = 18.7, waterWithin32 = true, built = "the lake's north shore" },
	{ id = "C7", name = "The Delta", bearing = 197, r = 790, position = Vector3.new(-230.974, 35.917, 755.481), region = "SouthMountain", slopeDegrees = 9.3, waterWithin32 = true, built = "the stream's mouth" },
	{ id = "C8", name = "The Lake Cave", bearing = 150, r = 980, position = Vector3.new(490, 92.23, 848.705), region = "SouthMountain", slopeDegrees = 41.8, waterWithin32 = false },
	{ id = "C9", name = "The Flock Scree", bearing = 215, r = 1150, position = Vector3.new(-659.613, 126.958, 942.025), region = "SouthMountain", slopeDegrees = 26.4, waterWithin32 = false },
	{ id = "C10", name = "The Grotto", bearing = 95, r = 1200, position = Vector3.new(1195.434, 206.16, 104.587), region = "EastRidge", slopeDegrees = 8.9, waterWithin32 = false },
	{ id = "C11", name = "The Overhang", bearing = 265, r = 1200, position = Vector3.new(-1195.434, 203.27, 104.587), region = "WestRidge", slopeDegrees = 7.5, waterWithin32 = false },
	{ id = "C12", name = "The West Gully Pines", bearing = 250, r = 800, position = Vector3.new(-751.754, 124.691, 273.616), region = "WestRidge", slopeDegrees = 21.6, waterWithin32 = false },
	{ id = "C13", name = "The East Brook Ford", bearing = 100, r = 700, position = Vector3.new(689.365, 103.169, 121.554), region = "EastRidge", slopeDegrees = 20, waterWithin32 = false },
	{ id = "C14", name = "The Burnt Pines", bearing = 195, r = 1280, position = Vector3.new(-331.288, 214.313, 1236.385), region = "SouthMountain", slopeDegrees = 50.3, waterWithin32 = false },
	{ id = "D1", name = "The Hollow Spring", bearing = 10, r = 1480, position = Vector3.new(256.999, 221.446, -1457.516), region = "NorthWood", slopeDegrees = 5.4, waterWithin32 = false },
	{ id = "D2", name = "The Hedge Hollow", bearing = 0, r = 1600, position = Vector3.new(0, 216.112, -1600), region = "NorthWood", slopeDegrees = 12.5, waterWithin32 = false, built = "M1_HollyHedge (22 modules)" },
	{ id = "D3", name = "The Edge", bearing = 0, r = 1750, position = Vector3.new(0, 133.946, -1750), region = "Edge", slopeDegrees = 85.8, waterWithin32 = false, built = "the cliff lip and the canyon are in the terrain" },
	{ id = "D4", name = "The Shoulder Cairn", bearing = 180, r = 1250, position = Vector3.new(0, 125.26, 1250), region = "SouthMountain", slopeDegrees = 32.2, waterWithin32 = false },
	{ id = "D5", name = "The East Crest", bearing = 80, r = 1600, position = Vector3.new(1575.692, 284.911, -277.837), region = "EastRidge", slopeDegrees = 20.2, waterWithin32 = false },
	{ id = "D6", name = "The West Crest", bearing = 280, r = 1600, position = Vector3.new(-1575.692, 365.395, -277.837), region = "WestRidge", slopeDegrees = 26.6, waterWithin32 = false },
	{ id = "F1", name = "Runner's flag 1", bearing = 22.5, r = 340, position = Vector3.new(130.112, 47.876, -314.119), region = "Iris", slopeDegrees = 6.9, waterWithin32 = false },
	{ id = "F2", name = "Runner's flag 2", bearing = 67.5, r = 340, position = Vector3.new(314.119, 54.427, -130.112), region = "Iris", slopeDegrees = 2, waterWithin32 = false },
	{ id = "F3", name = "Runner's flag 3", bearing = 112.5, r = 340, position = Vector3.new(314.119, 45.679, 130.112), region = "Iris", slopeDegrees = 5.3, waterWithin32 = false },
	{ id = "F4", name = "Runner's flag 4", bearing = 157.5, r = 340, position = Vector3.new(130.112, 42.061, 314.119), region = "Iris", slopeDegrees = 5, waterWithin32 = false },
	{ id = "F5", name = "Runner's flag 5", bearing = 202.5, r = 340, position = Vector3.new(-130.112, 49.701, 314.119), region = "Iris", slopeDegrees = 2.7, waterWithin32 = false },
	{ id = "F6", name = "Runner's flag 6", bearing = 247.5, r = 340, position = Vector3.new(-314.119, 38.632, 130.112), region = "Iris", slopeDegrees = 13.7, waterWithin32 = true },
	{ id = "F7", name = "Runner's flag 7", bearing = 292.5, r = 340, position = Vector3.new(-314.119, 46.402, -130.112), region = "Iris", slopeDegrees = 1.9, waterWithin32 = false },
	{ id = "F8", name = "Runner's flag 8", bearing = 337.5, r = 340, position = Vector3.new(-130.112, 49.702, -314.119), region = "Iris", slopeDegrees = 3.6, waterWithin32 = false },
	{ id = "S1", name = "Single berm 1", bearing = 350, r = 640, position = Vector3.new(-111.135, 100.852, -630.277), region = "NorthWood", slopeDegrees = 18.4, waterWithin32 = false },
	{ id = "S2", name = "Single berm 2", bearing = 40, r = 680, position = Vector3.new(437.096, 109.119, -520.91), region = "NorthWood", slopeDegrees = 17.6, waterWithin32 = false },
	{ id = "S3", name = "Single berm 3", bearing = 100, r = 820, position = Vector3.new(807.542, 154.83, 142.392), region = "EastRidge", slopeDegrees = 19.5, waterWithin32 = false },
	{ id = "S4", name = "Single berm 4", bearing = 260, r = 760, position = Vector3.new(-748.454, 117.199, 131.973), region = "WestRidge", slopeDegrees = 26.4, waterWithin32 = false },
	{ id = "S5", name = "Single berm 5", bearing = 150, r = 560, position = Vector3.new(280, 36.275, 484.974), region = "Iris", slopeDegrees = 2.4, waterWithin32 = false },
	{ id = "S6", name = "Single berm 6", bearing = 315, r = 820, position = Vector3.new(-579.828, 162.167, -579.828), region = "NorthWood", slopeDegrees = 12.7, waterWithin32 = false },
	{ id = "S7", name = "Single berm 7", bearing = 70, r = 930, position = Vector3.new(873.914, 177.328, -318.079), region = "EastRidge", slopeDegrees = 10.7, waterWithin32 = false },
}

-- Trails[i]: the control points of each bare-earth path, heart outwards, Y = 0 (the v2 format). The path painted
-- into the terrain is a Catmull-Rom curve through them. TrailNames[i] is its name (TwoArenas 3.8).
ArenaLayout.TrailNames = { "Spiral Path", "Glade Path", "Lake Path" }
ArenaLayout.Trails = {
	{ Vector3.new(-173.205, 0, -100), Vector3.new(-285.788, 0, -165), Vector3.new(-482.136, 0, -194.795), Vector3.new(-606.218, 0, -350), Vector3.new(-548.687, 0, -609.379), Vector3.new(-430, 0, -744.782) },
	{ Vector3.new(173.205, 0, -100), Vector3.new(285.788, 0, -165), Vector3.new(508.829, 0, -317.952), Vector3.new(744.782, 0, -430), Vector3.new(831.384, 0, -480) },
	{ Vector3.new(0, 0, 200), Vector3.new(0, 0, 330), Vector3.new(39.064, 0, 558.636), Vector3.new(79.442, 0, 755.837) },
}

-- Stream: the one stream, from its spring in the north-west to the lake. points[i] = the centreline, with Y = the
-- DESIGNED water level there. The water in the game is voxels written from the data pack after its repairs (sills
-- between pools, levels snapped into their voxel layer): read the real surface from the terrain, not from here.
-- From the export: water steps down in ~45-stud pools from ~60 to 34; dip 6-12 deep, ~90 wide
ArenaLayout.Stream = {
	halfWidth = 4.6,
	points = {
		Vector3.new(-509.117, 60.65, -509.117), Vector3.new(-508.876, 60.65, -488.667), Vector3.new(-508.975, 60.65, -467.932),
		Vector3.new(-509.314, 60.65, -446.998), Vector3.new(-509.788, 60.65, -425.95), Vector3.new(-510.297, 60.65, -404.873),
		Vector3.new(-510.737, 60.65, -383.854), Vector3.new(-511.007, 60.65, -362.977), Vector3.new(-511.004, 60.65, -342.327),
		Vector3.new(-510.627, 60.65, -321.991), Vector3.new(-509.772, 60.65, -302.054), Vector3.new(-508.339, 49.74, -282.6),
		Vector3.new(-506.224, 49.74, -263.717), Vector3.new(-503.325, 49.74, -245.488), Vector3.new(-498.739, 45.06, -224.201),
		Vector3.new(-493.092, 45.06, -203.385), Vector3.new(-486.547, 42, -183.065), Vector3.new(-479.263, 42, -163.267),
		Vector3.new(-471.401, 41.01, -144.015), Vector3.new(-463.124, 41.01, -125.334), Vector3.new(-454.59, 40.9, -107.251),
		Vector3.new(-445.962, 40.9, -89.79), Vector3.new(-437.401, 40.9, -72.976), Vector3.new(-429.067, 40.9, -56.836),
		Vector3.new(-420.428, 40.9, -40.15), Vector3.new(-408.561, 40.9, -20.261), Vector3.new(-395.948, 40.9, -2.415),
		Vector3.new(-383.056, 40.9, 13.97), Vector3.new(-370.347, 40.9, 29.477), Vector3.new(-358.285, 40.9, 44.686),
		Vector3.new(-347.334, 40.9, 60.182), Vector3.new(-337.958, 40.9, 76.545), Vector3.new(-330.274, 38, 94.951),
		Vector3.new(-324.597, 38, 114.184), Vector3.new(-320.612, 38, 133.6), Vector3.new(-317.699, 38, 153.284),
		Vector3.new(-315.234, 37.45, 173.321), Vector3.new(-312.595, 37.45, 193.795), Vector3.new(-309.162, 34, 214.794),
		Vector3.new(-304.923, 34, 234.487), Vector3.new(-300.308, 34, 253.429), Vector3.new(-295.31, 34, 272.79),
		Vector3.new(-290.129, 34, 292.486), Vector3.new(-284.964, 34, 312.432), Vector3.new(-280.015, 34, 332.544),
		Vector3.new(-275.479, 34, 352.736), Vector3.new(-271.557, 34, 372.925), Vector3.new(-268.483, 34, 392.854),
		Vector3.new(-266.384, 34, 412.546), Vector3.new(-265.009, 34, 432.328), Vector3.new(-264.104, 34, 452.197),
		Vector3.new(-263.416, 34, 472.154), Vector3.new(-262.694, 34, 492.198), Vector3.new(-261.685, 34, 512.329),
		Vector3.new(-260.137, 34, 532.546), Vector3.new(-257.797, 34, 552.848), Vector3.new(-254.884, 34, 572.795),
		Vector3.new(-251.562, 34, 593.545), Vector3.new(-247.884, 34, 614.724), Vector3.new(-243.902, 34, 635.958),
		Vector3.new(-239.668, 34, 656.869), Vector3.new(-235.235, 34, 677.085), Vector3.new(-230.654, 34, 696.229),
		Vector3.new(-225.977, 34, 713.927), Vector3.new(-220.586, 34, 731.846), Vector3.new(-212.045, 34, 754.081),
		Vector3.new(-202.925, 34, 772.49), Vector3.new(-193.481, 34, 788.762), Vector3.new(-183.97, 34, 804.584),
		Vector3.new(-174.646, 34, 821.644),
	},
}

-- Edge: the cliff in the north. lipR = the lip's nominal radius (the real lip wanders: see the header); sector =
-- the bearings either side of north that the cliff spans; the ground above it is about canyonFloorY + cliffDrop.
ArenaLayout.Edge = { lipR = 1752, cliffDrop = 107, canyonFloorY = 133, sector = { -21, 21 } }

-- Lake: an ellipse. center.Y = the water level; radiusX = the east-west semi-axis, radiusZ = the north-south one.
ArenaLayout.Lake = { level = 34, center = Vector3.new(0, 34, 925), radiusX = 330, radiusZ = 128, depth = 14 }
-- <<< END GENERATED >>>

----------------------------------------------------------------------------------------------------
-- Fields worked out from the generated tables
----------------------------------------------------------------------------------------------------
-- Plates[i].cframe: on the turf at the plinth, facing the centre (what v2's Plates[i] was).
for _, plate in ipairs(ArenaLayout.Plates :: { any }) do
	local p = plate.position
	plate.cframe = CFrame.lookAt(p, Vector3.new(CX, p.Y, CZ))
end

-- getSite("B4") or getSite("The Stepping Stones") -> the site, or nil.
local siteByKey = {}
for _, site in ipairs(ArenaLayout.Sites) do
	siteByKey[site.id] = site
	siteByKey[site.name] = site
end
function ArenaLayout.getSite(idOrName: string)
	return siteByKey[idOrName]
end

-- Stream.samples: the centreline in the shape v2's River.samples had ({ x, z, y = water level, hw = half-width,
-- s = distance along it, fall, gorge }); Stream.spring and Stream.mouth are its two ends.
do
	local stream = ArenaLayout.Stream :: any
	local samples = {}
	local along = 0
	for i, p in ipairs(stream.points) do
		if i > 1 then
			local q = stream.points[i - 1]
			along += sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2)
		end
		samples[i] = { x = p.X, z = p.Z, y = p.Y, hw = stream.halfWidth, s = along, fall = false, gorge = 0 }
	end
	stream.samples = samples
	stream.length = along
	stream.spring = stream.points[1]
	stream.mouth = stream.points[#stream.points]
end

-- The lake is an ellipse. shoreRadius(phi): from its centre to the shore in direction phi (degrees clockwise from
-- north), as v2's Lake.shoreRadius. isInLake(position, margin): inside the ellipse grown by `margin` studs.
local lakeTable = ArenaLayout.Lake :: any
local LAKE_X, LAKE_Z = lakeTable.center.X, lakeTable.center.Z
local LAKE_RX, LAKE_RZ = lakeTable.radiusX, lakeTable.radiusZ

function lakeTable.shoreRadius(phi: number): number
	local a = rad(phi)
	return 1 / sqrt((sin(a) / LAKE_RX) ^ 2 + (cos(a) / LAKE_RZ) ^ 2)
end

local function inLake(x: number, z: number, margin: number): boolean
	local dx, dz = (x - LAKE_X) / (LAKE_RX + margin), (z - LAKE_Z) / (LAKE_RZ + margin)
	return dx * dx + dz * dz <= 1
end

function ArenaLayout.isInLake(position: Vector3, margin: number?): boolean
	return inLake(position.X, position.Z, margin or 0)
end

----------------------------------------------------------------------------------------------------
-- Regions and biomes
----------------------------------------------------------------------------------------------------
-- Map 1 has ten regions (Regions, generated). The ambience knows biomes by v2's names, so each region is given the
-- v2 name whose sound suits it, and AudioController needs no change (Map1Build decision 13). What AudioController
-- plays for each name: its BIOME_MIX row (the weights of its Amb_ beds by day / by night) and its BIOME_ENV reverb.
--   Meadow     ForestDay 0.8, Wind 0.45 / ForestNight 0.85, Wind 0.35; reverb Open
--   Field      Wind 0.75, ForestDay 0.55 / ForestNight 0.7, Wind 0.55; reverb Open
--   Forest     PineForest 1, ForestDay 0.45, Wind 0.25 / ForestNight 0.9, PineForest 0.45, Wind 0.25; reverb Forest
--   Cliffs     Highlands 0.8, Wind 0.6, PineForest 0.3 / Wind 0.8, Highlands 0.35, ForestNight 0.3; reverb Mountains
--   Mountains  Wind 1, Highlands 0.45 / Wind 1; reverb Mountains
--   Lake       Lake 1, ForestDay 0.3 / Lake 0.9, Swamp 0.35, ForestNight 0.3; reverb Lake
--   Lobby      Lobby 1, Wind 0.4, day and night; reverb Open
-- So the Heart sounds like the meadow it is: the day bed with a little wind. The open Iris is the same two beds with
-- the wind on top, which tells you that you have left the ring. The North Wood is the pine forest. The ridges and
-- the Edge are highland and wind with a mountain's echo (and a little pine: the wood is behind the Edge and in the
-- ridges' gullies). The mountain and everything past the field line is wind. The lake is water.
-- "Gorge" and "Marsh" are not used: Map 1 has neither. A name AudioController does not know would play its
-- "Woodland" bed with forest reverb, so only names from its two tables belong here.
local REGION_BIOME = {
	Heart = "Meadow",
	Iris = "Field",
	NorthWood = "Forest",
	EastRidge = "Cliffs",
	WestRidge = "Cliffs",
	SouthMountain = "Mountains",
	Lake = "Lake",
	Edge = "Cliffs",
	Crest = "Mountains",
	Outside = "Mountains",
}
local OUTSIDE_BIOME = "Mountains" -- beyond the map, and for a position that is not a position
ArenaLayout.RegionBiome = REGION_BIOME
ArenaLayout.Biomes = { "Meadow", "Field", "Forest", "Cliffs", "Mountains", "Lake", "Lobby" }

-- The lake's region is the water alone, so its shore would sound like the mountain. Within this many studs of the
-- water's edge the biome is "Lake" (v2 did the same, with 10 studs round a much smaller lake).
local LAKE_SHORE = 24

local REGION_ID = {}
for id, name in ipairs(ArenaLayout.Regions) do
	REGION_ID[name] = id
end

-- Distance bands: Map 1's regions from radius and bearing alone. These are the Blender generator's own rules without
-- their noise (the Iris ends at 600 +- 80 there, 150 farther out in the south). Used wherever the region grid cannot
-- answer: before Shared.Map1Regions has replicated, if it is missing or broken, and outside its +-1,920 studs.
local HEART_R, IRIS_R, IRIS_SOUTH_R, EDGE_FROM_R, EDGE_HALF_DEG = 190, 600, 750, 1640, 24
local PLAY_R, BOUNDARY_R = ArenaLayout.PlayRadius, ArenaLayout.BoundaryRadius

local function bandRegion(x: number, z: number): number
	local dx, dz = x - CX, z - CZ
	local r = sqrt(dx * dx + dz * dz)
	if not (r <= BOUNDARY_R) then
		return REGION_ID.Outside -- also where r is not a number
	elseif r > PLAY_R then
		return REGION_ID.Crest
	elseif r < HEART_R then
		return REGION_ID.Heart
	elseif inLake(x, z, 0) then
		return REGION_ID.Lake
	elseif r < IRIS_R then
		return REGION_ID.Iris
	end
	local a = deg(atan2(dx, -dz)) % 360
	if a >= 300 or a < 60 then
		if r >= EDGE_FROM_R and (a >= 360 - EDGE_HALF_DEG or a < EDGE_HALF_DEG) then
			return REGION_ID.Edge
		end
		return REGION_ID.NorthWood
	elseif a < 120 then
		return REGION_ID.EastRidge
	elseif a < 240 then
		return if r < IRIS_SOUTH_R then REGION_ID.Iris else REGION_ID.SouthMountain
	end
	return REGION_ID.WestRidge
end

local BAND_BIOME = {}
for id, name in ipairs(ArenaLayout.Regions) do
	BAND_BIOME[id] = REGION_BIOME[name] or OUTSIDE_BIOME
end

-- Shared.Map1Regions (written by tools/map1/pack.py): regionAt(x, z) -> id (10, Outside, beyond its grid), Names[id],
-- heightAt(x, z) -> y. The grid is 240 x 240 cells of 16 studs; the module is about 124,000 characters.
-- It is looked for when first needed, never waited for, and required in its own thread, so a module that is late,
-- missing, broken or slow can never make this layout error or yield: the caller gets distance bands meanwhile.
local regions: any = nil -- the module's table, once it has loaded
local biomeById: { [any]: string } = {} -- by the grid's region id (and by region name, should regionAt ever give one)
local regionsState = "none" -- "none" | "loading" | "ready" | "failed"
local regionsRetryAt = 0
local regionsFirstMissAt: number? = nil
local regionsFaults = 0
local regionsWarned = false

local function findRegionsModule(): ModuleScript?
	local parent = script.Parent
	local found = parent and parent:FindFirstChild("Map1Regions")
	if not found then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		found = shared and shared:FindFirstChild("Map1Regions")
	end
	return if found and found:IsA("ModuleScript") then found else nil
end

local function loadRegions(): any
	if regionsState ~= "none" then
		return regions
	end
	local now = os.clock()
	if now < regionsRetryAt then
		return nil
	end
	regionsRetryAt = now + 1
	local module = findRegionsModule()
	if not module then
		-- not replicated yet, or not installed: look again in a second; say so once if it stays away
		regionsFirstMissAt = regionsFirstMissAt or now
		if not regionsWarned and now - regionsFirstMissAt > 15 then
			regionsWarned = true
			warn("[ArenaLayout] Shared.Map1Regions is missing: getBiome and regionAt are using distance bands")
		end
		return nil
	end
	regionsState = "loading"
	task.spawn(function()
		local ok, result = pcall(function()
			-- Studio caches required modules in Edit mode: a clone picks up a module that was pushed again
			return require(if RunService:IsRunning() then module else module:Clone())
		end)
		if ok and type(result) == "table" and type(result.regionAt) == "function" then
			local names = if type(result.Names) == "table" then result.Names else ArenaLayout.Regions
			for id, name in pairs(names) do
				if type(id) == "number" and type(name) == "string" then
					biomeById[id] = REGION_BIOME[name] -- nil for a name this layout does not know: bands answer there
					biomeById[name] = REGION_BIOME[name]
				end
			end
			regions = result
			regionsState = "ready"
		else
			regionsState = "failed"
			warn("[ArenaLayout] Shared.Map1Regions did not load (" .. tostring(result) .. "): using distance bands")
		end
	end)
	return regions
end

-- A call into the grid failed. A few of those and the grid is dropped for good, so a broken module cannot cost an
-- error five times a frame.
local function regionFault(err: any)
	regionsFaults += 1
	if regionsFaults >= 5 and regionsState == "ready" then
		regions = nil
		regionsState = "failed"
		warn("[ArenaLayout] Shared.Map1Regions.regionAt keeps failing (" .. tostring(err) .. "): using distance bands")
	end
end

-- regionAt(x, z) -> (id, name): Map 1's region at a point (Regions[id]).
function ArenaLayout.regionAt(x: number, z: number): (number, string)
	local id: number? = nil
	local module = regions or loadRegions()
	if module and x == x and z == z then
		local ok, got = pcall(module.regionAt, x, z)
		if not ok then
			regionFault(got)
		elseif type(got) == "number" and ArenaLayout.Regions[got] then
			id = got
		elseif type(got) == "string" then
			id = REGION_ID[got]
		end
	end
	local known = id or bandRegion(x, z)
	return known, ArenaLayout.Regions[known]
end

-- getBiome(position) -> the biome name for the ambience. It never errors, for any argument, on any device.
function ArenaLayout.getBiome(position: Vector3): string
	if typeof(position) ~= "Vector3" then
		return OUTSIDE_BIOME
	end
	local x, z = position.X, position.Z
	if x ~= x or z ~= z then
		return OUTSIDE_BIOME
	end
	local lobby = ArenaLayout.LobbyPosition
	local lx, lz = x - lobby.X, z - lobby.Z
	if lx * lx + lz * lz < (ArenaLayout.LobbyRadius * 2) ^ 2 then
		return "Lobby"
	end
	if inLake(x, z, LAKE_SHORE) then
		return "Lake"
	end
	local module = regions or loadRegions()
	if module then
		local ok, id = pcall(module.regionAt, x, z)
		if ok then
			local biome = biomeById[id]
			if biome then
				return biome
			end
		else
			regionFault(id)
		end
	end
	return BAND_BIOME[bandRegion(x, z)]
end

----------------------------------------------------------------------------------------------------
-- Ground queries
----------------------------------------------------------------------------------------------------
local CAST_TOP = 1400 -- above the highest terrain (1,143, beyond the field line)
local CAST_DOWN = Vector3.new(0, -CAST_TOP - 200, 0)
local solidParams: RaycastParams? = nil -- made when first needed, so that loading the module touches nothing
local solidTerrain: Instance? = nil

-- groundAt(x, z) -> (y, normal, material)?: the top solid Terrain surface (water and every model ignored). nil where
-- no terrain is loaded: on a client that is anywhere outside what has streamed in.
function ArenaLayout.groundAt(x: number, z: number): (number?, Vector3?, Enum.Material?)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return nil
	end
	local params = solidParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.IgnoreWater = true
		solidParams = params
	end
	if solidTerrain ~= terrain then
		params.FilterDescendantsInstances = { terrain }
		solidTerrain = terrain
	end
	local hit = workspace:Raycast(Vector3.new(x, CAST_TOP, z), CAST_DOWN, params)
	if hit then
		return hit.Position.Y, hit.Normal, hit.Material
	end
	return nil
end

-- heightAt(x, z) -> y?: the ground from a Terrain raycast; where that finds nothing, from the coarse height grid in
-- Shared.Map1Regions (32-stud nodes: within about 1.5 studs on most ground, tens of studs out on cliffs; under water
-- it gives the bed). nil when neither can answer: the grid is only asked inside TerrainRadius, because beyond its
-- edge it repeats its edge.
local TERRAIN_R2 = ArenaLayout.TerrainRadius ^ 2

function ArenaLayout.heightAt(x: number, z: number): number?
	local y = ArenaLayout.groundAt(x, z)
	if y then
		return y
	end
	local dx, dz = x - CX, z - CZ
	if not (dx * dx + dz * dz <= TERRAIN_R2) then
		return nil
	end
	local module = regions or loadRegions()
	if module and type(module.heightAt) == "function" then
		local ok, h = pcall(module.heightAt, x, z)
		if ok and type(h) == "number" and h == h then
			return h
		end
	end
	return nil
end

return ArenaLayout
