--[[
	WorldProjectiles - spent arrows, throwing knives and thrown spears stay in the world until the round's arena
	cleanup. ProjectileService's one registry: a table of entries, a coarse grid for pickups, one 0.2 s tick and one
	Heartbeat while something falls; no per-item scripts. Poses, depths and reach rules: Shared.WorldItems.

	Where they end up (ProjectileService calls these at the impact; p = its projectile, velocity = at the impact)
	  World.embed(p, result, velocity) -> Entry?   terrain or a part: the tip WorldItems.depth past the server's impact
	      point along the flight, fletching out. Anchored; welded instead to unanchored parts and supply-crate parts, so
	      it swings with an opening lid. A blade that meets stone or metal falls to the ground below instead.
	  World.sink(p, result, velocity) -> Entry?    water: it goes in at the surface, then sinks to the bed below (a
	      little ahead) and rests there, an arrow angled with its nock up
	  World.stick(p, result, bodyPart, humanoid, velocity) -> Entry?   a contender or a training dummy: welded into the
	      body part (attributes Host, HostPart), visible to everyone. It comes out onto the ground at the body when that
	      body dies or the part goes, or by itself after Config.Combat.BodyFallOutTime (~30 s), whichever comes first.
	      A body that is already dead (the killing hit included) lets it fall straight out. A training dummy lets all its
	      items out as it breaks, before its parts tumble away (CombatService calls World.releaseFrom).
	  World.land(p, params) -> Entry?   a miss that outlived its lifetime: the rest of its arc is traced to the ground
	  "The ground below" (groundHit) is terrain or a part held in place: the ray looks past bodies (a broken dummy's
	  tumbling parts too), loose parts, loot and items. An item whose part disappears (a crate replaced at the Feast, a
	  dummy's stand) drops to the ground below, whether it was embedded in that part or lying on it.
	Entries keep `pivot` (where it was placed), `rel` (pivot relative to the part it is welded to) and, while it falls
	  or sinks, `fallTo` / `fallTime` / `sink`: ProjectileImpact carries them so a client lands its own copy the same way.
	Taking them: alive contenders in Countdown/Active, once an item is loose (WorldItems.LOOSE_TAG)
	  E: TakeWorldItem(worldId) from WorldItemController's prompt; reach is checked again here (PickupRange + 2 studs,
	     no higher than PickupReachAbove + 1.5 above the root).
	  Walking over: Config.Loot.AutoPickup items (arrows, throwing knives) at your feet (WorldItems.walkOver), even if
	     you carry none; spears are E only. A short WALK_DELAY after it settles, so a shot at your feet isn't caught
	     straight back.
	  Either adds 1 to your stack (InventoryService.give; the InventoryUpdate shows "+1 ARROW") with Sfx PickUp, or says
	  INVENTORY FULL (LootService.inventoryFull; walking over items you can't carry says it at most every 4 s).
	Lifetime: until LootService.cleared (the arena cleanup at the round's end and before the next one) or the Lobby.
	  Safety cap Config.Combat.WorldItemCap (400) per server: above it the oldest go first, logged.
	Models: ItemModels "world" models in workspace.Arena.Loot.Projectiles, Atomic streaming, CanCollide / CanTouch /
	  CanQuery false, Massless; anchored ones lose their internal welds and attachments (4 instances an arrow).
	API extras: World.count() -> number, World.get(worldId) -> Entry?, World.stats() -> { [string]: number },
	  World.releaseFrom(model) -> number (everything stuck in a body comes out now), World.clear()
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Util = require(Shared:WaitForChild("Util"))
local WorldItems = require(Shared:WaitForChild("WorldItems"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local CombatCfg = Config.Combat
local LootCfg = Config.Loot

local TICK = 0.2
local CELL = 8 -- grid cell (studs, X/Z)
local WALK_DELAY = 0.75 -- seconds after it settles before walking over it picks it up
local OWN_ITEM_DELAY = 5 -- one that fell out of your own body isn't walked up by you for this long (E still works)
local FULL_TOAST_INTERVAL = 4
local HOST_SCAN_PER_TICK = 40 -- anchored items checked per tick for a vanished part (every item every ~2 s at 400)
local KILL_HEIGHT = -400
local LAND_STEP = 1 / 15
local LAND_STEPS = 450 -- 30 s of flight at most
local FALL_GRAVITY = 70 -- studs/s^2, like tossed loot (Config.Loot.TossGravity)
local GROUND_RAY = 250 -- how far down the ground below an item is looked for
local GROUND_SKIPS = 8 -- bodies and loose parts looked past on the way down (groundHit)

local World = {}

type Fall = { from: CFrame, to: CFrame, t: number, duration: number, sink: boolean }
export type Entry = {
	id: number,
	itemId: string,
	model: Model,
	shot: number,
	born: number,
	pivot: CFrame,
	rel: CFrame?,
	free: boolean,
	freeAt: number,
	grab: Vector3,
	cell: number?,
	weld: Weld?,
	host: BasePart?,
	hostHumanoid: Humanoid?,
	fallOutAt: number?,
	anchorPart: BasePart?,
	noAutoPlayer: Player?,
	noAutoUntil: number,
	fall: Fall?,
	fallTo: CFrame?,
	fallTime: number?,
	sink: boolean?,
	dead: boolean,
}

local Services: { [string]: any } = {}
local folderRef: Folder? = nil
local entries: { [number]: Entry } = {}
local order: { Entry } = {} -- oldest first; dead entries are skipped and compacted away
local orderHead = 1
local count = 0
local nextId = 0
local grid: { [number]: { Entry } } = {}
local bodies: { [Entry]: boolean } = {}
local falling: { Entry } = {}
local hostWatch: { [BasePart]: { conn: RBXScriptConnection, n: number } } = {}
local scanIndex = 1
local capRemoved = 0
local capLogged = 0 -- capRemoved when it was last logged
local lastCapLog = -math.huge
local lastFullToast: { [Player]: number } = {}
local fallConnection: RBXScriptConnection? = nil
local rng = Random.new()

--------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------

local function getFolder(): Folder
	if folderRef and folderRef.Parent then
		return folderRef
	end
	local arena = workspace:FindFirstChild("Arena")
	if not arena then
		arena = Instance.new("Folder")
		arena.Name = "Arena"
		arena.Parent = workspace
	end
	local loot = arena:FindFirstChild("Loot")
	if not loot then
		loot = Instance.new("Folder")
		loot.Name = "Loot"
		loot.Parent = arena
	end
	local folder = loot:FindFirstChild(WorldItems.FOLDER)
	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name = WorldItems.FOLDER
		folder.Parent = loot
	end
	folderRef = folder :: Folder
	return folder :: Folder
end

local function getPhase(): string
	local round = Services.RoundService
	if round and type(round.getPhase) == "function" then
		local ok, phase = pcall(round.getPhase)
		if ok and type(phase) == "string" then
			return phase
		end
	end
	return GameState:GetAttribute("Phase") or "Lobby"
end

local function isAlive(player: Player): boolean
	local playerService = Services.PlayerService
	if playerService and type(playerService.isAlive) == "function" then
		local ok, alive = pcall(playerService.isAlive, player)
		return ok and alive == true
	end
	return player:GetAttribute("Alive") == true
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function unit(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-4 then v.Unit elseif fallback.Magnitude > 1e-4 then fallback.Unit else Vector3.new(0, -1, 0)
end

local function isMovable(part: Instance): boolean
	if not part:IsA("BasePart") or part == workspace.Terrain then
		return false
	end
	if not part.Anchored then
		return true
	end
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if CollectionService:HasTag(model, "SupplyCrate") then
			return true -- a crate's lid swings open and the Feast replaces crates
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

-- The ground (and lake beds) under a point: solid geometry and terrain, never characters, dummies, loot or items.
local function groundParams(): RaycastParams
	local list: { Instance } = { getFolder() }
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, dummy in ipairs(CollectionService:GetTagged("TrainingDummy")) do
		table.insert(list, dummy)
	end
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	local items = loot and loot:FindFirstChild("Items")
	if items then
		table.insert(list, items)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

-- The body (a contender or a training dummy, alive or broken) that `part` belongs to, if any.
local function bodyModelOf(part: Instance): Model?
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

-- The first solid ground along a ray: terrain, or a part that is held in place. It looks past bodies (a broken
-- dummy's tumbling parts too: CombatService untags them and makes them collidable) and anything loose, so an item
-- never comes to rest on something that moves or is about to go.
local function groundHit(origin: Vector3, direction: Vector3, params: RaycastParams): RaycastResult?
	for _ = 1, GROUND_SKIPS do
		local hit = workspace:Raycast(origin, direction, params)
		if not hit then
			return nil
		end
		local part = hit.Instance
		if part == workspace.Terrain or not part:IsA("BasePart") then
			return hit
		end
		local skip: Instance? = bodyModelOf(part)
		if not skip and not (part :: BasePart):IsGrounded() then
			skip = part
		end
		if not skip then
			return hit
		end
		params:AddToFilter(skip)
	end
	return nil
end

-- Where `itemId` comes to rest below `position`, lying along `heading` (give or take a little), and the part it rests
-- on (nil on terrain, or with no ground below).
local function restBelow(itemId: string, position: Vector3, heading: Vector3): (CFrame, BasePart?)
	local hit = groundHit(position + Vector3.new(0, 1, 0), Vector3.new(0, -GROUND_RAY, 0), groundParams())
	local point = if hit then hit.Position else position
	local normal = if hit then hit.Normal else Vector3.yAxis
	local flat = Util.flat(heading)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	end
	local turned = CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0):VectorToWorldSpace(flat)
	local support = if hit and hit.Instance ~= workspace.Terrain and hit.Instance:IsA("BasePart")
		then hit.Instance :: BasePart
		else nil
	return WorldItems.restPivot(itemId, point, normal, turned), support
end

--------------------------------------------------------------------------------------------------------------------
-- Grid (loose items, by their grab point)
--------------------------------------------------------------------------------------------------------------------

local function cellOf(x: number, z: number): number
	return (math.floor(x / CELL) + 32768) * 65536 + (math.floor(z / CELL) + 32768)
end

local function gridInsert(entry: Entry)
	local key = cellOf(entry.grab.X, entry.grab.Z)
	local list = grid[key]
	if not list then
		list = {}
		grid[key] = list
	end
	table.insert(list, entry)
	entry.cell = key
end

local function gridRemove(entry: Entry)
	local key = entry.cell
	if not key then
		return
	end
	entry.cell = nil
	local list = grid[key]
	if not list then
		return
	end
	local index = table.find(list, entry)
	if index then
		list[index] = list[#list]
		list[#list] = nil
	end
	if #list == 0 then
		grid[key] = nil
	end
end

local function gridQuery(position: Vector3, radius: number): { Entry }
	local out = {}
	local x0, x1 = math.floor((position.X - radius) / CELL), math.floor((position.X + radius) / CELL)
	local z0, z1 = math.floor((position.Z - radius) / CELL), math.floor((position.Z + radius) / CELL)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local list = grid[(cx + 32768) * 65536 + (cz + 32768)]
			if list then
				for _, entry in ipairs(list) do
					table.insert(out, entry)
				end
			end
		end
	end
	return out
end

-- Live for items welded to something that moves (a crate lid), else where it settled.
local function grabOf(entry: Entry): Vector3
	if entry.weld then
		return WorldItems.grabPoint(entry.itemId, entry.model:GetPivot())
	end
	return entry.grab
end

--------------------------------------------------------------------------------------------------------------------
-- Entries
--------------------------------------------------------------------------------------------------------------------

local release: (entry: Entry) -> ()

local function hostGone(part: BasePart)
	local watch = hostWatch[part]
	if watch then
		watch.conn:Disconnect()
		hostWatch[part] = nil
	end
	local list = {}
	for _, entry in pairs(entries) do
		if entry.host == part then
			table.insert(list, entry)
		end
	end
	for _, entry in ipairs(list) do
		release(entry) -- where it is right now, before physics can drop it
	end
end

local function watchHost(part: BasePart)
	local watch = hostWatch[part]
	if not watch then
		local conn = part.AncestryChanged:Connect(function()
			if not part:IsDescendantOf(workspace) then
				hostGone(part)
			end
		end)
		watch = { conn = conn, n = 0 }
		hostWatch[part] = watch
	end
	watch.n += 1
end

local function unwatchHost(part: BasePart?)
	local watch = part and hostWatch[part]
	if not watch then
		return
	end
	watch.n -= 1
	if watch.n <= 0 then
		watch.conn:Disconnect()
		hostWatch[part :: BasePart] = nil
	end
end

local function makeLoose(entry: Entry)
	if entry.dead or entry.free then
		return
	end
	entry.free = true
	entry.freeAt = os.clock()
	entry.grab = WorldItems.grabPoint(entry.itemId, entry.model:GetPivot())
	gridInsert(entry)
	CollectionService:AddTag(entry.model, WorldItems.LOOSE_TAG)
end

local function unloose(entry: Entry)
	if not entry.free then
		return
	end
	entry.free = false
	gridRemove(entry)
	CollectionService:RemoveTag(entry.model, WorldItems.LOOSE_TAG)
end

local function stepFalls(dt: number)
	for i = #falling, 1, -1 do
		local entry = falling[i]
		local fall = entry.fall
		if entry.dead or not fall then
			table.remove(falling, i)
		else
			fall.t += dt
			if fall.t >= fall.duration then
				entry.model:PivotTo(fall.to)
				entry.fall = nil
				entry.fallTo, entry.fallTime, entry.sink = nil, nil, nil
				table.remove(falling, i)
				makeLoose(entry)
			else
				entry.model:PivotTo(WorldItems.fallPose(fall.from, fall.to, fall.t / fall.duration, fall.sink))
			end
		end
	end
	if #falling == 0 and fallConnection then
		fallConnection:Disconnect()
		fallConnection = nil
	end
end

-- Fall (or sink) from `from` to `to`, then it is loose.
local function fallTo(entry: Entry, from: CFrame, to: CFrame, sink: boolean)
	local drop = math.max(0, from.Position.Y - to.Position.Y)
	local gap = (to.Position - from.Position).Magnitude
	if gap < 0.05 then
		entry.model:PivotTo(to)
		makeLoose(entry)
		return
	end
	local duration = if sink
		then math.clamp(0.45 + drop * 0.07, 0.5, 1.8)
		else math.clamp(math.sqrt(2 * math.max(drop, gap * 0.5) / FALL_GRAVITY), 0.18, 0.9)
	entry.fall = { from = from, to = to, t = 0, duration = duration, sink = sink }
	entry.fallTo, entry.fallTime, entry.sink = to, duration, sink
	table.insert(falling, entry)
	if not fallConnection then
		fallConnection = RunService.Heartbeat:Connect(stepFalls)
	end
end

-- Down from `from` onto the ground below it (groundHit); it stays there until that ground goes (scanTick).
local function dropFrom(entry: Entry, from: CFrame)
	local middle = from.Position + from.LookVector * (WorldItems.tipDistance(entry.itemId) * 0.5)
	local to, support = restBelow(entry.itemId, middle, from.LookVector)
	entry.anchorPart = support
	fallTo(entry, from, to, false)
end

local function removeEntry(entry: Entry)
	if entry.dead then
		return
	end
	entry.dead = true
	if entries[entry.id] == entry then
		entries[entry.id] = nil
		count -= 1
	end
	gridRemove(entry)
	bodies[entry] = nil
	if entry.weld then
		unwatchHost(entry.host)
	end
	entry.fall = nil
	entry.model:Destroy()
end

local function compactOrder()
	local list = {}
	for i = orderHead, #order do
		local entry = order[i]
		if not entry.dead then
			table.insert(list, entry)
		end
	end
	order = list
	orderHead = 1
	scanIndex = 1
end

local function enforceCap()
	local cap = math.max(1, math.floor(tonumber(CombatCfg.WorldItemCap) or 400))
	local removed = 0
	local oldestName = nil
	while count > cap and orderHead <= #order do
		local entry = order[orderHead]
		orderHead += 1
		if not entry.dead then
			oldestName = oldestName or entry.itemId
			removeEntry(entry)
			removed += 1
		end
	end
	if removed > 0 then
		capRemoved += removed
		local now = os.clock()
		if now - lastCapLog >= 5 then -- at most one line every 5 s; the tick logs the rest as a total
			lastCapLog = now
			capLogged = capRemoved
			print(string.format("[WorldProjectiles] over the cap of %d items: removed the oldest (%s); %d removed this round",
				cap, tostring(oldestName), capRemoved))
		end
	end
	if orderHead > 64 and orderHead > #order / 2 then
		compactOrder()
	end
end

type Options = { shot: number?, weldTo: BasePart?, hostUserId: number?, hostPart: string? }

local function register(itemId: string, pivot: CFrame, opts: Options): Entry?
	local model = ItemModels.build(itemId, "world")
	local handle = model and model.PrimaryPart
	if not model or not handle then
		return nil
	end
	local welded = opts.weldTo ~= nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = not welded
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.CastShadow = d.Transparency < 1
		elseif d:IsA("Attachment") or (not welded and (d:IsA("JointInstance") or d:IsA("WeldConstraint"))) then
			d:Destroy() -- poses come from Shared.WorldItems; anchored parts need no welds
		end
	end
	nextId += 1
	local now = os.clock()
	local entry: Entry = {
		id = nextId,
		itemId = itemId,
		model = model,
		shot = opts.shot or 0,
		born = now,
		pivot = pivot,
		rel = nil,
		free = false,
		freeAt = 0,
		grab = WorldItems.grabPoint(itemId, pivot),
		cell = nil,
		weld = nil,
		host = nil,
		hostHumanoid = nil,
		fallOutAt = nil,
		anchorPart = nil,
		noAutoPlayer = nil,
		noAutoUntil = 0,
		fall = nil,
		fallTo = nil,
		fallTime = nil,
		sink = nil,
		dead = false,
	}
	model.Name = itemId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("WorldId", entry.id)
	model:SetAttribute("Shot", entry.shot)
	if opts.hostUserId then
		model:SetAttribute("Host", opts.hostUserId)
		model:SetAttribute("HostPart", opts.hostPart or "")
	end
	model:PivotTo(pivot)
	local host = opts.weldTo
	if host then
		local rel = host.CFrame:ToObjectSpace(pivot)
		local weld = Instance.new("Weld")
		weld.Name = "HostWeld"
		weld.Part0 = host
		weld.Part1 = handle
		weld.C0 = rel
		weld.Parent = handle
		entry.weld = weld
		entry.host = host
		entry.rel = rel
		watchHost(host)
	end
	CollectionService:AddTag(model, WorldItems.TAG)
	model.Parent = getFolder()
	entries[entry.id] = entry
	count += 1
	table.insert(order, entry)
	enforceCap()
	if entry.dead then
		return nil -- the cap took it straight away (a cap of 0 or 1)
	end
	return entry
end

-- Out of the body (or off the part that went): where it is now, then down onto the ground below.
release = function(entry: Entry)
	if entry.dead or entry.fall then
		return
	end
	unloose(entry) -- an item welded to a crate is loose; it can't be taken while it falls
	bodies[entry] = nil
	local humanoid = entry.hostHumanoid
	local victim = if humanoid then Players:GetPlayerFromCharacter(humanoid.Parent) else nil
	if victim then
		-- it lands at their feet: standing there doesn't put it in their bag straight away
		entry.noAutoPlayer = victim
		entry.noAutoUntil = os.clock() + OWN_ITEM_DELAY
	end
	local model = entry.model
	local from = model:GetPivot()
	if entry.weld then
		unwatchHost(entry.host)
		entry.weld:Destroy()
		entry.weld = nil
	end
	entry.host = nil
	entry.hostHumanoid = nil
	entry.rel = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(from)
	model:SetAttribute("Host", nil)
	model:SetAttribute("HostPart", nil)
	dropFrom(entry, from)
end

--------------------------------------------------------------------------------------------------------------------
-- Placing (ProjectileService)
--------------------------------------------------------------------------------------------------------------------

function World.embed(p: any, result: RaycastResult, velocity: Vector3): Entry?
	local itemId = p.recoverItem
	if type(itemId) ~= "string" then
		return nil
	end
	local dir = unit(velocity, p.velocity)
	local part = result.Instance
	local material = result.Material
	if WorldItems.glances(itemId, material) then
		-- a blade off stone or metal: it falls to the ground below
		local from = WorldItems.embedPivot(itemId, result.Position, dir)
		local entry = register(itemId, from, { shot = p.id })
		if entry then
			local to, support = restBelow(itemId, result.Position + result.Normal * 0.4, dir)
			entry.anchorPart = support
			fallTo(entry, from, to, false)
		end
		return entry
	end
	local incidence = math.abs(dir:Dot(result.Normal))
	local depth = WorldItems.depth(itemId, material, velocity.Magnitude, incidence, false)
	local pivot = WorldItems.embedPivot(itemId, result.Position + dir * depth, dir)
	local movable = isMovable(part)
	local entry = register(itemId, pivot, { shot = p.id, weldTo = if movable then part :: BasePart else nil })
	if entry then
		if not movable and part ~= workspace.Terrain and part:IsA("BasePart") then
			entry.anchorPart = part
		end
		makeLoose(entry)
	end
	return entry
end

function World.sink(p: any, result: RaycastResult, velocity: Vector3): Entry?
	local itemId = p.recoverItem
	if type(itemId) ~= "string" then
		return nil
	end
	local dir = unit(velocity, p.velocity)
	local from = WorldItems.embedPivot(itemId, result.Position + dir * 0.25, dir)
	local entry = register(itemId, from, { shot = p.id })
	if not entry then
		return nil
	end
	local params = groundParams()
	local forward = Util.flat(dir)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.xAxis
	local bed = groundHit(result.Position, Vector3.new(0, -GROUND_RAY, 0), params)
	local to = from
	if bed then
		-- it carries on a little as it sinks, then settles on the bottom
		local drift = math.min((result.Position.Y - bed.Position.Y) * 0.35, 3)
		local ahead = groundHit(result.Position + forward * drift, Vector3.new(0, -GROUND_RAY, 0), params)
		local floor = ahead or bed
		to = if itemId == "arrow"
			then WorldItems.bedPivot(itemId, floor.Position, floor.Normal, forward)
			else WorldItems.restPivot(itemId, floor.Position, floor.Normal, forward)
		if floor.Instance ~= workspace.Terrain and floor.Instance:IsA("BasePart") then
			entry.anchorPart = floor.Instance :: BasePart
		end
	end
	fallTo(entry, from, to, true)
	return entry
end

function World.stick(p: any, result: RaycastResult, bodyPart: BasePart?, humanoid: Humanoid, velocity: Vector3): Entry?
	local itemId = p.recoverItem
	if type(itemId) ~= "string" then
		return nil
	end
	local host = if bodyPart and bodyPart:IsA("BasePart") then bodyPart else result.Instance
	if not host:IsA("BasePart") then
		return World.embed(p, result, velocity)
	end
	local dir = unit(velocity, p.velocity)
	local incidence = math.abs(dir:Dot(result.Normal))
	local depth = WorldItems.depth(itemId, nil, velocity.Magnitude, incidence, true)
	local pivot = WorldItems.embedPivot(itemId, result.Position + dir * depth, dir)
	local victim = Players:GetPlayerFromCharacter(humanoid.Parent)
	if humanoid.Health <= 0 then
		-- a body that is already dead (this hit killed it, or it lay there): it falls straight out onto the ground
		-- below, before the body comes apart and carries it off
		local dropped = register(itemId, pivot, { shot = p.id })
		if dropped then
			dropFrom(dropped, pivot)
		end
		return dropped
	end
	local entry = register(itemId, pivot, {
		shot = p.id,
		weldTo = host :: BasePart,
		hostUserId = if victim then victim.UserId else 0,
		hostPart = host.Name,
	})
	if entry then
		entry.hostHumanoid = humanoid
		local fallOut = tonumber(CombatCfg.BodyFallOutTime) or 30
		entry.fallOutAt = os.clock() + fallOut * rng:NextNumber(0.9, 1.1)
		bodies[entry] = true
	end
	return entry
end

function World.land(p: any, params: RaycastParams): Entry?
	if type(p.recoverItem) ~= "string" then
		return nil
	end
	local position: Vector3 = p.position
	local velocity: Vector3 = p.velocity
	local gravity = Vector3.new(0, -(tonumber(p.gravity) or 0), 0)
	for _ = 1, LAND_STEPS do
		local displacement = velocity * LAND_STEP + gravity * (0.5 * LAND_STEP * LAND_STEP)
		local hit = workspace:Raycast(position, displacement, params)
		if hit then
			local along = math.clamp(hit.Distance / math.max(displacement.Magnitude, 1e-6), 0, 1)
			local atHit = velocity + gravity * (LAND_STEP * along)
			if hit.Material == Enum.Material.Water then
				return World.sink(p, hit, atHit)
			end
			return World.embed(p, hit, atHit)
		end
		position += displacement
		velocity += gravity * LAND_STEP
		if position.Y < KILL_HEIGHT then
			return nil -- off the edge of the world
		end
	end
	return nil
end

--------------------------------------------------------------------------------------------------------------------
-- Taking
--------------------------------------------------------------------------------------------------------------------

local function inventoryFull(player: Player, walking: boolean)
	if walking then
		local now = os.clock()
		if now - (lastFullToast[player] or -math.huge) < FULL_TOAST_INTERVAL then
			return
		end
		lastFullToast[player] = now
	end
	local loot = Services.LootService
	if loot and type(loot.inventoryFull) == "function" then
		pcall(loot.inventoryFull, player)
	else
		Net.event("Announce"):FireClient(player, { style = "Toast", text = "INVENTORY FULL", duration = 1.6 })
	end
end

local function canInteract(player: Player): boolean
	local phase = getPhase()
	return (phase == "Active" or phase == "Countdown") and isAlive(player)
end

-- Returns "taken" | "full" | nil (not allowed).
local function take(player: Player, entry: Entry, walking: boolean): string?
	if entry.dead or not entry.free then
		return nil
	end
	local root = rootOf(player)
	if not root then
		return nil
	end
	local grab = grabOf(entry)
	if walking then
		if not WorldItems.walkOver(root.Position, grab) then
			return nil
		end
	elseif not WorldItems.inReach(root.Position, grab, (LootCfg.PickupRange or 10) + 2, 1.5) then
		return nil
	end
	local inventory = Services.InventoryService
	if not inventory or type(inventory.give) ~= "function" then
		return nil
	end
	local ok, result = pcall(inventory.give, player, entry.itemId, 1)
	if not ok then
		warn("[WorldProjectiles] InventoryService.give failed: " .. tostring(result))
		return nil
	end
	if (tonumber(result) or 0) <= 0 then
		inventoryFull(player, walking)
		return "full"
	end
	Sfx.playFor(player, "PickUp")
	removeEntry(entry)
	return "taken"
end

local function onTakeRequest(player: Player, worldId: any)
	if not Net.rateLimit(player, "TakeWorldItem", 10, 5) then
		return
	end
	if type(worldId) ~= "number" or worldId ~= worldId or not canInteract(player) then
		return
	end
	local entry = entries[worldId]
	if entry then
		take(player, entry, false)
	end
end

local function walkOverTick(now: number)
	local ids = LootCfg.AutoPickup
	if type(ids) ~= "table" or next(ids) == nil or next(grid) == nil then
		return
	end
	local phase = getPhase()
	if phase ~= "Active" and phase ~= "Countdown" then
		return
	end
	local reach = (tonumber(LootCfg.AutoPickupRange) or 3.5) + 0.5
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and isAlive(player) then
			local full: { [string]: boolean } = {}
			for _, entry in ipairs(gridQuery(root.Position, reach)) do
				if not entry.dead and entry.free and ids[entry.itemId] and not full[entry.itemId]
					and now - entry.freeAt >= WALK_DELAY
					and not (entry.noAutoPlayer == player and now < entry.noAutoUntil) then
					if take(player, entry, true) == "full" then
						full[entry.itemId] = true
					end
				end
			end
		end
	end
end

-- Body items come out when the body dies or its part goes, or by themselves after BodyFallOutTime.
local function bodyTick(now: number)
	if next(bodies) == nil then
		return
	end
	local due = {}
	for entry in pairs(bodies) do
		local humanoid = entry.hostHumanoid
		local host = entry.host
		if entry.dead or not host or not host:IsDescendantOf(workspace) or not humanoid or humanoid.Health <= 0
			or not humanoid:IsDescendantOf(workspace) or now >= (entry.fallOutAt or 0) then
			table.insert(due, entry)
		end
	end
	for _, entry in ipairs(due) do
		if entry.dead then
			bodies[entry] = nil
		else
			release(entry)
		end
	end
end

-- A few anchored items per tick: one whose part has gone (a crate replaced at the Feast) drops to the ground.
local function scanTick()
	local n = #order
	if n == 0 then
		return
	end
	for _ = 1, math.min(HOST_SCAN_PER_TICK, n) do
		if scanIndex > n or scanIndex < orderHead then
			scanIndex = orderHead
		end
		local entry = order[scanIndex]
		scanIndex += 1
		if entry and not entry.dead and entry.free and not entry.weld then
			local part = entry.anchorPart
			if part and not part:IsDescendantOf(workspace) then
				entry.anchorPart = nil
				unloose(entry)
				dropFrom(entry, entry.model:GetPivot())
			end
		end
	end
end

local function tick()
	local now = os.clock()
	if capRemoved > capLogged and now - lastCapLog >= 5 then
		lastCapLog = now
		capLogged = capRemoved
		print(string.format("[WorldProjectiles] over the cap of %d items: %d oldest removed this round",
			math.floor(tonumber(CombatCfg.WorldItemCap) or 400), capRemoved))
	end
	if count == 0 then
		return
	end
	bodyTick(now)
	walkOverTick(now)
	scanTick()
end

--------------------------------------------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------------------------------------------

function World.count(): number
	return count
end

-- Everything stuck in or welded to `model` (a body) comes out now, where it is, and drops to the ground below.
-- CombatService calls this as a training dummy breaks, before its parts tumble away. Returns how many came out.
function World.releaseFrom(model: Instance): number
	local list = {}
	for _, entry in pairs(entries) do
		local host = entry.host
		local humanoid = entry.hostHumanoid
		if not entry.dead and ((host and host:IsDescendantOf(model)) or (humanoid and humanoid.Parent == model)) then
			table.insert(list, entry)
		end
	end
	for _, entry in ipairs(list) do
		release(entry)
	end
	return #list
end

function World.get(worldId: number): Entry?
	return entries[worldId]
end

function World.stats(): { [string]: number }
	local cells, loose, inBodies = 0, 0, 0
	for _ in pairs(grid) do
		cells += 1
	end
	for _, entry in pairs(entries) do
		if entry.free then
			loose += 1
		end
	end
	for _ in pairs(bodies) do
		inBodies += 1
	end
	return { count = count, loose = loose, bodies = inBodies, falling = #falling, cells = cells, capRemoved = capRemoved }
end

function World.clear()
	for _, entry in pairs(entries) do
		entry.dead = true
		entry.model:Destroy()
	end
	table.clear(entries)
	table.clear(order)
	table.clear(grid)
	table.clear(bodies)
	table.clear(falling)
	for _, watch in pairs(hostWatch) do
		watch.conn:Disconnect()
	end
	table.clear(hostWatch)
	orderHead, scanIndex, count, capRemoved, capLogged = 1, 1, 0, 0, 0
	if fallConnection then
		fallConnection:Disconnect()
		fallConnection = nil
	end
	if folderRef and folderRef.Parent then
		folderRef:ClearAllChildren()
	end
end

function World.Init(registry)
	Services = registry
end

function World.Start()
	getFolder()
	Net.event("TakeWorldItem").OnServerEvent:Connect(onTakeRequest)
	local loot = Services.LootService
	if loot and type(loot.cleared) == "table" and type(loot.cleared.Connect) == "function" then
		loot.cleared:Connect(World.clear)
	end
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState:GetAttribute("Phase") == "Lobby" then
			World.clear()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastFullToast[player] = nil
	end)
	task.spawn(function()
		local warned = false
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok and not warned then
				warned = true
				warn("[WorldProjectiles] tick failed: " .. tostring(err))
			end
		end
	end)
end

return World
