--[[
	HallLightController - the Training Centre hall's own light (client only, a "lighting zone").
	The hall is lit by WorldGen.TrainingCentreBuilder's warm PointLight grid. Outside, the day cycle (ArenaController.Sky,
	DayCycle) drives Lighting for the lobby clock: a cool navy ambient, the haze of the Atmosphere and the arena's colour
	grade. Under the hall's roof that read as a cold blue room with a misty far end. While the camera is inside the hall
	(hall space |x| <= 111, -1 <= y <= 37, |z| <= 75.5: the shell, not the platform, the corridor or the red room) this
	blends, over HALL.blend s, to a warm sports-hall look: warm grey Ambient and OutdoorAmbient, a fifth of the sky's
	diffuse light (it painted the walls and ceiling navy in play), almost no haze, a neutral-warm tint. Values tuned in
	a Studio playtest at the automatic quality level, 19 Nov.
	Leaving the hall blends back to whatever the day cycle last wrote.
	Wave 16: platform B blends in too (seen from the platform, through the arches, the hall read navy until the camera
	stepped inside): PLATFORM.weight at the arches down to PLATFORM.back at the platform's back wall. And the walk-in red
	room (behind the launch corridor) has its own zone, RED: a low dark-red ambient, so the walkway and the stairs read
	(they were near-black) while the room stays red and dim. Zones switch through a blend of the targets, never a jump.

	How it shares Lighting with the day cycle: Sky writes a property only when its own look changes (it caches what it
	wrote). Each frame this notes any value it did not write itself as the day cycle's (so it always knows the value to
	return to), then writes the blend. When the blend is back at 0 it writes the day cycle's value once and stops.
	Cheap: one point-in-box test a frame, and up to six property writes only while in or near the hall.
]]
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local HallLightController = {}

local HALL = {
	half = Vector3.new(111, 19, 75.5), -- half size of the zone, centred at hall (0, 18, 0)
	centreY = 18,
	blend = 0.6, -- seconds to blend in or out
	ambient = Color3.fromRGB(86, 80, 72), -- warm grey (the day cycle's lobby ambient is about (38, 40, 48))
	-- the day cycle's OutdoorAmbient (about (76, 86, 104), sky blue) reaches inside the roofed hall at the automatic
	-- quality levels and turned its ceiling and walls navy in play (19 Nov): a warm grey there too
	outdoor = Color3.fromRGB(86, 80, 72),
	-- the sky's diffuse light (EnvironmentDiffuseScale 1) was what painted the walls and ceiling navy: a fifth of it
	envDiffuse = 0.2,
	density = 0.04, -- the Atmosphere's density: a clear hall, not a misty one
	tint = Color3.fromRGB(255, 249, 240), -- ArenaGrade's TintColor: neutral warm
}

-- platform B, south of the arches (hall space |x| <= 152, -8 <= y <= 26, 75.5 < z <= 114): the hall's look at this weight
-- by the arches, easing to `back` at the platform's back wall
local PLATFORM = { halfX = 152, minY = -8, maxY = 26, minZ = 75.5, maxZ = 114, weight = 1, back = 0.75 }

-- the walk-in red room (hall space, centred (0, 0.25, -100), 32 x 26 x 26; the corridor is not in it)
local RED = {
	centre = Vector3.new(0, 0.25, -100),
	half = Vector3.new(16.5, 13.5, 13.5),
	ambient = Color3.fromRGB(96, 46, 42), -- dark red: the walkway and the stairs read, the room stays red and dim
	outdoor = Color3.fromRGB(74, 38, 36),
	envDiffuse = 0.12,
	density = 0.05,
	tint = Color3.fromRGB(255, 236, 230),
}

type Track = { inst: Instance?, prop: string, sky: any, wrote: any, target: any, hall: any, red: any }

local tracks: { Track } = {
	{ inst = Lighting, prop = "Ambient", sky = nil, wrote = nil, target = HALL.ambient, hall = HALL.ambient, red = RED.ambient },
	{ inst = Lighting, prop = "OutdoorAmbient", sky = nil, wrote = nil, target = HALL.outdoor, hall = HALL.outdoor, red = RED.outdoor },
	{ inst = Lighting, prop = "EnvironmentDiffuseScale", sky = nil, wrote = nil, target = HALL.envDiffuse, hall = HALL.envDiffuse,
		red = RED.envDiffuse },
	{ inst = nil, prop = "Density", sky = nil, wrote = nil, target = HALL.density, hall = HALL.density, red = RED.density }, -- the Atmosphere
	{ inst = nil, prop = "TintColor", sky = nil, wrote = nil, target = HALL.tint, hall = HALL.tint, red = RED.tint }, -- Lighting.ArenaGrade
}

local hallCF: CFrame? = nil
local weight = 0
local redness = 0 -- 0: the hall's look is the target, 1: the red room's
local nextScan = 0

local function lerp(a: any, b: any, t: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b, t)
	end
	return a + (b - a) * t
end

local function same(a: any, b: any): boolean
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 1e-3
	end
	return a == b or (type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-4)
end

local function scan()
	local set = workspace:FindFirstChild("TrainingCentre")
	hallCF = if set and set:IsA("Model") and set:GetAttribute("BlenderSet") == true then set.WorldPivot else nil
	tracks[4].inst = Lighting:FindFirstChildWhichIsA("Atmosphere")
	tracks[5].inst = Lighting:FindFirstChild("ArenaGrade")
end

-- How much of a zone's look this point gets (0..1), and whether that zone is the red room.
local function zoneAt(pos: Vector3): (number, boolean)
	if not hallCF then
		return 0, false
	end
	local local_ = (hallCF :: CFrame):PointToObjectSpace(pos)
	local p = local_ - Vector3.new(0, HALL.centreY, 0)
	if math.abs(p.X) <= HALL.half.X and math.abs(p.Y) <= HALL.half.Y and math.abs(p.Z) <= HALL.half.Z then
		return 1, false
	end
	local q = local_
	if math.abs(q.X) <= PLATFORM.halfX and q.Y >= PLATFORM.minY and q.Y <= PLATFORM.maxY and q.Z > PLATFORM.minZ
		and q.Z <= PLATFORM.maxZ then
		local t = math.clamp((q.Z - PLATFORM.minZ) / (PLATFORM.maxZ - PLATFORM.minZ), 0, 1)
		return PLATFORM.weight + (PLATFORM.back - PLATFORM.weight) * t, false
	end
	local r = local_ - RED.centre
	if math.abs(r.X) <= RED.half.X and math.abs(r.Y) <= RED.half.Y and math.abs(r.Z) <= RED.half.Z then
		return 1, true
	end
	return 0, false
end

local function step(dt: number)
	local now = os.clock()
	if now >= nextScan then
		nextScan = now + 2
		scan()
	end
	local cam = workspace.CurrentCamera
	local want, red = 0, false
	if cam then
		want, red = zoneAt(cam.CFrame.Position)
	end
	if want == 0 and weight == 0 then
		redness = if red then 1 else 0
		return
	end
	local was = weight
	local rate = dt / HALL.blend
	weight = math.clamp(weight + math.clamp(want - weight, -rate, rate), 0, 1)
	-- the target itself moves between the hall's look and the red room's (only while some of it is in use)
	if weight <= 0 or was <= 0 then
		redness = if red then 1 else 0
	else
		redness = math.clamp(redness + math.clamp((if red then 1 else 0) - redness, -rate, rate), 0, 1)
	end
	for _, tr in ipairs(tracks) do
		tr.target = lerp(tr.hall, tr.red, redness)
	end
	for _, tr in ipairs(tracks) do
		local inst = tr.inst
		if inst and inst.Parent then
			local current = (inst :: any)[tr.prop]
			-- a value this did not write is the day cycle's: the one to blend from and to return to
			if tr.wrote == nil or not same(current, tr.wrote) then
				tr.sky = current
			end
			if weight <= 0 then
				if was > 0 then
					(inst :: any)[tr.prop] = tr.sky
				end
				tr.wrote = nil
			else
				local v = lerp(tr.sky, tr.target, weight)
				;(inst :: any)[tr.prop] = v
				tr.wrote = (inst :: any)[tr.prop]
			end
		end
	end
end

function HallLightController.Start()
	scan()
	RunService:BindToRenderStep("LS_HallLight", Enum.RenderPriority.Last.Value, function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[HallLightController] " .. tostring(err))
		end
	end)
end

return HallLightController
