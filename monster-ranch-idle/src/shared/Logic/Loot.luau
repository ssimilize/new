--[[
	Loot: expedition loot tables. Pure and deterministic from a seed.

	Loot.ExpeditionLoot(regionId, stage, durationSeconds, opts?) -> { Reward }
	  opts = {
	    lootPct = number?,   -- additive loot bonus (0.3 = +30%): traits, passives, caravans, providers
	    seed = number?,      -- rolls for random food flavours and egg drops
	    partial = boolean?,  -- recalled early: `durationSeconds` is the time spent, no duration bonus
	  }
	Loot.Expected(regionId, stage, durationSeconds, lootPct?) -> { coins, food, treats, eggs = { [eggType]: expected } }
	  (UI preview without randomness)
	Loot.Merge(lists) -> { Reward }   -- sums rewards of the same kind and id

	Per minute on a stage with global index g (Config.Regions.LootPerMinute):
	  coins, food (70% the region's flavour, the rest random flavours), treats,
	  and one egg roll per whole minute for each of the region's eggs unlocked at this stage.
	Everything except egg chances is multiplied by the duration bonus (full runs only).
	Egg chances scale with lootPct but not with the duration bonus.
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)

local Regions = Config.Regions
local Food = Config.Food

local Loot = {}

Loot.RegionFoodShare = 0.7
Loot.RandomFoodChunks = 3 -- the non-region food is split over up to this many random rolls

local function multipliers(durationSeconds: number, lootPct: number?, partial: boolean?): number
	local bonus = if partial then 1 else (Regions.DurationBonus[durationSeconds] or 1)
	return bonus * (1 + math.max(0, lootPct or 0))
end

function Loot.Expected(regionId: string, stage: number, durationSeconds: number, lootPct: number?)
	local region = Regions.ById[regionId]
	assert(region, "unknown region " .. tostring(regionId))
	local g = Regions.GlobalIndex(regionId, stage)
	local per = Regions.LootPerMinute(g)
	local minutes = math.max(0, durationSeconds) / 60
	local mult = multipliers(durationSeconds, lootPct, false)
	local eggs = {}
	for _, entry in region.eggs or {} do
		if stage >= (entry.fromStage or 1) then
			eggs[entry.egg] = (eggs[entry.egg] or 0) + entry.perMinute * (1 + (lootPct or 0)) * math.floor(minutes)
		end
	end
	return {
		coins = per.coins * minutes * mult,
		food = per.food * minutes * mult,
		treats = per.treats * minutes * mult,
		eggs = eggs,
	}
end

function Loot.ExpeditionLoot(regionId: string, stage: number, durationSeconds: number, options)
	local opts = options or {}
	local region = Regions.ById[regionId]
	assert(region, "unknown region " .. tostring(regionId))
	local rng = Rng.new(Rng.seed("loot", regionId, stage, durationSeconds, opts.seed or 0))
	local g = Regions.GlobalIndex(regionId, stage)
	local per = Regions.LootPerMinute(g)
	local seconds = math.max(0, durationSeconds)
	local minutes = seconds / 60
	local mult = multipliers(seconds, opts.lootPct, opts.partial)
	local rewards = {}

	local coins = math.floor(per.coins * minutes * mult)
	if coins > 0 then
		table.insert(rewards, { kind = "coins", amount = coins })
	end

	-- Food: most of it in the region's flavour, the rest in random flavours.
	local foodTotal = math.floor(per.food * minutes * mult)
	if foodTotal > 0 then
		local food = {}
		local regional = math.max(1, math.floor(foodTotal * Loot.RegionFoodShare + 0.5))
		food[region.food] = regional
		local rest = foodTotal - regional
		local chunk = math.max(1, math.ceil(rest / Loot.RandomFoodChunks))
		while rest > 0 do
			local take = math.min(chunk, rest)
			local flavor = rng:Pick(Food.Ids)
			food[flavor] = (food[flavor] or 0) + take
			rest -= take
		end
		for _, flavor in Food.Ids do
			if food[flavor] then
				table.insert(rewards, { kind = "food", id = flavor, amount = food[flavor] })
			end
		end
	end

	local treats = math.floor(per.treats * minutes * mult)
	if treats > 0 then
		table.insert(rewards, { kind = "treats", amount = treats })
	end

	-- One roll per whole minute for each egg the region drops at this stage.
	local wholeMinutes = math.floor(minutes)
	local eggLuck = 1 + math.max(0, opts.lootPct or 0)
	for _, entry in region.eggs or {} do
		if stage >= (entry.fromStage or 1) then
			local chance = entry.perMinute * eggLuck
			local count = 0
			for _ = 1, wholeMinutes do
				if rng:Chance(chance) then
					count += 1
				end
			end
			if count > 0 then
				table.insert(rewards, { kind = "egg", id = entry.egg, amount = count })
			end
		end
	end

	return rewards
end

-- Sums several reward lists; items with the same kind and id are combined.
function Loot.Merge(lists)
	local out = {}
	local index = {}
	for _, list in lists do
		for _, item in list do
			local key = item.kind .. ":" .. tostring(item.id)
			if item.seconds == nil and item.rarity == nil and index[key] then
				index[key].amount += item.amount or 0
			else
				local copy = table.clone(item)
				table.insert(out, copy)
				if item.seconds == nil and item.rarity == nil then
					index[key] = copy
				end
			end
		end
	end
	return out
end

return Loot
