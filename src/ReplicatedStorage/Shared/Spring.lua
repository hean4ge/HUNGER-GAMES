--[[
	Spring - damped spring for smooth, physical-feeling motion (camera bob, sway, recoil, FOV).
	Works with numbers, Vector2 and Vector3.
	local s = Spring.new(0, 12, 0.6) -- (initial, speed = angular frequency, damping: 1 = no overshoot, < 1 = bouncy)
	s.target = 1; s:impulse(5); local value = s:update(dt)
]]
local Spring = {}
Spring.__index = Spring

function Spring.new(initial: any?, speed: number?, damping: number?)
	local start = if initial == nil then 0 else initial
	return setmetatable({
		position = start,
		velocity = start * 0,
		target = start,
		speed = speed or 10,
		damping = damping or 1,
	}, Spring)
end

function Spring:impulse(velocity: any)
	self.velocity += velocity
end

function Spring:reset(value: any)
	self.position = value
	self.target = value
	self.velocity = value * 0
end

local MAX_STEP = 1 / 240

function Spring:update(dt: number): any
	dt = math.min(dt, 0.1)
	local steps = math.max(1, math.ceil(dt / MAX_STEP))
	local h = dt / steps
	local stiffness = self.speed * self.speed
	local friction = 2 * self.damping * self.speed
	local position, velocity, target = self.position, self.velocity, self.target
	for _ = 1, steps do
		local acceleration = (target - position) * stiffness - velocity * friction
		velocity += acceleration * h
		position += velocity * h
	end
	self.position, self.velocity = position, velocity
	return position
end

return Spring
