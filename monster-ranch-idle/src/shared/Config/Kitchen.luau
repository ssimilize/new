--[[
	Kitchen & Pantry (update 3.10): cook the Feed Garden's food into dishes, keep them in the
	Pantry and serve them to monsters. Rules in Logic/Kitchen, the server in Systems/Kitchen.

	  Recipes   `cost` in food flavours (Currency food.*), plus `fish` (the Fishing system's
	            catch, lowest value first) and `golden` (golden produce from golden seeds, kept in
	            profile.Kitchen.golden). `minutes` on the server clock; `makes` dishes per cook.
	  Slots     BaseSlots, one more at SlotUnlock. A finished slot waits until it is collected.
	  Pantry    at most PantryCap of each dish; a slot whose dish would overflow stays in its slot.
	  Effects   each dish has one (Effects[effect]):
	              meals  counts as MealsPerDish growth meals of the dish's `flavor` (Babies, Teens)
	              mood   fills Mood to the maximum
	              bond   +1 Bond heart
	              job    +JobBoost.pct Job Board output for JobBoost.hours hours (that monster)
	              loot   +LootPct loot on that monster's next expedition
	  Seasonal  (3.11 · Ranch Seasons) a recipe with `season` cooks only in that season
	            (Logic/Seasons.At) and needs at least one `seasonFish` (that season's fish, Config.Fishing)
	            among its `fish`. Dishes already cooked keep working all year.
	  Golden    each harvested Feed Garden food plot has GoldenSeedChance of a Golden seed
	            (seeded per harvest, kitchen unlocked only). A seed planted in a garden plot grows
	            GoldenYield golden produce in GoldenGrowMinutes.
]]

local Kitchen = {}

Kitchen.Unlock = "kitchen"
Kitchen.SlotUnlock = "kitchen_slot_3"
Kitchen.BaseSlots = 2
Kitchen.MaxSlots = 3
Kitchen.PantryCap = 99

Kitchen.MealsPerDish = 3
Kitchen.JobBoost = { pct = 0.20, hours = 2 }
Kitchen.LootPct = 0.05

Kitchen.GoldenSeedChance = 0.05
Kitchen.GoldenGrowMinutes = 30
Kitchen.GoldenYield = 2
Kitchen.Golden = { id = "golden", name = "Golden Honeyfruit", seedName = "Golden seed", color = "#F2C230" }
Kitchen.Fish = { name = "Fish" }

Kitchen.Effects = {
	meals = { id = "meals", desc = "Counts as 3 growth meals" },
	mood = { id = "mood", desc = "Fills Mood to the max" },
	bond = { id = "bond", desc = "+1 Bond heart" },
	job = { id = "job", desc = "+20% Job Board output for 2 hours" },
	loot = { id = "loot", desc = "+5% loot on its next expedition" },
}

-- icon: plate + food shape ("round", "wide", "bowl", "stack"), color, topping color.
Kitchen.Recipes = {
	{
		id = "berry_pie",
		name = "Berry Pie",
		cost = { sweet = 5, savory = 3 },
		minutes = 5,
		effect = "meals",
		flavor = "sweet",
		icon = { shape = "round", color = "#C9824A", top = "#EF6FA8" },
	},
	{
		id = "pepper_stew",
		name = "Pepper Stew",
		cost = { spicy = 5, savory = 3 },
		minutes = 10,
		effect = "job",
		icon = { shape = "bowl", color = "#8A5A3C", top = "#E5484D" },
	},
	{
		id = "lime_tart",
		name = "Lime Tart",
		cost = { sour = 5, sweet = 3 },
		minutes = 10,
		effect = "mood",
		icon = { shape = "round", color = "#E8C27A", top = "#C3D93B" },
	},
	{
		id = "root_roast",
		name = "Root Roast",
		cost = { savory = 6, spicy = 2 },
		minutes = 15,
		effect = "meals",
		flavor = "savory",
		icon = { shape = "wide", color = "#A0703D", top = "#E58B3B" },
	},
	{
		id = "fish_supper",
		name = "Fish Supper",
		cost = { fish = 2, savory = 3 },
		minutes = 20,
		effect = "loot",
		icon = { shape = "wide", color = "#7CA7C9", top = "#F2E3B5" },
	},
	{
		id = "sushi_roll",
		name = "Sushi Roll",
		cost = { fish = 3, sour = 2 },
		minutes = 30,
		effect = "job",
		icon = { shape = "stack", color = "#2F3B35", top = "#F28B6B" },
	},
	{
		id = "golden_honeycake",
		name = "Golden Honeycake",
		cost = { golden = 2, sweet = 5 },
		minutes = 45,
		effect = "bond",
		icon = { shape = "stack", color = "#F2C230", top = "#FFF1B8" },
	},
	{
		id = "golden_feast",
		name = "Golden Feast",
		cost = { golden = 3, sweet = 3, spicy = 3, savory = 3, sour = 3 },
		minutes = 60,
		makes = 2,
		effect = "bond",
		icon = { shape = "wide", color = "#F2C230", top = "#E5484D" },
	},
	-- 3.11 · Ranch Seasons: one per season (appended; never reorder)
	{
		id = "blossom_bento",
		name = "Blossom Bento",
		cost = { fish = 2, sweet = 4 },
		minutes = 20,
		effect = "mood",
		season = "spring",
		seasonFish = "blossom_trout",
		icon = { shape = "stack", color = "#F7A8C8", top = "#FFFFFF" },
	},
	{
		id = "sunny_ceviche",
		name = "Sunny Ceviche",
		cost = { fish = 2, sour = 4 },
		minutes = 20,
		effect = "job",
		season = "summer",
		seasonFish = "sunburst_bass",
		icon = { shape = "bowl", color = "#F2B233", top = "#C3D93B" },
	},
	{
		id = "maple_glazed_carp",
		name = "Maple Glazed Carp",
		cost = { fish = 2, savory = 4 },
		minutes = 20,
		effect = "loot",
		season = "autumn",
		seasonFish = "maple_carp",
		icon = { shape = "wide", color = "#D9652B", top = "#8A5A2B" },
	},
	{
		id = "frost_chowder",
		name = "Frost Chowder",
		cost = { fish = 2, spicy = 4 },
		minutes = 20,
		effect = "meals",
		flavor = "spicy",
		season = "winter",
		seasonFish = "frost_char",
		icon = { shape = "bowl", color = "#DCEBF2", top = "#E5484D" },
	},
}

Kitchen.ById = {}
Kitchen.Ids = {}
for i, r in Kitchen.Recipes do
	r.makes = r.makes or 1
	r.order = i
	Kitchen.ById[r.id] = r
	table.insert(Kitchen.Ids, r.id)
end

return Kitchen
