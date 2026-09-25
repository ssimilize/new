--[[
	World layout in studs. The world is built procedurally from this table (server builds
	collision/ground, clients build decoration and monsters), so art can replace pieces later
	by tagging models with the same names.
	Positions are { x, y, z } arrays (no Roblox types in Config).
]]

local World = {}

World.GroundY = 0
World.GroundSize = { 900, 900 }
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
World.PenSize = { 34, 28 }
World.PenOffsets = {
	{ -38, 0, -24 },
	{ 2, 0, -24 },
	{ -38, 0, 18 },
	{ 2, 0, 18 },
	{ 42, 0, -24 },
}
World.IncubatorOffset = { 48, 0, 22 }
World.BarnOffset = { 55, 0, 40 }
World.StatueRowOffset = { -60, 0, 44 }
World.GardenOffset = { 42, 0, 44 }

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

return World
