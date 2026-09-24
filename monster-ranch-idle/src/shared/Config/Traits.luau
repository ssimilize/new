--[[
	Traits. Every monster rolls 2 visible traits and 1 hidden trait (revealed as an Adult).
	`weight` is the roll weight; `hiddenOnly` traits can only appear in the hidden slot.
	`effect` keys are read by the systems that own the behaviour:
	  growthSpeed (Monsters) · mealMult (Monsters) · defPct/atkPct/hpPct/spdPct/allStatPct (Stats)
	  lootPct (Expeditions) · jarCapMinutes (Ranch) · nightAtkPct (BattleSim) · petMoodMult (Social)
	  coinPct / coinPerMutationPct (Formulas) · breedSpeed / extraInherit / goldenOffspringMult (Breeding)
	  mutationMult / starMutationMult (Weather) · bossDmgPct (Boss) · moodFloor (Monsters)
]]

local Traits = {}

Traits.List = {
	{
		id = 1,
		key = "speedy_grower",
		name = "Speedy Grower",
		desc = "Growth timers are 20% shorter.",
		weight = 100,
		effect = { growthSpeed = 0.2 },
	},
	{ id = 2, key = "glutton", name = "Glutton", desc = "Each meal counts double for growth.", weight = 100, effect = { mealMult = 2 } },
	{ id = 3, key = "tough_hide", name = "Tough Hide", desc = "DEF +12%.", weight = 100, effect = { defPct = 0.12 } },
	{ id = 4, key = "brawny", name = "Brawny", desc = "ATK +10%.", weight = 100, effect = { atkPct = 0.10 } },
	{ id = 5, key = "hearty", name = "Hearty", desc = "HP +12%.", weight = 100, effect = { hpPct = 0.12 } },
	{ id = 6, key = "swift", name = "Swift", desc = "SPD +10%.", weight = 100, effect = { spdPct = 0.10 } },
	{ id = 7, key = "cheerful", name = "Cheerful", desc = "Mood never drops below 60.", weight = 100, effect = { moodFloor = 60 } },
	{
		id = 8,
		key = "lucky_paw",
		name = "Lucky Paw",
		desc = "Expedition loot +8% (up to 3 in a squad).",
		weight = 55,
		effect = { lootPct = 0.08 },
	},
	{
		id = 9,
		key = "hoarder",
		name = "Hoarder",
		desc = "Its pen's coin jar holds 30 more minutes.",
		weight = 55,
		effect = { jarCapMinutes = 30 },
	},
	{
		id = 10,
		key = "night_owl",
		name = "Night Owl",
		desc = "ATK +15% during the server's night.",
		weight = 55,
		effect = { nightAtkPct = 0.15 },
	},
	{
		id = 11,
		key = "charmer",
		name = "Charmer",
		desc = "Visitors' petting gives double Mood.",
		weight = 55,
		effect = { petMoodMult = 2 },
	},
	{ id = 12, key = "busy_bee", name = "Busy Bee", desc = "Coin output +8%.", weight = 55, effect = { coinPct = 0.08 } },
	{ id = 13, key = "fertile", name = "Fertile", desc = "Breeding with it is 25% faster.", weight = 55, effect = { breedSpeed = 0.25 } },
	{
		id = 14,
		key = "weather_magnet",
		name = "Weather Magnet",
		desc = "Double mutation chance during weather.",
		weight = 20,
		effect = { mutationMult = 2 },
	},
	{
		id = 15,
		key = "show_off",
		name = "Show-off",
		desc = "+10% coins for each mutation it has.",
		weight = 20,
		effect = { coinPerMutationPct = 0.10 },
	},
	{
		id = 16,
		key = "boss_brawler",
		name = "Boss Brawler",
		desc = "+20% damage against the Stampede.",
		weight = 20,
		effect = { bossDmgPct = 0.2 },
	},
	{
		id = 17,
		key = "firstborn",
		name = "Firstborn",
		desc = "Offspring always inherit one extra trait.",
		weight = 8,
		hiddenOnly = true,
		effect = { extraInherit = 1 },
	},
	{
		id = 18,
		key = "golden_heart",
		name = "Golden Heart",
		desc = "Offspring are 3× more likely to be Golden.",
		weight = 8,
		hiddenOnly = true,
		effect = { goldenOffspringMult = 3 },
	},
	{
		id = 19,
		key = "stargazer",
		name = "Stargazer",
		desc = "Starfall and Aurora mutation chances ×1.5.",
		weight = 8,
		hiddenOnly = true,
		effect = { starMutationMult = 1.5 },
	},
	{
		id = 20,
		key = "ancient_blood",
		name = "Ancient Blood",
		desc = "All stats +5%.",
		weight = 8,
		hiddenOnly = true,
		effect = { allStatPct = 0.05 },
	},
}

Traits.ById = {}
Traits.ByKey = {}
for _, t in Traits.List do
	Traits.ById[t.id] = t
	Traits.ByKey[t.key] = t
end

Traits.VisibleSlots = 2
Traits.FreshRollChance = 0.12 -- breeding: chance each slot rolls a brand-new trait

-- Sums one effect key across a list of trait ids (visible + revealed hidden).
function Traits.Sum(traitIds: { number }, effectKey: string): number
	local total = 0
	for _, id in traitIds do
		local t = Traits.ById[id]
		if t and t.effect[effectKey] then
			total += t.effect[effectKey]
		end
	end
	return total
end

-- Multiplies one effect key across traits (for multiplier-style effects such as mealMult).
function Traits.Product(traitIds: { number }, effectKey: string): number
	local total = 1
	for _, id in traitIds do
		local t = Traits.ById[id]
		if t and t.effect[effectKey] then
			total *= t.effect[effectKey]
		end
	end
	return total
end

return Traits
