--[[
	MerchantClient (update 3.11 · Travelling Merchant) through the real client (ClientHarness,
	real clicks): the caravan and its "Trade" prompt while the merchant is here, the stock cards,
	buying with coins and with a fish barter, the HUD chip, the closed screen's countdown and the
	caravan arriving, and a Trait Scroll spent from Monster Detail.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Merchant")

	local Rules = Config.Merchant
	local START = 1790000000

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

	local function clickable(gui)
		if gui:IsA("GuiButton") then
			return gui
		end
		return gui:FindFirstChildWhichIsA("GuiButton", true)
	end

	local function visitWith(offerId: string): number
		local k = Logic.Visit(START)
		for i = 0, 2000 do
			if Logic.Find(k + i, offerId) then
				return (k + i) * Rules.Cycle + Rules.Offset + 60
			end
		end
		error("no visit sells " .. offerId)
	end

	local function payIndex(slot, kind: string): number
		for i, pay in slot.pay do
			if pay.kind == kind then
				return i
			end
		end
		error("no " .. kind .. " price")
	end

	local function boot(at: number)
		local h = TestKernel.new({ systems = allSystems(), startTime = at })
		local p = h:Join()
		levelTo(h, p, 20)
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		return h, p, c
	end

	describe("Travelling Merchant", function()
		it("parks the caravan with a Trade prompt, shows the stock and sells for coins and for fish", function()
			local h, p, c = boot(visitWith("seed_pouch"))
			local merchant = c.kernel:GetController("Merchant")
			local caravan = merchant.Caravan()
			expect(caravan ~= nil).toBe(true)
			expect(caravan:IsDescendantOf(c.world.workspace)).toBe(true)
			expect(caravan:FindFirstChild("MerchantFigure") ~= nil).toBe(true)
			-- The HUD chip counts down to the departure.
			expect(c:HasText("Merchant leaves")).toBe(true)

			local prompt = merchant.Prompt()
			expect(prompt.ActionText).toBe("Trade")
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Merchant")
			local screen = c:Screen("Merchant")
			local at = Logic.At(h.adapters.Clock.Now())
			local stock = Logic.Stock(at.visit)
			for _, slot in stock do
				local card = screen:FindFirstChild("Offer_" .. slot.offer, true)
				expect(card ~= nil).toBe(true)
				expect(c:HasText(slot.name, card)).toBe(true)
			end
			expect(c:HasText("The merchant leaves in", screen)).toBe(true)

			local slot = Logic.Find(at.visit, "seed_pouch")
			local coinsAt = payIndex(slot, "coins")
			local income = h:System("Ranch"):IncomePerSecond(p)
			local price = Logic.CoinPrice(income, slot.pay[coinsAt].seconds)
			local cur = h:Section(p, "Currency")
			cur.coins = price + 5
			c:Advance(0.5)
			local card = screen:FindFirstChild("Offer_seed_pouch", true)
			local payButton = card:FindFirstChild("Pay" .. coinsAt, true)
			expect(c:HasText(Logic.PayText(slot.pay[coinsAt], price), card)).toBe(true)
			c:Click(clickable(payButton))
			c:Advance(0.5)
			expect(cur.coins).toBe(5)
			expect(h:Section(p, "Kitchen").seeds).toBe(slot.amount)
			card = screen:FindFirstChild("Offer_seed_pouch", true)
			expect(c:HasText(string.format("1/%d bought this visit", slot.limit), card)).toBe(true)

			-- The barter: fish from the Fishing Pond.
			local fishAt = payIndex(slot, "fish")
			local need = slot.pay[fishAt].amount
			local pond = h:Section(p, "Fishing")
			pond.fish = { [Config.Fishing.Ids[1]] = need }
			c:Advance(1)
			card = screen:FindFirstChild("Offer_seed_pouch", true)
			expect(c:HasText(Logic.PayText(slot.pay[fishAt], need), card)).toBe(true)
			c:Click(clickable(card:FindFirstChild("Pay" .. fishAt, true)))
			c:Advance(0.5)
			expect(pond.fish[Config.Fishing.Ids[1]]).toBe(nil)
			expect(h:Section(p, "Kitchen").seeds).toBe(2 * slot.amount)
			expect(h:Section(p, "Merchant").bought.seed_pouch).toBe(2)
			expectClean(c)
		end)

		it("shows when the caravan returns while it is away, then parks it on arrival", function()
			local k = Logic.Visit(START)
			local arrives = (k + 1) * Rules.Cycle + Rules.Offset
			local h, _, c = boot(arrives - 30)
			local merchant = c.kernel:GetController("Merchant")
			expect(merchant.Caravan()).toBe(nil)
			expect(merchant.Prompt()).toBe(nil)
			local screen = c:Open("Merchant")
			c:Advance(1)
			expect(screen:FindFirstChild("Closed", true).Visible).toBe(true)
			expect(c:HasText("Back in", screen)).toBe(true)
			expect(screen:FindFirstChild("Offer_" .. Logic.Stock(k + 1)[1].offer, true)).toBe(nil)

			c:Advance(40, 1)
			expect(merchant.Caravan() ~= nil).toBe(true)
			expect(screen:FindFirstChild("Offer_" .. Logic.Stock(k + 1)[1].offer, true) ~= nil).toBe(true)
			expect(Logic.At(h.adapters.Clock.Now()).present).toBe(true)
			expectClean(c)
		end)

		it("spends a Trait Scroll from Monster Detail on a visible trait", function()
			local h, p, c = boot(START)
			local m = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 2, stage = 3, variant = 0 }, "test", true)
			c:Advance(1)
			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("MonsterDetail")
			expect(detail:FindFirstChild("RerollTrait", true)).toBe(nil)

			h:Section(p, "Merchant").scrolls = 1
			h.kernel.State:Dirty(p, { "profile", "Merchant", "scrolls" })
			c:Advance(1)
			local button = detail:FindFirstChild("RerollTrait", true)
			expect(button ~= nil).toBe(true)
			-- The trait chips beside it keep their tap button out of the row's layout; laid out, it
			-- stretched each chip to ~680 px and pushed this button off-screen (found in Studio).
			local chips = 0
			for _, chip in button.Parent:GetChildren() do
				if chip.Name == "Chip" then
					chips += 1
					expect(chip:FindFirstChild("Tap")).toBe(nil)
					expect(chip:FindFirstChild("Tap", true) ~= nil).toBe(true)
				end
			end
			expect(chips > 0).toBe(true)
			-- Traits, the hidden trait, this button and Dojo techniques overflow the column: the row scrolls.
			expect(button.Parent:IsA("ScrollingFrame")).toBe(true)
			c:Click(clickable(button))
			c:Advance(0.5)
			expect(c:HasText("Trait Scrolls: 1", detail)).toBe(true)
			local expected = Logic.Reroll(m, 1, Logic.ScrollSeed(p.UserId, m, 0))
			c:Click(clickable(detail:FindFirstChild("Reroll1", true)))
			c:Advance(1)
			expect(m.traits[1]).toBe(expected)
			expect(h:Section(p, "Merchant").scrolls).toBe(0)
			expect(detail:FindFirstChild("RerollTrait", true)).toBe(nil)
			expectClean(c)
		end)
	end)
end
