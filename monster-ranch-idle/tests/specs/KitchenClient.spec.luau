--[[
	KitchenClient (update 3.10): Kitchen & Pantry through the real client (ClientHarness): the
	"Cook" prompt on the plot's Kitchen, cooking, a dish finishing on the clock, collecting it,
	serving it from the Pantry through the monster picker and from Monster Detail's feed popup,
	the locked screen, and the screen in Spanish.
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

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function food(h, p, amounts)
		for flavor, n in amounts do
			h:System("Currency"):Add(p, "food." .. flavor, n, "test")
		end
	end

	local function baby(h, p)
		return h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1, stage = 1, traits = {}, hidden = 0 }, "test", true)
	end

	-- The "Cook" prompt on the local player's own Kitchen door.
	local function cookPrompt(c)
		local workspace = c.world.game:GetService("Workspace")
		for _, d in workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.ObjectText == "Kitchen" then
				return d
			end
		end
		return nil
	end

	describe("Kitchen", function()
		it("opens from the Cook prompt, cooks, finishes on the clock and serves through the picker", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 9)
			food(h, p, { sweet = 5, savory = 3 })
			local m = baby(h, p)
			local c = ClientHarness.new(h, p)
			c:Advance(1)

			local prompt = cookPrompt(c)
			expect(prompt ~= nil).toBe(true)
			expect(prompt.ActionText).toBe("Cook")
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Kitchen")
			local screen = c:Screen("Kitchen")

			c:Click(screen:FindFirstChild("Cook_berry_pie", true))
			c:Advance(1)
			expect(h:Section(p, "Kitchen").slots[1].recipe).toBe("berry_pie")
			expect(c:HasText("Berry Pie", screen:FindFirstChild("Slot1", true))).toBe(true)
			-- Out of food: the same recipe can't be cooked twice.
			c:Click(screen:FindFirstChild("Cook_berry_pie", true))
			c:Advance(1)
			expect(h:Section(p, "Kitchen").slots[2].recipe).toBe(false)

			h:Advance(Config.Kitchen.ById.berry_pie.minutes * 60 + 1)
			c:Advance(1.5)
			expect(c:HasText("Ready!", screen)).toBe(true)
			c:Click(screen:FindFirstChild("Collect", true))
			c:Advance(1)
			expect(h:Section(p, "Kitchen").pantry.berry_pie).toBe(1)

			c:Click(c:Button("Pantry", screen))
			c:Advance(0.5)
			expect(c:HasText("×1", screen:FindFirstChild("Dish_berry_pie", true))).toBe(true)
			c:Click(screen:FindFirstChild("Serve_berry_pie", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local picker = c:Screen("Monsters")
			local cell = picker:FindFirstChild(m.id, true)
			expect(cell ~= nil).toBe(true)
			c:Click(cell:FindFirstChild("Tap"))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Kitchen")
			expect(h:System("Monsters"):Get(p, m.id).meals.sweet).toBe(Config.Kitchen.MealsPerDish)
			expect(h:Section(p, "Kitchen").pantry.berry_pie).toBe(nil)
			expectClean(c)
		end)

		it("collects dishes that finished while away when it opens, and serves from Monster Detail", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 9)
			food(h, p, { sour = 5, sweet = 3 })
			local m = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 3, stage = 3, traits = {}, hidden = 0 }, "test", true)
			h:Call(p, "Kitchen.Cook", { recipe = "lime_tart" })
			p = h:Rejoin(p, 3600)
			h:System("Monsters"):Get(p, m.id).mood = 5
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			c:Open("Kitchen")
			c:Advance(1)
			expect(h:Section(p, "Kitchen").pantry.lime_tart).toBe(1)
			c:Close("Kitchen")

			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			c:Click(c:Button("Feed", detail))
			c:Advance(0.5)
			c:Click(detail:FindFirstChild("Pantry", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Kitchen")
			local screen = c:Screen("Kitchen")
			expect(c:HasText("Pick a dish for", screen)).toBe(true)
			c:Click(screen:FindFirstChild("Serve_lime_tart", true))
			c:Advance(1)
			expect(h:System("Monsters"):Get(p, m.id).mood).toBe(Config.Economy.Mood.max)
			expectClean(c)
		end)

		it("shows the Kitchen locked before Level 9, the 3rd slot's level and fish recipes before the Pond opens", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Kitchen")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 9", screen)).toBe(true)
			c:Close("Kitchen")
			levelTo(h, p, 9)
			c:Advance(1)
			screen = c:Open("Kitchen")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 30", screen)).toBe(true)
			expect(screen:FindFirstChild("NeedsFish", true) ~= nil).toBe(true)
			expect(screen:FindFirstChild("Cook_sushi_roll", true)).toBe(nil)
			-- The Fishing Pond opens at Level 13: the fish recipes get their Cook button.
			c:Close("Kitchen")
			levelTo(h, p, Config.Unlocks.Features[Config.Fishing.Unlock])
			c:Advance(1)
			screen = c:Open("Kitchen")
			c:Advance(0.5)
			expect(screen:FindFirstChild("NeedsFish", true)).toBe(nil)
			expect(screen:FindFirstChild("Cook_sushi_roll", true) ~= nil).toBe(true)
			expectClean(c)
		end)

		it("shows the Kitchen in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 9)
			h:Section(p, "Kitchen").seeds = 1
			p = h:Rejoin(p) -- a fresh join sends the whole save to the client
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local screen = c:Open("Kitchen")
			c:Advance(0.5)
			expect(c:HasText("Cocina")).toBe(true)
			expect(c:HasText("Pastel de bayas", screen)).toBe(true)
			c:Click(c:Button("Despensa", screen))
			c:Advance(0.5)
			c:Click(screen:FindFirstChild("PlantGolden", true))
			c:Advance(1)
			expect(h:Section(p, "Ranch").garden.plots[1].flavor).toBe("golden")
			expectClean(c)
		end)
	end)
end
