--[[
	TrialTower (update 3.12 · Honey & stars): the Trial Tower, an endless weekly climb fought with
	the Expeditions squad. Rules: Config/TrialTower and Logic/TrialTower. Opened from the tower in
	the Market Square (Config.World.Hub "trialTower") and the Expeditions screen's header.

	Save section (profile.TrialTower), version 1:
	  week, best            -- this leaderboard week and the highest floor cleared in it (the next
	                           floor to fight is best + 1)
	  record                -- the highest floor ever cleared (record bonuses pay as it rises)
	  day, used             -- UTC day and the daily attempts lost that day
	  retries               -- Retry tokens held (spent on a loss once the day's attempts are out)
	  paid = { [floor]: true }  -- milestones paid this week
	  fights, cleared       -- fights ever (the fight seed's counter), floors cleared ever

	Actions:
	  TrialTower.Fight {} -> { win, floor, best, record, replay, rewards, left, retries, spent }
	    Fights floor best + 1 with the default squad (Expeditions:GetSquad, every member free)
	    through Logic/TrialTower.Fight, seeded by (userId, week, floor, fights). A win climbs one
	    floor and pays the floor's milestone (once a week) and record bonus (once ever); a loss
	    uses one of the day's attempts, else a Retry token (`spent` = "attempt" | "retry").
	    With no attempts and no tokens the fight is refused.

	Public API:
	  TrialTower:AddRetries(player, n) -> number   new token count (Rewards kind "tower_retry")
	  TrialTower:Best(player) -> number            this week's highest floor (the "tower" board)
	  TrialTower:Record(player) -> number          the all-time highest floor
	  TrialTower:AttemptsLeft(player) -> number    the day's attempts left

	Bus: publishes TowerFloorCleared (player, { floor, best }) per won fight (Weekly goal tower_10).
	Subscribes to nothing; Expedition Bounties pay their token through Config.Bounties.Reward and
	the Travelling Merchant through its "tower_retry" offer.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.TrialTower)

local TrialTower = {
	Name = "TrialTower",
	Dependencies = { "Progression", "Monsters", "Rewards", "Expeditions" },
}

TrialTower.Profile = {
	Version = 1,
	Default = function()
		return {
			week = 0,
			best = 0,
			record = 0,
			day = 0,
			used = 0,
			retries = 0,
			paid = {},
			fights = 0,
			cleared = 0,
		}
	end,
}

local TICK = 30

local ctx
local Cfg -- Config.TrialTower
local Progression, Monsters, Rewards, Expeditions

local function week(): number
	return ctx.Config.Leaderboards.Week(ctx:Now())
end

-- Rolls the daily attempts and the weekly climb over.
local function sync(player, s)
	local day, wk = ctx:Day(), week()
	if s.day ~= day then
		s.day = day
		s.used = 0
		ctx:Dirty(player)
	end
	if s.week ~= wk then
		s.week = wk
		s.best = 0
		s.paid = {}
		ctx:Dirty(player)
	end
end

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	sync(player, s)
	return s
end

local function synced(player)
	local s = ctx:Section(player)
	if s then
		sync(player, s)
	end
	return s
end

-- Public API ---------------------------------------------------------------------------

function TrialTower:AddRetries(player, n: number): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	s.retries = math.clamp((tonumber(s.retries) or 0) + math.floor(n), 0, Cfg.RetryCap)
	ctx:Dirty(player, "retries")
	return s.retries
end

function TrialTower:Best(player): number
	local s = synced(player)
	return if s then s.best else 0
end

function TrialTower:Record(player): number
	local s = ctx:Section(player)
	return if s then s.record else 0
end

function TrialTower:AttemptsLeft(player): number
	local s = synced(player)
	return if s then math.max(0, Cfg.DailyAttempts - s.used) else 0
end

-- Actions ----------------------------------------------------------------------------------

local function squadOf(player)
	local ids = Expeditions:GetSquad(player)
	if #ids == 0 then
		ctx:Fail("Pick a squad first")
	end
	local members = {}
	for _, id in ids do
		local m, why = Monsters:Available(player, id)
		if not m then
			ctx:Fail(why or "That squad can't go")
		end
		table.insert(members, m)
	end
	return members
end

local function fight(player)
	Progression:Require(player, Cfg.Unlock)
	local s = mustSection(player)
	local left = math.max(0, Cfg.DailyAttempts - s.used)
	if left <= 0 and s.retries <= 0 then
		ctx:Fail("No attempts left today. Use a Retry token or come back tomorrow")
	end
	local members = squadOf(player)

	local floor = s.best + 1
	local seed = Logic.FightSeed(player.UserId, s.week, floor, s.fights)
	s.fights += 1
	local replay = Logic.Fight(members, s.week, floor, seed)

	local rewards = {}
	local spent = nil
	if replay.win then
		s.best = floor
		s.cleared += 1
		local items = {}
		local milestone = Logic.Milestone(floor)
		if milestone and not s.paid[floor] then
			s.paid[floor] = true
			for _, item in milestone do
				table.insert(items, item)
			end
		end
		if floor > s.record then
			s.record = floor
			for _, item in Logic.RecordReward(floor) or {} do
				table.insert(items, item)
			end
		end
		if #items > 0 then
			rewards = Rewards:Grant(player, items, Cfg.Source, { silent = true })
		end
		ctx.Bus:Publish("TowerFloorCleared", player, { floor = floor, best = s.best })
		ctx.Analytics.Custom(player, "tower_floor", floor, { boss = tostring(Logic.IsBoss(floor)) })
	elseif left > 0 then
		s.used += 1
		spent = "attempt"
	else
		s.retries -= 1
		spent = "retry"
	end
	ctx:Dirty(player)
	return {
		win = replay.win,
		floor = floor,
		best = s.best,
		record = s.record,
		replay = replay,
		rewards = rewards,
		left = math.max(0, Cfg.DailyAttempts - s.used),
		retries = s.retries,
		spent = spent,
	}
end

-- Lifecycle ----------------------------------------------------------------------------

function TrialTower.Init(context)
	ctx = context
	Cfg = ctx.Config.TrialTower
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	Expeditions = ctx:GetSystem("Expeditions")

	ctx.Net:Handle("TrialTower.Fight", function(player)
		return fight(player)
	end)

	-- Settles the day and the week for everyone online (the screen reads the save).
	ctx:Every(TICK, function()
		for _, player in ctx:Players() do
			synced(player)
		end
	end)
end

function TrialTower.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	-- Drops anything a damaged save left behind.
	if type(s.paid) ~= "table" then
		s.paid = {}
	end
	for _, key in { "week", "best", "record", "day", "used", "retries", "fights", "cleared" } do
		s[key] = math.max(0, math.floor(tonumber(s[key]) or 0))
	end
	s.record = math.max(s.record, s.best)
	sync(player, s)
	ctx:Dirty(player)
end

return TrialTower
