-- Glow-up L: gifts to friends through the Market mailbox (gates, caps, confirm token, offline
-- delivery, a Ranch Pass bought for a friend), monster tricks, invites, the group reward,
-- Premium perks and the VIP balcony gate. Pure rules in Logic/Community.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Community")
	local Cfg = Config.Community
	local G = Cfg.Gifts

	local GIFT_SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Accessories" }
	for _, name in { "Market", "Monetization", "Quests", "Gifts" } do
		table.insert(GIFT_SYSTEMS, name)
	end

	local function server(network, startTime)
		return TestKernel.new({ systems = GIFT_SYSTEMS, network = network or MockAdapters.network(), startTime = startTime })
	end

	local function befriend(h, a, b)
		h.adapters.friends[a] = h.adapters.friends[a] or {}
		h.adapters.friends[a][b] = true
		h.adapters.friends[b] = h.adapters.friends[b] or {}
		h.adapters.friends[b][a] = true
	end

	-- A sender past every gate.
	local function veteran(h, userId, name)
		local p = h:Join(userId, name)
		h:System("Progression"):AddXP(p, 1e6, "test")
		h.kernel.Data:Get(p)._meta.playSeconds = G.minPlaySeconds + 60
		return p
	end

	local function eggIds(h, p)
		local ids = {}
		for id in h:Section(p, "Eggs").list do
			table.insert(ids, id)
		end
		table.sort(ids)
		return ids
	end

	local function eggTypes(h, p, eggType)
		local n = 0
		for _, record in h:Section(p, "Eggs").list do
			if record.type == eggType then
				n += 1
			end
		end
		return n
	end

	local function gift(h, p, to, kind, item, amount)
		local prep = h:Call(p, "Gifts.Prepare", { to = to, kind = kind, item = item, amount = amount or 1 })
		return h:Call(p, "Gifts.Send", { token = prep.token }), prep
	end

	describe("Logic/Community", function()
		it("counts UTC weeks from Monday", function()
			-- Day 0 (1 Jan 1970) was a Thursday; day 4 was the first Monday.
			expect(Logic.Week(3)).toBe(Logic.Week(0))
			expect(Logic.Week(4)).toBe(Logic.Week(0) + 1)
			expect(Logic.Week(10)).toBe(Logic.Week(4))
			expect(Logic.Week(11)).toBe(Logic.Week(4) + 1)
		end)

		it("reads only our own invite launch data", function()
			local prefix = Cfg.Invites.launchPrefix
			expect(Logic.ParseInvite(Logic.InviteData(12345, prefix), prefix)).toBe(12345)
			expect(Logic.ParseInvite({ LaunchData = "invite:77" }, prefix)).toBe(77)
			expect(Logic.ParseInvite("invite:", prefix)).toBe(nil)
			expect(Logic.ParseInvite("invite:12a", prefix)).toBe(nil)
			expect(Logic.ParseInvite("invite:0", prefix)).toBe(nil)
			expect(Logic.ParseInvite("hello", prefix)).toBe(nil)
			expect(Logic.ParseInvite(nil, prefix)).toBe(nil)
			expect(Logic.ParseInvite(string.rep("9", 80), prefix)).toBe(nil)
		end)

		it("gates senders by level, play time and account age", function()
			local ok, why, need = Logic.GiftGate({ level = G.minLevel - 1, playSeconds = 1e9 }, G)
			expect(ok).toBe(false)
			expect(why).toBe("level")
			expect(need).toBe(G.minLevel)
			ok, why, need = Logic.GiftGate({ level = G.minLevel, playSeconds = G.minPlaySeconds - 10 }, G)
			expect(why).toBe("play")
			expect(need).toBe(10)
			ok, why = Logic.GiftGate({ level = G.minLevel, playSeconds = G.minPlaySeconds, accountDays = 1 }, G)
			expect(why).toBe("account")
			ok = Logic.GiftGate({ level = G.minLevel, playSeconds = G.minPlaySeconds, accountDays = G.minAccountDays }, G)
			expect(ok).toBe(true)
			expect((Logic.GiftGate({ level = 99, playSeconds = 1e9 }, G))).toBe(true) -- unknown age passes
		end)

		it("counts gifts left today overall and per friend", function()
			local left, forFriend = Logic.DailyLeft({ sent = 1, to = { u5 = G.perFriendPerDay } }, G, "u5")
			expect(left).toBe(G.perDay - 1)
			expect(forFriend).toBe(0)
			left, forFriend = Logic.DailyLeft({ sent = G.perDay, to = {} }, G, "u6")
			expect(left).toBe(0)
			expect(forFriend).toBe(0)
		end)

		it("knows the VIP deck's box", function()
			local b = Cfg.VipBalcony
			local floor = b.deck[2] + b.height
			expect(Logic.InDeck({ b.deck[1], floor + 3, b.deck[3] }, b)).toBe(true)
			expect(Logic.InDeck({ b.deck[1], 3, b.deck[3] }, b)).toBe(false) -- under the deck
			expect(Logic.InDeck({ b.pad[1], 3, b.pad[3] }, b)).toBe(false)
			expect(Logic.InDeck({ b.deck[1] + b.deckSize[1], floor + 3, b.deck[3] }, b)).toBe(false)
		end)
	end)

	describe("Gifts", function()
		it("sends an egg to an offline friend, who gets it on their next join", function()
			local network = MockAdapters.network()
			local a = server(network)
			local sender = veteran(a, 9101, "Ana")
			befriend(a, 9101, 9102)
			a:System("Eggs"):Add(sender, "grove", "test", 2)
			local before = #eggIds(a, sender)
			local sent, prep = gift(a, sender, 9102, "egg", eggIds(a, sender)[1])
			expect(prep.left).toBe(G.perDay)
			expect(sent.left).toBe(G.perDay - 1)
			expect(#eggIds(a, sender)).toBe(before - 1)
			expect(a:Section(sender, "Gifts").totalSent).toBe(1)
			expect(#a:Section(sender, "Market").outbox).toBe(0) -- delivered to the mailbox

			local b = server(network)
			local friend = b:Join(9102, "Bo")
			expect(eggTypes(b, friend, "grove")).toBe(1)
			expect(b:Section(friend, "Gifts").totalReceived).toBe(1)
			local granted = b:LastEvent(friend, "Rewards.Granted")
			expect(granted ~= nil).toBe(true)
			-- Collected once: a second sync and a rejoin add nothing.
			b:System("Market"):Sync(friend)
			local again = b:Rejoin(friend, 60)
			expect(eggTypes(b, again, "grove")).toBe(1)
		end)

		it("sends food, decor and stored accessories", function()
			local h = server()
			local sender = veteran(h, 9111)
			local friend = h:Join(9112)
			befriend(h, 9111, 9112)
			local flavor = Config.Food.Ids[1]
			h:System("Currency"):Add(sender, "food." .. flavor, 30, "test")
			gift(h, sender, 9112, "food", flavor, 12)
			expect(h:System("Currency"):Balance(sender, "food." .. flavor)).toBe(18)
			local decorId = Config.Decor.List[1].id
			h:System("Shop"):AddDecor(sender, decorId, 1)
			gift(h, sender, 9112, "decor", decorId)
			expect(h:System("Shop"):DecorCount(sender, decorId)).toBe(0)
			local accId = Config.Accessories.List[1].id
			h:System("Accessories"):Add(sender, accId, 1)
			h:Advance(86400) -- a new day: the per-friend cap resets
			gift(h, sender, 9112, "accessory", accId)
			expect(h:System("Accessories"):Stored(sender, accId)).toBe(0)

			h:System("Market"):Sync(friend)
			expect(h:System("Currency"):Balance(friend, "food." .. flavor)).toBe(12)
			expect(h:System("Shop"):DecorCount(friend, decorId)).toBe(1)
			expect(h:System("Accessories"):Stored(friend, accId)).toBe(1)
			expect(h:Section(friend, "Gifts").totalReceived).toBe(3)
		end)

		it("refuses strangers, yourself, and senders below the gates", function()
			local h = server()
			local sender = veteran(h, 9121)
			h:System("Eggs"):Add(sender, "grove", "test", 1)
			local egg = eggIds(h, sender)[1]
			local payload = { to = 9122, kind = "egg", item = egg, amount = 1 }
			expect(h:Reject(sender, "Gifts.Prepare", payload)).toContain("Roblox friends")
			h:Advance(2)
			expect(h:Reject(sender, "Gifts.Prepare", { to = 9121, kind = "egg", item = egg, amount = 1 })).toContain("yourself")

			local fresh = h:Join(9123)
			befriend(h, 9123, 9122)
			h:System("Eggs"):Add(fresh, "grove", "test", 1)
			local freshEgg = eggIds(h, fresh)[1]
			expect(h:Reject(fresh, "Gifts.Prepare", { to = 9122, kind = "egg", item = freshEgg, amount = 1 })).toContain(
				string.format("Ranch Level %d", G.minLevel)
			)
			h:System("Progression"):AddXP(fresh, 1e6, "test")
			h:Advance(2)
			expect(h:Reject(fresh, "Gifts.Prepare", { to = 9122, kind = "egg", item = freshEgg, amount = 1 })).toContain("more play time")
		end)

		it("checks the item at both steps, spends the token once and expires it", function()
			local h = server()
			local sender = veteran(h, 9131)
			befriend(h, 9131, 9132)
			local flavor = Config.Food.Ids[1]
			expect(h:Reject(sender, "Gifts.Prepare", { to = 9132, kind = "food", item = flavor, amount = 5 })).toContain("much food")
			h:System("Currency"):Add(sender, "food." .. flavor, 5, "test")
			h:Advance(2)
			local prep = h:Call(sender, "Gifts.Prepare", { to = 9132, kind = "food", item = flavor, amount = 5 })
			h:System("Currency"):Spend(sender, { ["food." .. flavor] = 1 }, "test") -- spent between the steps
			expect(h:Reject(sender, "Gifts.Send", { token = prep.token })).toContain("much food")
			h:Advance(2)
			expect(h:Reject(sender, "Gifts.Send", { token = prep.token })).toContain("expired") -- one token, one try
			h:Advance(2)
			local again = h:Call(sender, "Gifts.Prepare", { to = 9132, kind = "food", item = flavor, amount = 4 })
			h:Advance(G.confirmSeconds + 1)
			expect(h:Reject(sender, "Gifts.Send", { token = again.token })).toContain("expired")
			expect(h:System("Currency"):Balance(sender, "food." .. flavor)).toBe(4)
			-- Only eggs in storage, never one in an incubator or someone else's.
			h:Advance(2)
			expect(h:Reject(sender, "Gifts.Prepare", { to = 9132, kind = "egg", item = "e999", amount = 1 })).toContain("storage")
			local accId = Config.Accessories.List[1].id
			h:Advance(2)
			expect(h:Reject(sender, "Gifts.Prepare", { to = 9132, kind = "accessory", item = accId, amount = 1 })).toContain("storage")
		end)

		it("caps gifts per day and per friend, and resets the next UTC day", function()
			local h = server()
			local sender = veteran(h, 9141)
			local flavor = Config.Food.Ids[1]
			h:System("Currency"):Add(sender, "food." .. flavor, 100, "test")
			for i = 2, 5 do
				befriend(h, 9141, 9140 + i)
			end
			for _ = 1, G.perFriendPerDay do
				gift(h, sender, 9142, "food", flavor, 1)
				h:Advance(1)
			end
			expect(h:Reject(sender, "Gifts.Prepare", { to = 9142, kind = "food", item = flavor, amount = 1 })).toContain("this friend")
			local sent = G.perFriendPerDay
			local friend = 9143
			while sent < G.perDay do
				h:Advance(1)
				gift(h, sender, friend, "food", flavor, 1)
				sent += 1
				if sent % G.perFriendPerDay == 0 then
					friend += 1
				end
			end
			h:Advance(1)
			expect(h:Reject(sender, "Gifts.Prepare", { to = 9145, kind = "food", item = flavor, amount = 1 })).toContain("More tomorrow")
			h:Advance(86400)
			gift(h, sender, 9142, "food", flavor, 1)
		end)

		it("keeps an egg in the mailbox while the friend's storage is full", function()
			local h = server()
			local sender = veteran(h, 9151)
			local friend = h:Join(9152)
			befriend(h, 9151, 9152)
			h:System("Eggs"):Add(friend, "meadow", "test", Config.Economy.MaxEggs)
			h:System("Eggs"):Add(sender, "grove", "test", 1)
			gift(h, sender, 9152, "egg", eggIds(h, sender)[1])
			h:System("Market"):Sync(friend)
			expect(eggTypes(h, friend, "grove")).toBe(0)
			local Eggs = h:System("Eggs")
			Eggs:Remove(friend, eggIds(h, friend)[1])
			h:System("Market"):Sync(friend)
			expect(eggTypes(h, friend, "grove")).toBe(1)
		end)

		it("keeps a gift in the sender's saved outbox while the mailbox is down", function()
			local network = MockAdapters.network()
			local h = server(network)
			local sender = veteran(h, 9161)
			befriend(h, 9161, 9162)
			local flavor = Config.Food.Ids[1]
			h:System("Currency"):Add(sender, "food." .. flavor, 3, "test")
			network.marketDown = true
			gift(h, sender, 9162, "food", flavor, 3)
			expect(#h:Section(sender, "Market").outbox).toBe(1)
			network.marketDown = false
			h:System("Market"):Sync(sender)
			expect(#h:Section(sender, "Market").outbox).toBe(0)
			local friend = h:Join(9162)
			expect(h:System("Currency"):Balance(friend, "food." .. flavor)).toBe(3)
		end)
	end)

	describe("Ranch Pass gift", function()
		local Q = Config.Quests
		local IN_SEASON = Q.Pass.startsAt + 3600
		local product = Config.Monetization.ProductByKey[Cfg.PassGift.product]

		local function withProduct(fn)
			local saved = product.productId
			product.productId = 8851
			local ok, err = pcall(fn)
			product.productId = saved
			if not ok then
				error(err, 0)
			end
		end

		local function receipt(h, p, purchaseId)
			return h.adapters._processReceipt({
				PlayerId = p.UserId,
				ProductId = 8851,
				PurchaseId = purchaseId,
				CurrencySpent = product.price,
			})
		end

		it("needs a friend picked first, then mails the pass; a second one is saved for next season", function()
			withProduct(function()
				local h = server(nil, IN_SEASON)
				local buyer = h:Join(9201)
				local friend = h:Join(9202)
				expect(h:Reject(buyer, "Monetization.CanBuy", { product = product.key })).toContain("Pick a friend")
				h:Advance(2)
				expect(h:Reject(buyer, "Gifts.PassTarget", { to = 9202 })).toContain("Roblox friends")
				befriend(h, 9201, 9202)
				h:Advance(2)
				h:Call(buyer, "Gifts.PassTarget", { to = 9202 })
				h:Advance(2)
				h:Call(buyer, "Monetization.CanBuy", { product = product.key })
				expect(receipt(h, buyer, "pg1")).toBe("PurchaseGranted")
				expect(receipt(h, buyer, "pg1")).toBe("PurchaseGranted") -- replayed receipt: no second mail
				h:System("Market"):Sync(friend)
				expect(h:Section(friend, "Quests").pass.premium).toBe(true)
				expect(h:Section(buyer, "Quests").pass.premium).toBe(false)

				h:Advance(2)
				h:Call(buyer, "Gifts.PassTarget", { to = 9202 })
				expect(receipt(h, buyer, "pg2")).toBe("PurchaseGranted")
				h:System("Market"):Sync(friend)
				expect(h:Section(friend, "Quests").passCredit).toBe(1) -- never a duplicate: banked
			end)
		end)

		it("gives the pass to the buyer when the pick went stale", function()
			withProduct(function()
				local h = server(nil, IN_SEASON)
				local buyer = h:Join(9211)
				befriend(h, 9211, 9212)
				h:Call(buyer, "Gifts.PassTarget", { to = 9212 })
				h:Advance(Cfg.PassGift.targetSeconds + 5)
				expect(receipt(h, buyer, "pg3")).toBe("PurchaseGranted")
				expect(h:Section(buyer, "Quests").pass.premium).toBe(true)
			end)
		end)
	end)

	describe("Community", function()
		local function boot(opts)
			opts = opts or {}
			local vip = {}
			local pens = {}
			local h = TestKernel.new({
				systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Market", "Community" },
				network = opts.network,
				stubs = {
					Monetization = {
						HasPass = function(_, player, key)
							return key == "vip" and vip[player.UserId] == true
						end,
					},
					Ranch = {
						PenOf = function(_, _player, id)
							return pens[id] or 0
						end,
					},
				},
			})
			return h, vip, pens
		end

		local function monster(h, p)
			return h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1 }, "test", true)
		end

		it("plays a trick for everyone, for the player's own pen monsters only, with a cooldown", function()
			local h, _, pens = boot()
			local p = h:Join(9301)
			local other = h:Join(9302)
			local m = monster(h, p)
			monster(h, other)
			local theirs = monster(h, other) -- ids count per player: this one only exists for `other`
			expect(h:Reject(p, "Community.Trick", { id = m.id, trick = "trick" })).toContain("pens")
			pens[m.id] = 1
			pens[theirs.id] = 1
			h:Advance(2)
			expect(h:Reject(p, "Community.Trick", { id = theirs.id, trick = "trick" })).toContain("doesn't exist")
			h:Advance(2)
			expect(h:Call(p, "Community.Trick", { id = m.id, trick = "trick" }).state).toBe("trick")
			local seen = h:LastEvent(other, "Community.Trick")
			expect(seen.payload.owner).toBe(9301)
			expect(seen.payload.id).toBe(m.id)
			expect(h:Reject(p, "Community.Trick", { id = m.id, trick = "hop" })).toContain("rest")
			h:Advance(Cfg.TrickCooldown)
			h:Call(p, "Community.Trick", { id = m.id, trick = "hop" })
		end)

		it("rewards an invited friend once and mails the inviter, capped per week", function()
			local network = MockAdapters.network()
			local h = boot({ network = network })
			local inviterId = 9400
			h.adapters.Players.JoinData = function(player)
				if player.UserId == 9499 then
					return { LaunchData = "invite:9400" } -- not a friend
				end
				return { LaunchData = Logic.InviteData(inviterId, Cfg.Invites.launchPrefix) }
			end
			local joined = {}
			for i = 1, Cfg.Invites.weeklyCap + 1 do
				befriend(h, inviterId, 9400 + i)
				local p = h:Join(9400 + i)
				table.insert(joined, p)
				expect(h:Section(p, "Community").invitedBy).toBe(inviterId)
				expect(eggTypes(h, p, "grove")).toBe(1)
			end
			local stranger = h:Join(9499)
			expect(h:Section(stranger, "Community").invitedBy).toBe(0)
			-- A rejoin is not a first join.
			local back = h:Rejoin(joined[1], 60)
			expect(eggTypes(h, back, "grove")).toBe(1)

			local inviter = h:Join(inviterId)
			local s = h:Section(inviter, "Community")
			expect(s.invitesTotal).toBe(Cfg.Invites.weeklyCap + 1)
			expect(s.invites.count).toBe(Cfg.Invites.weeklyCap)
			expect(eggTypes(h, inviter, "grove")).toBe(Cfg.Invites.weeklyCap)
		end)

		it("keeps the group reward closed while GroupId is 0, then pays members once", function()
			local h = boot()
			local p = h:Join(9501)
			expect(h:Reject(p, "Community.ClaimGroup")).toBe("Coming soon")
			local saved = Config.Quests.GroupId
			Config.Quests.GroupId = 424242
			local ok, err = pcall(function()
				h:Advance(3)
				expect(h:Reject(p, "Community.ClaimGroup")).toContain("Join our Roblox group")
				h.adapters.groups[9501] = { [424242] = true }
				h:Advance(3)
				local res = h:Call(p, "Community.ClaimGroup")
				expect(#res.rewards > 0).toBe(true)
				expect(eggTypes(h, p, "crystal")).toBe(1)
				h:Advance(3)
				expect(h:Reject(p, "Community.ClaimGroup")).toBe("Already claimed")
			end)
			Config.Quests.GroupId = saved
			if not ok then
				error(err, 0)
			end
		end)

		it("gives Premium members a daily egg and lists them for the badge", function()
			local h = boot()
			local members = { [9602] = true }
			h.adapters.Players.IsPremium = function(player)
				return members[player.UserId] == true
			end
			local plain = h:Join(9601)
			local member = h:Join(9602)
			expect(h:Client(member).global.Community.premium.u9602).toBe(true)
			expect(h:Client(member).global.Community.premium.u9601).toBe(nil)
			expect(h:Reject(plain, "Community.ClaimPremium")).toContain("Premium members")
			h:Call(member, "Community.ClaimPremium")
			expect(eggTypes(h, member, "grove")).toBe(1)
			h:Advance(3)
			expect(h:Reject(member, "Community.ClaimPremium")).toContain("tomorrow")
			h:Advance(86400)
			h:Call(member, "Community.ClaimPremium")
			expect(eggTypes(h, member, "grove")).toBe(2)
		end)

		it("lets only VIP owners up to the balcony and moves anyone else off it", function()
			local h, vip = boot()
			local positions, moves = {}, {}
			h.adapters.Characters = {
				Position = function(player)
					return positions[player.UserId]
				end,
				MoveTo = function(player, to)
					positions[player.UserId] = to
					table.insert(moves, { userId = player.UserId, to = to })
					return true
				end,
			}
			local guest = h:Join(9701)
			local owner = h:Join(9702)
			vip[9702] = true
			expect(h:Reject(guest, "Community.Balcony", { enter = true })).toContain("VIP")
			h:Call(owner, "Community.Balcony", { enter = true })
			expect(Logic.InDeck(positions[9702], Cfg.VipBalcony)).toBe(true)
			-- The guest climbs up anyway: the patrol puts them back on the plaza.
			local b = Cfg.VipBalcony
			positions[9701] = { b.deck[1], b.deck[2] + b.height + 3, b.deck[3] }
			h:Advance(b.patrolSeconds + 1)
			expect(Logic.InDeck(positions[9701], b)).toBe(false)
			expect(Logic.InDeck(positions[9702], b)).toBe(true)
			h:Advance(2)
			h:Call(owner, "Community.Balcony", { enter = false })
			expect(Logic.InDeck(positions[9702], b)).toBe(false)
			expect(#moves).toBe(3)
		end)
	end)
end
