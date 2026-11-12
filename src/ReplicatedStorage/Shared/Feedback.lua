--[[
	Feedback - every refused press gets an answer (PlayabilityPlan QW12), every pickup and drop a line (QW8). Client only.

	Feedback.deny(reason: string, text: string?, opts: { limit: number?, silent: boolean? }?)
	    A short, dry deny sound, plus a toast with `text` at most once every 1.5 s per reason (text nil: sound only).
	    opts.limit: the toast shows only the first `limit` times this session (the sound always plays).
	    opts.silent: no sound (the toast still follows the rules above).
	Feedback.line(key: string, text: string, color: Color3?)
	    A short line just above the right end of the hotbar ("+4 ARROWS", "DROPPED ARROWS x24"). A line with the same
	    key within 1.5 s replaces the previous one instead of stacking. At most 3 lines; each fades after ~1.8 s.
	Feedback.pickup(itemId, added)      "+4 ARROWS" in the item's rarity colour (coalesces: +4 then +2 -> "+6 ARROWS")
	Feedback.dropped(itemId, count)     "DROPPED ARROWS x24" (coalesces taps)
	Feedback.shakeSlot(slot)            a quick wiggle of that hotbar slot (an empty slot refused)
	Feedback.toast(text, sub?, duration?) -> boolean   NotificationController.toast when it is there
	Feedback.plural(name, n) -> string  "ARROW" / "ARROWS", "THROWING KNIVES"; names that are already plural stay
	Feedback.init(Controllers)          InventoryController hands over the controller registry in Init
	Feedback.denied: Signal(reason, text?)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Signal = require(Shared:WaitForChild("Signal"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))

local Feedback = {}
Feedback.denied = Signal.new()

local DENY_TOAST_INTERVAL = 1.5
local DENY_SOUND_INTERVAL = 0.12
local LINE_LIFE = 1.8
local LINE_MERGE = 1.5
local MAX_LINES = 3

local Controllers: { [string]: any } = {}
local lastDenyToast: { [string]: number } = {}
local denyCount: { [string]: number } = {}
local lastDenySound = 0

function Feedback.init(registry: { [string]: any })
	Controllers = registry or {}
end

function Feedback.toast(text: string, sub: string?, duration: number?): boolean
	local notifications = Controllers.NotificationController
	if notifications and type(notifications.toast) == "function" then
		return (pcall(notifications.toast, text, sub, duration))
	end
	return false
end

function Feedback.deny(reason: string, text: string?, opts: { [string]: any }?)
	local o = opts or {}
	local now = os.clock()
	if not o.silent and now - lastDenySound >= DENY_SOUND_INTERVAL then
		lastDenySound = now
		Sfx.play("InventoryFull", { volume = 0.55 })
	end
	if type(text) == "string" and text ~= "" then
		local shown = denyCount[reason] or 0
		local allowed = o.limit == nil or shown < o.limit
		if allowed and now - (lastDenyToast[reason] or -math.huge) >= DENY_TOAST_INTERVAL then
			lastDenyToast[reason] = now
			denyCount[reason] = shown + 1
			Feedback.toast(text, nil, 1.6)
		end
	end
	Feedback.denied:Fire(reason, text)
end

local IRREGULAR: { [string]: string } = { Knife = "Knives", knife = "knives", Meat = "Meat", Herbs = "Herbs", Berries = "Berries" }

function Feedback.plural(name: string, n: number): string
	if n == 1 then
		return name
	end
	local last = string.match(name, "(%w+)$")
	if last and IRREGULAR[last] then
		return string.sub(name, 1, #name - #last) .. IRREGULAR[last]
	end
	if string.sub(name, -1) == "s" or string.sub(name, -1) == "S" then
		return name
	end
	return name .. "s"
end

--------------------------------------------------------------------------------------------------------------------
-- Lines above the hotbar
--------------------------------------------------------------------------------------------------------------------
local gui: ScreenGui? = nil
local holder: Frame? = nil
type Line = { key: string, label: TextLabel, stroke: UIStroke, born: number, token: number, amount: number }
local lines: { Line } = {}
local lineToken = 0

local function ensureGui(): Frame?
	if holder and holder.Parent and gui and gui.Parent then
		return holder
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local hud = playerGui:FindFirstChild("HUD")
	local screen = Instance.new("ScreenGui")
	screen.Name = "FeedbackLines"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = if hud and hud:IsA("ScreenGui") then hud.IgnoreGuiInset else false
	screen.DisplayOrder = (if hud and hud:IsA("ScreenGui") then hud.DisplayOrder else 0) + 1
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local frame = Instance.new("Frame")
	frame.Name = "Lines"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Size = UDim2.fromOffset(260, 90)
	frame.Position = UDim2.new(1, -24, 1, -96)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame
	frame.Parent = screen
	screen.Parent = playerGui
	gui, holder = screen, frame
	return frame
end

-- Keep the lines just above the right end of the hotbar (HUDController.getHotbarRect, in screen pixels).
local function place()
	local frame = holder
	if not frame then
		return
	end
	local hud = Controllers.HUDController
	if hud and type(hud.getHotbarRect) == "function" then
		local ok, pos, size = pcall(hud.getHotbarRect)
		if ok and typeof(pos) == "Vector2" and typeof(size) == "Vector2" and size.X > 0 then
			frame.Position = UDim2.fromOffset(math.floor(pos.X + size.X), math.floor(pos.Y - 6))
			frame.AnchorPoint = Vector2.new(1, 1)
		end
	end
end

local function fadeLine(line: Line)
	local index = table.find(lines, line)
	if index then
		table.remove(lines, index)
	end
	TweenService:Create(line.stroke, Theme.Tween.FadeOut, { Transparency = 1 }):Play()
	local t = TweenService:Create(line.label, Theme.Tween.FadeOut, { TextTransparency = 1 })
	t.Completed:Once(function()
		line.label:Destroy()
	end)
	t:Play()
end

local function schedule(line: Line)
	lineToken += 1
	local token = lineToken
	line.token = token
	task.delay(LINE_LIFE, function()
		if line.token == token and line.label.Parent then
			fadeLine(line)
		end
	end)
end

function Feedback.line(key: string, text: string, color: Color3?, amount: number?)
	local frame = ensureGui()
	if not frame then
		return
	end
	place()
	local now = os.clock()
	local newest = lines[#lines]
	if newest and newest.key == key and now - newest.born < LINE_MERGE then
		newest.label.Text = text
		newest.label.TextColor3 = color or Theme.Colors.Text
		newest.born = now
		newest.amount = amount or newest.amount
		local pop = newest.label:FindFirstChildOfClass("UIScale")
		if pop then
			pop.Scale = 1.08
			TweenService:Create(pop, Theme.Tween.Fast, { Scale = 1 }):Play()
		end
		schedule(newest)
		return
	end
	while #lines >= MAX_LINES do
		fadeLine(lines[1])
	end
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 20)
	label.FontFace = Theme.Fonts.Heading
	label.TextSize = 17
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = color or Theme.Colors.Text
	label.Text = text
	label.TextTransparency = 1
	lineToken += 1
	label.LayoutOrder = lineToken
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Shadow
	stroke.Transparency = 1
	stroke.Thickness = 1
	stroke.Parent = label
	local pop = Instance.new("UIScale")
	pop.Scale = 1.1
	pop.Parent = label
	label.Parent = frame
	TweenService:Create(label, Theme.Tween.Fast, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, Theme.Tween.Fast, { Transparency = Theme.Transparency.TextShadow }):Play()
	TweenService:Create(pop, Theme.Tween.Normal, { Scale = 1 }):Play()
	local line: Line = { key = key, label = label, stroke = stroke, born = now, token = 0, amount = amount or 0 }
	table.insert(lines, line)
	schedule(line)
end

local function itemName(itemId: string): (string, Color3)
	local def = ItemDefs.get(itemId)
	local name = if def then def.name else itemId
	local color = if def then Theme.Rarity[def.rarity] or Theme.Colors.Text else Theme.Colors.Text
	return name, color
end

local function amountFor(key: string, add: number): number
	local newest = lines[#lines]
	if newest and newest.key == key and os.clock() - newest.born < LINE_MERGE then
		return newest.amount + add
	end
	return add
end

function Feedback.pickup(itemId: string, added: number)
	if type(itemId) ~= "string" or type(added) ~= "number" or added <= 0 then
		return
	end
	local key = "pickup:" .. itemId
	local total = amountFor(key, added)
	local name, color = itemName(itemId)
	Feedback.line(key, string.format("+%d %s", total, string.upper(Feedback.plural(name, total))), color, total)
end

function Feedback.dropped(itemId: string, count: number)
	if type(itemId) ~= "string" or type(count) ~= "number" or count <= 0 then
		return
	end
	local key = "drop:" .. itemId
	local total = amountFor(key, count)
	local name = itemName(itemId)
	local text = if total > 1
		then string.format("DROPPED %s ×%d", string.upper(Feedback.plural(name, total)), total)
		else "DROPPED " .. string.upper(name)
	Feedback.line(key, text, Theme.Colors.TextDim, total)
end

-- A quick sideways wiggle (Rotation, which the HUD never animates) of a hotbar slot's card.
function Feedback.shakeSlot(slot: number)
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("HUD")
	local button = hud and hud:FindFirstChild("Slot" .. tostring(slot), true)
	local card = button and button:FindFirstChild("Card")
	if not (card and card:IsA("GuiObject")) then
		return
	end
	task.spawn(function()
		for _, angle in ipairs({ 6, -5, 3, -1.5, 0 }) do
			local t = TweenService:Create(card, TweenInfo.new(0.045, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Rotation = angle })
			t:Play()
			t.Completed:Wait()
		end
		card.Rotation = 0
	end)
end

return Feedback
