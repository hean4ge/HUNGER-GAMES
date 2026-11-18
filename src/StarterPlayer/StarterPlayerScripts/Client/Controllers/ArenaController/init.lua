--[[
	ArenaController - client-side arena presentation.
	  * The day/night cycle (helper ArenaController.Sky): every frame Lighting.ClockTime from the server's time base
	    (GameState "Clock", Shared.DayCycle) and the whole lighting look for that hour (Shared.DayCycle.Looks):
	    moonlit nights, warm low dawns and dusks, the "ArenaGrade" colour correction, atmosphere, bloom, sun rays;
	    low mist over the marsh and the lake at night and dawn. Lobby players keep the lobby hour.
	  * The border wall: a ring of tall, thin panels of orange light (Neon, mostly clear: workspace.Arena.Border,
    client-local; ForceField panels showed only where two met, as thin seams, by day) placed every frame from
	    GameState BorderCenter / BorderRadius with workspace:BulkMoveTo. Visible during the Countdown (so the round's
	    starting ring - GameState.BorderStartRadius, PlayabilityPlan QW3 - shows from the plates) and Active, while
	    you're in the arena or spectating; it pulses while the border is moving, and a low hum (Sounds.BorderHum) plays from its
	    nearest point. The sheet is strong only within about 60 studs of the camera. From farther off the wall is told by
	    a bright line on the ground under it and a low skirt of light over that line (BorderLine, BorderSkirt: one of each
	    per panel, laid along the ground from Shared.ArenaLayout.heightAt), so the scenery behind keeps its own colours.
	  * A soft red grade (Lighting.BorderTint, local) while your own character is outside the border in the Active phase.
	API:
	  ArenaController.getBorder() -> (center: Vector3, radius: number, shrinking: boolean)
	  ArenaController.isInsideBorder(position: Vector3) -> boolean   (true outside Active)
	  ArenaController.isWallVisible() -> boolean
	  ArenaController.getClock() -> (clock: number, arenaView: boolean)   unwrapped hours (31 = 07:00 on day 2)
	  ArenaController.getLook() -> { [string]: any }                     the lighting look applied this frame
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Util = require(Shared:WaitForChild("Util"))

local Sky = require(script:WaitForChild("Sky"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local GameState = ReplicatedStorage:WaitForChild("GameState")
local localPlayer = Players.LocalPlayer

local BorderCfg = Config.Border
local PANEL_COUNT = math.clamp(math.floor(BorderCfg.WallPanels or 96), 24, 256)
local WALL_HEIGHT = BorderCfg.WallHeight or 520
local WALL_BELOW = 110 -- studs the wall reaches below BorderCenter (lake beds, ravines)
local PANEL_THICKNESS = 0.4
-- Neon is not lit by the scene, so the wall reads the same at noon and at midnight: a clear orange sheet you can see
-- the land through. ForceField (until 18 Nov) drew only at grazing angles: straight on, at 32 studs, the wall was a
-- few thin seams where panels met. The sheet is thicker in colour while the border moves (the pulse).
local WALL_MATERIAL = Enum.Material.Neon
-- 0.74 (seen in Studio at 32 and at 250 studs, noon and 21:00) read at once but dyed the land behind it orange and
-- the sky pink; 0.84 is the sheet with the valley still in its own colours behind it.
local BASE_TRANSPARENCY = 0.84
-- That held only at Studio's low unfocused quality. At full engine quality (seen 18 Nov, focused, Shaders Off and
-- Full) the 0.84 sheet dyed everything behind it: from the plates of a small round (ring 700, 550 studs away) the
-- far forest read red, the mountains pink and the sky purple. So a panel is the full sheet only near the camera and
-- thins out with distance: the wall reads where you can walk into it, and from afar the valley keeps its own colours
-- (0.965 at 550 studs left the ring barely visible from the plates; the line and the skirt below tell it now, so the
-- far sheet is thinner still).
local FAR_TRANSPARENCY = 0.975
-- The sheet is a warning, so it is the full sheet only where the wall can hurt you within seconds: at 60 studs (the
-- Edge with a full ring) the 0.84 sheet still dyed the whole cliff view salmon, and with a fade out to 90 studs the
-- one panel in front of the Edge (71 studs wide on a full ring) stood there as a tinted rectangle.
local FADE_NEAR = 20 -- studs from the camera (flat) to a panel's middle: nearer panels are the full sheet
local FADE_FAR = 64 -- panels this far and farther are at FAR_TRANSPARENCY
-- Where the wall is, from any distance, is told by what lies on the ground under it instead (18 Nov, after the thin
-- sheet left the starting ring all but invisible from the plates): a bright line along the ground, and over it a low
-- skirt of light that shows above the undergrowth from far off. Both follow the ground from corner to corner of the
-- ring (ArenaLayout.heightAt: the terrain where it has streamed in, the coarse height grid beyond), so they cover a
-- strip of scenery a few degrees tall instead of the whole view. Seen in Edit at full quality from a plate (rings 700
-- and 1,800), at 250, 100 and 32 studs and from the Edge. A skirt at 0.90 from every distance dyed a ten-degree band
-- at 250 studs, so it is only there from SKIRT_NEAR out and at its full 0.93 from SKIRT_FAR.
local LINE_TRANSPARENCY = 0.15
local LINE_ANGLE = 0.0075 -- the line's height above the ground per stud of distance from the camera (about 0.43 degrees) ...
local LINE_MIN, LINE_MAX = 2, 14 -- ... within these limits, so it is a few pixels tall from the plates and from 30 studs
local SKIRT_HEIGHT = 44 -- studs above the ground: over the gorse and the beeches
local SKIRT_SINK = 24 -- and this far into it (the ground between two corners can dip under the straight run)
local SKIRT_TRANSPARENCY = 0.93 -- from SKIRT_FAR studs out
local SKIRT_NEAR, SKIRT_FAR = 120, 480 -- nearer than SKIRT_NEAR there is no skirt: the line is plain to see there
local GROUND_PER_FRAME = 16 -- corners whose ground height is read again each frame (all of them about 6 times a second)
local PULSE_TRANSPARENCY = -0.12 -- added at the top of the pulse: more solid while it moves
local PULSE_SPEED = 2.6
local OUTSIDE_TINT = Color3.fromRGB(255, 190, 176)

local ArenaController = {}

local Controllers = nil
local panels: { BasePart } = {}
local cframes: { CFrame } = {}
-- the ground line and the skirt: one of each under every panel, from the panel's left corner to its right one
local lines: { BasePart } = {}
local lineCFrames: { CFrame } = {}
local lineHeights: { number } = {}
local skirts: { BasePart } = {}
local skirtCFrames: { CFrame } = {}
local cornerY: { number } = {} -- the ground under corner i (the left end of panel i)
local cornerNext = 1
local groundDirty = true
local surfaceParams: RaycastParams? = nil
local SURFACE_CAST_TOP = 1400 -- above the highest terrain (1,143), as ArenaLayout casts
local SURFACE_CAST_DOWN = Vector3.new(0, -1600, 0)
local wallFolder: Folder? = nil
local wallVisible = false
local displayCenter = Vector3.new(ArenaLayout.Center.X, ArenaLayout.BaseHeight, ArenaLayout.Center.Z)
local displayRadius = BorderCfg.StartRadius
local laidCenter: Vector3? = nil
local laidRadius = -1
local panelWidth = 0
local panelTransparency = BASE_TRANSPARENCY
local pulseTime = 0
local lastTransparencyWrite = 0
local humAttachment: Attachment? = nil
local humSound: Sound? = nil
local tint: ColorCorrectionEffect? = nil
local tintAlpha = 0
local warned = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[ArenaController] " .. message)
end

-- Border wall --------------------------------------------------------------------------------------------------------

local function wallPart(name: string, transparency: number, size: Vector3, folder: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = WALL_MATERIAL
	part.Color = Theme.Colors.Border
	part.Transparency = transparency
	part.Size = size
	part.Parent = folder
	return part
end

local function buildWall()
	local folder = Instance.new("Folder")
	folder.Name = "Border"
	for i = 1, PANEL_COUNT do
		panels[i] = wallPart("BorderPanel", BASE_TRANSPARENCY, Vector3.new(4, WALL_HEIGHT, PANEL_THICKNESS), folder)
		cframes[i] = CFrame.identity
		lines[i] = wallPart("BorderLine", LINE_TRANSPARENCY, Vector3.new(4, 2 * LINE_MIN, PANEL_THICKNESS), folder)
		lineCFrames[i] = CFrame.identity
		lineHeights[i] = LINE_MIN
		skirts[i] = wallPart("BorderSkirt", 1, Vector3.new(4, SKIRT_HEIGHT + SKIRT_SINK, PANEL_THICKNESS), folder)
		skirtCFrames[i] = CFrame.identity
		cornerY[i] = displayCenter.Y
	end
	wallFolder = folder
end

local function wallParent(): Instance
	return workspace:FindFirstChild("Arena") or workspace
end

local function layoutWall(center: Vector3, radius: number)
	radius = math.max(radius, 2)
	local count = #panels
	-- panels tangent to the circle at their middle meet exactly at the corners of a regular polygon
	local width = 2 * radius * math.tan(math.pi / count) + 0.05
	if panelWidth <= 0 or width > panelWidth or (panelWidth - width) > panelWidth * 0.005 then
		panelWidth = width
		local size = Vector3.new(width, WALL_HEIGHT, PANEL_THICKNESS)
		for _, panel in ipairs(panels) do
			panel.Size = size
		end
	end
	local y = center.Y - WALL_BELOW + WALL_HEIGHT / 2
	local inward = Vector3.new(center.X, y, center.Z)
	local stepAngle = (2 * math.pi) / count
	for i = 1, count do
		local a = (i - 1) * stepAngle
		local position = Vector3.new(center.X + math.sin(a) * radius, y, center.Z - math.cos(a) * radius)
		cframes[i] = CFrame.lookAt(position, inward) -- width runs along the ring
	end
	workspace:BulkMoveTo(panels, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	laidCenter = center
	laidRadius = radius
end

-- Reads the ground under some of the ring's corners again (all of them when `all`): corner i is the left end of panel i.
-- Where neither the terrain nor the height grid answers, the corner keeps the border centre's height.
local function updateGround(center: Vector3, radius: number, all: boolean)
	local heightAt = ArenaLayout.heightAt
	if type(heightAt) ~= "function" then
		return
	end
	-- water counts as ground here, so over the lake the line lies on the surface and not on the bed (heightAt ignores
	-- water); where the terrain has not streamed in this finds nothing and heightAt's grid answers
	local params = surfaceParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.IgnoreWater = false
		surfaceParams = params
	end
	params.FilterDescendantsInstances = { workspace.Terrain }
	local count = #panels
	local stepAngle = (2 * math.pi) / count
	local cornerRadius = math.max(radius, 2) / math.cos(math.pi / count)
	for _ = 1, if all then count else math.min(GROUND_PER_FRAME, count) do
		local i = cornerNext
		cornerNext = i % count + 1
		local a = (i - 1.5) * stepAngle
		local x, z = center.X + math.sin(a) * cornerRadius, center.Z - math.cos(a) * cornerRadius
		local hit = workspace:Raycast(Vector3.new(x, SURFACE_CAST_TOP, z), SURFACE_CAST_DOWN, params)
		local y = if hit then hit.Position.Y else (heightAt(x, z) or center.Y)
		if math.abs(y - cornerY[i]) > 0.2 then
			cornerY[i] = y
			groundDirty = true
		end
	end
end

-- The ground line and the skirt: under each panel one straight run from its left corner's ground to its right
-- corner's, standing in the wall's plane. A run is as long as its slope makes it, so the sizes are written here too
-- (only when one changes by half a percent: never while the ring stands still).
local function layoutGround(center: Vector3, radius: number)
	radius = math.max(radius, 2)
	local count = #panels
	local stepAngle = (2 * math.pi) / count
	local cornerRadius = radius / math.cos(math.pi / count)
	local px, pz = center.X + math.sin(-0.5 * stepAngle) * cornerRadius, center.Z - math.cos(-0.5 * stepAngle) * cornerRadius
	local skirtRise = (SKIRT_HEIGHT - SKIRT_SINK) / 2
	for i = 1, count do
		local a = (i - 0.5) * stepAngle
		local qx, qz = center.X + math.sin(a) * cornerRadius, center.Z - math.cos(a) * cornerRadius
		local py, qy = cornerY[i], cornerY[i % count + 1]
		local run = Vector3.new(qx - px, qy - py, qz - pz)
		local length = math.max(run.Magnitude, 0.01)
		local right = run / length
		local mx, mz = (px + qx) / 2, (pz + qz) / 2
		local inward = Vector3.new(center.X - mx, 0, center.Z - mz).Unit
		local up = inward:Cross(right)
		local cf = CFrame.fromMatrix(Vector3.new(mx, (py + qy) / 2, mz), right, up, inward)
		lineCFrames[i] = cf
		skirtCFrames[i] = cf + up * skirtRise
		local line = lines[i]
		if math.abs(length + 0.05 - line.Size.X) > length * 0.005 then
			line.Size = Vector3.new(length + 0.05, 2 * lineHeights[i], PANEL_THICKNESS)
			skirts[i].Size = Vector3.new(length + 0.05, SKIRT_HEIGHT + SKIRT_SINK, PANEL_THICKNESS)
		end
		px, pz = qx, qz
	end
	workspace:BulkMoveTo(lines, lineCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	workspace:BulkMoveTo(skirts, skirtCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	groundDirty = false
end

local function startHum()
	if humSound then
		return
	end
	if not humAttachment then
		local attachment = Instance.new("Attachment")
		attachment.Name = "BorderHum"
		attachment.Parent = workspace.Terrain
		humAttachment = attachment
	end
	local ok, sound = pcall(Sfx.play, "BorderHum", { parent = humAttachment, looped = true })
	if ok and typeof(sound) == "Instance" and sound:IsA("Sound") then
		humSound = sound
	end
end

local function stopHum()
	if humSound then
		humSound:Stop()
		humSound:Destroy()
		humSound = nil
	end
end

local function setWallVisible(visible: boolean)
	if visible == wallVisible then
		return
	end
	wallVisible = visible
	if wallFolder then
		wallFolder.Parent = if visible then wallParent() else nil
	end
	if visible then
		laidRadius = -1 -- force a layout this frame
		startHum()
	else
		stopHum()
	end
end

local function wallShouldShow(): boolean
	local phase = GameState:GetAttribute("Phase")
	if phase ~= "Active" and phase ~= "Countdown" then
		return false
	end
	return ClientState.inArena == true or ClientState.spectating ~= nil
end

local function updatePulse(dt: number)
	local target = BASE_TRANSPARENCY
	if GameState:GetAttribute("BorderShrinking") == true then
		pulseTime += dt
		target = BASE_TRANSPARENCY + PULSE_TRANSPARENCY * (0.5 + 0.5 * math.sin(pulseTime * PULSE_SPEED))
	else
		pulseTime = 0
	end
	local t = os.clock()
	if t - lastTransparencyWrite < 1 / 20 then
		return
	end
	lastTransparencyWrite = t
	panelTransparency = target
	-- each panel by its flat distance from the camera: the full sheet near, thinned out far (see FAR_TRANSPARENCY)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else displayCenter
	local span = math.max(FADE_FAR - FADE_NEAR, 1)
	for i, panel in ipairs(panels) do
		local p = cframes[i].Position
		local dx, dz = p.X - eye.X, p.Z - eye.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		local k = math.clamp((distance - FADE_NEAR) / span, 0, 1)
		local value = target + (FAR_TRANSPARENCY - target) * k
		if math.abs(value - panel.Transparency) > 0.004 then
			panel.Transparency = value
		end
		-- the skirt is for the far view: none near the camera, all of it from SKIRT_FAR
		local skirt = skirts[i]
		local skirtValue = 1 + (SKIRT_TRANSPARENCY - 1) * math.clamp((distance - SKIRT_NEAR) / (SKIRT_FAR - SKIRT_NEAR), 0, 1)
		if math.abs(skirtValue - skirt.Transparency) > 0.004 then
			skirt.Transparency = skirtValue
		end
		-- the line keeps about the same height on screen: taller the farther it is
		local height = math.clamp(distance * LINE_ANGLE, LINE_MIN, LINE_MAX)
		if math.abs(height - lineHeights[i]) > lineHeights[i] * 0.08 then
			lineHeights[i] = height
			local line = lines[i]
			line.Size = Vector3.new(line.Size.X, 2 * height, PANEL_THICKNESS)
		end
	end
end

-- The hum follows the point of the wall nearest the camera.
local function updateHum(center: Vector3, radius: number)
	local camera = workspace.CurrentCamera
	if not humAttachment or not camera then
		return
	end
	local p = camera.CFrame.Position
	local dx, dz = p.X - center.X, p.Z - center.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < 0.01 then
		dx, dz, distance = 0, -1, 1
	end
	local k = radius / distance
	local bottom = center.Y - WALL_BELOW
	local y = math.clamp(p.Y, bottom, bottom + WALL_HEIGHT)
	humAttachment.WorldPosition = Vector3.new(center.X + dx * k, y, center.Z + dz * k)
end

local function updateTint(dt: number, center: Vector3, radius: number)
	local outside = false
	-- Active only: in the Countdown the wall already shows while the body is still in the lobby, far outside the ring,
	-- until the server has streamed the plate in and placed it (the launch intro and the plate got a red grade)
	if wallVisible and ClientState.alive and ClientState.inArena and GameState:GetAttribute("Phase") == "Active" then
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = root.Position
			local dx, dz = p.X - center.X, p.Z - center.Z
			outside = dx * dx + dz * dz > radius * radius
		end
	end
	local target = if outside then 1 else 0
	tintAlpha += (target - tintAlpha) * Util.damp(if outside then 5 else 3, dt)
	if target == 0 and tintAlpha < 0.003 then
		tintAlpha = 0
		if tint and tint.Enabled then
			tint.Enabled = false
		end
		return
	end
	if not tint then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "BorderTint"
		effect.Parent = Lighting
		tint = effect
	end
	local effect = tint :: ColorCorrectionEffect
	effect.Enabled = true
	effect.TintColor = Color3.new(1, 1, 1):Lerp(OUTSIDE_TINT, tintAlpha)
	effect.Saturation = -0.3 * tintAlpha
	effect.Contrast = 0.08 * tintAlpha
end

local function onHeartbeat(dt: number)
	local attrCenter = GameState:GetAttribute("BorderCenter")
	local center = if typeof(attrCenter) == "Vector3" then attrCenter else displayCenter
	local attrRadius = tonumber(GameState:GetAttribute("BorderRadius"))
		or tonumber(GameState:GetAttribute("BorderStartRadius"))
		or BorderCfg.StartRadius
	local show = wallShouldShow()
	-- the server publishes the radius ~5 times a second; ease toward it so the wall glides
	if not show or math.abs(attrRadius - displayRadius) > 40 then
		displayRadius = attrRadius
	else
		displayRadius += (attrRadius - displayRadius) * Util.damp(6, dt)
	end
	displayCenter = center
	setWallVisible(show)
	if show then
		local fresh = laidRadius < 0 -- just shown: read the ground under every corner at once
		local moved = laidCenter ~= center or math.abs(displayRadius - laidRadius) > 0.003
		if moved then
			layoutWall(center, displayRadius)
		end
		updateGround(center, displayRadius, fresh)
		if moved or groundDirty then
			layoutGround(center, displayRadius)
		end
		updatePulse(dt)
		updateHum(center, displayRadius)
	end
	updateTint(dt, center, displayRadius)
end

-- Public API ---------------------------------------------------------------------------------------------------------

function ArenaController.getBorder(): (Vector3, number, boolean)
	return displayCenter, displayRadius, GameState:GetAttribute("BorderShrinking") == true
end

function ArenaController.isInsideBorder(position: Vector3): boolean
	if typeof(position) ~= "Vector3" or GameState:GetAttribute("Phase") ~= "Active" then
		return true
	end
	local dx, dz = position.X - displayCenter.X, position.Z - displayCenter.Z
	return dx * dx + dz * dz <= displayRadius * displayRadius
end

function ArenaController.isWallVisible(): boolean
	return wallVisible
end

function ArenaController.getClock(): (number, boolean)
	return Sky.getClock()
end

function ArenaController.getLook()
	return Sky.getLook()
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function ArenaController.Init(registry)
	Controllers = registry
end

function ArenaController.Start()
	Sky.start(ClientState)
	buildWall()
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(onHeartbeat, dt)
		if not ok then
			warnOnce("heartbeat", "Border update failed: " .. tostring(err))
		end
	end)
end

return ArenaController
