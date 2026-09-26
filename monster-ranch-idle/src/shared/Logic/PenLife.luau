--[[
	Logic/PenLife (glow-up S, living pens): the pure decisions behind pen monsters, driven by
	Config/PenLife and unit-tested in PenLife.spec. Visuals/PenBrain (client) calls these.

	Personality
		PenLife.TraitIds(record) -> { number }         visible traits, plus the hidden one once revealed (stage 3)
		PenLife.Tendency(traits) -> Tendency           Config/PenLife.Base merged with each trait (ids or keys)
		PenLife.Asleep(t, situation) -> boolean        should it be in the night pile now
		PenLife.Weight(t, situation, action) -> number the day-roll weight of one action
		PenLife.Choose(t, situation, roll) -> action   roll in [0, 1); actions in PenLife.Actions order
		PenLife.Hold(action, t, roll) -> seconds       how long an action holds (Config/PenLife.Hold)
		PenLife.IdleState(t, situation) -> state       "shiver" in the cold, else "idle"
		PenLife.WeatherOf(id) -> reaction table        Config/PenLife.Weather[id] or {}
		PenLife.Onset(t, fromId, toId) -> "shake"?     a monster shakes off the rain when it starts
		PenLife.Bubble(action) -> kind?                 the mood bubble an action pops (Config/PenLife.Bubbles)
		PenLife.BubbleAllowed(kind, low, shown, cap) -> boolean
	  situation = { night, dawnIn?, weather?, lowGraphics?, hasMate? }

	Pen maths, flat and in pen-local studs (x across, z deep; the pen is |x| <= hx, |z| <= hz)
		PenLife.Clamp(x, z, hx, hz, margin) -> x, z
		PenLife.RandomPoint(r1, r2, r3, hx, hz, margin, edge) -> x, z   three rolls; edge 0..1 hugs the fence
		PenLife.FencePoint(px, pz, hx, hz, margin, slot, spacing, count?) -> x, z   nearest fence spot, spread by
		                                                   slot; with count the whole fan fits on that side
		PenLife.NearFence(px, pz, hx, hz, range) -> boolean                 within range of the pen, inside or out
		PenLife.PileSlot(i, spacing) -> dx, dz                             a sunflower heap round the pile centre
		PenLife.Ring(i, n, radius) -> dx, dz
		PenLife.Separation(x, z, xs, zs, rs, n, skip, r, scale) -> dx, dz   push away from overlapping pen-mates
		PenLife.Avoid(x, z, ox, oz, or, n, pad) -> dx, dz                   push out of decor circles
		PenLife.Steer(x, z, gx, gz, sx, sz, ax, az, leg) -> wx, wz          the next waypoint toward the goal
		PenLife.FleePoint(x, z, cx, cz, hx, hz, margin, distance) -> x, z   a runner's goal in a game of chase
		PenLife.PickMate(n, self, free, roll) -> index?                     free[i] = true for a pen-mate that can play
		PenLife.TurnYaw(from, to, maxStep) -> yaw                          the shortest way round, at most maxStep
		PenLife.ThinkRate(distance, onScreen, knob) -> 0..1                 Config/PenLife.Think bands

	Every function is allocation-free except TraitIds and Tendency (once per monster).
]]

local Config = script.Parent.Parent.Config
local Cfg = require(Config.PenLife)
local Traits = require(Config.Traits)

local PenLife = {}

export type Tendency = { [string]: any }

PenLife.Actions = { "wander", "eat", "sit", "nap", "cheer", "trick", "spar", "chase", "social", "idle", "bask", "shelter", "shiver" }

local EMPTY = table.freeze({})
local TAU = math.pi * 2
local sqrt, abs, min, max, clamp = math.sqrt, math.abs, math.min, math.max, math.clamp

-- Personality ---------------------------------------------------------------------------------

function PenLife.TraitIds(record: any): { number }
	local list = {}
	if type(record) ~= "table" then
		return list
	end
	if type(record.traits) == "table" then
		for _, id in record.traits do
			table.insert(list, id)
		end
	end
	if record.hidden ~= nil and (tonumber(record.stage) or 0) >= 3 then
		table.insert(list, record.hidden)
	end
	return list
end

function PenLife.Tendency(traits: { any }?): Tendency
	local t = table.clone(Cfg.Base)
	t.keys = {}
	for _, ref in traits or EMPTY do
		local def = if type(ref) == "number" then Traits.ById[ref] elseif type(ref) == "string" then Traits.ByKey[ref] else nil
		local mods = def and Cfg.Traits[def.key]
		if mods then
			table.insert(t.keys, def.key)
			for key, value in mods do
				if type(value) == "number" and key ~= "edge" and type(t[key]) == "number" then
					t[key] *= value
				else
					t[key] = value -- flags, and edge (a chance, the strongest wins below)
				end
			end
		end
	end
	for _, key in t.keys do
		local edge = Cfg.Traits[key].edge
		if type(edge) == "number" and edge > (t.edge or 0) then
			t.edge = edge
		end
	end
	return t
end

function PenLife.WeatherOf(id: string?): { [string]: any }
	return (id and Cfg.Weather[id]) or EMPTY
end

function PenLife.Asleep(t: Tendency, s): boolean
	if not s.night or t.nightOwl then
		return false
	end
	if t.earlyBird and type(s.dawnIn) == "number" and s.dawnIn <= Cfg.EarlyBirdLead then
		return false
	end
	return true
end

local function hardy(t: Tendency): boolean
	return t.weatherproof == true or t.weatherLover == true
end

function PenLife.Weight(t: Tendency, s, action: string): number
	local w = PenLife.WeatherOf(s.weather)
	if action == "bask" then
		if s.night or not w.sunny or t.weatherproof then
			return 0
		end
		return Cfg.BaskWeight * (w.bask or 1) * sqrt((t.nap or 0) / Cfg.Base.nap)
	elseif action == "shelter" then
		return if w.shelter and not hardy(t) then Cfg.ShelterWeight else 0
	elseif action == "shiver" then
		return if w.cold and not t.weatherproof then Cfg.ShiverWeight else 0
	end
	local weight = t[action]
	if type(weight) ~= "number" then
		return 0
	end
	if action == "chase" then
		if s.lowGraphics or not s.hasMate or s.night or (w.shelter and not hardy(t)) then
			return 0
		end
	elseif action == "social" then
		if not s.hasMate then
			return 0
		end
	elseif action == "nap" then
		if s.night and t.nightOwl then
			return 0
		end
	elseif action == "cheer" then
		if t.weatherLover and s.weather and s.weather ~= "clear" and Cfg.Weather[s.weather] then
			weight += Cfg.WeatherDanceWeight
		end
	elseif action == "wander" then
		if w.shelter and not hardy(t) then
			weight *= 0.3
		end
	end
	return max(0, weight)
end

function PenLife.Choose(t: Tendency, s, roll: number): string
	if PenLife.Asleep(t, s) then
		if t.stargazer and roll < Cfg.StargazeChance then
			return "stargaze"
		end
		return "sleep"
	end
	local total = 0
	for _, action in PenLife.Actions do
		total += PenLife.Weight(t, s, action)
	end
	if total <= 0 then
		return "idle"
	end
	local pick = clamp(roll, 0, 0.999999) * total
	for _, action in PenLife.Actions do
		local w = PenLife.Weight(t, s, action)
		if w > 0 then
			if pick < w then
				return action
			end
			pick -= w
		end
	end
	return "idle"
end

function PenLife.Hold(action: string, t: Tendency?, roll: number): number
	local range = Cfg.Hold[action] or Cfg.Hold.idle
	local seconds = range[1] + (range[2] - range[1]) * clamp(roll, 0, 1)
	if action == "eat" and t and type(t.eatLong) == "number" then
		seconds *= t.eatLong
	end
	return seconds
end

function PenLife.IdleState(t: Tendency, s): string
	return if PenLife.WeatherOf(s.weather).cold and not t.weatherproof then "shiver" else "idle"
end

function PenLife.Onset(t: Tendency, fromId: string?, toId: string?): string?
	if t.weatherproof or fromId == toId then
		return nil
	end
	local now, before = PenLife.WeatherOf(toId), PenLife.WeatherOf(fromId)
	if now.wet and not before.wet then
		return "shake"
	end
	return nil
end

local BUBBLE = {
	sleep = "sleep",
	nap = "sleep",
	eat = "food",
	greet = "love",
	gather = "love",
	social = "love",
	cheer = "music",
	chase = "music",
	trick = "music",
	pose = "music",
	shake = "wet",
	shelter = "wet",
}

function PenLife.Bubble(action: string): string?
	return BUBBLE[action]
end

function PenLife.BubbleAllowed(kind: string?, low: boolean, shown: number, cap: number): boolean
	if not kind or shown >= cap then
		return false
	end
	return not low or Cfg.Bubbles.essential[kind] == true
end

-- Pen maths -------------------------------------------------------------------------------------

function PenLife.Clamp(x: number, z: number, hx: number, hz: number, margin: number): (number, number)
	local mx = max(0.5, hx - margin)
	local mz = max(0.5, hz - margin)
	return clamp(x, -mx, mx), clamp(z, -mz, mz)
end

function PenLife.RandomPoint(r1: number, r2: number, r3: number, hx: number, hz: number, margin: number, edge: number?): (number, number)
	local mx = max(0.5, hx - margin)
	local mz = max(0.5, hz - margin)
	if edge and r3 < edge then
		-- Along the fence: r1 picks the side, r2 the spot along it, a band one margin deep.
		local along = r2 * 2 - 1
		local band = (r1 * 4) % 1
		local side = math.floor(r1 * 4)
		local depth = 1 - band * 0.2
		if side == 0 then
			return along * mx, -mz * depth
		elseif side == 1 then
			return along * mx, mz * depth
		elseif side == 2 then
			return -mx * depth, along * mz
		end
		return mx * depth, along * mz
	end
	return (r1 * 2 - 1) * mx, (r2 * 2 - 1) * mz
end

function PenLife.FencePoint(
	px: number,
	pz: number,
	hx: number,
	hz: number,
	margin: number,
	slot: number,
	spacing: number,
	count: number?
): (number, number)
	local mx = max(0.5, hx - margin)
	local mz = max(0.5, hz - margin)
	local k = max(0, slot - 1)
	local offset = (if k % 2 == 0 then 1 else -1) * math.ceil(k / 2) * spacing
	-- Slide the fan's centre so every slot fits along the side (no two clamped onto one corner).
	local half = math.ceil(max(0, (count or slot) - 1) / 2) * spacing
	local function along(p: number, m: number): number
		local centre = if half >= m then 0 else clamp(p, -m + half, m - half)
		return clamp(centre + offset, -m, m)
	end
	-- The side the point is past (or closest to), measured against the pen's own proportions.
	if abs(px) / hx >= abs(pz) / hz then
		local x = if px >= 0 then mx else -mx
		return x, along(pz, mz)
	end
	local z = if pz >= 0 then mz else -mz
	return along(px, mx), z
end

function PenLife.NearFence(px: number, pz: number, hx: number, hz: number, range: number): boolean
	local ax, az = abs(px), abs(pz)
	if ax > hx + range or az > hz + range then
		return false
	end
	-- Inside the pen but far from every side does not count.
	return ax >= hx - range or az >= hz - range
end

local GOLDEN = math.pi * (3 - sqrt(5))

function PenLife.PileSlot(i: number, spacing: number): (number, number)
	if i <= 1 then
		return 0, 0
	end
	local r = spacing * sqrt(i - 1)
	local a = (i - 1) * GOLDEN
	return math.cos(a) * r, math.sin(a) * r
end

function PenLife.Ring(i: number, n: number, radius: number): (number, number)
	local a = (i - 1) / max(1, n) * TAU
	return math.cos(a) * radius, math.sin(a) * radius
end

function PenLife.Separation(
	x: number,
	z: number,
	xs: { number },
	zs: { number },
	rs: { number },
	n: number,
	skip: number,
	r: number,
	scale: number
): (number, number)
	local dx, dz = 0, 0
	for i = 1, n do
		if i ~= skip then
			local ox, oz = x - xs[i], z - zs[i]
			local want = (r + rs[i]) * scale
			local d2 = ox * ox + oz * oz
			if d2 < want * want then
				local d = sqrt(d2)
				if d < 1e-3 then
					-- Exactly on top of each other: split them by index so the pair parts ways.
					local a = (skip * 2.4 + i) % TAU
					ox, oz, d = math.cos(a), math.sin(a), 1
				else
					ox, oz = ox / d, oz / d
					d = (want - d) / want
				end
				dx += ox * d
				dz += oz * d
			end
		end
	end
	return dx, dz
end

function PenLife.Avoid(x: number, z: number, ox: { number }, oz: { number }, orr: { number }, n: number, pad: number): (number, number)
	local dx, dz = 0, 0
	for i = 1, n do
		local vx, vz = x - ox[i], z - oz[i]
		local want = orr[i] + pad
		local d2 = vx * vx + vz * vz
		if d2 < want * want and d2 > 1e-6 then
			local d = sqrt(d2)
			local push = (want - d) / want
			dx += vx / d * push
			dz += vz / d * push
		end
	end
	return dx, dz
end

function PenLife.Steer(
	x: number,
	z: number,
	gx: number,
	gz: number,
	sx: number,
	sz: number,
	ax: number,
	az: number,
	leg: number
): (number, number)
	local vx, vz = gx - x, gz - z
	local dist = sqrt(vx * vx + vz * vz)
	if dist < 1e-4 then
		return gx, gz
	end
	vx, vz = vx / dist, vz / dist
	local wx = vx + sx * 1.5 + ax * 2.5
	local wz = vz + sz * 1.5 + az * 2.5
	local wl = sqrt(wx * wx + wz * wz)
	if wl < 1e-4 then
		-- Pushes cancel the goal exactly: side-step.
		wx, wz, wl = -vz, vx, 1
	end
	local step = min(leg, dist)
	if step >= dist and sx == 0 and sz == 0 and ax == 0 and az == 0 then
		return gx, gz
	end
	return x + wx / wl * step, z + wz / wl * step
end

function PenLife.FleePoint(
	x: number,
	z: number,
	cx: number,
	cz: number,
	hx: number,
	hz: number,
	margin: number,
	distance: number
): (number, number)
	local vx, vz = x - cx, z - cz
	local d = sqrt(vx * vx + vz * vz)
	if d < 1e-3 then
		vx, vz, d = 1, 0, 1
	end
	vx, vz = vx / d, vz / d
	local fx, fz = PenLife.Clamp(x + vx * distance, z + vz * distance, hx, hz, margin)
	local gx, gz = fx - cx, fz - cz
	if gx * gx + gz * gz < (distance * 0.6) ^ 2 then
		-- Cornered: break sideways, toward the roomier side.
		local sx, sz = -vz, vx
		local ax, az = PenLife.Clamp(x + sx * distance, z + sz * distance, hx, hz, margin)
		local bx, bz = PenLife.Clamp(x - sx * distance, z - sz * distance, hx, hz, margin)
		local da = (ax - cx) ^ 2 + (az - cz) ^ 2
		local db = (bx - cx) ^ 2 + (bz - cz) ^ 2
		if da >= db then
			return ax, az
		end
		return bx, bz
	end
	return fx, fz
end

function PenLife.PickMate(n: number, self: number, free: { boolean }, roll: number): number?
	local count = 0
	for i = 1, n do
		if i ~= self and free[i] then
			count += 1
		end
	end
	if count == 0 then
		return nil
	end
	local pick = math.floor(clamp(roll, 0, 0.999999) * count) + 1
	for i = 1, n do
		if i ~= self and free[i] then
			pick -= 1
			if pick == 0 then
				return i
			end
		end
	end
	return nil
end

function PenLife.TurnYaw(from: number, to: number, maxStep: number): number
	local delta = (to - from + math.pi) % TAU - math.pi
	if abs(delta) <= maxStep then
		return to
	end
	return from + (if delta > 0 then maxStep else -maxStep)
end

function PenLife.ThinkRate(distance: number, onScreen: boolean, knob: number?): number
	local think = Cfg.Think
	local rate
	if distance <= think.near then
		rate = 1
	elseif distance <= think.mid then
		rate = 0.5
	elseif distance <= think.far then
		rate = 0.25
	else
		return 0
	end
	if not onScreen then
		rate *= think.offScreen
	end
	return rate * clamp(if knob == nil then 1 else knob, 0, 1)
end

return PenLife
