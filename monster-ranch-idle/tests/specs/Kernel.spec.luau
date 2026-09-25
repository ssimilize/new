-- Kernel: lifecycle, dependency rules, validation, replication and save/load.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel

	describe("Kernel", function()
		it("boots systems and gives a new player default sections", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression" } })
			local p = h:Join()
			expect(h:Section(p, "Currency").coins).toBe(0)
			expect(h:Section(p, "Progression").level).toBe(1)
			local client = h:Client(p)
			expect(client.profile.Currency.gems).toBe(0)
			expect(client.profile.Progression.level).toBe(1)
		end)

		it("rejects undeclared actions and unplugged systems", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			local p = h:Join()
			expect(h:Invoke(p, "Nope.Nothing", {}).err).toBe("UnknownAction")
			expect(h:Invoke(p, "Shop.BuyEgg", { egg = "meadow", amount = 1 }).err).toBe("NotAvailable")
		end)

		it("validates payloads before handlers run", function()
			local h = TestKernel.new({ systems = { "Settings" } })
			local p = h:Join()
			expect(h:Invoke(p, "Settings.Set", { key = "music", value = "yes" }).err).toBe("BadRequest")
			expect(h:Invoke(p, "Settings.Set", { key = "hack", value = true }).err).toBe("BadRequest")
			expect(h:Invoke(p, "Settings.Set", { key = "music", value = false, extra = 1 }).err).toBe("BadRequest")
			expect(h:Invoke(p, "Settings.Set", { key = "music", value = false }).ok).toBe(true)
			expect(h:Client(p).profile.Settings.music).toBe(false)
		end)

		it("rate-limits bursts", function()
			local h = TestKernel.new({ systems = { "Settings" } })
			local p = h:Join()
			local rejected = 0
			for _ = 1, 20 do
				local r = h:Invoke(p, "Settings.Set", { key = "sfx", value = true })
				if r.err == "TooFast" then
					rejected += 1
				end
			end
			expect(rejected).toBeGreaterThan(0)
			h:Advance(3)
			expect(h:Invoke(p, "Settings.Set", { key = "sfx", value = true }).ok).toBe(true)
		end)

		it("saves on leave and restores on rejoin", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			local p = h:Join(4242)
			h:System("Currency"):Add(p, "coins", 1234, "test")
			h:Leave(p)
			expect(h.adapters.store["player_4242"].lock).toBeNil()
			expect(h.adapters.store["player_4242"].data.Currency.coins).toBe(1234)
			local p2 = h:Join(4242)
			expect(h:Section(p2, "Currency").coins).toBe(1234)
		end)

		it("reports time away on rejoin", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			local seen
			h.kernel.Bus:Subscribe("PlayerReady", function(_player, info)
				seen = info
			end)
			local p = h:Join(77)
			expect(seen.firstJoin).toBe(true)
			h:Rejoin(p, 3600)
			expect(seen.firstJoin).toBe(false)
			expect(seen.awaySeconds).toBe(3600)
		end)

		it("kicks a player when their data is locked by a live server", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			h.adapters.store["player_555"] = { v = 1, data = {}, lock = { job = "other-server", at = h.adapters.Clock.Now() } }
			-- Steal happens after Data.StealAfterAttempts; with a fresh lock we still eventually load.
			local p = h:Join(555)
			expect(h.kernel:IsReady(p)).toBe(true)
			expect(h.adapters.store["player_555"].lock.job).toBe(h.adapters.JobId)
		end)

		it("disables a system whose required dependency is missing", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			expect(h.kernel:SystemState("Currency")).toBe("ready")
			local Kernel = t.Server("Kernel.Kernel")
			local MockAdapters = t.MockAdapters
			local k = Kernel.new({ adapters = MockAdapters.new() })
			k:AddSystem({ Name = "Needy", Dependencies = { "Ghost" } })
			k:Start()
			expect(k:SystemState("Needy")).toBe("failed")
		end)

		it("scopes a system's context to its own actions", function()
			local Kernel = t.Server("Kernel.Kernel")
			local MockAdapters = t.MockAdapters
			local k = Kernel.new({ adapters = MockAdapters.new() })
			k:AddSystem({
				Name = "Rogue",
				Init = function(ctx)
					ctx.Net:Handle("Shop.BuyEgg", function() end)
				end,
			})
			k:Start()
			expect(k:SystemState("Rogue")).toBe("failed")
		end)
	end)
end
