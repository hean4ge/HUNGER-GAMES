--[[
	TrainingCentreBuilder - builds the Blender Training Centre set (edit time only): platform B, the hall and its five
	stations, the prep floor, the launch doors and corridor, the station chests and the training dummies.
	Design: docs/design/TrainingAndLoadup.md sections 3, 5 and 6. Art: art/blender/training_centre.py (seed 1119),
	export BlenderExports/TrainingCentre/, manifest art/manifests/TrainingCentre.manifest.json. The numbers come from
	WorldGen.TrainingCentreData (generated: python art/blender/training_centre_lua.py).

	Two sources for the visuals, same layout, same colours and materials, same colliders and markers:
	  "mesh"  - the uploaded GLB (TrainingCentreData.assetId, or a raw insert at ServerStorage.MeshImports.
	            LS_TrainingCentre_v1). Each MeshPart is placed at hall * placement * centre, turned back 180 degrees
	            about Y (the importer's turn), coloured from the data (the importer drops colours).
	  "parts" - one Part per modelled shape (boxes, fitted boxes, Cylinder parts) from the generator's primitives.
	            Used when there is no upload yet; the layout is identical, the shapes are simpler.
	opts.source = "auto" (default: mesh when it loads, else parts) | "mesh" | "parts".

	Edit mode (command bar or execute_luau):
	  local TC = require(game.ServerStorage.WorldGen.TrainingCentreBuilder:Clone())
	  print(TC.build())                      -> workspace.TrainingCentre at place (8800, 200, 3000)
	  print(TC.remove())                     -> removes it
	What it makes inside workspace.TrainingCentre (Model, attribute BlenderSet = true, Source = "mesh" | "parts"):
	  <Asset>/<placement>  visuals (never collide, never queried) + invisible *_Col Parts (CanCollide, CanQuery)
	                       tags: Climbable, TrainingTarget (Station, Lane, Distance), LaunchDoorLeaf, RedRoomSeam
	  LaunchDoors          LeafL / LeafR models (visuals + collider), attribute OpenOffset; RedLamp part
	  Chests/Chest_<Station>  chest visuals + Base (collider) with Attachments LidHinge, Prompt, LootPoint; Lid tagged
	  Dummies/Dummy_<Role>    burlap dummy, one part per R15 limb named by its R15 name (+ Stand)
	  Mats                 invisible CanTouch pads Mat_<Kit> (attributes Kit, Station)
	  Markers              invisible 0.2 Parts at every station / drill / screen / target marker, attributes copied
	  PlatformSpawns       Spawn_01..48 on platform B (plain Parts, NOT SpawnLocations)
	  Lamps                PointLights: the hall's warm grid (HallLight_r_c, below), platform banks, corridor
	  RedRoom              the walk-in red room behind the corridor (TrainingCentreData.redRoom, the uploaded
	                       LaunchRedRoom_WalkIn.glb): meshes with their palette SurfaceAppearance, box colliders, an
	                       invisible Disc (TrainRideService's red-room disc) and a few lights. Without it the corridor
	                       keeps its end cap and TrainRideService builds its Part stand-in room.
	In mesh mode the prep floor's Use and DarkSteel roles (the obstacle tops and posts: 9 shapes) are still Parts, so
	TC.prepare can lift the slide bar with its collider (one merged mesh cannot move one bar).

	The hall's light (19 Nov, wave 15): an even, soft, warm sports-hall light from 18 PointLights in a 6 x 3 grid under
	the coffers (Range 60, no shadows except the two over the floor), not from the 26 scattered downlights: the blade
	ring, the corners and the walls were dim. The 77 Neon downlight discs stay the visible source (warm white). Lights
	without shadows are cheap on phones (voxel lighting at low quality levels).
	Nothing here saves or publishes. It takes the shared-Studio lock (Workspace attribute QA_Lock).
]]
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local DATA = require(ServerStorage:WaitForChild("WorldGen"):WaitForChild("TrainingCentreData"):Clone())

local TC = {}

TC.HALL_AT = CFrame.new(DATA.hallOrigin[1], DATA.hallOrigin[2], DATA.hallOrigin[3])
TC.MODEL_NAME = "TrainingCentre"
TC.LOCK_LABEL = "training-centre"
-- the set's build version: a live server rebuilds a saved set older than this (or one made of Parts when the meshes load)
TC.VERSION = 2
local ROT = CFrame.Angles(0, math.pi, 0)
local PLAT_LAMP = Color3.fromRGB(255, 220, 180)
local RED_LAMP = Color3.fromRGB(255, 70, 56)
-- the hall's light: a warm grid under the coffers (hall coordinates), shadows only over the floor
local HALL_LIGHT = {
	colour = Color3.fromRGB(255, 228, 196),
	xs = { -90, -54, -18, 18, 54, 90 },
	zs = { -50, 0, 50 },
	y = 30,
	range = 60,
	brightness = 0.95, -- 1.35 washed the chequer out to white (Studio, 19 Nov)
	shadows = { ["3_2"] = true, ["4_2"] = true },
}
-- look overrides on top of the manifest's colours: the downlight discs read warm white, like the light they give
local LOOK: { [string]: Color3 } = {
	TC_HallShell_Downlight = Color3.fromRGB(255, 240, 220),
}
-- roles still built from Parts in mesh mode (asset -> role): TC.prepare moves the slide bar on its own
local MESH_AS_PARTS: { [string]: { [string]: boolean } } = {
	TC_PrepFloor = { Use = true, DarkSteel = true },
}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function yawCF(p: { number }, yawDeg: number?): CFrame
	return CFrame.new(v3(p)) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
end

local function material(name: string): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and m then m else Enum.Material.SmoothPlastic
end

local function setAttrs(inst: Instance, at: { [string]: any }?)
	for k, v in pairs(at or {}) do
		local key = string.upper(string.sub(k, 1, 1)) .. string.sub(k, 2)
		if typeof(v) == "table" then
			if #v == 3 and typeof(v[1]) == "number" then
				inst:SetAttribute(key, v3(v))
			elseif #v == 2 and typeof(v[1]) == "number" then
				inst:SetAttribute(key, Vector2.new(v[1], v[2]))
			else
				local parts = {}
				for _, x in ipairs(v) do
					table.insert(parts, tostring(x))
				end
				inst:SetAttribute(key, table.concat(parts, ","))
			end
		else
			inst:SetAttribute(key, v)
		end
	end
end

local function plainPart(name: string, size: Vector3, cf: CFrame, parent: Instance?): Part
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

local function styleVisual(p: BasePart, spec: any)
	p.Color = LOOK[spec.n] or Color3.fromRGB(spec.c[1], spec.c[2], spec.c[3])
	p.Material = material(spec.m)
	p.Transparency = spec.t or 0
	p.CastShadow = spec.sh ~= false
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	for _, tag in ipairs(spec.tags or {}) do
		if string.sub(tag, 1, 4) == "R15:" then
			p:SetAttribute("R15", string.sub(tag, 5))
		else
			CollectionService:AddTag(p, tag)
		end
	end
end

-- the Part build of one role: one Part per primitive
local function primParts(rows: { any }, frame: CFrame, spec: any, parent: Instance): number
	local n = 0
	for i, r in ipairs(rows) do
		local p = Instance.new("Part")
		p.Name = spec.n
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		local kind = r[1]
		local pos = Vector3.new(r[2], r[3], r[4])
		if kind == "A" then
			p.Size = Vector3.new(math.max(r[5], 0.05), math.max(r[6], 0.05), math.max(r[7], 0.05))
			p.CFrame = frame * CFrame.new(pos)
		elseif kind == "B" then
			local rx = Vector3.new(r[8], r[9], r[10])
			local uy = Vector3.new(r[11], r[12], r[13])
			p.Size = Vector3.new(math.max(r[5], 0.05), math.max(r[6], 0.05), math.max(r[7], 0.05))
			p.CFrame = frame * CFrame.fromMatrix(pos, rx, uy)
		else -- "C": Cylinder part, axis = the part's X
			local ax = Vector3.new(r[7], r[8], r[9]).Unit
			local ref = if math.abs(ax.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
			local up = (ref - ax * ref:Dot(ax)).Unit
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(math.max(r[5], 0.05), math.max(r[6], 0.05), math.max(r[6], 0.05))
			p.CFrame = frame * CFrame.fromMatrix(pos, ax, up)
		end
		styleVisual(p, spec)
		p.Parent = parent
		n += 1
		if i % 400 == 0 then
			task.wait()
		end
	end
	return n
end

local function loadMeshes(): ({ [string]: MeshPart }?, Instance?, string)
	local imports = ServerStorage:FindFirstChild("MeshImports")
	local raw = imports and imports:FindFirstChild("LS_TrainingCentre_v1")
	local container: Instance? = nil
	local how = ""
	if raw then
		container = raw
		how = "MeshImports.LS_TrainingCentre_v1"
	elseif DATA.assetId then
		local ok, loaded = pcall(function()
			return InsertService:LoadAsset(DATA.assetId)
		end)
		if not ok then
			return nil, nil, "LoadAsset(" .. tostring(DATA.assetId) .. ") failed: " .. tostring(loaded)
		end
		container = loaded
		how = "LoadAsset(" .. tostring(DATA.assetId) .. ")"
	else
		return nil, nil, "no upload recorded (TrainingCentreData.assetId is nil)"
	end
	local meshes = {}
	for _, d in ipairs((container :: Instance):GetDescendants()) do
		if d:IsA("MeshPart") then
			meshes[d.Name] = d
		end
	end
	return meshes, if raw then nil else container, how
end

local function takeLock(label: string): (boolean, string)
	local now = os.time()
	local lock = workspace:GetAttribute("QA_Lock")
	if typeof(lock) == "string" then
		local who, t = string.match(lock, "^(.-)|(%d+)$")
		if who ~= label and t and now - tonumber(t) < 540 then
			return false, "LOCKED by " .. lock .. " (now " .. now .. "). Nothing was built."
		end
	end
	workspace:SetAttribute("QA_Lock", label .. "|" .. now)
	return true, ""
end

local function releaseLock(label: string)
	local lock = workspace:GetAttribute("QA_Lock")
	if typeof(lock) == "string" and string.sub(lock, 1, #label + 1) == label .. "|" then
		workspace:SetAttribute("QA_Lock", nil)
	end
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

local function markerPart(name: string, frame: CFrame, mk: any, parent: Instance): Part
	local pos = frame * v3(mk.p)
	local look = frame:VectorToWorldSpace(v3(mk.l))
	local up = frame:VectorToWorldSpace(v3(mk.u))
	if math.abs(look:Dot(up)) > 0.99 then
		up = if math.abs(look.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	end
	local p = plainPart(name, Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(pos, pos + look, up), parent)
	setAttrs(p, mk.at)
	return p
end

-- The hall's light: HALL_LIGHT's grid of warm PointLights under the coffers, into `parent` (the Lamps folder).
local function hallLights(hall: CFrame, parent: Instance): number
	local n = 0
	for c, x in ipairs(HALL_LIGHT.xs) do
		for r, z in ipairs(HALL_LIGHT.zs) do
			local key = c .. "_" .. r
			local holder = plainPart("HallLight_" .. key, Vector3.new(0.2, 0.2, 0.2), hall * CFrame.new(x, HALL_LIGHT.y, z), parent)
			local light = Instance.new("PointLight")
			light.Color = HALL_LIGHT.colour
			light.Range = HALL_LIGHT.range
			light.Brightness = HALL_LIGHT.brightness
			light.Shadows = HALL_LIGHT.shadows[key] == true
			light.Parent = holder
			n += 1
		end
	end
	return n
end

-- The walk-in red room (design page 5.2): the room stands 10 lower than the hall floor, turned to face the hall, so the
-- launch corridor (floor 0, ending at hall z -87) runs through the doorway cut in its back wall onto its upper walkway
-- (deck top 10 in the room). Room frame = Launch.manifest.json's (Roblox axes, floor centre 0, walkway on -z).
TC.RED_ROOM_AT = CFrame.new(0, -10, -100) * CFrame.Angles(0, math.pi, 0) -- in hall space
-- box colliders in the room frame: name, size, centre (the visual meshes never collide)
local RED_COLLIDERS: { { any } } = {
	{ "Floor", { 30, 1, 24 }, { 0, -0.5, 0 } },
	{ "WallFront", { 32, 22.8, 1 }, { 0, 10.8, 12.5 } },
	{ "WallW", { 1, 22.8, 26 }, { -15.5, 10.8, 0 } },
	{ "WallE", { 1, 22.8, 26 }, { 15.5, 10.8, 0 } },
	{ "WallBackW", { 13, 22.8, 1 }, { -9.5, 10.8, -12.5 } },
	{ "WallBackE", { 13, 22.8, 1 }, { 9.5, 10.8, -12.5 } },
	{ "WallBackLow", { 6, 10.6, 1 }, { 0, 4.7, -12.5 } }, -- its top is the doorway's sill (room y 10 = hall floor)
	{ "WallBackTop", { 6, 3.6, 1 }, { 0, 20.4, -12.5 } },
	{ "Roof", { 32, 1, 26 }, { 0, 22.7, 0 } },
	{ "Walkway", { 26.9, 0.5, 3.6 }, { -1.55, 9.75, -10.2 } },
	{ "Landing", { 3.1, 0.5, 3.6 }, { 13.45, 9.75, -10.2 } },
	{ "WalkwayRail", { 26.9, 3.8, 0.4 }, { -1.55, 11.9, -8.55 } },
	{ "LiftRailW", { 0.4, 3.8, 9 }, { -7.25, 1.9, -0.1 } },
	{ "LiftRailE", { 0.4, 3.8, 9 }, { 7.25, 1.9, -0.1 } },
	{ "LiftRailBack", { 14.5, 3.8, 0.4 }, { 0, 1.9, -4.6 } },
	{ "RailBack", { 20, 3.8, 0.4 }, { 0, 1.9, -9.95 } },
	{ "RailFront", { 20, 3.8, 0.4 }, { 0, 1.9, 9.95 } },
}

local function buildRedRoom(hall: CFrame, root: Instance, counts: { [string]: number }): string
	local rr = DATA.redRoom
	if not (rr and rr.assetId) then
		return "no red room upload recorded"
	end
	local ok, loaded = pcall(function()
		return InsertService:LoadAsset(rr.assetId)
	end)
	if not ok then
		return "red room LoadAsset(" .. tostring(rr.assetId) .. ") failed: " .. tostring(loaded)
	end
	local container = loaded :: Instance
	local imported: Model? = nil
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Model") and d.Name == rr.name then
			imported = d
		end
	end
	if not imported then
		container:Destroy()
		return "red room upload has no model " .. rr.name
	end
	local roomCF = hall * TC.RED_ROOM_AT
	local room = Instance.new("Model")
	room.Name = "RedRoom"
	room:SetAttribute("AssetId", rr.assetId)
	-- the importer turns the model 180 degrees about Y: undo it about the import's bounding-box centre
	local importCentre = (imported :: Model):GetBoundingBox().Position
	local back = CFrame.new(v3(rr.centre)) * ROT * CFrame.new(-importCentre)
	local made, missing = 0, 0
	for name, spec in pairs(rr.parts) do
		local src = (imported :: Model):FindFirstChild(name, true)
		if src and src:IsA("MeshPart") then
			local p = src:Clone()
			for _, c in ipairs(p:GetChildren()) do
				if not c:IsA("SurfaceAppearance") then -- keep the palette textures
					c:Destroy()
				end
			end
			p.CFrame = roomCF * back * src.CFrame
			p.Color = Color3.fromRGB(spec.c[1], spec.c[2], spec.c[3])
			p.Material = material(spec.m)
			p.CastShadow = spec.sh ~= false
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Parent = room
			made += 1
		else
			missing += 1
			warn("[TrainingCentreBuilder] the red room upload has no MeshPart " .. name)
		end
	end
	container:Destroy()
	for _, c in ipairs(RED_COLLIDERS) do
		local p = plainPart("RedRoom_" .. c[1] .. "_Col", v3(c[2]), roomCF * CFrame.new(v3(c[3])), room)
		p.CanCollide = true
		p.CanQuery = true
		counts.colliders += 1
	end
	-- the stair: one ramp under the 13 steps (room x 12..15, from z 7 at the floor up to z -8.4 at the walkway)
	local rise, run = 10, 15.4
	local tilt = math.atan2(rise, run)
	local len = math.sqrt(rise * rise + run * run)
	local rampCF = CFrame.new(13.5, rise / 2, (7 - 8.4) / 2) * CFrame.Angles(tilt, 0, 0)
	local ramp = plainPart("RedRoom_Stair_Col", Vector3.new(3, 0.6, len), roomCF * rampCF * CFrame.new(0, -0.3, 0), room)
	ramp.CanCollide, ramp.CanQuery = true, true
	-- the open side's rail, stopped 2.5 short of the foot so you can step off the last stair and turn
	local rail = plainPart("RedRoom_StairRail_Col", Vector3.new(0.4, 3.8, len - 2.5), roomCF * CFrame.new(11.85, 0, 0)
		* CFrame.new(0, rise / 2 + 1.9, (7 - 8.4) / 2) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 0, -1.25), room)
	rail.CanCollide, rail.CanQuery = true, true
	counts.colliders += 2
	-- the disc TrainRideService looks for (stand on it: Ready); the rose lift mesh is its look
	local disc = plainPart("Disc", Vector3.new(7, 0.3, 7), roomCF * CFrame.new(0, 0.15, 0), room)
	disc:SetAttribute("RedRoomDisc", true)
	-- a few real lights: the cool key down the hex onto the lift, the walkway's spot, the two lamps on the back wall
	-- and the red glow in the two floor openings (Launch.manifest.json lighting, cut to six lights)
	local at = rr.attachments
	local function lightAt(name: string, kind: string, pos: Vector3, look: Vector3, colour: Color3, range: number,
		brightness: number, angle: number?)
		local up = if math.abs(look.Unit.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
		local h = plainPart("RedRoom_" .. name, Vector3.new(0.2, 0.2, 0.2), roomCF * CFrame.lookAt(pos, pos + look, up), room)
		local l = Instance.new(kind) :: any
		l.Color, l.Range, l.Brightness, l.Shadows = colour, range, brightness, false
		if angle then
			l.Angle = angle
			l.Face = Enum.NormalId.Front
		end
		l.Parent = h
		counts.lights += 1
	end
	lightAt("KeyLight", "SpotLight", Vector3.new(0, 19, 0), Vector3.new(0, -1, 0),Color3.fromRGB(220, 234, 255), 28, 3.2, 44)
	if at.WalkwaySpot then
		lightAt("WalkwaySpot", "SpotLight", v3(at.WalkwaySpot.p), v3(at.WalkwaySpot.l), Color3.fromRGB(170, 200, 255), 16, 1.6, 70)
	end
	for _, k in ipairs({ "Lamp_7", "Lamp_8" }) do
		if at[k] then
			lightAt(k, "SpotLight", v3(at[k].p), v3(at[k].l) + Vector3.new(0, -0.18, 0), Color3.fromRGB(236, 240, 255), 20, 1.3, 70)
		end
	end
	for _, k in ipairs({ "OpeningGlow_1", "OpeningGlow_2" }) do
		if at[k] then
			lightAt(k, "PointLight", v3(at[k].p) + Vector3.new(0, 1, 0), Vector3.new(0, 0, -1), Color3.fromRGB(255, 92, 86), 9, 1.6)
		end
	end
	room.WorldPivot = roomCF
	room.Parent = root
	return string.format("red room %d meshes%s", made, if missing > 0 then string.format(", %d MISSING", missing) else "")
end

function TC.build(opts: { [string]: any }?): string
	local o = opts or {}
	local label = o.label or TC.LOCK_LABEL
	if not o.noLock then
		local okLock, why = takeLock(label)
		if not okLock then
			return why
		end
	end
	local ok, result = pcall(function()
		local want = o.source or "auto"
		local meshes, container, how = nil, nil, ""
		if want ~= "parts" then
			meshes, container, how = loadMeshes()
			if not meshes and want == "mesh" then
				error("source mesh: " .. how)
			end
		end
		local source = if meshes then "mesh" else "parts"

		-- never clobber another model of the same name that this builder did not make
		local name = o.name or TC.MODEL_NAME
		local old = workspace:FindFirstChild(name)
		local note = ""
		if old and old:GetAttribute("BlenderSet") ~= true then
			name = name .. "_Blender"
			note = "; workspace." .. TC.MODEL_NAME .. " exists and is not ours, built as " .. name
			old = workspace:FindFirstChild(name)
		end
		if old then
			old:Destroy()
		end

		local root = Instance.new("Model")
		root.Name = name
		root:SetAttribute("BlenderSet", true)
		root:SetAttribute("Source", source)
		root:SetAttribute("Generator", "art/blender/training_centre.py")
		root.ModelStreamingMode = Enum.ModelStreamingMode.Default
		local hall = TC.HALL_AT
		local counts = { visuals = 0, colliders = 0, markers = 0, lights = 0, missing = 0 }

		local fMarkers = Instance.new("Folder")
		fMarkers.Name = "Markers"
		local fSpawns = Instance.new("Folder")
		fSpawns.Name = "PlatformSpawns"
		local fLamps = Instance.new("Folder")
		fLamps.Name = "Lamps"
		local fMats = Instance.new("Folder")
		fMats.Name = "Mats"

		for _, assetName in ipairs(DATA.order) do
			local a = DATA.assets[assetName]
			local group: Instance = root
			if assetName == "TC_Chest" then
				group = folder(root, "Chests")
			elseif assetName == "TC_Dummy" then
				group = folder(root, "Dummies")
			end
			for _, pl in ipairs(a.placements) do
				local frame = hall * yawCF(pl.p, pl.yaw)
				local m = Instance.new("Model")
				m.Name = if assetName == "TC_Chest" or assetName == "TC_Dummy" then pl.name else assetName
				if pl.station then
					m:SetAttribute("Station", pl.station)
				end
				if pl.role then
					m:SetAttribute("Role", pl.role)
				end
				-- the launch door leaves move: group their pieces
				local leaves = {}
				if assetName == "TC_LaunchDoors" then
					for _, side in ipairs({ "L", "R" }) do
						local lm = Instance.new("Model")
						lm.Name = "Leaf" .. side
						local mk = a.attachments["DoorLeaf" .. side]
						lm:SetAttribute("OpenOffset", v3(mk.at.openOffset))
						lm:SetAttribute("Seconds", mk.at.seconds)
						lm.Parent = m
						leaves[side] = lm
					end
				end
				local function parentFor(role: string): Instance
					local side = string.match(role, "^Door%a+([LR])$")
					if side and leaves[side] then
						return leaves[side]
					end
					return m
				end
				-- visuals
				for role, spec in pairs(a.roles) do
					local parent = parentFor(role)
					local asParts = MESH_AS_PARTS[assetName] ~= nil and MESH_AS_PARTS[assetName][role] == true
					if source == "mesh" and not asParts then
						local src = (meshes :: any)[spec.n]
						if src then
							local p = src:Clone()
							for _, c in ipairs(p:GetChildren()) do
								c:Destroy()
							end
							p.CFrame = frame * CFrame.new(v3(spec.p)) * ROT
							styleVisual(p, spec)
							if assetName == "TC_Dummy" and string.match(spec.n, "^TC_Dummy_(.+)$") then
								p.Name = string.match(spec.n, "^TC_Dummy_(.+)$")
							end
							p.Parent = parent
							counts.visuals += 1
						else
							counts.missing += 1
							warn("[TrainingCentreBuilder] the upload has no MeshPart " .. spec.n)
						end
					else
						local rows = a.prims[role]
						if rows then
							local holder: Instance = parent
							if assetName == "TC_Dummy" then
								local r15 = string.match(spec.n, "^TC_Dummy_(.+)$")
								spec = table.clone(spec)
								spec.n = r15 or spec.n
							end
							counts.visuals += primParts(rows, frame, spec, holder)
						end
					end
				end
				-- colliders
				for _, c in ipairs(a.colliders) do
					local side = string.match(c.n, "_Door([LR])_Col$")
					local parent = if side and leaves[side] then leaves[side] else m
					local p = plainPart(c.n, v3(c.s), frame * yawCF(c.p, c.yaw), parent)
					p.CanCollide = true
					p.CanQuery = true
					for _, tag in ipairs(c.tags or {}) do
						CollectionService:AddTag(p, tag)
						if tag == "TrainingTarget" then
							p.CanTouch = true
						end
					end
					setAttrs(p, c.at)
					counts.colliders += 1
				end
				-- chest attachments go on the chest's Base collider
				if assetName == "TC_Chest" then
					local base = m:FindFirstChild("TC_Chest_Base_Col") :: BasePart
					base.Name = "Base"
					for an, mk in pairs(a.attachments) do
						local att = Instance.new("Attachment")
						att.Name = an
						local pos = frame * v3(mk.p)
						local look = frame:VectorToWorldSpace(v3(mk.l))
						att.WorldCFrame = CFrame.lookAt(pos, pos + look, frame:VectorToWorldSpace(v3(mk.u)))
						att.Parent = base
					end
					m.PrimaryPart = base
				elseif assetName == "TC_Dummy" then
					local mk = a.attachments.Root
					markerPart("RootMarker", frame, mk, m)
				else
					-- zone markers
					for mn, mk in pairs(a.attachments) do
						if string.match(mn, "^Spawn_%d+$") then
							markerPart(mn, frame, mk, fSpawns)
						elseif string.match(mn, "^Lamp_") or string.match(mn, "^PlatLamp_") or mn == "RedLamp" then
							local at = mk.at or {}
							local isHall = string.match(mn, "^Lamp_%d+_%d+$") ~= nil
							local isPlat = string.match(mn, "^PlatLamp_") ~= nil
							-- (the hall's downlight markers stay markers: the hall is lit by HALL_LIGHT's grid below)
							if not isHall then
								local holder = markerPart(mn, frame, mk, fLamps)
								local light = Instance.new("PointLight")
								if isPlat then
									light.Color, light.Range, light.Brightness = PLAT_LAMP, 22, 1.2
									holder:SetAttribute("Bank", at.bank)
								else -- RedLamp and the corridor's red lamps
									light.Color, light.Range, light.Brightness = RED_LAMP, if mn == "RedLamp" then 16 else 12, 1
								end
								light.Shadows = false
								light.Parent = holder
								counts.lights += 1
							end
						elseif string.match(mn, "^Mat_") then
							local pos = frame * v3(mk.p)
							local s = mk.at.size
							local pad = plainPart(mn, Vector3.new(s[1], 1, s[3]), CFrame.new(pos + Vector3.new(0, 0.5, 0)), fMats)
							pad.CanTouch = true
							setAttrs(pad, { kit = mk.at.kit, station = mk.at.station })
						elseif string.match(mn, "^Chest_") or string.match(mn, "^Dummy_") or mn == "BandageDummy"
							or string.match(mn, "^DoorLeaf") then
							-- placed as their own models
						elseif mn == "BigScreen" or mn == "KitBoard" then
							local pos = frame * v3(mk.p)
							local look = frame:VectorToWorldSpace(v3(mk.l))
							local s = mk.at.size
							local face = plainPart(mn, Vector3.new(s[1], s[2], 0.05), CFrame.lookAt(pos + look * 0.03, pos + look * 2), fMarkers)
							face:SetAttribute("Face", "Front")
						else
							markerPart(mn, frame, mk, fMarkers)
						end
						counts.markers += 1
					end
				end
				if assetName == "TC_LaunchDoors" then
					m.Name = "LaunchDoors"
					local red = m:FindFirstChild("TC_LaunchDoors_RedLamp")
					if red then
						red:SetAttribute("ColourOn", Color3.fromRGB(255, 60, 48))
						red:SetAttribute("ColourOff", Color3.fromRGB(80, 24, 22))
					end
				elseif assetName == "TC_Platform" then
					for _, d in ipairs(m:GetChildren()) do
						local bank = string.match(d.Name, "^TC_Platform_PlatLamp(%d)$")
						if bank then
							d:SetAttribute("Bank", tonumber(bank))
						end
					end
				end
				m.WorldPivot = frame
				m.Parent = group
				task.wait()
			end
		end
		counts.lights += hallLights(hall, fLamps)
		fMarkers.Parent = root
		fSpawns.Parent = root
		fLamps.Parent = root
		fMats.Parent = root
		if container then
			container:Destroy()
		end
		-- the walk-in red room behind the corridor; with it the corridor's black end cap goes
		local roomNote = "red room: none"
		if o.redRoom ~= false then
			roomNote = buildRedRoom(hall, root, counts)
			local roomModel = root:FindFirstChild("RedRoom")
			if roomModel then
				-- the plan's disc marker (hall z -99 at floor 0) is not the disc: TrainRideService takes the first part
				-- named RedRoomDisc / Disc outside Markers... and skipped this one, then built its stand-in room
				local plan = fMarkers:FindFirstChild("RedRoomDisc")
				local disc = roomModel:FindFirstChild("Disc")
				if plan and plan:IsA("BasePart") then
					plan.Name = "RedRoomDiscPlan"
					if disc and disc:IsA("BasePart") then
						plan.CFrame = disc.CFrame
					end
				end
				local doors = root:FindFirstChild("LaunchDoors")
				for _, d in ipairs(doors and doors:GetDescendants() or {}) do
					if d.Name == "TC_LaunchDoors_EndCap" or d.Name == "TC_LaunchDoors_EndCap_Col" then
						d:Destroy()
					end
				end
			end
		end
		note ..= "; " .. roomNote
		root:SetAttribute("BuildVersion", TC.VERSION)
		root.WorldPivot = hall
		root.Parent = workspace
		return string.format(
			"TrainingCentreBuilder.build: source %s%s; %d visual parts, %d colliders, %d markers, %d lights%s%s",
			source,
			if how ~= "" then " (" .. how .. ")" else "",
			counts.visuals,
			counts.colliders,
			counts.markers,
			counts.lights,
			if counts.missing > 0 then string.format(", %d MISSING meshes", counts.missing) else "",
			note
		)
	end)
	if not o.noLock then
		releaseLock(label)
	end
	if not ok then
		return "TrainingCentreBuilder.build FAILED: " .. tostring(result)
	end
	return result
end

-- Runtime ---------------------------------------------------------------------------------------------------------
-- The set is not saved in the place yet, so a live server builds it at start (TC.ensure, from TrainingService and
-- TrainRideService, whichever asks first; the other waits). TC.prepare then makes the set work with the round code:
--   LaunchDoors   each leaf's collider becomes a direct child BasePart with Slide (studs) and SlideAxis ("X" | "Z"), its
--                 visuals parented under it (TrainRideController slides them for players who hold a place); the red
--                 lamp is named DoorLamp
--   EndCap        removed (the corridor opens onto the red room TrainRideService places behind it)
--   SlideBar      lifted 1.6 (underside 4.6: a crouch or a slide passes, standing does not; tuned in play)
--   BigScreen     a SurfaceGui line, attribute TrainScreen (the call's countdown)
--   PlatLamp_*    their lights start off; they come on bank by bank as train B stops
-- Idempotent (attribute RuntimeReady).
function TC.prepare(root: Instance): string
	if root:GetAttribute("RuntimeReady") == true then
		return "already prepared"
	end
	local hall = root:IsA("Model") and root:GetPivot() or TC.HALL_AT
	local notes = {}
	-- the launch doors
	local doors = root:FindFirstChild("LaunchDoors", true)
	if doors and doors:IsA("Model") then
		for _, side in ipairs({ "L", "R" }) do
			local leaf = doors:FindFirstChild("Leaf" .. side)
			if leaf then
				local col: BasePart? = nil
				for _, d in ipairs(leaf:GetChildren()) do
					if d:IsA("BasePart") and string.match(d.Name, "_Door" .. side .. "_Col$") then
						col = d
					end
				end
				if col then
					local off = leaf:GetAttribute("OpenOffset")
					local o = if typeof(off) == "Vector3" then col.CFrame:VectorToObjectSpace(off) else Vector3.new(if side == "L" then -4.2 else 4.2, 0, 0)
					local axis = if math.abs(o.X) >= math.abs(o.Z) then "X" else "Z"
					col.Name = "Leaf" .. side
					col:SetAttribute("Slide", if axis == "X" then o.X else o.Z)
					col:SetAttribute("SlideAxis", axis)
					col.Parent = doors
					for _, d in ipairs(leaf:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Parent = col
						end
					end
					leaf:Destroy()
				end
			end
		end
		local red = doors:FindFirstChild("TC_LaunchDoors_RedLamp")
		if red then
			red.Name = "DoorLamp"
		end
		for _, d in ipairs(doors:GetChildren()) do
			if d.Name == "TC_LaunchDoors_EndCap" or d.Name == "TC_LaunchDoors_EndCap_Col" then
				d:Destroy()
			end
		end
		table.insert(notes, "doors")
	end
	-- the slide bar: lift 1.6
	local prep = root:FindFirstChild("TC_PrepFloor")
	if prep then
		local n = 0
		for _, d in ipairs(prep:GetDescendants()) do
			if d:IsA("BasePart") then
				local p = hall:PointToObjectSpace(d.Position)
				if math.abs(p.X) <= 4.2 and math.abs(p.Z + 16) <= 0.7 and p.Y > 1 then
					if d.Size.Y > 4 and d.Size.Y < 5 then -- a post: taller, still standing on the floor
						d.Size = Vector3.new(d.Size.X, d.Size.Y + 1.6, d.Size.Z)
						d.CFrame = d.CFrame + Vector3.new(0, 0.8, 0)
					else
						d.CFrame = d.CFrame + Vector3.new(0, 1.6, 0)
					end
					n += 1
				end
			end
		end
		table.insert(notes, "slide bar " .. n)
	end
	-- the big screen
	local markers = root:FindFirstChild("Markers")
	local screen = markers and markers:FindFirstChild("BigScreen")
	if screen and screen:IsA("BasePart") then
		screen:SetAttribute("TrainScreen", true)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Screen"
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(1400, 450)
		gui.LightInfluence = 0
		gui.Brightness = 1.4
		local label = Instance.new("TextLabel")
		label.Name = "Line"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "THE TRAINING CENTRE"
		label.TextColor3 = Color3.fromRGB(226, 232, 230)
		label.TextScaled = true
		label.Font = Enum.Font.GothamMedium
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0.08, 0), UDim.new(0.08, 0)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.3, 0), UDim.new(0.3, 0)
		pad.Parent = label
		label.Parent = gui
		gui.Parent = screen
		table.insert(notes, "screen")
	end
	-- the platform lamps start dark
	local lamps = root:FindFirstChild("Lamps")
	if lamps then
		for _, d in ipairs(lamps:GetChildren()) do
			if string.match(d.Name, "^PlatLamp_") then
				local light = d:FindFirstChildWhichIsA("Light")
				if light then
					light.Enabled = false
				end
			end
		end
	end
	root:SetAttribute("RuntimeReady", true)
	return "prepared: " .. table.concat(notes, ", ")
end

local ensuring = false
-- The set in the workspace, built if missing (runtime: no lock) and prepared. Safe to call from several threads.
-- A saved set older than TC.VERSION (or a Part set while an upload is recorded) is rebuilt at start, before anything
-- has prepared or used it, so a live server always runs the meshes, the hall's light and the red room.
function TC.ensure(): Instance?
	if ensuring then -- another thread is building or preparing it: wait for the prepared set
		local deadline = os.clock() + 30
		local m: Instance? = nil
		repeat
			task.wait(0.1)
			m = workspace:FindFirstChild(TC.MODEL_NAME)
		until (m and m:GetAttribute("RuntimeReady") == true) or os.clock() > deadline
		return m
	end
	ensuring = true
	local m = workspace:FindFirstChild(TC.MODEL_NAME)
	if m and m:GetAttribute("BlenderSet") == true and m:GetAttribute("RuntimeReady") ~= true then
		local stale = (tonumber(m:GetAttribute("BuildVersion")) or 0) < TC.VERSION
			or (m:GetAttribute("Source") ~= "mesh" and DATA.assetId ~= nil)
		if stale then
			local result = TC.build({ noLock = true, source = "auto" })
			print("[TrainingCentreBuilder] rebuilt the saved set: " .. result)
			m = workspace:FindFirstChild(TC.MODEL_NAME)
		end
	elseif not m then
		local result = TC.build({ noLock = true, source = "auto" })
		print("[TrainingCentreBuilder] " .. result)
		m = workspace:FindFirstChild(TC.MODEL_NAME)
	end
	if m and m:GetAttribute("BlenderSet") == true then
		local ok, why = pcall(TC.prepare, m)
		if not ok then
			warn("[TrainingCentreBuilder] prepare failed: " .. tostring(why))
			m:SetAttribute("RuntimeReady", true)
		end
	end
	ensuring = false
	return m
end

function TC.remove(name: string?): string
	local m = workspace:FindFirstChild(name or TC.MODEL_NAME)
	if m and m:GetAttribute("BlenderSet") == true then
		m:Destroy()
		return "removed workspace." .. (name or TC.MODEL_NAME)
	end
	return "nothing of ours to remove"
end

return TC
