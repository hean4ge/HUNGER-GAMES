--[[
	TrainingStations - the Training Centre's stations: where each one stands, what its chest lends, which kit its mat
	picks, and its drill (docs/design/TrainingAndLoadup.md sections 3.2, 3.3 and 3.5). Read by TrainingService (server)
	and TrainingController (client). Numbers only; no Instances are made here.

	COORDINATES
	  Hall-local studs: x east (-110..110), z north negative (-75..75), y up from the floor's top. The hall's floor
	  centre is TrainingStations.HallOrigin (place (8800, 200, 3000)) unless workspace.TrainingCentre exists, in which
	  case its pivot is the hall's origin (TrainingService.hallCFrame).
	  Each station has an `origin` (hall-local) and its spots are relative to that origin. A set that carries empties
	  overrides them: an Attachment or BasePart named "Station_<id>" (or with attribute TrainingStation = id) moves the
	  whole station; one named "TS_<id>.<spot>" (or attribute TrainingSpot = "<id>.<spot>") moves that one spot.

	CHESTS ("chests will have diff items based on such": the hall's half)
	  TrainingStations.chestItems(stationId) -> { { id, count } }   what that station's chest lends (training only)
	  station.chestLine: the chest prompt's words ("Borrow a bow and 12 arrows")
	  Borrowed items stay in their station's bay: leave the bay, pass the launch doors or reach the call and they go back.

	KITS (the orange mats)
	  station.mats = { { spot, kit = kitId } } or { { spot, specialty = familyId } } (the blade circle sets a Specialty)
	  Each mat's name stands on a small sign beside it (Shared.StationSign). Optional mat.sign = { at = mat-local floor
	  offset, face = "n" | "s" | "e" | "w" (the way the board looks), width?, icon? }; without it the board looks toward
	  the hall's middle from the mat's far side.

	DRILLS
	  station.drill = { id, name, time (s), need, total, line (how to), pass (words) , gives = attribute trained }
	  Fitness drills give progress toward Stamina or Strength, the survival corner toward Fieldcraft (section 3.5).
	  Tokens: 1 per pass (TokensPerDay a day), 1 more the first time a drill is ever passed.
]]

local TrainingStations = {}

TrainingStations.HallOrigin = CFrame.new(8800, 200, 3000)
TrainingStations.HallSize = Vector3.new(220, 36, 150)
TrainingStations.Arrival = Vector3.new(0, 3, 70) -- platform B side, inside the three arches (south of the track)
TrainingStations.FallDepth = 40 -- a body this far under the floor goes back to the arrival spot
TrainingStations.TokensPerDay = 8
TrainingStations.CooldownScale = 0.25 -- skills in the hall (SkillService reads the player attribute TrainingCooldownScale)
TrainingStations.LentTag = "TrainingLent"

-- The colour rule (ArtStyle rule 9): orange marks what you can use, nothing else in the hall is orange.
TrainingStations.Colors = {
	Use = Color3.fromRGB(226, 120, 44),
	UseDark = Color3.fromRGB(150, 78, 30),
	Teal = Color3.fromRGB(78, 112, 118),
	Floor = Color3.fromRGB(104, 116, 122),
	FloorLight = Color3.fromRGB(150, 158, 162),
	Steel = Color3.fromRGB(88, 92, 96),
	Board = Color3.fromRGB(226, 214, 190),
	Ring = Color3.fromRGB(186, 70, 48),
	Wood = Color3.fromRGB(112, 80, 52),
	Hay = Color3.fromRGB(196, 170, 104),
	Pad = Color3.fromRGB(70, 82, 88),
	Line = Color3.fromRGB(236, 232, 222),
}

local function v(x, y, z)
	return Vector3.new(x, y, z)
end

-- The obstacle run's line (hall x). The set models it on the hall's centre line (x = 0), the straight walk from the
-- middle arch to the launch doors, where its mantle wall stopped players on their way to the launch (wave 15).
-- TrainingCentreBuilder.prepare moves the set's vault, mantle and slide bar (with their colliders) to this line, so
-- the centre stays clear from the benches to the doors. At -6 it also stays clear of the straight walks from the side
-- arches (Arch_1 / Arch_3 at x -+40) to the doors, which cross z -37..-15 at x -+10..14.4 (at -7 the west walk
-- brushed the vault box's corner, wave 16): a stud or more of air either side of a walker.
TrainingStations.RunX = -6
local RX = TrainingStations.RunX

-- The station decks (wave 27 look pass, art/blender/training_centre_v2.py): the blade circle, survival, fitness and the
-- spear range stand on low teak decks this high. Their origins sit on the deck top, so every spot, mat, chest, dummy and
-- target of theirs stands on it; TrainingCentreBuilder lifts their art (and its markers) by the same height.
-- The archery strip behind the line is a flush inlay (the line, the lane pads and the targets stay on the floor).
TrainingStations.DeckHeight = 0.35
local DH = TrainingStations.DeckHeight

TrainingStations.List = {
	{
		id = "archery",
		name = "Archery lanes",
		short = "ARCHERY",
		bay = { min = v(40, -4, -35), max = v(110, 40, 75) },
		origin = v(72, 0, 70), -- the middle of the shooting line (behind the set's rail at z 67.8)
		lanes = 6,
		laneWidth = 8,
		targetDistances = { 20, 40, 60 }, -- the lane's names for its three targets
		-- where the pop-up faces stand: just in front of the set's targets (hall z 46.9 / 26.9 / 6.9, centre 4.6 up)
		targetDepths = { 22.6, 42.6, 62.6 },
		targetHeight = 4.6,
		spots = {
			mat = { pos = v(31, 0, 0), size = v(8, 0.2, 6) },
			chest = { pos = v(32, 0, -12), yaw = 90 },
		},
		mats = { { spot = "mat", kit = "archer" } },
		chestLine = "Borrow a bow and 12 arrows",
		chest = { { id = "short_bow", count = 1 }, { id = "arrow", count = 12 } },
		drill = {
			id = "archery", name = "Archery", time = 30, total = 6, need = 4, upTime = 4, gapTime = 1,
			line = "Step on a lane's orange line to start · 4 hits from 6 · the centre ring counts double",
			gives = nil, -- tokens only (section 3.5 trains ranks at fitness and survival)
		},
	},
	{
		id = "throwing",
		name = "Spear and throwing range",
		short = "THROWING",
		bay = { min = v(40, -4, -75), max = v(110, 40, -35) },
		origin = v(52, DH, -55), -- the throwing line (on the spear deck)
		boardDistances = { 10, 20, 30, 40, 50 }, -- studs east of the line (the set's boards)
		boardOffsets = { -7, 9, -3, 11, 1 }, -- studs north/south: staggered, so a near board never shields a far one
		boardFront = -0.7, -- the face stands this far in front of the set's board (west)
		boardHeight = 4.4,
		spots = {
			start = { pos = v(0, 0, 0), size = v(3, 0.2, 10) },
			mat = { pos = v(-6, 0, -1), size = v(6, 0.2, 8) },
			chest = { pos = v(-6, 0, 9), yaw = 90 },
			backstop = { pos = v(55, 0, -2) },
		},
		mats = { { spot = "mat", kit = "hunter", sign = { at = v(-1, 0, -4.9), face = "w" } } }, -- north end: the walk to the line stays clear
		chestLine = "Borrow a spear and 6 throwing knives",
		chest = { { id = "spear", count = 1 }, { id = "throwing_knife", count = 6 } },
		drill = {
			id = "throwing", name = "Throwing", time = 30, total = 5, need = 3, minDistance = 20,
			line = "Stand on the orange line · 3 hits from 5 throws, on boards 20 or further",
			gives = nil, -- tokens only (section 3.5 trains ranks at fitness and survival)
		},
	},
	{
		id = "blades",
		name = "Blade and axe circle",
		short = "BLADES",
		bay = { min = v(-110, -4, -20), max = v(-40, 40, 30) },
		origin = v(-75, DH, 7.5), -- the ring's centre (on the blade deck)
		ringRadius = 14,
		dummyRadius = 8,
		spots = {
			start = { pos = v(0, 0, 0), size = v(4, 0.2, 4) },
			chest = { pos = v(25, 0, -17.5), yaw = -90 },
			matFists = { pos = v(19, 0, -6), size = v(4, 0.2, 4) },
			matShortBlade = { pos = v(19, 0, -1), size = v(4, 0.2, 4) },
			matSword = { pos = v(19, 0, 4), size = v(4, 0.2, 4) },
			matAxe = { pos = v(19, 0, 9), size = v(4, 0.2, 4) },
		},
		mats = {
			{ spot = "matFists", specialty = "Fists" },
			{ spot = "matShortBlade", specialty = "ShortBlade" },
			{ spot = "matSword", specialty = "Sword" },
			{ spot = "matAxe", specialty = "Axe" },
		},
		-- the four dummies (section 3.3), at the compass points of the ring, facing its centre
		dummies = {
			{ stance = "Target", angle = 180, name = "Target" }, -- north
			{ stance = "Blocker", angle = 90, name = "Blocker" }, -- east
			{ stance = "Parrier", angle = 0, name = "Parrier" }, -- south
			{ stance = "Striker", angle = 270, name = "Striker" }, -- west
		},
		chestLine = "Borrow the circle's blades and axes",
		chest = {
			{ id = "knife", count = 1 }, { id = "machete", count = 1 }, { id = "hatchet", count = 1 },
			{ id = "sword", count = 1 }, { id = "twin_axe", count = 1 },
		},
		drill = {
			id = "blades", name = "Blades", time = 25, total = 10, need = 10, hitsNeed = 8, guardsNeed = 2,
			line = "Stand in the middle · 8 clean hits on the blocker and parrier, block or parry 2 of the striker's blows",
			gives = nil, -- tokens only (section 3.5 trains ranks at fitness and survival)
		},
	},
	{
		id = "survival",
		name = "Survival corner",
		short = "SURVIVAL",
		bay = { min = v(-110, -4, -75), max = v(-40, 40, -20) },
		origin = v(-75, DH, -47.5), -- (on the survival deck)
		spots = {
			fire = { pos = v(-13, 0, -4.5) },
			trough = { pos = v(11, 0, 3.5) },
			plants = { pos = v(11, 0, -18.5) },
			patient = { pos = v(-7, 0, 13.5), yaw = 90 },
			chest = { pos = v(29, 0, -16.5), yaw = 0 },
			matForager = { pos = v(11, 0, -9.5), size = v(8, 0.2, 4) },
			matMedic = { pos = v(1, 0, 13.5), size = v(4, 0.2, 6) },
		},
		mats = {
			{ spot = "matForager", kit = "forager" },
			{ spot = "matMedic", kit = "medic", sign = { at = v(1.2, 0, 3.9), face = "e" } }, -- south end: the patient is west
		},
		plants = { true, false, true, false, true, false }, -- sound (true) or spoiled: never poisonous (the Larder rule)
		plantStep = 1.8, -- studs between pots on the table (the set's Plant_1..6)
		chestLine = "Borrow firewood, a bottle, bandages and herbs",
		chest = {
			{ id = "firewood", count = 1 }, { id = "empty_bottle", count = 1 }, { id = "bandage", count = 2 },
			{ id = "herbs", count = 2 },
		},
		drill = {
			id = "survival", name = "Survival", time = 45, total = 4, need = 4,
			line = "Light the fire · fill a bottle at the trough · keep the three sound plants · bandage the dummy",
			gives = "Fieldcraft",
		},
	},
	{
		id = "fitness",
		name = "Fitness corner",
		short = "FITNESS",
		bay = { min = v(-110, -4, 30), max = v(-40, 40, 75) },
		origin = v(-75, DH, 52.5), -- (on the fitness deck)
		wallHeight = 24,
		spots = {
			wall = { pos = v(-31.8, 0, 0.5), size = v(1.6, 24.4, 30) }, -- its climbing face looks east (the set's wall)
			wallTop = { pos = v(-33.6, 24.4, 0.5), size = v(2.4, 1, 30) }, -- the ledge behind its top
			matClimber = { pos = v(-26, 0, 0.5), size = v(5, 0.2, 10) },
			bike1 = { pos = v(-15, 0, 11.5), yaw = 0 },
			bike2 = { pos = v(-9, 0, 11.5), yaw = 0 },
			bike3 = { pos = v(-3, 0, 11.5), yaw = 0 },
			bike4 = { pos = v(3, 0, 11.5), yaw = 0 },
			bench = { pos = v(17, 0, 16.9), yaw = 0 }, -- its bar lands on the set's weight rack
			chest = { pos = v(29, 0, -2.5), yaw = 180 },
		},
		bikeSeatHeight = 3.75, -- the seat's centre (the set's bikes are 3.6 high)
		mats = { { spot = "matClimber", kit = "climber", sign = { at = v(1.2, 0, 5.9), face = "e" } } }, -- south end: the wall is west
		chestLine = "Borrow a climbing pick",
		chest = { { id = "climb_pick", count = 1 } },
		drills = {
			wall = { id = "wall", name = "Climbing wall", time = 8, line = "Climb from the orange mat to the top in under 8 s",
				gives = "Strength" },
			bike = { id = "bike", name = "Bike", time = 40, green = 20,
				line = "Sit on a bike · keep the needle in the green for 20 s · tap Space (or the button) to pedal",
				gives = "Stamina" },
			weights = { id = "weights", name = "Weights", total = 10, need = 10, period = 1.1,
				line = "10 lifts on the beat · press when the ring meets the line", gives = "Strength" },
		},
	},
	{
		id = "track",
		name = "Track and obstacle run",
		short = "TRACK",
		bay = { min = v(-40, -4, -75), max = v(40, 40, 75) },
		origin = v(0, 0, 0),
		-- the lap: the set's track (radius 20, straights 87 at x = +-20, 300 studs on its centre line). Start and finish at
		-- gate 1 on the east straight, running north; then the north bend, the west straight, the south bend.
		gates = { v(20, 0, 0), v(0, 0, -63.5), v(-20, 0, 0), v(0, 0, 63.5) },
		gateRadius = 9,
		-- the obstacle run: along x = RunX from z -44 south to z -8 (spots turned 90: their local x runs along the run)
		spots = {
			lapStart = { pos = v(20, 0, 0), size = v(2, 0.2, 6), yaw = 90 },
			runStart = { pos = v(RX, 0, -44), size = v(4, 0.2, 6), yaw = 90 },
			vault = { pos = v(RX, 0, -36), size = v(3, 3, 6), yaw = 90 },
			mantle = { pos = v(RX, 0, -26), size = v(2, 5.5, 8), yaw = 90 },
			slide = { pos = v(RX, 0, -16), size = v(0.6, 1, 7.4), yaw = 90 }, -- a bar whose underside is 4.6 off the floor: slide or crouch under
			runEnd = { pos = v(RX, 0, -8), size = v(4, 0.2, 6), yaw = 90 },
		},
		mats = {},
		chest = nil,
		drills = {
			lap = { id = "lap", name = "Lap", time = 19, line = "One lap through the four gates in under 19 s", gives = "Stamina" },
			run = { id = "run", name = "Obstacle run", time = 12, line = "Vault, mantle, slide: from the orange pad to the far one in under 12 s",
				gives = "Stamina" },
		},
	},
}

local byId = {}
for _, station in ipairs(TrainingStations.List) do
	byId[station.id] = station
end

function TrainingStations.get(id: any)
	return if type(id) == "string" then byId[id] else nil
end

-- What a station's chest lends: a fresh copy, so callers may change counts.
function TrainingStations.chestItems(id: any): { { id: string, count: number } }
	local station = byId[id]
	local list = {}
	if station and station.chest then
		for _, item in ipairs(station.chest) do
			table.insert(list, { id = item.id, count = item.count })
		end
	end
	return list
end

-- Which station's bay holds this hall-local point (nil: the floor between, or outside the hall). The track's bay is
-- the middle floor and is checked last, so a side bay always wins at its edge.
function TrainingStations.bayAt(p: Vector3): string?
	local found = nil
	for _, station in ipairs(TrainingStations.List) do
		local b = station.bay
		if p.X >= b.min.X and p.X <= b.max.X and p.Z >= b.min.Z and p.Z <= b.max.Z and p.Y >= b.min.Y and p.Y <= b.max.Y then
			if station.id ~= "track" then
				return station.id
			end
			found = station.id
		end
	end
	return found
end

-- Is a hall-local point inside the hall (its walls plus a margin of `pad` studs)?
function TrainingStations.inHall(p: Vector3, pad: number?): boolean
	local m = pad or 0
	local h = TrainingStations.HallSize
	return math.abs(p.X) <= h.X / 2 + m and math.abs(p.Z) <= h.Z / 2 + m and p.Y >= -TrainingStations.FallDepth and p.Y <= h.Y + 20
end

-- The Specialty a lent weapon trains (the circle's chest): LoadoutCatalog family ids.
TrainingStations.SpecialtyOf = {
	knife = "ShortBlade", machete = "ShortBlade", hatchet = "Axe", twin_axe = "Axe", sword = "Sword",
	spear = "Spear", throwing_knife = "Throwing", short_bow = "Bow",
}

-- The quiet line a kit mat shows (section 3.2: "ARCHER · crates lean to arrows · kit lands mid-round").
TrainingStations.KitLines = {
	archer = "crates lean to arrows",
	forager = "crates lean to food and water",
	hunter = "crates lean to throwing knives and spears",
	medic = "crates lean to bandages and herbs",
	climber = "crates lean to the climbing pick and armour",
}

return TrainingStations
