-- S5 Clubs (update 1.2): club records (Record.luau), create / join / leave / roles across
-- servers sharing one club store, weekly goals, the club boss and sync.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Cfg = Config.Clubs

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Expeditions", "Clubs" }

	local function server(network, startTime)
		return TestKernel.new({ systems = SYSTEMS, network = network, startTime = startTime })
	end

	local function rancher(h, userId, name)
		local p = h:Join(userId, name)
		h:System("Progression"):AddXP(p, 1e6, "test")
		h:System("Currency"):Add(p, "coins", 1e6, "test")
		return p
	end

	local function create(h, p, spec)
		local s = spec or {}
		return h:Call(p, "Clubs.Create", {
			name = s.name or "Moonlit Ranchers",
			tag = s.tag or "moon",
			color = s.color or 2,
			emblem = s.emblem or "moon",
			open = if s.open == nil then true else s.open,
		}).id
	end

	local function club(h, p)
		return h:Client(p).session.Clubs.club
	end

	describe("Record", function()
		local Record = t.Server("Systems.Clubs.Record")
		local NOW = 1790000000

		it("draws the same three distinct goals for a week everywhere", function()
			local a, b = Record.weekGoals(12), Record.weekGoals(12)
			expect(a).toEqual(b)
			expect(#a).toBe(Cfg.GoalsPerWeek)
			expect(a[1] ~= a[2] and a[2] ~= a[3] and a[1] ~= a[3]).toBe(true)
		end)

		it("caps members, hands the club on and disbands when empty", function()
			local r = Record.new(
				"ABCDEF",
				{ name = "A", tag = "AA", color = 1, emblem = "star", open = true },
				{ userId = 1, name = "Owner" },
				NOW
			)
			for i = 2, Cfg.MaxMembers do
				expect(Record.join(r, { userId = i, name = "P" .. i }, NOW + i)).toBeTruthy()
			end
			expect(r.count).toBe(Cfg.MaxMembers)
			local _, why = Record.join(r, { userId = 999, name = "Late" }, NOW)
			expect(why).toBe("full")
			Record.setRole(r, 1, 5, "officer")
			Record.remove(r, 1)
			expect(r.ownerId).toBe(5)
			expect(Record.member(r, 5).role).toBe("owner")
			local solo = Record.new(
				"GHJKLM",
				{ name = "B", tag = "BB", color = 1, emblem = "star", open = false },
				{ userId = 7, name = "Solo" },
				NOW
			)
			local _, closed = Record.join(solo, { userId = 8, name = "X" }, NOW, true)
			expect(closed).toBe("closed")
			Record.remove(solo, 7)
			expect(solo.disbanded).toBe(true)
			expect(Record.alive(solo)).toBe(false)
		end)

		it("lets officers kick members and only the owner change roles", function()
			local r = Record.new(
				"ABCDEF",
				{ name = "A", tag = "AA", color = 1, emblem = "star", open = true },
				{ userId = 1, name = "O" },
				NOW
			)
			Record.join(r, { userId = 2, name = "Off" }, NOW)
			Record.join(r, { userId = 3, name = "Mem" }, NOW)
			Record.setRole(r, 1, 2, "officer")
			expect(Record.canKick(r, 2, 3)).toBe(true)
			expect(Record.canKick(r, 3, 2)).toBe(false)
			expect(Record.canKick(r, 2, 1)).toBe(false)
			expect(Record.canKick(r, 1, 2)).toBe(true)
			expect((Record.setRole(r, 2, 3, "officer"))).toBe(false)
			Record.setRole(r, 1, 3, "owner")
			expect(r.ownerId).toBe(3)
			expect(Record.member(r, 1).role).toBe("officer")
		end)

		it("adds contributions to this week's goals and resets them next week", function()
			local r = Record.new(
				"ABCDEF",
				{ name = "A", tag = "AA", color = 1, emblem = "star", open = true },
				{ userId = 1, name = "O" },
				NOW
			)
			local goal = Record.weekGoals(r.week)[1]
			Record.apply(r, { week = r.week, points = { u1 = 5 }, goals = { [goal] = 5, notagoal = 3 }, damage = { u1 = 1000 } }, NOW)
			expect(r.goals[goal]).toBe(5)
			expect(r.goals.notagoal).toBeNil()
			expect(r.members.u1.points).toBe(5)
			expect(r.boss.maxHp - r.boss.hp).toBe(1000)
			local nextWeek = Config.Leaderboards.WeekEndsAt(r.week) + 1
			Record.apply(r, { week = r.week, points = { u1 = 1 } }, nextWeek)
			expect(r.members.u1.points).toBe(0) -- last week's points were dropped
			expect(r.boss.hp).toBe(r.boss.maxHp)
		end)
	end)

	describe("Membership", function()
		it("creates a club for coins with a filtered name and shows it to its members", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 5001, "Ana")
			local id = create(h, p)
			expect(#id).toBe(Cfg.CodeLength)
			expect(h:System("Currency"):Balance(p, "coins")).toBe(1e6 - Cfg.CreateCost.coins)
			expect(network.clubs[id].tag).toBe("MOON")
			local v = club(h, p)
			expect(v.name).toBe("Moonlit Ranchers")
			expect(v.myRole).toBe("owner")
			expect(#v.goals).toBe(Cfg.GoalsPerWeek)
			expect(h:Client(p).global.Clubs.here.u5001.tag).toBe("MOON")
			expect(h:Reject(p, "Clubs.Create", { name = "Again", tag = "AG", color = 1, emblem = "star", open = true })).toContain("Leave")
		end)

		it("rejects bad names, tags and low levels", function()
			local h = server(MockAdapters.network())
			local p = rancher(h, 5002, "Ben")
			expect(h:Reject(p, "Clubs.Create", { name = "my badword club", tag = "OK", color = 1, emblem = "star", open = true })).toContain(
				"isn't allowed"
			)
			h:Advance(6)
			expect(h:Reject(p, "Clubs.Create", { name = "Fine Club", tag = "!!", color = 1, emblem = "star", open = true })).toContain(
				"tag"
			)
			h:Advance(6)
			expect(h:Reject(p, "Clubs.Create", { name = "x", tag = "OK", color = 1, emblem = "star", open = true })).toContain("3 to 20")
			local fresh = h:Join(5003, "Newbie")
			expect(h:Reject(fresh, "Clubs.Create", { name = "Fine Club", tag = "OK", color = 1, emblem = "star", open = true })).toContain(
				"Ranch Level"
			)
			expect(h:System("Currency"):Balance(p, "coins")).toBe(1e6)
		end)

		it("joins by code from another server and syncs members between servers", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local owner = rancher(a, 5010, "Owner")
			local id = create(a, owner, { open = false })
			local guest = rancher(b, 5011, "Guest")
			expect(b:Call(guest, "Clubs.Join", { code = string.lower(id) }).id).toBe(id)
			expect(club(b, guest).count).toBe(2)
			-- Server A hears about it over Messaging and re-reads the club.
			expect(club(a, owner).count).toBe(2)
			local names = {}
			for _, m in club(a, owner).members do
				names[m.name] = m.here
			end
			expect(names.Owner).toBe(true)
			expect(names.Guest).toBe(false)
			expect(b:Reject(guest, "Clubs.Join", { code = "ZZZZZZ" })).toContain("Leave")
		end)

		it("joins open clubs of players here, but not invite-only ones", function()
			local network = MockAdapters.network()
			local h = server(network)
			local owner = rancher(h, 5020, "Owner")
			create(h, owner, { open = false })
			local other = rancher(h, 5021, "Other")
			expect(h:Reject(other, "Clubs.JoinPlayer", { userId = 5020 })).toContain("invite only")
			h:Call(owner, "Clubs.Settings", { open = true })
			h:Advance(3)
			h:Call(other, "Clubs.JoinPlayer", { userId = 5020 })
			expect(club(h, other).count).toBe(2)
			expect(h:Reject(other, "Clubs.Settings", { open = false })).toContain("owner and officers")
		end)

		it("removes kicked members on their own server", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local owner = rancher(a, 5030, "Owner")
			local id = create(a, owner)
			local member = rancher(b, 5031, "Member")
			b:Call(member, "Clubs.Join", { code = id })
			a:Call(owner, "Clubs.Kick", { userId = 5031 })
			expect(b:Section(member, "Clubs").id).toBe(false)
			expect(club(b, member)).toBe(false)
			expect(club(a, owner).count).toBe(1)
		end)

		it("hands the club over when the owner leaves and disbands when the last member leaves", function()
			local network = MockAdapters.network()
			local h = server(network)
			local owner = rancher(h, 5040, "Owner")
			local id = create(h, owner)
			local second = rancher(h, 5041, "Second")
			h:Call(second, "Clubs.Join", { code = id })
			h:Call(owner, "Clubs.Leave")
			expect(network.clubs[id].ownerId).toBe(5041)
			expect(club(h, second).myRole).toBe("owner")
			h:Advance(3)
			h:Call(second, "Clubs.Leave")
			expect(network.clubs[id].disbanded).toBe(true)
			h:Advance(3)
			expect(h:Reject(owner, "Clubs.Join", { code = id })).toContain("No club")
		end)

		it("clears a stale club on join", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 5050, "Ana")
			local id = create(h, p)
			network.clubs[id] = nil
			p = h:Rejoin(p, 60)
			expect(h:Section(p, "Clubs").id).toBe(false)
		end)
	end)

	describe("Goals", function()
		it("adds progress from every server and pays each member once", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local owner = rancher(a, 5100, "Owner")
			local id = create(a, owner)
			local member = rancher(b, 5101, "Member")
			b:Call(member, "Clubs.Join", { code = id })
			local week = t.Server("Systems.Clubs.Record").week(a.adapters.Clock.Now())
			local goalId = t.Server("Systems.Clubs.Record").weekGoals(week)[1]
			local goal = Cfg.GoalById[goalId]
			local target = goal.perMember * Cfg.MinScaleMembers
			local function push(h, p, n)
				local detail = table.clone(goal.filter or {})
				if goal.amount then
					detail[goal.amount] = (goal.per or 1) * n
					h.kernel.Bus:Publish(goal.topic, p, detail)
				else
					for _ = 1, n do
						h.kernel.Bus:Publish(goal.topic, p, detail)
					end
				end
			end
			push(a, owner, math.ceil(target / 2))
			-- Unsent progress already shows for the owner.
			expect(club(a, owner).goals[1].progress).toBe(math.ceil(target / 2))
			expect(a:Reject(owner, "Clubs.ClaimGoal", { goal = goalId })).toContain("hasn't finished")
			push(b, member, target)
			a:Advance(Cfg.SyncSeconds)
			b:Advance(Cfg.SyncSeconds)
			expect(network.clubs[id].goals[goalId]).toBeAtLeast(target)
			a:Call(owner, "Clubs.Refresh")
			expect(club(a, owner).goals[1].done).toBe(true)
			local rewards = a:Call(owner, "Clubs.ClaimGoal", { goal = goalId }).rewards
			expect(#rewards).toBeGreaterThan(0)
			a:Advance(2)
			expect(a:Reject(owner, "Clubs.ClaimGoal", { goal = goalId })).toContain("already")
			b:Call(member, "Clubs.ClaimGoal", { goal = goalId })
		end)
	end)

	describe("Club boss", function()
		it("limits attacks per day, falls to damage from several servers and pays attackers", function()
			local network = MockAdapters.network()
			local a, b = server(network), server(network)
			local owner = rancher(a, 5200, "Owner")
			local id = create(a, owner)
			local member = rancher(b, 5201, "Member")
			local idle = rancher(b, 5202, "Idle")
			b:Call(member, "Clubs.Join", { code = id })
			b:Advance(3)
			b:Call(idle, "Clubs.Join", { code = id })
			local first = a:Call(owner, "Clubs.AttackBoss")
			expect(first.damage).toBeAtLeast(Cfg.Boss.minDamage)
			for _ = 2, Cfg.Boss.attacksPerDay do
				a:Advance(1.5)
				a:Call(owner, "Clubs.AttackBoss")
			end
			a:Advance(1.5)
			expect(a:Reject(owner, "Clubs.AttackBoss")).toContain("No attacks left")
			-- Knock it down: the member keeps attacking over several days.
			local days = 0
			while network.clubs[id].boss.hp > 0 and days < 60 do
				for _ = 1, Cfg.Boss.attacksPerDay do
					if b:Invoke(member, "Clubs.AttackBoss").ok then
						b:Advance(1.5)
					end
				end
				b:Advance(Cfg.SyncSeconds)
				a:Advance(Cfg.SyncSeconds)
				network.clubs[id].boss.hp = math.max(0, network.clubs[id].boss.hp - 20000) -- other members
				b:Advance(86400 / 2)
				days += 1
			end
			a:Call(owner, "Clubs.Refresh")
			b:Call(member, "Clubs.Refresh")
			expect(club(a, owner).boss.defeated).toBe(true)
			a:Call(owner, "Clubs.ClaimBoss")
			b:Call(member, "Clubs.ClaimBoss")
			expect(b:Reject(idle, "Clubs.ClaimBoss")).toContain("at least once")
		end)
	end)

	describe("Store outages", function()
		it("fails actions politely and keeps contributions until the store is back", function()
			local network = MockAdapters.network()
			local h = server(network)
			local p = rancher(h, 5300, "Ana")
			local id = create(h, p)
			network.clubsDown = true
			h:Call(p, "Clubs.AttackBoss")
			h:Advance(Cfg.SyncSeconds)
			expect(network.clubs[id].boss.hp).toBe(network.clubs[id].boss.maxHp)
			expect(h:Reject(p, "Clubs.Leave")).toContain("busy")
			network.clubsDown = false
			h:Advance(Cfg.SyncSeconds)
			expect(network.clubs[id].boss.hp).toBeLessThan(network.clubs[id].boss.maxHp)
		end)
	end)
end
