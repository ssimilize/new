--[[
	MarketClient (M3, update 1.3 · Market Day): the Market screen, PriceChart and the HUD
	entry points, driven through the real client (ClientHarness) like a player would.

	Tests that need the Market / PriceHistory server systems return early (pass) while those
	systems are not in the server Manifest; the integrator plugs them in and they run for real.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness

	local function serverHas(...): boolean
		local systems = t.Server("Manifest").Systems
		for _, name in { ... } do
			if not table.find(systems, name) then
				return false
			end
		end
		return true
	end

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	-- Max level, lots of coins, one monster of every species line and a few eggs.
	local function veteran(h, player)
		local Config = t.Shared("Config")
		h:System("Progression"):AddXP(player, 1e9, "test")
		h:System("Currency"):Add(player, "coins", 1e9, "test")
		local ids = {}
		for i, line in Config.Species.Lines do
			local stage = (i % 3) + 1
			local spec = { line = line.id, rarity = 2, stage = stage }
			if stage == 3 then
				spec.form = line.forms[3][1].id
			end
			local record = h:System("Monsters"):Create(player, spec, "test", true)
			table.insert(ids, record.id)
		end
		h:System("Eggs"):Add(player, "meadow", "test", 2)
		h:Step()
		return ids
	end

	local function coins(h, player): number
		return h:Section(player, "Currency").coins
	end

	local function monsterCount(h, player): number
		local n = 0
		for _ in h:Section(player, "Monsters").list do
			n += 1
		end
		return n
	end

	-- Sells a monster through the UI: Sell tab → Monsters pick mode → price → List.
	local function sellThroughUi(c, monsterId: string, price: string, clubOnly: boolean?)
		local screen = c:Open("Market", { tab = "sell" })
		c:Advance(0.5)
		c:Click(screen:FindFirstChild("PickMonster", true))
		c:Advance(0.5)
		expect(c.kernel.Router:Current()).toBe("Monsters")
		local monsters = c:Screen("Monsters")
		local cell = monsters:FindFirstChild(monsterId, true)
		expect(cell ~= nil).toBe(true)
		c:Click(cell:FindFirstChild("Tap"))
		c:Advance(1)
		expect(c.kernel.Router:Current()).toBe("Market")
		c:Type(screen:FindFirstChild("PriceBox", true), price)
		c:Advance(0.5)
		if clubOnly then
			c:Click(screen:FindFirstChild("ClubOnly", true))
			c:Advance(0.2)
		end
		c:Click(screen:FindFirstChild("List", true))
		c:Advance(1)
		return screen
	end

	local function clickDialogButton(c, text: string)
		local button = c:Button(text, c.kernel.UI.Top)
		if not button then
			error("no dialog button " .. text .. "; top shows: " .. table.concat(c:Texts(c.kernel.UI.Top), " | "), 2)
		end
		c:Click(button)
		c:Advance(1)
	end

	describe("Market client", function()
		it("opens the Market screen and shows its tabs (no server needed)", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			h:System("Progression"):AddXP(player, 1e9, "test")
			local c = ClientHarness.new(h, player)
			c:Advance(1)
			local screen = c:Open("Market")
			expect(screen ~= nil).toBe(true)
			c:Advance(1)
			expect(c:IsShown(screen)).toBe(true)
			expect(c:HasText("Browse", screen)).toBe(true)
			expect(c:HasText("Sell", screen)).toBe(true)
			expect(c:HasText("My listings", screen)).toBe(true)
			expect(c:HasText("Club post", screen)).toBe(false) -- not in a club
			expect(c:HasText("Cheapest first", screen)).toBe(true)
			c:Click(c:Button("Sell", screen))
			c:Advance(0.5)
			expect(c:HasText("Pick a monster", screen)).toBe(true)
			expect(c:HasText("Market tax 8%", screen)).toBe(true)
			c:Type(screen:FindFirstChild("PriceBox", true), "12k")
			c:Advance(0.2)
			c:Click(c:Button("My listings", screen))
			c:Advance(0.5)
			expect(c:HasText("/ 8 listed", screen)).toBe(true)
			c:Click(c:Button("Browse", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("Sort", true))
			c:Advance(0.5)
			expect(c:HasText("Priciest first", screen)).toBe(true)
			c:Close("Market")
			expectClean(c)
		end)

		it("keeps the market locked until its Ranch Level", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local c = ClientHarness.new(h, player)
			c:Advance(1)
			local screen = c:Open("Market")
			c:Advance(0.5)
			local level = t.Shared("Config").Unlocks.Features.market
			expect(c:HasText("Unlocks at Ranch Level " .. level, screen)).toBe(true)
			expectClean(c)
		end)

		it("moves Settings to a gear by the level bar and adds a Market button", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local c = ClientHarness.new(h, player)
			c:Advance(1)
			local hud = c.kernel:GetController("Hud")
			local gear = hud:GetTarget("Settings")
			expect(gear ~= nil).toBe(true)
			expect(gear.Parent.Name).toBe("Hud")
			c:Click(gear)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Settings")
			c:Close()
			local market = hud:GetTarget("Market")
			expect(market ~= nil).toBe(true)
			expect(market.Parent.Name).toBe("LeftStack")
			c:Click(market) -- locked for a new player
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBeNil()
			h:System("Progression"):AddXP(player, 1e9, "test")
			c:Advance(1)
			c:Click(market)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Market")
			expectClean(c)
		end)

		it("shows Market.MailCollected as a toast", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local c = ClientHarness.new(h, player)
			c:Advance(1)
			c.world:Run(function()
				local handlers = c.kernel.Net._handlers["Market.MailCollected"]
				for _, fn in handlers do
					fn({ coins = 11040, items = {}, sold = { { key = "m:cindlet:3:1", price = 12000, proceeds = 11040 } }, returned = 1 })
				end
			end)
			c:Advance(0.3)
			expect(c:HasText("Your Rare Golden Cindlet sold for 12K! +11K coins", c.kernel.UI.Overlay)).toBe(true)
			expect(c:HasText("1 market item came back to you", c.kernel.UI.Overlay)).toBe(true)
			expectClean(c)
		end)

		it("draws a price series with frames, and parses prices", function()
			local h = TestKernel.new({ systems = {} })
			local c = ClientHarness.new(h, h:Join())
			local chart, Screen
			c.world:Run(function()
				local PriceChart = c:require(c.clientFolder.UI.Components.PriceChart)
				chart = PriceChart.new({ Parent = c.kernel.UI.Overlay })
				chart:SetSeries({
					{ day = 100, count = 2, low = 900, high = 1200, avg = 1000 },
					{ day = 103, count = 1, low = 1500, high = 1500, avg = 1500 },
				})
				Screen = c:require(c.clientFolder.UI.Screens.Market)
			end)
			c:Settle()
			local bars = chart.Root:FindFirstChild("Bars", true)
			expect(bars:FindFirstChild("Day100") ~= nil).toBe(true)
			expect(bars:FindFirstChild("Day103") ~= nil).toBe(true)
			expect(bars.Day100:FindFirstChild("Range") ~= nil).toBe(true)
			expect(bars.Day103:FindFirstChild("Range")).toBeNil()
			expect(chart.Root:FindFirstChild("Message", true).Visible).toBe(false)
			expect(chart.Root:FindFirstChild("Summary", true).Text).toBe("Last avg 1.5K · 3 sales in 7d")
			for _, d in chart.Root:GetDescendants() do
				if d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("ViewportFrame") then
					error("PriceChart must be drawn with frames only")
				end
			end
			c.world:Run(function()
				chart:SetSeries({})
			end)
			expect(chart.Root:FindFirstChild("Message", true).Text).toBe("No sales yet")
			expect(#bars:GetChildren()).toBe(0)

			expect(Screen.parsePrice("12000")).toBe(12000)
			expect(Screen.parsePrice("12,000")).toBe(12000)
			expect(Screen.parsePrice("12k")).toBe(12000)
			expect(Screen.parsePrice("1.5M")).toBe(1500000)
			expect(Screen.parsePrice("abc")).toBeNil()
			expect(Screen.parsePrice("")).toBeNil()
			expect(Screen.suggest({
				{ day = 1, count = 10, avg = 50000 }, -- older than a week: ignored
				{ day = 20, count = 1, avg = 1000 },
				{ day = 21, count = 3, avg = 2000 },
			}, 2000)).toBe(1750)
			expect(Screen.suggest({}, 4000)).toBe(4000)
			expect(Screen.suggest({}, nil)).toBeNil()
			expectClean(c)
		end)

		-- ─── Flows against the real Market / PriceHistory systems ───────────────────────

		it("sells a monster and a second player on the server buys it", function()
			if not serverHas("Market", "PriceHistory") then
				return
			end
			local Market = t.Shared("Config").Market
			local h = TestKernel.new({ systems = allSystems() })
			local seller = h:Join(9101, "Sally")
			local ids = veteran(h, seller)
			local buyer = h:Join(9102, "Bram")
			veteran(h, buyer)
			local a = ClientHarness.new(h, seller)
			local b = ClientHarness.new(h, buyer)
			a:Advance(1)

			local sold = h:Section(seller, "Monsters").list[ids[1]]
			local line = sold.line
			local sellerCount = monsterCount(h, seller)
			local screen = sellThroughUi(a, ids[1], "5000")
			expect(h:Section(seller, "Monsters").list[ids[1]]).toBeNil()
			expect(monsterCount(h, seller)).toBe(sellerCount - 1)
			local listingId = h:Section(seller, "Market").listings[1]
			expect(listingId ~= nil).toBe(true)
			-- After listing, the screen shows My listings with the new row.
			a:Advance(1)
			expect(screen:FindFirstChild("Listing_" .. listingId, true) ~= nil).toBe(true)

			-- The buyer browses, opens the confirm (price + chart) and buys.
			local buyerCoins, buyerCount = coins(h, buyer), monsterCount(h, buyer)
			-- The seller is on this server, so their mail can arrive as soon as the sale lands.
			local sellerCoins = coins(h, seller)
			local browse = b:Open("Market")
			b:Advance(1)
			local row = browse:FindFirstChild("Listing_" .. listingId, true)
			expect(row ~= nil).toBe(true)
			b:Click(row:FindFirstChild("Buy"))
			b:Advance(1)
			expect(b.kernel.UI.Top:FindFirstChild("PriceChart", true) ~= nil).toBe(true)
			expect(b:HasText("5,000", b.kernel.UI.Top)).toBe(true)
			clickDialogButton(b, "Buy ·")
			b:Advance(1)
			expect(coins(h, buyer)).toBe(buyerCoins - 5000)
			expect(monsterCount(h, buyer)).toBe(buyerCount + 1)
			local got = false
			for _, m in h:Section(buyer, "Monsters").list do
				if m.line == line and m.rarity == sold.rarity and not table.find(ids, m.id) then
					got = true
				end
			end
			expect(got).toBe(true)
			expect(browse:FindFirstChild("Listing_" .. listingId, true)).toBeNil()

			-- The seller's mail arrives within one sync (at once here: same server) and shows as a
			-- toast, which only stays up a few seconds, so watch for it from the moment of the sale.
			local arrived, toasted = false, false
			for _ = 1, (Market.MailSyncSeconds + 5) * 2 do
				toasted = toasted or a:HasText("sold for 5K", a.kernel.UI.Overlay)
				for _, e in a.events do
					if e.name == "Market.MailCollected" then
						arrived = true
					end
				end
				if arrived and toasted then
					break
				end
				a:Advance(0.5)
			end
			expect(arrived).toBe(true)
			expect(toasted).toBe(true)
			expect(coins(h, seller)).toBe(sellerCoins + Market.Proceeds(5000, false))
			expectClean(a)
			expectClean(b)
		end)

		it("cancels a listing from My listings and gets the monster back", function()
			if not serverHas("Market") then
				return
			end
			local h = TestKernel.new({ systems = allSystems() })
			local seller = h:Join(9201, "Cora")
			local ids = veteran(h, seller)
			local c = ClientHarness.new(h, seller)
			c:Advance(1)
			local screen = sellThroughUi(c, ids[2], "2500")
			expect(h:Section(seller, "Monsters").list[ids[2]]).toBeNil()
			local listingId = h:Section(seller, "Market").listings[1]
			c:Advance(1)
			local row = screen:FindFirstChild("Listing_" .. listingId, true)
			expect(row ~= nil).toBe(true)
			expect(c:HasText("left", row)).toBe(true)
			c:Click(row:FindFirstChild("Cancel"))
			c:Advance(0.5)
			clickDialogButton(c, "Take it back")
			c:Advance(1)
			local back = false
			for _, m in h:Section(seller, "Monsters").list do
				if m.line == t.Shared("Config").Species.Lines[2].id then
					back = true
				end
			end
			expect(back).toBe(true)
			expect(#h:Section(seller, "Market").listings).toBe(0)
			expectClean(c)
		end)

		it("posts to the club trading post, which only club members see", function()
			if not serverHas("Market", "Clubs") then
				return
			end
			local h = TestKernel.new({ systems = allSystems() })
			local owner = h:Join(9301, "Olga")
			local ids = veteran(h, owner)
			local member = h:Join(9302, "Milo")
			veteran(h, member)
			local outsider = h:Join(9303, "Otto")
			veteran(h, outsider)
			h:Call(owner, "Clubs.Create", { name = "Market Folk", tag = "MKT", color = 1, emblem = "star", open = true })
			local clubId = h:System("Clubs"):ClubOf(owner)
			h:Call(member, "Clubs.Join", { code = clubId })
			local a = ClientHarness.new(h, owner)
			local m = ClientHarness.new(h, member)
			local o = ClientHarness.new(h, outsider)
			a:Advance(2)

			local screen = sellThroughUi(a, ids[3], "4000", true)
			expect(screen ~= nil).toBe(true)
			local listingId = h:Section(owner, "Market").listings[1]
			expect(listingId ~= nil).toBe(true)

			local post = m:Open("Market", { tab = "club" })
			m:Advance(1)
			expect(m:HasText("Club members only", post)).toBe(true)
			expect(post:FindFirstChild("Listing_" .. listingId, true) ~= nil).toBe(true)

			local browse = o:Open("Market")
			o:Advance(1)
			expect(o:HasText("Club post", browse)).toBe(false)
			expect(browse:FindFirstChild("Listing_" .. listingId, true)).toBeNil()
			expectClean(a)
			expectClean(m)
			expectClean(o)
		end)

		it("draws the price chart on the Sell tab after a sale", function()
			if not serverHas("Market", "PriceHistory") then
				return
			end
			local h = TestKernel.new({ systems = allSystems() })
			local Market = t.Shared("Config").Market
			local seller = h:Join(9401, "Pia")
			local ids = veteran(h, seller)
			local buyer = h:Join(9402, "Quin")
			local buyerIds = veteran(h, buyer)
			local key = Market.ItemKey("monster", h:Section(seller, "Monsters").list[ids[4]])
			local a = ClientHarness.new(h, seller)
			a:Advance(1)
			sellThroughUi(a, ids[4], "3000")
			local listingId = h:Section(seller, "Market").listings[1]
			h:Call(buyer, "Market.Buy", { listing = listingId, price = 3000 })
			h:Advance(2)
			local b = ClientHarness.new(h, buyer)
			b:Advance(1)
			local boughtId
			for id, m in h:Section(buyer, "Monsters").list do
				if not table.find(buyerIds, id) and Market.ItemKey("monster", m) == key then
					boughtId = id
				end
			end
			expect(boughtId ~= nil).toBe(true)
			local screen = sellThroughUi(b, boughtId, "") -- pick only: an empty price does not list
			b:Advance(1)
			local chart = screen:FindFirstChild("PriceChart", true)
			expect(chart ~= nil).toBe(true)
			expect(#chart:FindFirstChild("Bars", true):GetChildren()).toBeGreaterThan(0)
			expect(b:HasText("Suggested: 3K", screen)).toBe(true)
			expectClean(a)
			expectClean(b)
		end)
	end)
end
