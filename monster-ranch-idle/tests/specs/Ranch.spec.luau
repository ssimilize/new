-- S3 Ranch: pens, coin jars (online, offline, caps, modifiers, passes), assignment and busy
-- monsters, upgrades, decor, themes, garden and auto-collect.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Formulas = t.Shared("Logic.Formulas")
	local Economy = Config.Economy

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
		local money = fakeMonetization()
		local stubs = { Monetization = money }
		for name, api in o.stubs or {} do
			stubs[name] = api
		end
		local h = TestKernel.new({ systems = SYSTEMS, stubs = stubs })
		local p = h:Join()
		return h, p, h:System("Ranch"), money
	end

	local function levelTo(h, p, level: number)
		local s = h:Section(p, "Progression")
		local need = -s.xp
		for l = s.level, level - 1 do
			need += Config.Unlocks.XPToNext(l)
		end
		h:System("Progression"):AddXP(p, need, "test")
	end

	local function coins(h, p, n)
		h:System("Currency"):Add(p, "coins", n, "test")
	end

	-- A monster with no coin/jar traits, so its rate is exactly Formulas.CoinRate.
	local function spawn(h, p, line: string?, source: string?, traits)
		local m = h:System("Monsters"):Create(p, {
			line = line or "cindlet",
			rarity = 1,
			traits = traits or { 3, 4 },
			hidden = 5,
			variant = 0,
		}, source or "hatch", true)
		return m
	end

	local function passesChanged(h, p, money)
		h.kernel.Bus:Publish("PassesChanged", p, { passes = money.passes })
	end

	describe("Ranch", function()
		it("starts with one pen and reports capacity to Monsters", function()
			local h, p, Ranch = boot()
			local s = h:Section(p, "Ranch")
			expect(#s.pens).toBe(1)
			expect(s.pens[1].capacity).toBe(Economy.Pens.startCapacity)
			expect(s.pens[1].jarTier).toBe(1)
			expect(s.pens[1].theme).toBe("wood")
			expect(s.incubatorTier).toBe(1)
			expect(s.barnTier).toBe(1)
			expect(#s.garden.plots).toBe(Economy.Garden.plots[1])
			local client = h:Client(p)
			expect(client.profile.Ranch.offline).toBeNil() -- private
			expect(client.session.Ranch.capacity).toBe(h:System("Monsters"):Capacity(p))
			expect(client.session.Ranch.income).toBe(0)
			expect(Ranch:IncomePerSecond(p)).toBe(0)
		end)

		it("auto-places new monsters and fills the jar at their coin rate", function()
			local h, p, Ranch = boot()
			local m = spawn(h, p)
			local other = spawn(h, p, "mossbun", "test") -- not an auto-place source
			expect(Ranch:PenOf(p, m.id)).toBe(1)
			expect(Ranch:PenOf(p, other.id)).toBe(0)
			local rate = Formulas.CoinRate(m)
			local sess = h:Session(p, "Ranch")
			expect(sess.rates[1]).toBeNear(rate)
			expect(sess.income).toBeNear(rate)
			expect(sess.used).toBe(2)
			h:Advance(100)
			expect(Ranch:JarTotal(p)).toBe(math.floor(rate * 100))
			local collected
			h.kernel.Bus:Subscribe("JarCollected", function(_, d)
				collected = d
			end)
			local data = h:Call(p, "Ranch.Collect", { pen = 1 })
			expect(data.coins).toBe(math.floor(rate * 100))
			expect(collected.coins).toBe(data.coins)
			expect(h:Section(p, "Currency").coins).toBe(data.coins)
			expect(h:Section(p, "Progression").xp).toBe(Config.Unlocks.XP.collectJar)
			expect(h:Reject(p, "Ranch.Collect", { pen = 1 })).toBe("That jar is empty")
			expect(h:Reject(p, "Ranch.Collect", { pen = 2 })).toContain("don't own")
			expect(h:Reject(p, "Ranch.CollectAll")).toBe("Your jars are empty")
		end)

		it("caps the jar and the client sees the settled jar", function()
			local h, p, Ranch = boot()
			local m = spawn(h, p)
			local rate = Formulas.CoinRate(m)
			-- Pretend the jar has been filling for 2 hours (advancing the clock would also run
			-- online mood decay, which lowers the rate).
			h:Section(p, "Ranch").pens[1].jarAt -= 2 * 3600
			expect(Ranch:JarTotal(p)).toBe(math.floor(rate * Economy.JarTiers[1].seconds))
			h:Advance(Economy.RanchTickSeconds) -- a settle tick keeps the capped value
			expect(Ranch:JarTotal(p)).toBe(math.floor(rate * Economy.JarTiers[1].seconds))
			local client = h:Client(p)
			expect(client.session.Ranch.caps[1]).toBe(Economy.JarTiers[1].seconds)
			local Jar = t.Shared("Logic.Jar")
			local pen = client.profile.Ranch.pens[1]
			local live = Jar.Value(pen.jar, client.session.Ranch.rates[1], pen.jarAt, h.adapters.Clock.Now(), client.session.Ranch.caps[1])
			expect(math.floor(live)).toBe(Ranch:JarTotal(p))
		end)

		it("pays offline income up to the jar cap after 8 hours away", function()
			local h, p, Ranch = boot()
			h:Advance(Config.Eggs.Starter.hatchSeconds)
			local starter = h:Call(p, "Eggs.Hatch", { slot = 1 }).monster
			local rate = Formulas.CoinRate(starter)
			local p2 = h:Rejoin(p, 8 * 3600)
			local expected = math.floor(rate * Economy.JarTiers[1].seconds)
			expect(Ranch:JarTotal(p2)).toBe(expected)
			expect(h:Session(p2, "WelcomeBack").coins).toBe(expected)
			expect(h:Call(p2, "Ranch.CollectAll").coins).toBe(expected)
		end)

		it("values offline time at the rates saved on leave (passes load later)", function()
			local h, p, Ranch, money = boot()
			money.passes.doubleCoins = true
			passesChanged(h, p, money)
			local m = spawn(h, p)
			local rate = Formulas.CoinRate(m) * Economy.DoubleCoinsMult
			expect(h:Session(p, "Ranch").rates[1]).toBeNear(rate)
			h:Leave(p)
			money.passes.doubleCoins = false -- e.g. Monetization hasn't loaded passes yet on rejoin
			h.adapters.advance(1800)
			local p2 = h:Join(p.UserId, p.Name)
			expect(Ranch:JarTotal(p2)).toBe(math.floor(rate * 1800))
		end)

		it("applies rate modifiers per monster element and the Double Coins pass", function()
			local h, p, Ranch, money = boot()
			local fire = spawn(h, p, "cindlet")
			local leaf = spawn(h, p, "mossbun")
			local fireElement = Config.Species.ById.cindlet.elements[1]
			expect(Config.Species.ById.mossbun.elements[1] ~= fireElement).toBe(true)
			Ranch:RegisterRateModifier("test", function(_player, elements)
				return if table.find(elements, fireElement) then 0.5 else 0
			end)
			local ok, err = pcall(function()
				h.kernel.Bus:Publish("RateModifiersChanged", p, {})
				local base = Formulas.CoinRate(fire) * 1.5 + Formulas.CoinRate(leaf)
				expect(Ranch:IncomePerSecond(p)).toBeNear(base)
				money.passes.doubleCoins = true
				passesChanged(h, p, money)
				expect(Ranch:IncomePerSecond(p)).toBeNear(base * 2)
				expect(h:Client(p).session.Ranch.income).toBeNear(base * 2)
			end)
			Ranch:RegisterRateModifier("test", nil)
			assert(ok, err)
		end)

		it("settles the jar before a rate change so past income is kept", function()
			local h, p, Ranch = boot()
			local m = spawn(h, p)
			local rate = Formulas.CoinRate(m)
			h:Advance(100)
			local m2 = spawn(h, p) -- rate doubles from now on
			local rate2 = rate + Formulas.CoinRate(m2)
			h:Advance(100)
			expect(Ranch:JarTotal(p)).toBe(math.floor(rate * 100 + rate2 * 100))
		end)

		it("extends the jar cap with jar bonuses, VIP and Hoarder", function()
			local h, p, Ranch, money = boot()
			spawn(h, p)
			local base = Economy.JarTiers[1].seconds
			expect(h:Session(p, "Ranch").caps[1]).toBe(base)
			Ranch:RegisterJarBonus("test", function()
				return 900
			end)
			local ok, err = pcall(function()
				expect(h:Session(p, "Ranch").caps[1]).toBe(base + 900)
				money.passes.vip = true
				passesChanged(h, p, money)
				expect(h:Session(p, "Ranch").caps[1]).toBe(base + 900 + Economy.VipJarBonusSeconds)
				spawn(h, p, "mossbun", "hatch", { 9, 3 }) -- Hoarder: +30 min
				expect(h:Session(p, "Ranch").caps[1]).toBe(base + 900 + Economy.VipJarBonusSeconds + 1800)
			end)
			Ranch:RegisterJarBonus("test", nil)
			assert(ok, err)
		end)

		it("buys pens with the unlock level and coins", function()
			local h, p = boot()
			local changes = 0
			h.kernel.Bus:Subscribe("PlotChanged", function()
				changes += 1
			end)
			expect(h:Reject(p, "Ranch.BuyPen")).toBe("Unlocks at Ranch Level 6")
			levelTo(h, p, 6)
			expect(h:Reject(p, "Ranch.BuyPen")).toBe("Not enough coins")
			coins(h, p, Economy.Pens.buyCost[2])
			h:Advance(1)
			expect(h:Call(p, "Ranch.BuyPen").pen).toBe(2)
			expect(h:Section(p, "Currency").coins).toBe(0)
			expect(#h:Client(p).profile.Ranch.pens).toBe(2)
			expect(h:Section(p, "Ranch").pens[2].capacity).toBe(Economy.Pens.startCapacity)
			expect(changes).toBeAtLeast(1)
			h:Advance(1)
			expect(h:Reject(p, "Ranch.BuyPen")).toBe("Unlocks at Ranch Level 15")
		end)

		it("assigns monsters between pens and the barn with validation", function()
			local h, p, Ranch = boot()
			local M = h:System("Monsters")
			levelTo(h, p, 6)
			coins(h, p, Economy.Pens.buyCost[2])
			h:Call(p, "Ranch.BuyPen")
			local m = spawn(h, p, "cindlet", "test")
			h:Call(p, "Ranch.Assign", { id = m.id, pen = 2 })
			expect(Ranch:PenOf(p, m.id)).toBe(2)
			expect(M:Get(p, m.id).loc).toBe("pen")
			expect(M:Get(p, m.id).pen).toBe(2)
			expect(h:Session(p, "Ranch").rates[2]).toBeNear(Formulas.CoinRate(m))
			h:Call(p, "Ranch.Assign", { id = m.id, pen = 0 })
			expect(Ranch:PenOf(p, m.id)).toBe(0)
			expect(M:Get(p, m.id).loc).toBe("barn")
			expect(h:Session(p, "Ranch").rates[2]).toBe(0)
			expect(h:Reject(p, "Ranch.Assign", { id = m.id, pen = 3 })).toContain("don't own")
			expect(h:Reject(p, "Ranch.Assign", { id = "m999", pen = 1 })).toBe("That monster doesn't exist")
			expect(h:Reject(p, "Ranch.Assign", { id = m.id, pen = 6 })).toBe("BadRequest")
			-- Fill pen 1, then it refuses more.
			for _ = 1, Economy.Pens.startCapacity do
				spawn(h, p)
			end
			h:Advance(1)
			expect(h:Reject(p, "Ranch.Assign", { id = m.id, pen = 1 })).toBe("Pen 1 is full")
			-- Someone else's monster id is just "doesn't exist" for this player.
			local q = h:Join()
			expect(h:Reject(q, "Ranch.Assign", { id = m.id, pen = 1 })).toBe("That monster doesn't exist")
			expect(#Ranch:MonstersInPens(p)).toBe(Economy.Pens.startCapacity)
			expect(#Ranch:PublicPens(p)[1].monsters).toBe(Economy.Pens.startCapacity)
		end)

		it("puts overflow in the barn when every pen is full", function()
			local h, p, Ranch = boot()
			for _ = 1, Economy.Pens.startCapacity + 1 do
				spawn(h, p)
			end
			local inPens = Ranch:MonstersInPens(p)
			expect(#inPens).toBe(Economy.Pens.startCapacity)
		end)

		it("takes busy monsters out of pens and brings them back afterwards", function()
			local h, p, Ranch = boot()
			local M = h:System("Monsters")
			local m = spawn(h, p)
			local rate = Formulas.CoinRate(m)
			h:Advance(100)
			M:SetBusy(p, m.id, "expedition")
			expect(Ranch:PenOf(p, m.id)).toBe(0)
			expect(M:Get(p, m.id).loc).toBe("barn")
			expect(h:Session(p, "Ranch").rates[1]).toBe(0)
			local jar = Ranch:JarTotal(p)
			expect(jar).toBe(math.floor(rate * 100)) -- earned coins stay in the jar
			h:Advance(100)
			expect(Ranch:JarTotal(p)).toBe(jar)
			expect(h:Reject(p, "Ranch.Assign", { id = m.id, pen = 1 })).toContain("busy")
			M:SetBusy(p, m.id, false)
			expect(Ranch:PenOf(p, m.id)).toBe(1)
		end)

		it("removes sold monsters from their pen", function()
			local h, p, Ranch = boot()
			local m = spawn(h, p)
			spawn(h, p, "mossbun")
			h:Call(p, "Monsters.Sell", { ids = { m.id } })
			expect(Ranch:PenOf(p, m.id)).toBe(0)
			expect(#h:Section(p, "Ranch").pens[1].monsters).toBe(1)
			expect(h:Session(p, "Ranch").used).toBe(1)
		end)

		it("repairs pen lists on join (monsters gone or busy while away)", function()
			local h, p = boot()
			local m = spawn(h, p)
			local gone = spawn(h, p)
			local s = h:Section(p, "Ranch")
			-- Simulate data changed outside a session.
			h:Section(p, "Monsters").list[gone.id] = nil
			h:Section(p, "Monsters").list[m.id].busy = "breeding"
			local p2 = h:Rejoin(p, 60)
			s = h:Section(p2, "Ranch")
			expect(#s.pens[1].monsters).toBe(0)
			expect(h:Section(p2, "Monsters").list[m.id].loc).toBe("barn")
		end)

		it("upgrades pen capacity, jars, incubators, barn and garden", function()
			local h, p, Ranch = boot()
			local s = h:Section(p, "Ranch")
			expect(h:Reject(p, "Ranch.Upgrade", { target = "capacity" })).toBe("Choose a pen")
			expect(h:Reject(p, "Ranch.Upgrade", { target = "capacity", pen = 1 })).toBe("Not enough coins")
			coins(h, p, 1e9)
			local capBefore = h:System("Monsters"):Capacity(p)
			expect(h:Call(p, "Ranch.Upgrade", { target = "capacity", pen = 1 }).level).toBe(7)
			expect(h:System("Monsters"):Capacity(p)).toBe(capBefore + 1)
			h:Advance(1)
			spawn(h, p)
			expect(h:Call(p, "Ranch.Upgrade", { target = "jar", pen = 1 }).level).toBe(2)
			expect(h:Session(p, "Ranch").caps[1]).toBe(Economy.JarTiers[2].seconds)
			expect(h:Call(p, "Ranch.Upgrade", { target = "incubatorSpeed" }).level).toBe(2)
			expect(h:Session(p, "Eggs").speed).toBeNear(Economy.Incubators.speedTiers[2])
			h:Advance(1)
			expect(h:Call(p, "Ranch.Upgrade", { target = "barn" }).level).toBe(2)
			expect(h:Session(p, "Ranch").capacity).toBe(capBefore + 1 + Economy.Barn.capacity[2] - Economy.Barn.capacity[1])
			expect(h:Reject(p, "Ranch.Upgrade", { target = "garden" })).toBe("Unlocks at Ranch Level 5")
			levelTo(h, p, 5)
			h:Advance(1)
			expect(h:Call(p, "Ranch.Upgrade", { target = "garden" }).level).toBe(2)
			expect(#s.garden.plots).toBe(Economy.Garden.plots[2])
			-- Max levels.
			s.pens[1].capacity = Economy.Pens.maxCapacity
			s.pens[1].jarTier = #Economy.JarTiers
			s.incubatorTier = #Economy.Incubators.speedTiers
			h:Advance(1)
			expect(h:Reject(p, "Ranch.Upgrade", { target = "capacity", pen = 1 })).toContain("max capacity")
			expect(h:Reject(p, "Ranch.Upgrade", { target = "jar", pen = 1 })).toContain("fully upgraded")
			expect(h:Reject(p, "Ranch.Upgrade", { target = "incubatorSpeed" })).toContain("fully upgraded")
			expect(Ranch:IncomePerSecond(p)).toBeGreaterThan(0)
		end)

		it("adds the Big Barn pass to monster capacity", function()
			local h, p, _Ranch, money = boot()
			local before = h:System("Monsters"):Capacity(p)
			money.passes.bigBarn = true
			passesChanged(h, p, money)
			expect(h:System("Monsters"):Capacity(p)).toBe(before + Economy.Barn.bigBarnPassBonus)
			expect(h:Session(p, "Ranch").capacity).toBe(before + Economy.Barn.bigBarnPassBonus)
		end)

		it("places decor from storage and it cheers up the pen", function()
			local h, p = boot()
			local Shop = h:System("Shop")
			local M = h:System("Monsters")
			local inPen = spawn(h, p)
			local inBarn = spawn(h, p, "cindlet", "test")
			expect(h:Reject(p, "Ranch.PlaceDecor", { decor = "hay_bale", pen = 1 })).toContain("don't have that decor")
			Shop:AddDecor(p, "hay_bale", 4)
			for _ = 1, Config.Decor.PerPen do
				h:Call(p, "Ranch.PlaceDecor", { decor = "hay_bale", pen = 1 })
			end
			h:Advance(1)
			expect(h:Reject(p, "Ranch.PlaceDecor", { decor = "hay_bale", pen = 1 })).toContain("up to")
			expect(Shop:DecorCount(p, "hay_bale")).toBe(1)
			expect(#h:Client(p).profile.Ranch.pens[1].decor).toBe(Config.Decor.PerPen)
			h:Advance(Economy.Mood.decayEvery)
			local aura = Config.Decor.ById.hay_bale.mood * Config.Decor.PerPen
			expect(M:Get(p, inPen.id).mood - M:Get(p, inBarn.id).mood).toBe(aura)
			h:Call(p, "Ranch.PlaceDecor", { decor = "hay_bale", pen = 0 })
			expect(Shop:DecorCount(p, "hay_bale")).toBe(2)
			expect(h:Reject(p, "Ranch.PlaceDecor", { decor = "lantern", pen = 0 })).toContain("isn't placed")
			expect(h:Reject(p, "Ranch.PlaceDecor", { decor = "hay_bale", pen = 2 })).toContain("don't own")
		end)

		it("sets owned pen themes", function()
			local h, p, Ranch = boot()
			expect(h:Reject(p, "Ranch.SetPenTheme", { pen = 1, theme = "stone" })).toBe("You don't own that theme")
			h:System("Currency"):Add(p, "gems", 200, "test")
			h:Call(p, "Shop.BuyTheme", { theme = "stone" })
			h:Call(p, "Ranch.SetPenTheme", { pen = 1, theme = "stone" })
			expect(Ranch:PublicPens(p)[1].theme).toBe("stone")
			expect(h:Client(p).profile.Ranch.pens[1].theme).toBe("stone")
			expect(h:Reject(p, "Ranch.SetPenTheme", { pen = 2, theme = "wood" })).toContain("don't own")
		end)

		it("grows food in the garden, twice as fast in the rain", function()
			local weather = { id = "clear" }
			local h, p = boot({
				stubs = {
					Weather = {
						Current = function()
							return { id = weather.id, endsAt = 0 }
						end,
					},
				},
			})
			expect(h:Reject(p, "Ranch.Plant", { plot = 1, flavor = "sweet" })).toBe("Unlocks at Ranch Level 5")
			levelTo(h, p, 5)
			local data = h:Call(p, "Ranch.Plant", { plot = 1, flavor = "sweet" })
			expect(data.readyAt).toBe(h.adapters.Clock.Now() + Economy.Garden.growSeconds)
			expect(h:Reject(p, "Ranch.Plant", { plot = 1, flavor = "sour" })).toContain("already growing")
			expect(h:Reject(p, "Ranch.Plant", { plot = 3, flavor = "sour" })).toContain("locked")
			expect(h:Reject(p, "Ranch.Harvest", { plot = 1 })).toContain("isn't ready")
			expect(h:Reject(p, "Ranch.Harvest", { plot = 2 })).toContain("Nothing is growing")
			expect(h:Reject(p, "Ranch.Harvest", {})).toContain("Nothing is ready")
			h:Advance(Economy.Garden.growSeconds)
			local food = h:Call(p, "Ranch.Harvest", {}).food
			expect(food).toEqual({ sweet = Economy.Garden.yield })
			expect(h:Section(p, "Currency").food.sweet).toBe(Economy.Garden.yield)
			-- Rain: 300 s of rain count as 600 s of growth.
			weather.id = "rain"
			h:Call(p, "Ranch.Plant", { plot = 2, flavor = "spicy" })
			h:Advance(Economy.Garden.growSeconds / 2 + Economy.RanchTickSeconds)
			expect(h:Call(p, "Ranch.Harvest", { plot = 2 }).food).toEqual({ spicy = Economy.Garden.yield })
		end)

		it("auto-collects with the pass, except while Welcome Back is waiting", function()
			local h, p, Ranch, money = boot()
			money.passes.autoCollect = true
			local m = spawn(h, p)
			h:Advance(60)
			expect(h:Section(p, "Currency").coins).toBeAtLeast(math.floor(Formulas.CoinRate(m) * 50))
			expect(Ranch:JarTotal(p)).toBeLessThan(math.ceil(Formulas.CoinRate(m) * Economy.RanchTickSeconds) + 1)
			Ranch:HoldAutoCollect(p, true)
			local before = h:Section(p, "Currency").coins
			h:Advance(60)
			expect(h:Section(p, "Currency").coins).toBe(before)
		end)
	end)
end
