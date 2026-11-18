--[[
	WildlifeConfig - every number of the squirrels (WildlifeService / WildlifeController) and of campfires and cooking
	(CookingService / CookingController). Server and clients read the same table. Edit freely to tune.

	What the numbers mean for a round (18 Nov 2026):
	  Hunger drains 100 in 14 minutes (7.1 a minute, more sprinting). A cooked squirrel gives 40: 5.6 minutes of
	  hunger, a little more than one Dried Meat (35) and close to what a tier-1 crate holds in food on average (about
	  46 across its 2-4 items). A raw one gives 8 and takes 8 thirst.
	  Squirrels on the map: Population.Base + PerContender x contenders, between Min and Max: 38 for a lone
	  contender, 94 for 8, 222 for 24, 240 for 32 and more. A hunted squirrel's home is empty for RespawnMin..Max
	  seconds (4 to 5 minutes), so a home feeds about three hunts in a 15-minute round.
]]
local WildlifeConfig = {}

WildlifeConfig.Squirrel = {
	-- how many live on the map (decided when the round starts, from the contenders and the start ring)
	Population = { Base = 30, PerContender = 8, Min = 24, Max = 240 },
	-- where: shares of the population. Meadow = trees inside EdgeRadius (the beech copses between the plinths and
	-- the wood), Edge = the first EdgeBand studs of the wood, Deep = the rest of the wood inside the ring.
	EdgeRadius = 540,
	EdgeBand = 170,
	MeadowShare = 0.3,
	EdgeShare = 0.35,
	MeadowPerTree = 0.5, -- never more meadow squirrels than this x the meadow's trees
	GroveMin = 2, -- they live in small groups: this many homes round one tree...
	GroveMax = 3,
	GroveRadius = 28, -- ...on trees this close to it
	GroveSpacing = 55, -- and groups stand at least this far apart
	BorderMargin = 30, -- no home closer than this to the start ring
	RespawnMin = 240, -- seconds a hunted squirrel's home stays empty
	RespawnMax = 300,
	RespawnClear = 50, -- ...and no contender may stand this close when the next one comes down the tree

	-- the server's work: only squirrels a player can see are simulated, and never more than AwakeBase +
	-- AwakePerPlayer x players (AwakeMax at most); the rest keep their last state
	TickRate = 4, -- simulation steps a second
	InterestIn = 190, -- a squirrel's state is sent to players this close to its home...
	InterestOut = 235, -- ...and dropped beyond this
	PerPlayerCap = 40, -- squirrels one client is told about at a time
	AwakeBase = 16,
	AwakePerPlayer = 6,
	AwakeMax = 96,

	-- senses (studs): how close a contender gets before a squirrel on the ground notices
	NoiseSprint = 58, -- sprinting (server speed above Config.Movement.SprintSpeedThreshold)
	NoiseMove = 30, -- jogging or walking upright
	NoiseStand = 16, -- standing still
	NoiseCrouchMove = 9, -- crouch-walking
	NoiseCrouchStill = 5, -- crouched and still
	WatchfulScale = 1.25, -- a squirrel sitting up notices from this much further
	PanicRange = 5, -- this close it bolts without the sit-up
	AlertMin = 0.55, -- seconds it sits up and stares before it bolts (the stalker's window)
	AlertMax = 1.0,
	AlertStay = 1.2, -- it bolts when the contender is still inside noise x this when the stare ends

	-- movement (studs / s)
	HopSpeed = 5,
	FleeSpeed = 21, -- a sprint's pace: it reaches its tree before you reach it
	ClimbSpeed = 9,
	DescendSpeed = 7,
	HomeRange = 16, -- it forages this far from its tree
	FleeTreeRange = 36,
	PerchConifer = { 13, 18 }, -- how high it sits on a fir or pine: out of a spear's reach, in a bow's
	PerchBeech = { 9, 12 },
	CalmRange = 55, -- it comes down when no contender has been this close...
	CalmMin = 14, -- ...for this long (seconds)
	CalmMax = 24,
	ShuffleRange = 32, -- a moving contender this close makes it slip round the trunk, at most every ShuffleEvery s
	ShuffleEvery = 2.5,

	-- hits
	HitRadius = 0.9, -- an arrow or thrown knife passing this close to its middle hits
	HitRadiusSpear = 1.2,
	MeleeReachBonus = 0.8, -- added to the weapon's range
	MeleeAimRadius = 1.7, -- how far off the look line its middle may be
	CarcassDelay = 0.45, -- seconds after the hit before the Squirrel item lies there
	CarcassItem = "squirrel",

	-- drawing (client), by DetailController's tier: { how many, how far, how far the tail and head move }
	Draw = {
		Low = { count = 8, distance = 95, animate = 35 },
		Medium = { count = 14, distance = 135, animate = 50 },
		High = { count = 24, distance = 175, animate = 70 },
	},
}

WildlifeConfig.Campfire = {
	FirewoodItem = "firewood",
	GatherHold = 2.0, -- seconds holding the prompt at a tree
	GatherCooldown = 3.0, -- seconds between two bundles for one player (server)
	GatherRange = 9, -- studs from the trunk
	BuildHold = 1.2,
	BuildRange = 11, -- studs from you to where the fire goes
	LightHold = 1.2,
	PutOutHold = 1.2,
	UseRange = 11, -- studs from the fire for every prompt (server-checked; the prompts themselves show at 8)
	PromptRange = 8,
	MinSpacing = 5, -- studs between two fires
	MaxSlope = 0.82, -- the ground normal's Y must be at least this
	PerPlayer = 1, -- fires one contender keeps going; building another puts their oldest out
	MaxFires = 40, -- on the whole map
	BurnTime = 150, -- seconds a lit fire burns
	FeedTime = 90, -- seconds one more bundle adds...
	MaxBurn = 240, -- ...up to this much ahead
	OutTime = 45, -- seconds the ashes stay
	UnlitTime = 240, -- an unlit fire nobody lights is cleared after this
	CookTime = 6, -- default seconds on the spit (an item's own cookTime wins)
	WarmRange = 9, -- studs: a lit fire warms contenders this close...
	WarmHealPerSecond = 0.25, -- ...this much health a second
	LightRange = 26, -- PointLight range
	LightBrightness = 1.7,
	-- drawing (client)
	DrawDistance = 1100, -- fires further than this are not drawn
	DrawCount = { Low = 6, Medium = 10, High = 14 },
	SmokeRate = { Low = 1.6, Medium = 2.6, High = 3.6 }, -- smoke particles a second
	SmokeLife = { 9, 12 }, -- seconds a smoke particle lives: the column stands about 60 studs
}

return WildlifeConfig
