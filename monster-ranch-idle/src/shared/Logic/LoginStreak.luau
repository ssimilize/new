--[[
	LoginStreak (logic): pure rules of the daily login calendar (Config.LoginStreak). Used by the
	server (Systems/LoginStreak) to claim and by the client (LoginStreak screen, HUD badge) to
	preview, so both always agree. Days are UTC day numbers (unix // 86400).

	State (profile.LoginStreak):
	  { last, streak, pos, track, cycles, total, best, shield, shieldWeek, savedDay }
	  last       UTC day of the last claim (0 = never)
	  streak     consecutive days claimed (a shield keeps it going over one missed day)
	  pos        calendar day (1..7) of the last claim, 0 = none
	  track      days claimed in the current 28-day milestone track (1..28 after a claim)
	  cycles     milestone tracks completed
	  total      days claimed ever; best = longest streak
	  shield     shields held (0..Shield.max); shieldWeek = UTC week of the last refill
	  savedDay   UTC day a shield last saved the streak (the calendar says so that day)

	API:
	  LoginStreak.Week(day) -> number                   UTC week (Monday start)
	  LoginStreak.Default(today) -> state
	  LoginStreak.ShieldsAt(state, day) -> n            shields held on `day` after weekly refills
	  LoginStreak.Preview(state, today) -> preview
	    { canClaim, pos, streak, track, shieldUsed, restarted, shields, milestone = def|nil }
	  LoginStreak.Apply(state, preview, today)          writes a claim into state (mutates)
	  LoginStreak.Items(preview, cycles) -> { item }    day items + milestone items (unresolved)
	  LoginStreak.Resolve(items, isUnlocked) -> { item } ladder eggs → real egg ids
	  LoginStreak.Deadline(state, today) -> unix?       end of the last UTC day that keeps a
	                                                    shield-less streak alive (nil: no streak
	                                                    or a shield covers the next miss)
]]

local Config = require(script.Parent.Parent.Config)

local LoginStreak = {}

local DAY = 86400

local function cfg()
	return Config.LoginStreak
end

function LoginStreak.Week(day: number): number
	return (day + 3) // 7 -- day 4 (Mon 5 Jan 1970) starts week 1
end

function LoginStreak.Default(today: number)
	return {
		last = 0,
		streak = 0,
		pos = 0,
		track = 0,
		cycles = 0,
		total = 0,
		best = 0,
		shield = cfg().Shield.max,
		shieldWeek = LoginStreak.Week(today),
		savedDay = 0,
	}
end

function LoginStreak.ShieldsAt(state, day: number): number
	local held = tonumber(state.shield) or 0
	if LoginStreak.Week(day) > (tonumber(state.shieldWeek) or 0) then
		held = cfg().Shield.max
	end
	return math.clamp(held, 0, cfg().Shield.max)
end

function LoginStreak.Preview(state, today: number)
	local last = tonumber(state.last) or 0
	local shields = LoginStreak.ShieldsAt(state, today)
	local preview = { canClaim = today > last, shields = shields, shieldUsed = false, restarted = false }
	local missed = if last > 0 then today - last - 1 else -1
	local continues = false
	if last > 0 and missed == 0 then
		continues = true
	elseif last > 0 and missed >= 1 and missed <= shields then
		continues = true
		preview.shieldUsed = true
		preview.shields = shields - missed
	end
	preview.restarted = last > 0 and missed >= 1 and not continues
	if continues then
		preview.pos = (tonumber(state.pos) or 0) % #cfg().Days + 1
		preview.streak = (tonumber(state.streak) or 0) + 1
	else
		preview.pos = 1
		preview.streak = 1
	end
	local track = tonumber(state.track) or 0
	if track >= cfg().TrackLength then
		track = 0
	end
	preview.track = track + 1
	for _, milestone in cfg().Milestones do
		if milestone.day == preview.track then
			preview.milestone = milestone
		end
	end
	return preview
end

function LoginStreak.Apply(state, preview, today: number)
	state.last = today
	state.pos = preview.pos
	state.streak = preview.streak
	state.best = math.max(tonumber(state.best) or 0, preview.streak)
	state.total = (tonumber(state.total) or 0) + 1
	state.track = preview.track
	if preview.track >= cfg().TrackLength then
		state.cycles = (tonumber(state.cycles) or 0) + 1
	end
	state.shield = preview.shields
	state.shieldWeek = math.max(tonumber(state.shieldWeek) or 0, LoginStreak.Week(today))
	if preview.shieldUsed then
		state.savedDay = today
	end
end

local function copyAll(list, out)
	for _, item in list do
		table.insert(out, table.clone(item))
	end
end

function LoginStreak.Items(preview, cycles: number)
	local out = {}
	copyAll(cfg().Days[preview.pos] or {}, out)
	local milestone = preview.milestone
	if milestone then
		copyAll(if milestone.first and (tonumber(cycles) or 0) == 0 then milestone.first else milestone.items, out)
	end
	return out
end

function LoginStreak.Resolve(items, isUnlocked: (string) -> boolean)
	local ladder = cfg().EggLadder
	local best = 1
	for i, rung in ladder do
		if isUnlocked(rung.unlock) then
			best = i
		end
	end
	local out = {}
	for _, item in items do
		local copy = table.clone(item)
		if copy.kind == "egg" and copy.id == "ladder" then
			copy.id = ladder[math.min(#ladder, best + (tonumber(copy.step) or 0))].egg
			copy.step = nil
		end
		copy.amount = copy.amount or 1
		table.insert(out, copy)
	end
	return out
end

function LoginStreak.Deadline(state, today: number): number?
	local last = tonumber(state.last) or 0
	if last <= 0 or (tonumber(state.streak) or 0) <= 0 then
		return nil
	end
	-- The claim must land on day last + 1; a claim on last + 2 needs a shield on that day.
	local mustClaimBy = last + 1
	if mustClaimBy < today then
		return nil -- already missed: the next claim uses a shield or restarts
	end
	if LoginStreak.ShieldsAt(state, mustClaimBy + 1) > 0 then
		return nil
	end
	return (mustClaimBy + 1) * DAY
end

return LoginStreak
