--!strict
-- Rails: camera paths for big moments, and moment hooks that map game events to rails.
--
--   rail = {
--     id = "reveal", duration = seconds, ease = "cubicInOut"?, alpha = 0.5?,
--     keys = { { pos = Vec3, look = Vec3, fov = number? }, ... },    -- >= 2 keys, or
--     orbit = { { yaw, pitch, distance, fov?, lookUp? }, ... },        -- keys around a subject at
--                                                                      -- the origin (Rails.resolve)
--     fov = number?,                                                   -- default for keys without one
--   }
--   Positions and look targets run on centripetal Catmull-Rom splines (alpha 0.5; 0 = uniform)
--   through every key; progress along the path is by ARC LENGTH, eased by `ease` over
--   `duration`, so the camera's speed follows the ease and not the key spacing.
--
--   Rails.validate(rail) -> { problems }
--   Rails.resolve(rail) -> rail with keys            (orbit templates become keys; cached)
--   Rails.place(rail, origin, yawDeg?) -> rail       template -> world: rotate around +Y, then move
--   Rails.sample(rail, t) -> { position, lookAt, look, fov, progress, done }   t in seconds
--   Rails.length(rail) -> studs
--
--   Rails.director(adapter, moments, sink, opts?) -> director
--     moments = { { id?, on = event, rail = rail | fn(payload) -> rail?, priority = number?,
--                   cooldown = seconds?, anchor = payloadKey?, yawKey = payloadKey?,
--                   when = fn(payload) -> boolean? } }
--     One rail plays at a time. An event whose moment is cooling down is dropped; one that
--     arrives while another rail plays preempts it only with a HIGHER priority. `anchor` names
--     the payload field holding the world point the template is placed at (dropped when absent).
--     sink(cmd): { kind = "play", moment, rail, at, priority, payload }
--                { kind = "stop", moment, reason = "preempted" | "stopped" }
--                { kind = "done", moment }
--     director.step() -> sample?   (call once a frame: emits "done" at the end; the sample to show)
--     director.playing() -> { moment, rail, at, priority }?
--     director.stop()   director.stats()   director.disconnect()

local Ease = require("./Ease")
local Vec = require("./Vec")

type Vec3 = Vec.Vec3

local Rails = {}

local fin = Vec.finiteNumber
local SUB = 64 -- arc-length table samples per segment
local EPS = 1e-4

-- validate -------------------------------------------------------------------------------------

function Rails.validate(rail: any): { string }
	local problems = {}
	if type(rail) ~= "table" then
		return { "rail must be a table" }
	end
	local id = tostring(rail.id or "?")
	local function need(cond: boolean, msg: string)
		if not cond then
			table.insert(problems, `rail {id}: {msg}`)
		end
	end
	need(fin(rail.duration) and rail.duration > 0, "duration must be > 0 seconds")
	need(rail.ease == nil or Ease.known(rail.ease), `unknown ease {tostring(rail.ease)}`)
	need(rail.alpha == nil or (fin(rail.alpha) and rail.alpha >= 0 and rail.alpha <= 1), "alpha must be in [0, 1]")
	need(rail.fov == nil or (fin(rail.fov) and rail.fov >= 1 and rail.fov <= 120), "fov must be in [1, 120]")
	if rail.keys ~= nil then
		need(type(rail.keys) == "table" and #rail.keys >= 2, "needs at least 2 keys")
		if type(rail.keys) == "table" then
			for i, k in ipairs(rail.keys) do
				need(type(k) == "table" and Vec.isVec(k.pos) and Vec.isVec(k.look), `key {i} needs pos and look Vec3s`)
				need(type(k) ~= "table" or k.fov == nil or (fin(k.fov) and k.fov >= 1 and k.fov <= 120), `key {i} fov must be in [1, 120]`)
			end
		end
	elseif rail.orbit ~= nil then
		need(type(rail.orbit) == "table" and #rail.orbit >= 2, "needs at least 2 orbit keys")
		if type(rail.orbit) == "table" then
			for i, k in ipairs(rail.orbit) do
				need(type(k) == "table" and fin(k.yaw) and fin(k.pitch) and fin(k.distance) and k.distance > 0, `orbit key {i} needs yaw, pitch and distance > 0`)
			end
		end
	else
		need(false, "needs keys or orbit")
	end
	return problems
end

-- resolve: orbit templates -> keys -----------------------------------------------------------

local resolved: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

function Rails.resolve(rail: any): any
	if rail.keys then
		return rail
	end
	local hit = resolved[rail]
	if hit then
		return hit
	end
	local keys = {}
	for _, o in ipairs(rail.orbit) do
		local look = { x = 0, y = o.lookUp or 0, z = 0 }
		local p, y = math.rad(o.pitch), math.rad(o.yaw)
		local h = math.cos(p) * o.distance
		local pos = { x = h * math.sin(y), y = look.y + math.sin(p) * o.distance, z = h * math.cos(y) }
		table.insert(keys, { pos = pos, look = look, fov = o.fov })
	end
	local out = table.clone(rail)
	out.orbit = nil
	out.keys = keys
	resolved[rail] = out
	return out
end

function Rails.place(rail: any, origin: Vec3, yawDeg: number?): any
	local r = Rails.resolve(rail)
	local yaw = yawDeg or 0
	local keys = {}
	for _, k in ipairs(r.keys) do
		table.insert(keys, {
			pos = Vec.add(Vec.yaw(k.pos, yaw), origin),
			look = Vec.add(Vec.yaw(k.look, yaw), origin),
			fov = k.fov,
		})
	end
	local out = table.clone(r)
	out.keys = keys
	return out
end

-- Catmull-Rom (Barry-Goldman form) --------------------------------------------------------------

local function knot(a: Vec3, b: Vec3, alpha: number): number
	return math.max(EPS, Vec.dist(a, b) ^ alpha)
end

local function mixv(a: Vec3, b: Vec3, wa: number, wb: number): Vec3
	return { x = a.x * wa + b.x * wb, y = a.y * wa + b.y * wb, z = a.z * wa + b.z * wb }
end

-- The point u in [0, 1] of the way from p1 to p2.
local function catmull(p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, u: number, alpha: number): Vec3
	if u <= 0 then
		return p1
	elseif u >= 1 then
		return p2
	end
	local t0 = 0
	local t1 = t0 + knot(p0, p1, alpha)
	local t2 = t1 + knot(p1, p2, alpha)
	local t3 = t2 + knot(p2, p3, alpha)
	local t = t1 + (t2 - t1) * u
	local a1 = mixv(p0, p1, (t1 - t) / (t1 - t0), (t - t0) / (t1 - t0))
	local a2 = mixv(p1, p2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1))
	local a3 = mixv(p2, p3, (t3 - t) / (t3 - t2), (t - t2) / (t3 - t2))
	local b1 = mixv(a1, a2, (t2 - t) / (t2 - t0), (t - t0) / (t2 - t0))
	local b2 = mixv(a2, a3, (t3 - t) / (t3 - t1), (t - t1) / (t3 - t1))
	return mixv(b1, b2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1))
end

-- Control points around segment i (keys i -> i+1), with mirrored phantoms at the ends.
local function controls(list: { Vec3 }, i: number): (Vec3, Vec3, Vec3, Vec3)
	local n = #list
	local p1, p2 = list[i], list[i + 1]
	local p0 = if i > 1 then list[i - 1] else Vec.sub(Vec.scale(p1, 2), p2)
	local p3 = if i + 2 <= n then list[i + 2] else Vec.sub(Vec.scale(p2, 2), p1)
	return p0, p1, p2, p3
end

local function segPoint(list: { Vec3 }, i: number, u: number, alpha: number): Vec3
	local p0, p1, p2, p3 = controls(list, i)
	return catmull(p0, p1, p2, p3, u, alpha)
end

-- Uniform Catmull-Rom on a scalar (fov), clamped between the segment's two keys.
local function segScalar(list: { number }, i: number, u: number): number
	local n = #list
	local p1, p2 = list[i], list[i + 1]
	local p0 = if i > 1 then list[i - 1] else 2 * p1 - p2
	local p3 = if i + 2 <= n then list[i + 2] else 2 * p2 - p1
	local u2, u3 = u * u, u * u * u
	local v = 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3)
	return math.clamp(v, math.min(p1, p2), math.max(p1, p2))
end

-- arc-length tables (cached per resolved rail) -------------------------------------------------

type Arc = { pos: { Vec3 }, look: { Vec3 }, fov: { number }, cum: { number }, total: number, alpha: number, n: number }

local arcs: { [any]: Arc } = setmetatable({}, { __mode = "k" }) :: any

local function arcOf(rail: any): Arc
	local hit = arcs[rail]
	if hit then
		return hit
	end
	local pos, look, fov = {}, {}, {}
	for _, k in ipairs(rail.keys) do
		table.insert(pos, Vec.of(k.pos) :: Vec3)
		table.insert(look, Vec.of(k.look) :: Vec3)
		table.insert(fov, k.fov or rail.fov or 70)
	end
	local alpha = if rail.alpha == nil then 0.5 else rail.alpha
	local cum = { 0 }
	local total = 0
	for i = 1, #pos - 1 do
		local prev = pos[i]
		for s = 1, SUB do
			local p = segPoint(pos, i, s / SUB, alpha)
			total += Vec.dist(prev, p)
			prev = p
			table.insert(cum, total)
		end
	end
	local arc = { pos = pos, look = look, fov = fov, cum = cum, total = total, alpha = alpha, n = #pos }
	arcs[rail] = arc
	return arc
end

-- progress s in [0, 1] -> segment index and local u.
local function locate(arc: Arc, s: number): (number, number)
	local segs = arc.n - 1
	if arc.total < 1e-9 then
		-- a path that does not move (a pure look pan): split time evenly between keys
		local g = math.clamp(s, 0, 1) * segs
		local i = math.clamp(math.floor(g) + 1, 1, segs)
		return i, g - (i - 1)
	end
	local target = math.clamp(s, 0, 1) * arc.total
	local cum = arc.cum
	-- binary search the table: largest j with cum[j] <= target
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= target then
			lo = mid
		else
			hi = mid
		end
	end
	local span = cum[hi] - cum[lo]
	local frac = if span > 1e-12 then (target - cum[lo]) / span else 0
	local sample = (lo - 1) + frac -- 0 .. segs * SUB
	local g = sample / SUB
	local i = math.clamp(math.floor(g) + 1, 1, segs)
	return i, math.clamp(g - (i - 1), 0, 1)
end

function Rails.length(rail: any): number
	return arcOf(Rails.resolve(rail)).total
end

export type Sample = { position: Vec3, lookAt: Vec3, look: Vec3, fov: number, progress: number, done: boolean }

function Rails.sample(rail: any, t: number): Sample
	local r = Rails.resolve(rail)
	local arc = arcOf(r)
	local x = if r.duration > 0 then t / r.duration else 1
	local s = Ease.apply(r.ease or "cubicInOut", x)
	local i, u = locate(arc, s)
	local position = segPoint(arc.pos, i, u, arc.alpha)
	local lookAt = segPoint(arc.look, i, u, arc.alpha)
	return {
		position = position,
		lookAt = lookAt,
		look = Vec.norm(Vec.sub(lookAt, position)),
		fov = segScalar(arc.fov, i, u),
		progress = s,
		done = t >= r.duration,
	}
end

-- moment hooks --------------------------------------------------------------------------------

export type Director = {
	step: () -> Sample?,
	playing: () -> any?,
	stop: () -> (),
	stats: () -> { [string]: number },
	disconnect: () -> (),
}

function Rails.validateMoments(moments: any): { string }
	local problems = {}
	if type(moments) ~= "table" then
		return { "moments must be a list" }
	end
	local ids: { [string]: boolean } = {}
	for i, m in ipairs(moments) do
		local id = tostring(m.id or m.on or i)
		if type(m.on) ~= "string" or m.on == "" then
			table.insert(problems, `moment {id}: on must be an event name`)
		end
		if ids[id] then
			table.insert(problems, `moment {id}: duplicate id`)
		end
		ids[id] = true
		if type(m.rail) == "table" then
			for _, p in ipairs(Rails.validate(m.rail)) do
				table.insert(problems, `moment {id}: {p}`)
			end
		elseif type(m.rail) ~= "function" then
			table.insert(problems, `moment {id}: rail must be a rail table or a function`)
		end
		if m.priority ~= nil and not fin(m.priority) then
			table.insert(problems, `moment {id}: priority must be a number`)
		end
		if m.cooldown ~= nil and not (fin(m.cooldown) and m.cooldown >= 0) then
			table.insert(problems, `moment {id}: cooldown must be >= 0 seconds`)
		end
	end
	return problems
end

function Rails.director(adapter: any, moments: { any }, sink: (any) -> (), opts: any?): Director
	local problems = Rails.validateMoments(moments)
	if #problems > 0 then
		error("Cinema.Rails.director: " .. table.concat(problems, "; "), 2)
	end
	local stats = { played = 0, done = 0, preempted = 0, droppedCooldown = 0, droppedBusy = 0, droppedNoAnchor = 0, invalid = 0, sinkErrors = 0 }
	local lastPlayed: { [string]: number } = {}
	local current: any = nil
	local disconnects = {}

	local function send(cmd: any)
		local ok, err = pcall(sink, cmd)
		if not ok then
			stats.sinkErrors += 1
			adapter.log("error", "Cinema.Rails: sink failed", { kind = cmd.kind, err = tostring(err) })
		end
	end

	local function busy(now: number): boolean
		return current ~= nil and now < current.at + current.rail.duration
	end

	local function fire(m: any, id: string, payload: any)
		if m.when and not m.when(payload) then
			return
		end
		local now = adapter.now()
		local cd = m.cooldown or 0
		local last = lastPlayed[id]
		if last and now - last < cd then
			stats.droppedCooldown += 1
			adapter.log("info", "Cinema.Rails: moment cooling down", { moment = id, left = cd - (now - last) })
			return
		end
		local priority = m.priority or 0
		if busy(now) and priority <= current.priority then
			stats.droppedBusy += 1
			adapter.log("info", "Cinema.Rails: busy", { moment = id, playing = current.moment })
			return
		end
		local rail = if type(m.rail) == "function" then m.rail(payload) else m.rail
		if rail == nil then
			return
		end
		if m.anchor then
			local at = type(payload) == "table" and Vec.of(payload[m.anchor]) or nil
			if not at then
				stats.droppedNoAnchor += 1
				adapter.log("warn", "Cinema.Rails: payload has no anchor", { moment = id, anchor = m.anchor })
				return
			end
			local yaw = (m.yawKey and type(payload) == "table" and fin(payload[m.yawKey])) and payload[m.yawKey] or 0
			rail = Rails.place(rail, at, yaw)
		end
		local bad = Rails.validate(rail)
		if #bad > 0 then
			stats.invalid += 1
			adapter.log("error", "Cinema.Rails: invalid rail", { moment = id, problems = bad })
			return
		end
		if busy(now) then
			stats.preempted += 1
			send({ kind = "stop", moment = current.moment, reason = "preempted" })
		end
		current = { moment = id, rail = rail, at = now, priority = priority }
		lastPlayed[id] = now
		stats.played += 1
		send({ kind = "play", moment = id, rail = rail, at = now, priority = priority, payload = payload })
	end

	local byEvent: { [string]: { any } } = {}
	for i, m in ipairs(moments) do
		local list = byEvent[m.on]
		if not list then
			list = {}
			byEvent[m.on] = list
		end
		table.insert(list, { m = m, id = tostring(m.id or m.on or i) })
	end
	for event, list in byEvent do
		table.insert(
			disconnects,
			adapter.on(event, function(payload: any)
				for _, e in ipairs(list) do
					fire(e.m, e.id, payload)
				end
			end)
		)
	end

	local director = {} :: any
	director.step = function(): Sample?
		if not current then
			return nil
		end
		local t = adapter.now() - current.at
		local s = Rails.sample(current.rail, t)
		if s.done then
			local id = current.moment
			current = nil
			stats.done += 1
			send({ kind = "done", moment = id })
		end
		return s
	end
	director.playing = function(): any?
		if not current then
			return nil
		end
		return { moment = current.moment, rail = current.rail, at = current.at, priority = current.priority }
	end
	director.stop = function()
		if current then
			local id = current.moment
			current = nil
			send({ kind = "stop", moment = id, reason = "stopped" })
		end
	end
	director.stats = function()
		return table.clone(stats)
	end
	director.disconnect = function()
		for _, d in disconnects do
			d()
		end
		table.clear(disconnects)
	end
	return director :: Director
end

return Rails
