--!strict
-- Wildlife rules: defaults per behaviour, validation, hashing and the spot index.
--
--   Rules.validate(spec) -> { problem }          every problem, never throws
--   Rules.normalise(spec) -> spec                 a copy with every default filled in
--   Rules.hash(...) -> uint32                     FNV-1a over "a|b|c" (Almanac's hash)
--   Rules.index(spec) -> index                    grid of spots + per-spot spawn entries

local Rules = {}

local TWO32 = 4294967296

local function imul(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local mid = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return (aLo * bLo + mid * 65536) % TWO32
end

function Rules.hash(...: any): number
	local parts = table.pack(...)
	local strs = table.create(parts.n)
	for i = 1, parts.n do
		strs[i] = tostring(parts[i])
	end
	local s = table.concat(strs, "|")
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = imul(h, 16777619)
	end
	return h
end

Rules.BEHAVIOURS = { flock = true, drift = true, swim = true, stray = true }

-- Default clip names match the Creature Workshop's critters pack (idle + a move clip + flee).
local DEFAULTS: { [string]: { [string]: any } } = {
	flock = {
		cost = 5,
		max = { 0, 4, 8 },
		radius = 90,
		phases = { "dawn", "day" },
		roostPhases = {},
		perchOn = { "roof", "perch" },
		roostOn = { "roost" },
		flock = { 2, 5 },
		bucket = 120,
		chance = 1,
		range = 40,
		tick = 0.1,
		speed = 14,
		minSpeed = 3,
		maxAccel = 40,
		view = 8,
		minSep = 0.8,
		weights = { separation = 6, alignment = 0.8, cohesion = 0.6, goal = 3 },
		slow = 6,
		landDist = 0.35,
		approach = 45,
		height = 25,
		spread = 3,
		arrive = { 0, 20 }, -- seconds after the bucket start the flock arrives (seeded)
		perch = { 0.5, 0.85 }, -- takeoff at this fraction of the bucket (seeded)
		leaveSeconds = 8,
		scare = 12,
		scareSpeed = 10,
		fleeDistance = 25,
		fleeSeconds = 1.5,
		returnAfter = { 6, 12 },
		maxRain = 0.2,
		anims = { perch = "idle", roost = "idle", land = "fly", takeoff = "fly", fly = "fly", flee = "flee", leave = "fly" },
	},
	drift = {
		cost = 1,
		max = { 0, 8, 8 },
		radius = 80,
		phases = { "dawn", "day" },
		on = { "flower" },
		bucket = 120,
		fade = 2,
		drift = { amp = 2.5, height = 1.2, bob = 0.6, freq = { 0.9, 1.7, 0.7 } },
		glow = false,
		maxRain = 0.2,
		anims = { drift = "fly" },
	},
	swim = {
		cost = 2,
		max = { 0, 3, 3 },
		radius = 120,
		phases = {},
		on = { "water" },
		bucket = 120,
		fade = 0,
		depth = 0.05,
		edge = 1.5,
		jump = { every = 20, chance = 0.35, seconds = 1, height = 2.5, length = 3 },
		startle = 2,
		passSpeed = 1,
		cooldown = 4,
		maxRain = math.huge,
		anims = { swim = "swim", jump = "flee" },
	},
	stray = {
		cost = 3,
		max = { 1, 2, 4 },
		radius = 100,
		phases = {},
		on = { "ground" },
		bucket = 120,
		tick = 0.5,
		speed = 9,
		wanderSpeed = 3,
		wanderRadius = 5,
		follow = { radius = 25, seconds = { 20, 45 }, trail = 3, giveUp = 22, lookEvery = 2, after = { 3, 15 } },
		sit = { 4, 12 },
		margin = 2,
		maxRain = math.huge,
		anims = { sit = "idle", wander = "walk", follow = "walk", home = "walk" },
	},
}
Rules.DEFAULTS = DEFAULTS

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end
Rules.copy = deepCopy

local function fill(dst: any, defaults: any)
	for k, v in defaults do
		if dst[k] == nil then
			dst[k] = deepCopy(v)
		elseif type(v) == "table" and type(dst[k]) == "table" and v[1] == nil and next(v) ~= nil then
			fill(dst[k], v) -- a keyed table (weights, drift, jump, follow): fill missing keys only
		end
	end
end

local function set(list: any): { [string]: boolean }
	local out = {}
	if type(list) == "table" then
		for _, v in list do
			out[tostring(v)] = true
		end
	end
	return out
end
Rules.set = set

function Rules.normalise(spec: any): any
	local s = deepCopy(spec)
	s.seed = s.seed or 0
	s.budgetKind = s.budgetKind or "critters"
	s.cell = s.cell or 64
	s.keep = s.keep or 10
	s.dayNight = s.dayNight or { mode = "phase" }
	s.kinds = if type(s.kinds) == "table" then s.kinds else {}
	s.biomes = if type(s.biomes) == "table" then s.biomes else {}
	s.spots = if type(s.spots) == "table" then s.spots else {}
	for _, k in s.kinds do
		if type(k) == "table" and DEFAULTS[k.behaviour] then
			fill(k, DEFAULTS[k.behaviour])
			k._phases = set(k.phases)
			k._roost = set(k.roostPhases)
			k._on = set(k.on or k.perchOn)
			k._roostOn = set(k.roostOn)
			k._seasons = k.seasons and set(k.seasons) or nil
			k._hide = set(k.hideWeathers)
		end
	end
	return s
end

-- Validation --------------------------------------------------------------------------------

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function range2(v: any): boolean
	return type(v) == "table" and isNum(v[1]) and isNum(v[2]) and v[1] <= v[2]
end

local function caps(v: any): boolean
	if isNum(v) then
		return v >= 0
	end
	if type(v) ~= "table" or #v ~= 3 then
		return false
	end
	for _, x in v do
		if not isNum(x) or x < 0 or x % 1 ~= 0 then
			return false
		end
	end
	return true
end

local function strList(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	for k, x in v do
		if type(k) ~= "number" or type(x) ~= "string" then
			return false
		end
	end
	return true
end

local PHASES = { dawn = true, day = true, dusk = true, night = true }

local function checkKind(name: string, k: any, add: (string) -> ())
	local p = `kinds.{name}`
	if type(k) ~= "table" then
		add(`{p} must be a table`)
		return
	end
	if not Rules.BEHAVIOURS[k.behaviour] then
		add(`{p}.behaviour must be flock, drift, swim or stray (got {tostring(k.behaviour)})`)
		return
	end
	if not isNum(k.cost) or k.cost <= 0 then
		add(`{p}.cost must be a number > 0`)
	end
	if not caps(k.max) then
		add(`{p}.max must be {"{q1, q2, q3}"} whole numbers >= 0`)
	end
	if not (isNum(k.radius) and k.radius > 0) and not (type(k.radius) == "table" and caps(k.radius)) then
		add(`{p}.radius must be a number > 0 or {"{q1, q2, q3}"}`)
	end
	for _, key in { "phases", "roostPhases" } do
		if k[key] ~= nil then
			if not strList(k[key]) then
				add(`{p}.{key} must be a list of phase names`)
			end
		end
	end
	if not isNum(k.bucket) or k.bucket <= 0 then
		add(`{p}.bucket must be seconds > 0`)
	end
	if k.chance ~= nil and not (isNum(k.chance) and k.chance >= 0 and k.chance <= 1) then
		add(`{p}.chance must be 0..1`)
	end
	if type(k.anims) ~= "table" then
		add(`{p}.anims must map states to clip names`)
	end
	if k.colors ~= nil and not strList(k.colors) then
		add(`{p}.colors must be a list of hex strings`)
	end
	if k.behaviour == "flock" then
		if not strList(k.perchOn) or #k.perchOn == 0 then
			add(`{p}.perchOn must list spot types`)
		end
		if not range2(k.flock) or k.flock[1] < 1 or k.flock[2] > 32 then
			add(`{p}.flock must be {"{lo, hi}"} with 1 <= lo <= hi <= 32`)
		end
		for _, key in { "tick", "speed", "maxAccel", "view", "minSep", "landDist", "approach", "leaveSeconds", "slow" } do
			if not isNum(k[key]) or k[key] <= 0 then
				add(`{p}.{key} must be a number > 0`)
			end
		end
		if isNum(k.tick) and isNum(k.bucket) and k.tick > k.bucket / 10 then
			add(`{p}.tick must be at most bucket / 10`)
		end
		if isNum(k.minSpeed) and isNum(k.speed) and (k.minSpeed < 0 or k.minSpeed > k.speed) then
			add(`{p}.minSpeed must be 0..speed`)
		end
		if not range2(k.arrive) or k.arrive[1] < 0 then
			add(`{p}.arrive must be {"{lo, hi}"} seconds >= 0`)
		end
		if not range2(k.perch) or k.perch[1] <= 0 or k.perch[2] >= 1 then
			add(`{p}.perch must be {"{lo, hi}"} fractions of the bucket inside (0, 1)`)
		elseif isNum(k.bucket) and isNum(k.leaveSeconds) and k.bucket * (1 - k.perch[2]) < k.leaveSeconds then
			add(`{p}: takeoff at {k.perch[2]} of a {k.bucket} s bucket leaves less than leaveSeconds ({k.leaveSeconds}) to fly out`)
		end
		if range2(k.arrive) and range2(k.perch) and isNum(k.bucket) and k.arrive[2] >= k.perch[1] * k.bucket then
			add(`{p}: arrive (up to {k.arrive[2]} s) must end before the earliest takeoff ({k.perch[1] * k.bucket} s)`)
		end
		if not isNum(k.scare) or k.scare < 0 or not isNum(k.scareSpeed) or k.scareSpeed < 0 then
			add(`{p}.scare and .scareSpeed must be numbers >= 0`)
		end
		if not range2(k.returnAfter) then
			add(`{p}.returnAfter must be {"{lo, hi}"} seconds`)
		end
		if type(k.weights) ~= "table" then
			add(`{p}.weights must be {"{separation, alignment, cohesion, goal}"}`)
		else
			for _, w in { "separation", "alignment", "cohesion", "goal" } do
				if not isNum(k.weights[w]) or k.weights[w] < 0 then
					add(`{p}.weights.{w} must be a number >= 0`)
				end
			end
		end
	elseif k.behaviour == "drift" then
		if not strList(k.on) or #k.on == 0 then
			add(`{p}.on must list spot types`)
		end
		local d = k.drift
		if type(d) ~= "table" or not isNum(d.amp) or not isNum(d.height) or not isNum(d.bob) or type(d.freq) ~= "table" or #d.freq ~= 3 then
			add(`{p}.drift must be {"{amp, height, bob, freq = {fx, fy, fz}}"}`)
		end
	elseif k.behaviour == "swim" then
		if not strList(k.on) or #k.on == 0 then
			add(`{p}.on must list spot types`)
		end
		local j = k.jump
		if type(j) ~= "table" or not isNum(j.every) or j.every <= 0 or not isNum(j.seconds) or j.seconds <= 0 or j.seconds >= j.every then
			add(`{p}.jump must be {"{every > seconds > 0, chance, height, length}"}`)
		elseif not isNum(j.chance) or j.chance < 0 or j.chance > 1 then
			add(`{p}.jump.chance must be 0..1`)
		end
	elseif k.behaviour == "stray" then
		if not strList(k.on) or #k.on == 0 then
			add(`{p}.on must list spot types`)
		end
		for _, key in { "tick", "speed", "wanderSpeed", "margin" } do
			if not isNum(k[key]) or k[key] <= 0 then
				add(`{p}.{key} must be a number > 0`)
			end
		end
		local f = k.follow
		if type(f) ~= "table" or not isNum(f.radius) or not range2(f.seconds) or not isNum(f.trail) or not isNum(f.giveUp) or not isNum(f.lookEvery) or not range2(f.after) then
			add(`{p}.follow must be {"{radius, seconds = {lo, hi}, trail, giveUp, lookEvery, after = {lo, hi}}"}`)
		end
		if not range2(k.sit) then
			add(`{p}.sit must be {"{lo, hi}"} seconds`)
		end
		if isNum(k.tick) and isNum(k.bucket) and k.tick > k.bucket / 20 then
			add(`{p}.tick must be at most bucket / 20`)
		end
	end
	for _, key in { "phases", "roostPhases" } do
		if strList(k[key]) then
			for _, ph in k[key] do
				if not PHASES[ph] then
					add(`{p}.{key}: unknown phase '{ph}' (dawn, day, dusk, night)`)
				end
			end
		end
	end
end

-- Minimum spacing between perch points a flock kind may land on (lands only on free perches,
-- and two birds perched side by side must not overlap).
local function checkPoints(spot: any, where: string, minSep: number, kindName: string, add: (string) -> ())
	local pts = spot.points
	if type(pts) ~= "table" then
		return
	end
	for i = 1, #pts do
		for j = i + 1, #pts do
			local a, b = pts[i], pts[j]
			local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d < minSep then
				add(`{where}: points {i} and {j} are {string.format("%.2f", d)} studs apart, under {kindName}.minSep {minSep}`)
				return
			end
		end
	end
end

function Rules.validate(spec: any): { string }
	local problems: { string } = {}
	local function add(msg: string)
		table.insert(problems, msg)
	end
	if type(spec) ~= "table" then
		return { "spec must be a table" }
	end
	if type(spec.id) ~= "string" or spec.id == "" then
		add("id must be a non-empty string")
	end
	if spec.seed ~= nil and not isNum(spec.seed) and type(spec.seed) ~= "string" then
		add("seed must be a number or a string")
	end
	if spec.budget ~= nil and not caps(spec.budget) then
		add("budget must be {q1, q2, q3} whole numbers >= 0")
	end
	local dn = spec.dayNight
	if dn ~= nil then
		if type(dn) ~= "table" or (dn.mode ~= "phase" and dn.mode ~= "curve") then
			add("dayNight.mode must be 'phase' or 'curve'")
		elseif dn.mode == "curve" and (not range2(dn.on) or not range2(dn.off)) then
			add("dayNight curve needs on = {from, to} and off = {from, to} hours")
		end
	end
	if spec.biomes ~= nil and type(spec.biomes) ~= "table" then
		add("biomes must be a table of biome -> spawn entries")
	end
	if spec.spots ~= nil and type(spec.spots) ~= "table" then
		add("spots must be a list")
	end
	local s = Rules.normalise(spec)
	if type(spec.kinds) ~= "table" or next(spec.kinds) == nil then
		add("kinds must name at least one kind")
	end
	local kindNames = {}
	for name in s.kinds do
		table.insert(kindNames, tostring(name))
	end
	table.sort(kindNames)
	for _, name in kindNames do
		checkKind(name, s.kinds[name], add)
	end
	local biomeNames = {}
	for name in s.biomes do
		table.insert(biomeNames, tostring(name))
	end
	table.sort(biomeNames)
	for _, b in biomeNames do
		local list = s.biomes[b]
		if type(list) ~= "table" then
			add(`biomes.{b} must be a list of spawn entries`)
			continue
		end
		for i, e in list do
			local p = `biomes.{b}[{i}]`
			if type(e) ~= "table" or type(e.kind) ~= "string" then
				add(`{p}.kind must name a kind`)
				continue
			end
			if s.kinds[e.kind] == nil then
				add(`{p}: unknown kind '{e.kind}'`)
			end
			if e.count ~= nil and not (isNum(e.count) and e.count >= 0) and not (range2(e.count) and e.count[1] >= 0) then
				add(`{p}.count must be a number >= 0 or {"{lo, hi}"}`)
			end
			if e.chance ~= nil and not (isNum(e.chance) and e.chance >= 0 and e.chance <= 1) then
				add(`{p}.chance must be 0..1`)
			end
			if e.seasons ~= nil and not strList(e.seasons) then
				add(`{p}.seasons must be a list of season names`)
			end
		end
	end
	local ids = {}
	for i, sp in s.spots do
		local p = `spots[{i}]`
		if type(sp) ~= "table" then
			add(`{p} must be a table`)
			continue
		end
		if type(sp.id) ~= "string" or sp.id == "" then
			add(`{p}.id must be a non-empty string`)
		elseif ids[sp.id] then
			add(`{p}: duplicate spot id '{sp.id}'`)
		else
			ids[sp.id] = true
			p = `spot '{sp.id}'`
		end
		if type(sp.type) ~= "string" then
			add(`{p}.type must be a string (roof, perch, flower, water, ground, lamp, roost, ...)`)
		end
		if not isNum(sp.x) or not isNum(sp.y) or not isNum(sp.z) then
			add(`{p}: x, y and z must be finite numbers`)
		end
		if sp.biome ~= nil and s.biomes[sp.biome] == nil then
			add(`{p}: unknown biome '{tostring(sp.biome)}'`)
		end
		if sp.radius ~= nil and not (isNum(sp.radius) and sp.radius > 0) then
			add(`{p}.radius must be > 0`)
		end
		if sp.points ~= nil then
			if type(sp.points) ~= "table" or #sp.points == 0 then
				add(`{p}.points must be a non-empty list of {"{x, y, z}"}`)
			else
				local okPts = true
				for j, pt in sp.points do
					if type(pt) ~= "table" or not isNum(pt.x) or not isNum(pt.y) or not isNum(pt.z) then
						add(`{p}.points[{j}] must be {"{x, y, z}"}`)
						okPts = false
					end
				end
				if okPts then
					for _, name in kindNames do
						local k = s.kinds[name]
						if type(k) == "table" and k.behaviour == "flock" and isNum(k.minSep) and (k._on[sp.type] or k._roostOn[sp.type]) then
							checkPoints(sp, p, k.minSep, name, add)
						end
					end
				end
			end
		end
		if sp.type == "water" and not (isNum(sp.radius) and sp.radius > 0) then
			add(`{p}: a water spot needs a radius`)
		end
	end
	return problems
end

-- Spot index --------------------------------------------------------------------------------
-- A uniform XZ grid of spots, and per spot the spawn entries of its biome whose kind lives on
-- the spot's type. Flock units get their perch candidates (points of perch-type spots within
-- `range` of the home spot, nearest first) and their lower-id neighbours for perch claims.

export type Unit = {
	id: string,
	kind: string,
	k: any,
	spot: any,
	entry: any,
	n: number,
	-- flock
	cands: { any }?,
	roostCands: { any }?,
	lower: { Unit }?,
	lowerRoost: { Unit }?,
	size: number?,
}

local function spotPoints(sp: any): { any }
	if type(sp.points) == "table" then
		local out = {}
		for j, pt in sp.points do
			table.insert(out, { x = pt.x, y = pt.y, z = pt.z, key = sp.id .. ":" .. j, spot = sp.id })
		end
		return out
	end
	return { { x = sp.x, y = sp.y, z = sp.z, key = sp.id .. ":1", spot = sp.id } }
end

function Rules.index(s: any): any
	local cell = s.cell
	local grid: { [string]: { any } } = {}
	local units: { Unit } = {}
	local bySpot: { [string]: { Unit } } = {}
	local byId: { [string]: Unit } = {}
	local function key(cx: number, cz: number): string
		return cx .. "," .. cz
	end
	local sorted = table.clone(s.spots)
	table.sort(sorted, function(a, b)
		return a.id < b.id
	end)
	local maxRadius = 0
	for _, k in s.kinds do
		local r = k.radius
		if type(r) == "table" then
			r = math.max(r[1], r[2], r[3])
		end
		maxRadius = math.max(maxRadius, r)
	end
	for _, sp in sorted do
		local ck = key(math.floor(sp.x / cell), math.floor(sp.z / cell))
		grid[ck] = grid[ck] or {}
		table.insert(grid[ck], sp)
		local list = {}
		local entries = s.biomes[sp.biome or ""] or {}
		for ei, e in entries do
			local k = s.kinds[e.kind]
			if k and k._on[sp.type] then
				local u: Unit = {
					id = `{sp.id}/{e.kind}` .. (if ei > 1 and entries[ei - 1].kind == e.kind then `/{ei}` else ""),
					kind = e.kind,
					k = k,
					spot = sp,
					entry = e,
					n = 0,
				}
				if byId[u.id] then
					u.id = `{sp.id}/{e.kind}/{ei}`
				end
				byId[u.id] = u
				table.insert(list, u)
				table.insert(units, u)
			end
		end
		bySpot[sp.id] = list
	end
	local idx = { grid = grid, cell = cell, units = units, bySpot = bySpot, byId = byId, maxRadius = maxRadius, spots = sorted }

	-- flock perch candidates and claim neighbours (lazy per unit; see Rules.flockInfo)
	function idx.query(x: number, z: number, r: number): { any }
		local out = {}
		local x0, x1 = math.floor((x - r) / cell), math.floor((x + r) / cell)
		local z0, z1 = math.floor((z - r) / cell), math.floor((z + r) / cell)
		local r2 = r * r
		for cx = x0, x1 do
			for cz = z0, z1 do
				local list = grid[key(cx, cz)]
				if list then
					for _, sp in list do
						local dx, dz = sp.x - x, sp.z - z
						if dx * dx + dz * dz <= r2 then
							table.insert(out, sp)
						end
					end
				end
			end
		end
		return out
	end

	local function candidates(u: Unit, types: { [string]: boolean }): { any }
		local k = u.k
		local out = {}
		for _, sp in idx.query(u.spot.x, u.spot.z, k.range) do
			if types[sp.type] then
				for _, pt in spotPoints(sp) do
					local dx, dy, dz = pt.x - u.spot.x, pt.y - u.spot.y, pt.z - u.spot.z
					pt.d = if sp.id == u.spot.id then -1 else dx * dx + dy * dy + dz * dz
					table.insert(out, pt)
				end
			end
		end
		table.sort(out, function(a, b)
			if a.d ~= b.d then
				return a.d < b.d
			end
			return a.key < b.key
		end)
		return out
	end

	local function neighbours(u: Unit, field: string): { Unit }
		local mine = {}
		for _, pt in (u :: any)[field] do
			mine[pt.key] = true
		end
		local out = {}
		for _, sp in idx.query(u.spot.x, u.spot.z, 2 * u.k.range + 1) do
			for _, v in bySpot[sp.id] or {} do
				if v.kind == u.kind and v.id < u.id then
					idx._ensureCands(v)
					for _, pt in (v :: any)[field] do
						if mine[pt.key] then
							table.insert(out, v)
							break
						end
					end
				end
			end
		end
		table.sort(out, function(a, b)
			return a.id < b.id
		end)
		return out
	end

	function idx._ensureCands(u: Unit)
		if not u.cands then
			u.cands = candidates(u, u.k._on)
			u.roostCands = candidates(u, u.k._roostOn)
		end
	end
	idx._neighbours = neighbours
	return idx
end

-- Perch candidates and the lower-id flocks of the same kind sharing any of them (the only
-- flocks whose claims this flock must respect). No recursion: neighbours need candidates only.
function Rules.flockInfo(idx: any, u: Unit)
	if u.lower then
		return
	end
	idx._ensureCands(u)
	u.lower = idx._neighbours(u, "cands")
	u.lowerRoost = idx._neighbours(u, "roostCands")
end

return Rules
