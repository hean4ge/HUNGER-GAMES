-- MPT_PolishClient (mp-polish, 20 Nov 2026): the client half of batch P (the owner's list of 20 Nov with two or three
-- players: the launch in first person all the way and the sun's glare, the music cues, the slide on a slope, the
-- hex border, the hills). Test only: MPT_Driver copies it into ReplicatedStorage while a Studio multiplayer test runs,
-- and MPT_Bot requires it for its "pmod" order. It reads the game's own controllers (the same module tables the game
-- uses: the bot is a LocalScript in the same VM) and reports; it never changes the game.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

return function(ctx: { [string]: any })
	local L: (string) -> () = ctx.L
	local fmt = ctx.fmt
	local Controllers: Instance = ctx.Controllers
	local ClientState = ctx.ClientState
	local touch: (string, boolean?) -> boolean = ctx.touch
	local move: (any) -> any = ctx.move
	local lp = Players.LocalPlayer
	local GS = RS:WaitForChild("GameState")

	local cache: { [string]: any } = {}
	local function C(name: string): any
		if cache[name] == nil then
			local m = Controllers:FindFirstChild(name)
			local ok, res = pcall(require, m)
			cache[name] = if ok then res else false
		end
		return cache[name] or nil
	end
	local function myRoot(): BasePart?
		local c = lp.Character
		return c and c:FindFirstChild("HumanoidRootPart") :: any
	end
	local function flat(a: Vector3, b: Vector3): number
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	local function r2(x: number): number
		return math.floor(x * 100 + 0.5) / 100
	end

	-- the launch: every rendered frame of the shot and the first seconds after it --------------------------------------
	local launch: { [string]: any } = { started = false }
	local launchConn: RBXScriptConnection? = nil
	local function coverAlpha(): number
		local g = lp.PlayerGui:FindFirstChild("LaunchShot")
		local f = g and g.Enabled and g:FindFirstChild("Root") and g.Root:FindFirstChild("Fade")
		return if f and f.Visible then 1 - f.BackgroundTransparency else 0
	end
	-- the cover's alpha only while it is a light one (the dip to black between the red room and the cases is not glare)
	local function lightCover(): number
		local g = lp.PlayerGui:FindFirstChild("LaunchShot")
		local f = g and g.Enabled and g:FindFirstChild("Root") and g.Root:FindFirstChild("Fade")
		if not (f and f.Visible) then
			return 0
		end
		local c = f.BackgroundColor3
		return if (c.R + c.G + c.B) / 3 > 0.5 then 1 - f.BackgroundTransparency else 0
	end
	local standIns: { Model } = {}
	local lastScan = 0
	local function scanStandIns()
		standIns = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d.Name == "StandIn" and d:IsA("Model") then
				table.insert(standIns, d)
			end
		end
	end
	local function armsInView(cam: Camera): (number, number)
		-- the block arms: parts under the camera, drawn, within 4 studs of the eye, in front of it
		local n, onScreen = 0, 0
		for _, d in ipairs(cam:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 0.95 and d.LocalTransparencyModifier < 0.95 then
				local rel = cam.CFrame:PointToObjectSpace(d.Position)
				if rel.Magnitude < 4 then
					n += 1
					local v, on = cam:WorldToViewportPoint(d.Position)
					if on and v.Z > 0 then
						onScreen += 1
					end
				end
			end
		end
		return n, onScreen
	end
	local function startLaunch()
		if launchConn then
			launchConn:Disconnect()
		end
		launch = { started = true, frames = 0, camTypes = {}, maxFlat = 0, minFlat = math.huge, sumFlat = 0, flatN = 0, noStandIn = 0,
			upMin = math.huge, upMax = -math.huge, armsFrames = 0, armsMax = 0, coverMax = 0, coverFrames95 = 0, exposureMax = -99,
			fovMin = 999, fovMax = 0, after = {}, shotSeen = false, ownDrawnNear = 0 }
		local lastShotCF: CFrame? = nil
		local lastShotFov = 0
		local endedAt: number? = nil
		launchConn = RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			if not cam then
				return
			end
			local playing = ClientState.launchShot == true
			if playing then
				launch.shotSeen = true
				launch.frames += 1
				launch.camTypes[cam.CameraType.Name] = (launch.camTypes[cam.CameraType.Name] or 0) + 1
				if os.clock() - lastScan > 0.5 then
					lastScan = os.clock()
					scanStandIns()
				end
				local p = cam.CFrame.Position
				local best, bestRoot = math.huge, nil
				for _, m in ipairs(standIns) do
					local r = m.Parent and (m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Root"))
					if r and r:IsA("BasePart") then
						local d = flat(p, r.Position)
						if d < best then
							best, bestRoot = d, r
						end
					end
				end
				if bestRoot then
					launch.maxFlat = math.max(launch.maxFlat, best)
					launch.minFlat = math.min(launch.minFlat, best)
					launch.sumFlat += best
					launch.flatN += 1
					local up = p.Y - bestRoot.Position.Y
					launch.upMin = math.min(launch.upMin, up)
					launch.upMax = math.max(launch.upMax, up)
					-- your own stand-in is never drawn: no drawn part of the nearest stand-in within 1.2 studs of the eye
					if best < 1 then
						for _, d in ipairs((bestRoot.Parent :: Instance):GetDescendants()) do
							if d:IsA("BasePart") and (d.Position - p).Magnitude < 1.2 and d.Transparency < 0.95 and d.LocalTransparencyModifier < 0.95 then
								launch.ownDrawnNear += 1
								break
							end
						end
					end
				else
					launch.noStandIn += 1
				end
				local n = armsInView(cam)
				if n > 0 then
					launch.armsFrames += 1
				end
				launch.armsMax = math.max(launch.armsMax, n)
				local a = lightCover()
				launch.blackMax = math.max(launch.blackMax or 0, coverAlpha())
				launch.coverMax = math.max(launch.coverMax, a)
				if a > 0.951 then
					launch.coverFrames95 += 1
				end
				launch.fovMin = math.min(launch.fovMin, cam.FieldOfView)
				launch.fovMax = math.max(launch.fovMax, cam.FieldOfView)
				launch.exposureMax = math.max(launch.exposureMax, Lighting.ExposureCompensation)
				lastShotCF, lastShotFov = cam.CFrame, cam.FieldOfView
			elseif launch.shotSeen then
				if not endedAt then
					endedAt = os.clock()
					launch.endedAt = workspace:GetServerTimeNow()
					local root = myRoot()
					local head = lp.Character and lp.Character:FindFirstChild("Head")
					if lastShotCF then
						local ang = math.deg(math.acos(math.clamp(lastShotCF.LookVector:Dot(cam.CFrame.LookVector), -1, 1)))
						local yawA = math.deg(math.atan2(-lastShotCF.LookVector.X, -lastShotCF.LookVector.Z))
						local yawB = math.deg(math.atan2(-cam.CFrame.LookVector.X, -cam.CFrame.LookVector.Z))
						launch.handoff = { lookJumpDeg = r2(ang), yawShot = r2(yawA), yawNow = r2(yawB), fovShot = r2(lastShotFov), fovNow = r2(cam.FieldOfView),
							camToHead = if head then r2((cam.CFrame.Position - head.Position).Magnitude) else -1, camType = cam.CameraType.Name,
							rootPos = if root then root.Position else nil }
					end
				end
				local since = os.clock() - endedAt
				if since < 3.0 then
					local head = lp.Character and lp.Character:FindFirstChild("Head")
					local slot = math.floor(since / 0.25)
					if not launch.after[slot + 1] then
						launch.after[slot + 1] = string.format("%.2f:cover=%.2f exp=%.2f head=%.2f", since, coverAlpha(), Lighting.ExposureCompensation,
							if head then (cam.CFrame.Position - head.Position).Magnitude else -1)
					end
					launch.exposureAfterMax = math.max(launch.exposureAfterMax or -99, Lighting.ExposureCompensation)
					launch.coverAfterMax = math.max(launch.coverAfterMax or 0, coverAlpha())
				elseif launchConn then
					launchConn:Disconnect()
					launchConn = nil
				end
			end
		end)
	end
	local function launchReport(): { [string]: any }
		local out = table.clone(launch)
		out.meanFlat = if launch.flatN and launch.flatN > 0 then r2(launch.sumFlat / launch.flatN) else -1
		out.maxFlat = r2(launch.maxFlat or -1)
		out.minFlat = r2(if launch.minFlat == math.huge then -1 else launch.minFlat)
		out.upMin, out.upMax = r2(launch.upMin or 0), r2(launch.upMax or 0)
		out.sumFlat, out.flatN = nil, launch.flatN
		out.after = table.concat(launch.after or {}, " ")
		out.stats = lp:GetAttribute("LS_LaunchStats")
		out.glare = lp:GetAttribute("LS_LaunchGlare")
		local Detail = lp:GetAttribute("DetailTier")
		out.detailTier = Detail
		out.reducedMotion = (function()
			local ok, v = pcall(function()
				return game:GetService("UserGameSettings").ReducedMotion
			end)
			return if ok then v else "?"
		end)()
		return out
	end

	-- the music: every change of cue, and the most beds heard together ----------------------------------------------------
	local music: { [string]: any } = { changes = {}, maxBeds = 0, samples = 0 }
	local musicConn: thread? = nil
	local function startMusic()
		music = { changes = {}, maxBeds = 0, samples = 0, maxAudible = 0 }
		local MC = C("MusicController")
		if not MC then
			music.error = "no MusicController"
			return
		end
		musicConn = task.spawn(function()
			local last = "?"
			while true do
				local ok, cue = pcall(MC.currentCue)
				cue = if ok then tostring(cue) else "err"
				local okS, st = pcall(MC.debugState)
				local beds, audible = 0, 0
				if okS and type(st) == "table" and type(st.beds) == "table" then
					for _, b in ipairs(st.beds) do
						beds += 1
						if (tonumber(b.volume) or 0) > 0.02 then
							audible += 1
						end
					end
				end
				music.samples += 1
				music.maxBeds = math.max(music.maxBeds, beds)
				music.maxAudible = math.max(music.maxAudible, audible)
				if cue ~= last then
					last = cue
					local line = string.format("%.1f %s %s", workspace:GetServerTimeNow() % 100000, cue, tostring(GS:GetAttribute("Phase")))
					table.insert(music.changes, line)
					L("MUSIC cue " .. line .. " duck=" .. (if okS and type(st) == "table" then fmt(st.duck) else "?"))
				end
				task.wait(0.25)
			end
		end)
	end
	local function musicReport(): { [string]: any }
		local out = { changes = table.concat(music.changes, " | "), n = #music.changes, maxBeds = music.maxBeds, maxAudible = music.maxAudible,
			samples = music.samples, error = music.error, debug = SoundService:GetAttribute("MusicDebug") }
		local MC = C("MusicController")
		out.cue = MC and tostring(MC.currentCue()) or "?"
		local list = {}
		for _, line in ipairs(music.changes) do
			local cue = string.match(line, "^%S+ (%S+)")
			table.insert(list, cue)
		end
		out.order = table.concat(list, ">")
		return out
	end

	-- the slide: run, crouch, ride it out ---------------------------------------------------------------------------------
	local function slide(arg: any): { [string]: any }
		local MC = C("MovementController")
		if not MC then
			return { error = "no MovementController" }
		end
		local root = myRoot()
		if not root then
			return { error = "no character" }
		end
		local before = MC.getLastSlide()
		local beforeAt = before and before.endedAt
		local facePoint = Vector3.new(arg.face.x, arg.face.y, arg.face.z)
		move({ seconds = (arg.run or 1.4) + 7, face = facePoint })
		-- the touch RUN button is "Auto" by default (a full stick push sprints; holding RUN jogs) and the bot's push is
		-- not a stick: for the test the touch mode is Hold, so RUN held is a sprint (put back afterwards)
		local oldMode = ClientState.settings.sprintModeTouch
		if arg.sprint ~= false then
			ClientState.settings.sprintModeTouch = 0
			touch("Sprint", true)
		end
		local t0 = os.clock()
		local runMax = 0
		while os.clock() - t0 < (arg.run or 1.4) do
			local v = root.AssemblyLinearVelocity
			runMax = math.max(runMax, Vector3.new(v.X, 0, v.Z).Magnitude)
			task.wait()
		end
		local moveState0 = tostring(ClientState.moveState)
		local startPos = root.Position
		touch("Crouch", true)
		local slid, maxSpeed, startedAt = false, 0, os.clock()
		local material, slope = "?", 0
		while os.clock() - startedAt < 7 do
			local s = MC.getSlide()
			if s and s.active then
				slid = true
				maxSpeed = math.max(maxSpeed, tonumber(s.speed) or 0)
				material = tostring(s.material)
				slope = math.max(slope, math.deg(math.asin(math.clamp(math.abs(tonumber(s.slopeSin) or 0), 0, 1))))
			elseif slid then
				break
			elseif os.clock() - startedAt > 0.8 then
				break
			end
			task.wait()
		end
		-- off: a hold button ends on release; a toggle button needs a second press
		touch("Crouch", false)
		task.wait(0.1)
		if ClientState.moveState == "Crouch" or ClientState.moveState == "Slide" then
			touch("Crouch", true)
		end
		if arg.sprint ~= false then
			touch("Sprint", false)
			ClientState.settings.sprintModeTouch = oldMode
		end
		move({})
		local last = MC.getLastSlide()
		local fresh = last and last.endedAt ~= beforeAt
		return { slid = slid, fresh = fresh, time = fresh and r2(last.time) or 0, dist = fresh and r2(last.distance) or 0, entry = fresh and r2(last.entry) or 0,
			maxSpeed = r2(maxSpeed), runMax = r2(runMax), moveStateAtCrouch = moveState0, material = material, slopeDeg = r2(slope),
			startPos = startPos, endPos = root.Position, drop = r2(startPos.Y - root.Position.Y), stateNow = tostring(ClientState.moveState) }
	end

	-- another player's slide as this screen sees it: their Stance and the spray beside them ------------------------------
	local function watchSlide(arg: any): { [string]: any }
		local p = Players:FindFirstChild(arg.target)
		local c = p and p:IsA("Player") and p.Character
		if not c then
			return { error = "no target" }
		end
		local out = { stanceSlide = 0, sprayFrames = 0, chipsMax = 0, samples = 0, rateMax = 0 }
		local t0 = os.clock()
		while os.clock() - t0 < (arg.seconds or 6) do
			out.samples += 1
			if c:GetAttribute("Stance") == "Slide" then
				out.stanceSlide += 1
			end
			local r = c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				local seen = false
				for _, att in ipairs(workspace.Terrain:GetChildren()) do
					if att.Name == "SlideFx" and att:IsA("Attachment") and (att.WorldPosition - r.Position).Magnitude < 8 then
						local chips = att:FindFirstChild("Chips") :: ParticleEmitter?
						if chips and chips.Enabled and chips.Rate > 0 then
							seen = true
							out.rateMax = math.max(out.rateMax, chips.Rate)
						end
					end
				end
				if seen then
					out.sprayFrames += 1
				end
			end
			task.wait(0.1)
		end
		return out
	end

	-- a walk through waypoints, as a held W (and Shift) on the real ground ------------------------------------------------
	local function walk(arg: any): { [string]: any }
		local root = myRoot()
		if not root then
			return { error = "no character" }
		end
		local pts = arg.points
		local out = { legs = {}, stuck = 0, worstWindow = math.huge, maxH = -math.huge, minH = math.huge, distance = 0, reached = 0, falls = 0 }
		local oldMode = ClientState.settings.sprintModeTouch
		if arg.sprint then
			ClientState.settings.sprintModeTouch = 0
			touch("Sprint", true)
		end
		local hist: { { t: number, p: Vector3 } } = {}
		local last = root.Position
		for i, q in ipairs(pts) do
			local target = Vector3.new(q.x, q.y or root.Position.Y, q.z)
			local t0 = os.clock()
			local reached = false
			local speeds = {}
			while os.clock() - t0 < (arg.legTime or 25) do
				local pos = root.Position
				local aim = Vector3.new(target.X, pos.Y + 1.0, target.Z)
				move({ seconds = 0.5, face = aim })
				if flat(pos, target) < (arg.within or 4) then
					reached = true
					break
				end
				out.distance += flat(pos, last)
				last = pos
				out.maxH, out.minH = math.max(out.maxH, pos.Y), math.min(out.minH, pos.Y)
				local now = os.clock()
				table.insert(hist, { t = now, p = pos })
				while #hist > 0 and now - hist[1].t > 2.0 do
					table.remove(hist, 1)
				end
				if #hist > 4 and now - hist[1].t > 1.8 then
					local moved = flat(pos, hist[1].p)
					out.worstWindow = math.min(out.worstWindow, moved)
					if moved < 1.5 then
						out.stuck += 1
						L(string.format("WALK stuck? leg %d at %s moved %.2f in 2 s", i, fmt(pos), moved))
						hist = {}
					end
				end
				local v = root.AssemblyLinearVelocity
				table.insert(speeds, Vector3.new(v.X, 0, v.Z).Magnitude)
				task.wait(0.1)
			end
			local sum = 0
			for _, s in ipairs(speeds) do
				sum += s
			end
			if reached then
				out.reached += 1
			end
			table.insert(out.legs, string.format("leg%d %s %.1fs mean %.1f st/s end %s", i, if reached then "reached" else "NOT reached", os.clock() - t0,
				if #speeds > 0 then sum / #speeds else 0, fmt(root.Position)))
		end
		move({})
		if arg.sprint then
			touch("Sprint", false)
			ClientState.settings.sprintModeTouch = oldMode
		end
		out.worstWindow = if out.worstWindow == math.huge then -1 else r2(out.worstWindow)
		out.distance = r2(out.distance)
		out.legs = table.concat(out.legs, " | ")
		out.climb = r2(out.maxH - out.minH)
		out.maxH, out.minH = r2(out.maxH), r2(out.minH)
		out.health = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid") and lp.Character:FindFirstChildOfClass("Humanoid").Health
		return out
	end

	-- the border wall on this screen ---------------------------------------------------------------------------------------
	local function border(): { [string]: any }
		local AC = Controllers:FindFirstChild("ArenaController")
		local wallM = AC and AC:FindFirstChild("Wall")
		local ok, Wall = pcall(require, wallM)
		local out: { [string]: any } = {}
		if ok and Wall and Wall.stats then
			local okS, st = pcall(Wall.stats)
			out = if okS and type(st) == "table" then table.clone(st) else { error = tostring(st) }
		else
			out.error = "no Wall module: " .. tostring(Wall)
		end
		local folder = workspace:FindFirstChild("Arena") and workspace.Arena:FindFirstChild("Border")
		out.folder = folder ~= nil
		local guis, guisOn = 0, 0
		if folder then
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("SurfaceGui") then
					guis += 1
					if d.Enabled then
						guisOn += 1
					end
				end
			end
		end
		out.surfaceGuis, out.surfaceGuisOn = guis, guisOn
		out.hexConfig = tostring(require(RS.Shared.Config).Border.HexImage)
		out.moving = GS:GetAttribute("BorderMoving") or GS:GetAttribute("BorderShrinking")
		local root = myRoot()
		out.at = root and root.Position
		return out
	end

	local function fps(): string
		local r, t0 = 0, os.clock()
		local c1 = RunService.RenderStepped:Connect(function()
			r += 1
		end)
		task.wait(1.0)
		c1:Disconnect()
		return string.format("%.1f", r / (os.clock() - t0))
	end

	return function(op: string, arg: any): any
		if op == "launch.start" then
			startLaunch()
			return true
		elseif op == "launch.report" then
			return launchReport()
		elseif op == "music.start" then
			startMusic()
			return true
		elseif op == "music.report" then
			return musicReport()
		elseif op == "slide" then
			return slide(arg)
		elseif op == "watchSlide" then
			return watchSlide(arg)
		elseif op == "walk" then
			return walk(arg)
		elseif op == "border" then
			return border()
		elseif op == "fps" then
			return fps()
		elseif op == "debug" then
			local MC = C("MovementController")
			return MC and MC.getDebug and HttpService:JSONEncode((function()
				local t = {}
				for k, v in pairs(MC.getDebug()) do
					if type(v) ~= "table" and typeof(v) ~= "Instance" then
						t[k] = if type(v) == "number" then r2(v) else tostring(v)
					end
				end
				return t
			end)())
		end
		return "unknown op " .. tostring(op)
	end
end
