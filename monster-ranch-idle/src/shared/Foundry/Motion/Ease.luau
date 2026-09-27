--!strict
-- Ease: the easing curves every Motion clip uses, by name. A copy of Guildhall's kernel
-- ClientAnim easing (src/kernel/ClientAnim.luau, read 2026-09-27) so a ClipDoc samples to the
-- same numbers as the clip it came from; tests/Convert.spec and the motion round-trip prove it.
--
--   Ease.ease("quadInOut", 0.25) -> 0.125   (t clamped to 0..1; an unknown name is linear)

local Ease = {}

local PI = math.pi

local function polyIn(p: number): (number) -> number
	return function(t)
		return t ^ p
	end
end
local function polyOut(p: number): (number) -> number
	return function(t)
		return 1 - (1 - t) ^ p
	end
end
local function polyInOut(p: number): (number) -> number
	return function(t)
		if t < 0.5 then
			return 2 ^ (p - 1) * t ^ p
		end
		return 1 - ((-2 * t + 2) ^ p) / 2
	end
end

local BACK_C1 = 1.70158
local BACK_C2 = BACK_C1 * 1.525
local BACK_C3 = BACK_C1 + 1
local ELASTIC_C4 = (2 * PI) / 3
local ELASTIC_C5 = (2 * PI) / 4.5

local function bounceOut(t: number): number
	local n1, d1 = 7.5625, 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	end
	t -= 2.625 / d1
	return n1 * t * t + 0.984375
end

local EASINGS: { [string]: (number) -> number } = {
	linear = function(t)
		return t
	end,
	constant = function(t)
		return if t >= 1 then 1 else 0
	end,
	sineIn = function(t)
		return 1 - math.cos(t * PI / 2)
	end,
	sineOut = function(t)
		return math.sin(t * PI / 2)
	end,
	sineInOut = function(t)
		return -(math.cos(PI * t) - 1) / 2
	end,
	quadIn = polyIn(2),
	quadOut = polyOut(2),
	quadInOut = polyInOut(2),
	cubicIn = polyIn(3),
	cubicOut = polyOut(3),
	cubicInOut = polyInOut(3),
	quartIn = polyIn(4),
	quartOut = polyOut(4),
	quartInOut = polyInOut(4),
	quintIn = polyIn(5),
	quintOut = polyOut(5),
	quintInOut = polyInOut(5),
	expoIn = function(t)
		return if t <= 0 then 0 else 2 ^ (10 * t - 10)
	end,
	expoOut = function(t)
		return if t >= 1 then 1 else 1 - 2 ^ (-10 * t)
	end,
	expoInOut = function(t)
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		elseif t < 0.5 then
			return 2 ^ (20 * t - 10) / 2
		end
		return (2 - 2 ^ (-20 * t + 10)) / 2
	end,
	circIn = function(t)
		return 1 - math.sqrt(1 - t * t)
	end,
	circOut = function(t)
		return math.sqrt(1 - (t - 1) ^ 2)
	end,
	circInOut = function(t)
		if t < 0.5 then
			return (1 - math.sqrt(1 - (2 * t) ^ 2)) / 2
		end
		return (math.sqrt(1 - (-2 * t + 2) ^ 2) + 1) / 2
	end,
	backIn = function(t)
		return BACK_C3 * t * t * t - BACK_C1 * t * t
	end,
	backOut = function(t)
		return 1 + BACK_C3 * (t - 1) ^ 3 + BACK_C1 * (t - 1) ^ 2
	end,
	backInOut = function(t)
		if t < 0.5 then
			return ((2 * t) ^ 2 * ((BACK_C2 + 1) * 2 * t - BACK_C2)) / 2
		end
		return ((2 * t - 2) ^ 2 * ((BACK_C2 + 1) * (t * 2 - 2) + BACK_C2) + 2) / 2
	end,
	elasticIn = function(t)
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		end
		return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * ELASTIC_C4)
	end,
	elasticOut = function(t)
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		end
		return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * ELASTIC_C4) + 1
	end,
	elasticInOut = function(t)
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		elseif t < 0.5 then
			return -(2 ^ (20 * t - 10) * math.sin((20 * t - 11.125) * ELASTIC_C5)) / 2
		end
		return (2 ^ (-20 * t + 10) * math.sin((20 * t - 11.125) * ELASTIC_C5)) / 2 + 1
	end,
	bounceIn = function(t)
		return 1 - bounceOut(1 - t)
	end,
	bounceOut = bounceOut,
	bounceInOut = function(t)
		if t < 0.5 then
			return (1 - bounceOut(1 - 2 * t)) / 2
		end
		return (1 + bounceOut(2 * t - 1)) / 2
	end,
}
Ease.EASINGS = table.freeze(table.clone(EASINGS))

local EASING_NAMES: { string } = {}
for name in pairs(EASINGS) do
	table.insert(EASING_NAMES, name)
end
table.sort(EASING_NAMES)
Ease.EASING_NAMES = table.freeze(EASING_NAMES)

-- ease(name, t): t is clamped to [0, 1]; an unknown name is linear.
function Ease.ease(name: string?, t: number): number
	if t <= 0 then
		t = 0
	elseif t >= 1 then
		t = 1
	end
	local fn = EASINGS[name or "linear"] or EASINGS.linear
	return fn(t)
end

function Ease.isEasing(name: any): boolean
	return type(name) == "string" and EASINGS[name] ~= nil
end

return Ease
