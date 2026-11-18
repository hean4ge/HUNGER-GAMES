--[[
	LaunchIntroController - the launch intro of the beta (TwoArenas.md section 2, Tier 1): one shot at the call, played
	on this client from the round's shared clock, before today's plate rise.
	  1. The red room: down through the teal hex frame at your own stand-in on the dusty-rose lift disc, under the fine
	     diamond net (a slow push in; you look up; the lift starts and carries you up toward the lens).
	  2. "It loads up": a quick dip to black into your glass case among the other contenders in theirs (Full only):
	     the camera at face height outside your glass looks past you along the row, then pulls back round the hall.
	  3. The rise: your disc carries you up your pole through the round hall while the camera circles you (two thirds
	     of a turn in the full shot, a quarter in the short cut), dropping low behind you to look up the pole, and then,
	     for the last part of the climb, spiralling in over your right shoulder and into your own eyes (your stand-in
	     fades as the lens reaches it; the field of view eases to your own setting). You ride the rest in first person,
	     looking up the pole at the lit roof and the white opening it runs into. The others rise on their own poles a
	     little ahead or behind. With Roblox's Reduce Motion the camera does not circle or travel: it holds its first
	     bearing and a short dip to black cuts to your eyes.
	  4. The arrival: the light from above floods the picture (the set's exposure and bloom, then a pale cover up to
	     0.95, never a hard white frame) while your eyes come down level, and under it the shot hands off: first person
	     on your own plate, facing the Spire, at the very bearing, pitch and field of view the shot ended on (no jump;
	     LaunchController's wave-1 turn, which waits for the shot, asks for the same view). Then the sun's glare falls
	     away over 1.5 to 2 seconds as your eyes adjust (Glare, a child module: stronger facing the real sun in
	     daylight, gentle at dawn, under cloud or in shade, and at night no light at all, the cover dark and gone in
	     under a second; "Shaders: Off" gets a plain fade of the same cover and nothing in Lighting is touched). The
	     plate rises out of its tube on today's timeline (GameState LaunchAt), then the last seconds of the countdown
	     and the horn. A skip still cuts through black, with no glare after it.
	The server picks the cut and the clock (RoundService, Config.Launch): GameState LaunchCut "Full" | "Short",
	LaunchCallAt, and LaunchAt = the end of the white-out = the start of the plate rise. Everyone in a round sees the
	same cut on the same clock; a client that starts late joins the shot where everyone else is, or skips it when it is
	nearly over.
	While the shot plays (ClientState.launchShot = true) this controller owns the camera (Scriptable), the lighting
	(a profile per room; ArenaController's day cycle holds and writes its whole look again afterwards) and the screen:
	the HUD, HUDFX, Overlay, FeedbackLines, TouchControls and Menu ScreenGuis, Roblox's touch controls, chat window
	and player list are switched off and put back as they were (the Menu comes back at once if you open it); CameraController, the zoom and
	ViewmodelController stand down; NotificationController holds its countdown numbers and ticks; music ducks and
	the arena's ambience is muted. Skip: hold Space / A, or hold the SKIP button on touch (Input action "LaunchSkip",
	bound only during the shot, Config.Launch.SkipHold): it cuts your own camera to your plate (in the tube until the
	rise); the round's timing stays the server's.
	Robust: every frame and every step of the clean-up is protected. An error, your death, a cancelled round, leaving
	the arena, a stalled render step or a shot still running at the horn ends it at once and gives back the camera, the
	lighting and the HUD (today's rise then plays as usual). The server's cut is the only switch: with
	Config.Launch.Intro = false it sends none and nothing here runs (the set isn't even built).
	Low engine quality draws none of the set's lights: each room has a flat fill for that (FILL), the same on
	every client; with "Shaders: Off" the shot uses no bloom (the flood of light is exposure, grade and cover).
	Studio only (tests and stills): LocalPlayer attribute LS_LaunchPreview = "Full" | "Short" plays a preview shot
	without a round (no hand-off; the camera goes back where it was), LS_LaunchFreeze = seconds holds the preview at
	that moment of the shot, LS_LaunchSkipTest = true acts as a completed skip hold; LS_LaunchStats (JSON) reports
	frame times per stage after every shot. LS_LaunchGlareTest = true (or the cover's alpha to start from) plays the
	arrival's glare alone, where you stand and look, at the hour the sky shows; LS_LaunchGlareFreeze = seconds holds
	it at that moment; LS_LaunchGlare (JSON) reports each glare when it ends (Glare).
	The arena (docs/design/Map1Build.md): the hall has one glass case per plate (ArenaLayout.PlinthCount, else the
	number of its Plates), but never more than MAX_CASES (24): the hall's radius and the camera's path are made for
	24 cases 15.7 studs apart. With 48 on the same ring the cases stood 7.85 apart and the camera started inside the
	neighbour's (seen 18 Nov). On Map 1 (48 plates) two neighbouring plates share a case, and the second contender of
	a pair is shown in the nearest free one. A contender's case is the plate they stand on:
	plate k of n stands at ArenaLayout.PlinthOffsetDeg + k * 360 / n degrees (the offset is 0 on the forest arena and
	3.75 on Map 1), so slotOf takes the offset off the bearing before it rounds. "On the plate ring" is
	LaunchController.onRing, the same test the plate rise uses. Map 1's plinths have no bores (decision 6): the plate
	does not rise, and the white-out hands off to a contender already standing on their plinth.
	API: LaunchIntroController.isPlaying() -> boolean, LaunchIntroController.stats() -> { [string]: any }?
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Input = require(Shared:WaitForChild("Input"))
local Glyphs = require(Shared:WaitForChild("Glyphs"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local ArenaLayout = require(Shared:WaitForChild("ArenaLayout"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Set = require(script:WaitForChild("Set"))
local Figures = require(script:WaitForChild("Figures"))
local Glare = require(script:WaitForChild("Glare"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local localPlayer = Players.LocalPlayer
local LaunchCfg = Config.Launch or {}
local IS_STUDIO = RunService:IsStudio()

local IDLE_ID = "rbxassetid://17172918855" -- the game's own idle clip (StarterCharacterScripts.Animate)
local SKIP_ACTION = "LaunchSkip"
local RENDER_NAME = "LS_LaunchShot"
local SKIP_HOLD = tonumber(LaunchCfg.SkipHold) or 0.6
local HIDE_GUIS = { "HUD", "HUDFX", "Overlay", "FeedbackLines", "TouchControls", "Menu" }
-- Roblox's own windows that would sit over the letterboxed shot (the pointer is already hidden: HUDController hides it
-- for a living contender in the arena)
local HIDE_CORE = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList }
-- The hall holds at most this many cases: its radius (Set: R_CASE 60) and the camera's path are made for 24.
local MAX_CASES = 24
local WHITE = Color3.fromRGB(246, 248, 252) -- the cover's colour when the sky can't be read (Glare.sky gives the real one)
local FACE_PITCH = -6 -- degrees: the view the shot ends on and hands over (LaunchController's FACE_PITCH)
local EYE_AHEAD = 12 -- studs ahead of the eyes the first-person view aims at
local BLACK = Color3.new(0, 0, 0)
local LIT = Set.Colors.light
local UNLIT = Color3.fromRGB(40, 44, 50)

-- Stage times in seconds from the call for the nominal cinematic length (the plan ends at LaunchAt), scaled to the
-- server's LaunchAt - LaunchCallAt.
--   look      the stand-in looks up the shaft     lift    the lift starts      dip   the dip to black out of the red room
--   cases     { from, to } at your case (Full)    rise    { from, to } up the pole, the disc climbing riseHeight studs
--   white     the flood of light starts           handoff first person on your plate (the glare falls from there)
--   phi       the camera's bearing round you { start, end } in degrees (0 = in front, + = your right). It ends
--             behind your right shoulder (155 = -205): the pole stands behind your left one, at 220.
--   eyes      { from, to } in rise progress (0..1): the camera leaves its circle and spirals into your own eyes;
--             from `to` on the rise is first person
--   low       the camera's lowest height against your feet, reached as the spiral starts (the full shot looks up at
--             you and the pole from under the disc; the short cut has no time to go down there and back)
--   gaze      degrees you look up the pole in first person      level  { from, to } seconds: your eyes come down to
--             the view the hand-off gives (FACE_PITCH), mostly under the flood of light
-- The server's clock depends on length alone (LaunchAt - LaunchCallAt); length, rise, white and handoff are as they
-- were before the first-person ending.
local PLANS = {
	Full = {
		length = 15.4, look = 1.0, lift = 3.3, dip = 4.45, cases = { 4.5, 8.6 }, rise = { 8.6, 14.95 },
		white = 14.15, handoff = 14.95, riseHeight = 70, phi = { 34.4, -205 }, start = nil,
		eyes = { 0.46, 0.70 }, low = -1.9, gaze = 60, level = { 14.15, 14.9 },
	},
	Short = {
		length = 6.2, look = 0.3, lift = 0.8, dip = 1.6, cases = nil, rise = { 1.66, 5.75 },
		white = 5.05, handoff = 5.75, riseHeight = 44, phi = { 60, 155 },
		start = { r = 9.6, h = 4.3, fov = 54 },
		eyes = { 0.40, 0.66 }, low = 1.8, gaze = 60, level = { 5.05, 5.7 },
	},
}
-- the case stage's last pose (slot space) = the full rise's first: continuous position, target and field of view
local CASE_END_EYE = Vector3.new(6.5, 6.4, -9.5)
local CASE_END_FOV = 52

-- Lighting per room (TwoArenas 2.8: navy halls, the red room's warm dark; the light carries the hue)
local PROFILES = {
	Red = {
		Ambient = Color3.fromRGB(96, 64, 66), Exposure = 0.2, EnvSpecular = 0.3, AtmDensity = 0.12,
		AtmColor = Color3.fromRGB(70, 42, 44), AtmDecay = Color3.fromRGB(44, 24, 26), BloomIntensity = 0.6,
		BloomSize = 24, BloomThreshold = 1.15, GradeContrast = 0.12, GradeSaturation = -0.06,
		GradeTint = Color3.fromRGB(255, 243, 238),
	},
	Cases = {
		Ambient = Color3.fromRGB(66, 82, 110), Exposure = 0.35, EnvSpecular = 0.35, AtmDensity = 0.18,
		AtmColor = Color3.fromRGB(40, 52, 72), AtmDecay = Color3.fromRGB(30, 40, 58), BloomIntensity = 0.75,
		BloomSize = 26, BloomThreshold = 1.1, GradeContrast = 0.1, GradeSaturation = -0.06,
		GradeTint = Color3.fromRGB(236, 244, 255),
	},
	Rise = {
		Ambient = Color3.fromRGB(50, 62, 86), Exposure = 0.35, EnvSpecular = 0.35, AtmDensity = 0.22,
		AtmColor = Color3.fromRGB(30, 40, 58), AtmDecay = Color3.fromRGB(22, 30, 44), BloomIntensity = 1.0,
		BloomSize = 32, BloomThreshold = 1.0, GradeContrast = 0.14, GradeSaturation = -0.04,
		GradeTint = Color3.fromRGB(232, 240, 255),
	},
}
-- The flat fill. At low engine quality (a phone on automatic graphics, a weak PC, an unfocused Studio window: levels
-- about 1 to 5 of 21) the engine draws none of the set's SpotLights and PointLights, and the rooms above are lit by
-- their Ambient alone. Measured 18 Nov at level 4: the red room's disc read luma 5 and the rise luma 4 (only the Neon
-- bars showed); the response to Ambient is steep (red room (200,160,160) gave luma 123).
--   Full   the picture reads with no local light, no shadow and no bloom at all. Every client gets it: no script can
--          read the engine's running quality level (the detail tier said High in a window drawing at level 3.5), and
--          with the lights drawing at full quality Full changes little (measured in Studio: the red room's frame
--          luma 44 without the fill, 54 with it; the rise 13 and 42, the figure 78 and 159, nothing clipped).
--   Part   a smaller lift, kept for comparison: at level 3.5 it left the rooms dim (seen in play, 18 Nov)
-- Studio tests: LocalPlayer attribute LS_LaunchFill = "Full" | "Part" | "None" picks one.
local FILL = {
	Full = {
		Red = { Ambient = Color3.fromRGB(150, 118, 120) },
		Cases = { Ambient = Color3.fromRGB(128, 150, 190), Exposure = 0.6 },
		Rise = { Ambient = Color3.fromRGB(120, 140, 180), Exposure = 0.6 },
	},
	Part = {
		Red = { Ambient = Color3.fromRGB(124, 92, 94) },
		Cases = { Ambient = Color3.fromRGB(96, 114, 150), Exposure = 0.45 },
		Rise = { Ambient = Color3.fromRGB(90, 106, 140), Exposure = 0.45 },
	},
}
local LIGHT_PROPS = { "Ambient", "OutdoorAmbient", "Brightness", "ExposureCompensation", "EnvironmentDiffuseScale",
	"EnvironmentSpecularScale", "ColorShift_Top", "ColorShift_Bottom", "GlobalShadows" }
local EFFECT_PROPS = {
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
	ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
	SunRaysEffect = { "Enabled", "Intensity" },
	DepthOfFieldEffect = { "Enabled" },
}

local LaunchIntroController = {}

local Controllers: any = nil
local set: any = nil
local building = false
local buildFailedAt = -math.huge
local shot: any = nil
local playedRound: any = nil
local seenRound: any = nil
local seenAt = 0
local ui: any = nil
local skipHeldSince: number? = nil
local fadeToken = 0
local glare: any = nil -- the arrival's glare while it falls away (Glare's state; see stopGlare)
local lastStats: any = nil
local lastTierCheck = 0

-- Helpers ----------------------------------------------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

-- the disc's climb: the lift takes the weight, then a steady climb still moving at the white-out (carried on past 1)
local function riseEase(u: number): number
	if u <= 0 then
		return 0
	elseif u >= 1 then
		return u
	end
	return 2 * u * u - u * u * u
end

local function tier(): string
	local t = localPlayer:GetAttribute("DetailTier")
	if t == "Low" or t == "Medium" or t == "High" then
		return t
	end
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Medium" else "High"
end

local function standInLimit(): number
	local n = tonumber(LaunchCfg.StandIns) or 8
	local t = tier()
	if t == "Low" then
		n = math.floor(n * 0.4)
	elseif t == "Medium" then
		n = math.floor(n * 0.75)
	end
	return math.max(0, n)
end

-- the shader tier (DetailController): "Off" is the player's own "Shaders: Off", which switches bloom off
local function shaderTier(): string
	local t = localPlayer:GetAttribute("ShaderTier")
	return if type(t) == "string" then t else "High"
end

-- the rooms' lighting for this shot: PROFILES with the flat fill this client needs (see FILL)
local function shotProfiles(): { [string]: any }
	local name = "Full"
	if IS_STUDIO then
		local forced = localPlayer:GetAttribute("LS_LaunchFill")
		if forced == "Full" or forced == "Part" or forced == "None" then
			name = forced
		end
	end
	local fill = FILL[name]
	local out = {}
	for room, profile in pairs(PROFILES) do
		local p = table.clone(profile)
		if fill and fill[room] then
			for key, value in pairs(fill[room]) do
				p[key] = value
			end
		end
		out[room] = p
	end
	return out
end

local function reducedMotion(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

local function arenaCentre(): Vector3
	local arena = workspace:FindFirstChild("Arena")
	local centre = arena and arena:GetAttribute("Center")
	if typeof(centre) == "Vector3" then
		return centre
	end
	return ArenaLayout.Center or Vector3.zero
end

-- standing on the plate ring: LaunchController's test (the layout's PlinthRingRadius, or the ring measured from the
-- plates in the place); without that controller, the layout's radius alone
local RING_TOLERANCE = 8
local function onPlateRing(position: Vector3): boolean
	local launch = Controllers and Controllers.LaunchController
	if launch and type(launch.onRing) == "function" then
		local ok, result = pcall(launch.onRing, position)
		if ok then
			return result == true
		end
	end
	local ring = tonumber((ArenaLayout :: any).PlinthRingRadius)
	if not ring then
		return false
	end
	local centre = arenaCentre()
	return math.abs(Vector2.new(position.X - centre.X, position.Z - centre.Z).Magnitude - ring) <= RING_TOLERANCE
end

-- how many plates the arena has = how many cases the hall gets
local function plateCount(): number
	local layout = ArenaLayout :: any
	local n = tonumber(layout.PlinthCount)
	if not n and type(layout.Plates) == "table" and #layout.Plates > 0 then
		n = #layout.Plates
	end
	return math.max(1, math.floor(n or tonumber(Config.Round.MaxContenders) or 24))
end

-- the case of the plate a contender stands on (or nil when they're not on the plate ring yet). Plate k (from 0) of n
-- stands at PlinthOffsetDeg + k * 360 / n degrees, clockwise from north. The offset comes off before the rounding:
-- on Map 1 (3.75 degrees, half a step of 48) the bare bearing sits exactly on the edge between two cases.
local function slotOf(position: Vector3): number?
	if not onPlateRing(position) then
		return nil
	end
	local centre = arenaCentre()
	local n = #set.hall.slots
	local first = tonumber((ArenaLayout :: any).PlinthOffsetDeg) or 0
	local deg = (math.deg(math.atan2(position.X - centre.X, -(position.Z - centre.Z))) - first) % 360
	-- the plate first (a whole number, well away from any rounding edge), then its case: with more plates than
	-- cases (Map 1: 48 and 24) plates 0 and 1 share case 1, plates 2 and 3 case 2, and so on
	local plates = math.max(n, plateCount())
	local plate = math.floor(deg / (360 / plates) + 0.5) % plates
	return (math.floor(plate * n / plates) % n) + 1
end

-- your own field of view (Settings), as CameraController starts from it: the shot ends on it and hands it over
local function ownFov(): number
	local settings = ClientState.settings
	return math.clamp(tonumber(settings and settings.fov) or Config.Camera.BaseFov, 40, 110)
end

local function ringDistance(a: number, b: number, n: number): number
	local d = math.abs(a - b) % n
	return math.min(d, n - d)
end

-- The set ---------------------------------------------------------------------------------------------------------------

local function ensureSet()
	if building or os.clock() - buildFailedAt < 30 then
		return
	end
	if set and (set.detail == tier() or shot) then
		return
	end
	building = true
	task.spawn(function()
		local ok, result = pcall(Set.build, { detail = tier(), slots = math.min(plateCount(), MAX_CASES) })
		if ok and result then
			if set and not shot then
				set.model:Destroy()
			end
			if not shot then
				set = result
			else
				result.model:Destroy()
			end
		else
			buildFailedAt = os.clock()
			warn("[LaunchIntroController] the set failed to build: " .. tostring(result))
		end
		building = false
	end)
end

-- The screen ------------------------------------------------------------------------------------------------------------

local function frame(name: string, parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = BLACK
	for k, v in pairs(props) do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function buildUi()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("LaunchShot")
	if old then
		old:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "LaunchShot"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 30
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	pcall(function()
		screen.ScreenInsets = Enum.ScreenInsets.None
	end)
	local root = frame("Root", screen, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local top = frame("BarTop", root, { Size = UDim2.fromScale(1, 0), ZIndex = 2 })
	local bottom = frame("BarBottom", root, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0), ZIndex = 2 })
	local fade = frame("Fade", root, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 })
	-- keyboard / gamepad: "HOLD SPACE TO SKIP" over the bottom bar, with a thin fill line
	local prompt = frame("Prompt", root, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -16),
		Size = UDim2.fromOffset(260, 26), BackgroundTransparency = 1, ZIndex = 4, Visible = false })
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 1, -4)
	text.FontFace = Theme.Fonts.Heading
	text.TextSize = 15
	text.TextColor3 = Theme.Colors.Text
	text.TextTransparency = 0.3
	text.TextXAlignment = Enum.TextXAlignment.Right
	text.Text = "HOLD SPACE TO SKIP"
	text.ZIndex = 4
	text.Parent = prompt
	local line = frame("Line", prompt, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0, 120, 0, 2), BackgroundColor3 = Theme.Colors.Text, BackgroundTransparency = 0.8, ZIndex = 4 })
	local fill = frame("Fill", line, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.Accent, ZIndex = 4 })
	-- touch: a HOLD TO SKIP button (InputCheck: gui LaunchShot.Root.Skip)
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	-- (this screen is drawn edge to edge, ScreenInsets None: the button stays in from a phone's rounded corner,
	-- camera cut-out and bottom gesture strip; it was 18 and 14 px from the physical edge)
	skip.Position = UDim2.new(1, -64, 1, -34)
	skip.Size = UDim2.fromOffset(136, 40)
	skip.AutoButtonColor = false
	skip.BackgroundColor3 = Theme.Colors.Panel
	skip.BackgroundTransparency = 0.45
	skip.BorderSizePixel = 0
	skip.FontFace = Theme.Fonts.Heading
	skip.TextSize = 15
	skip.TextColor3 = Theme.Colors.Text
	skip.Text = "HOLD TO SKIP"
	skip.Selectable = false
	skip.Visible = false
	skip.ZIndex = 4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerPill
	corner.Parent = skip
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.Text
	stroke.Transparency = 0.7
	stroke.Parent = skip
	local skipFill = frame("Fill", skip, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.Accent,
		BackgroundTransparency = 0.35, ZIndex = 3 })
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = Theme.CornerPill
	fillCorner.Parent = skipFill
	skip.Parent = root
	skip.InputBegan:Connect(function(io: InputObject)
		if shot and (io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1) then
			skipHeldSince = os.clock()
		end
	end)
	skip.InputEnded:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			skipHeldSince = nil
		end
	end)
	screen.Parent = playerGui
	ui = { screen = screen, root = root, top = top, bottom = bottom, fade = fade, prompt = prompt, promptText = text,
		promptFill = fill, skip = skip, skipFill = skipFill }
end

-- letterbox k: 1 = 2.39:1, 0 = full frame
local function setLetterbox(k: number)
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local bar = 0
	if v.X > 1 and v.Y > 1 then
		bar = math.max(0, (1 - (v.X / v.Y) / 2.39) / 2) * clamp01(k)
	end
	ui.top.Size = UDim2.fromScale(1, bar)
	ui.bottom.Size = UDim2.fromScale(1, bar)
end

local function setFade(color: Color3, alpha: number)
	ui.fade.BackgroundColor3 = color
	ui.fade.BackgroundTransparency = 1 - clamp01(alpha)
end

-- The arrival's glare that is falling away now (Glare's state), if any. It writes Lighting's exposure and bloom on top
-- of the day cycle's: stopGlare takes them off at once.
local function stopGlare()
	local g = glare
	if g then
		glare = nil
		local ok, err = pcall(Glare.finish, g)
		if not ok then
			warn("[LaunchIntroController] the glare couldn't be taken off: " .. tostring(err))
		end
	end
end

-- After a shot that did not hand off (a skip, a preview, an early end): the black gives way to the game.
local function fadeAway(color: Color3, from: number, duration: number)
	fadeToken += 1
	local token = fadeToken
	stopGlare()
	ui.prompt.Visible = false
	ui.skip.Visible = false
	setLetterbox(0)
	setFade(color, from)
	ui.screen.Enabled = true
	task.spawn(function()
		local t0 = os.clock()
		while token == fadeToken do
			local k = (os.clock() - t0) / duration
			if k >= 1 then
				break
			end
			setFade(color, from * (1 - smooth(k)))
			RunService.RenderStepped:Wait()
		end
		if token == fadeToken then
			setFade(color, 0)
			if not shot then
				ui.screen.Enabled = false
			end
		end
	end)
end

-- After the hand-off: the sun's glare falls away as the eyes adjust (Glare). `from` is the cover's alpha at the cut,
-- `sky` the shot's Glare.sky table (nil: read now), `fresh` true straight after a shot. The cover is this screen's
-- Fade frame; the over-bright picture under it is Glare's (not with "Shaders: Off": a plain fade of the cover).
local function glareAway(from: number, sky: any, fresh: boolean)
	fadeToken += 1
	local token = fadeToken
	stopGlare()
	ui.prompt.Visible = false
	ui.skip.Visible = false
	setLetterbox(0)
	local arena = Controllers and Controllers.ArenaController
	local g = Glare.begin({
		from = from,
		sky = sky,
		fresh = fresh,
		bloom = shaderTier() ~= "Off",
		getLook = if arena and type(arena.getLook) == "function" then arena.getLook else nil,
	})
	glare = g
	local color: Color3 = g.color
	local cover = clamp01(from)
	-- the first frame now, in the frame of the cut (the lighting has just been given back: the glare goes on top)
	local live, alpha, tint = pcall(Glare.update, g, 0)
	if live then
		color, cover = tint, alpha
	else
		-- (the glare broke: whatever it wrote comes off now, and the cover fades by itself)
		warn("[LaunchIntroController] the glare failed: " .. tostring(alpha))
		stopGlare()
	end
	setFade(color, cover)
	ui.screen.Enabled = true
	task.spawn(function()
		local t0 = os.clock()
		while token == fadeToken and (glare == g or not live) do
			local dt = RunService.RenderStepped:Wait()
			if token ~= fadeToken or (live and glare ~= g) then
				break
			end
			if live then
				local fine, a, c, done = pcall(Glare.update, g, dt)
				if not fine then
					warn("[LaunchIntroController] the glare failed: " .. tostring(a))
					live = false
					if glare == g then
						stopGlare()
					end
					t0 = os.clock()
				elseif done then
					break
				else
					color, cover = c, a
					setFade(color, cover)
				end
			else
				local k = (os.clock() - t0) / 0.6
				if k >= 1 then
					break
				end
				setFade(color, cover * (1 - smooth(k)))
			end
		end
		if glare == g then
			stopGlare()
		end
		if token == fadeToken then
			setFade(color, 0)
			if not shot then
				ui.screen.Enabled = false
			end
		end
	end)
end

local function skipText(): string
	local ok, key = pcall(function()
		if Input.isGamepad() then
			return Glyphs.forKey(Enum.KeyCode.ButtonA)
		end
		return Glyphs.forKey(Enum.KeyCode.Space)
	end)
	return "HOLD " .. (if ok and type(key) == "string" then key else "SPACE") .. " TO SKIP"
end

-- Everything that shows the game's own UI goes dark for the shot (and comes back exactly as it was).
local function holdGuis(s)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, name in ipairs(HIDE_GUIS) do
		local g = playerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then
			local wantOn = name == "Menu" and ClientState.menuOpen == true
			if wantOn then
				if not g.Enabled and s.guis[g] then
					g.Enabled = true
				end
			elseif g.Enabled then
				g.Enabled = false
				s.guis[g] = true
			end
		end
	end
	if s.touchControls == nil then
		local ok, was = pcall(function()
			return GuiService.TouchControlsEnabled
		end)
		if ok then
			s.touchControls = was
			pcall(function()
				GuiService.TouchControlsEnabled = false
			end)
		else
			s.touchControls = false
		end
	end
	-- Roblox's chat window and player list (they covered the corners of the letterboxed shot): off once, and back
	-- on in releaseGuis only where this shot switched them off
	if s.coreGuis == nil then
		s.coreGuis = {}
		for _, kind in ipairs(HIDE_CORE) do
			local ok, was = pcall(function()
				return StarterGui:GetCoreGuiEnabled(kind)
			end)
			if ok and was == true then
				local done = pcall(function()
					StarterGui:SetCoreGuiEnabled(kind, false)
				end)
				if done then
					table.insert(s.coreGuis, kind)
				end
			end
		end
	end
end

local function releaseGuis(s)
	for g in pairs(s.guis) do
		if g.Parent then
			g.Enabled = true
		end
	end
	table.clear(s.guis)
	if s.touchControls == true then
		pcall(function()
			GuiService.TouchControlsEnabled = true
		end)
	end
	if s.coreGuis then
		local chatBack = false
		for _, kind in ipairs(s.coreGuis) do
			pcall(function()
				StarterGui:SetCoreGuiEnabled(kind, true)
			end)
			chatBack = chatBack or kind == Enum.CoreGuiType.Chat
		end
		s.coreGuis = nil
		if chatBack then
			-- Switching chat back on reopened its window over the top left at every hand-off, and its system line stayed
			-- into the round. It comes back closed: the chat button in Roblox's top bar (or the / key) opens it.
			task.spawn(function()
				for _ = 1, 3 do
					pcall(function()
						StarterGui:SetCore("ChatActive", false)
					end)
					task.wait(0.2)
				end
			end)
		end
	end
end

-- Lighting --------------------------------------------------------------------------------------------------------------

local function findEffect(className: string, name: string?): Instance?
	if name then
		local named = Lighting:FindFirstChild(name)
		if named and named:IsA(className) then
			return named
		end
		if className == "ColorCorrectionEffect" then
			return nil -- only the arena's own grade, never another controller's tint
		end
	end
	return Lighting:FindFirstChildOfClass(className)
end

local function takeLighting(s)
	local snap = { props = {}, effects = {}, created = {} }
	for _, p in ipairs(LIGHT_PROPS) do
		snap.props[p] = (Lighting :: any)[p]
	end
	local function grab(className: string, name: string?, create: boolean): any
		local inst = findEffect(className, name)
		if not inst then
			if not create then
				return nil
			end
			inst = Instance.new(className)
			inst.Name = "LaunchShot" .. className
			inst.Parent = Lighting
			table.insert(snap.created, inst)
			return inst
		end
		local values = {}
		for _, p in ipairs(EFFECT_PROPS[className]) do
			values[p] = (inst :: any)[p]
		end
		table.insert(snap.effects, { inst = inst, values = values })
		return inst
	end
	s.fx = {
		atmosphere = grab("Atmosphere", nil, true),
		bloom = grab("BloomEffect", "Bloom", true),
		grade = grab("ColorCorrectionEffect", "ArenaGrade", true),
		rays = grab("SunRaysEffect", "SunRays", false),
		dof = grab("DepthOfFieldEffect", "DepthOfField", false),
	}
	s.lighting = snap
end

local function giveLightingBack(s)
	local snap = s.lighting
	if not snap then
		return
	end
	for p, v in pairs(snap.props) do
		pcall(function()
			(Lighting :: any)[p] = v
		end)
	end
	for _, e in ipairs(snap.effects) do
		for p, v in pairs(e.values) do
			pcall(function()
				e.inst[p] = v
			end)
		end
	end
	for _, inst in ipairs(snap.created) do
		inst:Destroy()
	end
	s.lighting = nil
end

-- white 0..1: the flood of light at the end of the rise. s.flood (Glare.sky) says how far it goes: 1 by day (the
-- set whites out, as it always did), less at dawn or under cloud, and under 0 at night, when the light falls away
-- instead and the cut passes through the dark.
local function writeLighting(s, p, white: number)
	local flood = white * (tonumber(s.flood) or 1)
	local glow = math.max(flood, 0)
	Lighting.Ambient = p.Ambient
	Lighting.OutdoorAmbient = p.Ambient
	Lighting.Brightness = 0
	Lighting.ExposureCompensation = p.Exposure + 2.4 * flood
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = p.EnvSpecular
	Lighting.ColorShift_Top = BLACK
	Lighting.ColorShift_Bottom = BLACK
	-- no sky occlusion in a closed set: the ambient applies at once everywhere, instead of waiting for the engine's
	-- lighting voxels round a camera that has just jumped thousands of studs (seen as seconds of black rooms)
	if Lighting.GlobalShadows then
		Lighting.GlobalShadows = false
	end
	local fx = s.fx
	if fx.atmosphere then
		fx.atmosphere.Density = p.AtmDensity
		fx.atmosphere.Offset = 0
		fx.atmosphere.Color = p.AtmColor
		fx.atmosphere.Decay = p.AtmDecay
		fx.atmosphere.Glare = 0
		fx.atmosphere.Haze = 0
	end
	-- "Shaders: Off" has no bloom: the flood then comes from the exposure, a stronger grade and the cover
	local bloomOn = s.bloom ~= false
	if fx.bloom then
		fx.bloom.Enabled = bloomOn
		fx.bloom.Intensity = p.BloomIntensity + 1.4 * glow
		fx.bloom.Size = math.floor(p.BloomSize + 16 * glow + 0.5)
		fx.bloom.Threshold = math.max(0.2, p.BloomThreshold - 0.8 * glow)
	end
	if fx.grade then
		fx.grade.Enabled = true
		fx.grade.Brightness = (if bloomOn then 0.25 else 0.45) * flood
		fx.grade.Contrast = p.GradeContrast
		fx.grade.Saturation = p.GradeSaturation - 0.3 * white
		fx.grade.TintColor = p.GradeTint
	end
	if fx.rays then
		fx.rays.Intensity = 0
	end
	if fx.dof then
		fx.dof.Enabled = false
	end
end

local function blendLighting(s, name: string, dt: number, snapTo: boolean, white: number)
	local target = (s.profiles or PROFILES)[name]
	local cur = s.profile
	if snapTo or not cur then
		cur = table.clone(target)
	else
		local k = 1 - math.exp(-5 * dt)
		for key, v in pairs(target) do
			local c = cur[key]
			if typeof(v) == "Color3" then
				cur[key] = (c :: Color3):Lerp(v, k)
			else
				cur[key] = c + (v - c) * k
			end
		end
	end
	s.profile = cur
	writeLighting(s, cur, white)
end

-- Sound -------------------------------------------------------------------------------------------------------------------

local function playSound(s, key: string, opts: { [string]: any }?): Sound?
	local entry = Sounds[key]
	if type(entry) ~= "table" or type(entry.ids) ~= "table" or #entry.ids == 0 then
		return nil
	end
	local o = opts or {}
	local sound = Instance.new("Sound")
	sound.Name = "LaunchShot_" .. key
	sound.SoundId = entry.ids[1]
	sound.Volume = (entry.volume or 0.5) * (o.volume or 1)
	sound.PlaybackSpeed = o.pitch or 1
	sound.Looped = o.looped == true
	local group = SoundService:FindFirstChild(entry.group or "SFX")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
	if o.region then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(o.region[1], o.region[2])
	end
	if o.reverb then
		local r = Instance.new("ReverbSoundEffect")
		r.DecayTime = o.reverb
		r.Density = 0.9
		r.Diffusion = 0.9
		r.WetLevel = -4
		r.DryLevel = -1
		r.Parent = sound
	end
	sound.Parent = SoundService
	sound:Play()
	table.insert(s.sounds, { sound = sound, base = sound.Volume, key = o.tag or key })
	return sound
end

-- volume envelope of a running shot sound by its tag (0..1 of its base volume)
local function soundLevel(s, tag: string, level: number)
	for _, e in ipairs(s.sounds) do
		if e.key == tag and e.sound.Parent then
			e.sound.Volume = e.base * clamp01(level)
		end
	end
end

local function cue(s, name: string, t: number, at: number, fn: () -> ())
	if not s.fired[name] and t >= at then
		s.fired[name] = true
		-- a late join doesn't replay what everyone else heard long ago
		if t - at < 1.5 then
			fn()
		end
	end
end

-- The contenders ----------------------------------------------------------------------------------------------------------

-- the other contenders' cases (their plates' bearings where known) and their stand-ins: copies of the nearest
-- avatars, plain figures for the rest
local function assignSlots(s)
	if s.assigned then
		return
	end
	s.assigned = true
	local slots = set.hall.slots
	local n = #slots
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local mine = if s.preview then 1 else ((root and root:IsA("BasePart") and slotOf(root.Position)) or 1)
	s.mySlot = mine
	local taken = { [mine] = true }
	local pending = {}
	for _, entry in ipairs(s.contenders) do
		local k = entry.fixedSlot
		if not k and entry.player then
			local c = entry.player.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			k = if r and r:IsA("BasePart") then slotOf(r.Position) else nil
		end
		if k and not taken[k] then
			taken[k] = true
			entry.slot = k
		else
			table.insert(pending, entry)
		end
	end
	-- the rest fill the free cases nearest yours, alternating sides
	for _, entry in ipairs(pending) do
		for step = 1, n do
			local a, b = (mine - 1 + step) % n + 1, (mine - 1 - step) % n + 1
			if not taken[a] then
				taken[a] = true
				entry.slot = a
				break
			elseif not taken[b] then
				taken[b] = true
				entry.slot = b
				break
			end
		end
	end
	table.sort(s.contenders, function(x, y)
		return ringDistance(x.slot or mine, mine, n) < ringDistance(y.slot or mine, mine, n)
	end)
	local limit = standInLimit()
	local lit = 0
	for i, entry in ipairs(s.contenders) do
		if entry.slot then
			local figure = entry.copy
			if not figure and i <= limit and entry.player then
				local ok, made = pcall(Figures.copy, entry.player.Character)
				figure = if ok then made else nil
			end
			if not figure then
				figure = Figures.plain(entry.seed)
			end
			entry.figure = figure
			local home = slots[entry.slot]
			figure.place(home.cf * CFrame.new(0, home.riserTop, 0))
			figure.model.Parent = set.model
			pcall(figure.secure)
			pcall(figure.play, IDLE_ID)
			-- each rides a few tenths of a second ahead of or behind the clock, set by its case
			entry.delay = 0.5 * math.sin(entry.slot * 2.3999)
			entry.pitch = 0.08 + 0.18 * (0.5 + 0.5 * math.sin(entry.slot * 1.7))
			entry.yaw = 0.35 * math.sin(entry.slot * 3.1)
		end
	end
	for k, slot in ipairs(slots) do
		local occupied = k == mine or taken[k] == true
		slot.strip.Material = if occupied then Enum.Material.Neon else Enum.Material.SmoothPlastic
		slot.strip.Color = if occupied then LIT else UNLIT
		local near = occupied and ringDistance(k, mine, n) <= 2
		if near and k ~= mine then
			lit += 1
		end
		slot.light.Enabled = near and (k == mine or lit <= 2)
		slot.light.Shadows = k == mine and set.detail == "High"
	end
	-- the camera passes beside your case: the wall units there step aside
	for _, p in ipairs(slots[mine].units) do
		p.LocalTransparencyModifier = 1
	end
	set.hall.gantryAnchor.CFrame = slots[mine].cf * CFrame.new(0, 12.9, -10.4)
end

local function updateOthers(s, t: number)
	local plan, k = s.plan, s.scale
	local riseA, riseB = plan.rise[1] * k, plan.rise[2] * k
	for _, entry in ipairs(s.contenders) do
		local figure = entry.figure
		if figure and entry.slot then
			local slot = set.hall.slots[entry.slot]
			local u = (t - riseA - entry.delay) / math.max(0.1, riseB - riseA)
			local y = plan.riseHeight * riseEase(math.max(0, u))
			slot.riser.CFrame = slot.riserCF + Vector3.yAxis * y
			figure.place(slot.cf * CFrame.new(0, slot.riserTop + y, 0))
			figure.look(entry.pitch, entry.yaw)
		end
	end
end

-- The shot ---------------------------------------------------------------------------------------------------------------

local function stageAt(s, t: number): string
	local plan, k = s.plan, s.scale
	if t < plan.dip * k then
		return "Red"
	elseif plan.cases and t < plan.rise[1] * k then
		return "Cases"
	end
	return "Rise"
end

local function setStageLights(s, stage: string)
	if s.lightStage == stage then
		return
	end
	s.lightStage = stage
	local red = set.red.lights
	local onRed = stage == "Red"
	red.key.Enabled = onRed
	red.roof.Enabled = onRed
	red.fill.Enabled = onRed
	red.lamp.Enabled = onRed
	for _, l in ipairs(red.pits) do
		l.Enabled = onRed
	end
	local hall = set.hall.lights
	hall.hub.Enabled = not onRed
	hall.gantry.Enabled = stage == "Cases"
	hall.rider.Enabled = stage == "Rise"
	hall.riderFill.Enabled = stage == "Rise"
end

-- The picture at time t (seconds from the call): camera, stand-ins, discs and lights. Pure in t, so a late join or a
-- frozen preview shows exactly what everyone else sees at that moment.
local function evaluate(s, t: number): (CFrame, number, string)
	local plan, k = s.plan, s.scale
	local red, hall = set.red, set.hall
	local up = Vector3.yAxis
	local dip = plan.dip * k
	local stage = stageAt(s, t)
	if t >= dip - 0.3 or stage ~= "Red" then
		assignSlots(s)
	end
	setStageLights(s, stage)
	if stage == "Red" then
		local O = red.origin
		local e = smooth(t / dip)
		-- the lift: still, then it takes you up the shaft toward the lens
		local liftA = plan.lift * k
		local lu = clamp01((t - liftA) / math.max(0.1, dip - liftA))
		local liftY = 7.2 * lu ^ 2.2
		red.lift.CFrame = red.liftHome + up * liftY
		s.me.place(O * CFrame.new(0, red.liftTop + liftY, 0) * CFrame.Angles(0, math.pi, 0))
		s.me.look(0.85 * smooth((t - plan.look * k) / 1.0), 0)
		s.me.fade(0)
		-- the camera: over the shaft's mouth, down through the far half of the hex (its top vertex at the top of the
		-- frame, its sides at the edges) at you on the disc; a slow push in and a slight drift round the shaft
		local drift = if s.reduced then 0 else math.rad(lerp(-4, 3, e))
		local eye = CFrame.Angles(0, drift, 0) * Vector3.new(0, lerp(19.4, 18.2, e), lerp(4.3, 3.7, e))
		local target = Vector3.new(0, lerp(2.4, 2.8, e) + liftY * 0.6, lerp(-4.2, -3.4, e) + liftY * 0.35)
		return CFrame.lookAt(O * eye, O * target), lerp(56, 50, e), stage
	end
	local slot = hall.slots[s.mySlot]
	local S = slot.cf
	if stage == "Cases" then
		local ca, cb = plan.cases[1] * k, plan.cases[2] * k
		local e = smooth((t - ca) / (cb - ca))
		slot.riser.CFrame = slot.riserCF
		s.me.place(S * CFrame.new(0, slot.riserTop, 0))
		s.me.look(0.04, 0.65 * smooth((t - ca - 0.5) / 1.0))
		s.me.fade(0)
		updateOthers(s, t)
		-- at face height just outside your glass, looking past you along the row; then it pulls back round the hall
		local eye = Vector3.new(3.6, 5.4, -4.6):Lerp(CASE_END_EYE, e)
		local target = Vector3.new(-12, 4.8, -0.5):Lerp(Vector3.new(0, slot.riserTop + 3.4, 0), e)
		return CFrame.lookAt(S * eye, S * target), lerp(46, CASE_END_FOV, e), stage
	end
	-- the rise: your disc climbs the pole while the camera circles you and drops low behind you; for the last part of
	-- the climb it spirals in over your right shoulder and into your own eyes, and the rest is first person
	local riseA, riseB = plan.rise[1] * k, plan.rise[2] * k
	local riseSpan = math.max(0.1, riseB - riseA)
	local u = clamp01((t - riseA) / riseSpan)
	local y = plan.riseHeight * riseEase((t - riseA) / riseSpan)
	slot.riser.CFrame = slot.riserCF + up * y
	local feetY = slot.riserTop + y
	s.me.place(S * CFrame.new(0, feetY, 0))
	s.me.look(lerp(0.04, 0.3, smooth(u * 2)), lerp(if plan.cases then 0.65 else 0, 0, smooth(u * 3)))
	updateOthers(s, t)
	local r0, h0, fov0
	if plan.start then
		r0, h0, fov0 = plan.start.r, plan.start.h, plan.start.fov
	else
		local flat = Vector2.new(CASE_END_EYE.X, CASE_END_EYE.Z)
		r0, h0, fov0 = flat.Magnitude, CASE_END_EYE.Y - slot.riserTop, CASE_END_FOV
	end
	-- into your eyes: 0 on the circle, 1 in first person. The circle's turn ends as the camera arrives.
	local eyesA, eyesB = plan.eyes[1], plan.eyes[2]
	local e = smooth((u - eyesA) / (eyesB - eyesA))
	local phi = math.rad(lerp(plan.phi[1], plan.phi[2], smooth(u / eyesB)))
	if s.reduced then
		-- Reduce Motion: no circling and no travel into the head. The camera keeps its first bearing (going low, to look
		-- up at your whole body), and a short dip to black (stepShot) cuts to your eyes.
		phi = math.rad(plan.phi[1])
		e = if u >= (eyesA + eyesB) / 2 then 1 else 0
	end
	local lowBy = eyesA + 0.02 - 0.3 -- (the camera is down as the spiral starts)
	local r = lerp(r0, 8.0, smooth(u / 0.3))
	r = lerp(r, 7.4, smooth((u - 0.3) / lowBy))
	local h = lerp(h0, 3.0, smooth(u / 0.3))
	h = lerp(h, plan.low, smooth((u - 0.3) / lowBy))
	local circleEye = Vector3.new(math.sin(phi) * r, feetY + h, -math.cos(phi) * r)
	local circleTarget = Vector3.new(0, feetY + lerp(3.4, 2.9, smooth((u - 0.3) / lowBy)), 0)
	-- first person: at your eyes, facing the hall's centre as your plinth faces the Spire. You look up the pole at the
	-- roof's lights and the opening, and your eyes come level (the view the hand-off gives) under the flood of light.
	local levelA, levelB = plan.level[1] * k, plan.level[2] * k
	local gaze = if s.reduced then math.min(plan.gaze, 30) else plan.gaze
	local pitch = math.rad(lerp(gaze, FACE_PITCH, smooth((t - levelA) / math.max(0.05, levelB - levelA))))
	local ownEye = Vector3.new(0, feetY + s.me.eye, 0)
	local ownTarget = ownEye + Vector3.new(0, math.sin(pitch), -math.cos(pitch)) * EYE_AHEAD
	local eye = circleEye:Lerp(ownEye, e)
	local target = circleTarget:Lerp(ownTarget, e)
	-- your stand-in is not drawn once the lens comes near it (gone 2 studs behind its head)
	s.me.fade(smooth((e - 0.4) / 0.3))
	local keyAt = S * Vector3.new(0, feetY + 9, -2.2)
	hall.riderAnchor.CFrame = CFrame.lookAt(keyAt, S * Vector3.new(0, feetY + 3, 0))
	-- your case light goes out behind you once you've left it
	slot.light.Enabled = u < 0.25
	-- the field of view ends on your own setting: nothing changes at the hand-off
	return CFrame.lookAt(S * eye, S * target), lerp(lerp(fov0, 61, smooth(u)), ownFov(), e), stage
end

local function shotTime(s): (number, boolean)
	if s.preview and IS_STUDIO then
		local f = localPlayer:GetAttribute("LS_LaunchFreeze")
		if type(f) == "number" then
			return f, true
		end
	end
	return now() - s.callAt, false
end

-- the shot's own sounds (the arena's ambience is muted and the music ducked meanwhile)
local function updateSound(s, t: number)
	local plan, k = s.plan, s.scale
	local dip, riseA, riseB = plan.dip * k, plan.rise[1] * k, plan.rise[2] * k
	cue(s, "room", t, 0, function()
		playSound(s, "BorderHum", { volume = 0.45, pitch = 0.62, looped = true, tag = "room" })
	end)
	soundLevel(s, "room", 1 - smooth((t - dip + 0.25) / 0.3))
	cue(s, "lift", t, plan.lift * k, function()
		playSound(s, "PlateLock", { volume = 1.1, pitch = 0.8 })
	end)
	if plan.cases then
		cue(s, "heart", t, plan.cases[1] * k, function()
			playSound(s, "Heartbeat", { volume = 1.6, looped = true, tag = "heart" })
		end)
		soundLevel(s, "heart", 1 - smooth((t - riseA - 1) / 2))
	end
	cue(s, "whir", t, riseA, function()
		local len = (riseB - riseA) * 0.92
		playSound(s, "PlateRise", { volume = 0.7, pitch = 0.92, region = { math.max(0, 9.4 - len - 0.6), 9.35 },
			tag = "whir" })
	end)
	cue(s, "tone", t, riseA, function()
		playSound(s, "RollCallToneSoft", { volume = 0.7, pitch = 0.82, reverb = 4, tag = "tone" })
	end)
	cue(s, "swell", t, plan.white * k - 0.5, function()
		playSound(s, "RollCallTone", { volume = 0.45, pitch = 0.9, reverb = 3, tag = "swell" })
	end)
	soundLevel(s, "swell", smooth((t - plan.white * k + 0.5) / 0.9))
	local audio = Controllers and Controllers.AudioController
	if audio and type(audio.duck) == "function" and os.clock() >= (s.duckAt or 0) then
		s.duckAt = os.clock() + 0.4
		pcall(audio.duck, 0.55, 0.0, 0.7)
	end
end

local finish: (reason: string) -> ()

-- your plate is under you (the server has placed you) - the white holds a moment for a late placement
local function placedOnPlate(): boolean
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and root.Anchored and set ~= nil and slotOf(root.Position) ~= nil
end

local function stepShot(dt: number)
	local s = shot
	s.lastRender = os.clock()
	local t, frozen = shotTime(s)
	local plan, k = s.plan, s.scale
	local cam = workspace.CurrentCamera
	-- skip (after the first moment; it only moves your own camera)
	local sinceStart = os.clock() - s.startedAt
	if IS_STUDIO and localPlayer:GetAttribute("LS_LaunchSkipTest") == true then
		-- (Studio tests: a completed hold, for a window that can't take key presses)
		localPlayer:SetAttribute("LS_LaunchSkipTest", nil)
		skipHeldSince = os.clock() - SKIP_HOLD - 0.01
	end
	if skipHeldSince and sinceStart > 0.8 and not s.preview then
		local held = os.clock() - (skipHeldSince :: number)
		if held >= SKIP_HOLD then
			finish("skip")
			return
		end
	end
	local holdK = if skipHeldSince then clamp01((os.clock() - (skipHeldSince :: number)) / SKIP_HOLD) else 0
	-- the hand-off: first person on your plate (the cover closes and holds up to 1.5 s for a late placement)
	local handoffT = plan.handoff * k
	if not frozen and t >= handoffT then
		if s.preview then
			if t >= handoffT + 0.4 then
				finish("preview")
				return
			end
		elseif placedOnPlate() or t >= handoffT + 1.5 then
			finish("handoff")
			return
		end
	end
	if not frozen and s.copyQueue and #s.copyQueue > 0 and not s.assigned then
		-- copies of the other avatars, two a frame, while the red room plays
		for _ = 1, 2 do
			local entry = table.remove(s.copyQueue, 1)
			if not entry then
				break
			end
			local ok, made = pcall(Figures.copy, entry.player and entry.player.Character)
			if ok and made then
				entry.copy = made
			end
		end
	end
	local camCF, fov, stage = evaluate(s, t)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = camCF
	cam.FieldOfView = fov
	-- light: snap at the cuts (behind black), blend otherwise; the arrival floods the exposure
	local whiteA = plan.white * k
	-- the arrival, one smooth rise: the light from above floods first (exposure and bloom, as far as the hour's sky
	-- allows: s.flood), then the sky's cover comes over the frame, up to its peak (under 1: never a hard white frame)
	-- at the hand-off. The cut onto your plinth hides under it, and Glare takes the same cover down from there.
	local span = math.max(0.1, handoffT - 0.1 - whiteA)
	local white = smooth((t - whiteA) / span)
	local cover = s.sky.peak * smooth((t - whiteA - 0.35 * span) / (0.65 * span))
	if t > handoffT then
		-- a late placement (or a preview's last moment): the cover closes while the shot waits
		cover = lerp(cover, 1, smooth((t - handoffT) / 0.25))
	end
	s.cover = cover
	local cut = s.profileStage == nil or (s.profileStage == "Red" and stage ~= "Red") -- behind the black
	blendLighting(s, stage, if frozen then 0 else dt, frozen or cut, white)
	s.profileStage = stage
	-- the screen: fades, the letterbox, the skip prompt
	local dip = plan.dip * k
	local black = 0
	if t - s.joinT < 0.6 then
		black = 1 - smooth((t - s.joinT - 0.3) / 0.3) -- black a moment while the set settles in, then fade in
	end
	if t > dip - 0.1 and t < dip + 0.35 then
		black = math.max(black, if t < dip then smooth((t - dip + 0.1) / 0.1) else 1 - smooth((t - dip - 0.06) / 0.28))
	end
	local riseA = plan.rise[1] * k
	if s.reduced and stage == "Rise" then
		-- Reduce Motion: the cut into your own eyes (evaluate) passes through a short dip to black
		local riseSpan = math.max(0.1, plan.rise[2] * k - riseA)
		local d = t - (riseA + riseSpan * (plan.eyes[1] + plan.eyes[2]) / 2)
		if d > -0.2 and d < 0.4 then
			black = math.max(black, if d < 0 then smooth((d + 0.2) / 0.2) else 1 - smooth((d - 0.05) / 0.3))
		end
	end
	if cover > 0 then
		setFade(s.sky.color, cover)
	else
		setFade(BLACK, black)
	end
	setLetterbox(if stage == "Rise" then 1 - smooth((t - riseA) / (2.5 * k)) else 1)
	local touch = Input.isTouch()
	local showSkip = not s.preview and sinceStart > 1.0 and t < whiteA - 0.2
	ui.prompt.Visible = showSkip and not touch
	ui.skip.Visible = showSkip and touch
	if showSkip then
		if not touch and ui.promptText.Text ~= s.skipText then
			ui.promptText.Text = s.skipText
		end
		ui.promptFill.Size = UDim2.fromScale(holdK, 1)
		ui.skipFill.Size = UDim2.fromScale(holdK, 1)
	end
	holdGuis(s)
	if not frozen then
		updateSound(s, t)
		local st = s.stats[stage]
		if not st then
			st = { n = 0, sum = 0, max = 0 }
			s.stats[stage] = st
		end
		st.n += 1
		st.sum += dt
		st.max = math.max(st.max, dt)
	end
end

local function render(dt: number)
	if not shot then
		return
	end
	local ok, err = pcall(stepShot, dt)
	if not ok then
		warn("[LaunchIntroController] " .. tostring(err))
		finish("error")
	end
end

local function cameraToPlate()
	local cam = workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	cam.CameraType = Enum.CameraType.Custom
	if humanoid then
		cam.CameraSubject = humanoid
	end
	if head and head:IsA("BasePart") and root and root:IsA("BasePart") then
		local centre = arenaCentre()
		local flat = Vector3.new(centre.X - root.Position.X, 0, centre.Z - root.Position.Z)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
		local pitch = math.rad(FACE_PITCH)
		local look = dir * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
		local eye = head.Position + Vector3.new(0, 0.1, 0)
		cam.CFrame = CFrame.lookAt(eye, eye + look)
		cam.Focus = CFrame.new(eye + look)
	end
	cam.FieldOfView = ownFov()
end

finish = function(reason: string)
	local s = shot
	if not s then
		return
	end
	shot = nil
	skipHeldSince = nil
	if s.preview and IS_STUDIO then
		localPlayer:SetAttribute("LS_LaunchPreview", nil)
	end
	local function try(label: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			warn(string.format("[LaunchIntroController] clean-up (%s) failed: %s", label, tostring(err)))
		end
	end
	try("render", function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	try("skip", function()
		Input.unbind(SKIP_ACTION)
	end)
	try("sounds", function()
		for _, e in ipairs(s.sounds) do
			e.sound:Destroy()
		end
	end)
	try("camera", function()
		local cam = workspace.CurrentCamera
		if s.preview then
			cam.CameraType = s.saved.cameraType
			if s.saved.subject and s.saved.subject.Parent then
				cam.CameraSubject = s.saved.subject
			end
			cam.CFrame = s.saved.cframe
			cam.FieldOfView = s.saved.fov
		else
			cameraToPlate()
		end
	end)
	try("lighting", function()
		giveLightingBack(s)
	end)
	ClientState.launchShot = false
	try("gui", function()
		releaseGuis(s)
	end)
	try("set", function()
		if s.me then
			s.me.destroy()
		end
		for _, entry in ipairs(s.contenders) do
			if entry.figure then
				entry.figure.destroy()
			elseif entry.copy then
				entry.copy.destroy()
			end
		end
		if set then
			set.red.lift.CFrame = set.red.liftHome
			for _, slot in ipairs(set.hall.slots) do
				slot.riser.CFrame = slot.riserCF
				slot.light.Enabled = false
				for _, p in ipairs(slot.units) do
					p.LocalTransparencyModifier = 0
				end
			end
			s.lightStage = nil
			setStageLights(s, "None")
			set.hall.lights.hub.Enabled = false
			set.model.Parent = nil
		end
	end)
	try("overlay", function()
		if reason == "handoff" then
			-- the sun's glare falls away from the cover the shot ended under (Glare)
			-- (never from less than its peak: after a stalled frame the shot's own cover may not have come up)
			glareAway(math.max(tonumber(s.cover) or 0, tonumber(s.sky.peak) or 0.95), s.sky, true)
		elseif reason == "skip" then
			fadeAway(BLACK, 1, 0.5)
		else
			fadeAway(BLACK, 0.85, 0.3)
		end
	end)
	try("stats", function()
		local out = { cut = s.cut, reason = reason, preview = s.preview, parts = set and set.parts, detail = set and set.detail }
		for stage, st in pairs(s.stats) do
			if st.n > 0 then
				out[stage] = {
					frames = st.n,
					fps = math.floor(st.n / math.max(st.sum, 1e-3) * 10 + 0.5) / 10,
					worstMs = math.floor(st.max * 10000 + 0.5) / 10,
				}
			end
		end
		lastStats = out
		if IS_STUDIO then
			local json = HttpService:JSONEncode(out)
			localPlayer:SetAttribute("LS_LaunchStats", json)
			print("[LaunchIntroController] shot ended (" .. reason .. "): " .. json)
		end
	end)
end

local function begin(cut: string, callAt: number, launchAt: number, preview: boolean): boolean
	local plan = PLANS[cut]
	if not plan or not set then
		return false
	end
	local length = launchAt - callAt
	local scale = if length > 1 then length / plan.length else 1
	local t0 = now() - callAt
	if not preview and t0 >= plan.handoff * scale - 0.6 then
		return false -- nearly over: today's rise as usual
	end
	local cam = workspace.CurrentCamera
	local s = {
		cut = cut, plan = plan, scale = scale, callAt = callAt, launchAt = launchAt, preview = preview,
		roundId = GameState:GetAttribute("RoundId"), sounds = {}, fired = {}, contenders = {}, guis = {}, stats = {},
		joinT = math.max(0, t0), startedAt = os.clock(), lastRender = os.clock(), reduced = reducedMotion(),
		skipText = skipText(),
		sky = { color = WHITE, peak = 0.95, cloud = 1, day = 1 }, flood = 1, cover = 0, -- (until Glare.sky is read below)
		saved = { cameraType = cam.CameraType, subject = cam.CameraSubject, cframe = cam.CFrame, fov = cam.FieldOfView },
	}
	shot = s
	ClientState.launchShot = true
	local ok, err = pcall(function()
		-- who else is in the round (their stand-ins are made while the red room plays)
		if preview then
			for i, slotOffset in ipairs({ 1, -1, 2, -2, 3, -3, 5, -5, 8 }) do
				local n = #set.hall.slots
				table.insert(s.contenders, { seed = i * 7919, fixedSlot = (slotOffset % n) + 1 })
			end
		else
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= localPlayer and p:GetAttribute("InArena") == true and p:GetAttribute("Alive") == true then
					table.insert(s.contenders, { player = p, seed = p.UserId })
				end
			end
		end
		s.copyQueue = {}
		for i, entry in ipairs(s.contenders) do
			if entry.player and i <= standInLimit() then
				table.insert(s.copyQueue, entry)
			end
		end
		-- (a glare still falling from the last shot comes off first: the lighting kept below must be the day cycle's)
		stopGlare()
		takeLighting(s)
		s.profiles = shotProfiles()
		s.bloom = shaderTier() ~= "Off"
		-- the arrival follows the arena's sky at this hour (the cover's colour, how far the set's light floods)
		local okSky, sky = pcall(Glare.sky)
		if okSky and type(sky) == "table" then
			s.sky, s.flood = sky, tonumber(sky.flood) or 1
		end
		holdGuis(s)
		ui.screen.Enabled = true
		fadeToken += 1 -- (a fade still running from the last shot stops here)
		setFade(BLACK, 1)
		setLetterbox(1)
		set.model.Parent = workspace
		s.me = Figures.copy(localPlayer.Character) or Figures.plain(localPlayer.UserId)
		s.me.place(set.red.origin * CFrame.new(0, set.red.liftTop, 0) * CFrame.Angles(0, math.pi, 0))
		s.me.model.Parent = set.model
		pcall(s.me.secure)
		pcall(s.me.play, IDLE_ID)
		Input.bind(SKIP_ACTION, function(state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				skipHeldSince = os.clock()
			else
				skipHeldSince = nil
			end
			return Enum.ContextActionResult.Sink
		end, { keys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA }, priority = 3000 })
		cam.CameraType = Enum.CameraType.Scriptable
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_NAME)
		end)
		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 20, render)
	end)
	if not ok then
		warn("[LaunchIntroController] the shot couldn't start: " .. tostring(err))
		finish("error")
		return false
	end
	return true
end

-- Watching the round ---------------------------------------------------------------------------------------------------

local function watch()
	local s = shot
	if s then
		if s.preview then
			if IS_STUDIO and localPlayer:GetAttribute("LS_LaunchPreview") == nil then
				finish("preview")
			end
			return
		end
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if GameState:GetAttribute("Phase") ~= "Countdown" or GameState:GetAttribute("RoundId") ~= s.roundId then
			finish("phase")
		elseif not (ClientState.inArena and ClientState.alive) or ClientState.spectating ~= nil then
			finish("left")
		elseif not humanoid or humanoid.Health <= 0 then
			finish("died")
		elseif os.clock() - s.lastRender > 1.5 then
			finish("stalled")
		elseif now() > (tonumber(GameState:GetAttribute("PhaseEndsAt")) or math.huge) + 0.5 then
			finish("timeout")
		end
		return
	end
	-- Studio previews (stills and timing checks without a round)
	if IS_STUDIO then
		-- the arrival's glare alone, where you stand and look, at the hour the sky shows now
		local glareTest = localPlayer:GetAttribute("LS_LaunchGlareTest")
		if glareTest ~= nil then
			localPlayer:SetAttribute("LS_LaunchGlareTest", nil)
			if glareTest == true or type(glareTest) == "number" then
				local arena = Controllers and Controllers.ArenaController
				local hour: number? = nil
				if arena and type(arena.getClock) == "function" then
					local okClock, clock = pcall(arena.getClock)
					if okClock and type(clock) == "number" then
						hour = clock
					end
				end
				local okSky, sky = pcall(Glare.sky, hour)
				glareAway(if type(glareTest) == "number" then glareTest else 0.95, if okSky then sky else nil, false)
			end
			return
		end
		local want = localPlayer:GetAttribute("LS_LaunchPreview")
		if (want == "Full" or want == "Short") and GameState:GetAttribute("Phase") ~= "Countdown" then
			if not set then
				ensureSet()
				return
			end
			local plan = PLANS[want]
			local t = now()
			if not begin(want, t, t + plan.length, true) then
				localPlayer:SetAttribute("LS_LaunchPreview", nil)
			end
			return
		end
	end
	local phase = GameState:GetAttribute("Phase")
	if phase ~= "Countdown" then
		-- with the intro on, the set is built ahead (and rebuilt for a new detail tier between rounds); without it,
		-- only when a cut arrives anyway (a Studio test). A missing set is built in any phase; a set of another tier
		-- is rebuilt only in the Lobby or the Intermission, never under a fight (the tier follows the engine's
		-- quality, which dips in fights: 1,500 to 2,000 parts built and destroyed for a set not needed until the
		-- next countdown).
		if LaunchCfg.Intro == true and os.clock() - lastTierCheck > 5 then
			lastTierCheck = os.clock()
			if not set or (set.detail ~= tier() and (phase == "Lobby" or phase == "Intermission")) then
				ensureSet()
			end
		end
		return
	end
	local roundId = GameState:GetAttribute("RoundId")
	if roundId == playedRound then
		return
	end
	if roundId ~= seenRound then
		seenRound = roundId
		seenAt = os.clock()
	end
	local cut = GameState:GetAttribute("LaunchCut")
	if cut ~= "Full" and cut ~= "Short" then
		playedRound = roundId -- no intro this round: today's rise
		return
	end
	if not (ClientState.inArena and ClientState.alive) or ClientState.spectating ~= nil then
		-- not a contender (a spectator, a late joiner), or the server's attributes are still on their way
		if os.clock() - seenAt > 1.5 then
			playedRound = roundId
		end
		return
	end
	if not set then
		ensureSet()
		return
	end
	local callAt = tonumber(GameState:GetAttribute("LaunchCallAt"))
	local launchAt = tonumber(GameState:GetAttribute("LaunchAt"))
	if not callAt or not launchAt or launchAt <= callAt then
		playedRound = roundId
		return
	end
	playedRound = roundId
	begin(cut, callAt, launchAt, false)
end

-- Public API -------------------------------------------------------------------------------------------------------------

function LaunchIntroController.isPlaying(): boolean
	return shot ~= nil
end

function LaunchIntroController.stats(): { [string]: any }?
	return lastStats
end

-- Lifecycle --------------------------------------------------------------------------------------------------------------

function LaunchIntroController.Init(registry)
	Controllers = registry
end

function LaunchIntroController.Start()
	buildUi()
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(watch)
		if not ok then
			warn("[LaunchIntroController] " .. tostring(err))
			if shot then
				pcall(finish, "error")
			end
		end
	end)
	-- the set is built once, in the background, a few seconds after joining
	if LaunchCfg.Intro == true then
		task.delay(3, ensureSet)
	end
end

return LaunchIntroController
