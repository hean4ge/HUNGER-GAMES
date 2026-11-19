--[[
	SkillService - the two skills a player brings into a round (docs/design/Combat_v3.md section 2), server-authoritative.

	A player has one WEAPON skill, from their Specialty family (it works while they hold a weapon of that family), and
	one GENERAL skill. Numbers: Shared.Moves.skills (Config.Skills overrides them).
	  Weapon: Head Kick (Fists), Chained Strikes (Short blade), Running Cut (Sword), Whirl (Axe), Vault Kick (Spear),
	          Ricochet (Throwing: arms the next throw), Piercing Shot (Bow: arms the next full-draw arrow).
	  General: Concentration, Second Wind, Sprint Burst, Quiet Step, Steady Hands, Brace.
	Skills are off in the train and for the first LockedFirst seconds of a real round (practice rounds: from the start).

	Client -> server: MeleeSwing("Skill", slot = "weapon" | "general", clientTime, direction: Vector3 (the camera's look))
	  (the same remote as every melee move: no new RemoteEvent). Rate limit 2 a second.
	  Head Kick and the chained strikes then send their blows as MeleeSwing strikes with the move "HK" / "S1".."S5"
	  (CombatService checks reach, line of sight, guard and parry as for any blow; strikeMove below times them).
	  Running Cut, Whirl and Vault Kick are traced here at their moments (one spatial query each, never per frame), at
	  most MaxTargets contenders each, the line of sight checked, through CombatService.resolveHit (guard, parry, dodge).
	Server -> client: Player attributes SkillWeaponReadyAt / SkillGeneralReadyAt (server time a slot is ready again),
	  SkillsOpenAt (server time skills unlock this round), SkillWeapon / SkillGeneral (the ids), SprintBurstUntil and
	  QuietStepUntil (for MovementController and AudioController), SteadyHandsUntil, ConcentrationUntil, BraceUntil;
	  CombatAction { action = "Skill", userId, skill, direction } to the players near (their clients show it), and
	  { action = "SkillDenied", slot, reason } to the user.
	Loadout: Player attributes LoadoutSpecialty (a family: "Fists" ... "Bow") and LoadoutGeneral (a general skill id),
	  or SkillService.setLoadout(player, specialty, general) (the Loadout screen's LoadoutSet). Until a player has one,
	  the Specialty is the family of the weapon in hand and the general skill Moves.skills.DefaultGeneral.

	API
	  SkillService.setLoadout(player, specialty?, general?)
	  SkillService.strikeMove(player, moveId, now, stats) -> move?   (CombatService: a skill strike's move, or nil)
	  SkillService.consumeArmed(player, id) -> boolean  ("ricochet" | "piercing_shot": the next throw / arrow)
	  SkillService.hasBuff(player, id) -> boolean       ("concentration", "steady_hands", "brace", "sprint_burst", ...)
	  SkillService._use(player, slot, direction?)       test hook: as the remote, from the server
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Moves = require(Shared:WaitForChild("Moves"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local SK = Moves.skills
local JITTER = (Config.Combat and Config.Combat.CooldownJitter) or 0.12
local LATE = 0.35 -- seconds a skill strike may arrive late

local SkillService = {}

local Services: { [string]: any } = {}
type SkillState = {
	ready: { [string]: number },
	active: { [string]: any }?,
	armed: { [string]: number },
	buffs: { [string]: number },
	specialty: string?,
	general: string?,
}
local states: { [Player]: SkillState } = {}
local activeSince = -math.huge -- server time the round went Active
local refusals: { [string]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stateOf(player: Player): SkillState
	local st = states[player]
	if not st then
		st = { ready = {}, armed = {}, buffs = {} }
		states[player] = st
	end
	return st
end

local function refuse(player: Player, slot: string, reason: string)
	refusals[reason] = (refusals[reason] or 0) + 1
	if Config.IsStudio then
		print(string.format("[SkillService] refused %s (%s) from %s", reason, slot, player.Name))
	end
	Net.event("CombatAction"):FireClient(player, { action = "SkillDenied", slot = slot, reason = reason })
end

local function isPractice(): boolean
	local round = Services.RoundService
	if round and type(round.isPractice) == "function" then
		local ok, value = pcall(round.isPractice)
		if ok then
			return value == true
		end
	end
	return GameState:GetAttribute("Practice") == true
end

local function opensAt(): number
	if isPractice() then
		return activeSince
	end
	return activeSince + (SK.LockedFirst or 45)
end

-- In a round the choice locked at the call wins (KitService sets RoundSpecialty / RoundGeneral then; Combat_v3 2.1);
-- in the train the next round's choice (LoadoutSpecialty / LoadoutGeneral) shows.
local function lockedOrChosen(player: Player, roundAttr: string, loadoutAttr: string): any
	if GameState:GetAttribute("Phase") == "Active" then
		local locked = player:GetAttribute(roundAttr)
		if type(locked) == "string" and locked ~= "" then
			return locked
		end
	end
	return player:GetAttribute(loadoutAttr)
end

local function specialtyOf(player: Player, st: SkillState): string?
	local chosen = st.specialty or lockedOrChosen(player, "RoundSpecialty", "LoadoutSpecialty")
	if type(chosen) == "string" and SK.Weapon[chosen] then
		return chosen
	end
	return nil
end

local function generalOf(player: Player, st: SkillState): string
	local chosen = st.general or lockedOrChosen(player, "RoundGeneral", "LoadoutGeneral")
	if type(chosen) == "string" and SK.General[chosen] then
		return chosen
	end
	return SK.DefaultGeneral or "concentration"
end

-- The family whose skill R does now: the held weapon's family when it is the Specialty (or when no Specialty is set,
-- or Specialty is off in Config), else nil (R is dim).
local function weaponFamilyFor(player: Player, st: SkillState): string?
	local combat = Services.CombatService
	local held = combat and combat.heldItem(player)
	local family = Moves.family(held)
	if held == nil then
		family = "Fists"
	end
	local specialty = specialtyOf(player, st)
	if SK.Specialty == false or specialty == nil or specialty == family then
		return family
	end
	return nil
end

local function publish(player: Player, st: SkillState)
	player:SetAttribute("SkillWeaponReadyAt", st.ready.weapon or 0)
	player:SetAttribute("SkillGeneralReadyAt", st.ready.general or 0)
	player:SetAttribute("SkillsOpenAt", opensAt())
	player:SetAttribute("SkillGeneral", generalOf(player, st))
	player:SetAttribute("SkillSpecialty", specialtyOf(player, st))
end

function SkillService.setLoadout(player: Player, specialty: string?, general: string?)
	local st = stateOf(player)
	st.specialty = if type(specialty) == "string" and SK.Weapon[specialty] then specialty else nil
	st.general = if type(general) == "string" and SK.General[general] then general else nil
	publish(player, st)
end

function SkillService.hasBuff(player: Player, id: string): boolean
	local st = states[player]
	return st ~= nil and now() < (st.buffs[id] or -math.huge)
end

function SkillService.consumeArmed(player: Player, id: string): boolean
	local st = states[player]
	if st and now() < (st.armed[id] or -math.huge) then
		st.armed[id] = nil
		player:SetAttribute("SkillArmed", nil)
		return true
	end
	return false
end

local function setBuff(player: Player, st: SkillState, id: string, seconds: number, attribute: string?)
	local untilAt = now() + seconds
	st.buffs[id] = untilAt
	if attribute then
		player:SetAttribute(attribute, untilAt)
	end
end

-- CombatService, on any accepted attack: Sprint Burst and Quiet Step end (Combat_v3 2.3 "Ends when you attack").
function SkillService.onAttack(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local t = now()
	for id, attribute in pairs({ sprint_burst = "SprintBurstUntil", quiet_step = "QuietStepUntil" }) do
		if t < (st.buffs[id] or -math.huge) then
			st.buffs[id] = t
			player:SetAttribute(attribute, t)
		end
	end
end

-- Bodies near a point, living, not the user, nearest first (one spatial query: the targets list, no physics).
local function bodiesNear(player: Player, center: Vector3, radius: number): { { model: Model, root: BasePart, d: number } }
	local combat = Services.CombatService
	local list = {}
	for _, model in ipairs(combat.getTargets(player.Character, true)) do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local d = Util.flat(root.Position - center).Magnitude
			if d <= radius and math.abs(root.Position.Y - center.Y) < 6 then
				table.insert(list, { model = model :: Model, root = root, d = d })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	return list
end

local function skillMove(id: string, damage: number, tier: string, knock: number): { [string]: any }
	return { id = id, kind = "Skill", damage = math.min(damage, 95), windup = 0, total = 0, tier = tier, knock = knock,
		stamina = 0 }
end

-- Running Cut: the lane from where the dash began, along the look, cut once per contender (Paired Blades twice).
local function runningCut(player: Player, start: Vector3, dir: Vector3, stats: any)
	local combat = Services.CombatService
	local S = SK.Weapon.Sword
	local ctx = combat.context(player)
	if not ctx then
		return
	end
	local length = S.Dash + 2
	local hits = 0
	for _, entry in ipairs(bodiesNear(player, start + dir * (length * 0.5), length * 0.5 + S.Lane)) do
		if hits >= S.MaxTargets then
			break
		end
		local offset = Util.flat(entry.root.Position - start)
		local along = offset:Dot(dir)
		local side = (offset - dir * along).Magnitude
		if along > -1 and along <= length and side <= S.Lane * 0.5 + 1.2 and combat.lineOfSight(start + Vector3.new(0, 1.5, 0), entry.model, ctx.character) then
			hits += 1
			local sideDir = Util.flat(offset - dir * along)
			local push = if sideDir.Magnitude > 0.1 then sideDir.Unit else dir:Cross(Vector3.yAxis)
			local cuts = if stats.id == "paired_blades" then 2 else 1
			for _ = 1, cuts do
				local move = skillMove("RunningCut", (stats.damage or 0) * S.Mult, "Stagger", S.Knockback)
				combat.resolveHit(player, entry.model, move, {
					damage = move.damage, position = entry.root.Position - dir * 2, hitPosition = entry.root.Position,
					weaponId = stats.id, attackerModel = ctx.character, knockDir = push, armourPierce = stats.armourPierce,
				})
			end
		end
	end
end

local function whirl(player: Player, stats: any)
	local combat = Services.CombatService
	local S = SK.Weapon.Axe
	local ctx = combat.context(player)
	if not ctx then
		return
	end
	local center = ctx.root.Position
	local hits = 0
	for _, entry in ipairs(bodiesNear(player, center, (stats.range or 5) + S.RadiusAdd)) do
		if hits >= S.MaxTargets then
			break
		end
		if combat.lineOfSight(ctx.head.Position, entry.model, ctx.character) then
			hits += 1
			local move = skillMove("Whirl", (stats.damage or 0) * S.Mult, "Stagger", S.Knockback)
			combat.resolveHit(player, entry.model, move, {
				damage = move.damage, position = center, hitPosition = entry.root.Position, weaponId = stats.id,
				attackerModel = ctx.character, armourPierce = stats.armourPierce,
			})
		end
	end
end

local function vaultKick(player: Player, dir: Vector3)
	local combat = Services.CombatService
	local S = SK.Weapon.Spear
	local ctx = combat.context(player)
	if not ctx then
		return
	end
	local center = ctx.root.Position
	local hits = 0
	for _, entry in ipairs(bodiesNear(player, center + dir * 1.5, S.Reach + 2)) do
		if hits >= 2 then
			break
		end
		local to = Util.flat(entry.root.Position - center)
		if (to.Magnitude < 1 or to.Unit:Dot(dir) > -0.2) and combat.lineOfSight(ctx.head.Position, entry.model, ctx.character) then
			hits += 1
			local move = skillMove("VaultKick", S.Damage, "Knockdown", S.Knockback)
			move.kind = "Kick" -- (both feet: it breaks a guard, as a kick does)
			local result = combat.resolveHit(player, entry.model, move, {
				damage = S.Damage, position = center, hitPosition = entry.root.Position, attackerModel = ctx.character,
				lift = S.Lift,
			})
			if result == "Blocked" then
				-- (a guard does not hold it: it still goes down)
				combat.react(player, entry.model, "Knockdown", { position = center, knock = S.Knockback, lift = S.Lift })
			end
		end
	end
end

local function secondWind(player: Player, st: SkillState, started: number)
	local S = SK.General.second_wind
	local combat = Services.CombatService
	local body = combat.bodyState(player.Character)
	if body then
		body.stamina = math.min(1, (body.stamina or 1) + S.Stamina)
	end
	local playerService = Services.PlayerService
	if not playerService or type(playerService.heal) ~= "function" then
		return
	end
	local steps = 4
	task.spawn(function()
		for _ = 1, steps do
			task.wait(S.HealTime / steps)
			local b = combat.bodyState(player.Character)
			-- a hit taken cancels the health part
			if not b or (b.interruptAt or -math.huge) > started or not player.Parent then
				return
			end
			pcall(playerService.heal, player, S.Heal / steps)
		end
	end)
end

local function broadcastSkill(player: Player, skill: string, dir: Vector3)
	local combat = Services.CombatService
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	combat.broadcastNear(if root and root:IsA("BasePart") then root.Position else nil,
		{ action = "Skill", userId = player.UserId, skill = skill, direction = dir }, player)
end

local function useSkill(player: Player, slot: any, clientTime: any, direction: any)
	if slot ~= "weapon" and slot ~= "general" then
		return
	end
	if not Net.rateLimit(player, "Skill", 2, 2) then
		return
	end
	local combat = Services.CombatService
	if not combat or not combat.canAct(player) then
		refuse(player, slot, "CantAct")
		return
	end
	local st = stateOf(player)
	local t = now()
	if t < opensAt() - JITTER then
		refuse(player, slot, "Locked")
		return
	end
	if t < (st.ready[slot] or -math.huge) - JITTER then
		refuse(player, slot, "Cooldown")
		return
	end
	local ctx = combat.context(player)
	local dir = if Util.isFiniteVector(direction) then Util.flat(direction :: Vector3) else Vector3.zero
	if dir.Magnitude < 0.1 then
		dir = Util.flat(ctx.root.CFrame.LookVector)
	end
	dir = dir.Unit
	local started = t
	if type(clientTime) == "number" and clientTime == clientTime then
		started = math.clamp(clientTime, t - JITTER, t)
	end

	local id: string
	local def: { [string]: any }
	if slot == "weapon" then
		local family = weaponFamilyFor(player, st)
		if not family then
			refuse(player, slot, "NotSpecialty")
			return
		end
		def = SK.Weapon[family]
		id = def.id
		local stats = combat.meleeStatsOf(player)
		if (family ~= "Throwing" and family ~= "Bow") and not stats then
			refuse(player, slot, "NoWeapon")
			return
		end
		if (def.Stamina or 0) > 0 and combat.staminaOf(player) < def.Stamina - 1e-3 then
			refuse(player, slot, "Stamina")
			return
		end
		combat.spendStamina(player, def.Stamina or 0)
		-- a moving skill holds the swing gate for its length (no light chain through it)
		local body = combat.bodyState(player.Character)
		if body and def.Total and family ~= "Throwing" and family ~= "Bow" then
			body.nextSwingStart = math.max(body.nextSwingStart or -math.huge, started + def.Total)
			body.guardOn = false
		end
		st.active = { id = id, start = started, struck = 0, dir = dir }
		if id == "running_cut" then
			local from = ctx.root.Position
			task.delay(math.max(0, started + def.Crouch + def.DashTime - now()), runningCut, player, from, dir, stats)
		elseif id == "whirl" then
			task.delay(math.max(0, started + def.Windup + def.Spin * 0.5 - now()), whirl, player, stats)
		elseif id == "vault_kick" then
			task.delay(math.max(0, started + def.HitAt - now()), vaultKick, player, dir)
		elseif id == "ricochet" or id == "piercing_shot" then
			st.armed[id] = t + def.Armed
			player:SetAttribute("SkillArmed", id)
			st.active = nil
		end
	else
		id = generalOf(player, st)
		def = SK.General[id]
		local body = combat.bodyState(player.Character)
		if id == "concentration" then
			setBuff(player, st, id, def.Time, "ConcentrationUntil")
			if body then
				body.concentrationUntil = st.buffs[id]
			end
		elseif id == "second_wind" then
			secondWind(player, st, started)
		elseif id == "sprint_burst" then
			setBuff(player, st, id, def.Time, "SprintBurstUntil")
		elseif id == "quiet_step" then
			setBuff(player, st, id, def.Time, "QuietStepUntil")
		elseif id == "steady_hands" then
			setBuff(player, st, id, def.Time, "SteadyHandsUntil")
		elseif id == "brace" then
			setBuff(player, st, id, def.Time, "BraceUntil")
			if body then
				body.braceUntil = st.buffs[id]
			end
		end
	end
	st.ready[slot] = started + (def.Cooldown or 30)
	publish(player, st)
	broadcastSkill(player, id, dir)
end

-- A skill strike sent as a MeleeSwing (CombatService.resolveMove): Head Kick ("HK") once, at its windup; the chained
-- strikes ("S1".."S5") in order, each at its own moment after the skill began. nil: refused.
function SkillService.strikeMove(player: Player, moveId: string, t: number, stats: any): { [string]: any }?
	local st = states[player]
	local active = st and st.active
	if not active then
		return nil
	end
	local body = Services.CombatService.bodyState(player.Character)
	if body and (body.interruptAt or -math.huge) > active.start then
		st.active = nil -- (a hit taken ends it)
		return nil
	end
	local since = t - active.start
	if moveId == "HK" and active.id == "head_kick" and active.struck == 0 then
		local S = SK.Weapon.Fists
		if since >= S.Windup - JITTER and since <= S.Windup + LATE + 0.3 then
			active.struck = 1
			return Moves.skillStrike(stats, stats and stats.id, "HK")
		end
		return nil
	end
	local n = tonumber(string.match(moveId, "^S(%d)$"))
	if n and active.id == "chained_strikes" and n == active.struck + 1 then
		local S = SK.Weapon.ShortBlade
		local at = S.First + (n - 1) * S.Gap
		if since >= at - JITTER and since <= at + LATE then
			active.struck = n
			if n >= #S.Mults then
				st.active = nil
			end
			return Moves.skillStrike(stats, stats and stats.id, moveId)
		end
	end
	return nil
end

function SkillService._use(player: Player, slot: string, direction: Vector3?)
	useSkill(player, slot, workspace:GetServerTimeNow(), direction)
end
SkillService._refusals = refusals
SkillService._state = function(player: Player)
	return states[player]
end

function SkillService.Init(registry)
	Services = registry
end

function SkillService.Start()
	Net.event("MeleeSwing").OnServerEvent:Connect(function(player: Player, mode: any, slot: any, clientTime: any, direction: any)
		if mode == "Skill" then
			local ok, err = pcall(useSkill, player, slot, clientTime, direction)
			if not ok then
				warn("[SkillService] " .. tostring(err))
			end
		end
	end)
	local function onPhase()
		if GameState:GetAttribute("Phase") == "Active" then
			activeSince = now()
			for player, st in pairs(states) do
				table.clear(st.ready)
				table.clear(st.armed)
				table.clear(st.buffs)
				st.active = nil
				publish(player, st)
			end
			for _, player in ipairs(Players:GetPlayers()) do
				publish(player, stateOf(player))
			end
		end
	end
	GameState:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	onPhase()
	Players.PlayerAdded:Connect(function(player)
		publish(player, stateOf(player))
		for _, attr in ipairs({ "LoadoutSpecialty", "LoadoutGeneral", "RoundSpecialty", "RoundGeneral" }) do
			player:GetAttributeChangedSignal(attr):Connect(function()
				publish(player, stateOf(player))
			end)
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		publish(player, stateOf(player))
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return SkillService
