-- MPT_Bot (mp-test): test-only client bot. It is cloned by MPT_Driver into a test player's PlayerGui inside a Studio
-- multiplayer test (StudioTestService) and never ships: the driver itself exists in the place only while a test is
-- being started. It reports what THIS client sees (lines go to this client's log and, batched, to the server) and
-- obeys orders from the driver through the RemoteFunction ReplicatedStorage.MPT_Call.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LogService = game:GetService("LogService")
local GuiService = game:GetService("GuiService")

if not RunService:IsStudio() then
	return
end
local lp = Players.LocalPlayer
local callFn = RS:WaitForChild("MPT_Call", 30) :: RemoteFunction?
local repEv = RS:WaitForChild("MPT_Rep", 30) :: RemoteEvent?
if not (lp and callFn and repEv) then
	return
end

local TAG = "[MPT][C:" .. lp.Name .. "] "
local buffer: { string } = {}
local function now(): number
	return workspace:GetServerTimeNow() % 100000
end
local function L(s: string)
	local line = string.format("%.3f %s", now(), s)
	print(TAG .. line)
	if #buffer < 400 then
		table.insert(buffer, line)
	end
end
task.spawn(function()
	while true do
		task.wait(0.2)
		if #buffer > 0 then
			local out = table.concat(buffer, "\n")
			table.clear(buffer)
			repEv:FireServer(string.sub(out, 1, 60000))
		end
	end
end)

local function fmt(v: any, depth: number?): string
	local d = depth or 0
	local t = typeof(v)
	if t == "table" then
		if d > 3 then
			return "{...}"
		end
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local out = {}
		for i, k in ipairs(keys) do
			if i > 40 then
				table.insert(out, "...")
				break
			end
			table.insert(out, tostring(k) .. "=" .. fmt(v[k], d + 1))
		end
		return "{" .. table.concat(out, ", ") .. "}"
	elseif t == "Vector3" then
		return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
	elseif t == "Instance" then
		return v.ClassName .. ":" .. v.Name
	elseif t == "number" then
		return if v % 1 == 0 then tostring(v) else string.format("%.3f", v)
	end
	return tostring(v)
end

-- errors and warnings of this client ----------------------------------------------------------------------------------
LogService.MessageOut:Connect(function(message, kind)
	if kind ~= Enum.MessageType.MessageError and kind ~= Enum.MessageType.MessageWarning then
		return
	end
	if string.find(message, "[MPT]", 1, true) then
		return
	end
	task.defer(L, (if kind == Enum.MessageType.MessageError then "LOG-E " else "LOG-W ") .. string.sub((string.gsub(message, "\n", " | ")), 1, 400))
end)

-- the game's own modules (the same tables the game uses: this is a LocalScript in the same VM) ------------------------
local GS = RS:WaitForChild("GameState")
local Remotes = RS:WaitForChild("Remotes")
local Shared = RS:WaitForChild("Shared")
local function req(parent: Instance?, name: string): any
	local m = parent and parent:WaitForChild(name, 30)
	if not m then
		L("REQUIRE no module " .. name)
		return nil
	end
	local ok, res = pcall(require, m)
	if not ok then
		L("REQUIRE FAIL " .. name .. ": " .. tostring(res))
		return nil
	end
	return res
end
local scripts = lp:WaitForChild("PlayerScripts")
local Client = scripts:WaitForChild("Client", 30)
local Controllers = Client and Client:WaitForChild("Controllers", 30)
local ClientState = req(Client, "ClientState")
local Input = req(Shared, "Input")
local Combat = req(Controllers, "CombatController")
local CameraController = req(Controllers, "CameraController")
local Visuals = req(Controllers, "CharacterVisuals")
local Inventory = req(Controllers, "InventoryController")
local Spectate = req(Controllers, "SpectateController")

-- what the server tells this client -----------------------------------------------------------------------------------
local lastSfx: { [string]: number } = {}
local function listen(name: string, brief: ((any) -> string?)?)
	local ev = Remotes:FindFirstChild(name)
	if not (ev and ev:IsA("RemoteEvent")) then
		L("no remote " .. name)
		return
	end
	ev.OnClientEvent:Connect(function(a, b, c)
		if brief then
			local text = brief(a)
			if text then
				L("REMOTE " .. name .. " " .. text)
			end
			return
		end
		L("REMOTE " .. name .. " " .. fmt(a) .. (if b ~= nil then " | " .. fmt(b) else "") .. (if c ~= nil then " | " .. fmt(c) else ""))
	end)
end
listen("Announce", function(p)
	if type(p) ~= "table" then
		return fmt(p)
	end
	if p.style == "Countdown" and p.text ~= "GO" and p.text ~= "1" and p.text ~= "10" then
		return nil
	end
	return fmt(p)
end)
listen("RoundSummary")
listen("YouDied")
listen("KillFeed")
listen("HitConfirm")
listen("DamageTaken")
listen("CombatAction")
listen("ProjectileFired", function(p)
	return if type(p) == "table" then fmt({ shooter = p.shooterId or p.userId or p.shooter, id = p.id or p.shotId, item = p.itemId, kind = p.kind }) else fmt(p)
end)
listen("ProjectileImpact", function(p)
	return if type(p) == "table" then fmt({ id = p.id or p.shotId, hit = p.hit or p.kind, host = p.host or p.hostId, part = p.part }) else fmt(p)
end)
listen("Sfx", function(key)
	local k = tostring(key)
	local t = os.clock()
	if lastSfx[k] and t - lastSfx[k] < 0.25 then
		return nil
	end
	lastSfx[k] = t
	return k
end)

-- the prompts the engine shows on this client now (ProximityPromptService)
local shownPrompts: { [Instance]: boolean } = {}
do
	local pps = game:GetService("ProximityPromptService")
	pps.PromptShown:Connect(function(p)
		shownPrompts[p] = true
		if p.Name == "KitPrompt" or p.Name == "TakeAllPrompt" then
			L("PROMPT-SHOWN " .. p:GetFullName() .. string.format(" hold=%.2f", p.HoldDuration))
		end
	end)
	pps.PromptHidden:Connect(function(p)
		shownPrompts[p] = nil
	end)
end
-- the weapons build (19 Nov, mp-weapons): the wheel, the boxes and the round's Gold as this client is told them
task.spawn(function()
	local ev = Remotes:WaitForChild("Rewards", 20)
	if not (ev and ev:IsA("RemoteEvent")) then
		L("no remote Rewards")
		return
	end
	ev.OnClientEvent:Connect(function(kind, data)
		if kind == "state" and type(data) == "table" then
			L("REMOTE Rewards state " .. fmt({ gold = data.gold, freeLeft = data.freeLeft, armoury = data.armoury, bring = data.bring, loaded = data.loaded }))
		else
			L("REMOTE Rewards " .. tostring(kind) .. " " .. fmt(data))
		end
	end)
end)
for _, n in ipairs({ "Phase", "LobbyCount", "AliveCount", "StartedCount", "Practice", "WinnerName", "WinnerUserId", "RoundId", "LaunchCut",
	"MinPlayers", "PrivateServer", "ArenaEvent", "BorderStartRadius" }) do
	GS:GetAttributeChangedSignal(n):Connect(function()
		L("GS " .. n .. "=" .. tostring(GS:GetAttribute(n)))
	end)
end
for _, n in ipairs({ "Alive", "InArena", "Frozen", "Kills", "Placement", "KilledBy", "UsingItem", "Armor" }) do
	lp:GetAttributeChangedSignal(n):Connect(function()
		L("ME " .. n .. "=" .. tostring(lp:GetAttribute(n)))
	end)
end

-- real input (the owner at the controls): the bot itself never makes UserInputService events ---------------------------
local realInput = 0
UIS.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2 then
		realInput += 1
		if realInput <= 40 then
			L("REAL-INPUT " .. (if input.UserInputType == Enum.UserInputType.Keyboard then input.KeyCode.Name else input.UserInputType.Name))
		end
	end
end)
UIS.WindowFocused:Connect(function()
	L("WINDOW focused")
end)
UIS.WindowFocusReleased:Connect(function()
	L("WINDOW focus released")
end)

-- a defeated body as THIS client draws it: one line per sample for 4 s from the moment its humanoid died here.
-- eff = the transparency this client draws a part with (its own and the local modifier together): 0 solid, 1 gone;
-- the range is over the body's parts (the root part and a held item are left out). upY = the root's up vector (1 =
-- upright, 0 = lying flat). motors = joints still holding the body in one piece.
local function bodyLine(c: Model): string
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = c:FindFirstChild("Head") :: BasePart?
	local n, vis, motors, collide, query = 0, 0, 0, 0, 0
	local effMin, effMax = 1, 0
	local playing = {}
	local died = "none"
	-- one piece: how far the farthest body part is from the chest (an R15 body: about 3 studs; limbs coming off: more),
	-- and the joints of every kind that hold it (newer avatars use AnimationConstraints and ball sockets, not Motor6Ds)
	local chest = (c:FindFirstChild("UpperTorso") or root) :: BasePart?
	local spread, anim, socket = 0, 0, 0
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("AnimationConstraint") then
			anim += 1
		elseif d:IsA("BallSocketConstraint") then
			socket += 1
		end
		if d:IsA("BasePart") then
			if d.Name ~= "HumanoidRootPart" and d:FindFirstAncestor("EquippedModel") == nil then
				if chest then
					spread = math.max(spread, (d.Position - chest.Position).Magnitude)
				end
				n += 1
				local eff = 1 - (1 - d.Transparency) * (1 - d.LocalTransparencyModifier)
				effMin, effMax = math.min(effMin, eff), math.max(effMax, eff)
				if eff < 0.95 then
					vis += 1
				end
				if d.CanCollide then
					collide += 1
				end
				if d.CanQuery then
					query += 1
				end
			end
		elseif d:IsA("Motor6D") then
			if d.Part0 and d.Part1 and d.Enabled then
				motors += 1
			end
		elseif d:IsA("Sound") then
			if d.Name == "Died" then
				died = string.format("vol=%.2f playing=%s", d.Volume, tostring(d.IsPlaying))
			end
			if d.IsPlaying and d.Volume > 0.01 then
				table.insert(playing, d.Name)
			end
		end
	end
	return string.format("inWorld=%s parts=%d visible=%d eff=%.2f..%.2f upY=%.2f headAboveRoot=%.2f rootY=%.1f anchored=%s spread=%.2f joints=%d/%d/%d collide=%d query=%d diedSound=[%s] playing=[%s]",
		tostring(c:IsDescendantOf(workspace)), n, vis, effMin, effMax, if root then root.CFrame.UpVector.Y else -9,
		if root and head then head.Position.Y - root.Position.Y else -9, if root then root.Position.Y else -9, tostring(root and root.Anchored), spread, motors,
		anim, socket, collide, query, died, table.concat(playing, ","))
end
local function watchBody(name: string, c: Model)
	task.spawn(function()
		local t0 = os.clock()
		for _, at in ipairs({ 0.05, 0.4, 0.8, 1.2, 1.7, 2.1, 2.4, 2.7, 3.0, 3.4, 3.9 }) do
			local w = at - (os.clock() - t0)
			if w > 0 then
				task.wait(w)
			end
			L(string.format("BODY %s +%.2f %s", name, os.clock() - t0, bodyLine(c)))
		end
	end)
end
local function hookOwn(c: Model)
	task.spawn(function()
		local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				L("ME-DIED")
				watchBody(lp.Name, c)
			end)
		end
	end)
end
lp.CharacterAdded:Connect(hookOwn)
if lp.Character then
	hookOwn(lp.Character)
end

-- what this client sees of the other players ---------------------------------------------------------------------------
local function hookCharacter(p: Player, c: Model)
	L("SEE-CHAR+ " .. p.Name)
	task.spawn(function()
		local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then
			return
		end
		local last = hum.Health
		hum.HealthChanged:Connect(function(h)
			if math.abs(h - last) >= 0.5 then
				L(string.format("SEE-HP %s %.1f -> %.1f", p.Name, last, h))
				last = h
			end
		end)
		hum.Died:Connect(function()
			L("SEE-DIED " .. p.Name)
			watchBody(p.Name, c)
		end)
		task.wait(1.5)
		local cry = c:FindFirstChild("Died", true)
		L(string.format("SEE-DIEDSOUND %s %s", p.Name, if cry and cry:IsA("Sound") then string.format("vol=%.2f", cry.Volume) else "no Died sound"))
	end)
	for _, n in ipairs({ "Stance", "EquippedItem" }) do
		c:GetAttributeChangedSignal(n):Connect(function()
			L("SEE-ATTR " .. p.Name .. "." .. n .. "=" .. tostring(c:GetAttribute(n)))
		end)
	end
end
local function hookPlayer(p: Player)
	if p == lp then
		return
	end
	L(string.format("SEE-PLAYER+ %s userId=%d display=%s", p.Name, p.UserId, p.DisplayName))
	p.CharacterAdded:Connect(function(c)
		hookCharacter(p, c)
	end)
	p.CharacterRemoving:Connect(function()
		L("SEE-CHAR- " .. p.Name)
	end)
	if p.Character then
		hookCharacter(p, p.Character)
	end
	for _, n in ipairs({ "Alive", "InArena", "UsingItem" }) do
		p:GetAttributeChangedSignal(n):Connect(function()
			L("SEE-PATTR " .. p.Name .. "." .. n .. "=" .. tostring(p:GetAttribute(n)))
		end)
	end
end
Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(p)
	L("SEE-PLAYER- " .. p.Name)
end)
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end

-- my own combat actions, and the swings this client plays on other bodies ----------------------------------------------
if Combat and Combat.action then
	Combat.action:Connect(function(name: string, data: any)
		L(string.format("ACT %s item=%s%s%s", name, tostring(data and data.itemId), if data and data.hit ~= nil then " hit=" .. tostring(data.hit) else "",
			if data and data.charge then string.format(" charge=%.2f", data.charge) else ""))
	end)
end
if ClientState and ClientState.hitConfirmed then
	ClientState.hitConfirmed:Connect(function(info: any)
		L("HITCONFIRMED " .. fmt(info))
	end)
end
local swingOn: { [Player]: boolean } = {}
local bowKey: { [Player]: string } = {}
local lastShot, lastSpec, lastCamType, lastSubject = false, nil :: any, "", nil :: any
RunService.Heartbeat:Connect(function()
	-- the bow this client draws on other bodies (CharacterVisuals._bowOf): a line whenever it changes (pull in tenths)
	if Visuals and Visuals._bowOf then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp and p.Character then
				local ok, b = pcall(Visuals._bowOf, p.Character)
				if ok and b then
					local pull = tonumber(b.pull) or 0
					local key = string.format("%s|%s|%s|%d", tostring(b.bow), tostring(b.drawing), tostring(b.string), math.floor(pull * 10 + 0.001))
					if bowKey[p] ~= key then
						bowKey[p] = key
						L(string.format("SEE-BOW %s bow=%s drawing=%s string=%s pull=%.2f arm=%.2f aim=%.2f hold=%.2f", p.Name, tostring(b.bow), tostring(b.drawing),
							tostring(b.string), pull, tonumber(b.arm) or -1, tonumber(b.aim) or -1, tonumber(b.hold) or -1))
					end
				end
			end
		end
	end
	if Visuals and Visuals._swingOf then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp and p.Character then
				local ok, s = pcall(Visuals._swingOf, p.Character)
				local on = ok and s ~= nil
				if on and not swingOn[p] then
					L(string.format("SEE-SWING %s shape=%s style=%s variant=%s u=%.2f dur=%.2f", p.Name, tostring(s.shape), tostring(s.style),
						tostring(s.variant), tonumber(s.u) or -1, tonumber(s.duration) or -1))
				end
				swingOn[p] = on
			end
		end
	end
	if ClientState then
		local shot = ClientState.launchShot == true
		if shot ~= lastShot then
			lastShot = shot
			L("LAUNCHSHOT " .. tostring(shot))
		end
		local spec = ClientState.spectating
		if spec ~= lastSpec then
			lastSpec = spec
			L("SPECTATING " .. (if spec then spec.Name else "nil"))
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		if cam.CameraType.Name ~= lastCamType then
			lastCamType = cam.CameraType.Name
			L("CAMTYPE " .. lastCamType)
		end
		if cam.CameraSubject ~= lastSubject then
			lastSubject = cam.CameraSubject
			L("CAMSUBJECT " .. (if lastSubject then lastSubject:GetFullName() else "nil"))
		end
	end
end)

-- helpers --------------------------------------------------------------------------------------------------------------
local function myParts(): (Humanoid?, BasePart?)
	local c = lp.Character
	if not c then
		return nil, nil
	end
	return c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart") :: any
end

local function basePos(): Vector3
	if CameraController and CameraController.getBaseCFrame then
		local ok, cf = pcall(CameraController.getBaseCFrame)
		if ok and typeof(cf) == "CFrame" then
			return cf.Position
		end
	end
	return workspace.CurrentCamera.CFrame.Position
end

local function pointOf(target: any): Vector3?
	if typeof(target) == "Vector3" then
		return target
	end
	if type(target) == "table" and target.x then
		return Vector3.new(target.x, target.y, target.z)
	end
	if type(target) == "string" then
		local name, partName = string.match(target, "^([^:]+):?(.*)$")
		local p = Players:FindFirstChild(name :: string)
		local c = p and p:IsA("Player") and p.Character
		if c then
			local part = (partName ~= "" and c:FindFirstChild(partName :: string)) or c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart")
			if part and part:IsA("BasePart") then
				return part.Position
			end
		end
	end
	return nil
end

local function face(target: any): number
	local point = pointOf(target)
	if not (point and CameraController) then
		return -1
	end
	local dir = point - basePos()
	local pitch = math.deg(math.asin(math.clamp(dir.Unit.Y, -1, 1)))
	CameraController.faceToward(dir, pitch)
	return dir.Magnitude
end

local function aimError(target: any): number
	local point = pointOf(target)
	if not point then
		return -1
	end
	local cf = if CameraController then CameraController.getBaseCFrame() else workspace.CurrentCamera.CFrame
	return math.deg(math.acos(math.clamp((point - cf.Position).Unit:Dot(cf.LookVector), -1, 1)))
end

-- a mover: walks the character every frame (after the control module's own Move call)
-- a mover: pushes the game's own move input (the PlayerModule's MoveAction, which MovementController reads) fully
-- forward, like a held W; the character walks where its camera looks. `face` = a point to keep looking at meanwhile.
local moveAction: any = nil
local function findMoveAction(): any
	if moveAction and moveAction.Parent then
		return moveAction
	end
	for _, container in ipairs({ lp, game:GetService("StarterPlayer") }) do
		for _, d in ipairs(container:GetDescendants()) do
			if d.Name == "MoveAction" and d:IsA("InputAction") then
				moveAction = d
				return d
			end
		end
	end
	return nil
end
local mover: { v: Vector2, face: any, untilT: number }? = nil
local function stopMover()
	mover = nil
	local action = findMoveAction()
	if action then
		pcall(function()
			action:Fire(Vector2.zero)
		end)
	end
end
RunService:BindToRenderStep("MPT_Move", Enum.RenderPriority.Input.Value + 5, function()
	local m = mover
	if not m then
		return
	end
	if os.clock() > m.untilT then
		stopMover()
		return
	end
	if m.face then
		face(m.face)
	end
	local action = findMoveAction()
	if action then
		pcall(function()
			action:Fire(m.v)
		end)
	end
end)

local tracking: { target: any, untilT: number }? = nil
RunService:BindToRenderStep("MPT_Track", Enum.RenderPriority.Camera.Value - 1, function()
	local t = tracking
	if not t then
		return
	end
	if os.clock() > t.untilT then
		tracking = nil
		return
	end
	face(t.target)
end)

local function touch(name: string, down: boolean?): boolean
	if not (Input and Input.testTouch) then
		return false
	end
	local ok, res = pcall(Input.testTouch, name, down)
	if not ok then
		L("touch " .. name .. " failed: " .. tostring(res))
	end
	return ok and res == true
end

-- Combat v3 (19 Nov, mp-fight): what this client plays and draws -------------------------------------------------------
-- CLIP <owner> <name>: every Blender clip ClipPlayer starts on a body (CLIPVIEW: on this client's first-person view);
-- TRAIL-SWING / TRAIL-SHOT: every cosmetic trail TrailController makes (owner, id); LOADIN <owner>: the load-in swirl;
-- SEE-MOTION: how another body moved while a clip played on it (per-frame steps of the right shoulder and the waist,
-- frames where the upper body sat at the rest pose, the whole range: a snap, a T-pose, a frozen limb);
-- SEE-HITAT: when this client's own health drops, where the attacker's clip was on this screen against its hit mark.
local ClipPlayerM = req(Controllers, "ClipPlayer")
local TrailM = req(Controllers, "TrailController")
local LoadInM = req(Controllers, "LoadInController")
local function ownerOf(inst: Instance?): string
	local m = inst
	while m and m ~= workspace do
		if m:IsA("Model") then
			local p = Players:GetPlayerFromCharacter(m)
			if p then
				return p.Name
			end
		end
		m = m.Parent
	end
	if inst and inst:IsDescendantOf(workspace.CurrentCamera) then
		return lp.Name .. "(view)"
	end
	return if inst then inst.Name else "nil"
end
-- wave 13 (mp-throw-look): THROWSEE <action> <owner>: when another player's ThrowStart / Throw reaches this client,
-- where that owner's newest throw clip is (name, clip time now, its first clip time, its release/hit time, its age)
local throwTracks: { [string]: any } = {}
do
	local ca = Remotes:FindFirstChild("CombatAction")
	if ca and ca:IsA("RemoteEvent") then
		ca.OnClientEvent:Connect(function(p)
			if type(p) ~= "table" or (p.action ~= "ThrowStart" and p.action ~= "Throw") then
				return
			end
			local who = Players:GetPlayerByUserId(tonumber(p.userId) or 0)
			local owner = if who then who.Name else tostring(p.userId)
			local recv = os.clock()
			task.defer(function()
				local tt = throwTracks[owner]
				local tr = tt and tt.track
				L(string.format("THROWSEE %s %s item=%s lead=%s clip=%s tau=%s startTau=%s hit=%s clipAge=%s", tostring(p.action), owner, tostring(p.itemId), fmt(p.lead),
					tostring(tt and tt.name), fmt(tr and tr.tau), fmt(tr and tr.startTau), fmt(tr and tr.clip and tr.clip.hit), fmt(tt and (recv - tt.at))))
			end)
		end)
	end
end
if ClipPlayerM and type(ClipPlayerM.play) == "function" then
	local origPlay = ClipPlayerM.play
	ClipPlayerM.play = function(model, name, opts, ...)
		local track = origPlay(model, name, opts, ...)
		if type(track) == "table" then
			track.__mpt = name
		end
		local owner = ownerOf(model)
		L(string.format("CLIP %s %s lead=%s total=%s ok=%s startTau=%s hit=%s", owner, tostring(name), fmt(opts and opts.lead), fmt(opts and opts.total), tostring(track ~= nil),
			fmt(type(track) == "table" and track.startTau), fmt(type(track) == "table" and track.clip and track.clip.hit)))
		if type(track) == "table" and type(name) == "string" and string.sub(name, 1, 6) == "throw_" then
			throwTracks[owner] = { track = track, name = name, at = os.clock() } -- (wave 13: THROWSEE reads it)
		end
		return track
	end
	if type(ClipPlayerM.playView) == "function" then
		local origView = ClipPlayerM.playView
		ClipPlayerM.playView = function(name, opts, ...)
			local track = origView(name, opts, ...)
			L(string.format("CLIPVIEW %s lead=%s ok=%s", tostring(name), fmt(opts and opts.lead), tostring(track ~= nil)))
			return track
		end
	end
end
if TrailM then
	if type(TrailM.swingOn) == "function" then
		local orig = TrailM.swingOn
		TrailM.swingOn = function(part, b, t, id, onAt, offAt, ...)
			L(string.format("TRAIL-SWING %s id=%s part=%s on=%.2f off=%.2f", ownerOf(part), tostring(id), if typeof(part) == "Instance" then part.Name else "?",
				tonumber(onAt) or -1, tonumber(offAt) or -1))
			return orig(part, b, t, id, onAt, offAt, ...)
		end
	end
	if type(TrailM.attachProjectile) == "function" then
		local orig = TrailM.attachProjectile
		TrailM.attachProjectile = function(itemId, shooterId, isLocal, origin, forced, ...)
			local h = orig(itemId, shooterId, isLocal, origin, forced, ...)
			local shooter = if isLocal then lp else Players:GetPlayerByUserId(tonumber(shooterId) or 0)
			L(string.format("TRAIL-SHOT %s item=%s local=%s id=%s", if shooter then shooter.Name else tostring(shooterId), tostring(itemId), tostring(isLocal),
				tostring(type(h) == "table" and h.id or nil)))
			return h
		end
	end
end
if LoadInM and type(LoadInM.play) == "function" then
	local orig = LoadInM.play
	LoadInM.play = function(character, opts, ...)
		local r = orig(character, opts, ...)
		L(string.format("LOADIN %s played=%s inArena=%s", ownerOf(character), tostring(r), tostring(lp:GetAttribute("InArena"))))
		return r
	end
end
local motion: { [Player]: any } = {}
local function angleDeg(a: CFrame, b: CFrame): number
	local _, ang = (a:Inverse() * b):ToAxisAngle()
	return math.deg(math.abs(ang))
end
local function jointOf(c: Model, name: string): any
	local j = c:FindFirstChild(name, true)
	return if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then j else nil
end
RunService.Heartbeat:Connect(function(dt)
	if not ClipPlayerM or type(ClipPlayerM.playing) ~= "function" then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		if p ~= lp and c then
			local ok, track = pcall(ClipPlayerM.playing, c)
			local m = motion[p]
			if ok and track and not track.done then
				local rs, ls, waist = jointOf(c, "RightShoulder"), jointOf(c, "LeftShoulder"), jointOf(c, "Waist")
				if rs and waist then
					local nowR, nowW = rs.Transform, waist.Transform
					if not m or m.track ~= track then
						if m then
							m.flush(m)
						end
						-- (a clip that follows another on the same body is measured from the last frame of the one before: a snap
						-- between two chain steps counts)
						m = { track = track, name = track.__mpt or "?", frames = 0, steps = {}, maxStep = 0, dtAtMax = 0, identity = 0,
							lastR = if m then m.lastR else nowR, lastW = if m then m.lastW else nowW, first = nowR, range = 0 }
						m.flush = function(s)
							table.sort(s.steps)
							local med = if #s.steps > 0 then s.steps[math.ceil(#s.steps / 2)] else 0
							local second = if #s.steps >= 2 then s.steps[#s.steps - 1] else 0
							L(string.format("SEE-MOTION %s clip=%s frames=%d maxStepDeg=%.1f dtAtMax=%.3f medianStepDeg=%.1f restPoseFrames=%d rangeDeg=%.1f atTau=%.3f atAge=%.3f atW=%.2f joint=%s second=%.1f prev=%.1f next=%.1f",
								p.Name, s.name, s.frames, s.maxStep, s.dtAtMax, med, s.identity, s.range, s.tauAt or -1, s.ageAt or -1, s.wAt or -1, tostring(s.jointAt), second,
								s.prevAt or -1, s.nextAt or -1))
						end
						motion[p] = m
					end
					m.frames += 1
					local sr, sw = angleDeg(m.lastR, nowR), angleDeg(m.lastW, nowW)
					local step = math.max(sr, sw)
					table.insert(m.steps, step)
					if m.waitNext then
						m.nextAt, m.waitNext = step, false
					end
					if step > m.maxStep then
						m.maxStep, m.dtAtMax = step, dt
						m.tauAt, m.ageAt, m.wAt = tonumber(track.tau), tonumber(track.age), tonumber(track.w)
						m.jointAt = if sr >= sw then "RightShoulder" else "Waist"
						m.prevAt, m.waitNext = m.lastStep, true
					end
					m.lastStep = step
					m.range = math.max(m.range, angleDeg(m.first, nowR))
					local rest = angleDeg(CFrame.identity, nowR) < 0.5 and angleDeg(CFrame.identity, nowW) < 0.5
						and (not ls or angleDeg(CFrame.identity, ls.Transform) < 0.5)
					if rest and (tonumber(track.w) or 1) > 0.5 then
						m.identity += 1
					end
					m.lastR, m.lastW = nowR, nowW
				end
			elseif m then
				m.flush(m)
				motion[p] = nil
			end
		end
	end
end)
local function hookOwnHits(c: Model)
	task.spawn(function()
		local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then
			return
		end
		local last = hum.Health
		hum.HealthChanged:Connect(function(h)
			if h < last - 0.5 and ClipPlayerM then
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= lp and p.Character then
						local ok, track = pcall(ClipPlayerM.playing, p.Character)
						if ok and track then
							local info = ClipPlayerM.info(track.__mpt or "")
							L(string.format("SEE-HITAT %s clip=%s tau=%.3f hit=%s delta=%s", p.Name, tostring(track.__mpt), tonumber(track.tau) or -1, fmt(info and info.hit),
								if info and type(info.hit) == "number" then string.format("%+.3f", (tonumber(track.tau) or 0) - info.hit) else "?"))
						end
					end
				end
			end
			last = h
		end)
	end)
end
lp.CharacterAdded:Connect(hookOwnHits)
if lp.Character then
	hookOwnHits(lp.Character)
end
-- a reaction armed by the driver: on the next Swing that `target` starts (as told here), raise the guard (parry), or
-- dodge, `lead` seconds before its strike; after a parry, tap Attack `counterDelay` later (the counter)
local reactArm: any = nil
do
	local ca = Remotes:FindFirstChild("CombatAction")
	if ca and ca:IsA("RemoteEvent") then
		ca.OnClientEvent:Connect(function(payload)
			local arm = reactArm
			if not arm or type(payload) ~= "table" or payload.action ~= "Swing" then
				return
			end
			local who = Players:FindFirstChild(arm.target)
			if not (who and who:IsA("Player") and tonumber(payload.userId) == who.UserId) then
				return
			end
			reactArm = nil
			local wait = math.max(0, (tonumber(payload.lead) or 0.1) - (arm.lead or 0.12))
			L(string.format("REACT swing seen from %s lead=%s move=%s -> %s in %.3f s", arm.target, fmt(payload.lead), tostring(payload.move), arm.mode, wait))
			task.delay(wait, function()
				if arm.mode == "parry" or arm.mode == "guard" then
					L("REACT guard down=" .. tostring(touch("Aim", true)))
					arm.guarding = true
					task.delay(arm.release or 1.0, function()
						touch("Aim", false)
						L("REACT guard released")
					end)
				elseif arm.mode == "dodge" then
					L("REACT dodge=" .. tostring(touch("Dodge", true)))
					touch("Dodge", false)
				end
			end)
			if arm.counter then
				local conn
				conn = Combat.action:Connect(function(name)
					if name == "Parry" then
						conn:Disconnect()
						task.delay(arm.counterDelay or 0.05, function()
							L("REACT counter press")
							touch("Attack", true)
							task.wait(0.05)
							touch("Attack", false)
						end)
					end
				end)
				task.delay(3, function()
					if conn.Connected then
						conn:Disconnect()
					end
				end)
			end
		end)
	end
end

local function shown(g: Instance): boolean
	local cur: Instance? = g
	while cur and not cur:IsA("PlayerGui") do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		if cur:IsA("LayerCollector") and not cur.Enabled then
			return false
		end
		if cur:IsA("CanvasGroup") and cur.GroupTransparency > 0.9 then
			return false
		end
		cur = cur.Parent
	end
	return true
end

local function guiTexts(filter: string?): { string }
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	local out = {}
	if not pg then
		return out
	end
	for _, d in ipairs(pg:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextTransparency < 0.85 and shown(d) then
			local layer = d:FindFirstAncestorWhichIsA("LayerCollector")
			local text = string.gsub(d.Text, "%s+", " ")
			local line = (if layer then layer.Name else "?") .. "/" .. d.Name .. ":" .. string.sub(text, 1, 90)
			if not filter or string.find(string.lower(line), string.lower(filter), 1, true) then
				table.insert(out, line)
				if #out >= 120 then
					break
				end
			end
		end
	end
	return out
end

-- red on this client's screen (the age rating: no red hit effects): every shown thing of the game's own GUI whose
-- colour is red (strong red, green and blue under half of it), with what it is. Sampled by itself a moment after
-- this client is hurt, lands a hit, dies or gets a kill feed line.
local function isRed(c: Color3): boolean
	return c.R >= 0.35 and c.G < c.R * 0.5 and c.B < c.R * 0.5
end
local function rgb(c: Color3): string
	return string.format("rgb(%d,%d,%d)", c.R * 255 + 0.5, c.G * 255 + 0.5, c.B * 255 + 0.5)
end
local function redScan(): { string }
	local out = {}
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return out
	end
	for _, d in ipairs(pg:GetDescendants()) do
		local hit: string? = nil
		local holder: Instance = d
		if d:IsA("GuiObject") then
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image ~= "" and d.ImageTransparency < 0.97 and isRed(d.ImageColor3) then
				hit = string.format("image %s a=%.2f", rgb(d.ImageColor3), 1 - d.ImageTransparency)
			elseif (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextTransparency < 0.9 then
				if isRed(d.TextColor3) then
					hit = string.format("text '%s' %s", string.sub(d.Text, 1, 28), rgb(d.TextColor3))
				elseif d.RichText then
					for hex in string.gmatch(d.Text, 'color="#(%x%x%x%x%x%x)"') do
						local okHex, col = pcall(Color3.fromHex, hex)
						if okHex and isRed(col) then
							hit = "rich text #" .. hex .. " in '" .. string.sub((string.gsub(d.Text, "<[^>]+>", "")), 1, 40) .. "'"
							break
						end
					end
				end
			end
			if not hit and d.BackgroundTransparency < 0.97 and isRed(d.BackgroundColor3) then
				hit = string.format("fill %s a=%.2f", rgb(d.BackgroundColor3), 1 - d.BackgroundTransparency)
			end
		elseif d:IsA("UIStroke") and d.Transparency < 0.9 and isRed(d.Color) and d.Parent then
			hit = string.format("stroke %s a=%.2f", rgb(d.Color), 1 - d.Transparency)
			holder = d.Parent
		end
		if hit and shown(holder) then
			local layer = holder:FindFirstAncestorWhichIsA("LayerCollector")
			if not (layer and layer.Name == "MPT") then
				table.insert(out, (if layer then layer.Name else "?") .. "/" .. (if holder.Parent then holder.Parent.Name .. "/" else "") .. holder.Name .. " " .. hit)
				if #out >= 14 then
					break
				end
			end
		end
	end
	return out
end
-- the screen-edge effects as drawn right now (HUDFX.Vignette: Hurt, LowHealth, Border), with their colour
local function vignetteNow(): string
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	local v = pg and pg:FindFirstChild("HUDFX") and pg.HUDFX:FindFirstChild("Vignette")
	if not v then
		return "no vignette"
	end
	local out = {}
	for _, holder in ipairs(v:GetChildren()) do
		if holder:IsA("GuiObject") then
			local strongest, colour = 0, nil
			for _, edge in ipairs(holder:GetChildren()) do
				if edge:IsA("GuiObject") and 1 - edge.BackgroundTransparency > strongest then
					strongest, colour = 1 - edge.BackgroundTransparency, edge.BackgroundColor3
				end
			end
			local group = if holder:IsA("CanvasGroup") then 1 - holder.GroupTransparency else 1
			if holder.Visible and strongest * group > 0.02 and colour then
				table.insert(out, string.format("%s %s strength=%.2f", holder.Name, rgb(colour), strongest * group))
			end
		end
	end
	return if #out > 0 then table.concat(out, ", ") else "none showing"
end
local function redAt(tag: string, delays: { number })
	for _, dl in ipairs(delays) do
		task.delay(dl, function()
			local list = redScan()
			L(string.format("RED[%s +%.2f] n=%d %s | edges: %s", tag, dl, #list, table.concat(list, " ; "), vignetteNow()))
		end)
	end
end
for name, spec in pairs({ DamageTaken = { "hurt", { 0.08, 0.35 } }, HitConfirm = { "hit", { 0.08, 0.3 } }, YouDied = { "died", { 0.3, 1.5, 3.0 } },
	KillFeed = { "killfeed", { 0.4 } } } :: { [string]: any }) do
	local ev = Remotes:FindFirstChild(name)
	if ev and ev:IsA("RemoteEvent") then
		ev.OnClientEvent:Connect(function()
			redAt(spec[1], spec[2])
		end)
	end
end

-- the round's HUD against the death, result and victory cards
local Notifications = req(Controllers, "NotificationController")
local Recap = req(Controllers, "FallenRecapController")
local function hudInfo(): { [string]: any }
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	local out: { [string]: any } = { pps = game:GetService("ProximityPromptService").Enabled }
	if Notifications and Notifications.isCardUp then
		local ok, up = pcall(Notifications.isCardUp)
		out.card = ok and up == true
	end
	if not pg then
		return out
	end
	local hudRoot = pg:FindFirstChild("HUD") and pg.HUD:FindFirstChild("Root")
	if hudRoot then
		for _, n in ipairs({ "Hotbar", "Vitals", "Top", "KillFeed" }) do
			local g = hudRoot:FindFirstChild(n)
			out[n] = g ~= nil and shown(g)
		end
	end
	local centre = pg:FindFirstChild("HUDFX") and pg.HUDFX:FindFirstChild("Root") and pg.HUDFX.Root:FindFirstChild("Center")
	local names = {}
	if centre then
		for _, g in ipairs(centre:GetChildren()) do
			if g:IsA("GuiObject") and shown(g) then
				table.insert(names, g.Name)
			end
		end
	end
	table.sort(names)
	out.centre = table.concat(names, ",")
	out.edges = vignetteNow()
	-- Take / Open prompts in reach of this character (they draw only while the prompt service is on)
	local _, root = myParts()
	local near = 0
	if root then
		for _, tag in ipairs({ "LootPrompt", "TakeAllPrompt" }) do
			for _, d in ipairs(game:GetService("CollectionService"):GetTagged(tag)) do
				if d:IsA("ProximityPrompt") and d.Enabled and d:IsDescendantOf(workspace) then
					local holder = d.Parent
					local pos = if holder and holder:IsA("BasePart") then holder.Position elseif holder and holder:IsA("Attachment") then holder.WorldPosition
						elseif holder and holder:IsA("Model") then holder:GetPivot().Position else nil
					if pos and (pos - root.Position).Magnitude <= d.MaxActivationDistance then
						near += 1
					end
				end
			end
		end
	end
	out.promptsInReach = near
	return out
end

-- Roblox's chat window and the lobby's status line. `open` true or false opens or closes the window first.
local function chatInfo(open: boolean?): { [string]: any }
	local SG = game:GetService("StarterGui")
	local TCS = game:GetService("TextChatService")
	if open ~= nil then
		pcall(function()
			SG:SetCore("ChatActive", open)
		end)
		task.wait(0.8)
	end
	local out: { [string]: any } = {}
	local ok, active = pcall(function()
		return SG:GetCore("ChatActive")
	end)
	out.active = if ok then active else "error: " .. tostring(active)
	out.coreEnabled = SG:GetCoreGuiEnabled(Enum.CoreGuiType.Chat)
	local w = TCS:FindFirstChildOfClass("ChatWindowConfiguration")
	if w then
		out.windowEnabled = w.Enabled
		pcall(function()
			out.winX, out.winW, out.widthScale = w.AbsolutePosition.X, w.AbsoluteSize.X, w.WidthScale
			out.winY, out.winH = w.AbsolutePosition.Y, w.AbsoluteSize.Y
		end)
	end
	local bar = TCS:FindFirstChildOfClass("ChatInputBarConfiguration")
	out.barEnabled = bar and bar.Enabled
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	local lobby = pg and pg:FindFirstChild("Lobby")
	local status = lobby and lobby:FindFirstChild("Root") and lobby.Root:FindFirstChild("Status")
	local pill = status and status:FindFirstChild("Pill")
	if pill and pill:IsA("GuiObject") then
		out.lineShown = shown(pill)
		out.lineX, out.lineW = pill.AbsolutePosition.X, pill.AbsoluteSize.X
		-- (the window is placed by Roblox's chat: AbsolutePosition is in the screen's inset-free frame; the pill in its
		-- ScreenGui's, so the pill's Y gets the top inset added)
		local inset = game:GetService("GuiService"):GetGuiInset()
		local layer = pill:FindFirstAncestorWhichIsA("ScreenGui")
		out.lineY = pill.AbsolutePosition.Y + (if layer and not layer.IgnoreGuiInset then inset.Y else 0)
		out.lineH = pill.AbsoluteSize.Y
		local xOver = type(out.winX) == "number" and (out.winW or 0) > 0 and out.winX + out.winW > out.lineX and out.lineX + out.lineW > out.winX
		local yOver = type(out.winY) == "number" and (out.winH or 0) > 0 and out.winY + out.winH > out.lineY and out.lineY + out.lineH > out.winY
		out.overLine = out.active == true and out.lineShown == true and xOver and yOver
	end
	local cam = workspace.CurrentCamera
	out.view = if cam then cam.ViewportSize.X else -1
	return out
end

-- Studio draws an unfocused window at its lowest quality, which leaves out small far parts (the Roll Call's points in
-- the sky). `level` (an Enum.QualityLevel name) asks for that quality in this test process; nil hands the old one back.
local qualityWas: any = nil
local function setQuality(level: string?): string
	local ok, res = pcall(function()
		local rendering = (settings() :: any).Rendering
		local before = rendering.QualityLevel
		if level then
			qualityWas = qualityWas or before
			rendering.QualityLevel = (Enum.QualityLevel :: any)[level]
		elseif qualityWas then
			rendering.QualityLevel = qualityWas
		end
		return "was " .. tostring(before) .. ", now " .. tostring(rendering.QualityLevel)
	end)
	L("QUALITY " .. tostring(level) .. ": " .. tostring(ok) .. " " .. tostring(res))
	return tostring(ok) .. " " .. tostring(res)
end

-- the chat window's open state, logged whenever it changes (it is polled: there is no signal for it)
task.spawn(function()
	local SG = game:GetService("StarterGui")
	local last: any = "?"
	local t0 = os.clock()
	while true do
		local ok, active = pcall(function()
			return SG:GetCore("ChatActive")
		end)
		local nowState: any = if ok then active else "not ready"
		if nowState ~= last then
			last = nowState
			L(string.format("CHATWINDOW open=%s (%.1f s after the bot started, uptime %.1f, phase %s)", tostring(nowState), os.clock() - t0, time(),
				tostring(GS:GetAttribute("Phase"))))
		end
		task.wait(0.2)
	end
end)

-- the PLUS marks this client keeps (PlusController: PlusMark_<UserId> in PlayerGui), per player
local function plusInfo(): { [string]: string }
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	local out = {}
	local cam = workspace.CurrentCamera
	for _, p in ipairs(Players:GetPlayers()) do
		local g = pg and pg:FindFirstChild("PlusMark_" .. tostring(p.UserId))
		local on = "-"
		if g and g:IsA("BillboardGui") and g.Adornee and g.Adornee:IsA("BasePart") and cam then
			local _, vis = cam:WorldToViewportPoint(g.Adornee.Position + g.StudsOffsetWorldSpace)
			on = tostring(vis)
		end
		out[p.Name] = string.format("member=%s mark=%s enabled=%s adornee=%s onScreen=%s", tostring(p:GetAttribute("PlusMember")), tostring(g ~= nil),
			tostring(g ~= nil and g:IsA("BillboardGui") and g.Enabled), if g and g:IsA("BillboardGui") and g.Adornee then g.Adornee:GetFullName() else "nil", on)
	end
	return out
end

-- the Roll Call's sky show as this client draws it (workspace.FallenRecap: glowing points 170 studs from the camera)
local recapSizes: { [BasePart]: Vector3 } = {} -- (points this test made bigger, with their own size)
local function recapInfo(arg: any): { [string]: any }
	local cam = workspace.CurrentCamera
	local f = workspace:FindFirstChild("FallenRecap")
	local n, lit, sum = 0, 0, Vector3.zero
	local solid, pointSize = 0, 0
	if arg and arg.restore then
		for part, size in pairs(recapSizes) do
			if part.Parent then
				part.Size = size
			end
		end
		table.clear(recapSizes)
	end
	if f and cam then
		for _, d in ipairs(f:GetChildren()) do
			if d:IsA("BasePart") then
				n += 1
				if d.Transparency < 0.95 and (d.Position - cam.CFrame.Position).Magnitude < 420 then
					lit += 1
					sum += d.Position
					pointSize = d.Size.X
					if d.Transparency < 0.05 then
						solid += 1
					end
					-- test only: an unfocused Studio window draws at its lowest quality and leaves such small far parts
					-- out, so for one picture the lit points are made `enlarge` times bigger where the game put them
					if arg and type(arg.enlarge) == "number" and not recapSizes[d] then
						recapSizes[d] = d.Size
						d.Size = d.Size * arg.enlarge
					end
				end
			end
		end
	end
	local centroid = if lit > 0 then sum / lit else nil
	if arg and arg.face and centroid then
		tracking = { target = centroid, untilT = os.clock() + (arg.seconds or 6) }
		face(centroid)
	end
	local on, screen = false, "-"
	if centroid and cam then
		local v, vis = cam:WorldToViewportPoint(centroid)
		on, screen = vis, string.format("%d,%d", v.X, v.Y)
	end
	local snaps = RS:FindFirstChild("FallenSnapshots")
	local names = {}
	if snaps then
		for _, s in ipairs(snaps:GetChildren()) do
			table.insert(names, s.Name)
		end
	end
	return {
		showing = if Recap and Recap.isShowing then Recap.isShowing() else nil, bearing = if Recap and Recap.getBearing then Recap.getBearing() else nil,
		points = n, lit = lit, solid = solid, pointSize = pointSize, centre = centroid, onScreen = on, screen = screen,
		elevation = if centroid and cam then math.deg(math.asin(math.clamp((centroid - cam.CFrame.Position).Unit.Y, -1, 1))) else nil,
		snapshots = table.concat(names, ","), freeze = GS:GetAttribute("DevRecapFreeze"),
	}
end

-- another player's bow as this client draws it: CharacterVisuals' own state and where things are
local function bowInfo(name: string): { [string]: any }
	local p = Players:FindFirstChild(name)
	local c = p and p:IsA("Player") and p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (c and root) then
		return { error = "no character" }
	end
	local out: { [string]: any } = {}
	if Visuals and Visuals._bowOf then
		local ok, b = pcall(Visuals._bowOf, c)
		if ok and b then
			out.bow, out.drawing, out.string, out.pull, out.arm, out.aim, out.hold = b.bow, b.drawing, b.string, b.pull, b.arm, b.aim, b.hold
		end
	end
	local lh, rh, head = c:FindFirstChild("LeftHand") :: BasePart?, c:FindFirstChild("RightHand") :: BasePart?, c:FindFirstChild("Head") :: BasePart?
	local lf, rf = c:FindFirstChild("LeftFoot") :: BasePart?, c:FindFirstChild("RightFoot") :: BasePart?
	local floorY = if lf and rf then math.min(lf.Position.Y - lf.Size.Y / 2, rf.Position.Y - rf.Size.Y / 2) else root.Position.Y - 3
	local em = c:FindFirstChild("EquippedModel", true)
	if em then
		out.item = em:GetAttribute("ItemId")
		local low, high, count, sum = math.huge, -math.huge, 0, Vector3.zero
		for _, d in ipairs(em:GetDescendants()) do
			if d:IsA("BasePart") then
				local cf, s = d.CFrame, d.Size / 2
				local ext = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
				low, high = math.min(low, d.Position.Y - ext), math.max(high, d.Position.Y + ext)
				count += 1
				sum += d.Position
			end
		end
		if count > 0 then
			local mid = sum / count
			out.lowAboveFeet, out.highAboveFeet = low - floorY, high - floorY
			out.inHand = if lh and rh then (if (mid - lh.Position).Magnitude < (mid - rh.Position).Magnitude then "Left" else "Right") else "?"
			out.bowFromRoot = root.CFrame:PointToObjectSpace(mid)
		end
	end
	local beams = 0
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("Beam") and d.Enabled then
			beams += 1
		end
	end
	out.beams = beams
	out.leftHand = if lh then root.CFrame:PointToObjectSpace(lh.Position) else nil
	out.rightHand = if rh then root.CFrame:PointToObjectSpace(rh.Position) else nil
	out.head = if head then root.CFrame:PointToObjectSpace(head.Position) else nil
	out.rightHandToHead = if rh and head then (rh.Position - head.Position).Magnitude else nil
	out.handsApart = if rh and lh then (rh.Position - lh.Position).Magnitude else nil
	return out
end

local function state(): { [string]: any }
	local hum, root = myParts()
	local cam = workspace.CurrentCamera
	local equipped = nil
	if Combat and Combat.getEquipped then
		local ok, id = pcall(Combat.getEquipped)
		equipped = if ok then id else "err"
	end
	local inv = {}
	if ClientState and type(ClientState.inventory) == "table" and type(ClientState.inventory.slots) == "table" then
		for slot, entry in pairs(ClientState.inventory.slots) do
			if type(entry) == "table" then
				table.insert(inv, tostring(slot) .. ":" .. tostring(entry.id) .. "x" .. tostring(entry.count or 1))
			end
		end
		table.sort(inv)
	end
	return {
		t = now(), phase = GS:GetAttribute("Phase"), inArena = ClientState and ClientState.inArena, alive = ClientState and ClientState.alive,
		frozen = ClientState and ClientState.frozen, menuOpen = ClientState and ClientState.menuOpen,
		launchShot = ClientState and ClientState.launchShot, moveState = ClientState and ClientState.moveState,
		speed = ClientState and math.floor((ClientState.speed or 0) * 10) / 10,
		spectating = if ClientState and ClientState.spectating then ClientState.spectating.Name else nil,
		equipped = equipped, inv = table.concat(inv, " "), equippedSlot = ClientState and ClientState.inventory and ClientState.inventory.equipped,
		health = if hum then math.floor(hum.Health * 10) / 10 else -1, pos = if root then root.Position else nil,
		look = if root then root.CFrame.LookVector else nil, anchored = if root then root.Anchored else nil,
		camType = if cam then cam.CameraType.Name else "?", camSubject = if cam and cam.CameraSubject then cam.CameraSubject:GetFullName() else "nil",
		camPos = if cam then cam.CFrame.Position else nil, camLook = if cam then cam.CFrame.LookVector else nil,
		focus = if lp.ReplicationFocus then lp.ReplicationFocus:GetFullName() else "nil",
		realInput = realInput, menu = GuiService.MenuIsOpen, attackBound = Input and Input.isBound and Input.isBound("Attack"),
		hunger = lp:GetAttribute("Hunger"), thirst = lp:GetAttribute("Thirst"),
		view = if cam then string.format("%dx%d", cam.ViewportSize.X, cam.ViewportSize.Y) else "?",
	}
end

-- what this client sees of every other player
local function see(): { [string]: any }
	local out = {}
	local _, myRoot = myParts()
	local cam = workspace.CurrentCamera
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp then
			local c = p.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			local held, heldParts, heldVisible = "none", 0, 0
			local visibleParts, totalParts = 0, 0
			if c then
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("BasePart") then
						local inHeld = d:FindFirstAncestor("EquippedModel") ~= nil
						if inHeld then
							heldParts += 1
							if d.Transparency < 0.95 and d.LocalTransparencyModifier < 0.95 then
								heldVisible += 1
							end
						else
							totalParts += 1
							if d.Transparency < 0.95 and d.LocalTransparencyModifier < 0.95 then
								visibleParts += 1
							end
						end
					end
				end
				local em = c:FindFirstChild("EquippedModel", true)
				if em then
					held = tostring(em:GetAttribute("ItemId"))
				end
			end
			local onScreen = false
			local screen = nil
			if root and cam then
				local v, on = cam:WorldToViewportPoint(root.Position)
				onScreen = on
				screen = string.format("%d,%d", v.X, v.Y)
			end
			local hand = c and c:FindFirstChild("RightHand") :: BasePart?
			local head = c and c:FindFirstChild("Head") :: BasePart?
			local playing = {}
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					local id = if track.Animation then string.match(track.Animation.AnimationId, "(%d+)$") else nil
					table.insert(playing, string.format("%s@%.1f", tostring(id or track.Name), track.WeightCurrent))
				end
			end
			-- the pose as numbers: how high the head is above the lower foot, both feet and the left hand from the root
			local lf = c and c:FindFirstChild("LeftFoot") :: BasePart?
			local rf = c and c:FindFirstChild("RightFoot") :: BasePart?
			local lh = c and c:FindFirstChild("LeftHand") :: BasePart?
			local headHeight = if head and lf and rf then head.Position.Y - math.min(lf.Position.Y, rf.Position.Y) else nil
			out[p.Name] = {
				headHeight = headHeight, leftFoot = if lf and root then root.CFrame:PointToObjectSpace(lf.Position) else nil,
				rightFoot = if rf and root then root.CFrame:PointToObjectSpace(rf.Position) else nil,
				leftHand = if lh and root then root.CFrame:PointToObjectSpace(lh.Position) else nil,
				userId = p.UserId, char = c ~= nil, pos = if root then root.Position else nil,
				vel = if root then root.AssemblyLinearVelocity else nil, look = if root then root.CFrame.LookVector else nil,
				health = if hum then math.floor(hum.Health * 10) / 10 else -1, humState = if hum then hum:GetState().Name else "?",
				stance = c and c:GetAttribute("Stance"), equippedAttr = c and c:GetAttribute("EquippedItem"), held = held,
				heldParts = heldParts, heldVisible = heldVisible, bodyParts = totalParts, bodyVisible = visibleParts,
				dist = if root and myRoot then math.floor((root.Position - myRoot.Position).Magnitude * 10) / 10 else -1,
				onScreen = onScreen, screen = screen, alive = p:GetAttribute("Alive"), inArena = p:GetAttribute("InArena"),
				using = p:GetAttribute("UsingItem"), tracks = table.concat(playing, ","),
				handFromRoot = if hand and root then root.CFrame:PointToObjectSpace(hand.Position) else nil,
				headFromRoot = if head and root then root.CFrame:PointToObjectSpace(head.Position) else nil,
				swing = if Visuals and Visuals._swingOf and c then (function()
					local ok, s = pcall(Visuals._swingOf, c)
					return if ok and s then tostring(s.shape) .. "@" .. string.format("%.2f", tonumber(s.u) or -1) else nil
				end)() else nil,
			}
		end
	end
	return out
end

-- steps: { "down" } { "up" } { "click", hold? } { "wait", s } { "select", slot } { "face", target } { "track", target, s }
-- { "aim", down } { "touch", action, down } { "note", text } { "remote", name, ... } { "aimerr", target }
local seqBusy = false
local function runSeq(steps: { any }): string
	if seqBusy then
		return "busy"
	end
	seqBusy = true
	local ok, err = pcall(function()
		for _, step in ipairs(steps) do
			local kind = step[1]
			if kind == "down" then
				L("SEQ attack down")
				touch("Attack", true)
			elseif kind == "up" then
				L("SEQ attack up")
				touch("Attack", false)
			elseif kind == "click" then
				L("SEQ click")
				touch("Attack", true)
				task.wait(step[2] or 0.05)
				touch("Attack", false)
			elseif kind == "wait" then
				task.wait(step[2])
			elseif kind == "select" then
				-- (selecting the slot already in hand would put the item away)
				local have = ClientState and ClientState.inventory and ClientState.inventory.equipped
				if have == step[2] then
					L("SEQ select " .. tostring(step[2]) .. " (already in hand)")
				elseif Inventory then
					L("SEQ select " .. tostring(step[2]))
					Inventory.select(step[2])
				end
			elseif kind == "face" then
				local d = face(step[2])
				L(string.format("SEQ face %s dist=%.2f", fmt(step[2]), d))
			elseif kind == "track" then
				tracking = { target = step[2], untilT = os.clock() + (step[3] or 1) }
			elseif kind == "aim" then
				L("SEQ aim " .. tostring(step[2] ~= false))
				touch("Aim", step[2] ~= false)
			elseif kind == "touch" then
				L("SEQ touch " .. tostring(step[2]) .. " " .. tostring(step[3]) .. " -> " .. tostring(touch(step[2], step[3])))
			elseif kind == "aimerr" then
				L(string.format("SEQ aimerr %s = %.2f deg", fmt(step[2]), aimError(step[2])))
			elseif kind == "aimset" then
				-- the touch Aim button is a toggle: put it in the wanted state (set the opposite, then one press)
				if Input and Input.setToggle then
					Input.setToggle("Aim", not step[2])
				end
				L("SEQ aimset " .. tostring(step[2]) .. " -> " .. tostring(touch("Aim", true)))
			elseif kind == "aimpt" then
				-- the point under the crosshair now (the rendered camera's look, as CombatController's bow release reads it;
				-- own character left out)
				local cf = workspace.CurrentCamera.CFrame
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { lp.Character, workspace.CurrentCamera }
				local hit = workspace:Raycast(cf.Position, cf.LookVector * 400, params)
				local hp = if hit then hit.Position else cf.Position + cf.LookVector * 400
				L(string.format("AIMPT %.3f,%.3f,%.3f on=%s from=%.3f,%.3f,%.3f", hp.X, hp.Y, hp.Z, if hit then hit.Instance:GetFullName() else "nothing",
					cf.Position.X, cf.Position.Y, cf.Position.Z))
			elseif kind == "note" then
				L("SEQ ---- " .. tostring(step[2]))
			elseif kind == "remote" then
				local ev = Remotes:FindFirstChild(step[2])
				if ev then
					L("SEQ remote " .. tostring(step[2]) .. " " .. fmt({ step[3], step[4], step[5], step[6], step[7] }))
					if step[2] == "MeleeSwing" and step[3] == "raw" then
						-- a modified client: a strike that claims a hit on `step[4]` (a player name) along the look
						local cf = CameraController.getBaseCFrame()
						local p = Players:FindFirstChild(step[4])
						ev:FireServer(cf.LookVector, true, 1, p and p.Character, workspace:GetServerTimeNow() - 0.3)
					else
						ev:FireServer(step[3], step[4], step[5], step[6], step[7])
					end
				end
			end
		end
	end)
	seqBusy = false
	if not ok then
		L("SEQ failed: " .. tostring(err))
		return "failed: " .. tostring(err)
	end
	return "done"
end

-- the nearest proximity prompt (loot): hold it like the E key would
local function usePrompt(arg: any): string
	local _, root = myParts()
	if not root then
		return "no character"
	end
	local best, bestD = nil, arg and arg.radius or 14
	local want = arg and arg.match
	local prompts = {}
	for _, tag in ipairs({ "LootPrompt", "TakeAllPrompt" }) do
		for _, d in ipairs(game:GetService("CollectionService"):GetTagged(tag)) do
			table.insert(prompts, d)
		end
	end
	for _, d in ipairs(prompts) do
		if d:IsA("ProximityPrompt") and d.Enabled and d:IsDescendantOf(workspace) then
			local holder = d.Parent
			local pos = if holder and holder:IsA("BasePart") then holder.Position elseif holder and holder:IsA("Attachment") then holder.WorldPosition
				elseif holder and holder:IsA("Model") then holder:GetPivot().Position else nil
			if pos then
				local dist = (pos - root.Position).Magnitude
				local label = d.ActionText .. "|" .. d.ObjectText .. "|" .. d:GetFullName()
				if dist < bestD and (not want or string.find(string.lower(label), string.lower(want), 1, true)) then
					best, bestD = d, dist
				end
			end
		end
	end
	if not best then
		return "no prompt in range"
	end
	local label = string.format("%s|%s|%s dist=%.1f hold=%.2f", best.ActionText, best.ObjectText, best:GetFullName(), bestD, best.HoldDuration)
	L("PROMPT " .. label)
	best:InputHoldBegin()
	task.wait(best.HoldDuration + 0.15)
	best:InputHoldEnd()
	return label
end

-- world loot as this client has it
local function worldItems(arg: any): { string }
	local out = {}
	local center = arg and pointOf(arg.near)
	local radius = arg and arg.radius or 30
	local CollectionService = game:GetService("CollectionService")
	local seen = {}
	local function add(inst: Instance, tag: string)
		if seen[inst] or not inst:IsDescendantOf(workspace) then
			return
		end
		seen[inst] = true
		local pos = if inst:IsA("Model") then inst:GetPivot().Position elseif inst:IsA("BasePart") then inst.Position else nil
		if pos and (not center or (pos - center).Magnitude <= radius) then
			table.insert(out, string.format("%s %s item=%s count=%s id=%s at %s", tag, inst.Name, tostring(inst:GetAttribute("ItemId")),
				tostring(inst:GetAttribute("Count")), tostring(inst:GetAttribute("WorldId") or inst:GetAttribute("Id")), fmt(pos)))
		end
	end
	for _, tag in ipairs({ "GroundItem", "SupplyCrate", "LooseProjectile" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			add(inst, tag)
		end
	end
	table.sort(out)
	return out
end

-- mp-finish (19 Nov, wave 11): what a weapon model is made of. tierMesh = the WeaponsV3 variant TierLooks put in
-- (Assets.Items.<id>_t<stars>), mesh = visible MeshParts with a mesh, trims = old part-built TierTrim parts, tiled =
-- visible parts in a tiled material (Wood, Metal ...: anything but SmoothPlastic, Plastic, Neon, Glass, ForceField)
local UNTILED = { SmoothPlastic = true, Plastic = true, Neon = true, Glass = true, ForceField = true }
local function finishLookOf(m: Instance): string
	local tierMesh = m:GetAttribute("TierMesh")
	if tierMesh == nil then
		for _, d in ipairs(m:GetDescendants()) do
			if d:GetAttribute("TierMesh") ~= nil then
				tierMesh = d:GetAttribute("TierMesh")
				break
			end
		end
	end
	local n, mesh, trims, tiled, mats = 0, 0, 0, {}, {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			n += 1
			if d:IsA("MeshPart") and d.MeshId ~= "" then
				mesh += 1
			end
			if d:GetAttribute("TierTrim") then
				trims += 1
			end
			mats[d.Material.Name] = (mats[d.Material.Name] or 0) + 1
			if not UNTILED[d.Material.Name] then
				table.insert(tiled, d.Name .. ":" .. d.Material.Name)
			end
		end
	end
	local ml = {}
	for k, v in pairs(mats) do
		table.insert(ml, k .. "x" .. v)
	end
	table.sort(ml)
	-- wave 13: the template that variant came from (its Source), and how many of the drawn meshes are that template's
	local assets = RS:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	local variant = if items and type(tierMesh) == "string" then items:FindFirstChild(tierMesh) else nil
	local srcName = if variant then tostring(variant:GetAttribute("Source")) else "none"
	local ids, matched, drawn, inlay = {}, 0, 0, 0
	for _, d in ipairs(variant and variant:GetDescendants() or {}) do
		if d:IsA("MeshPart") and d.MeshId ~= "" then
			ids[d.MeshId] = true
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		local off = d:FindFirstAncestor("OffHand") -- (the pair's left blade inside the right one's model: its own line)
		if d:IsA("MeshPart") and d.MeshId ~= "" and d.Transparency < 0.99 and not (off and off ~= m) then
			drawn += 1
			if ids[d.MeshId] then
				matched += 1
			end
			if d:GetAttribute("PartRole") == "Inlay" then
				inlay += 1
			end
		end
	end
	return string.format("%s item=%s stars=%s tierMesh=%s src=%s meshMatch=%d/%d inlay=%d parts=%d mesh=%d trims=%d mats=%s tiled=[%s]", m.Name, tostring(m:GetAttribute("ItemId")),
		tostring(m:GetAttribute("Stars")), tostring(tierMesh), srcName, matched, drawn, inlay, n, mesh, trims, table.concat(ml, ","), table.concat(tiled, ","))
end
-- every thrown model this client flies (ProjectileController's ClientProjectiles): its look when it leaves, then how
-- far it turned per second (sampled every drawn frame) when it goes
task.spawn(function()
	local folder = workspace:WaitForChild("ClientProjectiles", 600)
	if not folder then
		return
	end
	local function watch(m: Instance)
		if not m:IsA("Model") then
			return
		end
		task.defer(function()
			local item = tostring(m:GetAttribute("ItemId") or m.Name)
			L("FLY " .. finishLookOf(m))
			local t0, last, turned, frames = os.clock(), m:GetPivot(), 0, 0
			local conn
			conn = RunService.RenderStepped:Connect(function()
				if not m.Parent then
					conn:Disconnect()
					local dt = os.clock() - t0
					L(string.format("FLY-END %s secs=%.2f frames=%d turns=%.2f rate=%.2f/s", item, dt, frames, turned / 360, if dt > 0 then turned / 360 / dt else 0))
					return
				end
				local now_ = m:GetPivot()
				local _, a = (last.Rotation:Inverse() * now_.Rotation):ToAxisAngle()
				turned += math.deg(math.abs(a))
				last = now_
				frames += 1
			end)
		end)
	end
	-- (the folder is made with the first projectile, which may already be in it)
	for _, m in ipairs(folder:GetChildren()) do
		watch(m)
	end
	folder.ChildAdded:Connect(watch)
end)

-- the evening build (18 Nov, mp-retest2): squirrels, campfires, trees, the swarm, the border, the train lobby, the
-- results board ------------------------------------------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")
local wild: { [number]: { state: number, pos: Vector3, to: Vector3, t: number } } = {}
do
	local ev = Remotes:FindFirstChild("WildlifeState") or Remotes:WaitForChild("WildlifeState", 10)
	if ev and ev:IsA("RemoteEvent") then
		ev.OnClientEvent:Connect(function(arr: any)
			if type(arr) ~= "table" then
				return
			end
			local changes = {}
			for i = 1, #arr - 10, 11 do
				local id, st = arr[i], arr[i + 1]
				if type(id) == "number" and type(st) == "number" then
					local before = wild[id]
					local pos = Vector3.new(arr[i + 2], arr[i + 3], arr[i + 4])
					local to = Vector3.new(arr[i + 5], arr[i + 6], arr[i + 7])
					wild[id] = { state = st, pos = pos, to = to, t = now() }
					if not before or before.state ~= st then
						table.insert(changes, string.format("%d:%d@%.0f,%.0f,%.0f>%.0f,%.0f,%.0f", id, st, pos.X, pos.Y, pos.Z, to.X, to.Y, to.Z))
					end
				end
			end
			if #changes > 0 then
				L("WILD " .. table.concat(changes, " "))
			end
		end)
	else
		L("no remote WildlifeState")
	end
end
-- the winner's "You won" line (a few seconds): logged when it shows and when it goes
task.spawn(function()
	local was = false
	while true do
		task.wait(0.25)
		local list = guiTexts("you won")
		local on = #list > 0
		if on ~= was then
			was = on
			L("YOUWON " .. (if on then "shown " .. table.concat(list, " ; ") else "gone"))
		end
	end
end)
local Movement = req(Controllers, "MovementController")
local Hazards = req(Controllers, "HazardController")

local function partPos(d: Instance): Vector3?
	if d:IsA("BasePart") then
		return d.Position
	elseif d:IsA("Model") then
		return d:GetPivot().Position
	elseif d:IsA("Attachment") then
		return d.WorldPosition
	end
	return nil
end

-- the campfire's and the trees' prompts (CookingController's folder, TreeSeatController's tag)
local function gamePrompts(): { ProximityPrompt }
	local out = {}
	local folder = workspace:FindFirstChild("ClientCampfires")
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				table.insert(out, d)
			end
		end
	end
	for _, d in ipairs(CollectionService:GetTagged("TreePrompt")) do
		if d:IsA("ProximityPrompt") then
			table.insert(out, d)
		end
	end
	return out
end

-- every playing sound this client has, with where it is (the Sfx remote covers only the server's)
local function playingSounds(): { string }
	local out = {}
	local _, root = myParts()
	for _, container in ipairs({ workspace, game:GetService("SoundService"), lp:FindFirstChildOfClass("PlayerGui") } :: { any }) do
		if container then
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("Sound") and d.IsPlaying and d.Volume > 0.01 then
					local holder = d.Parent
					local pos = holder and partPos(holder)
					table.insert(out, string.format("%s<%s vol=%.2f%s", d.Name, if holder then holder.Name else "?", d.Volume,
						if pos and root then string.format(" %.0fst", (pos - root.Position).Magnitude) else ""))
					if #out >= 40 then
						return out
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

local function probe(arg: any): any
	local kind = type(arg) == "table" and arg.kind or arg
	local hum, root = myParts()
	local cam = workspace.CurrentCamera
	if kind == "lobby" then
		-- where the camera and the character are against the train's cars; the scenery's motion over 0.5 s
		local lobby = workspace:FindFirstChild("Lobby")
		local out: { [string]: any } = { root = root and root.Position, cam = cam.CFrame.Position, zoom = root and (cam.CFrame.Position - root.Position).Magnitude }
		if lobby then
			local function inside(p: Vector3): string?
				for _, car in ipairs(lobby:GetChildren()) do
					if car:IsA("Model") and (string.find(car.Name, "Gangway", 1, true) or car.Name == "Nose" or car.Name == "Lounge" or car.Name == "Dining"
						or car.Name == "Observation") then
						local cf, size = car:GetBoundingBox()
						local lp3 = cf:PointToObjectSpace(p)
						if math.abs(lp3.X) <= size.X / 2 - 0.4 and math.abs(lp3.Y) <= size.Y / 2 - 0.2 and math.abs(lp3.Z) <= size.Z / 2 then
							return car.Name
						end
					end
				end
				return nil
			end
			out.rootCar = root and inside(root.Position)
			out.camCar = inside(cam.CFrame.Position)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { lobby }
			local up = workspace:Raycast(cam.CFrame.Position, Vector3.new(0, 30, 0), params)
			out.ceilingAboveCam = if up then string.format("%s at %.1f", up.Instance.Name, up.Distance) else "none"
			local scen = lobby:FindFirstChild("Scenery")
			if scen then
				local before = {}
				for _, p in ipairs(scen:GetChildren()) do
					if p:IsA("BasePart") then
						before[p] = p.Position
					end
				end
				task.wait(0.5)
				local moved, n = 0, 0
				for p, at in pairs(before) do
					n += 1
					moved = math.max(moved, (p.Position - at).Magnitude)
				end
				out.sceneryParts = n
				out.sceneryMovedIn05s = moved
			end
			local best, bestD = nil, math.huge
			for _, d in ipairs(lobby:GetDescendants()) do
				if d:IsA("SpawnLocation") and root then
					local dd = (d.Position - root.Position).Magnitude
					if dd < bestD then
						best, bestD = d, dd
					end
				end
			end
			out.nearestSpawn = best and (best.Parent.Name .. "/" .. best.Name .. string.format(" %.1f", bestD))
		end
		return out
	elseif kind == "board" then
		local out = {}
		for _, part in ipairs(CollectionService:GetTagged("ResultsBoard")) do
			local gui = part:FindFirstChild("Results")
			local paper = gui and gui:FindFirstChild("Paper")
			local b: { [string]: any } = { at = part:GetFullName(), streamed = part:IsDescendantOf(workspace), gui = gui ~= nil }
			if paper then
				b.empty = paper.Empty.Visible
				b.meta = paper.Top.Meta.Text
				b.winner = paper.Winner.Visible and (paper.Winner.Label.Text .. ": " .. paper.Winner.Who.Text .. " / " .. paper.Winner.Sub.Text) or nil
				local rows = {}
				for i = 1, 5 do
					local r = paper.Table:FindFirstChild("Row" .. i)
					if r and r.Visible then
						table.insert(rows, string.format("%s|%s|%s|%s mine=%s", r.Place.Text, (string.gsub(r.Who.Text, "<[^>]+>", "")), r.Defeats.Text,
							r.Survived.Text, tostring(r.Band.Visible and r.Bar.Visible)))
					end
				end
				b.rows = table.concat(rows, " ; ")
				local you = paper.Table:FindFirstChild("You")
				b.youRow = you and you.Visible
				local facts = {}
				for i = 1, 4 do
					local f = paper.Facts:FindFirstChild("Fact" .. i)
					if f then
						table.insert(facts, f.Label.Text .. "=" .. f.Value.Text)
					end
				end
				b.facts = table.concat(facts, " ; ")
			end
			if root and part:IsA("BasePart") then
				b.dist = math.floor((part.Position - root.Position).Magnitude * 10) / 10
				local v, on = cam:WorldToViewportPoint(part.Position)
				b.onScreen = on and v.Z > 0
			end
			table.insert(out, b)
		end
		return out
	elseif kind == "wild" then
		local list = {}
		for id, w in pairs(wild) do
			table.insert(list, { id = id, state = w.state, pos = w.pos, to = w.to, t = w.t, dist = if root then (w.pos - root.Position).Magnitude else -1 })
		end
		local folder = workspace:FindFirstChild("ClientWildlife")
		local drawn, meshes, sample = 0, 0, ""
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if m:IsA("Model") then
					local vis = false
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("BasePart") and d.Transparency < 0.95 then
							vis = true
						end
						if d:IsA("MeshPart") and d.MeshId ~= "" then
							meshes += 1
							if sample == "" then
								sample = d.Name .. " " .. d.MeshId .. string.format(" size %.2f,%.2f,%.2f", d.Size.X, d.Size.Y, d.Size.Z)
							end
						end
					end
					if vis then
						drawn += 1
					end
				end
			end
		end
		return { list = list, drawn = drawn, meshParts = meshes, sample = sample, attr = lp:GetAttribute("WildlifeDrawn") }
	elseif kind == "fires" then
		local out = {}
		local cf = RS:FindFirstChild("Campfires")
		if cf then
			for _, c in ipairs(cf:GetChildren()) do
				table.insert(out, string.format("fire %s state=%s spit=%s owner=%s at %s", c.Name, tostring(c:GetAttribute("State")), tostring(c:GetAttribute("Spit")),
					tostring(c:GetAttribute("Owner")), fmt(c:GetAttribute("Position"))))
			end
		end
		local folder = workspace:FindFirstChild("ClientCampfires")
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				local em, emOn, snd, light, meshes = {}, 0, {}, "none", 0
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						table.insert(em, d.Name .. "=" .. tostring(d.Enabled) .. string.format("@%.1f", d.Rate))
						if d.Enabled then
							emOn += 1
						end
					elseif d:IsA("Sound") then
						table.insert(snd, d.Name .. "=" .. tostring(d.IsPlaying) .. string.format("@%.2f", d.Volume))
					elseif d:IsA("PointLight") then
						light = string.format("%s b=%.1f r=%.0f", tostring(d.Enabled), d.Brightness, d.Range)
					elseif d:IsA("MeshPart") and d.MeshId ~= "" then
						meshes += 1
					end
				end
				local pos = partPos(m)
				table.insert(out, string.format("drawn %s at %s dist=%s emitters on %d [%s] sounds [%s] light %s meshParts=%d", m.Name, fmt(pos),
					if pos and root then string.format("%.1f", (pos - root.Position).Magnitude) else "?", emOn, table.concat(em, ","), table.concat(snd, ","), light, meshes))
			end
		end
		return out
	elseif kind == "prompts" then
		-- the game's own prompts near this character (the campfire's, the trees')
		local out = {}
		for _, d in ipairs(gamePrompts()) do
			if d.Enabled then
				local pos = d.Parent and partPos(d.Parent)
				if pos and root and (pos - root.Position).Magnitude < 20 then
					table.insert(out, string.format("%s '%s' '%s' key=%s hold=%.1f style=%s dist=%.1f", d.Name, d.ActionText, d.ObjectText, d.KeyboardKeyCode.Name,
						d.HoldDuration, d.Style.Name, (pos - root.Position).Magnitude))
				end
			end
		end
		return out
	elseif kind == "hold" then
		-- holds the game's prompt named arg.name (as its key would)
		for _, d in ipairs(gamePrompts()) do
			if d.Enabled and d.Name == arg.name then
				L("HOLD " .. d:GetFullName() .. " '" .. d.ActionText .. "'")
				d:InputHoldBegin()
				task.wait(d.HoldDuration + 0.2)
				d:InputHoldEnd()
				return d.ActionText
			end
		end
		return "no enabled prompt " .. tostring(arg.name)
	elseif kind == "climb" then
		-- MovementController.tryClimb on the nearest Climbable trunk (the CLIMB prompt's own call)
		local best, bestD = nil, 9
		for _, t in ipairs(CollectionService:GetTagged("Climbable")) do
			if t:IsA("BasePart") and root then
				local dd = Vector3.new(t.Position.X - root.Position.X, 0, t.Position.Z - root.Position.Z).Magnitude
				if dd < bestD then
					best, bestD = t, dd
				end
			end
		end
		if not best or not Movement then
			return "no trunk in reach"
		end
		local ok, res = pcall(Movement.tryClimb, best)
		return string.format("tryClimb(%s %s %.1f) = %s %s", best:GetFullName(), best.ClassName, bestD, tostring(ok), tostring(res))
	elseif kind == "hazard" then
		local out: { [string]: any } = {}
		if Hazards and Hazards.debug then
			local ok, d = pcall(Hazards.debug)
			out.debug = if ok then fmt(d) else tostring(d)
		end
		-- the swarm's wings near arg.near (a player name): how many, how big, flapping
		local centre = arg.near and pointOf(arg.near)
		local wings, sizes, moved = {}, {}, 0
		local fxFolder = workspace:FindFirstChild("HazardFxLocal")
		if centre and fxFolder then
			for _, d in ipairs(fxFolder:GetDescendants()) do
				if d:IsA("BasePart") and string.find(string.lower(d.Name), "wing", 1, true) and d.Transparency < 0.95 and (d.Position - centre).Magnitude < 30 then
					table.insert(wings, d)
					if #sizes < 3 then
						table.insert(sizes, string.format("%s %s %.2fx%.2fx%.2f", d.Name, d.ClassName, d.Size.X, d.Size.Y, d.Size.Z))
					end
				end
			end
			local before = {}
			for _, w in ipairs(wings) do
				before[w] = w.CFrame
			end
			task.wait(0.15)
			for w, cf0 in pairs(before) do
				local _, ang = (cf0:Inverse() * w.CFrame):ToAxisAngle()
				moved = math.max(moved, math.deg(ang))
			end
		end
		out.wings = #wings
		out.wingSizes = table.concat(sizes, " ; ")
		out.wingTurnIn015s = moved
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		local lines = {}
		if pg then
			for _, d in ipairs(pg:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextTransparency < 0.85 and shown(d) then
					local layer = d:FindFirstAncestorWhichIsA("LayerCollector")
					if layer and layer.Name ~= "MPT" and (layer.Name == "HazardScreen" or layer.Name == "Overlay" or layer.Name == "HUD") and d.AbsolutePosition.Y < 400 then
						table.insert(lines, string.format("%s/%s y=%d..%d '%s'", layer.Name, d.Name, d.AbsolutePosition.Y, d.AbsolutePosition.Y + d.AbsoluteSize.Y,
							string.sub((string.gsub(d.Text, "<[^>]+>", "")), 1, 60)))
					end
				end
			end
		end
		out.topLines = table.concat(lines, " ; ")
		out.stung = lp:GetAttribute("HazardStung")
		return out
	elseif kind == "border" then
		local out: { [string]: any } = { radius = GS:GetAttribute("BorderRadius"), target = GS:GetAttribute("BorderTargetRadius"), stage = GS:GetAttribute("BorderStage"),
			stages = GS:GetAttribute("BorderStageCount"), nextMoveAt = GS:GetAttribute("BorderNextMoveAt"), moving = GS:GetAttribute("BorderMoving") }
		local arena = workspace:FindFirstChild("Arena")
		local border = arena and arena:FindFirstChild("Border")
		local centre = GS:GetAttribute("BorderCenter")
		if border then
			local n, colours, far, near = 0, {}, 0, math.huge
			for _, d in ipairs(border:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
					if d.Name == "BorderLine" and typeof(centre) == "Vector3" then
						local r = Vector3.new(d.Position.X - centre.X, 0, d.Position.Z - centre.Z).Magnitude
						far, near = math.max(far, r), math.min(near, r)
					end
					local key = d.Name .. " " .. rgb(d.Color) .. " " .. d.Material.Name
					colours[key] = (colours[key] or 0) + 1
				end
			end
			local list = {}
			for k, c in pairs(colours) do
				table.insert(list, k .. " x" .. c)
			end
			table.sort(list)
			out.parts = n
			out.looks = table.concat(list, " ; ")
			out.lineRadius = if near < math.huge then string.format("%.0f..%.0f", near, far) else "none"
			out.shown = border.Parent ~= nil
		else
			out.parts = 0
		end
		return out
	elseif kind == "sounds" then
		return playingSounds()
	elseif kind == "skip" then
		-- the launch shot's screen: the skip prompt and button
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		local out = {}
		if pg then
			for _, d in ipairs(pg:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and shown(d) and d.TextTransparency < 0.9 and string.find(string.lower(d.Text), "skip", 1, true) then
					table.insert(out, string.format("%s %s '%s' %dx%d", (d:FindFirstAncestorWhichIsA("LayerCollector") or d).Name, d.Name, d.Text, d.AbsoluteSize.X, d.AbsoluteSize.Y))
				end
			end
		end
		return { shown = out, launchShot = ClientState and ClientState.launchShot, cam = cam.CFrame.Position, camType = cam.CameraType.Name,
			root = root and root.Position, stats = lp:GetAttribute("LS_LaunchStats") }
	elseif kind == "seat" then
		return { moveState = ClientState and ClientState.moveState, sit = hum and hum.Sit, seat = hum and hum.SeatPart and hum.SeatPart:GetFullName(),
			attackBound = Input and Input.isBound and Input.isBound("Attack") }
	end
	-- mp-fight: every held item model on another body as this client draws it (Paired Blades: two)
	if kind == "allheld" then
		local p = Players:FindFirstChild(arg.target)
		local c = p and p:IsA("Player") and p.Character
		if not c then
			return "no character"
		end
		local models, out = 0, {}
		for _, m in ipairs(c:GetDescendants()) do
			if m:IsA("Model") and (m.Name == "EquippedModel" or m.Name == "OffHand" or string.find(m.Name, "Held", 1, true) or m:GetAttribute("ItemId") ~= nil) then
				models += 1
				local weld = m.Parent and m.Parent.Name
				local list = {}
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(list, string.format("%s %s %s %d,%d,%d", d.Name, d.Material.Name, fmt(d.Size), math.floor(d.Color.R * 255), math.floor(d.Color.G * 255),
							math.floor(d.Color.B * 255)))
					end
				end
				-- the hand it is held in: the nearest hand part
				local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
				local near, nd = "?", math.huge
				for _, h in ipairs({ "RightHand", "LeftHand" }) do
					local hp = c:FindFirstChild(h)
					if hp and pp then
						local d = (hp.Position - pp.Position).Magnitude
						if d < nd then
							near, nd = h, d
						end
					end
				end
				table.insert(out, string.format("[%s in %s near %s (%.1f) stars=%s: %s]", m.Name, tostring(weld), near, nd, tostring(m:GetAttribute("Stars")),
					table.concat(list, "; ")))
			end
		end
		return string.format("models=%d %s", models, table.concat(out, " "))
	end
	-- mp-finish (19 Nov, wave 11): the WeaponsV3 look of held / first-person / world models, the Take prompt, joints
	if kind == "look" then
		local found = {}
		if arg.target == "self" then
			for _, d in ipairs(cam:GetDescendants()) do
				if d:IsA("Model") and (d:GetAttribute("Stars") ~= nil or d:GetAttribute("ItemId") ~= nil or d.Name == "OffHand") then
					table.insert(found, d)
				end
			end
		else
			local p = Players:FindFirstChild(arg.target)
			local c = p and p:IsA("Player") and p.Character
			for _, d in ipairs(c and c:GetDescendants() or {}) do
				if d:IsA("Model") and (d.Name == "EquippedModel" or d.Name == "OffHand") then
					table.insert(found, d)
				end
			end
		end
		local out = {}
		for _, m in ipairs(found) do
			table.insert(out, "[" .. finishLookOf(m) .. "]")
		end
		return string.format("models=%d %s", #found, table.concat(out, " "))
	elseif kind == "worldlook" then
		local center = pointOf(arg.near)
		local out = {}
		for _, tag in ipairs({ "WorldProjectile", "GroundItem" }) do
			for _, m in ipairs(CollectionService:GetTagged(tag)) do
				if m:IsA("Model") and m:IsDescendantOf(workspace) and (not arg.item or m:GetAttribute("ItemId") == arg.item) then
					local pv = m:GetPivot()
					if not center or (pv.Position - center).Magnitude <= (arg.radius or 40) then
						table.insert(out, string.format("[%s %s loose=%s host=%s at %s up=%s | %s]", tag, tostring(m:GetAttribute("ItemId")),
							tostring(CollectionService:HasTag(m, "LooseProjectile")), tostring(m:GetAttribute("Host")), fmt(pv.Position), fmt(pv.UpVector), finishLookOf(m)))
					end
				end
			end
		end
		return table.concat(out, " ")
	elseif kind == "take" then
		-- WorldItemController's own Take prompt (E), as the key would press it, once it targets something
		local holderA = workspace.Terrain:FindFirstChild("WorldItemPrompt")
		local prompt = holderA and holderA:FindFirstChild("TakePrompt")
		local t0 = os.clock()
		while os.clock() - t0 < (arg.wait or 2.5) and not (prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled) do
			task.wait(0.1)
			holderA = workspace.Terrain:FindFirstChild("WorldItemPrompt")
			prompt = holderA and holderA:FindFirstChild("TakePrompt")
		end
		if not (prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled) then
			return "no Take prompt shown"
		end
		local text = prompt.ActionText .. " " .. prompt.ObjectText
		local fired = false
		local conn = prompt.Triggered:Connect(function()
			fired = true
		end)
		L("TAKE " .. text)
		prompt:InputHoldBegin()
		task.wait(0.1)
		prompt:InputHoldEnd()
		task.wait(0.3)
		conn:Disconnect()
		return string.format("prompt '%s' key=%s triggered=%s", text, prompt.KeyboardKeyCode.Name, tostring(fired))
	elseif kind == "joints" then
		-- every Motor6D's Transform turn on that body as this client has it (a folded body reads 100+ degrees)
		local c: Instance? = nil
		local p = Players:FindFirstChild(arg.target)
		if p and p:IsA("Player") then
			c = p.Character
		else
			c = workspace:FindFirstChild(arg.target, true)
		end
		if not c then
			return "no body " .. tostring(arg.target)
		end
		local worst, list = 0, {}
		for _, j in ipairs(c:GetDescendants()) do
			if j:IsA("Motor6D") then
				local _, ang = j.Transform:ToAxisAngle()
				local deg = math.deg(math.abs(ang))
				worst = math.max(worst, deg)
				if deg > 20 then
					table.insert(list, string.format("%s %.0f", j.Name, deg))
				end
			end
		end
		local hum = c:FindFirstChildOfClass("Humanoid")
		local an = hum and hum:FindFirstChildOfClass("Animator")
		local tracks = {}
		if an then
			for _, t in ipairs(an:GetPlayingAnimationTracks()) do
				table.insert(tracks, t.Name)
			end
		end
		return string.format("maxDeg=%.1f animator=%s tracks=%d over20=[%s]", worst, tostring(an ~= nil), #tracks, table.concat(list, ", "))
	end
	-- the weapons build (19 Nov, mp-weapons) ------------------------------------------------------------------------
	if kind == "weap" then
		-- stars as this client draws them: its own first-person item, and every other player's held model
		local out: { [string]: any } = { vm = {}, held = {} }
		local function steel(m: Instance): string
			local cols = {}
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 1 and (d:GetAttribute("Role") == "Steel" or d.Material == Enum.Material.Metal) then
					table.insert(cols, string.format("%s:%s:%s:r%.2f", d.Name, rgb(d.Color), d.Material.Name, d.Reflectance))
					if #cols >= 3 then
						break
					end
				end
			end
			return table.concat(cols, ",")
		end
		for _, d in ipairs(cam:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("Stars") ~= nil then
				table.insert(out.vm, string.format("%s stars=%s finish=%s steel=[%s]", d.Name, tostring(d:GetAttribute("Stars")), tostring(d:GetAttribute("Finish")), steel(d)))
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			local em = c and c:FindFirstChild("EquippedModel", true)
			if c and p ~= lp then
				out.held[p.Name] = string.format("item=%s charStars=%s modelStars=%s finish=%s steel=[%s]", tostring(c:GetAttribute("EquippedItem")),
					tostring(c:GetAttribute("EquippedStars")), tostring(em and em:GetAttribute("Stars")), tostring(em and em:GetAttribute("Finish")),
					if em then steel(em) else "")
			end
		end
		local inv = ClientState and ClientState.inventory
		if type(inv) == "table" and type(inv.slots) == "table" then
			local s = {}
			for i, e in ipairs(inv.slots) do
				if type(e) == "table" then
					table.insert(s, string.format("%d:%sx%s*%s", i, tostring(e.id), tostring(e.count), tostring(e.stars)))
				end
			end
			out.inv = table.concat(s, " ") .. " equipped=" .. tostring(inv.equipped)
		end
		out.hotbar = guiTexts("★")
		return out
	elseif kind == "parcels" then
		local out = {}
		for _, m in ipairs(CollectionService:GetTagged("KitParcel")) do
			if m:IsA("Model") then
				local prompt = m:FindFirstChild("KitPrompt", true)
				local pos = m:GetPivot().Position
				table.insert(out, string.format("owner=%s landed=%s opened=%s at=%.1f,%.1f,%.1f dist=%.1f prompt=%s hold=%s enabled=%s chute=%s",
					tostring(m:GetAttribute("OwnerUserId")), tostring(m:GetAttribute("Landed")), tostring(m:GetAttribute("Opened")), pos.X, pos.Y, pos.Z,
					if root then (pos - root.Position).Magnitude else -1, tostring(prompt ~= nil),
					if prompt and prompt:IsA("ProximityPrompt") then string.format("%.2f", prompt.HoldDuration) else "-",
					if prompt and prompt:IsA("ProximityPrompt") then tostring(prompt.Enabled) else "-", tostring(m:FindFirstChild("Chute") ~= nil)))
			end
		end
		return out
	elseif kind == "kithold" then
		-- holds the Open prompt of the parcel owned by arg.owner (a UserId) for arg.seconds; arg.force sets this client's
		-- HoldDuration first (a modified client trying the owner's short hold on someone else's parcel)
		for _, m in ipairs(CollectionService:GetTagged("KitParcel")) do
			if m:IsA("Model") and m:GetAttribute("OwnerUserId") == arg.owner and m:GetAttribute("Opened") ~= true and m:FindFirstChild("KitPrompt", true) then
				local prompt = m:FindFirstChild("KitPrompt", true)
				if not (prompt and prompt:IsA("ProximityPrompt")) then
					return "no prompt"
				end
				local was = prompt.HoldDuration
				if arg.force then
					prompt.HoldDuration = arg.force
				end
				local fired, began = false, false
				local conn = prompt.Triggered:Connect(function()
					fired = true
				end)
				local conn2 = prompt.PromptButtonHoldBegan:Connect(function()
					began = true
				end)
				local holder = prompt.Parent
				local at = if holder and holder:IsA("Attachment") then holder.WorldPosition elseif holder and holder:IsA("BasePart") then holder.Position else nil
				L(string.format("KITHOLD owner=%s hold %.2f s (prompt's own %.2f, now %.2f) shown=%s enabled=%s maxDist=%.1f dist=%s style=%s service=%s",
					tostring(arg.owner), arg.seconds, was, prompt.HoldDuration, tostring(shownPrompts[prompt] == true), tostring(prompt.Enabled),
					prompt.MaxActivationDistance, if at and root then string.format("%.1f", (at - root.Position).Magnitude) else "?", prompt.Style.Name,
					tostring(game:GetService("ProximityPromptService").Enabled)))
				local others = {}
				for sp in pairs(shownPrompts) do
					if sp:IsA("ProximityPrompt") then
						local h = sp.Parent
						local pos = if h and h:IsA("Attachment") then h.WorldPosition elseif h and h:IsA("BasePart") then h.Position else nil
						table.insert(others, string.format("%s key=%s excl=%s dist=%s", sp:GetFullName(), sp.KeyboardKeyCode.Name, sp.Exclusivity.Name,
							if pos and root then string.format("%.1f", (pos - root.Position).Magnitude) else "?"))
					end
				end
				L("KITHOLD prompts shown now: " .. table.concat(others, " ; ") .. string.format(" | max visible %d | the parcel's key=%s excl=%s los=%s parent=%s",
					game:GetService("ProximityPromptService").MaxPromptsVisible, prompt.KeyboardKeyCode.Name, prompt.Exclusivity.Name,
					tostring(prompt.RequiresLineOfSight), prompt.Parent and prompt.Parent:GetFullName() or "nil"))
				prompt:InputHoldBegin()
				task.wait(arg.seconds)
				prompt:InputHoldEnd()
				task.wait(0.3)
				conn:Disconnect()
				conn2:Disconnect()
				if arg.force then
					prompt.HoldDuration = was
				end
				return string.format("held %.2f s; prompt's hold was %.2f; shown on this client=%s; hold began on this client=%s; triggered on this client=%s", arg.seconds,
					was, tostring(shownPrompts[prompt] == true), tostring(began), tostring(fired))
			end
		end
		return "no parcel of " .. tostring(arg.owner)
	elseif kind == "watchboard" then
		-- logs the Armoury board's and the Gold line's words whenever they change, for arg.seconds
		task.spawn(function()
			local t0 = os.clock()
			local last = ""
			while os.clock() - t0 < (arg.seconds or 10) do
				local parts = {}
				for _, line in ipairs(guiTexts()) do
					if string.find(line, "ArmouryLive/", 1, true) or string.find(line, "GoldLine/", 1, true) then
						table.insert(parts, line)
					end
				end
				table.sort(parts)
				local now_ = table.concat(parts, " ; ")
				if now_ ~= last then
					last = now_
					L("BOARD " .. string.sub(now_, 1, 1500))
				end
				task.wait(0.1)
			end
			L("BOARD end")
		end)
		return true
	elseif kind == "yourgold" then
		local out = {}
		for _, face in ipairs(CollectionService:GetTagged("ResultsBoard")) do
			for _, d in ipairs(face:GetDescendants()) do
				if d:IsA("TextLabel") and d.Name == "YourGold" then
					table.insert(out, string.gsub(d.Text, "%s+", " ") .. " visible=" .. tostring(d.Visible))
				end
			end
		end
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		if pg then
			for _, d in ipairs(pg:GetDescendants()) do
				if d:IsA("TextLabel") and d.Name == "YourGold" then
					table.insert(out, "pg:" .. string.gsub(d.Text, "%s+", " ") .. " visible=" .. tostring(d.Visible))
				end
			end
		end
		return out
	end
	return "unknown probe " .. tostring(kind)
end

callFn.OnClientInvoke = function(cmd: string, arg: any): any
	local ok, res = pcall(function(): any
		if cmd == "ping" then
			return now()
		elseif cmd == "state" then
			return state()
		elseif cmd == "see" then
			return see()
		elseif cmd == "gui" then
			return guiTexts(arg)
		elseif cmd == "seq" then
			return runSeq(arg)
		elseif cmd == "face" then
			return face(arg)
		elseif cmd == "track" then
			tracking = if arg and arg.target then { target = arg.target, untilT = os.clock() + (arg.seconds or 2) } else nil
			return true
		elseif cmd == "move" then
			if arg and arg.seconds then
				local action = findMoveAction()
				mover = { v = Vector2.new(arg.x or 0, arg.y or 1), face = arg.face, untilT = os.clock() + arg.seconds }
				return if action then action:GetFullName() else "no MoveAction"
			end
			stopMover()
			return true
		elseif cmd == "setting" then
			local before = ClientState.settings[arg.name]
			ClientState.settings[arg.name] = arg.value
			return before
		elseif cmd == "heldinfo" then
			local p = Players:FindFirstChild(arg)
			local c = p and p:IsA("Player") and p.Character
			local root = c and c:FindFirstChild("HumanoidRootPart")
			local em = c and c:FindFirstChild("EquippedModel", true)
			if not (em and root) then
				return "no EquippedModel"
			end
			local out = { "item=" .. tostring(em:GetAttribute("ItemId")) .. " parent=" .. em.Parent.Name }
			local cam = workspace.CurrentCamera
			for _, d in ipairs(em:GetDescendants()) do
				if d:IsA("BasePart") then
					local v, on = cam:WorldToViewportPoint(d.Position)
					table.insert(out, string.format("%s %s size=%s rel=%s transp=%.2f ltm=%.2f mesh=%s screen=%d,%d on=%s color=%s", d.ClassName, d.Name, fmt(d.Size),
						fmt(root.CFrame:PointToObjectSpace(d.Position)), d.Transparency, d.LocalTransparencyModifier,
						if d:IsA("MeshPart") then tostring(d.MeshId ~= "") .. "/" .. d.RenderFidelity.Name else "-", v.X, v.Y, tostring(on), tostring(d.Color)))
				elseif d:IsA("Beam") or d:IsA("SurfaceAppearance") or d:IsA("Weld") or d:IsA("Motor6D") then
					table.insert(out, d.ClassName .. " " .. d.Name)
				end
			end
			return table.concat(out, " | ")
		elseif cmd == "touch" then
			return touch(arg.name, arg.down)
		elseif cmd == "react" then
			reactArm = arg
			L("REACT armed " .. fmt(arg))
			return true
		elseif cmd == "rawswing" then
			-- a modified client: a strike with a move id and a hold it claims, on `target` along the look
			local ev = Remotes:FindFirstChild("MeleeSwing")
			local p = arg.target and Players:FindFirstChild(arg.target)
			local cf = CameraController.getBaseCFrame()
			L("RAWSWING " .. fmt(arg))
			ev:FireServer(cf.LookVector, true, 1, p and p.Character, workspace:GetServerTimeNow() - (arg.ago or 0.1), arg.move, arg.held)
			return true
		elseif cmd == "skill" then
			local name = if arg.slot == "general" then "SkillGeneral" else "SkillWeapon"
			local ok1 = touch(name, true)
			task.wait(0.05)
			touch(name, false)
			L("SKILL " .. name .. " touch=" .. tostring(ok1))
			return ok1
		elseif cmd == "fps" then
			-- this window's frame rates over the next second: the render step (CombatController times strikes there) and Heartbeat
			local r, h, t0 = 0, 0, os.clock()
			local c1 = RunService.RenderStepped:Connect(function()
				r += 1
			end)
			local c2 = RunService.Heartbeat:Connect(function()
				h += 1
			end)
			task.wait(1.0)
			c1:Disconnect()
			c2:Disconnect()
			local e = os.clock() - t0
			return string.format("render %.0f fps, heartbeat %.0f fps", r / e, h / e)
		elseif cmd == "trails" then
			return if TrailM then fmt(TrailM.stats()) else "no TrailController"
		elseif cmd == "select" then
			Inventory.select(arg)
			return true
		elseif cmd == "spectate" then
			if not Spectate then
				return "no SpectateController"
			end
			if arg.op == "start" then
				local p = arg.target and Players:FindFirstChild(arg.target)
				return tostring(Spectate.start(p))
			elseif arg.op == "next" then
				Spectate.next()
			elseif arg.op == "prev" then
				Spectate.prev()
			elseif arg.op == "stop" then
				Spectate.stop()
			end
			local target = Spectate.getTarget()
			return string.format("can=%s spectating=%s target=%s", tostring(Spectate.canSpectate()), tostring(Spectate.isSpectating()),
				if target then target.Name else "nil")
		elseif cmd == "prompt" then
			return usePrompt(arg)
		elseif cmd == "items" then
			return worldItems(arg)
		elseif cmd == "setattr" then
			lp:SetAttribute(arg.name, arg.value)
			return true
		elseif cmd == "inputs" then
			return if Input and Input.list then Input.list() else {}
		elseif cmd == "fire" then
			local ev = Remotes:FindFirstChild(arg.name)
			if ev then
				ev:FireServer(arg.a, arg.b, arg.c, arg.d)
				return true
			end
			return false
		elseif cmd == "quality" then
			return setQuality(if type(arg) == "table" then arg.level else nil)
		elseif cmd == "hud" then
			return hudInfo()
		elseif cmd == "red" then
			return { list = redScan(), edges = vignetteNow() }
		elseif cmd == "chat" then
			return chatInfo(if type(arg) == "table" then arg.open else nil)
		elseif cmd == "plus" then
			return plusInfo()
		elseif cmd == "recap" then
			return recapInfo(arg)
		elseif cmd == "bow" then
			return bowInfo(arg)
		elseif cmd == "probe" then
			return probe(arg)
		elseif cmd == "leave" then
			local sts = game:GetService("StudioTestService")
			L("LEAVE CanLeaveTest=" .. tostring(sts:CanLeaveTest()))
			task.delay(0.3, function()
				sts:LeaveTest()
			end)
			return true
		end
		return "unknown " .. tostring(cmd)
	end)
	if not ok then
		L("ORDER " .. tostring(cmd) .. " failed: " .. tostring(res))
		return { error = tostring(res) }
	end
	return res
end

-- a tool-started client can come up with a Fixed camera, which skips the game's own camera layer
task.spawn(function()
	task.wait(3)
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Fixed then
		cam.CameraType = Enum.CameraType.Custom
		L("CAMERA was Fixed 3 s after the bot started; set to Custom (test-only)")
	end
end)

L(string.format("BOT ready %s userId=%d display=%s modules: state=%s input=%s combat=%s camera=%s visuals=%s inv=%s spectate=%s", lp.Name, lp.UserId,
	lp.DisplayName, tostring(ClientState ~= nil), tostring(Input ~= nil), tostring(Combat ~= nil), tostring(CameraController ~= nil),
	tostring(Visuals ~= nil), tostring(Inventory ~= nil), tostring(Spectate ~= nil)))
repEv:FireServer("\0READY")
