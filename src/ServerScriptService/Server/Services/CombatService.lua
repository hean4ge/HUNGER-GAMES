--[[
	CombatService - server-authoritative melee and ranged combat, plus the training dummies of practice rounds.

	Client -> server
	  MeleeSwing("Start", variant: number?) sent when a swing starts: the others near the attacker are told at once
	    (CombatAction "Swing" with lead = the weapon's windup), so they see the swing begin before the blow lands
	  MeleeSwing(lookDirection: Vector3, predictedHit: boolean, variant: number?, target: Model?, startTime: number?)
	    sent at the strike moment of a swing;
	    predictedHit = the attacker's own trace touched someone (CombatController): a swing their screen showed as a miss
	    never lands. variant (optional) = the swing's set, an integer 1-8: passed on to the other clients so they show the
	    same swing (CharacterVisuals); any other value is ignored and the swing goes ahead without it.
	    target (optional) = the body that trace touched: the server checks that one body and no other, so a bystander
	    in the swing's path never takes the hit. startTime (optional) = workspace:GetServerTimeNow() when the swing
	    started on the attacker's client (see trySwing)
	  RangedRelease(shotId, origin, direction, charge, mode)
	    "Fire"   bow shot: consumes 1 arrow; speed and damage scale with charge (capped by the measured draw time).
	             Needs a "Draw" for that bow first; a charge under Config.Combat.MinBowCharge is refused
	    "Throw"  throwing knife (consumes 1) or spear (removes the equipped spear)
	    "Draw"   the bow draw started: the server times the charge and tells other clients (CombatAction "Draw")
	    "Cancel" the draw was let down without shooting
	Server -> client
	  HitConfirm { damage, headshot, killed, position? (hit point), target = "Player" | "Dummy", weaponId?, melee }
	    to the attacker
	  CombatAction { userId, action = "Swing" | "Draw" | "Release" | "Throw", itemId, cancelled?, variant?, lead? }
	    to the other players within ACTION_RANGE studs (variant: a Swing's set, 1-8, when the attacker sent a valid one;
	    lead: seconds from this message to the swing's strike: the windup when sent at the swing's start, 0 when the
	    attacker's client sent no start and the swing is announced at the strike)
	  Sfx: swing, release and impact sounds for the players who can hear them (within the sound's roll-off distance of
	    where they listen from: their character, or the contender they spectate), except the attacker, who plays them
	    locally, instantly

	API
	  CombatService.applyHit(attacker: Player?, humanoid: Humanoid, baseDamage: number, info) -> (damageDealt, killed)
	    info = { cause = "Combat", weaponId = string?, position = Vector3? (where the attack came from),
	             headshot = boolean?, hitPosition = Vector3? }
	    Players: damage * InventoryService.getArmorMultiplier(victim) through PlayerService.damage.
	    Other humanoids (training dummies): Humanoid:TakeDamage. Never yourself, dead players, or outside Active.
	  CombatService.characterFromPart(part) -> (Humanoid?, Model?, BasePart?)   accessories resolve to the body part they're worn on
	  CombatService.getTargets(exclude: Instance?, aliveOnly: boolean?) -> { Model }   every character and training dummy
	    that can be hit; aliveOnly leaves out bodies whose Humanoid is dead (melee: a body that just fell never takes or
	    blocks a swing). Accessory parts are not part of anyone's hit box (CanQuery off, set here as characters load).

	Training dummies: practice rounds only (GameState.Practice), during Active; in Studio, and on live servers while
	Config.Round.SoloPractice is on (PlayabilityPlan QW1).
	Config.Combat.PracticeDummies dummies appear in front of the contender, between the plinths and the Spire, to either
	side of the straight line from the plate to the Spire (that path stays clear), tagged TrainingDummy. They wobble when
	hit, heal after DummyRegenDelay, and respawn DummyRespawnTime after breaking. Their name and health bar keep one size
	on screen (DUMMY_BAR_SIZE) and hide while the contender stands within DUMMY_BAR_HIDE studs, where they would sit on
	the HUD's compass.
	Template: ServerStorage.Dev.TrainingDummy (built by ServerStorage.WorldGen.DummyBuilder).
	Melee reach: honest reach plus half a stud, plus what the target moved on the server in the last quarter second and
	the attacker in the last tenth (meleeFront, recentTravel), never more than range + MeleeLagTolerance + MeleeHitRadius.
	The target's own body (never its held item or anything worn) must lie within that front (bodyDistance), and the
	sweep ball is the client's (2.04) plus 0.15, wider by the target's recent travel up to MeleeHitRadius.
	Weapons v2 (18 Nov): every weapon reads its stats at its stars through Shared.CombatStats (which uses Shared.Stars);
	no single hit over 95 (applyHit); each weapon's one rule (CombatStats.Rules): the knife's unseen hit, the machete's
	second contender in the arc, the spear weak inside 4 studs, the Twin-Bit Axe through half the armour. Bow shots carry
	their on-target range, distance falloff and the 90 head cap to ProjectileService.
	Defeat: a body at zero health stays in one piece (BreakJointsOnDeath off, set here as characters load), topples, fades
	on every client and is removed here DEFEAT_FALL + DEFEAT_FADE seconds after it fell (watchDefeat).
	Melee cooldown: the same rule as the attacker's client (CombatController: nextActionAt = start + total). The next swing
	may START once the cooldown of the weapon that swung last has passed since that swing started, whatever is in hand
	now (trySwing). Refusals are counted by reason in CombatService._refusals (and printed in Studio).

	Combat v3 (19 Nov, docs/design/Combat_v3.md section 1; every number in Shared.Moves). The move set is timed and
	checked here; the client predicts and shows at once.
	  MeleeSwing strike: (look, predictedHit, variant, target, startTime, move, held). move = "L1".."L4" (a light chain
	    step: a step only follows the one before it inside the chain window, else it counts as step 1), "H" (a heavy:
	    needs the "Charge" on record; held is checked against the server's own timing, as bow draws are), "C" (a counter:
	    only inside Counter.Window after this player parried), "K" (a kick: its own cooldown), "HK" / "S1".."S5"
	    (skill strikes, gated by SkillService). No move: step 1, as before. Each move has its own windup and total,
	    which the swing gate (trySwing) uses; the windup never changes with stars. A slash traces three rays across its
	    arc (Moves.traceDirections), a stab one thinner ray; the reach caps, the body check and line of sight are the
	    same for every ray. A hit can't land on a body twice from one swing.
	  MeleeSwing("Start", variant, move): as before, with the move for the others' clients.
	  MeleeSwing("Charge", clientTime | false): the heavy's hold began (the others see the charge) or was let go.
	  MeleeSwing("Guard", on, clientTime): the guard is up from clientTime (believed within CooldownJitter). A melee
	    strike from the guard's front Guard.Arc degrees is blocked (damage x (1 - the weapon's share), stamina drained;
	    at none left the guard breaks: a heavy stagger); inside the guard's first Parry.Window seconds it is parried
	    (no damage, the attacker staggers, the guard's owner may counter). A guard started inside the whiff lock of the
	    last one has no parry window. Arrows and throws are never blocked.
	  MeleeSwing("Dodge", direction, clientTime): melee strikes miss this body from Startup to Startup + Travel after
	    it; Dodge.Cooldown between dodges, Stamina each (twice inside RepeatWindow).
	  Reactions (Combat_v3 1.8): every hit has a tier (Flinch, Stagger, Heavy, Knockdown) from its move. Staggered:
	    no attack and no guard for the tier's time, and a swing being wound up when it began is refused (Interrupted).
	    Poise: after a stagger ends, new hits only flinch for Poise.AfterStagger. The victim's client gets CombatAction
	    { action = "Reaction", tier, impulse (knockback by impulse, capped), hitStop }, the others within ACTION_RANGE
	    { action = "React", userId?, target (the body), tier, from, hitStop, attackerId } and "Block" / "Parry". The
	    attacker's HitConfirm carries tier, hitStop, blocked.
	  Stamina: the server keeps its own combat ledger per player (spends from moves, guards, dodges and skills, the
	    regen of Config.Movement.Stamina): it bounds what a modified client can do; it never knows about sprinting, so
	    it is never stricter than the client's own bar.
	  API for SkillService: CombatService.bodyState(model), spendStamina(player, amount), staminaOf(player),
	    react(attacker, model, tier, opts), resolveHit(attacker, model, move, opts), lineOfSight(from, model, exclude),
	    canAct(player). Test hooks: _npcStrike(attackerModel, victimModel, moveId) (a dummy's strike, for guard and parry
	    tests), _bodyStates.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local CombatStats = require(Shared:WaitForChild("CombatStats"))
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Moves = require(Shared:WaitForChild("Moves"))
local Net = require(Shared:WaitForChild("Net"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local CombatConfig = Config.Combat

local DUMMY_TAG = "TrainingDummy"
local DUMMY_BAR_SIZE = Vector2.new(132, 26) -- pixels: a dummy's name and health bar, the same size at any distance
local DUMMY_BAR_HIDE = 8 -- studs (flat): closer than this the contender doesn't see it (shown again half a stud out):
-- above the head of a dummy that near, it sat in the compass band at the top of the view
local FISTS = ItemDefs.get("fists")
local MELEE_FACING_DOT = -0.2 -- flat swing direction vs. character facing; lenient because the server's view lags
-- Melee reach. The attacker's screen shows a hit when CombatController's sphere (MeleeHitRadius * MELEE_PREDICT_RADIUS)
-- swept `range` studs from the first-person camera (MELEE_CAMERA_BEHIND behind the head) touches someone. The server
-- sweeps from the head and reaches MELEE_REACH_ALLOWANCE studs further (the small difference between the server's head
-- and the client's camera), plus a lag allowance the server measures itself (recentTravel): how far the target moved,
-- on the server, in the last MELEE_LAG_TIME seconds (the attacker's screen showed it where it was up to interpolation
-- plus ping ago), and how far the attacker moved in the last MELEE_OWN_LAG (the server sees the attacker only a moment
-- behind their own screen: their position and their swing travel together). Neither can differ from what the attacker
-- saw by more than the body moved in that time. Two players standing still get no lag allowance at all: honest reach
-- plus MELEE_REACH_ALLOWANCE, whatever the client claims (a sword, range 8: 10.5 studs root to root; 11 is refused).
-- The allowance never passes the old flat one (range + MeleeLagTolerance + MeleeHitRadius), which a target walking
-- away already uses up. (It was flat: any claimed hit on a player was checked out to that front, so a modified client
-- landed a sword from about 15 studs on a player who had not moved. The attacker's part used to be the speed their own
-- client reported.)
-- MELEE_REACH_ALLOWANCE was 1: with it a sword (range 8) standing still was confirmed on a still target 11 studs away,
-- root to root, a full stud past what an honest client's trace can touch (10).
-- The body check (18 Nov, wave 8): whatever the trace touched, the swing lands only when the target's BODY (its own body
-- parts, never a held item or anything worn) has a point within the front of the sweep. Before it, a modified client
-- landed raw sword claims on a player standing still 11 and 12 studs away: the server's ball (2.4) was wider than the
-- client's (2.04) and anything inside the target counted. The ball itself is now the client's radius plus
-- MELEE_BALL_SLACK, widened by what the target moved lately (a strafing target's side, as the server sees it, is up to
-- that far from where the attacker saw it), never past MeleeHitRadius.
-- MELEE_REACH_ALLOWANCE was 0.5 until 18 Nov: with it a modified client still landed a sword on a still player holding
-- a weapon 11 and 11.5 studs away (root to root), whose raised hand an honest client's ball could not touch (Studio run,
-- wave 8). The honest client's own front is range + 2.04 - 0.5 from the head; the server's is now 0.15 past it.
local MELEE_PREDICT_RADIUS = 0.85
local MELEE_CAMERA_BEHIND = 0.5
local MELEE_REACH_ALLOWANCE = 0.15
local MELEE_BALL_SLACK = 0.1
local MELEE_LAG_TIME = 0.25
local MELEE_OWN_LAG = 0.1
local TRAVEL_STEP = 0.05 -- seconds between the position samples recentTravel reads
local RANGED_FACING_DOT = -0.35
local HEAVY_SWING_COOLDOWN = 0.75 -- weapons at least this slow use the heavy swing sound
local BOW_RECOVER = 0.32 -- seconds after a shot before the next draw can begin (CombatController's BOW_RECOVER)
local CHARGE_JITTER = 0.15 -- seconds of draw time forgiven for network jitter (not banked from shot to shot)
local SWING_LATE = 0.35 -- seconds a swing may arrive late and still be timed from when its client says it started
local START_MIN_GAP = 0.3 -- seconds between two swing starts relayed for one attacker
local DEFEAT_FALL = 1.8 -- seconds a defeated body is seen falling before it fades (CharacterVisuals has the same two)
local DEFEAT_FADE = 1.0 -- seconds the fade takes; after it the body is gone
local ACTION_RANGE = 220 -- studs: CombatAction reaches the clients listening this close to the attacker
local SOUND_MARGIN = 30 -- studs past a sound's roll-off distance that still get it (the listener may be moving)

local CombatService = {}

local Services: { [string]: any } = {}
local HitConfirm: RemoteEvent
local CombatAction: RemoteEvent
local SfxRemote: RemoteEvent

type PlayerState = {
	nextSwingStart: number, -- server time (workspace:GetServerTimeNow) from which the next swing may start (trySwing)
	startAt: number?, -- when the last swing start was relayed (MeleeSwing "Start"), and for which weapon
	startItem: string?,
	startGap: number?, -- seconds before another start is relayed if no strike follows that one (onMeleeStart)
	nextThrow: number,
	bowFree: number, -- os.clock() from which the next draw may count (the last shot + BOW_RECOVER)
	drawStart: number?,
	drawItem: string?,
	drawShown: boolean?, -- the players near were told of the draw on record ("Draw" on CombatAction)
	-- Combat v3 (server time, workspace:GetServerTimeNow, unless said)
	chainItem: string?, chainStep: number?, chainEndsAt: number?, -- the light chain: the last step and when it ended
	heavyStart: number?, heavyItem: string?, -- the heavy's hold on record ("Charge")
	counterUntil: number?, kickReady: number?,
	dodgeReady: number?, dodgeFrom: number?, dodgeUntil: number?, dodgeTimes: { number }?,
	stamina: number?, staminaAt: number?, staminaClock: number?, -- the combat ledger
	[string]: any, -- the body state (guard, stagger, poise, buffs): bodyState
}
local playerState: { [Player]: PlayerState } = {}
-- Training dummies and other non-player bodies keep the same body fields (bodyState).
local npcState: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

type Context = { character: Model, humanoid: Humanoid, head: BasePart, root: BasePart }

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function phaseActive(): boolean
	local round = Services.RoundService
	if round and type(round.getPhase) == "function" then
		return round.getPhase() == "Active"
	end
	return GameState:GetAttribute("Phase") == "Active"
end

local function isAliveContender(player: Player): boolean
	local playerService = Services.PlayerService
	if playerService and type(playerService.isAlive) == "function" then
		return playerService.isAlive(player) == true
	end
	return player:GetAttribute("Alive") == true
end

local function stateFor(player: Player): PlayerState
	local st = playerState[player]
	if not st then
		st = { nextSwingStart = -math.huge, startAt = nil, startItem = nil, nextThrow = 0, bowFree = 0, drawStart = nil,
			drawItem = nil }
		playerState[player] = st
	end
	return st
end

-- Cooldown that forgives network jitter without being exploitable: an early action doesn't pull the next window
-- earlier, so spamming at (cooldown - jitter) gains nothing on average.
local function tryCooldown(st: any, key: string, cooldown: number, now: number): boolean
	local ready = st[key] or 0
	if now < ready - (CombatConfig.CooldownJitter or 0.12) then
		return false
	end
	st[key] = math.max(now, ready) + cooldown
	return true
end

-- Melee, the same rule as the attacker's client (CombatController.startMelee: nextActionAt = start + total): the next
-- swing may START once the cooldown of the weapon that swung last has passed since that swing started, whatever is in
-- hand now. (Gating strike to strike by the weapon now in hand refused the first swing after a switch from a quick weapon
-- to a slower one, which the client allows: the attacker saw and heard a hit that never landed, the "ghost swing".)
-- `now` is workspace:GetServerTimeNow() when the strike arrived. The swing started at most `windup` before that; the
-- client's own start time (claimedStart, on the same clock) is believed when it is up to SWING_LATE earlier still, so a
-- strike held up on the way doesn't push the next swing's window back and get that one refused. Nothing is banked: a
-- client that always claims the earliest start gains SWING_LATE once, and its rate stays one swing per cooldown, because
-- an early swing never pulls the next window earlier.
local function trySwing(st: PlayerState, def: any, now: number, claimedStart: any): boolean
	local latest = now - (def.windup or 0.1)
	local start = latest
	-- (not Util.isFiniteNumber: server time is Unix time, about 1.8e9, past that check's 1e9 limit, so every claim was
	-- thrown away; the clamp bounds whatever is sent, infinity included, and NaN is kept out here)
	if type(claimedStart) == "number" and claimedStart == claimedStart then
		start = math.clamp(claimedStart, latest - SWING_LATE, latest)
	end
	if start < st.nextSwingStart - (CombatConfig.CooldownJitter or 0.12) then
		return false
	end
	st.nextSwingStart = math.max(start, st.nextSwingStart) + (def.cooldown or 0.5)
	return true
end

-- Refusals by reason (a swing or shot the server dropped): read CombatService._refusals; printed in Studio.
local refusals: { [string]: number } = {}
local function refuse(player: Player, reason: string)
	refusals[reason] = (refusals[reason] or 0) + 1
	if Config.IsStudio then
		print(string.format("[CombatService] refused %s from %s (%d so far)", reason, player.Name, refusals[reason]))
	end
end

local function getContext(player: Player): Context?
	if not phaseActive() or player:GetAttribute("Frozen") == true or not isAliveContender(player) then
		return nil
	end
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	if not (head and head:IsA("BasePart")) or not (root and root:IsA("BasePart")) then
		return nil
	end
	return { character = character, humanoid = humanoid, head = head, root = root }
end

local function equippedItemId(player: Player): string?
	local inventory = Services.InventoryService
	if inventory and type(inventory.getEquipped) == "function" then
		local itemId = inventory.getEquipped(player)
		if type(itemId) == "string" then
			return itemId
		end
	end
	return nil
end

-- The melee stats used for the equipped item: fists for nothing, ammo or utility items; nil for items that never swing.
local function meleeDefFor(itemId: string?)
	local def = ItemDefs.get(itemId)
	if def == nil or def.kind == "Ammo" or def.kind == "Utility" then
		return FISTS
	end
	if def.kind == "Melee" then
		return def
	end
	return nil
end

-- The star count (1..5) of the item in hand: InventoryService.getEquippedStars when it has one, else the `stars` field
-- of the equipped slot (slots { id, count, stars? }, Weapons_v2 9.2), else 1.
local function equippedStars(player: Player): number
	local inventory = Services.InventoryService
	if not inventory then
		return 1
	end
	if type(inventory.getEquippedStars) == "function" then
		local ok, value = pcall(inventory.getEquippedStars, player)
		if ok and type(value) == "number" then
			return CombatStats.clampStars(value)
		end
	end
	if type(inventory.getEquipped) == "function" and type(inventory.getSnapshot) == "function" then
		local ok, _, slot = pcall(inventory.getEquipped, player)
		local okSnap, snap = pcall(inventory.getSnapshot, player)
		local slots = okSnap and type(snap) == "table" and snap.slots
		local entry = ok and type(slot) == "number" and type(slots) == "table" and slots[slot]
		if type(entry) == "table" then
			return CombatStats.clampStars(entry.stars)
		end
	end
	return 1
end

-- The swing's stats at the star count of the weapon in hand (CombatStats.melee), or nil for items that never swing.
local function meleeStatsFor(player: Player, itemId: string?)
	local def = meleeDefFor(itemId)
	if not def then
		return nil
	end
	return CombatStats.melee(def, if def == FISTS then 1 else equippedStars(player))
end

local function hasItem(player: Player, itemId: string, count: number): boolean
	local inventory = Services.InventoryService
	return inventory ~= nil and type(inventory.has) == "function" and inventory.has(player, itemId, count) == true
end

local function consumeItem(player: Player, itemId: string, count: number): boolean
	local inventory = Services.InventoryService
	if not inventory then
		return false
	end
	local consume = inventory.consume or inventory.take
	return type(consume) == "function" and consume(player, itemId, count) == true
end

-- A shot the projectile caps refused gives its item back: nothing thrown or shot is ever lost.
local function refund(player: Player, itemId: string)
	local inventory = Services.InventoryService
	if inventory and type(inventory.give) == "function" then
		pcall(inventory.give, player, itemId, 1)
	end
end

local function facingOk(root: BasePart, direction: Vector3, minDot: number): boolean
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.3 then
		return true -- looking almost straight up or down
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.1 then
		return true
	end
	return flat.Unit:Dot(flatLook.Unit) >= minDot
end

-- Where a player listens and watches from: the contender they spectate (PlayerService points their ReplicationFocus
-- there), else their own character. nil while they have neither (still loading).
local function listenerPosition(other: Player): Vector3?
	local focus = other.ReplicationFocus
	if focus and focus:IsA("PVInstance") and focus:IsDescendantOf(workspace) then
		return focus:GetPivot().Position
	end
	local character = other.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- A positional sound, sent only to the players who can hear it: within its roll-off distance (Sounds: rollMax) plus
-- SOUND_MARGIN of where they listen from. (Sfx.play sends to every client, the lobby 8,800 studs away included.)
local function playSound(key: string, position: Vector3, exclude: Player?, volume: number?, pitch: number?, maxRange: number?)
	local entry = (Sounds :: any)[key]
	local range = ((if type(entry) == "table" then tonumber(entry.rollMax) else nil) or 160) + SOUND_MARGIN
	if type(maxRange) == "number" and maxRange > 0 then
		range = math.min(range, maxRange) -- (a quiet sound: the Leaf Dagger's throw, heard within 10 studs)
	end
	local data = { position = position, volume = volume, pitch = pitch }
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= exclude then
			local at = listenerPosition(other)
			if at and (at - position).Magnitude <= range then
				SfxRemote:FireClient(other, key, data)
			end
		end
	end
end

-- To the other players within ACTION_RANGE of the attacker (everyone else, if the attacker has no body to measure from).
local function broadcastAction(player: Player, action: string, itemId: string?, cancelled: boolean?, variant: number?, lead: number?, extra: { [string]: any }?)
	local payload: { [string]: any } = { userId = player.UserId, action = action, itemId = itemId or "fists", cancelled = cancelled == true }
	payload.variant = variant -- (a Swing's set, when the attacker sent a valid one)
	payload.lead = lead -- (a Swing: seconds until its strike)
	if extra then
		for key, value in pairs(extra) do
			payload[key] = value -- (Combat v3: the move, a guard's state, a dodge's direction)
		end
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local from = if root and root:IsA("BasePart") then root.Position else nil
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local at = if from then listenerPosition(other) else nil
			if from == nil or (at ~= nil and (at - from).Magnitude <= ACTION_RANGE) then
				CombatAction:FireClient(other, payload)
			end
		end
	end
end

-- A swing's set from MeleeSwing: an integer 1-8, else nil (ignored; the swing itself goes ahead).
local function swingVariant(value: any): number?
	if type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= 8 then
		return value
	end
	return nil
end

local SOUND_BY_MATERIAL: { [string]: string } = {
	Metal = "Hit_Metal", CorrodedMetal = "Hit_Metal", DiamondPlate = "Hit_Metal", Foil = "Hit_Metal",
	Wood = "Hit_Wood", WoodPlanks = "Hit_Wood", Fabric = "Hit_Wood", Grass = "Hit_Wood", LeafyGrass = "Hit_Wood",
	Ground = "Hit_Wood", Mud = "Hit_Wood", Sand = "Hit_Wood", Snow = "Hit_Wood", Cardboard = "Hit_Wood",
	Carpet = "Hit_Wood", Leather = "Hit_Wood", Rubber = "Hit_Wood", Plastic = "Hit_Wood", SmoothPlastic = "Hit_Wood",
}

local function worldHitSound(material: Enum.Material?): string
	return (material and SOUND_BY_MATERIAL[material.Name]) or "Hit_Stone"
end

-- Ground items (crates are solid and stay hittable).
local function lootFolder(): Instance?
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	return loot and loot:FindFirstChild("Items")
end

-- World geometry only: characters and dummies are excluded (they get their own precise pass) and non-collidable
-- foliage is ignored, so bushes and leaves don't stop a blade.
local function worldParams(targets: { Instance }, extra: Instance?): RaycastParams
	local list = table.clone(targets)
	if extra then
		table.insert(list, extra)
	end
	local loot = lootFolder()
	if loot then
		table.insert(list, loot)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

--------------------------------------------------------------------------------------------------------------------
-- Public helpers
--------------------------------------------------------------------------------------------------------------------

local HEAD_ATTACHMENTS = { HatAttachment = true, HairAttachment = true, FaceFrontAttachment = true, FaceCenterAttachment = true }

local function wornOn(handle: BasePart, accessory: Instance): BasePart?
	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
			local a = (child :: any).Part0
			local b = (child :: any).Part1
			local other = if a == handle then b else a
			if other and other ~= handle and other:IsA("BasePart") then
				return other
			end
		elseif child:IsA("RigidConstraint") then
			-- current avatars (layered clothing, most accessories) hang on a RigidConstraint between two attachments
			local a = child.Attachment0
			local b = child.Attachment1
			local other = if a and a.Parent == handle then b else a
			local part = other and other.Parent
			if part and part ~= handle and part:IsA("BasePart") then
				return part
			end
		end
	end
	local character = accessory.Parent
	if character then
		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("Attachment") and HEAD_ATTACHMENTS[child.Name] then
				local head = character:FindFirstChild("Head")
				if head and head:IsA("BasePart") then
					return head
				end
			end
		end
	end
	return nil
end

function CombatService.characterFromPart(part: Instance?): (Humanoid?, Model?, BasePart?)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil, nil, nil
	end
	local bodyPart: BasePart = part
	local parent = part.Parent
	if parent and parent:IsA("Accessory") then
		bodyPart = wornOn(part, parent) or part
		parent = parent.Parent
	end
	if parent and parent:IsA("Model") then
		local humanoid = parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, parent, bodyPart
		end
	end
	return nil, nil, nil
end

local function isLive(model: Instance): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function CombatService.getTargets(exclude: Instance?, aliveOnly: boolean?): { Instance }
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		if character and character ~= exclude and character.Parent and (not aliveOnly or isLive(character)) then
			table.insert(list, character)
		end
	end
	for _, dummy in ipairs(CollectionService:GetTagged(DUMMY_TAG)) do
		if dummy ~= exclude and dummy:IsA("Model") and dummy:IsDescendantOf(workspace) and (not aliveOnly or isLive(dummy)) then
			table.insert(list, dummy)
		end
	end
	return list
end

-- The hit box is the body. Hats, hair, wings, auras and layered clothing took swings and arrows that missed the body (and
-- anything worn on the head counted as a headshot), so accessory parts are left out of every ray and sweep, on the
-- server and (the property replicates) in each client's own trace. Accessory parts never collide, so nothing else changes.
local function bodyOnlyPart(inst: Instance)
	if inst:IsA("BasePart") and inst.CanQuery and inst:FindFirstAncestorWhichIsA("Accessory") then
		inst.CanQuery = false
	end
end

-- Defeat, kept clearly unrealistic (the game's age rating): the body stays in one piece (no limbs coming off), topples
-- over, fades out on every client (CharacterVisuals: DEFEAT_FALL seconds after it fell, over DEFEAT_FADE) and is then
-- gone for good here too: invisible, held still, and out of every ray, sweep and touch, so nothing sticks in or bumps
-- into a body nobody can see. Nothing is left lying. The Roll Call's figure is a copy taken the moment they fell
-- (ArenaService.FallenSnapshots), not this body. PlayerService loads the next character RespawnDelay after the fall.
local function removeFallenBody(character: Model)
	if not character.Parent then
		return
	end
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Transparency = 1
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			inst.Transparency = 1
		end
	end
end

local function watchDefeat(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Once(function()
		task.delay(DEFEAT_FALL + DEFEAT_FADE, removeFallenBody, character)
	end)
end

local function watchHitBox(character: Model)
	for _, inst in ipairs(character:GetDescendants()) do
		bodyOnlyPart(inst)
	end
	character.DescendantAdded:Connect(bodyOnlyPart) -- (accessories arrive after the body; gone with the character)
	task.spawn(watchDefeat, character)
end

local function watchPlayerHitBox(player: Player)
	player.CharacterAdded:Connect(watchHitBox)
	if player.Character then
		watchHitBox(player.Character)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Training dummies
--------------------------------------------------------------------------------------------------------------------

type DummySlot = { cframe: CFrame, model: Model?, stand: Instance? }
type DummyData = {
	lastHit: number,
	wobble: number,
	wobbleTime: number,
	axis: Vector3,
	push: Vector3,
	motor: Motor6D?,
	baseC0: CFrame?,
	bar: BillboardGui?,
}

local dummyFolder: Folder? = nil
local dummySlots: { DummySlot } = {}
local dummyData: { [Model]: DummyData } = {}
local dummiesWanted = false
local warnedTemplate = false

local function getDummyFolder(): Folder
	if dummyFolder and dummyFolder.Parent then
		return dummyFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "TrainingDummies"
	folder.Parent = workspace
	dummyFolder = folder
	return folder
end

local function dummyTemplate(): Model?
	local dev = ServerStorage:FindFirstChild("Dev")
	local template = dev and dev:FindFirstChild("TrainingDummy")
	if template and template:IsA("Model") then
		return template
	end
	-- Fall back to building one (the builder works at runtime too) and keep it as the template.
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	local builder = worldGen and worldGen:FindFirstChild("DummyBuilder")
	if builder and builder:IsA("ModuleScript") then
		local ok, result = pcall(function()
			return require(builder :: ModuleScript).create()
		end)
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			result.Name = "TrainingDummy"
			result.Parent = dev or ServerStorage
			return result
		end
	end
	if not warnedTemplate then
		warnedTemplate = true
		warn("[CombatService] No ServerStorage.Dev.TrainingDummy template; run ServerStorage.WorldGen.DummyBuilder.build()")
	end
	return nil
end

local function practiceContenderRoot(): BasePart?
	for _, other in ipairs(Players:GetPlayers()) do
		if other:GetAttribute("Alive") == true and other.Character then
			local root = other.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root
			end
		end
	end
	return nil
end

-- Dummies stand in a shallow arc a dozen studs in front of the practice contender, toward the Spire, to either side of
-- the straight line from the plate to the Spire (the middle one used to stand on it, in the way of the first sprint).
local function dummyLayout(): { CFrame }
	local center = Vector3.new(ArenaLayout.Center.X, ArenaLayout.BaseHeight, ArenaLayout.Center.Z)
	local root = practiceContenderRoot()
	local anchor = if root then root.Position else ArenaLayout.polar(0, ArenaLayout.PlinthRingRadius, ArenaLayout.BaseHeight + 3)
	local toCenter = Util.flat(center - anchor)
	toCenter = if toCenter.Magnitude > 1 then toCenter.Unit else Vector3.new(0, 0, 1)
	local right = toCenter:Cross(Vector3.yAxis)

	local ignore = CombatService.getTargets(nil)
	local loot = lootFolder()
	if loot then
		table.insert(ignore, loot)
	end
	if dummyFolder then
		table.insert(ignore, dummyFolder)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = false -- stand on what you can see (path overlays are non-collidable)
	params.IgnoreWater = false

	local spots = {}
	local count = math.max(0, math.floor(CombatConfig.PracticeDummies or 3))
	for i = 1, count do
		-- alternate sides: the first pair 6 studs either side of the line (a clear lane about 7 studs wide between their
		-- stands), then 12 studs further out each. (At 7 a dummy's outstretched hand was about a stud off the line from
		-- the plate to the next dummy's chest, and took the swings aimed at that one.)
		local side = if i % 2 == 1 then 1 else -1
		local lateral = side * (6 + 12 * math.floor((i - 1) / 2))
		local ahead = 13 + math.abs(lateral) * 0.3
		local spot = anchor + toCenter * ahead + right * lateral
		local ground = workspace:Raycast(Vector3.new(spot.X, anchor.Y + 40, spot.Z), Vector3.new(0, -120, 0), params)
		local position = if ground then ground.Position else Vector3.new(spot.X, ArenaLayout.BaseHeight, spot.Z)
		local face = Vector3.new(anchor.X, position.Y, anchor.Z)
		if (face - position).Magnitude < 0.5 then
			face = position - toCenter
		end
		table.insert(spots, CFrame.lookAt(position, face))
	end
	return spots
end

local spawnDummy: (slot: DummySlot) -> ()

local function breakDummy(model: Model, slot: DummySlot)
	local data = dummyData[model]
	if not data then
		return -- already broken (Died and HealthChanged can both report it)
	end
	dummyData[model] = nil
	-- arrows and blades in it come out now, where they are, and drop to the ground before its parts tumble away
	local projectiles = Services.ProjectileService
	local world = projectiles and projectiles.world
	if world and type(world.releaseFrom) == "function" then
		local ok, err = pcall(world.releaseFrom, model)
		if not ok then
			warn("[CombatService] couldn't free the items stuck in a training dummy: " .. tostring(err))
		end
	end
	CollectionService:RemoveTag(model, DUMMY_TAG)
	local push = if data then data.push else Vector3.zero
	local head = model:FindFirstChild("Head")
	local bar = head and head:FindFirstChild("HealthBar")
	if bar and bar:IsA("BillboardGui") then
		bar.Enabled = false
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		root:Destroy()
	end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("Motor6D") then
			inst:Destroy()
		end
	end
	local soundAt: Vector3? = nil
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = true
			inst.CanQuery = false
			inst.CanTouch = false
			soundAt = soundAt or inst.Position
		end
	end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			pcall(function()
				inst:SetNetworkOwner(nil)
			end)
			local scatter = Vector3.new(math.random() - 0.5, 0.6 + math.random() * 0.5, math.random() - 0.5)
			inst:ApplyImpulse((push * 16 + scatter * 14) * inst.AssemblyMass)
			inst:ApplyAngularImpulse(Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 6 * inst.AssemblyMass)
		end
	end
	if soundAt then
		playSound("Hit_Wood", soundAt, nil, 1.3, 0.75)
	end
	task.delay(CombatConfig.DummyRespawnTime or 3, function()
		if model.Parent then
			model:Destroy()
		end
		if slot.model == model then
			slot.model = nil
			if dummiesWanted and table.find(dummySlots, slot) then
				spawnDummy(slot)
			end
		end
	end)
end

spawnDummy = function(slot: DummySlot)
	if not dummiesWanted then
		return
	end
	local template = dummyTemplate()
	if not template then
		return
	end
	local model = template:Clone()
	model:PivotTo(slot.cframe)
	local stand = model:FindFirstChild("Stand")
	if stand then
		if slot.stand and slot.stand.Parent then
			stand:Destroy()
		else
			stand.Parent = getDummyFolder()
			slot.stand = stand
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		model:Destroy()
		return
	end
	local maxHealth = CombatConfig.DummyHealth or 200
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	local upperTorso = model:FindFirstChild("UpperTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist")
	local motor = if waist and waist:IsA("Motor6D") then waist else nil
	dummyData[model] = {
		lastHit = 0,
		wobble = 0,
		wobbleTime = 0,
		axis = Vector3.xAxis,
		push = Vector3.zero,
		motor = motor,
		baseC0 = if motor then motor.C0 else nil,
	}
	CollectionService:AddTag(model, DUMMY_TAG)
	model.Parent = getDummyFolder()
	slot.model = model

	local head = model:FindFirstChild("Head")
	local bar = head and head:FindFirstChild("HealthBar")
	local track = bar and bar:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Fill")
	-- one size on screen at any distance (sized in studs, it filled the top of the view up close, over the compass);
	-- updateDummies hides it while the contender is right in front of the dummy
	if bar and bar:IsA("BillboardGui") then
		bar.Size = UDim2.fromOffset(DUMMY_BAR_SIZE.X, DUMMY_BAR_SIZE.Y)
		local data = dummyData[model]
		if data then
			data.bar = bar
		end
	end
	humanoid.HealthChanged:Connect(function(health: number)
		if fill and fill:IsA("GuiObject") then
			local alpha = math.clamp(health / math.max(humanoid.MaxHealth, 1), 0, 1)
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			fill.BackgroundColor3 = Theme.Colors.HealthLow:Lerp(Theme.Colors.Health, math.clamp(alpha * 1.6, 0, 1))
		end
		if health <= 0 then
			breakDummy(model, slot)
		end
	end)
	humanoid.Died:Once(function()
		breakDummy(model, slot)
	end)
end

local function onDummyHit(model: Model, info: { [string]: any })
	local data = dummyData[model]
	if not data then
		return
	end
	data.lastHit = os.clock()
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local from = info.position
	if root and root:IsA("BasePart") and typeof(from) == "Vector3" then
		local away = Util.flat(root.Position - from)
		if away.Magnitude > 0.01 then
			data.push = away.Unit
			local localAway = root.CFrame:VectorToObjectSpace(away.Unit)
			local axis = Vector3.yAxis:Cross(localAway)
			if axis.Magnitude > 0.01 then
				data.axis = axis.Unit
			end
		end
	end
	-- (Combat v3: the wobble shows the hit's weight: a flinch rocks it a little, a heavy stagger a lot)
	local weight = ({ Flinch = 0.55, Stagger = 0.85, Heavy = 1.15, Knockdown = 1.3 })[info.tier or ""] or 0.75
	if info.blocked then
		weight = 0.3
	end
	data.wobble = math.min(1.35, data.wobble * 0.5 + 0.55 * weight)
	data.wobbleTime = 0
end

local function updateDummies(dt: number)
	if next(dummyData) == nil then
		return
	end
	local now = os.clock()
	local viewer = practiceContenderRoot()
	for model, data in pairs(dummyData) do
		local bar = data.bar
		local body = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if bar and body and body:IsA("BasePart") then
			local d = if viewer then Util.flat(body.Position - viewer.Position).Magnitude else math.huge
			local hide = d < (if bar.Enabled then DUMMY_BAR_HIDE else DUMMY_BAR_HIDE + 0.5)
			if bar.Enabled == hide then
				bar.Enabled = not hide
			end
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			if now - data.lastHit > (CombatConfig.DummyRegenDelay or 4) and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 1.5 * dt)
			end
			local motor = data.motor
			if motor and data.baseC0 then
				if data.wobble > 0.002 then
					data.wobbleTime += dt
					data.wobble *= math.exp(-3.2 * dt)
					local angle = data.wobble * math.rad(13) * math.sin(data.wobbleTime * 16)
					motor.C0 = data.baseC0 * CFrame.fromAxisAngle(data.axis, angle)
				elseif data.wobble ~= 0 then
					data.wobble = 0
					motor.C0 = data.baseC0
				end
			end
		end
	end
end

local function clearDummies()
	dummiesWanted = false
	for _, slot in ipairs(dummySlots) do
		if slot.model then
			slot.model:Destroy()
		end
		if slot.stand then
			slot.stand:Destroy()
		end
	end
	table.clear(dummySlots)
	table.clear(dummyData)
	if dummyFolder then
		dummyFolder:Destroy()
		dummyFolder = nil
	end
end

local function wantDummies(): boolean
	if not phaseActive() or (not Config.IsStudio and Config.Round.SoloPractice == false) then
		return false
	end
	local practice = GameState:GetAttribute("Practice") == true
	local round = Services.RoundService
	if not practice and round and type(round.isPractice) == "function" then
		practice = round.isPractice() == true
	end
	return practice
end

local function refreshDummies()
	if wantDummies() then
		if not dummiesWanted then
			dummiesWanted = true
			for _, cframe in ipairs(dummyLayout()) do
				local slot: DummySlot = { cframe = cframe, model = nil, stand = nil }
				table.insert(dummySlots, slot)
				spawnDummy(slot)
			end
		end
	elseif dummiesWanted or #dummySlots > 0 then
		clearDummies()
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Hits
--------------------------------------------------------------------------------------------------------------------

-- When each body last took damage from anything here (weak keys: gone with the body).
local lastHurtAt: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any

function CombatService.applyHit(attacker: Player?, humanoid: Humanoid, baseDamage: number, info: { [string]: any }?): (number, boolean)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then
		return 0, false
	end
	if not Util.isFiniteNumber(baseDamage) or baseDamage <= 0 or not phaseActive() then
		return 0, false
	end
	local model = humanoid.Parent
	if not model or humanoid.Health <= 0 then
		return 0, false
	end
	if attacker ~= nil and (typeof(attacker) ~= "Instance" or not attacker:IsA("Player") or attacker.Parent == nil) then
		attacker = nil -- left the game: no credit, no confirm
	end

	local hit = if type(info) == "table" then table.clone(info) else {}
	hit.attacker = attacker
	hit.cause = hit.cause or "Combat"
	-- the Leaf Dagger's unseen throw (ItemDefs throwUnseenDamage): a thrown hit on a body facing away from where the
	-- throw left, unhurt for CombatStats.UnseenWindow seconds, lands at throwUnseenDamage / throwDamage of its damage
	-- (40 -> 50 at 1 star; the stars, falloff and headshot carry over). Not on a guard: blocked throws never get here.
	if hit.cause == "Combat" and hit.melee ~= true and typeof(hit.position) == "Vector3" then
		local tdef = ItemDefs.get(hit.weaponId)
		local root = model:FindFirstChild("HumanoidRootPart")
		if tdef and tdef.throwUnseenDamage and tdef.throwDamage and tdef.throwDamage > 0 and root and root:IsA("BasePart") then
			local toThrower = Util.flat(hit.position - root.Position)
			local look = Util.flat(root.CFrame.LookVector)
			local unhurt = os.clock() - (lastHurtAt[humanoid] or -math.huge) >= CombatStats.UnseenWindow
			if unhurt and toThrower.Magnitude > 0.01 and look.Magnitude > 0.01 and look.Unit:Dot(toThrower.Unit) < 0 then
				baseDamage *= tdef.throwUnseenDamage / tdef.throwDamage
				hit.unseen = true
			end
		end
	end
	if hit.cause == "Combat" then
		baseDamage = math.min(baseDamage, CombatStats.hitCap()) -- no single weapon hit over 95, whatever the stars
	end

	local victim = Players:GetPlayerFromCharacter(model)
	local dealt, killed = 0, false
	if victim then
		if victim == attacker or not isAliveContender(victim) then
			return 0, false
		end
		local multiplier = 1
		local inventory = Services.InventoryService
		if inventory and type(inventory.getArmorMultiplier) == "function" then
			local ok, value = pcall(inventory.getArmorMultiplier, victim)
			if ok and Util.isFiniteNumber(value) then
				multiplier = math.clamp(value, 0, 1)
			end
		end
		local pierce = hit.armourPierce
		if type(pierce) == "number" and pierce == pierce then
			multiplier = 1 - (1 - multiplier) * (1 - math.clamp(pierce, 0, 1)) -- Twin-Bit Axe: armour stops half as much
		end
		local playerService = Services.PlayerService
		if not playerService or type(playerService.damage) ~= "function" then
			return 0, false
		end
		dealt = baseDamage * multiplier
		local ok, result = pcall(playerService.damage, victim, dealt, hit)
		if not ok then
			warn("[CombatService] PlayerService.damage failed: " .. tostring(result))
			return 0, false
		end
		killed = result == true
	else
		local before = humanoid.Health
		humanoid:TakeDamage(baseDamage)
		dealt = math.max(0, before - humanoid.Health)
		killed = humanoid.Health <= 0
		if model:IsA("Model") then
			onDummyHit(model, hit)
		end
	end

	if dealt > 0 then
		lastHurtAt[humanoid] = os.clock() -- (the knife's unseen hit needs 5 s unhurt)
	end
	-- Combat v3: the hit's weight. Melee passes its own tier (resolveHit); a shot or a throw gets one here: arrows and
	-- thrown weapons of 38 or more stagger, lighter throws flinch (Combat_v3 1.8).
	local tierName: string? = if type(hit.tier) == "string" then hit.tier else nil
	if dealt > 0 and not killed and hit.cause == "Combat" and hit.react ~= false and model:IsA("Model") then
		if not tierName and hit.melee ~= true then
			local def = ItemDefs.get(hit.weaponId)
			local shot = def ~= nil and def.kind == "Bow"
			tierName = if shot or baseDamage >= 38 then "Stagger" else "Flinch"
			hit.knock = hit.knock or Moves.knockSpeed(if shot then "arrow" else "thrown")
		end
		if tierName then
			local reaction = CombatService.react(attacker, model, tierName, hit)
			tierName = reaction and reaction.tier or tierName
			hit.hitStop = reaction and reaction.hitStop or hit.hitStop
		end
	end
	if attacker and dealt > 0 then
		HitConfirm:FireClient(attacker, {
			damage = math.floor(dealt + 0.5),
			headshot = hit.headshot == true,
			killed = killed,
			position = if typeof(hit.hitPosition) == "Vector3" then hit.hitPosition else nil,
			target = if victim then "Player" else "Dummy",
			weaponId = if type(hit.weaponId) == "string" then hit.weaponId else nil,
			melee = hit.melee == true,
			tier = tierName,
			hitStop = if type(hit.hitStop) == "number" then hit.hitStop else nil,
			blocked = hit.blocked == true,
			move = if type(hit.move) == "string" then hit.move else nil,
		})
	end
	return dealt, killed
end

type MeleeHit = {
	humanoid: Humanoid?,
	model: Model?,
	part: BasePart?,
	position: Vector3,
	normal: Vector3?,
	material: Enum.Material?,
}

-- The body a touched part belongs to: a body part or something worn (characterFromPart), or anything else inside one of
-- `targets` (the weapon it holds): a swing that meets the target's sword first still lands on the target.
local function bodyFromPart(part: Instance, targets: { Instance }): (Humanoid?, Model?, BasePart?)
	local humanoid, model, bodyPart = CombatService.characterFromPart(part)
	if humanoid then
		return humanoid, model, bodyPart
	end
	for _, target in ipairs(targets) do
		if part:IsDescendantOf(target) and target:IsA("Model") then
			return target:FindFirstChildOfClass("Humanoid"), target, nil
		end
	end
	return nil, nil, nil
end

-- What the swing lands on. First a thin ray along the look: whoever is under the crosshair, out to the sweep's front.
-- Only when that touches nobody it can see, the forgiving sphere sweep (first body touched), then a point-blank overlap
-- check (Spherecast skips parts that already overlap its start). A line-of-sight check on each so nobody is hit through
-- a wall, then a thin ray for the world sound. `reach` is the sweep's length: its front is reach + radius from the origin.
-- Only living bodies count (one that just fell neither takes the swing nor blocks it). `only` (the body the attacker's
-- own trace touched): that body is checked and no other, so a bystander in the path never takes the hit.
-- worldOnly skips the characters (the attacker's own trace missed them) and keeps the world sound.
-- The shortest distance (studs) from `point` to the body of `model`: its own body parts (direct BasePart children that
-- can be queried), never a held item, a tool or anything worn. math.huge when it has none.
local function bodyDistance(model: Instance?, point: Vector3): number
	if not model then
		return math.huge
	end
	local best = math.huge
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.CanQuery then
			local half = part.Size * 0.5
			local rel = part.CFrame:PointToObjectSpace(point)
			local closest = Vector3.new(math.clamp(rel.X, -half.X, half.X), math.clamp(rel.Y, -half.Y, half.Y), math.clamp(rel.Z, -half.Z, half.Z))
			local d = (rel - closest).Magnitude
			if d < best then
				best = d
			end
		end
	end
	return best
end

-- bodyLimit (optional): a body is only taken when bodyDistance from the origin is within it (see MELEE_BALL_SLACK).
local function meleeTrace(character: Model, origin: Vector3, direction: Vector3, reach: number, radius: number, worldOnly: boolean?, only: Instance?, bodyLimit: number?): MeleeHit?
	local world = worldParams(CombatService.getTargets(character), character) -- (no body, living or not, is world)
	local targets = if worldOnly then {} else CombatService.getTargets(character, true)
	if only ~= nil then
		targets = if table.find(targets, only) then { only } else {} -- (it just fell, or was never a target: nobody)
	end
	local function inReach(model: Instance?): boolean
		return bodyLimit == nil or bodyDistance(model, origin) <= bodyLimit
	end
	if #targets > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = targets
		local candidate: MeleeHit? = nil
		local aimed = workspace:Raycast(origin, direction * (reach + radius), params)
		if aimed then
			local humanoid, model, bodyPart = bodyFromPart(aimed.Instance, targets)
			if humanoid and humanoid.Health > 0 and inReach(model) then
				candidate = { humanoid = humanoid, model = model, part = bodyPart, position = aimed.Position }
			end
		end
		if candidate then
			-- the body under the crosshair, if the way to that point is clear. If it is not (the ray above passes
			-- through cover and found a hidden part of them), the ball below still gets its turn: it may touch an arm
			-- that is in the open, or somebody else. (Going straight to the world ray made such a swing hit the tree.)
			local offset = candidate.position - origin
			local distance = offset.Magnitude
			local blocked = if distance > 0.5 then workspace:Raycast(origin, offset, world) else nil
			if blocked == nil or blocked.Distance >= distance - 0.75 then
				return candidate
			end
			candidate = nil
		end
		local swept = workspace:Spherecast(origin, radius, direction * reach, params)
		if swept then
			local humanoid, model, bodyPart = bodyFromPart(swept.Instance, targets)
			if humanoid and humanoid.Health > 0 and inReach(model) then
				candidate = { humanoid = humanoid, model = model, part = bodyPart, position = swept.Position }
			end
		end
		if not candidate then
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Include
			overlap.FilterDescendantsInstances = targets
			local bestDistance = math.huge
			for _, part in ipairs(workspace:GetPartBoundsInRadius(origin + direction * radius, radius, overlap)) do
				local humanoid, model, bodyPart = bodyFromPart(part, targets)
				if humanoid and humanoid.Health > 0 and inReach(model) then
					local offset = part.Position - origin
					local distance = offset.Magnitude
					if offset:Dot(direction) > -0.5 and distance < bestDistance then
						bestDistance = distance
						candidate = { humanoid = humanoid, model = model, part = bodyPart, position = part.Position }
					end
				end
			end
		end
		if candidate then
			local offset = candidate.position - origin
			local distance = offset.Magnitude
			local clear = true
			if distance > 0.5 then
				local blocked = workspace:Raycast(origin, offset, world)
				clear = blocked == nil or blocked.Distance >= distance - 0.75
			end
			if clear then
				return candidate
			end
		end
	end
	local result = workspace:Raycast(origin, direction * reach, world)
	if result then
		return { position = result.Position, normal = result.Normal, material = result.Material }
	end
	return nil
end

-- Where every body that can be hit was over the last MELEE_LAG_TIME seconds, as the server saw it (a sample every
-- TRAVEL_STEP while a round is Active). The lag allowance of a swing is read from this, never from what a client reports.
type Trail = { times: { number }, points: { Vector3 } }
local trails: { [Instance]: Trail } = {}
local trailAt = 0

local function sampleTrails(now: number)
	if now - trailAt < TRAVEL_STEP then
		return
	end
	trailAt = now
	if not phaseActive() then
		if next(trails) ~= nil then
			table.clear(trails)
		end
		return
	end
	local keep: { [Instance]: Trail } = {}
	local oldest = now - MELEE_LAG_TIME - TRAVEL_STEP
	for _, model in ipairs(CombatService.getTargets(nil)) do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local trail = trails[model] or { times = {}, points = {} }
			while #trail.times > 0 and trail.times[1] < oldest do
				table.remove(trail.times, 1)
				table.remove(trail.points, 1)
			end
			table.insert(trail.times, now)
			table.insert(trail.points, root.Position)
			keep[model] = trail
		end
	end
	trails = keep
end

-- How far a body is now from where the server had it at any moment of the last `window` seconds (at most
-- MELEE_LAG_TIME; studs; 0 for one that stood still, or that the server has only just met).
local function recentTravel(model: Instance?, now: number, window: number): number
	local trail = if model then trails[model] else nil
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	if not trail or not (root and root:IsA("BasePart")) then
		return 0
	end
	local at = root.Position
	local oldest = now - window - TRAVEL_STEP
	local far = 0
	for i, t in ipairs(trail.times) do
		if t >= oldest then
			far = math.max(far, (trail.points[i] - at).Magnitude)
		end
	end
	return if Util.isFiniteNumber(far) then far else 0
end

-- The most any body in front of the swing moved lately (for a client that names no target).
local function travelAhead(character: Model, origin: Vector3, direction: Vector3, reach: number, radius: number, now: number): number
	local most = 0
	for _, target in ipairs(CombatService.getTargets(character, true)) do
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local offset = root.Position - origin
			local along = offset:Dot(direction)
			if along > 0 and along < reach + 3 and (offset - direction * along).Magnitude < radius + 3 then
				most = math.max(most, recentTravel(target, now, MELEE_LAG_TIME))
			end
		end
	end
	return most
end

-- The front of the server's sweep for one swing (studs from the attacker's head): honest reach plus
-- MELEE_REACH_ALLOWANCE, plus (only for a swing the attacker's screen showed hitting) what the attacker and the target
-- moved lately, never past the old flat allowance. Returns (front, honest + allowance, the cap, attacker's travel,
-- target's travel).
local function meleeFront(def: any, character: Model, origin: Vector3, direction: Vector3, predicted: boolean, claimed: Instance?): (number, number, number, number, number)
	local range = def.range or 5
	local radius = CombatConfig.MeleeHitRadius
	local cap = range + CombatConfig.MeleeLagTolerance + radius
	local still = math.min(range + radius * MELEE_PREDICT_RADIUS - MELEE_CAMERA_BEHIND + MELEE_REACH_ALLOWANCE, cap)
	if not predicted then
		return still, still, cap, 0, 0
	end
	local now = os.clock()
	local own = recentTravel(character, now, MELEE_OWN_LAG)
	local theirs = if claimed then recentTravel(claimed, now, MELEE_LAG_TIME) else travelAhead(character, origin, direction, cap, radius, now)
	return math.min(still + own + theirs, cap), still, cap, own, theirs
end

-- A swing's damage on the body it landed on, with its weapon's one rule (CombatStats.Rules, Weapons_v2 1.2): the spear
-- is weak inside its shaft (insideRange, flat root to root), the knife's first hit on someone facing away and unhurt for
-- CombatStats.UnseenWindow seconds is its unseen hit.
local function meleeDamage(def: any, ctx: Context, hit: MeleeHit): number
	local damage = def.damage or 0
	local model = hit.model
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return damage
	end
	local toAttacker = Util.flat(ctx.root.Position - root.Position)
	if def.insideRange and def.insideShare and toAttacker.Magnitude < def.insideRange then
		damage *= def.insideShare
	end
	if def.unseenDamage and hit.humanoid and toAttacker.Magnitude > 0.01 then
		local look = Util.flat(root.CFrame.LookVector)
		local unhurt = os.clock() - (lastHurtAt[hit.humanoid] or -math.huge) >= CombatStats.UnseenWindow
		if look.Magnitude > 0.01 and look.Unit:Dot(toAttacker.Unit) < 0 and unhurt then
			damage = math.max(damage, def.unseenDamage)
		end
	end
	return damage
end

-- The machete's wide cut: the nearest other living body inside the arc (sweepAngle either side of the swing, flat), its
-- body within the same front and in the open, takes sweepShare of the damage. One at most.
local function sweepSecond(player: Player, def: any, ctx: Context, origin: Vector3, direction: Vector3, front: number, primary: Instance)
	local flatDir = Util.flat(direction)
	if flatDir.Magnitude < 0.1 then
		return
	end
	flatDir = flatDir.Unit
	local cosLimit = math.cos(math.rad(def.sweepAngle or 55))
	local world: RaycastParams? = nil
	local best, bestDistance = nil, math.huge
	for _, model in ipairs(CombatService.getTargets(ctx.character, true)) do
		if model ~= primary then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local offset = Util.flat(root.Position - origin)
				local distance = bodyDistance(model, origin)
				if offset.Magnitude > 0.1 and offset.Unit:Dot(flatDir) >= cosLimit and distance <= front and distance < bestDistance then
					world = world or worldParams(CombatService.getTargets(ctx.character), ctx.character)
					local toRoot = root.Position - origin
					local blocked = workspace:Raycast(origin, toRoot, world)
					if blocked == nil or blocked.Distance >= toRoot.Magnitude - 0.75 then
						best, bestDistance = model, distance
					end
				end
			end
		end
	end
	local humanoid = best and best:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local root = best:FindFirstChild("HumanoidRootPart") :: BasePart
		local dealt = CombatService.applyHit(player, humanoid, (def.damage or 0) * def.sweepShare, {
			cause = "Combat", weaponId = def.id, position = origin, hitPosition = root.Position, melee = true, sweep = true,
			tier = "Flinch", knock = Moves.knockSpeed(def.id) * 0.6,
		})
		if dealt > 0 then
			playSound("Hit_Flesh", root.Position, player)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Combat v3: body state, the stamina ledger, reactions, guard, parry and dodge (numbers: Shared.Moves)
--------------------------------------------------------------------------------------------------------------------

local MV = Moves.cfg
local RX = Moves.reactions
local JITTER = CombatConfig.CooldownJitter or 0.12
local STAMINA = (Config.Movement and (Config.Movement :: any).Stamina) or {}
-- (the client's regen, at its idle bonus: the ledger is never stricter than the client's own bar)
local LEDGER_REGEN = (tonumber(STAMINA.Regen) or 0.2) * (tonumber(STAMINA.IdleRegenBonus) or 1.35)
local LEDGER_DELAY = tonumber(STAMINA.RegenDelay) or 1.0
local REACT_RANGE = ACTION_RANGE

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- The combat state of a body: a player's PlayerState, or a table kept for a dummy or any other non-player body.
function CombatService.bodyState(model: Instance?): { [string]: any }?
	if typeof(model) ~= "Instance" then
		return nil
	end
	local owner = Players:GetPlayerFromCharacter(model)
	if owner then
		return stateFor(owner)
	end
	local st = npcState[model]
	if not st then
		st = {}
		npcState[model] = st
	end
	return st
end

local function ledger(st: { [string]: any }, now: number): number
	local s = st.stamina or 1
	local from = math.max(st.staminaClock or now, (st.staminaAt or -math.huge) + LEDGER_DELAY)
	if now > from then
		s = math.min(1, s + LEDGER_REGEN * (now - from))
	end
	st.stamina = s
	st.staminaClock = now
	return s
end

local function spendLedger(st: { [string]: any }, amount: number, now: number): number
	local s = ledger(st, now)
	if amount > 0 then
		s = math.max(0, s - amount)
		st.stamina = s
		st.staminaAt = now
	end
	return s
end

function CombatService.spendStamina(player: Player, amount: number): number
	return spendLedger(stateFor(player), math.max(0, tonumber(amount) or 0), serverNow())
end

function CombatService.staminaOf(player: Player): number
	return ledger(stateFor(player), serverNow())
end

-- Sends one payload to every player listening within REACT_RANGE of `at` (but `exclude`).
local function broadcastNear(at: Vector3?, payload: { [string]: any }, exclude: Player?)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= exclude then
			local where = if at then listenerPosition(other) else nil
			if at == nil or (where ~= nil and (where - at).Magnitude <= REACT_RANGE) then
				CombatAction:FireClient(other, payload)
			end
		end
	end
end

local function rootOf(model: Instance?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Is `from` inside the front `arc` degrees of the body (flat)?
local function inFront(model: Instance, from: Vector3, arc: number): boolean
	local root = rootOf(model)
	if not root then
		return false
	end
	local look = Util.flat(root.CFrame.LookVector)
	local to = Util.flat(from - root.Position)
	if look.Magnitude < 0.05 or to.Magnitude < 0.05 then
		return true
	end
	return look.Unit:Dot(to.Unit) >= math.cos(math.rad(arc * 0.5))
end

local function regionMult(part: Instance?): number
	local region = RX.Knockback.Region
	if typeof(part) ~= "Instance" then
		return region.Torso or 1
	end
	local name = part.Name
	if name == "Head" then
		return region.Head or 1.4
	elseif name == "UpperTorso" or name == "LowerTorso" or name == "Torso" or name == "HumanoidRootPart" then
		return region.Torso or 1
	end
	return region.Limbs or 0.7
end

-- (guarding, parry window open) for a body now. A dummy guards while its attribute Guard is true, from GuardAt
-- (server time; the test hooks set them).
local function guardOf(model: Instance, st: { [string]: any }, now: number): (boolean, boolean)
	if now < (st.staggerUntil or -math.huge) then
		return false, false
	end
	local on, start, parry = st.guardOn == true, st.guardStart, st.guardParry == true
	if not Players:GetPlayerFromCharacter(model) and model:GetAttribute("Guard") == true then
		on = true
		start = tonumber(model:GetAttribute("GuardAt")) or -math.huge
		parry = st.npcParryUsedAt ~= start
	end
	if not on or type(start) ~= "number" then
		return false, false
	end
	local window = if now < (st.concentrationUntil or -math.huge) then MV.Parry.ConcentrationWindow else MV.Parry.Window
	return true, parry and now - start <= window
end

-- A reaction on a body (Combat_v3 1.8): the tier after poise and Brace, the stagger it holds, the knockback impulse
-- (the victim's own client applies it), the hit-stop. opts: position (where the blow came from), knock (studs/s),
-- hitPart, staggerTime (a tier's time overridden: a parry's rebound, a guard break), force (ignore poise), lift
-- (studs/s up: the knockdown), knockDir (a push that is not straight away from the blow: the running cut),
-- hitStop. Returns { tier, hitStop, impulse } or nil.
function CombatService.react(attacker: Player?, model: Instance, tierName: string, opts: { [string]: any }?): { [string]: any }?
	local o = opts or {}
	local st = CombatService.bodyState(model)
	if not st then
		return nil
	end
	local now = serverNow()
	local rank = if Moves.TIERS[tierName] then Moves.TIERS[tierName].rank else 1
	local braced = now < (st.braceUntil or -math.huge)
	if not o.force then
		if rank >= 2 and now < (st.poiseUntil or -math.huge) then
			rank = 1 -- poise: no stun-lock in a crowd
		end
		if braced then
			rank = math.max(1, rank - 1)
		end
	end
	local name = Moves.TIER_BY_RANK[rank]
	local tier = Moves.tier(name)
	local time = if o.staggerTime and rank >= 2 then o.staggerTime else tier.time
	if rank >= 2 then
		st.staggerUntil = math.max(st.staggerUntil or -math.huge, now + time)
		st.poiseUntil = st.staggerUntil + (if rank == 4 then RX.Poise.AfterKnockdown else RX.Poise.AfterStagger)
		st.interruptAt = now -- (a swing being wound up now is refused: CombatService.onMeleeSwing)
		st.guardOn = false
		st.heavyStart = nil
		if rank == 4 then
			st.knockdownAt = now
		end
	end
	local impulse = Vector3.zero
	local root = rootOf(model)
	local from = o.position
	if root and typeof(from) == "Vector3" then
		local away = Util.flat(root.Position - from)
		if typeof(o.knockDir) == "Vector3" and Util.flat(o.knockDir).Magnitude > 0.05 then
			away = Util.flat(o.knockDir)
		end
		if away.Magnitude < 0.05 then
			away = -Util.flat(root.CFrame.LookVector)
		end
		local speed = (tonumber(o.knock) or Moves.knockSpeed(nil)) * regionMult(o.hitPart) * (if braced then 0.5 else 1)
		speed = math.min(speed, RX.Knockback.Cap)
		impulse = away.Unit * speed + Vector3.new(0, if rank == 4 then (tonumber(o.lift) or 0) else 0, 0)
	end
	local hitStop = tonumber(o.hitStop) or tier.hitStop
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		CombatAction:FireClient(victim, {
			action = "Reaction", tier = name, impulse = impulse, hitStop = hitStop, time = time,
			from = if typeof(from) == "Vector3" then from else nil, attackerId = if attacker then attacker.UserId else nil,
			cap = RX.Knockback.Cap,
		})
	end
	broadcastNear(if root then root.Position else nil, {
		action = "React", userId = if victim then victim.UserId else nil, target = model, tier = name, hitStop = hitStop,
		time = time, from = if typeof(from) == "Vector3" then from else nil, attackerId = if attacker then attacker.UserId else nil,
	}, victim)
	return { tier = name, hitStop = hitStop, impulse = impulse }
end

-- Is the way from `from` to the body clear of world geometry?
function CombatService.lineOfSight(from: Vector3, model: Instance, exclude: Instance?): boolean
	local root = rootOf(model)
	if not root then
		return false
	end
	local world = worldParams(CombatService.getTargets(exclude), exclude)
	local offset = root.Position - from
	if offset.Magnitude < 0.5 then
		return true
	end
	local blocked = workspace:Raycast(from, offset, world)
	return blocked == nil or blocked.Distance >= offset.Magnitude - 0.75
end

-- The player can fight this moment: alive in an Active round, not frozen, not staggered.
function CombatService.canAct(player: Player): boolean
	local ctx = getContext(player)
	if not ctx then
		return false
	end
	return serverNow() >= ((stateFor(player) :: any).staggerUntil or -math.huge) - JITTER
end

-- One melee blow on one body, with the guard, the parry and the dodge (Combat_v3 1.3, 1.9): "Hit" | "Blocked" |
-- "Parried" | "Dodged" | "None", then the damage dealt. move: a Shared.Moves move. opts: damage (the blow's damage
-- before the guard), position (where it came from: the attacker's head), hitPosition, hitPart, weaponId,
-- armourPierce, attackerModel (its body: staggered by a parry), unblockable, guardBreak, staggerTime, knockDir, lift.
function CombatService.resolveHit(attacker: Player?, model: Instance, move: { [string]: any }, opts: { [string]: any }): (string, number)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return "None", 0
	end
	local st = CombatService.bodyState(model) :: { [string]: any }
	local now = serverNow()
	local root = rootOf(model)
	local at = if root then root.Position else opts.hitPosition
	if st.dodgeFrom and now >= st.dodgeFrom - 0.03 and now <= (st.dodgeUntil or 0) + 0.03 then
		broadcastNear(at, { action = "Dodged", target = model, attackerId = if attacker then attacker.UserId else nil })
		return "Dodged", 0
	end
	local damage = tonumber(opts.damage) or move.damage or 0
	local tierName = move.tier
	local staggerTime = opts.staggerTime
	local blocked = false
	local guarding, parryOpen = guardOf(model, st, now)
	local from = opts.position
	if guarding and typeof(from) == "Vector3" and inFront(model, from, MV.Guard.Arc) and not opts.unblockable then
		if move.kind == "Kick" or opts.guardBreak then
			-- the kick (and the pick's hook) breaks the guard
			st.guardOn = false
			if not Players:GetPlayerFromCharacter(model) then
				model:SetAttribute("Guard", false)
			end
			if tierName ~= "Knockdown" and tierName ~= "Heavy" then
				tierName = "Stagger"
				staggerTime = opts.guardBreakTime or MV.Kick.GuardBreakStagger
			end
			broadcastNear(at, { action = "GuardBreak", target = model })
		elseif parryOpen and not opts.noParry then
			-- parried: nothing lands, the attacker's weapon rebounds, the guard's owner may counter
			st.guardParry = false
			st.parryLockUntil = -math.huge
			st.npcParryUsedAt = tonumber(model:GetAttribute("GuardAt"))
			st.counterUntil = now + MV.Parry.Window + MV.Counter.Window
			local attackerModel = opts.attackerModel
			if typeof(attackerModel) == "Instance" and root then
				CombatService.react(nil, attackerModel, "Stagger", {
					force = true, position = root.Position, knock = 10,
					staggerTime = if move.heavyHit then MV.Parry.HeavyAttackerStagger else MV.Parry.AttackerStagger,
				})
			end
			if at then
				playSound("Hit_Metal", at, nil, 1.2, 1.45)
			end
			local owner = Players:GetPlayerFromCharacter(model)
			local payload = { action = "Parry", target = model, attacker = attackerModel, position = at,
				counterFor = MV.Counter.Window, attackerId = if attacker then attacker.UserId else nil }
			broadcastNear(at, payload)
			if attacker and attacker ~= owner then
				HitConfirm:FireClient(attacker, { damage = 0, parried = true, melee = true, target = if owner then "Player" else "Dummy",
					position = at, move = move.id })
			end
			return "Parried", 0
		else
			-- blocked: a share of it stops on the guard, the guard costs stamina, at none left it breaks
			local owner = Players:GetPlayerFromCharacter(model)
			local heldId = if owner then equippedItemId(owner) else nil
			local share = Moves.guardShare(heldId or "sword")
			local raw = damage
			damage = raw * (1 - share)
			blocked = true
			local drain = MV.Guard.StaminaPerDamage * raw * (if move.heavyHit then MV.Guard.HeavyDrainMult else 1)
			local left = spendLedger(st, drain, now)
			if left <= 0.001 then
				st.guardOn = false
				blocked = false -- (a broken guard: the rest of the blow lands as a heavy stagger)
				tierName = "Heavy"
				staggerTime = MV.Guard.BreakStagger
				broadcastNear(at, { action = "GuardBreak", target = model })
			end
			if at then
				playSound("Hit_Metal", at, nil, 1.1, if move.heavyHit then 0.8 else 1.05)
			end
			if blocked then
				broadcastNear(at, { action = "Block", target = model, position = opts.hitPosition or at, heavy = move.heavyHit == true })
			end
		end
	end
	local dealt = 0
	if damage > 0 then
		dealt = CombatService.applyHit(attacker, humanoid, damage, {
			cause = "Combat",
			weaponId = opts.weaponId,
			position = from,
			hitPosition = opts.hitPosition,
			melee = true,
			armourPierce = opts.armourPierce,
			stars = opts.stars,
			tier = if blocked then nil else tierName,
			react = not blocked,
			blocked = blocked,
			knock = move.knock,
			hitPart = opts.hitPart,
			staggerTime = staggerTime,
			hitStop = move.hitStop,
			knockDir = opts.knockDir,
			lift = opts.lift,
			move = move.id,
		})
	end
	return if blocked then "Blocked" else "Hit", dealt
end

-- The windup of the move a "Start" announces (the others' clients fit the swing so its cut lands at the strike).
local function moveWindup(stats: any, moveId: any): number
	local kind, index = Moves.parse(moveId)
	if kind == "Heavy" then
		return MV.Heavy.ReleaseWindup[Moves.weight(stats.id)] or 0.16
	elseif kind == "Counter" then
		return MV.Counter.Windup
	elseif kind == "Kick" then
		return MV.Kick.Windup
	elseif kind == "Light" then
		return Moves.step(stats, stats.id, index).windup
	end
	return stats.windup or 0.1
end

-- The move a strike claims, as the server allows it (see the header), or (nil, refusal reason).
local function resolveMove(player: Player, st: PlayerState, stats: any, moveId: any, held: any, now: number): ({ [string]: any }?, string?)
	local kind, index = Moves.parse(moveId)
	local id = stats.id
	if kind == "Heavy" then
		local H = MV.Heavy
		if st.heavyStart == nil or st.heavyItem ~= id then
			return Moves.step(stats, id, 1), nil -- (no hold on record: the press counts as a tap)
		end
		local releaseWindup = H.ReleaseWindup[Moves.weight(id)] or 0.16
		-- (the client sends "Charge" once Attack has been held MinHold, so the hold is that plus the time since)
		local measured = (now - releaseWindup) - st.heavyStart + H.MinHold + JITTER
		local claimed = tonumber(held) or 0
		if claimed ~= claimed then
			claimed = 0
		end
		local h = math.clamp(math.min(claimed, measured), 0, H.FullHold + H.MaxHoldAfterFull)
		if h < H.MinHold - 0.03 then
			return Moves.step(stats, id, 1), nil
		end
		local move = Moves.heavy(stats, id, h, now < (st.concentrationUntil or -math.huge))
		move.held = h
		if h > H.FullHold then
			move.stamina += H.HoldDrain * (h - H.FullHold)
		end
		return move, nil
	elseif kind == "Counter" then
		if now <= (st.counterUntil or -math.huge) + JITTER then
			return Moves.counter(stats, id), nil
		end
		return nil, "CounterWindow"
	elseif kind == "Kick" then
		if now < (st.kickReady or -math.huge) - JITTER then
			return nil, "KickCooldown"
		end
		return Moves.kick(), nil
	elseif kind == "Skill" then
		local skills = Services.SkillService
		if skills and type(skills.strikeMove) == "function" then
			local ok, move = pcall(skills.strikeMove, player, moveId, now, stats)
			if ok and type(move) == "table" then
				return move, nil
			end
		end
		return nil, "SkillStrike"
	end
	local i = if kind == "Light" and index then index else 1
	if i < 1 or i > Moves.chainLength(id) then
		i = 1
	end
	if i > 1 then
		-- a step only follows the step before it, inside the chain window after that one ended (lag allowed)
		local windup = Moves.step(stats, id, i).windup
		local follows = st.chainItem == id and st.chainStep == i - 1 and st.chainEndsAt ~= nil
			and now - windup <= st.chainEndsAt + MV.ChainWindow + JITTER + SWING_LATE
		if not follows then
			i = 1
		end
	end
	return Moves.step(stats, id, i), nil
end

--------------------------------------------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------------------------------------------

-- MeleeSwing("Start", variant, move): a swing began on the attacker's client. The others near them are told now, so
-- they see it wind up before the blow lands (told at the strike, the victim was hurt first and saw the swing
-- afterwards). Cheap: no trace, one small message to the players in range, at most one per swing (per weapon
-- cooldown when no strike follows, never more often than START_MIN_GAP), and not while the swing gate is closed.
local function onMeleeStart(player: Player, variant: any, moveId: any)
	if not Net.rateLimit(player, "MeleeStart", 5, 3) then
		return
	end
	local ctx = getContext(player)
	if not ctx then
		return
	end
	local def = meleeStatsFor(player, equippedItemId(player))
	if not def then
		return
	end
	local st = stateFor(player)
	local now = workspace:GetServerTimeNow()
	if now < st.nextSwingStart - (CombatConfig.CooldownJitter or 0.12) then
		return -- (the strike, if it is accepted after all, announces the swing itself)
	end
	-- One relayed start per swing: an accepted strike clears startAt, so an honest attacker never waits here. A start
	-- with no strike after it (a modified client showing wind-ups it never swings) holds the next one back for that
	-- weapon's cooldown, not START_MIN_GAP: a fake mace wind-up every 1 s instead of three a second.
	if st.startAt and now - st.startAt < (st.startGap or START_MIN_GAP) then
		return
	end
	st.startAt = now
	st.startItem = def.id
	st.startGap = math.max(START_MIN_GAP, (def.cooldown or 0.5) - (CombatConfig.CooldownJitter or 0.12))
	local move = if Moves.parse(moveId) then moveId else nil
	broadcastAction(player, "Swing", def.id, nil, swingVariant(variant), moveWindup(def, move), { move = move })
end

-- MeleeSwing("Charge", clientTime | false): the heavy's hold, on record for its strike; the others see it wound.
local function onCharge(player: Player, clientTime: any)
	if not Net.rateLimit(player, "MeleeCharge", 4, 3) then
		return
	end
	local st = stateFor(player)
	if clientTime == false then
		if st.heavyStart then
			st.heavyStart = nil
			broadcastAction(player, "Charge", st.heavyItem, true)
		end
		return
	end
	local ctx = getContext(player)
	local def = ctx and meleeStatsFor(player, equippedItemId(player))
	if not def then
		return
	end
	local now = serverNow()
	if now < st.nextSwingStart - JITTER or now < (st.staggerUntil or -math.huge) - JITTER then
		return
	end
	local start = now
	if type(clientTime) == "number" and clientTime == clientTime then
		start = math.clamp(clientTime, now - JITTER, now)
	end
	st.heavyStart = start
	st.heavyItem = def.id
	st.guardOn = false
	broadcastAction(player, "Charge", def.id)
end

-- MeleeSwing("Guard", on, clientTime)
local function onGuard(player: Player, on: any, clientTime: any)
	if not Net.rateLimit(player, "MeleeGuard", 8, 4) then
		return
	end
	local st = stateFor(player)
	local now = serverNow()
	if on ~= true then
		if st.guardOn then
			st.guardOn = false
			broadcastAction(player, "Guard", st.guardItem, true)
		end
		return
	end
	local ctx = getContext(player)
	local def = ctx and meleeStatsFor(player, equippedItemId(player))
	if not def or now < (st.staggerUntil or -math.huge) - JITTER then
		return
	end
	local start = now
	if type(clientTime) == "number" and clientTime == clientTime then
		start = math.clamp(clientTime, now - JITTER, now)
	end
	local window = if now < (st.concentrationUntil or -math.huge) then MV.Parry.ConcentrationWindow else MV.Parry.Window
	st.guardOn = true
	st.guardStart = start
	st.guardItem = def.id
	-- a guard raised inside the last one's whiff lock has no parry window (pressing guard over and over earns nothing)
	st.guardParry = start >= (st.parryLockUntil or -math.huge)
	st.parryLockUntil = start + window + MV.Parry.WhiffLock
	st.heavyStart = nil
	broadcastAction(player, "Guard", def.id)
end

-- MeleeSwing("Dodge", direction, clientTime)
local function onDodge(player: Player, direction: any, clientTime: any)
	if not Net.rateLimit(player, "MeleeDodge", 3, 2) then
		refuse(player, "DodgeRate")
		return
	end
	local ctx = getContext(player)
	if not ctx then
		return
	end
	local st = stateFor(player)
	local now = serverNow()
	local D = MV.Dodge
	local down = st.knockdownAt ~= nil and now - st.knockdownAt < (RX.Knockdown.Down or 1)
	local rollOut = down and now - st.knockdownAt >= (RX.Knockdown.RollOutAfter or 0.5)
	if now < (st.staggerUntil or -math.huge) - JITTER and not rollOut then
		refuse(player, "DodgeStaggered")
		return
	end
	if now < (st.dodgeReady or -math.huge) - JITTER then
		refuse(player, "DodgeCooldown")
		return
	end
	local times = st.dodgeTimes or {}
	local recent = {}
	for _, t in ipairs(times) do
		if now - t < D.RepeatWindow then
			table.insert(recent, t)
		end
	end
	local cost = D.Stamina * (if #recent >= 2 then D.RepeatCostMult else 1)
	if ledger(st, now) < D.Stamina - 1e-3 then
		refuse(player, "DodgeStamina")
		return
	end
	spendLedger(st, cost, now)
	table.insert(recent, now)
	st.dodgeTimes = recent
	local start = now
	if type(clientTime) == "number" and clientTime == clientTime then
		start = math.clamp(clientTime, now - JITTER, now)
	end
	st.dodgeFrom = start + D.Startup
	st.dodgeUntil = start + D.Startup + D.Travel
	st.dodgeReady = start + D.Cooldown
	st.guardOn = false
	st.heavyStart = nil
	local dir = if Util.isFiniteVector(direction) and (direction :: Vector3).Magnitude <= 1.1 then Util.flat(direction :: Vector3) else Vector3.zero
	broadcastAction(player, "Dodge", nil, nil, nil, nil, { direction = dir })
end

local function onMeleeSwing(player: Player, lookDirection: any, predictedHit: any, variant: any, target: any, startTime: any, moveId: any, held: any)
	if lookDirection == "Start" then
		onMeleeStart(player, predictedHit, variant)
		return
	elseif lookDirection == "Charge" then
		onCharge(player, predictedHit)
		return
	elseif lookDirection == "Guard" then
		onGuard(player, predictedHit, variant)
		return
	elseif lookDirection == "Dodge" then
		onDodge(player, predictedHit, variant)
		return
	elseif type(lookDirection) == "string" then
		return -- ("Skill": SkillService)
	end
	if not Net.rateLimit(player, "MeleeSwing", 7, 4) then
		refuse(player, "MeleeRate")
		return
	end
	if not Util.isFiniteVector(lookDirection) then
		return
	end
	local magnitude = (lookDirection :: Vector3).Magnitude
	if magnitude < 0.9 or magnitude > 1.1 then
		return
	end
	local direction = (lookDirection :: Vector3) / magnitude
	local ctx = getContext(player)
	if not ctx then
		return
	end
	local stats = meleeStatsFor(player, equippedItemId(player)) -- (the weapon's stats at its stars: CombatStats.melee)
	if not stats then
		return
	end
	if not facingOk(ctx.root, direction, MELEE_FACING_DOT) then
		refuse(player, "MeleeFacing")
		return
	end
	local st = stateFor(player)
	local now = workspace:GetServerTimeNow()
	local move, why = resolveMove(player, st, stats, moveId, held, now)
	if not move then
		refuse(player, why or "MeleeMove")
		return
	end
	-- staggered: no attack; a swing being wound up when the stagger began is cancelled (Interrupted)
	if now < (st.staggerUntil or -math.huge) - JITTER then
		refuse(player, "Staggered")
		return
	end
	local began = now - (move.windup or 0.1)
	if type(startTime) == "number" and startTime == startTime then
		began = math.clamp(startTime, began - SWING_LATE, began)
	end
	if st.interruptAt and st.interruptAt > began + 0.02 and st.interruptAt <= now then
		refuse(player, "Interrupted")
		return
	end
	-- out of stamina: the recovery takes twice as long (the chain slows)
	local total = move.total or stats.cooldown or 0.5
	if ledger(st, now) <= 0.001 then
		local w = move.windup or 0.1
		total = w + (total - w) / MV.ExhaustedAttackSpeed
	end
	if move.kind ~= "Skill" then
		if not trySwing(st, { windup = move.windup, cooldown = total }, now, startTime) then
			refuse(player, "MeleeCooldown")
			return
		end
	end
	if move.kind == "Light" then
		st.chainItem, st.chainStep, st.chainEndsAt = stats.id, move.index, began + total
	elseif move.kind ~= "Skill" then
		st.chainStep = nil
	end
	if move.kind == "Heavy" then
		st.heavyStart = nil
	elseif move.kind == "Counter" then
		st.counterUntil = nil
	elseif move.kind == "Kick" then
		st.kickReady = now + MV.Kick.Cooldown
	end
	if st.guardOn then
		st.guardOn = false -- (a strike lowers the guard; the client raises it again after)
	end
	local cost = (move.stamina or 0) * (if now < (st.concentrationUntil or -math.huge) then 0.7 else 1)
	spendLedger(st, cost, now)
	-- Sprint Burst and Quiet Step end when you attack (Combat_v3 2.3)
	local skillsSvc = Services.SkillService
	if skillsSvc and type(skillsSvc.onAttack) == "function" and move.kind ~= "Skill" then
		pcall(skillsSvc.onAttack, player)
	end

	local origin = ctx.head.Position
	local heavySound = move.heavyHit or (stats.cooldown or 0) >= HEAVY_SWING_COOLDOWN
	playSound(if heavySound then "Swing_Heavy" else "Swing_Light", origin, player, nil, if move.heavyHit then 0.85 else nil)
	-- the others saw this swing start (onMeleeStart); if its start never came, they are told now
	local announced = st.startAt ~= nil and st.startItem == stats.id and now - st.startAt < (move.windup or 0.1) + 0.6
	st.startAt = nil
	if not announced and move.kind ~= "Skill" then
		broadcastAction(player, "Swing", stats.id, nil, swingVariant(variant), 0, { move = move.id })
	end

	-- a swing the attacker's screen showed as a miss never lands; one it showed hitting is checked by a sweep whose
	-- front (cast length + radius) is MELEE_REACH_ALLOWANCE past the front of the attacker's own, plus what the
	-- attacker and the target moved, on the server, in the last MELEE_LAG_TIME seconds (meleeFront). A slash sends
	-- three such traces across its arc, a stab one thinner one (Moves.traceDirections): the same caps on each.
	local claimed = if typeof(target) == "Instance" and target:IsA("Model") then target else nil
	local reachDef = { range = (move.range or stats.range or 5) + (move.reach or 0) }
	local front, _, _, _, theirs = meleeFront(reachDef, ctx.character, origin, direction, predictedHit == true, claimed)
	-- the client's ball plus a little, wider by what the target moved lately (its side moved that far since the
	-- attacker saw it), never wider than MeleeHitRadius; the body itself must be within the front (bodyDistance)
	local radius = math.min(CombatConfig.MeleeHitRadius, CombatConfig.MeleeHitRadius * MELEE_PREDICT_RADIUS + MELEE_BALL_SLACK + theirs)
	if move.stab then
		radius *= MV.StabRadius
	end
	local hit: MeleeHit? = nil
	local worldHit: MeleeHit? = nil
	for _, dir in ipairs(Moves.traceDirections(move, direction)) do
		local found = meleeTrace(ctx.character, origin, dir, math.max(front - radius, 0), radius, predictedHit ~= true, claimed, front)
		if found and found.humanoid then
			hit = found
			break
		elseif found and not worldHit then
			worldHit = found
		end
	end
	hit = hit or worldHit
	if not hit then
		if predictedHit == true then
			refuse(player, "MeleeNoTarget") -- (the attacker's screen showed a hit; the server found nobody there)
		end
		return
	end
	if hit.humanoid and hit.model then
		local victimState = CombatService.bodyState(hit.model)
		local guarding = victimState ~= nil and victimState.guardOn == true
		local dmgDef = table.clone(stats)
		dmgDef.damage = move.damage
		if move.insideFull or move.kind ~= "Light" then
			dmgDef.insideRange = nil -- (the butt swing, the heavy lunge: full damage inside the shaft)
		end
		if guarding or (move.kind ~= "Light" and move.kind ~= "Heavy") then
			dmgDef.unseenDamage = nil -- (the knife's unseen hit never lands on a guard, nor on kicks and skills)
		end
		local damage = meleeDamage(dmgDef, ctx, hit)
		local guardBreak = stats.id == "climb_pick" and move.kind == "Light" and move.last
		local result, dealt = CombatService.resolveHit(player, hit.model, move, {
			damage = damage,
			position = origin,
			hitPosition = hit.position,
			hitPart = hit.part,
			weaponId = stats.id,
			armourPierce = stats.armourPierce,
			stars = stats.stars,
			attackerModel = ctx.character,
			guardBreak = guardBreak,
			guardBreakTime = if guardBreak then 0.3 else nil,
		})
		if result == "Hit" and dealt > 0 then
			playSound("Hit_Flesh", hit.position, player, nil, if move.heavyHit or move.kind == "Counter" then 0.78 elseif move.kind == "Kick" then 0.6 else nil)
		end
		if result == "Hit" and move.sweep and stats.sweepShare then
			local sweepDef = table.clone(stats)
			sweepDef.damage = move.damage
			sweepSecond(player, sweepDef, ctx, origin, direction, front, hit.model)
		end
	else
		if predictedHit == true then
			refuse(player, "MeleeNoTarget") -- (the attacker's screen showed a hit; the server found nobody there)
		end
		playSound(worldHitSound(hit.material), hit.position, player)
	end
end

local function validOrigin(ctx: Context, origin: any, targets: { Instance }): Vector3
	local head = ctx.head.Position
	if not Util.isFiniteVector(origin) then
		return head
	end
	local offset = (origin :: Vector3) - head
	local speed = math.min(ctx.root.AssemblyLinearVelocity.Magnitude, 80)
	-- The honest origin is the eye, under 2 studs from the head, plus what the body moved while the message travelled.
	-- A shot that claims to start further from where the server sees the attacker starts at their head instead: 3 studs
	-- standing still, more with speed, never more than the old allowance (9 studs at rest let a shot start round a corner).
	local limit = math.min(3 + speed * 0.2, (CombatConfig.RangedOriginTolerance or 6) + CombatConfig.MeleeLagTolerance + speed * 0.12)
	if offset.Magnitude > limit then
		return head
	end
	if offset.Magnitude > 0.5 and workspace:Raycast(head, offset, worldParams(targets, ctx.character)) then
		return head -- the reported origin is on the far side of a wall
	end
	return origin :: Vector3
end

local function onRangedRelease(player: Player, shotId: any, origin: any, direction: any, charge: any, mode: any)
	-- A "Draw" over the limit is still put on record (below), only not relayed: quick clicks send Draw and Cancel in
	-- pairs, 10 to 12 messages a second, and when the limiter dropped the Draw of the click that was then held, the
	-- full-draw shot after it was refused (BowNoDraw) while the archer saw their own arrow fly. Recording a draw is
	-- two assignments and can only restart the sender's own charge.
	local limited = not Net.rateLimit(player, "RangedRelease", 8, 4)
	if limited and mode ~= "Draw" then
		return
	end
	if mode ~= "Fire" and mode ~= "Throw" and mode ~= "Draw" and mode ~= "Cancel" then
		return
	end
	local ctx = getContext(player)
	if not ctx then
		return
	end
	local st = stateFor(player)
	local now = os.clock()
	local itemId = equippedItemId(player)
	local def = ItemDefs.get(itemId)

	if mode == "Draw" then
		if def and def.kind == "Bow" and hasItem(player, def.ammo or "arrow", 1) then
			-- told once per draw: a "Draw" sent again while the others already see this bow drawn (a modified client
			-- restarting the creak eight times a second, or an honest one whose "Cancel" the limiter dropped) only
			-- restarts the charge
			local shown = st.drawStart ~= nil and st.drawItem == itemId and st.drawShown == true
			st.drawStart = now
			st.drawItem = itemId
			if not shown and not limited then
				broadcastAction(player, "Draw", itemId)
				shown = true
			end
			st.drawShown = shown
		end
		return
	elseif mode == "Cancel" then
		if st.drawStart then
			st.drawStart = nil
			broadcastAction(player, "Release", st.drawItem or itemId, true)
			st.drawItem = nil
		end
		return
	end

	if type(shotId) ~= "string" or #shotId == 0 or #shotId > 40 then
		return
	end
	if not def or not Util.isFiniteVector(direction) then
		return
	end
	local magnitude = (direction :: Vector3).Magnitude
	if magnitude < 0.9 or magnitude > 1.1 then
		return
	end
	local aim = (direction :: Vector3) / magnitude
	if not facingOk(ctx.root, aim, RANGED_FACING_DOT) then
		return
	end
	local projectiles = Services.ProjectileService
	if not projectiles or type(projectiles.fire) ~= "function" then
		return
	end
	local amount = if Util.isFiniteNumber(charge) then math.clamp(charge, 0, 1) else 0
	local start = validOrigin(ctx, origin, CombatService.getTargets(ctx.character))

	if mode == "Fire" then
		if def.kind ~= "Bow" then
			return
		end
		-- An arrow's power comes from a real draw of this bow: the "Draw" the client sent when the string came back
		-- (cleared by a shot, a let-down or a weapon switch). Without one there is no shot. (Measured from the last
		-- shot instead, a client that never sent Draw had a full-power arrow the instant it equipped the bow, and
		-- half power every 0.3 s.) The draw counts from the later of that message and BOW_RECOVER after the last shot
		-- (bowFree), with CHARGE_JITTER forgiven for the network; a shot that used the forgiveness counts as loosed
		-- when its charge was really reached, so the forgiveness is never banked from shot to shot.
		local drawStart = if st.drawItem == itemId then st.drawStart else nil
		st.drawStart = nil -- (each shot needs its own draw)
		if not drawStart then
			refuse(player, "BowNoDraw")
			return
		end
		local bow = CombatStats.bow(def, equippedStars(player)) -- (draw time, speed, damage and range at its stars)
		local drawTime = bow.drawTime
		local skills = Services.SkillService
		if skills and type(skills.hasBuff) == "function" and skills.hasBuff(player, "steady_hands") then
			drawTime *= (Moves.skills.General.steady_hands.DrawMult or 0.85) -- (Steady Hands: a quicker draw)
		end
		local began = math.max(drawStart, st.bowFree)
		amount = math.min(amount, math.clamp((now - began + CHARGE_JITTER) / drawTime, 0, 1))
		if amount < (CombatConfig.MinBowCharge or 0.2) - 1e-3 then
			refuse(player, "BowCharge")
			broadcastAction(player, "Release", itemId, true) -- (the others stop hearing the draw)
			return
		end
		local ammo = def.ammo or "arrow"
		if not consumeItem(player, ammo, 1) then
			broadcastAction(player, "Release", itemId, true)
			return
		end
		st.bowFree = math.max(now, began + amount * drawTime) + BOW_RECOVER
		local speed = Util.lerp(bow.speedMin, bow.speedMax, amount)
		local damage = Util.lerp(bow.damageMin, bow.damageMax, amount)
		-- Piercing Shot (the bow's skill): the next full-draw arrow flies faster and passes through the first body
		local pierce = nil
		if amount >= 0.999 and skills and type(skills.consumeArmed) == "function" and skills.consumeArmed(player, "piercing_shot") then
			local P = Moves.skills.Weapon.Bow
			speed *= P.SpeedMult or 1.15
			pierce = { secondShare = P.SecondShare or 0.7 }
		end
		local fired = projectiles.fire(player, ammo, start, aim * speed, bow.gravity, damage, {
			pierce = pierce, -- (ProjectileService: pass through the first contender and hit a second at secondShare)
			shotId = shotId,
			weaponId = itemId,
			headshotMultiplier = bow.headshotMultiplier,
			headCap = bow.headCap, -- a bow headshot never over 90 (the owner's number)
			onTarget = bow.onTarget, -- full damage within its on-target range, then less with distance
			falloffBeyond = bow.falloffBeyond,
			falloffMin = bow.falloffMin,
			recoverItem = ammo, -- it stays where it ends up (ProjectileService.WorldProjectiles)
		})
		if not fired then
			refund(player, ammo)
			return
		end
		playSound("BowRelease", start, player)
		broadcastAction(player, "Release", itemId)
		return
	end

	-- Throw
	local speed, gravity, damage
	local thrownStars, pierce, headMultiplier = nil, nil, nil
	if def.kind == "Throwable" then
		headMultiplier = CombatStats.throwable(def).headshotMultiplier
		if not tryCooldown(st, "nextThrow", def.cooldown or 0.5, now) then
			return
		end
		if not consumeItem(player, itemId :: string, 1) then
			return
		end
		speed, gravity, damage = def.speed, def.gravity, def.damage
	elseif def.kind == "Melee" and def.throwable then
		local stats = CombatStats.melee(def, equippedStars(player)) -- (read before the weapon leaves the hand)
		if not tryCooldown(st, "nextThrow", stats.cooldown or 0.8, now) then
			return
		end
		local inventory = Services.InventoryService
		if not inventory or type(inventory.removeEquipped) ~= "function" then
			return
		end
		if inventory.removeEquipped(player) ~= itemId then
			return
		end
		speed, gravity, damage = stats.throwSpeed, stats.throwGravity, stats.throwDamage
		thrownStars, pierce, headMultiplier = stats.stars, stats.armourPierce, stats.throwHeadMultiplier
	else
		return
	end
	-- Ricochet (the throwing family's skill): the next throw glances once toward the nearest other contender
	local skills = Services.SkillService
	local ricochet = nil
	if skills and type(skills.consumeArmed) == "function" and skills.consumeArmed(player, "ricochet") then
		local R = Moves.skills.Weapon.Throwing
		ricochet = { share = R.Share or 0.7, range = R.Range or 20, cone = R.Cone or 120 }
	end
	local fired = projectiles.fire(player, itemId :: string, start, aim * (speed or 120), gravity or 40, damage or 0, {
		ricochet = ricochet, -- (ProjectileService: on the first contact, one bounce at share of the damage)
		shotId = shotId,
		weaponId = itemId,
		headshotMultiplier = headMultiplier or CombatConfig.DefaultHeadshotMultiplier,
		armourPierce = pierce,
		recoverItem = itemId, -- it stays where it ends up, like an arrow
		recoverStars = thrownStars, -- (a thrown weapon keeps its stars where it lands: see ProjectileService)
	})
	if not fired then
		refund(player, itemId :: string)
		return
	end
	-- (a quiet throw, ItemDefs quietThrow: only those within that many studs hear it, and softly)
	local quiet = tonumber(def.quietThrow)
	playSound("Throw", start, player, if quiet then 0.45 else nil, nil, quiet)
	broadcastAction(player, "Throw", itemId)
end

-- A draw doesn't outlive the bow in hand: switching away and back gave a full-power arrow at once.
local function onEquippedChanged(player: Player)
	local st = playerState[player]
	if st and st.drawStart then
		local was = st.drawItem
		st.drawStart = nil
		st.drawItem = nil
		broadcastAction(player, "Release", was, true)
	end
	-- (Combat v3: a guard, a heavy's hold and a chain don't outlive the weapon in hand)
	if st then
		if st.guardOn then
			st.guardOn = false
			broadcastAction(player, "Guard", st.guardItem, true)
		end
		if st.heavyStart then
			st.heavyStart = nil
			broadcastAction(player, "Charge", st.heavyItem, true)
		end
		st.chainStep = nil
	end
end

-- Test hook (server): a dummy or any other body strikes `victim` with a sword move ("L1".."L4", "H" at full charge,
-- "K"), through the same guard, parry and dodge rules as a player's blow. Its swing shows on every client (CombatAction
-- "Swing" with `model`). Returns (result, dealt).
function CombatService._npcStrike(attackerModel: Model, victim: Model, moveId: string?, itemId: string?): (string, number)
	local id = itemId or "sword"
	local stats = CombatStats.melee(ItemDefs.get(id) or FISTS, 1)
	local kind, index = Moves.parse(moveId or "L1")
	local move = if kind == "Heavy" then Moves.heavy(stats, id, 2)
		elseif kind == "Kick" then Moves.kick()
		else Moves.step(stats, id, index or 1)
	local root = rootOf(attackerModel)
	local at = if root then root.Position + Vector3.new(0, 1.5, 0) else nil
	broadcastNear(at, { action = "Swing", model = attackerModel, itemId = id, variant = move.variant, lead = 0, move = move.id })
	return CombatService.resolveHit(nil, victim, move, {
		damage = move.damage, position = at, hitPosition = rootOf(victim) and (rootOf(victim) :: BasePart).Position or nil,
		weaponId = id, attackerModel = attackerModel,
	})
end
CombatService._bodyStates = function(): { [Instance]: any }
	local all = {}
	for player, st in pairs(playerState) do
		all[player] = st
	end
	for model, st in pairs(npcState) do
		all[model] = st
	end
	return all
end
CombatService._resolveMove = resolveMove

-- For SkillService: the player's fighting context ({ character, humanoid, head, root } or nil) and the melee stats of
-- the weapon in hand at its stars (nil for a bow or a throwable).
function CombatService.context(player: Player): { [string]: any }?
	return getContext(player)
end
function CombatService.meleeStatsOf(player: Player): { [string]: any }?
	return meleeStatsFor(player, equippedItemId(player))
end
function CombatService.heldItem(player: Player): string?
	return equippedItemId(player)
end
CombatService.broadcastNear = broadcastNear
CombatService.playSound = playSound

-- Test hooks (server only): the server's melee trace, the check on MeleeSwing's variant, the swing gate, and the count
-- of refused swings and shots by reason.
CombatService._trace = meleeTrace
CombatService._swingVariant = swingVariant
CombatService._trySwing = trySwing
CombatService._refusals = refusals
CombatService._stateOf = function(player: Player): PlayerState? -- (the swing and draw record of one player, to read)
	return playerState[player]
end
CombatService._meleeFront = meleeFront -- (def, character, origin, direction, predicted, claimed) -> front, still, cap, own, theirs
CombatService._bodyDistance = bodyDistance -- (model, point) -> studs to its body (not held items or anything worn)
CombatService._equippedStars = equippedStars
-- the two remotes' handlers, for a test script on the server that plays a (modified) client: same arguments as the
-- remotes after the player
CombatService._meleeSwing = function(player: Player, ...: any)
	onMeleeSwing(player, ...)
end
CombatService._rangedRelease = function(player: Player, ...: any)
	onRangedRelease(player, ...)
end
CombatService._recentTravel = function(model: Instance?, window: number?): number
	return recentTravel(model, os.clock(), window or MELEE_LAG_TIME)
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function CombatService.Init(registry)
	Services = registry
	HitConfirm = Net.event("HitConfirm")
	CombatAction = Net.event("CombatAction")
	SfxRemote = Net.event("Sfx")
end

function CombatService.Start()
	Net.event("MeleeSwing").OnServerEvent:Connect(onMeleeSwing)
	Net.event("RangedRelease").OnServerEvent:Connect(onRangedRelease)
	Players.PlayerRemoving:Connect(function(player)
		playerState[player] = nil
	end)
	Players.PlayerAdded:Connect(watchPlayerHitBox)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayerHitBox(player)
	end
	local inventory = Services.InventoryService
	if inventory and type(inventory.equippedChanged) == "table" and type(inventory.equippedChanged.Connect) == "function" then
		inventory.equippedChanged:Connect(onEquippedChanged)
	end
	-- Training dummies come and go with practice rounds, in Studio and on live servers alike (wantDummies decides);
	-- updateDummies returns at once while there are none.
	GameState:GetAttributeChangedSignal("Phase"):Connect(refreshDummies)
	GameState:GetAttributeChangedSignal("Practice"):Connect(refreshDummies)
	local round = Services.RoundService
	if round and type(round.roundEnded) == "table" and type(round.roundEnded.Connect) == "function" then
		round.roundEnded:Connect(function()
			clearDummies()
		end)
	end
	RunService.Heartbeat:Connect(updateDummies)
	RunService.Heartbeat:Connect(function()
		sampleTrails(os.clock())
	end)
	refreshDummies()
end

return CombatService
