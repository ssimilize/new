--[[
	GeneticsClient (update 3.6): stat genes through the real client (ClientHarness): the
	grades and gene line on Monster Detail, the parents' grades and the baby's gene range in
	the Breeding Barn, a gene surge when the baby is claimed, and the Genes sort.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local BreedingLogic = t.Shared("Logic.Breeding")
	local Rng = t.Shared("Logic.Rng")

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
		return { hp = { a, b }, atk = { a, b }, def = { a, b }, spd = { a, b } }
	end

	local function gradeTexts(c, root)
		local list = {}
		for _, d in c:Descendants(root) do
			if d.Name == "Grade" and c:IsShown(d) then
				table.insert(list, d:FindFirstChildOfClass("TextLabel").Text)
			end
		end
		table.sort(list)
		return list
	end

	local function labelWith(c, root, prefix: string)
		for _, d in c:Descendants(root) do
			if d:IsA("TextLabel") and string.sub(d.Text, 1, #prefix) == prefix then
				return d
			end
		end
		return nil
	end

	describe("Monster Detail", function()
		it("grades each gene stat, sums the genes and explains a pair when tapped", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local genes = { hp = { 10, 10 }, atk = { 7, 8 }, def = { 0, 3 }, spd = { 5, 5 } }
			local m = h:System("Monsters"):Create(p, { line = "zappip", rarity = 3, stage = 3, genes = genes, gen = 4 }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)

			expect(c:HasText("Genes 48/80 · Gen 4", detail)).toBe(true)
			expect(gradeTexts(c, detail)).toEqual({ "A", "B", "D", "S" })
			-- Luck has no gene, so its row has no grade.
			local luck = detail:FindFirstChild("StatBar_Luck", true)
			expect(luck.Parent:FindFirstChild("Grade", true)).toBeNil()

			local hp = detail:FindFirstChild("StatBar_HP", true).Parent:FindFirstChild("Grade", true)
			c:Click(hp:FindFirstChild("Tap"))
			c:Advance(0.3)
			expect(c:HasText("HP genes: 10 + 10 = +20%")).toBe(true)

			local line = labelWith(c, detail, "Genes ")
			c:Click(line:FindFirstChild("Tap"))
			c:Advance(0.3)
			expect(c:HasText("Every gene point adds 1% to that stat")).toBe(true)

			-- The middle column still holds everything with the gene line added: its rows and
			-- the list's gaps add up to no more than the column's height (the mock does not lay
			-- out lists, so this sums the sizes the way UIListLayout would).
			local middle = line.Parent
			local layout = middle:FindFirstChildOfClass("UIListLayout")
			local used, rows = 0, 0
			for _, child in middle:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					used += child.Size.Y.Offset
					rows += 1
				end
			end
			used += layout.Padding.Offset * (rows - 1)
			expect(line.LayoutOrder).toBeGreaterThan(luck.Parent.LayoutOrder)
			expect(used).toBeAtMost(middle.Size.Y.Offset)
			expectClean(c)
		end)
	end)

	describe("In Spanish", function()
		it("translates the gene line, the grades and a pair's toast", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local genes = { hp = { 10, 10 }, atk = { 7, 8 }, def = { 0, 3 }, spd = { 5, 5 } }
			local m = h:System("Monsters"):Create(p, { line = "zappip", rarity = 3, stage = 3, genes = genes, gen = 4 }, "test", true)
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			expect(c:HasText("Genes 48/80 · Gen. 4", detail)).toBe(true)
			expect(gradeTexts(c, detail)).toEqual({ "A", "B", "D", "S" })
			local hp = detail:FindFirstChild("StatBar_HP", true).Parent:FindFirstChild("Grade", true)
			c:Click(hp:FindFirstChild("Tap"))
			c:Advance(0.3)
			expect(c:HasText("Genes de PV: 10 + 10 = +20%")).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Breeding Barn", function()
		it("shows both parents' grades, the baby's range and a gene surge on claim", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 12)
			h:System("Currency"):Add(p, "coins", 1e9, "test")
			local M = h:System("Monsters")
			local a = M:Create(p, { line = "cindlet", rarity = 2, stage = 3, genes = uniform(4, 6) }, "test", true)
			local b = M:Create(p, { line = "bubblin", rarity = 2, stage = 3, genes = uniform(2, 8) }, "test", true)
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			-- A seed whose baby has at least two surged genes.
			local surges = 0
			for seed = 1, 2000 do
				local spec = BreedingLogic.Roll(Rng.new(seed), a, b)
				if spec.surges >= 2 then
					h:Section(p, "Breeding").pods[1].seed = seed
					surges = spec.surges
					break
				end
			end
			expect(surges).toBeAtLeast(2)

			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Breeding")
			c:Advance(0.5)
			local rows = 0
			for _, d in c:Descendants(screen) do
				if d.Name == "GeneGrades" and c:IsShown(d) then
					rows += 1
				end
			end
			expect(rows).toBe(2)
			-- Parent A carries 4 and 6, parent B 2 and 8: the baby gets +6% .. +14% before surges.
			expect(c:HasText("+6–14%", screen)).toBe(true)
			local title = labelWith(c, screen:FindFirstChild("Genes", true), "Genes")
			c:Click(title:FindFirstChild("Tap"))
			c:Advance(0.3)
			expect(c:HasText("each gene has a 9% chance to surge higher")).toBe(true)

			h:Advance(Config.Breeding.Seconds[2])
			c:Advance(1)
			c:Click(c:Button("Claim", screen))
			c:Advance(1)
			expect(c:HasText(string.format("Gene surge! %d genes grew stronger", surges))).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Monsters list", function()
		it("sorts by gene points", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local M = h:System("Monsters")
			M:Create(p, { line = "cindlet", rarity = 5, stage = 3, genes = uniform(0, 1) }, "test", true)
			local best = M:Create(p, { line = "bubblin", rarity = 1, stage = 1, genes = uniform(9, 10) }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Monsters")
			c:Advance(0.5)
			local sort = c:Button("Sort:", screen)
			local cell = screen:FindFirstChild(best.id, true)
			expect(cell.LayoutOrder).toBeGreaterThan(1) -- the default sort puts rarity first
			for _ = 1, 6 do
				if c:HasText("Sort: Genes", screen) then
					break
				end
				c:Click(sort)
				c:Advance(0.3)
			end
			expect(c:HasText("Sort: Genes", screen)).toBe(true)
			expect(screen:FindFirstChild(best.id, true).LayoutOrder).toBe(1)
			expectClean(c)
		end)
	end)
end
