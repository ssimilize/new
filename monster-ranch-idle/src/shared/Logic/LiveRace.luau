--[[
	LiveRace: pure rules of the live races (Config/LiveRace), shared by the server (Systems/LiveRace,
	authoritative) and the client (Controllers/LiveRace, which predicts and draws).

	Track (a stadium loop; u = studs along the centreline from the start line, 0 ≤ u < Length):
	  LiveRace.Length() -> studs of one lap;  LiveRace.Total() -> studs of a heat (Laps laps)
	  LiveRace.Point(u, lateral?) -> x, z, dx, dz      -- (dx, dz) = unit direction of travel
	  LiveRace.Project(x, z) -> u, lateral, off        -- lateral + = inside; off = studs past the edge
	  LiveRace.IsCurve(u) -> boolean
	  LiveRace.Wrap(du) -> du in [-Length/2, Length/2)
	  LiveRace.Crossed(from, to, u) -> boolean          -- progress from→to passes track spot u (any lap)
	  LiveRace.Threshold(i) -> progress of the i-th checkpoint of the heat (in order, 1-based)
	Riding:
	  LiveRace.SpeedFor(monster) -> studs/s
	  LiveRace.Allowed(speed, from, to, boosts, stuns) -> studs a rider may cover in [from, to]
	  LiveRace.Refill(meter, dt, drafting, drifting) -> meter
	  LiveRace.Drafting(me, others) -> boolean          -- { progress, lateral } records
	  LiveRace.NewRider(speed, lateral) / LiveRace.TryJump(r) / LiveRace.StepRider(r, dt, steer)
	    the client's prediction; StepRider returns { stumbled, pad } for effects
	Heat:
	  LiveRace.CanJoin(state, count, isIn, busyRace?) -> ok, why?
	  LiveRace.LobbyDone(now, lobbyEndsAt, count, fullAt?) -> boolean
	  LiveRace.Ghosts(humans, seed) -> { { name, time, lane } }
	  LiveRace.GhostProgress(ghost, elapsed) -> progress
	  LiveRace.Order(entries) -> entries sorted with .place  -- { finished, time, progress, dq }
	  LiveRace.Place(progress, finished, time, others) -> 1-based place (for the HUD)
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)

local Cfg = Config.LiveRace
local Track = Cfg.Track

local LiveRace = {}

local S, R = Track.straight, Track.radius
local CX, CZ = Track.center[1], Track.center[3]
local ARC = math.pi * R
local LEN = 2 * S + 2 * ARC
local HALF = S / 2 -- the start line sits in the middle of the first straight

function LiveRace.Length(): number
	return LEN
end

function LiveRace.Total(): number
	return LEN * Cfg.Laps
end

local function base(u: number): number
	return (u + HALF) % LEN
end

-- Point on the centreline at base parameter b, with the direction of travel.
local function at(b: number): (number, number, number, number)
	if b < S then
		return CX - HALF + b, CZ - R, 1, 0
	elseif b < S + ARC then
		local th = (b - S) / R
		return CX + HALF + R * math.sin(th), CZ - R * math.cos(th), math.cos(th), math.sin(th)
	elseif b < 2 * S + ARC then
		return CX + HALF - (b - S - ARC), CZ + R, -1, 0
	else
		local th = math.pi + (b - 2 * S - ARC) / R
		return CX - HALF + R * math.sin(th), CZ - R * math.cos(th), math.cos(th), math.sin(th)
	end
end

function LiveRace.Point(u: number, lateral: number?): (number, number, number, number)
	local x, z, dx, dz = at(base(u))
	local lat = lateral or 0
	-- Lateral + is the inside of the loop: the direction turned a quarter towards the centre.
	return x - dz * lat, z + dx * lat, dx, dz
end

function LiveRace.Project(x: number, z: number): (number, number, number)
	local bestB, bestLat, bestDist = 0, 0, math.huge
	local function consider(b: number, lat: number, dist: number)
		if dist < bestDist then
			bestB, bestLat, bestDist = b, lat, dist
		end
	end
	-- Straights
	local t = math.clamp(x - (CX - HALF), 0, S)
	consider(t, z - (CZ - R), math.sqrt((x - (CX - HALF + t)) ^ 2 + (z - (CZ - R)) ^ 2))
	t = math.clamp((CX + HALF) - x, 0, S)
	consider(S + ARC + t, (CZ + R) - z, math.sqrt((x - (CX + HALF - t)) ^ 2 + (z - (CZ + R)) ^ 2))
	-- Curves (each covers one half plane)
	local vx, vz = x - (CX + HALF), z - CZ
	if vx >= 0 then
		local r = math.sqrt(vx * vx + vz * vz)
		local th = math.atan2(vx, -vz)
		consider(S + R * th, R - r, math.abs(r - R))
	end
	vx = x - (CX - HALF)
	if vx <= 0 then
		local r = math.sqrt(vx * vx + vz * vz)
		local th = math.atan2(vx, -vz) + 2 * math.pi -- π..2π
		consider(2 * S + ARC + R * (th - math.pi), R - r, math.abs(r - R))
	end
	local u = (bestB - HALF) % LEN
	return u, bestLat, math.max(0, math.abs(bestLat) - Track.halfWidth)
end

function LiveRace.IsCurve(u: number): boolean
	local b = base(u)
	return (b >= S and b < S + ARC) or b >= 2 * S + ARC
end

function LiveRace.Wrap(du: number): number
	return ((du + LEN / 2) % LEN) - LEN / 2
end

-- True when going from progress `from` to `to` (studs since the start, increasing) passes the
-- track spot u on some lap.
function LiveRace.Crossed(from: number, to: number, u: number): boolean
	if to <= from then
		return false
	end
	local k = math.floor((to - u) / LEN)
	return k * LEN + u > from and k * LEN + u <= to and k >= 0
end

function LiveRace.Threshold(i: number): number
	local per = #Cfg.Checkpoints
	local lap = (i - 1) // per
	return (lap + Cfg.Checkpoints[(i - 1) % per + 1]) * LEN
end

function LiveRace.CheckpointCount(): number
	return #Cfg.Checkpoints * Cfg.Laps
end

-- Riding ------------------------------------------------------------------------------------

function LiveRace.SpeedFor(m): number
	return Config.Riding.SpeedFor(m) * Cfg.SpeedScale
end

local function inAny(list, t: number): boolean
	for _, span in list or {} do
		if t >= span[1] and t < span[2] then
			return true
		end
	end
	return false
end

-- Studs a rider at `speed` may cover between the times `from` and `to`, with boosts and
-- stumbles as { { start, stop } } spans on the same clock.
function LiveRace.Allowed(speed: number, from: number, to: number, boosts, stuns): number
	local dt = math.min(math.max(0, to - from), Cfg.MaxGap)
	local steps = math.max(1, math.ceil(dt / 0.05))
	local h = dt / steps
	local sum = 0
	for i = 0, steps - 1 do
		local t = from + (i + 0.5) * h
		local mult = 1
		if inAny(boosts, t) then
			mult *= Cfg.BoostMult
		end
		if inAny(stuns, t) then
			mult *= Cfg.StunMult
		end
		sum += mult * h
	end
	return speed * sum * Cfg.CapSlack + Cfg.SlackStuds
end

function LiveRace.Refill(meter: number, dt: number, drafting: boolean, drifting: boolean): number
	local rate = Cfg.MeterRegen + (if drafting then Cfg.DraftRegen else 0) + (if drifting then Cfg.DriftRegen else 0)
	return math.clamp(meter + rate * math.max(0, dt), 0, Cfg.MeterMax)
end

-- Close behind another rider (by track distance) and nearly in line.
function LiveRace.Drafting(me, others): boolean
	for _, o in others do
		if o ~= me then
			local gap = o.progress - me.progress
			if gap > 0.5 and gap <= Cfg.DraftRange and math.abs((o.lateral or 0) - (me.lateral or 0)) <= Cfg.DraftLateral then
				return true
			end
		end
	end
	return false
end

function LiveRace.NewRider(speed: number, lateral: number)
	return {
		speed = speed,
		progress = 0,
		lateral = lateral,
		air = 0,
		cooldown = 0,
		stun = 0,
		boost = 0,
		meter = Cfg.MeterStart,
		t = 0,
	}
end

function LiveRace.TryJump(r): boolean
	if r.air > 0 or r.cooldown > 0 or r.stun > 0 then
		return false
	end
	r.air = Cfg.JumpSeconds
	return true
end

function LiveRace.Velocity(r): number
	local v = r.speed
	if r.boost > 0 then
		v *= Cfg.BoostMult
	end
	if r.stun > 0 then
		v *= Cfg.StunMult
	end
	return v
end

-- One prediction step (the server checks the result, it never trusts it). `steer` is -1..1
-- (+ = towards the inside). Returns what happened for the effects.
function LiveRace.StepRider(r, dt: number, steer: number)
	local out = { stumbled = false, pad = false }
	local from = r.progress
	r.progress += LiveRace.Velocity(r) * dt
	r.lateral = math.clamp(r.lateral + steer * Cfg.SteerSpeed * dt, -Track.halfWidth + 1, Track.halfWidth - 1)
	for _, f in Cfg.Hurdles do
		if LiveRace.Crossed(from, r.progress, f * LEN) and r.air <= 0 then
			r.stun = Cfg.StumbleSeconds
			out.stumbled = true
		end
	end
	for _, pad in Cfg.BoostPads do
		if LiveRace.Crossed(from, r.progress, pad.at * LEN) and r.lateral * pad.side >= 1 then
			r.boost = math.max(r.boost, Cfg.BoostSeconds)
			out.pad = true
		end
	end
	local wasAir = r.air > 0
	r.air = math.max(0, r.air - dt)
	if wasAir and r.air <= 0 then
		r.cooldown = Cfg.JumpCooldown
	elseif not wasAir then
		r.cooldown = math.max(0, r.cooldown - dt)
	end
	r.boost = math.max(0, r.boost - dt)
	r.stun = math.max(0, r.stun - dt)
	r.t += dt
	return out
end

-- Height of the jump arc (studs) for a rider with `air` seconds left in the air.
function LiveRace.Hop(air: number): number
	if air <= 0 then
		return 0
	end
	return math.sin((1 - air / Cfg.JumpSeconds) * math.pi) * Cfg.JumpHeight
end

-- Heat --------------------------------------------------------------------------------------

function LiveRace.CanJoin(state: string, count: number, isIn: boolean): (boolean, string?)
	if isIn then
		return false, "You're already in this race"
	end
	if state ~= "idle" and state ~= "lobby" then
		return false, "The track is busy. Race the ghosts or wait for the next race"
	end
	if count >= Cfg.MaxRiders then
		return false, "This race is full"
	end
	return true, nil
end

-- The lobby closes when its time is up, or FullSeconds after it filled.
function LiveRace.LobbyDone(now: number, lobbyEndsAt: number, count: number, fullAt: number?): boolean
	if count <= 0 then
		return false
	end
	if now >= lobbyEndsAt then
		return true
	end
	return count >= Cfg.MaxRiders and fullAt ~= nil and now >= fullAt + Cfg.FullSeconds
end

function LiveRace.Ghosts(humans: number, seed: number)
	if humans >= Cfg.MinPlayers then
		return {}
	end
	local rc = Config.Racing
	local par = LiveRace.Total() / Cfg.ParSpeed
	local rng = Rng.new(seed)
	local names = table.clone(rc.GhostNames)
	local ghosts = {}
	for i, pace in rc.GhostPace do
		local name = table.remove(names, rng:Int(1, #names))
		table.insert(ghosts, { name = name, time = math.floor(par * pace * 100 + 0.5) / 100, lane = humans + i })
	end
	return ghosts
end

function LiveRace.GhostProgress(ghost, elapsed: number): number
	return math.clamp(elapsed / ghost.time, 0, 1) * LiveRace.Total()
end

-- Finishers by time, then riders still out by distance, then disqualified riders.
function LiveRace.Order(entries)
	local list = table.clone(entries)
	local function rank(e): number
		return if e.dq then 3 elseif e.finished then 1 else 2
	end
	table.sort(list, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		if ra == 1 and a.time ~= b.time then
			return a.time < b.time
		end
		if ra == 2 and a.progress ~= b.progress then
			return a.progress > b.progress
		end
		return tostring(a.id) < tostring(b.id)
	end)
	for i, e in list do
		e.place = i
	end
	return list
end

-- Place of a rider still racing among `others` ({ progress, finished }).
function LiveRace.Place(progress: number, others): number
	local place = 1
	for _, o in others do
		if o.finished or o.progress > progress then
			place += 1
		end
	end
	return place
end

return LiveRace
