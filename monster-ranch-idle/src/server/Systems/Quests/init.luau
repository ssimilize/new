--[[
	Quests (S6): the first-session tutorial, daily quests, achievements, codes and the
	seasonal Ranch Pass. Progress is driven by bus topics (Api.Topics); objective matching
	lives in Quests/Objectives.

	Save section (profile.Quests):
	  tutorial     = { step, progress }                  -- step indexes Config.Quests.Tutorial; > #Tutorial = done
	  daily        = { day, list = { { id, progress, claimed } } }
	  achievements = { [id] = { progress, claimed } }
	  codes        = { [CODE] = true }                   -- upper-case code keys
	  pass         = { season, xp, premium, claimed = { free = { [tier] = boolean }, premium = { [tier] = boolean } } }
	                 -- claimed tracks are contiguous arrays (false = not claimed) so they save cleanly
	  passCredit   = n                                   -- Ranch Passes paid for but banked for a later season

	Tutorial: the current step advances on its `topic` (with `filter`) up to `target`; `ack` steps
	complete through Quests.Ack. Completing a step grants its reward, fires Quests.StepDone and logs
	the onboarding funnel step. Entering Config.Quests.TutorialRain.step starts the scripted rain.

	Dailies: unlock at "dailies"; every UTC day Config.Quests.DailyCount entries are picked from
	DailyPool (skipping locked ones), deterministically per (userId, day).

	Ranch Pass: pass XP comes from claimed dailies and achievements while the season is open
	(Pass.startsAt ≤ now < Pass.endsAt, Pass = Config.Quests.PassAt(now), the latest season that has
	started). Earned tiers stay claimable until the next season,
	which resets pass progress. Premium needs the "Quests.RanchPass" product (registered with
	Monetization in Start) bought for the current season. It is sold only while a season runs
	(Config.Quests.PassOnSale; the product check refuses it otherwise, and when premium is already
	on). A receipt that arrives anyway, off season or for a second pass in one season, is banked in
	`passCredit` and unlocks premium automatically once a season is open without it (on join, on
	the 30 s sweep, or on any pass XP), so nobody pays for nothing.

	Public API (other systems):
	  Quests:TutorialStep(player) -> stepIndex, stepId?      -- stepId nil when the tutorial is done
	  Quests:TutorialDone(player) -> boolean
	  Quests:PassPremium(player) -> boolean
	  Quests:GrantPass(player) -> boolean                    -- a gifted pass: premium now, or banked
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local QuestsConfig = require(Shared.Config).Quests
local Format = require(Shared.Logic.Format)
local Objectives = require(script.Objectives)

local Quests = {
	Name = "Quests",
	Dependencies = { "Rewards", "Progression" },
	OptionalDependencies = { "Monetization", "Weather" },
}

local TRACKS = { "free", "premium" }
local DAILY_SWEEP_SECONDS = 30

local ctx
local Config -- Config.Quests
local Rewards, Progression

-- The Ranch Pass season in effect right now (Config.Quests.PassAt).
local function currentPass()
	return QuestsConfig.PassAt(if ctx then ctx:Now() else 0)
end

local function newPass()
	local def = currentPass()
	local tiers = #def.tiers
	return {
		season = def.season,
		xp = 0,
		premium = false,
		claimed = { free = table.create(tiers, false), premium = table.create(tiers, false) },
	}
end

Quests.Profile = {
	Version = 1,
	Default = function()
		return {
			tutorial = { step = 1, progress = 0 },
			daily = { day = 0, list = {} },
			achievements = {},
			codes = {},
			pass = newPass(),
			passCredit = 0,
		}
	end,
}

local dailyById = {}
local achievementById = {}
local scriptedRain = {} -- [player] = true once the tutorial rain ran this session

-- Helpers ------------------------------------------------------------------------------

local function section(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function trim(text: string): string
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

local function grant(player, rewards, source: string, silent: boolean?)
	if not rewards or #rewards == 0 then
		return {}
	end
	return Rewards:Grant(player, rewards, source, { silent = silent })
end

-- Ranch Pass ---------------------------------------------------------------------------

local function seasonOpen(): boolean
	local now = ctx:Now()
	local def = currentPass()
	return now >= def.startsAt and now < def.endsAt
end

-- A banked pass (see the header) unlocks the first open season that doesn't have premium yet.
local function applyPassCredit(player, s)
	local credit = tonumber(s.passCredit) or 0
	if credit <= 0 or s.pass.premium or not seasonOpen() then
		return
	end
	s.passCredit = credit - 1
	s.pass.premium = true
	ctx:Dirty(player, "passCredit")
	ctx:Dirty(player, "pass", "premium")
	ctx:Notify(player, "Your saved Ranch Pass unlocked this season's premium rewards!", "success")
	ctx:RequestSave(player)
end

local function ensurePass(player, s)
	local def = currentPass()
	if s.pass.season ~= def.season then
		s.pass = newPass()
		ctx:Dirty(player, "pass")
	else
		-- A live config may add tiers mid-season: keep the claim arrays contiguous.
		for _, track in TRACKS do
			local list = s.pass.claimed[track]
			if #list < #def.tiers then
				for i = #list + 1, #def.tiers do
					list[i] = false
				end
				ctx:Dirty(player, "pass")
			end
		end
	end
	applyPassCredit(player, s)
end

local function addPassXP(player, s, amount: number)
	ensurePass(player, s)
	if amount <= 0 or not seasonOpen() then
		return
	end
	s.pass.xp += amount
	ctx:Dirty(player, "pass", "xp")
end

local function onRanchPassPurchased(player, _product, _receiptInfo): boolean
	local s = ctx:Section(player)
	if not s then
		return false
	end
	ensurePass(player, s)
	local now = ctx:Now()
	if QuestsConfig.PassOnSale(now) and not s.pass.premium then
		s.pass.premium = true
		ctx:Dirty(player, "pass", "premium")
		ctx:Notify(player, "Ranch Pass unlocked! Premium rewards are ready to claim.", "success")
		return true
	end
	-- Off season, or a second pass this season (the Store refuses both): bank it, never refuse
	-- a receipt the player already paid for.
	s.passCredit = (tonumber(s.passCredit) or 0) + 1
	ctx:Dirty(player, "passCredit")
	local nextSeason = QuestsConfig.NextSeason(now)
	if nextSeason then
		local text = string.format("Your Ranch Pass is saved for Season %d and unlocks when it starts.", nextSeason.season)
		ctx:Notify(player, text, "success")
	else
		ctx:Notify(player, "Your Ranch Pass is saved and unlocks when the next season starts.", "success")
	end
	return true
end

-- Asked before the purchase prompt (Monetization.CanBuy).
local function canBuyRanchPass(player, _product): (boolean, string?)
	local s = ctx:Section(player)
	if not s then
		return false, "Your ranch is still loading"
	end
	local now = ctx:Now()
	if not QuestsConfig.PassOnSale(now) then
		local nextSeason = QuestsConfig.NextSeason(now)
		if nextSeason then
			return false, string.format("The next Ranch Pass goes on sale in %s", Format.duration(nextSeason.startsAt - now))
		end
		return false, "No Ranch Pass is on sale right now"
	end
	ensurePass(player, s)
	if s.pass.premium then
		return false, "You already have this season's Ranch Pass"
	end
	return true, nil
end

-- Tutorial -----------------------------------------------------------------------------

local function currentStep(s)
	return Config.Tutorial[s.tutorial.step]
end

local function startScriptedRain(player)
	local rain = Config.TutorialRain
	if not rain or not ctx.Config.Flags.TutorialScriptedRain or scriptedRain[player] then
		return
	end
	local Weather = ctx:GetSystem("Weather")
	if not Weather then
		return
	end
	scriptedRain[player] = true
	local ok, err = pcall(function()
		local current = Weather:Current()
		if current == nil or current.id == "clear" then
			Weather:Trigger(rain.weather, "tutorial", rain.seconds)
		end
		Weather:GuaranteeMutation(player, rain.mutation)
	end)
	if not ok then
		warn("[Quests] scripted tutorial rain failed: " .. tostring(err))
	end
end

local function enterStep(player, s)
	local step = currentStep(s)
	if step and Config.TutorialRain and step.id == Config.TutorialRain.step then
		startScriptedRain(player)
	end
end

local function completeStep(player, s)
	local index = s.tutorial.step
	local step = Config.Tutorial[index]
	if not step then
		return
	end
	s.tutorial.step = index + 1
	s.tutorial.progress = 0
	ctx:Dirty(player, "tutorial")
	-- Quests.StepDone carries the rewards for the tutorial dialog, so no generic reward toast.
	local granted = grant(player, step.reward, "tutorial", true)
	ctx.Net:Fire(player, "Quests.StepDone", { step = step.id, rewards = granted })
	ctx.Analytics.Onboarding(player, index, step.id)
	enterStep(player, s)
end

local function progressTutorial(player, s, topic: string, detail, amount: number)
	local step = currentStep(s)
	if not step or step.ack or step.topic ~= topic or not Objectives.Matches(step.filter, detail) then
		return
	end
	local target = Objectives.Target(step)
	s.tutorial.progress = math.min(target, s.tutorial.progress + amount)
	ctx:Dirty(player, "tutorial")
	if s.tutorial.progress >= target then
		completeStep(player, s)
	end
end

-- Dailies ------------------------------------------------------------------------------

local function ensureDaily(player, s)
	local today = ctx:Day()
	if s.daily.day == today and #s.daily.list > 0 then
		return
	end
	local list = {}
	if Progression:IsUnlocked(player, "dailies") then
		local picked = Objectives.PickDailies(Config.DailyPool, Config.DailyCount, player.UserId, today, function(def)
			return def.unlock == nil or Progression:IsUnlocked(player, def.unlock)
		end)
		for i, def in picked do
			list[i] = { id = def.id, progress = 0, claimed = false }
		end
	end
	if s.daily.day ~= today or #list > 0 then
		s.daily = { day = today, list = list }
		ctx:Dirty(player, "daily")
	end
end

local function progressDailies(player, s, topic: string, detail, amount: number)
	ensureDaily(player, s)
	for i, entry in s.daily.list do
		local def = dailyById[entry.id]
		if def and not entry.claimed and def.topic == topic and Objectives.Matches(def.filter, detail) then
			local target = Objectives.Target(def)
			if entry.progress < target then
				entry.progress = math.min(target, entry.progress + amount)
				ctx:Dirty(player, "daily", "list", i)
			end
		end
	end
end

-- Achievements -------------------------------------------------------------------------

local function achievementEntry(player, s, id: string)
	local entry = s.achievements[id]
	if not entry then
		entry = { progress = 0, claimed = false }
		s.achievements[id] = entry
		ctx:Dirty(player, "achievements", id)
	end
	return entry
end

local function progressAchievements(player, s, topic: string, detail, amount: number)
	for _, def in Config.Achievements do
		if def.topic == topic and Objectives.Matches(def.filter, detail) then
			local entry = achievementEntry(player, s, def.id)
			local target = Objectives.Target(def)
			if not entry.claimed and entry.progress < target then
				entry.progress = math.min(target, entry.progress + amount)
				ctx:Dirty(player, "achievements", def.id)
			end
		end
	end
end

-- Topic router -------------------------------------------------------------------------

local function onTopic(player, topic: string, detail)
	if player == nil then
		return
	end
	local s = ctx:Section(player)
	if not s then
		return
	end
	local amount = Objectives.Amount(Config.CountField, topic, detail or {})
	if amount <= 0 then
		return
	end
	progressTutorial(player, s, topic, detail or {}, amount)
	progressDailies(player, s, topic, detail or {}, amount)
	progressAchievements(player, s, topic, detail or {}, amount)
end

local function questTopics(): { string }
	local set = {}
	for _, list in { Config.Tutorial, Config.DailyPool, Config.Achievements } do
		for _, def in list do
			if def.topic then
				set[def.topic] = true
			end
		end
	end
	local topics = {}
	for topic in set do
		table.insert(topics, topic)
	end
	table.sort(topics)
	return topics
end

-- Codes --------------------------------------------------------------------------------

local function findCode(input: string): (string?, any)
	local wanted = string.upper(trim(input))
	for code, def in Config.Codes do
		if string.upper(code) == wanted then
			return string.upper(code), def
		end
	end
	return nil, nil
end

-- Public API ---------------------------------------------------------------------------

function Quests:TutorialStep(player): (number, string?)
	local s = ctx:Section(player)
	if not s then
		return 1, nil
	end
	local step = currentStep(s)
	return s.tutorial.step, step and step.id
end

function Quests:TutorialDone(player): boolean
	local s = ctx:Section(player)
	return s ~= nil and currentStep(s) == nil
end

-- A Ranch Pass from somewhere other than the player's own purchase (glow-up L: a friend's gift).
-- Same rules as buying one: premium now if the season is open without it, otherwise banked.
function Quests:GrantPass(player): boolean
	return onRanchPassPurchased(player, nil, nil)
end

function Quests:PassPremium(player): boolean
	local s = ctx:Section(player)
	return s ~= nil and s.pass.season == currentPass().season and s.pass.premium == true
end

-- Lifecycle ----------------------------------------------------------------------------

function Quests.Init(context)
	ctx = context
	Config = ctx.Config.Quests
	Rewards = ctx:GetSystem("Rewards")
	Progression = ctx:GetSystem("Progression")
	-- Module state belongs to one kernel (tests boot several in one process).
	table.clear(dailyById)
	table.clear(achievementById)
	table.clear(scriptedRain)

	for _, def in Config.DailyPool do
		dailyById[def.id] = def
	end
	for _, def in Config.Achievements do
		achievementById[def.id] = def
	end
	for code in Config.Codes do
		-- Saved as a map key: digit-only keys would turn into array indexes.
		assert(not string.match(code, "^%d+$"), "[Quests] codes must contain a letter: " .. code)
	end

	for _, topic in questTopics() do
		ctx.Bus:Subscribe(topic, function(player, detail)
			onTopic(player, topic, detail)
		end)
	end
	ctx.Bus:Subscribe("LevelUp", function(player)
		local s = player and ctx:Section(player)
		if s then
			ensureDaily(player, s)
		end
	end)
	-- New dailies at UTC midnight for everyone online.
	ctx:Every(DAILY_SWEEP_SECONDS, function()
		for _, player in ctx:Players() do
			local s = ctx:Section(player)
			if s then
				ensureDaily(player, s)
				ensurePass(player, s) -- a new season: fresh pass, and any banked pass unlocks
			end
		end
	end)

	ctx.Net:Handle("Quests.Ack", function(player, payload)
		local s = section(player)
		local step = currentStep(s)
		if not step then
			ctx:Fail("The tutorial is already done")
		end
		if step.id ~= payload.step then
			ctx:Fail("That tutorial step isn't active")
		end
		if not step.ack then
			ctx:Fail("Finish this step first")
		end
		completeStep(player, s)
		return nil
	end)

	ctx.Net:Handle("Quests.ClaimDaily", function(player, payload)
		local s = section(player)
		Progression:Require(player, "dailies")
		ensureDaily(player, s)
		local entry = s.daily.list[payload.index]
		local def = entry and dailyById[entry.id]
		if not def then
			ctx:Fail("There's no daily quest there")
		end
		if entry.claimed then
			ctx:Fail("Already claimed")
		end
		if entry.progress < Objectives.Target(def) then
			ctx:Fail("Finish the quest first")
		end
		entry.claimed = true
		ctx:Dirty(player, "daily", "list", payload.index)
		local granted = grant(player, def.reward, "daily")
		addPassXP(player, s, currentPass().xpPerDaily)
		ctx.Analytics.Custom(player, "DailyClaimed", 1, { quest = def.id })
		return { rewards = granted }
	end)

	ctx.Net:Handle("Quests.ClaimAchievement", function(player, payload)
		local s = section(player)
		local def = achievementById[payload.id]
		if not def then
			ctx:Fail("That achievement doesn't exist")
		end
		local entry = achievementEntry(player, s, def.id)
		if entry.claimed then
			ctx:Fail("Already claimed")
		end
		if entry.progress < Objectives.Target(def) then
			ctx:Fail("Not finished yet")
		end
		entry.claimed = true
		ctx:Dirty(player, "achievements", def.id)
		local granted = grant(player, def.reward, "achievement")
		addPassXP(player, s, currentPass().xpPerAchievement)
		ctx.Analytics.Custom(player, "AchievementClaimed", 1, { achievement = def.id })
		return { rewards = granted }
	end)

	ctx.Net:Handle("Quests.ClaimPass", function(player, payload)
		local s = section(player)
		ensurePass(player, s)
		local def = currentPass()
		local tier = def.tiers[payload.tier]
		if not tier then
			ctx:Fail("That tier doesn't exist")
		end
		local needed = payload.tier * def.xpPerTier
		if s.pass.xp < needed then
			ctx:Fail(string.format("Reach %d Pass XP to unlock tier %d", needed, payload.tier))
		end
		if payload.track == "premium" and not s.pass.premium then
			ctx:Fail("Premium rewards need the Ranch Pass")
		end
		if s.pass.claimed[payload.track][payload.tier] == true then
			ctx:Fail("Already claimed")
		end
		s.pass.claimed[payload.track][payload.tier] = true
		ctx:Dirty(player, "pass", "claimed")
		local granted = grant(player, tier[payload.track], "pass")
		return { rewards = granted }
	end)

	ctx.Net:Handle("Quests.Redeem", function(player, payload)
		local key, def = findCode(payload.code)
		if not key then
			ctx:Fail("That code doesn't exist")
		end
		if section(player).codes[key] then
			ctx:Fail("You already used that code")
		end
		if def.expires and ctx:Now() >= def.expires then
			ctx:Fail("That code has expired")
		end
		if def.requiresGroup and not ctx.Services.Players.IsInGroup(player, Config.GroupId) then
			ctx:Fail("Join our Roblox group to use this code")
		end
		-- The group check yields: re-read the section and re-check before granting.
		local s = section(player)
		if s.codes[key] then
			ctx:Fail("You already used that code")
		end
		s.codes[key] = true
		ctx:Dirty(player, "codes", key)
		local granted = grant(player, def.reward, "code")
		ctx:RequestSave(player)
		ctx.Analytics.Custom(player, "CodeRedeemed", 1, { code = key })
		return { rewards = granted }
	end)
end

function Quests.Start()
	local Monetization = ctx:GetSystem("Monetization")
	if Monetization then
		Monetization:RegisterProduct("Quests.RanchPass", onRanchPassPurchased)
		Monetization:RegisterProductCheck("Quests.RanchPass", canBuyRanchPass)
	end
end

function Quests.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	if not s then
		return
	end
	if type(s.tutorial.step) ~= "number" or s.tutorial.step < 1 then
		s.tutorial.step, s.tutorial.progress = 1, 0
	end
	ensurePass(player, s)
	ensureDaily(player, s)
	for _, def in Config.Achievements do
		achievementEntry(player, s, def.id)
	end
	-- Rejoining mid-step: the rain dialog should still have rain behind it.
	enterStep(player, s)
end

function Quests.PlayerRemoving(player)
	scriptedRain[player] = nil
end

return Quests
