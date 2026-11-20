--[[
	CosmeticFx - the nine kill effects (CardMenusAndShop 3.1), drawn on a client at the defeated player's position.
	Clean only: light, petals, leaves, paper, feathers, dust, a bell, a flag, frost. No blood, nothing red sprayed, no
	body pieces; every effect is over in about 1.5 s. Matte parts (SmoothPlastic, no Neon), local to this client
	(nothing replicates), never collide, never cast shadows, never queried by a ray.

	Stand-ins: each piece is a small Part moved by one Heartbeat loop per effect. When the SeasonOne props ship
	(CosmeticLooks.Models: "bell_toll" -> a bell Model, "flag_drop" -> a pennant Model in ReplicatedStorage.Assets
	.SeasonOne), they are cloned in place of the part-built bell and pennant.

	Budget by detail tier (LocalPlayer attribute DetailTier, DetailController): High all pieces, Medium 60%, Low 30%
	and no light. At most MAX_LIVE effects at once on a client (the oldest ends early).

	API (client)
	  CosmeticFx.play(effectId, position, opts?) -> number?   seconds it runs (nil: unknown id)
	      opts: { tier = "High" | "Medium" | "Low"?, parent = Instance?, sound = boolean? (default true) }
	      position: the defeated player's root (about 3 studs above the ground)
	  CosmeticFx.stopAll()
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CosmeticLooks = require(script.Parent:WaitForChild("CosmeticLooks"))

local CosmeticFx = {}

local MAX_LIVE = 4
local TIER_SCALE = { High = 1, Medium = 0.6, Low = 0.3 }

local V3 = Vector3.new
local rad = math.rad
local rng = Random.new()

local live: { any } = {}

local function rand(a: number, b: number): number
	return a + rng:NextNumber() * (b - a)
end

local function pick(list: { string }): Color3
	return Color3.fromHex(list[rng:NextInteger(1, #list)])
end

local function part(parent: Instance, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function groundBelow(pos: Vector3, folder: Instance): Vector3
	local params = RaycastParams.new()
	local ignore = { folder }
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			table.insert(ignore, plr.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(pos + V3(0, 1, 0), V3(0, -12, 0), params)
	return if hit then hit.Position else pos - V3(0, 3, 0)
end

-- A "bit": a part with a simple motion. pos(t) = p0 + v*t + 0.5*a*t^2 (+ an optional custom path), spin by w, a fade
-- over the last `fade` of its life, an optional grow.
type Bit = { p: Part, p0: Vector3, v: Vector3, a: Vector3, w: Vector3, r0: CFrame, t0: number, life: number,
	fade: number, base: number, size0: Vector3?, grow: number?, path: ((number) -> Vector3)? }

local function bit(fx: any, p: Part, opts: { [string]: any }): Bit
	local b: Bit = {
		p = p,
		p0 = opts.p0,
		v = opts.v or Vector3.zero,
		a = opts.a or Vector3.zero,
		w = opts.w or Vector3.zero,
		r0 = opts.r0 or CFrame.Angles(rand(0, 6.28), rand(0, 6.28), rand(0, 6.28)),
		t0 = opts.t0 or 0,
		life = opts.life or 1.2,
		fade = opts.fade or 0.35,
		base = opts.base or 0,
		size0 = if opts.grow then p.Size else nil,
		grow = opts.grow,
		path = opts.path,
	}
	p.Transparency = 1
	table.insert(fx.bits, b)
	return b
end

local function stepBit(b: Bit, t: number): boolean
	local lt = t - b.t0
	if lt < 0 then
		b.p.Transparency = 1
		return true
	end
	if lt >= b.life then
		b.p.Transparency = 1
		return false
	end
	local pos = if b.path then b.path(lt) else b.p0 + b.v * lt + b.a * (0.5 * lt * lt)
	b.p.CFrame = CFrame.new(pos) * b.r0 * CFrame.Angles(b.w.X * lt, b.w.Y * lt, b.w.Z * lt)
	local k = lt / b.life
	local fadeStart = 1 - b.fade
	local tr = b.base
	if k > fadeStart then
		tr = b.base + (1 - b.base) * ((k - fadeStart) / b.fade)
	elseif lt < 0.08 then
		tr = b.base + (1 - b.base) * (1 - lt / 0.08)
	end
	b.p.Transparency = tr
	if b.grow and b.size0 then
		b.p.Size = b.size0 * (1 + b.grow * k)
	end
	return true
end

local function countFor(n: number, scale: number): number
	return math.max(1, math.floor(n * scale + 0.5))
end

local function prop(id: string): Model?
	local name = CosmeticLooks.Models[id]
	if not name then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("SeasonOne")
	local m = folder and folder:FindFirstChild(name)
	return if m and m:IsA("Model") then m:Clone() else nil
end

local function playSound(pos: Vector3, pitch: number, volume: number)
	local ok, Sfx = pcall(function()
		return require(script.Parent:WaitForChild("Sfx", 1) :: ModuleScript)
	end)
	if ok and Sfx and Sfx.play then
		pcall(Sfx.play, "FeastBell", { position = pos, pitch = pitch, volume = volume })
	end
end

-- The builders: build(fx, pos, ground, scale, opts) fills fx.bits (and fx.step for anything custom); returns duration.
local BUILD: { [string]: (any, Vector3, Vector3, number, any) -> number } = {}

BUILD.ash = function(fx, pos, ground, scale)
	local wind = V3(rand(-1, 1), 0, rand(-1, 1)).Unit * 2.4
	for _ = 1, countFor(40, scale) do
		local s = rand(0.14, 0.32)
		local p = part(fx.folder, V3(s, s, s), pick({ "8A8680", "A8A49C", "C8C4BC", "DAD6CE" }))
		local h = rand(-2.6, 2.4)
		bit(fx, p, {
			p0 = pos + V3(rand(-0.9, 0.9), h, rand(-0.6, 0.6)),
			v = wind * rand(0.5, 1.3) + V3(0, rand(0.8, 2.6), 0),
			a = wind * 0.6 + V3(0, -0.3, 0),
			w = V3(rand(-4, 4), rand(-4, 4), rand(-4, 4)),
			t0 = (h + 2.6) * 0.05, -- greys from the feet up
			life = rand(0.9, 1.35),
			fade = 0.5,
			base = 0.1,
		})
	end
	return 1.6
end

BUILD.petals = function(fx, pos, ground, scale)
	for _ = 1, countFor(32, scale) do
		local p = part(fx.folder, V3(0.34, 0.04, 0.24), pick({ "F2EBDD", "EEDFD2", "F6EEE6", "E6D6C4" }))
		local a0 = rand(0, 6.28)
		local r = rand(1.2, 2.6)
		local h0 = rand(3.5, 6)
		local spin = rand(1.6, 2.6)
		local fall = rand(2.6, 3.6)
		local top = pos + V3(0, 0, 0)
		bit(fx, p, {
			p0 = top,
			path = function(t)
				local ang = a0 + spin * t
				return top + V3(math.cos(ang) * r, h0 - fall * t, math.sin(ang) * r)
			end,
			w = V3(rand(-3, 3), rand(-2, 2), rand(-3, 3)),
			t0 = rand(0, 0.25),
			life = rand(1.1, 1.3),
			fade = 0.3,
		})
	end
	return 1.6
end

BUILD.leaves = function(fx, pos, ground, scale)
	for _ = 1, countFor(30, scale) do
		local p = part(fx.folder, V3(0.42, 0.04, 0.28), pick({ "B8642E", "C88A3A", "8E4A24", "D0A048", "A0702E" }))
		local a0 = rand(0, 6.28)
		local r0 = rand(0.8, 1.6)
		local base = ground + V3(0, 0.3, 0)
		local rise = rand(3.6, 5.2)
		bit(fx, p, {
			p0 = base,
			path = function(t)
				local ang = a0 + 5.5 * t
				local r = r0 + 1.6 * t
				return base + V3(math.cos(ang) * r, rise * t, math.sin(ang) * r)
			end,
			w = V3(rand(-6, 6), rand(-6, 6), rand(-6, 6)),
			t0 = rand(0, 0.2),
			life = rand(1.1, 1.3),
			fade = 0.35,
		})
	end
	return 1.55
end

BUILD.confetti = function(fx, pos, ground, scale)
	for _ = 1, countFor(54, scale) do
		local p = part(fx.folder, V3(0.24, 0.02, 0.15), pick({ "E8DFC8", "4E6A8A", "C9A24E", "6E9E8E", "D8CDB4" }))
		local dir = V3(rand(-1, 1), rand(0.6, 1.4), rand(-1, 1)).Unit
		bit(fx, p, {
			p0 = pos + V3(0, 2.6, 0),
			v = dir * rand(7, 11),
			a = V3(0, -13, 0) - dir * 7,
			w = V3(rand(-12, 12), rand(-8, 8), rand(-12, 12)),
			life = rand(1.1, 1.4),
			fade = 0.3,
		})
	end
	return 1.5
end

BUILD.feathers = function(fx, pos, ground, scale)
	for _ = 1, countFor(24, scale) do
		local p = part(fx.folder, V3(0.5, 0.03, 0.15), pick({ "F2F0EC", "D6D4D0", "B8B6B2", "E6E4E0" }))
		local dir = V3(rand(-1, 1), rand(-0.2, 1), rand(-1, 1)).Unit
		local v0 = dir * rand(3, 5)
		local start = pos + V3(0, 0.6, 0)
		local phase = rand(0, 6.28)
		bit(fx, p, {
			p0 = start,
			path = function(t)
				local burst = v0 * (1 - math.exp(-4 * t)) / 4 * 4
				return start + burst * 0.6 + V3(math.sin(phase + t * 5) * 0.4, -1.2 * t * t, math.cos(phase + t * 4) * 0.3)
			end,
			w = V3(rand(-2, 2), rand(-3, 3), rand(-2, 2)),
			life = rand(1.2, 1.45),
			fade = 0.35,
		})
	end
	return 1.5
end

local function dustRing(fx, ground: Vector3, n: number, speed: number, color: { string })
	for i = 1, n do
		local ang = (i / n) * math.pi * 2 + rand(-0.1, 0.1)
		local dir = V3(math.cos(ang), 0, math.sin(ang))
		local s = rand(0.3, 0.48)
		local p = part(fx.folder, V3(s, s * 0.7, s), pick(color), Enum.PartType.Ball)
		bit(fx, p, {
			p0 = ground + V3(0, 0.2, 0) + dir * 0.8,
			v = dir * speed * rand(0.85, 1.15) + V3(0, 0.4, 0),
			a = -dir * speed * 0.9,
			t0 = 0.12,
			life = 1.05,
			fade = 0.6,
			base = 0.55,
			grow = 1.3,
			r0 = CFrame.identity,
		})
	end
end

BUILD.bell = function(fx, pos, ground, scale, opts)
	local top = pos + V3(0, 4.2, 0)
	local bell = prop("bell_toll")
	local parts: { BasePart } = {}
	if bell then
		bell.Parent = fx.folder
		for _, d in ipairs(bell:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
			end
		end
		fx.step = function(t)
			local swing = math.sin(t * 9) * rad(18) * math.exp(-1.6 * t)
			bell:PivotTo(CFrame.new(top) * CFrame.Angles(0, 0, swing))
		end
	else
		local brass, dark = Color3.fromHex("B08A4E"), Color3.fromHex("6A5230")
		local body = part(fx.folder, V3(1.1, 1.3, 1.3), brass, Enum.PartType.Cylinder)
		local lip = part(fx.folder, V3(0.18, 1.6, 1.6), brass, Enum.PartType.Cylinder)
		local crown = part(fx.folder, V3(0.8, 0.8, 0.8), brass, Enum.PartType.Ball)
		local loop = part(fx.folder, V3(0.12, 0.42, 0.42), dark, Enum.PartType.Cylinder)
		local clapper = part(fx.folder, V3(0.32, 0.32, 0.32), dark, Enum.PartType.Ball)
		parts = { body, lip, crown, loop, clapper }
		-- offsets in the bell's frame (it hangs from its loop at the top)
		local OFF = {
			CFrame.new(0, -0.75, 0) * CFrame.Angles(0, 0, rad(90)),
			CFrame.new(0, -1.42, 0) * CFrame.Angles(0, 0, rad(90)),
			CFrame.new(0, -0.15, 0),
			CFrame.new(0, 0.2, 0) * CFrame.Angles(0, rad(90), 0),
			CFrame.new(0, -1.55, 0),
		}
		for _, p in ipairs(parts) do
			p.Transparency = 1
		end
		fx.step = function(t)
			local swing = math.sin(t * 9) * rad(18) * math.exp(-1.6 * t)
			local drop = math.max(0, 1 - t / 0.18) * 1.5
			local frame = CFrame.new(top + V3(0, drop, 0)) * CFrame.Angles(0, 0, swing)
			local tr = if t < 0.12 then 1 - t / 0.12 elseif t > 1.15 then math.min(1, (t - 1.15) / 0.35) else 0
			for i, p in ipairs(parts) do
				p.CFrame = frame * OFF[i]
				p.Transparency = tr
			end
		end
	end
	dustRing(fx, ground, countFor(24, scale), 5.5, { "C8BCA4", "B8AC94", "D6CCB6" })
	if opts.sound ~= false then
		playSound(top, 0.85, 0.35)
	end
	return 1.55
end

BUILD.flag = function(fx, pos, ground, scale, opts)
	local cam = workspace.CurrentCamera
	local right = if cam then cam.CFrame.RightVector * V3(1, 0, 1) else V3(1, 0, 0)
	right = if right.Magnitude > 0.01 then right.Unit else V3(1, 0, 0)
	local base = ground + right * 2
	local pole = part(fx.folder, V3(4.6, 0.14, 0.14), Color3.fromHex("6A4E38"), Enum.PartType.Cylinder)
	local cap = part(fx.folder, V3(0.28, 0.28, 0.28), Color3.fromHex("B08A4E"), Enum.PartType.Ball)
	local cloth = part(fx.folder, V3(0.04, 0.95, 1.7), Color3.fromHex("4E6A8A"))
	local stripe = part(fx.folder, V3(0.05, 0.22, 1.7), Color3.fromHex("E8DFC8"))
	local look = CFrame.lookAt(Vector3.zero, right)
	fx.step = function(t)
		local drop = math.max(0, 1 - t / 0.2) * 5
		local root = CFrame.new(base + V3(0, drop, 0)) * look
		pole.CFrame = root * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, rad(90))
		cap.CFrame = root * CFrame.new(0, 4.65, 0)
		local fold = if t > 1.05 then math.clamp((t - 1.05) / 0.35, 0, 1) else 0
		local len = 1.7 * (1 - fold) + 0.05
		local wave = math.sin(t * 11) * rad(14)
		local hinge = root * CFrame.new(0, 4.05, 0) * CFrame.Angles(0, wave, 0)
		cloth.Size = V3(0.04, 0.95, len)
		stripe.Size = V3(0.05, 0.22, len)
		cloth.CFrame = hinge * CFrame.new(0, 0, len / 2 + 0.07)
		stripe.CFrame = hinge * CFrame.new(0.01, 0, len / 2 + 0.07)
		local tr = if t < 0.06 then 1 - t / 0.06 elseif t > 1.3 then math.min(1, (t - 1.3) / 0.2) else 0
		for _, p in ipairs({ pole, cap, cloth, stripe }) do
			p.Transparency = tr
		end
	end
	dustRing(fx, base, countFor(10, scale), 3, { "C8BCA4", "B8AC94" })
	return 1.5
end

BUILD.frost = function(fx, pos, ground, scale)
	-- frost climbs from the feet (pale crystals round the figure), then breaks into snowflakes
	for i = 1, countFor(22, scale) do
		local h = (i / 22) * 5.2
		local ang = rand(0, 6.28)
		local s = rand(0.3, 0.55)
		local p = part(fx.folder, V3(s * 0.5, s, s * 0.5), pick({ "DCE8F0", "C8DAE6", "EEF4F8" }))
		bit(fx, p, {
			p0 = ground + V3(math.cos(ang) * 0.9, h + 0.2, math.sin(ang) * 0.9),
			r0 = CFrame.Angles(rand(-0.5, 0.5), ang, rand(-0.5, 0.5)),
			t0 = h * 0.09,
			life = 0.95 - h * 0.09 + 0.15,
			fade = 0.25,
			base = 0.15,
		})
	end
	for _ = 1, countFor(34, scale) do
		local p = part(fx.folder, V3(0.16, 0.16, 0.16), pick({ "FFFFFF", "EEF4F8", "DCE8F0" }), Enum.PartType.Ball)
		local start = ground + V3(rand(-0.9, 0.9), rand(0.5, 5), rand(-0.9, 0.9))
		local out = (start - ground) * V3(1, 0, 1)
		out = if out.Magnitude > 0.01 then out.Unit else V3(1, 0, 0)
		local phase = rand(0, 6.28)
		bit(fx, p, {
			p0 = start,
			path = function(t)
				return start + out * (1.6 * t) + V3(math.sin(phase + t * 6) * 0.25, 0.6 * t - 0.9 * t * t, 0)
			end,
			r0 = CFrame.identity,
			t0 = rand(0.55, 0.75),
			life = rand(0.75, 0.9),
			fade = 0.45,
		})
	end
	return 1.6
end

BUILD.beam = function(fx, pos, ground, scale, opts)
	local col = part(fx.folder, V3(80, 4.2, 4.2), Color3.fromHex("E8EEF4"), Enum.PartType.Cylinder)
	col.CFrame = CFrame.new(ground + V3(0, 40, 0)) * CFrame.Angles(0, 0, rad(90))
	local inner = part(fx.folder, V3(80, 1.6, 1.6), Color3.fromHex("F6F8FA"), Enum.PartType.Cylinder)
	inner.CFrame = col.CFrame
	local light: PointLight? = nil
	if opts.tier ~= "Low" then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromHex("E8EEF4")
		l.Range = 16
		l.Brightness = 0
		l.Shadows = false
		l.Parent = inner
		light = l
	end
	fx.step = function(t)
		local inK = math.clamp(t / 0.2, 0, 1)
		local outK = math.clamp((t - 0.9) / 0.6, 0, 1)
		local k = inK * (1 - outK)
		col.Transparency = 1 - 0.38 * k
		inner.Transparency = 1 - 0.55 * k
		local w = 4.2 * (0.6 + 0.4 * inK) * (1 - 0.5 * outK)
		col.Size = V3(80, w, w)
		if light then
			light.Brightness = 1.6 * k
		end
	end
	for _ = 1, countFor(22, scale) do
		local p = part(fx.folder, V3(0.18, 0.18, 0.18), Color3.fromHex("F4F6F8"), Enum.PartType.Ball)
		bit(fx, p, {
			p0 = ground + V3(rand(-1.4, 1.4), rand(0, 2), rand(-1.4, 1.4)),
			v = V3(0, rand(7, 12), 0),
			a = V3(0, 6, 0),
			r0 = CFrame.identity,
			t0 = rand(0.1, 0.5),
			life = rand(0.8, 1),
			fade = 0.5,
		})
	end
	if opts.sound ~= false then
		playSound(pos, 1.5, 0.22)
	end
	return 1.55
end

local function endFx(fx: any)
	if fx.conn then
		fx.conn:Disconnect()
		fx.conn = nil
	end
	if fx.folder then
		fx.folder:Destroy()
		fx.folder = nil
	end
	local i = table.find(live, fx)
	if i then
		table.remove(live, i)
	end
end

function CosmeticFx.play(effectId: any, position: Vector3, opts: { [string]: any }?): number?
	if not RunService:IsClient() or typeof(position) ~= "Vector3" then
		return nil
	end
	local item = CosmeticLooks.get(effectId)
	local build = item and item.kind == "effect" and BUILD[item.fx]
	if not build then
		return nil
	end
	local o = opts or {}
	local tier = o.tier
	if type(tier) ~= "string" then
		local lp = Players.LocalPlayer
		tier = lp and lp:GetAttribute("DetailTier")
	end
	tier = if TIER_SCALE[tier] then tier else "High"
	o.tier = tier
	while #live >= MAX_LIVE do
		endFx(live[1])
	end
	local folder = Instance.new("Folder")
	folder.Name = "KillFx_" .. item.id
	folder.Parent = o.parent or workspace
	local fx = { folder = folder, bits = {}, step = nil, id = item.id }
	table.insert(live, fx)
	local ground = groundBelow(position, folder)
	local duration = build(fx, position, ground, TIER_SCALE[tier], o)
	local started = os.clock()
	fx.conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		if fx.step then
			fx.step(t)
		end
		for _, b in ipairs(fx.bits) do
			stepBit(b, t)
		end
		if t >= duration then
			endFx(fx)
		end
	end)
	return duration
end

function CosmeticFx.stopAll()
	while #live > 0 do
		endFx(live[1])
	end
end

return CosmeticFx
