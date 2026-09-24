-- S3 WelcomeBack: the offline summary (coins + items) and its claim (×2 with an ad).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Formulas = t.Shared("Logic.Formulas")

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "WelcomeBack" }

	local function fakeMonetization()
		local m = { passes = {}, adResult = true, ads = {} }
		function m:HasPass(_player, key)
			return self.passes[key] == true
		end
		function m:WatchAd(_player, placement)
			table.insert(self.ads, placement)
			return self.adResult
		end
		function m:PaidRandomAllowed()
			return true
		end
		return m
	end

	local function boot(opts)
		local o = opts or {}
		local money = if o.monetization == false then nil else fakeMonetization()
		local h = TestKernel.new({ systems = SYSTEMS, stubs = { Monetization = money } })
		local p = h:Join()
		return h, p, money
	end

	-- A player with one monster earning coins in pen 1.
	local function withMonster(h, p)
		return h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1, traits = { 3, 4 }, hidden = 5, variant = 0 }, "hatch", true)
	end

	describe("WelcomeBack", function()
		it("shows nothing on the first join", function()
			local h, p = boot()
			local client = h:Client(p)
			expect(client.session.WelcomeBack.pending).toBe(false)
			expect(client.session.WelcomeBack.items).toEqual({})
			expect(h:Reject(p, "WelcomeBack.Claim", { double = false })).toBe("Nothing to claim")
		end)

		it("skips short absences", function()
			local h, p = boot()
			withMonster(h, p)
			local p2 = h:Rejoin(p, Config.Economy.WelcomeBackMinSeconds - 1)
			expect(h:Session(p2, "WelcomeBack").pending).toBe(false)
		end)

		it("skips the screen when there is nothing to show", function()
			local h, p = boot()
			local p2 = h:Rejoin(p, 3600) -- the unhatched starter egg is ready: that's an item
			expect(h:Session(p2, "WelcomeBack").pending).toBe(true)
			expect(h:Session(p2, "WelcomeBack").coins).toBe(0)
			h:Call(p2, "Eggs.Hatch", { slot = 1 })
			local monsters = h:System("Monsters")
			for id in monsters:All(p2) do
				monsters:Remove(p2, id, "sell")
			end
			local p3 = h:Rejoin(p2, 3600)
			expect(h:Session(p3, "WelcomeBack").pending).toBe(false)
		end)

		it("summarises offline coins and what finished while away", function()
			local h, p = boot()
			h:Advance(8)
			h:Call(p, "Eggs.Hatch", { slot = 1 })
			local m = withMonster(h, p)
			local id = h:System("Eggs"):Add(p, "royal", "test")[1]
			h:Call(p, "Eggs.Place", { egg = id, slot = 1 })
			local p2 = h:Rejoin(p, 2 * 3600)
			local wb = h:Client(p2).session.WelcomeBack
			expect(wb.pending).toBe(true)
			expect(wb.awaySeconds).toBe(2 * 3600)
			expect(wb.coins).toBe(h:System("Ranch"):JarTotal(p2))
			expect(wb.coins).toBeGreaterThan(math.floor(Formulas.CoinRate(m) * 3600) - 1)
			expect(wb.items).toContain({ kind = "eggs", text = "1 egg ready to hatch" })
		end)

		it("claims every jar and clears the summary", function()
			local h, p = boot()
			withMonster(h, p)
			local p2 = h:Rejoin(p, 3 * 3600)
			local total = h:Session(p2, "WelcomeBack").coins
			local data = h:Call(p2, "WelcomeBack.Claim", { double = false })
			expect(data.coins).toBe(total)
			expect(h:Section(p2, "Currency").coins).toBe(total)
			expect(h:Client(p2).session.WelcomeBack.pending).toBe(false)
			h:Advance(1)
			expect(h:Reject(p2, "WelcomeBack.Claim", { double = false })).toBe("Nothing to claim")
		end)

		it("doubles the haul after a rewarded ad", function()
			local h, p, money = boot()
			withMonster(h, p)
			local p2 = h:Rejoin(p, 3 * 3600)
			local total = h:Session(p2, "WelcomeBack").coins
			money.adResult = false
			expect(h:Reject(p2, "WelcomeBack.Claim", { double = true })).toBe("The ad didn't finish")
			expect(h:Session(p2, "WelcomeBack").pending).toBe(true)
			money.adResult = true
			h:Advance(1)
			local data = h:Call(p2, "WelcomeBack.Claim", { double = true })
			expect(data.coins).toBe(total * 2)
			expect(money.ads).toEqual({ "welcomeDouble", "welcomeDouble" })
		end)

		it("offers no ad without Monetization but still pays ×1", function()
			local h, p = boot({ monetization = false })
			withMonster(h, p)
			local p2 = h:Rejoin(p, 3 * 3600)
			expect(h:Reject(p2, "WelcomeBack.Claim", { double = true })).toBe("Ads aren't available")
			h:Advance(1)
			expect(h:Call(p2, "WelcomeBack.Claim", { double = false }).coins).toBeGreaterThan(0)
		end)

		it("keeps Auto-Collect from draining the jars before the claim", function()
			local h, p, money = boot()
			money.passes.autoCollect = true
			withMonster(h, p)
			h:Advance(Config.Economy.RanchTickSeconds)
			local p2 = h:Rejoin(p, 3 * 3600)
			local total = h:Session(p2, "WelcomeBack").coins
			local before = h:Section(p2, "Currency").coins
			h:Advance(30)
			expect(h:Section(p2, "Currency").coins).toBe(before)
			local data = h:Call(p2, "WelcomeBack.Claim", { double = true })
			expect(data.coins).toBeAtLeast(total * 2)
			h:Advance(30)
			expect(h:Section(p2, "Currency").coins).toBeGreaterThan(before + data.coins) -- auto-collect resumed
		end)

		it("collects join items from any system", function()
			local h = boot()
			local Welcome = h:System("WelcomeBack")
			expect(Welcome).toBeTruthy()
			local p = h:Join()
			-- Items published after the join are not added to a summary.
			h.kernel.Bus:Publish("WelcomeItem", p, { kind = "evolve", text = "1 monster grew up" })
			expect(h:Session(p, "WelcomeBack").items).toEqual({})
		end)
	end)
end
