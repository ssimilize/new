--[[
	Deep Reef (glow-up DR, roadmap 4.0 · Tides of the Deep): an underwater area you can visit and
	the swimming that goes with it. The expedition region itself is Config.Regions "reef" (it opens
	on its `opensAt`, like every region); this file is the place you dive into.

	  Dock       the Dive Dock at the edge of the Market Square (main place only): a pool, a pier and
	             the dive pad whose "Dive" prompt takes you down.
	  Area       a bowl of water deep under the ranch: sand at `floorY`, the surface at `surfaceY`,
	             `radius` studs round `center`. Everything inside it is swum, not walked.
	  Props      the hero props. Each has a `mesh` id ("" = the part-built placeholder; the art
	             pipeline fills them later and the builder gives the prop's Body a `Mesh` attribute).
	  Swim       the swim controller's tuning (Logic/Swim holds the maths).
	  Swimmers   existing lines that swim; new lines say `swims = true` in Config/Species.
	  Light      the underwater mood, applied locally while inside and handed back on leaving.
	  Life       light shafts, bubbles, fish schools and kelp: counts as `max` / `maxLow`.

	All client-built (Controllers/DeepReef, Visuals/ReefLife), like the Codex Museum: no state,
	actions or bus topics. Positions are { x, y, z } arrays.
]]

local Species = require(script.Parent.Species)

local DeepReef = {}

DeepReef.Region = "reef"
DeepReef.Unlock = "region_reef"

DeepReef.Dock = {
	position = { -72, 0, 60 }, -- the pool's centre, on the plaza's south-west edge by the Surf Shack
	pool = 16, -- pool diameter
	facing = 225, -- compass heading the pier points (0 = +Z, 90 = +X)
}

DeepReef.Area = {
	center = { 420, -330, 420 }, -- top of the sand, under the woods south-east of plot 4
	radius = 140,
	floorY = -330,
	surfaceY = -256,
	arrive = { 0, 14, -96 }, -- offsets from `center`: where a dive puts you
	bell = { 0, 0, -104 }, -- the Surface Bell ("Swim up")
	gate = { 0, 0, 64 }, -- the Reef Gate (Deep Reef expeditions)
	ruins = { -62, 0, 18 }, -- the sunken ruins
	seed = 4001, -- rocks, coral, kelp and vents are scattered from this seed
	clear = 22, -- studs kept free round the bell, the gate and the ruins
}

DeepReef.Props = {
	dock = { mesh = "", size = { 6, 1, 18 } },
	bell = { mesh = "", size = { 8, 10, 8 } },
	gate = { mesh = "", size = { 18, 22, 6 } },
	ruins = { mesh = "", size = { 40, 18, 30 } },
	giantClam = { mesh = "", size = { 9, 5, 7 } },
}

DeepReef.Counts = {
	rocks = 22, -- the ring of rocks round the edge
	coral = 18, -- glowing coral clusters
	kelp = 30,
	vents = 6, -- bubble vents
}

DeepReef.Swim = {
	speed = 14, -- studs a second, swimming on foot
	vertical = 11, -- ascend / descend speed on foot
	accel = 3.5, -- how quickly velocity reaches the target (per second, exponential)
	drag = 1.8, -- how quickly it coasts to a stop with no input
	buoyancy = 0.6, -- the gentle rise when nothing is pressed
	pitchFollow = 0.7, -- swimming forward follows the camera up and down this much
	margin = 3, -- studs kept from the sand, the surface and the edge
	tilt = 60, -- degrees an avatar leans into a full-speed swim
	mountTilt = 16, -- a mount leans less
	bob = { amplitude = 0.35, period = 2.8 }, -- the float while idle (studs, seconds)
	mountFactor = 1.1, -- a swimmer mount swims at its riding speed × this…
	mountMin = 1.5, -- …and at least this many times the on-foot speed
	clipRate = 0.55, -- a swimmer mount's walk clip plays this much slower: strokes, not steps
	inputSlack = 0.05,
}

-- Lines that swim before glow-up DR (new lines carry `swims = true` themselves).
DeepReef.Swimmers = {
	bubblin = true,
	shellsnap = true,
	anglit = true,
	jellow = true,
	surfotter = true,
	sunnyray = true,
	tempestray = true,
	floelet = true,
	pengling = true,
}

function DeepReef.Swims(lineId: string?): boolean
	if type(lineId) ~= "string" then
		return false
	end
	local def = Species.ById[lineId]
	return def ~= nil and (def.swims == true or DeepReef.Swimmers[lineId] == true)
end

DeepReef.Light = {
	tint = "#9FEBE0", -- ColorCorrection tint, stacked on the Weather controller's
	brightness = -0.04,
	contrast = 0.06,
	saturation = -0.08,
	ambient = "#2E6E78",
	outdoorAmbient = "#3F8F98",
	atmosphere = { density = 0.52, offset = 0, haze = 2.4, glare = 0, color = "#1D7F8C", decay = "#0B3F52" },
	-- Sky / Critters layers switched off while inside (their Lighting "Ambience_<layer>" overrides).
	layers = { "clouds", "sunRays", "depthOfField", "goldenHour", "butterflies", "fireflies", "birds", "fish" },
}

DeepReef.Life = {
	shafts = { max = 8, maxLow = 3, color = "#CFFFF6" },
	bubbles = { rate = 2.2, rateLow = 1, lifetime = { 4, 6 } },
	trail = { rate = 4, rateLow = 0 }, -- bubbles off a moving swimmer
	fish = {
		schools = 5,
		schoolsLow = 2,
		perSchool = 7,
		perSchoolLow = 4,
		colors = { "#FF8A3D", "#FFFFFF", "#FFC23D", "#5CE1E6", "#FF7AC8" }, -- the fountain carp's, plus reef colours
	},
	kelp = { max = 30, maxLow = 10, range = 140, angle = 7, speed = 0.18 },
	rate = 20, -- kelp / fish / shaft updates a second
}

return DeepReef
