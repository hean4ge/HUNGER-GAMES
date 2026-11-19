--[[
	WheelController - the wheel, the prize case and the Armoury board in the train, client side (the server half is
	RewardsService; the objects are built by ServerStorage.WorldGen.WheelBuilder as workspace.Lobby.Rewards).

	What it does (Weapons_v2 section 5.5, in the Quiet style: matte, no boxes, no pop-ups):
	  * the prompts: their one-line words (PromptLine) say free or the price; pressed, they ask the server
	  * while one of its prompts is shown, one thin odds line under the prompt's line (every outcome and its percent),
	    and one line with the pity count ("★★★★ weapon within 18 spins") - the odds are read before any draw
	  * a spin (anyone's: others in the car watch): the wheel turns 3.6 to 4.1 s, the leather tongue clicks over the
	    brass pegs, the clicks slow, the wheel stops on the server's segment, the warm lamp above lights it; the spinner's
	    camera eases to the wheel and the case and the train's ambience dips
	  * the reveal at the case: the lid lifts (a hiss), the prize rises on its plinth, turning, under a soft spot, and
	    its stars appear one at a time, each with a click and a light tick. 4 stars: a lower chime and the car's lamps
	    dip. 5 stars: a bell, the lamps dim for 1.5 s with only the spot on the case, and a puff of dust from the case.
	    A Strongbox: three latch clicks first. Gold: a small stack of coins and "+80 Gold".
	  * the Armoury board: a live face over the built one (a SurfaceGui in PlayerGui on Armoury.Face): every pool
	    weapon with the stars you own, BUY / RAISE with a second press to confirm, and BRING (click a name you own)
	Sounds are the game's own keys (Shared.Sounds) played locally at the objects.
	WheelController.holdUntil (os.clock time) tells CurrencyController not to show a new balance before your reveal.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared:WaitForChild("Rewards"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))

local player = Players.LocalPlayer

local WheelController = {}
WheelController.holdUntil = 0

local remote: RemoteEvent? = nil
local state: { [string]: any } = {}
local corner: Model? = nil
local wheelAngle = 0 -- degrees, clockwise as seen from the car; 0 = as built
local spinning = false
local revealToken = 0
local promptOwner: { [ProximityPrompt]: string } = {}
local shownPrompt: ProximityPrompt? = nil
local oddsGui: ScreenGui? = nil
local oddsLine: TextLabel? = nil
local pityLine: TextLabel? = nil
local promptText: TextLabel? = nil
local promptKey: Frame? = nil
local promptTap: TextButton? = nil
local board: { [string]: any } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function find(path: { string }): Instance?
	local node: Instance? = corner
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function play(key: string, at: Vector3?, volume: number?, pitch: number?)
	pcall(Sfx.play, key, { position = at, volume = volume, pitch = pitch })
end

local function within(at: Vector3, dist: number): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - at).Magnitude <= dist
end

-- Prompts and the odds line ----------------------------------------------------------------------------------------------

local function stateLine(kind: string): (string, string)
	local cfg = Rewards.config()
	local pity = state.pity or {}
	if kind == "spin" then
		local free = (state.freeLeft or 0) > 0
		local odds = Rewards.wheelOddsLine(not free)
		local p = string.format("A ★★★★ weapon or better within %d spins", pity.wheel4 or cfg.Wheel.Pity4)
		return odds, p
	end
	local odds = Rewards.boxOddsLine(kind)
	local p = string.format("★★★★ or better within %d boxes  ·  ★★★★★ within %d", pity.box4 or cfg.Strongbox.Pity4,
		pity.box5 or cfg.Strongbox.Pity5)
	return odds, p
end

-- Gold still needed for a paid draw (0: affordable, or free, or the Gold has not loaded)
local promptShort: { [ProximityPrompt]: number } = {}
local promptGold: number? = nil -- (held, like the Gold line, while your own reveal plays)
local function shortOf(cost: number): number
	if os.clock() >= WheelController.holdUntil or promptGold == nil then
		promptGold = tonumber(player:GetAttribute("Gold")) or (if state.loaded then tonumber(state.gold) else nil)
	end
	local gold = promptGold
	if not gold then
		return 0
	end
	return math.max(0, cost - gold)
end

local function refreshPrompts()
	local cfg = Rewards.config()
	for prompt, kind in pairs(promptOwner) do
		if kind == "spin" then
			local text
			local short = 0
			if (state.freeLeft or 0) > 0 then
				text = "Spin the wheel · free today"
			elseif state.paidBlocked then
				text = "Spin the wheel · free again tomorrow"
			elseif (state.paidLeft or 0) <= 0 then
				text = "The wheel · no more spins today"
			else
				local cost = state.spinCost or cfg.Wheel.SpinCost
				short = shortOf(cost)
				text = string.format("Spin the wheel · %s Gold", Rewards.comma(cost))
			end
			if short > 0 then
				text ..= string.format("  ·  need %s more Gold", Rewards.comma(short))
			end
			promptShort[prompt] = short
			prompt:SetAttribute("PromptLine", text)
			prompt.Enabled = not spinning
		else
			-- Strongboxes are always paid: hidden for a player who may not buy paid random items
			prompt.Enabled = not state.paidBlocked
			local short = shortOf(if kind == "masterwork" then cfg.Strongbox.MasterworkCost else cfg.Strongbox.Cost)
			promptShort[prompt] = short
			prompt:SetAttribute("PromptLine", prompt.ActionText .. " " .. prompt.ObjectText
				.. (if short > 0 then string.format("  ·  need %s more Gold", Rewards.comma(short)) else ""))
		end
	end
	if shownPrompt and oddsLine and pityLine then
		local odds, pity = stateLine(promptOwner[shownPrompt])
		oddsLine.Text = odds
		pityLine.Text = pity
		if promptText then
			local attr = shownPrompt:GetAttribute("PromptLine")
			promptText.Text = if type(attr) == "string" and attr ~= "" then attr
				else shownPrompt.ActionText .. " " .. shownPrompt.ObjectText
			-- too little Gold: the line is dimmed and shows no key (a press still only gets the server's quiet refusal)
			local short = (promptShort[shownPrompt] or 0) > 0
			QuietUI.textTransparency(promptText, if short then 0.5 else 0)
			if promptKey then
				promptKey.Visible = not short
			end
		end
	end
end

local function buildOddsGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WheelOdds"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Enabled = false
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0.5, 74) -- under the prompt's line
	holder.Size = UDim2.new(0.9, 0, 0, 44)
	holder.Parent = gui
	-- the prompt's own line (HUDController draws Custom prompts only in the arena): [E] Spin the wheel · free today
	local row = Instance.new("Frame")
	row.Name = "PromptRow"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0.5, 34)
	row.Size = UDim2.fromOffset(520, 30)
	row.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	promptKey = QuietUI.key({ Name = "Key", Parent = row, Text = "E", LayoutOrder = 1 })
	promptText = QuietUI.label({ Name = "Words", Parent = row, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
		TextSize = Theme.TextSize.Body, Font = "Medium", LayoutOrder = 2 })
	-- a touch screen presses it here (the prompt's hold, then its release)
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.AnchorPoint = Vector2.new(0.5, 0)
	tap.Position = UDim2.new(0.5, 0, 0.5, 26)
	tap.Size = UDim2.fromOffset(360, 48)
	tap.Visible = false
	tap.Parent = gui
	tap.Activated:Connect(function()
		local p = shownPrompt
		if p then
			pcall(function()
				p:InputHoldBegin()
			end)
			task.delay(p.HoldDuration + 0.05, function()
				pcall(function()
					p:InputHoldEnd()
				end)
			end)
		end
	end)
	promptTap = tap
	oddsLine = QuietUI.label({ Name = "Odds", Parent = holder, Size = UDim2.new(1, 0, 0, 20), TextSize = Theme.TextSize.Label,
		Font = "Medium", TextXAlignment = Enum.TextXAlignment.Center })
	pityLine = QuietUI.label({ Name = "Pity", Parent = holder, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.TextSize.Caption, Font = "Medium", TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.Ink2 })
	gui.Parent = player:WaitForChild("PlayerGui")
	oddsGui = gui
end

local function onPromptShown(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if not promptOwner[prompt] or not oddsGui then
		return
	end
	shownPrompt = prompt
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	if promptKey then
		QuietUI.setKey(promptKey, if touch then "TAP" elseif inputType == Enum.ProximityPromptInputType.Gamepad then "X" else "E")
	end
	if promptTap then
		promptTap.Visible = touch
	end
	refreshPrompts()
	oddsGui.Enabled = true
end

local function onPromptHidden(prompt: ProximityPrompt)
	if shownPrompt == prompt then
		shownPrompt = nil
		if oddsGui then
			oddsGui.Enabled = false
		end
	end
end

-- The wheel turning --------------------------------------------------------------------------------------------------------

local function setWheel(angle: number)
	local root = find({ "Wheel", "Root" }) :: BasePart?
	local wheel = find({ "Wheel" })
	if not root or not wheel then
		return
	end
	local rest = wheel:GetAttribute("RestCFrame")
	if typeof(rest) ~= "CFrame" then
		return
	end
	-- the hub's X axis points into the car: a turn of -angle about it is clockwise as seen from the car
	root.CFrame = rest * CFrame.Angles(-math.rad(angle), 0, 0)
end

local tongueRest: { [BasePart]: CFrame } = {}
local function flickTongue(amount: number)
	local tongue = find({ "Wheel", "Tongue" })
	if not tongue then
		return
	end
	local pivot = tongue:GetAttribute("PivotAt")
	if typeof(pivot) ~= "Vector3" then
		return
	end
	local axis = CFrame.new(pivot)
	for _, p in ipairs(tongue:GetChildren()) do
		if p:IsA("BasePart") then
			tongueRest[p] = tongueRest[p] or p.CFrame
			local rest = tongueRest[p]
			p.CFrame = axis * CFrame.Angles(0, 0, math.rad(amount)) * axis:Inverse() * rest
			task.delay(0.07, function()
				p.CFrame = rest
			end)
		end
	end
end

local savedCamera: { [string]: any }? = nil
local function holdCamera(on: boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local ambience = SoundService:FindFirstChild("Ambience")
	if on then
		if savedCamera then
			return
		end
		savedCamera = { type = camera.CameraType, cframe = camera.CFrame, volume = if ambience and ambience:IsA("SoundGroup") then ambience.Volume else nil }
		camera.CameraType = Enum.CameraType.Scriptable
		local wheelC = (find({ "Wheel", "Root" }) :: BasePart).Position
		local case = find({ "Case", "Base" }) :: BasePart?
		local mid = if case then (wheelC + case.Position) / 2 else wheelC
		-- high enough to look over the spinner's own head at the wheel and the case
		local target = CFrame.lookAt(Vector3.new(mid.X, mid.Y + 2.6, mid.Z + 9.5), mid + Vector3.new(0, -0.2, 0))
		TweenService:Create(camera, TweenInfo.new(if QuietUI.reducedMotion() then 0 else 0.4, Enum.EasingStyle.Sine), { CFrame = target }):Play()
		if ambience and ambience:IsA("SoundGroup") then
			TweenService:Create(ambience, TweenInfo.new(0.5), { Volume = ambience.Volume * 0.45 }):Play()
		end
	else
		local s = savedCamera
		savedCamera = nil
		if not s then
			return
		end
		camera.CameraType = Enum.CameraType.Custom
		if ambience and ambience:IsA("SoundGroup") and s.volume then
			TweenService:Create(ambience, TweenInfo.new(0.8), { Volume = s.volume }):Play()
		end
	end
end

local function shake(strength: number)
	local camera = workspace.CurrentCamera
	if camera and savedCamera and not QuietUI.reducedMotion() then
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * strength), math.rad((math.random() - 0.5) * strength), 0)
	end
end

-- The lamps of the car (for the 4 and 5 star moments): this client only
local function dimLamps(factor: number, seconds: number)
	local lobby = workspace:FindFirstChild("Lobby")
	local lamps = lobby and lobby:FindFirstChild("Lamps")
	local lights = {}
	if lamps then
		for _, l in ipairs(lamps:GetDescendants()) do
			if l:IsA("Light") and l.Parent and string.find(l.Parent.Name, "Observation") then
				table.insert(lights, l)
			end
		end
	end
	local before = Lighting.ExposureCompensation
	for _, l in ipairs(lights) do
		local b = l:GetAttribute("WheelBase") or l.Brightness
		l:SetAttribute("WheelBase", b)
		TweenService:Create(l, TweenInfo.new(0.25), { Brightness = b * factor }):Play()
	end
	TweenService:Create(Lighting, TweenInfo.new(0.25), { ExposureCompensation = before - (1 - factor) * 0.8 }):Play()
	task.delay(seconds, function()
		for _, l in ipairs(lights) do
			TweenService:Create(l, TweenInfo.new(0.6), { Brightness = l:GetAttribute("WheelBase") or l.Brightness }):Play()
		end
		TweenService:Create(Lighting, TweenInfo.new(0.6), { ExposureCompensation = before }):Play()
	end)
end

-- The reveal at the case -----------------------------------------------------------------------------------------------------

local function coinStack(): Model
	local m = Instance.new("Model")
	m.Name = "Coins"
	for i = 0, 3 do
		local c = Instance.new("Part")
		c.Shape = Enum.PartType.Cylinder
		c.Size = Vector3.new(0.09, 0.62 - i * 0.03, 0.62 - i * 0.03)
		c.CFrame = CFrame.new(math.sin(i * 1.7) * 0.05, 0.05 + i * 0.1, math.cos(i * 1.7) * 0.05) * CFrame.Angles(0, 0, math.rad(90))
		c.Color = Color3.fromRGB(196, 160, 88)
		c.Material = Enum.Material.SmoothPlastic
		c.Anchored = true
		c.CanCollide = false
		c.CanQuery = false
		c.Parent = m
		if i == 0 then
			m.PrimaryPart = c
		end
	end
	return m
end

local function prizeModel(prize: { [string]: any }): Model?
	if prize.kind == "gold" then
		return coinStack()
	end
	local ok, ItemModels = pcall(require, Shared:WaitForChild("ItemModels"))
	if not ok then
		return nil
	end
	local built = nil
	pcall(function()
		built = ItemModels.build(prize.id)
	end)
	-- the star finish (Shared.Stars, stars-kits): the same silhouette, a matte finish per star
	local starsModule = Shared:FindFirstChild("Stars")
	if built and starsModule then
		pcall(function()
			require(starsModule).applyFinish(built, prize.stars or 1)
		end)
	end
	if built then
		for _, d in ipairs(built:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			elseif d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
	end
	return built
end

local function reveal(prize: { [string]: any }, kind: string, mine: boolean, token: number)
	local base = find({ "Case", "Base" }) :: BasePart?
	local lid = find({ "Case", "Lid" }) :: BasePart?
	local plinth = find({ "Case", "Plinth" }) :: BasePart?
	local light = find({ "Case", "Lamp", "CaseLight" }) :: SpotLight?
	if not base or not lid or not plinth then
		return
	end
	local at = base.Position
	local audible = within(at, 70)
	local function vol(v: number): number
		return if audible then v else 0
	end
	local lidRest = lid.CFrame
	local hinge = lid:GetAttribute("Hinge")
	local plinthRest = plinth:GetAttribute("Rest")
	if typeof(hinge) ~= "CFrame" or typeof(plinthRest) ~= "CFrame" then
		return
	end

	-- a Strongbox: three latch clicks first
	if kind == "strongbox" or kind == "masterwork" then
		for i = 1, 3 do
			local latch = find({ "Case", "Latch" .. i }) :: BasePart?
			if latch then
				if latch:GetAttribute("WheelRest") == nil then
					latch:SetAttribute("WheelRest", latch.CFrame)
				end
				latch.CFrame = (latch:GetAttribute("WheelRest") :: CFrame) * CFrame.Angles(math.rad(-70), 0, 0)
			end
			play("PlateLock", at, vol(0.55), 1.15 + i * 0.05)
			task.wait(0.28)
		end
	end
	-- the lid lifts with a hiss
	play("Launch_Seal", at, vol(0.6), 1.1)
	local lidValue = Instance.new("NumberValue")
	lidValue.Changed:Connect(function(v)
		local a = hinge * CFrame.Angles(math.rad(-105 * v), 0, 0) * hinge:Inverse() * lidRest
		lid.CFrame = a
	end)
	TweenService:Create(lidValue, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
	if light then
		TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 2.2 }):Play()
	end
	task.wait(0.35)

	-- the prize rises on the plinth, turning
	local model = prizeModel(prize)
	local riseTop = plinthRest.Position + Vector3.new(0, 0.95, 0)
	TweenService:Create(plinth, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = plinthRest + Vector3.new(0, 0.95, 0) }):Play()
	local holder: Model? = nil
	if model then
		holder = model
		local cf, size = model:GetBoundingBox()
		local scale = math.min(1, 1.9 / math.max(size.X, size.Y, size.Z))
		if scale < 0.99 then
			pcall(function()
				model:ScaleTo(scale)
			end)
			cf, size = model:GetBoundingBox()
		end
		model.Parent = workspace
		local center = riseTop + Vector3.new(0, 0.45 + size.Y / 2 * 0.4, 0)
		local offset = cf:Inverse() * model:GetPivot()
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not model.Parent then
				conn:Disconnect()
				return
			end
			local t = os.clock() - t0
			local rise = math.min(1, t / 0.7)
			local y = (1 - (1 - rise) ^ 2) * 1
			local spinCF = CFrame.new(center + Vector3.new(0, (y - 1) * 0.9, 0)) * CFrame.Angles(0, t * 0.9, 0)
				* CFrame.Angles(0, 0, if prize.kind == "gold" then 0 else math.rad(70))
			model:PivotTo(spinCF * offset)
		end)
	end

	-- the words over it: the name, then the stars one at a time
	local bb = Instance.new("BillboardGui")
	bb.Name = "PrizeWords"
	bb.Size = UDim2.fromOffset(420, 90)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0.8) -- above the rising prize, clear of the board
	bb.LightInfluence = 0
	bb.MaxDistance = 45
	bb.AlwaysOnTop = false
	bb.Adornee = base
	local nameLine = QuietUI.label({ Name = "Name", Parent = bb, Size = UDim2.new(1, 0, 0, 30), Font = "SemiBold",
		TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center })
	local starLine = QuietUI.label({ Name = "Stars", Parent = bb, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 30),
		Font = "Medium", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.Colors.Ink })
	local noteLine = QuietUI.label({ Name = "Note", Parent = bb, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 22),
		Font = "Medium", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.Colors.Ink2 })
	bb.Parent = player:WaitForChild("PlayerGui")

	local stars = prize.stars or 0
	if prize.kind == "gold" then
		nameLine.Text = string.format("+%s Gold", Rewards.comma(prize.gold or 0))
		play("PickUp", at, vol(0.8), 1.0)
	else
		nameLine.Text = prize.name or prize.id or ""
		task.wait(0.45)
		for i = 1, stars do
			if revealToken ~= token then
				break
			end
			starLine.Text = string.rep("★", i)
			if i >= 4 then
				starLine.TextColor3 = Theme.Colors.Gold
			end
			play("UIClick", at, vol(0.9), 0.85 + i * 0.07)
			if light then
				light.Brightness = 3.2
				TweenService:Create(light, TweenInfo.new(0.22), { Brightness = 2.2 }):Play()
			end
			task.wait(0.32)
		end
		if prize.duplicate then
			noteLine.Text = string.format("already held  ·  +%s Gold", Rewards.comma(prize.goldBack or 0))
		elseif (prize.before or 0) > 0 then
			noteLine.Text = string.format("%s → %s", Rewards.starText(prize.before), Rewards.starText(stars))
		else
			noteLine.Text = "into your Armoury"
		end
		if not mine then
			noteLine.Text = ""
		end
		if stars >= 5 then
			play("FeastBell", at, vol(0.9), 1.0)
			dimLamps(0.25, 1.5)
			local puff = Instance.new("ParticleEmitter")
			puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
			puff.Color = ColorSequence.new(Color3.fromRGB(196, 186, 168))
			puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
			puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.6) })
			puff.Lifetime = NumberRange.new(0.8, 1.3)
			puff.Speed = NumberRange.new(0.6, 1.4)
			puff.SpreadAngle = Vector2.new(70, 70)
			puff.LightInfluence = 1
			puff.Rate = 0
			puff.Parent = base
			puff:Emit(14)
			task.delay(2, function()
				puff:Destroy()
			end)
		elseif stars == 4 then
			play("Notify", at, vol(0.8), 0.78)
			dimLamps(0.7, 1.2)
		end
	end
	-- Studio only: Workspace attribute RewardsRevealHold = seconds keeps the reveal up longer (for QA pictures)
	local hold = if RunService:IsStudio() then tonumber(workspace:GetAttribute("RewardsRevealHold")) else nil
	task.wait(hold or (if stars >= 5 then 3.2 else 2.4))

	-- back as it was
	if holder then
		holder:Destroy()
	end
	bb:Destroy()
	TweenService:Create(plinth, TweenInfo.new(0.4), { CFrame = plinthRest }):Play()
	TweenService:Create(lidValue, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Value = 0 }):Play()
	if light then
		TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	end
	task.wait(0.45)
	lid.CFrame = lidRest
	lidValue:Destroy()
	for i = 1, 3 do
		local latch = find({ "Case", "Latch" .. i }) :: BasePart?
		local rest = latch and latch:GetAttribute("WheelRest")
		if latch and typeof(rest) == "CFrame" then
			latch.CFrame = rest -- latches stand upright again
		end
	end
end

local function onSpin(data: { [string]: any })
	if type(data) ~= "table" or not corner then
		return
	end
	local mine = data.userId == player.UserId
	local token = revealToken + 1
	revealToken = token
	spinning = true
	refreshPrompts()
	local root = find({ "Wheel", "Root" }) :: BasePart?
	local wheel = find({ "Wheel" })
	if not root or not wheel then
		return
	end
	local pegs = tonumber(wheel:GetAttribute("Pegs")) or 32
	local step = 360 / pegs
	local from = wheelAngle
	local target = tonumber(data.angle) or 0
	local delta = (-(from + target)) % 360 + 360 * 4
	local duration = math.max(1, tonumber(data.duration) or 3.6)
	if mine then
		WheelController.holdUntil = os.clock() + duration + 4
		holdCamera(true)
	end
	local at = root.Position
	local audible = within(at, 60)
	while now() < (tonumber(data.startAt) or 0) do
		task.wait()
	end
	play("UIOpen", at, if audible then 0.6 else 0, 0.8) -- the pull
	local t0 = os.clock()
	local lastPeg = math.floor(from / step)
	local done = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local u = math.min(1, (os.clock() - t0) / duration)
		-- quick start, a long slowing; the last click comes in slow motion
		local e = 1 - (1 - u) ^ 3.2
		local angle = from + delta * e
		setWheel(angle)
		local peg = math.floor(angle / step)
		if peg ~= lastPeg then
			lastPeg = peg
			local late = u > 0.7
			if audible then
				play("UIClick", at, if late then 1.0 else 0.55, if late then 0.82 else 1.0)
			end
			flickTongue(if late then 16 else 9)
			if late and mine then
				shake(0.35)
			end
		end
		if u >= 1 then
			conn:Disconnect()
			wheelAngle = (from + delta) % 360
			done = true
		end
	end)
	while not done do
		task.wait()
	end
	-- the heavy stop and the warm lamp on the winning segment
	play("Land_Soft", at, if audible then 0.7 else 0, 0.7)
	local winLight = find({ "Wheel", "Lamp", "WinLight" }) :: SpotLight?
	if winLight then
		TweenService:Create(winLight, TweenInfo.new(0.25), { Brightness = 3 }):Play()
	end
	task.wait(0.3)
	if type(data.prize) == "table" then
		reveal(data.prize, "wheel", mine, token)
	end
	if winLight then
		TweenService:Create(winLight, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	end
	if mine then
		holdCamera(false)
		WheelController.holdUntil = 0
	end
	if revealToken == token then
		spinning = false
	end
	refreshPrompts()
end

local function onBox(data: { [string]: any })
	if type(data) ~= "table" or not corner then
		return
	end
	local mine = data.userId == player.UserId
	local token = revealToken + 1
	revealToken = token
	if mine then
		WheelController.holdUntil = os.clock() + 8
		holdCamera(true)
	end
	while now() < (tonumber(data.startAt) or 0) do
		task.wait()
	end
	if type(data.prize) == "table" then
		reveal(data.prize, data.kind or "strongbox", mine, token)
	end
	if mine then
		holdCamera(false)
		WheelController.holdUntil = 0
		refreshPrompts() -- the price line catches up with the Gold line
	end
end

-- The Armoury board ----------------------------------------------------------------------------------------------------------

local function sendAction(action: string, arg: any)
	if remote then
		remote:FireServer(action, arg)
	end
end

-- While your own wheel or box reveal plays, the board keeps the state from before the draw (its Gold total and the
-- weapon rows would give the prize away, as the Gold line would: CurrencyController), then catches up.
local boardState: any = nil
local boardWaiting = false

local function refreshBoard()
	if not board.gui then
		return
	end
	local held = os.clock() < WheelController.holdUntil and boardState ~= nil
	local state = if held then boardState else state
	if held then
		if not boardWaiting then
			boardWaiting = true
			task.spawn(function()
				while os.clock() < WheelController.holdUntil do
					task.wait(0.25)
				end
				boardWaiting = false
				refreshBoard()
			end)
		end
	else
		boardState = state
	end
	local cfg = Rewards.config()
	local armoury = state.armoury or {}
	board.gold.Text = if state.loaded then string.format("%s Gold", Rewards.comma(state.gold or 0)) else ""
	for _, id in ipairs(Rewards.Pool) do
		local row = board.rows[id]
		local owned = armoury[id] or 0
		row.name.Text = Rewards.weaponName(id)
		row.stars.Text = if owned > 0 then Rewards.starText(owned) else "—"
		row.stars.TextColor3 = if owned >= 4 then Color3.fromRGB(138, 92, 16) else Color3.fromRGB(35, 39, 43)
		row.bring.Visible = state.bring == id
		local text = ""
		if owned < 3 then
			text = string.format("BUY ★★★  %s", Rewards.comma(cfg.Armoury.Buy3))
		elseif owned == 3 then
			text = string.format("RAISE ★★★★  %s", Rewards.comma(cfg.Armoury.Raise4))
		elseif owned == 4 then
			text = string.format("RAISE ★★★★★  %s", Rewards.comma(cfg.Armoury.Raise5))
		end
		if row.confirmUntil and os.clock() < row.confirmUntil then
			text = "PRESS AGAIN  ·  " .. text
		end
		row.action.Text = text
		row.action.Visible = text ~= ""
	end
	local pity = state.pity or {}
	board.pity.Text = string.format("Strongboxes: ★★★★ or better within %d  ·  ★★★★★ within %d      The wheel: ★★★★ weapon within %d spins",
		pity.box4 or cfg.Strongbox.Pity4, pity.box5 or cfg.Strongbox.Pity5, pity.wheel4 or cfg.Wheel.Pity4)
	board.bringNote.Text = if state.bring and state.bring ~= "" then string.format("You bring your %s %s next round · it comes with your kit",
		Rewards.weaponName(state.bring), Rewards.starText(armoury[state.bring] or 0)) else "Click a weapon you own to bring it next round"
end

local function buildBoard()
	local face = find({ "Armoury", "Face" }) :: BasePart?
	if not face then
		return
	end
	local static = face:FindFirstChild("Static")
	local paperInk = Color3.fromRGB(35, 39, 43)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ArmouryLive"
	gui.Adornee = face
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(math.floor(face.Size.X * 200), math.floor(face.Size.Y * 200))
	gui.LightInfluence = 1
	gui.MaxDistance = 80
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local paper = Instance.new("Frame")
	paper.Name = "Paper"
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3 = Color3.fromRGB(234, 229, 217)
	paper.BorderSizePixel = 0
	paper.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 44)
	pad.PaddingRight = UDim.new(0, 44)
	pad.PaddingTop = UDim.new(0, 30)
	pad.Parent = paper
	local function text(name: string, parent: Instance, font: string, size: number, props: { [string]: any }): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.FontFace = (Theme.Fonts :: any)[font]
		l.TextSize = size
		l.TextColor3 = paperInk
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Center
		for k, v in pairs(props) do
			(l :: any)[k] = v
		end
		l.Parent = parent
		return l
	end
	text("Title", paper, "SemiBold", 50, { Text = "ARMOURY", Size = UDim2.new(0.5, 0, 0, 60) })
	board.gold = text("Gold", paper, "Medium", 40, { Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 0, 60), TextXAlignment = Enum.TextXAlignment.Right })
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = paperInk
	rule.BackgroundTransparency = 0.72
	rule.BorderSizePixel = 0
	rule.Position = UDim2.fromOffset(0, 70)
	rule.Size = UDim2.new(1, 0, 0, 2)
	rule.Parent = paper
	board.rows = {}
	local rowH = 72
	for i, id in ipairs(Rewards.Pool) do
		local y = 82 + (i - 1) * rowH
		local row = {}
		local nameButton = Instance.new("TextButton")
		nameButton.Name = "Name_" .. id
		nameButton.BackgroundTransparency = 1
		nameButton.AutoButtonColor = false
		nameButton.FontFace = Theme.Fonts.Medium
		nameButton.TextSize = 36
		nameButton.TextColor3 = paperInk
		nameButton.TextXAlignment = Enum.TextXAlignment.Left
		nameButton.Position = UDim2.fromOffset(0, y)
		nameButton.Size = UDim2.new(0.42, 0, 0, rowH)
		nameButton.Parent = paper
		row.name = nameButton
		row.bring = text("Bring_" .. id, paper, "SemiBold", 24, { Text = "BRING", Position = UDim2.new(0.33, 0, 0, y), Size = UDim2.new(0.1, 0, 0, rowH),
			TextColor3 = Color3.fromRGB(138, 92, 16), Visible = false })
		row.stars = text("Stars_" .. id, paper, "Medium", 34, { Text = "—", Position = UDim2.new(0.44, 0, 0, y), Size = UDim2.new(0.2, 0, 0, rowH) })
		local action = Instance.new("TextButton")
		action.Name = "Action_" .. id
		action.BackgroundTransparency = 1
		action.AutoButtonColor = false
		action.FontFace = Theme.Fonts.SemiBold
		action.TextSize = 26
		action.TextColor3 = paperInk
		action.TextXAlignment = Enum.TextXAlignment.Right
		action.AnchorPoint = Vector2.new(1, 0)
		action.Position = UDim2.new(1, 0, 0, y)
		action.Size = UDim2.new(0.36, 0, 0, rowH)
		action.Parent = paper
		row.action = action
		local line = Instance.new("Frame")
		line.BackgroundColor3 = paperInk
		line.BackgroundTransparency = 0.88
		line.BorderSizePixel = 0
		line.Position = UDim2.new(0, 0, 0, y + rowH - 2)
		line.Size = UDim2.new(1, 0, 0, 2)
		line.Parent = paper
		nameButton.Activated:Connect(function()
			local owned = (state.armoury or {})[id] or 0
			if owned > 0 then
				play("UIClick", face.Position, 0.5)
				sendAction("bring", if state.bring == id then "" else id)
			end
		end)
		action.Activated:Connect(function()
			if row.confirmUntil and os.clock() < row.confirmUntil then
				row.confirmUntil = nil
				local owned = (state.armoury or {})[id] or 0
				sendAction(if owned < 3 then "buy" else "raise", id)
				play("UIClick", face.Position, 0.7)
			else
				row.confirmUntil = os.clock() + 3
				play("UIHover", face.Position, 0.5)
				task.delay(3.05, refreshBoard)
			end
			refreshBoard()
		end)
		board.rows[id] = row
	end
	local footY = 82 + #Rewards.Pool * rowH + 10
	board.bringNote = text("BringNote", paper, "Medium", 26, { Text = "", Position = UDim2.fromOffset(0, footY), Size = UDim2.new(1, 0, 0, 34) })
	board.pity = text("Pity", paper, "Medium", 22, { Text = "", Position = UDim2.fromOffset(0, footY + 36), Size = UDim2.new(1, 0, 0, 30),
		TextTransparency = 0.3, TextWrapped = true })
	gui.Parent = player:WaitForChild("PlayerGui")
	board.gui = gui
	if static and static:IsA("SurfaceGui") then
		static.Enabled = false -- this client draws the live face (the built one stays for others' views without it)
	end
	refreshBoard()
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------------

local function onEvent(kind: any, data: any)
	if kind == "state" and type(data) == "table" then
		state = data
		refreshPrompts()
		refreshBoard()
	elseif kind == "spin" then
		task.spawn(onSpin, data)
	elseif kind == "box" then
		task.spawn(onBox, data)
	end
end

local function attach(root: Model)
	corner = root
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			local action = d:GetAttribute("RewardsAction")
			local kind = if action == "spin" then "spin" else d:GetAttribute("RewardsKind")
			if type(kind) == "string" then
				promptOwner[d] = kind
				d.Triggered:Connect(function()
					-- the server takes the Gold before its spin / box message arrives: hold the Gold line and the board
					-- from the press, so both keep the old total and change together when the reveal ends
					if (promptShort[d] or 0) <= 0 then
						WheelController.holdUntil = math.max(WheelController.holdUntil, os.clock() + 3)
					end
					if action == "spin" then
						sendAction("spin")
					else
						sendAction("box", kind)
					end
				end)
			end
		end
	end
	buildBoard()
	refreshPrompts()
end

function WheelController.Init(_controllers) end

function WheelController.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = remotes:WaitForChild("Rewards", 30) :: RemoteEvent?
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(onEvent)
	player:GetAttributeChangedSignal("Gold"):Connect(refreshPrompts)
	buildOddsGui()
	ProximityPromptService.PromptShown:Connect(onPromptShown)
	ProximityPromptService.PromptHidden:Connect(onPromptHidden)
	local lobby = workspace:WaitForChild("Lobby", 60)
	local root = lobby and lobby:WaitForChild("Rewards", 30)
	if root and root:IsA("Model") then
		attach(root)
	end
	remote:FireServer("state")
end

return WheelController
