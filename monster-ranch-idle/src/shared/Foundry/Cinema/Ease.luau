--!strict
-- Ease: named easing curves, t in [0, 1] -> [0, 1] with f(0) = 0 and f(1) = 1.
-- The names are Guildhall GodCamera's (Logic.ease) plus Monster Ranch's glide ("smoother",
-- Logic/Cinematic.Ease, Perlin's smootherstep). Unknown names ease linearly.

local Ease = {}

local CURVES: { [string]: (number) -> number } = {
	linear = function(t)
		return t
	end,
	quadOut = function(t)
		return 1 - (1 - t) * (1 - t)
	end,
	cubicOut = function(t)
		return 1 - (1 - t) ^ 3
	end,
	quadInOut = function(t)
		if t < 0.5 then
			return 2 * t * t
		end
		return 1 - ((-2 * t + 2) ^ 2) / 2
	end,
	cubicInOut = function(t)
		if t < 0.5 then
			return 4 * t * t * t
		end
		return 1 - ((-2 * t + 2) ^ 3) / 2
	end,
	sineInOut = function(t)
		return -(math.cos(math.pi * t) - 1) / 2
	end,
	smoother = function(t)
		return t * t * t * (t * (t * 6 - 15) + 10)
	end,
}

Ease.NAMES = table.freeze({ "linear", "quadOut", "cubicOut", "quadInOut", "cubicInOut", "sineInOut", "smoother" })
-- Curves whose slope is zero at both ends (a camera starts and stops without a jolt).
Ease.SOFT_BOTH_ENDS = table.freeze({ quadInOut = true, cubicInOut = true, sineInOut = true, smoother = true })

function Ease.known(name: any): boolean
	return type(name) == "string" and CURVES[name] ~= nil
end

function Ease.apply(name: string?, t: number): number
	local x = math.clamp(t, 0, 1)
	local f = CURVES[name or "linear"] or CURVES.linear
	return f(x)
end

return Ease
