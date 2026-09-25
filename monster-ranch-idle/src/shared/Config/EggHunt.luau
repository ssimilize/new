--[[
	Spring Bloom egg hunt (update 1.4). While the event runs, `PerRound` painted eggs hide
	around the Market Square each round (`RoundSeconds`, on the unix clock so every server
	hides them in the same spots at the same moment). Each player can find each egg once;
	finding them all in a round pays a bonus. Finds are capped per UTC day.

	Spots are { x, y, z } in studs around the hub (Config.World), clear of the buildings.
]]

local EggHunt = {}

EggHunt.Event = "springbloom"
EggHunt.RoundSeconds = 20 * 60
EggHunt.PerRound = 4
EggHunt.Reach = 16 -- studs: how close a player must stand to pick an egg up
EggHunt.Reward = 10 -- event tokens per egg
EggHunt.RoundBonus = 20 -- extra tokens for finding every egg of a round
EggHunt.DailyFinds = 40
EggHunt.Colors = { "#FF9EC7", "#FFE38A", "#9FE3FF", "#B9A7FF", "#7BD389", "#FFB38A" }

EggHunt.Spots = {
	{ -18, 1, -28 },
	{ 18, 1, -28 },
	{ -80, 1, -20 },
	{ 80, 1, -22 },
	{ -80, 1, 24 },
	{ 80, 1, 24 },
	{ -86, 1, 42 },
	{ 84, 1, 4 },
	{ -14, 1, 80 },
	{ 16, 1, 80 },
	{ -50, 1, -78 },
	{ 50, 1, -78 },
	{ -20, 1, -72 },
	{ -86, 1, -50 },
	{ 86, 1, -48 },
	{ 24, 1, 20 },
	{ -24, 1, 18 },
	{ 0, 1, 30 },
}

assert(EggHunt.PerRound <= #EggHunt.Spots, "EggHunt.PerRound must not exceed the number of spots")

return EggHunt
