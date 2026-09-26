-- S6 Quests: tutorial state machine, dailies, achievements, codes and the Ranch Pass.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Q = Config.Quests
	local Objectives = t.Server("Systems.Quests.Objectives")

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Monetization", "Quests" }

	local function weatherStub(startId: string?)
		local log = { current = startId or "clear", triggered = {}, guaranteed = {} }
		local api = {
			Current = function(_self)
				return { id = log.current, endsAt = 0 }
			end,
			Trigger = function(_self, id, source, seconds)
				table.insert(log.triggered, { id = id, source = source, seconds = seconds })
				log.current = id
			end,
			GuaranteeMutation = function(_self, player, mutation)
				table.insert(log.guaranteed, { player = player, mutation = mutation })
				return true
			end,
		}
		return api, log
	end

	local function boot(options: { startTime: number?, weather: any? }?)
		local opts = options or {}
		local stubs = {}
		if opts.weather then
			stubs.Weather = opts.weather
		end
		return TestKernel.new({ systems = SYSTEMS, stubs = stubs, startTime = opts.startTime })
	end

	local function publish(h, topic: string, player, detail, times: number?)
		for _ = 1, times or 1 do
			h.kernel.Bus:Publish(topic, player, detail or {})
		end
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function tutorial(h, p)
		return h:Section(p, "Quests").tutorial
	end

	describe("Quests objectives (pure)", function()
		it("matches exact keys, minRarity and hybrid", function()
			expect(Objectives.Matches(nil, {})).toBe(true)
			expect(Objectives.Matches({ stage = 2 }, { stage = 2, region = "meadow" })).toBe(true)
			expect(Objectives.Matches({ stage = 2 }, { stage = 1 })).toBe(false)
			expect(Objectives.Matches({ minRarity = 4 }, { rarity = 4 })).toBe(true)
			expect(Objectives.Matches({ minRarity = 4 }, { rarity = 3 })).toBe(false)
			expect(Objectives.Matches({ minRarity = 4 }, {})).toBe(false)
			expect(Objectives.Matches({ hybrid = true }, { hybrid = false })).toBe(false)
			expect(Objectives.Matches({ hybrid = true }, { hybrid = true })).toBe(true)
			expect(Objectives.Amount(Q.CountField, "EggBought", { amount = 3 })).toBe(3)
			expect(Objectives.Amount(Q.CountField, "EggHatched", { amount = 3 })).toBe(1)
			expect(Objectives.Amount(Q.CountField, "EggBought", {})).toBe(0)
		end)
	end)

	describe("Quests tutorial", function()
		it("runs the whole first session from bus topics", function()
			local weather, wlog = weatherStub("clear")
			local h = boot({ weather = weather })
			local p = h:Join()
			local function stepId()
				local step = Q.Tutorial[tutorial(h, p).step]
				return step and step.id
			end
			expect(stepId()).toBe("hatch_starter")

			publish(h, "JarCollected", p, { coins = 25 }) -- not the current step's topic
			expect(stepId()).toBe("hatch_starter")
			publish(h, "EggHatched", p, { id = "m1", egg = "starter", rarity = 2, variant = 0 })
			expect(stepId()).toBe("collect_first")
			publish(h, "JarCollected", p, { coins = 25 })
			expect(h:Section(p, "Currency").coins).toBe(300)
			local done = h:LastEvent(p, "Quests.StepDone").payload
			expect(done.step).toBe("collect_first")
			expect(done.rewards[1].amount).toBe(300)

			publish(h, "EggBought", p, { type = "meadow", amount = 2 }) -- counts the amount
			expect(stepId()).toBe("hatch_two")
			publish(h, "EggHatched", p, { id = "m2", egg = "meadow", rarity = 1, variant = 0 })
			expect(tutorial(h, p).progress).toBe(1)
			expect(h:Client(p).profile.Quests.tutorial.progress).toBe(1)
			publish(h, "EggHatched", p, { id = "m3", egg = "meadow", rarity = 1, variant = 0 })
			expect(stepId()).toBe("feed_starter")
			publish(h, "MonsterFed", p, { id = "m1", flavor = "sweet" }, 3)
			expect(stepId()).toBe("grow_starter")
			expect(h:Section(p, "Currency").food.sweet).toBe(5)
			publish(h, "MonsterEvolved", p, { id = "m1", stage = 2, form = "kindlefox" })
			publish(h, "StageCleared", p, { region = "meadow", stage = 1, first = true })
			expect(stepId()).toBe("clear_stage_2")
			publish(h, "StageCleared", p, { region = "meadow", stage = 1, first = false }) -- filter: stage 2
			expect(stepId()).toBe("clear_stage_2")
			publish(h, "StageCleared", p, { region = "meadow", stage = 2, first = true })
			expect(stepId()).toBe("start_expedition")
			expect(#wlog.triggered).toBe(0)
			publish(h, "ExpeditionStarted", p, { slot = 1, duration = 900 })

			-- The rain step starts the scripted rain and guarantees Soaked.
			expect(stepId()).toBe("weather_intro")
			expect(#wlog.triggered).toBe(1)
			expect(wlog.triggered[1].id).toBe("rain")
			expect(wlog.triggered[1].source).toBe("tutorial")
			expect(wlog.triggered[1].seconds).toBe(90)
			expect(wlog.guaranteed[1].mutation).toBe("soaked")
			expect(wlog.guaranteed[1].player).toBe(p)

			expect(h:Reject(p, "Quests.Ack", { step = "done" })).toContain("isn't active")
			h:Call(p, "Quests.Ack", { step = "weather_intro" })
			h:Call(p, "Quests.Ack", { step = "done" })
			expect(stepId()).toBeNil()
			expect(h:Section(p, "Currency").gems).toBe(50)
			expect(h:System("Quests"):TutorialDone(p)).toBe(true)
			h:Advance(1)
			expect(h:Reject(p, "Quests.Ack", { step = "done" })).toContain("already done")

			local funnel = {}
			for _, e in h.adapters.log.analytics do
				if e.kind == "onboarding" then
					table.insert(funnel, e)
				end
			end
			expect(#funnel).toBe(#Q.Tutorial)
			for i, e in funnel do
				expect(e.step).toBe(i)
				expect(e.name).toBe(Q.Tutorial[i].id)
			end
		end)

		it("refuses to ack a step that completes on a topic", function()
			local h = boot()
			local p = h:Join()
			expect(h:Reject(p, "Quests.Ack", { step = "hatch_starter" })).toContain("Finish this step first")
		end)

		it("does not force rain over other weather, and survives a missing Weather system", function()
			local weather, wlog = weatherStub("heatwave")
			local h = boot({ weather = weather })
			local p = h:Join()
			tutorial(h, p).step = 9 -- start_expedition
			publish(h, "ExpeditionStarted", p, { slot = 1, duration = 900 })
			expect(#wlog.triggered).toBe(0)
			expect(#wlog.guaranteed).toBe(1)

			local h2 = boot()
			local p2 = h2:Join()
			tutorial(h2, p2).step = 9
			publish(h2, "ExpeditionStarted", p2, { slot = 1, duration = 900 })
			expect(Q.Tutorial[tutorial(h2, p2).step].id).toBe("weather_intro")
		end)

		it("skips the scripted rain when the flag is off", function()
			local weather, wlog = weatherStub("clear")
			local h = boot({ weather = weather })
			local p = h:Join()
			Config.Flags.TutorialScriptedRain = false
			local ok, err = pcall(function()
				tutorial(h, p).step = 9
				publish(h, "ExpeditionStarted", p, { slot = 1, duration = 900 })
			end)
			Config.Flags.TutorialScriptedRain = true
			assert(ok, err)
			expect(#wlog.triggered).toBe(0)
			expect(#wlog.guaranteed).toBe(0)
		end)
	end)

	describe("Quests dailies", function()
		local function dailyIds(h, p)
			local ids = {}
			for i, entry in h:Section(p, "Quests").daily.list do
				ids[i] = entry.id
			end
			return ids
		end

		it("stay locked until Ranch Level 5, then roll on level-up", function()
			local h = boot()
			local p = h:Join()
			expect(#h:Section(p, "Quests").daily.list).toBe(0)
			expect(h:Reject(p, "Quests.ClaimDaily", { index = 1 })).toBe("Unlocks at Ranch Level 5")
			levelTo(h, p, 5)
			expect(#h:Section(p, "Quests").daily.list).toBe(Q.DailyCount)
			expect(#h:Client(p).profile.Quests.daily.list).toBe(Q.DailyCount)
		end)

		it("are deterministic per (userId, day) and skip locked entries", function()
			-- Kernels boot one at a time: system modules are shared, so the newest kernel wins.
			local h1 = boot()
			local a = h1:Join(7001)
			levelTo(h1, a, 5)
			local first = dailyIds(h1, a)
			local h2 = boot()
			local b = h2:Join(7001)
			levelTo(h2, b, 5)
			expect(dailyIds(h2, b)).toEqual(first)
			local other = h2:Join(7002)
			levelTo(h2, other, 5)
			expect(#dailyIds(h2, other)).toBe(Q.DailyCount)

			local sawBreed = false
			for uid = 7100, 7140 do
				local p = h2:Join(uid)
				levelTo(h2, p, 5)
				for _, id in dailyIds(h2, p) do
					expect(id == "breed_1").toBe(false) -- breeding unlocks at 12
				end
				levelTo(h2, p, 12)
				h2:Section(p, "Quests").daily.day = 0 -- force a re-roll with breeding unlocked
				h2.kernel.Bus:Publish("LevelUp", p, { level = 12 })
				for _, id in dailyIds(h2, p) do
					sawBreed = sawBreed or id == "breed_1"
				end
			end
			expect(sawBreed).toBe(true)
		end)

		it("progress on topics, claim once, and reset the next UTC day", function()
			local h = boot()
			local p = h:Join(7200)
			levelTo(h, p, 5)
			local list = h:Section(p, "Quests").daily.list
			local index, def
			for i, entry in list do
				for _, d in Q.DailyPool do
					if d.id == entry.id and not d.filter then
						index, def = i, d
					end
				end
			end
			assert(index, "expected a daily without a filter")
			expect(h:Reject(p, "Quests.ClaimDaily", { index = index })).toContain("Finish the quest first")
			local detail = if def.topic == "EggBought" then { type = "meadow", amount = 1 } else {}
			publish(h, def.topic, p, detail, def.target + 3)
			expect(list[index].progress).toBe(def.target)
			local gemsBefore = h:Section(p, "Currency").gems
			local data = h:Call(p, "Quests.ClaimDaily", { index = index })
			expect(#data.rewards).toBeGreaterThan(0)
			expect(h:Section(p, "Currency").gems).toBeGreaterThan(gemsBefore - 1)
			expect(list[index].claimed).toBe(true)
			expect(h:Reject(p, "Quests.ClaimDaily", { index = index })).toBe("Already claimed")
			expect(h:Reject(p, "Quests.ClaimDaily", { index = 5 })).toContain("no daily quest")

			local day = h:Section(p, "Quests").daily.day
			h:Advance(86400)
			local fresh = h:Section(p, "Quests").daily
			expect(fresh.day).toBe(day + 1)
			expect(#fresh.list).toBe(Q.DailyCount)
			for _, entry in fresh.list do
				expect(entry.progress).toBe(0)
				expect(entry.claimed).toBe(false)
			end
		end)
	end)

	describe("Quests achievements", function()
		it("progress with filters and claim once", function()
			local h = boot()
			local p = h:Join()
			local ach = h:Section(p, "Quests").achievements
			expect(ach.first_epic.progress).toBe(0) -- every achievement exists from the first join
			publish(h, "EggHatched", p, { id = "m1", egg = "meadow", rarity = 3, variant = 0 })
			expect(ach.first_epic.progress).toBe(0)
			expect(ach.hatch_100.progress).toBe(1)
			publish(h, "EggHatched", p, { id = "m2", egg = "crystal", rarity = 4, variant = 1 })
			expect(ach.first_epic.progress).toBe(1)
			expect(ach.first_golden.progress).toBe(1)
			expect(ach.first_legendary.progress).toBe(0)
			publish(h, "Bred", p, { id = "m3", hybrid = false, discovery = false })
			expect(ach.first_hybrid.progress).toBe(0)
			publish(h, "Bred", p, { id = "m4", hybrid = true, discovery = true })
			expect(ach.first_hybrid.progress).toBe(1)
			publish(h, "StageCleared", p, { region = "coral", stage = 20, first = true })
			publish(h, "StageCleared", p, { region = "meadow", stage = 19, first = true })
			expect(ach.clear_meadow.progress).toBe(0)
			expect(ach.clear_coral.progress).toBe(1)

			expect(h:Reject(p, "Quests.ClaimAchievement", { id = "first_legendary" })).toBe("Not finished yet")
			expect(h:Reject(p, "Quests.ClaimAchievement", { id = "nope" })).toContain("doesn't exist")
			local data = h:Call(p, "Quests.ClaimAchievement", { id = "first_epic" })
			expect(data.rewards[1].amount).toBe(25)
			expect(h:Section(p, "Currency").gems).toBe(25)
			h:Advance(2)
			expect(h:Reject(p, "Quests.ClaimAchievement", { id = "first_epic" })).toBe("Already claimed")
			expect(h:Client(p).profile.Quests.achievements.first_epic.claimed).toBe(true)
		end)
	end)

	describe("Quests codes", function()
		it("redeem case-insensitively once per account", function()
			local h = boot()
			local p = h:Join()
			local data = h:Call(p, "Quests.Redeem", { code = "  ranch " })
			expect(data.rewards[1].amount).toBe(50)
			expect(h:Section(p, "Quests").codes.RANCH).toBe(true)
			expect(h:Reject(p, "Quests.Redeem", { code = "RANCH" })).toBe("You already used that code")
			h:Advance(2)
			expect(h:Reject(p, "Quests.Redeem", { code = "nothing" })).toBe("That code doesn't exist")
			local p2 = h:Rejoin(p, 10)
			h:Advance(2)
			expect(h:Reject(p2, "Quests.Redeem", { code = "Ranch" })).toBe("You already used that code")
			expect(h:Section(p2, "Currency").gems).toBe(50)
		end)

		it("expire", function()
			local h = boot()
			local p = h:Join()
			expect(h:Call(p, "Quests.Redeem", { code = "frostfall" }).rewards[1].id).toBe("frostfall")
			expect(h:Section(p, "Currency").tokens.frostfall).toBe(100)
			h.adapters.setTime(Q.Codes.FROSTFALL.expires)
			local late = h:Join()
			expect(h:Reject(late, "Quests.Redeem", { code = "FROSTFALL" })).toBe("That code has expired")
		end)

		it("require the group when asked", function()
			-- GROUP itself became the group reward row (Community.spec); any code can still ask.
			expect(Q.Codes.GROUP).toBe(nil)
			Q.Codes.GROUP = { reward = { { kind = "gems", amount = 5 } }, requiresGroup = true }
			local ok, err = pcall(function()
				local h = boot()
				local p = h:Join()
				expect(h:Reject(p, "Quests.Redeem", { code = "group" })).toContain("Join our Roblox group")
				h.adapters.groups[p.UserId] = { [Q.GroupId] = true }
				h:Advance(2)
				h:Call(p, "Quests.Redeem", { code = "group" })
				expect(h:Section(p, "Quests").codes.GROUP).toBe(true)
				h:Advance(2)
				expect(h:Reject(p, "Quests.Redeem", { code = "group" })).toBe("You already used that code")
			end)
			Q.Codes.GROUP = nil
			if not ok then
				error(err, 0)
			end
		end)
	end)

	describe("Quests Ranch Pass", function()
		local IN_SEASON = Q.Pass.startsAt + 3600

		local function earnAchievements(h, p, n: number)
			local ids = { "first_epic", "first_golden", "first_mutation", "retire_1" }
			publish(h, "EggHatched", p, { id = "x", egg = "crystal", rarity = 4, variant = 1 })
			publish(h, "Mutated", p, { id = "x", mutation = "soaked" })
			publish(h, "Retired", p, { rarity = 1, element = "ember" })
			for i = 1, n do
				h:Call(p, "Quests.ClaimAchievement", { id = ids[i] })
				h:Advance(1)
			end
		end

		local function buyPass(h, p, purchaseId: string)
			local product = Config.Monetization.ProductByKey.ranchPass
			local saved = product.productId
			product.productId = 8801
			local ok, result = pcall(h.adapters._processReceipt, {
				PlayerId = p.UserId,
				ProductId = 8801,
				PurchaseId = purchaseId,
				CurrencySpent = product.price,
			})
			product.productId = saved
			assert(ok, result)
			return result
		end

		it("earns XP from dailies and achievements and claims free tiers", function()
			local h = boot({ startTime = IN_SEASON })
			local p = h:Join(7300)
			earnAchievements(h, p, 2)
			local pass = h:Section(p, "Quests").pass
			expect(pass.xp).toBe(2 * Q.Pass.xpPerAchievement)

			levelTo(h, p, 5)
			local daily = h:Section(p, "Quests").daily.list[1]
			local def
			for _, d in Q.DailyPool do
				if d.id == daily.id then
					def = d
				end
			end
			daily.progress = def.target
			h:Call(p, "Quests.ClaimDaily", { index = 1 })
			expect(pass.xp).toBe(2 * Q.Pass.xpPerAchievement + Q.Pass.xpPerDaily)

			local data = h:Call(p, "Quests.ClaimPass", { tier = 1, track = "free" })
			expect(data.rewards[1].kind).toBe(Q.Pass.tiers[1].free[1].kind)
			expect(pass.claimed.free[1]).toBe(true)
			expect(h:Reject(p, "Quests.ClaimPass", { tier = 1, track = "free" })).toBe("Already claimed")
			expect(h:Reject(p, "Quests.ClaimPass", { tier = 2, track = "free" })).toContain("Reach 600 Pass XP")
			h:Advance(2)
			expect(h:Reject(p, "Quests.ClaimPass", { tier = #Q.Pass.tiers + 1, track = "free" })).toBe("That tier doesn't exist")
			expect(h:Reject(p, "Quests.ClaimPass", { tier = 1, track = "premium" })).toContain("need the Ranch Pass")
			expect(h:Client(p).profile.Quests.pass.claimed.free[1]).toBe(true)
		end)

		it("unlocks the premium track through the Ranch Pass product", function()
			local h = boot({ startTime = IN_SEASON })
			local p = h:Join(7301)
			earnAchievements(h, p, 2)
			expect(buyPass(h, p, "rp1")).toBe("PurchaseGranted")
			expect(h:System("Quests"):PassPremium(p)).toBe(true)
			expect(buyPass(h, p, "rp1")).toBe("PurchaseGranted") -- same receipt replayed
			-- A second pass this season is never left unprocessed: it is banked for the next season.
			expect(buyPass(h, p, "rp2")).toBe("PurchaseGranted")
			expect(h:Section(p, "Quests").passCredit).toBe(1)
			expect(h:LastEvent(p, "Kernel.Notify").payload.text).toContain("saved for Season")
			expect(buyPass(h, p, "rp2")).toBe("PurchaseGranted")
			expect(h:Section(p, "Quests").passCredit).toBe(1)
			local data = h:Call(p, "Quests.ClaimPass", { tier = 1, track = "premium" })
			expect(data.rewards[1].amount).toBe(Q.Pass.tiers[1].premium[1].amount)
			expect(h:Section(p, "Currency").gems).toBe(25 + 50 + 30)
		end)

		it("gives no pass XP outside the season and resets on a new season", function()
			local h = boot() -- before the season starts
			local p = h:Join(7302)
			earnAchievements(h, p, 1)
			expect(h:Section(p, "Quests").pass.xp).toBe(0)

			local h2 = boot({ startTime = IN_SEASON })
			local q = h2:Join(7303)
			earnAchievements(h2, q, 2)
			expect(buyPass(h2, q, "rp3")).toBe("PurchaseGranted")
			h2:Call(q, "Quests.ClaimPass", { tier = 1, track = "free" })

			local season = Q.Pass.season
			Q.Pass.season = season + 1
			local ok, err = pcall(function()
				local q2 = h2:Rejoin(q, 60)
				local pass = h2:Section(q2, "Quests").pass
				expect(pass.season).toBe(season + 1)
				expect(pass.xp).toBe(0)
				expect(pass.premium).toBe(false)
				expect(pass.claimed.free[1]).toBe(false)
				expect(#pass.claimed.premium).toBe(#Q.Pass.tiers)
			end)
			Q.Pass.season = season
			assert(ok, err)
		end)
	end)

	describe("Ranch Pass sales outside a season", function()
		local S1 = Q.Seasons[1]

		local function sortedSeasons()
			local list = table.clone(Q.Seasons)
			table.sort(list, function(a, b)
				return a.startsAt < b.startsAt
			end)
			return list
		end

		local function buyPass(h, p, purchaseId: string)
			local product = Config.Monetization.ProductByKey.ranchPass
			local saved = product.productId
			product.productId = 8801
			local ok, result = pcall(h.adapters._processReceipt, {
				PlayerId = p.UserId,
				ProductId = 8801,
				PurchaseId = purchaseId,
				CurrencySpent = product.price,
			})
			product.productId = saved
			assert(ok, result)
			return result
		end

		it("is on sale only while a season runs, and knows when the next one starts", function()
			expect(Q.PassOnSale(S1.startsAt - 1)).toBe(false)
			expect(Q.PassOnSale(S1.startsAt)).toBe(true)
			expect(Q.PassOnSale(S1.endsAt - 1)).toBe(true)
			expect(Q.NextSeason(S1.startsAt - 1)).toBe(S1)
			local list = sortedSeasons()
			for i = 1, #list - 1 do
				local a, b = list[i], list[i + 1]
				if b.startsAt > a.endsAt then
					-- A gap between two seasons: not on sale, and the next is b.
					expect(Q.PassOnSale(a.endsAt)).toBe(false)
					expect(Q.NextSeason(a.endsAt)).toBe(b)
				end
			end
			expect(Q.NextSeason(list[#list].startsAt)).toBeNil()
			expect(Q.PassOnSale(list[#list].endsAt + 1)).toBe(false)
		end)

		it("refuses the prompt before a season and when premium is already on", function()
			local h = boot({ startTime = S1.startsAt - 86400 })
			local p = h:Join(7310)
			expect(h:Reject(p, "Monetization.CanBuy", { product = "ranchPass" })).toContain("goes on sale in")

			local h2 = boot({ startTime = S1.startsAt + 3600 })
			local q = h2:Join(7311)
			h2:Call(q, "Monetization.CanBuy", { product = "ranchPass" })
			buyPass(h2, q, "on1")
			h2:Advance(2)
			expect(h2:Reject(q, "Monetization.CanBuy", { product = "ranchPass" })).toBe("You already have this season's Ranch Pass")
		end)

		it("banks a pass bought before the season and unlocks it when the season opens", function()
			local h = boot({ startTime = S1.startsAt - 60 })
			local p = h:Join(7312)
			expect(buyPass(h, p, "early1")).toBe("PurchaseGranted")
			local s = h:Section(p, "Quests")
			expect(s.pass.premium).toBe(false)
			expect(s.passCredit).toBe(1)
			expect(h:Client(p).profile.Quests.passCredit).toBe(1)
			expect(h:System("Quests"):PassPremium(p)).toBe(false)

			-- Online when the season opens: the 30 s sweep applies it.
			h:Advance(100)
			s = h:Section(p, "Quests")
			expect(s.passCredit).toBe(0)
			expect(s.pass.premium).toBe(true)
			expect(h:System("Quests"):PassPremium(p)).toBe(true)
			expect(buyPass(h, p, "early1")).toBe("PurchaseGranted") -- replay: nothing more
			expect(h:Section(p, "Quests").passCredit).toBe(0)
		end)

		it("banks a pass bought in the gap after a season and unlocks the next one on join", function()
			local list = sortedSeasons()
			local a, b
			for i = 1, #list - 1 do
				if list[i + 1].startsAt > list[i].endsAt then
					a, b = list[i], list[i + 1]
					break
				end
			end
			assert(a and b, "expected a gap between two seasons in Config.Quests.Seasons")
			local h = boot({ startTime = a.endsAt + 3600 })
			local p = h:Join(7313)
			expect(buyPass(h, p, "gap1")).toBe("PurchaseGranted")
			expect(h:Section(p, "Quests").passCredit).toBe(1)
			expect(h:LastEvent(p, "Kernel.Notify").payload.text).toContain(string.format("Season %d", b.season))

			local p2 = h:Rejoin(p, b.startsAt - h.kernel.Clock.Now() + 10)
			local s = h:Section(p2, "Quests")
			expect(s.pass.season).toBe(b.season)
			expect(s.pass.premium).toBe(true)
			expect(s.passCredit).toBe(0)
		end)
	end)
end
