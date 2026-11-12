--[[
	ViewmodelController.Shade - lights the first-person avatar arms like the world around them (Config.Viewmodel.Shade).

	The engine lights the arms where they float, a few studs above the ground in the open air. In daylight that already
	looks right (the sun gives them a lit side and a shadow side). But at dusk and at night the light is mostly the flat
	twilight / moonlit fill (Lighting.OutdoorAmbient, DayCycle), and under the forest canopy the arms still get that
	fill in full while the ground around is dark: they read as flat, evenly lit cut-outs, brighter than the scene. And
	black clothing has no albedo to light at all: a black sleeve is a black hole whatever the light.

	A few times a second Shade looks at the light around the eye (how much open sky there is above, from a few rays;
	whether the sun or the moon is up and in view; the hour's DayCycle look) and sets three things on the Rig:
	  * exposure (Rig:setExposure): the whole viewmodel darkened toward the scene's level: at dusk, at night, and the
	    more so the more the sky is covered (forest, cabin);
	  * a sky key light (Rig.key, placed by update's return value as frame.key): a soft spot light above the arms,
	    tilted toward the sun's or moon's side when it is up, where the world gives no direct light (shade, dusk, night),
	    so the tops of the arms catch the sky and their sides and undersides fall off. Its range is short (about the
	    arms' reach) and it fades out against walls (the wall tuck), so it doesn't light the world;
	  * the shade layer (Rig:setShade): a pale, mostly transparent copy of the arms over them, lit by the same light, so
	    dark and black clothing keeps the shape of the light (a dark, softly lit fabric instead of a black hole).

	Shade.new(rig) -> shade
	shade:update(dt, camCF, tuck) -> CFrame?   every frame while the viewmodel is shown: the key light's frame (world)
	shade:reset()                                when the viewmodel is shown again (no fade from stale values)
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DayCycle = require(Shared:WaitForChild("DayCycle"))

local Shade = {}
Shade.__index = Shade
Shade.Options = (Config.Viewmodel and Config.Viewmodel.Shade) or {}

local function opt(name: string, default: any): any
	local value = Shade.Options[name]
	if value == nil then
		return default
	end
	return value
end

local SAMPLE_EVERY = 0.2 -- seconds between looks at the light around the eye
local SKY_RAY = 90 -- studs: further than this counts as open sky
local SUN_RAY = 400
-- the sky above: straight up and a ring of six at 55 degrees elevation (the zenith counts double)
local SKY_DIRS: { Vector3 } = { Vector3.yAxis }
for i = 0, 5 do
	local a = i / 6 * math.pi * 2
	local e = math.rad(55)
	table.insert(SKY_DIRS, Vector3.new(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e)))
end
local KEY_AT = Vector3.new(0, -0.62, -1.15) -- camera space: about the middle of where the hands and forearms are seen

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
params.RespectCanCollide = false

function Shade.new(rig: any)
	local self = setmetatable({}, Shade)
	self.rig = rig
	self.look = {}
	self.sampleAt = 0
	-- sampled (targets) and smoothed (current) state
	self.skyOpen, self.sunLit, self.night, self.twilight, self.sunBlocked = 1, 1, 0, 0, 0
	self.cur = { exposure = 1, key = 0 }
	self.fresh = true
	self.lightDir = Vector3.yAxis
	self.keyColor = Color3.new(1, 1, 1)
	return self
end

function Shade:reset()
	self.sampleAt = 0
	self.fresh = true
end

-- Looks at the light around the eye: open sky, the sun or moon, the hour.
function Shade:_sample(camCF: CFrame)
	local list: { Instance } = { workspace.CurrentCamera }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(list, character)
	end
	local effects = workspace:FindFirstChild("ClientProjectiles")
	if effects then
		table.insert(list, effects)
	end
	params.FilterDescendantsInstances = list
	local origin = camCF.Position
	local open, total = 0, 0
	for i, dir in ipairs(SKY_DIRS) do
		local w = if i == 1 then 2 else 1
		total += w
		if not workspace:Raycast(origin, dir * SKY_RAY, params) then
			open += w
		end
	end
	self.skyOpen = open / total
	local look = DayCycle.lookAt(Lighting.ClockTime, self.look)
	self.night = math.clamp(look.Night or 0, 0, 1)
	self.twilight = math.clamp(look.Twilight or 0, 0, 1)
	-- the direct light: the sun by day, the moon by night, when it is up and nothing is between it and the eye
	local sun = Lighting:GetSunDirection()
	local dir = if sun.Y > 0.03 then sun else Lighting:GetMoonDirection()
	local lit = 0
	if dir.Y > 0.03 then
		self.lightDir = dir
		if not workspace:Raycast(origin, dir * SUN_RAY, params) then
			lit = 1
		end
	else
		self.lightDir = Vector3.yAxis
	end
	-- how much the engine's own direct light gives the arms their form (the moon's is weak; none in the twilight)
	local strength = if sun.Y > 0.03 then 1 else 0.35
	self.sunLit = lit * strength * (1 - self.twilight)
	-- the sun is up but something stands between it and the eye (canopy, a roof): the arms are in its shadow
	self.sunBlocked = if sun.Y > 0.03 and lit == 0 then 1 - self.twilight else 0
	local ambient = Lighting.OutdoorAmbient
	local m = math.max(ambient.R, ambient.G, ambient.B, 1e-3)
	self.keyColor = Color3.new(1, 1, 1):Lerp(Color3.new(ambient.R / m, ambient.G / m, ambient.B / m), opt("KeyTint", 0.55))
end

function Shade:update(dt: number, camCF: CFrame, tuck: number?): CFrame?
	local now = os.clock()
	if now >= self.sampleAt then
		self.sampleAt = now + SAMPLE_EVERY
		self:_sample(camCF)
	end
	-- exposure: dusk and night bring the arms down toward the scene's level, cover (canopy, roofs) more so at night
	local dusk = math.max(self.night * opt("NightDarken", 0.45), self.twilight * opt("DuskDarken", 0.38))
	local dark = math.max(self.night, self.twilight)
	local shadeDarken = opt("ShadeDarken", 0.15)
	local coverDarken = (1 - self.skyOpen) * (shadeDarken + (opt("NightShadeDarken", 0.5) - shadeDarken) * dark)
	local exposure = math.clamp((1 - dusk) * (1 - coverDarken) * (1 - opt("SunShadeDarken", 0.3) * (self.sunBlocked or 0)),
		opt("MinExposure", 0.18), 1)
	-- the sky key: strongest where the world gives the arms no direct light, and stronger still in the twilight, whose
	-- flat fill is bright (KeyDuskBoost)
	local key = opt("KeyBrightness", 1.5) * (1 - self.sunLit) * (0.55 + 0.45 * self.skyOpen) * (1 - math.clamp(tuck or 0, 0, 1))
		* (1 + opt("KeyDuskBoost", 1.2) * self.twilight)
	local cur = self.cur
	local a = if self.fresh then 1 else 1 - math.exp(-dt * opt("Adapt", 3))
	self.fresh = false
	cur.exposure += (exposure - cur.exposure) * a
	cur.key += (key - cur.key) * a
	local rig = self.rig
	rig:setExposure(cur.exposure)
	rig:setShade(opt("ShadeColor", Color3.fromRGB(235, 235, 240)), opt("ShadeTransparency", 0.72), opt("HandShadeTransparency", 0.86))
	local light = rig.key
	if cur.key < 0.02 then
		if light.Enabled then
			light.Enabled = false
		end
		return nil
	end
	if not light.Enabled then
		light.Enabled = true
	end
	light.Brightness = cur.key
	light.Color = self.keyColor
	light.Range = opt("KeyRange", 4.5)
	light.Angle = opt("KeyAngle", 120)
	-- from above the arms, leaning toward the sun's or moon's side (never from below the horizon)
	local at = camCF * KEY_AT
	local d = self.lightDir
	local flatDir = Vector3.new(d.X, 0, d.Z)
	local from = Vector3.yAxis
	if flatDir.Magnitude > 1e-3 then
		from = (Vector3.yAxis + flatDir.Unit * opt("KeyLean", 0.35)).Unit
	end
	return CFrame.lookAt(at + from * opt("KeyHeight", 2), at)
end

return Shade
