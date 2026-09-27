--[[
	FishingClient (update 3.10 · Ranch life): the Fishing Pond through the real client
	(ClientHarness): the "Go fishing" prompt on the plot's dock opens the screen, Cast, hold and release
	the Reel button to keep the zone on the fish until one is caught, the catch card, selling from
	the bucket, the Fish Log tab in the Codex, and the locked pond before Level 13.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local RobloxMock = require("../runtime/RobloxMock")

	local Cfg = Config.Fishing

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

	local function fishPrompt(c)
		for _, d in c.world.workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.ActionText == "Go fishing" then
				return d
			end
		end
		return nil
	end

	-- Plays one cast with real presses on Reel: hold while the zone is below the fish.
	local function play(c, screen)
		local held = false
		for _ = 1, math.ceil(Cfg.Duration / 0.1) + 20 do
			local bar = screen:FindFirstChild("Bar", true)
			if not bar then
				break
			end
			local reel = screen:FindFirstChild("Reel", true)
			local want = (bar:GetAttribute("ZoneY") or 0) < (bar:GetAttribute("FishY") or 0)
			if want ~= held then
				held = want
				RobloxMock.fire(reel, if want then "MouseButton1Down" else "MouseButton1Up")
				c:Settle()
			end
			c:Advance(0.1)
		end
		c:Advance(0.5)
	end

	describe("Fishing Pond", function()
		it("opens from the pond prompt, reels a fish in with the Reel button and logs it", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 13)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local prompt = fishPrompt(c)
			expect(prompt ~= nil).toBe(true)
			expect(prompt:FindFirstAncestor("FishingPond") ~= nil).toBe(true)
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Fishing")
			local screen = c:Screen("Fishing")
			expect(c:HasText(string.format("Free casts today: %d / %d · Bait: 0", Cfg.FreeCasts, Cfg.FreeCasts), screen)).toBe(true)
			expect(c:HasText("Your bucket is empty. Cast a line!", screen)).toBe(true)

			c:Click(screen:FindFirstChild("Cast", true))
			c:Advance(0.2)
			local caught = false
			for cast = 1, Cfg.FreeCasts do
				expect(screen:FindFirstChild("Bar", true) ~= nil).toBe(true)
				play(c, screen)
				local s = h:Section(p, "Fishing")
				if s.total > 0 then
					caught = true
					break
				end
				expect(c:HasText("It got away!", screen)).toBe(true)
				if cast < Cfg.FreeCasts then
					c:Click(screen:FindFirstChild("CastAgain", true))
					c:Advance(0.2)
				end
			end
			expect(caught).toBe(true)
			local s = h:Section(p, "Fishing")
			local fishId = next(s.fish)
			local def = Cfg.ById[fishId]
			expect(c:HasText(string.format("You caught a %s!", def.name), screen)).toBe(true)
			expect(c:HasText("New in your Fish Log!", screen)).toBe(true)

			-- Back in the lobby the bucket holds it; selling pays coins.
			c:Click(screen:FindFirstChild("FishDone", true))
			c:Advance(0.5)
			local coins = h:Section(p, "Currency").coins
			c:Click(screen:FindFirstChild("Sell_" .. fishId, true))
			c:Advance(1)
			expect(h:Section(p, "Currency").coins).toBeGreaterThan(coins)
			expect(s.fish[fishId]).toBeNil()

			-- The Fish Log tab shows the catch.
			c:Click(screen:FindFirstChild("FishLog", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Codex")
			local codex = c:Screen("Codex")
			local card = codex:FindFirstChild("Log_" .. fishId, true)
			expect(card ~= nil).toBe(true)
			expect(c:HasText(def.name, card)).toBe(true)
			expect(c:HasText(string.format("Fish Log · 1 / %d kinds caught", #Cfg.Fish), codex)).toBe(true)
			expectClean(c)
		end)

		it("shows the pond locked before Level 13 and the buddy's odds once picked", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Fishing")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 13", screen)).toBe(true)
			c:Close("Fishing")
			levelTo(h, p, 13)
			local adult = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 5, stage = 3 }, "test", true)
			c:Advance(1)
			screen = c:Open("Fishing")
			c:Advance(0.5)
			expect(c:HasText("No fishing buddy yet", screen)).toBe(true)
			c:Click(screen:FindFirstChild("ChooseBuddy", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local picker = c:Screen("Monsters")
			c:Click(picker:FindFirstChild(adult.id, true):FindFirstChild("Tap"))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Fishing")
			expect(h:Section(p, "Fishing").buddy).toBe(adult.id)
			expect(c:HasText("Change buddy", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the pond in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 13)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			c:Open("Fishing")
			c:Advance(0.5)
			expect(c:HasText("Estanque de pesca")).toBe(true)
			expectClean(c)
		end)
	end)
end
