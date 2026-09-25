--[[
	WeatherRoll (S5): pure weather scheduling rules shared by the Weather system and the client.

	WeatherRoll.Weights(opts) -> { number }          -- aligned with Config.Weather.List
	WeatherRoll.Roll(rng, opts) -> weatherId
	  opts = { night = boolean, event = string? }    -- event = Config.Events.ActiveId(now)
	  Night-only weather (Blood Moon) has weight 0 during the day; event weather (`event = id`,
	  e.g. Lantern Night) only rolls while that event runs; an active event multiplies the
	  weights listed in Config.Weather.EventBoosts[event].

	WeatherRoll.Phase(now) -> (night, phaseEndsAt)   -- day/night cycle aligned to the unix clock
	WeatherRoll.NextRollAt(now) -> number            -- next multiple of RollInterval after `now`
	WeatherRoll.MutationChance(weather, elements, traitIds) -> chance per tick
]]

local Config = require(script.Parent.Parent.Config)

local Weather = Config.Weather
local Traits = Config.Traits

local WeatherRoll = {}

function WeatherRoll.Weights(opts: { night: boolean?, event: string? }?): { number }
	local o = opts or {}
	local boosts = if o.event then Weather.EventBoosts[o.event] else nil
	local weights = {}
	for i, w in Weather.List do
		local weight = w.weight
		if w.nightOnly and not o.night then
			weight = 0
		end
		if w.event and w.event ~= o.event then
			weight = 0
		end
		if boosts and boosts[w.id] then
			weight *= boosts[w.id]
		end
		weights[i] = weight
	end
	return weights
end

function WeatherRoll.Roll(rng, opts: { night: boolean?, event: string? }?): string
	return Weather.List[rng:Weighted(WeatherRoll.Weights(opts))].id
end

-- The last NightFraction of every DayLength cycle is night; cycles start at unix multiples of
-- DayLength so every server shares the same clock.
function WeatherRoll.Phase(now: number): (boolean, number)
	local length = Weather.DayLength
	local cycleStart = now - now % length
	local nightStart = cycleStart + math.floor(length * (1 - Weather.NightFraction))
	if now >= nightStart then
		return true, cycleStart + length
	end
	return false, nightStart
end

function WeatherRoll.NextRollAt(now: number): number
	local interval = Weather.RollInterval
	return (math.floor(now / interval) + 1) * interval
end

-- Chance for one monster on one tick of a weather event (the event chance split over Ticks).
function WeatherRoll.MutationChance(weather, elements: { string }, traitIds: { number }): number
	if not weather.mutation then
		return 0
	end
	local base = weather.chance or 0
	if weather.element and weather.matchChance and table.find(elements, weather.element) then
		base = weather.matchChance
	end
	local chance = base / Weather.Ticks * Traits.Product(traitIds, "mutationMult")
	if weather.starry then
		chance *= Traits.Product(traitIds, "starMutationMult")
	end
	return math.min(chance, 1)
end

return WeatherRoll
