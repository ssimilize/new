--[[
	Merchant (update 3.11 · Travelling Merchant) on the server: the visit schedule and its Calendar
	rows, the same stock for everyone, per-visit buy limits, every way to pay (all or nothing),
	delivery of seeds, bait, scrolls, decor, eggs and shovels (a DigSite stand-in), the Trait Scroll
	reroll rules, the unlock gate and the weekly goal.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Merchant")
	local Calendar = t.Shared("Logic.Calendar")

	local Rules = Config.Merchant
	local START = 1790000000

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "Kitchen", "Fishing", "Merchant" }

	-- The first visit from START whose stock holds `offerId` (a minute into it).
	local function visitWith(offerId: string): number
		local k = Logic.Visit(START)
		for i = 0, 2000 do
			if Logic.Find(k + i, offerId) then
				return (k + i) * Rules.Cycle + Rules.Offset + 60
			end
		end
		error("no visit sells " .. offerId)
	end

	local function boot(opts)
		opts = opts or {}
		local systems = table.clone(SYSTEMS)
		for _, name in opts.extra or {} do
			table.insert(systems, name)
		end
		local h = TestKernel.new({ systems = systems, startTime = opts.at or START, stubs = opts.stubs })
		local p = h:Join(opts.userId)
		levelTo(h, p, opts.level or 20)
		return h, p
	end

	local function slotIndex(slot, kind: string): number
		for i, pay in slot.pay do
			if pay.kind == kind then
				return i
			end
		end
		error("no " .. kind .. " price on " .. slot.offer)
	end

	local function stockAt(h)
		local at = Logic.At(h.adapters.Clock.Now())
		return Logic.Stock(at.visit), at
	end

	describe("Schedule", function()
		it("parks for Stay seconds out of every Cycle, the same function of time everywhere", function()
			expect(Rules.Stay).toBe(2 * 3600)
			expect(Rules.Cycle).toBe(6 * 3600)
			local k = Logic.Visit(START)
			local startsAt = k * Rules.Cycle + Rules.Offset
			local inside = Logic.At(startsAt + 10)
			expect(inside.present).toBe(true)
			expect(inside.endsAt).toBe(startsAt + Rules.Stay)
			local justBefore = Logic.At(startsAt + Rules.Stay - 1)
			expect(justBefore.present).toBe(true)
			local after = Logic.At(startsAt + Rules.Stay)
			expect(after.present).toBe(false)
			expect(after.nextAt).toBe(startsAt + Rules.Cycle)
			local before = Logic.At(startsAt - 1)
			expect(before.present).toBe(false)
			expect(before.nextAt).toBe(startsAt)
			-- Exactly Stay of every Cycle, sampled every 10 minutes over two days.
			local on = 0
			for s = 0, 2 * 86400 - 1, 600 do
				if Logic.At(START + s).present then
					on += 1
				end
			end
			expect(on).toBe(2 * 86400 / 600 * Rules.Stay / Rules.Cycle)
		end)

		it("puts the visit on the calendar: running now, or the next one", function()
			local k = Logic.Visit(START)
			local startsAt = k * Rules.Cycle + Rules.Offset
			local function merchantRows(list)
				local out = {}
				for _, e in list do
					if e.kind == "merchant" then
						table.insert(out, e)
					end
				end
				return out
			end
			local running = merchantRows(Calendar.Now(startsAt + 60))
			expect(#running).toBe(1)
			expect(running[1].endsAt).toBe(startsAt + Rules.Stay)
			expect(running[1].screen).toBe("Merchant")
			local away = startsAt + Rules.Stay + 60
			local soon = merchantRows(Calendar.Soon(away, 24 * 3600))
			expect(#soon).toBe(1)
			expect(soon[1].startsAt).toBe(startsAt + Rules.Cycle)
			-- The Events screen lists one row, never a month of visits.
			local sections = Calendar.Sections(away)
			local rows = #merchantRows(sections.now) + #merchantRows(sections.week) + #merchantRows(sections.later)
			expect(rows).toBe(1)
		end)
	end)

	describe("Stock", function()
		it("rolls Slots distinct offers per visit, the same for every player and server", function()
			local k = Logic.Visit(START)
			local a, b = Logic.Stock(k), Logic.Stock(k)
			expect(#a).toBe(Rules.Slots)
			local seen = {}
			for i, slot in a do
				expect(slot.offer).toBe(b[i].offer)
				expect(slot.item).toBe(b[i].item)
				expect(seen[slot.offer]).toBe(nil)
				seen[slot.offer] = true
				-- No Dig Site in Config.Unlocks yet: shovels never roll.
				expect(slot.kind == "shovels").toBe(false)
			end
			local differs = false
			for i = 1, 20 do
				local other = Logic.Stock(k + i)
				for j, slot in other do
					if slot.offer ~= a[j].offer then
						differs = true
					end
				end
			end
			expect(differs).toBe(true)
		end)

		it("sells real decor and eggs: the rotating merchant pieces and eggs from Config.Eggs", function()
			local k = Logic.Visit(START)
			for i = 0, 50 do
				for _, slot in Logic.Stock(k + i) do
					if slot.kind == "decor" then
						local def = Config.Decor.ById[slot.item]
						expect(def ~= nil).toBe(true)
						expect(def.reward).toBe("merchant")
						expect(def.price).toBe(nil)
						expect(table.find(Rules.Decor, slot.item) ~= nil).toBe(true)
					elseif slot.kind == "egg" then
						expect(Config.Eggs.ById[slot.item] ~= nil).toBe(true)
					end
				end
			end
		end)

		it("shows two players the same stock and lets each buy up to the limit", function()
			local h, p = boot({ at = visitWith("decor_a") })
			local q = h:Join()
			levelTo(h, q, 20)
			local stock = stockAt(h)
			local slot
			for _, s in stock do
				if s.offer == "decor_a" then
					slot = s
				end
			end
			for _, who in { p, q } do
				h:System("Currency"):Add(who, "gems", 10000, "test")
				local res = h:Call(who, "Merchant.Buy", { offer = "decor_a", pay = slotIndex(slot, "gems") })
				expect(res.bought).toBe(1)
				expect(res.left).toBe(0)
				expect(h:Section(who, "Shop").decor[slot.item]).toBe(1)
			end
			expect(h:Reject(p, "Merchant.Buy", { offer = "decor_a", pay = slotIndex(slot, "gems") })).toBe(
				"You bought all of those this visit"
			)
		end)

		it("clears the limits when the next visit starts", function()
			local at = visitWith("trait_scroll")
			local h, p = boot({ at = at })
			h:System("Currency"):Add(p, "gems", 10000, "test")
			h:Call(p, "Merchant.Buy", { offer = "trait_scroll", pay = 1 })
			expect(h:Section(p, "Merchant").bought.trait_scroll).toBe(1)
			-- Jump to the next visit that sells it again.
			local k = Logic.Visit(at)
			local nextAt
			for i = 1, 2000 do
				if Logic.Find(k + i, "trait_scroll") then
					nextAt = (k + i) * Rules.Cycle + Rules.Offset + 60
					break
				end
			end
			h.adapters.advance(nextAt - h.adapters.Clock.Now())
			h:Step()
			h:Call(p, "Merchant.Buy", { offer = "trait_scroll", pay = 1 })
			local s = h:Section(p, "Merchant")
			expect(s.bought.trait_scroll).toBe(1)
			expect(s.scrolls).toBe(2)
		end)

		it("refuses while the caravan is away, and offers that are not in this visit", function()
			local k = Logic.Visit(START)
			local away = k * Rules.Cycle + Rules.Offset + Rules.Stay + 60
			local h, p = boot({ at = away })
			local msg = h:Reject(p, "Merchant.Buy", { offer = "trait_scroll", pay = 1 })
			expect(string.find(msg, "The merchant is away. Back in", 1, true) ~= nil).toBe(true)

			local h2, p2 = boot({ at = k * Rules.Cycle + Rules.Offset + 60 })
			local stock = stockAt(h2)
			local missing
			for _, offer in Rules.Offers do
				if not Logic.Find(Logic.Visit(h2.adapters.Clock.Now()), offer.id) then
					missing = offer.id
				end
			end
			expect(#stock).toBe(Rules.Slots)
			expect(h2:Reject(p2, "Merchant.Buy", { offer = missing, pay = 1 })).toBe("The merchant isn't selling that this visit")
		end)

		it("is locked below its Ranch Level", function()
			local h, p = boot({ at = visitWith("trait_scroll"), level = 1 })
			expect(h:Reject(p, "Merchant.Buy", { offer = "trait_scroll", pay = 1 })).toBe(
				string.format("Unlocks at Ranch Level %d", Config.Unlocks.Features.merchant)
			)
			expect(Config.Unlocks.Features.merchant).toBe(7)
		end)
	end)

	describe("Paying", function()
		it("charges coins from the ranch income, all or nothing", function()
			local h, p = boot({ at = visitWith("seed_pouch") })
			local slot = Logic.Find(Logic.Visit(h.adapters.Clock.Now()), "seed_pouch")
			local i = slotIndex(slot, "coins")
			local income = h:System("Ranch"):IncomePerSecond(p)
			local price = Logic.CoinPrice(income, slot.pay[i].seconds)
			local cur = h:Section(p, "Currency")
			cur.coins = price - 1
			expect(h:Reject(p, "Merchant.Buy", { offer = "seed_pouch", pay = i })).toBe("Not enough coins")
			expect(cur.coins).toBe(price - 1)
			expect(h:Section(p, "Kitchen").seeds).toBe(0)
			expect(h:Section(p, "Merchant").bought.seed_pouch).toBe(nil)
			cur.coins = price
			local res = h:Call(p, "Merchant.Buy", { offer = "seed_pouch", pay = i })
			expect(res.amount).toBe(price)
			expect(res.total).toBe(slot.amount)
			expect(cur.coins).toBe(0)
			expect(h:Section(p, "Kitchen").seeds).toBe(slot.amount)
		end)

		it("barters fish, all or nothing, and delivers Golden seeds", function()
			local h, p = boot({ at = visitWith("seed_pouch") })
			local slot = Logic.Find(Logic.Visit(h.adapters.Clock.Now()), "seed_pouch")
			local i = slotIndex(slot, "fish")
			local need = slot.pay[i].amount
			local pond = h:Section(p, "Fishing")
			local fishId = Config.Fishing.Ids[1]
			pond.fish = { [fishId] = need - 1 }
			expect(h:Reject(p, "Merchant.Buy", { offer = "seed_pouch", pay = i })).toBe("Not enough fish")
			expect(pond.fish[fishId]).toBe(need - 1)
			expect(h:Section(p, "Kitchen").seeds).toBe(0)
			pond.fish[fishId] = need + 1
			h:Call(p, "Merchant.Buy", { offer = "seed_pouch", pay = i })
			expect(pond.fish[fishId]).toBe(1)
			expect(h:Section(p, "Kitchen").seeds).toBe(slot.amount)
		end)

		it("barters Pantry dishes, all or nothing, and delivers bait", function()
			local h, p = boot({ at = visitWith("bait_bundle") })
			local slot = Logic.Find(Logic.Visit(h.adapters.Clock.Now()), "bait_bundle")
			local i = slotIndex(slot, "dishes")
			local need = slot.pay[i].amount
			local k = h:Section(p, "Kitchen")
			k.pantry = {}
			local pond = h:Section(p, "Fishing")
			local bait = pond.bait
			expect(h:Reject(p, "Merchant.Buy", { offer = "bait_bundle", pay = i })).toBe("Not enough Pantry dishes")
			expect(pond.bait).toBe(bait)
			local dish = Config.Kitchen.Recipes[1].id
			k.pantry[dish] = need
			h:Call(p, "Merchant.Buy", { offer = "bait_bundle", pay = i })
			expect(k.pantry[dish]).toBe(nil)
			expect(pond.bait).toBe(math.min(bait + slot.amount, Config.Fishing.MaxBait))
		end)

		it("pays in amber or gems, all or nothing, and keeps the Trait Scroll", function()
			local h, p = boot({ at = visitWith("trait_scroll") })
			local slot = Logic.Find(Logic.Visit(h.adapters.Clock.Now()), "trait_scroll")
			local amber = slotIndex(slot, "amber")
			local cur = h:Section(p, "Currency")
			local price = slot.pay[amber].amount
			h:System("Currency"):Add(p, "amber", price - 1, "test")
			expect(h:Reject(p, "Merchant.Buy", { offer = "trait_scroll", pay = amber })).toBe("Not enough Amber")
			expect(h:System("Currency"):Balance(p, "amber")).toBe(price - 1)
			expect(h:Section(p, "Merchant").scrolls).toBe(0)
			h:System("Currency"):Add(p, "amber", 1, "test")
			local res = h:Call(p, "Merchant.Buy", { offer = "trait_scroll", pay = amber })
			expect(res.pay).toBe("amber")
			expect(res.total).toBe(1)
			expect(h:System("Currency"):Balance(p, "amber")).toBe(0)
			expect(h:Section(p, "Merchant").scrolls).toBe(1)
			local _ = cur
		end)

		it("hands out eggs through Rewards", function()
			local h, p = boot({ at = visitWith("egg_basket") })
			local slot = Logic.Find(Logic.Visit(h.adapters.Clock.Now()), "egg_basket")
			h:System("Currency"):Add(p, "coins", 1e12, "test")
			local before = 0
			for _ in h:Section(p, "Eggs").list do
				before += 1
			end
			h:Call(p, "Merchant.Buy", { offer = "egg_basket", pay = slotIndex(slot, "coins") })
			local after, found = 0, false
			for _, egg in h:Section(p, "Eggs").list do
				after += 1
				if egg.type == slot.item then
					found = true
				end
			end
			expect(after).toBe(before + 1)
			expect(found).toBe(true)
		end)

		it("sells shovels only with the Dig Site plugged in and unlocked", function()
			local Features = Config.Unlocks.Features
			local saved = Features.dig_site
			Features.dig_site = 16
			local ok, err = pcall(function()
				local at = visitWith("shovel_bundle")
				local added = {}
				local stub = {
					AddShovels = function(_, player, n)
						added[player.UserId] = (added[player.UserId] or 0) + n
						return added[player.UserId]
					end,
				}
				local h, p = boot({ at = at, stubs = { DigSite = stub }, level = 16 })
				local slot = Logic.Find(Logic.Visit(at), "shovel_bundle")
				h:System("Currency"):Add(p, "coins", 1e12, "test")
				expect(h:Session(p, "Merchant").shovels).toBe(true)
				local res = h:Call(p, "Merchant.Buy", { offer = "shovel_bundle", pay = slotIndex(slot, "coins") })
				expect(res.total).toBe(slot.amount)
				expect(added[p.UserId]).toBe(slot.amount)

				-- Below the Dig Site's level: refused, nothing charged.
				local h2, p2 = boot({ at = at, stubs = { DigSite = stub }, level = 10 })
				h2:System("Currency"):Add(p2, "coins", 1e12, "test")
				local coins = h2:Section(p2, "Currency").coins
				expect(h2:Reject(p2, "Merchant.Buy", { offer = "shovel_bundle", pay = slotIndex(slot, "coins") })).toBe(
					"Unlocks at Ranch Level 16"
				)
				expect(h2:Section(p2, "Currency").coins).toBe(coins)

				-- No DigSite system: not offered to anyone.
				local h3, p3 = boot({ at = at, level = 20 })
				h3:System("Currency"):Add(p3, "coins", 1e12, "test")
				expect(h3:Session(p3, "Merchant").shovels).toBe(false)
				expect(h3:Reject(p3, "Merchant.Buy", { offer = "shovel_bundle", pay = slotIndex(slot, "coins") })).toBe(
					"The Dig Site isn't open yet"
				)
			end)
			Features.dig_site = saved
			if not ok then
				error(err, 0)
			end
		end)
	end)

	describe("Trait Scroll", function()
		local function monster(h, p)
			return h:System("Monsters"):Create(p, { line = "cindlet", rarity = 2, stage = 3, variant = 0 }, "test", true)
		end

		it("rerolls one visible trait with the seeded hatch roll, never the hidden trait or a duplicate", function()
			local h, p = boot()
			local s = h:Section(p, "Merchant")
			s.scrolls = 30
			local m = monster(h, p)
			for n = 0, 29 do
				local slot = n % 2 + 1
				local expected = Logic.Reroll(m, slot, Logic.ScrollSeed(p.UserId, m, n))
				local old = m.traits[slot]
				h:Advance(1) -- the action's rate limit
				local res = h:Call(p, "Merchant.Reroll", { id = m.id, slot = slot })
				expect(res.trait).toBe(expected)
				expect(res.old).toBe(old)
				expect(res.trait ~= old).toBe(true)
				local other = m.traits[3 - slot]
				expect(res.trait ~= other).toBe(true)
				expect(res.trait ~= m.hidden).toBe(true)
				expect(Config.Traits.ById[res.trait].hiddenOnly).toBe(nil)
				expect(m.traits[slot]).toBe(res.trait)
			end
			expect(s.scrolls).toBe(0)
			expect(s.rerolls).toBe(30)
			h:Advance(1)
			expect(h:Reject(p, "Merchant.Reroll", { id = m.id, slot = 1 })).toBe("No Trait Scrolls left")
		end)

		it("refuses a missing monster or an empty slot without spending a scroll", function()
			local h, p = boot()
			local s = h:Section(p, "Merchant")
			s.scrolls = 1
			local m = monster(h, p)
			m.traits[2] = nil
			expect(h:Reject(p, "Merchant.Reroll", { id = m.id, slot = 2 })).toBe("That trait slot is empty")
			expect(s.scrolls).toBe(1)
			local msg = h:Reject(p, "Merchant.Reroll", { id = "nope", slot = 1 })
			expect(type(msg)).toBe("string")
			expect(s.scrolls).toBe(1)
		end)
	end)

	describe("Around the game", function()
		it("publishes MerchantBought and counts toward the weekly goal", function()
			local def = Config.Weekly.ById.merchant_3
			expect(def.family).toBe("merchant")
			expect(def.unlock).toBe("merchant")
			expect(def.topic).toBe("MerchantBought")
			expect(def.target).toBe(3)
			local h, p = boot({ at = visitWith("trait_scroll"), extra = { "Weekly" } })
			local seen = {}
			h.kernel.Bus:Subscribe("MerchantBought", function(_, data)
				table.insert(seen, data)
			end)
			local w = h:Section(p, "Weekly")
			w.goals = { { id = "merchant_3", progress = 0 } }
			h:System("Currency"):Add(p, "gems", 10000, "test")
			local slot = Logic.Find(Logic.Visit(h.adapters.Clock.Now()), "trait_scroll")
			h:Call(p, "Merchant.Buy", { offer = "trait_scroll", pay = slotIndex(slot, "gems") })
			expect(w.goals[1].progress).toBe(1)
			expect(#seen).toBe(1)
			expect(seen[1].item).toBe("trait_scroll")
			expect(seen[1].pay).toBe("gems")
		end)

		it("keeps the caravan clear of scenery with a keep-out", function()
			local zone = Config.World.MerchantCaravan
			expect(zone.center[1]).toBe(Rules.World.position[1])
			expect(zone.center[2]).toBe(Rules.World.position[3])
			expect(table.find(Config.World.Scenery.keepOut, zone) ~= nil).toBe(true)
		end)
	end)
end
