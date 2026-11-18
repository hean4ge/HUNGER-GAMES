-- studio_read_rig.luau - prints the R15 rig this place spawns as JSON (save the output as r15_rig.json).
-- execute_luau, Edit datamodel. Read-only: the model is never parented and is destroyed at the end.
-- Works for both joint kinds: AnimationConstraint (Avatar Joint Upgrade, what this place uses) and Motor6D.
local Http = game:GetService("HttpService")
local function r(v) return math.round(v * 100000) / 100000 end
local function cf(c) local t = { c:GetComponents() } for i, v in t do t[i] = r(v) end return t end
local m = game:GetService("Players"):CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
local hrp = m.HumanoidRootPart
local data = {
	source = "Players:CreateHumanoidModelFromDescription(blank HumanoidDescription, R15), unparented",
	note = "Part cframes are the UNASSEMBLED layout. The rest pose is forward kinematics: child = parent * c0 * c1^-1.",
	space = "Roblox studs, relative to HumanoidRootPart",
	hipHeight = r(m.Humanoid.HipHeight), parts = {}, joints = {}, attachments = {},
}
for _, p in m:GetChildren() do
	if p:IsA("BasePart") then
		data.parts[p.Name] = { size = { r(p.Size.X), r(p.Size.Y), r(p.Size.Z) }, cframe = cf(hrp.CFrame:ToObjectSpace(p.CFrame)), meshId = p:IsA("MeshPart") and p.MeshId or nil }
	end
end
for _, d in m:GetDescendants() do
	if d:IsA("AnimationConstraint") then
		table.insert(data.joints, { name = d.Name, class = d.ClassName, child = d.Parent.Name, parent = d.Attachment0.Parent.Name, c0 = cf(d.Attachment0.CFrame), c1 = cf(d.Attachment1.CFrame), att0 = d.Attachment0.Name, att1 = d.Attachment1.Name })
	elseif d:IsA("Motor6D") and d.Part0 and d.Part1 then
		table.insert(data.joints, { name = d.Name, class = d.ClassName, child = d.Part1.Name, parent = d.Part0.Name, c0 = cf(d.C0), c1 = cf(d.C1) })
	elseif d:IsA("Attachment") and (d.Name == "RightGripAttachment" or d.Name == "LeftGripAttachment") then
		data.attachments[d.Name] = { part = d.Parent.Name, cframe = cf(d.CFrame) }
	end
end
m:Destroy()
return Http:JSONEncode(data)
