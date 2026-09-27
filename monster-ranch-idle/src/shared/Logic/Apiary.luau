--[[
	Apiary (update 3.12 · Honey & stars): the beehives' rules. Pure: the server settles and pays
	with them, the client shows rates, fill bars and times to full with the same functions.
	Numbers in Config.Apiary (see its header).

	Hive (profile.Apiary.hives[i]):
	  { monster = id | false, at = unix, stored = { [kind]: number } }
	  at      the last settle (assignment, collect or join): stored honey counts up to here
	  stored  honey made but not collected yet, by kind, with fractions (the carry)

	  Apiary.EmptyHive() -> Hive
	  Apiary.HiveCount(isUnlocked: (key) -> boolean) -> number
	  Apiary.Power(m) -> number                 W = SPD ÷ Config.Jobs.RefBase.spd
	  Apiary.PerHour(m) -> number               BasePerHour × √W × SproutBonus (Sprout keepers)
	  Apiary.Cap(m, extraHours?) -> number      honey a hive holds: PerHour × (CapHours + extra)
	  Apiary.Total(stored) -> number            the honey in a stored table (fractions included)
	  Apiary.KindAt(t) -> kindId                the honey of the season at t (Logic/Seasons.At)
	  Apiary.Settle(hive, m, now, extraHours?) -> stored
	                                            a new stored table: what the hive made from `at`
	                                            to `now`, split at every season turnover, stopping
	                                            at the cap (the hive itself is not changed)
	  Apiary.Pending(hive, m, now, extraHours?) -> number   stored honey now (for bars)
	  Apiary.SecondsToFull(hive, m, now, extraHours?) -> number   0 when full
	  Apiary.Take(stored) -> (whole: { [kind]: n }, rest: stored)   whole honey out, fractions kept
	  Apiary.RoyalJelly(userId, n) -> boolean   the n-th hive collect (with honey) finds Royal Jelly
	  Apiary.SellSeconds(kind, amount) -> number    seconds of ranch income for selling
	  Apiary.Name(kind) -> string
]]

local Config = require(script.Parent.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Rng = require(script.Parent.Rng)
local Seasons = require(script.Parent.Seasons)

local Rules = Config.Apiary

local Apiary = {}

local HOUR = 3600
local EPS = 1e-9

function Apiary.EmptyHive()
	return { monster = false, at = 0, stored = {} }
end

function Apiary.HiveCount(isUnlocked: (string) -> boolean): number
	local n = 0
	for _, key in Rules.HiveUnlocks do
		if isUnlocked(key) then
			n += 1
		else
			break
		end
	end
	return n
end

function Apiary.Power(m): number
	if type(m) ~= "table" then
		return 0
	end
	return (Formulas.Stats(m).spd or 0) / Config.Jobs.RefBase.spd
end

local function isSprout(m): boolean
	local ok, list = pcall(Formulas.Elements, m)
	if ok and type(list) == "table" then
		for _, e in list do
			if e == Rules.SproutElement then
				return true
			end
		end
	end
	return false
end
Apiary.IsSprout = isSprout

function Apiary.PerHour(m): number
	if type(m) ~= "table" then
		return 0
	end
	local rate = Rules.BasePerHour * math.sqrt(math.max(0, Apiary.Power(m)))
	if isSprout(m) then
		rate *= Rules.SproutBonus
	end
	return rate
end

local function hours(extraHours: number?): number
	local extra = if type(extraHours) == "number" and extraHours == extraHours then math.max(0, extraHours) else 0
	return Rules.CapHours + extra
end

function Apiary.Cap(m, extraHours: number?): number
	return Apiary.PerHour(m) * hours(extraHours)
end

function Apiary.Total(stored): number
	local n = 0
	for _, v in (if type(stored) == "table" then stored else {}) do
		if type(v) == "number" and v == v then
			n += v
		end
	end
	return n
end

function Apiary.KindAt(t: number): string
	local kind = Rules.BySeason[Seasons.At(t).id]
	return if kind then kind.id else Rules.Ids[1]
end

function Apiary.Settle(hive, m, now: number, extraHours: number?)
	local stored = {}
	for k, v in (if type(hive) == "table" and type(hive.stored) == "table" then hive.stored else {}) do
		if type(v) == "number" and v == v and v > 0 then
			stored[k] = v
		end
	end
	if type(hive) ~= "table" or not hive.monster or type(m) ~= "table" then
		return stored
	end
	local rate = Apiary.PerHour(m) / HOUR
	local room = Apiary.Cap(m, extraHours) - Apiary.Total(stored)
	local t = tonumber(hive.at) or now
	while t < now and room > EPS and rate > 0 do
		local season = Seasons.At(t)
		local stop = math.min(now, season.endsAt)
		if stop <= t then
			-- Never loop forever on a bad season window.
			stop = now
		end
		local kind = Apiary.KindAt(t)
		local made = math.min(room, rate * (stop - t))
		stored[kind] = (stored[kind] or 0) + made
		room -= made
		t = stop
	end
	return stored
end

function Apiary.Pending(hive, m, now: number, extraHours: number?): number
	return Apiary.Total(Apiary.Settle(hive, m, now, extraHours))
end

function Apiary.SecondsToFull(hive, m, now: number, extraHours: number?): number
	local rate = Apiary.PerHour(m)
	if rate <= 0 then
		return 0
	end
	local left = Apiary.Cap(m, extraHours) - Apiary.Pending(hive, m, now, extraHours)
	return math.max(0, math.ceil(left / rate * HOUR))
end

function Apiary.Take(stored)
	local whole, rest = {}, {}
	for _, id in Rules.AllIds do
		local v = type(stored) == "table" and stored[id]
		if type(v) == "number" and v == v and v > 0 then
			-- A hair under a whole number (float sums) still counts as that number.
			local n = math.floor(v + 1e-6)
			if n > 0 then
				whole[id] = n
			end
			local left = v - n
			if left > 1e-6 then
				rest[id] = left
			end
		end
	end
	return whole, rest
end

function Apiary.RoyalJelly(userId: number, n: number): boolean
	return Rng.new(Rng.seed("apiary", userId, n)):Chance(Rules.RoyalJelly.chance)
end

function Apiary.SellSeconds(kind: string, amount: number): number
	return (Rules.SellSeconds[kind] or 0) * math.max(0, math.floor(amount))
end

function Apiary.Name(kind: string): string
	local def = Rules.ById[kind]
	return if def then def.name else kind
end

return Apiary
