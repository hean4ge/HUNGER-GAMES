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
	  Lamps                PointLights (hall downlights marked light, platform banks, corridor)
	Nothing here uploads, saves or publishes. It takes the shared-Studio lock (Workspace attribute QA_Lock).
]]
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local DATA = require(ServerStorage:WaitForChild("WorldGen"):WaitForChild("TrainingCentreData"):Clone())

local TC = {}

TC.HALL_AT = CFrame.new(DATA.hallOrigin[1], DATA.hallOrigin[2], DATA.hallOrigin[3])
TC.MODEL_NAME = "TrainingCentre"
TC.LOCK_LABEL = "training-centre"
local ROT = CFrame.Angles(0, math.pi, 0)
local HALL_LAMP = Color3.fromRGB(236, 240, 236)
local PLAT_LAMP = Color3.fromRGB(255, 220, 180)
local RED_LAMP = Color3.fromRGB(255, 70, 56)
local SHADOW_LAMPS = { Lamp_05_03 = true, Lamp_07_05 = true }

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
	p.Color = Color3.fromRGB(spec.c[1], spec.c[2], spec.c[3])
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
					if source == "mesh" then
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
							if (not isHall) or at.light then
								local holder = markerPart(mn, frame, mk, fLamps)
								local light = Instance.new("PointLight")
								if isPlat then
									light.Color, light.Range, light.Brightness = PLAT_LAMP, 22, 1.2
									holder:SetAttribute("Bank", at.bank)
								elseif mn == "RedLamp" or at.red then
									light.Color, light.Range, light.Brightness = RED_LAMP, if mn == "RedLamp" then 16 else 12, 1
								else
									light.Color, light.Range, light.Brightness = HALL_LAMP, 40, 1.4
								end
								light.Shadows = SHADOW_LAMPS[mn] == true
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
		fMarkers.Parent = root
		fSpawns.Parent = root
		fLamps.Parent = root
		fMats.Parent = root
		if container then
			container:Destroy()
		end
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
function TC.ensure(): Instance?
	local m = workspace:FindFirstChild(TC.MODEL_NAME)
	if not m then
		if ensuring then
			local deadline = os.clock() + 20
			repeat
				task.wait(0.1)
				m = workspace:FindFirstChild(TC.MODEL_NAME)
			until (m and m:GetAttribute("RuntimeReady") == true) or os.clock() > deadline
			return m
		end
		ensuring = true
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
