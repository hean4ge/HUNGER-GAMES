--[[
	LightingRig (ServerStorage.WorldGen) - the lighting baseline, owned by the day/night system.
	The look itself lives in ReplicatedStorage.Shared.DayCycle (Looks keyframes by hour + Knobs) so that edit time,
	the lobby and every hour of a round come from one table: at runtime ArenaController (client) sets ClockTime and
	applies DayCycle.lookAt(hour) every frame; at edit time this rig writes the look for Config.Round.LobbyClockTime.
	Tuned for Lighting.LightingStyle = Realistic with PrioritizeLightingQuality on (set in the Edit datamodel or the
	Properties panel; game scripts can't change them at runtime). It still reads on Soft and at low quality levels,
	where shadows switch off: the sky light (EnvironmentDiffuseScale) and the Atmosphere carry the shape then.
	It also owns the look's extra tracks: DepthOfField far blur, Terrain.Clouds (Cover / Density / Color) and the base
	Workspace.GlobalWind (the client adds gusts).

	LightingRig.apply(opts?) -> string report
	  opts.clock      hour to write (default Config.Round.LobbyClockTime)
	  opts.setClock   also set Lighting.ClockTime (default true in Edit mode)
	Creates any missing Sky / Atmosphere / Bloom / SunRays / DepthOfField / ColorCorrection "ArenaGrade", applies
	LightingRig.Static (hour-independent knobs) and then the DayCycle look. Safe to re-run any time.
	TerrainGen.applyLighting() delegates here.
	LightingRig.preview(hour) -> string   edit-time preview of any hour (run apply() afterwards to restore the lobby look)

	KNOBS: LightingRig.Static below; per-hour values in Shared.DayCycle.Looks; global multipliers in DayCycle.Knobs.
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LightingRig = {}

-- Hour-independent settings.
LightingRig.Static = {
	Lighting = {
		GeographicLatitude = 44, -- low-angle sun all day; the sun still rises at 06:00 and sets at 18:00
		GlobalShadows = true,
		FogEnd = 100000, -- Atmosphere does the haze
		FogStart = 0,
	},
	Sky = {
		CelestialBodiesShown = true,
		SunAngularSize = 12, -- a smaller, realistic sun disc (default 21)
		MoonAngularSize = 5, -- a cinematic moon: larger than the real one (~0.5 deg), far smaller than the engine's 11
		StarCount = 4500,
	},
	Bloom = { Enabled = true },
	SunRays = { Enabled = true },
	DepthOfField = {
		Enabled = true,
		FarIntensity = 0.07,
		FocusDistance = 200,
		InFocusRadius = 420, -- only blurs beyond ~620 studs (the far mountains); never the Roll Call display
		NearIntensity = 0,
	},
	ArenaGrade = { Enabled = true },
}

local function ensure(className: string, name: string): Instance
	local found = Lighting:FindFirstChild(name)
	if found and found:IsA(className) then
		return found
	end
	local byClass = nil
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA(className) and (className ~= "ColorCorrectionEffect" or child.Name == name) then
			byClass = child
			break
		end
	end
	if byClass then
		byClass.Name = name
		return byClass
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = Lighting
	return made
end

local function setProps(instance: Instance, props: { [string]: any }, report: { string })
	for prop, value in pairs(props) do
		local ok, err = pcall(function()
			(instance :: any)[prop] = value
		end)
		if not ok then
			table.insert(report, string.format("couldn't set %s.%s: %s", instance.Name, prop, tostring(err)))
		end
	end
end

local function freshDayCycle()
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local module = Shared:WaitForChild("DayCycle")
	if RunService:IsEdit() then
		-- Studio caches required modules during an edit session: require a copy to pick up edits
		local copy = module:Clone()
		local ok, result = pcall(require, copy)
		copy:Destroy()
		if ok then
			return result
		end
	end
	return require(module)
end

function LightingRig.apply(opts: { [string]: any }?): string
	local o = opts or {}
	local report = {}
	local DayCycle = freshDayCycle()
	local Config = require(ReplicatedStorage.Shared.Config)
	local clock = tonumber(o.clock) or Config.Round.LobbyClockTime
	local setClock = if o.setClock ~= nil then o.setClock else RunService:IsEdit()

	local sky = ensure("Sky", "Sky")
	local atmosphere = ensure("Atmosphere", "Atmosphere")
	local bloom = ensure("BloomEffect", "Bloom")
	local rays = ensure("SunRaysEffect", "SunRays")
	local dof = ensure("DepthOfFieldEffect", "DepthOfField")
	local grade = ensure("ColorCorrectionEffect", "ArenaGrade")
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = workspace.Terrain
	end

	local static = LightingRig.Static
	setProps(Lighting, static.Lighting, report)
	setProps(sky, static.Sky, report)
	setProps(bloom, static.Bloom, report)
	setProps(rays, static.SunRays, report)
	setProps(dof, static.DepthOfField, report)
	setProps(grade, static.ArenaGrade, report)

	if setClock then
		Lighting.ClockTime = clock % 24
	end
	local look = DayCycle.lookAt(clock % 24)
	DayCycle.applyLook(look, {
		lighting = Lighting,
		atmosphere = atmosphere,
		grade = grade,
		bloom = bloom,
		rays = rays,
		sky = sky,
		dof = dof,
		clouds = clouds,
		wind = workspace,
	})
	table.insert(report, 1, string.format("LightingRig: look for %.2f h applied (Brightness %.2f, Exposure %.2f, OutdoorAmbient %s, EnvDiffuse %.2f, Atmosphere %.2f, wind %.1f,%.1f)",
		clock % 24, look.Brightness, look.Exposure, tostring(look.Outdoor), look.EnvDiffuse, look.AtmDensity, look.WindX, look.WindZ))
	return table.concat(report, "\n")
end

-- Edit-time preview of any hour (does not touch the round): LightingRig.preview(19.2)
function LightingRig.preview(hour: number): string
	return LightingRig.apply({ clock = hour, setClock = true })
end

return LightingRig
