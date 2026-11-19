-- ALT_Driver (allies test): test-only server driver, put into ServerScriptService by ServerStorage.Dev.AllyTest only
-- while a test starts. Outside such a test (no test args, or not Studio) it does nothing. Lines start with "[MPT]".
local RunService = game:GetService("RunService")
if not RunService:IsStudio() or not RunService:IsServer() then
	return
end
local STS = game:GetService("StudioTestService")
local okArgs, ARGS = pcall(function()
	return STS:GetTestArgs()
end)
if not okArgs or type(ARGS) ~= "table" or ARGS.suite ~= "allytest" then
	return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")

local seq = 0
local function now(): number
	return workspace:GetServerTimeNow() % 100000
end
local function L(s: string)
	seq += 1
	print(string.format("[MPT] %04d %.3f %s", seq, now(), s))
end
local function json(v: any): string
	local ok, res = pcall(HttpService.JSONEncode, HttpService, v)
	return if ok then res else tostring(v)
end
L("allytest driver starting " .. json(ARGS))

local ended = false
local function endTest(summary: string)
	if ended then
		return
	end
	ended = true
	L("ENDTEST " .. summary)
	task.wait(1.5)
	pcall(function()
		STS:EndTest(summary)
	end)
end
task.delay(tonumber(ARGS.failsafe) or 320, function()
	endTest("failsafe")
end)
LogService.MessageOut:Connect(function(message, kind)
	if (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning) and not string.find(message, "[MPT]", 1, true) then
		task.defer(L, "LOG-W " .. string.sub((string.gsub(message, "\n", " | ")), 1, 300))
	end
end)

local GS = RS:WaitForChild("GameState")
local Config = require(RS:WaitForChild("Shared"):WaitForChild("Config"))
Config.Round.MinPlayers = 99 -- held in the Lobby (the prep room) until the prep checks are done
Config.Round.SoloPractice = false
GS:SetAttribute("LaunchCutTest", "Short")

local Services = SSS:WaitForChild("Server"):WaitForChild("Services")
local Ally = require(Services:WaitForChild("AllyService"))
local Combat = require(Services:WaitForChild("CombatService"))

-- bot remotes
local callFn = Instance.new("RemoteFunction")
callFn.Name = "MPT_Call"
callFn.Parent = RS
local repEv = Instance.new("RemoteEvent")
repEv.Name = "MPT_Rep"
repEv.Parent = RS
local ready: { [Player]: boolean } = {}
repEv.OnServerEvent:Connect(function(p, text)
	if text == "\0READY" then
		ready[p] = true
		L("BOT READY " .. p.Name)
	elseif type(text) == "string" then
		for line in string.gmatch(text, "[^\n]+") do
			seq += 1
			print(string.format("[MPT] %04d C:%s %s", seq, p.Name, line))
		end
	end
end)
local botTemplate = script:FindFirstChild("ALT_Bot")
Players.PlayerAdded:Connect(function(p)
	L("PLAYER+ " .. p.Name .. " " .. p.UserId)
	local gui = p:WaitForChild("PlayerGui", 20)
	if gui and botTemplate then
		local holder = Instance.new("ScreenGui")
		holder.Name = "MPT"
		holder.ResetOnSpawn = false
		holder.Enabled = false
		local copy = botTemplate:Clone()
		copy.Disabled = false
		copy.Parent = holder
		holder.Parent = gui
	end
end)
for _, n in ipairs({ "Phase", "AliveCount", "ArenaEvent", "StartedCount" }) do
	GS:GetAttributeChangedSignal(n):Connect(function()
		L("GS " .. n .. "=" .. tostring(GS:GetAttribute(n)))
	end)
end

local function call(p: Player, cmd: string, arg: any, timeout: number?): any
	local done, result = false, nil
	task.spawn(function()
		local ok, res = pcall(function()
			return callFn:InvokeClient(p, cmd, arg)
		end)
		result = if ok then res else { error = tostring(res) }
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < (timeout or 8) do
		task.wait(0.03)
	end
	return result
end
local function fmt(v: any): string
	return json(v)
end
local function check(id: string, pass: boolean?, detail: string)
	L(string.format("[CHECK] %s %s %s", id, if pass == true then "PASS" elseif pass == false then "FAIL" else "NOTE", detail))
end
local function waitFor(cond: () -> any, timeout: number): any
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local v = cond()
		if v then
			return v
		end
		task.wait(0.1)
	end
	return nil
end
local function shot(name: string)
	L("SHOT " .. name)
	task.wait(1.2)
end
local function st(p: Player): any
	return call(p, "ally", { "state" }) or {}
end
local function hasLine(s: any, needle: string): boolean
	for _, l in ipairs(s.lines or {}) do
		if string.find(l, needle, 1, true) then
			return true
		end
	end
	return false
end
local function root(p: Player): BasePart?
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end
-- puts b `dist` studs in front of a, facing a (on a's floor height)
local function faceToFace(a: Player, b: Player, dist: number)
	local ra, rb = root(a), root(b)
	if not (ra and rb) then
		return
	end
	local look = ra.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	local pos = ra.Position + look.Unit * dist
	rb.AssemblyLinearVelocity = Vector3.zero
	b.Character:PivotTo(CFrame.lookAt(pos, Vector3.new(ra.Position.X, pos.Y, ra.Position.Z)))
	a.Character:PivotTo(CFrame.lookAt(ra.Position, Vector3.new(pos.X, ra.Position.Y, pos.Z)))
end
local function allied(): boolean
	local ps = Players:GetPlayers()
	return #ps >= 2 and Ally.allied(ps[1], ps[2])
end
-- a offers by the walk-up gesture, b answers with T held and nobody in view
local function gesture(a: Player, b: Player, tag: string): boolean
	call(a, "ally", { "aim", b.UserId })
	task.wait(0.3)
	local sa = st(a)
	check(tag .. ".hint", string.find(sa.hint or "", b.DisplayName, 1, true) ~= nil, "A's line under the crosshair: '" .. tostring(sa.hint) .. "'")
	call(a, "ally", { "hold", 0.5 })
	call(a, "ally", { "aim", nil })
	local seen = waitFor(function()
		local sb = st(b)
		return if string.find(sb.offer or "", a.DisplayName, 1, true) then sb else nil
	end, 4)
	check(tag .. ".offerSeen", seen ~= nil, "B's offer line: '" .. tostring(seen and seen.offer) .. "'")
	return seen ~= nil
end

-- the test ---------------------------------------------------------------------------------------------------------------
task.spawn(function()
	if not waitFor(function()
		local n = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if ready[p] and root(p) then
				n += 1
			end
		end
		return n >= 2
	end, 90) then
		endTest("bots not ready")
		return
	end
	task.wait(3)
	local list = Players:GetPlayers()
	table.sort(list, function(x, y)
		return x.UserId > y.UserId -- Player1 (-1) first
	end)
	local A, B = list[1], list[2]
	L("A=" .. A.Name .. " B=" .. B.Name .. " phase=" .. tostring(GS:GetAttribute("Phase")))

	-- 1. the prep room with two players: no truce (cap 0 at 4 or fewer)
	faceToFace(A, B, 6)
	task.wait(0.5)
	call(A, "ally", { "aim", B.UserId })
	task.wait(0.3)
	call(A, "ally", { "hold", 0.5 })
	call(A, "ally", { "aim", nil })
	task.wait(1)
	local s = st(A)
	check("cap.small", hasLine(s, "Truces need five or more contenders") and not allied(), "A after asking with 2 players: " .. fmt(s.lines))

	-- 2. as if 5..11 were waiting (Studio switch): pairs. The quiet list first.
	GS:SetAttribute("AllyCapTest", 2)
	task.wait(1.2)
	call(A, "ally", { "tap" })
	task.wait(0.5)
	s = st(A)
	check("list.open", s.listOpen == true and #(s.rows or {}) >= 1, "A's quiet list: open=" .. tostring(s.listOpen) .. " rows=" .. fmt(s.rows) .. " cap=" .. tostring(s.cap))
	shot("prep_list")
	call(A, "ally", { "list", false })

	-- 3. the gesture: A offers, B accepts by holding T
	gesture(A, B, "prep")
	shot("prep_offer")
	call(B, "ally", { "hold", 0.5 })
	check("prep.allied", waitFor(allied, 4) ~= nil, "server: allied=" .. tostring(allied()))
	task.wait(1)
	local sa, sb = st(A), st(B)
	check("prep.lines", hasLine(sa, "Truce agreed") and hasLine(sb, "Truce agreed"), "A " .. fmt(sa.lines) .. " B " .. fmt(sb.lines))
	check("prep.marks", #(sa.marks or {}) == 1 and sa.marks[1].enabled == true and #(sb.marks or {}) == 1 and sb.marks[1].enabled == true,
		"A marks " .. fmt(sa.marks) .. " B marks " .. fmt(sb.marks))
	shot("prep_marks")

	-- 4. leave, then agree again through the list (offer, then accept)
	call(B, "ally", { "send", "leave" })
	task.wait(1)
	sa, sb = st(A), st(B)
	check("prep.leave", not allied() and hasLine(sb, "You left the truce") and (hasLine(sa, "left the truce") or hasLine(sa, "The truce is over")),
		"A " .. fmt(sa.lines) .. " B " .. fmt(sb.lines))
	call(A, "ally", { "list", true })
	task.wait(0.4)
	local pressed = call(A, "ally", { "press", B.UserId })
	call(A, "ally", { "list", false })
	task.wait(0.8)
	call(B, "ally", { "list", true })
	task.wait(0.4)
	sb = st(B)
	local pressedB = call(B, "ally", { "press", A.UserId })
	check("list.accept", waitFor(allied, 4) ~= nil, "A pressed " .. tostring(pressed) .. ", B's rows " .. fmt(sb.rows) .. ", B pressed " .. tostring(pressedB))
	call(B, "ally", { "list", false })

	-- 5. the call: both are contenders, the truce holds (Studio: four-left rule at 1 so a 2-player round keeps it)
	GS:SetAttribute("AllyEndAtTest", 0)
	Config.Round.SoloPractice = true
	Config.Round.MinPlayers = 2
	GS:SetAttribute("MinPlayers", 2)
	L("RELEASE")
	if not waitFor(function()
		return GS:GetAttribute("Phase") == "Countdown"
	end, 60) then
		endTest("no countdown")
		return
	end
	task.wait(0.5)
	check("call.kept", allied(), "allied at the call=" .. tostring(allied()))
	local ra, rb = root(A), root(B)
	if ra and rb then
		local arena = workspace:FindFirstChild("Arena")
		local c = arena and arena:GetAttribute("Center")
		c = if typeof(c) == "Vector3" then c else Vector3.zero
		local function ang(p: Vector3)
			return math.deg(math.atan2(p.X - c.X, -(p.Z - c.Z)))
		end
		local d = math.abs(ang(ra.Position) - ang(rb.Position)) % 360
		check("call.plinths", nil, string.format("their plinths are %.0f degrees apart (2 contenders: the even spread puts them at 180; the ally hook is RoundService's to call)", math.min(d, 360 - d)))
	end
	if not waitFor(function()
		return GS:GetAttribute("Phase") == "Active"
	end, 40) then
		endTest("no horn")
		return
	end
	task.wait(3)

	-- 6. the arena: the marks and the compass ticks
	faceToFace(A, B, 24)
	task.wait(1.5)
	sa, sb = st(A), st(B)
	check("arena.marks", #(sa.marks or {}) == 1 and sa.marks[1].enabled == true and #(sb.marks or {}) == 1,
		"A " .. fmt(sa.marks) .. " B " .. fmt(sb.marks))
	check("arena.compass", sa.marks and sa.marks[1] and sa.marks[1].tick == true and math.abs(tonumber(sa.marks[1].tickX) or 999) < 30,
		"A's compass tick: " .. fmt(sa.marks and sa.marks[1]))
	shot("arena_marks")

	-- 7. the Offering's bell ends it for everyone
	GS:SetAttribute("ArenaEvent", "Feast")
	task.wait(1.2)
	sa, sb = st(A), st(B)
	check("bell.ends", not allied() and hasLine(sa, "The truce is over") and hasLine(sb, "The truce is over"), "A " .. fmt(sa.lines) .. " B " .. fmt(sb.lines))
	shot("bell_line")
	task.wait(1.5)
	sa = st(A)
	check("bell.fade", #(sa.marks or {}) == 0, "A's marks 2.7 s after the bell: " .. fmt(sa.marks))
	-- no truce after the bell
	faceToFace(A, B, 6)
	call(A, "ally", { "aim", B.UserId })
	task.wait(0.3)
	call(A, "ally", { "hold", 0.5 })
	call(A, "ally", { "aim", nil })
	task.wait(1)
	sa = st(A)
	check("bell.noNew", not allied() and hasLine(sa, "No truces after the bell"), "A " .. fmt(sa.lines))
	GS:SetAttribute("ArenaEvent", "")
	Ally._testReset()

	-- 8. the arena gesture (B12) agrees one again; the four-left rule ends it
	gesture(A, B, "arena")
	call(B, "ally", { "hold", 0.5 })
	check("arena.allied", waitFor(allied, 4) ~= nil, "allied=" .. tostring(allied()))
	GS:SetAttribute("AllyEndAtTest", 2) -- two are left: "four left" for this test
	task.wait(1.5)
	sa, sb = st(A), st(B)
	check("four.ends", not allied() and hasLine(sa, "The truce is over") and hasLine(sb, "The truce is over"), "A " .. fmt(sa.lines) .. " B " .. fmt(sb.lines))
	GS:SetAttribute("AllyEndAtTest", 0)

	-- 9. damage between allies: it lands (never blocked) and it breaks the truce
	gesture(A, B, "again")
	call(B, "ally", { "hold", 0.5 })
	check("again.allied", waitFor(allied, 4) ~= nil, "allied=" .. tostring(allied()))
	local hb = B.Character and B.Character:FindFirstChildOfClass("Humanoid")
	local before = if hb then hb.Health else -1
	local ok, dealt = pcall(Combat.applyHit, A, hb, 12, { cause = "Combat", weaponId = "knife", melee = true, position = root(A) and root(A).Position })
	task.wait(1.2)
	local after = if hb then hb.Health else -1
	sa, sb = st(A), st(B)
	check("hit.lands", ok and after < before, string.format("B's health %.1f -> %.1f (applyHit ok=%s dealt=%s)", before, after, tostring(ok), tostring(dealt)))
	check("hit.breaks", not allied() and hasLine(sb, A.DisplayName .. " broke the truce") and hasLine(sa, "You broke the truce"), "A " .. fmt(sa.lines) .. " B " .. fmt(sb.lines))
	shot("broke_line")
	task.wait(0.5)
	call(A, "ally", { "aim", B.UserId })
	task.wait(0.3)
	call(A, "ally", { "hold", 0.5 })
	call(A, "ally", { "aim", nil })
	task.wait(1)
	sa = st(A)
	check("broke.noAgain", not allied() and hasLine(sa, "A truce between you was broken this round"), "A " .. fmt(sa.lines))
	task.wait(2)
	endTest("done")
end)
