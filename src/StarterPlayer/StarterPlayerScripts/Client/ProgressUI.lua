--[[
	ProgressUI - what SeasonController, DailyController and RanksController share (client only):
	  * the Progress remote (SeasonService): ProgressUI.send(msg), ProgressUI.on(t, fn(msg)), ProgressUI.state (the last
	    { t = "state" }), ProgressUI.stateChanged (Signal(state))
	  * one screen per menu, built on Shared.Cards: ProgressUI.screen(name, title, opts) -> screen
	      screen.gui, screen.panel, screen.body (the area under the title row), screen.head (right of the title),
	      screen.open(), screen.close(), screen.isOpen(), screen.onOpen(fn), screen.onClose(fn), screen.sub (a dim line
	      beside the title)
	    Opening: only in the train (not InArena, not spectating) and when no other menu has the screen
	    (ClientState.menuOpen); the world behind blurs (Cards.dimWorld), the mouse is freed (a Modal button), Esc / B /
	    the X close it, SettingsController.setModal keeps ClientState.menuOpen right.
	  * ProgressUI.rewardPicture(reward) -> fn(well) for a Cards tile / card: the reward's picture (a coin, a crate,
	    an acorn, the wheel, a 3D view or icon of a cosmetic, a rank emblem ...)
	  * ProgressUI.emblem(parent, band, size, prestige?) draws a rank emblem (a shield with chevrons) from Frames
]]
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Icons = require(Shared:WaitForChild("Icons"))
local Theme = require(Shared:WaitForChild("Theme"))
local Signal = require(Shared:WaitForChild("Signal"))
local Progression = require(Shared:WaitForChild("Progression"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer

local ProgressUI = {}
ProgressUI.state = nil :: { [string]: any }?
ProgressUI.stateChanged = Signal.new()
ProgressUI.Controllers = nil :: any -- set by the first controller's Init

local listeners: { [string]: { (any) -> () } } = {}
local remote: RemoteEvent? = nil
local screens: { [string]: any } = {}

function ProgressUI.send(msg: { [string]: any })
	if remote then
		remote:FireServer(msg)
	end
end

function ProgressUI.on(t: string, fn: (any) -> ())
	listeners[t] = listeners[t] or {}
	table.insert(listeners[t], fn)
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local r = folder:WaitForChild("Progress", 60)
	if not r or not r:IsA("RemoteEvent") then
		warn("[ProgressUI] no Progress remote: the Season, Daily and Ranks screens stay empty")
		return
	end
	remote = r
	r.OnClientEvent:Connect(function(msg: any)
		if type(msg) ~= "table" or type(msg.t) ~= "string" then
			return
		end
		if msg.t == "state" and type(msg.s) == "table" then
			ProgressUI.state = msg.s
			ProgressUI.stateChanged:Fire(msg.s)
		end
		for _, fn in ipairs(listeners[msg.t] or {}) do
			task.spawn(fn, msg)
		end
	end)
	r:FireServer({ t = "get" })
end)

--------------------------------------------------------------------------------------------------------------------
-- Where a menu may open
--------------------------------------------------------------------------------------------------------------------

function ProgressUI.inTrain(): boolean
	return not ClientState.inArena and ClientState.spectating == nil and not ClientState.launchShot
end

local function setModal(reason: string, on: boolean)
	local settings = ProgressUI.Controllers and ProgressUI.Controllers.SettingsController
	if settings and settings.setModal then
		settings.setModal(reason, on)
	else
		ClientState.menuOpen = on
	end
end
ProgressUI.setModal = setModal

--------------------------------------------------------------------------------------------------------------------
-- Screens
--------------------------------------------------------------------------------------------------------------------

function ProgressUI.anyOpen(): boolean
	for _, s in pairs(screens) do
		if s.isOpen() then
			return true
		end
	end
	return false
end

function ProgressUI.screen(name: string, title: string, opts: { [string]: any }?)
	local o = opts or {}
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	-- (integrate, 20 Nov) inside Roblox's own buttons: on a phone the panel fills the screen, and its title sat under
	-- the Roblox menu / chat buttons with DeviceSafeInsets
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = o.DisplayOrder or 40
	gui.Enabled = false
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = root
	local pad = Instance.new("UIPadding")
	pad.Name = "SafePad"
	pad.Parent = root

	local panel = Cards.panel({ Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), Parent = root })
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = o.MaxSize or Vector2.new(1200, 653)
	cap.Parent = panel
	-- the mouse is free while it is open (first person locks it otherwise)
	local modal = Instance.new("TextButton")
	modal.Name = "Modal"
	modal.Modal = true
	modal.Text = ""
	modal.BackgroundTransparency = 1
	modal.Size = UDim2.fromOffset(0, 0)
	modal.Selectable = false
	modal.Parent = panel

	local m = Cards.metrics()
	local edge = if m.phone then 12 else 28
	local titleLabel = Cards.label(title, { Name = "Title", Font = Theme.Fonts.Light, TextSize = if m.phone then 26 else 40,
		Position = UDim2.fromOffset(edge, if m.phone then 8 else 18), Size = UDim2.fromOffset(0, if m.phone then 34 else 50),
		AutomaticSize = Enum.AutomaticSize.X, Parent = panel })
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	local sub = Cards.label("", { Name = "Sub", TextSize = if m.phone then 13 else 16, Color = Theme.Colors.Ink2,
		Position = UDim2.fromOffset(edge, if m.phone then 8 else 18), Size = UDim2.new(0.5, 0, 0, if m.phone then 34 else 50),
		Parent = panel })
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextYAlignment = Enum.TextYAlignment.Center
	sub.RichText = true
	titleLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local s = scale.Scale
		sub.Position = UDim2.fromOffset(edge + titleLabel.AbsoluteSize.X / math.max(0.01, s) + 18, sub.Position.Y.Offset)
	end)
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.AnchorPoint = Vector2.new(1, 0)
	head.Position = UDim2.new(1, -(edge + 52), 0, if m.phone then 8 else 18)
	head.Size = UDim2.new(0.5, -60, 0, if m.phone then 34 else 50)
	head.Parent = panel
	local closeButton = Cards.button("Ghost", "", { Name = "Close", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, if m.phone then 4 else 14), Size = UDim2.fromOffset(44, 44), AutomaticSize = Enum.AutomaticSize.None,
		TextSize = 20, Parent = panel })
	local pads = closeButton:FindFirstChild("Pad") :: UIPadding?
	if pads then
		pads.PaddingLeft, pads.PaddingRight = UDim.new(0, 0), UDim.new(0, 0)
	end
	Icons.make("close", { Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Parent = closeButton })
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	local top = if m.phone then 48 else 84
	body.Position = UDim2.fromOffset(edge, top)
	body.Size = UDim2.new(1, -edge * 2, 1, -top - (if m.phone then 8 else 22))
	body.Parent = panel
	gui.Parent = player:WaitForChild("PlayerGui")
	Theme.bindRoot(gui)

	local screen = { gui = gui, panel = panel, body = body, head = head, sub = sub, title = titleLabel, phone = m.phone }
	local isOpen = false
	local openFns, closeFns = {}, {}
	local actionName = "ProgressClose_" .. name

	function screen.isOpen(): boolean
		return isOpen
	end
	function screen.onOpen(fn)
		table.insert(openFns, fn)
	end
	function screen.onClose(fn)
		table.insert(closeFns, fn)
	end
	function screen.close()
		if not isOpen then
			return
		end
		isOpen = false
		ContextActionService:UnbindAction(actionName)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		-- (ui-motion) fades and sinks out over QuietUI.Motion.Out, then the gui is disabled
		QuietUI.closeScreen(gui, panel)
		Cards.dimWorld(false)
		setModal("Progress_" .. name, false)
		for _, fn in ipairs(closeFns) do
			task.spawn(fn)
		end
	end
	-- force: open even if another of these screens is up (it closes first); never in the arena
	function screen.open(force: boolean?): boolean
		if isOpen then
			return true
		end
		if not ProgressUI.inTrain() then
			return false
		end
		for other, s in pairs(screens) do
			if other ~= name and s.isOpen() then
				s.close()
			end
		end
		if ClientState.menuOpen and not force then
			return false
		end
		isOpen = true
		-- (ui-motion) the panel fades in and rises 12 px over 0.25 s (the Figma motion spec); Reduce Motion: a fade
		QuietUI.openScreen(gui, panel)
		Cards.dimWorld(true)
		setModal("Progress_" .. name, true)
		ContextActionService:BindActionAtPriority(actionName, function(_, state)
			if state == Enum.UserInputState.Begin then
				screen.close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 15, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
		ProgressUI.send({ t = "get" })
		for _, fn in ipairs(openFns) do
			task.spawn(fn)
		end
		return true
	end
	closeButton.Activated:Connect(screen.close)
	-- a round starting under an open menu: it closes
	ClientState.lifeChanged:Connect(function()
		if isOpen and not ProgressUI.inTrain() then
			screen.close()
		end
	end)
	-- (final-shop, 20 Nov) arriving in the Training Centre hall: a screen left open from the train (the daily reward
	-- opens by itself there) closes, or it would hold ClientState.menuOpen and block swings, throws and ally offers
	player:GetAttributeChangedSignal("InTraining"):Connect(function()
		if isOpen and player:GetAttribute("InTraining") == true then
			screen.close()
		end
	end)
	screens[name] = screen
	return screen
end

--------------------------------------------------------------------------------------------------------------------
-- Pictures
--------------------------------------------------------------------------------------------------------------------

local function glyph(well: GuiObject, name: string, scale: number?, tone: Color3?)
	local s = scale or 0.56
	Icons.make(if Icons.has(name) then name else "spark", { Size = UDim2.fromScale(s, s), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Tone = tone, Parent = well })
end
ProgressUI.glyph = glyph

local CRATE_TINT = {
	timber = Color3.fromRGB(142, 107, 76), ironbound = Color3.fromRGB(120, 104, 90), steel = Color3.fromRGB(150, 156, 160),
	silverleaf = Color3.fromRGB(196, 202, 208), crown = Color3.fromRGB(96, 110, 136),
}

-- A rank emblem: the band's emblem from the Ranks sheets (else a Frame shield in its metal with 1 to 3 chevrons);
-- a Prestige star under it
function ProgressUI.emblem(parent: GuiObject, band: number, size: number?, prestige: number?): Frame
	local rank = Progression.Ranks[math.clamp(band or 1, 1, #Progression.Ranks)]
	local metal = Progression.Metals[rank.metal] or Theme.Colors.Ink2
	local holder = Instance.new("Frame")
	holder.Name = "Emblem"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = if size then UDim2.fromOffset(size, size) else UDim2.fromScale(0.62, 0.62)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = holder
	-- the emblem drawn on the Ranks sheets (Shared.IconAtlas); the Frame shield only if a band has no cell
	local sheetName = Icons.rank(band or 1)
	if Icons.cell(sheetName) then
		Icons.make(sheetName, { Name = "Sheet", Size = UDim2.fromScale(1, 1), Parent = holder })
	else
		-- the shield: a rounded top block and a rotated square for the point
		local top = Instance.new("Frame")
		top.Name = "Top"
		top.BorderSizePixel = 0
		top.BackgroundColor3 = metal
		top.Position = UDim2.fromScale(0.16, 0.06)
		top.Size = UDim2.fromScale(0.68, 0.5)
		local c1 = Instance.new("UICorner")
		c1.CornerRadius = UDim.new(0.12, 0)
		c1.Parent = top
		top.Parent = holder
		local point = Instance.new("Frame")
		point.Name = "Point"
		point.BorderSizePixel = 0
		point.BackgroundColor3 = metal
		point.AnchorPoint = Vector2.new(0.5, 0.5)
		point.Position = UDim2.fromScale(0.5, 0.56)
		point.Size = UDim2.fromScale(0.48, 0.48)
		point.Rotation = 45
		local c2 = Instance.new("UICorner")
		c2.CornerRadius = UDim.new(0.1, 0)
		c2.Parent = point
		point.Parent = holder
		-- a darker right half (one shade step, matte)
		local shade = Instance.new("Frame")
		shade.Name = "Half"
		shade.BorderSizePixel = 0
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 0.82
		shade.Position = UDim2.fromScale(0.5, 0.06)
		shade.Size = UDim2.fromScale(0.34, 0.82)
		shade.ZIndex = 2
		shade.Parent = holder
		local grad = Instance.new("UIGradient")
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.4) })
		grad.Rotation = 90
		grad.Parent = shade
		-- chevrons
		for i = 1, rank.chevrons do
			local y = 0.36 + (i - 1) * 0.13 - (rank.chevrons - 1) * 0.065
			for side = -1, 1, 2 do
				local bar = Instance.new("Frame")
				bar.Name = "Chevron" .. i
				bar.BorderSizePixel = 0
				bar.BackgroundColor3 = Theme.Colors.Shade
				bar.BackgroundTransparency = 0.15
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Position = UDim2.fromScale(0.5 + side * 0.105, y)
				bar.Size = UDim2.fromScale(0.27, 0.075)
				bar.Rotation = side * 32
				bar.ZIndex = 3
				local cc = Instance.new("UICorner")
				cc.CornerRadius = UDim.new(0.5, 0)
				cc.Parent = bar
				bar.Parent = holder
			end
		end
	end
	if prestige and prestige > 0 then
		local star = Instance.new("TextLabel")
		star.Name = "Prestige"
		star.BackgroundTransparency = 1
		star.AnchorPoint = Vector2.new(0.5, 0)
		star.Position = UDim2.fromScale(0.5, 0.86)
		star.Size = UDim2.fromScale(1, 0.2)
		star.FontFace = Theme.Fonts.SemiBold
		star.TextScaled = true
		star.TextColor3 = Theme.Colors.Sun
		star.Text = "★" .. tostring(prestige)
		star.ZIndex = 4
		star.Parent = holder
	end
	holder.Parent = parent
	return holder
end

-- The picture for a reward: fn(well)
function ProgressUI.rewardPicture(r: { [string]: any }): (GuiObject) -> ()
	return function(well: GuiObject)
		local k = r.k
		-- a drawn cell on the icon sheets (Shared.Icons) when there is one; a wide cell (banner, trim) fills the width
		local function sheet(name: string, s: number): boolean
			local _, cell = Icons.cell(name)
			if not cell then
				return false
			end
			glyph(well, name, if cell.W > cell.H * 1.5 then 0.9 else s)
			return true
		end
		if k == "gold" then
			glyph(well, "coin", 0.5)
		elseif k == "crate" then
			if not sheet("case_" .. tostring(r.id or "timber"), 0.62) then
				glyph(well, "crate", 0.56, CRATE_TINT[r.id or ""])
			end
		elseif k == "acorn" then
			glyph(well, "acorn", 0.5)
		elseif k == "spins" then
			if not sheet("spins", 0.56) then
				glyph(well, "wheel", 0.56)
			end
		elseif k == "stamp" then
			if not sheet("stamp", 0.52) then
				glyph(well, "star", 0.46, Theme.Colors.Sun)
			end
		elseif k == "slot" then
			glyph(well, "plus", 0.4)
		elseif k == "title" then
			if not sheet("ui_title_tag", 0.6) then
				glyph(well, "banner", 0.5, Theme.Colors.Ink2)
			end
		elseif k == "trim" then
			if not sheet(tostring(r.id or ""), 0.5) then
				glyph(well, "banner", 0.5, Progression.Metals.brass)
			end
		elseif k == "trail" then
			glyph(well, "trail", 0.56)
		elseif sheet(tostring(r.id or ""), 0.6) then
			-- a cosmetic with its own drawn cell (kill icon, kill effect, banner, emote, launch effect, skin tile)
		else
			local id = tostring(r.id or "")
			local prefix = string.sub(id, 1, 3)
			local icon = ({ sk_ = "skin", wr_ = "skin", ke_ = "kill_effect", ki_ = "kill_icon", bn_ = "banner", em_ = "emote",
				le_ = "spark" })[prefix] or "spark"
			glyph(well, icon, 0.52)
		end
	end
end

function ProgressUI.gradeOf(r: { [string]: any }): string?
	return Progression.Grades[r.id or ""]
end

function ProgressUI.rewardTitle(r: { [string]: any }): string
	if r.k == "gold" then
		return Progression.comma(r.n or 0) .. " Gold"
	end
	return Progression.rewardText(r)
end

-- "Weapon skin", "Kill icon" ... for a reward's second word
function ProgressUI.rewardKind(r: { [string]: any }): string
	local k = r.k
	if k == "gold" or k == "crate" or k == "acorn" or k == "spins" then
		return "REWARD"
	elseif k == "trail" then
		return "TRAIL"
	elseif k == "title" then
		return "TITLE"
	elseif k == "trim" then
		return "BANNER TRIM"
	end
	local prefix = string.sub(tostring(r.id or ""), 1, 3)
	return ({ sk_ = "WEAPON SKIN", wr_ = "WRAP", ke_ = "KILL EFFECT", ki_ = "KILL ICON", bn_ = "BANNER", em_ = "EMOTE",
		le_ = "LAUNCH EFFECT" })[prefix] or "ITEM"
end

-- Studio tests: setting the Workspace attribute ProgressTestOpen (on the client) to "daily", "season", "ranks",
-- "boards:Wins:week" or "rankup:4" calls the opener a controller registered here (the command bar has its own copy
-- of every module, so it cannot call the live controllers directly).
ProgressUI.openers = {} :: { [string]: (...any) -> () }
if game:GetService("RunService"):IsStudio() then
	-- "cam:boards" / "cam:level" / "cam:tag" hold the camera on the paper boards or on your own head; "cam:off" frees it
	ProgressUI.openers.cam = function(where)
		local RunService = game:GetService("RunService")
		RunService:UnbindFromRenderStep("ProgressTestCam")
		if where == "off" then
			return
		end
		RunService:BindToRenderStep("ProgressTestCam", Enum.RenderPriority.Last.Value + 50, function()
			local cam = workspace.CurrentCamera
			local folder = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("Leaderboards")
			local notice = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("Landmarks")
				and workspace.Lobby.Landmarks:FindFirstChild("NoticeBoard")
			if where == "results" and notice then
				local face = notice:FindFirstChild("NoticeFace") :: BasePart?
				if face then
					cam.CFrame = CFrame.lookAt(face.Position + face.CFrame.LookVector * 9, face.Position)
				end
			elseif where == "tag" then
				local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
				if head then
					local look = head.CFrame.LookVector
					cam.CFrame = CFrame.lookAt(head.Position + look * 9 + Vector3.new(0, 1.5, 0), head.Position + Vector3.new(0, 1.6, 0))
				end
			elseif folder then
				local a = folder:FindFirstChild(if where == "level" then "BoardLevel" else "BoardWins")
				local b = folder:FindFirstChild(if where == "level" then "BoardLevel" else "BoardElims")
				if a and b then
					local pa, pb = a:GetPivot(), b:GetPivot()
					local mid = (pa.Position + pb.Position) / 2
					local back = pa.LookVector -- the face looks into the car
					cam.CFrame = CFrame.lookAt(mid + back * (if where == "level" then 6 else 11) + Vector3.new(0, 0.3, 0), mid)
				end
			end
		end)
	end
	workspace:GetAttributeChangedSignal("ProgressTestOpen"):Connect(function()
		local v = workspace:GetAttribute("ProgressTestOpen")
		if type(v) ~= "string" or v == "" then
			return
		end
		local parts = string.split(v, ":")
		local fn = ProgressUI.openers[parts[1]]
		if fn and parts[2] == "phone" then
			-- a phone preview: build with the phone metrics, then frame the screen at 812 x 375 in the corner
			task.spawn(function()
				local orig = Cards.metrics
				Cards.metrics = function()
					return { class = "Phone", tile = 72, small = 52, card = Vector2.new(150, 204), touch = 44, word = 14,
						name = 16, gap = 8, phone = true }
				end
				pcall(fn, "phone")
				task.wait(0.6)
				Cards.metrics = orig
				for _, s in pairs(screens) do
					if s.isOpen() then
						local root = s.gui:FindFirstChild("Root") :: Frame
						local sc = root:FindFirstChild("Scale") :: UIScale
						local pad = root:FindFirstChild("SafePad") :: UIPadding
						sc.Scale = 1
						pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
						root.Size = UDim2.fromOffset(812, 375)
						local frameLine = Instance.new("UIStroke")
						frameLine.Name = "PhoneFrame"
						frameLine.Color = Theme.Colors.Sun -- the test's outline of the phone screen
						frameLine.Thickness = 2
						frameLine.Parent = root
					end
				end
			end)
		elseif fn then
			task.spawn(fn, parts[2], parts[3])
		end
		workspace:SetAttribute("ProgressTestOpen", nil)
	end)
end

function ProgressUI.isGamepad(): boolean
	local last = game:GetService("UserInputService"):GetLastInputType()
	return last.Name:find("Gamepad") ~= nil
end

return ProgressUI
