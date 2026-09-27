--[[
	Weekly (update 3.8 · Reasons to come back): weekly goals and their three-step chest.

	From Ranch Level 5 (Config.Weekly.Unlock) each player gets Config.Weekly.GoalCount goals a
	week (Config.Leaderboards.Week, Saturday 15:00 UTC). The draw (Logic/Weekly.Pick) is seeded by
	("weekly", userId, week), takes only goals whose feature is unlocked at the moment the week's
	draw first happens, never two of one family, and then stays fixed for the week. Goals advance
	on bus topics like Quests objectives (Logic/Objectives, Config.Quests.CountField).

	Save section (profile.Weekly):
	  week    = the week the goals belong to (0 = never drawn)
	  goals   = { { id, progress } }           -- empty until the draw
	  claimed = { bool, bool, bool }           -- chest steps (Config.Weekly.Chest)

	Actions:
	  Weekly.Claim { step }  -- a reached, unclaimed chest step; returns { rewards }

	Rollover is lazy (on join, on any goal topic, on LevelUp and on a sweep every SWEEP_SECONDS,
	like Quests' dailies): steps reached but not claimed are paid automatically with Rewards source
	"weekly", and a WelcomeItem says so (the join summary shows it; mid-session the reward card
	does). The chest's last egg is a Royal egg from Config.Weekly.RoyalLevel (Logic/Weekly).

	No public API.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Objectives = require(Shared.Logic.Objectives)
local WeeklyLogic = require(Shared.Logic.Weekly)

local Weekly = {
	Name = "Weekly",
	Dependencies = { "Rewards", "Progression" },
}

local SWEEP_SECONDS = 30

local ctx
local Cfg -- Config.Weekly
local Rewards, Progression

local function freshClaimed()
	local list = {}
	for i in Cfg.Chest do
		list[i] = false
	end
	return list
end

Weekly.Profile = {
	Version = 1,
	Default = function()
		return { week = 0, goals = {}, claimed = { false, false, false } }
	end,
}

local function currentWeek(): number
	return ctx.Config.Leaderboards.Week(ctx:Now())
end

local function level(player): number
	return Progression:GetLevel(player)
end

local function payOut(player, section, steps: { number })
	local items = {}
	for _, step in steps do
		section.claimed[step] = true
		for _, item in WeeklyLogic.ChestReward(step, level(player)) do
			table.insert(items, item)
		end
	end
	if #items == 0 then
		return {}
	end
	return Rewards:Grant(player, items, "weekly")
end

-- Rolls the section over to this week (paying last week's unclaimed steps) and draws the goals
-- once the feature is unlocked.
local function ensureWeek(player, s)
	local week = currentWeek()
	if s.week ~= week then
		local owed = WeeklyLogic.Unclaimed(s)
		if #owed > 0 then
			payOut(player, s, owed)
			ctx.Bus:Publish("WelcomeItem", player, { kind = "weekly", text = "Your weekly chest paid out" })
			ctx.Analytics.Custom(player, "WeeklyAutoPaid", #owed, {})
		end
		s.week = week
		s.goals = {}
		s.claimed = freshClaimed()
		ctx:Dirty(player)
	end
	if #s.goals == 0 and Progression:IsUnlocked(player, Cfg.Unlock) then
		local picked = WeeklyLogic.Pick(Cfg.Pool, Cfg.GoalCount, player.UserId, week, function(def)
			return def.unlock == nil or Progression:IsUnlocked(player, def.unlock)
		end)
		for i, def in picked do
			s.goals[i] = { id = def.id, progress = 0 }
		end
		ctx:Dirty(player, "goals")
	end
end

local function onTopic(player, topic: string, detail)
	if player == nil then
		return
	end
	local s = ctx:Section(player)
	if not s then
		return
	end
	ensureWeek(player, s)
	detail = if type(detail) == "table" then detail else {}
	local amount = Objectives.Amount(ctx.Config.Quests.CountField, topic, detail)
	if amount <= 0 then
		return
	end
	for i, entry in s.goals do
		local def = Cfg.ById[entry.id]
		if def and def.topic == topic and Objectives.Matches(def.filter, detail) then
			local target = Objectives.Target(def)
			if entry.progress < target then
				entry.progress = math.min(target, entry.progress + amount)
				ctx:Dirty(player, "goals", i)
			end
		end
	end
end

local function goalTopics(): { string }
	local set, list = {}, {}
	for _, def in Cfg.Pool do
		if not set[def.topic] then
			set[def.topic] = true
			table.insert(list, def.topic)
		end
	end
	table.sort(list)
	return list
end

local function claim(player, payload)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	Progression:Require(player, Cfg.Unlock)
	ensureWeek(player, s)
	local step = payload.step
	local def = Cfg.Chest[step]
	if not def then
		ctx:Fail("There's no chest step there")
	end
	if WeeklyLogic.Claimed(s, step) then
		ctx:Fail("Already claimed")
	end
	if not WeeklyLogic.Reached(s, step) then
		ctx:Fail(string.format("Finish %d of your weekly goals first", def.goals))
	end
	local granted = payOut(player, s, { step })
	ctx:Dirty(player, "claimed")
	ctx.Analytics.Custom(player, "WeeklyChestClaimed", step, {})
	return { rewards = granted }
end

function Weekly.Init(context)
	ctx = context
	Cfg = ctx.Config.Weekly
	Rewards = ctx:GetSystem("Rewards")
	Progression = ctx:GetSystem("Progression")

	ctx.Net:Handle("Weekly.Claim", claim)

	for _, topic in goalTopics() do
		ctx.Bus:Subscribe(topic, function(player, detail)
			onTopic(player, topic, detail)
		end)
	end
	ctx.Bus:Subscribe("LevelUp", function(player)
		local s = player and ctx:Section(player)
		if s then
			ensureWeek(player, s)
		end
	end)
	ctx:Every(SWEEP_SECONDS, function()
		for _, player in ctx:Players() do
			local s = ctx:Section(player)
			if s then
				ensureWeek(player, s)
			end
		end
	end)
end

function Weekly.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	if not s then
		return
	end
	if type(s.goals) ~= "table" then
		s.goals = {}
	end
	if type(s.claimed) ~= "table" then
		s.claimed = freshClaimed()
	end
	ensureWeek(player, s)
end

return Weekly
