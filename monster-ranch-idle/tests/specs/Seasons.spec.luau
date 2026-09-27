--[[
	Seasons (update 3.11 · Ranch Seasons): the season clock (one season per Leaderboards week,
	turning over at the Saturday reset; 2026-09-27 is autumn), the Calendar entries, seasonal fish
	(they bite only in their season and never move another fish's seeded roll), seasonal recipes
	(season gate, their own fish first), the Feed Garden bonus (+25% of the season's flavour,
	other flavours untouched), the tourists' favourite Appeal category, seasonal decor in the Shop,
	the season_fish_3 weekly goal, and SeasonChanged / the arrival line on join and at the turnover.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Seasons = t.Shared("Logic.Seasons")
	local FishLogic = t.Shared("Logic.Fishing")
	local KitchenLogic = t.Shared("Logic.Kitchen")
	local TouristsLogic = t.Shared("Logic.Tourists")
	local Calendar = t.Shared("Logic.Calendar")
	local Objectives = t.Shared("Logic.Objectives")

	local L = Config.Leaderboards
	local WEEK = L.WeekSeconds
	local SUMMER_AT = 1790000000 -- the harness's default clock: week 0, summer
	local SEPT_27 = 1790510400 -- Sunday 27 Sep 2026, 12:00 UTC

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function unlockLevel(key: string): number
		return Config.Unlocks.Features[key] or 1
	end

	describe("Season clock", function()
		it("puts the week of 27 Sep 2026 in autumn and turns over at the Saturday reset", function()
			local s = Seasons.At(SEPT_27)
			expect(s.id).toBe("autumn")
			expect(s.index).toBe(3)
			local week = L.Week(SEPT_27)
			expect(s.startsAt).toBe(L.WeekEndsAt(week - 1))
			expect(s.endsAt).toBe(L.WeekEndsAt(week))
			expect(Seasons.At(s.endsAt - 1).id).toBe("autumn")
			expect(Seasons.At(s.endsAt).id).toBe("winter")
			expect(Seasons.At(s.startsAt).id).toBe("autumn")
			expect(Seasons.At(s.startsAt - 1).id).toBe("summer")
			expect(Seasons.Next(SEPT_27).id).toBe("winter")
			expect(Seasons.Next(SEPT_27).startsAt).toBe(s.endsAt)
			expect(Seasons.At(SEPT_27 + 2 * WEEK).id).toBe("spring")
			expect(Seasons.At(SEPT_27 + 4 * WEEK).id).toBe("autumn") -- a 28-day cycle
			expect(Seasons.At(SEPT_27 - 52 * WEEK).id).toBe("autumn") -- weeks before the anchor wrap too
			expect(Seasons.At(SUMMER_AT).id).toBe("summer")
		end)

		it("lists the current and next season in the Calendar (the HUD chips and the Events screen)", function()
			local s = Seasons.At(SEPT_27)
			local now = Calendar.Now(SEPT_27)
			local running = nil
			for _, e in now do
				if e.kind == "season" then
					running = e
				end
			end
			expect(running ~= nil).toBe(true)
			expect(running.name).toBe("Autumn")
			expect(running.endsAt).toBe(s.endsAt)
			-- A day before the turnover, the next season is a HUD chip.
			local soon = Calendar.Soon(s.endsAt - 3600, 24 * 3600)
			local chip = nil
			for _, e in soon do
				if e.kind == "season" then
					chip = e
				end
			end
			expect(chip ~= nil).toBe(true)
			expect(chip.name).toBe("Winter")
			expect(chip.startsAt).toBe(s.endsAt)
		end)
	end)

	describe("Seasonal fish", function()
		it("bite only in their season and never move another fish's roll or course", function()
			local seen = {}
			for seed = 1, 3000 do
				local plain = FishLogic.Roll(seed, 0)
				expect(plain.season).toBe(nil)
				local winter = FishLogic.Roll(seed, 0, "winter")
				if winter.id ~= plain.id then
					expect(winter.id).toBe("frost_char")
					expect(plain.rarity).toBe("uncommon")
					seen[winter.id] = true
				else
					expect(winter.season).toBe(nil)
				end
				if seed <= 200 then
					-- Same rarity = the very same course points: the replay never shifts.
					local a, b = FishLogic.Course(seed, 0), FishLogic.Course(seed, 0, "winter")
					expect(#a.points).toBe(#b.points)
					for i, pt in a.points do
						expect(b.points[i].y).toBe(pt.y)
					end
				end
			end
			expect(seen.frost_char).toBe(true)
			expect(FishLogic.SeasonFish("spring").id).toBe("blossom_trout")
			expect(#Config.Fishing.Fish).toBe(20)
			expect(Config.Codex.FishSteps[#Config.Codex.FishSteps]).toBe(20)
		end)

		it("fixes the cast's season at Fishing.Start and marks seasonal catches", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Fishing" } })
			local p = h:Join()
			levelTo(h, p, unlockLevel("fishing"))
			local res = h:Call(p, "Fishing.Start")
			expect(res.season).toBe("summer")
			-- Seasonal fish are spent last (kept for the seasonal recipes).
			local order = FishLogic.SpendOrder()
			expect(Config.Fishing.ById[order[#order]].season ~= nil).toBe(true)
			expect(Config.Fishing.ById[order[1]].season).toBe(nil)
		end)
	end)

	describe("Seasonal recipes", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Fishing", "Kitchen" }

		local function boot()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			levelTo(h, p, math.max(unlockLevel("fishing"), unlockLevel("kitchen")))
			h:System("Currency"):Add(p, "food.sour", 20, "test")
			h:System("Currency"):Add(p, "food.savory", 20, "test")
			return h, p
		end

		it("cook only in their season with one of the season's own fish", function()
			local h, p = boot()
			local pond = h:Section(p, "Fishing")
			pond.fish = { minnow = 5 }
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "sunny_ceviche" })).toBe("Needs a Sunburst Bass from the Fishing Pond")
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "maple_glazed_carp" })).toBe("Only cooked in Autumn")
			pond.fish = { minnow = 3, sunburst_bass = 1 }
			h:Call(p, "Kitchen.Cook", { recipe = "sunny_ceviche" })
			expect(pond.fish.sunburst_bass).toBe(nil)
			expect(pond.fish.minnow).toBe(2)
		end)

		it("leaves the season's fish for last in the year-round recipes", function()
			local h, p = boot()
			local pond = h:Section(p, "Fishing")
			pond.fish = { sunburst_bass = 1, minnow = 1, trout = 1 }
			h:Call(p, "Kitchen.Cook", { recipe = "fish_supper" })
			expect(pond.fish.sunburst_bass).toBe(1)
			expect(pond.fish.minnow).toBe(nil)
			expect(pond.fish.trout).toBe(nil)
		end)

		it("say when they are in season", function()
			local r = Config.Kitchen.ById.frost_chowder
			local text, inSeason = KitchenLogic.SeasonNote(r, "winter")
			expect(text).toBe("In season: Winter")
			expect(inSeason).toBe(true)
			text, inSeason = KitchenLogic.SeasonNote(r, "spring")
			expect(text).toBe("Back in Winter")
			expect(inSeason).toBe(false)
			expect(KitchenLogic.SeasonNote(Config.Kitchen.ById.berry_pie, "spring")).toBe(nil)
			local have = { food = { spicy = 9 }, fish = 3, golden = 0, kinds = { minnow = 3 } }
			expect(KitchenLogic.Missing(r, have)).toBe("seasonFish")
			have.kinds.frost_char = 1
			expect(KitchenLogic.Missing(r, have)).toBe(nil)
		end)
	end)

	describe("Feed Garden bonus", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Seasons" }

		it("grows 25% more of the season's flavour and leaves the others alone", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			levelTo(h, p, unlockLevel("garden"))
			local C = h:System("Currency")
			local yield = Config.Economy.Garden.yield
			local function harvest(flavor: string): number
				local before = C:Balance(p, "food." .. flavor)
				h:Call(p, "Ranch.Plant", { plot = 1, flavor = flavor })
				h:Section(p, "Ranch").garden.plots[1].readyAt = 0
				h:Call(p, "Ranch.Harvest", { plot = 1 })
				return C:Balance(p, "food." .. flavor) - before
			end
			-- Summer's flavour is sour: 4 harvests pay exactly 25% more between them.
			local total = 0
			for _ = 1, 4 do
				local got = harvest("sour")
				expect(got >= yield + 1).toBe(true)
				total += got
			end
			expect(total).toBe(math.floor(4 * yield * (1 + Config.Seasons.GardenBonus) + 0.5))
			expect(harvest("sweet")).toBe(yield)
			expect(Seasons.GardenBonus("sweet", "summer", yield)).toBe(0)
			expect(Seasons.GardenBonus("sweet", "spring", yield)).toBe(yield * 0.25)
		end)
	end)

	describe("Tourists", function()
		it("count the season's favourite category x1.25, renormalised so a perfect ranch is still 100", function()
			local W = Config.Tourists.Weights
			local w = Seasons.AppealWeights(W, "rarity")
			local sum, base = 0, 0
			for id, v in w do
				sum += v
				base += W[id]
			end
			expect(math.abs(sum - base) < 1e-9).toBe(true)
			expect(math.abs(w.rarity / w.decor - 1.25 * W.rarity / W.decor) < 1e-9).toBe(true)
			expect(Seasons.AppealWeights(W, nil).rarity).toBe(W.rarity)
			-- Only rare monsters: the winter ranch scores higher than the same ranch with no season.
			local facts = { layout = {}, level = 1, pens = {}, rarities = { 6, 6, 6 }, codex = 0 }
			local plain = TouristsLogic.Appeal(facts).score
			facts.favored = "rarity"
			expect(TouristsLogic.Appeal(facts).score).toBeGreaterThan(plain)
			for _, s in Config.Seasons.List do
				expect(Config.Tourists.CategoryById[s.appeal] ~= nil).toBe(true)
				expect(Config.Food.ById[s.flavor] ~= nil).toBe(true)
			end
		end)
	end)

	describe("Seasonal decor", function()
		it("is sold only in its season and stays owned after", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop" } })
			local p = h:Join()
			h:System("Currency"):Add(p, "coins", 1e6, "test")
			local count = {}
			for _, d in Config.Decor.List do
				if d.season then
					count[d.season] = (count[d.season] or 0) + 1
					expect(d.price ~= nil).toBe(true)
				end
			end
			for _, id in Config.Seasons.Ids do
				expect(count[id]).toBe(2)
			end
			h:Call(p, "Shop.BuyDecor", { decor = "summer_sunflowers" })
			expect(h:Reject(p, "Shop.BuyDecor", { decor = "autumn_leaves" })).toBe("That seasonal decor isn't available right now")
			h:Advance(WEEK)
			expect(Seasons.At(h.adapters.Clock.Now()).id).toBe("autumn")
			h:Call(p, "Shop.BuyDecor", { decor = "autumn_leaves" })
			expect(h:Reject(p, "Shop.BuyDecor", { decor = "summer_sunflowers" })).toBe("That seasonal decor isn't available right now")
			local owned = h:Section(p, "Shop").decor
			expect(owned.summer_sunflowers).toBe(1)
			expect(owned.autumn_leaves).toBe(1)
		end)
	end)

	describe("Weekly goal", function()
		it("season_fish_3 counts the season's fish only", function()
			local def = Config.Weekly.ById.season_fish_3
			expect(def ~= nil).toBe(true)
			expect(def.family).toBe("seasons")
			expect(def.unlock).toBe("fishing")
			expect(def.topic).toBe("FishCaught")
			expect(def.target).toBe(3)
			expect(Objectives.Matches(def.filter, { fish = "frost_char", seasonal = true })).toBe(true)
			expect(Objectives.Matches(def.filter, { fish = "minnow", seasonal = false })).toBe(false)
		end)
	end)

	describe("SeasonChanged", function()
		it("records the season on a first join, then announces the turnover online and on a later join", function()
			local h = TestKernel.new({ systems = { "Seasons" } })
			local changed, welcome = {}, {}
			h.kernel.Bus:Subscribe("SeasonChanged", function(player, detail)
				table.insert(changed, { player = player, season = detail.season })
			end)
			h.kernel.Bus:Subscribe("WelcomeItem", function(player, detail)
				table.insert(welcome, detail)
			end)
			local p = h:Join()
			expect(h:Section(p, "Seasons").last).toBe("summer")
			expect(#changed).toBe(1)
			expect(#welcome).toBe(0) -- a brand new player gets no arrival line
			local endsAt = Seasons.At(h.adapters.Clock.Now()).endsAt
			h:Advance(endsAt - h.adapters.Clock.Now() - 2)
			expect(#changed).toBe(1)
			h:Advance(Config.Seasons.TickSeconds + 3)
			expect(#changed).toBe(2)
			expect(changed[2].season).toBe("autumn")
			expect(h:Section(p, "Seasons").last).toBe("autumn")
			local toast = h:LastEvent(p, "Kernel.Notify")
			expect(toast ~= nil and toast.payload.text).toBe("Autumn has come to the ranch")
			-- Away for a week: the Welcome Back screen says winter has come.
			h:Rejoin(p, WEEK)
			expect(changed[#changed].season).toBe("winter")
			expect(#welcome).toBe(1)
			expect(welcome[1].kind).toBe("season")
			expect(welcome[1].text).toBe("Winter has come to the ranch")
		end)
	end)
end
