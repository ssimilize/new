--[[
	WeeklyClient (update 3.8): the Weekly tab of the Quests screen through the real client
	(ClientHarness): the week's goals and countdown, claiming a chest step with a real click,
	the HUD Quests badge counting claimable steps, the locked tab, and the tab in Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	local W = Config.Weekly

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

	-- Finishes the player's goal `index` through its bus topic.
	local function finish(h, p, index: number)
		local def = W.ById[h:Section(p, "Weekly").goals[index].id]
		local detail = table.clone(def.filter or {})
		if detail.minRarity then
			detail.rarity, detail.minRarity = detail.minRarity, nil
		end
		for _ = 1, def.target do
			h.kernel.Bus:Publish(def.topic, p, detail)
		end
		h:Step()
	end

	local function badgeCount(c): number
		local badge = c.kernel.UI.Hud:FindFirstChild("Quests", true):FindFirstChild("Badge", true)
		if not c:IsShown(badge) then
			return 0
		end
		return tonumber(c:Texts(badge)[1]) or 0
	end

	describe("Weekly tab", function()
		it("shows the week's goals, the countdown and the chest", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 5)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Quests")
			c:Advance(0.5)
			c:Click(c:Button("Weekly", screen))
			c:Advance(0.5)
			for _, entry in h:Section(p, "Weekly").goals do
				expect(c:HasText(W.ById[entry.id].text, screen)).toBe(true)
			end
			expect(screen:FindFirstChild("Goal5", true) ~= nil).toBe(true)
			expect(c:HasText("New weekly goals in", screen)).toBe(true)
			expect(c:HasText("0 / 5 goals done", screen)).toBe(true)
			for step = 1, #W.Chest do
				expect(screen:FindFirstChild("Step" .. step, true) ~= nil).toBe(true)
			end
			expectClean(c)
		end)

		it("claims a reached chest step with a real click and counts it on the HUD badge", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 5)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local before = badgeCount(c)
			finish(h, p, 1)
			h:Advance(1)
			c:Advance(1)
			local reached = badgeCount(c)
			expect(reached).toBeGreaterThan(before)

			local screen = c:Open("Quests", { tab = "weekly" })
			c:Advance(0.5)
			expect(c:HasText("1 / 5 goals done", screen)).toBe(true)
			local gems = h:Section(p, "Currency").gems
			c:Click(screen:FindFirstChild("Step1", true):FindFirstChild("Claim", true))
			c:Advance(1)
			expect(h:Section(p, "Currency").gems).toBe(gems + 15)
			expect(h:Section(p, "Weekly").claimed[1]).toBe(true)
			expect(c:HasText("Claimed ✓", screen:FindFirstChild("Step1", true))).toBe(true)
			expect(badgeCount(c)).toBe(reached - 1)

			-- An unreached step's button stays put and nothing is paid.
			c:Click(screen:FindFirstChild("Step2", true):FindFirstChild("Claim", true))
			c:Advance(1)
			expect(h:Section(p, "Weekly").claimed[2]).toBe(false)
			expect(h:Section(p, "Currency").gems).toBe(gems + 15)
			expectClean(c)
		end)

		it("shows the tab locked before Ranch Level 5", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Quests", { tab = "weekly" })
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 5", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the tab in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 5)
			finish(h, p, 1)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local screen = c:Open("Quests", { tab = "weekly" })
			c:Advance(0.5)
			expect(c:HasText("Semanal", screen)).toBe(true)
			expect(c:HasText("Nuevas metas semanales en", screen)).toBe(true)
			expect(c:HasText("Cofre semanal", screen)).toBe(true)
			expect(c:HasText("Metas: 1 / 1", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
