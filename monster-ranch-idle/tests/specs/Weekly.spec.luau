--[[
	Weekly (update 3.8): weekly goals and their chest. The seeded, family-unique draw
	(Logic/Weekly), unlock filtering, progress from bus topics, chest claim rules, the rollover
	auto-pay with its Welcome Back line, and the Royal egg from Ranch Level 25.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local WeeklyLogic = t.Shared("Logic.Weekly")

	local W = Config.Weekly
	local DAY = 86400
	local WEEK = Config.Leaderboards.WeekSeconds

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Weekly" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(level: number?, userId: number?)
		local h = TestKernel.new({ systems = SYSTEMS })
		local p = h:Join(userId)
		levelTo(h, p, level or 5)
		return h, p
	end

	local function ids(goals)
		local list = {}
		for i, g in goals do
			list[i] = g.id
		end
		return list
	end

	-- A topic detail that passes the goal's filter.
	local function detailFor(def)
		local detail = table.clone(def.filter or {})
		if detail.minRarity then
			detail.rarity = detail.minRarity
			detail.minRarity = nil
		end
		return detail
	end

	local function finish(h, p, index: number)
		local entry = h:Section(p, "Weekly").goals[index]
		local def = W.ById[entry.id]
		for _ = 1, def.target do
			h.kernel.Bus:Publish(def.topic, p, detailFor(def))
		end
		h:Step()
	end

	local function gems(h, p): number
		return h:Section(p, "Currency").gems
	end

	describe("Weekly draw", function()
		it("draws the same 5 goals for a player and week, never two of one family", function()
			local function all()
				return true
			end
			local changed = false
			for userId = 1, 60 do
				for week = 0, 3 do
					local a = WeeklyLogic.Pick(W.Pool, W.GoalCount, userId, week, all)
					local b = WeeklyLogic.Pick(W.Pool, W.GoalCount, userId, week, all)
					expect(#a).toBe(W.GoalCount)
					expect(ids(a)).toEqual(ids(b))
					local families = {}
					for _, def in a do
						expect(families[def.family]).toBeNil()
						families[def.family] = true
					end
					local other = WeeklyLogic.Pick(W.Pool, W.GoalCount, userId, week + 1, all)
					if table.concat(ids(other), ",") ~= table.concat(ids(a), ",") then
						changed = true
					end
				end
			end
			expect(changed).toBe(true)
			-- The pool has about 20 goals, each with a family and a reachable target.
			expect(#W.Pool).toBeAtLeast(18)
		end)

		it("draws the titan goal only in a week with a titan invasion", function()
			local titan = W.ById.titan_1
			expect(titan.during).toBe("titan")
			local first = Config.Titan.Schedule[1].startsAt
			local titanWeek = Config.Leaderboards.Week(first)
			expect(WeeklyLogic.Available(titan, titanWeek)).toBe(true)
			expect(WeeklyLogic.Available(titan, titanWeek - 1)).toBe(false)
			expect(WeeklyLogic.Available(titan, 1)).toBe(false) -- the week 3.8 ships: no invasion
			expect(WeeklyLogic.Available(W.ById.feed_60, 1)).toBe(true)
			-- A server at a week without an invasion never draws it, whoever the player is.
			for userId = 1, 80 do
				local h, p = boot(12, userId)
				for _, g in h:Section(p, "Weekly").goals do
					expect(g.id ~= "titan_1").toBe(true)
				end
			end
		end)

		it("gives a player the same goals on two servers in one week", function()
			local h1, p1 = boot(12, 4242)
			local h2, p2 = boot(12, 4242)
			local a = ids(h1:Section(p1, "Weekly").goals)
			expect(#a).toBe(W.GoalCount)
			expect(a).toEqual(ids(h2:Section(p2, "Weekly").goals))
			expect(h1:Section(p1, "Weekly").week).toBe(Config.Leaderboards.Week(h1.adapters.Clock.Now()))
		end)

		it("opens at Ranch Level 5 and draws only from features unlocked at the draw", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			levelTo(h, p, 4)
			expect(#h:Section(p, "Weekly").goals).toBe(0)
			expect(h:Reject(p, "Weekly.Claim", { step = 1 })).toContain("Ranch Level 5")
			levelTo(h, p, 5)
			local goals = h:Section(p, "Weekly").goals
			expect(#goals).toBe(W.GoalCount)
			for _, g in goals do
				local def = W.ById[g.id]
				expect(def.unlock == nil or Config.Unlocks.Features[def.unlock] <= 5).toBe(true)
			end
			-- Unlocking more later in the week keeps the draw fixed.
			local before = ids(goals)
			levelTo(h, p, 40)
			h:Advance(31)
			expect(ids(h:Section(p, "Weekly").goals)).toEqual(before)
			expect(h:Client(p).profile.Weekly.goals[1].id).toBe(before[1])

			-- The pure rule: a locked feature never comes up.
			for userId = 1, 40 do
				for _, def in
					WeeklyLogic.Pick(W.Pool, W.GoalCount, userId, 7, function(d)
						return d.unlock == nil
					end)
				do
					expect(def.unlock).toBeNil()
				end
			end
		end)
	end)

	describe("Weekly progress", function()
		it("counts goals from bus topics, respects filters and stops at the target", function()
			local h, p = boot(25)
			local s = h:Section(p, "Weekly")
			s.goals = { { id = "hatch_rare_3", progress = 0 }, { id = "arena_wins_5", progress = 0 }, { id = "feed_60", progress = 0 } }
			local Bus = h.kernel.Bus
			Bus:Publish("EggHatched", p, { id = "e1", egg = "meadow", rarity = 1, variant = 0 })
			Bus:Publish("EggHatched", p, { id = "e2", egg = "crystal", rarity = 4, variant = 0 })
			Bus:Publish("ArenaBattle", p, { won = false, rating = 1000 })
			Bus:Publish("ArenaBattle", p, { won = true, rating = 1010 })
			for _ = 1, 70 do
				Bus:Publish("MonsterFed", p, { id = "m1", flavor = "sweet" })
			end
			h:Step()
			expect(s.goals[1].progress).toBe(1)
			expect(s.goals[2].progress).toBe(1)
			expect(s.goals[3].progress).toBe(60)
			expect(WeeklyLogic.Done(s)).toBe(1)
			h:Advance(1)
			expect(h:Client(p).profile.Weekly.goals[3].progress).toBe(60)
		end)
	end)

	describe("Weekly chest", function()
		it("claims a step once it is reached, and only once", function()
			local h, p = boot(10)
			expect(h:Reject(p, "Weekly.Claim", { step = 1 })).toContain("Finish 1 of your weekly goals first")
			finish(h, p, 1)
			local g = gems(h, p)
			local res = h:Call(p, "Weekly.Claim", { step = 1 })
			expect(gems(h, p)).toBe(g + 15)
			expect(#res.rewards).toBe(2)
			expect(h:Section(p, "Weekly").claimed[1]).toBe(true)
			expect(h:Reject(p, "Weekly.Claim", { step = 1 })).toContain("Already claimed")
			expect(h:Reject(p, "Weekly.Claim", { step = 2 })).toContain("Finish 3 of your weekly goals first")
			expect(h:Invoke(p, "Weekly.Claim", { step = 4 }).ok).toBe(false)
			finish(h, p, 2)
			finish(h, p, 3)
			h:Advance(1)
			local food = 0
			local res2 = h:Call(p, "Weekly.Claim", { step = 2 })
			for _, item in res2.rewards do
				if item.kind == "food" then
					food += item.amount
					expect(table.find(Config.Food.Ids, item.id) ~= nil).toBe(true)
				end
			end
			expect(food).toBe(10)
			-- The last step pays a Crystal egg below Ranch Level 25.
			finish(h, p, 4)
			finish(h, p, 5)
			h:Advance(1)
			local egg
			for _, item in h:Call(p, "Weekly.Claim", { step = 3 }).rewards do
				if item.kind == "egg" then
					egg = item.id
				end
			end
			expect(egg).toBe("crystal")
		end)

		it("pays a Royal egg instead from Ranch Level 25", function()
			expect(WeeklyLogic.ChestReward(3, 24)[3].id).toBe("crystal")
			expect(WeeklyLogic.ChestReward(3, 25)[3].id).toBe("royal")
			expect(W.Chest[3].reward[3].id).toBe("crystal") -- the config is never changed
			local h, p = boot(25)
			for i = 1, W.GoalCount do
				finish(h, p, i)
			end
			h:Call(p, "Weekly.Claim", { step = 1 })
			h:Advance(1)
			h:Call(p, "Weekly.Claim", { step = 2 })
			h:Advance(1)
			local res = h:Call(p, "Weekly.Claim", { step = 3 })
			expect(res.rewards[3].kind).toBe("egg")
			expect(res.rewards[3].id).toBe("royal")
		end)

		it("pays unclaimed steps automatically at rollover and says so on the way back", function()
			local h, p = boot(10)
			for i = 1, 3 do
				finish(h, p, i)
			end
			h:Call(p, "Weekly.Claim", { step = 1 })
			local welcome = {}
			h.kernel.Bus:Subscribe("WelcomeItem", function(_, detail)
				table.insert(welcome, detail)
			end)
			local g = gems(h, p)
			local oldWeek = h:Section(p, "Weekly").week
			local p2 = h:Rejoin(p, 8 * DAY)
			local s = h:Section(p2, "Weekly")
			expect(gems(h, p2)).toBe(g + 40) -- step 2 only: step 1 was claimed, step 3 not reached
			expect(s.week).toBe(oldWeek + 1)
			expect(s.claimed).toEqual({ false, false, false })
			expect(#s.goals).toBe(W.GoalCount)
			for _, entry in s.goals do
				expect(entry.progress).toBe(0)
			end
			local said = false
			for _, item in welcome do
				if item.kind == "weekly" then
					said = true
					expect(item.text).toBe("Your weekly chest paid out")
				end
			end
			expect(said).toBe(true)
			-- Nothing owed, nothing said.
			table.clear(welcome)
			local p3 = h:Rejoin(p2, WEEK)
			for _, item in welcome do
				expect(item.kind ~= "weekly").toBe(true)
			end
			expect(h:Section(p3, "Weekly").week).toBe(oldWeek + 2)
		end)

		it("rolls over mid-session on the periodic check", function()
			local h, p = boot(10)
			finish(h, p, 1)
			local g = gems(h, p)
			local week = h:Section(p, "Weekly").week
			h.adapters.advance(Config.Leaderboards.WeekEndsAt(week) - h.adapters.Clock.Now() + 1)
			h:Advance(31)
			expect(h:Section(p, "Weekly").week).toBe(week + 1)
			expect(gems(h, p)).toBe(g + 15)
			expect(h:LastEvent(p, "Rewards.Granted") ~= nil).toBe(true)
		end)
	end)
end
