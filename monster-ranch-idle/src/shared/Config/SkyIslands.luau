--[[
	Sky Islands wind crystals (update 2.0). Crystals sit on the floating islands
	(Config.World.Sky). Each player can collect each crystal once per `RespawnSeconds`, up to
	`DailyCap` a UTC day, standing within `Reach` studs of it. A crystal pays one roll of
	`Loot` (Rewards items; `coins` with `seconds` = that much ranch income).
]]

local SkyIslands = {}

SkyIslands.Unlock = "region_sky"
SkyIslands.RespawnSeconds = 60 * 60
SkyIslands.DailyCap = 60
SkyIslands.Reach = 14

SkyIslands.Crystals = {
	{ 20, 161.5, 10 },
	{ -24, 161.5, -12 },
	{ -8, 161.5, 30 },
	{ 126, 171.5, -2 },
	{ 110, 171.5, -16 },
	{ 122, 171.5, -20 },
	{ -118, 167.5, 36 },
	{ -104, 167.5, 52 },
	{ 40, 183.5, -116 },
	{ 28, 183.5, -130 },
	{ -52, 177.5, 126 },
	{ -38, 177.5, 112 },
	{ -44, 177.5, 132 },
}

SkyIslands.Loot = {
	{ weight = 60, item = { kind = "coins", seconds = 240, amount = 0 } },
	{ weight = 22, item = { kind = "treats", amount = 8 } },
	{ weight = 12, item = { kind = "stardust", amount = 20 } },
	{ weight = 6, item = { kind = "egg", id = "sky", amount = 1 } },
}

return SkyIslands
