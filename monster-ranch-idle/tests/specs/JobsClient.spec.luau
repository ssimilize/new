--[[
	JobsClient (update 3.7): the Job Board through the real client (ClientHarness): a worker
	picked from the barn best-first, its card, collecting, flavours, recall, the HUD badge, the
	locked slots, and the board in Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Formulas = t.Shared("Logic.Formulas")

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
		local spec = { line = "cindlet", rarity = 3, stage = 3, traits = { 7, 12 }, hidden = 9 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return h:System("Monsters"):Create(p, spec, "test", true)
	end

	-- Opens a slot's job, checks the picker's order, and picks `id`.
	local function assign(c, screen, slot: number, job: string, id: string)
		c:Click(screen:FindFirstChild("Slot" .. slot, true):FindFirstChild("Job_" .. job, true))
		c:Advance(0.5)
		expect(c.kernel.Router:Current()).toBe("Monsters")
		local picker = c:Screen("Monsters")
		local cell = picker:FindFirstChild(id, true)
		expect(cell ~= nil).toBe(true)
		c:Click(cell:FindFirstChild("Tap"))
		c:Advance(1)
		expect(c.kernel.Router:Current()).toBe("Jobs")
		return cell
	end

	describe("Job Board", function()
		it("picks the strongest barn worker first, shows its card and collects its coins", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 6)
			local weak = adult(h, p, { rarity = 1 })
			local strong = adult(h, p, { rarity = 5 })
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Jobs")
			c:Advance(0.5)

			c:Click(screen:FindFirstChild("Slot1", true):FindFirstChild("Job_miner", true))
			c:Advance(0.5)
			local picker = c:Screen("Monsters")
			-- Best ATK first, whatever the list's own sort says.
			expect(picker:FindFirstChild(strong.id, true).LayoutOrder).toBeLessThan(picker:FindFirstChild(weak.id, true).LayoutOrder)
			c:Click(picker:FindFirstChild(strong.id, true):FindFirstChild("Tap"))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Jobs")
			expect(h:Section(p, "Jobs").slots[1].job).toBe("miner")
			expect(c:HasText("coins an hour", screen)).toBe(true)
			expect(c:HasText(Formulas.DisplayName(strong), screen)).toBe(true)

			h:Advance(3 * HOUR)
			c:Advance(1.5)
			expect(c:HasText("Coins stored:", screen)).toBe(true)
			local coins = h:Section(p, "Currency").coins
			c:Click(screen:FindFirstChild("CollectAll", true))
			c:Advance(1)
			expect(h:Section(p, "Currency").coins).toBeGreaterThan(coins)

			c:Click(screen:FindFirstChild("Slot1", true):FindFirstChild("Recall", true))
			c:Advance(1)
			expect(h:Section(p, "Jobs").slots[1].job).toBe(false)
			expect(c:HasText("Pick a job", screen)).toBe(true)
			expectClean(c)
		end)

		it("lets a forager change flavour and shows the HUD badge when storage is full", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 6)
			local m = adult(h, p)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Jobs")
			c:Advance(0.5)
			assign(c, screen, 2, "forager", m.id)
			local first = h:Section(p, "Jobs").slots[2].flavor
			c:Click(screen:FindFirstChild("Slot2", true):FindFirstChild("Flavor", true))
			c:Advance(1)
			expect(h:Section(p, "Jobs").slots[2].flavor ~= first).toBe(true)

			c:Close("Jobs")
			h:Advance(Config.Jobs.MaxHours * HOUR + 60)
			c:Advance(12)
			local badge = c.kernel.UI.Hud:FindFirstChild("Jobs", true):FindFirstChild("Badge", true)
			expect(c:IsShown(badge)).toBe(true)
			expectClean(c)
		end)

		it("shows locked slots with their level and the whole board locked before Level 6", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Jobs")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 6", screen)).toBe(true)
			c:Close("Jobs")
			levelTo(h, p, 6)
			c:Advance(1)
			screen = c:Open("Jobs")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 20", screen)).toBe(true)
			expect(c:HasText("Unlocks at Ranch Level 50", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the board in Spanish", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 6)
			local m = adult(h, p)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local screen = c:Open("Jobs")
			c:Advance(0.5)
			assign(c, screen, 1, "scout", m.id)
			expect(c:HasText("Tablón de trabajos")).toBe(true)
			expect(c:HasText("Explorador", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
