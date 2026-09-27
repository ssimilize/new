--[[
	ApiaryClient (update 3.12 · Honey & stars): the Apiary through the real client (ClientHarness):
	the beehives on the own plot and their "Tend" prompt, assigning a keeper from the barn with the
	Monsters picker, Collect all, selling honey, Unassign, the locked hives with their level, the
	Kitchen's honey recipes, and the screen in Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	local HOUR = 3600

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

	local function adult(h, p, fields)
		local spec = { line = "cindlet", rarity = 5, stage = 3, traits = { 7, 12 }, hidden = 9 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return h:System("Monsters"):Create(p, spec, "test", true)
	end

	local function openByPrompt(c)
		local apiary = c.kernel:GetController("Apiary")
		local model = apiary.Model()
		expect(model ~= nil).toBe(true)
		expect(model:IsDescendantOf(c.world.workspace)).toBe(true)
		local prompt = apiary.Prompt()
		expect(prompt.ActionText).toBe("Tend")
		c:Trigger(prompt)
		c:Advance(0.5)
		expect(c.kernel.Router:Current()).toBe("Apiary")
		return c:Screen("Apiary"), model
	end

	describe("Apiary", function()
		it("opens from the Tend prompt, assigns a keeper, collects and sells honey, and unassigns", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 14)
			local m = adult(h, p)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen, model = openByPrompt(c)
			expect(model:FindFirstChild("Hive1"):GetAttribute("Open")).toBe(true)
			-- The honey store sits inside the panel at its right edge (Studio: Util.card dropped
			-- the AnchorPoint and the store, with its Sell buttons, hung past the panel).
			local view, store = screen:FindFirstChild("View", true), screen:FindFirstChild("Store", true)
			local right = view.AbsolutePosition.X + view.AbsoluteSize.X
			expect(math.abs(store.AbsolutePosition.X + store.AbsoluteSize.X - right) < 1).toBe(true)
			expect(model:FindFirstChild("Hive1"):GetAttribute("Tended")).toBe(false)

			c:Click(screen:FindFirstChild("Hive1", true):FindFirstChild("Assign", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local picker = c:Screen("Monsters")
			local cell = picker:FindFirstChild(m.id, true)
			expect(cell ~= nil).toBe(true)
			c:Click(cell:FindFirstChild("Tap"))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Apiary")
			expect(h:Section(p, "Apiary").hives[1].monster).toBe(m.id)
			expect(c:HasText("honey an hour", screen)).toBe(true)
			c:Advance(2.5)
			model = c.kernel:GetController("Apiary").Model()
			expect(model:FindFirstChild("Hive1"):GetAttribute("Tended")).toBe(true)

			h:Advance(3 * HOUR)
			c:Advance(1.5)
			c:Click(screen:FindFirstChild("CollectAll", true))
			c:Advance(1)
			local store = h:Section(p, "Apiary").store
			local kind = next(store)
			expect(kind ~= nil).toBe(true)
			expect(store[kind] > 0).toBe(true)

			local coins = h:Section(p, "Currency").coins
			c:Click(screen:FindFirstChild("Sell_" .. kind, true))
			c:Advance(1)
			expect(h:Section(p, "Currency").coins > coins).toBe(true)
			expect(h:Section(p, "Apiary").store[kind] or 0).toBe(0)

			c:Click(screen:FindFirstChild("Hive1", true):FindFirstChild("Unassign", true))
			c:Advance(1)
			expect(h:Section(p, "Apiary").hives[1].monster).toBe(false)
			expect(c:HasText("Assign a keeper", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the locked hives with their level, and the whole apiary locked before Level 14", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen, model = openByPrompt(c)
			expect(c:HasText("Unlocks at Ranch Level 14", screen)).toBe(true)
			expect(model:FindFirstChild("Hive1"):GetAttribute("Open")).toBe(false)
			c:Close("Apiary")
			levelTo(h, p, 14)
			c:Advance(3)
			screen = c:Open("Apiary")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 27", screen)).toBe(true)
			expect(c:HasText("Unlocks at Ranch Level 42", screen)).toBe(true)
			model = c.kernel:GetController("Apiary").Model()
			expect(model:FindFirstChild("Hive1"):GetAttribute("Open")).toBe(true)
			expect(model:FindFirstChild("Hive2"):GetAttribute("Open")).toBe(false)
			expectClean(c)
		end)

		it("shows honey costs and counts on the Kitchen's honey recipes", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 14)
			h:System("Apiary"):AddHoney(p, "clover", 4)
			h:System("Currency"):Add(p, "food.sour", 10, "test")
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Kitchen")
			c:Advance(0.5)
			local card = screen:FindFirstChild("Recipe_clover_honey_tea", true)
			expect(card ~= nil).toBe(true)
			expect(c:HasText("You have 4 Clover Honey", card)).toBe(true)
			c:Click(card:FindFirstChild("Cook_clover_honey_tea", true))
			c:Advance(1)
			expect(h:Section(p, "Apiary").store.clover).toBe(1)
			expectClean(c)
		end)

		it("shows the apiary in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 14)
			h:System("Apiary"):AddHoney(p, "frost", 2)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local screen = openByPrompt(c)
			expect(c:HasText("Colmenar")).toBe(true)
			expect(c:HasText("Almacén de miel", screen)).toBe(true)
			expect(c:HasText("Asignar cuidador", screen)).toBe(true)
			expect(c:HasText("Miel de escarcha", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
