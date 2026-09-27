-- SkyWeather rules for Guildhall Idle (read 2026-09-27 from src/systems/Weather):
--   Config.luau   kinds clear / rain / fog / snow (the Almanac's guildhall rules roll them);
--                 Terrain.Clouds cover per kind (clear 0.45; rain 0.75-0.9; fog 0.6-0.75; snow
--                 0.75-0.9) -> kinds.*.cloudCover, exactly; blendSeconds 8 (the client's ease)
--                 -> fronts.blendSeconds; one particle emitter on an anchor 30 studs above the
--                 camera focus (anchor.height) -> emitters (budget 1, not snapped); snow uses
--                 the light preset below 0.5 intensity (particles.snow.lightBelow); fog has no
--                 particles and no puddles.
--   README.md     no wind, no lightning, no wet ground today: those numbers are new here and
--                 are the look to tune in Studio (wind in studs/s at the diorama's scale).
-- Scale: a mesh door is 3.4 studs tall (profile world.meshDoor), about 2 m, so ~1.7 studs per
-- metre for the speed of sound. Bounds: 3 x 3 cells of 576 studs around the origin (profile
-- world.cell, plotCells offsets -1..1); pass the real valley bounds when adopting.
-- crossSeconds 0 (owner's call, 2026-09-27): today's instant, valley-wide switch, so the chip and
-- the rain agree to the second. 180 would make a front take 3 minutes to cross the valley.
return {
	id = "guildhall",
	seed = "guildhall-sky",
	studsPerMeter = 1.7,
	defaultBounds = { min = { x = -864, z = -864 }, max = { x = 864, z = 864 } },

	-- direction: the prevailing heading the wind blows TOWARD (degrees, 0 = +X, 90 = +Z); each
	-- front drifts +-drift from it (seeded). Gusts: value-noise cells gustScale studs across and
	-- gustSeconds long, drifting downwind at gustTravel studs/s.
	wind = { direction = 30, drift = 40, gustScale = 120, gustSeconds = 6, gustTravel = 10 },

	-- a front's line crosses the bounds in crossSeconds; each change blends over blendSeconds
	fronts = { crossSeconds = 0, blendSeconds = 8 },

	-- per Almanac kind: wind (studs/s) and gust (fraction added at full gust) as n or {lo, hi}
	-- lerped by the front's intensity; cloudCover likewise; precipitation (a key of the
	-- precipitation table) with rate = intensity * (rate or 1); dry = drying multiplier.
	-- fog (0..1, default 0) likewise: the snapshot's fog, which LT1 maps to Atmosphere
	-- Density / Haze. fog = {0.5, 1} is Weather/Config atmosphere.fog.haze {1.4, 2.6} above
	-- clear's 0.2, over 2.4 (the full fog). Rain and snow carry their own haze in the game's
	-- atmosphere table; they could say fog = {0.17, 0.42} / {0.25, 0.58} by the same measure,
	-- left 0 here so the snapshot's fog means the fog weather.
	kinds = {
		clear = { wind = 2, gust = 0.5, cloudCover = 0.45 },
		rain = { wind = { 4, 8 }, gust = { 0.5, 1 }, cloudCover = { 0.75, 0.9 }, precipitation = "rain" },
		fog = {
			wind = { 0.5, 1 },
			gust = 0.15,
			cloudCover = { 0.6, 0.75 },
			fog = { 0.5, 1 },
			dry = 0.5,
			note = "still, damp air: dries at half speed",
		},
		snow = { wind = { 3, 6 }, gust = { 0.4, 0.8 }, cloudCover = { 0.75, 0.9 }, precipitation = "snow" },
	},

	-- particlesAtFull: the emitter's rate at rate 1. Guildhall's presets carry their own rate,
	-- so here the plan's rate is a 0..1 multiplier. fallSpeed (studs/s) shifts the emitter
	-- upwind so particles land in their cell. lightBelow: use the light preset under that rate.
	precipitation = {
		rain = { particlesAtFull = 1, fallSpeed = 60, wets = true, lightBelow = 0 },
		snow = { particlesAtFull = 1, fallSpeed = 8, snows = true, lightBelow = 0.5 },
	},

	-- per second: wetting at rain rate 1; drying base / in full sun / per stud/s of wind;
	-- snowfall at rate 1; melt base / in full sun / in rain at rate 1; meltWet = wetting per unit
	-- melt. sun by Almanac phase. Seasons multiply drying and melting.
	surface = {
		lookbackSeconds = 28800,
		step = 180,
		wetPerSecond = 0.02,
		dry = 1 / 3000,
		drySun = 1 / 1500,
		dryWind = 0.00005,
		snowPerSecond = 1 / 600,
		melt = 0,
		meltSun = 1 / 3600,
		meltRain = 1 / 600,
		meltWet = 5,
		puddleFrom = 0.6,
		sun = { night = 0, dawn = 0.4, day = 1, dusk = 0.4 },
		seasons = {
			spring = { dry = 1, melt = 2 },
			summer = { dry = 1.6, melt = 4 },
			autumn = { dry = 0.7, melt = 1.5 },
			winter = { dry = 0.5, melt = 0.25 },
		},
	},

	-- no Guildhall kind is a storm today; the section is kept so one can be added as data
	lightning = {
		slotSeconds = 5,
		thunderSeconds = 4,
		hearRadius = 3000,
		flashRadius = 3000,
		flash = { { 0, 0.08, 1 }, { 0.16, 0.26, 0.65 } },
	},

	emitters = {
		spacing = 240,
		radius = 0,
		height = 30,
		snap = false,
		-- today's anchor sits exactly over the focus and its presets fall straight (no GlobalWind
		-- yet): no upwind shift. Turn on together with Workspace.GlobalWind.
		upwind = false,
		defaultBudget = 1,
		minRate = 0.01,
		qualityScale = { 1, 1, 1 },
	},

	-- the cloud-shadow offset drifts along the prevailing heading (studs/s), wrapped for a
	-- tiling texture
	-- sun occlusion: a cloud layer height studs up, value-noise cells cellSize studs across
	-- drifting with the shadow offset and reshaping over evolveSeconds; edge = the soft edge.
	-- sun: the path from the Almanac hour (Lighting.ClockTime = the hour here): up from rise to
	-- set, peak degrees at midday (DayNight Config sky.latitude 30 -> 90 - 30), rising toward
	-- heading (degrees, 0 = +X, 90 = +Z; TO CONFIRM against Lighting:GetSunDirection()). LT1
	-- passes the real sun direction to snapshot(t, pos, sun) and this path is then unused.
	clouds = {
		speed = 6,
		variation = 0.5,
		period = 600,
		wrap = 2048,
		height = 800,
		cellSize = 500,
		evolveSeconds = 180,
		edge = 0.1,
		sun = { rise = 6, set = 18, peak = 60, heading = 0, fade = 6 },
	},
}
