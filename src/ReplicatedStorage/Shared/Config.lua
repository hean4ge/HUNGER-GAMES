--[[
	Config - every tunable number in one place.
	Each section belongs to one system (see docs/GameDesign.md). Edit values freely to tune the game.
	The Studio block at the bottom only applies inside Roblox Studio, never on live servers.
]]
local RunService = game:GetService("RunService")

local Config = {}

Config.GameTitle = "LAST STANDING" -- working title (rename freely)
Config.IsStudio = RunService:IsStudio()

Config.Round = {
	MinPlayers = 2, -- players needed in the lobby before intermission starts
	MaxContenders = 24, -- one per plinth
	IntermissionTime = 25, -- lobby countdown once enough players are waiting
	CountdownTime = 10, -- frozen on the plinths before the start horn
	MaxRoundTime = 15 * 60, -- hard cap on round length (seconds)
	EndingTime = 10, -- victory screen before everyone returns to the lobby
	RespawnDelay = 4, -- seconds after death before you're back in the lobby
	LobbyClockTime = 14.5, -- lighting hour while in the lobby
	StartClockTime = 7.4, -- in-game hour when a round starts (= DaySchedule[1])
	EndClockTime = 20.55, -- in-game hour (on day 2) when MaxRoundTime is reached (= DaySchedule's last entry, 44.55)
	RollCallClockTime = 19.45, -- each dusk's Roll Call, "The Fallen": just after the moon takes over (19.25)
	-- The day/night schedule across the round: { round seconds, in-game hour (unwrapped: 31 = 07:00 on day 2) }.
	-- Day 1 morning -> golden hour, sunset (18:00, ~310 s) -> blue hour -> the moon takes over (19.25, ~342 s) ->
	-- Roll Call 1 (19.45, 345 s) while the clock slows (the vigil) -> a moonlit night of ~2.7 minutes -> the moon
	-- sets (4.75, ~503 s) -> sunrise (06:00, ~534 s) -> the Feast (590 s) -> the border closes (600-830 s) ->
	-- sunset 2 (~812 s) -> Roll Call 2 (43.45, 845 s) if the round lasts. Shared.DayCycle interpolates it and hides
	-- the engine's sun/moon switches; clients move the sun every frame.
	DaySchedule = {
		{ 0, 7.4 },
		{ 270, 17.0 },
		{ 330, 18.5 },
		{ 345, 19.45 },
		{ 395, 20.45 },
		{ 495, 28.45 },
		{ 525, 29.6 },
		{ 555, 31.0 },
		{ 800, 41.6 },
		{ 830, 42.6 },
		{ 845, 43.45 },
		{ 900, 44.55 },
	},
	LaunchDelay = 0.8, -- seconds into the Countdown before the launch plates start to rise
	LaunchRiseTime = 3.4, -- seconds the plates take to rise out of their tubes
	LaunchDepth = 10, -- studs the plates start below the surface (at most; each tube's own depth limits it)
	LobbyFallDepth = 80, -- lobby players this far below the lobby surface are put back on a spawn
	StudioTimeScale = 1, -- Studio only: > 1 runs the round schedule (clock, Feast, border, Roll Call, time limit) faster
	-- Quiet servers (PlayabilityPlan QW1, Q5): a player alone in the lobby of a live server for SoloWaitTime seconds
	-- gets a practice round (training dummies included); GameState.SoloStartAt = when its contenders are chosen.
	-- A player who arrives during a practice round ends it PracticeHandoffTime seconds later (the lone contender
	-- "survived the practice round"). Practice rounds never add Wins, TotalKills or RoundsPlayed.
	SoloPractice = true,
	SoloWaitTime = 30,
	PracticeHandoffTime = 60,
	-- The finale (QW14, Q3): the ring keeps closing to nothing beside the Spire (Config.Border.LastStand*), the border
	-- never takes the last contender standing, and a timeout with two or more alive goes to the healthiest (then the
	-- most kills). Roll Calls once the border moves post their names in the 2D list only (no sky show, no silence).
	LastStand = true,
	-- The epilogue (QW14, Q3): the fallen not yet shown in the sky get a short Roll Call (caption + all of them together,
	-- about 20 s) behind the winner card; Ending grows to fit it. EpilogueLeadIn = seconds of winner card first.
	Epilogue = true,
	EpilogueLeadIn = 2.5,
}

Config.Border = {
	StartRadius = 640,
	FinalRadius = 35,
	ShrinkStartTime = 600, -- seconds after the start horn (09:00 on day 2)
	ShrinkDuration = 230, -- fully closed at 830 s, just after the second sunset
	DamagePerSecond = 4,
	LateDamagePerSecond = 10, -- once the border has fully closed
	WarningLeadTime = 30, -- warn this many seconds before it starts moving
	WallPanels = 96, -- segments in the client-side border wall
	WallHeight = 520, -- studs (the wall starts 110 studs below the clearing)
	-- Small rounds start small (QW3): the start radius is clamp(StartRadius * sqrt(N / FullContenders), MinStartRadius,
	-- StartRadius) for N contenders (320 up to 6, 370 at 8, 453 at 12, 640 at 24), published at the Countdown as
	-- GameState.BorderStartRadius (read it instead of StartRadius).
	ScaleWithContenders = true,
	MinStartRadius = 320,
	FullContenders = 24,
	-- The Last Stand (QW14, Config.Round.LastStand): from ShrinkStartTime + ShrinkDuration (830 s) the ring closes from
	-- FinalRadius to nothing over LastStandDuration seconds (by 885 s). While the border closes its centre slides from
	-- the Spire to a point FinalSpireGap studs beyond the Spire's base on open plaza ground (picked per round).
	-- Outside the Last Stand ring: LastStandDamagePerSecond + LastStandDamageRamp for every second spent outside.
	LastStandDuration = 55,
	LastStandDamagePerSecond = 10,
	LastStandDamageRamp = 2,
	FinalSpireGap = { 15, 25 },
	-- A practice round's Last Stand stops at this radius instead of nothing (a lone contender has no rival to outlast;
	-- standing inside it survives the practice round). 0 = close to nothing in practice too.
	PracticeLastStandRadius = 8,
}

Config.Events = {
	FeastTime = 590, -- the Spire is restocked (08:30 on day 2, an hour after sunrise)
	FeastWarning = 45,
	FeastDuration = 30, -- seconds GameState.ArenaEvent stays "Feast"
}

Config.Survival = {
	MaxHealth = 100,
	HungerDrainPerSecond = 100 / (14 * 60), -- full to empty in 14 minutes
	ThirstDrainPerSecond = 100 / (9 * 60), -- full to empty in 9 minutes
	SprintDrainMultiplier = 1.6,
	SprintSpeedThreshold = 17, -- horizontal speed above which the server counts you as sprinting
	StarveDamagePerSecond = 1.5, -- per empty meter
	RegenPerSecond = 0.6,
	RegenMinStat = 55, -- hunger and thirst must both be above this to regenerate
	RegenDelayAfterDamage = 8,
	DrinkPerSip = 10,
	DrinkSipTime = 0.7,
	DrinkRange = 9,
	KillCreditWindow = 15, -- seconds an attacker keeps credit for an environmental death
	VoidHeight = -80, -- contenders below this height have fallen out of the world
}

Config.Movement = {
	-- Scale: an R15 contender is ~5.2 studs tall, so 1 stud ~ 0.33 m. Paces are real-world plausible but brisk
	-- for a 1300-stud arena: the default pace is a jog (13 studs/s ~ 4.3 m/s), a sprint is 21 (~7 m/s).
	-- Speeds (studs/s)
	WalkSpeed = 13, -- the default pace (a jog); an analog stick walks below full deflection
	SprintSpeed = 21,
	CrouchSpeed = 6.5,
	SwimSpeed = 8, -- breaststroke cruise (strokes surge and glide); hold Sprint to swim harder (Swim.SprintSpeed)
	ClimbSpeed = 5.5, -- average hand-over-hand climbing speed (each stroke pulls, then pauses to regrip)
	UseItemSpeed = 8, -- move speed while eating, drinking or bandaging
	AimSpeedMultiplier = 0.8, -- while aiming a bow or spear
	StrafeMultiplier = 0.88, -- side-stepping is slower than running forward...
	BackpedalMultiplier = 0.68, -- ...and walking backwards slower still (first person)
	SprintMaxAngle = 50, -- you can sprint up to this many degrees off where you look
	ExhaustedSpeedMultiplier = 0.9, -- jogging pace while exhausted
	FatigueSprintMultiplier = 0.86, -- the sprint fades to this as the last 30% of stamina runs out
	-- Momentum: a friction-circle model on top of the Humanoid (no instant starts, stops or turns)
	PushAcceleration = 48, -- studs/s^2 push-off from standing (force-limited): ~0.32 s to a jog
	RunPower = 340, -- power limit (accel = RunPower / speed): a jog builds into a full sprint over ~0.4 s
	BrakeAcceleration = 34, -- stopping with no input (~1 g): ~0.3 s from a jog...
	BrakePerSpeed = 0.9, -- ...harder from speed: a ~0.5 s, ~5-stud skid from a sprint
	TurnAcceleration = 95, -- lateral grip: turns carve wider at speed (~4.5 rad/s at a sprint), sharp turns cost speed
	AirControl = 0.22, -- fraction of push-off acceleration available in the air
	AirDrag = 0.4, -- studs/s^2 of drag in the air with no input (momentum is kept)
	-- Jumping, air and landing
	JumpHeight = 3, -- jump apex in studs (~1 m: an athletic hop; mantling handles anything taller)
	AirGravity = 125, -- studs/s^2 while airborne. Roblox's 196.2 is ~6.6 g at character scale; this is ~4 g:
	FallGravityScale = 1.08, -- natural-looking arcs that still feel weighty (a touch heavier on the way down)
	JumpCooldown = 0.4,
	JumpStaminaCost = 0.08,
	ExhaustedJumpScale = 0.8, -- jump height multiplier while exhausted
	RepeatJumpWindow = 0.45, -- jumping again this soon after landing a jump...
	RepeatJumpScale = 0.8, -- ...is lower and costs 50% more stamina: no bunny-hopping
	CoyoteTime = 0.1, -- you can still jump this long after walking off a ledge
	JumpBufferTime = 0.12, -- a jump pressed this long before landing still happens (once JumpGroundTime has passed)
	JumpPrepTime = 0.1, -- a standing jump starts with a short knee dip (s; Animate plays the take-off from it)...
	JumpPrepTimeMoving = 0.06, -- ...shorter on the move (momentum, one-footed take-off)
	JumpGroundTime = 0.2, -- after a landing the feet stay down this long before the next take-off: no bunny-hops
	LandingStunHeight = 5, -- drops higher than this (studs) cost speed for a moment...
	HardLandingHeight = 10, -- ...above this you stumble; fall damage starts at FallDamage.MinHeight
	LandingMaxSpeedLoss = 0.55,
	LandingHopSpeedLoss = 0.06, -- each landed jump at speed absorbs a little momentum
	StepLengthWalk = 2.3, -- footstep length (studs) of the walk clip...
	StepLengthRun = 4.85, -- ...and of the run clip (blended 8 -> 11.5 studs/s, like Animate): footsteps and head-bob
	-- stay in step with the legs (~2.8 steps/s walking, ~2.7 jogging, ~4.3 sprinting)
	Slope = {
		MaxWalkableAngle = 46, -- degrees (ground normal): steeper ground can't be walked up, you slide down it
		UphillSlowdown = 0.9, -- speed x (1 - this * sin(slope)): 10 deg -> 84%, 20 deg -> 69%, 30 deg -> 55%
		DownhillBoost = 0.55, -- speed x (1 + this * sin(slope)) up to DownhillBoostMaxAngle (+14% at 15 deg)...
		DownhillBoostMaxAngle = 15,
		SteepDownhillBrake = 1, -- ...then you brake with every step (30 deg: 91%, 40 deg: 77%)
		StumbleAngle = 18, -- sprinting down slopes steeper than this builds instability until you stumble
		StumbleRate = 4, -- (about 1.3 s of sprinting down a 30 deg slope; sooner on poor grip)
		UphillDrainAngle = 15, -- walking uphill steeper than this: no stamina recovery...
		UphillStaminaDrain = 0.12, -- ...and a slow drain (per second, per unit of sine above the threshold)
		SlideAcceleration = 38, -- sliding down unwalkable ground: accel x (sin - friction * grip * cos)
		SlideFriction = 0.55,
		SlideMaxSpeed = 26,
	},
	-- Speed multiplier, Grip (acceleration, braking and turning) and Effort (stamina) per ground material.
	-- Anything not listed (rock, slate, basalt, cobblestone, concrete, brick, asphalt...) is firm ground (1, 1, 1).
	Surfaces = {
		Grass = { Speed = 1, Grip = 0.95, Effort = 1 },
		LeafyGrass = { Speed = 0.95, Grip = 0.9, Effort = 1.08 }, -- undergrowth
		Ground = { Speed = 1, Grip = 1, Effort = 1 },
		Mud = { Speed = 0.72, Grip = 0.5, Effort = 1.45 },
		Sand = { Speed = 0.84, Grip = 0.72, Effort = 1.3 },
		Snow = { Speed = 0.8, Grip = 0.6, Effort = 1.35 },
		Glacier = { Speed = 0.95, Grip = 0.28, Effort = 1.1 },
		Ice = { Speed = 0.95, Grip = 0.2, Effort = 1.1 },
		Salt = { Speed = 0.96, Grip = 0.85, Effort = 1.05 },
		Pebble = { Speed = 0.94, Grip = 0.82, Effort = 1.1 },
		SmoothPlastic = { Speed = 1, Grip = 0.85, Effort = 1 },
		Plastic = { Speed = 1, Grip = 0.9, Effort = 1 },
		Metal = { Speed = 1, Grip = 0.85, Effort = 1 },
		Marble = { Speed = 1, Grip = 0.8, Effort = 1 },
		Glass = { Speed = 1, Grip = 0.7, Effort = 1 },
		Foil = { Speed = 1, Grip = 0.7, Effort = 1 },
	},
	Swim = {
		SprintSpeed = 11.5, -- holding Sprint in water (drains stamina)
		SprintDrain = 0.07,
		StrokeLength = 5.5, -- studs per stroke (two strokes per cycle)
		StrokePulse = 0.35, -- how much each stroke surges the speed (0 = constant)
		ExitMaxHeight = 3.8, -- a bank up to this high above the water can be climbed onto (push into it or jump)
		WadeStartDepth = 0.35, -- water deeper than this (studs) slows you...
		WadeFullDepth = 3.2, -- ...by up to WadeMaxSlowdown at waist depth; no sprinting deeper than ~1.8
		WadeMaxSlowdown = 0.55,
	},
	Stamina = {
		SprintDrain = 0.11, -- per second (about 9 s of sprinting from full; more uphill and on soft ground)
		ClimbDrain = 0.09,
		Regen = 0.2,
		RegenDelay = 1.0,
		IdleRegenBonus = 1.35, -- regen multiplier while standing still or crouched
		ExhaustedThreshold = 0.25, -- after hitting 0 you can't sprint until stamina is back above this
		MantleCost = 0.03, -- per mantle or vault...
		MantleCostPerStud = 0.012, -- ...plus this per stud of ledge height (mantles only)
	},
	Stance = {
		CrouchHeadTop = 4.3, -- crouching lowers the head top to about this height (fits under 4.5-stud gaps)
		BlendTime = 0.16, -- seconds to crouch or stand back up
	},
	Slide = {
		MinEntrySpeed = 15,
		Boost = 1.15,
		MaxSpeed = 28,
		Friction = 15, -- studs/s^2 on firm ground (less on mud, snow and ice: you slide further)
		SlopeAcceleration = 40,
		MaxTime = 1.2,
		MinTime = 0.35, -- releasing crouch ends the slide only after this long
		DownhillTimeScale = 0.35, -- the slide timer runs slower while sliding downhill
		HardMaxTime = 3.5,
		SteerRate = 1.2, -- rad/s of steering while sliding
		Cooldown = 0.7,
		EndSpeed = 8,
	},
	Mantle = {
		MinHeight = 2.2, -- ledge height above your feet
		MaxHeight = 6.5,
		MaxHeightFromJump = 7.8, -- a jump-and-grab reaches ledges up to this far above the take-off ground
		Reach = 3.2, -- how far ahead (from your centre) a sprint vault looks for an obstacle
		GrabDistance = 1.9, -- how close a ledge must be to mantle it after a jump
		PushTime = 0.18, -- pushing forward into a ledge this long mantles it without jumping
		TimeLow = 0.45, -- seconds to pull up onto a waist-high ledge...
		Time = 0.8, -- ...and a head-high one (x1.3 when exhausted, x1.15 out of water)
		VaultMinHeight = 1.3,
		VaultMaxHeight = 3.4,
		VaultTime = 0.36,
	},
	Climb = {
		Reach = 2.5, -- a Climbable surface this close in front of you can be climbed
		StandOff = 0.85, -- distance kept between the root and the surface
		LateralFactor = 0.6, -- sideways climbing speed as a fraction of ClimbSpeed
		PushOffSpeed = 12, -- jumping off a climb
		PushOffUp = 22,
		EntryPushTime = 0.15, -- pushing into a Climbable this long starts a climb (or press jump)
		StrokeLength = 2.6, -- studs climbed per hand-over-hand cycle
		StrokePulse = 0.6, -- how much each pull surges the climb (0 = constant speed)
	},
	FallDamage = {
		MinHeight = 13, -- drops above this (studs, ~4.3 m) hurt...
		LethalHeight = 58, -- ...and this one (~19 m) kills a healthy contender; water cushions any fall
		Exponent = 1.15, -- damage = MaxHealth * ((h - Min) / (Lethal - Min)) ^ Exponent
	},
}

Config.Camera = {
	BaseFov = 72, -- vertical degrees (about 104 horizontal on 16:9); players can change it in Settings
	SprintFovAdd = 3.5, -- subtle widening at a full sprint
	SlideFovAdd = 6,
	AimFovMultiplier = 0.76, -- aiming a bow or spear zooms in a little
	-- First-person head motion from the gait (mostly translation: real eyes stabilise the gaze)
	BobWalkAmplitude = 0.085, -- studs of vertical head travel at a jog (peak to peak)...
	BobSprintAmplitude = 0.14, -- ...and at a full sprint
	BobCrouchScale = 0.55,
	BobSwayRatio = 0.55, -- sideways sway toward the stance foot, as a fraction of the vertical bob (less running)
	BobRollDegrees = 0.35,
	BobNodDegrees = 0.45, -- tiny nod at each footfall when running
	StrafeTiltDegrees = 1.2,
	TurnLeanDegrees = 1.4, -- lean into fast turns at speed
	SlideTiltDegrees = 4,
	LandingDipMax = 0.7, -- studs, scaled by the drop height
	JumpPrepDip = 0.14, -- studs the eye drops in the knee dip before a take-off
	LandingPitchDegrees = 2.4,
	IdleBreathAmplitude = 0.012,
	ExertedBreathAmplitude = 0.045, -- heavy breathing after hard effort and while exhausted
	ExertedBreathPitchDegrees = 0.6,
	StepSmoothing = 14, -- 1/s: the eye eases up after a step-up instead of snapping...
	MaxStepLag = 1.25, -- ...lagging at most this far behind
	ShakeMaxDegrees = 2.6,
	ForwardOffset = 0.5, -- studs the eye sits in front of the head centre, so you don't see inside your neck
	LookDownForward = 0.55, -- extra forward eye offset when looking straight down (you see your legs, not your chest)
	LookDownDrop = 0.3,
	LookUpBack = 0.25,
	LobbyZoom = 12,
	LobbyMinZoom = 6,
	LobbyMaxZoom = 20,
}

Config.Combat = {
	MeleeHitRadius = 2.4,
	MeleeLagTolerance = 3, -- extra studs the server allows for latency
	DefaultHeadshotMultiplier = 1.6,
	ProjectileMaxLifetime = 4,
	ArrowRecoverChance = 0.5,
	ArrowStickTime = 20,
	DummyRespawnTime = 3,
	PracticeDummies = 3,
	DummyHealth = 200,
	DummyRegenDelay = 4, -- a training dummy heals back to full after this long without being hit
	RangedOriginTolerance = 6, -- studs a shot's reported origin may be from the server-side head (plus MeleeLagTolerance)
	CooldownJitter = 0.12, -- seconds of network jitter forgiven on attack cooldowns
	MinBowCharge = 0.2, -- releasing a lighter draw lets the string down instead of shooting
	ViewBowDraw = 1.35, -- first-person string pull at full draw (studs): brings the nock to an under-chin anchor
	-- Arrows land where the crosshair points: the release direction is solved so the arc passes through the point
	-- under the crosshair (or BowZeroDistance studs out when nothing is under it). The arc and the speed are unchanged;
	-- out of range (a weak draw at a far target) the arrow flies along the crosshair and drops short.
	BowAimOnTarget = true,
	BowZeroDistance = 100,
	BowMaxLiftDegrees = 25, -- never lift the release more than this above the crosshair
	EquipTime = 0.32, -- seconds after equipping before you can attack (bows take a little longer)
	-- PlayabilityPlan Q2 (open): 2 = a full-draw headshot does 100, a full health bar; the plan proposes 1.8 (90).
	BowHeadshotMultiplier = 2,
}

Config.Inventory = {
	Slots = 6,
	AutoEquipWeapons = true, -- picking up a weapon while empty-handed puts it straight in your hand
	UseFinishTolerance = 0.25, -- seconds a UseFinish may arrive early (network jitter)
	DropForwardSpeed = 8, -- toss speed (studs/s) when you drop an item
	DropUpSpeed = 10,
	EquipRequestsPerSecond = 20, -- server-side rate limit for EquipSlot
	FullAt = 95, -- QW12: food is refused at Hunger >= this and drinks at Thirst >= this (client and server)
}

Config.Loot = {
	CrateItemsMin = 2,
	CrateItemsMax = 4,
	CrateOpenTime = 0.6,
	GroundSpawnChance = 0.65, -- chance a Ground marker gets an item each round
	PickupRange = 10, -- server-side max distance from your root to a crate or ground item you use
	DeathDropScatter = 3, -- radius (studs) a fallen contender's items scatter over
	CratePromptDistance = 8,
	ItemPromptDistance = 7,
	LidOpenTime = 0.45,
	SpillDelay = 0.09, -- seconds between items popping out of an opened crate
	TossGravity = 70, -- studs/s^2 for tossed and spilled items
	SpireRefillRadius = 90, -- Tier-3 markers this close to the arena centre are restocked by the Feast
	FeastDropHeight = 55, -- Feast crates fall into place from this height
	ItemLightRange = 5,
	ItemLightBrightness = 0.9,
	BorderMargin = 30, -- QW3: markers more than this far outside the round's start radius get no loot
	-- QW8: after the open, the opener gets "Take all" on the crate for TakeAllTime seconds (everything that fits goes in
	-- the bag; the rest stays for anyone). Items in AutoPickup that you already carry are picked up when you walk
	-- within AutoPickupRange studs of them.
	TakeAllTime = 3,
	AutoPickup = { arrow = true, throwing_knife = true },
	AutoPickupRange = 3.5,
	-- QW11: Common and Uncommon ground items glint faintly too. New players (Config.Guidance) see an outline on the
	-- nearest CrateOutlineMax unopened crates within CrateOutlineRange studs for the first CrateOutlineTime seconds.
	CommonGlint = true,
	CrateOutline = true,
	CrateOutlineTime = 90,
	CrateOutlineRange = 25,
	CrateOutlineMax = 8,
	-- QW7 (Q4): the runner's caches, tier-2 crates at the meadow edge (markers with attribute Runner = true, positions
	-- in ArenaLayout.RunnerCaches) rolled from ItemDefs.LootTables.Runner, each marked by a pale canvas on a pole.
	RunnerCaches = true,
}

-- Help for new players (PlayabilityPlan Q1). Mode: "Auto" = players with fewer than NewPlayerRounds real rounds
-- (the RoundsPlayed attribute, read at the Countdown) get the extra help, which fades as they learn; "Always"; "Off".
-- A player's own Guidance setting (ClientState.settings.guidance, when it exists) overrides Mode.
Config.Guidance = {
	Mode = "Auto",
	NewPlayerRounds = 3,
	-- QW2 action hints (Shared.ActionHints, InventoryController): the full line for the first HintFullUses successful
	-- uses of an action, then only its button until HintKeyUses, then nothing. A new player holding food or a drink for
	-- StallTime seconds with that meter under StallBelow gets the full line back once a round.
	HintFullUses = 3,
	HintKeyUses = 6,
	StallTime = 10,
	StallBelow = 40,
}

-- One threshold per feedback signal (PlayabilityPlan QW5)
Config.Feedback = {
	LowHealth = 0.35, -- health fraction for the LOW tag, the red vignette and the heartbeat
}

Config.Studio = {
	-- Only applied inside Roblox Studio. Set to false to test real pacing.
	SoloTest = true, -- a round can start with 1 player (practice mode)
	FastTimers = true, -- short lobby, countdown and ending timers
}

if Config.IsStudio then
	if Config.Studio.SoloTest then
		Config.Round.MinPlayers = 1
	end
	if Config.Studio.FastTimers then
		Config.Round.IntermissionTime = 6
		Config.Round.CountdownTime = 8 -- room for the launch plates to rise (about 4 s) before the numbers run out
		Config.Round.EndingTime = 6
		Config.Round.RespawnDelay = 2
	end
end

return Config
