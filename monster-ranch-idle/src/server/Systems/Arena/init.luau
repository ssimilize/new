--[[
	Arena (update 2.1): asynchronous PvP with normalized stats. Rules: Config/Arena and
	Logic/Arena.

	Cross-server data (ctx.Services.Arena): one record per player
	  { userId, name, rating, team = { Fighter }, wins, losses, updatedAt, season }
	updated atomically; ratings are indexed for matchmaking (Services.Arena.Index / Near), one
	index per season (3.8): matchmaking only sees ratings from the current season.

	Seasons (3.8, Logic/Arena.SeasonAt): a record last touched in an older season gets its soft
	reset (Logic.Reseason) lazily, the first time it is loaded or updated in the new season, as the
	player's own record or as a defender. Fights boost the season's featured lines on both sides.
	The best tier of a season pays Config.Arena.SeasonRewards once, on the first join or arena
	action after the season ends (gems and cups through Rewards, source "arena_season"; titles
	and the aura through Mastery:GrantItem when Mastery is loaded) with a Welcome Back line.

	Save section (profile.Arena):
	  defense  = { monsterId }       -- the monsters behind the defense snapshot (for the UI)
	  attempts = { day, n }          -- attacks used this UTC day
	  week, bestTier                 -- this arena week and the best tier reached in it
	  lastTier, claimed              -- the last finished week's tier, and whether it was claimed
	  seasonOf, seasonBest           -- 3.8: the season being tracked and the best tier reached in it
	  seasonPaid                     -- 3.8: the last season whose reward was paid (0 = none)
	Session (session.Arena): { rating, tier, candidates = { Candidate }, attemptsLeft, season }
	  Candidate = { name, rating, bot, team = { { line, form, look } } }

	Actions:
	  Arena.SetDefense { ids }        -- TeamSize Adults; snapshot saved for other players
	  Arena.Refresh                   -- new candidates near your rating (bots fill in)
	  Arena.Attack { candidate, ids } -- fights a candidate; Elo for you (and a real defender)
	  Arena.ClaimWeekly               -- the finished week's tier reward, once
	Publishes ArenaBattle (player, { won, rating }) and WelcomeItem (a season reward was paid).

	Public API:
	  Arena:SeasonRating(player) -> number   -- this season's rating (0 before season 1 or unrated)
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Arena)

local Arena = {
	Name = "Arena",
	Dependencies = { "Progression", "Monsters", "Rewards" },
	OptionalDependencies = { "Mastery" }, -- 3.8: season titles and the aura (looked up lazily)
}

Arena.Profile = {
	Version = 2,
	Default = function()
		return {
			defense = {},
			attempts = { day = 0, n = 0 },
			week = 0,
			bestTier = "",
			lastTier = "",
			claimed = false,
			seasonOf = 0,
			seasonBest = "",
			seasonPaid = 0,
		}
	end,
	-- 2 (update 3.8): arena seasons.
	Migrate = function(section, from: number)
		if from < 2 then
			section.seasonOf = 0
			section.seasonBest = ""
			section.seasonPaid = 0
		end
		return section
	end,
}

local ctx
local Config -- Config.Arena
local Progression, Monsters, Rewards

local ratings = {} -- [player] = number (mirror of the Services.Arena record)
local ratedIn = {} -- [player] = the season the mirror was synced for (3.8)
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

local function currentSeason(): number
	return Logic.SeasonAt(ctx:Now())
end

local function tierRank(id: string): number
	for i, t in Config.Tiers do
		if t.id == id then
			return i
		end
	end
	return 0
end

local function attemptsLeft(s): number
	if s.attempts.day ~= ctx:Day() then
		return Config.AttemptsPerDay
	end
	return math.max(0, Config.AttemptsPerDay - s.attempts.n)
end

-- Rolls the arena week over and records the best tier reached this week (and this season).
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
		if s.bestTier == "" or tierRank(tier) > tierRank(s.bestTier) then
			s.bestTier = tier
			ctx:Dirty(player, "bestTier")
		end
		-- 3.8: the season's best, once the mirror belongs to the season being tracked.
		local season = s.seasonOf
		if season > 0 and ratedIn[player] == season and (s.seasonBest == "" or tierRank(tier) > tierRank(s.seasonBest)) then
			s.seasonBest = tier
			ctx:Dirty(player, "seasonBest")
		end
	end
end

-- Seasons (3.8) ---------------------------------------------------------------------------

-- Brings the player's own record into the current season (the lazy soft reset) and refreshes
-- the rating mirror. Runs once per season per session; a failed read or write retries later.
local function syncRating(player)
	local season = currentSeason()
	if ratedIn[player] == season then
		return
	end
	local svc = ctx.Services.Arena
	if not svc then
		return
	end
	local ok, record = svc.Get(player.UserId)
	if not ok then
		return
	end
	if record and type(record.rating) == "number" then
		if (tonumber(record.season) or 0) < season then
			local okUpdate, updated = svc.Update(player.UserId, function(current)
				if not current then
					return nil
				end
				Logic.Reseason(current, season)
				return current
			end)
			if not okUpdate or not updated then
				Logic.Reseason(record, season) -- show the reset now; the write retries later
				ratings[player] = record.rating
				return
			end
			record = updated
			svc.Index(player.UserId, record.rating, season)
		end
		ratings[player] = record.rating
	end
	ratedIn[player] = season
end

local function paySeason(player, s, season: number, tierId: string)
	s.seasonPaid = season
	ctx:Dirty(player, "seasonPaid")
	local reward = Config.SeasonRewards[tierId]
	if not reward then
		return -- Bronze earns nothing
	end
	Rewards:Grant(player, reward.items, "arena_season")
	local Mastery = ctx:GetSystem("Mastery")
	if Mastery then
		for _, itemId in { reward.titleId or false, reward.auraId or false } do
			if itemId then
				Mastery:GrantItem(player, itemId, true)
			end
		end
	end
	local tier = Config.Tiers[tierRank(tierId)] or Config.Tiers[1]
	ctx.Bus:Publish("WelcomeItem", player, {
		kind = "arena",
		icon = "trophy",
		text = string.format("Arena Season %d ended in %s. Your season rewards are in!", season, tier.name),
	})
end

-- Pays a finished season's best tier (once, guarded by seasonPaid), starts tracking the
-- current season, and syncs the rating into it.
local function syncSeason(player, s)
	local season = currentSeason()
	if s.seasonOf ~= season then
		local finished = s.seasonOf
		if finished > 0 and finished < season and s.seasonPaid < finished and s.seasonBest ~= "" then
			paySeason(player, s, finished, s.seasonBest)
		end
		s.seasonOf = season
		s.seasonBest = ""
		ctx:Dirty(player)
	end
	syncRating(player)
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
	sess.season = currentSeason()
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
		season = currentSeason(),
	}
end

-- Actions ------------------------------------------------------------------------------

local function setDefense(player, ids)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local team = teamOf(player, ids)
	syncSeason(player, s)
	local season = currentSeason()
	local ok, record = service().Update(player.UserId, function(current)
		local r = current or newRecord(player)
		Logic.Reseason(r, season)
		r.name = player.DisplayName or player.Name
		r.team = team
		r.updatedAt = ctx:Now()
		return r
	end)
	if not ok or not record then
		ctx:Fail("The arena is busy. Try again in a moment.")
	end
	ratings[player] = record.rating
	ratedIn[player] = season
	service().Index(player.UserId, record.rating, season)
	s.defense = table.clone(ids)
	ctx:Dirty(player, "defense")
	syncWeek(player, s)
	publish(player)
	return { rating = record.rating }
end

local function refresh(player)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	syncSeason(player, s)
	local season = currentSeason()
	local rating = ratings[player] or Config.StartRating
	local list = {}
	local ok, near = service().Near(rating, Config.RatingWindow, 20, season)
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
				-- An older season's record shows its reset rating (written when it is fought).
				local view = { rating = tonumber(record.rating) or Config.StartRating, season = record.season }
				Logic.Reseason(view, season)
				table.insert(list, {
					userId = entry.userId,
					name = record.name or "Rancher",
					rating = view.rating,
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
	syncSeason(player, s)
	local season = currentSeason()
	local seed = ctx.Rng:Int(1, 2 ^ 30)
	local replay = Logic.Fight(team, target.team, seed, season)
	local won = replay.win == true

	local mine = ratings[player] or Config.StartRating
	local delta = Logic.Delta(mine, target.rating, won)
	local ok, record = service().Update(player.UserId, function(current)
		local r = current or newRecord(player)
		Logic.Reseason(r, season)
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
	ratedIn[player] = season
	service().Index(player.UserId, record.rating, season)
	if target.userId then
		-- The defender's rating moves the other way (read fresh: they may have fought since).
		local okDef, def = service().Update(target.userId, function(current)
			if not current then
				return nil
			end
			Logic.Reseason(current, season) -- 3.8: a defender from an older season resets first
			current.rating = math.max(Config.MinRating, current.rating + Logic.Delta(current.rating, mine, not won))
			return current
		end)
		if okDef and def then
			service().Index(target.userId, def.rating, season)
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
	syncSeason(player, s)
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

-- Public API ---------------------------------------------------------------------------

function Arena:SeasonRating(player): number
	local season = currentSeason()
	if season <= 0 or ratedIn[player] ~= season then
		return 0
	end
	return ratings[player] or 0
end

-- Lifecycle ----------------------------------------------------------------------------

function Arena.Init(context)
	ctx = context
	Config = ctx.Config.Arena
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(ratings)
	table.clear(ratedIn)
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
	syncSeason(player, s) -- reads the record (its soft reset if it is from an older season)
	syncWeek(player, s)
	publish(player)
end

function Arena.PlayerRemoving(player)
	ratings[player] = nil
	ratedIn[player] = nil
	candidates[player] = nil
end

return Arena
