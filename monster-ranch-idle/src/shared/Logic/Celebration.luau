--[[
	Celebration: how big a reward feels (pure; used by the client's Celebrate controller).

	Four sizes, small < medium < big < huge. Coins are judged against the player's income
	(a payout worth hours of the ranch is bigger than the same number for a new player),
	gems and items by fixed steps.

	  Celebration.CoinSize(coins, incomePerSecond) -> size
	  Celebration.GemSize(gems) -> size
	  Celebration.Size(items, incomePerSecond) -> size        items = { Reward }
	  Celebration.Max(a, b) -> size                           the bigger of two sizes
	  Celebration.Plan(size, low?) -> plan                    what the client plays (low = Settings.lowGraphics)
	  Celebration.TickKey(index, count, streak) -> sound key  coin ticks climb over a stream and a streak
]]

local Celebration = {}

Celebration.Sizes = { "small", "medium", "big", "huge" }
Celebration.Rank = { small = 1, medium = 2, big = 3, huge = 4 }

-- Seconds of ranch income a coin payout has to be worth for each size.
Celebration.CoinSeconds = { medium = 120, big = 900, huge = 3600 }
-- Below this many coins a payout is always small, whatever the income.
Celebration.CoinFloor = 50
Celebration.GemSteps = { medium = 10, big = 50, huge = 250 }
Celebration.TickSteps = 5

-- plan fields: icons flown per currency, countTime (seconds the HUD total counts up), shower
-- (falling coins), confetti (pieces), shake (camera studs), fov (degrees of FOV kick), rumble
-- (gamepad motor 0..1), sound (Config.Sounds key or nil).
Celebration.Plans = {
	small = { icons = 3, countTime = 0.45, shower = 0, confetti = 0, shake = 0, fov = 0, rumble = 0, sound = nil },
	medium = { icons = 6, countTime = 0.7, shower = 0, confetti = 0, shake = 0, fov = 0, rumble = 0.2, sound = nil },
	big = { icons = 10, countTime = 1.1, shower = 16, confetti = 22, shake = 0, fov = 0, rumble = 0.45, sound = "CelebrateBig" },
	huge = { icons = 14, countTime = 1.6, shower = 26, confetti = 36, shake = 0.35, fov = 6, rumble = 0.8, sound = "CelebrateHuge" },
}

function Celebration.Max(a: string?, b: string?): string
	local ra = Celebration.Rank[a or ""] or 1
	local rb = Celebration.Rank[b or ""] or 1
	return Celebration.Sizes[math.max(ra, rb)]
end

function Celebration.CoinSize(coins: number, incomePerSecond: number?): string
	local amount = tonumber(coins) or 0
	if amount < Celebration.CoinFloor then
		return "small"
	end
	local seconds = amount / math.max(tonumber(incomePerSecond) or 0, 1)
	local steps = Celebration.CoinSeconds
	if seconds >= steps.huge then
		return "huge"
	elseif seconds >= steps.big then
		return "big"
	elseif seconds >= steps.medium then
		return "medium"
	end
	return "small"
end

function Celebration.GemSize(gems: number): string
	local amount = tonumber(gems) or 0
	local steps = Celebration.GemSteps
	if amount >= steps.huge then
		return "huge"
	elseif amount >= steps.big then
		return "big"
	elseif amount >= steps.medium then
		return "medium"
	end
	return "small"
end

-- An egg, a monster or a keepsake is always worth at least a medium moment.
local ITEM_KINDS = { egg = true, monster = true, accessory = true, decor = true }

function Celebration.Size(items: { any }?, incomePerSecond: number?): string
	local size = "small"
	for _, item in items or {} do
		if type(item) == "table" then
			local amount = tonumber(item.amount) or 0
			if item.kind == "coins" then
				size = Celebration.Max(size, Celebration.CoinSize(amount, incomePerSecond))
			elseif item.kind == "gems" then
				size = Celebration.Max(size, Celebration.GemSize(amount))
			elseif ITEM_KINDS[item.kind] then
				size = Celebration.Max(size, "medium")
			end
		end
	end
	return size
end

function Celebration.Plan(size: string?, low: boolean?)
	local plan = table.clone(Celebration.Plans[size or ""] or Celebration.Plans.small)
	if low then
		-- Reduced motion: the counters and one cue stay; swarms, shake and the FOV kick go.
		plan.icons = 0
		plan.shower = 0
		plan.confetti = 0
		plan.shake = 0
		plan.fov = 0
		plan.countTime = math.min(plan.countTime, 0.4)
	end
	return plan
end

-- The coin tick for arrival `index` of `count`: the pitch step climbs over the stream, and a
-- streak of quick collects starts it higher. Keys are "CoinTick1" .. "CoinTick5".
function Celebration.TickKey(index: number, count: number, streak: number?): string
	local steps = Celebration.TickSteps
	local along = if count > 1 then math.floor((index - 1) * steps / count) else 0
	local step = math.clamp(1 + along + math.max(0, (streak or 1) - 1), 1, steps)
	return "CoinTick" .. step
end

return Celebration
