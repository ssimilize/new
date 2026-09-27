--[[
	Jobs (update 3.7): the Job Board's rules. Pure: the server pays out with them and the client
	shows rates and what each worker has built up with the same functions. Numbers live in
	Config.Jobs (see its header for what each job does).

	Slot (profile.Jobs.slots[i]):
	  { job = jobId | false, monster = id | false, since, carry, rolled, flavor, seed }
	  since   unix time the stored work counts from (the assignment or the last collect)
	  carry   the part of a coin or a food left over at the last collect
	  rolled  scout: whole hours already searched since the assignment (seeds each hour's roll)
	  seed    set once at assignment; each scout hour rolls Rng.seed("scout", seed, hour)

	  Jobs.EmptySlot() -> Slot
	  Jobs.SlotCount(isUnlocked: (key) -> boolean) -> number
	  Jobs.Power(m, jobId) -> number                 W = stat ÷ RefBase[stat]
	  Jobs.Affinity(m) -> number                     the miner's ATK affinity
	  Jobs.CoinsPerSecond(m), Jobs.FoodPerHour(m), Jobs.EggChancePerHour(m),
	  Jobs.GuardMinutes(m), Jobs.HerderShield(m)     one worker's output
	  Jobs.GuardSeconds(workers), Jobs.Shield(workers)
	                                                 ranch-wide totals over a list of workers
	  Jobs.ScoutEggs(isUnlocked) -> { { egg, weight } }
	  Jobs.Elapsed(slot, now) -> seconds             stored work time, capped at MaxHours
	  Jobs.IsFull(slot, now) -> boolean              a collecting job whose storage is full
	  Jobs.Collect(slot, m, now, eggs, boosts?) -> (rewards, since, carry, rolled)
	                                                 what the slot pays now and its new counters;
	                                                 `eggs` = Jobs.ScoutEggs(...) for scouts
	  Jobs.Pending(slot, m, now, eggs, boosts?) -> rewards    the same payout, without the counters
	  Jobs.BoostedSeconds(since, seconds, boosts) -> number
	                                                 3.10: output boosts (Kitchen dishes), a list of
	                                                 { from, to, pct }: each adds pct × the part of
	                                                 [from, to] inside the worked time. Miners and
	                                                 foragers earn that much extra work time; a
	                                                 scout hour's egg chance is × (1 + its share)
]]

local Config = require(script.Parent.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Genetics = require(script.Parent.Genetics)
local Rng = require(script.Parent.Rng)

local Rules = Config.Jobs
local Species = Config.Species
local Traits = Config.Traits

local Jobs = {}

local HOUR = 3600

function Jobs.EmptySlot()
	return { job = false, monster = false, since = 0, carry = 0, rolled = 0, flavor = Config.Food.Ids[1], seed = 0 }
end

function Jobs.SlotCount(isUnlocked: (string) -> boolean): number
	if not isUnlocked(Rules.Unlock) then
		return 0
	end
	local n = Rules.BaseSlots
	for _, key in Rules.SlotUnlocks do
		if isUnlocked(key) then
			n += 1
		end
	end
	return n
end

function Jobs.Power(m, jobId: string): number
	local job = Rules.ById[jobId]
	if not job then
		return 0
	end
	return (Formulas.Stats(m)[job.stat] or 0) / Rules.RefBase[job.stat]
end

function Jobs.Affinity(m): number
	local def = Species.ById[m.line]
	local base = if def then def.base.atk else Rules.RefBase.atk
	local bonus = Genetics.Bonus(m.genes, "atk") + Traits.Sum(Formulas.ActiveTraits(m), "atkPct")
	return base / Rules.RefBase.atk * (1 + bonus)
end

function Jobs.CoinsPerSecond(m): number
	return Formulas.CoinRate(m) * Rules.MinerShare * Jobs.Affinity(m)
end

function Jobs.FoodPerHour(m): number
	return Rules.ForagerPerHour * math.sqrt(Jobs.Power(m, "forager"))
end

function Jobs.EggChancePerHour(m): number
	return math.min(1, Rules.ScoutPerHour * math.sqrt(Jobs.Power(m, "scout")))
end

function Jobs.GuardMinutes(m): number
	return Rules.GuardMinutes * math.sqrt(Jobs.Power(m, "guard"))
end

function Jobs.HerderShield(m): number
	return Rules.HerderShield * math.sqrt(Jobs.Power(m, "herder"))
end

function Jobs.GuardSeconds(workers): number
	local minutes = 0
	for _, m in workers do
		minutes += Jobs.GuardMinutes(m)
	end
	return math.floor(math.min(Rules.GuardMaxMinutes, minutes) * 60)
end

function Jobs.Shield(workers): number
	local shield = 0
	for _, m in workers do
		shield += Jobs.HerderShield(m)
	end
	return math.min(1, shield)
end

function Jobs.ScoutEggs(isUnlocked: (string) -> boolean)
	local list = {}
	for _, entry in Rules.ScoutEggs do
		local def = Config.Eggs.ById[entry.egg]
		if def and (def.unlock == nil or isUnlocked(def.unlock)) then
			table.insert(list, entry)
		end
	end
	return list
end

function Jobs.Elapsed(slot, now: number): number
	return math.clamp(now - (slot.since or now), 0, Rules.MaxHours * HOUR)
end

function Jobs.IsFull(slot, now: number): boolean
	local job = if slot.job then Rules.ById[slot.job] else nil
	if not job or not job.collects then
		return false
	end
	return now - (slot.since or now) >= Rules.MaxHours * HOUR
end

function Jobs.BoostedSeconds(since: number, seconds: number, boosts): number
	local extra = 0
	for _, b in boosts or {} do
		local a = math.max(since, tonumber(b.from) or 0)
		local z = math.min(since + seconds, tonumber(b.to) or 0)
		if z > a then
			extra += (tonumber(b.pct) or 0) * (z - a)
		end
	end
	return extra
end

local function scoutFinds(slot, m, hours: number, eggs, boosts)
	local found = {}
	if #eggs == 0 then
		return found
	end
	local chance = Jobs.EggChancePerHour(m)
	local weights = {}
	for i, entry in eggs do
		weights[i] = entry.weight
	end
	local since = slot.since or 0
	for h = 1, hours do
		local rng = Rng.new(Rng.seed("scout", slot.seed or 0, (slot.rolled or 0) + h))
		local boost = if boosts then Jobs.BoostedSeconds(since + (h - 1) * HOUR, HOUR, boosts) / HOUR else 0
		if rng:Chance(math.min(1, chance * (1 + boost))) then
			local egg = eggs[rng:Weighted(weights)].egg
			found[egg] = (found[egg] or 0) + 1
		end
	end
	return found
end

function Jobs.Collect(slot, m, now: number, eggs, boosts)
	local job = slot.job
	local since, carry, rolled = slot.since or now, slot.carry or 0, slot.rolled or 0
	local rewards = {}
	if not m or not job or not Rules.ById[job] or not Rules.ById[job].collects then
		return rewards, since, carry, rolled
	end
	local elapsed = Jobs.Elapsed(slot, now)
	if job == "miner" or job == "forager" then
		local perSecond = if job == "miner" then Jobs.CoinsPerSecond(m) else Jobs.FoodPerHour(m) / HOUR
		local value = perSecond * (elapsed + Jobs.BoostedSeconds(since, elapsed, boosts)) + carry
		local amount = math.floor(value)
		if amount > 0 then
			if job == "miner" then
				table.insert(rewards, { kind = "coins", amount = amount })
			else
				table.insert(rewards, { kind = "food", id = slot.flavor or Config.Food.Ids[1], amount = amount })
			end
		end
		return rewards, now, value - amount, rolled
	end
	-- Scout: whole hours only; the part of an hour already worked carries over unless the
	-- storage was full (the time past the cap is lost, as for every job).
	local hours = math.floor(elapsed / HOUR)
	local found = scoutFinds(slot, m, hours, eggs or {}, boosts)
	for _, entry in eggs or {} do
		local n = found[entry.egg]
		if n then
			table.insert(rewards, { kind = "egg", id = entry.egg, amount = n })
		end
	end
	local full = now - since >= Rules.MaxHours * HOUR
	return rewards, (if full then now else since + hours * HOUR), carry, rolled + hours
end

function Jobs.Pending(slot, m, now: number, eggs, boosts)
	return (Jobs.Collect(slot, m, now, eggs, boosts))
end

return Jobs
