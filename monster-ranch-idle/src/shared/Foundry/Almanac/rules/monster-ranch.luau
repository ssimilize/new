-- Almanac rules for Monster Ranch Idle, transcribed from the game (r2-integration, read
-- 2026-09-27):
--   src/shared/Config/Weather.luau       DayLength 1200 s, NightFraction 0.35 (night from hour
--                                         15.6), RollInterval 1200 s, Duration 240 s, 11 weathers
--   src/shared/Logic/WeatherRoll.luau    night-only / day-only / event-only gates, EventBoosts
--   src/shared/Config/Events.luau        festivals: dated windows plus reruns
-- The game rolls its weather on the server's own Random (ctx.Rng), so no calendar can predict
-- the exact kind it rolls: the Almanac's roll here is the same table and gates on a seeded
-- stream (same odds, different draws). Phase, phaseEndsAt, the roll clock and events agree
-- exactly (packages/Almanac/tests/Compat.spec.luau). No seasons in this game.
return {
	id = "monster-ranch",
	seed = 0,
	epoch = 0,
	dayLengthSeconds = 1200,
	phases = {
		{ id = "day", from = 0 },
		{ id = "night", from = 15.6 },
	},
	weather = {
		frontSeconds = 1200,
		activeSeconds = 240,
		rng = "contract",
		clearKind = "clear",
		names = {
			clear = "Clear",
			rain = "Rain",
			heatwave = "Heatwave",
			thunderstorm = "Thunderstorm",
			snow = "Snow",
			bloodmoon = "Blood Moon",
			starfall = "Starfall",
			lanternnight = "Lantern Night",
			pollenstorm = "Pollen Storm",
			beachday = "Beach Day",
			aurora = "Aurora",
		},
		tables = {
			all = {
				{ kind = "clear", weight = 55, intensity = { 0, 0 } },
				{ kind = "rain", weight = 15 },
				{ kind = "heatwave", weight = 10 },
				{ kind = "thunderstorm", weight = 8 },
				{ kind = "snow", weight = 6 },
				{ kind = "bloodmoon", weight = 3, phases = { "night" } },
				{ kind = "starfall", weight = 2.5 },
				{ kind = "lanternnight", weight = 8, event = "lunarlanterns", phases = { "night" } },
				{ kind = "pollenstorm", weight = 8, event = "springbloom", phases = { "day" } },
				{ kind = "beachday", weight = 8, event = "summersplash", phases = { "day" } },
				{ kind = "aurora", weight = 0.5 },
			},
		},
		boosts = {
			frostfall = { snow = 3 },
			harvestmoon = { bloodmoon = 3 },
			summersplash = { heatwave = 3 },
		},
	},
	events = {
		{
			id = "frostfall",
			name = "Frostfall",
			kind = "festival",
			windows = {
				{ startsAt = 1797087600, endsAt = 1799506800 },
				{ startsAt = 1829142000, endsAt = 1831561200 },
			},
		},
		{
			id = "lunarlanterns",
			name = "Lunar Lanterns",
			kind = "festival",
			windows = {
				{ startsAt = 1801926000, endsAt = 1803740400 },
				{ startsAt = 1833375600, endsAt = 1835190000 },
			},
		},
		{
			id = "springbloom",
			name = "Spring Bloom",
			kind = "festival",
			windows = { { startsAt = 1806764400, endsAt = 1808578800 } },
		},
		{
			id = "summersplash",
			name = "Summer Splash",
			kind = "festival",
			windows = { { startsAt = 1814626800, endsAt = 1818255600 } },
		},
		{
			id = "harvestmoon",
			name = "Harvest Moon",
			kind = "festival",
			windows = { { startsAt = 1822489200, endsAt = 1824908400 } },
		},
	},
}
