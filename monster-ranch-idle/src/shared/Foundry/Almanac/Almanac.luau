--!strict
-- Almanac: one world clock and calendar per game (hours, phases, seasons, weather fronts,
-- festivals and market days) that every package reads.
--
--   local Almanac = require("../Almanac/Almanac")
--   local alm = Almanac.new(adapter, rules)      -- rules: packages/Almanac/rules/<game>.luau
--   alm:hour()  alm:phase()  alm:season()  alm:weather()  alm:events()  alm:upcoming(5)
--   alm:at(t)                                     -- pure snapshot for any time (no overrides)
--   alm:step()                                    -- ~1/s; emits Almanac.* only on a change
--   alm:setOverride({ hour = 22, weather = "rain" })  alm:clearOverride()   -- QA staging
--
-- Time comes only from adapter.now(). Randomness comes only from seeded generators keyed on
-- (rules.seed, dayIndex) for events and (seed parts, front index) for weather, so every client
-- computes the same calendar with no network. See packages/Almanac/README.md for the rules
-- format.

local Contract = require("../Contract/Contract")

export type Season = { index: number, name: string, label: string }
export type Front = { index: number, startsAt: number, endsAt: number, progress: number }
export type Weather = {
	kind: string,
	name: string,
	intensity: number,
	active: boolean,
	season: number,
	front: Front?,
}
export type Occurrence = {
	id: string,
	name: string,
	kind: string,
	startsAt: number,
	endsAt: number,
	forced: boolean?,
}
export type Snapshot = {
	t: number,
	dayIndex: number,
	hour: number,
	phase: string,
	phaseEndsAt: number,
	weekday: number?,
	season: Season,
	weather: Weather,
	events: { Occurrence },
	overridden: { [string]: boolean },
}
export type Override = { hour: number?, weather: any?, season: any?, event: any? }

local Almanac = {}

local Methods = {}
Methods.__index = Methods

local TWO32 = 4294967296
local PHASE_IDS = { dawn = true, day = true, dusk = true, night = true }
local SCAN_LIMIT = 100000 -- recurrence steps any one query may walk (a guard, not a tuning)

-- 32-bit maths ----------------------------------------------------------------------------

local function imul(a: number, b: number): number
	local alo = bit32.band(a, 0xFFFF)
	local ahi = bit32.rshift(a, 16)
	return (((ahi * b) % 65536) * 65536 + alo * b) % TWO32
end

local function fmix32(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = imul(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = imul(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

-- hash(...) -> uint32: FNV-1a over tostring(arg) joined with "|".
function Almanac.hash(...: any): number
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	local s = table.concat(parts, "|")
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = imul(h, 16777619)
	end
	return h
end

-- A generator with `:next()` in [0, 1). "contract" = Contract.Rng (mulberry32, the default);
-- "xorshift32" = a transcription of the xorshift32 + fmix32 stream some games already seed
-- their weather with, so adopting the Almanac does not change that game's weather.
local function makeRng(kind: string?, seed: number): any
	if kind == "xorshift32" then
		local state = fmix32(math.floor(seed) % TWO32)
		if state == 0 then
			state = 0x9E3779B9
		end
		return {
			next = function(_self: any): number
				local x = state
				x = bit32.bxor(x, bit32.lshift(x, 13))
				x = bit32.bxor(x, bit32.rshift(x, 17))
				x = bit32.bxor(x, bit32.lshift(x, 5))
				state = x
				return x / TWO32
			end,
		}
	end
	return Contract.Rng.new(seed)
end

-- Rules helpers ---------------------------------------------------------------------------

local function num(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function secondsOf(tbl: any, key: string, L: number): number?
	-- `<key>Seconds` wins over `<key>Days`.
	local s = tbl[key .. "Seconds"]
	if s ~= nil then
		return s
	end
	local d = tbl[key .. "Days"]
	if d ~= nil then
		return d * L
	end
	return nil
end

local function seasonNames(rules: any): { string }
	return rules.seasons and rules.seasons.names or { "all" }
end

local function weatherKinds(rules: any): { [string]: boolean }
	local kinds: { [string]: boolean } = {}
	local W = rules.weather
	if type(W) ~= "table" then
		return kinds
	end
	kinds[W.clearKind or "clear"] = true
	if type(W.tables) == "table" then
		for _, list in W.tables do
			if type(list) == "table" then
				for _, e in list do
					if type(e) == "table" and type(e.kind) == "string" then
						kinds[e.kind] = true
					end
				end
			end
		end
	end
	return kinds
end

-- validate(rules) -> { problem }: every reason these rules cannot run (empty when fine).
function Almanac.validate(rules: any): { string }
	local p: { string } = {}
	local function bad(msg: string)
		table.insert(p, msg)
	end
	if type(rules) ~= "table" then
		return { "rules must be a table" }
	end
	local L = rules.dayLengthSeconds
	if not num(L) or L <= 0 then
		bad("dayLengthSeconds must be a number > 0")
		L = 1
	end
	if rules.epoch ~= nil and not num(rules.epoch) then
		bad("epoch must be a number (unix seconds of day 0, hour 0)")
	end
	if rules.seed ~= nil and not num(rules.seed) and type(rules.seed) ~= "string" then
		bad("seed must be a number or a string")
	end

	-- phases
	if type(rules.phases) ~= "table" or #rules.phases == 0 then
		bad("phases must be a non-empty list of { id, from }")
	else
		local prev = -1
		for i, ph in rules.phases do
			if type(ph) ~= "table" or not PHASE_IDS[ph.id] then
				bad(`phases[{i}].id must be dawn, day, dusk or night`)
			elseif not num(ph.from) or ph.from < 0 or ph.from >= 24 then
				bad(`phases[{i}].from must be an hour in [0, 24)`)
			elseif ph.from <= prev then
				bad(`phases[{i}].from must be greater than phases[{i - 1}].from (sorted, no duplicates)`)
			else
				prev = ph.from
			end
		end
	end

	-- seasons
	local S = rules.seasons
	if S ~= nil then
		if type(S) ~= "table" or type(S.names) ~= "table" or #S.names == 0 then
			bad("seasons.names must be a non-empty list")
		else
			local period = secondsOf(S, "period", L)
			if not num(period) or (period :: number) <= 0 then
				bad("seasons needs periodSeconds or periodDays > 0")
			end
			if S.labels ~= nil and (type(S.labels) ~= "table" or #S.labels ~= #S.names) then
				bad("seasons.labels must list one label per name")
			end
		end
	end

	-- week
	local Wk = rules.week
	if Wk ~= nil then
		if type(Wk) ~= "table" or not num(Wk.length) or Wk.length < 1 or Wk.length % 1 ~= 0 then
			bad("week.length must be a whole number >= 1")
		elseif Wk.names ~= nil and (type(Wk.names) ~= "table" or #Wk.names ~= Wk.length) then
			bad("week.names must list week.length names")
		end
	end

	-- weather
	local W = rules.weather
	if W ~= nil then
		if type(W) ~= "table" then
			bad("weather must be a table")
		else
			local front = secondsOf(W, "front", L)
			if not num(front) or (front :: number) <= 0 then
				bad("weather needs frontSeconds or frontDays > 0")
			end
			if W.activeSeconds ~= nil and (not num(W.activeSeconds) or W.activeSeconds <= 0 or (num(front) and W.activeSeconds > (front :: number))) then
				bad("weather.activeSeconds must be > 0 and no longer than a front")
			end
			if W.rng ~= nil and W.rng ~= "contract" and W.rng ~= "xorshift32" then
				bad("weather.rng must be \"contract\" or \"xorshift32\"")
			end
			if W.seedParts ~= nil and type(W.seedParts) ~= "table" then
				bad("weather.seedParts must be a list")
			end
			if type(W.tables) ~= "table" then
				bad("weather.tables must map season names (or \"all\") to weighted lists")
			else
				for _, sname in seasonNames(rules) do
					if W.tables[sname] == nil and W.tables.all == nil then
						bad(`weather.tables has no list for season "{sname}" and no "all" list`)
					end
				end
				for key, list in W.tables do
					if type(list) ~= "table" or #list == 0 then
						bad(`weather.tables.{key} must be a non-empty list`)
						continue
					end
					for i, e in list do
						local at = `weather.tables.{key}[{i}]`
						if type(e) ~= "table" or type(e.kind) ~= "string" then
							bad(at .. ".kind must be a string")
							continue
						end
						if not num(e.weight) or e.weight < 0 then
							bad(at .. ".weight must be a number >= 0")
						end
						local iv = e.intensity
						if iv ~= nil and (type(iv) ~= "table" or not num(iv[1]) or not num(iv[2]) or iv[1] < 0 or iv[2] > 1 or iv[1] > iv[2]) then
							bad(at .. ".intensity must be { lo, hi } with 0 <= lo <= hi <= 1")
						end
						if e.phases ~= nil then
							for _, ph in (type(e.phases) == "table" and e.phases or { e.phases }) :: any do
								if not PHASE_IDS[ph] then
									bad(at .. ".phases lists an unknown phase " .. tostring(ph))
								end
							end
						end
					end
				end
			end
		end
	end

	-- events
	local seenIds: { [string]: boolean } = {}
	local seasonSet: { [string]: boolean } = {}
	for _, n in seasonNames(rules) do
		seasonSet[n] = true
	end
	for i, e in (type(rules.events) == "table" and rules.events or {}) :: any do
		local at = `events[{i}]`
		if type(e) ~= "table" or type(e.id) ~= "string" then
			bad(at .. ".id must be a string")
			continue
		end
		at = `events[{i}] ({e.id})`
		if seenIds[e.id] then
			bad(at .. ": duplicate id")
		end
		seenIds[e.id] = true
		if e.windows ~= nil then
			if type(e.windows) ~= "table" or #e.windows == 0 then
				bad(at .. ".windows must be a non-empty list of { startsAt, endsAt }")
			else
				for j, w in e.windows do
					if type(w) ~= "table" or not num(w.startsAt) or not num(w.endsAt) or w.endsAt <= w.startsAt then
						bad(at .. `.windows[{j}] must have startsAt < endsAt`)
					end
				end
			end
		else
			local period = secondsOf(e, "every", L) or L
			if not num(period) or period <= 0 then
				bad(at .. ": everySeconds / everyDays must be > 0")
			end
			local length = secondsOf(e, "length", L)
			if length ~= nil and (not num(length) or length <= 0 or (num(period) and length > period * 64)) then
				bad(at .. ": lengthSeconds / lengthDays must be > 0 and at most 64 periods")
			end
			if e.hours ~= nil and (type(e.hours) ~= "table" or not num(e.hours.from) or not num(e.hours.to) or e.hours.from < 0 or e.hours.from >= 24 or e.hours.to < 0 or e.hours.to > 24) then
				bad(at .. ".hours must be { from, to } hours in [0, 24]")
			end
			if e.dayOfWeek ~= nil then
				if type(rules.week) ~= "table" then
					bad(at .. ".dayOfWeek needs rules.week")
				elseif type(e.dayOfWeek) == "string" then
					if not (rules.week.names and table.find(rules.week.names, e.dayOfWeek)) then
						bad(at .. ".dayOfWeek names no day in week.names")
					end
				elseif not num(e.dayOfWeek) or e.dayOfWeek < 0 or e.dayOfWeek >= (rules.week.length or 0) then
					bad(at .. ".dayOfWeek must be 0 .. week.length - 1 or a week name")
				end
			end
			if e.chance ~= nil and (not num(e.chance) or e.chance < 0 or e.chance > 1) then
				bad(at .. ".chance must be in [0, 1]")
			end
		end
		if e.seasons ~= nil then
			for _, s in (type(e.seasons) == "table" and e.seasons or { e.seasons }) :: any do
				if not seasonSet[s] then
					bad(at .. ".seasons lists an unknown season " .. tostring(s))
				end
			end
		end
	end

	-- weather entries gated on an event must name one
	if type(W) == "table" and type(W.tables) == "table" then
		for key, list in W.tables do
			if type(list) == "table" then
				for i, e in list do
					if type(e) == "table" and e.event ~= nil and not seenIds[e.event] then
						bad(`weather.tables.{key}[{i}].event names no event: {tostring(e.event)}`)
					end
				end
			end
		end
		if type(W.boosts) == "table" then
			for id in W.boosts do
				if not seenIds[id] then
					bad(`weather.boosts.{tostring(id)} names no event`)
				end
			end
		end
	end
	return p
end

-- Pure calendar maths (rules, t) ----------------------------------------------------------

local function epochOf(rules: any): number
	return rules.epoch or 0
end

-- clock(rules, t) -> dayIndex, secondOfDay, hour (0 <= hour < 24)
local function clock(rules: any, t: number): (number, number, number)
	local L = rules.dayLengthSeconds
	local rel = t - epochOf(rules)
	local day = math.floor(rel / L)
	local sod = rel - day * L
	local hour = sod * 24 / L
	if hour >= 24 then
		hour = 0
	end
	return day, sod, hour
end

local function phaseAt(rules: any, hour: number): string
	local list = rules.phases
	local out = list[#list].id -- before the first boundary: the last phase wraps past midnight
	for _, ph in list do
		if hour >= ph.from then
			out = ph.id
		end
	end
	return out
end

-- phaseEndsAt(rules, t) -> the time the phase next changes (the next boundary whose phase differs).
local function phaseEndsAt(rules: any, t: number): number
	local L = rules.dayLengthSeconds
	local day, _, hour = clock(rules, t)
	local here = phaseAt(rules, hour)
	local dayStart = epochOf(rules) + day * L
	for d = 0, 1 do
		for _, ph in rules.phases do
			local at = dayStart + d * L + ph.from * L / 24
			if at > t and ph.id ~= here then
				return at
			end
		end
	end
	return dayStart + 2 * L
end

local function seasonAt(rules: any, t: number): Season
	local S = rules.seasons
	if S == nil then
		return { index = 0, name = "all", label = "All year" }
	end
	local period = secondsOf(S, "period", rules.dayLengthSeconds) :: number
	local idx = math.floor((t - epochOf(rules) - (S.offsetSeconds or 0)) / period) % #S.names
	local name = S.names[idx + 1]
	return { index = idx, name = name, label = S.labels and S.labels[idx + 1] or name }
end

local function weekdayOf(rules: any, day: number): number?
	local Wk = rules.week
	if Wk == nil then
		return nil
	end
	return (day + (Wk.offset or 0)) % Wk.length
end

local function listHas(list: any, v: any): boolean
	if type(list) ~= "table" then
		return list == v
	end
	return table.find(list, v) ~= nil
end

-- Events --------------------------------------------------------------------------------

local function recurrence(rules: any, e: any): (number, number, number)
	local L = rules.dayLengthSeconds
	local period = secondsOf(e, "every", L) or L
	local base = epochOf(rules) + (secondsOf(e, "offset", L) or 0)
	local length = secondsOf(e, "length", L)
	if e.hours ~= nil then
		base += e.hours.from * L / 24
		if length == nil then
			local span = (e.hours.to - e.hours.from) % 24
			length = span > 0 and span * L / 24 or L
		end
	end
	return base, period, length or L
end

local function occurrenceOk(rules: any, e: any, startsAt: number): boolean
	local L = rules.dayLengthSeconds
	local day = math.floor((startsAt - epochOf(rules)) / L)
	if e.dayOfWeek ~= nil then
		local wd = weekdayOf(rules, day)
		local want = e.dayOfWeek
		if type(want) == "string" then
			want = (table.find(rules.week.names, want) :: number) - 1
		end
		if wd ~= want then
			return false
		end
	end
	if e.seasons ~= nil and not listHas(e.seasons, seasonAt(rules, startsAt).name) then
		return false
	end
	if e.chance ~= nil then
		-- randomness keyed on (rules.seed, dayIndex): same on every client
		local r = Contract.Rng.new(Almanac.hash(rules.seed or 0, "event", e.id, day)):next()
		if r >= e.chance then
			return false
		end
	end
	return true
end

local function occ(e: any, s: number, en: number): Occurrence
	return { id = e.id, name = e.name or e.id, kind = e.kind or "festival", startsAt = s, endsAt = en }
end

-- occurrences(rules, e, t0, t1) -> every occurrence of e overlapping [t0, t1), sorted.
local function occurrences(rules: any, e: any, t0: number, t1: number): { Occurrence }
	local out: { Occurrence } = {}
	if e.windows ~= nil then
		for _, w in e.windows do
			if w.startsAt < t1 and w.endsAt > t0 then
				table.insert(out, occ(e, w.startsAt, w.endsAt))
			end
		end
		table.sort(out, function(a, b)
			return a.startsAt < b.startsAt
		end)
		return out
	end
	local base, period, length = recurrence(rules, e)
	local k0 = math.floor((t0 - length - base) / period)
	local k1 = math.floor((t1 - base) / period)
	if k1 - k0 > SCAN_LIMIT then
		error(`Almanac: event {e.id} spans {k1 - k0} recurrences in one query (limit {SCAN_LIMIT})`)
	end
	for k = k0, k1 do
		local s = base + k * period
		local en = s + length
		if s < t1 and en > t0 and occurrenceOk(rules, e, s) then
			table.insert(out, occ(e, s, en))
		end
	end
	return out
end

-- eventsAt(rules, t) -> every occurrence with startsAt <= t < endsAt, in rules order.
local function eventsAt(rules: any, t: number): { Occurrence }
	local out: { Occurrence } = {}
	for _, e in (rules.events or {}) :: any do
		if e.windows ~= nil then
			for _, w in e.windows do
				if w.startsAt <= t and t < w.endsAt then
					table.insert(out, occ(e, w.startsAt, w.endsAt))
				end
			end
		else
			local base, period, length = recurrence(rules, e)
			for k = math.floor((t - length - base) / period), math.floor((t - base) / period) do
				local s = base + k * period
				if s <= t and t < s + length and occurrenceOk(rules, e, s) then
					table.insert(out, occ(e, s, s + length))
				end
			end
		end
	end
	return out
end

-- nextOccurrences(rules, e, t, n) -> the first n occurrences of e starting after t.
local function nextOccurrences(rules: any, e: any, t: number, n: number): { Occurrence }
	local out: { Occurrence } = {}
	if e.windows ~= nil then
		for _, w in e.windows do
			if w.startsAt > t then
				table.insert(out, occ(e, w.startsAt, w.endsAt))
			end
		end
		table.sort(out, function(a, b)
			return a.startsAt < b.startsAt
		end)
		while #out > n do
			table.remove(out)
		end
		return out
	end
	local base, period, length = recurrence(rules, e)
	local k = math.floor((t - base) / period)
	local steps = 0
	while #out < n and steps < SCAN_LIMIT do
		local s = base + k * period
		if s > t and occurrenceOk(rules, e, s) then
			table.insert(out, occ(e, s, s + length))
		end
		k += 1
		steps += 1
	end
	return out
end

-- Weather -------------------------------------------------------------------------------

local function frontLength(rules: any): number
	return secondsOf(rules.weather, "front", rules.dayLengthSeconds) :: number
end

local function frontIndex(rules: any, t: number): (number, number)
	local W = rules.weather
	local len = frontLength(rules)
	local origin = epochOf(rules) + (W.offsetSeconds or 0)
	local fi = math.floor((t - origin) / len)
	return fi, origin + fi * len
end

local function seedFor(rules: any, fi: number): number
	local W = rules.weather
	local parts = {}
	for _, p in (W.seedParts or { "$seed", "weather" }) :: any do
		if p == "$seed" then
			table.insert(parts, rules.seed or 0)
		elseif p == "$region" then
			table.insert(parts, rules.region or "")
		else
			table.insert(parts, p)
		end
	end
	table.insert(parts, fi)
	return Almanac.hash(table.unpack(parts))
end

-- odds(rules, fs) -> { {entry, weight} } for a front starting at fs (gates and boosts applied).
local function oddsAt(rules: any, fs: number, season: Season): { any }
	local W = rules.weather
	local list = W.tables[season.name] or W.tables.all
	local _, _, hour = clock(rules, fs)
	local phase = phaseAt(rules, hour)
	local active: { [string]: boolean } = {}
	for _, o in eventsAt(rules, fs) do
		active[o.id] = true
	end
	local bias = rules.region and W.bias and W.bias[rules.region] or nil
	local out = {}
	for _, e in list do
		local w = e.weight * ((bias and tonumber(bias[e.kind])) or 1)
		if e.phases ~= nil and not listHas(e.phases, phase) then
			w = 0
		end
		if e.event ~= nil and not active[e.event] then
			w = 0
		end
		for id in active do
			local b = W.boosts and W.boosts[id]
			if b and tonumber(b[e.kind]) then
				w *= b[e.kind]
			end
		end
		table.insert(out, { entry = e, weight = math.max(0, w) })
	end
	return out
end

local function kindName(rules: any, kind: string): string
	local names = rules.weather and rules.weather.names
	return names and names[kind] or kind
end

local function rollFront(rules: any, fi: number, fs: number): any
	local W = rules.weather
	local season = seasonAt(rules, fs)
	local odds = oddsAt(rules, fs, season)
	local rng = makeRng(W.rng, seedFor(rules, fi))
	-- exactly two draws per front: the kind, then the intensity
	local r1 = rng:next()
	local total = 0
	for _, o in odds do
		total += o.weight
	end
	local pick = odds[1].entry
	if total > 0 then
		local x = r1 * total
		pick = odds[#odds].entry
		for _, o in odds do
			x -= o.weight
			if x < 0 then
				pick = o.entry
				break
			end
		end
	end
	local r2 = rng:next()
	local iv = pick.intensity or (pick.kind == (W.clearKind or "clear") and { 0, 0 } or { 1, 1 })
	local intensity = iv[1] + (iv[2] - iv[1]) * r2
	local m = 10 ^ (W.intensityDecimals or 2)
	intensity = math.floor(intensity * m + 0.5) / m
	return { kind = pick.kind, intensity = intensity, season = season.index }
end

-- Instance ------------------------------------------------------------------------------

-- new(adapter, rules) -> an Almanac. Errors (listing every problem) on bad rules or adapter.
function Almanac.new(adapter: Contract.Adapter, rules: any): any
	local problems = Contract.check(adapter)
	if #problems > 0 then
		error("Almanac.new: bad adapter: " .. table.concat(problems, "; "), 2)
	end
	local rp = Almanac.validate(rules)
	if #rp > 0 then
		error("Almanac.new: bad rules: " .. table.concat(rp, "; "), 2)
	end
	local self = setmetatable({
		_adapter = adapter,
		_rules = rules,
		_override = {},
		_fronts = {},
		_frontCount = 0,
		_last = nil,
	}, Methods)
	return self
end

local function frontRoll(self: any, fi: number, fs: number): any
	local c = self._fronts[fi]
	if c == nil then
		if self._frontCount >= 512 then
			self._fronts = {}
			self._frontCount = 0
		end
		c = rollFront(self._rules, fi, fs)
		self._fronts[fi] = c
		self._frontCount += 1
	end
	return c
end

local function weatherAt(self: any, t: number): Weather
	local rules = self._rules
	local W = rules.weather
	if W == nil then
		return { kind = "clear", name = "Clear", intensity = 0, active = false, season = seasonAt(rules, t).index, front = nil }
	end
	local fi, fs = frontIndex(rules, t)
	local len = frontLength(rules)
	local roll = frontRoll(self, fi, fs)
	local kind, intensity, active = roll.kind, roll.intensity, true
	local clearKind = W.clearKind or "clear"
	if W.activeSeconds ~= nil and t - fs >= W.activeSeconds then
		kind, intensity, active = clearKind, 0, false
	end
	if kind == clearKind then
		active = false
	end
	return {
		kind = kind,
		name = kindName(rules, kind),
		intensity = intensity,
		active = active,
		season = roll.season,
		front = { index = fi, startsAt = fs, endsAt = fs + len, progress = (t - fs) / len },
	}
end

-- at(t) -> the pure snapshot for time t (overrides are NOT applied).
function Methods.at(self: any, t: number): Snapshot
	if not num(t) then
		error("Almanac: time must be a finite number, got " .. tostring(t), 2)
	end
	local rules = self._rules
	local day, _, hour = clock(rules, t)
	return {
		t = t,
		dayIndex = day,
		hour = hour,
		phase = phaseAt(rules, hour),
		phaseEndsAt = phaseEndsAt(rules, t),
		weekday = weekdayOf(rules, day),
		season = seasonAt(rules, t),
		weather = weatherAt(self, t),
		events = eventsAt(rules, t),
		overridden = {},
	}
end

local function seasonFromOverride(rules: any, v: any): Season
	local names = seasonNames(rules)
	local idx: number? = nil
	if type(v) == "number" and v % 1 == 0 and v >= 0 and v < #names then
		idx = v
	elseif type(v) == "string" and table.find(names, v) then
		idx = (table.find(names, v) :: number) - 1
	end
	if idx == nil then
		error(`Almanac.setOverride: unknown season {tostring(v)} (known: {table.concat(names, ", ")})`, 3)
	end
	local S = rules.seasons
	local name = names[idx + 1]
	return { index = idx, name = name, label = S and S.labels and S.labels[idx + 1] or (S and name or "All year") }
end

-- setOverride({hour?, weather?, season?, event?}) pins values for Shot Rig staging. Fields
-- merge with the current override. weather = kind or {kind, intensity?}; season = index or
-- name; event = an event id (forced active, all others hidden) or false (no events).
function Methods.setOverride(self: any, o: Override)
	assert(type(o) == "table", "Almanac.setOverride needs a table")
	local rules = self._rules
	local nextO = table.clone(self._override)
	if o.hour ~= nil then
		if not num(o.hour) or (o.hour :: number) < 0 or (o.hour :: number) >= 24 then
			error("Almanac.setOverride: hour must be in [0, 24), got " .. tostring(o.hour), 2)
		end
		nextO.hour = o.hour
	end
	if o.weather ~= nil then
		local w = o.weather
		local kind = type(w) == "table" and w.kind or w
		if type(kind) ~= "string" or not weatherKinds(rules)[kind] then
			local known = {}
			for k in weatherKinds(rules) do
				table.insert(known, k)
			end
			table.sort(known)
			error(`Almanac.setOverride: unknown weather {tostring(kind)} (known: {table.concat(known, ", ")})`, 2)
		end
		local intensity = type(w) == "table" and w.intensity or nil
		if intensity ~= nil and (not num(intensity) or intensity < 0 or intensity > 1) then
			error("Almanac.setOverride: weather intensity must be in [0, 1]", 2)
		end
		if intensity == nil then
			intensity = kind == ((rules.weather and rules.weather.clearKind) or "clear") and 0 or 1
		end
		nextO.weather = { kind = kind, intensity = intensity }
	end
	if o.season ~= nil then
		nextO.season = seasonFromOverride(rules, o.season)
	end
	if o.event ~= nil then
		if o.event ~= false then
			local found = nil
			for _, e in (rules.events or {}) :: any do
				if e.id == o.event then
					found = e
				end
			end
			if found == nil then
				error("Almanac.setOverride: unknown event " .. tostring(o.event), 2)
			end
		end
		nextO.event = o.event
	end
	self._override = nextO
end

function Methods.clearOverride(self: any)
	self._override = {}
end

function Methods.override(self: any): any
	return table.clone(self._override)
end

-- snapshot() -> at(now) with the override laid over it.
function Methods.snapshot(self: any): Snapshot
	local t = self._adapter.now()
	local s = self:at(t)
	local o = self._override
	local rules = self._rules
	if o.hour ~= nil then
		s.hour = o.hour
		s.phase = phaseAt(rules, o.hour)
		s.overridden.hour = true
		s.overridden.phase = true
	end
	if o.season ~= nil then
		s.season = table.clone(o.season)
		s.overridden.season = true
	end
	if o.weather ~= nil then
		s.weather = table.clone(s.weather)
		s.weather.kind = o.weather.kind
		s.weather.name = kindName(rules, o.weather.kind)
		s.weather.intensity = o.weather.intensity
		s.weather.active = o.weather.kind ~= ((rules.weather and rules.weather.clearKind) or "clear")
		s.overridden.weather = true
	end
	if o.event ~= nil then
		s.events = {}
		if o.event ~= false then
			for _, e in (rules.events or {}) :: any do
				if e.id == o.event then
					local forced = occ(e, t, t)
					forced.forced = true
					s.events = { forced }
				end
			end
		end
		s.overridden.event = true
	end
	return s
end

function Methods.hour(self: any): number
	return self:snapshot().hour
end

function Methods.dayIndex(self: any): number
	return (clock(self._rules, self._adapter.now()))
end

function Methods.phase(self: any): string
	return self:snapshot().phase
end

function Methods.season(self: any): Season
	return self:snapshot().season
end

function Methods.weather(self: any): Weather
	return self:snapshot().weather
end

function Methods.events(self: any): { Occurrence }
	return self:snapshot().events
end

function Methods.rules(self: any): any
	return self._rules
end

-- odds(t?) -> { {kind, weight, p} } the weather table for the front holding t (default now),
-- after phase / event gates, region bias and event boosts. p is weight / total.
function Methods.odds(self: any, t: number?): { any }
	local rules = self._rules
	if rules.weather == nil then
		return {}
	end
	local _, fs = frontIndex(rules, t or self._adapter.now())
	local odds = oddsAt(rules, fs, seasonAt(rules, fs))
	local total = 0
	for _, o in odds do
		total += o.weight
	end
	local out = {}
	for _, o in odds do
		table.insert(out, { kind = o.entry.kind, weight = o.weight, p = total > 0 and o.weight / total or 0 })
	end
	return out
end

-- upcoming(n) -> the next n event occurrences starting after now, soonest first.
function Methods.upcoming(self: any, n: number): { Occurrence }
	local rules = self._rules
	local t = self._adapter.now()
	local all: { Occurrence } = {}
	for _, e in (rules.events or {}) :: any do
		for _, o in nextOccurrences(rules, e, t, n) do
			table.insert(all, o)
		end
	end
	table.sort(all, function(a, b)
		if a.startsAt ~= b.startsAt then
			return a.startsAt < b.startsAt
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(n, #all) do
		out[i] = all[i]
	end
	return out
end

-- calendar(t0, t1) -> { days, events, fronts } for [t0, t1): every day start, every event
-- occurrence overlapping the span, every weather front overlapping it with its roll.
function Methods.calendar(self: any, t0: number, t1: number): any
	local rules = self._rules
	local L = rules.dayLengthSeconds
	local days, events, fronts = {}, {}, {}
	local d0 = math.floor((t0 - epochOf(rules)) / L)
	local d1 = math.ceil((t1 - epochOf(rules)) / L) - 1 -- the last day starting before t1
	if d1 - d0 > SCAN_LIMIT then
		error(`Almanac.calendar: {d1 - d0} days in one query (limit {SCAN_LIMIT})`, 2)
	end
	for d = d0, d1 do
		local s = epochOf(rules) + d * L
		table.insert(days, { dayIndex = d, startsAt = s, weekday = weekdayOf(rules, d), season = seasonAt(rules, s) })
	end
	for _, e in (rules.events or {}) :: any do
		for _, o in occurrences(rules, e, t0, t1) do
			table.insert(events, o)
		end
	end
	table.sort(events, function(a, b)
		if a.startsAt ~= b.startsAt then
			return a.startsAt < b.startsAt
		end
		return a.id < b.id
	end)
	if rules.weather ~= nil then
		local len = frontLength(rules)
		local f0, fs0 = frontIndex(rules, t0)
		local f1 = f0 + math.ceil((t1 - fs0) / len) - 1 -- the last front starting before t1
		if f1 - f0 > SCAN_LIMIT then
			error(`Almanac.calendar: {f1 - f0} fronts in one query (limit {SCAN_LIMIT})`, 2)
		end
		for fi = f0, f1 do
			local fs = fs0 + (fi - f0) * len
			local r = frontRoll(self, fi, fs)
			table.insert(fronts, {
				index = fi,
				startsAt = fs,
				endsAt = fs + len,
				activeUntil = rules.weather.activeSeconds and fs + rules.weather.activeSeconds or fs + len,
				kind = r.kind,
				name = kindName(rules, r.kind),
				intensity = r.intensity,
				season = r.season,
			})
		end
	end
	return { days = days, events = events, fronts = fronts }
end

-- step() -> { {event, payload} } emitted. Call about once a second. Emits Almanac.Hour,
-- Almanac.Phase, Almanac.Season, Almanac.Weather and Almanac.Event (one per start / end)
-- through adapter.emit only when the value changed since the last step (the first step emits
-- everything, so listeners start from a known state). Overrides count as values.
function Methods.step(self: any): { any }
	local s = self:snapshot()
	local last = self._last
	local sent = {}
	local function emit(name: string, payload: any)
		self._adapter.emit(name, payload)
		table.insert(sent, { event = name, payload = payload })
	end
	local hourInt = math.floor(s.hour)
	if last == nil or last.hourInt ~= hourInt then
		emit("Almanac.Hour", { hour = hourInt, exact = s.hour, dayIndex = s.dayIndex })
	end
	if last == nil or last.phase ~= s.phase then
		emit("Almanac.Phase", { phase = s.phase, previous = last and last.phase or nil, endsAt = s.phaseEndsAt })
	end
	if last == nil or last.season ~= s.season.index then
		emit("Almanac.Season", table.clone(s.season))
	end
	local w = s.weather
	local frontIdx = w.front and w.front.index or -1
	if last == nil or last.wKind ~= w.kind or last.wIntensity ~= w.intensity or last.wFront ~= frontIdx then
		emit("Almanac.Weather", { kind = w.kind, name = w.name, intensity = w.intensity, active = w.active, front = w.front })
	end
	local keys: { [string]: Occurrence } = {}
	for _, o in s.events do
		keys[o.id .. "@" .. tostring(o.forced and "forced" or o.startsAt)] = o
	end
	local prev = last and last.events or {}
	local ended = {}
	for k, o in prev do
		if keys[k] == nil then
			table.insert(ended, { k = k, o = o })
		end
	end
	table.sort(ended, function(a, b)
		return a.k < b.k
	end)
	for _, x in ended do
		emit("Almanac.Event", { id = x.o.id, name = x.o.name, kind = x.o.kind, state = "end", startsAt = x.o.startsAt, endsAt = x.o.endsAt })
	end
	local started = {}
	for k, o in keys do
		if prev[k] == nil then
			table.insert(started, { k = k, o = o })
		end
	end
	table.sort(started, function(a, b)
		return a.k < b.k
	end)
	for _, x in started do
		emit("Almanac.Event", { id = x.o.id, name = x.o.name, kind = x.o.kind, state = "start", startsAt = x.o.startsAt, endsAt = x.o.endsAt })
	end
	self._last = {
		hourInt = hourInt,
		phase = s.phase,
		season = s.season.index,
		wKind = w.kind,
		wIntensity = w.intensity,
		wFront = frontIdx,
		events = keys,
	}
	return sent
end

return Almanac
