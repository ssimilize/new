--[[
	PedigreeClient (update 3.9): the pedigree and the breeding planner through the real client
	(ClientHarness, real clicks): the family tree popup on Monster Detail, the planner's per-stat
	chances and grade spread in the Breeding Barn, the target chip and picker, the best-for-target
	parent sort, and Spanish.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Genetics = t.Shared("Logic.Genetics")
	local Pedigree = t.Shared("Logic.Pedigree")
	local Format = t.Shared("Logic.Format")

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
		local genes = {}
		for _, stat in Config.Genetics.Stats do
			genes[stat] = { a, b }
		end
		return genes
	end

	local function adult(M, p, fields)
		local spec = { stage = 3, line = "cindlet", rarity = 2, variant = 0 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return M:Create(p, spec, "test", true)
	end

	local function labelWith(c, root, prefix: string)
		for _, d in c:Descendants(root) do
			if d:IsA("TextLabel") and string.sub(d.Text, 1, #prefix) == prefix then
				return d
			end
		end
		return nil
	end

	local function clickable(gui)
		if gui:IsA("GuiButton") then
			return gui
		end
		return gui:FindFirstChildWhichIsA("GuiButton", true)
	end

	local function gradeLetters(c, node)
		local letters = {}
		for _, d in c:Descendants(node) do
			if d.Name == "Grade" then
				table.insert(letters, d:FindFirstChildOfClass("TextLabel").Text)
			end
		end
		return table.concat(letters)
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

	-- A family: two grandparents behind parent A, a hatched parent B, and the baby.
	local function family(h, p)
		local M = h:System("Monsters")
		local g1 = adult(M, p, { line = "mossbun", rarity = 4, genes = uniform(9, 9) })
		g1.name = "Granny"
		local g2 = adult(M, p, { line = "zappip", genes = uniform(0, 1) })
		local a = adult(M, p, { gen = 1, genes = uniform(7, 7), ped = Pedigree.Build(g1, g2) })
		a.name = "Mama"
		local b = adult(M, p, { line = "bubblin", genes = uniform(5, 5) })
		local baby = M:Create(p, { line = "cindlet", rarity = 2, gen = 2, genes = uniform(6, 6), ped = Pedigree.Build(a, b) }, "test", true)
		return baby, a, b, g1, g2
	end

	local function openTree(c, id)
		local detail = c:Open("MonsterDetail", { id = id })
		c:Advance(0.5)
		c:Click(labelWith(c, detail, "Genes "):FindFirstChild("Tap"))
		c:Advance(0.5)
		return detail, detail:FindFirstChild("FamilyTree", true)
	end

	describe("Family tree", function()
		it("opens from the gene line and shows parents, grandparents and missing ancestors", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local baby, _, b, _, g2 = family(h, p)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local detail, tree = openTree(c, baby.id)
			expect(tree ~= nil).toBe(true)
			expect(c:IsShown(tree)).toBe(true)
			expect(c:HasText("Family tree", detail)).toBe(true)
			expect(c:HasText("Every gene point adds 1% to that stat", detail)).toBe(true)
			expect(c:HasText("Grades: HP · ATK · DEF · SPD · Luck", tree)).toBe(true)

			local function node(slot)
				return tree:FindFirstChild("Node_" .. slot)
			end
			expect(node("self"):FindFirstChild("Name").Text).toBe(Pedigree.Name(Pedigree.Snap(baby)))
			expect(gradeLetters(c, node("self"))).toBe("BBBBB")
			expect(node("a"):FindFirstChild("Name").Text).toBe("Mama")
			expect(gradeLetters(c, node("a"))).toBe("AAAAA")
			expect(node("b"):FindFirstChild("Name").Text).toBe(Pedigree.Name(Pedigree.Snap(b)))
			expect(node("aa"):FindFirstChild("Name").Text).toBe("Granny")
			expect(gradeLetters(c, node("aa"))).toBe("SSSSS")
			expect(node("ab"):FindFirstChild("Name").Text).toBe(Pedigree.Name(Pedigree.Snap(g2)))
			expect(gradeLetters(c, node("ab"))).toBe("DDDDD")
			-- Parent B was hatched, so it has no parents to show.
			expect(c:HasText("Hatched", node("ba"))).toBe(true)
			expect(c:HasText("Hatched", node("bb"))).toBe(true)
			-- The rarity colours the border: Granny is Epic, Grandpa Uncommon.
			expect(node("aa"):FindFirstChildOfClass("UIStroke").Color ~= node("ab"):FindFirstChildOfClass("UIStroke").Color).toBe(true)
			expectClean(c)
		end)

		it("reads Unknown for a monster bred before pedigrees and Hatched for a hatched one", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local M = h:System("Monsters")
			local old = M:Create(p, { line = "zappip", rarity = 1, stage = 3, gen = 3 }, "test", true)
			local hatched = M:Create(p, { line = "zappip", rarity = 1, stage = 1 }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local _, tree = openTree(c, old.id)
			expect(c:HasText("Unknown", tree:FindFirstChild("Node_a"))).toBe(true)
			expect(c:HasText("Unknown", tree:FindFirstChild("Node_bb"))).toBe(true)
			c:Close("MonsterDetail")
			c:Advance(0.5)
			local _, tree2 = openTree(c, hatched.id)
			expect(c:HasText("Hatched", tree2:FindFirstChild("Node_b"))).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Breeding planner", function()
		local function barn()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 12)
			h:System("Currency"):Add(p, "coins", 1e9, "test")
			return h, p, h:System("Monsters")
		end

		it("shows each stat's chance of B or better, the spread on tap and the surge note", function()
			local h, p, M = barn()
			local a = adult(M, p, { genes = uniform(4, 6) })
			local b = adult(M, p, { line = "bubblin", genes = uniform(2, 8) })
			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Breeding")
			c:Advance(0.5)
			expect(c:HasText("Stats show the chance of B or better", screen)).toBe(true)
			expect(c:HasText("+6–14%", screen)).toBe(false) -- the old range is gone
			local odds = Genetics.GradeOdds(a.genes, b.genes, "hp")
			local cell = screen:FindFirstChild("Plan_hp", true)
			expect(cell:FindFirstChild("Chance").Text).toBe(chanceText(Genetics.AtLeast(odds, "B")))
			c:Click(cell:FindFirstChild("Tap"))
			c:Advance(0.3)
			expect(
				c:HasText(
					string.format(
						"HP grade chances: S %s · A %s · B %s · C %s · D %s",
						chanceText(odds.S),
						chanceText(odds.A),
						chanceText(odds.B),
						chanceText(odds.C),
						chanceText(odds.D)
					)
				)
			).toBe(true)
			local title = labelWith(c, screen:FindFirstChild("Genes", true), "Genes")
			c:Click(title:FindFirstChild("Tap"))
			c:Advance(0.3)
			expect(c:HasText("each gene has a 9% chance to surge higher")).toBe(true)

			-- The preview still fits its card above the footer (the mock does not lay out lists,
			-- so this sums the rows the way UIListLayout would).
			local preview = screen:FindFirstChild("Preview", true)
			local content = cell:FindFirstAncestorWhichIsA("Frame")
			while content and content.Parent ~= preview do
				content = content.Parent
			end
			local used, rows = 0, 0
			for _, child in content:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					used += child.Size.Y.Offset
					rows += 1
				end
			end
			used += content:FindFirstChildOfClass("UIListLayout").Padding.Offset * (rows - 1) + 10
			local cardHeight = 520 - 58 - 32 - 70
			expect(used).toBeAtMost(cardHeight - 64)
			expectClean(c)
		end)

		it("sets a target with the chip, shows the pair's chance and sorts parents best first", function()
			local h, p, M = barn()
			local weak = adult(M, p, { genes = uniform(1, 2) })
			local strong = adult(M, p, { line = "mossbun", genes = uniform(8, 9) })
			local mid = adult(M, p, { line = "zappip", genes = uniform(5, 6) })
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Breeding")
			c:Advance(0.5)
			c:Click(clickable(screen:FindFirstChild("TargetChip", true)))
			c:Advance(0.5)
			expect(c:HasText("Breeding target")).toBe(true)
			c:Click(clickable(c.playerGui:FindFirstChild("Stat_atk", true)))
			c:Advance(0.2)
			c:Click(clickable(c.playerGui:FindFirstChild("Grade_A", true)))
			c:Advance(1)
			expect(h:Section(p, "Breeding").target).toEqual({ stat = "atk", grade = "A" })
			expect(c:HasText("Target: ATK A or better", screen)).toBe(true)

			-- No partner yet: the picker ranks by the candidates' own ATK points.
			c:Click(clickable(screen:FindFirstChild("ParentA", true)))
			c:Advance(0.5)
			local picker = c:Screen("Monsters")
			expect(c:HasText("best for target first", picker)).toBe(true)
			local function order(m)
				return picker:FindFirstChild(m.id, true).LayoutOrder
			end
			expect(order(strong)).toBeLessThan(order(mid))
			expect(order(mid)).toBeLessThan(order(weak))
			c:Click(picker:FindFirstChild(weak.id, true):FindFirstChild("Tap"))
			c:Advance(1)

			-- With weak chosen, B's candidates rank by the pair's chance of ATK A or better.
			c:Click(clickable(screen:FindFirstChild("ParentB", true)))
			c:Advance(0.5)
			picker = c:Screen("Monsters")
			expect(order(strong)).toBeLessThan(order(mid))
			c:Click(picker:FindFirstChild(strong.id, true):FindFirstChild("Tap"))
			c:Advance(1)
			local chance = Genetics.AtLeast(Genetics.GradeOdds(weak.genes, strong.genes, "atk"), "A")
			expect(c:HasText(string.format("Chance with this pair: %s", chanceText(chance)), screen)).toBe(true)
			local atk = screen:FindFirstChild("Plan_atk", true)
			expect(atk:FindFirstChild("Chance").Text).toBe(chanceText(chance))
			expect(atk:FindFirstChildOfClass("UIStroke") ~= nil).toBe(true) -- the target's stat is outlined

			-- Clearing goes back to B or better.
			c:Click(clickable(screen:FindFirstChild("TargetChip", true)))
			c:Advance(0.5)
			c:Click(c:Button("Clear target"))
			c:Advance(1)
			expect(h:Section(p, "Breeding").target).toBe(false)
			expect(c:HasText("Set a target", screen)).toBe(true)
			expect(c:HasText("Stats show the chance of B or better", screen)).toBe(true)
			expectClean(c)
		end)
	end)

	describe("In Spanish", function()
		it("translates the family tree and the planner", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 12)
			local baby = family(h, p)
			h:Call(p, "Breeding.SetTarget", { stat = "luck", grade = "S" })
			local c = ClientHarness.new(h, p, { localeId = "es-mx" })
			c:Advance(1)
			local detail, tree = openTree(c, baby.id)
			expect(c:HasText("Árbol familiar", detail)).toBe(true)
			expect(c:HasText("Grados: PV · ATQ · DEF · VEL · Suerte", tree)).toBe(true)
			expect(c:HasText("Eclosionado", tree:FindFirstChild("Node_ba"))).toBe(true)
			c:Close("MonsterDetail")
			c:Advance(0.5)
			local screen = c:Open("Breeding")
			c:Advance(0.5)
			expect(c:HasText("Objetivo: Suerte S o mejor", screen)).toBe(true)
			expectClean(c)
		end)
	end)
end
