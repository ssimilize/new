--[[
	Club records (part of Clubs): pure functions over the DataStore record, so every rule is
	testable without a server. Transforms passed to Services.Clubs.Update call these on a
	fresh copy of the record and may run more than once, so none of them has side effects.

	record = {
	  id, name, tag, color, emblem, open, ownerId, createdAt, disbanded,
	  count,                                   -- members
	  members = { ["u" .. userId] = { name, role, joinedAt, points, war, lastWar } },
	                                           -- points / war: this week; lastWar: last week (3.1)
	  week,                                    -- leaderboard week the fields below belong to
	  scale,                                   -- member count the week's targets use
	  goals = { [goalId] = progress },
	  boss = { name, hp, maxHp, damage = { ["u" .. userId] = n } },
	  warPoints,                               -- Club Wars points this week (3.1)
	  lastWar = { week, points },              -- the week before, for league rewards
	  banner = { design, name, shape, color, color2 } | nil,   -- Workshop banner (3.1)
	}
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Rng = require(Shared.Logic.Rng)

local Cfg = Config.Clubs
local Boards = Config.Leaderboards

local Record = {}

local RANK = { owner = 3, officer = 2, member = 1 }
Record.Rank = RANK

function Record.key(userId: number): string
	return "u" .. tostring(userId)
end

function Record.userIdOf(key: string): number
	return tonumber(string.sub(key, 2)) or 0
end

function Record.week(now: number): number
	return Boards.Week(now)
end

-- The week's goals: the same draw on every server.
function Record.weekGoals(week: number): { string }
	local rng = Rng.new(Rng.seed("clubgoals", week))
	local ids = {}
	for _, g in Cfg.Goals do
		table.insert(ids, g.id)
	end
	rng:Shuffle(ids)
	local picked = {}
	for i = 1, math.min(Cfg.GoalsPerWeek, #ids) do
		picked[i] = ids[i]
	end
	return picked
end

function Record.target(record, goalId: string): number
	local goal = Cfg.GoalById[goalId]
	return if goal then goal.perMember * (record.scale or Cfg.MinScaleMembers) else math.huge
end

local function bossFor(week: number, scale: number)
	local names = Cfg.Boss.names
	local maxHp = Cfg.Boss.hpPerMember * scale
	return { name = names[week % #names + 1], hp = maxHp, maxHp = maxHp, damage = {} }
end

-- Starts a new week on the record when `week` moved on (goals, boss and points reset).
function Record.rollWeek(record, week: number)
	if record.week == week then
		return false
	end
	-- Club Wars: keep what the week that just ended scored (only if it was last week).
	local ended = record.week
	record.lastWar = { week = ended, points = record.warPoints or 0 }
	for _, m in record.members do
		m.lastWar = if ended == week - 1 then (m.war or 0) else 0
		m.war = 0
	end
	record.warPoints = 0
	record.week = week
	record.scale = math.clamp(record.count or 1, Cfg.MinScaleMembers, Cfg.MaxMembers)
	record.goals = {}
	record.boss = bossFor(week, record.scale)
	for _, m in record.members do
		m.points = 0
	end
	return true
end

function Record.new(id: string, spec, owner: { userId: number, name: string }, now: number)
	local record = {
		id = id,
		name = spec.name,
		tag = spec.tag,
		color = spec.color,
		emblem = spec.emblem,
		open = spec.open,
		ownerId = owner.userId,
		createdAt = now,
		disbanded = false,
		count = 1,
		members = {
			[Record.key(owner.userId)] = { name = owner.name, role = "owner", joinedAt = now, points = 0 },
		},
		week = -1,
		scale = Cfg.MinScaleMembers,
		goals = {},
		boss = bossFor(0, Cfg.MinScaleMembers),
	}
	Record.rollWeek(record, Record.week(now))
	return record
end

function Record.member(record, userId: number)
	return record and record.members and record.members[Record.key(userId)]
end

function Record.alive(record): boolean
	return type(record) == "table" and record.disbanded ~= true and (record.count or 0) > 0
end

-- Adds a member. Returns (record?, reason?) — reason: "missing" | "full" | "closed".
function Record.join(record, who: { userId: number, name: string }, now: number, needsOpen: boolean?)
	if not Record.alive(record) then
		return nil, "missing"
	end
	if Record.member(record, who.userId) then
		return record, nil
	end
	if needsOpen and not record.open then
		return nil, "closed"
	end
	if record.count >= Cfg.MaxMembers then
		return nil, "full"
	end
	Record.rollWeek(record, Record.week(now))
	record.members[Record.key(who.userId)] = { name = who.name, role = "member", joinedAt = now, points = 0 }
	record.count += 1
	return record, nil
end

-- The member who takes over when the owner leaves: the longest-serving officer, else the
-- longest-serving member.
local function successor(record)
	local best, bestKey = nil, nil
	for key, m in record.members do
		if
			best == nil
			or RANK[m.role] > RANK[best.role]
			or (RANK[m.role] == RANK[best.role] and (m.joinedAt < best.joinedAt or (m.joinedAt == best.joinedAt and key < bestKey)))
		then
			best, bestKey = m, key
		end
	end
	return best, bestKey
end

-- Removes a member (leaving or kicked). The last member leaving disbands the club.
function Record.remove(record, userId: number)
	local key = Record.key(userId)
	local m = record.members[key]
	if not m then
		return record
	end
	record.members[key] = nil
	record.count = math.max(0, record.count - 1)
	if record.count == 0 then
		record.disbanded = true
		return record
	end
	if m.role == "owner" then
		local heir, heirKey = successor(record)
		heir.role = "owner"
		record.ownerId = Record.userIdOf(heirKey)
	end
	return record
end

-- Can `actor` remove `target`? Officers remove members; the owner removes anyone else.
function Record.canKick(record, actorId: number, targetId: number): boolean
	local actor, target = Record.member(record, actorId), Record.member(record, targetId)
	if not actor or not target or actorId == targetId then
		return false
	end
	return RANK[actor.role] >= RANK.officer and RANK[actor.role] > RANK[target.role]
end

-- Owner only. Giving "owner" hands the club over (the old owner becomes an officer).
function Record.setRole(record, actorId: number, targetId: number, role: string): (boolean, string?)
	local actor, target = Record.member(record, actorId), Record.member(record, targetId)
	if not actor or actor.role ~= "owner" then
		return false, "Only the club owner can change roles"
	end
	if not target or actorId == targetId then
		return false, "Pick another member"
	end
	if role == "owner" then
		actor.role = "officer"
		target.role = "owner"
		record.ownerId = targetId
	else
		target.role = role
	end
	return true, nil
end

-- Adds contributions gathered on one server: { points = { [key] = n }, goals = { [id] = n },
-- damage = { [key] = n } }. Points and damage from players who left are dropped.
function Record.apply(record, delta, now: number)
	Record.rollWeek(record, Record.week(now))
	if delta.week ~= nil and delta.week ~= record.week then
		return record -- gathered last week: the week already reset
	end
	for key, n in delta.points or {} do
		local m = record.members[key]
		if m then
			m.points = (m.points or 0) + n
		end
	end
	local active = {}
	for _, id in Record.weekGoals(record.week) do
		active[id] = true
	end
	for goalId, n in delta.goals or {} do
		if active[goalId] then
			record.goals[goalId] = (record.goals[goalId] or 0) + n
		end
	end
	for key, n in delta.war or {} do
		local m = record.members[key]
		if m then
			m.war = (m.war or 0) + n
			record.warPoints = (record.warPoints or 0) + n
		end
	end
	for key, n in delta.damage or {} do
		if record.members[key] and record.boss.hp > 0 then
			record.boss.damage[key] = (record.boss.damage[key] or 0) + n
			record.boss.hp = math.max(0, record.boss.hp - n)
		end
	end
	return record
end

return Record
