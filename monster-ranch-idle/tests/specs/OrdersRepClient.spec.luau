--[[
	OrdersRepClient (update 3.9): buyer reputation through the real client (ClientHarness): the
	Orders tab's Buyers panel (levels, bars, the next perk), each card's buyer level and the
	favourite order's card, the level-up toast after a fill by real clicks, and Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Formulas = t.Shared("Logic.Formulas")

	local Rules = Config.Orders

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

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function adult(h, p, rarity: number, spd: number)
		local m = h:System("Monsters")
			:Create(p, { line = "cindlet", rarity = rarity, stage = 3, traits = { 7, 12 }, hidden = 9 }, "test", true)
		local g = {}
		for _, stat in Config.Genetics.Stats do
			g[stat] = { 1, 1 }
		end
		g.spd = { spd, spd }
		m.genes = g
		return m
	end

	-- Three known SPD-B orders from `buyers[i]` and the given reputation; the rejoin sends them.
	local function board(h, p, buyers, rep, favourite: string?)
		local s = h:Section(p, "Orders")
		for i = 1, Rules.PerDay do
			s.list[i] = {
				id = "t-" .. i,
				kind = "monster",
				difficulty = "medium",
				stat = "spd",
				grade = "B",
				seed = 10 + i,
				buyer = buyers[i],
				filled = false,
			}
		end
		if favourite then
			s.list[Rules.PerDay + 1] = {
				id = "t-fav",
				kind = "monster",
				difficulty = "easy",
				stat = "spd",
				grade = "C",
				seed = 99,
				buyer = favourite,
				favourite = true,
				filled = false,
			}
			s.favDay = s.day
		end
		s.rep = rep
		return h:Rejoin(p, 1)
	end

	local function open(h, p, opts)
		local c = ClientHarness.new(h, p, opts)
		c:Advance(1)
		local screen = c:Open("Jobs")
		c:Advance(0.5)
		return c, screen
	end

	local function ordersTab(c, screen, label: string?)
		c:Click(c:Button(label or "Orders", screen:FindFirstChild("Tabs", true)))
		c:Advance(0.5)
	end

	local function exactButton(c, text: string, root)
		for _, b in c:Buttons(root) do
			if ClientHarness.buttonText(b) == text then
				return b
			end
		end
		return nil
	end

	describe("Buyer reputation", function()
		it("shows every buyer's level, bar and next perk in the Buyers panel", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 10)
			p = board(h, p, { "rosa", "pip", "milo" }, { rosa = 20, hale = 70, pip = 3 })
			local c, screen = open(h, p)
			ordersTab(c, screen)
			local toggle = screen:FindFirstChild("BuyersToggle", true)
			expect(c:IsShown(toggle)).toBe(true)
			expect(screen:FindFirstChild("Buyer_rosa", true)).toBeNil()
			c:Click(toggle)
			c:Advance(0.5)
			expect(screen:FindFirstChild("Order1", true)).toBeNil()
			for _, id in Rules.BuyerIds do
				local card = screen:FindFirstChild("Buyer_" .. id, true)
				expect(card ~= nil).toBe(true)
				expect(c:HasText(Rules.BuyerById[id].name, card)).toBe(true)
			end
			local rosa = screen:FindFirstChild("Buyer_rosa", true)
			expect(c:HasText("Level 2", rosa)).toBe(true)
			expect(c:HasText("20 / 35", rosa)).toBe(true)
			expect(c:HasText("Level 3: " .. Rules.Rep.Perks[3], rosa)).toBe(true)
			expect(rosa:FindFirstChild("RepBar", true).Fill.Size.X.Scale).toBeNear(0.25, 0.001)
			local pip = screen:FindFirstChild("Buyer_pip", true)
			expect(c:HasText("Level 0", pip)).toBe(true)
			expect(c:HasText("3 / 5", pip)).toBe(true)
			expect(c:HasText("Level 1: +10% coins on their monster orders", pip)).toBe(true)
			local hale = screen:FindFirstChild("Buyer_hale", true)
			expect(c:HasText("Level 4", hale)).toBe(true)
			expect(c:HasText("Max level", hale)).toBe(true)
			expect(c:HasText("All perks earned", hale)).toBe(true)
			expect(hale:FindFirstChild("RepBar", true).Fill.Size.X.Scale).toBe(1)

			c:Click(exactButton(c, "Show orders", screen))
			c:Advance(0.5)
			expect(screen:FindFirstChild("Order1", true) ~= nil).toBe(true)
			expect(c:IsShown(screen:FindFirstChild("Buyers", true))).toBe(false)

			-- The Jobs tab hides the toggle.
			c:Click(c:Button("Jobs", screen:FindFirstChild("Tabs", true)))
			c:Advance(0.5)
			expect(c:IsShown(toggle)).toBe(false)
			expectClean(c)
		end)

		it("shows each card's buyer level, the coin bonus and the favourite order", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 10)
			p = board(h, p, { "rosa", "wren", "milo" }, { rosa = 5, wren = 40 }, "wren")
			local c, screen = open(h, p)
			ordersTab(c, screen)
			local cards = {}
			for i = 1, Rules.PerDay + 1 do
				cards[i] = screen:FindFirstChild("Order" .. i, true)
				expect(cards[i] ~= nil).toBe(true)
			end
			expect(c:HasText("Level 1", cards[1]:FindFirstChild("BuyerLevel", true))).toBe(true)
			expect(c:HasText("+10%", cards[1])).toBe(true)
			expect(c:HasText("Level 3", cards[2]:FindFirstChild("BuyerLevel", true))).toBe(true)
			expect(c:HasText("+25%", cards[2])).toBe(true)
			expect(c:HasText("Level 0", cards[3]:FindFirstChild("BuyerLevel", true))).toBe(true)
			expect(c:HasText("Plus coins: 3 times its sell price", cards[3])).toBe(true)
			expect(c:HasText("+", cards[3]:FindFirstChild("Coins", true))).toBe(false)
			local fav = cards[Rules.PerDay + 1]
			expect(c:HasText("Captain Wren", fav)).toBe(true)
			expect(fav:FindFirstChild("Favourite", true) ~= nil).toBe(true)
			expect(fav:FindFirstChild("Reroll", true)).toBeNil()
			expect(cards[1]:FindFirstChild("Favourite", true)).toBeNil()
			expectClean(c)
		end)

		it("toasts the buyer's new level after a fill by real clicks", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 10)
			local m = adult(h, p, 1, 5)
			adult(h, p, 1, 1)
			p = board(h, p, { "rosa", "pip", "milo" }, { rosa = 3 })
			local c, screen = open(h, p)
			ordersTab(c, screen)
			c:Click(screen:FindFirstChild("Order1", true):FindFirstChild("Fill", true))
			c:Advance(0.5)
			local picker = c:Screen("Monsters")
			c:Click(picker:FindFirstChild(m.id, true):FindFirstChild("Tap"))
			c:Advance(1)
			local top = c.kernel.UI.Top
			expect(c:HasText(Formulas.DisplayName(m) .. " leaves your ranch for good", top)).toBe(true)
			c:Click(exactButton(c, "Hand over", top))
			c:Advance(1)
			expect(h:Section(p, "Orders").rep.rosa).toBe(5)
			expect(c:HasText("Farmer Rosa is now a level 1 buyer!")).toBe(true)
			expect(c:HasText("Level 1", screen:FindFirstChild("Order1", true):FindFirstChild("BuyerLevel", true))).toBe(true)
			expectClean(c)
		end)

		it("shows the Buyers panel and the card levels in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 10)
			p = board(h, p, { "rosa", "pip", "milo" }, { rosa = 20 })
			local c, screen = open(h, p, { localeId = "es-mx" })
			ordersTab(c, screen, "Pedidos")
			expect(c:HasText("Nivel 2", screen:FindFirstChild("Order1", true))).toBe(true)
			c:Click(c:Button("Compradores", screen))
			c:Advance(0.5)
			local rosa = screen:FindFirstChild("Buyer_rosa", true)
			expect(c:HasText("Granjera Rosa", rosa)).toBe(true)
			expect(c:HasText("Nivel 2", rosa)).toBe(true)
			expect(c:HasText("Nivel 3: +25% de monedas y un pedido diario de comprador favorito", rosa)).toBe(true)
			expect(c:HasText("Ver pedidos", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
