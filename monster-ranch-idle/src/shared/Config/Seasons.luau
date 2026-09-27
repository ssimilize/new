--[[
	Ranch Seasons (update 3.11 · Seasons & secrets): a 28-day cycle of spring, summer, autumn and
	winter, one season per Leaderboards week (Config.Leaderboards.Week), so a season turns over at
	the Saturday 15:00 UTC weekly reset. A pure function of time (Logic/Seasons.At): every server
	and every client agrees without saving anything. The week containing 2026-09-27 is autumn.

	Season: { id, name, color (UI accent), ground (plot grass tint), flavor (Config.Food id: its
	          Feed Garden harvests give GardenBonus more), appeal (Config.Tourists category the
	          tourists favour: counts AppealBoost times, renormalised), particle (Controllers/Seasons),
	          arrive (the Welcome Back line / toast when it starts) }

	What each season changes (rules in Logic/Seasons):
	  Pond     Config.Fishing fish with `season` bite only in their season (Logic/Fishing.Roll)
	  Kitchen  Config.Kitchen recipes with `season` cook only in their season and need one of
	           their `seasonFish`
	  Shop     Config.Decor pieces with `season` are sold only in their season (owned ones stay)
	  Weekly   the goal season_fish_3 (catch 3 fish of the season)
]]

local Seasons = {}

-- Week 0 (Config.Leaderboards.WeekAnchor, 19 Sep 2026) is summer; the week of 27 Sep is autumn.
Seasons.WeekOffset = 1

Seasons.GardenBonus = 0.25 -- extra share of a harvest of the season's flavour
Seasons.AppealBoost = 1.25 -- the favoured Appeal category's weight multiplier (then renormalised)
Seasons.TickSeconds = 5 -- how often the server looks for the turnover

Seasons.List = {
	{
		id = "spring",
		name = "Spring",
		color = "#F28AC0",
		ground = "#8FD46A",
		flavor = "sweet",
		appeal = "decor",
		particle = "petals",
		arrive = "Spring has come to the ranch",
	},
	{
		id = "summer",
		name = "Summer",
		color = "#F2B233",
		ground = "#7CC456",
		flavor = "sour",
		appeal = "pens",
		particle = "fireflies",
		arrive = "Summer has come to the ranch",
	},
	{
		id = "autumn",
		name = "Autumn",
		color = "#E0782E",
		ground = "#B7B25A",
		flavor = "savory",
		appeal = "variety",
		particle = "leaves",
		arrive = "Autumn has come to the ranch",
	},
	{
		id = "winter",
		name = "Winter",
		color = "#7FC4F0",
		ground = "#DCEBF2",
		flavor = "spicy",
		appeal = "rarity",
		particle = "snow",
		arrive = "Winter has come to the ranch",
	},
}

Seasons.ById = {}
Seasons.Ids = {}
for i, s in Seasons.List do
	s.index = i
	Seasons.ById[s.id] = s
	table.insert(Seasons.Ids, s.id)
end

return Seasons
