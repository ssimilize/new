--!strict
-- Wildlife: flocks that perch on roofs and scatter, fish that jump, butterflies by day,
-- fireflies and moths by night, strays that follow people. Pure logic: the game's controller
-- only draws the poses `step` returns.
--
--   local Wildlife = require("../Wildlife/Wildlife")
--   local spec = Wildlife.spec(require("../Wildlife/tables/guildhall"), spots)
--   local env = Wildlife.envFrom({ almanac = alm, life = life, players = fn, movers = fn })
--   local wild = Wildlife.new(adapter, spec, env)          -- errors listing every problem
--   local poses = wild:step(dt, cameraPos)                   -- {x, y, z} or a Vector3 / CFrame
--   wild:disturb(x, z, radius)   wild:stats()   wild:problems()   wild:destroy()
--
-- A pose: { id, kind, unit, spot, state, anim, x, y, z, yaw, pitch, cf, mesh?, color?, glow?,
--           alpha, clip, diverged }. `cf` is the 12 numbers of CFrame.new(x, y, z, R00..R22)
--           (yaw then pitch); yaw and pitch are degrees (Life's convention: CFrame.Angles(0,
--           math.rad(yaw), 0).LookVector is the way the critter faces).

local Contract = require("../Contract/Contract")
local Rules = require("./Rules")
local Flock = require("./Flock")
local Stray = require("./Stray")

local Wildlife = {}
Wildlife.Rules = Rules
Wildlife.Flock = Flock
Wildlife.Stray = Stray
Wildlife.hash = Rules.hash
Wildlife.validate = Rules.validate

local TAU = math.pi * 2

export type Pose = {
	id: string,
	kind: string,
	unit: string,
	spot: string,
	state: string,
	anim: string,
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	cf: { number },
	mesh: string?,
	color: string?,
	glow: number?,
	alpha: number,
	clip: number,
	diverged: boolean,
}

-- Helpers ---------------------------------------------------------------------------------------

-- CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0), as 12 numbers.
function Wildlife.cframe(x: number, y: number, z: number, yaw: number, pitch: number): { number }
	local c, s = math.cos(yaw), math.sin(yaw)
	local cb, sb = math.cos(pitch), math.sin(pitch)
	return { x, y, z, c, s * sb, s * cb, 0, cb, -sb, -s, c * sb, c * cb }
end

-- The Ranch's night curve (Logic/Ambience.Night): 0 by day .. 1 at night.
local function ramp(x: number, from: number, to: number): number
	if to == from then
		return if x >= to then 1 else 0
	end
	local p = math.clamp((x - from) / (to - from), 0, 1)
	return p * p * (3 - 2 * p)
end

function Wildlife.night(clock: number, on: { number }, off: { number }): number
	local c = clock % 24
	if c >= off[1] and c <= off[2] then
		return 1 - ramp(c, off[1], off[2])
	elseif c >= on[1] and c <= on[2] then
		return ramp(c, on[1], on[2])
	elseif c > off[2] and c < on[1] then
		return 0
	end
	return 1
end

-- The scare rule: a mover at `speed` (studs/s) scatters a bird within `scare` studs (flat)
-- when it runs (speed >= scareSpeed). Walking past is fine.
function Wildlife.scared(bx: number, bz: number, mx: number, mz: number, speed: number, rule: any): boolean
	if speed < rule.scareSpeed then
		return false
	end
	local dx, dz = bx - mx, bz - mz
	return dx * dx + dz * dz <= rule.scare * rule.scare
end

function Wildlife.spec(tbl: any, spots: { any }?, extra: { [string]: any }?): any
	local s = Rules.copy(tbl)
	if spots then
		s.spots = spots
	end
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

local function xyzOf(p: any): (number, number, number)
	if type(p) == "table" then
		if p.pos then
			return p.pos.x or p.pos.X, p.pos.y or p.pos.Y or 0, p.pos.z or p.pos.Z
		end
		if p.x ~= nil then
			return p.x, p.y or 0, p.z
		end
	end
	local q = p
	if typeof(q) == "CFrame" then
		q = q.Position
	end
	return q.X, q.Y, q.Z
end

-- An env from an Almanac and a Life (duck-typed: alm:at(t), life:at(t)) plus game callbacks.
function Wildlife.envFrom(o: any): any
	local alm, life = o.almanac, o.life
	local rainKinds = Rules.set(o.rainKinds or { "rain", "thunderstorm", "storm" })
	local env: any = {}
	local lastT, lastSnap = nil, nil
	local function snap(t: number): any
		if t ~= lastT then
			lastT, lastSnap = t, alm:at(t)
		end
		return lastSnap
	end
	if alm then
		env.phase = function(t: number)
			return snap(t).phase
		end
		env.hour = function(t: number)
			return snap(t).hour
		end
		env.season = function(t: number)
			local s = snap(t).season
			return if type(s) == "table" then s.name else s
		end
		env.weather = function(t: number)
			local w = snap(t).weather
			if type(w) ~= "table" then
				return nil
			end
			local wet = rainKinds[w.kind] == true and (w.active ~= false)
			return { id = w.kind, rain = if wet then (w.intensity or 1) else 0, wind = w.wind or 0 }
		end
	end
	if life then
		env.people = function(t: number)
			return life:at(t)
		end
	end
	for _, key in { "phase", "hour", "season", "weather", "people", "players", "movers" } do
		if o[key] ~= nil then
			env[key] = o[key]
		end
	end
	return env
end

-- The world ------------------------------------------------------------------------------------

local World = {}
World.__index = World

local function capOf(v: any, q: number): number
	if type(v) == "number" then
		return v
	end
	return v[math.clamp(q, 1, 3)]
end

function Wildlife.new(adapter: Contract.Adapter, spec: any, env: any?): any
	local cp = Contract.check(adapter)
	if #cp > 0 then
		error("Wildlife.new: bad adapter: " .. table.concat(cp, "; "))
	end
	local problems = Rules.validate(spec)
	if #problems > 0 then
		error("Wildlife.new: bad spec (" .. #problems .. " problems):\n  " .. table.concat(problems, "\n  "))
	end
	local s = Rules.normalise(spec)
	local e = env or {}
	local self: any = setmetatable({}, World)
	self.adapter = adapter
	self.s = s
	self.env = e
	self.idx = Rules.index(s)
	self.sims = {}
	self.plans = {}
	self.jumps = {}
	self.startled = {}
	self.speeds = {}
	self.disturbs = {}
	self.lastStats = nil
	local seed = if type(s.seed) == "number" then s.seed else Rules.hash(s.seed)
	local phaseMemo: { [number]: string } = {}
	local phaseCount = 0
	local W: any = {
		s = s,
		idx = self.idx,
		seed = seed,
		wanted = {},
		claims = {},
		roosts = {},
		counts = {},
		agents = {},
		agentCount = 0,
	}
	W.rng = function(n: number)
		return adapter.rng(n)
	end
	W.hourAt = function(t: number): number
		if e.hour then
			return e.hour(t)
		end
		return 12
	end
	W.nightAt = function(t: number): number
		if s.dayNight.mode == "curve" then
			return Wildlife.night(W.hourAt(t), s.dayNight.on, s.dayNight.off)
		end
		local ph = W.phaseAt(t)
		return if ph == "night" then 1 elseif ph == "day" then 0 else 0.5
	end
	W.phaseAt = function(t: number): string
		local v = phaseMemo[t]
		if v then
			return v
		end
		if s.dayNight.mode == "curve" then
			v = if Wildlife.night(W.hourAt(t), s.dayNight.on, s.dayNight.off) < 0.5 then "day" else "night"
		elseif e.phase then
			v = e.phase(t)
		else
			v = "day"
		end
		phaseCount += 1
		if phaseCount > 4096 then
			table.clear(phaseMemo)
			phaseCount = 0
		end
		phaseMemo[t] = v :: string
		return v :: string
	end
	W.seasonAt = function(t: number): string?
		return if e.season then e.season(t) else nil
	end
	W.weatherAt = function(t: number): any
		return if e.weather then e.weather(t) else nil
	end
	W.wet = function(k: any, t: number): boolean
		local w = W.weatherAt(t)
		if type(w) ~= "table" then
			return false
		end
		return (w.rain or 0) > k.maxRain or k._hide[w.id or ""] == true
	end
	W.peopleAt = function(t: number): { any }
		local out = {}
		if e.people then
			for _, p in e.people(t) or {} do
				local x, y, z = xyzOf(p)
				table.insert(out, { id = p.id, x = x, y = y, z = z, visible = p.visible })
			end
		end
		return out
	end
	self.W = W
	return self
end

-- Counts ----------------------------------------------------------------------------------------

-- How many agents of a drift / swim / stray unit exist in bucket b (seeded; before gates).
local function rolled(W: any, u: any, b: number): number
	local key = u.id .. "@" .. b
	local memo = W.counts[key]
	if memo then
		return memo
	end
	local e = u.entry
	local c = e.count
	local n
	if type(c) == "table" then
		n = W.rng(Rules.hash(W.seed, u.id, "count", b)):int(c[1], c[2])
	else
		n = c or 1
	end
	local chance = (u.k.chance or 1) * (e.chance or 1)
	if chance < 1 and W.rng(Rules.hash(W.seed, u.id, "chance", b)):next() >= chance then
		n = 0
	end
	W.counts[key] = n
	return n
end

local function gated(W: any, u: any, t: number): boolean
	local k = u.k
	if next(k._phases) ~= nil and not k._phases[W.phaseAt(t)] then
		return false
	end
	local season = if k._seasons or u.entry.seasons then W.seasonAt(t) else nil
	if season ~= nil then -- no season from the env (a game without seasons): no season gate
		if k._seasons and not k._seasons[season] then
			return false
		end
		if u.entry.seasons and not table.find(u.entry.seasons, season) then
			return false
		end
	end
	if W.wet(k, t) then
		return false
	end
	return true
end

function World._plan(self: any, u: any, b: number): any
	local key = u.id .. "@" .. b
	local p = self.plans[key]
	if p == nil then
		p = Flock.plan(self.W, u, b) or false
		self.plans[key] = p
	end
	return p or nil
end

-- Agents the unit has at t (flock: its plan's size unless the whole flock has gone).
function World._count(self: any, u: any, t: number): number
	local k = u.k
	local b = math.floor(t / k.bucket)
	if k.behaviour == "flock" then
		local plan = self:_plan(u, b)
		if not plan then
			return 0
		end
		local sim = self.sims[u.id]
		if sim and sim.plan == plan and sim.T <= t then
			local live = 0
			for _, ag in sim.a do
				if ag.mode ~= "gone" then
					live += 1
				end
			end
			if live == 0 and not sim.backAt then
				return 0
			end
		end
		return plan.size
	elseif k.behaviour == "stray" then
		if not gated(self.W, u, b * k.bucket) then
			return 0
		end
		return rolled(self.W, u, b)
	end
	if not gated(self.W, u, t) then
		return 0
	end
	return rolled(self.W, u, b)
end

-- Poses per behaviour ---------------------------------------------------------------------------

-- Per-agent constants (phase seed, colour, clip offset), hashed once.
local function memoOf(W: any, k: any, id: string): any
	local m = W.agents[id]
	if m == nil then
		local color = nil
		if type(k.colors) == "table" and #k.colors > 0 then
			color = k.colors[Rules.hash(W.seed, id, "color") % #k.colors + 1]
		end
		local s = (Rules.hash(W.seed, id, "s") % 100000) / 1000
		m = { s = s, color = color, clip = s % 1 }
		W.agents[id] = m
		W.agentCount += 1
	end
	return m
end

local function seedOf(W: any, k: any, id: string): number
	return memoOf(W, k, id).s
end

function World._emit(self: any, out: { Pose }, u: any, i: number, state: string, x: number, y: number, z: number, yaw: number, pitch: number, extra: any?)
	local k = u.k
	local id = u.id .. "#" .. i
	local W = self.W
	local m = memoOf(W, k, id)
	local pose: any = {
		id = id,
		kind = u.kind,
		unit = u.id,
		spot = u.spot.id,
		state = state,
		anim = k.anims[state] or state,
		x = x,
		y = y,
		z = z,
		yaw = math.deg(yaw),
		pitch = math.deg(pitch),
		cf = Wildlife.cframe(x, y, z, yaw, pitch),
		mesh = k.mesh,
		color = m.color,
		alpha = 1,
		clip = m.clip,
		diverged = false,
	}
	if extra then
		for key, v in extra do
			pose[key] = v
		end
	end
	table.insert(out, pose)
end

local function fadeOf(self: any, u: any, i: number, t: number): number
	local k = u.k
	if (k.fade or 0) <= 0 then
		return 1
	end
	local b = math.floor(t / k.bucket)
	local start, stop = b * k.bucket, (b + 1) * k.bucket
	local a = 1
	if t - start < k.fade and rolled(self.W, u, b - 1) < i then
		a = math.min(a, (t - start) / k.fade)
	end
	if stop - t < k.fade and rolled(self.W, u, b + 1) < i then
		a = math.min(a, (stop - t) / k.fade)
	end
	return a
end

local function anchorOf(self: any, u: any, i: number): (number, number, number)
	local sp = u.spot
	if type(sp.points) == "table" and #sp.points > 0 then
		local pt = sp.points[(i - 1) % #sp.points + 1]
		return pt.x, pt.y, pt.z
	end
	if i == 1 or not sp.radius then
		return sp.x, sp.y, sp.z
	end
	local rng = self.W.rng(Rules.hash(self.W.seed, u.id, i, "anchor"))
	local a, r = rng:next() * TAU, rng:next() * sp.radius
	return sp.x + math.cos(a) * r, sp.y, sp.z + math.sin(a) * r
end

function World._drift(self: any, out: { Pose }, u: any, n: number, t: number)
	local k = u.k
	local d = k.drift
	local ph = d.phase or { 1, 1, 1.3 }
	local night = if k.glow then self.W.nightAt(t) else 0
	for i = 1, n do
		local s = seedOf(self.W, u.k, u.id .. "#" .. i)
		local ax, ay, az = anchorOf(self, u, i)
		local fx, fy, fz = d.freq[1], d.freq[2], d.freq[3]
		local x = ax + math.sin(t * fx + s * ph[1]) * d.amp
		local y = ay + d.height + math.sin(t * fy + s * ph[2]) * d.bob
		local z = az + math.cos(t * fz + s * ph[3]) * d.amp
		local vx = math.cos(t * fx + s * ph[1]) * fx * d.amp
		local vy = math.cos(t * fy + s * ph[2]) * fy * d.bob
		local vz = -math.sin(t * fz + s * ph[3]) * fz * d.amp
		local hs = math.sqrt(vx * vx + vz * vz)
		local extra: any = { alpha = fadeOf(self, u, i, t) }
		if k.glow then
			local pulse = 0.5 + 0.5 * math.sin(t * 2.2 + s * 3)
			extra.glow = pulse * pulse * night * extra.alpha
		end
		self:_emit(out, u, i, "drift", x, y, z, math.atan2(-vx, -vz), if k.glow then 0 else math.atan2(vy, math.max(hs, 1e-6)) * 0.5, extra)
	end
end

local function circle(u: any, s: number, t: number): (number, number, number, number)
	local k, sp = u.k, u.spot
	local reach = sp.radius - k.edge
	local r = math.clamp(reach * (0.45 + 0.25 * math.sin(t * 0.2 + s)), 1.5, math.max(1.5, reach))
	local a = t * (0.25 + (s % 1) * 0.15) + s * TAU
	return sp.x + math.cos(a) * r, sp.z + math.sin(a) * r, a, r
end

-- The jump a fish is in at t (seeded every `jump.every` s, or a local startle), if any.
function World._jumpOf(self: any, u: any, i: number, t: number): number?
	local j = u.k.jump
	local id = u.id .. "#" .. i
	local loc = self.jumps[id]
	if loc and t >= loc and t < loc + j.seconds then
		return loc
	end
	local jb = math.floor(t / j.every)
	local rng = self.W.rng(Rules.hash(self.W.seed, id, "jump", jb))
	if rng:next() < j.chance then
		local js = jb * j.every + rng:next() * (j.every - j.seconds)
		if t >= js and t < js + j.seconds then
			return js
		end
	end
	return nil
end

function World._swim(self: any, out: { Pose }, u: any, n: number, t: number)
	local k, sp = u.k, u.spot
	local j = k.jump
	local surface = sp.y - k.depth
	for i = 1, n do
		local id = u.id .. "#" .. i
		local s = seedOf(self.W, u.k, id)
		local x, z, a = circle(u, s, t)
		local yaw = math.atan2(math.sin(a), -math.cos(a))
		local js = self:_jumpOf(u, i, t)
		local extra = { alpha = fadeOf(self, u, i, t), diverged = self.jumps[id] ~= nil and js == self.jumps[id] }
		if js then
			local p = (t - js) / j.seconds
			local sx, sz, sa = circle(u, s, js)
			local tx, tz = -math.sin(sa), math.cos(sa)
			local jx, jz = sx + tx * j.length * p, sz + tz * j.length * p
			x, z = jx + (x - jx) * p, jz + (z - jz) * p
			local y = surface + 4 * j.height * p * (1 - p)
			local pitch = math.atan2(4 * j.height * (1 - 2 * p) / j.seconds, j.length / j.seconds)
			self:_emit(out, u, i, "jump", x, y, z, math.atan2(-tx, -tz), pitch, extra)
		else
			self:_emit(out, u, i, "swim", x, surface, z, yaw, 0, extra)
		end
	end
end

-- Something passing the water startles its nearest fish into a jump (local, with a cooldown).
function World._startle(self: any, u: any, n: number, t: number, movers: { any })
	local k, sp = u.k, u.spot
	if (self.startled[u.id] or -math.huge) > t then
		return
	end
	local reach = sp.radius + k.startle
	for _, m in movers do
		if (m.speed or 0) >= k.passSpeed then
			local dx, dz = m.x - sp.x, m.z - sp.z
			if dx * dx + dz * dz <= reach * reach and math.abs((m.y or sp.y) - sp.y) < 12 then
				local best, bestD = nil, math.huge
				for i = 1, n do
					if not self:_jumpOf(u, i, t) then
						local s = seedOf(self.W, u.k, u.id .. "#" .. i)
						local fx, fz = circle(u, s, t)
						local d = (fx - m.x) ^ 2 + (fz - m.z) ^ 2
						if d < bestD then
							best, bestD = i, d
						end
					end
				end
				if best then
					self.jumps[u.id .. "#" .. best] = t
					self.startled[u.id] = t + k.cooldown
				end
				return
			end
		end
	end
end

function World._flock(self: any, out: { Pose }, u: any, t: number, scarers: { any })
	local k = u.k
	local b = math.floor(t / k.bucket)
	local plan = self:_plan(u, b)
	if not plan then
		return
	end
	local sim = self.sims[u.id]
	if not sim or sim.plan ~= plan or sim.T > t then
		sim = Flock.start(self.W, u, plan)
		self.sims[u.id] = sim
	end
	sim.seen = t
	Flock.advance(self.W, sim, t)
	Flock.checkScare(sim, scarers)
	for _, d in self.disturbs do
		Flock.checkScare(sim, { d }, true)
	end
	Flock.poses(self.W, sim, t, function(ag, x, y, z, yaw, pitch, state)
		self:_emit(out, u, ag.i, state, x, y, z, yaw, pitch, { diverged = sim.diverged })
	end)
end

function World._stray(self: any, out: { Pose }, u: any, n: number, t: number)
	local k = u.k
	local b = math.floor(t / k.bucket)
	local sim = self.sims[u.id]
	if not sim or sim.b ~= b or #sim.a ~= n or sim.T > t then
		sim = Stray.start(self.W, u, n, b)
		self.sims[u.id] = sim
	end
	sim.seen = t
	Stray.advance(self.W, sim, t)
	Stray.poses(sim, t, function(ag, x, y, z, yaw, mode, moving)
		local state = mode
		if not moving and (mode == "follow" or mode == "wander") then
			state = if mode == "follow" then "watch" else "sit"
		end
		local anim = k.anims[state] or (if moving then k.anims.wander else k.anims.sit) or state
		self:_emit(out, u, ag.i, state, x, y, z, yaw, 0, { anim = anim, alpha = fadeOf(self, u, ag.i, t), follows = ag.target })
	end)
end

-- Movers ---------------------------------------------------------------------------------------

-- Players and movers (carts) with a speed: given, or measured from the last frame (flat).
function World._movers(self: any, dt: number): { any }
	local list = {}
	local seen = {}
	local function add(src: string, m: any)
		local x, y, z = xyzOf(m)
		local key = src .. ":" .. tostring(m.id or #list + 1)
		local speed = m.speed
		local last = self.speeds[key]
		if speed == nil then
			speed = 0
			if last and dt > 0 then
				local dx, dz = x - last.x, z - last.z
				speed = math.sqrt(dx * dx + dz * dz) / dt
			end
		end
		self.speeds[key] = { x = x, z = z }
		seen[key] = true
		table.insert(list, { id = key, x = x, y = y, z = z, speed = speed })
	end
	local e = self.env
	if e.players then
		for _, p in e.players() or {} do
			add("player", p)
		end
	end
	if e.movers then
		for _, m in e.movers(self.adapter.now()) or {} do
			add("mover", m)
		end
	end
	for key in self.speeds do
		if not seen[key] then
			self.speeds[key] = nil
		end
	end
	return list
end

-- step ------------------------------------------------------------------------------------------

function World.step(self: any, dt: number, camera: any): { Pose }
	local s, W = self.s, self.W
	local t = self.adapter.now()
	local q = self.adapter.quality()
	local cx, _, cz = xyzOf(camera)
	local movers = self:_movers(dt)
	-- 1. candidates near the camera
	local cands = {}
	local considered = 0
	for _, sp in self.idx.query(cx, cz, self.idx.maxRadius) do
		local dx, dz = sp.x - cx, sp.z - cz
		local d2 = dx * dx + dz * dz
		for _, u in self.idx.bySpot[sp.id] do
			considered += 1
			local r = capOf(u.k.radius, q)
			if d2 <= r * r and capOf(u.k.max, q) > 0 then
				local n = self:_count(u, t)
				if n > 0 then
					table.insert(cands, { u = u, d2 = d2, n = n })
				end
			end
		end
	end
	table.sort(cands, function(a, b)
		if a.d2 ~= b.d2 then
			return a.d2 < b.d2
		end
		return a.u.id < b.u.id
	end)
	-- 2. caps and budget, nearest first (a flock is drawn whole or not at all)
	local budget: number? = nil
	if s.budget then
		budget = capOf(s.budget, q)
	end
	local ab = self.adapter.budget(s.budgetKind)
	if ab ~= nil then
		budget = if budget then math.min(budget, ab) else ab
	end
	local used: { [string]: number } = {}
	local cost = 0
	local chosen = {}
	local dropCap, dropBudget = 0, 0
	for _, c in cands do
		local k = c.u.k
		local cap = capOf(k.max, q)
		local room = cap - (used[c.u.kind] or 0)
		local take = math.min(c.n, room)
		if budget then
			take = math.min(take, math.floor((budget - cost) / k.cost + 1e-9))
		end
		if k.behaviour == "flock" and take < c.n then
			take = 0
		end
		if take < c.n then
			if room < c.n then
				dropCap += c.n - math.max(take, 0)
			else
				dropBudget += c.n - math.max(take, 0)
			end
		end
		if take > 0 then
			used[c.u.kind] = (used[c.u.kind] or 0) + take
			cost += take * k.cost
			table.insert(chosen, { u = c.u, n = take })
		end
	end
	-- 3. poses
	local out: { Pose } = {}
	for _, c in chosen do
		local u = c.u
		local b = u.k.behaviour
		if b == "flock" then
			self:_flock(out, u, t, movers)
		elseif b == "drift" then
			self:_drift(out, u, c.n, t)
		elseif b == "swim" then
			self:_startle(u, c.n, t, movers)
			self:_swim(out, u, c.n, t)
		else
			self:_stray(out, u, c.n, t)
		end
	end
	table.clear(self.disturbs)
	-- 4. forget what has been out of view a while, and old plans / claims / jumps
	for id, sim in self.sims do
		if (sim.seen or -math.huge) < t - s.keep then
			self.sims[id] = nil
		end
	end
	self._gc = (self._gc or 0) + 1
	if self._gc >= 600 then
		self._gc = 0
		table.clear(self.plans)
		table.clear(W.wanted)
		table.clear(W.claims)
		table.clear(W.counts)
		if W.agentCount > 20000 then
			table.clear(W.agents)
			W.agentCount = 0
		end
		for id, js in self.jumps do
			if js < t - 60 then
				self.jumps[id] = nil
			end
		end
	end
	local byKind = {}
	for _, p in out do
		local e = byKind[p.kind] or { shown = 0, cost = 0, cap = capOf(s.kinds[p.kind].max, q) }
		e.shown += 1
		e.cost += s.kinds[p.kind].cost
		byKind[p.kind] = e
	end
	local shownCost = 0
	for _, e in byKind do
		shownCost += e.cost
	end
	self.lastStats = {
		t = t,
		quality = q,
		budget = budget,
		cost = cost,
		shownCost = shownCost,
		shown = #out,
		byKind = byKind,
		units = { considered = considered, candidates = #cands, chosen = #chosen, droppedByCap = dropCap, droppedByBudget = dropBudget },
		simulated = 0,
	}
	for _ in self.sims do
		self.lastStats.simulated += 1
	end
	return out
end

-- A game event (a cart horn, a firework): scatters flocks within `radius` on the next step.
function World.disturb(self: any, x: number, z: number, radius: number)
	table.insert(self.disturbs, { x = x, z = z, radius = radius, speed = math.huge })
end

function World.stats(self: any): any
	return self.lastStats
end

-- Non-fatal problems: kinds nothing spawns, spawn entries no spot can host.
function World.problems(self: any): { string }
	local s = self.s
	local out = {}
	local spawned = {}
	for _, u in self.idx.units do
		spawned[u.kind] = true
	end
	local names = {}
	for name in s.kinds do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		if not spawned[name] then
			table.insert(out, `kind '{name}' has no spot to spawn on (no biome entry on a spot of its types)`)
		end
	end
	return out
end

function World.destroy(self: any)
	table.clear(self.sims)
	table.clear(self.plans)
	table.clear(self.jumps)
end

return Wildlife
