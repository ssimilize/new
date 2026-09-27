--[[
	Sunken Abyss (R2-ABYSS, roadmap 4.1's idea — Clockwork Canyon took that slot's code name, so
	this ships as region 10, next after it): the darkest place in the game and the two things
	built for it in the world (like Config.Clockwork did for Clockwork Canyon, Config.DeepReef for
	the Deep Reef). The expedition region itself is Config.Regions "abyss" (it opens on its
	`opensAt`, like every region); this file is the place you dive to reach it.

	  Descent    a chasm prop dropped into the Deep Reef's own Area (Config.DeepReef.Area), reached
	             while already swimming there. Its "Dive Deeper" prompt hands the swim off to a
	             second, darker Area entirely (Controllers/DeepReef.Descend / .Ascend switch which
	             Area's bounds the swim steps against, so the same swim loop keeps running).
	  Area       a second, deeper bowl of water below the reef: no sunlight, only the glow the
	             place makes itself. `arrive` is where a descent lands you; `ascend` is the Ascent
	             Bell that hands the swim back to the Deep Reef's own Area at its `arrive` point —
	             the safe way back up.
	  Props      the hero props (mesh = "" placeholders, like every other region's).
	  Life       glowing motes, bioluminescent fish schools and vents: counts as `max` / `maxLow`
	             (Visuals/AbyssLife, the same shape as Config.DeepReef.Life minus light shafts —
	             there is no sunlight down here to shaft).
	  Light      stacked on top of the Deep Reef's own light while descended (an extra, darker
	             ColorCorrectionEffect; the Reef's own Weather hold / ambience swap is left alone).

	All client-built (Controllers/Abyss), like the Deep Reef and Clockwork Canyon: no state,
	actions or bus topics. Positions are { x, y, z } arrays; the Descent position is relative to
	Config.DeepReef.Area.center, like the Reef's own `bell` / `gate` / `ruins` offsets.
]]

local Abyss = {}

Abyss.Region = "abyss"
Abyss.Unlock = "region_abyss"

-- Inside the Deep Reef's own Area, past the ruins: a dark crack in the sand floor.
Abyss.Descent = {
	offset = { 40, 0, -60 }, -- from Config.DeepReef.Area.center
	clear = 12,
}

Abyss.Area = {
	center = { 900, -640, 900 }, -- its own bowl, well below and away from the reef's
	radius = 120,
	floorY = -640,
	surfaceY = -560, -- a false "ceiling" of black water, not open sky: no Surface part is drawn
	arrive = { 0, 10, -90 }, -- offsets from `center`
	ascend = { 0, 0, -100 }, -- the Ascent Bell (hands the swim back to the Deep Reef)
	gate = { 0, 0, 60 }, -- the Abyss Gate (Sunken Abyss expeditions)
	spire = { -50, 0, 10 }, -- a broken glowing spire, the landmark prop
	seed = 4201,
	clear = 20,
}

Abyss.Props = {
	chasm = { mesh = "", size = { 14, 4, 14 } },
	bell = { mesh = "", size = { 8, 10, 8 } },
	gate = { mesh = "", size = { 18, 22, 6 } },
	spire = { mesh = "", size = { 10, 34, 10 } },
}

Abyss.Counts = {
	rocks = 20,
	spires = 10, -- smaller glowing spire clusters scattered round the floor
	vents = 5,
}

Abyss.Life = {
	motes = { max = 26, maxLow = 10, color = "#5CE1E6" }, -- drifting glow motes (no sunlight to shaft)
	bubbles = { rate = 1.6, rateLow = 0.8, lifetime = { 5, 8 } },
	trail = { rate = 3, rateLow = 0 },
	fish = {
		schools = 4,
		schoolsLow = 2,
		perSchool = 6,
		perSchoolLow = 3,
		colors = { "#7CFFB2", "#5CE1E6", "#B388FF", "#FF7AC8" }, -- bioluminescent, not the reef's reds/oranges
	},
	rate = 20,
}

Abyss.Light = {
	tint = "#2A1E4A", -- stacked further onto the Deep Reef's own ReefColor: colder, darker, purple-black
	brightness = -0.16,
	contrast = 0.1,
	saturation = -0.14,
	atmosphere = { density = 0.7, offset = 0, haze = 3.4, glare = 0, color = "#0B0F2E", decay = "#02030F" },
}

return Abyss
