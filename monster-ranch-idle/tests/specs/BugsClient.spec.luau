--[[
	BugsClient (update 3.13 · Wild things): the Bug Catching Meadow through the real client
	(ClientHarness): the meadow and its "Catch bugs" signpost prompt, the screen it opens, a swing
	tapped while the bug is inside the net catches it, the Bug Log tab in the Codex, the Insect Hall
	on the Exhibits screen, selling from the jar, the locked meadow before Level 17 and Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	local Cfg = Config.Bugs

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

	local function bugPrompt(c)
		for _, d in c.world.workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.ActionText == "Catch bugs" then
				return d
			end
		end
		return nil
	end

	-- Watches the bug and taps Swing once it is well inside the net.
	local function swingInNet(c, screen): boolean
		for _ = 1, 400 do
			local field = screen:FindFirstChild("Field", true)
			if not field then
				return false
			end
			local x = field:GetAttribute("BugX") or 0
			local from, to = field:GetAttribute("NetFrom") or 0, field:GetAttribute("NetTo") or 0
			if x >= from + (to - from) * 0.3 and x <= to - (to - from) * 0.3 then
				c:Click(screen:FindFirstChild("Swing", true))
				c:Advance(0.3)
				return true
			end
			c:Advance(0.01, 0.01)
		end
		return false
	end

	describe("Bug Catching Meadow", function()
		it("opens from the meadow prompt, catches a bug with a well-timed Swing and logs it", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, Config.Unlocks.Features.bug_meadow)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local meadow = c.world.workspace:FindFirstChild("BugMeadow")
			expect(meadow ~= nil).toBe(true)
			expect(meadow:FindFirstChild("Flutterers") ~= nil).toBe(true)
			local area = Config.World.BugMeadow
			for _, d in meadow:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "Ground" and d.Parent == meadow then
					local dx, dz = d.Position.X - area.center[1], d.Position.Z - area.center[2]
					expect(math.sqrt(dx * dx + dz * dz) <= area.radius).toBe(true)
				end
			end
			local prompt = bugPrompt(c)
			expect(prompt ~= nil).toBe(true)
			expect(prompt:FindFirstAncestor("BugMeadow") ~= nil).toBe(true)
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Bugs")
			local screen = c:Screen("Bugs")
			expect(c:HasText(string.format("Free swings today: %d / %d", Cfg.FreeSwings, Cfg.FreeSwings), screen)).toBe(true)
			expect(c:HasText("Your jar is empty. Go catch some bugs!", screen)).toBe(true)

			c:Click(screen:FindFirstChild("StartSwing", true))
			c:Advance(0.05, 0.05)
			expect(screen:FindFirstChild("Field", true) ~= nil).toBe(true)
			expect(swingInNet(c, screen)).toBe(true)
			local s = h:Section(p, "Bugs")
			expect(s.total).toBe(1)
			local bugId = next(s.log)
			local def = Cfg.ById[bugId]
			expect(c:HasText(string.format("You caught a %s!", def.name), screen)).toBe(true)
			expect(c:HasText("New in your Bug Log!", screen)).toBe(true)

			-- A bug left to cross without a swing flies off.
			c:Click(screen:FindFirstChild("SwingAgain", true))
			c:Advance(6, 0.1)
			expect(c:HasText("It flew off!", screen)).toBe(true)
			expect(s.total).toBe(1)

			-- Back in the lobby the jar holds it; selling pays coins.
			c:Click(screen:FindFirstChild("BugsDone", true))
			c:Advance(0.5)
			local coins = h:Section(p, "Currency").coins
			c:Click(screen:FindFirstChild("Sell_" .. bugId, true))
			c:Advance(1)
			expect(h:Section(p, "Currency").coins).toBeGreaterThan(coins)
			expect(s.jar[bugId]).toBeNil()

			-- The Bug Log tab shows the catch.
			c:Click(screen:FindFirstChild("BugLog", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Codex")
			local codex = c:Screen("Codex")
			local card = codex:FindFirstChild("Bug_" .. bugId, true)
			expect(card ~= nil).toBe(true)
			expect(c:HasText(def.name, card)).toBe(true)
			expect(c:HasText(string.format("Bug Log · 1 / %d kinds caught", #Cfg.List), codex)).toBe(true)

			-- The Insect Hall has it on display (the bug was not used up).
			c:Close("Codex")
			screen = c:Open("Bugs")
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("InsectHall", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Exhibits")
			local exhibits = c:Screen("Exhibits")
			local tile = exhibits:FindFirstChild("Exhibit_" .. bugId, true)
			expect(tile ~= nil).toBe(true)
			expect(tile:GetAttribute("Filled")).toBe(true)
			expect(c:HasText("Catch it in the Bug Catching Meadow", exhibits)).toBe(true)
			expectClean(c)
		end)

		it("shows the meadow locked before Level 17", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Bugs")
			c:Advance(0.5)
			expect(c:HasText(string.format("Unlocks at Ranch Level %d", Config.Unlocks.Features.bug_meadow), screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the meadow in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, Config.Unlocks.Features.bug_meadow)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			c:Open("Bugs")
			c:Advance(0.5)
			expect(c:HasText("Pradera de insectos")).toBe(true)
			expect(c:HasText("Atrapar un insecto")).toBe(true)
			expectClean(c)
		end)
	end)
end
