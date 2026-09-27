--[[
	Fishing (update 3.10 · Ranch life): the Fishing Pond on every plot. Rules: Config/Fishing and
	Logic/Fishing. Opened from the pond's "Go fishing" prompt (Controllers/Interaction).

	Save section (profile.Fishing):
	  day, casts            -- free casts used today (UTC day)
	  bait                  -- bait owned (one extra cast each)
	  fish = { [fishId]: n }            -- fish in the bucket (sold, or cooked by the Kitchen)
	  log = { [fishId]: { n, best } }   -- the Fish Log: caught ever, heaviest (kg)
	  buddy                 -- monster id of the fishing buddy (an Adult) or false
	  week, weekBest, weekFish          -- biggest catch this leaderboard week (kg × WeightScale)
	  total, best           -- fish caught ever, heaviest ever (kg)

	Actions:
	  Fishing.Start {} -> { run, seed, bonus, season, duration, casts, bait }
	    season (3.11) = Logic/Seasons.At(now).id, fixed for the run: that season's fish can bite.
	    Spends a free cast, else a bait. One open run per player (a new cast replaces it).
	  Fishing.Finish { run, inputs = { { t, down } } } -> { caught, fish, rarity, weight, time, rewards, best, first }
	    Replays the moves (Logic/Fishing.Simulate with the bonus fixed at Start); the run must have
	    taken at least the simulated time on the wall clock (minus GraceSeconds) and be finished
	    within Duration + LateSeconds. Run ids are one-shot.
	  Fishing.Sell { fish, amount } -> { coins }    coins = the rarity's value in seconds of ranch income
	  Fishing.SetBuddy { id } -> nil                any Adult (stage 3) you own

	Public API:
	  Fishing:FishCount(player) -> number           every fish in the bucket (Kitchen)
	  Fishing:SpendFish(player, n, kind?) -> boolean  cheapest fish first (one `kind` first when given,
	                                                3.11 seasonal recipes); false and no change if short
	  Fishing:Have(player, fishId) -> number        that kind in the bucket
	  Fishing:AddBait(player, n) -> number          new bait count (Rewards kind "bait")
	  Fishing:SpeciesCaught(player) -> number       kinds in the Fish Log (Codex Fish Log milestones)
	  Fishing:WeekBest(player) -> (number, string?) biggest catch this week in kg × WeightScale, fish name
	  Fishing:Bonus(player) -> number               the buddy's Luck bonus right now

	Publishes FishCaught (player, { fish, rarity, weight, seasonal }) (seasonal: 3.11, a season's fish).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Fishing)
local Formulas = require(Shared.Logic.Formulas)
local Seasons = require(Shared.Logic.Seasons)

local Fishing = {
	Name = "Fishing",
	Dependencies = { "Progression", "Monsters", "Rewards" },
	OptionalDependencies = { "Observatory" }, -- 3.12: the rare_fish star perk
}

Fishing.Profile = {
	Version = 1,
	Default = function()
		return {
			day = 0,
			casts = 0,
			bait = 0,
			fish = {},
			log = {},
			buddy = false,
			week = 0,
			weekBest = 0,
			weekFish = "",
			total = 0,
			best = 0,
		}
	end,
}

local ctx
local Cfg -- Config.Fishing
local Progression, Monsters, Rewards
local Observatory -- 3.12, optional (found in Start)

local runs = {} -- [player] = { id, seed, bonus, season, startedAt }
local nextRun = 0

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
		s.casts = 0
		ctx:Dirty(player)
	end
	if s.week ~= wk then
		s.week = wk
		s.weekBest = 0
		s.weekFish = ""
		ctx:Dirty(player)
	end
end

local function buddyOf(player, s)
	local m = s.buddy and Monsters:Get(player, s.buddy)
	if m and (m.stage or 1) == 3 then
		return m
	end
	return nil
end

-- Public API ---------------------------------------------------------------------------

function Fishing:Bonus(player): number
	local s = ctx:Section(player)
	local m = s and buddyOf(player, s)
	return if m then Logic.BuddyBonus(Formulas.Stats(m).luck) else 0
end

function Fishing:FishCount(player): number
	local s = ctx:Section(player)
	local n = 0
	if s then
		for _, count in s.fish do
			n += count
		end
	end
	return n
end

function Fishing:Have(player, fishId: string): number
	local s = ctx:Section(player)
	local n = s and s.fish[fishId]
	return if type(n) == "number" then n else 0
end

function Fishing:SpendFish(player, n: number, kind: string?): boolean
	local s = ctx:Section(player)
	if not s or type(n) ~= "number" or n ~= n or n < 0 or n % 1 ~= 0 then
		return false
	end
	if Fishing:FishCount(player) < n then
		return false
	end
	local left = n
	if kind ~= nil then
		if n < 1 or Fishing:Have(player, kind) < 1 then
			return false
		end
		s.fish[kind] = if s.fish[kind] > 1 then s.fish[kind] - 1 else nil
		left -= 1
	end
	for _, id in Logic.SpendOrder() do
		if left <= 0 then
			break
		end
		local have = s.fish[id] or 0
		local take = math.min(have, left)
		if take > 0 then
			s.fish[id] = if have - take > 0 then have - take else nil
			left -= take
		end
	end
	ctx:Dirty(player, "fish")
	return true
end

function Fishing:AddBait(player, n: number): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	s.bait = math.clamp(s.bait + math.max(0, math.floor(n)), 0, Cfg.MaxBait)
	ctx:Dirty(player, "bait")
	return s.bait
end

function Fishing:SpeciesCaught(player): number
	local s = ctx:Section(player)
	return if s then Logic.Species(s.log) else 0
end

function Fishing:WeekBest(player): (number, string?)
	local s = ctx:Section(player)
	if not s or s.week ~= week() or s.weekBest <= 0 then
		return 0, nil
	end
	local def = Cfg.ById[s.weekFish]
	return s.weekBest, if def then def.name else nil
end

-- Actions ------------------------------------------------------------------------------

local function start(player)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	sync(player, s)
	if s.casts < Cfg.FreeCasts then
		s.casts += 1
	elseif s.bait > 0 then
		s.bait -= 1
	else
		ctx:Fail("No casts left today. Use bait or come back tomorrow")
	end
	ctx:Dirty(player)
	nextRun += 1
	local seed = ctx.Rng:Int(1, 2 ^ 30)
	local bonus = Fishing:Bonus(player)
	-- 3.12: the Observatory's rare_fish perk adds to the bonus (nothing added at 0).
	local stars = if Observatory then Observatory:Perk(player, "rare_fish") else 0
	if type(stars) == "number" and stars > 0 then
		bonus += stars
	end
	local season = Seasons.At(ctx:Now()).id
	runs[player] = { id = nextRun, seed = seed, bonus = bonus, season = season, startedAt = ctx.Clock.Precise() }
	return {
		run = nextRun,
		seed = seed,
		bonus = bonus,
		season = season,
		duration = Cfg.Duration,
		casts = Cfg.FreeCasts - s.casts,
		bait = s.bait,
	}
end

local function finish(player, runId: number, inputs)
	local s = mustSection(player)
	local run = runs[player]
	if not run or run.id ~= runId then
		ctx:Fail("That cast has ended. Cast again!")
	end
	runs[player] = nil
	local ok, why = Logic.Valid(inputs)
	if not ok then
		ctx:Fail(string.format("That catch didn't add up (%s)", tostring(why)))
	end
	local result = Logic.Simulate(run.seed, inputs, run.bonus, run.season)
	local elapsed = ctx.Clock.Precise() - run.startedAt
	if elapsed + Cfg.GraceSeconds < result.time then
		ctx:Fail("That catch was too quick")
	end
	if elapsed > Cfg.Duration + Cfg.LateSeconds then
		ctx:Fail("That cast has ended. Cast again!")
	end
	if not result.caught then
		return {
			caught = false,
			fish = result.fish,
			rarity = result.rarity,
			weight = 0,
			time = result.time,
			rewards = {},
			best = 0,
			first = false,
		}
	end
	sync(player, s)
	local id, weight = result.fish, result.weight
	s.fish[id] = (s.fish[id] or 0) + 1
	local entry = s.log[id]
	local first = entry == nil
	if not entry then
		entry = { n = 0, best = 0 }
		s.log[id] = entry
	end
	entry.n += 1
	entry.best = math.max(entry.best, weight)
	s.total += 1
	s.best = math.max(s.best, weight)
	local scaled = math.floor(weight * ctx.Config.Leaderboards.WeightScale + 0.5)
	if scaled > s.weekBest then
		s.weekBest = scaled
		s.weekFish = id
	end
	ctx:Dirty(player)
	local extras = Logic.Extras(run.seed, run.bonus)
	local granted = if #extras > 0 then Rewards:Grant(player, extras, Cfg.Source) else {}
	local seasonal = Cfg.ById[id].season ~= nil
	ctx.Bus:Publish("FishCaught", player, { fish = id, rarity = result.rarity, weight = weight, seasonal = seasonal })
	return {
		caught = true,
		fish = id,
		rarity = result.rarity,
		weight = weight,
		time = result.time,
		rewards = granted,
		best = entry.best,
		first = first,
	}
end

local function sell(player, payload)
	local s = mustSection(player)
	local have = s.fish[payload.fish] or 0
	if have < payload.amount then
		ctx:Fail("You don't have that many fish")
	end
	s.fish[payload.fish] = if have - payload.amount > 0 then have - payload.amount else nil
	ctx:Dirty(player, "fish")
	local seconds = Logic.Value(payload.fish) * payload.amount
	local granted = Rewards:Grant(player, { { kind = "coins", seconds = seconds, amount = 0 } }, Cfg.Source)
	local coins = 0
	for _, item in granted do
		if item.kind == "coins" then
			coins += item.amount
		end
	end
	return { coins = coins }
end

local function setBuddy(player, payload)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	local m = Monsters:Get(player, payload.id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	if (m.stage or 1) ~= 3 then
		ctx:Fail("Only Adults can be a fishing buddy")
	end
	s.buddy = m.id
	ctx:Dirty(player, "buddy")
	return nil
end

-- Lifecycle ----------------------------------------------------------------------------

function Fishing.Init(context)
	ctx = context
	Cfg = ctx.Config.Fishing
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	table.clear(runs)

	ctx.Net:Handle("Fishing.Start", function(player)
		return start(player)
	end)
	ctx.Net:Handle("Fishing.Finish", function(player, payload)
		return finish(player, payload.run, payload.inputs)
	end)
	ctx.Net:Handle("Fishing.Sell", sell)
	ctx.Net:Handle("Fishing.SetBuddy", setBuddy)

	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = player and ctx:Section(player)
		if s and s.buddy and s.buddy == detail.id then
			s.buddy = false
			ctx:Dirty(player, "buddy")
		end
	end)
end

function Fishing.Start()
	Observatory = ctx:GetSystem("Observatory")
end

function Fishing.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	-- Drops anything a damaged save left behind.
	for key, value in { fish = {}, log = {} } do
		if type(s[key]) ~= "table" then
			s[key] = value
		end
	end
	for id, n in s.fish do
		if not Cfg.ById[id] or type(n) ~= "number" or n <= 0 then
			s.fish[id] = nil
		end
	end
	if s.buddy and not Monsters:Get(player, s.buddy) then
		s.buddy = false
	end
	sync(player, s)
	ctx:Dirty(player)
end

function Fishing.PlayerRemoving(player)
	runs[player] = nil
end

return Fishing
