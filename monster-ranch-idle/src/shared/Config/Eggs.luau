--[[
	Eggs. `odds` are percentages by rarity index {common, uncommon, rare, epic, legendary, mythic}
	and must sum to 100. Odds shown to players are read from this table, so what players see
	and what the server rolls can never disagree.

	price: { coins = n } or { gems = n } or nil (not sold).
	stock: restock behaviour on the global 5-minute clock.
	  unlimited = true           always in stock
	  min, max                   stock range when the egg appears
	  appearChance               chance the egg appears in a given restock
	pool: which Species pool the line is drawn from.
]]

local Eggs = {}

Eggs.RestockSeconds = 5 * 60
Eggs.MaxBuyPerRequest = 10

Eggs.List = {
	{
		id = "meadow",
		name = "Meadow Egg",
		order = 1,
		price = { coins = 150 },
		hatchSeconds = 30,
		unlock = "egg_meadow",
		odds = { 75, 22, 3, 0, 0, 0 },
		pool = "common",
		stock = { unlimited = true },
		colors = { shell = "#C9EDA8", spots = "#79C455" },
		pattern = "spots",
	},
	{
		id = "grove",
		name = "Grove Egg",
		order = 2,
		price = { coins = 4000 },
		hatchSeconds = 180,
		unlock = "egg_grove",
		odds = { 45, 40, 13, 2, 0, 0 },
		pool = "common",
		stock = { min = 3, max = 6, appearChance = 1 },
		colors = { shell = "#8FD19E", spots = "#2F8A4A" },
		pattern = "spots",
	},
	{
		id = "crystal",
		name = "Crystal Egg",
		order = 3,
		price = { coins = 90000 },
		hatchSeconds = 900,
		unlock = "egg_crystal",
		odds = { 0, 45, 38, 15, 2, 0 },
		pool = "common",
		stock = { min = 1, max = 3, appearChance = 0.6 },
		colors = { shell = "#A9DEFF", spots = "#FFFFFF" },
		pattern = "facets",
	},
	{
		id = "royal",
		name = "Royal Egg",
		order = 4,
		price = { coins = 2500000 },
		hatchSeconds = 3600,
		unlock = "egg_royal",
		odds = { 0, 0, 50, 38, 11, 1 },
		pool = "common",
		stock = { min = 1, max = 1, appearChance = 0.15 },
		colors = { shell = "#B58CFF", spots = "#FFD447" },
		pattern = "band",
		luckyMeter = { every = 5, minRarity = 4 }, -- every 5th Royal hatch is Epic or better
	},
	{
		id = "starlit",
		name = "Starlit Egg",
		order = 5,
		price = { gems = 150 },
		hatchSeconds = 1200,
		unlock = "egg_starlit",
		odds = { 0, 0, 60, 32, 7.5, 0.5 },
		pool = "common",
		stock = { unlimited = true },
		colors = { shell = "#2E3A78", spots = "#FFE680" },
		pattern = "stars",
		pity = { count = 40, minRarity = 5 }, -- a Legendary+ within 40 eggs
		paidRandom = true, -- hidden where paid random items are restricted
	},
	{
		id = "stampede",
		name = "Stampede Egg",
		order = 6,
		price = nil,
		hatchSeconds = 3600,
		unlock = "boss",
		odds = { 0, 0, 0, 70, 27, 3 },
		pool = "common",
		hybridChance = 0.05,
		colors = { shell = "#F08A4B", spots = "#7A3A12" },
		pattern = "cracks",
	},
	{
		id = "frostfall",
		name = "Frostfall Egg",
		order = 7,
		event = "frostfall",
		price = { token = 400 },
		hatchSeconds = 900,
		unlock = "egg_meadow",
		odds = { 0, 40, 35, 18, 6, 1 },
		pool = "frostfall",
		forcedMutation = "frosted",
		stock = { unlimited = true },
		colors = { shell = "#E6F6FF", spots = "#7CC7FF" },
		pattern = "snowflake",
	},
}

Eggs.ById = {}
for _, e in Eggs.List do
	Eggs.ById[e.id] = e
	local sum = 0
	for _, p in e.odds do
		sum += p
	end
	assert(math.abs(sum - 100) < 1e-6, "Egg odds must sum to 100: " .. e.id)
end

-- The starter egg given on first join (see Quests.Tutorial). Always Uncommon.
Eggs.Starter = { lines = { "cindlet", "bubblin", "mossbun" }, rarity = 2, hatchSeconds = 8 }

return Eggs
