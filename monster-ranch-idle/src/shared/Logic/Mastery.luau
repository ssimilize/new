--[[
	Logic/Mastery: pure rules of the endgame layer (numbers in Config/Mastery, design in its
	header). Used by Systems/Mastery and the Mastery screen, so both show the same odds and costs.

	  Mastery.RanchCost(level) -> xp                 Ranch Mastery level -> level + 1
	  Mastery.AddRanchXP(level, xp, amount) -> (level, xp, gained)
	  Mastery.LineCost(level) -> points              Line Mastery level -> level + 1
	  Mastery.LineLevel(points) -> (level, into, need)
	  Mastery.LineTier(level) -> tier?               Config.Mastery.Tiers entry, nil below Bronze
	  Mastery.TierIndex(points) -> 0..#Tiers
	  Mastery.RerollCost(done) -> shards             the cost of reroll number done + 1
	  Mastery.RerollOdds(record, slot) -> { { id, name, pct } }   highest first; pct sums to 1
	  Mastery.RerollTrait(record, slot, seed) -> traitId?
	  Mastery.RerollSeed(userId, record, done) -> number
	  Mastery.LadderPoints(xp, line) -> points
	  Mastery.LadderTier(points) -> 0..#Ladder
	  Mastery.SeasonAt(now) -> season number | 0     0 = no ladder open now
	  Mastery.PerkEffect(perks, effectKey) -> number
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)
local MonsterGen = require(script.Parent.MonsterGen)

local M = Config.Mastery
local Traits = Config.Traits

local Mastery = {}

function Mastery.RanchCost(level: number): number
	return M.RanchBase + M.RanchStep * math.max(0, math.floor(level))
end

function Mastery.AddRanchXP(level: number, xp: number, amount: number): (number, number, number)
	local gained = 0
	xp += math.max(0, amount)
	while xp >= Mastery.RanchCost(level) do
		xp -= Mastery.RanchCost(level)
		level += 1
		gained += 1
	end
	return level, xp, gained
end

function Mastery.LineCost(level: number): number
	return M.LineBase + M.LineStep * math.max(0, math.floor(level))
end

-- The level reached with `points`, how far into the next level, and what that level costs.
function Mastery.LineLevel(points: number): (number, number, number)
	local level = 0
	local left = math.max(0, math.floor(tonumber(points) or 0))
	while left >= Mastery.LineCost(level) do
		left -= Mastery.LineCost(level)
		level += 1
	end
	return level, left, Mastery.LineCost(level)
end

function Mastery.LineTier(level: number)
	local best = nil
	for _, tier in M.Tiers do
		if level >= tier.level then
			best = tier
		end
	end
	return best
end

function Mastery.TierIndex(points: number): number
	local tier = Mastery.LineTier((Mastery.LineLevel(points)))
	return if tier then tier.index else 0
end

function Mastery.RerollCost(done: number): number
	local costs = M.RerollCosts
	return costs[math.clamp(math.floor(done) + 1, 1, #costs)]
end

-- Every trait on the monster except the one in `slot` (hidden included), plus that one: a
-- reroll always changes the trait and never duplicates another.
local function excluded(record, slot: number): { [number]: boolean }
	local taken = {}
	for _, id in record.traits or {} do
		taken[id] = true
	end
	if record.hidden and record.hidden ~= 0 then
		taken[record.hidden] = true
	end
	local current = (record.traits or {})[slot]
	if current then
		taken[current] = true
	end
	return taken
end

function Mastery.RerollOdds(record, slot: number): { { id: number, name: string, pct: number } }
	local taken = excluded(record, slot)
	local list, total = {}, 0
	for _, t in Traits.List do
		if not taken[t.id] and not t.hiddenOnly then
			table.insert(list, { id = t.id, name = t.name, pct = t.weight })
			total += t.weight
		end
	end
	for _, row in list do
		row.pct = if total > 0 then row.pct / total else 0
	end
	table.sort(list, function(a, b)
		if a.pct ~= b.pct then
			return a.pct > b.pct
		end
		return a.id < b.id
	end)
	return list
end

function Mastery.RerollSeed(userId: number, record, done: number): number
	return Rng.seed("reroll", userId, record.id, record.born or 0, done)
end

-- The same pick a hatch makes (MonsterGen.PickTrait) from the reroll pool.
function Mastery.RerollTrait(record, slot: number, seed: number): number?
	if type(record.traits) ~= "table" or record.traits[slot] == nil then
		return nil
	end
	local ok, id = pcall(MonsterGen.PickTrait, Rng.new(seed), excluded(record, slot), false)
	return if ok then id else nil
end

function Mastery.LadderPoints(xp: number, line: number): number
	return math.floor((tonumber(xp) or 0) / M.LadderXP) + math.floor((tonumber(line) or 0) / M.LadderLine)
end

function Mastery.LadderTier(points: number): number
	local tier = 0
	for i, row in M.Ladder do
		if points >= row.points then
			tier = i
		end
	end
	return tier
end

function Mastery.SeasonAt(now: number): number
	for _, season in Config.Quests.Seasons do
		if now >= season.startsAt and now < season.endsAt then
			return season.season
		end
	end
	return 0
end

function Mastery.PerkEffect(perks, effectKey: string): number
	local total = 0
	for id, level in if type(perks) == "table" then perks else {} do
		local def = M.ShopById[id]
		if def and def.kind == "perk" and def.effect[effectKey] then
			total += def.effect[effectKey] * math.clamp(tonumber(level) or 0, 0, def.maxLevel)
		end
	end
	return total
end

return Mastery
