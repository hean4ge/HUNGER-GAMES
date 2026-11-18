--[[
	WildlifeController - draws and animates the squirrels the server tells this client about (WildlifeService).
	Numbers: Shared.WildlifeConfig.Squirrel.Draw. Looks: Shared.CreatureLooks (the one Mesh table swaps in a Blender
	model later; nothing here changes).

	The server sends, only when a squirrel changes what it does, one flat array of 11 numbers a squirrel:
	  id, state, x0, y0, z0, x1, y1, z1, t0 (server time), duration, yaw
	state: 0 forget, 1 Idle, 2 Hop, 3 Sit, 4 Alert, 5 Flee, 6 Climb, 7 Perch, 8 Descend, 9 Hit (-9: hit on a trunk)
	This client plays each move itself from those numbers: no per-step traffic.

	Cost: models are pooled and only the nearest Draw[tier].count within Draw[tier].distance are drawn (picked twice
	a second); only those within .animate get the small motions (tail flick, head turns) every frame, the others are
	placed when they move. Everything is a local, anchored, non-colliding Model under workspace.ClientWildlife, so
	the map's streaming never touches it. DetailController's tier (LocalPlayer attribute DetailTier) sets the caps.
	A hit squirrel falls still (from a trunk it drops to the ground) and fades: no blood, no cry.

	Studio: LocalPlayer attribute WildlifeDrawn = "<drawn>/<known> <ms per frame>" every 2 s.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureLooks = require(Shared:WaitForChild("CreatureLooks"))
local WildlifeConfig = require(Shared:WaitForChild("WildlifeConfig"))

local SQ = WildlifeConfig.Squirrel
local player = Players.LocalPlayer
local IS_STUDIO = RunService:IsStudio()

local WildlifeController = {}

local S_FORGET, S_IDLE, S_HOP, S_SIT, S_ALERT, S_FLEE, S_CLIMB, S_PERCH, S_DESCEND, S_HIT = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9

local FADE_IN = 0.35
local FADE_OUT = 0.35
local HIT_DROP = 0.42 -- seconds a squirrel hit on a trunk takes to fall to the ground
local HIT_LIE = 0.55 -- then it lies still this long...
local HIT_FADE = 0.6 -- ...and fades over this long (the Squirrel item is on the ground by then)

type Rig = any
type Critter = {
	id: number,
	state: number,
	p0: Vector3,
	p1: Vector3,
	t0: number,
	dur: number,
	yaw: number,
	high: boolean, -- (Hit) it was on a trunk
	groundY: number?, -- (Hit from a trunk) where it lands
	rig: Rig?,
	shownAt: number, -- os.clock() it was given a model (fade in)
	goneAt: number?, -- os.clock() it was forgotten (fade out)
	phase: number, -- its own offset for the small motions
	dist: number,
	placed: boolean, -- far ones: placed once per move
}

local critters: { [number]: Critter } = {}
local knownCount = 0
local pool: { Rig } = {}
local drawn: { Critter } = {}
local folder: Folder? = nil
local tier = { count = 14, distance = 135, animate = 50 }
local frameMs = 0

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function readTier()
	local name = player:GetAttribute("DetailTier")
	local entry = SQ.Draw[if type(name) == "string" then name else "Medium"] or SQ.Draw.Medium
	tier = entry
end

local function ensureFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local created = Instance.new("Folder")
	created.Name = "ClientWildlife"
	created.Parent = workspace
	folder = created
	return created
end

local function takeRig(): Rig
	local rig = table.remove(pool)
	if not rig then
		rig = CreatureLooks.newSquirrel()
	end
	rig.model.Parent = ensureFolder()
	return rig
end

local function releaseRig(c: Critter)
	local rig = c.rig
	if not rig then
		return
	end
	c.rig = nil
	rig.model.Parent = nil
	CreatureLooks.fade(rig, 0)
	if #pool < 32 then
		table.insert(pool, rig)
	else
		rig.model:Destroy()
	end
end

local function remove(c: Critter)
	releaseRig(c)
	if critters[c.id] == c then
		critters[c.id] = nil
		knownCount -= 1
	end
end

-- where it is now on its move
local function positionAt(c: Critter, t: number): (Vector3, number)
	if c.dur <= 1e-3 then
		return c.p1, 1
	end
	local a = math.clamp((t - c.t0) / c.dur, 0, 1)
	return c.p0:Lerp(c.p1, a), a
end

local function groundBelow(p: Vector3): number?
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local result = workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), groundParams)
	return if result then result.Position.Y else nil
end

--------------------------------------------------------------------------------------------------------------------
-- The server's messages
--------------------------------------------------------------------------------------------------------------------

local function onState(data: any)
	if type(data) ~= "table" then
		return
	end
	local n = #data
	local i = 1
	while i + 10 <= n do
		local id = data[i]
		local state = data[i + 1]
		if type(id) == "number" and type(state) == "number" then
			local c = critters[id]
			if state == S_FORGET then
				if c and not c.goneAt and c.state ~= S_HIT then
					c.goneAt = os.clock()
				end
			else
				if not c then
					c = {
						id = id,
						state = state,
						p0 = Vector3.zero,
						p1 = Vector3.zero,
						t0 = 0,
						dur = 0,
						yaw = 0,
						high = false,
						rig = nil,
						shownAt = 0,
						phase = (id * 0.618) % 1 * 10,
						dist = math.huge,
						placed = false,
					}
					critters[id] = c
					knownCount += 1
				end
				c.goneAt = nil
				c.high = state < 0
				c.state = math.abs(state)
				c.p0 = Vector3.new(data[i + 2], data[i + 3], data[i + 4])
				c.p1 = Vector3.new(data[i + 5], data[i + 6], data[i + 7])
				c.t0 = data[i + 8]
				c.dur = math.max(0, data[i + 9])
				c.yaw = data[i + 10]
				c.placed = false
				c.groundY = nil
				if c.state == S_HIT then
					c.goneAt = os.clock() -- the fall-and-fade clock
					if c.high then
						c.groundY = groundBelow(c.p1)
					end
				end
			end
		end
		i += 11
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------------------------------------------

local UP = Vector3.yAxis

-- On the ground: facing yaw (the model's nose is -Z).
local function groundFrame(p: Vector3, yaw: number): CFrame
	return CFrame.new(p) * CFrame.Angles(0, yaw + math.pi, 0)
end

-- On a trunk: belly to the bark (yaw = the way to the trunk's axis), nose up (or down when descending).
local function trunkFrame(p: Vector3, yaw: number, noseDown: boolean): CFrame
	local toAxis = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local up = -toAxis -- the model's +Y points away from the bark
	local back = if noseDown then UP else -UP -- the model's +Z (the nose is -Z)
	local right = up:Cross(back)
	return CFrame.fromMatrix(p, right, up, back)
end

local function poseFor(c: Critter, t: number, clock: number, a: number): (string, number?)
	local s = c.state
	if s == S_IDLE then
		-- nibbling and looking about by turns
		local cycle = (clock * 0.35 + c.phase) % 2
		return (if cycle < 1.2 then "Nibble" else "Stand"), nil
	elseif s == S_HOP then
		return "Hop", math.sin(a * math.pi)
	elseif s == S_SIT then
		return "Sit", nil
	elseif s == S_ALERT then
		return "Alert", nil
	elseif s == S_FLEE then
		return "Run", math.abs(math.sin(clock * 15 + c.phase))
	elseif s == S_CLIMB or s == S_DESCEND then
		return "Climb", nil
	elseif s == S_PERCH then
		return "Perch", nil
	elseif s == S_HIT then
		return "Limp", nil
	end
	return "Stand", nil
end

local function frameFor(c: Critter, t: number, clock: number): (CFrame, number)
	local p, a = positionAt(c, t)
	local s = c.state
	if s == S_HIT then
		local since = clock - (c.goneAt or clock)
		if c.high then
			-- it drops off the trunk, turning onto its side, and lands still
			local drop = math.clamp(since / HIT_DROP, 0, 1)
			local gy = c.groundY or (p.Y - 0.5)
			local out = Vector3.new(-math.sin(c.yaw), 0, -math.cos(c.yaw))
			local fall = drop * drop
			local at = Vector3.new(p.X, p.Y + (gy - p.Y) * fall, p.Z) + out * (1.2 * drop)
			return groundFrame(at, c.yaw) * CFrame.Angles(0, 0, math.rad(90 * drop)), a
		end
		local tip = math.clamp(since / 0.25, 0, 1)
		return groundFrame(p, c.yaw) * CFrame.Angles(0, 0, math.rad(90 * tip)), a
	elseif s == S_CLIMB or s == S_PERCH then
		return trunkFrame(p, c.yaw, false), a
	elseif s == S_DESCEND then
		return trunkFrame(p, c.yaw, true), a
	elseif s == S_HOP then
		-- a little arc
		return groundFrame(p + Vector3.new(0, math.sin(a * math.pi) * 0.45, 0), c.yaw), a
	elseif s == S_FLEE then
		local bound = math.abs(math.sin(clock * 15 + c.phase)) * 0.22
		return groundFrame(p + Vector3.new(0, bound, 0), c.yaw), a
	end
	return groundFrame(p, c.yaw), a
end

local function fadeOf(c: Critter, clock: number): number
	local alpha = 1 - math.clamp((clock - c.shownAt) / FADE_IN, 0, 1)
	if c.goneAt then
		if c.state == S_HIT then
			local since = clock - c.goneAt - (if c.high then HIT_DROP else 0) - HIT_LIE
			alpha = math.max(alpha, math.clamp(since / HIT_FADE, 0, 1))
		else
			alpha = math.max(alpha, math.clamp((clock - c.goneAt) / FADE_OUT, 0, 1))
		end
	end
	return alpha
end

local function finished(c: Critter, clock: number): boolean
	if not c.goneAt then
		return false
	end
	if c.state == S_HIT then
		return clock - c.goneAt > (if c.high then HIT_DROP else 0) + HIT_LIE + HIT_FADE + 0.05
	end
	return clock - c.goneAt > FADE_OUT + 0.05
end

-- Twice a second: which ones get a model.
local function choose(focus: Vector3)
	local list: { Critter } = {}
	local t = serverNow()
	local clock = os.clock()
	local far2 = tier.distance * tier.distance
	for _, c in pairs(critters) do
		if finished(c, clock) then
			remove(c)
		else
			local p = positionAt(c, t)
			local d = p - focus
			c.dist = d:Dot(d)
			if c.dist <= far2 then
				table.insert(list, c)
			elseif c.rig then
				releaseRig(c)
			end
		end
	end
	if #list > tier.count then
		table.sort(list, function(a, b)
			return a.dist < b.dist
		end)
	end
	for index, c in ipairs(list) do
		if index > tier.count then
			if c.rig then
				releaseRig(c)
			end
		end
	end
	table.clear(drawn)
	for index = 1, math.min(#list, tier.count) do
		local c = list[index]
		if not c.rig then
			c.rig = takeRig()
			c.shownAt = os.clock()
			c.placed = false
		end
		table.insert(drawn, c)
	end
end

local function render()
	local started = os.clock()
	local t = serverNow()
	local clock = started
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local animate2 = tier.animate * tier.animate
	for _, c in ipairs(drawn) do
		local rig = c.rig
		if rig then
			local alpha = fadeOf(c, clock)
			local d = c.p1 - eye
			local near = d:Dot(d) <= animate2
			local moving = c.dur > 0 and t < c.t0 + c.dur + 0.05
			local fading = alpha > 0 or c.state == S_HIT
			if near or moving or fading or not c.placed then
				local cf, a = frameFor(c, t, clock)
				local pose, lift = poseFor(c, t, clock, a)
				CreatureLooks.poseSquirrel(rig, pose, if near then clock + c.phase else c.phase, lift)
				rig.model:PivotTo(cf)
				c.placed = true
			end
			CreatureLooks.fade(rig, alpha)
		end
	end
	frameMs = frameMs * 0.95 + (os.clock() - started) * 1000 * 0.05
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function WildlifeController.Init(_controllers)
	readTier()
	player:GetAttributeChangedSignal("DetailTier"):Connect(readTier)
end

function WildlifeController.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("WildlifeState", 60)
	if not (remote and remote:IsA("RemoteEvent")) then
		warn("[Wildlife] no WildlifeState remote: squirrels are not drawn")
		return
	end
	remote.OnClientEvent:Connect(onState)
	RunService.RenderStepped:Connect(render)
	local sinceStats = 0
	while true do
		local dt = task.wait(0.5)
		local camera = workspace.CurrentCamera
		local focus = if camera then camera.Focus.Position else Vector3.zero
		choose(focus)
		if IS_STUDIO then
			sinceStats += dt
			if sinceStats >= 2 then
				sinceStats = 0
				player:SetAttribute("WildlifeDrawn", string.format("%d/%d %.3fms", #drawn, knownCount, frameMs))
			end
		end
	end
end

return WildlifeController
