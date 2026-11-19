--[[
	SkillController - the local player's two skills (docs/design/Combat_v3.md section 2). Client only.

	Binds SkillWeapon (R, D-pad left, touch: a round button above ATTACK) and SkillGeneral (F, D-pad right, touch: the
	other round button) through Shared.Input (Input.ACTIONS), only while alive in the arena and not spectating. F passes
	through to a fire's F prompt while one shows (CookingController's prompts win).
	A press is checked here against what the server published (Player attributes SkillWeaponReadyAt,
	SkillGeneralReadyAt, SkillsOpenAt, SkillGeneral, SkillSpecialty: SkillService) and sent as MeleeSwing("Skill", slot,
	serverTime, look). The local part plays at once: Head Kick and the chained strikes are swings
	(CombatController.playSkillMove, each strike checked by the server as any blow), Running Cut and Vault Kick move
	the body (CombatController.driveBody), Whirl and the rest hold the hands for their length; CombatController.action
	fires "Skill" { id, slot, t0, total } for the views (ViewmodelController, CharacterVisuals).
	A refused skill (CombatAction "SkillDenied") is answered with the dry click only.

	The readiness, for the HUD (Quiet: a thin ring and the seconds, no text, no pop-up): ClientState.skills =
	  { weapon = { id?, ready (0..1), seconds, usable, locked }, general = { ... } }, and its own small display at the
	  lower right (two key squares with the seconds left in Roboto Mono beside them) until the HUD draws the rings.
	  On touch the two round buttons show the seconds left in place of their glyph.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatStats = require(Shared:WaitForChild("CombatStats"))
local Input = require(Shared:WaitForChild("Input"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Moves = require(Shared:WaitForChild("Moves"))
local Net = require(Shared:WaitForChild("Net"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Theme = require(Shared:WaitForChild("Theme"))
local QuietUI = require(Shared:WaitForChild("QuietUI"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local SK = Moves.skills

local SkillController = {}
local Controllers: { [string]: any } = {}
local MeleeSwing: RemoteEvent? = nil
local bound = false
local promptsWithF = 0
local gui: ScreenGui? = nil
local rows: { [string]: { key: Frame, seconds: TextLabel, name: TextLabel } } = {}
local pending: { [string]: number } = {} -- slot -> os.clock of a press not yet answered (shown as used at once)

local GLYPH = { weapon = "R", general = "F" }

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function combat(): any
	return Controllers.CombatController
end

local function heldDef(): any
	local cc = combat()
	if cc and type(cc.getEquipped) == "function" then
		local _, def = cc.getEquipped()
		return def
	end
	return ItemDefs.get("fists")
end

-- The weapon skill R does now: the held weapon's family when it is the Specialty (or none is set), else nil.
local function weaponSkillNow(): (string?, string?)
	local def = heldDef()
	local family = Moves.family(def and def.id)
	local specialty = player:GetAttribute("SkillSpecialty")
	if SK.Specialty ~= false and type(specialty) == "string" and specialty ~= family then
		return nil, family
	end
	local skill = Moves.weaponSkill(family)
	return if skill then skill.id else nil, family
end

local function generalNow(): string
	local id = player:GetAttribute("SkillGeneral")
	return if type(id) == "string" and SK.General[id] then id else (SK.DefaultGeneral or "concentration")
end

local function slotInfo(slot: string): { [string]: any }
	local now = serverNow()
	local id, family
	if slot == "weapon" then
		id, family = weaponSkillNow()
	else
		id = generalNow()
	end
	local def = if slot == "weapon" then Moves.weaponSkill(family) else Moves.generalSkill(id)
	local readyAt = tonumber(player:GetAttribute(if slot == "weapon" then "SkillWeaponReadyAt" else "SkillGeneralReadyAt")) or 0
	local opensAt = tonumber(player:GetAttribute("SkillsOpenAt")) or 0
	local cooldown = (def and def.Cooldown) or 30
	local wait = math.max(readyAt - now, opensAt - now, 0)
	if pending[slot] and os.clock() - pending[slot] < 0.6 then
		wait = math.max(wait, cooldown) -- (pressed: shown as used until the server's answer arrives)
	end
	return {
		id = id,
		family = family,
		seconds = wait,
		ready = if wait <= 0 then 1 else math.clamp(1 - wait / cooldown, 0, 1),
		usable = id ~= nil and wait <= 0.05,
		locked = now < opensAt,
		def = def,
	}
end

-- The local part of a skill (the server does the rest and checks every blow).
local function playLocal(id: string, look: Vector3)
	local cc = combat()
	if not cc then
		return
	end
	local def = heldDef()
	local stats = CombatStats.melee(def or ItemDefs.get("fists"), 1)
	local W = SK.Weapon
	local t0 = os.clock()
	if id == "head_kick" then
		local move = Moves.skillStrike(stats, def and def.id, "HK")
		if move then
			cc.playSkillMove(move)
		end
	elseif id == "chained_strikes" then
		local S = W.ShortBlade
		task.spawn(function()
			for i = 1, #S.Mults do
				local at = if i == 1 then 0 else S.First + (i - 1) * S.Gap
				local waitFor = t0 + at - os.clock()
				if waitFor > 0 then
					task.wait(waitFor)
				end
				if not cc.canFight() then
					return -- (a hit taken ends it)
				end
				local move = Moves.skillStrike(stats, def and def.id, "S" .. i)
				local rec = move and cc.playSkillMove(move)
				if not rec then
					return
				end
				cc.driveBody(look, S.Step / 0.1, 0.1, move.windup)
				-- a miss ends the chain
				task.wait((move.windup or 0) + 0.03)
				if rec.hit ~= "Character" then
					return
				end
			end
		end)
	elseif id == "running_cut" then
		local S = W.Sword
		cc.holdAttacks(S.Total)
		cc.driveBody(look, S.Dash / S.DashTime, S.DashTime, S.Crouch)
	elseif id == "whirl" then
		cc.holdAttacks(W.Axe.Total)
	elseif id == "vault_kick" then
		local S = W.Spear
		cc.holdAttacks(S.Total)
		cc.driveBody(look, S.Vault / (S.HitAt - S.Plant), S.HitAt - S.Plant, S.Plant, 16)
	elseif id == "second_wind" then
		local movement = Controllers.MovementController
		if movement and type(movement.addStamina) == "function" then
			pcall(movement.addStamina, SK.General.second_wind.Stamina)
		end
	end
	local skillDef = Moves.weaponSkill(Moves.family(def and def.id))
	local total = if skillDef and skillDef.id == id then skillDef.Total else (SK.General[id] and SK.General[id].Total) or 0.4
	cc.action:Fire("Skill", { id = id, t0 = t0, total = total or 0.5 })
end

local function use(slot: string): boolean
	local cc = combat()
	if not (cc and cc.canFight and cc.canFight()) then
		return false
	end
	local info = slotInfo(slot)
	if not info.usable or not info.id then
		Sfx.play("UIClick", { volume = 0.6, pitch = 0.6 })
		return false
	end
	local cam = workspace.CurrentCamera
	local look = if cam then cam.CFrame.LookVector else Vector3.new(0, 0, -1)
	pending[slot] = os.clock()
	if MeleeSwing then
		MeleeSwing:FireServer("Skill", slot, serverNow(), look)
	end
	playLocal(info.id, look)
	return true
end

local function onWeapon(state: Enum.UserInputState, _io: InputObject?): Enum.ContextActionResult?
	if state ~= Enum.UserInputState.Begin then
		return nil
	end
	if ClientState.menuOpen then
		return Enum.ContextActionResult.Pass
	end
	use("weapon")
	return nil
end

local function onGeneral(state: Enum.UserInputState, io: InputObject?): Enum.ContextActionResult?
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if ClientState.menuOpen then
		return Enum.ContextActionResult.Pass
	end
	if io and io.KeyCode == Enum.KeyCode.F and promptsWithF > 0 then
		return Enum.ContextActionResult.Pass -- (a fire's F prompt shows: it wins)
	end
	use("general")
	return nil
end

local function bind()
	if bound then
		return
	end
	bound = true
	local A = Input.ACTIONS or {}
	Input.bind("SkillWeapon", onWeapon, {
		keys = if A.SkillWeapon then A.SkillWeapon.keys else { Enum.KeyCode.R, Enum.KeyCode.DPadLeft },
		touch = if A.SkillWeapon then table.clone(A.SkillWeapon.touch) else true,
	})
	Input.bind("SkillGeneral", onGeneral, {
		keys = if A.SkillGeneral then A.SkillGeneral.keys else { Enum.KeyCode.F, Enum.KeyCode.DPadRight },
		touch = if A.SkillGeneral then table.clone(A.SkillGeneral.touch) else true,
		priority = 1000, -- (under the fire's prompts)
	})
	if gui then
		gui.Enabled = true
	end
end

local function unbind()
	if not bound then
		return
	end
	bound = false
	Input.unbind("SkillWeapon")
	Input.unbind("SkillGeneral")
	if gui then
		gui.Enabled = false
	end
end

local function refreshBinding()
	-- (and in the Training Centre's hall, where skills are tried at four times the recharge: TrainingService)
	if (ClientState.inArena and ClientState.alive and ClientState.spectating == nil)
		or player:GetAttribute("InTraining") == true then
		bind()
	else
		unbind()
	end
end

-- The small display (until the HUD draws the rings): two key squares at the lower right, each with the seconds left.
local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "SkillRings"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 4
	screen.Enabled = false
	local holder = Instance.new("Frame")
	holder.Name = "Root"
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -28, 1, -132)
	holder.Size = UDim2.fromOffset(120, 64)
	holder.BackgroundTransparency = 1
	holder.Parent = screen
	for i, slot in ipairs({ "weapon", "general" }) do
		local row = Instance.new("Frame")
		row.Name = slot
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromOffset(120, 28)
		row.Position = UDim2.fromOffset(0, (i - 1) * 34)
		row.Parent = holder
		local key = QuietUI.key({ Text = GLYPH[slot], Position = UDim2.fromOffset(84, 0) })
		key.Parent = row
		local seconds = QuietUI.label({ Font = "Mono", TextSize = Theme.TextSize.Number, Text = "",
			TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(76, 28) })
		seconds.Parent = row
		rows[slot] = { key = key, seconds = seconds, name = seconds }
	end
	screen.Parent = playerGui
	gui = screen
end

local function refreshDisplay()
	local skills = {}
	for _, slot in ipairs({ "weapon", "general" }) do
		local info = slotInfo(slot)
		skills[slot] = { id = info.id, ready = info.ready, seconds = info.seconds, usable = info.usable, locked = info.locked }
		local row = rows[slot]
		if row then
			local text = if info.id == nil then "" elseif info.seconds > 0.05 then string.format("%d", math.ceil(info.seconds)) else ""
			row.seconds.Text = text
			local dim = info.id == nil or not info.usable
			local letter = row.key:FindFirstChild("Label")
			if letter and letter:IsA("TextLabel") then
				QuietUI.textTransparency(letter, if info.id == nil then 0.75 elseif dim then 0.5 else 0)
			end
			local stroke = row.key:FindFirstChild("Stroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Transparency = if dim then 0.7 else 0.25
			end
		end
		if bound and Input.isTouch() then
			local name = if slot == "weapon" then "SkillWeapon" else "SkillGeneral"
			Input.setTouchLabel(name, if info.id == nil then "" elseif info.seconds > 0.05 then tostring(math.ceil(info.seconds)) else GLYPH[slot])
		end
	end
	ClientState.skills = skills
end

function SkillController.Init(registry)
	Controllers = registry
end

function SkillController.Start()
	MeleeSwing = Net.event("MeleeSwing")
	Net.event("CombatAction").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.action == "SkillDenied" then
			pending[payload.slot or ""] = nil
			Sfx.play("UIClick", { volume = 0.6, pitch = 0.6 })
		end
	end)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.KeyboardKeyCode == Enum.KeyCode.F then
			promptsWithF += 1
			prompt.PromptHidden:Once(function()
				promptsWithF = math.max(0, promptsWithF - 1)
			end)
		end
	end)
	pcall(buildGui)
	ClientState.lifeChanged:Connect(refreshBinding)
	ClientState.spectateChanged:Connect(refreshBinding)
	player:GetAttributeChangedSignal("InTraining"):Connect(refreshBinding)
	refreshBinding()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			refreshDisplay()
		end
	end)
end

SkillController._use = use -- test hook: ("weapon" | "general") -> pressed

return SkillController
