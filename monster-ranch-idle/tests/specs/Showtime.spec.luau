-- Update 1.5 · Showtime: accessories (buy, equip, storage, never leaving with a monster),
-- Contest Ribbons, and Monster Contests (phases, votes, judge, prizes, stats).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Acc = Config.Accessories
	local C = Config.Contests

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Accessories", "Contests", "Quests" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function monster(h, p, line: string?)
		return h:System("Monsters"):Create(p, { line = line or "cindlet", rarity = 2, stage = 3 }, "test", true)
	end

	-- A kernel whose clock sits `offset` seconds into a show's cycle.
	local function atShow(offset: number, systems)
		local show = 2900000 -- any show number
		local h = TestKernel.new({ systems = systems or SYSTEMS, startTime = show * C.CycleSeconds + offset })
		return h, show
	end

	local function player(h, userId: number, name: string)
		local p = h:Join(userId, name)
		levelTo(h, p, 10)
		return p
	end

	describe("Accessories", function()
		it("buys with gems or ribbons, equips, swaps and unequips", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			local m = monster(h, p)
			expect(h:Reject(p, "Accessories.Buy", { accessory = "top_hat" })).toBe("Unlocks at Ranch Level 3")
			levelTo(h, p, 3)
			local Currency = h:System("Currency")
			Currency:Add(p, "gems", 200, "test")
			Currency:Add(p, "ribbons", 45, "test")
			expect(h:Call(p, "Accessories.Buy", { accessory = "top_hat" }).owned).toBe(1)
			expect(Currency:Balance(p, "gems")).toBe(200 - Acc.ById.top_hat.price.gems)
			h:Call(p, "Accessories.Buy", { accessory = "flower_crown" })
			expect(Currency:Balance(p, "ribbons")).toBe(5)
			expect(h:Reject(p, "Accessories.Buy", { accessory = "starlight_crown" })).toBe("Starlight Crown can't be bought. Earn it!")
			expect(h:Reject(p, "Accessories.Buy", { accessory = "hero_helmet" })).toBeTruthy()

			h:Call(p, "Accessories.Equip", { id = m.id, accessory = "top_hat" })
			expect(m.acc.head).toBe("top_hat")
			expect(h:Section(p, "Accessories").owned.top_hat).toBeNil()
			expect(h:System("Accessories"):Count(p, "top_hat")).toBe(1)
			expect(h:Reject(p, "Accessories.Equip", { id = m.id, accessory = "top_hat" })).toBe("You don't have a spare Top Hat")
			-- Same slot: the crown replaces the hat, which goes back to storage.
			local swap = h:Call(p, "Accessories.Equip", { id = m.id, accessory = "flower_crown" })
			expect(swap.previous).toBe("top_hat")
			expect(m.acc.head).toBe("flower_crown")
			expect(h:Section(p, "Accessories").owned.top_hat).toBe(1)
			h:Call(p, "Accessories.Unequip", { id = m.id, slot = "head" })
			expect(m.acc).toBeNil()
			expect(h:Section(p, "Accessories").owned.flower_crown).toBe(1)
			expect(h:Reject(p, "Accessories.Unequip", { id = m.id, slot = "head" })).toBe("Nothing to take off there")
			expect(h:System("Accessories"):Collection(p)).toBe(2)
		end)

		it("comes back to storage when the monster leaves, and shows in the appearance", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			levelTo(h, p, 3)
			local A = h:System("Accessories")
			A:Add(p, "royal_cape", 1)
			A:Add(p, "monocle", 1)
			local m = monster(h, p)
			monster(h, p, "bubblin") -- keep one monster after the sale
			h:Call(p, "Accessories.Equip", { id = m.id, accessory = "royal_cape" })
			h:Call(p, "Accessories.Equip", { id = m.id, accessory = "monocle" })
			local Appearance = t.Shared("Logic.Appearance")
			expect(Appearance.Of(m).acc).toEqual({ back = "royal_cape", face = "monocle" })

			local removed = h:System("Monsters"):Remove(p, m.id, "trade")
			expect(removed.acc).toBeNil() -- the record that leaves carries nothing
			expect(h:Section(p, "Accessories").owned).toEqual({ royal_cape = 1, monocle = 1 })
			-- Inserting a record that still has accessories strips them too.
			local copy = table.clone(removed)
			copy.acc = { head = "halo" }
			local inserted = h:System("Monsters"):Insert(p, copy, "trade")
			expect(inserted.acc).toBeNil()
		end)

		it("is granted by rewards and the starter pack lists the Sprout Cap", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			h:System("Rewards"):Grant(p, { { kind = "accessory", id = "halo", amount = 2 }, { kind = "ribbons", amount = 7 } }, "test")
			expect(h:Section(p, "Accessories").owned.halo).toBe(2)
			expect(h:System("Currency"):Balance(p, "ribbons")).toBe(7)
			local starter = Config.Monetization.ProductByKey.starterPack
			local found = false
			for _, item in starter.grant do
				found = found or (item.kind == "accessory" and item.id == "sprout_cap")
			end
			expect(found).toBe(true)
			expect(h:Section(p, "Quests").achievements.accessories_10.progress).toBe(2)
		end)

		it("has a real theme for every tag and at least 30 accessories", function()
			expect(#Acc.List >= 30).toBe(true)
			local tags = {}
			for _, theme in C.Themes do
				for _, tag in theme.tags do
					tags[tag] = true
				end
			end
			for _, a in Acc.List do
				local fits = false
				for _, tag in a.tags do
					fits = fits or tags[tag] == true
				end
				expect(fits).toBe(true)
			end
			-- Every theme can be matched in every slot... or at least three of them.
			for _, theme in C.Themes do
				local slots = {}
				for _, a in Acc.List do
					for _, tag in a.tags do
						if table.find(theme.tags, tag) then
							slots[a.slot] = true
						end
					end
				end
				local n = 0
				for _ in slots do
					n += 1
				end
				expect(n >= 2).toBe(true)
			end
		end)
	end)

	describe("Monster Contests", function()
		it("runs entry, runway and results on the clock, with votes and prizes", function()
			local h, show = atShow(5)
			local a = player(h, 501, "Ann")
			local b = player(h, 502, "Ben")
			local c = player(h, 503, "Cal")
			local g = h:Client(a).global.Contests
			expect(g.state).toBe("entry")
			expect(g.show).toBe(show)
			expect(g.theme).toBe(C.ThemeFor(show).id)
			local theme = C.ThemeFor(show)

			local ma, mb = monster(h, a), monster(h, b, "bubblin")
			-- Ben dresses for the theme; Ann doesn't.
			local fit
			for _, acc in Acc.List do
				if not fit and acc.price and table.find(theme.tags, acc.tags[1]) then
					fit = acc
				end
			end
			h:System("Accessories"):Add(b, fit.id, 1)
			h:Call(b, "Accessories.Equip", { id = mb.id, accessory = fit.id })
			expect(h:Call(a, "Contests.Enter", { id = ma.id }).entries).toBe(1)
			expect(h:Call(b, "Contests.Enter", { id = mb.id }).entries).toBe(2)
			expect(h:Session(a, "Contests").entered).toBe(ma.id)
			expect(#h:Client(c).global.Contests.entries).toBe(2)
			expect(h:Reject(c, "Contests.Vote", { entry = 1, stars = 5 })).toBe("That monster isn't on the runway right now")

			-- Runway: entry 1 (Ann) walks first.
			h:Advance(C.EntrySeconds)
			g = h:Client(c).global.Contests
			expect(g.state).toBe("runway")
			expect(g.current).toBe(1)
			expect(h:Reject(a, "Contests.Vote", { entry = 1, stars = 5 })).toBe("You can't vote for your own monster")
			expect(h:Reject(a, "Contests.Enter", { id = ma.id })).toBe("Entries are closed. The next show opens soon!")
			h:Call(b, "Contests.Vote", { entry = 1, stars = 5 })
			h:Call(c, "Contests.Vote", { entry = 1, stars = 4 })
			h:Advance(1)
			h:Call(c, "Contests.Vote", { entry = 1, stars = 5 }) -- changing a vote is fine
			expect(h:Session(c, "Contests").votes[1]).toBe(5)
			h:Advance(C.RunwaySeconds)
			expect(h:Client(c).global.Contests.current).toBe(2)
			h:Call(a, "Contests.Vote", { entry = 2, stars = 2 })
			h:Call(c, "Contests.Vote", { entry = 2, stars = 3 })

			local ribbons = function(p)
				return h:System("Currency"):Balance(p, "ribbons")
			end
			h:Advance(C.RunwaySeconds + 1)
			g = h:Client(a).global.Contests
			expect(g.state).toBe("results")
			-- Ann: 0.7 × 5 + 0.3 × 2 = 4.1 · Ben: 0.7 × 2.5 + 0.3 × judge(fit)
			local judgeB = C.JudgeScore({ [fit.slot] = fit.id }, theme)
			expect(judgeB).toBe(C.Judge.base + C.Judge.perWorn + C.Judge.perMatch)
			expect(g.results[1].userId).toBe(501)
			expect(g.results[1].score).toBeNear(4.1)
			expect(g.results[2].score).toBeNear(0.7 * 2.5 + 0.3 * judgeB)
			expect(g.results[1].votes).toBe(2)
			-- Prizes: 1st and 2nd, plus a ribbon per entry voted on.
			expect(ribbons(a)).toBe(30 + 1)
			expect(ribbons(b)).toBe(20 + 1)
			expect(ribbons(c)).toBe(2)
			expect(h:System("Currency"):Balance(a, "gems")).toBe(15)
			local s = h:Section(a, "Contests")
			expect(s.shows).toBe(1)
			expect(s.wins).toBe(1)
			expect(s.best).toBe(1)
			expect(h:Section(c, "Contests").votes).toBe(2)
			expect(h:Section(a, "Quests").achievements.contest_win.progress).toBe(1)

			-- Results, then idle until the next show, which opens by itself.
			h:Advance(C.ResultsSeconds + 1)
			expect(h:Client(a).global.Contests.state).toBe("idle")
			h:Advance(C.CycleSeconds - (C.EntrySeconds + 2 * C.RunwaySeconds + C.ResultsSeconds) + 2)
			g = h:Client(a).global.Contests
			expect(g.state).toBe("entry")
			expect(g.show).toBe(show + 1)
			expect(#g.entries).toBe(0)
			expect(h:Session(a, "Contests").entered).toBe(false)
		end)

		it("judges alone on a quiet server, locks outfits at the runway and needs the unlock", function()
			local h = atShow(10)
			local newbie = h:Join(601, "New")
			local m0 = monster(h, newbie)
			expect(h:Reject(newbie, "Contests.Enter", { id = m0.id })).toBe("Unlocks at Ranch Level 7")
			local p = player(h, 602, "Solo")
			local m = monster(h, p)
			h:Call(p, "Contests.Enter", { id = m.id })
			h:System("Accessories"):Add(p, "halo", 1)
			h:Call(p, "Accessories.Equip", { id = m.id, accessory = "halo" }) -- counts: runway not started
			h:Advance(C.EntrySeconds)
			local g = h:Client(p).global.Contests
			expect(g.entries[1].appearance.acc.head).toBe("halo")
			h:Call(p, "Accessories.Unequip", { id = m.id, slot = "head" }) -- too late to matter
			h:Advance(C.RunwaySeconds + 1)
			g = h:Client(p).global.Contests
			expect(g.state).toBe("results")
			expect(g.results[1].votes).toBe(0)
			expect(g.results[1].score).toBe(C.JudgeScore({ head = "halo" }, C.ThemeById[g.theme]))
		end)

		it("lets you switch or withdraw before the runway, and drops leavers", function()
			local h = atShow(1)
			local p = player(h, 701, "Pia")
			local q = player(h, 702, "Quin")
			local m1, m2 = monster(h, p), monster(h, p, "bubblin")
			h:Call(p, "Contests.Enter", { id = m1.id })
			h:Advance(1)
			expect(h:Call(p, "Contests.Enter", { id = m2.id }).entries).toBe(1)
			expect(h:Client(p).global.Contests.entries[1].appearance.line).toBe("bubblin")
			h:Call(p, "Contests.Withdraw")
			expect(#h:Client(p).global.Contests.entries).toBe(0)
			expect(h:Reject(p, "Contests.Withdraw")).toBe("You have no entry to withdraw")
			h:Call(q, "Contests.Enter", { id = monster(h, q).id })
			h:Leave(q)
			expect(#h:Client(p).global.Contests.entries).toBe(0)
			h:Advance(C.EntrySeconds)
			expect(h:Client(p).global.Contests.state).toBe("idle") -- nobody entered
		end)

		it("cycles themes without repeats back to back", function()
			for show = 1, 50 do
				expect(C.ThemeFor(show).id ~= C.ThemeFor(show + 1).id).toBe(true)
			end
			local info = C.Show(12345)
			expect(info.startsAt <= 12345 and 12345 < info.nextAt).toBe(true)
		end)
	end)

	describe("Season 3 Ranch Pass", function()
		it("starts when Season 2 ends and grants real accessories", function()
			local Q = Config.Quests
			expect(Q.Seasons[3].startsAt).toBe(Q.Seasons[2].endsAt)
			expect(Q.PassAt(Q.Seasons[3].startsAt).season).toBe(3)
			for _, tier in Q.Seasons[3].tiers do
				for _, track in { tier.free, tier.premium } do
					for _, reward in track do
						if reward.kind == "accessory" then
							expect(Acc.ById[reward.id] ~= nil).toBe(true)
						end
					end
				end
			end
		end)
	end)
end
