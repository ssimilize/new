--[[
	Economy tuning. Starting values from the GDD; tune with telemetry.
	All times are seconds, all prices are coins unless stated otherwise.
]]

local Economy = {}

-- Life stages ---------------------------------------------------------------
Economy.Stages = {
	[1] = { name = "Baby", coinMult = 0.4, statMult = 0.55, levelCap = 10, scale = 0.6 },
	[2] = { name = "Teen", coinMult = 0.7, statMult = 0.8, levelCap = 25, scale = 0.8 },
	[3] = { name = "Adult", coinMult = 1.0, statMult = 1.0, levelCap = nil, scale = 1.0 },
}
Economy.AdultLevelCapBase = 40
Economy.AdultLevelCapPerStar = 2 -- 5★ adult caps at level 50

Economy.CoinLevelGrowth = 1.07 -- coin output × 1.07 per level above 1
Economy.StatPerLevel = 0.06 -- stats × (1 + 0.06 × (lv − 1))
Economy.StarMult = { 1.0, 1.25, 1.6, 2.0, 2.6 }

function Economy.LevelCost(level: number): { coins: number, treats: number }
	-- Cost to go from `level` to `level + 1`.
	return { coins = math.floor(50 * 1.12 ^ level), treats = math.ceil(level / 5) }
end

-- Growth: requirements to leave a stage (index = current stage), timers by rarity index.
Economy.Growth = {
	[1] = { meals = 3, seconds = { 120, 300, 900, 2700, 7200, 14400 } },
	[2] = { meals = 5, seconds = { 300, 900, 2700, 7200, 18000, 36000 } },
}
Economy.TutorialGrowSeconds = 15 -- first ever growth during the tutorial

-- Mood ------------------------------------------------------------------------
Economy.Mood = {
	start = 70,
	max = 100,
	feedGain = 6,
	petGain = 10,
	decayEvery = 300, -- online only; mood is frozen while offline
	decayAmount = 2,
	floor = 0,
}
function Economy.MoodMult(mood: number): number
	return 0.9 + math.clamp(mood, 0, 100) / 500 -- 0.90 .. 1.10
end

-- Ranch -----------------------------------------------------------------------
Economy.Pens = {
	max = 6,
	unlocks = { "pen_1", "pen_2", "pen_3", "pen_4", "pen_5", "pen_6" },
	buyCost = { 0, 15000, 500000, 15000000, 400000000, 10000000000 },
	startCapacity = 6,
	maxCapacity = 10,
	capacityCost = { [6] = 5000, [7] = 40000, [8] = 300000, [9] = 2000000 }, -- cost to go from n to n+1
}
Economy.JarTiers = {
	{ seconds = 3600, cost = 0 },
	{ seconds = 7200, cost = 20000 },
	{ seconds = 14400, cost = 400000 },
	{ seconds = 28800, cost = 8000000 },
}
Economy.VipJarBonusSeconds = 4 * 3600

Economy.Incubators = {
	baseSlots = 1,
	slotUnlocks = { "incubator_1", "incubator_2", "incubator_3", "incubator_4" }, -- earned slots
	passSlots = 1, -- Extra Incubator pass
	maxSlots = 5,
	speedTiers = { 0, 0.1, 0.2, 0.3, 0.4 }, -- hatch time reduction
	speedCost = { 0, 10000, 150000, 2000000, 30000000 },
}

Economy.Barn = {
	capacity = { 30, 60, 100, 150, 200 },
	cost = { 0, 25000, 250000, 2500000, 25000000 },
	bigBarnPassBonus = 100,
}

Economy.Garden = {
	unlock = "garden",
	plots = { 2, 4, 6, 8 },
	cost = { 0, 50000, 1000000, 20000000 },
	growSeconds = 600,
	yield = 5,
}

-- Food store ---------------------------------------------------------------------
Economy.FoodPrice = 20

-- Selling and value ------------------------------------------------------------
Economy.SellSeconds = 600 -- a monster sells for 10 minutes of its current coin output
Economy.SellMinimum = 25
Economy.ValueSeconds = 3600 -- "value" (breeding fee base) = 1 hour of output

-- Global modifiers --------------------------------------------------------------
Economy.FriendBoost = { perFriend = 0.10, max = 0.40 }
Economy.DoubleCoinsMult = 2
Economy.OfflineMaxSeconds = 7 * 24 * 3600

-- Storage ------------------------------------------------------------------------
Economy.MaxEggs = 200

-- Ranch & eggs runtime (S3) --------------------------------------------------------
Economy.RanchTickSeconds = 10 -- jar settle, auto-collect (pass) and rain garden tick
Economy.IncubatorSpeedCap = 0.75 -- total hatch-time reduction from every source
Economy.WelcomeBackMinSeconds = 300 -- shorter absences skip the Welcome Back screen
Economy.StartTheme = "wood" -- pen theme of a new pen (free, always owned)

return Economy
