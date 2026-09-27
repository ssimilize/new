-- Wildlife table for Monster Ranch Idle, transcribed from the game (r2-integration, read
-- 2026-09-27):
--   src/shared/Config/Ambience.luau        Ambience.Critters (caps, radii, colours, scare) and
--                                           Ambience.Lights on / off (the day/night curve)
--   src/shared/Logic/Ambience.luau         Night, Cap, Nearest, Scared
--   src/client/Controllers/Critters.luau   spots, drift curves, fish circles, bird scatter
-- Quality: the Ranch's lowGraphics is quality 1 (max = maxLow); full graphics is 2 and 3 (max).
-- Compatibility: packages/Wildlife/tests/Compat.spec.luau checks these numbers and rules against
-- the game's own config and Logic when the game checkout is present.
-- Extensions over today's controller: fish jump now and then and when something passes the
-- fountain; birds that scatter re-land on a free perch (never a taken one) or leave and come back
-- 6-12 s later to the same perch. Reef (beach / abyss water) has no spots in the game yet.
return {
	id = "monster-ranch",
	seed = "monster-ranch",
	budgetKind = "critters",
	dayNight = { mode = "curve", on = { 16.5, 18.5 }, off = { 5.5, 7.5 } },
	kinds = {
		butterfly = {
			behaviour = "drift",
			on = { "flower" },
			phases = { "day" },
			cost = 2,
			max = { 0, 8, 8 },
			radius = 80,
			fade = 0,
			maxRain = math.huge,
			drift = { amp = 2.5, height = 1.2, bob = 0.6, freq = { 0.9, 1.7, 0.7 }, phase = { 1, 1, 1.3 } },
			colors = { "#FFB547", "#FF8FC8", "#8FD3FF", "#FFF07A", "#C9A2FF" },
			mesh = "critter_butterfly",
		},
		firefly = {
			behaviour = "drift",
			on = { "flower" },
			phases = { "night" },
			cost = 1,
			max = { 5, 16, 16 },
			radius = 70,
			fade = 0,
			glow = true,
			maxRain = math.huge,
			drift = { amp = 3, height = 1.6, bob = 1.1, freq = { 0.31, 0.53, 0.27 }, phase = { 1, 2, 1.7 } },
			colors = { "#E8FF7A" },
			anims = { drift = "glow" },
		},
		bird = {
			behaviour = "flock",
			perchOn = { "perch" },
			roostOn = {},
			phases = { "day" },
			cost = 5,
			max = { 0, 4, 4 },
			radius = 90,
			flock = { 1, 1 },
			bucket = 600,
			chance = 1,
			range = 90,
			arrive = { 0, 0 },
			perch = { 0.9, 0.95 },
			scare = 12,
			scareSpeed = 10,
			fleeDistance = 25,
			returnAfter = { 6, 12 },
			maxRain = math.huge,
			colors = { "#6E8FD6", "#D96A4A", "#8A6A4E", "#F2D35B" },
			mesh = "critter_bird",
		},
		fish = {
			behaviour = "swim",
			on = { "water" },
			phases = {},
			cost = 2,
			max = { 0, 3, 3 },
			radius = 120,
			edge = 1.5,
			depth = 0.05,
			jump = { every = 25, chance = 0.25, seconds = 0.9, height = 2, length = 2.5 },
			colors = { "#FF8A3D", "#FFFFFF", "#FFC23D" },
			mesh = "critter_fish",
		},
		reef_fish = {
			behaviour = "swim",
			on = { "reef" },
			phases = {},
			cost = 2,
			max = { 0, 4, 6 },
			radius = 100,
			jump = { every = 30, chance = 0.15, seconds = 0.8, height = 1.5, length = 2 },
			colors = { "#3DD6FF", "#FF5FA2", "#FFE14D" },
			mesh = "critter_fish",
		},
	},
	biomes = {
		meadow = {
			{ kind = "butterfly", count = 1 },
			{ kind = "firefly", count = 1 },
			{ kind = "bird", count = 1 },
		},
		town = {
			{ kind = "bird", count = 1 },
			{ kind = "butterfly", count = 1 },
			{ kind = "firefly", count = 1 },
		},
		water = { { kind = "fish", count = 3 } },
		forest = { { kind = "firefly", count = 1 }, { kind = "bird", count = 1 } },
		reef = { { kind = "reef_fish", count = { 2, 4 } } },
	},
	-- `foundry wildlife compat --game monster-ranch` loads these (relative to the profile's
	-- paths.source) and runs tests/RanchCompat.luau on them.
	compat = { module = "RanchCompat", config = "shared/Config/Ambience.luau", logic = "shared/Logic/Ambience.luau" },
	-- How the game's controller builds spots (read by ADOPT.md and `foundry wildlife`; the
	-- package itself only sees the spots list).
	sources = {
		{ from = "SceneryIndex flowers, sunflowers (top of the part)", type = "flower", biome = "meadow" },
		{ from = "World.Plots Floor parts with PenIndex (top)", type = "flower", biome = "meadow" },
		{ from = "SceneryIndex birdhouse (top)", type = "perch", biome = "town" },
		{ from = "World.Plots parts named Rail* (top)", type = "perch", biome = "meadow" },
		{ from = "World.Hub.Fountain.Water: surface = Position.Y + Size.X / 2 (or the Basin's), radius = Size.Y / 2", type = "water", biome = "water" },
	},
}
