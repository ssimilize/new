--[[
	Server weather. Every `RollInterval` seconds the server rolls a weather from `List`
	by weight; non-clear weather lasts `Duration` seconds. Monsters standing in a pen roll
	for the mutation `Ticks` times per event; the per-event chance is split evenly across ticks.
]]

local Weather = {}

Weather.RollInterval = 20 * 60
Weather.Duration = 4 * 60
Weather.Ticks = 8
Weather.DayLength = 20 * 60 -- full day/night cycle
Weather.NightFraction = 0.35 -- last 35% of each cycle is night

Weather.List = {
	{ id = "clear", name = "Clear", weight = 55 },
	{
		id = "rain",
		name = "Rain",
		weight = 15,
		mutation = "soaked",
		element = "tide",
		chance = 0.04,
		matchChance = 0.12,
		effects = { gardenSpeed = 2 },
	},
	{
		id = "heatwave",
		name = "Heatwave",
		weight = 10,
		mutation = "scorched",
		element = "ember",
		chance = 0.04,
		matchChance = 0.12,
		effects = { hatchSpeed = 1.25 },
	},
	{
		id = "thunderstorm",
		name = "Thunderstorm",
		weight = 8,
		mutation = "charged",
		element = "spark",
		chance = 0.04,
		matchChance = 0.12,
		effects = { bossDamage = 1.1 },
	},
	{ id = "snow", name = "Snow", weight = 6, mutation = "frosted", element = "stone", chance = 0.04, matchChance = 0.12, effects = {} },
	{
		id = "bloodmoon",
		name = "Blood Moon",
		weight = 3,
		nightOnly = true,
		mutation = "shadow",
		element = "gloom",
		chance = 0.03,
		matchChance = 0.09,
		effects = { gloomAtk = 1.2 },
	},
	{
		id = "starfall",
		name = "Starfall",
		weight = 2.5,
		mutation = "starstruck",
		chance = 0.05,
		effects = { freeEgg = "grove" },
		starry = true,
	},
	-- Lunar Lanterns (update 1.2): only rolls at night while the event runs.
	{
		id = "lanternnight",
		name = "Lantern Night",
		weight = 8,
		event = "lunarlanterns",
		nightOnly = true,
		mutation = "glow",
		chance = 0.06,
		effects = {},
	},
	{
		id = "aurora",
		name = "Aurora",
		weight = 0.5,
		mutation = "prismatic",
		chance = 0.01,
		effects = {},
		starry = true,
		broadcast = "global",
		notForSale = true,
	},
}

Weather.ById = {}
for _, w in Weather.List do
	Weather.ById[w.id] = w
end

-- Weather that can be summoned by a Robux totem (see Monetization.Products).
Weather.Totems = { rain = true, thunderstorm = true, starfall = true }

-- Event overrides: while an event is active its weather weights are multiplied.
Weather.EventBoosts = {
	frostfall = { snow = 3 },
	harvestmoon = { bloodmoon = 3 },
}

return Weather
