--[[
	RateLimiter: token buckets per (player, action). `rate` tokens refill per second and the
	bucket holds max(2, rate × 2) tokens, so short bursts (double taps) are allowed.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(clock)
	return setmetatable({ _clock = clock, _buckets = {} }, RateLimiter)
end

function RateLimiter:Allow(player: any, action: string, rate: number): boolean
	local now = self._clock.Precise()
	local perPlayer = self._buckets[player]
	if not perPlayer then
		perPlayer = {}
		self._buckets[player] = perPlayer
	end
	local capacity = math.max(2, rate * 2)
	local bucket = perPlayer[action]
	if not bucket then
		bucket = { tokens = capacity, at = now }
		perPlayer[action] = bucket
	end
	bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.at) * rate)
	bucket.at = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:Forget(player: any)
	self._buckets[player] = nil
end

return RateLimiter
