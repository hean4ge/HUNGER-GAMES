--[[
	PlusController - Roblox Plus (Roblox's own subscription) in the lobby: the client half. PlusService is the server half.

	Everything it draws lives inside the Lobby screen (PlayerGui.Lobby, LobbyController's), so it is on show only when
	the lobby is: never in the arena, on the death or result card, or while spectating.
	  * "ROBLOX PLUS": one quiet text button at the end of the lobby's button row (SETTINGS, HOW TO PLAY). Dim text
	    on a soft backing, no outline, no motion, no sound, no counter. Shown only when the server says so
	    (PlusService: not a member, allowed to buy subscriptions, the API exists). Nothing opens by itself.
	  * Pressing it opens a small panel of the game's own words saying exactly what a member gets here, with SUBSCRIBE
	    and CLOSE. SUBSCRIBE asks the server to open Roblox's own window (no price in our text; theirs shows it).
	  * A member sees "PLUS MEMBER" in the button's place.
	  * The member perk, cosmetic and lobby-only: other players read "<name>  ·  PLUS" on a member's name tag. Name
	    tags are off in the arena (PlayerService), so nothing shows in a round. The change is local to each client.
	  * "PRIVATE SERVER" above the title when GameState.PrivateServer is true (RoundService).
	If the Lobby screen or the remote is missing, the part that needs it does not run.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local C = Theme.Colors

local PlusController = {}
local Controllers: any = nil

local REMOTE_NAME = "PlusSubscribe"
local PRESS_COOLDOWN = 10 -- matches PlusService.PROMPT_COOLDOWN
local MARK = "  ·  PLUS"

local PANEL_TEXT = table.concat({
	"Roblox Plus is Roblox's own membership. It is optional, and it changes nothing about how a round plays: "
		.. "no weapons, no supplies, no head start.",
	"In this game a member gets one thing: a PLUS mark beside their name in the lobby.",
	"SUBSCRIBE opens Roblox's own window, which has the details. If you subscribe from here, Roblox pays this "
		.. "game's creator a bonus. Not an adult? Ask a parent or guardian first.",
}, "\n\n")

local lobby: ScreenGui? = nil
local R: { [string]: any } = {}
local offer = false
local panelOpen = false
local lastPress = -math.huge

---------------------------------------------------------------------------------------------------------------------
-- The member perk: a mark on other members' lobby name tags

local function applyName(other: Player)
	if other == player then
		return
	end
	local character = other.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local plain = other.DisplayName
	local marked = plain .. MARK
	if other:GetAttribute("PlusMember") == true then
		if humanoid.DisplayName ~= marked then
			humanoid.DisplayName = marked
		end
	elseif humanoid.DisplayName == marked then
		humanoid.DisplayName = plain
	end
end

local function watchCharacter(other: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or other.Character ~= character then
		return
	end
	applyName(other)
	-- the name arrives from the server with the character and can land after ours: put the mark back
	humanoid:GetPropertyChangedSignal("DisplayName"):Connect(function()
		applyName(other)
	end)
end

local function watchPlayer(other: Player)
	if other == player then
		return
	end
	other:GetAttributeChangedSignal("PlusMember"):Connect(function()
		applyName(other)
	end)
	other.CharacterAdded:Connect(function(character)
		watchCharacter(other, character)
	end)
	if other.Character then
		task.spawn(watchCharacter, other, other.Character)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Lobby parts

local function newLabel(name: string, text: string, fontKey: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	Theme.text(label, fontKey, size)
	label.TextColor3 = color
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.BorderSizePixel = 0
	return label
end

local function newButton(name: string, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	Theme.text(button, "Heading", Theme.TextSize.Label)
	button.Text = text
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.fromOffset(0, 34)
	local pad = Instance.new("UIPadding")
	pad.Name = "Pad"
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = button
	return button
end

local function fillButton(button: TextButton)
	button.BackgroundColor3 = C.Panel
	button.BackgroundTransparency = Theme.Transparency.Panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerPill
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Stroke
	stroke.Transparency = 0.8
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0.15
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = Theme.Transparency.Panel
	end)
end

local function overlaps(a: GuiObject, b: GuiObject): boolean
	local ap, as, bp, bs = a.AbsolutePosition, a.AbsoluteSize, b.AbsolutePosition, b.AbsoluteSize
	return ap.X < bp.X + bs.X and bp.X < ap.X + as.X and ap.Y < bp.Y + bs.Y and bp.Y < ap.Y + as.Y
end

local function setPanel(open: boolean)
	local panel = R.panel
	if not panel or open == panelOpen then
		return
	end
	panelOpen = open
	panel.Visible = open
	if open then
		-- HOW TO PLAY sits in the middle on phones: it steps aside rather than share the place
		task.defer(function()
			local howTo = R.howTo
			local lobbyController = Controllers and Controllers.LobbyController
			if panelOpen and howTo and howTo.Visible and overlaps(panel, howTo) and lobbyController
				and lobbyController.setHowToVisible then
				pcall(lobbyController.setHowToVisible, false)
			end
		end)
	end
end

local function refresh()
	local member = player:GetAttribute("PlusMember") == true
	if R.button then
		R.button.Visible = offer and not member
	end
	if R.memberTag then
		R.memberTag.Visible = member
	end
	if panelOpen and (member or not offer) then
		setPanel(false)
	end
end

-- a headline, the Roll Call, a card or the menu has the screen: the panel goes rather than sit under or over it
local function mustYield(): boolean
	if not lobby or not lobby.Enabled or ClientState.menuOpen or ClientState.inArena or ClientState.spectating ~= nil then
		return true
	end
	local notifications = Controllers and Controllers.NotificationController
	if notifications and notifications.isBannerUp then
		local ok, headline, roll = pcall(notifications.isBannerUp)
		if ok and (headline == true or roll == true) then
			return true
		end
	end
	return false
end

local function buildPrivateLabel(brand: Instance)
	local GameState = ReplicatedStorage:FindFirstChild("GameState")
	if not GameState then
		return
	end
	local label = newLabel("PrivateServer", "PRIVATE SERVER", "Heading", Theme.TextSize.Label, C.Text)
	label.LayoutOrder = 0
	label.Size = UDim2.new(1, 0, 0, 18)
	local shadow = Instance.new("UIStroke")
	shadow.Name = "Shadow"
	shadow.Color = C.Shadow
	shadow.Transparency = 0.45
	shadow.Thickness = 1
	shadow.Parent = label
	local function apply()
		label.Visible = GameState:GetAttribute("PrivateServer") == true
	end
	GameState:GetAttributeChangedSignal("PrivateServer"):Connect(apply)
	apply()
	label.Parent = brand
end

local function buildPanel(root: Instance, remote: RemoteEvent)
	local panel = Instance.new("Frame")
	panel.Name = "PlusPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(360, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Active = true -- clicks on it do not reach the world
	panel.Visible = false
	panel.ZIndex = 5
	Theme.panel(panel, Theme.Transparency.PanelStrong)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 14), UDim.new(0, 16)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = panel

	local title = newLabel("Title", "ROBLOX PLUS", "Heading", Theme.TextSize.Heading, C.Text)
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.ZIndex = 5
	title.Parent = panel

	local body = newLabel("Body", PANEL_TEXT, "Body", 15, C.Text)
	body.LayoutOrder = 2
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LineHeight = 1.1
	body.ZIndex = 5
	body.Parent = panel

	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.LayoutOrder = 3
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, 34)
	actions.ZIndex = 5
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 8)
	row.Parent = actions
	actions.Parent = panel

	local subscribe = newButton("Subscribe", "SUBSCRIBE")
	subscribe.LayoutOrder = 1
	subscribe.ZIndex = 5
	fillButton(subscribe)
	subscribe.Parent = actions
	local close = newButton("Close", "CLOSE")
	close.LayoutOrder = 2
	close.ZIndex = 5
	fillButton(close)
	close.Parent = actions

	subscribe.Activated:Connect(function()
		local now = os.clock()
		if not offer or now - lastPress < PRESS_COOLDOWN then
			setPanel(false)
			return
		end
		lastPress = now
		setPanel(false) -- Roblox's window takes over from here
		remote:FireServer("subscribe")
	end)
	close.Activated:Connect(function()
		setPanel(false)
	end)

	R.panel = panel
	panel.Parent = root
end

local function buildButton(buttons: Instance)
	local button = newButton("Plus", "ROBLOX PLUS")
	button.LayoutOrder = 3
	button.TextColor3 = C.TextDim
	button.Visible = false
	-- a soft dark backing and no outline: readable over bright ground, quieter than SETTINGS and HOW TO PLAY
	button.BackgroundColor3 = C.Panel
	button.BackgroundTransparency = Theme.Transparency.PanelSoft
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerPill
	corner.Parent = button
	button:FindFirstChild("Pad").PaddingLeft = UDim.new(0, 12)
	button:FindFirstChild("Pad").PaddingRight = UDim.new(0, 12)
	button.MouseEnter:Connect(function()
		button.TextColor3 = C.Text
	end)
	button.MouseLeave:Connect(function()
		button.TextColor3 = C.TextDim
	end)
	button.SelectionGained:Connect(function()
		button.TextColor3 = C.Text
	end)
	button.SelectionLost:Connect(function()
		button.TextColor3 = C.TextDim
	end)
	button.Activated:Connect(function()
		if panelOpen then
			setPanel(false)
		elseif offer and not mustYield() then
			setPanel(true)
		end
	end)
	R.button = button
	button.Parent = buttons

	local tag = newLabel("PlusMember", "PLUS MEMBER", "Heading", Theme.TextSize.Label, C.Gold)
	tag.LayoutOrder = 4
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.Size = UDim2.fromOffset(0, 34)
	tag.Visible = false
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = tag
	R.memberTag = tag
	tag.Parent = buttons
end

function PlusController.Init(registry)
	Controllers = registry
end

function PlusController.Start()
	for _, other in ipairs(Players:GetPlayers()) do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("Lobby", 30)
	local root = gui and gui:WaitForChild("Root", 10)
	local brand = root and root:WaitForChild("Brand", 10)
	local buttons = brand and brand:WaitForChild("Buttons", 10)
	if not (gui and gui:IsA("ScreenGui") and root and brand and buttons) then
		return
	end
	lobby = gui
	R.howTo = root:FindFirstChild("HowTo")

	buildPrivateLabel(brand)
	buildButton(buttons)
	player:GetAttributeChangedSignal("PlusMember"):Connect(refresh)
	refresh()

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local remote = remotes and remotes:WaitForChild(REMOTE_NAME, 30)
	if not remote or not remote:IsA("RemoteEvent") then
		return -- no PlusService on this server: no button, the rest stands
	end
	buildPanel(root, remote)
	remote.OnClientEvent:Connect(function(what: any, value: any)
		if what == "state" then
			offer = value == true
			refresh()
		end
	end)
	remote:FireServer("state")

	while true do
		task.wait(0.25)
		if panelOpen and mustYield() then
			setPanel(false)
		end
	end
end

return PlusController
