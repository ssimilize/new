--[[
	Racing (update 3.0 · Year Two): Monster Racing on the Racetrack. Rules: Config/Racing and
	Logic/Racing.

	Save section (profile.Racing):
	  day, rewarded          -- races paid today (UTC day)
	  week, cup              -- Racing Cup points this leaderboard week
	  races, wins, best      -- lifetime races, 1st places and fastest time (0 = none)
	  bestDay, bestToday     -- fastest time on today's track

	Actions:
	  Racing.Start { id } -> { race, day, speed, ghosts = { { name, time } }, maxSeconds }
	    Races the Adult `id` (not busy, or being ridden) on today's track (seeded by the day).
	  Racing.Finish { race, inputs = { { t, a = "jump"|"boost" } } }
	    -> { time, finished, place, stumbles, rewards, cup, best, bestToday }
	The server keeps the open race (track, speed, start time) in memory and replays the moves;
	the race must have taken at least the simulated time on the wall clock (minus
	GraceSeconds) and be finished within MaxSeconds + LateSeconds.

	Public API: Racing:CupPoints(player) -> number   -- this week (Leaderboards "racing")
	Publishes RaceFinished (player, { place, time, day, cup }) and RanchXP.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Racing)
local Rng = require(Shared.Logic.Rng)

local Racing = {
	Name = "Racing",
	Dependencies = { "Progression", "Monsters", "Rewards" },
}

Racing.Profile = {
	Version = 1,
	Default = function()
		return { day = 0, rewarded = 0, week = 0, cup = 0, races = 0, wins = 0, best = 0, bestDay = 0, bestToday = 0 }
	end,
}

local ctx
local Config -- Config.Racing
local Progression, Monsters, Rewards

local races = {} -- [player] = { id, day, track, speed, ghosts, startedAt }
local nextRace = 0
local tracks = {} -- [day] = { track, ghosts } (cached)

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function week(): number
	return ctx.Config.Leaderboards.Week(ctx:Now())
end

-- Rolls the daily and weekly counters over.
local function sync(player, s)
	local day, wk = ctx:Day(), week()
	if s.day ~= day then
		s.day = day
		s.rewarded = 0
		ctx:Dirty(player)
	end
	if s.bestDay ~= day then
		s.bestDay = day
		s.bestToday = 0
		ctx:Dirty(player)
	end
	if s.week ~= wk then
		s.week = wk
		s.cup = 0
		ctx:Dirty(player)
	end
end

function Racing.TrackFor(day: number)
	local cached = tracks[day]
	if not cached then
		local track = Logic.Track(Rng.seed("racing", day))
		cached = { track = track, ghosts = Logic.Ghosts(track, day) }
		tracks = { [day] = cached } -- keep only today's
	end
	return cached
end

-- Public API ---------------------------------------------------------------------------

function Racing:CupPoints(player): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	return if s.week == week() then s.cup else 0
end

-- Actions ------------------------------------------------------------------------------

local function start(player, id: string)
	mustSection(player)
	Progression:Require(player, Config.Unlock)
	local m = Monsters:Get(player, id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	if m.stage ~= 3 then
		ctx:Fail("Only Adults can race")
	end
	if m.busy and m.busy ~= "riding" then
		ctx:Fail("That monster is busy")
	end
	local day = ctx:Day()
	local today = Racing.TrackFor(day)
	local speed = ctx.Config.Riding.SpeedFor(m) * Config.SpeedScale
	nextRace += 1
	races[player] = {
		id = nextRace,
		day = day,
		track = today.track,
		ghosts = today.ghosts,
		speed = speed,
		startedAt = ctx.Clock.Precise(),
	}
	return { race = nextRace, day = day, speed = speed, ghosts = today.ghosts, maxSeconds = Config.MaxSeconds }
end

local function finish(player, raceId: number, inputs)
	local s = mustSection(player)
	local race = races[player]
	if not race or race.id ~= raceId then
		ctx:Fail("That race is over. Start a new one!")
	end
	races[player] = nil
	local ok, why = Logic.Valid(inputs)
	if not ok then
		ctx:Fail("That race didn't add up (" .. tostring(why) .. ")")
	end
	local result = Logic.Simulate(race.track, race.speed, inputs)
	local elapsed = ctx.Clock.Precise() - race.startedAt
	if elapsed + Config.GraceSeconds < result.time then
		ctx:Fail("That race finished too quickly")
	end
	if elapsed > Config.MaxSeconds + Config.LateSeconds then
		ctx:Fail("That race is over. Start a new one!")
	end
	sync(player, s)
	local place = if result.finished then Logic.Place(result.time, race.ghosts) else #race.ghosts + 1
	s.races += 1
	if place == 1 then
		s.wins += 1
	end
	if result.finished then
		if s.best == 0 or result.time < s.best then
			s.best = result.time
		end
		if race.day == s.bestDay and (s.bestToday == 0 or result.time < s.bestToday) then
			s.bestToday = result.time
		end
	end
	local granted = {}
	local cup = 0
	if s.rewarded < Config.RewardedPerDay then
		s.rewarded += 1
		granted = Rewards:Grant(player, Config.PlaceRewards[place] or {}, "racing")
		cup = Config.CupPoints[place] or 0
		s.cup += cup
	end
	ctx:Dirty(player)
	ctx.Bus:Publish("RaceFinished", player, { place = place, time = result.time, day = race.day, cup = cup })
	ctx.Bus:Publish("RanchXP", player, { amount = 10, reason = "race" })
	return {
		time = result.time,
		finished = result.finished,
		place = place,
		stumbles = result.stumbles,
		rewards = granted,
		cup = cup,
		best = s.best,
		bestToday = s.bestToday,
	}
end

-- Lifecycle ----------------------------------------------------------------------------

function Racing.Init(context)
	ctx = context
	Config = ctx.Config.Racing
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(races)
	tracks = {}

	ctx.Net:Handle("Racing.Start", function(player, payload)
		return start(player, payload.id)
	end)
	ctx.Net:Handle("Racing.Finish", function(player, payload)
		return finish(player, payload.race, payload.inputs)
	end)
end

function Racing.PlayerAdded(player)
	local s = ctx:Section(player)
	if s then
		sync(player, s)
	end
end

function Racing.PlayerRemoving(player)
	races[player] = nil
end

return Racing
