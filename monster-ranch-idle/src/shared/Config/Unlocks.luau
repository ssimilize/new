--[[
	Ranch Level: the player's main progress bar. `Features` maps an unlock key to the
	Ranch Level that unlocks it. Systems check keys with Progression:IsUnlocked(player, key).

	The level cap is date-gated like regions: `LevelCaps` lists { level, from } steps (unix
	seconds, Saturdays 15:00 UTC) and `MaxLevelAt(now)` is the cap in force at `now`.
	`MaxLevel` is the all-time ceiling (the last step).
]]

local Unlocks = {}

Unlocks.MaxLevel = 70

-- Update 3.2 raises the cap from 60 to 70 when Frostbite Glacier opens (Sat 11 Mar 2028).
Unlocks.LevelCaps = {
	{ level = 60, from = 0 },
	{ level = 70, from = 1836399600 },
}

-- The Ranch Level cap in force at unix time `now`.
function Unlocks.MaxLevelAt(now: number): number
	local cap = Unlocks.LevelCaps[1].level
	for _, step in Unlocks.LevelCaps do
		if now >= step.from then
			cap = math.max(cap, step.level)
		end
	end
	return math.min(cap, Unlocks.MaxLevel)
end

-- XP needed to go from `level` to `level + 1`.
function Unlocks.XPToNext(level: number): number
	return math.floor(40 * level ^ 1.5)
end

Unlocks.Features = {
	egg_meadow = 1,
	pen_1 = 1,
	incubator_1 = 1,
	expeditions = 1,
	region_meadow = 1,
	egg_grove = 3,
	wardrobe = 3,
	incubator_2 = 3,
	boss = 4,
	garden = 5,
	egg_starlit = 5,
	dailies = 5,
	pen_2 = 6,
	contests = 7,
	expedition_slot_2 = 6,
	trading = 8,
	caravans = 8,
	clubs = 8,
	region_coral = 10,
	market = 10,
	egg_crystal = 10,
	breeding = 12,
	pen_3 = 15,
	expedition_slot_3 = 15,
	region_ember = 18,
	coral_depths = 22,
	hall_of_fame = 20,
	arena = 20,
	raids = 30,
	egg_royal = 25,
	pen_4 = 25,
	region_gloom = 28,
	incubator_3 = 30,
	squad_4 = 35,
	pen_5 = 40,
	riding = 16,
	region_sky = 45,
	rebirth = 40,
	region_dunes = 50,
	racing = 16,
	workshop = 12,
	region_glacier = 55,
	-- Update 3.2 · Frostbite Glacier + Level 70
	raid_leviathan = 60,
	incubator_4 = 62,
	pen_6 = 66,
	squad_5 = 70,
	-- Glow-up DR · Deep Reef
	region_reef = 64,
}

-- Player-facing names for the level-up popup.
Unlocks.Names = {
	egg_grove = "Grove Egg",
	wardrobe = "Wardrobe",
	contests = "Monster Contests",
	incubator_2 = "Incubator 2",
	boss = "Stampede boss",
	garden = "Feed Garden",
	egg_starlit = "Starlit Egg",
	dailies = "Daily quests",
	pen_2 = "Pen 2",
	expedition_slot_2 = "Expedition slot 2",
	trading = "Trading",
	caravans = "Caravans",
	clubs = "Clubs",
	region_coral = "Coral Coast",
	market = "Market",
	coral_depths = "Coral Depths",
	egg_crystal = "Crystal Egg",
	breeding = "Breeding Barn",
	pen_3 = "Pen 3",
	expedition_slot_3 = "Expedition slot 3",
	region_ember = "Ember Peaks",
	hall_of_fame = "Hall of Fame",
	arena = "Arena",
	raids = "Raids",
	egg_royal = "Royal Egg",
	pen_4 = "Pen 4",
	region_gloom = "Gloom Hollow",
	incubator_3 = "Incubator 3",
	squad_4 = "Squad size 4",
	pen_5 = "Pen 5",
	riding = "Riding",
	region_sky = "Sky Islands",
	rebirth = "Ranch Rebirth",
	region_dunes = "Mirage Dunes",
	racing = "Monster Racing",
	workshop = "Accessory Workshop",
	region_glacier = "Frostbite Glacier",
	raid_leviathan = "Frost Leviathan raid",
	incubator_4 = "Incubator 4",
	pen_6 = "Pen 6",
	squad_5 = "Squad size 5",
	region_reef = "Deep Reef",
}

-- Unlock keys reached exactly at `level` (for the level-up popup).
function Unlocks.At(level: number): { string }
	local list = {}
	for key, lv in Unlocks.Features do
		if lv == level then
			table.insert(list, key)
		end
	end
	table.sort(list)
	return list
end

-- Ranch XP rewarded for actions (see Progression; systems publish "RanchXP").
Unlocks.XP = {
	growTeen = 15,
	growAdult = 30,
	stageClearBase = 20, -- + stage index
	expeditionPerMinute = 0.5,
	breed = 50,
	bossJoin = 30,
	monsterLevelUp = 2,
	collectJar = 3,
	retire = 100,
	trade = 10,
	buyEgg = 2,
}

return Unlocks
