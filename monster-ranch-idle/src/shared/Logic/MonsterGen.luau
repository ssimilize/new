--[[
	MonsterGen: builds new monster records. Used by hatching, breeding, rewards and tests.

	MonsterGen.New(rng, spec, now) -> record (without `id`; the Monsters system assigns ids)
	spec = {
	  line = "cindlet",          -- required
	  rarity = 1..6,             -- required
	  stage = 1..3?,             -- default 1 (Baby)
	  form = string?,            -- adult branch id when stage == 3
	  variant = 0|1|2?,          -- rolled when nil (see RollVariant)
	  lucky = boolean?,          -- use Lucky Hatcher variant odds when rolling
	  traits = { id, id }?,      -- rolled when nil
	  hidden = id?,              -- rolled when nil
	  weight = number?,          -- rolled when nil
	  muts = { string }?,
	  gen = number?,             -- generation (0 hatched, parents' max + 1 when bred)
	}
]]

local Config = require(script.Parent.Parent.Config)

local Species = Config.Species
local Traits = Config.Traits
local Rarities = Config.Rarities
local Economy = Config.Economy

local MonsterGen = {}

function MonsterGen.RollVariant(rng, lucky: boolean?): number
	local odds = if lucky then Rarities.LuckyVariantChance else Rarities.VariantChance
	local roll = rng:Next()
	if roll < odds.rainbow then
		return 2
	elseif roll < odds.rainbow + odds.golden then
		return 1
	end
	return 0
end

-- Weight in kg: 1% chance of a "huge" roll (1.8×–2.0× average), otherwise a bell curve
-- around the average clamped to 0.5×–1.79×.
function MonsterGen.RollWeight(rng, lineId: string): number
	local avg = Species.ById[lineId].weight
	local mult
	if rng:Chance(0.01) then
		mult = rng:Float(1.8, 2.0)
	else
		local sum = 0
		for _ = 1, 4 do
			sum += rng:Next()
		end
		-- sum of 4 uniforms: mean 2, sd ≈ 0.577 → scale to mean 1, sd ≈ 0.18
		mult = math.clamp(1 + (sum - 2) * 0.31, 0.5, 1.79)
	end
	return math.floor(avg * mult * 100 + 0.5) / 100
end

local function pickTrait(rng, exclude: { [number]: boolean }, allowHiddenOnly: boolean): number
	local pool = {}
	local weights = {}
	for _, t in Traits.List do
		if not exclude[t.id] and (allowHiddenOnly or not t.hiddenOnly) then
			table.insert(pool, t.id)
			table.insert(weights, t.weight)
		end
	end
	return pool[rng:Weighted(weights)]
end
MonsterGen.PickTrait = pickTrait

-- Two distinct visible traits and one hidden trait (distinct from both; may be hidden-only).
function MonsterGen.RollTraits(rng): ({ number }, number)
	local taken = {}
	local visible = {}
	for _ = 1, Traits.VisibleSlots do
		local id = pickTrait(rng, taken, false)
		taken[id] = true
		table.insert(visible, id)
	end
	local hidden = pickTrait(rng, taken, true)
	return visible, hidden
end

function MonsterGen.New(rng, spec, now: number)
	local def = Species.ById[spec.line]
	assert(def, "unknown line " .. tostring(spec.line))
	assert(Rarities.List[spec.rarity], "bad rarity " .. tostring(spec.rarity))
	local stage = spec.stage or 1
	local form
	if stage == 3 then
		form = Species.Form(spec.line, 3, spec.form).id
	else
		form = def.forms[stage].id
	end
	local traits, hidden = spec.traits, spec.hidden
	if not traits or not hidden then
		local rolledTraits, rolledHidden = MonsterGen.RollTraits(rng)
		traits = traits or rolledTraits
		hidden = hidden or rolledHidden
	end
	return {
		line = spec.line,
		stage = stage,
		form = form,
		rarity = spec.rarity,
		variant = spec.variant or MonsterGen.RollVariant(rng, spec.lucky),
		muts = spec.muts and table.clone(spec.muts) or {},
		traits = table.clone(traits),
		hidden = hidden,
		weight = spec.weight or MonsterGen.RollWeight(rng, spec.line),
		lv = 1,
		stars = 1,
		mood = Economy.Mood.start,
		meals = {},
		growEndsAt = 0,
		loc = "barn",
		pen = 0,
		busy = false,
		name = "",
		locked = false,
		born = now,
		gen = spec.gen or 0,
	}
end

return MonsterGen
