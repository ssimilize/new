--[[
	Clubs (S5, update 1.2): groups of up to 30 players across every server, with weekly
	club goals and a weekly club boss (Config.Clubs). Club records live in their own
	DataStore through ctx.Services.Clubs (Get / atomic Update); the rules are pure functions
	in Record.luau.

	Save section (profile.Clubs):
	  id       = club code | false
	  claimed  = { week, goals = { [goalId] = true }, boss = boolean }
	  attacks  = { day, n }          -- boss attacks today
	  war      = { day, n, claimed } -- war points added today; last war week claimed (3.1)

	Session (session.Clubs): { club = ClubView | false, loading = boolean }
	  ClubView = { id, name, tag, color, emblem, open, ownerId, myRole, count, max, week,
	               weekEndsAt, members = { { userId, name, role, points, here } },
	               goals = { { id, text, progress, target, done, claimed, index } },
	               boss = { name, hp, maxHp, myDamage, attacksLeft, defeated, claimed,
	                        top = { { userId, name, damage } } } }
	Global (global.Clubs): { here = { ["u" .. userId] = { clubId, tag, color, emblem, name, open } } }
	  so nameplates and "join a club on this server" work without extra reads.

	Contributions (goal progress, points, boss damage) collect in memory and are written
	every Config.Clubs.SyncSeconds with one atomic Update per club, then announced over
	Messaging ("Clubs") so other servers re-read that club. What this server has not
	written yet is still shown to its own players (cached record + pending).

	Club Wars (update 3.1, Config.Clubs.War): war points from RaidFinished / RaceFinished /
	BossDamage collect in pending like goal progress (at most War.dailyCap per member per UTC
	day, counted in profile.Clubs.war). After a write, the club's weekly total is indexed on the
	ladder (Services.Clubs.IndexWar); every server reads the top clubs every War.ladderRefresh
	seconds into global.Clubs.ladder. Record.rollWeek keeps last week's score (lastWar) and each
	member's share; Clubs.ClaimWar pays last week's league (or Champion) reward once.
	Banners (3.1): Clubs.SetBanner { design } hangs a Workshop design the officer owns a copy of.

	Actions: Clubs.Create, Join, JoinPlayer, Leave, Kick, SetRole, Settings, ClaimGoal,
	AttackBoss, ClaimBoss, Refresh, ClaimWar, SetBanner.
	Public API: Clubs:ClubOf(player) -> clubId?, Clubs:Flush() (tests / shutdown),
	Clubs:RefreshLadder().
	Publishes ClubWarClaimed (player, { league, week }).
]]

local Record = require(script.Record)

local Clubs = {
	Name = "Clubs",
	Dependencies = { "Currency", "Progression", "Rewards" },
	OptionalDependencies = { "Expeditions", "Workshop" },
}

Clubs.Profile = {
	Version = 1,
	Default = function()
		return {
			id = false,
			claimed = { week = 0, goals = {}, boss = false },
			attacks = { day = 0, n = 0 },
			war = { day = 0, n = 0, claimed = -1 },
		}
	end,
}

local ctx
local Config, Cfg
local Currency, Progression, Rewards

local cache = {} -- [clubId] = last record read or written
local pending = {} -- [clubId] = { week, points = {}, goals = {}, damage = {} }
local here = {} -- [clubId] = { [player] = true }
local syncing = {} -- [clubId] = true while an Update is in flight
local champions = {} -- [week] = { clubId } (the week's top clubs, read once it is over)
local ladderBusy = false

local MESSAGE_TOPIC = "Clubs"

-- Helpers -------------------------------------------------------------------------------

local function displayName(player): string
	return player.DisplayName or player.Name
end

local function now(): number
	return ctx:Now()
end

local function section(player)
	return ctx:Section(player)
end

local function clubIdOf(player): string?
	local s = section(player)
	return if s and s.id then s.id else nil
end

local function service()
	local svc = ctx.Services.Clubs
	if not svc then
		ctx:Fail("Clubs aren't available right now")
	end
	return svc
end

local function pendingFor(clubId: string)
	local week = Record.week(now())
	local p = pending[clubId]
	if not p or p.week ~= week then
		p = { week = week, points = {}, goals = {}, damage = {}, war = {} }
		pending[clubId] = p
	end
	return p
end

-- The record as this server's players should see it: cached record + unsent contributions.
local function merged(clubId: string)
	local record = cache[clubId]
	if not record then
		return nil
	end
	local copy = table.clone(record)
	copy.members = {}
	for k, m in record.members do
		copy.members[k] = table.clone(m)
	end
	copy.goals = table.clone(record.goals or {})
	copy.boss = table.clone(record.boss)
	copy.boss.damage = table.clone(record.boss.damage or {})
	local p = pending[clubId]
	if p then
		Record.apply(copy, p, now())
	else
		Record.rollWeek(copy, Record.week(now()))
	end
	return copy
end

-- Session view ---------------------------------------------------------------------------

local function view(player, clubId: string)
	local record = merged(clubId)
	if not record or not Record.alive(record) then
		return false
	end
	local me = Record.member(record, player.UserId)
	if not me then
		return false
	end
	local s = section(player)
	local week = record.week
	local claimed = if s and s.claimed.week == week then s.claimed else { goals = {}, boss = false }

	local members = {}
	for key, m in record.members do
		local userId = Record.userIdOf(key)
		table.insert(members, {
			userId = userId,
			name = m.name,
			role = m.role,
			points = m.points or 0,
			here = ctx:PlayerByUserId(userId) ~= nil,
		})
	end
	table.sort(members, function(a, b)
		if Record.Rank[a.role] ~= Record.Rank[b.role] then
			return Record.Rank[a.role] > Record.Rank[b.role]
		end
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.userId < b.userId
	end)

	local goals = {}
	for i, goalId in Record.weekGoals(week) do
		local def = Cfg.GoalById[goalId]
		local target = Record.target(record, goalId)
		local progress = math.min(record.goals[goalId] or 0, target)
		table.insert(goals, {
			id = goalId,
			index = i,
			text = string.format(def.text, tostring(target)),
			progress = math.floor(progress),
			target = target,
			done = progress >= target,
			claimed = claimed.goals[goalId] == true,
		})
	end

	local damage = {}
	for key, n in record.boss.damage do
		local m = record.members[key]
		if m then
			table.insert(damage, { userId = Record.userIdOf(key), name = m.name, damage = n })
		end
	end
	table.sort(damage, function(a, b)
		return a.damage > b.damage
	end)
	local top = {}
	for i = 1, math.min(5, #damage) do
		top[i] = damage[i]
	end
	local attacks = if s and s.attacks.day == ctx:Day() then s.attacks.n else 0

	-- Club Wars (3.1)
	local War = Cfg.War
	local warPoints = record.warPoints or 0
	local league = Cfg.League(warPoints)
	local nextLeague = nil
	for _, l in War.leagues do
		if l.min > warPoints and (nextLeague == nil or l.min < nextLeague.min) then
			nextLeague = l
		end
	end
	local last = record.lastWar
	local lastWeekClaim = nil
	if last and last.week == week - 1 and (me.lastWar or 0) > 0 then
		lastWeekClaim = {
			week = last.week,
			points = last.points,
			league = Cfg.League(last.points).id,
			champion = table.find(champions[last.week] or {}, record.id) ~= nil,
			claimed = s ~= nil and s.war.claimed == last.week,
		}
	end
	local today = if s and s.war.day == ctx:Day() then s.war.n else 0

	return {
		id = record.id,
		name = record.name,
		tag = record.tag,
		color = record.color,
		emblem = record.emblem,
		open = record.open,
		ownerId = record.ownerId,
		myRole = me.role,
		count = record.count,
		max = Cfg.MaxMembers,
		week = week,
		weekEndsAt = Config.Leaderboards.WeekEndsAt(week),
		members = members,
		goals = goals,
		boss = {
			name = record.boss.name,
			hp = record.boss.hp,
			maxHp = record.boss.maxHp,
			myDamage = record.boss.damage[Record.key(player.UserId)] or 0,
			attacksLeft = math.max(0, Cfg.Boss.attacksPerDay - attacks),
			defeated = record.boss.hp <= 0,
			claimed = claimed.boss == true,
			top = top,
		},
		war = {
			open = now() >= War.startsAt,
			startsAt = War.startsAt,
			points = warPoints,
			mine = me.war or 0,
			league = league.id,
			next = if nextLeague then { id = nextLeague.id, min = nextLeague.min } else false,
			todayLeft = math.max(0, War.dailyCap - today),
			last = lastWeekClaim or false,
		},
		banner = record.banner or false,
	}
end

local function publishHere()
	local g = ctx:Global()
	local list = {}
	for clubId, players in here do
		local record = cache[clubId]
		if record and Record.alive(record) then
			for player in players do
				list[Record.key(player.UserId)] = {
					clubId = clubId,
					tag = record.tag,
					color = record.color,
					emblem = record.emblem,
					name = record.name,
					open = record.open == true,
					banner = if record.banner then { color = record.banner.color, color2 = record.banner.color2 } else false,
				}
			end
		end
	end
	g.here = list
	ctx:DirtyGlobal("here")
end

local function refreshPlayer(player)
	local sess = ctx:Session(player)
	if not sess then
		return
	end
	local clubId = clubIdOf(player)
	sess.club = if clubId and cache[clubId] then view(player, clubId) else false
	ctx:DirtySession(player)
end

local function refreshClub(clubId: string)
	for player in here[clubId] or {} do
		refreshPlayer(player)
	end
	publishHere()
end

-- Membership bookkeeping ------------------------------------------------------------------

local function track(player, clubId: string?)
	for id, players in here do
		players[player] = nil
		if next(players) == nil then
			here[id] = nil
		end
	end
	if clubId then
		here[clubId] = here[clubId] or {}
		here[clubId][player] = true
	end
end

local function setClub(player, clubId: string?)
	local s = section(player)
	if not s then
		return
	end
	s.id = clubId or false
	ctx:Dirty(player, "id")
	track(player, clubId)
	refreshPlayer(player)
	publishHere()
end

-- Drops players whose club no longer lists them (kicked or disbanded on another server).
local function checkMembers(clubId: string)
	local record = cache[clubId]
	for player in table.clone(here[clubId] or {}) do
		if not Record.alive(record) or not Record.member(record, player.UserId) then
			setClub(player, nil)
			ctx:Notify(player, "You're no longer in that club", "info")
		end
	end
end

local function store(clubId: string, record)
	cache[clubId] = record
	checkMembers(clubId)
	refreshClub(clubId)
end

local function announce(clubId: string)
	ctx.Services.Messaging.Publish(MESSAGE_TOPIC, { id = clubId, job = ctx.Services.JobId })
end

-- Runs an atomic update. `transform(record)` returns the new record or nil (no change);
-- it may set `why` through the returned second value. Returns the stored record or fails.
local function update(clubId: string, transform)
	local svc = service()
	local reason = nil
	local ok, result = svc.Update(clubId, function(record)
		reason = nil
		local out, why = transform(record)
		reason = why
		return out
	end)
	if not ok then
		ctx:Fail("Clubs are busy right now. Try again in a moment")
	end
	if result == nil then
		return nil, reason
	end
	store(clubId, result)
	announce(clubId)
	return result, nil
end

local function read(clubId: string)
	local svc = ctx.Services.Clubs
	if not svc then
		return false
	end
	local ok, record = svc.Get(clubId)
	if ok then
		if record then
			store(clubId, record)
		else
			cache[clubId] = nil
			checkMembers(clubId)
		end
	end
	return ok
end

-- Sync --------------------------------------------------------------------------------------

local function isEmpty(p): boolean
	return next(p.points) == nil and next(p.goals) == nil and next(p.damage) == nil and next(p.war or {}) == nil
end

local function subtract(live, sent)
	for _, field in { "points", "goals", "damage", "war" } do
		live[field] = live[field] or {}
		for k, n in sent[field] or {} do
			local left = (live[field][k] or 0) - n
			live[field][k] = if left > 0 then left else nil
		end
	end
end

-- Writes one club's pending contributions (if any) and re-reads it otherwise.
local function syncClub(clubId: string)
	if syncing[clubId] or not ctx.Services.Clubs then
		return
	end
	syncing[clubId] = true
	local p = pending[clubId]
	if p and not isEmpty(p) then
		local sent = {
			week = p.week,
			points = table.clone(p.points),
			goals = table.clone(p.goals),
			damage = table.clone(p.damage),
			war = table.clone(p.war or {}),
		}
		local ok, result = ctx.Services.Clubs.Update(clubId, function(record)
			if not Record.alive(record) then
				return nil
			end
			return Record.apply(record, sent, now())
		end)
		if ok then
			subtract(p, sent)
			if result then
				if next(sent.war) ~= nil and ctx.Services.Clubs.IndexWar then
					ctx.Services.Clubs.IndexWar(result.week, clubId, result.warPoints or 0)
				end
				store(clubId, result)
				announce(clubId)
			else
				cache[clubId] = nil
				checkMembers(clubId)
			end
		end
	else
		read(clubId)
	end
	syncing[clubId] = nil
end

function Clubs:Flush()
	for clubId in table.clone(here) do
		syncClub(clubId)
	end
	for clubId, p in table.clone(pending) do
		if not here[clubId] and not isEmpty(p) then
			syncClub(clubId)
		end
	end
end

function Clubs:ClubOf(player): string?
	return clubIdOf(player)
end

-- Contributions -------------------------------------------------------------------------------

local function matches(filter, detail): boolean
	for key, want in filter or {} do
		if detail[key] ~= want then
			return false
		end
	end
	return true
end

local function contribute(player, goalId: string, amount: number)
	local clubId = clubIdOf(player)
	if not clubId or amount <= 0 or not cache[clubId] then
		return
	end
	local active = false
	for _, id in Record.weekGoals(Record.week(now())) do
		if id == goalId then
			active = true
		end
	end
	if not active then
		return
	end
	local p = pendingFor(clubId)
	p.goals[goalId] = (p.goals[goalId] or 0) + amount
	local key = Record.key(player.UserId)
	p.points[key] = (p.points[key] or 0) + amount
	refreshPlayer(player)
end

-- Club Wars: adds war points for the player's club, within the member's daily cap.
local function addWar(player, amount: number)
	local clubId = clubIdOf(player)
	local s = section(player)
	if not clubId or not s or amount <= 0 or not cache[clubId] or now() < Cfg.War.startsAt then
		return
	end
	local today = ctx:Day()
	if s.war.day ~= today then
		s.war.day, s.war.n = today, 0
	end
	local add = math.min(math.floor(amount), Cfg.War.dailyCap - s.war.n)
	if add <= 0 then
		return
	end
	s.war.n += add
	ctx:Dirty(player, "war")
	local p = pendingFor(clubId)
	local key = Record.key(player.UserId)
	p.war[key] = (p.war[key] or 0) + add
	refreshPlayer(player)
end

local championsOf

-- The ladder: this week's top clubs across servers, with their names (cached records or reads).
function Clubs:RefreshLadder()
	local svc = ctx.Services.Clubs
	if ladderBusy or not svc or not svc.TopWar then
		return
	end
	ladderBusy = true
	local week = Record.week(now())
	local ok, top = svc.TopWar(week, Cfg.War.ladderSize)
	if ok then
		local rows = {}
		for i, entry in top do
			local record = cache[entry.id]
			if not record then
				local got, fresh = svc.Get(entry.id)
				record = if got then fresh else nil
			end
			if Record.alive(record) then
				table.insert(rows, {
					rank = i,
					clubId = entry.id,
					name = record.name,
					tag = record.tag,
					color = record.color,
					emblem = record.emblem,
					points = entry.points,
				})
			end
		end
		local g = ctx:Global()
		g.ladder = { week = week, rows = rows, at = now() }
		ctx:DirtyGlobal("ladder")
		-- Last week's champions, so club views can show the Champion result.
		if not champions[week - 1] then
			pcall(championsOf, week - 1)
		end
	end
	ladderBusy = false
end

-- The finished week's champions (read once per week and kept).
function championsOf(week: number): { string }
	if champions[week] then
		return champions[week]
	end
	local svc = ctx.Services.Clubs
	local ok, top = false, {}
	if svc and svc.TopWar then
		ok, top = svc.TopWar(week, Cfg.War.champion.top)
	end
	if not ok then
		ctx:Fail("Clubs are busy right now. Try again in a moment")
	end
	local ids = {}
	for _, entry in top do
		if entry.points > 0 then
			table.insert(ids, entry.id)
		end
	end
	champions[week] = ids
	return ids
end

-- Actions -------------------------------------------------------------------------------------

local function cleanName(player, text: string, min: number, max: number, what: string): string
	local trimmed = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	trimmed = string.gsub(trimmed, "%s+", " ")
	local length = utf8.len(trimmed) or #trimmed
	if length < min or length > max then
		ctx:Fail(string.format("%s must be %d to %d characters", what, min, max))
	end
	local filtered = ctx.Services.Text.Filter(trimmed, player.UserId)
	if filtered == nil then
		ctx:Fail("Couldn't check that name. Try again")
	end
	if filtered ~= trimmed then
		ctx:Fail("That " .. string.lower(what) .. " isn't allowed")
	end
	return trimmed
end

local function newCode(): string
	local alphabet = Cfg.CodeAlphabet
	local chars = {}
	for i = 1, Cfg.CodeLength do
		local n = ctx.Rng:Int(1, #alphabet)
		chars[i] = string.sub(alphabet, n, n)
	end
	return table.concat(chars)
end

local function requireClub(player)
	local clubId = clubIdOf(player)
	if not clubId then
		ctx:Fail("You're not in a club")
	end
	return clubId :: string
end

local function requireNoClub(player)
	if clubIdOf(player) then
		ctx:Fail("Leave your club first")
	end
	Progression:Require(player, Cfg.Unlock)
end

local function joinReason(reason: string?)
	if reason == "missing" then
		ctx:Fail("No club has that code")
	elseif reason == "full" then
		ctx:Fail(string.format("That club is full (%d members)", Cfg.MaxMembers))
	elseif reason == "closed" then
		ctx:Fail("That club is invite only. Ask for its code")
	end
	ctx:Fail("Couldn't join that club")
end

local function join(player, clubId: string, needsOpen: boolean)
	local who = { userId = player.UserId, name = displayName(player) }
	local record, reason = update(clubId, function(record)
		return Record.join(record, who, now(), needsOpen)
	end)
	if not record then
		joinReason(reason)
	end
	setClub(player, clubId)
	ctx.Bus:Publish("ClubJoined", player, { club = clubId })
	return { id = clubId, name = record.name }
end

local function registerActions()
	ctx.Net:Handle("Clubs.Create", function(player, payload)
		requireNoClub(player)
		local name = cleanName(player, payload.name, Cfg.NameLength[1], Cfg.NameLength[2], "Name")
		local tag = string.upper(payload.tag)
		if not string.match(tag, "^[%w]+$") or #tag < Cfg.TagLength[1] or #tag > Cfg.TagLength[2] then
			ctx:Fail(string.format("The tag must be %d to %d letters or numbers", Cfg.TagLength[1], Cfg.TagLength[2]))
		end
		tag = cleanName(player, tag, Cfg.TagLength[1], Cfg.TagLength[2], "Tag")
		if not Cfg.EmblemById[payload.emblem] then
			ctx:Fail("Pick an emblem")
		end
		local cost = Currency:NormalizeCost(Cfg.CreateCost)
		Currency:Charge(player, cost, "club_create")
		local spec = { name = name, tag = tag, color = payload.color, emblem = payload.emblem, open = payload.open }
		local owner = { userId = player.UserId, name = displayName(player) }
		local ok, created = pcall(function()
			for _ = 1, 6 do
				local code = newCode()
				local record = update(code, function(existing)
					if existing ~= nil then
						return nil, "taken"
					end
					return Record.new(code, spec, owner, now())
				end)
				if record then
					return record
				end
			end
			return nil
		end)
		if not ok or not created then
			-- Refund: the club was never created.
			for key, amount in cost do
				Currency:Add(player, key, amount, "club_create_refund")
			end
			if not ok then
				error(created, 0)
			end
			ctx:Fail("Couldn't create the club. Try again")
		end
		setClub(player, created.id)
		ctx.Bus:Publish("ClubJoined", player, { club = created.id })
		ctx:RequestSave(player)
		return { id = created.id }
	end)

	ctx.Net:Handle("Clubs.Join", function(player, payload)
		requireNoClub(player)
		local code = string.upper(payload.code)
		if #code ~= Cfg.CodeLength or not string.match(code, "^[%w]+$") then
			ctx:Fail("Club codes are " .. Cfg.CodeLength .. " letters and numbers")
		end
		return join(player, code, false)
	end)

	ctx.Net:Handle("Clubs.JoinPlayer", function(player, payload)
		requireNoClub(player)
		local other = ctx:PlayerByUserId(payload.userId)
		local clubId = other and clubIdOf(other)
		if not clubId then
			ctx:Fail("That rancher isn't in a club")
		end
		return join(player, clubId :: string, true)
	end)

	ctx.Net:Handle("Clubs.Leave", function(player)
		local clubId = requireClub(player)
		update(clubId, function(record)
			if not Record.alive(record) or not Record.member(record, player.UserId) then
				return nil
			end
			return Record.remove(record, player.UserId)
		end)
		setClub(player, nil)
		return nil
	end)

	ctx.Net:Handle("Clubs.Kick", function(player, payload)
		local clubId = requireClub(player)
		local _, why = update(clubId, function(record)
			if not Record.alive(record) then
				return nil, "missing"
			end
			if not Record.canKick(record, player.UserId, payload.userId) then
				return nil, "denied"
			end
			return Record.remove(record, payload.userId)
		end)
		if why then
			ctx:Fail("You can't remove that member")
		end
		local target = ctx:PlayerByUserId(payload.userId)
		if target and clubIdOf(target) == clubId then
			setClub(target, nil)
			ctx:Notify(target, "You were removed from the club", "info")
		end
		return nil
	end)

	ctx.Net:Handle("Clubs.SetRole", function(player, payload)
		local clubId = requireClub(player)
		local _, why = update(clubId, function(record)
			if not Record.alive(record) then
				return nil, "Club not found"
			end
			local ok, reason = Record.setRole(record, player.UserId, payload.userId, payload.role)
			if not ok then
				return nil, reason
			end
			return record
		end)
		if why then
			ctx:Fail(why)
		end
		return nil
	end)

	ctx.Net:Handle("Clubs.Settings", function(player, payload)
		local clubId = requireClub(player)
		if payload.emblem ~= nil and not Cfg.EmblemById[payload.emblem] then
			ctx:Fail("Pick an emblem")
		end
		local _, why = update(clubId, function(record)
			local me = Record.alive(record) and Record.member(record, player.UserId)
			if not me or Record.Rank[me.role] < Record.Rank.officer then
				return nil, "denied"
			end
			if payload.open ~= nil then
				record.open = payload.open
			end
			if payload.color ~= nil then
				record.color = payload.color
			end
			if payload.emblem ~= nil then
				record.emblem = payload.emblem
			end
			return record
		end)
		if why then
			ctx:Fail("Only the owner and officers can change club settings")
		end
		return nil
	end)

	ctx.Net:Handle("Clubs.ClaimGoal", function(player, payload)
		local clubId = requireClub(player)
		local v = view(player, clubId)
		if not v then
			ctx:Fail("You're not in a club")
		end
		local goal = nil
		for _, g in v.goals do
			if g.id == payload.goal then
				goal = g
			end
		end
		if not goal then
			ctx:Fail("That isn't one of this week's goals")
		end
		if goal.claimed then
			ctx:Fail("You already claimed that")
		end
		if not goal.done then
			ctx:Fail("Your club hasn't finished that goal yet")
		end
		local s = section(player)
		if s.claimed.week ~= v.week then
			s.claimed = { week = v.week, goals = {}, boss = false }
		end
		s.claimed.goals[goal.id] = true
		ctx:Dirty(player, "claimed")
		local rewards = Rewards:Grant(player, Cfg.GoalRewards[goal.index] or {}, "club_goal")
		refreshPlayer(player)
		return { rewards = rewards }
	end)

	ctx.Net:Handle("Clubs.AttackBoss", function(player)
		local clubId = requireClub(player)
		local v = view(player, clubId)
		if not v then
			ctx:Fail("You're not in a club")
		end
		if v.boss.defeated then
			ctx:Fail(v.boss.name .. " is already down this week")
		end
		if v.boss.attacksLeft <= 0 then
			ctx:Fail("No attacks left today. Come back tomorrow")
		end
		local s = section(player)
		local today = ctx:Day()
		if s.attacks.day ~= today then
			s.attacks = { day = today, n = 0 }
		end
		s.attacks.n += 1
		ctx:Dirty(player, "attacks")
		local Expeditions = ctx:GetSystem("Expeditions")
		local power = if Expeditions then Expeditions:SquadPower(player) else 0
		local damage = math.max(Cfg.Boss.minDamage, math.floor(Cfg.Boss.damagePerRootPower * math.sqrt(math.max(0, power))))
		damage = math.min(damage, v.boss.hp)
		local p = pendingFor(clubId)
		local key = Record.key(player.UserId)
		p.damage[key] = (p.damage[key] or 0) + damage
		p.points[key] = (p.points[key] or 0) + 1
		refreshPlayer(player)
		if damage >= v.boss.hp then
			-- The last hit: write it now so every server sees the boss fall.
			ctx.Services.Spawn(syncClub, clubId)
		end
		return { damage = damage, hp = math.max(0, v.boss.hp - damage) }
	end)

	ctx.Net:Handle("Clubs.ClaimBoss", function(player)
		local clubId = requireClub(player)
		local v = view(player, clubId)
		if not v then
			ctx:Fail("You're not in a club")
		end
		if not v.boss.defeated then
			ctx:Fail("Defeat the club boss first")
		end
		if v.boss.claimed then
			ctx:Fail("You already claimed that")
		end
		if v.boss.myDamage <= 0 then
			ctx:Fail("Attack the boss at least once to share the reward")
		end
		local s = section(player)
		if s.claimed.week ~= v.week then
			s.claimed = { week = v.week, goals = {}, boss = false }
		end
		s.claimed.boss = true
		ctx:Dirty(player, "claimed")
		local rewards = Rewards:Grant(player, Cfg.Boss.reward, "club_boss")
		refreshPlayer(player)
		return { rewards = rewards }
	end)

	ctx.Net:Handle("Clubs.ClaimWar", function(player)
		local clubId = requireClub(player)
		local record = merged(clubId)
		local me = record and Record.member(record, player.UserId)
		if not me then
			ctx:Fail("You're not in a club")
		end
		local last = record.lastWar
		if not last or last.week ~= record.week - 1 then
			ctx:Fail("Your club has no Club Wars result from last week")
		end
		if (me.lastWar or 0) <= 0 then
			ctx:Fail("Earn war points for your club to share its reward")
		end
		local s = section(player)
		if s.war.claimed == last.week then
			ctx:Fail("You already claimed that")
		end
		local champion = table.find(championsOf(last.week), clubId) ~= nil
		local league = if champion then Cfg.War.champion else Cfg.League(last.points)
		s.war.claimed = last.week
		ctx:Dirty(player, "war")
		local rewards = Rewards:Grant(player, league.reward, "club_war")
		ctx.Bus:Publish("ClubWarClaimed", player, { league = if champion then "champion" else league.id, week = last.week })
		ctx:RequestSave(player)
		refreshPlayer(player)
		return { league = if champion then "champion" else league.id, rewards = rewards }
	end)

	ctx.Net:Handle("Clubs.SetBanner", function(player, payload)
		local clubId = requireClub(player)
		local banner = false
		if payload.design ~= "" then
			local Workshop = ctx:GetSystem("Workshop")
			local copy = if Workshop then Workshop:Copy(player, payload.design) else nil
			if not copy then
				ctx:Fail("Own a copy of that design to use it as a banner")
			end
			banner = {
				design = payload.design,
				name = copy.name,
				shape = copy.shape,
				color = copy.color,
				color2 = copy.color2,
			}
		end
		local _, why = update(clubId, function(record)
			local me = Record.alive(record) and Record.member(record, player.UserId)
			if not me or Record.Rank[me.role] < Record.Rank.officer then
				return nil, "denied"
			end
			record.banner = if banner then banner else nil
			return record
		end)
		if why then
			ctx:Fail("Only the owner and officers can change the banner")
		end
		return { banner = banner }
	end)

	ctx.Net:Handle("Clubs.Refresh", function(player)
		local clubId = requireClub(player)
		syncClub(clubId)
		return nil
	end)
end

-- Lifecycle -----------------------------------------------------------------------------------

function Clubs.Init(context)
	ctx = context
	Config = ctx.Config
	Cfg = Config.Clubs
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(cache)
	table.clear(pending)
	table.clear(here)
	table.clear(syncing)
	table.clear(champions)
	ladderBusy = false

	ctx:Global().here = {}
	ctx:Global().ladder = { week = Record.week(now()), rows = {}, at = 0 }
	registerActions()

	-- Club Wars (3.1)
	for _, source in Cfg.War.sources do
		ctx.Bus:Subscribe(source.topic, function(player, detail)
			detail = detail or {}
			if player == nil or not matches(source.filter, detail) then
				return
			end
			local amount = source.points or ((tonumber(detail[source.field]) or 0) * (source.mult or 1))
			if source.bonusRank and (tonumber(detail.rank) or math.huge) <= source.bonusRank then
				amount += source.bonus or 0
			end
			addWar(player, amount)
		end)
	end

	for _, goal in Cfg.Goals do
		ctx.Bus:Subscribe(goal.topic, function(player, detail)
			if player == nil or not matches(goal.filter, detail or {}) then
				return
			end
			local amount = 1
			if goal.amount then
				amount = (tonumber(detail and detail[goal.amount]) or 0) / (goal.per or 1)
			end
			contribute(player, goal.id, amount)
		end)
	end
end

function Clubs.Start()
	ctx:Every(Cfg.SyncSeconds, function()
		ctx.Services.Spawn(function()
			Clubs:Flush()
		end)
	end)
	ctx:Every(Cfg.War.ladderRefresh, function()
		if now() >= Cfg.War.startsAt then
			ctx.Services.Spawn(function()
				Clubs:RefreshLadder()
			end)
		end
	end)
	ctx.Services.Messaging.Subscribe(MESSAGE_TOPIC, function(data)
		if type(data) == "table" and type(data.id) == "string" and data.job ~= ctx.Services.JobId and here[data.id] then
			ctx.Services.Spawn(read, data.id)
		end
	end)
end

function Clubs.PlayerAdded(player)
	local clubId = clubIdOf(player)
	if not clubId then
		refreshPlayer(player)
		return
	end
	track(player, clubId)
	ctx.Services.Spawn(function()
		-- Always re-read: the player may have been removed while they were away.
		if not read(clubId) and cache[clubId] then
			checkMembers(clubId)
		end
		refreshPlayer(player)
		publishHere()
	end)
end

function Clubs.PlayerRemoving(player)
	local clubId = clubIdOf(player)
	track(player, nil)
	publishHere()
	if clubId and pending[clubId] and not isEmpty(pending[clubId]) then
		ctx.Services.Spawn(syncClub, clubId)
	end
end

return Clubs
