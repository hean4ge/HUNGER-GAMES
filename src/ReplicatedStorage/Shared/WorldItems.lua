--[[
	WorldItems - shared rules for spent projectiles left in the world: arrows, throwing knives and thrown spears.
	The server's registry (ServerScriptService.Server.Services.ProjectileService.WorldProjectiles) places them and hands
	them out; ProjectileController lands its own flying copy on the same pose so the hand-over to the server's model is
	seamless; WorldItemController offers the Take prompt. Shared so client and server always agree.

	Tags and attributes (on the item's Model, in workspace.Arena.Loot.Projectiles)
	  WorldItems.TAG = "WorldProjectile"        every spent projectile in the world, whatever its state
	  WorldItems.LOOSE_TAG = "LooseProjectile"  one that can be taken now: embedded or lying, settled, not in a body
	  ItemId, WorldId (registry id, sent with TakeWorldItem), Shot (the ProjectileService id it flew as, 0 = none),
	  Host / HostPart (UserId, 0 = a training dummy, and body part name, only while it is stuck in a body)
	Poses: an item's pivot is its Handle (= Grip) frame; LookVector points to the business end (ItemModels).
	  WorldItems.tipDistance(itemId) -> number   Grip to Tip from the template (arrow 3.0, throwing knife 0.66, spear 4.4)
	  WorldItems.depth(itemId, material, speed, incidence, body?) -> number   how far the tip sinks past the surface.
	      Arrows: 0.7-1.4 into soil, 0.2-0.55 into wood, 0.85-1.05 into canvas, 0.6-1.1 into a body, a 0.08 wedge into
	      stone and metal. Faster and more head-on (incidence 1) goes deeper; never more than half the item.
	      Throwing knives and spears glance off stone and metal (0, see glances).
	  WorldItems.glances(itemId, material) -> boolean   a blade that meets stone or metal falls instead of sticking
	  WorldItems.embedPivot(itemId, tip, direction) -> CFrame   tip at `tip`, pointing along `direction`, rolled level
	      (the same pose on every machine for the same inputs)
	  WorldItems.restPivot(itemId, point, normal, heading) -> CFrame   lying on its side on a surface, centred on `point`
	  WorldItems.bedPivot(itemId, point, normal, heading) -> CFrame    an arrow on a lake bed: tip in, nock raised ~28 deg
	  WorldItems.fallPose(from, to, alpha, sink?) -> CFrame   the fall (or sink) between two poses; both sides use it
	  WorldItems.grabPoint(itemId, pivot) -> Vector3   where a hand closes on it: the shaft just ahead of the nock, a
	      knife's or spear's grip
	Reach (Config.Loot.ItemPromptDistance / PickupRange / AutoPickupRange, Config.Combat.PickupReachAbove)
	  WorldItems.inReach(root, grab, range, slack?) -> boolean   within `range` studs of the root and no higher than a
	      raised hand (PickupReachAbove above the root, ~7 studs above the feet; + slack)
	  WorldItems.walkOver(root, grab) -> boolean   at your feet: within AutoPickupRange on the flat, from 4.5 below to
	      0.5 above the root
	  WorldItems.folder() -> Instance?   workspace.Arena.Loot.Projectiles, once the server has made it
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("Config"))

local WorldItems = {}

WorldItems.TAG = "WorldProjectile"
WorldItems.LOOSE_TAG = "LooseProjectile"
WorldItems.FOLDER = "Projectiles"

local CombatCfg = Config.Combat
local LootCfg = Config.Loot

-- Matches the templates' Tip attachments (read from them when they are there).
local FALLBACK_TIP: { [string]: number } = { arrow = 3, throwing_knife = 0.66, spear = 4.4 }
-- The item's extent in its own frame: X across (the cock feather / blade flat), Z along (tip at -tipDistance).
local FALLBACK_EXTENT: { [string]: { x0: number, z0: number, z1: number } } = {
	arrow = { x0 = -0.09, z0 = -3.0, z1 = 0.05 },
	throwing_knife = { x0 = -0.03, z0 = -0.66, z1 = 0.36 },
	spear = { x0 = -0.11, z0 = -4.4, z1 = 2.62 },
}

-- Material classes (Enum.Material names) and how much more or less the class gives (x the class depth).
local CLASS: { [string]: { string | number } } = {
	Grass = { "soil", 1 }, LeafyGrass = { "soil", 1 }, Ground = { "soil", 1 }, Mud = { "soil", 1.15 },
	Sand = { "soil", 0.9 }, Snow = { "soil", 1.1 },
	Wood = { "wood", 1 }, WoodPlanks = { "wood", 1 }, Cardboard = { "wood", 1.3 },
	Fabric = { "cloth", 1 }, Leather = { "cloth", 0.8 }, Carpet = { "cloth", 1 }, Rubber = { "cloth", 0.6 },
	Salt = { "gravel", 1 }, Pebble = { "gravel", 1 },
	Rock = { "hard", 1 }, Slate = { "hard", 1 }, Basalt = { "hard", 1 }, Granite = { "hard", 1 }, Marble = { "hard", 1 },
	Limestone = { "hard", 1 }, Sandstone = { "hard", 1 }, Concrete = { "hard", 1 }, Brick = { "hard", 1 },
	Cobblestone = { "hard", 1 }, Pavement = { "hard", 1 }, Asphalt = { "hard", 1 }, CrackedLava = { "hard", 1 },
	Glacier = { "hard", 1 }, Ice = { "hard", 1 }, Metal = { "hard", 1 }, CorrodedMetal = { "hard", 1 },
	DiamondPlate = { "hard", 1 }, Foil = { "hard", 1 }, Glass = { "hard", 1 },
}

-- { base, extra at full speed } studs of the tip past the surface, per material class
type Profile = { [string]: any }
local PROFILES: { [string]: Profile } = {
	arrow = {
		soil = { 0.7, 0.7 }, wood = { 0.22, 0.33 }, cloth = { 0.85, 0.2 }, gravel = { 0.25, 0.1 }, hard = { 0.08, 0 },
		other = { 0.25, 0.15 }, body = { 0.6, 0.5 }, glances = false,
	},
	throwing_knife = {
		soil = { 0.3, 0.1 }, wood = { 0.2, 0.08 }, cloth = { 0.3, 0.05 }, gravel = { 0.08, 0 }, hard = { 0, 0 },
		other = { 0.12, 0.05 }, body = { 0.35, 0.1 }, glances = true,
	},
	spear = {
		soil = { 0.6, 0.6 }, wood = { 0.3, 0.15 }, cloth = { 0.8, 0.2 }, gravel = { 0.2, 0.1 }, hard = { 0, 0 },
		other = { 0.25, 0.1 }, body = { 0.85, 0.35 }, glances = true,
	},
}

local tipCache: { [string]: number } = {}
local extentCache: { [string]: { x0: number, z0: number, z1: number } } = {}

local function template(itemId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	local model = items and items:FindFirstChild(itemId)
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

local function upFor(direction: Vector3): Vector3
	return if math.abs(direction.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
end

-- `normal` leaned back toward vertical so it is at most maxTilt (radians) from straight up
local function clampUp(normal: Vector3, maxTilt: number): Vector3
	local n = if normal.Magnitude > 1e-6 then normal.Unit else Vector3.yAxis
	if math.acos(math.clamp(n.Y, -1, 1)) <= maxTilt then
		return n
	end
	local horizontal = Vector3.new(n.X, 0, n.Z)
	if horizontal.Magnitude < 1e-4 then
		return Vector3.yAxis
	end
	return (Vector3.yAxis * math.cos(maxTilt) + horizontal.Unit * math.sin(maxTilt)).Unit
end

-- `heading` flattened onto the plane of `up` (a sideways direction when it points along `up`)
local function along(heading: Vector3, up: Vector3): Vector3
	local flat = heading - up * heading:Dot(up)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.xAxis:Cross(up)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.zAxis
		end
	end
	return flat.Unit
end

function WorldItems.tipDistance(itemId: string): number
	local cached = tipCache[itemId]
	if cached then
		return cached
	end
	local value = FALLBACK_TIP[itemId] or 1
	local model = template(itemId)
	local handle = model and model.PrimaryPart
	local tip = handle and handle:FindFirstChild("Tip")
	if tip and tip:IsA("Attachment") then
		local grip = (handle :: BasePart):FindFirstChild("Grip")
		local from = if grip and grip:IsA("Attachment") then grip.Position else Vector3.zero
		local d = (tip.Position - from).Magnitude
		if d > 0.05 then
			value = d
		end
		tipCache[itemId] = value -- only remembered once the template has been read
	end
	return value
end

local function extent(itemId: string): { x0: number, z0: number, z1: number }
	local cached = extentCache[itemId]
	if cached then
		return cached
	end
	local fallback = FALLBACK_EXTENT[itemId] or { x0 = -0.1, z0 = -WorldItems.tipDistance(itemId), z1 = 0.1 }
	local model = template(itemId)
	if not model then
		return fallback
	end
	-- the template sits with its Grip at the origin; measure its visible parts in that frame
	local origin = (model.PrimaryPart :: BasePart).CFrame
	local x0, z0, z1 = math.huge, math.huge, -math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf = origin:ToObjectSpace(d.CFrame)
			local half = d.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						x0 = math.min(x0, p.X)
						z0 = math.min(z0, p.Z)
						z1 = math.max(z1, p.Z)
					end
				end
			end
		end
	end
	local value = if x0 < math.huge then { x0 = x0, z0 = z0, z1 = z1 } else fallback
	extentCache[itemId] = value
	return value
end

function WorldItems.glances(itemId: string, material: Enum.Material?): boolean
	local profile = PROFILES[itemId]
	local class = material and CLASS[material.Name]
	return profile ~= nil and profile.glances == true and class ~= nil and class[1] == "hard"
end

function WorldItems.depth(itemId: string, material: Enum.Material?, speed: number, incidence: number, body: boolean?): number
	local profile = PROFILES[itemId] or PROFILES.arrow
	local s = math.clamp(((tonumber(speed) or 0) - 60) / 180, 0, 1)
	local head = math.clamp(tonumber(incidence) or 1, 0, 1)
	local depth: number
	if body then
		local b = profile.body
		depth = (b[1] + b[2] * s) * (0.75 + 0.25 * head)
	else
		local class = material and CLASS[material.Name]
		local name = if class then class[1] :: string else "other"
		local scale = if class then class[2] :: number else 1
		if name == "hard" and profile.glances then
			return 0
		end
		local c = profile[name] or profile.other
		depth = (c[1] + c[2] * s) * scale
		if name ~= "hard" then
			depth *= 0.55 + 0.45 * head -- a glancing hit doesn't go in as far
		end
	end
	return math.min(depth, WorldItems.tipDistance(itemId) * 0.5)
end

function WorldItems.embedPivot(itemId: string, tip: Vector3, direction: Vector3): CFrame
	local d = if direction.Magnitude > 1e-4 then direction.Unit else Vector3.new(0, -1, 0)
	return CFrame.lookAt(tip, tip + d, upFor(d)) * CFrame.new(0, 0, WorldItems.tipDistance(itemId))
end

function WorldItems.restPivot(itemId: string, point: Vector3, normal: Vector3, heading: Vector3): CFrame
	local up = clampUp(normal, math.rad(30))
	local forward = along(heading, up)
	local e = extent(itemId)
	-- on its side (ItemModels.restRotation: the item's X, its feather or blade flat, faces up), lowest point on the
	-- surface, centred lengthwise on `point`
	local rest = CFrame.lookAt(point, point + forward, up) * CFrame.Angles(0, 0, math.rad(90))
	return rest * CFrame.new(-e.x0 + 0.02, 0, -(e.z0 + e.z1) / 2)
end

function WorldItems.bedPivot(itemId: string, point: Vector3, normal: Vector3, heading: Vector3): CFrame
	local up = clampUp(normal, math.rad(35))
	local forward = along(heading, up)
	local angle = math.rad(28)
	local into = (forward * math.cos(angle) - up * math.sin(angle)).Unit
	return WorldItems.embedPivot(itemId, point + into * 0.22, into)
end

function WorldItems.fallPose(from: CFrame, to: CFrame, alpha: number, sink: boolean?): CFrame
	local a = math.clamp(alpha, 0, 1)
	local e = if sink then 1 - (1 - a) * (1 - a) else a * a -- water slows it; a fall speeds up
	return from:Lerp(to, e)
end

function WorldItems.grabPoint(itemId: string, pivot: CFrame): Vector3
	if itemId == "arrow" then
		return pivot.Position + pivot.LookVector * 0.8
	end
	return pivot.Position
end

function WorldItems.reachAbove(): number
	return tonumber(CombatCfg.PickupReachAbove) or 4.3
end

function WorldItems.inReach(root: Vector3, grab: Vector3, range: number, slack: number?): boolean
	local d = grab - root
	return d.Magnitude <= range and d.Y <= WorldItems.reachAbove() + (slack or 0)
end

function WorldItems.walkOver(root: Vector3, grab: Vector3): boolean
	local d = grab - root
	if d.Y > 0.5 or d.Y < -4.5 then
		return false
	end
	return Vector3.new(d.X, 0, d.Z).Magnitude <= (tonumber(LootCfg.AutoPickupRange) or 3.5)
end

function WorldItems.folder(): Instance?
	local arena = workspace:FindFirstChild("Arena")
	local loot = arena and arena:FindFirstChild("Loot")
	return loot and loot:FindFirstChild(WorldItems.FOLDER)
end

return WorldItems
