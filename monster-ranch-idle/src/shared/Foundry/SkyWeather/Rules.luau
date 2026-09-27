--!strict
-- Rules: validation for SkyWeather rules, alone and against the Almanac rules they ride on.
--
--   Rules.validate(rules) -> { problem }          -- every reason these rules cannot run
--   Rules.check(rules, almanacRules) -> { problem } -- validate + kinds covered + front timing
--   Rules.bounds(b) -> { problem }                 -- {min = {x, z}, max = {x, z}}

local Rules = {}

local TOP = {
	id = true,
	seed = true,
	studsPerMeter = true,
	defaultBounds = true,
	wind = true,
	fronts = true,
	kinds = true,
	precipitation = true,
	surface = true,
	lightning = true,
	emitters = true,
	clouds = true,
}

local KIND_KEYS = {
	wind = true,
	gust = true,
	cloudCover = true,
	precipitation = true,
	rate = true,
	storm = true,
	dry = true,
	fog = true,
	note = true,
}

-- Optional clouds fields (the sun-occlusion cloud field and the sun path); these defaults apply
-- when a rules file leaves them out.
Rules.CLOUD_DEFAULTS = { height = 800, cellSize = 500, evolveSeconds = 180, edge = 0.1 }
Rules.SUN_DEFAULTS = { rise = 6, set = 18, peak = 60, heading = 0, fade = 6 }

local function num(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A value that is a number or a {lo, hi} pair; returns a problem string or nil.
local function range(v: any, lo: number, hi: number): string?
	if num(v) then
		if v < lo or v > hi then
			return `{v} is outside [{lo}, {hi}]`
		end
		return nil
	end
	if type(v) == "table" and num(v[1]) and num(v[2]) then
		for _, x in { v[1], v[2] } do
			if x < lo or x > hi then
				return `{x} is outside [{lo}, {hi}]`
			end
		end
		return nil
	end
	return "must be a number or a {lo, hi} pair, got " .. typeof(v)
end

local function pos(v: any): (number?, number?)
	if typeof(v) == "Vector3" then
		return (v :: any).X, (v :: any).Z
	end
	if type(v) ~= "table" then
		return nil, nil
	end
	local x, z = v.x or v.X, v.z or v.Z
	if num(x) and num(z) then
		return x, z
	end
	return nil, nil
end
Rules.pos = pos

function Rules.bounds(b: any): { string }
	if type(b) ~= "table" then
		return { "bounds must be a table {min = {x, z}, max = {x, z}}, got " .. typeof(b) }
	end
	local x0, z0 = pos(b.min)
	local x1, z1 = pos(b.max)
	if x0 == nil or x1 == nil then
		return { "bounds.min and bounds.max need finite x and z" }
	end
	if (x1 :: number) <= (x0 :: number) or (z1 :: number) <= (z0 :: number) then
		return { `bounds.max ({x1}, {z1}) must exceed bounds.min ({x0}, {z0}) on both axes` }
	end
	return {}
end

local function positive(p: { string }, tbl: any, key: string, where: string, allowZero: boolean?)
	local v = tbl[key]
	if not num(v) or v < 0 or (v == 0 and not allowZero) then
		table.insert(p, `{where}.{key} must be a {allowZero and "number >= 0" or "number > 0"}, got {tostring(v)}`)
	end
end

function Rules.validate(rules: any): { string }
	local p: { string } = {}
	if type(rules) ~= "table" then
		return { "rules must be a table, got " .. typeof(rules) }
	end
	for k in rules do
		if not TOP[k] then
			table.insert(p, `unknown top-level key '{tostring(k)}'`)
		end
	end
	if type(rules.id) ~= "string" then
		table.insert(p, "id must be a string")
	end
	if rules.seed ~= nil and type(rules.seed) ~= "number" and type(rules.seed) ~= "string" then
		table.insert(p, "seed must be a number or a string")
	end
	positive(p, rules, "studsPerMeter", "rules")
	if rules.defaultBounds ~= nil then
		for _, b in Rules.bounds(rules.defaultBounds) do
			table.insert(p, "defaultBounds: " .. b)
		end
	end

	local W = rules.wind
	if type(W) ~= "table" then
		table.insert(p, "wind must be a table")
	else
		if not num(W.direction) then
			table.insert(p, "wind.direction must be a number (degrees, 0 = +X, 90 = +Z)")
		end
		if not num(W.drift) or W.drift < 0 or W.drift > 180 then
			table.insert(p, "wind.drift must be in [0, 180] degrees")
		end
		positive(p, W, "gustScale", "wind")
		positive(p, W, "gustSeconds", "wind")
		positive(p, W, "gustTravel", "wind", true)
	end

	local F = rules.fronts
	if type(F) ~= "table" then
		table.insert(p, "fronts must be a table")
	else
		positive(p, F, "crossSeconds", "fronts", true)
		positive(p, F, "blendSeconds", "fronts", true)
	end

	local P = rules.precipitation
	if type(P) ~= "table" then
		table.insert(p, "precipitation must be a table of {particlesAtFull, fallSpeed, wets?, snows?, lightBelow?}")
		P = {}
	else
		for name, e in P do
			local where = `precipitation.{name}`
			if name == "none" then
				table.insert(p, "precipitation.none is reserved (it means no precipitation)")
			end
			if type(e) ~= "table" then
				table.insert(p, where .. " must be a table")
				continue
			end
			positive(p, e, "particlesAtFull", where, true)
			positive(p, e, "fallSpeed", where)
			if e.wets ~= nil and type(e.wets) ~= "boolean" then
				table.insert(p, where .. ".wets must be a boolean")
			end
			if e.snows ~= nil and type(e.snows) ~= "boolean" then
				table.insert(p, where .. ".snows must be a boolean")
			end
			if e.wets and e.snows then
				table.insert(p, where .. " cannot both wet and snow")
			end
			if e.lightBelow ~= nil and (not num(e.lightBelow) or e.lightBelow < 0 or e.lightBelow > 1) then
				table.insert(p, where .. ".lightBelow must be in [0, 1]")
			end
		end
	end

	local L = rules.lightning
	local slot = 0
	if type(L) ~= "table" then
		table.insert(p, "lightning must be a table")
	else
		positive(p, L, "slotSeconds", "lightning")
		positive(p, L, "thunderSeconds", "lightning", true)
		positive(p, L, "hearRadius", "lightning")
		positive(p, L, "flashRadius", "lightning")
		slot = num(L.slotSeconds) and L.slotSeconds or 0
		if type(L.flash) ~= "table" or #L.flash == 0 then
			table.insert(p, "lightning.flash must be a list of {from, to, level} pulses")
		else
			for i, f in L.flash do
				if type(f) ~= "table" or not num(f[1]) or not num(f[2]) or not num(f[3]) or f[1] < 0 or f[2] <= f[1] or f[3] < 0 or f[3] > 1 then
					table.insert(p, "lightning.flash[" .. i .. "] must be {from >= 0, to > from, level 0..1}")
				end
			end
		end
	end

	local K = rules.kinds
	if type(K) ~= "table" or next(K) == nil then
		table.insert(p, "kinds must be a non-empty table keyed by weather kind")
	else
		for kind, k in K do
			local where = `kinds.{kind}`
			if type(k) ~= "table" then
				table.insert(p, where .. " must be a table")
				continue
			end
			for key in k do
				if not KIND_KEYS[key] then
					table.insert(p, `{where}: unknown key '{tostring(key)}'`)
				end
			end
			local r = range(k.wind, 0, 500)
			if r then
				table.insert(p, `{where}.wind (studs/s) {r}`)
			end
			r = range(k.gust, 0, 4)
			if r then
				table.insert(p, `{where}.gust (fraction added at full gust) {r}`)
			end
			r = range(k.cloudCover, 0, 1)
			if r then
				table.insert(p, `{where}.cloudCover {r}`)
			end
			if k.fog ~= nil then
				r = range(k.fog, 0, 1)
				if r then
					table.insert(p, `{where}.fog {r}`)
				end
			end
			if k.precipitation ~= nil then
				if type(k.precipitation) ~= "string" or P[k.precipitation] == nil then
					table.insert(p, `{where}.precipitation '{tostring(k.precipitation)}' is not a key of rules.precipitation`)
				end
			end
			if k.rate ~= nil and (not num(k.rate) or k.rate < 0 or k.rate > 1) then
				table.insert(p, where .. ".rate must be in [0, 1]")
			end
			if k.dry ~= nil and (not num(k.dry) or k.dry < 0) then
				table.insert(p, where .. ".dry must be a number >= 0 (drying multiplier)")
			end
			if k.storm ~= nil then
				local s = k.storm
				if type(s) ~= "table" or not num(s.strikesPerMinute) or s.strikesPerMinute < 0 then
					table.insert(p, where .. ".storm must be {strikesPerMinute >= 0}")
				elseif slot > 0 and s.strikesPerMinute * slot / 60 > 1 then
					table.insert(p, `{where}.storm: {s.strikesPerMinute}/min needs more than one strike per {slot} s slot (lower lightning.slotSeconds)`)
				end
			end
		end
	end

	local S = rules.surface
	if type(S) ~= "table" then
		table.insert(p, "surface must be a table")
	else
		positive(p, S, "lookbackSeconds", "surface")
		positive(p, S, "step", "surface")
		for _, key in { "wetPerSecond", "dry", "drySun", "dryWind", "snowPerSecond", "melt", "meltSun", "meltRain", "meltWet" } do
			positive(p, S, key, "surface", true)
		end
		if num(S.lookbackSeconds) and num(S.step) and S.step > 0 and S.lookbackSeconds / S.step > 2000 then
			table.insert(p, `surface: lookbackSeconds / step = {S.lookbackSeconds / S.step} intervals (limit 2000)`)
		end
		if not num(S.puddleFrom) or S.puddleFrom < 0 or S.puddleFrom >= 1 then
			table.insert(p, "surface.puddleFrom must be in [0, 1)")
		end
		if type(S.sun) ~= "table" then
			table.insert(p, "surface.sun must map Almanac phase ids to 0..1")
		else
			for ph, v in S.sun do
				if not num(v) or v < 0 or v > 1 then
					table.insert(p, `surface.sun.{ph} must be in [0, 1]`)
				end
			end
		end
		if S.seasons ~= nil then
			if type(S.seasons) ~= "table" then
				table.insert(p, "surface.seasons must map season names to {dry?, melt?}")
			else
				for name, m in S.seasons do
					if type(m) ~= "table" then
						table.insert(p, `surface.seasons.{name} must be a table`)
					else
						for key, v in m do
							if (key ~= "dry" and key ~= "melt") or not num(v) or v < 0 then
								table.insert(p, `surface.seasons.{name}.{tostring(key)}: only dry / melt multipliers >= 0`)
							end
						end
					end
				end
			end
		end
	end

	local E = rules.emitters
	if type(E) ~= "table" then
		table.insert(p, "emitters must be a table")
	else
		positive(p, E, "spacing", "emitters")
		positive(p, E, "radius", "emitters", true)
		if not num(E.height) then
			table.insert(p, "emitters.height must be a number (studs above the camera focus)")
		end
		if not num(E.defaultBudget) or E.defaultBudget < 0 or E.defaultBudget % 1 ~= 0 then
			table.insert(p, "emitters.defaultBudget must be a whole number >= 0")
		end
		positive(p, E, "minRate", "emitters", true)
		if E.snap ~= nil and type(E.snap) ~= "boolean" then
			table.insert(p, "emitters.snap must be a boolean")
		end
		if E.upwind ~= nil and type(E.upwind) ~= "boolean" then
			table.insert(p, "emitters.upwind must be a boolean")
		end
		if type(E.qualityScale) ~= "table" or #E.qualityScale ~= 3 then
			table.insert(p, "emitters.qualityScale must be {low, medium, high} multipliers")
		else
			for i, v in E.qualityScale do
				if not num(v) or v < 0 then
					table.insert(p, `emitters.qualityScale[{i}] must be a number >= 0`)
				end
			end
		end
	end

	local C = rules.clouds
	if type(C) ~= "table" then
		table.insert(p, "clouds must be a table")
	else
		positive(p, C, "speed", "clouds", true)
		positive(p, C, "period", "clouds")
		positive(p, C, "wrap", "clouds")
		if not num(C.variation) or C.variation < 0 or C.variation > 1 then
			table.insert(p, "clouds.variation must be in [0, 1] (so the drift never reverses)")
		end
		for _, key in { "height", "cellSize", "evolveSeconds" } do
			if C[key] ~= nil then
				positive(p, C, key, "clouds")
			end
		end
		if C.edge ~= nil and (not num(C.edge) or C.edge <= 0 or C.edge > 0.5) then
			table.insert(p, "clouds.edge must be in (0, 0.5] (the soft edge of a cloud, in noise units)")
		end
		local sun = C.sun
		if sun ~= nil then
			if type(sun) ~= "table" then
				table.insert(p, "clouds.sun must be a table {rise?, set?, peak?, heading?, fade?}")
			else
				for key in sun do
					if Rules.SUN_DEFAULTS[key] == nil then
						table.insert(p, `clouds.sun: unknown key '{tostring(key)}'`)
					end
				end
				for _, key in { "rise", "set" } do
					local v = sun[key]
					if v ~= nil and (not num(v) or v < 0 or v >= 24) then
						table.insert(p, `clouds.sun.{key} must be an Almanac hour in [0, 24)`)
					end
				end
				local rise = sun.rise or Rules.SUN_DEFAULTS.rise
				local set = sun.set or Rules.SUN_DEFAULTS.set
				if num(rise) and num(set) and rise == set then
					table.insert(p, "clouds.sun.set must differ from clouds.sun.rise (the sun must be up for part of the day)")
				end
				if sun.peak ~= nil and (not num(sun.peak) or sun.peak <= 0 or sun.peak > 90) then
					table.insert(p, "clouds.sun.peak must be in (0, 90] degrees (the midday elevation)")
				end
				if sun.heading ~= nil and not num(sun.heading) then
					table.insert(p, "clouds.sun.heading must be a number (degrees, 0 = +X, 90 = +Z)")
				end
				if sun.fade ~= nil and (not num(sun.fade) or sun.fade <= 0 or sun.fade > 90) then
					table.insert(p, "clouds.sun.fade must be in (0, 90] degrees (occlusion fades in above the horizon)")
				end
			end
		end
	end
	table.sort(p)
	return p
end

-- The Almanac's weather kinds (clear kind included), as a sorted list.
local function almanacKinds(arules: any): { string }
	local seen: { [string]: boolean } = {}
	local W = arules.weather
	if type(W) == "table" then
		seen[W.clearKind or "clear"] = true
		for _, list in (W.tables or {}) :: any do
			for _, e in list do
				if type(e) == "table" and type(e.kind) == "string" then
					seen[e.kind] = true
				end
			end
		end
	else
		seen.clear = true
	end
	local out = {}
	for k in seen do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end
Rules.almanacKinds = almanacKinds

-- frontSeconds(almanacRules) -> the Almanac's front length (nil without weather).
function Rules.frontSeconds(arules: any): number?
	local W = arules.weather
	if type(W) ~= "table" then
		return nil
	end
	if num(W.frontSeconds) then
		return W.frontSeconds
	end
	if num(W.frontDays) and num(arules.dayLengthSeconds) then
		return W.frontDays * arules.dayLengthSeconds
	end
	return nil
end

function Rules.check(rules: any, arules: any): { string }
	local p = Rules.validate(rules)
	if #p > 0 then
		return p
	end
	if type(arules) ~= "table" then
		return { "almanac rules must be a table" }
	end
	local W = arules.weather
	local clearKind = (type(W) == "table" and W.clearKind) or "clear"
	for _, kind in almanacKinds(arules) do
		if rules.kinds[kind] == nil then
			table.insert(p, `the Almanac rolls '{kind}' but kinds.{kind} is missing`)
		end
	end
	if rules.kinds[clearKind] == nil and rules.kinds.clear == nil then
		table.insert(p, `kinds.{clearKind} (the clear kind) is missing`)
	end
	local L = Rules.frontSeconds(arules)
	if L ~= nil then
		local cross, blend = rules.fronts.crossSeconds, rules.fronts.blendSeconds
		if cross + blend > L then
			table.insert(p, `fronts: crossSeconds + blendSeconds = {cross + blend} exceeds the Almanac front ({L} s)`)
		end
		local active = W.activeSeconds
		if num(active) then
			if blend > active then
				table.insert(p, `fronts.blendSeconds {blend} exceeds the Almanac's activeSeconds {active}`)
			end
			if active + blend + cross > L then
				table.insert(p, `fronts: activeSeconds + blendSeconds + crossSeconds = {active + blend + cross} exceeds the front ({L} s)`)
			end
		end
	end
	local S = rules.surface
	if S.seasons ~= nil then
		local names = arules.seasons and arules.seasons.names or { "all" }
		for name in S.seasons do
			if not table.find(names, name) then
				table.insert(p, `surface.seasons.{name} is not an Almanac season ({table.concat(names, ", ")})`)
			end
		end
	end
	local phases: { [string]: boolean } = {}
	for _, ph in (arules.phases or {}) :: any do
		phases[ph.id] = true
	end
	for ph in phases do
		if S.sun[ph] == nil then
			table.insert(p, `surface.sun.{ph} is missing (an Almanac phase)`)
		end
	end
	table.sort(p)
	return p
end

return Rules
