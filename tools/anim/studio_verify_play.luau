-- studio_verify_play.luau - reads a script-built KeyframeSequence back and plays it on a rig WITHOUT a playtest and
-- WITHOUT an upload. execute_luau, Edit datamodel. As run on 2026-11-18 for ServerStorage._AnimProof.SwordSwing.
--   * KeyframeSequenceProvider:RegisterKeyframeSequence gives a temporary id (Studio only).
--   * The rig sits in a WorldModel inside the temp folder: a WorldModel assembles AnimationConstraints outside Workspace.
--   * Animator:StepAnimations(dt) advances the track from execute_luau. Wait for track.Length > 0 first: a clip that
--     has not finished loading steps to nowhere.
-- EXPECT = part positions relative to HumanoidRootPart from <Name>.anim.json "check" (keyframes 6 and 9 here).
local LABEL = "anim-proof"
local FOLDER = "_AnimProof"
local NAME = "SwordSwing"
local STEPS = { { 0.2, 6 }, { 0.1, 9 } } -- { seconds to step, keyframe index reached }
local EXPECT = {
	[6] = { RightHand = Vector3.new(0.21115, 1.55804, 1.47932), Head = Vector3.new(-0.26014, 1.541, 0.18275), LeftFoot = Vector3.new(-0.49785, -3.03644, 0), RightLowerArm = Vector3.new(0.63015, 1.11921, 1.69256), UpperTorso = Vector3.new(-0.07188, 0.13056, 0.18645) },
	[9] = { RightHand = Vector3.new(-0.10854, -0.19319, -2.00833), Head = Vector3.new(-0.10187, 1.42887, -0.68634), LeftFoot = Vector3.new(-0.49785, -3.03644, 0), RightLowerArm = Vector3.new(0.35945, -0.17008, -1.54281), UpperTorso = Vector3.new(-0.05375, 0.03835, -0.39516) },
}

local SS = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local KSP = game:GetService("KeyframeSequenceProvider")
local now = os.time()
local lock = workspace:GetAttribute("QA_Lock")
if typeof(lock) == "string" then
	local who, t = string.match(lock, "^(.-)|(%d+)$")
	if who ~= LABEL and t and now - tonumber(t) < 540 then return "LOCKED by " .. lock end
end
workspace:SetAttribute("QA_Lock", LABEL .. "|" .. now)
local out = {}
local function log(...) table.insert(out, string.format(...)) end
local ok, err = pcall(function()
	local folder = SS:FindFirstChild(FOLDER)
	local kfs = folder:FindFirstChild(NAME)
	local kfl = kfs:GetKeyframes()
	table.sort(kfl, function(a, b) return a.Time < b.Time end)
	log("A. %s %s: Loop=%s Priority=%s AuthoredHipHeight=%s keyframes=%d first=%.4f last=%.4f", kfs.ClassName, kfs.Name, tostring(kfs.Loop), tostring(kfs.Priority), tostring(kfs.AuthoredHipHeight), #kfl, kfl[1].Time, kfl[#kfl].Time)
	for i, kf in kfl do
		for _, m in kf:GetMarkers() do log("   marker %s (%s) on keyframe %d at t=%.4f s", m.Name, m.ClassName, i - 1, kf.Time) end
	end
	local rig = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	local jointOf, parentOf = {}, {}
	for _, d in rig:GetDescendants() do
		if d:IsA("AnimationConstraint") then jointOf[d.Parent.Name] = d parentOf[d.Parent.Name] = d.Attachment0.Parent.Name end
	end
	local poseCount, bad, seen = 0, {}, {}
	for _, d in kfl[1]:GetDescendants() do
		if d:IsA("Pose") then
			poseCount += 1
			seen[d.Name] = true
			local part = rig:FindFirstChild(d.Name)
			if not (part and part:IsA("BasePart")) then table.insert(bad, d.Name .. " is not an R15 part") end
			if d.Name ~= "HumanoidRootPart" and not (d.Parent:IsA("Pose") and d.Parent.Name == parentOf[d.Name]) then
				table.insert(bad, d.Name .. " nested under " .. d.Parent.Name .. ", rig says " .. tostring(parentOf[d.Name]))
			end
		end
	end
	for _, p in rig:GetChildren() do if p:IsA("BasePart") and not seen[p.Name] then table.insert(bad, "no pose for " .. p.Name) end end
	log("   poses in keyframe 0: %d; names and nesting vs the R15 rig: %s", poseCount, #bad == 0 and "all match" or table.concat(bad, "; "))

	local id = KSP:RegisterKeyframeSequence(kfs)
	log("B. temporary id %s; GetKeyframeSequenceAsync returns %d keyframes", id, #KSP:GetKeyframeSequenceAsync(id):GetKeyframes())

	local wm = Instance.new("WorldModel")
	wm.Name = "RigHolder"
	rig.HumanoidRootPart.Anchored = true
	rig.HumanoidRootPart.CFrame = CFrame.new(0, 500, 0)
	rig.Parent = wm
	wm.Parent = folder
	local animator = rig.Humanoid:FindFirstChildOfClass("Animator")
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	anim.Parent = folder
	local track = animator:LoadAnimation(anim)
	local t0 = os.clock()
	while track.Length <= 0 and os.clock() - t0 < 8 do task.wait() end
	log("C. loaded in %.2f s: Length=%.4f Priority=%s Looped=%s", os.clock() - t0, track.Length, tostring(track.Priority), tostring(track.Looped))
	local hits = {}
	track:GetMarkerReachedSignal("Hit"):Connect(function() table.insert(hits, string.format("%.4f", track.TimePosition)) end)
	track:Play(0, 1, 1)
	local function poseOf(kf, name) for _, d in kf:GetDescendants() do if d:IsA("Pose") and d.Name == name then return d.CFrame end end end
	local hrp = rig.HumanoidRootPart
	for _, step in STEPS do
		animator:StepAnimations(step[1])
		local worstA, wn = 0, ""
		for name, j in jointOf do
			local _, ang = poseOf(kfl[step[2] + 1], name):ToObjectSpace(j.Transform):ToAxisAngle()
			if ang > math.pi then ang = 2 * math.pi - ang end
			if math.deg(ang) > worstA then worstA, wn = math.deg(ang), name end
		end
		task.wait()
		local worst, wp = 0, ""
		for n2, want in EXPECT[step[2]] or {} do
			local e2 = (hrp.CFrame:ToObjectSpace(rig[n2].CFrame).Position - want).Magnitude
			if e2 > worst then worst, wp = e2, n2 end
		end
		log("   t=%.4f: joint Transforms vs keyframe %d worst %.4f deg (%s); part positions vs Blender worst %.5f studs (%s)", track.TimePosition, step[2], worstA, wn, worst, wp)
	end
	animator:StepAnimations(0.05)
	task.wait()
	task.wait()
	log("   marker signal 'Hit' fired %d time(s)", #hits)
	track:Stop(0)
	wm:Destroy()
	anim:Destroy()
end)
workspace:SetAttribute("QA_Lock", nil)
return (ok and "OK\n" or ("FAILED " .. tostring(err) .. "\n")) .. table.concat(out, "\n")
