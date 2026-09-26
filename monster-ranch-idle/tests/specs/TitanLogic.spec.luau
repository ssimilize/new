-- Glow-up TT: pure rules for a titan invasion (Logic/Titan) - schedule window, report timing,
-- shared-pool reconcile maths, stale-server pruning and the fall/retreat rule.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Titan = t.Shared("Logic.Titan")

	local SCHEDULE = {
		{ startsAt = 1000, rotation = 1 },
		{ startsAt = 5000, rotation = 2 },
	}

	describe("Titan.Window", function()
		it("is nil outside every lobby/active window", function()
			expect(Titan.Window(SCHEDULE, 100, 50, 800)).toBe(nil)
			expect(Titan.Window(SCHEDULE, 100, 50, 1101)).toBe(nil) -- 1000 + 100 duration
		end)

		it("covers the lobby before startsAt and the fight until endsAt", function()
			local w = Titan.Window(SCHEDULE, 100, 50, 960) -- lobbyAt = 950
			expect(w ~= nil).toBe(true)
			expect(w.startsAt).toBe(1000)
			expect(w.endsAt).toBe(1100)
			expect(w.rotation).toBe(1)

			local live = Titan.Window(SCHEDULE, 100, 50, 1050)
			expect(live.startsAt).toBe(1000)

			-- The next slot, once the first has fully ended.
			local next = Titan.Window(SCHEDULE, 100, 50, 4960)
			expect(next.startsAt).toBe(5000)
			expect(next.rotation).toBe(2)
		end)
	end)

	describe("Titan.NextStart", function()
		it("is the soonest startsAt at or after now, or nil once exhausted", function()
			expect(Titan.NextStart(SCHEDULE, 0)).toBe(1000)
			expect(Titan.NextStart(SCHEDULE, 1000)).toBe(1000)
			expect(Titan.NextStart(SCHEDULE, 1001)).toBe(5000)
			expect(Titan.NextStart(SCHEDULE, 5001)).toBe(nil)
		end)
	end)

	describe("Titan.ShouldReport", function()
		it("is true once the interval has elapsed", function()
			expect(Titan.ShouldReport(100, 104, 5)).toBe(false)
			expect(Titan.ShouldReport(100, 105, 5)).toBe(true)
			expect(Titan.ShouldReport(100, 200, 5)).toBe(true)
		end)
	end)

	describe("Titan.Reconcile", function()
		it("shows the last confirmed hp minus damage not yet folded in, never below 0", function()
			expect(Titan.Reconcile(1000, 200)).toBe(800)
			expect(Titan.Reconcile(1000, 5000)).toBe(0)
		end)
	end)

	describe("Titan.PruneServers / Totals", function()
		it("drops servers that stopped reporting and totals the rest", function()
			local servers = {
				a = { players = 3, at = 100 },
				b = { players = 2, at = 60 }, -- stale once now = 100, staleAfter = 30
			}
			local kept = Titan.PruneServers(servers, 100, 30)
			expect(kept.a ~= nil).toBe(true)
			expect(kept.b).toBe(nil)
			local serverCount, playerCount = Titan.Totals(kept)
			expect(serverCount).toBe(1)
			expect(playerCount).toBe(3)
		end)

		it("Totals handles nil/empty tables", function()
			local serverCount, playerCount = Titan.Totals(nil)
			expect(serverCount).toBe(0)
			expect(playerCount).toBe(0)
		end)
	end)

	describe("Titan.Outcome", function()
		it("is fallen at 0 hp, retreated once time is up, else active", function()
			expect(Titan.Outcome(0, 50, 100)).toBe("fallen")
			expect(Titan.Outcome(10, 100, 100)).toBe("retreated")
			expect(Titan.Outcome(10, 50, 100)).toBe("active")
			-- hp <= 0 wins even if time is also up.
			expect(Titan.Outcome(0, 100, 100)).toBe("fallen")
		end)
	end)

	describe("Titan.Helped", function()
		it("is true once damage reaches the minimum", function()
			expect(Titan.Helped(0, 1)).toBe(false)
			expect(Titan.Helped(1, 1)).toBe(true)
			expect(Titan.Helped(500, 1)).toBe(true)
		end)
	end)

	describe("PruneServers cap", function()
		it("keeps only the most recent servers once there are more than the cap", function()
			local servers = {
				a = { players = 1, at = 100 },
				b = { players = 2, at = 104 },
				c = { players = 3, at = 102 },
				d = { players = 4, at = 103 },
				old = { players = 9, at = 10 },
			}
			local kept = Titan.PruneServers(servers, 105, 30, 2)
			expect(kept.b ~= nil).toBe(true)
			expect(kept.d ~= nil).toBe(true)
			expect(kept.a).toBe(nil)
			expect(kept.c).toBe(nil)
			expect(kept.old).toBe(nil)
			local all = Titan.PruneServers(servers, 105, 30)
			local n = 0
			for _ in all do
				n += 1
			end
			expect(n).toBe(4) -- no cap: every fresh server
		end)
	end)

	describe("Titan.Overlaps", function()
		it("sees any window that touches an invasion's lobby-to-end span", function()
			local schedule = { { startsAt = 10000, rotation = 1 } }
			-- the invasion holds [10000 - 100, 10000 + 600)
			expect(Titan.Overlaps(schedule, 600, 100, 9000, 9950)).toBe(true) -- runs into the lobby
			expect(Titan.Overlaps(schedule, 600, 100, 10500, 11000)).toBe(true) -- starts before the end
			expect(Titan.Overlaps(schedule, 600, 100, 8000, 9900)).toBe(false) -- ends as the lobby opens
			expect(Titan.Overlaps(schedule, 600, 100, 10600, 12000)).toBe(false) -- starts at the end
			expect(Titan.Overlaps({}, 600, 100, 0, 1e9)).toBe(false)
		end)
	end)
end
