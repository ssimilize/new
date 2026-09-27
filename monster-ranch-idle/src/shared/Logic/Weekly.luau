--[[
	Weekly (update 3.8): pure rules for the weekly goals and their chest (Config/Weekly). Used by
	the Weekly system, the Quests screen's Weekly tab and the HUD badge. No Roblox APIs.

	Section shape (profile.Weekly): { week, goals = { { id, progress } }, claimed = { bool, bool, bool } }
]]

local Rng = require(script.Parent.Rng)
local Config = require(script.Parent.Parent.Config)

local Cfg = Config.Weekly

local Weekly = {}

-- Whether a goal can be done in `week` at all. A goal with `during = "titan"` needs a titan
-- invasion that starts inside that week (Config.Titan.Schedule); invasions are rare and dated,
-- so drawing it in any other week would leave a goal nobody can finish.
function Weekly.Available(def, week: number): boolean
	if def.during == "titan" then
		local from = Config.Leaderboards.WeekEndsAt(week - 1)
		local to = Config.Leaderboards.WeekEndsAt(week)
		for _, entry in Config.Titan.Schedule do
			if entry.startsAt >= from and entry.startsAt < to then
				return true
			end
		end
		return false
	end
	return true
end

-- The week's goals: up to `count` entries of `pool` that pass `eligible(def)`, never two of one
-- family, in a deterministic order for (userId, week). Returns the chosen definitions.
function Weekly.Pick(pool, count: number, userId: number, week: number, eligible: ((any) -> boolean)?)
	local candidates = {}
	for _, def in pool do
		if eligible == nil or eligible(def) then
			table.insert(candidates, def)
		end
	end
	Rng.new(Rng.seed("weekly", userId, week)):Shuffle(candidates)
	local picked, families = {}, {}
	for _, def in candidates do
		if #picked >= count then
			break
		end
		if not families[def.family] then
			families[def.family] = true
			table.insert(picked, def)
		end
	end
	return picked
end

-- How many of the section's goals are finished.
function Weekly.Done(section): number
	local n = 0
	local goals = if type(section) == "table" and type(section.goals) == "table" then section.goals else {}
	for _, entry in goals do
		local def = type(entry) == "table" and Cfg.ById[entry.id]
		if def and (tonumber(entry.progress) or 0) >= (def.target or 1) then
			n += 1
		end
	end
	return n
end

function Weekly.Reached(section, step: number): boolean
	local def = Cfg.Chest[step]
	return def ~= nil and Weekly.Done(section) >= def.goals
end

function Weekly.Claimed(section, step: number): boolean
	local claimed = if type(section) == "table" and type(section.claimed) == "table" then section.claimed else {}
	return claimed[step] == true
end

-- Chest steps reached and not claimed yet, in order.
function Weekly.Unclaimed(section): { number }
	local list = {}
	for step in Cfg.Chest do
		if Weekly.Reached(section, step) and not Weekly.Claimed(section, step) then
			table.insert(list, step)
		end
	end
	return list
end

-- The step's reward list for a player at Ranch Level `level` (a fresh copy).
function Weekly.ChestReward(step: number, level: number): { any }
	local def = Cfg.Chest[step]
	local list = {}
	for i, item in def and def.reward or {} do
		local copy = table.clone(item)
		if def.royal and copy.kind == "egg" and level >= Cfg.RoyalLevel then
			copy.id = "royal"
		end
		list[i] = copy
	end
	return list
end

return Weekly
