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
	rebirths: Rebirth Stars needed to buy it (Celestial Egg), on top of `unlock`.
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

-- Update 1.1 · Coral Depths: dropped by Coral Depths expeditions (stages 21+) and by
-- the Depths bosses the first time they fall; hatches the three Depths lines only.
table.insert(Eggs.List, {
	id = "pearl",
	name = "Pearl Egg",
	order = 8,
	price = nil,
	hatchSeconds = 1800,
	unlock = "coral_depths",
	odds = { 0, 30, 42, 22, 5.5, 0.5 },
	pool = "pearl",
	colors = { shell = "#F4EFE4", spots = "#7CC7E8" },
	pattern = "band",
})

-- Update 1.2 · Lunar Lanterns event egg (bought with Lantern Coins while the event runs).
table.insert(Eggs.List, {
	id = "lantern",
	name = "Lantern Egg",
	order = 9,
	event = "lunarlanterns",
	price = { token = 400 },
	hatchSeconds = 900,
	unlock = "egg_meadow",
	odds = { 0, 40, 35, 18, 6, 1 },
	pool = "lunarlanterns",
	forcedMutation = "glow",
	stock = { unlimited = true },
	colors = { shell = "#E5484D", spots = "#FFD447" },
	pattern = "band",
})

-- Update 1.4 · Rebirth: the Celestial Egg tier. Sold to ranches with a Rebirth Star
-- (`rebirths`), for coins; hatches the three celestial lines only.
table.insert(Eggs.List, {
	id = "celestial",
	name = "Celestial Egg",
	order = 10,
	price = { coins = 6000000 },
	hatchSeconds = 5400,
	unlock = "rebirth",
	rebirths = 1,
	odds = { 0, 0, 35, 42, 19, 4 },
	pool = "celestial",
	stock = { min = 1, max = 2, appearChance = 0.5 },
	colors = { shell = "#1B1F4B", spots = "#B9A7FF" },
	pattern = "stars",
})

-- Update 1.4 · Spring Bloom event egg (bought with Petals while the event runs).
table.insert(Eggs.List, {
	id = "bloom",
	name = "Bloom Egg",
	order = 11,
	event = "springbloom",
	price = { token = 400 },
	hatchSeconds = 900,
	unlock = "egg_meadow",
	odds = { 0, 40, 35, 18, 6, 1 },
	pool = "springbloom",
	forcedMutation = "blossom",
	stock = { unlimited = true },
	colors = { shell = "#FFE3F1", spots = "#7BD389" },
	pattern = "spots",
})

-- Update 2.0 · Sky Islands: dropped by Sky Islands expeditions and wind crystals; hatches
-- the Light and Void lines.
table.insert(Eggs.List, {
	id = "sky",
	name = "Sky Egg",
	order = 12,
	price = nil,
	hatchSeconds = 2400,
	unlock = "region_sky",
	odds = { 0, 20, 40, 28, 10, 2 },
	pool = "sky",
	colors = { shell = "#EAF6FF", spots = "#F2C94C" },
	pattern = "stars",
})

-- Update 2.0 · Summer Splash event egg (bought with Seashells while the event runs).
table.insert(Eggs.List, {
	id = "splash",
	name = "Splash Egg",
	order = 13,
	event = "summersplash",
	price = { token = 400 },
	hatchSeconds = 900,
	unlock = "egg_meadow",
	odds = { 0, 40, 35, 18, 6, 1 },
	pool = "summersplash",
	forcedMutation = "sunkissed",
	stock = { unlimited = true },
	colors = { shell = "#7FDBFF", spots = "#FFD447" },
	pattern = "band",
})

-- Update 2.1 · Raids: won from raids only; hatches the three raid lines.
table.insert(Eggs.List, {
	id = "raid",
	name = "Raid Egg",
	order = 14,
	price = nil,
	hatchSeconds = 3600,
	unlock = "raids",
	odds = { 0, 0, 40, 40, 17, 3 },
	pool = "raid",
	colors = { shell = "#3A2D55", spots = "#F5C630" },
	pattern = "cracks",
})

-- Update 2.1 · Harvest Moon event egg (bought with Moon Candy while the event runs).
table.insert(Eggs.List, {
	id = "harvest",
	name = "Harvest Egg",
	order = 15,
	event = "harvestmoon",
	price = { token = 400 },
	hatchSeconds = 900,
	unlock = "egg_meadow",
	odds = { 0, 40, 35, 18, 6, 1 },
	pool = "harvestmoon",
	stock = { unlimited = true },
	colors = { shell = "#F08A4B", spots = "#3A2D55" },
	pattern = "band",
})

-- Update 3.0 · Year Two: the new regions' eggs (from their expeditions and bosses).
table.insert(Eggs.List, {
	id = "dunes",
	name = "Dune Egg",
	order = 16,
	price = nil,
	hatchSeconds = 2700,
	unlock = "region_dunes",
	odds = { 0, 15, 40, 30, 12, 3 },
	pool = "dunes",
	colors = { shell = "#F4D58D", spots = "#C9772B" },
	pattern = "band",
})
table.insert(Eggs.List, {
	id = "glacier",
	name = "Glacier Egg",
	order = 17,
	price = nil,
	hatchSeconds = 2700,
	unlock = "region_glacier",
	odds = { 0, 15, 40, 30, 12, 3 },
	pool = "glacier",
	colors = { shell = "#DDF3FF", spots = "#7CC7FF" },
	pattern = "snowflake",
})

-- Update 3.2 · Raid 3: won only from the Frost Leviathan raid; hatches the Floelet line.
table.insert(Eggs.List, {
	id = "leviathan",
	name = "Leviathan Egg",
	order = 18,
	price = nil,
	hatchSeconds = 3600,
	unlock = "raid_leviathan",
	odds = { 0, 0, 35, 40, 20, 5 },
	pool = "leviathan",
	colors = { shell = "#1F4E79", spots = "#BFEFFF" },
	pattern = "cracks",
})

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
