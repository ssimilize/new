--!strict
-- SkyWeather: one wind for trees, flags, smoke and clouds; weather fronts that cross the map;
-- wet ground, puddles and snow; lightning with distance-delayed thunder.
--
--   local SkyWeather = require("../SkyWeather/SkyWeather")
--   local sky = SkyWeather.new(adapter, almanac, rules, bounds?)   -- errors listing every problem
--   sky:snapshot(t, pos, sun?)       -- the full local state (packages/SkyWeather/README.md)
--   sky:sunOcclusion(t, pos, sun?)   -- cloud across the sun here, 0..1 (0 at night)
--   sky:sunDirection(t)              -- the sun path from the Almanac hour (rules.clouds.sun)
--   sky:wind(t, pos)                 -- the wind alone (cheap; per frame)
--   sky:precipitationPlan(t, camera) -- emitters around the camera within adapter.budget("weatherEmitters")
--   sky:strikes(t0, t1)              -- lightning strikes in [t0, t1)
--   sky:front(t)                     -- the front whose line is crossing at t
--   SkyWeather.kindRate(rules, kind, intensity?)  -- a kind's settled precipitation (pure)
--   SkyWeather.qualityScale(rules, level)         -- the emitter multiplier per quality level
--
-- Stateless: everything is a function of (rules.seed, t, position) and the Almanac's rolls
-- (read through almanac:at, which is pure), so every client computes the same sky. The only
-- memory is a cache of per-front rolls (a pure function of the front index).

local Contract = require("../Contract/Contract")
local Noise = require("./Noise")
local Rules = require("./Rules")

local SkyWeather = {}
SkyWeather.validate = Rules.validate
SkyWeather.check = Rules.check
SkyWeather.SPEED_OF_SOUND = 343 -- metres per second; studs = this * rules.studsPerMeter

local Methods = {}
Methods.__index = Methods

local TWO_PI = 2 * math.pi
local CACHE_LIMIT = 512
local SLOT_LIMIT = 200000 -- lightning slots one strikes() query may walk (a guard)
-- the sun ray meets the cloud layer at most height / sin(25 deg) studs away: below that the
-- sample point stops sliding with the sun, so a low sun does not race clouds across itself
local MIN_RAY_SIN = math.sin(math.rad(25))

local function num(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpRange(v: any, t: number): number
	if type(v) == "number" then
		return v
	end
	return v[1] + (v[2] - v[1]) * t
end

local function needTime(t: any, where: string)
	if not num(t) then
		error(`SkyWeather.{where}: time must be a finite number, got {tostring(t)}`, 3)
	end
end

local function needPos(p: any, where: string): (number, number)
	local x, z = Rules.pos(p)
	if x == nil or z == nil then
		error(`SkyWeather.{where}: position needs finite x and z (a table or a Vector3), got {typeof(p)}`, 3)
	end
	return x :: number, z :: number
end

-- the clouds section with its optional fields filled from Rules.CLOUD_DEFAULTS / SUN_DEFAULTS
local function resolveClouds(C: any): any
	local out = {}
	for k, v in Rules.CLOUD_DEFAULTS do
		out[k] = if C[k] ~= nil then C[k] else v
	end
	local sun = {}
	local given = C.sun or {}
	for k, v in Rules.SUN_DEFAULTS do
		sun[k] = if given[k] ~= nil then given[k] else v
	end
	out.sun = sun
	return out
end

-- new --------------------------------------------------------------------------------------

function SkyWeather.new(adapter: Contract.Adapter, almanac: any, rules: any, bounds: any?): any
	local problems = Contract.check(adapter)
	if #problems > 0 then
		error("SkyWeather.new: bad adapter: " .. table.concat(problems, "; "), 2)
	end
	if type(almanac) ~= "table" or type(almanac.at) ~= "function" or type(almanac.rules) ~= "function" then
		error("SkyWeather.new: almanac must be an Almanac (with :at and :rules)", 2)
	end
	local arules = almanac:rules()
	local rp = Rules.check(rules, arules)
	if #rp > 0 then
		error("SkyWeather.new: bad rules: " .. table.concat(rp, "; "), 2)
	end
	local b = bounds or rules.defaultBounds
	if b == nil then
		error("SkyWeather.new: no bounds (pass bounds or set rules.defaultBounds)", 2)
	end
	local bp = Rules.bounds(b)
	if #bp > 0 then
		error("SkyWeather.new: bad bounds: " .. table.concat(bp, "; "), 2)
	end
	local x0, z0 = Rules.pos((b :: any).min)
	local x1, z1 = Rules.pos((b :: any).max)
	local seed = Noise.seed(rules.seed or 0)
	local W = arules.weather
	local self: any = setmetatable({
		_adapter = adapter,
		_almanac = almanac,
		_arules = arules,
		_rules = rules,
		_bounds = { x0 = x0, z0 = z0, x1 = x1, z1 = z1 },
		_seed = seed,
		_gustSeed = Noise.hash(seed, Noise.seed("gust")),
		_dirSeed = Noise.hash(seed, Noise.seed("dir")),
		_strikeSeed = Noise.hash(seed, Noise.seed("strike")),
		_cloudSeed = Noise.hash(seed, Noise.seed("cloud")),
		_cloud = resolveClouds(rules.clouds),
		_frontLen = Rules.frontSeconds(arules),
		_active = if type(W) == "table" then W.activeSeconds else nil,
		_clearKind = if type(W) == "table" then (W.clearKind or "clear") else "clear",
		_fronts = {},
		_frontCount = 0,
	}, Methods)
	if rules.kinds[self._clearKind] == nil then
		self._clearKind = "clear"
	end
	local pr = math.rad(rules.wind.direction)
	self._pdx, self._pdz = math.cos(pr), math.sin(pr)
	self._still = self:_profile(self._clearKind, 0, self._pdx, self._pdz, nil)
	if self._frontLen ~= nil then
		local f = almanac:at(0).weather.front
		if f == nil or math.abs((f.endsAt - f.startsAt) - self._frontLen) > 1e-6 then
			error("SkyWeather.new: the Almanac's front length disagrees with its rules", 2)
		end
		self._anchorIndex = f.index
		self._anchorStart = f.startsAt
	end
	return self
end

-- profiles -----------------------------------------------------------------------------------

-- _profile(kind, intensity, dx, dz, season) -> the steady state a weather kind implies.
function Methods._profile(self: any, kind: string, intensity: number, dx: number, dz: number, season: string?): any
	local rules = self._rules
	local k = rules.kinds[kind] or rules.kinds[self._clearKind]
	local precip = k.precipitation or "none"
	local rate = if precip ~= "none" then clamp01(intensity * (k.rate or 1)) else 0
	if rate <= 0 then
		precip, rate = "none", 0
	end
	return {
		kind = kind,
		intensity = intensity,
		wind = lerpRange(k.wind, intensity),
		gust = lerpRange(k.gust, intensity),
		cloud = lerpRange(k.cloudCover, intensity),
		fog = lerpRange(k.fog or 0, intensity),
		precip = precip,
		rate = rate,
		dry = k.dry or 1,
		strikes = if k.storm then k.storm.strikesPerMinute else 0,
		dx = dx,
		dz = dz,
		season = season,
	}
end

-- fronts -------------------------------------------------------------------------------------

function Methods._frontIndexAt(self: any, t: number): number
	return self._anchorIndex + math.floor((t - self._anchorStart) / self._frontLen)
end

function Methods._front(self: any, i: number): any
	local c = self._fronts[i]
	if c ~= nil then
		return c
	end
	local L = self._frontLen
	local fs = self._anchorStart + (i - self._anchorIndex) * L
	local snap = self._almanac:at(fs + math.min(0.5, L * 0.001))
	local w = snap.weather
	if w.front == nil or w.front.index ~= i then
		error(`SkyWeather: the Almanac put time {fs} in front {w.front and w.front.index} (expected {i})`, 2)
	end
	local rules = self._rules
	local angle = rules.wind.direction + rules.wind.drift * (2 * Noise.u(self._dirSeed, i) - 1)
	local r = math.rad(angle)
	local dx, dz = math.cos(r), math.sin(r)
	local B = self._bounds
	local c1, c2 = dx * B.x0 + dz * B.z0, dx * B.x1 + dz * B.z0
	local c3, c4 = dx * B.x0 + dz * B.z1, dx * B.x1 + dz * B.z1
	local season = snap.season and snap.season.name or nil
	c = {
		index = i,
		startsAt = fs,
		kind = w.kind,
		intensity = w.intensity,
		angle = angle % 360,
		dx = dx,
		dz = dz,
		pmin = math.min(c1, c2, c3, c4),
		pmax = math.max(c1, c2, c3, c4),
		season = season,
		profile = self:_profile(w.kind, w.intensity, dx, dz, season),
		clear = self:_profile(self._clearKind, 0, dx, dz, season),
	}
	if self._frontCount >= CACHE_LIMIT then
		self._fronts = {}
		self._frontCount = 0
	end
	self._fronts[i] = c
	self._frontCount += 1
	return c
end

-- arrival(F, x, z) -> when front F's line reaches (x, z).
function Methods._arrival(self: any, F: any, x: number, z: number): number
	local span = F.pmax - F.pmin
	local p = if span > 0 then clamp01((F.dx * x + F.dz * z - F.pmin) / span) else 0
	return F.startsAt + self._rules.fronts.crossSeconds * p
end

function Methods._override(self: any): any
	local a = self._almanac
	if type(a.override) ~= "function" then
		return nil
	end
	local o = a:override()
	return o
end

-- _local(t, x, z, ov) -> { cur, prev, start, w, front, arrival, overridden }: the local weather
-- segment and the one it is blending in from.
function Methods._local(self: any, t: number, x: number, z: number, ov: any): any
	if ov ~= nil and ov.weather ~= nil then
		local dx, dz = self._pdx, self._pdz
		local fi = nil
		if self._frontLen ~= nil then
			fi = self:_frontIndexAt(t)
			local F = self:_front(fi)
			dx, dz = F.dx, F.dz
		end
		local season = ov.season and ov.season.name or nil
		local p = self:_profile(ov.weather.kind, ov.weather.intensity, dx, dz, season)
		return { cur = p, prev = p, start = -math.huge, w = 1, front = fi, arrival = -math.huge, overridden = true }
	end
	if self._frontLen == nil then
		local s = self._still
		return { cur = s, prev = s, start = -math.huge, w = 1, front = nil, arrival = -math.huge, overridden = false }
	end
	local i = self:_frontIndexAt(t)
	local F = self:_front(i)
	local a = self:_arrival(F, x, z)
	if t < a then
		i -= 1
		F = self:_front(i)
		a = self:_arrival(F, x, z)
	end
	local active = self._active
	local cur, prev, start
	if active ~= nil and t >= a + active then
		cur, prev, start = F.clear, F.profile, a + active
	else
		local P = self:_front(i - 1)
		cur, start = F.profile, a
		prev = if active ~= nil then P.clear else P.profile
	end
	local B = self._rules.fronts.blendSeconds
	local w = if B > 0 then smooth((t - start) / B) else 1
	return { cur = cur, prev = prev, start = start, w = w, front = i, arrival = a, overridden = false }
end

-- _mix(st) -> the blended steady state (wind vector, gust amplitude, cloud, precipitation).
local function mix(st: any): any
	local p, c, w = st.prev, st.cur, st.w
	local vx = p.wind * p.dx * (1 - w) + c.wind * c.dx * w
	local vz = p.wind * p.dz * (1 - w) + c.wind * c.dz * w
	local base = math.sqrt(vx * vx + vz * vz)
	local dx, dz = c.dx, c.dz
	if base > 1e-9 then
		dx, dz = vx / base, vz / base
	end
	local kind, rate
	if p.precip == c.precip then
		kind, rate = c.precip, lerp(p.rate, c.rate, w)
	else
		local rp, rc = p.rate * (1 - w), c.rate * w
		if rc >= rp then
			kind, rate = c.precip, rc
		else
			kind, rate = p.precip, rp
		end
	end
	if rate <= 0 then
		kind, rate = "none", 0
	end
	return {
		base = base,
		dx = dx,
		dz = dz,
		gustAmp = lerp(p.gust, c.gust, w),
		cloud = lerp(p.cloud, c.cloud, w),
		fog = lerp(p.fog, c.fog, w),
		precip = kind,
		rate = rate,
	}
end

-- wind -----------------------------------------------------------------------------------------

-- _gust(t, x, z) -> 0..1: value noise over (x, z, t) drifting downwind along the prevailing heading.
function Methods._gust(self: any, t: number, x: number, z: number): number
	local W = self._rules.wind
	local travel = W.gustTravel * t
	local gx = (x - self._pdx * travel) / W.gustScale
	local gz = (z - self._pdz * travel) / W.gustScale
	local n = Noise.value3(self._gustSeed, gx, gz, t / W.gustSeconds)
	return smooth((n - 0.3) / 0.6)
end

local function windOf(self: any, t: number, x: number, z: number, m: any): any
	local gust = self:_gust(t, x, z)
	local angle = math.deg(math.atan2(m.dz, m.dx)) % 360
	return {
		dir = { x = m.dx, z = m.dz },
		angle = angle,
		speed = m.base * (1 + m.gustAmp * gust),
		base = m.base,
		gust = gust,
	}
end

function Methods.wind(self: any, t: number, pos: any): any
	needTime(t, "wind")
	local x, z = needPos(pos, "wind")
	local st = self:_local(t, x, z, self:_override())
	return windOf(self, t, x, z, mix(st))
end

-- clouds ---------------------------------------------------------------------------------------

-- _cloudDrift(t) -> studs the cloud layer has moved along the prevailing heading (unwrapped).
function Methods._cloudDrift(self: any, t: number): number
	local C = self._rules.clouds
	local T = C.period
	return C.speed * t + C.speed * C.variation * T / TWO_PI * math.sin(TWO_PI * t / T)
end

function Methods._cloudOffset(self: any, t: number): any
	local C = self._rules.clouds
	local d = self:_cloudDrift(t)
	return { x = (self._pdx * d) % C.wrap, z = (self._pdz * d) % C.wrap }
end

-- _cloudDensity(t, qx, qz) -> 0..1: the cloud layer's value noise at world point (qx, qz):
-- cells of clouds.cellSize studs carried downwind by the same drift as the shadow offset, and
-- slowly reshaping over clouds.evolveSeconds.
function Methods._cloudDensity(self: any, t: number, qx: number, qz: number): number
	local C = self._cloud
	local d = self:_cloudDrift(t)
	local gx = (qx - self._pdx * d) / C.cellSize
	local gz = (qz - self._pdz * d) / C.cellSize
	return Noise.value3(self._cloudSeed, gx, gz, t / C.evolveSeconds)
end

-- _hour(t, ov) -> the Almanac hour (0 <= h < 24), the override's hour when one is set.
function Methods._hour(self: any, t: number, ov: any): number
	if ov ~= nil and num(ov.hour) then
		return ov.hour
	end
	local ar = self._arules
	local L = ar.dayLengthSeconds
	local rel = t - (ar.epoch or 0)
	local sod = rel - math.floor(rel / L) * L
	return sod * 24 / L
end

-- _sunDir(t, ov) -> x, y, z: the unit direction TOWARD the sun from the Almanac hour. The sun
-- rises at clouds.sun.rise toward heading, climbs to peak degrees at midday (toward heading + 90)
-- and sets at clouds.sun.set toward heading + 180; between set and rise it runs below the
-- horizon (y < 0) back to the rise point.
function Methods._sunDir(self: any, t: number, ov: any): (number, number, number)
	local S = self._cloud.sun
	local h = self:_hour(t, ov)
	local dayLen = (S.set - S.rise) % 24
	local since = (h - S.rise) % 24
	local phi
	if since <= dayLen then
		phi = math.pi * since / dayLen
	else
		phi = math.pi + math.pi * (since - dayLen) / (24 - dayLen)
	end
	local hd, pk = math.rad(S.heading), math.rad(S.peak)
	local rx, rz = math.cos(hd), math.sin(hd)
	local px, pz = -rz, rx
	local c, s = math.cos(phi), math.sin(phi)
	return c * rx + s * math.cos(pk) * px, s * math.sin(pk), c * rz + s * math.cos(pk) * pz
end

-- the sun argument: a direction toward the sun, {x, y, z} (or X/Y/Z) or a Vector3; normalised.
local function needSun(v: any, where: string): (number, number, number)
	local x, y, z
	if typeof(v) == "Vector3" then
		x, y, z = (v :: any).X, (v :: any).Y, (v :: any).Z
	elseif type(v) == "table" then
		x, y, z = v.x or v.X, v.y or v.Y, v.z or v.Z
	end
	if not (num(x) and num(y) and num(z)) then
		error("SkyWeather." .. where .. ": sun must be a direction toward the sun ({x, y, z} or a Vector3), got " .. typeof(v), 3)
	end
	local len = math.sqrt(x * x + y * y + z * z)
	if len < 1e-9 then
		error(`SkyWeather.{where}: sun direction has zero length`, 3)
	end
	return x / len, y / len, z / len
end

-- uniform(n) -> 0..1: value noise bunches around 0.5 (sd 0.185, measured over 200k samples);
-- a logistic of the same spread, rescaled to hit 0 and 1 at the ends, spreads it near-uniformly
-- so a threshold at 1 - cover covers about cover of the sky (the mean occlusion tracks cover).
local LOGISTIC_K = math.pi / (math.sqrt(3) * 0.185)
local U0 = 1 / (1 + math.exp(LOGISTIC_K * 0.5))
local U1 = 1 / (1 + math.exp(-LOGISTIC_K * 0.5))
local function uniform(n: number): number
	return (1 / (1 + math.exp(-LOGISTIC_K * (n - 0.5))) - U0) / (U1 - U0)
end

-- _occlusion(t, x, z, cover, sx, sy, sz) -> 0..1: the cloud layer (clouds.height studs up) where
-- the ray from (x, z) toward the sun crosses it, spread to near-uniform and thresholded so the
-- sky there is covered with probability ~cover (clouds.edge soft edge): cover 0 -> 0
-- everywhere, cover 1 -> 1 everywhere; in between the mean is about cover (Sky.spec). The
-- ray's reach is capped at the 25 degree elevation (MIN_RAY_SIN). Fades in over the first
-- clouds.sun.fade degrees above the horizon; 0 with the sun at or below it.
function Methods._occlusion(self: any, t: number, x: number, z: number, cover: number, sx: number, sy: number, sz: number): number
	if sy <= 0 or cover <= 0 then
		return 0
	end
	local C = self._cloud
	local elev = math.deg(math.asin(math.min(sy, 1)))
	local fade = smooth(elev / C.sun.fade)
	if fade <= 0 then
		return 0
	end
	local k = C.height / math.max(sy, MIN_RAY_SIN)
	local n = uniform(self:_cloudDensity(t, x + sx * k, z + sz * k))
	local e = C.edge
	local thr = lerp(1 + e, -e, clamp01(cover))
	return clamp01(smooth((n - thr) / (2 * e) + 0.5) * fade)
end

function Methods._sunFor(self: any, t: number, sun: any, ov: any, where: string): (number, number, number)
	if sun ~= nil then
		return needSun(sun, where)
	end
	return self:_sunDir(t, ov)
end

-- sunDirection(t) -> {x, y, z, elevation, hour}: the rules' sun path at the Almanac hour (the
-- override's hour when one is set). y < 0 means night.
function Methods.sunDirection(self: any, t: number): any
	needTime(t, "sunDirection")
	local ov = self:_override()
	local x, y, z = self:_sunDir(t, ov)
	return { x = x, y = y, z = z, elevation = math.deg(math.asin(math.clamp(y, -1, 1))), hour = self:_hour(t, ov) }
end

-- sunOcclusion(t, pos, sun?) -> 0..1: the snapshot's sunOcclusion alone.
function Methods.sunOcclusion(self: any, t: number, pos: any, sun: any?): number
	needTime(t, "sunOcclusion")
	local x, z = needPos(pos, "sunOcclusion")
	local ov = self:_override()
	local sx, sy, sz = self:_sunFor(t, sun, ov, "sunOcclusion")
	local m = mix(self:_local(t, x, z, ov))
	return self:_occlusion(t, x, z, m.cloud, sx, sy, sz)
end

-- surface ----------------------------------------------------------------------------------------

function Methods._sun(self: any, t: number): number
	local ar = self._arules
	local L = ar.dayLengthSeconds
	local rel = t - (ar.epoch or 0)
	local sod = rel - math.floor(rel / L) * L
	local hour = sod * 24 / L
	local list = ar.phases
	local phase = list[#list].id
	for _, ph in list do
		if hour >= ph.from then
			phase = ph.id
		end
	end
	return self._rules.surface.sun[phase] or 0
end

-- _segments(t0, t1, x, z, ov) -> { {start, prof} } in order; the first starts at or before t0.
function Methods._segments(self: any, t0: number, t1: number, x: number, z: number, ov: any): { any }
	if (ov ~= nil and ov.weather ~= nil) or self._frontLen == nil then
		return { { start = -math.huge, prof = self:_local(t1, x, z, ov).cur } }
	end
	local half = self._rules.fronts.blendSeconds / 2
	local active = self._active
	local out = {}
	for i = self:_frontIndexAt(t0) - 1, self:_frontIndexAt(t1) do
		local F = self:_front(i)
		local a = self:_arrival(F, x, z) + half
		if a <= t1 then
			table.insert(out, { start = a, prof = F.profile })
		end
		if active ~= nil and a + active <= t1 then
			table.insert(out, { start = a + active, prof = F.clear })
		end
	end
	return out
end

-- _surface(t, x, z, ov) -> wetness, snow: integrated exactly over the lookback from dry and bare.
function Methods._surface(self: any, t: number, x: number, z: number, ov: any): (number, number)
	local rules = self._rules
	local S = rules.surface
	local P = rules.precipitation
	local t0 = t - S.lookbackSeconds
	local step = S.step
	local segs = self:_segments(t0, t, x, z, ov)
	local seasonOverride = ov and ov.season and ov.season.name or nil
	local wet, snow = 0, 0
	for si, seg in segs do
		local a = math.max(seg.start, t0)
		local nextSeg = segs[si + 1]
		local e = if nextSeg then math.min(nextSeg.start, t) else t
		if e <= a then
			continue
		end
		local p = seg.prof
		local pd = P[p.precip]
		local rain = if pd and pd.wets then p.rate else 0
		local fall = if pd and pd.snows then p.rate else 0
		local sm = S.seasons and S.seasons[seasonOverride or p.season or ""] or nil
		local seasonDry = sm and sm.dry or 1
		local seasonMelt = sm and sm.melt or 1
		while a < e do
			local b = math.min(e, (math.floor(a / step) + 1) * step)
			local dt = b - a
			local sun = self:_sun((a + b) / 2)
			local melt = (S.melt + S.meltSun * sun + S.meltRain * rain) * seasonMelt
			local kw = S.wetPerSecond * rain + (if snow > 0 then S.meltWet * melt else 0)
			local kd = (S.dry + S.drySun * sun + S.dryWind * p.wind) * seasonDry * p.dry
			local k = kw + kd
			if k > 0 then
				local inf = kw / k
				wet = inf + (wet - inf) * math.exp(-k * dt)
			end
			snow = clamp01(snow + (S.snowPerSecond * fall - melt) * dt)
			a = b
		end
	end
	return clamp01(wet), snow
end

-- lightning --------------------------------------------------------------------------------------

local function flashCurve(rules: any, age: number): number
	for _, f in rules.lightning.flash do
		if age >= f[1] and age < f[2] then
			return f[3]
		end
	end
	return 0
end

-- strikes(t0, t1) -> { {id, t, x, z, strength, front} } sorted by time, for [t0, t1).
function Methods.strikes(self: any, t0: number, t1: number): { any }
	needTime(t0, "strikes")
	needTime(t1, "strikes")
	local out = {}
	if self._frontLen == nil or t1 <= t0 then
		return out
	end
	local rules = self._rules
	local L = self._frontLen
	local slot = rules.lightning.slotSeconds
	local cross = rules.fronts.crossSeconds
	local ov = self:_override()
	local ovOn = ov ~= nil and ov.weather ~= nil
	local B = self._bounds
	local iA, iB = self:_frontIndexAt(t0 - L - cross), self:_frontIndexAt(t1)
	local slots = math.ceil((L + cross) / slot)
	if (iB - iA + 1) * slots > SLOT_LIMIT then
		error(`SkyWeather.strikes: {(iB - iA + 1) * slots} slots in one query (limit {SLOT_LIMIT})`, 2)
	end
	for i = iA, iB do
		local F = self:_front(i)
		local prof = if ovOn then self:_local(F.startsAt, 0, 0, ov).cur else F.profile
		if prof.strikes <= 0 or prof.intensity <= 0 then
			continue
		end
		local chance = prof.strikes * slot / 60 * prof.intensity
		-- under an override the front holds the whole map for exactly L seconds; otherwise its
		-- storm can still be crossing the downwind edge until L + cross
		local span = if ovOn then L else L + cross
		local k0 = math.max(0, math.floor((t0 - F.startsAt) / slot))
		local k1 = math.min(math.ceil(span / slot) - 1, math.floor((t1 - F.startsAt) / slot))
		for k = k0, k1 do
			local rng = Contract.Rng.new(Noise.hash(self._strikeSeed, i, k))
			local r1, r2, r3, r4, r5 = rng:next(), rng:next(), rng:next(), rng:next(), rng:next()
			local ts = F.startsAt + (k + r2) * slot
			if r1 >= chance or ts < t0 or ts >= t1 or ts >= F.startsAt + span then
				continue
			end
			local x = B.x0 + r3 * (B.x1 - B.x0)
			local z = B.z0 + r4 * (B.z1 - B.z0)
			if not ovOn then
				local st = self:_local(ts, x, z, nil)
				if st.front ~= i or st.cur ~= F.profile then
					continue -- the storm has not reached this point yet (or has passed)
				end
			end
			table.insert(out, { id = `{i}:{k}`, t = ts, x = x, z = z, strength = 0.5 + 0.5 * r5, front = i })
		end
	end
	table.sort(out, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.id < b.id
	end)
	return out
end

function Methods._lightningAt(self: any, t: number, x: number, z: number): any
	local rules = self._rules
	local LR = rules.lightning
	local sos = SkyWeather.SPEED_OF_SOUND * rules.studsPerMeter
	local reach = LR.hearRadius / sos + LR.thunderSeconds
	local out = {}
	local flash = 0
	for _, s in self:strikes(t - reach, t + 1e-6) do
		if s.t > t then
			continue
		end
		local d = math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
		if d > LR.hearRadius then
			continue
		end
		local thunderAt = s.t + d / sos
		if t >= thunderAt + LR.thunderSeconds then
			continue
		end
		local age = t - s.t
		local f = s.strength * flashCurve(rules, age) / (1 + (d / LR.flashRadius) ^ 2)
		flash = math.max(flash, f)
		table.insert(out, {
			id = s.id,
			t = s.t,
			x = s.x,
			z = s.z,
			strength = s.strength,
			distance = d,
			thunderAt = thunderAt,
			age = age,
			flash = f,
		})
	end
	return { flash = flash, strikes = out }
end

-- snapshot ----------------------------------------------------------------------------------------

function Methods.snapshot(self: any, t: number, pos: any, sun: any?): any
	needTime(t, "snapshot")
	local x, z = needPos(pos, "snapshot")
	local ov = self:_override()
	local sx, sy, sz = self:_sunFor(t, sun, ov, "snapshot")
	local st = self:_local(t, x, z, ov)
	local m = mix(st)
	local wet, snow = self:_surface(t, x, z, ov)
	local from = self._rules.surface.puddleFrom
	return {
		t = t,
		pos = { x = x, z = z },
		weather = {
			kind = st.cur.kind,
			intensity = st.cur.intensity,
			front = st.front,
			arrivedAt = st.start,
			blend = st.w,
			previous = st.prev.kind,
		},
		wind = windOf(self, t, x, z, m),
		precipitation = { kind = m.precip, rate = m.rate },
		wetness = wet,
		puddles = clamp01((wet - from) / (1 - from)),
		snow = snow,
		cloudCover = m.cloud,
		cloudShadowOffset = self:_cloudOffset(t),
		fog = clamp01(m.fog),
		sunOcclusion = self:_occlusion(t, x, z, m.cloud, sx, sy, sz),
		lightning = self:_lightningAt(t, x, z),
		overridden = st.overridden,
	}
end

-- front(t) -> the front whose line is crossing (or last crossed) at t.
function Methods.front(self: any, t: number): any
	needTime(t, "front")
	if self._frontLen == nil then
		return nil
	end
	local i = self:_frontIndexAt(t)
	local F = self:_front(i)
	local cross = self._rules.fronts.crossSeconds
	return {
		index = i,
		startsAt = F.startsAt,
		endsAt = F.startsAt + self._frontLen,
		crossedAt = F.startsAt + cross,
		progress = if cross > 0 then clamp01((t - F.startsAt) / cross) else 1,
		kind = F.kind,
		intensity = F.intensity,
		angle = F.angle,
		dir = { x = F.dx, z = F.dz },
		season = F.season,
		previous = self:_front(i - 1).kind,
	}
end

-- precipitation plan --------------------------------------------------------------------------------

local function cameraFocus(camera: any): (number, number, number)
	local c = camera
	if type(camera) == "table" and (camera.focus ~= nil or camera.position ~= nil) then
		c = camera.focus or camera.position
	end
	local x, z = needPos(c, "precipitationPlan")
	local y = (type(c) == "table" or typeof(c) == "Vector3") and ((c :: any).y or (c :: any).Y) or 0
	return x, (if num(y) then y else 0), z
end

-- precipitationPlan(t, camera) -> { emitters, cap, budget, candidates, dropped, particles, quality }
function Methods.precipitationPlan(self: any, t: number, camera: any): any
	needTime(t, "precipitationPlan")
	local cx, cy, cz = cameraFocus(camera)
	local rules = self._rules
	local E = rules.emitters
	local P = rules.precipitation
	local adapter = self._adapter
	local budget = adapter.budget("weatherEmitters")
	local cap = math.max(0, math.floor(budget or E.defaultBudget))
	local q = math.clamp(math.floor(adapter.quality()), 1, 3)
	local scale = E.qualityScale[q]
	local S, R = E.spacing, E.radius
	local n = math.ceil(R / S)
	local snap = E.snap ~= false
	local bx = if snap then math.floor(cx / S + 0.5) * S else cx
	local bz = if snap then math.floor(cz / S + 0.5) * S else cz
	local ov = self:_override()
	local cands = {}
	for i = -n, n do
		for j = -n, n do
			local gx, gz = bx + i * S, bz + j * S
			local d = math.sqrt((gx - cx) ^ 2 + (gz - cz) ^ 2)
			if d > R + 1e-9 and not (i == 0 and j == 0) then
				continue
			end
			local m = mix(self:_local(t, gx, gz, ov))
			if m.precip == "none" or m.rate < E.minRate then
				continue
			end
			local pd = P[m.precip]
			local w = windOf(self, t, gx, gz, m)
			-- upwind = false: the emitter stays over its cell (a game whose particles do not take
			-- the wind yet); default: shifted upwind by the fall time so particles land in the cell
			local fallTime = if E.upwind == false then 0 else math.abs(E.height) / pd.fallSpeed
			local wx, wz = w.dir.x * w.speed, w.dir.z * w.speed
			table.insert(cands, {
				kind = m.precip,
				x = gx - wx * fallTime,
				y = cy + E.height,
				z = gz - wz * fallTime,
				cell = { x = gx, z = gz },
				size = S,
				localRate = m.rate,
				rate = m.rate * pd.particlesAtFull * scale,
				light = pd.lightBelow ~= nil and m.rate < pd.lightBelow,
				wind = { x = wx, z = wz },
				distance = d,
			})
		end
	end
	table.sort(cands, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		if a.cell.x ~= b.cell.x then
			return a.cell.x < b.cell.x
		end
		return a.cell.z < b.cell.z
	end)
	local emitters, particles = {}, 0
	for k = 1, math.min(cap, #cands) do
		table.insert(emitters, cands[k])
		particles += cands[k].rate
	end
	return {
		emitters = emitters,
		cap = cap,
		budget = budget,
		candidates = #cands,
		dropped = #cands - #emitters,
		particles = particles,
		quality = q,
		qualityScale = scale,
	}
end

-- kindRate(rules, kind, intensity?) -> (precip, particles per second at full quality): a kind's
-- settled precipitation, what precipitationPlan gives one emitter once a front has blended in
-- (quality 3). Pure: a game that keeps its own weather roll and blend (Monster Ranch) reads its
-- steady emitter rates here. An unknown kind is the clear kind "clear"; intensity defaults to 1.
function SkyWeather.kindRate(rules: any, kind: string, intensity: number?): (string, number)
	local k = rules.kinds[kind] or rules.kinds.clear
	local precip = if k then k.precipitation or "none" else "none"
	local rate = if precip ~= "none" then clamp01((intensity or 1) * (k.rate or 1)) else 0
	if rate <= 0 then
		return "none", 0
	end
	return precip, rate * rules.precipitation[precip].particlesAtFull
end

-- qualityScale(rules, level) -> the emitter multiplier precipitationPlan applies at quality
-- level 1 (low), 2 or 3 (high).
function SkyWeather.qualityScale(rules: any, level: number): number
	return rules.emitters.qualityScale[math.clamp(math.floor(level), 1, 3)]
end

function Methods.rules(self: any): any
	return self._rules
end

function Methods.bounds(self: any): any
	local B = self._bounds
	return { min = { x = B.x0, z = B.z0 }, max = { x = B.x1, z = B.z1 } }
end

return SkyWeather
