--[[
	BlenderTemplates - builds game templates from the three Blender models uploaded on 18 Nov 2026 (edit time only).
	  LS_Creatures_v1  119629886091854   squirrel poses, campfire, butterfly
	  LS_TreesClimb_v1 74649547382213    the four climbable trees
	  LS_TrainLobby_v1 118495945857547   the red train lobby
	The numbers (colours, materials, part centres, colliders, markers) come from WorldGen.BlenderData, generated from
	art/manifests/*.manifest.json. The importer drops colours and turns every model 180 degrees about Y, so each
	MeshPart is placed from its manifest centre and turned back (ROT); its colour and material are set from the data.

	Edit mode (Studio command bar or execute_luau), after the scripts are in Studio:
	  local BT = require(game.ServerStorage.WorldGen.BlenderTemplates:Clone())
	  BT.buildCreatures()  -> ReplicatedStorage.Assets.Creatures.{Squirrel, CookFire}, ReplicatedStorage.HazardAssets
	                          .{ButterflyWingL, ButterflyWingR}  (the swap tables: Shared.CreatureLooks.Mesh, HazardLook)
	  BT.buildTrees()      -> ServerStorage.WorldAssets.Map1.TreesClimb.{TC_Pine_A, TC_Pine_B, TC_Beech_A, TC_Beech_B}
	                          (the swap table: Shared.TreeClimb.SPECS.<asset>.mesh; then rebuild the planting)
	  BT.buildTrainLobby() -> the red train as workspace.Lobby; the old lobby (the Tor) moves to
	                          ServerStorage.LobbyVault_Tor. BT.restoreTor() puts the Tor back (and the train in the vault).
	Nothing here uploads, saves or publishes.
]]
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- (by path: this module is usually required as a clone, which has no parent)
local DATA = require(ServerStorage:WaitForChild("WorldGen"):WaitForChild("BlenderData"):Clone())

local BT = {}

local ROT = CFrame.Angles(0, math.pi, 0)

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function loadMeshes(category: string): ({ [string]: MeshPart }, Instance)
	local id = DATA[category].assetId
	local container = InsertService:LoadAsset(id)
	local meshes = {}
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("MeshPart") then
			meshes[d.Name] = d
		end
	end
	return meshes, container
end

-- one MeshPart from the upload, placed at `frame` * its manifest centre
local function meshPart(meshes: { [string]: MeshPart }, spec: any, frame: CFrame, parent: Instance, visualOnly: boolean?): MeshPart?
	local source = meshes[spec.n]
	if not source then
		warn("[BlenderTemplates] the upload has no MeshPart " .. tostring(spec.n))
		return nil
	end
	local p = source:Clone()
	for _, c in ipairs(p:GetChildren()) do
		c:Destroy()
	end
	p.CFrame = frame * CFrame.new(v3(spec.p)) * ROT
	p.Color = Color3.fromRGB(spec.c[1], spec.c[2], spec.c[3])
	local ok, mat = pcall(function()
		return (Enum.Material :: any)[spec.m]
	end)
	p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
	p.Transparency = spec.t or 0
	p.Anchored = true
	local collide = spec.col and not visualOnly
	p.CanCollide = collide
	p.CanQuery = collide or (spec.q and not visualOnly) or false
	p.CanTouch = false
	p.CastShadow = spec.sh ~= false and (spec.t or 0) < 1
	p.Massless = true
	p.Parent = parent
	return p
end

local function plainPart(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function folder(parent: Instance, name: string): Instance
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function weldAll(model: Instance, root: BasePart)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Creatures: squirrel (four poses), campfire, butterfly wings
----------------------------------------------------------------------------------------------------
function BT.buildCreatures(): string
	local meshes, container = loadMeshes("Creatures")
	local A = DATA.Creatures.assets
	local assets = folder(ReplicatedStorage, "Assets")
	local creatures = folder(assets, "Creatures")
	for _, name in ipairs({ "Squirrel", "CookFire" }) do
		local old = creatures:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	-- Squirrel: Root at the feet, nose -Z; one Model per pose, every part welded to Root
	local squirrel = Instance.new("Model")
	squirrel.Name = "Squirrel"
	local root = plainPart("Root", Vector3.new(0.2, 0.2, 0.2), CFrame.identity, squirrel)
	squirrel.PrimaryPart = root
	local poses = { Sit = "SquirrelSit", Run = "SquirrelRun", Climb = "SquirrelClimb", Still = "SquirrelStill" }
	local count = 0
	for pose, assetName in pairs(poses) do
		local m = Instance.new("Model")
		m.Name = "Pose_" .. pose
		m.Parent = squirrel
		-- SquirrelClimb was modelled standing up (nose +Y, back +Z): turned nose -Z, belly -Y like the others
		local frame = if pose == "Climb" then CFrame.Angles(math.rad(-90), 0, 0) else CFrame.identity
		for _, spec in ipairs(A[assetName].parts) do
			local p = meshPart(meshes, spec, frame, m, true)
			if p then
				p.Anchored = false
				p.CastShadow = false
				count += 1
			end
		end
	end
	weldAll(squirrel, root)
	squirrel.Parent = creatures

	-- CookFire: Root at the ground centre; the ember "Ember", the logs "Log" (CreatureLooks greys them when out).
	-- The Blender spit frame (CookFire_Wood) is left out: CreatureLooks adds its own spit.
	local fire = Instance.new("Model")
	fire.Name = "CookFire"
	local froot = plainPart("Root", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0.15, 0), fire)
	fire.PrimaryPart = froot
	for _, spec in ipairs(A.CookFire.parts) do
		if spec.n ~= "CookFire_Wood" then
			local p = meshPart(meshes, spec, CFrame.identity, fire, true)
			if p then
				if spec.n == "CookFire_Ember" then
					p.Name = "Ember"
				elseif spec.n == "CookFire_Log" then
					p.Name = "Log"
				end
				count += 1
			end
		end
	end
	fire.Parent = creatures

	-- Butterfly wings for the swarm (HazardLook.Templates): the blue face of each wing, 1.4x (the game's wings are
	-- bigger than the brief's so they read in play). Placed by HazardLook.WingL / WingR.
	local hazard = folder(ReplicatedStorage, "HazardAssets")
	for _, side in ipairs({ "L", "R" }) do
		local old = hazard:FindFirstChild("ButterflyWing" .. side)
		if old then
			old:Destroy()
		end
		for _, spec in ipairs(A.Butterfly.parts) do
			if spec.n == "Butterfly_Wing" .. side .. "_Blue" then
				local p = meshPart(meshes, spec, CFrame.identity, hazard, true)
				if p then
					p.Name = "ButterflyWing" .. side
					p.Size = p.Size * 1.4
					p.CFrame = CFrame.identity
					p.CastShadow = false
					count += 1
				end
			end
		end
	end
	container:Destroy()
	return string.format("BlenderTemplates.buildCreatures: %d mesh parts (Squirrel 4 poses, CookFire, ButterflyWingL/R)", count)
end

----------------------------------------------------------------------------------------------------
-- Trees: TC_* at scale 1, standing on their pivot (TreeClimb's contract)
----------------------------------------------------------------------------------------------------
function BT.buildTrees(): string
	local meshes, container = loadMeshes("TreesClimb")
	local A = DATA.TreesClimb.assets
	local map1 = ServerStorage:WaitForChild("WorldAssets"):WaitForChild("Map1")
	local holder = folder(map1, "TreesClimb")
	local built = {}
	for _, name in ipairs({ "TC_Pine_A", "TC_Pine_B", "TC_Beech_A", "TC_Beech_B" }) do
		local a = A[name]
		local old = holder:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local model = Instance.new("Model")
		model.Name = name
		local trunk: BasePart? = nil
		for _, spec in ipairs(a.parts) do
			if string.find(spec.n, "_Col", 1, true) then
				if string.find(spec.n, "Trunk", 1, true) then
					-- the climbable trunk: an invisible upright block (kinematic climbing reads its faces)
					local t = plainPart(spec.n, v3(spec.s), CFrame.new(v3(spec.p)), model)
					t.CanCollide = true
					t.CanQuery = true
					trunk = t
				end
			else
				meshPart(meshes, spec, CFrame.identity, model, true)
			end
		end
		-- the limbs as true oriented boxes (the mesh limbs' bounding boxes are wider than the limbs)
		for i, limb in ipairs(a.climb.limbs) do
			local b = math.rad(limb.bearing)
			local dir = Vector3.new(math.sin(b), 0, -math.cos(b))
			local reach = limb.length
			local centre = dir * (reach / 2) + Vector3.new(0, limb.y - limb.thick / 2, 0)
			local l = plainPart(name .. "_Limb" .. i, Vector3.new(limb.width, limb.thick, reach),
				CFrame.lookAt(centre, centre + dir), model)
			l.CanCollide = true
			l.CanQuery = true
		end
		-- seats and climbing steps (TreeClimb.adopt renames Seat_n to Perch<n> and tags them)
		if trunk then
			for attName, at in pairs(a.att or {}) do
				-- (the ClimbStep_n handhold marks are read by no code: left out, 3 to 4 fewer instances a tree)
				if string.sub(attName, 1, 9) == "ClimbStep" then
					continue
				end
				local pos, look, up = v3(at.p), v3(at.l), v3(at.u)
				local att = Instance.new("Attachment")
				att.Name = attName
				att.Parent = trunk
				att.WorldCFrame = CFrame.lookAt(pos, pos + look, up)
			end
		end
		-- no PrimaryPart: the pivot must stay at the trunk's foot (a PrimaryPart would move it to the trunk's centre,
		-- and the scatter plants every tree by its pivot)
		model.WorldPivot = CFrame.identity
		model.Parent = holder
		table.insert(built, name)
	end
	container:Destroy()
	return "BlenderTemplates.buildTrees: " .. table.concat(built, ", ") .. " under ServerStorage.WorldAssets.Map1.TreesClimb"
end

----------------------------------------------------------------------------------------------------
-- The red train lobby
----------------------------------------------------------------------------------------------------
BT.TRAIN_AT = CFrame.new(8800, 200, -30) -- the lounge car's floor centre; nose toward -Z; the Tor's island is 40 below
BT.LAMP_COLOUR = Color3.fromRGB(255, 196, 140)

local function yawCF(p: { number }, yawDeg: number?): CFrame
	return CFrame.new(v3(p)) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
end

local function colliders(list: { any }, frame: CFrame, parent: Instance)
	for _, c in ipairs(list or {}) do
		local p = plainPart(c.n, v3(c.s), frame * yawCF(c.p, c.yaw), parent)
		p.CanCollide = true
		p.CanQuery = true
	end
end

function BT.buildTrainLobby(): string
	local meshes, container = loadMeshes("TrainLobby")
	local A = DATA.TrainLobby.assets
	local M = DATA.TrainMarkers
	local base = BT.TRAIN_AT

	-- vault the Tor
	local old = workspace:FindFirstChild("Lobby")
	if old and old:GetAttribute("TrainLobby") ~= true then
		local vaultOld = ServerStorage:FindFirstChild("LobbyVault_Tor")
		if vaultOld then
			vaultOld:Destroy()
		end
		old.Name = "LobbyVault_Tor"
		old.Parent = ServerStorage
	elseif old then
		old:Destroy()
	end

	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	lobby:SetAttribute("TrainLobby", true)
	lobby.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local parts = 0

	-- the cars
	local carFrames = {}
	for _, carName in ipairs({ "TrainLobby_Nose", "TrainLobby_Lounge", "TrainLobby_Dining", "TrainLobby_Observation" }) do
		local a = A[carName]
		local frame = base * yawCF(a.placement.p, a.placement.yaw)
		carFrames[carName] = frame
		local car = Instance.new("Model")
		car.Name = (string.gsub(carName, "^TrainLobby_", ""))
		for _, spec in ipairs(a.parts) do
			local p = meshPart(meshes, spec, frame, car, true)
			if p then
				-- queryable (not solid): the camera's occlusion rays stop at the ceiling and walls instead of passing
				-- out of the car (seen in play: a third-person camera above the roof, looking down through it)
				p.CanQuery = spec.m ~= "Glass" and spec.m ~= "Neon"
				-- the camera's occlusion (Poppercam) only stops at opaque parts that collide: the ceiling slab does
				-- (out of reach above the heads, so it changes nothing for movement)
				if string.find(spec.n, "_Ceiling", 1, true) then
					p.CanCollide = true
					p.CollisionFidelity = Enum.CollisionFidelity.Box
				end
				parts += 1
			end
		end
		colliders(a.colliders, frame, car)
		car.WorldPivot = frame
		car.Parent = lobby
	end
	-- the gangways between the cars
	local gw = A.TrainLobby_Gangway
	for i, pl in ipairs(gw.placements) do
		local frame = base * yawCF(pl.p, pl.yaw)
		local m = Instance.new("Model")
		m.Name = "Gangway" .. i
		for _, spec in ipairs(gw.parts) do
			if meshPart(meshes, spec, frame, m, true) then
				parts += 1
			end
		end
		colliders(gw.colliders, frame, m)
		m.Parent = lobby
	end

	-- the scenery strip: three copies per layer per side, slid by TrainSceneryController on each client
	local sc = A.TrainLobby_Scenery
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery:SetAttribute("Length", sc.length)
	for _, side in ipairs({ 1, -1 }) do
		local sideFrame = base * (if side == 1 then CFrame.identity else CFrame.Angles(0, math.pi, 0))
		for _, spec in ipairs(sc.parts) do
			for k = -1, 1 do
				local p = meshPart(meshes, spec, sideFrame * CFrame.new(0, 0, k * sc.length), scenery, true)
				if p then
					p.CastShadow = false
					p.CanQuery = false
					p:SetAttribute("Speed", sc.speeds[spec.n] or 0)
					p:SetAttribute("Copy", k)
					p:SetAttribute("Side", side)
					parts += 1
				end
			end
		end
	end
	scenery.Parent = lobby

	-- markers: spawns, lamps, boards
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = lobby
	local lights = Instance.new("Folder")
	lights.Name = "Lamps"
	lights.Parent = lobby
	local landmarks = Instance.new("Folder")
	landmarks.Name = "Landmarks"
	landmarks.Parent = lobby
	local spawnCount = 0
	for name, mk in pairs(M) do
		local pos = base * v3(mk.p)
		local look = base:VectorToWorldSpace(v3(mk.l))
		local num = string.match(name, "^Spawn_(%d+)$")
		if num then
			local s = Instance.new("SpawnLocation")
			s.Name = "Spawn" .. tonumber(num)
			s.Size = Vector3.new(2, 0.2, 2)
			local flat = Vector3.new(look.X, 0, look.Z)
			s.CFrame = CFrame.lookAt(pos + Vector3.new(0, 0.1, 0), pos + Vector3.new(0, 0.1, 0) + (if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, 1)))
			s.Anchored = true
			s.Transparency = 1
			s.CanCollide = false
			s.CanQuery = false
			s.CanTouch = false
			s.Neutral = true
			s.Enabled = true
			s.Duration = 0
			s.Parent = spawns
			spawnCount += 1
		elseif string.find(name, "Lamp", 1, true) then
			local holder = plainPart(name, Vector3.new(0.4, 0.4, 0.4), CFrame.new(pos), lights)
			local light = Instance.new("PointLight")
			light.Color = if name == "NoseLamp" then Color3.fromRGB(255, 120, 80) else BT.LAMP_COLOUR
			light.Range = 16
			light.Brightness = 1.2
			light.Shadows = string.find(name, "Dining_Lamp", 1, true) ~= nil and (tonumber(string.match(name, "(%d+)$")) or 0) % 2 == 0
			light.Parent = holder
		end
	end
	-- the results board (LobbyBoardBuilder finds a "NoticeBoard" with a "NoticeFace" in Landmarks) and the rules board
	local function board(markerName: string, modelName: string, w: number, h: number): BasePart
		local mk = M[markerName]
		local pos = base * v3(mk.p)
		local look = base:VectorToWorldSpace(v3(mk.l))
		local m = Instance.new("Model")
		m.Name = modelName
		local face = plainPart("NoticeFace", Vector3.new(w, h, 0.05), CFrame.lookAt(pos + look * 0.12, pos + look * 2), m)
		face.Transparency = 1
		local back = plainPart("Frame", Vector3.new(w + 0.5, h + 0.5, 0.12), CFrame.lookAt(pos + look * 0.04, pos + look * 2), m)
		back.Transparency = 0
		back.Color = Color3.fromRGB(46, 32, 26)
		back.Material = Enum.Material.Wood
		m.Parent = landmarks
		return face
	end
	-- 1600 x 956 canvas: the face keeps that shape (6.75 high -> 11.3 wide)
	board("ResultsBoard", "NoticeBoard", 11.3, 6.75)
	local rules = board("HowToPlayBoard", "RulesBoard", 9.4, 5.6)
	local vault = ServerStorage:FindFirstChild("LobbyVault_Tor")
	local oldNotice = nil
	if vault then
		for _, d in ipairs(vault:GetDescendants()) do
			if d:IsA("SurfaceGui") and d.Name == "Notice" and d.Parent and not CollectionService:HasTag(d.Parent, "ResultsBoard") then
				oldNotice = d
				break
			end
		end
	end
	if oldNotice then
		local g = oldNotice:Clone()
		g.Enabled = true
		g.Face = Enum.NormalId.Front
		g.Parent = rules
	end

	container:Destroy()
	lobby.WorldPivot = base
	lobby.Parent = workspace
	return string.format("BlenderTemplates.buildTrainLobby: %d mesh parts, %d spawns; the Tor is in ServerStorage.LobbyVault_Tor%s",
		parts, spawnCount, if oldNotice then "; rules board copied" else "; NO rules board found to copy")
end

function BT.restoreTor(): string
	local vault = ServerStorage:FindFirstChild("LobbyVault_Tor")
	if not vault then
		return "no ServerStorage.LobbyVault_Tor"
	end
	local train = workspace:FindFirstChild("Lobby")
	if train then
		local tv = ServerStorage:FindFirstChild("LobbyVault_Train")
		if tv then
			tv:Destroy()
		end
		train.Name = "LobbyVault_Train"
		train.Parent = ServerStorage
	end
	vault.Name = "Lobby"
	vault.Parent = workspace
	return "the Tor is back as workspace.Lobby; the train is in ServerStorage.LobbyVault_Train"
end

return BT
