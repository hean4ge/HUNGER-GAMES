-- studio_build_kfs.luau - builds a KeyframeSequence from a <Name>.studio.json (ls_anim_studio/1) made by ls_anim.py.
-- Run through the Studio tool's execute_luau in the Edit datamodel. make_studio_luau.py pastes the JSON in for SRC,
-- and sets LABEL / FOLDER. Nothing is uploaded. The sequence is parented to ServerStorage.<FOLDER>.
local SRC = [==[__JSON__]==]
local LABEL = "__LABEL__"
local FOLDER = "__FOLDER__"

local Http = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local data = Http:JSONDecode(SRC)
assert(data.format == "ls_anim_studio/1", "unknown format")

-- 1. the numbers arrived intact
local sum, count = 0, 0
for _, row in data.frames do
	for _, tr in row do
		for _, v in tr do
			sum = (sum + v * (count % 7 + 1)) % 1000000007
			count += 1
		end
	end
end
if sum ~= data.checksum or count ~= data.count then
	return string.format("CHECKSUM MISMATCH: got %d numbers / %d, expected %d / %d. Nothing was built.", count, sum, data.count, data.checksum)
end

-- 2. shared-Studio lock (Workspace attribute QA_Lock = "<label>|<os.time()>")
local now = os.time()
local lock = workspace:GetAttribute("QA_Lock")
if typeof(lock) == "string" then
	local who, t = string.match(lock, "^(.-)|(%d+)$")
	if who ~= LABEL and t and now - tonumber(t) < 540 then
		return "LOCKED by " .. lock .. " (now " .. now .. "). Nothing was built."
	end
end
workspace:SetAttribute("QA_Lock", LABEL .. "|" .. now)

local ok, result = pcall(function()
	local S = data.scale
	local out = {}

	-- 3. the rig this place spawns must be the rig the clip was authored on
	local rig = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	local joints = {}
	for _, d in rig:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			joints[d.Parent.Name] = { d.Attachment0.Parent.Name, d.Attachment0.CFrame, d.Attachment1.CFrame, d.ClassName }
		elseif d:IsA("Motor6D") and d.Part1 then
			joints[d.Part1.Name] = { d.Part0.Name, d.C0, d.C1, d.ClassName }
		end
	end
	rig:Destroy()
	local worst, worstPart, jointClass = 0, "", ""
	for i, part in data.parts do
		local j = joints[part]
		assert(j, "this place's R15 rig has no joint driving " .. part)
		assert(j[1] == data.parents[i], part .. " hangs from " .. j[1] .. " here, from " .. data.parents[i] .. " in the clip")
		local r = data.rig[i]
		local e = math.max((j[2].Position - Vector3.new(r[1], r[2], r[3]) / S).Magnitude, (j[3].Position - Vector3.new(r[4], r[5], r[6]) / S).Magnitude)
		if e > worst then
			worst, worstPart = e, part
		end
		jointClass = j[4]
	end
	table.insert(out, string.format("rig check: %d joints (%s), worst attachment offset vs the authoring rig %.5f studs (%s)", #data.parts, jointClass, worst, worstPart))
	assert(worst < 0.01, "rig mismatch: re-read the rig from Studio and re-bake in Blender")

	-- 4. the sequence
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = data.name
	kfs.Loop = data.loop
	kfs.Priority = Enum.AnimationPriority[data.priority]
	pcall(function()
		kfs.AuthoredHipHeight = data.hipHeight
	end)
	for i, row in data.frames do
		local kf = Instance.new("Keyframe")
		kf.Name = "Keyframe"
		kf.Time = (i - 1) / data.fps
		local poses = {}
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		kf:AddPose(root)
		poses.HumanoidRootPart = root
		for j, part in data.parts do -- parents always come before their children
			local tr = row[j]
			local x, y, z = tr[1] / S, tr[2] / S, tr[3] / S
			local w = math.sqrt(math.max(0, 1 - x * x - y * y - z * z))
			local pose = Instance.new("Pose")
			pose.Name = part
			pose.CFrame = CFrame.new((tr[4] or 0) / S, (tr[5] or 0) / S, (tr[6] or 0) / S, x, y, z, w)
			pose.EasingStyle = Enum.PoseEasingStyle.Linear
			pose.EasingDirection = Enum.PoseEasingDirection.In
			poses[data.parents[j]]:AddSubPose(pose)
			poses[part] = pose
		end
		for _, m in data.markers do
			if m[2] == i - 1 then
				local marker = Instance.new("KeyframeMarker")
				marker.Name = m[1]
				marker.Value = ""
				kf:AddMarker(marker)
			end
		end
		kfs:AddKeyframe(kf)
	end
	kfs:SetAttribute("Source", "Blender ls_anim.py, " .. data.format)

	local folder = ServerStorage:FindFirstChild(FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER
		folder.Parent = ServerStorage
	end
	local old = folder:FindFirstChild(data.name)
	if old then
		old:Destroy()
	end
	kfs.Parent = folder
	table.insert(out, string.format("built %s: %d keyframes, %.4f s, %d poses per keyframe, in %s", kfs:GetFullName(), #kfs:GetKeyframes(), (#data.frames - 1) / data.fps, #data.parts + 1, folder:GetFullName()))
	return table.concat(out, "\n")
end)

workspace:SetAttribute("QA_Lock", nil)
return (ok and "OK\n" or "FAILED\n") .. tostring(result)
