--[[
	ClipPlayer - plays the Combat v3 fight clips (Shared.FightClips, baked in Blender by
	art/blender/anim/fight/build_fight_clips.py) on characters and on the first-person viewmodel. Client only, no
	Animator, no asset ids, no uploads: a clip is joint Transforms as data, sampled every frame.

	Third person
	  A clip holds, per sample, the joint Transforms of the upper body (Waist, Neck, shoulders, elbows, wrists: legs keep
	  the locomotion, the pelvis turn is folded into the waist) or of the whole body (+ Root and legs: dodges, the kick,
	  lunging heavies, skills, knockdowns). Samples are Catmull-Rom interpolated (smooth at 60 fps from ~30 fps data).
	  * Blending: a clip fades in over blendIn (0.06 s; reactions 0.08) from whatever the body is doing, including the
	    clip before it (a chain flows: the new step fades in over the old one, which keeps playing underneath until it
	    is covered); it fades out over blendOut (0.15 s; reactions 0.25) after its last sample, holding that sample.
	  * Fitted to the server: opts.lead = seconds from now to the strike (the server's windup): the part before the hit
	    is stretched or squeezed so the hit sample lands exactly then; opts.total = the step's whole time (stars shorten
	    the recovery only): the part after the hit is fitted to it. lead 0 (announced at the strike) starts the clip two
	    samples before its hit. Rates are kept within 0.35 - 3.
	  * Additive clips (the upper-body flinches) are applied as their change from their first sample, on top of
	    whatever pose is there, so legs keep walking and an attack keeps its shape under a flinch.
	  * Hit-stop: ClipPlayer.hitStop(model, seconds) slows that model's clips to 8 % for that long (client-side only).
	  Two ways to apply it:
	  * Hooked (the intended path): CharacterVisuals calls ClipPlayer.claim(model) once and, in its pose pass,
	    ClipPlayer.sample(model, now, out, weights, adds) after its own poses: `out[joint]` is the clip's Transform for
	    that joint and `weights[joint]` how much of it (lerp the joint's final Transform toward it), `adds[joint]` an
	    additive delta to multiply on (Transform = add * Transform). Joints not written are left as they are.
	  * Standalone (test rigs, NPCs, and until the hook lands): a model not claimed is driven here on
	    RunService.PreSimulation after CharacterVisuals: base = the joint's Transform as it stands, written as
	    base:Lerp(clip, w) (additive: delta * base); when the last clip ends the joints get their base back.

	First person
	  The same move, as the right and left wrist frames in camera space (Poses.hand frames: thumb toward the item's
	  business end, knuckles toward its edge) and the two elbow poles, ending on the block viewmodel's own hold for that
	  weapon kind. ClipPlayer.playView(name, opts) -> view track; ClipPlayer.sampleView(track, now, holdRight,
	  holdLeft) -> right, left, poleRight?, poleLeft?, weight (blended in from the holds given and back out to them).
	  Same timing fit (lead / total) and hit-stop (ClipPlayer.hitStopView(seconds)).

	API
	  ClipPlayer.has(name) -> boolean
	  ClipPlayer.info(name) -> { len, hit, mask, loop, additive, item, kind, markers, family }?
	  ClipPlayer.play(model, name, opts?) -> track?
	      opts: lead, total, speed, blendIn, blendOut, loop (override), mask ("upper" | "full"), startAt (clip seconds),
	            onMarker(name), onEnd(), weight (0..1 overall)
	  ClipPlayer.stop(model, fade?)          fades every clip on that model out over `fade` (default 0.12)
	  ClipPlayer.stopTrack(track, fade?)
	  ClipPlayer.playing(model) -> track?    the newest non-additive track still playing
	  ClipPlayer.hitStop(model, seconds)
	  ClipPlayer.claim(model, claimed?)      a hook will call sample() for this model (standalone skips it)
	  ClipPlayer.sample(model, now, out, weights, adds) -> boolean (anything written)
	  ClipPlayer.playView(name, opts?) / ClipPlayer.sampleView(track, now, holdRight, holdLeft) / ClipPlayer.stopView(fade?)
	  ClipPlayer.hitStopView(seconds)
	  ClipPlayer.stats() -> { tracks, models, decoded, ms }
	Clip names per family and what each is: docs/design/Combat_v3.md 7.2 and FightClips/init.lua.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClipPlayer = {}

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightClips = nil -- (required on first use: the index of every clip and its family)

local UPPER = { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }
local FULL = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow",
	"LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
local UPPER_SET = {}
for _, j in ipairs(UPPER) do
	UPPER_SET[j] = true
end

local BLEND_IN = 0.06
local BLEND_OUT = 0.15
local CHAIN_BLEND = 0.1 -- a new clip over one still showing (ClipPlayer.play)
local REACT_IN = 0.08 -- (the owner's numbers for reactions)
local REACT_OUT = 0.25
local RATE_MIN, RATE_MAX = 0.35, 3
local HITSTOP_RATE = 0.08

-- 64-letter alphabet, 12 bits per value (two letters)
local ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
local VAL = table.create(256, 0)
for i = 1, #ALPHA do
	VAL[string.byte(ALPHA, i)] = i - 1
end

local function smooth(x: number): number
	if x <= 0 then
		return 0
	elseif x >= 1 then
		return 1
	end
	return x * x * (3 - 2 * x)
end

--------------------------------------------------------------------------------------------------------------------
-- Clip data
--------------------------------------------------------------------------------------------------------------------

local decoded: { [string]: any } = {}
local decodedCount = 0

local function index()
	if FightClips == nil then
		local ok, mod = pcall(function()
			return require(Shared:WaitForChild("FightClips", 5) :: any)
		end)
		FightClips = if ok and type(mod) == "table" then mod else false
		if not ok then
			warn("[ClipPlayer] no FightClips: " .. tostring(mod))
		end
	end
	return FightClips or nil
end

local function rawClip(name: string): any
	local fc = index()
	if not fc then
		return nil
	end
	return fc.get(name)
end

-- decodes a run of `count` 12-bit values starting at byte `at` (1-based) into `out`, scaled to [lo, hi]
local function decodeInto(s: string, at: number, count: number, lo: number, hi: number, out: { number }, o: number)
	local span = (hi - lo) / 4095
	for k = 0, count - 1 do
		local a, b = string.byte(s, at + 2 * k, at + 2 * k + 1)
		out[o + k] = lo + (VAL[a] * 64 + VAL[b]) * span
	end
end

-- De-pop (fight-fixes, 19 Nov): a scan of all 102 clips found 190 single-sample jumps (a joint turning 40 to 179
-- degrees between two samples while its neighbours turn less than half that), most of them wrists flipping half a
-- turn (sword_light_2's right wrist: 150 degrees in one 0.032 s sample). On screen each is a snap. A jump is spread
-- over its neighbours (one sample each side, two for a flip over 100 degrees) along the shortest arc; the window
-- never crosses the hit sample, so the pose at the hit stays exactly as authored. Quaternions at arr[s*stride+off].
local depopCount = 0 -- (ClipPlayer.stats().depops)
local DEPOP_MIN = 40 -- degrees in one sample
local DEPOP_RATIO = 2 -- against the larger neighbour step
local DEPOP_WIDE = 100 -- a flip: spread two samples each side
local function qAngle(arr, a: number, b: number): number
	local d = arr[a] * arr[b] + arr[a + 1] * arr[b + 1] + arr[a + 2] * arr[b + 2] + arr[a + 3] * arr[b + 3]
	return math.deg(2 * math.acos(math.clamp(math.abs(d), 0, 1)))
end
local function depop(arr: { number }, n: number, stride: number, off: number, hitIndex: number?): number
	local fixed = 0
	-- a lone bad sample (axe_skill_whirl's hips and ankles at sample 15: 180 degrees from both neighbours, which agree
	-- with each other): replaced by the midpoint of its neighbours
	for i = 1, n - 2 do
		local o0, o1, o2 = (i - 1) * stride + off, i * stride + off, (i + 1) * stride + off
		local a, b, across = qAngle(arr, o0, o1), qAngle(arr, o1, o2), qAngle(arr, o0, o2)
		if a > 60 and b > 60 and across < 0.5 * math.min(a, b) and i ~= hitIndex then
			local q0 = CFrame.new(0, 0, 0, arr[o0], arr[o0 + 1], arr[o0 + 2], arr[o0 + 3])
			local q2 = CFrame.new(0, 0, 0, arr[o2], arr[o2 + 1], arr[o2 + 2], arr[o2 + 3])
			local axis, angle = q0:Lerp(q2, 0.5):ToAxisAngle()
			local h = math.sin(angle / 2)
			arr[o1], arr[o1 + 1], arr[o1 + 2], arr[o1 + 3] = axis.X * h, axis.Y * h, axis.Z * h, math.cos(angle / 2)
			fixed += 1
		end
	end
	for pass = 1, 2 do
		local steps = table.create(n, 0)
		for i = 1, n - 1 do
			steps[i] = qAngle(arr, (i - 1) * stride + off, i * stride + off)
		end
		local i = 1
		while i <= n - 1 do
			local s = steps[i]
			local nb = math.max(steps[i - 1] or 0, steps[i + 1] or 0)
			local nextI = i + 1
			if s > DEPOP_MIN and s > DEPOP_RATIO * nb then
				local k = if s > DEPOP_WIDE then 2 else 1
				local a, b = math.max(0, i - 1 - k), math.min(n - 1, i + k)
				if hitIndex and a < hitIndex and hitIndex < b then
					if hitIndex <= i - 1 then
						a = hitIndex
					else
						b = hitIndex
					end
				end
				if b - a >= 2 then
					local oa, ob = a * stride + off, b * stride + off
					local qa = CFrame.new(0, 0, 0, arr[oa], arr[oa + 1], arr[oa + 2], arr[oa + 3])
					local qb = CFrame.new(0, 0, 0, arr[ob], arr[ob + 1], arr[ob + 2], arr[ob + 3])
					for sIdx = a + 1, b - 1 do
						local axis, angle = qa:Lerp(qb, (sIdx - a) / (b - a)):ToAxisAngle()
						local h = math.sin(angle / 2)
						local o = sIdx * stride + off
						arr[o], arr[o + 1], arr[o + 2], arr[o + 3] = axis.X * h, axis.Y * h, axis.Z * h, math.cos(angle / 2)
					end
					fixed += 1
					nextI = b + 1 -- (this window is done; the next pass rescans)
				end
			end
			i = nextI
		end
	end
	return fixed
end

local function decode(name: string): any
	local d = decoded[name]
	if d ~= nil then
		return d or nil
	end
	local raw = rawClip(name)
	if not raw then
		decoded[name] = false
		return nil
	end
	local full = raw.mask == "full"
	local joints = if full then FULL else UPPER
	local nj = #joints
	local n = raw.n
	-- third person: per joint, per sample: qx, qy, qz, qw (and the Root's x, y, z)
	local q = table.create(nj)
	for j = 1, nj do
		q[j] = table.create(n * 4, 0)
	end
	local rootPos = if full then table.create(n * 3, 0) else nil
	local stride = nj * 8 + (if full then 6 else 0)
	local tp = raw.tp
	local tmp = table.create(4, 0)
	for i = 0, n - 1 do
		local at = 1 + i * stride
		for j = 1, nj do
			decodeInto(tp, at, 4, -1, 1, tmp, 1)
			local x, y, z, w = tmp[1], tmp[2], tmp[3], tmp[4]
			local m = math.sqrt(x * x + y * y + z * z + w * w)
			if m < 1e-6 then
				x, y, z, w, m = 0, 0, 0, 1, 1
			end
			local arr = q[j]
			arr[i * 4 + 1], arr[i * 4 + 2], arr[i * 4 + 3], arr[i * 4 + 4] = x / m, y / m, z / m, w / m
			at += 8
			if full and j == 1 then
				decodeInto(tp, at, 3, -8, 8, rootPos :: any, i * 3 + 1)
				at += 6
			end
		end
	end
	-- first person: per sample: right pos (3), right quat (4), left pos (3), left quat (4), right pole (3), left pole (3)
	local fp = nil
	if type(raw.fp) == "string" and #raw.fp >= n * 40 then
		fp = table.create(n * 20, 0)
		for i = 0, n - 1 do
			local at = 1 + i * 40
			decodeInto(raw.fp, at, 3, -4, 4, fp, i * 20 + 1)
			decodeInto(raw.fp, at + 6, 4, -1, 1, fp, i * 20 + 4)
			decodeInto(raw.fp, at + 14, 3, -4, 4, fp, i * 20 + 8)
			decodeInto(raw.fp, at + 20, 4, -1, 1, fp, i * 20 + 11)
			decodeInto(raw.fp, at + 28, 3, -1, 1, fp, i * 20 + 15)
			decodeInto(raw.fp, at + 34, 3, -1, 1, fp, i * 20 + 18)
		end
	end
	-- de-pop (above): third-person joints and the first-person hands, never moving the hit sample
	local hitIndex = if type(raw.hit) == "number" and raw.hit > 0 and raw.dt then math.floor(raw.hit / raw.dt + 0.5) else nil
	local pops = 0
	for j = 1, nj do
		pops += depop(q[j], n, 4, 1, hitIndex)
	end
	if fp then
		pops += depop(fp, n, 20, 4, hitIndex)
		pops += depop(fp, n, 20, 11, hitIndex)
	end
	depopCount += pops
	local markers = {}
	for k, v in pairs(raw.markers or {}) do
		table.insert(markers, { name = k, t = v })
	end
	table.sort(markers, function(a, b)
		return a.t < b.t
	end)
	d = {
		name = name,
		len = raw.len,
		dt = raw.dt,
		n = n,
		hit = raw.hit,
		mask = raw.mask,
		loop = raw.loop == true,
		additive = raw.additive == true,
		item = raw.item,
		kind = raw.kind,
		family = raw.family,
		fpLeft = raw.fpLeft == true,
		joints = joints,
		q = q,
		rootPos = rootPos,
		fp = fp,
		markers = markers,
	}
	decoded[name] = d
	decodedCount += 1
	return d
end

function ClipPlayer.has(name: string): boolean
	return decode(name) ~= nil
end

function ClipPlayer.info(name: string): { [string]: any }?
	local d = decode(name)
	if not d then
		return nil
	end
	local markers = {}
	for _, m in ipairs(d.markers) do
		markers[m.name] = m.t
	end
	return { len = d.len, hit = d.hit, mask = d.mask, loop = d.loop, additive = d.additive, item = d.item, kind = d.kind,
		markers = markers, family = d.family, hasView = d.fp ~= nil }
end

-- Catmull-Rom between samples i and i + 1 (0-based) of a 4-wide (quaternion) or 3-wide array, at fraction f.
local function sampleIndex(d, i: number): number
	if d.loop then
		return i % (d.n - 1) -- (the last sample repeats the first)
	end
	return math.clamp(i, 0, d.n - 1)
end

local function crQuat(arr: { number }, d, i: number, f: number): (number, number, number, number)
	local i0, i1, i2, i3 = sampleIndex(d, i - 1) * 4, sampleIndex(d, i) * 4, sampleIndex(d, i + 1) * 4, sampleIndex(d, i + 2) * 4
	local bx, by, bz, bw = arr[i1 + 1], arr[i1 + 2], arr[i1 + 3], arr[i1 + 4]
	local ax, ay, az, aw = arr[i0 + 1], arr[i0 + 2], arr[i0 + 3], arr[i0 + 4]
	local cx, cy, cz, cw = arr[i2 + 1], arr[i2 + 2], arr[i2 + 3], arr[i2 + 4]
	local dx, dy, dz, dw = arr[i3 + 1], arr[i3 + 2], arr[i3 + 3], arr[i3 + 4]
	-- keep every neighbour on b's side of the sphere
	if ax * bx + ay * by + az * bz + aw * bw < 0 then
		ax, ay, az, aw = -ax, -ay, -az, -aw
	end
	if cx * bx + cy * by + cz * bz + cw * bw < 0 then
		cx, cy, cz, cw = -cx, -cy, -cz, -cw
	end
	if dx * cx + dy * cy + dz * cz + dw * cw < 0 then
		dx, dy, dz, dw = -dx, -dy, -dz, -dw
	end
	local f2, f3 = f * f, f * f * f
	local k0 = -0.5 * f3 + f2 - 0.5 * f
	local k1 = 1.5 * f3 - 2.5 * f2 + 1
	local k2 = -1.5 * f3 + 2 * f2 + 0.5 * f
	local k3 = 0.5 * f3 - 0.5 * f2
	local x = ax * k0 + bx * k1 + cx * k2 + dx * k3
	local y = ay * k0 + by * k1 + cy * k2 + dy * k3
	local z = az * k0 + bz * k1 + cz * k2 + dz * k3
	local w = aw * k0 + bw * k1 + cw * k2 + dw * k3
	local m = math.sqrt(x * x + y * y + z * z + w * w)
	if m < 1e-6 then
		return bx, by, bz, bw
	end
	return x / m, y / m, z / m, w / m
end

local function crVec(arr: { number }, d, i: number, f: number, width: number, off: number): (number, number, number)
	local i0, i1, i2, i3 = sampleIndex(d, i - 1) * width + off, sampleIndex(d, i) * width + off,
		sampleIndex(d, i + 1) * width + off, sampleIndex(d, i + 2) * width + off
	local f2, f3 = f * f, f * f * f
	local k0 = -0.5 * f3 + f2 - 0.5 * f
	local k1 = 1.5 * f3 - 2.5 * f2 + 1
	local k2 = -1.5 * f3 + 2 * f2 + 0.5 * f
	local k3 = 0.5 * f3 - 0.5 * f2
	return arr[i0 + 1] * k0 + arr[i1 + 1] * k1 + arr[i2 + 1] * k2 + arr[i3 + 1] * k3,
		arr[i0 + 2] * k0 + arr[i1 + 2] * k1 + arr[i2 + 2] * k2 + arr[i3 + 2] * k3,
		arr[i0 + 3] * k0 + arr[i1 + 3] * k1 + arr[i2 + 3] * k2 + arr[i3 + 3] * k3
end

-- the clip's position (samples) at clip time tau
local function cursor(d, tau: number): (number, number)
	local u = tau / d.dt
	if d.loop then
		u = u % (d.n - 1)
	else
		u = math.clamp(u, 0, d.n - 1)
	end
	local i = math.floor(u)
	if not d.loop and i >= d.n - 1 then
		return d.n - 2, 1
	end
	return i, u - i
end

-- the Transform of joint j (index into d.joints) at clip time tau
local function jointAt(d, j: number, tau: number): CFrame
	local i, f = cursor(d, tau)
	local x, y, z, w = crQuat(d.q[j], d, i, f)
	local px, py, pz = 0, 0, 0
	if j == 1 and d.rootPos then
		px, py, pz = crVec(d.rootPos, d, i, f, 3, 0)
	end
	return CFrame.new(px, py, pz, x, y, z, w)
end

--------------------------------------------------------------------------------------------------------------------
-- Tracks and timing
--------------------------------------------------------------------------------------------------------------------

-- Builds the time map of a track: clip time as a function of seconds since it started.
local function fitTiming(d, opts): (number, number, number, number)
	-- returns startTau, splitReal (seconds at which the hit is reached), rate before, rate after
	local speed = math.max(tonumber(opts.speed) or 1, 0.05)
	local hit = d.hit
	local lead = tonumber(opts.lead)
	local total = tonumber(opts.total)
	if hit and hit > 0 and lead then
		-- (opts.startAt with a lead: from that clip time, reaching the hit in `lead` seconds)
		local startTau = math.clamp(tonumber(opts.startAt) or 0, 0, hit)
		if lead <= 1e-3 then
			-- announced at the strike: start two samples before the hit, quickly
			startTau = math.max(0, hit - 2 * d.dt)
			lead = 2 * d.dt / 1.5
		end
		local before = math.clamp((hit - startTau) / math.max(lead, 1e-3), RATE_MIN, RATE_MAX)
		local after = speed
		if total and total > lead then
			after = math.clamp((d.len - hit) / (total - lead), RATE_MIN, RATE_MAX)
		end
		return startTau, (hit - startTau) / before, before, after
	end
	if total and total > 0 and not d.loop then
		local r = math.clamp(d.len / total, RATE_MIN, RATE_MAX)
		return 0, math.huge, r, r
	end
	return tonumber(opts.startAt) or 0, math.huge, speed, speed
end

local function newTrack(d, opts)
	opts = opts or {}
	local startTau, split, before, after = fitTiming(d, opts)
	if opts.startAt then
		startTau = math.max(startTau, tonumber(opts.startAt) or 0)
	end
	local track = {
		clip = d,
		age = 0, -- seconds of (hit-stop slowed) play
		tau = startTau,
		startTau = startTau,
		split = split,
		before = before,
		after = after,
		loop = if opts.loop ~= nil then opts.loop == true else d.loop,
		blendIn = tonumber(opts.blendIn) or (if d.additive then REACT_IN else BLEND_IN),
		blendOut = tonumber(opts.blendOut) or (if d.additive then REACT_OUT else BLEND_OUT),
		weight = math.clamp(tonumber(opts.weight) or 1, 0, 1),
		upperOnly = opts.mask == "upper" or d.mask ~= "full",
		onMarker = opts.onMarker,
		onEnd = opts.onEnd,
		markerAt = 1,
		endedAt = nil :: number?,
		stopAt = nil :: number?,
		stopFade = 0.12,
		w = 0,
		done = false,
	}
	-- markers already behind the start are not fired
	while track.markerAt <= #d.markers and d.markers[track.markerAt].t < startTau - 1e-6 do
		track.markerAt += 1
	end
	return track
end

-- advances a track by dt seconds of real time (rate = hit-stop factor); returns its blend weight now
local function advance(track, dt: number, rate: number): number
	local d = track.clip
	local step = dt * rate
	if track.endedAt == nil then
		local a0 = track.age
		track.age += step
		local a1 = track.age
		-- clip time: the part before the split at `before`, after it at `after`
		local tau
		if a1 <= track.split then
			tau = track.startTau + a1 * track.before
		else
			tau = track.startTau + track.split * track.before + (a1 - track.split) * track.after
		end
		if not track.loop and tau >= d.len then
			tau = d.len
			track.endedAt = 0
		end
		track.tau = tau
		-- markers
		local markers = d.markers
		while track.markerAt <= #markers and markers[track.markerAt].t <= tau + 1e-6 do
			local m = markers[track.markerAt]
			track.markerAt += 1
			if track.onMarker then
				task.spawn(track.onMarker, m.name)
			end
		end
		if track.loop and a1 > a0 and tau >= d.len then
			track.markerAt = 1
		end
	else
		track.endedAt += dt
	end
	local w = if track.blendIn > 0 then smooth(track.age / track.blendIn) else 1
	if track.endedAt then
		w *= 1 - smooth(track.endedAt / math.max(track.blendOut, 1e-3))
		if track.endedAt >= track.blendOut then
			track.done = true
		end
	end
	if track.stopAt then
		track.stopAt += dt
		w *= 1 - smooth(track.stopAt / math.max(track.stopFade, 1e-3))
		if track.stopAt >= track.stopFade then
			track.done = true
		end
	end
	track.w = w * track.weight
	if track.done and track.onEnd then
		local cb = track.onEnd
		track.onEnd = nil
		task.spawn(cb)
	end
	return track.w
end

--------------------------------------------------------------------------------------------------------------------
-- Third person
--------------------------------------------------------------------------------------------------------------------

local models: { [Model]: any } = {}
local lastMs = 0

local function entryOf(model: Model)
	local e = models[model]
	if not e then
		e = { tracks = {}, claimed = false, hitStop = 0, joints = nil, bases = {}, written = {}, lastClock = os.clock() }
		models[model] = e
	end
	return e
end

local function findJoints(model: Model): { [string]: any }
	local out = {}
	for _, dsc in ipairs(model:GetDescendants()) do
		if dsc:IsA("Motor6D") or dsc:IsA("AnimationConstraint") then
			local name = dsc.Name
			if out[name] == nil or dsc:IsA("AnimationConstraint") then
				out[name] = dsc
			end
		end
	end
	return out
end

function ClipPlayer.play(model: Model, name: string, opts: { [string]: any }?): any
	local d = decode(name)
	if not d or typeof(model) ~= "Instance" then
		return nil
	end
	local e = entryOf(model)
	if #e.tracks == 0 then
		e.lastClock = os.clock() -- (idle until now: the first step must not count the idle time)
	end
	opts = opts or {}
	if opts.blendIn == nil and not d.additive and d.family ~= "Spear" and string.sub(d.name, 1, 8) ~= "twinaxe_" then
		-- a chain step cutting into the last one: crossfade over CHAIN_BLEND, not BLEND_IN. Measured on every chain
		-- (fight-fixes frame sims, 60 fps): the 0.06 s crossfade turned the waist and neck 19 to 26 degrees in one
		-- frame at each step's start (the step begins at the last one's follow-through, the body was in its recovery);
		-- 0.1 s took the paired chain from 10 snaps to 3 and its worst frame from 62 to 46 degrees. (The spear's two
		-- grips are half a turn apart, so a longer crossfade there flips the wrist: it keeps BLEND_IN, as does the
		-- two-handed twin axe, 63 -> 78 with it.)
		for _, t in ipairs(e.tracks) do
			if not t.done and not t.clip.additive and t.w > 0.05 then
				opts = table.clone(opts)
				opts.blendIn = CHAIN_BLEND
				break
			end
		end
	end
	local track = newTrack(d, opts)
	table.insert(e.tracks, track)
	return track
end

function ClipPlayer.stopTrack(track: any, fade: number?)
	if track and not track.done and not track.stopAt then
		track.stopAt = 0
		track.stopFade = fade or 0.12
	end
end

function ClipPlayer.stop(model: Model, fade: number?)
	local e = models[model]
	if e then
		for _, t in ipairs(e.tracks) do
			ClipPlayer.stopTrack(t, fade)
		end
	end
end

function ClipPlayer.playing(model: Model): any
	local e = models[model]
	if not e then
		return nil
	end
	for i = #e.tracks, 1, -1 do
		local t = e.tracks[i]
		if not t.done and not t.clip.additive then
			return t
		end
	end
	return nil
end

function ClipPlayer.hitStop(model: Model, seconds: number)
	local e = models[model]
	if e then
		e.hitStop = math.max(e.hitStop, seconds)
	end
end

function ClipPlayer.claim(model: Model, claimed: boolean?)
	entryOf(model).claimed = claimed ~= false
end

-- Steps the model's tracks to `now` and writes this frame's targets. out[joint] = the clip's Transform,
-- weights[joint] = how much of it, adds[joint] = an additive delta (already weighted).
local function step(e, now: number)
	local dt = math.clamp(now - e.lastClock, 0, 0.1)
	e.lastClock = now
	local rate = 1
	if e.hitStop > 0 then
		rate = HITSTOP_RATE
		e.hitStop = math.max(0, e.hitStop - dt)
	end
	local tracks = e.tracks
	local covered = false
	-- newest first: once a full-weight non-additive track covers everything, older ones underneath are dropped
	for i = #tracks, 1, -1 do
		local t = tracks[i]
		advance(t, dt, rate)
		if covered and not t.clip.additive then
			t.done = true
		elseif not t.clip.additive and t.w >= 0.999 and not t.upperOnly then
			covered = true
		elseif not t.clip.additive and t.w >= 0.999 and t.upperOnly then
			-- an upper clip covers older upper clips only
			for k = i - 1, 1, -1 do
				local o = tracks[k]
				if not o.clip.additive and o.upperOnly then
					o.done = true
				end
			end
		end
	end
	for i = #tracks, 1, -1 do
		if tracks[i].done then
			table.remove(tracks, i)
		end
	end
end

function ClipPlayer.sample(model: Model, now: number, out: { [string]: CFrame }, weights: { [string]: number },
	adds: { [string]: CFrame }?): boolean
	local e = models[model]
	if not e or #e.tracks == 0 then
		return false
	end
	step(e, now)
	local any = false
	for _, t in ipairs(e.tracks) do -- oldest first: newer tracks blend over older ones
		local d = t.clip
		local w = t.w
		if w > 1e-3 then
			for j, name in ipairs(d.joints) do
				if not (t.upperOnly and not UPPER_SET[name]) then
					local cf = jointAt(d, j, t.tau)
					if d.additive then
						if adds then
							local ref = jointAt(d, j, 0)
							local delta = ref:Inverse() * cf
							delta = CFrame.identity:Lerp(delta, w)
							adds[name] = if adds[name] then adds[name] * delta else delta
							any = true
						end
					else
						local prev = out[name]
						local pw = weights[name] or 0
						if prev and pw > 0 then
							out[name] = prev:Lerp(cf, w)
							weights[name] = pw + (1 - pw) * w
						else
							out[name] = cf
							weights[name] = w
						end
						any = true
					end
				end
			end
		end
	end
	return any
end

-- Standalone: models no hook claimed are written here, after CharacterVisuals' pass.
local outT, outW, outA = {}, {}, {}
local function standalone()
	if next(models) == nil then
		return
	end
	local t0 = os.clock()
	local now = os.clock()
	for model, e in pairs(models) do
		if not model.Parent then
			models[model] = nil
		elseif not e.claimed then
			if #e.tracks == 0 then
				-- give the joints their base back once (so a layer reading them never mistakes our pose for its own)
				if next(e.written) then
					for joint, written in pairs(e.written) do
						if joint.Parent and joint.Transform == written then
							joint.Transform = e.bases[joint]
						end
					end
					table.clear(e.written)
					table.clear(e.bases)
				end
			else
				if e.joints == nil or e.jointsAt == nil or now - e.jointsAt > 2 then
					e.joints = findJoints(model)
					e.jointsAt = now
				end
				table.clear(outT)
				table.clear(outW)
				table.clear(outA)
				ClipPlayer.sample(model, now, outT, outW, outA)
				for name, joint in pairs(e.joints) do
					local cf, w, add = outT[name], outW[name], outA[name]
					if cf or add then
						local cur = joint.Transform
						local base = if e.written[joint] ~= nil and cur == e.written[joint] then e.bases[joint] else cur
						local v = base
						if cf and w and w > 0 then
							v = base:Lerp(cf, w)
						end
						if add then
							v = add * v
						end
						joint.Transform = v
						-- (as read back: the property keeps a re-orthonormalised copy that never equals `v`, and the
						-- check above then took our own pose as the next base and compounded it)
						e.written[joint] = joint.Transform
						e.bases[joint] = base
					end
				end
			end
		end
	end
	lastMs = (os.clock() - t0) * 1000
end

--------------------------------------------------------------------------------------------------------------------
-- First person
--------------------------------------------------------------------------------------------------------------------

local view = { tracks = {}, hitStop = 0, lastClock = os.clock() }

function ClipPlayer.playView(name: string, opts: { [string]: any }?): any
	local d = decode(name)
	if not d or not d.fp then
		return nil
	end
	if #view.tracks == 0 then
		view.lastClock = os.clock()
	end
	local track = newTrack(d, opts or {})
	table.insert(view.tracks, track)
	return track
end

function ClipPlayer.stopView(fade: number?)
	for _, t in ipairs(view.tracks) do
		ClipPlayer.stopTrack(t, fade)
	end
end

function ClipPlayer.hitStopView(seconds: number)
	view.hitStop = math.max(view.hitStop, seconds)
end

-- (a quaternion inside the 20-wide first-person rows, at offset `off`)
local function crQuat4(arr: { number }, d, i: number, f: number, off: number): (number, number, number, number)
	local function at(k: number): (number, number, number, number)
		local b = sampleIndex(d, k) * 20 + off
		return arr[b + 1], arr[b + 2], arr[b + 3], arr[b + 4]
	end
	local ax, ay, az, aw = at(i - 1)
	local bx, by, bz, bw = at(i)
	local cx, cy, cz, cw = at(i + 1)
	local dx, dy, dz, dw = at(i + 2)
	if ax * bx + ay * by + az * bz + aw * bw < 0 then
		ax, ay, az, aw = -ax, -ay, -az, -aw
	end
	if cx * bx + cy * by + cz * bz + cw * bw < 0 then
		cx, cy, cz, cw = -cx, -cy, -cz, -cw
	end
	if dx * cx + dy * cy + dz * cz + dw * cw < 0 then
		dx, dy, dz, dw = -dx, -dy, -dz, -dw
	end
	local f2, f3 = f * f, f * f * f
	local k0 = -0.5 * f3 + f2 - 0.5 * f
	local k1 = 1.5 * f3 - 2.5 * f2 + 1
	local k2 = -1.5 * f3 + 2 * f2 + 0.5 * f
	local k3 = 0.5 * f3 - 0.5 * f2
	local x = ax * k0 + bx * k1 + cx * k2 + dx * k3
	local y = ay * k0 + by * k1 + cy * k2 + dy * k3
	local z = az * k0 + bz * k1 + cz * k2 + dz * k3
	local w = aw * k0 + bw * k1 + cw * k2 + dw * k3
	local m = math.sqrt(x * x + y * y + z * z + w * w)
	if m < 1e-6 then
		return bx, by, bz, bw
	end
	return x / m, y / m, z / m, w / m
end

local function viewFrames(d, tau: number): (CFrame, CFrame, Vector3, Vector3)
	local i, f = cursor(d, tau)
	local fp = d.fp
	local rx, ry, rz = crVec(fp, d, i, f, 20, 0)
	local qx, qy, qz, qw = crQuat4(fp, d, i, f, 3)
	local lx, ly, lz = crVec(fp, d, i, f, 20, 7)
	local sx, sy, sz, sw = crQuat4(fp, d, i, f, 10)
	local px, py, pz = crVec(fp, d, i, f, 20, 14)
	local ox, oy, oz = crVec(fp, d, i, f, 20, 17)
	return CFrame.new(rx, ry, rz, qx, qy, qz, qw), CFrame.new(lx, ly, lz, sx, sy, sz, sw), Vector3.new(px, py, pz),
		Vector3.new(ox, oy, oz)
end

-- This frame's wrists for the viewmodel: blended in from (and back out to) the holds given. Returns right, left,
-- poleRight?, poleLeft?, weight (0 = nothing playing: use the holds).
function ClipPlayer.sampleView(track: any, now: number, holdRight: CFrame, holdLeft: CFrame): (CFrame, CFrame, Vector3?, Vector3?, number)
	local dt = math.clamp(now - view.lastClock, 0, 0.1)
	view.lastClock = now
	local rate = 1
	if view.hitStop > 0 then
		rate = HITSTOP_RATE
		view.hitStop = math.max(0, view.hitStop - dt)
	end
	local right, left = holdRight, holdLeft
	local poleR, poleL = nil, nil
	local wsum = 0
	for i = 1, #view.tracks do
		local t = view.tracks[i]
		advance(t, dt, rate)
		if t.w > 1e-3 then
			local r, l, pr, pl = viewFrames(t.clip, t.tau)
			right = right:Lerp(r, t.w)
			if t.clip.fpLeft or t.clip.kind ~= "Blade" then
				left = left:Lerp(l, t.w)
				poleL = if poleL then poleL:Lerp(pl, t.w) else pl
			end
			poleR = if poleR then poleR:Lerp(pr, t.w) else pr
			wsum = math.max(wsum, t.w)
		end
	end
	for i = #view.tracks, 1, -1 do
		if view.tracks[i].done then
			table.remove(view.tracks, i)
		end
	end
	return right, left, poleR, poleL, wsum
end

--------------------------------------------------------------------------------------------------------------------

function ClipPlayer.stats(): { [string]: number }
	local n, m = 0, 0
	for _, e in pairs(models) do
		m += 1
		n += #e.tracks
	end
	return { tracks = n, models = m, decoded = decodedCount, ms = lastMs, depops = depopCount }
end

function ClipPlayer._decode(name: string): any -- test hook: the decoded clip
	return decode(name)
end

function ClipPlayer._jointAt(name: string, joint: string, tau: number): CFrame? -- test hook: one joint's Transform
	local d = decode(name)
	if not d then
		return nil
	end
	for j, n in ipairs(d.joints) do
		if n == joint then
			return jointAt(d, j, tau)
		end
	end
	return nil
end

function ClipPlayer.Init(_controllers: any) end

function ClipPlayer.Start()
	-- after CharacterVisuals' PreSimulation pass (it connects first: ClientMain starts it earlier)
	RunService.PreSimulation:Connect(standalone)
	Players.PlayerRemoving:Connect(function(p)
		if p.Character then
			models[p.Character] = nil
		end
	end)
end

return ClipPlayer
