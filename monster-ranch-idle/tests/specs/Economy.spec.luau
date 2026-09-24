-- S1 Economy core + S2 Monsters: reference system tests.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel

	local CORE = { "Currency", "Progression", "Rewards", "Settings", "Monsters" }

	describe("Currency", function()
		it("adds, spends all-or-nothing and replicates", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			local p = h:Join()
			local C = h:System("Currency")
			C:Add(p, "coins", 500, "test")
			C:Add(p, "food.sweet", 3, "test")
			expect(C:Spend(p, { coins = 400, ["food.sweet"] = 4 }, "test")).toBe(false)
			expect(C:Balance(p, "coins")).toBe(500)
			expect(C:Spend(p, { coins = 400, ["food.sweet"] = 3 }, "test")).toBe(true)
			local client = h:Client(p)
			expect(client.profile.Currency.coins).toBe(100)
			expect(client.profile.Currency.food.sweet).toBe(0)
		end)
	end)

	describe("Progression", function()
		it("levels up through RanchXP and announces unlocks", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression" } })
			local p = h:Join()
			local need = t.Shared("Config").Unlocks.XPToNext(1) + t.Shared("Config").Unlocks.XPToNext(2)
			h.kernel.Bus:Publish("RanchXP", p, { amount = need, reason = "test" })
			expect(h:Section(p, "Progression").level).toBe(3)
			local ev = h:LastEvent(p, "Progression.LevelUp")
			expect(ev.payload.level).toBe(3)
			expect(ev.payload.unlocks).toContain("egg_grove")
			expect(h:System("Progression"):IsUnlocked(p, "egg_grove")).toBe(true)
			expect(h:System("Progression"):IsUnlocked(p, "breeding")).toBe(false)
		end)
	end)

	describe("Rewards", function()
		it("grants mixed rewards and skips kinds whose system is unplugged", function()
			local h = TestKernel.new({ systems = CORE })
			local p = h:Join()
			local granted = h:System("Rewards"):Grant(p, {
				{ kind = "coins", amount = 50 },
				{ kind = "gems", amount = 5 },
				{ kind = "food", id = "random", amount = 2 },
				{ kind = "monster", id = "mossbun", rarity = 2, amount = 1 },
				{ kind = "egg", id = "meadow", amount = 1 },
			}, "test")
			expect(#granted).toBe(4)
			expect(h:Section(p, "Currency").coins).toBe(50)
			expect(h:System("Monsters"):Count(p)).toBe(1)
			expect(h:LastEvent(p, "Rewards.Granted").payload.source).toBe("test")
		end)
	end)

	describe("Monsters", function()
		local function setup()
			local h = TestKernel.new({ systems = CORE })
			local p = h:Join()
			local M = h:System("Monsters")
			local m = M:Create(p, { line = "cindlet", rarity = 1, traits = { 3, 4 }, hidden = 5 }, "test")
			return h, p, M, m
		end

		it("creates monsters with ids, codex entries and replication", function()
			local h, p, _M, m = setup()
			expect(m.id).toBe("m1")
			local client = h:Client(p)
			expect(client.profile.Monsters.list.m1.line).toBe("cindlet")
			expect(client.profile.Monsters.codex.cindlet.forms.cindlet).toBe(true)
		end)

		it("feeds with food, levels with coins and grows after the timer", function()
			local h, p, _M, m = setup()
			local C = h:System("Currency")
			C:Add(p, "food.spicy", 20, "test")
			C:Add(p, "coins", 1e6, "test")
			C:Add(p, "treats", 100, "test")
			h:Call(p, "Monsters.Feed", { id = m.id, flavor = "spicy", amount = 3 })
			expect(h:Reject(p, "Monsters.Grow", { id = m.id })).toContain("level")
			local data = h:Call(p, "Monsters.LevelUp", { id = m.id, times = 10 })
			expect(data.lv).toBe(10)
			local grow = h:Call(p, "Monsters.Grow", { id = m.id })
			expect(grow.growEndsAt).toBe(h.adapters.Clock.Now() + 15) -- tutorial timer
			h:Advance(16)
			expect(m.stage).toBe(2)
			expect(m.form).toBe("kindlefox")
			expect(h:LastEvent(p, "Monsters.Evolved").payload.toForm).toBe("kindlefox")
		end)

		it("picks the adult branch from the teen's diet", function()
			local h, p, _M, m = setup()
			m.stage, m.form, m.lv = 2, "kindlefox", 25
			h:System("Monsters"):Changed(p, m.id)
			local C = h:System("Currency")
			C:Add(p, "food.sweet", 10, "test")
			h:Call(p, "Monsters.Feed", { id = m.id, flavor = "sweet", amount = 5 })
			h:Section(p, "Monsters").grown = 1
			h:Call(p, "Monsters.Grow", { id = m.id })
			h:Advance(301)
			expect(m.form).toBe("hearthtail")
		end)

		it("completes growth that finished while offline", function()
			local h, p, _M, m = setup()
			m.lv, m.meals = 10, { sweet = 3 }
			h:Section(p, "Monsters").grown = 1
			h:Call(p, "Monsters.Grow", { id = m.id })
			local p2 = h:Rejoin(p, 3600)
			expect(h:Section(p2, "Monsters").list.m1.stage).toBe(2)
		end)

		it("star-ups with a matching duplicate and refuses mismatches", function()
			local h, p, M, m = setup()
			local other = M:Create(p, { line = "mossbun", rarity = 1 }, "test")
			local dupe = M:Create(p, { line = "cindlet", rarity = 1 }, "test")
			expect(h:Reject(p, "Monsters.StarUp", { id = m.id, fodder = other.id })).toContain("same species")
			expect(h:Call(p, "Monsters.StarUp", { id = m.id, fodder = dupe.id }).stars).toBe(2)
			expect(M:Get(p, dupe.id)).toBeNil()
		end)

		it("sells unlocked monsters for coins but keeps at least one", function()
			local h, p, M, m = setup()
			local extra = M:Create(p, { line = "mossbun", rarity = 1 }, "test")
			expect(h:Reject(p, "Monsters.Sell", { ids = { m.id, extra.id } })).toContain("at least one")
			local data = h:Call(p, "Monsters.Sell", { ids = { extra.id } })
			expect(data.coins).toBeAtLeast(25)
			expect(M:Count(p)).toBe(1)
		end)

		it("respects capacity providers", function()
			local _h, p, M = setup()
			M:RegisterCapacityProvider(function()
				return 1
			end)
			local _, err = M:Create(p, { line = "mossbun", rarity = 1 }, "test")
			expect(err).toContain("full")
		end)

		it("filters names", function()
			local h, p, _M, m = setup()
			expect(h:Call(p, "Monsters.Rename", { id = m.id, name = "  Toasty " }).name).toBe("Toasty")
			expect(h:Call(p, "Monsters.Rename", { id = m.id, name = "badword" }).name).toBe("#######")
		end)
	end)
end
