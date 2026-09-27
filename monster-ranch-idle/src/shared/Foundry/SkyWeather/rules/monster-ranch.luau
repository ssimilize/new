-- SkyWeather rules for Monster Ranch Idle (r2-integration, read 2026-09-27):
--   src/shared/Config/Weather.luau        11 weathers (the Almanac's monster-ranch rules roll
--                                         them), Duration 240 s of each 1200 s roll
--   src/client/Controllers/Weather.luau   PROFILES particle rates at full quality: rain 450,
--                                         thunderstorm rain 650, snow 160, starfall stars 14,
--                                         lanternnight stars 8, pollenstorm pollen 120
--                                         -> precipitation.*.particlesAtFull x kinds.*.rate;
--                                         lowGraphics x0.35 -> emitters.qualityScale[1]; one
--                                         emitter part 32 studs above the camera -> emitters;
--                                         BLEND_TIME 1.6 s (settles in ~5 s) -> blendSeconds 5;
--                                         lightning: two pulses (1.0 for 0.08 s, 0.65 from 0.16
--                                         to 0.26 s) every 4 + U*9 s while a storm is in ->
--                                         lightning.flash, thunderstorm 7 strikes/min
--                                         (60 / 8.5 s mean gap)
-- New here (no counterpart in the game): wind, cloud cover, wet ground, snow cover, strike
-- positions and thunder delays. Scale: Roblox avatars, 1 stud = 0.28 m (3.57 studs per metre).
-- Bounds: TO CONFIRM with the Ranch session (the profile has no world extent); +-600 studs
-- matches the streaming target radius.
-- crossSeconds 0 (owner's call, 2026-09-27): today's instant sky; the client follows the server's
-- roll by Almanac override. 60 would roll a storm over the ranch in a minute.
return {
	id = "monster-ranch",
	seed = "monster-ranch-sky",
	studsPerMeter = 3.57,
	defaultBounds = { min = { x = -600, z = -600 }, max = { x = 600, z = 600 } },

	wind = { direction = 200, drift = 50, gustScale = 90, gustSeconds = 5, gustTravel = 14 },

	fronts = { crossSeconds = 0, blendSeconds = 5 },

	kinds = {
		clear = { wind = 3, gust = 0.4, cloudCover = 0.3 },
		rain = { wind = 6, gust = 0.7, cloudCover = 0.8, precipitation = "rain", rate = 450 / 650 },
		heatwave = { wind = 1.5, gust = 0.2, cloudCover = 0.05, dry = 2.5 },
		thunderstorm = {
			wind = 12,
			gust = 1.2,
			cloudCover = 0.95,
			precipitation = "rain",
			rate = 1,
			storm = { strikesPerMinute = 7 },
		},
		snow = { wind = 4, gust = 0.6, cloudCover = 0.8, precipitation = "snow" },
		bloodmoon = { wind = 2, gust = 0.3, cloudCover = 0.2 },
		starfall = { wind = 2, gust = 0.3, cloudCover = 0.05, precipitation = "stars" },
		lanternnight = { wind = 1, gust = 0.2, cloudCover = 0.1, precipitation = "stars", rate = 8 / 14 },
		pollenstorm = { wind = 7, gust = 0.9, cloudCover = 0.3, precipitation = "pollen" },
		beachday = { wind = 4, gust = 0.5, cloudCover = 0.1, dry = 1.8 },
		aurora = { wind = 1.5, gust = 0.2, cloudCover = 0.05 },
	},

	precipitation = {
		rain = { particlesAtFull = 650, fallSpeed = 60, wets = true },
		snow = { particlesAtFull = 160, fallSpeed = 8, snows = true },
		stars = { particlesAtFull = 14, fallSpeed = 30 },
		pollen = { particlesAtFull = 120, fallSpeed = 4 },
	},

	surface = {
		lookbackSeconds = 10800,
		step = 120,
		wetPerSecond = 0.02,
		dry = 1 / 2400,
		drySun = 1 / 1200,
		dryWind = 0.00005,
		snowPerSecond = 1 / 300,
		melt = 1 / 3600,
		meltSun = 1 / 1800,
		meltRain = 1 / 300,
		meltWet = 3,
		puddleFrom = 0.6,
		sun = { day = 1, night = 0 },
	},

	lightning = {
		slotSeconds = 5,
		thunderSeconds = 4,
		hearRadius = 4000,
		flashRadius = 4000,
		flash = { { 0, 0.08, 1 }, { 0.16, 0.26, 0.65 } },
	},

	emitters = {
		spacing = 200,
		radius = 0,
		height = 32,
		snap = false,
		defaultBudget = 1,
		minRate = 0.01,
		qualityScale = { 0.35, 1, 1 },
	},

	-- sun occlusion (see rules/guildhall.luau). No Monster Ranch kind is foggy (no kinds.*.fog),
	-- so the snapshot's fog is always 0. sun: the Almanac day phase runs from hour 0 to 15.6,
	-- so the sun is up exactly then; peak and heading TO CONFIRM with the Ranch session (or
	-- pass Lighting:GetSunDirection() to snapshot).
	clouds = {
		speed = 5,
		variation = 0.4,
		period = 900,
		wrap = 2048,
		height = 700,
		cellSize = 450,
		evolveSeconds = 150,
		edge = 0.1,
		sun = { rise = 0, set = 15.6, peak = 60, heading = 0, fade = 6 },
	},
}
