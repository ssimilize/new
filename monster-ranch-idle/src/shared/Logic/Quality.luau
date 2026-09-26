--[[
	Logic/Quality (glow-up P): the pure rules behind the automatic quality levels and the
	distance LOD (Config/Quality). Unit-tested in Quality.spec; used by the client Quality
	module / controller, World and MonsterAnimator.

	Levels are ranks: 1 = low, 2 = medium, 3 = high.

		Quality.Choice(settings) -> "auto" | "high" | "low"
		    The player's Graphics choice from profile.Settings. lowGraphics == true is an explicit
		    Low (saves from before the choice existed stay low); else settings.graphics.
		Quality.Resolve(choice, autoLevel) -> level   pinned choices win; auto = the stepper's level
		Quality.Median(list) -> number                (does not modify list)

		Quality.NewStepper(cfg, now) -> stepper        cfg = Config.Quality.Auto
		Quality.Sample(stepper, dtSeconds, now)        one frame; hitches and held frames are dropped
		Quality.Hold(stepper, now, seconds?)           ignore frames until now + seconds (cfg.hold)
		Quality.Evaluate(stepper, now) -> level, changed   call about once a second
		Quality.Reset(stepper, now, level?)            forget samples (a pinned choice went back to auto)

		Quality.PenCap(lod, level, own, distance, ownCap) -> number   monsters drawn per pen
		Quality.Band(lod, level, distance) -> 1 | 2 | 3                near / mid / far (plots)
		Quality.EffectsOn(lod, level, own, distance) -> boolean       auras etc. on another plot
		Quality.AnimInterval(lod, level, own, distance, onScreen) -> number?
		    seconds between animator updates; 0 = every frame; nil = paused (beyond lod.animPause)
]]

local Quality = {}

local VALID = { auto = true, high = true, low = true }

function Quality.Choice(settings: any): string
	if type(settings) ~= "table" then
		return "auto"
	end
	if settings.lowGraphics == true then
		return "low"
	end
	local g = settings.graphics
	if g == "high" then
		return "high"
	end
	-- "low" saved without lowGraphics (the old toggle switched it back off) reads as auto.
	return if VALID[g] and g ~= "low" then g else "auto"
end

function Quality.Resolve(choice: string, autoLevel: number): number
	if choice == "high" then
		return 3
	elseif choice == "low" then
		return 1
	end
	return math.clamp(math.floor(tonumber(autoLevel) or 3), 1, 3)
end

function Quality.Median(list: { number }): number
	local n = #list
	if n == 0 then
		return 0
	end
	local copy = table.clone(list)
	table.sort(copy)
	if n % 2 == 1 then
		return copy[(n + 1) / 2]
	end
	return (copy[n / 2] + copy[n / 2 + 1]) / 2
end

-- ─── The Auto stepper ─────────────────────────────────────────────────────────────────

export type Stepper = {
	cfg: any,
	level: number,
	times: { number }, -- sample timestamps (seconds)
	ms: { number }, -- frame times (ms), parallel to times
	head: number, -- index of the oldest live sample
	holdUntil: number,
	lastChange: number,
	lastUpAt: number,
	bad: number,
	good: number,
	upAfter: { [number]: number },
	median: number,
}

function Quality.NewStepper(cfg, now: number): Stepper
	return {
		cfg = cfg,
		level = math.clamp(cfg.start or 3, 1, 3),
		times = {},
		ms = {},
		head = 1,
		holdUntil = now + (cfg.warmup or 0),
		lastChange = -math.huge,
		lastUpAt = -math.huge,
		bad = 0,
		good = 0,
		upAfter = {},
		median = 0,
	}
end

local function compact(s: Stepper)
	if s.head > 64 and s.head > #s.times / 2 then
		s.times = table.move(s.times, s.head, #s.times, 1, {})
		s.ms = table.move(s.ms, s.head, #s.ms, 1, {})
		s.head = 1
	end
end

local function trim(s: Stepper, now: number)
	local oldest = now - (s.cfg.window or 4)
	while s.head <= #s.times and s.times[s.head] < oldest do
		s.head += 1
	end
	compact(s)
end

function Quality.Sample(s: Stepper, dt: number, now: number)
	if type(dt) ~= "number" or dt <= 0 or now < s.holdUntil then
		return
	end
	local ms = dt * 1000
	if ms >= (s.cfg.hitchMs or 250) then
		return
	end
	table.insert(s.times, now)
	table.insert(s.ms, ms)
end

function Quality.Hold(s: Stepper, now: number, seconds: number?)
	s.holdUntil = math.max(s.holdUntil, now + (seconds or s.cfg.hold or 2))
	-- Frames just before a screen opened or a teleport are part of the hitch too.
	s.times, s.ms, s.head = {}, {}, 1
	s.bad, s.good = 0, 0
end

function Quality.Reset(s: Stepper, now: number, level: number?)
	s.times, s.ms, s.head = {}, {}, 1
	s.bad, s.good = 0, 0
	s.holdUntil = math.max(s.holdUntil, now + (s.cfg.hold or 2))
	if level then
		s.level = math.clamp(level, 1, 3)
	end
end

function Quality.Evaluate(s: Stepper, now: number): (number, boolean)
	trim(s, now)
	local cfg = s.cfg
	local live = table.move(s.ms, s.head, #s.ms, 1, {})
	if #live < (cfg.minSamples or 1) then
		return s.level, false
	end
	local median = Quality.Median(live)
	s.median = median
	local down = cfg.down[s.level]
	local up = cfg.up[s.level]
	if down and median > down then
		s.bad += 1
		s.good = 0
	elseif up and median < up then
		s.good += 1
		s.bad = 0
	else
		s.bad, s.good = 0, 0
	end
	if now - s.lastChange < (cfg.cooldown or 0) then
		return s.level, false
	end
	if s.bad >= (cfg.downAfter or 3) and s.level > 1 then
		local from = s.level
		s.level -= 1
		if now - s.lastUpAt < (cfg.relapse or 0) then
			-- It could not hold the level it just climbed to: wait longer before trying again.
			local current = s.upAfter[s.level] or cfg.upAfter
			s.upAfter[s.level] = math.min(current * 2, cfg.upAfterMax or current * 2)
		end
		s.lastChange = now
		s.bad, s.good = 0, 0
		s.times, s.ms, s.head = {}, {}, 1
		return s.level, from ~= s.level
	end
	local needed = s.upAfter[s.level] or cfg.upAfter
	if s.good >= needed and s.level < 3 then
		s.level += 1
		s.lastChange = now
		s.lastUpAt = now
		s.bad, s.good = 0, 0
		s.times, s.ms, s.head = {}, {}, 1
		return s.level, true
	end
	return s.level, false
end

-- ─── Distance LOD ─────────────────────────────────────────────────────────────────────

function Quality.Band(lod, level: number, distance: number): number
	local b = lod.bands[level] or lod.bands[3]
	if distance >= b[2] then
		return 3
	elseif distance >= b[1] then
		return 2
	end
	return 1
end

function Quality.PenCap(lod, level: number, own: boolean, distance: number, ownCap: number): number
	if own then
		return ownCap
	end
	local caps = lod.penCap[level] or lod.penCap[3]
	return math.min(caps[Quality.Band(lod, level, distance)], ownCap)
end

function Quality.EffectsOn(lod, level: number, own: boolean, distance: number): boolean
	if own then
		return true
	end
	return distance <= (lod.effectsDistance[level] or 0)
end

function Quality.AnimInterval(lod, level: number, own: boolean, distance: number, onScreen: boolean): number?
	if distance > lod.animPause then
		return nil
	end
	local intervals = lod.animInterval
	local rate
	if not own and distance > lod.animFar then
		rate = intervals.far[level]
	elseif distance > lod.animMid then
		rate = intervals.mid[level]
	else
		rate = intervals.near[level]
	end
	if not onScreen then
		rate = math.max(rate or 0, intervals.offScreen)
	end
	return rate or 0
end

return Quality
