--[[
	Editions (glow-up W): numbered limited editions. The counter rules as units, then servers
	sharing one universe (MockAdapters.network()) with the Services.Editions adapter the kernel is
	asked to add (built here over network.editions, the way MockAdapters would): no duplicate
	numbers under concurrent hatches, the edition cap, a store that is down then late numbering,
	the profile-DataStore fallback, and numbers that survive a trade.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Cfg = Config.Editions
	local Logic = t.Shared("Logic.Editions")
	local Appearance = t.Shared("Logic.Appearance")

	local LINE = "lanternling" -- a Lunar Lanterns event line
	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Editions" }

	-- The adapter the lead adds to Kernel/Adapters + MockAdapters (see ARCHITECTURE.md).
	local function editionsAdapter(net)
		net.editions = net.editions or {}
		return {
			Claim = function(id: string, size: number)
				if net.editionsDown then
					return false, nil
				end
				local count, n = Logic.Claim(net.editions[id], size)
				if count then
					net.editions[id] = count
				end
				return true, n
			end,
		}
	end

	local function server(net)
		local h = TestKernel.new({ systems = SYSTEMS, network = net })
		h.adapters.Editions = editionsAdapter(net)
		return h
	end

	local function create(h, p, source, line)
		return h:System("Monsters"):Create(p, { line = line or LINE, rarity = 2, traits = { 3, 4 }, hidden = 5 }, source or "hatch", true)
	end

	-- Holds every Services.Spawn call so tasks from several servers can be run interleaved.
	local function deferSpawns(h, queue)
		h.adapters.Spawn = function(fn, ...)
			table.insert(queue, { fn = fn, args = table.pack(...) })
		end
	end

	local function withSize(size: number, fn)
		local edition = Cfg.ByLine[LINE]
		local before = edition.size
		edition.size = size
		local ok, err = pcall(fn)
		edition.size = before
		if not ok then
			error(err, 0)
		end
	end

	describe("Logic/Editions", function()
		it("claims the next number until the edition is full", function()
			expect(select(2, Logic.Claim(nil, 500))).toBe(1)
			local count, n = Logic.Claim(499, 500)
			expect(count).toBe(500)
			expect(n).toBe(500)
			count, n = Logic.Claim(500, 500)
			expect(count).toBeNil()
			expect(n).toBeNil()
			expect(select(2, Logic.Claim("junk", 3))).toBe(1)
		end)

		it("numbers event lines from hatches and grants only, and labels them", function()
			expect(Logic.For({ line = LINE }, "hatch")).toBe(Cfg.ByLine[LINE])
			expect(Logic.For({ line = LINE }, "reward")).toBe(Cfg.ByLine[LINE])
			expect(Logic.For({ line = LINE }, "breed")).toBeNil()
			expect(Logic.For({ line = LINE }, "trade")).toBeNil()
			expect(Logic.For({ line = "cindlet" }, "hatch")).toBeNil()
			expect(Logic.For({ line = LINE, ltd = LINE }, "hatch")).toBeNil()
			expect(Logic.Label({ ltd = LINE, ltdNo = 37, ltdOf = 500 })).toBe("#37/500")
			expect(Logic.Label({ ltd = LINE })).toBeNil()
			expect(Logic.Pending({ ltd = LINE })).toBe(true)
			expect(Logic.Pending({ ltd = LINE, ltdNo = 1 })).toBe(false)
		end)

		it("makes every limited line an event line that is earnable without Robux", function()
			expect(#Cfg.List > 0).toBe(true)
			for _, edition in Cfg.List do
				expect(Config.Species.ById[edition.line].event ~= nil).toBe(true)
				expect(edition.size > 0).toBe(true)
				local earnable = false
				for _, egg in Config.Eggs.List do
					for _, lineId in Config.Species.Pools[egg.pool] or {} do
						if lineId == edition.line and type(egg.price) == "table" and (egg.price.token or egg.price.coins) then
							earnable = true
						end
					end
				end
				if not earnable then
					error("limited line " .. edition.line .. " has no egg bought with tokens or coins")
				end
			end
		end)
	end)

	describe("Editions on one server", function()
		it("numbers hatched and granted event monsters, never bred or other lines", function()
			local net = MockAdapters.network()
			local h = server(net)
			local p = h:Join()
			local a = create(h, p, "hatch")
			local b = create(h, p, "hatch")
			expect(a.ltd).toBe(LINE)
			expect(a.ltdNo).toBe(1)
			expect(b.ltdNo).toBe(2)
			expect(a.ltdOf).toBe(Cfg.ByLine[LINE].size)
			h:System("Rewards"):Grant(p, { { kind = "monster", id = LINE, rarity = 2, amount = 1 } }, "test")
			local granted = 0
			for _, m in h:System("Monsters"):All(p) do
				if m.ltdNo == 3 then
					granted += 1
				end
			end
			expect(granted).toBe(1)
			expect(create(h, p, "breed").ltd).toBeNil()
			expect(create(h, p, "hatch", "cindlet").ltd).toBeNil()
			expect(net.editions[LINE]).toBe(3)
			h:Step()
			expect(h:Client(p).profile.Monsters.list[a.id].ltdNo).toBe(1)
			local ap = h:System("Monsters"):Appearance(p, a.id)
			expect(ap.ltdNo).toBe(1)
			expect(ap.ltdOf).toBe(Cfg.ByLine[LINE].size)
		end)

		it("stops numbering at the edition size and grants the rest as ordinary monsters", function()
			withSize(3, function()
				local net = MockAdapters.network()
				local h = server(net)
				local p = h:Join()
				local before = h:System("Monsters"):Count(p)
				local got = {}
				for i = 1, 5 do
					got[i] = create(h, p, "hatch")
				end
				expect(got[3].ltdNo).toBe(3)
				expect(got[3].ltdOf).toBe(3)
				for i = 4, 5 do
					expect(got[i].ltd).toBeNil()
					expect(got[i].ltdNo).toBeNil()
				end
				expect(h:System("Monsters"):Count(p)).toBe(before + 5) -- all five granted
				expect(net.editions[LINE]).toBe(3)
			end)
		end)

		it("keeps a monster pending while the store is down and numbers it later", function()
			local net = MockAdapters.network()
			local h = server(net)
			local p = h:Join()
			net.editionsDown = true
			local m = create(h, p, "hatch")
			expect(h:System("Monsters"):Get(p, m.id) ~= nil).toBe(true) -- granted, never lost
			expect(m.ltd).toBe(LINE)
			expect(m.ltdNo).toBeNil()
			expect(h:System("Editions"):Pending(p)).toBe(1)
			h:Advance(Cfg.RetrySeconds)
			expect(m.ltdNo).toBeNil()
			net.editionsDown = false
			h:Advance(Cfg.RetrySeconds)
			expect(m.ltdNo).toBe(1)
			expect(h:System("Editions"):Pending(p)).toBe(0)
			-- On rejoin too: down while hatching, back up by the next join.
			net.editionsDown = true
			local later = create(h, p, "hatch")
			expect(later.ltdNo).toBeNil()
			net.editionsDown = false
			local p2 = h:Rejoin(p)
			expect(h:System("Monsters"):Get(p2, later.id).ltdNo).toBe(2)
		end)

		it("falls back to the profile DataStore (with retries) when there is no Editions adapter", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			local a = create(h, p, "hatch")
			expect(a.ltdNo).toBe(1)
			expect(h.adapters.store["Edition_" .. LINE]).toBe(1)
			h.adapters.failNextUpdates = Cfg.Attempts - 1 -- fails twice, the third try lands
			expect(create(h, p, "hatch").ltdNo).toBe(2)
			h.adapters.failNextUpdates = Cfg.Attempts -- every try fails: pending
			local c = create(h, p, "hatch")
			expect(c.ltdNo).toBeNil()
			h:Advance(Cfg.RetrySeconds)
			expect(c.ltdNo).toBe(3)
		end)
	end)

	describe("Editions across servers", function()
		it("never hands out a number twice under concurrent hatches on three servers", function()
			local net = MockAdapters.network()
			local queue = {}
			local servers, players, made = {}, {}, {}
			for i = 1, 3 do
				servers[i] = server(net)
				players[i] = servers[i]:Join()
				deferSpawns(servers[i], queue)
			end
			-- Every server hatches before any claim runs, then the claims interleave.
			for _ = 1, 4 do
				for i = 1, 3 do
					local m = create(servers[i], players[i], "hatch")
					expect(m.ltd).toBe(LINE)
					expect(m.ltdNo).toBeNil()
					table.insert(made, m)
				end
			end
			while #queue > 0 do
				local job = table.remove(queue, 1)
				job.fn(table.unpack(job.args, 1, job.args.n))
			end
			local seen = {}
			for _, m in made do
				expect(type(m.ltdNo)).toBe("number")
				if seen[m.ltdNo] then
					error("duplicate edition number " .. tostring(m.ltdNo))
				end
				seen[m.ltdNo] = true
			end
			for n = 1, #made do
				expect(seen[n]).toBe(true)
			end
			expect(net.editions[LINE]).toBe(#made)
		end)

		it("keeps the number through a trade and never mints on arrival", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({
				systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Trade", "Editions" },
				network = net,
			})
			h.adapters.Editions = editionsAdapter(net)
			local a, b = h:Join(nil, "Alice"), h:Join(nil, "Bob")
			for _, p in { a, b } do
				local xp = 0
				for l = 1, 11 do
					xp += Config.Unlocks.XPToNext(l)
				end
				h:System("Progression"):AddXP(p, xp, "test")
				h.kernel.Data:Get(p)._meta.playSeconds = 3600
			end
			local m = create(h, a, "hatch")
			expect(m.ltdNo).toBe(1)
			h:Call(a, "Trade.Request", { target = b.UserId })
			h:Call(b, "Trade.Respond", { from = a.UserId, accept = true })
			h:Call(a, "Trade.SetOffer", { items = { { kind = "monster", id = m.id } } })
			local offered = h:Client(b).session.Trade.theirs.items[1].appearance
			expect(offered.ltdNo).toBe(1) -- the trade window shows "#1/500"
			expect(offered.ltdOf).toBe(Cfg.ByLine[LINE].size)
			h:Call(a, "Trade.SetReady", { ready = true })
			h:Call(b, "Trade.SetReady", { ready = true })
			h:Call(a, "Trade.Confirm")
			h:Call(b, "Trade.Confirm")
			h:Advance(Config.Social.Trade.countdownSeconds)
			local received = nil
			for _, r in h:System("Monsters"):All(b) do
				if r.line == LINE then
					received = r
				end
			end
			expect(received ~= nil).toBe(true)
			expect(received.ltd).toBe(LINE)
			expect(received.ltdNo).toBe(1)
			expect(received.ltdOf).toBe(Cfg.ByLine[LINE].size)
			expect(net.editions[LINE]).toBe(1) -- nothing minted on arrival
			expect(Appearance.Of(received).ltdNo).toBe(1) -- Market listings carry Appearance.Of
		end)
	end)
end
