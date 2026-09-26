--[[
	Formulas: every number derived from a monster record. Pure functions over plain data,
	shared by the server (authoritative) and the client (previews).

	Monster record fields used here (see ARCHITECTURE.md → "Monster record"):
	  line, stage, form, rarity, variant, muts, traits, hidden, weight, lv, stars, mood, genes
]]

local Config = require(script.Parent.Parent.Config)
local Genetics = require(script.Parent.Genetics)

local Economy = Config.Economy
local Rarities = Config.Rarities
local Species = Config.Species
local Traits = Config.Traits
local Mutations = Config.Mutations

local Formulas = {}

-- Trait ids whose effects apply (visible traits + the hidden trait; hidden effects apply
-- from birth, the trait is only *displayed* once the monster is an Adult).
function Formulas.ActiveTraits(m): { number }
	local list = table.clone(m.traits or {})
	if m.hidden and m.hidden ~= 0 then
		table.insert(list, m.hidden)
	end
	return list
end

function Formulas.StarMult(stars: number): number
	return Economy.StarMult[math.clamp(stars or 1, 1, #Economy.StarMult)]
end

function Formulas.LevelCap(m): number
	local stage = Economy.Stages[m.stage]
	if stage.levelCap then
		return stage.levelCap
	end
	return Economy.AdultLevelCapBase + Economy.AdultLevelCapPerStar * (m.stars or 1)
end

function Formulas.MaxStars(m): number
	return Rarities.List[m.rarity].maxStars
end

function Formulas.MutationMult(muts: { string }?): number
	local mult = 1
	for _, id in muts or {} do
		local def = Mutations.ById[id]
		if def then
			mult *= def.mult
		end
	end
	return mult
end

function Formulas.VariantMult(variant: number?): number
	local v = Rarities.Variants[variant or 0]
	return if v then v.mult else 1
end

-- Coins per second produced by one monster standing in a pen, before ranch-wide
-- modifiers (friends, legacy, passes), which Ranch applies.
function Formulas.CoinRate(m): number
	local rarity = Rarities.List[m.rarity]
	local stage = Economy.Stages[m.stage]
	local traits = Formulas.ActiveTraits(m)
	local traitBonus = Traits.Sum(traits, "coinPct") + Traits.Sum(traits, "coinPerMutationPct") * #(m.muts or {})
	return rarity.coinRate
		* stage.coinMult
		* Economy.CoinLevelGrowth ^ ((m.lv or 1) - 1)
		* Formulas.StarMult(m.stars)
		* Formulas.VariantMult(m.variant)
		* Formulas.MutationMult(m.muts)
		* Economy.MoodMult(m.mood or Economy.Mood.start)
		* (1 + traitBonus)
end

-- Battle stats. Returns { hp, atk, def, spd, luck }. Genes (Logic/Genetics) multiply HP, ATK,
-- DEF and SPD on top of everything else; a record without genes gets no gene bonus.
function Formulas.Stats(m)
	local def = Species.ById[m.line]
	local rarity = Rarities.List[m.rarity]
	local stage = Economy.Stages[m.stage]
	local traits = Formulas.ActiveTraits(m)
	local levelMult = 1 + Economy.StatPerLevel * ((m.lv or 1) - 1)
	local common = rarity.statMult * stage.statMult * levelMult * Formulas.StarMult(m.stars)
	local mutPct = 0
	for _, id in m.muts or {} do
		local mdef = Mutations.ById[id]
		if mdef then
			mutPct += mdef.statPct
		end
	end
	local all = Traits.Sum(traits, "allStatPct") + mutPct
	local function stat(key: string, traitKey: string?)
		local bonus = all + (if traitKey then Traits.Sum(traits, traitKey) else 0)
		return math.floor(def.base[key] * common * (1 + bonus) * (1 + Genetics.Bonus(m.genes, key)) + 0.5)
	end
	return {
		hp = stat("hp", "hpPct"),
		atk = stat("atk", "atkPct"),
		def = stat("def", "defPct"),
		spd = stat("spd", "spdPct"),
		luck = stat("luck", nil),
	}
end

-- A single number summarising battle strength (squad power, boss HP scaling, UI).
function Formulas.Power(stats): number
	return math.floor(stats.hp * 0.25 + stats.atk * 2 + stats.def * 1.5 + stats.spd * 1.2 + 0.5)
end

function Formulas.MonsterPower(m): number
	return Formulas.Power(Formulas.Stats(m))
end

function Formulas.Value(m): number
	return math.floor(Formulas.CoinRate(m) * Economy.ValueSeconds)
end

function Formulas.SellPrice(m): number
	return math.max(Economy.SellMinimum, math.floor(Formulas.CoinRate(m) * Economy.SellSeconds))
end

-- Growth ----------------------------------------------------------------------------

function Formulas.MealsNeeded(stage: number): number?
	local g = Economy.Growth[stage]
	return if g then g.meals else nil
end

function Formulas.MealsEaten(m): number
	local total = 0
	for _, n in m.meals or {} do
		total += n
	end
	return total
end

function Formulas.GrowSeconds(m): number?
	local g = Economy.Growth[m.stage]
	if not g then
		return nil
	end
	local speed = Traits.Sum(Formulas.ActiveTraits(m), "growthSpeed")
	return math.max(1, math.floor(g.seconds[m.rarity] * (1 - speed)))
end

-- Can the monster start growing into the next stage right now?
function Formulas.CanGrow(m): (boolean, string?)
	if m.stage >= 3 then
		return false, "Already an Adult"
	end
	if (m.growEndsAt or 0) > 0 then
		return false, "Already growing"
	end
	if (m.lv or 1) < Formulas.LevelCap(m) then
		return false, string.format("Reach level %d first", Formulas.LevelCap(m))
	end
	if Formulas.MealsEaten(m) < (Formulas.MealsNeeded(m.stage) or 0) then
		return false, string.format("Needs %d meals", Formulas.MealsNeeded(m.stage))
	end
	return true, nil
end

-- Name of the monster's current form.
function Formulas.FormName(m): string
	local form = Species.Form(m.line, m.stage, m.form)
	return if form then form.name else m.line
end

function Formulas.DisplayName(m): string
	if m.name and m.name ~= "" then
		return m.name
	end
	return Formulas.FormName(m)
end

function Formulas.Elements(m): { string }
	return Species.ById[m.line].elements
end

function Formulas.IsHuge(m): boolean
	local avg = Species.ById[m.line].weight
	return (m.weight or avg) >= avg * Config.Social.HugeWeightMult
end

return Formulas
