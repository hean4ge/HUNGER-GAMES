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

type Track = { inst: Instance?, prop: string, sky: any, wrote: any, target: any }

local tracks: { Track } = {
	{ inst = Lighting, prop = "Ambient", sky = nil, wrote = nil, target = HALL.ambient },
	{ inst = Lighting, prop = "OutdoorAmbient", sky = nil, wrote = nil, target = HALL.outdoor },
	{ inst = Lighting, prop = "EnvironmentDiffuseScale", sky = nil, wrote = nil, target = HALL.envDiffuse },
	{ inst = nil, prop = "Density", sky = nil, wrote = nil, target = HALL.density }, -- the Atmosphere
	{ inst = nil, prop = "TintColor", sky = nil, wrote = nil, target = HALL.tint }, -- Lighting.ArenaGrade
}

local hallCF: CFrame? = nil
local weight = 0
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

local function inHall(pos: Vector3): boolean
	if not hallCF then
		return false
	end
	local p = (hallCF :: CFrame):PointToObjectSpace(pos) - Vector3.new(0, HALL.centreY, 0)
	return math.abs(p.X) <= HALL.half.X and math.abs(p.Y) <= HALL.half.Y and math.abs(p.Z) <= HALL.half.Z
end

local function step(dt: number)
	local now = os.clock()
	if now >= nextScan then
		nextScan = now + 2
		scan()
	end
	local cam = workspace.CurrentCamera
	local want = if cam and inHall(cam.CFrame.Position) then 1 else 0
	if want == 0 and weight == 0 then
		return
	end
	local was = weight
	weight = math.clamp(weight + (if want > weight then 1 else -1) * dt / HALL.blend, 0, 1)
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
