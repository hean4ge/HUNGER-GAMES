--[[
	LootCueController - client cues for loot (docs/design/PlayabilityPlan.md QW8 and QW11). Client only.
	  * Take all (QW8): for a few seconds after a crate is opened, LootService puts a "Take all" prompt on it (tag
	    "TakeAllPrompt", attribute OwnerUserId). Only the contender who opened the crate sees it (it is disabled
	    locally for everyone else). While it is up, the items that crate spilled for them (attribute SpillOwner)
	    hide their own Take prompts, so one press of E takes everything; whatever doesn't fit stays on the ground.
	  * Crate outlines (QW11): with Guidance on (ClientState.guidanceOn: new players on Auto, Q1), during the first
	    Config.Loot.CrateOutlineTime seconds after the horn, an outline-only Highlight on the nearest CrateOutlineMax
	    unopened crates (tag SupplyCrate) within CrateOutlineRange studs, in your line of sight (Occluded). It fades
	    out over the last few seconds. Roblox draws at most 31 Highlights at once; this uses at most 8.
	API: LootCueController.getOutlined() -> { Model }   (the crates outlined right now)
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer
local LootCfg = Config.Loot

local TAKE_ALL_TAG = "TakeAllPrompt"
local ITEM_PROMPT_TAG = "LootPrompt"
local CRATE_TAG = "SupplyCrate"
local GROUND_TAG = "GroundItem"
local OUTLINE_COLOR = Color3.fromRGB(238, 228, 204)
local OUTLINE_TRANSPARENCY = 0.35
local OUTLINE_FADE = 5 -- seconds the outlines take to fade at the end of the window
local TICK = 0.2

local LootCueController = {}

local Controllers: any = nil
local myTakeAlls: { [ProximityPrompt]: boolean } = {}
local heldBack: { [ProximityPrompt]: boolean } = {} -- item prompts disabled locally while Take all is up
local outlines: { [Model]: Highlight } = {}
local warned = false

-- Take all ---------------------------------------------------------------------------------------------------------------

local function ownerOf(prompt: Instance): number?
	return tonumber(prompt:GetAttribute("OwnerUserId"))
end

local function spilledForMe(prompt: Instance): boolean
	local model = prompt:FindFirstAncestorOfClass("Model")
	return model ~= nil and CollectionService:HasTag(model, GROUND_TAG) and model:GetAttribute("SpillOwner") == player.UserId
end

local function holdBack(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt.Enabled and spilledForMe(prompt) then
		prompt.Enabled = false
		heldBack[prompt] = true
	end
end

local function refreshItemPrompts()
	if next(myTakeAlls) ~= nil then
		for _, prompt in ipairs(CollectionService:GetTagged(ITEM_PROMPT_TAG)) do
			holdBack(prompt)
		end
	else
		for prompt in pairs(heldBack) do
			if prompt.Parent then
				prompt.Enabled = true
			end
		end
		table.clear(heldBack)
	end
end

local function applyTakeAll(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	if ownerOf(prompt) ~= player.UserId then
		prompt.Enabled = false -- someone else's crate: only its opener can take all
		myTakeAlls[prompt] = nil
		return
	end
	local range = tonumber(prompt:GetAttribute("Range"))
	if range then
		prompt.MaxActivationDistance = if ClientState.alive then range else 0
	end
	myTakeAlls[prompt] = true
	refreshItemPrompts()
end

local function onTakeAllRemoved(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and myTakeAlls[prompt] then
		myTakeAlls[prompt] = nil
		refreshItemPrompts()
	end
end

local function onItemPrompt(prompt: Instance)
	if next(myTakeAlls) ~= nil then
		-- an item that landed while Take all is up waits its turn (its model and attributes arrive with it)
		task.defer(holdBack, prompt)
	end
end

-- Drop prompts whose time is up even if their removal hasn't replicated yet.
local function pruneTakeAlls()
	local now = workspace:GetServerTimeNow()
	local changed = false
	for prompt in pairs(myTakeAlls) do
		local untilAt = tonumber(prompt:GetAttribute("Until"))
		if not prompt.Parent or (untilAt and now > untilAt + 0.5) then
			myTakeAlls[prompt] = nil
			changed = true
		end
	end
	if changed then
		refreshItemPrompts()
	end
end

-- Crate outlines -------------------------------------------------------------------------------------------------------

local function guidanceOn(): boolean
	local fn = (ClientState :: any).guidanceOn
	if type(fn) == "function" then
		local ok, on = pcall(fn)
		if ok then
			return on == true
		end
	end
	return player:GetAttribute("NewPlayer") == true
end

-- 0..1 strength of the outlines now (0 = none)
local function outlineStrength(): number
	if LootCfg.CrateOutline == false then
		return 0
	end
	if GameState:GetAttribute("Phase") ~= "Active" or not ClientState.inArena or not ClientState.alive or ClientState.spectating then
		return 0
	end
	local startedAt = tonumber(GameState:GetAttribute("RoundStartedAt")) or 0
	if startedAt <= 0 then
		return 0
	end
	local window = tonumber(LootCfg.CrateOutlineTime) or 90
	local left = window - (workspace:GetServerTimeNow() - startedAt)
	if left <= 0 or not guidanceOn() then
		return 0
	end
	return math.clamp(left / OUTLINE_FADE, 0, 1)
end

local function updateOutlines()
	local strength = outlineStrength()
	local keep: { [Model]: boolean } = {}
	if strength > 0 then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local range = tonumber(LootCfg.CrateOutlineRange) or 25
			local most = math.clamp(math.floor(tonumber(LootCfg.CrateOutlineMax) or 8), 0, 24)
			local near = {}
			for _, crate in ipairs(CollectionService:GetTagged(CRATE_TAG)) do
				if crate:IsA("Model") and crate:GetAttribute("Opened") ~= true and crate:IsDescendantOf(workspace) then
					local d = (crate:GetPivot().Position - root.Position).Magnitude
					if d <= range then
						table.insert(near, { crate = crate, d = d })
					end
				end
			end
			table.sort(near, function(a, b)
				return a.d < b.d
			end)
			for i = 1, math.min(most, #near) do
				keep[near[i].crate] = true
			end
		end
	end
	for crate, highlight in pairs(outlines) do
		if not keep[crate] or not highlight.Parent then
			highlight:Destroy()
			outlines[crate] = nil
		end
	end
	local transparency = 1 - (1 - OUTLINE_TRANSPARENCY) * strength
	for crate in pairs(keep) do
		local highlight = outlines[crate]
		if not highlight then
			highlight = Instance.new("Highlight")
			highlight.Name = "CrateOutline"
			highlight.Adornee = crate
			highlight.FillTransparency = 1
			highlight.OutlineColor = OUTLINE_COLOR
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Parent = crate -- client-local; goes with the crate
			outlines[crate] = highlight
		end
		if math.abs(highlight.OutlineTransparency - transparency) > 0.01 then
			highlight.OutlineTransparency = transparency
		end
	end
end

-- Public API -------------------------------------------------------------------------------------------------------------

function LootCueController.getOutlined(): { Model }
	local list = {}
	for crate in pairs(outlines) do
		table.insert(list, crate)
	end
	return list
end

-- Lifecycle --------------------------------------------------------------------------------------------------------------

function LootCueController.Init(registry)
	Controllers = registry
end

function LootCueController.Start()
	CollectionService:GetInstanceAddedSignal(TAKE_ALL_TAG):Connect(applyTakeAll)
	CollectionService:GetInstanceRemovedSignal(TAKE_ALL_TAG):Connect(onTakeAllRemoved)
	for _, prompt in ipairs(CollectionService:GetTagged(TAKE_ALL_TAG)) do
		applyTakeAll(prompt)
	end
	CollectionService:GetInstanceAddedSignal(ITEM_PROMPT_TAG):Connect(onItemPrompt)
	ClientState.lifeChanged:Connect(function()
		for prompt in pairs(myTakeAlls) do
			applyTakeAll(prompt)
		end
	end)
	while true do
		task.wait(TICK)
		local ok, err = pcall(function()
			pruneTakeAlls()
			updateOutlines()
		end)
		if not ok and not warned then
			warned = true
			warn("[LootCueController] " .. tostring(err))
		end
	end
end

return LootCueController
