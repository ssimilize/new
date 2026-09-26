--[[
	Visits (glow-up Y): likes that pay, the crown over this server's most-liked ranch, visiting a
	friend's ranch on any server, and the Ranch of the Week stage. Tuning in Config.Visits, pure
	rules in Logic/Visits (snapshots, crown leader) and Logic/Community.GiftGate (the like gate).

	Likes that pay: a like (Social.Like at a gate here, published as RanchLiked, or Visits.Like on
	a snapshot in the showcase) pays the liker Likes.likerReward and the owner Likes.ownerReward,
	once per liker/owner pair per UTC day, at most likerPaidPerDay / ownerPaidPerDay a day. The
	liker must pass Config.Visits.Gate (Ranch Level, play time, account age) or the like pays
	nobody and counts for neither the crown nor Ranch of the Week; self-likes are refused by
	Social and here. A snapshot like is mailed (Market:Send, kind Likes.mailKind) so the owner
	gets it, their reward and the weekly count on their next join or sync, wherever they are.

	Crown: counted likes received on this server today (module state, reset each UTC day); the
	leader among ranches on a plot here (ties by who reached the count first) wears it. A new
	holder gets a toast.

	Visiting: Visits.Visit { userId, snapshot? } to a Roblox friend. On this server -> their plot
	number. On another server of the universe (Services.Ranches.Locate) -> Services.Teleport.
	ToServer. Offline, full (the client asks again with snapshot = true when the teleport did not
	happen) or no Locate -> their saved snapshot (Services.Ranches.Load) goes into this player's
	session and their client draws it in the Visiting Showcase. Snapshots are saved
	(Services.Ranches.Save) when a player leaves and every Snapshot.saveSeconds when changed.

	Ranch of the Week: last week's #1 on the Config.Leaderboards board Visits.BoardId (likes
	received, Visits:WeekLikes) is read through Services.Leaderboards.Top, their snapshot loaded,
	and their showiest monsters published for the stage in the hub. Re-read every
	Stage.refreshSeconds (a new week shows a new winner).

	Save section (profile.Visits), version 1:
	  day, liked = { ['u'..userId] = true }   -- ranches liked today (either way)
	  paid = { ['u'..userId] = true }         -- pairs already paid today
	  paidCount, got                          -- likes that paid me as liker / as owner today
	  week, weekLikes                         -- counted likes received this leaderboard week
	  received                                -- counted likes received, lifetime
	Session (session.Visits): { showcase = Snapshot | false }   -- drawn only for this player
	Global (global.Visits):
	  crown = { userId, plot, likes, name } | false
	  stage = { week, userId, name, likes, monsters = { Appearance } } | false

	Actions: Visits.Visit { userId, snapshot? }, Visits.Leave {}, Visits.Like {}.
	Bus: subscribes RanchLiked (Social), PlayerReady. Mail kind Likes.mailKind (Market).
	Adapters (optional): Services.Ranches = { Save(userId, snap) -> ok, Load(userId) -> (ok, snap?),
	  Locate(userId) -> (ok, { placeId, jobId }?) }; absent = visits and the stage are off.

	Public API:
	  Visits:WeekLikes(player) -> number    -- the Ranch of the Week board value
	  Visits:Crown() -> userId?              -- the ranch wearing the crown here
	  Visits:SaveSnapshot(player) -> boolean -- save now (skips an unchanged snapshot)
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Visits)
local Gate = require(Shared.Logic.Community)

local Visits = {
	Name = "Visits",
	Dependencies = { "Progression", "Rewards" },
	OptionalDependencies = { "Social", "Plots", "Bond", "Market" },
}

Visits.Profile = {
	Version = 1,
	Default = function()
		return { day = 0, liked = {}, paid = {}, paidCount = 0, got = 0, week = 0, weekLikes = 0, received = 0 }
	end,
	Private = { "paid" },
}

local ctx
local Config, Cfg
local Progression, Rewards

local present = {} -- [player] = true while in the game
local counts = {} -- [userId] = { likes, at }: counted likes received on this server today
local countsDay = 0
local savedKey = {} -- [userId] = Encode of the last saved snapshot (without `at`)
local busy = { stage = false }

-- Helpers ---------------------------------------------------------------------------------------

local function displayName(player): string
	return player.DisplayName or player.Name
end

local function week(): number
	return Config.Leaderboards.Week(ctx:Now())
end

local function section(player)
	local s = ctx:Section(player)
	if not s then
		return nil
	end
	local today = ctx:Day()
	if s.day ~= today then
		s.day = today
		s.liked = {}
		s.paid = {}
		s.paidCount = 0
		s.got = 0
		ctx:Dirty(player)
	end
	local w = week()
	if s.week ~= w then
		s.week = w
		s.weekLikes = 0
		ctx:Dirty(player)
	end
	return s
end

local function accountDays(player): number?
	local ok, age = pcall(function()
		return player.AccountAge
	end)
	return if ok and type(age) == "number" then age else nil
end

-- true when this player's likes pay and count (Logic/Community gift gates, Config.Visits.Gate).
local function passesGate(player, tell: boolean): boolean
	local meta = ctx:Meta(player)
	local ok, why, need = Gate.GiftGate({
		level = Progression:GetLevel(player),
		playSeconds = meta and meta.playSeconds or 0,
		accountDays = accountDays(player),
	}, Cfg.Gate)
	if not ok and tell then
		if why == "level" then
			ctx:Notify(player, string.format("Likes pay rewards from Ranch Level %d", need or 0), "info")
		else
			ctx:Notify(player, "Likes from new players don't pay rewards yet", "info")
		end
	end
	return ok
end

local function payLiker(player, s)
	if s.paidCount >= Cfg.Likes.likerPaidPerDay then
		return false
	end
	s.paidCount += 1
	ctx:Dirty(player, "paidCount")
	Rewards:Grant(player, Cfg.Likes.likerReward, "like")
	return true
end

-- The owner's side of a like. counted = the liker passed the gate; likeWeek = the week it was given.
local function receiveLike(owner, counted: boolean, likeWeek: number?)
	local s = section(owner)
	if not s or not counted then
		return
	end
	s.received += 1
	ctx:Dirty(owner, "received")
	if likeWeek == nil or likeWeek == s.week then
		s.weekLikes += 1
		ctx:Dirty(owner, "weekLikes")
	end
	if s.got < Cfg.Likes.ownerPaidPerDay then
		s.got += 1
		ctx:Dirty(owner, "got")
		Rewards:Grant(owner, Cfg.Likes.ownerReward, "liked")
	end
end

-- Crown -----------------------------------------------------------------------------------------

local function plotOf(player): number
	local Plots = ctx:GetSystem("Plots")
	return (Plots and Plots:GetPlot(player)) or 0
end

local function checkDay()
	local today = ctx:Day()
	if countsDay ~= today then
		countsDay = today
		table.clear(counts)
	end
end

local function recomputeCrown()
	checkDay()
	local rows = {}
	for player in present do
		local c = counts[player.UserId]
		if c and plotOf(player) > 0 then
			table.insert(rows, { userId = player.UserId, likes = c.likes, at = c.at })
		end
	end
	local leader = Logic.Leader(rows)
	local G = ctx:Global()
	local old = G.crown
	local holder = leader and ctx:PlayerByUserId(leader)
	local crown = if holder
		then { userId = leader, plot = plotOf(holder), likes = counts[leader].likes, name = displayName(holder) }
		else false
	local oldId = if type(old) == "table" then old.userId else nil
	if
		type(old) ~= type(crown)
		or (type(crown) == "table" and (crown.userId ~= old.userId or crown.plot ~= old.plot or crown.likes ~= old.likes))
	then
		G.crown = crown
		ctx:DirtyGlobal("crown")
	end
	if holder and leader ~= oldId then
		ctx:Notify(holder, "Your ranch wears the crown: the most-liked ranch on this server today!", "success")
	end
end

local function countLike(owner)
	checkDay()
	local c = counts[owner.UserId] or { likes = 0, at = 0 }
	c.likes += 1
	c.at = ctx:Now()
	counts[owner.UserId] = c
	recomputeCrown()
end

-- Snapshots -------------------------------------------------------------------------------------

local function bestFriends(player, plot)
	local Bond = ctx:GetSystem("Bond")
	if not Bond then
		return {}
	end
	local rows = {}
	for _, pen in plot.pens or {} do
		for _, m in pen.monsters or {} do
			local hearts = Bond:Hearts(player, m.id)
			if hearts > 0 then
				table.insert(rows, { hearts = hearts, appearance = m.appearance })
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.hearts > b.hearts
	end)
	while #rows > Cfg.Snapshot.maxBest do
		table.remove(rows)
	end
	return rows
end

local function buildSnapshot(player)
	local Plots = ctx:GetSystem("Plots")
	if not Plots or type(Plots.Public) ~= "function" then
		return nil
	end
	local plot = Plots:Public(player)
	if type(plot) ~= "table" then
		return nil
	end
	return Logic.Build(Config, plot, bestFriends(player, plot), ctx:Now())
end

local function saveSnapshot(player): boolean
	local service = ctx.Services.Ranches
	if not service or type(service.Save) ~= "function" then
		return false
	end
	local snap = buildSnapshot(player)
	if not snap then
		return false
	end
	local at = snap.at
	snap.at = 0
	local key = Logic.Encode(snap)
	snap.at = at
	local userId = player.UserId
	if savedKey[userId] == key then
		return false
	end
	savedKey[userId] = key
	ctx.Services.Spawn(function()
		local ok = pcall(service.Save, userId, snap)
		if not ok and savedKey[userId] == key then
			savedKey[userId] = nil -- try again next time
		end
	end)
	return true
end

local function saveAll()
	for player in present do
		if ctx:IsReady(player) then
			saveSnapshot(player)
		end
	end
end

-- Ranch of the Week -----------------------------------------------------------------------------

local function refreshStage()
	local service, boards = ctx.Services.Ranches, ctx.Services.Leaderboards
	if busy.stage or not service or not boards then
		return
	end
	busy.stage = true
	ctx.Services.Spawn(function()
		local last = week() - 1
		local ok, top = pcall(boards.Top, Config.Leaderboards.Key(Cfg.BoardId, last), 1)
		local G = ctx:Global()
		if ok and type(top) == "table" then
			local first = top[1]
			local current = G.stage
			if not first then
				G.stage = false
				ctx:DirtyGlobal("stage")
			elseif type(current) ~= "table" or current.week ~= last or current.userId ~= first.userId then
				local called, loaded, record = pcall(service.Load, first.userId)
				local snap = if called and loaded then Logic.Sanitize(Config, record) else nil
				if snap then
					G.stage = {
						week = last,
						userId = first.userId,
						name = snap.name,
						likes = math.floor(tonumber(first.value) or 0),
						monsters = Logic.Monsters(snap, Cfg.Stage.maxMonsters),
					}
					ctx:DirtyGlobal("stage")
				end
			end
		end
		busy.stage = false
	end)
end

-- Actions ---------------------------------------------------------------------------------------

local function mustSection(player)
	local s = section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function visit(player, payload)
	local userId = payload.userId
	if userId == player.UserId then
		ctx:Fail("That's your own ranch")
	end
	local here = ctx:PlayerByUserId(userId)
	if here then
		return { mode = "here", plot = plotOf(here), name = displayName(here) }
	end
	if ctx.Services.Players.IsFriendsWith(player, userId) ~= true then
		ctx:Fail("You can only visit your Roblox friends' ranches")
	end
	local service = ctx.Services.Ranches
	if not service then
		ctx:Fail("Ranch visits aren't available right now")
	end
	if payload.snapshot ~= true and type(service.Locate) == "function" and ctx.Services.Teleport then
		local ok, found, where = pcall(service.Locate, userId)
		if ok and found and type(where) == "table" and type(where.jobId) == "string" and where.jobId ~= ctx.Services.JobId then
			local placeId = tonumber(where.placeId)
			if placeId and ctx.Services.Teleport.ToServer(player, placeId, where.jobId) then
				return { mode = "teleport" }
			end
		end
	end
	if Config.TradingHub.Mode(ctx.Services.PlaceId, ctx.Services.PlaceMode) == "hub" then
		ctx:Fail("Ranch snapshots show on the ranch server")
	end
	local ok, loaded, raw = pcall(service.Load, userId)
	if not ok or not loaded then
		ctx:Fail("Couldn't load that ranch right now. Try again soon")
	end
	local snap = Logic.Sanitize(Config, raw)
	if not snap or snap.userId ~= userId then
		ctx:Fail("That ranch has no snapshot yet")
	end
	local sess = ctx:Session(player)
	sess.showcase = snap
	ctx:DirtySession(player, "showcase")
	return { mode = "showcase", name = snap.name }
end

local function leave(player)
	local sess = ctx:Session(player)
	if sess.showcase then
		sess.showcase = false
		ctx:DirtySession(player, "showcase")
	end
	return nil
end

local function likeSnapshot(player)
	local snap = ctx:Session(player).showcase
	if type(snap) ~= "table" then
		ctx:Fail("Open a ranch in the showcase first")
	end
	local ownerId = snap.userId
	if ownerId == player.UserId then
		ctx:Fail("You can't like your own ranch")
	end
	if ctx:PlayerByUserId(ownerId) then
		ctx:Fail("That rancher is on this server: like their ranch at its gate")
	end
	local Market = ctx:GetSystem("Market")
	if not Market then
		ctx:Fail("Ranch visits aren't available right now")
	end
	local s = mustSection(player)
	local key = "u" .. tostring(ownerId)
	if s.liked[key] or s.paid[key] then
		ctx:Fail("You already liked this ranch today")
	end
	local given = 0
	for _ in s.liked do
		given += 1
	end
	if given >= Config.Social.LikesPerDay then
		ctx:Fail(string.format("You've used all %d likes today", Config.Social.LikesPerDay))
	end
	s.liked[key] = true
	ctx:Dirty(player, "liked", key)
	local counted = passesGate(player, true)
	local paid = false
	if counted then
		s.paid[key] = true
		paid = payLiker(player, s)
	end
	Market:Send(player, ownerId, {
		id = string.format("like:%d:%d:%d", player.UserId, ownerId, s.day),
		kind = Cfg.Likes.mailKind,
		from = player.UserId,
		fromName = displayName(player),
		counted = counted,
		week = s.week,
	})
	return { paid = paid, counted = counted }
end

-- A like given at a gate on this server (Social.Like).
local function onRanchLiked(player, detail)
	local owner = ctx:PlayerByUserId(tonumber(detail.owner) or 0)
	local s = section(player)
	if not owner or not s or owner == player then
		return
	end
	local key = "u" .. tostring(owner.UserId)
	if not s.liked[key] then
		s.liked[key] = true
		ctx:Dirty(player, "liked", key)
	end
	if s.paid[key] then
		return
	end
	if not passesGate(player, true) then
		return
	end
	s.paid[key] = true
	payLiker(player, s)
	ctx:Notify(owner, string.format("%s liked your ranch!", displayName(player)), "success")
	receiveLike(owner, true, nil)
	countLike(owner)
end

-- A like given to this player's snapshot on another server (Market mail).
local function receiveMail(player, entry): boolean
	if not ctx:Section(player) then
		return false
	end
	local Social = ctx:GetSystem("Social")
	if Social and type(Social.AddLike) == "function" then
		Social:AddLike(player)
	end
	local name = if type(entry.fromName) == "string" then string.sub(entry.fromName, 1, 24) else "A friend"
	ctx:Notify(player, string.format("%s liked your ranch!", name), "success")
	receiveLike(player, entry.counted == true, tonumber(entry.week) or -1)
	return true
end

-- Public API ------------------------------------------------------------------------------------

function Visits:WeekLikes(player): number
	local s = section(player)
	return if s then s.weekLikes else 0
end

function Visits:Crown(): number?
	local crown = ctx:Global().crown
	return if type(crown) == "table" then crown.userId else nil
end

function Visits:SaveSnapshot(player): boolean
	return saveSnapshot(player)
end

-- Lifecycle -------------------------------------------------------------------------------------

function Visits.Init(context)
	ctx = context
	Config = ctx.Config
	Cfg = Config.Visits
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(present)
	table.clear(counts)
	table.clear(savedKey)
	countsDay = 0
	busy.stage = false

	local G = ctx:Global()
	G.crown = false
	G.stage = false
	ctx:DirtyGlobal()

	ctx.Net:Handle("Visits.Visit", visit)
	ctx.Net:Handle("Visits.Leave", leave)
	ctx.Net:Handle("Visits.Like", likeSnapshot)

	ctx.Bus:Subscribe("RanchLiked", onRanchLiked)
	ctx.Bus:Subscribe("PlayerReady", function()
		-- Plots assigns on the same topic: look at the crown once the plot is known.
		ctx:After(1, recomputeCrown)
	end)
end

function Visits.Start()
	local Market = ctx:GetSystem("Market")
	if Market then
		Market:RegisterMail(Cfg.Likes.mailKind, receiveMail)
	end
	ctx:Every(Cfg.Snapshot.saveSeconds, saveAll)
	ctx:Every(Cfg.Stage.refreshSeconds, refreshStage)
	ctx:Every(60, function()
		if countsDay ~= ctx:Day() then
			recomputeCrown()
		end
	end)
	refreshStage()
end

function Visits.PlayerAdded(player, _info)
	section(player)
	present[player] = true
	local sess = ctx:Session(player)
	sess.showcase = false
	ctx:DirtySession(player)
end

function Visits.PlayerRemoving(player)
	saveSnapshot(player)
	present[player] = nil
	savedKey[player.UserId] = nil
	recomputeCrown()
end

return Visits
