--[[
	EggRoll: what hatches out of an egg. Pure rules over Config data (no Roblox APIs), used by
	the Eggs system (authoritative roll) and by the client (odds and pity previews).

	EggRoll.roll(rng, eggDef, opts?) -> spec, result
	  opts   = { lucky = boolean?, pity = { [eggId] = count }? }
	           `pity` holds the counters BEFORE this hatch (profile.Eggs.pity: { starlit, royal }).
	  spec   = MonsterGen spec { line, rarity, variant, muts? } (pass to Monsters:Create)
	  result = { pity = { [eggId] = count } (a new table: the counters AFTER this hatch),
	             guaranteed = boolean (pity or lucky meter forced the rarity), hybrid = boolean }

	EggRoll.starter(rng, opts?) -> spec          -- the first-join egg: Uncommon, random starter line
	EggRoll.RollRarity(rng, odds, minRarity?) -> rarity
	EggRoll.Guarantee(eggDef) -> { counter, every, minRarity }?   -- pity or lucky meter, if any
	EggRoll.HatchesUntilGuarantee(eggDef, pity) -> number?        -- 1 = the next hatch is guaranteed

	Guarantees (Config.Eggs):
	  pity       { count, minRarity }  a rarity ≥ minRarity within `count` eggs; the counter
	                                   resets whenever a hatch reaches minRarity (Starlit).
	  luckyMeter { every, minRarity }  every `every`-th hatch is ≥ minRarity; the meter fills on
	                                   every hatch and empties when it pays out (Royal).
]]

local Config = require(script.Parent.Parent.Config)
local MonsterGen = require(script.Parent.MonsterGen)

local Species = Config.Species
local Rarities = Config.Rarities

local EggRoll = {}

-- Weighted rarity roll over an egg's odds, ignoring rarities below `minRarity`.
function EggRoll.RollRarity(rng, odds: { number }, minRarity: number?): number
	local min = minRarity or 1
	local weights = {}
	local total = 0
	for i = 1, Rarities.Count do
		local w = if i >= min then (odds[i] or 0) else 0
		weights[i] = w
		total += math.max(w, 0)
	end
	if total <= 0 then
		-- The egg never rolls this high naturally: the guarantee pays the floor rarity.
		return math.clamp(min, 1, Rarities.Count)
	end
	return rng:Weighted(weights)
end

-- The guarantee rule of an egg, normalised: which counter it uses, how often it pays, and
-- whether a natural high roll resets it.
function EggRoll.Guarantee(egg)
	if egg.pity then
		return { counter = egg.id, every = egg.pity.count, minRarity = egg.pity.minRarity, resetOnHit = true }
	elseif egg.luckyMeter then
		return { counter = egg.id, every = egg.luckyMeter.every, minRarity = egg.luckyMeter.minRarity, resetOnHit = false }
	end
	return nil
end

function EggRoll.HatchesUntilGuarantee(egg, pity: { [string]: number }?): number?
	local rule = EggRoll.Guarantee(egg)
	if not rule then
		return nil
	end
	local count = (pity and pity[rule.counter]) or 0
	return math.max(1, rule.every - count)
end

local function pickLine(rng, egg): (string, boolean)
	if egg.hybridChance and egg.hybridChance > 0 then
		local hybrids = Species.Pools.hybrid
		if hybrids and #hybrids > 0 and rng:Chance(egg.hybridChance) then
			return rng:Pick(hybrids), true
		end
	end
	local pool = Species.Pools[egg.pool]
	assert(pool and #pool > 0, "[EggRoll] egg pool is empty: " .. tostring(egg.pool))
	return rng:Pick(pool), false
end

function EggRoll.roll(rng, egg, opts: { lucky: boolean?, pity: { [string]: number }? }?)
	local options = opts or {}
	local pity = table.clone(options.pity or {})
	local rule = EggRoll.Guarantee(egg)

	local guaranteed = false
	local rarity
	if rule and ((pity[rule.counter] or 0) + 1) >= rule.every then
		guaranteed = true
		rarity = EggRoll.RollRarity(rng, egg.odds, rule.minRarity)
	else
		rarity = EggRoll.RollRarity(rng, egg.odds)
	end

	if rule then
		local count = pity[rule.counter] or 0
		if guaranteed or (rule.resetOnHit and rarity >= rule.minRarity) then
			pity[rule.counter] = 0
		else
			pity[rule.counter] = count + 1
		end
	end

	local line, hybrid = pickLine(rng, egg)
	local spec = {
		line = line,
		rarity = rarity,
		variant = MonsterGen.RollVariant(rng, options.lucky),
		lucky = options.lucky,
	}
	if egg.forcedMutation then
		spec.muts = { egg.forcedMutation }
	end
	return spec, { pity = pity, guaranteed = guaranteed, hybrid = hybrid }
end

function EggRoll.starter(rng, opts: { lucky: boolean? }?)
	local starter = Config.Eggs.Starter
	return {
		line = rng:Pick(starter.lines),
		rarity = starter.rarity,
		variant = MonsterGen.RollVariant(rng, opts and opts.lucky),
	}
end

return EggRoll
