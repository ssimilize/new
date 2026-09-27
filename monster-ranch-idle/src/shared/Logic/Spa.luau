--[[
	Spa (update 3.13 · Wild things): the Hot Springs rules. Pure: the server soaks, pays and
	buffs with them, the client shows costs, times and buffs with the same functions. Numbers in
	Config.Spa (see its header).

	Pool (profile.Spa.pools[i]):
	  { monster = id | false, soak = soakId | false, at = unix, endsAt = unix }
	Buff (profile.Spa.buffs[monsterId]):
	  { soak = soakId, from = unix, endsAt = unix }   from the collect for Config.Spa.BuffHours

	  Spa.EmptyPool() -> Pool
	  Spa.PoolCount(isUnlocked: (key) -> boolean) -> number
	  Spa.Seconds(soakId) -> number                   the soak's time
	  Spa.Cost(soakId) -> { honey, food = { [flavour]: n } }
	  Spa.Left(pool, now) -> number                   seconds until the soak is done (0 done)
	  Spa.Done(pool, now) -> boolean                  a soaking monster whose time is up
	  Spa.Active(buff, now) -> Buff?                  the buff while it lasts
	  Spa.GrowthMult(buff, now) -> number             1 + growthPct under a warm buff, else 1
	  Spa.OutputBoosts(buff) -> { { from, to, pct } }?   a mineral buff's window (Logic/Jobs boosts)
	  Spa.CanTake(m, soakId) -> (boolean, why?)       stage and growing rules
]]

local Config = require(script.Parent.Parent.Config)
local Formulas = require(script.Parent.Formulas)

local Rules = Config.Spa

local Spa = {}

function Spa.EmptyPool()
	return { monster = false, soak = false, at = 0, endsAt = 0 }
end

function Spa.PoolCount(isUnlocked: (string) -> boolean): number
	local n = 0
	for i, key in Rules.PoolUnlocks do
		if not isUnlocked(key) then
			break
		end
		n = i
	end
	return n
end

function Spa.Seconds(soakId: string): number
	local def = Rules.ById[soakId]
	return if def then def.minutes * 60 else 0
end

function Spa.Cost(soakId: string)
	local def = Rules.ById[soakId]
	if not def then
		return { honey = 0, food = {} }
	end
	return { honey = def.honey, food = { [def.food] = def.foodAmount } }
end

function Spa.Left(pool, now: number): number
	if type(pool) ~= "table" or not pool.monster then
		return 0
	end
	return math.max(0, (tonumber(pool.endsAt) or 0) - now)
end

function Spa.Done(pool, now: number): boolean
	return type(pool) == "table" and pool.monster ~= false and pool.monster ~= nil and Spa.Left(pool, now) <= 0
end

function Spa.Active(buff, now: number)
	if type(buff) ~= "table" or not Rules.ById[buff.soak] then
		return nil
	end
	return if (tonumber(buff.endsAt) or 0) > now then buff else nil
end

function Spa.GrowthMult(buff, now: number): number
	local b = Spa.Active(buff, now)
	local def = b and Rules.ById[b.soak]
	return if def and def.growthPct then 1 + def.growthPct else 1
end

function Spa.OutputBoosts(buff)
	local def = type(buff) == "table" and Rules.ById[buff.soak]
	if not def or not def.outputPct then
		return nil
	end
	return { { from = tonumber(buff.from) or 0, to = tonumber(buff.endsAt) or 0, pct = def.outputPct } }
end

function Spa.CanTake(m, soakId: string): (boolean, string?)
	local def = Rules.ById[soakId]
	if not def then
		return false, "That soak doesn't exist"
	end
	if type(m) ~= "table" or (m.stage or 1) < Rules.MinStage then
		return false, "Only Teens and Adults can soak in the spa"
	end
	if def.growing and not Formulas.MealsNeeded(m.stage or 1) then
		return false, "Only a growing monster gains from a Warm Soak"
	end
	return true, nil
end

return Spa
