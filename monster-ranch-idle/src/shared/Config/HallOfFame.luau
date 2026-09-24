--[[
	Hall of Fame (prestige layer 1). Retire an Adult at its level cap: it becomes a statue,
	adds a Legacy bonus (+1%..+6% by rarity) to every monster of its element, capped per element,
	and pays Stardust + Star Shards. Stardust buys permanent upgrades.
]]

local HallOfFame = {}

HallOfFame.Unlock = "hall_of_fame"
HallOfFame.LegacyCapPerElement = 0.60
HallOfFame.StarShardsPerRetire = { 1, 1, 2, 2, 3, 4 } -- by rarity index
HallOfFame.MaxStatues = 12 -- statues shown on the ranch (newest first)
HallOfFame.MaxEntries = 100 -- retired monsters kept in the save (newest first)

HallOfFame.Upgrades = {
	{
		id = "incubator_speed",
		name = "Warm Nests",
		desc = "Hatch time −5% per level.",
		maxLevel = 3,
		cost = { 60, 180, 500 },
		effect = { hatchSpeed = 0.05 },
	},
	{
		id = "expedition_loot",
		name = "Trail Maps",
		desc = "Expedition loot +5% per level.",
		maxLevel = 5,
		cost = { 50, 120, 260, 520, 1000 },
		effect = { lootPct = 0.05 },
	},
	{
		id = "daily_breed",
		name = "Matchmaker",
		desc = "+1 breed per monster per day.",
		maxLevel = 2,
		cost = { 300, 900 },
		effect = { breedsPerDay = 1 },
	},
	{
		id = "jar_cap",
		name = "Deep Jars",
		desc = "Coin jars hold 15 more minutes per level.",
		maxLevel = 4,
		cost = { 40, 100, 220, 450 },
		effect = { jarCapSeconds = 900 },
	},
	{
		id = "mood_floor",
		name = "Happy Ranch",
		desc = "Mood never drops below 50.",
		maxLevel = 1,
		cost = { 150 },
		effect = { moodFloor = 50 },
	},
	{
		id = "boss_power",
		name = "War Drums",
		desc = "Stampede damage +5% per level.",
		maxLevel = 4,
		cost = { 80, 200, 420, 800 },
		effect = { bossDmgPct = 0.05 },
	},
}

HallOfFame.UpgradeById = {}
for _, u in HallOfFame.Upgrades do
	HallOfFame.UpgradeById[u.id] = u
end

return HallOfFame
