-- MPT_Driver (mp-test): test-only server driver for a Studio multiplayer test started with
-- StudioTestService:ExecuteMultiplayerTestAsync(n, { suite = "mpt", batch = ... }). It is put into ServerScriptService
-- only while a test is being started and removed again; outside such a test (no test args, or not Studio) it does
-- nothing. Every line it prints starts with "[MPT]"; the bots' lines are relayed as "[MPT] C:<player> ...".
local RunService = game:GetService("RunService")
if not RunService:IsStudio() or not RunService:IsServer() then
	return
end
local STS = game:GetService("StudioTestService")
local okArgs, ARGS = pcall(function()
	return STS:GetTestArgs()
end)
if not okArgs or type(ARGS) ~= "table" or ARGS.suite ~= "mpt" then
	return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local CollectionService = game:GetService("CollectionService")

local seq = 0
local function now(): number
	return workspace:GetServerTimeNow() % 100000
end
local function L(s: string)
	seq += 1
	print(string.format("[MPT] %04d %.3f %s", seq, now(), s))
end
local function json(v: any): string
	local ok, res = pcall(HttpService.JSONEncode, HttpService, v)
	return if ok then res else "<json failed: " .. tostring(res) .. ">"
end
local function v3(v: Vector3): string
	return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
end
local function fmt(v: any, depth: number?): string
	local d = depth or 0
	local t = typeof(v)
	if t == "table" then
		if d > 4 then
			return "{...}"
		end
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local out = {}
		for _, k in ipairs(keys) do
			table.insert(out, tostring(k) .. "=" .. fmt(v[k], d + 1))
		end
		return "{" .. table.concat(out, ", ") .. "}"
	elseif t == "Vector3" then
		return v3(v)
	elseif t == "Instance" then
		return v.ClassName .. ":" .. v.Name
	elseif t == "number" then
		return if v % 1 == 0 then tostring(v) else string.format("%.3f", v)
	end
	return tostring(v)
end

L("driver starting: args=" .. json(ARGS) .. string.format(" uptime=%.1f", time()))

-- the session always ends by itself
local FAILSAFE = tonumber(ARGS.failsafe) or 330
local ended = false
local beforeEnd: (() -> ())? = nil -- (set further down: hands each test window its own render quality back)
local function endTest(summary: string)
	if ended then
		return
	end
	ended = true
	if beforeEnd then
		pcall(beforeEnd)
	end
	L("ENDTEST " .. summary)
	task.wait(1.5) -- let the last client lines arrive and the log flush
	pcall(function()
		STS:EndTest(summary)
	end)
end
task.delay(FAILSAFE, function()
	endTest("failsafe after " .. FAILSAFE .. " s")
end)

local serverLogs: { string } = {} -- every warning and error of this server (not the test's own lines)
LogService.MessageOut:Connect(function(message, kind)
	if kind ~= Enum.MessageType.MessageError and kind ~= Enum.MessageType.MessageWarning then
		return
	end
	if string.find(message, "[MPT]", 1, true) then
		return
	end
	local line = (if kind == Enum.MessageType.MessageError then "LOG-E " else "LOG-W ") .. string.sub((string.gsub(message, "\n", " | ")), 1, 400)
	table.insert(serverLogs, line)
	task.defer(L, line)
end)

local Shared = RS:WaitForChild("Shared")
local GS = RS:WaitForChild("GameState")
local Config = require(Shared:WaitForChild("Config"))
-- a real round needs two: before anything else, so the first client to load does not get a practice round
local MINP = tonumber(ARGS.minPlayers) or 2
-- held until the lobby has been looked at: no round and no practice round starts before release()
Config.Round.MinPlayers = 99
Config.Round.SoloPractice = false
local function release()
	Config.Round.SoloPractice = true
	Config.Round.MinPlayers = MINP
	GS:SetAttribute("MinPlayers", MINP)
	L("RELEASE MinPlayers=" .. MINP)
end
L("held: MinPlayers=99 SoloPractice=false; IntermissionTime=" .. tostring(Config.Round.IntermissionTime))
if ARGS.timeScale then
	Config.Round.StudioTimeScale = ARGS.timeScale
end
if ARGS.border then
	-- a small ring, so that "outside the border" is a few steps from the plates (the damage path is the game's own)
	Config.Border.MinStartRadius = ARGS.border
	Config.Border.StartRadius = ARGS.border
end
if ARGS.cut then
	GS:SetAttribute("LaunchCutTest", ARGS.cut)
end
-- the live respawn wait (Studio's fast timers use 2 s, which takes a defeated body away 0.2 s into its fade)
Config.Round.RespawnDelay = tonumber(ARGS.respawn) or 4
if ARGS.intermission then
	Config.Round.IntermissionTime = tonumber(ARGS.intermission) or Config.Round.IntermissionTime
end
if ARGS.fill then
	GS:SetAttribute("FillTest", 1) -- (Studio only: turns RoundService's fill rule on, as on a live public server)
end
L("RespawnDelay=" .. tostring(Config.Round.RespawnDelay) .. " IntermissionTime=" .. tostring(Config.Round.IntermissionTime))

local function req(parent: Instance, name: string): any
	local m = parent:WaitForChild(name, 30)
	if not m then
		L("REQUIRE no module " .. name)
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok then
		L("REQUIRE FAIL " .. name .. ": " .. tostring(res))
		return nil
	end
	return res
end
local Services = SSS:WaitForChild("Server"):WaitForChild("Services")
local Net = req(Shared, "Net")
local ItemDefs = req(Shared, "ItemDefs")
local Inv = req(Services, "InventoryService")
local Combat = req(Services, "CombatService")
local PS = req(Services, "PlayerService")
local Round = req(Services, "RoundService")
local Arena = req(Services, "ArenaService")
local Loot = req(Services, "LootService")
local Data = req(Services, "DataService")
-- the weapons build (19 Nov, mp-weapons)
local Stars = req(Shared, "Stars")
local Kits = req(Shared, "Kits")
local KitSvc = req(Services, "KitService")
local RewardsSvc = req(Services, "RewardsService")
local Currency = req(Services, "CurrencyService")
local Projectiles = SSS.Server.Services:FindFirstChild("ProjectileService") and req(Services, "ProjectileService")
-- a melee weapon's damage at its stars (Shared.Stars: the game's own numbers)
local function dmgOf(id: string, stars: number?): number
	local d = Stars and Stars.def(id, stars or 1) or ItemDefs.get(id)
	return if d and d.damage then d.damage else 0
end
-- a stand-in DataStore (DataStores are off in Studio): every save of this test server goes here, so Gold, the Armoury
-- and the daily bonuses really load and save (DataService.testRejoin reads it back)
local fakeData: { [string]: any } = {}
local fakeWrites = 0
local function deep(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = deep(v)
	end
	return c
end
local fakeStore: any = nil
if ARGS.batch == "W" or ARGS.fakeStore then
	local fake = {}
	fakeStore = fake
	function fake:GetAsync(k)
		return deep(fakeData[k])
	end
	function fake:UpdateAsync(k, fn)
		local new = fn(deep(fakeData[k]))
		if new ~= nil then
			fakeData[k] = deep(new)
			fakeWrites += 1
		end
		return deep(new)
	end
	function fake:SetAsync(k, v)
		fakeData[k] = deep(v)
		fakeWrites += 1
	end
	L("FAKESTORE installed=" .. tostring(Data and Data.useTestStore(fake)))
end
-- every projectile the server fires: where from, how fast, what gravity (the bow checks rebuild its arc from this)
local fires: { { t: number, shooter: string, item: string, origin: Vector3, velocity: Vector3, gravity: number, damage: number, opts: any } } = {}
if Projectiles and type(Projectiles.fire) == "function" then
	local origFire = Projectiles.fire
	Projectiles.fire = function(shooter, itemId, origin, velocity, gravity, damage, opts, ...)
		local id = origFire(shooter, itemId, origin, velocity, gravity, damage, opts, ...)
		if id and typeof(origin) == "Vector3" and typeof(velocity) == "Vector3" then
			table.insert(fires, { t = os.clock(), shooter = if shooter then shooter.Name else "?", item = tostring(itemId), origin = origin, velocity = velocity,
				gravity = tonumber(gravity) or 0, damage = tonumber(damage) or 0, opts = opts })
			L(string.format("FIRED %s %s origin=%s vel=%s speed=%.1f g=%.1f dmg=%.2f onTarget=%s headCap=%s stars=%s pierce=%s", if shooter then shooter.Name else "?",
				tostring(itemId), v3(origin), v3(velocity), velocity.Magnitude, tonumber(gravity) or 0, tonumber(damage) or 0, tostring(opts and opts.onTarget),
				tostring(opts and opts.headCap), tostring(opts and opts.recoverStars), tostring(opts and opts.armourPierce)))
		end
		return id
	end
end

-- remotes for the bots ---------------------------------------------------------------------------------------------------
local callFn = Instance.new("RemoteFunction")
callFn.Name = "MPT_Call"
callFn.Parent = RS
local repEv = Instance.new("RemoteEvent")
repEv.Name = "MPT_Rep"
repEv.Parent = RS
local botReady: { [Player]: boolean } = {}
local clientLines: { [string]: { string } } = {} -- per player name, every line the bot sent (for searching)
repEv.OnServerEvent:Connect(function(p, text)
	if type(text) ~= "string" then
		return
	end
	if text == "\0READY" then
		botReady[p] = true
		L("BOT READY " .. p.Name)
		return
	end
	local store = clientLines[p.Name]
	if not store then
		store = {}
		clientLines[p.Name] = store
	end
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(store, line)
		seq += 1
		print(string.format("[MPT] %04d C:%s %s", seq, p.Name, line))
	end
end)

local botTemplate = script:FindFirstChild("MPT_Bot")
local function giveBot(p: Player)
	local gui = p:WaitForChild("PlayerGui", 20)
	if not (gui and botTemplate) then
		L("BOT cannot be given to " .. p.Name)
		return
	end
	local holder = Instance.new("ScreenGui")
	holder.Name = "MPT"
	holder.ResetOnSpawn = false
	holder.Enabled = false
	local copy = botTemplate:Clone()
	copy.Disabled = false
	copy.Parent = holder
	holder.Parent = gui
end

-- calls a bot; never waits longer than `timeout`
local function call(p: Player?, cmd: string, arg: any, timeout: number?): any
	if not (p and p.Parent == Players) then
		return nil
	end
	local done, result = false, nil
	task.spawn(function()
		local ok, res = pcall(function()
			return callFn:InvokeClient(p, cmd, arg)
		end)
		result = if ok then res else { error = tostring(res) }
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < (timeout or 8) do
		task.wait(0.03)
	end
	if not done then
		L("CALL " .. cmd .. " to " .. p.Name .. " timed out")
		return nil
	end
	return result
end

-- server truth, logged as it happens ---------------------------------------------------------------------------------------
local CORE = { "Phase", "LobbyCount", "AliveCount", "StartedCount", "Practice", "WinnerName", "WinnerUserId", "RoundId", "LaunchCut",
	"BorderStartRadius", "SoloStartAt", "PrivateServer", "ArenaEvent" }
for _, n in ipairs(CORE) do
	GS:GetAttributeChangedSignal(n):Connect(function()
		L("GS " .. n .. "=" .. tostring(GS:GetAttribute(n)))
	end)
end
GS:GetAttributeChangedSignal("RollCall"):Connect(function()
	L("GS RollCall=" .. string.sub(tostring(GS:GetAttribute("RollCall")), 1, 700))
end)
GS:GetAttributeChangedSignal("PhaseEndsAt"):Connect(function()
	local e = tonumber(GS:GetAttribute("PhaseEndsAt")) or 0
	L(string.format("GS PhaseEndsAt in %.1f s", if e > 0 then e - workspace:GetServerTimeNow() else -1))
end)

local WATCH = { "Alive", "InArena", "Frozen", "Kills", "Placement", "KilledBy", "Wins", "RoundsPlayed", "TotalKills", "Launched", "UsingItem",
	"NewPlayer", "Armor" }
local hpLog: { [string]: { { t: number, from: number, to: number } } } = {}
local function hookPlayer(p: Player)
	L(string.format("PLAYER+ %s userId=%d display=%s", p.Name, p.UserId, p.DisplayName))
	for _, n in ipairs(WATCH) do
		p:GetAttributeChangedSignal(n):Connect(function()
			L("PA " .. p.Name .. "." .. n .. "=" .. tostring(p:GetAttribute(n)))
		end)
	end
	local function onChar(c: Model)
		L("CHAR+ " .. p.Name)
		task.spawn(function()
			local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
			if not hum then
				return
			end
			local last = hum.Health
			hum.HealthChanged:Connect(function(h)
				if math.abs(h - last) >= 0.5 then
					L(string.format("HP %s %.1f -> %.1f", p.Name, last, h))
					local list = hpLog[p.Name] or {}
					hpLog[p.Name] = list
					table.insert(list, { t = now(), from = last, to = h })
					last = h
				end
			end)
		end)
		for _, n in ipairs({ "Stance", "EquippedItem" }) do
			c:GetAttributeChangedSignal(n):Connect(function()
				L("CA " .. p.Name .. "." .. n .. "=" .. tostring(c:GetAttribute(n)))
			end)
		end
	end
	p.CharacterAdded:Connect(onChar)
	p.CharacterRemoving:Connect(function()
		L("CHAR- " .. p.Name)
	end)
	if p.Character then
		onChar(p.Character)
	end
	p:GetPropertyChangedSignal("ReplicationFocus"):Connect(function()
		L("FOCUS " .. p.Name .. " = " .. (if p.ReplicationFocus then p.ReplicationFocus:GetFullName() else "nil"))
	end)
	task.spawn(giveBot, p)
end
Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(p)
	botReady[p] = nil
	L("PLAYER- " .. p.Name)
end)
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end

local diedAt: { [string]: number } = {} -- os.clock() of each player's last death
local hitsBy: { [string]: number } = {} -- hits the server applied, per attacker
local claimsBy: { [string]: number } = {} -- strikes a client sent with "my screen shows a hit", per attacker
local maxDealt = { n = 0, what = "none" } -- the biggest single hit a player dealt in this test
if PS and PS.died then
	PS.died:Connect(function(victim, killer, cause)
		diedAt[victim.Name] = os.clock()
		L(string.format("SIGNAL died victim=%s killer=%s cause=%s", victim.Name, if killer then killer.Name else "nil", tostring(cause)))
	end)
end
local function contenderNames(): string
	local names = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if Round.isContender(p) then
			table.insert(names, p.Name)
		end
	end
	table.sort(names)
	return table.concat(names, "+")
end
if Round then
	Round.phaseChanged:Connect(function(new, old)
		L(string.format("SIGNAL phase %s -> %s practice=%s roundId=%s contenders=%s", tostring(old), tostring(new), tostring(Round.isPractice()),
			tostring(Round.getRoundId()), contenderNames()))
	end)
	Round.roundEnded:Connect(function(winner)
		L("SIGNAL roundEnded winner=" .. (if winner then winner.Name else "nil"))
	end)
end
if Combat and type(Combat.applyHit) == "function" then
	local orig = Combat.applyHit
	Combat.applyHit = function(attacker, humanoid, base, info)
		local isHum = typeof(humanoid) == "Instance"
		local before = if isHum then humanoid.Health else -1
		local dealt, killed = orig(attacker, humanoid, base, info)
		if attacker and (tonumber(dealt) or 0) > 0 then
			hitsBy[attacker.Name] = (hitsBy[attacker.Name] or 0) + 1
			if (tonumber(dealt) or 0) > maxDealt.n then
				maxDealt.n, maxDealt.what = tonumber(dealt) or 0, string.format("%s weapon=%s base=%s headshot=%s", attacker.Name, tostring(info and info.weaponId),
					tostring(base), tostring(info and info.headshot))
			end
		end
		L(string.format("APPLYHIT %s -> %s base=%s dealt=%s killed=%s weapon=%s melee=%s headshot=%s hp %.1f -> %.1f", if attacker then attacker.Name else "nil",
			if isHum and humanoid.Parent then humanoid.Parent.Name else "?", tostring(base), tostring(dealt), tostring(killed),
			tostring(info and info.weaponId), tostring(info and info.melee), tostring(info and info.headshot), before, if isHum then humanoid.Health else -1))
		return dealt, killed
	end
end
if Net then
	Net.event("MeleeSwing").OnServerEvent:Connect(function(p, a, predicted, variant, target, startTime)
		if predicted == true then
			claimsBy[p.Name] = (claimsBy[p.Name] or 0) + 1
		end
		L(string.format("RECV MeleeSwing from=%s a=%s predicted=%s variant=%s target=%s startAgo=%s", p.Name,
			if typeof(a) == "Vector3" then "dir" else tostring(a), tostring(predicted), tostring(variant),
			if typeof(target) == "Instance" then target.Name else tostring(target),
			if type(startTime) == "number" then string.format("%.3f", workspace:GetServerTimeNow() - startTime) else "nil"))
	end)
	Net.event("RangedRelease").OnServerEvent:Connect(function(p, _id, _origin, _dir, charge, mode)
		L(string.format("RECV RangedRelease from=%s mode=%s charge=%s", p.Name, tostring(mode), tostring(charge)))
	end)
	Net.event("SpectateTarget").OnServerEvent:Connect(function(p, target)
		L(string.format("RECV SpectateTarget from=%s target=%s", p.Name, if typeof(target) == "Instance" then target.Name else tostring(target)))
	end)
	for _, n in ipairs({ "UseStart", "UseFinish", "UseCancel", "Drink", "TakeWorldItem", "EquipSlot" }) do
		Net.event(n).OnServerEvent:Connect(function(p, a)
			L(string.format("RECV %s from=%s arg=%s", n, p.Name, tostring(a)))
		end)
	end
end

-- helpers ---------------------------------------------------------------------------------------------------------------
local results: { string } = {}
local function check(id: string, pass: boolean?, detail: string)
	local verdict = if pass == true then "PASS" elseif pass == false then "FAIL" else "NOTE"
	local line = string.format("[CHECK] %s %s %s", id, verdict, detail)
	table.insert(results, id .. "=" .. verdict)
	L(line)
end
local function waitFor(cond: () -> any, timeout: number): any
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local v = cond()
		if v then
			return v
		end
		task.wait(0.05)
	end
	return nil
end
local function phase(): string
	return tostring(GS:GetAttribute("Phase"))
end
local function waitPhase(name: string, timeout: number): boolean
	return waitFor(function()
		return phase() == name
	end, timeout) ~= nil
end
local function parts(p: Player?): (Humanoid?, BasePart?)
	local c = p and p.Character
	if not c then
		return nil, nil
	end
	return c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart") :: any
end
local function arenaCenter(): Vector3
	local arena = workspace:FindFirstChild("Arena")
	local c = arena and arena:GetAttribute("Center")
	return if typeof(c) == "Vector3" then c else Vector3.zero
end
local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function groundAt(x: number, yFrom: number, z: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, yFrom + 40, z), Vector3.new(0, -160, 0), params)
	return if hit then hit.Position else nil
end
-- stands p on the ground at (x, z), facing `lookAt`
local function standAt(p: Player, x: number, z: number, lookAt: Vector3?, yHint: number?): Vector3?
	local hum, root = parts(p)
	if not (hum and root and p.Character) then
		return nil
	end
	local g = groundAt(x, yHint or root.Position.Y, z)
	local y = (if g then g.Y else root.Position.Y - hum.HipHeight - root.Size.Y / 2) + hum.HipHeight + root.Size.Y / 2 + 0.1
	local pos = Vector3.new(x, y, z)
	root.AssemblyLinearVelocity = Vector3.zero
	local target = if lookAt then Vector3.new(lookAt.X, y, lookAt.Z) else pos + root.CFrame.LookVector
	if (target - pos).Magnitude < 0.05 then
		target = pos + Vector3.new(0, 0, -1)
	end
	p.Character:PivotTo(CFrame.lookAt(pos, target))
	return pos
end
-- a flat duel line: A at `base`, B `dist` studs (flat, root to root) further along `dir`; they face each other
local duelBase: Vector3? = nil
local duelDir: Vector3 = Vector3.new(1, 0, 0)
local function duel(a: Player, b: Player, dist: number): string
	if not duelBase then
		return "no duel base"
	end
	local pb = duelBase + duelDir * dist
	local posA = standAt(a, duelBase.X, duelBase.Z, pb, duelBase.Y)
	local posB = standAt(b, pb.X, pb.Z, duelBase, duelBase.Y)
	task.wait(0.6)
	local _, ra = parts(a)
	local _, rb = parts(b)
	if not (ra and rb and posA and posB) then
		return "duel: a character is missing"
	end
	return string.format("A at %s B at %s flat=%.2f dy=%.2f", v3(ra.Position), v3(rb.Position), flatDist(ra.Position, rb.Position), rb.Position.Y - ra.Position.Y)
end
local function setHealth(p: Player, h: number?)
	local hum = parts(p)
	if hum and hum.Health > 0 then
		hum.Health = h or hum.MaxHealth
	end
end
local function health(p: Player): number
	local hum = parts(p)
	return if hum then hum.Health else -1
end
local function slotOf(p: Player, itemId: string): number?
	local snap = Inv.getSnapshot(p)
	for i, s in ipairs(snap.slots) do
		if type(s) == "table" and s.id == itemId then
			return i
		end
	end
	return nil
end
local function invLine(p: Player): string
	local snap = Inv.getSnapshot(p)
	local out = {}
	for i, s in ipairs(snap.slots) do
		if type(s) == "table" then
			table.insert(out, string.format("%d:%sx%s", i, tostring(s.id), tostring(s.count)))
		end
	end
	return table.concat(out, " ") .. " equipped=" .. tostring(snap.equipped) .. " armor=" .. tostring(snap.armor)
end
-- lines a bot sent since index `from` that contain `pattern` (plain)
local function clientFind(p: Player, pattern: string, from: number?): (string?, number?)
	local store = clientLines[p.Name]
	if not store then
		return nil, nil
	end
	for i = (from or 0) + 1, #store do
		if string.find(store[i], pattern, 1, true) then
			return store[i], tonumber(string.match(store[i], "^([%d%.]+)"))
		end
	end
	return nil, nil
end
local function mark(p: Player): number
	local store = clientLines[p.Name]
	return if store then #store else 0
end
local function refusals(): string
	local out = {}
	for reason, count in pairs((Combat and Combat._refusals) or {}) do
		table.insert(out, tostring(reason) .. "=" .. tostring(count))
	end
	table.sort(out)
	return if #out > 0 then table.concat(out, " ") else "none"
end
local function guiHas(p: Player, needle: string): (boolean, string)
	local list = call(p, "gui", needle)
	if type(list) ~= "table" then
		return false, "no gui reply"
	end
	return #list > 0, table.concat(list, " ; ")
end

local A: Player, B: Player
local P3: Player? = nil
local EXPECT = math.max(2, tonumber(ARGS.clients) or 2)

-- one attack by A on B: returns what every side saw
local function attack(label: string, steps: { any }, settle: number?): { [string]: any }
	local mA, mB = mark(A), mark(B)
	local hpBefore = health(B)
	local hpCount = #(hpLog[B.Name] or {})
	local t0 = now()
	call(A, "seq", steps, 20)
	task.wait(settle or 1.2)
	local hp = hpLog[B.Name] or {}
	local drop = hp[hpCount + 1]
	local _, tConfirm = clientFind(A, "REMOTE HitConfirm", mA)
	local strikeLine, tStrike = clientFind(A, "ACT Strike", mA)
	local _, tSwingA = clientFind(A, "ACT Swing", mA)
	local actLine, tAct = clientFind(B, "REMOTE CombatAction", mB)
	local _, tSeeSwing = clientFind(B, "SEE-SWING " .. A.Name, mB)
	local dmgLine, tDmg = clientFind(B, "REMOTE DamageTaken", mB)
	local _, tSeeHp = clientFind(A, "SEE-HP " .. B.Name, mA)
	local r = {
		label = label, hpBefore = hpBefore, hpAfter = health(B), dealt = hpBefore - health(B), tServerDrop = drop and drop.t,
		tSwingA = tSwingA, tStrike = tStrike, strike = strikeLine, tConfirm = tConfirm, tAct = tAct, act = actLine, tSeeSwing = tSeeSwing,
		tDmg = tDmg, dmg = dmgLine, tSeeHp = tSeeHp, t0 = t0,
	}
	local function rel(t: number?): string
		return if t then string.format("%+.3f", t - t0) else "none"
	end
	L(string.format("ATTACK %s: hp %.1f -> %.1f | A swing %s strike %s (%s) confirm %s seesHp %s | server drop %s | B combatAction %s seesSwing %s damageTaken %s | refusals %s",
		label, hpBefore, r.hpAfter, rel(tSwingA), rel(tStrike), tostring(strikeLine and string.match(strikeLine, "hit=%S+")), rel(tConfirm), rel(tSeeHp),
		rel(r.tServerDrop), rel(tAct), rel(tSeeSwing), rel(tDmg), refusals()))
	return r
end

local function snapshotAll(tag: string)
	for _, p in ipairs(Players:GetPlayers()) do
		local hum, root = parts(p)
		L(string.format("STATE[%s] server %s contender=%s alive=%s inArena=%s frozen=%s hp=%.1f pos=%s inv=%s", tag, p.Name, tostring(Round.isContender(p)),
			tostring(p:GetAttribute("Alive")), tostring(p:GetAttribute("InArena")), tostring(p:GetAttribute("Frozen")), if hum then hum.Health else -1,
			if root then v3(root.Position) else "none", invLine(p)))
		local st = call(p, "state")
		L(string.format("STATE[%s] client %s %s", tag, p.Name, fmt(st)))
		local see = call(p, "see")
		L(string.format("SEE[%s] client %s sees %s", tag, p.Name, fmt(see)))
	end
end

local function shot(name: string, hold: number?)
	L("SHOT " .. name)
	task.wait(hold or 1.6)
end

-- the re-test of 18 November (second round) ------------------------------------------------------------------------------
-- Roblox's chat window is closed on each of `players` (and chat itself is switched on when `needCore`)
local function chatCheck(id: string, players: { Player }, needCore: boolean)
	local ok, detail = true, {}
	for _, p in ipairs(players) do
		if p.Parent == Players then
			local c = call(p, "chat") or {}
			ok = ok and c.active == false and (not needCore or c.coreEnabled == true)
			table.insert(detail, string.format("%s: chat window open=%s, chat switched on=%s, window x=%s width=%s scale=%s, lobby line shown=%s at x=%s, screen %s wide",
				p.Name, tostring(c.active), tostring(c.coreEnabled), fmt(c.winX), fmt(c.winW), fmt(c.widthScale), tostring(c.lineShown), fmt(c.lineX), fmt(c.view)))
		end
	end
	check(id, ok, table.concat(detail, " | "))
end

-- the PLUS member mark (PlusController), through the Studio switch Workspace.PlusTestMember
local PLUS = ARGS.plus ~= false
local function markOn(t: any, of: Player): boolean
	local s = type(t) == "table" and t[of.Name]
	return type(s) == "string" and string.find(s, "enabled=true", 1, true) ~= nil and string.find(s, of.Name .. ".Head", 1, true) ~= nil
end
local function anyMark(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	for _, s in pairs(t) do
		if type(s) == "string" and string.find(s, "enabled=true", 1, true) then
			return true
		end
	end
	return false
end
local function plusLobbyChecks(a: Player, b: Player)
	if not PLUS then
		return
	end
	call(a, "face", b.Name)
	call(b, "face", a.Name)
	workspace:SetAttribute("PlusTestMember", true)
	task.wait(1.8)
	local pa, pb = call(a, "plus") or {}, call(b, "plus") or {}
	check("plus.markInLobby", markOn(pb, a) and markOn(pa, b), string.format(
		"every player a test member, both in the lobby: %s's client has %s | %s's client has %s", a.Name, fmt(pa), b.Name, fmt(pb)))
	shot("plus_lobby", 1.2)
	workspace:SetAttribute("PlusTestMember", false)
	task.wait(1.8)
	pa, pb = call(a, "plus") or {}, call(b, "plus") or {}
	check("plus.noMarkForNonMember", not anyMark(pa) and not anyMark(pb), string.format("nobody a member: %s's client has %s | %s's client has %s", a.Name, fmt(pa),
		b.Name, fmt(pb)))
	workspace:SetAttribute("PlusTestMember", true)
	task.wait(0.8)
end
local function plusOffCheck(id: string, viewers: { Player }, why: string)
	if not PLUS then
		return
	end
	local ok, detail = true, {}
	for _, p in ipairs(viewers) do
		if p.Parent == Players then
			local t = call(p, "plus") or {}
			ok = ok and not anyMark(t)
			table.insert(detail, p.Name .. "'s client: " .. fmt(t))
		end
	end
	check(id, ok, why .. " (every player a test member): " .. table.concat(detail, " | "))
end

-- the round's HUD against the cards
local function hudOf(p: Player): (any, string)
	local h = call(p, "hud") or {}
	return h, string.format(
		"card up=%s, Take/Open prompts switched on=%s (%s in reach), hotbar=%s, vitals=%s, compass block=%s, kill feed=%s, at the screen centre: [%s], screen edges: %s",
		tostring(h.card), tostring(h.pps), tostring(h.promptsInReach), tostring(h.Hotbar), tostring(h.Vitals), tostring(h.Top), tostring(h.KillFeed), tostring(h.centre),
		tostring(h.edges))
end
local function hudHidden(h: any): boolean
	return h.card == true and h.pps == false and h.Hotbar == false and h.Vitals == false and h.Top == false
		and string.find(tostring(h.centre), "Crosshair", 1, true) == nil
end

-- what a client was sent to play since `from`
local function sfxSince(p: Player, from: number): string
	local store = clientLines[p.Name] or {}
	local seen, out = {}, {}
	for i = from + 1, #store do
		local key = string.match(store[i], "REMOTE Sfx (%S+)")
		if key and not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	return table.concat(out, ",")
end

-- red on a client's screen since `from` (the bots sample after every hurt, hit, death and kill feed line)
local function redCheck(id: string, p: Player, from: number)
	local store = clientLines[p.Name] or {}
	local fxRed, other, edges = {}, {}, {}
	local samples = 0
	for i = from + 1, #store do
		local n, rest = string.match(store[i], "RED%[.-%] n=(%d+) (.*)$")
		if n then
			samples += 1
			local list, e = string.match(rest, "^(.-) | edges: (.*)$")
			if e and e ~= "none showing" then
				edges[(string.gsub(e, " strength=[%d%.]+", ""))] = true
			end
			if (tonumber(n) or 0) > 0 and list then
				for item in string.gmatch(list, "[^;]+") do
					local s = string.gsub(string.gsub(item, "^%s+", ""), "%s+$", "")
					if string.sub(s, 1, 6) == "HUDFX/" then
						fxRed[s] = true
					elseif s ~= "" then
						other[s] = true
					end
				end
			end
		end
	end
	local function keys(t: { [string]: boolean }): string
		local out = {}
		for k in pairs(t) do
			table.insert(out, k)
		end
		table.sort(out)
		return if #out > 0 then table.concat(out, " ; ") else "none"
	end
	check(id, if samples == 0 then nil else next(fxRed) == nil, string.format(
		"%s's screen, %d samples after hits, hurts, the death and the kill feed line: red in the hit effects layer (HUDFX): %s | screen edges seen: %s | other red on screen: %s",
		p.Name, samples, keys(fxRed), keys(edges), keys(other)))
end

-- a defeated body on each viewer's screen, from the BODY lines the bots log by themselves. viewers: { role, player, mark }
local function defeatChecks(tag: string, victim: Player, viewers: { { any } })
	for _, v in ipairs(viewers) do
		local role, p, from = v[1] :: string, v[2] :: Player, v[3] :: number
		local store = clientLines[p.Name] or {}
		local rows, brief = {}, {}
		for i = from + 1, #store do
			local at, rest = string.match(store[i], "BODY " .. victim.Name .. " %+([%d%.]+) (.*)$")
			if at then
				local r = {
					at = tonumber(at) or 0, inWorld = string.find(rest, "inWorld=true", 1, true) ~= nil,
					eff = tonumber(string.match(rest, "eff=(%d+%.%d+)")) or -1, upY = tonumber(string.match(rest, "upY=(%-?%d+%.%d+)")) or 9,
					spread = tonumber(string.match(rest, "spread=(%d+%.%d+)")) or 99, joints = string.match(rest, "joints=(%S+)") or "?",
					collide = tonumber(string.match(rest, "collide=(%d+)")) or -1,
					playing = string.match(rest, "playing=%[(.-)%]$") or "", died = string.match(rest, "diedSound=%[(.-)%]") or "",
				}
				table.insert(rows, r)
				table.insert(brief, string.format("+%.1fs %s, up %.2f, farthest part %.1f studs from the chest, %d solid parts", r.at, if not r.inWorld then "removed"
					elseif r.eff >= 0.99 then "invisible" elseif r.eff <= 0.05 then "fully drawn" else string.format("%.0f%% faded", r.eff * 100), r.upY, r.spread,
					r.collide))
			end
		end
		local first = rows[1]
		local whole, toppled, solidEarly, fading, gone, quiet = first ~= nil and first.spread < 4.5, false, false, false, #rows > 0, true
		local goneAt: number? = nil
		for _, r in ipairs(rows) do
			local isGone = (not r.inWorld) or r.eff >= 0.99
			if r.at <= 2.75 and r.inWorld and first and r.spread > first.spread + 1.0 then
				whole = false -- (a limb has left the body)
			end
			if r.at >= 0.6 and r.at <= 1.95 and math.abs(r.upY) < 0.5 then
				toppled = true
			end
			if r.at <= 1.75 and r.inWorld and r.eff <= 0.05 then
				solidEarly = true
			end
			if r.at >= 1.85 and r.at <= 2.95 and r.inWorld and r.eff > 0.05 and r.eff < 0.99 then
				fading = true
			end
			if r.at >= 3.25 and not isGone then
				gone = false
			end
			if isGone and not goneAt then
				goneAt = r.at
			end
			if r.playing ~= "" or (r.died ~= "none" and string.find(r.died, "vol=0.00", 1, true) == nil) then
				quiet = false
			end
		end
		gone = gone and #rows > 0 and rows[#rows].at >= 3.25
		local pass = if role == "victim" then whole and gone and quiet else whole and toppled and solidEarly and fading and gone and quiet
		check(string.format("%s.defeat.%s", tag, role), if #rows == 0 then false else pass, string.format(
			"%s's body on %s's screen (joints at the fall, Motor6D/AnimationConstraint/BallSocket: %s): one piece=%s, topples=%s, fully drawn while falling=%s, seen part-faded between 1.9 and 2.9 s=%s, gone from 3.3 s=%s (first gone at %s), no voice or body sound=%s; samples: %s ; sounds the server sent this client meanwhile: [%s]",
			victim.Name, p.Name, if first then first.joints else "?", tostring(whole), tostring(toppled), tostring(solidEarly), tostring(fading), tostring(gone), if goneAt then string.format("%.1f s", goneAt) else "never",
			tostring(quiet), table.concat(brief, " / "), sfxSince(p, from)))
		redCheck(string.format("%s.noRedEffect.%s", tag, role), p, from)
	end
end

-- the Roll Call's sky show, held at the moment its figure is assembled (Studio's DevRecapFreeze), on each screen
local function recapShots(id: string, shotName: string, players: { Player }, alsoLog: { Player }?)
	GS:SetAttribute("DevRecapFreeze", 11.5)
	task.wait(1.6)
	for _, p in ipairs(players) do
		if p.Parent == Players then
			call(p, "recap", { face = true, seconds = 8 })
		end
	end
	task.wait(1.4)
	local ok, detail = true, {}
	for _, p in ipairs(players) do
		if p.Parent == Players then
			local r = call(p, "recap", {}) or {}
			ok = ok and r.showing == true and (tonumber(r.lit) or 0) >= 150 and r.onScreen == true
			table.insert(detail, string.format(
				"%s: show running=%s, %s of %s points lit (%s fully opaque, each %s studs across), their centre on screen=%s at %s, %s degrees up, bearing %s, figures stored: [%s]",
				p.Name, tostring(r.showing), tostring(r.lit), tostring(r.points), tostring(r.solid), fmt(r.pointSize), tostring(r.onScreen), tostring(r.screen),
				fmt(r.elevation), fmt(r.bearing), tostring(r.snapshots)))
		end
	end
	for _, p in ipairs(alsoLog or {}) do
		if p.Parent == Players then
			L("RECAP also " .. p.Name .. ": " .. fmt(call(p, "recap", {})))
		end
	end
	check(id, ok, "the sky show held at 11.5 s of its timeline (the fallen's figure assembled): " .. table.concat(detail, " | "))
	shot(shotName, 2.0)
	-- test only, for one more picture: the lit points three times their size, where the game put them (an unfocused
	-- Studio window draws at its lowest quality, which leaves out parts this small and far)
	for _, p in ipairs(players) do
		if p.Parent == Players then
			call(p, "recap", { enlarge = 3 })
		end
	end
	task.wait(0.8)
	shot(shotName .. "_x3", 1.6)
	for _, p in ipairs(players) do
		if p.Parent == Players then
			call(p, "recap", { restore = true })
		end
	end
	GS:SetAttribute("DevRecapFreeze", nil)
end

-- every warning and error of the server and of each client (the bots relay theirs)
local function logChecks()
	local fallen, others = {}, {}
	for _, l in ipairs(serverLogs) do
		if string.find(l, "FallenSnapshots", 1, true) then
			table.insert(fallen, l)
		else
			table.insert(others, string.sub(l, 1, 160))
		end
	end
	check("log.noFallenSnapshotsWarning", #fallen == 0, #fallen .. " server warnings naming FallenSnapshots: " .. table.concat(fallen, " ; "))
	check("log.server", nil, #others .. " other server warnings or errors: " .. string.sub(table.concat(others, " ; "), 1, 1200))
	local total, list = 0, {}
	for name, store in pairs(clientLines) do
		for _, line in ipairs(store) do
			if string.find(line, " LOG-E ", 1, true) or string.find(line, " LOG-W ", 1, true) then
				total += 1
				if #list < 12 then
					table.insert(list, name .. ": " .. string.sub(line, 1, 170))
				end
			end
		end
	end
	check("log.clients", nil, total .. " client warnings or errors relayed: " .. table.concat(list, " ; "))
end

-- the evening build (mp-retest2) -------------------------------------------------------------------------------------------
local SKIP_BY: { [string]: Player } = {} -- round tag -> the contender who skips their intro in that round
-- the border wall on each screen: blue, where the server says, fully open at the start (1,800) or past its first stage
local function borderLook(tag: string, players: { Player }, moving: boolean)
	local sr = tonumber(GS:GetAttribute("BorderRadius")) or -1
	local ok = if moving then sr < 1795 and (tonumber(GS:GetAttribute("BorderStage")) or 0) >= 1
		else sr >= 1799 and tonumber(GS:GetAttribute("BorderStartRadius")) == 1800 and (tonumber(GS:GetAttribute("BorderStage")) or 0) == 0
	local detail = { string.format("server: radius %.1f start %s stage %s of %s, next move at round second %s, moving=%s, round clock %s", sr,
		tostring(GS:GetAttribute("BorderStartRadius")), tostring(GS:GetAttribute("BorderStage")), tostring(GS:GetAttribute("BorderStageCount")),
		tostring(GS:GetAttribute("BorderNextMoveAt")), tostring(GS:GetAttribute("BorderMoving")), fmt({ Arena.getClock() })) }
	for _, p in ipairs(players) do
		if p.Parent == Players then
			local b = call(p, "probe", { kind = "border" }) or {}
			local r, g, bl = string.match(tostring(b.looks), "BorderLine rgb%((%d+),(%d+),(%d+)%)")
			local blue = r ~= nil and tonumber(bl) > 200 and tonumber(bl) > 2 * tonumber(r) and tonumber(bl) > tonumber(g)
			local lo = tonumber(string.match(tostring(b.lineRadius), "^(%d+)")) or -1
			local near = lo > 0 and math.abs(lo - sr) < 60
			local cr = tonumber(b.radius) or -1
			ok = ok and blue and near and math.abs(cr - sr) < 30
			table.insert(detail, string.format("%s's client: radius %s stage %s next %s; wall parts %s, ground line at %s from the centre; looks: %s", p.Name, fmt(b.radius),
				tostring(b.stage), tostring(b.nextMoveAt), tostring(b.parts), tostring(b.lineRadius), string.sub(tostring(b.looks), 1, 260)))
		end
	end
	check(tag, ok, table.concat(detail, " | "))
end

-- the results board in the lobby on each screen: the round's winner and rows, each player's own row marked
local function boardChecks(tag: string, players: { Player }, winner: Player?, notInRound: Player?)
	local ok, detail = true, {}
	for _, p in ipairs(players) do
		if p.Parent == Players then
			local wantRow = p ~= notInRound
			local list = waitFor(function()
				local l = call(p, "probe", { kind = "board" })
				if type(l) == "table" then
					for _, b in ipairs(l) do
						if b.streamed and b.empty == false then
							return l
						end
					end
				end
				return nil
			end, 8) or call(p, "probe", { kind = "board" }) or {}
			local good = false
			local lines = {}
			for _, b in ipairs(list) do
				local mineRow = string.match(tostring(b.rows), "[^;]*" .. p.Name .. "[^;]*mine=true") ~= nil
				local othersMarked = false
				for row in string.gmatch(tostring(b.rows), "[^;]+") do
					if string.find(row, "mine=true", 1, true) and not string.find(row, p.Name, 1, true) then
						othersMarked = true
					end
				end
				local winOk = winner == nil or string.find(tostring(b.winner), winner.Name, 1, true) ~= nil
				if b.streamed and b.empty == false and (mineRow or not wantRow) and not othersMarked and winOk then
					good = true
				end
				table.insert(lines, string.format("board %s streamed=%s empty=%s %s; winner: %s; rows: %s; facts: %s; %s studs away, on screen=%s", tostring(b.at), tostring(b.streamed),
					tostring(b.empty), tostring(b.meta), tostring(b.winner), tostring(b.rows), tostring(b.facts), tostring(b.dist), tostring(b.onScreen)))
			end
			ok = ok and good
			table.insert(detail, p.Name .. "'s client: " .. (if #lines > 0 then table.concat(lines, " / ") else "no board"))
		end
	end
	check(tag, ok, table.concat(detail, " | "))
end

-- the train lobby: everyone in a car, the camera inside it, the scenery sliding past
local function trainChecks(tag: string, players: { Player })
	local ok, detail, spawns = true, {}, {}
	for _, p in ipairs(players) do
		if p.Parent == Players then
			local t = call(p, "probe", { kind = "lobby" }) or {}
			local good = t.rootCar ~= nil and t.camCar ~= nil and (tonumber(t.sceneryMovedIn05s) or 0) > 0.5
			ok = ok and good
			table.insert(spawns, tostring(t.nearestSpawn))
			table.insert(detail, string.format("%s: character in car %s at %s, camera in car %s at %s (%.1f studs from the root; ceiling above the camera: %s); scenery %s parts moved %.1f studs in 0.5 s; nearest spawn %s",
				p.Name, tostring(t.rootCar), fmt(t.root), tostring(t.camCar), fmt(t.cam), tonumber(t.zoom) or -1, tostring(t.ceilingAboveCam), tostring(t.sceneryParts),
				tonumber(t.sceneryMovedIn05s) or -1, tostring(t.nearestSpawn)))
		end
	end
	check(tag, ok, table.concat(detail, " | "))
end

-- batches ---------------------------------------------------------------------------------------------------------------
local lobbyExtra: (() -> ())? = nil -- (batch W: the wheel, the boxes and the Armoury, before the round is released)
local function lobbyChecks()
	local ok = waitFor(function()
		local list = Players:GetPlayers()
		if #list < EXPECT then
			return false
		end
		for _, p in ipairs(list) do
			if not botReady[p] or not p.Character then
				return false
			end
		end
		return true
	end, 150)
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return a.UserId > b.UserId -- -1 first (Player1), then -2
	end)
	A, B = list[1], list[2]
	P3 = list[3]
	if not (ok and A and B) then
		check("lobby.join", false, "two players with bots did not appear in 150 s: " .. #list .. " players")
		return false
	end
	L(string.format("A=%s (%d) B=%s (%d) uptime=%.1f phase=%s", A.Name, A.UserId, B.Name, B.UserId, time(), phase()))
	if ARGS.quality then
		for _, p in ipairs(list) do
			L("QUALITY " .. p.Name .. ": " .. tostring(call(p, "quality", { level = tostring(ARGS.quality) })))
		end
		beforeEnd = function()
			for _, p in ipairs(Players:GetPlayers()) do
				call(p, "quality", {}, 2)
			end
		end
	end
	task.wait(1.0)
	snapshotAll("lobby")
	local seeA, seeB = call(A, "see") or {}, call(B, "see") or {}
	local sa, sb = seeA[B.Name], seeB[A.Name]
	local _, ra = parts(A)
	local _, rb = parts(B)
	local okSee = sa ~= nil and sb ~= nil and sa.char == true and sb.char == true
	local errA = if sb and sb.pos and ra then (sb.pos - ra.Position).Magnitude else -1
	local errB = if sa and sa.pos and rb then (sa.pos - rb.Position).Magnitude else -1
	check("lobby.seeEachOther", okSee and errA >= 0 and errA < 3 and errB >= 0 and errB < 3,
		string.format("A sees B's character=%s (position off by %.2f from the server's), B sees A's=%s (off by %.2f); A sees %d/%d of B's body parts visible, B %d/%d of A's",
			tostring(sa and sa.char), errB, tostring(sb and sb.char), errA, sa and sa.bodyVisible or -1, sa and sa.bodyParts or -1, sb and sb.bodyVisible or -1,
			sb and sb.bodyParts or -1))
	check("lobby.state", A:GetAttribute("InArena") ~= true and B:GetAttribute("InArena") ~= true and (tonumber(GS:GetAttribute("LobbyCount")) or 0) == #list,
		string.format("phase=%s LobbyCount=%s A.InArena=%s B.InArena=%s Practice=%s", phase(), tostring(GS:GetAttribute("LobbyCount")),
			tostring(A:GetAttribute("InArena")), tostring(B:GetAttribute("InArena")), tostring(GS:GetAttribute("Practice"))))
	for _, p in ipairs({ A, B }) do
		local list = call(p, "gui") or {}
		L("GUI[lobby,held] " .. p.Name .. ": " .. string.sub(table.concat(list, " ; "), 1, 1500))
	end
	trainChecks("lobby.train", list)
	shot("train_lobby", 1.0)
	chatCheck("lobby.chatClosed", { A, B }, true)
	plusLobbyChecks(A, B)
	if lobbyExtra then
		local okX, errX = pcall(lobbyExtra)
		if not okX then
			L("DRIVER ERROR in the lobby part: " .. tostring(errX))
		end
	end
	-- the lobby countdown as each client shows it
	release()
	waitFor(function()
		return phase() == "Intermission" or phase() == "Countdown"
	end, 20)
	task.wait(0.5)
	for _, p in ipairs({ A, B }) do
		local has, text = guiHas(p, "next round")
		check("lobby.timer." .. p.Name, has, "phase=" .. phase() .. " texts with 'next round': " .. string.sub(text, 1, 300))
	end
	return true
end

local function roundStartChecks(tag: string, fromA: number?, fromB: number?): boolean
	local mA0, mB0 = fromA or mark(A), fromB or mark(B)
	if not waitPhase("Countdown", 60) then
		check(tag .. ".countdown", false, "no Countdown within 60 s, phase=" .. phase())
		return false
	end
	local cut = tostring(GS:GetAttribute("LaunchCut"))
	local both = Round.isContender(A) and Round.isContender(B) and (EXPECT < 3 or (P3 ~= nil and Round.isContender(P3)))
	check(tag .. ".realRound", both and GS:GetAttribute("Practice") == false and GS:GetAttribute("StartedCount") == EXPECT
		and workspace:FindFirstChild("TrainingDummies") == nil,
		string.format("contenders=%s Practice=%s StartedCount=%s cut=%s dummiesFolder=%s BorderStartRadius=%s", contenderNames(), tostring(GS:GetAttribute("Practice")),
			tostring(GS:GetAttribute("StartedCount")), cut, tostring(workspace:FindFirstChild("TrainingDummies") ~= nil), tostring(GS:GetAttribute("BorderStartRadius"))))
	task.wait(1.0)
	local center = arenaCenter()
	local _, ra = parts(A)
	local _, rb = parts(B)
	if ra and rb then
		local function facing(root: BasePart): number
			local to = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			return if to.Magnitude > 0.1 and look.Magnitude > 0.1 then to.Unit:Dot(look.Unit) else -2
		end
		local apart = flatDist(ra.Position, rb.Position)
		local ringA, ringB = flatDist(ra.Position, center), flatDist(rb.Position, center)
		check(tag .. ".plinths", apart > 20 and facing(ra) > 0.97 and facing(rb) > 0.97 and A:GetAttribute("Frozen") == true and B:GetAttribute("Frozen") == true,
			string.format("A at %s (ring radius %.1f, facing-the-Horn dot %.3f, frozen %s), B at %s (radius %.1f, dot %.3f, frozen %s); %.1f studs apart", v3(ra.Position),
				ringA, facing(ra), tostring(A:GetAttribute("Frozen")), v3(rb.Position), ringB, facing(rb), tostring(B:GetAttribute("Frozen")), apart))
	else
		check(tag .. ".plinths", false, "a contender has no character in the Countdown")
	end
	-- the launch intro on both clients
	local mA, mB = mA0, mB0
	local shotA = waitFor(function()
		return clientFind(A, "LAUNCHSHOT true", mA)
	end, 6)
	local shotB = waitFor(function()
		return clientFind(B, "LAUNCHSHOT true", mB)
	end, 2)
	if cut ~= "" then
		check(tag .. ".introStarts", shotA ~= nil and shotB ~= nil, string.format("cut=%s; launch shot took the camera on A: %s, on B: %s", cut, tostring(shotA ~= nil),
			tostring(shotB ~= nil)))
		task.wait(2.5)
		for _, p in ipairs({ A, B }) do
			local st = call(p, "state") or {}
			L(string.format("INTRO mid-shot client %s launchShot=%s camType=%s camPos=%s frozen=%s", p.Name, tostring(st.launchShot), tostring(st.camType),
				fmt(st.camPos), tostring(st.frozen)))
			local see = call(p, "see") or {}
			L(string.format("INTRO mid-shot client %s sees %s", p.Name, fmt(see)))
		end
	end
	-- the personal skip (owner, 18 Nov): one contender skips, the other's intro plays on
	local skipper = SKIP_BY[tag]
	local watcher = if skipper == A then B elseif skipper == B then A else nil
	local tSkip: number? = nil
	if skipper and watcher and shotA and shotB then
		local before = call(skipper, "probe", { kind = "skip" }) or {}
		check(tag .. ".skip.promptShown", before.launchShot == true and #(before.shown or {}) > 0, string.format("%s's screen before skipping: launchShot=%s, skip texts: [%s]",
			skipper.Name, tostring(before.launchShot), table.concat(before.shown or {}, " ; ")))
		shot(tag .. "_before_skip", 0.6)
		local mS = mark(skipper)
		tSkip = now()
		call(skipper, "setattr", { name = "LS_LaunchSkipTest", value = true }) -- (Studio: acts as a completed hold of Space)
		local ended = waitFor(function()
			return (clientFind(skipper, "LAUNCHSHOT false", mS))
		end, 3)
		task.wait(0.4)
		local s, w = call(skipper, "probe", { kind = "skip" }) or {}, call(watcher, "probe", { kind = "skip" }) or {}
		local _, rs = parts(skipper)
		local camOff = if typeof(s.cam) == "Vector3" and rs then (s.cam - rs.Position).Magnitude else -1
		check(tag .. ".skip.personal", ended ~= nil and s.launchShot ~= true and #(s.shown or {}) == 0 and camOff >= 0 and camOff < 4 and w.launchShot == true
			and #(w.shown or {}) > 0, string.format(
			"%s skipped: shot ended on its client %s (%s s after the order); its camera now %.1f studs from its own root (%s), skip texts left: [%s] | %s's intro: launchShot=%s, skip texts: [%s]",
			skipper.Name, tostring(ended), if ended then string.format("%.2f", (tonumber(string.match(ended, "^([%d%.]+)")) or 0) - tSkip) else "?", camOff,
			tostring(s.camType), table.concat(s.shown or {}, " ; "), watcher.Name, tostring(w.launchShot), table.concat(w.shown or {}, " ; ")))
		shot(tag .. "_after_skip", 0.6)
	end
	if not waitPhase("Active", 40) then
		check(tag .. ".horn", false, "no Active phase within 40 s of the Countdown, phase=" .. phase())
		return false
	end
	if skipper and watcher and tSkip then
		task.wait(0.6)
		local endW = clientFind(watcher, "LAUNCHSHOT false", mA0 and (if watcher == A then mA0 else mB0))
		local hornS = clientFind(skipper, "REMOTE Sfx StartHorn", if skipper == A then mA0 else mB0)
		local hornW = clientFind(watcher, "REMOTE Sfx StartHorn", if watcher == A then mA0 else mB0)
		local tW = endW and tonumber(string.match(endW, "^([%d%.]+)"))
		local tHS, tHW = hornS and tonumber(string.match(hornS, "^([%d%.]+)")), hornW and tonumber(string.match(hornW, "^([%d%.]+)"))
		check(tag .. ".skip.otherPlaysOn", tW ~= nil and tW - tSkip > 3 and tHS ~= nil and tHW ~= nil and math.abs(tHS - tHW) < 0.5, string.format(
			"%s's intro ended %s s after %s skipped (the shot's own hand-off); the horn sound reached %s at %s and %s at %s (apart %s s); phase Active at %.3f",
			watcher.Name, if tW then string.format("%.2f", tW - tSkip) else "never", skipper.Name, skipper.Name, tostring(tHS), watcher.Name, tostring(tHW),
			if tHS and tHW then string.format("%.2f", math.abs(tHS - tHW)) else "?", now()))
	end
	task.wait(1.2)
	local stA, stB = call(A, "state") or {}, call(B, "state") or {}
	local function own(st: any, p: Player): boolean
		return st.launchShot ~= true and st.camType == "Custom" and type(st.camSubject) == "string" and string.find(st.camSubject, p.Name, 1, true) ~= nil
			and st.frozen == false and st.inArena == true and st.alive == true
	end
	check(tag .. ".horn", own(stA, A) and own(stB, B),
		string.format("after the horn: A launchShot=%s cam=%s subject=%s frozen=%s alive=%s | B launchShot=%s cam=%s subject=%s frozen=%s alive=%s",
			tostring(stA.launchShot), tostring(stA.camType), tostring(stA.camSubject), tostring(stA.frozen), tostring(stA.alive), tostring(stB.launchShot),
			tostring(stB.camType), tostring(stB.camSubject), tostring(stB.frozen), tostring(stB.alive)))
	chatCheck(tag .. ".chatClosedAtHandoff", { A, B }, true)
	-- nobody left in a tube on the other's screen
	local seeA, seeB = call(A, "see") or {}, call(B, "see") or {}
	local _, ra2 = parts(A)
	local _, rb2 = parts(B)
	local sa, sb = seeA[B.Name], seeB[A.Name]
	if sa and sb and sa.pos and sb.pos and ra2 and rb2 then
		local eB, eA = (sa.pos - rb2.Position).Magnitude, (sb.pos - ra2.Position).Magnitude
		check(tag .. ".riseOnOtherScreen", eA < 1.5 and eB < 1.5, string.format(
			"after the horn A's screen has B %.2f studs from the server's position (y %.2f vs %.2f); B's screen has A %.2f studs off (y %.2f vs %.2f)", eB, sa.pos.Y,
			rb2.Position.Y, eA, sb.pos.Y, ra2.Position.Y))
	else
		check(tag .. ".riseOnOtherScreen", nil, "the other contender's character is not streamed in on one client (they stand "
			.. (if ra2 and rb2 then string.format("%.0f", flatDist(ra2.Position, rb2.Position)) else "?") .. " studs apart): A sees B=" .. tostring(sa and sa.char)
			.. " B sees A=" .. tostring(sb and sb.char))
	end
	check(tag .. ".roundsPlayed", nil, string.format("RoundsPlayed A=%s B=%s", tostring(A:GetAttribute("RoundsPlayed")), tostring(B:GetAttribute("RoundsPlayed"))))
	if not ARGS.border then
		borderLook(tag .. ".borderAtStart", { A, B }, false)
	end
	return true
end

-- puts both on flat ground near A's plate and readies the duel line
local function setupDuel()
	local _, ra = parts(A)
	local center = arenaCenter()
	if not ra then
		return
	end
	local toCenter = Vector3.new(center.X - ra.Position.X, 0, center.Z - ra.Position.Z).Unit
	-- across the line to the Horn, a little inside the plate ring: open ground
	local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
	local base = ra.Position + toCenter * 14
	duelBase = base
	duelDir = side
	local best, bestSpread = nil, math.huge
	for _, try in ipairs({ { 14, 1 }, { 14, -1 }, { 22, 1 }, { 22, -1 }, { 30, 1 }, { 8, 1 } }) do
		local b = ra.Position + toCenter * try[1]
		local lo, hi = math.huge, -math.huge
		local okAll = true
		for d = 0, 24, 3 do
			local g = groundAt(b.X + side.X * d * try[2], ra.Position.Y, b.Z + side.Z * d * try[2])
			if g then
				lo, hi = math.min(lo, g.Y), math.max(hi, g.Y)
			else
				okAll = false
			end
		end
		if okAll and hi - lo < bestSpread then
			bestSpread = hi - lo
			best = { b, side * try[2] }
		end
	end
	if best then
		duelBase, duelDir = best[1], best[2]
	end
	L(string.format("DUEL line base %s dir (%.2f,%.2f) ground spread over 24 studs %.2f", v3(duelBase :: Vector3), duelDir.X, duelDir.Z, bestSpread))
end

-- what `viewer`'s client drew of `archer`'s bow since `from` (SEE-BOW lines), against the arrow's ProjectileFired
local function bowSeen(viewer: Player, archer: Player, from: number): { [string]: any }
	local out: { [string]: any } = { maxPull = 0, held = false }
	local store = clientLines[viewer.Name] or {}
	for i = from + 1, #store do
		local line = store[i]
		local t = tonumber(string.match(line, "^([%d%.]+)"))
		if string.find(line, "SEE-BOW " .. archer.Name, 1, true) then
			local drawing = string.find(line, "drawing=true", 1, true) ~= nil
			local pull = tonumber(string.match(line, "pull=([%d%.]+)")) or 0
			out.held = out.held or string.find(line, "bow=true", 1, true) ~= nil
			if drawing and not out.tDraw then
				out.tDraw = t
			end
			if drawing and string.find(line, "string=true", 1, true) and not out.tString then
				out.tString = t
			end
			if drawing and not out.tFired then
				out.maxPull = math.max(out.maxPull, pull)
			end
			if not drawing and out.tDraw and not out.tEnd then
				out.tEnd = t
			end
		elseif string.find(line, "REMOTE ProjectileFired", 1, true) and not out.tFired then
			out.tFired = t
		end
	end
	return out
end

-- honest swings at a moving player: A clicks every `every` seconds for `seconds` while `eachStep` moves the players;
-- every strike A's own screen showed as a hit must be applied by the server, with no refusal. B's health is refilled.
local function swingAtMoving(label: string, seconds: number, first: number, every: number, eachStep: (number) -> ()): (number, number, string, string)
	local c0, h0, r0 = claimsBy[A.Name] or 0, hitsBy[A.Name] or 0, refusals()
	local t0 = os.clock()
	local nextClick = first
	local far, near, fastA, fastB = 0, math.huge, 0, 0
	while os.clock() - t0 < seconds do
		local e = os.clock() - t0
		eachStep(e)
		if e >= nextClick then
			nextClick = e + every
			task.spawn(call, A, "seq", { { "click" } }, 3)
		end
		setHealth(B)
		local _, ra = parts(A)
		local _, rb = parts(B)
		if ra and rb then
			local d = flatDist(ra.Position, rb.Position)
			far, near = math.max(far, d), math.min(near, d)
			fastA = math.max(fastA, Vector3.new(ra.AssemblyLinearVelocity.X, 0, ra.AssemblyLinearVelocity.Z).Magnitude)
			fastB = math.max(fastB, Vector3.new(rb.AssemblyLinearVelocity.X, 0, rb.AssemblyLinearVelocity.Z).Magnitude)
		end
		task.wait(0.05)
	end
	call(A, "move", {})
	call(B, "move", {})
	task.wait(0.9)
	setHealth(B)
	local claims, hits = (claimsBy[A.Name] or 0) - c0, (hitsBy[A.Name] or 0) - h0
	local detail = string.format("%d strikes A's own screen showed as hits, %d applied by the server; they were %.1f to %.1f studs apart; top speed A %.1f, B %.1f studs/s; refusals before [%s], after [%s]",
		claims, hits, near, far, fastA, fastB, r0, refusals())
	L("MOVING " .. label .. ": " .. detail)
	return claims, hits, r0, detail
end

local function movingChecks()
	local sword = slotOf(A, "sword")
	local perp = Vector3.new(-duelDir.Z, 0, duelDir.X)
	local up = Vector3.new(0, 1.5, 0)
	-- B strafes across A's view, turning every 0.9 s; A stands and follows with the camera
	setHealth(B)
	L(duel(A, B, 6))
	call(A, "seq", { { "select", sword }, { "wait", 0.8 } }, 6)
	call(A, "track", { target = B.Name, seconds = 9 })
	local sign, nextFlip = 1, 0
	local claims, hits, r0, detail = swingAtMoving("strafing", 6.5, 0.45, 0.85, function(e)
		if e >= nextFlip then
			local _, rb = parts(B)
			if rb then
				task.spawn(call, B, "move", { seconds = 1.2, face = rb.Position + perp * sign * 60 + up })
			end
			nextFlip = e + (if nextFlip == 0 then 0.45 else 0.9)
			sign = -sign
		end
	end)
	check("melee.moving.strafe", claims >= 3 and hits == claims and refusals() == r0, "sword, B strafing at walking speed 6 studs in front of A: " .. detail)
	-- B walks straight away from A; A walks after it, swinging
	call(A, "track", {})
	setHealth(B)
	L(duel(A, B, 5))
	local _, ra = parts(A)
	local farPoint = (if ra then ra.Position else Vector3.zero) + duelDir * 220 + up
	local started = false
	claims, hits, r0, detail = swingAtMoving("retreating", 4.5, 0.45, 0.85, function()
		if not started then
			started = true
			task.spawn(call, A, "move", { seconds = 4.4, face = B.Name })
			task.spawn(call, B, "move", { seconds = 4.4, face = farPoint })
		end
	end)
	check("melee.moving.retreat", claims >= 3 and hits == claims and refusals() == r0, "sword, B walking away and A walking after it: " .. detail)
	-- the tight case of the new allowance: A sprints from a standstill at a player standing still and swings at once
	setHealth(B)
	L(duel(A, B, 13))
	local was = call(A, "setting", { name = "sprintMode", value = 2 })
	task.wait(0.5)
	started = false
	claims, hits, r0, detail = swingAtMoving("lunge", 1.7, 0.2, 0.6, function()
		if not started then
			started = true
			task.spawn(call, A, "move", { seconds = 1.1, face = B.Name })
		end
	end)
	call(A, "setting", { name = "sprintMode", value = was or 0 })
	check("melee.moving.lunge", if claims == 0 then nil else hits == claims and refusals() == r0,
		"sword, B standing still 13 studs away, A sprints at it from a standstill and swings at once: " .. detail)
	-- a modified client's claims on a player standing still: the sword from 13 studs, bare hands from 11.5
	setHealth(B)
	L(duel(A, B, 13))
	task.wait(0.6)
	local r = attack("sword raw claim@13", { { "face", B.Name }, { "wait", 0.3 }, { "remote", "MeleeSwing", "raw", B.Name } })
	check("melee.sword.rawClaim@13", r.dealt < 0.5, string.format("a modified client claiming a sword hit from 13 studs on a player standing still: B lost %.1f; refusals: %s",
		r.dealt, refusals()))
	setHealth(B)
	local st = call(A, "state") or {}
	if st.equippedSlot then
		call(A, "select", st.equippedSlot) -- (selecting the slot in hand puts the item away: bare hands)
	end
	L(duel(A, B, 11.5))
	task.wait(0.6)
	st = call(A, "state") or {}
	r = attack("fists raw claim@11.5", { { "face", B.Name }, { "wait", 0.3 }, { "remote", "MeleeSwing", "raw", B.Name } })
	check("melee.fists.rawClaim@11.5", r.dealt < 0.5, string.format(
		"a modified client claiming a bare-hands hit from 11.5 studs on a player standing still (in hand: %s): B lost %.1f; refusals: %s", tostring(st.equipped), r.dealt,
		refusals()))
	setHealth(B)
end

local function combatChecks()
	setupDuel()
	Inv.clear(A)
	Inv.clear(B)
	L("give A: sword " .. Inv.give(A, "sword", 1) .. " knife " .. Inv.give(A, "knife", 1) .. " bow " .. Inv.give(A, "bow", 1) .. " arrow " .. Inv.give(A, "arrow", 12)
		.. " throwing_knife " .. Inv.give(A, "throwing_knife", 4) .. " mace " .. Inv.give(A, "mace", 1))
	L("give B: knife " .. Inv.give(B, "knife", 1))
	task.wait(0.5)
	L("inv A " .. invLine(A) .. " | inv B " .. invLine(B))
	local sword, knife, bow, tk, mace = slotOf(A, "sword"), slotOf(A, "knife"), slotOf(A, "bow"), slotOf(A, "throwing_knife"), slotOf(A, "mace")
	local target = B.Name

	-- sword in reach
	L(duel(A, B, 7))
	local r = attack("sword@7", { { "select", sword }, { "wait", 0.7 }, { "face", target }, { "wait", 0.4 }, { "aimerr", target }, { "click" } })
	local seen = r.tAct ~= nil and r.tDmg ~= nil and r.tAct < r.tDmg
	check("melee.sword.damage", math.abs(r.dealt - dmgOf("sword")) < 0.6 and r.tConfirm ~= nil, string.format(
		"sword at 7 studs: B lost %.1f on the server (expected " .. dmgOf("sword") .. ", the Longsword at 1 star); A got HitConfirm=%s; A's own screen shows B's health drop=%s", r.dealt, tostring(r.tConfirm ~= nil),
		tostring(r.tSeeHp ~= nil)))
	check("melee.sword.victimSeesSwingFirst", seen, string.format(
		"on B's client the swing message arrived %s s before the damage message (swing start on A %.3f, B told %s, B plays the swing %s, B damage %s, server health drop %s); message: %s",
		if r.tAct and r.tDmg then string.format("%.3f", r.tDmg - r.tAct) else "?", r.tSwingA or -1, tostring(r.tAct), tostring(r.tSeeSwing), tostring(r.tDmg),
		tostring(r.tServerDrop), tostring(r.act)))
	check("melee.sword.attackerSeesReact", r.tSeeHp ~= nil and r.tConfirm ~= nil, string.format("A's client: HitConfirm %s, B's health change seen at %s (strike at %s)",
		tostring(r.tConfirm), tostring(r.tSeeHp), tostring(r.tStrike)))
	local dmgLine = r.dmg
	L("B DamageTaken line: " .. tostring(dmgLine))

	-- sword at the edge and beyond
	setHealth(B)
	L(duel(A, B, 10))
	r = attack("sword@10", { { "face", target }, { "wait", 0.4 }, { "aimerr", target }, { "click" } })
	check("melee.sword.reach10", math.abs(r.dealt - dmgOf("sword")) < 0.6, string.format("sword at 10 studs: B lost %.1f (the reach is 10 root to root)", r.dealt))
	setHealth(B)
	L(duel(A, B, 11.5))
	r = attack("sword@11.5", { { "face", target }, { "wait", 0.4 }, { "aimerr", target }, { "click" } })
	check("melee.sword.beyondReach", r.dealt < 0.5, string.format("sword at 11.5 studs: B lost %.1f (expected 0); A's client predicted %s", r.dealt,
		tostring(r.strike and string.match(r.strike, "hit=%S+"))))
	r = attack("sword raw claim@11.5", { { "face", target }, { "wait", 0.3 }, { "remote", "MeleeSwing", "raw", target } })
	check("melee.sword.rawClaimBeyondReach", r.dealt < 0.5, string.format("a modified client claiming a hit from 11.5 studs: B lost %.1f (expected 0); refusals: %s",
		r.dealt, refusals()))

	-- the first swing after a weapon switch
	setHealth(B)
	L(duel(A, B, 6))
	r = attack("knife then switch to sword, attack during the switch",
		{ { "select", knife }, { "wait", 0.8 }, { "face", target }, { "wait", 0.3 }, { "click" }, { "wait", 0.25 }, { "select", sword }, { "wait", 0.05 }, { "click" },
			{ "wait", 1.0 } }, 1.0)
	check("melee.switch.firstSwingLands", math.abs(r.dealt - (dmgOf("knife") + dmgOf("sword"))) < 0.6, string.format(
		"knife hit (" .. dmgOf("knife") .. "), switch to the sword and attack during the switch (" .. dmgOf("sword") .. "): B lost %.1f in all (expected " .. (dmgOf("knife") + dmgOf("sword")) .. "); refusals: %s", r.dealt, refusals()))
	setHealth(B)
	r = attack("sword then switch to mace", { { "face", target }, { "wait", 0.2 }, { "click" }, { "wait", 0.3 }, { "select", mace }, { "wait", 0.05 }, { "click" },
		{ "wait", 1.6 } }, 1.0)
	check("melee.switch.swordToMace", math.abs(r.dealt - (dmgOf("sword") + dmgOf("mace"))) < 0.6, string.format("sword hit (" .. dmgOf("sword") .. "), switch to the mace and attack (" .. dmgOf("mace") .. "): B lost %.1f (expected " .. (dmgOf("sword") + dmgOf("mace")) .. "); refusals: %s",
		r.dealt, refusals()))

	-- bow
	setHealth(B)
	L(duel(A, B, 20))
	local arrowsBefore = Inv.count(A, "arrow")
	local mBow = mark(B)
	task.delay(2.15, L, "SHOT a_bow_drawn") -- (about 0.8 s into the draw below)
	r = attack("bow@20", { { "select", bow }, { "wait", 0.9 }, { "face", target }, { "wait", 0.4 }, { "aimerr", target }, { "down" }, { "track", target, 1.2 },
		{ "wait", 1.15 }, { "up" }, { "wait", 0.8 } }, 1.0)
	local fired = clientFind(B, "REMOTE ProjectileFired", 0)
	-- on B's screen: the draw is drawn on A's body before the arrow leaves (the bot logs CharacterVisuals' bow state)
	local bs = bowSeen(B, A, mBow)
	check("bow.drawnOnOtherScreenBeforeArrow", bs.tDraw ~= nil and bs.tFired ~= nil and bs.tDraw < bs.tFired and bs.tString ~= nil and bs.tString <= bs.tFired
		and bs.maxPull >= 0.85, string.format(
		"B's client: bow in A's hand=%s; draw pose began %s s before the arrow was told (string bent %s s before); string hand reached %.0f%% of the full pull before the arrow; pose let go %s s after it",
		tostring(bs.held), if bs.tDraw and bs.tFired then string.format("%.2f", bs.tFired - bs.tDraw) else "?",
		if bs.tString and bs.tFired then string.format("%.2f", bs.tFired - bs.tString) else "?", bs.maxPull * 100,
		if bs.tEnd and bs.tFired then string.format("%.2f", bs.tEnd - bs.tFired) else "?"))
	check("bow.damage", r.dealt > 20 and r.tConfirm ~= nil and Inv.count(A, "arrow") == arrowsBefore - 1, string.format(
		"a drawn arrow at 20 studs: B lost %.1f (full draw to the body = 50); arrows %d -> %d; A got HitConfirm=%s; B was told of the arrow in flight=%s; B's draw/release messages: %s",
		r.dealt, arrowsBefore, Inv.count(A, "arrow"), tostring(r.tConfirm ~= nil), tostring(fired ~= nil), tostring(r.act)))
	-- bow far beyond: an undrawn release must not shoot
	setHealth(B)

	-- thrown knife
	L(duel(A, B, 14))
	local tkBefore = Inv.count(A, "throwing_knife")
	r = attack("throwing knife@14", { { "select", tk }, { "wait", 0.9 }, { "face", target }, { "wait", 0.4 }, { "aimerr", target }, { "click" }, { "wait", 1.0 } }, 1.0)
	check("throw.knife.damage", (math.abs(r.dealt - ItemDefs.get("throwing_knife").damage) < 0.6 or math.abs(r.dealt - ItemDefs.get("throwing_knife").headDamage) < 0.6) and r.tConfirm ~= nil, string.format(
		"a thrown knife at 14 studs: B lost %.1f (expected " .. ItemDefs.get("throwing_knife").damage .. " body or " .. ItemDefs.get("throwing_knife").headDamage .. " head, Weapons_v2 1.2); knives %d -> %d; A got HitConfirm=%s; B's messages: %s", r.dealt, tkBefore, Inv.count(A, "throwing_knife"),
		tostring(r.tConfirm ~= nil), tostring(r.act)))
	setHealth(B)
	L("refusals after combat: " .. refusals())
	movingChecks()
	L("refusals after the moving checks: " .. refusals())
	snapshotAll("afterCombat")
end

local function seeOf(viewer: Player, target: Player): any
	local s = call(viewer, "see") or {}
	return s[target.Name] or {}
end

local function speedOf(s: any): number
	return if s and typeof(s.vel) == "Vector3" then Vector3.new(s.vel.X, 0, s.vel.Z).Magnitude else -1
end

local function poseLine(tag: string, s: any): string
	return string.format(
		"POSE %s: B sees A stance=%s humState=%s speed=%.1f headHeight=%s held=%s heldVisible=%s rightHand=%s leftHand=%s feet L=%s R=%s swing=%s onScreen=%s screen=%s tracks=%s",
		tag, tostring(s.stance), tostring(s.humState), speedOf(s), if s.headHeight then string.format("%.2f", s.headHeight) else "?", tostring(s.held),
		tostring(s.heldVisible), fmt(s.handFromRoot), fmt(s.leftHand), fmt(s.leftFoot), fmt(s.rightFoot), tostring(s.swing), tostring(s.onScreen), tostring(s.screen),
		tostring(s.tracks))
end

local function giveKit()
	Inv.clear(A)
	Inv.clear(B)
	L("give A: sword " .. Inv.give(A, "sword", 1) .. " bow " .. Inv.give(A, "bow", 1) .. " arrow " .. Inv.give(A, "arrow", 12)
		.. " throwing_knife " .. Inv.give(A, "throwing_knife", 4) .. " spear " .. Inv.give(A, "spear", 1) .. " apple " .. Inv.give(A, "apple", 2))
	L("give B: knife " .. Inv.give(B, "knife", 1))
	task.wait(0.5)
	L("inv A " .. invLine(A) .. " | inv B " .. invLine(B))
end

local RAW_CLAIMS = { 11, 12, 13, 13.5, 15 }
local function swordChecks()
	local sword = slotOf(A, "sword")
	local target = B.Name
	setHealth(B)
	L(duel(A, B, 7))
	local r = attack("sword@7", { { "select", sword }, { "wait", 0.7 }, { "face", target }, { "wait", 0.4 }, { "aimerr", target }, { "click" } })
	check("melee.sword.damage", math.abs(r.dealt - dmgOf("sword")) < 0.6 and r.tConfirm ~= nil, string.format(
		"sword at 7 studs: B lost %.1f on the server (expected " .. dmgOf("sword") .. ", the Longsword at 1 star); A got HitConfirm=%s; A's own screen shows B's health drop=%s", r.dealt, tostring(r.tConfirm ~= nil),
		tostring(r.tSeeHp ~= nil)))
	check("melee.sword.victimSeesSwingFirst", r.tAct ~= nil and r.tDmg ~= nil and r.tAct < r.tDmg, string.format(
		"B's client: swing message %s s before the damage message (A starts %s, B told %s, B plays it %s, B damage %s, server drop %s); %s",
		if r.tAct and r.tDmg then string.format("%.3f", r.tDmg - r.tAct) else "?", tostring(r.tSwingA), tostring(r.tAct), tostring(r.tSeeSwing), tostring(r.tDmg),
		tostring(r.tServerDrop), tostring(r.act)))
	setHealth(B)
	L(duel(A, B, 10))
	r = attack("sword@10", { { "face", target }, { "wait", 0.4 }, { "aimerr", target }, { "click" } })
	check("melee.sword.reach10", math.abs(r.dealt - dmgOf("sword")) < 0.6, string.format("sword at 10 studs: B lost %.1f (expected " .. dmgOf("sword") .. ": the reach is 10 root to root); A predicted %s",
		r.dealt, tostring(r.strike and string.match(r.strike, "hit=%S+"))))
	setHealth(B)
	L(duel(A, B, 11.5))
	r = attack("sword@11.5", { { "face", target }, { "wait", 0.4 }, { "aimerr", target }, { "click" } })
	check("melee.sword.beyondReach", r.dealt < 0.5, string.format("sword at 11.5 studs: B lost %.1f (expected 0); A's client predicted %s", r.dealt,
		tostring(r.strike and string.match(r.strike, "hit=%S+"))))
	for _, d in ipairs(RAW_CLAIMS) do
		setHealth(B)
		L(duel(A, B, d))
		local before = refusals()
		r = attack("sword raw claim@" .. d, { { "face", target }, { "wait", 0.3 }, { "remote", "MeleeSwing", "raw", target } })
		check("melee.sword.rawClaim@" .. d, r.dealt < 0.5, string.format(
			"a modified client claiming a sword hit from %.1f studs on a player standing still: B lost %.1f; refusals before [%s] after [%s]", d, r.dealt, before, refusals()))
	end
	setHealth(B)
end

local function poseChecks()
	local target = A.Name
	local perp = Vector3.new(-duelDir.Z, 0, duelDir.X)
	local center = arenaCenter()
	if duelBase and (center - (duelBase + perp * 10)).Magnitude > (center - duelBase).Magnitude then
		perp = -perp -- walk toward the Horn: open ground
	end
	local sword = slotOf(A, "sword")
	call(B, "setattr", { name = "LS_SwingSlowMo", value = nil })
	L(duel(A, B, 10))
	call(B, "track", { target = target, seconds = 90 })
	call(A, "seq", { { "select", sword }, { "wait", 0.6 } }, 6)
	task.wait(0.6)
	local stand = seeOf(B, A)
	L(poseLine("stand", stand))
	shot("pose_stand")

	-- walking: A looks toward the Horn and pushes its move input fully forward (across B's view)
	local _, raw = parts(A)
	local ahead = if raw then raw.Position + perp * 60 + Vector3.new(0, 1.5, 0) else Vector3.zero
	local moved = call(A, "move", { seconds = 2.6, face = ahead })
	task.wait(1.1)
	local walk = seeOf(B, A)
	local stA = call(A, "state") or {}
	L(poseLine("walk", walk) .. " | A moveState=" .. tostring(stA.moveState) .. " speed=" .. tostring(stA.speed) .. " moveAction=" .. tostring(moved))
	shot("pose_walk", 1.3)
	check("pose.walk", speedOf(walk) > 6 and stA.moveState == "Walk" and walk.onScreen == true, string.format(
		"A walks (its own client: %s at %s studs/s); B's client has A moving at %.1f studs/s, on screen=%s, feet L=%s R=%s", tostring(stA.moveState),
		tostring(stA.speed), speedOf(walk), tostring(walk.onScreen), fmt(walk.leftFoot), fmt(walk.rightFoot)))
	task.wait(0.5)

	-- sprinting: the keyboard's sprint mode set to Auto on A's client (a player setting: a full push forward sprints)
	L(duel(A, B, 10))
	local was = call(A, "setting", { name = "sprintMode", value = 2 })
	_, raw = parts(A)
	ahead = if raw then raw.Position + perp * 80 + Vector3.new(0, 1.5, 0) else Vector3.zero
	call(A, "move", { seconds = 2.6, face = ahead })
	task.wait(1.3)
	local sprint = seeOf(B, A)
	stA = call(A, "state") or {}
	L(poseLine("sprint", sprint) .. " | A moveState=" .. tostring(stA.moveState) .. " speed=" .. tostring(stA.speed))
	shot("pose_sprint", 1.1)
	check("pose.sprint", speedOf(sprint) > 16 and stA.moveState == "Sprint", string.format(
		"A sprints (its own client: %s at %s studs/s); B's client has A moving at %.1f studs/s, feet L=%s R=%s", tostring(stA.moveState), tostring(stA.speed),
		speedOf(sprint), fmt(sprint.leftFoot), fmt(sprint.rightFoot)))
	task.wait(0.6)
	call(A, "setting", { name = "sprintMode", value = was or 0 })
	call(A, "move", {})

	-- crouching
	L(duel(A, B, 10))
	local mB = mark(B)
	call(A, "touch", { name = "Crouch", down = true })
	task.wait(1.0)
	local crouch = seeOf(B, A)
	stA = call(A, "state") or {}
	L(poseLine("crouch", crouch) .. " | A moveState=" .. tostring(stA.moveState))
	shot("pose_crouch")
	local told = clientFind(B, "SEE-ATTR " .. A.Name .. ".Stance=Crouch", mB)
	check("pose.crouch", crouch.stance == "Crouch" and told ~= nil and (crouch.headHeight or 9) < (stand.headHeight or 0) - 0.4, string.format(
		"A crouches (its own client: %s); B's client has A's Stance=%s (told: %s) and A's head %.2f studs above its feet, standing %.2f", tostring(stA.moveState),
		tostring(crouch.stance), tostring(told ~= nil), crouch.headHeight or -1, stand.headHeight or -1))
	_, raw = parts(A)
	call(A, "move", { seconds = 1.6, face = if raw then raw.Position + perp * 60 + Vector3.new(0, 1.5, 0) else nil })
	task.wait(0.9)
	local cw = seeOf(B, A)
	L(poseLine("crouch-walk", cw))
	shot("pose_crouchwalk", 1.0)
	stA = call(A, "state") or {}
	if stA.moveState == "Crouch" then
		call(A, "touch", { name = "Crouch", down = true }) -- toggle off
		task.wait(0.4)
		stA = call(A, "state") or {}
		if stA.moveState == "Crouch" then
			call(A, "touch", { name = "Crouch", down = false })
		end
	end
	task.wait(0.6)
	local up = seeOf(B, A)
	L(poseLine("stand again", up))

	-- what A holds, as B sees it
	L(duel(A, B, 8))
	local okHolds, holds = true, {}
	for _, id in ipairs({ "sword", "bow", "throwing_knife", "spear", "apple" }) do
		local slot = slotOf(A, id)
		call(A, "seq", { { "select", slot }, { "wait", 0.9 } }, 6)
		local s = seeOf(B, A)
		L(poseLine("hold " .. id, s))
		L("HELD " .. id .. " on B's client: " .. tostring(call(B, "heldinfo", A.Name)))
		local good = s.held == id and (s.heldVisible or 0) > 0 and s.equippedAttr == id
		okHolds = okHolds and good
		table.insert(holds, string.format("%s: model=%s visible parts=%s hand=%s", id, tostring(s.held), tostring(s.heldVisible), fmt(s.handFromRoot)))
		shot("hold_" .. id, 1.2)
	end
	check("pose.holds", okHolds, "what B's client has in A's hand: " .. table.concat(holds, "; "))

	-- a swing seen from the side, slowed 8 times on B's client only (a look hook of CharacterVisuals; damage is not involved)
	call(B, "setattr", { name = "LS_SwingSlowMo", value = 8 })
	local _, ra = parts(A)
	local away = if ra then ra.Position + perp * 30 + Vector3.new(0, 1.5, 0) else Vector3.zero
	mB = mark(B)
	call(A, "seq", { { "select", sword }, { "wait", 0.8 }, { "face", away }, { "wait", 0.4 }, { "click" } }, 8)
	task.wait(0.5)
	L(poseLine("swing sword, slow motion", seeOf(B, A)))
	shot("swing_1", 0.9)
	L(poseLine("swing sword, slow motion", seeOf(B, A)))
	shot("swing_2", 0.9)
	L(poseLine("swing sword, slow motion", seeOf(B, A)))
	shot("swing_3", 0.9)
	local sw = clientFind(B, "SEE-SWING " .. A.Name, mB)
	check("pose.swing", sw ~= nil, "B's client plays A's swing: " .. tostring(sw))
	task.wait(2.5)
	call(B, "setattr", { name = "LS_SwingSlowMo", value = nil })
	-- the bow drawn, seen from the side
	mB = mark(B)
	call(A, "seq", { { "select", slotOf(A, "bow") }, { "wait", 1.2 }, { "face", away }, { "wait", 0.5 } }, 8)
	local bHold = call(B, "bow", A.Name) or {}
	L(poseLine("bow held", seeOf(B, A)) .. " | bow on B's client: " .. fmt(bHold))
	L("HELD bow (held) on B's client: " .. tostring(call(B, "heldinfo", A.Name)))
	shot("bow_hold", 1.2)
	check("pose.bowHold", bHold.bow == true and bHold.item == "bow" and bHold.inHand == "Left" and (tonumber(bHold.lowAboveFeet) or -9) >= 0.4, string.format(
		"B's client: the bow is in A's %s hand, its lowest point %.2f studs above A's feet and its top %.2f; left hand at %s from the body's centre (right %s); bow state %s",
		tostring(bHold.inHand), tonumber(bHold.lowAboveFeet) or -9, tonumber(bHold.highAboveFeet) or -9, fmt(bHold.leftHand), fmt(bHold.rightHand),
		fmt({ bow = bHold.bow, hold = bHold.hold, drawing = bHold.drawing })))
	call(A, "seq", { { "down" } }, 4)
	task.wait(0.3)
	local bMid = call(B, "bow", A.Name) or {}
	shot("bow_draw_mid", 0.9)
	local bDrawn = call(B, "bow", A.Name) or {}
	L(poseLine("bow drawn", seeOf(B, A)) .. " | bow on B's client: mid-draw " .. fmt(bMid) .. " | drawn " .. fmt(bDrawn))
	L("HELD bow (drawn) on B's client: " .. tostring(call(B, "heldinfo", A.Name)))
	shot("bow_drawn", 1.2)
	local lh = bDrawn.leftHand
	check("pose.bowDrawn", bDrawn.drawing == true and bDrawn.string == true and (tonumber(bDrawn.pull) or 0) >= 0.9 and (tonumber(bDrawn.rightHandToHead) or 9) < 1.4
		and typeof(lh) == "Vector3" and lh.Y > 0 and Vector3.new(lh.X, 0, lh.Z).Magnitude > 1.6, string.format(
		"B's client 1.3 s after A began to draw: drawing=%s, bent string=%s (%s beams), pull %.0f%% (%.0f%% at 0.3 s); bow hand at %s from the body's centre (held: %s), string hand %.2f studs from the head and %.2f from the bow hand (held: %.2f)",
		tostring(bDrawn.drawing), tostring(bDrawn.string), tostring(bDrawn.beams), (tonumber(bDrawn.pull) or 0) * 100, (tonumber(bMid.pull) or 0) * 100, fmt(lh),
		fmt(bHold.leftHand), tonumber(bDrawn.rightHandToHead) or -1, tonumber(bDrawn.handsApart) or -1, tonumber(bHold.handsApart) or -1))
	call(A, "seq", { { "select", sword }, { "up" }, { "wait", 0.9 } }, 6) -- (switching away lets the draw down without a shot)
	local bDown = call(B, "bow", A.Name) or {}
	check("pose.bowLetDown", bDown.drawing ~= true and bDown.string ~= true, "after A switched to the sword mid-draw, B's client: "
		.. fmt({ bow = bDown.bow, drawing = bDown.drawing, string = bDown.string, pull = bDown.pull, beams = bDown.beams, item = bDown.item }))
	local draw = clientFind(B, "action=Draw", mB)
	check("pose.bowDraw", draw ~= nil, "B's client was told A draws the bow: " .. tostring(draw) .. " ; then: "
		.. tostring(clientFind(B, "cancelled=true", mB) or clientFind(B, "action=Release", mB)))
	call(B, "track", {})
end

local function lootCheck()
	local _, ra = parts(A)
	if not (ra and Loot) then
		check("loot.takenIsGone", false, "no character or no LootService")
		return
	end
	L(duel(A, B, 8))
	_, ra = parts(A)
	local pos = (ra :: BasePart).Position + duelDir * 3
	local model = Loot.spawnGroundItem("bandage", 2, pos + Vector3.new(0, 1.5, 0))
	task.wait(1.5)
	local near = { x = pos.X, y = pos.Y, z = pos.Z }
	local itemsA, itemsB = call(A, "items", { near = near, radius = 12 }) or {}, call(B, "items", { near = near, radius = 12 }) or {}
	L("LOOT before: A's client has " .. #itemsA .. " [" .. table.concat(itemsA, " ; ") .. "] B's client has " .. #itemsB .. " [" .. table.concat(itemsB, " ; ") .. "]")
	local before = Inv.count(A, "bandage")
	call(A, "face", near)
	call(B, "face", near)
	task.wait(0.7)
	local res = call(A, "prompt", { radius = 10 }, 8)
	task.wait(1.2)
	local after = Inv.count(A, "bandage")
	local itemsA2, itemsB2 = call(A, "items", { near = near, radius = 12 }) or {}, call(B, "items", { near = near, radius = 12 }) or {}
	local resB = call(B, "prompt", { radius = 10 }, 8)
	task.wait(0.8)
	L("LOOT after: A used " .. tostring(res) .. " ; A's client has " .. #itemsA2 .. ", B's client has " .. #itemsB2 .. " [" .. table.concat(itemsB2, " ; ")
		.. "] ; B tried: " .. tostring(resB) .. " ; B bandages " .. Inv.count(B, "bandage"))
	check("loot.takenIsGone", after == before + 2 and #itemsB >= 1 and #itemsB2 == #itemsB - 1 and (model == nil or model.Parent == nil) and Inv.count(B, "bandage") == 0,
		string.format("a bandage x2 on the ground between them: A's bag %d -> %d; B's client saw %d item(s) there before and %d after; the server's item is gone=%s; B then got %d",
			before, after, #itemsB, #itemsB2, tostring(model == nil or model.Parent == nil), Inv.count(B, "bandage")))
end

local function useChecks()
	Inv.clear(A)
	L("give A: sword " .. Inv.give(A, "sword", 1) .. " apple " .. Inv.give(A, "apple", 2) .. " water_bottle " .. Inv.give(A, "water_bottle", 1))
	task.wait(0.4)
	PS.addHunger(A, -45)
	PS.addThirst(A, -55)
	task.wait(0.3)
	L(duel(A, B, 8))
	call(B, "track", { target = A.Name, seconds = 12 })
	for _, item in ipairs({ { "apple", "Hunger", 1.2 }, { "water_bottle", "Thirst", 1.6 } }) do
		local id, stat, useTime = item[1], item[2], item[3]
		local v0 = tonumber(A:GetAttribute(stat)) or -1
		local n0 = Inv.count(A, id)
		local mB = mark(B)
		call(A, "seq", { { "select", slotOf(A, id) }, { "wait", 0.9 }, { "down" }, { "wait", useTime * 0.5 } }, 10)
		local mid = seeOf(B, A)
		L(poseLine("using " .. id, mid) .. " using=" .. tostring(mid.using))
		shot("use_" .. id, useTime * 0.5 + 0.25)
		call(A, "seq", { { "up" }, { "wait", 0.5 } }, 6)
		local v1 = tonumber(A:GetAttribute(stat)) or -1
		local told = clientFind(B, "SEE-PATTR " .. A.Name .. ".UsingItem=" .. id, mB)
		check("use." .. id, v1 > v0 + 3 and Inv.count(A, id) == n0 - 1 and told ~= nil and mid.held == id, string.format(
			"A uses %s: %s %.1f -> %.1f on the server, bag %d -> %d; B's client saw A.UsingItem=%s (%s) with the %s in A's hand (%s)", id, stat, v0, v1, n0,
			Inv.count(A, id), id, tostring(told ~= nil), id, tostring(mid.held)))
	end
end

local function groundHigh(x: number, z: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local hit = workspace:Raycast(Vector3.new(x, 900, z), Vector3.new(0, -1800, 0), params)
	return if hit then hit.Position else nil
end

local function borderCheck()
	local center, radius = Arena.getBorder()
	local _, ra = parts(A)
	if not ra then
		return
	end
	local dir = Vector3.new(ra.Position.X - center.X, 0, ra.Position.Z - center.Z).Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local pa = center + dir * (radius + 14)
	local pb = pa + side * 7
	local ga, gb = groundHigh(pa.X, pa.Z), groundHigh(pb.X, pb.Z)
	L(string.format("BORDER centre %s radius %.1f; standing A at %s (ground %s) and B at %s (ground %s)", v3(center), radius, v3(pa), if ga then v3(ga) else "none", v3(pb),
		if gb then v3(gb) else "none"))
	if not (ga and gb) then
		check("border.hurtsBoth", nil, "no ground found outside the ring")
		return
	end
	setHealth(A)
	setHealth(B)
	local mA, mB = mark(A), mark(B)
	standAt(A, pa.X, pa.Z, center, ga.Y)
	standAt(B, pb.X, pb.Z, center, gb.Y)
	task.wait(4.0)
	local _, ra2 = parts(A)
	local _, rb2 = parts(B)
	local outA = ra2 ~= nil and not Arena.isInsideBorder(ra2.Position)
	local outB = rb2 ~= nil and not Arena.isInsideBorder(rb2.Position)
	local hA, hB = health(A), health(B)
	local dA = clientFind(A, "cause=Border", mA)
	local dB = clientFind(B, "cause=Border", mB)
	shot("border", 1.0)
	check("border.hurtsBoth", outA and outB and hA < 99 and hB < 99 and dA ~= nil and dB ~= nil, string.format(
		"both 14 studs outside the ring (radius %.0f) for 4 s: A outside=%s health %.1f, B outside=%s health %.1f; A's client told: %s ; B's client told: %s", radius,
		tostring(outA), hA, tostring(outB), hB, tostring(dA), tostring(dB)))
	L(duel(A, B, 8))
	setHealth(A)
	setHealth(B)
end

-- A kills B with the sword; returns the marks taken before the killing blows
local function killB(tag: string): (number, number)
	local sword = slotOf(A, "sword") or (Inv.give(A, "sword", 1) > 0 and slotOf(A, "sword")) or 1
	setHealth(B)
	L(duel(A, B, 7))
	local mA, mB = mark(A), mark(B)
	diedAt[B.Name] = nil
	for i = 1, 6 do
		-- (the third blow is the last one when the first two land: a short settle, so the fall itself gets a picture)
		attack(tag .. " blow " .. i, { { "select", sword }, { "wait", if i == 1 then 0.8 else 0.05 }, { "face", B.Name }, { "wait", 0.3 }, { "click" } },
			if i >= 3 then 0.3 else 0.75)
		if B:GetAttribute("Alive") ~= true then
			break
		end
	end
	-- the fall, the fade and the empty ground, as every client window shows them (the bots log their BODY lines by themselves)
	local t0 = diedAt[B.Name] or os.clock()
	local function untilAfter(s: number)
		local w = s - (os.clock() - t0)
		if w > 0 then
			task.wait(w)
		end
	end
	L(string.format("DEFEAT pictures from %.2f s after the fall", os.clock() - t0))
	shot(tag .. "_defeat_fall", 0.1)
	untilAfter(2.05)
	shot(tag .. "_defeat_fade", 0.1)
	untilAfter(3.3)
	shot(tag .. "_defeat_gone", 0.3)
	untilAfter(4.2)
	return mA, mB
end

local function deathChecks(tag: string, mA: number, mB: number, expectPlacement: number)
	local died = clientFind(B, "REMOTE YouDied", mB)
	local kfA, kfB = clientFind(A, "REMOTE KillFeed", mA), clientFind(B, "REMOTE KillFeed", mB)
	local guiB = call(B, "gui") or {}
	L("GUI[" .. tag .. " death] " .. B.Name .. ": " .. string.sub(table.concat(guiB, " ; "), 1, 1800))
	local idText = "killerUserId=" .. tostring(A.UserId)
	check(tag .. ".deathCard", died ~= nil and string.find(died, idText, 1, true) ~= nil and string.find(died, "placement=" .. expectPlacement, 1, true) ~= nil
		and B:GetAttribute("Alive") ~= true, "B's client got: " .. tostring(died))
	local hB, hudB = hudOf(B)
	-- (with a third contender alive B watches its killer at once: the spectator's view keeps the compass block)
	local spect = (call(B, "state") or {}).spectating
	if spect then
		check(tag .. ".deathCardCoversHud", hB.Hotbar == false and hB.Vitals == false, "B's screen, defeated and watching (hotbar and vitals down; the spectator keeps the compass block) " .. tostring(spect) .. ": " .. hudB)
	else
		check(tag .. ".deathCardCoversHud", hudHidden(hB), "B's screen with the death card: " .. hudB)
	end
	-- the evening UI: the defeat strip along the bottom, "Defeated by <killer> · <weapon>"
	local stripHas, stripText = guiHas(B, "defeated by")
	check(tag .. ".defeatStrip", stripHas and string.find(stripText, A.DisplayName, 1, true) ~= nil, "B's screen: " .. string.sub(stripText, 1, 300))
	local function feedOk(line: string?): boolean
		return line ~= nil and string.find(line, idText, 1, true) ~= nil and string.find(line, "victimUserId=" .. tostring(B.UserId), 1, true) ~= nil
	end
	check(tag .. ".killFeed", feedOk(kfA) and feedOk(kfB), "A's client: " .. tostring(kfA) .. " | B's client: " .. tostring(kfB))
	local hasA, textA = guiHas(A, B.DisplayName)
	local hasB, textB = guiHas(B, A.DisplayName)
	L("GUI[" .. tag .. " feed] on A with B's name: " .. string.sub(textA, 1, 400) .. " | on B with A's name: " .. string.sub(textB, 1, 400))
	check(tag .. ".killCredit", A:GetAttribute("Kills") == 1 and B:GetAttribute("Placement") == expectPlacement and B:GetAttribute("KilledBy") == A.UserId,
		string.format("A.Kills=%s B.Placement=%s B.KilledBy=%s (A is %d); kill feed text on A's screen=%s, A's name on B's screen=%s", tostring(A:GetAttribute("Kills")),
			tostring(B:GetAttribute("Placement")), tostring(B:GetAttribute("KilledBy")), A.UserId, tostring(hasA), tostring(hasB)))
	shot(tag .. "_death", 1.0)
end

local function resultChecks(tag: string, mA: number, mB: number, winner: Player, others: { Player })
	if not waitPhase("Ending", 6) then
		check(tag .. ".ending", false, "the round did not end, phase=" .. phase() .. " AliveCount=" .. tostring(GS:GetAttribute("AliveCount")))
		return
	end
	task.wait(1.6)
	local tEnd = os.clock()
	-- the evening UI (owner, 18 Nov): no VICTORY card; the winner gets one quiet "You won" line for about 5 s, everyone
	-- else one quiet line, and the full result is on the board in the lobby
	local idLine = "GS WinnerUserId=" .. tostring(winner.UserId)
	local vicW = clientFind(winner, "style=Victory", mA)
	-- (the bots log the line themselves: the checks here come several seconds after the round ended)
	local shownW, tShown = clientFind(winner, "YOUWON shown", mA)
	local hasW, textW = shownW ~= nil, tostring(shownW)
	local goneLine, tGone = clientFind(winner, "YOUWON gone", mA)
	local _, tVic = clientFind(winner, "style=Victory", mA)
	L(string.format("YOUWON on %s: announce at %s, line shown at %s, gone at %s (%s s on screen)", winner.Name, tostring(tVic), tostring(tShown), tostring(tGone),
		if tShown and tGone then string.format("%.1f", tGone - tShown) else "?"))
	local detail = { string.format("server: WinnerName=%s WinnerUserId=%s; winner's client: announce %s ; its WinnerUserId attribute seen=%s ; texts with 'You won': %s",
		tostring(GS:GetAttribute("WinnerName")), tostring(GS:GetAttribute("WinnerUserId")), tostring(vicW), tostring(clientFind(winner, idLine, mA) ~= nil),
		string.sub(textW, 1, 300)) }
	local ok = GS:GetAttribute("WinnerUserId") == winner.UserId and vicW ~= nil and string.find(vicW, "winnerUserId=" .. tostring(winner.UserId), 1, true) ~= nil and hasW
	for _, p in ipairs(others) do
		if p.Parent == Players then
			local line = clientFind(p, "YOUWON shown", mB)
			local has, text = line ~= nil, tostring(line)
			local all = call(p, "gui") or {}
			L("GUI[" .. tag .. " result] " .. p.Name .. ": " .. string.sub(table.concat(all, " ; "), 1, 1500))
			ok = ok and not has
			table.insert(detail, string.format("%s's client: texts with 'You won': [%s]; its result lines: %s", p.Name, string.sub(text, 1, 200),
				string.sub(table.concat(call(p, "gui", "standing") or {}, " ; "), 1, 300)))
		end
	end
	local allW = call(winner, "gui") or {}
	L("GUI[" .. tag .. " result] " .. winner.Name .. ": " .. string.sub(table.concat(allW, " ; "), 1, 1500))
	check(tag .. ".youWonById", ok, table.concat(detail, " | "))
	local _, hudW = hudOf(winner)
	L("HUD[" .. tag .. " result] " .. winner.Name .. ": " .. hudW)
	shot(tag .. "_result", 1.0)
	-- the line goes after about 5 s (checked alongside whatever comes next)
	task.spawn(function()
		local w = 6.6 - (os.clock() - tEnd)
		if w > 0 then
			task.wait(w)
		end
		local _, tG = clientFind(winner, "YOUWON gone", mA)
		local still, stillText = guiHas(winner, "you won")
		local onFor = if tShown and tG then tG - tShown else nil
		check(tag .. ".youWonFades", not still and onFor ~= nil and onFor >= 3.5 and onFor <= 7.5, string.format(
			"%s's screen: 'You won' shown at %s, gone at %s (%s s on screen); still shown about 8 s after the end=%s %s", winner.Name, tostring(tShown), tostring(tG),
			if onFor then string.format("%.1f", onFor) else "?", tostring(still), string.sub(stillText, 1, 200)))
	end)
end

local function backToLobby(tag: string, players: { Player }): boolean
	local okPhase = waitFor(function()
		return phase() == "Lobby" or phase() == "Intermission"
	end, 60)
	task.wait(2.5)
	local ok = okPhase ~= nil
	local detail = { "phase=" .. phase() }
	for _, p in ipairs(players) do
		if p.Parent == Players then
			local st = call(p, "state") or {}
			local own = st.camType == "Custom" and type(st.camSubject) == "string" and string.find(st.camSubject, p.Name, 1, true) ~= nil
			local good = p:GetAttribute("InArena") ~= true and p:GetAttribute("Alive") ~= true and p.Character ~= nil and st.inArena == false and own and st.inv == ""
				and st.spectating == nil
			ok = ok and good
			table.insert(detail, string.format("%s InArena=%s Alive=%s Kills=%s Wins=%s RoundsPlayed=%s client: inArena=%s cam=%s subject=%s bag='%s' spectating=%s pos=%s",
				p.Name, tostring(p:GetAttribute("InArena")), tostring(p:GetAttribute("Alive")), tostring(p:GetAttribute("Kills")), tostring(p:GetAttribute("Wins")),
				tostring(p:GetAttribute("RoundsPlayed")), tostring(st.inArena), tostring(st.camType), tostring(st.camSubject), tostring(st.inv), tostring(st.spectating),
				fmt(st.pos)))
		end
	end
	check(tag .. ".backToLobby", ok, table.concat(detail, " | "))
	return ok
end

local function rollCallSeen(tag: string, marks: { [Player]: number }, name: string, timeout: number): boolean
	local seenAll = true
	local detail = {}
	for p, m in pairs(marks) do
		if p.Parent == Players then
			local line = waitFor(function()
				return (clientFind(p, "style=RollCall", m))
			end, timeout)
			timeout = 2
			local has = line ~= nil and string.find(line, name, 1, true) ~= nil
			seenAll = seenAll and has
			table.insert(detail, p.Name .. ": " .. (if line then string.sub(line, 1, 420) else "no Roll Call message"))
		end
	end
	check(tag, seenAll, "the Roll Call names " .. name .. " on every client: " .. table.concat(detail, " | "))
	return seenAll
end

local function batchB()
	setupDuel()
	giveKit()
	swordChecks()
	poseChecks()
	useChecks() -- (starts from a small kit: the loot check after it needs a free slot in A's bag)
	lootCheck()
	borderCheck()
	snapshotAll("beforeKill")
	plusOffCheck("plus.offInArena", { A, B }, "both in the arena, 8 studs apart")
	-- a bandage on the ground in A's reach: its Take prompt showed through the VICTORY card
	local _, ra = parts(A)
	if ra and Loot then
		Loot.spawnGroundItem("bandage", 1, ra.Position + duelDir * 3 + Vector3.new(0, 1.5, 0))
	end
	task.wait(1.0)
	local hA, hudA = hudOf(A)
	check("hud.beforeTheCards", hA.card == false and hA.pps == true and hA.Hotbar == true and hA.Vitals == true and hA.Top == true,
		"A alive in the round, a bandage on the ground in reach (the probe sees the HUD when it is there): " .. hudA)
	local mA, mB = killB("round1")
	defeatChecks("round1", B, { { "killer", A, mA }, { "victim", B, mB } })
	deathChecks("round1", mA, mB, 2)
	local spec = call(B, "spectate", { op = "start", target = A.Name })
	L("B tries to spectate A after a 2-player round was decided: " .. tostring(spec))
	resultChecks("round1", mA, mB, A, { B })
	rollCallSeen("round1.rollCall", { [A] = mA, [B] = mB }, B.DisplayName, 10)
	recapShots("round1.rollCallSky", "round1_rollcall_sky", { A }, { B })
	shot("round1_rollcall", 1.0)
	backToLobby("round1", { A, B })
	boardChecks("round1.board", { A, B }, A)
	chatCheck("round1.chatClosedInLobby", { A, B }, true)
	if PLUS then
		local pa, pb = call(A, "plus") or {}, call(B, "plus") or {}
		check("plus.backInLobby", markOn(pb, A) and markOn(pa, B), "both back in the lobby: A's client has " .. fmt(pa) .. " | B's client has " .. fmt(pb))
	end
	if roundStartChecks("round2") then
		snapshotAll("round2")
		local h2, hud2 = hudOf(A)
		check("round2.hudAndPromptsBack", h2.card == false and h2.pps == true and h2.Hotbar == true and h2.Vitals == true, "A in round two: " .. hud2)
		plusOffCheck("round2.plusOffInArena", { A, B }, "round two, both in the arena")
	end
end

local function batchB2()
	setupDuel()
	giveKit()
	RAW_CLAIMS = { 15, 16.5, 18 }
	local sword = slotOf(A, "sword")
	call(A, "seq", { { "select", slotOf(A, "bow") }, { "wait", 0.5 }, { "select", sword }, { "wait", 0.7 } }, 6)
	for _, d in ipairs(RAW_CLAIMS) do
		setHealth(B)
		L(duel(A, B, d))
		local r = attack("sword raw claim@" .. d, { { "face", B.Name }, { "wait", 0.3 }, { "remote", "MeleeSwing", "raw", B.Name } })
		check("melee.sword.rawClaim@" .. d, r.dealt < 0.5, string.format("a modified client claiming a sword hit from %.1f studs: B lost %.1f; refusals: %s", d, r.dealt,
			refusals()))
	end
	setHealth(B)
	poseChecks()
	useChecks()
	lootCheck()
end

local function batchC()
	local C = P3 :: Player
	setupDuel()
	Inv.give(A, "sword", 1)
	-- the bystander stands 9 studs beside the duel line and looks at the spot where B will fall
	if duelBase then
		local perp = Vector3.new(-duelDir.Z, 0, duelDir.X)
		local spot = duelBase + duelDir * 3.5 + perp * 9
		local fallAt = duelBase + duelDir * 7
		standAt(C, spot.X, spot.Z, fallAt, duelBase.Y)
		task.wait(0.4)
		local _, rc0 = parts(C)
		call(C, "track", { target = Vector3.new(fallAt.X, (if rc0 then rc0.Position.Y else duelBase.Y) - 1.0, fallAt.Z), seconds = 22 })
	end
	local mC = mark(C)
	local mA, mB = killB("round1")
	defeatChecks("round1", B, { { "killer", A, mA }, { "victim", B, mB }, { "bystander", C, mC } })
	deathChecks("round1", mA, mB, 3)
	-- the evening build: a defeated contender watches the one who defeated them, by itself
	local autoLine = waitFor(function()
		return (clientFind(B, "SPECTATING " .. A.Name, mB))
	end, 6)
	local stAuto = call(B, "state") or {}
	check("round1.autoSpectateKiller", autoLine ~= nil and stAuto.spectating == A.Name, string.format(
		"without being asked, B's client: %s ; now spectating=%s camera subject=%s; server focus for B=%s", tostring(autoLine), tostring(stAuto.spectating),
		tostring(stAuto.camSubject), if B.ReplicationFocus then B.ReplicationFocus:GetFullName() else "nil"))
	task.wait(0.3)
	check("round1.goesOnWithTwo", phase() == "Active" and GS:GetAttribute("AliveCount") == 2, "phase=" .. phase() .. " AliveCount=" .. tostring(GS:GetAttribute("AliveCount")))
	-- B watches A, through its own respawn into the lobby
	local res = call(B, "spectate", { op = "start", target = A.Name })
	task.wait(1.5)
	local st = call(B, "state") or {}
	local _, ra = parts(A)
	local s = seeOf(B, A)
	check("spectate.start", st.spectating == A.Name and B.ReplicationFocus ~= nil and s.pos ~= nil and ra ~= nil and (s.pos - ra.Position).Magnitude < 3, string.format(
		"B asked to watch A (%s): B's client spectating=%s camera subject=%s; the server's streaming focus for B=%s; on B's screen A stands %.2f studs from the server's position",
		tostring(res), tostring(st.spectating), tostring(st.camSubject), if B.ReplicationFocus then B.ReplicationFocus:GetFullName() else "nil",
		if s.pos and ra then (s.pos - ra.Position).Magnitude else -1))
	shot("spectate_A", 1.0)
	plusOffCheck("plus.offWhileSpectating", { B }, "B in the lobby, spectating A")
	task.wait(3.0) -- B's new lobby character has loaded by now
	st = call(B, "state") or {}
	s = seeOf(B, A)
	check("spectate.survivesRespawn", st.spectating == A.Name and B.ReplicationFocus ~= nil and s.char == true, string.format(
		"after B's respawn in the lobby: spectating=%s camera subject=%s server focus=%s B's own position=%s A still on B's client=%s", tostring(st.spectating),
		tostring(st.camSubject), if B.ReplicationFocus then B.ReplicationFocus:GetFullName() else "nil", fmt(st.pos), tostring(s.char)))
	res = call(B, "spectate", { op = "next" })
	task.wait(2.0)
	st = call(B, "state") or {}
	local sc = seeOf(B, C)
	local _, rc = parts(C)
	check("spectate.cycle", st.spectating == C.Name and sc.pos ~= nil and rc ~= nil and (sc.pos - rc.Position).Magnitude < 3, string.format(
		"next target (%s): spectating=%s server focus=%s; on B's screen %s stands %.2f studs from the server's position", tostring(res), tostring(st.spectating),
		if B.ReplicationFocus then B.ReplicationFocus:GetFullName() else "nil", C.Name, if sc.pos and rc then (sc.pos - rc.Position).Magnitude else -1))
	shot("spectate_C", 1.0)
	call(B, "spectate", { op = "prev" })
	-- the dusk Roll Call (the round clock runs ARGS.timeScale times faster)
	local ok = rollCallSeen("rollCall.dusk", { [A] = mA, [B] = mB, [C] = mC }, B.DisplayName, 90)
	if ok then
		call(C, "track", {})
		recapShots("rollCall.duskSky", "rollcall_dusk_sky", { A, C }, { B })
		task.wait(1.5)
		shot("rollcall_dusk_running", 1.2)
	end
	L("clock " .. fmt({ Arena.getClock() }) .. " fallen " .. fmt(Arena.getFallen()))
	-- the border's first stage (round second 210: 35 s after the horn at time scale 6) on every screen
	waitFor(function()
		return (tonumber(GS:GetAttribute("BorderRadius")) or 1800) < 1790
	end, 40)
	borderLook("border.stage1", { A, B, C }, true)
	-- C leaves in the middle of the round
	mA, mB = mark(A), mark(B)
	local t0 = os.clock()
	call(C, "leave")
	local ended = waitPhase("Ending", 12)
	local took = os.clock() - t0
	task.wait(0.5)
	local feed = clientFind(A, "left the arena", mA)
	check("leave.endsRound", ended and GS:GetAttribute("WinnerUserId") == A.UserId, string.format(
		"C left mid-round: phase=%s %.1f s later, WinnerName=%s WinnerUserId=%s AliveCount=%s; A's kill feed: %s", phase(), took, tostring(GS:GetAttribute("WinnerName")),
		tostring(GS:GetAttribute("WinnerUserId")), tostring(GS:GetAttribute("AliveCount")), tostring(feed)))
	resultChecks("leave", mA, mB, A, { B })
	backToLobby("leave", { A, B })
	boardChecks("leave.board", { A, B }, A)
	L(string.format("after the round: A Wins=%s RoundsPlayed=%s TotalKills=%s", tostring(A:GetAttribute("Wins")), tostring(A:GetAttribute("RoundsPlayed")),
		tostring(A:GetAttribute("TotalKills"))))
end

local function batchD()
	setupDuel()
	lootCheck()
	-- a third client joins in the middle of the round
	local before = #Players:GetPlayers()
	local okAdd, errAdd = pcall(function()
		STS:AddPlayers(1)
	end)
	L("AddPlayers(1): " .. tostring(okAdd) .. " " .. tostring(errAdd))
	local joined = waitFor(function()
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= A and p ~= B and botReady[p] and p.Character then
				return p
			end
		end
		return nil
	end, 90)
	if not joined then
		check("late.join", false, "no third client with a bot within 90 s (players now " .. #Players:GetPlayers() .. ", before " .. before .. ")")
		return
	end
	local J = joined :: Player
	P3 = J
	task.wait(2.5)
	local st = call(J, "state") or {}
	check("late.waitsInLobby", phase() == "Active" and not Round.isContender(J) and J:GetAttribute("InArena") ~= true and st.inArena == false, string.format(
		"%s joined during the round: phase=%s contender=%s InArena=%s; its client: inArena=%s camera=%s subject=%s position=%s", J.Name, phase(),
		tostring(Round.isContender(J)), tostring(J:GetAttribute("InArena")), tostring(st.inArena), tostring(st.camType), tostring(st.camSubject), fmt(st.pos)))
	local has, text = guiHas(J, "next round in")
	local all = call(J, "gui") or {}
	L("GUI[late] " .. J.Name .. ": " .. string.sub(table.concat(all, " ; "), 1, 1200))
	check("late.timer", has and string.find(string.lower(text), "remain", 1, true) ~= nil, "the lobby line on the late joiner's screen: " .. string.sub(text, 1, 300))
	shot("late_lobby", 1.0)
	chatCheck("late.chatClosed", { J }, true)
	task.wait(6.0) -- (for its first seconds HUDController closes the chat window again whenever it opens)
	local c = call(J, "chat", { open = true }) or {}
	check("late.chatOpenLeavesLine", c.active == true and c.overLine ~= true, string.format(
		"the late joiner opens the chat window: open=%s, window x=%s width=%s y=%s height=%s (scale %s) on a screen %s wide; the lobby line shown=%s at x=%s width=%s y=%s height=%s; window over the line=%s",
		tostring(c.active), fmt(c.winX), fmt(c.winW), fmt(c.winY), fmt(c.winH), fmt(c.widthScale), fmt(c.view), tostring(c.lineShown), fmt(c.lineX), fmt(c.lineW),
		fmt(c.lineY), fmt(c.lineH), tostring(c.overLine)))
	shot("late_chat_open", 1.0)
	call(J, "chat", { open = false })
	local res = call(J, "spectate", { op = "start", target = A.Name })
	task.wait(2.0)
	st = call(J, "state") or {}
	local s = seeOf(J, A)
	local _, ra = parts(A)
	check("late.spectate", st.spectating == A.Name and s.pos ~= nil and ra ~= nil and (s.pos - ra.Position).Magnitude < 3 and J.ReplicationFocus ~= nil, string.format(
		"the late joiner watches A (%s): spectating=%s camera subject=%s server focus=%s; on its screen A stands %.2f studs from the server's position", tostring(res),
		tostring(st.spectating), tostring(st.camSubject), if J.ReplicationFocus then J.ReplicationFocus:GetFullName() else "nil",
		if s.pos and ra then (s.pos - ra.Position).Magnitude else -1))
	shot("late_spectate", 1.2)
	plusOffCheck("late.plusOffWhileSpectating", { J }, "the late joiner in the lobby, spectating A")
	-- B leaves in the middle of the round: A is the last one standing
	local mA, mJ = mark(A), mark(J)
	local t0 = os.clock()
	call(B, "leave")
	local ended = waitPhase("Ending", 12)
	local took = os.clock() - t0
	task.wait(0.5)
	check("leave.endsRound", ended and GS:GetAttribute("WinnerUserId") == A.UserId, string.format(
		"B left mid-round: phase=%s %.1f s later, WinnerName=%s WinnerUserId=%s; A's kill feed: %s ; the watcher's: %s", phase(), took,
		tostring(GS:GetAttribute("WinnerName")), tostring(GS:GetAttribute("WinnerUserId")), tostring(clientFind(A, "left the arena", mA)),
		tostring(clientFind(J, "left the arena", mJ))))
	resultChecks("leave", mA, mJ, A, { J })
	task.wait(1.0)
	st = call(J, "state") or {}
	L("the watcher after the round was decided: spectating=" .. tostring(st.spectating) .. " camera subject=" .. tostring(st.camSubject))
	backToLobby("leave", { A, J })
	boardChecks("late.board", { A, J }, A, J)
	-- the next round takes the late joiner
	if waitPhase("Countdown", 40) then
		check("late.pickedNextRound", Round.isContender(J) and Round.isContender(A) and GS:GetAttribute("Practice") == false and GS:GetAttribute("StartedCount") == 2,
			string.format("next round: contenders=%s Practice=%s StartedCount=%s cut=%s", contenderNames(), tostring(GS:GetAttribute("Practice")),
				tostring(GS:GetAttribute("StartedCount")), tostring(GS:GetAttribute("LaunchCut"))))
		if waitPhase("Active", 40) then
			task.wait(1.2)
			st = call(J, "state") or {}
			check("late.playsNextRound", st.alive == true and st.frozen == false and st.launchShot ~= true and st.camType == "Custom", string.format(
				"the late joiner after the horn: alive=%s frozen=%s launchShot=%s camera=%s subject=%s", tostring(st.alive), tostring(st.frozen), tostring(st.launchShot),
				tostring(st.camType), tostring(st.camSubject)))
		end
	else
		check("late.pickedNextRound", false, "no Countdown within 40 s, phase=" .. phase())
	end
end

-- one of two contenders leaves during the Countdown, in the middle of the launch shot
local function batchE()
	if not waitPhase("Countdown", 60) then
		check("countdownLeave.cancelled", false, "no Countdown, phase=" .. phase())
		return
	end
	task.wait(4.0)
	local st0 = call(A, "state") or {}
	L(string.format("mid-countdown: cut=%s A launchShot=%s camera=%s; RoundsPlayed A=%s", tostring(GS:GetAttribute("LaunchCut")), tostring(st0.launchShot),
		tostring(st0.camType), tostring(A:GetAttribute("RoundsPlayed"))))
	local mA = mark(A)
	local played = A:GetAttribute("RoundsPlayed")
	local t0 = os.clock()
	call(B, "leave")
	local back = waitFor(function()
		return phase() == "Lobby" or phase() == "Intermission"
	end, 10)
	local took = os.clock() - t0
	task.wait(3.0)
	local toast = clientFind(A, "Round cancelled", mA)
	local victory = clientFind(A, "style=Victory", mA)
	local st = call(A, "state") or {}
	local hasV, textV = guiHas(A, "victory")
	local all = call(A, "gui") or {}
	L("GUI[cancelled] " .. A.Name .. ": " .. string.sub(table.concat(all, " ; "), 1, 900))
	local own = st.camType == "Custom" and type(st.camSubject) == "string" and string.find(st.camSubject, A.Name, 1, true) ~= nil
	check("countdownLeave.cancelled", back ~= nil and toast ~= nil and victory == nil and not hasV and A:GetAttribute("InArena") ~= true and st.launchShot ~= true and own
		and st.inArena == false and A:GetAttribute("RoundsPlayed") == played and (GS:GetAttribute("WinnerName") or "") == "", string.format(
		"B left %.1f s before... the Countdown ended %.1f s after the leave: phase=%s; A's client: toast=%s ; winner card=%s (texts with VICTORY: [%s]); launchShot=%s camera=%s subject=%s inArena=%s position=%s; RoundsPlayed %s -> %s; WinnerName='%s'",
		0.3, took, phase(), tostring(toast), tostring(victory), string.sub(textV, 1, 120), tostring(st.launchShot), tostring(st.camType), tostring(st.camSubject),
		tostring(st.inArena), fmt(st.pos), tostring(played), tostring(A:GetAttribute("RoundsPlayed")), tostring(GS:GetAttribute("WinnerName"))))
	shot("cancelled", 1.0)
	task.wait(2.0)
	local has, text = guiHas(A, "round")
	L("the lobby line for the one left alone (live rules: 2 needed): " .. string.sub(text, 1, 300) .. " | phase=" .. phase() .. " SoloStartAt="
		.. tostring(GS:GetAttribute("SoloStartAt")))
end

-- the fill rule (RoundService): a third client joins during the lobby countdown. The Studio switch GameState.FillTest
-- turns the rule on (set before the release); the Intermission is ARGS.intermission seconds so a client has time to boot.
local function batchG()
	if not waitPhase("Intermission", 20) then
		check("fill.joinExtendsCountdown", false, "no Intermission, phase=" .. phase())
		return
	end
	local length = tonumber(Config.Round.IntermissionTime) or 25
	local cap = math.max(length, tonumber(Config.Round.FillMaxTime) or 90)
	local e0 = tonumber(GS:GetAttribute("PhaseEndsAt")) or 0
	local began = e0 - length
	L(string.format("FILL the Intermission ends in %.1f s (IntermissionTime %s, FillMaxTime %s, FillTest=%s)", e0 - workspace:GetServerTimeNow(), tostring(length),
		tostring(Config.Round.FillMaxTime), tostring(GS:GetAttribute("FillTest"))))
	local mA, mB = mark(A), mark(B)
	local J: Player? = nil
	local joinedAt = 0
	local conn = Players.PlayerAdded:Connect(function(p)
		if not J then
			J = p
			joinedAt = workspace:GetServerTimeNow()
		end
	end)
	local okAdd, errAdd = pcall(function()
		STS:AddPlayers(1)
	end)
	L("AddPlayers(1): " .. tostring(okAdd) .. " " .. tostring(errAdd))
	waitFor(function()
		return J ~= nil or phase() ~= "Intermission"
	end, 90)
	conn:Disconnect()
	local joiner = J
	if not (joiner and phase() == "Intermission") then
		check("fill.joinExtendsCountdown", nil, "the third client did not join during the Intermission (phase now " .. phase() .. ", joined=" .. tostring(joiner ~= nil)
			.. "): not tested")
		return
	end
	task.wait(1.5)
	local e1 = tonumber(GS:GetAttribute("PhaseEndsAt")) or 0
	local toastA, toastB = clientFind(A, "A contender has arrived", mA), clientFind(B, "A contender has arrived", mB)
	local _, lineA = guiHas(A, "next round")
	check("fill.joinExtendsCountdown", e1 > e0 + 1 and e1 <= began + cap + 1 and math.abs(e1 - (joinedAt + length)) < 3 and toastA ~= nil and toastB ~= nil, string.format(
		"%s joined %.1f s into a %d-second lobby countdown: its end moved from %.1f s to %.1f s after the countdown began (%.1f s after the join; the limit is %d s); A's client was told: %s ; B's: %s ; A's lobby line: %s",
		joiner.Name, joinedAt - began, length, e0 - began, e1 - began, e1 - joinedAt, cap, tostring(toastA), tostring(toastB ~= nil), string.sub(lineA, 1, 200)))
	shot("fill_lobby", 1.0)
	if e1 > e0 + 2 then
		local w = e0 + 1.2 - workspace:GetServerTimeNow()
		if w > 0 then
			task.wait(w)
		end
		check("fill.noPickAtTheOldTime", phase() == "Intermission", string.format("1.2 s after the old end: phase=%s, the countdown now ends in %.1f s", phase(),
			(tonumber(GS:GetAttribute("PhaseEndsAt")) or 0) - workspace:GetServerTimeNow()))
	end
	P3 = joiner
	EXPECT = 3
	local started = waitFor(function()
		return phase() == "Countdown"
	end, math.max(5, e1 - workspace:GetServerTimeNow() + 20))
	local at = workspace:GetServerTimeNow()
	check("fill.roundTakesAllThree", started ~= nil and GS:GetAttribute("StartedCount") == 3 and Round.isContender(joiner) and GS:GetAttribute("Practice") == false,
		string.format("the round was picked %.1f s after the countdown began (new end %.1f): contenders=%s StartedCount=%s Practice=%s", at - began, e1 - began,
			contenderNames(), tostring(GS:GetAttribute("StartedCount")), tostring(GS:GetAttribute("Practice"))))
end

-- batch H: the evening build with two players (mp-retest2) ---------------------------------------------------------------
local function terrainAt(x: number, z: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = false
	local hit = workspace:Raycast(Vector3.new(x, 900, z), Vector3.new(0, -1800, 0), params)
	return if hit then hit.Position else nil
end
-- stands p on the terrain at (x, z) (trees' crowns and limbs above are ignored), facing lookAt
local function placeAt(p: Player, x: number, z: number, lookAt: Vector3?): Vector3?
	local hum, root = parts(p)
	local g = terrainAt(x, z)
	if not (hum and root and g and p.Character) then
		return nil
	end
	local pos = g + Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.15, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	local target = if lookAt then Vector3.new(lookAt.X, pos.Y, lookAt.Z) else pos + Vector3.new(0, 0, -1)
	if (target - pos).Magnitude < 0.05 then
		target = pos + Vector3.new(0, 0, -1)
	end
	p.Character:PivotTo(CFrame.lookAt(pos, target))
	return pos
end
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end
local function wildOf(p: Player): { any }
	local w = call(p, "probe", { kind = "wild" }) or {}
	return w.list or {}, w
end
local function linesWith(p: Player, from: number, needle: string): { string }
	local out = {}
	local store = clientLines[p.Name] or {}
	for i = from + 1, #store do
		if string.find(store[i], needle, 1, true) then
			table.insert(out, store[i])
		end
	end
	return out
end
-- did p's client get squirrel `id` in one of `states` since `from`
local function wildSaw(p: Player, from: number, id: number, states: { number }): string?
	for _, line in ipairs(linesWith(p, from, "WILD ")) do
		for _, st in ipairs(states) do
			if string.find(line, " " .. id .. ":" .. st .. "@", 1, true) then
				return string.match(line, "^([%d%.]+)") .. " " .. id .. ":" .. st
			end
		end
	end
	return nil
end

local function batchH()
	local Wild = req(Services, "WildlifeService")
	local Cooking = req(Services, "CookingService")
	local Hazard = req(Services, "HazardService")
	local TreeClimb = req(Shared, "TreeClimb")
	workspace:SetAttribute("DevHazardOff", true) -- (the director calls nothing; the tests below call their own)
	local huntedBy: { string } = {}
	if Wild and Wild.hunted then
		Wild.hunted:Connect(function(p, weaponId)
			table.insert(huntedBy, tostring(p and p.Name) .. ":" .. tostring(weaponId))
			L("SIGNAL hunted by " .. tostring(p and p.Name) .. " with " .. tostring(weaponId))
		end)
	end
	local _, ra0 = parts(A)
	if not ra0 then
		return
	end
	-- a climbable tree of the new (Blender TC) kind, near A's plate, on fairly level ground
	local best, bestD = nil, math.huge
	for _, trunk in ipairs(CollectionService:GetTagged("Climbable")) do
		if trunk:IsA("BasePart") and trunk:IsDescendantOf(workspace) and TreeClimb and #TreeClimb.perchesOf(trunk) > 0 then
			local d = flatDist(trunk.Position, ra0.Position)
			if d < bestD and d > 20 then
				local model = trunk.Parent
				local g1, g2 = terrainAt(trunk.Position.X + 7, trunk.Position.Z), terrainAt(trunk.Position.X - 7, trunk.Position.Z)
				if model and g1 and g2 and math.abs(g1.Y - g2.Y) < 3 then
					best, bestD = trunk, d
				end
			end
		end
	end
	if not best then
		check("tree.found", false, "no climbable tree with perches near A")
		return
	end
	local trunk = best :: BasePart
	local tree = trunk.Parent :: Instance
	local axis = trunk.Position
	local base = terrainAt(axis.X, axis.Z) or axis
	local meshCount = 0
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("MeshPart") then
			meshCount += 1
		end
	end
	local perches = TreeClimb.perchesOf(trunk)
	L(string.format("TREE %s (%s, trunk %s %s, %d mesh parts, %d perches, top perch %.1f above the ground) %.0f studs from A's plate", tree:GetFullName(), tree.ClassName,
		trunk.Name, trunk.ClassName, meshCount, #perches, perches[#perches].WorldPosition.Y - base.Y, bestD))
	-- everyone to the tree: A 5 studs from the trunk, B 14 studs on the other side
	placeAt(A, base.X + 5, base.Z, base)
	placeAt(B, base.X - 14, base.Z + 3, base)
	task.wait(3.0) -- (the area streams in on both clients)

	-- 1. squirrels ---------------------------------------------------------------------------------------------------
	workspace:SetAttribute("WildlifeTest", "near:5")
	task.wait(0.2)
	workspace:SetAttribute("WildlifeTest", "calm")
	task.wait(3.0)
	local listA, wA = wildOf(A)
	local listB, wB = wildOf(B)
	local byB = {}
	for _, s in ipairs(listB) do
		byB[s.id] = s
	end
	local shared, near = 0, 0
	for _, s in ipairs(listA) do
		if s.dist < 60 and s.state ~= 0 then
			near += 1
			local o = byB[s.id]
			if o and (o.pos - s.pos).Magnitude < 2 and o.state == s.state then
				shared += 1
			end
		end
	end
	check("squirrel.sameOnBoth", near > 0 and shared == near, string.format(
		"%d squirrels within 60 studs on A's client, %d of them at the same spot and doing the same on B's; A draws %s (%s mesh parts, e.g. %s; %s) | B draws %s (%s mesh parts; %s); stats %s",
		near, shared, tostring(wA.drawn), tostring(wA.meshParts), tostring(wA.sample), tostring(wA.attr), tostring(wB.drawn), tostring(wB.meshParts), tostring(wB.attr),
		fmt(Wild and Wild.stats())))
	shot("squirrels", 1.0)
	-- flee and climb, seen by both
	local function groundSquirrel(except: number?): any
		local pick, pd = nil, math.huge
		for _, s in ipairs((wildOf(A))) do
			if s.id ~= except and s.state >= 1 and s.state <= 4 and s.dist < pd and s.dist < 80 then
				pick, pd = s, s.dist
			end
		end
		return pick
	end
	local s1 = groundSquirrel(nil)
	if s1 then
		local mA, mB = mark(A), mark(B)
		local from = s1.pos + (flat(s1.pos - base).Unit * 12)
		placeAt(A, from.X, from.Z, s1.pos)
		placeAt(B, s1.pos.X - 10, s1.pos.Z + 10, s1.pos)
		task.wait(0.8)
		workspace:SetAttribute("WildlifeTest", "scare")
		local was = call(A, "setting", { name = "sprintMode", value = 2 })
		call(A, "move", { seconds = 1.4, face = s1.pos })
		task.wait(4.5)
		call(A, "setting", { name = "sprintMode", value = was or 0 })
		local fA, fB = wildSaw(A, mA, s1.id, { 5 }), wildSaw(B, mB, s1.id, { 5 })
		local cA, cB = wildSaw(A, mA, s1.id, { 6, 7 }), wildSaw(B, mB, s1.id, { 6, 7 })
		-- the trunk it went up
		local upLine = nil
		for _, line in ipairs(linesWith(A, mA, " " .. s1.id .. ":6@")) do
			upLine = line
		end
		local climbedOn = "?"
		if upLine then
			local x, y, z = string.match(upLine, " " .. s1.id .. ":6@[%-%d]+,[%-%d]+,[%-%d]+>([%-%d]+),([%-%d]+),([%-%d]+)")
			if x then
				local p = Vector3.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number)
				local nb, nd = nil, math.huge
				for _, t in ipairs(CollectionService:GetTagged("Climbable")) do
					if t:IsA("BasePart") then
						local d = flatDist(t.Position, p)
						if d < nd then
							nb, nd = t, d
						end
					end
				end
				if nb then
					climbedOn = string.format("%s (%s %s, %.1f studs from its axis)", nb.Parent and nb.Parent.Name or "?", nb.Name, nb.ClassName, nd)
				end
			end
		end
		check("squirrel.fleeAndClimbOnBoth", fA ~= nil and fB ~= nil and cA ~= nil and cB ~= nil, string.format(
			"A ran at squirrel %d: A's client flee %s climb %s | B's client flee %s climb %s; it went up the trunk of %s", s1.id, tostring(fA), tostring(cA), tostring(fB),
			tostring(cB), climbedOn))
		shot("squirrel_fled", 0.8)
	else
		check("squirrel.fleeAndClimbOnBoth", nil, "no squirrel on the ground near A")
	end
	-- the hunt: A strikes a squirrel on the ground with the sword; it falls still for both, and is gone for B
	workspace:SetAttribute("WildlifeTest", "calm")
	task.wait(1.0)
	Inv.give(A, "sword", 1)
	local s2 = groundSquirrel(s1 and s1.id)
	if s2 then
		local mA, mB = mark(A), mark(B)
		local at = s2.to or s2.pos -- (where it is now: the end of its last move)
		local dir = flat(at - base)
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
		local stand = at + dir * 3.2
		placeAt(A, stand.X, stand.Z, at)
		placeAt(B, at.X - dir.X * 12 + 4, at.Z - dir.Z * 12, at)
		task.wait(0.6)
		local sword = slotOf(A, "sword")
		call(A, "seq", { { "select", sword }, { "wait", 0.8 }, { "face", at + Vector3.new(0, 0.45, 0) }, { "wait", 0.3 }, { "click" }, { "wait", 0.4 } }, 8)
		task.wait(2.5)
		local hitA, hitB = wildSaw(A, mA, s2.id, { 9, -9 }), wildSaw(B, mB, s2.id, { 9, -9 })
		local confirm = clientFind(A, "REMOTE HitConfirm", mA)
		local item = nil
		for _, g in ipairs(CollectionService:GetTagged("GroundItem")) do
			local pos = if g:IsA("Model") then g:GetPivot().Position elseif g:IsA("BasePart") then g.Position else nil
			if pos and g:GetAttribute("ItemId") == "squirrel" and flatDist(pos, s2.pos) < 6 then
				item = g
			end
		end
		task.wait(2.0)
		local after = nil
		for _, s in ipairs((wildOf(B))) do
			if s.id == s2.id then
				after = s
			end
		end
		local goneForB = after == nil or after.state == 0 or after.state == 9 or after.state == -9
		local seenB = call(B, "items", { near = { x = s2.pos.X, y = s2.pos.Y, z = s2.pos.Z }, radius = 8 }) or {}
		check("squirrel.huntedGoneForBoth", hitA ~= nil and hitB ~= nil and goneForB and item ~= nil and #huntedBy > 0, string.format(
			"A struck squirrel %d (state " .. tostring(s2.state) .. " at " .. fmt(at) .. ") with the sword from 3.2 studs: server hunted signal [%s]; A's HitConfirm %s; fell still on A's client %s, on B's %s; B's client now has it %s; a Squirrel item on the ground=%s; B's client sees there: %s",
			s2.id, table.concat(huntedBy, ","), tostring(confirm), tostring(hitA), tostring(hitB), if after then "in state " .. after.state else "forgotten", tostring(item ~= nil),
			table.concat(seenB, " ; ")))
		L("sounds sent since the hunt: A [" .. sfxSince(A, mA) .. "] B [" .. sfxSince(B, mB) .. "]")
	else
		check("squirrel.huntedGoneForBoth", nil, "no squirrel on the ground near A")
	end

	-- 2. sticks at the TC trunk, a campfire A builds and lights, B cooks on it ------------------------------------------
	Inv.clear(A)
	local toTrunk = flat(Vector3.new(1, 0, 0.3)).Unit
	local gStand = base + toTrunk * 3.6
	placeAt(A, gStand.X, gStand.Z, base)
	task.wait(1.0)
	call(A, "face", Vector3.new(axis.X, base.Y + 4.5, axis.Z))
	task.wait(0.8)
	local promptsA = call(A, "probe", { kind = "prompts" }) or {}
	local fwBefore = Inv.count(A, "firewood")
	local held = call(A, "probe", { kind = "hold", name = "GatherSticks" }, 6)
	task.wait(0.6)
	check("campfire.gatherAtTCTrunk", Inv.count(A, "firewood") == fwBefore + 1, string.format(
		"A at the trunk of %s (%s), looking at it: prompts on A's screen [%s]; held: %s; firewood %d -> %d", tree.Name, trunk.ClassName, table.concat(promptsA, " ; "),
		tostring(held), fwBefore, Inv.count(A, "firewood")))
	Inv.give(A, "firewood", 2 - Inv.count(A, "firewood"))
	local away = flat(base - Vector3.new(axis.X, 0, axis.Z) + Vector3.new(0.01, 0, 0))
	local campStand = base + Vector3.new(14, 0, 0)
	placeAt(A, campStand.X, campStand.Z, campStand + Vector3.new(10, 0, 0))
	placeAt(B, campStand.X + 6, campStand.Z + 7, campStand + Vector3.new(6, 0, 0))
	task.wait(1.0)
	local _, raC = parts(A)
	local spot = (if raC then raC.Position else campStand) + Vector3.new(6, 0, 0)
	local mA, mB = mark(A), mark(B)
	call(A, "fire", { name = "CampAction", a = "Build", b = spot })
	task.wait(1.0)
	local fireId, fire = nil, nil
	for id, f in pairs(Cooking and Cooking.fires() or {}) do
		if f.owner == A.UserId and f.state ~= "Out" then
			fireId, fire = id, f
		end
	end
	if fireId then
		call(A, "fire", { name = "CampAction", a = "Light", b = fireId })
		task.wait(2.5)
		local fa, fb = call(A, "probe", { kind = "fires" }) or {}, call(B, "probe", { kind = "fires" }) or {}
		local function litDrawn(list: { string }): boolean
			local lit, drawn = false, false
			for _, s in ipairs(list) do
				if string.find(s, "fire " .. fireId .. " state=Lit", 1, true) then
					lit = true
				end
				local on = tonumber(string.match(s, "emitters on (%d+)")) or 0
				if string.find(s, "drawn ", 1, true) and on >= 2 and string.find(s, "=true@", 1, true) and string.find(s, "light true", 1, true) then
					drawn = true
				end
			end
			return lit and drawn
		end
		check("campfire.litSeenByBoth", fire.state == "Lit" and litDrawn(fa) and litDrawn(fb), string.format(
			"A built fire %d and lit it (server state %s): A's client [%s] | B's client [%s]; sounds sent: A [%s] B [%s]", fireId, tostring(fire.state), table.concat(fa, " ; "),
			table.concat(fb, " ; "), sfxSince(A, mA), sfxSince(B, mB)))
		L("SOUNDS playing near the fire: A " .. table.concat(call(A, "probe", { kind = "sounds" }) or {}, ", ") .. " | B "
			.. table.concat(call(B, "probe", { kind = "sounds" }) or {}, ", "))
		shot("campfire_lit", 1.2)
		-- B cooks a squirrel on A's fire and takes it
		Inv.clear(B)
		Inv.give(B, "squirrel", 1)
		local fp = fire.position
		placeAt(B, fp.X - 4, fp.Z + 3, fp)
		task.wait(0.8)
		local promptsB = call(B, "probe", { kind = "prompts" }) or {}
		call(B, "fire", { name = "CampAction", a = "Cook", b = fireId })
		task.wait(0.8)
		local spit = fire.spit
		task.wait(7.0)
		call(B, "fire", { name = "CampAction", a = "Take", b = fireId })
		task.wait(1.0)
		check("campfire.usableByB", spit == "squirrel" and Inv.count(B, "cooked_squirrel") >= 1, string.format(
			"B at A's fire: prompts on B's screen [%s]; B put its squirrel on the spit (spit=%s), 7 s later took it: B has cooked_squirrel x%d, squirrel x%d",
			table.concat(promptsB, " ; "), tostring(spit), Inv.count(B, "cooked_squirrel"), Inv.count(B, "squirrel")))
	else
		check("campfire.litSeenByBoth", false, "A's Build made no fire at " .. v3(spot))
	end

	-- 3. a butterfly swarm: A runs past a resting roost; it follows A and stings A only; smoke at the fire shakes it off ----
	-- (run after the tree below: no roost wakes in a round's first minute, HazardDefs.Butterflies.HeartQuietTime)
	local function swarmTest()
	local roost, rd = nil, math.huge
	local folder = workspace:FindFirstChild("Hazards")
	local _, raS = parts(A)
	if folder and raS then
		for _, part in ipairs(folder:GetChildren()) do
			if part:IsA("BasePart") and part:GetAttribute("S") == 0 then
				local d = flatDist(part.Position, raS.Position)
				if d < rd and d > 25 then
					roost, rd = part, d
				end
			end
		end
	end
	if roost and fire then
		local rp = roost.Position
		local fromR = rp + Vector3.new(16, 0, 0)
		local mA2, mB2 = mark(A), mark(B)
		placeAt(B, rp.X - 60, rp.Z + 30, rp)
		placeAt(A, fromR.X, fromR.Z, rp)
		task.wait(1.5)
		local hpA0, hpB0 = health(A), health(B)
		local was = call(A, "setting", { name = "sprintMode", value = 2 })
		call(A, "move", { seconds = 1.6, face = rp - Vector3.new(16, 0, 0) })
		task.wait(1.8)
		call(A, "setting", { name = "sprintMode", value = was or 0 })
		local woke = waitFor(function()
			return roost:GetAttribute("S") == 2
		end, 6)
		-- A waits; the swarm comes to A
		local stung = waitFor(function()
			return health(A) < hpA0 - 0.5
		end, 14)
		task.wait(1.0)
		local hA = call(A, "probe", { kind = "hazard", near = A.Name }) or {}
		local hB = call(B, "probe", { kind = "hazard", near = A.Name }) or {}
		shot("swarm", 1.0)
		local dmgA = clientFind(A, "REMOTE DamageTaken", mA2)
		check("swarm.stingsOnlyTarget", woke ~= nil and stung ~= nil and math.abs(health(B) - hpB0) < 0.5, string.format(
			"roost %s %.0f studs from A; A sprinted past it: swarm up=%s; A's health %.1f -> %.1f (%s), B's (60 studs off) %.1f -> %.1f; server %s",
			roost.Name, rd, tostring(woke ~= nil), hpA0, health(A), tostring(dmgA), hpB0, health(B), fmt(Hazard and Hazard.debug().Butterflies)))
		local function swarming(h: any): boolean
			local n = tonumber(string.match(tostring(h.debug), "swarms=(%d+)")) or 0
			return n >= 1
		end
		check("swarm.seenByBoth", swarming(hA) and swarming(hB) and (tonumber(hA.wings) or 0) > 0 and (tonumber(hB.wings) or 0) > 0
			and (tonumber(hA.wingTurnIn015s) or 0) > 2 and (tonumber(hB.wingTurnIn015s) or 0) > 2, string.format(
			"the swarm on A: A's client %s wings within 30 studs of A (%s), flap %.0f deg in 0.15 s; B's client %s wings (%s), flap %.0f deg; A's debug %s | B's debug %s",
			tostring(hA.wings), tostring(hA.wingSizes), tonumber(hA.wingTurnIn015s) or -1, tostring(hB.wings), tostring(hB.wingSizes), tonumber(hB.wingTurnIn015s) or -1,
			tostring(hA.debug), tostring(hB.debug)))
		local hintTop = tonumber(string.match(tostring(hA.topLines), "HazardScreen/Line y=(%d+)"))
		local eventBottom = tonumber(string.match(tostring(hA.topLines), "HUD/Event y=%d+%.%.(%d+)"))
		check("swarm.hintUnderEventLine", if hintTop and eventBottom then hintTop >= eventBottom else nil, "A's screen, the lines at the top: " .. tostring(hA.topLines) .. " | B's: " .. tostring(hB.topLines))
		-- smoke: A stands beside the lit fire
		local shakenBefore = (Hazard and Hazard.debug().Butterflies or {}).shaken or 0
		local fp = fire.position
		placeAt(A, fp.X + 3, fp.Z + 2, fp)
		local shook = waitFor(function()
			local s = roost:GetAttribute("S")
			return s == 3 or s == 4 or s == 0
		end, 8)
		task.wait(0.5)
		check("swarm.smokeEscape", shook ~= nil and ((Hazard and Hazard.debug().Butterflies or {}).shaken or 0) > shakenBefore, string.format(
			"A stood 3.6 studs from the lit fire: roost state now %s; shaken %s -> %s", tostring(roost:GetAttribute("S")), tostring(shakenBefore),
			tostring((Hazard and Hazard.debug().Butterflies or {}).shaken)))
		L("sounds sent during the swarm: A [" .. sfxSince(A, mA2) .. "] B [" .. sfxSince(B, mB2) .. "]")
	else
		check("swarm.stingsOnlyTarget", nil, "no resting roost 25+ studs from A, or no fire: roost=" .. tostring(roost) .. " fire=" .. tostring(fire))
	end
	end

	-- 4. the tree: A climbs, B watches; A sits on a perch, B sees it seated and hits it; A cannot attack while seated -------
	setHealth(A)
	setHealth(B)
	Inv.clear(A)
	Inv.give(A, "sword", 1)
	local mA3, mB3 = mark(A), mark(B)
	local foot = base + Vector3.new(2.6, 0, 0)
	placeAt(A, foot.X, foot.Z, base)
	placeAt(B, base.X - 16, base.Z - 6, base)
	task.wait(1.0)
	call(B, "track", { target = A.Name, seconds = 12 })
	call(A, "face", Vector3.new(axis.X, base.Y + 6, axis.Z))
	local _, raT = parts(A)
	local y0 = raT and raT.Position.Y or 0
	local tc = call(A, "probe", { kind = "climb" })
	call(A, "move", { seconds = 2.5, face = Vector3.new(axis.X, base.Y + 30, axis.Z) })
	task.wait(1.4)
	local seeClimb = seeOf(B, A)
	shot("tree_climb", 0.6)
	task.wait(1.4)
	local _, raT2 = parts(A)
	local climbSeen = clientFind(B, "SEE-ATTR " .. A.Name .. ".Stance=Climb", mB3)
	check("tree.climbSeenByB", climbSeen ~= nil and raT2 ~= nil and raT2.Position.Y > y0 + 1, string.format(
		"A at the foot of %s: %s; A rose %.1f studs; B's client: %s, A's pose there %s", tree.Name, tostring(tc), if raT2 then raT2.Position.Y - y0 else -1, tostring(climbSeen),
		poseLine("climb", seeClimb)))
	-- sit on the top perch
	local perch = perches[#perches]
	local hum, rootA = parts(A)
	if hum and rootA and perch then
		local stand = perch.WorldPosition + Vector3.new(0, hum.HipHeight + rootA.Size.Y / 2 + 0.2, 0)
		rootA.AssemblyLinearVelocity = Vector3.zero
		A.Character:PivotTo(CFrame.lookAt(stand, stand + perch.WorldCFrame.LookVector * Vector3.new(1, 0, 1)))
		task.wait(1.2)
		call(A, "fire", { name = "TreeSeat", a = "sit", b = perch })
		task.wait(1.2)
		local sitA = call(A, "probe", { kind = "seat" }) or {}
		local seeSit = seeOf(B, A)
		check("tree.sitSeenByB", hum.Sit == true and hum.SeatPart ~= nil and hum.SeatPart.Name == "TreeSeat" and seeSit.humState == "Seated", string.format(
			"A on the top perch of %s (%.1f above the ground): server Sit=%s seat=%s; A's client %s; B's client has A in state %s at %s (server %s)", tree.Name,
			perch.WorldPosition.Y - base.Y, tostring(hum.Sit), if hum.SeatPart then hum.SeatPart:GetFullName() else "nil", fmt(sitA), tostring(seeSit.humState), fmt(seeSit.pos),
			v3(rootA.Position)))
		shot("tree_sit", 0.8)
		-- A tries to swing while seated
		local swingsBefore = #linesWith(A, mA3, "ACT Swing")
		local mS = seq
		call(A, "seq", { { "select", slotOf(A, "sword") }, { "wait", 0.8 }, { "click" }, { "wait", 0.6 } }, 6)
		task.wait(0.5)
		local swings = #linesWith(A, mA3, "ACT Swing") - swingsBefore
		local heldA = clientFind(B, "SEE-ATTR " .. A.Name .. ".EquippedItem", mB3)
		check("tree.noAttackWhileSeated", swings == 0 and hum.Sit == true, string.format(
			"A clicked with the sword while seated: A's client swings started %d; still seated=%s; B saw A's held item change: %s", swings, tostring(hum.Sit), tostring(heldA)))
		-- B shoots the sitter
		Inv.clear(B)
		Inv.give(B, "bow", 1)
		Inv.give(B, "arrow", 6)
		local hpA = health(A)
		local _, rbT = parts(B)
		call(B, "track", {})
		local dToA = if rbT then (rbT.Position - rootA.Position).Magnitude else -1
		local shots = 0
		for _ = 1, 3 do
			shots += 1
			call(B, "seq", { { "select", slotOf(B, "bow") }, { "wait", 0.9 }, { "face", A.Name .. ":UpperTorso" }, { "wait", 0.4 }, { "down" },
				{ "track", A.Name .. ":UpperTorso", 1.3 }, { "wait", 1.2 }, { "up" }, { "wait", 0.8 } }, 10)
			task.wait(1.0)
			if health(A) < hpA - 0.5 then
				break
			end
		end
		L("arrows at the sitter: " .. shots)
		check("tree.sitterCanBeHit", health(A) < hpA - 0.5, string.format("B shot the seated A from %.1f studs with the bow: A's health %.1f -> %.1f; B's client: %s",
			dToA, hpA, health(A), tostring(clientFind(B, "REMOTE HitConfirm", mB3))))
		-- off the tree
		hum.Sit = false
		local seat = hum.SeatPart
		if seat then
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
		end
		task.wait(0.5)
	else
		check("tree.sitSeenByB", false, "no perch or no character")
	end

	-- the swarm, once the round's first minute is over
	local startedAt = tonumber(GS:GetAttribute("RoundStartedAt")) or 0
	local left = 62 - (workspace:GetServerTimeNow() - startedAt)
	L(string.format("SWARM test %.1f s after the horn (RoundStartedAt %s); waiting %.1f s", workspace:GetServerTimeNow() - startedAt, tostring(startedAt), math.max(left, 0)))
	if left > 0 and left < 70 then
		task.wait(left)
	end
	setHealth(A)
	setHealth(B)
	swarmTest()

	-- 5. another challenge: a rockfall called on A; B far away is not hurt -------------------------------------------------
	setHealth(A)
	setHealth(B)
	local _, raR = parts(A)
	if Hazard and raR then
		placeAt(A, raR.Position.X, raR.Position.Z + 6, raR.Position + Vector3.new(0, 0, 20))
		placeAt(B, raR.Position.X + 220, raR.Position.Z, raR.Position)
		task.wait(1.0)
		local mA4, mB4 = mark(A), mark(B)
		local hpB = health(B)
		local _, raR2 = parts(A)
		local ev, why = Hazard.call("Rockfall", { x = raR2.Position.X, z = raR2.Position.Z, warning = 4, force = true })
		L("Rockfall called: " .. fmt(ev) .. " " .. tostring(why))
		task.wait(18)
		local annA = linesWith(A, mA4, "REMOTE Announce")
		local annB = linesWith(B, mB4, "REMOTE Announce")
		local dmgA = linesWith(A, mA4, "REMOTE DamageTaken")
		check("challenge.rockfallBothSeeRightHurt", ev ~= nil and #annA > 0 and #annB > 0 and math.abs(health(B) - hpB) < 0.5, string.format(
			"Rockfall on A: A's client announcements %s ; B's (220 studs off) %s ; A was hurt %d times %s ; B's health %.1f -> %.1f; GS ArenaEvent/HazardEvent %s",
			string.sub(table.concat(annA, " | "), 1, 400), string.sub(table.concat(annB, " | "), 1, 400), #dmgA, string.sub(table.concat(dmgA, " | "), 1, 300), hpB, health(B),
			tostring(GS:GetAttribute("HazardEvent"))))
		L("sounds sent during the rockfall: A [" .. sfxSince(A, mA4) .. "] B [" .. sfxSince(B, mB4) .. "]")
		pcall(Hazard.stop)
	end

	-- 6. the kill, the result, the board, the train again --------------------------------------------------------------
	setHealth(A)
	setHealth(B)
	Inv.clear(A)
	Inv.clear(B)
	Inv.give(A, "sword", 1)
	setupDuel()
	local mA5, mB5 = killB("round1")
	deathChecks("round1", mA5, mB5, 2)
	resultChecks("round1", mA5, mB5, A, { B })
	backToLobby("round1", { A, B })
	local mA6, mB6 = mark(A), mark(B) -- (round two's Countdown starts while the board is read)
	task.wait(2.0)
	trainChecks("round1.respawnInTrain", { A, B })
	boardChecks("round1.board", { A, B }, A)
	shot("board_after_round1", 1.0)
	-- round two: B skips its intro this time
	SKIP_BY.round2 = B
	if roundStartChecks("round2", mA6, mB6) then
		snapshotAll("round2")
	end
	workspace:SetAttribute("DevHazardOff", nil)
	workspace:SetAttribute("WildlifeTest", "scare")
end

-- batch W: the weapons build (19 Nov, mp-weapons) ------------------------------------------------------------------------
-- kits (the pick, the midpoint parcel, the steal, Take all with a brought weapon), stars (damage, the finish on other
-- screens and in first person, kept through a throw), the new weapons between players, the bow on a moving player, the
-- wheel, the Strongbox and the Armoury (whose prize, what the board shows when), Gold per player through a fake store
-- and a rejoin, a real round's Gold, the hotbar under load, and Kits.Delivery = "Start" in round two.
local W: { [string]: any } = {}
local function goldOf(p: Player): number
	local g = Currency and Currency.balance(p)
	return tonumber(g) or tonumber(p:GetAttribute("Gold")) or -1
end
local function econOf(p: Player): any
	return (Data and Data.getEcon(p)) or {}
end
local function armStr(t: any): string
	local out = {}
	for id, s in pairs(type(t) == "table" and t or {}) do
		table.insert(out, tostring(id) .. ":" .. tostring(s))
	end
	table.sort(out)
	return table.concat(out, ",")
end
local function spotOf(name: string): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local c = lobby and lobby:FindFirstChild("Rewards")
	local o = c and c:FindFirstChild(name)
	local s = o and o:FindFirstChild("PromptSpot", true)
	return if s and s:IsA("BasePart") then s else nil
end
-- stands p on the train's floor at (x, z) (a ray from under the roof), facing `look`
local function trainStand(p: Player, x: number, z: number, look: Vector3)
	local hum, root = parts(p)
	if not (hum and root and p.Character) then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, q in ipairs(Players:GetPlayers()) do
		if q.Character then
			table.insert(ignore, q.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 206, z), Vector3.new(0, -20, 0), params)
	local y = (if hit then hit.Position.Y else 200) + hum.HipHeight + root.Size.Y / 2 + 0.1
	root.AssemblyLinearVelocity = Vector3.zero
	p.Character:PivotTo(CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(look.X, y, look.Z)))
end
local function slotWith(p: Player, itemId: string, stars: number?): number?
	local snap = Inv.getSnapshot(p)
	for i, s in ipairs(snap.slots) do
		if type(s) == "table" and s.id == itemId and (stars == nil or s.stars == stars) then
			return i
		end
	end
	return nil
end
local function bagStr(p: Player): string
	local snap = Inv.getSnapshot(p)
	local out = {}
	for i, s in ipairs(snap.slots) do
		if type(s) == "table" then
			table.insert(out, string.format("%d:%sx%s*%s", i, tostring(s.id), tostring(s.count), tostring(s.stars)))
		end
	end
	return table.concat(out, " ") .. " equipped=" .. tostring(snap.equipped)
end
local function lineTime(line: string?): number?
	return line and tonumber(string.match(line, "^([%d%.]+)"))
end
local function num(line: string?, key: string): number?
	return line and tonumber(string.match(line, key .. "=(%-?[%d%.]+)"))
end
-- the board's words on `p` since `from`: (first line, time of the first change after it, every change)
local function boardChanges(p: Player, from: number): (string?, number?, { string })
	local store = clientLines[p.Name] or {}
	local first, tChange, all = nil, nil, {}
	for i = from + 1, #store do
		local line = store[i]
		if string.find(line, "BOARD ", 1, true) and not string.find(line, "BOARD end", 1, true) then
			if not first then
				first = line
			else
				tChange = tChange or lineTime(line)
				table.insert(all, string.sub(line, 1, 260))
			end
		end
	end
	return first, tChange, all
end

-- one draw by A at the wheel or the case, watched by B; returns the line A's client was told
local function drawCheck(tag: string, msg: { any }, kind: string)
	local eA0, eB0, gA0, gB0 = econOf(A), econOf(B), goldOf(A), goldOf(B)
	local mA, mB = mark(A), mark(B)
	call(A, "probe", { kind = "watchboard", seconds = 13 })
	task.wait(0.5)
	call(A, "fire", { name = "Rewards", a = msg[1], b = msg[2] })
	local lineB = waitFor(function()
		return (clientFind(B, "REMOTE Rewards " .. kind .. " ", mB))
	end, 5)
	task.wait(13)
	local lineA = clientFind(A, "REMOTE Rewards " .. kind .. " ", mA)
	local eA1, eB1 = econOf(A), econOf(B)
	local startAt = num(lineA, "startAt")
	local duration = num(lineA, "duration") or (if kind == "box" then 0 else 3.6)
	local stop = if startAt then (startAt % 100000) + duration else nil
	local first, tChange, all = boardChanges(A, mA)
	L(string.format("DRAW %s: A told %s | B told %s | A gold %d -> %d, B gold %d -> %d | A armoury %s -> %s, B armoury %s -> %s | board first: %s | changes: %s", tag,
		tostring(lineA), tostring(lineB), gA0, goldOf(A), gB0, goldOf(B), armStr(eA0.Armoury), armStr(eA1.Armoury), armStr(eB0.Armoury), armStr(eB1.Armoury),
		tostring(first), table.concat(all, " || ")))
	check("w." .. tag .. ".othersSee", lineB ~= nil and string.find(lineB, "userId=" .. A.UserId, 1, true) ~= nil,
		"B's client was told of A's draw (others in the car watch it): " .. tostring(lineB and string.sub(lineB, 1, 300)))
	check("w." .. tag .. ".prizeIsAsOnly", lineA ~= nil and (eA1.Draws or 0) == (eA0.Draws or 0) + 1 and armStr(eB0.Armoury) == armStr(eB1.Armoury) and gB0 == goldOf(B)
		and (eB1.Draws or 0) == (eB0.Draws or 0), string.format("A's draws %s -> %s, A's armoury %s -> %s, A's Gold %d -> %d | B's draws %s -> %s, armoury '%s' -> '%s', Gold %d -> %d",
		tostring(eA0.Draws), tostring(eA1.Draws), armStr(eA0.Armoury), armStr(eA1.Armoury), gA0, goldOf(A), tostring(eB0.Draws), tostring(eB1.Draws), armStr(eB0.Armoury),
		armStr(eB1.Armoury), gB0, goldOf(B)))
	-- the board holds its pre-draw Gold and rows until the reveal ends (the wheel stops at startAt + duration; the reveal
	-- runs about 2.4 to 3.2 s after the prize rises)
	local ok = first ~= nil and (tChange == nil or (stop ~= nil and tChange >= stop + 1.5))
	check("w." .. tag .. ".boardWaitsForReveal", ok, string.format(
		"A's Armoury board and Gold line: first change %s s after the %s (draw sent at %s, %s at %s); the board %s",
		if tChange and stop then string.format("%.2f", tChange - stop) else "?", if kind == "spin" then "wheel stopped" else "box opened",
		tostring(startAt and startAt % 100000), if kind == "spin" then "stops" else "opens", tostring(stop), if tChange then "changed" else "did not change in 13 s"))
	return lineA
end

local function wLobby()
	-- a player who joined before this driver ran loaded from Studio's own (switched off) DataStore, whose failure can
	-- mark the stores unavailable after the stand-in went in: put it in again and load everyone from it
	if fakeStore then
		task.wait(1.0)
		Data.useTestStore(fakeStore)
		for _, p in ipairs(Players:GetPlayers()) do
			Data.testRejoin(p)
		end
		L("FAKESTORE again, every player loaded from it")
	end
	local okLoad = waitFor(function()
		return Data.isLoaded(A) and Data.isLoaded(B)
	end, 25)
	local gA0, gB0 = goldOf(A), goldOf(B)
	Data.increment(A, "Gold", 5000)
	Data.increment(B, "Gold", 700)
	task.wait(1.0)
	check("w.gold.perPlayer", okLoad ~= nil and goldOf(A) == gA0 + 5000 and goldOf(B) == gB0 + 700, string.format(
		"profiles loaded=%s (fake store); A %d -> %d (+5000), B %d -> %d (+700); attributes A.Gold=%s B.Gold=%s", tostring(okLoad ~= nil), gA0, goldOf(A), gB0, goldOf(B),
		tostring(A:GetAttribute("Gold")), tostring(B:GetAttribute("Gold"))))
	local wheel = spotOf("Wheel")
	if not wheel then
		check("w.lobby.rewards", false, "no workspace.Lobby.Rewards.Wheel PromptSpot")
		return
	end
	trainStand(A, 8800, 80, wheel.Position)
	trainStand(B, 8800, 72, wheel.Position)
	task.wait(1.5)
	shot("w_lobby_wheel", 0.6)
	drawCheck("spin", { "spin" }, "spin")
	drawCheck("strongbox", { "box", "strongbox" }, "box")
	-- the Armoury: a Machete at 3 stars (unless a draw already gave one), brought to the next round
	local owned = (econOf(A).Armoury or {}).machete or 0
	local g0 = goldOf(A)
	if owned < 3 then
		call(A, "fire", { name = "Rewards", a = "buy", b = "machete" })
		task.wait(1.5)
	end
	local now3 = (econOf(A).Armoury or {}).machete or 0
	check("w.armoury.buy", now3 >= 3 and (owned >= 3 or goldOf(A) == g0 - 800), string.format("A owned machete at %s stars, now %s; Gold %d -> %d (a buy is 800)",
		tostring(owned), tostring(now3), g0, goldOf(A)))
	call(A, "fire", { name = "Rewards", a = "bring", b = "machete" })
	call(A, "fire", { name = "KitPick", a = "archer" })
	call(B, "fire", { name = "KitPick", a = "forager" })
	task.wait(1.5)
	W.macheteStars = now3
	check("w.kit.pick", A:GetAttribute("Kit") == "archer" and B:GetAttribute("Kit") == "forager" and A:GetAttribute("KitBring") == "machete"
		and econOf(A).Bring == "machete" and string.find(tostring(A:GetAttribute("KitArmoury")), "machete:" .. now3, 1, true) ~= nil and (B:GetAttribute("KitBring") or "") == "",
		string.format("A Kit=%s KitBring=%s Econ.Bring=%s KitArmoury=%s | B Kit=%s KitBring=%s", tostring(A:GetAttribute("Kit")), tostring(A:GetAttribute("KitBring")),
			tostring(econOf(A).Bring), tostring(A:GetAttribute("KitArmoury")), tostring(B:GetAttribute("Kit")), tostring(B:GetAttribute("KitBring"))))
	-- a leave and a rejoin (DataService.testRejoin: save, drop the session, load it again from the store)
	task.wait(1.0)
	local before = { goldA = goldOf(A), goldB = goldOf(B), armA = armStr(econOf(A).Armoury), armB = armStr(econOf(B).Armoury), bring = econOf(A).Bring }
	local savedA = Data.testRejoin(A)
	local savedB = Data.testRejoin(B)
	local okRe = waitFor(function()
		return Data.isLoaded(A) and Data.isLoaded(B)
	end, 15)
	task.wait(0.5)
	check("w.gold.rejoin", okRe ~= nil and savedA and savedB and goldOf(A) == before.goldA and goldOf(B) == before.goldB and armStr(econOf(A).Armoury) == before.armA
		and armStr(econOf(B).Armoury) == before.armB and econOf(A).Bring == before.bring, string.format(
		"saved A=%s B=%s, loaded again=%s, store writes %d | A Gold %d -> %d, armoury %s -> %s, bring %s -> %s | B Gold %d -> %d, armoury '%s' -> '%s'", tostring(savedA),
		tostring(savedB), tostring(okRe ~= nil), fakeWrites, before.goldA, goldOf(A), before.armA, armStr(econOf(A).Armoury), tostring(before.bring), tostring(econOf(A).Bring),
		before.goldB, goldOf(B), before.armB, armStr(econOf(B).Armoury)))
	W.goldBeforeRound = { [A] = goldOf(A), [B] = goldOf(B) }
	if P3 then
		W.gold3 = goldOf(P3)
	end
end

-- what the server's parcel prompts receive (hold began / ended / triggered), logged as it happens
local function watchPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local t0 = os.clock()
	L(string.format("SRV-PROMPT %s added hold=%.2f", prompt:GetFullName(), prompt.HoldDuration))
	prompt.PromptButtonHoldBegan:Connect(function(who)
		L(string.format("SRV-PROMPT %s HoldBegan by %s at +%.2f", prompt.Name, who.Name, os.clock() - t0))
	end)
	prompt.PromptButtonHoldEnded:Connect(function(who)
		L(string.format("SRV-PROMPT %s HoldEnded by %s at +%.2f", prompt.Name, who.Name, os.clock() - t0))
	end)
	prompt.Triggered:Connect(function(who)
		L(string.format("SRV-PROMPT %s Triggered by %s at +%.2f", prompt.Name, who.Name, os.clock() - t0))
	end)
end
CollectionService:GetInstanceAddedSignal("KitParcel"):Connect(function(m)
	m.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			watchPrompt(d)
		end
	end)
end)

-- the parcel of `owner` (unopened, landed when `landed`), newest first
local function parcelOf(owner: Player, landed: boolean?): Model?
	local best = nil
	for _, m in ipairs(CollectionService:GetTagged("KitParcel")) do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == owner.UserId and m:GetAttribute("Opened") ~= true and (not landed or m:GetAttribute("Landed") == true) then
			best = m
		end
	end
	return best
end

-- the midpoint drop now (Studio switch KitDropNow); returns where each player stood when their spot was picked
local function dropNow(tag: string): { [Player]: Vector3 }
	local at: { [Player]: Vector3 } = {}
	for _, p in ipairs({ A, B }) do
		p:SetAttribute("KitIncoming", nil)
	end
	GS:SetAttribute("KitDropNow", true)
	waitFor(function()
		for _, p in ipairs({ A, B }) do
			if not at[p] and p:GetAttribute("KitIncoming") ~= nil then
				local _, r = parts(p)
				at[p] = if r then r.Position else Vector3.zero
			end
		end
		return at[A] and at[B]
	end, 12)
	L(string.format("DROP %s: KitIncoming A=%s B=%s", tag, tostring(A:GetAttribute("KitIncoming")), tostring(B:GetAttribute("KitIncoming"))))
	waitFor(function()
		return parcelOf(A, true) and parcelOf(B, true)
	end, 16)
	task.wait(0.8)
	return at
end

local function kitChecks()
	Kits.Settings.Stagger = 1 -- (both parcels within a second: the test's own number)
	setupDuel()
	L(duel(A, B, 30))
	task.wait(0.6)
	local mA, mB = mark(A), mark(B)
	local at = dropNow("first")
	local pa, pb = parcelOf(A, true), parcelOf(B, true)
	local function landDist(p: Player, m: Model?): number
		return if m and at[p] then flatDist(m:GetPivot().Position, at[p]) else -1
	end
	local dA, dB = landDist(A, pa), landDist(B, pb)
	check("w.kit.landsNear", dA >= 14.5 and dA <= 25.5 and dB >= 14.5 and dB <= 25.5, string.format(
		"each parcel landed this far (flat) from where its owner stood when the warning came: A %.1f, B %.1f (design 15 to 25)", dA, dB))
	local comingA = clientFind(A, "KitIncoming", mA)
	local guiA = call(A, "gui", "kit") or {}
	L("KIT A's screen: " .. table.concat(guiA, " ; ") .. " | A's line: " .. tostring(comingA))
	local seenB = call(B, "probe", { kind = "parcels" }) or {}
	local seenA = call(A, "probe", { kind = "parcels" }) or {}
	L("PARCELS on A: " .. table.concat(seenA, " | ") .. " || on B: " .. table.concat(seenB, " | "))
	local bSeesA, aHold, bHoldOnA = false, nil, nil
	for _, s in ipairs(seenB) do
		if string.find(s, "owner=" .. A.UserId .. " landed=true", 1, true) then
			bSeesA = true
			bHoldOnA = tonumber(string.match(s, "hold=([%d%.]+)"))
		end
	end
	for _, s in ipairs(seenA) do
		if string.find(s, "owner=" .. A.UserId .. " landed=true", 1, true) then
			aHold = tonumber(string.match(s, "hold=([%d%.]+)"))
		end
	end
	check("w.kit.otherSeesLanding", bSeesA, "B's client has A's parcel landed (chute folded): " .. table.concat(seenB, " | "))
	check("w.kit.holdTimes", aHold ~= nil and math.abs(aHold - 0.6) < 0.01 and bHoldOnA ~= nil and math.abs(bHoldOnA - 2.5) < 0.01, string.format(
		"A's own parcel's Open prompt holds %s s on A's screen (0.6); on B's screen %s s (2.5)", tostring(aHold), tostring(bHoldOnA)))
	shot("w_kit_landed", 0.6)
	-- B steals A's parcel: a modified client's short hold first, then the honest 2.5 s
	if pa then
		local p = pa:GetPivot().Position
		local _, ra = parts(A)
		local away = if ra then flat(ra.Position - p) else Vector3.xAxis
		away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
		standAt(B, p.X - away.X * 3.5, p.Z - away.Z * 3.5, p, p.Y)
		task.wait(0.6)
		call(B, "face", { x = p.X, y = p.Y, z = p.Z })
		task.wait(0.6)
		local quick = call(B, "probe", { kind = "kithold", owner = A.UserId, seconds = 0.75, force = 0.6 }, 6)
		task.wait(0.5)
		local openedQuick = pa:GetAttribute("Opened") == true
		check("w.kit.stealShortHoldRefused", not openedQuick, "B (not the owner) holds A's parcel for 0.75 s with its client's hold set to 0.6: " .. tostring(quick)
			.. "; opened on the server=" .. tostring(openedQuick))
		local before = bagStr(B)
		local full = call(B, "probe", { kind = "kithold", owner = A.UserId, seconds = 2.75 }, 8)
		task.wait(1.2)
		local opened = pa:GetAttribute("Opened") == true
		check("w.kit.stealByHold", opened, "B holds A's parcel 2.75 s with the engine's own prompt: " .. tostring(full) .. "; opened on the server=" .. tostring(opened))
		if not opened then
			pa:SetAttribute("TestOpenBy", B.UserId) -- (Studio switch: opens it as B, so the rest can be checked)
			task.wait(1.2)
			opened = pa:GetAttribute("Opened") == true
			L("KIT A's parcel opened as B by the test switch: " .. tostring(opened))
		end
		local take = call(B, "prompt", { match = "take all", radius = 12 }, 8)
		task.wait(1.2)
		local want = W.macheteStars or 3
		check("w.kit.steal", opened and slotWith(B, "machete", want) ~= nil and Inv.count(B, "arrow") == 8 and Inv.count(B, "apple") >= 1, string.format(
			"B holds A's parcel 2.75 s: %s; opened=%s; B's Take all: %s; B's bag %s -> %s (A's Archer kit with its brought Machete %d stars)", tostring(full), tostring(opened),
			tostring(take), before, bagStr(B), want))
		shot("w_kit_stolen", 0.6)
	else
		check("w.kit.steal", false, "A's parcel never landed")
	end
	-- the second drop: A opens its own with the owner's short hold and takes all
	Inv.clear(A)
	Inv.clear(B)
	local oldItems: { [Instance]: boolean } = {}
	for _, m in ipairs(CollectionService:GetTagged("GroundItem")) do
		oldItems[m] = true
	end
	local _, ra = parts(A)
	if ra then
		standAt(A, ra.Position.X, ra.Position.Z, nil)
	end
	task.wait(0.4)
	at = dropNow("second")
	local pa2 = parcelOf(A, true)
	if not pa2 then
		check("w.kit.ownerOpens", false, "A's second parcel did not land")
		return
	end
	local p2 = pa2:GetPivot().Position
	standAt(A, p2.X + 3.5, p2.Z, p2, p2.Y)
	task.wait(0.6)
	call(A, "face", { x = p2.X, y = p2.Y, z = p2.Z })
	task.wait(0.6)
	local own = call(A, "probe", { kind = "kithold", owner = A.UserId, seconds = 0.8 }, 6)
	task.wait(1.2)
	local opened = pa2:GetAttribute("Opened") == true
	check("w.kit.ownerOpens", opened, "A holds its own parcel 0.8 s (its prompt's own hold): " .. tostring(own) .. "; opened=" .. tostring(opened))
	if not opened then
		pa2:SetAttribute("TestOpenBy", A.UserId)
		task.wait(1.2)
		L("KIT A's second parcel opened as A by the test switch: " .. tostring(pa2:GetAttribute("Opened")))
	end
	local take = call(A, "prompt", { match = "take all", radius = 12 }, 8)
	task.wait(1.5)
	local want = W.macheteStars or 3
	local spilled = {}
	for _, m in ipairs(CollectionService:GetTagged("GroundItem")) do
		if not oldItems[m] and m:IsDescendantOf(workspace) and (m:GetPivot().Position - p2).Magnitude < 16 then
			table.insert(spilled, tostring(m:GetAttribute("ItemId")) .. "x" .. tostring(m:GetAttribute("Count")) .. "*" .. tostring(m:GetAttribute("Stars")))
		end
	end
	local macheteSlots = 0
	for _, s in ipairs(Inv.getSnapshot(A).slots) do
		if type(s) == "table" and s.id == "machete" then
			macheteSlots += s.count
		end
	end
	check("w.kit.takeAllBringsOwned", slotWith(A, "machete", want) ~= nil and macheteSlots == 1 and Inv.count(A, "short_bow") == 0 and Inv.count(A, "arrow") == 8
		and Inv.count(A, "apple") == 1 and #spilled == 0, string.format("A's Take all: %s; A's bag: %s; left on the ground by the parcel: [%s] (want Machete %d stars once, Arrow x8, Apple; no Short Bow)",
		tostring(take), bagStr(A), table.concat(spilled, ", "), want))
	shot("w_kit_taken", 0.6)
end

local function starChecks()
	setupDuel()
	Inv.clear(A)
	Inv.clear(B)
	setHealth(A)
	setHealth(B)
	L(string.format("give A: machete1 %d machete5 %d twin_axe1 %d hatchet4 %d ring_blade1 %d", Inv.give(A, "machete", 1, 1), Inv.give(A, "machete", 1, 5),
		Inv.give(A, "twin_axe", 1, 1), Inv.give(A, "hatchet", 1, 4), Inv.give(A, "ring_blade", 1, 1)))
	task.wait(0.6)
	L("bag A " .. bagStr(A))
	local s1, s5 = slotWith(A, "machete", 1), slotWith(A, "machete", 5)
	L(duel(A, B, 5))
	local r1 = attack("machete 1 star@5", { { "select", s1 }, { "wait", 0.8 }, { "face", B.Name }, { "wait", 0.4 }, { "click" } })
	setHealth(B)
	task.wait(0.8)
	local r5 = attack("machete 5 stars@5", { { "select", s5 }, { "wait", 0.8 }, { "face", B.Name }, { "wait", 0.4 }, { "click" } })
	local e1, e5 = dmgOf("machete", 1), dmgOf("machete", 5)
	check("w.stars.damage", math.abs(r1.dealt - e1) < 0.3 and math.abs(r5.dealt - e5) < 0.3, string.format(
		"A's machete on B at 5 studs: 1 star B lost %.2f (expected %.2f), 5 stars B lost %.2f (expected %.2f); refusals %s", r1.dealt, e1, r5.dealt, e5, refusals()))
	setHealth(B)
	call(B, "face", A.Name)
	task.wait(1.0)
	local wB, wA = call(B, "probe", { kind = "weap" }) or {}, call(A, "probe", { kind = "weap" }) or {}
	local heldB = tostring((wB.held or {})[A.Name])
	L("WEAP B sees A: " .. heldB .. " | A's viewmodel: " .. table.concat(wA.vm or {}, " ; ") .. " | A's hotbar stars: " .. table.concat(wA.hotbar or {}, " ; ")
		.. " | A's client bag " .. tostring(wA.inv))
	check("w.stars.otherScreen", string.find(heldB, "item=machete", 1, true) ~= nil and string.find(heldB, "modelStars=5", 1, true) ~= nil
		and string.find(heldB, "finish=Masterwork", 1, true) ~= nil, "B's client, A's held machete: " .. heldB)
	local vm = table.concat(wA.vm or {}, " ; ")
	check("w.stars.firstPerson", string.find(vm, "stars=5", 1, true) ~= nil and string.find(vm, "Masterwork", 1, true) ~= nil,
		"A's own first-person item: " .. vm .. " | the steel colour B draws: " .. heldB)
	check("w.stars.hotbar", #(wA.hotbar or {}) > 0, "A's screen, texts with a star: " .. table.concat(wA.hotbar or {}, " ; "))
	shot("w_machete5", 0.8)

	-- throws: the Hatchet at 4 stars keeps its stars where it lands and when it is picked up again
	local function throwAt(tag: string, slot: number?, dist: number, expectBody: number, headMult: number): { [string]: any }
		setHealth(B)
		L(duel(A, B, dist))
		local nF = #fires
		local r = attack(tag, { { "select", slot }, { "wait", 0.8 }, { "face", B.Name }, { "wait", 0.3 }, { "aimset", true }, { "wait", 0.4 }, { "face", B.Name },
			{ "wait", 0.1 }, { "click" }, { "wait", 0.25 }, { "aimset", false }, { "wait", 1.2 } }, 1.0)
		local f = fires[nF + 1]
		local okDmg = math.abs(r.dealt - expectBody) < 0.6 or math.abs(r.dealt - math.min(expectBody * headMult, 95)) < 0.6
		check("w.throw." .. tag, f ~= nil and okDmg, string.format("%s at %d studs: fired=%s (%s stars=%s); B lost %.2f (body %.2f, head %.2f); A got HitConfirm=%s", tag, dist,
			tostring(f ~= nil), if f then f.item else "-", tostring(f and f.opts and f.opts.recoverStars), r.dealt, expectBody, math.min(expectBody * headMult, 95),
			tostring(r.tConfirm ~= nil)))
		return r
	end
	local hd = Stars.def("hatchet", 4)
	throwAt("hatchet4", slotWith(A, "hatchet", 4), 12, hd.throwDamage, hd.throwHeadMultiplier or 1.6)
	task.wait(0.8)
	-- the 4-star one is in B's body now: its world copy carries the stars
	local stuck = nil
	for _, m in ipairs(CollectionService:GetTagged("WorldProjectile")) do
		if m:GetAttribute("ItemId") == "hatchet" then
			stuck = m
		end
	end
	L("STUCK hatchet " .. tostring(stuck and stuck:GetFullName()) .. " Stars=" .. tostring(stuck and stuck:GetAttribute("Stars")) .. " Host=" .. tostring(stuck and stuck:GetAttribute("Host")))
	-- a second Hatchet, 3 stars, thrown at the ground 9 studs to the side, then taken back with E
	Inv.give(A, "hatchet", 1, 3)
	task.wait(0.4)
	local _, ra0 = parts(A)
	local _, rb0 = parts(B)
	local ground = if ra0 and rb0 then ra0.Position + (flat(rb0.Position - ra0.Position).Unit:Cross(Vector3.yAxis)) * 9 - Vector3.new(0, 3, 0) else Vector3.zero
	local gp = { x = ground.X, y = ground.Y, z = ground.Z }
	local nF = #fires
	call(A, "seq", { { "select", slotWith(A, "hatchet", 3) }, { "wait", 0.8 }, { "face", gp }, { "wait", 0.3 }, { "aimset", true },
		{ "wait", 0.4 }, { "face", gp }, { "click" }, { "wait", 0.25 }, { "aimset", false } }, 10)
	task.wait(2.5)
	L("THROWN at the ground: " .. tostring(fires[nF + 1] and fires[nF + 1].item) .. " stars " .. tostring(fires[nF + 1] and fires[nF + 1].opts and fires[nF + 1].opts.recoverStars))
	local loose, wid = nil, nil
	for _, m in ipairs(CollectionService:GetTagged("LooseProjectile")) do
		if m:GetAttribute("ItemId") == "hatchet" then
			loose, wid = m, m:GetAttribute("WorldId")
		end
	end
	local seenOnB = call(B, "items", { radius = 400 }) or {}
	L("B's client world items: " .. table.concat(seenOnB, " ; "))
	if loose then
		local p = if loose:IsA("Model") then loose:GetPivot().Position else (loose :: any).Position
		standAt(A, p.X + 2, p.Z, p, p.Y)
		task.wait(0.8)
		call(A, "fire", { name = "TakeWorldItem", a = wid })
		task.wait(1.0)
	end
	check("w.throw.hatchetKeepsStars", stuck ~= nil and stuck:GetAttribute("Stars") == 4 and loose ~= nil and slotWith(A, "hatchet", 3) ~= nil, string.format(
		"the Hatchet 4 stars stuck in B: Stars attribute %s | the Hatchet 3 stars thrown at the ground: %s (Stars attribute %s, WorldId %s); A took it back with E: bag %s",
		tostring(stuck and stuck:GetAttribute("Stars")), tostring(loose and loose:GetFullName()), tostring(loose and loose:GetAttribute("Stars")), tostring(wid), bagStr(A)))
	local rb = Stars.def("ring_blade", 1)
	throwAt("ringBlade1", slotWith(A, "ring_blade", 1), 25, rb.throwDamage, rb.throwHeadMultiplier or 1.6)
	local ta = Stars.def("twin_axe", 1)
	throwAt("twinAxe1", slotWith(A, "twin_axe", 1), 12, ta.throwDamage, 1.6)

	-- the Twin-Bit Axe against padded armour (and a machete against the same armour)
	Inv.give(A, "twin_axe", 1, 1)
	Inv.give(B, "padded_armor", 1)
	task.wait(0.5)
	L(duel(A, B, 5))
	call(B, "seq", { { "select", slotWith(B, "padded_armor") }, { "wait", 0.8 }, { "down" }, { "wait", 2.9 }, { "up" }, { "wait", 0.4 } }, 10)
	task.wait(0.5)
	local mult = Inv.getArmorMultiplier(B)
	L("ARMOUR B wears " .. tostring(B:GetAttribute("Armor")) .. " multiplier " .. tostring(mult))
	setHealth(B)
	L(duel(A, B, 5))
	local rA = attack("twin axe vs padded@5", { { "aimset", false }, { "select", slotWith(A, "twin_axe", 1) }, { "wait", 0.8 }, { "face", B.Name }, { "wait", 0.4 }, { "click" }, { "wait", 0.4 } }, 1.0)
	setHealth(B)
	task.wait(1.0)
	local rM = attack("machete vs padded@5", { { "select", slotWith(A, "machete", 1) }, { "wait", 0.8 }, { "face", B.Name }, { "wait", 0.4 }, { "click" } })
	local eAxe = dmgOf("twin_axe", 1) * (1 - (1 - mult) * 0.5)
	local eMac = dmgOf("machete", 1) * mult
	check("w.twinAxe.armour", B:GetAttribute("Armor") == "padded_armor" and math.abs(rA.dealt - eAxe) < 0.4 and math.abs(rM.dealt - eMac) < 0.4, string.format(
		"B wears %s (x%.2f): Twin-Bit Axe B lost %.2f (expected %.2f, armour stops half as much), machete B lost %.2f (expected %.2f)", tostring(B:GetAttribute("Armor")),
		mult, rA.dealt, eAxe, rM.dealt, eMac))
	setHealth(B)
end

-- the arc of a fired projectile against a point: the closest it passes (studs)
local function arcMiss(f: any, point: Vector3): number
	local best = math.huge
	for i = 0, 1500 do
		local t = i * 0.002
		local p = f.origin + f.velocity * t + Vector3.new(0, -0.5 * f.gravity * t * t, 0)
		best = math.min(best, (p - point).Magnitude)
	end
	return best
end

local function bowChecks()
	setupDuel()
	Inv.clear(A)
	Inv.clear(B)
	Inv.give(A, "bow", 1, 1)
	Inv.give(A, "arrow", 24)
	Inv.give(A, "bow", 1, 5)
	task.wait(0.5)
	local perp = Vector3.new(-duelDir.Z, 0, duelDir.X)
	local up = Vector3.new(0, 1.5, 0)
	local bow1 = slotWith(A, "bow", 1)
	for _, dd in ipairs({ -55, 55, 100, 150 }) do
		local still = dd < 0
		local d = math.abs(dd)
		setHealth(B)
		L(duel(A, B, d))
		call(A, "seq", { { "aimset", false }, { "select", bow1 }, { "wait", 0.6 } }, 4)
		local _, rb = parts(B)
		if rb and not still then
			call(B, "move", { seconds = 3.4, face = rb.Position + perp * 80 + up })
		end
		task.wait(0.7)
		local nF, mA = #fires, mark(A)
		local r = attack("bow@" .. d .. " on B walking across", { { "track", B.Name, 3.0 }, { "wait", 0.2 }, { "down" }, { "wait", 1.0 }, { "aimpt" }, { "up" }, { "wait", 0.4 } }, 1.4)
		call(B, "move", {})
		local f = fires[nF + 1]
		local aim = clientFind(A, "AIMPT ", mA)
		local x, y, z = string.match(aim or "", "AIMPT ([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
		local point = if x then Vector3.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number) else nil
		local miss = if f and point then arcMiss(f, point) else -1
		local onB = aim and string.find(aim, "on=Workspace." .. B.Name, 1, true) ~= nil
		local dist = if f and point then (point - f.origin).Magnitude else -1
		local id = "w.bow.crosshair@" .. d .. (if still then "Standing" else "")
		local detail = string.format("B " .. (if still then "standing" else "walking across A's view") .. " %d studs away, A standing and tracking: the crosshair was on %s (%.1f studs from the arrow's start) at the release; the arrow's arc passes %.2f studs from that point; B lost %.1f; arrow speed %.0f",
			d, tostring(aim and string.match(aim, "on=(%S+)")), dist, miss, r.dealt, if f then f.velocity.Magnitude else -1)
		if d <= 60 then
			-- (moving: the camera follows B every frame, so the logged point and the release are up to one frame apart)
			check(id, f ~= nil and point ~= nil and miss >= 0 and miss < (if still then 0.15 else 0.5), detail)
		else
			check(id, nil, detail .. " (beyond the on-target range the arrow drops below the crosshair by design)")
		end
		task.wait(0.4)
	end
	-- a headshot with the 5-star bow: capped at 90, no red, no words
	setHealth(B)
	L(duel(A, B, 30))
	call(B, "move", {})
	local mB, mAh = mark(B), mark(A)
	local r = attack("bow 5 stars head@30", { { "select", slotWith(A, "bow", 5) }, { "wait", 0.8 }, { "track", B.Name .. ":Head", 2.4 }, { "wait", 0.3 }, { "down" },
		{ "wait", 1.2 }, { "up" }, { "wait", 0.5 } }, 1.4)
	local bd = Stars.def("bow", 5)
	task.wait(1.0)
	local guiB = call(B, "gui") or {}
	check("w.bow.headshotCap", math.abs(r.dealt - 90) < 0.6, string.format("5-star Recurve (full draw body %.1f, head x2 = %.1f) at B's head from 30 studs: B lost %.1f (cap 90); damage line on B: %s; A's sounds: %s",
		bd.damageMax, bd.damageMax * 2, r.dealt, tostring(r.dmg), "A: " .. sfxSince(A, mAh) .. " | B: " .. sfxSince(B, mB)))
	redCheck("w.bow.headshotNoRed", B, mB)
	L("GUI B after the headshot: " .. string.sub(table.concat(guiB, " ; "), 1, 1200))
	setHealth(B)
end

local function rawClaimChecks()
	Inv.clear(A)
	Inv.give(A, "sword", 1, 1)
	task.wait(0.4)
	call(A, "seq", { { "select", slotWith(A, "sword") }, { "wait", 0.8 } }, 4)
	for _, d in ipairs({ 11, 11, 12 }) do
		setHealth(B)
		L(duel(A, B, d))
		task.wait(0.6)
		local hA = A.Character and A.Character:FindFirstChild("Head")
		local bestPart, best = "?", math.huge
		if hA and hA:IsA("BasePart") and B.Character then
			for _, part in ipairs(B.Character:GetChildren()) do
				if part:IsA("BasePart") and part.CanQuery then
					local half = part.Size * 0.5
					local rel = part.CFrame:PointToObjectSpace(hA.Position)
					local c = Vector3.new(math.clamp(rel.X, -half.X, half.X), math.clamp(rel.Y, -half.Y, half.Y), math.clamp(rel.Z, -half.Z, half.Z))
					if (rel - c).Magnitude < best then
						best, bestPart = (rel - c).Magnitude, part.Name
					end
				end
			end
		end
		local range = (Stars.def("sword", 1) :: any).range
		L(string.format("BODYDIST at %.1f: from A's head to B's body %.2f (%s); the server's front for a still pair %.2f; B holds %s", d, best, bestPart,
			range + Config.Combat.MeleeHitRadius * 0.85 - 0.5 + 0.15, tostring(B.Character and B.Character:GetAttribute("EquippedItem"))))
		local honest = attack("sword honest@" .. d, { { "face", B.Name }, { "wait", 0.4 }, { "click" }, { "wait", 0.7 } })
		L(string.format("HONEST sword at %.1f: B lost %.1f; A's own screen: %s", d, honest.dealt, tostring(honest.strike)))
		setHealth(B)
		task.wait(0.4)
		local before = refusals()
		local r = attack("sword raw claim@" .. d, { { "face", B.Name }, { "wait", 0.3 }, { "remote", "MeleeSwing", "raw", B.Name } })
		-- a claim is a cheat only beyond what an honest swing reaches: at the same spot the honest click came first
		check("w.melee.rawClaim@" .. d, r.dealt < 0.5 or honest.dealt > 0.5, string.format(
			"a modified client claiming a Longsword (1 star) hit from %d studs on a player standing still: B lost %.1f; an honest click from the same spot took %.1f (A's screen %s); A's head to B's nearest body part %.2f (%s), the server's front %.2f; refusals before [%s] after [%s]",
			d, r.dealt, honest.dealt, tostring(honest.strike and string.match(honest.strike, "hit=%S+") or "showed a miss"), best, bestPart,
			range + Config.Combat.MeleeHitRadius * 0.85 - 0.5 + 0.15, before, refusals()))
	end
	setHealth(B)
end

local function hotbarChecks()
	Inv.clear(A)
	Inv.clear(B)
	for _, p in ipairs({ A, B }) do
		Inv.give(p, "apple", 5)
		Inv.give(p, "bandage", 4)
		Inv.give(p, "berries", 8)
		Inv.give(p, "knife", 1, 2)
	end
	L(duel(A, B, 6))
	task.wait(0.8)
	-- both at once: drop one apple, equip, drop a berry, take whatever is in reach, again and again
	local done = 0
	for _, p in ipairs({ A, B }) do
		task.spawn(function()
			for i = 1, 5 do
				call(p, "fire", { name = "DropSlot", a = 1, b = 1 }, 2)
				call(p, "fire", { name = "EquipSlot", a = (i % 4) + 1 }, 2)
				call(p, "fire", { name = "DropSlot", a = 3, b = 1 }, 2)
				task.wait(0.12)
				call(p, "prompt", { radius = 9 }, 3)
			end
			done += 1
		end)
	end
	waitFor(function()
		return done >= 2
	end, 40)
	task.wait(1.5)
	local ok, detail = true, {}
	for _, p in ipairs({ A, B }) do
		local w = call(p, "probe", { kind = "weap" }) or {}
		local server = bagStr(p)
		ok = ok and w.inv == server
		table.insert(detail, string.format("%s server [%s] client [%s]", p.Name, server, tostring(w.inv)))
	end
	check("w.hotbar.syncUnderLoad", ok, table.concat(detail, " | "))
end

-- three players: the machete's second contender in the arc (60%), and the third player's own Gold and Armoury untouched
local function sweepChecks()
	if not P3 then
		return
	end
	setupDuel()
	Inv.clear(A)
	Inv.clear(B)
	Inv.clear(P3)
	Inv.give(A, "machete", 1, 1)
	setHealth(B)
	setHealth(P3)
	L(duel(A, B, 4.5))
	local _, ra = parts(A)
	local _, rb = parts(B)
	if ra and rb then
		-- P3 beside B, 2.5 studs to its side: inside the 55-degree arc at about 5 studs
		local side = Vector3.new(-duelDir.Z, 0, duelDir.X)
		local q = rb.Position + side * 2.5
		standAt(P3, q.X, q.Z, ra.Position, rb.Position.Y)
	end
	task.wait(0.8)
	local h3 = health(P3)
	local r = attack("machete with two in the arc", { { "aimset", false }, { "select", slotWith(A, "machete", 1) }, { "wait", 0.8 }, { "face", B.Name }, { "wait", 0.4 },
		{ "click" }, { "wait", 0.5 } })
	local d3 = h3 - health(P3)
	local def = Stars.def("machete", 1)
	check("w.machete.secondTarget", math.abs(r.dealt - def.damage) < 0.3 and math.abs(d3 - def.damage * (def.sweepShare or 0.6)) < 0.3, string.format(
		"A's machete at B (4.5 studs) with %s beside B: B lost %.2f (expected %.2f), %s lost %.2f (expected %.2f, the second in the arc)", P3.Name, r.dealt, def.damage,
		P3.Name, d3, def.damage * (def.sweepShare or 0.6)))
	setHealth(B)
	setHealth(P3)
	local e3 = econOf(P3)
	check("w.thirdPlayer.untouched", (e3.Draws or 0) == 0 and armStr(e3.Armoury) == "" and goldOf(P3) == (W.gold3 or goldOf(P3)), string.format(
		"%s (no draws of its own): draws %s, armoury '%s', Gold %d (at the start of the round %s)", P3.Name, tostring(e3.Draws), armStr(e3.Armoury), goldOf(P3),
		tostring(W.gold3)))
end

local function batchW()
	check("w.kit.notAtHorn", Inv.count(A, "machete") == 0 and Inv.count(A, "short_bow") == 0 and Inv.count(A, "arrow") == 0 and Inv.count(B, "knife") == 0,
		"Kits.Delivery=" .. tostring(KitSvc and KitSvc.deliveryMode()) .. ": nothing of the kit in the bag at the horn: A " .. bagStr(A) .. " | B " .. bagStr(B))
	-- they have to move to take part (the round's Gold): a walk each
	call(A, "move", { seconds = 3 })
	call(B, "move", { seconds = 3 })
	task.wait(3.2)
	local steps = {
		{ "kits", kitChecks },
		{ "stars", starChecks },
		{ "sweep", sweepChecks },
		{ "bow", bowChecks },
		{ "raw", rawClaimChecks },
		{ "hotbar", hotbarChecks },
	}
	local only = if type(ARGS.wsteps) == "string" then "," .. ARGS.wsteps .. "," else nil
	for _, s in ipairs(steps) do
		if only and not string.find(only, "," .. s[1] .. ",", 1, true) then
			continue
		end
		local ok, err = pcall(s[2])
		if not ok then
			L("DRIVER ERROR in " .. s[1] .. ": " .. string.gsub(tostring(err), "\n", " | "))
		end
	end
	if only and not string.find(only, ",round,", 1, true) then
		return
	end
	check("w.hitCap", maxDealt.n <= 95, string.format("the biggest single hit in the test: %.2f (%s); cap 95", maxDealt.n, maxDealt.what))
	-- the round's Gold: A defeats B
	Kits.Settings.Delivery = "Start" -- round two: the one-line switch
	Inv.clear(A)
	Inv.give(A, "sword", 1, 1)
	local mA, mB = killB("w")
	if not waitPhase("Ending", 8) then
		check("w.round.ended", false, "phase " .. phase())
	end
	task.wait(3.0)
	local gA = clientFind(A, "REMOTE Rewards round", mA)
	local gB = clientFind(B, "REMOTE Rewards round", mB)
	local before = W.goldBeforeRound or {}
	check("w.round.gold", gA ~= nil and gB ~= nil and string.find(gA, "firstWin=", 1, true) ~= nil and string.find(gA, "firstRound=", 1, true) ~= nil
		and string.find(gB, "firstRound=", 1, true) ~= nil and string.find(gB, "firstWin=", 1, true) == nil and goldOf(A) > (before[A] or 0) and goldOf(B) > (before[B] or 0),
		string.format("A (won, 1 defeat) told: %s | B (2nd) told: %s | Gold A %s -> %d, B %s -> %d", tostring(gA and string.sub(gA, 1, 500)), tostring(gB and string.sub(gB, 1, 500)),
			tostring(before[A]), goldOf(A), tostring(before[B]), goldOf(B)))
	backToLobby("w", { A, B })
	task.wait(2.0)
	local yA, yB = call(A, "probe", { kind = "yourgold" }) or {}, call(B, "probe", { kind = "yourgold" }) or {}
	local goldA, goldB = num(gA, "gold"), num(gB, "gold")
	local okBoard = #yA > 0 and #yB > 0 and goldA ~= nil and goldB ~= nil and string.find(table.concat(yA, " "), "+" .. tostring(goldA), 1, true) ~= nil
		and string.find(table.concat(yB, " "), "+" .. tostring(goldB), 1, true) ~= nil
	check("w.round.boardLine", okBoard, string.format("A's board: [%s] (A got %s) | B's board: [%s] (B got %s)", table.concat(yA, " ; "), tostring(goldA), table.concat(yB, " ; "),
		tostring(goldB)))
	shot("w_board_gold", 0.8)
	local dA, dB = (econOf(A).Daily or {}), (econOf(B).Daily or {})
	local gBefore = goldOf(B)
	Data.testRejoin(B)
	waitFor(function()
		return Data.isLoaded(B)
	end, 10)
	check("w.round.dailySaved", dA.firstRound == true and dA.firstWin == true and dB.firstRound == true and dB.firstWin ~= true and goldOf(B) == gBefore, string.format(
		"A daily %s | B daily %s | B rejoined: Gold %d -> %d", fmt(dA), fmt(dB), gBefore, goldOf(B)))
	-- round two with Kits.Delivery = "Start": the kit and the brought weapon in the bag at the horn
	if roundStartChecks("round2") then
		task.wait(1.0)
		local want = W.macheteStars or 3
		check("w.kit.deliveryStart", slotWith(A, "machete", want) ~= nil and Inv.count(A, "arrow") == 8 and Inv.count(A, "apple") >= 1 and Inv.count(A, "short_bow") == 0
			and slotWith(B, "knife", 1) ~= nil and Inv.count(B, "apple") >= 3, string.format("Kits.Delivery=%s at the horn: A %s | B %s", tostring(KitSvc and KitSvc.deliveryMode()),
			bagStr(A), bagStr(B)))
		local wA = call(A, "probe", { kind = "weap" }) or {}
		L("round2 A's client bag " .. tostring(wA.inv))
	end
end
if ARGS.batch == "W" then
	lobbyExtra = wLobby
end

local function run()
	local batch = tostring(ARGS.batch or "A")
	L("BATCH " .. batch)
	if not lobbyChecks() then
		return
	end
	if batch == "E" then
		batchE()
		return
	end
	if batch == "G" then
		batchG()
		return
	end
	if batch == "H" then
		SKIP_BY.round1 = A
	end
	if not roundStartChecks("round1") then
		return
	end
	if batch == "A" then
		combatChecks()
	elseif batch == "B" then
		batchB()
	elseif batch == "B2" then
		batchB2()
	elseif batch == "C" then
		batchC()
	elseif batch == "D" then
		batchD()
	elseif batch == "H" then
		batchH()
	elseif batch == "W" then
		batchW()
	end
end

task.spawn(function()
	local ok, err = xpcall(run, function(e)
		return tostring(e) .. " | " .. debug.traceback()
	end)
	if not ok then
		L("DRIVER ERROR " .. (string.gsub(tostring(err), "\n", " | ")))
	end
	task.wait(1.0)
	pcall(logChecks)
	L("RESULTS " .. table.concat(results, " "))
	endTest("batch done")
end)
