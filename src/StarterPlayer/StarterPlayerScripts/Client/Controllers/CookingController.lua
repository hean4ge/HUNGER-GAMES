--[[
	CookingController - campfires and cooking: the client half (CookingService decides everything).
	Numbers: Shared.WildlifeConfig.Campfire. Looks: Shared.CreatureLooks (newCampfire / setCampfire / setSpit).

	What it shows
	  Fires: every Configuration under ReplicatedStorage.Campfires within DrawDistance (the nearest DrawCount[tier])
	  is drawn here as a local Model under workspace.ClientCampfires: stones, logs, a spit; while lit a flame, sparks,
	  a warm light and a smoke column that stands about 60 studs and shows from far off. Out: ashes and a thin
	  smoke. The map's streaming never touches them.
	  Prompts (ProximityPrompts, so a phone taps them; plain default style, the UI owners restyle them):
	    at a tree trunk you look at, close:  "Gather sticks"  [F] hold GatherHold      (not while climbing)
	    holding Firewood, at the ground:     "Build fire"     [E] hold BuildHold  (a faint ghost shows where)
	    at a fire (PromptRange):
	      Unlit:  "Light fire" [E]        "Kick apart" [X]
	      Lit:    "Cook <raw item>" [E] (a raw item in the bag, the spit empty) or "Take <item>" [E] (something on
	              the spit), "Add firewood" [F] (Firewood in the bag), "Put out" [X]
	      Out:    "Take <item>" [E] when something was left on the spit
	    Gamepad: E = ButtonX, F = ButtonY, X = DPadDown.
	  Over the spit, plain white text: "Cooking 4" counting down, then "Cooked Squirrel - ready".
	Everything it sends goes through ReplicatedStorage.Remotes.CampAction; the server checks range, state and items.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureLooks = require(Shared:WaitForChild("CreatureLooks"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local WildlifeConfig = require(Shared:WaitForChild("WildlifeConfig"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local CF = WildlifeConfig.Campfire
local player = Players.LocalPlayer
local GameState = ReplicatedStorage:WaitForChild("GameState")

local CookingController = {}

local KEY_MAIN = { Enum.KeyCode.E, Enum.KeyCode.ButtonX }
local KEY_SECOND = { Enum.KeyCode.F, Enum.KeyCode.ButtonY }
local KEY_THIRD = { Enum.KeyCode.X, Enum.KeyCode.DPadDown }

type View = {
	inst: Configuration,
	id: number,
	fire: any?, -- CreatureLooks Fire while drawn
	main: ProximityPrompt?,
	second: ProximityPrompt?,
	third: ProximityPrompt?,
	mainAction: string?,
	conns: { RBXScriptConnection },
	dist: number,
}

local views: { [Configuration]: View } = {}
local remote: RemoteEvent? = nil
local folder: Folder? = nil
local drawCount = CF.DrawCount.Medium
local smokeRate = CF.SmokeRate.Medium

local function send(action: string, value: any)
	local r = remote
	if r then
		r:FireServer(action, value)
	end
end

local function ensureFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local created = Instance.new("Folder")
	created.Name = "ClientCampfires"
	created.Parent = workspace
	folder = created
	return created
end

local function readTier()
	local name = player:GetAttribute("DetailTier")
	local key = if type(name) == "string" and CF.DrawCount[name] then name else "Medium"
	drawCount = CF.DrawCount[key]
	smokeRate = CF.SmokeRate[key]
end

local function canAct(): boolean
	return ClientState.alive == true and GameState:GetAttribute("Phase") == "Active" and ClientState.frozen ~= true
end

local function bagCount(itemId: string): number
	local total = 0
	local inv = ClientState.inventory
	for _, slot in pairs(inv and inv.slots or {}) do
		if type(slot) == "table" and slot.id == itemId then
			total += tonumber(slot.count) or 1
		end
	end
	return total
end

local function heldId(): string?
	local inv = ClientState.inventory
	if not inv or not inv.equipped or inv.equipped == 0 then
		return nil
	end
	local slot = inv.slots[inv.equipped]
	return if type(slot) == "table" then slot.id else nil
end

-- the raw thing to cook: the held one first, else the first in the bag
local function cookable(): string?
	local held = heldId()
	local def = ItemDefs.get(held)
	if def and def.cooksInto and ItemDefs.get(def.cooksInto) then
		return held
	end
	local inv = ClientState.inventory
	for _, slot in ipairs(inv and inv.slots or {}) do
		if type(slot) == "table" then
			local d = ItemDefs.get(slot.id)
			if d and d.cooksInto and ItemDefs.get(d.cooksInto) then
				return slot.id
			end
		end
	end
	return nil
end

local function itemName(itemId: string?): string
	local def = ItemDefs.get(itemId)
	return if def then def.name else "it"
end

local function newPrompt(parent: Instance, keys: { Enum.KeyCode }, hold: number, name: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.KeyboardKeyCode = keys[1]
	prompt.GamepadKeyCode = keys[2]
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = CF.PromptRange
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.ObjectText = "Campfire"
	prompt.Enabled = false
	prompt.Parent = parent
	return prompt
end

--------------------------------------------------------------------------------------------------------------------
-- Fires
--------------------------------------------------------------------------------------------------------------------

local function firePosition(inst: Configuration): Vector3?
	local p = inst:GetAttribute("Position")
	return if typeof(p) == "Vector3" then p else nil
end

local function refreshPrompts(view: View)
	local fire = view.fire
	if not fire then
		return
	end
	local inst = view.inst
	local state = inst:GetAttribute("State")
	local spit = inst:GetAttribute("Spit")
	local done = tonumber(inst:GetAttribute("SpitDone")) or 0
	local hasSpit = type(spit) == "string" and spit ~= ""
	local able = canAct()
	local main, second, third = view.main, view.second, view.third
	if not (main and second and third) then
		return
	end
	-- main: Light / Cook / Take
	local mainAction, mainText = nil, ""
	if state == "Unlit" then
		mainAction, mainText = "Light", "Light fire"
	elseif hasSpit then
		local cooked = done > 0 and workspace:GetServerTimeNow() >= done
		mainAction = "Take"
		mainText = "Take " .. string.lower(itemName(if cooked then inst:GetAttribute("SpitResult") else spit))
	elseif state == "Lit" then
		local raw = cookable()
		if raw then
			mainAction, mainText = "Cook", "Cook " .. string.lower(itemName(raw))
		end
	end
	view.mainAction = mainAction
	main.Enabled = able and mainAction ~= nil
	if mainAction then
		main.ActionText = mainText
		main.HoldDuration = if mainAction == "Light" then CF.LightHold elseif mainAction == "Cook" then 0.5 else 0
	end
	second.Enabled = able and state == "Lit" and bagCount(CF.FirewoodItem) > 0
	second.ActionText = "Add firewood"
	third.Enabled = able and (state == "Lit" or state == "Unlit")
	third.ActionText = if state == "Unlit" then "Kick apart" else "Put out"
end

local function refreshLabel(view: View)
	local fire = view.fire
	if not fire then
		return
	end
	local inst = view.inst
	local spit = inst:GetAttribute("Spit")
	local done = tonumber(inst:GetAttribute("SpitDone")) or 0
	local hasSpit = type(spit) == "string" and spit ~= ""
	local t = workspace:GetServerTimeNow()
	local cooked = hasSpit and done > 0 and t >= done
	CreatureLooks.setSpit(fire, if hasSpit then spit else nil, cooked)
	local board = fire.label.Parent :: BillboardGui
	if not hasSpit then
		board.Enabled = false
		return
	end
	board.Enabled = true
	if cooked then
		fire.label.Text = itemName(inst:GetAttribute("SpitResult")) .. " - ready"
	elseif done > 0 then
		fire.label.Text = string.format("Cooking %d", math.max(1, math.ceil(done - t)))
	else
		fire.label.Text = itemName(spit) .. " - still raw"
	end
end

local function applyState(view: View)
	local fire = view.fire
	if not fire then
		return
	end
	local state = view.inst:GetAttribute("State")
	CreatureLooks.setCampfire(fire, if type(state) == "string" then state else "Unlit", smokeRate)
	fire.light.Brightness = if state == "Lit" then CF.LightBrightness else 0
	fire.light.Range = CF.LightRange
	-- a lit fire crackles: AudioController's 3D emitters (AmbientEmitter tag, SoundKey Emit_Fire)
	local holder = fire.light.Parent
	if holder and (holder:IsA("BasePart") or holder:IsA("Attachment")) then
		if state == "Lit" then
			holder:SetAttribute("SoundKey", "Emit_Fire")
			CollectionService:AddTag(holder, "AmbientEmitter")
		else
			CollectionService:RemoveTag(holder, "AmbientEmitter")
		end
	end
	refreshLabel(view)
	refreshPrompts(view)
end

local function undraw(view: View)
	local fire = view.fire
	if fire then
		view.fire = nil
		fire.model:Destroy()
	end
	view.main, view.second, view.third = nil, nil, nil
end

local function draw(view: View)
	if view.fire then
		return
	end
	local p = firePosition(view.inst)
	if not p then
		return
	end
	local fire = CreatureLooks.newCampfire()
	local yaw = tonumber(view.inst:GetAttribute("Yaw")) or 0
	fire.model:PivotTo(CFrame.new(p) * CFrame.Angles(0, yaw, 0))
	fire.model.Parent = ensureFolder()
	view.fire = fire
	local main = newPrompt(fire.prompts, KEY_MAIN, 0, "CampMain")
	local second = newPrompt(fire.prompts, KEY_SECOND, 0.6, "CampFeed")
	local third = newPrompt(fire.prompts, KEY_THIRD, CF.PutOutHold, "CampOut")
	view.main, view.second, view.third = main, second, third
	main.Triggered:Connect(function()
		if view.mainAction then
			send(view.mainAction, view.id)
		end
	end)
	second.Triggered:Connect(function()
		send("Feed", view.id)
	end)
	third.Triggered:Connect(function()
		send("PutOut", view.id)
	end)
	applyState(view)
end

local function addFire(inst: Instance)
	if not inst:IsA("Configuration") or views[inst] then
		return
	end
	local id = tonumber(inst.Name)
	if not id then
		return
	end
	local view: View = { inst = inst, id = id, conns = {}, dist = math.huge }
	views[inst] = view
	table.insert(view.conns, inst.AttributeChanged:Connect(function()
		applyState(view)
	end))
end

local function removeFire(inst: Instance)
	local view = views[inst :: any]
	if not view then
		return
	end
	views[inst :: any] = nil
	for _, c in ipairs(view.conns) do
		c:Disconnect()
	end
	undraw(view)
end

-- Twice a second: which fires are drawn (the nearest DrawCount within DrawDistance).
local function chooseFires(focus: Vector3)
	local list: { View } = {}
	local far = CF.DrawDistance * CF.DrawDistance
	for _, view in pairs(views) do
		local p = firePosition(view.inst)
		if p then
			local d = p - focus
			view.dist = d:Dot(d)
			if view.dist <= far then
				table.insert(list, view)
			else
				undraw(view)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	for index, view in ipairs(list) do
		if index <= drawCount then
			draw(view)
			refreshLabel(view)
			refreshPrompts(view)
		else
			undraw(view)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Gathering sticks and building
--------------------------------------------------------------------------------------------------------------------

local spot: Part? = nil
local gatherPrompt: ProximityPrompt? = nil
local buildPrompt: ProximityPrompt? = nil
local gatherPoint: Vector3? = nil
local buildPoint: Vector3? = nil
local ghost: any = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

local function isTrunk(part: Instance?): boolean
	if not part or not part:IsA("BasePart") then
		return false
	end
	if string.sub(part.Name, -5) == "_Bark" or part.Name == "Trunk" then
		return true
	end
	return CollectionService:HasTag(part, "Climbable") and string.find(part.Name, "Ladder", 1, true) == nil
end

local function ensureSpot(): Part
	local s = spot
	if s and s.Parent then
		return s
	end
	local part = Instance.new("Part")
	part.Name = "CampPromptSpot"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = ensureFolder()
	spot = part
	local gather = Instance.new("ProximityPrompt")
	gather.Name = "GatherSticks"
	gather.ActionText = "Gather sticks"
	gather.ObjectText = "Tree"
	gather.KeyboardKeyCode = KEY_SECOND[1]
	gather.GamepadKeyCode = KEY_SECOND[2]
	gather.HoldDuration = CF.GatherHold
	gather.MaxActivationDistance = CF.GatherRange + 4
	gather.RequiresLineOfSight = false
	gather.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	gather.Enabled = false
	local gatherAt = Instance.new("Attachment")
	gatherAt.Name = "GatherAt"
	gatherAt.Parent = part
	gather.Parent = gatherAt
	gather.Triggered:Connect(function()
		if gatherPoint then
			send("Gather", gatherPoint)
		end
	end)
	gatherPrompt = gather
	local build = Instance.new("ProximityPrompt")
	build.Name = "BuildFire"
	build.ActionText = "Build fire"
	build.ObjectText = "Firewood"
	build.KeyboardKeyCode = KEY_MAIN[1]
	build.GamepadKeyCode = KEY_MAIN[2]
	build.HoldDuration = CF.BuildHold
	build.MaxActivationDistance = CF.BuildRange + 6
	build.RequiresLineOfSight = false
	build.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	build.Enabled = false
	local buildAt = Instance.new("Attachment")
	buildAt.Name = "BuildAt"
	buildAt.Parent = part
	build.Parent = buildAt
	build.Triggered:Connect(function()
		if buildPoint then
			send("Build", buildPoint)
		end
	end)
	buildPrompt = build
	return part
end

local function showGhost(at: Vector3?)
	if not at then
		if ghost then
			ghost.model.Parent = nil
		end
		return
	end
	if not ghost then
		ghost = CreatureLooks.newCampfire()
		for _, d in ipairs(ghost.model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0.6
				d.CastShadow = false
			end
		end
		CreatureLooks.setCampfire(ghost, "Unlit", 0)
	end
	ghost.model.Parent = ensureFolder()
	ghost.model:PivotTo(CFrame.new(at))
end

local function nearFire(p: Vector3): boolean
	for _, view in pairs(views) do
		local q = firePosition(view.inst)
		if q and (q - p).Magnitude < CF.MinSpacing then
			return true
		end
	end
	return false
end

local function updateWorkPrompts()
	local part = ensureSpot()
	local gather, build = gatherPrompt :: ProximityPrompt, buildPrompt :: ProximityPrompt
	gatherPoint, buildPoint = nil, nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not (canAct() and root and root:IsA("BasePart") and camera) or ClientState.menuOpen then
		gather.Enabled, build.Enabled = false, false
		showGhost(nil)
		return
	end
	local exclude: { Instance } = { character :: Instance, ensureFolder() }
	local wildlife = workspace:FindFirstChild("ClientWildlife")
	if wildlife then
		table.insert(exclude, wildlife)
	end
	rayParams.FilterDescendantsInstances = exclude
	local look = camera.CFrame
	local hit = workspace:Raycast(look.Position, look.LookVector * (CF.GatherRange + 12), rayParams)

	-- Gather: looking at a trunk, close
	local firewoodDef = ItemDefs.get(CF.FirewoodItem)
	local full = bagCount(CF.FirewoodItem) >= ((firewoodDef and firewoodDef.stack) or 2)
	local climbing = ClientState.moveState == "Climb"
	local gatherAt = (gather.Parent :: Attachment)
	if hit and not full and not climbing and isTrunk(hit.Instance) and (hit.Position - root.Position).Magnitude <= CF.GatherRange then
		gatherPoint = hit.Position
		gatherAt.WorldPosition = hit.Position + hit.Normal * 0.4
		gather.Enabled = true
	else
		gather.Enabled = false
	end

	-- Build: holding Firewood, looking at open ground near you
	local def = ItemDefs.get(heldId())
	local spotAt: Vector3? = nil
	if def and def.builds then
		local target: Vector3
		if hit and (hit.Position - root.Position).Magnitude <= CF.BuildRange and hit.Normal.Y >= CF.MaxSlope then
			target = hit.Position
		else
			local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
			flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			target = root.Position + flat * 4
		end
		groundParams.FilterDescendantsInstances = { workspace.Terrain }
		local down = workspace:Raycast(target + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), groundParams)
		if down and down.Material ~= Enum.Material.Water and down.Normal.Y >= CF.MaxSlope and not nearFire(down.Position)
			and math.abs(down.Position.Y - root.Position.Y) < 8 then
			spotAt = down.Position
		end
	end
	if spotAt then
		buildPoint = spotAt
		local buildAt = (build.Parent :: Attachment)
		buildAt.WorldPosition = spotAt + Vector3.new(0, 1, 0)
		build.Enabled = true
	else
		build.Enabled = false
	end
	showGhost(spotAt)
	local _ = part -- (the part stays at the origin; its attachments are placed in world space)
end

--------------------------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------------------------

function CookingController.Init(_controllers)
	readTier()
	player:GetAttributeChangedSignal("DetailTier"):Connect(function()
		readTier()
		for _, view in pairs(views) do
			applyState(view)
		end
	end)
end

function CookingController.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local r = remotes:WaitForChild("CampAction", 60)
	if r and r:IsA("RemoteEvent") then
		remote = r
	else
		warn("[Cooking] no CampAction remote: campfires are off")
		return
	end
	local fires = ReplicatedStorage:WaitForChild("Campfires", 60)
	if fires then
		for _, inst in ipairs(fires:GetChildren()) do
			addFire(inst)
		end
		fires.ChildAdded:Connect(addFire)
		fires.ChildRemoved:Connect(removeFire)
	end
	local function refreshAll()
		for _, view in pairs(views) do
			refreshPrompts(view)
		end
	end
	if ClientState.inventoryChanged then
		ClientState.inventoryChanged:Connect(refreshAll)
	end
	if ClientState.equippedChanged then
		ClientState.equippedChanged:Connect(refreshAll)
	end
	local sinceChoose = 1
	while true do
		local dt = task.wait(0.2)
		local ok, err = pcall(updateWorkPrompts)
		if not ok then
			warn("[Cooking] prompts: " .. tostring(err))
		end
		sinceChoose += dt
		if sinceChoose >= 0.5 then
			sinceChoose = 0
			local camera = workspace.CurrentCamera
			local focus = if camera then camera.CFrame.Position else Vector3.zero
			local ok2, err2 = pcall(chooseFires, focus)
			if not ok2 then
				warn("[Cooking] fires: " .. tostring(err2))
			end
		end
	end
end

return CookingController
