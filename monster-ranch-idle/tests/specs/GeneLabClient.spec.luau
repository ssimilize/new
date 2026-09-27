--[[
	GeneLabClient (update 3.10): the Gene Lab through the real client (ClientHarness, real clicks):
	opened from Monster Detail, a tune with its odds, cost and seeded result; opened from the
	Breeding Barn's header, an Adult picked, a gene locked through the confirm, and the planner's
	"Locked" marker with odds that count the lock.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Format = t.Shared("Logic.Format")
	local Genetics = t.Shared("Logic.Genetics")
	local Lab = t.Shared("Logic.GeneLab")

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

	local function uniform(a, b)
		local g = {}
		for _, stat in Config.Genetics.Stats do
			g[stat] = { a, b }
		end
		return g
	end

	local function adult(M, p, fields)
		local spec = { stage = 3, line = "cindlet", rarity = 2, variant = 0, genes = uniform(3, 5) }
		for k, v in fields or {} do
			spec[k] = v
		end
		return M:Create(p, spec, "test", true)
	end

	local function clickable(gui)
		if gui:IsA("GuiButton") then
			return gui
		end
		return gui:FindFirstChildWhichIsA("GuiButton", true)
	end

	-- The planner's display of a chance (Screens/Breeding chanceText).
	local function chanceText(p: number): string
		if p <= 0 then
			return "0%"
		elseif p >= 1 then
			return "100%"
		elseif p < 0.01 then
			return Format.percent(math.max(p, 0.001), 1)
		elseif p > 0.99 then
			return "99%"
		end
		return Format.percent(p)
	end

	local function lab()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		levelTo(h, p, Config.Unlocks.Features.gene_lab)
		h:System("Currency"):Add(p, "stardust", 5000, "test")
		h:System("Currency"):Add(p, "coins", 1e9, "test")
		return h, p, h:System("Monsters")
	end

	describe("Gene Lab", function()
		it("opens from Monster Detail, shows odds and cost, tunes and shows the seeded result", function()
			local h, p, M = lab()
			local m = adult(M, p)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			-- The family tree still opens from the genes line.
			local genesRow = detail:FindFirstChild("GenesRow", true)
			expect(genesRow ~= nil).toBe(true)
			c:Click(genesRow:FindFirstChildWhichIsA("TextLabel"):FindFirstChild("Tap"))
			c:Advance(0.3)
			expect(c:HasText("Family tree", detail)).toBe(true)

			c:Click(clickable(genesRow:FindFirstChild("GeneLab")))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("GeneLab")
			local screen = c:Screen("GeneLab")
			expect(c:HasText("Tunes left today: 5/5", screen)).toBe(true)
			local row = screen:FindFirstChild("Stat_hp", true)
			expect(row:FindFirstChild("Pair").Text).toBe("Genes 3 + 5")
			expect(row:FindFirstChild("Odds").Text).toBe("90% chance · 80 Stardust")
			expect(row:FindFirstChild("Locked").Visible).toBe(false)

			local expected = Lab.Roll(Lab.Seed(p.UserId, m.id, 0), 0.9)
			c:Click(clickable(row:FindFirstChild("Tune")))
			c:Advance(0.5)
			expect(h:Section(p, "Currency").stardust).toBe(5000 - 80)
			local result = screen:FindFirstChild("Result", true)
			if expected then
				expect(result.Text).toBe("Success! HP gene is now 4")
				expect(row:FindFirstChild("Pair").Text).toBe("Genes 4 + 5")
			else
				expect(result.Text).toBe("No luck this time. HP gene stays at 3")
			end
			expect(c:HasText("Tunes left today: 4/5", screen)).toBe(true)
			expectClean(c)
		end)

		it("opens from the Breeding Barn, locks a gene and marks it in the planner", function()
			local h, p, M = lab()
			h:System("HallOfFame"):AddStarShards(p, 5, "test")
			local a = adult(M, p, { genes = { hp = { 2, 9 }, atk = { 3, 3 }, def = { 3, 3 }, spd = { 3, 3 }, luck = { 3, 3 } } })
			local b = adult(M, p, { line = "bubblin", genes = uniform(4, 4) })
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local barn = c:Open("Breeding")
			c:Advance(0.5)
			c:Click(clickable(barn:FindFirstChild("GeneLab", true)))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("GeneLab")
			local screen = c:Screen("GeneLab")
			expect(c:HasText("Choose an Adult to tune its genes", screen)).toBe(true)

			c:Click(clickable(screen:FindFirstChild("Pick", true)))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			c:Click(c:Screen("Monsters"):FindFirstChild(a.id, true):FindFirstChild("Tap"))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("GeneLab")
			local row = screen:FindFirstChild("Stat_hp", true)
			expect(row:FindFirstChild("Pair").Text).toBe("Genes 2 + 9")

			c:Click(clickable(row:FindFirstChild("LockGene")))
			c:Advance(0.5)
			expect(c:HasText("Star Shards are not refunded", c.kernel.UI.Top)).toBe(true)
			local dialogButtons = c.kernel.UI.Top:FindFirstChild("Dialog"):FindFirstChild("Buttons", true)
			c:Click(c:Button("Lock", dialogButtons))
			c:Advance(0.5)
			expect(a.geneLock).toBe("hp")
			expect(row:FindFirstChild("Locked").Visible).toBe(true)
			expect(screen:FindFirstChild("Result", true).Text).toBe("HP locked for the next baby")
			expect(h:System("HallOfFame"):StarShards(p)).toBe(0)

			-- The planner counts the lock and marks the stat.
			c:Close("GeneLab")
			c:Request("Breeding.Start", { pod = 1, a = a.id, b = b.id })
			c:Advance(1)
			barn = c:Open("Breeding")
			c:Advance(0.5)
			local cell = barn:FindFirstChild("Plan_hp", true)
			expect(cell:FindFirstChild("Locked") ~= nil).toBe(true)
			expect(barn:FindFirstChild("Plan_atk", true):FindFirstChild("Locked")).toBeNil()
			local grade = Config.Breeding.PlanGrade
			local withLock = Genetics.AtLeast(Genetics.GradeOdds(a.genes, b.genes, "hp", "hp", nil), grade)
			expect(cell:FindFirstChild("Chance").Text).toBe(chanceText(withLock))
			expect(withLock > Genetics.AtLeast(Genetics.GradeOdds(a.genes, b.genes, "hp"), grade)).toBe(true)
			expectClean(c)
		end)
	end)
end
