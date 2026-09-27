-- R2 Design Weeks (Systems/Workshop/DesignWeek.luau): a rotating theme, one entry per player
-- per week, cross-server votes, and a once-only rollover that Features the top N winners.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, MockAdapters, ClientHarness = t.TestKernel, t.MockAdapters, t.ClientHarness
	local Config = t.Shared("Config")
	local Boards = Config.Leaderboards
	local W = Config.Workshop

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "Accessories", "Shop", "Workshop" }
	local WEEK0 = Boards.WeekAnchor + 5000 -- well inside week 0, clear of the boundary

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	-- A leveled-up, funded player who can publish and enter Design Week.
	local function maker(h, userId: number, name: string)
		local p = h:Join(userId, name)
		levelTo(h, p, 12)
		h:System("Currency"):Add(p, "ribbons", 400, "test")
		return p
	end

	local function design(h, p, name: string, shape: string?)
		return h:Call(p, "Workshop.Create", {
			name = name,
			shape = shape or "tophat",
			color = W.Palette[5],
			color2 = W.Palette[3],
		}).design
	end

	describe("Design Week theme", function()
		it("rotates by week and repeats after a full cycle", function()
			local w0 = Boards.Week(WEEK0)
			local t0 = W.ThemeForWeek(w0)
			local t1 = W.ThemeForWeek(w0 + 1)
			expect(t0.id ~= t1.id).toBe(true)
			expect(W.ThemeForWeek(w0 + #W.Themes).id).toBe(t0.id)
		end)
	end)

	describe("Design Week entries", function()
		it("lets a player enter one of their own designs, once a week", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 })
			local m = maker(h, 9001, "Maker")
			local id = design(h, m, "Ghosty Hat")
			h:Advance(2)
			local id2 = design(h, m, "Second Hat", "cap")

			local res = h:Call(m, "Workshop.Enter", { design = id })
			expect(res.design).toBe(id)
			expect(h:Reject(m, "Workshop.Enter", { design = id2 })).toBe("You already entered this week's Design Week")

			local fan = maker(h, 9002, "Fan")
			expect(h:Reject(fan, "Workshop.Enter", { design = id })).toBe("That design isn't yours")
		end)
	end)

	describe("Design Week votes", function()
		it("enforces not-your-own and once-per-entry", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 })
			local m = maker(h, 9101, "Maker")
			local id = design(h, m, "Ghosty Hat")
			h:Call(m, "Workshop.Enter", { design = id })
			expect(h:Reject(m, "Workshop.Vote", { design = id })).toBe("You can't vote for your own design")

			local voter = h:Join(9102, "Voter")
			expect(h:Call(voter, "Workshop.Vote", { design = id }).votes).toBe(1)
			expect(h:Reject(voter, "Workshop.Vote", { design = id })).toBe("You already voted for that design")
		end)

		it("enforces a daily vote budget", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 })
			local voter = h:Join(9200, "Voter")
			local ids = {}
			for i = 1, W.VotesPerDay + 1 do
				local m = maker(h, 9200 + i, "Maker" .. i)
				local id = design(h, m, "Hat " .. i)
				h:Call(m, "Workshop.Enter", { design = id })
				table.insert(ids, id)
				h:Advance(1)
			end
			for i = 1, W.VotesPerDay do
				h:Call(voter, "Workshop.Vote", { design = ids[i] })
				h:Advance(1)
			end
			expect(h:Reject(voter, "Workshop.Vote", { design = ids[#ids] })).toBe("You've used today's votes. Come back tomorrow!")
		end)

		it("adds up votes cast on different servers", function()
			local net = MockAdapters.network()
			local s1 = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 })
			local s2 = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 })
			local m = maker(s1, 9301, "Maker")
			local id = design(s1, m, "Cross Server Hat")
			s1:Call(m, "Workshop.Enter", { design = id })

			local va = s1:Join(9302, "VoterA")
			local vb = s2:Join(9303, "VoterB")
			s1:Call(va, "Workshop.Vote", { design = id })
			s2:Call(vb, "Workshop.Vote", { design = id })
			expect(net.designs[id].weekEntry.votes).toBe(2)
		end)
	end)

	describe("Design Week rollover", function()
		it("features the top N once, even when the rollover runs twice", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 })
			local ids = {}
			for i = 1, W.Winners + 2 do
				local m = maker(h, 9400 + i, "Maker" .. i)
				local id = design(h, m, "Entry " .. i)
				h:Call(m, "Workshop.Enter", { design = id })
				table.insert(ids, id)
				h:Advance(1)
			end
			-- ids[1] gets the most votes, then fewer for each following entry.
			local voterId = 9600
			for i, id in ids do
				local n = #ids - i
				for _ = 1, n do
					voterId += 1
					local v = h:Join(voterId)
					h:Call(v, "Workshop.Vote", { design = id })
				end
			end

			local wk0 = Boards.Week(WEEK0)
			local h2 = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 + Boards.WeekSeconds })
			h2:System("Workshop"):CheckDesignWeek()

			local featured = 0
			for _, id in ids do
				if net.designs[id].featured == wk0 + 1 then
					featured += 1
				end
			end
			expect(featured).toBe(W.Winners)
			expect(net.designs[ids[1]].featured).toBe(wk0 + 1) -- the top-voted entry won

			local firstFinalizedAt = net.designWeekResults[wk0].finalizedAt
			h2:Advance(5)
			h2:System("Workshop"):CheckDesignWeek() -- a second run must not change anything
			expect(net.designWeekResults[wk0].finalizedAt).toBe(firstFinalizedAt)
		end)

		it("repairs winners left unfeatured by a server that stopped after the rollover write", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 })
			local m = maker(h, 9701, "Crashy")
			local id = design(h, m, "Half Done")
			h:Call(m, "Workshop.Enter", { design = id })
			local wk0 = Boards.Week(WEEK0)
			-- The rollover record landed, but no winner was flagged before the server went away.
			net.designWeekResults[wk0] = { week = wk0, theme = "x", winners = { id }, finalizedAt = WEEK0 + 1 }
			expect(net.designs[id].featured).toBeNil()

			local h2 = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 + Boards.WeekSeconds })
			h2:System("Workshop"):CheckDesignWeek()
			expect(net.designs[id].featured).toBe(wk0 + 1)
			expect(net.designWeekResults[wk0].finalizedAt).toBe(WEEK0 + 1) -- the record is untouched
		end)

		it("sells a Featured design in the Gallery next week and pays the designer's royalty", function()
			local net = MockAdapters.network()
			local h = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 })
			local m = maker(h, 9700, "Maker")
			local id = design(h, m, "Star Hat")
			h:Call(m, "Workshop.Enter", { design = id })
			local voter = h:Join(9701, "Voter")
			h:Call(voter, "Workshop.Vote", { design = id })

			local wk0 = Boards.Week(WEEK0)
			local h2 = TestKernel.new({ systems = SYSTEMS, network = net, startTime = WEEK0 + Boards.WeekSeconds })
			h2:System("Workshop"):CheckDesignWeek()
			expect(net.designs[id].featured).toBe(wk0 + 1)

			local buyer = maker(h2, 9702, "Buyer")
			local before = h2:Section(buyer, "Currency").ribbons
			expect(h2:Call(buyer, "Workshop.Buy", { design = id }).owned).toBe(1)
			expect(h2:Section(buyer, "Currency").ribbons).toBe(before - W.FeaturedPrice.ribbons)

			local makerHere = h2:Join(9700, "Maker") -- the designer, reached on this (other) server
			expect(h2:Call(makerHere, "Workshop.Claim").ribbons).toBe(W.Royalty)
		end)
	end)

	describe("Design Week client", function()
		it("shows this week's theme, entries and a Vote button", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = WEEK0 })
			local m = maker(h, 9800, "Maker")
			local id = design(h, m, "Client Hat")
			h:Call(m, "Workshop.Enter", { design = id })

			local voter = maker(h, 9801, "Voter")
			local c = ClientHarness.new(h, voter)
			c:Advance(1)
			local screen = c:Open("Workshop")
			c:Advance(0.5)
			c:Click(c:Button("Design Week", screen))
			c:Advance(0.5)
			expect(c:HasText("Client Hat", screen)).toBe(true)
			local voteBtn = screen:FindFirstChild("Entry_" .. id, true):FindFirstChild("Vote", true)
			expect(voteBtn ~= nil).toBe(true)
			c:Click(voteBtn)
			c:Advance(0.5)
			expect(#c:Problems()).toBe(0)
		end)
	end)
end
