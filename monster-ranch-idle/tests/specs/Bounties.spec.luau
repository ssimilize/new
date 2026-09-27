--[[
	Bounties (update 3.9 · Family and fortune): Expedition Bounties. The weekly draw
	(Logic/Bounties), the wanted monster in the wave, paying once, the Luck-scaled egg, the
	BountyDefeated topic and the weekly goal, the week's rollover, the "bounties" leaderboard,
	the save migration, rebirth and the empty state.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Api = t.Shared("Kernel.Api")
	local BountyLogic = t.Shared("Logic.Bounties")
	local BattleSim = t.Shared("Logic.BattleSim")

	local Cfg = Config.Bounties
	local Regions = Config.Regions
	local WEEK = Config.Leaderboards.WeekSeconds

	local function all()
		return true
	end

	local function clearedFrom(map)
		return function(regionId)
			return map[regionId] or 0
		end
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions" }

	local function boot(extra: { string }?)
		local eggs = {}
		local stubs = {
			Eggs = {
				Add = function(_, player, eggType, source, amount)
					table.insert(eggs, { userId = player.UserId, egg = eggType, source = source, amount = amount or 1 })
					return {}
				end,
			},
		}
		local systems = table.clone(SYSTEMS)
		for _, name in extra or {} do
			table.insert(systems, name)
		end
		local h = TestKernel.new({ systems = systems, stubs = stubs })
		local topics = { BountyDefeated = {} }
		h.kernel.Bus:Subscribe("BountyDefeated", function(player, detail)
			table.insert(topics.BountyDefeated, { player = player, detail = detail })
		end)
		return h, eggs, topics
	end

	-- A squad strong enough to win any early stage (or a lone baby that loses them all).
	local function squad(h, p, strong: boolean)
		local M = h:System("Monsters")
		local ids = {}
		for i = 1, if strong then 3 else 1 do
			local m = M:Create(p, {
				line = ({ "cindlet", "bubblin", "mossbun" })[i],
				rarity = if strong then 5 else 1,
				stage = if strong then 3 else 1,
				traits = { 3, 4 },
				hidden = 5,
			}, "test", true)
			m.lv = if strong then 60 else 1
			table.insert(ids, m.id)
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return ids
	end

	-- A level 6 player with `cleared` progress and this week's draw made.
	local function hunter(h, cleared)
		local p = h:Join()
		local s = h:Section(p, "Expeditions")
		for regionId, stage in cleared do
			s.cleared[regionId] = stage
		end
		levelTo(h, p, 6)
		return p, h:System("Expeditions"):Bounties(p)
	end

	local function gems(h, p)
		return h:Section(p, "Currency").gems
	end

	describe("Bounty draw", function()
		it("is deterministic for a player and week, and changes with the week", function()
			local cleared = clearedFrom({ meadow = 20, coral = 18, ember = 9 })
			local a = BountyLogic.Draw(4242, 7, all, cleared)
			local b = BountyLogic.Draw(4242, 7, all, cleared)
			expect(#a).toBe(Cfg.Count)
			for i = 1, #a do
				for _, key in { "region", "stage", "name", "line", "seed", "done" } do
					expect(a[i][key]).toBe(b[i][key])
				end
			end
			local differs = false
			for week = 8, 12 do
				local c = BountyLogic.Draw(4242, week, all, cleared)
				for i = 1, #a do
					if c[i].region ~= a[i].region or c[i].stage ~= a[i].stage or c[i].name ~= a[i].name then
						differs = true
					end
				end
			end
			expect(differs).toBe(true)
		end)

		it("only uses cleared non-boss stages in the last Window, in distinct regions first", function()
			for userId = 1, 60 do
				local map = { meadow = 20, coral = 30, ember = 4 }
				local list = BountyLogic.Draw(userId, 3, all, clearedFrom(map))
				expect(#list).toBe(3)
				local regions = {}
				for _, b in list do
					local c = map[b.region]
					expect(b.stage <= c).toBe(true)
					expect(b.stage >= math.max(1, c - Cfg.Window + 1)).toBe(true)
					expect(BattleSim.IsBossStage(b.region, b.stage)).toBe(false)
					expect(b.done).toBe(false)
					expect(table.find(Regions.Band(b.region, b.stage).enemyLines, b.line) ~= nil).toBe(true)
					expect(type(b.name) == "string" and string.find(b.name, " the ", 1, true) ~= nil).toBe(true)
					regions[b.region] = true
				end
				expect(regions.meadow and regions.coral and regions.ember).toBe(true)
			end
		end)

		it("skips regions that aren't eligible or have nothing cleared, and draws fewer when it must", function()
			local only = function(region)
				return region.id == "coral"
			end
			local list = BountyLogic.Draw(9, 1, only, clearedFrom({ meadow = 20, coral = 12 }))
			expect(#list).toBe(3)
			local stages = {}
			for _, b in list do
				expect(b.region).toBe("coral")
				expect(stages[b.stage]).toBe(nil) -- one region: three different stages
				stages[b.stage] = true
			end
			expect(#BountyLogic.Draw(9, 1, all, clearedFrom({ meadow = 1 }))).toBe(1)
			expect(#BountyLogic.Draw(9, 1, all, clearedFrom({}))).toBe(0)
			expect(#BountyLogic.Stages("meadow", 10)).toBe(9) -- stage 10 is a boss
			expect(#BountyLogic.Stages("meadow", 0)).toBe(0)
		end)

		it("draws on the server from unlocked, open regions only, and not before Level 6", function()
			local h = boot()
			local p = h:Join()
			local s = h:Section(p, "Expeditions")
			s.cleared.meadow = 8
			s.cleared.dunes = 8 -- a region that isn't open yet (and is locked)
			levelTo(h, p, 5)
			expect(#h:System("Expeditions"):Bounties(p)).toBe(0)
			levelTo(h, p, 6)
			local list = h:Section(p, "Expeditions").bounty.list
			expect(#list).toBe(3)
			for _, b in list do
				expect(b.region).toBe("meadow")
			end
			expect(h:Section(p, "Expeditions").bounty.week).toBe(Config.Leaderboards.Week(h.adapters.Clock.Now()))
			expect(#h:Client(p).profile.Expeditions.bounty.list).toBe(3)
		end)

		it("shows nothing until a first clear, then draws on that clear", function()
			local h = boot()
			local p, list = hunter(h, {})
			expect(#list).toBe(0)
			squad(h, p, true)
			h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 1 })
			local after = h:Section(p, "Expeditions").bounty.list
			expect(#after).toBe(1)
			expect(after[1].region).toBe("meadow")
			expect(after[1].stage).toBe(1)
			-- Fixed for the week: more clears don't redraw a list that isn't empty.
			h:Section(p, "Expeditions").cleared.coral = 9
			h:Advance(1)
			h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 2 })
			expect(#h:Section(p, "Expeditions").bounty.list).toBe(1)
		end)
	end)

	describe("The bounty fight", function()
		it("puts the wanted monster in the wave of its stage only", function()
			local b = { region = "meadow", stage = 7, name = "Grumbletooth the Fierce", line = "pebblet", seed = 99, done = false }
			local wave = BattleSim.BuildEnemies("meadow", 7, 1234)
			local withBounty = BountyLogic.Inject(wave, b, "meadow", 7)
			expect(#withBounty).toBe(#wave)
			local m = withBounty[1]
			expect(m.bounty).toBe(true)
			expect(m.boss).toBe(false)
			expect(m.statMult).toBe(Cfg.StatMult)
			expect(m.name).toBe("Grumbletooth the Fierce")
			expect(m.line).toBe("pebblet")
			expect(m.look.aura).toBe(Cfg.Aura)
			expect(t.Shared("Config.Vfx").Mastery[Cfg.Aura] ~= nil).toBe(true)
			local level = BattleSim.StageScaling("meadow", 7)
			expect(m.lv).toBe(level)
			for i = 2, #wave do
				expect(withBounty[i]).toBe(wave[i])
			end
			expect(BountyLogic.Inject(wave, b, "meadow", 8)).toBe(wave)
			expect(BountyLogic.Inject(wave, b, "coral", 7)).toBe(wave)
			b.done = true
			expect(BountyLogic.Inject(wave, b, "meadow", 7)).toBe(wave)
			expect(BountyLogic.Inject(wave, nil, "meadow", 7)).toBe(wave)

			b.done = false
			local ally = BattleSim.EnemyRecord("cindlet", 30, 3, nil)
			local replay = BattleSim.Simulate({ ally }, withBounty, 5)
			local flagged = 0
			for _, u in replay.units do
				if u.bounty then
					flagged += 1
					expect(u.name).toBe("Grumbletooth the Fierce")
					expect(u.appearance.aura).toBe(Cfg.Aura)
				end
			end
			expect(flagged).toBe(1)
		end)

		it("pays a won bounty once, publishes BountyDefeated and replays like a normal stage", function()
			local h, _, topics = boot()
			local p, list = hunter(h, { meadow = 12 })
			local ids = squad(h, p, true)
			local b = list[1]
			local expected = BountyLogic.Rewards(table.clone(b), h:System("Expeditions"):LootBonus(p, ids))
			local before = gems(h, p)
			local res = h:Call(p, "Expeditions.Fight", { region = b.region, stage = b.stage })
			expect(res.win).toBe(true)
			expect(res.bounty).toBe(b.name)
			local flagged = 0
			for _, u in res.replay.units do
				if u.bounty then
					flagged += 1
				end
			end
			expect(flagged).toBe(1)
			local section = h:Section(p, "Expeditions").bounty
			expect(section.list[1].done).toBe(true)
			expect(section.count).toBe(1)
			expect(gems(h, p) - before).toBe(20)
			expect(#res.rewards).toBe(#expected) -- a replayed stage pays nothing else
			expect(#topics.BountyDefeated).toBe(1)
			expect(topics.BountyDefeated[1].detail.region).toBe(b.region)
			expect(topics.BountyDefeated[1].detail.stage).toBe(b.stage)
			expect(h:Client(p).profile.Expeditions.bounty.count).toBe(1)

			h:Advance(1)
			local mid = gems(h, p)
			local again = h:Call(p, "Expeditions.Fight", { region = b.region, stage = b.stage })
			expect(again.win).toBe(true)
			expect(again.bounty).toBe(nil)
			expect(#again.rewards).toBe(0)
			for _, u in again.replay.units do
				expect(u.bounty).toBe(nil)
			end
			expect(gems(h, p)).toBe(mid)
			expect(section.count).toBe(1)
			expect(#topics.BountyDefeated).toBe(1)
		end)

		it("changes nothing when the squad loses", function()
			local h, _, topics = boot()
			local p, list = hunter(h, { meadow = 15 })
			squad(h, p, false)
			local b = list[1]
			local res = h:Call(p, "Expeditions.Fight", { region = b.region, stage = b.stage })
			expect(res.win).toBe(false)
			expect(h:Section(p, "Expeditions").bounty.list[1].done).toBe(false)
			expect(h:Section(p, "Expeditions").bounty.count).toBe(0)
			expect(#topics.BountyDefeated).toBe(0)
		end)

		it("rolls the region's first egg with a Luck-scaled chance from the bounty's seed", function()
			expect(BountyLogic.EggChance(0)).toBe(0.25)
			expect(BountyLogic.EggChance(0.5)).toBe(0.375)
			expect(BountyLogic.EggChance(1)).toBe(0.5)
			expect(BountyLogic.EggChance(3)).toBe(Cfg.EggChanceMax)
			expect(BountyLogic.Egg("meadow")).toBe(Regions.ById.meadow.eggs[1].egg)
			expect(BountyLogic.Egg("coral")).toBe("grove")

			local hitsLow, hitsHigh, n = 0, 0, 4000
			for seed = 1, n do
				local b = { region = "meadow", stage = 3, seed = seed * 7919 }
				local low = BountyLogic.RollEgg(b, 0)
				expect(BountyLogic.RollEgg(b, 0)).toBe(low)
				local high = BountyLogic.RollEgg(b, 1)
				if low then
					hitsLow += 1
					expect(high).toBe(true) -- more Luck never loses an egg the bounty would drop
				end
				if high then
					hitsHigh += 1
				end
			end
			expect(math.abs(hitsLow / n - 0.25) < 0.03).toBe(true)
			expect(math.abs(hitsHigh / n - 0.5) < 0.03).toBe(true)

			local rewards = BountyLogic.Rewards({ region = "coral", stage = 3, seed = 1 }, 5)
			expect(rewards[1].kind).toBe("coins")
			expect(rewards[1].seconds).toBe(1800)
			expect(rewards[2].kind).toBe("gems")
			expect(rewards[2].amount).toBe(20)
		end)

		it("grants the rolled egg on the server", function()
			local h, eggs = boot()
			for _ = 1, 12 do
				local p, list = hunter(h, { meadow = 12 })
				local ids = squad(h, p, true)
				local b = list[1]
				local bonus = h:System("Expeditions"):LootBonus(p, ids)
				local want = BountyLogic.RollEgg(b, bonus)
				local before = #eggs
				h:Call(p, "Expeditions.Fight", { region = b.region, stage = b.stage })
				expect(#eggs - before).toBe(if want then 1 else 0)
				if want then
					expect(eggs[#eggs].egg).toBe(BountyLogic.Egg(b.region))
					expect(eggs[#eggs].source).toBe("bounty")
				end
			end
		end)
	end)

	describe("Bounty weeks", function()
		it("rolls over to a new draw and count next week, online or on rejoin", function()
			local h = boot({ "Leaderboards" })
			local p, list = hunter(h, { meadow = 14, coral = 9 })
			squad(h, p, true)
			local first = list[1]
			h:Call(p, "Expeditions.Fight", { region = first.region, stage = first.stage })
			expect(h:System("Expeditions"):BountyCount(p)).toBe(1)
			expect((h:System("Leaderboards"):Value(p, "bounties"))).toBe(1)
			local week = h:Section(p, "Expeditions").bounty.week

			-- Past the reset the old count no longer counts, even before the sweep runs.
			h.adapters.advance(WEEK)
			expect(h:System("Expeditions"):BountyCount(p)).toBe(0)
			expect((h:System("Leaderboards"):Value(p, "bounties"))).toBe(0)
			h:Advance(31)
			local b = h:Section(p, "Expeditions").bounty
			expect(b.week).toBe(week + 1)
			expect(b.count).toBe(0)
			expect(#b.list).toBe(3)
			for _, entry in b.list do
				expect(entry.done).toBe(false)
			end

			local p2 = h:Rejoin(p, WEEK)
			local b2 = h:Section(p2, "Expeditions").bounty
			expect(b2.week).toBe(week + 2)
			expect(#b2.list).toBe(3)
		end)

		it("counts on the Bounty Hunter board and the weekly goal", function()
			local board = Config.Leaderboards.ById.bounties
			expect(board ~= nil and board.period == "week").toBe(true)
			expect(board.name).toBe("Bounty Hunter")
			expect(table.find(Config.Leaderboards.Weekly, board) ~= nil).toBe(true)
			local goal = Config.Weekly.ById.bounty_3
			expect(goal.topic).toBe("BountyDefeated")
			expect(goal.unlock).toBe("bounties")
			expect(Api.Topics.BountyDefeated ~= nil).toBe(true)
			expect(Config.Unlocks.Features.bounties).toBe(6)

			local h = boot({ "Weekly" })
			local p, list = hunter(h, { meadow = 12 })
			squad(h, p, true)
			local weekly = h:Section(p, "Weekly")
			weekly.goals[1] = { id = "bounty_3", progress = 0 }
			h:Call(p, "Expeditions.Fight", { region = list[1].region, stage = list[1].stage })
			expect(weekly.goals[1].progress).toBe(1)
		end)

		it("keeps the week's bounties through a rebirth", function()
			local h = boot()
			local p, list = hunter(h, { meadow = 18 })
			local before = table.clone(list)
			expect(h:System("Expeditions"):ResetForRebirth(p)).toBe(true)
			expect(h:System("Expeditions"):Cleared(p, "meadow")).toBe(0)
			h:Advance(31)
			local after = h:Section(p, "Expeditions").bounty.list
			expect(#after).toBe(#before)
			for i, b in before do
				expect(after[i]).toBe(b)
			end
			-- Out of reach until the stage is cleared again.
			squad(h, p, true)
			local far = nil
			for _, b in after do
				if b.stage > 1 then
					far = b
				end
			end
			if far then
				expect(h:Reject(p, "Expeditions.Fight", { region = far.region, stage = far.stage })).toBe(
					string.format("Clear stage %d first", 1)
				)
			end
		end)

		it("migrates a version 1 save to an empty bounty section", function()
			local h = boot()
			local profile = h:System("Expeditions").Profile
			expect(profile.Version).toBe(2)
			local old = { cleared = { meadow = 5 }, slots = {}, squad = {} }
			local migrated = profile.Migrate(old, 1)
			expect(migrated.cleared.meadow).toBe(5)
			expect(migrated.bounty.week).toBe(0)
			expect(#migrated.bounty.list).toBe(0)
			expect(migrated.bounty.count).toBe(0)
			expect(profile.Default().bounty.count).toBe(0)
		end)
	end)
end
