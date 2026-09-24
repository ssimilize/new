-- S5 Trade: gates, request/respond, offers, ready/confirm countdown, atomic execution with
-- capacity checks, cancellation on change and on leave. Eggs is an in-memory stub.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")

	local Rules = Config.Social.Trade

	-- Monsters capacity providers outlive a TestKernel; this one answers only for this spec's players.
	local capacity = {}
	local providerRegistered = false
	local function setCapacity(M, p, n)
		if not providerRegistered then
			providerRegistered = true
			M:RegisterCapacityProvider(function(player)
				return capacity[player.UserId] or 0
			end)
		end
		capacity[p.UserId] = 0
		capacity[p.UserId] = n - M:Capacity(p)
	end

	local function eggStub()
		local store, nextId = {}, 0
		local stub = { incubating = {}, countOverride = {} }
		local function bag(p)
			store[p.UserId] = store[p.UserId] or {}
			return store[p.UserId]
		end
		function stub.give(p, eggType)
			nextId += 1
			local id = "e" .. nextId
			bag(p)[id] = { type = eggType, source = "test", t = 0 }
			return id
		end
		function stub.Get(_, p, id)
			return bag(p)[id]
		end
		function stub.Remove(_, p, id)
			local record = bag(p)[id]
			bag(p)[id] = nil
			return record
		end
		function stub.Insert(_, p, record, _source)
			nextId += 1
			local id = "e" .. nextId
			bag(p)[id] = table.clone(record)
			return id
		end
		function stub.Count(_, p)
			if stub.countOverride[p.UserId] then
				return stub.countOverride[p.UserId]
			end
			local n = 0
			for _ in bag(p) do
				n += 1
			end
			return n
		end
		function stub.IsIncubating(_, _p, id)
			return stub.incubating[id] == true
		end
		stub.bag = bag
		return stub
	end

	local function levelTo(h, p, level)
		local xp = 0
		for l = 1, level - 1 do
			xp += Config.Unlocks.XPToNext(l)
		end
		h:System("Progression"):AddXP(p, xp, "test")
	end

	local function ready(h, p, options)
		local opts = options or {}
		levelTo(h, p, opts.level or 8)
		h.kernel.Data:Get(p)._meta.playSeconds = opts.playSeconds or 3600
		setCapacity(h:System("Monsters"), p, 100)
	end

	local function boot()
		local eggs = eggStub()
		local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Trade" }, stubs = { Eggs = eggs } })
		local a, b = h:Join(nil, "Alice"), h:Join(nil, "Bob")
		ready(h, a)
		ready(h, b)
		return h, a, b, h:System("Monsters"), eggs
	end

	local function monster(M, p, fields)
		local spec = { line = "cindlet", rarity = 2, traits = { 3, 4 }, hidden = 5 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return M:Create(p, spec, "test", true)
	end

	local function open(h, a, b)
		h:Call(a, "Trade.Request", { target = b.UserId })
		h:Call(b, "Trade.Respond", { from = a.UserId, accept = true })
	end

	local function readyUp(h, a, b)
		h:Call(a, "Trade.SetReady", { ready = true })
		h:Call(b, "Trade.SetReady", { ready = true })
		h:Call(a, "Trade.Confirm")
		h:Call(b, "Trade.Confirm")
	end

	local function session(h, p)
		return h:Client(p).session.Trade
	end

	describe("Trade requests", function()
		it("checks level, playtime, presence and the feature flag", function()
			local h, a, b = boot()
			local c = h:Join(nil, "Cleo")
			expect(h:Reject(a, "Trade.Request", { target = a.UserId })).toContain("yourself")
			expect(h:Reject(a, "Trade.Request", { target = 424242 })).toContain("isn't on this server")
			h:Advance(2)
			expect(h:Reject(c, "Trade.Request", { target = a.UserId })).toContain("Ranch Level 8")
			expect(h:Reject(a, "Trade.Request", { target = c.UserId })).toContain("hasn't unlocked trading")
			h:Advance(2)
			levelTo(h, c, 8)
			h.kernel.Data:Get(c)._meta.playSeconds = 10 * 60
			expect(h:Reject(c, "Trade.Request", { target = a.UserId })).toContain("20 more minutes")
			expect(h:Reject(a, "Trade.Request", { target = c.UserId })).toContain("playtime")
			-- this session's time counts too
			h:Advance(20 * 60)
			h:Call(c, "Trade.Request", { target = a.UserId })
			h:Call(c, "Trade.Cancel")

			Config.Flags.Trading = false
			local ok, err = pcall(function()
				expect(h:Reject(a, "Trade.Request", { target = b.UserId })).toContain("turned off")
			end)
			Config.Flags.Trading = true
			assert(ok, err)
		end)

		it("sends an incoming request that can be declined or expire", function()
			local h, a, b = boot()
			local c = h:Join(nil, "Cleo")
			ready(h, c)
			h:Call(a, "Trade.Request", { target = b.UserId })
			local incoming = h:LastEvent(b, "Trade.Incoming")
			expect(incoming.payload.from).toBe(a.UserId)
			expect(incoming.payload.name).toBe("Alice")
			expect(session(h, a).status).toBe("outgoing")
			expect(session(h, b).status).toBe("incoming")
			expect(session(h, b).partner.name).toBe("Alice")
			expect(h:Reject(c, "Trade.Request", { target = b.UserId })).toContain("busy trading")
			expect(h:Reject(a, "Trade.Request", { target = c.UserId })).toContain("Finish your current trade")
			expect(h:Reject(c, "Trade.Respond", { from = a.UserId, accept = true })).toContain("expired")

			h:Call(b, "Trade.Respond", { from = a.UserId, accept = false })
			expect(session(h, a).status).toBe("none")
			expect(session(h, b).status).toBe("none")
			expect(h:LastEvent(a, "Kernel.Notify").payload.text).toContain("declined")

			h:Advance(2)
			h:Call(a, "Trade.Request", { target = b.UserId })
			h:Advance(Rules.requestTimeout + 1)
			expect(session(h, a).status).toBe("none")
			expect(session(h, b).status).toBe("none")
			expect(h:LastEvent(a, "Kernel.Notify").payload.text).toContain("didn't answer")
			expect(h:Reject(b, "Trade.Respond", { from = a.UserId, accept = true })).toContain("expired")
		end)
	end)

	describe("Trading", function()
		it("swaps monsters and eggs atomically after ready, confirm and the countdown", function()
			local h, a, b, M, eggs = boot()
			local completed = {}
			h.kernel.Bus:Subscribe("TradeCompleted", function(player, detail)
				completed[player] = detail
			end)
			local ma = monster(M, a, { line = "cindlet", rarity = 3, muts = { "soaked" } })
			local mb = monster(M, b, { line = "mossbun", rarity = 4 })
			local egg = eggs.give(a, "grove")
			local aCount, bCount = M:Count(a), M:Count(b)
			open(h, a, b)
			expect(session(h, a).status).toBe("open")
			expect(session(h, b).partner.userId).toBe(a.UserId)

			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = ma.id }, { kind = "egg", id = egg } } })
			h:Call(b, "Trade.SetOffer", { items = { { kind = "monster", id = mb.id } } })
			expect(ma.busy).toBe("trade")
			local view = session(h, b)
			expect(#view.theirs.items).toBe(2)
			expect(view.theirs.items[1].appearance.muts).toEqual({ "soaked" })
			expect(view.theirs.items[2].egg).toBe("grove")
			expect(view.theirs.items[2].appearance).toBe(false)
			expect(view.mine.items[1].kind).toBe("monster")

			readyUp(h, a, b)
			expect(session(h, a).status).toBe("countdown")
			expect(session(h, a).endsAt).toBe(h.adapters.Clock.Now() + Rules.countdownSeconds)
			expect(session(h, b).mine.confirmed).toBe(true)
			h:Advance(Rules.countdownSeconds)

			expect(M:Get(a, ma.id)).toBeNil()
			expect(M:Get(b, mb.id)).toBeNil()
			expect(M:Count(a)).toBe(aCount)
			expect(M:Count(b)).toBe(bCount + 1)
			local gotA, gotB = {}, {}
			for _, m in M:All(a) do
				gotA[m.line] = m
			end
			for _, m in M:All(b) do
				gotB[m.line] = m
			end
			expect(gotA.mossbun.rarity).toBe(4)
			expect(gotA.mossbun.busy).toBe(false)
			expect(gotB.cindlet.muts).toEqual({ "soaked" })
			expect(eggs.Get(nil, a, egg)).toBeNil()
			expect(eggs.Count(nil, b)).toBe(1)

			local ev = h:LastEvent(b, "Trade.Completed")
			expect(#ev.payload.received).toBe(2)
			expect(ev.payload.received[2].egg).toBe("grove")
			expect(h:LastEvent(a, "Trade.Completed").payload.received[1].appearance.line).toBe("mossbun")
			expect(completed[a].partner).toBe(b.UserId)
			expect(completed[b].partner).toBe(a.UserId)
			expect(session(h, a).status).toBe("none")
			expect(session(h, b).status).toBe("none")

			local log = h:Section(a, "Trade").log
			expect(#log).toBe(1)
			expect(log[1].partner).toBe(b.UserId)
			expect(#log[1].gave).toBe(2)
			expect(log[1].got[1].line).toBe("mossbun")
			expect(h:Client(a).profile.Trade.log).toBeNil() -- private
		end)

		it("resets both sides and stops the countdown when an offer changes", function()
			local h, a, b, M = boot()
			local ma, extra = monster(M, a), monster(M, a)
			local mb = monster(M, b)
			open(h, a, b)
			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = ma.id } } })
			h:Call(b, "Trade.SetOffer", { items = { { kind = "monster", id = mb.id } } })
			readyUp(h, a, b)
			expect(session(h, a).status).toBe("countdown")
			h:Advance(2)
			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = extra.id } } })
			expect(ma.busy).toBe(false)
			expect(extra.busy).toBe("trade")
			local view = session(h, b)
			expect(view.status).toBe("open")
			expect(view.mine.ready).toBe(false)
			expect(view.theirs.ready).toBe(false)
			expect(view.theirs.confirmed).toBe(false)
			h:Advance(Rules.countdownSeconds + 1)
			expect(M:Get(a, extra.id)).toBeTruthy() -- nothing happened

			-- un-readying during the countdown stops it too
			readyUp(h, a, b)
			h:Advance(1)
			h:Call(b, "Trade.SetReady", { ready = false })
			expect(session(h, a).status).toBe("open")
			expect(session(h, a).mine.confirmed).toBe(false)
			h:Advance(Rules.countdownSeconds + 1)
			expect(M:Get(b, mb.id)).toBeTruthy()

			-- changing an offered monster (rename) also resets both sides
			h:Advance(2)
			readyUp(h, a, b)
			h:Call(a, "Monsters.Rename", { id = extra.id, name = "Mythic Dragon" })
			expect(session(h, b).status).toBe("open")
			expect(session(h, b).theirs.items[1].appearance.name).toBe("Mythic Dragon")
			h:Advance(Rules.countdownSeconds + 1)
			expect(M:Get(a, extra.id)).toBeTruthy()
		end)

		it("needs both sides ready and something on the table", function()
			local h, a, b = boot()
			open(h, a, b)
			expect(h:Reject(a, "Trade.Confirm")).toContain("Both players need to be Ready")
			h:Call(a, "Trade.SetReady", { ready = true })
			h:Call(b, "Trade.SetReady", { ready = true })
			expect(h:Reject(a, "Trade.Confirm")).toContain("Add something")
			expect(h:Reject(h:Join(), "Trade.SetOffer", { items = {} })).toContain("not in a trade")
		end)

		it("refuses busy, locked, missing, duplicate and incubating items", function()
			local h, a, b, M, eggs = boot()
			local locked = monster(M, a)
			locked.locked = true
			local away = monster(M, a)
			M:SetBusy(a, away.id, "expedition")
			local fine = monster(M, a)
			local theirs = monster(M, b)
			local warm = eggs.give(a, "meadow")
			eggs.incubating[warm] = true
			open(h, a, b)
			local function offer(items)
				h:Advance(1)
				return h:Reject(a, "Trade.SetOffer", { items = items })
			end
			expect(offer({ { kind = "monster", id = locked.id } })).toContain("locked")
			expect(offer({ { kind = "monster", id = away.id } })).toContain("busy")
			expect(offer({ { kind = "monster", id = theirs.id } })).toContain("doesn't exist")
			expect(offer({ { kind = "monster", id = fine.id }, { kind = "monster", id = fine.id } })).toContain("already in your offer")
			expect(offer({ { kind = "egg", id = "e999" } })).toContain("doesn't exist")
			expect(offer({ { kind = "egg", id = warm } })).toContain("incubator")
			expect(fine.busy).toBe(false)
			-- an item already in the offer stays valid when the offer is resent
			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = fine.id } } })
			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = fine.id } } })
			expect(fine.busy).toBe("trade")
			-- busy monsters can't be sold while offered
			expect(h:Reject(a, "Monsters.Sell", { ids = { fine.id } })).toContain("busy")
		end)

		it("stops at the countdown when a ranch has no room, keeping the offers", function()
			local h, a, b, M = boot()
			local m1, m2 = monster(M, a), monster(M, a)
			open(h, a, b)
			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = m1.id }, { kind = "monster", id = m2.id } } })
			setCapacity(M, b, M:Count(b) + 1)
			print("DEBUG", M:Count(b), M:Capacity(b), b.UserId)
			readyUp(h, a, b)
			h:Advance(Rules.countdownSeconds)
			expect(M:Get(a, m1.id)).toBeTruthy()
			expect(M:Get(a, m2.id)).toBeTruthy()
			expect(m1.busy).toBe("trade")
			local view = session(h, a)
			expect(view.status).toBe("open")
			expect(view.mine.ready).toBe(false)
			expect(#view.mine.items).toBe(2)
			expect(h:LastEvent(b, "Kernel.Notify").payload.text).toContain("Your ranch is full")
			expect(h:LastEvent(a, "Kernel.Notify").payload.text).toContain("Bob's ranch is full")

			-- with room the same offer goes through
			setCapacity(M, b, 100)
			h:Advance(1)
			readyUp(h, a, b)
			h:Advance(Rules.countdownSeconds)
			expect(M:Get(a, m1.id)).toBeNil()
		end)

		it("checks egg caps and eggs that disappear before the trade runs", function()
			local h, a, b, _M, eggs = boot()
			local egg = eggs.give(a, "grove")
			open(h, a, b)
			h:Call(a, "Trade.SetOffer", { items = { { kind = "egg", id = egg } } })
			eggs.countOverride[b.UserId] = Config.Economy.MaxEggs
			readyUp(h, a, b)
			h:Advance(Rules.countdownSeconds)
			expect(eggs.Get(nil, a, egg)).toBeTruthy()
			expect(h:LastEvent(b, "Kernel.Notify").payload.text).toContain("too many eggs")
			eggs.countOverride[b.UserId] = nil

			h:Advance(1)
			readyUp(h, a, b)
			eggs.Remove(nil, a, egg) -- e.g. placed in an incubator and hatched elsewhere
			h:Advance(Rules.countdownSeconds)
			expect(session(h, a).status).toBe("open")
			expect(h:LastEvent(a, "Kernel.Notify").payload.text).toContain("no longer available")
			expect(eggs.Count(nil, b)).toBe(0)
		end)

		it("cancels when either player cancels or leaves mid-countdown", function()
			local h, a, b, M = boot()
			local ma = monster(M, a)
			local mb = monster(M, b)
			open(h, a, b)
			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = ma.id } } })
			h:Call(a, "Trade.Cancel")
			expect(ma.busy).toBe(false)
			expect(session(h, b).status).toBe("none")
			expect(h:LastEvent(b, "Kernel.Notify").payload.text).toContain("Alice cancelled the trade")
			expect(h:Reject(a, "Trade.Cancel")).toContain("You're not trading")

			h:Advance(2)
			open(h, a, b)
			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = ma.id } } })
			h:Call(b, "Trade.SetOffer", { items = { { kind = "monster", id = mb.id } } })
			readyUp(h, a, b)
			h:Advance(2)
			h:Leave(b)
			expect(ma.busy).toBe(false)
			expect(session(h, a).status).toBe("none")
			expect(h:LastEvent(a, "Kernel.Notify").payload.text).toContain("Bob left")
			h:Advance(Rules.countdownSeconds + 1)
			expect(M:Get(a, ma.id)).toBeTruthy()
			-- Bob's monster was freed before his profile saved
			local b2 = h:Join(b.UserId, b.Name)
			expect(M:Get(b2, mb.id).busy).toBe(false)
		end)

		it("clears trade tags left behind by a crash on rejoin", function()
			local h, a, _b, M = boot()
			local m = monster(M, a)
			m.busy = "trade"
			local a2 = h:Rejoin(a, 60)
			expect(M:Get(a2, m.id).busy).toBe(false)
			expect(h:Client(a2).session.Trade.status).toBe("none")
		end)
	end)
end
