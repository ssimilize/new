--[[
	Swim (glow-up DR): the pure maths of swimming in the Deep Reef, used by Controllers/DeepReef
	(the local swimmer) and Controllers/Mounts (a swimmer mount's pose). Tuning in Config.DeepReef.
	Plain numbers only (x, y, z), so it runs anywhere and is unit-tested in DeepReef.spec.

	Swim.Inside(x, y, z, area, slack?) -> boolean       within the water (radius, sand, surface)
	Swim.Clamp(x, y, z, area, margin) -> (x, y, z, hitY, hitEdge)
	                                                   kept margin studs off the sand, surface and edge
	Swim.Speed(riding, swims, rideSpeed) -> number     on foot, or a swimmer mount (faster)
	Swim.Target(mx, mz, vertical, lookY, speed, cfg) -> (tx, ty, tz)
	                                                   the velocity the input asks for: the stick /
	                                                   keys move flat, ascend / descend (-1..1) and
	                                                   the camera's pitch while swimming forward move
	                                                   up and down; no input floats gently up
	Swim.Approach(v, target, rate, dt) -> number       exponential ease (frame-rate independent)
	Swim.Step(state, tx, ty, tz, dt, cfg, area) -> state
	                                                   state = { x, y, z, vx, vy, vz }, in place:
	                                                   eases the velocity, moves, clamps (and stops the
	                                                   velocity into a wall)
	Swim.Heading(vx, vz, previous) -> yaw              faces the way it swims (characters face -Z)
	Swim.Tilt(vx, vy, vz, speed, maxDegrees) -> pitch  radians: leans into the swim, noses up / down
	Swim.Bob(t, bob) -> studs                          the idle float
	Swim.ClipSpeed(speed, cfg) -> number               a mount's walk clip speed: slowed strokes

	No drowning: there is no air meter at all.
]]

local Swim = {}

local sqrt, exp, clamp, atan2, sin, rad = math.sqrt, math.exp, math.clamp, math.atan2, math.sin, math.rad

local function flat(x: number, z: number, area): (number, number)
	return x - area.center[1], z - area.center[3]
end

function Swim.Inside(x: number, y: number, z: number, area, slack: number?): boolean
	local s = slack or 0
	local dx, dz = flat(x, z, area)
	if dx * dx + dz * dz > (area.radius + s) ^ 2 then
		return false
	end
	return y >= area.floorY - s and y <= area.surfaceY + s
end

function Swim.Clamp(x: number, y: number, z: number, area, margin: number): (number, number, number, boolean, boolean)
	local hitY, hitEdge = false, false
	local low, high = area.floorY + margin, area.surfaceY - margin
	if y < low then
		y, hitY = low, true
	elseif y > high then
		y, hitY = high, true
	end
	local dx, dz = flat(x, z, area)
	local r = area.radius - margin
	local d = sqrt(dx * dx + dz * dz)
	if d > r and d > 0 then
		x = area.center[1] + dx / d * r
		z = area.center[3] + dz / d * r
		hitEdge = true
	end
	return x, y, z, hitY, hitEdge
end

-- rideSpeed: the mount's riding speed (session.Riding.speed); only a swimmer mount uses it.
function Swim.Speed(riding: boolean, swims: boolean, rideSpeed: number?, cfg): number
	if riding and swims then
		local ride = tonumber(rideSpeed) or 0
		return math.max(ride * cfg.mountFactor, cfg.speed * cfg.mountMin)
	end
	return cfg.speed
end

-- mx, mz: the flat move direction (length 0..1, e.g. Humanoid.MoveDirection); vertical: -1..1
-- from the ascend / descend buttons; lookY: the camera's look vector Y (-1..1).
function Swim.Target(mx: number, mz: number, vertical: number, lookY: number, speed: number, cfg): (number, number, number)
	local m = sqrt(mx * mx + mz * mz)
	if m > 1 then
		mx, mz, m = mx / m, mz / m, 1
	end
	local scale = speed / cfg.speed -- a fast mount climbs faster too
	local vy
	if math.abs(vertical) > cfg.inputSlack then
		vy = clamp(vertical, -1, 1) * cfg.vertical * scale
	elseif m > cfg.inputSlack then
		vy = clamp(lookY, -1, 1) * cfg.pitchFollow * speed * m
	else
		vy = cfg.buoyancy
	end
	return mx * speed, vy, mz * speed
end

function Swim.Approach(v: number, target: number, rate: number, dt: number): number
	return v + (target - v) * (1 - exp(-rate * dt))
end

function Swim.Step(state, tx: number, ty: number, tz: number, dt: number, cfg, area)
	local pushing = (tx * tx + tz * tz) > 0.01 or math.abs(ty) > cfg.buoyancy + 0.01
	local rate = if pushing then cfg.accel else cfg.drag
	state.vx = Swim.Approach(state.vx, tx, rate, dt)
	state.vy = Swim.Approach(state.vy, ty, rate, dt)
	state.vz = Swim.Approach(state.vz, tz, rate, dt)
	local x, y, z, hitY, hitEdge = Swim.Clamp(state.x + state.vx * dt, state.y + state.vy * dt, state.z + state.vz * dt, area, cfg.margin)
	if hitY then
		state.vy = 0
	end
	if hitEdge then
		-- Keep only the part of the velocity along the wall.
		local nx, nz = flat(x, z, area)
		local d = sqrt(nx * nx + nz * nz)
		if d > 0 then
			nx, nz = nx / d, nz / d
			local out = state.vx * nx + state.vz * nz
			if out > 0 then
				state.vx -= out * nx
				state.vz -= out * nz
			end
		end
	end
	state.x, state.y, state.z = x, y, z
	return state
end

function Swim.Heading(vx: number, vz: number, previous: number): number
	if vx * vx + vz * vz < 0.25 then
		return previous
	end
	return atan2(-vx, -vz)
end

function Swim.Tilt(vx: number, vy: number, vz: number, speed: number, maxDegrees: number): number
	if speed <= 0 then
		return 0
	end
	local h = sqrt(vx * vx + vz * vz)
	local lean = clamp(h / speed, 0, 1) -- forward lean with speed
	local climb = clamp(vy / speed, -1, 1) -- nose up climbing, down diving
	return rad(maxDegrees) * clamp(-lean + climb * 0.5 * lean, -1, 1)
end

function Swim.Bob(t: number, bob): number
	return sin(t * (math.pi * 2) / bob.period) * bob.amplitude
end

function Swim.ClipSpeed(speed: number, cfg): number
	return speed * cfg.clipRate
end

return Swim
