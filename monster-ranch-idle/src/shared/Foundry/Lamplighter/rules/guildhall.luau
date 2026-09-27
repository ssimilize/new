-- Lamplighter rules for Guildhall Idle, transcribed from the game (read 2026-09-27):
--   src/systems/BuildingLife/Config.luau  windows: lit "#FFC86B", fadeSeconds 1.6, schedules
--                                          default / home (sleep, wake) / social_hub / arcane /
--                                          civic, order social_hub > home > arcane > civic;
--                                          door lamps on {17.5, 18.4} off {5.8, 6.8}; flicker
--                                          amount 0.18 rate 3.1; door-lamp light "#FFB866"
--                                          brightness 1.1 range 11; range 240
--   src/systems/BuildingLife/Logic.luau   windowsLit / pickIn / salt / flicker (Windows.luau and
--                                          the "breathe" profile carry them over unchanged)
--   src/systems/DayNight/Config.luau      lamps.max low 8 / medium 24 / high 48 (ClientFx
--                                          presets whose light part needs medium: 0 / 24 / 48
--                                          real lights) + BuildingLife door lights 0 / 4 / 8 =
--                                          lights 0 / 28 / 56; maxDistance 260; the dusk curve
--                                          18-19 / 5-6.5 with a per-uid threshold (forges)
--   packages/Life/rules/guildhall.luau    the lamplighter role: from hour 18, a tour of up to 12
--                                          lamps, 3 s each, home within 300 s (+ 20 s leave lag)
-- New here (not in the game today): ground light decals, shadow picks, torches and braziers,
-- per-pane staggered windows. Guildhall has no shadowed practicals today: shadows stay 0 at every
-- quality until the owner opts in (a visible change).
return {
	id = "guildhall",
	seed = 0,
	budgetKind = "activeLights",
	shadowBudgetKind = "shadowLights",
	decalBudgetKind = "lightDecals",
	lights = { 0, 28, 56 },
	shadows = { 0, 0, 0 },
	decals = { 6, 12, 24 },
	radius = 260,
	shadowRadius = 80,
	decalRadius = 200,
	priority = "weighted",
	-- the owner's call (2026-09-27): posts and lanterns on the lamplighter's tour hold a real light
	-- before any window or door lamp (a far tour stop lit at the 56 cap otherwise stayed glow-only)
	tourFirst = true,
	offscreen = 0.25,
	screenMargin = 10,
	hysteresis = 0.25,
	lamps = { mode = "switch", on = { 17.5, 18.4 }, off = { 5.8, 6.8 }, fade = 1.6 },
	lamplighter = { role = "lamplighter", activity = "light", from = 18, seconds = 420, late = { 18.6, 19.4 } },
	kinds = {
		-- decor tagged `lamp`: the lamplighter lights these
		lamppost = { colour = "#FFB866", brightness = 1.4, range = 16, lamplighter = true },
		-- BuildingLife door lamps: lit per building at a seeded hour, not by the lamplighter
		lantern = { colour = "#FFB866", brightness = 1.1, range = 11, lamplighter = false },
		window = { colour = "#FFC86B", brightness = 0.8, range = 8, flicker = "breathe" },
		-- smithy / kiln: lit as DayNight lit their glow, the dusk curve past a per-uid threshold
		-- t in 0.05..0.95: on at 18 + t, off at 6.5 - 1.5 t (the game passes onSeed / offSeed)
		forge = { switch = "night", on = { 18.05, 18.95 }, off = { 5.075, 6.425 }, lamplighter = false },
	},
	windows = {
		order = { "social_hub", "home", "arcane", "civic" },
		schedules = {
			default = { on = { 18.0, 19.3 }, off = { 5.4, 6.6 } },
			home = { on = { 17.9, 19.0 }, sleep = { 22.5, 1.5 }, wake = { 4.6, 5.6 }, off = { 6.0, 7.0 } },
			social_hub = { on = { 17.6, 18.3 }, off = { 5.8, 6.6 } },
			arcane = { on = { 18.4, 20.0 }, off = { 4.8, 5.8 } },
			civic = { on = { 17.8, 18.8 }, off = { 5.6, 6.4 } },
		},
		stagger = { 0, 12 },
		fade = 1.6,
	},
}
