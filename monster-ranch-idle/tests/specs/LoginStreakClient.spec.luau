--[[
	LoginStreakClient (glow-up): the daily streak calendar, its HUD badge and the once-a-day
	auto-open, driven through the real client (ClientHarness).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

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

	local function dailyBadge(c): boolean
		for _, gui in c:Descendants(c.kernel.UI.Hud) do
			if gui.Name == "Daily" then
				local badge = gui:FindFirstChild("Badge", true)
				return badge ~= nil and badge.Visible
			end
		end
		error("no Daily button on the HUD")
	end

	local function finishTutorial(h, p)
		h:Section(p, "Quests").tutorial.step = #Config.Quests.Tutorial + 1
	end

	describe("LoginStreak client", function()
		it("waits for the tutorial, shows the badge and claims through the screen", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(8)
			expect(c.kernel.Router:IsOpen("LoginStreak")).toBe(false)
			expect(dailyBadge(c)).toBe(true)
			local screen = c:Open("LoginStreak")
			c:Advance(1)
			expect(c:HasText("Day 7", screen)).toBe(true)
			expect(c:HasText("Today's reward", screen)).toBe(true)
			c:Click(c:Button("Claim", screen))
			c:Advance(1)
			expect(h:Section(p, "LoginStreak").total).toBe(1)
			expect(c:HasText("Come back tomorrow!", screen)).toBe(true)
			expect(c:HasText("Rewards · Daily streak", c.kernel.UI.Feedback)).toBe(true)
			expect(dailyBadge(c)).toBe(false)
			c:Close("LoginStreak")
			expectClean(c)
		end)

		it("opens by itself once a day for a player past the tutorial", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			finishTutorial(h, p)
			p = h:Rejoin(p, 60) -- the next session loads the finished tutorial
			local c = ClientHarness.new(h, p)
			c:Advance(8)
			expect(c.kernel.Router:IsOpen("LoginStreak")).toBe(true)
			c:Click(c:Button("Claim", c:Screen("LoginStreak")))
			c:Advance(1)
			c:Close("LoginStreak")
			expectClean(c)

			-- Same UTC day again: already claimed, so it stays closed.
			local p2 = h:Rejoin(p, 60)
			local c2 = ClientHarness.new(h, p2)
			c2:Advance(8)
			expect(c2.kernel.Router:IsOpen("LoginStreak")).toBe(false)
			expectClean(c2)
		end)
	end)
end
