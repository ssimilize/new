-- M1 Market (update 1.3): escrowed listings, purchases across servers sharing one market store,
-- the club trading post, tax, cancel / expiry, mailboxes and browsing.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Cfg = Config.Market

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Clubs", "Market" }
	local COINS = 1e6
	local BUSY = "market is busy"

	local function server(network, startTime)
		return TestKernel.new({ systems = SYSTEMS, network = network or MockAdapters.network(), startTime = startTime })
	end

	local function rancher(h, userId, name)
		local p = h:Join(userId, name)
		h:System("Progression"):AddXP(p, 1e6, "test")
		h:System("Currency"):Add(p, "coins", COINS, "test")
		return p
	end

	local function coins(h, p)
		return h:System("Currency"):Balance(p, "coins")
	end

	local function monster(h, p, fields)
		local spec = { line = "cindlet", rarity = 3, traits = { 3, 4 }, hidden = 5 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return h:System("Monsters"):Create(p, spec, "test", true)
	end

	-- Pins a player's monster capacity (one provider per kernel; see Trade.spec).
	local function setCapacity(h, p, n)
		local M = h:System("Monsters")
		if not h.marketCapacity then
			local cap = {}
			h.marketCapacity = cap
			M:RegisterCapacityProvider(function(player)
				return cap[player.UserId] or 60
			end)
		end
		h.marketCapacity[p.UserId] = n
	end

	local function sell(h, p, id, price, club, kind)
		local listing = h:Call(p, "Market.List", { kind = kind or "monster", id = id, price = price, club = club }).listing
		h:Advance(1)
		return listing
	end

	-- Entries waiting in a mailbox (records are { entries, acked }).
	local function mailOf(network, userId)
		local box = network.market.mail[userId]
		return if box then box.entries else {}
	end

	local function topics(h, name)
		local seen = {}
		h.kernel.Bus:Subscribe(name, function(player, detail)
			table.insert(seen, { player = player, detail = detail })
		end)
		return seen
	end

	local function makeClub(h, p)
		return h:Call(p, "Clubs.Create", { name = "Market Folk", tag = "MKT", color = 2, emblem = "moon", open = true }).id
	end

	describe("Listing", function()
		it("takes the monster into escrow and returns a public view", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7001, "Ana")
			local listed = topics(h, "MarketListed")
			local m = monster(h, p, { variant = 1 })
			local count = h:System("Monsters"):Count(p)
			local view = sell(h, p, m.id, 5000)

			expect(h:System("Monsters"):Get(p, m.id)).toBeNil()
			expect(h:System("Monsters"):Count(p)).toBe(count - 1)
			local record = network.market.listings[view.id]
			expect(record.state).toBe("open")
			expect(record.item.hidden).toBe(5)
			expect(record.key).toBe("m:cindlet:3:1")
			expect(record.expiresAt).toBe(record.createdAt + Cfg.DurationSeconds)
			expect(record.club).toBe(false)
			expect(h:Section(p, "Market").listings).toEqual({ view.id })
			expect(h:Client(p).profile.Market.listings).toEqual({ view.id })
			expect(h:Client(p).profile.Market.outbox).toBeNil()

			expect(view.mine).toBe(true)
			expect(view.club).toBe(false)
			expect(view.state).toBe("open")
			expect(view.key).toBe("m:cindlet:3:1")
			expect(view.item.hidden).toBeNil()
			expect(view.item.id).toBeNil()
			expect(view.item.appearance.line).toBe("cindlet")
			expect(view.item.variant).toBe(1)
			expect(view.item.egg).toBe(false)
			expect(view.item.traits).toEqual({ 3, 4 })
			expect(#listed).toBe(1)
			expect(listed[1].detail).toEqual({ listing = view.id, key = view.key, price = 5000, club = false })
		end)

		it("lists eggs from storage but not eggs in an incubator", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7002, "Ben")
			local ids = h:System("Eggs"):Add(p, "meadow", "test", 2)
			h:Call(p, "Eggs.Place", { egg = ids[1], slot = 2 })
			expect(h:Reject(p, "Market.List", { kind = "egg", id = ids[1], price = 500 })).toContain("storage")
			local view = sell(h, p, ids[2], 500, nil, "egg")
			expect(view.key).toBe("e:meadow")
			expect(view.item.egg).toBe("meadow")
			expect(view.item.appearance).toBe(false)
			expect(h:System("Eggs"):Get(p, ids[2])).toBeNil()
			expect(network.market.listings[view.id].item.type).toBe("meadow")
		end)

		it("checks the unlock, missing, locked and busy monsters, and the listing cap", function()
			local network = MockAdapters.network()
			local h = server(network)
			local fresh = h:Join(7003, "Newbie")
			local young = monster(h, fresh)
			expect(h:Reject(fresh, "Market.List", { kind = "monster", id = young.id, price = 500 })).toContain("Ranch Level 10")

			local p = rancher(h, 7004, "Cleo")
			expect(h:Reject(p, "Market.List", { kind = "monster", id = "m999", price = 500 })).toContain("doesn't exist")
			h:Advance(1)
			local locked = monster(h, p)
			locked.locked = true
			expect(h:Reject(p, "Market.List", { kind = "monster", id = locked.id, price = 500 })).toContain("locked")
			h:Advance(1)
			local busy = monster(h, p)
			h:System("Monsters"):SetBusy(p, busy.id, "expedition")
			expect(h:Reject(p, "Market.List", { kind = "monster", id = busy.id, price = 500 })).toContain("busy")
			expect(h:System("Monsters"):Get(p, locked.id)).toBeTruthy()
			expect(h:System("Monsters"):Get(p, busy.id)).toBeTruthy()
			h:Advance(1)

			for _ = 1, Cfg.MaxListings do
				sell(h, p, monster(h, p).id, 500)
			end
			local extra = monster(h, p)
			expect(h:Reject(p, "Market.List", { kind = "monster", id = extra.id, price = 500 })).toContain("up to 8")
			expect(h:System("Monsters"):Get(p, extra.id)).toBeTruthy()
			expect(#h:Section(p, "Market").listings).toBe(Cfg.MaxListings)
		end)

		it("needs a club for a trading post listing", function()
			local h = server()
			local p = rancher(h, 7005, "Dee")
			local m = monster(h, p)
			expect(h:Reject(p, "Market.List", { kind = "monster", id = m.id, price = 500, club = true })).toContain("Join a club")
			expect(h:System("Monsters"):Get(p, m.id)).toBeTruthy()
		end)

		it("keeps the item safe while the market is down and gives it back once it can confirm", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7006, "Eli")
			local m = monster(h, p)
			local egg = h:System("Eggs"):Add(p, "meadow", "test")[1]
			local count, eggs = h:System("Monsters"):Count(p), h:System("Eggs"):Count(p)
			network.marketDown = true
			expect(h:Reject(p, "Market.List", { kind = "monster", id = m.id, price = 500 })).toContain("The market is busy")
			h:Advance(1)
			expect(h:Reject(p, "Market.List", { kind = "egg", id = egg, price = 500 })).toContain("The market is busy")
			-- Nothing is known yet (the Create may have landed), so the items wait in saved tasks.
			expect(#h:Section(p, "Market").outbox).toBe(2)
			expect(h:System("Monsters"):Count(p)).toBe(count - 1)
			expect(next(network.market.listings)).toBeNil()
			expect(coins(h, p)).toBe(COINS)
			-- Once the market answers, a tombstone blocks each id and the items come back.
			network.marketDown = false
			h:Advance(Cfg.MailSyncSeconds)
			expect(#h:Section(p, "Market").outbox).toBe(0)
			expect(h:System("Monsters"):Count(p)).toBe(count)
			expect(h:System("Eggs"):Count(p)).toBe(eggs)
			expect(#h:Section(p, "Market").listings).toBe(0)
			for _, l in network.market.listings do
				expect(l.state).toBe("void")
			end
		end)
	end)

	describe("Buying", function()
		it("sells across servers, charges the buyer and mails the seller the price after tax", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7101, "Seller")
			local buyer = rancher(b, 7102, "Buyer")
			local soldTopic = topics(b, "MarketSold")
			local boughtTopic = topics(b, "MarketBought")
			local m = monster(a, seller, { line = "bubblin", rarity = 4 })
			local view = sell(a, seller, m.id, 10000)

			local page = b:Call(buyer, "Market.Browse", {})
			expect(#page.listings).toBe(1)
			expect(page.listings[1].mine).toBe(false)
			local before = b:System("Monsters"):Count(buyer)
			local got = b:Call(buyer, "Market.Buy", { listing = view.id, price = 10000 })
			expect(got.kind).toBe("monster")
			local mine = b:System("Monsters"):Get(buyer, got.id)
			expect(mine.line).toBe("bubblin")
			expect(mine.rarity).toBe(4)
			expect(mine.hidden).toBe(5)
			expect(b:System("Monsters"):Count(buyer)).toBe(before + 1)
			expect(coins(b, buyer)).toBe(COINS - 10000)
			expect(b:Section(buyer, "Market").stats.bought).toBe(1)
			expect(b:Section(buyer, "Market").stats.spent).toBe(10000)

			local record = network.market.listings[view.id]
			expect(record.state).toBe("sold")
			expect(record.buyer).toBe(7102)
			local mail = mailOf(network, 7101)
			expect(#mail).toBe(1)
			expect(mail[1].kind).toBe("coins")
			expect(mail[1].amount).toBe(Cfg.Proceeds(10000, false))
			expect(mail[1].amount).toBe(9200)

			expect(#soldTopic).toBe(1)
			expect(soldTopic[1].player).toBeNil()
			expect(soldTopic[1].detail.proceeds).toBe(9200)
			expect(soldTopic[1].detail.seller).toBe(7101)
			expect(soldTopic[1].detail.buyer).toBe(7102)
			expect(#boughtTopic).toBe(1)
			expect(boughtTopic[1].player).toBe(buyer)

			-- The seller's server collects the mail on its timer.
			a:Advance(Cfg.MailSyncSeconds)
			expect(coins(a, seller)).toBe(COINS + 9200)
			expect(#a:Section(seller, "Market").listings).toBe(0)
			expect(a:Section(seller, "Market").stats.sold).toBe(1)
			expect(a:Section(seller, "Market").stats.earned).toBe(9200)
			local event = a:LastEvent(seller, "Market.MailCollected").payload
			expect(event.coins).toBe(9200)
			expect(event.sold[1]).toEqual({ key = "m:bubblin:4:0", price = 10000, proceeds = 9200, name = "Bubblin" })
			expect(#mailOf(network, 7101)).toBe(0)
			b:Advance(3)
			expect(b:Reject(buyer, "Market.Buy", { listing = view.id, price = 10000 })).toContain("already bought")
			expect(coins(b, buyer)).toBe(COINS - 10000)
		end)

		it("pays a seller on the same server at once", function()
			local network = MockAdapters.network()
			local h = server(network)
			local seller = rancher(h, 7103, "Seller")
			local buyer = rancher(h, 7104, "Buyer")
			local view = sell(h, seller, monster(h, seller).id, 1000)
			h:Call(buyer, "Market.Buy", { listing = view.id, price = 1000 })
			expect(coins(h, seller)).toBe(COINS + 920)
			expect(#mailOf(network, 7103)).toBe(0)
		end)

		it("gives the item to exactly one buyer when two servers buy it at once", function()
			local network = MockAdapters.network()
			local a, b, c = server(network), server(network), server(network)
			local seller = rancher(a, 7110, "Seller")
			local first = rancher(b, 7111, "First")
			local second = rancher(c, 7112, "Second")
			local view = sell(a, seller, monster(a, seller).id, 20000)
			local countFirst, countSecond = b:System("Monsters"):Count(first), c:System("Monsters"):Count(second)

			-- Server C has read the open listing and charged its buyer; server B wins the write.
			local update = c.adapters.Market.Update
			c.adapters.Market.Update = function(id, transform)
				b:Call(first, "Market.Buy", { listing = id, price = 20000 })
				return update(id, transform)
			end
			expect(c:Reject(second, "Market.Buy", { listing = view.id, price = 20000 })).toContain("Someone else")
			c.adapters.Market.Update = update

			expect(coins(c, second)).toBe(COINS)
			expect(c:System("Monsters"):Count(second)).toBe(countSecond)
			expect(coins(b, first)).toBe(COINS - 20000)
			expect(b:System("Monsters"):Count(first)).toBe(countFirst + 1)
			expect(network.market.listings[view.id].buyer).toBe(7111)
			expect(#mailOf(network, 7110)).toBe(1)
			a:Advance(Cfg.MailSyncSeconds)
			expect(coins(a, seller)).toBe(COINS + Cfg.Proceeds(20000))
		end)

		it("holds the charge while a sale can't be confirmed, then refunds it", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7120, "Seller")
			local buyer = rancher(b, 7121, "Buyer")
			local view = sell(a, seller, monster(a, seller).id, 3000)
			local count = b:System("Monsters"):Count(buyer)
			local update = b.adapters.Market.Update
			b.adapters.Market.Update = function()
				return false, nil
			end
			expect(b:Reject(buyer, "Market.Buy", { listing = view.id, price = 3000 })).toContain("The market is busy")
			-- The outcome is unknown: the charge waits in a saved settle task.
			expect(coins(b, buyer)).toBe(COINS - 3000)
			expect(#b:Section(buyer, "Market").outbox).toBe(1)
			b.adapters.Market.Update = update
			b:Advance(Cfg.MailSyncSeconds)
			expect(coins(b, buyer)).toBe(COINS)
			expect(#b:Section(buyer, "Market").outbox).toBe(0)
			expect(b:System("Monsters"):Count(buyer)).toBe(count)
			expect(network.market.listings[view.id].state).toBe("open")
			expect(#mailOf(network, 7120)).toBe(0)
			b:Call(buyer, "Market.Buy", { listing = view.id, price = 3000 })
			expect(coins(b, buyer)).toBe(COINS - 3000)
		end)

		it("keeps the proceeds and retries them when the mailbox can't be reached", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7130, "Seller")
			local buyer = rancher(b, 7131, "Buyer")
			local view = sell(a, seller, monster(a, seller).id, 5000)
			local mailAdd = b.adapters.Market.MailAdd
			b.adapters.Market.MailAdd = function()
				return false
			end
			b:Call(buyer, "Market.Buy", { listing = view.id, price = 5000 })
			expect(#mailOf(network, 7130)).toBe(0)
			expect(#b:Section(buyer, "Market").outbox).toBe(1)
			-- Saved with the buyer's profile: a rejoin (still failing) keeps it.
			buyer = b:Rejoin(buyer, 30)
			expect(#b:Section(buyer, "Market").outbox).toBe(1)
			b:Advance(Cfg.MailSyncSeconds)
			expect(#mailOf(network, 7130)).toBe(0)
			b.adapters.Market.MailAdd = mailAdd
			b:Advance(Cfg.MailSyncSeconds)
			expect(#b:Section(buyer, "Market").outbox).toBe(0)
			local mail = mailOf(network, 7130)
			expect(#mail).toBe(1)
			expect(mail[1].amount).toBe(4600)
			a:Advance(Cfg.MailSyncSeconds)
			expect(coins(a, seller)).toBe(COINS + 4600)
		end)

		it("rejects bad purchases politely and changes nothing", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7140, "Seller")
			local buyer = rancher(b, 7141, "Buyer")
			local view = sell(a, seller, monster(a, seller).id, 4000)
			local eggView = sell(a, seller, a:System("Eggs"):Add(seller, "meadow", "test")[1], 800, nil, "egg")
			local count = b:System("Monsters"):Count(buyer)
			local function unchanged()
				expect(coins(b, buyer)).toBe(COINS)
				expect(b:System("Monsters"):Count(buyer)).toBe(count)
				expect(network.market.listings[view.id].state).toBe("open")
				expect(network.market.listings[eggView.id].state).toBe("open")
				expect(#mailOf(network, 7140)).toBe(0)
			end
			local function reject(p, payload, text)
				b:Advance(1)
				expect(b:Reject(p, "Market.Buy", payload)).toContain(text)
				unchanged()
			end

			expect(a:Reject(seller, "Market.Buy", { listing = view.id, price = 4000 })).toContain("your own")
			reject(buyer, { listing = view.id, price = 3999 }, "price changed")
			reject(buyer, { listing = "L0-0-0", price = 4000 }, "gone")
			network.marketDown = true
			reject(buyer, { listing = view.id, price = 4000 }, BUSY)
			network.marketDown = false

			local fresh = b:Join(7142, "Fresh")
			b:System("Currency"):Add(fresh, "coins", COINS, "test")
			reject(fresh, { listing = view.id, price = 4000 }, "Ranch Level 10")

			setCapacity(b, buyer, count)
			reject(buyer, { listing = view.id, price = 4000 }, "ranch is full")
			setCapacity(b, buyer, 60)

			b:System("Eggs"):Add(buyer, "meadow", "test", b:System("Eggs"):Room(buyer))
			reject(buyer, { listing = eggView.id, price = 800 }, "too many eggs")

			local poor = rancher(b, 7143, "Poor")
			b:System("Currency"):Charge(poor, { coins = coins(b, poor) - 100 }, "test")
			b:Advance(1)
			expect(b:Reject(poor, "Market.Buy", { listing = view.id, price = 4000 })).toContain("Not enough coins")
			expect(coins(b, poor)).toBe(100)
			unchanged()

			-- Only server B's clock moves on: to B the listing has expired.
			b.adapters.advance(Cfg.DurationSeconds)
			reject(buyer, { listing = view.id, price = 4000 }, "expired")
		end)

		it("sells eggs into the buyer's storage", function()
			local network = MockAdapters.network()
			local h = server(network)
			local seller = rancher(h, 7150, "Seller")
			local buyer = rancher(h, 7151, "Buyer")
			local view = sell(h, seller, h:System("Eggs"):Add(seller, "grove", "test")[1], 900, nil, "egg")
			local before = h:System("Eggs"):Count(buyer)
			local got = h:Call(buyer, "Market.Buy", { listing = view.id, price = 900 })
			expect(got.kind).toBe("egg")
			expect(h:System("Eggs"):Get(buyer, got.id).type).toBe("grove")
			expect(h:System("Eggs"):Count(buyer)).toBe(before + 1)
			expect(coins(h, seller)).toBe(COINS + Cfg.Proceeds(900))
		end)
	end)

	describe("Club trading post", function()
		it("shows club listings to members only and pays the club tax", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local owner = rancher(a, 7201, "Owner")
			local id = makeClub(a, owner)
			local member = rancher(b, 7202, "Member")
			b:Call(member, "Clubs.Join", { code = id })
			local outsider = rancher(b, 7203, "Outsider")
			local ownerCoins = coins(a, owner)

			local view = sell(a, owner, monster(a, owner).id, 10000, true)
			expect(view.club).toBe(true)
			expect(network.market.listings[view.id].club).toBe(id)
			expect(#b:Call(member, "Market.Browse", {}).listings).toBe(0)
			local post = b:Call(member, "Market.Browse", { club = true })
			expect(#post.listings).toBe(1)
			expect(post.listings[1].club).toBe(true)
			expect(b:Reject(outsider, "Market.Browse", { club = true })).toContain("not in a club")
			expect(b:Reject(outsider, "Market.Buy", { listing = view.id, price = 10000 })).toContain("members of that club")
			expect(coins(b, outsider)).toBe(COINS)

			b:Call(member, "Market.Buy", { listing = view.id, price = 10000 })
			a:Advance(Cfg.MailSyncSeconds)
			expect(coins(a, owner)).toBe(ownerCoins + Cfg.Proceeds(10000, true))
			-- The club post pays a lower tax than the market, but never zero.
			expect(Cfg.Proceeds(10000, true)).toBe(9600)
			expect(Cfg.Proceeds(10000, true)).toBeGreaterThan(Cfg.Proceeds(10000, false))
		end)
	end)

	describe("Cancel and expiry", function()
		it("cancels a listing and returns the item to the ranch", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7301, "Ana")
			local m = monster(h, p, { line = "mossbun" })
			local count = h:System("Monsters"):Count(p)
			local view = sell(h, p, m.id, 700)
			expect(h:Call(p, "Market.Cancel", { listing = view.id }).returned).toBe(true)
			expect(h:System("Monsters"):Count(p)).toBe(count)
			expect(network.market.listings[view.id].state).toBe("cancelled")
			expect(#h:Section(p, "Market").listings).toBe(0)
			h:Advance(1)
			expect(h:Reject(p, "Market.Cancel", { listing = view.id })).toContain("isn't one of your listings")
			local other = rancher(h, 7302, "Other")
			local view2 = sell(h, p, monster(h, p).id, 700)
			expect(h:Reject(other, "Market.Cancel", { listing = view2.id })).toContain("isn't one of your listings")
			network.marketDown = true
			expect(h:Reject(p, "Market.Cancel", { listing = view2.id })).toContain(BUSY)
			network.marketDown = false
			expect(network.market.listings[view2.id].state).toBe("open")
		end)

		it("refuses to cancel a listing that already sold", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7303, "Seller")
			local buyer = rancher(b, 7304, "Buyer")
			local view = sell(a, seller, monster(a, seller).id, 700)
			b:Call(buyer, "Market.Buy", { listing = view.id, price = 700 })
			local count = a:System("Monsters"):Count(seller)
			expect(a:Reject(seller, "Market.Cancel", { listing = view.id })).toContain("already sold")
			expect(a:System("Monsters"):Count(seller)).toBe(count)
			expect(coins(a, seller)).toBe(COINS + Cfg.Proceeds(700))
			expect(#a:Section(seller, "Market").listings).toBe(0)
		end)

		it("sends a cancelled item to the mailbox when the ranch is full", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7310, "Ana")
			local view = sell(h, p, monster(h, p, { line = "bubblin" }).id, 700)
			local count = h:System("Monsters"):Count(p)
			setCapacity(h, p, count)
			expect(h:Call(p, "Market.Cancel", { listing = view.id }).returned).toBe(false)
			expect(h:System("Monsters"):Count(p)).toBe(count)
			local mail = h:Client(p).session.Market.mail
			expect(#mail.items).toBe(1)
			expect(mail.items[1].key).toBe("m:bubblin:3:0")
			expect(mail.items[1].reason).toBe("cancelled")
			expect(mail.items[1].item.hidden).toBeNil()
			expect(#mailOf(network, 7310)).toBe(1)
			-- Still full on the next sync: it stays in the mailbox.
			h:Advance(Cfg.MailSyncSeconds)
			expect(#mailOf(network, 7310)).toBe(1)
			expect(#h:Client(p).session.Market.mail.items).toBe(1)
			-- Room again: Market.Collect brings it home.
			setCapacity(h, p, count + 5)
			local got = h:Call(p, "Market.Collect")
			expect(#got.items).toBe(1)
			expect(got.left).toBe(0)
			expect(h:System("Monsters"):Get(p, got.items[1].id).line).toBe("bubblin")
			expect(#h:Client(p).session.Market.mail.items).toBe(0)
			expect(#mailOf(network, 7310)).toBe(0)
			local event = h:LastEvent(p, "Market.MailCollected").payload
			expect(event.returned).toBe(1)
		end)

		it("expires listings on the seller's server and returns the item", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7320, "Ana")
			local count = h:System("Monsters"):Count(p)
			local view = sell(h, p, monster(h, p).id, 700)
			h.adapters.advance(Cfg.DurationSeconds)
			h:Advance(Cfg.MailSyncSeconds)
			expect(network.market.listings[view.id].state).toBe("expired")
			expect(h:System("Monsters"):Count(p)).toBe(count + 1)
			expect(#h:Section(p, "Market").listings).toBe(0)
			local event = h:LastEvent(p, "Market.MailCollected").payload
			expect(event.returned).toBe(1)
			expect(#event.items).toBe(1)
		end)

		it("expires on join, to the ranch or to the mailbox when it is full", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7330, "Ana")
			local egg = sell(h, p, h:System("Eggs"):Add(p, "meadow", "test")[1], 700, nil, "egg")
			local mon = sell(h, p, monster(h, p).id, 700)
			local count = h:System("Monsters"):Count(p)
			setCapacity(h, p, count)
			local eggs = h:System("Eggs"):Count(p)
			p = h:Rejoin(p, Cfg.DurationSeconds + 10)
			expect(network.market.listings[egg.id].state).toBe("expired")
			expect(network.market.listings[mon.id].state).toBe("expired")
			expect(h:System("Eggs"):Count(p)).toBe(eggs + 1)
			expect(h:System("Monsters"):Count(p)).toBe(count)
			expect(#h:Section(p, "Market").listings).toBe(0)
			expect(#h:Client(p).session.Market.mail.items).toBe(1)
			expect(h:Client(p).session.Market.mail.items[1].reason).toBe("expired")
		end)
	end)

	describe("Browse", function()
		local Listing = t.Server("Systems.Market.Listing")

		local function inject(network, spec)
			local item = if spec.kind == "egg"
				then { type = spec.egg or "meadow", source = "test", t = 0 }
				else {
					id = "m1",
					line = spec.line or "cindlet",
					stage = 1,
					form = "cindlet",
					rarity = spec.rarity or 1,
					variant = 0,
					muts = {},
					traits = { 1, 2 },
					hidden = 9,
					weight = 3,
					lv = 1,
					stars = 1,
				}
			local listing = Listing.New({
				id = spec.id,
				seller = spec.seller or 1,
				sellerName = "Someone",
				kind = spec.kind or "monster",
				item = item,
				price = spec.price,
				now = spec.now,
				club = spec.club,
			})
			network.market.listings[spec.id] = listing
			return listing
		end

		it("filters by kind and key, sorts three ways and pages", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7401, "Ana")
			local now = h.adapters.Clock.Now()
			for i = 1, 30 do
				inject(network, {
					id = string.format("M%02d", i),
					price = 1000 + i * 10,
					now = now - i,
					line = if i % 2 == 0 then "bubblin" else "cindlet",
				})
			end
			for i = 1, 5 do
				inject(network, { id = "E" .. i, kind = "egg", price = 500 + i, now = now - 100 - i, seller = if i == 1 then 7401 else 2 })
			end
			inject(network, { id = "OLD", price = 1, now = now - Cfg.DurationSeconds - 1 })
			inject(network, { id = "CLUB", price = 2, now = now, club = "ABCDEF" })
			network.market.listings.M30.state = "sold"

			local first = h:Call(p, "Market.Browse", {})
			expect(#first.listings).toBe(Cfg.PageSize)
			expect(first.more).toBe(true)
			expect(first.page).toBe(1)
			expect(first.listings[1].id).toBe("E1") -- cheapest open, unexpired, public
			expect(first.listings[1].mine).toBe(true)
			expect(first.listings[2].mine).toBe(false)
			local second = h:Call(p, "Market.Browse", { page = 2 })
			expect(#second.listings).toBe(29 + 5 - Cfg.PageSize)
			expect(second.more).toBe(false)
			for _, v in second.listings do
				expect(v.id ~= "OLD" and v.id ~= "CLUB" and v.id ~= "M30").toBe(true)
			end

			local monsters = h:Call(p, "Market.Browse", { kind = "monster", sort = "-price" })
			expect(monsters.listings[1].id).toBe("M29")
			expect(monsters.listings[1].kind).toBe("monster")
			for _, v in monsters.listings do
				expect(v.kind).toBe("monster")
			end
			h:Advance(1)
			local bubblin = h:Call(p, "Market.Browse", { key = "m:bubblin:1:0" })
			expect(#bubblin.listings).toBe(14)
			local newest = h:Call(p, "Market.Browse", { kind = "monster", sort = "new" })
			expect(newest.listings[1].id).toBe("M01")
			expect(newest.listings[2].id).toBe("M02")
			local eggs = h:Call(p, "Market.Browse", { kind = "egg" })
			expect(#eggs.listings).toBe(5)

			local v = newest.listings[1]
			for _, field in
				{ "id", "seller", "sellerName", "kind", "key", "price", "createdAt", "expiresAt", "club", "mine", "state", "item" }
			do
				expect(v[field] ~= nil).toBe(true)
			end
			expect(v.item.hidden).toBeNil()
			expect(v.item.id).toBeNil()
			expect(v.item.name).toBeTruthy()
			expect(v.item.traits).toEqual({ 1, 2 })
			expect(v.view).toBeNil()
			expect(v.token).toBeNil()
		end)

		it("reuses a browse result for a few seconds and fails politely when the market is down", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 7402, "Ben")
			local now = h.adapters.Clock.Now()
			inject(network, { id = "A", price = 500, now = now })
			expect(#h:Call(p, "Market.Browse", {}).listings).toBe(1)
			inject(network, { id = "B", price = 600, now = now })
			expect(#h:Call(p, "Market.Browse", {}).listings).toBe(1)
			h:Advance(Cfg.BrowseCacheSeconds)
			expect(#h:Call(p, "Market.Browse", {}).listings).toBe(2)
			network.marketDown = true
			h:Advance(Cfg.BrowseCacheSeconds)
			expect(h:Reject(p, "Market.Browse", {})).toContain(BUSY)
		end)

		it("lists my open listings and drops the ones that sold", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7403, "Seller")
			local buyer = rancher(b, 7404, "Buyer")
			local one = sell(a, seller, monster(a, seller).id, 700)
			local two = sell(a, seller, monster(a, seller).id, 800)
			b:Call(buyer, "Market.Buy", { listing = one.id, price = 700 })
			local mine = a:Call(seller, "Market.Mine")
			expect(#mine.listings).toBe(1)
			expect(mine.listings[1].id).toBe(two.id)
			expect(mine.listings[1].mine).toBe(true)
			expect(a:Section(seller, "Market").listings).toEqual({ two.id })
			network.marketDown = true
			a:Advance(1)
			expect(a:Reject(seller, "Market.Mine")).toContain(BUSY)
			expect(a:Reject(seller, "Market.Collect")).toContain(BUSY)
		end)
	end)

	describe("Mail", function()
		it("collects proceeds on join", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7501, "Seller")
			local buyer = rancher(b, 7502, "Buyer")
			local view = sell(a, seller, monster(a, seller, { line = "mossbun", rarity = 2 }).id, 2500)
			a:Leave(seller)
			b:Call(buyer, "Market.Buy", { listing = view.id, price = 2500 })
			seller = a:Join(7501, "Seller")
			expect(coins(a, seller)).toBe(COINS + Cfg.Proceeds(2500))
			local event = a:LastEvent(seller, "Market.MailCollected").payload
			expect(event.coins).toBe(Cfg.Proceeds(2500))
			expect(event.sold[1].key).toBe("m:mossbun:2:0")
			expect(event.returned).toBe(0)
			expect(#a:Section(seller, "Market").listings).toBe(0)
			expect(#mailOf(network, 7501)).toBe(0)
			-- Nothing new: no event and no coins on the next sync.
			local events = #a:Events(seller, "Market.MailCollected")
			a:Advance(Cfg.MailSyncSeconds)
			expect(#a:Events(seller, "Market.MailCollected")).toBe(events)
			expect(coins(a, seller)).toBe(COINS + Cfg.Proceeds(2500))
		end)

		it("keeps mail that doesn't fit and never loses an item across a full market round trip", function()
			local network = MockAdapters.network()
			local a = server(network)
			local p = rancher(a, 7503, "Ana")
			local views = {}
			for i = 1, 3 do
				views[i] = sell(a, p, monster(a, p, { rarity = i }).id, 700)
			end
			local count = a:System("Monsters"):Count(p)
			setCapacity(a, p, count + 1)
			for i = 1, 3 do
				a:Call(p, "Market.Cancel", { listing = views[i].id })
				a:Advance(1)
			end
			expect(a:System("Monsters"):Count(p)).toBe(count + 1)
			expect(#a:Client(p).session.Market.mail.items).toBe(2)
			setCapacity(a, p, 60)
			a:Advance(Cfg.MailSyncSeconds)
			expect(a:System("Monsters"):Count(p)).toBe(count + 3)
			expect(#a:Client(p).session.Market.mail.items).toBe(0)
			expect(#mailOf(network, 7503)).toBe(0)
		end)
	end)

	describe("Failure safety", function()
		-- A copy of one server's saved profiles, as a crashed server would leave them.
		local function snapshot(h)
			return MockAdapters.deepCopy(h.adapters.store)
		end

		local function rebootWith(network, store)
			local h = server(network)
			h.adapters.store = MockAdapters.deepCopy(store)
			return h
		end

		it("keeps mail in the box when the player leaves while it is being read", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7601, "Sal")
			local buyer = rancher(b, 7602, "Bo")
			local view = sell(a, seller, monster(a, seller).id, 8000)
			local peek = a.adapters.Market.MailPeek
			a.adapters.Market.MailPeek = function(userId)
				local ok, entries = peek(userId)
				a:Leave(seller) -- the player leaves during the read
				return ok, entries
			end
			b:Call(buyer, "Market.Buy", { listing = view.id, price = 8000 })
			a.adapters.Market.MailPeek = peek
			expect(#mailOf(network, 7601)).toBe(1) -- still waiting, not lost
			local back = a:Rejoin(seller, 5)
			a:Advance(2)
			expect(coins(a, back)).toBe(COINS + Cfg.Proceeds(8000, false))
			expect(#mailOf(network, 7601)).toBe(0)
		end)

		it("delivers exactly once when a sale lands but reports failure", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7611, "Sal")
			local buyer = rancher(b, 7612, "Bo")
			local view = sell(a, seller, monster(a, seller).id, 6000)
			local count = b:System("Monsters"):Count(buyer)
			local update = b.adapters.Market.Update
			local lied = false
			b.adapters.Market.Update = function(id, transform)
				local ok, result = update(id, transform)
				if not lied and result ~= nil then
					lied = true
					return false, nil -- the write happened; the reply was lost
				end
				return ok, result
			end
			b:Call(buyer, "Market.Buy", { listing = view.id, price = 6000 })
			b.adapters.Market.Update = update
			expect(lied).toBe(true)
			expect(coins(b, buyer)).toBe(COINS - 6000)
			expect(b:System("Monsters"):Count(buyer)).toBe(count + 1)
			a:Advance(Cfg.MailSyncSeconds)
			expect(coins(a, seller)).toBe(COINS + Cfg.Proceeds(6000, false))
		end)

		it("never pays twice when a mail delivery lands but reports failure", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7621, "Sal")
			local buyer = rancher(b, 7622, "Bo")
			local view = sell(a, seller, monster(a, seller).id, 9000)
			local add = b.adapters.Market.MailAdd
			b.adapters.Market.MailAdd = function(userId, entry)
				add(userId, entry)
				return false -- delivered, but the reply was lost: the buyer's server retries it
			end
			b:Call(buyer, "Market.Buy", { listing = view.id, price = 9000 })
			expect(#b:Section(buyer, "Market").outbox).toBe(1)
			b.adapters.Market.MailAdd = add
			b:Advance(Cfg.MailSyncSeconds) -- the retry is skipped by the mailbox (same id)
			expect(#b:Section(buyer, "Market").outbox).toBe(0)
			a:Advance(Cfg.MailSyncSeconds)
			expect(coins(a, seller)).toBe(COINS + Cfg.Proceeds(9000, false))
			a:Advance(Cfg.MailSyncSeconds)
			expect(coins(a, seller)).toBe(COINS + Cfg.Proceeds(9000, false))
		end)

		it("recovers a listing when the server dies right after the market write", function()
			local network = MockAdapters.network()
			local a = server(network)
			local seller = rancher(a, 7631, "Sal")
			local m = monster(a, seller)
			local count = a:System("Monsters"):Count(seller)
			local saved
			local create = a.adapters.Market.Create
			a.adapters.Market.Create = function(listing)
				local ok = create(listing)
				saved = snapshot(a) -- the server dies here: this is all that was saved
				return ok
			end
			local view = a:Call(seller, "Market.List", { kind = "monster", id = m.id, price = 700 }).listing
			local b = rebootWith(network, saved)
			local back = b:Join(7631, "Sal")
			b:Advance(2)
			-- The saved profile never had the monster after listing: no duplicate…
			expect(b:System("Monsters"):Get(back, m.id)).toBeNil()
			expect(b:System("Monsters"):Count(back)).toBe(count - 1)
			-- …and the listing is still theirs and still for sale.
			expect(table.find(b:Section(back, "Market").listings, view.id) ~= nil).toBe(true)
			expect(#b:Section(back, "Market").outbox).toBe(0)
			expect(network.market.listings[view.id].state).toBe("open")
		end)

		it("recovers a purchase when the buyer's server dies right after the sale", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7641, "Sal")
			local buyer = rancher(b, 7642, "Bo")
			local view = sell(a, seller, monster(a, seller).id, 4000)
			local count = b:System("Monsters"):Count(buyer)
			local saved
			local update = b.adapters.Market.Update
			b.adapters.Market.Update = function(id, transform)
				local ok, result = update(id, transform)
				if saved == nil and result ~= nil and result.state == "sold" then
					saved = snapshot(b) -- the server dies here
				end
				return ok, result
			end
			b:Call(buyer, "Market.Buy", { listing = view.id, price = 4000 })
			local c = rebootWith(network, saved)
			local back = c:Join(7642, "Bo")
			c:Advance(2)
			expect(coins(c, back)).toBe(COINS - 4000) -- charged once
			expect(c:System("Monsters"):Count(back)).toBe(count + 1) -- and got the monster
			expect(#c:Section(back, "Market").outbox).toBe(0)
			a:Advance(Cfg.MailSyncSeconds)
			expect(coins(a, seller)).toBe(COINS + Cfg.Proceeds(4000, false))
		end)

		it("refuses a second purchase while one is still running", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local seller = rancher(a, 7651, "Sal")
			local buyer = rancher(b, 7652, "Bo")
			local first = sell(a, seller, monster(a, seller).id, 1000)
			local second = sell(a, seller, monster(a, seller).id, 1000)
			local update = b.adapters.Market.Update
			local nested = nil
			b.adapters.Market.Update = function(id, transform)
				if nested == nil then
					nested = b:Invoke(buyer, "Market.Buy", { listing = second.id, price = 1000 })
				end
				return update(id, transform)
			end
			b:Call(buyer, "Market.Buy", { listing = first.id, price = 1000 })
			b.adapters.Market.Update = update
			expect(nested.ok).toBe(false)
			expect(nested.err).toContain("last purchase")
		end)
	end)
end
