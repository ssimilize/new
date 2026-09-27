--[[
	Clockwork Canyon (R2-CLOCKWORK, roadmap 4.1): the brass-and-gears region and the two things
	built for it in the world (like Config.DeepReef did for the Deep Reef). The expedition region
	itself is Config.Regions "clockwork" (it opens on its `opensAt`, like every region); this file
	is the landmark and the walk-in area round its Gate.

	  Landmark   a rotating gear tower at the edge of the Market Square (main place only): always
	             built, always turning, no unlock check (like the Dive Dock). Purely decorative.
	  Area       a girder-and-gear canyon floor elsewhere in the world: sand replaced with rusted
	             plate, scattered gears, girders and spark vents, and the Gate that opens
	             Clockwork Canyon expeditions (Ranch Level `Regions.reef`'s equivalent check).
	  Props      the hero props. Each has a `mesh` id ("" = the part-built placeholder; the art
	             pipeline fills them later and the builder gives the prop's Body a `Mesh` attribute).
	  Gears      every rotating disc, on the landmark and in the area: `speed` degrees a second,
	             `axis` the local axis it spins round. Visuals/ClockworkGears turns them client-side
	             from a plain CFrame update on Heartbeat; cheap (a handful of parts) and
	             streaming-safe (only touches gears that exist, like Visuals/Streaming everywhere
	             else in R2-STREAMING).

	Client-built, like the Deep Reef and the Codex Museum: no state, actions or bus topics.
	Positions are { x, y, z } arrays.
]]

local Clockwork = {}

Clockwork.Region = "clockwork"
Clockwork.Unlock = "region_clockwork"

Clockwork.Landmark = {
	position = { -96, 0, -40 }, -- the Market Square's north-west edge, opposite the Dive Dock
	facing = 45, -- compass heading the tower faces (0 = +Z, 90 = +X)
}

Clockwork.Area = {
	center = { -420, -40, 420 }, -- a rusted canyon floor south-west of the ranch, away from the reef
	radius = 130,
	floorY = -40,
	seed = 4101, -- girders, gears and vents are scattered from this seed
	gate = { 0, 0, 60 }, -- the Clockwork Gate (Clockwork Canyon expeditions)
	clear = 20, -- studs kept free round the gate
}

Clockwork.Props = {
	tower = { mesh = "", size = { 10, 30, 10 } },
	gate = { mesh = "", size = { 18, 22, 6 } },
	forge = { mesh = "", size = { 12, 10, 10 } },
}

Clockwork.Counts = {
	girders = 20, -- rusted brass girders round the edge
	gears = 16, -- scattered ground gears (some turning)
	vents = 6, -- spark vents
}

-- Gear rotation tuning read by Visuals/ClockworkGears. `speed` degrees a second; alternating
-- neighbours spin opposite ways, the way meshed gears actually mesh.
Clockwork.Gears = {
	towerSpeed = 18,
	groundSpeedMin = 10,
	groundSpeedMax = 26,
}

return Clockwork
