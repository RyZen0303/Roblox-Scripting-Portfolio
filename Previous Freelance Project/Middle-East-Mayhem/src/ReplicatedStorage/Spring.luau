-- Spring.luau
-- Leaky-integrator Spring physics simulation class

local Spring = {}
Spring.__index = Spring

function Spring.new(position)
	local self = setmetatable({}, Spring)
	self.s = 10 -- Speed / Stiffness
	self.d = 1  -- Damper
	self.t = position or Vector3.new() -- Target
	self.p = position or Vector3.new() -- Position
	self.v = (typeof(position) == "Vector3" and Vector3.new() or 0) -- Velocity
	return self
end

function Spring:Update(dt: number)
	local d = (self.t - self.p)
	local f = d * self.s
	self.v = self.v + f * dt
	self.v = self.v * (1 - math.clamp(self.d * dt * 10, 0, 1))
	self.p = self.p + self.v * dt
	return self.p
end

function Spring:Accelerate(velocity)
	self.v = self.v + velocity
end

return Spring