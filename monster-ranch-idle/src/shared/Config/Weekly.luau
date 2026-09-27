--[[
	Weekly goals (update 3.8 · Reasons to come back). From Ranch Level 5 (Unlocks "weekly") each
	player gets GoalCount goals a week, drawn from Pool with a seed of ("weekly", userId, week)
	(Logic/Weekly.Pick), only from features unlocked when the week's draw first happens, and never
	two goals of one `family`. The week is Config.Leaderboards.Week (Saturday 15:00 UTC reset).

	Pool entry: { id, family, text, topic, target, filter?, unlock?, during? }
	  during = "titan": drawn only in a week with a titan invasion (Logic/Weekly.Available)
	  topic/filter/target work like Quests objectives (Logic/Objectives); counts use
	  Config.Quests.CountField. Targets are sized for a casual player to finish in 5-7 days.

	Chest: steps paid by goals done; each step is claimable as soon as it is reached, and any step
	reached but not claimed is paid automatically when the week rolls over. From RoyalLevel the
	last step's Crystal egg becomes a Royal egg (Logic/Weekly.ChestReward).
]]

local Weekly = {}

Weekly.Unlock = "weekly"
Weekly.GoalCount = 5
Weekly.RoyalLevel = 25

Weekly.Pool = {
	{ id = "hatch_15", family = "eggs", text = "Hatch 15 eggs", topic = "EggHatched", target = 15 },
	{
		id = "hatch_rare_3",
		family = "eggs",
		text = "Hatch 3 Rare or better monsters",
		topic = "EggHatched",
		target = 3,
		filter = { minRarity = 3 },
		unlock = "egg_crystal",
	},
	{ id = "jars_40", family = "jars", text = "Collect coin jars 40 times", topic = "JarCollected", target = 40 },
	{ id = "stages_20", family = "stages", text = "Win 20 stage battles", topic = "StageCleared", target = 20 },
	{ id = "expeditions_6", family = "expeditions", text = "Claim 6 expeditions", topic = "ExpeditionClaimed", target = 6 },
	{ id = "feed_60", family = "feeding", text = "Feed monsters 60 times", topic = "MonsterFed", target = 60 },
	{ id = "levelup_40", family = "training", text = "Level up monsters 40 times", topic = "MonsterLeveled", target = 40 },
	{ id = "evolve_3", family = "growing", text = "Grow up 3 monsters", topic = "MonsterEvolved", target = 3 },
	{ id = "pet_25", family = "social", text = "Pet 25 monsters on other ranches", topic = "PetGiven", target = 25 },
	{ id = "stampede_4", family = "stampede", text = "Join 4 Stampedes", topic = "BossJoined", target = 4, unlock = "boss" },
	{
		id = "titan_1",
		family = "stampede",
		text = "Join a Titan invasion",
		topic = "TitanJoined",
		target = 1,
		unlock = "boss",
		during = "titan",
	},
	{
		id = "contests_3",
		family = "contests",
		text = "Enter 3 Monster Contests",
		topic = "ContestEntered",
		target = 3,
		unlock = "contests",
	},
	{ id = "breed_3", family = "breeding", text = "Breed 3 monsters", topic = "Bred", target = 3, unlock = "breeding" },
	{ id = "market_3", family = "market", text = "List 3 items on the Market", topic = "MarketListed", target = 3, unlock = "market" },
	{
		id = "jobs_10",
		family = "jobs",
		text = "Collect from the Job Board 10 times",
		topic = "JobsCollected",
		target = 10,
		unlock = "jobs",
	},
	{ id = "ride_10", family = "riding", text = "Ride your monsters 10 times", topic = "Mounted", target = 10, unlock = "riding" },
	{ id = "races_8", family = "racing", text = "Run 8 races", topic = "RaceFinished", target = 8, unlock = "racing" },
	{ id = "arena_10", family = "arena", text = "Fight 10 Arena battles", topic = "ArenaBattle", target = 10, unlock = "arena" },
	{
		id = "arena_wins_5",
		family = "arena",
		text = "Win 5 Arena battles",
		topic = "ArenaBattle",
		target = 5,
		filter = { won = true },
		unlock = "arena",
	},
	{
		id = "genelab_5",
		family = "genelab",
		text = "Tune 5 genes in the Gene Lab",
		topic = "GeneTuned",
		target = 5,
		unlock = "gene_lab",
	},
	{
		id = "dojo_3",
		family = "dojo",
		text = "Train 3 techniques at the Dojo",
		topic = "SkillTrained",
		target = 3,
		unlock = "dojo",
	},
	{
		id = "bounty_3",
		family = "bounties",
		text = "Defeat 3 bounties",
		topic = "BountyDefeated",
		target = 3,
		unlock = "bounties",
	},
	{ id = "cook_10", family = "cooking", text = "Cook 10 dishes", topic = "DishCooked", target = 10, unlock = "kitchen" },
	{ id = "fish_20", family = "fishing", text = "Catch 20 fish", topic = "FishCaught", target = 20, unlock = "fishing" },
	{ id = "dig_10", family = "digsite", text = "Finish 10 digs", topic = "DigFinished", target = 10, unlock = "dig_site" },
	{ id = "raids_5", family = "raids", text = "Finish 5 raids", topic = "RaidFinished", target = 5, unlock = "raids" },
	{
		id = "crystals_10",
		family = "sky",
		text = "Collect 10 Sky Island crystals",
		topic = "CrystalCollected",
		target = 10,
		unlock = "region_sky",
	},
	-- 3.10 · Ranch Tourists
	{
		id = "tourists_15",
		family = "tourists",
		text = "Welcome 15 tourists",
		topic = "TouristVisited",
		target = 15,
		unlock = "tourists",
	},
	-- 3.11 · Travelling Merchant
	{
		id = "merchant_3",
		family = "merchant",
		text = "Shop 3 times at the Travelling Merchant",
		topic = "MerchantBought",
		target = 3,
		unlock = "merchant",
	},
	-- 3.11 · Ranch Seasons: the season's own fish (they bite only in their season)
	{
		id = "season_fish_3",
		family = "seasons",
		text = "Catch 3 fish of the season",
		topic = "FishCaught",
		target = 3,
		filter = { seasonal = true },
		unlock = "fishing",
	},
	{
		id = "stars_5",
		family = "observatory",
		text = "Make 5 star sightings",
		topic = "StarSighted",
		target = 5,
		unlock = "observatory",
	},
	-- 3.12 · Museum Exhibits (donated or filled by themselves)
	{
		id = "exhibits_3",
		family = "exhibits",
		text = "Fill 3 museum exhibits",
		topic = "ExhibitDonated",
		target = 3,
		unlock = "exhibits",
	},
	-- 3.12 · Apiary & Honey: honey only (Royal Jelly is published with honey = false)
	{
		id = "honey_40",
		family = "apiary",
		text = "Collect 40 honey from your beehives",
		topic = "HoneyCollected",
		target = 40,
		filter = { honey = true },
		unlock = "apiary",
	},
	-- 3.12 · Trial Tower: floors cleared (the climb starts over with the week)
	{
		id = "tower_10",
		family = "tower",
		text = "Clear 10 Trial Tower floors",
		topic = "TowerFloorCleared",
		target = 10,
		unlock = "trial_tower",
	},
	-- 3.13 · Treasure Maps
	{
		id = "treasure_2",
		family = "treasure",
		text = "Open 2 treasure chests",
		topic = "TreasureOpened",
		target = 2,
		unlock = "treasure_maps",
	},
	-- 3.13 · Stray Monsters: strays befriended (and adopted)
	{
		id = "strays_3",
		family = "strays",
		text = "Befriend 3 stray monsters",
		topic = "StrayBefriended",
		target = 3,
		unlock = "strays",
	},
	-- 3.13 · Hot Springs & Spa: soaks collected
	{
		id = "spa_5",
		family = "spa",
		text = "Give your monsters 5 spa soaks",
		topic = "SpaSoaked",
		target = 5,
		unlock = "spa",
	},
	},
	-- 3.13 · Bug Catching Meadow
	{ id = "bugs_15", family = "bugs", text = "Catch 15 bugs", topic = "BugCaught", target = 15, unlock = "bug_meadow" },
}

Weekly.ById = {}
for _, def in Weekly.Pool do
	assert(Weekly.ById[def.id] == nil, "[Config.Weekly] duplicate goal id " .. def.id)
	assert(type(def.family) == "string", "[Config.Weekly] goal without a family: " .. def.id)
	Weekly.ById[def.id] = def
end

Weekly.Chest = {
	{
		goals = 1,
		reward = { { kind = "coins", seconds = 1200, amount = 0 }, { kind = "gems", amount = 15 } },
	},
	{
		goals = 3,
		reward = {
			{ kind = "coins", seconds = 3600, amount = 0 },
			{ kind = "gems", amount = 40 },
			{ kind = "food", id = "random", amount = 10 },
		},
	},
	{
		goals = 5,
		reward = {
			{ kind = "coins", seconds = 7200, amount = 0 },
			{ kind = "gems", amount = 100 },
			{ kind = "egg", id = "crystal", amount = 1 },
		},
		royal = true, -- the egg is a Royal egg from RoyalLevel
	},
}

return Weekly
