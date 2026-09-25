--[[
	Contests (update 1.5 · Showtime): Monster Contests, themed shows on each server where
	players dress a monster up and everyone votes. Rules and numbers: Config/Contests.

	Save section (profile.Contests): { shows, wins, podiums, best, votes }
	  shows = shows entered, wins = 1st places, podiums = top 3, best = best rank (0 = none),
	  votes = runway votes cast
	Session (session.Contests): { entered = monsterId|false, votes = { [entryIndex] = stars } }
	Global (global.Contests):
	  { state = "idle"|"entry"|"runway"|"results", show, theme, endsAt, nextAt,
	    entries = { { userId, name, appearance } }, current, results = { Result } }
	  Result = { userId, name, appearance, score, votes, rank }
	  endsAt = when the current phase (or the current runway walk) ends.

	The phase follows the unix clock (Config.Show(now)) and is advanced every second:
	entry → runway (entries' appearances are snapshotted, outfits locked in; no entries → idle)
	→ one walk per entry → results (scores, prizes, stats) → idle until the next show.
	Votes are kept only in server memory: votes[entryIndex][userId] = stars.

	Actions: Contests.Enter { id }, Contests.Withdraw, Contests.Vote { entry, stars }.
	Publishes ContestEntered (player, { show, theme }), ContestVoted (player, {}),
	ContestPlaced (player, { rank, entries, theme, score }).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Appearance = require(Shared.Logic.Appearance)

local Contests = {
	Name = "Contests",
	Dependencies = { "Currency", "Progression", "Monsters", "Rewards" },
}

Contests.Profile = {
	Version = 1,
	Default = function()
		return { shows = 0, wins = 0, podiums = 0, best = 0, votes = 0 }
	end,
}

local ctx
local Config -- Config.Contests
local Progression, Monsters, Rewards

local entered = {} -- [player] = monsterId (this show)
local order = {} -- players in entry order (this show)
local votes = {} -- [entryIndex] = { [userId] = stars }
local runStart = 0 -- when the first runway walk started

local function G()
	return ctx:Global()
end

local function setSession(player)
	local sess = ctx:Session(player)
	if not sess then
		return
	end
	sess.entered = entered[player] or false
	local mine = {}
	for i, byUser in votes do
		mine[i] = byUser[player.UserId]
	end
	sess.votes = mine
	ctx:DirtySession(player)
end

local function appearanceOf(player, id: string)
	local m = Monsters:Get(player, id)
	return m and Appearance.Of(m)
end

-- The public entry list (appearances as they look right now).
local function publishEntries()
	local list = {}
	for _, player in order do
		local id = entered[player]
		local ap = id and appearanceOf(player, id)
		if ap then
			table.insert(list, { userId = player.UserId, name = player.DisplayName or player.Name, appearance = ap })
		end
	end
	G().entries = list
	ctx:DirtyGlobal()
end

local function resetShow()
	table.clear(entered)
	table.clear(order)
	table.clear(votes)
	for _, player in ctx:Players() do
		setSession(player)
	end
end

-- Phases -------------------------------------------------------------------------------

local function setState(state: string, endsAt: number)
	local g = G()
	g.state = state
	g.endsAt = endsAt
	ctx:DirtyGlobal()
end

local function openEntry(info)
	resetShow()
	local g = G()
	g.show = info.show
	g.theme = Config.ThemeFor(info.show).id
	g.nextAt = info.nextAt
	g.entries = {}
	g.results = {}
	g.current = 0
	setState("entry", info.entryEndsAt)
end

local function startRunway(now: number)
	-- Lock in outfits; drop players who left or whose monster is gone.
	local kept = {}
	for _, player in order do
		if entered[player] and appearanceOf(player, entered[player]) and ctx:IsReady(player) then
			table.insert(kept, player)
		else
			entered[player] = nil
		end
	end
	order = kept
	publishEntries()
	if #G().entries == 0 then
		setState("idle", G().nextAt)
		return
	end
	runStart = now
	G().current = 1
	setState("runway", now + Config.RunwaySeconds)
end

local function score(index: number, theme): (number, number)
	local judge = Config.JudgeScore(G().entries[index].appearance.acc, theme)
	local sum, n = 0, 0
	for _, stars in votes[index] or {} do
		sum += stars
		n += 1
	end
	local value = if n > 0 then Config.VoteWeight * (sum / n) + (1 - Config.VoteWeight) * judge else judge
	return math.floor(value * 100 + 0.5) / 100, n
end

local function finish(now: number)
	local g = G()
	local theme = Config.ThemeById[g.theme]
	local results = {}
	for i, entry in g.entries do
		local value, n = score(i, theme)
		table.insert(results, {
			userId = entry.userId,
			name = entry.name,
			appearance = entry.appearance,
			score = value,
			votes = n,
			index = i,
		})
	end
	table.sort(results, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		elseif a.votes ~= b.votes then
			return a.votes > b.votes
		end
		return a.index < b.index
	end)
	for rank, r in results do
		r.rank = rank
		r.index = nil
	end
	g.results = results
	g.current = 0
	setState("results", now + Config.ResultsSeconds)

	-- Prizes and stats for everyone still here.
	local voted = {}
	for _, byUser in votes do
		for userId in byUser do
			voted[userId] = (voted[userId] or 0) + 1
		end
	end
	for _, player in ctx:Players() do
		local s = ctx:Section(player)
		local items = {}
		for _, r in results do
			if r.userId == player.UserId and s then
				for _, prize in Config.Prizes[r.rank] or Config.Prizes.entered do
					table.insert(items, prize)
				end
				s.shows += 1
				if r.rank == 1 then
					s.wins += 1
				end
				if r.rank <= 3 then
					s.podiums += 1
				end
				if s.best == 0 or r.rank < s.best then
					s.best = r.rank
				end
				ctx:Dirty(player)
				ctx.Bus:Publish("ContestPlaced", player, { rank = r.rank, entries = #results, theme = g.theme, score = r.score })
			end
		end
		local cast = voted[player.UserId] or 0
		if cast > 0 and s then
			table.insert(items, { kind = "ribbons", amount = math.min(cast, Config.VoteRibbonMax) * Config.VoteRibbon })
		end
		if #items > 0 then
			Rewards:Grant(player, items, "contest")
		end
	end
end

local function tick()
	local now = ctx:Now()
	local info = Config.Show(now)
	local g = G()
	if g.show ~= info.show then
		-- A new show: its entry window, if we are still inside it.
		if now < info.entryEndsAt then
			openEntry(info)
		else
			g.show = info.show
			g.nextAt = info.nextAt
			g.theme = Config.ThemeFor(info.show).id
			if g.state ~= "results" or now >= g.endsAt then
				resetShow()
				setState("idle", info.nextAt)
			end
		end
		return
	end
	if g.state == "entry" and now >= g.endsAt then
		startRunway(now)
	elseif g.state == "runway" and now >= g.endsAt then
		local index = math.floor((now - runStart) / Config.RunwaySeconds) + 1
		if index > #g.entries then
			finish(now)
		else
			g.current = index
			setState("runway", runStart + index * Config.RunwaySeconds)
		end
	elseif g.state == "results" and now >= g.endsAt then
		-- The podium (g.results) stays visible until the next show opens.
		resetShow()
		setState("idle", g.nextAt)
	end
end

-- Actions ------------------------------------------------------------------------------

local function enter(player, id: string)
	Progression:Require(player, Config.Unlock)
	tick()
	if G().state ~= "entry" then
		ctx:Fail("Entries are closed. The next show opens soon!")
	end
	if not Monsters:Get(player, id) then
		ctx:Fail("That monster doesn't exist")
	end
	if not entered[player] then
		if #order >= Config.MaxEntries then
			ctx:Fail("This show is full. Try the next one!")
		end
		table.insert(order, player)
		ctx.Bus:Publish("ContestEntered", player, { show = G().show, theme = G().theme })
	end
	entered[player] = id
	setSession(player)
	publishEntries()
	return { entries = #order }
end

local function withdraw(player)
	tick()
	if G().state ~= "entry" or not entered[player] then
		ctx:Fail("You have no entry to withdraw")
	end
	entered[player] = nil
	local i = table.find(order, player)
	if i then
		table.remove(order, i)
	end
	setSession(player)
	publishEntries()
	return nil
end

local function vote(player, index: number, stars: number)
	tick()
	local g = G()
	if g.state ~= "runway" or g.current ~= index then
		ctx:Fail("That monster isn't on the runway right now")
	end
	local entry = g.entries[index]
	if entry.userId == player.UserId then
		ctx:Fail("You can't vote for your own monster")
	end
	votes[index] = votes[index] or {}
	local first = votes[index][player.UserId] == nil
	votes[index][player.UserId] = stars
	if first then
		local s = ctx:Section(player)
		if s then
			s.votes += 1
			ctx:Dirty(player, "votes")
		end
		ctx.Bus:Publish("ContestVoted", player, {})
	end
	setSession(player)
	return { stars = stars }
end

-- Lifecycle ----------------------------------------------------------------------------

function Contests.Init(context)
	ctx = context
	Config = ctx.Config.Contests
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(entered)
	table.clear(order)
	table.clear(votes)

	ctx.Net:Handle("Contests.Enter", function(player, payload)
		return enter(player, payload.id)
	end)
	ctx.Net:Handle("Contests.Withdraw", function(player)
		return withdraw(player)
	end)
	ctx.Net:Handle("Contests.Vote", function(player, payload)
		return vote(player, payload.entry, payload.stars)
	end)

	local g = G()
	g.state, g.show, g.theme, g.endsAt, g.nextAt, g.entries, g.current, g.results = "idle", -1, "", 0, 0, {}, 0, {}
	tick()
end

function Contests.Start()
	ctx:Every(1, tick)
end

function Contests.PlayerAdded(player, _info)
	setSession(player)
end

function Contests.PlayerRemoving(player)
	if entered[player] and G().state == "entry" then
		entered[player] = nil
		local i = table.find(order, player)
		if i then
			table.remove(order, i)
		end
		publishEntries()
	end
	entered[player] = nil
end

return Contests
