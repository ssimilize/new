--!strict
-- Flocks: a plan per (flock, time bucket) and a fixed-tick boids simulation of it.
--
-- The plan is a pure function of (seed, flock id, bucket, clock): whether the flock is out, its
-- size, the free perch points it lands on (claimed in flock-id order so two flocks never share a
-- point), when it arrives, when it takes off, and where it roosts. The simulation starts at the
-- bucket start and steps at `tick` seconds using only + - * / and sqrt, so any client that
-- replays it lands the same birds on the same roof at the same time. A player-caused scatter is
-- local: that flock then diverges on that client until its next bucket (pose.diverged).

local Rules = require("./Rules")

local Flock = {}

local TAU = math.pi * 2

-- Claims -------------------------------------------------------------------------------------

local function baseKey(u: any, b: number): string
	return u.id .. "@" .. b
end

-- The flock's own conditions for a day episode in bucket b (phase, season, weather, chance).
local function dayWanted(W: any, u: any, b: number): boolean
	local memo = W.wanted
	local key = baseKey(u, b)
	local v = memo[key]
	if v ~= nil then
		return v
	end
	local k = u.k
	local start = b * k.bucket
	local ok = k._phases[W.phaseAt(start)] == true and not k._roost[W.phaseAt(start)]
	local season = if ok and (k._seasons or u.entry.seasons) then W.seasonAt(start) else nil
	if season ~= nil then -- no season from the env: no season gate
		if k._seasons and not k._seasons[season] then
			ok = false
		end
		if u.entry.seasons and not table.find(u.entry.seasons, season) then
			ok = false
		end
	end
	if ok and W.wet(k, start) then
		ok = false
	end
	if ok then
		local chance = k.chance * (u.entry.chance or 1)
		ok = W.rng(Rules.hash(W.seed, u.id, "chance", b)):next() < chance
	end
	memo[key] = ok
	return ok
end

function Flock.size(W: any, u: any): number
	if u.size == nil then
		local lo, hi = u.k.flock[1], u.k.flock[2]
		local c = u.entry.count
		if type(c) == "table" then
			lo, hi = c[1], c[2]
		elseif type(c) == "number" and c >= 1 then
			lo, hi = c, c
		end
		u.size = W.rng(Rules.hash(W.seed, u.id, "size")):int(math.max(1, lo), math.max(1, hi))
	end
	return u.size :: number
end

-- Picks `size` free points: a seeded window of the home spot's free points when they fit
-- (birds on one ridge sit together), else the nearest free points.
local function pick(W: any, u: any, cands: { any }, taken: { [string]: boolean }, size: number, salt: any): { any }?
	local home, other = {}, {}
	for _, pt in cands do
		if not taken[pt.key] then
			table.insert(if pt.d < 0 then home else other, pt)
		end
	end
	if #home + #other < size then
		return nil
	end
	if #home >= size then
		local off = W.rng(Rules.hash(W.seed, u.id, "window", salt)):int(0, #home - size)
		return table.move(home, off + 1, off + size, 1, {})
	end
	local out = table.clone(home)
	for i = 1, size - #home do
		table.insert(out, other[i])
	end
	return out
end

-- Iterative (no recursion: a town of roofs can chain thousands of flocks): a flock's claims
-- need the claims of its lower-id neighbours first.
local function solve(W: any, u: any, memo: { [string]: any }, keyOf: (any) -> string, wanted: (any) -> boolean, candField: string, lowerField: string, salt: any)
	local stack = { u }
	while #stack > 0 do
		local top = stack[#stack]
		local key = keyOf(top)
		if memo[key] ~= nil then
			table.remove(stack)
			continue
		end
		Rules.flockInfo(W.idx, top)
		local want = wanted(top)
		local pending = false
		if want then
			for _, v in top[lowerField] do
				if memo[keyOf(v)] == nil then
					table.insert(stack, v)
					pending = true
				end
			end
		end
		if not pending then
			table.remove(stack)
			if not want then
				memo[key] = false
			else
				local taken = {}
				for _, v in top[lowerField] do
					local c = memo[keyOf(v)]
					if c then
						for _, pt in c do
							taken[pt.key] = true
						end
					end
				end
				memo[key] = pick(W, top, top[candField], taken, Flock.size(W, top), salt) or false
			end
		end
	end
	return memo[keyOf(u)]
end

function Flock.dayClaims(W: any, u: any, b: number): { any }?
	local c = solve(W, u, W.claims, function(v)
		return baseKey(v, b)
	end, function(v)
		return dayWanted(W, v, b)
	end, "cands", "lower", b)
	return c or nil
end

function Flock.roostClaims(W: any, u: any): { any }?
	local c = solve(W, u, W.roosts, function(v)
		return v.id
	end, function(v)
		return next(v.k._roost) ~= nil
	end, "roostCands", "lowerRoost", "roost")
	return c or nil
end

local function modeOf(W: any, u: any, b: number): string
	local k = u.k
	local start = b * k.bucket
	if k._roost[W.phaseAt(start)] then
		return if Flock.roostClaims(W, u) then "roost" else "none"
	end
	return if Flock.dayClaims(W, u, b) then "day" else "none"
end

-- Plan ----------------------------------------------------------------------------------------

export type Plan = {
	u: any,
	b: number,
	start: number,
	stop: number,
	mode: string,
	prevRoost: boolean,
	size: number,
	claims: { any }?,
	roost: { any }?,
	arriveAt: number,
	takeoffAt: number,
	departRoost: number,
	sky: { x: number, y: number, z: number },
	exit: { x: number, y: number, z: number },
	home: { x: number, y: number, z: number },
	stagger: { number },
}

function Flock.plan(W: any, u: any, b: number): Plan?
	local k = u.k
	local mode = modeOf(W, u, b)
	local prevRoost = modeOf(W, u, b - 1) == "roost"
	if mode == "none" and not prevRoost then
		return nil
	end
	local start = b * k.bucket
	local rng = W.rng(Rules.hash(W.seed, u.id, "plan", b))
	local size = Flock.size(W, u)
	local claims = if mode == "day" then Flock.dayClaims(W, u, b) elseif mode == "roost" then Flock.roostClaims(W, u) else nil
	local roost = if prevRoost then Flock.roostClaims(W, u) else nil
	local ref = claims or roost or {}
	local hx, hy, hz = 0, 0, 0
	for _, pt in ref do
		hx += pt.x
		hy += pt.y
		hz += pt.z
	end
	local n = math.max(1, #ref)
	local home = { x = hx / n, y = hy / n, z = hz / n }
	local a1 = rng:next() * TAU
	local a2 = a1 + math.pi * (0.5 + rng:next())
	local arrive = k.arrive[1] + rng:next() * (k.arrive[2] - k.arrive[1])
	local frac = k.perch[1] + rng:next() * (k.perch[2] - k.perch[1])
	local depart = k.arrive[1] + rng:next() * (k.arrive[2] - k.arrive[1])
	local stagger = {}
	for i = 1, size do
		stagger[i] = rng:next() * 1.2
	end
	return {
		u = u,
		b = b,
		start = start,
		stop = start + k.bucket,
		mode = mode,
		prevRoost = prevRoost,
		size = size,
		claims = claims,
		roost = roost,
		arriveAt = start + arrive,
		takeoffAt = start + frac * k.bucket,
		departRoost = start + depart,
		sky = { x = home.x + math.cos(a1) * k.approach, y = home.y + k.height, z = home.z + math.sin(a1) * k.approach },
		exit = { x = home.x + math.cos(a2) * k.approach, y = home.y + k.height, z = home.z + math.sin(a2) * k.approach },
		home = home,
		stagger = stagger,
	}
end

-- Simulation ----------------------------------------------------------------------------------

local function v3(x: number, y: number, z: number): any
	return { x = x, y = y, z = z }
end

local function pt3(p: any): any
	return { x = p.x, y = p.y, z = p.z, key = p.key }
end

function Flock.start(W: any, u: any, plan: Plan): any
	local k = u.k
	local st: any = {
		u = u,
		k = k,
		plan = plan,
		h = k.tick,
		T = plan.start,
		ticks = 0,
		a = {},
		diverged = false,
		wetDone = false,
		nextWeather = plan.start,
	}
	local gap = math.max(2 * k.minSep, k.spread)
	local dx, dz = plan.home.x - plan.sky.x, plan.home.z - plan.sky.z
	local dl = math.sqrt(dx * dx + dz * dz)
	local ux, uz = if dl > 0 then dx / dl else 1, if dl > 0 then dz / dl else 0
	for i = 1, plan.size do
		local ag: any = { i = i, mode = "gone", queue = {}, yaw = 0, v = v3(0, 0, 0), leftAt = -math.huge }
		local exit = { kind = "exit", point = plan.exit }
		if plan.prevRoost and plan.roost then
			local r = plan.roost[i]
			ag.p = pt3(r)
			ag.mode = "perch"
			ag.roosting = true
			ag.perchKey = r.key
			if plan.mode == "day" and plan.claims then
				ag.queue = {
					{ goal = { kind = "land", point = pt3(plan.claims[i]) }, at = plan.departRoost + plan.stagger[i] },
					{ goal = exit, at = plan.takeoffAt + plan.stagger[i] },
				}
			elseif plan.mode == "none" then
				ag.queue = { { goal = exit, at = plan.departRoost + plan.stagger[i] } }
			end
		elseif plan.claims then
			local col, row = (i - 1) % 4, (i - 1) // 4
			local ox, oz = (col - 1.5) * gap, row * gap
			-- offsets across (ox) and along (oz) the approach direction
			ag.p = v3(plan.sky.x + ox * -uz - oz * ux, plan.sky.y + row * gap * 0.3, plan.sky.z + ox * ux - oz * uz)
			ag.mode = "sky"
			ag.startAt = plan.arriveAt
			ag.goal = { kind = "land", point = pt3(plan.claims[i]) }
			ag.roostGoal = plan.mode == "roost"
			ag.v = v3(ux * k.speed * 0.8, 0, uz * k.speed * 0.8)
			if plan.mode == "day" then
				ag.queue = { { goal = exit, at = plan.takeoffAt + plan.stagger[i] } }
			end
		end
		ag.q = v3(ag.p.x, ag.p.y, ag.p.z)
		st.a[i] = ag
	end
	return st
end

local function flatAway(ax: number, az: number, fx: number, fz: number, i: number): (number, number)
	local dx, dz = ax - fx, az - fz
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1e-6 then
		local ang = i * 2.399963
		return math.cos(ang), math.sin(ang)
	end
	return dx / d, dz / d
end

local function takeoff(st: any, ag: any, goal: any, T: number)
	ag.mode = "fly"
	ag.goal = goal
	ag.leftAt = T
	ag.roosting = false
	ag.perchKey = nil
	ag.roostGoal = false
	ag.v = v3(ag.v.x, math.max(ag.v.y, st.k.speed * 0.4), ag.v.z)
end

-- Everything that makes the flock leave now (rain, a flee with nowhere to land).
local function leaveAll(st: any, T: number, goal: any)
	for _, ag in st.a do
		ag.queue = {}
		if ag.mode == "perch" then
			takeoff(st, ag, goal, T + 0)
		elseif ag.mode == "fly" then
			ag.goal = goal
		elseif ag.mode == "sky" then
			ag.mode = "gone"
		end
	end
end

-- Other flocks' claims this bucket (lower and higher ids), for a local re-landing.
local function othersTaken(W: any, st: any): { [string]: boolean }
	local u = st.u
	local taken = {}
	for _, sp in W.idx.query(u.spot.x, u.spot.z, 2 * u.k.range + 1) do
		for _, v in W.idx.bySpot[sp.id] or {} do
			if v.kind == u.kind and v.id ~= u.id then
				local c = Flock.dayClaims(W, v, st.plan.b)
				for _, pt in c or {} do
					taken[pt.key] = true
				end
				if st.plan.mode == "roost" then
					for _, pt in Flock.roostClaims(W, v) or {} do
						taken[pt.key] = true
					end
				end
			end
		end
	end
	return taken
end

local function scatter(W: any, st: any, T: number, fx: number, fz: number)
	local k = st.k
	st.diverged = true
	st.fleeUntil = T + k.fleeSeconds
	st.fleeFrom = { x = fx, z = fz }
	for _, ag in st.a do
		if ag.mode == "perch" or ag.mode == "fly" then
			local ux, uz = flatAway(ag.p.x, ag.p.z, fx, fz, ag.i)
			local goal = { kind = "flee", point = v3(ag.p.x + ux * k.fleeDistance, ag.p.y + 6, ag.p.z + uz * k.fleeDistance) }
			if ag.mode == "perch" then
				ag.v = v3(ux * k.speed * 0.6, k.speed * 0.5, uz * k.speed * 0.6)
			end
			ag.mode = "fly"
			ag.goal = goal
			ag.leftAt = T
			ag.perchKey = nil
			ag.roosting = false
			ag.queue = {}
			ag.fleeing = true
		end
	end
end

local function afterFlee(W: any, st: any, T: number)
	local k, plan = st.k, st.plan
	st.fleeUntil = nil
	local live = {}
	local cx, cy, cz = 0, 0, 0
	for _, ag in st.a do
		ag.fleeing = false
		if ag.mode == "fly" then
			table.insert(live, ag)
			cx += ag.p.x
			cy += ag.p.y
			cz += ag.p.z
		end
	end
	if #live == 0 then
		return
	end
	cx, cy, cz = cx / #live, cy / #live, cz / #live
	local taken = othersTaken(W, st)
	local cands = if plan.mode == "roost" then st.u.roostCands else st.u.cands
	local free = {}
	local ff = st.fleeFrom
	for _, pt in cands or {} do
		local dx, dz = pt.x - ff.x, pt.z - ff.z
		if not taken[pt.key] and dx * dx + dz * dz > k.fleeDistance * k.fleeDistance then
			local ex, ey, ez = pt.x - cx, pt.y - cy, pt.z - cz
			table.insert(free, { pt = pt, d = ex * ex + ey * ey + ez * ez })
		end
	end
	table.sort(free, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.pt.key < b.pt.key
	end)
	local stillTime = plan.mode == "roost" or T < plan.takeoffAt - k.leaveSeconds
	if #free >= #live and stillTime then
		for i, ag in live do
			ag.goal = { kind = "land", point = pt3(free[i].pt) }
			ag.roostGoal = plan.mode == "roost"
			if plan.mode == "day" then
				ag.queue = { { goal = { kind = "exit", point = plan.exit }, at = plan.takeoffAt + plan.stagger[ag.i] } }
			end
		end
		return
	end
	leaveAll(st, T, { kind = "exit", point = plan.exit })
	local back = k.returnAfter[1] + W.rng(Rules.hash(W.seed, st.u.id, "back", plan.b, st.ticks)):next() * (k.returnAfter[2] - k.returnAfter[1])
	if plan.mode == "day" and T + back < plan.takeoffAt - k.leaveSeconds then
		st.backAt = T + back
	end
end

-- Re-arrival after a scatter-and-leave: back to the plan's own perches (re-syncs the landing).
local function comeBack(st: any)
	local plan = st.plan
	st.backAt = nil
	for _, ag in st.a do
		if ag.mode == "gone" and plan.claims then
			ag.p = v3(plan.sky.x + (ag.i - 1) * 2 * st.k.minSep, plan.sky.y, plan.sky.z)
			ag.q = v3(ag.p.x, ag.p.y, ag.p.z)
			ag.v = v3(0, 0, 0)
			ag.mode = "fly"
			ag.leftAt = -math.huge
			ag.goal = { kind = "land", point = pt3(plan.claims[ag.i]) }
			ag.queue = { { goal = { kind = "exit", point = plan.exit }, at = plan.takeoffAt + plan.stagger[ag.i] } }
		end
	end
end

local function tick(W: any, st: any, T: number)
	local k, h, plan = st.k, st.h, st.plan
	local a = st.a
	for _, ag in a do
		ag.q.x, ag.q.y, ag.q.z = ag.p.x, ag.p.y, ag.p.z
	end
	-- weather: once a second on the shared clock, rain sends a day flock away
	if T >= st.nextWeather then
		st.nextWeather = T + 1
		if plan.mode == "day" and not st.wetDone and W.wet(k, T) then
			st.wetDone = true
			leaveAll(st, T, { kind = "exit", point = plan.exit })
		end
	end
	if st.pendingScare then
		local s = st.pendingScare
		st.pendingScare = nil
		scatter(W, st, T, s.x, s.z)
	end
	if st.fleeUntil and T >= st.fleeUntil then
		afterFlee(W, st, T)
	end
	if st.backAt and T >= st.backAt then
		comeBack(st)
	end
	local flying = 0
	for _, ag in a do
		if ag.mode == "sky" and T >= ag.startAt then
			ag.mode = "fly"
			ag.leftAt = -math.huge
		elseif ag.mode == "perch" and #ag.queue > 0 and T >= ag.queue[1].at then
			local nxt = table.remove(ag.queue, 1)
			takeoff(st, ag, nxt.goal, T)
		end
		if ag.mode == "fly" then
			flying += 1
		end
	end
	if flying == 0 then
		return
	end
	-- boids for the flying members
	local w = k.weights
	local view2 = k.view * k.view
	local sepR = k.minSep * 3
	local sepR2 = sepR * sepR
	for _, ag in a do
		if ag.mode ~= "fly" then
			continue
		end
		local p, v = ag.p, ag.v
		local sx, sy, sz, ax, ay, az, cx, cy, cz, n = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
		for _, o in a do
			if o ~= ag and (o.mode == "fly" or o.mode == "perch") then
				local dx, dy, dz = p.x - o.p.x, p.y - o.p.y, p.z - o.p.z
				local d2 = dx * dx + dy * dy + dz * dz
				if d2 < sepR2 and d2 > 1e-12 then
					sx += dx / d2
					sy += dy / d2
					sz += dz / d2
				end
				if o.mode == "fly" and d2 < view2 then
					ax += o.v.x
					ay += o.v.y
					az += o.v.z
					cx += o.p.x
					cy += o.p.y
					cz += o.p.z
					n += 1
				end
			end
		end
		local g = ag.goal.point
		local tx, ty, tz = g.x - p.x, g.y - p.y, g.z - p.z
		local d = math.sqrt(tx * tx + ty * ty + tz * tz)
		local landing = ag.goal.kind == "land"
		local want = if landing then k.speed * math.min(1, d / k.slow) else k.speed
		local fx, fy, fz = 0, 0, 0
		if d > 1e-9 then
			fx, fy, fz = (tx / d * want - v.x) * w.goal, (ty / d * want - v.y) * w.goal, (tz / d * want - v.z) * w.goal
		end
		-- near its perch a bird trusts the hard separation below (the soft push would hold it
		-- off a point next to a perched neighbour)
		local near = landing and d < k.slow
		if not near then
			fx += sx * w.separation
			fy += sy * w.separation
			fz += sz * w.separation
		end
		if n > 0 then
			local wa = if near then 0 else w.alignment
			local wc = if near then 0 else w.cohesion
			fx += (ax / n - v.x) * wa + (cx / n - p.x) * wc
			fy += (ay / n - v.y) * wa + (cy / n - p.y) * wc
			fz += (az / n - v.z) * wa + (cz / n - p.z) * wc
		end
		local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
		if fl > k.maxAccel then
			fx, fy, fz = fx / fl * k.maxAccel, fy / fl * k.maxAccel, fz / fl * k.maxAccel
		end
		ag.nv = v3(v.x + fx * h, v.y + fy * h, v.z + fz * h)
		ag.nd = d
	end
	for _, ag in a do
		if ag.mode ~= "fly" then
			continue
		end
		local v = ag.nv
		local s = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
		local landing = ag.goal.kind == "land"
		if s > k.speed then
			v.x, v.y, v.z = v.x / s * k.speed, v.y / s * k.speed, v.z / s * k.speed
			s = k.speed
		elseif s > 1e-9 and s < k.minSpeed and not (landing and ag.nd < k.slow) then
			v.x, v.y, v.z = v.x / s * k.minSpeed, v.y / s * k.minSpeed, v.z / s * k.minSpeed
			s = k.minSpeed
		end
		ag.v = v
		local g = ag.goal.point
		if landing and ag.nd <= math.max(k.landDist, s * h) then
			ag.p = v3(g.x, g.y, g.z)
			ag.mode = "perch"
			ag.perchKey = g.key
			ag.roosting = ag.roostGoal == true
			ag.v = v3(0, 0, 0)
			if s > 1e-6 then
				ag.yaw = math.atan2(-v.x, -v.z)
			end
		elseif ag.goal.kind == "exit" and ag.nd <= math.max(4, s * h) then
			ag.mode = "gone"
		else
			ag.p = v3(ag.p.x + v.x * h, ag.p.y + v.y * h, ag.p.z + v.z * h)
			if v.x * v.x + v.z * v.z > 1e-6 then
				ag.yaw = math.atan2(-v.x, -v.z)
			end
		end
	end
	-- hard separation: fliers step out of each other's way (perched birds never move)
	local min = k.minSep
	for _ = 1, 3 do
		for i = 1, #a do
			local ai = a[i]
			if ai.mode ~= "fly" and ai.mode ~= "perch" then
				continue
			end
			for j = i + 1, #a do
				local aj = a[j]
				if aj.mode ~= "fly" and aj.mode ~= "perch" then
					continue
				end
				if ai.mode == "perch" and aj.mode == "perch" then
					continue
				end
				local dx, dy, dz = aj.p.x - ai.p.x, aj.p.y - ai.p.y, aj.p.z - ai.p.z
				local d = math.sqrt(dx * dx + dy * dy + dz * dz)
				if d < min then
					local push = min * 1.05 - d -- a little over, so the drawn in-between frames stay clear too
					local ux, uy, uz
					if d < 1e-9 then
						local ang = (i + j) * 2.399963
						ux, uy, uz = math.cos(ang), 0, math.sin(ang)
					else
						ux, uy, uz = dx / d, dy / d, dz / d
					end
					if ai.mode == "perch" then
						aj.p = v3(aj.p.x + ux * push, aj.p.y + uy * push, aj.p.z + uz * push)
					elseif aj.mode == "perch" then
						ai.p = v3(ai.p.x - ux * push, ai.p.y - uy * push, ai.p.z - uz * push)
					else
						local hp = push / 2
						ai.p = v3(ai.p.x - ux * hp, ai.p.y - uy * hp, ai.p.z - uz * hp)
						aj.p = v3(aj.p.x + ux * hp, aj.p.y + uy * hp, aj.p.z + uz * hp)
					end
				end
			end
		end
	end
end

-- Steps the simulation to the last tick at or before t.
function Flock.advance(W: any, st: any, t: number)
	local h = st.h
	local target = st.plan.start + math.floor((t - st.plan.start) / h + 1e-9) * h
	local limit = math.min(target, st.plan.stop)
	while st.T + h <= limit + 1e-9 do
		st.ticks += 1
		local T = st.plan.start + st.ticks * h
		tick(W, st, T)
		st.T = T
	end
end

-- A running mover near a perched member (or one about to land) scatters the whole flock.
function Flock.checkScare(st: any, scarers: { any }, force: boolean?): boolean
	if st.fleeUntil or st.pendingScare then
		return false
	end
	local k = st.k
	local r2 = k.scare * k.scare
	for _, s in scarers do
		if force or (s.speed or 0) >= k.scareSpeed then
			local rr = if s.radius then s.radius * s.radius else r2
			for _, ag in st.a do
				if ag.mode == "perch" or (ag.mode == "fly" and ag.goal and ag.goal.kind == "land" and (ag.nd or math.huge) < k.slow) then
					local dx, dz = ag.p.x - s.x, ag.p.z - s.z
					if dx * dx + dz * dz <= rr then
						st.pendingScare = { x = s.x, z = s.z }
						return true
					end
				end
			end
		end
	end
	return false
end

-- Poses at t, drawn one tick behind: between the last two ticks, so motion is continuous.
function Flock.poses(W: any, st: any, t: number, emit: (ag: any, x: number, y: number, z: number, yaw: number, pitch: number, state: string) -> ())
	local k = st.k
	local alpha = math.clamp((t - st.T) / st.h, 0, 1)
	for _, ag in st.a do
		if ag.mode == "sky" or ag.mode == "gone" then
			continue
		end
		local x = ag.q.x + (ag.p.x - ag.q.x) * alpha
		local y = ag.q.y + (ag.p.y - ag.q.y) * alpha
		local z = ag.q.z + (ag.p.z - ag.q.z) * alpha
		local state
		local pitch = 0
		if ag.mode == "perch" then
			state = if ag.roosting then "roost" else "perch"
		else
			local v = ag.v
			local hs = math.sqrt(v.x * v.x + v.z * v.z)
			pitch = math.atan2(v.y, math.max(hs, 1e-6))
			if ag.fleeing then
				state = "flee"
			elseif st.T - ag.leftAt < 0.6 then
				state = "takeoff"
			elseif ag.goal.kind == "exit" then
				state = "leave"
			elseif ag.nd and ag.nd < k.slow then
				state = "land"
			else
				state = "fly"
			end
		end
		emit(ag, x, y, z, ag.yaw, pitch, state)
	end
end

return Flock
