--!strict
-- Soundscape: layered, positional ambience as data (SO1 Soundscape Weaver).
--
--   local Soundscape = require("../Soundscape/Soundscape")
--   local s = Soundscape.new(adapter, scape, sink)       -- scape: packages/Soundscape/scapes/<game>.json
--   s:setSources("Fountain", { { id = "plaza", position = { 0, 3, 0 } } })
--   s:update(listener, dt, { phase = "day", weather = "rain", season = "spring", crowd = { hub = 0.6 } })
--   s:stats()  s:stop()
--   Soundscape.validate(scape) -> { problem }            Soundscape.weights(scape, listener) -> { [zoneId] = 0..1 }
--   Soundscape.occlusion(scape, from, to) -> 0..1        Soundscape.events(adapter, scape, index, slot) -> { event }
--
-- The package never creates Instances. It calls
--   sink({ op = "play" | "stop" | "fade" | "oneshot" | "reverb", id, sound, volume, position?, group, ... })
-- and the game's own audio system owns every Sound. Extra fields: `cue` (the scape's sound name),
-- `time` (fade seconds), `loop`, `rolloff` = { min, max }, `pitch` (one-shots), `preset` and `zone`
-- (reverb). `volume` never includes the group volume (the game's SoundGroups apply it) or distance
-- rolloff (the game's Sound applies it); it does include zone weight and occlusion.
--
-- Layers:
--   beds      2D loops per zone, gated by `when`; one voice per sound ("bed:<sound>"), loudest wins
--   oneShots  scattered one-shots; timing from Contract.Rng seeded by (seed, zone, index, time slot),
--             so every client hears the same events at the same world time
--   sources   positional loops on game-supplied points (setSources); culled past rolloff.max
--   crowd     murmur bands chosen by context.crowd[zone] density, weighted by the listener's zone weight
--   reverb    the preset of the dominant zone (weight >= 0.5, highest priority) that names one
-- Zone weight: 1 inside the shape, falling linearly to 0 over `blend` studs outside; zones are walked
-- by priority (high first) and a zone with mask ~= false takes its weight away from lower zones.
-- Handoff (optional `handoff = { mode = "sequential", fadeOut, fadeIn }`): the beds share ONE voice
--   ("bed:<sound>" of the loudest wanted bed, ties by id) and never overlap. A per-frame fader over
--   update's dt (nil dt = the adapter time since the last update): a change fades the playing bed
--   from its level to 0 (fade over level x fadeOut, `at` = now - dt since this frame's dt already
--   counts), then stops it (time 0) and plays the next (fading in over fadeIn, `at` = now); a
--   change back fades the same bed up again. The channel's voice counts against the budget first.
--   Without `handoff` nothing changes: every wanted bed is its own voice and they crossfade.
-- Voice budget: adapter.budget("voices") (nil = unlimited). Every update ranks every wanted voice by
-- audibility (volume x group volume x distance rolloff x occlusion) and keeps the loudest; the rest
-- are stopped (loops) or never started (new one-shots). Ties break by voice id, so it is stable.

local Contract = require("../Contract/Contract")

export type Sink = (cmd: { [string]: any }) -> ()

local Soundscape = {}

local Methods = {}
Methods.__index = Methods

Soundscape.SLOT = 10 -- seconds per one-shot time slot (a one-shot may override with `slot`)
Soundscape.CATCHUP = 2 -- an update never fires one-shots older than this many seconds
Soundscape.EPS = 0.01 -- a loop's volume must move this much before a new "fade" is sent
Soundscape.ONESHOT_LENGTH = 2 -- seconds a one-shot holds a voice unless it says `length`
Soundscape.DEFAULT_FADE = 2
Soundscape.OCCLUSION_SAMPLES = 16
Soundscape.SHAPES = { box = true, sphere = true, polygon = true, world = true }
Soundscape.GROUPS = { Ambience = true, Music = true, SFX = true, UI = true }

local TWO32 = 4294967296

-- small helpers ------------------------------------------------------------------------------

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v
end

local function vec(v: any): (number, number, number)
	if v == nil then
		return 0, 0, 0
	end
	if type(v) == "table" then
		if v[1] ~= nil then
			return v[1], v[2] or 0, v[3] or 0
		end
		if v.x ~= nil then
			return v.x, v.y or 0, v.z or 0
		end
	end
	-- a Vector3 (or anything with X/Y/Z)
	local ok, x, y, z = pcall(function()
		return (v :: any).X, (v :: any).Y, (v :: any).Z
	end)
	if ok and type(x) == "number" then
		return x, y, z
	end
	return 0, 0, 0
end

local function fnv(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		-- x the FNV prime (2^24 + 403) mod 2^32 without leaving exact double range
		h = (bit32.lshift(h, 24) + h * 403) % TWO32
	end
	return h
end
Soundscape.hash = fnv


local function isVec3(v: any): boolean
	return type(v) == "table" and #v == 3 and isNumber(v[1]) and isNumber(v[2]) and isNumber(v[3])
end

-- conditions ---------------------------------------------------------------------------------

local WHEN_KEYS = { "phase", "weather", "season" }

local function matchOne(cond: any, value: any): boolean
	if cond == nil then
		return true
	end
	if type(cond) == "string" then
		return value == cond
	end
	if type(cond) == "table" then
		if cond["not"] ~= nil then
			if value == nil then
				return true
			end
			for _, v in cond["not"] do
				if v == value then
					return false
				end
			end
			return true
		end
		if value == nil then
			return false
		end
		for _, v in cond do
			if v == value then
				return true
			end
		end
	end
	return false
end

function Soundscape.when(cond: any, context: any): boolean
	if cond == nil then
		return true
	end
	local ctx = context or {}
	for _, k in WHEN_KEYS do
		if not matchOne(cond[k], ctx[k]) then
			return false
		end
	end
	return true
end

-- shapes and zones ---------------------------------------------------------------------------

local function pointInPolygon(points: { any }, x: number, z: number): boolean
	local inside = false
	local n = #points
	local j = n
	for i = 1, n do
		local xi, zi = points[i][1], points[i][2]
		local xj, zj = points[j][1], points[j][2]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function segDist(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cz = ax + dx * t, az + dz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- Distance from a point to a shape (0 = inside).
function Soundscape.distance(shape: any, p: any): number
	local x, y, z = vec(p)
	local kind = shape.type
	if kind == "world" then
		return 0
	elseif kind == "box" then
		local cx, cy, cz = vec(shape.center)
		local sx, sy, sz = vec(shape.size)
		local ex = math.max(0, math.abs(x - cx) - sx / 2)
		local ey = math.max(0, math.abs(y - cy) - sy / 2)
		local ez = math.max(0, math.abs(z - cz) - sz / 2)
		return math.sqrt(ex * ex + ey * ey + ez * ez)
	elseif kind == "sphere" then
		local cx, cy, cz = vec(shape.center)
		if shape.flat then
			-- a vertical cylinder: flat (XZ) distance, optionally capped by yMin / yMax
			local ex = math.max(0, math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2) - shape.radius)
			local ey = 0
			if isNumber(shape.yMin) and y < shape.yMin then
				ey = shape.yMin - y
			elseif isNumber(shape.yMax) and y > shape.yMax then
				ey = y - shape.yMax
			end
			return math.sqrt(ex * ex + ey * ey)
		end
		return math.max(0, math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2) - shape.radius)
	elseif kind == "polygon" then
		local pts = shape.points
		local flatD = 0
		if not pointInPolygon(pts, x, z) then
			flatD = math.huge
			local n = #pts
			for i = 1, n do
				local a, b = pts[i], pts[(i % n) + 1]
				flatD = math.min(flatD, segDist(x, z, a[1], a[2], b[1], b[2]))
			end
		end
		local ey = 0
		if isNumber(shape.yMin) and y < shape.yMin then
			ey = shape.yMin - y
		elseif isNumber(shape.yMax) and y > shape.yMax then
			ey = y - shape.yMax
		end
		return math.sqrt(flatD * flatD + ey * ey)
	end
	return math.huge
end

function Soundscape.inside(shape: any, p: any): boolean
	return Soundscape.distance(shape, p) <= 0
end

local function rawWeight(zone: any, listener: any): number
	if listener == nil then
		return if zone.shape.type == "world" then 1 else 0
	end
	local d = Soundscape.distance(zone.shape, listener)
	if d <= 0 then
		return 1
	end
	local blend = zone.blend or 0
	if blend <= 0 then
		return 0
	end
	return math.clamp(1 - d / blend, 0, 1)
end

local function zoneOrder(scape: any): { any }
	local list = table.clone(scape.zones)
	table.sort(list, function(a, b)
		local pa, pb = a.priority or 0, b.priority or 0
		if pa ~= pb then
			return pa > pb
		end
		return a.id < b.id
	end)
	return list
end

-- { [zoneId] = effective weight 0..1 }
function Soundscape.weights(scape: any, listener: any, order: { any }?): { [string]: number }
	local out = {}
	local remaining = 1
	for _, zone in order or zoneOrder(scape) do
		local raw = rawWeight(zone, listener)
		out[zone.id] = raw * remaining
		if zone.mask ~= false then
			remaining *= 1 - raw
		end
	end
	return out
end

-- occlusion ----------------------------------------------------------------------------------
-- For every zone with `walls = { loss = 0..1, absorb = per stud }`: a sound whose source and
-- listener are on different sides of the zone's boundary loses `loss` once; a path that enters and
-- leaves a zone (neither end inside) loses it twice; and any path through the zone that does not
-- stay inside it loses exp(-absorb x studs inside), sampled along the straight line.
function Soundscape.occlusion(scape: any, from: any, to: any): number
	if from == nil or to == nil then
		return 1
	end
	local ax, ay, az = vec(from)
	local bx, by, bz = vec(to)
	local factor = 1
	local n = Soundscape.OCCLUSION_SAMPLES
	for _, zone in scape.zones do
		local walls = zone.walls
		if walls and zone.shape.type ~= "world" then
			local inA = Soundscape.inside(zone.shape, from)
			local inB = Soundscape.inside(zone.shape, to)
			if not (inA and inB) then
				local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
				local hits = 0
				for i = 0, n - 1 do
					local t = (i + 0.5) / n
					if Soundscape.inside(zone.shape, { ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t }) then
						hits += 1
					end
				end
				local through = len * hits / n
				local crossings = if inA ~= inB then 1 elseif hits > 0 then 2 else 0
				factor *= (1 - (walls.loss or 0)) ^ crossings * math.exp(-(walls.absorb or 0) * through)
			end
		end
	end
	return factor
end

-- Distance rolloff used only for ranking voices (the game's Sound does its own): 1 within min,
-- inverse-tapered to 0 at max.
function Soundscape.rolloff(d: number, min: number, max: number): number
	if d <= min then
		return 1
	elseif d >= max then
		return 0
	end
	return (min / d) * (1 - (d - min) / (max - min))
end

-- validation ---------------------------------------------------------------------------------

local function checkWhen(p: { string }, where: string, when: any)
	if when == nil then
		return
	end
	if type(when) ~= "table" then
		table.insert(p, `{where}.when must be a table`)
		return
	end
	for k, v in when do
		if not table.find(WHEN_KEYS, k) then
			table.insert(p, `{where}.when: unknown key {k}`)
		elseif type(v) == "table" and v["not"] ~= nil then
			if type(v["not"]) ~= "table" or #v["not"] == 0 then
				table.insert(p, `{where}.when.{k}.not must be a non-empty list`)
			end
		elseif type(v) == "table" then
			if #v == 0 then
				table.insert(p, `{where}.when.{k} is an empty list (nothing can match)`)
			end
		elseif type(v) ~= "string" then
			table.insert(p, `{where}.when.{k} must be a string, a list or \{ not = list }`)
		end
	end
end

local function checkVolume(p: { string }, where: string, v: any)
	if not isNumber(v) or v < 0 or v > 10 then
		table.insert(p, `{where}.volume must be a number 0..10`)
	end
end

function Soundscape.validate(scape: any): { string }
	local p: { string } = {}
	if type(scape) ~= "table" then
		return { "scape must be a table" }
	end
	local zones: { [string]: any } = {}
	if type(scape.zones) ~= "table" or #scape.zones == 0 then
		table.insert(p, "zones must be a non-empty list")
	else
		for i, z in scape.zones do
			local where = `zones[{i}]`
			if type(z.id) ~= "string" or z.id == "" then
				table.insert(p, `{where}.id must be a string`)
			elseif zones[z.id] then
				table.insert(p, `{where}: duplicate zone id {z.id}`)
			else
				zones[z.id] = z
			end
			local s = z.shape
			if type(s) ~= "table" or not Soundscape.SHAPES[s.type] then
				table.insert(p, `{where}.shape.type must be box, sphere, polygon or world`)
			elseif s.type == "box" then
				if not isVec3(s.center) or not isVec3(s.size) then
					table.insert(p, `{where}.shape: a box needs center and size [x,y,z]`)
				elseif s.size[1] <= 0 or s.size[2] <= 0 or s.size[3] <= 0 then
					table.insert(p, `{where}.shape: box size must be positive`)
				end
			elseif s.type == "sphere" then
				if not isVec3(s.center) or not isNumber(s.radius) or s.radius <= 0 then
					table.insert(p, `{where}.shape: a sphere needs center [x,y,z] and radius > 0`)
				end
				if (s.yMin ~= nil or s.yMax ~= nil) and not s.flat then
					table.insert(p, `{where}.shape: yMin / yMax need flat = true`)
				end
				if isNumber(s.yMin) and isNumber(s.yMax) and s.yMin >= s.yMax then
					table.insert(p, `{where}.shape: yMin must be below yMax`)
				end
			elseif s.type == "polygon" then
				local ok = type(s.points) == "table" and #s.points >= 3
				if ok then
					for _, pt in s.points do
						if type(pt) ~= "table" or not isNumber(pt[1]) or not isNumber(pt[2]) then
							ok = false
						end
					end
				end
				if not ok then
					table.insert(p, `{where}.shape: a polygon needs 3+ points [x,z]`)
				end
				if isNumber(s.yMin) and isNumber(s.yMax) and s.yMin >= s.yMax then
					table.insert(p, `{where}.shape: yMin must be below yMax`)
				end
			end
			if z.priority ~= nil and not isNumber(z.priority) then
				table.insert(p, `{where}.priority must be a number`)
			end
			if z.blend ~= nil and (not isNumber(z.blend) or z.blend < 0) then
				table.insert(p, `{where}.blend must be a number >= 0`)
			end
			if z.walls ~= nil then
				local w = z.walls
				if type(w) ~= "table" or (w.loss ~= nil and (not isNumber(w.loss) or w.loss < 0 or w.loss > 1)) or (w.absorb ~= nil and (not isNumber(w.absorb) or w.absorb < 0)) then
					table.insert(p, `{where}.walls: loss must be 0..1 and absorb >= 0`)
				end
			end
		end
	end
	local cues = scape.cues
	local function checkSound(where: string, s: any)
		if type(s) ~= "string" or s == "" then
			table.insert(p, `{where} must be a non-empty string`)
		elseif type(cues) == "table" and string.sub(s, 1, 13) ~= "rbxassetid://" and cues[s] == nil and not string.find(s, "/", 1, true) then
			table.insert(p, `{where}: {s} is not a cue, an rbxassetid or a Vault key`)
		end
	end
	local function checkZone(where: string, id: any)
		if type(id) ~= "string" or zones[id] == nil then
			table.insert(p, `{where}.zone {tostring(id)} is not a zone`)
		end
	end
	local function checkGroup(where: string, g: any)
		if g ~= nil and not Soundscape.GROUPS[g] then
			table.insert(p, `{where}.group {tostring(g)} is not Ambience, Music, SFX or UI`)
		end
	end
	if scape.handoff ~= nil then
		local h = scape.handoff
		if type(h) ~= "table" or h.mode ~= "sequential" then
			table.insert(p, 'handoff must be { mode = "sequential", fadeOut, fadeIn }')
		elseif not isNumber(h.fadeOut) or h.fadeOut < 0 or not isNumber(h.fadeIn) or h.fadeIn < 0 then
			table.insert(p, "handoff.fadeOut and handoff.fadeIn must be numbers >= 0")
		end
	end
	for i, b in scape.beds or {} do
		local where = `beds[{i}]`
		checkZone(where, b.zone)
		checkSound(where .. ".sound", b.sound)
		checkWhen(p, where, b.when)
		checkVolume(p, where, b.volume)
		checkGroup(where, b.group)
		if b.fade ~= nil and (not isNumber(b.fade) or b.fade < 0) then
			table.insert(p, `{where}.fade must be >= 0`)
		end
	end
	for i, o in scape.oneShots or {} do
		local where = `oneShots[{i}]`
		checkZone(where, o.zone)
		if type(o.sounds) ~= "table" or #o.sounds == 0 then
			table.insert(p, `{where}.sounds must be a non-empty list`)
		else
			for j, s in o.sounds do
				checkSound(`{where}.sounds[{j}]`, s)
			end
		end
		if not isNumber(o.perMinute) or o.perMinute < 0 or o.perMinute > 600 then
			table.insert(p, `{where}.perMinute must be 0..600`)
		end
		if o.radius ~= nil and (not isNumber(o.radius) or o.radius < 0) then
			table.insert(p, `{where}.radius must be >= 0`)
		end
		if o.slot ~= nil and (not isNumber(o.slot) or o.slot <= 0) then
			table.insert(p, `{where}.slot must be > 0`)
		end
		if o.pitch ~= nil and (type(o.pitch) ~= "table" or not isNumber(o.pitch[1]) or not isNumber(o.pitch[2]) or o.pitch[1] > o.pitch[2] or o.pitch[1] <= 0) then
			table.insert(p, `{where}.pitch must be [lo, hi] with 0 < lo <= hi`)
		end
		checkWhen(p, where, o.when)
		checkVolume(p, where, o.volume)
		checkGroup(where, o.group)
	end
	for i, s in scape.sources or {} do
		local where = `sources[{i}]`
		if type(s.tag) ~= "string" or s.tag == "" then
			table.insert(p, `{where}.tag must be a string`)
		end
		checkSound(where .. ".sound", s.sound)
		checkWhen(p, where, s.when)
		checkVolume(p, where, s.volume)
		checkGroup(where, s.group)
		if s.zone ~= nil then
			checkZone(where, s.zone)
		end
		local r = s.rolloff
		if type(r) ~= "table" or not isNumber(r.min) or not isNumber(r.max) or r.min <= 0 or r.min >= r.max then
			table.insert(p, `{where}.rolloff must be \{ min > 0, max > min }`)
		end
	end
	if scape.crowd ~= nil then
		local c = scape.crowd
		if type(c) ~= "table" or type(c.bands) ~= "table" or #c.bands == 0 then
			table.insert(p, "crowd.bands must be a non-empty list")
		else
			local last = -1
			for i, b in c.bands do
				local where = `crowd.bands[{i}]`
				if not isNumber(b.min) or b.min < 0 or b.min > 1 then
					table.insert(p, `{where}.min must be 0..1`)
				elseif b.min <= last then
					table.insert(p, `{where}.min must rise band by band`)
				else
					last = b.min
				end
				checkSound(where .. ".sound", b.sound)
				checkVolume(p, where, b.volume)
			end
			checkGroup("crowd", c.group)
			for _, id in c.zones or {} do
				checkZone("crowd.zones", id)
			end
		end
	end
	local reverbZones: { [string]: boolean } = {}
	for i, r in scape.reverb or {} do
		local where = `reverb[{i}]`
		checkZone(where, r.zone)
		if type(r.preset) ~= "string" or r.preset == "" then
			table.insert(p, `{where}.preset must be a string`)
		end
		if type(r.zone) == "string" then
			if reverbZones[r.zone] then
				table.insert(p, `{where}: zone {r.zone} already has a reverb`)
			end
			reverbZones[r.zone] = true
		end
	end
	if scape.groups ~= nil then
		for g, v in scape.groups do
			if not Soundscape.GROUPS[g] then
				table.insert(p, `groups.{g} is not Ambience, Music, SFX or UI`)
			elseif not isNumber(v) or v < 0 or v > 1 then
				table.insert(p, `groups.{g} must be 0..1`)
			end
		end
	end
	return p
end

-- one-shot timing ----------------------------------------------------------------------------

export type Event = { at: number, sound: string, angle: number, dist: number, pitch: number, index: number, j: number }

-- The events one-shot entry `index` schedules in time slot `slot`: the same on every client.
function Soundscape.events(adapter: any, scape: any, index: number, slot: number): { Event }
	local o = scape.oneShots[index]
	local len = o.slot or Soundscape.SLOT
	local seed = fnv(`{scape.seed or 0}|{o.zone}|{index}|{slot}`)
	local rng = adapter.rng(seed)
	local expected = (o.perMinute or 0) * len / 60
	local count = math.floor(expected)
	if rng:next() < expected - count then
		count += 1
	end
	local out: { Event } = {}
	local lo = if o.pitch then o.pitch[1] else 1
	local hi = if o.pitch then o.pitch[2] else 1
	for j = 1, count do
		local at = slot * len + rng:next() * len
		local sound = o.sounds[rng:int(1, #o.sounds)]
		local angle = rng:next() * math.pi * 2
		local dist = (o.radius or 0) * (0.35 + 0.65 * rng:next())
		local pitch = lo + (hi - lo) * rng:next()
		table.insert(out, { at = at, sound = sound, angle = angle, dist = dist, pitch = pitch, index = index, j = j })
	end
	table.sort(out, function(a, b)
		return a.at < b.at
	end)
	return out
end

-- construction -------------------------------------------------------------------------------

function Soundscape.new(adapter: Contract.Adapter, scape: any, sink: Sink)
	local problems = Contract.check(adapter)
	assert(#problems == 0, "Soundscape.new: " .. table.concat(problems, "; "))
	local bad = Soundscape.validate(scape)
	assert(#bad == 0, "Soundscape.new: invalid scape: " .. table.concat(bad, "; "))
	assert(type(sink) == "function", "Soundscape.new needs a sink function")
	local self = setmetatable({
		adapter = adapter,
		scape = scape,
		sink = sink,
		order = zoneOrder(scape),
		points = {} :: { [string]: { any } },
		voices = {} :: { [string]: any }, -- playing loops: id -> { sound, volume, group, position }
		shots = {} :: { [string]: any }, -- one-shots holding a voice: id -> { volume, audible, ends }
		slotCache = {} :: { [string]: { Event } },
		lastT = nil :: number?,
		reverbPreset = nil :: string?,
		weightsNow = {} :: { [string]: number },
		denied = {} :: { [string]: boolean }, -- loops wanted but outside the voice budget this update
		channel = { level = 0, dir = 0 } :: any, -- the sequential handoff's bed voice: id?, entry?, level, dir
		counters = { played = 0, stopped = 0, oneshots = 0, dropped = 0, sinkErrors = 0 },
	}, Methods)
	return self
end

-- points: { { id = string?, position = vec } } or { vec }
function Methods.setSources(self: any, tag: string, points: { any }?)
	self.points[tag] = points or {}
end

function Methods.send(self: any, cmd: { [string]: any })
	local ok, err = pcall(self.sink, cmd)
	if not ok then
		self.counters.sinkErrors += 1
		self.adapter.log("warn", "Soundscape sink failed", { op = cmd.op, id = cmd.id, err = tostring(err) })
	end
end

local function resolve(scape: any, name: string): string
	local cues = scape.cues
	if type(cues) == "table" then
		local c = cues[name]
		if type(c) == "table" and type(c.sound) == "string" and c.sound ~= "" then
			return c.sound
		end
	end
	return name
end

local function groupVolume(scape: any, group: string): number
	local g = scape.groups
	if type(g) == "table" and isNumber(g[group]) then
		return g[group]
	end
	return 1
end

local function dist3(a: any, b: any): number
	local ax, ay, az = vec(a)
	local bx, by, bz = vec(b)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

-- The loops the scape wants now: id -> { sound, cue, volume, audible, group, fade, position?, rolloff?, loop }
function Methods.wanted(self: any, listener: any, context: any): { [string]: any }
	local scape = self.scape
	local w = self.weightsNow
	local want: { [string]: any } = {}
	local function offer(id: string, entry: any)
		if entry.volume <= 1e-4 or entry.audible <= 1e-4 then
			return
		end
		local cur = want[id]
		if cur == nil or entry.audible > cur.audible then
			want[id] = entry
		end
	end
	local fadeDefault = scape.fade or Soundscape.DEFAULT_FADE
	for _, b in scape.beds or {} do
		local zw = w[b.zone] or 0
		if zw > 0 and Soundscape.when(b.when, context) then
			local group = b.group or "Ambience"
			local v = b.volume * zw
			offer("bed:" .. b.sound, {
				sound = resolve(scape, b.sound),
				cue = b.sound,
				volume = v,
				audible = v * groupVolume(scape, group),
				group = group,
				fade = b.fade or fadeDefault,
				loop = true,
			})
		end
	end
	for _, s in scape.sources or {} do
		local zw = if s.zone then (w[s.zone] or 0) else 1
		if zw > 0 and Soundscape.when(s.when, context) then
			local group = s.group or "Ambience"
			for i, pt in self.points[s.tag] or {} do
				local pos = if type(pt) == "table" and pt.position ~= nil then pt.position else pt
				local pid = if type(pt) == "table" and pt.id ~= nil then tostring(pt.id) else tostring(i)
				local d = if listener ~= nil then dist3(listener, pos) else 0
				if d < s.rolloff.max then
					local occ = Soundscape.occlusion(scape, listener, pos)
					local v = s.volume * zw * occ
					offer(`src:{s.tag}:{pid}`, {
						sound = resolve(scape, s.sound),
						cue = s.sound,
						volume = v,
						audible = v * groupVolume(scape, group) * Soundscape.rolloff(d, s.rolloff.min, s.rolloff.max),
						group = group,
						fade = s.fade or fadeDefault,
						position = pos,
						rolloff = { min = s.rolloff.min, max = s.rolloff.max },
						loop = s.loop ~= false,
					})
				end
			end
		end
	end
	local crowd = scape.crowd
	local density = if type(context) == "table" then context.crowd else nil
	if crowd ~= nil and type(density) == "table" then
		local group = crowd.group or "Ambience"
		local allowed: { [string]: boolean } = {}
		local anyZone = crowd.zones == nil
		for _, id in crowd.zones or {} do
			allowed[id] = true
		end
		for _, zone in self.order do
			local d = density[zone.id]
			local zw = w[zone.id] or 0
			if isNumber(d) and d > 0 and zw > 0 and (anyZone or allowed[zone.id]) then
				local band = Soundscape.band(crowd, d)
				if band then
					local v = band.volume * zw
					offer("crowd:" .. band.sound, {
						sound = resolve(scape, band.sound),
						cue = band.sound,
						volume = v,
						audible = v * groupVolume(scape, group),
						group = group,
						fade = crowd.fade or fadeDefault,
						loop = true,
					})
				end
			end
		end
	end
	return want
end

-- The crowd band for a density (the last band whose min <= density), or nil below the first band.
function Soundscape.band(crowd: any, density: number): any
	local pick = nil
	for _, b in crowd.bands do
		if density >= b.min then
			pick = b
		end
	end
	return pick
end

function Methods.dueShots(self: any, listener: any, context: any, t0: number, t1: number): { [string]: any }
	local scape = self.scape
	local out: { [string]: any } = {}
	for index, o in scape.oneShots or {} do
		local zw = self.weightsNow[o.zone] or 0
		if zw > 0 and (o.perMinute or 0) > 0 and Soundscape.when(o.when, context) then
			local len = o.slot or Soundscape.SLOT
			for slot = math.floor(t0 / len), math.floor(t1 / len) do
				local key = `{index}|{slot}`
				local events = self.slotCache[key]
				if events == nil then
					events = Soundscape.events(self.adapter, scape, index, slot)
					self.slotCache[key] = events
				end
				for _, e in events do
					if e.at > t0 and e.at <= t1 then
						local group = o.group or "Ambience"
						local v = o.volume * zw
						local pos = nil
						if (o.radius or 0) > 0 then
							local lx, ly, lz = vec(listener)
							pos = { lx + math.cos(e.angle) * e.dist, ly, lz + math.sin(e.angle) * e.dist }
						end
						out[`one:{o.zone}:{index}:{slot}:{e.j}`] = {
							sound = resolve(scape, e.sound),
							cue = e.sound,
							volume = v,
							audible = v * groupVolume(scape, group),
							group = group,
							position = pos,
							pitch = e.pitch,
							ends = e.at + (o.length or Soundscape.ONESHOT_LENGTH),
							at = e.at,
						}
					end
				end
			end
		end
	end
	return out
end

local function sortRanked(list: { any })
	table.sort(list, function(a, b)
		if a.entry.audible ~= b.entry.audible then
			return a.entry.audible > b.entry.audible
		end
		return a.id < b.id
	end)
end

-- The sequential handoff's bed channel for one update (see the header): `id`/`entry` = the bed
-- wanted now (nil = none), `step` = this frame's dt.
function Methods.stepChannel(self: any, id: string?, entry: any, now: number, step: number)
	local h = self.scape.handoff
	local ch = self.channel
	local function cmd(op: string, volume: number, time: number, at: number)
		local e = ch.entry
		self:send({ op = op, id = ch.id, sound = e.sound, cue = e.cue, volume = volume, group = e.group, time = time, at = at, loop = if op == "play" then true else nil })
	end
	if ch.id ~= id then
		if ch.id ~= nil and ch.level > 0 then
			if ch.dir ~= -1 then
				ch.dir = -1
				cmd("fade", 0, ch.level * h.fadeOut, now - step)
			end
			ch.level = if h.fadeOut > 0 then math.max(0, ch.level - step / h.fadeOut) else 0
			if ch.level > 0 then
				return
			end
		end
		if ch.id ~= nil then
			self.counters.stopped += 1
			cmd("stop", 0, 0, now)
		end
		ch.id, ch.entry, ch.level, ch.dir = id, entry, 0, 0
		if id ~= nil then
			ch.dir = 1
			self.counters.played += 1
			cmd("play", entry.volume, h.fadeIn, now)
		end
		return
	end
	if id == nil then
		return
	end
	if math.abs(entry.volume - ch.entry.volume) >= Soundscape.EPS and ch.dir == 1 then
		ch.entry = entry
		cmd("fade", entry.volume, if ch.level < 1 then (1 - ch.level) * h.fadeIn else entry.fade, now)
	end
	if ch.level < 1 then
		if ch.dir ~= 1 then
			ch.dir = 1
			cmd("fade", ch.entry.volume, (1 - ch.level) * h.fadeIn, now - step)
		end
		ch.level = if h.fadeIn > 0 then math.min(1, ch.level + step / h.fadeIn) else 1
	end
end

function Methods.update(self: any, listener: any, dt: number?, context: any?)
	local now = self.adapter.now()
	local scape = self.scape
	self.weightsNow = Soundscape.weights(scape, listener, self.order)
	local want = self:wanted(listener, context)
	local step = if dt ~= nil then math.max(0, dt) else math.max(0, now - (self.lastT or now))
	local reserved = 0
	if scape.handoff then
		-- the beds leave the voice race: one channel plays the loudest (ties by id)
		local bestId, best = nil, nil
		for id, e in want do
			if string.sub(id, 1, 4) == "bed:" then
				if best == nil or e.audible > best.audible or (e.audible == best.audible and id < (bestId :: string)) then
					bestId, best = id, e
				end
				want[id] = nil
			end
		end
		self:stepChannel(bestId, best, now, step)
		reserved = if self.channel.id ~= nil then 1 else 0
	end
	local t1 = now
	local t0 = if self.lastT == nil then now else math.max(self.lastT, now - Soundscape.CATCHUP)
	self.lastT = now
	local fresh = if t1 > t0 then self:dueShots(listener, context, t0, t1) else {}
	-- expire one-shots and forget old slot caches
	for id, s in self.shots do
		if s.ends <= now then
			self.shots[id] = nil
		end
	end
	for key in self.slotCache do
		local index, slot = string.match(key, "^(%d+)|(%-?%d+)$")
		local o = scape.oneShots[tonumber(index) :: number]
		local len = o.slot or Soundscape.SLOT
		if (tonumber(slot) :: number) < math.floor(now / len) - 1 then
			self.slotCache[key] = nil
		end
	end

	-- rank every candidate voice
	local ranked = {}
	for id, e in want do
		table.insert(ranked, { id = id, entry = e, kind = "loop" })
	end
	for id, s in self.shots do
		table.insert(ranked, { id = id, entry = s, kind = "held" })
	end
	for id, e in fresh do
		table.insert(ranked, { id = id, entry = e, kind = "new" })
	end
	sortRanked(ranked)
	local cap = self.adapter.budget("voices")
	local limit = if isNumber(cap) then math.max(0, math.floor(cap :: number) - reserved) else math.huge
	local keptLoops: { [string]: any } = {}
	local denied: { [string]: boolean } = {}
	local newShots = {}
	for i, r in ranked do
		local keep = i <= limit
		if r.kind == "loop" then
			if keep then
				keptLoops[r.id] = r.entry
			else
				denied[r.id] = true
			end
		elseif r.kind == "held" then
			if not keep then
				self.shots[r.id] = nil
			end
		elseif keep then
			table.insert(newShots, r)
		else
			self.counters.dropped += 1
		end
	end

	-- stop loops that are no longer wanted (or lost their voice), sorted for a stable stream
	local stopping = {}
	for id in self.voices do
		if keptLoops[id] == nil then
			table.insert(stopping, id)
		end
	end
	table.sort(stopping)
	for _, id in stopping do
		local v = self.voices[id]
		self.voices[id] = nil
		if want[id] ~= nil then
			self.counters.dropped += 1
		end
		self.counters.stopped += 1
		self:send({ op = "stop", id = id, sound = v.sound, cue = v.cue, volume = 0, group = v.group, time = if want[id] then 0 else v.fade })
	end
	local ids = {}
	for id in keptLoops do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local e = keptLoops[id]
		local v = self.voices[id]
		if v == nil then
			self.voices[id] = { sound = e.sound, cue = e.cue, volume = e.volume, group = e.group, fade = e.fade, position = e.position }
			self.counters.played += 1
			self:send({
				op = "play",
				id = id,
				sound = e.sound,
				cue = e.cue,
				volume = e.volume,
				position = e.position,
				group = e.group,
				time = e.fade,
				loop = e.loop,
				rolloff = e.rolloff,
			})
		elseif math.abs(v.volume - e.volume) >= Soundscape.EPS or (e.volume <= 1e-4) ~= (v.volume <= 1e-4) or v.position ~= e.position then
			v.volume = e.volume
			v.position = e.position
			v.fade = e.fade
			self:send({ op = "fade", id = id, sound = e.sound, cue = e.cue, volume = e.volume, position = e.position, group = e.group, time = e.fade })
		end
	end
	self.denied = denied
	table.sort(newShots, function(a, b)
		if a.entry.at ~= b.entry.at then
			return a.entry.at < b.entry.at
		end
		return a.id < b.id
	end)
	for _, r in newShots do
		local e = r.entry
		self.shots[r.id] = e
		self.counters.oneshots += 1
		self:send({ op = "oneshot", id = r.id, sound = e.sound, cue = e.cue, volume = e.volume, position = e.position, group = e.group, pitch = e.pitch })
	end

	-- reverb: the highest-priority zone the listener is (mostly) in that names a preset
	local preset, rzone = "NoReverb", nil
	if scape.reverb then
		local byZone: { [string]: string } = {}
		for _, r in scape.reverb do
			byZone[r.zone] = r.preset
		end
		for _, zone in self.order do
			if byZone[zone.id] and (self.weightsNow[zone.id] or 0) >= 0.5 then
				preset, rzone = byZone[zone.id], zone.id
				break
			end
		end
	end
	if preset ~= self.reverbPreset then
		self.reverbPreset = preset
		self:send({ op = "reverb", id = "reverb", preset = preset, zone = rzone, sound = preset, volume = 1, group = "Ambience" })
	end
end

function Methods.stop(self: any)
	local ids = {}
	for id in self.voices do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local v = self.voices[id]
		self.voices[id] = nil
		self.counters.stopped += 1
		self:send({ op = "stop", id = id, sound = v.sound, cue = v.cue, volume = 0, group = v.group, time = 0 })
	end
	local ch = self.channel
	if ch.id ~= nil then
		self.counters.stopped += 1
		self:send({ op = "stop", id = ch.id, sound = ch.entry.sound, cue = ch.entry.cue, volume = 0, group = ch.entry.group, time = 0 })
		ch.id, ch.entry, ch.level, ch.dir = nil, nil, 0, 0
	end
	self.shots = {}
end

function Methods.stats(self: any)
	local playing, held = 0, 0
	local list = {}
	for id, v in self.voices do
		playing += 1
		list[id] = v.volume
	end
	if self.channel.id ~= nil then
		playing += 1
		list[self.channel.id] = self.channel.entry.volume * self.channel.level
	end
	for _ in self.shots do
		held += 1
	end
	local c = self.counters
	local denied = 0
	for _ in self.denied do
		denied += 1
	end
	return {
		denied = denied,
		playing = playing,
		oneshotsHeld = held,
		voices = playing + held,
		volumes = list,
		weights = table.clone(self.weightsNow),
		reverb = self.reverbPreset,
		played = c.played,
		stopped = c.stopped,
		oneshots = c.oneshots,
		dropped = c.dropped,
		sinkErrors = c.sinkErrors,
	}
end

return Soundscape
