--!strict
-- Strays: a cat (or dog, or chicken) that wanders by its home spot, trails a passing
-- townsperson a while, gives up, sits, and walks home before its time bucket ends.
--
-- One episode per bucket, fixed `tick`, starting and ending at the stray's home point, so the
-- position is a pure function of (seed, stray id, bucket, the people's positions at the tick
-- times). People come from `env.people(t)` (Life is deterministic), so every client sees the
-- same cat follow the same person. Speed never exceeds `speed`; the leash (time left versus the
-- walk home) is checked every tick, so the cat is always home when the bucket turns.

local Rules = require("./Rules")

local Stray = {}

local TAU = math.pi * 2

local function roll(W: any, range: { number }, ...: any): number
	return range[1] + W.rng(Rules.hash(W.seed, ...)):next() * (range[2] - range[1])
end

function Stray.home(W: any, u: any, i: number): any
	local sp = u.spot
	if type(sp.points) == "table" and #sp.points > 0 then
		local pt = sp.points[(i - 1) % #sp.points + 1]
		return { x = pt.x, y = pt.y, z = pt.z }
	end
	local rng = W.rng(Rules.hash(W.seed, u.id, i, "home"))
	local r = (sp.radius or 2) * 0.5 * rng:next()
	local a = rng:next() * TAU
	return { x = sp.x + math.cos(a) * r, y = sp.y, z = sp.z + math.sin(a) * r }
end

function Stray.start(W: any, u: any, n: number, b: number): any
	local k = u.k
	local start = b * k.bucket
	local st: any = { u = u, k = k, b = b, start = start, stop = start + k.bucket, h = k.tick, T = start, ticks = 0, a = {} }
	for i = 1, n do
		local home = Stray.home(W, u, i)
		st.a[i] = {
			i = i,
			home = home,
			p = { x = home.x, y = home.y, z = home.z },
			q = { x = home.x, y = home.y, z = home.z },
			yaw = roll(W, { -math.pi, math.pi }, u.id, i, "yaw", b),
			mode = "wander",
			moving = false,
			lookAt = start + roll(W, k.follow.after, u.id, i, "after", b),
			follows = 0,
		}
	end
	return st
end

local function dist(a: any, b: any): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Moves toward target at most speed * h; returns true when it arrived.
local function moveTo(ag: any, target: any, speed: number, h: number): boolean
	local dx, dy, dz = target.x - ag.p.x, target.y - ag.p.y, target.z - ag.p.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	local step = speed * h
	if dx * dx + dz * dz > 1e-8 then
		ag.yaw = math.atan2(-dx, -dz)
	end
	if d <= step then
		ag.p = { x = target.x, y = target.y, z = target.z }
		ag.moving = d > 1e-6
		return true
	end
	ag.p = { x = ag.p.x + dx / d * step, y = ag.p.y + dy / d * step, z = ag.p.z + dz / d * step }
	ag.moving = true
	return false
end

local function findPerson(list: { any }, id: any): any?
	for _, p in list do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function tick(W: any, st: any, T: number)
	local k, h = st.k, st.h
	local f = k.follow
	local remaining = st.stop - T
	local people: { any }? = nil
	local function peopleNow(): { any }
		if people == nil then
			people = W.peopleAt(T)
		end
		return people :: { any }
	end
	for _, ag in st.a do
		ag.q = { x = ag.p.x, y = ag.p.y, z = ag.p.z }
		local dh = dist(ag.p, ag.home)
		local need = dh / k.speed + k.margin + 2 * h
		if ag.mode ~= "home" and ag.mode ~= "wander" and need >= remaining then
			ag.mode = "home"
			ag.target = nil
		end
		if ag.mode == "follow" then
			local person = findPerson(peopleNow(), ag.target)
			local give = person == nil or person.visible == false or T >= ag.followUntil
			if not give and person then
				local dp = dist(ag.p, person)
				if dp > f.giveUp then
					give = true
				else
					if dp > f.trail then
						local tp = {
							x = person.x + (ag.p.x - person.x) / dp * f.trail,
							y = person.y,
							z = person.z + (ag.p.z - person.z) / dp * f.trail,
						}
						moveTo(ag, tp, k.speed, h)
					else
						ag.moving = false
					end
				end
			end
			if give then
				ag.target = nil
				local slack = remaining - dh / k.speed - k.margin - 2 * h
				local sit = math.min(roll(W, k.sit, st.u.id, ag.i, "sit", st.b, ag.follows), slack)
				if sit >= 1 then
					ag.mode = "sit"
					ag.sitUntil = T + sit
				else
					ag.mode = "home"
				end
				ag.moving = false
			end
		elseif ag.mode == "sit" then
			ag.moving = false
			if T >= ag.sitUntil then
				ag.mode = "home"
			end
		elseif ag.mode == "home" then
			if moveTo(ag, ag.home, k.speed, h) then
				ag.mode = "wander"
				ag.lookAt = T + f.lookEvery
			end
		elseif ag.mode == "wander" then
			local last = (2 * k.wanderRadius) / k.wanderSpeed + k.margin + 2 * h
			local target
			if remaining <= last then
				target = ag.home
			else
				local slot = math.floor((T - st.start) / 8)
				local rng = W.rng(Rules.hash(W.seed, st.u.id, ag.i, "wander", st.b, slot))
				if rng:next() < 0.5 then
					target = nil -- a sitting slot
				else
					local a, r = rng:next() * TAU, rng:next() * k.wanderRadius
					target = { x = ag.home.x + math.cos(a) * r, y = ag.home.y, z = ag.home.z + math.sin(a) * r }
				end
			end
			if target then
				moveTo(ag, target, k.wanderSpeed, h)
			else
				ag.moving = false
			end
			if T >= ag.lookAt and remaining > need + f.seconds[1] then
				ag.lookAt = T + f.lookEvery
				local best, bestD = nil, f.radius
				for _, p in peopleNow() do
					if p.visible ~= false then
						local d = dist(ag.p, p)
						if d < bestD or (d == bestD and best and tostring(p.id) < tostring(best.id)) then
							best, bestD = p, d
						end
					end
				end
				if best then
					ag.mode = "follow"
					ag.target = best.id
					ag.follows += 1
					ag.followUntil = T + roll(W, f.seconds, st.u.id, ag.i, "follow", st.b, ag.follows)
				end
			end
		end
	end
end

function Stray.advance(W: any, st: any, t: number)
	local h = st.h
	local limit = math.min(t, st.stop)
	while st.T + h <= limit + 1e-9 do
		st.ticks += 1
		local T = st.start + st.ticks * h
		tick(W, st, T)
		st.T = T
	end
end

function Stray.poses(st: any, t: number, emit: (ag: any, x: number, y: number, z: number, yaw: number, state: string, moving: boolean) -> ())
	local alpha = math.clamp((t - st.T) / st.h, 0, 1)
	for _, ag in st.a do
		local x = ag.q.x + (ag.p.x - ag.q.x) * alpha
		local y = ag.q.y + (ag.p.y - ag.q.y) * alpha
		local z = ag.q.z + (ag.p.z - ag.q.z) * alpha
		emit(ag, x, y, z, ag.yaw, ag.mode, ag.moving)
	end
end

return Stray
