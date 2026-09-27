--[[
	Logic/Observatory (update 3.12 · Honey & stars): pure rules of the Observatory (Config/Observatory),
	used by Systems/Observatory (the authority) and the Observatory screen.

	  Observatory.Night(now) -> (isNight, nightId, changesAt)   the Weather day cycle: nightId is the
	                                          cycle index (now // DayLength, cycles start at unix
	                                          multiples of DayLength like WeatherRoll.Phase); changesAt
	                                          = when night falls (by day) or dawn breaks (by night)
	  Observatory.Seed(userId, night, n, secret) -> number   a sighting's seed
	  Observatory.Sky(seed, count) -> { stars = { { x, y } }, order = { number } }
	                                          `count` stars in the unit square (Margin from the edge,
	                                          Spacing apart as far as it fits) and the order to tap them
	  Observatory.Check(order, taps) -> (ok, why?)   taps = { { star, t } }: every star of `order` in
	                                          turn, t increasing by at least MinGap, first t >= 0, last
	                                          t <= TimeLimit. why = "order" | "fast" | "slow"
	  Observatory.Progress(charts, id) -> number     observations on a chart (0..Observations)
	  Observatory.Done(charts, id) -> boolean
	  Observatory.Perk(charts, key) -> number        the capped sum of finished charts' perks
	  Observatory.Available(def, seasonId) -> boolean   a chart with no season, or in its season
	  Observatory.PerkText(key, value) -> string     "Eggs hatch 2% faster"
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)
local WeatherRoll = require(script.Parent.WeatherRoll)

local Cfg = Config.Observatory

local Observatory = {}

function Observatory.Night(now: number): (boolean, number, number)
	local night, changesAt = WeatherRoll.Phase(now)
	return night, now // Config.Weather.DayLength, changesAt
end

function Observatory.Seed(userId: number, night: number, n: number, secret: number): number
	return Rng.seed("observatory", userId, night, n, secret)
end

function Observatory.Sky(seed: number, count: number)
	local rng = Rng.new(seed)
	local stars = {}
	local span = 1 - Cfg.Margin * 2
	for _ = 1, count do
		local x, y
		-- A few tries for a spot clear of the other stars; the last try stands either way.
		for _ = 1, 40 do
			x = math.floor((Cfg.Margin + rng:Next() * span) * 1000 + 0.5) / 1000
			y = math.floor((Cfg.Margin + rng:Next() * span) * 1000 + 0.5) / 1000
			local clear = true
			for _, s in stars do
				if (s.x - x) ^ 2 + (s.y - y) ^ 2 < Cfg.Spacing ^ 2 then
					clear = false
					break
				end
			end
			if clear then
				break
			end
		end
		table.insert(stars, { x = x, y = y })
	end
	local order = {}
	for i = 1, count do
		order[i] = i
	end
	for i = count, 2, -1 do
		local j = rng:Int(1, i)
		order[i], order[j] = order[j], order[i]
	end
	return { stars = stars, order = order }
end

function Observatory.Check(order: { number }, taps): (boolean, string?)
	if type(taps) ~= "table" or #taps ~= #order then
		return false, "order"
	end
	local last = nil
	for i, tap in taps do
		if type(tap) ~= "table" or tap.star ~= order[i] then
			return false, "order"
		end
		local t = tap.t
		if type(t) ~= "number" or t ~= t or t < 0 then
			return false, "fast"
		end
		if last and t - last < Cfg.MinGap - 1e-6 then
			return false, "fast"
		end
		last = t
	end
	if last and last > Cfg.TimeLimit then
		return false, "slow"
	end
	return true, nil
end

function Observatory.Progress(charts, id: string): number
	local n = type(charts) == "table" and tonumber(charts[id]) or 0
	return math.clamp(math.floor(n or 0), 0, Cfg.Observations)
end

function Observatory.Done(charts, id: string): boolean
	return Observatory.Progress(charts, id) >= Cfg.Observations
end

function Observatory.Perk(charts, key: string): number
	local cap = Cfg.PerkCaps[key]
	if not cap then
		return 0
	end
	local total = 0
	for _, c in Cfg.Charts do
		if c.perk.key == key and Observatory.Done(charts, c.id) then
			total += c.perk.value
		end
	end
	return math.min(total, cap)
end

function Observatory.Available(def, seasonId: string?): boolean
	return def.season == nil or def.season == seasonId
end

local function pct(value: number): string
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

function Observatory.PerkText(key: string, value: number): string
	if key == "egg_speed" then
		return string.format("Eggs hatch %s faster", pct(value))
	elseif key == "income" then
		return string.format("%s more ranch income", pct(value))
	elseif key == "rare_fish" then
		return string.format("%s better odds of rare fish", pct(value))
	elseif key == "loot" then
		return string.format("%s more expedition loot", pct(value))
	elseif key == "dojo_time" then
		return string.format("Dojo training %s quicker", pct(value))
	elseif key == "hive_hours" then
		return string.format("Hive hours +%d", math.floor(value + 0.5))
	elseif key == "appeal" then
		return string.format("Ranch appeal +%d", math.floor(value + 0.5))
	end
	return "Star perk"
end

return Observatory
