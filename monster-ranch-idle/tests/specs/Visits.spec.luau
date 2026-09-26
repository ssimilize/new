-- Glow-up Y: likes that pay (gates, caps, once per pair per day), the crown over this server's
-- most-liked ranch, ranch snapshots (sanitising, size limit, save and load across servers,
-- teleport to a friend's server, likes mailed to the owner) and the Ranch of the Week board and
-- stage. Pure rules in Logic/Visits.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Visits")
	local Cfg = Config.Visits
	local L = Cfg.Likes

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function copy(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = copy(x)
		end
		return out
	end

	-- The Ranches adapter the lead adds to Adapters.Roblox, backed by the shared network table.
	local function installRanches(h, net)
		net.ranches = net.ranches or {}
		net.where = net.where or {}
		net.saves = net.saves or 0
		h.adapters.Ranches = {
			Save = function(userId, snap)
				net.saves += 1
				net.ranches[userId] = copy(snap)
				return true
			end,
			Load = function(userId)
				if net.ranchesDown then
					return false, nil
				end
				return true, copy(net.ranches[userId])
			end,
			Locate = function(userId)
				return true, copy(net.where[userId])
			end,
		}
	end

	local function server(net)
		net = net or MockAdapters.network()
		local h = TestKernel.new({ systems = allSystems(), network = net })
		installRanches(h, net)
		return h, net
	end

	local function veteran(h, userId, name)
		local p = h:Join(userId, name)
		h:System("Progression"):AddXP(p, 1e6, "test")
		h.kernel.Data:Get(p)._meta.playSeconds = Cfg.Gate.minPlaySeconds + 60
		p.AccountAge = 400
		return p
	end

	local function friendship(h, p)
		return h:System("Currency"):Balance(p, "friendship")
	end

	local function befriend(h, a, b)
		h.adapters.friends[a] = h.adapters.friends[a] or {}
		h.adapters.friends[a][b] = true
		h.adapters.friends[b] = h.adapters.friends[b] or {}
		h.adapters.friends[b][a] = true
	end

	local function like(h, liker, owner)
		h:Advance(2)
		return h:Call(liker, "Social.Like", { owner = owner.UserId })
	end

	local Appearance = t.Shared("Logic.Appearance")
	local function sampleAppearance(name)
		local a = Appearance.Preview("cindlet")
		a.name = name or "Blip"
		return a
	end

	describe("Logic/Visits", function()
		it("sanitises a loaded snapshot and rejects garbage", function()
			expect(Logic.Sanitize(Config, nil)).toBe(nil)
			expect(Logic.Sanitize(Config, { userId = "x" })).toBe(nil)
			expect(Logic.Sanitize(Config, { userId = -4 })).toBe(nil)
			local snap = Logic.Sanitize(Config, {
				userId = 77,
				name = string.rep("N", 200),
				level = 1e9,
				pens = {
					{ theme = "no_such_theme", capacity = "5", jarTier = 999, monsters = { sampleAppearance(), { line = "nope" }, 42 } },
					"not a pen",
				},
				garden = { tier = 2, plots = { { flavor = "sweet", readyAt = 10 }, { flavor = "poison" } } },
				best = { { hearts = 7, appearance = sampleAppearance("Pal") }, { hearts = 2 } },
				decor = { { id = "bench", x = 3, bad = function() end }, "junk" },
				extra = "dropped",
			})
			expect(snap ~= nil).toBe(true)
			expect(#snap.name).toBe(Cfg.Snapshot.maxName)
			expect(snap.level).toBe(1000)
			expect(#snap.pens).toBe(1)
			expect(snap.pens[1].theme).toBe(false)
			expect(snap.pens[1].capacity).toBe(5)
			expect(#snap.pens[1].monsters).toBe(1)
			expect(snap.garden.plots[2].flavor).toBe(false)
			expect(#snap.best).toBe(1)
			expect(#snap.decor).toBe(1)
			expect(snap.decor[1].bad).toBe(nil)
			expect(snap.extra).toBe(nil)
		end)

		it("trims a huge ranch to the size limit, monsters first", function()
			local pens = {}
			for p = 1, 10 do
				local monsters = {}
				for i = 1, 50 do
					monsters[i] = sampleAppearance(string.rep("M", 24) .. i)
				end
				pens[p] = { theme = false, capacity = 50, jarTier = 3, monsters = monsters }
			end
			local snap = Logic.Build(Config, { userId = 5, name = "Big", pens = pens }, {}, 100)
			expect(#snap.pens).toBe(Cfg.Snapshot.maxPens)
			expect(Logic.Size(snap) <= Cfg.Snapshot.maxBytes).toBe(true)
			for _, pen in snap.pens do
				expect(#pen.monsters <= Cfg.Snapshot.maxMonstersPerPen).toBe(true)
			end
			expect(Logic.Encode(snap)).toBe(Logic.Encode(Logic.Sanitize(Config, snap)))
		end)

		it("picks the crown leader with ties going to the earliest", function()
			expect(Logic.Leader({})).toBe(nil)
			expect(Logic.Leader({ { userId = 1, likes = 0, at = 1 } })).toBe(nil)
			expect(Logic.Leader({ { userId = 1, likes = 2, at = 50 }, { userId = 2, likes = 2, at = 40 } })).toBe(2)
			expect(Logic.Leader({ { userId = 1, likes = 3, at = 50 }, { userId = 2, likes = 2, at = 40 } })).toBe(1)
		end)
	end)

	describe("likes that pay", function()
		it("pays the liker and the owner once per pair per day", function()
			local h = server()
			local a, b = veteran(h, 7001, "Ana"), veteran(h, 7002, "Bo")
			local fa, fb = friendship(h, a), friendship(h, b)
			like(h, a, b)
			expect(friendship(h, a)).toBe(fa + L.likerReward[1].amount)
			expect(friendship(h, b)).toBe(fb + L.ownerReward[1].amount)
			expect(h:Section(b, "Visits").weekLikes).toBe(1)
			expect(h:System("Leaderboards"):Value(b, Cfg.BoardId)).toBe(1)
			-- Social refuses a second like today; the pair is paid either way.
			h:Advance(2)
			expect(h:Reject(a, "Social.Like", { owner = b.UserId })).toContain("already liked")
			expect(h:Reject(b, "Social.Like", { owner = b.UserId })).toContain("your own ranch")
			-- Tomorrow it pays again.
			h:Advance(86400)
			like(h, a, b)
			expect(friendship(h, a)).toBe(fa + 2 * L.likerReward[1].amount)
			expect(friendship(h, b)).toBe(fb + 2 * L.ownerReward[1].amount)
		end)

		it("gates new accounts: no reward, no crown, no weekly count", function()
			local h = server()
			local owner = veteran(h, 7011, "Owner")
			local alt = h:Join(7012, "Alt") -- Ranch Level 1, no play time
			local fresh = veteran(h, 7013, "Fresh")
			fresh.AccountAge = 1
			local before = friendship(h, owner)
			like(h, alt, owner)
			like(h, fresh, owner)
			expect(friendship(h, owner)).toBe(before)
			expect(friendship(h, alt)).toBe(0)
			expect(h:Section(owner, "Visits").weekLikes).toBe(0)
			expect(h:Section(owner, "Social").likes).toBe(2) -- the counter still counts
			expect(h:System("Visits"):Crown()).toBe(nil)
			local notes = {}
			for _, e in h:Events(alt, "Kernel.Notify") do
				table.insert(notes, e.payload.text)
			end
			expect(table.concat(notes, "|")).toContain("Ranch Level")
		end)

		it("caps paid likes per day for likers and owners", function()
			local h = server()
			local liker = veteran(h, 7020, "Liker")
			local owners = {}
			for i = 1, L.likerPaidPerDay + 1 do
				owners[i] = veteran(h, 7020 + i, "O" .. i)
			end
			local before = friendship(h, liker)
			for _, o in owners do
				like(h, liker, o)
			end
			expect(friendship(h, liker)).toBe(before + L.likerPaidPerDay * L.likerReward[1].amount)
			expect(h:Section(liker, "Visits").paidCount).toBe(L.likerPaidPerDay)
			-- The last owner still got paid: the owner cap is separate.
			expect(h:Section(owners[#owners], "Visits").got).toBe(1)
		end)
	end)

	describe("the crown", function()
		it("sits on the most-liked ranch here and moves live, ties by earliest", function()
			local h = server()
			local a, b = veteran(h, 7101, "A"), veteran(h, 7102, "B")
			local fans = {}
			for i = 1, 3 do
				fans[i] = veteran(h, 7110 + i, "Fan" .. i)
			end
			h:Advance(2)
			like(h, fans[1], a)
			local Visits = h:System("Visits")
			expect(Visits:Crown()).toBe(a.UserId)
			local crown = h:Client(a).global.Visits.crown
			expect(crown.plot).toBe(h:System("Plots"):GetPlot(a))
			like(h, fans[1], b) -- 1 : 1, A got there first
			expect(Visits:Crown()).toBe(a.UserId)
			like(h, fans[2], b) -- B leads
			expect(Visits:Crown()).toBe(b.UserId)
			local toasts = {}
			for _, e in h:Events(b, "Kernel.Notify") do
				table.insert(toasts, e.payload.text)
			end
			expect(table.concat(toasts, "|")).toContain("wears the crown")
			-- The holder leaves: the crown goes back to A.
			h:Leave(b)
			expect(Visits:Crown()).toBe(a.UserId)
			-- A new day clears it.
			h:Advance(86400)
			h:Advance(61)
			expect(Visits:Crown()).toBe(nil)
		end)
	end)

	describe("snapshots and visits", function()
		it("saves a snapshot on leave and shows it to a friend on another server", function()
			local net = MockAdapters.network()
			local s1 = server(net)
			local owner = veteran(s1, 7201, "Owner")
			s1:Advance(2)
			s1:Leave(owner)
			local saved = net.ranches[7201]
			expect(saved ~= nil).toBe(true)
			expect(saved.userId).toBe(7201)
			expect(#saved.pens > 0).toBe(true)
			expect(type(saved.decor)).toBe("table")
			expect(Logic.Size(saved) <= Cfg.Snapshot.maxBytes).toBe(true)

			local s2 = server(net)
			local visitor = veteran(s2, 7202, "Visitor")
			local stranger = veteran(s2, 7203, "Stranger")
			befriend(s2, 7201, 7202)
			expect(s2:Reject(stranger, "Visits.Visit", { userId = 7201 })).toContain("friends")
			expect(s2:Reject(visitor, "Visits.Visit", { userId = 7202 })).toContain("own ranch")
			s2:Advance(3)
			local res = s2:Call(visitor, "Visits.Visit", { userId = 7201 })
			expect(res.mode).toBe("showcase")
			local shown = s2:Client(visitor).session.Visits.showcase
			expect(shown.userId).toBe(7201)
			expect(shown.name).toBe("Owner")
			expect(s2:Client(stranger).session.Visits.showcase).toBe(false)

			-- Like it: the visitor is paid now, the owner by mail on their next join.
			local before = friendship(s2, visitor)
			local liked = s2:Call(visitor, "Visits.Like")
			expect(liked.paid).toBe(true)
			expect(friendship(s2, visitor)).toBe(before + L.likerReward[1].amount)
			s2:Advance(2)
			expect(s2:Reject(visitor, "Visits.Like")).toContain("already liked")
			s2:Advance(2)
			s2:Call(visitor, "Visits.Leave")
			expect(s2:Client(visitor).session.Visits.showcase).toBe(false)
			s2:Advance(2)
			expect(s2:Reject(visitor, "Visits.Like")).toContain("showcase first")

			local s3 = server(net)
			local back = s3:Join(7201, "Owner")
			expect(s3:Section(back, "Social").likes).toBe(1)
			expect(s3:Section(back, "Visits").weekLikes).toBe(1)
			expect(s3:Section(back, "Visits").got).toBe(1)
			-- Collected once.
			s3:System("Market"):Sync(back)
			expect(s3:Section(back, "Social").likes).toBe(1)
		end)

		it("saves on a slow timer only when the ranch changed", function()
			local h, net = server()
			veteran(h, 7301, "Timer")
			h:Advance(Cfg.Snapshot.saveSeconds + 1)
			expect(net.saves).toBe(1)
			h:Advance(Cfg.Snapshot.saveSeconds + 1)
			expect(net.saves).toBe(1)
		end)

		it("teleports to a friend on another server, or shows the snapshot when asked", function()
			local net = MockAdapters.network()
			local h = server(net)
			local visitor = veteran(h, 7402, "Vis")
			befriend(h, 7401, 7402)
			net.where[7401] = { placeId = 555, jobId = "other-job" }
			net.ranches[7401] = Logic.Build(
				Config,
				{ userId = 7401, name = "Far", pens = { { monsters = { sampleAppearance() } } } },
				{},
				1
			)
			local res = h:Call(visitor, "Visits.Visit", { userId = 7401 })
			expect(res.mode).toBe("teleport")
			expect(net.teleports[#net.teleports].jobId).toBe("other-job")
			h:Advance(3)
			res = h:Call(visitor, "Visits.Visit", { userId = 7401, snapshot = true })
			expect(res.mode).toBe("showcase")
			-- Offline with no snapshot, and a store outage.
			befriend(h, 7403, 7402)
			h:Advance(3)
			expect(h:Reject(visitor, "Visits.Visit", { userId = 7403 })).toContain("no snapshot")
			net.ranchesDown = true
			h:Advance(3)
			expect(h:Reject(visitor, "Visits.Visit", { userId = 7401, snapshot = true })).toContain("Try again")
		end)

		it("reports a friend who is on this server by plot", function()
			local h = server()
			local a, b = veteran(h, 7501, "A"), veteran(h, 7502, "B")
			local res = h:Call(a, "Visits.Visit", { userId = b.UserId })
			expect(res.mode).toBe("here")
			expect(res.plot).toBe(h:System("Plots"):GetPlot(b))
		end)

		it("is off without the Ranches adapter", function()
			local h = TestKernel.new({ systems = allSystems() })
			local a = veteran(h, 7601, "A")
			befriend(h, 7601, 7602)
			expect(h:Reject(a, "Visits.Visit", { userId = 7602 })).toContain("aren't available")
		end)
	end)

	describe("Ranch of the Week", function()
		it("puts last week's most-liked ranch on the hub stage", function()
			local h, net = server()
			local viewer = veteran(h, 7701, "Viewer")
			local lastWeek = Config.Leaderboards.Week(h.adapters.Clock.Now()) - 1
			local key = Config.Leaderboards.Key(Cfg.BoardId, lastWeek)
			h.adapters.boards[key] = { [7702] = 9, [7703] = 4 }
			local monsters = {}
			for i = 1, 8 do
				local a = sampleAppearance("W" .. i)
				a.rarity = if i == 3 then 5 else 1
				monsters[i] = a
			end
			net.ranches[7702] = Logic.Build(Config, { userId = 7702, name = "Winner", pens = { { monsters = monsters } } }, {}, 1)
			h:Advance(Cfg.Stage.refreshSeconds + 1)
			local stage = h:Client(viewer).global.Visits.stage
			expect(stage.userId).toBe(7702)
			expect(stage.name).toBe("Winner")
			expect(stage.likes).toBe(9)
			expect(stage.week).toBe(lastWeek)
			expect(#stage.monsters).toBe(Cfg.Stage.maxMonsters)
			expect(stage.monsters[1].rarity).toBe(5)
		end)
	end)
end
