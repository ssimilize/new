--[[
	OrdersClient (update 3.8): Ranch Orders through the real client (ClientHarness): the Orders
	tab on the Job Board and its lock, the HUD's "Board" button, a monster picked by real clicks
	with the cheapest qualifying one first, the confirm that names it, the pay, the daily
	reroll, and the orders in Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Formulas = t.Shared("Logic.Formulas")
	local OrdersLogic = t.Shared("Logic.Orders")

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

	local function genes(spd: number)
		local g = {}
		for _, stat in Config.Genetics.Stats do
			g[stat] = { 1, 1 }
		end
		g.spd = { spd, spd }
		return g
	end

	local function adult(h, p, rarity: number, spd: number)
		local m = h:System("Monsters")
			:Create(p, { line = "cindlet", rarity = rarity, stage = 3, traits = { 7, 12 }, hidden = 9 }, "test", true)
		m.genes = genes(spd)
		return m
	end

	local function spdOrder(i: number)
		return { id = "t-" .. i, kind = "monster", difficulty = "medium", stat = "spd", grade = "B", seed = 10 + i, filled = false }
	end

	-- Puts three known SPD-B orders on the board; the rejoin sends them to the client.
	local function knownOrders(h, p)
		local s = h:Section(p, "Orders")
		for i = 1, Config.Orders.PerDay do
			s.list[i] = spdOrder(i)
		end
		return h:Rejoin(p, 1)
	end

	-- The shown button whose whole text is `text` (the dialog's title also says "Hand over").
	local function exactButton(c, text: string, root)
		for _, b in c:Buttons(root) do
			if ClientHarness.buttonText(b) == text then
				return b
			end
		end
		return nil
	end

	local function hudBoard(c)
		return c.kernel.UI.Hud:FindFirstChild("Jobs", true)
	end

	local function ordersTab(c, screen, label: string?)
		c:Click(c:Button(label or "Orders", screen:FindFirstChild("Tabs", true)))
		c:Advance(0.5)
	end

	describe("Ranch Orders", function()
		it("sits on the Board's Orders tab and stays locked before Level 10", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 6)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			expect(ClientHarness.buttonText(hudBoard(c))).toBe("Board")
			local screen = c:Open("Jobs")
			c:Advance(0.5)
			expect(c:HasText("Pick a job", screen)).toBe(true)
			ordersTab(c, screen)
			expect(c:HasText("Unlocks at Ranch Level 10", screen)).toBe(true)
			expect(c:HasText("Pick a job", screen)).toBe(false)
			c:Click(c:Button("Jobs", screen:FindFirstChild("Tabs", true)))
			c:Advance(0.5)
			expect(c:HasText("Pick a job", screen)).toBe(true)
			expectClean(c)
		end)

		it("picks the cheapest qualifying monster first, confirms by name, then pays", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 10)
			local cheap = adult(h, p, 1, 5)
			local dear = adult(h, p, 5, 6)
			local weak = adult(h, p, 1, 2)
			expect(Formulas.SellPrice(cheap)).toBeLessThan(Formulas.SellPrice(dear))
			p = knownOrders(h, p)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Jobs")
			c:Advance(0.5)
			ordersTab(c, screen)
			expect(c:HasText("A Teen or Adult with SPD grade B or better", screen)).toBe(true)
			expect(c:HasText("Monsters that qualify: 2", screen)).toBe(true)

			c:Click(screen:FindFirstChild("Order1", true):FindFirstChild("Fill", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local picker = c:Screen("Monsters")
			expect(picker:FindFirstChild(weak.id, true)).toBeNil()
			local first, second = picker:FindFirstChild(cheap.id, true), picker:FindFirstChild(dear.id, true)
			expect(first.LayoutOrder).toBeLessThan(second.LayoutOrder)
			c:Click(first:FindFirstChild("Tap"))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Jobs")
			local top = c.kernel.UI.Top
			expect(c:HasText(Formulas.DisplayName(cheap) .. " leaves your ranch for good", top)).toBe(true)
			expect(h:System("Monsters"):Get(p, cheap.id) ~= nil).toBe(true)

			local cur = h:Section(p, "Currency")
			local coins, gems = cur.coins, cur.gems
			local expected = OrdersLogic.Coins(h:System("Monsters"):Get(p, cheap.id))
			c:Click(exactButton(c, "Hand over", top))
			c:Advance(1)
			expect(h:System("Monsters"):Get(p, cheap.id)).toBeNil()
			expect(cur.coins - coins).toBeNear(expected, math.max(2, expected * 0.05))
			expect(cur.gems - gems).toBe(Config.Orders.Difficulty.medium.gems)
			expect(h:Section(p, "Orders").list[1].filled).toBe(true)
			expect(c:HasText("Order filled", screen:FindFirstChild("Order1", true))).toBe(true)

			-- The free reroll: once, then the buttons go.
			c:Click(screen:FindFirstChild("Order2", true):FindFirstChild("Reroll", true))
			c:Advance(1)
			expect(h:Section(p, "Orders").rerolls).toBe(1)
			expect(screen:FindFirstChild("Order3", true):FindFirstChild("Reroll", true)).toBeNil()
			expectClean(c)
		end)

		it("shows the orders and the Board in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 10)
			adult(h, p, 1, 5)
			p = knownOrders(h, p)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			expect(ClientHarness.buttonText(hudBoard(c))).toBe("Tablón")
			local screen = c:Open("Jobs")
			c:Advance(0.5)
			ordersTab(c, screen, "Pedidos")
			expect(c:HasText("Un Joven o Adulto con VEL en grado B o mejor", screen)).toBe(true)
			expect(c:HasText("Elegir monstruo", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
