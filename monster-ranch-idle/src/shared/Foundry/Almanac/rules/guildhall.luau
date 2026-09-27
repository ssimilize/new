-- Almanac rules for Guildhall Idle, transcribed from the game (read 2026-09-27):
--   src/systems/DayNight/Config.luau    secondsPerHour 60 (a 24-minute day), phases dawn [5,8),
--                                        day [8,18), dusk [18,20), night [20,5)
--   src/systems/Weather/Config.luau     season = floor(now / 604800) % 4, 30-minute windows,
--                                        per-season tables, valley "valley", intensity to 0.01
--   src/systems/Weather/Server.luau     seed = kernel.Contracts.hash("weather", valley, window)
--   src/kernel/Contracts.luau           rng = xorshift32 over fmix32(seed): rng "xorshift32"
--   src/systems/WanderingMerchant/Config.luau  arrives every 14400 s, stays 3600 s, offset 0
-- Compatibility: packages/Almanac/tests/Compat.spec.luau checks sampled times against a
-- transcription of each formula. One Almanac is one valley: set `region` to the valley id.
return {
	id = "guildhall",
	seed = 0,
	epoch = 0,
	dayLengthSeconds = 1440,
	region = "valley",
	phases = {
		{ id = "night", from = 0 },
		{ id = "dawn", from = 5 },
		{ id = "day", from = 8 },
		{ id = "dusk", from = 18 },
		{ id = "night", from = 20 },
	},
	seasons = {
		periodSeconds = 604800,
		names = { "spring", "summer", "autumn", "winter" },
		labels = { "Spring", "Summer", "Autumn", "Winter" },
	},
	weather = {
		frontSeconds = 1800,
		rng = "xorshift32",
		seedParts = { "weather", "$region" },
		intensityDecimals = 2,
		clearKind = "clear",
		names = { clear = "Clear", rain = "Rain", fog = "Fog", snow = "Snow" },
		bias = {},
		tables = {
			spring = {
				{ kind = "clear", weight = 45, intensity = { 0, 0 } },
				{ kind = "rain", weight = 35, intensity = { 0.3, 0.8 } },
				{ kind = "fog", weight = 20, intensity = { 0.3, 0.7 } },
			},
			summer = {
				{ kind = "clear", weight = 70, intensity = { 0, 0 } },
				{ kind = "rain", weight = 20, intensity = { 0.4, 1 } },
				{ kind = "fog", weight = 10, intensity = { 0.2, 0.5 } },
			},
			autumn = {
				{ kind = "clear", weight = 35, intensity = { 0, 0 } },
				{ kind = "rain", weight = 35, intensity = { 0.3, 0.9 } },
				{ kind = "fog", weight = 30, intensity = { 0.4, 1 } },
			},
			winter = {
				{ kind = "clear", weight = 35, intensity = { 0, 0 } },
				{ kind = "snow", weight = 45, intensity = { 0.3, 1 } },
				{ kind = "fog", weight = 20, intensity = { 0.3, 0.8 } },
			},
		},
	},
	events = {
		{
			id = "merchant",
			name = "Wandering Merchant",
			kind = "market",
			everySeconds = 14400,
			lengthSeconds = 3600,
			offsetSeconds = 0,
		},
	},
}
