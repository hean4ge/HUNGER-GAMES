--[[
	ArenaController - client-side arena presentation.
	  * The day/night cycle (helper ArenaController.Sky): every frame Lighting.ClockTime from the server's time base
	    (GameState "Clock", Shared.DayCycle) and the whole lighting look for that hour (Shared.DayCycle.Looks):
	    moonlit nights, warm low dawns and dusks, the "ArenaGrade" colour correction, atmosphere, bloom, sun rays;
	    low mist over the marsh and the lake at night and dawn. Lobby players keep the lobby hour.
	  * The border wall: a ring of tall ForceField panels (workspace.Arena.Border, client-local) placed every frame from
	    GameState BorderCenter / BorderRadius with workspace:BulkMoveTo. Visible during the Countdown (so the round's
	    starting ring - GameState.BorderStartRadius, PlayabilityPlan QW3 - shows from the plates) and Active, while
	    you're in the arena or spectating; it pulses while the border is moving, and a low hum (Sounds.BorderHum) plays from its
	    nearest point.
	  * A soft red grade (Lighting.BorderTint, local) while your own character is outside the border.
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
local BASE_TRANSPARENCY = 0.25
local PULSE_TRANSPARENCY = 0.14
local PULSE_SPEED = 2.6
local OUTSIDE_TINT = Color3.fromRGB(255, 190, 176)

local ArenaController = {}

local Controllers = nil
local panels: { BasePart } = {}
local cframes: { CFrame } = {}
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

local function buildWall()
	local folder = Instance.new("Folder")
	folder.Name = "Border"
	for i = 1, PANEL_COUNT do
		local panel = Instance.new("Part")
		panel.Name = "BorderPanel"
		panel.Anchored = true
		panel.CanCollide = false
		panel.CanQuery = false
		panel.CanTouch = false
		panel.CastShadow = false
		panel.Locked = true
		panel.Material = Enum.Material.ForceField
		panel.Color = Theme.Colors.Border
		panel.Transparency = BASE_TRANSPARENCY
		panel.Size = Vector3.new(4, WALL_HEIGHT, PANEL_THICKNESS)
		panel.Parent = folder
		panels[i] = panel
		cframes[i] = CFrame.identity
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
	if math.abs(target - panelTransparency) > 0.008 and t - lastTransparencyWrite >= 1 / 20 then
		panelTransparency = target
		lastTransparencyWrite = t
		for _, panel in ipairs(panels) do
			panel.Transparency = target
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
	if wallVisible and ClientState.alive and ClientState.inArena then
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
		if laidCenter ~= center or math.abs(displayRadius - laidRadius) > 0.003 then
			layoutWall(center, displayRadius)
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
