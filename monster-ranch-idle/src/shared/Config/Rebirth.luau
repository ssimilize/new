--[[
	Ranch Rebirth (prestige layer 2, update 1.4) and the Stardust skill tree.

	Rebirth (Ranch Level 40+, always optional) needs `CoinsNeeded(stars)` coins in hand.
	  Resets : coins (to the Head Start amount), ranch buildings (pens, jars, incubator speed,
	           barn, garden; placed decor goes back to storage) and region progress.
	           Monsters that are not kept turn into Stardust at `DustShare` of their value.
	  Keeps  : Ranch Level, Codex, Hall of Fame, gems and every other currency, eggs,
	           cosmetics (decor, themes), passes, and `Heirlooms(stars, bonus)` monsters.
	  Gains  : a Rebirth Star (coins × (1 + StarCoinBonus × stars)), that star's biome pen
	           theme, the Celestial Egg (from star 1) and, from `ThirdTraitStars`, a 3rd
	           visible trait on every monster.

	Skill tree: three branches of three nodes. A node needs the one above it (`requires`,
	level ≥ 1) and, for deeper nodes, a number of Rebirth Stars. Every effect is read by the
	system that owns it through the providers the Rebirth system registers.
]]

local Rarities = require(script.Parent.Rarities)
local Economy = require(script.Parent.Economy)

local Rebirth = {}

Rebirth.Unlock = "rebirth"
Rebirth.MaxStars = 10
Rebirth.BaseHeirlooms = 3 -- + 1 per Rebirth Star + Family Vault levels
Rebirth.MaxHeirlooms = 16
Rebirth.StarCoinBonus = 0.5 -- ×1.5 coins with one star, ×2 with two, …
Rebirth.DustShare = 0.5 -- unkept monsters pay 50% of their Hall of Fame Stardust value
Rebirth.ThirdTraitStars = 3
Rebirth.CelestialStars = 1

-- Coins you must hold to earn star `stars + 1` (the coins are reset anyway).
function Rebirth.CoinsNeeded(stars: number): number
	return 50000000 * 3 ^ math.max(0, stars)
end

function Rebirth.Heirlooms(stars: number, bonus: number?): number
	return math.min(Rebirth.MaxHeirlooms, Rebirth.BaseHeirlooms + stars + (bonus or 0))
end

function Rebirth.CoinMult(stars: number): number
	return 1 + Rebirth.StarCoinBonus * math.max(0, stars)
end

-- Stardust one unkept monster turns into (before the Star Sifter bonus).
function Rebirth.DustFor(m): number
	local rarity = Rarities.List[m.rarity or 1] or Rarities.List[1]
	local stars = Economy.StarMult[math.clamp(m.stars or 1, 1, #Economy.StarMult)]
	return math.floor(rarity.stardust * stars * Rebirth.DustShare)
end

-- Biome pen theme granted with each star (Config.Decor pen themes with `rebirth = n`).
Rebirth.Biomes = { "starfield", "crystal_tundra", "aurora_isle", "sunset_mesa", "nebula" }

function Rebirth.BiomeFor(star: number): string
	return Rebirth.Biomes[math.clamp(star, 1, #Rebirth.Biomes)]
end

Rebirth.Branches = {
	{ id = "ranch", name = "Ranch", color = "#F5C630" },
	{ id = "hatchery", name = "Hatchery", color = "#FF9EC7" },
	{ id = "adventure", name = "Adventure", color = "#4FB6F2" },
}

-- effect keys: coinPct, jarCapSeconds, startCoins, hatchSpeed, breedsPerDay, dustPct,
-- lootPct, bossDmgPct, heirlooms (all per level).
Rebirth.Skills = {
	{
		id = "golden_touch",
		branch = "ranch",
		tier = 1,
		name = "Golden Touch",
		desc = "+8% coins per level.",
		maxLevel = 5,
		cost = { 40, 90, 180, 350, 700 },
		effect = { coinPct = 0.08 },
	},
	{
		id = "deep_pockets",
		branch = "ranch",
		tier = 2,
		requires = "golden_touch",
		name = "Deep Pockets",
		desc = "Coin jars hold 30 more minutes per level.",
		maxLevel = 3,
		cost = { 150, 400, 900 },
		effect = { jarCapSeconds = 1800 },
	},
	{
		id = "head_start",
		branch = "ranch",
		tier = 3,
		requires = "deep_pockets",
		stars = 1,
		name = "Head Start",
		desc = "Start each rebirth with 250K coins per level.",
		maxLevel = 3,
		cost = { 500, 1200, 2500 },
		effect = { startCoins = 250000 },
	},
	{
		id = "warm_hands",
		branch = "hatchery",
		tier = 1,
		name = "Warm Hands",
		desc = "Hatch time −4% per level.",
		maxLevel = 5,
		cost = { 50, 110, 220, 420, 800 },
		effect = { hatchSpeed = 0.04 },
	},
	{
		id = "twin_nests",
		branch = "hatchery",
		tier = 2,
		requires = "warm_hands",
		name = "Twin Nests",
		desc = "+1 breed per monster per day.",
		maxLevel = 1,
		cost = { 600 },
		effect = { breedsPerDay = 1 },
	},
	{
		id = "star_sifter",
		branch = "hatchery",
		tier = 3,
		requires = "twin_nests",
		stars = 1,
		name = "Star Sifter",
		desc = "+15% Stardust from monsters you don't keep, per level.",
		maxLevel = 3,
		cost = { 400, 1000, 2200 },
		effect = { dustPct = 0.15 },
	},
	{
		id = "trailblazer",
		branch = "adventure",
		tier = 1,
		name = "Trailblazer",
		desc = "Expedition loot +4% per level.",
		maxLevel = 5,
		cost = { 45, 100, 200, 380, 750 },
		effect = { lootPct = 0.04 },
	},
	{
		id = "war_paint",
		branch = "adventure",
		tier = 2,
		requires = "trailblazer",
		name = "War Paint",
		desc = "Stampede damage +5% per level.",
		maxLevel = 3,
		cost = { 200, 500, 1100 },
		effect = { bossDmgPct = 0.05 },
	},
	{
		id = "family_vault",
		branch = "adventure",
		tier = 3,
		requires = "war_paint",
		stars = 2,
		name = "Family Vault",
		desc = "Keep 1 more Heirloom monster per level.",
		maxLevel = 2,
		cost = { 1500, 4000 },
		effect = { heirlooms = 1 },
	},
}

Rebirth.SkillById = {}
for _, s in Rebirth.Skills do
	Rebirth.SkillById[s.id] = s
	assert(#s.cost == s.maxLevel, "Rebirth skill cost list must match maxLevel: " .. s.id)
end

return Rebirth
