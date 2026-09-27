-- Lamplighter rules for Monster Ranch Idle, transcribed from the game (r2-integration worktree,
-- read 2026-09-27):
--   src/shared/Config/Ambience.luau      Ambience.Lights: on {16.5, 18.5}, off {5.5, 7.5},
--                                         radius 220, max 12, maxLow 5, the five kinds (colour,
--                                         brightness, range, window angle 70, campfire flicker 0.25)
--   src/shared/Logic/Ambience.luau       Night (smoothstep through dusk and dawn), Nearest
--                                         (flat X/Z distance, radius inclusive, nearest first)
--   src/client/Controllers/Lamplight.luau  brightness = k.brightness * night, campfire flicker
--                                         1 + f * (sin(c 11 + s) 0.5 + sin(c 23.7 + s 3) 0.3 +
--                                         sin(c 5.3) 0.2), s = source index * 1.7; no shadows;
--                                         nothing lit while night <= 0.001
-- Reproduced exactly (tests/Compat.spec.luau): which sources are lit and their brightness, equal-
-- distance ties at the cap included (squaredNearest; fixture ids must sort in the game's source order).
-- Quality 1 = lowGraphics (maxLow). The ranch has no decals, no shadows and no hysteresis, and
-- its "window" is a single SurfaceLight on the front face, not lit panes.
return {
	id = "monster-ranch",
	seed = 0,
	lights = { 5, 12, 12 },
	shadows = { 0, 0, 0 },
	decals = { 0, 0, 0 },
	radius = 220,
	shadowRadius = 0,
	decalRadius = 0,
	priority = "nearest",
	squaredNearest = true, -- Logic.Nearest exactly: squared distance, source order into table.sort, no id tie-break
	flat = true,
	offscreen = 1,
	hysteresis = 0,
	minLevel = 0.001,
	lamps = { mode = "curve", on = { 16.5, 18.5 }, off = { 5.5, 7.5 }, fade = 0 },
	kinds = {
		door = { colour = "#FFC27A", brightness = 1.4, range = 18, light = "point", flicker = "steady", decal = 0, shadows = false, switch = "night", emissive = 0.9 },
		window = { colour = "#FFD59A", brightness = 0.8, range = 16, light = "surface", angle = 70, flicker = "steady", decal = 0, shadows = false, switch = "night", emissive = 0.85 },
		campfire = { colour = "#FF9A45", brightness = 2, range = 18, light = "point", flicker = "ranch", decal = 0, shadows = false, switch = "night", emissive = 1 },
		crystals = { colour = "#B79BFF", brightness = 0.9, range = 10, light = "point", flicker = "steady", decal = 0, shadows = false, switch = "night", emissive = 0.8 },
		fountain = { colour = "#9FDFFF", brightness = 1.1, range = 20, light = "point", flicker = "steady", decal = 0, shadows = false, switch = "night", emissive = 0.6 },
	},
}
