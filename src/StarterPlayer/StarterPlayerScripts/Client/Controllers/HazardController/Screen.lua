--[[
	HazardController.Screen - the challenges' own small ScreenGui (PlayerGui.HazardScreen). Self-contained and plain on
	purpose: it uses no Theme and no UI kit, so the UI owners can restyle or replace it without touching anything else.

	  Edges   two sets of four soft bars along the screen's edges:
	            Sting  blue, shimmering: you are in a butterfly swarm (Screen.sting 0..1, set by Butterflies)
	            Frost  pale: the fog's cold (Screen.frost 0..1, set by Fog)
	          Never red, never a wound: a colour at the edge of the view, nothing more.
	  Line    one line of plain white text under the top of the screen: the hint a module asks for this frame
	          (ctx.setHint) or a short message (Screen.say). It carries the same information as the colour, in words.
]]
local Players = game:GetService("Players")

local Screen = {}

Screen.sting = 0
Screen.frost = 0

local gui: ScreenGui? = nil
local line: TextLabel? = nil
local bars: { [string]: { Frame } } = { Sting = {}, Frost = {} }
local shown = { Sting = 0, Frost = 0 }
local sayText: string? = nil
local sayUntil = 0
local lineText = ""
local lineAlpha = 1

local EDGES = {
	-- anchor, position, size (scale of the screen), gradient rotation (transparent toward the middle)
	{ Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.2), 90 },
	{ Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.2), -90 },
	{ Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.16, 1), 0 },
	{ Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.16, 1), 180 },
}

local function build(ctx)
	local made = Instance.new("ScreenGui")
	made.Name = "HazardScreen"
	made.ResetOnSpawn = false
	made.IgnoreGuiInset = true
	made.DisplayOrder = -5 -- under the game's own HUD
	made.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	for set, color in pairs({ Sting = ctx.Look.Colors.StingEdge, Frost = ctx.Look.Colors.Frost }) do
		for index, edge in ipairs(EDGES) do
			local bar = Instance.new("Frame")
			bar.Name = set .. index
			bar.AnchorPoint = edge[1]
			bar.Position = edge[2]
			bar.Size = edge[3]
			bar.BackgroundColor3 = color
			bar.BackgroundTransparency = 0
			bar.BorderSizePixel = 0
			bar.Visible = false
			bar.Active = false
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = edge[4]
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(0.45, 0.8),
				NumberSequenceKeypoint.new(1, 1),
			})
			gradient.Parent = bar
			bar.Parent = made
			table.insert(bars[set], bar)
		end
	end
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.17)
	label.Size = UDim2.fromScale(0.9, 0.04)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.55
	label.TextScaled = true
	label.Text = ""
	label.Visible = false
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 20
	limit.MinTextSize = 10
	limit.Parent = label
	label.Parent = made
	line = label
	made.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = made
end

function Screen.start(ctx)
	build(ctx)
end

function Screen.say(text: string, seconds: number)
	sayText = text
	sayUntil = os.clock() + seconds
end

local function showSet(set: string, alpha: number, t: number, shimmer: boolean)
	local list = bars[set]
	if alpha <= 0.01 then
		if shown[set] ~= 0 then
			shown[set] = 0
			for _, bar in ipairs(list) do
				bar.Visible = false
			end
		end
		return
	end
	shown[set] = alpha
	for index, bar in ipairs(list) do
		local a = alpha
		if shimmer then
			-- each edge breathes on its own: wings crossing the view
			a *= 0.62 + 0.38 * math.noise(t * 5.5, index * 7.3)
				+ 0.18 * math.sin(t * 23 + index * 1.9)
		end
		bar.BackgroundTransparency = 1 - math.clamp(a, 0, 1) * 0.7
		bar.Visible = true
	end
end

function Screen.update(ctx, dt: number, _now: number)
	if not gui then
		return
	end
	local t = os.clock()
	local show = ctx.inArena
	-- ease toward what the modules asked for
	local sting = if show then Screen.sting else 0
	local frost = if show then Screen.frost else 0
	local s = shown.Sting + (sting - shown.Sting) * math.min(1, dt * 9)
	local f = shown.Frost + (frost - shown.Frost) * math.min(1, dt * 2.5)
	showSet("Sting", if s < 0.012 and sting == 0 then 0 else s, t, true)
	shown.Sting = if s < 0.012 and sting == 0 then 0 else s
	showSet("Frost", if f < 0.012 and frost == 0 then 0 else f, t, false)
	-- the line
	local label = line :: TextLabel
	local text = nil
	if sayText and t < sayUntil then
		text = sayText
	elseif show and ctx.hint then
		text = ctx.hint
	end
	if text then
		if lineText ~= text then
			lineText = text
			label.Text = text
		end
		lineAlpha = math.max(0, lineAlpha - dt * 5)
		label.TextTransparency = lineAlpha
		label.TextStrokeTransparency = 0.55 + 0.45 * lineAlpha
		label.Visible = true
	elseif label.Visible then
		lineAlpha = math.min(1, lineAlpha + dt * 2.5)
		label.TextTransparency = lineAlpha
		label.TextStrokeTransparency = 0.55 + 0.45 * lineAlpha
		if lineAlpha >= 1 then
			label.Visible = false
			lineText = ""
		end
	end
end

function Screen.debug(_ctx)
	return { sting = shown.Sting, frost = shown.Frost, line = lineText }
end

return Screen
