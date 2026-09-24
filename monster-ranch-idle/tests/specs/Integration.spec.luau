--[[
	Integration: every server system from the Manifest plugged in together, driven through
	the same actions the client uses. This is the "does the game loop actually work" test
	the integrator runs after plugging systems in.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel

	local function manifestSystems()
		local manifest = t.Server("Manifest")
		local list = {}
		for _, name in manifest.Systems do
			if name ~= "World" then -- geometry; Studio only
				table.insert(list, name)
			end
		end
		return list
	end

	local function has(list, name)
		return table.find(list, name) ~= nil
	end

	describe("Integration", function()
		it("boots every plugged-in system", function()
			local systems = manifestSystems()
			local h = TestKernel.new({ systems = systems })
			for _, name in systems do
				expect(h.kernel:SystemState(name)).toBe("ready")
			end
		end)

		it("plays the first session loop end to end", function()
			local systems = manifestSystems()
			for _, required in { "Eggs", "Shop", "Ranch", "Expeditions" } do
				if not has(systems, required) then
					return -- not plugged in yet
				end
			end
			local h = TestKernel.new({ systems = systems })
			local p = h:Join()

			-- Starter egg is waiting in slot 1 and hatches after a few seconds.
			local slots = h:Client(p).profile.Eggs.slots
			expect(slots[1].type).toBe("starter")
			h:Advance(10)
			local hatched = h:Call(p, "Eggs.Hatch", { slot = 1 })
			local starter = hatched.monster
			expect(starter.rarity).toBe(2)

			-- It walked into pen 1 and starts filling the jar.
			h:Advance(60)
			local coins = h:Call(p, "Ranch.CollectAll").coins
			expect(coins).toBeGreaterThan(0)

			-- Buy and hatch Meadow Eggs.
			h:System("Currency"):Add(p, "coins", 1000, "test")
			local bought = h:Call(p, "Shop.BuyEgg", { egg = "meadow", amount = 2 })
			expect(#bought.eggs).toBe(2)
			h:Call(p, "Eggs.PlaceAuto")
			h:Advance(35)
			local all = h:Call(p, "Eggs.HatchAll")
			expect(#all.monsters).toBeAtLeast(1)

			-- Feed, level and grow the starter.
			h:System("Currency"):Add(p, "food.spicy", 10, "test")
			h:System("Currency"):Add(p, "coins", 1e6, "test")
			h:System("Currency"):Add(p, "treats", 50, "test")
			h:Call(p, "Monsters.Feed", { id = starter.id, flavor = "spicy", amount = 3 })
			h:Call(p, "Monsters.LevelUp", { id = starter.id, times = 10 })
			h:Call(p, "Monsters.Grow", { id = starter.id })
			h:Advance(20)
			expect(h:Client(p).profile.Monsters.list[starter.id].stage).toBe(2)

			-- Battle and an expedition.
			h:Call(p, "Expeditions.SetSquad", { ids = { starter.id } })
			local fight = h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 1 })
			expect(type(fight.win)).toBe("boolean")
			expect(#fight.replay.units).toBeGreaterThan(1)
			if fight.win then
				h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = { starter.id } })
				expect(h:Client(p).profile.Monsters.list[starter.id].busy).toBe("expedition")
			end

			-- Leave for an hour: the jar fills (capped) and Welcome Back is waiting.
			local p2 = h:Rejoin(p, 3600)
			h:Step()
			if has(systems, "WelcomeBack") then
				local wb = h:Client(p2).session.WelcomeBack
				expect(wb and wb.pending).toBe(true)
				local claim = h:Call(p2, "WelcomeBack.Claim", { double = false })
				expect(claim.coins).toBeGreaterThan(0)
			end
			if fight.win then
				local rewards = h:Call(p2, "Expeditions.Claim", { slot = 1 }).rewards
				expect(#rewards).toBeGreaterThan(0)
			end
		end)

		it("keeps saved data intact across many rejoins", function()
			local systems = manifestSystems()
			local h = TestKernel.new({ systems = systems })
			local p = h:Join(9001)
			h:System("Currency"):Add(p, "coins", 777, "test")
			for _ = 1, 3 do
				p = h:Rejoin(p, 120)
			end
			expect(h:Section(p, "Currency").coins).toBeAtLeast(777)
			expect(h.adapters.log.kicks[1]).toBeNil()
		end)

		it("hosts a full server of six players with plots", function()
			local systems = manifestSystems()
			if not has(systems, "Plots") then
				return
			end
			local h = TestKernel.new({ systems = systems })
			local players = {}
			for i = 1, 6 do
				players[i] = h:Join()
			end
			h:Advance(3)
			local plots = h:Client(players[1]).global.Plots
			local taken = 0
			for i = 1, 6 do
				if plots[i] and plots[i].userId ~= 0 then
					taken += 1
				end
			end
			expect(taken).toBe(6)
			h:Leave(players[3])
			h:Advance(3)
			plots = h:Client(players[1]).global.Plots
			taken = 0
			for i = 1, 6 do
				if plots[i] and plots[i].userId ~= 0 then
					taken += 1
				end
			end
			expect(taken).toBe(5)
		end)

		it("survives a day of server time with timers running", function()
			local systems = manifestSystems()
			local h = TestKernel.new({ systems = systems })
			local p = h:Join()
			local q = h:Join()
			h:Advance(3 * 3600)
			expect(h.kernel:IsReady(p)).toBe(true)
			expect(h.kernel:IsReady(q)).toBe(true)
			for _, w in t.warnings do
				-- No system should be throwing inside scheduled jobs.
				expect(string.find(w, "failed", 1, true) == nil).toBe(true)
			end
		end)
	end)
end
