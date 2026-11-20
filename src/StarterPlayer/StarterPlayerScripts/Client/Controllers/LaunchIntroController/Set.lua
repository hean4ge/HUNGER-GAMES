--[[
	LaunchIntroController.Set - the launch intro's set, built on this client from Parts and a few lights (no uploads),
	far from the arena (around x = -12000, y = 600), once per client, and parented to nil while no shot shows it.
	  * The red room (the transition room): oxblood walls, a roof of red panels under a fine dark net set at 45 degrees
	    to the teal hexagonal frame of the lift shaft, a short oxblood hood with a thin red lip under the frame, a
	    blue-grey steel deck with white stripes, black grates over dark pits, red mesh and red light in the two openings
	    beside the lift, a red rail with two lamp housings round the dusty-rose lift disc, and a walkway on the back wall.
	  * The pole hall: a huge dark round hall (radius 130). On its floor the ring of glass cases (one per plate, facing
	    the centre) on dark steel pedestals with raised dark-red discs, a maroon wall unit with a white panel between
	    every other pair, a walkway with a pale kerb and a gantry of white strip lights; behind the cases a banked ring
	    of oxblood and pale stripes. Tall thin dark poles rise from every case to a white opening in the roof (copper
	    bands on High); white light bars on the walls and in radial rows on the ceiling; the spoked ceiling ring with
	    its hub of spots.
	Shapes, sizes and colours follow art/blender/launch_rooms.py (TwoArenas.md section 2.2), translated to Roblox's own
	materials: painted steel as Plastic / SmoothPlastic (Roblox's Metal reads black in a closed set with no sky to
	reflect), bare steel and copper as Metal, the walkways DiamondPlate, the case glass Glass, the light bars Neon, the
	apron WoodPlanks: semi-real, never photo-real. The red room is
	lower than Blender's (net at 10.6 instead of 20) so the stand-in fills the frame through the hex. The Blender set can
	replace this one later behind the same API.

	Set.build(opts) -> set   yields between groups of parts; the model stays parented to nil (show it with
	                         set.model.Parent = workspace)
	  opts.detail  "High" | "Medium" | "Low" (DetailController's tier). Medium: no bolts, girts or purlins. Low: also
	               every other net and mesh bar, no copper bands, ribs or floor seams, half the light bars, and no
	               light casts shadows.
	  opts.slots   cases in the ring (the plate count)
	set.red  = { origin: CFrame (floor centre under the hex; the stand-in faces +Z, toward the camera side),
	             lift: BasePart (the lift disc's root: move it to raise the stand-in), liftHome: CFrame, liftTop: number
	             (its top above the floor), hexY: number (top of the hex frame), lights = { key, roof, fill, lamp, pits } }
	set.hall = { origin: CFrame (floor centre), slotRadius: number, slots = { [i] = { cf: CFrame (case floor centre;
	             -Z faces the hall centre), riser: BasePart (disc root), riserCF: CFrame (its home), riserTop: number,
	             strip: BasePart (the case's top light), light: SpotLight, units: { BasePart } (wall units beside it) } },
	             poleOffset: Vector3 (a pole's foot from its case centre, case space), poleTop: number,
	             riderAnchor: BasePart (SpotLight "Key"), gantryAnchor: BasePart (SurfaceLight "Fill"),
	             ride: Model (your ride, in case space: rails with lamps, collars, the roof shaft and its bright top;
	             PivotTo a slot's cf), shaftY: number (the shaft's mouth above the case floor),
	             lights = { hub, rider, riderFill, gantry } }
	set.parts: number   parts built          set.detail: the tier it was built for
]]
local Set = {}

local RED_ORIGIN = CFrame.new(-12000, 600, 900)
local HALL_ORIGIN = CFrame.new(-12000, 600, 0)
local M = Enum.Material
-- Painted steel is Plastic / SmoothPlastic: Roblox's Metal reflects the sky, and a closed set has none to show, so it
-- reads black. Bare steel and copper stay Metal (small parts that catch the lights).
local PAINT = M.SmoothPlastic
local PANEL = M.Plastic
local STEEL = M.Metal
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is its X: stand it up
local TAN30 = math.tan(math.rad(30))

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- The palette of launch_rooms.py (the semi-real tones; the light carries the hue, the paint stays neutral).
local C = {
	oxblood = rgb(86, 53, 53),
	oxbloodDk = rgb(66, 41, 43),
	net = rgb(62, 82, 86),
	hex = rgb(66, 114, 122),
	bolt = rgb(84, 96, 100),
	rose = rgb(126, 101, 121),
	roseRim = rgb(58, 38, 41),
	deck = rgb(120, 130, 136),
	grate = rgb(34, 36, 38),
	pit = rgb(18, 18, 20),
	redmesh = rgb(87, 48, 61),
	redpit = rgb(70, 30, 34),
	rail = rgb(126, 63, 75),
	stripe = rgb(206, 206, 200),
	lamp = rgb(112, 57, 72),
	concrete = rgb(126, 126, 122),
	post = rgb(90, 59, 63),
	caseDisc = rgb(89, 60, 62),
	discRim = rgb(82, 51, 54),
	unit = rgb(94, 58, 63),
	plinth = rgb(76, 80, 86),
	walkway = rgb(54, 59, 66),
	shell = rgb(58, 66, 78),
	truss = rgb(96, 104, 114),
	floor = rgb(70, 76, 84),
	wedgeRed = rgb(92, 63, 62),
	wedgePale = rgb(176, 178, 176),
	steel = rgb(164, 166, 168),
	pole = rgb(70, 74, 80),
	copper = rgb(176, 112, 70),
	housing = rgb(64, 68, 74),
	light = rgb(236, 240, 244),
	lens = rgb(245, 240, 232),
	glass = rgb(196, 210, 214),
}
Set.Colors = C
Set.RED_ORIGIN = RED_ORIGIN
Set.HALL_ORIGIN = HALL_ORIGIN

local count = 0

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?,
	opts: { [string]: any }?): BasePart
	local o = opts or {}
	local p: any = Instance.new(o.class or "Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.shape then
		p.Shape = o.shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or PAINT
	if o.shadow == false then
		p.CastShadow = false
	end
	if o.transparency then
		p.Transparency = o.transparency
	end
	p.Parent = parent
	count += 1
	return p
end

-- an upright cylinder (axis along the CFrame's Y)
local function cylinder(parent: Instance, name: string, height: number, diameter: number, centre: CFrame, color: Color3,
	material: Enum.Material?, opts: { [string]: any }?): BasePart
	local o = if opts then table.clone(opts) else {}
	o.shape = Enum.PartType.Cylinder
	return part(parent, name, Vector3.new(height, diameter, diameter), centre * UPRIGHT, color, material, o)
end

-- a box from a to b (w across, h up)
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, w: number, h: number, color: Color3,
	material: Enum.Material?, opts: { [string]: any }?): BasePart
	local d = b - a
	local up = if math.abs(d.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return part(parent, name, Vector3.new(w, h, d.Magnitude), CFrame.lookAt((a + b) / 2, b, up), color, material, opts)
end

-- A flat right triangle in the horizontal plane (a WedgePart t thick): the right angle at `corner`, one leg along u1
-- (length l1) and the other along u2 (length l2); u1 and u2 horizontal and perpendicular.
local function triangle(parent: Instance, name: string, corner: Vector3, u1: Vector3, l1: number, u2: Vector3, l2: number,
	t: number, color: Color3, material: Enum.Material?): BasePart
	-- a wedge's right angle sits at local (-Y/2, +Z/2): X = thickness, Y = leg 1, Z = minus leg 2
	local xAxis = Vector3.yAxis
	if xAxis:Cross(u1):Dot(u2) > 0 then
		xAxis = -Vector3.yAxis
	end
	local centre = corner + u1 * (l1 / 2) + u2 * (l2 / 2)
	return part(parent, name, Vector3.new(t, l1, l2), CFrame.fromMatrix(centre, xAxis, u1), color, material,
		{ class = "WedgePart" })
end

local function weldTo(root: BasePart, p: BasePart)
	p.Anchored = false
	p.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
end

local function anchor(parent: Instance, name: string, cf: CFrame): BasePart
	return part(parent, name, Vector3.new(0.2, 0.2, 0.2), cf, C.housing, M.SmoothPlastic, { transparency = 1, shadow = false })
end

local function folder(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Rectangles { x0, z0, x1, z1 } covering `room` minus the `holes`: cells of the breakpoint grid, merged along x per row.
local function rectSubtract(room: { number }, holes: { { number } }): { { number } }
	local function uniq(list: { number }): { number }
		table.sort(list)
		local out = {}
		for _, v in ipairs(list) do
			if #out == 0 or math.abs(v - out[#out]) > 1e-6 then
				table.insert(out, v)
			end
		end
		return out
	end
	local xs, zs = { room[1], room[3] }, { room[2], room[4] }
	for _, h in ipairs(holes) do
		for _, v in ipairs({ h[1], h[3] }) do
			if v > room[1] and v < room[3] then
				table.insert(xs, v)
			end
		end
		for _, v in ipairs({ h[2], h[4] }) do
			if v > room[2] and v < room[4] then
				table.insert(zs, v)
			end
		end
	end
	xs, zs = uniq(xs), uniq(zs)
	local out = {}
	for j = 1, #zs - 1 do
		local za, zb = zs[j], zs[j + 1]
		local run: { number }? = nil
		for i = 1, #xs - 1 do
			local xa, xb = xs[i], xs[i + 1]
			local cx, cz = (xa + xb) / 2, (za + zb) / 2
			local inside = false
			for _, h in ipairs(holes) do
				if cx > h[1] and cx < h[3] and cz > h[2] and cz < h[4] then
					inside = true
					break
				end
			end
			if inside then
				if run then
					table.insert(out, { run[1], za, run[2], zb })
					run = nil
				end
			else
				run = if run then { run[1], xb } else { xa, xb }
			end
		end
		if run then
			table.insert(out, { run[1], za, run[2], zb })
		end
	end
	return out
end

-- The interval (s0, s1) of the line o + d * s inside a convex polygon (Vector2 points (x, z)), or nil.
local function clipConvex(o: Vector2, d: Vector2, poly: { Vector2 }): (number?, number?)
	local centre = Vector2.zero
	for _, p in ipairs(poly) do
		centre += p
	end
	centre /= #poly
	local s0, s1 = -math.huge, math.huge
	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		local e = b - a
		local nIn = Vector2.new(-e.Y, e.X)
		if (centre - a):Dot(nIn) < 0 then
			nIn = -nIn
		end
		local num = (o - a):Dot(nIn)
		local den = d:Dot(nIn)
		if math.abs(den) < 1e-9 then
			if num < 0 then
				return nil, nil
			end
		elseif den > 0 then
			s0 = math.max(s0, -num / den)
		else
			s1 = math.min(s1, -num / den)
		end
	end
	if s1 - s0 <= 1e-6 then
		return nil, nil
	end
	return s0, s1
end

-- pointy hexagon (vertices on +-Z, flats on +-X) of apothem a, as Vector2 (x, z)
local function hexPoly(a: number): { Vector2 }
	local r = a / math.cos(math.rad(30))
	return {
		Vector2.new(0, -r), Vector2.new(a, -r / 2), Vector2.new(a, r / 2),
		Vector2.new(0, r), Vector2.new(-a, r / 2), Vector2.new(-a, -r / 2),
	}
end

-- Bars of a diamond net (both 45-degree directions, `pitch` apart) over the rectangle {x0, z0, x1, z1} minus the
-- convex `hole`, at height y in the frame `origin`.
local function diamondNet(parent: Instance, name: string, origin: CFrame, rect: { number }, hole: { Vector2 }?, pitch: number,
	y: number, w: number, h: number, color: Color3, material: Enum.Material)
	local box = { Vector2.new(rect[1], rect[2]), Vector2.new(rect[3], rect[2]), Vector2.new(rect[3], rect[4]),
		Vector2.new(rect[1], rect[4]) }
	local cx, cz = (rect[1] + rect[3]) / 2, (rect[2] + rect[4]) / 2
	local reach = (math.abs(rect[3] - rect[1]) + math.abs(rect[4] - rect[2])) / 2
	for _, d in ipairs({ Vector2.new(1, 1).Unit, Vector2.new(1, -1).Unit }) do
		local n = Vector2.new(-d.Y, d.X)
		local k = math.ceil(reach / pitch)
		for i = -k, k do
			local o = Vector2.new(cx, cz) + n * (i * pitch + pitch * 0.5)
			local r0, r1 = clipConvex(o, d, box)
			if r0 and r1 then
				local spans = { { r0, r1 } }
				if hole then
					local h0, h1 = clipConvex(o, d, hole)
					if h0 and h1 and h1 > r0 and h0 < r1 then
						spans = {}
						if h0 > r0 then
							table.insert(spans, { r0, h0 })
						end
						if h1 < r1 then
							table.insert(spans, { h1, r1 })
						end
					end
				end
				for _, s in ipairs(spans) do
					if s[2] - s[1] > 0.3 then
						local a = o + d * s[1]
						local b = o + d * s[2]
						beam(parent, name, (origin * CFrame.new(a.X, y, a.Y)).Position,
							(origin * CFrame.new(b.X, y, b.Y)).Position, w, h, color, material, { shadow = true })
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The red room
--------------------------------------------------------------------------------------------------------------------

local function buildRed(model: Model, detail: string)
	local room = folder(model, "RedRoom")
	local O = RED_ORIGIN
	local low, high = detail == "Low", detail == "High"
	local function at(x: number, y: number, z: number): CFrame
		return O * CFrame.new(x, y, z)
	end
	local function pt(x: number, y: number, z: number): Vector3
		return (O * CFrame.new(x, y, z)).Position
	end
	local W, D = 12, 10 -- half extents inside: 24 x 20
	local FLOOR_BOTTOM = -1.8 -- the pits' floor
	local ROOF_BOTTOM, ROOF_TOP = 10.6, 11.0
	local A_IN, A_OUT = 5.0, 5.8 -- the hex frame: 10 across the flats inside, square tube 0.8
	local A_MID = (A_IN + A_OUT) / 2
	local R_MID = A_MID / math.cos(math.rad(30))
	local FRAME_Y = ROOF_TOP + 0.4

	-- the pit floor under everything, dark (the red pits get their own red floor)
	part(room, "PitFloor", Vector3.new(2 * W + 2, 1, 2 * D + 2), at(0, FLOOR_BOTTOM - 0.5, 0), C.pit, PAINT)

	-- the deck: steel plates round the openings (2 red pits beside the lift, 2 grate lanes in front and behind)
	local pitL = { -10.6, -2.6, -6.2, 2.6 }
	local pitR = { 6.2, -2.6, 10.6, 2.6 }
	local laneF = { -4.5, 5.4, 4.5, 8.9 }
	local laneB = { -4.5, -8.9, 4.5, -5.4 }
	for _, r in ipairs(rectSubtract({ -W, -D, W, D }, { pitL, pitR, laneF, laneB })) do
		local sx, sz = r[3] - r[1], r[4] - r[2]
		part(room, "Deck", Vector3.new(sx, -FLOOR_BOTTOM, sz), at((r[1] + r[3]) / 2, FLOOR_BOTTOM / 2, (r[2] + r[4]) / 2),
			C.deck, PANEL)
	end
	-- the oxblood apron (painted boards) and the lift: a dark rim ring and the dusty-rose disc
	part(room, "Apron", Vector3.new(9, 0.1, 9), at(0, 0.0, 0), C.oxbloodDk, M.WoodPlanks)
	cylinder(room, "LiftRim", 0.16, 7.0, at(0, 0.12, 0), C.roseRim, PAINT)
	local lift = cylinder(room, "Lift", 0.3, 6.4, at(0, 0.2, 0), C.rose, PAINT)
	local liftTop = 0.35

	-- the red openings: red mesh at 45 degrees, a red floor and a red light in each
	local pits = {}
	for _, r in ipairs({ pitL, pitR }) do
		local cx, cz = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
		part(room, "RedPitFloor", Vector3.new(r[3] - r[1], 0.2, r[4] - r[2]), at(cx, FLOOR_BOTTOM + 0.1, cz), C.redpit,
			M.Metal)
		diamondNet(room, "RedMesh", O, { r[1], r[2], r[3], r[4] }, nil, if low then 1.6 else 0.9, -0.28, 0.14, 0.12,
			C.redmesh, PAINT)
		local l = Instance.new("PointLight")
		l.Name = "Pit"
		l.Color = Color3.fromRGB(255, 62, 58)
		l.Brightness = 2.4
		l.Range = 6.5
		l.Shadows = false
		l.Parent = anchor(room, "PitLight", at(cx, FLOOR_BOTTOM + 0.9, cz))
		table.insert(pits, l)
	end
	-- the grate lanes: black square grates over the dark pits (frame and bars)
	for _, r in ipairs({ laneF, laneB }) do
		local x0, z0, x1, z1 = r[1], r[2], r[3], r[4]
		local y = -0.12
		local frameW = 0.3
		beam(room, "GrateFrame", pt(x0, y, z0 + frameW / 2), pt(x1, y, z0 + frameW / 2), frameW, 0.24, C.grate, PAINT)
		beam(room, "GrateFrame", pt(x0, y, z1 - frameW / 2), pt(x1, y, z1 - frameW / 2), frameW, 0.24, C.grate, PAINT)
		beam(room, "GrateFrame", pt(x0 + frameW / 2, y, z0), pt(x0 + frameW / 2, y, z1), frameW, 0.24, C.grate, PAINT)
		beam(room, "GrateFrame", pt(x1 - frameW / 2, y, z0), pt(x1 - frameW / 2, y, z1), frameW, 0.24, C.grate, PAINT)
		beam(room, "GrateFrame", pt(0, y, z0), pt(0, y, z1), frameW, 0.24, C.grate, PAINT) -- two grates per lane
		local step = if low then 1.8 else 0.9
		local x = x0 + step
		while x < x1 - 0.2 do
			if math.abs(x) > 0.25 then
				beam(room, "GrateBar", pt(x, y, z0), pt(x, y, z1), 0.14, 0.2, C.grate, PAINT)
			end
			x += step
		end
		local z = z0 + step
		while z < z1 - 0.2 do
			beam(room, "GrateBar", pt(x0, y - 0.03, z), pt(x1, y - 0.03, z), 0.14, 0.18, C.grate, PAINT)
			z += step
		end
	end
	-- white floor stripes along the lanes and the walls
	for _, x in ipairs({ -5.35, 5.35 }) do
		part(room, "Stripe", Vector3.new(0.35, 0.04, 2 * D), at(x, 0.02, 0), C.stripe, M.SmoothPlastic)
	end
	for _, z in ipairs({ -9.35, 9.35 }) do
		part(room, "Stripe", Vector3.new(2 * W, 0.04, 0.35), at(0, 0.02, z), C.stripe, M.SmoothPlastic)
	end
	-- the red rail round the apron, and two lamp housings on its back rail
	local RAIL = 4.8
	for _, p in ipairs({ { -RAIL, -RAIL }, { RAIL, -RAIL }, { -RAIL, RAIL }, { RAIL, RAIL }, { -RAIL, 0 }, { RAIL, 0 } }) do
		cylinder(room, "RailPost", 3.6, 0.3, at(p[1], 1.8, p[2]), C.rail, PAINT)
	end
	for _, s in ipairs({ { -RAIL, -RAIL, RAIL, -RAIL }, { -RAIL, RAIL, RAIL, RAIL }, { -RAIL, -RAIL, -RAIL, RAIL },
		{ RAIL, -RAIL, RAIL, RAIL } }) do
		beam(room, "Rail", pt(s[1], 3.55, s[2]), pt(s[3], 3.55, s[4]), 0.3, 0.3, C.rail, PAINT)
	end
	for _, x in ipairs({ -RAIL, RAIL }) do
		beam(room, "Rail", pt(x, 2.1, -RAIL), pt(x, 2.1, RAIL), 0.26, 0.26, C.rail, PAINT)
	end
	for _, x in ipairs({ -1.15, 1.15 }) do
		part(room, "LampHousing", Vector3.new(0.95, 0.75, 0.8), at(x, 3.95, -RAIL), C.lamp, PAINT)
		cylinder(room, "LampLens", 0.1, 0.62, at(x, 4.36, -RAIL), C.lens, M.Neon, { shadow = false })
	end
	local lamp = Instance.new("PointLight")
	lamp.Name = "Lamp"
	lamp.Color = Color3.fromRGB(255, 236, 220)
	lamp.Brightness = 0.9
	lamp.Range = 7
	lamp.Shadows = false
	lamp.Parent = anchor(room, "LampLight", at(0, 4.6, -RAIL))

	-- oxblood walls on a concrete base course, with vertical ribs
	local wallH = ROOF_TOP - FLOOR_BOTTOM
	local wallY = (ROOF_TOP + FLOOR_BOTTOM) / 2
	part(room, "Wall", Vector3.new(1, wallH, 2 * D + 2), at(-W - 0.5, wallY, 0), C.oxblood, PANEL)
	part(room, "Wall", Vector3.new(1, wallH, 2 * D + 2), at(W + 0.5, wallY, 0), C.oxblood, PANEL)
	part(room, "Wall", Vector3.new(2 * W + 2, wallH, 1), at(0, wallY, -D - 0.5), C.oxblood, PANEL)
	part(room, "Wall", Vector3.new(2 * W + 2, wallH, 1), at(0, wallY, D + 0.5), C.oxblood, PANEL)
	part(room, "BaseCourse", Vector3.new(0.4, 1.2, 2 * D), at(-W + 0.2, 0.6, 0), C.concrete, M.Concrete)
	part(room, "BaseCourse", Vector3.new(0.4, 1.2, 2 * D), at(W - 0.2, 0.6, 0), C.concrete, M.Concrete)
	part(room, "BaseCourse", Vector3.new(2 * W, 1.2, 0.4), at(0, 0.6, -D + 0.2), C.concrete, M.Concrete)
	part(room, "BaseCourse", Vector3.new(2 * W, 1.2, 0.4), at(0, 0.6, D - 0.2), C.concrete, M.Concrete)
	if not low then
		for _, v in ipairs({ -8, -4, 0, 4, 8 }) do
			part(room, "Rib", Vector3.new(0.35, ROOF_BOTTOM - 1.2, 0.45), at(-W + 0.18, (ROOF_BOTTOM + 1.2) / 2, v), C.oxbloodDk, PAINT)
			part(room, "Rib", Vector3.new(0.35, ROOF_BOTTOM - 1.2, 0.45), at(W - 0.18, (ROOF_BOTTOM + 1.2) / 2, v), C.oxbloodDk, PAINT)
			part(room, "Rib", Vector3.new(0.45, ROOF_BOTTOM - 1.2, 0.35), at(v, (ROOF_BOTTOM + 1.2) / 2, -D + 0.18), C.oxbloodDk, PAINT)
		end
	end
	-- a walkway along the back wall
	part(room, "Walkway", Vector3.new(2 * W, 0.3, 2.6), at(0, 6.4, -D + 1.3), C.deck, M.DiamondPlate)
	for _, x in ipairs({ -10, -5, 0, 5, 10 }) do
		cylinder(room, "WalkwayPost", 3.2, 0.22, at(x, 8.15, -D + 2.45), C.rail, PAINT)
	end
	beam(room, "WalkwayRail", pt(-W, 9.7, -D + 2.45), pt(W, 9.7, -D + 2.45), 0.22, 0.22, C.rail, PAINT)

	-- the roof round the hex (red panels), the fine net over it, the hex frame, the hood and its lip under the frame
	local roofT = ROOF_TOP - ROOF_BOTTOM
	local roofY = (ROOF_TOP + ROOF_BOTTOM) / 2
	local E = 1 -- the roof runs into the walls
	part(room, "Roof", Vector3.new(W + E - A_MID, roofT, 2 * (D + E)), at(-(W + E + A_MID) / 2, roofY, 0), C.oxblood, PANEL)
	part(room, "Roof", Vector3.new(W + E - A_MID, roofT, 2 * (D + E)), at((W + E + A_MID) / 2, roofY, 0), C.oxblood, PANEL)
	part(room, "Roof", Vector3.new(2 * A_MID, roofT, D + E - R_MID), at(0, roofY, -(D + E + R_MID) / 2), C.oxblood, PANEL)
	part(room, "Roof", Vector3.new(2 * A_MID, roofT, D + E - R_MID), at(0, roofY, (D + E + R_MID) / 2), C.oxblood, PANEL)
	local rx, rz = O.RightVector, -O.LookVector -- room +X and +Z in world space
	local function corner(x: number, z: number): Vector3
		return pt(x, roofY, z)
	end
	-- the four triangles between the hex's slanted sides and the roof panels
	triangle(room, "Roof", corner(A_MID, -R_MID), -rx, A_MID, rz, R_MID / 2, roofT, C.oxblood, PANEL)
	triangle(room, "Roof", corner(-A_MID, -R_MID), rx, A_MID, rz, R_MID / 2, roofT, C.oxblood, PANEL)
	triangle(room, "Roof", corner(A_MID, R_MID), -rx, A_MID, -rz, R_MID / 2, roofT, C.oxblood, PANEL)
	triangle(room, "Roof", corner(-A_MID, R_MID), rx, A_MID, -rz, R_MID / 2, roofT, C.oxblood, PANEL)
	diamondNet(room, "Net", O, { -W, -D, W, D }, hexPoly(A_OUT), if low then 2.9 else 1.45, ROOF_TOP + 0.08, 0.2, 0.14,
		C.net, PAINT)
	local frame = hexPoly(A_MID)
	for i = 1, 6 do
		local a, b = frame[i], frame[i % 6 + 1]
		local dir = (b - a).Unit
		local ext = 0.8 * TAN30 / 2 + 0.02
		local pa, pb = a - dir * ext, b + dir * ext
		beam(room, "HexFrame", pt(pa.X, FRAME_Y, pa.Y), pt(pb.X, FRAME_Y, pb.Y), 0.8, 0.8, C.hex, PAINT)
		cylinder(room, "Gusset", 0.12, 1.5, at(a.X, FRAME_Y + 0.46, a.Y), C.bolt, PAINT)
		if high then
			for _, s in ipairs({ -0.4, 0.4 }) do
				cylinder(room, "Bolt", 0.16, 0.26, at(a.X + dir.X * s, FRAME_Y + 0.58, a.Y + dir.Y * s), C.bolt, STEEL)
			end
		end
	end
	local hood = hexPoly(A_IN + 0.15)
	local lip = hexPoly(A_IN - 0.05)
	for i = 1, 6 do
		local a, b = hood[i], hood[i % 6 + 1]
		local dir = (b - a).Unit
		local pa, pb = a - dir * 0.1, b + dir * 0.1
		local hoodTop, hoodBottom = ROOF_BOTTOM, 7.4
		local mid = (pa + pb) / 2
		part(room, "Hood", Vector3.new(0.3, hoodTop - hoodBottom, (pb - pa).Magnitude),
			CFrame.lookAt(pt(mid.X, (hoodTop + hoodBottom) / 2, mid.Y), pt(pb.X, (hoodTop + hoodBottom) / 2, pb.Y)),
			C.oxblood, PANEL)
		local la, lb = lip[i], lip[i % 6 + 1]
		beam(room, "HoodLip", pt(la.X, hoodBottom + 0.1, la.Y), pt(lb.X, hoodBottom + 0.1, lb.Y), 0.16, 0.16, C.rail, PAINT)
	end

	-- the lift shaft above the hex (first person, 20 Nov: you look up through the frame as the lift starts): six dark
	-- walls from the frame up, two pale bands inside and a bright cap at the top, the light the lift carries you toward
	local SHAFT_TOP = FRAME_Y + 11
	local shaftWall = hexPoly(A_OUT + 0.25)
	local shaftBand = hexPoly(A_OUT + 0.08)
	for i = 1, 6 do
		local a, b = shaftWall[i], shaftWall[i % 6 + 1]
		local dir = (b - a).Unit
		local pa, pb = a - dir * 0.15, b + dir * 0.15
		local mid = (pa + pb) / 2
		local midY = (FRAME_Y + 0.4 + SHAFT_TOP) / 2
		part(room, "LiftShaft", Vector3.new(0.3, SHAFT_TOP - FRAME_Y - 0.4, (pb - pa).Magnitude),
			CFrame.lookAt(pt(mid.X, midY, mid.Y), pt(pb.X, midY, pb.Y)), C.oxbloodDk, PANEL, { shadow = false })
		local la, lb = shaftBand[i], shaftBand[i % 6 + 1]
		for _, y in ipairs(if low then { SHAFT_TOP - 3 } else { FRAME_Y + 4, SHAFT_TOP - 3 }) do
			beam(room, "LiftShaftBand", pt(la.X, y, la.Y), pt(lb.X, y, lb.Y), 0.1, 0.22, C.light, M.Neon, { shadow = false })
		end
	end
	part(room, "LiftShaftCap", Vector3.new(2 * A_OUT + 1, 0.3, 2 * (A_OUT + 0.5) / math.cos(math.rad(30))), at(0, SHAFT_TOP, 0),
		C.lens, M.Neon, { shadow = false })

	-- lights: a cool white key down the shaft, a cool fill under the roof, the lamp, red light in the openings
	local keyAnchor = anchor(room, "KeyLight", CFrame.lookAt(pt(0, ROOF_BOTTOM - 0.5, 1.2), pt(0, 0, -0.3)))
	local key = Instance.new("SpotLight")
	key.Name = "Key"
	key.Face = Enum.NormalId.Front
	key.Color = Color3.fromRGB(226, 234, 255)
	key.Brightness = 2.8
	key.Range = 16
	key.Angle = 80
	key.Shadows = not low
	key.Parent = keyAnchor
	-- a soft light from above for the net, the hex frame and the roof panels (seen from the shaft's mouth)
	local roofAnchor = anchor(room, "RoofLight", CFrame.lookAt(pt(0, 24, 5), pt(0, ROOF_TOP, -1.5)))
	local roof = Instance.new("SpotLight")
	roof.Name = "Roof"
	roof.Face = Enum.NormalId.Front
	roof.Color = Color3.fromRGB(214, 226, 255)
	roof.Brightness = 1.4
	roof.Range = 26
	roof.Angle = 110
	roof.Shadows = false
	roof.Parent = roofAnchor
	local fillAnchor = anchor(room, "FillLight", CFrame.lookAt(pt(0, ROOF_BOTTOM - 0.4, 0), pt(0, 0, 0), Vector3.zAxis))
	local fill = Instance.new("SpotLight")
	fill.Name = "Fill"
	fill.Face = Enum.NormalId.Front
	fill.Color = Color3.fromRGB(150, 172, 255)
	fill.Brightness = 1.0
	fill.Range = 18
	fill.Angle = 150
	fill.Shadows = false
	fill.Parent = fillAnchor

	return {
		origin = O,
		lift = lift,
		liftHome = lift.CFrame,
		liftTop = liftTop,
		hexY = FRAME_Y + 0.4,
		model = room,
		lights = { key = key, roof = roof, fill = fill, lamp = lamp, pits = pits },
	}
end

--------------------------------------------------------------------------------------------------------------------
-- The pole hall and the ring of glass cases
--------------------------------------------------------------------------------------------------------------------

local function buildHall(model: Model, detail: string, slotCount: number)
	local hall = folder(model, "PoleHall")
	local O = HALL_ORIGIN
	local low, high = detail == "Low", detail == "High"
	local N = math.max(4, slotCount)
	local STEP = 360 / N
	local R_CASE = 60
	local R_WALL = 130
	local ROOF_Y = 124
	local CROWN_Y = 117
	local POLE_X, POLE_Z = -1.2, 1.45 -- the pole stands just behind the stand-in's left shoulder, inside the case
	local function polar(deg: number, r: number, y: number): Vector3
		local a = math.rad(deg)
		return (O * CFrame.new(math.sin(a) * r, y, -math.cos(a) * r)).Position
	end
	local centreAt = function(y: number): Vector3
		return (O * CFrame.new(0, y, 0)).Position
	end
	-- facing the hall centre (-Z to the centre)
	local function facing(deg: number, r: number, y: number): CFrame
		local p = polar(deg, r, y)
		return CFrame.lookAt(p, centreAt(y))
	end

	-- floor: the dark disc, the banked ring of oxblood and pale stripes behind the cases, seams in the centre
	cylinder(hall, "Floor", 2, 2 * (R_WALL + 4), O * CFrame.new(0, -1, 0), C.floor, PANEL)
	cylinder(hall, "Ring", 0.2, 248, O * CFrame.new(0, 0.1, 0), C.wedgeRed, PANEL)
	cylinder(hall, "InnerFloor", 0.24, 132, O * CFrame.new(0, 0.12, 0), C.floor, PANEL)
	for k = 1, N do
		local deg = (k - 1) * STEP + STEP / 2
		beam(hall, "Stripe", polar(deg, 67, 0.215), polar(deg, 123, 0.215), 5, 0.03, C.wedgePale, M.SmoothPlastic)
	end
	if not low then
		for k = 1, 12 do
			beam(hall, "Seam", polar(k * 30, 6, 0.25), polar(k * 30, 46, 0.25), 0.4, 0.03, C.wedgePale, M.SmoothPlastic)
		end
	end
	task.wait()

	-- the walkway in front of the cases (pale kerb) and the gantry of strip lights over it
	for k = 1, N do
		local deg = (k - 1) * STEP
		local chordOuter = 2 * 57.2 * math.sin(math.rad(STEP / 2)) + 0.3
		part(hall, "Walkway", Vector3.new(chordOuter, 0.3, 8.6), facing(deg, 52.9, 0.15), C.walkway, M.DiamondPlate)
		local chordKerb = 2 * 48.6 * math.sin(math.rad(STEP / 2)) + 0.2
		part(hall, "Kerb", Vector3.new(chordKerb, 0.45, 0.7), facing(deg, 48.25, 0.225), C.wedgePale, M.Concrete)
		local g0, g1 = polar(deg - STEP / 2, 49.6, 13.6), polar(deg + STEP / 2, 49.6, 13.6)
		beam(hall, "Gantry", g0, g1, 0.9, 1.1, C.truss, PAINT)
		local s0, s1 = g0:Lerp(g1, 0.1) - O.UpVector * 0.6, g0:Lerp(g1, 0.9) - O.UpVector * 0.6
		beam(hall, "GantryStrip", s0, s1, 0.45, 0.12, C.light, M.Neon, { shadow = false })
	end
	task.wait()

	-- the cases: pedestal, the riser (dark-red disc, rim and the collar on the pole), posts, glass, header, top light
	local slots = {}
	for k = 1, N do
		local deg = (k - 1) * STEP
		local sc = facing(deg, R_CASE, 0)
		local slot = { index = k, bearing = deg, cf = sc, units = {} }
		cylinder(hall, "Pedestal", 0.62, 4.8, sc * CFrame.new(0, 0.31, 0), C.plinth, PAINT)
		local riser = cylinder(hall, "Riser", 0.3, 4.1, sc * CFrame.new(0, 0.77, 0), C.caseDisc, PAINT)
		if not low then
			weldTo(riser, cylinder(hall, "RiserRim", 0.16, 4.35, sc * CFrame.new(0, 0.66, 0), C.discRim, PAINT))
		end
		weldTo(riser, cylinder(hall, "Collar", 1.0, 1.25, sc * CFrame.new(POLE_X, 0.85, POLE_Z), C.steel, STEEL))
		slot.riser = riser
		slot.riserCF = riser.CFrame
		slot.riserTop = 0.92
		for _, p in ipairs({ { -2.45, -2.45 }, { 2.45, -2.45 }, { -2.45, 2.45 }, { 2.45, 2.45 } }) do
			part(hall, "Post", Vector3.new(0.5, 9.7, 0.5), sc * CFrame.new(p[1], 4.85, p[2]), C.post, PAINT)
		end
		local glassOpts = { transparency = 0.62, shadow = false }
		part(hall, "Glass", Vector3.new(4.4, 8.9, 0.12), sc * CFrame.new(0, 5.2, -2.45), C.glass, M.Glass, glassOpts)
		part(hall, "Glass", Vector3.new(0.12, 8.9, 4.4), sc * CFrame.new(-2.45, 5.2, 0), C.glass, M.Glass, glassOpts)
		part(hall, "Glass", Vector3.new(0.12, 8.9, 4.4), sc * CFrame.new(2.45, 5.2, 0), C.glass, M.Glass, glassOpts)
		part(hall, "Header", Vector3.new(5.4, 0.5, 0.5), sc * CFrame.new(0, 9.95, -2.45), C.post, PAINT)
		part(hall, "Header", Vector3.new(5.4, 0.5, 0.5), sc * CFrame.new(0, 9.95, 2.45), C.post, PAINT)
		local strip = part(hall, "TopLight", Vector3.new(3.6, 0.1, 0.32), sc * CFrame.new(0, 9.65, -2.2), C.light, M.Neon,
			{ shadow = false })
		local light = Instance.new("SpotLight")
		light.Name = "CaseLight"
		light.Face = Enum.NormalId.Bottom
		light.Color = Color3.fromRGB(232, 240, 255)
		light.Brightness = 3.0
		light.Range = 12
		light.Angle = 100
		light.Shadows = false
		light.Enabled = false
		light.Parent = strip
		slot.strip = strip
		slot.light = light
		-- the pole, its copper bands and the white opening in the roof above it
		cylinder(hall, "Pole", ROOF_Y, 0.8, sc * CFrame.new(POLE_X, ROOF_Y / 2, POLE_Z), C.pole, STEEL)
		if not low then
			for _, y in ipairs({ 30, 60, 90 }) do
				cylinder(hall, "Band", 0.35, 1.0, sc * CFrame.new(POLE_X, y, POLE_Z), C.copper, STEEL)
			end
		end
		cylinder(hall, "Opening", 0.25, 5, sc * CFrame.new(POLE_X, ROOF_Y - 0.35, POLE_Z), C.light, M.Neon, { shadow = false })
		slots[k] = slot
		if k % 6 == 0 then
			task.wait()
		end
	end
	-- wall units (maroon, a white panel) between every other pair of cases
	for k = 1, N, 2 do
		local deg = (k - 1) * STEP + STEP / 2
		local uc = facing(deg, R_CASE + 0.5, 0)
		local unit = part(hall, "WallUnit", Vector3.new(2.6, 7.2, 1.6), uc * CFrame.new(0, 3.6, 0), C.unit, PAINT)
		local panel = part(hall, "WallUnitPanel", Vector3.new(1.7, 0.75, 0.1), uc * CFrame.new(0, 6.1, -0.82), C.light, M.Neon,
			{ shadow = false })
		table.insert(slots[k].units, unit)
		table.insert(slots[k].units, panel)
		local nextSlot = slots[k % N + 1]
		table.insert(nextSlot.units, unit)
		table.insert(nextSlot.units, panel)
	end
	task.wait()

	-- the wall: dark panels and columns, white light bars, a girt
	for k = 1, N do
		local deg = (k - 1) * STEP + STEP / 2
		local width = 2 * (R_WALL + 1) * math.tan(math.rad(STEP / 2)) + 0.4
		local pc = facing(deg, R_WALL + 1, ROOF_Y / 2)
		part(hall, "WallPanel", Vector3.new(width, ROOF_Y + 2, 2), pc, C.shell, PANEL)
		local cc = facing((k - 1) * STEP, R_WALL - 0.2, ROOF_Y / 2)
		part(hall, "Column", Vector3.new(2.6, ROOF_Y + 2, 2.6), cc, C.truss, PAINT)
		-- one tall light bar per bay, high and low in turn (the film's lit wall, not a curtain of dashes)
		local barY = if k % 2 == 0 then 64 else 86
		part(hall, "WallBar", Vector3.new(0.7, 13, 0.3), facing(deg, R_WALL - 0.1, barY), C.light, M.Neon, { shadow = false })
		if high then
			part(hall, "Girt", Vector3.new(width, 1.1, 1.1), facing(deg, R_WALL - 0.45, 40), C.truss, PAINT)
		end
	end
	task.wait()

	-- the ceiling: the roof deck, the spoked ring and its hub of spots, radial rows of light bars, purlins
	cylinder(hall, "RoofDeck", 2, 2 * (R_WALL + 3), O * CFrame.new(0, ROOF_Y + 1, 0), C.shell, PANEL)
	for k = 1, N do
		local a, b = polar((k - 1) * STEP, 92, CROWN_Y), polar(k * STEP, 92, CROWN_Y)
		local dir = (b - a).Unit
		beam(hall, "CrownRing", a - dir * 0.3, b + dir * 0.3, 2.2, 2.2, C.truss, PAINT)
	end
	for k = 1, 12 do
		local a, b = polar((k - 1) * 30, 36, CROWN_Y), polar(k * 30, 36, CROWN_Y)
		local dir = (b - a).Unit
		beam(hall, "CrownInner", a - dir * 0.2, b + dir * 0.2, 1.6, 1.6, C.truss, PAINT)
	end
	for j = 1, 48 do
		local deg = (j - 1) * 7.5
		beam(hall, "Spoke", polar(deg, 17, CROWN_Y), polar(deg, 92, CROWN_Y), 0.9, 0.9, C.truss, PAINT)
	end
	cylinder(hall, "Hub", 5, 34, O * CFrame.new(0, CROWN_Y - 0.5, 0), C.housing, PAINT)
	for j = 1, 12 do
		local r = if j % 2 == 0 then 7.5 else 13
		local p = polar(j * 30, r, CROWN_Y - 3.15)
		cylinder(hall, "Spot", 0.3, 3.0, CFrame.new(p), C.lens, M.Neon, { shadow = false })
	end
	local rows = if low then { 102, 114 } else { 100, 108, 116 }
	for k = 1, N do
		local deg = (k - 1) * STEP + STEP / 2
		for _, r in ipairs(rows) do
			beam(hall, "CeilingBar", polar(deg, r - 3, ROOF_Y - 0.3), polar(deg, r + 3, ROOF_Y - 0.3), 0.55, 0.25, C.light, M.Neon,
				{ shadow = false })
		end
		if high then
			local pdeg = (k - 1) * STEP + STEP / 4
			beam(hall, "Purlin", polar(pdeg, 20, ROOF_Y - 0.6), polar(pdeg, R_WALL - 1, ROOF_Y - 0.6), 1.2, 1.2, C.truss, PAINT)
		end
	end
	task.wait()

	-- Your ride (first person, 20 Nov): built once at the hall's origin in case space and moved onto your own case
	-- (set.hall.ride:PivotTo(slot.cf)). The case's four posts run on up as guide rails to the roof, with small lamps on
	-- their inner faces that stream past as you climb, square collars every 24 studs that you pass through, and a
	-- square shaft in the roof (the tube) whose top is a bright panel: the light you rise into.
	local ride = folder(hall, "Ride")
	local rideCF = O * CFrame.new(0, 0, 0)
	local RAIL_R = 2.45 -- the case posts' corners
	local SHAFT_A = 3.7 -- the shaft's half width (the rails run up inside it)
	local SHAFT_Y = 108
	local lampStep = if low then 12 elseif high then 6 else 8
	for _, p in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local x, z = p[1] * RAIL_R, p[2] * RAIL_R
		part(ride, "Rail", Vector3.new(0.2, ROOF_Y - 9.7, 0.2), rideCF * CFrame.new(x, (9.7 + ROOF_Y) / 2, z), C.pole, PAINT,
			{ shadow = false })
		-- lamps on the inner corner, toward you
		local y = 12
		while y < SHAFT_Y + 12 do
			part(ride, "RailLamp", Vector3.new(0.1, 0.45, 0.1), rideCF * CFrame.new(x - p[1] * 0.15, y, z - p[2] * 0.15), C.light,
				M.Neon, { shadow = false })
			y += lampStep
		end
	end
	for _, y in ipairs({ 34, 58, 82 }) do
		for _, s in ipairs({ { -1, -1, 1, -1 }, { -1, 1, 1, 1 }, { -1, -1, -1, 1 }, { 1, -1, 1, 1 } }) do
			beam(ride, "Collar", (rideCF * CFrame.new(s[1] * RAIL_R, y, s[2] * RAIL_R)).Position,
				(rideCF * CFrame.new(s[3] * RAIL_R, y, s[4] * RAIL_R)).Position, 0.3, 0.3, C.truss, PAINT, { shadow = false })
		end
		-- a thin light strip under each collar's front bar (the one you face), so each one flashes past
		beam(ride, "CollarLight", (rideCF * CFrame.new(-RAIL_R + 0.4, y - 0.2, -RAIL_R + 0.05)).Position,
			(rideCF * CFrame.new(RAIL_R - 0.4, y - 0.2, -RAIL_R + 0.05)).Position, 0.12, 0.08, C.light, M.Neon, { shadow = false })
	end
	-- the shaft: four dark walls from SHAFT_Y up into the roof deck, a lit band at its mouth, the bright top
	local shaftH = ROOF_Y + 0.8 - SHAFT_Y
	for _, w in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		local size = if w[1] == 0 then Vector3.new(2 * SHAFT_A + 0.6, shaftH, 0.3) else Vector3.new(0.3, shaftH, 2 * SHAFT_A + 0.6)
		part(ride, "ShaftWall", size, rideCF * CFrame.new(w[1] * (SHAFT_A + 0.15), SHAFT_Y + shaftH / 2, w[2] * (SHAFT_A + 0.15)),
			C.shell, PANEL, { shadow = false })
		local band = if w[1] == 0 then Vector3.new(2 * SHAFT_A, 0.25, 0.08) else Vector3.new(0.08, 0.25, 2 * SHAFT_A)
		part(ride, "ShaftBand", band, rideCF * CFrame.new(w[1] * (SHAFT_A - 0.02), SHAFT_Y + 0.3, w[2] * (SHAFT_A - 0.02)),
			C.light, M.Neon, { shadow = false })
		if not low then
			part(ride, "ShaftBand", band, rideCF * CFrame.new(w[1] * (SHAFT_A - 0.02), SHAFT_Y + 8, w[2] * (SHAFT_A - 0.02)),
				C.light, M.Neon, { shadow = false })
		end
	end
	part(ride, "ShaftTop", Vector3.new(2 * SHAFT_A, 0.2, 2 * SHAFT_A), rideCF * CFrame.new(0, ROOF_Y - 0.4, 0), C.lens, M.Neon,
		{ shadow = false })
	ride.WorldPivot = rideCF

	-- lights: the hub, a key that rides up with your disc, a fill from the gantry over your case
	local hubAnchor = anchor(hall, "HubLight", O * CFrame.new(0, CROWN_Y - 6, 0))
	local hub = Instance.new("PointLight")
	hub.Name = "Hub"
	hub.Color = Color3.fromRGB(228, 236, 255)
	hub.Brightness = 3.0
	hub.Range = 95
	hub.Shadows = false
	hub.Enabled = false
	hub.Parent = hubAnchor
	local riderAnchor = anchor(hall, "RiderKey", O * CFrame.new(0, 10, 0))
	local rider = Instance.new("SpotLight")
	rider.Name = "Key"
	rider.Face = Enum.NormalId.Front
	rider.Color = Color3.fromRGB(226, 234, 255)
	rider.Brightness = 2.8
	rider.Range = 22
	rider.Angle = 70
	rider.Shadows = not low
	rider.Enabled = false
	rider.Parent = riderAnchor
	-- (a soft all-round fill with it, so the circling camera never sees a black silhouette)
	local riderFill = Instance.new("PointLight")
	riderFill.Name = "Fill"
	riderFill.Color = Color3.fromRGB(200, 214, 255)
	riderFill.Brightness = 0.9
	riderFill.Range = 12
	riderFill.Shadows = false
	riderFill.Enabled = false
	riderFill.Parent = riderAnchor
	local gantryAnchor = part(hall, "GantryFill", Vector3.new(8, 0.2, 2), O * CFrame.new(0, 12.9, 0), C.housing,
		M.SmoothPlastic, { transparency = 1, shadow = false })
	local gantry = Instance.new("SurfaceLight")
	gantry.Name = "Fill"
	gantry.Face = Enum.NormalId.Bottom
	gantry.Color = Color3.fromRGB(214, 228, 255)
	gantry.Brightness = 2.2
	gantry.Range = 16
	gantry.Angle = 110
	gantry.Shadows = false
	gantry.Enabled = false
	gantry.Parent = gantryAnchor

	return {
		origin = O,
		model = hall,
		slots = slots,
		slotRadius = R_CASE,
		poleOffset = Vector3.new(POLE_X, 0, POLE_Z),
		poleTop = ROOF_Y,
		crownY = CROWN_Y,
		riderAnchor = riderAnchor,
		gantryAnchor = gantryAnchor,
		ride = ride,
		shaftY = SHAFT_Y,
		lights = { hub = hub, rider = rider, riderFill = riderFill, gantry = gantry },
	}
end

function Set.build(opts: { [string]: any }?): { [string]: any }
	local o = opts or {}
	local detail = if o.detail == "Low" or o.detail == "Medium" then o.detail else "High"
	count = 0
	local model = Instance.new("Model")
	model.Name = "LaunchSet"
	local red = buildRed(model, detail)
	task.wait()
	local hall = buildHall(model, detail, tonumber(o.slots) or 24)
	return { model = model, red = red, hall = hall, parts = count, detail = detail }
end

return Set
