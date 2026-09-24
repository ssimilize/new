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
	{ id = "hatch_starter", text = "Your first egg is hatching! Tap the incubator.", topic = "EggHatched", arrow = "incubator" },
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

-- Codes (case-insensitive). `expires` is a Unix time or nil.
Quests.Codes = {
	RANCH = { reward = { { kind = "gems", amount = 50 } } },
	FROSTFALL = { reward = { { kind = "token", id = "frostfall", amount = 100 } }, expires = 1798761600 },
	GROUP = { reward = { { kind = "egg", id = "crystal", amount = 1 } }, requiresGroup = true },
}
Quests.GroupId = 0 -- set to the Roblox group id for the GROUP code

return Quests
