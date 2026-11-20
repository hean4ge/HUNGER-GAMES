--[[
	SlidePhysics - the physics of a voluntary slide (crouch while running), shared by the client
	(MovementController drives the local slide with it) and the server (MovementService checks speeds against it).

	The owner: "the steeper the hill and higher momentum u are running the longer you slide".
	So a slide is a body sliding on the ground, not a timed move:
	  - Entry: your current run speed, plus a small drop kick (a jog slides short, a sprint long, a downhill run
	    longer still). The kick never takes you above SprintSpeed * 1.15, so slide-jump-slide cannot build speed.
	  - Gravity along the slope: G * sin(slope) towards downhill. Steeper ground accelerates you more; sliding
	    uphill gravity and friction both brake you, so an uphill slide stops fast. Sliding across a slope curves
	    you downhill.
	  - Friction: mu(material) * G * cos(slope) against the motion, plus BodyDrag * speed. Snow, mud and ice are
	    slippery, sand and rock grab (Friction table below).
	  - A soft speed cap (drag grows above SoftCap, terminal speed ~34 on the steepest walkable ground) and a hard
	    cap the server trusts.
	  - Steering: lateral grip turns you (faster when slow), and each turn scrubs a little speed.
	  - It ends when the speed drops below EndSpeed, when you stand (release crouch / jump), on hitting something,
	    after AirGrace in the air, or at MaxTime (a safety net, not a design limit).
	Units: studs and seconds. An R15 contender is ~5.2 studs tall, so 1 stud ~ 0.33 m and 1 g ~ 30 studs/s^2.
	Speeds are horizontal (MovementController commands horizontal velocity through Humanoid:Move).

	API
	  SlidePhysics.C                                    constants (below)
	  SlidePhysics.friction(material: Enum.Material) -> mu
	  SlidePhysics.entrySpeed(runSpeed, sprintSpeed) -> studs/s at the start of a slide
	  SlidePhysics.step(v, fallbackDir, normal, mu, grip, wishDir, dt, grounded) -> Vector3 (new horizontal velocity)
	  SlidePhysics.simulate(entrySpeed, slopeDeg, material?, dt?) -> { time, distance, peak, endSpeed }
	      a straight slide on a constant slope (+ downhill, - uphill), crouch held: for tests and tuning
	  SlidePhysics.serverSpeedLimit(sprintSpeed) -> the most horizontal speed a legitimate contender can hold
]]
local SlidePhysics = {}

local C = {
	G = 30, -- studs/s^2 (1 g at character scale)
	MinEntrySpeed = 12, -- a jog (13) slides; a walk crouches
	EntryKick = 1.08, -- dropping into the slide turns a little height into speed...
	EntryKickAdd = 1, -- ...(studs/s)...
	KickCeiling = 1.15, -- ...but never above SprintSpeed x this
	EndSpeed = 5, -- below this the slide is over (you are back on your feet, or crouching if crouch is held)
	BodyDrag = 0.3, -- 1/s: drag proportional to speed (clothes ploughing the ground). Terminal speed on a slope
	-- steeper than atan(mu) is G * (sin - mu * cos) / BodyDrag: ~14 on 30-degree grass, so steep slides carry on
	SoftCap = 30, -- above this, drag grows with the square of the excess...
	Drag = 0.8, -- ...(studs/s^2 per (studs/s)^2): terminal ~34 on the steepest walkable ground
	HardCap = 36, -- never faster (the server trusts this)
	SteerAccel = 16, -- lateral grip while sliding (studs/s^2 at grip 1): turn rate = this / speed...
	SteerMaxRate = 1.8, -- ...up to this (rad/s)
	SteerScrub = 0.25, -- each radian of turn costs this fraction of the speed
	AirDrag = 0.4, -- studs/s^2 while airborne (momentum is kept over a crest)
	AirGrace = 0.35, -- seconds in the air before the slide ends (small crests keep it)
	MinTime = 0.3, -- releasing crouch ends the slide only after this long (a tap still gives a short slide)
	MaxTime = 12, -- safety net
	Cooldown = 0.6, -- between slides
	NormalSmoothing = 10, -- 1/s: the slope under you is smoothed (faceted terrain normals are noisy)
}
SlidePhysics.C = C

-- Sliding friction coefficient per material (clothes and boots on the surface). Anything else: Default.
local FRICTION = {
	Grass = 0.42,
	LeafyGrass = 0.5, -- undergrowth catches you
	Ground = 0.46,
	Mud = 0.3,
	Sand = 0.62, -- you dig in
	Snow = 0.2,
	Glacier = 0.08,
	Ice = 0.06,
	Salt = 0.45,
	Pebble = 0.5,
	Rock = 0.52,
	Slate = 0.5,
	Basalt = 0.52,
	Granite = 0.5,
	Limestone = 0.5,
	Sandstone = 0.52,
	CrackedLava = 0.55,
	Cobblestone = 0.5,
	Asphalt = 0.55,
	Concrete = 0.52,
	Brick = 0.52,
	Wood = 0.38,
	WoodPlanks = 0.38,
	Fabric = 0.5,
	SmoothPlastic = 0.3,
	Plastic = 0.34,
	Metal = 0.3,
	DiamondPlate = 0.35,
	Marble = 0.3,
	Glass = 0.25,
	Foil = 0.3,
}
local DEFAULT_MU = 0.46
SlidePhysics.Friction = FRICTION

function SlidePhysics.friction(material: Enum.Material?): number
	if typeof(material) ~= "EnumItem" then
		return DEFAULT_MU
	end
	return FRICTION[material.Name] or DEFAULT_MU
end

function SlidePhysics.entrySpeed(runSpeed: number, sprintSpeed: number): number
	local s = math.max(0, runSpeed)
	local kicked = s * C.EntryKick + C.EntryKickAdd
	return math.min(C.HardCap, math.min(kicked, math.max(s, sprintSpeed * C.KickCeiling)))
end

-- One step. v: horizontal velocity; normal: the (smoothed) ground normal; mu: friction; grip: steering grip (0..1.5).
function SlidePhysics.step(v: Vector3, fallbackDir: Vector3, normal: Vector3, mu: number, grip: number,
	wishDir: Vector3, dt: number, grounded: boolean): Vector3
	local s = v.Magnitude
	local dir = if s > 0.01 then v / s else fallbackDir
	-- steering: lateral grip turns the slide; tighter when slow, and every turn scrubs speed
	if grounded and wishDir.Magnitude > 0.01 then
		local angle = math.acos(math.clamp(dir:Dot(wishDir), -1, 1))
		if angle > 1e-3 and angle < 2.2 then
			local rate = math.min(C.SteerMaxRate, C.SteerAccel * math.clamp(grip, 0.2, 1.2) / math.max(s, 4))
			local turn = math.min(angle, rate * dt)
			local sign = if dir:Cross(wishDir).Y >= 0 then 1 else -1
			dir = CFrame.fromAxisAngle(Vector3.yAxis, sign * turn):VectorToWorldSpace(dir)
			s *= math.max(0, 1 - C.SteerScrub * turn)
		end
	end
	local nv = dir * s
	if grounded then
		local cosT = math.clamp(normal.Y, 0, 1)
		local sinT = math.sqrt(math.max(0, 1 - cosT * cosT))
		local downhill = Vector3.new(normal.X, 0, normal.Z)
		if sinT > 1e-3 and downhill.Magnitude > 1e-4 then
			nv += downhill.Unit * (C.G * sinT * dt) -- gravity along the slope
		end
		local ns = nv.Magnitude
		if ns > 1e-4 then
			-- sliding friction, plus a drag that grows with speed (clothes ploughing the ground)
			local slow = mu * C.G * cosT + C.BodyDrag * ns
			if ns > C.SoftCap then
				local over = ns - C.SoftCap
				slow += C.Drag * over * over
			end
			nv = nv * (math.max(0, ns - slow * dt) / ns)
		end
	else
		local ns = nv.Magnitude
		if ns > 1e-4 then
			nv = nv * (math.max(0, ns - C.AirDrag * dt) / ns)
		end
	end
	local ns = nv.Magnitude
	if ns > C.HardCap then
		nv = nv * (C.HardCap / ns)
	end
	return nv
end

-- A straight slide on a constant slope (degrees; + downhill, - uphill), crouch held, until it stops or MaxTime.
function SlidePhysics.simulate(entrySpeed: number, slopeDeg: number, material: Enum.Material?, dt: number?)
	local h = dt or 1 / 60
	local a = math.rad(math.abs(slopeDeg))
	-- travel along -Z; the slope falls towards -Z when downhill
	local nz = if slopeDeg >= 0 then -math.sin(a) else math.sin(a)
	local normal = Vector3.new(0, math.cos(a), nz)
	local mu = SlidePhysics.friction(material or Enum.Material.Grass)
	local fwd = Vector3.new(0, 0, -1)
	local v = fwd * entrySpeed
	local t, dist, peak = 0, 0, entrySpeed
	while t < C.MaxTime do
		v = SlidePhysics.step(v, fwd, normal, mu, 1, Vector3.zero, h, true)
		t += h
		dist += v.Magnitude * h
		peak = math.max(peak, v.Magnitude)
		if v.Magnitude < C.EndSpeed then
			break
		end
	end
	return { time = t, distance = dist, peak = peak, endSpeed = v.Magnitude }
end

-- The fastest horizontal speed a legitimate contender holds for more than a moment: a slide's hard cap, or a
-- Sprint Burst (x1.25) down a hill (x1.2), whichever is higher.
function SlidePhysics.serverSpeedLimit(sprintSpeed: number): number
	return math.max(C.HardCap, sprintSpeed * 1.25 * 1.2)
end

return SlidePhysics
