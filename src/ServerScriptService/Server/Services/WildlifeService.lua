--[[
	WildlifeService - the squirrels: small animals that live at the trees of the meadow and the wood, to be hunted and
	cooked (CookingService). The server half; WildlifeController draws them. Numbers: Shared.WildlifeConfig.

	What a squirrel does
	  It forages round its home tree (short hops, a nibble, a sit-up to look about). It notices contenders by how loud
	  they are: sprinting from far away, jogging from closer, crouch-walking only from a few steps, and from further
	  when it is sitting up. Then it sits up and stares for under a second (the stalker's moment), bolts to a near
	  tree away from the contender, runs up the trunk and sits there, slipping round the trunk when someone circles
	  it. It comes back down when nobody has been near for a while.
	  It can be hit by an arrow, a thrown knife or spear, or a swing from close up. A hit squirrel falls still and
	  fades, and a "Squirrel" item lies where it was (LootService.spawnGroundItem: the usual Take prompt). No blood,
	  no cry. Its home is empty for a few minutes, then another comes down the tree when nobody is close.

	How it is kept cheap
	  A squirrel is a row of numbers on the server: no Instance, no physics, no Humanoid. Only squirrels with a player
	  in range are simulated, TickRate times a second, never more than AwakeBase + AwakePerPlayer x players
	  (AwakeMax); the others keep their last state. A client is told only about the squirrels near it, and only when
	  one changes what it is doing (a move from A to B with a start time: the client plays it), not every step.
	  Trees are indexed once at start-up (the Bark part of every tree Model in workspace.Arena.Scatter and the like),
	  so "the nearest tree" is a table lookup.

	Hits without touching the combat code
	  Projectiles: this service wraps ProjectileService.fire at Init (the same table CombatService calls), follows each
	  accepted shot's arc itself and tests it against the squirrels near it. The real projectile flies on and sticks
	  where it lands, to be picked up as always.
	  Swings: a second listener on the MeleeSwing remote (the strike message) checks the squirrels in front of the
	  attacker with the held weapon's range.
	  The hunter gets the ordinary HitConfirm (target = "Creature"), so the hit marker and its knock play.

	Remote (created here, like PlusService's; not in Net.Names): ReplicatedStorage.Remotes.WildlifeState
	  server -> client: one flat array, 11 numbers a squirrel:
	    id, state, x0, y0, z0, x1, y1, z1, t0 (server time the move starts), duration, yaw
	  state: 0 forget it, 1 Idle (nibbling), 2 Hop, 3 Sit, 4 Alert, 5 Flee, 6 Climb, 7 Perch, 8 Descend, 9 Hit
	  yaw: on the ground the way it faces (radians, atan2(x, z)); on a trunk the way from it to the trunk's axis.

	API
	  WildlifeService.nearestTree(position, radius) -> { x, y, z, bark, kind }?   (CookingService: sticks come from trees)
	  WildlifeService.hunted: Signal(player, weaponId)
	  WildlifeService.stats() -> { total, alive, awake, watchers, trees, tickMs, tickMaxMs, projMs, sent }
	Studio only: workspace attribute WildlifeTest = "near:N" puts N more squirrels on the trees nearest the first
	  contender (to reach the caps), "calm" / "scare" switches their senses off / on; workspace attribute WildlifeStats
	  is written every 2 s with the numbers of stats().
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureLooks = require(Shared:WaitForChild("CreatureLooks"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Signal = require(Shared:WaitForChild("Signal"))
local WildlifeConfig = require(Shared:WaitForChild("WildlifeConfig"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local SQ = WildlifeConfig.Squirrel
local IS_STUDIO = RunService:IsStudio()

local WildlifeService = {}
WildlifeService.hunted = Signal.new()

local REMOTE_NAME = "WildlifeState"
local TREE_CELL = 48
local HOME_CELL = 128

local S_FORGET, S_IDLE, S_HOP, S_SIT, S_ALERT, S_FLEE, S_CLIMB, S_PERCH, S_DESCEND, S_HIT = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9
local S_GONE = 10 -- server only: hunted, waiting to be replaced

type Tree = { x: number, y: number, z: number, bark: BasePart, kind: number, r: number }
type Squirrel = {
	id: number,
	home: Tree,
	tree: Tree?, -- the tree it is on (Climb / Perch / Descend)
	state: number,
	x0: number, y0: number, z0: number,
	x1: number, y1: number, z1: number,
	t0: number,
	t1: number,
	yaw: number,
	think: number, -- when it next decides something
	calmAt: number, -- (Perch) when it may come down
	shuffleAt: number,
	respawnAt: number,
	grounded: boolean, -- its ground height has been looked up
	watchers: { Player },
	nearest: number, -- distance to the nearest contender at the last interest pass
}

local Services: { [string]: any } = {}
local remote: RemoteEvent? = nil
local rng = Random.new()

local trees: { Tree } = {}
local treeCells: { [number]: { Tree } } = {}
local treesReady = false

local squirrels: { Squirrel } = {}
local byId: { [number]: Squirrel } = {}
local homeCells: { [number]: { Squirrel } } = {}
local awake: { Squirrel } = {}
local nextId = 0
local roundOn = false
local senses = true

local known: { [Player]: { [number]: boolean } } = {}
local knownCount: { [Player]: number } = {}
local outbox: { [Player]: { number } } = {}

type Info = { pos: Vector3, noise: number, speed: number, alive: boolean }
local infos: { [Player]: Info } = {}

local stat = { tickMs = 0, tickMaxMs = 0, projMs = 0, sent = 0, ticks = 0 }

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.IgnoreWater = false

local barkParams = RaycastParams.new()
barkParams.FilterType = Enum.RaycastFilterType.Include

--------------------------------------------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local function cellKey(x: number, z: number, size: number): number
	return math.floor(x / size) * 4096 + math.floor(z / size)
end

local function phaseOn(): boolean
	local phase = GameState:GetAttribute("Phase")
	return phase == "Active" or phase == "Countdown"
end

local function isAlive(player: Player): boolean
	local playerService = Services.PlayerService
	if playerService and type(playerService.isAlive) == "function" then
		local ok, alive = pcall(playerService.isAlive, player)
		return ok and alive == true
	end
	return player:GetAttribute("Alive") == true
end

-- Ground height under (x, z) near y, or nil over water or where there is no terrain.
local function groundAt(x: number, y: number, z: number): number?
	local result = workspace:Raycast(Vector3.new(x, y + 40, z), Vector3.new(0, -140, 0), terrainParams)
	if not result or result.Material == Enum.Material.Water then
		return nil
	end
	return result.Position.Y
end

local function positionOf(s: Squirrel, t: number): (number, number, number)
	if t >= s.t1 then
		return s.x1, s.y1, s.z1
	end
	local span = s.t1 - s.t0
	local a = if span > 1e-4 then math.clamp((t - s.t0) / span, 0, 1) else 1
	return s.x0 + (s.x1 - s.x0) * a, s.y0 + (s.y1 - s.y0) * a, s.z0 + (s.z1 - s.z0) * a
end

local function onTrunk(s: Squirrel): boolean
	return s.state == S_CLIMB or s.state == S_PERCH or s.state == S_DESCEND
end

-- Its middle: what a shot or a swing has to pass.
local function centreOf(s: Squirrel, t: number): Vector3
	local x, y, z = positionOf(s, t)
	if onTrunk(s) then
		-- yaw points at the trunk's axis: its body sits a little off the bark
		return Vector3.new(x - math.sin(s.yaw) * 0.3, y, z - math.cos(s.yaw) * 0.3)
	end
	return Vector3.new(x, y + 0.45, z)
end

--------------------------------------------------------------------------------------------------------------------
-- Trees
--------------------------------------------------------------------------------------------------------------------

local TREE_KINDS: { { any } } = { { "Beech", 1 }, { "Oak", 1 }, { "Birch", 1 }, { "Pine", 2 }, { "Fir", 3 }, { "Spruce", 3 }, { "Larch", 3 } }

local function treeKind(name: string): number?
	for _, entry in ipairs(TREE_KINDS) do
		if string.find(name, entry[1], 1, true) then
			return entry[2]
		end
	end
	return nil
end

local function barkOf(model: Instance): BasePart?
	local climbable: BasePart? = nil
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			if string.sub(child.Name, -5) == "_Bark" or child.Name == "Trunk" then
				return child
			end
			-- the climbable trees (Shared.TreeClimb): the Blender TC meshes have no "_Bark" part; their trunk is the
			-- collision part tagged "Climbable" (TC_<asset>_Trunk_Col). Without this every TC pine and beech (7,653 on
			-- Map 1, 18 Nov) was left out of the index and no squirrel lived on or fled up one.
			if not climbable and CollectionService:HasTag(child, "Climbable") then
				climbable = child
			end
		end
	end
	return climbable
end

local function addTree(model: Model, kind: number)
	local bark = barkOf(model)
	if not bark then
		return
	end
	local pivot = model:GetPivot().Position
	-- a fir or pine trunk is a pole: half its bark's footprint. A beech's bark holds its limbs too: a fixed guess,
	-- corrected by a ray against the bark when a squirrel climbs it.
	local radius = if kind == 1 then 0.9 else math.clamp(math.min(bark.Size.X, bark.Size.Z) * 0.4, 0.5, 1.6)
	local tree: Tree = { x = pivot.X, y = pivot.Y, z = pivot.Z, bark = bark, kind = kind, r = radius }
	table.insert(trees, tree)
	local key = cellKey(tree.x, tree.z, TREE_CELL)
	local cell = treeCells[key]
	if not cell then
		cell = {}
		treeCells[key] = cell
	end
	table.insert(cell, tree)
end

local function indexTrees()
	local arena = workspace:WaitForChild("Arena", 30)
	if not arena then
		treesReady = true
		return
	end
	local budget = 0
	local function scan(folder: Instance, depth: number)
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") then
				local kind = treeKind(child.Name)
				if kind then
					addTree(child, kind)
				end
			elseif child:IsA("Folder") and depth < 3 then
				scan(child, depth + 1)
			end
			budget += 1
			if budget >= 1500 then
				budget = 0
				task.wait()
			end
		end
	end
	for _, name in ipairs({ "Scatter", "Forest", "Trees" }) do
		local folder = arena:FindFirstChild(name)
		if folder then
			scan(folder, 0)
		end
	end
	treesReady = true
end

local function treesNear(x: number, z: number, radius: number, out: { Tree })
	table.clear(out)
	local span = math.ceil(radius / TREE_CELL)
	local cx, cz = math.floor(x / TREE_CELL), math.floor(z / TREE_CELL)
	local r2 = radius * radius
	for i = cx - span, cx + span do
		for j = cz - span, cz + span do
			local cell = treeCells[i * 4096 + j]
			if cell then
				for _, tree in ipairs(cell) do
					local dx, dz = tree.x - x, tree.z - z
					if dx * dx + dz * dz <= r2 and tree.bark.Parent then
						table.insert(out, tree)
					end
				end
			end
		end
	end
end

local scratchTrees: { Tree } = {}

function WildlifeService.nearestTree(position: Vector3, radius: number): Tree?
	treesNear(position.X, position.Z, radius, scratchTrees)
	local best, bestD = nil, math.huge
	for _, tree in ipairs(scratchTrees) do
		local dx, dz = tree.x - position.X, tree.z - position.Z
		local d = dx * dx + dz * dz
		if d < bestD and math.abs(tree.y - position.Y) < 40 then
			best, bestD = tree, d
		end
	end
	return best
end

-- Where the bark is at height y on the side `dirX, dirZ` (unit, pointing away from the axis): distance from the axis.
local function barkRadius(tree: Tree, y: number, dirX: number, dirZ: number): number
	barkParams.FilterDescendantsInstances = { tree.bark }
	local from = Vector3.new(tree.x + dirX * 6, y, tree.z + dirZ * 6)
	local result = workspace:Raycast(from, Vector3.new(-dirX * 6, 0, -dirZ * 6), barkParams)
	if result then
		return math.clamp(6 - result.Distance, 0.2, 3.5)
	end
	return tree.r
end

--------------------------------------------------------------------------------------------------------------------
-- Telling the clients
--------------------------------------------------------------------------------------------------------------------

local function r2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local function append(out: { number }, s: Squirrel, state: number)
	local n = #out
	out[n + 1] = s.id
	out[n + 2] = state
	out[n + 3] = r2(s.x0)
	out[n + 4] = r2(s.y0)
	out[n + 5] = r2(s.z0)
	out[n + 6] = r2(s.x1)
	out[n + 7] = r2(s.y1)
	out[n + 8] = r2(s.z1)
	out[n + 9] = math.floor(s.t0 * 1000 + 0.5) / 1000
	out[n + 10] = r2(s.t1 - s.t0)
	out[n + 11] = r2(s.yaw)
end

local function queueFor(player: Player, s: Squirrel, state: number)
	local out = outbox[player]
	if not out then
		out = {}
		outbox[player] = out
	end
	append(out, s, state)
end

-- Its state changed: everyone watching it hears.
local function push(s: Squirrel)
	local state = if s.state == S_GONE then S_FORGET else s.state
	for _, player in ipairs(s.watchers) do
		queueFor(player, s, state)
	end
end

local function flush()
	local event = remote
	for player, out in pairs(outbox) do
		if #out > 0 then
			if event and player.Parent == Players then
				event:FireClient(player, out)
				stat.sent += #out / 11
			end
			outbox[player] = {}
		end
	end
end

local function unwatch(s: Squirrel, player: Player, tell: boolean)
	local index = table.find(s.watchers, player)
	if index then
		table.remove(s.watchers, index)
	end
	local set = known[player]
	if set and set[s.id] then
		set[s.id] = nil
		knownCount[player] = math.max(0, (knownCount[player] or 1) - 1)
		if tell then
			queueFor(player, s, S_FORGET)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- A squirrel's moves
--------------------------------------------------------------------------------------------------------------------

local function stay(s: Squirrel, t: number, state: number, yaw: number?)
	local x, y, z = positionOf(s, t)
	s.x0, s.y0, s.z0 = x, y, z
	s.x1, s.y1, s.z1 = x, y, z
	s.t0, s.t1 = t, t
	s.state = state
	if yaw then
		s.yaw = yaw
	end
end

local function moveTo(s: Squirrel, t: number, state: number, x: number, y: number, z: number, speed: number)
	local px, py, pz = positionOf(s, t)
	local dx, dy, dz = x - px, y - py, z - pz
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	s.x0, s.y0, s.z0 = px, py, pz
	s.x1, s.y1, s.z1 = x, y, z
	s.t0 = t
	s.t1 = t + distance / math.max(speed, 0.1)
	s.state = state
	if state ~= S_CLIMB and state ~= S_DESCEND and (dx * dx + dz * dz) > 1e-4 then
		s.yaw = math.atan2(dx, dz)
	end
end

-- Its ground height is looked up the first time someone can see it.
local function ground(s: Squirrel): boolean
	if s.grounded then
		return true
	end
	local home = s.home
	for _ = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(2.5, 8)
		local x, z = home.x + math.cos(a) * d, home.z + math.sin(a) * d
		local y = groundAt(x, home.y, z)
		if y and math.abs(y - home.y) < 9 then
			s.x0, s.y0, s.z0 = x, y, z
			s.x1, s.y1, s.z1 = x, y, z
			s.yaw = rng:NextNumber(-math.pi, math.pi)
			s.grounded = true
			return true
		end
	end
	return false
end

local function forage(s: Squirrel, t: number)
	local roll = rng:NextNumber()
	if roll < 0.55 then
		local home = s.home
		local px, py, pz = positionOf(s, t)
		for _ = 1, 4 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(3, 9)
			local x, z = px + math.cos(a) * d, pz + math.sin(a) * d
			local hx, hz = x - home.x, z - home.z
			if hx * hx + hz * hz <= SQ.HomeRange * SQ.HomeRange and hx * hx + hz * hz > (home.r + 1) * (home.r + 1) then
				local y = groundAt(x, py, z)
				if y and math.abs(y - py) < 5 then
					moveTo(s, t, S_HOP, x, y, z, SQ.HopSpeed)
					s.think = s.t1 + rng:NextNumber(0.5, 2.6)
					return
				end
			end
		end
		stay(s, t, S_IDLE)
		s.think = t + rng:NextNumber(1, 2)
	elseif roll < 0.76 then
		stay(s, t, S_SIT, rng:NextNumber(-math.pi, math.pi))
		s.think = t + rng:NextNumber(1.6, 3.6)
	else
		stay(s, t, S_IDLE)
		s.think = t + rng:NextNumber(1.5, 4)
	end
end

-- The tree to run to: near, and not past the contender.
local function pickFleeTree(s: Squirrel, px: number, pz: number, tx: number, tz: number): Tree
	treesNear(px, pz, SQ.FleeTreeRange, scratchTrees)
	local best, bestScore = s.home, math.huge
	local toThreatX, toThreatZ = tx - px, tz - pz
	local threatDistance = math.sqrt(toThreatX * toThreatX + toThreatZ * toThreatZ)
	for _, tree in ipairs(scratchTrees) do
		local dx, dz = tree.x - px, tree.z - pz
		local d = math.sqrt(dx * dx + dz * dz)
		local score = d * (if tree.kind == 3 then 1.25 else 1)
		if d > 0.5 and threatDistance > 0.5 then
			local dot = (dx * toThreatX + dz * toThreatZ) / (d * threatDistance)
			if dot > 0.35 and d > threatDistance * 0.45 then
				score += 30 -- it would run at the contender
			end
		end
		if math.abs(tree.y - s.y1) > 12 then
			score += 40
		end
		if score < bestScore then
			best, bestScore = tree, score
		end
	end
	return best
end

local function flee(s: Squirrel, t: number, threat: Vector3)
	local px, py, pz = positionOf(s, t)
	local tree = pickFleeTree(s, px, pz, threat.X, threat.Z)
	-- the side of the trunk away from the contender
	local ax, az = tree.x - threat.X, tree.z - threat.Z
	local length = math.sqrt(ax * ax + az * az)
	if length < 0.01 then
		ax, az, length = 1, 0, 1
	end
	ax, az = ax / length, az / length
	local baseY = groundAt(tree.x + ax * (tree.r + 0.6), tree.y, tree.z + az * (tree.r + 0.6)) or tree.y
	s.tree = tree
	moveTo(s, t, S_FLEE, tree.x + ax * (tree.r + 0.35), baseY, tree.z + az * (tree.r + 0.35), SQ.FleeSpeed)
	s.think = s.t1
end

local function climb(s: Squirrel, t: number)
	local tree = s.tree or s.home
	local dx, dz = s.x1 - tree.x, s.z1 - tree.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 0.01 then
		dx, dz, length = 1, 0, 1
	end
	dx, dz = dx / length, dz / length
	local range = if tree.kind == 1 then SQ.PerchBeech else SQ.PerchConifer
	local height = rng:NextNumber(range[1], range[2])
	local baseY = s.y1
	local r0 = barkRadius(tree, baseY + 1.2, dx, dz)
	local r1 = barkRadius(tree, baseY + height, dx, dz)
	-- start on the bark a little above the ground, end at the perch
	s.x0, s.y0, s.z0 = tree.x + dx * r0, baseY + 0.5, tree.z + dz * r0
	s.x1, s.y1, s.z1 = tree.x + dx * r1, baseY + height, tree.z + dz * r1
	s.t0 = t
	s.t1 = t + height / SQ.ClimbSpeed
	s.yaw = math.atan2(-dx, -dz) -- toward the axis
	s.state = S_CLIMB
	s.think = s.t1
end

local function perch(s: Squirrel, t: number)
	stay(s, t, S_PERCH)
	s.calmAt = t + rng:NextNumber(SQ.CalmMin, SQ.CalmMax)
	s.shuffleAt = t + 0.8
	s.think = t + 0.5
end

local function descend(s: Squirrel, t: number)
	local tree = s.tree or s.home
	local dx, dz = s.x1 - tree.x, s.z1 - tree.z
	local length = math.max(math.sqrt(dx * dx + dz * dz), 0.01)
	dx, dz = dx / length, dz / length
	local baseY = groundAt(tree.x + dx * (tree.r + 0.6), tree.y, tree.z + dz * (tree.r + 0.6)) or tree.y
	local r0 = barkRadius(tree, baseY + 1.2, dx, dz)
	local px, py, pz = positionOf(s, t)
	s.x0, s.y0, s.z0 = px, py, pz
	s.x1, s.y1, s.z1 = tree.x + dx * (r0 + 0.3), baseY, tree.z + dz * (r0 + 0.3)
	s.t0 = t
	s.t1 = t + math.max(py - baseY, 0.5) / SQ.DescendSpeed
	s.state = S_DESCEND
	s.think = s.t1
end

-- Round the trunk to the side away from the contender (same height).
local function shuffle(s: Squirrel, t: number, threat: Vector3)
	local tree = s.tree or s.home
	local ax, az = tree.x - threat.X, tree.z - threat.Z
	local length = math.sqrt(ax * ax + az * az)
	if length < 0.5 then
		return
	end
	ax, az = ax / length, az / length
	local r = barkRadius(tree, s.y1, ax, az)
	s.x0, s.y0, s.z0 = s.x1, s.y1, s.z1
	s.x1, s.z1 = tree.x + ax * r, tree.z + az * r
	s.t0, s.t1 = t, t + 0.3
	s.yaw = math.atan2(-ax, -az)
	s.state = S_PERCH
end

--------------------------------------------------------------------------------------------------------------------
-- Population
--------------------------------------------------------------------------------------------------------------------

local function addSquirrel(home: Tree): Squirrel
	nextId += 1
	local s: Squirrel = {
		id = nextId,
		home = home,
		tree = nil,
		state = S_IDLE,
		x0 = home.x + 3, y0 = home.y, z0 = home.z,
		x1 = home.x + 3, y1 = home.y, z1 = home.z,
		t0 = 0,
		t1 = 0,
		yaw = 0,
		think = 0,
		calmAt = 0,
		shuffleAt = 0,
		respawnAt = 0,
		grounded = false,
		watchers = {},
		nearest = math.huge,
	}
	table.insert(squirrels, s)
	byId[s.id] = s
	local key = cellKey(home.x, home.z, HOME_CELL)
	local cell = homeCells[key]
	if not cell then
		cell = {}
		homeCells[key] = cell
	end
	table.insert(cell, s)
	return s
end

local function clearAll()
	for _, s in ipairs(squirrels) do
		for _, player in ipairs(s.watchers) do
			queueFor(player, s, S_FORGET)
		end
	end
	flush()
	table.clear(squirrels)
	table.clear(byId)
	table.clear(homeCells)
	table.clear(awake)
	table.clear(known)
	table.clear(knownCount)
end

local function borderCentre(): Vector3
	local centre = GameState:GetAttribute("BorderCenter")
	return if typeof(centre) == "Vector3" then centre else Vector3.zero
end

-- Homes: small groups round a tree, spread over the meadow's copses, the wood's edge and the wood inside the ring.
local function populate()
	local startRadius = tonumber(GameState:GetAttribute("BorderStartRadius")) or tonumber(Config.Border.StartRadius) or 640
	local contenders = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Alive") == true or player:GetAttribute("InArena") == true then
			contenders += 1
		end
	end
	contenders = math.max(1, contenders, tonumber(GameState:GetAttribute("StartedCount")) or 0,
		tonumber(GameState:GetAttribute("AliveCount")) or 0)
	local pop = SQ.Population
	local total = math.clamp(math.floor(pop.Base + pop.PerContender * contenders + 0.5), pop.Min, pop.Max)
	local centre = borderCentre()
	local limit = startRadius - SQ.BorderMargin

	local bands: { { Tree } } = { {}, {}, {} }
	for _, tree in ipairs(trees) do
		local dx, dz = tree.x - centre.X, tree.z - centre.Z
		local r = math.sqrt(dx * dx + dz * dz)
		if r <= limit then
			local band = if r < SQ.EdgeRadius then 1 elseif r < SQ.EdgeRadius + SQ.EdgeBand then 2 else 3
			table.insert(bands[band], tree)
		end
	end
	local quota = {
		math.min(math.floor(total * SQ.MeadowShare + 0.5), math.floor(#bands[1] * SQ.MeadowPerTree)),
		0,
		0,
	}
	if #bands[3] == 0 then
		quota[2] = total - quota[1]
	else
		quota[2] = math.floor(total * SQ.EdgeShare + 0.5)
		quota[3] = total - quota[1] - quota[2]
	end
	if #bands[2] == 0 then
		quota[1] = math.min(total, math.floor(#bands[1] * SQ.MeadowPerTree))
		quota[2], quota[3] = 0, 0
	end

	local groves: { Tree } = {}
	local spacing2 = SQ.GroveSpacing * SQ.GroveSpacing
	local nearby: { Tree } = {}
	for band = 1, 3 do
		local list = bands[band]
		local want = quota[band]
		local tries = 0
		while want > 0 and #list > 0 and tries < want * 14 + 40 do
			tries += 1
			local tree = list[rng:NextInteger(1, #list)]
			-- firs hide a squirrel in their needles: beeches and pines are liked better
			if tree.kind ~= 3 or rng:NextNumber() < 0.45 then
				local clear = true
				for _, other in ipairs(groves) do
					local dx, dz = other.x - tree.x, other.z - tree.z
					if dx * dx + dz * dz < spacing2 then
						clear = false
						break
					end
				end
				if clear then
					table.insert(groves, tree)
					local size = math.min(want, rng:NextInteger(SQ.GroveMin, SQ.GroveMax))
					treesNear(tree.x, tree.z, SQ.GroveRadius, nearby)
					for i = 1, size do
						local home = if i == 1 or #nearby == 0 then tree else nearby[rng:NextInteger(1, #nearby)]
						local s = addSquirrel(home)
						s.think = now() + rng:NextNumber(0, 3)
					end
					want -= size
				end
			end
		end
	end
	if IS_STUDIO then
		print(string.format("[Wildlife] %d squirrels in %d groups (ring %d, %d contenders; trees in reach: meadow %d, edge %d, deep %d)",
			#squirrels, #groves, startRadius, contenders, #bands[1], #bands[2], #bands[3]))
	end
end

local function startRound()
	if roundOn then
		return
	end
	roundOn = true
	task.spawn(function()
		local waited = 0
		while not treesReady and waited < 30 do
			waited += task.wait(0.25)
		end
		-- the ring's size is published at the Countdown: give it a moment
		local deadline = os.clock() + 3
		while GameState:GetAttribute("BorderStartRadius") == nil and os.clock() < deadline do
			task.wait(0.1)
		end
		if roundOn and #squirrels == 0 then
			populate()
		end
	end)
end

local function endRound()
	if not roundOn then
		return
	end
	roundOn = false
	clearAll()
end

--------------------------------------------------------------------------------------------------------------------
-- Who can see what
--------------------------------------------------------------------------------------------------------------------

local function focusOf(player: Player): Vector3?
	local focus = player.ReplicationFocus
	if focus then
		if focus:IsA("BasePart") then
			return focus.Position
		elseif focus:IsA("Model") then
			return focus:GetPivot().Position
		end
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function refreshInfos()
	table.clear(infos)
	local sprintAt = tonumber(Config.Movement and Config.Movement.SprintSpeedThreshold) or 17
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and isAlive(player) then
			local v = root.AssemblyLinearVelocity
			local speed = math.sqrt(v.X * v.X + v.Z * v.Z)
			local crouched = (character :: Model):GetAttribute("Stance") == "Crouch"
			local noise
			if speed > sprintAt then
				noise = SQ.NoiseSprint
			elseif crouched then
				noise = if speed > 1.5 then SQ.NoiseCrouchMove else SQ.NoiseCrouchStill
			else
				noise = if speed > 1.5 then SQ.NoiseMove else SQ.NoiseStand
			end
			infos[player] = { pos = root.Position, noise = noise, speed = speed, alive = true }
		end
	end
end

local interestScratch: { Squirrel } = {}

local function interestPass()
	local inR, outR = SQ.InterestIn, SQ.InterestOut
	local span = math.ceil(inR / HOME_CELL)
	for _, player in ipairs(Players:GetPlayers()) do
		local focus = focusOf(player)
		local set = known[player]
		if not set then
			set = {}
			known[player] = set
			knownCount[player] = 0
		end
		if focus then
			-- drop the far ones
			for id in pairs(set) do
				local s = byId[id]
				if not s then
					set[id] = nil
				else
					local dx, dz = s.home.x - focus.X, s.home.z - focus.Z
					if dx * dx + dz * dz > outR * outR then
						unwatch(s, player, true)
					end
				end
			end
			-- take the near ones
			local cx, cz = math.floor(focus.X / HOME_CELL), math.floor(focus.Z / HOME_CELL)
			for i = cx - span, cx + span do
				for j = cz - span, cz + span do
					local cell = homeCells[i * 4096 + j]
					if cell then
						for _, s in ipairs(cell) do
							if not set[s.id] and s.state ~= S_GONE and (knownCount[player] or 0) < SQ.PerPlayerCap then
								local dx, dz = s.home.x - focus.X, s.home.z - focus.Z
								if dx * dx + dz * dz <= inR * inR and ground(s) then
									set[s.id] = true
									knownCount[player] = (knownCount[player] or 0) + 1
									table.insert(s.watchers, player)
									queueFor(player, s, s.state)
								end
							end
						end
					end
				end
			end
		end
	end

	-- who is simulated: watched squirrels, the nearest to a contender first when there are more than the cap
	table.clear(interestScratch)
	for _, s in ipairs(squirrels) do
		if #s.watchers > 0 and s.state ~= S_GONE then
			local best = math.huge
			local x, z = s.x1, s.z1
			for _, info in pairs(infos) do
				local dx, dz = info.pos.X - x, info.pos.Z - z
				local d = dx * dx + dz * dz
				if d < best then
					best = d
				end
			end
			s.nearest = best
			table.insert(interestScratch, s)
		end
	end
	local cap = math.min(SQ.AwakeMax, SQ.AwakeBase + SQ.AwakePerPlayer * #Players:GetPlayers())
	if #interestScratch > cap then
		table.sort(interestScratch, function(a, b)
			return a.nearest < b.nearest
		end)
	end
	table.clear(awake)
	for i = 1, math.min(cap, #interestScratch) do
		awake[i] = interestScratch[i]
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The simulation step
--------------------------------------------------------------------------------------------------------------------

-- The contender it should mind most: (position, how far inside their noise it is 0..1+, distance).
local function threatTo(s: Squirrel, x: number, z: number, scale: number): (Vector3?, number)
	local bestPos, bestD = nil, math.huge
	for _, player in ipairs(s.watchers) do
		local info = infos[player]
		if info then
			local dx, dz = info.pos.X - x, info.pos.Z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < info.noise * scale and d < bestD then
				bestPos, bestD = info.pos, d
			end
		end
	end
	return bestPos, bestD
end

local function nearestContender(s: Squirrel, x: number, z: number): (Info?, number)
	local best, bestD = nil, math.huge
	for _, player in ipairs(s.watchers) do
		local info = infos[player]
		if info then
			local dx, dz = info.pos.X - x, info.pos.Z - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < bestD then
				best, bestD = info, d
			end
		end
	end
	return best, bestD
end

local function step(s: Squirrel, t: number)
	local state = s.state
	if state == S_IDLE or state == S_HOP or state == S_SIT then
		local x, _, z = positionOf(s, t)
		if senses then
			local threat, distance = threatTo(s, x, z, if state == S_SIT then SQ.WatchfulScale else 1)
			if threat then
				if distance < SQ.PanicRange then
					flee(s, t, threat)
				else
					stay(s, t, S_ALERT, math.atan2(threat.X - x, threat.Z - z))
					s.think = t + rng:NextNumber(SQ.AlertMin, SQ.AlertMax)
				end
				push(s)
				return
			end
		end
		if t >= s.think and t >= s.t1 then
			forage(s, t)
			push(s)
		end
	elseif state == S_ALERT then
		local x, _, z = positionOf(s, t)
		local threat, distance = threatTo(s, x, z, SQ.AlertStay)
		if threat and (distance < SQ.PanicRange or t >= s.think) then
			flee(s, t, threat)
			push(s)
		elseif t >= s.think then
			stay(s, t, S_IDLE)
			s.think = t + rng:NextNumber(0.8, 2)
			push(s)
		end
	elseif state == S_FLEE then
		if t >= s.t1 then
			climb(s, t)
			push(s)
		end
	elseif state == S_CLIMB then
		if t >= s.t1 then
			perch(s, t)
			push(s)
		end
	elseif state == S_PERCH then
		local info, distance = nearestContender(s, s.x1, s.z1)
		if info and distance < SQ.CalmRange then
			s.calmAt = math.max(s.calmAt, t + SQ.CalmMin * 0.6)
			if distance < SQ.ShuffleRange and info.speed > 2 and t >= s.shuffleAt and t >= s.t1 then
				local tree = s.tree or s.home
				-- on the contender's side of the trunk?
				local sx, sz = s.x1 - tree.x, s.z1 - tree.z
				local px, pz = info.pos.X - tree.x, info.pos.Z - tree.z
				if sx * px + sz * pz > 0 then
					shuffle(s, t, info.pos)
					s.shuffleAt = t + SQ.ShuffleEvery
					push(s)
				end
			end
		elseif t >= s.calmAt then
			descend(s, t)
			push(s)
		end
	elseif state == S_DESCEND then
		if t >= s.t1 then
			s.tree = nil
			stay(s, t, S_IDLE, rng:NextNumber(-math.pi, math.pi))
			s.think = t + rng:NextNumber(0.6, 2)
			push(s)
		end
	end
end

local function respawnPass(t: number)
	local centre = borderCentre()
	local radius = tonumber(GameState:GetAttribute("BorderRadius")) or math.huge
	local clear2 = SQ.RespawnClear * SQ.RespawnClear
	for _, s in ipairs(squirrels) do
		if s.state == S_GONE and t >= s.respawnAt then
			local home = s.home
			local dx, dz = home.x - centre.X, home.z - centre.Z
			local inside = dx * dx + dz * dz < (radius - 20) * (radius - 20)
			local clear = true
			for _, info in pairs(infos) do
				local px, pz = info.pos.X - home.x, info.pos.Z - home.z
				if px * px + pz * pz < clear2 then
					clear = false
					break
				end
			end
			if inside and clear then
				-- the next one is up the home tree and comes down in its own time
				local a = rng:NextNumber(0, math.pi * 2)
				local ax, az = math.cos(a), math.sin(a)
				local range = if home.kind == 1 then SQ.PerchBeech else SQ.PerchConifer
				local baseY = groundAt(home.x + ax * (home.r + 0.6), home.y, home.z + az * (home.r + 0.6)) or home.y
				local y = baseY + rng:NextNumber(range[1], range[2])
				local r = barkRadius(home, y, ax, az)
				s.tree = home
				s.x0, s.y0, s.z0 = home.x + ax * r, y, home.z + az * r
				s.x1, s.y1, s.z1 = s.x0, s.y0, s.z0
				s.t0, s.t1 = t, t
				s.yaw = math.atan2(-ax, -az)
				s.state = S_PERCH
				s.calmAt = t + rng:NextNumber(4, 10)
				s.shuffleAt = t
				s.grounded = true
			else
				s.respawnAt = t + 15
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Hits
--------------------------------------------------------------------------------------------------------------------

local function defeat(s: Squirrel, hunter: Player?, weaponId: string?, melee: boolean)
	local t = now()
	local centre = centreOf(s, t)
	local x, y, z = positionOf(s, t)
	local high = onTrunk(s)
	local outX, outZ = -math.sin(s.yaw), -math.cos(s.yaw)
	-- watchers see it fall still and fade
	s.x0, s.y0, s.z0 = x, y, z
	s.x1, s.y1, s.z1 = x, y, z
	s.t0, s.t1 = t, t
	s.state = S_HIT
	for _, player in ipairs(s.watchers) do
		queueFor(player, s, if high then -S_HIT else S_HIT) -- (negative: it was on a trunk, so it drops off it)
	end
	flush()
	s.state = S_GONE
	s.tree = nil
	s.respawnAt = t + rng:NextNumber(SQ.RespawnMin, SQ.RespawnMax)
	for i = #s.watchers, 1, -1 do
		unwatch(s, s.watchers[i], false)
	end
	local index = table.find(awake, s)
	if index then
		table.remove(awake, index)
	end

	if hunter and hunter.Parent == Players then
		Net.event("HitConfirm"):FireClient(hunter, {
			damage = 1, headshot = false, killed = true, position = centre, target = "Creature", weaponId = weaponId,
			melee = melee,
		})
		WildlifeService.hunted:Fire(hunter, weaponId)
	end
	Sfx.play("Hit_Flesh", { position = centre, volume = 0.45, exclude = hunter })

	task.delay(SQ.CarcassDelay, function()
		if not roundOn then
			return
		end
		local loot = Services.LootService
		if not loot or type(loot.spawnGroundItem) ~= "function" then
			return
		end
		local from = Vector3.new(x, y + 0.6, z)
		local velocity = if high then Vector3.new(outX * 3, 1, outZ * 3) else nil
		local ok, err = pcall(loot.spawnGroundItem, SQ.CarcassItem, 1, from, velocity)
		if not ok then
			warn("[Wildlife] the Squirrel item could not be placed: " .. tostring(err))
		end
	end)
end

-- Projectiles this service follows on its own (see the header).
type Shot = { shooter: Player?, weaponId: string, origin: Vector3, velocity: Vector3, gravity: number, born: number,
	last: Vector3, radius: number, life: number, exclude: Instance? }
local shots: { Shot } = {}
local shotParams = RaycastParams.new()
shotParams.FilterType = Enum.RaycastFilterType.Exclude
shotParams.RespectCanCollide = true
shotParams.IgnoreWater = false

local function trackShot(shooter: Player?, itemId: string, origin: Vector3, velocity: Vector3, gravity: number, opts: any)
	if not roundOn or #squirrels == 0 or #shots >= 64 then
		return
	end
	local weaponId = if type(opts) == "table" and type(opts.weaponId) == "string" then opts.weaponId else itemId
	table.insert(shots, {
		shooter = shooter,
		weaponId = weaponId,
		origin = origin,
		velocity = velocity,
		gravity = tonumber(gravity) or 0,
		born = os.clock(),
		last = origin,
		radius = if itemId == "spear" then SQ.HitRadiusSpear else SQ.HitRadius,
		life = math.min(tonumber(Config.Combat and Config.Combat.ProjectileMaxLifetime) or 6, 8),
		exclude = shooter and shooter.Character,
	})
end

local function closestOnSegment(a: Vector3, b: Vector3, p: Vector3): (number, number)
	local ab = b - a
	local length2 = ab:Dot(ab)
	local u = if length2 > 1e-8 then math.clamp((p - a):Dot(ab) / length2, 0, 1) else 0
	local q = a + ab * u
	return (p - q).Magnitude, u
end

local function stepShots()
	if #shots == 0 then
		return
	end
	local started = os.clock()
	local t = now()
	for i = #shots, 1, -1 do
		local shot = shots[i]
		local age = started - shot.born
		local position = shot.origin + shot.velocity * age + Vector3.new(0, -0.5 * shot.gravity * age * age, 0)
		local from = shot.last
		local delta = position - from
		local done = age >= shot.life
		local reach = 1
		if delta.Magnitude > 1e-3 then
			-- it stops where the real one stops: at the first solid thing
			local arena = workspace:FindFirstChild("Arena")
			local loot = arena and arena:FindFirstChild("Loot")
			local exclude = {}
			if shot.exclude then
				table.insert(exclude, shot.exclude)
			end
			if loot then
				table.insert(exclude, loot)
			end
			shotParams.FilterDescendantsInstances = exclude
			local wall = workspace:Raycast(from, delta, shotParams)
			if wall then
				reach = wall.Distance / delta.Magnitude
				done = true
			end
			local best: Squirrel? = nil
			local bestU = math.huge
			for _, s in ipairs(awake) do
				if s.state ~= S_GONE then
					local d, u = closestOnSegment(from, position, centreOf(s, t))
					if d <= shot.radius and u <= reach + 0.02 and u < bestU then
						best, bestU = s, u
					end
				end
			end
			if best then
				defeat(best, shot.shooter, shot.weaponId, false)
				done = true
			end
		end
		shot.last = position
		if done then
			table.remove(shots, i)
		end
	end
	stat.projMs = stat.projMs * 0.95 + (os.clock() - started) * 1000 * 0.05
end

local function onMeleeSwing(player: Player, lookDirection: any)
	if not roundOn or typeof(lookDirection) ~= "Vector3" then
		return -- ("Start" messages and anything malformed)
	end
	if GameState:GetAttribute("Phase") ~= "Active" or player:GetAttribute("Frozen") == true or not isAlive(player) then
		return
	end
	if not Net.rateLimit(player, "WildlifeSwing", 3, 2) then
		return
	end
	local magnitude = lookDirection.Magnitude
	if magnitude ~= magnitude or magnitude < 0.9 or magnitude > 1.1 then
		return
	end
	local direction = lookDirection / magnitude
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local inventory = Services.InventoryService
	local itemId = nil
	if inventory and type(inventory.getEquipped) == "function" then
		itemId = inventory.getEquipped(player)
	end
	local def = ItemDefs.get(itemId)
	if not def or def.kind ~= "Melee" then
		def = ItemDefs.get("fists")
	end
	local reach = (tonumber(def and def.range) or 5.5) + SQ.MeleeReachBonus
	local origin = head.Position
	local t = now()
	local set = known[player]
	if not set then
		return
	end
	local best: Squirrel? = nil
	local bestAlong = math.huge
	for _, s in ipairs(awake) do
		if set[s.id] and s.state ~= S_GONE then
			local to = centreOf(s, t) - origin
			local along = to:Dot(direction)
			if along > 0 and along <= reach and to.Magnitude <= reach + 0.5 then
				local off = (to - direction * along).Magnitude
				if off <= SQ.MeleeAimRadius and along < bestAlong then
					best, bestAlong = s, along
				end
			end
		end
	end
	if best then
		-- (this message is sent at the strike moment of the swing)
		defeat(best, player, def and def.id or "fists", true)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Studio tests
--------------------------------------------------------------------------------------------------------------------

function WildlifeService.stats()
	local alive, watched = 0, 0
	for _, s in ipairs(squirrels) do
		if s.state ~= S_GONE then
			alive += 1
		end
		if #s.watchers > 0 then
			watched += 1
		end
	end
	return {
		total = #squirrels, alive = alive, awake = #awake, watched = watched, trees = #trees,
		tickMs = stat.tickMs, tickMaxMs = stat.tickMaxMs, projMs = stat.projMs, sent = stat.sent, shots = #shots,
	}
end

local function devCommand(text: any)
	if type(text) ~= "string" or text == "" then
		return
	end
	local count = tonumber(string.match(text, "^near:(%d+)$"))
	if count then
		local origin: Vector3? = nil
		for _, info in pairs(infos) do
			origin = info.pos
			break
		end
		if not origin then
			for _, player in ipairs(Players:GetPlayers()) do
				origin = focusOf(player)
				if origin then
					break
				end
			end
		end
		if origin and treesReady then
			local list: { Tree } = {}
			treesNear(origin.X, origin.Z, 150, list)
			table.sort(list, function(a, b)
				local o = origin :: Vector3
				return (a.x - o.X) ^ 2 + (a.z - o.Z) ^ 2 < (b.x - o.X) ^ 2 + (b.z - o.Z) ^ 2
			end)
			for i = 1, count do
				local tree = list[(i - 1) % math.max(#list, 1) + 1]
				if tree then
					addSquirrel(tree).think = now() + rng:NextNumber(0, 2)
				end
			end
			roundOn = true
		end
	elseif text == "calm" then
		senses = false
	elseif text == "scare" then
		senses = true
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function WildlifeService.Init(registry)
	Services = registry
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder then
		local existing = folder:FindFirstChild(REMOTE_NAME)
		if existing and existing:IsA("RemoteEvent") then
			remote = existing
		else
			local created = Instance.new("RemoteEvent")
			created.Name = REMOTE_NAME
			created.Parent = folder
			remote = created
		end
	end
	-- the Squirrel, Cooked Squirrel and Firewood models, where ItemModels looks for every item's
	local ok, err = pcall(CreatureLooks.installItemTemplates)
	if not ok then
		warn("[Wildlife] item templates: " .. tostring(err))
	end
	-- follow every accepted shot (CombatService calls Services.ProjectileService.fire: this same field)
	local projectiles = registry.ProjectileService
	if projectiles and type(projectiles.fire) == "function" then
		local fire = projectiles.fire
		projectiles.fire = function(shooter, itemId, origin, velocity, gravity, damage, opts)
			local id = fire(shooter, itemId, origin, velocity, gravity, damage, opts)
			if id then
				local ok2, err2 = pcall(trackShot, shooter, itemId, origin, velocity, gravity, opts)
				if not ok2 then
					warn("[Wildlife] trackShot: " .. tostring(err2))
				end
			end
			return id
		end
	end
end

function WildlifeService.Start()
	task.spawn(indexTrees)
	Net.event("MeleeSwing").OnServerEvent:Connect(function(player, lookDirection)
		local ok, err = pcall(onMeleeSwing, player, lookDirection)
		if not ok then
			warn("[Wildlife] swing: " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, s in ipairs(squirrels) do
			local index = table.find(s.watchers, player)
			if index then
				table.remove(s.watchers, index)
			end
		end
		known[player] = nil
		knownCount[player] = nil
		outbox[player] = nil
	end)
	local function onPhase()
		if phaseOn() then
			startRound()
		else
			endRound()
		end
	end
	GameState:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	onPhase()
	RunService.Heartbeat:Connect(stepShots)
	if IS_STUDIO then
		workspace:GetAttributeChangedSignal("WildlifeTest"):Connect(function()
			local text = workspace:GetAttribute("WildlifeTest")
			workspace:SetAttribute("WildlifeTest", nil)
			devCommand(text)
		end)
	end

	local interval = 1 / math.max(1, SQ.TickRate)
	local sinceInterest, sinceSlow, sinceStats = 1, 0, 0
	while true do
		local dt = task.wait(interval)
		if roundOn and #squirrels > 0 then
			local started = os.clock()
			local t = now()
			refreshInfos()
			sinceInterest += dt
			if sinceInterest >= 1 then
				sinceInterest = 0
				interestPass()
			end
			for _, s in ipairs(awake) do
				if s.state ~= S_GONE then
					step(s, t)
				end
			end
			sinceSlow += dt
			if sinceSlow >= 5 then
				sinceSlow = 0
				respawnPass(t)
			end
			flush()
			local ms = (os.clock() - started) * 1000
			stat.ticks += 1
			stat.tickMs = stat.tickMs * 0.95 + ms * 0.05
			if ms > stat.tickMaxMs then
				stat.tickMaxMs = ms
			end
		end
		if IS_STUDIO then
			sinceStats += dt
			if sinceStats >= 2 then
				sinceStats = 0
				local st = WildlifeService.stats()
				workspace:SetAttribute("WildlifeStats", string.format(
					"total=%d alive=%d awake=%d watched=%d trees=%d tickMs=%.3f tickMaxMs=%.3f projMs=%.3f sent=%d shots=%d",
					st.total, st.alive, st.awake, st.watched, st.trees, st.tickMs, st.tickMaxMs, st.projMs, st.sent, st.shots))
				stat.tickMaxMs = 0
			end
		end
	end
end

return WildlifeService
