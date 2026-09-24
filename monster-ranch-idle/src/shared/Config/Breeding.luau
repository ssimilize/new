-- Breeding rules and hybrid recipes.
local Breeding = {}

Breeding.Unlock = "breeding"
Breeding.BreedsPerDay = 2 -- per monster per real (UTC) day
Breeding.Pods = { base = 1, passPods = 1, max = 2 }
Breeding.Seconds = { 1200, 2400, 4800, 9600, 14400, 21600 } -- by the higher parent's rarity
Breeding.FeePct = 0.10 -- of the higher parent's value
Breeding.SpeciesOdds = { parentA = 45, parentB = 45, hybrid = 10 }
Breeding.RarityOdds = { lower = 60, higher = 32, up = 8 }
Breeding.MaxBredRarity = 5 -- breeding can reach Legendary normally…
Breeding.MythicFromLegendaryPair = 0.02 -- …and Mythic only from Legendary + Legendary at 2%
Breeding.MutationInheritChance = 0.20
Breeding.RainbowBothParentsChance = 1 / 100
Breeding.GoldenOneParentChance = 1 / 20
Breeding.WeightJitter = 0.20

-- Hybrid recipes: sorted element pair "a+b" -> hybrid line id.
Breeding.Hybrids = {
	["ember+tide"] = "steamling",
	["stone+tide"] = "mudpuff",
	["spark+sprout"] = "thornbolt",
	["ember+stone"] = "lavashell",
	["gloom+spark"] = "eclipsette",
	["gloom+sprout"] = "mirebloom",
}

function Breeding.HybridFor(elementA: string, elementB: string): string?
	if elementA == elementB then
		return nil
	end
	local pair = { elementA, elementB }
	table.sort(pair)
	return Breeding.Hybrids[pair[1] .. "+" .. pair[2]]
end

-- Added by S5 (Logic/Breeding, Systems/Breeding) -------------------------------------
-- Fertile parents stack (two Fertile parents = 50% faster), capped here.
Breeding.MaxBreedSpeed = 0.5
-- Offspring weight is kept as a multiple of its species' average weight (so crossing a
-- tiny and a huge species stays sensible); breeding toward Huge is capped at this range.
Breeding.WeightRatioRange = { 0.5, 2.5 }

return Breeding
