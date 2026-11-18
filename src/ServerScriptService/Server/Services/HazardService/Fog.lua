--[[
	HazardService.Fog - the cold fog (server).

	A circle on low ground where contenders are. The fog has a flat top: during the warning a thin ground mist creeps
	in (harmless), then the top rises over Rise seconds to Depth studs above the ground at the circle's centre,
	stands, and sinks back over the last Fade seconds (HazardDefs.fogTopAt: the same curve on every client).

	A contender whose head is under the top, inside the circle, loses warmth: the player attribute HazardChill runs
	from 0 to 1 over ChillTime seconds and back over WarmTime once they are out. At 1 they lose DamagePerSecond
	(cause "Cold"). Beside a lit fire (FireRadius) the warmth comes back even in the fog.
	Ways out: walk out of the circle, climb above the top (a slope, a tree, the horn's deck where it is high enough),
	or find a fire.
]]
local Fog = {}

local chill: { [Player]: number } = {}
local hurtAt: { [Player]: number } = {}

local function setChill(player: Player, value: number?)
	local rounded = if value then math.floor(value * 20 + 0.5) / 20 else nil
	if rounded == 0 then
		rounded = nil
	end
	if player:GetAttribute("HazardChill") ~= rounded then
		player:SetAttribute("HazardChill", rounded)
	end
end

function Fog.make(ctx, opts: { [string]: any })
	local F = ctx.Defs.Fog
	local alive = #ctx.players
	local radius = math.min(F.Radius + F.RadiusPerAlive * alive, F.RadiusMax)
	local x, z = opts.x, opts.z
	if not x then
		-- the lowest-standing contender whose circle does not swallow too many of the living
		local maxShare = ctx.Defs.Director.MaxShare
		local best, bestY = nil, math.huge
		for _, entry in ipairs(ctx.players) do
			local inside = 0
			for _, other in ipairs(ctx.players) do
				if (Vector3.new(other.pos.X, 0, other.pos.Z) - Vector3.new(entry.pos.X, 0, entry.pos.Z)).Magnitude <= radius then
					inside += 1
				end
			end
			local share = inside / math.max(alive, 1)
			if (alive < 4 or share <= maxShare) and entry.pos.Y < bestY then
				best, bestY = entry, entry.pos.Y
			end
		end
		if not best then
			return nil, "no hollow with few enough contenders in it"
		end
		x, z = best.pos.X, best.pos.Z
	end
	-- the fog lies on the lowest ground near the centre, so it fills the hollow and not the hillside
	local base = ctx.ground(x, z)
	for _, offset in ipairs({ { 40, 0 }, { -40, 0 }, { 0, 40 }, { 0, -40 }, { 80, 0 }, { -80, 0 }, { 0, 80 }, { 0, -80 } }) do
		base = math.min(base, ctx.ground(x + offset[1], z + offset[2]) + 3)
	end
	local intensity = tonumber(opts.intensity) or 1
	local depth = math.max(F.Depth * math.min(intensity, 1.2), 9)
	-- the contender it was called on must be under it, or it is no challenge to them
	local first = nil
	for _, entry in ipairs(ctx.players) do
		if math.abs(entry.pos.X - x) < 1 and math.abs(entry.pos.Z - z) < 1 then
			first = entry
		end
	end
	if first then
		base = math.max(base, first.pos.Y - 3 - depth * 0.5)
	end
	return { x = x, z = z, radius = radius, duration = F.Duration, a = base, b = base + depth, intensity = intensity }
end

function Fog.begin(ctx, _event: { [string]: any })
	table.clear(chill)
	table.clear(hurtAt)
	-- butterflies do not fly in it
	local butterflies = ctx.modules and ctx.modules.Butterflies
	if butterflies then
		butterflies.recall(ctx)
	end
end

function Fog.step(ctx, event: { [string]: any }, phase: string, dt: number, now: number)
	local F = ctx.Defs.Fog
	local top = ctx.Defs.fogTopAt(event, now)
	local r2 = event.radius * event.radius
	for _, entry in ipairs(ctx.players) do
		local player = entry.player
		local dx, dz = entry.pos.X - event.x, entry.pos.Z - event.z
		local head = entry.pos.Y + 1.5
		local under = phase == "Active" and dx * dx + dz * dz <= r2 and head < top
		local value = chill[player] or 0
		if under and not ctx.nearFire(entry.pos, F.FireRadius) then
			value = math.min(1, value + dt / F.ChillTime)
		else
			value = math.max(0, value - dt / F.WarmTime)
		end
		chill[player] = value
		setChill(player, value)
		if value >= 1 and under and now >= (hurtAt[player] or 0) then
			hurtAt[player] = now + 1
			ctx.damage(entry, F.DamagePerSecond, F.Cause, nil)
		end
	end
end

function Fog.finish(_ctx, _event: { [string]: any })
	for player in pairs(chill) do
		if player.Parent then
			setChill(player, nil)
		end
	end
	table.clear(chill)
	table.clear(hurtAt)
end

function Fog.roundEnd(ctx)
	Fog.finish(ctx, {})
end

function Fog.debug(_ctx)
	local n, cold = 0, 0
	for _, value in pairs(chill) do
		n += 1
		if value >= 1 then
			cold += 1
		end
	end
	return { tracked = n, cold = cold }
end

return Fog
