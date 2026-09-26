--[[
	Reminders (logic): pure planning rules for offline reminders (Config.Reminders). The server
	system (Systems/Reminders) gathers the facts when a player leaves and stores what Plan
	returns; Allow gates each send against the per-player daily cap.

	API:
	  Reminders.LocalHour(t, offset) -> 0..24
	  Reminders.Place(due, expiresAt, now, offset?) -> due?   moves a time out of quiet hours
	      (to the next quiet-hours end, or back before the quiet start when that would miss
	      expiresAt); nil = no good time left. offset nil = no quiet-hours rule.
	  Reminders.Plan(facts, now) -> { { kind, dueAt, expiresAt } }   soonest first, ≤ MaxPlanned
	      facts = { eggsReadyAt?, expeditionsBackAt?, stampede = boolean?, streakDeadline?,
	                offset?, templates = { [kind]: string }? }
	  Reminders.Allow(record?, now) -> (ok, record)   record = { day, n, last, prev } per player
	  Reminders.Refund(record?) -> record?            gives back a send that failed
]]

local Config = require(script.Parent.Parent.Config)

local Reminders = {}

local DAY = 86400
local HOUR = 3600

local function cfg()
	return Config.Reminders
end

function Reminders.LocalHour(t: number, offset: number): number
	return ((t + offset * HOUR) % DAY) / HOUR
end

local function isQuiet(hour: number): boolean
	local q = cfg().Quiet
	if q.start > q.stop then
		return hour >= q.start or hour < q.stop
	end
	return hour >= q.start and hour < q.stop
end

function Reminders.Place(due: number, expiresAt: number, now: number, offset: number?): number?
	if offset == nil then
		return if due < expiresAt then due else nil
	end
	local hour = Reminders.LocalHour(due, offset)
	if not isQuiet(hour) then
		return if due < expiresAt then due else nil
	end
	local q = cfg().Quiet
	local untilStop = ((q.stop - hour) % 24) * HOUR
	local later = due + untilStop
	if later < expiresAt then
		return later
	end
	-- Too late after the quiet hours: try just before they started.
	local sinceStart = ((hour - q.start) % 24) * HOUR
	local earlier = due - sinceStart - 15 * 60
	if earlier > now + cfg().MinAwaySeconds * 0.5 and earlier < expiresAt then
		return earlier
	end
	return nil
end

local function on(facts, kind: string): boolean
	local templates = facts.templates or cfg().Templates
	return type(templates[kind]) == "string" and templates[kind] ~= ""
end

function Reminders.Plan(facts, now: number)
	local c = cfg()
	local earliest = now + c.MinAwaySeconds
	local planned = {}
	local function add(kind: string, due: number, expiresAt: number)
		if not on(facts, kind) then
			return
		end
		local placed = Reminders.Place(due, expiresAt, now, facts.offset)
		if placed and placed >= now then
			table.insert(planned, { kind = kind, dueAt = math.floor(placed), expiresAt = math.floor(expiresAt) })
		end
	end
	local eggs = tonumber(facts.eggsReadyAt)
	if eggs and eggs > now then
		local due = math.max(eggs, earliest)
		add("egg", due, due + c.ExpireSeconds)
	end
	local back = tonumber(facts.expeditionsBackAt)
	if back and back > now then
		local due = math.max(back, earliest)
		add("expedition", due, due + c.ExpireSeconds)
	end
	local period = Config.Boss.Period
	if facts.stampede and period and period > 0 then
		local start = math.ceil((now + c.Stampede.minAwaySeconds) / period) * period
		add("stampede", start - c.Stampede.leadSeconds, start)
	end
	local deadline = tonumber(facts.streakDeadline)
	if deadline and deadline > earliest then
		local due = math.max(earliest, deadline - c.Streak.hoursLeft * HOUR)
		add("streak", due, deadline - 15 * 60)
	end
	table.sort(planned, function(a, b)
		return a.dueAt < b.dueAt
	end)
	while #planned > c.MaxPlanned do
		table.remove(planned)
	end
	return planned
end

function Reminders.Allow(record, now: number)
	local c = cfg()
	local today = now // DAY
	local r = if type(record) == "table" then table.clone(record) else { day = today, n = 0, last = 0 }
	if r.day ~= today then
		r.day = today
		r.n = 0
	end
	if (tonumber(r.n) or 0) >= c.MaxPerDay or now - (tonumber(r.last) or 0) < c.MinGapSeconds then
		return false, r
	end
	r.n = (tonumber(r.n) or 0) + 1
	r.prev = tonumber(r.last) or 0
	r.last = now
	return true, r
end

function Reminders.Refund(record)
	if type(record) ~= "table" or (tonumber(record.n) or 0) <= 0 then
		return nil
	end
	local r = table.clone(record)
	r.n -= 1
	r.last = tonumber(r.prev) or 0
	return r
end

return Reminders
