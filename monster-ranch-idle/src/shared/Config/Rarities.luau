-- Rarity tiers. Index order matters: 1 = Common … 6 = Mythic.
local Rarities = {}

Rarities.List = {
	{
		id = "common",
		index = 1,
		name = "Common",
		color = "#8E9990",
		statMult = 1.00,
		coinRate = 1,
		maxStars = 3,
		stardust = 5,
		legacyPct = 0.01,
		xp = 10,
		broadcast = "none",
	},
	{
		id = "uncommon",
		index = 2,
		name = "Uncommon",
		color = "#4FAF45",
		statMult = 1.25,
		coinRate = 3,
		maxStars = 3,
		stardust = 12,
		legacyPct = 0.02,
		xp = 20,
		broadcast = "none",
	},
	{
		id = "rare",
		index = 3,
		name = "Rare",
		color = "#3A8FE0",
		statMult = 1.60,
		coinRate = 8,
		maxStars = 4,
		stardust = 30,
		legacyPct = 0.03,
		xp = 40,
		broadcast = "none",
	},
	{
		id = "epic",
		index = 4,
		name = "Epic",
		color = "#A259E0",
		statMult = 2.10,
		coinRate = 25,
		maxStars = 4,
		stardust = 75,
		legacyPct = 0.04,
		xp = 80,
		broadcast = "server",
	},
	{
		id = "legendary",
		index = 5,
		name = "Legendary",
		color = "#E99A10",
		statMult = 2.80,
		coinRate = 80,
		maxStars = 5,
		stardust = 180,
		legacyPct = 0.05,
		xp = 160,
		broadcast = "server",
	},
	{
		id = "mythic",
		index = 6,
		name = "Mythic",
		color = "#E8436F",
		statMult = 3.80,
		coinRate = 250,
		maxStars = 5,
		stardust = 400,
		legacyPct = 0.06,
		xp = 320,
		broadcast = "global",
	},
}

Rarities.Count = #Rarities.List

Rarities.ById = {}
for _, r in Rarities.List do
	Rarities.ById[r.id] = r
end

function Rarities.Get(index: number)
	return Rarities.List[index]
end

-- Variants rolled on every hatch. `mult` multiplies coin output and trade value.
Rarities.Variants = {
	[0] = { id = "normal", name = "Normal", mult = 1 },
	[1] = { id = "golden", name = "Golden", mult = 3, color = "#F4C43A" },
	[2] = { id = "rainbow", name = "Rainbow", mult = 10 },
}
Rarities.VariantChance = { golden = 1 / 40, rainbow = 1 / 400 }
Rarities.LuckyVariantChance = { golden = 1 / 30, rainbow = 1 / 300 } -- Lucky Hatcher pass

return Rarities
