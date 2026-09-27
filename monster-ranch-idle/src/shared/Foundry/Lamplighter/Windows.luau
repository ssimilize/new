--!strict
-- Lit windows (LT2 step 1): a building's panes light when it is occupied and its window schedule
-- says lamps are lit, each pane `delay` seconds behind the building (a staggered switch-on and
-- switch-off). Pure: pane k is lit at t iff the building was lit and occupied at t - delay(k).
--
-- The schedule maths is Guildhall's BuildingLife Logic (windowsLit, pickIn, salt, inWindow),
-- transcribed so a building keeps the switch hours it has today.

local Windows = {}

-- Is `hour` inside [a, b) on a 24 h clock (wrapping past midnight)?
function Windows.inWindow(hour: number, a: number, b: number): boolean
	local h, s, e = hour % 24, a % 24, b % 24
	if s <= e then
		return h >= s and h < e
	end
	return h >= s or h < e
end

-- A point inside an hour range, which may wrap past midnight ({ 22.5, 1.5 }).
function Windows.pickIn(range: { number }, u: number): number
	local a, b = range[1], range[2]
	if b < a then
		b += 24
	end
	return (a + (b - a) * u) % 24
end

-- A second, independent 0..1 from the same seed (Guildhall Logic.salt).
function Windows.salt(seed: number, n: number): number
	local x = math.sin((seed * 1000 + n * 97.13) * 12.9898) * 43758.5453
	return x - math.floor(x)
end

-- Guildhall Logic.windowsLit: on from the building's own hour in `on` until its own hour in
-- `off`; with `sleep` the house goes dark at its sleep hour and an early riser (half the houses)
-- lights up again at its `wake` hour.
function Windows.scheduleLit(hour: number, seed: number, schedule: any): boolean
	local on = Windows.pickIn(schedule.on, seed)
	local off = Windows.pickIn(schedule.off, Windows.salt(seed, 1))
	if not Windows.inWindow(hour, on, off) then
		return false
	end
	if schedule.sleep then
		local sleep = Windows.pickIn(schedule.sleep, Windows.salt(seed, 2))
		local wake = schedule.wake and Windows.pickIn(schedule.wake, Windows.salt(seed, 3)) or off
		local riser = Windows.salt(seed, 4) < 0.5
		if Windows.inWindow(hour, sleep, riser and wake or off) then
			return false
		end
	end
	return true
end

-- The schedule id a building follows: its own `schedule`, else the first tag of `order` it
-- carries, else "default".
function Windows.scheduleFor(fixture: any, cfg: any): string
	if type(fixture.schedule) == "string" and cfg.schedules[fixture.schedule] then
		return fixture.schedule
	end
	local have = {}
	for _, t in fixture.tags or {} do
		have[t] = true
	end
	for _, name in cfg.order or {} do
		if have[name] and cfg.schedules[name] then
			return name
		end
	end
	return "default"
end

return Windows
