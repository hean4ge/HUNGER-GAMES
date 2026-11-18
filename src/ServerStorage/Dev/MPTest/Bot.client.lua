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
		out.overLine = out.active == true and out.lineShown == true and type(out.winX) == "number" and (out.winW or 0) > 0 and out.winX + out.winW > out.lineX
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
