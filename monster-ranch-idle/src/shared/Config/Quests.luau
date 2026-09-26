--[[
	Quests: tutorial (first session), dailies, achievements and codes.

	Progress is driven by bus topics (see Api.Topics). Each objective names a `topic` and
	an optional `filter` (matched against the topic's detail table) and a `target` count.
	Rewards use the shared reward format: { kind = "coins"|"gems"|"food"|"treats"|"egg"|
	"stardust"|"friendship"|"token"|"xp"|"decor", id = string?, amount = number }.
]]

local Quests = {}

-- Tutorial -----------------------------------------------------------------------
-- Steps run in order. `topic` completes a step; `ack` steps complete when the client
-- acknowledges the dialog (Quests.Ack). `arrow` tells the client what to point at.
Quests.Tutorial = {
	{ id = "hatch_starter", text = "Your first egg is ready! Tap it and choose your monster.", topic = "EggHatched", arrow = "incubator" },
	{
		id = "collect_first",
		text = "Your monster makes coins. Collect the jar!",
		topic = "JarCollected",
		arrow = "jar",
		reward = { { kind = "coins", amount = 300 } },
	},
	{ id = "buy_eggs", text = "Buy 2 Meadow Eggs at the Egg Shop.", topic = "EggBought", target = 2, arrow = "shop" },
	{ id = "hatch_two", text = "Hatch your new eggs.", topic = "EggHatched", target = 2, arrow = "incubator" },
	{
		id = "feed_starter",
		text = "Feed your starter 3 meals.",
		topic = "MonsterFed",
		target = 3,
		arrow = "monster",
		reward = { { kind = "food", id = "sweet", amount = 5 } },
	},
	{ id = "grow_starter", text = "Your starter is ready. Tap Grow Up!", topic = "MonsterEvolved", arrow = "monster" },
	{ id = "clear_stage_1", text = "Win your first battle in Whispering Meadow.", topic = "StageCleared", arrow = "expeditions" },
	{
		id = "clear_stage_2",
		text = "Clear stage 2. Ember beats Sprout!",
		topic = "StageCleared",
		filter = { stage = 2 },
		arrow = "expeditions",
	},
	{
		id = "start_expedition",
		text = "Send your squad on a 15-minute expedition.",
		topic = "ExpeditionStarted",
		arrow = "expeditions",
		reward = { { kind = "egg", id = "grove", amount = 1 } },
	},
	{ id = "weather_intro", text = "Rain! Monsters in pens can get Soaked. Soaked monsters earn ×1.5.", ack = true, arrow = "weather" },
	{
		id = "done",
		text = "You're a real rancher now. Come back soon, your ranch keeps going!",
		ack = true,
		reward = { { kind = "gems", amount = 50 } },
	},
}

-- Dailies ------------------------------------------------------------------------
Quests.DailyCount = 3
Quests.DailyPool = {
	{
		id = "hatch_5",
		text = "Hatch 5 eggs",
		topic = "EggHatched",
		target = 5,
		reward = { { kind = "gems", amount = 10 }, { kind = "treats", amount = 5 } },
	},
	{
		id = "collect_10",
		text = "Collect coin jars 10 times",
		topic = "JarCollected",
		target = 10,
		reward = { { kind = "gems", amount = 10 }, { kind = "food", id = "random", amount = 10 } },
	},
	{
		id = "feed_15",
		text = "Feed monsters 15 times",
		topic = "MonsterFed",
		target = 15,
		reward = { { kind = "gems", amount = 10 }, { kind = "treats", amount = 5 } },
	},
	{ id = "stage_3", text = "Win 3 stage battles", topic = "StageCleared", target = 3, reward = { { kind = "gems", amount = 15 } } },
	{
		id = "expedition_2",
		text = "Claim 2 expeditions",
		topic = "ExpeditionClaimed",
		target = 2,
		reward = { { kind = "gems", amount = 10 }, { kind = "egg", id = "meadow", amount = 2 } },
	},
	{ id = "boss_1", text = "Join a Stampede", topic = "BossJoined", target = 1, reward = { { kind = "gems", amount = 15 } } },
	{
		id = "pet_10",
		text = "Pet 10 monsters on other ranches",
		topic = "PetGiven",
		target = 10,
		reward = { { kind = "friendship", amount = 20 }, { kind = "gems", amount = 5 } },
	},
	{
		id = "breed_1",
		text = "Breed a monster",
		topic = "Bred",
		target = 1,
		reward = { { kind = "gems", amount = 15 } },
		unlock = "breeding",
	},
	{
		id = "levelup_10",
		text = "Level up monsters 10 times",
		topic = "MonsterLeveled",
		target = 10,
		reward = { { kind = "treats", amount = 10 }, { kind = "gems", amount = 5 } },
	},
}

-- Achievements ------------------------------------------------------------------
Quests.Achievements = {
	{ id = "hatch_100", text = "Hatch 100 eggs", topic = "EggHatched", target = 100, reward = { { kind = "gems", amount = 100 } } },
	{
		id = "first_epic",
		text = "Hatch an Epic",
		topic = "EggHatched",
		filter = { minRarity = 4 },
		target = 1,
		reward = { { kind = "gems", amount = 25 } },
	},
	{
		id = "first_legendary",
		text = "Hatch a Legendary",
		topic = "EggHatched",
		filter = { minRarity = 5 },
		target = 1,
		reward = { { kind = "gems", amount = 75 } },
	},
	{
		id = "first_golden",
		text = "Hatch a Golden monster",
		topic = "EggHatched",
		filter = { variant = 1 },
		target = 1,
		reward = { { kind = "gems", amount = 50 } },
	},
	{ id = "first_mutation", text = "Get a weather mutation", topic = "Mutated", target = 1, reward = { { kind = "gems", amount = 25 } } },
	{
		id = "first_hybrid",
		text = "Breed a hybrid",
		topic = "Bred",
		filter = { hybrid = true },
		target = 1,
		reward = { { kind = "gems", amount = 100 } },
	},
	{
		id = "clear_meadow",
		text = "Clear Whispering Meadow",
		topic = "StageCleared",
		filter = { region = "meadow", stage = 20 },
		target = 1,
		reward = { { kind = "egg", id = "crystal", amount = 1 } },
	},
	{
		id = "clear_coral",
		text = "Clear Coral Coast",
		topic = "StageCleared",
		filter = { region = "coral", stage = 20 },
		target = 1,
		reward = { { kind = "gems", amount = 150 } },
	},
	-- Update 1.1 · Coral Depths
	{
		id = "clear_depths",
		text = "Clear the Coral Depths",
		topic = "StageCleared",
		filter = { region = "coral", stage = 30 },
		target = 1,
		reward = { { kind = "gems", amount = 200 }, { kind = "egg", id = "pearl", amount = 1 } },
	},
	{
		id = "hatch_pearl_5",
		text = "Hatch 5 Pearl Eggs",
		topic = "EggHatched",
		filter = { egg = "pearl" },
		target = 5,
		reward = { { kind = "decor", id = "tide_pool", amount = 1 } },
	},
	{
		id = "pearl_mutation",
		text = "Get the Pearl mutation (Soaked + Starstruck)",
		topic = "Mutated",
		filter = { mutation = "pearl" },
		target = 1,
		reward = { { kind = "gems", amount = 150 } },
	},
	-- Update 3.1 · Club Wars
	{
		id = "club_war",
		text = "Claim a Club Wars reward",
		topic = "ClubWarClaimed",
		target = 1,
		reward = { { kind = "gems", amount = 50 } },
	},
	{
		id = "club_war_gold",
		text = "Reach the Gold league with your club",
		topic = "ClubWarClaimed",
		filter = { league = "gold" },
		target = 1,
		reward = { { kind = "egg", id = "crystal", amount = 1 }, { kind = "ribbons", amount = 30 } },
	},
	-- Update 3.0 · Year Two
	{
		id = "clear_dunes",
		text = "Clear the Mirage Dunes",
		topic = "StageCleared",
		filter = { region = "dunes", stage = 20 },
		target = 1,
		reward = { { kind = "gems", amount = 250 }, { kind = "egg", id = "dunes", amount = 2 } },
	},
	{
		id = "race_win_10",
		text = "Win 10 monster races",
		topic = "RaceFinished",
		filter = { place = 1 },
		target = 10,
		reward = { { kind = "gems", amount = 100 }, { kind = "ribbons", amount = 40 } },
	},
	{
		id = "design_first",
		text = "Publish a Workshop design",
		topic = "DesignPublished",
		target = 1,
		reward = { { kind = "ribbons", amount = 40 } },
	},
	{
		id = "hub_ad",
		text = "Post an ad on the Trade Board",
		topic = "HubAdPosted",
		target = 1,
		reward = { { kind = "gems", amount = 20 } },
	},
	-- Update 2.1 · Arena & Raids
	{
		id = "arena_win_10",
		text = "Win 10 arena battles",
		topic = "ArenaBattle",
		filter = { won = true },
		target = 10,
		reward = { { kind = "gems", amount = 100 }, { kind = "accessory", id = "gold_medal", amount = 1 } },
	},
	{
		id = "raid_win",
		text = "Defeat a raid boss with your team",
		topic = "RaidFinished",
		filter = { win = true },
		target = 1,
		reward = { { kind = "gems", amount = 100 } },
	},
	{
		id = "raid_wyrm",
		text = "Defeat the Umbral Wyrm",
		topic = "RaidFinished",
		filter = { raid = "wyrm", win = true },
		target = 1,
		reward = { { kind = "egg", id = "raid", amount = 1 }, { kind = "accessory", id = "hero_cape", amount = 1 } },
	},
	-- Update 3.2 · Frostbite Glacier + Level 70
	{
		id = "raid_leviathan",
		text = "Defeat the Frost Leviathan",
		topic = "RaidFinished",
		filter = { raid = "leviathan", win = true },
		target = 1,
		reward = { { kind = "egg", id = "leviathan", amount = 1 }, { kind = "gems", amount = 100 } },
	},
	{
		id = "clear_glacier",
		text = "Clear the Frostbite Glacier",
		topic = "StageCleared",
		filter = { region = "glacier", stage = 20 },
		target = 1,
		reward = { { kind = "gems", amount = 250 }, { kind = "egg", id = "glacier", amount = 2 } },
	},
	-- Update 2.0 · Light & Void
	{
		id = "sky_first",
		text = "Collect a wind crystal on the Sky Islands",
		topic = "CrystalCollected",
		target = 1,
		reward = { { kind = "gems", amount = 50 } },
	},
	{
		id = "sky_crystals_50",
		text = "Collect 50 wind crystals",
		topic = "CrystalCollected",
		target = 50,
		reward = { { kind = "egg", id = "sky", amount = 1 }, { kind = "gems", amount = 100 } },
	},
	{
		id = "clear_sky",
		text = "Clear the Sky Islands",
		topic = "StageCleared",
		filter = { region = "sky", stage = 20 },
		target = 1,
		reward = { { kind = "gems", amount = 250 }, { kind = "egg", id = "sky", amount = 2 } },
	},
	{
		id = "ride_1",
		text = "Ride one of your monsters",
		topic = "Mounted",
		target = 1,
		reward = { { kind = "accessory", id = "backpack", amount = 1 } },
	},
	{
		id = "surf_10",
		text = "Finish 10 surf runs at the Surf Shack",
		topic = "SurfRun",
		target = 10,
		reward = { { kind = "accessory", id = "surfboard", amount = 1 } },
	},
	-- Update 1.5 · Showtime
	{
		id = "contest_win",
		text = "Win a Monster Contest",
		topic = "ContestPlaced",
		filter = { rank = 1 },
		target = 1,
		reward = { { kind = "gems", amount = 100 }, { kind = "accessory", id = "halo", amount = 1 } },
	},
	{
		id = "contest_enter_10",
		text = "Enter 10 Monster Contests",
		topic = "ContestEntered",
		target = 10,
		reward = { { kind = "ribbons", amount = 50 } },
	},
	{
		id = "contest_vote_25",
		text = "Vote on 25 runway walks",
		topic = "ContestVoted",
		target = 25,
		reward = { { kind = "ribbons", amount = 30 }, { kind = "gems", amount = 50 } },
	},
	{
		id = "accessories_10",
		text = "Collect 10 accessories",
		topic = "AccessoryGained",
		target = 10,
		reward = { { kind = "accessory", id = "flower_crown", amount = 1 } },
	},
	-- Update 1.4 · Rebirth + Spring Bloom
	{
		id = "rebirth_1",
		text = "Rebirth your ranch",
		topic = "Rebirthed",
		target = 1,
		reward = { { kind = "gems", amount = 200 }, { kind = "stardust", amount = 100 } },
	},
	{
		id = "egghunt_20",
		text = "Find 20 hidden eggs in the Spring Bloom egg hunt",
		topic = "EggFound",
		target = 20,
		reward = { { kind = "gems", amount = 100 }, { kind = "decor", id = "tulip_patch", amount = 1 } },
	},
	{
		id = "blossom_mutation",
		text = "Get the Blossom mutation in a Pollen Storm",
		topic = "Mutated",
		filter = { mutation = "blossom" },
		target = 1,
		reward = { { kind = "gems", amount = 100 } },
	},
	{
		id = "retire_1",
		text = "Retire a monster to the Hall of Fame",
		topic = "Retired",
		target = 1,
		reward = { { kind = "stardust", amount = 50 } },
	},
	{
		id = "boss_10",
		text = "Join 10 Stampedes",
		topic = "BossJoined",
		target = 10,
		reward = { { kind = "egg", id = "stampede", amount = 1 } },
	},
}

-- Ranch Pass (6-week seasons). Pass XP comes from dailies and achievements; premium
-- rewards need the Ranch Pass product bought for that season. `PassAt(now)` is the season
-- that counts at `now`: the latest one that has started (the first before any has), so
-- earned tiers stay claimable in the gap after a season ends until the next one starts.
local function tier(free, premium)
	return { free = free, premium = premium }
end
Quests.Seasons = {
	{
		season = 1,
		name = "Frostfall Ranch",
		startsAt = 1797292800, -- 2026-12-15 00:00 UTC
		endsAt = 1800921600, -- 2027-01-26 00:00 UTC
		xpPerTier = 300,
		xpPerDaily = 100,
		xpPerAchievement = 200,
		tiers = {
			tier({ { kind = "coins", amount = 2000 } }, { { kind = "gems", amount = 30 } }),
			tier({ { kind = "food", id = "random", amount = 10 } }, { { kind = "egg", id = "grove", amount = 2 } }),
			tier({ { kind = "treats", amount = 10 } }, { { kind = "decor", id = "flower_bed", amount = 1 } }),
			tier({ { kind = "egg", id = "grove", amount = 1 } }, { { kind = "gems", amount = 40 } }),
			tier({ { kind = "gems", amount = 15 } }, { { kind = "egg", id = "crystal", amount = 1 } }),
			tier({ { kind = "coins", amount = 20000 } }, { { kind = "treats", amount = 30 } }),
			tier({ { kind = "friendship", amount = 30 } }, { { kind = "decor", id = "lantern", amount = 1 } }),
			tier({ { kind = "egg", id = "crystal", amount = 1 } }, { { kind = "gems", amount = 60 } }),
			tier({ { kind = "treats", amount = 20 } }, { { kind = "egg", id = "crystal", amount = 2 } }),
			tier({ { kind = "gems", amount = 25 } }, { { kind = "egg", id = "royal", amount = 1 } }),
			tier({ { kind = "coins", amount = 150000 } }, { { kind = "decor", id = "rainbow_arch", amount = 1 } }),
			tier({ { kind = "egg", id = "crystal", amount = 1 } }, { { kind = "gems", amount = 80 } }),
			tier({ { kind = "food", id = "random", amount = 30 } }, { { kind = "egg", id = "stampede", amount = 1 } }),
			tier({ { kind = "gems", amount = 30 } }, { { kind = "stardust", amount = 100 } }),
			tier({ { kind = "egg", id = "royal", amount = 1 } }, { { kind = "monster", id = "snowmitt", rarity = 5, amount = 1 } }),
		},
	},
	-- Update 1.4 · Season 2 "Spring Stars": Stardust for the skill tree, spring decor and a
	-- Legendary Budling at the top of the premium track.
	{
		season = 2,
		name = "Spring Stars",
		startsAt = 1806764400, -- Sat 3 Apr 2027, 15:00 UTC (update 1.4)
		endsAt = 1810393200, -- Sat 15 May 2027, 15:00 UTC
		xpPerTier = 300,
		xpPerDaily = 100,
		xpPerAchievement = 200,
		tiers = {
			tier({ { kind = "coins", amount = 5000 } }, { { kind = "gems", amount = 30 } }),
			tier({ { kind = "stardust", amount = 30 } }, { { kind = "egg", id = "grove", amount = 3 } }),
			tier({ { kind = "treats", amount = 15 } }, { { kind = "decor", id = "tulip_patch", amount = 1 } }),
			tier({ { kind = "egg", id = "grove", amount = 2 } }, { { kind = "stardust", amount = 80 } }),
			tier({ { kind = "gems", amount = 20 } }, { { kind = "egg", id = "crystal", amount = 1 } }),
			tier({ { kind = "food", id = "random", amount = 20 } }, { { kind = "treats", amount = 40 } }),
			tier({ { kind = "stardust", amount = 50 } }, { { kind = "gems", amount = 60 } }),
			tier({ { kind = "egg", id = "crystal", amount = 1 } }, { { kind = "decor", id = "bloom_arch", amount = 1 } }),
			tier({ { kind = "friendship", amount = 40 } }, { { kind = "egg", id = "crystal", amount = 2 } }),
			tier({ { kind = "gems", amount = 25 } }, { { kind = "stardust", amount = 150 } }),
			tier({ { kind = "coins", amount = 250000 } }, { { kind = "egg", id = "royal", amount = 1 } }),
			tier({ { kind = "stardust", amount = 80 } }, { { kind = "gems", amount = 80 } }),
			tier({ { kind = "egg", id = "stampede", amount = 1 } }, { { kind = "egg", id = "celestial", amount = 1 } }),
			tier({ { kind = "gems", amount = 30 } }, { { kind = "stardust", amount = 250 } }),
			tier({ { kind = "egg", id = "royal", amount = 1 } }, { { kind = "monster", id = "budling", rarity = 5, amount = 1 } }),
		},
	},
	-- Update 1.5 · Season 3 "Showtime": accessories (two pass-only), Contest Ribbons and gems.
	{
		season = 3,
		name = "Showtime",
		startsAt = 1810393200, -- Sat 15 May 2027, 15:00 UTC (update 1.5)
		endsAt = 1814022000, -- Sat 26 Jun 2027, 15:00 UTC
		xpPerTier = 300,
		xpPerDaily = 100,
		xpPerAchievement = 200,
		tiers = {
			tier({ { kind = "ribbons", amount = 20 } }, { { kind = "gems", amount = 30 } }),
			tier({ { kind = "coins", amount = 10000 } }, { { kind = "accessory", id = "party_hat", amount = 1 } }),
			tier({ { kind = "accessory", id = "mustache", amount = 1 } }, { { kind = "egg", id = "crystal", amount = 1 } }),
			tier({ { kind = "treats", amount = 20 } }, { { kind = "ribbons", amount = 40 } }),
			tier({ { kind = "gems", amount = 20 } }, { { kind = "accessory", id = "sunglasses", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 25 } }, { { kind = "gems", amount = 50 } }),
			tier({ { kind = "egg", id = "grove", amount = 2 } }, { { kind = "accessory", id = "royal_cape", amount = 1 } }),
			tier({ { kind = "accessory", id = "red_scarf", amount = 1 } }, { { kind = "egg", id = "crystal", amount = 2 } }),
			tier({ { kind = "friendship", amount = 40 } }, { { kind = "ribbons", amount = 60 } }),
			tier({ { kind = "gems", amount = 25 } }, { { kind = "accessory", id = "rainbow_wings", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 30 } }, { { kind = "egg", id = "royal", amount = 1 } }),
			tier({ { kind = "egg", id = "crystal", amount = 1 } }, { { kind = "gems", amount = 80 } }),
			tier({ { kind = "coins", amount = 300000 } }, { { kind = "accessory", id = "top_hat", amount = 1 } }),
			tier({ { kind = "gems", amount = 30 } }, { { kind = "ribbons", amount = 100 } }),
			tier({ { kind = "accessory", id = "bow_tie", amount = 1 } }, { { kind = "accessory", id = "starlight_crown", amount = 1 } }),
		},
	},
	-- Update 2.0 · Season 4 "Summer Splash": beachwear, Sky and Splash Eggs.
	{
		season = 4,
		name = "Summer Splash",
		startsAt = 1814022000, -- Sat 26 Jun 2027, 15:00 UTC
		endsAt = 1817650800, -- Sat 7 Aug 2027, 15:00 UTC
		xpPerTier = 300,
		xpPerDaily = 100,
		xpPerAchievement = 200,
		tiers = {
			tier({ { kind = "coins", amount = 15000 } }, { { kind = "gems", amount = 30 } }),
			tier({ { kind = "treats", amount = 20 } }, { { kind = "accessory", id = "sun_hat", amount = 1 } }),
			tier({ { kind = "accessory", id = "flower_lei", amount = 1 } }, { { kind = "egg", id = "crystal", amount = 1 } }),
			tier({ { kind = "gems", amount = 20 } }, { { kind = "stardust", amount = 100 } }),
			tier({ { kind = "egg", id = "grove", amount = 2 } }, { { kind = "accessory", id = "sunglasses", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 25 } }, { { kind = "gems", amount = 60 } }),
			tier({ { kind = "food", id = "random", amount = 30 } }, { { kind = "egg", id = "sky", amount = 1 } }),
			tier({ { kind = "accessory", id = "snorkel", amount = 1 } }, { { kind = "egg", id = "crystal", amount = 2 } }),
			tier({ { kind = "gems", amount = 25 } }, { { kind = "accessory", id = "surfboard", amount = 1 } }),
			tier({ { kind = "coins", amount = 400000 } }, { { kind = "egg", id = "royal", amount = 1 } }),
			tier({ { kind = "egg", id = "sky", amount = 1 } }, { { kind = "gems", amount = 80 } }),
			tier({ { kind = "stardust", amount = 60 } }, { { kind = "egg", id = "celestial", amount = 1 } }),
			tier({ { kind = "gems", amount = 30 } }, { { kind = "stardust", amount = 250 } }),
			tier({ { kind = "egg", id = "royal", amount = 1 } }, { { kind = "egg", id = "sky", amount = 2 } }),
			tier(
				{ { kind = "accessory", id = "pearl_necklace", amount = 1 } },
				{ { kind = "monster", id = "surfotter", rarity = 5, amount = 1 } }
			),
		},
	},
	-- Update 2.1 · Season 5 "Harvest Moon": spooky accessories, Raid and Harvest Eggs.
	{
		season = 5,
		name = "Harvest Moon",
		startsAt = 1822489200, -- Sat 2 Oct 2027, 15:00 UTC (update 2.1)
		endsAt = 1826118000, -- Sat 13 Nov 2027, 15:00 UTC
		xpPerTier = 300,
		xpPerDaily = 100,
		xpPerAchievement = 200,
		tiers = {
			tier({ { kind = "coins", amount = 20000 } }, { { kind = "gems", amount = 30 } }),
			tier({ { kind = "treats", amount = 20 } }, { { kind = "accessory", id = "witch_hat", amount = 1 } }),
			tier({ { kind = "accessory", id = "devil_horns", amount = 1 } }, { { kind = "egg", id = "crystal", amount = 2 } }),
			tier({ { kind = "gems", amount = 20 } }, { { kind = "stardust", amount = 120 } }),
			tier({ { kind = "egg", id = "grove", amount = 2 } }, { { kind = "accessory", id = "bat_wings", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 30 } }, { { kind = "gems", amount = 60 } }),
			tier({ { kind = "food", id = "random", amount = 30 } }, { { kind = "egg", id = "raid", amount = 1 } }),
			tier({ { kind = "accessory", id = "hero_mask", amount = 1 } }, { { kind = "egg", id = "sky", amount = 1 } }),
			tier({ { kind = "gems", amount = 25 } }, { { kind = "egg", id = "royal", amount = 1 } }),
			tier({ { kind = "coins", amount = 500000 } }, { { kind = "stardust", amount = 200 } }),
			tier({ { kind = "egg", id = "crystal", amount = 1 } }, { { kind = "gems", amount = 80 } }),
			tier({ { kind = "stardust", amount = 80 } }, { { kind = "egg", id = "raid", amount = 1 } }),
			tier({ { kind = "gems", amount = 30 } }, { { kind = "egg", id = "celestial", amount = 1 } }),
			tier({ { kind = "egg", id = "royal", amount = 1 } }, { { kind = "egg", id = "raid", amount = 2 } }),
			tier({ { kind = "accessory", id = "halo", amount = 1 } }, { { kind = "monster", id = "pumpkit", rarity = 5, amount = 1 } }),
		},
	},
	-- Update 3.0 · Season 6 "Year Two": Dune Eggs, ribbons for the Workshop, a Legendary Sandskip.
	{
		season = 6,
		name = "Year Two",
		startsAt = 1828537200, -- Sat 11 Dec 2027, 15:00 UTC (update 3.0)
		endsAt = 1832166000, -- Sat 22 Jan 2028, 15:00 UTC
		xpPerTier = 300,
		xpPerDaily = 100,
		xpPerAchievement = 200,
		tiers = {
			tier({ { kind = "coins", amount = 25000 } }, { { kind = "gems", amount = 30 } }),
			tier({ { kind = "ribbons", amount = 20 } }, { { kind = "accessory", id = "party_hat", amount = 1 } }),
			tier({ { kind = "treats", amount = 25 } }, { { kind = "egg", id = "dunes", amount = 1 } }),
			tier({ { kind = "gems", amount = 20 } }, { { kind = "stardust", amount = 120 } }),
			tier({ { kind = "egg", id = "grove", amount = 2 } }, { { kind = "ribbons", amount = 40 } }),
			tier({ { kind = "ribbons", amount = 30 } }, { { kind = "gems", amount = 60 } }),
			tier({ { kind = "food", id = "random", amount = 30 } }, { { kind = "egg", id = "raid", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 25 } }, { { kind = "egg", id = "dunes", amount = 1 } }),
			tier({ { kind = "gems", amount = 25 } }, { { kind = "egg", id = "royal", amount = 1 } }),
			tier({ { kind = "coins", amount = 750000 } }, { { kind = "stardust", amount = 200 } }),
			tier({ { kind = "egg", id = "crystal", amount = 1 } }, { { kind = "gems", amount = 80 } }),
			tier({ { kind = "stardust", amount = 80 } }, { { kind = "egg", id = "dunes", amount = 1 } }),
			tier({ { kind = "gems", amount = 30 } }, { { kind = "egg", id = "celestial", amount = 1 } }),
			tier({ { kind = "egg", id = "royal", amount = 1 } }, { { kind = "egg", id = "dunes", amount = 2 } }),
			tier({ { kind = "ribbons", amount = 60 } }, { { kind = "monster", id = "sandskip", rarity = 5, amount = 1 } }),
		},
	},
	-- Update 3.1 · Season 7 "Club Wars": Lantern Eggs, club-friendly rewards, a Legendary Tinselkit.
	{
		season = 7,
		name = "Club Wars",
		startsAt = 1832166000, -- Sat 22 Jan 2028, 15:00 UTC (right after Season 6)
		endsAt = 1835794800, -- Sat 4 Mar 2028, 15:00 UTC
		xpPerTier = 300,
		xpPerDaily = 100,
		xpPerAchievement = 200,
		tiers = {
			tier({ { kind = "coins", amount = 30000 } }, { { kind = "gems", amount = 30 } }),
			tier({ { kind = "treats", amount = 25 } }, { { kind = "egg", id = "lantern", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 25 } }, { { kind = "egg", id = "crystal", amount = 1 } }),
			tier({ { kind = "gems", amount = 20 } }, { { kind = "stardust", amount = 120 } }),
			tier({ { kind = "egg", id = "grove", amount = 2 } }, { { kind = "egg", id = "lantern", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 30 } }, { { kind = "gems", amount = 60 } }),
			tier({ { kind = "food", id = "random", amount = 30 } }, { { kind = "egg", id = "raid", amount = 1 } }),
			tier({ { kind = "coins", amount = 400000 } }, { { kind = "egg", id = "dunes", amount = 1 } }),
			tier({ { kind = "gems", amount = 25 } }, { { kind = "egg", id = "royal", amount = 1 } }),
			tier({ { kind = "coins", amount = 900000 } }, { { kind = "stardust", amount = 200 } }),
			tier({ { kind = "egg", id = "crystal", amount = 1 } }, { { kind = "gems", amount = 80 } }),
			tier({ { kind = "stardust", amount = 80 } }, { { kind = "egg", id = "lantern", amount = 2 } }),
			tier({ { kind = "gems", amount = 30 } }, { { kind = "egg", id = "celestial", amount = 1 } }),
			tier({ { kind = "egg", id = "royal", amount = 1 } }, { { kind = "egg", id = "raid", amount = 2 } }),
			tier({ { kind = "ribbons", amount = 60 } }, { { kind = "monster", id = "tinselkit", rarity = 5, amount = 1 } }),
		},
	},
	-- Update 3.2 · Season 8 "Frostbite": Glacier Eggs, Leviathan Eggs on the premium track, a Legendary Pengling.
	{
		season = 8,
		name = "Frostbite",
		startsAt = 1835794800, -- Sat 4 Mar 2028, 15:00 UTC (right after Season 7)
		endsAt = 1839423600, -- Sat 15 Apr 2028, 15:00 UTC
		xpPerTier = 300,
		xpPerDaily = 100,
		xpPerAchievement = 200,
		tiers = {
			tier({ { kind = "coins", amount = 35000 } }, { { kind = "gems", amount = 30 } }),
			tier({ { kind = "treats", amount = 25 } }, { { kind = "egg", id = "glacier", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 25 } }, { { kind = "egg", id = "crystal", amount = 1 } }),
			tier({ { kind = "gems", amount = 20 } }, { { kind = "stardust", amount = 120 } }),
			tier({ { kind = "egg", id = "glacier", amount = 1 } }, { { kind = "ribbons", amount = 40 } }),
			tier({ { kind = "ribbons", amount = 30 } }, { { kind = "gems", amount = 60 } }),
			tier({ { kind = "food", id = "random", amount = 30 } }, { { kind = "egg", id = "leviathan", amount = 1 } }),
			tier({ { kind = "coins", amount = 450000 } }, { { kind = "egg", id = "glacier", amount = 1 } }),
			tier({ { kind = "gems", amount = 25 } }, { { kind = "egg", id = "royal", amount = 1 } }),
			tier({ { kind = "coins", amount = 1000000 } }, { { kind = "stardust", amount = 200 } }),
			tier({ { kind = "egg", id = "glacier", amount = 1 } }, { { kind = "gems", amount = 80 } }),
			tier({ { kind = "stardust", amount = 80 } }, { { kind = "egg", id = "glacier", amount = 2 } }),
			tier({ { kind = "gems", amount = 30 } }, { { kind = "egg", id = "celestial", amount = 1 } }),
			tier({ { kind = "egg", id = "royal", amount = 1 } }, { { kind = "egg", id = "leviathan", amount = 1 } }),
			tier({ { kind = "ribbons", amount = 60 } }, { { kind = "monster", id = "pengling", rarity = 5, amount = 1 } }),
		},
	},
}
Quests.Pass = Quests.Seasons[1] -- kept for older call sites; prefer Quests.PassAt(now)

function Quests.PassAt(now: number)
	local current = Quests.Seasons[1]
	for _, season in Quests.Seasons do
		if now >= season.startsAt and season.startsAt >= current.startsAt then
			current = season
		end
	end
	return current
end

-- The Ranch Pass is sold only while a season runs (startsAt <= now < endsAt): before the first
-- season and in the gap between two there is nothing to unlock yet. A pass bought anyway is
-- banked by the Quests system and unlocks the next season.
function Quests.PassOnSale(now: number): boolean
	local season = Quests.PassAt(now)
	return now >= season.startsAt and now < season.endsAt
end

-- The first season that starts after `now`, or nil when none is scheduled yet.
function Quests.NextSeason(now: number)
	local nextSeason = nil
	for _, season in Quests.Seasons do
		if season.startsAt > now and (nextSeason == nil or season.startsAt < nextSeason.startsAt) then
			nextSeason = season
		end
	end
	return nextSeason
end

-- Codes (case-insensitive). `expires` is a Unix time or nil.
Quests.Codes = {
	RANCH = { reward = { { kind = "gems", amount = 50 } } },
	FROSTFALL = { reward = { { kind = "token", id = "frostfall", amount = 100 } }, expires = 1798761600 },
	GROUP = { reward = { { kind = "egg", id = "crystal", amount = 1 } }, requiresGroup = true },
	-- Update 3.2 launch code (expires 1 Apr 2028, the 3.3 launch).
	FROSTBITE = { reward = { { kind = "egg", id = "glacier", amount = 1 }, { kind = "gems", amount = 50 } }, expires = 1838214000 },
	-- Update 3.1 launch code: Lantern Coins for the Lunar Lanterns rerun (expires 26 Feb 2028).
	CLUBWARS = {
		reward = { { kind = "token", id = "lunarlanterns", amount = 150 }, { kind = "gems", amount = 50 } },
		expires = 1835190000,
	},
	-- Frostfall returns (3.0.1): Snowflakes for the rerun (expires 15 Jan 2028).
	FROSTFALL27 = { reward = { { kind = "token", id = "frostfall", amount = 150 } }, expires = 1831561200 },
	-- Update 3.0 launch code (expires 1 Jan 2028).
	YEARTWO = { reward = { { kind = "egg", id = "dunes", amount = 1 }, { kind = "gems", amount = 50 } }, expires = 1830351600 },
	-- Update 2.1 launch code (expires 30 Oct 2027).
	ARENAANDRAIDS = { reward = { { kind = "egg", id = "raid", amount = 1 }, { kind = "gems", amount = 50 } }, expires = 1824908400 },
	-- Update 2.0 launch code (expires 14 Aug 2027).
	LIGHTANDVOID = { reward = { { kind = "egg", id = "sky", amount = 1 }, { kind = "gems", amount = 50 } }, expires = 1818255600 },
	-- Update 1.5 launch code (expires 26 Jun 2027).
	SHOWTIME = {
		reward = { { kind = "accessory", id = "party_hat", amount = 1 }, { kind = "ribbons", amount = 25 } },
		expires = 1814022000,
	},
	-- Update 1.1 launch code (expires 6 Feb 2027).
	CORALDEPTHS = { reward = { { kind = "egg", id = "pearl", amount = 1 }, { kind = "gems", amount = 50 } }, expires = 1801872000 },
}
Quests.GroupId = 0 -- set to the Roblox group id for the GROUP code

-- Topics whose detail carries a count (progress += detail[field]); every other topic counts 1.
Quests.CountField = { EggBought = "amount", AccessoryGained = "amount" }

-- Scripted first-session rain (Flags.TutorialScriptedRain): when `step` becomes current the
-- server starts `weather` for `seconds` if the sky is clear, and guarantees `mutation`.
Quests.TutorialRain = { step = "weather_intro", weather = "rain", seconds = 90, mutation = "soaked" }

return Quests
