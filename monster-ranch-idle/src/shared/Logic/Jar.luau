--[[
	Jar: coin-jar accrual and pen income rules. Pure maths shared by the Ranch system
	(authoritative) and the client (live jar display, "full in 2 h" hints).

	A pen's jar fills at `rate` coins/s from `jarAt` and stops at `rate × capSeconds`:
	  Jar.Value(jar, rate, jarAt, now, capSeconds) -> coins
	    = max(jar, min(jar + rate × (now − jarAt), rate × capSeconds))
	  The outer max keeps coins already in the jar when the rate later drops (a monster
	  left the pen): settled coins are never taken away, the jar just stops filling.
	  Clients should call this function rather than re-deriving it.

	Jar.Settle(pen, rate, capSeconds, now)          -- folds accrual into pen.jar, sets pen.jarAt = now
	Jar.SecondsToFull(jar, rate, capSeconds) -> n   -- 0 when full, math.huge when rate is 0
	Jar.IsFull(jar, rate, capSeconds) -> boolean
	Jar.CapSeconds(jarTier, opts?) -> seconds
	  opts = { vip = boolean?, hoarderMinutes = number?, bonusSeconds = number? }
	Jar.MonsterRate(baseRate, modifierPct, multiplier?) -> coins/s   -- one monster in a pen
	Jar.Collectable(jar) -> whole coins, remainder                    -- jars pay whole coins
]]

local Config = require(script.Parent.Parent.Config)

local Economy = Config.Economy

local Jar = {}

function Jar.Value(jar: number, rate: number, jarAt: number, now: number, capSeconds: number): number
	jar = jar or 0
	if rate <= 0 then
		return jar
	end
	local elapsed = math.max(0, now - (jarAt or now))
	local capCoins = rate * math.max(0, capSeconds)
	return math.max(jar, math.min(jar + rate * elapsed, capCoins))
end

function Jar.Settle(pen, rate: number, capSeconds: number, now: number)
	pen.jar = Jar.Value(pen.jar, rate, pen.jarAt, now, capSeconds)
	pen.jarAt = now
	return pen.jar
end

function Jar.IsFull(jar: number, rate: number, capSeconds: number): boolean
	return rate > 0 and jar >= rate * capSeconds
end

function Jar.SecondsToFull(jar: number, rate: number, capSeconds: number): number
	if rate <= 0 then
		return math.huge
	end
	return math.max(0, (rate * capSeconds - jar) / rate)
end

function Jar.CapSeconds(jarTier: number, opts: { vip: boolean?, hoarderMinutes: number?, bonusSeconds: number? }?): number
	local tiers = Economy.JarTiers
	local tier = tiers[math.clamp(jarTier or 1, 1, #tiers)]
	local o = opts or {}
	local seconds = tier.seconds
	if o.vip then
		seconds += Economy.VipJarBonusSeconds
	end
	seconds += (o.hoarderMinutes or 0) * 60
	seconds += o.bonusSeconds or 0
	return math.max(0, seconds)
end

function Jar.MonsterRate(baseRate: number, modifierPct: number, multiplier: number?): number
	return baseRate * math.max(0, 1 + (modifierPct or 0)) * (multiplier or 1)
end

function Jar.Collectable(jar: number): (number, number)
	local whole = math.floor(math.max(0, jar or 0))
	return whole, math.max(0, (jar or 0) - whole)
end

return Jar
