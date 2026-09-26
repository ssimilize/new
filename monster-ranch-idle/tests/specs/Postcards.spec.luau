-- Glow-up X: postcards from expeditions. Recording on claim (rewards untouched), the album caps
-- and favourites, sending to friends through the Market mailbox (Gifts' gates, own daily caps,
-- dedup by mail id, offline delivery), malformed cards and load-time normalising.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Postcards")
	local Cfg = Config.Postcards
	local G = Config.Community.Gifts

	local SYSTEMS = {
		"Currency",
		"Progression",
		"Rewards",
		"Monsters",
		"Eggs",
		"Shop",
		"Accessories",
		"Expeditions",
		"Market",
		"Monetization",
		"Quests",
		"Gifts",
		"Postcards",
	}

	local function server(network)
		return TestKernel.new({ systems = SYSTEMS, network = network or MockAdapters.network() })
	end

	local function befriend(h, a, b)
		h.adapters.friends[a] = h.adapters.friends[a] or {}
		h.adapters.friends[a][b] = true
		h.adapters.friends[b] = h.adapters.friends[b] or {}
		h.adapters.friends[b][a] = true
	end

	local function veteran(h, userId, name)
		local p = h:Join(userId, name)
		h:System("Progression"):AddXP(p, 1e6, "test")
		h.kernel.Data:Get(p)._meta.playSeconds = G.minPlaySeconds + 60
		return p
	end

	local function team(h, p, n: number)
		local ids = {}
		for i = 1, n do
			local m = h:System("Monsters"):Create(p, {
				line = ({ "cindlet", "bubblin", "mossbun", "zappip" })[(i - 1) % 4 + 1],
				rarity = 2,
				stage = 3,
			}, "test", true)
			m.lv = 30
			table.insert(ids, m.id)
		end
		return ids
	end

	-- Starts an expedition and brings it back at once (no long clock).
	local function finish(h, p, slot: number, ids, region: string?)
		h:Call(p, "Expeditions.Start", { slot = slot, region = region or "meadow", stage = 1, duration = "900", squad = ids })
		h:Section(p, "Expeditions").slots[slot].endsAt = h.adapters.Clock.Now()
		h:Advance(2)
	end

	local function count(cards): number
		local n = 0
		for _ in cards do
			n += 1
		end
		return n
	end

	local function detail(region: string, ids)
		return { slot = 1, duration = 900, region = region, stage = 1, squad = ids, loot = { { kind = "coins", amount = 10 } } }
	end

	describe("Logic/Postcards", function()
		local function card(id, n, region, fav)
			return { id = id, n = n, region = region, fav = fav == true }
		end

		it("drops the oldest non-favourites per region, then past the total", function()
			local cfg = { perRegion = 2, maxTotal = 4 }
			local cards = {
				a = card("a", 1, "meadow", true),
				b = card("b", 2, "meadow"),
				c = card("c", 3, "meadow"),
				d = card("d", 4, "meadow"),
				e = card("e", 5, "coral"),
				f = card("f", 6, "coral"),
			}
			local dropped = Logic.Trim(cards, cfg)
			table.sort(dropped)
			-- meadow keeps c, d (+ the favourite a); then 5 > 4 drops the oldest non-favourite left (c).
			expect(table.concat(dropped, ",")).toBe("b,c")
		end)

		it("summarises loot by kind and id, coins first, capped", function()
			local out = Logic.Summarise({
				{ kind = "food", id = "sweet", amount = 3 },
				{ kind = "coins", amount = 10 },
				{ kind = "food", id = "sweet", amount = 2 },
				{ kind = "egg", id = "meadow", amount = 1 },
				"junk",
			}, 2)
			expect(#out).toBe(2)
			expect(out[1].kind).toBe("coins")
			expect(out[2].kind).toBe("egg")
			local all = Logic.Summarise({ { kind = "food", id = "sweet", amount = 3 }, { kind = "food", id = "sweet", amount = 2 } }, 6)
			expect(all[1].amount).toBe(5)
		end)

		it("rebuilds a card from known fields only", function()
			expect(Logic.Clean(nil, Config)).toBe(nil)
			expect(Logic.Clean({ region = "meadow", squad = { { line = "nope" } } }, Config)).toBe(nil)
			local clean = Logic.Clean({
				region = "meadow",
				line = "not_a_line",
				squad = { { line = "cindlet", form = "made_up", stage = 3, name = string.rep("x", 99), muts = { "a", "b", "c" } } },
				loot = { { kind = "coins", amount = "12" }, 5 },
				fav = "yes",
				from = 7,
				evil = function() end,
			}, Config)
			expect(clean ~= nil).toBe(true)
			expect(clean.line).toBe(Cfg.DefaultScene.lines[1].id)
			expect(clean.squad[1].form).toBe("cindlet")
			expect(clean.squad[1].stage).toBe(1)
			expect(#clean.squad[1].name).toBe(30)
			expect(#clean.squad[1].muts).toBe(2)
			expect(clean.loot[1].amount).toBe(12)
			expect(#clean.loot).toBe(1)
			expect(clean.fav).toBe(false)
			expect(clean.from).toBe(false)
			expect(clean.evil).toBe(nil)
		end)

		it("picks a line from the region's pool, else the default pool", function()
			local id = Logic.PickLine("meadow", Cfg, function()
				return 2
			end)
			expect(id).toBe(Cfg.Scenes.meadow.lines[2].id)
			expect(string.find(Logic.LineText(id, Cfg), "%s", 1, true) ~= nil).toBe(true)
			local other = Logic.PickLine("moon", Cfg, function()
				return 99
			end)
			expect(other).toBe(Cfg.DefaultScene.lines[#Cfg.DefaultScene.lines].id)
		end)
	end)

	describe("Postcards", function()
		it("writes a postcard when an expedition is claimed, without touching the rewards", function()
			local h = server()
			local p = h:Join()
			local ids = team(h, p, 3)
			finish(h, p, 1, ids)
			local claim = h:Call(p, "Expeditions.Claim", { slot = 1 })
			local cards = h:Section(p, "Postcards").cards
			expect(count(cards)).toBe(1)
			local card = cards.c1
			expect(card.region).toBe("meadow")
			expect(#card.squad).toBe(Cfg.maxMonsters)
			expect(card.squad[1].line).toBe("cindlet")
			expect(card.squad[1].lv).toBe(nil) -- only what redraws it
			expect(card.from).toBe(false)
			expect(Cfg.LineById[card.line] ~= nil).toBe(true)
			local coins = 0
			for _, item in claim.rewards do
				if item.kind == "coins" then
					coins += item.amount
				end
			end
			expect(card.loot[1].kind).toBe("coins")
			expect(card.loot[1].amount).toBe(coins)
			-- The client sees it.
			expect(h:Client(p).profile.Postcards.cards.c1.region).toBe("meadow")
			expect(h:Client(p).profile.Postcards.recv).toBe(nil)
		end)

		it("writes one per slot on Claim all and none for a recall", function()
			local h = server()
			local p = h:Join()
			h:Section(p, "Progression").level = 30
			local ids = team(h, p, 3)
			h:Advance(1)
			finish(h, p, 1, { ids[1] })
			finish(h, p, 2, { ids[2] })
			h:Call(p, "Expeditions.ClaimAll")
			expect(count(h:Section(p, "Postcards").cards)).toBe(2)
			h:Advance(2)
			h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = { ids[3] } })
			h:Advance(2)
			h:Call(p, "Expeditions.Recall", { slot = 1 })
			expect(count(h:Section(p, "Postcards").cards)).toBe(2)
		end)

		it("keeps the newest per region, favourites for good, and caps the album", function()
			local h = server()
			local p = h:Join()
			local ids = team(h, p, 1)
			local P = h:System("Postcards")
			for _ = 1, Cfg.perRegion do
				P:Record(p, detail("meadow", ids))
			end
			local s = h:Section(p, "Postcards")
			h:Call(p, "Postcards.Favourite", { card = "c1", on = true })
			P:Record(p, detail("meadow", ids))
			P:Record(p, detail("meadow", ids))
			expect(s.cards.c1 ~= nil).toBe(true) -- the favourite stays
			expect(s.cards.c2).toBe(nil) -- the oldest others went
			expect(count(s.cards)).toBe(Cfg.perRegion + 1)
			-- Unstarring lets it go at once when its region is full.
			h:Advance(1)
			local res = h:Call(p, "Postcards.Favourite", { card = "c1", on = false })
			expect(res.kept).toBe(false)
			expect(s.cards.c1).toBe(nil)
			expect(count(s.cards)).toBe(Cfg.perRegion)
			expect(h:Reject(p, "Postcards.Favourite", { card = "c999", on = true })).toContain("isn't in your album")
			-- The whole album is capped across regions.
			local regions = {}
			for _, r in Config.Regions.List do
				table.insert(regions, r.id)
			end
			for i = 1, Cfg.maxTotal + 10 do
				P:Record(p, detail(regions[i % #regions + 1], ids))
			end
			expect(count(s.cards) <= Cfg.maxTotal).toBe(true)
		end)

		it("limits favourites", function()
			local h = server()
			local p = h:Join()
			local ids = team(h, p, 1)
			local P = h:System("Postcards")
			local regions = {}
			for _, r in Config.Regions.List do
				table.insert(regions, r.id)
			end
			local made = {}
			for i = 1, Cfg.maxFavourites + 1 do
				table.insert(made, P:Record(p, detail(regions[i % #regions + 1], ids)).id)
			end
			for i = 1, Cfg.maxFavourites do
				h:Call(p, "Postcards.Favourite", { card = made[i], on = true })
				h:Advance(1)
			end
			expect(h:Reject(p, "Postcards.Favourite", { card = made[#made], on = true })).toContain("Unstar one first")
		end)

		it("sends a postcard to a friend, who finds it in their album", function()
			local h = server()
			local ana = veteran(h, 9401, "Ana")
			local bo = h:Join(9402, "Bo")
			befriend(h, 9401, 9402)
			local ids = team(h, ana, 2)
			finish(h, ana, 1, ids)
			h:Call(ana, "Expeditions.Claim", { slot = 1 })
			local res = h:Call(ana, "Postcards.Send", { card = "c1", to = 9402 })
			expect(res.left).toBe(Cfg.Send.perDay - 1)
			expect(h:Section(ana, "Postcards").totalSent).toBe(1)
			h:System("Market"):Sync(bo)
			local got = h:Section(bo, "Postcards")
			expect(count(got.cards)).toBe(1)
			local card = got.cards.c1
			expect(card.from).toBe("Ana")
			expect(card.region).toBe("meadow")
			expect(card.fav).toBe(false)
			expect(#card.sent).toBe(0)
			expect(got.totalReceived).toBe(1)
			-- A received postcard can't be sent on, and the same card can't go twice to one friend.
			h:Advance(2)
			expect(h:Reject(bo, "Postcards.Send", { card = "c1", to = 9401 })).toContain("your own postcards")
			expect(h:Reject(ana, "Postcards.Send", { card = "c1", to = 9402 })).toContain("already sent")
		end)

		it("refuses strangers, yourself and senders below the gift gates", function()
			local h = server()
			local ana = veteran(h, 9411, "Ana")
			local ids = team(h, ana, 1)
			local card = h:System("Postcards"):Record(ana, detail("meadow", ids))
			expect(h:Reject(ana, "Postcards.Send", { card = card.id, to = 9412 })).toContain("Roblox friends")
			h:Advance(2)
			expect(h:Reject(ana, "Postcards.Send", { card = card.id, to = 9411 })).toContain("yourself")
			local newbie = h:Join(9413, "Cy")
			befriend(h, 9413, 9411)
			local mine = h:System("Postcards"):Record(newbie, detail("meadow", team(h, newbie, 1)))
			expect(h:Reject(newbie, "Postcards.Send", { card = mine.id, to = 9411 })).toContain("Ranch Level")
		end)

		it("caps sends per day and per friend, and resets tomorrow", function()
			local h = server()
			local ana = veteran(h, 9421, "Ana")
			local ids = team(h, ana, 1)
			local P = h:System("Postcards")
			local friends = {}
			for i = 1, Cfg.Send.perDay + 1 do
				friends[i] = 9430 + i
				befriend(h, 9421, friends[i])
			end
			local cards = {}
			for i = 1, Cfg.Send.perDay + 1 do
				cards[i] = P:Record(ana, detail("meadow", ids)).id
			end
			-- Per friend first.
			for i = 1, Cfg.Send.perFriendPerDay do
				h:Call(ana, "Postcards.Send", { card = cards[i], to = friends[1] })
				h:Advance(2)
			end
			expect(h:Reject(ana, "Postcards.Send", { card = cards[Cfg.Send.perFriendPerDay + 1], to = friends[1] })).toContain(
				"this friend more postcards tomorrow"
			)
			h:Advance(2)
			local sent = Cfg.Send.perFriendPerDay
			local f = 2
			while sent < Cfg.Send.perDay do
				h:Call(ana, "Postcards.Send", { card = cards[sent + 1], to = friends[f] })
				sent += 1
				f += 1
				h:Advance(2)
			end
			expect(h:Reject(ana, "Postcards.Send", { card = cards[1], to = friends[#friends] })).toContain("postcards for today")
			h:Advance(86400)
			expect(h:Call(ana, "Postcards.Send", { card = cards[1], to = friends[#friends] }).left).toBe(Cfg.Send.perDay - 1)
		end)

		it("delivers to an offline friend on their next join, once per mail id", function()
			local network = MockAdapters.network()
			local a = server(network)
			local ana = veteran(a, 9441, "Ana")
			befriend(a, 9441, 9442)
			local ids = team(a, ana, 1)
			local card = a:System("Postcards"):Record(ana, detail("coral", ids))
			a:Call(ana, "Postcards.Send", { card = card.id, to = 9442 })

			local b = server(network)
			local bo = b:Join(9442, "Bo")
			local got = b:Section(bo, "Postcards")
			expect(count(got.cards)).toBe(1)
			expect(got.cards.c1.from).toBe("Ana")
			expect(got.cards.c1.region).toBe("coral")
			-- The same mail again (a retried delivery) adds nothing.
			local entry = {
				id = string.format("postcard:%d:%s", 9441, card.id),
				kind = "postcard",
				card = card,
				from = 9441,
				fromName = "Ana",
			}
			b:System("Market"):Send(nil, 9442, entry)
			b:System("Market"):Sync(bo)
			expect(count(got.cards)).toBe(1)
			-- A malformed postcard is dropped, never stored.
			b:System("Market"):Send(nil, 9442, { id = "postcard:1:bad", kind = "postcard", card = { region = "meadow", squad = {} } })
			b:System("Market"):Sync(bo)
			expect(count(b:Section(bo, "Postcards").cards)).toBe(1)
			expect(b:Section(bo, "Postcards").totalReceived).toBe(1)
		end)

		it("cleans and re-caps the album on load (a bad card or a lowered cap never stays)", function()
			local h = server()
			local p = h:Join()
			local ids = team(h, p, 1)
			local P = h:System("Postcards")
			for _ = 1, 3 do
				P:Record(p, detail("meadow", ids))
			end
			local s = h:Section(p, "Postcards")
			s.cards.c2.squad = { { line = "no_such_line" } } -- corrupted
			s.cards.c9 = { id = "c7", region = "meadow" } -- key and id disagree
			local again = h:Rejoin(p, 60)
			local cards = h:Section(again, "Postcards").cards
			expect(cards.c1 ~= nil).toBe(true)
			expect(cards.c2).toBe(nil)
			expect(cards.c9).toBe(nil)
			expect(cards.c3 ~= nil).toBe(true)
			expect(h:Section(again, "Postcards").seq).toBe(3)
		end)

		it("gives a profile saved before postcards existed an empty album", function()
			local h = server()
			local p = h:Join()
			local data = h.kernel.Data:Get(p)
			data.Postcards = nil
			data._meta.versions.Postcards = nil
			local again = h:Rejoin(p, 60)
			local s = h:Section(again, "Postcards")
			expect(count(s.cards)).toBe(0)
			expect(s.seq).toBe(0)
			expect(Logic.Migrate({ cards = {} }, 1).cards ~= nil).toBe(true)
		end)
	end)
end
