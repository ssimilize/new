--[[
	VisitsClient (glow-up Y): through the real client (ClientHarness). Liking ranches puts the
	crown over the most-liked plot's gate and moves it when the leader changes; the Friends
	screen's "Visit ranch" opens an offline friend's snapshot in the Visiting Showcase, where the
	visitor likes it and leaves; last week's winner stands on the Ranch of the Week stage.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local MockAdapters = t.MockAdapters
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Visits")
	local Appearance = t.Shared("Logic.Appearance")
	local Cfg = Config.Visits

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

	local function veteran(h, userId, name)
		local p = h:Join(userId, name)
		h:System("Progression"):AddXP(p, 1e6, "test")
		h.kernel.Data:Get(p)._meta.playSeconds = Cfg.Gate.minPlaySeconds + 60
		h:Section(p, "Quests").tutorial.step = #Config.Quests.Tutorial + 1
		return p
	end

	local function boot()
		local net = MockAdapters.network()
		net.ranches = {}
		local h = TestKernel.new({ systems = allSystems(), network = net })
		h.adapters.Ranches = {
			Save = function(userId, snap)
				net.ranches[userId] = copy(snap)
				return true
			end,
			Load = function(userId)
				return true, copy(net.ranches[userId])
			end,
			Locate = function(_userId)
				return true, nil
			end,
		}
		local me = veteran(h, 8001, "Me")
		local c = ClientHarness.new(h, me)
		c:Advance(2)
		return h, net, me, c
	end

	local function visits(c)
		return c.kernel:GetController("Visits")
	end

	local function sample(name)
		local a = Appearance.Preview("cindlet")
		a.name = name
		return a
	end

	describe("VisitsClient", function()
		it("likes a ranch and sees the crown move to the new leader", function()
			local h, _, me, c = boot()
			local a, b = veteran(h, 8002, "Ana"), veteran(h, 8003, "Bo")
			local fans = { veteran(h, 8004, "F1"), veteran(h, 8005, "F2") }
			c:Advance(2)
			expect(visits(c).Stats().crownPlot).toBe(0)
			local ok = c:Request("Social.Like", { owner = a.UserId })
			expect(ok).toBe(true)
			c:Advance(1)
			local Plots = h:System("Plots")
			expect(visits(c).Stats().crownPlot).toBe(Plots:GetPlot(a))
			expect(c.world.game:GetService("Workspace"):FindFirstChild("RanchCrown") ~= nil).toBe(true)
			h:Call(fans[1], "Social.Like", { owner = b.UserId })
			c:Advance(2)
			h:Call(fans[2], "Social.Like", { owner = b.UserId })
			c:Advance(1)
			expect(visits(c).Stats().crownPlot).toBe(Plots:GetPlot(b))
			expect(me ~= nil).toBe(true)
			expectClean(c)
		end)

		it("opens a friend's snapshot in the showcase, likes it and leaves", function()
			local h, net, me, c = boot()
			h.adapters.friends[8001] = { [9001] = true }
			h.adapters.friends[9001] = { [8001] = true }
			net.ranches[9001] = Logic.Build(Config, {
				userId = 9001,
				name = "Pal",
				pens = {
					{ theme = false, capacity = 4, jarTier = 2, monsters = { sample("One"), sample("Two") } },
					{ monsters = { sample("Three") } },
				},
				garden = { tier = 1, plots = { { flavor = "sweet", readyAt = 0 } } },
			}, { { hearts = 4, appearance = sample("Buddy") } }, 1)

			c:Open("Friends", { tab = "gifts", friend = { userId = 9001, name = "Pal" } })
			c:Advance(0.5)
			c:Click(c:Button("Visit ranch"))
			c:Advance(1)
			local stats = visits(c).Stats()
			expect(stats.showcaseOwner).toBe(9001)
			expect(stats.showcaseMonsters).toBe(4) -- three in pens, one best friend at the gate
			expect(c.world.game:GetService("Workspace"):FindFirstChild("RanchShowcase") ~= nil).toBe(true)
			expect(c:HasText("Visiting Pal's ranch")).toBe(true)
			c:Close("Friends")
			c:Advance(0.5)

			c:Click(c:Button("Like"))
			c:Advance(1)
			expect(h:Section(me, "Visits").liked["u9001"]).toBe(true)
			c:Click(c:Button("Go there"))
			c:Advance(0.5)
			c:Click(c:Button("Leave"))
			c:Advance(1)
			expect(visits(c).Stats().showcaseOwner).toBe(0)
			expect(c.world.game:GetService("Workspace"):FindFirstChild("RanchShowcase")).toBe(nil)
			expectClean(c)
		end)

		it("shows last week's winner on the Ranch of the Week stage", function()
			local h, net, _, c = boot()
			local lastWeek = Config.Leaderboards.Week(h.adapters.Clock.Now()) - 1
			h.adapters.boards[Config.Leaderboards.Key(Cfg.BoardId, lastWeek)] = { [9101] = 12 }
			net.ranches[9101] = Logic.Build(Config, { userId = 9101, name = "Champ", pens = { { monsters = { sample("Star") } } } }, {}, 1)
			c:Advance(Cfg.Stage.refreshSeconds + 1, 1)
			expect(visits(c).Stats().stageName).toBe("Champ")
			expect(c.world.game:GetService("Workspace"):FindFirstChild("RanchOfTheWeek") ~= nil).toBe(true)
			expectClean(c)
		end)
	end)
end
