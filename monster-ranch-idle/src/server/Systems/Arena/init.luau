--[[
	Arena (update 2.1): asynchronous PvP with normalized stats. Rules: Config/Arena and
	Logic/Arena.

	Cross-server data (ctx.Services.Arena): one record per player
	  { userId, name, rating, team = { Fighter }, wins, losses, updatedAt }
	updated atomically; ratings are indexed for matchmaking (Services.Arena.Index / Near).

	Save section (profile.Arena):
	  defense  = { monsterId }       -- the monsters behind the defense snapshot (for the UI)
	  attempts = { day, n }          -- attacks used this UTC day
	  week, bestTier                 -- this arena week and the best tier reached in it
	  lastTier, claimed              -- the last finished week's tier, and whether it was claimed
	Session (session.Arena): { rating, tier, candidates = { Candidate }, attemptsLeft }
	  Candidate = { name, rating, bot, team = { { line, form, look } } }

	Actions:
	  Arena.SetDefense { ids }        -- TeamSize Adults; snapshot saved for other players
	  Arena.Refresh                   -- new candidates near your rating (bots fill in)
	  Arena.Attack { candidate, ids } -- fights a candidate; Elo for you (and a real defender)
	  Arena.ClaimWeekly               -- the finished week's tier reward, once
	Publishes ArenaBattle (player, { won, rating }).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Arena)

local Arena = {
	Name = "Arena",
	Dependencies = { "Progression", "Monsters", "Rewards" },
}

Arena.Profile = {
	Version = 1,
	Default = function()
		return {
			defense = {},
			attempts = { day = 0, n = 0 },
			week = 0,
			bestTier = "",
			lastTier = "",
			claimed = false,
		}
	end,
}

local ctx
local Config -- Config.Arena
local Progression, Monsters, Rewards

local ratings = {} -- [player] = number (mirror of the Services.Arena record)
local candidates = {} -- [player] = { Candidate + userId }

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function service()
	local s = ctx.Services.Arena
	if not s then
		ctx:Fail("The arena is closed right now")
	end
	return s
end

local function week(): number
	return ctx.Config.Leaderboards.Week(ctx:Now())
end

local function attemptsLeft(s): number
	if s.attempts.day ~= ctx:Day() then
		return Config.AttemptsPerDay
	end
	return math.max(0, Config.AttemptsPerDay - s.attempts.n)
end

-- Rolls the arena week over and records the best tier reached this week.
local function syncWeek(player, s)
	local current = week()
	if s.week ~= current then
		-- Any week number (even 0) is real; an empty bestTier means nothing was earned.
		if s.bestTier ~= "" then
			s.lastTier = s.bestTier
			s.claimed = false
		end
		s.week = current
		s.bestTier = ""
		ctx:Dirty(player)
	end
	local rating = ratings[player]
	if rating then
		local tier = Logic.Tier(rating).id
		local order = {}
		for i, t in Config.Tiers do
			order[t.id] = i
		end
		if s.bestTier == "" or (order[tier] or 0) > (order[s.bestTier] or 0) then
			s.bestTier = tier
			ctx:Dirty(player, "bestTier")
		end
	end
end

local function publish(player)
	local sess = ctx:Session(player)
	local s = ctx:Section(player)
	if not sess or not s then
		return
	end
	local rating = ratings[player] or Config.StartRating
	sess.rating = rating
	sess.tier = Logic.Tier(rating).id
	sess.attemptsLeft = attemptsLeft(s)
	local list = {}
	for _, c in candidates[player] or {} do
		table.insert(list, { name = c.name, rating = c.rating, bot = c.bot == true, team = c.team, done = c.done == true })
	end
	sess.candidates = list
	ctx:DirtySession(player)
end

local function teamOf(player, ids: { string })
	local seen, team = {}, {}
	for _, id in ids do
		local m = Monsters:Get(player, id)
		if not m then
			ctx:Fail("That monster doesn't exist")
		end
		if m.stage < 3 then
			ctx:Fail("Only Adults can fight in the arena")
		end
		if seen[id] then
			ctx:Fail("Pick three different monsters")
		end
		seen[id] = true
		table.insert(team, Logic.Snapshot(m))
	end
	if #team ~= Config.TeamSize then
		ctx:Fail(string.format("Pick %d Adults", Config.TeamSize))
	end
	return team
end

local function newRecord(player)
	return {
		userId = player.UserId,
		name = player.DisplayName or player.Name,
		rating = Config.StartRating,
		wins = 0,
		losses = 0,
		updatedAt = ctx:Now(),
	}
end

-- Actions ------------------------------------------------------------------------------

local function setDefense(player, ids)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local team = teamOf(player, ids)
	local ok, record = service().Update(player.UserId, function(current)
		local r = current or newRecord(player)
		r.name = player.DisplayName or player.Name
		r.team = team
		r.updatedAt = ctx:Now()
		return r
	end)
	if not ok or not record then
		ctx:Fail("The arena is busy. Try again in a moment.")
	end
	ratings[player] = record.rating
	service().Index(player.UserId, record.rating)
	s.defense = table.clone(ids)
	ctx:Dirty(player, "defense")
	syncWeek(player, s)
	publish(player)
	return { rating = record.rating }
end

local function refresh(player)
	mustSection(player)
	Progression:Require(player, Config.Unlock)
	local rating = ratings[player] or Config.StartRating
	local list = {}
	local ok, near = service().Near(rating, Config.RatingWindow, 20)
	if ok then
		local pool = {}
		for _, entry in near do
			if entry.userId ~= player.UserId then
				table.insert(pool, entry)
			end
		end
		ctx.Rng:Shuffle(pool)
		for _, entry in pool do
			if #list >= Config.Candidates then
				break
			end
			local got, record = service().Get(entry.userId)
			if got and record and type(record.team) == "table" and #record.team == Config.TeamSize then
				table.insert(list, {
					userId = entry.userId,
					name = record.name or "Rancher",
					rating = record.rating or Config.StartRating,
					team = record.team,
				})
			end
		end
	end
	while #list < Config.Candidates do
		table.insert(list, Logic.Bot(rating, ctx.Rng:Int(1, 2 ^ 30)))
	end
	candidates[player] = list
	publish(player)
	return { candidates = #list }
end

local function attack(player, index: number, ids)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local list = candidates[player]
	local target = list and list[index]
	if not target or target.done then
		ctx:Fail("Pick an opponent from the list")
	end
	if attemptsLeft(s) <= 0 then
		ctx:Fail("No arena battles left today. Come back tomorrow!")
	end
	local team = teamOf(player, ids)
	local seed = ctx.Rng:Int(1, 2 ^ 30)
	local replay = Logic.Fight(team, target.team, seed)
	local won = replay.win == true

	local mine = ratings[player] or Config.StartRating
	local delta = Logic.Delta(mine, target.rating, won)
	local ok, record = service().Update(player.UserId, function(current)
		local r = current or newRecord(player)
		r.rating = math.max(Config.MinRating, (r.rating or Config.StartRating) + delta)
		r.wins = (r.wins or 0) + (if won then 1 else 0)
		r.losses = (r.losses or 0) + (if won then 0 else 1)
		r.updatedAt = ctx:Now()
		return r
	end)
	if not ok or not record then
		ctx:Fail("The arena is busy. Try again in a moment.")
	end
	ratings[player] = record.rating
	service().Index(player.UserId, record.rating)
	if target.userId then
		-- The defender's rating moves the other way (read fresh: they may have fought since).
		local okDef, def = service().Update(target.userId, function(current)
			if not current then
				return nil
			end
			current.rating = math.max(Config.MinRating, current.rating + Logic.Delta(current.rating, mine, not won))
			return current
		end)
		if okDef and def then
			service().Index(target.userId, def.rating)
		end
	end

	if s.attempts.day ~= ctx:Day() then
		s.attempts = { day = ctx:Day(), n = 0 }
	end
	s.attempts.n += 1
	ctx:Dirty(player, "attempts")
	target.done = true
	syncWeek(player, s)
	local rewards = {}
	if won then
		rewards = Rewards:Grant(player, Config.WinReward, "arena_win")
	end
	ctx.Bus:Publish("ArenaBattle", player, { won = won, rating = record.rating, squad = table.clone(ids) })
	publish(player)
	return { replay = replay, win = won, delta = delta, rating = record.rating, tier = Logic.Tier(record.rating).id, rewards = rewards }
end

local function claimWeekly(player)
	local s = mustSection(player)
	syncWeek(player, s)
	if s.lastTier == "" then
		ctx:Fail("Finish an arena week to earn a reward")
	end
	if s.claimed then
		ctx:Fail("You already claimed this week's arena reward")
	end
	local items = Config.WeeklyRewards[s.lastTier] or {}
	local granted = Rewards:Grant(player, items, "arena_weekly")
	s.claimed = true
	ctx:Dirty(player, "claimed")
	return { tier = s.lastTier, rewards = granted }
end

-- Lifecycle ----------------------------------------------------------------------------

function Arena.Init(context)
	ctx = context
	Config = ctx.Config.Arena
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(ratings)
	table.clear(candidates)

	ctx.Net:Handle("Arena.SetDefense", function(player, payload)
		return setDefense(player, payload.ids)
	end)
	ctx.Net:Handle("Arena.Refresh", function(player)
		return refresh(player)
	end)
	ctx.Net:Handle("Arena.Attack", function(player, payload)
		return attack(player, payload.candidate, payload.ids)
	end)
	ctx.Net:Handle("Arena.ClaimWeekly", function(player)
		return claimWeekly(player)
	end)
end

function Arena.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	local svc = ctx.Services.Arena
	if svc then
		local ok, record = svc.Get(player.UserId)
		if ok and record and type(record.rating) == "number" then
			ratings[player] = record.rating
		end
	end
	syncWeek(player, s)
	publish(player)
end

function Arena.PlayerRemoving(player)
	ratings[player] = nil
	candidates[player] = nil
end

return Arena
