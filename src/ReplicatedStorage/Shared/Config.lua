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
	-- Still alone when it ends, they go again after a PracticeIntermissionTime-second Intermission (no second wait).
	-- A player who arrives during a practice round ends it PracticeHandoffTime seconds later (the lone contender
	-- "survived the practice round"). Practice rounds never add Wins, TotalKills or RoundsPlayed.
	SoloPractice = true,
	SoloWaitTime = 30,
	PracticeHandoffTime = 60,
	PracticeIntermissionTime = 8,
	-- Filling a public server (RoundService). On a live public server (not Studio, not a private server) a player who
	-- joins during the Intermission restarts its countdown, so the first two players do not start alone while the
	-- server is still filling; it never runs longer than FillMaxTime seconds from its start, and with FillTarget or
	-- more already waiting it is not held at all (a busy server keeps its pace between rounds). A private server
	-- (game.PrivateServerId ~= "", GameState.PrivateServer = true) starts with whoever is there after the normal
	-- IntermissionTime. A round takes MaxContenders at most: the others watch, and whoever played least recently is
	-- picked first for the next round.
	FillExtendOnJoin = true,
	FillTarget = 8,
	FillMaxTime = 90,
	-- When the Intermission ends with two or more players present but fewer than two of them ready (still loading or
	-- respawning), the pick waits up to this many seconds instead of starting a practice round for the one who is ready.
	StartHoldTime = 10,
	-- The finale (QW14, Q3): the ring keeps closing to nothing beside the Spire (Config.Border.LastStand*), the border
	-- never takes the last contender standing, and a timeout with two or more alive goes to the healthiest (then the
	-- most kills). Roll Calls once the border moves post their names in the 2D list only (no sky show, no silence).
	LastStand = true,
	-- The epilogue (QW14, Q3): the fallen not yet shown in the sky get a short Roll Call (caption + all of them together,
	-- about 20 s) behind the winner card; Ending grows to fit it. EpilogueLeadIn = seconds of winner card first.
	Epilogue = true,
	EpilogueLeadIn = 2.5,
}

-- The road to the arena (docs/design/TrainingAndLoadup.md section 2; TrainRideService, TrainRideController): after the
-- Intermission the train departs, rides RideTime s to the Training Centre, players train for TrainingTime s, the launch
-- doors open DoorsOpenBefore s before the call and the call comes early once every held contender has stood on the red
-- room's disc ReadyHold s (ReadyLead s later, never before MinTraining s of training). Alone: SoloWaitTime s at the
-- station, a SoloIntermissionTime s Intermission, a SoloRideTime s ride and SoloTrainingTime s of training with the
-- doors open from the start. A second player arriving then makes it a real round, the call at least LateJoinFloor s
-- away. Enabled = false: today's flow exactly (Intermission -> the call; SoloWaitTime and IntermissionTime as above).
-- The launch, the countdown and the round's clock are not changed by any of it.
Config.TrainFlow = {
	Enabled = true,
	RideTime = 25,
	SoloRideTime = 15,
	TrainingTime = 90,
	SoloTrainingTime = 60,
	DoorsOpenBefore = 40,
	ReadyHold = 3,
	ReadyLead = 5,
	MinTraining = 30,
	LateJoinFloor = 30,
	SoloWaitTime = 20,
	SoloIntermissionTime = 10,
	SkipHold = 0.6, -- hold Space (A, or the SKIP line on touch) this long to skip a ride you have ridden this session
	HallCentre = Vector3.new(8800, 200, 3000), -- the stand-in hall's floor centre (when there is no workspace.TrainingCentre)
}

Config.Border = {
	StartRadius = 640,
	FinalRadius = 35,
	ShrinkStartTime = 600, -- seconds after the start horn (09:00 on day 2)
	ShrinkDuration = 230, -- fully closed at 830 s, just after the second sunset
	-- The wall never moves faster than this (studs a second of round time, the slide of its centre included). A ring too
	-- big to close in ShrinkDuration at that speed starts earlier, as early as it must, and still closes at
	-- ShrinkStartTime + ShrinkDuration; ArenaService publishes each round's own start as GameState.BorderShrinkStart.
	-- GameState.BorderShrinking still turns true at ShrinkStartTime (the final closing). nil or 0 = no limit.
	MaxShrinkSpeed = 3.5,
	DamagePerSecond = 4,
	LateDamagePerSecond = 10, -- once the border has fully closed
	WarningLeadTime = 30, -- warn this many seconds before it starts moving
	WallPanels = 96, -- segments in the client-side border wall
	WallHeight = 520, -- studs (the wall starts 110 studs below the clearing)
	-- The wall's look (ArenaController; owner, 18 Nov: "hollow blue"). A see-through barrier in a clear, cool blue: a
	-- bright line on the ground, a thin rail above it and thin posts between them (the outline), an almost empty
	-- sheet and a slow rising lattice only where you stand close to it. Nothing with any area shows from far away, so
	-- the valley and the sky keep their own colours. WallColor: the sheet, the rail, the posts and the lattice.
	-- WallLineColor: the ground line and the lattice bars (a little lighter, so it reads on grass and on the lake).
	-- OutsideTint: the screen's grade while you are outside the border (a cold blue-grey; it was a soft red).
	WallColor = Color3.fromRGB(44, 112, 255), -- (Neon draws a colour brighter and nearer cyan than it is written)
	WallLineColor = Color3.fromRGB(56, 124, 255),
	OutsideTint = Color3.fromRGB(176, 204, 255),
	-- Stages (optional). nil: the ring closes in one run, as described above. A list: the ring closes in stages and
	-- rests between them. Each stage is { at = the round second it starts moving, over = seconds it moves,
	-- radius = where it stops }, in order; the last one must end at FinalRadius, and ShrinkStartTime / ShrinkDuration
	-- must be the last stage's at / over (the final closing: GameState.BorderShrinking, the music, the HUD's line).
	-- ArenaService warns WarningLeadTime seconds before every stage, starts a stage earlier (never before the stage
	-- before it has stopped) if it would otherwise move faster than MaxShrinkSpeed, and publishes GameState
	-- BorderStage, BorderStageCount, BorderMoving, BorderNextMoveAt and BorderMoveEndAt.
	Stages = nil,
	-- Small rounds start smaller (QW3; opened up in wave 2 after "why so small"): the start radius grows with the
	-- headcount N, from MinStartRadius for a lone contender to StartRadius at FullContenders:
	-- MinStartRadius + (StartRadius - MinStartRadius) * sqrt((N - 1) / (FullContenders - 1)) (500 alone, 529 for 2,
	-- 565 for 6, 597 for 12, 640 at 24: a lone player's ring takes in the caves, the hunter's cabin and the watchtower),
	-- published at the Countdown as GameState.BorderStartRadius (read it instead of StartRadius).
	ScaleWithContenders = true,
	MinStartRadius = 500,
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
	-- Zoom (V held; R3 or the touch ZOOM button toggles; CameraController): a real look closer, much stronger than the
	-- aim. "x" is how many times bigger things look: tan(72 / 2) / tan(fov / 2). The multiplier is given at BaseFov; a
	-- player with another Field of view setting gets the same magnification. A swing, a throw, a bow draw, the aim of a
	-- bow or spear (which keeps its own zoom: the two never add up), eating, drinking, bandaging and a menu end it; it
	-- turns the sprint widening off and slows the look by the same ratio.
	ZoomFovMultiplier = 0.45, -- the default level: 72 -> 32.4 vertical, 2.5x (the bow's aim is 1.4x)
	-- While the zoom is on, the mouse wheel changes its level. Each notch multiplies (or divides) the magnification by
	-- ZoomWheelStep, so a notch feels the same at every level: 1.56x, 1.76x, 1.98x, 2.22x, 2.5x, 2.81x, 3.16x, 3.56x, 4x.
	-- The level is kept until the player leaves.
	ZoomWheelStep = 1.125,
	ZoomWheelStepsOut = 4, -- notches the wheel can pull back from the default: to 1.56x (72 -> 49.9, FOV x0.69)...
	ZoomWheelStepsIn = 4, -- ...and push in: to 4x (72 -> 20.6, FOV x0.29)
	ZoomInTime = 0.18, -- seconds for the view to ease in (98 % of the way; no overshoot)...
	ZoomOutTime = 0.14, -- ...back out...
	ZoomStepTime = 0.1, -- ...and from one wheel level to the next
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
	-- the lobby is the red train since 18 Nov (10.5 studs to the ceiling, 19 wide): a closer third person keeps the
	-- camera inside the car (was 12, 6..20: it rose above the roof and looked down through it)
	LobbyZoom = 7,
	LobbyMinZoom = 3,
	LobbyMaxZoom = 10,
}

Config.Combat = {
	MeleeHitRadius = 2.4,
	MeleeLagTolerance = 3, -- extra studs the server allows for latency
	DefaultHeadshotMultiplier = 1.6,
	ProjectileMaxLifetime = 12, -- seconds a shot is simulated (a full-draw arrow lofted high is up ~9 s); a miss that
	-- outlives it is traced on to where its arc meets the ground
	-- Spent arrows, throwing knives and thrown spears stay where they end up until the round's arena cleanup
	-- (ProjectileService.WorldProjectiles, Shared.WorldItems): embedded where they hit, on the bed under water, or in a
	-- body until it dies or BodyFallOutTime passes. Taken by walking over them (Config.Loot.AutoPickup) or with E.
	WorldItemCap = 400, -- safety cap per server: above it the oldest go first (logged)
	BodyFallOutTime = 30, -- seconds an arrow stays in a living contender or dummy before it falls out by itself
	PickupReachAbove = 4.3, -- studs above the root a hand reaches (~7 studs above the feet); higher needs a climb or jump
	ArrowStickTime = 20, -- a client's own stuck copy, only when the server left nothing in the world for that shot
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
	-- Thrown knives and spears land on the crosshair the same way: the throw is lifted so its own arc (speed, gravity)
	-- passes through the point under the crosshair (CombatController.releaseThrow). false = thrown along the look.
	ThrowAimOnTarget = true,
	EquipTime = 0.32, -- seconds after equipping before you can attack (bows take a little longer)
	-- PlayabilityPlan Q2 (decided 14 Nov, owner's note): 1.8 = a full-draw headshot does 90, so one arrow can't kill
	-- from full health (2 did 100, a whole health bar).
	BowHeadshotMultiplier = 1.8,
	-- Swing sets (#90, CombatController): a swing that starts this soon (s) after the same weapon's last swing ended
	-- continues the chain (the next set in order); later, a fresh click takes another set at random. Never one set twice.
	SwingChainWindow = 0.45,
	ThirdPersonSwings = true, -- other players' swings show on their bodies (CharacterVisuals, from CombatAction "Swing")
}

-- First-person arms (ViewmodelController). "Blocky" (the default): a Roblox character's arms, square blocks built from
-- Parts, the hand in your avatar's own arm colour, matte, lit by the engine alone (no lamp, no overlay); relaxed and low
-- when empty, fists only for a punch and the short guard after it. The older styles stay selectable: "Faceted": the
-- faceted Blender hands and forearms (Assets.Viewmodel.ArmsFaceted: bare skin in your avatar's arm colours, a charcoal
-- sleeve); "Avatar": your own avatar's R15 arms (skin colour and shirt, rebuilt when your appearance changes);
-- "Classic": the original part-built arms (dark sleeves, block fists).
Config.Viewmodel = {
	ArmStyle = "Blocky", -- "Blocky" | "Faceted" | "Avatar" | "Classic"
	-- The block arms (ViewmodelController.Blocky). Each value is read when the arms are built.
	Blocky = {
		Variant = "A", -- the hand. "A": one block. "B": a palm block, one four-finger block and a thumb block
		Sleeve = "Jacket", -- "Jacket": a long sleeve to the wrist. "Bare": bare arms. "Short": rolled up to mid-forearm
		SleeveColor = Color3.fromRGB(96, 88, 80),
		SleeveMaterial = Enum.Material.SmoothPlastic, -- (clean and without gloss in game; Fabric shows its weave up close)
		SkinMaterial = Enum.Material.SmoothPlastic,
		SkinMaxValue = 0.92, -- the hand colour's brightest channel is held to this (pure white arms would bloom in full sun)
		-- Nothing lights the block arms but the engine. When the sun is gone its fill light is strong and the ground is
		-- dark, so a pale hand would be several times brighter than everything round it; these values bring pale arm
		-- colours down, by colour alone, at dusk (DuskDarken), at night (NightDarken), under trees (ShadeDarken by day and
		-- NightShadeDarken at night, times how much sky is covered; SunShadeDarken when the sun is hidden from the eye),
		-- never below MinExposure. Dark colours (a dark skin tone, the sleeve) are not darkened. At night under open sky
		-- they are lifted instead, until their brightest channel reaches NightFloor (their unlit faces rendered black; 0:
		-- off; not under cover, where the whole scene is black). Shade = false: all of this off.
		Shade = {
			DuskDarken = 0.36,
			NightDarken = 0.30,
			ShadeDarken = 0.30,
			NightShadeDarken = 0.40,
			SunShadeDarken = 0.15,
			MinExposure = 0.5,
			NightFloor = 0.5,
			Adapt = 3, -- how fast it follows the light (1/s)
		},
	},
	GuardHold = 1.5, -- (Blocky, Faceted) seconds the fists stay up as a guard after the last punch before the hands relax
	ArmScale = 0.46, -- avatar arms are drawn this wide, a fraction of the avatar's (a full-width Roblox arm fills the view)
	ArmReach = 1.34, -- ... and this long, shoulder to wrist in studs, whatever the avatar's proportions (the poses' reach)
	ArmMaterial = Enum.Material.SmoothPlastic,
	ArmShadows = false, -- the arms cast shadows (onto each other, the held item and the ground)
	-- The light on the avatar arms (ViewmodelController.Shade): the whole viewmodel brought down toward the scene's
	-- level at dusk (DuskDarken), at night (NightDarken) and under cover (ShadeDarken by day, NightShadeDarken at night,
	-- times how much sky is covered; never below MinExposure); a soft spot light above the arms where the world gives no
	-- direct light (KeyBrightness, KeyRange studs, KeyAngle degrees, KeyHeight studs above them, KeyLean toward the sun or
	-- moon, KeyTint toward the sky's colour); and the shade layer that gives black clothing the shape of the light
	-- (ShadeColor at ShadeTransparency). Adapt: how fast it follows the light (1/s).
	Shade = {
		DuskDarken = 0.38,
		NightDarken = 0.45,
		ShadeDarken = 0.15,
		NightShadeDarken = 0.5,
		SunShadeDarken = 0.3, -- (by day, when the sun is up but hidden from the eye: canopy, roofs)
		MinExposure = 0.18,
		KeyBrightness = 0, -- owner, 15 Nov: no lamp over the hands ("weird glowy light"); was 1.5
		KeyDuskBoost = 1.2, -- (the key x (1 + this) in the twilight, whose flat fill is bright)
		KeyRange = 4.5,
		KeyAngle = 120,
		KeyHeight = 2, -- (high above the arms, so their tops catch it and their inner sides fall off)
		KeyLean = 0.35,
		KeyTint = 0.55,
		ShadeColor = Color3.fromRGB(235, 235, 240),
		ShadeTransparency = 0.72, -- (sleeves)
		HandShadeTransparency = 0.86, -- (hands: fainter, so skin keeps its colour)
		Adapt = 3,
	},
}

Config.Inventory = {
	Slots = 6,
	AutoEquipWeapons = true, -- picking up a weapon while empty-handed puts it straight in your hand
	UseFinishTolerance = 0.25, -- seconds a UseFinish may arrive early (network jitter)
	DropForwardSpeed = 8, -- toss speed (studs/s) when you drop an item
	DropUpSpeed = 10,
	EquipRequestsPerSecond = 8, -- server-side rate limit for EquipSlot (each change rebuilds the held model for everyone near)
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
	-- QW3: markers further out than the round's start radius + BorderMargin get no loot (negative: that far inside the
	-- ring, so nothing lies out at the wall where the border hurts)
	BorderMargin = -10,
	CrateSpacing = 5, -- studs kept between crates: one whose marker is closer to another moves aside, or is left out
	-- QW8: an opened crate's items land beside it, in view. The opener gets "Take all" on the crate (everything that fits
	-- goes in the bag; the rest stays for anyone) until they press it or walk TakeAllWalkAway studs from the crate.
	-- Items in AutoPickup that you already carry are picked up when you walk within AutoPickupRange studs of them (spent
	-- ones ProjectileService left in the world even if you carry none); arrows only with a bow (E still takes them).
	TakeAll = true,
	TakeAllWalkAway = 14,
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

-- Weapons v2 (docs/design/Weapons_v2.md). Any key left out takes its default in Shared.Kits / Shared.Rewards.
-- THE KIT SWITCH: Delivery = "Midpoint" (the kit comes down near the player at the middle of the round) or "Start"
-- (the kit goes into the bag at the launch).
Config.Kits = {
	Delivery = "Midpoint",
}
-- Gold for Robux stays OFF until the owner says yes (developer products, maturity questionnaire: rules.md section 4).
-- While it is off Gold can never be bought, so the wheel and the Strongboxes are not paid random items.
Config.Economy = {
	RobuxGold = false,
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

-- The launch intro for the beta (LaunchIntroController; TwoArenas.md section 2, Tier 1: built from Parts on each
-- client). At the call every contender watches one shot on the round's clock: the red room under the net, the cut to
-- the glass cases (the full shot only), the rise up the pole through the round hall with the camera circling, a short
-- white-out, then today's plate rise in first person and the last seconds of the countdown. The full shot plays when
-- at least FullCutShare of the round's contenders haven't seen it yet this session (player attribute Launched), the
-- short cut otherwise; practice rounds play PracticeCut. The countdown grows to fit: FullCountdown / ShortCountdown seconds from the call
-- to the horn, the plates rising at FullRiseAt / ShortRiseAt (GameState LaunchAt) as the white-out ends, and the
-- "Stay on your plate" announcements only in the last AnnounceLast seconds. Intro = false: today's countdown
-- (Round.CountdownTime) and plate rise, unchanged. Studio only: GameState attribute LaunchCutTest = "Full" | "Short"
-- forces a cut (tests).
Config.Launch = {
	Intro = true,
	FullCountdown = 22,
	FullRiseAt = 15.4,
	ShortCountdown = 12,
	ShortRiseAt = 6.2,
	PracticeCut = "Short", -- "Short" | "Full"
	-- The full shot plays only when at least this share of the round's contenders has not seen it this session (a
	-- server's first round: everyone). One newcomer among many no longer makes every contender wait through the long
	-- cut; they see the short one. 0 = the full shot whenever any contender is new.
	FullCutShare = 0.5,
	AnnounceLast = 10,
	SkipHold = 0.6, -- seconds to hold Skip (Space / A / the SKIP button); it only cuts your own camera to your plate
	StandIns = 8, -- other contenders shown as copies of their avatars (the rest as plain figures); fewer on Medium / Low
}

-- The arena (docs/design/Map1Build.md, decision 14). Config.Map names the arena this place holds. Config.Maps[name]
-- holds that arena's own numbers, section by section; they are laid over the sections above when this module loads, so
-- every reader keeps reading Config.Round, Config.Border, Config.Events and Config.Loot. What belongs to the world
-- itself (the centre, the plinth ring, the lobby's place) comes from ReplicatedStorage.Shared.ArenaLayout, which must
-- be the same arena's: ArenaService warns at start-up when the layout's Map field and Config.Map disagree.
--   "ClassicForest"  the forest valley (vaulted in ServerStorage.Vault_ClassicForest): 24 plates round the Spire
--   "GreenLand"      Map 1, the Green Land: 48 plinths round the Horn, a field of radius 1,800
Config.Map = "GreenLand"

Config.Maps = {
	ClassicForest = {
		Round = { MaxContenders = 24 },
		Border = {
			StartRadius = 640,
			MinStartRadius = 500,
			FullContenders = 24,
			FinalRadius = 35,
			FinalSpireGap = { 15, 25 },
			WallPanels = 96,
			WallHeight = 520,
		},
		Events = { FeastWarning = 45 },
		Loot = { SpireRefillRadius = 90, FeastDropHeight = 55 },
	},
	GreenLand = {
		-- Owner, 18 Nov 2026 (evening): "make it shrink slower and make the world map more open for people to explore".
		-- A round is 20 minutes at most (it was 15), so the ring can rest wide open first and then close slowly in
		-- stages. The day/night schedule is the old one stretched by 4/3 (same hours, same order):
		--   sunset 1 at 6:53 (413 s), the moon at 7:36, Roll Call 1 at 7:40 (460 s), the vigil to 8:45, a moonlit night of
		--   2.3 minutes, the moon sets at 11:10, sunrise at 11:51 (711 s), the Offering at 13:05 (785 s, 08:30 on day 2),
		--   sunset 2 at 18:01 (1,081 s), Roll Call 2 at 18:45 (1,125 s, in the list only: the final closing is on), the
		--   time limit at 20:00.
		Round = {
			MaxContenders = 48, -- one per plinth
			MaxRoundTime = 20 * 60,
			DaySchedule = {
				{ 0, 7.4 },
				{ 360, 17.0 },
				{ 440, 18.5 },
				{ 460, 19.45 },
				{ 525, 20.45 },
				{ 660, 28.45 },
				{ 700, 29.6 },
				{ 740, 31.0 },
				{ 1065, 41.6 },
				{ 1105, 42.6 },
				{ 1125, 43.45 },
				{ 1200, 44.55 },
			},
		},
		Border = {
			-- Every round starts with the whole field open (radius 1,800), whatever the head count: ScaleWithContenders
			-- is off. Until 18 Nov (evening) a lone contender's ring started at 700 and two contenders' at 860, and a
			-- lone tester never reached the lake. MinStartRadius is not read while the scaling is off (Map1.Audit still
			-- wants it under StartRadius; it is the number to go back to).
			StartRadius = 1800,
			ScaleWithContenders = false,
			MinStartRadius = 700,
			FullContenders = 48,
			-- The ring rests wide open for 3:30, then closes in four stages with 45 seconds of rest between them, and
			-- never moves faster than 2.5 studs a second (it was 3.5; a jog is 13, a crouched walk 6.5):
			--   stage 1   3:30 to  7:45   1,800 to 1,200   2.35 studs/s (2.49 with the slide of its centre)
			--   stage 2   8:30 to 12:05   1,200 to   700   2.33         (2.46)   the lake (r 800) is inside until 11:20
			--   stage 3  12:50 to 16:00     700 to   300   2.11         (2.23)   the Offering falls at 13:05, ring 668
			--   stage 4  16:45 to 19:00     300 to    60   1.78         (1.88)   the final closing
			--   the Last Stand, 19:00 to 19:55: 60 to nothing (1.09), as before.
			-- Until 18 Nov it closed in one run at up to 3.5 studs/s and had closed at 13:50 (a full ring from 5:04, a lone
			-- contender's 700 from 10:00).
			MaxShrinkSpeed = 2.5,
			Stages = {
				{ at = 210, over = 255, radius = 1200 },
				{ at = 510, over = 215, radius = 700 },
				{ at = 770, over = 190, radius = 300 },
				{ at = 1005, over = 135, radius = 60 },
			},
			ShrinkStartTime = 1005, -- the last stage: the final closing (was 600)
			ShrinkDuration = 135, -- closed at 1,140 s (19:00; was 830 s, 13:50)
			-- The ring is 60 wide when the Last Stand begins, round a point on the turf 90 to 100 studs from the Horn (the
			-- layout's LastStandPoints: the middle of a mouth lane), so it never closes on the platform.
			FinalRadius = 60,
			FinalSpireGap = { 15, 25 }, -- used only when the layout has no LastStandPoints: this far past AssetInfo.Spire.r
			WallPanels = 160, -- 71 studs each at r 1,800; their corners stand 0.35 studs outside the circle, as the forest's did
			WallHeight = 800, -- from 110 below the knoll (y -64) to y 736: above the ground on the start circle (524) and the peak (640)
		},
		-- the Offering at 08:30 on day 2, as before (785 s on the 20-minute schedule; it was 590). The ring is about 840
		-- studs out two minutes before it and 668 at it (51 s at a jog), so the warning comes two minutes ahead (it reads
		-- "in 2 minutes"; ThreatLine words 90 s as 2 minutes too)
		Events = { FeastTime = 785, FeastWarning = 120 },
		Loot = {
			SpireRefillRadius = 90, -- the Horn's floor, its deck and the foot of its steps (r 0 to 40)
			FeastDropHeight = 55, -- (markers under the Horn's sails carry DropIn = false: restocked in place)
			-- How much loot there is. LootService puts a crate on every Crate marker and an item on GroundSpawnChance of
			-- the Ground markers inside the round's start ring, so the amount is the marker set, and
			-- ServerStorage.WorldGen.Map1.Loot builds that set from this plan (edit time; nothing reads it in a round):
			-- fixed markers at the Horn, the runner's flags and the sites (the sites' counts are written for
			-- SiteContenders and grow with Round.MaxContenders), then scattered tier-1 ground markers at one density over
			-- the whole field, as many as bring a full round's expected loot to ItemsPerContender a head (a crate counts
			-- as the mean of CrateItemsMin..Max, a ground marker as GroundSpawnChance). One density means a smaller
			-- round's loot follows its ring's area: it keeps the Horn and the nearer sites, and a share of the rest.
			Plan = {
				ItemsPerContender = 10,
				SiteContenders = 24,
			},
		},
	},
}

do
	local map = Config.Maps[Config.Map]
	if type(map) ~= "table" then
		warn("[Config] Config.Map names no arena in Config.Maps (" .. tostring(Config.Map) .. "); using ClassicForest")
		Config.Map, map = "ClassicForest", Config.Maps.ClassicForest
	end
	for section, values in pairs(map) do
		local target = (Config :: any)[section]
		if type(target) == "table" and type(values) == "table" then
			for key, value in pairs(values) do
				target[key] = value
			end
		end
	end
end

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
		-- the train flow, short (TrainingAndLoadup.md 2.3): a 6 s ride, 20 s of training, the doors open at 8 s.
		-- (Live keeps the real numbers: GameState attribute TrainFlowLive = true uses them in a Studio test.)
		Config.TrainFlow.Live = table.clone(Config.TrainFlow)
		Config.TrainFlow.RideTime = 6
		Config.TrainFlow.SoloRideTime = 6
		Config.TrainFlow.TrainingTime = 20
		Config.TrainFlow.SoloTrainingTime = 20
		Config.TrainFlow.DoorsOpenBefore = 12
		Config.TrainFlow.MinTraining = 8
		Config.TrainFlow.LateJoinFloor = 12
	end
end

return Config
