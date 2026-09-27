--[[
	TrialTower (update 3.12 · Honey & stars) on the server: the unlock gate, a win climbing a floor
	(and publishing TowerFloorCleared), a loss using a daily attempt, Retry tokens once the attempts
	are out, the daily and weekly resets, milestones once a week, the record bonus once ever, boss
	floors, the same enemies for everyone in a week, the Bounty and Merchant token sources, the
	Rewards kind, the "tower" board and the tower_10 weekly goal.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.TrialTower")
	local MerchantLogic = t.Shared("Logic.Merchant")

	local Cfg = Config.TrialTower
	local Boards = Config.Leaderboards
	local DAY = 86400
	local WEEK = Boards.WeekSeconds
	-- Saturday 16:00 UTC, an hour into leaderboard week 7: a day later is still the same week.
	local START = Boards.WeekAnchor + 7 * WEEK + 3600

	local SYSTEMS = {
		"Currency",
		"Progression",
		"Rewards",
		"Monsters",
		"Eggs",
		"Shop",
		"Ranch",
		"Expeditions",
		"TrialTower",
		"Leaderboards",
		"Weekly",
	}

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(opts)
		opts = opts or {}
		local systems = table.clone(SYSTEMS)
		for _, name in opts.extra or {} do
			table.insert(systems, name)
		end
		local h = TestKernel.new({ systems = systems, startTime = opts.at or START })
		local cleared = {}
		h.kernel.Bus:Subscribe("TowerFloorCleared", function(player, detail)
			table.insert(cleared, { player = player, detail = detail })
		end)
		return h, cleared
	end

	local function climber(h, opts)
		opts = opts or {}
		local p = h:Join(opts.userId)
		levelTo(h, p, opts.level or Config.Unlocks.Features.trial_tower)
		local ids = {}
		for i = 1, opts.size or 3 do
			local line = ({ "cindlet", "bubblin", "mossbun" })[(i - 1) % 3 + 1]
			local m = h:System("Monsters"):Create(p, { line = line, rarity = opts.rarity or 6, stage = 3 }, "test", true)
			m.lv = opts.lv or 100
			table.insert(ids, m.id)
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return p
	end

	-- A squad that cannot win high up: one Lv 1 Common.
	local function weakling(h)
		return climber(h, { size = 1, rarity = 1, lv = 1 })
	end

	local function setBest(h, p, best: number)
		h:Section(p, "TrialTower").best = best
	end

	-- Moves the clock without stepping every second of it (the tower settles days and weeks lazily).
	local function jump(h, seconds: number)
		h.adapters.advance(seconds)
		h:Advance(1)
	end

	-- One fight, spaced out past the action's rate limit.
	local function fight(h, p)
		h:Advance(1)
		return h:Call(p, "TrialTower.Fight")
	end

	local function find(items, kind: string)
		for _, item in items or {} do
			if item.kind == kind then
				return item
			end
		end
		return nil
	end

	describe("TrialTower climb", function()
		it("is locked below Ranch Level 26 and needs a squad", function()
			local h = boot()
			local p = h:Join()
			levelTo(h, p, Config.Unlocks.Features.trial_tower - 1)
			expect(h:Reject(p, "TrialTower.Fight")).toBe("Unlocks at Ranch Level 26")
			levelTo(h, p, Config.Unlocks.Features.trial_tower)
			expect(h:Reject(p, "TrialTower.Fight")).toBe("Pick a squad first")
		end)

		it("climbs a floor on a win, uses no attempt, and publishes TowerFloorCleared", function()
			local h, cleared = boot()
			local p = climber(h)
			local res = fight(h, p)
			expect(res.win).toBe(true)
			expect(res.floor).toBe(1)
			expect(res.best).toBe(1)
			expect(res.left).toBe(Cfg.DailyAttempts)
			expect(res.spent).toBeNil()
			expect(type(res.replay.events)).toBe("table")
			local s = h:Section(p, "TrialTower")
			expect(s.best).toBe(1)
			expect(s.record).toBe(1)
			expect(s.used).toBe(0)
			expect(#cleared).toBe(1)
			expect(cleared[1].detail.floor).toBe(1)
			expect(cleared[1].detail.best).toBe(1)
			res = fight(h, p)
			expect(res.floor).toBe(2)
			expect(h:System("TrialTower"):Best(p)).toBe(2)
		end)

		it("uses a daily attempt on a loss, then Retry tokens, and refuses with neither", function()
			local h, cleared = boot()
			local p = weakling(h)
			setBest(h, p, 40)
			for i = 1, Cfg.DailyAttempts do
				local res = fight(h, p)
				expect(res.win).toBe(false)
				expect(res.floor).toBe(41)
				expect(res.spent).toBe("attempt")
				expect(res.left).toBe(Cfg.DailyAttempts - i)
			end
			expect(#cleared).toBe(0)
			expect(h:System("TrialTower"):AttemptsLeft(p)).toBe(0)
			expect(h:Reject(p, "TrialTower.Fight")).toBe("No attempts left today. Use a Retry token or come back tomorrow")

			expect(h:System("TrialTower"):AddRetries(p, 2)).toBe(2)
			local res = fight(h, p)
			expect(res.spent).toBe("retry")
			expect(res.retries).toBe(1)
			expect(h:Section(p, "TrialTower").retries).toBe(1)
			expect(h:Section(p, "TrialTower").best).toBe(40)

			-- The next UTC day brings the attempts back (tokens are kept).
			jump(h, DAY)
			expect(h:System("TrialTower"):AttemptsLeft(p)).toBe(Cfg.DailyAttempts)
			res = fight(h, p)
			expect(res.spent).toBe("attempt")
			expect(res.retries).toBe(1)
		end)

		it("starts the climb over at the weekly reset and keeps the all-time record", function()
			local h = boot()
			local p = climber(h)
			fight(h, p)
			fight(h, p)
			expect(h:System("TrialTower"):Best(p)).toBe(2)
			jump(h, WEEK)
			expect(h:System("TrialTower"):Best(p)).toBe(0)
			local s = h:Section(p, "TrialTower")
			expect(s.record).toBe(2)
			expect(s.week).toBe(Boards.Week(START + WEEK))
			local res = fight(h, p)
			expect(res.floor).toBe(1)
		end)

		it("pays each milestone once a week and the record bonus once ever", function()
			local h = boot()
			local p = climber(h)
			setBest(h, p, 4)
			local res = fight(h, p)
			expect(res.floor).toBe(5)
			local dust = find(res.rewards, "stardust")
			expect(dust ~= nil and dust.amount == Cfg.MilestoneDust).toBe(true)
			expect(find(res.rewards, "coins") ~= nil).toBe(true)
			expect(find(res.rewards, "gems")).toBeNil()
			expect(h:Section(p, "TrialTower").paid[5]).toBe(true)

			-- Floor 5 again this week: no second payout.
			setBest(h, p, 4)
			res = fight(h, p)
			expect(res.win).toBe(true)
			expect(#res.rewards).toBe(0)

			-- Floor 10: the milestone plus the first-ever record gems.
			setBest(h, p, 9)
			local gems = h:Section(p, "Currency").gems
			res = fight(h, p)
			expect(res.win).toBe(true)
			expect(res.floor).toBe(10)
			expect(find(res.rewards, "gems").amount).toBe(Cfg.RecordGems)
			expect(find(res.rewards, "stardust").amount).toBe(Cfg.MilestoneDust * 2)
			expect(h:Section(p, "Currency").gems).toBe(gems + Cfg.RecordGems)
			expect(h:Section(p, "TrialTower").record).toBe(10)

			-- Next week: the milestones pay again, the record bonus does not.
			jump(h, WEEK)
			setBest(h, p, 4)
			res = fight(h, p)
			expect(find(res.rewards, "stardust") ~= nil).toBe(true)
			setBest(h, p, 9)
			res = fight(h, p)
			expect(find(res.rewards, "stardust") ~= nil).toBe(true)
			expect(find(res.rewards, "gems")).toBeNil()
		end)

		it("pays gems at the floor 25 and 50 milestones", function()
			expect(find(Logic.Milestone(25), "gems").amount).toBe(Cfg.MilestoneGems[25])
			expect(find(Logic.Milestone(50), "gems").amount).toBe(Cfg.MilestoneGems[50])
			expect(find(Logic.Milestone(20), "gems")).toBeNil()
			expect(Logic.Milestone(7)).toBeNil()
			expect(Logic.NextMilestone(0)).toBe(5)
			expect(Logic.NextMilestone(5)).toBe(10)
			expect(Logic.RecordReward(20)[1].amount).toBe(Cfg.RecordGems)
			expect(Logic.RecordReward(15)).toBeNil()
		end)
	end)

	describe("TrialTower enemies", function()
		it("puts a lone boss on every 10th floor and fights it as a boss", function()
			local week = Boards.Week(START)
			for _, floor in { 10, 20, 30, 40 } do
				expect(Logic.IsBoss(floor)).toBe(true)
				local enemies = Logic.Enemies(week, floor)
				expect(#enemies).toBe(1)
				expect(enemies[1].boss).toBe(true)
				expect(Logic.Preview(week, floor).boss).toBe(true)
			end
			for _, floor in { 1, 9, 11, 25 } do
				expect(Logic.IsBoss(floor)).toBe(false)
				local enemies = Logic.Enemies(week, floor)
				expect(#enemies).toBe(Config.Regions.WaveSize)
				expect(enemies[1].boss).toBe(false)
			end
			expect(Logic.Region(1)).toBe(Config.Regions.List[1].id)
			expect(Logic.Region(11)).toBe(Config.Regions.List[2].id)
			expect(Logic.Region(9999)).toBe(Config.Regions.List[#Config.Regions.List].id)
			-- Enemy power grows with the floor.
			expect(Logic.Power(20) > Logic.Power(10)).toBe(true)
		end)

		it("shows everyone the same enemies in a week, and new ones next week", function()
			local h = boot()
			local a = climber(h, { userId = 101 })
			local b = climber(h, { userId = 202 })
			local ra = fight(h, a)
			local rb = fight(h, b)
			local function foes(replay)
				local out = {}
				for _, u in replay.units do
					if u.side == "enemy" then
						table.insert(out, { line = u.appearance.line, form = u.appearance.form, lv = u.lv, maxHp = u.maxHp })
					end
				end
				return out
			end
			expect(foes(ra.replay)).toEqual(foes(rb.replay))
			local week = Boards.Week(START)
			expect(Logic.Enemies(week, 3)).toEqual(Logic.Enemies(week, 3))
			local differs = false
			for floor = 1, 9 do
				local ok = pcall(function()
					expect(Logic.Preview(week, floor)).toEqual(Logic.Preview(week + 1, floor))
				end)
				differs = differs or not ok
			end
			expect(differs).toBe(true)
		end)
	end)

	describe("TrialTower sources and hooks", function()
		it("gives Retry tokens through Rewards (kind tower_retry) and every Bounty reward", function()
			local h = boot()
			local p = climber(h)
			h:System("Rewards"):Grant(p, { { kind = "tower_retry", amount = 2 } }, "test")
			expect(h:Section(p, "TrialTower").retries).toBe(2)
			local token = find(Config.Bounties.Reward, "tower_retry")
			expect(token ~= nil and token.amount == 1).toBe(true)
			h:System("Rewards"):Grant(p, Config.Bounties.Reward, Config.Bounties.Source, { silent = true })
			expect(h:Section(p, "TrialTower").retries).toBe(3)
			expect(h:System("TrialTower"):AddRetries(p, 1000)).toBe(Cfg.RetryCap)
		end)

		it("sells Retry tokens at the Travelling Merchant, two a visit", function()
			local M = Config.Merchant
			local offer = M.ById.tower_retry
			expect(offer.limit).toBe(2)
			expect(offer.unlock).toBe("trial_tower")
			local k = MerchantLogic.Visit(START)
			local at = nil
			for i = 0, 2000 do
				if MerchantLogic.Find(k + i, "tower_retry") then
					at = (k + i) * M.Cycle + M.Offset + 60
					break
				end
			end
			expect(at ~= nil).toBe(true)
			local slot = MerchantLogic.Find(MerchantLogic.Visit(at), "tower_retry")
			local h = boot({ at = at, extra = { "Merchant" } })
			local p = climber(h)
			h:System("Currency"):Add(p, "gems", 1000, "test")
			local pay = 1
			for i, way in slot.pay do
				if way.kind == "gems" then
					pay = i
				end
			end
			local res = h:Call(p, "Merchant.Buy", { offer = "tower_retry", pay = pay })
			expect(res.total).toBe(1)
			h:Call(p, "Merchant.Buy", { offer = "tower_retry", pay = pay })
			expect(h:Section(p, "TrialTower").retries).toBe(2)
			expect(h:Reject(p, "Merchant.Buy", { offer = "tower_retry", pay = pay })).toBe("You bought all of those this visit")

			-- Below the tower's level: refused.
			local h2 = boot({ at = at, extra = { "Merchant" } })
			local p2 = climber(h2, { level = 20 })
			h2:System("Currency"):Add(p2, "gems", 1000, "test")
			expect(h2:Reject(p2, "Merchant.Buy", { offer = "tower_retry", pay = pay })).toBe("Unlocks at Ranch Level 26")
		end)

		it("feeds the weekly Highest Floor board and clears it next week", function()
			local board = Boards.ById.tower
			expect(board ~= nil and board.period == "week" and board.format == "count").toBe(true)
			local h = boot()
			local p = climber(h)
			fight(h, p)
			fight(h, p)
			fight(h, p)
			expect((h:System("Leaderboards"):Value(p, "tower"))).toBe(3)
			jump(h, WEEK)
			expect((h:System("Leaderboards"):Value(p, "tower"))).toBe(0)
		end)

		it("has the tower_10 weekly goal counting floors cleared", function()
			local goal = Config.Weekly.ById.tower_10
			expect(goal.family).toBe("tower")
			expect(goal.unlock).toBe("trial_tower")
			expect(goal.topic).toBe("TowerFloorCleared")
			expect(goal.target).toBe(10)
			local h = boot()
			local p = climber(h)
			local s = h:Section(p, "Weekly")
			s.goals = { { id = "tower_10", progress = 0 } }
			fight(h, p)
			fight(h, p)
			expect(h:Section(p, "Weekly").goals[1].progress).toBe(2)
		end)
	end)
end
