--[[
	Breeding (S5): pure breeding rules. Shared by the server (authoritative roll) and the
	Breeding screen (previews). No Roblox APIs; parents are plain monster records.

	Breeding.Outcomes(a, b) -> preview (ARCHITECTURE.md §7):
	  {
	    species = { { line, pct, hybrid } },   -- pct in percent (0..100); hybrid = hybrid species
	    rarity = { { rarity, pct } },          -- ascending rarity, pct in percent
	    mutationChance = number,               -- 0..1, chance to inherit one parent mutation
	    seconds = number,                      -- breeding time
	    fee = number,                          -- coins
	    rainbowChance = number,                -- 0..1
	    goldenChance = number,                 -- 0..1
	  }
	Breeding.Roll(rng, a, b) -> (MonsterGen spec, isHybrid)

	Rules (Config.Breeding):
	  species   45% parent A · 45% parent B · 10% hybrid when Config.Breeding.HybridFor has a recipe
	            for the parents' first elements; otherwise 50/50 (100% when both are the same line)
	  rarity    lower parent 60% · higher parent 32% · one tier above the higher parent 8%, capped at
	            MaxBredRarity. Parents that are both ≥ MaxBredRarity (Legendary) get Mythic at 2%.
	  traits    each visible slot copies a random parent slot (FreshRollChance of a fresh roll);
	            the hidden trait is rolled fresh, unless a parent carries Firstborn (extraInherit):
	            then the hidden slot inherits one of the parents' hidden traits.
	  mutation  MutationInheritChance to inherit one random parent mutation
	  variant   Rainbow 1/100 if both parents are Rainbow, Golden 1/20 if a parent is Golden,
	            otherwise the normal hatch odds; Golden Heart multiplies the golden chance ×3
	  weight    parents' average weight (relative to their species average) ±WeightJitter
	  time      Seconds[higher rarity] × (1 − Fertile breedSpeed of both parents, capped)
	  fee       FeePct × the higher parent's value (Formulas.Value)
]]

local Config = require(script.Parent.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local MonsterGen = require(script.Parent.MonsterGen)

local Rules = Config.Breeding
local Species = Config.Species
local Traits = Config.Traits
local Rarities = Config.Rarities

local Breeding = {}

local function isHybridLine(lineId: string): boolean
	local def = Species.ById[lineId]
	return def ~= nil and def.hybrid == true
end

local function firstElement(m): string
	return Species.ById[m.line].elements[1]
end

-- Species odds ------------------------------------------------------------------------

function Breeding.SpeciesOdds(a, b): { { line: string, pct: number, hybrid: boolean } }
	if a.line == b.line then
		return { { line = a.line, pct = 100, hybrid = isHybridLine(a.line) } }
	end
	local odds = Rules.SpeciesOdds
	local weighted = { { a.line, odds.parentA }, { b.line, odds.parentB } }
	local hybridLine = Rules.HybridFor(firstElement(a), firstElement(b))
	if hybridLine and Species.ById[hybridLine] then
		table.insert(weighted, { hybridLine, odds.hybrid })
	end
	local total = 0
	for _, entry in weighted do
		total += entry[2]
	end
	local list, index = {}, {}
	for _, entry in weighted do
		local line, pct = entry[1], 100 * entry[2] / total
		local existing = index[line]
		if existing then
			-- A hybrid parent bred with a matching partner can roll its own line twice.
			existing.pct += pct
		else
			existing = { line = line, pct = pct, hybrid = isHybridLine(line) }
			index[line] = existing
			table.insert(list, existing)
		end
	end
	return list
end

-- Rarity odds -------------------------------------------------------------------------

function Breeding.RarityOdds(a, b): { { rarity: number, pct: number } }
	local odds = Rules.RarityOdds
	local lo, hi = math.min(a.rarity, b.rarity), math.max(a.rarity, b.rarity)
	local cap = math.min(Rules.MaxBredRarity, Rarities.Count)
	local weights = {}
	local function add(rarity: number, w: number)
		local r = math.clamp(rarity, 1, cap)
		weights[r] = (weights[r] or 0) + w
	end
	add(lo, odds.lower)
	add(hi, odds.higher)
	add(hi + 1, odds.up)

	local total = 0
	for _, w in weights do
		total += w
	end
	local list = {}
	local mythic = cap + 1
	local mythicPct = 0
	if lo >= cap and mythic <= Rarities.Count then
		mythicPct = 100 * Rules.MythicFromLegendaryPair
	end
	for rarity, w in weights do
		table.insert(list, { rarity = rarity, pct = 100 * w / total * (1 - mythicPct / 100) })
	end
	if mythicPct > 0 then
		table.insert(list, { rarity = mythic, pct = mythicPct })
	end
	table.sort(list, function(x, y)
		return x.rarity < y.rarity
	end)
	return list
end

-- Time, fee, variants -------------------------------------------------------------------

local function traitSum(m, key: string): number
	return Traits.Sum(Formulas.ActiveTraits(m), key)
end

function Breeding.Seconds(a, b): number
	local hi = math.clamp(math.max(a.rarity, b.rarity), 1, #Rules.Seconds)
	local speed = math.clamp(traitSum(a, "breedSpeed") + traitSum(b, "breedSpeed"), 0, Rules.MaxBreedSpeed or 0.5)
	return math.max(1, math.floor(Rules.Seconds[hi] * (1 - speed)))
end

function Breeding.Fee(a, b): number
	return math.floor(Rules.FeePct * math.max(Formulas.Value(a), Formulas.Value(b)))
end

function Breeding.MutationChance(a, b): number
	if #(a.muts or {}) + #(b.muts or {}) > 0 then
		return Rules.MutationInheritChance
	end
	return 0
end

-- Returns rainbowChance, goldenChance (both 0..1).
function Breeding.VariantChances(a, b): (number, number)
	local base = Rarities.VariantChance
	local rainbow = if a.variant == 2 and b.variant == 2 then Rules.RainbowBothParentsChance else base.rainbow
	local golden = if a.variant == 1 or b.variant == 1 then Rules.GoldenOneParentChance else base.golden
	local heart = math.max(
		Traits.Product(Formulas.ActiveTraits(a), "goldenOffspringMult"),
		Traits.Product(Formulas.ActiveTraits(b), "goldenOffspringMult")
	)
	golden = math.min(golden * heart, 1 - rainbow)
	return rainbow, golden
end

function Breeding.Outcomes(a, b)
	local rainbow, golden = Breeding.VariantChances(a, b)
	return {
		species = Breeding.SpeciesOdds(a, b),
		rarity = Breeding.RarityOdds(a, b),
		mutationChance = Breeding.MutationChance(a, b),
		seconds = Breeding.Seconds(a, b),
		fee = Breeding.Fee(a, b),
		rainbowChance = rainbow,
		goldenChance = golden,
	}
end

-- Roll ----------------------------------------------------------------------------------

local function pickWeighted(rng, list)
	local weights = {}
	for i, entry in list do
		weights[i] = entry.pct
	end
	return list[rng:Weighted(weights)]
end

local function rollTraits(rng, a, b): ({ number }, number)
	local parentSlots = {}
	for _, parent in { a, b } do
		for _, id in parent.traits or {} do
			local def = Traits.ById[id]
			if def and not def.hiddenOnly then
				table.insert(parentSlots, id)
			end
		end
	end
	local taken, visible = {}, {}
	for _ = 1, Traits.VisibleSlots do
		local id
		if not rng:Chance(Traits.FreshRollChance) then
			local candidates = {}
			for _, slotId in parentSlots do
				if not taken[slotId] then
					table.insert(candidates, slotId)
				end
			end
			if #candidates > 0 then
				id = rng:Pick(candidates)
			end
		end
		id = id or MonsterGen.PickTrait(rng, taken, false)
		taken[id] = true
		table.insert(visible, id)
	end

	local hidden
	if traitSum(a, "extraInherit") + traitSum(b, "extraInherit") > 0 then
		local candidates = {}
		for _, parent in { a, b } do
			if parent.hidden and Traits.ById[parent.hidden] and not taken[parent.hidden] then
				table.insert(candidates, parent.hidden)
			end
		end
		if #candidates > 0 then
			hidden = rng:Pick(candidates)
		end
	end
	hidden = hidden or MonsterGen.PickTrait(rng, taken, true)
	return visible, hidden
end

local function rollWeight(rng, a, b, line: string): number
	local function ratio(m): number
		local avg = Species.ById[m.line].weight
		return (m.weight or avg) / avg
	end
	local jitter = Rules.WeightJitter
	local range = Rules.WeightRatioRange or { 0.5, 2.5 }
	local r = (ratio(a) + ratio(b)) / 2 * rng:Float(1 - jitter, 1 + jitter)
	r = math.clamp(r, range[1], range[2])
	return math.floor(Species.ById[line].weight * r * 100 + 0.5) / 100
end

function Breeding.Roll(rng, a, b)
	local line = pickWeighted(rng, Breeding.SpeciesOdds(a, b)).line
	local rarity = pickWeighted(rng, Breeding.RarityOdds(a, b)).rarity
	local traits, hidden = rollTraits(rng, a, b)

	local muts = {}
	local mutationChance = Breeding.MutationChance(a, b)
	if mutationChance > 0 and rng:Chance(mutationChance) then
		local pool = {}
		for _, parent in { a, b } do
			for _, id in parent.muts or {} do
				table.insert(pool, id)
			end
		end
		table.insert(muts, rng:Pick(pool))
	end

	local rainbow, golden = Breeding.VariantChances(a, b)
	local roll = rng:Next()
	local variant = if roll < rainbow then 2 elseif roll < rainbow + golden then 1 else 0

	local spec = {
		line = line,
		rarity = rarity,
		stage = 1,
		variant = variant,
		traits = traits,
		hidden = hidden,
		weight = rollWeight(rng, a, b, line),
		muts = muts,
		gen = math.max(a.gen or 0, b.gen or 0) + 1,
	}
	return spec, isHybridLine(line)
end

return Breeding
