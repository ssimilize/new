--[[
	Logic/Seasons (update 3.11 · Seasons & secrets): the season clock and the seasonal rules (tuning
	in Config/Seasons). Pure: the server, the client and the tests all read the same answers.

	  Seasons.At(now) -> { id, index 1..4, startsAt, endsAt }   the season `now` falls in: one per
	                                          Leaderboards week, turning over at the weekly reset
	  Seasons.Next(now) -> { id, index, startsAt, endsAt }      the season after that
	  Seasons.Def(id) -> Season?                                Config.Seasons.ById[id]
	  Seasons.InSeason(def, seasonId) -> boolean                a def with no `season` is always in
	  Seasons.GardenBonus(flavor, seasonId, yield) -> number    exact extra food for one harvest, a
	                                          fraction (0 if not the season's flavour; the server
	                                          pays whole food and carries the rest)
	  Seasons.AppealWeights(weights, favored?) -> weights       the favoured category × AppealBoost,
	                                          every weight rescaled so they still sum to the original
	                                          total (a perfect ranch stays at 100)
	  Seasons.ArriveText(seasonId) -> string                    "Winter has come to the ranch"
]]

local Config = require(script.Parent.Parent.Config)

local Rules = Config.Seasons

local Seasons = {}

local function window(week: number)
	local L = Config.Leaderboards
	local index = (week + Rules.WeekOffset) % #Rules.List + 1
	local def = Rules.List[index]
	return { id = def.id, index = index, startsAt = L.WeekEndsAt(week - 1), endsAt = L.WeekEndsAt(week) }
end

function Seasons.At(now: number)
	return window(Config.Leaderboards.Week(now))
end

function Seasons.Next(now: number)
	return window(Config.Leaderboards.Week(now) + 1)
end

function Seasons.Def(id: string?)
	return if type(id) == "string" then Rules.ById[id] else nil
end

function Seasons.InSeason(def, seasonId: string?): boolean
	if type(def) ~= "table" or def.season == nil then
		return true
	end
	return def.season == seasonId
end

function Seasons.GardenBonus(flavor: string, seasonId: string?, yield: number): number
	local def = Seasons.Def(seasonId)
	if not def or def.flavor ~= flavor or type(yield) ~= "number" or yield <= 0 then
		return 0
	end
	return yield * Rules.GardenBonus
end

function Seasons.AppealWeights(weights: { [string]: number }, favored: string?): { [string]: number }
	local out = table.clone(weights)
	if type(favored) ~= "string" or out[favored] == nil then
		return out
	end
	local total, boosted = 0, 0
	for id, w in weights do
		total += w
		boosted += if id == favored then w * Rules.AppealBoost else w
	end
	if boosted <= 0 then
		return out
	end
	for id, w in weights do
		out[id] = (if id == favored then w * Rules.AppealBoost else w) * total / boosted
	end
	return out
end

function Seasons.ArriveText(seasonId: string?): string
	local def = Seasons.Def(seasonId)
	return if def then def.arrive else ""
end

return Seasons
