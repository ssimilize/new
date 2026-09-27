--[[
	SpaClient (update 3.13 · Wild things): the Hot Springs through the real client (ClientHarness):
	the pools on the own plot and their "Soak" prompt, choosing a soak and a monster with the
	Monsters picker, the time left, Collect after the time and the buff it shows, the locked pool
	3 with its level, the whole spa locked before Level 29, and the screen in Spanish.
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

	local function adult(h, p)
		return h:System("Monsters"):Create(p, { line = "cindlet", rarity = 5, stage = 3, traits = { 7, 12 }, hidden = 9 }, "test", true)
	end

	local function stock(h, p)
		h:System("Apiary"):AddHoney(p, "clover", 10)
		h:System("Currency"):Add(p, "food.savory", 10, "test")
	end

	local function openByPrompt(c)
		local spa = c.kernel:GetController("Spa")
		local model = spa.Model()
		expect(model ~= nil).toBe(true)
		expect(model:IsDescendantOf(c.world.workspace)).toBe(true)
		local prompt = spa.Prompt()
		expect(prompt.ActionText).toBe("Soak")
		c:Trigger(prompt)
		c:Advance(0.5)
		expect(c.kernel.Router:Current()).toBe("Spa")
		return c:Screen("Spa"), model
	end

	describe("Spa", function()
		it("opens from the Soak prompt, soaks a monster, collects it after the time and shows its buff", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 29)
			stock(h, p)
			local m = adult(h, p)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen, model = openByPrompt(c)
			expect(model:FindFirstChild("Pool1"):GetAttribute("Open")).toBe(true)
			expect(model:FindFirstChild("Pool1"):GetAttribute("Soaking")).toBe(false)
			expect(c:HasText("2 honey (have 10) · 5 Hearty Roots (have 10)", screen)).toBe(true)
			-- The salts column sits inside the panel at its right edge.
			local view, side = screen:FindFirstChild("View", true), screen:FindFirstChild("Salts", true)
			expect(math.abs(side.AbsolutePosition.X + side.AbsoluteSize.X - (view.AbsolutePosition.X + view.AbsoluteSize.X)) < 1).toBe(true)

			c:Click(screen:FindFirstChild("Pool1", true):FindFirstChild("Soak_mineral", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local picker = c:Screen("Monsters")
			local cell = picker:FindFirstChild(m.id, true)
			expect(cell ~= nil).toBe(true)
			c:Click(cell:FindFirstChild("Tap"))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Spa")
			expect(h:Section(p, "Spa").pools[1].monster).toBe(m.id)
			expect(h:System("Monsters"):Get(p, m.id).busy).toBe("spa")
			expect(h:System("Apiary"):HoneyCount(p)).toBe(8)
			expect(c:HasText("Mineral Soak", screen:FindFirstChild("Pool1", true))).toBe(true)
			expect(string.sub(screen:FindFirstChild("TimeLeft", true).Text, 1, 8)).toBe("Done in ")
			c:Advance(2.5)
			model = c.kernel:GetController("Spa").Model()
			expect(model:FindFirstChild("Pool1"):GetAttribute("Soaking")).toBe(true)
			expect(model:FindFirstChild("Pool1"):FindFirstChild("Bubble") ~= nil).toBe(true)

			h:Advance(HOUR)
			c:Advance(1.5)
			expect(c:HasText("Done · collect it!", screen)).toBe(true)
			c:Click(screen:FindFirstChild("Pool1", true):FindFirstChild("Collect", true))
			c:Advance(1)
			expect(h:Section(p, "Spa").pools[1].monster).toBe(false)
			expect(h:System("Spa"):Buff(p, m.id).soak).toBe("mineral")
			local row = screen:FindFirstChild("Buff_" .. m.id, true)
			expect(row ~= nil).toBe(true)
			expect(string.find(row.Text, "Mineral Soak · ", 1, true) ~= nil).toBe(true)
			expectClean(c)
		end)

		it("shows the locked pool 3 with its level, and the whole spa locked before Level 29", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen, model = openByPrompt(c)
			expect(c:HasText("Unlocks at Ranch Level 29", screen)).toBe(true)
			expect(model:FindFirstChild("Pool1"):GetAttribute("Open")).toBe(false)
			c:Close("Spa")
			levelTo(h, p, 29)
			c:Advance(3)
			screen = c:Open("Spa")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 45", screen)).toBe(true)
			-- Without honey and food, the soak buttons wait.
			local button = screen:FindFirstChild("Pool1", true):FindFirstChild("Soak_warm", true)
			expect(button ~= nil).toBe(true)
			model = c.kernel:GetController("Spa").Model()
			expect(model:FindFirstChild("Pool2"):GetAttribute("Open")).toBe(true)
			expect(model:FindFirstChild("Pool3"):GetAttribute("Open")).toBe(false)
			expectClean(c)
		end)

		it("shows the spa in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 29)
			stock(h, p)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local screen = openByPrompt(c)
			expect(c:HasText("Sales de baño", screen)).toBe(true)
			expect(c:HasText("Mejoras activas", screen)).toBe(true)
			expect(c:HasText("Baño mineral", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
