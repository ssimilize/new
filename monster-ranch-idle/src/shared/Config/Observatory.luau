--[[
	Observatory & Star Charts (update 3.12 · Honey & stars). A small domed observatory in the
	north strip of every plot (Config.World.Observatory) with a "Stargaze" prompt on its telescope
	that opens the Observatory screen. From Ranch Level 19 (Unlocks "observatory").

	Night only: the Weather day cycle (Logic/WeatherRoll.Phase; Config.Weather.DayLength). A night's
	id is its day-cycle index (Logic/Observatory.Night).

	A sighting: a seeded tap minigame. The server deals `stars` stars in a unit square (seed
	(userId, night, n, the player's private secret)) and the order to trace them; the player taps
	them in that order within TimeLimit seconds, at least MinGap seconds apart. Sightings a night per
	player; a sighting is used when it starts, success or not. A success adds one observation to its
	chart; Observations finish a chart, which grants its perk for good and publishes StarCharted.

	Charts: `{ id, name, season?, stars, perk = { key, value } }`. A seasonal chart can only be
	started in its season (Logic/Seasons.At(now).id); its perk, once earned, stays all year.

	Perk keys (Observatory:Perk(player, key) = the capped sum of finished charts' perks):
	  egg_speed   fraction  incubator speed (an Eggs speed provider)
	  income      fraction  ranch income (a Ranch rate modifier)
	  rare_fish   fraction  added to the Fishing bonus (rarer bites, better extras)
	  loot        fraction  expedition loot (an Expeditions loot modifier)
	  dojo_time   fraction  off every Dojo training time
	  hive_hours  hours     extra Apiary hive hours (read by the Apiary)
	  appeal      points    ranch appeal (a Tourists appeal bonus)
]]

local Observatory = {}

Observatory.Unlock = "observatory"
Observatory.Source = "observatory"

Observatory.Sightings = 3 -- a night per player
Observatory.Observations = 3 -- successful sightings that finish a chart
Observatory.TimeLimit = 12 -- seconds from the start of a sighting to its last tap
Observatory.MinGap = 0.12 -- seconds between two taps (quicker is not a human)
Observatory.GraceSeconds = 1 -- the taps' own clock may run this far ahead of the server's
Observatory.LateSeconds = 4 -- a submit this long after TimeLimit is refused
Observatory.Margin = 0.1 -- stars keep this far from the edge of the unit square
Observatory.Spacing = 0.2 -- and this far from each other

Observatory.PerkKeys = { "egg_speed", "income", "rare_fish", "loot", "dojo_time", "hive_hours", "appeal" }

-- The most each perk key can add up to, all charts together.
Observatory.PerkCaps = {
	egg_speed = 0.04,
	income = 0.04,
	rare_fish = 0.06,
	loot = 0.04,
	dojo_time = 0.05,
	hive_hours = 2,
	appeal = 2,
}

Observatory.Charts = {
	{ id = "ladle", name = "The Great Ladle", stars = 5, perk = { key = "egg_speed", value = 0.02 } },
	{ id = "lantern", name = "The Lantern", stars = 5, perk = { key = "income", value = 0.02 } },
	{ id = "fish", name = "The Silver Fish", stars = 5, perk = { key = "rare_fish", value = 0.03 } },
	{ id = "compass", name = "The Compass", stars = 5, perk = { key = "loot", value = 0.02 } },
	{ id = "kettle", name = "The Kettle", stars = 6, perk = { key = "dojo_time", value = 0.05 } },
	{ id = "beehive", name = "The Beehive", stars = 6, perk = { key = "hive_hours", value = 1 } },
	{ id = "crown", name = "The Crown", stars = 6, perk = { key = "appeal", value = 2 } },
	{ id = "twin_eggs", name = "The Twin Eggs", stars = 6, perk = { key = "egg_speed", value = 0.02 } },
	{ id = "blossom", name = "The Blossom", season = "spring", stars = 7, perk = { key = "income", value = 0.02 } },
	{ id = "leaping_carp", name = "The Leaping Carp", season = "summer", stars = 7, perk = { key = "rare_fish", value = 0.03 } },
	{ id = "acorn", name = "The Acorn", season = "autumn", stars = 7, perk = { key = "loot", value = 0.02 } },
	{ id = "sleeping_bear", name = "The Sleeping Bear", season = "winter", stars = 7, perk = { key = "hive_hours", value = 1 } },
}

Observatory.ById = {}
Observatory.Ids = {}
for i, c in Observatory.Charts do
	assert(Observatory.ById[c.id] == nil, "[Config.Observatory] duplicate chart " .. c.id)
	assert(Observatory.PerkCaps[c.perk.key] ~= nil, "[Config.Observatory] unknown perk " .. c.perk.key)
	c.order = i
	Observatory.ById[c.id] = c
	table.insert(Observatory.Ids, c.id)
end

Observatory.MaxStars = 7

return Observatory
