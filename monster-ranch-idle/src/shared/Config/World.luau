--[[
	World layout in studs. The world is built procedurally from this table (server builds
	collision/ground, clients build decoration and monsters), so art can replace pieces later
	by tagging models with the same names.
	Positions are { x, y, z } arrays (no Roblox types in Config).
]]

local World = {}

World.GroundY = 0
-- The grass runs past the wall (Boundary) so the forest band beyond it stands on ground.
World.GroundSize = { 2000, 2000 }
World.PlotSize = { 150, 110 } -- width (x), depth (z)
World.HubRadius = 95

World.Plots = {
	{ id = 1, center = { -240, 0, -120 }, facing = 90 },
	{ id = 2, center = { -240, 0, 120 }, facing = 90 },
	{ id = 3, center = { 240, 0, -120 }, facing = -90 },
	{ id = 4, center = { 240, 0, 120 }, facing = -90 },
	{ id = 5, center = { 0, 0, -265 }, facing = 0 },
	{ id = 6, center = { 0, 0, 265 }, facing = 180 },
}

-- Pens inside a plot, relative to the plot centre (plot faces the hub along +x local).
-- A 3 × 2 grid either side of the middle aisle (plot-local z = 0) that leads in from the gate.
World.PenSize = { 34, 28 }
World.PenOffsets = {
	{ -38, 0, -24 },
	{ 2, 0, -24 },
	{ -38, 0, 18 },
	{ 2, 0, 18 },
	{ 42, 0, -24 },
	{ 42, 0, 18 }, -- update 3.2: pen 6 completes the grid
}
-- Update 3.2: pen 6 took the incubator pad's old corner. The pad now closes the far end of
-- the middle aisle, facing the gate; the barn moved back so its door clears pen 6's fence.
World.IncubatorOffset = { -65, 0, -3 }
World.BarnOffset = { 58, 0, 45 }
World.StatueRowOffset = { -60, 0, 44 }
World.GardenOffset = { 42, 0, 44 }

-- Footprints on the plot floor ({ x, z } studs), used to build the pieces and by
-- LevelSeventy.spec to prove that no two pieces overlap and all stay inside PlotSize.
World.IncubatorPadSize = 15 -- diameter of the pad's rim
World.BarnSize = { 14, 10, 12 } -- x, height, z (the door faces plot-local -z)
World.GardenSize = { 10, 8 } -- reserved: the garden has no world model yet
World.StatueRow = { count = 8, spacing = 7, pedestal = 4.4 } -- runs +x from StatueRowOffset

-- Hub buildings (Market Square), relative to the origin.
World.Hub = {
	{ id = "eggShop", name = "Egg Shop", position = { -35, 0, -55 }, size = { 26, 18, 18 }, color = "#EF6FA8", screen = "EggShop" },
	{ id = "feedStore", name = "Feed Store", position = { 35, 0, -55 }, size = { 26, 18, 18 }, color = "#F2A93B", screen = "Store" },
	{ id = "trading", name = "Trading Plaza", position = { -62, 0, 0 }, size = { 20, 14, 26 }, color = "#4FB6F2", screen = "Trade" },
	{ id = "gate", name = "Expedition Gate", position = { 62, 0, 0 }, size = { 20, 24, 26 }, color = "#43B649", screen = "Expeditions" },
	{
		id = "hallOfFame",
		name = "Hall of Fame",
		position = { -35, 0, 55 },
		size = { 26, 20, 18 },
		color = "#8B6AD8",
		screen = "HallOfFame",
	},
	{ id = "arena", name = "Stampede Arena", position = { 35, 0, 55 }, size = { 30, 12, 30 }, color = "#E5484D", screen = "Boss" },
	-- Update 1.3: market stalls beside the Trading Plaza.
	{ id = "market", name = "Market", position = { -62, 0, -34 }, size = { 18, 12, 16 }, color = "#F2A93B", screen = "Market" },
	-- Update 1.4: the Star Altar (Ranch Rebirth) between the Expedition Gate and the Arena.
	{ id = "starAltar", name = "Star Altar", position = { 62, 0, 36 }, size = { 14, 14, 14 }, color = "#6B5BD6", screen = "Rebirth" },
	-- Update 1.5: the Showtime Stage (Monster Contests) across from the Market stalls.
	{ id = "showStage", name = "Showtime Stage", position = { 62, 0, -36 }, size = { 20, 6, 16 }, color = "#FF7AC8", screen = "Contests" },
	-- Update 2.0: the Surf Shack (Summer Splash surfing) south-west of the fountain.
	{ id = "surfShack", name = "Surf Shack", position = { -62, 0, 36 }, size = { 16, 10, 14 }, color = "#3FB6D9", screen = "Surf" },
	-- Update 1.2: the Club Plaza between the Hall of Fame and the Arena.
	{ id = "clubPlaza", name = "Club Plaza", position = { 0, 0, 62 }, size = { 16, 12, 14 }, color = "#2BA89A", screen = "Clubs" },
}
World.Fountain = { position = { 0, 0, 0 }, radius = 14 }
-- Weekly leaderboard board between the shops, facing the fountain (Screen: Leaderboards).
World.Board = { position = { 0, 0, -40 }, size = { 20, 12, 1.2 }, color = "#D49A12" }
World.Spawn = { 0, 3, -20 }

-- Update 2.1: the Champions Arena and the Raid Portal stand just outside the Market Square,
-- on the way to plots 1 and 3. They open their screens like hub buildings.
table.insert(World.Hub, {
	id = "championsArena",
	name = "Champions Arena",
	position = { -58, 0, -128 },
	size = { 30, 14, 26 },
	color = "#C0392B",
	screen = "Arena",
})
table.insert(World.Hub, {
	id = "raidPortal",
	name = "Raid Portal",
	position = { 58, 0, -128 },
	size = { 20, 18, 14 },
	color = "#6B5BD6",
	screen = "Raids",
})

-- Update 3.0 · Year Two: the Racetrack and the Trading Hub portal stand just outside the
-- Market Square on the way to plots 2 and 4 (mirroring the 2.1 buildings).
table.insert(World.Hub, {
	id = "racetrack",
	name = "Racetrack",
	position = { -58, 0, 128 },
	size = { 30, 8, 22 },
	color = "#FF8A3D",
	screen = "Racing",
})
table.insert(World.Hub, {
	id = "hubPortal",
	name = "Trading Hub",
	position = { 58, 0, 128 },
	size = { 18, 20, 14 },
	color = "#4FB6F2",
	screen = "TradingHub",
})

-- Update 3.0: the Accessory Workshop, west of the plaza between the paths to plots 1 and 2.
table.insert(World.Hub, {
	id = "workshop",
	name = "Workshop",
	position = { -112, 0, 0 },
	size = { 22, 14, 18 },
	color = "#FF7AC8",
	screen = "Workshop",
})

-- Glow-up O: the Codex Museum and the Hall of Fame plaza (client-built, Config/Codex) south of the
-- Market Square, either side of the path to plot 5. Scenery keeps off them (keepOut below).
World.CodexGrounds = {
	{ center = { 125, -222 }, size = { 90, 88 } }, -- Codex Museum (Logic/Museum.Layout fits inside)
	{ center = { -120, -214 }, size = { 70, 40 } }, -- Hall of Fame plaza
}

-- The perimeter: a stone wall on a square of 2 x `half` studs round the origin, and an invisible
-- barrier `barrier` studs tall on the same line so nobody jumps or climbs over. The play area
-- inside (1600 x 1600) leaves room around the plots for future features. `segment` is the
-- length of one wall mesh; a pillar stands every `pillarEvery` segments and on the corners.
World.Boundary = { half = 800, height = 9, thickness = 4, barrier = 80, segment = 24, pillarEvery = 4 }

-- Scenery (Logic/Scenery, World/Scenery): meshes scattered over the open ground, never on the
-- plaza, a plot, a path, a building or an egg-hunt spot. Per kind: `size` = the mesh's largest
-- dimension in studs, `count` items, placed in groups of `group` within `spread` studs.
-- `solid` items collide and keep other items off their `footprint` (x size). Add a zone to
-- `keepOut` ({ center = { x, z }, radius = r } or { center, size = { w, d } }) to keep ground
-- clear for a future feature; the kinds' mesh ids live in World/SceneryMeshes.
World.Scenery = {
	seed = 3203,
	margin = 6, -- extra studs between an item and a keep-out zone
	wallClearance = 8, -- studs kept clear inside the wall
	keepOut = { World.CodexGrounds[1], World.CodexGrounds[2] },
	kinds = {
		-- Big things first so the small ones fill in around them.
		-- Trees collide only through an invisible trunk post `trunk` x size wide.
		{ id = "oak", size = { 16, 22 }, count = 70, group = { 2, 5 }, spread = 26, solid = true, footprint = 0.42, trunk = 0.12 },
		{ id = "oakLight", size = { 16, 22 }, count = 55, group = { 2, 4 }, spread = 24, solid = true, footprint = 0.42, trunk = 0.12 },
		{ id = "pine", size = { 18, 26 }, count = 60, group = { 3, 6 }, spread = 28, solid = true, footprint = 0.3, trunk = 0.1 },
		{ id = "blossom", size = { 15, 20 }, count = 30, group = { 1, 3 }, spread = 16, solid = true, footprint = 0.42, trunk = 0.12 },
		{ id = "boulder", size = { 5, 10 }, count = 45, group = { 1, 3 }, spread = 14, solid = true, footprint = 0.5 },
		{ id = "bush", size = { 4, 7 }, count = 90, group = { 2, 4 }, spread = 12, solid = true, footprint = 0.45 },
		{ id = "log", size = { 7, 11 }, count = 25, solid = true, footprint = 0.35 },
		-- Ranch life: little scenes to come across between the trees.
		{ id = "windmill", size = { 22, 28 }, count = 5, solid = true, footprint = 0.3 },
		{ id = "wagon", size = { 8, 10 }, count = 8, solid = true, footprint = 0.45 },
		{ id = "well", size = { 7, 9 }, count = 8, solid = true, footprint = 0.45 },
		{ id = "scarecrow", size = { 7, 9 }, count = 14, solid = true, footprint = 0.2 },
		{ id = "toadstool", size = { 6, 10 }, count = 20, group = { 1, 3 }, spread = 12, solid = true, footprint = 0.35 },
		{ id = "hayStack", size = { 5, 7 }, count = 30, group = { 1, 3 }, spread = 10, solid = true, footprint = 0.4 },
		{ id = "bench", size = { 5, 6 }, count = 14, solid = true, footprint = 0.4 },
		{ id = "birdhouse", size = { 5, 7 }, count = 14, solid = true, footprint = 0.15 },
		{ id = "firewood", size = { 4, 6 }, count = 18, solid = true, footprint = 0.45 },
		{ id = "campfire", size = { 4, 5.5 }, count = 14, solid = true, footprint = 0.45 },
		{ id = "crystals", size = { 3, 5 }, count = 30, group = { 1, 3 }, spread = 10, solid = true, footprint = 0.45 },
		{ id = "honeypot", size = { 2.5, 3.5 }, count = 16, group = { 1, 2 }, spread = 6, solid = true, footprint = 0.45 },
		{ id = "stump", size = { 2.5, 4 }, count = 50, group = { 1, 3 }, spread = 16, solid = true, footprint = 0.4 },
		{ id = "stones", size = { 2, 4 }, count = 90, group = { 1, 3 }, spread = 10, footprint = 0.5 },
		{ id = "mushrooms", size = { 2, 3.5 }, count = 70, group = { 2, 4 }, spread = 8, footprint = 0.5 },
		{ id = "flowers", size = { 2.5, 4 }, count = 260, group = { 3, 7 }, spread = 12, footprint = 0.5 },
		{ id = "sunflowers", size = { 4, 6 }, count = 60, group = { 2, 5 }, spread = 10, footprint = 0.4 },
		{ id = "pumpkins", size = { 4, 6 }, count = 45, group = { 2, 4 }, spread = 10, footprint = 0.5 },
		{ id = "grass", size = { 2, 3.5 }, count = 700, group = { 4, 9 }, spread = 14, footprint = 0.5 },
	},
	-- The woods beyond the wall: one tree every `step` studs along each side, `depth` studs out.
	outside = { kinds = { "oak", "oakLight", "pine" }, size = { 22, 32 }, step = 26, depth = { 16, 150 } },
}

-- Update 2.0 · Sky Islands: floating islands high above the map, joined by cloud bridges.
-- The launch pad in the Market Square flies players to the landing island's return pad;
-- the Sky Gate there opens the Sky Islands expeditions. Island `center` is the top of the
-- grass; `radius` its size. Wind crystals are listed in Config.SkyIslands.
World.Sky = {
	launchPad = { 0, 0, -82 },
	returnPad = { 0, 160, 22 },
	gate = { 0, 160, -24 },
	islands = {
		{ id = "landing", name = "Landing Isle", center = { 0, 160, 0 }, radius = 42, grass = "#A6E07A" },
		{ id = "sunrise", name = "Sunrise Isle", center = { 118, 170, -8 }, radius = 26, grass = "#FFE9A8" },
		{ id = "dusk", name = "Dusk Isle", center = { -112, 166, 44 }, radius = 24, grass = "#B9A7FF" },
		{ id = "halo", name = "Halo Isle", center = { 34, 182, -122 }, radius = 22, grass = "#FFF6D6" },
		{ id = "rift", name = "Rift Isle", center = { -46, 176, 120 }, radius = 24, grass = "#6E62B6" },
	},
	bridges = { { "landing", "sunrise" }, { "landing", "dusk" }, { "landing", "halo" }, { "landing", "rift" } },
}

-- Glow-up U: the Stampede arena, east of the Expedition Gate between the paths to plots 3 and 4.
-- The giant and every joined squad appear here when the fight goes live; scenery keeps off it.
World.StampedeArena = { center = { 150, 0 }, radius = 40 }
table.insert(World.Scenery.keepOut, World.StampedeArena)

return World
