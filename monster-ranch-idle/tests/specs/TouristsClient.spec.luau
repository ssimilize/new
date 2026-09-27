--[[
	TouristsClient (update 3.10 · Ranch Tourists) through the real client (ClientHarness): the
	Guestbook opened from the Decorate header and from the stand by the gate, its stars, category
	bars, tip and reviews, a tourist walking onto the plot and leaving, and the locked Guestbook.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Tourists")

	local Rules = Config.Tourists

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	-- Runs server and client to just past this player's next tourist (1 s frames). The server pays
	-- visits on a 5 s tick, so the visit can land up to 5 s after NextAt; +6 covers every user id's
	-- phase and stays well inside the 16 s walk.
	local function nextVisit(c, h, p)
		local now = h.adapters.Clock.Now()
		c:Advance(Logic.NextAt(p.UserId, now) - now + 6, 1)
	end

	local function ownPlot(c, p): number?
		for i, plot in c:Store("global.Plots") or {} do
			if type(plot) == "table" and plot.userId == p.UserId then
				return i
			end
		end
		return nil
	end

	local function boot(level: number)
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		levelTo(h, p, level)
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		return h, p, c
	end

	describe("Guestbook", function()
		it("opens from the Decorate header and shows the stars, the bars, the tip and the reviews", function()
			local h, p, c = boot(11)
			nextVisit(c, h, p)
			nextVisit(c, h, p)
			expect(#h:Section(p, "Tourists").book).toBeGreaterThan(0)

			local decorate = c:Open("Decorate")
			c:Advance(0.5)
			c:Click(decorate:FindFirstChild("Guestbook", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Guestbook")
			local screen = c:Screen("Guestbook")
			local sess = h:Session(p, "Tourists")
			expect(c:HasText(Logic.StarText(sess.stars), screen)).toBe(true)
			expect(c:HasText(string.format("Appeal %d/100", sess.score), screen)).toBe(true)
			expect(c:HasText(sess.tip, screen)).toBe(true)
			for _, cat in Rules.Categories do
				expect(screen:FindFirstChild("Part_" .. cat.id, true) ~= nil).toBe(true)
				expect(c:HasText(cat.name, screen)).toBe(true)
			end
			local review = screen:FindFirstChild("Review1", true)
			expect(review ~= nil).toBe(true)
			local r = h:Section(p, "Tourists").book[1]
			-- A bare Level 11 ranch: nothing is worth praising yet, so the card shows only the gripe.
			expect(r.good).toBe(false)
			expect(review:FindFirstChild("Praise", true)).toBe(nil)
			expect(c:HasText(Rules.Gripes[r.bad][r.bi].text, review)).toBe(true)
			expect(c:HasText(Rules.Visitors[r.who], review)).toBe(true)
			expect(c:HasText("Next tourist in", screen)).toBe(true)
			expectClean(c)
		end)

		it("walks a tourist onto the plot, then away, and opens from the stand by the gate", function()
			local h, p, c = boot(11)
			local index = ownPlot(c, p)
			expect(index ~= nil).toBe(true)
			local tourists = c.kernel:GetController("Tourists")
			expect(tourists.Stats().stands).toBeGreaterThan(0)
			expect(tourists.Walker(index)).toBe(nil)

			nextVisit(c, h, p)
			local walker = tourists.Walker(index)
			expect(walker ~= nil).toBe(true)
			expect(walker.Name).toBe("Tourist")
			expect(walker:IsDescendantOf(c.world.workspace)).toBe(true)
			c:Advance(20, 0.5)
			expect(tourists.Walker(index)).toBe(nil)
			expect(walker.Parent).toBe(nil)

			local folder = c.world.workspace:FindFirstChild("Tourists"):FindFirstChild("Plot" .. index)
			local prompt = folder:FindFirstChild("GuestbookPrompt", true)
			expect(prompt ~= nil).toBe(true)
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Guestbook")
			expectClean(c)
		end)

		it("shows the Guestbook locked before Ranch Level 11", function()
			local h, p, c = boot(1)
			local screen = c:Open("Guestbook")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 11", screen)).toBe(true)
			expect(c:HasText("No reviews yet. A tourist visits every 10 minutes.", screen)).toBe(true)
			nextVisit(c, h, p)
			expect(h:Section(p, "Tourists").count).toBe(0)
			expectClean(c)
		end)
	end)
end
